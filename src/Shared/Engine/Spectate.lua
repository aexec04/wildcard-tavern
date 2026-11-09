--[[
	Spectate.lua
	Watching a friend's run live, same server only. Pure Lua, no Roblox APIs (the server owns the remotes and calls these).

	Rules (all tested):
	  * a spectator watches one player at a time, never themselves, never twice; at most MAX_SPECTATORS per player;
	  * a player can turn spectators off (setting allowSpectators) or block one player (profile.blockedSpectators);
	  * leaving, stopping or a run ending removes the watcher; a watched player leaving frees every watcher;
	  * spectators can only send a reaction (6 presets, 3 second cooldown), never any game input and never free text;
	  * what spectators receive is ONLY what the watched player can see on their own table: `snapshot` and `handPlayed` below
	    are whitelists, so a deck order, the draw pile, the rng seed, the shop offers or the profile never leave the server.
]]

local Spectate = {}

Spectate.MAX_SPECTATORS = 8
Spectate.REACTION_COOLDOWN = 3 -- seconds per spectator
Spectate.STREAM_INTERVAL = 0.25 -- at most 4 snapshots a second per watched player
Spectate.MAX_BLOCKED = 50

Spectate.Emotes = {
	{ id = "cheer", icon = "🎉", name = "Cheer" },
	{ id = "gasp", icon = "😮", name = "Gasp" },
	{ id = "clap", icon = "👏", name = "Clap" },
	{ id = "fire", icon = "🔥", name = "Fire" },
	{ id = "heart", icon = "❤️", name = "Heart" },
	{ id = "laugh", icon = "😂", name = "Laugh" },
}
local EMOTE_BY_ID = {}
for _, e in ipairs(Spectate.Emotes) do EMOTE_BY_ID[e.id] = e end

function Spectate.emote(id)
	return EMOTE_BY_ID[id]
end

function Spectate.new()
	return { viewing = {}, watchers = {}, lastReact = {}, lastStream = {}, peak = {} }
end

local function validId(n)
	return type(n) == "number" and n == n and n >= 1 and n == math.floor(n) and n <= 1e15
end

function Spectate.count(state, targetId)
	local list = state.watchers[targetId]
	return list and #list or 0
end

function Spectate.watchersOf(state, targetId)
	local out = {}
	for i, id in ipairs(state.watchers[targetId] or {}) do out[i] = id end
	return out
end

function Spectate.watching(state, viewerId)
	return state.viewing[viewerId]
end

-- opts = { allows = bool (the target's allowSpectators), blocked = bool (the target blocked this viewer), inRun = bool (optional) }
function Spectate.canWatch(state, viewerId, targetId, opts)
	opts = opts or {}
	if not validId(viewerId) or not validId(targetId) then
		return false, "Unknown player."
	end
	if viewerId == targetId then
		return false, "You cannot watch yourself."
	end
	if opts.allows == false then
		return false, "That player is not allowing spectators."
	end
	if opts.blocked == true then
		return false, "You cannot watch that player."
	end
	if state.viewing[viewerId] == targetId then
		return false, "Already watching."
	end
	if Spectate.count(state, targetId) >= Spectate.MAX_SPECTATORS then
		return false, "That table is full."
	end
	return true
end

local function removeFrom(list, id)
	for i, v in ipairs(list) do
		if v == id then
			table.remove(list, i)
			return true
		end
	end
	return false
end

-- Starts watching (moving off any earlier target). Returns ok, reason | previous target id.
function Spectate.watch(state, viewerId, targetId, opts)
	local ok, reason = Spectate.canWatch(state, viewerId, targetId, opts)
	if not ok then
		return false, reason
	end
	local previous = Spectate.stop(state, viewerId)
	local list = state.watchers[targetId] or {}
	state.watchers[targetId] = list
	list[#list + 1] = viewerId
	state.viewing[viewerId] = targetId
	state.peak[targetId] = math.max(state.peak[targetId] or 0, #list)
	return true, previous
end

-- Stops watching. Returns the target that was being watched, or nil.
function Spectate.stop(state, viewerId)
	local target = state.viewing[viewerId]
	if target then
		local list = state.watchers[target]
		if list then
			removeFrom(list, viewerId)
			if #list == 0 then state.watchers[target] = nil end
		end
		state.viewing[viewerId] = nil
	end
	return target
end

-- A player left the server: they stop watching, and everyone watching them is released.
-- Returns the list of viewer ids that lost their target.
function Spectate.leave(state, userId)
	Spectate.stop(state, userId)
	local released = Spectate.watchersOf(state, userId)
	for _, viewerId in ipairs(released) do
		state.viewing[viewerId] = nil
	end
	state.watchers[userId] = nil
	state.lastReact[userId] = nil
	state.lastStream[userId] = nil
	return released
end

-- The watched player's run ended: every watcher is released (they can watch the next run again). Returns their ids.
function Spectate.runEnded(state, targetId)
	local released = Spectate.watchersOf(state, targetId)
	for _, viewerId in ipairs(released) do
		state.viewing[viewerId] = nil
	end
	state.watchers[targetId] = nil
	return released
end

-- Removes everyone who watches `targetId` that they now block, or all when spectators were turned off. Returns removed ids.
function Spectate.enforce(state, targetId, allows, isBlocked)
	local removed = {}
	for _, viewerId in ipairs(Spectate.watchersOf(state, targetId)) do
		if allows == false or (isBlocked and isBlocked(viewerId)) then
			Spectate.stop(state, viewerId)
			removed[#removed + 1] = viewerId
		end
	end
	return removed
end

-- The highest number of watchers `targetId` had at once (for the analytics event), and resets it.
function Spectate.takePeak(state, targetId)
	local peak = state.peak[targetId] or 0
	state.peak[targetId] = nil
	return peak
end

-- A reaction from a spectator: valid emote, watching someone, past the cooldown. Returns ok, targetId | reason.
function Spectate.reaction(state, viewerId, emoteId, now)
	local target = state.viewing[viewerId]
	if not target then
		return false, "Not watching anyone."
	end
	if type(emoteId) ~= "string" or not EMOTE_BY_ID[emoteId] then
		return false, "Unknown reaction."
	end
	local last = state.lastReact[viewerId]
	if last and now - last < Spectate.REACTION_COOLDOWN then
		return false, "Too fast."
	end
	state.lastReact[viewerId] = now
	return true, target
end

-- At most one snapshot per STREAM_INTERVAL per watched player. Returns true when it may be sent now.
function Spectate.streamAllowed(state, targetId, now)
	local last = state.lastStream[targetId]
	if last and now - last < Spectate.STREAM_INTERVAL then
		return false
	end
	state.lastStream[targetId] = now
	return true
end

-- ===== blocking and the setting =====

function Spectate.isBlocked(profile, userId)
	return type(profile.blockedSpectators) == "table" and profile.blockedSpectators[tostring(userId)] == true
end

function Spectate.block(profile, userId)
	if not validId(userId) then
		return false
	end
	profile.blockedSpectators = type(profile.blockedSpectators) == "table" and profile.blockedSpectators or {}
	local n = 0
	for _ in pairs(profile.blockedSpectators) do n = n + 1 end
	if n >= Spectate.MAX_BLOCKED and not profile.blockedSpectators[tostring(userId)] then
		return false
	end
	profile.blockedSpectators[tostring(userId)] = true
	return true
end

function Spectate.unblock(profile, userId)
	if type(profile.blockedSpectators) == "table" and profile.blockedSpectators[tostring(userId)] then
		profile.blockedSpectators[tostring(userId)] = nil
		return true
	end
	return false
end

function Spectate.cleanSaved(raw)
	local out, n = {}, 0
	if type(raw) == "table" then
		for k, flag in pairs(raw) do
			if flag == true and type(k) == "string" and k:match("^%d+$") and #k <= 15 and n < Spectate.MAX_BLOCKED then
				out[k] = true
				n = n + 1
			end
		end
	end
	return out
end

-- Does the target's own setting (profile.settings.allowSpectators, default on) allow watching?
function Spectate.allows(profile)
	local settings = profile and profile.settings
	return not (type(settings) == "table" and settings.allowSpectators == false)
end

-- ===== the event stream: whitelists =====

local function pickCards(cards, limit)
	local out = {}
	for i, c in ipairs(type(cards) == "table" and cards or {}) do
		if i > limit then break end
		if type(c) == "table" and type(c.rank) == "number" and type(c.suit) == "string" then
			out[#out + 1] = {
				rank = c.rank, suit = c.suit,
				garnish = type(c.garnish) == "string" and c.garnish or nil,
				special = type(c.special) == "string" and c.special or nil,
				stamp = type(c.stamp) == "string" and c.stamp or nil,
			}
		end
	end
	return out
end

local function str(v, max)
	if type(v) ~= "string" then return nil end
	return v:sub(1, max or 40)
end

local function num(v)
	if type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then return nil end
	return v
end

-- What spectators see of a table: exactly the player's own visible state, nothing else. `input` may contain anything
-- (the server passes fields it already built); only the whitelisted keys below survive.
function Spectate.snapshot(input)
	input = type(input) == "table" and input or {}
	local patrons = {}
	for i, id in ipairs(type(input.patrons) == "table" and input.patrons or {}) do
		if i > 8 then break end
		if type(id) == "string" then patrons[#patrons + 1] = id:sub(1, 40) end
	end
	local boss
	if type(input.boss) == "table" then
		boss = { id = str(input.boss.id), name = str(input.boss.name, 60), text = str(input.boss.text, 120) }
	end
	local flair = {}
	for slot, id in pairs(type(input.flair) == "table" and input.flair or {}) do
		if type(slot) == "string" and type(id) == "string" then flair[slot:sub(1, 20)] = id:sub(1, 40) end
	end
	local selected = {}
	for _, i in ipairs(type(input.selected) == "table" and input.selected or {}) do
		if type(i) == "number" and i >= 1 and i <= 12 and #selected < 5 then selected[#selected + 1] = math.floor(i) end
	end
	return {
		kind = "snapshot",
		name = str(input.name, 30), crest = str(input.crest, 8), badge = str(input.badge, 30),
		stake = num(input.stake), stakeName = str(input.stakeName, 30), road = str(input.road, 40), roadName = str(input.roadName, 40),
		phase = str(input.phase, 20), night = num(input.night), round = num(input.round), tips = num(input.tips),
		targetScore = num(input.targetScore), roundScore = num(input.roundScore),
		handsRemaining = num(input.handsRemaining), discardsRemaining = num(input.discardsRemaining),
		hand = pickCards(input.hand, 12), selected = selected, patrons = patrons, boss = boss, flair = flair,
	}
end

-- The hand just played: the cards, the hand type and the score numbers the player sees.
function Spectate.handPlayed(input)
	input = type(input) == "table" and input or {}
	return {
		kind = "handPlayed", cards = pickCards(input.cards, 5), handName = str(input.handName, 30),
		chips = num(input.chips), mult = num(input.mult), score = num(input.score), legendary = input.legendary == true,
	}
end

function Spectate.roundResult(input)
	input = type(input) == "table" and input or {}
	return { kind = "roundResult", won = input.won == true, night = num(input.night), round = num(input.round), banner = str(input.banner, 60) }
end

function Spectate.reactionEvent(emoteId, fromName)
	local e = EMOTE_BY_ID[emoteId]
	if not e then return nil end
	return { kind = "reaction", emote = e.id, icon = e.icon, from = str(fromName, 30) }
end

Spectate.AllowedKinds = { snapshot = true, handPlayed = true, roundResult = true, reaction = true, ended = true, watchers = true }

-- Every event leaving the server passes through here: unknown kinds are refused, so nothing new can leak by accident.
function Spectate.outgoing(event)
	if type(event) ~= "table" or not Spectate.AllowedKinds[event.kind] then
		return nil
	end
	return event
end

return Spectate
