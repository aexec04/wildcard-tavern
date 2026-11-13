--[[
	ReplicatedFirst/LoadingScreenUI.lua
	Builds the launch loading screen: painted tavern doorway (loading_scene_bg), the wordmark, a wooden beam
	progress bar (loading_bar_frame, code-drawn wood when the id is missing) with an amber fill, a moving
	shimmer and an ember at the leading edge, a status line and a rotating tip. Rules (weights, easing, tips)
	are in Engine/LoadProgress and Engine/LoadingTips. The two scrims are the only UIGradient Transparency use (a fade, Engine/ScrimGradient).
	LoadingScreenUI.show(playerGui, { shared = ReplicatedStorage.Shared, frozen = 0..1 or nil, onSkip = fn })
	  -> handle { gui, setTarget(v), setReady(), fadeOut(), destroy(), isAlive() }
]]

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local LoadingScreenUI = {}

local BAR_ART = { x = 0, y = 360, w = 1536, h = 305 } -- the beam inside the 1536x1024 picture
local CHANNEL = { x0 = 0.11, x1 = 0.89, y0 = 0.31, y1 = 0.69 } -- the hollow channel inside the beam crop
local AMBER = Color3.fromRGB(255, 170, 60)
local CREAM = Color3.fromRGB(240, 224, 190)
local BRASS = Color3.fromRGB(214, 170, 86)

local function validId(v)
	return type(v) == "string" and v ~= "" and v ~= "rbxassetid://0"
end

local function gradient(parent, c0, c1, rotation)
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new(c0, c1)
	g.Rotation = rotation or 90
	g.Parent = parent
	return g
end

local function label(parent, text, size, color, font)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Text = text
	l.TextSize = math.max(15, size)
	l.TextColor3 = color
	l.Font = font or Enum.Font.GothamMedium
	l.TextWrapped = true
	l.TextTransparency = 0
	l.TextStrokeTransparency = 0.35
	l.TextStrokeColor3 = Color3.fromRGB(10, 6, 4)
	l.Parent = parent
	return l
end

function LoadingScreenUI.show(playerGui, opts)
	opts = opts or {}
	local shared = opts.shared
	local Engine = shared and shared:FindFirstChild("Engine")
	local LoadProgress = Engine and require(Engine:WaitForChild("LoadProgress"))
	local LoadingTips = Engine and require(Engine:WaitForChild("LoadingTips"))
	local SceneArt = Engine and Engine:FindFirstChild("SceneArt") and require(Engine.SceneArt) or {}
	local GameName = Engine and Engine:FindFirstChild("GameName") and require(Engine.GameName) or { NAME = "The Gilded Knave" }
	if not (LoadProgress and LoadingTips) then return nil end

	local gui = Instance.new("ScreenGui")
	gui.Name = "LoadingScreen"
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 1000
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = playerGui

	local fade = Instance.new("CanvasGroup")
	fade.Name = "Fade"
	fade.Size = UDim2.fromScale(1, 1)
	fade.BackgroundColor3 = Color3.fromRGB(14, 10, 12)
	fade.BorderSizePixel = 0
	fade.GroupTransparency = 0
	fade.Active = true -- swallow clicks while it is up
	fade.Parent = gui
	gradient(fade, Color3.fromRGB(26, 20, 30), Color3.fromRGB(8, 6, 8), 90)

	-- painted scene, cover-cropped
	if validId(SceneArt.loading_scene_bg) then
		local bg = Instance.new("ImageLabel")
		bg.Name = "Scene"
		bg.Size = UDim2.fromScale(1, 1)
		bg.BackgroundTransparency = 1
		bg.Image = SceneArt.loading_scene_bg
		bg.ScaleType = Enum.ScaleType.Crop
		bg.Parent = fade
	else
		-- code-drawn doorway glow
		local glow = Instance.new("Frame")
		glow.Name = "DoorGlow"
		glow.AnchorPoint = Vector2.new(0.5, 0.5)
		glow.Position = UDim2.fromScale(0.5, 0.5)
		glow.Size = UDim2.fromScale(0.26, 0.5)
		glow.BackgroundColor3 = Color3.fromRGB(120, 70, 26)
		glow.BackgroundTransparency = 0.35
		glow.BorderSizePixel = 0
		glow.Parent = fade
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0.5, 0)
		c.Parent = glow
		gradient(glow, Color3.fromRGB(190, 120, 50), Color3.fromRGB(60, 34, 18), 90)
	end

	-- two soft scrims, each ONE frame with a UIGradient fade (the painting stays visible in between)
	local ScrimGradient = require(Engine:WaitForChild("ScrimGradient"))
	local Look = require(Engine:WaitForChild("LoadingLook"))
	for _, def in ipairs({ { "ScrimBottom", Look.BOTTOM, 90 }, { "ScrimTop", Look.TOP, 270 } }) do
		local spec = def[2]
		local f = Instance.new("Frame")
		f.Name = def[1]
		f.Position = UDim2.fromScale(0, spec.from)
		f.Size = UDim2.fromScale(1, spec.to - spec.from)
		f.BackgroundColor3 = Color3.fromRGB(6, 4, 6)
		f.BorderSizePixel = 0
		local g = Instance.new("UIGradient")
		g.Rotation = def[3]
		local pts = {}
		for _, k in ipairs(ScrimGradient.keypoints(12, spec.peak, spec.exponent)) do
			pts[#pts + 1] = NumberSequenceKeypoint.new(k[1], k[2])
		end
		g.Transparency = NumberSequence.new(pts)
		g.Parent = f
		f.Parent = fade
	end

	-- title
	local title = label(fade, GameName.NAME, 56, Color3.fromRGB(232, 196, 112), Enum.Font.Fondamento)
	title.Name = "Title"
	title.AnchorPoint = Vector2.new(0.5, 0)
	title.Position = UDim2.fromScale(0.5, 0.09)
	title.Size = UDim2.fromScale(0.8, 0.12)
	title.TextStrokeTransparency = 0.2
	local tsc = Instance.new("UITextSizeConstraint")
	tsc.MinTextSize = 28
	tsc.MaxTextSize = 72
	tsc.Parent = title
	title.TextScaled = true

	-- bar: 46 percent of the screen width, at least 280 px, art aspect kept
	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.AnchorPoint = Vector2.new(0.5, 0.5)
	bar.Position = UDim2.fromScale(0.5, 0.8)
	bar.Size = UDim2.fromScale(0.46, 0.46 * 0.2)
	bar.BackgroundTransparency = 1
	bar.Parent = fade
	local sc = Instance.new("UISizeConstraint")
	sc.MinSize = Vector2.new(280, 56)
	sc.Parent = bar
	local ar = Instance.new("UIAspectRatioConstraint")
	ar.AspectRatio = BAR_ART.w / BAR_ART.h
	ar.AspectType = Enum.AspectType.ScaleWithParentSize
	ar.DominantAxis = Enum.DominantAxis.Width
	ar.Parent = bar

	local paintedBar = validId(SceneArt.loading_bar_frame)
	local channel = Instance.new("Frame")
	channel.Name = "Channel"
	channel.Position = UDim2.fromScale(CHANNEL.x0, CHANNEL.y0)
	channel.Size = UDim2.fromScale(CHANNEL.x1 - CHANNEL.x0, CHANNEL.y1 - CHANNEL.y0)
	channel.BackgroundColor3 = Color3.fromRGB(70, 42, 22)
	channel.BorderSizePixel = 0
	channel.ClipsDescendants = true
	channel.ZIndex = 1
	channel.Parent = bar
	local cc = Instance.new("UICorner")
	cc.CornerRadius = UDim.new(0.5, 0)
	cc.Parent = channel

	if paintedBar then
		local frame = Instance.new("ImageLabel")
		frame.Name = "BarFrame"
		frame.Size = UDim2.fromScale(1, 1)
		frame.BackgroundTransparency = 1
		frame.Image = SceneArt.loading_bar_frame
		frame.ImageRectOffset = Vector2.new(BAR_ART.x, BAR_ART.y)
		frame.ImageRectSize = Vector2.new(BAR_ART.w, BAR_ART.h)
		frame.ScaleType = Enum.ScaleType.Stretch
		frame.ZIndex = 3
		frame.Parent = bar
	else
		local wood = Instance.new("Frame")
		wood.Name = "BarFrame"
		wood.Size = UDim2.fromScale(1, 1)
		wood.BackgroundTransparency = 1
		wood.ZIndex = 3
		wood.Parent = bar
		local st = Instance.new("UIStroke")
		st.Color = BRASS
		st.Thickness = 3
		st.Parent = wood
		local wc = Instance.new("UICorner")
		wc.CornerRadius = UDim.new(0.3, 0)
		wc.Parent = wood
	end

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.new(0, 0, 1, 0)
	fill.BackgroundColor3 = AMBER
	fill.BorderSizePixel = 0
	fill.ClipsDescendants = true
	fill.ZIndex = 2
	fill.Parent = channel
	gradient(fill, Color3.fromRGB(255, 214, 120), Color3.fromRGB(214, 104, 28), 90)
	local fc = Instance.new("UICorner")
	fc.CornerRadius = UDim.new(0.5, 0)
	fc.Parent = fill

	local shimmer = Instance.new("Frame")
	shimmer.Name = "Shimmer"
	shimmer.Size = UDim2.new(0, 36, 1, 0)
	shimmer.Position = UDim2.new(0, -40, 0, 0)
	shimmer.BackgroundColor3 = Color3.fromRGB(255, 244, 210)
	shimmer.BackgroundTransparency = 0.7
	shimmer.BorderSizePixel = 0
	shimmer.ZIndex = 2
	shimmer.Parent = fill

	local ember = Instance.new("Frame") -- glowing spark at the leading edge
	ember.Name = "Ember"
	ember.AnchorPoint = Vector2.new(0.5, 0.5)
	ember.Size = UDim2.fromOffset(14, 14)
	ember.BackgroundColor3 = Color3.fromRGB(255, 226, 150)
	ember.BackgroundTransparency = 0.1
	ember.BorderSizePixel = 0
	ember.ZIndex = 2
	ember.Parent = channel
	local ec = Instance.new("UICorner")
	ec.CornerRadius = UDim.new(0.5, 0)
	ec.Parent = ember
	local emberGlow = Instance.new("Frame")
	emberGlow.AnchorPoint = Vector2.new(0.5, 0.5)
	emberGlow.Position = UDim2.fromScale(0.5, 0.5)
	emberGlow.Size = UDim2.fromScale(2.6, 2.6)
	emberGlow.BackgroundColor3 = AMBER
	emberGlow.BackgroundTransparency = 0.8
	emberGlow.BorderSizePixel = 0
	emberGlow.ZIndex = 2
	emberGlow.Parent = ember
	local egc = Instance.new("UICorner")
	egc.CornerRadius = UDim.new(0.5, 0)
	egc.Parent = emberGlow

	-- brass Ready pulse over the bar
	local pulse = Instance.new("Frame")
	pulse.Name = "ReadyPulse"
	pulse.AnchorPoint = Vector2.new(0.5, 0.5)
	pulse.Position = UDim2.fromScale(0.5, 0.5)
	pulse.Size = UDim2.fromScale(1, 1)
	pulse.BackgroundTransparency = 1
	pulse.ZIndex = 4
	pulse.Parent = bar
	local ps = Instance.new("UIStroke")
	ps.Color = BRASS
	ps.Thickness = 3
	ps.Transparency = 1
	ps.Parent = pulse
	local pcn = Instance.new("UICorner")
	pcn.CornerRadius = UDim.new(0.3, 0)
	pcn.Parent = pulse

	local status = label(fade, "Lighting the lanterns...", 18, CREAM)
	status.Name = "Status"
	status.AnchorPoint = Vector2.new(0.5, 0)
	status.Position = UDim2.fromScale(0.5, 0.865)
	status.Size = UDim2.fromScale(0.7, 0.05)

	local tip = label(fade, "", 16, CREAM)
	tip.Name = "Tip"
	tip.AnchorPoint = Vector2.new(0.5, 0)
	tip.Position = UDim2.fromScale(0.5, 0.92)
	tip.Size = UDim2.fromScale(0.86, 0.06)
	tip.TextTransparency = 0

	local skip = Instance.new("TextButton")
	skip.Name = "Skip"
	skip.AnchorPoint = Vector2.new(1, 1)
	skip.Position = UDim2.new(1, -20, 1, -20)
	skip.Size = UDim2.fromOffset(110, 44)
	skip.BackgroundColor3 = Color3.fromRGB(70, 46, 26)
	skip.Text = "Skip"
	skip.TextSize = 18
	skip.Font = Enum.Font.GothamMedium
	skip.TextColor3 = CREAM
	skip.Visible = false
	skip.Parent = fade
	local sk = Instance.new("UICorner")
	sk.CornerRadius = UDim.new(0, 8)
	sk.Parent = skip
	local sks = Instance.new("UIStroke")
	sks.Color = BRASS
	sks.Thickness = 2
	sks.Parent = skip

	-- state
	local handle = { gui = gui }
	local alive = true
	local startClock = os.clock()
	local target = 0
	local display = 0
	local lastProgressAt = startClock
	local lastTarget = 0
	local frozen = opts.frozen and LoadProgress.clamp01(opts.frozen) or nil
	local ready = false
	local fading = false
	local order = LoadingTips.order(math.floor(os.clock() * 1000) + 7)
	local tipIndex, tipAt = 0, -100
	local conn

	local function showTip(now)
		tipIndex = (tipIndex % #order) + 1
		tip.Text = LoadingTips.TIPS[order[tipIndex]]
		tipAt = now
		tip.TextTransparency = 1
		TweenService:Create(tip, TweenInfo.new(0.3), { TextTransparency = 0 }):Play()
	end

	local function stop()
		alive = false
		if conn then conn:Disconnect() conn = nil end
	end

	function handle.destroy()
		stop()
		fade.Active = false
		fade.Visible = false
		gui.Enabled = false
		gui:Destroy()
	end

	function handle.isAlive() return alive end
	function handle.setTarget(v) target = LoadProgress.clamp01(v) end
	function handle.setReady() ready = true end

	function handle.fadeOut()
		if fading or not alive then return end
		fading = true
		fade.Active = false
		local tw = TweenService:Create(fade, TweenInfo.new(LoadProgress.FADE_TIME), { GroupTransparency = 1 })
		tw.Completed:Connect(function() handle.destroy() end)
		tw:Play()
		task.delay(LoadProgress.FADE_TIME + 1, function() if alive then handle.destroy() end end) -- never leave it up
	end

	skip.MouseButton1Click:Connect(function()
		if opts.onSkip then pcall(opts.onSkip) end
		handle.fadeOut()
	end)

	local readyShown = false
	conn = RunService.RenderStepped:Connect(function(dt)
		if not alive then return end
		local now = os.clock()
		local t = frozen or target
		if t > lastTarget + 0.0005 then lastTarget = t lastProgressAt = now end
		display = LoadProgress.ease(display, t, dt)
		if frozen then display = frozen end

		local innerW = channel.AbsoluteSize.X
		local px = LoadProgress.fillWidth(innerW, display)
		fill.Size = UDim2.new(0, px, 1, 0)
		-- shimmer sweep and ember flicker
		shimmer.Position = UDim2.new(0, ((now * 0.5) % 1.4) * math.max(px, 1) - 40, 0, 0)
		ember.Position = UDim2.new(0, math.max(7, px), 0.5, 0)
		ember.Visible = px > 2 and not ready
		local flick = 0.1 + 0.15 * math.abs(math.sin(now * 9))
		ember.BackgroundTransparency = flick
		emberGlow.BackgroundTransparency = 0.7 + 0.12 * math.abs(math.sin(now * 5))

		if not frozen then
			local slow = (now - startClock) >= LoadProgress.SKIP_AFTER
			local stalled = LoadProgress.stalled(now, lastProgressAt)
			status.Text = LoadProgress.status(display, stalled, slow)
			skip.Visible = slow
		end
		if now - tipAt >= LoadProgress.TIP_EVERY then showTip(now) end

		-- finish: bar full, Ready pulse, then fade (never before MIN_VISIBLE)
		if ready and not frozen and display >= 0.995 and not readyShown and (now - startClock) >= LoadProgress.MIN_VISIBLE then
			readyShown = true
			status.Text = "Ready"
			ps.Transparency = 0
			TweenService:Create(ps, TweenInfo.new(0.4), { Transparency = 1 }):Play()
			task.delay(0.35, function() handle.fadeOut() end)
		end
	end)

	return handle
end

return LoadingScreenUI
