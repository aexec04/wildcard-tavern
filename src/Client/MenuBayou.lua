--[[
	Client/MenuBayou.lua
	The bayou backdrop for the Menu: a stilt tavern over misty water at golden hour, drawn as separate parallax layers (numbers in
	Engine/MenuLayout.Bayou, art in Engine/BayouArt). UI only. Active only when the sky art is recorded; with no art the Menu keeps
	the painted tavern wall, so nothing is ever blank. Layer order, back to front: sky, far trees, water, tavern on stilts, boat and
	post, mist, cypress knees, willow foreground. All layers share ZIndex 10 and stack by creation order.

	Life (11 animated objects, all off under calm mode): water shimmer (UIGradient Offset), drifting mist, tavern window glow pulse,
	rowboat bob (3 px, 4 s sine), willow moss sway (1 degree), 6 fireflies on slow drifts.

	build(parent) returns { active, layers = { { inst, base, px } }, update(nx, ny, t, calm), animatedCount }
	Menu adds `layers` to MenuParallax and calls update from the same frame step (layer.base is mutated by the bob and drift).
]]

local Layout = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("MenuLayout"))
local ContentArt = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("ContentArt"))

local MenuBayou = {}

function MenuBayou.build(parent)
	local B = Layout.Bayou
	local scale = Layout.Parallax.backdropScale
	local scene = { active = false, layers = {}, animatedCount = 0 }
	local container = Instance.new("Frame")
	container.Name = "BayouScene"
	container.Size = UDim2.fromScale(1, 1)
	container.BackgroundTransparency = 1
	container.Active = false
	container.ClipsDescendants = true
	container.ZIndex = 10
	container.Visible = false
	container.Parent = parent

	local byKey = {}
	for _, def in ipairs(B.layers) do
		local art = ContentArt.getImageId("menu_bayou", def.id)
		local img = Instance.new("ImageLabel")
		img.Name = "Bayou_" .. def.key
		img.AnchorPoint = Vector2.new(0.5, 0.5)
		local base = UDim2.fromScale(def.x, def.y)
		img.Position = base
		img.Size = def.bleed and UDim2.fromScale(def.w * scale, def.h * scale) or UDim2.fromScale(def.w, def.h)
		img.BackgroundTransparency = 1
		img.BorderSizePixel = 0
		img.ScaleType = (def.key == "sky" or def.key == "water") and Enum.ScaleType.Crop or Enum.ScaleType.Fit
		img.Active = false
		img.ZIndex = 10
		if art then img.Image = art end
		img.Visible = art ~= nil
		img.Parent = container
		local layer = { inst = img, base = base, px = def.px, baseX = def.x, baseY = def.y }
		byKey[def.key] = layer
		table.insert(scene.layers, layer)
	end
	scene.active = byKey.sky.inst.Visible
	container.Visible = scene.active
	if not scene.active then return scene end

	-- the mist ribbon is pink from its cutout: warm it to cream and keep it soft
	local mist = byKey.mist.inst
	local mt = Layout.Bayou.mistTint
	mist.ImageColor3 = Color3.fromRGB(mt[1], mt[2], mt[3])
	mist.ImageTransparency = 0.35

	-- water shimmer: a light warm gradient whose Offset slides (Color stops only, never Transparency)
	local waterGrad = Instance.new("UIGradient")
	waterGrad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(235, 225, 205)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(235, 225, 205)),
	})
	waterGrad.Parent = byKey.water.inst
	scene.animatedCount += 1

	-- tavern window glow: a soft amber frame over the lit windows, a child of the tavern so it moves with it
	local G = Layout.Bayou.windowGlow
	local glow = Instance.new("Frame")
	glow.Name = "WindowGlow"
	glow.AnchorPoint = Vector2.new(0.5, 0.5)
	glow.Position = UDim2.fromScale(G.x, G.y)
	glow.Size = UDim2.fromScale(G.w, G.h)
	glow.BackgroundColor3 = Color3.fromRGB(255, 170, 70)
	glow.BackgroundTransparency = 0.88
	glow.BorderSizePixel = 0
	glow.Active = false
	glow.ZIndex = 10
	glow.Parent = byKey.tavern.inst
	local gc = Instance.new("UICorner")
	gc.CornerRadius = UDim.new(0.5, 0)
	gc.Parent = glow
	scene.animatedCount += 3 -- mist drift, rowboat bob and moss sway share the count with the glow below
	scene.animatedCount += 1 -- window glow

	-- fireflies: small warm dots on slow drifts, over the water and under the foreground
	local flies = {}
	for i = 1, Layout.Bayou.fireflies do
		local f = Instance.new("Frame")
		f.Name = "Firefly"
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Size = UDim2.fromOffset(4 + i % 2 * 2, 4 + i % 2 * 2)
		f.BackgroundColor3 = Color3.fromRGB(255, 240, 150)
		f.BackgroundTransparency = 0.2
		f.BorderSizePixel = 0
		f.Active = false
		f.ZIndex = 10
		f.Parent = container
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(1, 0)
		c.Parent = f
		flies[i] = { frame = f, fx = 0.12 + (i * 0.153) % 0.76, fy = 0.38 + (i * 0.11) % 0.34, phase = i * 1.9, speed = 0.15 + (i % 3) * 0.05 }
	end
	scene.animatedCount += #flies

	-- dark translucent backing so the title and the counter panels stay readable on the bright sky and water
	local function scrim(name, y, h)
		local s = Instance.new("Frame")
		s.Name = name
		s.Position = UDim2.fromScale(0, y)
		s.Size = UDim2.fromScale(1, h)
		s.BackgroundColor3 = Color3.fromRGB(14, 18, 16)
		s.BackgroundTransparency = Layout.Bayou.scrim
		s.BorderSizePixel = 0
		s.Active = false
		s.ZIndex = 10
		s.Parent = container
	end
	scrim("TitleScrim", 0, 0.22)
	scrim("CounterScrim", Layout.Counter.top, 1 - Layout.Counter.top)

	local boat, mistLayer, willow = byKey.boat, byKey.mist, byKey.willow
	function scene.update(_nx, _ny, t, calm)
		for _, f in ipairs(flies) do f.frame.Visible = not calm end
		if calm then
			waterGrad.Offset = Vector2.new(0, 0)
			willow.inst.Rotation = 0
			boat.base = UDim2.fromScale(boat.baseX, boat.baseY)
			mistLayer.base = UDim2.fromScale(mistLayer.baseX, mistLayer.baseY)
			glow.BackgroundTransparency = 0.86
			return
		end
		waterGrad.Offset = Vector2.new(math.sin(t * 0.18) * 0.35, 0)
		mistLayer.base = UDim2.new(mistLayer.baseX + math.sin(t * 0.05) * 0.06, 0, mistLayer.baseY, math.sin(t * 0.3) * 3)
		boat.base = UDim2.new(boat.baseX, 0, boat.baseY, math.sin(t * math.pi * 2 / 4) * 3)
		glow.BackgroundTransparency = 0.86 + math.sin(t * 1.3) * 0.05
		willow.inst.Rotation = math.sin(t * 0.6) * 1
		for _, f in ipairs(flies) do
			f.frame.Position = UDim2.fromScale(f.fx + math.sin(t * f.speed + f.phase) * 0.04, f.fy + math.cos(t * f.speed * 0.7 + f.phase) * 0.03)
			f.frame.BackgroundTransparency = 0.25 + (math.sin(t * 1.1 + f.phase * 2) * 0.5 + 0.5) * 0.6
		end
	end

	return scene
end

return MenuBayou
