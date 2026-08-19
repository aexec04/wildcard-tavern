--[[
	Client/HowToPlay.lua
	The "How to Play" overlay -- a full-screen backdrop + panel showing a
	grid of icon/caption rule tiles plus one worked scoring example per hand
	type (weakest to strongest), reachable from the main menu's "How to
	Play" button and from the in-game "?" corner button.

	Extracted out of init.client.lua as part of splitting the client script
	into smaller, per-feature files. Fully self-contained: nothing outside
	this module needs anything it builds (both buttons that open it are
	wired from inside), so unlike Shop.lua this module returns an empty
	table -- it's here purely so init.client.lua doesn't have to carry this
	~280-line block inline anymore.

	deps fields:
		screenGui           -- ScreenGui, the panel's ultimate parent (via backdrop)
		polishPanel          -- function(instance, radius)
		polishButton         -- function(instance, radius)
		roundCorner          -- function(instance, radius)
		addSoftShadow        -- function(instance, radius)
		playClickSfx         -- function(volume?)
		RED_SUITS            -- table, suit name -> true for red suits
		RANK_NAMES           -- table, rank number -> display name
		SUIT_SYMBOLS         -- table, suit name -> unicode symbol
		HandEvaluator         -- the Shared/Engine/HandEvaluator module
		Scoring              -- the Shared/Engine/Scoring module
		menuHowToPlayButton  -- TextButton, "How to Play" on the main menu
		helpButton           -- TextButton, the in-game "?" corner button

	Returns: {} (nothing else in the client needs to reach into this overlay)
]]

return function(deps)
	local screenGui = deps.screenGui
	local polishPanel = deps.polishPanel
	local polishButton = deps.polishButton
	local roundCorner = deps.roundCorner
	local addSoftShadow = deps.addSoftShadow
	local playClickSfx = deps.playClickSfx
	local RED_SUITS = deps.RED_SUITS
	local RANK_NAMES = deps.RANK_NAMES
	local SUIT_SYMBOLS = deps.SUIT_SYMBOLS
	local HandEvaluator = deps.HandEvaluator
	local Scoring = deps.Scoring
	local menuHowToPlayButton = deps.menuHowToPlayButton
	local helpButton = deps.helpButton

	local howToPlayBackdrop = Instance.new("Frame")
	howToPlayBackdrop.Name = "HowToPlayBackdrop"
	howToPlayBackdrop.Size = UDim2.fromScale(1, 1)
	howToPlayBackdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	howToPlayBackdrop.BackgroundTransparency = 0.4
	howToPlayBackdrop.Visible = false
	howToPlayBackdrop.ZIndex = 20
	howToPlayBackdrop.Parent = screenGui

	local howToPlayPanel = Instance.new("Frame")
	howToPlayPanel.Size = UDim2.fromScale(0.6, 0.75)
	howToPlayPanel.Position = UDim2.fromScale(0.2, 0.12)
	howToPlayPanel.BackgroundColor3 = Color3.fromRGB(40, 30, 22)
	howToPlayPanel.ZIndex = 21
	howToPlayPanel.Parent = howToPlayBackdrop
	polishPanel(howToPlayPanel, 16)
	addSoftShadow(howToPlayPanel, 18)

	local howToPlayTitle = Instance.new("TextLabel")
	howToPlayTitle.Size = UDim2.new(1, 0, 0, 40)
	howToPlayTitle.BackgroundTransparency = 1
	howToPlayTitle.Font = Enum.Font.GothamBold
	howToPlayTitle.TextSize = 22
	howToPlayTitle.TextColor3 = Color3.fromRGB(250, 240, 220)
	howToPlayTitle.Text = "How to Play"
	howToPlayTitle.ZIndex = 21
	howToPlayTitle.Parent = howToPlayPanel

	-- FEATURE 5: worked examples, scrollable. Built from real Card tables and
	-- run through the actual HandEvaluator + Scoring modules, so the numbers
	-- shown are always exactly what you'd see in a real game.

	local howToPlayScroll = Instance.new("ScrollingFrame")
	howToPlayScroll.Size = UDim2.new(1, -30, 1, -100)
	howToPlayScroll.Position = UDim2.new(0, 15, 0, 45)
	howToPlayScroll.BackgroundTransparency = 1
	howToPlayScroll.BorderSizePixel = 0
	howToPlayScroll.ScrollBarThickness = 8
	howToPlayScroll.CanvasSize = UDim2.new(0, 0, 0, 0) -- grown automatically below
	howToPlayScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	howToPlayScroll.ZIndex = 21
	howToPlayScroll.Parent = howToPlayPanel

	local howToPlayLayout = Instance.new("UIListLayout")
	howToPlayLayout.Padding = UDim.new(0, 14)
	howToPlayLayout.Parent = howToPlayScroll

	-- A grid of icon + short-caption tiles instead of a paragraph -- one glance
	-- per rule, not a page of reading.
	local HOW_TO_PLAY_STEPS = {
		{ icon = "👆", text = "Click cards to select up to 5" },
		{ icon = "▶️", text = "Play Hand to score your best poker hand" },
		{ icon = "🔄", text = "Discard to swap cards -- free, no hand cost" },
		{ icon = "🎯", text = "Reach the target score before hands run out" },
		{ icon = "🍺", text = "Win a round -- spend Tips on Patrons at the Bar" },
		{ icon = "🌙", text = "Survive as many Nights as you can!" },
	}

	local howToPlayStepsGrid = Instance.new("Frame")
	-- AutomaticSize (not a hardcoded pixel height) so the grid always grows to
	-- fit exactly however many rows the tiles need -- a fixed height here was
	-- the bug: it was too short for 3 rows, so the bottom row spilled out and
	-- covered "How scoring works" and the example hands right below it.
	howToPlayStepsGrid.Size = UDim2.new(1, 0, 0, 0)
	howToPlayStepsGrid.AutomaticSize = Enum.AutomaticSize.Y
	howToPlayStepsGrid.BackgroundTransparency = 1
	howToPlayStepsGrid.ZIndex = 21
	howToPlayStepsGrid.LayoutOrder = 1
	howToPlayStepsGrid.Parent = howToPlayScroll

	local howToPlayGridLayout = Instance.new("UIGridLayout")
	howToPlayGridLayout.CellSize = UDim2.new(1 / 3, -6, 0, 96)
	howToPlayGridLayout.CellPadding = UDim2.new(0, 8, 0, 8)
	howToPlayGridLayout.Parent = howToPlayStepsGrid

	for stepIndex, step in ipairs(HOW_TO_PLAY_STEPS) do
		local tile = Instance.new("Frame")
		tile.BackgroundColor3 = Color3.fromRGB(60, 45, 32)
		tile.LayoutOrder = stepIndex
		tile.ZIndex = 21
		tile.Parent = howToPlayStepsGrid
		polishPanel(tile, 10)

		local iconLabel = Instance.new("TextLabel")
		iconLabel.Size = UDim2.new(1, 0, 0, 40)
		iconLabel.Position = UDim2.new(0, 0, 0, 8)
		iconLabel.BackgroundTransparency = 1
		iconLabel.Font = Enum.Font.GothamBold
		iconLabel.TextSize = 28
		iconLabel.Text = step.icon
		iconLabel.ZIndex = 21
		iconLabel.Parent = tile

		local captionLabel = Instance.new("TextLabel")
		captionLabel.Size = UDim2.new(1, -16, 0, 42)
		captionLabel.Position = UDim2.new(0, 8, 0, 50)
		captionLabel.BackgroundTransparency = 1
		captionLabel.Font = Enum.Font.Gotham
		captionLabel.TextSize = 13
		captionLabel.TextColor3 = Color3.fromRGB(235, 225, 210)
		captionLabel.TextWrapped = true
		captionLabel.Text = step.text
		captionLabel.ZIndex = 21
		captionLabel.Parent = tile
	end

	local howToPlayExamplesLabel = Instance.new("TextLabel")
	howToPlayExamplesLabel.Size = UDim2.new(1, 0, 0, 24)
	howToPlayExamplesLabel.BackgroundTransparency = 1
	howToPlayExamplesLabel.Font = Enum.Font.GothamBold
	howToPlayExamplesLabel.TextSize = 15
	howToPlayExamplesLabel.TextColor3 = Color3.fromRGB(255, 214, 130)
	howToPlayExamplesLabel.TextXAlignment = Enum.TextXAlignment.Left
	howToPlayExamplesLabel.Text = "How scoring works -- every hand, weakest to strongest:"
	howToPlayExamplesLabel.ZIndex = 21
	howToPlayExamplesLabel.LayoutOrder = 2
	howToPlayExamplesLabel.Parent = howToPlayScroll

	-- Ahmed: "the Poker Hands [reference] has all ways to score points, why is
	-- that not being visually shown in the how to play?" -- one worked example
	-- per HandEvaluator.HandOrder entry now (was only 3 of 9), weakest to
	-- strongest, same visual mini-card format as before.
	local EXAMPLE_HANDS = {
		{ -- High Card
			{ rank = 2, suit = "Hearts" },
			{ rank = 5, suit = "Diamonds" },
			{ rank = 9, suit = "Clubs" },
			{ rank = 11, suit = "Spades" },
			{ rank = 13, suit = "Hearts" },
		},
		{ -- Pair
			{ rank = 7, suit = "Hearts" },
			{ rank = 7, suit = "Spades" },
		},
		{ -- Two Pair
			{ rank = 9, suit = "Diamonds" },
			{ rank = 9, suit = "Clubs" },
			{ rank = 2, suit = "Hearts" },
			{ rank = 2, suit = "Diamonds" },
		},
		{ -- Three of a Kind
			{ rank = 5, suit = "Spades" },
			{ rank = 5, suit = "Hearts" },
			{ rank = 5, suit = "Diamonds" },
		},
		{ -- Straight
			{ rank = 4, suit = "Hearts" },
			{ rank = 5, suit = "Diamonds" },
			{ rank = 6, suit = "Clubs" },
			{ rank = 7, suit = "Spades" },
			{ rank = 8, suit = "Hearts" },
		},
		{ -- Flush
			{ rank = 2, suit = "Hearts" },
			{ rank = 5, suit = "Hearts" },
			{ rank = 9, suit = "Hearts" },
			{ rank = 11, suit = "Hearts" },
			{ rank = 13, suit = "Hearts" },
		},
		{ -- Full House
			{ rank = 9, suit = "Diamonds" },
			{ rank = 9, suit = "Clubs" },
			{ rank = 9, suit = "Spades" },
			{ rank = 2, suit = "Hearts" },
			{ rank = 2, suit = "Diamonds" },
		},
		{ -- Four of a Kind
			{ rank = 8, suit = "Hearts" },
			{ rank = 8, suit = "Diamonds" },
			{ rank = 8, suit = "Clubs" },
			{ rank = 8, suit = "Spades" },
		},
		{ -- Straight Flush
			{ rank = 4, suit = "Clubs" },
			{ rank = 5, suit = "Clubs" },
			{ rank = 6, suit = "Clubs" },
			{ rank = 7, suit = "Clubs" },
			{ rank = 8, suit = "Clubs" },
		},
	}

	local function makeMiniCard(card, parent, layoutOrder)
		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(0, 34, 0, 46)
		label.BackgroundColor3 = Color3.fromRGB(250, 245, 235)
		label.Font = Enum.Font.GothamBold
		label.TextSize = 13
		label.TextColor3 = RED_SUITS[card.suit] and Color3.fromRGB(180, 30, 30) or Color3.fromRGB(20, 20, 20)
		label.Text = string.format("%s\n%s", RANK_NAMES[card.rank] or tostring(card.rank), SUIT_SYMBOLS[card.suit] or "?")
		label.LayoutOrder = layoutOrder or 0
		label.ZIndex = 21
		label.Parent = parent
		roundCorner(label, 6)
		return label
	end

	for exampleIndex, cards in ipairs(EXAMPLE_HANDS) do
		local handResult = HandEvaluator.evaluate(cards)
		local score, chips, mult = Scoring.calculate(handResult, {}, {})

		local exampleRow = Instance.new("Frame")
		exampleRow.Size = UDim2.new(1, 0, 0, 70)
		exampleRow.BackgroundColor3 = Color3.fromRGB(60, 45, 32)
		exampleRow.ZIndex = 21
		exampleRow.LayoutOrder = 2 + exampleIndex
		exampleRow.Parent = howToPlayScroll
		polishPanel(exampleRow, 10)

		local cardsHolder = Instance.new("Frame")
		cardsHolder.Size = UDim2.new(0, 34 * #cards + 6 * (#cards - 1) + 16, 1, 0)
		cardsHolder.Position = UDim2.new(0, 10, 0, 0)
		cardsHolder.BackgroundTransparency = 1
		cardsHolder.ZIndex = 21
		cardsHolder.Parent = exampleRow

		local cardsLayout = Instance.new("UIListLayout")
		cardsLayout.FillDirection = Enum.FillDirection.Horizontal
		cardsLayout.VerticalAlignment = Enum.VerticalAlignment.Center
		cardsLayout.Padding = UDim.new(0, 6)
		cardsLayout.Parent = cardsHolder

		for cardIndex, card in ipairs(cards) do
			makeMiniCard(card, cardsHolder, cardIndex)
		end

		local resultLabel = Instance.new("TextLabel")
		resultLabel.Size = UDim2.new(1, -(34 * #cards + 6 * (#cards - 1) + 30), 1, 0)
		resultLabel.Position = UDim2.new(0, 34 * #cards + 6 * (#cards - 1) + 20, 0, 0)
		resultLabel.BackgroundTransparency = 1
		resultLabel.Font = Enum.Font.Gotham
		resultLabel.TextSize = 14
		resultLabel.TextWrapped = true
		resultLabel.TextXAlignment = Enum.TextXAlignment.Left
		resultLabel.TextColor3 = Color3.fromRGB(255, 214, 130)
		resultLabel.ZIndex = 21
		resultLabel.Text = string.format(
			"%s\n%d chips x %d mult = %d points",
			handResult.name, chips, mult, score
		)
		resultLabel.Parent = exampleRow
	end

	local howToPlayCloseButton = Instance.new("TextButton")
	howToPlayCloseButton.Size = UDim2.new(0, 140, 0, 40)
	howToPlayCloseButton.Position = UDim2.new(0.5, -70, 1, -50)
	howToPlayCloseButton.Font = Enum.Font.GothamBold
	howToPlayCloseButton.TextSize = 16
	howToPlayCloseButton.Text = "Got it"
	howToPlayCloseButton.BackgroundColor3 = Color3.fromRGB(90, 60, 30)
	howToPlayCloseButton.TextColor3 = Color3.fromRGB(250, 240, 220)
	howToPlayCloseButton.ZIndex = 21
	howToPlayCloseButton.Parent = howToPlayPanel
	polishButton(howToPlayCloseButton, 10)

	howToPlayCloseButton.MouseButton1Click:Connect(function()
		playClickSfx()
		howToPlayBackdrop.Visible = false
	end)

	local function openHowToPlay()
		playClickSfx()
		howToPlayBackdrop.Visible = true
	end

	menuHowToPlayButton.MouseButton1Click:Connect(openHowToPlay)
	helpButton.MouseButton1Click:Connect(openHowToPlay)

	return {}
end
