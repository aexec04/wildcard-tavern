--[[
	Client/VisualHelpers.lua
	Small, generic presentation helpers used across almost every other
	client module: a tween shortcut, rounded corners, a soft drop shadow,
	a reusable "- value +" stepper row, and a real click-and-drag slider
	row (makeSliderRow, added for the Master Volume control -- see
	Client/Settings.lua -- once "just use a stepper" stopped being
	precise enough for dialing in volume to taste).

	Extracted out of init.client.lua as part of splitting the client script
	into smaller, per-feature files. Like Sound.lua, this is foundational --
	nearly every overlay module takes tweenTo/polishPanel/polishButton/
	roundCorner/addSoftShadow as deps -- so it's required early, right after
	Sound.lua (makeStepperRow/makeSliderRow need playClickSfx from Sound.lua).

	FOUND IT (kept from the original comment, still relevant): an earlier
	version of this helper set also had an addGloss() that layered a
	near-white UIGradient on top of buttons/cards using a Transparency
	sequence of 0.75 -> 0.9 -> 1.0 to fake a subtle highlight. In Roblox,
	UIGradient.Transparency does NOT add a highlight on top of the object's
	own color -- it OVERRIDES how see-through the object is at each point. A
	sequence that's 75-100% transparent across almost the whole object means
	you're mostly looking straight through the button/card to whatever's
	behind it (the dark table background), not seeing a gloss at all. That's
	the actual cause of the "everything looks near-black" bug this whole
	project chased once. addGloss is left out entirely; rounded corners
	alone are zero-risk since they don't touch color or transparency.

	deps fields:
		TweenService     -- the TweenService
		UserInputService -- the UserInputService, for makeSliderRow's drag tracking
		playClickSfx     -- function(volume?), for the stepper/slider row controls

	Returns:
		{
			tweenTo = function(instance, properties, duration, style?, direction?),
			roundCorner = function(instance, radius?),
			polishButton = function(instance, radius?),
			polishPanel = function(instance, radius?),
			addSoftShadow = function(panel, radius?),
			makeStepperRow = function(parent, labelText, min, max, step,
			                          getValue, setValue, formatValue) -> refresh,
			makeSliderRow = function(parent, labelText, min, max,
			                         getValue, setValue, formatValue) -> refresh,
			screenShake = function(target, intensity, duration?),
		}
]]

return function(deps)
	local TweenService = deps.TweenService
	local UserInputService = deps.UserInputService
	local playClickSfx = deps.playClickSfx

	local function tweenTo(instance, properties, duration, style, direction)
		local tween = TweenService:Create(
			instance,
			TweenInfo.new(duration, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out),
			properties
		)
		tween:Play()
		return tween
	end

	local function roundCorner(instance, radius)
		if instance:FindFirstChildOfClass("UICorner") then
			return
		end
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, radius or 10)
		corner.Parent = instance
	end

	local function polishButton(instance, radius)
		roundCorner(instance, radius or 10)
	end

	local function polishPanel(instance, radius)
		roundCorner(instance, radius or 16)
	end

	-- FEATURE 3: a soft drop shadow behind a panel -- a plain, offset,
	-- fixed-transparency black Frame placed just behind it. Unlike addGloss,
	-- this uses ordinary BackgroundTransparency (0.55, constant, not a
	-- gradient), which blends normally -- it can only ever darken the thin
	-- offset border area behind a panel, never the panel's own content.
	local function addSoftShadow(panel, radius)
		local shadow = Instance.new("Frame")
		shadow.Name = "Shadow"
		shadow.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
		shadow.BackgroundTransparency = 0.55
		shadow.Size = UDim2.new(1, 14, 1, 14)
		shadow.Position = UDim2.new(0, -7, 0, 4)
		shadow.BorderSizePixel = 0
		shadow.ZIndex = math.max(0, panel.ZIndex - 1)
		shadow.Parent = panel.Parent
		roundCorner(shadow, radius or 18)
		return shadow
	end

	-- SCORING JUICE: whole-screen shake. Jitters `target`'s Position by small
	-- random pixel offsets a few times, easing back to rest. Shakes the UI
	-- itself rather than the 3D camera -- TavernScene.server.lua explicitly
	-- never touches the camera/character (see its own header comment), and a
	-- UI shake reads just as "juicy" for a card game where the action IS the
	-- UI, with zero risk of ever fighting a future camera script. Intended
	-- target is the game's full-screen root Frame (see Client/ScorePopup.lua).
	--
	-- `intensity` is the max pixel offset per jitter step; `duration`
	-- (seconds, default 0.25) is spread across a fixed number of quick
	-- steps, easing out, so a bigger shake hits harder rather than just
	-- lasting longer.
	--
	-- Rest-position tracking: the FIRST time screenShake is ever called on a
	-- given target, its current Position is remembered as "home" (in a
	-- weak-keyed table, so it doesn't leak if the target is ever destroyed).
	-- Every shake -- including several fired back-to-back while an earlier
	-- one is still mid-tween, which is exactly what a fast chip/mult/xmult
	-- reveal sequence does -- always jitters relative to that SAME home
	-- position, never to wherever the target happens to be mid-jitter. That
	-- prevents rapid overlapping shakes from ever drifting the screen away
	-- from center, since every tween (including the final settle) always
	-- aims at the one true rest position. Known rough edge, left for a
	-- future polish pass rather than this one: overlapping shakes don't
	-- cancel each other, they just each keep tweening toward home in
	-- parallel -- harmless (no drift, nothing ever gets stuck off-center),
	-- just not perfectly crisp when many fire back-to-back in under
	-- `duration` seconds of each other.
	local shakeRestPositions = setmetatable({}, { __mode = "k" })
	local function screenShake(target, intensity, duration)
		duration = duration or 0.25
		if not shakeRestPositions[target] then
			shakeRestPositions[target] = target.Position
		end
		local restPosition = shakeRestPositions[target]
		local steps = 5
		local stepTime = duration / steps
		task.spawn(function()
			for i = 1, steps do
				local falloff = 1 - (i / steps) -- ease out -- later jitters are smaller
				local dx = (math.random() * 2 - 1) * intensity * falloff
				local dy = (math.random() * 2 - 1) * intensity * falloff
				tweenTo(target, { Position = restPosition + UDim2.fromOffset(dx, dy) }, stepTime, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
				task.wait(stepTime)
			end
			tweenTo(target, { Position = restPosition }, stepTime, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
		end)
	end

	-- Used by the Settings overlay.
	local function makeStepperRow(parent, labelText, min, max, step, getValue, setValue, formatValue)
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, 0, 0, 46)
		row.BackgroundTransparency = 1
		row.Parent = parent

		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(0.5, 0, 1, 0)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.Gotham
		label.TextSize = 15
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextColor3 = Color3.fromRGB(240, 230, 215)
		label.Text = labelText
		label.ZIndex = 21
		label.Parent = row

		local controlHolder = Instance.new("Frame")
		controlHolder.Size = UDim2.new(0.5, 0, 1, 0)
		controlHolder.Position = UDim2.new(0.5, 0, 0, 0)
		controlHolder.BackgroundTransparency = 1
		controlHolder.ZIndex = 21
		controlHolder.Parent = row

		local controlLayout = Instance.new("UIListLayout")
		controlLayout.FillDirection = Enum.FillDirection.Horizontal
		controlLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
		controlLayout.VerticalAlignment = Enum.VerticalAlignment.Center
		controlLayout.Padding = UDim.new(0, 10)
		controlLayout.Parent = controlHolder

		local minusButton = Instance.new("TextButton")
		minusButton.Size = UDim2.new(0, 34, 0, 34)
		minusButton.Font = Enum.Font.GothamBold
		minusButton.TextSize = 18
		minusButton.Text = "-"
		minusButton.BackgroundColor3 = Color3.fromRGB(60, 45, 32)
		minusButton.TextColor3 = Color3.fromRGB(250, 240, 220)
		minusButton.ZIndex = 21
		minusButton.Parent = controlHolder
		polishButton(minusButton, 8)

		local valueLabel = Instance.new("TextLabel")
		valueLabel.Size = UDim2.new(0, 60, 1, 0)
		valueLabel.BackgroundTransparency = 1
		valueLabel.Font = Enum.Font.GothamBold
		valueLabel.TextSize = 15
		valueLabel.TextColor3 = Color3.fromRGB(255, 214, 130)
		valueLabel.ZIndex = 21
		valueLabel.Parent = controlHolder

		local plusButton = Instance.new("TextButton")
		plusButton.Size = UDim2.new(0, 34, 0, 34)
		plusButton.Font = Enum.Font.GothamBold
		plusButton.TextSize = 18
		plusButton.Text = "+"
		plusButton.BackgroundColor3 = Color3.fromRGB(60, 45, 32)
		plusButton.TextColor3 = Color3.fromRGB(250, 240, 220)
		plusButton.ZIndex = 21
		plusButton.Parent = controlHolder
		polishButton(plusButton, 8)

		local function refresh()
			local value = getValue()
			valueLabel.Text = formatValue and formatValue(value) or tostring(value)
		end

		minusButton.MouseButton1Click:Connect(function()
			playClickSfx(0.35)
			setValue(math.max(min, getValue() - step))
			refresh()
		end)
		plusButton.MouseButton1Click:Connect(function()
			playClickSfx(0.35)
			setValue(math.min(max, getValue() + step))
			refresh()
		end)

		refresh()
		return refresh
	end

	-- Real click-and-drag slider row -- used for Master Volume (see
	-- Client/Settings.lua), where a stepper's fixed 10%-per-click jumps
	-- weren't fine-grained enough to actually dial the music down to a
	-- comfortable level. `min`/`max` are inclusive bounds; the dragged
	-- value is always rounded to the nearest whole number (plenty precise
	-- for a 0-100 volume percentage, and keeps the value label from
	-- jittering on fractional pixels).
	--
	-- Track + fill + knob, all children of the same row so ZIndex ordering
	-- is automatic. Both the track AND the knob start a drag on
	-- InputBegan (the knob sits visually on top of the track, so without
	-- wiring both, clicking directly on the knob wouldn't register on the
	-- track underneath it). UserInputService's global InputChanged/
	-- InputEnded track the drag once started, so releasing the mouse
	-- outside the row still ends the drag cleanly.
	local function makeSliderRow(parent, labelText, min, max, getValue, setValue, formatValue)
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, 0, 0, 46)
		row.BackgroundTransparency = 1
		row.Parent = parent

		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(0.35, 0, 1, 0)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.Gotham
		label.TextSize = 15
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextColor3 = Color3.fromRGB(240, 230, 215)
		label.Text = labelText
		label.ZIndex = 21
		label.Parent = row

		local valueLabel = Instance.new("TextLabel")
		valueLabel.Size = UDim2.new(0, 50, 1, 0)
		valueLabel.Position = UDim2.new(1, -50, 0, 0)
		valueLabel.BackgroundTransparency = 1
		valueLabel.Font = Enum.Font.GothamBold
		valueLabel.TextSize = 15
		valueLabel.TextColor3 = Color3.fromRGB(255, 214, 130)
		valueLabel.TextXAlignment = Enum.TextXAlignment.Right
		valueLabel.ZIndex = 21
		valueLabel.Parent = row

		local trackHolder = Instance.new("Frame")
		trackHolder.Size = UDim2.new(0.65, -60, 1, 0)
		trackHolder.Position = UDim2.new(0.35, 0, 0, 0)
		trackHolder.BackgroundTransparency = 1
		trackHolder.ZIndex = 21
		trackHolder.Parent = row

		local track = Instance.new("Frame")
		track.Size = UDim2.new(1, 0, 0, 8)
		track.AnchorPoint = Vector2.new(0, 0.5)
		track.Position = UDim2.new(0, 0, 0.5, 0)
		track.BackgroundColor3 = Color3.fromRGB(60, 45, 32)
		track.ZIndex = 21
		track.Parent = trackHolder
		polishButton(track, 4)

		local fill = Instance.new("Frame")
		fill.Size = UDim2.new(0, 0, 1, 0)
		fill.BackgroundColor3 = Color3.fromRGB(255, 214, 130)
		fill.BorderSizePixel = 0
		fill.ZIndex = 22
		fill.Parent = track
		polishButton(fill, 4)

		local knob = Instance.new("Frame")
		knob.Size = UDim2.new(0, 18, 0, 18)
		knob.AnchorPoint = Vector2.new(0.5, 0.5)
		knob.Position = UDim2.new(0, 0, 0.5, 0)
		knob.BackgroundColor3 = Color3.fromRGB(250, 240, 220)
		knob.ZIndex = 23
		knob.Parent = track
		polishButton(knob, 9)

		local function valueFromInputX(inputX)
			local trackPos = track.AbsolutePosition.X
			local trackWidth = track.AbsoluteSize.X
			if trackWidth <= 0 then
				return getValue()
			end
			local fraction = math.clamp((inputX - trackPos) / trackWidth, 0, 1)
			return math.floor(min + fraction * (max - min) + 0.5)
		end

		local function refresh()
			local value = getValue()
			valueLabel.Text = formatValue and formatValue(value) or tostring(value)
			local fraction = (max > min) and math.clamp((value - min) / (max - min), 0, 1) or 0
			fill.Size = UDim2.new(fraction, 0, 1, 0)
			knob.Position = UDim2.new(fraction, 0, 0.5, 0)
		end

		local dragging = false
		local function isDragInput(input)
			return input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
		end

		local function beginDrag(input)
			if not isDragInput(input) then
				return
			end
			dragging = true
			playClickSfx(0.25)
			setValue(valueFromInputX(input.Position.X))
			refresh()
		end

		track.InputBegan:Connect(beginDrag)
		knob.InputBegan:Connect(beginDrag)

		UserInputService.InputChanged:Connect(function(input)
			if not dragging then
				return
			end
			if input.UserInputType == Enum.UserInputType.MouseMovement
				or input.UserInputType == Enum.UserInputType.Touch then
				setValue(valueFromInputX(input.Position.X))
				refresh()
			end
		end)

		UserInputService.InputEnded:Connect(function(input)
			if dragging and isDragInput(input) then
				dragging = false
			end
		end)

		refresh()
		return refresh
	end

	return {
		tweenTo = tweenTo,
		roundCorner = roundCorner,
		polishButton = polishButton,
		polishPanel = polishPanel,
		addSoftShadow = addSoftShadow,
		makeStepperRow = makeStepperRow,
		makeSliderRow = makeSliderRow,
		screenShake = screenShake,
	}
end
