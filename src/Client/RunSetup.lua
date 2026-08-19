--[[
	Client/RunSetup.lua
	FEATURE 8: pick a Deck Variant + Difficulty before a new run begins,
	reachable from the main menu's "New Run..." button.

	Extracted out of init.client.lua as part of splitting the client script
	into smaller, per-feature files. Fully self-contained -- nothing outside
	this module needs anything it builds, so it returns an empty table.

	deps fields:
		screenGui         -- ScreenGui, the panel's ultimate parent (via backdrop)
		root              -- Frame, the main gameplay root (shown once a run starts)
		menuFrame         -- Frame, the main menu (hidden once a run starts)
		polishPanel        -- function(instance, radius)
		polishButton       -- function(instance, radius)
		roundCorner        -- function(instance, radius)
		addSoftShadow      -- function(instance, radius)
		playClickSfx       -- function(volume?)
		playSfx            -- function(soundId, volume?, maxLength?)
		SOUND_IDS          -- table, for SOUND_IDS.buyPatron
		DeckVariants       -- the Shared/Engine/DeckVariants module
		DifficultyTiers    -- the Shared/Engine/DifficultyTiers module
		StartRunRemote     -- RemoteEvent
		backgroundMusic    -- Sound instance, started once a run begins
		menuNewRunButton   -- TextButton, "New Run..." on the main menu

	Returns: {}
]]

return function(deps)
	local screenGui = deps.screenGui
	local root = deps.root
	local menuFrame = deps.menuFrame
	local polishPanel = deps.polishPanel
	local polishButton = deps.polishButton
	local roundCorner = deps.roundCorner
	local addSoftShadow = deps.addSoftShadow
	local playClickSfx = deps.playClickSfx
	local playSfx = deps.playSfx
	local SOUND_IDS = deps.SOUND_IDS
	local DeckVariants = deps.DeckVariants
	local DifficultyTiers = deps.DifficultyTiers
	local StartRunRemote = deps.StartRunRemote
	local backgroundMusic = deps.backgroundMusic
	local menuNewRunButton = deps.menuNewRunButton

	local runSetupBackdrop = Instance.new("Frame")
	runSetupBackdrop.Name = "RunSetupBackdrop"
	runSetupBackdrop.Size = UDim2.fromScale(1, 1)
	runSetupBackdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	runSetupBackdrop.BackgroundTransparency = 0.4
	runSetupBackdrop.Visible = false
	runSetupBackdrop.ZIndex = 25 -- above the in-game overlays; it's reachable from the menu too
	runSetupBackdrop.Parent = screenGui

	local runSetupPanel = Instance.new("Frame")
	runSetupPanel.Size = UDim2.fromScale(0.6, 0.72)
	runSetupPanel.Position = UDim2.fromScale(0.2, 0.13)
	runSetupPanel.BackgroundColor3 = Color3.fromRGB(40, 30, 22)
	runSetupPanel.ZIndex = 26
	runSetupPanel.Parent = runSetupBackdrop
	polishPanel(runSetupPanel, 16)
	addSoftShadow(runSetupPanel, 18)

	local runSetupTitle = Instance.new("TextLabel")
	runSetupTitle.Size = UDim2.new(1, 0, 0, 40)
	runSetupTitle.BackgroundTransparency = 1
	runSetupTitle.Font = Enum.Font.GothamBold
	runSetupTitle.TextSize = 22
	runSetupTitle.TextColor3 = Color3.fromRGB(250, 240, 220)
	runSetupTitle.Text = "Start a New Run"
	runSetupTitle.ZIndex = 26
	runSetupTitle.Parent = runSetupPanel

	local runSetupScroll = Instance.new("ScrollingFrame")
	runSetupScroll.Size = UDim2.new(1, -30, 1, -110)
	runSetupScroll.Position = UDim2.new(0, 15, 0, 45)
	runSetupScroll.BackgroundTransparency = 1
	runSetupScroll.BorderSizePixel = 0
	runSetupScroll.ScrollBarThickness = 8
	runSetupScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	runSetupScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	runSetupScroll.ZIndex = 26
	runSetupScroll.Parent = runSetupPanel

	local runSetupLayout = Instance.new("UIListLayout")
	runSetupLayout.Padding = UDim.new(0, 14)
	runSetupLayout.Parent = runSetupScroll

	-- accentColor: a whole colored bar (not just tinted text) so "which
	-- section am I in" is answerable at a glance while scrolling, even before
	-- reading the word -- Deck Variant is gold, Difficulty is crimson, and
	-- every card below carries a matching accent stripe (see makePickCard).
	local function makeRunSetupSectionLabel(text, icon, order, accentColor)
		local header = Instance.new("Frame")
		header.Size = UDim2.new(1, 0, 0, 32)
		header.BackgroundColor3 = accentColor
		header.BackgroundTransparency = 0.75
		header.LayoutOrder = order
		header.ZIndex = 26
		header.Parent = runSetupScroll
		polishPanel(header, 8)

		local stripe = Instance.new("Frame")
		stripe.Size = UDim2.new(0, 4, 1, -10)
		stripe.Position = UDim2.new(0, 0, 0, 5)
		stripe.BackgroundColor3 = accentColor
		stripe.BorderSizePixel = 0
		stripe.ZIndex = 27
		stripe.Parent = header
		roundCorner(stripe, 2)

		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(1, -20, 1, 0)
		label.Position = UDim2.new(0, 14, 0, 0)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamBold
		label.TextSize = 17
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextColor3 = Color3.fromRGB(255, 240, 215)
		label.Text = icon .. "  " .. text
		label.ZIndex = 27
		label.Parent = header
		return header
	end

	local selectedDeckVariantId = DeckVariants.DefaultId
	local selectedDifficultyId = DifficultyTiers.DefaultId
	local deckVariantCards = {}
	local difficultyCards = {}

	-- Deck Variant = gold (matches the game's card-suit gold), Difficulty =
	-- crimson (danger/stakes read) -- reused for both the section headers
	-- above and the accent stripe on every card in that section below.
	local DECK_VARIANT_ACCENT = Color3.fromRGB(255, 200, 90)
	local DIFFICULTY_ACCENT = Color3.fromRGB(210, 70, 70)

	makeRunSetupSectionLabel("Deck Variant", "🃏", 1, DECK_VARIANT_ACCENT)
	makeRunSetupSectionLabel("Difficulty", "⚔️", 19, DIFFICULTY_ACCENT)

	local function makePickCard(parent, order, name, description, isSelected, accentColor)
		local card = Instance.new("Frame")
		card.Size = UDim2.new(1, 0, 0, 60)
		card.BackgroundColor3 = isSelected and Color3.fromRGB(90, 70, 40) or Color3.fromRGB(60, 45, 32)
		card.LayoutOrder = order
		card.ZIndex = 26
		card.Parent = parent
		polishPanel(card, 10)

		local stripe = Instance.new("Frame")
		stripe.Size = UDim2.new(0, 4, 1, -12)
		stripe.Position = UDim2.new(0, 0, 0, 6)
		stripe.BackgroundColor3 = accentColor
		stripe.BorderSizePixel = 0
		stripe.ZIndex = 27
		stripe.Parent = card
		roundCorner(stripe, 2)

		local nameLabel = Instance.new("TextLabel")
		nameLabel.Size = UDim2.new(1, -30, 0, 22)
		nameLabel.Position = UDim2.new(0, 16, 0, 4)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Font = Enum.Font.GothamBold
		nameLabel.TextSize = 15
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.TextColor3 = Color3.fromRGB(250, 240, 220)
		nameLabel.Text = (isSelected and "✓ " or "") .. name
		nameLabel.ZIndex = 26
		nameLabel.Parent = card

		local descLabel = Instance.new("TextLabel")
		descLabel.Size = UDim2.new(1, -30, 0, 30)
		descLabel.Position = UDim2.new(0, 16, 0, 26)
		descLabel.BackgroundTransparency = 1
		descLabel.Font = Enum.Font.Gotham
		descLabel.TextSize = 13
		descLabel.TextWrapped = true
		descLabel.TextXAlignment = Enum.TextXAlignment.Left
		descLabel.TextColor3 = Color3.fromRGB(210, 195, 175)
		descLabel.Text = description
		descLabel.ZIndex = 26
		descLabel.Parent = card

		local clickCatcher = Instance.new("TextButton")
		clickCatcher.Size = UDim2.fromScale(1, 1)
		clickCatcher.BackgroundTransparency = 1
		clickCatcher.Text = ""
		clickCatcher.ZIndex = 26
		clickCatcher.Parent = card

		return card, clickCatcher
	end

	local function refreshRunSetupCards()
		for _, child in ipairs(deckVariantCards) do
			child:Destroy()
		end
		deckVariantCards = {}
		for i, variant in ipairs(DeckVariants.Definitions) do
			local card, clickCatcher = makePickCard(runSetupScroll, 2 + i, variant.name, variant.description, variant.id == selectedDeckVariantId, DECK_VARIANT_ACCENT)
			table.insert(deckVariantCards, card)
			clickCatcher.MouseButton1Click:Connect(function()
				playClickSfx(0.4)
				selectedDeckVariantId = variant.id
				refreshRunSetupCards()
			end)
		end

		for _, child in ipairs(difficultyCards) do
			child:Destroy()
		end
		difficultyCards = {}
		for i, tier in ipairs(DifficultyTiers.Definitions) do
			local card, clickCatcher = makePickCard(runSetupScroll, 20 + i, tier.name, tier.description, tier.id == selectedDifficultyId, DIFFICULTY_ACCENT)
			table.insert(difficultyCards, card)
			clickCatcher.MouseButton1Click:Connect(function()
				playClickSfx(0.4)
				selectedDifficultyId = tier.id
				refreshRunSetupCards()
			end)
		end
	end

	refreshRunSetupCards()

	local runSetupBeginButton = Instance.new("TextButton")
	runSetupBeginButton.Size = UDim2.new(0, 200, 0, 44)
	runSetupBeginButton.Position = UDim2.new(0.5, -210, 1, -55)
	runSetupBeginButton.Font = Enum.Font.GothamBold
	runSetupBeginButton.TextSize = 18
	runSetupBeginButton.Text = "Begin Run"
	runSetupBeginButton.BackgroundColor3 = Color3.fromRGB(70, 110, 65)
	runSetupBeginButton.TextColor3 = Color3.fromRGB(250, 240, 220)
	runSetupBeginButton.ZIndex = 26
	runSetupBeginButton.Parent = runSetupPanel
	polishButton(runSetupBeginButton, 12)

	local runSetupCancelButton = Instance.new("TextButton")
	runSetupCancelButton.Size = UDim2.new(0, 140, 0, 44)
	runSetupCancelButton.Position = UDim2.new(0.5, 10, 1, -55)
	runSetupCancelButton.Font = Enum.Font.GothamBold
	runSetupCancelButton.TextSize = 16
	runSetupCancelButton.Text = "Cancel"
	runSetupCancelButton.BackgroundColor3 = Color3.fromRGB(90, 60, 30)
	runSetupCancelButton.TextColor3 = Color3.fromRGB(250, 240, 220)
	runSetupCancelButton.ZIndex = 26
	runSetupCancelButton.Parent = runSetupPanel
	polishButton(runSetupCancelButton, 12)

	runSetupCancelButton.MouseButton1Click:Connect(function()
		playClickSfx()
		runSetupBackdrop.Visible = false
	end)

	runSetupBeginButton.MouseButton1Click:Connect(function()
		playSfx(SOUND_IDS.buyPatron)
		StartRunRemote:FireServer(selectedDeckVariantId, selectedDifficultyId)
		runSetupBackdrop.Visible = false
		menuFrame.Visible = false
		root.Visible = true
		if backgroundMusic.SoundId ~= "rbxassetid://0" and backgroundMusic.Volume > 0 then
			backgroundMusic:Play()
		end
	end)

	local function openRunSetup()
		playClickSfx()
		refreshRunSetupCards()
		runSetupBackdrop.Visible = true
	end

	menuNewRunButton.MouseButton1Click:Connect(openRunSetup)

	return {}
end
