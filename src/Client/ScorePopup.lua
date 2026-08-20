--[[
	Client/ScorePopup.lua
	Balatro's signature score-pop -- the "Hand Name / chips x mult" callout
	shown when Play Hand is clicked. Parented to root (not handFrame --
	rebuildHand() destroys every Frame child of handFrame on every render(),
	which would destroy this the instant a hand is played) and centered on
	the full screen rather than the narrower play area, to avoid hand-
	crafting sidebar/deck-widget-aware centering math for an element that's
	only ever on screen for a couple seconds.

	SCORING JUICE (this pass): this used to just flash the final "chips x
	mult" once. It now plays preview.breakdown (see Scoring.lua's
	extra.breakdown) back as a SEQUENCE -- each individual scoring event
	(the base hand, every scoring card's rank/Garnish/Special/Stamp, every
	owned Patron's effect/Special) pops in one at a time, color-coded by
	kind (blue Chips / red Mult / purple XMult), with an escalating-pitch
	tick sound, a small screen shake + particle burst scaled to that
	event's size, and a brief anticipation pause before a big XMult hit --
	then finishes on the real final numbers with the biggest pop/shake/
	burst and a pitched-down "thud". Matches the "AI Implementation Prompt"
	Ahmed pasted in almost field-for-field (audio pitch escalation + bass
	thud, elastic scaling + color coding + shake/particles proportional to
	payout, anticipatory micro-delays before high-tier multipliers).

	The running chips/mult totals shown DURING the sequence are computed by
	replaying the same breakdown the engine returned -- summing every
	"chips"/"mult" entry and multiplying every "xmult" entry gives back
	EXACTLY preview.chips/preview.mult (see Scoring.calculate's own
	comment on why breakdown is purely additive data), so there's no way
	for the animation to end on a different number than what you actually
	get paid. The finale re-sets the labels to preview.chips/preview.mult
	directly anyway, as a belt-and-suspenders guard against float drift
	from repeated multiplication.

	A hand with lots of Patrons/Garnishes can generate a LOT of breakdown
	entries (worst case: 5 cards x up to ~3 triggers each, plus 5 Patrons x
	up to ~3 bonuses each plus a Special = 50+). MAX_ANIMATED_ENTRIES caps
	how many get their own animated beat so one huge hand can't turn into
	a multi-second slog -- everything past the cap still counts toward the
	running/final totals, it just doesn't get its own pop/tick/shake.

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

	Returns:
		{
			showScorePopup = function(preview),
			-- preview: { name, chips, mult, score, breakdown } from
			--   computeHandPreview(). breakdown may be nil (e.g. if the
			--   preview computation failed for some reason) -- the popup
			--   still shows correctly, it just skips straight to the finale.
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

	-- Blue = Chips, Red = Mult, Purple = XMult -- straight from Ahmed's spec.
	local KIND_COLORS = {
		chips = Color3.fromRGB(110, 180, 255),
		mult = Color3.fromRGB(255, 110, 110),
		xmult = Color3.fromRGB(200, 130, 255),
	}
	local FINALE_COLOR = Color3.fromRGB(255, 214, 130)

	-- PACING: Ahmed's first playtest of this feature couldn't actually
	-- read any of the per-entry text before it was replaced by the next
	-- one -- 0.09s between entries is fine for a sound/shake beat but way
	-- too fast for a human to read a few words. ENTRY_STAGGER is the main
	-- knob if this still feels off; MAX_ANIMATED_ENTRIES was brought down
	-- to compensate (a much slower per-entry pace needs a lower cap to
	-- keep a big hand's worst-case sequence from dragging on).
	local MAX_ANIMATED_ENTRIES = 10 -- see file header -- caps worst-case sequence length
	local BASE_PITCH = 1.0
	local PITCH_STEP = 0.045 -- per-entry pitch increment -- "increment sequentially along a musical scale"
	local MAX_PITCH = 1.7
	local HIGH_TIER_XMULT = 2 -- xmult entries at/above this get an anticipation pause before they land
	local ENTRY_STAGGER = 0.45 -- seconds between entries -- long enough to actually read each line
	local ANTICIPATION_PAUSE = 0.3

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

	local scorePopupMath = Instance.new("TextLabel")
	scorePopupMath.Size = UDim2.new(1, 0, 0, 50)
	scorePopupMath.Position = UDim2.new(0, 0, 0, 26)
	scorePopupMath.BackgroundTransparency = 1
	scorePopupMath.Font = Enum.Font.GothamBold
	scorePopupMath.TextSize = 36
	scorePopupMath.TextColor3 = Color3.fromRGB(255, 255, 255)
	scorePopupMath.TextStrokeTransparency = 0.4
	scorePopupMath.Text = ""
	scorePopupMath.ZIndex = 25
	scorePopupMath.Parent = scorePopup

	-- SCORING JUICE: the per-entry "what just triggered" line -- e.g.
	-- "King of Hearts  +9 Chips" -- color-coded and separately elastic-
	-- popped from the big total above it.
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

	local function tickSoundFor(kind)
		if kind == "chips" then
			return chipTickSound
		elseif kind == "mult" then
			return multTickSound
		end
		return xmultTickSound
	end

	local function formatEntryText(entry)
		if entry.kind == "xmult" then
			return string.format("%s  x%g XMult", entry.label, entry.amount)
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
		end
		return math.min(6, math.abs(entry.amount) / 4)
	end

	local function burstPositionFor(frame)
		return UDim2.fromOffset(
			frame.AbsolutePosition.X + frame.AbsoluteSize.X / 2,
			frame.AbsolutePosition.Y + frame.AbsoluteSize.Y / 2
		)
	end

	-- preview: { name, chips, mult, score, breakdown } from
	-- computeHandPreview(). chips/mult/score are computed at the moment
	-- Play Hand is clicked, using the exact same scoring call
	-- RunState.playHand makes server-side, so this can never show a number
	-- that doesn't match what you actually get paid.
	local function showScorePopup(preview)
		scorePopupToken = scorePopupToken + 1
		local myToken = scorePopupToken

		scorePopupHandName.Text = preview.name
		scorePopupEventLabel.Text = ""
		scorePopupMath.Text = "0 x 0"
		scorePopup.Visible = true
		scorePopupScale.Scale = 0.6
		tweenTo(scorePopupScale, { Scale = 1.15 }, 0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

		task.delay(0.18, function()
			if scorePopupToken == myToken then
				tweenTo(scorePopupScale, { Scale = 1 }, 0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			end
		end)

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

					-- VISUALS: elastic pop on the event line + color coding.
					scorePopupEventScale.Scale = 0.5
					tweenTo(scorePopupEventScale, { Scale = 1 }, 0.14, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

					-- AUDIO: pitch climbs a little with every consecutive
					-- trigger in this sequence, resetting fresh on the next
					-- Play Hand (myToken/i are both per-sequence, not global).
					local pitch = math.min(MAX_PITCH, BASE_PITCH + PITCH_STEP * (i - 1))
					playPitched(tickSoundFor(entry.kind), pitch, 0.35)

					local magnitude = entryMagnitude(entry)
					if magnitude > 0.3 then
						screenShake(root, math.min(6, 1.5 + magnitude), 0.16)
						particleBurst(burstPositionFor(scorePopup), color, math.min(10, 2 + math.floor(magnitude)))
					end

					-- Running total, floored before %d -- xmult chains can
					-- easily be fractional mid-sequence (e.g. a x1.5
					-- Special) even when the eventual final mult happens to
					-- land on a whole number.
					scorePopupMath.Text = string.format("%d x %d", runningChips, math.floor(runningMult * runningXMult + 0.5))
					task.wait(ENTRY_STAGGER)
				end
			end

			if scorePopupToken ~= myToken then
				return
			end

			-- FINALE: the real final numbers (guaranteed correct -- see file
			-- header comment), biggest pop + shake + burst + a pitched-down
			-- "bass thud" to land the payout.
			scorePopupEventLabel.Text = ""
			-- Floor both before %d -- chips can end up fractional too now
			-- (a Boss Round's chips-halving applied to an odd base chips
			-- value), not just mult -- Lua 5.3's %d hard-errors on a
			-- non-integral float.
			scorePopupMath.Text = string.format("%d x %d", math.floor(preview.chips + 0.5), math.floor(preview.mult + 0.5))
			scorePopupScale.Scale = 1.3
			tweenTo(scorePopupScale, { Scale = 1 }, 0.22, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out)

			playPitched(payoutThudSound, 0.55, 0.7) -- pitched well down to fake a heavy low thud

			local finalMagnitude = math.min(10, preview.score / 40)
			screenShake(root, math.min(10, 3 + finalMagnitude), 0.3)
			particleBurst(burstPositionFor(scorePopup), FINALE_COLOR, math.min(24, 8 + math.floor(finalMagnitude)), { spread = 110, duration = 0.6 })

			-- Hide AFTER the sequence actually finishes, not on a fixed
			-- timer from when Play Hand was clicked -- a hand loaded with
			-- Patrons/Garnishes (several anticipation pauses stacked up)
			-- can easily take longer than any one fixed delay would assume,
			-- and hiding mid-sequence would cut the reveal off early. 1.6s
			-- (up from 1.1s) so the final total actually gets read too,
			-- not just flashed.
			task.delay(1.6, function()
				if scorePopupToken == myToken then
					scorePopup.Visible = false
				end
			end)
		end)
	end

	return {
		showScorePopup = showScorePopup,
	}
end
