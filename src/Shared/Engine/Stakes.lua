--[[
	Stakes.lua
	The difficulty ladder. Eight named stakes; each one adds exactly ONE rule on top of every lower stake.
	Stake 1 (Regular) is today's game. A player starts with Regular open and unlocks stake N+1 by winning a
	standard run on stake N. Winning also stamps every road (region) the run walked with the highest stake won.

	Pure Lua, no Roblox APIs. Stake rules are plain numbers read by RunState:
		discardsDelta       added to the discards of every round (Night 1 onboarding bonus still applies)
		bossTargetPct       percent added to Boss Round targets
		rerollExtra         added to the shop reroll price
		noInterest          no interest on held Tips at round end
		recipeSlotDelta     added to the recipe box size
		tipsPerRoundDelta   added to the flat Tips paid for clearing a round (Boss Round double included)
		tipsNonBossDelta    added to the Tips paid for clearing a NON-boss round only (Closing Time)
		bossExtraDiscards   added to the discards of Boss Rounds only (a second small debuff)

	Daily, Weekly, Seed, revived and tutorial runs always use stake 1 so shared boards stay fair.
]]

local Stakes = {}

Stakes.MIN = 1
Stakes.MAX = 8

-- `rule` is what this stake adds; `hint` is the one-line player text.
Stakes.Definitions = {
	{ id = "regular", name = "Regular", icon = "🍞", hint = "The tavern as it is.", rule = {} },
	{ id = "busy_night", name = "Busy Night", icon = "🕯️", hint = "One fewer discard each round.", rule = { discardsDelta = -1 } },
	{ id = "rowdy_crowd", name = "Rowdy Crowd", icon = "🎻", hint = "Boss targets are 10% higher.", rule = { bossTargetPct = 10 } },
	{ id = "rush_hour", name = "Rush Hour", icon = "⏱️", hint = "Rerolls cost 1 more. Boss targets rise 9%.", rule = { rerollExtra = 1, bossTargetPct = 9 } },
	{ id = "final_bell", name = "Final Bell", icon = "🔔", hint = "No interest on your Tips.", rule = { noInterest = true } },
	{ id = "packed_house", name = "Packed House", icon = "🪑", hint = "Recipe box holds 1 less. Boss targets rise 5%.", rule = { recipeSlotDelta = -1, bossTargetPct = 5 } },
	{ id = "closing_time", name = "Closing Time", icon = "🌙", hint = "Rounds pay 1 less Tip, except Boss Rounds.", rule = { tipsNonBossDelta = -1 } },
	{ id = "legend", name = "Legend", icon = "👑", hint = "Boss rounds give 1 fewer discard.", rule = { bossExtraDiscards = -1 } },
}

-- RULE BAN tokens a normal run starts with (Engine/BossCounters, RunState.useRuleBan): 1 on stakes 1 to 4, none above.
-- One more is earned by clearing the Night 4 boss. Boss counterplay only, never changes Daily, Weekly or Seed runs.
Stakes.RuleBansAtStart = { 1, 1, 1, 1, 0, 0, 0, 0 }
Stakes.RULE_BAN_BONUS_NIGHT = 4

-- Clamps anything (nil, junk, floats) to a whole stake number from MIN to MAX.
function Stakes.clamp(n)
	if type(n) ~= "number" or n ~= n then
		return Stakes.MIN
	end
	return math.max(Stakes.MIN, math.min(Stakes.MAX, math.floor(n)))
end

function Stakes.ruleBansFor(n)
	return Stakes.RuleBansAtStart[Stakes.clamp(n)] or 0
end

function Stakes.get(n)
	return Stakes.Definitions[Stakes.clamp(n)]
end

-- The combined rules of stake `n`: every number summed over stakes 1..n, flags OR-ed.
function Stakes.rulesFor(n)
	n = Stakes.clamp(n)
	local rules = {
		discardsDelta = 0,
		bossTargetPct = 0,
		rerollExtra = 0,
		noInterest = false,
		recipeSlotDelta = 0,
		tipsPerRoundDelta = 0,
		tipsNonBossDelta = 0,
		bossExtraDiscards = 0,
	}
	for i = 1, n do
		for key, value in pairs(Stakes.Definitions[i].rule) do
			if type(value) == "boolean" then
				rules[key] = rules[key] or value
			else
				rules[key] = (rules[key] or 0) + value
			end
		end
	end
	return rules
end

-- Highest stake a profile may start (1 for a missing or junk value).
function Stakes.highestUnlocked(profile)
	return Stakes.clamp(profile and profile.highestStakeUnlocked)
end

function Stakes.isUnlocked(profile, n)
	return type(n) == "number" and n == math.floor(n) and n >= Stakes.MIN and n <= Stakes.highestUnlocked(profile)
end

-- The stake a start request really gets: the asked-for one if the profile has it open, otherwise stake 1.
-- Seeded and tutorial runs pass `forceRegular`.
function Stakes.resolveStart(profile, asked, forceRegular)
	if forceRegular or not Stakes.isUnlocked(profile, asked) then
		return Stakes.MIN
	end
	return asked
end

-- Hint shown on a locked tier.
function Stakes.unlockHint(n)
	n = Stakes.clamp(n)
	if n <= Stakes.MIN then
		return ""
	end
	return "Win a run on " .. Stakes.Definitions[n - 1].name .. "."
end

-- Records a won standard run on `stake` that walked `regions` (array of region ids, repeats fine).
-- Unlocks stake+1 and stamps each region with the highest stake won. Returns true when anything changed.
function Stakes.recordWin(profile, stake, regions)
	stake = Stakes.clamp(stake)
	local changed = false
	if stake >= Stakes.highestUnlocked(profile) and stake < Stakes.MAX then
		profile.highestStakeUnlocked = stake + 1
		changed = true
	elseif profile.highestStakeUnlocked == nil then
		profile.highestStakeUnlocked = Stakes.highestUnlocked(profile)
	end
	profile.stakeStamps = profile.stakeStamps or {}
	for _, region in ipairs(regions or {}) do
		if type(region) == "string" and (profile.stakeStamps[region] or 0) < stake then
			profile.stakeStamps[region] = stake
			changed = true
		end
	end
	return changed
end

-- Highest stake won on a region (0 = no stamp).
function Stakes.stampOf(profile, region)
	local stamps = profile and profile.stakeStamps
	return (stamps and stamps[region]) or 0
end

-- Cleans a raw saved value into { highestStakeUnlocked, stakeStamps } fields (junk dropped).
function Stakes.cleanSaved(rawHighest, rawStamps, isRegion)
	local stamps = {}
	if type(rawStamps) == "table" then
		for region, stake in pairs(rawStamps) do
			if type(region) == "string" and (not isRegion or isRegion(region))
				and type(stake) == "number" and stake == stake and stake >= Stakes.MIN then
				stamps[region] = Stakes.clamp(stake)
			end
		end
	end
	return Stakes.clamp(rawHighest), stamps
end

return Stakes
