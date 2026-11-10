--[[
	Client/ShopBackdrop.lua
	Counter v2 back layers for the Shop overlay: the painted back bar wall filling the area, a smooth dark vignette
	(same technique as BossFight), a warm light pool, the counter top across the lower band and four counter props.
	Look only, static (no loops, so calm mode needs nothing). Every piece is skipped when its Image id is missing; the
	whole backdrop only mounts when shop_wall has an id, so until the art is recorded the Shop looks exactly as before.
	Geometry comes from Engine/ShopSceneLayout.lua. Everything sits at ZIndex 5 under the offer cards and controls.

	ShopBackdrop.new({ shopFrame }) -> { active, root, relayout }   (nil when the art is not recorded yet)
]]

local Engine = game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine")
local Layout = require(Engine:WaitForChild("ShopSceneLayout"))
local ContentArt = require(Engine:WaitForChild("ContentArt"))

local ShopBackdrop = {}

local function image(parent, name, id, z)
	local img = Instance.new("ImageLabel")
	img.Name = name
	img.BackgroundTransparency = 1
	img.BorderSizePixel = 0
	img.Image = id
	img.Active = false
	img.ZIndex = z or 5
	img.Parent = parent
	return img
end

-- Crop a fraction rect { x, y, w, h } of a 3:2 picture (ImageRect needs the picture's pixel size; the generator
-- writes 1536x1024 for these pieces).
local function crop(img, c)
	img.ScaleType = Enum.ScaleType.Stretch
	img.ImageRectOffset = Vector2.new(c[1] * 1536, c[2] * 1024)
	img.ImageRectSize = Vector2.new(c[3] * 1536, c[4] * 1024)
end

local function place(obj, r)
	obj.Position = UDim2.fromOffset(r.x, r.y)
	obj.Size = UDim2.fromOffset(r.w, r.h)
end

function ShopBackdrop.new(deps)
	local shopFrame = deps.shopFrame
	local wallId = ContentArt.getImageId("shop_scene", "shop_wall")
	if not wallId then
		return nil
	end
	local topId = ContentArt.getImageId("shop_scene", "shop_counter_top")
	local propsId = ContentArt.getImageId("shop_scene", "shop_counter_props")
	local self = { active = true }

	local root = Instance.new("Frame")
	root.Name = "ShopBackdrop"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1
	root.Active = false
	root.ZIndex = 5
	root.ClipsDescendants = true
	root.Parent = shopFrame
	self.root = root

	local wall = image(root, "Wall", wallId, 5)
	wall.Size = UDim2.fromScale(1, 1)
	wall.ScaleType = Enum.ScaleType.Crop

	-- Smooth vignette: one gradient frame per edge, no stacked bands.
	require(script.Parent.SmoothVignette).build(root, {
		name = "Vignette", zIndex = 5, color = Color3.fromRGB(14, 8, 4),
		top = { strength = 0.59, extent = 0.1 },
		left = { strength = 0.59, extent = 0.06 },
		right = { strength = 0.59, extent = 0.06 },
	})

	local light = Instance.new("Frame")
	light.Name = "LightPool"
	light.BackgroundColor3 = Color3.fromRGB(255, 196, 110)
	light.BackgroundTransparency = 0.9
	light.BorderSizePixel = 0
	light.Active = false
	light.ZIndex = 5
	light.Parent = root
	do
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0.5, 0)
		c.Parent = light
	end

	local counter = topId and image(root, "CounterTop", topId, 5) or nil
	if counter then
		crop(counter, Layout.COUNTER_CROP)
	end
	local props = {}
	if propsId then
		for name in pairs(Layout.PROP_CROP) do
			local img = image(root, "Prop_" .. name, propsId, 5)
			crop(img, Layout.PROP_CROP[name])
			props[name] = img
		end
	end

	function self.relayout()
		local size = shopFrame.AbsoluteSize
		if size.X < 1 or size.Y < 1 then
			return
		end
		local r = Layout.rects(size.X, size.Y)
		place(light, r.light)
		if counter then
			place(counter, r.counter)
		end
		for name, img in pairs(props) do
			if r.props[name] then
				place(img, r.props[name])
				img.Visible = true
			else
				img.Visible = false
			end
		end
	end
	shopFrame:GetPropertyChangedSignal("AbsoluteSize"):Connect(self.relayout)
	self.relayout()
	return self
end

return ShopBackdrop
