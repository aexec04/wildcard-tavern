--[[
	Legend.lua
	LEGEND PRESTIGE: a reason to keep playing after stake 8. Clearing stake 8 on a standard run earns Legend points: 1 for
	every clear plus 1 bonus the first time a road (region) is cleared on stake 8, so new roads level you faster than
	repeating one. Legend level = points, capped at MAX_LEVEL (10). Every level gives one permanent cosmetic reward from the
	Rewards table below, nothing with gameplay power. Pure Lua, no Roblox APIs.

	Profile fields (cleaned on load):
	  legendPoints      whole number, 0 to 999
	  legendRoads       { [region id] = true } roads already cleared on stake 8 (the new-road bonus is paid once each)
	  legendRewardIds   { [level] = true } rewards already granted (granted once, safe to call again)
	The level is always derived from the points, never saved on its own.

	Reward kinds: title (Achievements id, milestone title), cardBack (CardBacks id), aura (a gold ring around your name
	medallion), trinket (a small table ornament shown in the Legend panel). Daily, Weekly, Seed, challenge and Quick runs
	never count (the server only calls recordClear for a standard stake 8 clear).
]]

local Stakes = require(script.Parent.Stakes)

local Legend = {}

Legend.MAX_LEVEL = 10
Legend.MAX_POINTS = 999
Legend.UNLOCK_STAKE = Stakes.MAX -- clear stake 8 to start

-- EDIT ME: level -> reward. New registry entries used: 3 titles (Achievements) and 3 card backs (CardBacks).
Legend.Rewards = {
	[1] = { kind = "title", id = "legend_1", name = "Legend" },
	[2] = { kind = "aura", id = "gold_aura", name = "Gold name aura", icon = "✨" },
	[3] = { kind = "cardBack", id = "legend_gold", name = "Legend Gold card back" },
	[4] = { kind = "trinket", id = "gold_cup", name = "Gold Cup", icon = "🏆" },
	[5] = { kind = "title", id = "legend_5", name = "Living Legend" },
	[6] = { kind = "trinket", id = "eternal_candle", name = "Eternal Candle", icon = "🕯️" },
	[7] = { kind = "cardBack", id = "legend_crown", name = "Legend Crown card back" },
	[8] = { kind = "trinket", id = "keepers_key", name = "Keeper's Key", icon = "🗝️" },
	[9] = { kind = "title", id = "legend_9", name = "Legend of Legends" },
	[10] = { kind = "cardBack", id = "legend_eternal", name = "Eternal Legend card back" },
}

function Legend.levelFor(points)
	points = math.floor(tonumber(points) or 0)
	return math.max(0, math.min(Legend.MAX_LEVEL, points))
end

function Legend.level(profile)
	return Legend.levelFor(profile and profile.legendPoints)
end

-- Legend is open once stake 8 has been cleared (that clear is the first point).
function Legend.isOpen(profile)
	return Legend.level(profile) >= 1
end

local function grant(profile, reward)
	if reward.kind == "title" then
		profile.rewardTitleIds = profile.rewardTitleIds or {}
		profile.rewardTitleIds[reward.id] = true
	elseif reward.kind == "cardBack" then
		profile.unlockedCardBackIds = profile.unlockedCardBackIds or {}
		profile.unlockedCardBackIds[reward.id] = true
	end
	-- aura and trinket are read straight from the level (Legend.hasAura, Legend.trinkets): nothing to store
end

-- Grants every reward up to the profile's level that was not granted yet. Returns the list of { level, reward } granted now.
function Legend.grantDue(profile)
	profile.legendRewardIds = profile.legendRewardIds or {}
	local granted = {}
	for level = 1, Legend.level(profile) do
		local reward = Legend.Rewards[level]
		if reward and not profile.legendRewardIds[level] then
			profile.legendRewardIds[level] = true
			grant(profile, reward)
			granted[#granted + 1] = { level = level, reward = reward }
		end
	end
	return granted
end

-- A standard stake 8 clear that walked `regions` (array of region ids, repeats fine). Adds 1 point, plus 1 for each road
-- never cleared on stake 8 before, then grants any rewards that became due. Returns { points, levelBefore, levelAfter, granted }.
function Legend.recordClear(profile, regions)
	local before = Legend.level(profile)
	profile.legendRoads = profile.legendRoads or {}
	local gained = 1
	for _, region in ipairs(regions or {}) do
		if type(region) == "string" and not profile.legendRoads[region] then
			profile.legendRoads[region] = true
			gained = gained + 1
		end
	end
	profile.legendPoints = math.min(Legend.MAX_POINTS, math.floor(tonumber(profile.legendPoints) or 0) + gained)
	local granted = Legend.grantDue(profile)
	return { points = gained, levelBefore = before, levelAfter = Legend.level(profile), granted = granted }
end

function Legend.hasAura(profile)
	return Legend.level(profile) >= 2
end

-- The trinkets earned so far, in level order: { { level, id, name, icon } }.
function Legend.trinkets(profile)
	local out = {}
	for level = 1, Legend.level(profile) do
		local r = Legend.Rewards[level]
		if r and r.kind == "trinket" then
			out[#out + 1] = { level = level, id = r.id, name = r.name, icon = r.icon }
		end
	end
	return out
end

-- Short reward text. `lookup` (optional) = { titleName = fn(id), cardBackName = fn(id) }.
function Legend.rewardText(reward, lookup)
	lookup = lookup or {}
	if reward.kind == "title" then
		return "Title: " .. ((lookup.titleName and lookup.titleName(reward.id)) or reward.name)
	elseif reward.kind == "cardBack" then
		return "Card back: " .. ((lookup.cardBackName and lookup.cardBackName(reward.id)) or reward.name)
	elseif reward.kind == "aura" then
		return "Gold aura on your name"
	end
	return "Table trinket: " .. (reward.name or reward.id)
end

-- What the client draws.
function Legend.view(profile, lookup)
	local level = Legend.level(profile)
	local rows = {}
	for l = 1, Legend.MAX_LEVEL do
		local r = Legend.Rewards[l]
		rows[l] = { level = l, kind = r.kind, id = r.id, icon = r.icon, text = Legend.rewardText(r, lookup), reached = l <= level }
	end
	local locked = (profile and profile.highestStakeUnlocked or 1) < Legend.UNLOCK_STAKE and level == 0
	return {
		level = level, max = Legend.MAX_LEVEL, points = math.floor(tonumber(profile and profile.legendPoints) or 0),
		open = level >= 1, locked = locked, aura = level >= 2, rewards = rows,
		hint = level >= Legend.MAX_LEVEL and "Every Legend reward is yours."
			or "Clear stake 8 again, or on a road you have not cleared on stake 8, to level up.",
	}
end

-- Cleans saved values: junk dropped, rewards re-derived from the level on the next grantDue.
function Legend.cleanSaved(rawPoints, rawRoads, rawRewardIds, isRegion)
	local points = 0
	if type(rawPoints) == "number" and rawPoints == rawPoints and rawPoints ~= math.huge and rawPoints ~= -math.huge then
		points = math.max(0, math.min(Legend.MAX_POINTS, math.floor(rawPoints)))
	end
	local roads, rewards = {}, {}
	if type(rawRoads) == "table" then
		for region, flag in pairs(rawRoads) do
			if flag == true and type(region) == "string" and (not isRegion or isRegion(region)) then
				roads[region] = true
			end
		end
	end
	if type(rawRewardIds) == "table" then
		for level, flag in pairs(rawRewardIds) do
			if flag == true and type(level) == "number" and level == math.floor(level) and Legend.Rewards[level] then
				rewards[level] = true
			end
		end
	end
	return points, roads, rewards
end

return Legend
