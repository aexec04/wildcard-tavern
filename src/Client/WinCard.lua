--[[
	Client/WinCard.lua
	The Win Card: a parchment card for a won run or a new best, opened from the run summary. It shows the title, the
	Night reached, the best hand, the stake stamp, the equipped card back, up to three Patrons used and a seed or
	date line, plus the share text (Engine/WinCard.shareText, 200 characters or less).

	Games cannot write the clipboard, so "Copy result" selects the text in a read-only box; press Ctrl+C to copy.
	All text is 15px or larger. Display only: no remotes, no run data changes.

	WinCard.show(parent, state, summary)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Engine = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine")
local WinCardData = require(Engine:WaitForChild("WinCard"))
local SeedDisplay = require(Engine:WaitForChild("SeedDisplay"))

local WinCard = {}

local PARCHMENT = Color3.fromRGB(235, 215, 170)
local INK = Color3.fromRGB(60, 40, 22)
local WOOD = Color3.fromRGB(86, 58, 34)
local GOLD = Color3.fromRGB(222, 182, 104)
local GREEN = Color3.fromRGB(86, 140, 70)
local CREAM = Color3.fromRGB(250, 235, 200)

local current

local function corner(obj, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = obj
end

local function text(parent, props)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = props.font or Enum.Font.GothamBold
	l.TextSize = props.size or 16
	l.TextColor3 = props.color or INK
	l.TextTransparency = 0
	l.TextStrokeTransparency = 1
	l.TextWrapped = true
	l.TextXAlignment = props.alignX or Enum.TextXAlignment.Center
	l.Text = props.text or ""
	l.Position = props.pos or UDim2.new()
	l.Size = props.size2 or UDim2.fromScale(1, 1)
	l.ZIndex = 93
	l.Parent = parent
	return l
end

local function button(parent, label, color, pos, size)
	local b = Instance.new("TextButton")
	b.BackgroundColor3 = color
	b.BorderSizePixel = 0
	b.Font = Enum.Font.GothamBold
	b.TextSize = 16
	b.TextColor3 = CREAM
	b.TextTransparency = 0
	b.TextStrokeTransparency = 0.6
	b.Text = label
	b.Position = pos
	b.Size = size
	b.ZIndex = 93
	b.Parent = parent
	corner(b, 8)
	return b
end

function WinCard.close()
	if current then
		current:Destroy()
		current = nil
	end
end

function WinCard.show(parent, state, summary)
	WinCard.close()
	if not parent or type(summary) ~= "table" then
		return
	end
	local seed = SeedDisplay.label(state or {})
	local card = WinCardData.build(summary, {
		stake = summary.stake, cardBackId = state and state.cardBackId, seedText = seed and seed.text, newBest = summary.newBest,
	})

	local backdrop = Instance.new("TextButton") -- a button so a click outside closes it
	backdrop.Name = "WinCardBackdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.fromRGB(10, 8, 6)
	backdrop.BackgroundTransparency = 0.35
	backdrop.BorderSizePixel = 0
	backdrop.AutoButtonColor = false
	backdrop.Text = ""
	backdrop.ZIndex = 90
	backdrop.Parent = parent
	backdrop.MouseButton1Click:Connect(WinCard.close)
	current = backdrop

	local panel = Instance.new("Frame")
	panel.Name = "WinCard"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(420, 500)
	panel.BackgroundColor3 = PARCHMENT
	panel.BorderSizePixel = 0
	panel.Active = true -- swallows clicks so the backdrop does not close it
	panel.ZIndex = 91
	panel.Parent = backdrop
	corner(panel, 12)
	local stroke = Instance.new("UIStroke")
	stroke.Color = GOLD
	stroke.Thickness = 3
	stroke.Parent = panel
	local fit = Instance.new("UIScale")
	local size = parent.AbsoluteSize
	fit.Scale = math.clamp(math.min(size.X / 460, size.Y / 540), 0.6, 1)
	fit.Parent = panel

	-- Title ribbon.
	local ribbon = Instance.new("Frame")
	ribbon.Size = UDim2.new(1, -24, 0, 44)
	ribbon.Position = UDim2.fromOffset(12, 12)
	ribbon.BackgroundColor3 = WOOD
	ribbon.BorderSizePixel = 0
	ribbon.ZIndex = 92
	ribbon.Parent = panel
	corner(ribbon, 8)
	text(ribbon, { text = card.title, size = 24, color = CREAM, font = Enum.Font.GothamBlack })
	text(panel, { text = card.subtitle, size = 16, pos = UDim2.fromOffset(12, 60), size2 = UDim2.new(1, -24, 0, 24) })

	-- Card back thumbnail (left) and the facts (right).
	local back = Instance.new("ImageLabel")
	back.Name = "CardBack"
	back.Position = UDim2.fromOffset(24, 96)
	back.Size = UDim2.fromOffset(100, 150)
	back.BackgroundColor3 = Color3.fromRGB(70, 40, 40)
	back.ScaleType = Enum.ScaleType.Crop
	back.ZIndex = 92
	back.Parent = panel
	corner(back, 8)
	local backStroke = Instance.new("UIStroke")
	backStroke.Color = GOLD
	backStroke.Thickness = 2
	backStroke.Parent = back
	pcall(function()
		local id = card.cardBackId and require(Engine:WaitForChild("ContentArt")).getImageId("card_backs", card.cardBackId)
		if id then
			back.Image = id
		end
	end)
	text(panel, { text = card.nightText, size = 26, alignX = Enum.TextXAlignment.Left, pos = UDim2.fromOffset(140, 100), size2 = UDim2.new(1, -160, 0, 34) })
	text(panel, { text = card.bestHandText, size = 17, alignX = Enum.TextXAlignment.Left, pos = UDim2.fromOffset(140, 140), size2 = UDim2.new(1, -160, 0, 48) })
	local stamp = Instance.new("Frame")
	stamp.Position = UDim2.fromOffset(140, 200)
	stamp.Size = UDim2.fromOffset(120, 36)
	stamp.BackgroundTransparency = 1
	stamp.Rotation = -4
	stamp.ZIndex = 92
	stamp.Parent = panel
	corner(stamp, 8)
	local stampStroke = Instance.new("UIStroke")
	stampStroke.Color = Color3.fromRGB(150, 50, 40)
	stampStroke.Thickness = 3
	stampStroke.Parent = stamp
	text(stamp, { text = card.stakeText, size = 18, color = Color3.fromRGB(150, 50, 40), font = Enum.Font.GothamBlack })

	-- Up to three Patrons.
	text(panel, { text = "Patrons at my table", size = 16, pos = UDim2.fromOffset(12, 256), size2 = UDim2.new(1, -24, 0, 22) })
	local row = Instance.new("Frame")
	row.Position = UDim2.fromOffset(0, 282)
	row.Size = UDim2.new(1, 0, 0, 70)
	row.BackgroundTransparency = 1
	row.ZIndex = 92
	row.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0, 14)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = row
	for i, patron in ipairs(card.patrons) do
		local seat = Instance.new("Frame")
		seat.LayoutOrder = i
		seat.Size = UDim2.fromOffset(64, 64)
		seat.BackgroundColor3 = Color3.fromRGB(196, 168, 118)
		seat.ZIndex = 92
		seat.Parent = row
		corner(seat, 32)
		local ring = Instance.new("UIStroke")
		ring.Color = GOLD
		ring.Thickness = 2
		ring.Parent = seat
		local emoji = text(seat, { text = patron.icon or "\u{1F9D1}", size = 30, color = INK })
		pcall(function()
			require(script.Parent.ArtIcon).apply(seat, "patrons", patron.id, emoji, { cornerRadius = 32 })
		end)
	end
	if #card.patrons == 0 then
		text(row, { text = "None yet", size = 16 })
	end

	text(panel, { text = card.footer, size = 15, color = Color3.fromRGB(110, 70, 30), pos = UDim2.fromOffset(12, 356), size2 = UDim2.new(1, -24, 0, 22) })

	-- Share text in a selectable box, plus Copy result and Close.
	local box = Instance.new("TextBox")
	box.Name = "ShareText"
	box.Position = UDim2.fromOffset(16, 384)
	box.Size = UDim2.new(1, -32, 0, 56)
	box.BackgroundColor3 = Color3.fromRGB(26, 17, 10)
	box.BorderSizePixel = 0
	box.Font = Enum.Font.Gotham
	box.TextSize = 15
	box.TextColor3 = CREAM
	box.TextTransparency = 0
	box.TextWrapped = true
	box.ClearTextOnFocus = false
	box.TextEditable = false
	box.Text = card.shareText
	box.ZIndex = 93
	box.Parent = panel
	corner(box, 6)
	local copy = button(panel, "Copy result", GREEN, UDim2.fromOffset(16, 450), UDim2.new(0.5, -22, 0, 38))
	local close = button(panel, "Close", WOOD, UDim2.new(0.5, 6, 0, 450), UDim2.new(0.5, -22, 0, 38))
	copy.MouseButton1Click:Connect(function()
		box:CaptureFocus()
		box.SelectionStart = 1
		box.CursorPosition = #box.Text + 1
		copy.Text = "Selected: press Ctrl+C"
	end)
	close.MouseButton1Click:Connect(WinCard.close)
end

return WinCard
