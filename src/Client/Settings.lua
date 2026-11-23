--[[
	Client/Settings.lua
	The "⚙" corner button's panel (wood variant), in sections:
		Accessibility -- Calm mode, Reduce motion, Text size, Colorblind suits
		Sound    -- Volume
		Display  -- Animation speed (Normal/Fast), Performance mode
		Gameplay -- Round hints, Confirm before discard, Hold to confirm
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
local S = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("Strings")).get -- player facing text by id

return function(deps)
	local polishButton = deps.polishButton
	local playClickSfx = deps.playClickSfx
	local popIn = deps.popIn
	local popOut = deps.popOut
	local addButtonHoverScale = deps.addButtonHoverScale
	local roundCorner = deps.roundCorner
	local SettingsLayout = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("SettingsLayout"))
	local SW = SettingsLayout.SWITCH

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
	settingsPanel.Size = UDim2.fromScale(SettingsLayout.PANEL.fw, SettingsLayout.PANEL.fh)
	settingsPanel.Position = UDim2.fromScale((1 - SettingsLayout.PANEL.fw) / 2, SettingsLayout.PANEL.fy)
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
	settingsTitle.Font = Enum.Font.Merriweather
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
	runLabel.Font = Enum.Font.Merriweather
	runLabel.TextSize = 16
	runLabel.TextColor3 = HEADER
	runLabel.Visible = false
	runLabel.ZIndex = 21
	runLabel.Parent = settingsPanel

	local scroll = Instance.new("ScrollingFrame")
	scroll.Size = UDim2.new(1, -40, 1, -(SettingsLayout.PANEL.top + SettingsLayout.PANEL.bottomReserve))
	scroll.Position = UDim2.new(0, 20, 0, SettingsLayout.PANEL.top)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 8
	scroll.VerticalScrollBarInset = Enum.ScrollBarInset.Always -- the rows end before the bar, 16 px more below
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
		label.Font = Enum.Font.Merriweather
		label.TextSize = SettingsLayout.HEADER_SIZE
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextYAlignment = Enum.TextYAlignment.Bottom
		label.TextColor3 = HEADER
		label.Text = text
		label.ZIndex = 21
		label.Parent = scroll
		-- a thin rule under the section name in the equipped Card Set accent (gold for classic); a child, so the list layout ignores it
		local rule = Instance.new("Frame")
		rule.Name = "HeaderRule"
		rule.AnchorPoint = Vector2.new(0, 1)
		rule.Position = UDim2.new(0, 0, 1, 0)
		rule.Size = UDim2.new(1, 0, 0, 2)
		rule.BorderSizePixel = 0
		rule.BackgroundColor3 = require(script.Parent.TavernKit).ringColor(Color3.fromRGB(222, 182, 104))
		rule.ZIndex = 21
		rule.Parent = label
		pcall(function()
			require(script.Parent.HudTheme).onSkin(function()
				if rule.Parent then rule.BackgroundColor3 = require(script.Parent.TavernKit).ringColor(Color3.fromRGB(222, 182, 104)) end
			end)
		end)
	end

	-- One row: label + description on the left, a value button on the
	-- right. `choices` is a list of { value, text }; clicking cycles them.
	local function backPlate(button)
		local B = SettingsLayout.BACKING
		local back = Instance.new("Frame")
		back.Name = "PlateBacking"
		back.BackgroundColor3 = Color3.fromRGB(B.fill[1], B.fill[2], B.fill[3])
		back.BackgroundTransparency = B.transparency
		back.BorderSizePixel = 0
		back.Active = false
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, B.corner)
		corner.Parent = back
		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.fromRGB(B.edge[1], B.edge[2], B.edge[3])
		stroke.Thickness = B.edgePx
		stroke.Parent = back
		local function fit()
			back.AnchorPoint = button.AnchorPoint
			back.Position = button.Position
			back.Size = button.Size
			back.Visible = button.Visible
			back.ZIndex = math.max(0, button.ZIndex - 3) -- under the picture (ZIndex - 1) and the button
		end
		fit()
		for _, prop in ipairs({ "Position", "Size", "AnchorPoint", "Visible", "ZIndex" }) do
			button:GetPropertyChangedSignal(prop):Connect(fit)
		end
		back.Parent = button.Parent
		button.Destroying:Connect(function() back:Destroy() end)
		return back
	end

	local function makeChoiceRow(key, labelText, description, choices, custom)
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, 0, 0, 62) -- 14px description may wrap to 2 lines
		row.LayoutOrder = order()
		row.BackgroundTransparency = 1
		row.ZIndex = 21
		row.Parent = scroll

		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(1, -130, 0, 22)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.Merriweather
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
		desc.Font = Enum.Font.Merriweather
		desc.TextSize = 14
		desc.TextWrapped = true
		desc.TextXAlignment = Enum.TextXAlignment.Left
		desc.TextColor3 = SUBTLE
		desc.Text = description
		desc.ZIndex = 21
		desc.Parent = row

		local button = Instance.new("TextButton")
		local isSwitch = #choices == 2 and choices[1][1] == false
		button.Size = isSwitch and UDim2.new(0, SW.w, 0, SW.h) or UDim2.new(0, 110, 0, 44)
		button.AnchorPoint = Vector2.new(1, 0.5)
		button.Position = UDim2.new(1, -16, 0.5, 0)
		button.Font = Enum.Font.Merriweather
		button.TextSize = 16
		button.TextColor3 = TEXT
		button.ZIndex = 24 -- plate backing (21) and picture (23) sit under it, above the panel art (Global z order)
		button.Parent = row
		polishButton(button, 8)
		addButtonHoverScale(button)
		if not isSwitch then button:SetAttribute("FlatFace", true) end -- no set plate on top (Hold to Confirm showed two gold corners): the brass plate fills
		if not isSwitch then pcall(backPlate, button); pcall(require(script.Parent.TavernKit).painted, button, SettingsLayout.PLATE) end -- the same whole-picture brass plate as the Account buttons; the word shows the value

		local function getVal()
			if custom then return custom.get() end
			return ClientSettings.getRaw(key)
		end
		local function refresh()
			local current = getVal()
			for i, choice in ipairs(choices) do
				if choice[1] == current then
					button.Text = choice[2]
					if isSwitch then -- clear On and Off: fill plus the word
						local f = (i == 1) and SW.offFill or SW.onFill
						local t = (i == 1) and SW.offText or SW.onText
						if i ~= 1 then -- the On state wears the equipped Card Set accent (white text 4.5:1); classic keeps green
							local ok, c = pcall(function()
								return require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("CosmeticSets")).controlAccentOf(require(script.Parent.TavernKit).plateSetId())
							end)
							if ok and c then f, t = c.onFill, c.onText end
						end
						button.BackgroundColor3 = Color3.fromRGB(f[1], f[2], f[3])
						button.TextColor3 = Color3.fromRGB(t[1], t[2], t[3])
					else
						button.BackgroundColor3 = (i == 1) and BUTTON or ON
					end
					return
				end
			end
		end

		button.MouseButton1Click:Connect(function()
			playClickSfx()
			local current = getVal()
			local nextIndex = 1
			for i, choice in ipairs(choices) do
				if choice[1] == current then
					nextIndex = (i % #choices) + 1
				end
			end
			if custom then
				custom.set(choices[nextIndex][1])
			else
				ClientSettings.set(key, choices[nextIndex][1])
			end
			refresh()
		end)

		ClientSettings.onChanged(function(changedKey)
			if changedKey == key or (custom and custom.keys[changedKey]) then
				refresh()
			end
		end)
		refresh()
		pcall(function() require(script.Parent.HudTheme).onSkin(function() if button.Parent then refresh() end end) end) -- an equipped set shows at once
	end

	local OFF_ON = { { false, "Off" }, { true, "On" } }

	-- ===== Accessibility (Calm mode and Reduce Motion are always the first two rows, Engine/SettingsLayout) =====
	makeHeader("Accessibility")
	makeChoiceRow("calmMode", "Calm Mode", S("settings.calm.hint"), OFF_ON, {
		keys = { reduceMotion = true, reduceFlashing = true, reduceShake = true },
		get = function()
			return SettingsLayout.calmValue({ reduceMotion = ClientSettings.getRaw("reduceMotion"), reduceFlashing = ClientSettings.getRaw("reduceFlashing"), reduceShake = ClientSettings.getRaw("reduceShake") })
		end,
		set = function(on)
			for k, v in pairs(SettingsLayout.calmWrites(on)) do ClientSettings.set(k, v) end
		end,
	})
	makeChoiceRow("reduceMotion", "Reduce Motion", S("settings.reduceMotion.hint"), OFF_ON)
	makeChoiceRow("reduceFlashing", "Reduce Flashing", S("settings.reduceFlashing.hint"), OFF_ON)
	makeChoiceRow("reduceShake", "Reduce Screen Shake", S("settings.reduceShake.hint"), OFF_ON)
	makeChoiceRow("largerText", "Text Size", S("settings.largerText.hint"), { { false, "Normal" }, { true, "Large" } })
	makeChoiceRow("colorblindSuits", "Colorblind Suits", S("settings.colorblindSuits.hint"), OFF_ON)

	-- Sound and Music live only under the speaker icon (GearMenu), never repeated here (Engine/SettingsLayout, tested)

	-- ===== Display =====
	makeHeader("Display")
	makeChoiceRow("animSpeed", "Animation Speed", S("settings.animSpeed.hint"), {
		{ "normal", "Normal" },
		{ "fast", "Fast" },
	})
	makeChoiceRow("performanceMode", "Performance Mode", S("settings.performanceMode.hint"), OFF_ON)

	-- ===== Gameplay =====
	makeHeader("Gameplay")
	makeChoiceRow("roundHints", "Round Hints", S("settings.roundHints.hint"), { { false, "Off" }, { true, "On" } })
	makeChoiceRow("confirmDiscard", "Confirm Before Discard", S("settings.confirmDiscard.hint"), OFF_ON)
	makeChoiceRow("holdConfirmSeconds", "Hold to Confirm", S("settings.holdConfirm.hint"), {
		{ 0.5, "0.5 s" }, { 1, "1 s" }, { 1.5, "1.5 s" }, { 2, "2 s" }, { 3, "3 s" },
	})
	do -- the key hint (Engine/TableKeyMap.hintLines, same text as How to play)
		local hint = Instance.new("TextLabel")
		hint.Name = "KeysHint"
		hint.Size = UDim2.new(1, -16, 0, 96)
		hint.LayoutOrder = order()
		hint.BackgroundTransparency = 1
		hint.Font = Enum.Font.Merriweather
		hint.TextSize = 15
		hint.TextWrapped = true
		hint.TextXAlignment = Enum.TextXAlignment.Left
		hint.TextYAlignment = Enum.TextYAlignment.Top
		hint.TextColor3 = SUBTLE
		hint.TextTransparency = 0
		hint.TextStrokeTransparency = 1
		hint.Text = table.concat(require(game:GetService("ReplicatedStorage").Shared.Engine.TableKeyMap).hintLines(), "\n")
		hint.ZIndex = 21
		hint.Parent = scroll
	end

	-- ===== Account =====
	makeHeader("Account")
	makeChoiceRow("allowSpectators", "Allow Spectators", S("settings.allowSpectators.hint"), { { false, "Off" }, { true, "On" } })

	-- Replay Tutorial: the 24 step walkthrough again (Skip is always on screen while it runs)
	if deps.replayTutorial then
		local row = Instance.new("Frame")
		row.Name = "ReplayTutorialRow"
		row.Size = UDim2.new(1, 0, 0, 62)
		row.LayoutOrder = order()
		row.BackgroundTransparency = 1
		row.ZIndex = 21
		row.Parent = scroll
		local title = Instance.new("TextLabel")
		title.Size = UDim2.new(1, -130, 0, 22)
		title.BackgroundTransparency = 1
		title.Font = Enum.Font.Merriweather
		title.TextSize = 16
		title.TextXAlignment = Enum.TextXAlignment.Left
		title.TextColor3 = TEXT
		title.Text = "Replay Tutorial"
		title.ZIndex = 21
		title.Parent = row
		local blurb = Instance.new("TextLabel")
		blurb.Size = UDim2.new(1, -130, 0, 36)
		blurb.Position = UDim2.new(0, 0, 0, 22)
		blurb.BackgroundTransparency = 1
		blurb.Font = Enum.Font.Merriweather
		blurb.TextSize = 14
		blurb.TextWrapped = true
		blurb.TextXAlignment = Enum.TextXAlignment.Left
		blurb.TextYAlignment = Enum.TextYAlignment.Top
		blurb.TextColor3 = SUBTLE
		blurb.Text = S("settings.tutorial.blurb")
		blurb.ZIndex = 21
		blurb.Parent = row
		local go = Instance.new("TextButton")
		go.Name = "ReplayTutorial"
		go.Size = UDim2.new(0, 110, 0, 44)
		go.AnchorPoint = Vector2.new(1, 0.5)
		go.Position = UDim2.new(1, -4, 0.5, 0)
		go.Font = Enum.Font.Merriweather
		go.TextSize = 14
		go.TextColor3 = TEXT
		go.BackgroundColor3 = BUTTON
		go.Text = "Replay"
		go.ZIndex = 21
		go.Parent = row
		polishButton(go, 8)
		addButtonHoverScale(go)
		go.MouseButton1Click:Connect(function()
			-- a calm confirm first (Client/ReplayConfirm): replaying changes no saved progress
			require(script.Parent.ReplayConfirm).ask(function()
				settingsBackdrop.Visible = false
				pcall(deps.replayTutorial)
			end)
		end)
	end

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
		title.Font = Enum.Font.Merriweather
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
		blurb.Font = Enum.Font.Merriweather
		blurb.TextSize = 14
		blurb.TextWrapped = true
		blurb.TextXAlignment = Enum.TextXAlignment.Left
		blurb.TextYAlignment = Enum.TextYAlignment.Top
		blurb.TextColor3 = SUBTLE
		blurb.Text = S("settings.hints.blurb")
		blurb.ZIndex = 21
		blurb.Parent = row
		local replay = Instance.new("TextButton")
		replay.Size = UDim2.new(0, SettingsLayout.PANEL.replayW, 0, SettingsLayout.PANEL.replayH)
		replay.AnchorPoint = Vector2.new(1, 0.5)
		replay.Position = UDim2.new(1, -4, 0.5, 0)
		replay.Font = Enum.Font.Merriweather
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
			pcall(function() require(script.Parent.RoundHintsFX).replay() end)
			replay.Text = "Done"
			task.delay(1.5, function()
				if replay.Parent then replay.Text = "Replay" end
			end)
		end)
	end


	local ACC = SettingsLayout.ACCOUNT
	local function makeAccountRow()
		local rowFrame = Instance.new("Frame")
		rowFrame.Size = UDim2.new(1, 0, 0, ACC.plateH)
		rowFrame.LayoutOrder = order()
		rowFrame.BackgroundTransparency = 1
		rowFrame.ZIndex = 21
		rowFrame.Parent = scroll
		-- No list layout here on purpose:TavernKit.painted parents each plate picture as a SIBLING of the button, and a list layout
		-- would give every picture its own slot and push the buttons one panel width to the right (live, Nov 22). Plates are placed by Position.
		return rowFrame
	end
	local accountRow = makeAccountRow()
	local accountRow2 = makeAccountRow()

	local function makeAccountButton(text, layoutOrder, iconName, parentRow, perRow)
		perRow = perRow or ACC.perRow
		local button = Instance.new("TextButton")
		button.Size = UDim2.new(1 / perRow, -math.ceil(ACC.gap * (perRow - 1) / perRow), 0, ACC.plateH)
		button.Position = UDim2.new((layoutOrder - 1) / perRow, (layoutOrder - 1) * ACC.gap / perRow, 0, 0) -- slot i: i * (width + gap)
		button.TextWrapped = true
		button.LayoutOrder = layoutOrder
		button.Font = Enum.Font.Merriweather
		button.TextSize = ACC.textSize
		button.Text = text
		button.BackgroundColor3 = BUTTON
		button.TextColor3 = TEXT
		button.ZIndex = 24 -- plate backing (21) and picture (23) sit under it, above the panel art (Global z order)
		button.Parent = parentRow or accountRow
		polishButton(button, 12)
		addButtonHoverScale(button)
		-- The one shared ornate dark plate (same as the gear menu and All actions) with its own painted icon; every Account
		-- button gets exactly one plate and one icon, a flat brown look stays if the art does not load.
		local Kit = require(script.Parent.TavernKit)
		button:SetAttribute("AccountButton", true)
		button:SetAttribute("FlatFace", true) -- SetSkin draws no set plate over it: the brass kit plate always shows, whatever Card Set is equipped
		pcall(backPlate, button)
		pcall(Kit.painted, button, SettingsLayout.PLATE)
		if iconName then pcall(Kit.icon, button, iconName, 0.2) end
		return button
	end

	local settingsHowToPlayButton = makeAccountButton("How to Play", 1, "bulb")
	local settingsLeaderboardButton = makeAccountButton("Leaderboards", 2, "bars")
	local settingsMainMenuButton = makeAccountButton(SettingsLayout.PAUSE.quitText, 3, "pause")
	settingsMainMenuButton.Name = "MainMenu"
	-- Daily Rewards ladder, readable any time (Client/DailyRewardsPanel.lua); its own row under the three buttons, with the one Tavern Map button.
	local settingsDailyButton = makeAccountButton("Daily Rewards", 1, "crown", accountRow2, ACC.secondRow)
	-- Tavern Map: reachable from Settings too (opens over the table during a round, closing returns to it)
	local settingsMapButton = makeAccountButton("Tavern Map", 2, "spade", accountRow2, ACC.secondRow)
	settingsMapButton.Name = "TavernMap"

	-- Codes box: the typed text only goes to the server (Engine/Codes.lua), which answers with a toast
	do
		local row = Instance.new("Frame")
		row.Name = "CodesRow"
		row.Size = UDim2.new(1, 0, 0, SettingsLayout.CODES.rowH)
		row.LayoutOrder = order()
		row.BackgroundTransparency = 1
		row.ZIndex = 21
		row.Parent = scroll
		local title = Instance.new("TextLabel")
		title.Size = UDim2.new(1, 0, 0, 22)
		title.BackgroundTransparency = 1
		title.Font = Enum.Font.Merriweather
		title.TextSize = 16
		title.TextXAlignment = Enum.TextXAlignment.Left
		title.TextColor3 = TEXT
		title.Text = "Codes"
		title.ZIndex = 21
		title.Parent = row
		local box = Instance.new("TextBox")
		box.Name = "CodeBox"
		box.Size = UDim2.new(1, -130, 0, SettingsLayout.CODES.boxH)
		box.Position = UDim2.new(0, 0, 0, SettingsLayout.CODES.boxY)
		box.Font = Enum.Font.Merriweather
		box.TextSize = 16
		box.TextColor3 = TEXT
		box.PlaceholderText = "Type a code"
		box.PlaceholderColor3 = SUBTLE
		box.Text = ""
		box.ClearTextOnFocus = false
		box.BackgroundColor3 = BUTTON
		box.ZIndex = 21
		box.Parent = row
		polishButton(box, 8)
		local redeem = Instance.new("TextButton")
		redeem.Name = "Redeem"
		redeem.Size = UDim2.new(0, SettingsLayout.CODES.redeemW, 0, SettingsLayout.CODES.boxH)
		redeem.AnchorPoint = Vector2.new(1, 0)
		redeem.Position = UDim2.new(1, -4, 0, SettingsLayout.CODES.boxY)
		redeem.Font = Enum.Font.Merriweather
		redeem.TextSize = 15
		redeem.TextColor3 = TEXT
		redeem.BackgroundColor3 = BUTTON
		redeem.Text = "Redeem"
		redeem.ZIndex = 21
		redeem.Parent = row
		polishButton(redeem, 8)
		if pcall(function() return require(script.Parent.TavernKit).setPlateButton(redeem, "primary") end) and redeem:GetAttribute("BasePiece") then
			redeem.TextColor3 = Color3.fromRGB(250, 240, 220) -- the equipped Card Set's green plate; classic keeps the flat button
		end
		addButtonHoverScale(redeem)
		local msg = Instance.new("TextLabel")
		msg.Name = "CodeMessage"
		msg.Size = UDim2.new(1, 0, 0, SettingsLayout.CODES.msgH)
		msg.Position = UDim2.new(0, 0, 0, SettingsLayout.CODES.msgY)
		msg.BackgroundTransparency = 1
		msg.Font = Enum.Font.Merriweather
		msg.TextSize = SettingsLayout.CODES.msgSize
		msg.TextXAlignment = Enum.TextXAlignment.Left
		msg.TextColor3 = SUBTLE
		msg.TextTransparency, msg.TextStrokeTransparency = 0, 1
		msg.Text = ""
		msg.ZIndex = 21
		msg.Parent = row
		local function say(text)
			msg.Text = text
			task.delay(4, function()
				if msg.Parent and msg.Text == text then msg.Text = "" end
			end)
		end
		local function send()
			local text = box.Text
			if #text < SettingsLayout.CODES.minLen then
				say(SettingsLayout.CODES_SHORT)
				return
			end
			playClickSfx()
			local remotes = game:GetService("ReplicatedStorage"):FindFirstChild("Remotes")
			local remote = remotes and remotes:FindFirstChild("RedeemCode")
			if remote then
				remote:FireServer(text)
			end
			box.Text = ""
			say(SettingsLayout.CODES_SENT)
			redeem.Text = "Sent"
			task.delay(1.2, function()
				if redeem.Parent then redeem.Text = "Redeem" end
			end)
		end
		redeem.MouseButton1Click:Connect(send)
		box.FocusLost:Connect(function(enterPressed)
			if enterPressed then send() end
		end)
	end

	-- Restart Run (danger button + hold-to-confirm popup), see Client/RestartRun.lua. Hidden when no run is active.
	local restartRun = require(script.Parent.RestartRun)({
		screenGui = deps.screenGui, root = deps.root, menuFrame = deps.menuFrame,
		polishPanel = deps.polishPanel, polishButton = polishButton, playClickSfx = playClickSfx,
		addSoftShadow = deps.addSoftShadow, addButtonHoverScale = addButtonHoverScale,
		parent = scroll, layoutOrder = order(),
	})

	-- ===== About: game name with version and a one line thanks (Engine/GameName), no links =====
	makeHeader("About")
	do
		-- the About card wears the equipped Card Set: fill, gold edge and cream ink at 7:1 (PopupSkin.dark); classic keeps dark wood and gold
		local GameName = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("GameName"))
		local card = Instance.new("Frame")
		card.Name = "AboutPanel"
		card.Size = UDim2.new(1, 0, 0, GameName.aboutPanelHeight())
		card.LayoutOrder = order()
		card.BackgroundColor3 = Color3.fromRGB(40, 30, 22)
		card.BorderSizePixel = 0
		card.ZIndex = 21
		card.Parent = scroll
		local cc = Instance.new("UICorner")
		cc.CornerRadius = UDim.new(0, 8)
		cc.Parent = card
		local cs = Instance.new("UIStroke")
		cs.Color = HEADER
		cs.Thickness = 1.5
		cs.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		cs.Parent = card
		local labels = {}
		local y = GameName.ABOUT.PAD
		for i, line in ipairs(GameName.aboutLines()) do
			local about = Instance.new("TextLabel")
			about.Name = "AboutLine" .. i
			about.Size = UDim2.new(1, -GameName.ABOUT.PAD * 2, 0, GameName.ABOUT.LINE_H[i] or 26)
			about.Position = UDim2.fromOffset(GameName.ABOUT.PAD, y)
			y = y + (GameName.ABOUT.LINE_H[i] or 26)
			about.BackgroundTransparency = 1
			about.Font = Enum.Font.Merriweather
			about.TextSize = 16
			about.TextWrapped = true
			about.TextXAlignment = Enum.TextXAlignment.Left
			about.TextYAlignment = Enum.TextYAlignment.Top
			about.TextColor3 = TEXT
			about.Text = line
			about.ZIndex = 22
			about.Parent = card
			labels[#labels + 1] = { about, TEXT }
		end
		pcall(function() require(script.Parent.PopupSkin).dark(card, cs, labels, { plate = Color3.fromRGB(40, 30, 22), edge = HEADER }) end)
	end

	local settingsCloseButton = Instance.new("TextButton")
	settingsCloseButton.Size = UDim2.new(0, SettingsLayout.CLOSE.w, 0, SettingsLayout.CLOSE.h)
	settingsCloseButton.Position = UDim2.new(0.5, -SettingsLayout.CLOSE.w / 2, 1, -(SettingsLayout.CLOSE.h + 8))
	settingsCloseButton.Font = Enum.Font.Merriweather
	settingsCloseButton.TextSize = 16
	settingsCloseButton.Name = "Close" -- code and skins find this button by name; the word is Resume
	settingsCloseButton.Text = SettingsLayout.PAUSE.resumeText
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
			require(script.Parent.QuitConfirm).ask()
		end)
	end)

	settingsDailyButton.MouseButton1Click:Connect(function()
		playClickSfx()
		popOut(settingsBackdrop, settingsPanel, nil, function()
			pcall(function() require(script.Parent.DailyRewardsPanel).open() end)
		end)
	end)

	settingsMapButton.MouseButton1Click:Connect(function()
		playClickSfx()
		popOut(settingsBackdrop, settingsPanel, nil, function()
			OverlayManager.open("journey")
		end)
	end)

	-- Exactly one Tavern Map plate: a stray duplicate (an older merged copy named TavernMap) is removed, and Studio prints each Account rect.
	for _, d in ipairs(scroll:GetDescendants()) do
		if d:IsA("TextButton") and d ~= settingsMapButton and (d.Name == "TavernMap" or d.Text == "Tavern Map") then
			d:Destroy()
		end
	end
	if game:GetService("RunService"):IsStudio() then
		task.defer(function()
			task.wait(1)
			for _, b in ipairs(scroll:GetDescendants()) do
				if b:IsA("TextButton") and b:GetAttribute("AccountButton") then
					local rel = b.AbsolutePosition - scroll.AbsolutePosition
					warn(string.format("[SettingsAccount] %s x=%d y=%d w=%d h=%d (scroll %dx%d)", b.Text, rel.X, rel.Y, b.AbsoluteSize.X, b.AbsoluteSize.Y, scroll.AbsoluteSize.X, scroll.AbsoluteSize.Y))
					-- runtime check on the REAL built plates: x must sit inside the scroll width (a plate one panel width to the right was the Nov 22 bug)
					if rel.X < -1 or rel.X + b.AbsoluteSize.X > scroll.AbsoluteSize.X + 1 or b.AbsoluteSize.Y < 44 then
						warn("[SettingsAccount] OUTSIDE the scroll: " .. b:GetFullName())
					end
				end
			end
		end)
	end

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
		pcall(function() require(script.Parent.PopupDismiss).openSettings() end) -- lifted above the table plates (ZIndex is absolute under Global)
	end
	deps.settingsButton.MouseButton1Click:Connect(openSettings)
	if deps.menuSettingsButton then
		deps.menuSettingsButton.MouseButton1Click:Connect(openSettings)
	end
	-- PopupDismiss: Escape and a click on the dark area close it, and a locked screen's Escape opens it (lifted above that screen).
	OverlayManager.registerOpener("settings", openSettings)
	-- the gear menu's Quit to Tavern row: the same calm confirm as Settings > Quit to Tavern (Client/QuitConfirm)
	require(script.Parent.QuitConfirm).install({
		screenGui = deps.screenGui, root = deps.root, menuFrame = deps.menuFrame,
		polishPanel = deps.polishPanel, polishButton = polishButton, playClickSfx = playClickSfx,
	})
	require(script.Parent.ReplayConfirm).install({
		screenGui = deps.screenGui, polishPanel = deps.polishPanel, polishButton = polishButton, playClickSfx = playClickSfx,
	})
	OverlayManager.registerOpener("quitToTavern", function()
		require(script.Parent.QuitConfirm).ask()
	end)
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
	blessingRow.Font = Enum.Font.Merriweather
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
