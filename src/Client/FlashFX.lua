--[[
	Client/FlashFX.lua
	The premium replacement for the flat full-screen colour flashes (Legendary, True Wildcard, the boss Showdown). Draws the layered effect
	of Engine/FlashFX: a soft radial glow on the thing that triggered it (SoftGlow, no visible edge), a faint dark vignette at the screen
	edges only (SmoothVignette, the middle is unchanged), 10 to 16 small motes drifting up from it, and for Legendary a thin light strip
	sweeping across the banner. Nothing covers the whole screen above 15 percent opacity, nothing strobes, and with Reduce screen shake on
	it is a still glow and vignette that simply fade out, no motes and no sweep. Never blocks input.

	FlashFX.play(root, kind, center, opts) -> { stop() }
	  kind   "legendary" | "wildcard" | "showdown"
	  center UDim2 in root space (the scoring card, the banner or the wildcard card)
	  opts   { zIndex = 33, banner = GuiObject? (for the sweep) }
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Engine = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine")
local Spec = require(Engine:WaitForChild("FlashFX"))
local SoftGlow = require(script.Parent.SoftGlow)
local SmoothVignette = require(script.Parent.SmoothVignette)
local ClientSettings = require(script.Parent.ClientSettings)

local FlashFX = {}

local EDGES = { "top", "bottom", "left", "right" }

function FlashFX.play(root, kind, center, opts)
	opts = opts or {}
	if not root then return { stop = function() end } end
	local z = opts.zIndex or 33
	local reduced = ClientSettings.get("reduceShake") == true
	local spec = Spec.spec(kind, reduced)
	local color = Color3.fromRGB(spec.color[1], spec.color[2], spec.color[3])

	local holder = Instance.new("Frame")
	holder.Name = "FlashFX_" .. tostring(kind)
	holder.Size = UDim2.fromScale(1, 1)
	holder.BackgroundTransparency = 1
	holder.BorderSizePixel = 0
	holder.Active = false
	holder.ZIndex = z
	holder.Parent = root

	local screen = root.AbsoluteSize
	local glowSpec
	for _, l in ipairs(spec.layers) do if l.type == "glow" then glowSpec = l end end
	local gw = math.max(240, screen.X * (glowSpec and glowSpec.size or 0.5))
	local glow = SoftGlow.build(holder, { name = "FlashGlow", color = color, position = center or UDim2.fromScale(0.5, 0.45),
		size = UDim2.fromOffset(gw, gw * 0.7), peak = 0.01, zIndex = z })
	glow.root.Active = false
	local vignette = SmoothVignette.build(holder, { name = "FlashVignette", zIndex = z, color = Color3.fromRGB(14, 10, 6),
		top = { strength = 0.01, extent = 0.22 }, bottom = { strength = 0.01, extent = 0.22 },
		left = { strength = 0.01, extent = 0.22 }, right = { strength = 0.01, extent = 0.22 } })

	local alive = true
	local function destroy()
		alive = false
		if holder.Parent then holder:Destroy() end
	end

	-- motes rising from the card (not in reduced motion)
	if spec.motion then
		local centerPx = Vector2.new(screen.X * (center and center.X.Scale or 0.5) + (center and center.X.Offset or 0),
			screen.Y * (center and center.Y.Scale or 0.45) + (center and center.Y.Offset or 0))
		local rolls = {}
		for i = 1, Spec.moteCount(kind, false) do rolls[i] = { math.random(), math.random(), math.random(), math.random() } end
		for _, m in ipairs(Spec.motes(kind, rolls)) do
			task.delay(m.delay, function()
				if not alive then return end
				local dot = Instance.new("Frame")
				dot.Name = "Mote"
				dot.AnchorPoint = Vector2.new(0.5, 0.5)
				dot.Size = UDim2.fromOffset(m.size, m.size)
				dot.Position = UDim2.fromOffset(centerPx.X + m.dx, centerPx.Y + m.dy)
				dot.BackgroundColor3 = color:Lerp(Color3.new(1, 1, 1), 0.35)
				dot.BackgroundTransparency = 0.4
				dot.BorderSizePixel = 0
				dot.Active = false
				dot.ZIndex = z
				dot.Parent = holder
				local c = Instance.new("UICorner")
				c.CornerRadius = UDim.new(0.5, 0)
				c.Parent = dot
				local info = TweenInfo.new(1.3, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
				TweenService:Create(dot, info, { Position = UDim2.fromOffset(centerPx.X + m.dx + m.drift, centerPx.Y + m.dy - m.rise), BackgroundTransparency = 1 }):Play()
			end)
		end
	end

	-- the thin light strip across the banner (Legendary)
	if spec.motion and kind == "legendary" and opts.banner and opts.banner.Parent then
		local banner = opts.banner
		local from = banner.AbsolutePosition - root.AbsolutePosition
		local strip = Instance.new("Frame")
		strip.Name = "BannerSweep"
		strip.Size = UDim2.fromOffset(34, banner.AbsoluteSize.Y)
		strip.Position = UDim2.fromOffset(from.X - 34, from.Y)
		strip.BackgroundColor3 = Color3.fromRGB(255, 244, 214)
		strip.BackgroundTransparency = 0.75
		strip.BorderSizePixel = 0
		strip.Active = false
		strip.ZIndex = (banner.ZIndex or z) + 1
		strip.Parent = holder
		TweenService:Create(strip, TweenInfo.new(0.7, Enum.EasingStyle.Sine), { Position = UDim2.fromOffset(from.X + banner.AbsoluteSize.X, from.Y), BackgroundTransparency = 1 }):Play()
	end

	-- the glow and the vignette follow the tested envelope
	task.spawn(function()
		local t0 = os.clock()
		-- a failing frame must never leave the overlays on screen: every step is protected and destroy() always runs
		local ok, err = pcall(function()
			while alive do
				local t = os.clock() - t0
				if t >= spec.duration then break end
				glow.setPeak(math.max(0.001, Spec.glowPeakAt(spec, t)))
				local strength = math.min(0.95, math.max(0.001, Spec.vignetteAt(spec, t)))
				for _, edge in ipairs(EDGES) do vignette.setStrength(edge, strength) end -- third argument is an optional apply function, never a boolean
				task.wait(1 / 30)
			end
		end)
		if not ok then warn("[FlashFX] " .. tostring(err)) end
		destroy()
	end)
	task.delay(spec.duration + 0.6, destroy) -- hard safety net: nothing can stay on screen

	return { stop = destroy }
end

return FlashFX
