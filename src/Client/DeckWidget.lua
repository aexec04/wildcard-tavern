--[[
	Client/DeckWidget.lua
	LAYOUT FEATURE 3: the always-visible "how many cards are left" readout,
	bottom-right, with a card-back icon -- so that info isn't only reachable
	through the Deck Tracker overlay. Parented under root (not screenGui
	directly), so its addSoftShadow correctly cascades hidden/visible with
	the menu <-> gameplay toggle.

	Extracted out of init.client.lua as part of splitting the client script
	into smaller, per-feature files. deckCountLabel is updated every
	render() call, and deckWidgetButton is passed as a dep into
	DeckTracker.lua (which wires its own click handler onto it -- the deck
	widget itself IS the Deck Tracker entry point, no separate corner
	button), so both come back out of the require() call.

	deps fields:
		root          -- Frame, the widget's parent
		polishPanel    -- function(instance, radius)
		addSoftShadow  -- function(instance, radius)
		addTooltip     -- function(button, text, align?)
		roundCorner    -- function(instance, radius)
		cardSpriteSheet      -- string, "rbxassetid://..." -- see Client/ArtAssets.lua
		cardSpriteBackOffset -- Vector2, see Client/ArtAssets.lua
		cardSpriteCellSize   -- number, see Client/ArtAssets.lua

	Returns:
		{
			deckCountLabel = TextLabel,
			deckWidgetButton = TextButton,
		}
]]

return function(deps)
	local root = deps.root
	local polishPanel = deps.polishPanel
	local addSoftShadow = deps.addSoftShadow
	local addTooltip = deps.addTooltip
	local roundCorner = deps.roundCorner
	local cardSpriteSheet = deps.cardSpriteSheet
	local cardSpriteBackOffset = deps.cardSpriteBackOffset
	local cardSpriteCellVector = Vector2.new(deps.cardSpriteCellSize, deps.cardSpriteCellSize)

	local deckWidget = Instance.new("Frame")
	deckWidget.Name = "DeckWidget"
	deckWidget.AnchorPoint = Vector2.new(1, 1)
	deckWidget.Position = UDim2.new(1, -20, 1, -70)
	deckWidget.Size = UDim2.new(0, 74, 0, 118)
	deckWidget.BackgroundTransparency = 1
	deckWidget.ZIndex = 2
	deckWidget.Parent = root

	-- The deck widget itself IS the Deck Tracker entry point (no separate
	-- corner button) -- a transparent click-catcher over the whole widget, so
	-- clicking the card-back icon or the count label both open the tracker.
	-- Its click handler is wired inside Client/DeckTracker.lua, which takes
	-- this button as a dep.
	local deckWidgetButton = Instance.new("TextButton")
	deckWidgetButton.Name = "ClickCatcher"
	deckWidgetButton.Size = UDim2.fromScale(1, 1)
	deckWidgetButton.BackgroundTransparency = 1
	deckWidgetButton.Text = ""
	deckWidgetButton.ZIndex = 3
	deckWidgetButton.Parent = deckWidget
	addTooltip(deckWidgetButton, "Deck Tracker -- click to see what's left in the deck")

	local deckCardBack = Instance.new("Frame")
	deckCardBack.Size = UDim2.new(1, 0, 0, 96)
	deckCardBack.BackgroundColor3 = Color3.fromRGB(50, 70, 110)
	deckCardBack.ZIndex = 2
	deckCardBack.Parent = deckWidget
	polishPanel(deckCardBack, 8)
	addSoftShadow(deckCardBack, 10)

	-- CARD ART (same Kenney sprite sheet as the hand's cards -- see
	-- ArtAssets.lua): the sheet's one card-back cell. ZIndex 3, one above
	-- deckCardBackIcon's emoji fallback (ZIndex 2) -- not that both are
	-- ever visible at once (see showPlaceholderBack below), but matches
	-- the "art sits in front" ordering used everywhere else.
	local deckCardBackArt = Instance.new("ImageLabel")
	deckCardBackArt.Name = "CardBackArt"
	deckCardBackArt.Size = UDim2.fromScale(1, 1)
	deckCardBackArt.BackgroundTransparency = 1
	deckCardBackArt.BorderSizePixel = 0
	deckCardBackArt.ScaleType = Enum.ScaleType.Stretch
	deckCardBackArt.Image = cardSpriteSheet
	deckCardBackArt.ImageRectOffset = cardSpriteBackOffset
	deckCardBackArt.ImageRectSize = cardSpriteCellVector
	deckCardBackArt.ZIndex = 3
	deckCardBackArt.Parent = deckCardBack
	roundCorner(deckCardBackArt, 8)

	-- Fallback while cardSpriteSheet is still the "rbxassetid://0"
	-- placeholder -- same pattern as init.client.lua's cardRankSuitLabel
	-- (see its own comment): hidden, not removed, the instant a real
	-- sheet is wired in, so there's nothing else to flip by hand either
	-- way.
	local showPlaceholderBack = cardSpriteSheet == "rbxassetid://0"
	local deckCardBackIcon = Instance.new("TextLabel")
	deckCardBackIcon.Size = UDim2.fromScale(1, 1)
	deckCardBackIcon.BackgroundTransparency = 1
	deckCardBackIcon.Font = Enum.Font.GothamBold
	deckCardBackIcon.TextSize = 30
	deckCardBackIcon.TextColor3 = Color3.fromRGB(220, 225, 240)
	deckCardBackIcon.Text = "🂠"
	deckCardBackIcon.Visible = showPlaceholderBack
	deckCardBackIcon.ZIndex = 2
	deckCardBackIcon.Parent = deckCardBack

	local deckCountLabel = Instance.new("TextLabel")
	deckCountLabel.Size = UDim2.new(1, 0, 0, 20)
	deckCountLabel.Position = UDim2.new(0, 0, 0, 98)
	deckCountLabel.BackgroundTransparency = 1
	deckCountLabel.Font = Enum.Font.GothamBold
	deckCountLabel.TextSize = 14
	deckCountLabel.TextColor3 = Color3.fromRGB(240, 230, 215)
	deckCountLabel.Text = ""
	deckCountLabel.ZIndex = 2
	deckCountLabel.Parent = deckWidget

	return {
		deckCountLabel = deckCountLabel,
		deckWidgetButton = deckWidgetButton,
	}
end
