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
		ArtAssetsModule -- the required Client/ArtAssets.lua module table
		                   (reads cardBackTemplate off it)

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
	local ArtAssetsModule = deps.ArtAssetsModule
	local cardBackTemplate = ArtAssetsModule.cardBackTemplate

	local deckWidget = Instance.new("Frame")
	deckWidget.Name = "DeckWidget"
	deckWidget.AnchorPoint = Vector2.new(1, 1)
	-- REFERENCE-MATCH PASS (Nov 1 2026): bigger, and set in an ornate
	-- dark-wood frame with the count inside the frame's bottom edge, like
	-- the reference. Bottom edge lines up with the hand tray's bottom.
	deckWidget.Position = UDim2.new(1, -20, 1, -84)
	deckWidget.Size = UDim2.new(0, 124, 0, 195) -- matches the holder art's 651x1024 shape
	deckWidget.BackgroundColor3 = Color3.fromRGB(34, 22, 13)
	deckWidget.BackgroundTransparency = 0.1
	deckWidget.ZIndex = 2
	deckWidget.Parent = root
	polishPanel(deckWidget, 10)
	do
		local rim = deckWidget:FindFirstChildOfClass("UIStroke")
		if rim then
			rim.Color = Color3.fromRGB(205, 170, 95)
			rim.Thickness = 2
			rim.Transparency = 0.05
		end
		local carve = Instance.new("UIGradient")
		carve.Rotation = 90
		carve.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(150, 150, 150))
		carve.Parent = deckWidget
	end

	-- ART: the carved deck-holder image (ArtAssets.deckHolderArt). Created
	-- before the card back and count so it draws underneath both. Once it
	-- loads, the card back and count move into the holder's window.
	local deckSkin = require(script.Parent.SkinArt)
	local deckHolderArt = deckSkin.apply(deckWidget, ArtAssetsModule.deckHolderArt, {
		zIndex = 2,
		onLoaded = function()
			deckSkin.hideCodeChrome(deckWidget)
		end,
	})

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
	deckCardBack.Position = UDim2.fromOffset(12, 12)
	deckCardBack.Size = UDim2.new(1, -24, 0, 140)
	deckCardBack.BackgroundColor3 = Color3.fromRGB(50, 70, 110)
	deckCardBack.ZIndex = 2
	deckCardBack.Parent = deckWidget
	polishPanel(deckCardBack, 8)
	addSoftShadow(deckCardBack, 10)

	-- CARD ART: the single card-back template (see ArtAssets.lua). ZIndex
	-- 3, one above deckCardBackIcon's emoji fallback (ZIndex 2), matching
	-- the "art sits in front" ordering used everywhere else.
	local deckCardBackArt = Instance.new("ImageLabel")
	deckCardBackArt.Name = "CardBackArt"
	deckCardBackArt.Size = UDim2.fromScale(1, 1)
	deckCardBackArt.BackgroundTransparency = 1
	deckCardBackArt.BorderSizePixel = 0
	deckCardBackArt.ScaleType = Enum.ScaleType.Stretch
	deckCardBackArt.Image = cardBackTemplate
	deckCardBackArt.ZIndex = 3
	deckCardBackArt.Parent = deckCardBack
	roundCorner(deckCardBackArt, 8)

	-- Emoji fallback, shown only while cardBackTemplate is the
	-- "rbxassetid://0" placeholder. No async load check needed anymore:
	-- a whole (unsliced) image can't show a broken partial cell mid-load.
	local deckCardBackIcon = Instance.new("TextLabel")
	deckCardBackIcon.Size = UDim2.fromScale(1, 1)
	deckCardBackIcon.BackgroundTransparency = 1
	deckCardBackIcon.Font = Enum.Font.GothamBold
	deckCardBackIcon.TextSize = 30
	deckCardBackIcon.TextColor3 = Color3.fromRGB(220, 225, 240)
	deckCardBackIcon.Text = "🂠"
	deckCardBackIcon.Visible = (cardBackTemplate == "rbxassetid://0")
	deckCardBackIcon.ZIndex = 2
	deckCardBackIcon.Parent = deckCardBack

	local deckCountLabel = Instance.new("TextLabel")
	deckCountLabel.Size = UDim2.new(1, 0, 0, 26)
	deckCountLabel.Position = UDim2.new(0, 0, 0, 158)
	deckCountLabel.BackgroundTransparency = 1
	deckCountLabel.Font = Enum.Font.GothamBold
	deckCountLabel.TextSize = 18
	deckCountLabel.TextColor3 = Color3.fromRGB(240, 230, 215)
	deckCountLabel.Text = ""
	deckCountLabel.ZIndex = 2
	deckCountLabel.Parent = deckWidget

	-- Re-lay the card back + count inside the holder's window once the
	-- art is actually showing (window measured from ui-deck-holder.png).
	if deckHolderArt then
		deckHolderArt:GetPropertyChangedSignal("IsLoaded"):Connect(function()
			if deckHolderArt.IsLoaded then
				local win = deckSkin.DeckHolderWindow
				local winW = win.right - win.left
				deckCardBack.AnchorPoint = Vector2.new(0.5, 0)
				deckCardBack.Position = UDim2.new((win.left + win.right) / 2, 0, win.top, 6)
				deckCardBack.Size = UDim2.new(winW * 0.84, 0, 0, 118)
				deckCountLabel.Position = UDim2.new(0, 0, win.bottom, -30)
				deckCountLabel.Size = UDim2.new(1, 0, 0, 24)
				local shadow = deckWidget:FindFirstChild("Shadow")
				if shadow then
					shadow.Visible = false -- was positioned for the old layout
				end
			end
		end)
	end

	return {
		deckCountLabel = deckCountLabel,
		deckWidgetButton = deckWidgetButton,
	}
end
