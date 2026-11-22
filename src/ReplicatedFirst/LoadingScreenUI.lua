--[[
	ReplicatedFirst/LoadingScreenUI.lua
	Builds the launch loading screen: painted tavern doorway (loading_scene_bg), the wordmark, a wooden beam
	progress bar (loading_bar_frame, code-drawn wood when the id is missing) with a gold fill on a dark track
	inside the plate and an ember at the leading edge, a status line and a rotating tip. Rules (weights, easing, tips)
	are in Engine/LoadProgress and Engine/LoadingTips. The two scrims are the only UIGradient Transparency use (a fade, Engine/ScrimGradient).
	LoadingScreenUI.show(playerGui, { shared = ReplicatedStorage.Shared, frozen = 0..1 or nil, onSkip = fn })
	  -> handle { gui, setTarget(v), setReady(), fadeOut(), destroy(), isAlive() }
]]

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local LoadingScreenUI = {}

local BAR_ART = { x = 0, y = 360, w = 1536, h = 305 } -- the beam inside the 1536x1024 picture
-- the track sits 14 px inside the 700 x 80 plate (fractions of the plate, so it scales with it)
local INSET_X, INSET_Y = 14 / 700, 14 / 80
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
	l.TextSize = math.max(16, size)
	l.TextColor3 = color
	l.Font = font or Enum.Font.Fondamento
	l.TextWrapped = true
	l.TextTransparency = 0
	l.TextStrokeTransparency = 0 -- a 1 px dark outline
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
	local Layout = Engine and require(Engine:WaitForChild("LoadingLayout"))
	if not (LoadProgress and LoadingTips and Layout) then return nil end
	local calm = opts.calm == true
	local motion = Layout.motion(calm)

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
	-- the colour wash is a plain Frame behind the painting: a UIGradient on the CanvasGroup itself multiplies every child (screen near black)
	local backdrop = Instance.new("Frame")
	backdrop.Name = "Backdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	backdrop.BorderSizePixel = 0
	backdrop.Parent = fade
	gradient(backdrop, Color3.fromRGB(26, 20, 30), Color3.fromRGB(8, 6, 8), 90)

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
	bar.Position = UDim2.fromScale(0.5, Layout.BAR_CENTER_Y)
	bar.Size = UDim2.fromScale(Layout.BAR_WIDTH, Layout.BAR_WIDTH / Layout.BAR_ASPECT)
	bar.BackgroundTransparency = 1
	bar.Parent = fade
	local sc = Instance.new("UISizeConstraint")
	sc.MinSize = Vector2.new(Layout.BAR_MIN_W, Layout.BAR_MIN_W / Layout.BAR_ASPECT)
	sc.MaxSize = Vector2.new(Layout.BAR_MAX_W, Layout.BAR_MAX_W / Layout.BAR_ASPECT)
	sc.Parent = bar
	local ar = Instance.new("UIAspectRatioConstraint")
	ar.AspectRatio = Layout.BAR_ASPECT
	ar.AspectType = Enum.AspectType.ScaleWithParentSize
	ar.DominantAxis = Enum.DominantAxis.Width
	ar.Parent = bar

	local paintedBar = validId(SceneArt.loading_bar_frame)
	local channel = Instance.new("Frame")
	channel.Name = "Channel"
	channel.Position = UDim2.fromScale(INSET_X, INSET_Y)
	channel.Size = UDim2.fromScale(1 - 2 * INSET_X, 1 - 2 * INSET_Y)
	channel.BackgroundColor3 = Color3.fromRGB(Layout.TRACK.track[1], Layout.TRACK.track[2], Layout.TRACK.track[3])
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
	fill.BackgroundColor3 = Color3.fromRGB(Layout.TRACK.fill[1], Layout.TRACK.fill[2], Layout.TRACK.fill[3])
	fill.BorderSizePixel = 0
	fill.ClipsDescendants = true
	fill.ZIndex = 2
	fill.Parent = channel
	local fc = Instance.new("UICorner")
	fc.CornerRadius = UDim.new(0.5, 0)
	fc.Parent = fill

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

	local status = label(fade, "Lighting the lanterns...", Layout.STATUS_TEXT, CREAM, Enum.Font.Fondamento)
	status.Name = "Status"
	status.AnchorPoint = Vector2.new(0, 0)

	local tip = label(fade, "", Layout.TIP_TEXT, CREAM, Enum.Font.Fondamento)
	tip.Name = "Tip"
	tip.AnchorPoint = Vector2.new(0, 0)
	tip.TextYAlignment = Enum.TextYAlignment.Top
	local tipPlate -- built under applyLayout, which places it
	-- status and tip sit under the bar in pixels from LoadingLayout, so nothing overlaps at any size
	local function applyLayout()
		local sz = fade.AbsoluteSize
		if sz.X < 10 or sz.Y < 10 then return end
		local r = Layout.rects(sz.X, sz.Y)
		status.Position = UDim2.fromOffset(r.status.x, r.status.y)
		status.Size = UDim2.fromOffset(r.status.w, r.status.h)
		tip.Position = UDim2.fromOffset(r.tip.x, r.tip.y)
		tip.Size = UDim2.fromOffset(r.tip.w, r.tip.h)
		if tipPlate then
			tipPlate.Position = UDim2.fromOffset(r.tip.x - 8, r.tip.y - 4)
			tipPlate.Size = UDim2.fromOffset(r.tip.w + 16, r.tip.h + 8)
		end
	end
	fade:GetPropertyChangedSignal("AbsoluteSize"):Connect(applyLayout)
	applyLayout()
	tip.TextTransparency = 0
	-- a plate behind the tip, drawn only when an equipped Card Set is known (see handle.setSet); classic leaves it hidden
	tipPlate = Instance.new("Frame")
	tipPlate.Name = "TipPlate"
	tipPlate.Visible = false
	tipPlate.BackgroundColor3 = Color3.fromRGB(40, 28, 20)
	tipPlate.BorderSizePixel = 0
	tipPlate.ZIndex = math.max(1, tip.ZIndex - 1)
	tipPlate.Parent = fade
	do
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, 8)
		c.Parent = tipPlate
	end
	local tipPlateStroke = Instance.new("UIStroke")
	tipPlateStroke.Thickness = 2
	tipPlateStroke.Color = BRASS
	tipPlateStroke.Parent = tipPlate
	applyLayout()

	local skip = Instance.new("TextButton")
	skip.Name = "Skip"
	skip.AnchorPoint = Vector2.new(1, 1)
	skip.Position = UDim2.new(1, -20, 1, -20)
	skip.Size = UDim2.fromOffset(110, 44)
	skip.BackgroundColor3 = Color3.fromRGB(70, 46, 26)
	skip.Text = "Skip"
	skip.TextSize = 18
	skip.Font = Enum.Font.Fondamento
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

	-- The equipped Card Set tints the tip plate, Skip plate and bar trim (colours only, no tween, so Calm mode is unchanged). nil restores classic.
	function handle.setSet(setId)
		local style
		pcall(function()
			local CS = Engine and Engine:FindFirstChild("CosmeticSets") and require(Engine.CosmeticSets)
			style = CS and CS.loadingStyleOf(setId)
		end)
		local edge, ink = BRASS, CREAM
		tipPlate.Visible = style ~= nil
		if style then
			local p = style.plate
			tipPlate.BackgroundColor3 = Color3.fromRGB(p[1], p[2], p[3])
			tipPlate.BackgroundTransparency = style.tipAlpha
			edge = Color3.fromRGB(style.edge[1], style.edge[2], style.edge[3])
			ink = Color3.fromRGB(style.ink[1], style.ink[2], style.ink[3])
			skip.BackgroundColor3 = Color3.fromRGB(p[1], p[2], p[3])
		else
			skip.BackgroundColor3 = Color3.fromRGB(70, 46, 26)
		end
		tipPlateStroke.Color = edge
		sks.Color = edge
		ps.Color = edge
		tip.TextColor3 = ink
		status.TextColor3 = ink
		skip.TextColor3 = ink
	end
	if opts.setId then handle.setSet(opts.setId) end
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

	local function showTip(now, first)
		tipIndex = (tipIndex % #order) + 1
		tip.Text = LoadingTips.TIPS[order[tipIndex]]
		tipAt = now
		if motion.tipFade and not (first and not motion.firstTipFade) then
			tip.TextTransparency = 1
			TweenService:Create(tip, TweenInfo.new(0.3), { TextTransparency = 0 }):Play()
		else
			tip.TextTransparency = 0
		end
	end

	showTip(os.clock(), true) -- the first kind tip is on screen in the very first frame, with the title, no fade from empty

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
		local tw = TweenService:Create(fade, TweenInfo.new(Layout.fadeTime(calm, LoadProgress.FADE_TIME)), { GroupTransparency = 1 })
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
		-- ember flicker
		ember.Position = UDim2.new(0, math.max(7, px), 0.5, 0)
		ember.Visible = px > 2 and not ready
		if motion.ember then
			ember.BackgroundTransparency = 0.1 + 0.15 * math.abs(math.sin(now * 9))
			emberGlow.BackgroundTransparency = 0.7 + 0.12 * math.abs(math.sin(now * 5))
		end

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
			if motion.readyPulse then
				ps.Transparency = 0
				TweenService:Create(ps, TweenInfo.new(0.4), { Transparency = 1 }):Play()
			end
			task.delay(motion.readyPulse and 0.35 or 0.15, function() handle.fadeOut() end)
		end
	end)

	return handle
end

return LoadingScreenUI
