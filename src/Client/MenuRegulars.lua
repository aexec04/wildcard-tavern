--[[
	Client/MenuRegulars.lua
	The Menu remembers you: up to 6 Tavern Regulars (Engine/Regulars.lua, bosses you beat and Patrons you won with, most recent first)
	hang as small framed portraits on the chimney wall above the fireplace of the painted Menu room, not as a floating row over it.
	Painted portraits when the art exists (patrons / boss_rounds), emoji otherwise. Each frame: a dark wood border, a thin brass inner
	line, a soft shadow below, a short cord to a brass nail, a slightly different size and a tiny tilt (at most 2 degrees). Hover gives a
	gentle warm glow and today's greeting; a tap opens a small card, titled "Your Regular", with their story line and your record.
	No gameplay power. With no Regulars nothing is drawn. Positions come from the tested Engine/RegularsLayout (a rectangle of the
	painted picture mapped through the room's cover crop, 3 frames at most on a narrow screen). Text is 15 px or more.

	MenuRegulars.update(state, menuFrame) is called from render() in a pcall; state.regulars comes from the server.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Layout = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("RegularsLayout"))

local MenuRegulars = {}

local CREAM = Color3.fromRGB(250, 235, 200)
local INK = Color3.fromRGB(60, 40, 22)
local PARCHMENT = Color3.fromRGB(235, 215, 170)
local GOLD = Color3.fromRGB(222, 182, 104)
local BRASS = Color3.fromRGB(205, 164, 84)
local FRAME_WOOD = Color3.fromRGB(84, 54, 30)
local FRAME_DARK = Color3.fromRGB(40, 26, 14)
local WARM = Color3.fromRGB(255, 196, 110)

local ui
local shownKey = ""
local shownSize = ""

local function build(menuFrame)
	-- a transparent layer over the whole Menu: the frames are placed in Menu pixels, the layer itself takes no clicks
	local root = Instance.new("Frame")
	root.Name = "TavernRegulars"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1
	root.Active = false
	root.ZIndex = 11
	root.Parent = menuFrame

	local frames = Instance.new("Frame")
	frames.Name = "Portraits"
	frames.Size = UDim2.fromScale(1, 1)
	frames.BackgroundTransparency = 1
	frames.Active = false
	frames.ZIndex = 11
	frames.Parent = root

	-- the greeting bubble and the record card are siblings of the portraits, placed under them when shown
	local bubble = Instance.new("TextLabel")
	bubble.Name = "RegularGreeting"
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
	card.Size = UDim2.fromOffset(280, 176)
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
	local function cardLabel(name, y, h, size, color)
		local l = Instance.new("TextLabel")
		l.Name = name
		l.Position = UDim2.fromOffset(10, y)
		l.Size = UDim2.new(1, -20, 0, h)
		l.BackgroundTransparency = 1
		l.Font = Enum.Font.GothamBold
		l.TextSize = size
		l.TextColor3 = color or INK
		l.TextTransparency = 0
		l.TextStrokeTransparency = 1
		l.TextWrapped = true
		l.TextXAlignment = Enum.TextXAlignment.Left
		l.TextYAlignment = Enum.TextYAlignment.Top
		l.ZIndex = 16
		l.Parent = card
		return l
	end
	cardLabel("CardTitle", 6, 20, 15, Color3.fromRGB(120, 84, 24)).Text = "Your Regular"
	local cardName = cardLabel("Name", 28, 24, 18)
	local cardStory = cardLabel("Story", 56, 64, 15)
	local cardRecord = cardLabel("Record", 126, 40, 15, Color3.fromRGB(110, 70, 30))

	ui = { root = root, grid = frames, bubble = bubble, card = card, cardName = cardName, cardStory = cardStory, cardRecord = cardRecord, seats = {}, anchor = nil }
	-- a resized window moves the chimney with the picture: lay the frames out again from the last state
	menuFrame:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		if ui and ui.lastState then MenuRegulars.update(ui.lastState, menuFrame) end
	end)
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

-- the bubble and the card hang under the portraits, left edge on the chimney spot
local function placeNotes(menuFrame)
	local a = ui.anchor
	if not a then return end
	local W = menuFrame.AbsoluteSize.X
	local x = math.max(8, math.min(a.x, W - 290))
	ui.bubble.Position = UDim2.fromOffset(x, a.y + a.h + 6)
	ui.card.Position = UDim2.fromOffset(x, a.y + a.h + 6)
end

local function addSeat(entry, order, f, menuFrame)
	-- the hanging unit: shadow, cord and nail, frame. Kept in one Frame sized to the frame so the cord sits above it.
	local seat = Instance.new("TextButton")
	seat.Name = "Regular_" .. entry.id
	seat.LayoutOrder = order
	seat.AutoButtonColor = false
	seat.Text = ""
	seat.BackgroundColor3 = FRAME_WOOD
	seat.BorderSizePixel = 0
	seat.Position = UDim2.fromOffset(f.x, f.y)
	seat.Size = UDim2.fromOffset(f.w, f.h)
	seat.Rotation = f.tilt
	seat.ZIndex = 12
	seat.Parent = ui.grid
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = seat
	local outer = Instance.new("UIStroke") -- dark wood outer edge, 3 px
	outer.Color = FRAME_DARK
	outer.Thickness = 3
	outer.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	outer.Parent = seat

	local shadow = Instance.new("Frame") -- soft shadow below the frame
	shadow.Name = "Shadow"
	shadow.Position = UDim2.fromOffset(3, 5)
	shadow.Size = UDim2.fromScale(1, 1)
	shadow.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	shadow.BackgroundTransparency = 0.65
	shadow.BorderSizePixel = 0
	shadow.Active = false
	shadow.ZIndex = 11
	shadow.Parent = seat
	local sc = Instance.new("UICorner")
	sc.CornerRadius = UDim.new(0, 5)
	sc.Parent = shadow

	local glow = Instance.new("Frame") -- warm glow on hover
	glow.Name = "HoverGlow"
	glow.AnchorPoint = Vector2.new(0.5, 0.5)
	glow.Position = UDim2.fromScale(0.5, 0.5)
	glow.Size = UDim2.new(1, 14, 1, 14)
	glow.BackgroundColor3 = WARM
	glow.BackgroundTransparency = 0.8
	glow.BorderSizePixel = 0
	glow.Active = false
	glow.Visible = false
	glow.ZIndex = 11
	glow.Parent = seat
	local gc = Instance.new("UICorner")
	gc.CornerRadius = UDim.new(0, 8)
	gc.Parent = glow

	local inner = Instance.new("Frame") -- thin brass inner line around the portrait
	inner.Name = "PortraitWindow"
	inner.Position = UDim2.fromOffset(4, 4)
	inner.Size = UDim2.new(1, -8, 1, -8)
	inner.BackgroundColor3 = Color3.fromRGB(70, 48, 30)
	inner.BorderSizePixel = 0
	inner.Active = false
	inner.ZIndex = 13
	inner.Parent = seat
	local ik = Instance.new("UICorner")
	ik.CornerRadius = UDim.new(0, 2)
	ik.Parent = inner
	local brass = Instance.new("UIStroke")
	brass.Color = BRASS
	brass.Thickness = 1
	brass.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	brass.Parent = inner

	local cord = Instance.new("Frame") -- short cord up to the nail
	cord.Name = "Cord"
	cord.AnchorPoint = Vector2.new(0.5, 1)
	cord.Position = UDim2.new(0.5, 0, 0, 0)
	cord.Size = UDim2.fromOffset(2, f.cord)
	cord.BackgroundColor3 = Color3.fromRGB(150, 112, 60)
	cord.BorderSizePixel = 0
	cord.Active = false
	cord.ZIndex = 12
	cord.Parent = seat
	local nail = Instance.new("Frame")
	nail.Name = "Nail"
	nail.AnchorPoint = Vector2.new(0.5, 0.5)
	nail.Position = UDim2.new(0.5, 0, 0, -f.cord)
	nail.Size = UDim2.fromOffset(6, 6)
	nail.BackgroundColor3 = BRASS
	nail.BorderSizePixel = 0
	nail.Active = false
	nail.ZIndex = 12
	nail.Parent = seat
	local nk = Instance.new("UICorner")
	nk.CornerRadius = UDim.new(0.5, 0)
	nk.Parent = nail

	local emoji = Instance.new("TextLabel")
	emoji.Size = UDim2.fromScale(1, 1)
	emoji.BackgroundTransparency = 1
	emoji.Text = entry.icon or "\u{1F9D1}"
	emoji.TextSize = math.max(24, math.floor(f.w * 0.5))
	emoji.TextColor3 = CREAM
	emoji.TextTransparency = 0
	emoji.TextStrokeTransparency = 1
	emoji.ZIndex = 14
	emoji.Parent = inner
	pcall(function()
		require(script.Parent.ArtIcon).apply(inner, entry.kind == "boss" and "boss_rounds" or "patrons", entry.id, emoji, { cornerRadius = 2 })
	end)

	seat.MouseEnter:Connect(function()
		glow.Visible = true
		if ui.card.Visible then return end
		ui.bubble.Text = entry.name .. ": " .. entry.greeting
		placeNotes(menuFrame)
		ui.bubble.Visible = true
	end)
	seat.MouseLeave:Connect(function()
		glow.Visible = false
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
		placeNotes(menuFrame)
		ui.card.Visible = true
	end)
	ui.seats[#ui.seats + 1] = seat
end

function MenuRegulars.update(state, menuFrame)
	if not menuFrame then return end
	if not ui or not ui.root.Parent then
		build(menuFrame)
		shownKey = ""
		shownSize = ""
	end
	ui.lastState = state
	local list = state.regulars or {}
	ui.root.Visible = #list > 0
	local parts = {}
	for _, e in ipairs(list) do
		parts[#parts + 1] = e.key .. "|" .. e.greeting .. "|" .. tostring(e.wins) .. "|" .. tostring(e.losses)
	end
	local key = table.concat(parts, ";")
	local size = menuFrame.AbsoluteSize
	local sizeKey = tostring(math.floor(size.X)) .. "x" .. tostring(math.floor(size.Y))
	if key == shownKey and sizeKey == shownSize then return end
	shownKey, shownSize = key, sizeKey
	clearSeats()
	if #list == 0 or size.X <= 0 or size.Y <= 0 then return end
	local placed = Layout.compute(size.X, size.Y, #list)
	ui.anchor = placed.spot
	for i, f in ipairs(placed.frames) do
		addSeat(list[i], i, f, menuFrame)
	end
end

return MenuRegulars
