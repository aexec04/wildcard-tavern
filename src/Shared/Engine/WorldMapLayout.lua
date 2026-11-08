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

-- Screen boxes (node + its label) the Graph view draws, so overlaps can be avoided here and tested.
-- kind "night": node of size floor(nodeSize * 0.78) (nodeSize on the player's road), label 190 x 44 below it.
-- kind "side": node of size floor(nodeSize * 0.56), label 150 x 40 to the RIGHT of it (a short, wide box).
WorldMapLayout.NIGHT_LABEL_W, WorldMapLayout.NIGHT_LABEL_H = 190, 44
WorldMapLayout.SIDE_LABEL_W, WorldMapLayout.SIDE_LABEL_H = 150, 40

function WorldMapLayout.box(kind, x, y, nodeSize, onRoute, compact)
	if kind == "side" then
		local size = math.floor(nodeSize * 0.56)
		if compact then -- crowded spot: node only, its label shows on hover
			return { x0 = x - size / 2, x1 = x + size / 2, y0 = y - size / 2, y1 = y + size / 2 }
		end
		local h = math.max(size, WorldMapLayout.SIDE_LABEL_H)
		return { x0 = x - size / 2, x1 = x + size / 2 + 4 + WorldMapLayout.SIDE_LABEL_W, y0 = y - h / 2, y1 = y + h / 2 }
	end
	local size = onRoute and nodeSize or math.floor(nodeSize * 0.78)
	local w = WorldMapLayout.NIGHT_LABEL_W
	return { x0 = x - w / 2, x1 = x + w / 2, y0 = y - size / 2, y1 = y + size / 2 + 6 + WorldMapLayout.NIGHT_LABEL_H }
end

function WorldMapLayout.overlaps(a, b)
	return a.x0 < b.x1 and b.x0 < a.x1 and a.y0 < b.y1 and b.y0 < a.y1
end

-- Every node + label box of a compute() result: { id = box }. route = the displayed road (array of ids).
function WorldMapLayout.boxesOf(res, nodeSize, route)
	local onRoute = {}
	for _, id in ipairs(route or {}) do onRoute[id] = true end
	local out = {}
	for id, p in pairs(res.pos) do
		out[id] = WorldMapLayout.box("night", p.x, p.y, nodeSize, onRoute[id])
	end
	for id, p in pairs(res.side) do
		out[id] = WorldMapLayout.box("side", p.x, p.y, nodeSize, nil, p.compact)
	end
	return out
end

function WorldMapLayout.compute(opts)
	local stops = opts.stops or WorldMap.Stops
	local H = opts.height
	local minGap = opts.minGap or 110
	if opts.nodeSize then -- a column must fit a node plus its label
		minGap = math.max(minGap, math.floor(opts.nodeSize * 0.78) + 6 + WorldMapLayout.NIGHT_LABEL_H + 4)
	end
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
	-- Side stops hang off their parent Night stop: to the right of it, above (dy < 0) or below it. A side
	-- stop is only placed where its node + label box (WorldMapLayout.box) overlaps no other node or label.
	local side = {}
	local nodeSize = opts.nodeSize or 72
	local spacing = (opts.nightX[2] or (opts.nightX[1] + 280)) - opts.nightX[1]
	local sideIds = {}
	for id, stop in pairs(stops) do
		if stop.kind == "side" and pos[stop.parent] then
			sideIds[#sideIds + 1] = id
		end
	end
	table.sort(sideIds)
	local step = math.floor(minGap * 0.6)
	local boxes = {}
	for id, p in pairs(pos) do
		boxes[#boxes + 1] = WorldMapLayout.box("night", p.x, p.y, nodeSize, onRoute[id] ~= nil)
	end
	local function clash(b)
		for _, other in ipairs(boxes) do
			if WorldMapLayout.overlaps(b, other) then return true end
		end
		return false
	end
	local sideSize = math.floor(nodeSize * 0.56)
	for _, id in ipairs(sideIds) do
		local stop = stops[id]
		local pp = pos[stop.parent]
		local want = ((stop.dy or 0.14) < 0) and -1 or 1
		local lo, hi = 30, H - 30
		local placedX, placedY
		-- preferred side first, then the other side, scanning outward in small steps; then further across.
		-- If the full node + label box fits nowhere (a crowded small canvas), place the node alone and mark it
		-- compact: the view then shows its label on hover only.
		local compact = false
		for pass = 1, 2 do
			compact = pass == 2
			for _, fx in ipairs({ 0.45, 0.32, 0.58, 0.7, 0.85, 1.0, 0.2 }) do
				local x = pp.x + math.floor(spacing * fx)
				local off = math.floor(step * 0.7)
				while not placedY and off <= H do
					for _, dir in ipairs({ want, -want }) do
						local y = pp.y + dir * off
						if not placedY and y >= lo and y <= hi
							and not clash(WorldMapLayout.box("side", x, y, nodeSize, nil, compact)) then
							placedX, placedY = x, y
						end
					end
					off = off + 12
				end
				if placedY then break end
			end
			if placedY then break end
		end
		if not placedY then -- no free spot: take the preferred one (the layout test flags this case)
			placedX, placedY = pp.x + math.floor(spacing * 0.45), math.max(lo, math.min(hi, pp.y + want * step))
		end
		side[id] = { x = placedX, y = placedY, parent = stop.parent, compact = compact or nil }
		boxes[#boxes + 1] = WorldMapLayout.box("side", placedX, placedY, nodeSize, nil, compact)
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
