--[[
	Shared/Engine/BiomeRewards.lua
	Rewards of the branching adventure map (claude/MAP_DESIGN.md section 4). Pure data and helpers.

	Rewards do not change at every stop. Three triggers only:
	  1. Branch end: clearing the LAST Night stop of a biome on your route (the next stop is another biome, or
	     the route ends) grants that biome's `reward` list the first time.
	  2. Region complete: once every Night stop of a biome has been seen over time, its `bonus` is granted;
	     seeing every biome grants `AllRegionsBonus`.
	  3. Keeper win: clearing Night 8 (the tavern biome's branch end) grants the tavern row; the Tavern Keeper
	     title itself is still the Night 8 Journey reward (JourneyMap.recordNightsCleared).

	Reward kinds match JourneyMap: "cardBack", "set", "title" (ids from CardBacks, CosmeticSets, Achievements).
	Granted rows are remembered in profile.worldRewardIds so each is handed out once. Existing Night 1 to 8
	rewards stay with JourneyMap.recordNightsCleared; rows that repeat one of them are harmless (granting is
	idempotent).

	Patrons and recipes are NOT part of the rows yet: adding them changes the shop pool and the balance plan,
	so that waits for a balance pass (see claude/OUTBOX.md, World map step 4).
]]

local WorldMap = require(script.Parent.WorldMap)
local PlayerProfile = require(script.Parent.PlayerProfile)

local BiomeRewards = {}

BiomeRewards.Rows = {
	road = { reward = {} },
	meadow = { reward = { { kind = "cardBack", id = "kitchen_checks" } } },
	river = { reward = { { kind = "title", id = "loft_climber" } } },
	peaks = { reward = { { kind = "set", id = "festival_night" } } },
	desert = { reward = { { kind = "cardBack", id = "dune_gold" } }, bonus = { kind = "title", id = "dune_wanderer" } },
	swamp = { reward = { { kind = "cardBack", id = "lilypad_green" } }, bonus = { kind = "title", id = "marsh_wader" } },
	snow = {
		reward = { { kind = "set", id = "winter_evening" }, { kind = "cardBack", id = "frost_walker" } },
		bonus = { kind = "title", id = "snow_scout" },
	},
	coast = { reward = { { kind = "cardBack", id = "shell_pearl" } }, bonus = { kind = "title", id = "lighthouse_friend" } },
	tavern = { reward = { { kind = "cardBack", id = "gala" }, { kind = "cardBack", id = "hall_banner" } } },
}

BiomeRewards.AllRegionsBonus = { kind = "title", id = "trailblazer" }

local function grant(profile, reward)
	if reward.kind == "cardBack" then
		profile.unlockedCardBackIds[reward.id] = true
	elseif reward.kind == "set" then
		profile.ownedSetIds[reward.id] = true
	elseif reward.kind == "title" then
		profile.rewardTitleIds[reward.id] = true
	end
end

-- Every reward the map can hand out (for tests and previews).
function BiomeRewards.allRewards()
	local out = {}
	for region, row in pairs(BiomeRewards.Rows) do
		for _, r in ipairs(row.reward) do
			out[#out + 1] = { region = region, kind = r.kind, id = r.id }
		end
		if row.bonus then
			out[#out + 1] = { region = region, kind = row.bonus.kind, id = row.bonus.id, bonus = true }
		end
	end
	out[#out + 1] = { region = "all", kind = BiomeRewards.AllRegionsBonus.kind, id = BiomeRewards.AllRegionsBonus.id, bonus = true }
	return out
end

-- Grants a biome's branch-end reward once. Returns the list of rewards newly granted (empty when already done
-- or the region has none).
function BiomeRewards.recordBiomeCleared(profile, region)
	local row = BiomeRewards.Rows[region]
	local fresh = {}
	if not row or #row.reward == 0 then return fresh end
	local key = region
	if profile.worldRewardIds[key] then return fresh end
	profile.worldRewardIds[key] = true
	for _, r in ipairs(row.reward) do
		grant(profile, r)
		fresh[#fresh + 1] = r
	end
	return fresh
end

-- The Night stops of a region (every stop with kind "night" in it).
local function stopsOf(region)
	local ids = {}
	for id, stop in pairs(WorldMap.Stops) do
		if stop.kind == "night" and stop.region == region then
			ids[#ids + 1] = id
		end
	end
	return ids
end

-- Region complete bonuses from the stops seen so far. Returns newly granted rewards.
function BiomeRewards.recordRegionBonuses(profile)
	local fresh = {}
	local allDone = true
	for _, region in ipairs(WorldMap.RegionOrder) do
		local ids = stopsOf(region)
		local complete = #ids > 0
		for _, id in ipairs(ids) do
			if not profile.worldSeenStopIds[id] then
				complete = false
				break
			end
		end
		if #ids > 0 and not complete then allDone = false end
		local row = BiomeRewards.Rows[region]
		local key = region .. ":complete"
		if complete and row and row.bonus and not profile.worldRewardIds[key] then
			profile.worldRewardIds[key] = true
			grant(profile, row.bonus)
			fresh[#fresh + 1] = row.bonus
		end
	end
	if allDone and not profile.worldRewardIds["all:complete"] then
		profile.worldRewardIds["all:complete"] = true
		grant(profile, BiomeRewards.AllRegionsBonus)
		fresh[#fresh + 1] = BiomeRewards.AllRegionsBonus
	end
	return fresh
end

-- COMPASS: spend one charge at a fork to see exactly what waits at the end of each road. Only on Round Select,
-- only while a fork is pending, once per Night. Returns true plus the road ids, or false plus a reason.
function BiomeRewards.useCompass(profile, state, phase)
	if not WorldMap.phaseAllowsRoadChoice(phase) then return false, "wrong_phase" end
	local choices = WorldMap.pendingChoices(state)
	if not choices or #choices < 2 then return false, "no_fork" end
	if state.compassNight == state.night then return false, "already_used" end
	if not PlayerProfile.spendCompassCharge(profile) then return false, "no_charge" end
	state.compassNight = state.night
	return true, choices
end

-- The roads whose rewards the compass revealed this Night (nil when not used).
function BiomeRewards.revealedChoices(state)
	if state and state.compassNight ~= nil and state.compassNight == state.night then
		return WorldMap.pendingChoices(state)
	end
	return nil
end

-- True when route[i] is the last stop of its biome on this road: the Finish, or every road that can follow
-- it (or the stop actually taken) is in another biome.
function BiomeRewards.isBranchEnd(route, i)
	local id = route[i]
	if not id or not WorldMap.Stops[id] then return false end
	if id == WorldMap.Finish then return true end
	local region = WorldMap.regionOf(id)
	if route[i + 1] then
		return WorldMap.regionOf(route[i + 1]) ~= region
	end
	for _, nxt in ipairs(WorldMap.choicesAfter(id)) do
		if WorldMap.regionOf(nxt) == region then
			return false
		end
	end
	return true
end

-- Called with the run's route and how many Nights are cleared. Grants every branch end reached and the region
-- bonuses. Safe to call on every push. Returns the newly granted rewards.
function BiomeRewards.recordProgress(profile, route, cleared)
	local fresh = {}
	if not WorldMap.isValidRoute(route) then return fresh end
	local upTo = math.min(math.floor(cleared or 0), #route)
	for i = 1, upTo do
		if BiomeRewards.isBranchEnd(route, i) then
			for _, r in ipairs(BiomeRewards.recordBiomeCleared(profile, WorldMap.regionOf(route[i]))) do
				fresh[#fresh + 1] = r
			end
		end
	end
	for _, r in ipairs(BiomeRewards.recordRegionBonuses(profile)) do
		fresh[#fresh + 1] = r
	end
	return fresh
end

return BiomeRewards
