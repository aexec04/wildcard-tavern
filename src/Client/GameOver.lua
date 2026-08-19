--[[
	Client/GameOver.lua
	The small "run has ended" panel shown when state.phase == "gameover",
	with its "Play Again" button.

	Extracted out of init.client.lua as part of splitting the client script
	into smaller, per-feature files. Both pieces are needed back in
	init.client.lua: applyTheme() tweens their colors on a theme change, and
	render() toggles gameOverFrame.Visible based on state.phase. The Play
	Again click handler itself is wired from init.client.lua's "Wire up
	buttons" section (it needs RestartRunRemote, which lives there), so
	playAgainButton comes back out too.

	deps fields:
		root          -- Frame, gameOverFrame's parent
		polishPanel    -- function(instance, radius)
		polishButton   -- function(instance, radius)
		addSoftShadow  -- function(instance, radius)

	Returns:
		{
			gameOverFrame = Frame,
			playAgainButton = TextButton,
		}
]]

return function(deps)
	local root = deps.root
	local polishPanel = deps.polishPanel
	local polishButton = deps.polishButton
	local addSoftShadow = deps.addSoftShadow

	local gameOverFrame = Instance.new("Frame")
	gameOverFrame.Name = "GameOver"
	gameOverFrame.Size = UDim2.fromScale(0.5, 0.3)
	gameOverFrame.Position = UDim2.fromScale(0.25, 0.35)
	gameOverFrame.BackgroundColor3 = Color3.fromRGB(40, 30, 22)
	gameOverFrame.Visible = false
	gameOverFrame.Parent = root
	polishPanel(gameOverFrame, 16)
	addSoftShadow(gameOverFrame, 18)

	local gameOverLabel = Instance.new("TextLabel")
	gameOverLabel.Size = UDim2.new(1, 0, 0, 60)
	gameOverLabel.BackgroundTransparency = 1
	gameOverLabel.Font = Enum.Font.GothamBold
	gameOverLabel.TextSize = 22
	gameOverLabel.TextColor3 = Color3.fromRGB(250, 240, 220)
	gameOverLabel.Text = "Last call! Your run has ended."
	gameOverLabel.Parent = gameOverFrame

	local playAgainButton = Instance.new("TextButton")
	playAgainButton.Size = UDim2.new(0, 200, 0, 40)
	playAgainButton.Position = UDim2.new(0.5, -100, 1, -60)
	playAgainButton.Font = Enum.Font.GothamBold
	playAgainButton.TextSize = 18
	playAgainButton.Text = "Play Again"
	playAgainButton.BackgroundColor3 = Color3.fromRGB(90, 60, 30)
	playAgainButton.TextColor3 = Color3.fromRGB(250, 240, 220)
	playAgainButton.Parent = gameOverFrame
	polishButton(playAgainButton, 10)

	return {
		gameOverFrame = gameOverFrame,
		playAgainButton = playAgainButton,
	}
end
