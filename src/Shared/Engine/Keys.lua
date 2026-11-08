--[[
	Shared/Engine/Keys.lua
	Locked roads and Keys for the branching world map. Pure, no Roblox APIs, unit-tested.

	A "road" is the first stop after a fork (the stop id the player picks): garden_terrace, desert_dunes,
	swamp_boardwalk (Fork A), mountain_pass, frosty_trail, lighthouse_cove (Fork B), grand_hall, warm_kitchen
	(Fork C). All roads stay visible on the map; a locked one shows a padlock and the biome it leads to.

	Open for a new player (no Key needed):
	  - the default road at every fork (the first `next`, i.e. the Dusty Road route), and
	  - Keys.FreeRoads: the two gentlest other roads, the Lighthouse Cove (a friendly lighthouse) and the Warm
	    Kitchen (steam, pots and a busy stove). That makes three open routes to walk before any Key is needed.
	Locked until a Key is spent: desert_dunes, swamp_boardwalk, frosty_trail.

	Keys are earned only, never sold: +1 for winning a run (PlayerProfile.recordRunWon) and +1 for the first
	clear of a biome at its branch end (BiomeRewards.recordBiomeCleared). One Key opens one road for good
	(profile.unlockedRoadIds). Daily, Weekly and Seed boards use their own fixed route and ignore locks, which the
	server enforces in WorldMap.chooseRoad (fixed_route) and WorldMap.extendRoute (plans do not check locks).

	Profile fields (PlayerProfile): keys (0..MAX_KEYS), unlockedRoadIds ([stop id] = true).
]]

local WorldMap = require(script.Parent.WorldMap)

local Keys = {}

Keys.MAX_KEYS = 99
Keys.FreeRoads = { "lighthouse_cove", "warm_kitchen" }

-- Every road: a Night stop that follows a fork. Returns { [stopId] = true } and a sorted list.
function Keys.allRoads(stops)
	stops = stops or WorldMap.Stops
	local set, list = {}, {}
	for id, stop in pairs(stops) do
		if stop.kind == "night" and #(stop.next or {}) > 1 then
			for _, nxt in ipairs(stop.next) do
				if not set[nxt] then
					set[nxt] = true
					list[#list + 1] = nxt
				end
			end
		end
	end
	table.sort(list)
	return set, list
end

-- True for the first road of a fork (the default route).
function Keys.isDefaultRoad(stopId, stops)
	stops = stops or WorldMap.Stops
	for _, stop in pairs(stops) do
		if stop.kind == "night" and #(stop.next or {}) > 1 and stop.next[1] == stopId then
			return true
		end
	end
	return false
end

-- True when the road needs no Key: a default road, a free road, or any stop that is not a fork road at all.
function Keys.isFreeRoad(stopId, stops)
	local roads = Keys.allRoads(stops)
	if not roads[stopId] then
		return true
	end
	return Keys.isDefaultRoad(stopId, stops) or table.find(Keys.FreeRoads, stopId) ~= nil
end

-- Sorted list of the roads that need a Key.
function Keys.lockedRoads(stops)
	local _, list = Keys.allRoads(stops)
	local out = {}
	for _, id in ipairs(list) do
		if not Keys.isFreeRoad(id, stops) then
			out[#out + 1] = id
		end
	end
	return out
end

-- Can this profile walk the road? (free, or already unlocked with a Key)
function Keys.isRoadOpen(profile, stopId)
	if Keys.isFreeRoad(stopId) then
		return true
	end
	return type(profile) == "table" and type(profile.unlockedRoadIds) == "table" and profile.unlockedRoadIds[stopId] == true
end

-- "open" (free), "unlocked" (opened with a Key) or "locked".
function Keys.status(profile, stopId)
	if Keys.isFreeRoad(stopId) then return "open" end
	if Keys.isRoadOpen(profile, stopId) then return "unlocked" end
	return "locked"
end

-- Status of every pending road for the state push: { [stopId] = "open" | "unlocked" | "locked" }.
function Keys.statusMap(profile, choices)
	local out = {}
	for _, id in ipairs(choices or {}) do
		out[id] = Keys.status(profile, id)
	end
	return out
end

function Keys.count(profile)
	return type(profile) == "table" and math.floor(profile.keys or 0) or 0
end

-- +1 Key (capped). Returns true if one was added.
function Keys.add(profile)
	if type(profile) ~= "table" then return false end
	local n = math.floor(profile.keys or 0)
	if n >= Keys.MAX_KEYS then return false end
	profile.keys = n + 1
	return true
end

-- Spend one Key on a locked road. Only a road that is a pending fork choice right now can be unlocked, and only
-- on Round Select (the same gate as ChooseRoad). Returns true, or false plus a reason code:
-- wrong_phase, bad_id, not_next, not_locked, no_key, fixed_route.
function Keys.unlock(profile, state, stopId, phase)
	if phase ~= nil and not WorldMap.phaseAllowsRoadChoice(phase) then return false, "wrong_phase" end
	if type(profile) ~= "table" then return false, "no_profile" end
	if type(stopId) ~= "string" then return false, "bad_id" end
	if type(state) == "table" and state.worldPlan then return false, "fixed_route" end
	local choices = WorldMap.pendingChoices(state)
	if not choices or not table.find(choices, stopId) then return false, "not_next" end
	if Keys.isRoadOpen(profile, stopId) then return false, "not_locked" end
	if Keys.count(profile) <= 0 then return false, "no_key" end
	profile.keys = Keys.count(profile) - 1
	profile.unlockedRoadIds = profile.unlockedRoadIds or {}
	profile.unlockedRoadIds[stopId] = true
	return true
end

return Keys
