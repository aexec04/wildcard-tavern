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
	local PARCH = Color3.fromRGB(222, 198, 150)
	local GREEN = Color3.fromRGB(86, 140, 80)

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
	backdrop.Name = "CollectionRewardsBackdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	backdrop.BackgroundTransparency = 0.4
	backdrop.Visible = false
	backdrop.ZIndex = 40
	backdrop.Parent = deps.screenGui

	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Size = UDim2.fromScale(0.8, 0.88)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.BackgroundColor3 = Color3.fromRGB(40, 30, 22)
	panel.ZIndex = 41
	panel.Parent = backdrop
	deps.polishPanel(panel, 16, "parchment")
	deps.addSoftShadow(panel, 18)

	label(panel, { Size = UDim2.new(1, 0, 0, 30), Position = UDim2.fromOffset(0, 6), TextSize = 22, Text = "Collection Rewards" })

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
	scroll.Position = UDim2.fromOffset(15, 48)
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

	local function chip(row, group, m, order)
		local c = Instance.new("TextButton")
		c.Name = "Milestone_" .. m.pct
		c.LayoutOrder = order
		c.Size = UDim2.fromOffset(118, 104)
		c.AutoButtonColor = false
		c.Text = ""
		c.BackgroundColor3 = m.claimed and Color3.fromRGB(176, 190, 140) or PARCH
		c.BorderSizePixel = 0
		c.ZIndex = 42
		c.Parent = row
		deps.roundCorner(c, 10)
		local stroke = Instance.new("UIStroke")
		stroke.Color = (m.reached and not m.claimed) and GOLD or INK
		stroke.Thickness = (m.reached and not m.claimed) and 3 or 1.5
		stroke.Parent = c
		label(c, { Size = UDim2.new(1, 0, 0, 20), Position = UDim2.fromOffset(0, 3), TextSize = 16, Text = m.pct .. "%" })
		local well = Instance.new("Frame")
		well.Size = UDim2.fromOffset(46, 46)
		well.Position = UDim2.fromOffset(36, 26)
		well.BackgroundColor3 = WOOD
		well.BorderSizePixel = 0
		well.ZIndex = 43
		well.Parent = c
		deps.roundCorner(well, 8)
		local category, key, emoji = rewardArt(m.reward)
		local glyph = label(well, { Size = UDim2.fromScale(1, 1), TextSize = 24, TextColor3 = CREAM, Text = emoji, ZIndex = 44 })
		if category then
			pcall(ArtIcon.apply, well, category, key, glyph, { cornerRadius = 8, zIndex = 45, dim = not m.reached })
		end
		if not m.reached then glyph.TextTransparency = 0.35 end -- dimmed, never black
		label(c, { Size = UDim2.new(1, -6, 0, 32), Position = UDim2.fromOffset(3, 72), TextSize = 14, TextWrapped = true, Font = Enum.Font.GothamMedium, Text = m.text or "" })
		if m.claimed then
			label(c, { Size = UDim2.fromOffset(28, 28), Position = UDim2.new(1, -30, 0, 0), TextSize = 20, TextColor3 = GREEN, Text = "✔", ZIndex = 47 })
		end
		c.MouseButton1Click:Connect(function()
			if m.reached and not m.claimed then
				deps.playClickSfx()
				ClaimRemote:FireServer(group, m.pct)
			end
		end)
		deps.addTooltip(c, (m.text or "") .. (m.claimed and " (claimed)" or m.reached and " (tap to claim)" or (" at " .. m.pct .. " percent")))
	end

	local function groupRow(g, order)
		local row = Instance.new("Frame")
		row.Name = "Group_" .. g.id
		row.LayoutOrder = order
		row.Size = UDim2.new(1, 0, 0, 120)
		row.BackgroundColor3 = Color3.fromRGB(205, 180, 134)
		row.BorderSizePixel = 0
		row.ZIndex = 42
		row.Parent = scroll
		deps.roundCorner(row, 12)
		-- progress ring: a round badge, its ring is gold once any milestone is reached
		local ring = Instance.new("Frame")
		ring.Size = UDim2.fromOffset(84, 84)
		ring.Position = UDim2.fromOffset(12, 18)
		ring.BackgroundColor3 = WOOD
		ring.BorderSizePixel = 0
		ring.ZIndex = 43
		ring.Parent = row
		deps.roundCorner(ring, 42)
		local ringStroke = Instance.new("UIStroke")
		ringStroke.Color = g.percent >= 100 and Color3.fromRGB(255, 226, 140) or GOLD
		ringStroke.Thickness = 2 + math.floor(g.percent / 34)
		ringStroke.Parent = ring
		label(ring, { Size = UDim2.new(1, 0, 0, 20), Position = UDim2.fromOffset(0, 12), TextSize = 22, Text = g.icon, TextColor3 = CREAM, ZIndex = 44 })
		label(ring, { Size = UDim2.new(1, 0, 0, 26), Position = UDim2.fromOffset(0, 40), TextSize = 20, Text = g.percent .. "%", TextColor3 = GOLD, ZIndex = 44 })
		label(row, { Size = UDim2.fromOffset(150, 20), Position = UDim2.fromOffset(108, 8), TextSize = 17, TextXAlignment = Enum.TextXAlignment.Left, Text = g.name })
		label(row, { Size = UDim2.fromOffset(150, 20), Position = UDim2.fromOffset(108, 30), Font = Enum.Font.Gotham, TextXAlignment = Enum.TextXAlignment.Left,
			Text = g.found .. " of " .. g.total })
		local chips = Instance.new("Frame")
		chips.Size = UDim2.new(1, -270, 1, -12)
		chips.Position = UDim2.fromOffset(262, 8)
		chips.BackgroundTransparency = 1
		chips.ZIndex = 42
		chips.Parent = row
		local chipLayout = Instance.new("UIListLayout")
		chipLayout.FillDirection = Enum.FillDirection.Horizontal
		chipLayout.SortOrder = Enum.SortOrder.LayoutOrder
		chipLayout.Padding = UDim.new(0, 8)
		chipLayout.Parent = chips
		for i, m in ipairs(g.milestones) do
			chip(chips, g.id, m, i)
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
			ClaimRemote:FireServer("all")
		end
	end)

	OverlayManager.register("collectionRewards", function()
		deps.popOut(backdrop, panel)
	end)
	deps.openButton.MouseButton1Click:Connect(function()
		deps.playClickSfx()
		OverlayManager.closeAllExcept("collectionRewards")
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

return CollectionRewardsPanel
