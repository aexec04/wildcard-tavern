--[[
	Client/GameOver.lua
	The panel shown when state.phase == "gameover", with its "Play Again"
	button.

	Extracted out of init.client.lua as part of splitting the client script
	into smaller, per-feature files. Both pieces are needed back in
	init.client.lua: applyTheme() tweens their colors on a theme change, and
	render() calls refreshGameOver(state) whenever state.phase == "gameover"
	(same "build once, refresh in place" pattern as Shop.lua/Journey.lua).
	The Play Again click handler itself is wired from init.client.lua's
	"Wire up buttons" section (it needs RestartRunRemote, which lives
	there), so playAgainButton comes back out too.

	BUGFIX: this used to have a bare `gameOverLabel.Text = ...` assignment
	sitting directly in init.client.lua's render() -- but gameOverLabel was
	never actually destructured from this module's return table (and this
	module never returned it in the first place), so that line threw
	"attempt to index nil with 'Text'" on EVERY single state push once
	phase == "gameover" (Ahmed's Output log caught this: "Last call! Your
	run has ended." never got the dynamic "you made it to Night N, Round R"
	text because of it). Fixed by moving all of this panel's own text/state
	logic into this module as refreshGameOver(state), which owns its own
	labels directly -- no more reaching into a half-destructured local from
	the other file.

	POLISH PASS: also distinguishes an actual win (state.wonRun -- cleared
	Night nightCap's Boss Round at some point this run, which stays true
	forever even if the run later ends during Endless Mode) from a loss,
	with different icon/color/copy for each, a Final Score/Tips stat line,
	and a one-time pop-in reveal (via UIScale) the moment a NEW run-ending
	state actually shows -- not on every state push while already sitting
	on this screen (see lastGameOverKey below).

	deps fields:
		root          -- Frame, gameOverFrame's parent
		polishPanel    -- function(instance, radius)
		polishButton   -- function(instance, radius)
		addSoftShadow  -- function(instance, radius)
		tweenTo        -- function(instance, props, duration, easingStyle?, easingDirection?)
		playSfx        -- function(soundId, volume?) -- see Sound.lua
		SOUND_IDS      -- table, for SOUND_IDS.gameOverWin/gameOverLoss
		gameOverWinBackgroundImage -- string, "rbxassetid://..." -- see Client/ArtAssets.lua

	AI ART: gameOverWinBackgroundImage is a celebration-scene illustration
	from the art brief, shown ONLY on an actual win (see winBackgroundArt
	below) -- still "rbxassetid://0" until uploaded, which Roblox renders
	as no image, so the win state just looks like the loss state (flat
	panel, no picture) until a real id is filled in.

	POLISH (Phase 14, requested fix: "there is no losing sound, it just
	brings up this screen"): this panel played NO sound at all on either
	outcome before -- fixed by playing SOUND_IDS.gameOverWin/gameOverLoss
	once per genuinely NEW run-ending state, reusing the exact same
	lastGameOverKey gate the pop-in reveal animation already uses below (so
	it fires once per fresh loss/win, never replays just from sitting on
	this screen while other players' actions push unrelated state updates).

	ONE MORE ROUND: a button sits next to Play Again whenever the server
	offers this run its one continue (state.continueOffer: "free" for the
	player's free one today, "paid" for the Developer Product, nil for
	none; see RunState.canContinue). Its click is wired in
	init.client.lua next to Play Again's. A run that already used its
	continue (state.revived) shows a "Revived" badge in the top corner, so
	the summary never passes for a Standard run.

	Returns:
		{
			gameOverFrame = Frame,
			playAgainButton = TextButton,
			continueButton = TextButton,
			refreshGameOver = function(state),
		}
]]

return function(deps)
	local root = deps.root
	local GameOverTips = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("GameOverTips"))
	local polishPanel = deps.polishPanel
	local polishButton = deps.polishButton
	local addSoftShadow = deps.addSoftShadow
	local tweenTo = deps.tweenTo
	local playSfx = deps.playSfx
	local SOUND_IDS = deps.SOUND_IDS
	local gameOverWinBackgroundImage = deps.gameOverWinBackgroundImage

	-- dim is the full-screen even dark dim (hides the table so no cards peek out) and sinks clicks; the wood panel
	-- sits centred inside it, so one Visible flag on `dim` (returned as gameOverFrame) shows and hides everything.
	local dim = Instance.new("Frame")
	dim.Name = "GameOver"
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = Color3.fromRGB(10, 8, 6)
	dim.BackgroundTransparency = 0.25
	dim.BorderSizePixel = 0
	dim.Active = true
	dim.Visible = false
	dim.Parent = root

	local gameOverFrame = Instance.new("Frame")
	gameOverFrame.Name = "Panel"
	gameOverFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	gameOverFrame.Size = UDim2.new(0.5, 0, 0, 470)
	gameOverFrame.Position = UDim2.fromScale(0.5, 0.5)
	gameOverFrame.BackgroundColor3 = Color3.fromRGB(40, 30, 22)
	gameOverFrame.ClipsDescendants = true
	gameOverFrame.Parent = dim
	local sizeLimit = Instance.new("UISizeConstraint")
	sizeLimit.MinSize = Vector2.new(560, 470)
	sizeLimit.MaxSize = Vector2.new(780, 470)
	sizeLimit.Parent = gameOverFrame
	polishPanel(gameOverFrame, 16, "wood")
	-- Painted background (PanelArt): flat panel color if the art id is missing.
	local gameOverFrameArt = require(script.Parent.PanelArt).add(gameOverFrame, {
		key = "game_over_lose_bg", zIndex = 20, scrim = { position = UDim2.fromScale(0, 0), size = UDim2.fromScale(1, 1) },
		scrimTransparency = 0.35,
	})
	addSoftShadow(gameOverFrame, 18)

	-- ART (placeholder-safe, see Client/ArtAssets.lua): win-only background
	-- illustration. Starts hidden -- refreshGameOver below flips Visible to
	-- match isWin every time this panel refreshes, so it's never shown for
	-- a loss. ImageTransparency keeps it from fighting the readability of
	-- the text/stats drawn on top (ZIndex 21+) once a real id is filled in.
	local winBackgroundArt = Instance.new("ImageLabel")
	winBackgroundArt.Name = "WinBackgroundArt"
	winBackgroundArt.Size = UDim2.fromScale(1, 1)
	winBackgroundArt.BackgroundTransparency = 1
	winBackgroundArt.ImageTransparency = 0.15
	winBackgroundArt.BorderSizePixel = 0
	winBackgroundArt.ScaleType = Enum.ScaleType.Crop
	winBackgroundArt.Image = gameOverWinBackgroundImage or "rbxassetid://0"
	winBackgroundArt.Visible = false
	winBackgroundArt.ZIndex = 20
	winBackgroundArt.Parent = gameOverFrame

	-- POLISH: everything below the accent bar is grouped under one child
	-- Frame so the pop-in UIScale (see revealPending below) scales the
	-- whole panel's CONTENT from its visual center, not from the
	-- top-left corner the way scaling gameOverFrame itself would (an
	-- AnchorPoint(0.5,0.5) + UIScale combination reads as a much more
	-- natural "pop," not a corner-anchored stretch).
	local content = Instance.new("Frame")
	content.Name = "Content"
	content.Size = UDim2.fromScale(1, 1)
	content.BackgroundTransparency = 1
	content.ZIndex = 21
	content.Parent = gameOverFrame

	local contentScale = Instance.new("UIScale")
	contentScale.Scale = 1
	contentScale.Parent = content

	local iconLabel = Instance.new("TextLabel")
	iconLabel.Size = UDim2.new(1, 0, 0, 50)
	iconLabel.Position = UDim2.new(0, 0, 0, 22)
	iconLabel.BackgroundTransparency = 1
	iconLabel.Font = Enum.Font.GothamBold
	iconLabel.TextSize = 40
	iconLabel.Text = "🕯️"
	iconLabel.ZIndex = 22
	iconLabel.Parent = content

	local gameOverLabel = Instance.new("TextLabel")
	gameOverLabel.Size = UDim2.new(1, -40, 0, 68)
	gameOverLabel.Position = UDim2.new(0, 20, 0, 74)
	gameOverLabel.BackgroundTransparency = 1
	gameOverLabel.Font = Enum.Font.GothamBold
	gameOverLabel.TextSize = 28
	gameOverLabel.TextWrapped = true
	gameOverLabel.TextColor3 = Color3.fromRGB(250, 240, 220)
	gameOverLabel.Text = "Last call! Your run has ended."
	gameOverLabel.ZIndex = 22
	gameOverLabel.Parent = content

	-- Final Score / Night reached / Tips banked -- previously this panel
	-- showed no stats at all once the run ended, just the one static
	-- sentence (and, thanks to the bug above, not even the dynamic part of
	-- THAT sentence).
	local function statRow(name, y)
		local plate = Instance.new("Frame")
		plate.Name = name
		plate.Size = UDim2.new(1, -80, 0, 38)
		plate.Position = UDim2.new(0, 40, 0, y)
		plate.BackgroundColor3 = Color3.fromRGB(30, 22, 16)
		plate.BackgroundTransparency = 0.15
		plate.BorderSizePixel = 0
		plate.ZIndex = 22
		plate.Parent = content
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 10)
		corner.Parent = plate
		local label = Instance.new("TextLabel")
		label.Name = "Label"
		label.Size = UDim2.new(1, -24, 1, 0)
		label.Position = UDim2.fromOffset(12, 0)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamBold
		label.TextSize = 18
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextColor3 = Color3.fromRGB(250, 240, 220)
		label.Text = ""
		label.ZIndex = 23
		label.Parent = plate
		return label
	end
	local scoreLabel = statRow("ScoreRow", 150)
	local tipsLabel = statRow("TipsRow", 194)

	-- PHASE A (Spectacle pass, see claude/mind-blowing-plan.md): a small
	-- run-recap line -- the single biggest hand this run (tracked purely
	-- client-side by Client/RunRecap.lua). Separate label from statsLabel
	-- above (not just appended text) so it can be hidden entirely when
	-- bestHand is nil (e.g. the run ended before a single hand scored --
	-- an immediate quit -- rather than showing an empty/misleading line).
	local recapLabel = Instance.new("TextLabel")
	recapLabel.Size = UDim2.new(1, -80, 0, 24)
	recapLabel.Position = UDim2.new(0, 40, 0, 240)
	recapLabel.BackgroundTransparency = 1
	recapLabel.Font = Enum.Font.GothamBold
	recapLabel.TextSize = 18
	recapLabel.TextWrapped = true
	recapLabel.TextColor3 = Color3.fromRGB(255, 214, 130)
	recapLabel.Text = ""
	recapLabel.Visible = false
	recapLabel.ZIndex = 22
	recapLabel.Parent = content

	local hintLabel = Instance.new("TextLabel")
	hintLabel.Name = "Hint"
	hintLabel.Size = UDim2.new(1, -80, 0, 44)
	hintLabel.Position = UDim2.new(0, 40, 0, 272)
	hintLabel.BackgroundTransparency = 1
	hintLabel.Font = Enum.Font.GothamMedium
	hintLabel.TextSize = 16
	hintLabel.TextWrapped = true
	hintLabel.TextColor3 = Color3.fromRGB(235, 222, 195)
	hintLabel.Text = ""
	hintLabel.Visible = false
	hintLabel.ZIndex = 22
	hintLabel.Parent = content

	local playAgainButton = Instance.new("TextButton")
	playAgainButton.Name = "PlayAgain"
	playAgainButton.Size = UDim2.new(0, 220, 0, 48)
	playAgainButton.Position = UDim2.new(0.5, -230, 1, -70)
	playAgainButton.Font = Enum.Font.GothamBold
	playAgainButton.TextSize = 20
	playAgainButton.Text = "Play Again"
	playAgainButton.BackgroundColor3 = Color3.fromRGB(196, 150, 60)
	playAgainButton.TextColor3 = Color3.fromRGB(40, 28, 14)
	playAgainButton.ZIndex = 22
	playAgainButton.Parent = content
	polishButton(playAgainButton, 10)

	local continueButton = Instance.new("TextButton")
	continueButton.Name = "ContinueButton"
	continueButton.Size = UDim2.new(0, 220, 0, 48)
	continueButton.Position = UDim2.new(0.5, -110, 1, -130)
	continueButton.Font = Enum.Font.GothamBold
	continueButton.TextSize = 20
	continueButton.TextWrapped = true
	continueButton.Text = "One More Round"
	continueButton.BackgroundColor3 = Color3.fromRGB(60, 110, 70)
	continueButton.TextColor3 = Color3.fromRGB(250, 240, 220)
	continueButton.Visible = false
	continueButton.ZIndex = 22
	continueButton.Parent = content
	polishButton(continueButton, 10)

	local tavernButton = Instance.new("TextButton")
	tavernButton.Name = "BackToTavern"
	tavernButton.Size = UDim2.new(0, 220, 0, 48)
	tavernButton.Position = UDim2.new(0.5, 10, 1, -70)
	tavernButton.Font = Enum.Font.GothamBold
	tavernButton.TextSize = 20
	tavernButton.Text = "Back to Tavern"
	tavernButton.BackgroundColor3 = Color3.fromRGB(70, 50, 34)
	tavernButton.TextColor3 = Color3.fromRGB(250, 240, 220)
	tavernButton.ZIndex = 22
	tavernButton.Parent = content
	polishButton(tavernButton, 10)
	local revivedBadge = Instance.new("TextLabel")
	revivedBadge.Name = "RevivedBadge"
	revivedBadge.AnchorPoint = Vector2.new(1, 0)
	revivedBadge.Size = UDim2.new(0, 110, 0, 26)
	revivedBadge.Position = UDim2.new(1, -14, 0, 16)
	revivedBadge.BackgroundColor3 = Color3.fromRGB(70, 120, 150)
	revivedBadge.Font = Enum.Font.GothamBold
	revivedBadge.TextSize = 14
	revivedBadge.TextColor3 = Color3.fromRGB(250, 240, 220)
	revivedBadge.Text = "\u{1F4AB} Revived"
	revivedBadge.Visible = false
	revivedBadge.ZIndex = 23
	revivedBadge.Parent = content
	polishPanel(revivedBadge, 13)

	-- Only replays the pop-in/fade reveal when this is genuinely a NEW
	-- run-ending state (a fresh loss, or the run flipping from ongoing to
	-- won) -- not on every subsequent state push while the player is just
	-- sitting on this screen deciding whether to hit Play Again (render()
	-- fires on any state change, and other players' actions in a
	-- multiplayer session could still push a state update here). Same
	-- "only trust a change in this key" pattern Journey.lua/RoundSelect.lua
	-- already use for their own animations/confirmations.
	local lastGameOverKey = nil

	-- bestHand (new, PHASE A): optional { name = string, score = number }
	-- from Client/RunRecap.lua's getBest() -- nil if no hand scored this
	-- run yet (an immediate quit) or the tracker was never wired up.
	local function refreshGameOver(state, bestHand)
		if not state then
			return
		end

		local isWin = state.wonRun == true
		winBackgroundArt.Visible = isWin
		if gameOverFrameArt then
			gameOverFrameArt.Visible = not isWin
			local loseScrim = gameOverFrame:FindFirstChild("PanelScrim")
			if loseScrim then
				loseScrim.Visible = not isWin
			end
		end

		-- PAID CONTINUE: badge for a run that used its continue, and the
		-- Continue button only while the server allows one. With Continue
		-- showing, the two buttons sit side by side; otherwise Play Again
		-- stays centered.
		local isRevived = state.revived == true
		revivedBadge.Visible = isRevived
		local canContinue = state.continueOffer == "free" or state.continueOffer == "paid"
		continueButton.Visible = canContinue
		continueButton.Text = state.continueOffer == "free" and "One More Round (Free)" or "One More Round"
		-- Play Again (gold, primary) left, Back to Tavern right; One More Round sits above them when offered.
		if isWin then
			iconLabel.Text = "🏆"
			gameOverLabel.Text = "Last call, but what a night! You beat the tavern."
		else
			iconLabel.Text = "🕯️"
			gameOverLabel.Text = string.format(
				"Last call! You made it to Night %d, Round %d.",
				state.night, state.round
			)
		end

		scoreLabel.Text = string.format("Final score: %d / %d", math.floor(state.roundScore or 0), math.floor(state.targetScore or 0))
		tipsLabel.Text = string.format("Tips banked: %d", math.floor(state.tips or 0))
		local hint = (not isWin) and GameOverTips.pick(state.night, state.round) or nil
		hintLabel.Visible = hint ~= nil
		hintLabel.Text = hint and ("Tip: " .. hint) or ""

		-- PHASE A (Spectacle pass): only shown when there's actually a hand
		-- to brag about -- see recapLabel's own comment above for why this
		-- hides entirely rather than showing an empty/misleading line.
		if bestHand then
			recapLabel.Visible = true
			recapLabel.Text = string.format("⚡ Biggest Hand: %s: %d", bestHand.name, bestHand.score)
		else
			recapLabel.Visible = false
			recapLabel.Text = ""
		end

		-- isRevived is part of the key so losing again after a continue
		-- (same Night/Round) still counts as a new run-ending moment.
		local key = tostring(state.night) .. "-" .. tostring(state.round) .. "-" .. tostring(isWin) .. "-" .. tostring(isRevived)
		if key ~= lastGameOverKey then
			-- POLISH: pop-in reveal -- content starts slightly shrunk and
			-- fully transparent, tweens up to full scale/opacity. UIScale
			-- (not a Size tween) so every child scales together from one
			-- shared center instead of each element needing its own tween.
			contentScale.Scale = 0.82
			iconLabel.TextTransparency = 1
			gameOverLabel.TextTransparency = 1
			scoreLabel.TextTransparency = 1
			tipsLabel.TextTransparency = 1
			hintLabel.TextTransparency = 1
			tavernButton.BackgroundTransparency = 1
			tavernButton.TextTransparency = 1
			recapLabel.TextTransparency = 1
			playAgainButton.BackgroundTransparency = 1
			playAgainButton.TextTransparency = 1
			continueButton.BackgroundTransparency = 1
			continueButton.TextTransparency = 1

			tweenTo(contentScale, { Scale = 1 }, 0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
			tweenTo(iconLabel, { TextTransparency = 0 }, 0.3)
			tweenTo(gameOverLabel, { TextTransparency = 0 }, 0.3)
			task.delay(0.08, function()
				tweenTo(scoreLabel, { TextTransparency = 0 }, 0.3)
				tweenTo(tipsLabel, { TextTransparency = 0 }, 0.3)
				tweenTo(hintLabel, { TextTransparency = 0 }, 0.3)
				if recapLabel.Visible then
					tweenTo(recapLabel, { TextTransparency = 0 }, 0.3)
				end
			end)
			task.delay(0.16, function()
				tweenTo(playAgainButton, { BackgroundTransparency = 0, TextTransparency = 0 }, 0.3)
				tweenTo(continueButton, { BackgroundTransparency = 0, TextTransparency = 0 }, 0.3)
				tweenTo(tavernButton, { BackgroundTransparency = 0, TextTransparency = 0 }, 0.3)
			end)

			if playSfx and SOUND_IDS then
				require(script.Parent.Cue).play(isWin and "win" or "lose", 1.2)
			end

			lastGameOverKey = key
		end
	end

	return {
		gameOverFrame = dim,
		playAgainButton = playAgainButton,
		continueButton = continueButton,
		tavernButton = tavernButton, -- wired in init.client.lua (needs the Menu frame)
		refreshGameOver = refreshGameOver,
	}
end
