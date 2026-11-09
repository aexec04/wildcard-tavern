--[[
	EndlessRules.lua
	Crowd Rules: the escalation after the Night 8 win. Every EVERY Nights beyond the Night cap one more rule joins
	for the rest of the run, in the fixed order of EndlessRules.Rules (so the order is the same every run and
	needs no rng). Each rule is plain numbers that RunState reads (see RunState.startRound and friends):

		handSizeDelta        cards dealt per round
		discardsDelta        discards per round
		handsDelta           hands per round (never below 1)
		bossExtraDiscards    discards in Boss Rounds only
		bossTargetPct        percent added to Boss Round targets
		patronPricePct       percent added to Patron prices
		rerollExtra          added to the shop reroll price
		interestCapDelta     added to the round-win interest cap (never below 0)
		tipsDelta            added to the Tips paid per round won (never below 1)
		recipeSlotDelta      added to the recipe box size

	Only normal runs use them (RunState option `endlessRules`); Daily, Weekly, Seed, Boss Rush and the tutorial
	never do. Targets keep growing with the Night but are clamped at TARGET_CAP so no number can overflow.
	Pure Lua, no Roblox APIs.
]]

local Stakes = require(script.Parent.Stakes)

local EndlessRules = {}

EndlessRules.EVERY = 3
EndlessRules.TARGET_CAP = 9e15 -- below 2^53, so a target is always an exact whole number

EndlessRules.Rules = {
	{ id = "rowdy_bosses", name = "Rowdy Bosses", icon = "🥁", text = "Boss targets are 10% higher.", rule = { bossTargetPct = 10 } },
	{ id = "pricey_patrons", name = "Pricey Patrons", icon = "🏷️", text = "Patrons cost 10% more.", rule = { patronPricePct = 10 } },
	{ id = "costly_rerolls", name = "Costly Rerolls", icon = "🔄", text = "Shop rerolls cost 1 more.", rule = { rerollExtra = 1 } },
	{ id = "thin_interest", name = "Thin Interest", icon = "🪙", text = "Interest on held Tips is capped 3 lower.", rule = { interestCapDelta = -3 } },
	{ id = "second_sting", name = "Second Sting", icon = "🦂", text = "Boss Rounds give 1 fewer Discard.", rule = { bossExtraDiscards = -1 } },
	{ id = "tight_seats", name = "Tight Seats", icon = "💺", text = "Draw 1 fewer card each round.", rule = { handSizeDelta = -1 } },
	{ id = "lean_tips", name = "Lean Tips", icon = "🥣", text = "Rounds pay 1 less Tip.", rule = { tipsDelta = -1 } },
	{ id = "packed_shelf", name = "Packed Shelf", icon = "🗄️", text = "The recipe box holds 1 less.", rule = { recipeSlotDelta = -1 } },
	{ id = "short_rations", name = "Short Rations", icon = "🍞", text = "1 fewer Discard each round.", rule = { discardsDelta = -1 } },
	{ id = "short_shift", name = "Short Shift", icon = "⏳", text = "1 fewer Hand each round.", rule = { handsDelta = -1 } },
}

local FIELDS = {
	"handSizeDelta", "discardsDelta", "handsDelta", "bossExtraDiscards", "bossTargetPct",
	"patronPricePct", "rerollExtra", "interestCapDelta", "tipsDelta", "recipeSlotDelta",
}

-- How many rules are active on `night` (0 until Night cap + EVERY).
function EndlessRules.countFor(night, nightCap)
	if type(night) ~= "number" or night ~= night or night <= nightCap then
		return 0
	end
	return math.min(#EndlessRules.Rules, math.floor((night - nightCap) / EndlessRules.EVERY))
end

-- The active rules, in the order they joined.
function EndlessRules.activeFor(night, nightCap)
	local list = {}
	for i = 1, EndlessRules.countFor(night, nightCap) do
		list[i] = EndlessRules.Rules[i]
	end
	return list
end

-- The rule that joins exactly on this Night, or nil.
function EndlessRules.newAt(night, nightCap)
	if type(night) ~= "number" or night <= nightCap then
		return nil
	end
	local since = night - nightCap
	if since % EndlessRules.EVERY ~= 0 then
		return nil
	end
	return EndlessRules.Rules[since / EndlessRules.EVERY]
end

-- All active numbers summed: { field = total } with every field present.
function EndlessRules.combined(list)
	local sum = {}
	for _, field in ipairs(FIELDS) do
		sum[field] = 0
	end
	for _, entry in ipairs(list or {}) do
		for field, value in pairs(entry.rule) do
			sum[field] = (sum[field] or 0) + value
		end
	end
	return sum
end

function EndlessRules.clampTarget(target)
	if target ~= target then
		return EndlessRules.TARGET_CAP
	end
	return math.min(EndlessRules.TARGET_CAP, target)
end

-- Run Summary personal best card: one line per stake with a recorded Endless Night, the current stake first.
-- `bests` = profile.endlessBestByStake ({ ["3"] = 14 }). Returns a list of strings (empty when none).
function EndlessRules.bestLines(bests, currentStake)
	local lines = {}
	if type(bests) ~= "table" then
		return lines
	end
	local function line(stake)
		local night = bests[tostring(stake)]
		if night then
			lines[#lines + 1] = string.format("%s: Night %d", Stakes.get(stake).name, math.floor(night))
		end
	end
	if currentStake then
		line(currentStake)
	end
	for stake = Stakes.MIN, Stakes.MAX do
		if stake ~= currentStake then
			line(stake)
		end
	end
	return lines
end

return EndlessRules
