--[[
	Client/PokerHandsReference.lua
	The Poker Hands ledger board, opened from the in-game corner book button. Same carved-wood look as the Menu plaques (dark
	wood, brass studs, cream text, warm glow on hover), not the old ornate frame.

	  * Left: every hand from weakest to strongest as a wooden plaque: name, 5 mini example cards (scoring cards lit, kickers
	    dimmed), level, base Chips x Mult at its current level and times played this run. The tint runs wood, brass, gold, legend
	    (never red). A click selects a plaque.
	  * Right: the detail card for the selected hand: large example, the full score formula with the level bonus added, a tip,
	    plays this run and the lifetime total of hands. Hands never played say "Not played yet".
	  * Highlights: a laurel on the hand that has earned the most points this run (an estimate: plays x chips x mult), a soft
	    pulse on the hand you just played, an up arrow on hands a Recipe or House Pass levelled, and a gold glow on the hand the
	    selected cards make right now (Client/HandHighlight.lua).
	  * The panel eases up to 6px toward the cursor (off in calm mode and reduced motion). Phones stack the list over the detail.
	Data and layout math live in Engine/HandLedger.lua (unit tested). Closes with Back, Close, a click outside or Escape.

	deps fields: screenGui, polishPanel, polishButton, addSoftShadow, playClickSfx, handRefButton, HandEvaluator, Scoring,
	getLatestState, popIn, popOut, addButtonHoverScale (as before). Returns {}.
]]

return function(deps)
	local screenGui = deps.screenGui
	local playClickSfx = deps.playClickSfx
	local handRefButton = deps.handRefButton
	local HandEvaluator = deps.HandEvaluator
	local Scoring = deps.Scoring
	local getLatestState = deps.getLatestState
	local popIn = deps.popIn
	local popOut = deps.popOut
	local OverlayManager = require(script.Parent.OverlayManager)
	local HandHighlight = require(script.Parent.HandHighlight)
	local CardFace = require(script.Parent.CardFace)
	local Palette = require(script.Parent.Palette)
	local ClientSettings = require(script.Parent.ClientSettings)
	local UserInputService = game:GetService("UserInputService")
	local RunService = game:GetService("RunService")
	local TweenService = game:GetService("TweenService")
	local Engine = game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine")
	local HandLedger = require(Engine:WaitForChild("HandLedger"))
	local MenuLayout = require(Engine:WaitForChild("MenuLayout"))

	local CREAM = Color3.fromRGB(250, 240, 220)
	local CREAM_DIM = Color3.fromRGB(226, 208, 170)
	local GOLD = Color3.fromRGB(255, 214, 130)
	local BRASS = Color3.fromRGB(214, 172, 88)
	local WOOD = Color3.fromRGB(52, 36, 22)
	local WOOD_ROW = Color3.fromRGB(70, 48, 28)
	local SUIT_SYMBOLS = { Hearts = "♥", Diamonds = "♦", Clubs = "♣", Spades = "♠" }
	local RANK_TEXT = { [11] = "J", [12] = "Q", [13] = "K", [14] = "A" }
	local Z = 21

	local function calm()
		return ClientSettings.get("reduceShake") == true
	end
	local function rgb(t)
		return Color3.fromRGB(t[1], t[2], t[3])
	end

	local function text(parent, props)
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Font = props.font or Enum.Font.GothamBold
		l.TextSize = props.size or 16
		l.TextColor3 = props.color or CREAM
		l.TextTransparency = props.transparency or 0
		l.TextStrokeTransparency = 1
		l.TextXAlignment = props.align or Enum.TextXAlignment.Left
		l.TextTruncate = Enum.TextTruncate.AtEnd
		l.TextWrapped = props.wrapped == true
		l.RichText = props.rich == true
		l.Position = props.position or UDim2.new()
		l.Size = props.sizeUdim or UDim2.fromScale(1, 1)
		l.Text = props.text or ""
		l.ZIndex = props.z or Z + 2
		l.Parent = parent
		return l
	end

	local function studs(parent, z)
		for i = 1, 4 do
			local s = Instance.new("Frame")
			s.Name = "Stud"
			s.AnchorPoint = Vector2.new((i % 2 == 1) and 0 or 1, (i <= 2) and 0 or 1)
			s.Position = UDim2.new((i % 2 == 1) and 0 or 1, (i % 2 == 1) and 5 or -5, (i <= 2) and 0 or 1, (i <= 2) and 5 or -5)
			s.Size = UDim2.fromOffset(7, 7)
			s.BackgroundColor3 = BRASS
			s.BorderSizePixel = 0
			s.ZIndex = z
			s.Parent = parent
			local c = Instance.new("UICorner")
			c.CornerRadius = UDim.new(1, 0)
			c.Parent = s
		end
	end

	local function woodFrame(parent, color, z, radius)
		local f = Instance.new("Frame")
		f.BackgroundColor3 = color
		f.BorderSizePixel = 0
		f.ZIndex = z
		f.Parent = parent
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, radius or 10)
		c.Parent = f
		local s = Instance.new("UIStroke")
		s.Color = BRASS
		s.Thickness = 2
		s.Parent = f
		return f
	end

	-- ===== Shell =====
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

	local panel = woodFrame(backdrop, WOOD, Z, 16)
	panel.Name = "HandLedgerPanel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(900, 600)
	panel.Active = true -- swallow clicks so only the backdrop outside closes
	studs(panel, Z + 1)
	deps.addSoftShadow(panel, 18)

	text(panel, { text = "Poker Hands", size = 28, color = GOLD, align = Enum.TextXAlignment.Center,
		position = UDim2.new(0, 120, 0, 8), sizeUdim = UDim2.new(1, -240, 0, 36) })

	local function plaqueButton(label, position, anchor)
		local b = Instance.new("TextButton")
		b.AnchorPoint = anchor
		b.Position = position
		b.Size = UDim2.fromOffset(96, 34)
		b.AutoButtonColor = false
		b.BackgroundColor3 = WOOD_ROW
		b.Font = Enum.Font.GothamBold
		b.TextSize = 16
		b.TextColor3 = CREAM
		b.TextTransparency = 0
		b.TextStrokeTransparency = 1
		b.Text = label
		b.ZIndex = Z + 5
		b.Parent = panel
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, 7)
		c.Parent = b
		local s = Instance.new("UIStroke")
		s.Color = BRASS
		s.Thickness = 2
		s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		s.Parent = b
		b.MouseEnter:Connect(function() s.Color = GOLD end)
		b.MouseLeave:Connect(function() s.Color = BRASS end)
		return b
	end
	local backButton = plaqueButton("< Back", UDim2.fromOffset(14, 10), Vector2.new(0, 0))
	local closeButton = plaqueButton("Close", UDim2.new(1, -14, 0, 10), Vector2.new(1, 0))

	local listFrame = Instance.new("ScrollingFrame")
	listFrame.Name = "HandList"
	listFrame.BackgroundTransparency = 1
	listFrame.BorderSizePixel = 0
	listFrame.ScrollBarThickness = 6
	listFrame.ScrollBarImageColor3 = BRASS
	listFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	listFrame.CanvasSize = UDim2.new()
	listFrame.ZIndex = Z + 1
	listFrame.Parent = panel
	local listLayout = Instance.new("UIListLayout")
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Padding = UDim.new(0, 4)
	listLayout.Parent = listFrame

	local detail = woodFrame(panel, Color3.fromRGB(38, 26, 16), Z + 1, 12)
	detail.Name = "HandDetail"
	studs(detail, Z + 2)

	-- ===== Cards =====
	-- 5 mini example cards of a hand; scoring cards lit, kickers dimmed. Returns nothing.
	local function buildCards(parent, handName, cardW, cardH, gap, dimAll)
		local spec = HandEvaluator.Examples and HandEvaluator.Examples[handName]
		if not spec then return end
		local cards = {}
		for _, rs in ipairs(spec) do
			table.insert(cards, { rank = rs[1], suit = rs[2] })
		end
		local scoring = {}
		local ok, result = pcall(HandEvaluator.evaluate, cards)
		if ok and result then
			for _, c in ipairs(result.scoringCards) do scoring[c] = true end
		end
		local layout = Instance.new("UIListLayout")
		layout.FillDirection = Enum.FillDirection.Horizontal
		layout.VerticalAlignment = Enum.VerticalAlignment.Center
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Padding = UDim.new(0, gap)
		layout.Parent = parent
		for i, c in ipairs(cards) do
			local card = Instance.new("Frame")
			card.LayoutOrder = i
			card.Size = UDim2.fromOffset(cardW, cardH)
			card.BackgroundColor3 = Palette.colors.cardBase
			card.BackgroundTransparency = (dimAll or (ok and not scoring[c])) and 0.55 or 0
			card.BorderSizePixel = 0
			card.ZIndex = Z + 3
			card.Parent = parent
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0, 3)
			corner.Parent = card
			local stroke = Instance.new("UIStroke")
			stroke.Color = Color3.fromRGB(90, 60, 30)
			stroke.Thickness = 1
			stroke.Transparency = 0.3
			stroke.Parent = card
			CardFace.build(card, RANK_TEXT[c.rank] or tostring(c.rank), SUIT_SYMBOLS[c.suit], c.suit == "Hearts" or c.suit == "Diamonds", Z + 4, false)
		end
	end

	-- ===== State =====
	local ledger, selected = nil, nil
	local rowFrames = {} -- hand name -> row button
	local pulses = {}
	local currentLayout

	local function stopPulses()
		for _, t in ipairs(pulses) do t:Cancel() end
		pulses = {}
	end

	local function paintDetail()
		for _, child in ipairs(detail:GetChildren()) do
			if child:IsA("GuiObject") and child.Name ~= "Stud" then child:Destroy() end
		end
		local row
		for _, r in ipairs(ledger.rows) do
			if r.name == selected then row = r end
		end
		if not row then return end
		local d = currentLayout.detail
		local color = rgb(HandLedger.TIER_COLORS[row.tier])
		local stripe = Instance.new("Frame")
		stripe.Size = UDim2.new(1, -24, 0, 4)
		stripe.Position = UDim2.fromOffset(12, 46)
		stripe.BackgroundColor3 = color
		stripe.BorderSizePixel = 0
		stripe.ZIndex = Z + 3
		stripe.Parent = detail
		text(detail, { text = row.name .. (row.isTop and "  🏅" or ""), size = 24, color = GOLD,
			position = UDim2.fromOffset(14, 10), sizeUdim = UDim2.new(1, -28, 0, 32) })
		local cardH = math.clamp(math.floor(d.h * 0.2), 44, 84)
		local cardW = math.floor(cardH * 0.7)
		local cards = Instance.new("Frame")
		cards.BackgroundTransparency = 1
		cards.Position = UDim2.fromOffset(14, 58)
		cards.Size = UDim2.new(1, -28, 0, cardH)
		cards.ZIndex = Z + 2
		cards.Parent = detail
		buildCards(cards, row.name, cardW, cardH, 6, false)
		local y = 58 + cardH + 10
		local function line(textValue, color2, size)
			text(detail, { text = textValue, size = size or 16, color = color2 or CREAM, font = Enum.Font.GothamMedium,
				position = UDim2.fromOffset(14, y), sizeUdim = UDim2.new(1, -28, 0, 22) })
			y = y + 24
		end
		line(row.chipsFormula)
		line(row.multFormula)
		line(string.format("Score: %d x %d = %d per hand", row.chips, row.mult, row.chips * row.mult), GOLD, 18)
		y = y + 6
		if row.notPlayed then
			line("Not played yet", CREAM_DIM)
		else
			line(string.format("Played this run: %d", row.played))
		end
		line(string.format("Lifetime: %d hands of every kind", ledger.lifetimeHands), CREAM_DIM)
		y = y + 6
		text(detail, { text = row.tip, size = 16, color = CREAM_DIM, font = Enum.Font.Gotham, wrapped = true,
			position = UDim2.fromOffset(14, y), sizeUdim = UDim2.new(1, -28, 0, math.max(40, d.h - y - 10)) })
		if row.leveled then
			text(detail, { text = "▲ Level " .. row.level, size = 16, color = GOLD, align = Enum.TextXAlignment.Right,
				position = UDim2.new(1, -150, 0, 10), sizeUdim = UDim2.fromOffset(136, 32) })
		end
	end

	local function paintSelection()
		for name, button in pairs(rowFrames) do
			local stroke = button:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Color = (name == selected) and GOLD or BRASS
				stroke.Thickness = (name == selected) and 3 or 1.5
			end
		end
	end

	local function applyHighlight(handName)
		for name, button in pairs(rowFrames) do
			local lit = name == handName
			button.BackgroundColor3 = lit and Color3.fromRGB(104, 76, 38) or WOOD_ROW
		end
	end

	local function buildRows()
		stopPulses()
		for _, child in ipairs(listFrame:GetChildren()) do
			if child:IsA("GuiObject") then child:Destroy() end
		end
		rowFrames = {}
		local L = currentLayout
		local rowW = L.list.w - 10
		local cardH = math.floor(L.rowH * 0.7)
		local cardW = math.floor(cardH * 0.7)
		for i, row in ipairs(ledger.rows) do
			local button = Instance.new("TextButton")
			button.Name = "Row_" .. row.name
			button.LayoutOrder = i -- weakest at the top
			button.Size = UDim2.new(1, -10, 0, L.rowH)
			button.AutoButtonColor = false
			button.BackgroundColor3 = WOOD_ROW
			button.Text = ""
			button.ZIndex = Z + 2
			button.Parent = listFrame
			local c = Instance.new("UICorner")
			c.CornerRadius = UDim.new(0, 8)
			c.Parent = button
			local stroke = Instance.new("UIStroke")
			stroke.Color = BRASS
			stroke.Thickness = 1.5
			stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			stroke.Parent = button
			local tint = Instance.new("Frame") -- strength tint on the left edge
			tint.Size = UDim2.new(0, 8, 1, -8)
			tint.Position = UDim2.fromOffset(4, 4)
			tint.BackgroundColor3 = rgb(HandLedger.TIER_COLORS[row.tier])
			tint.BorderSizePixel = 0
			tint.ZIndex = Z + 3
			tint.Parent = button
			local tc = Instance.new("UICorner")
			tc.CornerRadius = UDim.new(0, 4)
			tc.Parent = tint
			local dimT = row.notPlayed and 0.35 or 0
			local nameW = math.floor(rowW * 0.30)
			text(button, { text = (row.isTop and "🏅 " or "") .. row.name, size = 17, transparency = dimT,
				position = UDim2.fromOffset(18, 0), sizeUdim = UDim2.new(0, nameW - 18, 1, 0) })
			if row.leveled then
				text(button, { text = "▲" .. row.level, size = 14, color = GOLD,
					position = UDim2.fromOffset(18, L.rowH - 20), sizeUdim = UDim2.fromOffset(60, 18), z = Z + 4 })
			end
			local cards = Instance.new("Frame")
			cards.BackgroundTransparency = 1
			cards.Position = UDim2.fromOffset(nameW, 0)
			cards.Size = UDim2.fromOffset(math.floor(rowW * 0.36), L.rowH)
			cards.ZIndex = Z + 3
			cards.Parent = button
			buildCards(cards, row.name, cardW, cardH, 3, row.notPlayed)
			text(button, { rich = true, size = 20, align = Enum.TextXAlignment.Center, transparency = row.notPlayed and 0.25 or 0,
				text = string.format('<font color="rgb(255,214,130)">%d</font> <font color="rgb(200,185,165)">x</font> <font color="rgb(150,215,255)">%d</font>', row.chips, row.mult),
				position = UDim2.fromOffset(nameW + math.floor(rowW * 0.36), 0), sizeUdim = UDim2.new(0, math.floor(rowW * 0.22), 1, 0) })
			text(button, { text = row.notPlayed and "-" or tostring(row.played), size = 18, color = Color3.fromRGB(200, 220, 200), align = Enum.TextXAlignment.Right,
				position = UDim2.new(1, -62, 0, 0), sizeUdim = UDim2.fromOffset(52, L.rowH) })
			rowFrames[row.name] = button
			button.MouseEnter:Connect(function() stroke.Color = GOLD end)
			button.MouseLeave:Connect(function() paintSelection() end)
			button.MouseButton1Click:Connect(function()
				playClickSfx(0.2)
				selected = row.name
				paintSelection()
				paintDetail()
			end)
			if row.justPlayed and not calm() then -- soft pulse on the hand you just played
				local t = TweenService:Create(stroke, TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Thickness = 4 })
				t:Play()
				table.insert(pulses, t)
			end
		end
	end

	local function applyLayout()
		local v = screenGui.AbsoluteSize
		if v.X <= 0 then v = Vector2.new(1280, 720) end
		currentLayout = HandLedger.layout(v.X, v.Y, #HandEvaluator.HandOrder)
		local L = currentLayout
		panel.Size = UDim2.fromOffset(L.panel.w, L.panel.h)
		listFrame.Position = UDim2.fromOffset(L.list.x, L.list.y)
		listFrame.Size = UDim2.fromOffset(L.list.w, L.list.h)
		detail.Position = UDim2.fromOffset(L.detail.x, L.detail.y)
		detail.Size = UDim2.fromOffset(L.detail.w, L.detail.h)
	end

	local function refresh()
		applyLayout()
		local state = getLatestState()
		ledger = HandLedger.build({
			order = HandEvaluator.HandOrder, base = Scoring.HandBase, growth = Scoring.HandLevelGrowth,
			handStats = state and state.handStats, handLevels = state and state.handLevels,
			lastHand = state and state.lastHand and state.lastHand.name,
			lifetimeHands = state and state.runStats and state.runStats.hands,
		})
		buildRows()
		if not selected or not rowFrames[selected] then
			selected = HandLedger.defaultSelection(ledger, HandHighlight.get())
		end
		paintSelection()
		paintDetail()
		applyHighlight(HandHighlight.get())
	end

	-- ===== Open / close =====
	local parallaxConn
	local function stopEase()
		if parallaxConn then
			parallaxConn:Disconnect()
			parallaxConn = nil
		end
		panel.Position = UDim2.fromScale(0.5, 0.5)
		stopPulses()
	end
	local function startEase()
		if parallaxConn then return end
		local sx, sy = 0, 0
		parallaxConn = RunService.RenderStepped:Connect(function(dt)
			local nx, ny = 0, 0
			if not calm() and UserInputService.MouseEnabled then
				local m, size = UserInputService:GetMouseLocation(), screenGui.AbsoluteSize
				if size.X > 0 and size.Y > 0 then
					nx, ny = MenuLayout.clamp(m.X / size.X * 2 - 1, -1, 1), MenuLayout.clamp(m.Y / size.Y * 2 - 1, -1, 1)
				end
			end
			local a = 1 - (1 - 0.08) ^ math.min(4, dt * 60)
			sx, sy = sx + (nx - sx) * a, sy + (ny - sy) * a
			local dx, dy = MenuLayout.parallaxOffset(sx, sy, 6, calm())
			panel.Position = UDim2.new(0.5, dx, 0.5, dy)
		end)
	end

	local function closePanel()
		if backdrop.Visible then
			stopEase()
			popOut(backdrop, panel)
		end
	end
	local function openPanel()
		playClickSfx()
		OverlayManager.closeAllExcept("pokerHandsReference")
		selected = nil -- the detail card starts on the hand the selected cards make, or the one just played
		refresh()
		popIn(backdrop, panel)
		startEase()
	end
	backButton.MouseButton1Click:Connect(function()
		playClickSfx()
		closePanel()
	end)
	require(script.Parent.CloseX).retire(closeButton) -- the round X replaces the Close plaque
	require(script.Parent.CloseX).attach(panel, function()
		playClickSfx()
		closePanel()
	end)
	backdrop.MouseButton1Click:Connect(closePanel)
	-- Escape goes through Client/PopupDismiss like every other popup (it ignores gameProcessed, as this always did); the click
	-- on the dim area stays this panel's own (the backdrop is a button).
	require(script.Parent.PopupDismiss).attach(backdrop, { id = "pokerHandsReference", panel = panel, outside = false, button = true })
	HandHighlight.onChange(function(handName)
		if backdrop.Visible and ledger then
			applyHighlight(handName)
		end
	end)
	screenGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		if backdrop.Visible and ledger then refresh() end
	end)

	OverlayManager.register("pokerHandsReference", closePanel)
	OverlayManager.registerOpener("pokerHandsReference", openPanel)
	handRefButton.MouseButton1Click:Connect(openPanel)

	return {}
end
