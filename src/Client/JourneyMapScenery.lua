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

	REBUILT (no seams by construction): one continuous parchment base (colour ramp of the region tints) under soft-edged
	paintings. Every painting is a Crop ImageLabel with a horizontal UIGradient transparency mask (RegionTiles.maskStops,
	smootherstep, 10 keypoints per faded side) so it fades to the base on its left and right, and two full-width parchment
	feathers fade the top and bottom. Neighbouring regions overlap by the join zone and cross-fade; there are no clip windows,
	no stacked slices and no flat tint frames. (The older notes below describe the slice scheme this replaced.)

	LAYERS (ZIndex is absolute): the GameUI ScreenGui draws with ZIndexBehavior.Global, so a child is never lifted to its
	parent's level and a ZIndex left at 1 draws under the whole map. Bottom to top: the Tavern Map plate (21), ParchmentBase
	(21, the plate's descendant, so it wins the tie), every painting (22), WorldGraph (23), the road, labels and nodes,
	the top and bottom feathers (29), doodles (30 and 31), the fog (35). Painting tiles used to take their tile number (1, 2, ...)
	as ZIndex and drew under ParchmentBase and the plate, so the map showed only the base colours. At equal ZIndex the later
	sibling draws on top: that is what lets a later region (or tile) fade in over the earlier one, and the road pieces, created
	after this layer, draw over the paintings. reportLayers() prints every ZIndex once per Studio session.

	Joins (old notes): no pale or white seam. Each painted tile is zoomed 1.2x about its centre inside a clipping
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
	local PropRules = deps.PropRules -- Engine/MapPropRules: opaque props are not drawn
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
	-- Layers (see the header): absolute ZIndex values under ZIndexBehavior.Global.
	local Z_BASE = 21 -- ParchmentBase and the container, level with the Tavern Map plate (a descendant wins the tie)
	local Z_PAINTING = 22 -- every Region frame and painting tile: above the base, below WorldGraph (23) and everything on the road
	local Z_FEATHER = 29 -- FeatherTop and FeatherBottom
	local Z_DECOR = 30 -- doodles: above the feathers (they would fade a doodle) and below the fog (35, which hides them)
	local ART_ASPECT = 1.5 -- region art width / height
	local ZOOM = 1.2 -- tiles are zoomed about their centre so the art's own pale edge fade is clipped away
	-- Cross-fade zone: MapSeams.joinWidth (36 percent of the narrower region, so each painting overlaps its neighbour by
	-- 18 percent on each side). UIGradient.Transparency is never used (project rule): the fade is thin ImageTransparency slices.
	local HORIZON_Y = 0.5 -- every painting is anchored on the same vertical fraction so horizons line up
	local PARCHMENT_BASE = Color3.fromRGB(176, 170, 120) -- muted sand-green, so a gap never reads as a cream block

	-- Hover card text for each doodle lives in Engine/MapTooltips (what it is and what to expect there). Fogged landmarks only say "???".
	local Tips = deps.MapTips -- Engine/MapTooltips
	local DECOR_INFO = Tips.DECOR
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
				return { title = "???", biome = "???", line = Tips.FOG_DECOR }
			end
			local info = DECOR_INFO[key] or { (key:gsub("_", " ")), Tips.DECOR_FALLBACK }
			return { title = info[1], biome = REGIONS[regionIndex].name or "", line = info[2] }
		end, { pin = true })
	end

	local layer = Instance.new("Frame")
	layer.Name = "Scenery"
	layer.Size = UDim2.fromScale(1, 1)
	layer.BackgroundTransparency = 1
	layer.ZIndex = Z_BASE
	layer.BorderSizePixel = 0
	layer.Parent = canvas

	-- One continuous parchment sheet under every region, so a tile join can never show the panel behind.
	local base = Instance.new("Frame")
	base.Name = "ParchmentBase"
	base.BackgroundColor3 = Color3.new(1, 1, 1) -- tinted by the ramp below
	base.BorderSizePixel = 0
	base.ZIndex = Z_BASE
	base.Parent = layer
	local baseRamp = Instance.new("UIGradient") -- Color stops only: the averaged region colours across the canvas
	baseRamp.Color = ColorSequence.new(PARCHMENT_BASE)
	baseRamp.Parent = base

	local regionIds = {}
	local fallbackIds = {} -- fallbackIds[i] = the nearest recorded painting, used when region i has none
	for i, region in ipairs(REGIONS) do
		regionIds[i] = ContentArt.getImageId("map_regions", region.key)
	end
	for i in ipairs(REGIONS) do
		if not regionIds[i] then
			local src = MapSeams.fallbackSource(REGIONS, i, function(j) return regionIds[j] ~= nil end)
			fallbackIds[i] = src and regionIds[src] or nil
		end
	end

	-- Region paintings live in holders (no clipping, no flat tint frame: a missing painting just shows the base ramp).
	local regionHolders = {}
	for i = 1, #REGIONS do
		local h = Instance.new("Frame")
		h.Name = "Region" .. i
		h.BackgroundTransparency = 1
		h.BorderSizePixel = 0
		h.ZIndex = Z_PAINTING -- not 22 + i: a later holder wins the tie by being created later
		h.Parent = layer
		regionHolders[i] = h
	end

	-- RegionTiles.maskStops points -> NumberSequence. Roblox allows at most 20 keypoints, so anything longer is resampled evenly.
	local function maskSequence(pts)
		local max = RegionTiles.MAX_KEYPOINTS
		local kps = {}
		if #pts <= max then
			for _, p in ipairs(pts) do kps[#kps + 1] = NumberSequenceKeypoint.new(p.t, p.transparency) end
		else
			for i = 1, max do
				local p = pts[1 + math.floor((i - 1) * (#pts - 1) / (max - 1) + 0.5)]
				kps[#kps + 1] = NumberSequenceKeypoint.new(i == 1 and 0 or (i == max and 1 or p.t), p.transparency)
			end
		end
		return NumberSequence.new(kps)
	end

	-- Top and bottom feathers: one full-width parchment frame per edge fading to clear, so a painting never ends in a straight cut.
	local function feather(name, up)
		local f = Instance.new("Frame")
		f.Name = name
		f.BackgroundColor3 = PARCHMENT_BASE
		f.BorderSizePixel = 0
		f.ZIndex = Z_FEATHER
		f.Parent = layer
		local g = Instance.new("UIGradient")
		g.Rotation = 90
		g.Transparency = maskSequence(RegionTiles.maskStops(1, up and 0 or 1, up and 1 or 0, 10)) -- fully parchment at the canvas edge, clear inward
		g.Parent = f
		return f
	end
	local featherTop, featherBottom = feather("FeatherTop", true), feather("FeatherBottom", false)

	local decorLayer = Instance.new("Frame")
	decorLayer.Name = "Decor"
	decorLayer.Size = UDim2.fromScale(1, 1)
	decorLayer.BackgroundTransparency = 1
	decorLayer.ZIndex = 40
	decorLayer.Parent = layer

	-- Region edges in canvas pixels: edges[i] = left of region i, edges[#REGIONS + 1] = canvasW.
	local function regionEdges(canvasW, nodeXs)
		return MapSeams.edges(REGIONS, canvasW, nodeXs)
	end

	-- One painted tile: a Crop image whose horizontal UIGradient mask fades it to the base on the sides that need it.
	local function paintTile(parent, name, image, x, w, canvasH, z, fadeL, fadeR)
		local img = Instance.new("ImageLabel")
		img.Name = name
		img.Position = UDim2.fromOffset(x, 0)
		img.Size = UDim2.fromOffset(w, canvasH)
		img.BackgroundTransparency = 1
		img.BorderSizePixel = 0
		img.Image = image
		img.ScaleType = Enum.ScaleType.Crop
		img.ZIndex = z
		img.Parent = parent
		local mask = Instance.new("UIGradient") -- the mask: smootherstep from clear to opaque, at least 8 keypoints per faded side
		mask.Transparency = maskSequence(RegionTiles.maskStops(w, fadeL, fadeR, 10))
		mask.Parent = img
		return img
	end

	-- The painted parchment countryside (map_paint parchment_map) covers the first screen, where the eight Nights are; it melts into the
	-- region paintings after it. Without the picture nothing here changes. Props are not drawn on top of it (it has its own scenery).
	local parchmentHolder = nil
	local parchmentW = 0
	-- the equipped Card Set's own painted ground (Engine/ThemeScenes "mapBackdrop", e.g. the ice map); nil for every other set keeps the parchment
	local function themedGround()
		local okId, id = pcall(function()
			local skin = require(script.Parent.HudTheme).skin()
			return require(game:GetService("ReplicatedStorage").Shared.Engine.ThemeScenes).themeImageId(skin and skin.id, "mapBackdrop")
		end)
		return okId and id or nil
	end
	local function layoutParchment(canvasW, canvasH, viewW)
		local id = themedGround() or ContentArt.getImageId("map_paint", "parchment_map")
		if not parchmentHolder then
			parchmentHolder = Instance.new("Frame")
			parchmentHolder.Name = "ParchmentPainting"
			parchmentHolder.BackgroundTransparency = 1
			parchmentHolder.BorderSizePixel = 0
			parchmentHolder.Active = false
			parchmentHolder.ZIndex = Z_PAINTING -- created after the region holders, so it draws above them; below the roads and nodes
			parchmentHolder.Parent = layer
		end
		parchmentHolder:ClearAllChildren()
		parchmentW = 0
		if not id then return end
		local w = math.floor(math.min(canvasW, math.max(viewW or 0, 1)))
		parchmentW = w
		parchmentHolder.Position, parchmentHolder.Size = UDim2.fromOffset(0, 0), UDim2.fromOffset(w, canvasH)
		local melt = w < canvasW and math.floor(math.min(w * 0.12, 240)) or 0
		local img = paintTile(parchmentHolder, "Parchment", id, 0, w, canvasH, Z_PAINTING, 0, melt)
		img.ScaleType = Enum.ScaleType.Stretch -- the whole picture across the first screen, nothing cropped
	end

	local function layout(canvasW, canvasH, topLimit, bottomLimit, nodeXs, viewW)
		local edges = regionEdges(canvasW, nodeXs)
		local joinW = {} -- joinW[i] = width of the cross-fade zone between region i-1 and i, centred on edges[i]
		for i = 2, #REGIONS do
			joinW[i] = MapSeams.joinWidth(edges[i] - edges[i - 1], edges[i + 1] - edges[i])
		end
		base.Size = UDim2.fromOffset(math.floor(canvasW), canvasH)
		-- Decorative ramp: a failure here must never stop the painted regions below from drawing.
		local okRamp, rampErr = pcall(function()
			local keypoints = {}
			for _, stop in ipairs(MapSeams.underlayStops(REGIONS, edges, canvasW)) do
				keypoints[#keypoints + 1] = ColorSequenceKeypoint.new(stop.t, Color3.fromRGB(stop.r, stop.g, stop.b))
			end
			if #keypoints >= 2 then baseRamp.Color = ColorSequence.new(keypoints) end
		end)
		if not okRamp then warn("[JourneyMapScenery] colour ramp failed: " .. tostring(rampErr)) end
		local featherH = math.floor(canvasH * 0.14)
		featherTop.Position, featherTop.Size = UDim2.fromOffset(0, 0), UDim2.fromOffset(math.floor(canvasW), featherH)
		featherBottom.Position, featherBottom.Size = UDim2.fromOffset(0, canvasH - featherH), UDim2.fromOffset(math.floor(canvasW), featherH)
		for i, holder in ipairs(regionHolders) do
			holder:ClearAllChildren()
			-- A region's painting runs half a join past each of its edges; the later painting fades in over the earlier one.
			local x0 = math.floor(edges[i] - (i > 1 and joinW[i] / 2 or 0))
			local x1 = math.floor(edges[i + 1] + (i < #REGIONS and joinW[i + 1] / 2 or 0))
			local w = x1 - x0
			holder.Position = UDim2.fromOffset(x0, 0)
			holder.Size = UDim2.fromOffset(w, canvasH)
			local image = regionIds[i] or fallbackIds[i]
			if image then
				local outerFade = math.floor(math.min(w * 0.25, 360)) -- canvas ends melt into the parchment too
				local tiles = REGIONS[i].single and 1 or RegionTiles.tiled(w, canvasH, ART_ASPECT)
				local nomW = math.ceil(w / tiles)
				local FW = tiles > 1 and math.floor(math.min(160, nomW * 0.2)) or 0
				for t = 1, tiles do
					local tx0 = math.floor((t - 1) * w / tiles) - (t > 1 and FW or 0)
					local tx1 = math.min(w, math.floor(t * w / tiles) + 1)
					local fadeL = (t > 1 and FW) or (i > 1 and joinW[i]) or outerFade
					local fadeR = (i == #REGIONS and t == tiles) and outerFade or 0
					-- The ZIndex was the tile number (1, 2, ...): absolute under Global, so every painting drew under ParchmentBase.
					paintTile(holder, "Tile" .. t, image, tx0, tx1 - tx0, canvasH, Z_PAINTING, fadeL, fadeR)
				end
			end
		end

		layoutParchment(canvasW, canvasH, viewW)
		decorLayer:ClearAllChildren()
		local size = math.floor(math.clamp(canvasH * 0.13, 64, 112))
		local topRoom = topLimit - size - 12
		-- props stay above the bottom feather so none is cut off or fades into a hard-edged square
		local propFloor = canvasH - math.floor(canvasH * 0.14) - 8
		local bottomRoom = propFloor - size - bottomLimit
		local placed = 0
		for r, region in ipairs(REGIONS) do
			-- About one doodle per 330px of region, at least one per region.
			local rw = edges[r + 1] - edges[r]
			local count = math.max(1, math.floor(rw / 330))
			for j = 1, count do
				placed = placed + 1
				local i = placed
				local key = region.decor[((j - 1) % #region.decor) + 1]
				local id = PropRules.isDrawable(key) and ContentArt.getImageId("map_decor", key) or nil
				local onTop = (i % 2 == 1)
				local room = onTop and topRoom or bottomRoom
				if id and room >= 0 then
					local jitterX = (((i * 7919) % 101) - 50) / 50 * 40
					local x = edges[r] + (j - 0.5) * rw / count + jitterX
					if x < parchmentW + size then id = nil end -- the parchment painting has its own trees and buildings
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
					img.ZIndex = Z_DECOR -- absolute: the layer's own ZIndex is not inherited
					img.Parent = decorLayer
					bindLandmark(img, key, r) -- no rounded corner or stroke: they drew the prop's art as a hard-edged square
				end
			end
		end
		-- shared prop on each seam line (a sign or lantern post straddling the join)
		for i = 2, #REGIONS do
			local key = (i % 2 == 0) and "signpost" or "lantern_post"
			local id = PropRules.isDrawable(key) and ContentArt.getImageId("map_decor", key) or nil
			if id and edges[i] >= parchmentW + size and bottomLimit + 6 + size <= propFloor then
				local img = Instance.new("ImageLabel")
				img.Name = "Seam_" .. key
				img.AnchorPoint = Vector2.new(0.5, 0)
				img.Position = UDim2.fromOffset(math.floor(edges[i]), math.floor(bottomLimit + 6))
				img.Size = UDim2.fromOffset(size, size)
				img.BackgroundTransparency = 1
				img.Image = id
				img.ImageTransparency = 0.2
				img.ScaleType = Enum.ScaleType.Fit
				img.ZIndex = Z_DECOR + 1
				img.Parent = decorLayer
				bindLandmark(img, key, i)
			end
		end
	end

	-- Studio only, once per Play: the live ZIndex of every map layer in one Output line, so a layering mistake is one look away.
	-- layers=ok means every painting is above ParchmentBase and below WorldGraph (the roads, labels and nodes).
	local reported = false
	local function reportLayers()
		if reported then
			return
		end
		local okRun, studio = pcall(function()
			return game:GetService("RunService"):IsStudio()
		end)
		if not (okRun and studio) then
			return
		end
		reported = true
		local function zOf(name)
			local inst = canvas:FindFirstChild(name)
			return inst and math.floor(inst.ZIndex) or nil
		end
		local tiles, lowest, highest = {}, math.huge, -math.huge
		for _, holder in ipairs(regionHolders) do
			for _, tile in ipairs(holder:GetChildren()) do
				local z = math.floor(tile.ZIndex)
				tiles[#tiles + 1] = string.format("%s.%s=%d", holder.Name, tile.Name, z)
				lowest, highest = math.min(lowest, z), math.max(highest, z)
			end
		end
		local graphZ = zOf("WorldGraph")
		local verdict = "no paintings"
		if #tiles > 0 then
			verdict = (graphZ ~= nil and lowest > base.ZIndex and highest < graphZ) and "ok" or "WRONG"
		end
		warn(string.format("[TavernMap z] v1 ParchmentBase=%d tiles(%s) WorldGraph=%s Discoveries=%s FogBand=%s FeatherTop=%d layers=%s",
			math.floor(base.ZIndex), table.concat(tiles, " "), tostring(graphZ), tostring(zOf("Discoveries")), tostring(zOf("FogBand")),
			math.floor(featherTop.ZIndex), verdict))
	end

	-- equip, Preview start and Preview stop redraw the ground with the last layout arguments
	local rawLayout, lastArgs = layout, nil
	layout = function(...)
		lastArgs = table.pack(...)
		return rawLayout(...)
	end
	pcall(function()
		require(script.Parent.HudTheme).onSkin(function()
			if lastArgs then pcall(rawLayout, table.unpack(lastArgs, 1, lastArgs.n)) end
		end)
	end)

	return {
		layout = layout,
		reportLayers = reportLayers,
		-- The view tells the scenery where the fog starts so hidden landmarks only say "???".
		setFogEdge = function(x) fogEdge = x end,
	}
end
