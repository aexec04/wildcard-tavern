--[[
	Client/CosmeticSetsPanel.lua
	The "Card Sets" screen (parchment), opened from a button inside the
	Collection panel. Lists every Cosmetic Set (CosmeticSets.Definitions):
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
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local BuyRemote = remotes:WaitForChild("BuyCosmeticSet")
	local EquipRemote = remotes:WaitForChild("EquipCosmeticSet")

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
	panel.Size = UDim2.fromScale(0.5, 0.7)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.BackgroundColor3 = Color3.fromRGB(40, 30, 22)
	panel.ZIndex = 41
	panel.Parent = backdrop
	polishPanel(panel, 16, "parchment")
	deps.addSoftShadow(panel, 18)

	label(panel, {
		Size = UDim2.new(1, 0, 0, 28), Position = UDim2.fromOffset(0, 6),
		Font = Enum.Font.GothamBold, TextSize = 22, Text = "Card Sets",
	})
	label(panel, {
		Size = UDim2.new(1, -30, 0, 16), Position = UDim2.fromOffset(15, 34),
		TextSize = 12, TextColor3 = SOFT_CREAM,
		Text = "A card back and a tavern backdrop. Looks only.",
	})

	local scroll = Instance.new("ScrollingFrame")
	scroll.Size = UDim2.new(1, -30, 1, -100)
	scroll.Position = UDim2.fromOffset(15, 58)
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
	closeButton.TextSize = 14
	closeButton.TextColor3 = CREAM
	closeButton.BackgroundColor3 = BROWN
	closeButton.Text = "Close"
	closeButton.ZIndex = 42
	closeButton.Parent = panel
	polishButton(closeButton, 8)
	deps.addButtonHoverScale(closeButton)

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
			row.Size = UDim2.new(1, -8, 0, 64)
			row.BackgroundColor3 = Color3.fromRGB(35, 26, 18)
			row.LayoutOrder = order
			row.ZIndex = 41
			row.Parent = scroll
			roundCorner(row, 8)

			local isOwned = unlocked[set.id] == true
			local isEquipped = cosmetics.equippedSetId == set.id
			label(row, {
				Size = UDim2.fromOffset(44, 44), Position = UDim2.fromOffset(8, 10),
				TextSize = 28, Text = isOwned and set.icon or "🔒",
			})
			local back = CardBacks.getById(set.cardBackId)
			label(row, {
				Size = UDim2.new(1, -190, 0, 20), Position = UDim2.fromOffset(60, 8),
				Font = Enum.Font.GothamBold, TextSize = 15, TextXAlignment = Enum.TextXAlignment.Left,
				TextColor3 = isOwned and GOLD or DIM, Text = isOwned and set.name or "???",
			})
			label(row, {
				Size = UDim2.new(1, -190, 0, 16), Position = UDim2.fromOffset(60, 28),
				TextSize = 11, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = SOFT_CREAM,
				Text = isOwned and (set.description .. (back and ("  Card back: " .. back.name) or "")) or set.description,
			})
			label(row, {
				Size = UDim2.new(1, -190, 0, 14), Position = UDim2.fromOffset(60, 44),
				TextSize = 11, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = DIM,
				Text = CosmeticSets.unlockText(set),
			})

			local action = Instance.new("TextButton")
			action.Size = UDim2.fromOffset(110, 32)
			action.AnchorPoint = Vector2.new(1, 0.5)
			action.Position = UDim2.new(1, -10, 0.5, 0)
			action.Font = Enum.Font.GothamBold
			action.TextSize = 13
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
