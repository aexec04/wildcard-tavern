--[[
	Client/ActionButtonFX.lua
	Flavor and motion for the four gameplay buttons, in the tavern style. Tweens only, no per-frame loops,
	nothing allocated per frame. It decorates the existing buttons (the hub keeps their layout, art and click
	handlers) with a UIScale and a few decorative children that live INSIDE each button:

	  Play Hand  a big wooden sign with a lit lantern: a lantern icon and an ember glow ring that pulse
	             softly while cards are selected, dim and stay still when nothing is. A spark puff on click.
	  Discard    a dark iron plate (cooler tint) with a cards icon that wobbles on hover; a paper flutter
	             (cream flecks) on click. Dim and still when nothing is selected.
	  Rank/Suit  small brass tags: they swivel with a short squash when toggled and the active one keeps a lit
	             gold edge.
	  All        hover swell (1.05), press squash (0.94, a 6 percent squash) with a springy release, a rate
	             limited hover cue (Cue "hover", skipped silently when no sound exists). Hit areas are
	             unchanged (large for phones). "Reduce screen shake" skips every motion and particle, keeping
	             only the dim/lit states.

	install{ play, discard, rank, suit, burst }   once, from the hub
	setSelection(count)                           cards currently selected (drives ready/dim)
	setSort(mode)                                 "rank" | "suit" | nil (the active sort's lit edge)

	The rules live in Engine/ButtonFeel (pure, tested).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Engine = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine")
local ButtonFeel = require(Engine:WaitForChild("ButtonFeel"))
local ClientSettings = require(script.Parent.ClientSettings)

local GOLD = Color3.fromRGB(222, 182, 104)
local EMBER = Color3.fromRGB(255, 170, 70)

local ActionButtonFX = {}

local state = { buttons = {}, selection = 0, sort = nil, burst = nil }
local lastHover = 0

local function calm()
	return ClientSettings.get("reduceShake") == true
end

local function tween(inst, props, time, style, dir)
	local t = TweenService:Create(inst, TweenInfo.new(time, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
	t:Play()
	return t
end

local function corner(inst, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = inst
	return c
end

local function icon(button, text, x)
	local l = Instance.new("TextLabel")
	l.Name = "FXIcon"
	l.AnchorPoint = Vector2.new(0, 0.5)
	l.Position = UDim2.new(0, x, 0.5, 0)
	l.Size = UDim2.fromOffset(30, 30)
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBold
	l.TextSize = 22
	l.Text = text
	l.TextColor3 = Color3.fromRGB(255, 232, 180)
	l.Active = false
	l.ZIndex = button.ZIndex + 2
	l.Visible = false -- emoji glyphs rendered as tiny misplaced blobs beside the label; the button text is clear on its own
	l.Parent = button
	return l
end

local function ring(button, color, thickness, name)
	local f = Instance.new("Frame")
	f.Name = name
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromScale(0.5, 0.5)
	f.Size = UDim2.new(1, 4, 1, 4)
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	f.Active = false
	f.ZIndex = button.ZIndex + 1
	f.Parent = button
	corner(f, 10)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.Transparency = 1
	s.Parent = f
	return f, s
end

-- Dim / restore the button's art and text without touching its layout.
local function setDim(entry, dim)
	local btn = entry.button
	local art = btn:FindFirstChild("SkinArt")
	if art and art:IsA("ImageLabel") then
		entry.artColor = entry.artColor or art.ImageColor3
		art.ImageColor3 = dim and entry.artColor:Lerp(Color3.fromRGB(70, 70, 70), 0.45) or entry.artColor
	end
	local face = btn:FindFirstChild("HudFace") -- code-drawn themed base
	if face then face.BackgroundTransparency = dim and 0.45 or 0 end
	btn.TextTransparency = dim and 0.35 or 0
	for _, child in ipairs(btn:GetChildren()) do
		if child.Name == "FXIcon" then child.TextTransparency = dim and 0.55 or 0 end
	end
end

local function updateScale(entry)
	if calm() then
		entry.scale.Scale = 1
		return
	end
	local target = ButtonFeel.scaleFor(entry.hover, entry.pressed)
	local style, dir = Enum.EasingStyle.Quad, Enum.EasingDirection.Out
	if not entry.pressed and entry.wasPressed then
		style, dir = Enum.EasingStyle.Back, Enum.EasingDirection.Out -- springy release
	end
	entry.wasPressed = entry.pressed
	tween(entry.scale, { Scale = target }, entry.pressed and 0.06 or 0.14, style, dir)
end

local function wire(entry)
	local btn = entry.button
	btn.MouseEnter:Connect(function()
		entry.hover = true
		updateScale(entry)
		if not calm() and entry.onHover then entry.onHover() end
		local now = os.clock()
		if now - lastHover >= 0.1 then
			lastHover = now
			pcall(function() require(script.Parent.Cue).play("hover") end)
		end
	end)
	btn.MouseLeave:Connect(function()
		entry.hover, entry.pressed = false, false
		updateScale(entry)
	end)
	btn.MouseButton1Down:Connect(function()
		entry.pressed = true
		updateScale(entry)
	end)
	btn.MouseButton1Up:Connect(function()
		entry.pressed = false
		updateScale(entry)
	end)
end

local function addScale(btn)
	local s = Instance.new("UIScale") -- scales the drawing only; the layout slot never changes
	s.Name = "FXScale"
	s.Parent = btn
	return s
end

local function puff(btn, color, count, spread)
	if calm() or not state.burst then return end
	local pos = btn.AbsolutePosition + btn.AbsoluteSize / 2
	pcall(state.burst, UDim2.fromOffset(pos.X, pos.Y), color, count, { spread = spread, size = 5, duration = 0.45 })
end

function ActionButtonFX.install(opts)
	state.burst = opts.burst

	-- ===== Play Hand: wooden sign with a lit lantern =====
	do
		local btn = opts.play
		local entry = { button = btn, scale = addScale(btn), hover = false, pressed = false }
		state.buttons.play = entry
		local lantern = icon(btn, "🏮", 12)
		local glowFrame, glowStroke = ring(btn, EMBER, 4, "EmberGlow")
		entry.glowStroke = glowStroke
		entry.lantern = lantern
		function entry.setReady(ready)
			setDim(entry, not ready)
			if entry.pulse then entry.pulse:Cancel() entry.pulse = nil end
			if ready then
				glowStroke.Transparency = 0.55
				if not calm() then
					entry.pulse = TweenService:Create(glowStroke,
						TweenInfo.new(1.1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Transparency = 0.9 })
					entry.pulse:Play()
				end
			else
				glowStroke.Transparency = 1 -- dim and still
			end
		end
		btn.MouseButton1Click:Connect(function()
			if state.selection >= 1 then puff(btn, EMBER, 12, 70) end
		end)
		wire(entry)
		entry.setReady(false)
	end

	-- ===== Discard: dark iron plate with a wobbling icon =====
	do
		local btn = opts.discard
		local entry = { button = btn, scale = addScale(btn), hover = false, pressed = false }
		state.buttons.discard = entry
		local cards = icon(btn, "🃏", 12)
		local art = btn:FindFirstChild("SkinArt")
		local function iron(a)
			if a and a:IsA("ImageLabel") and not a:GetAttribute("IronTinted") then
				a:SetAttribute("IronTinted", true)
				a.ImageColor3 = a.ImageColor3:Lerp(Color3.fromRGB(110, 124, 150), 0.38) -- cooler, darker: iron, not wood
			end
		end
		iron(art)
		btn.ChildAdded:Connect(function(child)
			if child.Name == "SkinArt" then iron(child) end
		end)
		entry.onHover = function()
			local rots = { -12, 12, -8, 8, 0 }
			task.spawn(function()
				for _, r in ipairs(rots) do
					if not cards.Parent then return end
					tween(cards, { Rotation = r }, 0.07, Enum.EasingStyle.Sine)
					task.wait(0.07)
				end
			end)
		end
		function entry.setReady(ready)
			setDim(entry, not ready)
		end
		btn.MouseButton1Click:Connect(function()
			if state.selection >= 1 then puff(btn, Color3.fromRGB(240, 230, 205), 7, 55) end -- paper flutter
		end)
		wire(entry)
		entry.setReady(false)
	end

	-- ===== Rank / Suit: brass tags with a swivel and a lit edge =====
	local tags = {}
	for _, spec in ipairs({ { key = "rank", btn = opts.rank }, { key = "suit", btn = opts.suit } }) do
		if not spec.btn:GetAttribute("Segment") then table.insert(tags, spec) end -- the segmented Rank | Suit toggle (Client/SortToggle) lights itself
	end
	for _, spec in ipairs(tags) do
		local btn = spec.btn
		local entry = { button = btn, scale = addScale(btn), hover = false, pressed = false, key = spec.key }
		state.buttons[spec.key] = entry
		local _, litStroke = ring(btn, Color3.fromRGB(255, 226, 140), 3, "LitEdge")
		entry.litStroke = litStroke
		btn.MouseButton1Click:Connect(function()
			if calm() then return end
			-- short swivel: a quick rotation wobble with a squash
			task.spawn(function()
				for _, r in ipairs({ -7, 7, -3, 0 }) do
					if not btn.Parent then return end
					tween(btn, { Rotation = r }, 0.05, Enum.EasingStyle.Sine)
					task.wait(0.05)
				end
			end)
		end)
		wire(entry)
	end
	ActionButtonFX.setSort(state.sort)
	ActionButtonFX.setSelection(state.selection)
end

function ActionButtonFX.setSelection(count)
	state.selection = count or 0
	local ready = ButtonFeel.playReady(state.selection)
	for _, key in ipairs({ "play", "discard" }) do
		local entry = state.buttons[key]
		if entry and entry.ready ~= ready then
			entry.ready = ready
			entry.setReady(ready)
		end
	end
end

function ActionButtonFX.setSort(mode)
	state.sort = mode
	for _, key in ipairs({ "rank", "suit" }) do
		local entry = state.buttons[key]
		if entry and entry.litStroke then
			entry.litStroke.Transparency = (mode == key) and 0.1 or 1
		end
	end
end

return ActionButtonFX
