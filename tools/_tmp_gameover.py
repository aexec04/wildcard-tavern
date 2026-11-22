p = 'src/Client/GameOver.lua'
s = open(p).read()


def rep(old, new, count=1):
    global s
    assert old in s, old[:60]
    s = s.replace(old, new, count)


rep('''	local gameOverFrame = Instance.new("Frame")
	gameOverFrame.Name = "GameOver"
	gameOverFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	gameOverFrame.Size = UDim2.fromScale(0.46, 0.42)
	gameOverFrame.Position = UDim2.fromScale(0.5, 0.5)
	gameOverFrame.BackgroundColor3 = Color3.fromRGB(40, 30, 22)
	gameOverFrame.ClipsDescendants = true
	gameOverFrame.Visible = false
	gameOverFrame.Parent = root
	polishPanel(gameOverFrame, 16, "wood")
''', '''	-- dim is the full-screen even dark dim (hides the table so no cards peek out) and sinks clicks; the wood panel
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
''')

a = s.index('	-- POLISH: a thin color-coded strip')
b = s.index('	-- ART (placeholder-safe')
s = s[:a] + s[b:]
rep('			accentBar.BackgroundColor3 = WIN_COLOR\n', '')
rep('			accentBar.BackgroundColor3 = LOSS_COLOR\n', '')
rep('''	local WIN_COLOR = Color3.fromRGB(230, 190, 90)
	local LOSS_COLOR = Color3.fromRGB(177, 84, 79)

''', '')

rep('''	gameOverLabel.Size = UDim2.new(1, -40, 0, 34)
	gameOverLabel.Position = UDim2.new(0, 20, 0, 76)''', '''	gameOverLabel.Size = UDim2.new(1, -40, 0, 68)
	gameOverLabel.Position = UDim2.new(0, 20, 0, 74)''')
rep('gameOverLabel.TextSize = 21', 'gameOverLabel.TextSize = 28')

a = s.index('	local statsLabel = Instance.new("TextLabel")')
b = s.index('	-- PHASE A (Spectacle pass')
s = s[:a] + '''	local function statRow(name, y)
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

''' + s[b:]
rep('''	recapLabel.Size = UDim2.new(1, -60, 0, 22)
	recapLabel.Position = UDim2.new(0, 30, 0, 168)''', '''	recapLabel.Size = UDim2.new(1, -80, 0, 24)
	recapLabel.Position = UDim2.new(0, 40, 0, 240)''')
rep('recapLabel.TextSize = 14', 'recapLabel.TextSize = 18')

rep('''	local playAgainButton = Instance.new("TextButton")
	playAgainButton.Size = UDim2.new(0, 200, 0, 40)
	playAgainButton.Position = UDim2.new(0.5, -100, 1, -60)''', '''	local hintLabel = Instance.new("TextLabel")
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
	playAgainButton.Position = UDim2.new(0.5, -230, 1, -70)''')
rep('''	playAgainButton.TextSize = 18
	playAgainButton.Text = "Play Again"
	playAgainButton.BackgroundColor3 = Color3.fromRGB(90, 60, 30)
	playAgainButton.TextColor3 = Color3.fromRGB(250, 240, 220)''', '''	playAgainButton.TextSize = 20
	playAgainButton.Text = "Play Again"
	playAgainButton.BackgroundColor3 = Color3.fromRGB(196, 150, 60)
	playAgainButton.TextColor3 = Color3.fromRGB(40, 28, 14)''')
rep('''	continueButton.Size = UDim2.new(0, 200, 0, 40)
	continueButton.Position = UDim2.new(0.5, 10, 1, -60)
	continueButton.Font = Enum.Font.GothamBold
	continueButton.TextSize = 16''', '''	continueButton.Size = UDim2.new(0, 220, 0, 48)
	continueButton.Position = UDim2.new(0.5, -110, 1, -130)
	continueButton.Font = Enum.Font.GothamBold
	continueButton.TextSize = 20''')
rep('''	local revivedBadge =''', '''	local tavernButton = Instance.new("TextButton")
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
	-- Like Settings > Main Menu: shows the Menu and sends nothing to the server.
	tavernButton.MouseButton1Click:Connect(function()
		if deps.playClickSfx then deps.playClickSfx() end
		if deps.root then deps.root.Visible = false end
		if deps.menuFrame then deps.menuFrame.Visible = true end
	end)

	local revivedBadge =''')

a = s.index('		playAgainButton.Position = canContinue')
b = s.index('\n', a)
s = s[:a] + '''		-- Play Again (gold, primary) left, Back to Tavern right; One More Round sits above them when offered.''' + s[b:]

a = s.index('		statsLabel.Text = string.format(')
b = s.index('\n\n', a)
s = s[:a] + '''		scoreLabel.Text = string.format("Final score: %d / %d", math.floor(state.roundScore or 0), math.floor(state.targetScore or 0))
		tipsLabel.Text = string.format("Tips banked: %d", math.floor(state.tips or 0))
		local hint = (not isWin) and GameOverTips.pick(state.night, state.round) or nil
		hintLabel.Visible = hint ~= nil
		hintLabel.Text = hint and ("Tip: " .. hint) or ""''' + s[b:]
rep('			statsLabel.TextTransparency = 1\n', '			scoreLabel.TextTransparency = 1\n			tipsLabel.TextTransparency = 1\n			hintLabel.TextTransparency = 1\n			tavernButton.BackgroundTransparency = 1\n			tavernButton.TextTransparency = 1\n')
rep('				tweenTo(statsLabel, { TextTransparency = 0 }, 0.3)\n', '				tweenTo(scoreLabel, { TextTransparency = 0 }, 0.3)\n				tweenTo(tipsLabel, { TextTransparency = 0 }, 0.3)\n				tweenTo(hintLabel, { TextTransparency = 0 }, 0.3)\n')
rep('				tweenTo(continueButton, { BackgroundTransparency = 0, TextTransparency = 0 }, 0.3)\n', '				tweenTo(continueButton, { BackgroundTransparency = 0, TextTransparency = 0 }, 0.3)\n				tweenTo(tavernButton, { BackgroundTransparency = 0, TextTransparency = 0 }, 0.3)\n')
rep('''	local root = deps.root
''', '''	local root = deps.root
	local GameOverTips = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("GameOverTips"))
''')
rep('		gameOverFrame = gameOverFrame,', '		gameOverFrame = dim,')
open(p, 'w').write(s)
