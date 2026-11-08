--[[
	Client/JourneyMapScenery.lua
	Backdrop for the Journey map canvas: three painted regions side by side
	(ContentArt map_regions: orchard, village, peaks), soft fog bands over the
	seams, and map_decor doodles scattered in the empty bands above and below
	the trail. Without region art each region is a flat parchment tint; decor
	without art is simply skipped. Decor positions come from a fixed formula
	of the doodle's index, so they never shift between opens.

	deps: canvas (Frame), roundCorner, ContentArt

	Returns { layout = function(canvasW, canvasH, topLimit, bottomLimit) }
	topLimit = lowest y the top decor band may reach, bottomLimit = highest y
	of the bottom band (both from the node/label geometry).
]]

return function(deps)
	local canvas = deps.canvas
	local ContentArt = deps.ContentArt

	local REGIONS = {
		{ key = "region_orchard", tint = Color3.fromRGB(214, 196, 148) },
		{ key = "region_village", tint = Color3.fromRGB(208, 192, 154) },
		{ key = "region_peaks", tint = Color3.fromRGB(196, 190, 170) },
	}
	-- Compass first, then the rest in a fixed order.
	local DECOR = { "compass_rose", "pine_tree", "cottage", "windmill", "signpost", "bridge", "mushroom_ring", "lantern_post" }
	local SEAM_FOG = Color3.fromRGB(240, 228, 204)
	local SEAM_STEPS = { 0.9, 0.78, 0.66, 0.78, 0.9 } -- stepped transparency, never a gradient

	local layer = Instance.new("Frame")
	layer.Name = "Scenery"
	layer.Size = UDim2.fromScale(1, 1)
	layer.BackgroundTransparency = 1
	layer.ZIndex = 22
	layer.Parent = canvas

	local regionFrames = {}
	for i, region in ipairs(REGIONS) do
		local f = Instance.new("Frame")
		f.Name = "Region" .. i
		f.BackgroundColor3 = region.tint
		f.BorderSizePixel = 0
		f.ZIndex = 22
		f.Parent = layer
		local id = ContentArt.getImageId("map_regions", region.key)
		if id then
			local img = Instance.new("ImageLabel")
			img.Size = UDim2.fromScale(1, 1)
			img.BackgroundTransparency = 1
			img.Image = id
			img.ScaleType = Enum.ScaleType.Crop
			img.ZIndex = 22
			img.Parent = f
		end
		regionFrames[i] = f
	end

	local seams = {}
	for s = 1, #REGIONS - 1 do
		local band = Instance.new("Frame")
		band.Name = "SeamFog" .. s
		band.BackgroundTransparency = 1
		band.ZIndex = 24
		band.Parent = layer
		for i, tr in ipairs(SEAM_STEPS) do
			local strip = Instance.new("Frame")
			strip.Size = UDim2.new(1 / #SEAM_STEPS, 0, 1, 0)
			strip.Position = UDim2.fromScale((i - 1) / #SEAM_STEPS, 0)
			strip.BackgroundColor3 = SEAM_FOG
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

	local function layout(canvasW, canvasH, topLimit, bottomLimit)
		local regionW = canvasW / #REGIONS
		for i, f in ipairs(regionFrames) do
			f.Position = UDim2.fromOffset(math.floor((i - 1) * regionW), 0)
			f.Size = UDim2.fromOffset(math.ceil(regionW) + 1, canvasH)
		end
		local seamW = math.floor(math.clamp(regionW * 0.12, 120, 260))
		for s, band in ipairs(seams) do
			band.Position = UDim2.fromOffset(math.floor(s * regionW - seamW / 2), 0)
			band.Size = UDim2.fromOffset(seamW, canvasH)
		end

		decorLayer:ClearAllChildren()
		local size = math.floor(math.clamp(canvasH * 0.13, 64, 112))
		local count = math.max(1, math.floor(canvasW / 330))
		local topRoom = topLimit - size - 12
		local bottomRoom = canvasH - size - 12 - bottomLimit
		for i = 1, count do
			local key = DECOR[1]
			if i > 1 then
				key = DECOR[2 + ((i - 2) * 3) % (#DECOR - 1)]
			end
			local id = ContentArt.getImageId("map_decor", key)
			local onTop = (i % 2 == 1)
			local room = onTop and topRoom or bottomRoom
			if id and room >= 0 then
				local jitterX = (((i * 7919) % 101) - 50) / 50 * 60
				local x = (i - 0.5) * canvasW / count + jitterX
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

	return { layout = layout }
end
