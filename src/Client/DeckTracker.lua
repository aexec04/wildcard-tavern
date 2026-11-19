--[[
	Client/DeckTracker.lua
	"Your Deck": every card in the run's deck as a small real card face, in four
	suit rows by rank (sort toggle High to Low / Low to High). Opened by
	clicking the deck pile.

	Card states (from state.deckView, built by RunState.deckView; only
	membership is sent, never the draw order):
	  draw       full color
	  hand       full color, gold outline, small hand badge
	  played     dimmed grey with a check
	  discarded  dimmed grey with an x
	Cards with a Garnish / Special / Stamp keep a tint and tiny icons. The
	hidden True Wildcard shows as a "?" back.

	Filter chips: All, Left in deck, In hand, Used. Counter: "N left of M".
	Hovering a card lifts it and shows "Queen of Hearts" in the caption line.
	The fan-in on open is skipped on the Fast setting and under Reduce shake.

	deps: screenGui, polishPanel, polishButton, roundCorner, addSoftShadow,
	playClickSfx, deckWidgetButton, Deck, RANK_NAMES, SUIT_SYMBOLS,
	SUIT_DISPLAY_ORDER, RED_SUITS, getLatestState, popIn, popOut,
	addButtonHoverScale.

	Returns: {}
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

return function(deps)
	local screenGui = deps.screenGui
	local polishPanel = deps.polishPanel
	local polishButton = deps.polishButton
	local roundCorner = deps.roundCorner
	local addSoftShadow = deps.addSoftShadow
	local playClickSfx = deps.playClickSfx
	local deckWidgetButton = deps.deckWidgetButton
	local SUIT_SYMBOLS = deps.SUIT_SYMBOLS
	local SUIT_DISPLAY_ORDER = deps.SUIT_DISPLAY_ORDER
	local RED_SUITS = deps.RED_SUITS
	local RANK_NAMES = deps.RANK_NAMES
	local getLatestState = deps.getLatestState
	local popIn = deps.popIn
	local popOut = deps.popOut
	local addButtonHoverScale = deps.addButtonHoverScale
	local OverlayManager = require(script.Parent.OverlayManager)
	local CardFace = require(script.Parent.CardFace)
	local ClientSettings = require(script.Parent.ClientSettings)
	local Palette = require(script.Parent.Palette)
	local Card = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("Card"))

	local CREAM = Color3.fromRGB(250, 240, 220)
	local SOFT_CREAM = Color3.fromRGB(215, 200, 178)
	local GOLD = Color3.fromRGB(222, 182, 104)
	local BROWN = Color3.fromRGB(70, 55, 40)
	local ACTIVE_BROWN = Color3.fromRGB(150, 115, 50)
	local RANK_FULL = Card.RankNames

	local FILTERS = {
		{ id = "all", name = "All" },
		{ id = "draw", name = "Left in deck" },
		{ id = "hand", name = "In hand" },
		{ id = "used", name = "Used" },
	}

	local backdrop = Instance.new("Frame")
	backdrop.Name = "DeckTrackerBackdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	backdrop.BackgroundTransparency = 0.4
	backdrop.Visible = false
	backdrop.ZIndex = 20
	backdrop.Parent = screenGui

	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Size = UDim2.fromScale(0.88, 0.88)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.BackgroundColor3 = Color3.fromRGB(40, 30, 22)
	panel.ZIndex = 21
	panel.Parent = backdrop
	polishPanel(panel, 16, "parchment")
	addSoftShadow(panel, 18)

	local function label(parent, props)
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Font = Enum.Font.GothamBold
		l.TextColor3 = CREAM
		l.TextStrokeTransparency = 1
		l.ZIndex = 22
		for k, v in pairs(props) do
			l[k] = v
		end
		l.Parent = parent
		return l
	end

	local function button(parent, props)
		local b = Instance.new("TextButton")
		b.Font = Enum.Font.GothamBold
		b.TextColor3 = CREAM
		b.BackgroundColor3 = BROWN
		b.AutoButtonColor = true
		b.TextSize = 15
		b.ZIndex = 22
		for k, v in pairs(props) do
			b[k] = v
		end
		b.Parent = parent
		return b
	end

	local titleLabel = label(panel, {
		Size = UDim2.new(1, 0, 0, 34), Position = UDim2.fromOffset(0, 6),
		TextSize = 24, Text = "Your Deck",
	})
	-- Gameplay v2: the panel wears the TavernKit look (plate colours with a gold trim, serif title, kit buttons); the old look stays on the v1 archive
	local Engine = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine")
	local Kit = require(script.Parent.TavernKit)
	local TavernStyle = require(Engine:WaitForChild("TavernStyle"))
	local function v2() return require(Engine:WaitForChild("FeatureFlags")).gameplay() == 2 end

	-- Controls row: filter chips on the left, counter and sort toggle on the right.
	local controls = Instance.new("Frame")
	controls.Size = UDim2.new(1, -30, 0, 44)
	controls.Position = UDim2.fromOffset(15, 44)
	controls.BackgroundTransparency = 1
	controls.ZIndex = 22
	controls.Parent = panel

	local chipLayout = Instance.new("UIListLayout")
	chipLayout.FillDirection = Enum.FillDirection.Horizontal
	chipLayout.SortOrder = Enum.SortOrder.LayoutOrder
	chipLayout.Padding = UDim.new(0, 6)
	chipLayout.Parent = controls

	local chipButtons = {}
	local activeFilter = "all"
	local sortDescending = true

	local counterLabel = label(controls, {
		LayoutOrder = 10, Size = UDim2.fromOffset(150, 44), TextSize = 17, TextColor3 = GOLD,
		Text = "", TextXAlignment = Enum.TextXAlignment.Center,
	})
	local sortButton = button(controls, {
		LayoutOrder = 11, Size = UDim2.fromOffset(140, 44), Text = "High to Low",
	})
	polishButton(sortButton, 8)
	addButtonHoverScale(sortButton)

	local nextDrawLabel = label(panel, {
		Size = UDim2.new(1, -30, 0, 22), Position = UDim2.fromOffset(15, 92),
		TextSize = 15, Font = Enum.Font.Gotham, TextColor3 = SOFT_CREAM, Text = "",
		TextXAlignment = Enum.TextXAlignment.Left,
	})

	local scroll = Instance.new("ScrollingFrame")
	scroll.Size = UDim2.new(1, -30, 1, -196)
	scroll.Position = UDim2.fromOffset(15, 118)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 8
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.ZIndex = 22
	scroll.Parent = panel

	local rowsLayout = Instance.new("UIListLayout")
	rowsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rowsLayout.Padding = UDim.new(0, 8)
	rowsLayout.Parent = scroll
	local scrollPad = Instance.new("UIPadding")
	scrollPad.PaddingTop = UDim.new(0, 8) -- room for the hover lift
	scrollPad.PaddingBottom = UDim.new(0, 8)
	scrollPad.Parent = scroll

	local captionLabel = label(panel, {
		Size = UDim2.new(1, -300, 0, 28), Position = UDim2.new(0, 15, 1, -50),
		TextSize = 18, Text = "", TextXAlignment = Enum.TextXAlignment.Left,
	})

	local closeButton = button(panel, {
		Size = UDim2.fromOffset(140, 44), Position = UDim2.new(1, -155, 1, -54), TextSize = 16,
		Text = "Close", BackgroundColor3 = Color3.fromRGB(90, 60, 30),
	})
	polishButton(closeButton, 12)
	addButtonHoverScale(closeButton)
	if v2() then
		local pc = TavernStyle.rgb("plateFill")
		panel.BackgroundColor3 = Color3.fromRGB(pc[1], pc[2], pc[3])
		local gt = TavernStyle.rgb("goldTrim")
		local trim = Instance.new("UIStroke")
		trim.Name = "KitTrim"
		trim.Color = Color3.fromRGB(gt[1], gt[2], gt[3])
		trim.Thickness = 2
		trim.Parent = panel
		titleLabel.Font = Enum.Font[TavernStyle.FONTS.title]
		pcall(Kit.skin, sortButton, nil, "secondary")
		pcall(Kit.skin, closeButton, nil, "secondary")
	end
	require(script.Parent.CloseX).retire(closeButton)
	require(script.Parent.CloseX).attach(panel, function()
		playClickSfx()
		popOut(backdrop, panel)
	end)

	-- ===== Card building =====
	local function statusMatches(status, filter)
		if filter == "all" then
			return true
		elseif filter == "draw" then
			return status == "draw"
		elseif filter == "hand" then
			return status == "hand"
		end
		return status == "played" or status == "discarded"
	end

	local function tintFor(entry)
		local tint = nil
		if entry.garnish then
			tint = Color3.fromRGB(255, 232, 170)
		elseif entry.special then
			tint = Color3.fromRGB(200, 225, 255)
		elseif entry.stamp then
			tint = Color3.fromRGB(255, 205, 205)
		end
		return tint
	end

	local function iconsFor(entry)
		local icons = {}
		local g = entry.garnish and Card.Garnishes[entry.garnish]
		local s = entry.special and Card.Specials[entry.special]
		local m = entry.stamp and Card.Stamps[entry.stamp]
		if g and g.icon then table.insert(icons, g.icon) end
		if s and s.icon then table.insert(icons, s.icon) end
		if m and m.icon then table.insert(icons, m.icon) end
		return table.concat(icons)
	end

	local function captionFor(entry)
		if entry.hidden then
			return "A mystery card (the True Wildcard)"
		end
		local text = (RANK_FULL[entry.rank] or tostring(entry.rank)) .. " of " .. tostring(entry.suit)
		local extras = {}
		local g = entry.garnish and Card.Garnishes[entry.garnish]
		local s = entry.special and Card.Specials[entry.special]
		local m = entry.stamp and Card.Stamps[entry.stamp]
		if g then table.insert(extras, g.name) end
		if s then table.insert(extras, s.name) end
		if m then table.insert(extras, m.name) end
		if #extras > 0 then
			text = text .. "  (" .. table.concat(extras, ", ") .. ")"
		end
		return text
	end

	local function makeCard(parent, entry, width, height)
		local card = Instance.new("TextButton")
		card.Text = ""
		card.AutoButtonColor = false
		card.Size = UDim2.fromOffset(width, height)
		card.BorderSizePixel = 0
		card.ZIndex = 23
		card.Parent = parent
		roundCorner(card, 6)
		local scale = Instance.new("UIScale")
		scale.Parent = card

		local used = entry.status == "played" or entry.status == "discarded"
		if entry.hidden then
			card.BackgroundColor3 = Color3.fromRGB(46, 62, 110)
			label(card, {
				Size = UDim2.fromScale(1, 1), TextSize = math.floor(height * 0.5), ZIndex = 24,
				Text = "?", TextColor3 = GOLD,
			})
			local edge = Instance.new("UIStroke")
			edge.Color = GOLD
			edge.Thickness = 1.5
			edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			edge.Parent = card
		else
			local base = Palette.colors.cardBase
			local tint = tintFor(entry)
			card.BackgroundColor3 = tint and base:Lerp(tint, 0.45) or base
			local edge = Instance.new("UIStroke")
			edge.Color = Color3.fromRGB(90, 60, 30)
			edge.Thickness = 1
			edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			edge.Parent = card
			CardFace.build(
				card,
				RANK_NAMES[entry.rank] or tostring(entry.rank),
				SUIT_SYMBOLS[entry.suit] or "?",
				RED_SUITS[entry.suit] == true,
				24,
				false,
				entry
			)
			-- special cards (Garnish / Special / Stamp) glow so the player can see where they are in the deck
			if entry.garnish or entry.special or entry.stamp then
				local glow = Instance.new("UIStroke")
				glow.Name = "SpecialGlow"
				glow.Color = Color3.fromRGB(255, 226, 140)
				glow.Thickness = 2.5
				glow.Transparency = 0.2
				glow.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
				if card:FindFirstChildOfClass("UIStroke") and card:FindFirstChildOfClass("UIStroke").Name ~= "SpecialGlow" then
					-- the card already carries its own edge stroke: put the glow on an overlay frame instead
					local ring = Instance.new("Frame")
					ring.Name = "SpecialGlowRing"
					ring.Size = UDim2.fromScale(1, 1)
					ring.BackgroundTransparency = 1
					ring.BorderSizePixel = 0
					ring.Active = false
					ring.ZIndex = 25
					ring.Parent = card
					local rc = Instance.new("UICorner")
					rc.CornerRadius = UDim.new(0, 6)
					rc.Parent = ring
					glow.Parent = ring
				else
					glow.Parent = card
				end
			end
			local icons = iconsFor(entry)
			if icons ~= "" then
				label(card, {
					Size = UDim2.new(1, -4, 0, 18), Position = UDim2.new(0, 2, 1, -20), ZIndex = 26,
					TextSize = 15, Text = icons, TextStrokeTransparency = 1,
				})
			end
		end

		if entry.status == "hand" then
			local ring = Instance.new("UIStroke")
			ring.Name = "HandRing"
			ring.Color = GOLD
			ring.Thickness = 3
			ring.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			ring.Parent = card
			label(card, {
				Size = UDim2.fromOffset(22, 22), Position = UDim2.new(1, -23, 0, 1), ZIndex = 27,
				TextSize = 15, Text = "✋",
			})
		elseif used then
			local shade = Instance.new("Frame")
			shade.Size = UDim2.fromScale(1, 1)
			shade.BackgroundColor3 = Color3.fromRGB(70, 70, 74)
			shade.BackgroundTransparency = 0.35
			shade.BorderSizePixel = 0
			shade.Active = false
			shade.ZIndex = 28
			shade.Parent = card
			roundCorner(shade, 6)
			label(shade, {
				Size = UDim2.fromScale(1, 1), ZIndex = 29, TextSize = math.max(18, math.floor(height * 0.34)),
				Text = entry.status == "played" and "✓" or "✕",
				TextColor3 = entry.status == "played" and Color3.fromRGB(150, 235, 160) or Color3.fromRGB(240, 150, 150),
			})
		end

		card.MouseEnter:Connect(function()
			TweenService:Create(scale, TweenInfo.new(0.12, Enum.EasingStyle.Quad), { Scale = 1.14 }):Play()
			captionLabel.Text = captionFor(entry)
		end)
		card.MouseLeave:Connect(function()
			TweenService:Create(scale, TweenInfo.new(0.12, Enum.EasingStyle.Quad), { Scale = 1 }):Play()
			if captionLabel.Text == captionFor(entry) then
				captionLabel.Text = ""
			end
		end)
		return card, scale
	end

	-- ===== Refresh =====
	local function suitRank(entry)
		return entry.rank or 0
	end

	local function refresh()
		for _, child in ipairs(scroll:GetChildren()) do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		captionLabel.Text = ""

		local state = getLatestState()
		local view = state and state.deckView or {}

		-- Counters and the optional "next draw" line.
		local total, left = #view, 0
		local suitLeft = {}
		for _, entry in ipairs(view) do
			if entry.status == "draw" then
				left = left + 1
				if entry.suit then
					suitLeft[entry.suit] = (suitLeft[entry.suit] or 0) + 1
				end
			end
		end
		counterLabel.Text = string.format("%d left of %d", math.floor(left), math.floor(total))
		local bestSuit, bestCount = nil, 0
		for _, suit in ipairs(SUIT_DISPLAY_ORDER) do
			if (suitLeft[suit] or 0) > bestCount then
				bestSuit, bestCount = suit, suitLeft[suit]
			end
		end
		if bestSuit and left > 0 then
			nextDrawLabel.Text = string.format(
				"Next draw: %d percent %s (most likely suit)", math.floor(bestCount * 100 / left + 0.5), bestSuit
			)
		else
			nextDrawLabel.Text = left == 0 and "The draw pile is empty." or ""
		end

		-- Group by suit, filter, sort.
		local bySuit = {}
		local maxPerSuit = 1
		for _, suit in ipairs(SUIT_DISPLAY_ORDER) do
			bySuit[suit] = {}
		end
		local hiddenCards = {}
		for _, entry in ipairs(view) do
			if statusMatches(entry.status, activeFilter) then
				if entry.hidden then
					table.insert(hiddenCards, entry)
				elseif bySuit[entry.suit] then
					table.insert(bySuit[entry.suit], entry)
				end
			end
		end
		for _, suit in ipairs(SUIT_DISPLAY_ORDER) do
			table.sort(bySuit[suit], function(a, b)
				if suitRank(a) ~= suitRank(b) then
					if sortDescending then
						return suitRank(a) > suitRank(b)
					end
					return suitRank(a) < suitRank(b)
				end
				return a.status < b.status
			end)
			maxPerSuit = math.max(maxPerSuit, #bySuit[suit])
		end

		-- Card size: about 70px wide, shrinking so a 13-card row always fits.
		local availableWidth = math.max(300, panel.AbsoluteSize.X - 60 - 16)
		local perRow = math.max(13, maxPerSuit)
		local width = math.clamp(math.floor((availableWidth - (perRow - 1) * 4) / perRow), 44, 70)
		local height = math.floor(width * 1.4)

		local animate = ClientSettings.get("animSpeed") ~= "fast" and not ClientSettings.get("reduceShake")
		local order, shown = 0, 0
		local function addRow(entries, rowLabel)
			if #entries == 0 then
				return
			end
			order = order + 1
			local row = Instance.new("Frame")
			row.LayoutOrder = order
			row.AutomaticSize = Enum.AutomaticSize.Y
			row.Size = UDim2.new(1, -12, 0, height)
			row.BackgroundTransparency = 1
			row.ZIndex = 22
			row.Parent = scroll
			local grid = Instance.new("UIGridLayout")
			grid.CellSize = UDim2.fromOffset(width, height)
			grid.CellPadding = UDim2.fromOffset(4, 4)
			grid.SortOrder = Enum.SortOrder.LayoutOrder
			grid.Parent = row
			for i, entry in ipairs(entries) do
				local card, scale = makeCard(row, entry, width, height)
				card.LayoutOrder = i
				shown = shown + 1
				if animate then
					scale.Scale = 0.4
					card.Visible = false
					task.delay(shown * 0.008, function()
						if card.Parent then
							card.Visible = true
							TweenService:Create(scale, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
								Scale = 1,
							}):Play()
						end
					end)
				end
			end
		end
		for _, suit in ipairs(SUIT_DISPLAY_ORDER) do
			addRow(bySuit[suit], suit)
		end
		addRow(hiddenCards, "?")

		if shown == 0 then
			label(scroll, {
				Size = UDim2.new(1, 0, 0, 60), TextSize = 18, TextColor3 = SOFT_CREAM,
				Text = total == 0 and "No deck data yet." or "No cards match this filter.",
			})
		end

		for _, filter in ipairs(FILTERS) do
			if v2() then
				local kind = filter.id == activeFilter and "primary" or "secondary" -- the open filter is the green plate
				if chipButtons[filter.id]:GetAttribute("TavernKind") ~= kind then pcall(Kit.skin, chipButtons[filter.id], nil, kind) end
			else
				chipButtons[filter.id].BackgroundColor3 = filter.id == activeFilter and ACTIVE_BROWN or BROWN
			end
		end
		sortButton.Text = sortDescending and "High to Low" or "Low to High"
	end

	for i, filter in ipairs(FILTERS) do
		local chip = button(controls, {
			LayoutOrder = i, Size = UDim2.fromOffset(filter.id == "draw" and 132 or 96, 44), Text = filter.name,
		})
		polishButton(chip, 8)
		chipButtons[filter.id] = chip
		chip.MouseButton1Click:Connect(function()
			playClickSfx()
			if activeFilter ~= filter.id then
				activeFilter = filter.id
				refresh()
			end
		end)
	end
	sortButton.MouseButton1Click:Connect(function()
		playClickSfx()
		sortDescending = not sortDescending
		refresh()
	end)

	OverlayManager.register("deckTracker", function()
		popOut(backdrop, panel)
	end)
	-- Escape and a click on the dark area close it (Client/PopupDismiss); the deck pile still toggles it.
	require(script.Parent.PopupDismiss).attach(backdrop, { id = "deckTracker", panel = panel, button = true })

	deckWidgetButton.MouseButton1Click:Connect(function()
		playClickSfx()
		OverlayManager.closeAllExcept("deckTracker")
		activeFilter = v2() and "draw" or "all" -- the table's deck viewer opens on what is still left to draw
		scroll.CanvasPosition = Vector2.new(0, 0)
		popIn(backdrop, panel)
		task.defer(refresh) -- after popIn so panel.AbsoluteSize is real
	end)

	return {}
end
