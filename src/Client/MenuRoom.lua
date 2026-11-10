--[[
	Client/MenuRoom.lua
	The Tavern Room Menu: ONE painted tavern interior (menu_room_scene, 1536x1024) fills the whole Menu, cover-cropped and centred,
	never stretched, no frame. The props in the picture are the buttons (hotspots are rectangles of the picture, Engine/MenuRoomLayout).
	Without the Image id a code-drawn room stands in: dark wood wall, plank floor, window, fireplace, counter and a felt table, and
	the hotspots draw as plates (MenuHotspots reads Layout.roomPainted).

	Life, all off in calm mode, eight kinds, one update: fire glow, two lantern halos, motes, two candle flames, window stars, jukebox
	notes, a coin glint and the pulse ring on the deck. Everything lives in a picture-sized host so it follows the crop.

	build(parent) returns { active = true, layers = {}, animatedCount, update(nx, ny, t, calm) }.
]]

local Engine = game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine")
local RL = require(Engine:WaitForChild("MenuRoomLayout"))
local ContentArt = require(Engine:WaitForChild("ContentArt"))

local MenuRoom = {}

local function frame(parent, name, color, transparency)
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundColor3 = color
	f.BackgroundTransparency = transparency or 0
	f.BorderSizePixel = 0
	f.Active = false
	f.ZIndex = 10
	f.Parent = parent
	return f
end

local function round(inst, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = radius
	c.Parent = inst
end

-- A frame over a picture rectangle { l, t, r, b } (fractions of the host).
local function over(parent, name, color, r, transparency)
	local f = frame(parent, name, color, transparency)
	f.Position = UDim2.fromScale(r.l, r.t)
	f.Size = UDim2.fromScale(r.r - r.l, r.b - r.t)
	return f
end

local function disc(parent, name, color, cx, cy, w, h, transparency)
	local g = frame(parent, name, color, transparency)
	g.AnchorPoint = Vector2.new(0.5, 0.5)
	g.Position = UDim2.fromScale(cx, cy)
	g.Size = UDim2.fromScale(w, h)
	round(g, UDim.new(0.5, 0))
	return g
end

local function gradient(inst, top, bottom)
	local g = Instance.new("UIGradient")
	g.Rotation = 90
	g.Color = ColorSequence.new(top, bottom)
	g.Parent = inst
end

-- Code-drawn room used until menu_room_scene has an Image id. Colour only; the hotspot plates stand in for the props.
local function drawFallback(host)
	local wall = frame(host, "Wall", Color3.fromRGB(86, 58, 38))
	wall.Size = UDim2.fromScale(1, 1)
	gradient(wall, Color3.fromRGB(58, 38, 26), Color3.fromRGB(104, 72, 46))
	over(host, "BeamTop", Color3.fromRGB(46, 30, 20), { l = 0, t = 0, r = 1, b = 0.07 })
	local win = over(host, "Window", Color3.fromRGB(28, 40, 84), RL.windowRect)
	local rim = Instance.new("UIStroke")
	rim.Color = Color3.fromRGB(54, 36, 22)
	rim.Thickness = 5
	rim.Parent = win
	over(host, "Fireplace", Color3.fromRGB(96, 90, 82), { l = 0.04, t = 0.30, r = 0.17, b = 0.62 })
	over(host, "FireOpening", Color3.fromRGB(40, 24, 16), RL.fireRect)
	over(host, "BarTop", Color3.fromRGB(128, 86, 48), { l = 0.2, t = 0.50, r = 0.80, b = 0.53 })
	over(host, "BarFront", Color3.fromRGB(82, 54, 32), { l = 0.2, t = 0.53, r = 0.80, b = 0.62 })
	local floor = over(host, "Floor", Color3.fromRGB(70, 46, 30), { l = 0, t = 0.82, r = 1, b = 1 })
	gradient(floor, Color3.fromRGB(86, 58, 38), Color3.fromRGB(48, 32, 22))
	local P = RL.pic.play
	local felt = over(host, "Felt", Color3.fromRGB(46, 110, 62), { l = P.l + 0.04, t = P.t + 0.07, r = P.r - 0.04, b = P.b - 0.06 })
	round(felt, UDim.new(0.5, 0))
	local feltRim = Instance.new("UIStroke")
	feltRim.Color = Color3.fromRGB(120, 78, 44)
	feltRim.Thickness = 6
	feltRim.Parent = felt
	round(over(host, "Deck", Color3.fromRGB(176, 66, 52), RL.deck), UDim.new(0.1, 0))
	return wall
end

function MenuRoom.build(parent)
	local scene = { active = true, layers = {}, animatedCount = 0 }
	local container = Instance.new("Frame")
	container.Name = "RoomScene"
	container.Size = UDim2.fromScale(1, 1)
	container.BackgroundColor3 = Color3.fromRGB(30, 20, 14)
	container.BorderSizePixel = 0
	container.Active = false
	container.ClipsDescendants = true
	container.ZIndex = 10
	container.Parent = parent

	-- the picture host: the picture's aspect, scaled to cover the screen and centred, so everything inside follows the crop
	local host = Instance.new("Frame")
	host.Name = "Picture"
	host.AnchorPoint = Vector2.new(0.5, 0.5)
	host.Position = UDim2.fromScale(0.5, 0.5)
	host.Size = UDim2.fromScale(1, 1)
	host.BackgroundTransparency = 1
	host.BorderSizePixel = 0
	host.Active = false
	host.ZIndex = 10
	host.Parent = container
	local function fit()
		local sz = container.AbsoluteSize
		if sz.X < 1 or sz.Y < 1 then return end
		local pw, ph = RL.cover(sz.X, sz.Y)
		host.Size = UDim2.fromOffset(math.ceil(pw), math.ceil(ph))
	end
	container:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	fit()

	local sceneArt = ContentArt.getImageId("menu_scene", RL.SCENE_KEY)
	scene.painted = sceneArt ~= nil
	if sceneArt then
		local img = Instance.new("ImageLabel")
		img.Name = "Scene"
		img.BackgroundTransparency = 1
		img.BorderSizePixel = 0
		img.Image = sceneArt
		img.ScaleType = Enum.ScaleType.Stretch -- the host already has the picture's aspect
		img.Size = UDim2.fromScale(1, 1)
		img.Active = false
		img.ZIndex = 10
		img.Parent = host
	else
		drawFallback(host)
	end

	-- life: the eight kinds below (fire, lanterns, motes, candles, stars, notes, glint, deck ring)
	local F = RL.fireRect
	local fireGlow = disc(host, "FireGlow", Color3.fromRGB(255, 150, 60), (F.l + F.r) / 2, (F.t + F.b) / 2, F.r - F.l, F.b - F.t, 0.85)
	local lanternGlows = {}
	for i, r in ipairs(RL.lanternRects) do
		lanternGlows[i] = disc(host, "LanternGlow" .. i, Color3.fromRGB(255, 190, 90), (r.l + r.r) / 2, (r.t + r.b) / 2, (r.r - r.l) * 1.6, (r.b - r.t) * 1.2, 0.86)
	end
	local motes = {}
	for i = 1, RL.motes do
		motes[i] = disc(host, "Mote", Color3.fromRGB(255, 214, 140), 0.1, 0.4, 0.004, 0.006, 0.3)
	end
	local flames = {}
	for i, c in ipairs(RL.candles) do
		flames[i] = disc(host, "Flame" .. i, Color3.fromRGB(255, 200, 100), c.x, c.y, 0.008, 0.016, 0.2)
	end
	local stars = {}
	for i, p in ipairs(RL.stars) do
		stars[i] = disc(host, "Star" .. i, Color3.fromRGB(255, 250, 225), p[1], p[2], 0.004, 0.006, 0.4)
	end
	local notes = {}
	for i = 1, 2 do
		notes[i] = disc(host, "Note", Color3.fromRGB(255, 240, 200), RL.jukeTop.x, RL.jukeTop.y, 0.007, 0.012, 1)
	end
	local jg = RL.jarGlint
	local glint = frame(host, "CoinGlint", Color3.fromRGB(255, 250, 220), 1)
	glint.AnchorPoint = Vector2.new(0.5, 0.5)
	glint.Position = UDim2.fromScale(jg.x, jg.y)
	glint.Size = UDim2.fromOffset(10, 10)
	glint.Rotation = 45
	local ring = over(host, "DeckRing", Color3.fromRGB(255, 220, 140), RL.deck, 1)
	round(ring, UDim.new(0.3, 0))
	local ringStroke = Instance.new("UIStroke")
	ringStroke.Color = Color3.fromRGB(255, 220, 140)
	ringStroke.Thickness = 2
	ringStroke.Transparency = 1
	ringStroke.Parent = ring
	scene.animatedCount = RL.ambientKinds

	-- soft dark plate behind the title at the top centre, over the ceiling beams: eight thin steps that fade out, no band edge
	do
		local steps, height = 8, 0.16
		for i = 1, steps do
			local step = frame(container, "TitleScrim" .. i, Color3.fromRGB(14, 10, 6), 0.7 + (i - 1) * 0.04)
			step.Size = UDim2.fromScale(1, height * (steps - i + 1) / steps)
		end
	end

	function scene.update(_nx, _ny, t, calm)
		for _, list in ipairs({ motes, flames, stars, notes }) do
			for _, o in ipairs(list) do o.Visible = not calm end
		end
		glint.Visible = not calm
		ring.Visible = not calm
		if calm then
			fireGlow.BackgroundTransparency = 0.85
			for _, g in ipairs(lanternGlows) do g.BackgroundTransparency = 0.86 end
			return
		end
		fireGlow.BackgroundTransparency = 0.85 + RL.flickerAt(t) * 0.5
		for i, g in ipairs(lanternGlows) do
			g.BackgroundTransparency = 0.86 + math.sin(t * 0.7 + i * 2.4) * 0.03 -- slow breathing halo
		end
		for i, m in ipairs(motes) do
			local x, y, a = RL.moteAt(i, t)
			m.Position = UDim2.fromScale(x, y)
			m.BackgroundTransparency = 0.9 - a * 0.6
		end
		for i, f in ipairs(flames) do
			f.BackgroundTransparency = 0.2 + (math.sin(t * 7 + i * 3) * 0.5 + 0.5) * 0.25
		end
		for i, s in ipairs(stars) do
			s.BackgroundTransparency = 0.4 + (math.sin(t * 1.3 + i * 2) * 0.5 + 0.5) * 0.5
		end
		for i, n in ipairs(notes) do
			local k = (t / 3 + (i - 1) * 0.5) % 1 -- two notes, each rising over 3 s then resting
			n.Position = UDim2.fromScale(RL.jukeTop.x + math.sin(t + i * 2) * 0.008, RL.jukeTop.y - k * 0.06)
			n.BackgroundTransparency = 0.4 + k * 0.6
		end
		local g = RL.glintAt(t)
		glint.BackgroundTransparency = g == 0 and 1 or 1 - math.sin(g * math.pi) * 0.9
		ringStroke.Transparency = 0.55 + math.sin(t * 2.2) * 0.3
	end

	scene.update(0, 0, 0, false)
	return scene
end

return MenuRoom
