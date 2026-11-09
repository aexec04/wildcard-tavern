--[[
	Engine/MapSeams.lua
	Pure geometry for the Tavern Map backdrop (Client/JourneyMapScenery.lua draws it), so the join rules can be tested
	and reported without Studio.

	The map canvas is a row of painted region strips. Where two neighbours meet, BOTH paintings overlap across a join
	zone and cross-fade (thin ImageTransparency slices; UIGradient.Transparency is never used in this project). The zone
	is JOIN_FRAC of the narrower region wide, so each painting runs JOIN_FRAC / 2 (18 percent) past its own edge. Under
	every strip sits one full-canvas colour ramp built from the region tints, so a gap or a missing painting is never a
	flat block.

	  MapSeams.edges(regions, canvasW, nodeXs)      -> edges[1..#regions + 1] (canvas pixels)
	  MapSeams.joinWidth(wa, wb)                    -> pixel width of the cross-fade zone between two regions
	  MapSeams.plan(regions, canvasW, canvasH, nodeXs, hasArt) -> per-region and per-join numbers (for the report)
	  MapSeams.underlayStops(regions, edges, canvasW) -> { { t, r, g, b } ... } colour ramp stops, t in 0..1
	  MapSeams.fallbackSource(regions, i, hasArt)   -> index of the nearest region that has art (or nil)
]]

local MapSeams = {}

MapSeams.JOIN_FRAC = 0.36 -- zone = 36 percent of the narrower region: 18 percent of overlap on each side
MapSeams.JOIN_MIN = 120
MapSeams.JOIN_MAX = 720
MapSeams.ART_ASPECT = 1.5 -- region art is generated at 1536x1024

function MapSeams.joinWidth(wa, wb)
	local narrow = math.min(wa, wb)
	local w = math.max(MapSeams.JOIN_MIN, narrow * MapSeams.JOIN_FRAC)
	w = math.min(w, MapSeams.JOIN_MAX, narrow)
	return math.floor(w)
end

-- regions[i].lastNode = index of the last map node inside region i (math.huge for the last region).
function MapSeams.edges(regions, canvasW, nodeXs)
	local edges = { 0 }
	for i = 1, #regions - 1 do
		local last = regions[i].lastNode
		local x
		if nodeXs and nodeXs[last] and nodeXs[last + 1] then
			x = (nodeXs[last] + nodeXs[last + 1]) / 2
		else
			x = canvasW * i / #regions
		end
		edges[i + 1] = math.floor(math.max(edges[i] + 1, math.min(x, canvasW)))
	end
	edges[#regions + 1] = math.floor(canvasW)
	return edges
end

function MapSeams.fallbackSource(regions, i, hasArt)
	for d = 1, #regions do
		for _, j in ipairs({ i - d, i + d }) do
			if j >= 1 and j <= #regions and hasArt(j) then
				return j
			end
		end
	end
	return nil
end

function MapSeams.plan(regions, canvasW, canvasH, nodeXs, hasArt)
	local edges = MapSeams.edges(regions, canvasW, nodeXs)
	local out = { edges = edges, regions = {}, joins = {} }
	for i = 2, #regions do
		local wa, wb = edges[i] - edges[i - 1], edges[i + 1] - edges[i]
		local jw = MapSeams.joinWidth(wa, wb)
		out.joins[i] = {
			between = { i - 1, i }, x = edges[i], width = jw, from = edges[i] - jw / 2, to = edges[i] + jw / 2,
			overlapLeftPct = jw / 2 / wa * 100, overlapRightPct = jw / 2 / wb * 100,
		}
	end
	for i, region in ipairs(regions) do
		local w = edges[i + 1] - edges[i]
		local art = hasArt(i)
		out.regions[i] = {
			key = region.key, hasArt = art, width = w, x0 = edges[i], x1 = edges[i + 1],
			tiles = region.single and 1 or math.max(1, math.floor(w / (canvasH * MapSeams.ART_ASPECT) + 0.5)),
			fallbackFrom = (not art) and MapSeams.fallbackSource(regions, i, hasArt) or nil,
		}
	end
	return out
end

-- A smooth colour ramp across the canvas: one stop at the centre of every region, tints given as {r, g, b} 0..255.
function MapSeams.underlayStops(regions, edges, canvasW)
	local stops = {}
	for i, region in ipairs(regions) do
		local centre = (edges[i] + edges[i + 1]) / 2
		local t = math.max(0, math.min(1, centre / math.max(1, canvasW)))
		stops[#stops + 1] = { t = t, r = region.tint[1], g = region.tint[2], b = region.tint[3] }
	end
	table.sort(stops, function(a, b) return a.t < b.t end)
	-- ColorSequence keypoints must start at 0 and end at 1 with strictly increasing times
	local clean = {}
	for _, s in ipairs(stops) do
		local last = clean[#clean]
		if not last or s.t > last.t + 0.001 then
			clean[#clean + 1] = s
		end
	end
	local first, last = clean[1], clean[#clean]
	if first and first.t > 0 then table.insert(clean, 1, { t = 0, r = first.r, g = first.g, b = first.b }) end
	if last and last.t < 1 then clean[#clean + 1] = { t = 1, r = last.r, g = last.g, b = last.b } end
	return clean
end

return MapSeams
