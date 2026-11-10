--[[
	Client/BadgesPanel.lua
	The Badge trophy wall, opened from the Collection group tabs. A ribbon banner with "x of 32 earned" and a thin
	progress rail, filter tabs (All, Roads, Masters, Night, Special: Badges.chipOf) and a wall board whose furniture
	changes per tab (Client/BadgeWall.lua draws it, Engine/BadgeWallLayout.lua places it). Click a badge for a detail
	card (large art, requirement, how to earn it, what it does, Equip / Unequip, VIP second-slot star). One equipped badge
	is shown beside the player's name on the leaderboards and the results screen (EquipBadge remote; the server refuses a
	badge that is not owned).

	Reads state.badgeIds (earned ids), state.equippedBadgeId, state.equippedBadgeId2 and state.store.vip. Refreshes on
	every StateUpdated while open; one Heartbeat (sheen and pulse) runs only while the panel is open and is off under
	Reduce screen shake.
	deps: screenGui, polishPanel, polishButton, roundCorner, addSoftShadow, playClickSfx, openButton, addTooltip,
	      getLatestState, popIn, popOut, addButtonHoverScale, StateUpdatedRemote
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

return function(deps)
	local OverlayManager = require(script.Parent.OverlayManager)
	local Engine = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine")
	local Badges = require(Engine:WaitForChild("Badges"))
	local Wall = require(Engine:WaitForChild("BadgeWallLayout"))
	local ContentArt = require(Engine:WaitForChild("ContentArt"))
	local PatronPlaque = require(script.Parent.PatronPlaque)
	local RarityFrame = require(script.Parent.RarityFrame)
	local ClientSettings = require(script.Parent.ClientSettings)
	local BadgeWall = require(script.Parent.BadgeWall)
	local EquipRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("EquipBadge")

	local polishPanel, polishButton = deps.polishPanel, deps.polishButton
	local roundCorner, playClickSfx = deps.roundCorner, deps.playClickSfx
	local popIn, popOut = deps.popIn, deps.popOut

	local CREAM = Color3.fromRGB(250, 240, 220)
	local GOLD = Color3.fromRGB(222, 182, 104)
	local BROWN = Color3.fromRGB(70, 55, 40)
	local INK = Color3.fromRGB(60, 40, 22)

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

	-- ribbon banner header: title, "x of 32 earned" and a thin progress rail
	local banner = Instance.new("Frame")
	banner.Name = "RibbonBanner"
	banner.AnchorPoint = Vector2.new(0.5, 0)
	banner.Position = UDim2.new(0.5, 0, 0, 8)
	banner.Size = UDim2.new(0.6, 0, 0, 44)
	banner.BackgroundColor3 = Color3.fromRGB(150, 36, 36)
	banner.BorderSizePixel = 0
	banner.ZIndex = 44
	banner.Parent = panel
	roundCorner(banner, 6)
	local bannerStroke = Instance.new("UIStroke")
	bannerStroke.Color = GOLD
	bannerStroke.Thickness = 2
	bannerStroke.Parent = banner
	label(banner, { Size = UDim2.new(1, 0, 0, 24), Position = UDim2.fromOffset(0, 2), Font = Enum.Font.GothamBold, TextSize = 20, Text = "Badges", ZIndex = 46 })
	local countLabel = label(banner, { Size = UDim2.new(1, 0, 0, 18), Position = UDim2.fromOffset(0, 22), Font = Enum.Font.GothamBold, TextSize = 14, Text = "", ZIndex = 46, TextColor3 = Color3.fromRGB(250, 214, 140) })
	local rail = Instance.new("Frame")
	rail.AnchorPoint = Vector2.new(0.5, 0)
	rail.Position = UDim2.new(0.5, 0, 0, 56)
	rail.Size = UDim2.new(0.6, 0, 0, 6)
	rail.BackgroundColor3 = Color3.fromRGB(30, 22, 16)
	rail.BorderSizePixel = 0
	rail.ZIndex = 44
	rail.Parent = panel
	roundCorner(rail, 3)
	local railFill = Instance.new("Frame")
	railFill.Size = UDim2.fromScale(0, 1)
	railFill.BackgroundColor3 = GOLD
	railFill.BorderSizePixel = 0
	railFill.ZIndex = 45
	railFill.Parent = rail
	roundCorner(railFill, 3)

	-- filter tabs
	local activeChip = "All"
	local chipButtons = {}
	local chipRow = Instance.new("Frame")
	chipRow.Size = UDim2.new(1, -30, 0, 28)
	chipRow.Position = UDim2.fromOffset(15, 70)
	chipRow.BackgroundTransparency = 1
	chipRow.ZIndex = 41
	chipRow.Parent = panel
	local chipLayout = Instance.new("UIListLayout")
	chipLayout.FillDirection = Enum.FillDirection.Horizontal
	chipLayout.SortOrder = Enum.SortOrder.LayoutOrder
	chipLayout.Padding = UDim.new(0, 8)
	chipLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	chipLayout.Parent = chipRow

	-- the wall board; furniture and badges are built by BadgeWall.render
	local board = Instance.new("Frame")
	board.Name = "WallBoard"
	board.Position = UDim2.fromOffset(15, 106)
	board.Size = UDim2.new(1, -30, 1, -152)
	board.BackgroundTransparency = 1
	board.BorderSizePixel = 0
	board.ClipsDescendants = true
	board.ZIndex = 41
	board.Parent = panel

	local closeButton = Instance.new("TextButton")
	closeButton.Size = UDim2.fromOffset(110, 30)
	closeButton.AnchorPoint = Vector2.new(0.5, 1)
	closeButton.Position = UDim2.new(0.5, 0, 1, -10)
	closeButton.Font = Enum.Font.GothamBold
	closeButton.TextSize = 15
	closeButton.TextColor3 = CREAM
	closeButton.BackgroundColor3 = BROWN
	closeButton.Text = "Close"
	closeButton.ZIndex = 52
	closeButton.Parent = panel
	polishButton(closeButton, 8)
	deps.addButtonHoverScale(closeButton)

	-- ===== detail card =====
	local detail = Instance.new("Frame")
	detail.Name = "BadgeDetail"
	detail.AnchorPoint = Vector2.new(0.5, 0.5)
	detail.Position = UDim2.fromScale(0.5, 0.5)
	detail.Size = UDim2.new(0, 420, 0, 330)
	detail.BackgroundColor3 = Color3.fromRGB(236, 218, 176)
	detail.BorderSizePixel = 0
	detail.Visible = false
	detail.ZIndex = 60
	detail.Parent = panel
	roundCorner(detail, 12)
	local detailStroke = Instance.new("UIStroke")
	detailStroke.Color = GOLD
	detailStroke.Thickness = 3
	detailStroke.Parent = detail
	local detailArt = Instance.new("Frame")
	detailArt.Size = UDim2.fromOffset(120, 120)
	detailArt.Position = UDim2.fromOffset(14, 14)
	detailArt.BackgroundColor3 = Color3.fromRGB(60, 44, 30)
	detailArt.BorderSizePixel = 0
	detailArt.ClipsDescendants = true
	detailArt.ZIndex = 61
	detailArt.Parent = detail
	roundCorner(detailArt, 16)
	local detailIcon = label(detailArt, { Size = UDim2.fromScale(1, 1), TextSize = 64, Font = Enum.Font.GothamBold, ZIndex = 62, Text = "" })
	local detailName = label(detail, { Size = UDim2.new(1, -170, 0, 30), Position = UDim2.fromOffset(148, 14), TextSize = 22, Font = Enum.Font.GothamBold, TextColor3 = INK, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 62 })
	local detailState = label(detail, { Size = UDim2.new(1, -170, 0, 22), Position = UDim2.fromOffset(148, 46), TextSize = 15, Font = Enum.Font.GothamBold, TextColor3 = Color3.fromRGB(120, 84, 30), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 62 })
	local detailBody = label(detail, { Size = UDim2.new(1, -170, 0, 70), Position = UDim2.fromOffset(148, 72), TextSize = 15, Font = Enum.Font.GothamMedium, TextColor3 = INK, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 62 })
	local detailHow = label(detail, { Size = UDim2.new(1, -28, 0, 44), Position = UDim2.fromOffset(14, 150), TextSize = 15, Font = Enum.Font.GothamMedium, TextColor3 = INK, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 62 })
	local detailReward = label(detail, { Size = UDim2.new(1, -28, 0, 44), Position = UDim2.fromOffset(14, 198), TextSize = 15, Font = Enum.Font.GothamMedium, TextColor3 = Color3.fromRGB(110, 76, 30), TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 62 })
	local equipButton = Instance.new("TextButton")
	equipButton.Size = UDim2.fromOffset(130, 34)
	equipButton.AnchorPoint = Vector2.new(0, 1)
	equipButton.Position = UDim2.new(0, 14, 1, -14)
	equipButton.Font = Enum.Font.GothamBold
	equipButton.TextSize = 16
	equipButton.TextColor3 = CREAM
	equipButton.TextTransparency = 0
	equipButton.TextStrokeTransparency = 1
	equipButton.BackgroundColor3 = BROWN
	equipButton.ZIndex = 62
	equipButton.Parent = detail
	roundCorner(equipButton, 8)
	local starButton = Instance.new("TextButton")
	starButton.Size = UDim2.fromOffset(150, 34)
	starButton.AnchorPoint = Vector2.new(0.5, 1)
	starButton.Position = UDim2.new(0.5, 40, 1, -14)
	starButton.Font = Enum.Font.GothamBold
	starButton.TextSize = 14
	starButton.TextColor3 = CREAM
	starButton.BackgroundColor3 = Color3.fromRGB(86, 58, 34)
	starButton.ZIndex = 62
	starButton.Parent = detail
	roundCorner(starButton, 8)
	local detailClose = Instance.new("TextButton")
	detailClose.Size = UDim2.fromOffset(90, 34)
	detailClose.AnchorPoint = Vector2.new(1, 1)
	detailClose.Position = UDim2.new(1, -14, 1, -14)
	detailClose.Font = Enum.Font.GothamBold
	detailClose.TextSize = 16
	detailClose.TextColor3 = CREAM
	detailClose.BackgroundColor3 = Color3.fromRGB(110, 80, 50)
	detailClose.Text = "Back"
	detailClose.ZIndex = 62
	detailClose.Parent = detail
	roundCorner(detailClose, 8)
	detailClose.MouseButton1Click:Connect(function()
		playClickSfx(0.4)
		detail.Visible = false
	end)

	local have, equippedId, secondId, vipOn = {}, nil, nil, false
	local detailDef = nil

	local function showDetail(def, owned)
		detailDef = def
		detail.Visible = true
		for _, c in ipairs(detailArt:GetChildren()) do
			if c:IsA("ImageLabel") or c.Name == "RarityFrame" then c:Destroy() end
		end
		detailIcon.Text = def.icon
		detailIcon.TextTransparency = owned and 0 or 0.7
		local artId = ContentArt.getImageId("badges", def.id)
		if artId then
			local art = PatronPlaque.applyById(detailArt, artId, { zIndex = 63, cornerRadius = 0 })
			if art then
				art.ScaleType = Enum.ScaleType.Crop
				art.ImageColor3 = owned and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(56, 56, 56)
			end
		end
		detailName.Text = def.name
		detailState.Text = owned and (equippedId == def.id and "Earned, equipped" or "Earned") or "Locked"
		detailBody.Text = def.description
		detailHow.Text = (owned and "How you earned it: " or "How to earn it: ") .. def.hint
		detailReward.Text = "What it does: wear it beside your name on the boards and the results screen."
		equipButton.Visible = owned
		starButton.Visible = owned and vipOn and equippedId ~= def.id
		equipButton.Text = equippedId == def.id and "Unequip" or "Equip"
		equipButton.BackgroundColor3 = equippedId == def.id and Color3.fromRGB(150, 115, 50) or BROWN
		starButton.Text = secondId == def.id and "Unpin 2nd slot" or "Pin 2nd slot \u{2605}"
	end
	equipButton.MouseButton1Click:Connect(function()
		if not detailDef then return end
		playClickSfx()
		EquipRemote:FireServer(equippedId == detailDef.id and nil or detailDef.id) -- tapping the equipped badge takes it off
		detail.Visible = false
	end)
	starButton.MouseButton1Click:Connect(function()
		if not detailDef then return end
		playClickSfx()
		if secondId == detailDef.id then
			EquipRemote:FireServer(nil, 2) -- unpin
		else
			EquipRemote:FireServer(detailDef.id, 2)
		end
		detail.Visible = false
	end)

	-- one Heartbeat for the sheen sweep and the "Next up" pulse; alive only while the panel is open
	local conn = nil
	local function stopLoop()
		if conn then conn:Disconnect(); conn = nil end
	end
	local function startLoop()
		stopLoop()
		if ClientSettings.get("reduceShake") == true or not BadgeWall.animated() then return end
		conn = RunService.Heartbeat:Connect(function()
			if backdrop.Visible then BadgeWall.step() end
		end)
	end

	local function relayout()
		local cam = workspace.CurrentCamera
		local vpX = cam and cam.ViewportSize.X or 1280
		panel.Size = (vpX < 700) and UDim2.fromScale(0.96, 0.92) or UDim2.fromScale(0.78, 0.88)
		detail.Size = UDim2.new(0, math.min(420, math.max(280, vpX - 60)), 0, 330)
	end

	local function refresh()
		relayout()
		local state = deps.getLatestState()
		have = {}
		for _, id in ipairs(state and state.badgeIds or {}) do have[id] = true end
		equippedId = state and state.equippedBadgeId or nil
		secondId = state and state.equippedBadgeId2 or nil
		vipOn = state ~= nil and state.store ~= nil and state.store.vip == true
		local earned, total, frac = Wall.progress(have)
		countLabel.Text = string.format("%d of %d earned", earned, total)
		railFill.Size = UDim2.fromScale(frac, 1)
		for _, entry in ipairs(chipButtons) do
			entry.button.BackgroundColor3 = (entry.name == activeChip) and Color3.fromRGB(150, 115, 50) or BROWN
		end
		BadgeWall.render(board, activeChip, have, {
			equippedId = equippedId, secondId = secondId, onPick = showDetail, tooltip = deps.addTooltip,
		})
		startLoop()
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
			detail.Visible = false
			refresh()
		end)
	end

	-- keep the wall fitted if the window changes while it is open
	local resizePending = false
	board:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		if backdrop.Visible and not resizePending then
			resizePending = true
			task.defer(function()
				resizePending = false
				if backdrop.Visible then refresh() end
			end)
		end
	end)

	require(script.Parent.PanelTabs).attach(backdrop, "badges", deps.playClickSfx) -- shared tab strip + Back
	OverlayManager.register("badges", function()
		stopLoop()
		detail.Visible = false
		popOut(backdrop, panel)
	end)

	local function openThisPanel()
		playClickSfx()
		OverlayManager.closeAllExcept("badges")
		task.spawn(function()
			ContentArt.preload({ { "badges" } }, "badges") -- a lazy category: warm it as the wall opens
		end)
		detail.Visible = false
		refresh()
		popIn(backdrop, panel)
		task.defer(function() if backdrop.Visible then refresh() end end) -- sized now that the panel is shown
	end
	OverlayManager.registerOpener("badges", openThisPanel)
	deps.openButton.MouseButton1Click:Connect(openThisPanel)
	closeButton.MouseButton1Click:Connect(function()
		playClickSfx()
		stopLoop()
		detail.Visible = false
		popOut(backdrop, panel)
	end)

	deps.StateUpdatedRemote.OnClientEvent:Connect(function()
		task.defer(function()
			if backdrop.Visible then refresh() end
		end)
	end)

	return {}
end
