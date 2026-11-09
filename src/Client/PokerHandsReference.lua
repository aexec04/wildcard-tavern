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
		popIn            -- function(backdrop, content, opts?)
		popOut           -- function(backdrop, content, opts?, onHidden?)
		addButtonHoverScale -- function(button, opts?)

	Returns: {}

	REDESIGN: parchment panel; one divider per row with a faint alternating
	tint; 5 mini example cards per row (HandEvaluator.Examples, drawn with
	CardFace); big Chips x Mult using leveled values (state.handLevels +
	Scoring.HandLevelGrowth); level badge; dimmed 0-play rows; gold star on
	the most played hand; live row highlight for the hand the selected cards
	make (Client/HandHighlight.lua). Closes via Close, clicking outside, or
	Escape. List scrolls only if the panel is too short for all 9 rows.

	POLISH PASS (Batch 3): popIn/popOut replace the old bare
	Visible = true/false cut; the Close button gets addButtonHoverScale.
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
	local popIn = deps.popIn
	local popOut = deps.popOut
	local addButtonHoverScale = deps.addButtonHoverScale
	-- BUGFIX (overlapping overlays): see Client/OverlayManager.lua's own
	-- header comment for the full story.
	local OverlayManager = require(script.Parent.OverlayManager)
	local HandHighlight = require(script.Parent.HandHighlight)
	local CardFace = require(script.Parent.CardFace)
	local Palette = require(script.Parent.Palette)
	local UserInputService = game:GetService("UserInputService")

	local CREAM = Color3.fromRGB(250, 240, 220)
	local GOLD = Color3.fromRGB(255, 214, 130)
	local EMBER = Color3.fromRGB(240, 100, 75)
	local MUTED = Color3.fromRGB(200, 185, 165)
	local SUIT_SYMBOLS = { Hearts = "♥", Diamonds = "♦", Clubs = "♣", Spades = "♠" }
	local RANK_TEXT = { [11] = "J", [12] = "Q", [13] = "K", [14] = "A" }
	local ROW_COUNT = #HandEvaluator.HandOrder
	local MIN_ROW, MAX_ROW = 34, 60

	-- Column layout (scale of row width): name, example cards, chips x mult, played.
	local COL = {
		name = { 0, 0.30 },
		example = { 0.30, 0.30 },
		value = { 0.60, 0.26 },
		played = { 0.86, 0.14 },
	}

	local backdrop = Instance.new("TextButton")
	backdrop.Name = "HandRefBackdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	backdrop.BackgroundTransparency = 0.4
	backdrop.AutoButtonColor = false
	backdrop.Text = ""
	backdrop.Visible = false
	backdrop.ZIndex = 20
	backdrop.Parent = screenGui

	local panel = Instance.new("Frame")
	panel.Size = UDim2.fromScale(0.62, 0.92)
	panel.Position = UDim2.fromScale(0.19, 0.04)
	panel.BackgroundColor3 = Color3.fromRGB(40, 30, 22)
	panel.Active = true -- swallow clicks so only the backdrop outside closes
	panel.ZIndex = 21
	panel.Parent = backdrop
	local sizeLimit = Instance.new("UISizeConstraint")
	sizeLimit.MinSize = Vector2.new(400, 330)
	sizeLimit.MaxSize = Vector2.new(760, 640)
	sizeLimit.Parent = panel
	polishPanel(panel, 16, "parchment")
	addSoftShadow(panel, 18)
	-- Same carved-wood plaque art the sidebar boxes use. Created before any
	-- labels so it draws underneath them; code chrome hides once it loads.
	do
		local SkinArt = require(script.Parent.SkinArt)
		local ArtAssets = require(script.Parent.ArtAssets)
		local slice = SkinArt.Slices.plaque
		SkinArt.apply(panel, ArtAssets.plaqueFrameArt, {
			tint = SkinArt.Tints.plaque,
			sliceCenter = slice.center,
			sliceScale = slice.scale,
			onLoaded = function()
				SkinArt.hideCodeChrome(panel)
			end,
		})
	end

	-- ===== Header: ornate title =====
	local function line(parent, pos, size, alpha, z)
		local f = Instance.new("Frame")
		f.AnchorPoint = Vector2.new(0, 0.5)
		f.Position = pos
		f.Size = size
		f.BackgroundColor3 = GOLD
		f.BackgroundTransparency = alpha
		f.BorderSizePixel = 0
		f.ZIndex = z or 22
		f.Parent = parent
		return f
	end

	local title = Instance.new("TextLabel")
	title.AnchorPoint = Vector2.new(0.5, 0)
	title.Position = UDim2.new(0.5, 0, 0, 8)
	title.Size = UDim2.new(0, 260, 0, 36)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.TextSize = 28
	title.TextColor3 = GOLD
	title.TextTransparency = 0
	title.TextStrokeTransparency = 1
	title.Text = "◆ Poker Hands ◆"
	title.ZIndex = 22
	title.Parent = panel
	line(panel, UDim2.new(0, 24, 0, 25), UDim2.new(0.5, -144, 0, 2), 0.35, 22)
	line(panel, UDim2.new(0.5, 124, 0, 25), UDim2.new(0.5, -148, 0, 2), 0.35, 22)

	local header = Instance.new("Frame")
	header.Position = UDim2.new(0, 14, 0, 46)
	header.Size = UDim2.new(1, -28, 0, 20)
	header.BackgroundTransparency = 1
	header.ZIndex = 22
	header.Parent = panel
	local function headerLabel(text, col, align, inset)
		local label = Instance.new("TextLabel")
		label.Position = UDim2.new(col[1], inset or 0, 0, 0)
		label.Size = UDim2.new(col[2], -(inset or 0), 1, 0)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamBold
		label.TextSize = 15
		label.TextColor3 = GOLD
		label.TextTransparency = 0
		label.TextStrokeTransparency = 1
		label.TextXAlignment = align
		label.Text = text
		label.ZIndex = 22
		label.Parent = header
	end
	headerLabel("Hand", COL.name, Enum.TextXAlignment.Left, 8)
	headerLabel("Example", COL.example, Enum.TextXAlignment.Left)
	headerLabel("Chips x Mult", COL.value, Enum.TextXAlignment.Center)
	headerLabel("Played", COL.played, Enum.TextXAlignment.Right, 0)
	line(panel, UDim2.new(0, 14, 0, 70), UDim2.new(1, -28, 0, 1), 0.55)

	-- ===== List (scrolls only as a small-screen fallback) =====
	local listFrame = Instance.new("ScrollingFrame")
	listFrame.Position = UDim2.new(0, 14, 0, 74)
	listFrame.Size = UDim2.new(1, -28, 1, -74 - 66)
	listFrame.BackgroundTransparency = 1
	listFrame.BorderSizePixel = 0
	listFrame.ScrollBarThickness = 5
	listFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	listFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
	listFrame.ZIndex = 21
	listFrame.Parent = panel

	local listLayout = Instance.new("UIListLayout")
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Padding = UDim.new(0, 0)
	listLayout.Parent = listFrame

	local closeButton = Instance.new("TextButton")
	closeButton.Size = UDim2.new(0, 160, 0, 46)
	closeButton.Position = UDim2.new(0.5, -80, 1, -56)
	closeButton.Font = Enum.Font.GothamBold
	closeButton.TextSize = 16
	closeButton.Text = "Close"
	closeButton.BackgroundColor3 = Color3.fromRGB(90, 60, 30)
	closeButton.TextColor3 = CREAM
	closeButton.ZIndex = 23
	closeButton.Parent = panel
	polishButton(closeButton, 12)
	addButtonHoverScale(closeButton)
	do
		-- Same button art as Play Hand / Discard. Art sits at ZIndex 22,
		-- under the button's own text at 23.
		local SkinArt = require(script.Parent.SkinArt)
		local ArtAssets = require(script.Parent.ArtAssets)
		local slice = SkinArt.Slices.button
		SkinArt.apply(closeButton, ArtAssets.actionButtonArt, {
			tint = SkinArt.Tints.button,
			zIndex = 22,
			sliceCenter = slice.center,
			sliceScale = slice.scale,
			onLoaded = function()
				SkinArt.hideCodeChrome(closeButton)
			end,
		})
	end

	local function closePanel()
		if backdrop.Visible then
			popOut(backdrop, panel)
		end
	end
	closeButton.MouseButton1Click:Connect(function()
		playClickSfx()
		closePanel()
	end)
	backdrop.MouseButton1Click:Connect(closePanel)
	-- Escape is also Roblox's own menu key, so ignore gameProcessed.
	UserInputService.InputBegan:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.Escape then
			closePanel()
		end
	end)

	-- ===== Rows =====
	local rowsByHand = {}

	local function applyHighlight(handName)
		for name, row in pairs(rowsByHand) do
			if row.Parent then
				local lit = name == handName
				local bar = row:FindFirstChild("HighlightBar")
				if bar then
					bar.Visible = lit
				end
				if lit then
					row.BackgroundColor3 = GOLD
					row.BackgroundTransparency = 0.78
				else
					row.BackgroundColor3 = Color3.fromRGB(255, 245, 225)
					row.BackgroundTransparency = row:GetAttribute("BaseTint")
				end
			end
		end
	end

	local function fitRows()
		local available = listFrame.AbsoluteSize.Y
		if available <= 0 then
			return
		end
		local listW = listFrame.AbsoluteSize.X
		local h = math.clamp(math.floor(available / ROW_COUNT), MIN_ROW, MAX_ROW)
		-- Example cards: as tall as the row allows, but never wider than the
		-- column holds all 5 of them (explicit pixel sizes; a 0-scale width
		-- plus an aspect constraint collapsed them to nothing).
		local gap = 3
		local ch = math.floor(h * 0.84)
		local maxW = math.floor((listW * COL.example[2] - gap * 4) / 5)
		local cw = math.max(8, math.min(math.floor(ch * 0.7), maxW))
		if cw < math.floor(ch * 0.7) then
			ch = math.floor(cw / 0.7)
		end
		for _, row in pairs(rowsByHand) do
			if row.Parent then
				row.Size = UDim2.new(1, 0, 0, h)
				local ex = row:FindFirstChild("Examples")
				if ex then
					for _, c in ipairs(ex:GetChildren()) do
						if c:IsA("Frame") then
							c.Size = UDim2.fromOffset(cw, ch)
						end
					end
				end
			end
		end
	end
	listFrame:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitRows)

	local function addText(parent, col, text, size, font, color, align, inset, rich)
		local label = Instance.new("TextLabel")
		label.Position = UDim2.new(col[1], inset or 0, 0, 0)
		label.Size = UDim2.new(col[2], -(inset or 0), 1, 0)
		label.BackgroundTransparency = 1
		label.Font = font
		label.TextSize = size
		label.TextColor3 = color
		label.TextTransparency = 0
		label.TextStrokeTransparency = 1
		label.TextXAlignment = align
		label.TextTruncate = Enum.TextTruncate.AtEnd
		label.RichText = rich == true
		label.Text = text
		label.ZIndex = 22
		label.Parent = parent
		return label
	end

	local function buildExample(parent, handName, dim)
		local spec = HandEvaluator.Examples and HandEvaluator.Examples[handName]
		if not spec then
			return
		end
		local container = Instance.new("Frame")
		container.Name = "Examples"
		container.Position = UDim2.new(COL.example[1], 0, 0, 0)
		container.Size = UDim2.new(COL.example[2], 0, 1, 0)
		container.BackgroundTransparency = 1
		container.ZIndex = 22
		container.Parent = parent
		local layout = Instance.new("UIListLayout")
		layout.FillDirection = Enum.FillDirection.Horizontal
		layout.VerticalAlignment = Enum.VerticalAlignment.Center
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Padding = UDim.new(0, 3)
		layout.Parent = container

		-- Which example cards actually score (the rest are kickers, drawn dimmer).
		local cards = {}
		for _, rs in ipairs(spec) do
			table.insert(cards, { rank = rs[1], suit = rs[2] })
		end
		local scoring = {}
		local okEval, result = pcall(HandEvaluator.evaluate, cards)
		if okEval and result then
			for _, c in ipairs(result.scoringCards) do
				scoring[c] = true
			end
		end

		for i, c in ipairs(cards) do
			local card = Instance.new("Frame")
			card.LayoutOrder = i
			card.Size = UDim2.fromOffset(20, 28) -- real size set in fitRows
			card.BackgroundColor3 = Palette.colors.cardBase
			card.BackgroundTransparency = (dim or (okEval and not scoring[c])) and 0.45 or 0
			card.BorderSizePixel = 0
			card.ZIndex = 22
			card.Parent = container
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0, 3)
			corner.Parent = card
			local stroke = Instance.new("UIStroke")
			stroke.Color = Color3.fromRGB(90, 60, 30)
			stroke.Thickness = 1
			stroke.Transparency = 0.3
			stroke.Parent = card
			CardFace.build(
				card,
				RANK_TEXT[c.rank] or tostring(c.rank),
				SUIT_SYMBOLS[c.suit],
				c.suit == "Hearts" or c.suit == "Diamonds",
				23,
				false
			)
		end
	end

	local function refreshHandReference()
		for _, child in ipairs(listFrame:GetChildren()) do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
		rowsByHand = {}

		local latestState = getLatestState()
		local handStats = (latestState and latestState.handStats) or {}
		local handLevels = (latestState and latestState.handLevels) or {}

		-- Most played hand (strongest wins ties); nil if nothing played yet.
		local topHand, topCount = nil, 0
		for i = #HandEvaluator.HandOrder, 1, -1 do
			local name = HandEvaluator.HandOrder[i]
			local n = handStats[name] or 0
			if n > topCount then
				topHand, topCount = name, n
			end
		end

		-- Strongest hand first, matching how most poker reference charts read.
		local order = 0
		for i = #HandEvaluator.HandOrder, 1, -1 do
			local handName = HandEvaluator.HandOrder[i]
			local base = Scoring.HandBase[handName]
			local growth = Scoring.HandLevelGrowth[handName] or { chips = 0, mult = 0 }
			local level = math.floor(handLevels[handName] or 0)
			local chips = math.floor(base.chips + growth.chips * level)
			local mult = math.floor(base.mult + growth.mult * level)
			local played = math.floor(handStats[handName] or 0)
			local dim = played == 0
			order = order + 1

			local row = Instance.new("Frame")
			row.Name = "Row_" .. handName
			row.LayoutOrder = order
			row.Size = UDim2.new(1, 0, 0, MIN_ROW)
			row.BackgroundColor3 = Color3.fromRGB(255, 245, 225)
			local baseTint = (order % 2 == 0) and 0.93 or 1
			row:SetAttribute("BaseTint", baseTint)
			row.BackgroundTransparency = baseTint
			row.BorderSizePixel = 0
			row.ZIndex = 21
			row.Parent = listFrame
			rowsByHand[handName] = row

			-- One thin divider between rows (not after the last).
			if order < ROW_COUNT then
				local div = line(row, UDim2.new(0, 0, 1, 0), UDim2.new(1, 0, 0, 1), 0.75, 21)
				div.Name = "Divider"
			end

			local bar = Instance.new("Frame")
			bar.Name = "HighlightBar"
			bar.Size = UDim2.new(0, 3, 1, -6)
			bar.Position = UDim2.new(0, 0, 0, 3)
			bar.BackgroundColor3 = GOLD
			bar.BorderSizePixel = 0
			bar.Visible = false
			bar.ZIndex = 23
			bar.Parent = row

			local nameText = handName
			if handName == topHand then
				nameText = '<font color="rgb(255,214,130)">★</font> ' .. handName
			end
			local nameLabel = addText(row, COL.name, nameText, 17, Enum.Font.GothamBold, CREAM, Enum.TextXAlignment.Left, 8, true)
			nameLabel.TextTransparency = dim and 0.4 or 0

			if level > 0 then
				local badge = Instance.new("TextLabel")
				badge.AnchorPoint = Vector2.new(1, 0.5)
				badge.Position = UDim2.new(COL.name[2], -4, 0.5, 0)
				badge.Size = UDim2.new(0, 40, 0, 20)
				badge.BackgroundColor3 = GOLD
				badge.BackgroundTransparency = 0.1
				badge.Font = Enum.Font.GothamBold
				badge.TextSize = 14
				badge.TextColor3 = Color3.fromRGB(50, 32, 14)
				badge.TextTransparency = 0
				badge.TextStrokeTransparency = 1
				badge.Text = string.format("Lv %d", level)
				badge.ZIndex = 24
				badge.Parent = row
				local bc = Instance.new("UICorner")
				bc.CornerRadius = UDim.new(0, 8)
				bc.Parent = badge
			end

			buildExample(row, handName, dim)

			local valueText = string.format(
				'<font color="rgb(255,214,130)">%d</font> <font color="rgb(200,185,165)">x</font> <font color="rgb(240,100,75)">%d</font>',
				chips,
				mult
			)
			local valueLabel = addText(row, COL.value, valueText, 24, Enum.Font.GothamBold, CREAM, Enum.TextXAlignment.Center, 0, true)
			valueLabel.TextTransparency = dim and 0.3 or 0

			local playedLabel = addText(row, COL.played, string.format("%d", played), 18, Enum.Font.GothamBold, Color3.fromRGB(200, 220, 200), Enum.TextXAlignment.Right, 0, false)
			playedLabel.TextTransparency = dim and 0.5 or 0
		end

		fitRows()
		applyHighlight(HandHighlight.get())
	end

	HandHighlight.onChange(function(handName)
		if backdrop.Visible then
			applyHighlight(handName)
		end
	end)

	OverlayManager.register("pokerHandsReference", closePanel)

	handRefButton.MouseButton1Click:Connect(function()
		playClickSfx()
		OverlayManager.closeAllExcept("pokerHandsReference")
		refreshHandReference()
		popIn(backdrop, panel)
	end)

	return {}
end
