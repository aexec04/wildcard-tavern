--[[
	Client/CollectionRewardsPanel.lua
	Collection completion rewards (Engine/CollectionRewards.lua), opened from the "Rewards" button in the Collection
	header. One row per group (Patrons, Recipes, Boss Rounds, Card Sets, Titles, Badges): a progress ring with the
	percent, then four milestone chips at 25, 50, 75 and 100 percent. A reached chip glows and is tapped to claim; a
	claimed chip shows a check; a locked chip is dimmed. "Claim All" takes everything that is ready.
	Display only: the server re-checks the progress before paying (remote ClaimCollectionReward) and sends
	state.collectionRewards. Refreshes on every StateUpdated while open.

	init(deps): { screenGui, openButton, polishPanel, polishButton, roundCorner, addSoftShadow, playClickSfx, addTooltip,
	              popIn, popOut, addButtonHoverScale, getLatestState, StateUpdatedRemote }
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CollectionRewardsPanel = {}

function CollectionRewardsPanel.init(deps)
	local OverlayManager = require(script.Parent.OverlayManager)
	local ArtIcon = require(script.Parent.ArtIcon)
	local ClaimRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("ClaimCollectionReward")

	local INK = Color3.fromRGB(60, 40, 22)
	local CREAM = Color3.fromRGB(250, 235, 200)
	local GOLD = Color3.fromRGB(222, 182, 104)
	local WOOD = Color3.fromRGB(86, 58, 34)
	local PARCH = Color3.fromRGB(104, 76, 48) -- milestone tile: dark wood
	local LEATHER = Color3.fromRGB(66, 48, 34) -- row: dark leather
	local BRASS = Color3.fromRGB(150, 110, 44)
	local GREEN = Color3.fromRGB(70, 118, 66)
	local Layout = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("RewardsLayout"))
	local ContentArt = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("ContentArt"))

	local function label(parent, props)
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Font = Enum.Font.GothamBold
		l.TextColor3 = CREAM
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
	backdrop.Name = "CollectionRewardsBackdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	backdrop.BackgroundTransparency = 0.4
	backdrop.Visible = false
	backdrop.ZIndex = 40
	backdrop.Parent = deps.screenGui

	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0, 0.5)
	panel.Size = UDim2.fromScale(0.66, 0.78)
	panel.Position = UDim2.fromScale(0.17, 0.5)
	local function placePanel() -- Collection's left edge, never over the left HUD, at every window size
		local cam = workspace.CurrentCamera
		local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
		local fit = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("ResponsiveLayout")).badgesPanel(vp.X, vp.Y)
		panel.Size = UDim2.fromOffset(fit.w, math.max(fit.h, math.floor(vp.Y * 0.84)))
		panel.Position = UDim2.new(0, fit.x, 0.5, 0)
	end
	placePanel()
	if workspace.CurrentCamera then workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(placePanel) end
	panel.BackgroundColor3 = Color3.fromRGB(40, 30, 22)
	panel.ZIndex = 41
	panel.Parent = backdrop
	deps.polishPanel(panel, 16, "parchment")
	deps.addSoftShadow(panel, 18)

	do
		local sign = Instance.new("Frame")
		sign.Name = "TitleSign"
		sign.AnchorPoint = Vector2.new(0.5, 0)
		sign.Size = UDim2.fromOffset(280, 34)
		sign.Position = UDim2.new(0.5, 0, 0, 6)
		sign.BackgroundColor3 = BRASS
		sign.BorderSizePixel = 0
		sign.ZIndex = 42
		sign.Parent = panel
		deps.roundCorner(sign, 8)
		local rim = Instance.new("UIStroke")
		rim.Color = GOLD
		rim.Thickness = 2
		rim.Parent = sign
		label(sign, { Size = UDim2.fromScale(1, 1), TextSize = 22, Text = "Collection Rewards", TextColor3 = CREAM, ZIndex = 44 }) -- cream on brass
	end

	local claimAll = Instance.new("TextButton")
	claimAll.Size = UDim2.fromOffset(170, 32)
	claimAll.AnchorPoint = Vector2.new(1, 0)
	claimAll.Position = UDim2.new(1, -15, 0, 8)
	claimAll.Font = Enum.Font.GothamBold
	claimAll.TextSize = 15
	claimAll.TextColor3 = CREAM
	claimAll.BackgroundColor3 = GREEN
	claimAll.Text = "Claim All"
	claimAll.ZIndex = 43
	claimAll.Parent = panel
	deps.polishButton(claimAll, 8)
	deps.addButtonHoverScale(claimAll)

	local scroll = Instance.new("ScrollingFrame")
	scroll.Size = UDim2.new(1, -30, 1, -102)
	scroll.Position = UDim2.fromOffset(15, 52)
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
	layout.Padding = UDim.new(0, 10)
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

	local function clear()
		for _, child in ipairs(scroll:GetChildren()) do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
	end

	local function rewardArt(reward)
		-- Shared resolver: Tips, XP, tokens and the rest always get an emoji, never the grey X box.
		return require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("RewardArt")).resolve(reward)
	end

	local function chip(row, group, m, order, rect)
		local c = Instance.new("TextButton")
		c.Name = "Milestone_" .. m.pct
		c.LayoutOrder = order
		c.Position = UDim2.fromOffset(rect.x, rect.y)
		c.Size = UDim2.fromOffset(rect.w, rect.h)
		c.AutoButtonColor = false
		c.Text = ""
		c.BackgroundColor3 = m.claimed and Color3.fromRGB(70, 92, 62) or PARCH
		c.BorderSizePixel = 0
		c.ZIndex = 42
		c.Parent = row
		deps.roundCorner(c, 10)
		local claimable = m.reached and not m.claimed
		local stroke = Instance.new("UIStroke")
		stroke.Color = claimable and GOLD or Color3.fromRGB(40, 28, 18)
		stroke.Thickness = claimable and 3 or 1.5
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Parent = c
		if claimable then -- a soft warm glow behind a claimable tile
			local glow = Instance.new("Frame")
			glow.Name = "Glow"
			glow.AnchorPoint = Vector2.new(0.5, 0.5)
			glow.Position = UDim2.fromScale(0.5, 0.5)
			glow.Size = UDim2.new(1, 10, 1, 10)
			glow.BackgroundColor3 = Color3.fromRGB(255, 190, 90)
			glow.BackgroundTransparency = 0.82
			glow.BorderSizePixel = 0
			glow.ZIndex = 41
			glow.Parent = c
			deps.roundCorner(glow, 14)
		end
		label(c, { Size = UDim2.new(1, 0, 0, 20), Position = UDim2.fromOffset(0, 3), TextSize = 16, Text = m.pct .. "%" })
		local well = Instance.new("Frame")
		well.Size = UDim2.fromOffset(46, 46)
		well.Position = UDim2.new(0.5, -23, 0, 26)
		well.BackgroundColor3 = WOOD
		well.BorderSizePixel = 0
		well.ZIndex = 43
		well.Parent = c
		deps.roundCorner(well, 8)
		local category, key, emoji = rewardArt(m.reward)
		local pouch = Layout.pouchKey(m.reward) -- Tips rewards get a small or a full coin pouch once the art is recorded
		if pouch and ContentArt.getImageId("rewards_emblems", pouch) then category, key = "rewards_emblems", pouch end
		local glyph = label(well, { Size = UDim2.fromScale(1, 1), TextSize = 24, TextColor3 = CREAM, Text = emoji, ZIndex = 44 })
		if category then
			pcall(ArtIcon.apply, well, category, key, glyph, { cornerRadius = 8, zIndex = 45, dim = not m.reached })
		end
		if not m.reached then glyph.TextTransparency = 0.35 end -- dimmed, never black
		label(c, { Size = UDim2.new(1, -6, 0, 32), Position = UDim2.fromOffset(3, 72), TextSize = 14, TextWrapped = true, Font = Enum.Font.GothamMedium, Text = m.text or "" })
		if m.claimed then
			label(c, { Size = UDim2.fromOffset(28, 28), Position = UDim2.new(1, -30, 0, 0), TextSize = 20, TextColor3 = Color3.fromRGB(150, 220, 140), Text = "\226\156\148", ZIndex = 47 })
		elseif claimable then -- a Claim button on a brass plate
			local plate = Instance.new("Frame")
			plate.Name = "ClaimPlate"
			plate.AnchorPoint = Vector2.new(1, 0)
			plate.Position = UDim2.new(1, -3, 0, 2)
			plate.Size = UDim2.fromOffset(52, 20)
			plate.BackgroundColor3 = BRASS
			plate.BorderSizePixel = 0
			plate.ZIndex = 46
			plate.Parent = c
			deps.roundCorner(plate, 5)
			label(plate, { Size = UDim2.fromScale(1, 1), TextSize = 14, Text = "Claim", ZIndex = 47 })
		end
		c.MouseButton1Click:Connect(function()
			if m.reached and not m.claimed then
				deps.playClickSfx()
				pcall(function() require(script.Parent.Cue).play("reward_claim") end)
				ClaimRemote:FireServer(group, m.pct)
			end
		end)
		deps.addTooltip(c, (m.text or "") .. (m.claimed and " (claimed)" or m.reached and " (tap to claim)" or (" at " .. m.pct .. " percent")))
	end

	local function groupRow(g, order)
		local rowW = math.max(300, scroll.AbsoluteSize.X - 12)
		local geo = Layout.row(rowW, #g.milestones)
		local row = Instance.new("Frame")
		row.Name = "Group_" .. g.id
		row.LayoutOrder = order
		row.Size = UDim2.new(1, 0, 0, geo.rowH)
		row.BackgroundColor3 = LEATHER
		row.BorderSizePixel = 0
		row.ZIndex = 42
		row.Parent = scroll
		deps.roundCorner(row, 12)
		-- the category emblem: painted medallion when its Image id is recorded, else the old round badge with the emoji
		local emblem = Instance.new("Frame")
		emblem.Name = "Emblem"
		emblem.Position = UDim2.fromOffset(geo.emblem.x, geo.emblem.y)
		emblem.Size = UDim2.fromOffset(geo.emblem.w, geo.emblem.h)
		emblem.BackgroundColor3 = WOOD
		emblem.BorderSizePixel = 0
		emblem.ZIndex = 43
		emblem.Parent = row
		deps.roundCorner(emblem, 42)
		local glyph = label(emblem, { Size = UDim2.fromScale(1, 1), TextSize = 34, Text = g.icon, ZIndex = 44 })
		local key = Layout.emblemKey(g.id)
		if key then pcall(ArtIcon.apply, emblem, "rewards_emblems", key, glyph, { cornerRadius = 42, zIndex = 45 }) end
		-- a thin progress ring of dots around the emblem, filling with the percent
		local lit = Layout.litDots(g.percent, 36)
		local cx, cy = geo.emblem.x + geo.emblem.w / 2, geo.emblem.y + geo.emblem.h / 2
		for i, d in ipairs(Layout.ringDots(36, cx, cy, geo.emblem.w / 2 + 3)) do
			local dot = Instance.new("Frame")
			dot.Name = "RingDot"
			dot.AnchorPoint = Vector2.new(0.5, 0.5)
			dot.Position = UDim2.fromOffset(d.x, d.y)
			dot.Size = UDim2.fromOffset(3, 3)
			dot.BackgroundColor3 = i <= lit and GOLD or Color3.fromRGB(40, 28, 18)
			dot.BorderSizePixel = 0
			dot.ZIndex = 43
			dot.Parent = row
		end
		local plate = Instance.new("Frame")
		plate.Name = "PercentPlate"
		plate.Position = UDim2.fromOffset(geo.plate.x, geo.plate.y)
		plate.Size = UDim2.fromOffset(geo.plate.w, geo.plate.h)
		plate.BackgroundColor3 = BRASS
		plate.BorderSizePixel = 0
		plate.ZIndex = 44
		plate.Parent = row
		deps.roundCorner(plate, 5)
		label(plate, { Size = UDim2.fromScale(1, 1), TextSize = 16, Text = g.percent .. "%", ZIndex = 45 })
		label(row, { Size = UDim2.fromOffset(geo.name.w, geo.name.h), Position = UDim2.fromOffset(geo.name.x, geo.name.y), TextSize = 17, TextXAlignment = Enum.TextXAlignment.Left, Text = g.name })
		label(row, { Size = UDim2.fromOffset(geo.count.w, geo.count.h), Position = UDim2.fromOffset(geo.count.x, geo.count.y), Font = Enum.Font.Gotham, TextXAlignment = Enum.TextXAlignment.Left,
			Text = g.found .. " of " .. g.total })
		for i, m in ipairs(g.milestones) do
			if geo.chips[i] then chip(row, g.id, m, i, geo.chips[i]) end
		end
	end

	local function refresh()
		local state = deps.getLatestState and deps.getLatestState() or nil
		local view = state and state.collectionRewards
		clear()
		if not view then
			claimAll.Visible = false
			return
		end
		claimAll.Visible = true
		claimAll.Text = view.claimable > 0 and ("Claim All (" .. view.claimable .. ")") or "Claim All"
		claimAll.BackgroundColor3 = view.claimable > 0 and GREEN or Color3.fromRGB(110, 100, 86)
		for i, g in ipairs(view.groups) do
			groupRow(g, i)
		end
	end

	claimAll.MouseButton1Click:Connect(function()
		local state = deps.getLatestState and deps.getLatestState() or nil
		if state and state.collectionRewards and (state.collectionRewards.claimable or 0) > 0 then
			deps.playClickSfx()
			pcall(function() require(script.Parent.Cue).play("reward_claim") end)
			ClaimRemote:FireServer("all")
		end
	end)

	require(script.Parent.PanelTabs).attach(backdrop, "collectionRewards", deps.playClickSfx, panel) -- shared tab strip + Back
	OverlayManager.register("collectionRewards", function()
		deps.popOut(backdrop, panel)
	end)
	local function openThisPanel()
		deps.playClickSfx()
		OverlayManager.closeAllExcept("collectionRewards")
		refresh()
		deps.popIn(backdrop, panel)
	end
	OverlayManager.registerOpener("collectionRewards", openThisPanel)
	deps.openButton.MouseButton1Click:Connect(openThisPanel)
	require(script.Parent.CloseX).retire(closeButton)
	require(script.Parent.CloseX).attach(panel, function()
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

return CollectionRewardsPanel
