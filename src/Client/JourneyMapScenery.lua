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

	Joins: no pale or white seam. Each painted tile is zoomed 1.2x about its centre inside a clipping
	frame, so the pale parchment fade the art has at its own edges falls outside the frame. Where two
	biomes meet (a 2 * OVERLAP zone), the later biome is drawn as thin ImageLabel slices whose
	ImageTransparency steps from clear to opaque (RegionTiles.fadeSlices), a true cross-fade of the two
	neighbouring paintings (stacked frames, no UIGradient Transparency).

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
			decor = { "signpost", "pine_tree", "mushroom_ring" } }, -- sand (no compass_rose: the map has one real compass icon)
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
	local ZOOM = 1.2 -- tiles are zoomed about their centre so the art's own pale edge fade is clipped away
	local FADE_SLICES = 16
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

	local fadeLayer = Instance.new("Frame") -- cross-fade slices; above every region body (they only cover joins)
	fadeLayer.Name = "RegionFades"
	fadeLayer.Size = UDim2.fromScale(1, 1)
	fadeLayer.BackgroundTransparency = 1
	fadeLayer.BorderSizePixel = 0
	fadeLayer.ZIndex = 22
	fadeLayer.Parent = layer

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

	-- Draws region i's painting into `row` (a Frame of size w x canvasH whose left is canvas x = x0).
	local function paintRegion(row, i, w, canvasH, x0, nodeXs)
		local image = regionIds[i]
		local function zoomed(parent, name, x, tileW, scaleType, z)
			-- clip window of the tile's exact size, with the image zoomed ZOOM about the centre inside it
			local win = Instance.new("Frame")
			win.Name = name .. "Win"
			win.Position = UDim2.fromOffset(x, 0)
			win.Size = UDim2.fromOffset(tileW, canvasH)
			win.BackgroundTransparency = 1
			win.BorderSizePixel = 0
			win.ClipsDescendants = true
			win.ZIndex = z
			win.Parent = parent
			local img = Instance.new("ImageLabel")
			img.Name = name
			img.AnchorPoint = Vector2.new(0.5, 0.5)
			img.Position = UDim2.fromScale(0.5, 0.5)
			img.Size = UDim2.fromScale(ZOOM, ZOOM)
			img.BackgroundTransparency = 1
			img.Image = image
			img.ScaleType = scaleType
			img.ZIndex = z
			img.Parent = win
			return win
		end
		if REGIONS[i].single then
			-- The single tavern: a zoomed Crop copy covers the WHOLE row, and the hero image keeps its native
			-- aspect on top, centred on the Keeper's node.
			local cx = (nodeXs and nodeXs[REGIONS[i].lastNode]) or (x0 + w / 2)
			local t = RegionTiles.single(w + 1, canvasH, ART_ASPECT, cx - x0)
			zoomed(row, "Fill", 0, t.fillW, Enum.ScaleType.Crop, 22)
			zoomed(row, "Tile1", t.heroX, t.heroW, Enum.ScaleType.Fit, 23)
		else
			local tiles = RegionTiles.tiled(w, canvasH, ART_ASPECT)
			for t = 1, tiles do
				zoomed(row, "Tile" .. t, math.floor((t - 1) * w / tiles), math.ceil(w / tiles) + 1, Enum.ScaleType.Crop, 22)
			end
		end
	end

	local function layout(canvasW, canvasH, topLimit, bottomLimit, nodeXs)
		local edges = regionEdges(canvasW, nodeXs)
		base.Size = UDim2.fromOffset(math.floor(canvasW), canvasH)
		fadeLayer:ClearAllChildren()
		for i, f in ipairs(regionFrames) do
			local x0, x1 = edges[i] - (i > 1 and OVERLAP or 0), edges[i + 1] + (i < #REGIONS and OVERLAP or 0)
			local w = x1 - x0
			-- The body starts after the cross-fade zone (2 * OVERLAP wide) so its left edge is never a hard cut.
			local fadeW = (i > 1 and regionIds[i]) and 2 * OVERLAP or 0
			f:ClearAllChildren()
			f.ClipsDescendants = true
			f.Position = UDim2.fromOffset(x0 + fadeW, 0)
			f.Size = UDim2.fromOffset(w - fadeW + 1, canvasH)
			-- With art the flat tint steps aside and the continuous parchment base shows through.
			f.BackgroundTransparency = regionIds[i] and 1 or 0
			if regionIds[i] then
				local row = Instance.new("Frame")
				row.Name = "Row"
				row.Position = UDim2.fromOffset(-fadeW, 0)
				row.Size = UDim2.fromOffset(w + 1, canvasH)
				row.BackgroundTransparency = 1
				row.BorderSizePixel = 0
				row.ZIndex = 22
				row.Parent = f
				paintRegion(row, i, w, canvasH, x0, nodeXs)
				if fadeW > 0 then
					-- cross-fade: thin clipped slices of the same painting, clear on the left to opaque on the right
					for k, slice in ipairs(RegionTiles.fadeSlices(fadeW, FADE_SLICES)) do
						local win = Instance.new("Frame")
						win.Name = "Fade" .. i .. "_" .. k
						win.Position = UDim2.fromOffset(x0 + slice.x, 0)
						win.Size = UDim2.fromOffset(slice.w, canvasH)
						win.BackgroundTransparency = 1
						win.BorderSizePixel = 0
						win.ClipsDescendants = true
						win.ZIndex = 22
						win.Parent = fadeLayer
						local copy = Instance.new("Frame")
						copy.Name = "Row"
						copy.Position = UDim2.fromOffset(-slice.x, 0)
						copy.Size = UDim2.fromOffset(w + 1, canvasH)
						copy.BackgroundTransparency = 1
						copy.BorderSizePixel = 0
						copy.ZIndex = 22
						copy.Parent = win
						paintRegion(copy, i, w, canvasH, x0, nodeXs)
						for _, d in ipairs(copy:GetDescendants()) do
							if d:IsA("ImageLabel") then d.ImageTransparency = slice.transparency end
						end
					end
				end
			end
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
