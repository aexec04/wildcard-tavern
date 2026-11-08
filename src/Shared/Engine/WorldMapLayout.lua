--[[
	Engine/WorldMapLayout.lua
	Pure layout helper for drawing the whole branching world on the Tavern Map.

	The map view already places one node per Night along the player's road (`route`, one stop id per
	Night). This helper places EVERY other Night stop at the same Night column (same x) in a free lane
	above or below the road, and lists the roads (edges) between stops.

	compute(opts) -> { pos = { [stopId] = {x, y, depth} }, edges = { {from, to, onRoute} ... }, depthOf = {...} }
		opts.nightX   array of 8 pixel x positions (one per Night column)
		opts.routeY   array of 8 pixel y positions of the road's own nodes
		opts.height   canvas height in pixels
		opts.route    array of stop ids, one per Night (the displayed road: picked stops + default road)
		opts.minGap   minimum vertical distance between two nodes in a column (default 110)
		opts.stops    optional stop table (default WorldMap.Stops)
]]

local WorldMap = require(script.Parent.WorldMap)

local WorldMapLayout = {}

-- Night number of every Night stop (breadth first from the Start; all roads agree, see WorldMap.validate).
function WorldMapLayout.depths(stops)
	stops = stops or WorldMap.Stops
	local depthOf = { [WorldMap.Start] = 1 }
	local queue = { WorldMap.Start }
	local head = 1
	while head <= #queue do
		local id = queue[head]
		head = head + 1
		local stop = stops[id]
		for _, nxt in ipairs(stop and stop.next or {}) do
			if not depthOf[nxt] and stops[nxt] then
				depthOf[nxt] = depthOf[id] + 1
				queue[#queue + 1] = nxt
			end
		end
	end
	return depthOf
end

-- The road to show: the picked stops, then the default road onward from the last pick.
function WorldMapLayout.displayRoute(worldRoute, stops)
	stops = stops or WorldMap.Stops
	local route = {}
	for i, id in ipairs(worldRoute or {}) do
		if stops[id] and stops[id].kind == "night" then
			route[i] = id
		else
			break
		end
	end
	if #route == 0 then
		route[1] = WorldMap.Start
	end
	while #route < WorldMap.NIGHTS do
		local nxt = (stops[route[#route]] or {}).next
		if not nxt or not nxt[1] then
			break
		end
		route[#route + 1] = nxt[1]
	end
	return route
end

function WorldMapLayout.compute(opts)
	local stops = opts.stops or WorldMap.Stops
	local H = opts.height
	local minGap = opts.minGap or 110
	local depthOf = WorldMapLayout.depths(stops)
	local onRoute = {}
	for i, id in ipairs(opts.route) do
		onRoute[id] = i
	end

	local pos = {}
	local columns = {}
	for id, stop in pairs(stops) do
		if stop.kind == "night" and depthOf[id] then
			local d = depthOf[id]
			columns[d] = columns[d] or {}
			table.insert(columns[d], id)
		end
	end

	local lanes = { 0.16, 0.84, 0.5, 0.33, 0.67 } -- fractions of the height, tried nearest-first
	for d, ids in pairs(columns) do
		table.sort(ids, function(a, b)
			local ya, yb = stops[a].y or 0.5, stops[b].y or 0.5
			if ya ~= yb then return ya < yb end
			return a < b
		end)
		local placed = {}
		for _, id in ipairs(ids) do
			if onRoute[id] == d then
				local y = opts.routeY[d]
				pos[id] = { x = opts.nightX[d], y = y, depth = d }
				table.insert(placed, y)
			end
		end
		for _, id in ipairs(ids) do
			if not pos[id] then
				local want = (stops[id].y or 0.5) * H
				local order = {}
				for _, f in ipairs(lanes) do
					order[#order + 1] = f * H
				end
				table.sort(order, function(a, b) return math.abs(a - want) < math.abs(b - want) end)
				local chosen
				for _, y in ipairs(order) do
					local ok = true
					for _, other in ipairs(placed) do
						if math.abs(other - y) < minGap then ok = false break end
					end
					if ok then chosen = y break end
				end
				if not chosen then -- crowded column: stack below the lowest node
					local low = 0
					for _, other in ipairs(placed) do low = math.max(low, other) end
					chosen = low + minGap
				end
				pos[id] = { x = opts.nightX[d], y = chosen, depth = d }
				table.insert(placed, chosen)
			end
		end
	end

	local edges = {}
	local ids = {}
	for id in pairs(pos) do ids[#ids + 1] = id end
	table.sort(ids)
	for _, id in ipairs(ids) do
		for _, nxt in ipairs(stops[id].next or {}) do
			if pos[nxt] then
				local bothRoute = onRoute[id] ~= nil and onRoute[nxt] ~= nil and onRoute[nxt] == onRoute[id] + 1
				edges[#edges + 1] = { from = id, to = nxt, onRoute = bothRoute }
			end
		end
	end
	-- Side stops hang off their parent Night stop: to the right of it, above (dy < 0) or below it.
	local side = {}
	local spacing = (opts.nightX[2] or (opts.nightX[1] + 280)) - opts.nightX[1]
	local sideIds = {}
	for id, stop in pairs(stops) do
		if stop.kind == "side" and pos[stop.parent] then
			sideIds[#sideIds + 1] = id
		end
	end
	table.sort(sideIds)
	local step = math.floor(minGap * 0.6)
	local function clash(x, y)
		for _, other in pairs(side) do
			if math.abs(other.x - x) < 90 and math.abs(other.y - y) < 48 then return true end
		end
		for _, n in pairs(pos) do
			if math.abs(n.x - x) < 70 and math.abs(n.y - y) < 60 then return true end
		end
		return false
	end
	for _, id in ipairs(sideIds) do
		local stop = stops[id]
		local pp = pos[stop.parent]
		local want = ((stop.dy or 0.14) < 0) and -1 or 1
		local x = pp.x + math.floor(spacing * 0.45)
		local placed
		-- preferred side first, then the other side, then further out
		for _, k in ipairs({ 1, 1.7, 2.4 }) do
			for _, dir in ipairs({ want, -want }) do
				local y = math.max(40, math.min(H - 40, pp.y + dir * step * k))
				if not placed and not clash(x, y) then placed = y end
			end
		end
		side[id] = { x = x, y = placed or math.max(40, math.min(H - 40, pp.y + want * step)), parent = stop.parent }
	end
	return { pos = pos, edges = edges, depthOf = depthOf, side = side }
end

-- Fog rule for the extra stops: same Night distance rule as the nodes (the current Night and the next 3 are
-- shown, +4 is a "?" teaser, further is hidden). Anything already seen by the player stays shown.
function WorldMapLayout.visibility(depth, currentNight, seen)
	if seen then return "revealed" end
	local d = depth - math.max(1, currentNight or 1)
	if d <= 3 then return "revealed" end
	if d == 4 then return "teaser" end
	return "hidden"
end

-- Turn a compass bearing by `delta` degrees (an arrow button), snapped to a multiple of `snap` (default 15),
-- wrapped into 0..359.
function WorldMapLayout.stepBearing(bearing, delta, snap)
	snap = snap or 15
	local b = math.floor((bearing + delta) / snap + 0.5) * snap
	return b % 360
end

-- The stop ids whose rewards are shown as a badge: the last Night stop of each biome along each road.
function WorldMapLayout.branchEnds(stops)
	stops = stops or WorldMap.Stops
	local out = {}
	for id, stop in pairs(stops) do
		if stop.kind == "night" then
			local ends = true
			for _, nxt in ipairs(stop.next or {}) do
				if stops[nxt] and stops[nxt].region == stop.region then
					ends = false
				end
			end
			if ends and stop.region ~= "road" then
				out[id] = stop.region
			end
		end
	end
	return out
end

return WorldMapLayout
