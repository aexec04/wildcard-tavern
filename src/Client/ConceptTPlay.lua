--[[
	Client/ConceptTPlay.lua
	The Concept T play screen: the painted tavern room as the full screen background, blank HUD plates with live numbers
	(coins, hands, round and its gold bar, deck count), the gear, the deck pile and image buttons for Play Hand and Discard.
	Rects come from Engine/ConceptTLayout (pure, tested). The real buttons (Play Hand, Discard, the deck's click catcher and the
	Settings corner button) keep every handler: they are only moved onto the painted pieces and made see-through, so keys,
	hit areas and the InputGuard / PopupShield rules stay as they were. Everything else of the old play screen (left board, corner
	icons, drawer strip, felt shade) is hidden while the screen is up; run info and options live behind the gear (Settings).
	Active only in phase "playing" on screens of at least 640 x 360; phones and smaller keep the old play screen.

	install{ root, handFrame, actionFrame, playButton, discardButton, deckWidget, settingsButton, getState } -> { update(state), isActive() }
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Engine = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine")
local Layout = require(Engine:WaitForChild("ConceptTLayout"))
local Art = require(Engine:WaitForChild("ConceptTArt"))
local DeckCountText = require(Engine:WaitForChild("DeckCountText"))
local PlayMotion = require(Engine:WaitForChild("PlayMotion"))
local LayoutSwitch = require(script.Parent.LayoutSwitch)

local M = {}
local current = nil

local INK = Color3.fromRGB(255, 244, 214) -- cream on the dark wood plates, well over 4.5:1
local OUTLINE = Color3.fromRGB(40, 22, 10)
local GOLD = Color3.fromRGB(246, 196, 70)
local HIDE = { "Sidebar", "SidebarBoard", "EdgeShadow", "PlayBoardPaint", "PlayBoardPaintBand", "PlayBoardPaintCap", "PlayBoardFiller", "BlessingChip", "PlayFeltShade", "PlayTableFront", "PlayTableBg", "PlayFloorShade", "HandRailLip", "PlayGrooveLip", "PlayRailBack", "PlayRailFront" }

local function image(parent, name, key, z)
	local img = Instance.new("ImageLabel")
	img.Name = name
	img.BackgroundTransparency = 1
	img.BorderSizePixel = 0
	img.Active = false
	img.Image = Art[key] or ""
	img.ScaleType = Enum.ScaleType.Stretch
	img.ZIndex = z
	img.Parent = parent
	return img
end

local function text(parent, name, size, z)
	local t = Instance.new("TextLabel")
	t.Name = name
	t.BackgroundTransparency = 1
	t.Font = Enum.Font.GothamBlack
	t.TextSize = size
	t.TextColor3 = INK
	t.TextTransparency = 0
	t.TextStrokeColor3 = OUTLINE
	t.TextStrokeTransparency = 0.2
	t.TextScaled = false
	t.ZIndex = z
	t.Parent = parent
	return t
end

local function place(g, r)
	g.Position = UDim2.fromOffset(r.x, r.y)
	g.Size = UDim2.fromOffset(r.w, r.h)
end

local function clearButton(b)
	b.BackgroundTransparency = 1
	b.TextTransparency = 1
	b.TextStrokeTransparency = 1
	for _, c in ipairs(b:GetChildren()) do
		if c:IsA("GuiObject") then c.Visible = false
		elseif c:IsA("UIStroke") then c.Enabled = false end
	end
end

function M.install(deps)
	local root = deps.root
	local layer = Instance.new("Frame")
	layer.Name = "ConceptTPlay"
	layer.BackgroundTransparency = 1
	layer.BorderSizePixel = 0
	layer.Size = UDim2.fromScale(1, 1)
	layer.ZIndex = 1
	layer.Visible = false
	layer.Active = false
	layer.Parent = root

	local room = image(layer, "Room", "ct_table_room", 0)
	room.Size = UDim2.fromScale(1, 1)
	room.ScaleType = Enum.ScaleType.Crop
	local coins = image(layer, "Coins", "ct_hud_coins", 2)
	local hands = image(layer, "Hands", "ct_hud_hands", 2)
	local round = image(layer, "Round", "ct_hud_round", 2)
	local gear = image(layer, "Gear", "ct_hud_gear", 2)
	local deck = image(layer, "Deck", "ct_deck_a", 2)
	local deckCount = image(layer, "DeckCount", "ct_deck_count", 2)
	local play = image(layer, "PlayArt", "ct_btn_play_a", 2)
	local discard = image(layer, "DiscardArt", "ct_btn_discard_a", 2)
	local coinsText = text(layer, "CoinsText", 20, 3)
	local handsText = text(layer, "HandsText", 20, 3)
	local roundText = text(layer, "RoundText", 18, 3)
	-- the banner title is a warm cream serif, not the heavy HUD face
	roundText.FontFace = Font.new("rbxasset://fonts/families/Merriweather.json", Enum.FontWeight.Bold)
	roundText.TextColor3 = Color3.fromRGB(Layout.ROUND_TEXT.r, Layout.ROUND_TEXT.g, Layout.ROUND_TEXT.b)
	roundText.TextStrokeTransparency = 0.6
	local deckText = text(layer, "DeckText", 18, 3)
	local fill = Instance.new("Frame")
	fill.Name = "BarFill"
	fill.BackgroundColor3 = GOLD
	fill.BorderSizePixel = 0
	fill.ZIndex = 3
	fill.Parent = layer
	local fc = Instance.new("UICorner")
	fc.CornerRadius = UDim.new(1, 0)
	fc.Parent = fill
	-- subtle highlight: one Color-only gradient, lighter on top (never Transparency)
	local fg = Instance.new("UIGradient")
	fg.Rotation = 90
	fg.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 226, 120)), ColorSequenceKeypoint.new(0.5, GOLD), ColorSequenceKeypoint.new(1, Color3.fromRGB(214, 150, 40)) })
	fg.Parent = fill

	local active, lastState = false, nil
	local hiddenDeck = {} -- old deck widget pieces this screen hid, given back when it leaves
	local sortHost = nil -- the Rank | Suit frame this screen restyled, given back when it leaves
	local function restoreOld()
		for c in pairs(hiddenDeck) do c.Visible = true end
		hiddenDeck = {}
		if sortHost and sortHost.Parent then
			local sf = sortHost
			sortHost = nil
			LayoutSwitch.on(sf)
			sf.Size = UDim2.new(0, 214, 1, 0)
			sf.Position = UDim2.new()
			for _, k in ipairs(sf:GetChildren()) do
				if k.Name == "PlatePaint" and k:IsA("GuiObject") then k.Visible = true
				elseif k:IsA("TextLabel") then k.Visible = true
				elseif k.Name == "SortToggle" then
					k:SetAttribute("Flat", false)
					k.Size = UDim2.fromOffset(132, 28)
				end
			end
		end
		local row = root:FindFirstChild("CornerIconRow")
		if row and row:IsA("GuiObject") then
			row.Position = UDim2.new(1, -16, 0, 12)
			local sc = row:FindFirstChild("CTScale")
			if sc then sc.Scale = 1 end
		end
	end
	-- ambient tavern life on the painted room: fire and candle flicker, dust motes (static glows in Calm mode)
	local cat = require(script.Parent.TavernLifeFX).cat(layer, room) -- the sleeping cat breathes (still in Calm mode)
	local lights = require(script.Parent.RoomLights).attach(layer, { room = "concept_t", zIndex = 1, visible = function() return active end })
	local self = {}
	local savedFan, savedFanOn = PlayMotion.FAN, PlayMotion.HAND_FAN_ENABLED

	-- the hand lies in the reference's tight arc while this screen is up (a static pose, no tweens, so Calm mode and Fast keep it)
	local function fanHand(on, h)
		if on then
			PlayMotion.FAN = Layout.fanProfile(h)
			PlayMotion.HAND_FAN_ENABLED = true
		else
			PlayMotion.FAN = savedFan
			PlayMotion.HAND_FAN_ENABLED = savedFanOn
		end
	end

	local function apply()
		local size = root.AbsoluteSize
		local r = Layout.rects(size.X, size.Y)
		fanHand(true, size.Y)
		do -- the room is cover-cropped at 3:2, tell the lights where the picture really is
			local w = math.max(size.X, size.Y * 1.5)
			local h = w / 1.5
			local pr = { x = (size.X - w) / 2, y = (size.Y - h) / 2, w = w, h = h }
			lights.place(pr)
			cat.place(pr, true)
		end
		place(coins, r.coins); place(hands, r.hands); place(round, r.round); place(gear, r.gear)
		place(deck, r.deck); place(deckCount, r.deckCount); place(play, r.play); place(discard, r.discard)
		-- numbers fill their plates like the reference (frame height scaled, at least 15 px)
		coinsText.TextSize = Layout.textSize("coins", size.Y); handsText.TextSize = Layout.textSize("hands", size.Y)
		roundText.TextSize = Layout.textSize("round", size.Y); deckText.TextSize = Layout.textSize("deckCount", size.Y)
		place(coinsText, Layout.textRect(r.coins, "coins")); place(handsText, Layout.textRect(r.hands, "hands"))
		place(deckText, Layout.textRect(r.deckCount, "deckCount"))
		place(roundText, Layout.textRect(r.round, "round"))
		local bar = Layout.bar(r)
		local p = Layout.progress(lastState and lastState.roundScore, lastState and lastState.targetScore)
		fill.Position = UDim2.fromOffset(bar.x, bar.y)
		fill.Size = UDim2.fromOffset(math.floor(bar.w * p), bar.h)
		fill.Visible = p > 0
		if self.lastP ~= nil and p > self.lastP then local prev = self.lastP; pcall(function() require(script.Parent.AnimPassFX).barShine(fill, prev, p) end) end
		self.lastP = p
		-- the real controls ride on the painted pieces
		place(deps.handFrame, Layout.handFor(r.hand, size.X, lastState and lastState.hand and #lastState.hand or 0))
		deps.actionFrame.Position = UDim2.fromOffset(r.play.x, r.play.y)
		deps.actionFrame.Size = UDim2.fromOffset(r.discard.x + r.discard.w - r.play.x, r.play.h)
		place(deps.playButton, { x = 0, y = 0, w = r.play.w, h = r.play.h })
		deps.playButton.Position = UDim2.fromOffset(0, 0)
		deps.discardButton.Position = UDim2.fromOffset(r.discard.x - r.play.x, r.discard.y - r.play.y)
		deps.discardButton.Size = UDim2.fromOffset(r.discard.w, r.discard.h)
		-- the Rank | Suit sort frame used to sit at the action row's origin, on top of Play Hand (the stray bracket and line):
		-- it stands at the bottom left, clear of the hand and the buttons
		for _, c in ipairs(deps.actionFrame:GetChildren()) do
			if c:IsA("Frame") and c.LayoutOrder == 0 then
				-- a flat wood pill, no plate art, ring or divider (SortToggle reads the Flat attribute), left of Play Hand
				local box = Layout.sortSize(size.X, size.Y)
				local sx = Layout.sortSpot(size.X, size.Y, box.w, box.h, r)
				LayoutSwitch.off(c)
				c.Size = UDim2.fromOffset(box.w, box.h)
				c.Position = UDim2.fromOffset(sx.x - r.play.x, sx.y - r.play.y)
				sortHost = c
				for _, k in ipairs(c:GetChildren()) do
					if k.Name == "PlatePaint" and k:IsA("GuiObject") then k.Visible = false
					elseif k:IsA("TextLabel") then k.Visible = false -- the "Sort:" caption
					elseif k.Name == "SortToggle" then
						k:SetAttribute("Flat", true)
						k.Position = UDim2.fromOffset(0, 0)
						k.Size = UDim2.fromOffset(box.w, box.h)
						k.BackgroundTransparency = 0
						local st = k:FindFirstChildOfClass("UIStroke")
						if st then st.Enabled = true end
					end
				end
			end
		end
		-- the Patron cards place themselves from ConceptTLayout.patronRow (Client/PatronRow asks isActive)
		local dw = deps.deckWidget
		if dw then
			place(dw, r.deck)
			dw.AnchorPoint = Vector2.new(0, 0)
			-- only the click catcher stays: the old framed deck, card back and count pills are covered by the painted book and one count plate
			dw.BackgroundTransparency = 1
			for _, c in ipairs(dw:GetChildren()) do
				if c.Name ~= "ClickCatcher" then
					if c:IsA("GuiObject") then
						if c.Visible then hiddenDeck[c] = true end
						c.Visible = false
					elseif c:IsA("UIStroke") then c.Enabled = false end
				end
			end
		end
		-- the other corner icons sit in a row left of the gear at 0.7 of its height (the gear itself is the painted one)
		local row = root:FindFirstChild("CornerIconRow")
		if row and row:IsA("GuiObject") then
			row.AnchorPoint = Vector2.new(1, 0)
			row.Position = UDim2.fromOffset(r.gear.x - 10, r.gear.y + math.floor(r.gear.h * 0.15))
			local sc = row:FindFirstChild("CTScale")
			if not sc then sc = Instance.new("UIScale"); sc.Name = "CTScale"; sc.Parent = row end
			sc.Scale = math.max(0.5, math.min(1.2, r.gear.h * 0.7 / 54))
		end
		local sb = deps.settingsButton
		if sb then
			sb.Parent = layer
			sb.AnchorPoint = Vector2.new(0, 0)
			place(sb, r.gear)
			sb.ZIndex = 6
		end
	end

	local function shell(on)
		for _, name in ipairs(HIDE) do
			local g = root:FindFirstChild(name)
			if g and g:IsA("GuiObject") and on then g.Visible = false end
		end
		layer.Visible = on
	end

	function self.isActive() return active end

	function self.update(state)
		lastState = state or lastState
		local size = root.AbsoluteSize
		local on = lastState ~= nil and lastState.phase == "playing" and deps.handFrame.Visible and Layout.fits(size.X, size.Y)
		active = on
		shell(on)
		if not on then fanHand(false, size.Y); restoreOld(); return end
		local FX = require(script.Parent.HudTickFX) -- number pops, deck shake (nothing in Calm mode)
		local oldCoins, oldHands, oldDeck = coinsText.Text, handsText.Text, deckText.Text
		coinsText.Text = string.format("%d", math.floor(lastState.tips or 0))
		handsText.Text = string.format("%d", math.floor(lastState.handsRemaining or 0))
		if oldCoins ~= "" then
			pcall(FX.pop, coinsText, oldCoins, coinsText.Text)
			pcall(require(script.Parent.TavernLifeFX).coinBurst, layer, coins, oldCoins, coinsText.Text) -- gold burst when coins rise
		end
		if oldHands ~= "" then pcall(FX.pop, handsText, oldHands, handsText.Text) end
		roundText.Text = string.format("Round %d", math.floor(lastState.round or 1))
		local remaining = 0
		for _, suit in pairs(lastState.deckCounts or {}) do
			for _, n in pairs(suit) do remaining = remaining + (tonumber(n) or 0) end
		end
		deckText.Text = DeckCountText.spaced(remaining, lastState.deckView)
		if oldDeck ~= "" and oldDeck ~= deckText.Text then
			local newDeck = deckText.Text
			pcall(FX.pop, deckText, oldDeck, newDeck)
			pcall(FX.deckShake, deck, oldDeck, newDeck)
			pcall(function() require(script.Parent.AnimPassFX).countFlip(deckText, oldDeck, newDeck) end)
		end
		clearButton(deps.playButton); clearButton(deps.discardButton)
		apply()
		if deps.selectedCount then -- the guided first hand hint (Engine/GuidedHand), display only
			pcall(function()
				local r = Layout.rects(size.X, size.Y)
				require(script.Parent.GuidedHint).update(layer, lastState, deps.selectedCount(), deps.firstCard and deps.firstCard(), deps.playButton, r)
			end)
		end
	end

	if deps.settingsButton then -- the gear turns a little while the cursor is on it (still in Calm mode)
		deps.settingsButton.MouseEnter:Connect(function() pcall(require(script.Parent.HudTickFX).gear, gear, true) end)
		deps.settingsButton.MouseLeave:Connect(function() pcall(require(script.Parent.HudTickFX).gear, gear, false) end)
	end
	root:GetPropertyChangedSignal("AbsoluteSize"):Connect(function() if active then apply() end end)
	-- other modules rewrite their own Position now and then; this keeps the painted layout the last word
	task.spawn(function()
		while layer.Parent do
			task.wait(0.25)
			if active then pcall(shell, true); pcall(apply) end
		end
	end)
	current = self
	return self
end

function M.isActive()
	return current ~= nil and current.isActive()
end

function M.update(state)
	if current then current.update(state) end
end

return M
