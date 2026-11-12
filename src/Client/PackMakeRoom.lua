--[[
	Client/PackMakeRoom.lua
	The "Make room" step of a pack pick. When the picked Patrons (or Recipes) do not fit the table (or the recipe box), Confirm opens this
	painted panel (dark wood frame with brass studs round a parchment sheet, the look of the Choose a Patron cards) instead of firing the
	pick. The incoming pick stands on the left as "Joins your table"; the owned Patrons (or Recipes) that could leave are small cards with a
	brass-ring portrait, name, rarity gem and tier word and "Sells for $N" in green ink. Tap one to choose it (thick red rim, a "Leaves"
	ribbon, the others dim once enough are chosen; tap again to put it back); a line says "X leaves, Y joins your table." with the Tips back.
	Back returns to change the pick. Confirm fires the same ResolvePack remote with the chosen ids as its second argument; the server
	(Engine/PackRoom) checks they are owned, distinct and exactly the overflow. A multi-pick pack asks for every overflowing pick at once,
	one line per pair. Text is 14 px or more. The panel is sized to its content and sits above the Confirm and Skip Pack plates.

	PackMakeRoom.new{ parent, z, playClick, polishButton } -> { open(view, items, onConfirm), close(), isOpen() }
	  view  = { ownedPatrons = { id }, recipes = { id }, patronLimit, recipeLimit }   (Engine/PackRoom)
	  items = the picked reveal items ({ id, name, category })
	  onConfirm(replaceIds)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Engine = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine")
local PackRoom = require(Engine:WaitForChild("PackRoom"))

-- the rarity helper and the portrait overlay are optional: without them a card has no gem and shows the emoji
local okR, ChoiceRarity = pcall(function() return require(Engine:WaitForChild("ChoiceRarity")) end)
if not okR then ChoiceRarity = nil end
local okP, PatronPlaque = pcall(function() return require(script.Parent.PatronPlaque) end)
if not okP then PatronPlaque = nil end

local PackMakeRoom = {}

local WOOD = Color3.fromRGB(82, 54, 30)
local WOOD_EDGE = Color3.fromRGB(38, 24, 12)
local WELL = Color3.fromRGB(60, 42, 26)
local BRASS = Color3.fromRGB(200, 160, 84)
local CREAM = Color3.fromRGB(250, 238, 212)
local GOLD = Color3.fromRGB(255, 214, 130)
local INK = Color3.fromRGB(46, 32, 20)
local GREEN_INK = Color3.fromRGB(34, 84, 40)
local RED = Color3.fromRGB(176, 44, 36)

-- measured numbers (pixels before the fit scale)
local CARD_W, CARD_H, GAP = 108, 168, 8
local JOIN_W = 132
local PAD = 22
local TITLE_H, SUB_H, SUMMARY_H, BUTTON_H = 32, 44, 56, 44

local function corner(inst, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = inst
end

local function stroke(inst, color, thickness)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = inst
	return s
end

local function c3(t) return Color3.fromRGB(t[1], t[2], t[3]) end

local function label(parent, props)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBold
	l.TextSize = 16
	l.TextColor3 = INK
	l.TextTransparency = 0
	l.TextStrokeTransparency = 1
	l.TextWrapped = true
	for k, v in pairs(props) do l[k] = v end
	l.Parent = parent
	return l
end

-- One small painted card: brass-ring portrait, name plate (with the tier word), and a caption line. Used for owned and incoming items.
local function buildCard(parent, z, kind, id, name, caption, captionColor, asButton)
	local card = Instance.new(asButton and "TextButton" or "Frame")
	card.Name = id
	card.BackgroundColor3 = Color3.fromRGB(238, 222, 186)
	card.BorderSizePixel = 0
	card.ZIndex = z
	if asButton then
		card.AutoButtonColor = false
		card.Text = ""
	end
	card.Parent = parent
	corner(card, 10)
	local rim = stroke(card, BRASS, 1.5)
	local paper = Instance.new("UIGradient") -- warm paper, colour stops only
	paper.Rotation = 90
	paper.Color = ColorSequence.new(Color3.fromRGB(246, 232, 198), Color3.fromRGB(228, 210, 172))
	paper.Parent = card

	local ring = Instance.new("Frame")
	ring.Name = "MedalRing"
	ring.Size = UDim2.fromOffset(70, 70)
	ring.Position = UDim2.new(0.5, -35, 0, 6)
	ring.BackgroundColor3 = BRASS
	ring.BorderSizePixel = 0
	ring.Active = false
	ring.ZIndex = z + 1
	ring.Parent = card
	corner(ring, 35)
	stroke(ring, Color3.fromRGB(60, 40, 22), 2)
	local well = Instance.new("Frame")
	well.Name = "Well"
	well.Size = UDim2.fromOffset(60, 60)
	well.Position = UDim2.new(0.5, -30, 0, 11)
	well.BackgroundColor3 = WELL
	well.BorderSizePixel = 0
	well.Active = false
	well.ZIndex = z + 2
	well.Parent = card
	corner(well, 30)
	stroke(well, GOLD, 1.5)
	local icon = label(well, { Name = "Icon", Size = UDim2.fromScale(1, 1), Text = PackRoom.iconOf(kind, id), TextSize = 30,
		TextColor3 = CREAM, TextWrapped = false, ZIndex = z + 3 })
	if PatronPlaque then
		pcall(PatronPlaque.apply, well, id, { category = kind == "patron" and "patrons" or "recipes", emojiLabel = icon, zIndex = z + 4, cornerRadius = 30 })
	end

	local rarity = ChoiceRarity and ChoiceRarity.info(ChoiceRarity.tabFor(kind), id) or nil
	local plate = Instance.new("Frame") -- dark name plate; tinted by the tier from Uncommon up
	plate.Name = "NamePlate"
	plate.Position = UDim2.fromOffset(5, 80)
	plate.Size = UDim2.new(1, -10, 0, rarity and 58 or 44)
	plate.BackgroundColor3 = rarity and c3(rarity.plate) or Color3.fromRGB(44, 32, 22)
	plate.BorderSizePixel = 0
	plate.Active = false
	plate.ZIndex = z + 1
	plate.Parent = card
	corner(plate, 7)
	if rarity then
		rim.Color = c3(rarity.rim)
		stroke(plate, c3(rarity.rim), 1.5)
		local gem = Instance.new("Frame")
		gem.Name = "RarityGem"
		gem.AnchorPoint = Vector2.new(0.5, 0.5)
		gem.Position = UDim2.new(1, -13, 0, 13)
		gem.Size = UDim2.fromOffset(12, 12)
		gem.Rotation = 45
		gem.BackgroundColor3 = c3(rarity.color)
		gem.BorderSizePixel = 0
		gem.Active = false
		gem.ZIndex = z + 3
		gem.Parent = card
		stroke(gem, Color3.fromRGB(30, 20, 10), 1.5)
	end
	label(plate, { Name = "Name", Size = UDim2.new(1, -8, 0, rarity and 38 or 40), Position = UDim2.fromOffset(4, 2), Text = name, TextSize = 14,
		TextColor3 = CREAM, TextYAlignment = Enum.TextYAlignment.Center, ZIndex = z + 2 })
	if rarity then
		label(plate, { Name = "Rarity", Size = UDim2.new(1, -8, 0, 16), Position = UDim2.fromOffset(4, 40), Text = rarity.word, TextSize = 14,
			TextColor3 = c3(rarity.text), TextWrapped = false, ZIndex = z + 2 })
	end
	label(card, { Name = "Value", Size = UDim2.new(1, -8, 0, 22), Position = UDim2.new(0, 4, 1, -28), Text = caption, TextSize = 15,
		TextColor3 = captionColor, TextWrapped = false, ZIndex = z + 1 })

	-- chosen state: thick red rim, "Leaves" ribbon, and a dim sheet for the cards that are not chosen
	local ribbon = Instance.new("TextLabel")
	ribbon.Name = "Ribbon"
	ribbon.Size = UDim2.fromOffset(CARD_W - 24, 20)
	ribbon.Position = UDim2.fromOffset(12, 0)
	ribbon.BackgroundColor3 = RED
	ribbon.BorderSizePixel = 0
	ribbon.Font = Enum.Font.GothamBold
	ribbon.TextSize = 14
	ribbon.Text = "Leaves"
	ribbon.TextColor3 = CREAM
	ribbon.TextTransparency = 0
	ribbon.TextStrokeTransparency = 1
	ribbon.Visible = false
	ribbon.ZIndex = z + 6
	ribbon.Parent = card
	corner(ribbon, 5)
	local dim = Instance.new("Frame")
	dim.Name = "Dim"
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = Color3.fromRGB(20, 12, 6)
	dim.BackgroundTransparency = 0.55
	dim.BorderSizePixel = 0
	dim.Active = false
	dim.Visible = false
	dim.ZIndex = z + 5
	dim.Parent = card
	corner(dim, 10)
	return card, rim, ribbon, dim
end

function PackMakeRoom.new(deps)
	local z = deps.z or 20
	local self = {}
	local current -- { view, items, onConfirm, chosen = { [id] = true }, order = {}, kindOf = {}, cards = {}, need }

	local panel = Instance.new("Frame")
	panel.Name = "MakeRoomPanel"
	panel.AnchorPoint = Vector2.new(0.5, 1)
	panel.Position = UDim2.new(0.5, 0, 1, -112) -- above the Confirm and Skip Pack plates of the pick screen
	panel.Size = UDim2.fromOffset(760, 420)
	panel.BackgroundColor3 = WOOD
	panel.BorderSizePixel = 0
	panel.Active = true -- sinks clicks: nothing behind it reacts
	panel.Visible = false
	panel.ZIndex = z
	panel.Parent = deps.parent
	corner(panel, 15)
	stroke(panel, WOOD_EDGE, 2)
	local fit = Instance.new("UIScale")
	fit.Parent = panel
	local shadow = Instance.new("Frame") -- soft shadow under the wood
	shadow.Name = "Shadow"
	shadow.Position = UDim2.fromOffset(-10, 4)
	shadow.Size = UDim2.new(1, 20, 1, 20)
	shadow.BackgroundColor3 = Color3.new(0, 0, 0)
	shadow.BackgroundTransparency = 0.7
	shadow.BorderSizePixel = 0
	shadow.Active = false
	shadow.ZIndex = z - 1
	shadow.Parent = panel
	corner(shadow, 20)
	for i, at in ipairs({ { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 } }) do
		local stud = Instance.new("Frame")
		stud.Name = "WoodStud" .. i
		stud.AnchorPoint = Vector2.new(0.5, 0.5)
		stud.Position = UDim2.new(at[1], at[1] == 0 and 8 or -8, at[2], at[2] == 0 and 8 or -8)
		stud.Size = UDim2.fromOffset(9, 9)
		stud.BackgroundColor3 = Color3.fromRGB(205, 164, 84)
		stud.BorderSizePixel = 0
		stud.Active = false
		stud.ZIndex = z + 4
		stud.Parent = panel
		corner(stud, 5)
	end
	local sheet = Instance.new("Frame") -- the parchment inside the wood
	sheet.Name = "Sheet"
	sheet.Position = UDim2.fromOffset(8, 8)
	sheet.Size = UDim2.new(1, -16, 1, -16)
	sheet.BackgroundColor3 = Color3.fromRGB(238, 222, 186)
	sheet.BorderSizePixel = 0
	sheet.Active = false
	sheet.ZIndex = z + 1
	sheet.Parent = panel
	corner(sheet, 10)
	stroke(sheet, BRASS, 2)
	local sheetPaper = Instance.new("UIGradient")
	sheetPaper.Rotation = 90
	sheetPaper.Color = ColorSequence.new(Color3.fromRGB(246, 232, 198), Color3.fromRGB(228, 210, 172))
	sheetPaper.Parent = sheet

	label(sheet, { Name = "Title", Size = UDim2.new(1, -40, 0, TITLE_H), Position = UDim2.fromOffset(20, 12), Text = "Make room",
		TextSize = 26, TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = false, ZIndex = z + 2 })
	local subtitle = label(sheet, { Name = "Subtitle", Size = UDim2.new(1, -40, 0, SUB_H), Position = UDim2.fromOffset(20, 12 + TITLE_H), Text = "",
		TextSize = 16, Font = Enum.Font.GothamMedium, TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Center, ZIndex = z + 2 })

	local joinHead = label(sheet, { Name = "JoinHead", Size = UDim2.fromOffset(JOIN_W, 20), Position = UDim2.fromOffset(PAD, 0), Text = "Joins your table",
		TextSize = 15, TextColor3 = GREEN_INK, TextWrapped = false, ZIndex = z + 2 })
	local joinHolder = Instance.new("Frame")
	joinHolder.Name = "Joins"
	joinHolder.BackgroundTransparency = 1
	joinHolder.Active = false
	joinHolder.ZIndex = z + 2
	joinHolder.Parent = sheet

	local list = Instance.new("Frame")
	list.Name = "Owned"
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ZIndex = z + 2
	list.Parent = sheet
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(CARD_W, CARD_H)
	grid.CellPadding = UDim2.fromOffset(GAP, GAP)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.HorizontalAlignment = Enum.HorizontalAlignment.Left
	grid.Parent = list

	local summary = label(sheet, { Name = "Summary", Size = UDim2.new(1, -40, 0, SUMMARY_H), Text = "", TextSize = 16,
		Font = Enum.Font.GothamMedium, TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Center, ZIndex = z + 2 })

	local function plate(name, text, color)
		local b = Instance.new("TextButton")
		b.Name = name
		b.AnchorPoint = Vector2.new(0.5, 1)
		b.Size = UDim2.fromOffset(170, BUTTON_H)
		b.Font = Enum.Font.GothamBold
		b.TextSize = 16
		b.Text = text
		b.BackgroundColor3 = color
		b.TextColor3 = CREAM
		b.TextTransparency = 0
		b.TextStrokeTransparency = 1
		b.AutoButtonColor = true
		b.ZIndex = z + 3
		b.Parent = sheet
		corner(b, 8)
		stroke(b, Color3.fromRGB(150, 110, 52), 2)
		if deps.polishButton then pcall(deps.polishButton, b, 8) end
		return b
	end
	local backButton = plate("Back", "Back", Color3.fromRGB(70, 52, 40))
	local confirmButton = plate("Confirm", "Confirm", Color3.fromRGB(110, 72, 34))

	local function chosenList()
		local out = {}
		for _, id in ipairs(current.order) do
			if current.chosen[id] then out[#out + 1] = id end
		end
		return out
	end

	local function countOf(kind)
		local n = 0
		for id in pairs(current.chosen) do
			if current.kindOf[id] == kind then n = n + 1 end
		end
		return n
	end

	local function refresh()
		if not current then return end
		local info = PackRoom.summary(current.view, current.items, chosenList())
		local need = info.need
		local parts = {}
		if need.patrons > 0 then
			parts[#parts + 1] = string.format("Your table is full. Choose %d Patron%s to leave.", need.patrons, need.patrons == 1 and "" or "s")
		end
		if need.recipes > 0 then
			parts[#parts + 1] = string.format("Your recipe box is full. Choose %d recipe%s to leave.", need.recipes, need.recipes == 1 and "" or "s")
		end
		subtitle.Text = table.concat(parts, " ")
		local text = #info.lines > 0 and table.concat(info.lines, "\n") or "Tap the ones that should leave. They are sold at half price."
		if info.refund > 0 then text = text .. string.format("\nYou get $%d back.", info.refund) end
		summary.Text = text
		confirmButton.BackgroundColor3 = info.ready and Color3.fromRGB(110, 72, 34) or Color3.fromRGB(78, 66, 58)
		confirmButton.TextColor3 = info.ready and CREAM or Color3.fromRGB(200, 188, 168)
		confirmButton.Active = info.ready
		for id, c in pairs(current.cards) do
			local on = current.chosen[id] == true
			local kind = current.kindOf[id]
			local full = countOf(kind) >= (kind == "patron" and need.patrons or need.recipes)
			c.card:SetAttribute("Chosen", on)
			c.rim.Color = on and RED or c.baseRim
			c.rim.Thickness = on and 4 or 1.5
			c.ribbon.Visible = on
			c.dim.Visible = (not on) and full
		end
	end

	local function build()
		for _, c in ipairs(list:GetChildren()) do
			if c:IsA("GuiObject") then c:Destroy() end
		end
		for _, c in ipairs(joinHolder:GetChildren()) do
			if c:IsA("GuiObject") then c:Destroy() end
		end
		current.order, current.kindOf, current.cards = {}, {}, {}
		local need = PackRoom.overflow(current.view, current.items)
		current.need = need

		-- the incoming picks, on the left
		local joiners = PackRoom.joiners(current.view, current.items)
		for i, j in ipairs(joiners) do
			local card = buildCard(joinHolder, z + 3, j.kind, j.id, j.name, "Joins", GREEN_INK, false)
			card.Name = "Join_" .. j.id
			card.Size = UDim2.fromOffset(CARD_W, CARD_H)
			card.Position = UDim2.fromOffset(math.floor((JOIN_W - CARD_W) / 2), (i - 1) * (CARD_H + GAP))
		end

		local function add(kind, id, index)
			local card, rim, ribbon, dim = buildCard(list, z + 3, kind, id, PackRoom.nameOf(kind, id),
				string.format("Sells for $%d", PackRoom.sellValue(kind, id)), GREEN_INK, true)
			card.LayoutOrder = index
			current.order[#current.order + 1] = id
			current.kindOf[id] = kind
			current.cards[id] = { card = card, rim = rim, baseRim = rim.Color, ribbon = ribbon, dim = dim }
			card.MouseButton1Click:Connect(function()
				if deps.playClick then deps.playClick() end
				local limit = (kind == "patron") and need.patrons or need.recipes
				if current.chosen[id] then
					current.chosen[id] = nil
				elseif countOf(kind) < limit then
					current.chosen[id] = true
				end
				refresh()
			end)
		end
		local index = 0
		if need.patrons > 0 then
			for _, id in ipairs(current.view.ownedPatrons) do index = index + 1 add("patron", id, index) end
		end
		if need.recipes > 0 then
			local seen = {}
			for _, id in ipairs(current.view.recipes) do
				if not seen[id] then seen[id] = true index = index + 1 add("recipe", id, index) end -- a recipe owned twice shows once
			end
		end
		return #joiners
	end

	-- Size the panel to its content (no dead space): one row of cards on wide windows, two on narrow ones, then a fit scale so the
	-- whole panel stays inside the pick screen, above its Confirm and Skip Pack plates.
	local function layout(joinCount)
		local n = #current.order
		local host = deps.parent and deps.parent.AbsoluteSize
		local hostW, hostH = host and host.X or 0, host and host.Y or 0
		local cols = math.max(1, math.min(n, 6))
		if hostW > 0 and hostW < 900 and n > 3 then cols = math.ceil(n / 2) end
		local rows = math.max(1, math.ceil(n / cols))
		local ownedW = cols * CARD_W + (cols - 1) * GAP
		local ownedH = rows * CARD_H + (rows - 1) * GAP
		local joinH = joinCount * CARD_H + math.max(0, joinCount - 1) * GAP
		local bodyH = math.max(ownedH, joinH)
		local W = PAD + JOIN_W + 12 + ownedW + PAD + 16
		local top = 12 + TITLE_H + SUB_H + 6
		local H = top + 22 + bodyH + 8 + SUMMARY_H + 10 + BUTTON_H + 16 + 16
		panel.Size = UDim2.fromOffset(W, H)
		joinHead.Position = UDim2.fromOffset(PAD, top)
		joinHolder.Position = UDim2.fromOffset(PAD, top + 22)
		joinHolder.Size = UDim2.fromOffset(JOIN_W, joinH)
		list.Position = UDim2.fromOffset(PAD + JOIN_W + 12, top + 22)
		list.Size = UDim2.fromOffset(ownedW, ownedH)
		summary.Position = UDim2.fromOffset(20, top + 22 + bodyH + 8)
		backButton.Position = UDim2.new(0.5, -96, 1, -16)
		confirmButton.Position = UDim2.new(0.5, 96, 1, -16)
		local scale = 1
		if hostW > 0 and hostH > 0 then
			scale = math.max(0.6, math.min(1, (hostW - 24) / W, (hostH - 112 - 280) / H))
		end
		fit.Scale = scale
		panel:SetAttribute("PanelW", W)
		panel:SetAttribute("PanelH", H)
	end

	backButton.MouseButton1Click:Connect(function()
		if deps.playClick then deps.playClick() end
		self.close()
	end)
	confirmButton.MouseButton1Click:Connect(function()
		if not current then return end
		local ids = chosenList()
		local info = PackRoom.summary(current.view, current.items, ids)
		if not info.ready then return end
		local onConfirm = current.onConfirm
		self.close()
		if onConfirm then onConfirm(ids) end
	end)

	function self.open(view, items, onConfirm)
		current = { view = view, items = items, onConfirm = onConfirm, chosen = {}, order = {}, kindOf = {}, cards = {} }
		layout(build())
		refresh()
		panel.Visible = true
	end
	function self.close()
		panel.Visible = false
		current = nil
	end
	function self.isOpen() return panel.Visible end
	self.panel = panel
	return self
end

return PackMakeRoom
