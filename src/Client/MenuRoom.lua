--[[
	Client/MenuRoom.lua
	The Tavern Room Menu: the inside of the tavern under the Menu's buttons. Numbers in Engine/MenuRoomLayout (tested), painted
	pieces from Engine/MenuRoomArt (category menu_room). UI only. Every piece has a code-drawn fallback, so the room looks fine
	before any art is recorded: panelled wall, window, stone fireplace, bar, floor, a felt card table with candles.

	The props that are buttons (scroll, map, Tome, Rulebook, Coin Jar, Jukebox) are drawn by Client/MenuHotspots at the spots in
	MenuRoomLayout.apply; this module draws the wall, the card table behind the Deal Me In button, the hanging lantern and the life.

	Life (at most 10 animated objects, all hidden in calm mode): fire glow and lantern glow flicker 3 percent, a few motes in the
	firelight, a glint on the coin jar now and then, a soft ripple over the Tome's pages, two note puffs over the Jukebox.

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

-- A box centred at (x, y) that keeps an aspect ratio inside a height fraction.
local function aspectBox(parent, name, spot)
	local box = Instance.new("Frame")
	box.Name = name
	box.AnchorPoint = Vector2.new(0.5, 0.5)
	box.Position = UDim2.fromScale(spot.x, spot.y)
	box.Size = UDim2.fromScale(1, spot.s)
	box.BackgroundTransparency = 1
	box.Active = false
	box.ZIndex = 10
	box.Parent = parent
	local a = Instance.new("UIAspectRatioConstraint")
	a.AspectRatio = spot.asp
	a.Parent = box
	return box
end

local function rect(parent, name, color, x, y, w, h)
	local f = frame(parent, name, color)
	f.Position = UDim2.fromScale(x, y)
	f.Size = UDim2.fromScale(w, h)
	return f
end

local function glowDisc(parent, name, color, x, y, w, h, transparency)
	local g = frame(parent, name, color, transparency)
	g.AnchorPoint = Vector2.new(0.5, 0.5)
	g.Position = UDim2.fromScale(x, y)
	g.Size = UDim2.fromScale(w, h)
	round(g, UDim.new(0.5, 0))
	return g
end

-- Code-drawn room used when menu_room_wall has no Image id yet.
local function drawWall(container)
	local wall = frame(container, "WallFallback", Color3.fromRGB(70, 48, 32))
	wall.Size = UDim2.fromScale(1, 1)
	rect(wall, "Plaster", Color3.fromRGB(122, 94, 62), 0.36, 0.16, 0.38, 0.42)
	rect(wall, "BeamTop", Color3.fromRGB(54, 36, 22), 0, 0, 1, 0.07)
	rect(wall, "BeamL", Color3.fromRGB(54, 36, 22), 0.05, 0, 0.03, 0.6)
	rect(wall, "BeamR", Color3.fromRGB(54, 36, 22), 0.74, 0, 0.03, 0.6)
	local win = rect(wall, "Window", Color3.fromRGB(28, 40, 84), 0.13, 0.21, 0.17, 0.26)
	local winRim = Instance.new("UIStroke")
	winRim.Color = Color3.fromRGB(54, 36, 22)
	winRim.Thickness = 5
	winRim.Parent = win
	rect(wall, "Fireplace", Color3.fromRGB(96, 90, 82), 0.80, 0.22, 0.20, 0.44)
	rect(wall, "FireOpening", Color3.fromRGB(40, 24, 16), 0.85, 0.40, 0.11, 0.22)
	rect(wall, "BarTop", Color3.fromRGB(128, 86, 48), 0, 0.60, 0.89, 0.04)
	rect(wall, "BarFront", Color3.fromRGB(82, 54, 32), 0, 0.64, 0.89, 0.18)
	rect(wall, "Floor", Color3.fromRGB(60, 40, 26), 0, 0.82, 1, 0.18)
	return wall
end

-- Code-drawn felt card table under the Deal Me In button when menu_room_cardtable has no Image id yet.
local function drawTable(box)
	local felt = frame(box, "Felt", Color3.fromRGB(46, 110, 62))
	felt.AnchorPoint = Vector2.new(0.5, 0.5)
	felt.Position = UDim2.fromScale(0.5, 0.5)
	felt.Size = UDim2.fromScale(0.86, 0.7)
	round(felt, UDim.new(0.5, 0))
	local rim = Instance.new("UIStroke")
	rim.Color = Color3.fromRGB(120, 78, 44)
	rim.Thickness = 6
	rim.Parent = felt
	for i = -1, 1, 2 do
		local candle = rect(box, "Candle", Color3.fromRGB(246, 232, 190), 0.5 + i * 0.22 - 0.015, 0.22, 0.03, 0.14)
		round(candle, UDim.new(0.2, 0))
		glowDisc(box, "Flame", Color3.fromRGB(255, 190, 90), 0.5 + i * 0.22, 0.2, 0.035, 0.07, 0.1)
	end
	local deck = rect(box, "Deck", Color3.fromRGB(176, 66, 52), 0.44, 0.4, 0.12, 0.2)
	round(deck, UDim.new(0.1, 0))
end

function MenuRoom.build(parent)
	local scene = { active = true, layers = {}, animatedCount = 0 }
	local container = Instance.new("Frame")
	container.Name = "RoomScene"
	container.Size = UDim2.fromScale(1, 1)
	container.BackgroundColor3 = Color3.fromRGB(46, 30, 20)
	container.BorderSizePixel = 0
	container.Active = false
	container.ClipsDescendants = true
	container.ZIndex = 10
	container.Parent = parent

	-- the back wall and floor: painted when recorded, drawn otherwise
	local wallArt = ContentArt.getImageId("menu_room", "menu_room_wall")
	if wallArt then
		image(container, "Wall", wallArt, Enum.ScaleType.Crop).Size = UDim2.fromScale(1, 1)
	else
		drawWall(container)
	end

	-- the card table behind the Deal Me In button (the button itself is placed by MenuHotspots on the same rect)
	local tableBox = aspectBox(container, "CardTable", RL.spots.play)
	local tableArt = ContentArt.getImageId("menu_room", "menu_room_cardtable")
	if tableArt then
		image(tableBox, "Art", tableArt).Size = UDim2.fromScale(1, 1)
	else
		drawTable(tableBox)
	end

	-- the hanging lantern at the left edge
	local lanternBox = aspectBox(container, "Lantern", RL.lantern)
	local lanternArt = ContentArt.getImageId("menu_room", "menu_room_lantern")
	if lanternArt then
		image(lanternBox, "Art", lanternArt).Size = UDim2.fromScale(1, 1)
	else
		rect(lanternBox, "Chain", Color3.fromRGB(70, 66, 62), 0.48, 0, 0.04, 0.55)
		rect(lanternBox, "Body", Color3.fromRGB(86, 80, 72), 0.25, 0.55, 0.5, 0.4)
	end

	-- life: every object below is one of the counted animated objects
	local F = RL.fire
	local fireGlow = glowDisc(container, "FireGlow", Color3.fromRGB(255, 150, 60), F.x, F.y, F.w, F.h, 0.82)
	local lanternGlow = glowDisc(container, "LanternGlow", Color3.fromRGB(255, 190, 90), RL.lantern.x, RL.lantern.y + RL.lantern.s * 0.28, 0.07, 0.11, 0.84)
	local motes = {}
	for i = 1, RL.motes do
		local m = glowDisc(container, "Mote", Color3.fromRGB(255, 214, 140), F.x, F.y, 0.004, 0.007, 0.3)
		motes[i] = m
	end
	local jar = RL.spots.coinjar
	local glint = frame(container, "CoinGlint", Color3.fromRGB(255, 250, 220), 1)
	glint.AnchorPoint = Vector2.new(0.5, 0.5)
	glint.Position = UDim2.fromScale(jar.x - jar.s * 0.18, jar.y - jar.s * 0.1)
	glint.Size = UDim2.fromOffset(10, 10)
	glint.Rotation = 45
	local tome = RL.spots.tome
	local ripple = glowDisc(container, "TomeRipple", Color3.fromRGB(255, 232, 170), tome.x, tome.y - tome.s * 0.12, tome.s * 0.5 * 0.5625, tome.s * 0.22, 0.9)
	local juke = RL.spots.jukebox
	local puffs = {}
	for i = 1, 2 do
		local p = glowDisc(container, "Note", Color3.fromRGB(255, 226, 150), juke.x, juke.y - juke.s * 0.5, 0.008, 0.014, 1)
		puffs[i] = p
	end
	scene.animatedCount = RL.animated

	-- soft backing under the title so the lettering reads: eight thin steps that fade out, no band edge
	do
		local steps, height = 8, 0.16
		for i = 1, steps do
			local step = frame(container, "TitleScrim" .. i, Color3.fromRGB(14, 10, 6), 0.7 + (i - 1) * 0.04)
			step.Size = UDim2.fromScale(1, height * (steps - i + 1) / steps)
		end
	end

	function scene.update(_nx, _ny, t, calm)
		for _, m in ipairs(motes) do m.Visible = not calm end
		for _, p in ipairs(puffs) do p.Visible = not calm end
		glint.Visible = not calm
		ripple.Visible = not calm
		if calm then
			fireGlow.BackgroundTransparency = 0.82
			lanternGlow.BackgroundTransparency = 0.84
			return
		end
		local fl = RL.flickerAt(t)
		fireGlow.BackgroundTransparency = 0.82 + fl
		lanternGlow.BackgroundTransparency = 0.84 + RL.flickerAt(t + 3.1)
		for i, m in ipairs(motes) do
			local x, y, a = RL.moteAt(i, t)
			m.Position = UDim2.fromScale(x, y)
			m.BackgroundTransparency = 0.9 - a * 0.6
		end
		local g = RL.glintAt(t)
		glint.BackgroundTransparency = g == 0 and 1 or 1 - math.sin(g * math.pi) * 0.9
		ripple.BackgroundTransparency = 0.9 + math.sin(t * 0.9) * 0.04
		for i, p in ipairs(puffs) do
			local k = (t / 3 + (i - 1) / 2) % 1
			p.Position = UDim2.fromScale(juke.x + math.sin(t + i * 2) * 0.01, juke.y - juke.s * 0.5 - k * 0.07)
			p.BackgroundTransparency = 0.5 + k * 0.5
		end
	end

	scene.update(0, 0, 0, false)
	return scene
end

return MenuRoom
