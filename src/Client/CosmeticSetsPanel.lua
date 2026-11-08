--[[
	Client/CosmeticSetsPanel.lua
	The "Card Sets & Backs" screen (parchment), opened from a button inside the
	Collection panel. A second section lists every card back (equip any
	unlocked one, or "Match my set"). Lists every Cosmetic Set (CosmeticSets.Definitions):
	icon, name, how it unlocks, and a button -- Equip, Equipped, Buy (Tips),
	or a locked label. All rules live in Shared/Engine/CosmeticSets.lua; the
	server decides (BuyCosmeticSet / EquipCosmeticSet remotes).

	Reads state.cosmetics = { equippedSetId, unlockedSetIds } and
	state.tips. Refreshes on every StateUpdated while open.

	deps: screenGui, polishPanel, polishButton, roundCorner, addSoftShadow,
	playClickSfx, openButton, getLatestState, popIn, popOut,
	addButtonHoverScale, StateUpdatedRemote
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

return function(deps)
	local OverlayManager = require(script.Parent.OverlayManager)
	local Engine = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine")
	local CosmeticSets = require(Engine:WaitForChild("CosmeticSets"))
	local CardBacks = require(Engine:WaitForChild("CardBacks"))
	local CardBackView = require(script.Parent.CardBackView)
	local ArtAssets = require(script.Parent.ArtAssets)
	local JourneyMap = require(Engine:WaitForChild("JourneyMap"))
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local BuyRemote = remotes:WaitForChild("BuyCosmeticSet")
	local EquipRemote = remotes:WaitForChild("EquipCosmeticSet")
	local EquipBackRemote = remotes:WaitForChild("EquipCardBack")

	local polishPanel, polishButton = deps.polishPanel, deps.polishButton
	local roundCorner, playClickSfx = deps.roundCorner, deps.playClickSfx
	local popIn, popOut = deps.popIn, deps.popOut

	local CREAM = Color3.fromRGB(250, 240, 220)
	local SOFT_CREAM = Color3.fromRGB(215, 200, 178)
	local GOLD = Color3.fromRGB(255, 214, 130)
	local BROWN = Color3.fromRGB(70, 55, 40)
	local DIM = Color3.fromRGB(140, 130, 120)

	local function label(parent, props)
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Font = Enum.Font.Gotham
		l.TextColor3 = CREAM
		l.TextStrokeTransparency = 1
		l.ZIndex = 41
		for k, v in pairs(props) do
			l[k] = v
		end
		l.Parent = parent
		return l
	end

	local backdrop = Instance.new("Frame")
	backdrop.Name = "CosmeticSetsBackdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	backdrop.BackgroundTransparency = 0.4
	backdrop.Visible = false
	backdrop.ZIndex = 40
	backdrop.Parent = deps.screenGui

	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Size = UDim2.fromScale(0.64, 0.84)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.BackgroundColor3 = Color3.fromRGB(40, 30, 22)
	panel.ZIndex = 41
	panel.Parent = backdrop
	polishPanel(panel, 16, "parchment")
	deps.addSoftShadow(panel, 18)

	label(panel, {
		Size = UDim2.new(1, 0, 0, 28), Position = UDim2.fromOffset(0, 6),
		Font = Enum.Font.GothamBold, TextSize = 22, Text = "Card Sets & Backs",
	})
	label(panel, {
		Size = UDim2.new(1, -30, 0, 20), Position = UDim2.fromOffset(15, 34),
		TextSize = 15, TextColor3 = SOFT_CREAM, TextTruncate = Enum.TextTruncate.AtEnd,
		Text = "Sets theme the table. Backs can be picked on their own. Looks only.",
	})

	local scroll = Instance.new("ScrollingFrame")
	scroll.Size = UDim2.new(1, -30, 1, -104)
	scroll.Position = UDim2.fromOffset(15, 62)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 6
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new()
	scroll.ZIndex = 41
	scroll.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 8)
	layout.Parent = scroll

	local closeButton = Instance.new("TextButton")
	closeButton.Size = UDim2.fromOffset(110, 30)
	closeButton.AnchorPoint = Vector2.new(0.5, 1)
	closeButton.Position = UDim2.new(0.5, 0, 1, -10)
	closeButton.Font = Enum.Font.GothamBold
	closeButton.TextSize = 15
	closeButton.TextColor3 = CREAM
	closeButton.BackgroundColor3 = BROWN
	closeButton.Text = "Close"
	closeButton.ZIndex = 42
	closeButton.Parent = panel
	polishButton(closeButton, 8)
	deps.addButtonHoverScale(closeButton)

	-- Short unlock hint for a locked back tile (kept under ~28 characters so it fits at 15px).
	local function backUnlockHint(back)
		for _, set in ipairs(CosmeticSets.Definitions) do
			if set.cardBackId == back.id then
				return "Comes with " .. set.name
			end
		end
		for _, entry in ipairs(JourneyMap.Nights) do
			if entry.reward.kind == "cardBack" and entry.reward.id == back.id then
				return "Clear Night " .. entry.night
			end
		end
		return "Collection milestone"
	end

	local function sectionHeader(order, text)
		local holder = Instance.new("Frame")
		holder.Size = UDim2.new(1, -8, 0, 24)
		holder.BackgroundTransparency = 1
		holder.LayoutOrder = order
		holder.ZIndex = 41
		holder.Parent = scroll
		label(holder, {
			Size = UDim2.fromScale(1, 1), Font = Enum.Font.GothamBold, TextSize = 15,
			TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = GOLD, Text = text,
		})
	end

	-- One tile in the Card Backs grid: tall painted thumbnail (90x135), name, action.
	-- back == nil is the "Match my set" tile (shows the set's back).
	local function backTile(grid, order, back, cosmetics, backsUnlocked)
		local tile = Instance.new("Frame")
		tile.Size = UDim2.fromOffset(132, 226)
		tile.BackgroundColor3 = Color3.fromRGB(35, 26, 18)
		tile.LayoutOrder = order
		tile.ZIndex = 41
		tile.Parent = grid
		roundCorner(tile, 8)

		local isOwned = back == nil or backsUnlocked[back.id] == true
		local isEquipped
		if back == nil then
			isEquipped = cosmetics.pickedCardBackId == nil
		else
			isEquipped = cosmetics.pickedCardBackId == back.id
		end

		local shown = back or CardBacks.getById(cosmetics.cardBackId)
		local thumb = CardBackView.thumb(tile, shown, {
			equipped = isEquipped, locked = not isOwned, zIndex = 42,
			isActive = function() return backdrop.Visible end,
		})
		thumb.AnchorPoint = Vector2.new(0.5, 0)
		thumb.Position = UDim2.new(0.5, 0, 0, 8)
		if not isOwned then
			label(thumb, {
				Size = UDim2.new(1, -8, 1, 0), Position = UDim2.fromOffset(4, 0), TextSize = 15, TextWrapped = true,
				Font = Enum.Font.GothamBold, TextColor3 = CREAM, TextStrokeTransparency = 0.3,
				Text = "🔒 " .. backUnlockHint(back), ZIndex = 47,
			})
		end

		label(tile, {
			Size = UDim2.new(1, -8, 0, 22), Position = UDim2.fromOffset(4, 148),
			Font = Enum.Font.GothamBold, TextSize = 15, TextColor3 = isOwned and GOLD or DIM,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Text = back == nil and "Match my set" or (isOwned and back.name or "???"),
		})

		local action = Instance.new("TextButton")
		action.Size = UDim2.fromOffset(112, 30)
		action.AnchorPoint = Vector2.new(0.5, 0)
		action.Position = UDim2.new(0.5, 0, 0, 180)
		action.Font = Enum.Font.GothamBold
		action.TextSize = 15
		action.TextColor3 = CREAM
		action.BackgroundColor3 = BROWN
		action.ZIndex = 42
		action.Parent = tile
		polishButton(action, 8)
		if isEquipped then
			action.Text = "Equipped"
			action.AutoButtonColor = false
			action.BackgroundColor3 = Color3.fromRGB(150, 115, 50)
		elseif isOwned then
			action.Text = back == nil and "Use set's" or "Equip"
			action.MouseButton1Click:Connect(function()
				playClickSfx()
				EquipBackRemote:FireServer(back and back.id or nil)
			end)
		else
			action.Text = "Locked"
			action.AutoButtonColor = false
			action.TextColor3 = DIM
		end
	end

	-- 3-part preview for a set row: backdrop thumbnail, its back, a sample card face tinted by the set.
	local function setPreview(row, set, back, isOwned)
		local holder = Instance.new("Frame")
		holder.Size = UDim2.fromOffset(150, 76)
		holder.Position = UDim2.fromOffset(8, 8)
		holder.BackgroundTransparency = 1
		holder.ZIndex = 42
		holder.Parent = row

		local bd = Instance.new("ImageLabel")
		bd.Size = UDim2.fromOffset(62, 76)
		bd.BackgroundColor3 = Color3.fromRGB(50, 40, 30)
		local image = set.backdropImage
		bd.Image = (image and image ~= "rbxassetid://0") and image or (ArtAssets.gameplayBackground or "rbxassetid://0")
		bd.ScaleType = Enum.ScaleType.Crop
		bd.ImageColor3 = isOwned and Color3.new(1, 1, 1) or Color3.fromRGB(120, 120, 120)
		bd.ZIndex = 42
		bd.Parent = holder
		roundCorner(bd, 6)

		local backThumb = CardBackView.thumb(holder, back, {
			size = Vector2.new(38, 57), locked = not isOwned, shimmer = false, zIndex = 42,
		})
		backThumb.Position = UDim2.fromOffset(66, 9)

		local face = Instance.new("Frame")
		face.Size = UDim2.fromOffset(38, 57)
		face.Position = UDim2.fromOffset(110, 9)
		face.BackgroundColor3 = isOwned and Color3.fromRGB(246, 236, 214) or Color3.fromRGB(120, 120, 120)
		face.ZIndex = 42
		face.Parent = holder
		roundCorner(face, 5)
		local faceStroke = Instance.new("UIStroke")
		faceStroke.Thickness = 2
		local trim = back and back.colors.trim or { 205, 170, 95 }
		faceStroke.Color = Color3.fromRGB(trim[1], trim[2], trim[3])
		faceStroke.Parent = face
		label(face, {
			Size = UDim2.fromScale(1, 1), Font = Enum.Font.GothamBold, TextSize = 18,
			TextColor3 = Color3.fromRGB(60, 40, 22), Text = "A", ZIndex = 43,
		})
	end

	local function refresh()
		for _, child in ipairs(scroll:GetChildren()) do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
		local state = deps.getLatestState()
		local cosmetics = state and state.cosmetics or { equippedSetId = CosmeticSets.DefaultId, unlockedSetIds = { CosmeticSets.DefaultId } }
		local unlocked = {}
		for _, id in ipairs(cosmetics.unlockedSetIds) do
			unlocked[id] = true
		end
		local tips = state and state.tips or 0

		for order, set in ipairs(CosmeticSets.Definitions) do
			local row = Instance.new("Frame")
			row.Size = UDim2.new(1, -8, 0, 96)
			row.BackgroundColor3 = Color3.fromRGB(35, 26, 18)
			row.LayoutOrder = order
			row.ZIndex = 41
			row.Parent = scroll
			roundCorner(row, 8)

			local isOwned = unlocked[set.id] == true
			local isEquipped = cosmetics.equippedSetId == set.id
			local back = CardBacks.getById(set.cardBackId)
			setPreview(row, set, back, isOwned)
			label(row, {
				Size = UDim2.new(1, -310, 0, 22), Position = UDim2.fromOffset(168, 6),
				Font = Enum.Font.GothamBold, TextSize = 17, TextXAlignment = Enum.TextXAlignment.Left,
				TextColor3 = isOwned and GOLD or DIM, Text = isOwned and (set.icon .. " " .. set.name) or "🔒 ???",
				TextTruncate = Enum.TextTruncate.AtEnd,
			})
			label(row, {
				Size = UDim2.new(1, -310, 0, 40), Position = UDim2.fromOffset(168, 28),
				TextSize = 15, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
				TextColor3 = SOFT_CREAM, TextWrapped = true, TextTruncate = Enum.TextTruncate.AtEnd,
				Text = set.description,
			})
			label(row, {
				Size = UDim2.new(1, -310, 0, 22), Position = UDim2.fromOffset(168, 68),
				TextSize = 15, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = DIM,
				TextTruncate = Enum.TextTruncate.AtEnd, Text = CosmeticSets.unlockText(set),
			})

			local action = Instance.new("TextButton")
			action.Size = UDim2.fromOffset(120, 34)
			action.AnchorPoint = Vector2.new(1, 0.5)
			action.Position = UDim2.new(1, -10, 0.5, 0)
			action.Font = Enum.Font.GothamBold
			action.TextSize = 15
			action.TextColor3 = CREAM
			action.BackgroundColor3 = BROWN
			action.ZIndex = 42
			action.Parent = row
			polishButton(action, 8)

			if isEquipped then
				action.Text = "Equipped"
				action.AutoButtonColor = false
				action.BackgroundColor3 = Color3.fromRGB(150, 115, 50)
			elseif isOwned then
				action.Text = "Equip"
				action.MouseButton1Click:Connect(function()
					playClickSfx()
					EquipRemote:FireServer(set.id)
				end)
			elseif set.unlock.kind == "tips" then
				action.Text = string.format("Buy (%d)", math.floor(set.unlock.price))
				if tips < set.unlock.price then
					action.TextColor3 = DIM
				end
				action.MouseButton1Click:Connect(function()
					playClickSfx()
					BuyRemote:FireServer(set.id)
				end)
			else
				action.Text = "Locked"
				action.AutoButtonColor = false
				action.TextColor3 = DIM
			end
		end

		-- Card backs: pick any unlocked one, independent of the set.
		sectionHeader(100, "Card Backs")
		local backsUnlocked = {}
		for _, id in ipairs(cosmetics.unlockedCardBackIds or { CardBacks.DefaultId }) do
			backsUnlocked[id] = true
		end
		cosmetics.cardBackId = cosmetics.cardBackId or CardBacks.DefaultId
		local grid = Instance.new("Frame")
		grid.Name = "BacksGrid"
		grid.Size = UDim2.new(1, -8, 0, 0)
		grid.AutomaticSize = Enum.AutomaticSize.Y
		grid.BackgroundTransparency = 1
		grid.LayoutOrder = 101
		grid.ZIndex = 41
		grid.Parent = scroll
		local gridLayout = Instance.new("UIGridLayout")
		gridLayout.CellSize = UDim2.fromOffset(132, 226)
		gridLayout.CellPadding = UDim2.fromOffset(10, 10)
		gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
		gridLayout.Parent = grid
		backTile(grid, 0, nil, cosmetics, backsUnlocked)
		for i, back in ipairs(CardBacks.Definitions) do
			backTile(grid, i, back, cosmetics, backsUnlocked)
		end
	end

	OverlayManager.register("cosmeticSets", function()
		popOut(backdrop, panel)
	end)

	deps.openButton.MouseButton1Click:Connect(function()
		playClickSfx()
		OverlayManager.closeAllExcept("cosmeticSets")
		refresh()
		popIn(backdrop, panel)
	end)
	closeButton.MouseButton1Click:Connect(function()
		playClickSfx()
		popOut(backdrop, panel)
	end)

	deps.StateUpdatedRemote.OnClientEvent:Connect(function()
		task.defer(function()
			if backdrop.Visible then
				refresh()
			end
		end)
	end)

	return {}
end
