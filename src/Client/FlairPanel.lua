--[[
	Client/FlairPanel.lua
	FLAIR (Engine/Flair.lua), opened from the "Flair" button in the Collection header. Four slots (Score Numbers, Play Trail,
	Finisher, Name Aura), each a row of option tiles: a preview card with the icon, the name, a rarity frame, and either
	"Equipped", an Equip button, or the unlock hint (locked ones are dimmed, never black; store ones say so). Every unlocked
	option has a Preview button that plays the effect once (nothing plays under Reduce Flashing / Motion / Shake).
	Display only: the server validates the slot, the option and ownership (remote EquipFlair) and sends state.flair.
	Refreshes on every StateUpdated while open.

	init(deps): { screenGui, openButton, polishPanel, polishButton, roundCorner, addSoftShadow, playClickSfx, addTooltip,
	              popIn, popOut, addButtonHoverScale, getLatestState, StateUpdatedRemote, particleBurst }
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local FlairPanel = {}

function FlairPanel.init(deps)
	local OverlayManager = require(script.Parent.OverlayManager)
	local ArtIcon = require(script.Parent.ArtIcon)
	local RarityFrame = require(script.Parent.RarityFrame)
	local FlairFX = require(script.Parent.FlairFX)
	local ClientSettings = require(script.Parent.ClientSettings)
	local EquipRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("EquipFlair")
	local PurchaseRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("StorePurchase")

	local INK = Color3.fromRGB(60, 40, 22)
	local CREAM = Color3.fromRGB(250, 235, 200)
	local GOLD = Color3.fromRGB(222, 182, 104)
	local WOOD = Color3.fromRGB(86, 58, 34)
	local PARCH = Color3.fromRGB(222, 198, 150)
	local GREEN = Color3.fromRGB(86, 140, 80)
	local TILE_W, TILE_H = 132, 196

	local function label(parent, props)
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Font = Enum.Font.GothamBold
		l.TextColor3 = INK
		l.TextTransparency = 0
		l.TextStrokeTransparency = 1
		l.TextSize = 15
		l.ZIndex = 43
		for k, v in pairs(props) do
			l[k] = v
		end
		l.Parent = parent
		return l
	end

	local backdrop = Instance.new("Frame")
	backdrop.Name = "FlairBackdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	backdrop.BackgroundTransparency = 0.4
	backdrop.Visible = false
	backdrop.ZIndex = 40
	backdrop.Parent = deps.screenGui

	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Size = UDim2.fromScale(0.86, 0.9)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.BackgroundColor3 = Color3.fromRGB(40, 30, 22)
	panel.ZIndex = 41
	panel.Parent = backdrop
	deps.polishPanel(panel, 16, "parchment")
	deps.addSoftShadow(panel, 18)

	label(panel, { Size = UDim2.new(1, 0, 0, 30), Position = UDim2.fromOffset(0, 6), TextSize = 22, Text = "Flair" })
	label(panel, {
		Size = UDim2.new(1, -30, 0, 22), Position = UDim2.fromOffset(15, 36), Font = Enum.Font.GothamMedium, TextXAlignment = Enum.TextXAlignment.Left,
		Text = "Looks only. Flair never changes your score.",
	})

	-- the four Store pieces at a lower price (hidden once everything in it is yours)
	local bundleButton = Instance.new("TextButton")
	bundleButton.Size = UDim2.fromOffset(190, 30)
	bundleButton.AnchorPoint = Vector2.new(1, 0)
	bundleButton.Position = UDim2.new(1, -15, 0, 34)
	bundleButton.Font = Enum.Font.GothamBold
	bundleButton.TextSize = 14
	bundleButton.TextColor3 = INK
	bundleButton.BackgroundColor3 = GOLD
	bundleButton.Text = "Flair Bundle"
	bundleButton.ZIndex = 43
	bundleButton.Visible = false
	bundleButton.Parent = panel
	deps.polishButton(bundleButton, 8)
	bundleButton.MouseButton1Click:Connect(function()
		deps.playClickSfx()
		PurchaseRemote:FireServer("flair_bundle")
	end)
	local StorePanelModule = require(script.Parent.StorePanel)

	local scroll = Instance.new("ScrollingFrame")
	scroll.Size = UDim2.new(1, -30, 1, -118)
	scroll.Position = UDim2.fromOffset(15, 62)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 10
	scroll.ScrollBarImageColor3 = GOLD
	scroll.ScrollBarImageTransparency = 0
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new()
	scroll.ZIndex = 41
	scroll.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 12)
	layout.Parent = scroll

	local closeButton = Instance.new("TextButton")
	closeButton.Size = UDim2.fromOffset(110, 34)
	closeButton.AnchorPoint = Vector2.new(0.5, 1)
	closeButton.Position = UDim2.new(0.5, 0, 1, -10)
	closeButton.Font = Enum.Font.GothamBold
	closeButton.TextSize = 15
	closeButton.TextColor3 = CREAM
	closeButton.BackgroundColor3 = Color3.fromRGB(70, 55, 40)
	closeButton.Text = "Close"
	closeButton.ZIndex = 43
	closeButton.Parent = panel
	deps.polishButton(closeButton, 8)
	deps.addButtonHoverScale(closeButton)

	-- one-shot previews: a score number sample or an aura name chip near the middle of the panel
	local function previewSample(slotId, option)
		local center = UDim2.fromOffset(panel.AbsolutePosition.X + panel.AbsoluteSize.X / 2, panel.AbsolutePosition.Y + panel.AbsoluteSize.Y * 0.45)
		if slotId == "playTrail" or slotId == "finisher" then
			if deps.particleBurst then
				FlairFX.preview(deps.particleBurst, slotId, option, center)
			end
			return
		end
		local sample = Instance.new("TextLabel")
		sample.AnchorPoint = Vector2.new(0.5, 0.5)
		sample.Size = UDim2.fromOffset(260, 56)
		sample.Position = UDim2.fromScale(0.5, 0.5)
		sample.BackgroundColor3 = Color3.fromRGB(30, 22, 16)
		sample.BackgroundTransparency = 0.2
		sample.Font = Enum.Font.GothamBold
		sample.TextSize = 32
		sample.TextTransparency = 0
		sample.TextStrokeTransparency = 0.6
		sample.ZIndex = 60
		sample.Parent = backdrop
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 12)
		corner.Parent = sample
		local c = option.color or { 250, 235, 200 }
		sample.TextColor3 = Color3.fromRGB(c[1], c[2], c[3])
		sample.Text = slotId == "nameAura" and ((option.crest or "") .. " You") or "12,480"
		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.fromRGB(c[1], c[2], c[3])
		stroke.Thickness = slotId == "nameAura" and 3 or math.max(1, (option.glow or 0))
		stroke.Parent = sample
		task.delay(1.4, function()
			if sample.Parent then
				if ClientSettings.get("reduceShake") == true then
					sample:Destroy()
				else
					TweenService:Create(sample, TweenInfo.new(0.3), { BackgroundTransparency = 1, TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
					task.delay(0.35, function() if sample.Parent then sample:Destroy() end end)
				end
			end
		end)
	end

	local function tile(row, slotId, option)
		local t = Instance.new("Frame")
		t.Name = "Flair_" .. option.id
		t.Size = UDim2.fromOffset(TILE_W, TILE_H)
		t.BackgroundColor3 = option.equipped and Color3.fromRGB(176, 190, 140) or PARCH
		t.BorderSizePixel = 0
		t.ZIndex = 42
		t.Parent = row
		deps.roundCorner(t, 10)
		pcall(RarityFrame.apply, t, option.rarity or "common", { thickness = 2, radius = 10, locked = not option.owned, zIndex = 46 })

		local well = Instance.new("Frame")
		well.Size = UDim2.fromOffset(64, 64)
		well.Position = UDim2.fromOffset(34, 10)
		well.BackgroundColor3 = WOOD
		well.BorderSizePixel = 0
		well.ZIndex = 43
		well.Parent = t
		deps.roundCorner(well, 10)
		local glyph = label(well, { Size = UDim2.fromScale(1, 1), TextSize = 32, TextColor3 = CREAM, Text = option.icon, ZIndex = 44 })
		pcall(ArtIcon.apply, well, "flair", option.id, glyph, { cornerRadius = 10, zIndex = 45, dim = not option.owned })
		if not option.owned then glyph.TextTransparency = 0.35 end -- dimmed, never black

		label(t, { Size = UDim2.new(1, -6, 0, 34), Position = UDim2.fromOffset(3, 78), TextSize = 14, TextWrapped = true, Text = option.name })
		if option.owned then
			label(t, { Size = UDim2.new(1, -6, 0, 16), Position = UDim2.fromOffset(3, 112), Font = Enum.Font.Gotham, TextSize = 14,
				Text = option.equipped and "Equipped" or "Unlocked" })
			if slotId ~= "nameAura" or true then
				local preview = Instance.new("TextButton")
				preview.Size = UDim2.fromOffset(56, 28)
				preview.Position = UDim2.fromOffset(8, 142)
				preview.Font = Enum.Font.GothamBold
				preview.TextSize = 14
				preview.TextColor3 = CREAM
				preview.BackgroundColor3 = Color3.fromRGB(70, 55, 40)
				preview.Text = "Preview"
				preview.ZIndex = 44
				preview.Parent = t
				deps.polishButton(preview, 6)
				preview.MouseButton1Click:Connect(function()
					deps.playClickSfx()
					previewSample(slotId, option)
				end)
			end
			if not option.equipped then
				local equip = Instance.new("TextButton")
				equip.Size = UDim2.fromOffset(56, 28)
				equip.Position = UDim2.fromOffset(68, 142)
				equip.Font = Enum.Font.GothamBold
				equip.TextSize = 14
				equip.TextColor3 = CREAM
				equip.BackgroundColor3 = GREEN
				equip.Text = "Equip"
				equip.ZIndex = 44
				equip.Parent = t
				deps.polishButton(equip, 6)
				equip.MouseButton1Click:Connect(function()
					deps.playClickSfx()
					EquipRemote:FireServer(slotId, option.id)
				end)
			end
		else
			label(t, { Size = UDim2.new(1, -8, 0, option.store and 28 or 66), Position = UDim2.fromOffset(4, 112), Font = Enum.Font.GothamMedium, TextSize = 14, TextWrapped = true,
				Text = option.store and "Tavern Store" or option.hint })
			if option.store then
				local buy = Instance.new("TextButton")
				buy.Size = UDim2.fromOffset(112, 28)
				buy.Position = UDim2.fromOffset(10, 150)
				buy.Font = Enum.Font.GothamBold
				buy.TextSize = 14
				buy.TextColor3 = INK
				buy.BackgroundColor3 = GOLD
				buy.Text = "Buy"
				buy.ZIndex = 44
				buy.Parent = t
				deps.polishButton(buy, 6)
				buy.MouseButton1Click:Connect(function()
					deps.playClickSfx()
					PurchaseRemote:FireServer("flair_" .. option.id) -- the server checks the item, Studio grants placeholders free
				end)
			end
		end
		deps.addTooltip(t, option.name .. (option.owned and "" or (": " .. (option.store and "Sold in the Tavern Store." or option.hint))))
	end

	local function refresh()
		for _, child in ipairs(scroll:GetChildren()) do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		local state = deps.getLatestState and deps.getLatestState() or nil
		local view = state and state.flair
		if not view then
			return
		end
		bundleButton.Visible = false
		for _, item in ipairs(state.flairStore and state.flairStore.items or {}) do
			if item.id == "flair_bundle" and not item.owned then
				bundleButton.Visible = true
				bundleButton.Text = "Flair Bundle: " .. StorePanelModule.priceText(item)
			end
		end
		for i, slot in ipairs(view.slots) do
			local section = Instance.new("Frame")
			section.LayoutOrder = i
			section.Size = UDim2.new(1, 0, 0, TILE_H + 34)
			section.BackgroundTransparency = 1
			section.ZIndex = 41
			section.Parent = scroll
			label(section, { Size = UDim2.new(1, 0, 0, 26), TextSize = 18, TextXAlignment = Enum.TextXAlignment.Left, Text = slot.icon .. " " .. slot.name })
			local row = Instance.new("ScrollingFrame")
			row.Position = UDim2.fromOffset(0, 30)
			row.Size = UDim2.new(1, 0, 0, TILE_H + 4)
			row.BackgroundTransparency = 1
			row.BorderSizePixel = 0
			row.ScrollingDirection = Enum.ScrollingDirection.X
			row.ScrollBarThickness = 6
			row.AutomaticCanvasSize = Enum.AutomaticSize.X
			row.CanvasSize = UDim2.new()
			row.ZIndex = 41
			row.Parent = section
			local rowLayout = Instance.new("UIListLayout")
			rowLayout.FillDirection = Enum.FillDirection.Horizontal
			rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
			rowLayout.Padding = UDim.new(0, 10)
			rowLayout.Parent = row
			for _, option in ipairs(slot.options) do
				tile(row, slot.id, option)
			end
		end
	end

	OverlayManager.register("flair", function()
		deps.popOut(backdrop, panel)
	end)
	deps.openButton.MouseButton1Click:Connect(function()
		deps.playClickSfx()
		OverlayManager.closeAllExcept("flair")
		refresh()
		deps.popIn(backdrop, panel)
	end)
	closeButton.MouseButton1Click:Connect(function()
		deps.playClickSfx()
		deps.popOut(backdrop, panel)
	end)
	deps.StateUpdatedRemote.OnClientEvent:Connect(function()
		task.defer(function()
			if backdrop.Visible then
				refresh()
			end
		end)
	end)
end

return FlairPanel
