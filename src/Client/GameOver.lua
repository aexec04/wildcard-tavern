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

	Returns:
		{
			gameOverFrame = Frame,
			playAgainButton = TextButton,
			refreshGameOver = function(state),
		}
]]

return function(deps)
	local root = deps.root
	local polishPanel = deps.polishPanel
	local polishButton = deps.polishButton
	local addSoftShadow = deps.addSoftShadow
	local tweenTo = deps.tweenTo

	local gameOverFrame = Instance.new("Frame")
	gameOverFrame.Name = "GameOver"
	gameOverFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	gameOverFrame.Size = UDim2.fromScale(0.46, 0.42)
	gameOverFrame.Position = UDim2.fromScale(0.5, 0.5)
	gameOverFrame.BackgroundColor3 = Color3.fromRGB(40, 30, 22)
	gameOverFrame.ClipsDescendants = true
	gameOverFrame.Visible = false
	gameOverFrame.Parent = root
	polishPanel(gameOverFrame, 16)
	addSoftShadow(gameOverFrame, 18)

	-- POLISH: a thin color-coded strip along the top -- gold for a win,
	-- warm ember-red for a loss -- recolored in refreshGameOver below.
	-- Cheap, high-signal "how did this run go" cue readable before the
	-- player even reads a word of text.
	local accentBar = Instance.new("Frame")
	accentBar.Name = "AccentBar"
	accentBar.Size = UDim2.new(1, 0, 0, 6)
	accentBar.BackgroundColor3 = Color3.fromRGB(177, 84, 79)
	accentBar.BorderSizePixel = 0
	accentBar.ZIndex = 21
	accentBar.Parent = gameOverFrame

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
	gameOverLabel.Size = UDim2.new(1, -40, 0, 34)
	gameOverLabel.Position = UDim2.new(0, 20, 0, 76)
	gameOverLabel.BackgroundTransparency = 1
	gameOverLabel.Font = Enum.Font.GothamBold
	gameOverLabel.TextSize = 21
	gameOverLabel.TextWrapped = true
	gameOverLabel.TextColor3 = Color3.fromRGB(250, 240, 220)
	gameOverLabel.Text = "Last call! Your run has ended."
	gameOverLabel.ZIndex = 22
	gameOverLabel.Parent = content

	-- Final Score / Night reached / Tips banked -- previously this panel
	-- showed no stats at all once the run ended, just the one static
	-- sentence (and, thanks to the bug above, not even the dynamic part of
	-- THAT sentence).
	local statsLabel = Instance.new("TextLabel")
	statsLabel.Size = UDim2.new(1, -60, 0, 70)
	statsLabel.Position = UDim2.new(0, 30, 0, 118)
	statsLabel.BackgroundTransparency = 1
	statsLabel.Font = Enum.Font.Gotham
	statsLabel.TextSize = 15
	statsLabel.TextWrapped = true
	statsLabel.TextColor3 = Color3.fromRGB(220, 205, 185)
	statsLabel.Text = ""
	statsLabel.ZIndex = 22
	statsLabel.Parent = content

	local playAgainButton = Instance.new("TextButton")
	playAgainButton.Size = UDim2.new(0, 200, 0, 40)
	playAgainButton.Position = UDim2.new(0.5, -100, 1, -60)
	playAgainButton.Font = Enum.Font.GothamBold
	playAgainButton.TextSize = 18
	playAgainButton.Text = "Play Again"
	playAgainButton.BackgroundColor3 = Color3.fromRGB(90, 60, 30)
	playAgainButton.TextColor3 = Color3.fromRGB(250, 240, 220)
	playAgainButton.ZIndex = 22
	playAgainButton.Parent = content
	polishButton(playAgainButton, 10)

	local WIN_COLOR = Color3.fromRGB(230, 190, 90)
	local LOSS_COLOR = Color3.fromRGB(177, 84, 79)

	-- Only replays the pop-in/fade reveal when this is genuinely a NEW
	-- run-ending state (a fresh loss, or the run flipping from ongoing to
	-- won) -- not on every subsequent state push while the player is just
	-- sitting on this screen deciding whether to hit Play Again (render()
	-- fires on any state change, and other players' actions in a
	-- multiplayer session could still push a state update here). Same
	-- "only trust a change in this key" pattern Journey.lua/RoundSelect.lua
	-- already use for their own animations/confirmations.
	local lastGameOverKey = nil

	local function refreshGameOver(state)
		if not state then
			return
		end

		local isWin = state.wonRun == true
		if isWin then
			accentBar.BackgroundColor3 = WIN_COLOR
			iconLabel.Text = "🏆"
			gameOverLabel.Text = "Last call -- but what a night! You beat the tavern."
		else
			accentBar.BackgroundColor3 = LOSS_COLOR
			iconLabel.Text = "🕯️"
			gameOverLabel.Text = string.format(
				"Last call! You made it to Night %d, Round %d.",
				state.night, state.round
			)
		end

		statsLabel.Text = string.format(
			"Final Score: %d / %d\nTips banked: %d",
			state.roundScore or 0, state.targetScore or 0, state.tips or 0
		)

		local key = tostring(state.night) .. "-" .. tostring(state.round) .. "-" .. tostring(isWin)
		if key ~= lastGameOverKey then
			-- POLISH: pop-in reveal -- content starts slightly shrunk and
			-- fully transparent, tweens up to full scale/opacity. UIScale
			-- (not a Size tween) so every child scales together from one
			-- shared center instead of each element needing its own tween.
			contentScale.Scale = 0.82
			iconLabel.TextTransparency = 1
			gameOverLabel.TextTransparency = 1
			statsLabel.TextTransparency = 1
			playAgainButton.BackgroundTransparency = 1
			playAgainButton.TextTransparency = 1

			tweenTo(contentScale, { Scale = 1 }, 0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
			tweenTo(iconLabel, { TextTransparency = 0 }, 0.3)
			tweenTo(gameOverLabel, { TextTransparency = 0 }, 0.3)
			task.delay(0.08, function()
				tweenTo(statsLabel, { TextTransparency = 0 }, 0.3)
			end)
			task.delay(0.16, function()
				tweenTo(playAgainButton, { BackgroundTransparency = 0, TextTransparency = 0 }, 0.3)
			end)

			lastGameOverKey = key
		end
	end

	return {
		gameOverFrame = gameOverFrame,
		playAgainButton = playAgainButton,
		refreshGameOver = refreshGameOver,
	}
end
