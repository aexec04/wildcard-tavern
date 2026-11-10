--[[
	Client/MenuWorld.lua
	The Living Map Menu: a painted slice of the Tavern Map under the Menu's buttons. Numbers in Engine/MenuWorldLayout (tested),
	painted pieces from Engine/MenuWorldArt (category menu_world). UI only. Every piece has a code-drawn fallback, so the scene
	looks fine before any art is recorded: a meadow ground, a block tavern with a glowing door, a dirt road, a parchment border.

	Motion: everything that belongs to the map lives in ONE `World` frame and only that frame moves (a tiny pan and 1 percent zoom
	breath over 40 s), so no landmark slides against another. Local life only: chimney smoke, door glow, cloud shadows, fireflies,
	the hero token walking the road out and back every 30 s. Calm mode holds the map still and hides the life.

	build(parent) returns { active = true, layers = {}, update(nx, ny, t, calm), animatedCount, world }.
	Buttons, plates and scrolls are not here: Client/MenuHotspots places them at the landmark spots (MenuWorldLayout.apply).
]]

local Engine = game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine")
local WL = require(Engine:WaitForChild("MenuWorldLayout"))
local ContentArt = require(Engine:WaitForChild("ContentArt"))

local MenuWorld = {}

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

local function image(parent, name, art, scaleType)
	local img = Instance.new("ImageLabel")
	img.Name = name
	img.BackgroundTransparency = 1
	img.BorderSizePixel = 0
	img.Image = art
	img.ScaleType = scaleType or Enum.ScaleType.Fit
	img.Active = false
	img.ZIndex = 10
	img.Parent = parent
	return img
end

-- A box centred at (x, y) that keeps an aspect ratio inside a height fraction (the same trick the hotspot frames use).
local function aspectBox(parent, name, x, y, h, asp)
	local box = Instance.new("Frame")
	box.Name = name
	box.AnchorPoint = Vector2.new(0.5, 0.5)
	box.Position = UDim2.fromScale(x, y)
	box.Size = UDim2.fromScale(1, h)
	box.BackgroundTransparency = 1
	box.Active = false
	box.ZIndex = 10
	box.Parent = parent
	local a = Instance.new("UIAspectRatioConstraint")
	a.AspectRatio = asp
	a.Parent = box
	return box
end

function MenuWorld.build(parent)
	local scene = { active = true, layers = {}, animatedCount = 0 }
	local D = WL.drift
	local container = Instance.new("Frame")
	container.Name = "WorldScene"
	container.Size = UDim2.fromScale(1, 1)
	container.BackgroundColor3 = Color3.fromRGB(86, 120, 64)
	container.BorderSizePixel = 0
	container.Active = false
	container.ClipsDescendants = true
	container.ZIndex = 10
	container.Parent = parent

	local world = Instance.new("Frame")
	world.Name = "World"
	world.AnchorPoint = Vector2.new(0.5, 0.5)
	world.Position = UDim2.fromScale(0.5, 0.5)
	world.Size = UDim2.fromScale(D.baseZoom, D.baseZoom)
	world.BackgroundTransparency = 1
	world.Active = false
	world.ZIndex = 10
	world.Parent = container
	scene.world = world
	scene.animatedCount += 1 -- the whole-scene drift

	-- ground: the Tavern Map meadow tile as one continuous painted floor, a flat green when the art is missing
	local ground = frame(world, "Ground", Color3.fromRGB(96, 132, 70))
	ground.Size = UDim2.fromScale(1, 1)
	local meadow = ContentArt.getImageId("map_regions", "region_meadow")
	if meadow then
		local img = image(ground, "Meadow", meadow, Enum.ScaleType.Crop)
		img.Size = UDim2.fromScale(1, 1)
	end

	-- road from the door toward the bottom
	local R = WL.road
	local roadArt = ContentArt.getImageId("menu_world", "menu_road_out")
	local road = aspectBox(world, "Road", R.x, R.y, R.h, R.asp)
	if roadArt then
		image(road, "Art", roadArt).Size = UDim2.fromScale(1, 1)
	else
		local dirt = frame(road, "Dirt", Color3.fromRGB(150, 112, 70))
		dirt.AnchorPoint = Vector2.new(0.5, 0.5)
		dirt.Position = UDim2.fromScale(0.5, 0.5)
		dirt.Size = UDim2.fromScale(0.26, 1)
		round(dirt, UDim.new(0.2, 0))
		local edge = Instance.new("UIStroke")
		edge.Color = Color3.fromRGB(110, 80, 48)
		edge.Thickness = 3
		edge.Parent = dirt
	end

	-- the tavern hub
	local H = WL.hub
	local hubArt = ContentArt.getImageId("menu_world", "menu_tavern_hub")
	local hub = aspectBox(world, "Hub", H.x, H.y, H.h, H.asp)
	if hubArt then
		image(hub, "Art", hubArt).Size = UDim2.fromScale(1, 1)
	else
		local body = frame(hub, "Body", Color3.fromRGB(122, 84, 52))
		body.AnchorPoint = Vector2.new(0.5, 1)
		body.Position = UDim2.fromScale(0.5, 0.95)
		body.Size = UDim2.fromScale(0.74, 0.5)
		round(body, UDim.new(0.06, 0))
		local roof = frame(hub, "Roof", Color3.fromRGB(150, 54, 44))
		roof.AnchorPoint = Vector2.new(0.5, 1)
		roof.Position = UDim2.fromScale(0.5, 0.5)
		roof.Size = UDim2.fromScale(0.86, 0.34)
		round(roof, UDim.new(0.3, 0))
		local chim = frame(hub, "Chimney", Color3.fromRGB(96, 84, 76))
		chim.AnchorPoint = Vector2.new(0.5, 1)
		chim.Position = UDim2.fromScale(0.68, 0.3)
		chim.Size = UDim2.fromScale(0.07, 0.2)
		local door = frame(hub, "Door", Color3.fromRGB(255, 190, 90))
		door.AnchorPoint = Vector2.new(0.5, 1)
		door.Position = UDim2.fromScale(0.5, 0.95)
		door.Size = UDim2.fromScale(0.14, 0.26)
		round(door, UDim.new(0.3, 0))
		for i = -1, 1, 2 do
			local win = frame(hub, "Window", Color3.fromRGB(255, 214, 130))
			win.AnchorPoint = Vector2.new(0.5, 0.5)
			win.Position = UDim2.fromScale(0.5 + i * 0.24, 0.68)
			win.Size = UDim2.fromScale(0.1, 0.14)
			round(win, UDim.new(0.2, 0))
		end
	end

	-- door glow: a soft warm halo that flickers
	local glow = frame(world, "DoorGlow", Color3.fromRGB(255, 176, 76), 0.82)
	glow.AnchorPoint = Vector2.new(0.5, 0.5)
	glow.Position = UDim2.fromScale(WL.door.x, WL.door.y)
	glow.Size = UDim2.fromScale(0.09, 0.14)
	round(glow, UDim.new(0.5, 0))
	scene.animatedCount += 1

	-- chimney smoke: three puffs rising and fading in a loop
	local puffs = {}
	for i = 1, 3 do
		local p = frame(world, "Smoke", Color3.fromRGB(235, 232, 226), 0.7)
		p.AnchorPoint = Vector2.new(0.5, 0.5)
		round(p, UDim.new(0.5, 0))
		puffs[i] = p
	end
	scene.animatedCount += 1

	-- cloud shadows: soft dark ellipses drifting across the ground (shadow only, never a bright cloud over the buttons)
	local wispArt = ContentArt.getImageId("menu_world", "menu_cloud_wisp")
	local clouds = {}
	for i = 1, WL.clouds do
		local c
		if wispArt then
			c = image(world, "CloudShadow", wispArt)
			c.ImageColor3 = Color3.fromRGB(20, 30, 24)
			c.ImageTransparency = 0.86
		else
			c = frame(world, "CloudShadow", Color3.fromRGB(20, 30, 24), 0.9)
			round(c, UDim.new(0.5, 0))
		end
		c.AnchorPoint = Vector2.new(0.5, 0.5)
		c.Size = UDim2.fromScale(0.26 + i * 0.04, 0.09)
		clouds[i] = { inst = c, y = 0.26 + i * 0.22, speed = 1 / (70 + i * 25), phase = i * 0.37 }
	end
	scene.animatedCount += 1

	-- a signpost beside the Notice Board, only when its art exists
	local postArt = ContentArt.getImageId("menu_world", "menu_notice_post")
	if postArt then
		local post = aspectBox(world, "NoticePost", 0.10, 0.68, 0.14, 0.8)
		image(post, "Art", postArt).Size = UDim2.fromScale(1, 1)
	end

	-- hero token: a small gold disc that walks the road out and back
	local hero = frame(world, "Hero", Color3.fromRGB(255, 214, 130))
	hero.AnchorPoint = Vector2.new(0.5, 0.5)
	hero.Size = UDim2.fromOffset(WL.hero.size, WL.hero.size)
	round(hero, UDim.new(0.5, 0))
	local heroRim = Instance.new("UIStroke")
	heroRim.Color = Color3.fromRGB(96, 60, 28)
	heroRim.Thickness = 2
	heroRim.Parent = hero
	local heroGlyph = Instance.new("TextLabel")
	heroGlyph.Size = UDim2.fromScale(1, 1)
	heroGlyph.BackgroundTransparency = 1
	heroGlyph.Font = Enum.Font.Gotham
	heroGlyph.TextScaled = true
	heroGlyph.Text = "\240\159\167\153"
	heroGlyph.TextTransparency = 0
	heroGlyph.TextStrokeTransparency = 1
	heroGlyph.Active = false
	heroGlyph.ZIndex = 10
	heroGlyph.Parent = hero
	scene.animatedCount += 1

	-- fireflies
	local flies = {}
	for i = 1, WL.fireflies do
		local f = frame(world, "Firefly", Color3.fromRGB(255, 240, 150), 0.2)
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Size = UDim2.fromOffset(4 + i % 2 * 2, 4 + i % 2 * 2)
		round(f, UDim.new(1, 0))
		flies[i] = { frame = f, fx = 0.14 + (i * 0.21) % 0.72, fy = 0.30 + (i * 0.13) % 0.4, phase = i * 1.9, speed = 0.15 + (i % 3) * 0.05 }
	end
	scene.animatedCount += #flies

	-- soft backing under the title so the gold lettering reads on the grass
	local scrim = frame(container, "TitleScrim", Color3.fromRGB(14, 20, 12), 0.62)
	scrim.Size = UDim2.fromScale(1, 0.2)

	-- the parchment map edge frames the screen: painted fog and roller frame when recorded, a drawn parchment border otherwise
	local fogArt = ContentArt.getImageId("menu_world", "menu_fog_edge")
	local frameArt = ContentArt.getImageId("menu_world", "menu_map_frame")
	if fogArt then image(container, "FogEdge", fogArt, Enum.ScaleType.Stretch).Size = UDim2.fromScale(1, 1) end
	if frameArt then
		image(container, "MapFrame", frameArt, Enum.ScaleType.Stretch).Size = UDim2.fromScale(1, 1)
	else
		local border = Instance.new("Frame")
		border.Name = "ParchmentBorder"
		border.Size = UDim2.fromScale(1, 1)
		border.BackgroundTransparency = 1
		border.Active = false
		border.ZIndex = 10
		border.Parent = container
		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.fromRGB(214, 190, 140)
		stroke.Thickness = 10
		stroke.Parent = border
	end

	function scene.update(_nx, _ny, t, calm)
		for _, f in ipairs(flies) do f.frame.Visible = not calm end
		for _, p in ipairs(puffs) do p.Visible = not calm end
		hero.Visible = not calm
		if calm then
			world.Position = UDim2.fromScale(0.5, 0.5)
			world.Size = UDim2.fromScale(D.baseZoom, D.baseZoom)
			glow.BackgroundTransparency = 0.82
			for _, c in ipairs(clouds) do c.inst.Position = UDim2.fromScale(0.3 + c.phase, c.y) end
			return
		end
		local dx, dy, z = WL.driftAt(t)
		world.Position = UDim2.new(0.5, dx, 0.5, dy)
		world.Size = UDim2.fromScale(z, z)
		glow.BackgroundTransparency = 0.82 + math.sin(t * 1.7) * 0.05 + math.sin(t * 4.3) * 0.02
		for i, p in ipairs(puffs) do
			local k = (t / 4 + (i - 1) / 3) % 1
			local s = 0.012 + k * 0.03
			p.Size = UDim2.fromScale(s, s * 1.7)
			p.Position = UDim2.fromScale(WL.chimney.x + math.sin(t * 0.8 + i) * 0.008 + k * 0.02, WL.chimney.y - k * 0.12)
			p.BackgroundTransparency = 0.55 + k * 0.45
		end
		for _, c in ipairs(clouds) do
			local x = (t * c.speed + c.phase) % 1.5 - 0.25
			c.inst.Position = UDim2.fromScale(x, c.y)
		end
		local hx, hy = WL.heroAt(t)
		hero.Position = UDim2.fromScale(hx, hy)
		for _, f in ipairs(flies) do
			f.frame.Position = UDim2.fromScale(f.fx + math.sin(t * f.speed + f.phase) * 0.04, f.fy + math.cos(t * f.speed * 0.7 + f.phase) * 0.03)
			f.frame.BackgroundTransparency = 0.25 + (math.sin(t * 1.1 + f.phase * 2) * 0.5 + 0.5) * 0.6
		end
	end

	-- first frame: put the moving bits at their t = 0 spots so nothing starts at the corner
	scene.update(0, 0, 0, false)
	return scene
end

return MenuWorld
