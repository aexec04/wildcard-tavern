--[[
	NightStar.lua
	The best scoring card or Patron of the Night, for the Night clear toast ("Star of the Night: Gilded King of Hearts"). Pure Lua, no
	Roblox APIs, no tween. The run state keeps one small record, state.nightStar = { night, name, value }, replaced when a bigger
	single contribution scores in the same Night or when a new Night starts.

	NightStar.record(state, breakdown, chips, mult)   call once per played hand with the scoring breakdown (Scoring.calculate's extra.breakdown)
	NightStar.line(star)                              -> "Star of the Night: <name>" of 60 characters or less, or nil for no star
]]

local Card = require(script.Parent.Card)

local NightStar = {}

NightStar.MAX_LENGTH = 60
NightStar.PREFIX = "Star of the Night: "

local function num(n)
	n = tonumber(n) or 0
	if n ~= n or n == math.huge or n == -math.huge then return 0 end
	return n
end

-- how much one breakdown entry added to the hand's score, as one comparable number (chips add chips x mult, mult adds mult x chips,
-- a multiplier adds (x - 1) x chips x mult)
local function worth(entry, chips, mult)
	local a = num(entry.amount)
	if entry.kind == "chips" then return a * mult end
	if entry.kind == "mult" then return a * chips end
	if entry.kind == "xmult" then return math.max(0, a - 1) * chips * mult end
	return 0
end

local function nameOf(entry)
	local src = entry.source or {}
	if src.type == "patron" then
		return type(entry.label) == "string" and (entry.label:gsub("'s Special$", "")) or nil
	end
	if (src.type == "card" or src.type == "heldCard") and type(src.card) == "table" and src.card.rank then
		local text = Card.toString(src.card)
		local mk = src.card.mark and Card.Marks[src.card.mark]
		return mk and (mk.name .. " " .. text) or text
	end
	return nil
end

function NightStar.record(state, breakdown, chips, mult)
	if type(state) ~= "table" or type(breakdown) ~= "table" then return end
	chips, mult = num(chips), num(mult)
	local night = math.floor(num(state.night))
	local best = state.nightStar
	if type(best) ~= "table" or best.night ~= night then best = nil end
	local bestValue = best and num(best.value) or 0
	local bestName = best and best.name or nil
	for _, entry in ipairs(breakdown) do
		local name = nameOf(entry)
		if name then
			local v = worth(entry, chips, mult)
			if v > bestValue then bestValue, bestName = v, name end
		end
	end
	if bestName then
		state.nightStar = { night = night, name = bestName, value = bestValue }
	end
end

function NightStar.line(star)
	if type(star) ~= "table" or type(star.name) ~= "string" or star.name == "" then return nil end
	local room = NightStar.MAX_LENGTH - #NightStar.PREFIX
	local name = star.name
	if #name > room then name = name:sub(1, room - 3) .. "..." end
	return NightStar.PREFIX .. name
end

return NightStar
