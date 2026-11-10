--[[
	Client/MenuScene.lua
	The painted tavern layers and the life drawn over them, all UI only. Everything is driven by one update(nx, ny, t, calm) call
	from MenuParallax's frame step, so there are no tweens or threads of its own. Nothing here is Active, so it never blocks a
	click. Calm mode (Reduce Shake / Reduce Motion) hides every animated object and holds the lantern still.
	Layers: the mid beams (scene.beams) and the cutout foreground lantern (scene.lantern) are parallax layers that Menu.lua adds
	to MenuParallax. Both stay hidden when their art is missing, so the plain scene still works.
	Animated objects (16, the cap in Engine/MenuLayout.MAX_ANIMATED): 5 dust motes, 6 embers, the fire glow, the window light
	shaft, the counter candle glow, a steam wisp and the swinging lantern. There is no cat sprite, so no tail flick.
	The placeholder emoji lantern and the big soft glow and smoke circles were removed (redesign 2).

	build(parent) returns { update, animatedCount, beams, beamsBase, lantern, lanternBase }
]]

local Layout = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("MenuLayout"))
local ContentArt = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("ContentArt"))

local MenuScene = {}

local MOTE_SIZES = { 4, 6, 5, 8, 10 } -- px; small and rare, never big faint circles
local EMBERS = 6

local function dot(parent, name, size, color, transparency, z)
	local f = Instance.new("Frame")
	f.Name = name
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Size = UDim2.fromOffset(size, size)
	f.BackgroundColor3 = color
	f.BackgroundTransparency = transparency
	f.BorderSizePixel = 0
	f.Active = false
	f.ZIndex = z
	f.Parent = parent
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(1, 0)
	c.Parent = f
	return f
end

-- Deterministic pseudo random in [0, 1) so the glow intervals look random without a RNG per frame.
local function hash01(n)
	local s = math.sin(n * 12.9898) * 43758.5453
	return s - math.floor(s)
end

-- Fire flicker schedule: 48 intervals of 0.6 to 1.4 seconds, looped.
local FLICKER_STEPS = 48
local FLICKER_START, FLICKER_SPAN = {}, {}
local FLICKER_CYCLE = 0
for k = 1, FLICKER_STEPS do
	FLICKER_START[k] = FLICKER_CYCLE
	FLICKER_SPAN[k] = 0.6 + hash01(k) * 0.8
	FLICKER_CYCLE += FLICKER_SPAN[k]
end

function MenuScene.build(parent)
	local A = Layout.SceneArt
	local root = Instance.new("Frame")
	root.Name = "SceneFX"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1
	root.Active = false
	root.ZIndex = 18
	root.Parent = parent

	local scene = { animatedCount = 0 }

	-- ===== Mid beams: the band of ceiling beams, cropped so its flat sky never covers the wall =====
	local beams = Instance.new("ImageLabel")
	beams.Name = "MidBeams"
	beams.AnchorPoint = Vector2.new(0.5, 0)
	scene.beamsBase = UDim2.fromScale(0.5, 0)
	beams.Position = scene.beamsBase
	beams.Size = UDim2.fromScale(1.06, 0.34)
	beams.BackgroundTransparency = 1
	beams.ScaleType = Enum.ScaleType.Stretch
	beams.Active = false
	beams.ZIndex = 11
	local beamsArt = ContentArt.getImageId("menu_scene", A.beams)
	if beamsArt then
		beams.Image = beamsArt
		beams.ImageRectOffset = Vector2.new(A.beamsRect.x, A.beamsRect.y)
		beams.ImageRectSize = Vector2.new(A.beamsRect.w, A.beamsRect.h)
	end
	beams.Visible = beamsArt ~= nil
	beams.Parent = parent
	scene.beams = beams

	-- ===== Foreground lantern: hangs from the top edge on its chain and swings with the cursor =====
	local lantern = Instance.new("ImageLabel")
	lantern.Name = "ForegroundLantern"
	lantern.AnchorPoint = Vector2.new(0.5, 0)
	scene.lanternBase = UDim2.fromScale(A.lanternPos.x, -0.04)
	lantern.Position = scene.lanternBase
	lantern.Size = UDim2.fromScale(A.lanternPos.h, A.lanternPos.h)
	lantern.SizeConstraint = Enum.SizeConstraint.RelativeYY
	lantern.BackgroundTransparency = 1
	lantern.ScaleType = Enum.ScaleType.Fit
	lantern.Active = false
	lantern.ZIndex = 19
	local lanternArt = ContentArt.getImageId("menu_scene", A.lantern)
	if lanternArt then lantern.Image = lanternArt end
	lantern.Visible = lanternArt ~= nil
	lantern.Parent = parent
	scene.lantern = lantern
	scene.animatedCount += 1

	-- ===== Fire flicker: a soft orange glow over the fireplace, pulsing at random 0.6 to 1.4 second intervals =====
	local fire = Instance.new("Frame")
	fire.Name = "FireGlow"
	fire.AnchorPoint = Vector2.new(0.5, 0.5)
	fire.Position = UDim2.fromScale(A.fire.x, A.fire.y)
	fire.Size = UDim2.fromScale(A.fire.w, A.fire.h)
	fire.BackgroundColor3 = Color3.fromRGB(255, 150, 50)
	fire.BackgroundTransparency = 0.88
	fire.BorderSizePixel = 0
	fire.Active = false
	fire.ZIndex = 12
	fire.Parent = root
	local fc = Instance.new("UICorner")
	fc.CornerRadius = UDim.new(1, 0)
	fc.Parent = fire
	scene.animatedCount += 1

	-- ===== Window light shaft: a slow warm slanted beam with a gentle breathing alpha =====
	local shaft = Instance.new("Frame")
	shaft.Name = "WindowShaft"
	shaft.AnchorPoint = Vector2.new(0, 0)
	shaft.Position = UDim2.fromScale(A.window.x, A.window.y)
	shaft.Size = UDim2.fromScale(A.window.w, A.window.h)
	shaft.Rotation = -22
	shaft.BackgroundColor3 = Color3.fromRGB(255, 205, 140)
	shaft.BackgroundTransparency = 0.93
	shaft.BorderSizePixel = 0
	shaft.Active = false
	shaft.ZIndex = 12
	shaft.Parent = root
	scene.animatedCount += 1

	-- ===== Counter candle glow and a steam wisp over a mug =====
	local candle = dot(root, "CandleGlow", 40, Color3.fromRGB(255, 190, 90), 0.85, 12)
	candle.Position = UDim2.fromScale(A.candle.x, A.candle.y)
	scene.animatedCount += 1
	local steam = dot(root, "Steam", 10, Color3.fromRGB(240, 235, 225), 0.8, 18)
	steam.Position = UDim2.fromScale(A.steam.x, A.steam.y)
	scene.animatedCount += 1

	-- ===== Embers rising near the fireplace =====
	local embers = {}
	for i = 1, EMBERS do
		local e = dot(root, "Ember", 3 + i % 3, Color3.fromRGB(255, 160, 60), 0.2, 18)
		embers[i] = { frame = e, ox = (i - 3.5) * 0.012, speed = 0.05 + (i % 3) * 0.02, phase = i * 0.31 }
	end
	scene.animatedCount += EMBERS

	-- ===== Dust motes drifting slowly upward =====
	local motes = {}
	for i = 1, #MOTE_SIZES do
		local m = dot(root, "Mote", MOTE_SIZES[i], Color3.fromRGB(255, 236, 190), 0.6, 18)
		motes[i] = { frame = m, fx = 0.3 + (i * 0.17) % 0.5, fy = (i * 0.37) % 0.7, speed = 0.005 + (i % 3) * 0.002, phase = i * 1.7 }
	end
	scene.animatedCount += #motes

	local animated = { fire, shaft, candle, steam }

	-- The bayou backdrop (Client/MenuBayou.lua) replaces the tavern wall: the wall-bound life (beams, fire, shaft, candle, steam,
	-- embers) is hidden, the dust motes and the swinging lantern stay. The animated count drops to the lantern plus the motes.
	local bayouMode = false
	function scene.setBayou(on)
		bayouMode = on
		beams.Visible = beamsArt ~= nil and not on
		scene.animatedCount = on and (1 + #motes) or (1 + 4 + EMBERS + #motes)
	end

	-- Tavern Room: the picture has its own life, so the foreground lantern, motes and embers are off
	local roomMode = false
	function scene.setRoom(on)
		roomMode = on
		lantern.Visible = not on
		scene.animatedCount = on and 0 or scene.animatedCount
	end

	function scene.update(nx, ny, t, calm)
		local wallLife = not calm and not bayouMode and not roomMode
		for _, f in ipairs(animated) do f.Visible = wallLife end
		for _, m in ipairs(motes) do m.frame.Visible = not calm and not roomMode end
		for _, e in ipairs(embers) do e.frame.Visible = wallLife end
		if calm then
			lantern.Rotation = 0
			return
		end
		-- fire: a new target brightness every 0.6 to 1.4 seconds, eased between the last and the next
		local tt = t % FLICKER_CYCLE
		local seg = 1
		while seg < FLICKER_STEPS and FLICKER_START[seg + 1] <= tt do seg += 1 end
		local u = math.clamp((tt - FLICKER_START[seg]) / FLICKER_SPAN[seg], 0, 1)
		local a = hash01(seg + 100)
		local b = hash01(seg < FLICKER_STEPS and seg + 101 or 101) -- the last step eases back to the first, so the loop has no jump
		local level = a + (b - a) * u
		fire.BackgroundTransparency = 0.94 - level * 0.14 -- 0.80 to 0.94, never a hard flash
		shaft.BackgroundTransparency = 0.92 + math.sin(t * 0.35) * 0.02
		candle.BackgroundTransparency = 0.82 + math.sin(t * 2.3) * 0.05
		-- steam: one wisp rises 0.05 of the screen and fades, looping every 3 seconds
		local s = (t % 3) / 3
		steam.Position = UDim2.fromScale(A.steam.x + math.sin(t * 1.5) * 0.004, A.steam.y - s * 0.05)
		steam.BackgroundTransparency = 0.7 + s * 0.3
		for _, e in ipairs(embers) do
			local k = (t * e.speed + e.phase) % 1
			e.frame.Position = UDim2.fromScale(A.fire.x + e.ox + math.sin(t + e.phase * 9) * 0.01, A.fire.y - 0.04 - k * 0.22)
			e.frame.BackgroundTransparency = 0.2 + k * 0.8
		end
		for _, m in ipairs(motes) do
			local y = (m.fy - t * m.speed) % 0.7 + 0.05 -- stays in the upper scene, clear of the counter
			m.frame.Position = UDim2.fromScale(m.fx + math.sin(t * 0.5 + m.phase) * 0.012, y)
		end
		lantern.Rotation = -nx * 4 + math.sin(t * 0.9) * 1.5
	end

	return scene
end

return MenuScene
