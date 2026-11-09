--[[
	Client/BadgesPanel.lua
	The Badge trophy shelf, opened from a "Badges" button in the Collection header. A progress bar (earned of
	total), filter chips (All, Roads, Masters, Night, Special: Badges.chipOf) and a grid that fills the panel
	width (Badges.gridFor). One tile per badge in Engine/Badges.lua: the painted BadgeArt fills the top two
	thirds (Crop, drawn at full opacity at once: no IsLoaded gate, the emoji sits behind it as a fallback and a
	missing id warns once), a gold frame when earned, a dark silhouette with a padlock when locked, the name and
	the requirement line below, and a small Equip / Unequip pill. The equipped badge wears an "Equipped" ribbon and
	a shine sweep (one Heartbeat connection, alive only while the panel is open, off under Reduce screen shake).
	Hovering a tile shows only its requirement. One equipped badge is shown beside the player's name on the
	leaderboards and the results screen (EquipBadge remote; the server refuses a badge that is not owned).

	Reads state.badgeIds (earned ids) and state.equippedBadgeId. Refreshes on every StateUpdated while open.
	deps: screenGui, polishPanel, polishButton, roundCorner, addSoftShadow, playClickSfx, openButton, addTooltip,
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
	local GOLD = Color3.fromRGB(222, 182, 104)
	local BROWN = Color3.fromRGB(70, 55, 40)
	local INK = Color3.fromRGB(60, 40, 22)
	local TILE = Color3.fromRGB(232, 212, 168)
	local TILE_W, TILE_H = 170, 247 -- replaced by relayout() from the real shelf width
	local GAP, MIN_CELL = 10, 170
	local SHINE_PERIOD = 3.2
	local warnedNoArt = {}

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
	panel.Size = UDim2.fromScale(0.78, 0.88)
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

	-- progress bar: gold fill, the count sits on it
	local progressBack = Instance.new("Frame")
	progressBack.Size = UDim2.new(1, -30, 0, 22)
	progressBack.Position = UDim2.fromOffset(15, 38)
	progressBack.BackgroundColor3 = Color3.fromRGB(30, 22, 16)
	progressBack.BorderSizePixel = 0
	progressBack.ZIndex = 41
	progressBack.Parent = panel
	roundCorner(progressBack, 11)
	local progressFill = Instance.new("Frame")
	progressFill.Size = UDim2.fromScale(0, 1)
	progressFill.BackgroundColor3 = GOLD
	progressFill.BorderSizePixel = 0
	progressFill.ZIndex = 42
	progressFill.Parent = progressBack
	roundCorner(progressFill, 11)
	local countLabel = label(progressBack, {
		Size = UDim2.fromScale(1, 1), TextSize = 14, Font = Enum.Font.GothamBold, ZIndex = 43,
		TextColor3 = CREAM, TextStrokeColor3 = Color3.fromRGB(30, 18, 8), TextStrokeTransparency = 0.35, Text = "",
	})

	-- filter chips
	local activeChip = "All"
	local chipButtons = {}
	local chipRow = Instance.new("Frame")
	chipRow.Size = UDim2.new(1, -30, 0, 28)
	chipRow.Position = UDim2.fromOffset(15, 68)
	chipRow.BackgroundTransparency = 1
	chipRow.ZIndex = 41
	chipRow.Parent = panel
	local chipLayout = Instance.new("UIListLayout")
	chipLayout.FillDirection = Enum.FillDirection.Horizontal
	chipLayout.SortOrder = Enum.SortOrder.LayoutOrder
	chipLayout.Padding = UDim.new(0, 8)
	chipLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	chipLayout.Parent = chipRow

	local scroll = Instance.new("ScrollingFrame")
	scroll.Size = UDim2.new(1, -30, 1, -146)
	scroll.Position = UDim2.fromOffset(15, 104)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 10
	scroll.ScrollBarImageColor3 = GOLD
	scroll.ScrollBarImageTransparency = 0
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new()
	scroll.ZIndex = 41
	scroll.Parent = panel
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(TILE_W, TILE_H)
	grid.CellPadding = UDim2.fromOffset(GAP, GAP)
	grid.HorizontalAlignment = Enum.HorizontalAlignment.Left
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

	-- ===== Equipped shine: one loop for the shelf, alive only while the panel is open =====
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

	local vipOn, secondId = false, nil -- VIP second badge slot (state.store.vip, state.equippedBadgeId2)
	local function tile(def, owned, equipped, order)
		local w = TILE_W
		local artH = math.floor(w * 0.9)
		local t = Instance.new("Frame")
		t.Name = "Badge_" .. def.id
		t.LayoutOrder = order
		t.BackgroundColor3 = owned and TILE or Color3.fromRGB(176, 158, 126)
		t.BorderSizePixel = 0
		t.ClipsDescendants = true
		t.ZIndex = 42
		t.Parent = scroll
		roundCorner(t, 10)
		RarityFrame.apply(t, def.rarity, { thickness = def.tier == "master" and 4 or 3, radius = 10, locked = not owned, zIndex = 46 })

		-- art window: the painted badge fills the top two thirds
		local artFrame = Instance.new("Frame")
		artFrame.Name = "ArtWindow"
		artFrame.Position = UDim2.fromOffset(6, 6)
		artFrame.Size = UDim2.fromOffset(w - 12, artH)
		artFrame.BackgroundColor3 = owned and Color3.fromRGB(70, 52, 36) or Color3.fromRGB(46, 36, 28)
		artFrame.BorderSizePixel = 0
		artFrame.ClipsDescendants = true
		artFrame.ZIndex = 43
		artFrame.Parent = t
		roundCorner(artFrame, 8)
		local frameStroke = Instance.new("UIStroke")
		frameStroke.Color = owned and GOLD or Color3.fromRGB(105, 92, 74)
		frameStroke.Thickness = owned and 2.5 or 1.5
		frameStroke.Parent = artFrame
		-- emoji fallback sits BEHIND the art and is never hidden: the art simply covers it
		label(artFrame, {
			Size = UDim2.fromScale(1, 1), TextSize = math.floor(artH * 0.5), Font = Enum.Font.GothamBold, Text = def.icon, ZIndex = 44,
			TextTransparency = owned and 0 or 0.7, TextColor3 = owned and CREAM or Color3.fromRGB(60, 50, 40),
		})
		local artId = ContentArt.getImageId("badges", def.id)
		if artId then
			local art = PatronPlaque.applyById(artFrame, artId, { zIndex = 45, cornerRadius = 0 })
			if art then
				art.ScaleType = Enum.ScaleType.Crop
				-- locked: a dark silhouette, never black
				art.ImageColor3 = owned and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(62, 62, 62)
			end
		elseif not warnedNoArt[def.id] then
			warnedNoArt[def.id] = true
			warn("[Badges] no painted art for badge '" .. def.id .. "' (emoji fallback shown)")
		end
		if not owned then
			local lock = label(artFrame, {
				AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(46, 46),
				TextSize = 26, Text = "\240\159\148\146", ZIndex = 47, BackgroundTransparency = 0.25,
				BackgroundColor3 = Color3.fromRGB(26, 19, 13),
			})
			roundCorner(lock, 23)
		end

		-- hover shows only the requirement
		local hit = Instance.new("TextButton")
		hit.Name = "Hit"
		hit.Size = artFrame.Size
		hit.Position = artFrame.Position
		hit.BackgroundTransparency = 1
		hit.Text = ""
		hit.AutoButtonColor = false
		hit.ZIndex = 49
		hit.Parent = t
		if deps.addTooltip then
			deps.addTooltip(hit, def.hint)
		end

		local nameY = 6 + artH + 4
		label(t, {
			Size = UDim2.new(1, -12, 0, 20), Position = UDim2.fromOffset(6, nameY), TextSize = 15,
			Font = Enum.Font.GothamBold, TextColor3 = INK, ZIndex = 44, TextTruncate = Enum.TextTruncate.AtEnd,
			Text = def.name,
		})
		label(t, {
			Size = UDim2.new(1, -12, 0, 30), Position = UDim2.fromOffset(6, nameY + 20), TextSize = 13,
			TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, TextColor3 = Color3.fromRGB(80, 62, 44),
			Font = Enum.Font.GothamMedium, ZIndex = 44, TextTruncate = Enum.TextTruncate.AtEnd, Text = def.hint,
		})

		if owned then
			local b = Instance.new("TextButton")
			b.Size = UDim2.fromOffset(math.floor(w * 0.62), 24)
			b.AnchorPoint = Vector2.new(0.5, 1)
			b.Position = UDim2.new(0.5, 0, 1, -6)
			b.Font = Enum.Font.GothamBold
			b.TextSize = 14
			b.TextColor3 = CREAM
			b.TextTransparency = 0
			b.TextStrokeTransparency = 1
			b.ZIndex = 50
			b.Parent = t
			roundCorner(b, 12)
			b.Text = equipped and "Unequip" or "Equip"
			b.BackgroundColor3 = equipped and Color3.fromRGB(150, 115, 50) or BROWN
			b.MouseButton1Click:Connect(function()
				playClickSfx()
				if equipped then
					EquipRemote:FireServer(nil) -- tapping the equipped badge takes it off
				else
					EquipRemote:FireServer(def.id)
				end
			end)
		end

		if owned and vipOn and not equipped then
			-- VIP: a small star pins this badge in the second slot (tap again to unpin)
			local star = Instance.new("TextButton")
			star.Name = "SecondSlot"
			star.Size = UDim2.fromOffset(28, 28)
			star.Position = UDim2.new(1, -32, 0, 4)
			star.Font = Enum.Font.GothamBold
			star.TextSize = 18
			star.Text = "\u{2605}"
			star.TextColor3 = secondId == def.id and INK or CREAM
			star.BackgroundColor3 = secondId == def.id and GOLD or Color3.fromRGB(86, 58, 34)
			star.ZIndex = 52
			star.Parent = t
			roundCorner(star, 14)
			star.MouseButton1Click:Connect(function()
				playClickSfx()
				if secondId == def.id then
					EquipRemote:FireServer(nil, 2) -- unpin
				else
					EquipRemote:FireServer(def.id, 2)
				end
			end)
		end

		if equipped then
			local ribbon = Instance.new("Frame")
			ribbon.Name = "EquippedRibbon"
			ribbon.Position = UDim2.fromOffset(0, 14)
			ribbon.Size = UDim2.fromOffset(92, 22)
			ribbon.BackgroundColor3 = GOLD
			ribbon.BorderSizePixel = 0
			ribbon.ZIndex = 51
			ribbon.Parent = t
			label(ribbon, {
				Size = UDim2.fromScale(1, 1), TextSize = 13, Font = Enum.Font.GothamBold, TextColor3 = INK, ZIndex = 52, Text = "Equipped",
			})
			local strip = Instance.new("Frame") -- thin white-gold diagonal highlight (plain Frame; no UIGradient transparency)
			strip.Name = "EquippedShine"
			strip.Size = UDim2.fromScale(0.14, 1.3)
			strip.Position = UDim2.fromScale(2, -0.1)
			strip.Rotation = 18
			strip.BackgroundColor3 = Color3.fromRGB(255, 240, 190)
			strip.BackgroundTransparency = 0.7
			strip.BorderSizePixel = 0
			strip.Active = false
			strip.ZIndex = 48
			strip.Parent = t
			table.insert(shines, { strip = strip, phase = 0 })
		end
		return t
	end

	-- Cells fill the whole shelf width (Badges.gridFor); tiles are rebuilt at the new size.
	local function relayout()
		local cam = workspace.CurrentCamera
		local vpX = cam and cam.ViewportSize.X or 1280
		local small = vpX < 700
		panel.Size = small and UDim2.fromScale(0.96, 0.92) or UDim2.fromScale(0.78, 0.88)
		local width = scroll.AbsoluteSize.X
		if width <= 0 then
			width = math.floor(vpX * (small and 0.96 or 0.78)) - 30
		end
		local _, cellW = Badges.gridFor(width - 12, MIN_CELL, GAP, 2) -- 12 = scroll bar + breathing room
		TILE_W = cellW
		TILE_H = math.floor(cellW * 0.9) + 94
		grid.CellSize = UDim2.fromOffset(TILE_W, TILE_H)
	end

	local function refresh()
		for _, child in ipairs(scroll:GetChildren()) do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		shines = {}
		relayout()
		local state = deps.getLatestState()
		local have = {}
		for _, id in ipairs(state and state.badgeIds or {}) do
			have[id] = true
		end
		local equippedId = state and state.equippedBadgeId or nil
		vipOn = state ~= nil and state.store ~= nil and state.store.vip == true
		secondId = state and state.equippedBadgeId2 or nil
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
		local earned, shown = 0, 0
		for _, o in ipairs(order) do
			if o.owned then earned = earned + 1 end
			if activeChip == "All" or Badges.chipOf(o.def) == activeChip then
				shown = shown + 1
				tile(o.def, o.owned, equippedId == o.def.id, shown)
			end
		end
		countLabel.Text = string.format("%d of %d earned", earned, #Badges.Definitions)
		progressFill.Size = UDim2.fromScale(#Badges.Definitions > 0 and earned / #Badges.Definitions or 0, 1)
		for _, entry in ipairs(chipButtons) do
			entry.button.BackgroundColor3 = (entry.name == activeChip) and Color3.fromRGB(150, 115, 50) or BROWN
		end
		startShine()
	end

	for i, name in ipairs(Badges.Chips) do
		local c = Instance.new("TextButton")
		c.LayoutOrder = i
		c.Size = UDim2.fromOffset(84, 28)
		c.Font = Enum.Font.GothamBold
		c.TextSize = 14
		c.TextColor3 = CREAM
		c.TextTransparency = 0
		c.TextStrokeTransparency = 1
		c.BackgroundColor3 = BROWN
		c.Text = name
		c.ZIndex = 42
		c.Parent = chipRow
		roundCorner(c, 14)
		table.insert(chipButtons, { name = name, button = c })
		c.MouseButton1Click:Connect(function()
			playClickSfx(0.4)
			activeChip = name
			refresh()
		end)
	end

	-- keep the grid filling the width if the window changes while the shelf is open
	local resizePending = false
	scroll:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		if backdrop.Visible and not resizePending then
			resizePending = true
			task.defer(function()
				resizePending = false
				if backdrop.Visible then
					refresh()
				end
			end)
		end
	end)

	OverlayManager.register("badges", function()
		stopShine()
		popOut(backdrop, panel)
	end)

	deps.openButton.MouseButton1Click:Connect(function()
		playClickSfx()
		OverlayManager.closeAllExcept("badges")
		task.spawn(function()
			ContentArt.preload({ { "badges" } }, "badges") -- a lazy category: warm it as the shelf opens
		end)
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
