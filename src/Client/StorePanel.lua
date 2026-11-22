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
	require(script.Parent.ArtIcon).apply(well, "store_bundles", row.id, icon, { zIndex = 35, cornerRadius = 43 })

	label(card, { Name = "Name", Size = UDim2.new(1, -16, 0, 26), Position = UDim2.fromOffset(8, 104), Text = row.name, TextSize = 19 })
	label(card, {
		Name = "Desc", Size = UDim2.new(1, -20, 0, 66), Position = UDim2.fromOffset(10, 132), Text = row.description, TextSize = 15,
		Font = Enum.Font.GothamMedium, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top,
	})
	label(card, {
		Name = "Perks", Size = UDim2.new(1, -20, 0, 54), Position = UDim2.fromOffset(10, 200), Text = "• " .. table.concat(row.perks or {}, "\n• "),
		TextSize = 14, Font = Enum.Font.GothamMedium, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top, TextColor3 = Color3.fromRGB(90, 66, 40),
	})
	label(card, {
		Name = "Price", Size = UDim2.new(1, -16, 0, 20), Position = UDim2.new(0, 8, 1, -76), Text = StorePanel.priceText(row, priceCache), TextSize = 15,
		TextColor3 = row.owned and GREEN or INK,
	})

	local button = Instance.new("TextButton")
	button.Name = "Buy"
	button.Size = UDim2.new(1, -36, 0, 44) -- 44 px touch target (TavernKit look)
	button.Position = UDim2.new(0, 18, 1, -52)
	button.ZIndex = 34
	button.Parent = card
	if row.owned then
		Kit.skin(button, "Owned", "secondary")
		button.Active = false
	elseif row.available then
		Kit.skin(button, row.studioFree and "Take (Studio)" or "Buy", "primary")
		button.MouseButton1Click:Connect(function()
			ui.playClickSfx()
			ui.purchaseRemote:FireServer(row.id)
		end)
	else
		Kit.skin(button, row.listOnly and "Info" or "Coming soon", "secondary")
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
	panel.Size = UDim2.fromOffset(820, 470)
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
		for _, d in ipairs(panel:GetDescendants()) do
			if d.Name == "Buy" and d:IsA("TextButton") then
				d.Size = UDim2.new(1, -36, 0, bh)
				d.Position = UDim2.new(0, 18, 1, -4 - bh)
			end
		end
	end
	resize()
	deps.screenGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(resize)

	label(panel, { Name = "Title", Size = UDim2.new(1, 0, 0, 36), Position = UDim2.fromOffset(0, 8), Text = "The Tavern Store", TextSize = 26, TextColor3 = CREAM })
	label(panel, {
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
	resize() -- the Close plate exists now

	ui = {
		resize = resize,
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
