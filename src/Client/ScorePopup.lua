--[[
	Client/ScorePopup.lua
	The step-by-step scoring sequence -- Play Hand triggers a step-by-step
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
	    a deliberate substitute, not a shortcut: the game is pure 2D UI
	    and never touches the Camera/character, so "focus" here is a
	    UI-only dim/highlight trick, same philosophy as screenShake
	    jittering the UI root instead of the camera.
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
		hasFastForwardPass -- optional function() -> boolean, live getter -- QoL Game Pass
		                       (Phase 9): with Animation Speed "Fast", upgrades the speed-up
		                       to the pass's full divisor (see pace()). Checked once at the top of each
		                       showScorePopup call, not per-entry -- a hand already mid-reveal
		                       finishes at whatever pace it started at.

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
	local SoundFX = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("SoundFX"))
	local CueBridge = require(script.Parent.Cue)
	local chipTickSound = deps.chipTickSound
	local multTickSound = deps.multTickSound
	local xmultTickSound = deps.xmultTickSound
	local payoutThudSound = deps.payoutThudSound
	local deckWidgetButton = deps.deckWidgetButton
	local hasFastForwardPass = deps.hasFastForwardPass

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
	local FINALE_DEFAULT = Color3.fromRGB(255, 214, 130)
	local FINALE_COLOR = FINALE_DEFAULT -- reassigned per hand from the equipped Flair (Engine/Flair.lua Score Numbers)
	local SHATTER_COLOR = Color3.fromRGB(210, 230, 255)

	-- PHASE A (Spectacle pass, Oct 2026, see claude/mind-blowing-plan.md):
	-- "Legendary Hand" moment -- a short freeze-frame beat BEFORE the
	-- normal reveal sequence starts, for a genuinely huge hand. Whether a
	-- given hand qualifies is decided by the CALLER (init.client.lua sets
	-- preview.isLegendary -- it has latestState.targetScore, which this
	-- module deliberately doesn't take as a dep), so this file only ever
	-- reacts to that one boolean field, same as every other optional
	-- preview/sourceInfo field this file already degrades gracefully
	-- without (see the file header).
	--
	-- PLAYTEST FEEDBACK (Ahmed, right after this first shipped): the
	-- first version also boosted every per-entry/finale shake+particle
	-- for a legendary hand's WHOLE reveal, on top of the freeze-frame --
	-- reported as "the multipliers are moving by so fast now, I liked it
	-- before where it was slower and you can take in the effects." That
	-- boost is gone (see entryMagnitude's call site and the finale below)
	-- -- a legendary hand's ENTIRE distinction is now the freeze-frame
	-- beat at the start; the reveal that follows is identical to a normal
	-- hand's, same intensity Ahmed already tuned it to.
	local LEGENDARY_BANNER_COLOR = Color3.fromRGB(255, 221, 140)
	local LEGENDARY_FLASH_COLOR = Color3.fromRGB(255, 225, 160)
	local LEGENDARY_FREEZE_HOLD = 0.45 -- how long the banner lingers before the normal per-entry reveal continues

	-- PHASE C ("mind-blowing plan" Signature Mechanic): the True Wildcard's
	-- OWN one-time freeze-frame beat -- same shape as the Legendary Hand
	-- banner above (built once, reused), but its own color (a distinct
	-- purple/violet, not gold, so the two never read as the same event)
	-- and dynamic text set fresh each time it fires, since WHICH card it
	-- became is different every run. See showScorePopup's wildcardResolution
	-- block below for when this actually plays -- driven by
	-- Client/init.client.lua's computeHandPreview, which only ever sets
	-- preview.wildcardResolution the ONE time this card is actually played
	-- unresolved (never from the live sidebar preview, which never calls
	-- this file at all).
	local WILDCARD_BANNER_COLOR = Color3.fromRGB(205, 170, 255)
	local WILDCARD_FLASH_COLOR = Color3.fromRGB(190, 160, 255)
	local WILDCARD_FREEZE_HOLD = 0.5

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
	-- PACING: Ahmed's report -- playing a single card as a High Card hand
	-- (e.g. "Ace of Clubs +11 Chips") still went by so fast he had to
	-- screenshot it to read it, even at 0.75s. A short hand only has 1-2
	-- entries total, so there's nothing else filling the sequence to make
	-- it feel deliberate -- the one line that matters needs to actually
	-- hold long enough to read on its own, not just relative to a longer
	-- sequence. Bumped again to 1.3s.
	local ENTRY_STAGGER = 1.0 -- seconds between entries -- long enough to actually read each line
	local ANTICIPATION_PAUSE = 0.5
	local FLY_DURATION = 0.4 -- < ENTRY_STAGGER, so a flying number always lands before the next entry starts
	local GHOST_LIFT_DURATION = 0.35 -- played row "lift out of hand" tween
	local DROPOFF_DURATION = 0.7 -- played row "drop into discard" tween at the end
	-- BUGFIX (report: "the sound effect... with the explosions doesn't
	-- fit"): dropOffPlayedGhosts used to fire in the exact same instant as
	-- the finale's payout thud + particle burst below, which made the loud
	-- "explosion" read as if it belonged to the cards quietly sliding back
	-- to the deck. This short gap lets the burst/thud land and read as its
	-- OWN beat (the payout landing) before the calmer drop-off starts.
	local DROPOFF_START_DELAY = 0.3
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
	local FINALE_LINGER = 0.7

	-- QoL Game Pass (Fast Forward, Phase 9): every task.wait/tween duration
	-- above gets funneled through pace() rather than used directly, so
	-- there's exactly one place that decides how fast the choreography
	-- runs. The divisor (PlayerProfile.animationPaceDivisor: Animation
	-- Speed setting + Fast Forward pass) shrinks every one of those durations by
	-- the same factor -- same relative pacing/
	-- readability the constants above were carefully tuned for (see their
	-- own comments), just compressed, not reshuffled. currentPaceDivisor
	-- is re-read once at the top of each showScorePopup call (not
	-- per-entry) so a hand already mid-reveal can't change speed partway
	-- through if ownership happens to resolve mid-sequence.
	local ClientSettings = require(script.Parent.ClientSettings)
	local PlayerProfileEngine = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("PlayerProfile"))
	local currentPaceDivisor = 1
	local function pace(duration)
		if currentPaceDivisor == 1 then
			return duration
		end
		return duration / currentPaceDivisor
	end

	local POPUP_H = 112
	local READOUT_INK = Color3.fromRGB(40, 24, 12)
	local scorePopup = Instance.new("Frame")
	scorePopup.Name = "ScorePopup"
	-- The readout sits ABOVE the played cards (layoutPlayedRow sets Position from the row's top edge),
	-- never over the hand: event line, a parchment pill with Chips x Mult, then the hand name on a dark pill.
	scorePopup.Size = UDim2.new(0, 360, 0, POPUP_H)
	scorePopup.AnchorPoint = Vector2.new(0.5, 0)
	scorePopup.Position = UDim2.new(0.5, 0, 0, 120)
	scorePopup.BackgroundTransparency = 1
	scorePopup.Visible = false
	scorePopup.ZIndex = 25
	scorePopup.Parent = root

	local scorePopupHandName = Instance.new("TextLabel")
	local handPill = Instance.new("Frame")
	handPill.Name = "HandPill"
	handPill.AnchorPoint = Vector2.new(0.5, 0)
	handPill.Position = UDim2.new(0.5, 0, 0, 80)
	handPill.Size = UDim2.new(0, 260, 0, 30)
	handPill.BackgroundColor3 = Color3.fromRGB(34, 24, 16)
	handPill.BackgroundTransparency = 0.05
	handPill.BorderSizePixel = 0
	handPill.ZIndex = 24
	handPill.Parent = scorePopup
	local handPillCorner = Instance.new("UICorner")
	handPillCorner.CornerRadius = UDim.new(0.5, 0)
	handPillCorner.Parent = handPill
	scorePopupHandName.Size = UDim2.new(1, 0, 1, 0)
	scorePopupHandName.BackgroundTransparency = 1
	scorePopupHandName.Font = Enum.Font.GothamBold
	scorePopupHandName.TextSize = 20
	scorePopupHandName.TextColor3 = Color3.fromRGB(255, 230, 180)
	scorePopupHandName.TextStrokeTransparency = 0.5
	scorePopupHandName.Text = ""
	scorePopupHandName.ZIndex = 25
	scorePopupHandName.Parent = handPill

	-- SCORING JUICE, full choreography pass: split out of the old single
	-- "chips x mult" label into a real blue Chips box / red Mult box, so
	-- flying numbers have an actual matching box to merge into (Ahmed's
	-- spec: "the blue Chips box and red Mult box pop directly into the
	-- HUD" / "slam together... as the math completes").
	local readoutPill = Instance.new("Frame")
	readoutPill.Name = "ReadoutPill"
	readoutPill.AnchorPoint = Vector2.new(0.5, 0)
	readoutPill.Position = UDim2.new(0.5, 0, 0, 26)
	readoutPill.Size = UDim2.new(0, 260, 0, 50)
	readoutPill.BackgroundColor3 = Color3.fromRGB(240, 228, 196)
	readoutPill.BorderSizePixel = 0
	readoutPill.ZIndex = 24
	readoutPill.Parent = scorePopup
	local readoutCorner = Instance.new("UICorner")
	readoutCorner.CornerRadius = UDim.new(0.5, 0)
	readoutCorner.Parent = readoutPill
	local readoutEdge = Instance.new("UIStroke")
	readoutEdge.Color = Color3.fromRGB(120, 84, 40)
	readoutEdge.Thickness = 2
	readoutEdge.Parent = readoutPill
	local function readoutOutline(label)
		local o = Instance.new("UIStroke")
		o.Name = "ReadoutOutline"
		o.Color = READOUT_INK
		o.Thickness = 2
		o.Parent = label
	end
	local chipsLabel = Instance.new("TextLabel")
	chipsLabel.Size = UDim2.new(0, 105, 0, 50)
	chipsLabel.Position = UDim2.new(0, 10, 0, 0)
	chipsLabel.BackgroundTransparency = 1
	chipsLabel.Font = Enum.Font.GothamBold
	chipsLabel.TextSize = 28
	chipsLabel.TextColor3 = Color3.fromRGB(60, 130, 235)
	chipsLabel.TextStrokeTransparency = 1
	chipsLabel.TextXAlignment = Enum.TextXAlignment.Right
	chipsLabel.Text = "0"
	chipsLabel.ZIndex = 25
	chipsLabel.Parent = readoutPill
	readoutOutline(chipsLabel)

	local xLabel = Instance.new("TextLabel")
	xLabel.Size = UDim2.new(0, 30, 0, 50)
	xLabel.Position = UDim2.new(0, 115, 0, 0)
	xLabel.BackgroundTransparency = 1
	xLabel.Font = Enum.Font.GothamBold
	xLabel.TextSize = 26
	xLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	xLabel.TextStrokeTransparency = 1
	xLabel.TextXAlignment = Enum.TextXAlignment.Center
	xLabel.Text = "x"
	xLabel.ZIndex = 25
	xLabel.Parent = readoutPill
	readoutOutline(xLabel)

	local multLabel = Instance.new("TextLabel")
	multLabel.Size = UDim2.new(0, 105, 0, 50)
	multLabel.Position = UDim2.new(0, 145, 0, 0)
	multLabel.BackgroundTransparency = 1
	multLabel.Font = Enum.Font.GothamBold
	multLabel.TextSize = 28
	multLabel.TextColor3 = Color3.fromRGB(225, 55, 55)
	multLabel.TextStrokeTransparency = 1
	multLabel.TextXAlignment = Enum.TextXAlignment.Left
	multLabel.Text = "0"
	multLabel.ZIndex = 25
	multLabel.Parent = readoutPill
	readoutOutline(multLabel)

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
	scorePopupEventLabel.Size = UDim2.new(1, 0, 0, 24)
	scorePopupEventLabel.Position = UDim2.new(0, 0, 0, 0)
	scorePopupEventLabel.BackgroundTransparency = 1
	scorePopupEventLabel.Font = Enum.Font.GothamBold
	scorePopupEventLabel.TextSize = 18
	scorePopupEventLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	scorePopupEventLabel.TextStrokeTransparency = 0
	scorePopupEventLabel.TextStrokeColor3 = Color3.fromRGB(25, 15, 8)
	scorePopupEventLabel.Text = ""
	scorePopupEventLabel.ZIndex = 25
	scorePopupEventLabel.Parent = scorePopup

	local scorePopupScale = Instance.new("UIScale")
	scorePopupScale.Scale = 1
	scorePopupScale.Parent = scorePopup

	local scorePopupEventScale = Instance.new("UIScale")
	scorePopupEventScale.Scale = 1
	scorePopupEventScale.Parent = scorePopupEventLabel

	-- PHASE A (Spectacle pass): a big slammed-in banner built once here and reused every call (same pattern as scorePopup itself) -- see
	-- showScorePopup's `legendary` block below for when it gets driven. The old flat full-screen colour wash is gone: Client/FlashFX draws
	-- a soft glow, edge vignette and drifting motes instead (nothing over 15 percent opacity across the screen).
	local FlashFX = require(script.Parent.FlashFX)
	local activeFlash = nil -- the effect on screen (stopped when the sequence is cancelled)
	local legendaryBanner = Instance.new("TextLabel")
	legendaryBanner.Name = "LegendaryBanner"
	legendaryBanner.AnchorPoint = Vector2.new(0.5, 0.5)
	legendaryBanner.Position = UDim2.fromScale(0.5, 0.3)
	legendaryBanner.Size = UDim2.new(0, 560, 0, 60)
	legendaryBanner.BackgroundTransparency = 1
	legendaryBanner.Font = Enum.Font.GothamBlack
	legendaryBanner.TextSize = 36
	legendaryBanner.TextColor3 = LEGENDARY_BANNER_COLOR
	-- BUGFIX (Ahmed's Studio screenshot: the banner stayed fully legible
	-- forever, even sitting in the Shop): TextTransparency only hides a
	-- TextLabel's FILL -- the stroke/outline is a separate property that
	-- was left at a permanent 0.1 (90% opaque) here and never touched
	-- anywhere else, so the bold "⚡ LEGENDARY HAND ⚡" outline rendered
	-- forever from the very first time this ever showed, independent of
	-- TextTransparency. Starts at 1 (hidden) like the fill now, and every
	-- place below that shows/hides the banner animates both together.
	legendaryBanner.TextStrokeTransparency = 1
	legendaryBanner.TextStrokeColor3 = Color3.fromRGB(80, 40, 20)
	legendaryBanner.TextTransparency = 1
	legendaryBanner.Text = "⚡ LEGENDARY HAND ⚡"
	legendaryBanner.ZIndex = 34
	legendaryBanner.Parent = root

	local legendaryBannerScale = Instance.new("UIScale")
	legendaryBannerScale.Scale = 1
	legendaryBannerScale.Parent = legendaryBanner

	-- POLISH 1: "NEW BEST!" / "TARGET CLEARED!" banner (hidden until the finale).
	local ScoreJuice = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("ScoreJuice"))
	local ScoreFeel = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("ScoreFeel")) -- tier size/color, combo, big-hand shake
	local juiceBest = 0
	local juiceBanner = Instance.new("TextLabel")
	juiceBanner.Name = "ScoreJuiceBanner"
	juiceBanner.AnchorPoint = Vector2.new(0.5, 0.5)
	juiceBanner.Position = UDim2.fromScale(0.5, 0.4)
	juiceBanner.Size = UDim2.new(0, 520, 0, 56)
	juiceBanner.BackgroundTransparency = 1
	juiceBanner.Font = Enum.Font.GothamBlack
	juiceBanner.TextSize = 34
	juiceBanner.TextColor3 = Color3.fromRGB(255, 214, 90)
	juiceBanner.TextStrokeColor3 = Color3.fromRGB(70, 40, 15)
	juiceBanner.TextTransparency = 1
	juiceBanner.TextStrokeTransparency = 1
	juiceBanner.Text = ""
	juiceBanner.ZIndex = 34
	juiceBanner.Parent = root
	local juiceScale = Instance.new("UIScale")
	juiceScale.Parent = juiceBanner

	-- PHASE C ("mind-blowing plan" Signature Mechanic): the True
	-- Wildcard's own flash/banner, same construction as the Legendary
	-- Hand pair above, its own instances so the two can never fight over
	-- the same TextLabel/Frame if a hand is somehow both at once (rare,
	-- but not impossible -- a locked-in Four of a Kind COULD also clear
	-- the Legendary threshold). wildcardBanner.Text is set fresh per call
	-- in showScorePopup below -- unlike the Legendary banner, there's no
	-- fixed string to set once here.
	local wildcardBanner = Instance.new("TextLabel")
	wildcardBanner.Name = "WildcardBanner"
	wildcardBanner.AnchorPoint = Vector2.new(0.5, 0.5)
	wildcardBanner.Position = UDim2.fromScale(0.5, 0.3)
	wildcardBanner.Size = UDim2.new(0, 560, 0, 70)
	wildcardBanner.BackgroundTransparency = 1
	wildcardBanner.Font = Enum.Font.GothamBlack
	wildcardBanner.TextSize = 30
	wildcardBanner.TextWrapped = true
	wildcardBanner.TextColor3 = WILDCARD_BANNER_COLOR
	-- Same TextTransparency/TextStrokeTransparency-together discipline as
	-- legendaryBanner above (see its own BUGFIX comment) -- both start
	-- hidden, both always animated as a pair, everywhere below.
	wildcardBanner.TextStrokeTransparency = 1
	wildcardBanner.TextStrokeColor3 = Color3.fromRGB(45, 25, 70)
	wildcardBanner.TextTransparency = 1
	wildcardBanner.Text = ""
	wildcardBanner.ZIndex = 34
	wildcardBanner.Parent = root

	local wildcardBannerScale = Instance.new("UIScale")
	wildcardBannerScale.Scale = 1
	wildcardBannerScale.Parent = wildcardBanner

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
		local rootSize = root.AbsoluteSize
		-- the played hand lands as a small tilted, slightly overlapping group with a soft shadow (Engine/PlayMotion.stackSpec);
		-- calm mode keeps the flat row
		local stacked = ClientSettings.get("reduceShake") ~= true
		local gap = stacked and -8 or 14
		local PMotion = stacked and require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("PlayMotion")) or nil
		local totalWidth = 0
		for _, entry in ipairs(playedGhosts) do
			totalWidth = totalWidth + entry.ghost.AbsoluteSize.X
		end
		totalWidth = totalWidth + gap * (#playedGhosts - 1)
		-- reference line the row has always hung from (the old popup's top edge)
		local popupTop = root.AbsolutePosition.Y + rootSize.Y - 356
		local rowY = math.max(20, popupTop - ROW_MARGIN_ABOVE_POPUP - ROW_CARD_HEIGHT)
		-- Boss rounds: keep the row below the boss plaque and HP bar (host bottom),
		-- but never lower than just above the popup.
		local bossHost = root:FindFirstChild("BossFightHost")
		local bossPlate = bossHost and bossHost:FindFirstChild("NamePlate") -- the host is now a full-area backdrop
		if bossHost and bossPlate and bossHost.Visible then
			local bossBottom = bossPlate.AbsolutePosition.Y - root.AbsolutePosition.Y + bossPlate.AbsoluteSize.Y
			rowY = math.min(math.max(rowY, bossBottom + 6), popupTop - 6 - ROW_CARD_HEIGHT)
		end
		-- the readout hangs just above the row's top edge, clear of the hand
		scorePopup.Position = UDim2.new(0.5, 0, 0, math.max(4, rowY - 8 - POPUP_H))
		if #playedGhosts == 0 then
			return
		end
		local x = (rootSize.X - totalWidth) / 2
		for i, entry in ipairs(playedGhosts) do
			local dy, rot = 0, nil
			if PMotion then
				local _, sy, sr = PMotion.stackSpec(i, #playedGhosts)
				dy, rot = sy, sr
				if not entry.ghost:FindFirstChild("StackShadow") then
					local sh = Instance.new("Frame")
					sh.Name = "StackShadow"
					sh.AnchorPoint = Vector2.new(0.5, 0)
					sh.Position = UDim2.new(0.5, 0, 1, -2)
					sh.Size = UDim2.new(0.86, 0, 0, 14)
					sh.BackgroundColor3 = Color3.new(0, 0, 0)
					sh.BackgroundTransparency = 0.7
					sh.BorderSizePixel = 0
					sh.Active = false
					sh.ZIndex = 29 -- under the ghost (30), in Global layering
					local c = Instance.new("UICorner")
					c.CornerRadius = UDim.new(0.5, 0)
					c.Parent = sh
					sh.Parent = entry.ghost
				end
			end
			tweenTo(entry.ghost, { Position = UDim2.fromOffset(x, rowY + dy) }, pace(GHOST_LIFT_DURATION), Enum.EasingStyle.Back, Enum.EasingDirection.Out)
			if rot then tweenTo(entry.ghost, { Rotation = rot }, pace(GHOST_LIFT_DURATION)) end
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

	-- AI ART (card-face template rollout): this used to flash ghost's own
	-- BackgroundColor3 white then back -- which is now completely hidden
	-- once the card-art image sits on top of it (see init.client.lua's
	-- rebuildHand). Same fix as ensureDimOverlay above and for the exact
	-- same reason: a lazily-created per-ghost overlay Frame, so the flash
	-- can never interfere with -- or be hidden behind -- the ghost's own
	-- art/text/badge. ZIndex one above ensureDimOverlay's overlay so a
	-- highlight beat still reads clearly even on a ghost that's
	-- simultaneously NOT focus-dimmed (the common case -- see the call
	-- sites below, which fire setPlayedRowFocus and highlightGhost
	-- together).
	local function ensureHighlightOverlay(entry)
		if entry.highlightOverlay then
			return entry.highlightOverlay
		end
		local overlay = Instance.new("Frame")
		overlay.Name = "ScoreHighlight"
		overlay.Size = UDim2.fromScale(1, 1)
		overlay.BackgroundColor3 = Color3.new(1, 1, 1)
		overlay.BackgroundTransparency = 1
		overlay.BorderSizePixel = 0
		overlay.ZIndex = entry.ghost.ZIndex + 2
		overlay.Parent = entry.ghost
		entry.highlightOverlay = overlay
		return overlay
	end

	local function highlightGhost(entry)
		local ghost = entry.ghost
		local overlay = ensureHighlightOverlay(entry)
		ghost.Visible = true
		tweenTo(entry.scale, { Scale = 1.22 }, 0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		tweenTo(overlay, { BackgroundTransparency = 0.45 }, 0.1)
		task.delay(0.16, function()
			if ghost.Parent then
				tweenTo(entry.scale, { Scale = 1 }, 0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
				tweenTo(overlay, { BackgroundTransparency = 1 }, 0.25)
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
		-- No dedicated glass-break sound exists yet -- borrows chipTickSound
		-- (see Sound.lua) pitched way up, which reads close enough as a
		-- "crack" for now. Worth a real dedicated shatter SFX if this ever
		-- gets its own pass.
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
		label.Size = UDim2.fromOffset(200, 22) -- wide enough for "3 of Hearts  +3 Chips"
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.Position = fromPos
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamBold
		label.TextSize = 16
		label.TextColor3 = color
		label.TextStrokeTransparency = 0.4
		label.Text = formatEntryText(entry)
		label.ZIndex = 60 -- above the played cards
		label.Parent = root

		tweenTo(label, { Position = centerOf(targetBox), TextTransparency = 0.6 }, pace(FLY_DURATION), Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		task.delay(pace(FLY_DURATION), function()
			label:Destroy()
			if targetBox.Parent then
				local boxScale = targetBox:FindFirstChildOfClass("UIScale")
				if boxScale then
					tweenTo(boxScale, { Scale = 1.15 }, 0.06)
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
		label.ZIndex = 60 -- above the played cards
		label.Parent = root

		local targetPos = UDim2.new(fromPos.X.Scale, fromPos.X.Offset, fromPos.Y.Scale, fromPos.Y.Offset - 46)
		-- BUGFIX (Phase 9, caught by independent review before shipping):
		-- this was hardcoded (not wrapped in pace()) while every sibling
		-- timed element (flyNumberToBox etc.) was -- with Fast Forward
		-- owned, a Tips proc's float would visibly lag/overlap into the
		-- next beat instead of speeding up with everything else.
		local floatDuration = pace(0.6)
		tweenTo(label, { Position = targetPos, TextTransparency = 1 }, floatDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		task.delay(floatDuration, function()
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
			local startDelay = pace((i - 1) * 0.05)
			local dropoffDuration = pace(DROPOFF_DURATION)
			task.delay(startDelay, function()
				local ghost = entry.ghost
				if ghost.Parent then
					local dest = targetPos or UDim2.fromOffset(ghost.Position.X.Offset, root.AbsoluteSize.Y + 120)
					tweenTo(ghost, { Position = dest }, dropoffDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
					tweenTo(entry.scale, { Scale = 0 }, dropoffDuration)
				end
			end)
			task.delay(startDelay + dropoffDuration, function()
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

		-- PHASE A (Spectacle pass): decided once per hand, same timing as
		-- currentPaceDivisor just below -- see this file's "LEGENDARY
		-- BANNER_COLOR" comment above for why this file trusts the caller's
		-- flag instead of re-deriving it.
		local legendary = preview.isLegendary == true

		-- PHASE C ("mind-blowing plan" Signature Mechanic): only set by
		-- Client/init.client.lua's computeHandPreview when THIS exact play
		-- is the one, once-per-run hand that resolves the True Wildcard --
		-- see that function's own comment. { rank, suit, label } or nil.
		local wildcardResolution = preview.wildcardResolution

		-- Settings > Display > Animation Speed, decided once per hand (see
		-- pace()). "fast" is a free mild speed-up; owning the Fast Forward
		-- pass upgrades it to the full one (PlayerProfile.animationPaceDivisor).
		currentPaceDivisor = PlayerProfileEngine.animationPaceDivisor(
			ClientSettings.get("animSpeed"),
			hasFastForwardPass ~= nil and hasFastForwardPass()
		)

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

		-- FLAIR (visual only, Engine/Flair.lua): the Score Numbers color and a few Play Trail particles
		pcall(function()
			local FlairFX = require(script.Parent.FlairFX)
			FINALE_COLOR = FlairFX.scoreColor() or FINALE_DEFAULT
			FlairFX.playTrail(particleBurst, centerOf(scorePopup))
			-- Score Numbers glow on every digit tick (chips and mult), not only the finale
			local glow, flairColor = FlairFX.scoreGlow(), FlairFX.scoreColor()
			for _, digits in ipairs({ chipsLabel, multLabel }) do
				local stroke = digits:FindFirstChild("FlairGlow")
				if glow > 0 and flairColor then
					if not stroke then
						stroke = Instance.new("UIStroke")
						stroke.Name = "FlairGlow"
						stroke.Parent = digits
					end
					stroke.Color = flairColor
					stroke.Thickness = glow
					stroke.Enabled = true
				elseif stroke then
					stroke.Enabled = false
				end
			end
		end)
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
			-- PHASE A (Spectacle pass): freeze-frame beat, fires BEFORE the
			-- normal per-entry reveal starts -- a big slammed-in banner, a
			-- hard screen flash, a heavier shake, a low "boom" stinger (the
			-- existing payout thud, pitched down further -- no new asset
			-- needed), and a scatter of extra particle bursts across the
			-- whole screen. Everything from here through the end of this
			-- hand's reveal also gets boosted shake/particle magnitude --
			-- see entryMagnitude's call sites below.
			-- PHASE C ("mind-blowing plan" Signature Mechanic): the True
			-- Wildcard's own freeze-frame, fires BEFORE the Legendary beat
			-- (and before the normal per-entry reveal) if both happen to
			-- land on the same hand -- a once-per-run moment earns going
			-- first. Same shape as the Legendary block just below, its own
			-- instances/color/hold.
			if wildcardResolution then
				-- one message in the centre at a time: wait (briefly) for the Announcer's turn, free the slot when the banner is gone
				local wildcardTicket
				do
					local okA, Announcer = pcall(function() return require(script.Parent.Announcer) end)
					if okA then
						wildcardTicket = Announcer.request("wildcard", 3, 2.6)
						wildcardTicket.wait(1.5)
					end
				end
				if scorePopupToken ~= myToken then
					if wildcardTicket then wildcardTicket.release() end
					return
				end
				wildcardBanner.TextTransparency = 1
				wildcardBanner.TextStrokeTransparency = 1
				wildcardBannerScale.Scale = 0.4
				wildcardBanner.Text = "🎴 TRUE WILDCARD LOCKS IN:\n" .. wildcardResolution.label .. "!"

				-- HARD SAFETY NET, same pattern as the Legendary banner's
				-- own timeout just below -- this can never stay on screen
				-- longer than this, full stop.
				task.delay(2.5, function()
					wildcardBanner.TextTransparency = 1
					wildcardBanner.TextStrokeTransparency = 1
				end)
				playPitched(payoutThudSound, 0.5, 0.85)
				CueBridge.play("legendary_moment") -- the win sting +5, a low thud and a two note chime (+12 and +19)
				CueBridge.duck()
				screenShake(root, 8, pace(0.3))
				particleBurst(centerOf(scorePopup), WILDCARD_FLASH_COLOR, 12, { spread = 100, duration = 0.55 })

				if activeFlash then activeFlash.stop() end
				activeFlash = FlashFX.play(root, "wildcard", centerOf(scorePopup), { zIndex = 33, banner = wildcardBanner })

				tweenTo(wildcardBanner, { TextTransparency = 0, TextStrokeTransparency = 0.1 }, pace(0.12))
				tweenTo(wildcardBannerScale, { Scale = 1.15 }, pace(0.22), Enum.EasingStyle.Back, Enum.EasingDirection.Out)
				task.delay(pace(0.22), function()
					if scorePopupToken == myToken then
						tweenTo(wildcardBannerScale, { Scale = 1 }, pace(0.14), Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
					end
				end)

				task.wait(pace(WILDCARD_FREEZE_HOLD))
				if wildcardTicket then wildcardTicket.release() end
				if scorePopupToken ~= myToken then
					return
				end
				tweenTo(wildcardBanner, { TextTransparency = 1, TextStrokeTransparency = 1 }, pace(0.4))
			end

			if legendary then
				legendaryBanner.TextTransparency = 1
				legendaryBanner.TextStrokeTransparency = 1
				legendaryBannerScale.Scale = 0.4

				-- HARD SAFETY NET, same pattern as the ghosts' own
				-- GHOST_HARD_TIMEOUT below: no matter what else goes wrong
				-- (a bug in the token bookkeeping, an interrupted sequence
				-- that skips the normal fade-out above), this banner can
				-- never stay on screen longer than this, full stop.
				task.delay(2.5, function()
					legendaryBanner.TextTransparency = 1
					legendaryBanner.TextStrokeTransparency = 1
				end)
				playPitched(payoutThudSound, 0.55, 0.8)
				CueBridge.play("legendary_moment")
				CueBridge.duck()
				screenShake(root, 9, pace(0.35))
				particleBurst(centerOf(scorePopup), LEGENDARY_FLASH_COLOR, 10, { spread = 90, duration = 0.5 })
				for _ = 1, 4 do
					local randomPos = UDim2.fromScale(0.15 + math.random() * 0.7, 0.15 + math.random() * 0.55)
					particleBurst(randomPos, (math.random() > 0.5) and FINALE_COLOR or Color3.fromRGB(200, 130, 255), 14, { spread = 140, duration = 0.6 })
				end

				if activeFlash then activeFlash.stop() end
				activeFlash = FlashFX.play(root, "legendary", centerOf(scorePopup), { zIndex = 33, banner = legendaryBanner })

				tweenTo(legendaryBanner, { TextTransparency = 0, TextStrokeTransparency = 0.1 }, pace(0.12))
				tweenTo(legendaryBannerScale, { Scale = 1.15 }, pace(0.22), Enum.EasingStyle.Back, Enum.EasingDirection.Out)
				task.delay(pace(0.22), function()
					if scorePopupToken == myToken then
						tweenTo(legendaryBannerScale, { Scale = 1 }, pace(0.14), Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
					end
				end)

				task.wait(pace(LEGENDARY_FREEZE_HOLD))
				if scorePopupToken ~= myToken then
					return
				end
				tweenTo(legendaryBanner, { TextTransparency = 1, TextStrokeTransparency = 1 }, pace(0.4))
			end

			task.wait(pace(0.2)) -- let the hand-name pop land before the numbers start ticking

			local breakdown = preview.breakdown or {}
			local animatedCount = math.min(#breakdown, MAX_ANIMATED_ENTRIES)
			local runningChips, runningMult, runningXMult = 0, 0, 1
			local chipTicks, multTicks = 0, 0 -- the pitch ladder: each tick of a kind rises a half step (Engine/SoundFX)

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
						task.wait(pace(ANTICIPATION_PAUSE))
						if scorePopupToken ~= myToken then
							return
						end
					end

					local color = KIND_COLORS[entry.kind] or FINALE_COLOR
					scorePopupEventLabel.Text = formatEntryText(entry)
					scorePopupEventLabel.TextColor3 = Color3.fromRGB(255, 244, 214) -- cream on a dark outline: the kind colour read at 2:1 on the sky

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
					-- SOUND PASS: a half step up per tick (capped at +12 semitones), the volume climbing a little, and an xmult tick an octave
					-- over the last mult tick (Engine/SoundFX.tick)
					local plan
					if entry.kind == "xmult" then
						plan = SoundFX.tick("xmult", 1, multTicks)
					elseif entry.kind == "mult" then
						multTicks = multTicks + 1
						plan = SoundFX.tick("mult", multTicks)
					else
						chipTicks = chipTicks + 1
						plan = SoundFX.tick("chips", chipTicks)
					end
					playPitched(tickSoundFor(entry.kind), plan.speed, plan.volume)

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
							-- voice line + hop, once per hand per Patron (cosmetic, never throws)
							pcall(function()
								require(script.Parent.PatronVoice).say(source.patronId, slotFrame, preview)
							end)
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

					-- PLAYTEST FEEDBACK (Ahmed, right after Phase A shipped):
					-- "the multipliers are moving by so fast now, I liked it
					-- before where it was slower and you can take in the
					-- effects." The per-entry boost that used to live here
					-- (bigger shake/particle caps on a legendary hand) made
					-- THIS already-tuned reveal loop feel more chaotic/rushed
					-- even though its timing (ENTRY_STAGGER etc.) never
					-- actually changed -- extra shake on every single entry
					-- reads as "faster" even at the same pace. Reverted: a
					-- legendary hand's distinction is now ENTIRELY the
					-- freeze-frame beat above (and the finale's below) --
					-- every entry in between plays at the exact same
					-- intensity/pace it always has, legendary or not.
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
					task.wait(pace(ENTRY_STAGGER))
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
			-- GAME FEEL: the finale pop grows with the hand's share of the Target, its hand name takes the tier's color,
			-- a big hand (half the Target or more) gets an extra slam, and the combo counter ticks up (visual only).
			local feelTier = ScoreFeel.tierFor(preview.score, preview.targetScore)
			local feelColor = ScoreFeel.tierColor(feelTier)
			scorePopupHandName.TextColor3 = Color3.fromRGB(feelColor[1], feelColor[2], feelColor[3])
			scorePopupScale.Scale = ScoreFeel.popScale(feelTier)
			do
				local slam = ScoreFeel.slamFor(feelTier)
				if slam > 0 and currentPaceDivisor == 1 then -- Reduce shake is honored inside screenShake; Fast skips it
					screenShake(root, slam + 3, 0.22)
				end
				pcall(function()
					require(script.Parent.ComboCounter).hand(preview.score, (preview.roundScoreBefore or 0) <= 0)
				end)
			end
			tweenTo(scorePopupScale, { Scale = 1 }, 0.22, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out)
			tweenTo(chipsScale, { Scale = 1.3 }, 0.1)
			tweenTo(multScale, { Scale = 1.3 }, 0.1)
			task.delay(0.1, function()
				if scorePopupToken == myToken then
					tweenTo(chipsScale, { Scale = 1 }, 0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
					tweenTo(multScale, { Scale = 1 }, 0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
				end
			end)

			-- POLISH (Phase 14 playtest feedback): payoutThudSound used to be
			-- "magic_bomb" pitched way down (0.55x) to fake a heavy impact --
			-- reported as "way too aggressive, sounds like a kamehameha."
			-- It's now "cash register" (see Sound.lua), a completely
			-- different sound family that doesn't need disguising -- just a
			-- gentle 0.85x to land it with a touch of weight.
			playPitched(payoutThudSound, 0.85, 0.6)
			CueBridge.coinCascade(0.35) -- the payout landing: 3 coins 60 ms apart at slightly different pitch
			CueBridge.sting(preview.name) -- a hand-type sting by tier (the biggest tier also ducks the music)

			-- PLAYTEST FEEDBACK: same revert as the per-entry loop above --
			-- the finale's own boost is gone too. A legendary hand's whole
			-- distinction is the freeze-frame beat at the very start now;
			-- everything from here on (including this finale) plays
			-- identically to a normal hand's reveal.
			local finalMagnitude = math.min(10, preview.score / 40)
			screenShake(root, math.min(10, 3 + finalMagnitude), 0.3)
			particleBurst(centerOf(scorePopup), FINALE_COLOR, math.min(24, 8 + math.floor(finalMagnitude)), { spread = 110, duration = 0.6 })
			pcall(function() require(script.Parent.FlairFX).finisher(particleBurst, centerOf(scorePopup), preview, ScoreJuice.clearsTarget(preview.roundScoreBefore, preview.score, preview.targetScore)) end) -- equipped Finisher: any clearing hand, stronger on big hands

			-- POLISH 1: record hand flourish + target-cleared pulse (rules in
			-- Engine/ScoreJuice). Slow-motion beat is a short hold with the
			-- popup scaled up; skipped on Fast pace (currentPaceDivisor > 1).
			do
				if preview.isRunStart then
					juiceBest = 0
				end
				local newBest = ScoreJuice.isNewBest(preview.score, juiceBest)
				local clears = ScoreJuice.clearsTarget(preview.roundScoreBefore, preview.score, preview.targetScore)
				juiceBest = math.max(juiceBest, preview.score)
				if newBest or clears then
					local color = newBest and Color3.fromRGB(255, 214, 90) or Color3.fromRGB(150, 235, 150)
					juiceBanner.Text = newBest and "NEW BEST!" or "TARGET CLEARED!"
					juiceBanner.TextColor3 = color
					juiceBanner.TextTransparency = 0
					juiceBanner.TextStrokeTransparency = 0.2
					juiceScale.Scale = 0.5
					tweenTo(juiceScale, { Scale = 1.1 }, pace(0.25), Enum.EasingStyle.Back, Enum.EasingDirection.Out)
					playPitched(payoutThudSound, 1.25, 0.5)
					if clears then
						CueBridge.play("win", 0.6) -- the round win: the win sting and a coin cascade, the music ducks for the beat
						CueBridge.coinCascade(0.3)
						CueBridge.duck()
					end
					screenShake(root, ScoreJuice.shakeFor(preview.score, preview.targetScore), pace(0.3))
					particleBurst(centerOf(scorePopup), color, ScoreJuice.burstFor(preview.score, preview.targetScore), { spread = 140, duration = 0.7 })
					if clears then
						tweenTo(scorePopupScale, { Scale = 1.25 }, pace(0.15))
						task.delay(pace(0.15), function()
							if scorePopupToken == myToken then
								tweenTo(scorePopupScale, { Scale = 1 }, pace(0.3), Enum.EasingStyle.Back, Enum.EasingDirection.Out)
							end
						end)
					end
					if currentPaceDivisor == 1 then
						task.wait(ScoreJuice.slowMoFor(newBest, clears))
					end
					task.delay(pace(1.4), function()
						tweenTo(juiceBanner, { TextTransparency = 1, TextStrokeTransparency = 1 }, pace(0.4))
					end)
					-- Hard safety net like the other banners.
					task.delay(2.5, function()
						juiceBanner.TextTransparency = 1
						juiceBanner.TextStrokeTransparency = 1
					end)
					if scorePopupToken ~= myToken then
						return
					end
				end
			end

			-- "Played cards drop off the bottom of the screen into the
			-- discard pile" -- used to fire alongside the finale burst/thud
			-- above; now waits DROPOFF_START_DELAY (see that constant) so
			-- it reads as its own separate, calmer beat instead of getting
			-- lumped in with the "explosion."
			task.delay(pace(DROPOFF_START_DELAY), function()
				if scorePopupToken == myToken then
					dropOffPlayedGhosts(playedGhosts)
				end
			end)

			-- Hide AFTER the sequence actually finishes, not on a fixed
			-- timer from when Play Hand was clicked -- a hand loaded with
			-- Patrons/Garnishes (several anticipation pauses stacked up)
			-- can easily take longer than any one fixed delay would assume,
			-- and hiding mid-sequence would cut the reveal off early. Ghost
			-- cleanup piggybacks on this same delay.
			--
			-- BUGFIX: this used to just be pace(FINALE_LINGER), on the
			-- assumption the drop-off tweens were always done well before
			-- it fired. That was already a slightly optimistic guess for a
			-- big hand (5+ played cards' stagger + DROPOFF_DURATION could
			-- exceed FINALE_LINGER, letting destroyGhosts below force-cut a
			-- ghost mid-tween -- an abrupt pop instead of its own shrink-
			-- to-nothing), and adding DROPOFF_START_DELAY above only made
			-- that worse. Computed properly now from the actual number of
			-- played ghosts this hand, so destroyGhosts can never fire
			-- before every ghost's own drop-off tween has genuinely
			-- finished -- small hands are unaffected (FINALE_LINGER still
			-- wins the max()), only big ones get the extra beat they
			-- actually need.
			local worstCaseDropoffTime = pace(DROPOFF_START_DELAY)
				+ pace(math.max(0, #playedGhosts - 1) * 0.05)
				+ pace(DROPOFF_DURATION)
			task.delay(math.max(pace(FINALE_LINGER), worstCaseDropoffTime + 0.05), function()
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
		-- PHASE A (Spectacle pass): defensive reset, same reasoning as the
		-- rest of this function -- a phase change mid-sequence shouldn't be
		-- able to leave a legendary flash/banner stuck visible over
		-- whatever screen comes next. Both TextTransparency (fill) AND
		-- TextStrokeTransparency (outline) -- see this banner's own BUGFIX
		-- comment at its creation for why leaving either one out is exactly
		-- how it got stuck visible in the first place.
		legendaryBanner.TextTransparency = 1
		legendaryBanner.TextStrokeTransparency = 1
		if activeFlash then activeFlash.stop() activeFlash = nil end
		-- PHASE C: same defensive reset for the True Wildcard's own
		-- banner/flash pair -- see wildcardBanner's own comment at its
		-- creation.
		wildcardBanner.TextTransparency = 1
		wildcardBanner.TextStrokeTransparency = 1
		destroyGhosts(liveGhosts)
		liveGhosts = {}
	end

	return {
		showScorePopup = showScorePopup,
		cancelScorePopup = cancelScorePopup,
	}
end
