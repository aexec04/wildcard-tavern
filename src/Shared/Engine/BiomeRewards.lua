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

	Reward kinds: "cardBack", "set", "title" (ids from CardBacks, CosmeticSets, Achievements) plus "patron" and
	"recipe" (a House Recipe): those two are added to the Collection (profile.discoveredPatronIds /
	discoveredRecipeIds, like the login-streak Bard). They are mild and already sit in the shop pool for every
	run, so no road changes the balance (see the tests in EngineTests, "World map balance").
	Granted rows are remembered in profile.worldRewardIds so each is handed out once. Existing Night 1 to 8
	rewards stay with JourneyMap.recordNightsCleared; rows that repeat one of them are harmless (granting is
	idempotent).

	Every biome row except road and tavern also hands out one Patron and one House Recipe.
]]

local WorldMap = require(script.Parent.WorldMap)
local PlayerProfile = require(script.Parent.PlayerProfile)
local Keys = require(script.Parent.Keys)
local Badges = require(script.Parent.Badges)

local BiomeRewards = {}

BiomeRewards.Rows = {
	road = { reward = {} },
	meadow = { reward = { { kind = "cardBack", id = "kitchen_checks" }, { kind = "patron", id = "meadow_bee" },
		{ kind = "recipe", id = "honey_drizzle" }, { kind = "set", id = "meadow_picnic" }, { kind = "badge", id = "biome_meadow" }, { kind = "title", id = "meadow_walker" } } },
	river = { reward = { { kind = "title", id = "loft_climber" }, { kind = "patron", id = "ferry_captain" },
		{ kind = "recipe", id = "riverside_chowder" }, { kind = "set", id = "riverside_evening" }, { kind = "badge", id = "biome_river" }, { kind = "title", id = "river_crosser" } } },
	peaks = { reward = { { kind = "set", id = "festival_night" }, { kind = "patron", id = "summit_guide" },
		{ kind = "recipe", id = "summit_stew" }, { kind = "set", id = "summit_camp" }, { kind = "badge", id = "biome_peaks" }, { kind = "title", id = "peak_climber" } } },
	desert = {
		reward = { { kind = "cardBack", id = "dune_gold" }, { kind = "patron", id = "sand_merchant" },
			{ kind = "recipe", id = "date_cake" }, { kind = "set", id = "dune_market" }, { kind = "badge", id = "biome_desert" }, { kind = "title", id = "dune_crosser" } },
		bonus = { kind = "title", id = "dune_wanderer" },
	},
	swamp = {
		reward = { { kind = "cardBack", id = "lilypad_green" }, { kind = "patron", id = "marsh_gardener" },
			{ kind = "recipe", id = "bog_stew" }, { kind = "set", id = "marsh_lanterns" }, { kind = "badge", id = "biome_swamp" }, { kind = "title", id = "marsh_strider" } },
		bonus = { kind = "title", id = "marsh_wader" },
	},
	snow = {
		reward = { { kind = "set", id = "winter_evening" }, { kind = "cardBack", id = "frost_walker" },
			{ kind = "patron", id = "lantern_lighter" }, { kind = "recipe", id = "frost_pudding" }, { kind = "set", id = "snowy_hearth" }, { kind = "badge", id = "biome_snow" }, { kind = "title", id = "snow_trekker" } },
		bonus = { kind = "title", id = "snow_scout" },
	},
	coast = {
		reward = { { kind = "cardBack", id = "shell_pearl" }, { kind = "patron", id = "lighthouse_keeper" },
			{ kind = "recipe", id = "sea_biscuit" }, { kind = "set", id = "harbor_lights" }, { kind = "badge", id = "biome_coast" }, { kind = "title", id = "cove_sailor" } },
		bonus = { kind = "title", id = "lighthouse_friend" },
	},
	tavern = { reward = { { kind = "cardBack", id = "gala" }, { kind = "cardBack", id = "hall_banner" }, { kind = "set", id = "tavern_feast" }, { kind = "badge", id = "biome_tavern" }, { kind = "title", id = "tavern_guest" } } },
}

-- Winning a run that travels through a biome upgrades its badge: the gold Master badge and a Master title,
-- granted once per biome (BiomeRewards.recordRunWin).
BiomeRewards.Master = {
	meadow = { { kind = "badge", id = "master_meadow" }, { kind = "title", id = "meadow_master" } },
	river = { { kind = "badge", id = "master_river" }, { kind = "title", id = "river_master" } },
	peaks = { { kind = "badge", id = "master_peaks" }, { kind = "title", id = "peak_master" } },
	desert = { { kind = "badge", id = "master_desert" }, { kind = "title", id = "dune_master" } },
	swamp = { { kind = "badge", id = "master_swamp" }, { kind = "title", id = "marsh_master" } },
	snow = { { kind = "badge", id = "master_snow" }, { kind = "title", id = "snow_master" } },
	coast = { { kind = "badge", id = "master_coast" }, { kind = "title", id = "coast_master" } },
	tavern = { { kind = "badge", id = "master_tavern" }, { kind = "title", id = "tavern_master" } },
}

BiomeRewards.AllRegionsBonus = { kind = "title", id = "trailblazer" }

local function grant(profile, reward)
	if reward.kind == "cardBack" then
		profile.unlockedCardBackIds[reward.id] = true
	elseif reward.kind == "set" then
		profile.ownedSetIds[reward.id] = true
	elseif reward.kind == "title" then
		profile.rewardTitleIds[reward.id] = true
	elseif reward.kind == "badge" then
		Badges.grant(profile, reward.id)
	elseif reward.kind == "patron" then
		profile.discoveredPatronIds = profile.discoveredPatronIds or {}
		profile.discoveredPatronIds[reward.id] = true
	elseif reward.kind == "recipe" then
		profile.discoveredRecipeIds = profile.discoveredRecipeIds or {}
		profile.discoveredRecipeIds[reward.id] = true
	end
end

-- Short display text of one reward ("Card back: Dune Gold", "Patron: Meadow Bee"), for the map and the
-- fork cards. Falls back to the id.
function BiomeRewards.label(reward)
	local Patrons = require(script.Parent.Patrons)
	local Recipes = require(script.Parent.Recipes)
	local CardBacks = require(script.Parent.CardBacks)
	local CosmeticSets = require(script.Parent.CosmeticSets)
	local Achievements = require(script.Parent.Achievements)
	local def, prefix
	if reward.kind == "cardBack" then
		def, prefix = CardBacks.getById(reward.id), "Card back: "
	elseif reward.kind == "set" then
		def, prefix = CosmeticSets.getById(reward.id), "Card set: "
	elseif reward.kind == "title" then
		def, prefix = Achievements.getById(reward.id), "Title: "
	elseif reward.kind == "badge" then
		def, prefix = Badges.getById(reward.id), "Badge: "
	elseif reward.kind == "patron" then
		def, prefix = Patrons.getById(reward.id), "Patron: "
	elseif reward.kind == "recipe" then
		def, prefix = Recipes.getHouseRecipeById(reward.id), "Recipe: "
	end
	return (prefix or "") .. (def and (def.name or def.title) or reward.id)
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
	for region, list in pairs(BiomeRewards.Master) do
		for _, r in ipairs(list) do
			out[#out + 1] = { region = region, kind = r.kind, id = r.id, master = true }
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
	Keys.add(profile) -- the first clear of a biome earns one Key (once: guarded by worldRewardIds above)
	return fresh
end

-- A WON run through a biome upgrades it: grants that biome's Master badge and title once. `route` is the run's
-- worldRoute. Call once when the run is won (the server does, not for revived runs). Returns the new rewards.
function BiomeRewards.recordRunWin(profile, route)
	local fresh = {}
	if not WorldMap.isValidRoute(route) then return fresh end
	local done = {}
	for _, id in ipairs(route) do
		local region = WorldMap.regionOf(id)
		local list = region and BiomeRewards.Master[region]
		local key = "master:" .. tostring(region)
		if list and not done[region] and not profile.worldRewardIds[key] then
			done[region] = true
			profile.worldRewardIds[key] = true
			for _, r in ipairs(list) do
				grant(profile, r)
				fresh[#fresh + 1] = r
			end
		end
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
-- target (optional) is the road the player means to take with it: a road that is not a pending choice or is still
-- locked (roadOpen(target) false) is refused BEFORE a charge is spent.
function BiomeRewards.useCompass(profile, state, phase, target, roadOpen)
	if not WorldMap.phaseAllowsRoadChoice(phase) then return false, "wrong_phase" end
	local choices = WorldMap.pendingChoices(state)
	if not choices or #choices < 2 then return false, "no_fork" end
	if target ~= nil then
		if type(target) ~= "string" or not table.find(choices, target) then return false, "not_next" end
		if roadOpen and not roadOpen(target) then return false, "locked" end
	end
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
function BiomeRewards.recordProgress(profile, route, cleared, state)
	local fresh = {}
	if not WorldMap.isValidRoute(route) then return fresh end
	local upTo = math.min(math.floor(cleared or 0), #route)
	for i = 1, upTo do
		if BiomeRewards.isBranchEnd(route, i) then
			local region = WorldMap.regionOf(route[i])
			local granted = BiomeRewards.recordBiomeCleared(profile, region)
			for _, r in ipairs(granted) do
				fresh[#fresh + 1] = r
			end
			-- A minigame token (state.mapTokens) upgrades the branch end: the biome's bonus title comes
			-- with it right away instead of waiting for every stop to be seen. One token per biome.
			local row = BiomeRewards.Rows[region]
			local key = region .. ":complete"
			if #granted > 0 and state and (state.mapTokens or 0) > 0 and row and row.bonus and not profile.worldRewardIds[key] then
				state.mapTokens = state.mapTokens - 1
				profile.worldRewardIds[key] = true
				grant(profile, row.bonus)
				fresh[#fresh + 1] = row.bonus
			end
		end
	end
	for _, r in ipairs(BiomeRewards.recordRegionBonuses(profile)) do
		fresh[#fresh + 1] = r
	end
	return fresh
end

return BiomeRewards
