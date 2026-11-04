--[[
	Client/JourneyMapView.lua
	The "Tavern Map" tab of the Journey screen: the 8 named Night locations,
	the Endless doors and the Endless milestone nodes on a map. Node positions
	are normalized (0-1) coordinates from Shared/Engine/JourneyMap.lua, drawn on
	a canvas that keeps the map's aspect ratio (scrolls sideways when narrow).

	Background: JourneyMap.Config.journeyMapImage. An id of "rbxassetid://0",
	or one that fails to load, falls back to the UI-built parchment look.

	Node states: cleared (gold ring + check), current (soft pulse), locked
	(dimmed, reward preview under the name), boss tier badge (distinct icon per
	tier). Tapping a node opens a detail card (reward, how it unlocks, Equip).

	Unlock moment: when the map is shown and a node has been cleared since the
	player last looked, the path draws toward the next node, that node lights
	up and the reward pops with a short message. Animation speed and "reduce
	screen shake" settings are respected (no bounce when shake is reduced).

	State used: state.clearedNightIds (Nights 1-8 and Endless milestone
	Nights), state.night, state.wonRun, state.profileStats.bestNightReached,
	state.cosmetics, state.equippedTitleId.

	deps: parent (the Journey panel), polishPanel, polishButton, roundCorner,
	getLatestState, titleLabel, subtitleLabel, StateUpdatedRemote, playClickSfx

	Returns:
		{
			frame = Frame,
			refresh = function(),
			setShown = function(bool),
			applyHeader = function(isMapTab) -- title/subtitle text and colors
		}
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local ContentProvider = game:GetService("ContentProvider")

return function(deps)
	local Engine = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine")
	local JourneyMap = require(Engine:WaitForChild("JourneyMap"))
	local CardBacks = require(Engine:WaitForChild("CardBacks"))
	local CosmeticSets = require(Engine:WaitForChild("CosmeticSets"))
	local Achievements = require(Engine:WaitForChild("Achievements"))
	local PlayerProfile = require(Engine:WaitForChild("PlayerProfile"))
	local ClientSettings = require(script.Parent.ClientSettings)
	local lookups = { cardBack = CardBacks, set = CosmeticSets, title = Achievements }

	local function rgb(t)
		return Color3.fromRGB(t[1], t[2], t[3])
	end

	local CREAM = Color3.fromRGB(250, 240, 220)
	local SOFT = Color3.fromRGB(215, 200, 178)
	local DIM = Color3.fromRGB(140, 130, 120)
	local GOLD = Color3.fromRGB(255, 214, 130)
	local GOLD_DARK = Color3.fromRGB(150, 115, 50)
	local INK = Color3.fromRGB(30, 22, 16)
	local PURPLE = rgb(JourneyMap.EndlessTheme.accent)
	local MAP_BG = Color3.fromRGB(58, 44, 30)
	local MAP_BG_ENDLESS = rgb(JourneyMap.EndlessTheme.background)

	local nodeData = JourneyMap.allNodes()
	local NODE_COUNT = #nodeData
	local ENDLESS_INDEX = JourneyMap.NightCap + 1

	local equipRemote = nil
	task.spawn(function()
		local remotes = ReplicatedStorage:WaitForChild("Remotes", 10)
		equipRemote = remotes and remotes:WaitForChild("EquipJourneyReward", 10)
	end)

	-- Speed multiplier from Settings > Animation Speed (1 = normal).
	local function pace()
		return PlayerProfile.animationPaceDivisor(ClientSettings.get("animSpeed"), false)
	end
	local function calm()
		return ClientSettings.get("reduceShake") == true
	end

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
	scroll.CanvasSize = UDim2.fromOffset(0, 0)
	scroll.ZIndex = 22
	scroll.Parent = frame

	local canvas = Instance.new("Frame")
	canvas.Name = "Canvas"
	canvas.BackgroundTransparency = 1
	canvas.Size = UDim2.fromOffset(600, 300)
	canvas.ZIndex = 22
	canvas.Parent = scroll

	-- Painted map image (hidden until it is a real id that loads).
	local mapImage = Instance.new("ImageLabel")
	mapImage.Name = "MapImage"
	mapImage.Size = UDim2.fromScale(1, 1)
	mapImage.BackgroundTransparency = 1
	mapImage.ScaleType = Enum.ScaleType.Stretch
	mapImage.Visible = false
	mapImage.ZIndex = 22
	mapImage.Parent = canvas
	do
		local id = JourneyMap.Config.journeyMapImage
		if type(id) == "string" and id ~= "" and id ~= "rbxassetid://0" then
			mapImage.Image = id
			task.spawn(function()
				local ok = pcall(function()
					ContentProvider:PreloadAsync({ mapImage }, function(_, status)
						if status == Enum.AssetFetchStatus.Success then
							mapImage.Visible = true
						end
					end)
				end)
				if not ok then
					mapImage.Visible = false
				end
			end)
		end
	end

	local function text(parent, props)
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Font = Enum.Font.Gotham
		l.TextColor3 = CREAM
		l.TextTransparency = 0
		l.TextStrokeTransparency = 1
		l.TextWrapped = true
		l.ZIndex = 26
		for k, v in pairs(props) do
			l[k] = v
		end
		l.Parent = parent
		return l
	end

	-- ===== Path segments (segment i joins node i to node i + 1) =====
	local segments = {}
	for i = 1, NODE_COUNT - 1 do
		local base = Instance.new("Frame")
		base.AnchorPoint = Vector2.new(0, 0.5)
		base.BackgroundColor3 = Color3.fromRGB(30, 22, 16)
		base.BackgroundTransparency = 0.15
		base.BorderSizePixel = 0
		base.ZIndex = 23
		base.Parent = canvas
		deps.roundCorner(base, 3)
		local fill = Instance.new("Frame")
		fill.AnchorPoint = Vector2.new(0, 0.5)
		fill.BackgroundColor3 = GOLD
		fill.BorderSizePixel = 0
		fill.ZIndex = 24
		fill.Parent = canvas
		deps.roundCorner(fill, 3)
		segments[i] = { base = base, fill = fill, length = 0, filled = false }
	end

	-- ===== Nodes =====
	local nodes = {}
	local nodeSize = 56

	local function buildNode(index)
		local data = nodeData[index]
		local info = data.info
		local isEndless = data.kind == "endless"

		local button = Instance.new("TextButton")
		button.Name = "Node" .. index
		button.AnchorPoint = Vector2.new(0.5, 0.5)
		button.Position = UDim2.fromScale(info.x, info.y)
		button.Size = UDim2.fromOffset(nodeSize, nodeSize)
		button.BackgroundColor3 = Color3.fromRGB(45, 34, 24)
		button.AutoButtonColor = false
		button.Text = ""
		button.ZIndex = 26
		button.Parent = canvas
		deps.roundCorner(button, 30)
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 3
		stroke.Parent = button
		local scale = Instance.new("UIScale")
		scale.Parent = button

		-- Soft pulse ring for the current node.
		local halo = Instance.new("Frame")
		halo.AnchorPoint = Vector2.new(0.5, 0.5)
		halo.Position = UDim2.fromScale(0.5, 0.5)
		halo.Size = UDim2.fromScale(1.35, 1.35)
		halo.BackgroundTransparency = 1
		halo.Visible = false
		halo.ZIndex = 25
		halo.Parent = button
		deps.roundCorner(halo, 40)
		local haloStroke = Instance.new("UIStroke")
		haloStroke.Thickness = 3
		haloStroke.Transparency = 0.2
		haloStroke.Parent = halo
		local haloScale = Instance.new("UIScale")
		haloScale.Parent = halo

		local icon = text(button, {
			Size = UDim2.fromScale(1, 1), TextSize = 26, Text = info.icon, TextWrapped = false,
		})
		local numberTag = text(button, {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.08, 0.1), Size = UDim2.fromOffset(20, 20),
			Font = Enum.Font.GothamBold, TextSize = 11, TextWrapped = false,
			Text = isEndless and "∞" or tostring(data.night), BackgroundTransparency = 0,
			BackgroundColor3 = INK, TextColor3 = CREAM, ZIndex = 28,
		})
		deps.roundCorner(numberTag, 10)

		local bossBadge
		if data.kind == "night" or data.kind == "milestone" then
			local tierInfo = JourneyMap.BossTiers[JourneyMap.bossTierFor(data.night)]
			bossBadge = text(button, {
				AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.92, 0.1), Size = UDim2.fromOffset(22, 22),
				TextSize = 13, TextWrapped = false, Text = tierInfo.icon, BackgroundTransparency = 0,
				BackgroundColor3 = Color3.fromRGB(110, 40, 40), ZIndex = 28,
			})
			deps.roundCorner(bossBadge, 11)
		end

		local check = text(button, {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.9, 0.92), Size = UDim2.fromOffset(22, 22),
			Font = Enum.Font.GothamBold, TextSize = 14, TextWrapped = false, Text = "✓", BackgroundTransparency = 0,
			BackgroundColor3 = GOLD, TextColor3 = INK, Visible = false, ZIndex = 28,
		})
		deps.roundCorner(check, 11)

		-- Labels live on the canvas (not the button) so the button's UIScale
		-- pop does not stretch the text.
		local name = text(canvas, {
			AnchorPoint = Vector2.new(0.5, 0), Size = UDim2.fromOffset(120, 28),
			Font = Enum.Font.GothamBold, TextSize = 11, Text = info.name, ZIndex = 27,
			TextStrokeColor3 = INK, TextStrokeTransparency = 0.5,
		})
		local preview = text(canvas, {
			AnchorPoint = Vector2.new(0.5, 0), Size = UDim2.fromOffset(120, 14),
			TextSize = 10, Text = "", TextWrapped = false, ZIndex = 27,
			TextStrokeColor3 = INK, TextStrokeTransparency = 0.5,
		})

		local pulse = TweenService:Create(haloStroke, TweenInfo.new(1.1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Transparency = 0.85 })
		local pulseScale = TweenService:Create(haloScale, TweenInfo.new(1.1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Scale = 1.12 })

		nodes[index] = {
			button = button, stroke = stroke, scale = scale, halo = halo, haloStroke = haloStroke, haloScale = haloScale,
			icon = icon, numberTag = numberTag, bossBadge = bossBadge, check = check, name = name, preview = preview,
			pulse = pulse, pulseScale = pulseScale, pulsing = false, data = data, isEndless = isEndless,
		}
	end

	for index = 1, NODE_COUNT do
		buildNode(index)
	end

	-- ===== Layout (positions come from data; only pixels are computed here) =====
	local canvasW, canvasH = 600, 300

	local function layout()
		local size = scroll.AbsoluteSize
		if size.X < 10 or size.Y < 10 then
			return
		end
		canvasH = math.max(220, size.Y - 10)
		canvasW = math.max(size.X, canvasH * JourneyMap.Config.mapAspect)
		canvas.Size = UDim2.fromOffset(canvasW, canvasH)
		scroll.CanvasSize = UDim2.fromOffset(canvasW, 0)
		nodeSize = math.floor(math.clamp(canvasH * 0.18, 44, 72))
		for index, node in ipairs(nodes) do
			node.button.Size = UDim2.fromOffset(nodeSize, nodeSize)
			node.icon.TextSize = math.floor(nodeSize * 0.46)
			local info = node.data.info
			node.name.Position = UDim2.new(info.x, 0, info.y, nodeSize / 2 + 4)
			node.preview.Position = UDim2.new(info.x, 0, info.y, nodeSize / 2 + 32)
			node.name.Size = UDim2.fromOffset(math.max(100, nodeSize * 2), 28)
			node.preview.Size = UDim2.fromOffset(math.max(100, nodeSize * 2), 14)
			local nextData = nodeData[index + 1]
			if nextData then
				local ax, ay = info.x * canvasW, info.y * canvasH
				local bx, by = nextData.info.x * canvasW, nextData.info.y * canvasH
				local seg = segments[index]
				seg.length = math.sqrt((bx - ax) ^ 2 + (by - ay) ^ 2)
				local rotation = math.deg(math.atan2(by - ay, bx - ax))
				seg.base.Position = UDim2.fromOffset(ax, ay)
				seg.base.Size = UDim2.fromOffset(seg.length, 6)
				seg.base.Rotation = rotation
				seg.fill.Position = UDim2.fromOffset(ax, ay)
				seg.fill.Rotation = rotation
				seg.fill.Size = UDim2.fromOffset(seg.filled and seg.length or 0, 6)
			end
		end
	end
	scroll:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)

	-- ===== View of the current state =====
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
		return {
			state = state, cleared = cleared, reached = reached, night = night,
			inEndless = night > JourneyMap.NightCap,
			endlessOpen = cleared[JourneyMap.NightCap] == true or reached > JourneyMap.NightCap or won,
		}
	end

	-- Which node is "here" (the current Night, or the nearest milestone behind it).
	local function currentIndexFor(view)
		if not view.state then
			return nil
		end
		local night = math.max(view.night, 1)
		if night <= JourneyMap.NightCap then
			return night
		end
		local idx = ENDLESS_INDEX
		for i = ENDLESS_INDEX + 1, NODE_COUNT do
			if nodeData[i].night <= night then
				idx = i
			end
		end
		return idx
	end

	local function isNodeLocked(view, cleared, index)
		local data = nodeData[index]
		if data.kind == "endless" then
			return not view.endlessOpen
		end
		return not cleared[data.night] and data.night > view.reached
	end

	local function setPulse(node, on)
		if node.pulsing == on then
			return
		end
		node.pulsing = on
		node.halo.Visible = on
		if on then
			node.pulse:Play()
			if not calm() then
				node.pulseScale:Play()
			end
		else
			node.pulse:Cancel()
			node.pulseScale:Cancel()
		end
	end

	local function rewardOf(index)
		return nodeData[index].info.reward
	end

	local function previewText(index)
		local reward = rewardOf(index)
		if not reward then
			return ""
		end
		local def = lookups[reward.kind].getById(reward.id)
		local kind = JourneyMap.RewardKinds[reward.kind]
		return kind.icon .. " " .. (def and (def.title or def.name) or reward.id)
	end

	-- Draws every node and segment from `cleared`. `animating` leaves
	-- segment fills alone (the unlock moment tweens them itself).
	local function render(view, cleared, animating)
		local currentIndex = currentIndexFor(view)
		local accentHere = view.inEndless and PURPLE or GOLD
		for index, node in ipairs(nodes) do
			local data = node.data
			local isCleared = data.kind ~= "endless" and cleared[data.night] == true
			local locked = isNodeLocked(view, cleared, index)
			local isCurrent = currentIndex == index and not isCleared
			local isEndless = data.kind ~= "night"

			node.stroke.Color = isCleared and GOLD or (isCurrent and accentHere) or (locked and Color3.fromRGB(70, 58, 46)) or GOLD_DARK
			node.stroke.Thickness = isCleared and 4 or 3
			node.button.BackgroundColor3 = isCleared and Color3.fromRGB(70, 54, 28)
				or (isEndless and Color3.fromRGB(46, 36, 70) or Color3.fromRGB(45, 34, 24))
			node.icon.TextTransparency = locked and 0.55 or 0
			node.icon.TextStrokeTransparency = 1
			node.check.Visible = isCleared
			node.numberTag.TextColor3 = locked and DIM or CREAM
			if node.bossBadge then
				node.bossBadge.TextTransparency = locked and 0.4 or 0
				node.bossBadge.BackgroundTransparency = locked and 0.4 or 0
			end

			node.name.TextColor3 = locked and DIM or CREAM
			node.preview.Text = previewText(index)
			node.preview.TextColor3 = isCleared and GOLD or (locked and DIM or SOFT)
			node.haloStroke.Color = accentHere
			setPulse(node, isCurrent and frame.Visible)
		end

		local endlessEntered = view.reached > JourneyMap.NightCap
		for index, seg in ipairs(segments) do
			local data = nodeData[index]
			local filled
			if data.kind == "endless" then
				filled = endlessEntered
			else
				filled = cleared[data.night] == true
			end
			seg.filled = filled
			seg.fill.BackgroundColor3 = (data.kind ~= "night") and PURPLE or GOLD
			if not animating then
				seg.fill.Size = UDim2.fromOffset(filled and seg.length or 0, 6)
			end
		end
		frame.BackgroundColor3 = view.inEndless and MAP_BG_ENDLESS or MAP_BG
	end

	-- ===== Detail card =====
	local card = Instance.new("Frame")
	card.Name = "NodeDetail"
	card.AnchorPoint = Vector2.new(0.5, 1)
	card.Position = UDim2.new(0.5, 0, 1, -14)
	card.Size = UDim2.new(0, 400, 0, 176)
	card.BackgroundColor3 = Color3.fromRGB(35, 26, 18)
	card.Visible = false
	card.ZIndex = 40
	card.Parent = frame
	deps.polishPanel(card, 10, "wood")
	local cardLimit = Instance.new("UISizeConstraint")
	cardLimit.MaxSize = Vector2.new(400, 176)
	cardLimit.Parent = card

	local function cardText(props)
		props.ZIndex = 42
		return text(card, props)
	end
	local cardIcon = cardText({ Size = UDim2.fromOffset(40, 40), Position = UDim2.fromOffset(10, 8), TextSize = 30, TextWrapped = false })
	local cardName = cardText({ Size = UDim2.new(1, -150, 0, 22), Position = UDim2.fromOffset(54, 8), Font = Enum.Font.GothamBold,
		TextSize = 16, TextXAlignment = Enum.TextXAlignment.Left })
	local cardBoss = cardText({ Size = UDim2.new(1, -150, 0, 16), Position = UDim2.fromOffset(54, 30), TextSize = 11,
		TextColor3 = SOFT, TextXAlignment = Enum.TextXAlignment.Left })
	local cardDesc = cardText({ Size = UDim2.new(1, -20, 0, 34), Position = UDim2.fromOffset(10, 54), TextSize = 11,
		TextColor3 = SOFT, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top })
	local cardReward = cardText({ Size = UDim2.new(1, -110, 0, 18), Position = UDim2.fromOffset(10, 92), Font = Enum.Font.GothamBold,
		TextSize = 12, TextColor3 = GOLD, TextXAlignment = Enum.TextXAlignment.Left })
	local cardHow = cardText({ Size = UDim2.new(1, -110, 0, 30), Position = UDim2.fromOffset(10, 112), TextSize = 10,
		TextColor3 = SOFT, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top })

	-- Reward preview swatch (right side): card-back colors, or an icon tile.
	local swatch = Instance.new("Frame")
	swatch.AnchorPoint = Vector2.new(1, 0)
	swatch.Position = UDim2.new(1, -12, 0, 90)
	swatch.Size = UDim2.fromOffset(46, 64)
	swatch.ZIndex = 42
	swatch.Parent = card
	deps.roundCorner(swatch, 6)
	local swatchStroke = Instance.new("UIStroke")
	swatchStroke.Thickness = 2
	swatchStroke.Parent = swatch
	local swatchIcon = text(swatch, { Size = UDim2.fromScale(1, 1), TextSize = 24, TextWrapped = false, ZIndex = 43 })

	local equipButton = Instance.new("TextButton")
	equipButton.AnchorPoint = Vector2.new(1, 1)
	equipButton.Position = UDim2.new(1, -66, 1, -10)
	equipButton.Size = UDim2.fromOffset(96, 30)
	equipButton.Font = Enum.Font.GothamBold
	equipButton.TextSize = 13
	equipButton.TextColor3 = CREAM
	equipButton.BackgroundColor3 = Color3.fromRGB(90, 60, 30)
	equipButton.Text = "Equip"
	equipButton.ZIndex = 43
	equipButton.Parent = card
	deps.polishButton(equipButton, 8)

	local closeCard = Instance.new("TextButton")
	closeCard.AnchorPoint = Vector2.new(1, 0)
	closeCard.Position = UDim2.new(1, -8, 0, 8)
	closeCard.Size = UDim2.fromOffset(28, 28)
	closeCard.Font = Enum.Font.GothamBold
	closeCard.TextSize = 14
	closeCard.TextColor3 = CREAM
	closeCard.BackgroundColor3 = Color3.fromRGB(70, 55, 40)
	closeCard.Text = "✕"
	closeCard.ZIndex = 43
	closeCard.Parent = card
	deps.polishButton(closeCard, 8)

	local openIndex = nil

	local function equippedNow(view, reward)
		local cosmetics = view.state and view.state.cosmetics
		if reward.kind == "cardBack" then
			return cosmetics ~= nil and cosmetics.pickedCardBackId == reward.id
		elseif reward.kind == "set" then
			return cosmetics ~= nil and cosmetics.equippedSetId == reward.id
		end
		return view.state ~= nil and view.state.equippedTitleId == reward.id
	end

	local function fillCard()
		if not openIndex then
			return
		end
		local view = currentView()
		local data = nodeData[openIndex]
		local info = data.info
		local reward = info.reward
		local isEarned = data.kind ~= "endless" and view.cleared[data.night] == true
		local locked = isNodeLocked(view, view.cleared, openIndex)

		cardIcon.Text = info.icon
		cardName.Text = info.name
		cardDesc.Text = info.description
		if data.kind == "endless" then
			cardBoss.Text = "Boss ★★★ and beyond"
			cardBoss.TextColor3 = PURPLE
		else
			cardBoss.Text = JourneyMap.BossTiers[JourneyMap.bossTierFor(data.night)].icon .. " "
				.. JourneyMap.BossTiers[JourneyMap.bossTierFor(data.night)].label
			cardBoss.TextColor3 = SOFT
		end

		swatch.Visible = reward ~= nil
		equipButton.Visible = false
		if not reward then
			cardReward.Text = locked and "🔒 Clear Night 8 to open the doors for good." or "The doors are open. Milestones wait ahead."
			cardReward.TextColor3 = locked and DIM or PURPLE
			cardHow.Text = "Endless Nights keep going. Clear Endless Night 10, 15 and 20 for rewards."
			return
		end

		cardReward.Text = (isEarned and "✓ Earned: " or "🎁 Reward: ") .. JourneyMap.rewardLabel(reward, lookups)
		cardReward.TextColor3 = isEarned and GOLD or SOFT
		cardHow.Text = (isEarned and "Unlocked: " or "How to unlock: ") .. JourneyMap.unlockText(data)

		-- Preview
		local def = lookups[reward.kind].getById(reward.id)
		local back = reward.kind == "cardBack" and def or (reward.kind == "set" and def and CardBacks.getById(def.cardBackId)) or nil
		if back then
			swatch.BackgroundColor3 = rgb(back.colors.base)
			swatchStroke.Color = rgb(back.colors.trim)
			swatchIcon.Text = back.icon
		else
			swatch.BackgroundColor3 = Color3.fromRGB(60, 46, 32)
			swatchStroke.Color = GOLD
			swatchIcon.Text = def and def.icon or JourneyMap.RewardKinds[reward.kind].icon
		end
		swatchIcon.TextTransparency = isEarned and 0 or 0.5
		swatchIcon.TextStrokeTransparency = 1

		if isEarned then
			local equipped = equippedNow(view, reward)
			equipButton.Visible = true
			equipButton.Text = equipped and "Equipped ✓" or "Equip"
			equipButton.Active = not equipped
			equipButton.AutoButtonColor = not equipped
			equipButton.BackgroundColor3 = equipped and Color3.fromRGB(70, 90, 60) or Color3.fromRGB(90, 60, 30)
		end
	end

	local function openCard(index)
		openIndex = index
		card.Visible = true
		fillCard()
	end
	local function closeDetail()
		openIndex = nil
		card.Visible = false
	end

	closeCard.MouseButton1Click:Connect(function()
		deps.playClickSfx()
		closeDetail()
	end)
	equipButton.MouseButton1Click:Connect(function()
		if not openIndex or not equipButton.Active then
			return
		end
		local data = nodeData[openIndex]
		if equipRemote and data.night then
			deps.playClickSfx()
			equipRemote:FireServer(data.night)
		end
	end)
	for index, node in ipairs(nodes) do
		node.button.MouseButton1Click:Connect(function()
			deps.playClickSfx()
			if openIndex == index then
				closeDetail()
			else
				openCard(index)
			end
		end)
	end

	-- ===== Unlock moment =====
	local seen = nil -- nights already shown as cleared (baseline from the first state)
	local playing = 0 -- token; a newer play or hide cancels older ones
	local unlocking = false -- true while the unlock moment runs (refresh leaves the picture alone)

	local function copySet(set)
		local out = {}
		for k, v in pairs(set) do
			out[k] = v
		end
		return out
	end

	local toast = text(frame, {
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 10), Size = UDim2.fromOffset(360, 34),
		Font = Enum.Font.GothamBold, TextSize = 14, TextColor3 = INK, BackgroundTransparency = 1,
		BackgroundColor3 = GOLD, Visible = false, ZIndex = 45, TextWrapped = true,
	})
	deps.roundCorner(toast, 8)

	local function showToast(message, token, accent)
		toast.Text = message
		toast.BackgroundColor3 = accent
		toast.BackgroundTransparency = 0
		toast.TextTransparency = 0
		toast.TextStrokeTransparency = 1
		toast.Visible = true
		local rise = calm() and 0 or 14
		toast.Position = UDim2.new(0.5, 0, 0, 10 + rise)
		TweenService:Create(toast, TweenInfo.new(0.25 / pace(), Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Position = UDim2.new(0.5, 0, 0, 10) }):Play()
		task.delay(2.6 / pace(), function()
			if playing ~= token then
				return
			end
			local fade = TweenService:Create(toast, TweenInfo.new(0.35 / pace()),
				{ BackgroundTransparency = 1, TextTransparency = 1 })
			fade:Play()
			fade.Completed:Wait()
			if playing == token then
				toast.Visible = false
			end
		end)
	end

	local function popNode(node)
		if calm() then
			return
		end
		node.scale.Scale = 1
		local up = TweenService:Create(node.scale, TweenInfo.new(0.18 / pace(), Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1.3 })
		up:Play()
		up.Completed:Wait()
		TweenService:Create(node.scale, TweenInfo.new(0.2 / pace()), { Scale = 1 }):Play()
	end

	-- Plays the unlock for each night in `pendingNights` (ascending), starting
	-- from the pre-clear picture.
	local function playUnlocks(view, pendingNights)
		playing = playing + 1
		local token = playing
		unlocking = true
		local shown = copySet(view.cleared)
		for _, n in ipairs(pendingNights) do
			shown[n] = nil
		end
		render(view, shown, false)

		task.spawn(function()
			for _, n in ipairs(pendingNights) do
				if playing ~= token then
					return
				end
				local index
				for i, data in ipairs(nodeData) do
					if data.night == n then
						index = i
					end
				end
				if not index then
					continue
				end
				task.wait(0.4 / pace())
				if playing ~= token then
					return
				end
				-- Bring the node into view.
				local target = math.clamp(nodes[index].data.info.x * canvasW - scroll.AbsoluteSize.X / 2, 0,
					math.max(0, canvasW - scroll.AbsoluteSize.X))
				TweenService:Create(scroll, TweenInfo.new(0.4 / pace()), { CanvasPosition = Vector2.new(target, 0) }):Play()
				task.wait(0.35 / pace())

				-- The node itself clears: gold ring and check.
				shown[n] = true
				render(view, shown, true)
				popNode(nodes[index])
				if playing ~= token then
					return
				end

				-- The path draws toward the next node, which then lights up.
				local seg = segments[index]
				if seg then
					seg.fill.Size = UDim2.fromOffset(0, 6)
					local draw = TweenService:Create(seg.fill, TweenInfo.new(0.7 / pace(), Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
						{ Size = UDim2.fromOffset(seg.length, 6) })
					draw:Play()
					draw.Completed:Wait()
					seg.filled = true
					if playing ~= token then
						return
					end
					local nextNode = nodes[index + 1]
					if nextNode then
						popNode(nextNode)
					end
				end

				local reward = rewardOf(index)
				if reward then
					showToast("🎁 " .. nodeData[index].info.name .. " cleared! " .. JourneyMap.rewardLabel(reward, lookups),
						token, nodeData[index].kind == "milestone" and PURPLE or GOLD)
					task.wait(1.2 / pace())
				end
			end
			if playing == token then
				unlocking = false
				render(view, view.cleared, false)
			end
		end)
	end

	-- Takes the first state seen as "what the player has already looked at".
	deps.StateUpdatedRemote.OnClientEvent:Connect(function()
		task.defer(function()
			if seen == nil then
				local view = currentView()
				if view.state then
					seen = copySet(view.cleared)
				end
			end
		end)
	end)

	local function refresh()
		if unlocking then
			return
		end
		local view = currentView()
		render(view, view.cleared, false)
		if openIndex then
			fillCard()
		end
		-- Anything cleared while the map is already open is not an "unlock moment".
		if frame.Visible and view.state then
			seen = copySet(view.cleared)
		end
	end

	local function applyHeader(isMapTab)
		if not isMapTab then
			return
		end
		local view = currentView()
		local done, total, percent = JourneyMap.completion(view.cleared)
		local nextNode = JourneyMap.nextReward(view.cleared)
		local hint
		if nextNode then
			local label = string.format("Night %d, %s: %s", nextNode.night, nextNode.info.name,
				JourneyMap.rewardLabel(nextNode.info.reward, lookups))
			hint = "Next reward: " .. label
		else
			hint = "Every reward earned. Well played, Keeper!"
		end
		local progress = string.format("Journey %d%% (%d/%d)", percent, done, total)
		if view.inEndless then
			deps.titleLabel.Text = "♾ " .. JourneyMap.Endless.name .. " ♾"
			deps.titleLabel.TextColor3 = PURPLE
			deps.subtitleLabel.Text = string.format("Night %d. %s. %s", math.floor(view.night), progress, hint)
			deps.subtitleLabel.TextColor3 = rgb(JourneyMap.EndlessTheme.subtitle)
		else
			deps.titleLabel.Text = "The Tavern Map"
			deps.titleLabel.TextColor3 = CREAM
			deps.subtitleLabel.Text = progress .. ". " .. hint
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
			if not shown then
				playing = playing + 1 -- cancel any unlock in progress
				unlocking = false
				toast.Visible = false
				closeDetail()
				for _, node in ipairs(nodes) do
					setPulse(node, false)
				end
				return
			end
			layout()
			local view = currentView()
			local pending = {}
			if seen and view.state then
				for _, data in ipairs(nodeData) do
					if data.night and view.cleared[data.night] and not seen[data.night] then
						table.insert(pending, data.night)
					end
				end
				table.sort(pending)
			end
			if view.state then
				seen = copySet(view.cleared)
			end
			playing = playing + 1
			unlocking = false
			if #pending > 0 then
				playUnlocks(view, pending)
			else
				render(view, view.cleared, false)
				local idx = currentIndexFor(view) or 1
				local target = math.clamp(nodes[idx].data.info.x * canvasW - scroll.AbsoluteSize.X / 2, 0,
					math.max(0, canvasW - scroll.AbsoluteSize.X))
				scroll.CanvasPosition = Vector2.new(target, 0)
			end
		end,
		applyHeader = applyHeader,
	}
end
