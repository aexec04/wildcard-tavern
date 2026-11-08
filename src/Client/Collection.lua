--[[
	Client/Collection.lua
	The Collection screen (parchment panel), opened from the "📔" corner
	button. Five tabs -- Patrons, Recipes, Boss Rounds, House Passes,
	Titles -- each showing its completion %, plus an overall % bar with the
	next milestone reward.

	All content and rules come from Shared/Engine/CollectionBook.lua, which
	reads the registries. Nothing here lists content by hand.

	Tiles: discovered entries show their icon, name and a glow in their
	rarity's color; undiscovered ones are a dark silhouette named "???".
	Tapping a tile opens a detail card with the effect text and flavor
	line. A Title's detail card has the Equip button (fires EquipTitle;
	clicking the equipped title's button un-equips it).

	Data comes from the server's state push:
	  state.collection = { discovered = { [tabId] = {id...} },
	                       claimedMilestoneIds = {id...}, unlockedCardBackIds = {id...} }
	  state.unlockedAchievementIds  -- the Titles tab's "discovered" list
	  state.equippedTitleId, state.profileStats
	  state.collectionMilestoneNotice -- one-shot milestone ids, shown as a toast

	This module listens to StateUpdatedRemote itself (with task.defer, so
	init.client.lua's render() has already updated latestState) instead of
	returning a refresh function -- init.client.lua has no spare locals.

	deps: screenGui, polishPanel, polishButton, roundCorner, addSoftShadow,
	playClickSfx, collectionButton, Achievements, EquipTitleRemote,
	getLatestState, popIn, popOut, addButtonHoverScale, StateUpdatedRemote.

	A "Card Sets" button in the header opens CosmeticSetsPanel.lua (equip
	and buy cosmetic sets).

	Returns: {}
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

return function(deps)
	local screenGui = deps.screenGui
	local polishPanel = deps.polishPanel
	local polishButton = deps.polishButton
	local roundCorner = deps.roundCorner
	local addSoftShadow = deps.addSoftShadow
	local playClickSfx = deps.playClickSfx
	local Achievements = deps.Achievements
	local EquipTitleRemote = deps.EquipTitleRemote
	local getLatestState = deps.getLatestState
	local popIn = deps.popIn
	local popOut = deps.popOut
	local addButtonHoverScale = deps.addButtonHoverScale
	local OverlayManager = require(script.Parent.OverlayManager)
	local PatronPlaqueModule = require(script.Parent.PatronPlaque)
	local Engine = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine")
	local CollectionBook = require(Engine:WaitForChild("CollectionBook"))
	local ContentArt = require(Engine:WaitForChild("ContentArt"))

	local CREAM = Color3.fromRGB(250, 240, 220)
	local SOFT_CREAM = Color3.fromRGB(215, 200, 178)
	local GOLD = Color3.fromRGB(255, 214, 130)
	local DIM = Color3.fromRGB(140, 130, 120)
	local BUTTON_BROWN = Color3.fromRGB(70, 55, 40)
	local ACTIVE_BROWN = Color3.fromRGB(150, 115, 50)
	local ITALIC = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Regular, Enum.FontStyle.Italic)
	-- Boss Rounds have no icon of their own.
	local FALLBACK_ICONS = { bosses = "⚡" }

	local function rgb(triple)
		return Color3.fromRGB(triple[1], triple[2], triple[3])
	end

	local function label(parent, props)
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Font = Enum.Font.Gotham
		l.TextColor3 = CREAM
		l.TextStrokeTransparency = 1
		l.ZIndex = 21
		for k, v in pairs(props) do
			l[k] = v
		end
		l.Parent = parent
		return l
	end

	local function button(parent, props)
		local b = Instance.new("TextButton")
		b.Font = Enum.Font.GothamBold
		b.TextColor3 = CREAM
		b.BackgroundColor3 = BUTTON_BROWN
		b.AutoButtonColor = true
		b.ZIndex = 21
		for k, v in pairs(props) do
			b[k] = v
		end
		b.Parent = parent
		return b
	end

	-- ===== Panel =====
	local backdrop = Instance.new("Frame")
	backdrop.Name = "CollectionBackdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	backdrop.BackgroundTransparency = 0.4
	backdrop.Visible = false
	backdrop.ZIndex = 20
	backdrop.Parent = screenGui

	local PANEL_SIZE = UDim2.fromScale(0.66, 0.78)
	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Size = PANEL_SIZE
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.BackgroundColor3 = Color3.fromRGB(40, 30, 22)
	panel.ZIndex = 21
	panel.Parent = backdrop
	polishPanel(panel, 16, "parchment")
	addSoftShadow(panel, 18)

	label(panel, {
		Size = UDim2.new(1, 0, 0, 28), Position = UDim2.fromOffset(0, 6),
		Font = Enum.Font.GothamBold, TextSize = 22, Text = "Collection",
	})

	require(script.Parent.ExpandToggle)(panel, {
		collapsedSize = PANEL_SIZE,
		polishButton = polishButton,
		addButtonHoverScale = addButtonHoverScale,
		playClickSfx = playClickSfx,
	})

	-- Card Sets (cosmetic card back + backdrop) live in their own panel.
	local setsButton = button(panel, {
		Size = UDim2.fromOffset(96, 24), Position = UDim2.fromOffset(15, 6),
		TextSize = 12, Text = "Card Sets",
	})
	polishButton(setsButton, 8)
	require(script.Parent.CosmeticSetsPanel)({
		screenGui = screenGui,
		polishPanel = polishPanel,
		polishButton = polishButton,
		roundCorner = roundCorner,
		addSoftShadow = addSoftShadow,
		playClickSfx = playClickSfx,
		openButton = setsButton,
		getLatestState = getLatestState,
		popIn = popIn,
		popOut = popOut,
		addButtonHoverScale = addButtonHoverScale,
		StateUpdatedRemote = deps.StateUpdatedRemote,
	})

	local statsLabel = label(panel, {
		Size = UDim2.new(1, -30, 0, 16), Position = UDim2.fromOffset(15, 34),
		TextSize = 12, TextColor3 = SOFT_CREAM, Text = "",
	})

	-- Overall completion bar + next milestone.
	local overallBar = Instance.new("Frame")
	overallBar.Size = UDim2.new(1, -30, 0, 22)
	overallBar.Position = UDim2.fromOffset(15, 54)
	overallBar.BackgroundColor3 = Color3.fromRGB(35, 26, 18)
	overallBar.ZIndex = 21
	overallBar.Parent = panel
	roundCorner(overallBar, 6)

	local overallFill = Instance.new("Frame")
	overallFill.Size = UDim2.fromScale(0, 1)
	overallFill.BackgroundColor3 = Color3.fromRGB(190, 145, 60)
	overallFill.ZIndex = 22
	overallFill.Parent = overallBar
	roundCorner(overallFill, 6)

	local overallText = label(overallBar, {
		Size = UDim2.new(1, -16, 1, 0), Position = UDim2.fromOffset(8, 0),
		Font = Enum.Font.GothamBold, TextSize = 13, ZIndex = 23,
		TextXAlignment = Enum.TextXAlignment.Left, Text = "",
	})

	-- Tabs.
	local tabRow = Instance.new("Frame")
	tabRow.Size = UDim2.new(1, -30, 0, 38)
	tabRow.Position = UDim2.fromOffset(15, 82)
	tabRow.BackgroundTransparency = 1
	tabRow.ZIndex = 21
	tabRow.Parent = panel

	local tabLayout = Instance.new("UIListLayout")
	tabLayout.FillDirection = Enum.FillDirection.Horizontal
	tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
	tabLayout.Padding = UDim.new(0, 6)
	tabLayout.Parent = tabRow

	local scroll = Instance.new("ScrollingFrame")
	scroll.Size = UDim2.new(1, -30, 1, -186)
	scroll.Position = UDim2.fromOffset(15, 128)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 8
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.ZIndex = 21
	scroll.Parent = panel

	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(92, 108)
	grid.CellPadding = UDim2.fromOffset(10, 10)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.HorizontalAlignment = Enum.HorizontalAlignment.Center
	grid.Parent = scroll

	-- Grid cells need a little inset so the rarity stroke isn't clipped.
	local gridPadding = Instance.new("UIPadding")
	gridPadding.PaddingTop = UDim.new(0, 4)
	gridPadding.PaddingBottom = UDim.new(0, 4)
	gridPadding.Parent = scroll

	local closeButton = button(panel, {
		Size = UDim2.fromOffset(140, 40), Position = UDim2.new(0.5, -70, 1, -50),
		TextSize = 16, Text = "Close", BackgroundColor3 = Color3.fromRGB(90, 60, 30),
	})
	polishButton(closeButton, 12)
	addButtonHoverScale(closeButton)
	closeButton.MouseButton1Click:Connect(function()
		playClickSfx()
		popOut(backdrop, panel)
	end)

	-- ===== Detail card =====
	-- `detailShade` covers the panel; hiding it hides the card too.
	local detailShade = Instance.new("TextButton")
	detailShade.Text = ""
	detailShade.AutoButtonColor = false
	detailShade.Size = UDim2.fromScale(1, 1)
	detailShade.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	detailShade.BackgroundTransparency = 0.35
	detailShade.Visible = false
	detailShade.ZIndex = 30
	detailShade.Parent = panel
	roundCorner(detailShade, 16)

	local card = Instance.new("TextButton") -- a button so clicks on it don't close it
	card.Text = ""
	card.AutoButtonColor = false
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.5)
	card.Size = UDim2.fromOffset(340, 330)
	card.BackgroundColor3 = Color3.fromRGB(40, 30, 22)
	card.ZIndex = 31
	card.Parent = detailShade
	polishPanel(card, 14, "parchment")

	-- Reuse polishPanel's gold ring as the rarity border (one UIStroke only).
	local cardStroke = card:FindFirstChildOfClass("UIStroke")
	cardStroke.Thickness = 3

	local cardIcon = label(card, {
		Size = UDim2.new(1, 0, 0, 64), Position = UDim2.fromOffset(0, 16),
		TextSize = 52, ZIndex = 32, Text = "",
	})
	local cardName = label(card, {
		Size = UDim2.new(1, -30, 0, 26), Position = UDim2.fromOffset(15, 84),
		Font = Enum.Font.GothamBold, TextSize = 20, ZIndex = 32, TextWrapped = true, Text = "",
	})
	local cardKind = label(card, {
		Size = UDim2.new(1, -30, 0, 16), Position = UDim2.fromOffset(15, 112),
		Font = Enum.Font.GothamBold, TextSize = 12, ZIndex = 32, Text = "",
	})
	local cardEffect = label(card, {
		Size = UDim2.new(1, -40, 0, 70), Position = UDim2.fromOffset(20, 138),
		TextSize = 15, ZIndex = 32, TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top, Text = "",
	})
	local cardFlavor = label(card, {
		Size = UDim2.new(1, -40, 0, 44), Position = UDim2.fromOffset(20, 212),
		TextSize = 13, ZIndex = 32, TextWrapped = true, TextColor3 = SOFT_CREAM,
		FontFace = ITALIC, TextYAlignment = Enum.TextYAlignment.Top, Text = "",
	})
	local cardEquip = button(card, {
		Size = UDim2.fromOffset(130, 34), Position = UDim2.new(0.5, -140, 1, -48),
		TextSize = 14, ZIndex = 32, Text = "Equip", Visible = false,
	})
	polishButton(cardEquip, 8)
	local cardClose = button(card, {
		Size = UDim2.fromOffset(130, 34), Position = UDim2.new(0.5, -65, 1, -48),
		TextSize = 14, ZIndex = 32, Text = "Back",
	})
	polishButton(cardClose, 8)

	-- ===== Milestone toast =====
	local toast = Instance.new("Frame")
	toast.AnchorPoint = Vector2.new(0.5, 0)
	toast.Position = UDim2.new(0.5, 0, 0, 70)
	toast.Size = UDim2.fromOffset(420, 64)
	toast.BackgroundColor3 = Color3.fromRGB(40, 30, 22)
	toast.Visible = false
	toast.ZIndex = 60
	toast.Parent = screenGui
	polishPanel(toast, 12, "parchment")
	local toastText = label(toast, {
		Size = UDim2.new(1, -24, 1, -8), Position = UDim2.fromOffset(12, 4),
		Font = Enum.Font.GothamBold, TextSize = 14, TextWrapped = true, ZIndex = 61,
		TextColor3 = GOLD, Text = "",
	})

	-- ===== State =====
	local activeTabId = CollectionBook.Tabs[1].id
	local tabButtons = {}
	local openItem = nil -- the item shown on the detail card, if any

	local function currentView()
		local state = getLatestState()
		local collection = state and state.collection or {}
		local lists = {}
		for tabId, ids in pairs(collection.discovered or {}) do
			lists[tabId] = ids
		end
		lists.titles = state and state.unlockedAchievementIds or {}
		local claimed = {}
		for _, id in ipairs(collection.claimedMilestoneIds or {}) do
			claimed[id] = true
		end
		local sets = CollectionBook.setsFromLists(lists)
		return {
			state = state,
			sets = sets,
			completion = CollectionBook.completion(sets),
			claimed = claimed,
			equippedTitleId = state and state.equippedTitleId,
		}
	end

	local function iconFor(item)
		return item.def.icon or FALLBACK_ICONS[item.tab] or "❔"
	end

	local function milestoneFor(titleId)
		for _, milestone in ipairs(CollectionBook.Milestones) do
			for _, reward in ipairs(milestone.rewards) do
				if reward.kind == "title" and reward.id == titleId then
					return milestone
				end
			end
		end
		return nil
	end

	local function undiscoveredHint(item)
		if item.tab == "titles" then
			local milestone = item.def.milestoneReward and milestoneFor(item.id)
			if milestone then
				return "Reach " .. milestone.percent .. "% Collection completion to earn this title."
			end
			return "Not unlocked yet. Keep playing to earn this title."
		elseif item.tab == "bosses" then
			return "Not discovered yet. Face this boss on a Boss Round to add it."
		end
		return "Not discovered yet. Spot it in the shop or a pack to add it."
	end

	local function showDetail(item, view)
		openItem = item
		local found = CollectionBook.isDiscovered(view.sets, item)
		local rarity = CollectionBook.Rarities[CollectionBook.rarityOf(item)]
		local def = item.def

		cardIcon.Text = iconFor(item)
		cardIcon.Visible = true
		cardIcon.TextTransparency = found and 0 or 0.55
		cardIcon.TextStrokeTransparency = 1
		cardStroke.Color = found and rgb(rarity.color) or Color3.fromRGB(60, 55, 50)
		cardKind.TextColor3 = found and rgb(rarity.color) or DIM

		-- Detail card art: overlay a portrait for any tab that has art.
		local prevArt = card:FindFirstChild("ContentDetailArt")
		if prevArt then prevArt:Destroy() end
		do
			local artId = ContentArt.getImageId(item.tab, item.id)
			local detailArt = artId and PatronPlaqueModule.applyById(card, artId, {
				emojiLabel = cardIcon,
				dim = not found,
				zIndex = 33,
				cornerRadius = 10,
				size = UDim2.fromOffset(60, 60),
				position = UDim2.new(0.5, -30, 0, 16),
			})
			if detailArt then
				detailArt.Name = "ContentDetailArt"
			end
		end
		local prevLock = card:FindFirstChild("ContentLockBadge")
		if prevLock then prevLock:Destroy() end
		if not found then
			local lockBadge = label(card, {
				Size = UDim2.fromOffset(22, 22), Position = UDim2.new(0.5, 14, 0, 58),
				TextSize = 16, ZIndex = 36, Text = "🔒", BackgroundTransparency = 1,
			})
			lockBadge.Name = "ContentLockBadge"
		end

		if found then
			cardName.Text = item.tab == "titles" and ('"' .. def.title .. '"') or def.name
			cardKind.Text = rarity.name .. " " .. CollectionBook.kindLabel(item)
			local effect = def.description
			if item.tab == "titles" then
				local milestone = def.milestoneReward and milestoneFor(item.id)
				effect = milestone and ("Reward for reaching " .. milestone.percent .. "% Collection completion.")
					or (def.name .. ": " .. def.description)
			end
			cardEffect.Text = effect
			cardFlavor.Text = def.flavorText and ('"' .. def.flavorText .. '"') or ""
		else
			cardName.Text = "???"
			cardKind.Text = CollectionBook.kindLabel(item)
			cardEffect.Text = undiscoveredHint(item)
			cardFlavor.Text = ""
		end

		local canEquip = found and item.tab == "titles"
		cardEquip.Visible = canEquip
		cardClose.Position = canEquip and UDim2.new(0.5, 10, 1, -48) or UDim2.new(0.5, -65, 1, -48)
		if canEquip then
			local equipped = view.equippedTitleId == item.id
			cardEquip.Text = equipped and "Unequip" or "Equip"
			cardEquip.BackgroundColor3 = equipped and ACTIVE_BROWN or BUTTON_BROWN
		end
		detailShade.Visible = true
	end

	local function hideDetail()
		openItem = nil
		detailShade.Visible = false
	end

	cardClose.MouseButton1Click:Connect(function()
		playClickSfx()
		hideDetail()
	end)
	detailShade.MouseButton1Click:Connect(hideDetail)
	cardEquip.MouseButton1Click:Connect(function()
		playClickSfx()
		if openItem and openItem.tab == "titles" and EquipTitleRemote then
			local state = getLatestState()
			local equipped = state and state.equippedTitleId == openItem.id
			EquipTitleRemote:FireServer(not equipped and openItem.id or nil)
		end
	end)

	local function makeTile(item, order, view)
		local found = CollectionBook.isDiscovered(view.sets, item)
		local rarity = CollectionBook.Rarities[CollectionBook.rarityOf(item)]

		local tile = Instance.new("TextButton")
		tile.Text = ""
		tile.AutoButtonColor = true
		tile.LayoutOrder = order
		tile.BackgroundColor3 = found and Color3.fromRGB(58, 44, 30) or Color3.fromRGB(22, 18, 15)
		tile.ZIndex = 21
		tile.Parent = scroll
		roundCorner(tile, 8)

		-- Rarity glow: a colored stroke plus a soft wash behind the icon.
		local stroke = Instance.new("UIStroke")
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Thickness = found and 2 or 1
		stroke.Color = found and rgb(rarity.color) or Color3.fromRGB(50, 45, 40)
		stroke.Parent = tile

		local iconWell = Instance.new("Frame")
		iconWell.Size = UDim2.fromOffset(60, 60)
		iconWell.Position = UDim2.new(0.5, -30, 0, 8)
		iconWell.BackgroundColor3 = found and rgb(rarity.color) or Color3.fromRGB(35, 28, 20)
		iconWell.BackgroundTransparency = found and 0.72 or 0.35
		iconWell.ZIndex = 22
		iconWell.Parent = tile
		roundCorner(iconWell, 30)

		local icon = label(iconWell, {
			Size = UDim2.fromScale(1, 1), TextSize = 34, ZIndex = 23, Text = iconFor(item),
		})
		if not found then
			-- TextTransparency dims emojis even though TextColor3 doesn't.
			icon.TextTransparency = 0.55
			icon.TextStrokeTransparency = 1
		end
		do
			local artId = ContentArt.getImageId(item.tab, item.id)
			if artId then
				PatronPlaqueModule.applyById(iconWell, artId, {
					emojiLabel = icon,
					dim = not found,
					zIndex = 24,
					cornerRadius = 30,
				})
			end
		end
		if not found then
			label(iconWell, {
				Size = UDim2.fromOffset(18, 18), Position = UDim2.new(1, -16, 1, -16),
				TextSize = 13, ZIndex = 26, Text = "🔒", BackgroundTransparency = 1,
			})
		end

		label(tile, {
			Size = UDim2.new(1, -8, 0, 32), Position = UDim2.new(0, 4, 0, 70),
			Font = Enum.Font.GothamBold, TextSize = 11, TextWrapped = true, ZIndex = 22,
			TextColor3 = found and CREAM or DIM,
			Text = found and (item.tab == "titles" and item.def.title or item.def.name) or "???",
		})

		if found and item.tab == "titles" and view.equippedTitleId == item.id then
			label(tile, {
				Size = UDim2.new(1, 0, 0, 14), Position = UDim2.fromOffset(0, 2),
				Font = Enum.Font.GothamBold, TextSize = 10, ZIndex = 25, TextColor3 = GOLD,
				Text = "EQUIPPED",
			})
		end

		tile.MouseButton1Click:Connect(function()
			playClickSfx()
			showDetail(item, view)
		end)
	end

	local function refresh()
		local view = currentView()
		local completion = view.completion

		-- Header stats.
		local stats = view.state and view.state.profileStats
		if stats then
			local equipped = view.equippedTitleId and Achievements.getById(view.equippedTitleId)
			statsLabel.Text = string.format(
				"Runs played: %d  |  Runs won: %d  |  Best Night: %d  |  Title: %s",
				math.floor(stats.runsStarted), math.floor(stats.runsWon), math.floor(stats.bestNightReached),
				equipped and ('"' .. equipped.title .. '"') or "none"
			)
		else
			statsLabel.Text = ""
		end

		-- Overall bar.
		overallFill.Size = UDim2.fromScale(completion.total > 0 and completion.found / completion.total or 0, 1)
		local nextMilestone = CollectionBook.nextMilestone(view.claimed)
		local nextText
		if nextMilestone then
			local rewards = {}
			for _, reward in ipairs(nextMilestone.rewards) do
				table.insert(rewards, CollectionBook.rewardLabel(reward))
			end
			nextText = "Next at " .. nextMilestone.percent .. "%: " .. table.concat(rewards, " + ")
		else
			nextText = "Every milestone claimed!"
		end
		overallText.Text = string.format("Overall %d%%  (%d / %d)   --   %s",
			math.floor(completion.percent), math.floor(completion.found), math.floor(completion.total), nextText)

		-- Tab headers.
		for _, tab in ipairs(CollectionBook.Tabs) do
			local tabButton = tabButtons[tab.id]
			local tabCompletion = completion.tabs[tab.id]
			tabButton.Text = string.format("%s\n%d%%", tab.name, math.floor(tabCompletion.percent))
			tabButton.BackgroundColor3 = tab.id == activeTabId and ACTIVE_BROWN or BUTTON_BROWN
		end

		-- Grid.
		for _, child in ipairs(scroll:GetChildren()) do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		for i, item in ipairs(CollectionBook.itemsFor(activeTabId)) do
			makeTile(item, i, view)
		end

		-- Keep an open detail card current (e.g. after an Equip click).
		if openItem then
			showDetail(openItem, view)
		end
	end

	for i, tab in ipairs(CollectionBook.Tabs) do
		local tabButton = button(tabRow, {
			Size = UDim2.new(1 / #CollectionBook.Tabs, -5, 1, 0),
			TextSize = 12, LayoutOrder = i, Text = tab.name,
		})
		polishButton(tabButton, 8)
		tabButtons[tab.id] = tabButton
		tabButton.MouseButton1Click:Connect(function()
			playClickSfx()
			if activeTabId ~= tab.id then
				activeTabId = tab.id
				hideDetail()
				scroll.CanvasPosition = Vector2.new(0, 0)
				refresh()
			end
		end)
	end

	local function showMilestoneToast(milestoneIds)
		local lines = {}
		for _, id in ipairs(milestoneIds) do
			for _, milestone in ipairs(CollectionBook.Milestones) do
				if milestone.id == id then
					local rewards = {}
					for _, reward in ipairs(milestone.rewards) do
						table.insert(rewards, CollectionBook.rewardLabel(reward))
					end
					table.insert(lines, "Collection " .. milestone.percent .. "%! " .. table.concat(rewards, " + "))
				end
			end
		end
		if #lines == 0 then
			return
		end
		toastText.Text = table.concat(lines, "\n")
		toast.Size = UDim2.fromOffset(420, 40 + 20 * #lines)
		toast.Visible = true
		local shownText = toastText.Text
		task.delay(5, function()
			if toastText.Text == shownText then
				toast.Visible = false
			end
		end)
	end

	OverlayManager.register("collection", function()
		hideDetail()
		popOut(backdrop, panel)
	end)

	deps.collectionButton.MouseButton1Click:Connect(function()
		playClickSfx()
		OverlayManager.closeAllExcept("collection")
		hideDetail()
		refresh()
		popIn(backdrop, panel)
	end)

	if deps.StateUpdatedRemote then
		deps.StateUpdatedRemote.OnClientEvent:Connect(function()
			task.defer(function()
				local state = getLatestState()
				if state and state.collectionMilestoneNotice then
					showMilestoneToast(state.collectionMilestoneNotice)
				end
				if backdrop.Visible then
					refresh()
				end
			end)
		end)
	end

	return {}
end
