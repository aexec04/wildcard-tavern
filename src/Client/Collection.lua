--[[
	Client/Collection.lua
	FEATURE 11: a grid of every Patron and Theme in the game -- owned ones
	shown in full, locked ones silhouetted with a "?". Reachable from the
	in-game "📔" corner button.

	PERSISTENT SAVE (Phase 10): Patron rows used to only reflect the
	CURRENT run's ownedPatrons, which reset every run -- finding a rare
	Patron, then starting fresh, made it look undiscovered again (hence the
	old title, "Collection -- this run"). They now read
	`state.discoveredPatronIds`, a permanent set maintained server-side
	(Shared/Engine/PlayerProfile.lua) across every run this player has ever
	played. Theme rows still read `state.ownedThemeIds` -- same field name
	as before, but that's now ALSO effectively permanent (RunState.new
	seeds it from the same saved profile -- see Server/init.server.lua's
	startNewSession), so no client-side change was needed there.

	Extracted out of init.client.lua as part of splitting the client script
	into smaller, per-feature files. Fully self-contained -- nothing outside
	this module needs anything it builds, so it returns an empty table.

	deps fields:
		screenGui        -- ScreenGui, the panel's ultimate parent (via backdrop)
		polishPanel       -- function(instance, radius)
		polishButton      -- function(instance, radius)
		roundCorner       -- function(instance, radius)
		addSoftShadow     -- function(instance, radius)
		playClickSfx      -- function(volume?)
		collectionButton  -- TextButton, the in-game "📔" corner button
		Patrons           -- the Shared/Engine/Patrons module
		Themes            -- the Shared/Engine/Themes module
		getLatestState    -- function() -> latest state table or nil (live getter)
		popIn             -- function(backdrop, content, opts?)
		popOut            -- function(backdrop, content, opts?, onHidden?)
		addButtonHoverScale -- function(button, opts?)

	Returns: {}

	POLISH PASS (Batch 3): popIn/popOut replace the old bare
	Visible = true/false cut; the Close button gets addButtonHoverScale.
	Deliberately NOT using revealStagger on the row list itself -- this
	panel can hold 35+ rows (31 Patrons + every Theme) once fully unlocked,
	and a per-row cascade at revealStagger's usual pacing would take
	several seconds to finish, reading as sluggish rather than juicy for a
	list this long. The modal pop-in is enough of a "this just opened" cue
	on its own here.
]]

return function(deps)
	local screenGui = deps.screenGui
	local polishPanel = deps.polishPanel
	local polishButton = deps.polishButton
	local roundCorner = deps.roundCorner
	local addSoftShadow = deps.addSoftShadow
	local playClickSfx = deps.playClickSfx
	local collectionButton = deps.collectionButton
	local Patrons = deps.Patrons
	local Themes = deps.Themes
	local getLatestState = deps.getLatestState
	local popIn = deps.popIn
	local popOut = deps.popOut
	local addButtonHoverScale = deps.addButtonHoverScale

	local collectionBackdrop = Instance.new("Frame")
	collectionBackdrop.Name = "CollectionBackdrop"
	collectionBackdrop.Size = UDim2.fromScale(1, 1)
	collectionBackdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	collectionBackdrop.BackgroundTransparency = 0.4
	collectionBackdrop.Visible = false
	collectionBackdrop.ZIndex = 20
	collectionBackdrop.Parent = screenGui

	local collectionPanel = Instance.new("Frame")
	collectionPanel.Size = UDim2.fromScale(0.6, 0.7)
	collectionPanel.Position = UDim2.fromScale(0.2, 0.15)
	collectionPanel.BackgroundColor3 = Color3.fromRGB(40, 30, 22)
	collectionPanel.ZIndex = 21
	collectionPanel.Parent = collectionBackdrop
	polishPanel(collectionPanel, 16)
	addSoftShadow(collectionPanel, 18)

	local collectionTitle = Instance.new("TextLabel")
	collectionTitle.Size = UDim2.new(1, 0, 0, 26)
	collectionTitle.Position = UDim2.new(0, 0, 0, 0)
	collectionTitle.BackgroundTransparency = 1
	collectionTitle.Font = Enum.Font.GothamBold
	collectionTitle.TextSize = 22
	collectionTitle.TextColor3 = Color3.fromRGB(250, 240, 220)
	collectionTitle.Text = "Collection"
	collectionTitle.ZIndex = 21
	collectionTitle.Parent = collectionPanel

	-- PERSISTENT SAVE (Phase 10): a small permanent-stats line under the
	-- title -- state.profileStats (Server/init.server.lua's serializeState)
	-- is 3 small counters from Shared/Engine/PlayerProfile.lua, refreshed
	-- the same time as everything else in refreshCollection below.
	local collectionStatsLabel = Instance.new("TextLabel")
	collectionStatsLabel.Size = UDim2.new(1, 0, 0, 18)
	collectionStatsLabel.Position = UDim2.new(0, 0, 0, 26)
	collectionStatsLabel.BackgroundTransparency = 1
	collectionStatsLabel.Font = Enum.Font.Gotham
	collectionStatsLabel.TextSize = 13
	collectionStatsLabel.TextColor3 = Color3.fromRGB(200, 185, 165)
	collectionStatsLabel.Text = ""
	collectionStatsLabel.ZIndex = 21
	collectionStatsLabel.Parent = collectionPanel

	local collectionScroll = Instance.new("ScrollingFrame")
	collectionScroll.Size = UDim2.new(1, -30, 1, -110)
	collectionScroll.Position = UDim2.new(0, 15, 0, 45)
	collectionScroll.BackgroundTransparency = 1
	collectionScroll.BorderSizePixel = 0
	collectionScroll.ScrollBarThickness = 8
	collectionScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	collectionScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	collectionScroll.ZIndex = 21
	collectionScroll.Parent = collectionPanel

	local collectionLayout = Instance.new("UIListLayout")
	collectionLayout.Padding = UDim.new(0, 10)
	collectionLayout.Parent = collectionScroll

	local collectionCloseButton = Instance.new("TextButton")
	collectionCloseButton.Size = UDim2.new(0, 140, 0, 40)
	collectionCloseButton.Position = UDim2.new(0.5, -70, 1, -50)
	collectionCloseButton.Font = Enum.Font.GothamBold
	collectionCloseButton.TextSize = 16
	collectionCloseButton.Text = "Close"
	collectionCloseButton.BackgroundColor3 = Color3.fromRGB(90, 60, 30)
	collectionCloseButton.TextColor3 = Color3.fromRGB(250, 240, 220)
	collectionCloseButton.ZIndex = 21
	collectionCloseButton.Parent = collectionPanel
	polishButton(collectionCloseButton, 12)
	addButtonHoverScale(collectionCloseButton)

	collectionCloseButton.MouseButton1Click:Connect(function()
		playClickSfx()
		popOut(collectionBackdrop, collectionPanel)
	end)

	local function makeCollectionSectionHeader(text, order)
		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(1, 0, 0, 22)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamBold
		label.TextSize = 16
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextColor3 = Color3.fromRGB(255, 214, 130)
		label.Text = text
		label.LayoutOrder = order
		label.ZIndex = 21
		label.Parent = collectionScroll
		return label
	end

	local function makeCollectionRow(order, name, description, isOwned, swatchColor, icon)
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, 0, 0, 50)
		row.BackgroundColor3 = isOwned and Color3.fromRGB(60, 50, 32) or Color3.fromRGB(45, 40, 38)
		row.LayoutOrder = order
		row.ZIndex = 21
		row.Parent = collectionScroll
		polishPanel(row, 10)

		local swatch = Instance.new("Frame")
		swatch.Size = UDim2.new(0, 30, 0, 30)
		swatch.Position = UDim2.new(0, 10, 0.5, -15)
		swatch.BackgroundColor3 = isOwned and (swatchColor or Color3.fromRGB(200, 170, 100)) or Color3.fromRGB(70, 65, 60)
		swatch.ZIndex = 21
		swatch.Parent = row
		roundCorner(swatch, 8)

		local swatchLabel = Instance.new("TextLabel")
		swatchLabel.Size = UDim2.fromScale(1, 1)
		swatchLabel.BackgroundTransparency = 1
		swatchLabel.Font = Enum.Font.GothamBold
		swatchLabel.TextSize = 16
		swatchLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		swatchLabel.Text = isOwned and (icon or "") or "?"
		swatchLabel.ZIndex = 21
		swatchLabel.Parent = swatch

		local nameLabel = Instance.new("TextLabel")
		nameLabel.Size = UDim2.new(1, -60, 0, 22)
		nameLabel.Position = UDim2.new(0, 50, 0, 4)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Font = Enum.Font.GothamBold
		nameLabel.TextSize = 15
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.TextColor3 = isOwned and Color3.fromRGB(250, 240, 220) or Color3.fromRGB(140, 135, 130)
		nameLabel.Text = isOwned and name or "???"
		nameLabel.ZIndex = 21
		nameLabel.Parent = row

		local descLabel = Instance.new("TextLabel")
		descLabel.Size = UDim2.new(1, -60, 0, 20)
		descLabel.Position = UDim2.new(0, 50, 0, 24)
		descLabel.BackgroundTransparency = 1
		descLabel.Font = Enum.Font.Gotham
		descLabel.TextSize = 12
		descLabel.TextWrapped = true
		descLabel.TextXAlignment = Enum.TextXAlignment.Left
		descLabel.TextColor3 = isOwned and Color3.fromRGB(210, 195, 175) or Color3.fromRGB(120, 115, 110)
		descLabel.Text = isOwned and description or "Not discovered yet."
		descLabel.ZIndex = 21
		descLabel.Parent = row
	end

	local function refreshCollection()
		for _, child in ipairs(collectionScroll:GetChildren()) do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end

		local latestState = getLatestState()
		local ownedPatronIds = {}
		local ownedThemeIds = {}
		if latestState then
			-- PERSISTENT SAVE (Phase 10): discoveredPatronIds is the
			-- permanent, cross-run set -- see this file's header comment.
			for _, id in ipairs(latestState.discoveredPatronIds or {}) do
				ownedPatronIds[id] = true
			end
			for _, id in ipairs(latestState.ownedThemeIds or {}) do
				ownedThemeIds[id] = true
			end
		end

		local ownedPatronCount = 0
		for _ in pairs(ownedPatronIds) do
			ownedPatronCount = ownedPatronCount + 1
		end
		local ownedThemeCount = 0
		for _ in pairs(ownedThemeIds) do
			ownedThemeCount = ownedThemeCount + 1
		end

		local stats = latestState and latestState.profileStats
		if stats then
			collectionStatsLabel.Text = string.format(
				"Runs played: %d  |  Runs won: %d  |  Best Night reached: %d",
				stats.runsStarted, stats.runsWon, stats.bestNightReached
			)
		else
			collectionStatsLabel.Text = ""
		end

		makeCollectionSectionHeader(string.format("Patrons -- %d / %d found", ownedPatronCount, #Patrons.Definitions), 1)
		for i, patron in ipairs(Patrons.Definitions) do
			makeCollectionRow(1 + i, patron.name, patron.description, ownedPatronIds[patron.id] == true, Color3.fromRGB(200, 170, 100), patron.icon)
		end

		makeCollectionSectionHeader(string.format("Themes -- %d / %d found", ownedThemeCount, #Themes.Definitions), 100)
		for i, theme in ipairs(Themes.Definitions) do
			makeCollectionRow(100 + i, theme.name, theme.description, ownedThemeIds[theme.id] == true, theme.colors.accent)
		end
	end

	collectionButton.MouseButton1Click:Connect(function()
		playClickSfx()
		refreshCollection()
		popIn(collectionBackdrop, collectionPanel)
	end)

	return {}
end
