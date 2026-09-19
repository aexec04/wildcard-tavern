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
			popIn = function(backdrop, content, opts?),
			popOut = function(backdrop, content, opts?, onHidden?),
			pulseFrame = function(frame, flashColor, opts?),
			popScale = function(instance, fromScale?, duration?),
			addButtonHoverScale = function(button, opts?),
			revealStagger = function(instances, opts?),
			makePortraitBadge = function(parent, icon, accentColor, opts?) -> badge,
			tintBackground = function(frame, accentColor, strength?),
		}

	POLISH PASS (post-Phase-7, "great animations" ask): the 4 functions
	added at the bottom (popIn/popOut/pulseFrame/popScale) are shared,
	generic versions of animation patterns that already existed ad hoc in
	one place each -- GameOver.lua hand-rolled its own pop-in reveal
	(UIScale + staggered transparency tweens), and ScorePopup.lua's private
	pulsePatronSlot() flashes a Patron's Sidebar seat with an overlap-safe
	rest-color cache. Pulling the general shape of both out here means the
	next modal/indicator that wants the same treatment (ConfirmDialog,
	Sidebar's Tips/Hands/Discards/Patron-slot boxes, below) doesn't have to
	re-derive it -- and, importantly, doesn't accidentally re-introduce a
	bug that was already found and fixed once (see pulseFrame's own
	comment for why naive color-revert-on-settle is a real footgun).
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
	--
	-- PERF/BUGFIX (technical-debt pass): this used to size itself as
	-- `UDim2.new(1, 14, 1, 14)` of panel.Parent -- i.e. "the panel's own
	-- size plus 14px" ONLY held true if the panel's parent happened to be
	-- ~1:1 sized with the panel itself. In practice every one of this
	-- function's call sites parents a modal panel inside a full-screen
	-- backdrop Frame, so `1, 14` resolved to "100% of the screen plus
	-- 14px" -- a second near-fullscreen dark overlay stacked behind every
	-- dialog in the game, not a soft edge shadow. Reading the panel's own
	-- Size/Position/AnchorPoint directly and sizing the shadow relative to
	-- THOSE (scaled against the real parent) fixes all ~10 call sites.
	--
	-- The X/Y offset math below has to compensate for panel.AnchorPoint,
	-- not just copy it onto the shadow: growing Size by a flat +14/+14
	-- while keeping the SAME anchor point shifts where that extra 14px
	-- lands relative to the panel's actual edges (an independent review
	-- caught this -- a first pass that didn't compensate produced a
	-- lopsided shadow, thick on one side and invisible on the other, for
	-- every centered/AnchorPoint(0.5,0.5) dialog: ConfirmDialog, GameOver,
	-- Journey). Solving "shadow's left/top/right/bottom edges sit exactly
	-- {7, -4(recede), 7, 18} px past the panel's own edges, regardless of
	-- anchor" for the Position that keeps a SHARED anchor point consistent
	-- works out to offsetting by (-7 + 14*anchorX) horizontally and
	-- (+4 + 14*anchorY) vertically -- which correctly collapses back to the
	-- original flat (-7, +4) for every AnchorPoint(0,0) panel (the common
	-- case) while also landing symmetrically for centered ones.
	local function addSoftShadow(panel, radius)
		local shadow = Instance.new("Frame")
		shadow.Name = "Shadow"
		shadow.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
		shadow.BackgroundTransparency = 0.55
		shadow.AnchorPoint = panel.AnchorPoint
		shadow.Size = UDim2.new(panel.Size.X.Scale, panel.Size.X.Offset + 14, panel.Size.Y.Scale, panel.Size.Y.Offset + 14)
		shadow.Position = UDim2.new(
			panel.Position.X.Scale,
			panel.Position.X.Offset - 7 + 14 * panel.AnchorPoint.X,
			panel.Position.Y.Scale,
			panel.Position.Y.Offset + 4 + 14 * panel.AnchorPoint.Y
		)
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

	-- POLISH: generic modal reveal -- `content` (typically a Frame anchored
	-- at its own center, e.g. AnchorPoint(0.5,0.5)) pops in from a slightly
	-- shrunk UIScale while `backdrop` fades from fully transparent to
	-- whatever transparency it was already sitting at (captured BEFORE this
	-- function forces it to 1, so callers never have to repeat their own
	-- backdrop dimming value -- pass opts.backdropTransparency to override
	-- it explicitly instead). Generalizes the reveal GameOver.lua built by
	-- hand for its own panel; new callers (ConfirmDialog, any future
	-- overlay) get the same "pop" for free instead of a hard instant cut.
	local function popIn(backdrop, content, opts)
		opts = opts or {}
		local duration = opts.duration or 0.22
		local targetTransparency = opts.backdropTransparency
		if targetTransparency == nil then
			targetTransparency = backdrop.BackgroundTransparency
		end

		local scale = content:FindFirstChildOfClass("UIScale")
		if not scale then
			scale = Instance.new("UIScale")
			scale.Parent = content
		end

		backdrop.Visible = true
		backdrop.BackgroundTransparency = 1
		scale.Scale = opts.fromScale or 0.85

		tweenTo(backdrop, { BackgroundTransparency = targetTransparency }, duration)
		tweenTo(scale, { Scale = 1 }, duration, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	end

	-- Reverses popIn: `content` shrinks slightly while `backdrop` fades back
	-- to fully transparent, and ONLY THEN (never on a hard cut) does
	-- backdrop.Visible get set false and onHidden (if given) fire -- lets a
	-- caller know it's safe to clear any per-show state once the dialog has
	-- actually finished disappearing, not the instant a button was clicked.
	local function popOut(backdrop, content, opts, onHidden)
		opts = opts or {}
		local duration = opts.duration or 0.15
		local scale = content:FindFirstChildOfClass("UIScale")
		if scale then
			tweenTo(scale, { Scale = opts.toScale or 0.9 }, duration, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		end
		local tween = tweenTo(backdrop, { BackgroundTransparency = 1 }, duration)
		tween.Completed:Connect(function(playbackState)
			if playbackState ~= Enum.PlaybackState.Completed then
				return -- interrupted by a newer tween (e.g. re-shown mid-fade-out) -- don't stomp it
			end
			backdrop.Visible = false
			if scale then
				scale.Scale = 1
			end
			if onHidden then
				onHidden()
			end
		end)
	end

	-- POLISH: generic overlap-safe "flash and settle" pulse for a Frame's
	-- BackgroundColor3 plus a small UIScale bump -- for any small,
	-- frequently-updated indicator that should visibly react to ITS OWN
	-- value changing while its rest color stays CONSTANT (e.g. Sidebar's
	-- Tips/Hands/Discards boxes, whose BackgroundColor3 is set once at
	-- creation and never touched anywhere else). Same shape as
	-- ScorePopup.lua's private pulsePatronSlot: a weak-keyed rest-color
	-- cache + an overlap-depth counter, so two pulses firing back-to-back
	-- on the same frame (two quick Tips changes) settle back to the right
	-- color instead of a naive read-current-color-as-rest approach
	-- converging on an already-flashed value (see pulsePatronSlot's own
	-- comment for the full failure mode this avoids).
	--
	-- IMPORTANT: do NOT use this on something whose BackgroundColor3 is
	-- itself meaningful state that changes over time (e.g. a Patron slot
	-- that flips between an "owned" color and an "empty" color) -- the
	-- settle step always reverts to whichever color was cached on this
	-- frame's FIRST-ever pulse, which would fight a caller that's also
	-- explicitly setting BackgroundColor3 every render. Use popScale
	-- (below) for that case instead -- a pure scale bump with no color
	-- opinion at all.
	local pulseRestColors = setmetatable({}, { __mode = "k" })
	local pulseDepths = setmetatable({}, { __mode = "k" })
	local function pulseFrame(frame, flashColor, opts)
		opts = opts or {}
		local bumpScale = opts.scale or 1.06
		local flashAmount = opts.flashAmount or 0.6
		local bumpDuration = opts.bumpDuration or 0.1
		local settleDelay = opts.settleDelay or 0.16
		local settleDuration = opts.settleDuration or 0.28

		local scale = frame:FindFirstChildOfClass("UIScale")
		if not scale then
			scale = Instance.new("UIScale")
			scale.Parent = frame
		end
		if not pulseRestColors[frame] then
			pulseRestColors[frame] = frame.BackgroundColor3
		end
		local restColor = pulseRestColors[frame]
		pulseDepths[frame] = (pulseDepths[frame] or 0) + 1

		tweenTo(scale, { Scale = bumpScale }, bumpDuration, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		tweenTo(frame, { BackgroundColor3 = restColor:Lerp(flashColor, flashAmount) }, bumpDuration)
		task.delay(settleDelay, function()
			pulseDepths[frame] = math.max(0, (pulseDepths[frame] or 1) - 1)
			if frame.Parent and pulseDepths[frame] == 0 then
				tweenTo(scale, { Scale = 1 }, settleDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
				tweenTo(frame, { BackgroundColor3 = restColor }, settleDuration)
			end
		end)
	end

	-- One-off scale "pop" -- bumps `instance`'s UIScale up then eases back
	-- to 1, with NO color change at all (see pulseFrame's warning above for
	-- why that matters). Fire-and-forget "something just appeared/changed
	-- here" cue for anything whose own color is independently managed by
	-- its caller every render -- e.g. Sidebar's Patron slots, which already
	-- flip BackgroundColor3 between an owned and an empty color elsewhere.
	local function popScale(instance, fromScale, duration)
		local scale = instance:FindFirstChildOfClass("UIScale")
		if not scale then
			scale = Instance.new("UIScale")
			scale.Parent = instance
		end
		scale.Scale = fromScale or 1.3
		tweenTo(scale, { Scale = 1 }, duration or 0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	end

	-- VISUAL LIFE PASS: a small "portrait" badge for a Patron/Recipe/
	-- Special -- an icon glyph with a soft colored glow behind it, a
	-- 2-stop gradient body instead of one flat fill color, and a thin
	-- colored ring, so an ability's TYPE reads at a glance from its color
	-- before you've even read the description -- a lightweight version of
	-- how a Balatro-style Joker's rarity border works. `accentColor` is a
	-- plain Color3; this function has no opinion on what a "category" is
	-- -- callers look that up (e.g. Patrons.CATEGORY_COLORS) and pass the
	-- resolved color in, so the same helper works for Recipes/Specials
	-- too, not just Patrons.
	--
	-- The halo is 2 oversized, mostly-transparent circles behind the
	-- badge, each less transparent than the last going inward -- fakes a
	-- soft radial glow (Roblox Frames can't render a real radial
	-- gradient), the same layered-circle technique the Journey map's
	-- lantern landmark glow already uses (see feature-expansion-plan.md).
	--
	-- `opts.x` is the badge's left edge in pixels within `parent` (default
	-- 8, matching every existing offer-row's icon position) -- kept as an
	-- offset rather than hardcoding this to always be flush-left so a
	-- badge can still be dropped into a differently-laid-out row later.
	local function makePortraitBadge(parent, icon, accentColor, opts)
		opts = opts or {}
		local size = opts.size or 46
		local x = opts.x or 8
		accentColor = accentColor or Color3.fromRGB(120, 100, 90)
		local centerX = x + size / 2

		local haloOuter = Instance.new("Frame")
		haloOuter.Name = "HaloOuter"
		haloOuter.Size = UDim2.new(0, size * 1.9, 0, size * 1.9)
		haloOuter.Position = UDim2.new(0, centerX, 0.5, 0)
		haloOuter.AnchorPoint = Vector2.new(0.5, 0.5)
		haloOuter.BackgroundColor3 = accentColor
		haloOuter.BackgroundTransparency = 0.88
		haloOuter.BorderSizePixel = 0
		haloOuter.ZIndex = parent.ZIndex
		haloOuter.Parent = parent
		roundCorner(haloOuter, size)

		local haloInner = Instance.new("Frame")
		haloInner.Name = "HaloInner"
		haloInner.Size = UDim2.new(0, size * 1.35, 0, size * 1.35)
		haloInner.Position = UDim2.new(0, centerX, 0.5, 0)
		haloInner.AnchorPoint = Vector2.new(0.5, 0.5)
		haloInner.BackgroundColor3 = accentColor
		haloInner.BackgroundTransparency = 0.72
		haloInner.BorderSizePixel = 0
		haloInner.ZIndex = parent.ZIndex
		haloInner.Parent = parent
		roundCorner(haloInner, size)

		local badge = Instance.new("TextLabel")
		badge.Name = "PortraitBadge"
		badge.Size = UDim2.new(0, size, 0, size)
		badge.Position = UDim2.new(0, centerX, 0.5, 0)
		badge.AnchorPoint = Vector2.new(0.5, 0.5)
		badge.BackgroundColor3 = Color3.fromRGB(45, 35, 25)
		badge.Font = Enum.Font.GothamBold
		badge.TextSize = math.floor(size * 0.48)
		badge.Text = icon or "🎴"
		badge.ZIndex = parent.ZIndex + 1
		badge.Parent = parent
		roundCorner(badge, math.floor(size / 4))

		-- Dark tavern-brown -> a tint of the category color, instead of one
		-- flat fill -- gives the badge some depth ("life") rather than
		-- reading as a single flat swatch.
		local gradient = Instance.new("UIGradient")
		gradient.Rotation = 55
		gradient.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(45, 35, 25)),
			ColorSequenceKeypoint.new(1, accentColor:Lerp(Color3.fromRGB(45, 35, 25), 0.3)),
		})
		gradient.Parent = badge

		local ring = Instance.new("UIStroke")
		ring.Color = accentColor
		ring.Thickness = 2
		ring.Transparency = 0.1
		ring.Parent = badge

		return badge
	end

	-- VISUAL LIFE PASS: tints a row/panel's flat BackgroundColor3 into a
	-- subtle 2-stop gradient toward `accentColor` -- kept deliberately
	-- gentle (a `strength` of 0.16 by default blends only that much of the
	-- accent in) so offer rows still read as "the same tavern brown,
	-- distinguished by a color note" rather than a stripe of solid color a
	-- Special-edition card should look far more dramatic than. Safe to
	-- call on anything with a BackgroundColor3 -- reads the frame's OWN
	-- current color as the gradient's base rather than assuming a fixed
	-- brown, so it still works on a row whose base color varies (e.g. a
	-- pack-reveal item toggling selected/unselected).
	local function tintBackground(frame, accentColor, strength)
		if not accentColor then
			return
		end
		strength = strength or 0.16
		local base = frame.BackgroundColor3
		local tinted = base:Lerp(accentColor, strength)
		local gradient = frame:FindFirstChildOfClass("UIGradient")
		if not gradient then
			gradient = Instance.new("UIGradient")
			gradient.Parent = frame
		end
		gradient.Rotation = 65
		gradient.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, base),
			ColorSequenceKeypoint.new(1, tinted),
		})
	end

	-- POLISH (Batch 2): generic hover + press feedback for a plain
	-- TextButton -- scales up slightly on mouse-over, dips down slightly
	-- on press, eases back on release/leave. A UIScale-based version of
	-- the same "hover lift" the hand-of-cards area in init.client.lua
	-- already does by hand for cards; this generalizes it for any button
	-- that just wants a little life without wiring its own MouseEnter/
	-- MouseLeave/MouseButton1Down/Up handlers every time (Menu.lua's 4
	-- buttons, first user of this).
	--
	-- KNOWN LIMIT: MouseEnter/MouseLeave don't fire for touch input, so on
	-- a touch device this button only ever shows the press dip, never the
	-- hover swell -- the same limitation the hand-card hover fan already
	-- has. Not a regression, just not solved here either.
	local function addButtonHoverScale(button, opts)
		opts = opts or {}
		local hoverScale = opts.hoverScale or 1.05
		local pressScale = opts.pressScale or 0.96
		local hoverDuration = opts.hoverDuration or 0.12
		local pressDuration = opts.pressDuration or 0.06

		local scale = button:FindFirstChildOfClass("UIScale")
		if not scale then
			scale = Instance.new("UIScale")
			scale.Parent = button
		end

		local hovering = false
		local pressed = false

		local function settle()
			local target = pressed and pressScale or (hovering and hoverScale or 1)
			tweenTo(scale, { Scale = target }, pressed and pressDuration or hoverDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		end

		button.MouseEnter:Connect(function()
			hovering = true
			settle()
		end)
		button.MouseLeave:Connect(function()
			hovering = false
			pressed = false
			settle()
		end)
		button.MouseButton1Down:Connect(function()
			pressed = true
			settle()
		end)
		button.MouseButton1Up:Connect(function()
			pressed = false
			settle()
		end)
	end

	-- POLISH (Batch 2): a one-time staggered reveal for a LIST of
	-- instances (e.g. a menu's title/subtitle/buttons, a row of freshly
	-- rebuilt Shop offer cards) -- each one starts transparent and
	-- slightly shrunk (UIScale), then scales/fades up into place,
	-- staggered `opts.stagger` seconds apart so they cascade in rather
	-- than all popping at once.
	--
	-- DELIBERATELY scale-based, not Position-based: several real callers
	-- (Menu.lua's button row, Shop.lua's offer rows) are children of a
	-- UIListLayout, which recomputes and overrides a child's Position
	-- every layout pass -- an offset-then-tween-back-to-rest approach on
	-- Position would just get silently fought/overridden by the layout
	-- engine (same class of bug this project already chased once with
	-- the Journey map's path line, see feature-expansion-plan.md's Phase
	-- 7 notes). UIScale has no such conflict -- it's exactly the pattern
	-- Sidebar's own UIListLayout-managed Patron slots already use safely
	-- (ScorePopup.lua's pulsePatronSlot / this file's popScale).
	--
	-- Only touches TextTransparency/BackgroundTransparency/UIScale -- it
	-- does NOT assume a Frame's resting BackgroundTransparency is 0 (a
	-- label-only Frame that's meant to stay fully see-through keeps its
	-- own resting transparency, read fresh from the instance before this
	-- runs, never hardcoded).
	--
	-- Fire-and-forget one-shot -- unlike popIn/popOut, there's no
	-- "reverse" call, since callers so far (Menu.lua's load-in, a Shop
	-- offer row rebuilding) never need to un-reveal the same instances.
	local function revealStagger(instances, opts)
		opts = opts or {}
		local stagger = opts.stagger or 0.08
		local duration = opts.duration or 0.3
		local fromScale = opts.fromScale or 0.75
		for i, instance in ipairs(instances) do
			local restBackgroundTransparency = instance.BackgroundTransparency
			local isLabel = instance:IsA("TextLabel") or instance:IsA("TextButton")

			local scale = instance:FindFirstChildOfClass("UIScale")
			if not scale then
				scale = Instance.new("UIScale")
				scale.Parent = instance
			end
			scale.Scale = fromScale

			if isLabel then
				instance.TextTransparency = 1
			end
			if restBackgroundTransparency < 1 then
				instance.BackgroundTransparency = 1
			end

			task.delay((i - 1) * stagger, function()
				if not instance.Parent then
					return
				end
				tweenTo(scale, { Scale = 1 }, duration, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
				local fadeProps = {}
				if isLabel then
					fadeProps.TextTransparency = 0
				end
				if restBackgroundTransparency < 1 then
					fadeProps.BackgroundTransparency = restBackgroundTransparency
				end
				if next(fadeProps) then
					tweenTo(instance, fadeProps, duration)
				end
			end)
		end
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
		popIn = popIn,
		popOut = popOut,
		pulseFrame = pulseFrame,
		popScale = popScale,
		addButtonHoverScale = addButtonHoverScale,
		revealStagger = revealStagger,
		makePortraitBadge = makePortraitBadge,
		tintBackground = tintBackground,
	}
end
