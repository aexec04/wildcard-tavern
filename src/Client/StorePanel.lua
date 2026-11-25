-- The Tavern Store: four painted bundle cards (Starter Pack, Card Set Bundle, VIP, One More Round) with what they
-- hold, an owned ribbon and a price. FAIR: cosmetics and convenience only; the header says so. Prices come from
-- MarketplaceService when the item has a real id, otherwise honest fallback text ("Coming soon" in the live game,
-- "Free in Studio" in Studio). Buying sends the `StorePurchase` remote; the server prompts the real purchase and
-- grants through ProcessReceipt / pass checks. Art is emoji until the `store_subjects` images exist.
--
-- init(deps): { screenGui, openButton, polishPanel, polishButton, roundCorner, playClickSfx, popIn, popOut, purchaseRemote }
-- update(state): called from render in a pcall; keeps an open panel current and opens it once per state.storePrompt.
local MarketplaceService = game:GetService("MarketplaceService")

local OverlayManager = require(script.Parent.OverlayManager)
local Kit = require(script.Parent.TavernKit)
local StoreLayout = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("StoreLayout")) -- panel numbers, tested at every size

local Store = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("Store"))

local StorePanel = {}

local INK = Color3.fromRGB(60, 40, 22)
local PARCHMENT = Color3.fromRGB(222, 198, 150)
local GOLD = Color3.fromRGB(222, 182, 104)
local CREAM = Color3.fromRGB(250, 235, 200)
local WOOD = Color3.fromRGB(86, 58, 34)
local GREEN = Color3.fromRGB(70, 110, 65)

local ui
local lastPromptSeq = 0
local priceCache = {} -- [roblox id] = text
local pricePending = {}

-- Text under an item's name: owned, free in Studio, coming soon, a real price, or a plain fallback.
function StorePanel.priceText(row, cache)
	return Store.priceLine(row, cache)
end

local function fetchPrice(row)
	if row.robloxId <= 0 or priceCache[row.robloxId] or pricePending[row.robloxId] then
		return
	end
	pricePending[row.robloxId] = true
	task.spawn(function()
		local ok, info = pcall(function()
			return MarketplaceService:GetProductInfo(row.robloxId, row.kind == "pass" and Enum.InfoType.GamePass or Enum.InfoType.Product)
		end)
		pricePending[row.robloxId] = nil
		local price = ok and info and info.PriceInRobux or nil
		if price then
			priceCache[row.robloxId] = "R$ " .. tostring(math.floor(price))
			if ui and ui.backdrop.Visible then
				StorePanel.refresh()
			end
		end
	end)
end

local function label(parent, props)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBold
	l.TextColor3 = INK
	l.TextTransparency = 0
	l.TextStrokeTransparency = 1
	l.ZIndex = 33
	for k, v in pairs(props) do
		l[k] = v
	end
	l.Parent = parent
	return l
end

-- Button looks (numbers in Engine/StoreLayout.BUTTON, tested): a brown plate with cream text for Owned, Info and Coming soon,
-- the normal green with cream text for Buy and the Studio free state. Always fully opaque, 16 px.
local function paintButton(button, kind, outline)
	local B = StoreLayout.BUTTON[kind]
	button.BackgroundColor3 = Color3.fromRGB(B.fill[1], B.fill[2], B.fill[3])
	button.BackgroundTransparency = 0
	button.TextColor3 = Color3.fromRGB(B.text[1], B.text[2], B.text[3])
	button.TextTransparency = 0
	button.TextStrokeTransparency = 1
	button.TextSize = StoreLayout.BUTTON.textSize
	for _, c in ipairs(button:GetChildren()) do
		if c:IsA("UIGradient") then c:Destroy() end
	end
	if outline then
		local st = button:FindFirstChildOfClass("UIStroke")
		if st then st.Color = GOLD; st.Thickness = 2 end
	end
end

local function buildCard(row, order)
	local card = Instance.new("Frame")
	card.Name = "Item_" .. row.id
	card.Size = UDim2.fromOffset(180, 330)
	card.LayoutOrder = order
	card.BackgroundColor3 = PARCHMENT
	card.ZIndex = 32
	card.Parent = ui.row
	ui.roundCorner(card, 12)
	local stroke = Instance.new("UIStroke")
	stroke.Color = row.owned and GREEN or GOLD
	stroke.Thickness = 2.5
	stroke.Parent = card

	local well = Instance.new("Frame")
	well.Size = UDim2.fromOffset(86, 86)
	well.Position = UDim2.new(0.5, -43, 0, 12)
	well.BackgroundColor3 = WOOD
	well.ZIndex = 33
	well.Parent = card
	ui.roundCorner(well, 43)
	local ring = Instance.new("UIStroke")
	ring.Color = GOLD
	ring.Thickness = 2
	ring.Parent = well
	local icon = label(well, { Size = UDim2.fromScale(1, 1), Text = row.icon, TextSize = 46, TextColor3 = CREAM, ZIndex = 34 })
	pcall(function() -- a recorded launch icon wins, then the bundle art, then the emoji
		local Engine = game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine")
		local artId = require(Engine:WaitForChild("LaunchIcons")).imageFor(row.id, require(Engine:WaitForChild("ContentArt")).store_bundles)
		if artId then
			require(script.Parent.PatronPlaque).applyById(well, artId, { emojiLabel = icon, zIndex = 35, cornerRadius = 43 })
		end
	end)

	local nameLabel = label(card, { Name = "Name", Size = UDim2.new(1, -16, 0, 26), Position = UDim2.fromOffset(8, 104), Text = row.name, TextSize = 19 })
	local descLabel = label(card, {
		Name = "Desc", Size = UDim2.new(1, -20, 0, 66), Position = UDim2.fromOffset(10, 132), Text = row.description, TextSize = 15,
		Font = Enum.Font.GothamMedium, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top,
		TextTruncate = Enum.TextTruncate.AtEnd, -- three lines at most, so every card lines up
	})
	local perksLabel = label(card, {
		Name = "Perks", Size = UDim2.new(1, -20, 0, 54), Position = UDim2.fromOffset(10, 200), Text = "• " .. table.concat(row.perks or {}, "\n• "),
		TextSize = 14, Font = Enum.Font.GothamMedium, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top, TextColor3 = Color3.fromRGB(90, 66, 40),
	})
	local priceLabel = label(card, {
		Name = "Price", Size = UDim2.new(1, -16, 0, 20), Position = UDim2.new(0, 8, 1, -76), Text = StorePanel.priceText(row, priceCache), TextSize = 15,
		TextColor3 = row.owned and GREEN or INK,
	})

	pcall(function() -- the equipped Card Set's paper, edge and dark ink (7:1); Owned keeps its green ring and price, classic keeps parchment
		local labels = { { nameLabel, INK }, { descLabel, INK }, { perksLabel, Color3.fromRGB(90, 66, 40) } }
		if not row.owned then table.insert(labels, { priceLabel, INK }) end
		require(script.Parent.PopupSkin).paper(card, nil, (not row.owned) and stroke or nil, labels, { fill = PARCHMENT, edge = GOLD })
	end)

	local button = Instance.new("TextButton")
	button.Name = "Buy"
	button.Size = UDim2.new(1, -36, 0, 44) -- 44 px touch target (TavernKit look)
	button.Position = UDim2.new(0, 18, 1, -52)
	button.ZIndex = 34
	button.Parent = card
	if row.owned then
		Kit.skin(button, "Thank you", "secondary") -- the green price line above already says Owned; the button must not repeat it
		paintButton(button, "plate")
		button.Active = false
	elseif row.available then
		Kit.skin(button, row.studioFree and "Take for free" or "Buy", "primary")
		paintButton(button, "buy")
		pcall(function() Kit.setPlateButton(button, "primary") end) -- the equipped Card Set's green plate; classic keeps the flat green
		button.MouseButton1Click:Connect(function()
			ui.playClickSfx()
			ui.purchaseRemote:FireServer(row.id)
		end)
	else
		Kit.skin(button, row.listOnly and "Info" or "Coming soon", "secondary")
		paintButton(button, "plate", row.listOnly) -- Info keeps the gold outline of an active button
		button.Active = false
	end
	return card
end

function StorePanel.refresh()
	if not ui then
		return
	end
	local state = ui.getLatestState and ui.getLatestState()
	local view = state and state.store
	if view then
		local built = false
		for _, child in ipairs(ui.row:GetChildren()) do
			if child:IsA("GuiObject") then built = true break end
		end
		-- the same items, owned states and prices as the cards on screen: keep them (no teardown on every state tick)
		if not ui.buildCache:shouldBuild(Store.viewKey(view, priceCache)) and built then return end
	else
		ui.buildCache:reset()
	end
	for _, child in ipairs(ui.row:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	if not view then
		return
	end
	for i, row in ipairs(view.items) do
		fetchPrice(row)
		buildCard(row, i)
	end
	if ui.resize then ui.resize() end -- new Buy plates take the 44 px on screen height
end

function StorePanel.init(deps)
	local backdrop = Instance.new("Frame")
	backdrop.Name = "StoreBackdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	backdrop.BackgroundTransparency = 0.4
	backdrop.Visible = false
	backdrop.ZIndex = 30
	backdrop.Parent = deps.screenGui
	require(script.Parent.MenuTitleHider).bind(deps.screenGui, backdrop)

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(StoreLayout.PANEL_W, StoreLayout.PANEL_H)
	panel.BackgroundColor3 = Color3.fromRGB(40, 30, 22)
	panel.ZIndex = 31
	panel.Parent = backdrop
	deps.polishPanel(panel, 16, "wood")
	local fit = Instance.new("UIScale")
	fit.Parent = panel
	local function resize()
		local size = deps.screenGui.AbsoluteSize
		fit.Scale = StoreLayout.scale(size.X, size.Y)
		local bh = StoreLayout.touchH(fit.Scale) -- stays 44 px on screen when the panel shrinks
		local c = panel:FindFirstChild("Close")
		if c then c.Size = UDim2.fromOffset(160, bh) end
		local x = panel:FindFirstChild("CloseX") -- the round X keeps a 44 px hit area on screen (the disc stays the same size)
		if x then x.Size = UDim2.fromOffset(bh, bh) end
		for _, d in ipairs(panel:GetDescendants()) do
			if d.Name == "Buy" and d:IsA("TextButton") then
				d.Size = UDim2.new(1, -36, 0, bh)
				d.Position = UDim2.new(0, 18, 1, -4 - bh)
			end
		end
	end
	resize()
	deps.screenGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(resize)

	local titleLabel = label(panel, { Name = "Title", Size = UDim2.new(1, 0, 0, 36), Position = UDim2.fromOffset(0, 8), Text = "The Tavern Store", TextSize = 26, TextColor3 = CREAM })
	local promiseLabel = label(panel, {
		Name = "Promise", Size = UDim2.new(1, -40, 0, 22), Position = UDim2.fromOffset(20, 46),
		Text = "Cosmetics and small conveniences only. Nothing here helps you win.", TextSize = 16, TextColor3 = GOLD,
		Font = Enum.Font.GothamMedium,
	})

	local row = Instance.new("Frame")
	row.Name = "Row"
	row.Size = UDim2.new(1, -30, 0, 330)
	row.Position = UDim2.fromOffset(15, 78)
	row.BackgroundTransparency = 1
	row.ZIndex = 31
	row.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 14)
	layout.Parent = row

	local close = Instance.new("TextButton")
	close.Name = "Close"
	close.Size = UDim2.fromOffset(160, 44)
	close.AnchorPoint = Vector2.new(0.5, 1)
	close.Position = UDim2.new(0.5, 0, 1, -12)
	close.ZIndex = 33
	close.Parent = panel
	Kit.skin(close, "Close", "secondary")
	pcall(function() -- the equipped Card Set's panel colours and ink (7:1); classic keeps the wood panel
		local pStroke = panel:FindFirstChildOfClass("UIStroke")
		require(script.Parent.PopupSkin).dark(panel, pStroke, { { titleLabel, CREAM }, { promiseLabel, GOLD } },
			{ plate = Color3.fromRGB(40, 30, 22), edge = pStroke and pStroke.Color })
		Kit.setPlateButton(close, "secondary")
	end)
	resize() -- the Close plate exists now

	ui = {
		resize = resize, buildCache = Store.newBuildCache(),
		backdrop = backdrop, panel = panel, row = row, roundCorner = deps.roundCorner, polishButton = deps.polishButton,
		playClickSfx = deps.playClickSfx, purchaseRemote = deps.purchaseRemote, getLatestState = deps.getLatestState,
		popIn = deps.popIn, popOut = deps.popOut,
	}

	local function open()
		deps.playClickSfx()
		OverlayManager.closeAllExcept("store")
		StorePanel.refresh()
		deps.popIn(backdrop, panel)
		pcall(function() -- tuning data: the Store panel was opened (server counts it against the hourly event budget)
			local remotes = game:GetService("ReplicatedStorage"):FindFirstChild("Remotes")
			local remote = remotes and remotes:FindFirstChild("StoreOpened")
			if remote then
				remote:FireServer()
			end
		end)
	end
	ui.open = open
	require(script.Parent.PanelTabs).attach(backdrop, "store", deps.playClickSfx, panel) -- shared tab strip + Back
	OverlayManager.register("store", function() deps.popOut(backdrop, panel) end)
	OverlayManager.registerOpener("store", open)
	deps.openButton.MouseButton1Click:Connect(open)
	require(script.Parent.CloseX).retire(close) -- the round X replaces the text Close
	require(script.Parent.CloseX).attach(panel, function()
		deps.playClickSfx()
		deps.popOut(backdrop, panel)
	end)
	ui.resize() -- the round X exists now: give it its 44 px on screen hit area
end

function StorePanel.update(state)
	if not ui or type(state) ~= "table" then
		return
	end
	if ui.backdrop.Visible then
		StorePanel.refresh()
	end
	local seq = state.storePrompt
	if type(seq) == "number" and seq > lastPromptSeq then
		lastPromptSeq = seq
		if not ui.backdrop.Visible then
			ui.open() -- the one-time Starter Pack prompt after the second run
		end
	end
end

return StorePanel
