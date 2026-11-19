--[[
	Client/Settings.lua
	The "⚙" corner button's panel (wood variant), in three sections:
		Display  -- Animation speed (Normal/Fast), Reduce screen shake,
		            Colorblind suits
		Gameplay -- Confirm before discard
		Account  -- How to Play, Leaderboards, Main Menu, Restart Run (danger button, in a run only)
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

	Returns:
		{
			settingsBackdrop = Frame,
			settingsHowToPlayButton = TextButton,
			settingsLeaderboardButton = TextButton,
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
	require(script.Parent.MenuTitleHider).bind(deps.screenGui, settingsBackdrop)

	local settingsPanel = Instance.new("Frame")
	settingsPanel.Size = UDim2.fromScale(0.5, 0.8)
	settingsPanel.Position = UDim2.fromScale(0.25, 0.1)
	settingsPanel.BackgroundColor3 = Color3.fromRGB(40, 30, 22)
	settingsPanel.ZIndex = 21
	settingsPanel.Parent = settingsBackdrop
	deps.polishPanel(settingsPanel, 16, "wood")
	-- Painted background (PanelArt): flat panel color if the art id is missing.
	local settingsPanelArt = require(script.Parent.PanelArt).add(settingsPanel, {
		key = "settings_bg", scrim = { position = UDim2.fromScale(0, 0), size = UDim2.fromScale(1, 1) },
		scrimTransparency = 0.35,
	})
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
	do -- Concept T look: serif cream title, green plate Close button
		local CS = require(script.Parent.ConceptTSkin)
		CS.title(settingsTitle)
		settingsTitle.TextSize = 26
	end

	-- The seed (Seed Run), date (Daily) or week (Weekly) of the run in progress; hidden for ordinary runs.
	local runLabel = Instance.new("TextLabel")
	runLabel.Name = "RunSeedLabel"
	runLabel.Size = UDim2.new(1, -40, 0, 22)
	runLabel.Position = UDim2.new(0, 20, 0, 40)
	runLabel.BackgroundTransparency = 1
	runLabel.Font = Enum.Font.GothamBold
	runLabel.TextSize = 16
	runLabel.TextColor3 = HEADER
	runLabel.Visible = false
	runLabel.ZIndex = 21
	runLabel.Parent = settingsPanel

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
		row.Size = UDim2.new(1, 0, 0, 62) -- 14px description may wrap to 2 lines
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
		desc.Size = UDim2.new(1, -130, 0, 36)
		desc.TextYAlignment = Enum.TextYAlignment.Top
		desc.Position = UDim2.new(0, 0, 0, 22)
		desc.BackgroundTransparency = 1
		desc.Font = Enum.Font.Gotham
		desc.TextSize = 14
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
			local current = ClientSettings.getRaw(key)
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
			local current = ClientSettings.getRaw(key)
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

	-- ===== Display =====
	makeHeader("Display")
	makeChoiceRow("animSpeed", "Animation Speed", "How fast hands score. Fast Forward pass owners get extra speed.", {
		{ "normal", "Normal" },
		{ "fast", "Fast" },
	})
	makeChoiceRow("reduceShake", "Reduce Screen Shake", "Turns off the screen shake on big hits.", OFF_ON)
	makeChoiceRow("colorblindSuits", "Colorblind Suits", "Gives each suit its own color and a corner letter.", OFF_ON)
	makeChoiceRow("reduceFlashing", "Reduce Flashing", "No screen flashes or fast pulses, fewer sparkles.", OFF_ON)
	makeChoiceRow("reduceMotion", "Reduce Motion", "Still backgrounds and no travel animations.", OFF_ON)
	makeChoiceRow("largerText", "Larger Text", "Makes text 15 percent bigger where there is room.", OFF_ON)

	-- ===== Gameplay =====
	makeHeader("Gameplay")
	makeChoiceRow("confirmDiscard", "Confirm Before Discard", "Asks before your selected cards are discarded.", OFF_ON)
	makeChoiceRow("allowSpectators", "Allow Spectators", "Friends in your server can watch your run. Turn off to stop them.", { { false, "Off" }, { true, "On" } })
	makeChoiceRow("holdConfirmSeconds", "Hold to Confirm", "How long to hold buttons that cannot be undone.", {
		{ 0.5, "0.5 s" }, { 1, "1 s" }, { 1.5, "1.5 s" }, { 2, "2 s" }, { 3, "3 s" },
	})

	-- Replay Hints: forget which first time hints were shown (Engine/Hints.lua), so each shows once more
	do
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, 0, 0, 62)
		row.LayoutOrder = order()
		row.BackgroundTransparency = 1
		row.ZIndex = 21
		row.Parent = scroll
		local title = Instance.new("TextLabel")
		title.Size = UDim2.new(1, -130, 0, 22)
		title.BackgroundTransparency = 1
		title.Font = Enum.Font.GothamBold
		title.TextSize = 16
		title.TextXAlignment = Enum.TextXAlignment.Left
		title.TextColor3 = TEXT
		title.Text = "Replay Hints"
		title.ZIndex = 21
		title.Parent = row
		local blurb = Instance.new("TextLabel")
		blurb.Size = UDim2.new(1, -130, 0, 36)
		blurb.Position = UDim2.new(0, 0, 0, 22)
		blurb.BackgroundTransparency = 1
		blurb.Font = Enum.Font.Gotham
		blurb.TextSize = 14
		blurb.TextWrapped = true
		blurb.TextXAlignment = Enum.TextXAlignment.Left
		blurb.TextYAlignment = Enum.TextYAlignment.Top
		blurb.TextColor3 = SUBTLE
		blurb.Text = "Show the one line tips again as you meet each part of the game."
		blurb.ZIndex = 21
		blurb.Parent = row
		local replay = Instance.new("TextButton")
		replay.Size = UDim2.new(0, 110, 0, 34)
		replay.AnchorPoint = Vector2.new(1, 0.5)
		replay.Position = UDim2.new(1, -4, 0.5, 0)
		replay.Font = Enum.Font.GothamBold
		replay.TextSize = 14
		replay.TextColor3 = TEXT
		replay.BackgroundColor3 = BUTTON
		replay.Text = "Replay"
		replay.ZIndex = 21
		replay.Parent = row
		polishButton(replay, 8)
		addButtonHoverScale(replay)
		replay.MouseButton1Click:Connect(function()
			playClickSfx()
			local remotes = game:GetService("ReplicatedStorage"):FindFirstChild("Remotes")
			local remote = remotes and remotes:FindFirstChild("ResetHints")
			if remote then
				remote:FireServer()
			end
			pcall(function() require(script.Parent.FirstTimeHints).replay() end)
			replay.Text = "Done"
			task.delay(1.5, function()
				if replay.Parent then replay.Text = "Replay" end
			end)
		end)
	end

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
		require(script.Parent.ConceptTSkin).plateButton(button)
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
	-- Daily Rewards ladder, readable any time (Client/DailyRewardsPanel.lua); its own full-width row under the three buttons.
	local settingsDailyButton = makeAccountButton("Daily Rewards", 4, nil)
	settingsDailyButton.Parent = scroll
	settingsDailyButton.Size = UDim2.new(1, 0, 0, 40)
	settingsDailyButton.LayoutOrder = order()

	-- Restart Run (danger button + hold-to-confirm popup), see Client/RestartRun.lua. Hidden when no run is active.
	local restartRun = require(script.Parent.RestartRun)({
		screenGui = deps.screenGui, root = deps.root, menuFrame = deps.menuFrame,
		polishPanel = deps.polishPanel, polishButton = polishButton, playClickSfx = playClickSfx,
		addSoftShadow = deps.addSoftShadow, addButtonHoverScale = addButtonHoverScale,
		parent = scroll, layoutOrder = order(),
	})

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
	require(script.Parent.ConceptTSkin).plateButton(settingsCloseButton)

	require(script.Parent.CloseX).retire(settingsCloseButton)
	require(script.Parent.CloseX).attach(settingsPanel, function()
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

	settingsDailyButton.MouseButton1Click:Connect(function()
		playClickSfx()
		popOut(settingsBackdrop, settingsPanel, nil, function()
			pcall(function() require(script.Parent.DailyRewardsPanel).open() end)
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

	local function openSettings()
		playClickSfx()
		OverlayManager.closeAllExcept("settings")
		restartRun.refresh()
		popIn(settingsBackdrop, settingsPanel)
	end
	deps.settingsButton.MouseButton1Click:Connect(openSettings)
	if deps.menuSettingsButton then
		deps.menuSettingsButton.MouseButton1Click:Connect(openSettings)
	end
	-- PopupDismiss: Escape and a click on the dark area close it, and a locked screen's Escape opens it (lifted above that screen).
	OverlayManager.registerOpener("settings", openSettings)
	require(script.Parent.PopupDismiss).attach(settingsBackdrop, { id = "settings", panel = settingsPanel, button = true })

	local function setRunLabel(text)
		runLabel.Visible = text ~= nil
		runLabel.Text = text or ""
		scroll.Position = UDim2.new(0, 20, 0, text and 66 or 48)
		scroll.Size = UDim2.new(1, -40, 1, text and -128 or -110)
	end

	-- "This run: <blessing>" with both lines, first row of the list while a run has a blessing.
	local blessingRow = Instance.new("TextLabel")
	blessingRow.Name = "RunBlessing"
	blessingRow.Size = UDim2.new(1, 0, 0, 62)
	blessingRow.LayoutOrder = 0
	blessingRow.BackgroundTransparency = 1
	blessingRow.Font = Enum.Font.GothamMedium
	blessingRow.TextSize = 14
	blessingRow.RichText = true
	blessingRow.TextWrapped = true
	blessingRow.TextXAlignment = Enum.TextXAlignment.Left
	blessingRow.TextYAlignment = Enum.TextYAlignment.Top
	blessingRow.TextColor3 = TEXT
	blessingRow.TextTransparency = 0
	blessingRow.TextStrokeTransparency = 1
	blessingRow.Visible = false
	blessingRow.ZIndex = 21
	blessingRow.Parent = scroll
	local function setBlessing(view)
		blessingRow.Visible = type(view) == "table"
		if blessingRow.Visible then
			blessingRow.Text = string.format("<b>This run: %s</b>\n<font color=\"#7BD389\">Blessing: %s</font>\n<font color=\"#FF9C8A\">Curse: %s</font>",
				view.name, view.blessing, view.curse)
		end
	end

	return {
		setBlessing = setBlessing,
		setRunLabel = setRunLabel,
		settingsBackdrop = settingsBackdrop,
		settingsHowToPlayButton = settingsHowToPlayButton,
		settingsLeaderboardButton = settingsLeaderboardButton,
	}
end
