--[[
	Shared/Engine/WorldMap.lua
	Pure data and helpers for the branching adventure map (design: claude/MAP_DESIGN.md sections 1 and 2).
	No Roblox APIs, so it runs under plain Lua and is unit-tested.

	The world is a directed graph of stops. Every route from Start to Finish is exactly NIGHTS Night stops
	long, so a run is always 8 Nights whichever roads are taken (balance stays valid). A stop's Night number
	is its depth along the route, never stored on the stop.

	Shape (three forks):
	  Night 1-2   dusty_road -> wildflower_meadow
	  Fork A      after Night 2: 3 roads of 2 stops (Nights 3-4): lantern garden + willow bridge (default),
	              desert dunes + oasis camp, swamp boardwalk + lilypad pond
	  Fork B      after Night 4: 3 roads of 1 stop (Night 5): mountain pass (default), frosty trail, lighthouse cove
	  Crossing    tavern_gate (Night 6), the start of the tavern region
	  Fork C      after Night 6: 2 roads of 1 stop (Night 7): grand hall (default), warm kitchen
	  Finish      keepers_table (Night 8)
	That is 3 x 3 x 2 = 18 main routes. Forks B and C have one-stop roads because the default route must stay
	today's eight Nights and the tavern region (gate, hall, Keeper) has to come last.

	`art` is the SceneArt / map_nodes key. `fallbackArt` is an existing scene to use while the stop's own
	scenes are not generated yet (the new biomes; step 8 of the build order). Coordinates are canvas fractions
	(x along the world, y down) used for the map layout and the compass bearing.
]]

local WorldMap = {}

WorldMap.NIGHTS = 8
WorldMap.Start = "dusty_road"
WorldMap.Finish = "keepers_table"

-- Biomes. `scenery` is the map_regions key (missing art falls back to the flat tint), `reward` the biome
-- reward row id used by step 4.
WorldMap.Regions = {
	road = { name = "The Dusty Road", tint = { 222, 200, 150 }, scenery = "region_road", reward = "road" },
	meadow = { name = "Wildflower Meadow", tint = { 190, 200, 142 }, scenery = "region_meadow", reward = "meadow" },
	river = { name = "Willow River", tint = { 168, 196, 176 }, scenery = "region_river", reward = "river" },
	peaks = { name = "Mountain Peaks", tint = { 186, 190, 172 }, scenery = "region_peaks", reward = "peaks" },
	desert = { name = "Golden Dunes", tint = { 232, 204, 140 }, scenery = "region_desert", reward = "desert" },
	swamp = { name = "Misty Marsh", tint = { 150, 176, 138 }, scenery = "region_swamp", reward = "swamp" },
	snow = { name = "Frosty Hills", tint = { 206, 218, 228 }, scenery = "region_snow", reward = "snow" },
	coast = { name = "Lantern Coast", tint = { 170, 206, 214 }, scenery = "region_coast", reward = "coast" },
	tavern = { name = "The Tavern", tint = { 226, 190, 128 }, scenery = "region_tavern", reward = "tavern" },
}

-- Display order of the regions (for legends and lists; `pairs` order is not stable).
WorldMap.RegionOrder = { "road", "meadow", "river", "peaks", "desert", "swamp", "snow", "coast", "tavern" }

-- `next` lists the Night stops reachable from here: 1 id is a plain road, 2 to 3 ids are a fork.
-- The FIRST entry of every `next` list is the default road (the one today's eight Nights follow).
WorldMap.Stops = {
	dusty_road = { kind = "night", region = "road", art = "dusty_road", name = "The Dusty Road", icon = "DR",
		next = { "wildflower_meadow" }, x = 0.04, y = 0.5 },
	wildflower_meadow = { kind = "night", region = "meadow", art = "wildflower_meadow", name = "The Wildflower Meadow", icon = "WM",
		next = { "garden_terrace", "desert_dunes", "swamp_boardwalk" }, x = 0.12, y = 0.5 },

	-- Fork A, road 1 (default): garden and river.
	garden_terrace = { kind = "night", region = "meadow", art = "garden_terrace", name = "The Lantern Garden", icon = "LG",
		hint = "Calm gardens, then a quiet river", next = { "willow_bridge" }, x = 0.22, y = 0.5 },
	willow_bridge = { kind = "night", region = "river", art = "willow_bridge", name = "The Willow Bridge", icon = "WB",
		next = { "mountain_pass", "frosty_trail", "lighthouse_cove" }, x = 0.32, y = 0.5 },
	-- Fork A, road 2: the dunes.
	desert_dunes = { kind = "night", region = "desert", art = "desert_dunes", fallbackArt = "dusty_road", name = "The Singing Dunes", icon = "SD",
		hint = "Warm sands and market stalls", next = { "oasis_camp" }, x = 0.22, y = 0.18 },
	oasis_camp = { kind = "night", region = "desert", art = "oasis_camp", fallbackArt = "dusty_road", name = "The Oasis Camp", icon = "OC",
		next = { "mountain_pass", "frosty_trail", "lighthouse_cove" }, x = 0.32, y = 0.18 },
	-- Fork A, road 3: the marsh.
	swamp_boardwalk = { kind = "night", region = "swamp", art = "swamp_boardwalk", fallbackArt = "willow_bridge", name = "The Misty Boardwalk", icon = "MB",
		hint = "Foggy planks and glowing mushrooms", next = { "lilypad_pond" }, x = 0.22, y = 0.82 },
	lilypad_pond = { kind = "night", region = "swamp", art = "lilypad_pond", fallbackArt = "willow_bridge", name = "The Lilypad Pond", icon = "LP",
		next = { "mountain_pass", "frosty_trail", "lighthouse_cove" }, x = 0.32, y = 0.82 },

	-- Fork B: one stop on Night 5, all three roads rejoin at the tavern gate.
	mountain_pass = { kind = "night", region = "peaks", art = "mountain_pass", name = "The Mountain Pass", icon = "MP",
		hint = "Rocky trails and snowy peaks", next = { "tavern_gate" }, x = 0.46, y = 0.5 },
	frosty_trail = { kind = "night", region = "snow", art = "frosty_trail", fallbackArt = "mountain_pass", name = "The Frosty Trail", icon = "FT",
		hint = "Snowdrifts and lantern-lit pines", next = { "tavern_gate" }, x = 0.46, y = 0.18 },
	lighthouse_cove = { kind = "night", region = "coast", art = "lighthouse_cove", fallbackArt = "willow_bridge", name = "The Lighthouse Cove", icon = "LC",
		hint = "Tide pools and a friendly lighthouse", next = { "tavern_gate" }, x = 0.46, y = 0.82 },

	-- The tavern region always comes last: gate, hall (or kitchen), Keeper.
	tavern_gate = { kind = "night", region = "tavern", art = "tavern_gate", name = "The Tavern Gate", icon = "TG",
		next = { "grand_hall", "warm_kitchen" }, x = 0.6, y = 0.5 },
	grand_hall = { kind = "night", region = "tavern", art = "grand_hall", name = "The Grand Hall", icon = "GH",
		hint = "Chandeliers and banners", next = { "keepers_table" }, x = 0.74, y = 0.34 },
	warm_kitchen = { kind = "night", region = "tavern", art = "warm_kitchen", name = "The Warm Kitchen", icon = "WK",
		hint = "Steam, pots and a busy stove", next = { "keepers_table" }, x = 0.74, y = 0.66 },
	keepers_table = { kind = "night", region = "tavern", art = "keepers_table", name = "The Keeper's Table", icon = "KT",
		next = {}, x = 0.9, y = 0.5 },
}

-- Side stops: optional spurs off a Night stop (never a Night themselves). `side` is "shop", "shrine", "rest"
-- (step 6) or "minigame" with a `game` (steps 7a/7b). At most MAX_SIDE_PER_REGION per biome (validate checks it).
-- x/y are offsets from the parent's position for the dotted detour.
WorldMap.MAX_SIDE_PER_REGION = 3
WorldMap.SideKinds = { shop = true, shrine = true, rest = true, minigame = true }
local function side(id, parent, kind, name, icon, dx, dy)
	WorldMap.Stops[id] = { kind = "side", parent = parent, side = kind, name = name, icon = icon,
		dx = dx or 0.02, dy = dy or 0.14 }
end
side("picnic_stall", "wildflower_meadow", "shop", "The Picnic Stall", "$")
side("garden_shrine", "garden_terrace", "shrine", "The Garden Shrine", "+", 0.0, -0.14)
side("bridge_rest", "willow_bridge", "rest", "The Bridge Rest", "z")
side("summit_shrine", "mountain_pass", "shrine", "The Summit Shrine", "+")
side("oasis_stall", "oasis_camp", "shop", "The Oasis Stall", "$")
side("dune_rest", "desert_dunes", "rest", "The Dune Tent", "z", 0.0, -0.14)
side("lantern_hut", "swamp_boardwalk", "rest", "The Lantern Hut", "z")
side("mushroom_stall", "lilypad_pond", "shop", "The Mushroom Stall", "$")
side("cabin_rest", "frosty_trail", "rest", "The Snow Cabin", "z", 0.0, -0.14)
side("harbor_stall", "lighthouse_cove", "shop", "The Harbor Stall", "$")
side("gate_shrine", "tavern_gate", "shrine", "The Gate Shrine", "+", 0.0, 0.14)
-- Minigame stops (Engine/Minigames.lua): a win gives a map token and maybe a compass charge.
side("flip_bridge", "willow_bridge", "minigame", "The Card Flip Table", "*", 0.0, -0.14)
side("lockpick_cave", "mountain_pass", "minigame", "The Lockbox Cave", "*", 0.0, -0.14)
side("trivia_cabin", "frosty_trail", "minigame", "The Trivia Corner", "*")
side("dice_dock", "lighthouse_cove", "minigame", "The Dice Dock", "*", 0.0, -0.14)
-- Hidden side stops: a "?" stub on the map until revealed with a map token or compass charge (Engine/SideStops).
for _, id in ipairs({ "lockpick_cave", "dune_rest", "lantern_hut", "cabin_rest" }) do
	WorldMap.Stops[id].hidden = true
end
-- The Story Scroll hangs above the Meadow while the Picnic Stall hangs below it: the first fork of the road (a shop branch and an event branch)
side("story_scroll", "wildflower_meadow", "minigame", "The Story Scroll", "*", 0.0, -0.14)
WorldMap.Stops.story_scroll.game = "trivia"
WorldMap.Stops.flip_bridge.game = "cardflip"
WorldMap.Stops.lockpick_cave.game = "lockpick"
WorldMap.Stops.trivia_cabin.game = "trivia"
WorldMap.Stops.dice_dock.game = "dice"

-- The side stops hanging off a Night stop, in a stable order.
function WorldMap.sideStopsAt(stopId, stops)
	stops = stops or WorldMap.Stops
	local out = {}
	for id, stop in pairs(stops) do
		if stop.kind == "side" and stop.parent == stopId then
			out[#out + 1] = id
		end
	end
	table.sort(out)
	return out
end

-- ===== Lookups =====

function WorldMap.get(stopId)
	return WorldMap.Stops[stopId]
end

-- The Night stops that can follow `stopId` (empty at the Finish or for an unknown/side id).
function WorldMap.choicesAfter(stopId, stops)
	stops = stops or WorldMap.Stops
	local stop = stops[stopId]
	if not stop or stop.kind ~= "night" then
		return {}
	end
	local out = {}
	for i, id in ipairs(stop.next or {}) do
		out[i] = id
	end
	return out
end

function WorldMap.isFork(stopId, stops)
	return #WorldMap.choicesAfter(stopId, stops) > 1
end

-- Region id of a stop (a side stop belongs to its parent's region).
function WorldMap.regionOf(stopId, stops)
	stops = stops or WorldMap.Stops
	local stop = stops[stopId]
	if not stop then return nil end
	if stop.kind == "side" and stop.parent and stops[stop.parent] then
		return stops[stop.parent].region
	end
	return stop.region
end

-- How many Night stops a route array holds; the last one is the current Night. Side stops and ids that are
-- not Night stops do not count.
function WorldMap.routeNight(route, stops)
	stops = stops or WorldMap.Stops
	local n = 0
	for _, id in ipairs(route or {}) do
		local stop = stops[id]
		if stop and stop.kind == "night" then
			n = n + 1
		end
	end
	return n
end

-- True when `route` is a valid prefix of a path: starts at Start and every step is a legal choice.
function WorldMap.isValidRoute(route, stops, start)
	stops = stops or WorldMap.Stops
	start = start or WorldMap.Start
	if type(route) ~= "table" or #route == 0 or route[1] ~= start then
		return false
	end
	for i = 2, #route do
		if not table.find(WorldMap.choicesAfter(route[i - 1], stops), route[i]) then
			return false
		end
	end
	return true
end

-- The route that always takes the first road: today's eight Nights.
function WorldMap.defaultRoute(stops, start)
	stops = stops or WorldMap.Stops
	local route = { start or WorldMap.Start }
	local guard = 0
	while guard < 64 do
		guard = guard + 1
		local nxt = WorldMap.choicesAfter(route[#route], stops)[1]
		if not nxt then break end
		route[#route + 1] = nxt
	end
	return route
end

-- Every full route Start -> Finish as arrays of stop ids, in a stable order (first road first).
function WorldMap.allRoutes(stops, start, finish)
	stops = stops or WorldMap.Stops
	start = start or WorldMap.Start
	finish = finish or WorldMap.Finish
	local routes = {}
	local path = {}
	local function walk(id, depth)
		if depth > 64 then return end
		path[#path + 1] = id
		if id == finish then
			routes[#routes + 1] = { table.unpack(path) }
		else
			for _, nxt in ipairs(WorldMap.choicesAfter(id, stops)) do
				walk(nxt, depth + 1)
			end
		end
		path[#path] = nil
	end
	walk(start, 1)
	return routes
end

-- The art key to use for a stop's scenes: its own `art`, or `fallbackArt` while `hasArt(key)` says the
-- own art does not exist yet (hasArt omitted = always use the own art).
function WorldMap.sceneArtFor(stopId, hasArt, stops)
	stops = stops or WorldMap.Stops
	local stop = stops[stopId]
	if not stop then return nil end
	if hasArt and stop.fallbackArt and not hasArt(stop.art) then
		return stop.fallbackArt
	end
	return stop.art
end

-- ===== Compass =====

local atan2 = math.atan2 or math.atan -- Lua 5.3 and Luau differ; both give atan2(y, x) here

-- Compass bearing in degrees [0, 360) from one stop to another: 0 = up (north), 90 = right (east),
-- 180 = down, 270 = left. Uses the stops' canvas x/y (y grows downward).
function WorldMap.bearing(fromId, toId, stops)
	stops = stops or WorldMap.Stops
	local a, b = stops[fromId], stops[toId]
	if not (a and b) then return nil end
	local dx, dy = b.x - a.x, b.y - a.y
	if dx == 0 and dy == 0 then return 0 end
	local deg = math.deg(atan2(dx, -dy))
	return deg % 360
end

local function angleDiff(a, b)
	local d = math.abs(a - b) % 360
	return d > 180 and 360 - d or d
end

WorldMap.angleDiff = angleDiff

-- Of the roads after `stopId`, the one whose bearing is closest to `degrees`. Ties go to the earlier
-- (default) road. Returns nil when there is no road.
function WorldMap.pickByBearing(stopId, degrees, stops)
	local best, bestDiff
	for _, id in ipairs(WorldMap.choicesAfter(stopId, stops)) do
		local d = angleDiff(WorldMap.bearing(stopId, id, stops) or 0, degrees)
		if not bestDiff or d < bestDiff - 1e-9 then
			best, bestDiff = id, d
		end
	end
	return best
end

-- ===== The route of a run =====
-- state.worldRoute is the array of stop ids chosen so far, one per Night: Night n's stop is worldRoute[n].
-- It starts as { Start }. At the start of Night n (2 to NIGHTS) the route is one short until the road is
-- picked: a plain road (one choice) or a fixed plan (Daily, Weekly, Seed runs) fills in by itself, a fork
-- waits for ChooseRoad, and a player who never chooses gets the default (first) road.

function WorldMap.pendingChoices(state)
	local route = state and state.worldRoute
	if type(route) ~= "table" or type(state.night) ~= "number" then return nil end
	if state.night < 2 or state.night > WorldMap.NIGHTS then return nil end
	if #route ~= state.night - 1 then return nil end
	local choices = WorldMap.choicesAfter(route[#route])
	if #choices == 0 then return nil end
	return choices
end

-- The stop of the current Night (the last route entry), or nil past the Finish.
function WorldMap.currentStop(state)
	local route = state and state.worldRoute
	if type(route) ~= "table" then return nil end
	return route[math.min(#route, state.night or 1)]
end

-- Fills in the current Night's stop when nothing needs asking. Returns true if it added one.
function WorldMap.extendRoute(state)
	local choices = WorldMap.pendingChoices(state)
	if not choices then return false end
	local nxt
	if state.worldPlan and state.worldPlan[state.night] and table.find(choices, state.worldPlan[state.night]) then
		nxt = state.worldPlan[state.night]
	elseif #choices == 1 then
		nxt = choices[1]
	end
	if not nxt then return false end
	state.worldRoute[#state.worldRoute + 1] = nxt
	return true
end

-- A player who leaves Round Select without picking gets the default road (or the plan's).
function WorldMap.fillDefault(state)
	local choices = WorldMap.pendingChoices(state)
	if not choices then return false end
	if WorldMap.extendRoute(state) then return true end
	state.worldRoute[#state.worldRoute + 1] = choices[1]
	return true
end

-- Roads are only picked on the Round Select screen (never while playing, shopping or after game over).
function WorldMap.phaseAllowsRoadChoice(phase)
	return phase == "roundSelect"
end

-- Server-side validation of ChooseRoad; pass the session phase as the third argument to apply the phase gate
-- too. Returns true, or false plus a reason code.
-- roadOpen (optional) is a function(stopId) -> bool from the server (Engine/Keys): a locked road is refused.
function WorldMap.chooseRoad(state, stopId, phase, roadOpen)
	if phase ~= nil and not WorldMap.phaseAllowsRoadChoice(phase) then return false, "wrong_phase" end
	if type(state) ~= "table" or type(state.worldRoute) ~= "table" then return false, "no_route" end
	if type(stopId) ~= "string" then return false, "bad_id" end
	if state.worldPlan then return false, "fixed_route" end -- ranked boards use the seed's route
	local choices = WorldMap.pendingChoices(state)
	if not choices then return false, "no_choice" end
	if not table.find(choices, stopId) then return false, "not_next" end
	if roadOpen and not roadOpen(stopId) then return false, "locked" end
	state.worldRoute[#state.worldRoute + 1] = stopId
	-- The One More Round snapshot was taken before the pick; keep the pick in it so a continue does not undo it.
	local snap = state.roundStartSnapshot
	if type(snap) == "table" and type(snap.worldRoute) == "table" and #snap.worldRoute < #state.worldRoute then
		snap.worldRoute = { table.unpack(state.worldRoute) }
	end
	return true
end

-- A fixed route from a string (the Daily date key, Weekly key or Seed code), so every player of the same
-- board walks the same road. Uses its own tiny hash, never the run's rng, so deck and shop draws are
-- unchanged. Returns an array of NIGHTS stop ids.
function WorldMap.routeFromSeed(label)
	-- Plain arithmetic only (no bit operators, which differ between Lua 5.3 and Luau); every product stays
	-- below 2^53 so doubles are exact.
	local text = tostring(label)
	local h = 5381
	for i = 1, #text do
		h = (h * 33 + text:byte(i)) % 4294967296
	end
	local route = { WorldMap.Start }
	while #route < WorldMap.NIGHTS do
		local choices = WorldMap.choicesAfter(route[#route])
		if #choices == 0 then break end
		h = (h * 69069 + 1) % 4294967296
		route[#route + 1] = choices[(math.floor(h / 65536) % #choices) + 1]
	end
	return route
end

-- ===== Validation =====

-- Checks a graph (default: the real one). Returns ok, errors (array of strings).
-- Rules: Start and Finish exist; every stop is reachable from Start; no cycles; every route ends at the
-- Finish and has exactly `nights` Night stops; `next` ids exist and are Night stops; side stops have a
-- Night-stop parent; regions exist; tavern stops are never followed by a non-tavern stop.
function WorldMap.validate(stops, start, finish, nights, regions)
	stops = stops or WorldMap.Stops
	start = start or WorldMap.Start
	finish = finish or WorldMap.Finish
	nights = nights or WorldMap.NIGHTS
	regions = regions or WorldMap.Regions
	local errors = {}
	local function err(fmt, ...)
		errors[#errors + 1] = string.format(fmt, ...)
	end

	if not stops[start] then err("start stop %s missing", tostring(start)) end
	if not stops[finish] then err("finish stop %s missing", tostring(finish)) end
	if #errors > 0 then return false, errors end

	for id, stop in pairs(stops) do
		if stop.kind ~= "night" and stop.kind ~= "side" then
			err("%s has unknown kind %s", id, tostring(stop.kind))
		end
		if stop.kind == "night" then
			if not regions[stop.region] then err("%s has unknown region %s", id, tostring(stop.region)) end
			if type(stop.art) ~= "string" or stop.art == "" then err("%s has no art key", id) end
			if type(stop.name) ~= "string" or stop.name == "" then err("%s has no name", id) end
			if type(stop.x) ~= "number" or type(stop.y) ~= "number" then err("%s has no x/y", id) end
			if id ~= finish and #(stop.next or {}) == 0 then err("%s is a dead end", id) end
			if id == finish and #(stop.next or {}) > 0 then err("finish %s must not have next stops", id) end
			if #(stop.next or {}) > 3 then err("%s has more than 3 roads", id) end
			for _, nxt in ipairs(stop.next or {}) do
				if not stops[nxt] then
					err("%s -> %s does not exist", id, tostring(nxt))
				elseif stops[nxt].kind ~= "night" then
					err("%s -> %s is not a Night stop", id, tostring(nxt))
				elseif stops[nxt].region == nil or (stop.region == "tavern" and stops[nxt].region ~= "tavern") then
					err("%s (tavern) leads out of the tavern to %s", id, nxt)
				end
			end
		elseif stop.kind == "side" then
			local parent = stops[stop.parent]
			if not parent or parent.kind ~= "night" then
				err("side stop %s has no Night-stop parent", id)
			elseif not WorldMap.SideKinds[stop.side] then
				err("side stop %s has unknown side kind %s", id, tostring(stop.side))
			end
		end
	end
	-- At most MAX_SIDE_PER_REGION side stops per biome.
	local perRegion = {}
	for id, stop in pairs(stops) do
		if stop.kind == "side" and stops[stop.parent] then
			local region = stops[stop.parent].region
			perRegion[region] = (perRegion[region] or 0) + 1
			if perRegion[region] == WorldMap.MAX_SIDE_PER_REGION + 1 then
				err("region %s has more than %d side stops", tostring(region), WorldMap.MAX_SIDE_PER_REGION)
			end
		end
	end
	if #errors > 0 then return false, errors end

	-- Cycles and route lengths (DFS from Start).
	local visiting, reached = {}, {}
	local function walk(id, count)
		if visiting[id] then
			err("cycle through %s", id)
			return
		end
		reached[id] = true
		count = count + 1
		if count > nights then
			err("a route is longer than %d Night stops at %s", nights, id)
			return
		end
		local nexts = stops[id].next or {}
		if id == finish then
			if count ~= nights then
				err("a route reaches %s after %d Night stops, expected %d", id, count, nights)
			end
			return
		end
		visiting[id] = true
		for _, nxt in ipairs(nexts) do
			walk(nxt, count)
		end
		visiting[id] = nil
	end
	walk(start, 0)

	for id, stop in pairs(stops) do
		if stop.kind == "night" and not reached[id] then
			err("%s is not reachable from the start on a valid route", id)
		end
	end
	return #errors == 0, errors
end

return WorldMap
