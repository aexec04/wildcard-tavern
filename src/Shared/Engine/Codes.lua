--[[
	Codes.lua
	Redeem codes as DATA (the Codes box in the Menu). Pure Lua, no Roblox APIs; the server calls Codes.redeem and the
	client only sends the typed text. Rewards are small and never pay to win: Tips banked for the next run (capped like
	every other source), a card back that already exists, or a title.

	TO ADD A CODE: append one entry to Codes.Definitions (UPPERCASE letters and digits, 3 to 20 characters). Optional
	`expires = "YYYY-MM-DD"` (UTC, that day still works). A test checks the ids, dates and reward ids.

	Codes.redeem(profile, text, nowSeconds, state) -> ok, status, message
	  status: "redeemed" | "used" | "invalid" | "expired" | "slow"
	  state: a per-player table owned by the server (holds the last try time for the one-try-per-second limit)
]]

local TavernRank = require(script.Parent.TavernRank)

local Codes = {}

Codes.MIN_SECONDS_BETWEEN_TRIES = 1
Codes.MAX_LENGTH = 20
Codes.MIN_LENGTH = 3

-- EDIT ME. Amounts stay at or under TavernRank.MAX_PENDING_TIPS (the bank cap shared by every Tips source).
Codes.Definitions = {
	{ id = "LAUNCH", blurb = "Launch gift", rewards = { { kind = "tips", amount = 30 }, { kind = "cardBack", id = "kitchen_checks" } } },
	{ id = "KNAVE", blurb = "Knave's gift", rewards = { { kind = "cardBack", id = "hall_banner" } } },
	{ id = "FAVORITE", blurb = "Thanks for the favorite", rewards = { { kind = "tips", amount = 20 } } },
}

local BY_ID = {}
for _, def in ipairs(Codes.Definitions) do
	BY_ID[def.id] = def
end

Codes.MESSAGES = {
	redeemed = "Redeemed!",
	used = "Already used.",
	invalid = "Not a valid code.",
	expired = "Expired.",
	slow = "One try per second, please.",
}

-- Days since 1970-01-01 for a UTC civil date (the standard days-from-civil count).
local function civilDay(y, m, d)
	y = m <= 2 and y - 1 or y
	local era = math.floor(y / 400)
	local yoe = y - era * 400
	local doy = math.floor((153 * (m + (m > 2 and -3 or 9)) + 2) / 5) + d - 1
	local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
	return era * 146097 + doe - 719468
end

local function expiryDay(def)
	if type(def.expires) ~= "string" then
		return nil
	end
	local y, m, d = def.expires:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
	if not y then
		return nil
	end
	return civilDay(tonumber(y), tonumber(m), tonumber(d))
end

-- Uppercase, trims spaces, letters and digits only. Returns the clean code or nil.
function Codes.normalize(text)
	if type(text) ~= "string" or #text > 64 then
		return nil
	end
	local clean = text:gsub("^%s+", ""):gsub("%s+$", ""):upper()
	if #clean < Codes.MIN_LENGTH or #clean > Codes.MAX_LENGTH or clean:find("[^A-Z0-9]") then
		return nil
	end
	return clean
end

function Codes.getById(id)
	return BY_ID[id]
end

function Codes.isExpired(def, day)
	local last = expiryDay(def)
	return last ~= nil and day > last
end

local function addTips(profile, amount)
	profile.pendingStartTips = math.min(TavernRank.MAX_PENDING_TIPS, (profile.pendingStartTips or 0) + amount)
end

local function grant(profile, reward)
	if reward.kind == "tips" then
		addTips(profile, reward.amount)
	elseif reward.kind == "cardBack" then
		profile.unlockedCardBackIds = type(profile.unlockedCardBackIds) == "table" and profile.unlockedCardBackIds or {}
		profile.unlockedCardBackIds[reward.id] = true
	elseif reward.kind == "title" then
		profile.rewardTitleIds = type(profile.rewardTitleIds) == "table" and profile.rewardTitleIds or {}
		profile.rewardTitleIds[reward.id] = true
	end
end

local function result(ok, status)
	return ok, status, Codes.MESSAGES[status]
end

function Codes.redeem(profile, text, now, state)
	now = type(now) == "number" and now or 0
	if type(state) == "table" then
		local last = state.lastTry
		if last and now - last < Codes.MIN_SECONDS_BETWEEN_TRIES then
			return result(false, "slow")
		end
		state.lastTry = now
	end
	local code = Codes.normalize(text)
	local def = code and BY_ID[code]
	if not def then
		return result(false, "invalid")
	end
	if Codes.isExpired(def, math.floor(now / 86400)) then
		return result(false, "expired")
	end
	profile.redeemedCodes = type(profile.redeemedCodes) == "table" and profile.redeemedCodes or {}
	if profile.redeemedCodes[def.id] then
		return result(false, "used")
	end
	for _, reward in ipairs(def.rewards) do
		grant(profile, reward)
	end
	profile.redeemedCodes[def.id] = true
	return result(true, "redeemed")
end

-- Short reward line for the success toast, e.g. "+30 Tips next run, Card back: Meadow Checks".
function Codes.rewardText(def, cardBackName)
	local parts = {}
	for _, reward in ipairs(def.rewards) do
		if reward.kind == "tips" then
			parts[#parts + 1] = "+" .. tostring(reward.amount) .. " Tips next run"
		elseif reward.kind == "cardBack" then
			parts[#parts + 1] = "Card back: " .. ((cardBackName and cardBackName(reward.id)) or reward.id)
		elseif reward.kind == "title" then
			parts[#parts + 1] = "Title unlocked"
		end
	end
	return table.concat(parts, ", ")
end

-- Save cleaning: only known code ids survive (a removed code is dropped, a bad value is ignored).
function Codes.cleanSaved(raw)
	local out = {}
	if type(raw) == "table" then
		for id, flag in pairs(raw) do
			if flag == true and type(id) == "string" and BY_ID[id] then
				out[id] = true
			end
		end
	end
	return out
end

-- Problems with the table (used by a test): list of strings, empty when fine.
function Codes.validate(cardBackExists)
	local problems, seen = {}, {}
	for _, def in ipairs(Codes.Definitions) do
		if Codes.normalize(def.id) ~= def.id then
			problems[#problems + 1] = tostring(def.id) .. ": id must be UPPERCASE letters and digits, 3 to 20"
		end
		if seen[def.id] then
			problems[#problems + 1] = def.id .. ": duplicate id"
		end
		seen[def.id] = true
		if def.expires ~= nil and expiryDay(def) == nil then
			problems[#problems + 1] = def.id .. ": bad expires date"
		end
		if type(def.rewards) ~= "table" or #def.rewards == 0 then
			problems[#problems + 1] = def.id .. ": no rewards"
		else
			for _, reward in ipairs(def.rewards) do
				if reward.kind == "tips" then
					if type(reward.amount) ~= "number" or reward.amount < 1 or reward.amount > TavernRank.MAX_PENDING_TIPS then
						problems[#problems + 1] = def.id .. ": tips amount out of range"
					end
				elseif reward.kind == "cardBack" then
					if cardBackExists and not cardBackExists(reward.id) then
						problems[#problems + 1] = def.id .. ": unknown card back " .. tostring(reward.id)
					end
				elseif reward.kind ~= "title" then
					problems[#problems + 1] = def.id .. ": unknown reward kind"
				end
			end
		end
	end
	return problems
end

return Codes
