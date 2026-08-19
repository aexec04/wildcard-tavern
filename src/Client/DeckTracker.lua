--[[
	Client/DeckTracker.lua
	FEATURE 7: shows exactly how many of each card are still left to be
	drawn this round -- reads directly off the server-computed
	Deck.remainingCounts snapshot already included in the state payload.
	Reachable by clicking the blue deck-remaining widget, bottom-right.

	Extracted out of init.client.lua as part of splitting the client script
	into smaller, per-feature files. Like PokerHandsReference.lua, the
	refresh function used to live in a totally different part of the file
	purely to dodge Lua's 200-local-per-function ceiling; as its own module
	it lives right next to the panel it updates instead.

	Fully self-contained -- nothing outside this module needs anything it
	builds, so it returns an empty table.

	deps fields:
		screenGui        -- ScreenGui, the panel's ultimate parent (via backdrop)
		polishPanel       -- function(instance, radius)
		polishButton      -- function(instance, radius)
		roundCorner       -- function(instance, radius)
		addSoftShadow     -- function(instance, radius)
		playClickSfx      -- function(volume?)
		deckWidgetButton  -- TextButton, the click-catcher over the bottom-right
		                     deck widget (built earlier in init.client.lua)
		Deck              -- the Shared/Engine/Deck module (for Deck.RankOrder)
		RANK_NAMES        -- table, rank number -> display name
		SUIT_SYMBOLS      -- table, suit name -> unicode symbol
		SUIT_DISPLAY_ORDER -- array, suit display order (Spades/Hearts/Clubs/Diamonds)
		RED_SUITS         -- table, suit name -> true for red suits
		getLatestState    -- function() -> latest state table or nil (live getter)

	Returns: {}
]]

return function(deps)
	local screenGui = deps.screenGui
	local polishPanel = deps.polishPanel
	local polishButton = deps.polishButton
	local roundCorner = deps.roundCorner
	local addSoftShadow = deps.addSoftShadow
	local playClickSfx = deps.playClickSfx
	local deckWidgetButton = deps.deckWidgetButton
	local Deck = deps.Deck
	local RANK_NAMES = deps.RANK_NAMES
	local SUIT_SYMBOLS = deps.SUIT_SYMBOLS
	local SUIT_DISPLAY_ORDER = deps.SUIT_DISPLAY_ORDER
	local RED_SUITS = deps.RED_SUITS
	local getLatestState = deps.getLatestState

	local deckTrackerBackdrop = Instance.new("Frame")
	deckTrackerBackdrop.Name = "DeckTrackerBackdrop"
	deckTrackerBackdrop.Size = UDim2.fromScale(1, 1)
	deckTrackerBackdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	deckTrackerBackdrop.BackgroundTransparency = 0.4
	deckTrackerBackdrop.Visible = false
	deckTrackerBackdrop.ZIndex = 20
	deckTrackerBackdrop.Parent = screenGui

	local deckTrackerPanel = Instance.new("Frame")
	deckTrackerPanel.Size = UDim2.fromScale(0.72, 0.5)
	deckTrackerPanel.Position = UDim2.fromScale(0.14, 0.24)
	deckTrackerPanel.BackgroundColor3 = Color3.fromRGB(40, 30, 22)
	deckTrackerPanel.ZIndex = 21
	deckTrackerPanel.Parent = deckTrackerBackdrop
	polishPanel(deckTrackerPanel, 16)
	addSoftShadow(deckTrackerPanel, 18)

	local deckTrackerTitle = Instance.new("TextLabel")
	deckTrackerTitle.Size = UDim2.new(1, 0, 0, 40)
	deckTrackerTitle.BackgroundTransparency = 1
	deckTrackerTitle.Font = Enum.Font.GothamBold
	deckTrackerTitle.TextSize = 22
	deckTrackerTitle.TextColor3 = Color3.fromRGB(250, 240, 220)
	deckTrackerTitle.Text = "What's Left in the Deck"
	deckTrackerTitle.ZIndex = 21
	deckTrackerTitle.Parent = deckTrackerPanel

	local deckTrackerGrid = Instance.new("Frame")
	deckTrackerGrid.Size = UDim2.new(1, -30, 1, -110)
	deckTrackerGrid.Position = UDim2.new(0, 15, 0, 45)
	deckTrackerGrid.BackgroundTransparency = 1
	deckTrackerGrid.ZIndex = 21
	deckTrackerGrid.Parent = deckTrackerPanel

	local deckTrackerGridLayout = Instance.new("UIListLayout")
	deckTrackerGridLayout.Padding = UDim.new(0, 4)
	deckTrackerGridLayout.Parent = deckTrackerGrid

	local deckTrackerCloseButton = Instance.new("TextButton")
	deckTrackerCloseButton.Size = UDim2.new(0, 140, 0, 40)
	deckTrackerCloseButton.Position = UDim2.new(0.5, -70, 1, -50)
	deckTrackerCloseButton.Font = Enum.Font.GothamBold
	deckTrackerCloseButton.TextSize = 16
	deckTrackerCloseButton.Text = "Close"
	deckTrackerCloseButton.BackgroundColor3 = Color3.fromRGB(90, 60, 30)
	deckTrackerCloseButton.TextColor3 = Color3.fromRGB(250, 240, 220)
	deckTrackerCloseButton.ZIndex = 21
	deckTrackerCloseButton.Parent = deckTrackerPanel
	polishButton(deckTrackerCloseButton, 12)

	deckTrackerCloseButton.MouseButton1Click:Connect(function()
		playClickSfx()
		deckTrackerBackdrop.Visible = false
	end)

	local function refreshDeckTracker()
		local function makeDeckTrackerCell(parent, text, widthScale, isHeader, textColor)
			local cell = Instance.new("TextLabel")
			cell.Size = UDim2.new(widthScale, 0, 1, 0)
			cell.BackgroundTransparency = 1
			cell.Font = isHeader and Enum.Font.GothamBold or Enum.Font.Gotham
			cell.TextSize = 13
			cell.TextColor3 = textColor or Color3.fromRGB(230, 220, 205)
			cell.Text = text
			cell.ZIndex = 21
			cell.Parent = parent
			return cell
		end

		for _, child in ipairs(deckTrackerGrid:GetChildren()) do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end

		local latestState = getLatestState()
		local deckCounts = latestState and latestState.deckCounts
		local cellWidth = 1 / (#Deck.RankOrder + 1)

		local headerRow = Instance.new("Frame")
		headerRow.Size = UDim2.new(1, 0, 0, 24)
		headerRow.BackgroundTransparency = 1
		headerRow.ZIndex = 21
		headerRow.Parent = deckTrackerGrid
		local headerLayout = Instance.new("UIListLayout")
		headerLayout.FillDirection = Enum.FillDirection.Horizontal
		headerLayout.Parent = headerRow
		makeDeckTrackerCell(headerRow, "", cellWidth, true)
		for _, rank in ipairs(Deck.RankOrder) do
			makeDeckTrackerCell(headerRow, RANK_NAMES[rank], cellWidth, true, Color3.fromRGB(200, 185, 165))
		end

		for _, suit in ipairs(SUIT_DISPLAY_ORDER) do
			local suitRow = Instance.new("Frame")
			suitRow.Size = UDim2.new(1, 0, 0, 26)
			suitRow.BackgroundColor3 = Color3.fromRGB(50, 38, 28)
			suitRow.ZIndex = 21
			suitRow.Parent = deckTrackerGrid
			roundCorner(suitRow, 6)
			local suitLayout = Instance.new("UIListLayout")
			suitLayout.FillDirection = Enum.FillDirection.Horizontal
			suitLayout.Parent = suitRow

			local suitColor = RED_SUITS[suit] and Color3.fromRGB(230, 140, 140) or Color3.fromRGB(220, 220, 230)
			makeDeckTrackerCell(suitRow, SUIT_SYMBOLS[suit], cellWidth, true, suitColor)
			for _, rank in ipairs(Deck.RankOrder) do
				local count = (deckCounts and deckCounts[suit] and deckCounts[suit][rank]) or 0
				local cellColor = count > 0 and Color3.fromRGB(230, 220, 205) or Color3.fromRGB(110, 100, 90)
				makeDeckTrackerCell(suitRow, tostring(count), cellWidth, false, cellColor)
			end
		end
	end

	deckWidgetButton.MouseButton1Click:Connect(function()
		playClickSfx()
		refreshDeckTracker()
		deckTrackerBackdrop.Visible = true
	end)

	return {}
end
