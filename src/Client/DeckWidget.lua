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

	-- ART: a solid wood board behind the holder's see-through window, so
	-- it reads as a clipboard the card sits ON (like the reference), not an
	-- empty frame with the room showing through. Reuses the sidebar column
	-- art's plank texture (ImageRect picks a plain middle patch of that
	-- 417x1024 image, clear of its gold trim) -- no extra upload needed.
	-- Created BEFORE the holder art so it draws underneath it, and hidden
	-- until the holder art has loaded.
	local deckBoard = Instance.new("ImageLabel")
	deckBoard.Name = "DeckBoard"
	do
		local win = deckSkin.DeckHolderWindow
		local pad = 0.02 -- tuck the edges under the carved frame
		deckBoard.Position = UDim2.fromScale(win.left - pad, win.top - pad)
		deckBoard.Size = UDim2.fromScale(win.right - win.left + 2 * pad, win.bottom - win.top + 2 * pad)
	end
	deckBoard.BackgroundColor3 = Color3.fromRGB(46, 28, 15) -- shows if the texture is slow
	deckBoard.BackgroundTransparency = 0
	deckBoard.BorderSizePixel = 0
	deckBoard.Image = ArtAssetsModule.sidebarColumnArt or "rbxassetid://0"
	deckBoard.ImageRectOffset = Vector2.new(40, 120)
	deckBoard.ImageRectSize = Vector2.new(300, 470)
	deckBoard.ScaleType = Enum.ScaleType.Stretch
	deckBoard.ImageColor3 = deckSkin.Tints.deckBoard
	deckBoard.ZIndex = 2
	deckBoard.Visible = false
	deckBoard.Parent = deckWidget

	-- Filled in further down, once the card back and count exist.
	local onDeckHolderLoaded
	deckSkin.apply(deckWidget, ArtAssetsModule.deckHolderArt, {
		tint = deckSkin.Tints.deckHolder,
		zIndex = 2,
		onLoaded = function()
			deckSkin.hideCodeChrome(deckWidget)
			if onDeckHolderLoaded then
				onDeckHolderLoaded()
			end
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
	addTooltip(deckWidgetButton, "Click to see your deck")

	-- Hover feel like the hand cards: the pile lifts 6px and a gold glow ring fades in; a click gives a small
	-- shuffle wiggle. Tweens only (no loops); Reduce screen shake keeps the glow and skips the motion. The glow
	-- frame is a child of the widget (decorative, not in any layout) and survives a recolor by CosmeticSetsView.
	do
		local TweenService = game:GetService("TweenService")
		local ClientSettings = require(script.Parent.ClientSettings)
		local baseRest = deckWidget.Position
		-- Client/PlayDeckPaint moves the widget into the painted recess and records where it rests as an attribute
		local function restPos() return deckWidget:GetAttribute("PaintedRest") or baseRest end
		local glowFrame = Instance.new("Frame")
		glowFrame.Name = "PileGlow"
		glowFrame.Size = UDim2.fromScale(1, 1)
		glowFrame.BackgroundTransparency = 1
		glowFrame.BorderSizePixel = 0
		glowFrame.Active = false
		glowFrame.ZIndex = 2
		glowFrame.Parent = deckWidget
		roundCorner(glowFrame, 10)
		local glowStroke = Instance.new("UIStroke")
		glowStroke.Color = Color3.fromRGB(235, 200, 120)
		glowStroke.Thickness = 5
		glowStroke.Transparency = 1
		glowStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		glowStroke.Parent = glowFrame
		local liftTween, wiggleToken = nil, 0
		local function motion()
			return ClientSettings.get("reduceShake") ~= true
		end
		deckWidgetButton.MouseEnter:Connect(function()
			if require(script.Parent.ModalStage).blocks(deckWidgetButton) then return end -- a modal is open: nothing behind it reacts
			TweenService:Create(glowStroke, TweenInfo.new(0.15), { Transparency = 0.2 }):Play()
			if motion() then
				if liftTween then liftTween:Cancel() end
				liftTween = TweenService:Create(deckWidget, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
					{ Position = restPos() - UDim2.fromOffset(0, 6) })
				liftTween:Play()
			end
		end)
		deckWidgetButton.MouseLeave:Connect(function()
			TweenService:Create(glowStroke, TweenInfo.new(0.2), { Transparency = 1 }):Play()
			if liftTween then liftTween:Cancel() end
			liftTween = TweenService:Create(deckWidget, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = restPos() })
			liftTween:Play()
		end)
		deckWidgetButton.MouseButton1Click:Connect(function()
			if not motion() then return end
			wiggleToken = wiggleToken + 1
			local mine = wiggleToken
			task.spawn(function()
				for _, rot in ipairs({ -4, 4, -2.5, 2.5, 0 }) do
					if wiggleToken ~= mine then return end
					TweenService:Create(deckWidget, TweenInfo.new(0.05, Enum.EasingStyle.Sine), { Rotation = rot }):Play()
					task.wait(0.05)
				end
			end)
		end)
	end

	-- Two cards peek out from under the top card (2-3px offsets, 1.5 degree turns)
	-- so the pile reads as a stack. CosmeticSetsView swaps their art with the top card's.
	local stackCards = {}
	for i, spec in ipairs({ { name = "StackBackA", dx = 3, dy = 3, rot = 1.5 }, { name = "StackBackB", dx = -2, dy = 2, rot = -1.5 } }) do
		local c = Instance.new("ImageLabel")
		c.Name = spec.name
		c.AnchorPoint = Vector2.new(0.5, 0)
		c.BackgroundColor3 = Color3.fromRGB(50, 70, 110)
		c.BorderSizePixel = 0
		c.Image = cardBackTemplate
		c.ScaleType = Enum.ScaleType.Stretch
		c.Rotation = spec.rot
		c.ZIndex = 2
		c.Active = false
		c.Parent = deckWidget
		roundCorner(c, 8)
		local edge = Instance.new("UIStroke")
		edge.Color = Color3.fromRGB(20, 14, 8)
		edge.Thickness = 1
		edge.Parent = c
		stackCards[i] = { frame = c, dx = spec.dx, dy = spec.dy }
	end

	local deckCardBack = Instance.new("Frame")
	deckCardBack.Name = "DeckCardBack"
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
	deckCardBackArt.AnchorPoint = Vector2.new(0.5, 0.5)
	deckCardBackArt.Position = UDim2.fromScale(0.5, 0.5)
	deckCardBackArt.Size = UDim2.fromScale(1, 1)
	deckCardBackArt.BackgroundTransparency = 1
	deckCardBackArt.BorderSizePixel = 0
	deckCardBackArt.ScaleType = Enum.ScaleType.Stretch -- Crop once a painted back is equipped
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
	deckCountLabel.Name = "DeckCount"
	deckCountLabel.AnchorPoint = Vector2.new(0.5, 0)
	deckCountLabel.Size = UDim2.new(0, 72, 0, 24)
	deckCountLabel.Position = UDim2.new(0.5, 0, 0, 158)
	deckCountLabel.BackgroundColor3 = Color3.fromRGB(24, 15, 8) -- dark pill keeps the count readable on any back
	deckCountLabel.BackgroundTransparency = 0.25
	roundCorner(deckCountLabel, 12)
	deckCountLabel.Font = Enum.Font.GothamBold
	deckCountLabel.TextSize = 18
	deckCountLabel.TextColor3 = Color3.fromRGB(240, 230, 215)
	deckCountLabel.Text = ""
	deckCountLabel.ZIndex = 4
	deckCountLabel.Parent = deckWidget

	-- Re-lay the card back + count inside the holder's window once the
	-- art is actually showing (window measured from ui-deck-holder.png).
	-- Once the holder art is showing: move the card back and count into
	-- its window, and drop the card back's own light rim, blue fill and
	-- shadow -- the holder's carved frame replaces all of them.
	onDeckHolderLoaded = function()
		local win = deckSkin.DeckHolderWindow
		local winW = win.right - win.left
		deckBoard.Visible = true
		-- Card fills most of the board (about 82% of its width, card-shaped),
		-- with the count on the board underneath.
		deckCardBack.AnchorPoint = Vector2.new(0.5, 0)
		deckCardBack.Position = UDim2.new((win.left + win.right) / 2, 0, win.top, 8)
		deckCardBack.Size = UDim2.new(winW * 0.82, 0, 0, 116)
		deckCountLabel.Position = UDim2.new(0.5, 0, win.bottom, -29)
		deckCountLabel.Size = UDim2.new(0, 72, 0, 24)
		local shadow = deckWidget:FindFirstChild("Shadow")
		if shadow then
			shadow.Visible = false
		end
		local backRim = deckCardBack:FindFirstChildOfClass("UIStroke")
		if backRim then
			backRim.Enabled = false
		end
		deckCardBack.BackgroundTransparency = 1
	end

	local function syncStack()
		for _, c in ipairs(stackCards) do
			c.frame.Visible = deckCardBack.Visible
			c.frame.Size = deckCardBack.Size
			local pos = deckCardBack.Position
			c.frame.AnchorPoint = Vector2.new(0.5, 0)
			-- The top card is anchored at its left edge before the holder art loads, and centered after.
			local cx = deckCardBack.AnchorPoint.X == 0.5 and pos.X or UDim.new(pos.X.Scale, pos.X.Offset)
			local halfW = deckCardBack.AnchorPoint.X == 0.5 and 0 or deckCardBack.AbsoluteSize.X / 2
			c.frame.Position = UDim2.new(cx.Scale, cx.Offset + halfW + c.dx, pos.Y.Scale, pos.Y.Offset + c.dy)
		end
	end
	for _, prop in ipairs({ "Position", "Size", "AnchorPoint", "Visible" }) do
		deckCardBack:GetPropertyChangedSignal(prop):Connect(syncStack)
	end
	deckCardBack:GetPropertyChangedSignal("AbsoluteSize"):Connect(syncStack)
	syncStack()

	-- per-set brackets, count plate and card-back pile tilt (Client/DeckWidgetSkin)
	pcall(function()
		require(script.Parent.DeckWidgetSkin).install({
			widget = deckWidget, cardBack = deckCardBack, stackCards = stackCards, count = deckCountLabel, syncStack = syncStack,
		})
	end)

	return {
		deckCountLabel = deckCountLabel,
		deckWidgetButton = deckWidgetButton,
	}
end
