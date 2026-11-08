--[[
	Client/RoadChoice.lua
	The fork screen of the branching adventure map (claude/MAP_DESIGN.md section 3).
	When the server state has `worldChoices` (2 or 3 roads to pick from, Round Select of a new Night) this
	shows one card per road: biome tint, stop art or icon, name, biome, one-line hint and what waits at the
	end of the road, with a "Take this road" button that fires the ChooseRoad remote. The server validates
	everything; this only displays and asks. "Decide later" hides the panel (a small "Choose your road" chip
	stays); leaving Round Select without a pick takes the default road on the server.

	Built once by RoundSelect.lua: require(RoadChoice)({ root, polishPanel, polishButton, roundCorner,
	playClickSfx }) -> { update = function(state), destroy = function() }. Text is 15px or larger.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Engine = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine")
local WorldMap = require(Engine:WaitForChild("WorldMap"))
local ContentArt = require(Engine:WaitForChild("ContentArt"))

local INK = Color3.fromRGB(60, 40, 22)
local CREAM = Color3.fromRGB(250, 235, 200)
local GOLD = Color3.fromRGB(222, 182, 104)
local PARCHMENT = Color3.fromRGB(222, 198, 150)

local CARD_W, CARD_H = 236, 330

return function(deps)
	local root = deps.root
	local polishPanel, roundCorner = deps.polishPanel, deps.roundCorner
	local playClickSfx = deps.playClickSfx or function() end

	local function label(parent, props)
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Font = Enum.Font.GothamBold
		l.TextSize = 16
		l.TextColor3 = INK
		l.TextWrapped = true
		l.TextTransparency = 0
		l.TextStrokeTransparency = 1
		for k, v in pairs(props) do
			l[k] = v
		end
		l.Parent = parent
		return l
	end

	-- Input sink + dim, above Round Select (ZIndex 6).
	local backdrop = Instance.new("TextButton")
	backdrop.Name = "RoadChoiceBackdrop"
	backdrop.Text = ""
	backdrop.AutoButtonColor = false
	backdrop.Active = true
	backdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	backdrop.BackgroundTransparency = 0.45
	backdrop.BorderSizePixel = 0
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.ZIndex = 20
	backdrop.Visible = false
	backdrop.Parent = root

	local panel = Instance.new("Frame")
	panel.Name = "RoadChoicePanel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(CARD_W * 3 + 4 * 16 + 24, CARD_H + 150)
	panel.BackgroundColor3 = Color3.fromRGB(78, 52, 30)
	panel.ZIndex = 21
	panel.Parent = backdrop
	roundCorner(panel, 14)
	polishPanel(panel, 14, "wood")
	local fit = Instance.new("UIScale") -- keeps the whole panel on screen at small viewports
	fit.Parent = panel

	local title = label(panel, {
		Size = UDim2.new(1, -40, 0, 34), Position = UDim2.fromOffset(20, 12), Text = "Choose your road",
		TextSize = 26, TextColor3 = CREAM, ZIndex = 22,
	})
	title.TextStrokeTransparency = 0.3
	title.TextStrokeColor3 = Color3.fromRGB(30, 18, 8)
	local subtitle = label(panel, {
		Size = UDim2.new(1, -40, 0, 24), Position = UDim2.fromOffset(20, 48), Text = "",
		TextSize = 16, TextColor3 = Color3.fromRGB(235, 218, 180), ZIndex = 22, Font = Enum.Font.GothamMedium,
	})

	local row = Instance.new("Frame")
	row.Name = "Roads"
	row.BackgroundTransparency = 1
	row.AnchorPoint = Vector2.new(0.5, 0)
	row.Position = UDim2.new(0.5, 0, 0, 82)
	row.Size = UDim2.new(1, -24, 0, CARD_H)
	row.ZIndex = 22
	row.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0, 16)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = row

	local laterButton = Instance.new("TextButton")
	laterButton.Name = "DecideLater"
	laterButton.AnchorPoint = Vector2.new(0.5, 1)
	laterButton.Position = UDim2.new(0.5, 0, 1, -14)
	laterButton.Size = UDim2.fromOffset(190, 38)
	laterButton.BackgroundColor3 = Color3.fromRGB(110, 76, 44)
	laterButton.Text = "Decide later"
	laterButton.Font = Enum.Font.GothamBold
	laterButton.TextSize = 17
	laterButton.TextColor3 = CREAM
	laterButton.ZIndex = 22
	laterButton.Parent = panel
	roundCorner(laterButton, 8)

	-- Small chip that brings the panel back after "Decide later".
	local chip = Instance.new("TextButton")
	chip.Name = "ChooseRoadChip"
	chip.AnchorPoint = Vector2.new(0.5, 0)
	chip.Position = UDim2.new(0.5, 0, 0, 10)
	chip.Size = UDim2.fromOffset(220, 38)
	chip.BackgroundColor3 = Color3.fromRGB(222, 182, 104)
	chip.Text = "🧭 Choose your road"
	chip.Font = Enum.Font.GothamBold
	chip.TextSize = 17
	chip.TextColor3 = INK
	chip.ZIndex = 8
	chip.Visible = false
	chip.Parent = root
	roundCorner(chip, 10)

	local dismissedKey = nil
	local currentKey = nil
	local cards = {}

	local function remote()
		local folder = ReplicatedStorage:FindFirstChild("Remotes")
		return folder and folder:FindFirstChild("ChooseRoad")
	end

	local function clearCards()
		for _, c in ipairs(cards) do
			c:Destroy()
		end
		cards = {}
	end

	local function buildCard(order, stopId)
		local stop = WorldMap.Stops[stopId]
		local region = WorldMap.Regions[stop.region]
		local tint = region and region.tint or { 200, 190, 150 }

		local card = Instance.new("Frame")
		card.Name = "Road_" .. stopId
		card.LayoutOrder = order
		card.Size = UDim2.fromOffset(CARD_W, CARD_H)
		card.BackgroundColor3 = PARCHMENT
		card.BorderSizePixel = 0
		card.ZIndex = 23
		card.Parent = row
		roundCorner(card, 12)
		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.fromRGB(110, 80, 45)
		stroke.Thickness = 2
		stroke.Parent = card

		-- Biome strip with the stop art (emoji behind it so a missing or slow image never leaves it empty).
		local strip = Instance.new("Frame")
		strip.Size = UDim2.new(1, -16, 0, 120)
		strip.Position = UDim2.fromOffset(8, 8)
		strip.BackgroundColor3 = Color3.fromRGB(tint[1], tint[2], tint[3])
		strip.BorderSizePixel = 0
		strip.ClipsDescendants = true
		strip.ZIndex = 24
		strip.Parent = card
		roundCorner(strip, 8)
		label(strip, {
			Size = UDim2.fromScale(1, 1), Text = stop.icon or "🧭", TextSize = 56, ZIndex = 25,
			TextWrapped = false, Font = Enum.Font.GothamBold,
		})
		local artId = ContentArt.getImageId("map_nodes", stop.art)
		if artId then
			local img = Instance.new("ImageLabel")
			img.Name = "ContentArt"
			img.BackgroundTransparency = 1
			img.Size = UDim2.fromScale(1, 1)
			img.Image = artId
			img.ScaleType = Enum.ScaleType.Crop
			img.ZIndex = 26
			img.Parent = strip
		end

		label(card, {
			Size = UDim2.new(1, -20, 0, 24), Position = UDim2.fromOffset(10, 134), Text = stop.name,
			TextSize = 19, ZIndex = 24,
		})
		label(card, {
			Size = UDim2.new(1, -20, 0, 20), Position = UDim2.fromOffset(10, 160),
			Text = region and region.name or "", TextSize = 15, TextColor3 = Color3.fromRGB(110, 76, 44),
			Font = Enum.Font.GothamMedium, ZIndex = 24,
		})
		label(card, {
			Size = UDim2.new(1, -20, 0, 40), Position = UDim2.fromOffset(10, 184), Text = stop.hint or "",
			TextSize = 15, Font = Enum.Font.GothamMedium, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 24,
		})
		label(card, {
			Size = UDim2.new(1, -20, 0, 40), Position = UDim2.fromOffset(10, 228),
			Text = "At the end of this road: a " .. (region and region.name or "biome") .. " reward",
			TextSize = 15, TextColor3 = Color3.fromRGB(120, 84, 24), TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 24,
		})

		local take = Instance.new("TextButton")
		take.Name = "TakeRoad"
		take.AnchorPoint = Vector2.new(0.5, 1)
		take.Position = UDim2.new(0.5, 0, 1, -10)
		take.Size = UDim2.new(1, -24, 0, 40)
		take.BackgroundColor3 = Color3.fromRGB(86, 140, 70)
		take.Text = "Take this road"
		take.Font = Enum.Font.GothamBold
		take.TextSize = 18
		take.TextColor3 = CREAM
		take.ZIndex = 24
		take.Parent = card
		roundCorner(take, 8)
		local pending = false
		take.MouseButton1Click:Connect(function()
			if pending then return end
			pending = true
			playClickSfx()
			local r = remote()
			if r then
				r:FireServer(stopId)
			end
			-- The next state push hides the panel; re-arm if it never comes (rejected pick).
			task.delay(2, function()
				pending = false
			end)
		end)
		table.insert(cards, card)
	end

	local function fitToScreen()
		local size = root.AbsoluteSize
		local needW, needH = CARD_W * 3 + 4 * 16 + 24, CARD_H + 150
		fit.Scale = math.clamp(math.min((size.X - 40) / needW, (size.Y - 40) / needH), 0.5, 1)
	end

	local function show()
		backdrop.Visible = true
		chip.Visible = false
		fitToScreen()
	end

	laterButton.MouseButton1Click:Connect(function()
		dismissedKey = currentKey
		backdrop.Visible = false
		chip.Visible = currentKey ~= nil
	end)
	chip.MouseButton1Click:Connect(function()
		dismissedKey = nil
		show()
	end)

	local M = {}

	function M.update(state)
		local choices = type(state) == "table" and state.phase == "roundSelect" and state.worldChoices or nil
		if type(choices) ~= "table" or #choices < 2 then
			currentKey = nil
			dismissedKey = nil
			backdrop.Visible = false
			chip.Visible = false
			return
		end
		local key = tostring(state.night) .. ":" .. table.concat(choices, ",")
		if key ~= currentKey then
			currentKey = key
			clearCards()
			subtitle.Text = string.format("Night %d: the road splits. Pick where to go next.", math.floor(state.night or 1))
			for i, id in ipairs(choices) do
				if WorldMap.Stops[id] then
					buildCard(i, id)
				end
			end
		end
		if dismissedKey == key then
			backdrop.Visible = false
			chip.Visible = true
		else
			show()
		end
	end

	function M.destroy()
		clearCards()
		backdrop:Destroy()
		chip:Destroy()
	end

	return M
end
