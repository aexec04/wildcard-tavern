--[[
	Invites.lua
	Game invites (Roblox SocialService) and their rewards. Pure Lua, no Roblox APIs; the server decides everything.

	How an invitee is recognised: the client sends the invite with LaunchData "inv:<inviter userId>"
	(Invites.launchData), and the server reads the joining player's join data (Invites.inviterFromJoinData accepts
	that LaunchData or Roblox's own ReferredByPlayerId).

	Rewards, each granted ONCE:
	  * inviter  +INVITER_TIPS Tips on the next run (profile.pendingStartTips, capped like quests) and progress to
	    the titles Welcoming Host (3 invites) and Tavern Ambassador (10), see Engine/Achievements.
	  * invitee  one starter card back (INVITEE_CARD_BACK) the first time they arrive through an invite.

	Profile fields (all cleaned on load by cleanSaved):
	  invitesAccepted     count of distinct invitees credited
	  inviteLedger        { [tostring(inviteeUserId)] = true }, at most LEDGER_CAP entries (the idempotency record)
	  invitedByUserId     who invited this player (set once, never changed)
	  inviteeRewardClaimed  the starter card back was granted
	Nothing here ever blocks gameplay; the server wraps every call in pcall.
]]

local TavernRank = require(script.Parent.TavernRank)

local Invites = {}

Invites.INVITER_TIPS = 3
Invites.INVITEE_CARD_BACK = "hall_banner"
Invites.LEDGER_CAP = 200
Invites.Titles = {
	{ id = "welcoming_host", need = 3 },
	{ id = "tavern_ambassador", need = 10 },
}

local function validId(n)
	return type(n) == "number" and n == n and n >= 1 and n <= 1e15 and n == math.floor(n)
end

-- The LaunchData string the client puts on an invite.
function Invites.launchData(inviterUserId)
	if not validId(inviterUserId) then
		return nil
	end
	return "inv:" .. string.format("%d", inviterUserId)
end

-- The inviter's user id from a player's join data ({ LaunchData = string?, ReferredByPlayerId = number? }), or nil.
function Invites.inviterFromJoinData(joinData)
	if type(joinData) ~= "table" then
		return nil
	end
	if type(joinData.LaunchData) == "string" then
		local digits = joinData.LaunchData:match("^inv:(%d+)$")
		local id = digits and #digits <= 15 and tonumber(digits)
		if id and validId(id) then
			return id
		end
	end
	if validId(joinData.ReferredByPlayerId) then
		return joinData.ReferredByPlayerId
	end
	return nil
end

local function ledgerCount(ledger)
	local n = 0
	for _ in pairs(ledger) do n = n + 1 end
	return n
end

-- Credits the inviter's profile for one invitee. Idempotent per invitee; refuses self invites and junk ids.
-- Returns true when something was granted, plus the list of title ids newly reached.
function Invites.creditInviter(profile, inviterUserId, inviteeUserId)
	if not validId(inviteeUserId) or not validId(inviterUserId) or inviteeUserId == inviterUserId then
		return false, {}
	end
	profile.inviteLedger = profile.inviteLedger or {}
	local key = string.format("%d", inviteeUserId)
	if profile.inviteLedger[key] or ledgerCount(profile.inviteLedger) >= Invites.LEDGER_CAP then
		return false, {}
	end
	local before = profile.invitesAccepted or 0
	profile.inviteLedger[key] = true
	profile.invitesAccepted = before + 1
	profile.pendingStartTips = math.min(TavernRank.MAX_PENDING_TIPS, (profile.pendingStartTips or 0) + Invites.INVITER_TIPS)
	local reached = {}
	for _, t in ipairs(Invites.Titles) do
		if before < t.need and profile.invitesAccepted >= t.need then
			reached[#reached + 1] = t.id
		end
	end
	return true, reached
end

-- A player arrived through an invite. Only a brand new player (no run started yet) with no earlier inviter counts.
-- Grants the starter card back once. Returns true when this arrival counts (the inviter may now be credited).
function Invites.acceptInvite(profile, selfUserId, inviterUserId)
	if not validId(selfUserId) or not validId(inviterUserId) or selfUserId == inviterUserId then
		return false
	end
	if profile.invitedByUserId ~= nil or ((profile.stats and profile.stats.runsStarted) or 0) > 0 then
		return false
	end
	profile.invitedByUserId = inviterUserId
	if not profile.inviteeRewardClaimed then
		profile.inviteeRewardClaimed = true
		profile.unlockedCardBackIds = profile.unlockedCardBackIds or {}
		profile.unlockedCardBackIds[Invites.INVITEE_CARD_BACK] = true
	end
	return true
end

-- Cleans the saved invite fields into the profile (junk dropped, ledger capped).
function Invites.cleanSaved(profile, raw)
	profile.invitesAccepted, profile.inviteLedger, profile.invitedByUserId, profile.inviteeRewardClaimed = 0, {}, nil, false
	if type(raw.inviteLedger) == "table" then
		local n = 0
		for k, v in pairs(raw.inviteLedger) do
			if type(k) == "string" and k:match("^%d+$") and #k <= 15 and v == true and n < Invites.LEDGER_CAP then
				profile.inviteLedger[k] = true
				n = n + 1
			end
		end
	end
	-- the count can never be lower than the ledger, and never absurd
	local saved = type(raw.invitesAccepted) == "number" and raw.invitesAccepted == raw.invitesAccepted and math.floor(raw.invitesAccepted) or 0
	profile.invitesAccepted = math.max(math.min(saved, 100000), ledgerCount(profile.inviteLedger))
	if validId(raw.invitedByUserId) then
		profile.invitedByUserId = raw.invitedByUserId
	end
	profile.inviteeRewardClaimed = raw.inviteeRewardClaimed == true
end

-- The inbox of an offline inviter: a list of invitee ids waiting to be credited (deduplicated, capped).
function Invites.inboxAdd(list, inviteeUserId)
	list = type(list) == "table" and list or {}
	if not validId(inviteeUserId) then
		return list
	end
	for _, id in ipairs(list) do
		if id == inviteeUserId then
			return list
		end
	end
	if #list < Invites.LEDGER_CAP then
		list[#list + 1] = inviteeUserId
	end
	return list
end

-- Applies an inbox to a profile; returns how many were newly credited and the title ids reached.
function Invites.drainInbox(profile, inviterUserId, list)
	local credited, titles = 0, {}
	for _, inviteeId in ipairs(type(list) == "table" and list or {}) do
		local ok, reached = Invites.creditInviter(profile, inviterUserId, inviteeId)
		if ok then
			credited = credited + 1
			for _, t in ipairs(reached) do titles[#titles + 1] = t end
		end
	end
	return credited, titles
end

return Invites
