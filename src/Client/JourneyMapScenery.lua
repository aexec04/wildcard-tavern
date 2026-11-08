--[[
	Client/JourneyMapScenery.lua
	Backdrop for the Journey map canvas: five painted regions side by side, the road
	to the tavern (ContentArt map_regions: road, meadow, river, peaks, tavern), soft
	fog bands over the seams, and map_decor doodles in the empty bands above and
	below the trail. Without region art each region is a flat tint; decor without art
	is skipped. Decor positions come from a fixed formula of the doodle's index, so
	they never shift between opens.

	Region widths follow the nodes: each region ends midway between its `lastNode`
	and the next node (the last region runs to the canvas edge), so Night 1 sits on
	the road, Nights 2-3 in the meadow, 4 on the river, 5 in the peaks and 6+ at the
	tavern. A region wider than its art (aspect 1.5) repeats the art in tiles; the art
	fades to plain parchment at its left and right edges so tiles join.

	deps: canvas (Frame), roundCorner, ContentArt

	Returns { layout = function(canvasW, canvasH, topLimit, bottomLimit, nodeXs) }
	topLimit = lowest y the top decor band may reach, bottomLimit = highest y
	of the bottom band (both from the node/label geometry). nodeXs = x of each node
	in canvas pixels (optional; without it the regions are equal width).
]]

return function(deps)
	local canvas = deps.canvas
	local ContentArt = deps.ContentArt
	local RegionTiles = deps.RegionTiles

	-- lastNode = index (in JourneyMap.allNodes order) of the last node inside the region.
	-- decor = doodles that fit the place, used in this order.
	local REGIONS = {
		{ key = "region_road", tint = Color3.fromRGB(222, 200, 150), lastNode = 1,
			decor = { "compass_rose", "signpost", "pine_tree" } }, -- sand
		{ key = "region_meadow", tint = Color3.fromRGB(190, 200, 142), lastNode = 3,
			decor = { "windmill", "mushroom_ring", "lantern_post", "cottage" } }, -- green
		{ key = "region_river", tint = Color3.fromRGB(168, 196, 176), lastNode = 4,
			decor = { "bridge", "pine_tree", "mushroom_ring" } }, -- blue-green
		{ key = "region_peaks", tint = Color3.fromRGB(186, 190, 172), lastNode = 5,
			decor = { "pine_tree", "signpost" } }, -- grey-green
		-- ONE tavern only (Nights 6 to 8; the Keeper's Table is the final destination): a single
		-- stretched image, never tiled. The Endless nodes beyond it get a plain road region.
		{ key = "region_tavern", tint = Color3.fromRGB(226, 190, 128), lastNode = 8, single = true,
			decor = { "cottage", "lantern_post", "pine_tree" } }, -- warm amber
		{ key = "region_road", tint = Color3.fromRGB(214, 192, 146), lastNode = math.huge,
			decor = { "signpost", "pine_tree", "mushroom_ring" } }, -- the road continues past the tavern
	}
	-- Neighbouring regions overlap by this many pixels (their art fades to plain parchment at
	-- the edges), so no 1px gap or white seam can show between biomes.
	local OVERLAP = 48
	local ART_ASPECT = 1.5 -- region art width / height
	local SEAM_FOG = Color3.fromRGB(240, 228, 204)
	-- Feathered join: 24 thin strips whose transparency follows a smoothstep bell (opaque-ish in the middle,
	-- clear at both ends), so the overlap reads as a soft mist instead of a straight cut. Never UIGradient
	-- Transparency.
	local SEAM_STEPS = {}
	do
		local n, peak = 24, 0.12 -- peak = lowest transparency, at the centre of the join
		for i = 1, n do
			local d = math.abs((i - 0.5) / n * 2 - 1) -- 1 at the ends, 0 in the middle
			local k = 1 - d * d * (3 - 2 * d) -- smoothstep bell
			SEAM_STEPS[i] = 1 - k * (1 - peak)
		end
	end
	local PARCHMENT_BASE = Color3.fromRGB(176, 170, 120) -- muted sand-green, so a gap never reads as a cream block

	local layer = Instance.new("Frame")
	layer.Name = "Scenery"
	layer.Size = UDim2.fromScale(1, 1)
	layer.BackgroundTransparency = 1
	layer.ZIndex = 21 -- under the road (22) and the trail dots (23)
	layer.BorderSizePixel = 0
	layer.Parent = canvas

	-- One continuous parchment sheet under every region, so a tile join can never show the panel behind.
	local base = Instance.new("Frame")
	base.Name = "ParchmentBase"
	base.BackgroundColor3 = PARCHMENT_BASE
	base.BorderSizePixel = 0
	base.ZIndex = 21
	base.Parent = layer

	local regionFrames = {}
	local regionIds = {}
	for i, region in ipairs(REGIONS) do
		local f = Instance.new("Frame")
		f.Name = "Region" .. i
		f.BackgroundColor3 = region.tint
		f.BorderSizePixel = 0
		f.ZIndex = 22
		f.Parent = layer
		regionIds[i] = ContentArt.getImageId("map_regions", region.key)
		regionFrames[i] = f
	end

	local seams = {}
	for s = 1, #REGIONS - 1 do
		local band = Instance.new("Frame")
		band.Name = "SeamFog" .. s
		band.BackgroundTransparency = 1
		band.BorderSizePixel = 0
		band.ZIndex = 24
		band.Parent = layer
		for i, tr in ipairs(SEAM_STEPS) do
			local strip = Instance.new("Frame")
			strip.Size = UDim2.new(1 / #SEAM_STEPS, 0, 1, 0)
			strip.Position = UDim2.fromScale((i - 1) / #SEAM_STEPS, 0)
			-- Tint runs from the left biome's colour to the right one's, so the join is never a pale band.
			local l, r = REGIONS[s].tint, REGIONS[s + 1].tint
			local c = RegionTiles.seamColor(
				{ l.R * 255, l.G * 255, l.B * 255 }, { r.R * 255, r.G * 255, r.B * 255 }, i, #SEAM_STEPS)
			strip.BackgroundColor3 = Color3.fromRGB(c[1], c[2], c[3])
			strip.BackgroundTransparency = tr
			strip.BorderSizePixel = 0
			strip.ZIndex = 24
			strip.Parent = band
		end
		seams[s] = band
	end

	local decorLayer = Instance.new("Frame")
	decorLayer.Name = "Decor"
	decorLayer.Size = UDim2.fromScale(1, 1)
	decorLayer.BackgroundTransparency = 1
	decorLayer.ZIndex = 23
	decorLayer.Parent = layer

	-- Region edges in canvas pixels: edges[i] = left of region i, edges[#REGIONS + 1] = canvasW.
	local function regionEdges(canvasW, nodeXs)
		local edges = { 0 }
		for i = 1, #REGIONS - 1 do
			local last = REGIONS[i].lastNode
			local x
			if nodeXs and nodeXs[last] and nodeXs[last + 1] then
				x = (nodeXs[last] + nodeXs[last + 1]) / 2
			else
				x = canvasW * i / #REGIONS
			end
			edges[i + 1] = math.floor(math.clamp(x, edges[i] + 1, canvasW))
		end
		edges[#REGIONS + 1] = math.floor(canvasW)
		return edges
	end

	local function layout(canvasW, canvasH, topLimit, bottomLimit, nodeXs)
		local edges = regionEdges(canvasW, nodeXs)
		base.Size = UDim2.fromOffset(math.floor(canvasW), canvasH)
		for i, f in ipairs(regionFrames) do
			local x0, x1 = edges[i] - (i > 1 and OVERLAP or 0), edges[i + 1] + (i < #REGIONS and OVERLAP or 0)
			local w = x1 - x0
			f.Position = UDim2.fromOffset(x0, 0)
			f.Size = UDim2.fromOffset(w + 1, canvasH)
			f:ClearAllChildren()
			-- With art the flat tint steps aside and the continuous parchment base shows through.
			f.BackgroundTransparency = regionIds[i] and 1 or 0
			if regionIds[i] then
				if REGIONS[i].single then
					-- The single tavern: a Crop copy covers the WHOLE frame (no uncovered gap, ever), and
					-- the hero image keeps its native aspect on top, centred on the Keeper's node.
					local cx = (nodeXs and nodeXs[REGIONS[i].lastNode]) or (x0 + w / 2)
					local t = RegionTiles.single(w + 1, canvasH, ART_ASPECT, cx - x0)
					local fill = Instance.new("ImageLabel")
					fill.Name = "Fill"
					fill.Size = UDim2.fromOffset(t.fillW, canvasH)
					fill.BackgroundTransparency = 1
					fill.Image = regionIds[i]
					fill.ScaleType = Enum.ScaleType.Crop
					fill.ZIndex = 22
					fill.Parent = f
					local img = Instance.new("ImageLabel")
					img.Name = "Tile1"
					img.Position = UDim2.fromOffset(t.heroX, 0)
					img.Size = UDim2.fromOffset(t.heroW, canvasH)
					img.BackgroundTransparency = 1
					img.Image = regionIds[i]
					img.ScaleType = Enum.ScaleType.Fit
					img.ZIndex = 23
					img.Parent = f
				else
					local tiles = RegionTiles.tiled(w, canvasH, ART_ASPECT)
					for t = 1, tiles do
						local img = Instance.new("ImageLabel")
						img.Name = "Tile" .. t
						img.Position = UDim2.fromOffset(math.floor((t - 1) * w / tiles), 0)
						img.Size = UDim2.fromOffset(math.ceil(w / tiles) + 1, canvasH)
						img.BackgroundTransparency = 1
						img.Image = regionIds[i]
						img.ScaleType = Enum.ScaleType.Crop
						img.ZIndex = 22
						img.Parent = f
					end
				end
			end
		end
		for s, band in ipairs(seams) do
			local leftW, rightW = edges[s + 1] - edges[s], edges[s + 2] - edges[s + 1]
			local seamW = math.floor(math.clamp(math.min(leftW, rightW) * 0.4, 180, 300))
			band.Position = UDim2.fromOffset(math.floor(edges[s + 1] - seamW / 2), 0)
			band.Size = UDim2.fromOffset(seamW, canvasH)
		end

		decorLayer:ClearAllChildren()
		local size = math.floor(math.clamp(canvasH * 0.13, 64, 112))
		local topRoom = topLimit - size - 12
		local bottomRoom = canvasH - size - 12 - bottomLimit
		local placed = 0
		for r, region in ipairs(REGIONS) do
			-- About one doodle per 330px of region, at least one per region.
			local rw = edges[r + 1] - edges[r]
			local count = math.max(1, math.floor(rw / 330))
			for j = 1, count do
				placed = placed + 1
				local i = placed
				local key = region.decor[((j - 1) % #region.decor) + 1]
				local id = ContentArt.getImageId("map_decor", key)
				local onTop = (i % 2 == 1)
				local room = onTop and topRoom or bottomRoom
				if id and room >= 0 then
					local jitterX = (((i * 7919) % 101) - 50) / 50 * 40
					local x = edges[r] + (j - 0.5) * rw / count + jitterX
					local t = ((i * 37) % 100) / 100
					local y = onTop and (12 + room * t) or (bottomLimit + room * t)
					local img = Instance.new("ImageLabel")
					img.Name = key
					img.AnchorPoint = Vector2.new(0.5, 0)
					img.Position = UDim2.fromOffset(math.floor(x), math.floor(y))
					img.Size = UDim2.fromOffset(size, size)
					img.BackgroundTransparency = 1
					img.Image = id
					img.ImageTransparency = 0.12
					img.ScaleType = Enum.ScaleType.Fit
					img.ZIndex = 23
					img.Parent = decorLayer
					deps.roundCorner(img, 14)
					local stroke = Instance.new("UIStroke")
					stroke.Color = Color3.fromRGB(110, 80, 45)
					stroke.Thickness = 1.5
					stroke.Transparency = 0.3
					stroke.Parent = img
				end
			end
		end
	end

	return { layout = layout }
end
