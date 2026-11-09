--[[
	Client/JourneyMapScenery.lua
	Backdrop for the Journey map canvas: six painted strips side by side, the road
	to the tavern (ContentArt map_regions: road, meadow, river, peaks, tavern, road again), soft
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
	biomes meet (a zone of at least 25 percent of the narrower region, 96 to 480px, RegionTiles.joinWidth), the later biome is drawn as thin ImageLabel slices whose
	ImageTransparency follows a smootherstep from clear to opaque over many thin slices (RegionTiles.fadeSlices),
	a low-opacity tint band blends the two biome colours across the join, and a signpost or lantern post stands on the seam, a true cross-fade of the two
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
	local MapSeams = deps.MapSeams -- Engine/MapSeams: join geometry shared with the tests and tools/map_seam_report.lua

	-- lastNode = index (in JourneyMap.allNodes order) of the last node inside the region.
	-- decor = doodles that fit the place, used in this order.
	local REGIONS = {
		{ key = "region_road", tint = Color3.fromRGB(222, 200, 150), lastNode = 1, name = "The Dusty Road",
			decor = { "signpost", "pine_tree", "mushroom_ring" } }, -- sand (no compass_rose: the map has one real compass icon)
		{ key = "region_meadow", name = "Wildflower Meadow", tint = Color3.fromRGB(190, 200, 142), lastNode = 3,
			decor = { "windmill", "mushroom_ring", "lantern_post", "cottage" } }, -- green
		{ key = "region_river", name = "Willow River", tint = Color3.fromRGB(168, 196, 176), lastNode = 4,
			decor = { "bridge", "pine_tree", "mushroom_ring" } }, -- blue-green
		{ key = "region_peaks", name = "Mountain Peaks", tint = Color3.fromRGB(186, 190, 172), lastNode = 5,
			decor = { "pine_tree", "signpost" } }, -- grey-green
		-- ONE tavern only (Nights 6 to 8; the Keeper's Table is the final destination): a single
		-- stretched image, never tiled. The Endless nodes beyond it get a plain road region.
		{ key = "region_tavern", name = "The Tavern", tint = Color3.fromRGB(226, 190, 128), lastNode = 8, single = true,
			decor = { "cottage", "lantern_post", "pine_tree" } }, -- warm amber
		{ key = "region_road", tint = Color3.fromRGB(214, 192, 146), name = "The Road Beyond", lastNode = math.huge,
			decor = { "signpost", "pine_tree", "mushroom_ring" } }, -- the road continues past the tavern
	}
		local ART_ASPECT = 1.5 -- region art width / height
	local ZOOM = 1.2 -- tiles are zoomed about their centre so the art's own pale edge fade is clipped away
	-- Cross-fade zone: MapSeams.joinWidth (36 percent of the narrower region, so each painting overlaps its neighbour by
	-- 18 percent on each side). UIGradient.Transparency is never used (project rule): the fade is thin ImageTransparency slices.
	local HORIZON_Y = 0.5 -- every painting is anchored on the same vertical fraction so horizons line up
	local PARCHMENT_BASE = Color3.fromRGB(176, 170, 120) -- muted sand-green, so a gap never reads as a cream block

	-- Hover card text for each doodle: what it is and what to expect there. Hidden (fogged) landmarks only say "???".
	local DECOR_INFO = {
		signpost = { "Old Signpost", "Arrows point the way to the tavern." },
		pine_tree = { "Tall Pine", "A quiet spot to rest. Nothing is hidden here." },
		mushroom_ring = { "Mushroom Ring", "A fairy ring. Tavern folk say it brings luck." },
		windmill = { "Windmill", "Its sails turn all day for the tavern's flour." },
		lantern_post = { "Lantern Post", "Lit every evening for travellers." },
		cottage = { "Little Cottage", "A cosy stop with a warm window." },
		bridge = { "Stone Bridge", "Cross it to keep following the road." },
	}
	local hover = deps.TweenService and require(script.Parent.MapHover).new({
		canvas = canvas, TweenService = deps.TweenService, calm = deps.calm,
	}) or nil
	local fogEdge = nil -- canvas x where the fog starts (nil = nothing hidden); set by the view
	local decorRegion = {} -- decor ImageLabel -> region index

	local function bindLandmark(img, key, regionIndex)
		if not hover then return end
		decorRegion[img] = regionIndex
		hover.bind(img, function()
			local hidden = fogEdge ~= nil and img.Position.X.Offset > fogEdge
			if hidden then
				return { title = "???", biome = "???", line = "Something is hidden in the fog." }
			end
			local info = DECOR_INFO[key] or { key:gsub("_", " "), "A landmark on the road." }
			return { title = info[1], biome = REGIONS[regionIndex].name or "", line = info[2] }
		end, { pin = true })
	end

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
	base.BackgroundColor3 = Color3.new(1, 1, 1) -- tinted by the ramp below
	base.BorderSizePixel = 0
	base.ZIndex = 21
	base.Parent = layer
	local baseRamp = Instance.new("UIGradient") -- Color stops only: the averaged region colours across the canvas
	baseRamp.Color = ColorSequence.new(PARCHMENT_BASE)
	baseRamp.Parent = base

	local regionFrames = {}
	local regionIds = {}
	local fallbackIds = {} -- fallbackIds[i] = the nearest recorded painting, used when region i has none
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
	for i in ipairs(REGIONS) do
		if not regionIds[i] then
			local src = MapSeams.fallbackSource(REGIONS, i, function(j) return regionIds[j] ~= nil end)
			fallbackIds[i] = src and regionIds[src] or nil
		end
	end

	local fadeLayer = Instance.new("Frame") -- cross-fade slices; above every region body (they only cover joins)
	fadeLayer.Name = "RegionFades"
	fadeLayer.Size = UDim2.fromScale(1, 1)
	fadeLayer.BackgroundTransparency = 1
	fadeLayer.BorderSizePixel = 0
	fadeLayer.ZIndex = 22
	fadeLayer.Parent = layer

	local seamLayer = Instance.new("Frame") -- tint bands over the joins
	seamLayer.Name = "Seams"
	seamLayer.Size = UDim2.fromScale(1, 1)
	seamLayer.BackgroundTransparency = 1
	seamLayer.BorderSizePixel = 0
	seamLayer.ZIndex = 23
	seamLayer.Parent = layer

	local decorLayer = Instance.new("Frame")
	decorLayer.Name = "Decor"
	decorLayer.Size = UDim2.fromScale(1, 1)
	decorLayer.BackgroundTransparency = 1
	decorLayer.ZIndex = 23
	decorLayer.Parent = layer

	-- Region edges in canvas pixels: edges[i] = left of region i, edges[#REGIONS + 1] = canvasW.
	local function regionEdges(canvasW, nodeXs)
		return MapSeams.edges(REGIONS, canvasW, nodeXs)
	end

	-- Draws region i's painting into `row` (a Frame of size w x canvasH whose left is canvas x = x0).
	local function paintRegion(row, i, w, canvasH, x0, nodeXs)
		local image = regionIds[i] or fallbackIds[i]
		-- Clip window [winX, winX + winW] showing the tile whose nominal span is [nomX, nomX + nomW]; the image is
		-- zoomed ZOOM about the nominal centre, so windows can be widened or narrowed without moving the painting.
		local function zoomed(parent, name, winX, winW, nomX, nomW, scaleType, z)
			local win = Instance.new("Frame")
			win.Name = name .. "Win"
			win.Position = UDim2.fromOffset(winX, 0)
			win.Size = UDim2.fromOffset(winW, canvasH)
			win.BackgroundTransparency = 1
			win.BorderSizePixel = 0
			win.ClipsDescendants = true
			win.ZIndex = z
			win.Parent = parent
			local img = Instance.new("ImageLabel")
			img.Name = name
			img.AnchorPoint = Vector2.new(0.5, 0.5)
			img.Position = UDim2.fromOffset(nomX + nomW / 2 - winX, canvasH / 2)
			img.Size = UDim2.fromOffset(nomW * ZOOM, canvasH * ZOOM)
			img.BackgroundTransparency = 1
			img.Image = image
			img.ScaleType = scaleType
			img.ZIndex = z
			img.Parent = win
			return win, img
		end
		if REGIONS[i].single then
			-- The single tavern: a zoomed Crop copy covers the WHOLE row, and the hero image keeps its native
			-- aspect on top, centred on the Keeper's node.
			local cx = (nodeXs and nodeXs[REGIONS[i].lastNode]) or (x0 + w / 2)
			local t = RegionTiles.single(w + 1, canvasH, ART_ASPECT, cx - x0)
			zoomed(row, "Fill", 0, t.fillW, 0, t.fillW, Enum.ScaleType.Crop, 22)
			zoomed(row, "Tile1", t.heroX, t.heroW, t.heroX, t.heroW, Enum.ScaleType.Fit, 23)
		else
			-- Repeated tiles of one painting cannot match at their edges, so every tile boundary is a cross-fade:
			-- the earlier tile runs FW px past its edge and the later tile fades in over that overlap (thin slices,
			-- smootherstep), the same technique as the biome joins. No hard vertical band remains.
			local tiles = RegionTiles.tiled(w, canvasH, ART_ASPECT)
			local nomW = math.ceil(w / tiles) + 1
			local FW = tiles > 1 and math.floor(math.min(120, nomW * 0.1)) or 0
			for t = 1, tiles do
				local nomX = math.floor((t - 1) * w / tiles)
				local winX = nomX + (t > 1 and FW or 0)
				local winEnd = nomX + nomW + (t < tiles and FW or 0)
				zoomed(row, "Tile" .. t, winX, winEnd - winX, nomX, nomW, Enum.ScaleType.Crop, 22)
				if t > 1 then
					for k, slice in ipairs(RegionTiles.fadeSlices(FW, RegionTiles.sliceCount(FW))) do
						local _, img = zoomed(row, "TileFade" .. t .. "_" .. k, nomX + slice.x, slice.w, nomX, nomW, Enum.ScaleType.Crop, 23)
						img.ImageTransparency = slice.transparency
					end
				end
			end
		end
	end

	local function layout(canvasW, canvasH, topLimit, bottomLimit, nodeXs)
		local edges = regionEdges(canvasW, nodeXs)
		local joinW = {} -- joinW[i] = width of the cross-fade zone between region i-1 and i, centred on edges[i]
		for i = 2, #REGIONS do
			joinW[i] = MapSeams.joinWidth(edges[i] - edges[i - 1], edges[i + 1] - edges[i])
		end
		seamLayer:ClearAllChildren()
		base.Size = UDim2.fromOffset(math.floor(canvasW), canvasH)
		local keypoints = {}
		for _, stop in ipairs(MapSeams.underlayStops(REGIONS, edges, canvasW)) do
			keypoints[#keypoints + 1] = ColorSequenceKeypoint.new(stop.t, Color3.fromRGB(stop.r, stop.g, stop.b))
		end
		if #keypoints >= 2 then baseRamp.Color = ColorSequence.new(keypoints) end
		fadeLayer:ClearAllChildren()
		for i, f in ipairs(regionFrames) do
			local x0 = edges[i] - (i > 1 and joinW[i] / 2 or 0)
			local x1 = edges[i + 1] + (i < #REGIONS and joinW[i + 1] / 2 or 0)
			x0, x1 = math.floor(x0), math.floor(x1)
			local w = x1 - x0
			-- The body starts after the cross-fade zone so its left edge is never a hard cut.
			local image = regionIds[i] or fallbackIds[i]
			local fadeW = (i > 1 and image) and joinW[i] or 0
			f:ClearAllChildren()
			f.ClipsDescendants = true
			f.Position = UDim2.fromOffset(x0 + fadeW, 0)
			f.Size = UDim2.fromOffset(w - fadeW + 1, canvasH)
			-- With art the flat tint steps aside and the continuous parchment base shows through.
			f.BackgroundTransparency = image and 1 or 0
			if image then
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
					for k, slice in ipairs(RegionTiles.fadeSlices(fadeW, RegionTiles.sliceCount(fadeW))) do
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
							if d:IsA("ImageLabel") then
								-- keep the tile cross-fade: combine both transparencies instead of overwriting
								d.ImageTransparency = 1 - (1 - d.ImageTransparency) * (1 - slice.transparency)
							end
						end
					end
				end
			end
		end

		-- Soft low-opacity tint band across each join that blends the two biome colours (Color stops only),
		-- plus one shared prop planted on the seam line so the join reads as one landscape.
		for i = 2, #REGIONS do
			local band = Instance.new("Frame")
			band.Name = "SeamTint" .. i
			band.Position = UDim2.fromOffset(math.floor(edges[i] - joinW[i] / 2), 0)
			band.Size = UDim2.fromOffset(joinW[i], canvasH)
			band.BackgroundColor3 = Color3.new(1, 1, 1)
			band.BackgroundTransparency = 0.82
			band.BorderSizePixel = 0
			band.ZIndex = 23
			band.Parent = seamLayer
			local grad = Instance.new("UIGradient")
			grad.Color = ColorSequence.new(REGIONS[i - 1].tint, REGIONS[i].tint)
			grad.Parent = band
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
					bindLandmark(img, key, r)
					local stroke = Instance.new("UIStroke")
					stroke.Color = Color3.fromRGB(110, 80, 45)
					stroke.Thickness = 1.5
					stroke.Transparency = 0.3
					stroke.Parent = img
				end
			end
		end
		-- shared prop on each seam line (a sign or lantern post straddling the join)
		for i = 2, #REGIONS do
			local key = (i % 2 == 0) and "signpost" or "lantern_post"
			local id = ContentArt.getImageId("map_decor", key)
			if id and bottomLimit + size + 12 <= canvasH then
				local img = Instance.new("ImageLabel")
				img.Name = "Seam_" .. key
				img.AnchorPoint = Vector2.new(0.5, 0)
				img.Position = UDim2.fromOffset(math.floor(edges[i]), math.floor(bottomLimit + 6))
				img.Size = UDim2.fromOffset(size, size)
				img.BackgroundTransparency = 1
				img.Image = id
				img.ImageTransparency = 0.12
				img.ScaleType = Enum.ScaleType.Fit
				img.ZIndex = 24
				img.Parent = decorLayer
				bindLandmark(img, key, i)
			end
		end
	end

	return {
		layout = layout,
		-- The view tells the scenery where the fog starts so hidden landmarks only say "???".
		setFogEdge = function(x) fogEdge = x end,
	}
end
