--[[
	Client/ScorePopup.lua
	Balatro's signature scoring sequence -- Play Hand triggers a step-by-step
	choreography: the played cards lift into a row, each scoring card (left
	to right) pops/highlights while its own chip/mult number flies up into
	the HUD, held cards get a brief in-place nudge for Iron Garnish, owned
	Patrons pulse in the sidebar when their bonus fires, then a finale slams
	the real total home and the played cards drop away.

	FULL CHOREOGRAPHY PASS (this rewrite): Ahmed pasted a very detailed
	field-by-field breakdown of that sequence and asked for the full thing,
	after being warned it's a real architecture change (a genuine
	played-card row that survives the server round-trip) rather than a
	quick tweak to the existing HUD-only popup. Kept from the prior pass,
	unchanged in spirit: color-coded elastic numbers (blue Chips / red Mult
	/ purple XMult), an escalating-pitch tick sound per entry, screen shake
	+ particle bursts scaled to payout size, an anticipation pause before a
	big XMult, and a pitched-down "thud" finale.

	NEW this pass, tracing each breakdown entry back to what caused it (see
	Scoring.lua's `breakdown[i].source` -- the whole reason that field
	exists is to make this file possible without any id-plumbing):
	  - Played cards are cloned into screen-space "ghost" Instances (see
	    init.client.lua's buildScoreSourceInfo) that lift into a centered
	    row above the hand the instant Play Hand is clicked -- immune to
	    rebuildHand() destroying the real hand out from under the
	    animation the moment the server responds.
	  - The active scoring card's ghost pops/scales/flashes while its
	    number visibly flies from the card to the matching Chips/Mult box
	    (split out of the old single "chips x mult" label into two boxes
	    specifically so there's a real blue box and a real red box to fly
	    into, matching the spec).
	  - The OTHER played cards dim slightly while one is active -- a
	    "focus" cue standing in for the spec's camera micro-zoom. This is
	    a deliberate substitute, not a shortcut: TavernScene.server.lua
	    has an explicit standing rule to never touch the real 3D
	    Camera/character, so "focus" here is a UI-only dim/highlight
	    trick, same philosophy as screenShake jittering the UI root
	    instead of the camera.
	  - Held cards get a smaller in-place highlight for Iron Garnish
	    (no row, they never left the hand).
	  - Owned Patrons pulse their actual Sidebar seat (scale + color
	    flash) when their bonus/Special fires, with their own number
	    flying from the seat to the HUD.
	  - `kind = "tips"` entries (new in Scoring.lua this pass -- Gold
	    Stamp / Lucky Garnish procs / a Patron's flat tips bonus) get a
	    small floating "+N Tips" flash instead of flying into a box (there
	    isn't a dedicated Tips box in this popup).
	  - Brittle Garnish cards that broke this hand (preview.brokenCards)
	    get a shatter effect and are destroyed early instead of joining
	    the calmer end-of-sequence drop-off.
	  - At the very end, played-card ghosts drop off toward the deck
	    widget (bottom-right -- the same landmark new cards deal IN from),
	    mirroring "played cards drop into the discard pile."

	Every one of the above degrades gracefully to the OLD center-HUD-only
	behavior if a ghost/slot can't be found (e.g. sourceInfo wasn't passed,
	or a card reference doesn't match anything) -- see findGhostForCard/
	patronSlotFrames lookups below returning nil. Nothing here can hard
	fail just because the choreography's optional pieces didn't resolve.

	The running chips/mult totals shown DURING the sequence are computed by
	replaying the same breakdown the engine returned (summing every
	"chips" entry and multiplying every "xmult" entry into "mult" gives
	back EXACTLY preview.chips/preview.mult -- see Scoring.calculate's own
	comment on why breakdown is purely additive data), so there's no way
	for the animation to end on a different number than what you actually
	get paid. The finale re-sets the boxes to preview.chips/preview.mult
	directly anyway, as a belt-and-suspenders guard against float drift.

	A hand with lots of Patrons/Garnishes can generate a LOT of breakdown
	entries (worst case: 5 cards x up to ~3 triggers each, plus 5 Patrons x
	up to ~3 bonuses each plus a Special = 50+). MAX_ANIMATED_ENTRIES caps
	how many get their own animated beat so one huge hand can't turn into
	a multi-second slog -- everything past the cap still counts toward the
	running/final totals, it just doesn't get its own pop/tick/shake/fly.

	Extracted out of init.client.lua as part of splitting the client script
	into smaller, per-feature files. showScorePopup is called from
	playButton's click handler elsewhere in init.client.lua, so it comes
	back out of the require() call.

	deps fields:
		root           -- Frame, the popup's parent AND the screen-shake target
		tweenTo        -- function(instance, props, duration, easingStyle?, easingDirection?)
		screenShake    -- function(target, intensity, duration?) -- see VisualHelpers.lua
		particleBurst  -- function(screenPosition, color, count, options?) -- see ParticleBurst.lua
		playPitched    -- function(sound, pitch?, volume?) -- see Sound.lua
		chipTickSound, multTickSound, xmultTickSound, payoutThudSound -- Sound instances, see Sound.lua
		deckWidgetButton -- optional GuiObject, drop-off target for played ghosts (bottom-right deck widget)

	Returns:
		{
			showScorePopup = function(preview, sourceInfo),
			-- preview: { name, chips, mult, score, breakdown, brokenCards }
			--   from computeHandPreview(). breakdown/brokenCards may be nil
			--   (e.g. if the preview computation failed) -- the popup
			--   still shows correctly, it just skips straight to the finale.
			-- sourceInfo: { cardGhosts, patronSlotFrames } from
			--   init.client.lua's buildScoreSourceInfo(indices), called
			--   right before this. May be omitted/nil -- everything below
			--   just falls back to the old center-HUD-only behavior.
		}
]]

return function(deps)
	local root = deps.root
	local tweenTo = deps.tweenTo
	local screenShake = deps.screenShake
	local particleBurst = deps.particleBurst
	local playPitched = deps.playPitched
	local chipTickSound = deps.chipTickSound
	local multTickSound = deps.multTickSound
	local xmultTickSound = deps.xmultTickSound
	local payoutThudSound = deps.payoutThudSound
	local deckWidgetButton = deps.deckWidgetButton

	-- Blue = Chips, Red = Mult, Purple = XMult, Green = Tips -- Blue/Red/
	-- Purple straight from Ahmed's original juice spec; Tips added this
	-- pass (green is the standard "money" association, and it's clearly
	-- distinct from the other three so it never reads as a chips/mult
	-- entry by mistake).
	local KIND_COLORS = {
		chips = Color3.fromRGB(110, 180, 255),
		mult = Color3.fromRGB(255, 110, 110),
		xmult = Color3.fromRGB(200, 130, 255),
		tips = Color3.fromRGB(130, 230, 150),
	}
	local FINALE_COLOR = Color3.fromRGB(255, 214, 130)
	local SHATTER_COLOR = Color3.fromRGB(210, 230, 255)

	-- PACING: Ahmed's first playtest of the old HUD-only popup couldn't
	-- read the per-entry text before it was replaced by the next one, and
	-- a later full-sequence playtest still felt too fast across the board
	-- (not just the finale) -- these knobs slow the WHOLE choreography
	-- down, not just any one piece of it. ENTRY_STAGGER is the main knob
	-- if it ever needs adjusting again; MAX_ANIMATED_ENTRIES is kept low
	-- to match, so a big hand's worst-case total duration doesn't balloon
	-- just because each individual beat got slower.
	local MAX_ANIMATED_ENTRIES = 8 -- see file header -- caps worst-case sequence length
	local BASE_PITCH = 1.0
	local PITCH_STEP = 0.045 -- per-entry pitch increment -- "increment sequentially along a musical scale"
	local MAX_PITCH = 1.7
	local HIGH_TIER_XMULT = 2 -- xmult entries at/above this get an anticipation pause before they land
	local ENTRY_STAGGER = 0.75 -- seconds between entries -- long enough to actually read each line
	local ANTICIPATION_PAUSE = 0.5
	local FLY_DURATION = 0.4 -- < ENTRY_STAGGER, so a flying number always lands before the next entry starts
	local GHOST_LIFT_DURATION = 0.35 -- played row "lift out of hand" tween
	local DROPOFF_DURATION = 0.7 -- played row "drop into discard" tween at the end
	local GHOST_HARD_TIMEOUT = 12 -- last-resort backstop, see showScorePopup's per-ghost task.delay
	-- PACING: how long the finale's final "Chips x Mult" stays on screen
	-- before the popup hides. Was 1.1s originally, 1.6s, then 2.6s in
	-- earlier pacing passes. Trimmed back down to 1.8s here -- Ahmed's
	-- report was that once the played cards drop off toward the deck, the
	-- lingering "Chips x Mult" readout with nothing else happening felt
	-- unnecessary. Now that dropOffPlayedGhosts actually cleans its ghosts
	-- up as soon as they land (see that function's BUGFIX comment) instead
	-- of leaving them frozen at the deck for the rest of this linger, the
	-- dead-air problem is smaller, but the linger itself still doesn't need
	-- to run the full 2.6s to be readable.
	local FINALE_LINGER = 1.8

	local scorePopup = Instance.new("Frame")
	scorePopup.Name = "ScorePopup"
	scorePopup.Size = UDim2.new(0, 260, 0, 116)
	scorePopup.AnchorPoint = Vector2.new(0.5, 1)
	scorePopup.Position = UDim2.new(0.5, 0, 1, -240)
	scorePopup.BackgroundTransparency = 1
	scorePopup.Visible = false
	scorePopup.ZIndex = 25
	scorePopup.Parent = root

	local scorePopupHandName = Instance.new("TextLabel")
	scorePopupHandName.Size = UDim2.new(1, 0, 0, 24)
	scorePopupHandName.BackgroundTransparency = 1
	scorePopupHandName.Font = Enum.Font.GothamBold
	scorePopupHandName.TextSize = 18
	scorePopupHandName.TextColor3 = Color3.fromRGB(255, 230, 180)
	scorePopupHandName.TextStrokeTransparency = 0.5
	scorePopupHandName.Text = ""
	scorePopupHandName.ZIndex = 25
	scorePopupHandName.Parent = scorePopup

	-- SCORING JUICE, full choreography pass: split out of the old single
	-- "chips x mult" label into a real blue Chips box / red Mult box, so
	-- flying numbers have an actual matching box to merge into (Ahmed's
	-- spec: "the blue Chips box and red Mult box pop directly into the
	-- HUD" / "slam together... as the math completes").
	local chipsLabel = Instance.new("TextLabel")
	chipsLabel.Size = UDim2.new(0, 115, 0, 50)
	chipsLabel.Position = UDim2.new(0, 0, 0, 26)
	chipsLabel.BackgroundTransparency = 1
	chipsLabel.Font = Enum.Font.GothamBold
	chipsLabel.TextSize = 30
	chipsLabel.TextColor3 = KIND_COLORS.chips
	chipsLabel.TextStrokeTransparency = 0.35
	chipsLabel.TextXAlignment = Enum.TextXAlignment.Right
	chipsLabel.Text = "0"
	chipsLabel.ZIndex = 25
	chipsLabel.Parent = scorePopup

	local xLabel = Instance.new("TextLabel")
	xLabel.Size = UDim2.new(0, 30, 0, 50)
	xLabel.Position = UDim2.new(0, 115, 0, 26)
	xLabel.BackgroundTransparency = 1
	xLabel.Font = Enum.Font.GothamBold
	xLabel.TextSize = 26
	xLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	xLabel.TextStrokeTransparency = 0.4
	xLabel.TextXAlignment = Enum.TextXAlignment.Center
	xLabel.Text = "x"
	xLabel.ZIndex = 25
	xLabel.Parent = scorePopup

	local multLabel = Instance.new("TextLabel")
	multLabel.Size = UDim2.new(0, 115, 0, 50)
	multLabel.Position = UDim2.new(0, 145, 0, 26)
	multLabel.BackgroundTransparency = 1
	multLabel.Font = Enum.Font.GothamBold
	multLabel.TextSize = 30
	multLabel.TextColor3 = KIND_COLORS.mult
	multLabel.TextStrokeTransparency = 0.35
	multLabel.TextXAlignment = Enum.TextXAlignment.Left
	multLabel.Text = "0"
	multLabel.ZIndex = 25
	multLabel.Parent = scorePopup

	-- Bump targets for flyNumberToBox's "merge into the box" impact -- see
	-- there. Kept on the boxes themselves (not the whole popup) so a
	-- flying chips number bumps ONLY the blue box, not the red one too.
	local chipsScale = Instance.new("UIScale")
	chipsScale.Parent = chipsLabel
	local multScale = Instance.new("UIScale")
	multScale.Parent = multLabel

	-- SCORING JUICE: the per-entry "what just triggered" line -- e.g.
	-- "King of Hearts  +9 Chips" -- color-coded and separately elastic-
	-- popped from the boxes above it. Kept from the prior pass: even with
	-- per-card ghosts now doing most of the visual work, this line is
	-- still the one place the exact text is always guaranteed readable
	-- regardless of whether a ghost/slot happened to be found.
	local scorePopupEventLabel = Instance.new("TextLabel")
	scorePopupEventLabel.Size = UDim2.new(1, 0, 0, 22)
	scorePopupEventLabel.Position = UDim2.new(0, 0, 0, 80)
	scorePopupEventLabel.BackgroundTransparency = 1
	scorePopupEventLabel.Font = Enum.Font.GothamBold
	scorePopupEventLabel.TextSize = 15
	scorePopupEventLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	scorePopupEventLabel.TextStrokeTransparency = 0.6
	scorePopupEventLabel.Text = ""
	scorePopupEventLabel.ZIndex = 25
	scorePopupEventLabel.Parent = scorePopup

	local scorePopupScale = Instance.new("UIScale")
	scorePopupScale.Scale = 1
	scorePopupScale.Parent = scorePopup

	local scorePopupEventScale = Instance.new("UIScale")
	scorePopupEventScale.Scale = 1
	scorePopupEventScale.Parent = scorePopupEventLabel

	local scorePopupToken = 0

	-- Ghosts (and their FocusDim overlays) currently "owned" by whichever
	-- sequence is in flight. Always cleared at the START of a new
	-- showScorePopup call (defensive -- a previous sequence that got
	-- interrupted, e.g. the player rushed straight into another hand,
	-- may have left its ghosts behind) so ghosts can never pile up run
	-- over run.
	local liveGhosts = {}

	local function destroyGhosts(ghosts)
		for _, entry in ipairs(ghosts) do
			if entry.ghost and entry.ghost.Parent then
				entry.ghost:Destroy()
			end
		end
	end

	local function tickSoundFor(kind)
		if kind == "chips" or kind == "tips" then
			return chipTickSound
		elseif kind == "mult" then
			return multTickSound
		end
		return xmultTickSound
	end

	local function formatEntryText(entry)
		if entry.kind == "xmult" then
			return string.format("%s  x%g XMult", entry.label, entry.amount)
		elseif entry.kind == "tips" then
			local sign = entry.amount >= 0 and "+" or ""
			return string.format("%s  %s%d Tips", entry.label, sign, math.floor(entry.amount + 0.5))
		end
		local verb = entry.kind == "chips" and "Chips" or "Mult"
		local sign = entry.amount >= 0 and "+" or ""
		-- Every current Chips/Mult source in the engine happens to be a
		-- whole number, but nothing guarantees that stays true forever --
		-- floor before %d so a future fractional flat-mult source (a
		-- Garnish/Patron/Special) can't hard-error Lua 5.3's %d mid-reveal.
		return string.format("%s  %s%d %s", entry.label, sign, math.floor(entry.amount + 0.5), verb)
	end

	-- Rough "how big a deal is this" score, used to scale shake/particle
	-- intensity -- an xmult entry counts for a lot more than a flat chips/
	-- mult bump of the same raw number, matching how much more a
	-- multiplier actually swings the final score.
	local function entryMagnitude(entry)
		if entry.kind == "xmult" then
			return (entry.amount - 1) * 6
		elseif entry.kind == "tips" then
			return math.min(4, math.abs(entry.amount) / 3)
		end
		return math.min(6, math.abs(entry.amount) / 4)
	end

	-- Generic "center point, as a UDim2 offset" helper -- used for particle
	-- burst origins, flying-number start/end points, and label positions
	-- alike, for any GuiObject (the popup itself, a card ghost, a Patron
	-- slot Frame, a HUD box).
	local function centerOf(instance)
		return UDim2.fromOffset(
			instance.AbsolutePosition.X + instance.AbsoluteSize.X / 2,
			instance.AbsolutePosition.Y + instance.AbsoluteSize.Y / 2
		)
	end

	local function findGhostForCard(cardGhosts, card)
		if not cardGhosts or not card then
			return nil
		end
		for _, entry in ipairs(cardGhosts) do
			if entry.card == card then
				return entry
			end
		end
		return nil
	end

	-- ===== Played-card row layout =====

	-- Lifts every PLAYED ghost (already left-to-right sorted, see
	-- init.client.lua's buildScoreSourceInfo) into a centered row well
	-- above the hand/HUD, the instant Play Hand is clicked -- Ahmed's
	-- spec's "the active card nudges upward out of the played row", made
	-- literal instead of the old HUD-only popup's implicit version of it.
	--
	-- BUGFIX (Ahmed's Studio screenshot): this used to place the row at a
	-- fixed FRACTION of root.AbsoluteSize.Y (0.3), independent of where
	-- `scorePopup` itself actually sits (which is positioned with a fixed
	-- PIXEL offset from the bottom, not a fraction). On a shorter/embedded
	-- Studio viewport those two independent guesses collided -- the row
	-- rendered low enough to sit ON TOP of the hand-name/Chips-Mult boxes,
	-- hiding them behind the played cards. Anchoring the row's bottom
	-- edge to `scorePopup`'s OWN measured top edge (not a guess) makes
	-- them mutually exclusive by construction, at any screen size.
	local ROW_CARD_HEIGHT = 100 -- matches rebuildHand's card slot height
	local ROW_MARGIN_ABOVE_POPUP = 24
	local function layoutPlayedRow(playedGhosts)
		if #playedGhosts == 0 then
			return
		end
		local rootSize = root.AbsoluteSize
		local gap = 14
		local totalWidth = 0
		for _, entry in ipairs(playedGhosts) do
			totalWidth = totalWidth + entry.ghost.AbsoluteSize.X
		end
		totalWidth = totalWidth + gap * (#playedGhosts - 1)
		local popupTop = scorePopup.AbsolutePosition.Y
		local rowY = math.max(20, popupTop - ROW_MARGIN_ABOVE_POPUP - ROW_CARD_HEIGHT)
		local x = (rootSize.X - totalWidth) / 2
		for _, entry in ipairs(playedGhosts) do
			tweenTo(entry.ghost, { Position = UDim2.fromOffset(x, rowY) }, GHOST_LIFT_DURATION, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
			x = x + entry.ghost.AbsoluteSize.X + gap
		end
	end

	-- "Camera Focus" substitute -- see file header. Dims every OTHER played
	-- ghost via a per-ghost overlay Frame (lazily created, cached on the
	-- ghost entry) rather than touching the ghost's own colors, so it can
	-- never interfere with the card's own text/badge/highlight tween.
	local function ensureDimOverlay(entry)
		if entry.dimOverlay then
			return entry.dimOverlay
		end
		local overlay = Instance.new("Frame")
		overlay.Name = "FocusDim"
		overlay.Size = UDim2.fromScale(1, 1)
		overlay.BackgroundColor3 = Color3.new(0, 0, 0)
		overlay.BackgroundTransparency = 1
		overlay.BorderSizePixel = 0
		overlay.ZIndex = entry.ghost.ZIndex + 1
		overlay.Parent = entry.ghost
		entry.dimOverlay = overlay
		return overlay
	end

	local function setPlayedRowFocus(playedGhosts, activeEntry)
		for _, entry in ipairs(playedGhosts) do
			if entry.ghost.Parent then
				local overlay = ensureDimOverlay(entry)
				tweenTo(overlay, { BackgroundTransparency = entry == activeEntry and 1 or 0.55 }, 0.12)
			end
		end
	end

	local function clearPlayedRowFocus(playedGhosts)
		for _, entry in ipairs(playedGhosts) do
			if entry.dimOverlay then
				tweenTo(entry.dimOverlay, { BackgroundTransparency = 1 }, 0.2)
			end
		end
	end

	-- ===== Per-source highlight beats =====

	local function highlightGhost(entry)
		local ghost = entry.ghost
		entry.baseColor = entry.baseColor or ghost.BackgroundColor3
		ghost.Visible = true
		tweenTo(entry.scale, { Scale = 1.22 }, 0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		tweenTo(ghost, { BackgroundColor3 = entry.baseColor:Lerp(Color3.new(1, 1, 1), 0.55) }, 0.1)
		task.delay(0.16, function()
			if ghost.Parent then
				tweenTo(entry.scale, { Scale = 1 }, 0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
				tweenTo(ghost, { BackgroundColor3 = entry.baseColor }, 0.25)
			end
		end)
	end

	local function ensureSlotScale(frame)
		local scale = frame:FindFirstChildOfClass("UIScale")
		if not scale then
			scale = Instance.new("UIScale")
			scale.Parent = frame
		end
		return scale
	end

	-- Rest color + overlap depth per Patron slot Frame, weak-keyed so it
	-- never leaks (same pattern as VisualHelpers.lua's shakeRestPositions).
	-- Needed because `frame` is the PERMANENT Sidebar seat, not a disposable
	-- ghost -- a single Patron can rack up more than one breakdown entry in
	-- one hand (a flat bonus + a Special, say), and nothing debounces
	-- rapid repeated Play Hand clicks, so two pulses on the SAME slot can
	-- easily overlap. Reading frame.BackgroundColor3 fresh each call (the
	-- first version of this function did) would capture an already-
	-- lerped-toward-FINALE_COLOR value as the "base" on the second overlap,
	-- so both resets would converge on the wrong color. Caching the TRUE
	-- rest color once, and only tweening back to it once every overlapping
	-- pulse on that slot has finished (pulseDepth reaches 0), fixes both
	-- problems at once. Found via independent review before shipping.
	local patronSlotRestColors = setmetatable({}, { __mode = "k" })
	local patronSlotPulseDepth = setmetatable({}, { __mode = "k" })

	-- "Joker Activation" equivalent -- scale + color flash on the Patron's
	-- actual, permanent Sidebar seat (never cloned/destroyed, so this is
	-- safe to animate directly and just settles back to normal after).
	local function pulsePatronSlot(frame)
		local scale = ensureSlotScale(frame)
		if not patronSlotRestColors[frame] then
			patronSlotRestColors[frame] = frame.BackgroundColor3
		end
		local restColor = patronSlotRestColors[frame]
		patronSlotPulseDepth[frame] = (patronSlotPulseDepth[frame] or 0) + 1

		tweenTo(scale, { Scale = 1.35 }, 0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		tweenTo(frame, { BackgroundColor3 = restColor:Lerp(FINALE_COLOR, 0.6) }, 0.1)
		task.delay(0.16, function()
			patronSlotPulseDepth[frame] = math.max(0, (patronSlotPulseDepth[frame] or 1) - 1)
			if frame.Parent and patronSlotPulseDepth[frame] == 0 then
				tweenTo(scale, { Scale = 1 }, 0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
				tweenTo(frame, { BackgroundColor3 = restColor }, 0.3)
			end
		end)
	end

	-- Brittle Garnish shattering -- destroyed early (not part of the calmer
	-- end-of-sequence drop-off) since that card is actually leaving the
	-- deck for good, not just going to the discard pile.
	local function shatterGhost(entry)
		local ghost = entry.ghost
		-- Placeholder SFX (see Sound.lua's dedicated-placeholder pattern) --
		-- no dedicated glass-break sound yet, chipTickSound pitched way up
		-- reads close enough as a "crack".
		playPitched(chipTickSound, 1.9, 0.5)
		particleBurst(centerOf(ghost), SHATTER_COLOR, 14, { spread = 90, duration = 0.4 })
		screenShake(root, 2, 0.12)
		tweenTo(ghost, { Rotation = 12 }, 0.08)
		tweenTo(entry.scale, { Scale = 0 }, 0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		task.delay(0.3, function()
			if ghost.Parent then
				ghost:Destroy()
			end
		end)
	end

	-- ===== Flying numbers =====

	-- Flies a small copy of the entry's text from `fromPos` to the center
	-- of `targetBox` (the blue Chips box or red Mult box), then bumps that
	-- box's own UIScale on arrival -- the "merging into it with a quick
	-- elastic bounce" Ahmed's spec calls for. Purely decorative: the box's
	-- actual running-total TEXT is updated immediately by the caller,
	-- same timing as the old HUD-only popup, so this can never desync
	-- from (or block on) the authoritative number.
	local function flyNumberToBox(fromPos, entry, color, targetBox)
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromOffset(96, 22)
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.Position = fromPos
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamBold
		label.TextSize = 16
		label.TextColor3 = color
		label.TextStrokeTransparency = 0.4
		label.Text = formatEntryText(entry)
		label.ZIndex = 32
		label.Parent = root

		tweenTo(label, { Position = centerOf(targetBox), TextTransparency = 0.6 }, FLY_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		task.delay(FLY_DURATION, function()
			label:Destroy()
			if targetBox.Parent then
				local boxScale = targetBox:FindFirstChildOfClass("UIScale")
				if boxScale then
					tweenTo(boxScale, { Scale = 1.18 }, 0.06)
					task.delay(0.06, function()
						if boxScale.Parent then
							tweenTo(boxScale, { Scale = 1 }, 0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
						end
					end)
				end
			end
		end)
	end

	-- Tips procs have no dedicated HUD box to fly into -- just a small
	-- "+N Tips" flash that floats up and fades near its source.
	local function floatTipsText(fromPos, entry)
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromOffset(100, 20)
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.Position = fromPos
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamBold
		label.TextSize = 15
		label.TextColor3 = KIND_COLORS.tips
		label.TextStrokeTransparency = 0.4
		label.Text = formatEntryText(entry)
		label.ZIndex = 32
		label.Parent = root

		local targetPos = UDim2.new(fromPos.X.Scale, fromPos.X.Offset, fromPos.Y.Scale, fromPos.Y.Offset - 46)
		tweenTo(label, { Position = targetPos, TextTransparency = 1 }, 0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		task.delay(0.6, function()
			label:Destroy()
		end)
	end

	-- Played ghosts drop toward the deck widget (bottom-right -- the same
	-- landmark new cards deal IN from, see rebuildHand's LAYOUT FEATURE 8)
	-- at the end of the sequence, matching "played cards drop off the
	-- bottom of the screen into the discard pile." Cards that already
	-- shattered (see shatterGhost) are skipped -- their ghost.Parent is
	-- already nil by the time this runs.
	--
	-- BUGFIX (Ahmed's Studio screenshot + report): this used to only tween
	-- each ghost down to Scale 0.5 and stop -- the ghost then just sat
	-- there, small but fully visible, parked at the deck for however long
	-- was left of FINALE_LINGER before the *next* showScorePopup call (or
	-- the end-of-sequence destroyGhosts below) finally cleaned it up. Ahmed
	-- described this as the cards "look like that for a bit instead of
	-- just disappearing after getting back to the deck" -- so now each
	-- ghost shrinks all the way to nothing and gets destroyed the instant
	-- its OWN drop tween finishes, instead of waiting on the shared
	-- end-of-sequence cleanup.
	local function dropOffPlayedGhosts(playedGhosts)
		local targetPos
		if deckWidgetButton and deckWidgetButton.Parent then
			targetPos = centerOf(deckWidgetButton)
		end
		for i, entry in ipairs(playedGhosts) do
			local startDelay = (i - 1) * 0.05
			task.delay(startDelay, function()
				local ghost = entry.ghost
				if ghost.Parent then
					local dest = targetPos or UDim2.fromOffset(ghost.Position.X.Offset, root.AbsoluteSize.Y + 120)
					tweenTo(ghost, { Position = dest }, DROPOFF_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
					tweenTo(entry.scale, { Scale = 0 }, DROPOFF_DURATION)
				end
			end)
			task.delay(startDelay + DROPOFF_DURATION, function()
				local ghost = entry.ghost
				if ghost.Parent then
					ghost:Destroy()
				end
				for liveIndex, liveEntry in ipairs(liveGhosts) do
					if liveEntry == entry then
						table.remove(liveGhosts, liveIndex)
						break
					end
				end
			end)
		end
	end

	-- preview: { name, chips, mult, score, breakdown, brokenCards } from
	-- computeHandPreview(). chips/mult/score are computed at the moment
	-- Play Hand is clicked, using the exact same scoring call
	-- RunState.playHand makes server-side, so this can never show a number
	-- that doesn't match what you actually get paid.
	-- sourceInfo: { cardGhosts, patronSlotFrames } from
	-- init.client.lua's buildScoreSourceInfo -- may be nil/omitted, in
	-- which case every per-source visual below just no-ops back to the
	-- plain center-HUD reveal.
	local function showScorePopup(preview, sourceInfo)
		scorePopupToken = scorePopupToken + 1
		local myToken = scorePopupToken

		-- Defensive cleanup: a previous sequence that got interrupted
		-- (e.g. the player queued up another hand before this one's
		-- reveal finished) may have left ghosts behind -- always start
		-- this call with a clean slate.
		destroyGhosts(liveGhosts)
		liveGhosts = {}

		sourceInfo = sourceInfo or {}
		local cardGhosts = sourceInfo.cardGhosts or {}
		local patronSlotFrames = sourceInfo.patronSlotFrames or {}
		for _, entry in ipairs(cardGhosts) do
			table.insert(liveGhosts, entry)
			-- HARD SAFETY NET (Ahmed's Studio screenshot showed a leaked
			-- ghost surviving into the Shop screen even after the
			-- cancelScorePopup()-on-phase-change fix): no matter what
			-- happens to `myToken`/liveGhosts bookkeeping above, or
			-- whether render() ever actually gets a chance to call
			-- cancelScorePopup for this specific state push, this ghost
			-- can never survive longer than GHOST_HARD_TIMEOUT -- well
			-- past any real sequence's worst-case natural duration (10
			-- animated entries at the slowest realistic pace + the
			-- finale's own linger is nowhere close to this). This only
			-- ever fires if something upstream already went wrong, as a
			-- true last-resort backstop against a PERMANENT leak.
			task.delay(GHOST_HARD_TIMEOUT, function()
				if entry.ghost and entry.ghost.Parent then
					entry.ghost:Destroy()
				end
			end)
		end

		local playedGhosts = {}
		for _, entry in ipairs(cardGhosts) do
			if entry.isPlayed then
				table.insert(playedGhosts, entry)
			end
		end

		scorePopupHandName.Text = preview.name
		scorePopupEventLabel.Text = ""
		chipsLabel.Text = "0"
		multLabel.Text = "0"
		scorePopup.Visible = true
		scorePopupScale.Scale = 0.6
		tweenTo(scorePopupScale, { Scale = 1.15 }, 0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

		task.delay(0.18, function()
			if scorePopupToken == myToken then
				tweenTo(scorePopupScale, { Scale = 1 }, 0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			end
		end)

		-- Lift the played row up out of the hand right away, so the cards
		-- are already in place by the time the reveal loop starts picking
		-- them out one at a time.
		layoutPlayedRow(playedGhosts)

		task.spawn(function()
			task.wait(0.2) -- let the hand-name pop land before the numbers start ticking

			local breakdown = preview.breakdown or {}
			local animatedCount = math.min(#breakdown, MAX_ANIMATED_ENTRIES)
			local runningChips, runningMult, runningXMult = 0, 0, 1

			for i, entry in ipairs(breakdown) do
				if scorePopupToken ~= myToken then
					return
				end

				if entry.kind == "chips" then
					runningChips = runningChips + entry.amount
				elseif entry.kind == "mult" then
					runningMult = runningMult + entry.amount
				elseif entry.kind == "xmult" then
					runningXMult = runningXMult * entry.amount
				end
				-- "tips" entries deliberately don't touch chips/mult/xmult --
				-- they don't affect the score math, just the Tips reward.

				if i <= animatedCount then
					-- PACING: a brief anticipation pause right before a
					-- big XMult hits, so the payout feels like it's
					-- building instead of ticking along at a flat rate.
					if entry.kind == "xmult" and entry.amount >= HIGH_TIER_XMULT then
						task.wait(ANTICIPATION_PAUSE)
						if scorePopupToken ~= myToken then
							return
						end
					end

					local color = KIND_COLORS[entry.kind] or FINALE_COLOR
					scorePopupEventLabel.Text = formatEntryText(entry)
					scorePopupEventLabel.TextColor3 = color

					-- VISUALS: elastic pop on the event line + color coding
					-- (kept from the prior pass -- always fires regardless
					-- of whether a ghost/slot is found below, so the text
					-- readout is never dependent on the choreography
					-- resolving correctly).
					scorePopupEventScale.Scale = 0.5
					tweenTo(scorePopupEventScale, { Scale = 1 }, 0.14, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

					-- AUDIO: pitch climbs a little with every consecutive
					-- trigger in this sequence, resetting fresh on the next
					-- Play Hand (myToken/i are both per-sequence, not global).
					local pitch = math.min(MAX_PITCH, BASE_PITCH + PITCH_STEP * (i - 1))
					playPitched(tickSoundFor(entry.kind), pitch, 0.35)

					-- SOURCE-AWARE CHOREOGRAPHY: trace this entry back to
					-- the card/Patron that caused it (see Scoring.lua's
					-- breakdown[i].source) and animate THAT specific
					-- on-screen thing, falling back to the plain center
					-- popup above if it can't be found.
					local source = entry.source or { type = "hand" }
					local sourcePos = nil

					if source.type == "card" then
						local ghostEntry = findGhostForCard(cardGhosts, source.card)
						if ghostEntry then
							setPlayedRowFocus(playedGhosts, ghostEntry)
							highlightGhost(ghostEntry)
							sourcePos = centerOf(ghostEntry.ghost)
						end
					elseif source.type == "heldCard" then
						local ghostEntry = findGhostForCard(cardGhosts, source.card)
						if ghostEntry then
							highlightGhost(ghostEntry)
							sourcePos = centerOf(ghostEntry.ghost)
						end
					elseif source.type == "patron" then
						local slotFrame = patronSlotFrames[source.patronId]
						if slotFrame then
							pulsePatronSlot(slotFrame)
							sourcePos = centerOf(slotFrame)
						end
					end

					if sourcePos then
						if entry.kind == "tips" then
							floatTipsText(sourcePos, entry)
						elseif entry.kind == "chips" then
							flyNumberToBox(sourcePos, entry, color, chipsLabel)
						else -- mult or xmult both merge into the red Mult box
							flyNumberToBox(sourcePos, entry, color, multLabel)
						end
					end

					local magnitude = entryMagnitude(entry)
					if magnitude > 0.3 then
						screenShake(root, math.min(6, 1.5 + magnitude), 0.16)
						particleBurst(sourcePos or centerOf(scorePopup), color, math.min(10, 2 + math.floor(magnitude)))
					end

					-- Running totals, floored before %d -- xmult chains can
					-- easily be fractional mid-sequence (e.g. a x1.5
					-- Special) even when the eventual final mult happens to
					-- land on a whole number.
					chipsLabel.Text = string.format("%d", math.floor(runningChips + 0.5))
					multLabel.Text = string.format("%d", math.floor(runningMult * runningXMult + 0.5))
					task.wait(ENTRY_STAGGER)
				end
			end

			if scorePopupToken ~= myToken then
				return
			end

			-- Brittle Garnish cards that shattered this hand -- shown
			-- right after the reveal loop, right before the finale, so
			-- the "this card broke" beat reads as the last thing that
			-- happened to it.
			if preview.brokenCards then
				for _, brokenCard in ipairs(preview.brokenCards) do
					local ghostEntry = findGhostForCard(cardGhosts, brokenCard)
					if ghostEntry and ghostEntry.ghost.Parent then
						shatterGhost(ghostEntry)
					end
				end
			end

			clearPlayedRowFocus(playedGhosts)

			-- FINALE: the real final numbers (guaranteed correct -- see file
			-- header comment), biggest pop + shake + burst + a pitched-down
			-- "bass thud" to land the payout.
			scorePopupEventLabel.Text = ""
			-- Floor both before %d -- chips can end up fractional too now
			-- (a Boss Round's chips-halving applied to an odd base chips
			-- value), not just mult -- Lua 5.3's %d hard-errors on a
			-- non-integral float.
			chipsLabel.Text = string.format("%d", math.floor(preview.chips + 0.5))
			multLabel.Text = string.format("%d", math.floor(preview.mult + 0.5))
			scorePopupScale.Scale = 1.3
			tweenTo(scorePopupScale, { Scale = 1 }, 0.22, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out)
			tweenTo(chipsScale, { Scale = 1.3 }, 0.1)
			tweenTo(multScale, { Scale = 1.3 }, 0.1)
			task.delay(0.1, function()
				if scorePopupToken == myToken then
					tweenTo(chipsScale, { Scale = 1 }, 0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
					tweenTo(multScale, { Scale = 1 }, 0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
				end
			end)

			playPitched(payoutThudSound, 0.55, 0.7) -- pitched well down to fake a heavy low thud

			local finalMagnitude = math.min(10, preview.score / 40)
			screenShake(root, math.min(10, 3 + finalMagnitude), 0.3)
			particleBurst(centerOf(scorePopup), FINALE_COLOR, math.min(24, 8 + math.floor(finalMagnitude)), { spread = 110, duration = 0.6 })

			-- "Played cards drop off the bottom of the screen into the
			-- discard pile" -- fires alongside the finale so it reads as
			-- part of the same beat, not a separate afterthought.
			dropOffPlayedGhosts(playedGhosts)

			-- Hide AFTER the sequence actually finishes, not on a fixed
			-- timer from when Play Hand was clicked -- a hand loaded with
			-- Patrons/Garnishes (several anticipation pauses stacked up)
			-- can easily take longer than any one fixed delay would assume,
			-- and hiding mid-sequence would cut the reveal off early. Ghost
			-- cleanup piggybacks on this same delay -- by FINALE_LINGER
			-- seconds after the finale, the drop-off tweens (<=0.5s + up
			-- to ~0.5s of per-card stagger) are guaranteed done well
			-- before it fires.
			task.delay(FINALE_LINGER, function()
				if scorePopupToken == myToken then
					scorePopup.Visible = false
					destroyGhosts(liveGhosts)
					liveGhosts = {}
				end
			end)
		end)
	end

	-- BUGFIX (Ahmed's Studio screenshot): nothing used to stop an in-flight
	-- reveal sequence if the game moved on to a new phase mid-animation --
	-- e.g. the hand that was just played WON the round, and the server's
	-- response (phase -> "shop") can arrive well before a several-second
	-- reveal sequence (several anticipation pauses stacked up) finishes.
	-- The sequence kept animating right through the phase change, so its
	-- ghosts (parented straight to `root`, which stays around under the
	-- Shop overlay) were still visibly flying around ON TOP of the Shop
	-- screen -- exactly what Ahmed's screenshot showed (a leftover played
	-- card + its flying number stuck floating over the Patron/Pack
	-- listings). Bumping the token immediately invalidates the running
	-- coroutine (it bails at its next per-entry check) and this also does
	-- the same cleanup its normal end-of-sequence path would have done,
	-- right now instead of waiting for a `task.delay` that may never
	-- fire correctly once the coroutine's already bailed early.
	local function cancelScorePopup()
		scorePopupToken = scorePopupToken + 1
		scorePopup.Visible = false
		scorePopupEventLabel.Text = ""
		destroyGhosts(liveGhosts)
		liveGhosts = {}
	end

	return {
		showScorePopup = showScorePopup,
		cancelScorePopup = cancelScorePopup,
	}
end
