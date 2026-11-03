--[[
	Client/Settings.lua
	The "⚙" corner button's panel (wood variant), in four sections:
		Audio    -- Custom Jukebox (Client/JukeboxSection.lua, Game Pass gated)
		Display  -- Animation speed (Normal/Fast), Reduce screen shake,
		            Colorblind suits
		Gameplay -- Confirm before discard
		Account  -- How to Play, Leaderboards, Main Menu
	Music/SFX volume and mute are in the volume popup (Client/VolumePanel.lua).
	Toggle values live in Client/ClientSettings.lua (saved to the profile).

	How to Play / Leaderboards only close this panel; HowToPlay.lua and
	DailyLeaderboard.lua wire the "open" on the returned buttons. Main Menu
	hides root and shows menuFrame (the reverse of the menu's Play button).

	deps fields:
		screenGui, polishPanel, polishButton, addSoftShadow, playClickSfx,
		roundCorner, popIn, popOut, addButtonHoverScale
		settingsButton -- TextButton, the "⚙" corner button
		menuFrame, root -- for Main Menu
		jukeboxDeps    -- table, passed to JukeboxSection.lua (see its header);
		                  parent/layoutOrder/isVisible/polishButton/etc are filled in here

	Returns:
		{
			settingsBackdrop = Frame,
			settingsHowToPlayButton = TextButton,
			settingsLeaderboardButton = TextButton,
			refreshJukeboxSection = function(), -- call from render() while open
		}
]]

local ClientSettings = require(script.Parent.ClientSettings)
local OverlayManager = require(script.Parent.OverlayManager)
local ArtAssetsModule = require(script.Parent.ArtAssets)

local TEXT = Color3.fromRGB(250, 240, 220)
local HEADER = Color3.fromRGB(255, 214, 130)
local SUBTLE = Color3.fromRGB(190, 175, 155)
local BUTTON = Color3.fromRGB(70, 45, 25)
local ON = Color3.fromRGB(70, 110, 60)

return function(deps)
	local polishButton = deps.polishButton
	local playClickSfx = deps.playClickSfx
	local popIn = deps.popIn
	local popOut = deps.popOut
	local addButtonHoverScale = deps.addButtonHoverScale
	local roundCorner = deps.roundCorner

	local settingsBackdrop = Instance.new("Frame")
	settingsBackdrop.Name = "SettingsBackdrop"
	settingsBackdrop.Size = UDim2.fromScale(1, 1)
	settingsBackdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	settingsBackdrop.BackgroundTransparency = 0.4
	settingsBackdrop.Visible = false
	settingsBackdrop.ZIndex = 20
	settingsBackdrop.Parent = deps.screenGui

	local settingsPanel = Instance.new("Frame")
	settingsPanel.Size = UDim2.fromScale(0.5, 0.8)
	settingsPanel.Position = UDim2.fromScale(0.25, 0.1)
	settingsPanel.BackgroundColor3 = Color3.fromRGB(40, 30, 22)
	settingsPanel.ZIndex = 21
	settingsPanel.Parent = settingsBackdrop
	deps.polishPanel(settingsPanel, 16, "wood")
	deps.addSoftShadow(settingsPanel, 18)

	local settingsTitle = Instance.new("TextLabel")
	settingsTitle.Size = UDim2.new(1, 0, 0, 40)
	settingsTitle.BackgroundTransparency = 1
	settingsTitle.Font = Enum.Font.GothamBold
	settingsTitle.TextSize = 22
	settingsTitle.TextColor3 = TEXT
	settingsTitle.Text = "Settings"
	settingsTitle.ZIndex = 21
	settingsTitle.Parent = settingsPanel

	local scroll = Instance.new("ScrollingFrame")
	scroll.Size = UDim2.new(1, -40, 1, -110)
	scroll.Position = UDim2.new(0, 20, 0, 48)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 8
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.ZIndex = 21
	scroll.Parent = settingsPanel

	local scrollLayout = Instance.new("UIListLayout")
	scrollLayout.SortOrder = Enum.SortOrder.LayoutOrder
	scrollLayout.Padding = UDim.new(0, 8)
	scrollLayout.Parent = scroll

	local nextOrder = 0
	local function order()
		nextOrder = nextOrder + 1
		return nextOrder
	end

	local function makeHeader(text)
		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(1, 0, 0, 30)
		label.LayoutOrder = order()
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamBold
		label.TextSize = 18
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextYAlignment = Enum.TextYAlignment.Bottom
		label.TextColor3 = HEADER
		label.Text = text
		label.ZIndex = 21
		label.Parent = scroll
	end

	-- One row: label + description on the left, a value button on the
	-- right. `choices` is a list of { value, text }; clicking cycles them.
	local function makeChoiceRow(key, labelText, description, choices)
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, 0, 0, 46)
		row.LayoutOrder = order()
		row.BackgroundTransparency = 1
		row.ZIndex = 21
		row.Parent = scroll

		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(1, -130, 0, 22)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamBold
		label.TextSize = 15
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextColor3 = TEXT
		label.Text = labelText
		label.ZIndex = 21
		label.Parent = row

		local desc = Instance.new("TextLabel")
		desc.Size = UDim2.new(1, -130, 0, 20)
		desc.Position = UDim2.new(0, 0, 0, 22)
		desc.BackgroundTransparency = 1
		desc.Font = Enum.Font.Gotham
		desc.TextSize = 12
		desc.TextWrapped = true
		desc.TextXAlignment = Enum.TextXAlignment.Left
		desc.TextColor3 = SUBTLE
		desc.Text = description
		desc.ZIndex = 21
		desc.Parent = row

		local button = Instance.new("TextButton")
		button.Size = UDim2.new(0, 110, 0, 34)
		button.AnchorPoint = Vector2.new(1, 0.5)
		button.Position = UDim2.new(1, -4, 0.5, 0)
		button.Font = Enum.Font.GothamBold
		button.TextSize = 14
		button.TextColor3 = TEXT
		button.ZIndex = 21
		button.Parent = row
		polishButton(button, 8)
		addButtonHoverScale(button)

		local function refresh()
			local current = ClientSettings.get(key)
			for i, choice in ipairs(choices) do
				if choice[1] == current then
					button.Text = choice[2]
					button.BackgroundColor3 = (i == 1) and BUTTON or ON
					return
				end
			end
		end

		button.MouseButton1Click:Connect(function()
			playClickSfx()
			local current = ClientSettings.get(key)
			local nextIndex = 1
			for i, choice in ipairs(choices) do
				if choice[1] == current then
					nextIndex = (i % #choices) + 1
				end
			end
			ClientSettings.set(key, choices[nextIndex][1])
		end)

		ClientSettings.onChanged(function(changedKey)
			if changedKey == key then
				refresh()
			end
		end)
		refresh()
	end

	local OFF_ON = { { false, "Off" }, { true, "On" } }

	-- ===== Audio =====
	makeHeader("Audio")
	local jukeboxDeps = deps.jukeboxDeps or {}
	jukeboxDeps.parent = scroll
	jukeboxDeps.layoutOrder = order()
	jukeboxDeps.isVisible = function()
		return settingsBackdrop.Visible
	end
	jukeboxDeps.polishButton = polishButton
	jukeboxDeps.addButtonHoverScale = addButtonHoverScale
	jukeboxDeps.playClickSfx = playClickSfx
	local jukebox = require(script.Parent.JukeboxSection)(jukeboxDeps)

	-- ===== Display =====
	makeHeader("Display")
	makeChoiceRow("animSpeed", "Animation Speed", "How fast hands score. Fast Forward pass owners get extra speed.", {
		{ "normal", "Normal" },
		{ "fast", "Fast" },
	})
	makeChoiceRow("reduceShake", "Reduce Screen Shake", "Turns off the screen shake on big hits.", OFF_ON)
	makeChoiceRow("colorblindSuits", "Colorblind Suits", "Gives each suit its own color and a bolder symbol.", OFF_ON)

	-- ===== Gameplay =====
	makeHeader("Gameplay")
	makeChoiceRow("confirmDiscard", "Confirm Before Discard", "Asks before your selected cards are discarded.", OFF_ON)

	-- ===== Account =====
	makeHeader("Account")
	local accountRow = Instance.new("Frame")
	accountRow.Size = UDim2.new(1, 0, 0, 44)
	accountRow.LayoutOrder = order()
	accountRow.BackgroundTransparency = 1
	accountRow.ZIndex = 21
	accountRow.Parent = scroll

	local accountLayout = Instance.new("UIListLayout")
	accountLayout.FillDirection = Enum.FillDirection.Horizontal
	accountLayout.SortOrder = Enum.SortOrder.LayoutOrder
	accountLayout.Padding = UDim.new(0, 10)
	accountLayout.Parent = accountRow

	local function makeAccountButton(text, layoutOrder, iconImage)
		local button = Instance.new("TextButton")
		button.Size = UDim2.new(1 / 3, -7, 0, 40)
		button.LayoutOrder = layoutOrder
		button.Font = Enum.Font.GothamBold
		button.TextSize = 15
		button.Text = text
		button.BackgroundColor3 = BUTTON
		button.TextColor3 = TEXT
		button.ZIndex = 21
		button.Parent = accountRow
		polishButton(button, 12)
		addButtonHoverScale(button)
		-- Icon badge on the left edge, parented to the button.
		if iconImage and iconImage ~= "rbxassetid://0" then
			local icon = Instance.new("ImageLabel")
			icon.Size = UDim2.new(0, 22, 0, 22)
			icon.AnchorPoint = Vector2.new(0, 0.5)
			icon.Position = UDim2.new(0, 10, 0.5, 0)
			icon.BackgroundTransparency = 1
			icon.Image = iconImage
			icon.ScaleType = Enum.ScaleType.Crop
			icon.ZIndex = 22
			icon.Parent = button
			roundCorner(icon, 11)
		end
		return button
	end

	local settingsHowToPlayButton = makeAccountButton("How to Play", 1, ArtAssetsModule.cornerIconHowToPlay)
	local settingsLeaderboardButton = makeAccountButton("Leaderboards", 2, ArtAssetsModule.cornerIconLeaderboards)
	local settingsMainMenuButton = makeAccountButton("Main Menu", 3, nil)

	local settingsCloseButton = Instance.new("TextButton")
	settingsCloseButton.Size = UDim2.new(0, 140, 0, 40)
	settingsCloseButton.Position = UDim2.new(0.5, -70, 1, -54)
	settingsCloseButton.Font = Enum.Font.GothamBold
	settingsCloseButton.TextSize = 16
	settingsCloseButton.Text = "Close"
	settingsCloseButton.BackgroundColor3 = Color3.fromRGB(90, 60, 30)
	settingsCloseButton.TextColor3 = TEXT
	settingsCloseButton.ZIndex = 21
	settingsCloseButton.Parent = settingsPanel
	polishButton(settingsCloseButton, 12)
	addButtonHoverScale(settingsCloseButton)

	settingsCloseButton.MouseButton1Click:Connect(function()
		playClickSfx()
		popOut(settingsBackdrop, settingsPanel)
	end)

	settingsMainMenuButton.MouseButton1Click:Connect(function()
		playClickSfx()
		popOut(settingsBackdrop, settingsPanel, nil, function()
			deps.root.Visible = false
			deps.menuFrame.Visible = true
		end)
	end)

	for _, button in ipairs({ settingsHowToPlayButton, settingsLeaderboardButton }) do
		button.MouseButton1Click:Connect(function()
			playClickSfx()
			popOut(settingsBackdrop, settingsPanel)
		end)
	end

	OverlayManager.register("settings", function()
		popOut(settingsBackdrop, settingsPanel)
	end)

	deps.settingsButton.MouseButton1Click:Connect(function()
		playClickSfx()
		OverlayManager.closeAllExcept("settings")
		jukebox.refreshJukeboxSection()
		popIn(settingsBackdrop, settingsPanel)
	end)

	return {
		settingsBackdrop = settingsBackdrop,
		settingsHowToPlayButton = settingsHowToPlayButton,
		settingsLeaderboardButton = settingsLeaderboardButton,
		refreshJukeboxSection = jukebox.refreshJukeboxSection,
	}
end
