--[[
	Client/MenuRegulars.lua
	The Menu remembers you: up to 6 Tavern Regulars (Engine/Regulars.lua) sit at little tables in the bottom left
	corner of the Menu, most recent first. Painted art when it exists (patrons / boss_rounds), emoji otherwise.
	Hover shows today's greeting; a click opens a tiny card with their story line and your record. No gameplay power.

	The row sits in the bottom left corner (3 across, 2 rows) so it stays clear of the Play column and the news
	banner, and is hidden on narrow screens. Text is 15px or larger.

	MenuRegulars.update(state, menuFrame) is called from render() in a pcall; state.regulars comes from the server.
]]

local MenuRegulars = {}

local CREAM = Color3.fromRGB(250, 235, 200)
local INK = Color3.fromRGB(60, 40, 22)
local PARCHMENT = Color3.fromRGB(235, 215, 170)
local GOLD = Color3.fromRGB(222, 182, 104)
local SEAT = 60
local GAP = 8
local MIN_WIDTH = 900 -- hidden below this viewport width

local ui
local shownKey = ""

local function build(menuFrame)
	local root = Instance.new("Frame")
	root.Name = "TavernRegulars"
	root.AnchorPoint = Vector2.new(0, 1)
	root.Position = UDim2.new(0, 16, 1, -16)
	root.Size = UDim2.fromOffset(SEAT * 3 + GAP * 2, SEAT * 2 + GAP + 24)
	root.BackgroundTransparency = 1
	root.ZIndex = 11
	root.Parent = menuFrame

	local title = Instance.new("TextLabel")
	title.Name = "RegularsTitle"
	title.Size = UDim2.new(1, 0, 0, 22)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.TextSize = 15
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = CREAM
	title.TextTransparency = 0
	title.TextStrokeTransparency = 0.3
	title.Text = "Your Regulars"
	title.ZIndex = 12
	title.Parent = root

	local grid = Instance.new("Frame")
	grid.Name = "Seats"
	grid.Position = UDim2.fromOffset(0, 24)
	grid.Size = UDim2.new(1, 0, 1, -24)
	grid.BackgroundTransparency = 1
	grid.ZIndex = 11
	grid.Parent = root
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromOffset(SEAT, SEAT)
	layout.CellPadding = UDim2.fromOffset(GAP, GAP)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid

	-- The bubble and the card are siblings of the grid (never inside the layout's parent).
	local bubble = Instance.new("TextLabel")
	bubble.Name = "RegularGreeting"
	bubble.AnchorPoint = Vector2.new(0, 1)
	bubble.Position = UDim2.new(0, 0, 0, -4)
	bubble.Size = UDim2.fromOffset(240, 44)
	bubble.BackgroundColor3 = PARCHMENT
	bubble.Font = Enum.Font.GothamBold
	bubble.TextSize = 15
	bubble.TextColor3 = INK
	bubble.TextWrapped = true
	bubble.TextTransparency = 0
	bubble.TextStrokeTransparency = 1
	bubble.Visible = false
	bubble.ZIndex = 14
	bubble.Parent = root
	local bc = Instance.new("UICorner")
	bc.CornerRadius = UDim.new(0, 8)
	bc.Parent = bubble

	local card = Instance.new("Frame")
	card.Name = "RegularCard"
	card.AnchorPoint = Vector2.new(0, 1)
	card.Position = UDim2.new(0, 0, 0, -4)
	card.Size = UDim2.fromOffset(280, 150)
	card.BackgroundColor3 = PARCHMENT
	card.Visible = false
	card.ZIndex = 15
	card.Parent = root
	local cc = Instance.new("UICorner")
	cc.CornerRadius = UDim.new(0, 10)
	cc.Parent = card
	local cs = Instance.new("UIStroke")
	cs.Color = GOLD
	cs.Thickness = 2
	cs.Parent = card
	local function cardLabel(name, y, h, size)
		local l = Instance.new("TextLabel")
		l.Name = name
		l.Position = UDim2.fromOffset(10, y)
		l.Size = UDim2.new(1, -20, 0, h)
		l.BackgroundTransparency = 1
		l.Font = Enum.Font.GothamBold
		l.TextSize = size
		l.TextColor3 = INK
		l.TextTransparency = 0
		l.TextStrokeTransparency = 1
		l.TextWrapped = true
		l.TextXAlignment = Enum.TextXAlignment.Left
		l.TextYAlignment = Enum.TextYAlignment.Top
		l.ZIndex = 16
		l.Parent = card
		return l
	end
	local cardName = cardLabel("Name", 8, 24, 18)
	local cardStory = cardLabel("Story", 36, 64, 15)
	local cardRecord = cardLabel("Record", 108, 36, 15)
	cardRecord.TextColor3 = Color3.fromRGB(110, 70, 30)

	ui = { root = root, grid = grid, bubble = bubble, card = card, cardName = cardName, cardStory = cardStory, cardRecord = cardRecord, seats = {} }
end

local function clearSeats()
	for _, seat in ipairs(ui.seats) do
		seat:Destroy()
	end
	ui.seats = {}
	ui.bubble.Visible = false
	ui.card.Visible = false
end

local function recordText(entry)
	if entry.kind == "boss" then
		return string.format("You: %d win%s, %d loss%s", entry.wins or 0, (entry.wins or 0) == 1 and "" or "s",
			entry.losses or 0, (entry.losses or 0) == 1 and "" or "es")
	end
	return string.format("Runs won together: %d", entry.wins or 0)
end

local function addSeat(entry, order)
	local seat = Instance.new("TextButton")
	seat.Name = "Regular_" .. entry.id
	seat.LayoutOrder = order
	seat.AutoButtonColor = false
	seat.BackgroundColor3 = Color3.fromRGB(86, 58, 34)
	seat.Text = ""
	seat.ZIndex = 12
	seat.Parent = ui.grid
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = seat
	local stroke = Instance.new("UIStroke")
	stroke.Color = GOLD
	stroke.Thickness = 2
	stroke.Parent = seat
	local emoji = Instance.new("TextLabel")
	emoji.Size = UDim2.fromScale(1, 1)
	emoji.BackgroundTransparency = 1
	emoji.Text = entry.icon or "\u{1F9D1}"
	emoji.TextSize = 30
	emoji.TextColor3 = CREAM
	emoji.TextTransparency = 0
	emoji.TextStrokeTransparency = 1
	emoji.ZIndex = 13
	emoji.Parent = seat
	pcall(function()
		require(script.Parent.ArtIcon).apply(seat, entry.kind == "boss" and "boss_rounds" or "patrons", entry.id, emoji, { cornerRadius = SEAT / 2 })
	end)

	seat.MouseEnter:Connect(function()
		if ui.card.Visible then return end
		ui.bubble.Text = entry.name .. ": " .. entry.greeting
		ui.bubble.Visible = true
	end)
	seat.MouseLeave:Connect(function()
		ui.bubble.Visible = false
	end)
	seat.MouseButton1Click:Connect(function()
		ui.bubble.Visible = false
		if ui.card.Visible and ui.cardName.Text == entry.name then
			ui.card.Visible = false
			return
		end
		ui.cardName.Text = entry.name
		ui.cardStory.Text = entry.story
		ui.cardRecord.Text = recordText(entry)
		ui.card.Visible = true
	end)
	ui.seats[#ui.seats + 1] = seat
end

function MenuRegulars.update(state, menuFrame)
	if not menuFrame then return end
	if not ui or not ui.root.Parent then
		build(menuFrame)
		shownKey = ""
	end
	local list = state.regulars or {}
	local wide = menuFrame.AbsoluteSize.X >= MIN_WIDTH
	ui.root.Visible = #list > 0 and wide
	local parts = {}
	for _, e in ipairs(list) do
		parts[#parts + 1] = e.key .. "|" .. e.greeting .. "|" .. tostring(e.wins) .. "|" .. tostring(e.losses)
	end
	local key = table.concat(parts, ";")
	if key == shownKey then return end
	shownKey = key
	clearSeats()
	for i, entry in ipairs(list) do
		addSeat(entry, i)
	end
end

return MenuRegulars
