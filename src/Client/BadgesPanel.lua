--[[
	Client/BadgesPanel.lua
	The Badge shelf (parchment), opened from a "Badges" button in the Collection header. One tile per badge in
	Engine/Badges.lua with a RarityFrame for its tier. Earned badges show their icon, name and an Equip / Equipped
	button (one equipped badge, shown beside the player's name on the leaderboards and the results screen;
	EquipBadge remote, the server refuses a badge that is not owned). Locked badges are silhouettes (dimmed icon, the
	tier colour kept, name and the earn hint). Master badges get a slow gold shine sweep, driven by ONE Heartbeat
	connection that only exists while the panel is open and stops under Reduce screen shake.

	Reads state.badgeIds (earned ids) and state.equippedBadgeId. Refreshes on every StateUpdated while open.
	deps: screenGui, polishPanel, polishButton, roundCorner, addSoftShadow, playClickSfx, openButton,
	      getLatestState, popIn, popOut, addButtonHoverScale, StateUpdatedRemote
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

return function(deps)
	local OverlayManager = require(script.Parent.OverlayManager)
	local Engine = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine")
	local Badges = require(Engine:WaitForChild("Badges"))
	local CollectionBook = require(Engine:WaitForChild("CollectionBook"))
	local ContentArt = require(Engine:WaitForChild("ContentArt"))
	local PatronPlaque = require(script.Parent.PatronPlaque)
	local RarityFrame = require(script.Parent.RarityFrame)
	local ClientSettings = require(script.Parent.ClientSettings)
	local EquipRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("EquipBadge")

	local polishPanel, polishButton = deps.polishPanel, deps.polishButton
	local roundCorner, playClickSfx = deps.roundCorner, deps.playClickSfx
	local popIn, popOut = deps.popIn, deps.popOut

	local CREAM = Color3.fromRGB(250, 240, 220)
	local SOFT_CREAM = Color3.fromRGB(215, 200, 178)
	local GOLD = Color3.fromRGB(255, 214, 130)
	local BROWN = Color3.fromRGB(70, 55, 40)
	local INK = Color3.fromRGB(60, 40, 22)
	local TILE = Color3.fromRGB(232, 212, 168)
	local TILE_W, TILE_H = 150, 196
	local SHINE_PERIOD = 3.2

	local function label(parent, props)
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Font = Enum.Font.Gotham
		l.TextColor3 = CREAM
		l.TextTransparency = 0
		l.TextStrokeTransparency = 1
		l.ZIndex = 41
		for k, v in pairs(props) do
			l[k] = v
		end
		l.Parent = parent
		return l
	end

	local backdrop = Instance.new("Frame")
	backdrop.Name = "BadgesBackdrop"
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
		Font = Enum.Font.GothamBold, TextSize = 22, Text = "Badges",
	})
	local countLabel = label(panel, {
		Size = UDim2.new(1, -30, 0, 22), Position = UDim2.fromOffset(15, 34),
		TextSize = 15, TextColor3 = SOFT_CREAM, Text = "",
	})

	local scroll = Instance.new("ScrollingFrame")
	scroll.Size = UDim2.new(1, -30, 1, -112)
	scroll.Position = UDim2.fromOffset(15, 62)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 6
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new()
	scroll.ZIndex = 41
	scroll.Parent = panel
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(TILE_W, TILE_H)
	grid.CellPadding = UDim2.fromOffset(10, 10)
	grid.HorizontalAlignment = Enum.HorizontalAlignment.Center
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = scroll

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

	-- ===== Master shine: one loop for all Master tiles, alive only while the panel is open =====
	local shines = {} -- { strip = Frame, phase = number }
	local shineConn = nil
	local function stopShine()
		if shineConn then
			shineConn:Disconnect()
			shineConn = nil
		end
	end
	local function startShine()
		stopShine()
		if ClientSettings.get("reduceShake") == true or #shines == 0 then
			return
		end
		shineConn = RunService.Heartbeat:Connect(function()
			if not backdrop.Visible then
				return
			end
			local t = os.clock()
			for _, s in ipairs(shines) do
				if s.strip.Parent then
					local k = ((t / SHINE_PERIOD) + s.phase) % 1.6 -- 0.6 of every cycle is a pause off to the right
					local x = k < 1 and (-0.3 + k * 1.6) or 2
					s.strip.Position = UDim2.fromScale(x, -0.1)
				end
			end
		end)
	end

	local function tile(def, owned, equipped, order)
		local t = Instance.new("Frame")
		t.Name = "Badge_" .. def.id
		t.LayoutOrder = order
		t.BackgroundColor3 = owned and TILE or Color3.fromRGB(190, 172, 138)
		t.BorderSizePixel = 0
		t.ClipsDescendants = true
		t.ZIndex = 42
		t.Parent = scroll
		roundCorner(t, 10)
		RarityFrame.apply(t, def.rarity, { thickness = def.tier == "master" and 4 or 3, radius = 10, locked = not owned, zIndex = 46 })

		-- medallion
		local medal = Instance.new("Frame")
		medal.Size = UDim2.fromOffset(72, 72)
		medal.AnchorPoint = Vector2.new(0.5, 0)
		medal.Position = UDim2.new(0.5, 0, 0, 12)
		medal.BackgroundColor3 = owned and (def.tier == "master" and Color3.fromRGB(235, 196, 96) or Color3.fromRGB(205, 178, 120))
			or Color3.fromRGB(150, 135, 110)
		medal.ZIndex = 43
		medal.Parent = t
		roundCorner(medal, 36)
		local ring = Instance.new("UIStroke")
		ring.Color = owned and Color3.fromRGB(110, 80, 45) or Color3.fromRGB(105, 92, 74)
		ring.Thickness = 2
		ring.Parent = medal
		local icon = label(medal, {
			Size = UDim2.fromScale(1, 1), TextSize = 40, Font = Enum.Font.GothamBold, Text = def.icon, ZIndex = 44,
		})
		if not owned then
			icon.TextTransparency = 0.7 -- silhouette: the shape is there, the picture is not
			icon.TextColor3 = Color3.fromRGB(60, 50, 40)
		end
		-- Painted badge art (BadgeArt via ContentArt "badges"); the emoji stays until an id is recorded and loaded.
		PatronPlaque.applyById(medal, ContentArt.getImageId("badges", def.id), {
			emojiLabel = icon, dim = not owned, cornerRadius = 36, zIndex = 45,
		})

		label(t, {
			Size = UDim2.new(1, -12, 0, 40), Position = UDim2.fromOffset(6, 88), TextSize = 15,
			Font = Enum.Font.GothamBold, TextWrapped = true, TextColor3 = INK, ZIndex = 44,
			Text = def.name,
		})

		if owned then
			local b = Instance.new("TextButton")
			b.Size = UDim2.new(1, -24, 0, 30)
			b.AnchorPoint = Vector2.new(0.5, 1)
			b.Position = UDim2.new(0.5, 0, 1, -12)
			b.Font = Enum.Font.GothamBold
			b.TextSize = 15
			b.TextColor3 = CREAM
			b.TextTransparency = 0
			b.TextStrokeTransparency = 1
			b.ZIndex = 47
			b.Parent = t
			roundCorner(b, 8)
			if equipped then
				b.Text = "Equipped"
				b.BackgroundColor3 = Color3.fromRGB(150, 115, 50)
				b.AutoButtonColor = false
				b.MouseButton1Click:Connect(function()
					playClickSfx()
					EquipRemote:FireServer(nil) -- tapping the equipped badge takes it off
				end)
			else
				b.Text = "Equip"
				b.BackgroundColor3 = BROWN
				b.MouseButton1Click:Connect(function()
					playClickSfx()
					EquipRemote:FireServer(def.id)
				end)
			end
		else
			label(t, {
				Size = UDim2.new(1, -16, 0, 56), Position = UDim2.new(0, 8, 1, -64), TextSize = 15,
				TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, TextColor3 = Color3.fromRGB(80, 62, 44),
				Font = Enum.Font.GothamMedium, ZIndex = 44, Text = "🔒 " .. def.hint,
			})
		end

		if owned and def.tier == "master" then
			local strip = Instance.new("Frame") -- thin white-gold diagonal highlight (plain Frame; no UIGradient transparency)
			strip.Name = "MasterShine"
			strip.Size = UDim2.fromScale(0.14, 1.3)
			strip.Position = UDim2.fromScale(2, -0.1)
			strip.Rotation = 18
			strip.BackgroundColor3 = Color3.fromRGB(255, 240, 190)
			strip.BackgroundTransparency = 0.72
			strip.BorderSizePixel = 0
			strip.Active = false
			strip.ZIndex = 48
			strip.Parent = t
			table.insert(shines, { strip = strip, phase = (order % 7) * 0.13 })
		end
		return t
	end

	local function refresh()
		for _, child in ipairs(scroll:GetChildren()) do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		shines = {}
		local state = deps.getLatestState()
		local have = {}
		for _, id in ipairs(state and state.badgeIds or {}) do
			have[id] = true
		end
		local equippedId = state and state.equippedBadgeId or nil
		-- Earned badges first (rarest first), then the locked ones in registry order.
		local order = {}
		for i, def in ipairs(Badges.Definitions) do
			order[#order + 1] = { def = def, owned = have[def.id] == true, index = i }
		end
		local rank = {}
		for i, id in ipairs(CollectionBook.RarityOrder) do rank[id] = i end
		table.sort(order, function(a, b)
			if a.owned ~= b.owned then return a.owned end
			if a.owned and (rank[a.def.rarity] or 0) ~= (rank[b.def.rarity] or 0) then
				return (rank[a.def.rarity] or 0) > (rank[b.def.rarity] or 0)
			end
			return a.index < b.index
		end)
		local earned = 0
		for i, o in ipairs(order) do
			if o.owned then earned = earned + 1 end
			tile(o.def, o.owned, equippedId == o.def.id, i)
		end
		countLabel.Text = string.format("%d of %d earned.  Equip one to show it beside your name.", earned, #Badges.Definitions)
		startShine()
	end

	OverlayManager.register("badges", function()
		stopShine()
		popOut(backdrop, panel)
	end)

	deps.openButton.MouseButton1Click:Connect(function()
		playClickSfx()
		OverlayManager.closeAllExcept("badges")
		refresh()
		popIn(backdrop, panel)
	end)
	closeButton.MouseButton1Click:Connect(function()
		playClickSfx()
		stopShine()
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
