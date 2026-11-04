--[[
	Client/JourneyMapView.lua
	The "Tavern Map" tab of the Journey screen: the 8 named Night locations
	on a painted-map path (UI elements only), plus an Endless Mode node.

	Each node shows its icon, name, one-line description, boss tier
	(Boss ★ to ★★★) and the first-clear reward. Locked nodes preview the
	reward; cleared nodes say "Earned". The path fills in up to the furthest
	Night reached. All content is in Shared/Engine/JourneyMap.lua.

	State used: state.clearedNightIds, state.night, state.wonRun,
	state.profileStats.bestNightReached.

	deps: parent (the Journey panel), polishPanel, roundCorner,
	getLatestState, titleLabel, subtitleLabel

	Returns:
		{
			frame = Frame,
			refresh = function(),
			setShown = function(bool),
			applyHeader = function(isMapTab) -- title/subtitle text and colors
		}
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

return function(deps)
	local Engine = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine")
	local JourneyMap = require(Engine:WaitForChild("JourneyMap"))
	local CardBacks = require(Engine:WaitForChild("CardBacks"))
	local CosmeticSets = require(Engine:WaitForChild("CosmeticSets"))
	local Achievements = require(Engine:WaitForChild("Achievements"))
	local lookups = { cardBack = CardBacks, set = CosmeticSets, title = Achievements }

	local COL = 156 -- horizontal space per node
	local PAD = 20
	local CARD_W, CARD_H = 144, 134
	local LINE_Y = 150
	local CANVAS_H = 300
	local ENDLESS_INDEX = JourneyMap.NightCap + 1

	local CREAM = Color3.fromRGB(250, 240, 220)
	local SOFT = Color3.fromRGB(215, 200, 178)
	local DIM = Color3.fromRGB(140, 130, 120)
	local GOLD = Color3.fromRGB(255, 214, 130)
	local GREEN = Color3.fromRGB(126, 161, 116)
	local PURPLE = Color3.fromRGB(180, 140, 255)
	local MAP_BG = Color3.fromRGB(58, 44, 30)
	local MAP_BG_ENDLESS = Color3.fromRGB(34, 26, 54)

	local frame = Instance.new("Frame")
	frame.Name = "TavernMap"
	frame.Size = UDim2.new(1, -20, 1, -124)
	frame.Position = UDim2.new(0, 10, 0, 68)
	frame.BackgroundColor3 = MAP_BG
	frame.ZIndex = 21
	frame.Visible = false
	frame.Parent = deps.parent
	deps.polishPanel(frame, 10, "parchment")

	local scroll = Instance.new("ScrollingFrame")
	scroll.Size = UDim2.new(1, -16, 1, -12)
	scroll.Position = UDim2.fromOffset(8, 6)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 8
	scroll.ScrollingDirection = Enum.ScrollingDirection.X
	scroll.CanvasSize = UDim2.fromOffset(PAD * 2 + COL * ENDLESS_INDEX, 0)
	scroll.ZIndex = 22
	scroll.Parent = frame

	local lineWidth = COL * ENDLESS_INDEX
	local baseLine = Instance.new("Frame")
	baseLine.Size = UDim2.fromOffset(lineWidth, 6)
	baseLine.Position = UDim2.fromOffset(PAD, LINE_Y - 3)
	baseLine.BackgroundColor3 = Color3.fromRGB(30, 22, 16)
	baseLine.BorderSizePixel = 0
	baseLine.ZIndex = 22
	baseLine.Parent = scroll
	deps.roundCorner(baseLine, 3)

	local fillLine = Instance.new("Frame")
	fillLine.Size = UDim2.fromOffset(0, 6)
	fillLine.Position = baseLine.Position
	fillLine.BackgroundColor3 = GOLD
	fillLine.BorderSizePixel = 0
	fillLine.ZIndex = 23
	fillLine.Parent = scroll
	deps.roundCorner(fillLine, 3)

	local function text(parent, props)
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Font = Enum.Font.Gotham
		l.TextColor3 = CREAM
		l.TextTransparency = 0
		l.TextStrokeTransparency = 1
		l.TextWrapped = true
		l.ZIndex = 25
		for k, v in pairs(props) do
			l[k] = v
		end
		l.Parent = parent
		return l
	end

	-- One entry per node: { card, stroke, dot, dotLabel, name, desc, tier, reward, tag }
	local nodes = {}

	local function buildNode(index)
		local isEndless = index == ENDLESS_INDEX
		local info = isEndless and JourneyMap.Endless or JourneyMap.Nights[index]
		local centerX = PAD + (index - 0.5) * COL
		local above = index % 2 == 1

		local dot = Instance.new("Frame")
		dot.Size = UDim2.fromOffset(26, 26)
		dot.AnchorPoint = Vector2.new(0.5, 0.5)
		dot.Position = UDim2.fromOffset(centerX, LINE_Y)
		dot.BackgroundColor3 = Color3.fromRGB(60, 46, 32)
		dot.BorderSizePixel = 0
		dot.ZIndex = 24
		dot.Parent = scroll
		deps.roundCorner(dot, 13)
		local dotStroke = Instance.new("UIStroke")
		dotStroke.Thickness = 2
		dotStroke.Parent = dot
		local dotLabel = text(dot, {
			Size = UDim2.fromScale(1, 1), Font = Enum.Font.GothamBold, TextSize = 13,
			Text = isEndless and "∞" or tostring(index),
		})

		local card = Instance.new("Frame")
		card.Size = UDim2.fromOffset(CARD_W, CARD_H)
		card.AnchorPoint = Vector2.new(0.5, 0)
		card.Position = UDim2.fromOffset(centerX, above and 6 or (LINE_Y + 18))
		card.BackgroundColor3 = Color3.fromRGB(35, 26, 18)
		card.ZIndex = 23
		card.Parent = scroll
		deps.roundCorner(card, 8)
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 2
		stroke.Parent = card

		text(card, {
			Size = UDim2.fromOffset(28, 28), Position = UDim2.fromOffset(6, 4), TextSize = 22, Text = info.icon,
		})
		local name = text(card, {
			Size = UDim2.new(1, -40, 0, 28), Position = UDim2.fromOffset(36, 4),
			Font = Enum.Font.GothamBold, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left,
			Text = info.name,
		})
		local desc = text(card, {
			Size = UDim2.new(1, -12, 0, 40), Position = UDim2.fromOffset(6, 34),
			TextSize = 10, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
			TextColor3 = SOFT, Text = info.description,
		})
		local tier = text(card, {
			Size = UDim2.fromOffset(CARD_W - 58, 14), Position = UDim2.fromOffset(6, 76),
			TextSize = 11, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = SOFT,
			Text = isEndless and "Boss ★★★ and beyond" or "",
		})
		if not isEndless then
			local stars = JourneyMap.bossTierFor(index)
			tier.Text = "👑 Boss " .. string.rep("★", stars) .. string.rep("☆", 3 - stars)
		end
		local reward = text(card, {
			Size = UDim2.new(1, -12, 0, 36), Position = UDim2.fromOffset(6, 92),
			TextSize = 10, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
			Text = "",
		})
		local tag = text(card, {
			Size = UDim2.fromOffset(46, 14), Position = UDim2.fromOffset(CARD_W - 52, 76),
			Font = Enum.Font.GothamBold, TextSize = 10, TextXAlignment = Enum.TextXAlignment.Right,
			Text = "", Visible = false,
		})

		nodes[index] = {
			card = card, stroke = stroke, dot = dot, dotStroke = dotStroke, dotLabel = dotLabel,
			name = name, desc = desc, tier = tier, reward = reward, tag = tag, centerX = centerX,
			above = above, isEndless = isEndless,
		}
	end

	for index = 1, ENDLESS_INDEX do
		buildNode(index)
	end

	local function currentView()
		local state = deps.getLatestState()
		local cleared = {}
		local best = 0
		local night = 0
		local won = false
		if state then
			for _, n in ipairs(state.clearedNightIds or {}) do
				cleared[n] = true
			end
			best = state.profileStats and state.profileStats.bestNightReached or 0
			night = state.night or 0
			won = state.wonRun == true
		end
		local reached = math.max(best, night)
		local inEndless = night > JourneyMap.NightCap
		return {
			state = state, cleared = cleared, reached = reached, night = night,
			inEndless = inEndless, endlessOpen = cleared[JourneyMap.NightCap] == true or reached > JourneyMap.NightCap or won,
		}
	end

	local function refresh()
		local view = currentView()
		local reachedIndex = math.min(view.reached, ENDLESS_INDEX)
		local currentIndex = view.state and math.min(math.max(view.night, 1), ENDLESS_INDEX) or nil

		for index, node in ipairs(nodes) do
			local isCleared = view.cleared[index] == true
			local isReached = index <= reachedIndex
			local isCurrent = currentIndex == index
			local locked
			if node.isEndless then
				locked = not view.endlessOpen
				isCleared = false
			else
				locked = not isReached and not isCleared
			end

			local accent = node.isEndless and PURPLE or GOLD
			local strokeColor = isCleared and GREEN or (isCurrent and accent) or (locked and Color3.fromRGB(70, 58, 46)) or Color3.fromRGB(150, 115, 50)
			node.stroke.Color = strokeColor
			node.dotStroke.Color = strokeColor
			node.dot.BackgroundColor3 = isCleared and GREEN or (isCurrent and accent) or Color3.fromRGB(60, 46, 32)
			node.dotLabel.Text = isCleared and "✓" or (node.isEndless and "∞" or tostring(index))
			node.dotLabel.TextColor3 = (isCleared or isCurrent) and Color3.fromRGB(30, 22, 16) or CREAM

			local dim = locked and DIM or CREAM
			node.name.TextColor3 = dim
			node.desc.TextColor3 = locked and DIM or SOFT
			node.tier.TextColor3 = locked and DIM or SOFT
			node.card.BackgroundColor3 = node.isEndless and Color3.fromRGB(40, 30, 62) or Color3.fromRGB(35, 26, 18)

			if node.isEndless then
				node.reward.Text = locked and "🔒 Clear Night 8 to open the doors for good." or "No reward, just bragging rights. Depth is tracked on the leaderboards."
				node.reward.TextColor3 = locked and DIM or PURPLE
			else
				local entry = JourneyMap.Nights[index]
				local label = JourneyMap.rewardLabel(entry.reward, lookups)
				node.reward.Text = (isCleared and "✓ Earned: " or "🎁 Reward: ") .. label
				node.reward.TextColor3 = isCleared and GREEN or (locked and DIM or GOLD)
			end

			node.tag.Visible = isCurrent
			node.tag.Text = "📍 Here"
			node.tag.TextColor3 = accent
		end

		local fillTo = nodes[math.max(1, reachedIndex)].centerX - PAD
		if reachedIndex == 0 then
			fillTo = 0
		end
		fillLine.Size = UDim2.fromOffset(math.max(0, fillTo), 6)
		fillLine.BackgroundColor3 = view.inEndless and PURPLE or GOLD

		frame.BackgroundColor3 = view.inEndless and MAP_BG_ENDLESS or MAP_BG
	end

	local function applyHeader(isMapTab)
		if not isMapTab then
			return
		end
		local view = currentView()
		if view.inEndless then
			deps.titleLabel.Text = "♾ " .. JourneyMap.Endless.name .. " ♾"
			deps.titleLabel.TextColor3 = PURPLE
			deps.subtitleLabel.Text = string.format("Night %d. %s", math.floor(view.night), JourneyMap.Endless.description)
			deps.subtitleLabel.TextColor3 = Color3.fromRGB(205, 190, 240)
		else
			deps.titleLabel.Text = "The Tavern Map"
			deps.titleLabel.TextColor3 = CREAM
			deps.subtitleLabel.Text = "Eight nights, eight rooms. Clear each one for the first time to earn a reward."
			deps.subtitleLabel.TextColor3 = Color3.fromRGB(220, 205, 185)
		end
	end

	return {
		frame = frame,
		refresh = function()
			refresh()
		end,
		setShown = function(shown)
			frame.Visible = shown
			if shown then
				refresh()
				local view = currentView()
				local idx = math.min(math.max(view.night, 1), ENDLESS_INDEX)
				scroll.CanvasPosition = Vector2.new(math.max(0, nodes[idx].centerX - 300), 0)
			end
		end,
		applyHeader = applyHeader,
	}
end
