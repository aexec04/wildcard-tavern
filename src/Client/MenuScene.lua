--[[
	Client/MenuScene.lua
	Cheap UI-only foreground for the Menu: a hanging lantern that swings with the cursor, drifting dust motes, two flickering
	candle glows and a pipe smoke wisp. 12 animated objects (cap: Engine/MenuLayout.MAX_ANIMATED). Everything is driven by one
	update(nx, ny, t, calm) call from MenuParallax's frame step, so there are no tweens or threads of its own. Nothing here is
	Active, so it never blocks a click. In calm mode (Reduce Shake / Reduce Motion) the scene is static: the lantern hangs
	straight, the glows hold, motes and smoke are hidden.

	build(parent) returns { update = function(nx, ny, t, calm), animatedCount = number }
]]

local Engine = game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine")
local Layout = require(Engine:WaitForChild("MenuLayout"))
local ContentArt = require(Engine:WaitForChild("ContentArt"))

local MenuScene = {}

local function dot(parent, size, color, transparency, z)
	local f = Instance.new("Frame")
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

function MenuScene.build(parent)
	local Z = 18
	local root = Instance.new("Frame")
	root.Name = "SceneFX"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1
	root.Active = false
	root.ZIndex = Z
	root.Parent = parent

	-- Hanging lantern (pivots at the ceiling).
	local lantern = Instance.new("Frame")
	lantern.Name = "Lantern"
	lantern.AnchorPoint = Vector2.new(0.5, 0)
	lantern.Position = UDim2.fromScale(0.14, 0)
	lantern.Size = UDim2.fromOffset(60, 130)
	lantern.BackgroundTransparency = 1
	lantern.Active = false
	lantern.ZIndex = Z
	lantern.Parent = root
	local rope = Instance.new("Frame")
	rope.AnchorPoint = Vector2.new(0.5, 0)
	rope.Position = UDim2.fromScale(0.5, 0)
	rope.Size = UDim2.fromOffset(3, 80)
	rope.BackgroundColor3 = Color3.fromRGB(96, 66, 38)
	rope.BorderSizePixel = 0
	rope.Active = false
	rope.ZIndex = Z
	rope.Parent = lantern
	-- The painted lantern has an opaque dark background (no alpha from the generator),
	-- so it would show as a dark square over the backdrop. Keep the emoji until it is cut out.
	local artId = nil -- ContentArt.getImageId("menu_icons", "menu_lantern_fg")
	if artId then
		local img = Instance.new("ImageLabel")
		img.AnchorPoint = Vector2.new(0.5, 0)
		img.Position = UDim2.fromOffset(30, 70)
		img.Size = UDim2.fromOffset(56, 64)
		img.BackgroundTransparency = 1
		img.Image = artId
		img.ScaleType = Enum.ScaleType.Fit
		img.Active = false
		img.ZIndex = Z + 1
		img.Parent = lantern
	else
		local body = Instance.new("TextLabel")
		body.AnchorPoint = Vector2.new(0.5, 0)
		body.Position = UDim2.fromOffset(30, 72)
		body.Size = UDim2.fromOffset(56, 56)
		body.BackgroundTransparency = 1
		body.Font = Enum.Font.Gotham
		body.TextSize = 44
		body.Text = "🏮"
		body.TextTransparency = 0
		body.TextStrokeTransparency = 1
		body.Active = false
		body.ZIndex = Z + 1
		body.Parent = lantern
	end

	-- Candle glows: two warm soft circles that flicker.
	local glows = {}
	for i, pos in ipairs({ { 0.30, 0.60 }, { 0.80, 0.44 } }) do
		local g = dot(root, 120, Color3.fromRGB(255, 190, 90), 0.85, Z)
		g.Position = UDim2.fromScale(pos[1], pos[2])
		glows[i] = g
	end

	-- Dust motes drifting slowly upward.
	local motes = {}
	for i = 1, 6 do
		local m = dot(root, 4, Color3.fromRGB(255, 236, 190), 0.55, Z)
		motes[i] = { frame = m, fx = 0.12 + (i * 0.15) % 0.8, fy = (i * 0.37) % 1, speed = 0.006 + (i % 3) * 0.003, phase = i * 1.7 }
	end

	-- Pipe smoke: three faint puffs rising from near the bar.
	local smoke = {}
	for i = 1, 3 do
		smoke[i] = dot(root, 18, Color3.fromRGB(220, 215, 205), 1, Z)
	end

	local scene = { animatedCount = 1 + #glows + #motes + #smoke }

	function scene.update(nx, ny, t, calm)
		if calm then
			lantern.Rotation = 0
			for _, g in ipairs(glows) do g.BackgroundTransparency = 0.85 end
			for _, m in ipairs(motes) do m.frame.Visible = false end
			for _, s in ipairs(smoke) do s.Visible = false end
			return
		end
		lantern.Rotation = Layout.clamp(-nx * 5, -6, 6) + math.sin(t * 1.3) * 1.5
		for i, g in ipairs(glows) do
			g.BackgroundTransparency = 0.84 + math.sin(t * (7 + i) + i) * 0.04 + math.sin(t * 13 + i * 2) * 0.025
		end
		for _, m in ipairs(motes) do
			m.frame.Visible = true
			local y = (m.fy - t * m.speed) % 1
			m.frame.Position = UDim2.fromScale(m.fx + math.sin(t * 0.5 + m.phase) * 0.012, y)
		end
		for i, s in ipairs(smoke) do
			s.Visible = true
			local p = (t * 0.12 + i / 3) % 1
			s.Position = UDim2.fromScale(0.64 + math.sin(p * 6 + i) * 0.01, 0.86 - p * 0.14)
			s.BackgroundTransparency = 0.78 + p * 0.22
			s.Size = UDim2.fromOffset(14 + p * 22, 14 + p * 22)
		end
	end

	return scene
end

return MenuScene
