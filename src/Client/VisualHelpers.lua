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
			polishPanel = function(instance, radius?, variant?),
			              -- variant: "wood" (menus) | "parchment" (reading screens)
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

	local function addGoldChrome(instance, thickness)
		if instance:FindFirstChildOfClass("UIStroke") then
			return
		end
		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.fromRGB(200, 165, 90)
		stroke.Thickness = thickness or 1.5
		stroke.Transparency = 0.15
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Parent = instance
	end

	-- ===== Shared carved-wood skin =====
	-- Every polishPanel/polishButton caller gets the gameplay sidebar's
	-- look from here: a gold ring, a thin gold inner rim, and (on panels
	-- big enough for them) gold L-shaped corner brackets with a stud at
	-- each tip. Same colors and piece names as Sidebar.lua's ornamentBox,
	-- so SkinArt.hideCodeChrome hides these too when real art loads.
	--
	-- Corner radius is standardized: callers' small radii (4-18) all become
	-- PANEL_RADIUS/BUTTON_RADIUS. A radius of ROUND_RADIUS_MIN or more is
	-- kept as-is -- that's a deliberate circle (the corner medallions).
	local GOLD = Color3.fromRGB(222, 182, 104)
	local PANEL_RADIUS = 6
	local BUTTON_RADIUS = 6
	local ROUND_RADIUS_MIN = 20
	local BRACKET_MIN_SIZE = 56 -- px; below this the corner brackets crowd the content
	local RIM_MIN_SIZE = 24

	-- Color-only shading (never UIGradient.Transparency -- see this file's
	-- header). It multiplies whatever fill the panel has, so Themes that
	-- recolor a panel (Shop, Game Over) still tint it as before. A variant
	-- only replaces the fill while it's still the default flat panel brown;
	-- a deliberately colored panel (the green round reward popup) keeps
	-- its color and just gets the shading and frame.
	local FLAT_PANEL_BROWN = Color3.fromRGB(40, 30, 22)
	local VARIANTS = {
		-- Dark carved wood for menus and dialogs: the standard panel brown,
		-- top-lit like the sidebar plaques.
		wood = {
			fill = Color3.fromRGB(40, 30, 22),
			shade = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(165, 160, 155)),
		},
		-- A lighter, softer-shaded tone for reading screens. Still dark
		-- enough for the cream text every screen already uses.
		parchment = {
			fill = Color3.fromRGB(70, 55, 40),
			shade = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(210, 195, 175)),
		},
	}

	local function styleRadius(radius, default)
		if radius and radius >= ROUND_RADIUS_MIN then
			return radius
		end
		return default
	end

	local function hasLayout(instance)
		return instance:FindFirstChildWhichIsA("UIGridStyleLayout") ~= nil
	end

	-- Builds the rim/brackets one frame later (task.defer), once the caller
	-- has finished setting ZIndex, visibility and children. Skipped when:
	--   - the element already has them (Sidebar's own ornamentBox, or a
	--     Clone() of an element that already had them),
	--   - it's a ScrollingFrame (they'd scroll with the content),
	--   - it's see-through (nothing to frame),
	--   - its code chrome was already hidden for real art (SkinArt),
	--   - it holds a UIListLayout/UIGridLayout -- the layout would treat
	--     every decorative frame as an item and shove the content around.
	--     If a layout is added later, the pieces are removed again.
	local function addOrnateFrame(instance, withBrackets)
		if instance:IsA("ScrollingFrame") then
			return
		end
		task.defer(function()
			if instance:FindFirstChild("InnerRim") or hasLayout(instance) then
				return
			end
			if instance.BackgroundTransparency >= 1 then
				return
			end
			local ring = instance:FindFirstChildOfClass("UIStroke")
			if ring and not ring.Enabled then
				return
			end

			local inset = withBrackets and 4 or 3
			local pieces, brackets = {}, {}

			local inner = Instance.new("Frame")
			inner.Name = "InnerRim"
			inner.Position = UDim2.fromOffset(inset, inset)
			inner.Size = UDim2.new(1, -inset * 2, 1, -inset * 2)
			inner.BackgroundTransparency = 1
			inner.Active = false
			local innerCorner = Instance.new("UICorner")
			-- Follow the host's corner so a round medallion gets a round
			-- inner rim. A fixed 3px radius left square corners poking out
			-- past the circular ring (the "square behind the icon" bug).
			local hostCorner = instance:FindFirstChildOfClass("UICorner")
			if hostCorner and hostCorner.CornerRadius.Scale > 0 then
				innerCorner.CornerRadius = hostCorner.CornerRadius
			else
				local hostOffset = hostCorner and hostCorner.CornerRadius.Offset or 0
				innerCorner.CornerRadius = UDim.new(0, math.max(3, hostOffset - inset))
			end
			innerCorner.Parent = inner
			local innerStroke = Instance.new("UIStroke")
			innerStroke.Color = GOLD
			innerStroke.Thickness = 1
			innerStroke.Transparency = 0.35
			innerStroke.Parent = inner
			inner.Parent = instance
			table.insert(pieces, inner)

			if withBrackets then
				local ARM, THICK = 12, 3
				-- Sit just over the ring like the sidebar's, unless the
				-- element clips its children -- then tuck them inside.
				local out = instance.ClipsDescendants and 0 or 2
				for _, c in ipairs({ { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 } }) do
					local ax, ay = c[1], c[2]
					local xOff = ax == 0 and -out or out
					local yOff = ay == 0 and -out or out
					for _, spec in ipairs({ { "BracketH", ARM, THICK }, { "BracketV", THICK, ARM } }) do
						local arm = Instance.new("Frame")
						arm.Name = spec[1]
						arm.AnchorPoint = Vector2.new(ax, ay)
						arm.Position = UDim2.new(ax, xOff, ay, yOff)
						arm.Size = UDim2.fromOffset(spec[2], spec[3])
						arm.BackgroundColor3 = GOLD
						arm.BorderSizePixel = 0
						arm.Active = false
						arm.Parent = instance
						table.insert(brackets, arm)
					end
					local stud = Instance.new("Frame")
					stud.Name = "CornerStud"
					stud.AnchorPoint = Vector2.new(0.5, 0.5)
					stud.Position = UDim2.new(ax, ax == 0 and 5 or -5, ay, ay == 0 and 5 or -5)
					stud.Size = UDim2.fromOffset(4, 4)
					stud.Rotation = 45
					stud.BackgroundColor3 = GOLD
					stud.BorderSizePixel = 0
					stud.Active = false
					stud.Parent = instance
					table.insert(brackets, stud)
				end
			end
			for _, piece in ipairs(brackets) do
				table.insert(pieces, piece)
			end

			-- This ScreenGui uses Global ZIndex, so the pieces must follow
			-- the element's own ZIndex or they'd draw under its fill.
			local function syncZ()
				inner.ZIndex = instance.ZIndex
				for _, piece in ipairs(brackets) do
					piece.ZIndex = instance.ZIndex + 1
				end
			end
			local function syncSize()
				local size = instance.AbsoluteSize
				local smallest = math.min(size.X, size.Y)
				-- 0 means not laid out yet; show everything until it is.
				local measured = smallest > 0
				-- a host that wears painted art (the Run Over scroll) sets OrnateOff: the rim and brackets stay hidden
				local off = instance:GetAttribute("OrnateOff") == true
				inner.Visible = not off and (not measured or smallest >= RIM_MIN_SIZE)
				for _, piece in ipairs(brackets) do
					piece.Visible = not off and (not measured or smallest >= BRACKET_MIN_SIZE)
				end
			end
			syncZ()
			syncSize()
			local connections = {
				instance:GetPropertyChangedSignal("ZIndex"):Connect(syncZ),
				instance:GetPropertyChangedSignal("AbsoluteSize"):Connect(syncSize),
			}
			table.insert(connections, instance.ChildAdded:Connect(function(child)
				if child:IsA("UIGridStyleLayout") then
					for _, connection in ipairs(connections) do
						connection:Disconnect()
					end
					for _, piece in ipairs(pieces) do
						piece:Destroy()
					end
				end
			end))
		end)
	end

	local function polishButton(instance, radius)
		roundCorner(instance, styleRadius(radius, BUTTON_RADIUS))
		addGoldChrome(instance, 1.5)
		-- Buttons get the rim only -- corner brackets on every button would
		-- crowd button rows.
		addOrnateFrame(instance, false)
		require(script.Parent.SetSkin).register(instance, "button")
	end

	local function polishPanel(instance, radius, variant)
		roundCorner(instance, styleRadius(radius, PANEL_RADIUS))
		addGoldChrome(instance, 2)
		local style = variant and VARIANTS[variant]
		if style then
			if instance.BackgroundColor3 == FLAT_PANEL_BROWN then
				instance.BackgroundColor3 = style.fill
			end
			if not instance:FindFirstChildOfClass("UIGradient") then
				local shade = Instance.new("UIGradient")
				shade.Name = "PanelShade"
				shade.Rotation = 90
				shade.Color = style.shade
				shade.Parent = instance
			end
		end
		addOrnateFrame(instance, true)
		require(script.Parent.SetSkin).register(instance, "panel")
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
		roundCorner(shadow, styleRadius(radius, PANEL_RADIUS + 2))
		-- A clamped panel (UISizeConstraint) needs the same clamp grown by the shadow padding, or the shadow overshoots it.
		local function syncLimit()
			local src = panel:FindFirstChildOfClass("UISizeConstraint")
			local dst = shadow:FindFirstChildOfClass("UISizeConstraint")
			if not src then
				if dst then dst:Destroy() end
				return
			end
			if not dst then
				dst = Instance.new("UISizeConstraint")
				dst.Parent = shadow
			end
			local ShadowFit = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("ShadowFit"))
			local a, b, c, d = ShadowFit.limits(src.MinSize.X, src.MinSize.Y, src.MaxSize.X, src.MaxSize.Y)
			dst.MinSize = Vector2.new(a, b)
			dst.MaxSize = Vector2.new(c, d)
		end
		syncLimit()
		panel.ChildAdded:Connect(function(child)
			if child:IsA("UISizeConstraint") then syncLimit() end
		end)
		-- BUGFIX (reference-match pass): the shadow is a SIBLING of the
		-- panel, so hiding the panel never hid it. GameOver's panel sits
		-- straight on the game screen (no backdrop to hide it), so its
		-- shadow was always there -- invisible only because the screen's
		-- opaque fill used to paint over it. Now it follows the panel.
		shadow.Visible = panel.Visible
		panel:GetPropertyChangedSignal("Visible"):Connect(function()
			shadow.Visible = panel.Visible
		end)
		return shadow
	end

	-- SCORING JUICE: whole-screen shake. Jitters `target`'s Position by small
	-- random pixel offsets a few times, easing back to rest. Shakes the UI
	-- itself rather than the camera -- the game is pure 2D UI and never
	-- touches the camera/character, and a
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
		-- Settings > Display > Reduce Screen Shake turns every shake off.
		if require(script.Parent.ClientSettings).get("reduceShake") then
			return
		end
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
		controlLayout.SortOrder = Enum.SortOrder.LayoutOrder
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
	-- layoutOrder (optional, SFX VOLUME SLIDERS addition): lets a caller
	-- stack several rows inside a parent that has its own UIListLayout
	-- (e.g. Settings.lua's scrollable audio section, one row per sound
	-- effect) with a deterministic, caller-chosen order -- a plain
	-- Instance.new("Frame") row with no explicit Name would otherwise tie
	-- with every other row at the layout's default LayoutOrder (0),
	-- leaving their relative order unspecified. Every existing single-row
	-- caller (just Master Volume, before this) is unaffected -- omitting
	-- it leaves LayoutOrder at Roblox's own default (0), same as before
	-- this parameter existed.
	local function makeSliderRow(parent, labelText, min, max, getValue, setValue, formatValue, layoutOrder)
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, 0, 0, 46)
		row.BackgroundTransparency = 1
		if layoutOrder then
			row.LayoutOrder = layoutOrder
		end
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
		do -- a 44 px touch target around the small knob (invisible, rides the knob)
			local hit = Instance.new("Frame")
			hit.Name = "KnobHit"
			hit.AnchorPoint = Vector2.new(0.5, 0.5)
			hit.Position = UDim2.fromScale(0.5, 0.5)
			hit.Size = UDim2.fromOffset(44, 44)
			hit.BackgroundTransparency = 1
			hit.ZIndex = 24
			hit.Parent = knob
			hit.InputBegan:Connect(beginDrag)
		end

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

		-- hide bookkeeping: a later popOut's safety timer must not hide a backdrop that was shown again, and Active comes back with it
		backdrop:SetAttribute("PopSeq", (backdrop:GetAttribute("PopSeq") or 0) + 1)
		backdrop:SetAttribute("PopState", "in")
		if backdrop:GetAttribute("PopActive") == nil then backdrop:SetAttribute("PopActive", backdrop.Active) end
		backdrop.Active = backdrop:GetAttribute("PopActive") == true
		backdrop.Visible = true
		backdrop.BackgroundTransparency = 1
		-- a full screen page (PanelFullScreen) never scales: its layout and the painted scene measure the panel's AbsoluteSize,
		-- and an 85 percent pop left them laid out at the transient size (a dark band at the bottom)
		local fullScreen = content:GetAttribute("FullScreenPanel") == true
		scale.Scale = fullScreen and 1 or (opts.fromScale or 0.85)

		tweenTo(backdrop, { BackgroundTransparency = targetTransparency }, duration)
		if not fullScreen then
			tweenTo(scale, { Scale = 1 }, duration, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		end
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
		if scale and content:GetAttribute("FullScreenPanel") ~= true then
			tweenTo(scale, { Scale = opts.toScale or 0.9 }, duration, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		end
		local seq = (backdrop:GetAttribute("PopSeq") or 0) + 1
		backdrop:SetAttribute("PopSeq", seq)
		backdrop:SetAttribute("PopState", "out") -- Client/InputGuard.watchStuck hides a backdrop that is still up a second after this
		backdrop:SetAttribute("PopOutAt", os.clock())
		if backdrop:GetAttribute("PopActive") == nil then backdrop:SetAttribute("PopActive", backdrop.Active) end
		local hidden = false
		local function hide()
			if hidden then return end
			hidden = true
			backdrop.Visible = false
			backdrop.Active = false -- a hidden backdrop never keeps swallowing clicks (popIn gives Active back)
			if scale then
				scale.Scale = 1
			end
			if onHidden then
				onHidden()
			end
		end
		local tween = tweenTo(backdrop, { BackgroundTransparency = 1 }, duration)
		tween.Completed:Connect(function(playbackState)
			if playbackState ~= Enum.PlaybackState.Completed then
				return -- interrupted by a newer tween (e.g. re-shown mid-fade-out) -- don't stomp it
			end
			if backdrop:GetAttribute("PopSeq") ~= seq then return end
			hide()
		end)
		-- safety net: if the tween never completes (it was cancelled or replaced), the backdrop still goes away, unless it was shown again
		task.delay(duration + 0.45, function()
			if backdrop:GetAttribute("PopSeq") == seq then hide() end
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
			if require(script.Parent.ModalStage).blocks(button) then return end -- a modal is open: nothing behind it reacts
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
	}
end
