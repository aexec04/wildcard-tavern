--[[
	Client/Themes.lua
	The Themes (cosmetics) overlay -- buy/equip table+card color palettes.
	Purely visual, no gameplay effect, and buyable/equippable any time (not
	gated to the shop phase like Patrons are).

	Extracted out of init.client.lua as part of splitting the client script
	into smaller, per-feature files. Unlike HowToPlay.lua this one DOES need
	to hand things back: render() checks themesBackdrop.Visible to decide
	whether to refresh the list on every state update (so the panel stays
	accurate if it's open across a purchase), and calls refreshThemesList()
	when it is.

	deps fields:
		screenGui         -- ScreenGui, the panel's ultimate parent (via backdrop)
		polishPanel        -- function(instance, radius)
		polishButton       -- function(instance, radius)
		roundCorner        -- function(instance, radius)
		addSoftShadow      -- function(instance, radius)
		playClickSfx       -- function(volume?)
		playSfx            -- function(soundId, volume?, maxLength?)
		SOUND_IDS          -- table, for SOUND_IDS.buyPatron
		Themes             -- the Shared/Engine/Themes module
		BuyThemeRemote     -- RemoteEvent
		EquipThemeRemote   -- RemoteEvent
		showWarning        -- function(text)
		themesButton       -- TextButton, the in-game "🎨" corner button
		getLatestState     -- function() -> latest state table or nil (live
		                       getter, since latestState is reassigned each
		                       render() call, not mutated)

	Returns:
		{
			themesBackdrop = Frame,
			refreshThemesList = function(),
		}
]]

return function(deps)
	local screenGui = deps.screenGui
	local polishPanel = deps.polishPanel
	local polishButton = deps.polishButton
	local roundCorner = deps.roundCorner
	local addSoftShadow = deps.addSoftShadow
	local playClickSfx = deps.playClickSfx
	local playSfx = deps.playSfx
	local SOUND_IDS = deps.SOUND_IDS
	local Themes = deps.Themes
	local BuyThemeRemote = deps.BuyThemeRemote
	local EquipThemeRemote = deps.EquipThemeRemote
	local showWarning = deps.showWarning
	local themesButton = deps.themesButton
	local getLatestState = deps.getLatestState

	-- Purely visual -- spend Tips on table/card color palettes. No gameplay
	-- effect. Buyable/equippable any time, not just during the shop phase.

	local themesBackdrop = Instance.new("Frame")
	themesBackdrop.Name = "ThemesBackdrop"
	themesBackdrop.Size = UDim2.fromScale(1, 1)
	themesBackdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	themesBackdrop.BackgroundTransparency = 0.4
	themesBackdrop.Visible = false
	themesBackdrop.ZIndex = 20
	themesBackdrop.Parent = screenGui

	local themesPanel = Instance.new("Frame")
	themesPanel.Size = UDim2.fromScale(0.55, 0.6)
	themesPanel.Position = UDim2.fromScale(0.225, 0.2)
	themesPanel.BackgroundColor3 = Color3.fromRGB(40, 30, 22)
	themesPanel.ZIndex = 21
	themesPanel.Parent = themesBackdrop
	polishPanel(themesPanel, 16)
	addSoftShadow(themesPanel, 18)

	local themesTitle = Instance.new("TextLabel")
	themesTitle.Size = UDim2.new(1, 0, 0, 40)
	themesTitle.BackgroundTransparency = 1
	themesTitle.Font = Enum.Font.GothamBold
	themesTitle.TextSize = 22
	themesTitle.TextColor3 = Color3.fromRGB(250, 240, 220)
	themesTitle.Text = "Themes -- cosmetic only, spend Tips"
	themesTitle.ZIndex = 21
	themesTitle.Parent = themesPanel

	local themesListFrame = Instance.new("Frame")
	themesListFrame.Size = UDim2.new(1, -20, 1, -100)
	themesListFrame.Position = UDim2.new(0, 10, 0, 45)
	themesListFrame.BackgroundTransparency = 1
	themesListFrame.ZIndex = 21
	themesListFrame.Parent = themesPanel

	local themesListLayout = Instance.new("UIListLayout")
	themesListLayout.Padding = UDim.new(0, 8)
	themesListLayout.Parent = themesListFrame

	local themesCloseButton = Instance.new("TextButton")
	themesCloseButton.Size = UDim2.new(0, 140, 0, 40)
	themesCloseButton.Position = UDim2.new(0.5, -70, 1, -50)
	themesCloseButton.Font = Enum.Font.GothamBold
	themesCloseButton.TextSize = 16
	themesCloseButton.Text = "Close"
	themesCloseButton.BackgroundColor3 = Color3.fromRGB(90, 60, 30)
	themesCloseButton.TextColor3 = Color3.fromRGB(250, 240, 220)
	themesCloseButton.ZIndex = 21
	themesCloseButton.Parent = themesPanel
	polishButton(themesCloseButton, 10)

	themesCloseButton.MouseButton1Click:Connect(function()
		playClickSfx()
		themesBackdrop.Visible = false
	end)

	local function refreshThemesList()
		for _, child in ipairs(themesListFrame:GetChildren()) do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end

		local latestState = getLatestState()
		local ownedSet = {}
		local equippedId = Themes.DefaultThemeId
		if latestState then
			for _, id in ipairs(latestState.ownedThemeIds or {}) do
				ownedSet[id] = true
			end
			equippedId = latestState.equippedTheme or equippedId
		end

		for _, theme in ipairs(Themes.Definitions) do
			local row = Instance.new("Frame")
			row.Size = UDim2.new(1, 0, 0, 50)
			row.BackgroundColor3 = Color3.fromRGB(60, 45, 32)
			row.Parent = themesListFrame
			polishPanel(row, 10)

			local swatch = Instance.new("Frame")
			swatch.Size = UDim2.new(0, 30, 0, 30)
			swatch.Position = UDim2.new(0, 10, 0.5, -15)
			swatch.BackgroundColor3 = theme.colors.accent
			swatch.Parent = row
			roundCorner(swatch, 6)

			local label = Instance.new("TextLabel")
			label.Size = UDim2.new(1, -220, 1, 0)
			label.Position = UDim2.new(0, 50, 0, 0)
			label.BackgroundTransparency = 1
			label.Font = Enum.Font.Gotham
			label.TextSize = 15
			label.TextXAlignment = Enum.TextXAlignment.Left
			label.TextColor3 = Color3.fromRGB(250, 240, 220)
			label.Text = string.format("%s -- %s", theme.name, theme.description)
			label.Parent = row

			local actionButton = Instance.new("TextButton")
			actionButton.Size = UDim2.new(0, 130, 0, 36)
			actionButton.Position = UDim2.new(1, -140, 0.5, -18)
			actionButton.Font = Enum.Font.GothamBold
			actionButton.TextSize = 14
			actionButton.BackgroundColor3 = Color3.fromRGB(90, 60, 30)
			actionButton.TextColor3 = Color3.fromRGB(250, 240, 220)
			actionButton.Parent = row
			polishButton(actionButton, 8)

			if theme.id == equippedId then
				actionButton.Text = "Equipped"
				actionButton.AutoButtonColor = false
				actionButton.BackgroundColor3 = Color3.fromRGB(70, 90, 55)
			elseif ownedSet[theme.id] then
				actionButton.Text = "Equip"
				actionButton.MouseButton1Click:Connect(function()
					playClickSfx()
					EquipThemeRemote:FireServer(theme.id)
				end)
			else
				actionButton.Text = string.format("Buy (%d)", theme.price)
				actionButton.MouseButton1Click:Connect(function()
					local latest = getLatestState()
					if not latest or latest.tips < theme.price then
						showWarning("Not enough tips for that.")
						playClickSfx()
						return
					end
					playSfx(SOUND_IDS.buyPatron)
					BuyThemeRemote:FireServer(theme.id)
				end)
			end
		end
	end

	themesButton.MouseButton1Click:Connect(function()
		playClickSfx()
		refreshThemesList()
		themesBackdrop.Visible = true
	end)

	return {
		themesBackdrop = themesBackdrop,
		refreshThemesList = refreshThemesList,
	}
end
