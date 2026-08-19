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

	local deckCardBackIcon = Instance.new("TextLabel")
	deckCardBackIcon.Size = UDim2.fromScale(1, 1)
	deckCardBackIcon.BackgroundTransparency = 1
	deckCardBackIcon.Font = Enum.Font.GothamBold
	deckCardBackIcon.TextSize = 30
	deckCardBackIcon.TextColor3 = Color3.fromRGB(220, 225, 240)
	deckCardBackIcon.Text = "🂠"
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
