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
local BiomeRewards = require(Engine:WaitForChild("BiomeRewards"))
local CardBacks = require(Engine:WaitForChild("CardBacks"))
local CosmeticSets = require(Engine:WaitForChild("CosmeticSets"))
local Achievements = require(Engine:WaitForChild("Achievements"))
local CompassWheel = require(script.Parent.CompassWheel)
local RoadLock = require(script.Parent.RoadLock)
local ModalStage = require(script.Parent.ModalStage)

-- "Dune Gold card back, Dune Wanderer title": the exact rewards at the end of a road (shown after the compass).
local function rewardText(region)
	local row = BiomeRewards.Rows[region]
	local names = {}
	for _, r in ipairs(row and row.reward or {}) do
		names[#names + 1] = BiomeRewards.label(r)
	end
	if row and row.bonus then
		local def = Achievements.getById(row.bonus.id)
		names[#names + 1] = (def and def.name or row.bonus.id) .. " title (all stops seen)"
	end
	return #names > 0 and table.concat(names, ", ") or "a surprise"
end

local INK = Color3.fromRGB(60, 40, 22)
local CREAM = Color3.fromRGB(250, 235, 200)
local GOLD = Color3.fromRGB(222, 182, 104)
local PARCHMENT = Color3.fromRGB(238, 222, 186) -- the paper of the Choose a blessing cards
local BRASS = Color3.fromRGB(200, 160, 84)

local CARD_W, CARD_H = 236, 330
local HEADER_H = 150 -- title, subtitle and the compass wheel
local PANEL_W = CARD_W * 3 + 4 * 16 + 24
local PANEL_H = HEADER_H + CARD_H + 70

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
	pcall(ModalStage.mount, backdrop, "road") -- map desk stage + modal gate
	pcall(function() require(script.Parent.ModalScene).build(backdrop, backdrop.ZIndex) end) -- the painted tavern room under a scrim, like the Choice screens

	local panel = Instance.new("Frame")
	panel.Name = "RoadChoicePanel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(PANEL_W, PANEL_H)
	panel.BackgroundColor3 = Color3.fromRGB(78, 52, 30)
	panel.ZIndex = 21
	panel.Parent = backdrop
	roundCorner(panel, 14)
	polishPanel(panel, 14, "wood")
	local panelEdge = Instance.new("UIStroke") -- brass edge on dark wood, like the Choice title plate
	panelEdge.Name = "PanelBrass"
	panelEdge.Color = BRASS
	panelEdge.Thickness = 3
	panelEdge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	panelEdge.Parent = panel
	-- A mid-run choice is not abandonable (it has its own Later button), but Escape opens Settings above it so nobody is stuck
	-- (Client/PopupDismiss, policy "locked").
	require(script.Parent.PopupDismiss).attach(backdrop, { policy = "locked", panel = panel, button = true })
	local fit = Instance.new("UIScale") -- keeps the whole panel on screen at small viewports
	fit.Parent = panel

	local title = label(panel, {
		Size = UDim2.new(1, -190, 0, 34), Position = UDim2.fromOffset(20, 12), Text = "Choose your road",
		TextSize = 26, TextColor3 = CREAM, ZIndex = 22,
	})
	title.TextStrokeTransparency = 0.8
	title.TextStrokeColor3 = Color3.fromRGB(30, 18, 8)
	local subtitle = label(panel, {
		Size = UDim2.new(1, -190, 0, 36), Position = UDim2.fromOffset(20, 44), Text = "",
		TextSize = 16, TextColor3 = Color3.fromRGB(235, 218, 180), ZIndex = 22, Font = Enum.Font.GothamMedium,
	})

	local row = Instance.new("Frame")
	row.Name = "Roads"
	row.BackgroundTransparency = 1
	row.AnchorPoint = Vector2.new(0.5, 0)
	row.Position = UDim2.new(0.5, 0, 0, HEADER_H)
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
	chip.Text = "Choose your road"
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
	local cardByStop = {} -- [stopId] = { stroke, rewardLabel, region }
	local currentStopId = WorldMap.Start
	local latestState = nil

	-- Compass wheel: turn it (drag or tap a rim icon) and the road it points at lights up.
	local function highlight(stopId)
		for id, c in pairs(cardByStop) do
			local on = id == stopId
			c.stroke.Color = on and GOLD or BRASS
			c.stroke.Thickness = on and 5 or 3
		end
	end
	local wheel = CompassWheel.new({
		parent = panel, size = 118,
		onTurn = function(bearing, id)
			highlight(id or WorldMap.pickByBearing(currentStopId, bearing))
		end,
	})
	wheel.frame.AnchorPoint = Vector2.new(1, 0)
	wheel.frame.Position = UDim2.new(1, -30, 0, 14)
	wheel.frame.ZIndex = 22

	local revealButton = Instance.new("TextButton")
	revealButton.Name = "UseCompass"
	revealButton.Position = UDim2.fromOffset(20, 84)
	revealButton.Size = UDim2.fromOffset(250, 38)
	revealButton.BackgroundColor3 = GOLD
	revealButton.Text = "Use compass: reveal rewards"
	revealButton.Font = Enum.Font.GothamBold
	revealButton.TextSize = 16
	revealButton.TextColor3 = INK
	revealButton.ZIndex = 22
	revealButton.Visible = false
	revealButton.Parent = panel
	roundCorner(revealButton, 8)
	revealButton.MouseButton1Click:Connect(function()
		playClickSfx()
		local folder = ReplicatedStorage:FindFirstChild("Remotes")
		local r = folder and folder:FindFirstChild("UseCompass")
		if r then
			r:FireServer()
		end
	end)

	local function remote()
		local folder = ReplicatedStorage:FindFirstChild("Remotes")
		return folder and folder:FindFirstChild("ChooseRoad")
	end

	local function clearCards()
		for _, c in ipairs(cards) do
			c:Destroy()
		end
		cards = {}
		cardByStop = {}
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
		stroke.Color = BRASS
		stroke.Thickness = 3
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
			Size = UDim2.fromScale(1, 1), Text = stop.icon or "?", TextSize = 56, ZIndex = 25,
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
		local rewardLabel = label(card, {
			Size = UDim2.new(1, -20, 0, 52), Position = UDim2.fromOffset(10, 224),
			Text = "At the end of this road: a " .. (region and region.name or "biome") .. " reward",
			TextSize = 15, TextColor3 = Color3.fromRGB(120, 84, 24), TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 24,
		})
		cardByStop[stopId] = { stroke = stroke, rewardLabel = rewardLabel, region = stop.region, take = nil, lock = nil }

		local take = Instance.new("TextButton")
		take.Name = "TakeRoad"
		take.AnchorPoint = Vector2.new(0.5, 1)
		take.Position = UDim2.new(0.5, 0, 1, -10)
		take.Size = UDim2.new(1, -24, 0, 40)
		take.BackgroundColor3 = Color3.fromRGB(46, 98, 52) -- the Choose button green
		take.Text = "Take this road"
		take.Font = Enum.Font.GothamBold
		take.TextSize = 18
		take.TextColor3 = CREAM
		take.ZIndex = 24
		take.Parent = card
		roundCorner(take, 8)
		cardByStop[stopId].take = take
		-- padlock on the art when the road needs a Key (shown by refreshLocks)
		local lock = label(strip, {
			AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -6, 0, 6), Size = UDim2.fromOffset(40, 40),
			Text = "Lock", TextSize = 20, ZIndex = 28, BackgroundTransparency = 0.25, BackgroundColor3 = Color3.fromRGB(40, 28, 18),
		})
		lock.Visible = false
		roundCorner(lock, 20)
		cardByStop[stopId].lock = lock
		local pending = false
		take.MouseButton1Click:Connect(function()
			if pending then return end
			playClickSfx()
			RoadLock.pick(stopId, latestState, backdrop, stop.name, function()
				pending = true
				require(script.Parent.Cue).play("road_choose")
				local r = remote()
				if r then
					r:FireServer(stopId)
				end
				-- The next state push hides the panel; re-arm if it never comes (rejected pick).
				task.delay(2, function()
					pending = false
				end)
			end)
		end)
		table.insert(cards, card)
	end

	local function fitToScreen()
		local size = root.AbsoluteSize
		local needW, needH = PANEL_W, PANEL_H
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

	-- Wheel icons, idle bearing (toward the Keeper's Table) and compass state for the current fork.
	local function refreshCompass(state, choices)
		local route = state.worldRoute
		currentStopId = (type(route) == "table" and route[#route]) or WorldMap.Start
		local icons = {}
		for _, id in ipairs(choices) do
			local stop = WorldMap.Stops[id]
			if stop then
				icons[#icons + 1] = { bearing = WorldMap.bearing(currentStopId, id) or 0, text = stop.icon or "?", id = id }
			end
		end
		wheel.setIcons(icons)
		wheel.setCharges(state.compassCharges or 0)
		wheel.setBearing(WorldMap.bearing(currentStopId, WorldMap.Finish) or 90, true)
		highlight(nil)
	end

	-- After a compass charge is spent the cards name their exact rewards.
	local function refreshReveal(state, choices)
		local revealed = {}
		for _, id in ipairs(type(state.compassReveal) == "table" and state.compassReveal or {}) do
			revealed[id] = true
		end
		for _, id in ipairs(choices) do
			local c = cardByStop[id]
			if c then
				c.rewardLabel.Text = revealed[id] and ("Reward: " .. rewardText(c.region))
					or ("At the end of this road: a " .. (WorldMap.Regions[c.region] and WorldMap.Regions[c.region].name or "biome") .. " reward")
			end
		end
		local canUse = (state.compassCharges or 0) > 0 and next(revealed) == nil
		revealButton.Visible = canUse
		wheel.setCharges(state.compassCharges or 0)
	end

	-- Padlock + button text for roads that need a Key (the whole map keeps them visible).
	local function refreshLocks(state, choices)
		for _, id in ipairs(choices) do
			local c = cardByStop[id]
			if c and c.take then
				local locked = RoadLock.isLocked(state, id)
				c.lock.Visible = locked
				c.take.Text = locked and (RoadLock.keys(state) > 0 and "Unlock with a Key" or "Locked: needs a Key") or "Take this road"
				c.take.BackgroundColor3 = locked and Color3.fromRGB(150, 110, 50) or Color3.fromRGB(86, 140, 70)
			end
		end
	end

	function M.update(state)
		latestState = state
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
			subtitle.Text = string.format("Night %d: the road splits. Turn the compass or pick a card.", math.floor(state.night or 1))
			for i, id in ipairs(choices) do
				if WorldMap.Stops[id] then
					buildCard(i, id)
				end
			end
			refreshCompass(state, choices)
		end
		refreshReveal(state, choices)
		refreshLocks(state, choices)
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
