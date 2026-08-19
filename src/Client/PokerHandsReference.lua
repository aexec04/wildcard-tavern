--[[
	Client/PokerHandsReference.lua
	FEATURE 6: a live lookup table -- every hand type this game recognizes,
	its base chips/mult (straight from Scoring.HandBase, so it can't drift
	out of sync with actual balance), and how many times you've played it
	this run. Reachable from the in-game "📖" corner button only.

	Extracted out of init.client.lua as part of splitting the client script
	into smaller, per-feature files. In the original monolith this overlay's
	refresh function had to be defined in a totally different part of the
	file (with the panel/list frame forward-declared as top-level locals to
	bridge the gap) purely to dodge Lua's 200-local-per-function ceiling --
	seeing that gap was what originally made "opening Poker Hands reference
	does nothing" a real bug once before. As its own module this doesn't
	come up: the refresh function lives right next to the panel it updates.

	Fully self-contained -- nothing outside this module needs anything it
	builds, so it returns an empty table.

	deps fields:
		screenGui       -- ScreenGui, the panel's ultimate parent (via backdrop)
		polishPanel      -- function(instance, radius)
		polishButton     -- function(instance, radius)
		addSoftShadow    -- function(instance, radius)
		playClickSfx     -- function(volume?)
		handRefButton    -- TextButton, the in-game "📖" corner button
		HandEvaluator    -- the Shared/Engine/HandEvaluator module
		Scoring          -- the Shared/Engine/Scoring module
		getLatestState   -- function() -> latest state table or nil (live getter)

	Returns: {}
]]

return function(deps)
	local screenGui = deps.screenGui
	local polishPanel = deps.polishPanel
	local polishButton = deps.polishButton
	local addSoftShadow = deps.addSoftShadow
	local playClickSfx = deps.playClickSfx
	local handRefButton = deps.handRefButton
	local HandEvaluator = deps.HandEvaluator
	local Scoring = deps.Scoring
	local getLatestState = deps.getLatestState

	local handRefBackdrop = Instance.new("Frame")
	handRefBackdrop.Name = "HandRefBackdrop"
	handRefBackdrop.Size = UDim2.fromScale(1, 1)
	handRefBackdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	handRefBackdrop.BackgroundTransparency = 0.4
	handRefBackdrop.Visible = false
	handRefBackdrop.ZIndex = 20
	handRefBackdrop.Parent = screenGui

	local handRefPanel = Instance.new("Frame")
	handRefPanel.Size = UDim2.fromScale(0.5, 0.65)
	handRefPanel.Position = UDim2.fromScale(0.25, 0.17)
	handRefPanel.BackgroundColor3 = Color3.fromRGB(40, 30, 22)
	handRefPanel.ZIndex = 21
	handRefPanel.Parent = handRefBackdrop
	polishPanel(handRefPanel, 16)
	addSoftShadow(handRefPanel, 18)

	local handRefTitle = Instance.new("TextLabel")
	handRefTitle.Size = UDim2.new(1, 0, 0, 40)
	handRefTitle.BackgroundTransparency = 1
	handRefTitle.Font = Enum.Font.GothamBold
	handRefTitle.TextSize = 22
	handRefTitle.TextColor3 = Color3.fromRGB(250, 240, 220)
	handRefTitle.Text = "Poker Hands"
	handRefTitle.ZIndex = 21
	handRefTitle.Parent = handRefPanel

	local handRefHeaderRow = Instance.new("Frame")
	handRefHeaderRow.Size = UDim2.new(1, -30, 0, 22)
	handRefHeaderRow.Position = UDim2.new(0, 15, 0, 42)
	handRefHeaderRow.BackgroundTransparency = 1
	handRefHeaderRow.ZIndex = 21
	handRefHeaderRow.Parent = handRefPanel

	local function makeHandRefHeaderLabel(text, xScale, widthScale, alignment)
		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(widthScale, 0, 1, 0)
		label.Position = UDim2.new(xScale, 0, 0, 0)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamBold
		label.TextSize = 13
		label.TextColor3 = Color3.fromRGB(200, 185, 165)
		label.TextXAlignment = alignment or Enum.TextXAlignment.Left
		label.Text = text
		label.ZIndex = 21
		label.Parent = handRefHeaderRow
		return label
	end

	makeHandRefHeaderLabel("Hand", 0, 0.4)
	makeHandRefHeaderLabel("Chips x Mult", 0.4, 0.35)
	makeHandRefHeaderLabel("Played", 0.78, 0.22, Enum.TextXAlignment.Right)

	local handRefListFrame = Instance.new("ScrollingFrame")
	handRefListFrame.Size = UDim2.new(1, -20, 1, -145)
	handRefListFrame.Position = UDim2.new(0, 10, 0, 68)
	handRefListFrame.BackgroundTransparency = 1
	handRefListFrame.BorderSizePixel = 0
	handRefListFrame.ScrollBarThickness = 8
	handRefListFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	handRefListFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
	handRefListFrame.ZIndex = 21
	handRefListFrame.Parent = handRefPanel

	local handRefListLayout = Instance.new("UIListLayout")
	handRefListLayout.Padding = UDim.new(0, 6)
	handRefListLayout.Parent = handRefListFrame

	local handRefCloseButton = Instance.new("TextButton")
	handRefCloseButton.Size = UDim2.new(0, 140, 0, 40)
	handRefCloseButton.Position = UDim2.new(0.5, -70, 1, -50)
	handRefCloseButton.Font = Enum.Font.GothamBold
	handRefCloseButton.TextSize = 16
	handRefCloseButton.Text = "Close"
	handRefCloseButton.BackgroundColor3 = Color3.fromRGB(90, 60, 30)
	handRefCloseButton.TextColor3 = Color3.fromRGB(250, 240, 220)
	handRefCloseButton.ZIndex = 21
	handRefCloseButton.Parent = handRefPanel
	polishButton(handRefCloseButton, 12)

	handRefCloseButton.MouseButton1Click:Connect(function()
		playClickSfx()
		handRefBackdrop.Visible = false
	end)

	local function refreshHandReference()
		for _, child in ipairs(handRefListFrame:GetChildren()) do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end

		local latestState = getLatestState()
		local handStats = (latestState and latestState.handStats) or {}

		-- Strongest hand first, matching how most poker reference charts read.
		for i = #HandEvaluator.HandOrder, 1, -1 do
			local handName = HandEvaluator.HandOrder[i]
			local base = Scoring.HandBase[handName]

			local row = Instance.new("Frame")
			row.Size = UDim2.new(1, 0, 0, 34)
			row.BackgroundColor3 = Color3.fromRGB(60, 45, 32)
			row.ZIndex = 21
			row.Parent = handRefListFrame
			polishPanel(row, 8)

			local nameLabel = Instance.new("TextLabel")
			nameLabel.Size = UDim2.new(0.4, 0, 1, 0)
			nameLabel.Position = UDim2.new(0, 10, 0, 0)
			nameLabel.BackgroundTransparency = 1
			nameLabel.Font = Enum.Font.Gotham
			nameLabel.TextSize = 14
			nameLabel.TextXAlignment = Enum.TextXAlignment.Left
			nameLabel.TextColor3 = Color3.fromRGB(250, 240, 220)
			nameLabel.Text = handName
			nameLabel.ZIndex = 21
			nameLabel.Parent = row

			local valueLabel = Instance.new("TextLabel")
			valueLabel.Size = UDim2.new(0.35, 0, 1, 0)
			valueLabel.Position = UDim2.new(0.4, 0, 0, 0)
			valueLabel.BackgroundTransparency = 1
			valueLabel.Font = Enum.Font.Gotham
			valueLabel.TextSize = 14
			valueLabel.TextXAlignment = Enum.TextXAlignment.Left
			valueLabel.TextColor3 = Color3.fromRGB(255, 214, 130)
			valueLabel.Text = string.format("%d x %d", base.chips, base.mult)
			valueLabel.ZIndex = 21
			valueLabel.Parent = row

			local playedLabel = Instance.new("TextLabel")
			playedLabel.Size = UDim2.new(0.2, -10, 1, 0)
			playedLabel.Position = UDim2.new(0.8, 0, 0, 0)
			playedLabel.BackgroundTransparency = 1
			playedLabel.Font = Enum.Font.GothamBold
			playedLabel.TextSize = 14
			playedLabel.TextXAlignment = Enum.TextXAlignment.Right
			playedLabel.TextColor3 = Color3.fromRGB(200, 220, 200)
			playedLabel.Text = tostring(handStats[handName] or 0)
			playedLabel.ZIndex = 21
			playedLabel.Parent = row
		end
	end

	handRefButton.MouseButton1Click:Connect(function()
		playClickSfx()
		refreshHandReference()
		handRefBackdrop.Visible = true
	end)

	return {}
end
