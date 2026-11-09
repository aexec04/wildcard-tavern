--[[
	Client/MenuScene.lua
	Cheap UI-only foreground for the Menu: a few tiny dust motes drifting slowly upward. 5 animated objects (cap:
	Engine/MenuLayout.MAX_ANIMATED). Everything is driven by one update(nx, ny, t, calm) call from MenuParallax's frame step, so
	there are no tweens or threads of its own. Nothing here is Active, so it never blocks a click. In calm mode (Reduce Shake /
	Reduce Motion) the motes are hidden.
	The placeholder emoji lantern and the big soft glow and smoke circles were removed (redesign 2): a cutout lantern, candle
	glow and steam come back with the painted scene art.

	build(parent) returns { update = function(nx, ny, t, calm), animatedCount = number }
]]

local MenuScene = {}

local MOTE_SIZES = { 4, 6, 5, 8, 10 } -- px; small and rare, never big faint circles

function MenuScene.build(parent)
	local root = Instance.new("Frame")
	root.Name = "SceneFX"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1
	root.Active = false
	root.ZIndex = 18
	root.Parent = parent

	local motes = {}
	for i = 1, #MOTE_SIZES do
		local m = Instance.new("Frame")
		m.Name = "Mote"
		m.AnchorPoint = Vector2.new(0.5, 0.5)
		m.Size = UDim2.fromOffset(MOTE_SIZES[i], MOTE_SIZES[i])
		m.BackgroundColor3 = Color3.fromRGB(255, 236, 190)
		m.BackgroundTransparency = 0.6
		m.BorderSizePixel = 0
		m.Active = false
		m.ZIndex = 18
		m.Parent = root
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(1, 0)
		c.Parent = m
		motes[i] = { frame = m, fx = 0.3 + (i * 0.17) % 0.5, fy = (i * 0.37) % 0.7, speed = 0.005 + (i % 3) * 0.002, phase = i * 1.7 }
	end

	local scene = { animatedCount = #motes }

	function scene.update(nx, ny, t, calm)
		for _, m in ipairs(motes) do
			if calm then
				m.frame.Visible = false
			else
				m.frame.Visible = true
				local y = (m.fy - t * m.speed) % 0.7 + 0.05 -- stays in the upper scene, clear of the counter
				m.frame.Position = UDim2.fromScale(m.fx + math.sin(t * 0.5 + m.phase) * 0.012, y)
			end
		end
	end

	return scene
end

return MenuScene
