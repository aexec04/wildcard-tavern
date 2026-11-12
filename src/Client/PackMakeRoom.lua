--[[
	Client/PackMakeRoom.lua
	The "Make room" step of a pack pick. When the picked Patrons (or Recipes) do not fit the table (or the recipe box), Confirm opens this
	calm painted-wood panel instead of firing the pick: the owned Patrons (or Recipes) that could leave are small cards with their sell
	value, tap one to choose it (tap again to put it back), and a line says "X leaves, Y joins your table." with the Tips that come back.
	Back returns to change the pick. Confirm fires the same ResolvePack remote with the chosen ids as its second argument; the server
	(Engine/PackRoom) checks they are owned, distinct and exactly the overflow. A multi-pick pack asks for every overflowing pick at once,
	one line per pair. Text is 15 px or more.

	PackMakeRoom.new{ parent, z, playClick } -> { open(view, items, onConfirm), close(), isOpen() }
	  view  = { ownedPatrons = { id }, recipes = { id }, patronLimit, recipeLimit }   (Engine/PackRoom)
	  items = the picked reveal items ({ id, name, category })
	  onConfirm(replaceIds)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PackRoom = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("PackRoom"))

local PackMakeRoom = {}

local WOOD = Color3.fromRGB(70, 48, 30)
local WOOD_DARK = Color3.fromRGB(40, 28, 18)
local BRASS = Color3.fromRGB(200, 160, 84)
local CREAM = Color3.fromRGB(250, 238, 212)
local GOLD = Color3.fromRGB(255, 214, 130)
local PAPER = Color3.fromRGB(226, 208, 168)
local INK = Color3.fromRGB(46, 32, 20)

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

local function label(parent, props)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBold
	l.TextSize = 16
	l.TextColor3 = CREAM
	l.TextTransparency = 0
	l.TextStrokeTransparency = 1
	l.TextWrapped = true
	for k, v in pairs(props) do l[k] = v end
	l.Parent = parent
	return l
end

function PackMakeRoom.new(deps)
	local z = deps.z or 20
	local self = {}
	local current -- { view, items, onConfirm, chosen = { [id] = true }, order = {} }

	local panel = Instance.new("Frame")
	panel.Name = "MakeRoomPanel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(640, 440)
	panel.BackgroundColor3 = WOOD
	panel.Active = true -- sinks clicks: nothing behind it reacts
	panel.Visible = false
	panel.ZIndex = z
	panel.Parent = deps.parent
	corner(panel, 14)
	stroke(panel, BRASS, 3)
	local fit = Instance.new("UIScale")
	fit.Parent = panel

	local title = label(panel, { Name = "Title", Size = UDim2.new(1, -40, 0, 34), Position = UDim2.fromOffset(20, 14), Text = "Make room",
		TextSize = 26, TextColor3 = GOLD, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = z + 1 })
	local subtitle = label(panel, { Name = "Subtitle", Size = UDim2.new(1, -40, 0, 40), Position = UDim2.fromOffset(20, 50), Text = "",
		TextSize = 16, Font = Enum.Font.GothamMedium, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = z + 1 })

	local list = Instance.new("ScrollingFrame")
	list.Name = "Owned"
	list.Position = UDim2.fromOffset(20, 96)
	list.Size = UDim2.new(1, -40, 0, 170)
	list.BackgroundColor3 = WOOD_DARK
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 6
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.ZIndex = z + 1
	list.Parent = panel
	corner(list, 8)
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(190, 64)
	grid.CellPadding = UDim2.fromOffset(8, 8)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = list
	local pad = Instance.new("UIPadding")
	pad.PaddingTop, pad.PaddingLeft = UDim.new(0, 8), UDim.new(0, 8)
	pad.Parent = list

	local summary = label(panel, { Name = "Summary", Size = UDim2.new(1, -40, 0, 78), Position = UDim2.fromOffset(20, 276), Text = "",
		TextSize = 16, Font = Enum.Font.GothamMedium, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = z + 1 })

	local function plate(name, text, x, color)
		local b = Instance.new("TextButton")
		b.Name = name
		b.AnchorPoint = Vector2.new(0.5, 1)
		b.Size = UDim2.fromOffset(170, 42)
		b.Position = UDim2.new(0.5, x, 1, -16)
		b.Font = Enum.Font.GothamBold
		b.TextSize = 17
		b.Text = text
		b.BackgroundColor3 = color
		b.TextColor3 = CREAM
		b.AutoButtonColor = true
		b.ZIndex = z + 2
		b.Parent = panel
		corner(b, 8)
		stroke(b, BRASS, 2)
		return b
	end
	local backButton = plate("Back", "Back", -96, Color3.fromRGB(70, 52, 40))
	local confirmButton = plate("Confirm", "Confirm", 96, Color3.fromRGB(110, 72, 34))

	local function chosenList()
		local out = {}
		for _, id in ipairs(current.order) do
			if current.chosen[id] then out[#out + 1] = id end
		end
		return out
	end

	local function refresh()
		if not current then return end
		local ids = chosenList()
		local info = PackRoom.summary(current.view, current.items, ids)
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
		confirmButton.BackgroundColor3 = info.ready and Color3.fromRGB(110, 72, 34) or Color3.fromRGB(70, 60, 55)
		confirmButton.Active = info.ready
		for _, card in ipairs(list:GetChildren()) do
			if card:IsA("TextButton") then
				local on = current.chosen[card.Name] == true
				card.BackgroundColor3 = on and Color3.fromRGB(150, 110, 52) or PAPER
				local st = card:FindFirstChildOfClass("UIStroke")
				if st then st.Color = on and GOLD or BRASS st.Thickness = on and 3 or 1.5 end
			end
		end
	end

	local function build()
		for _, c in ipairs(list:GetChildren()) do
			if c:IsA("TextButton") then c:Destroy() end
		end
		current.order = {}
		local need = PackRoom.overflow(current.view, current.items)
		local function add(kind, id, index)
			local card = Instance.new("TextButton")
			card.Name = id
			card.LayoutOrder = index
			card.AutoButtonColor = false
			card.Text = ""
			card.BackgroundColor3 = PAPER
			card.BorderSizePixel = 0
			card.ZIndex = z + 2
			card.Parent = list
			corner(card, 8)
			stroke(card, BRASS, 1.5)
			label(card, { Name = "Name", Size = UDim2.new(1, -12, 0, 24), Position = UDim2.fromOffset(6, 6), Text = PackRoom.nameOf(kind, id), TextSize = 16,
				TextColor3 = INK, TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = z + 3 })
			label(card, { Name = "Value", Size = UDim2.new(1, -12, 0, 20), Position = UDim2.fromOffset(6, 34), Text = string.format("Sells for $%d", PackRoom.sellValue(kind, id)),
				TextSize = 15, Font = Enum.Font.GothamMedium, TextColor3 = Color3.fromRGB(96, 60, 20), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = z + 3 })
			current.order[#current.order + 1] = id
			card.MouseButton1Click:Connect(function()
				if deps.playClick then deps.playClick() end
				local limit = (kind == "patron") and need.patrons or need.recipes
				local count = 0
				for _, other in ipairs(chosenList()) do
					local isPatron = false
					for _, pid in ipairs(current.view.ownedPatrons) do if pid == other then isPatron = true break end end
					if (kind == "patron") == isPatron then count = count + 1 end
				end
				if current.chosen[id] then
					current.chosen[id] = nil
				elseif count < limit then
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
		current = { view = view, items = items, onConfirm = onConfirm, chosen = {}, order = {} }
		build()
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
