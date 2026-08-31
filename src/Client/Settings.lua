--[[
	Client/Settings.lua
	FEATURE 10: a simple audio-only settings panel, reachable via the gear
	corner button. Scoped down to just Master Volume -- game options like
	animation speed/screenshake have no consumer code yet, so they're
	deliberately left out to keep this one piece small.

	Extracted out of init.client.lua as part of splitting the client script
	into smaller, per-feature files. Fully self-contained -- nothing outside
	this module needs anything it builds, so it returns an empty table.

	deps fields:
		screenGui        -- ScreenGui, the panel's ultimate parent (via backdrop)
		polishPanel       -- function(instance, radius)
		polishButton      -- function(instance, radius)
		addSoftShadow     -- function(instance, radius)
		playClickSfx      -- function(volume?)
		showWarning       -- function(text)
		settingsButton    -- TextButton, the in-game "⚙" corner button
		makeSliderRow     -- function(parent, labelText, min, max, getValue,
		                       setValue, formatValue) -- reusable drag-slider row
		backgroundMusic   -- Sound instance, for reading/writing .Volume
		volumeButton      -- TextButton, the corner "♪/♩/×" volume-cycle button --
		                       its icon is kept roughly in sync (loud vs muted)
		                       whenever the slider is dragged, so the corner icon
		                       doesn't go stale next to this panel's real value
		VOLUME_ICONS      -- { "♪", "♩", "×" }, same table Sound.lua hands out
		popIn             -- function(backdrop, content, opts?)
		popOut            -- function(backdrop, content, opts?, onHidden?)
		addButtonHoverScale -- function(button, opts?)
		-- QoL Game Pass (Custom Jukebox, Phase 9):
		GamePasses         -- the Shared/Engine/GamePasses module
		MarketplaceService -- the MarketplaceService, for PromptGamePassPurchase
		player              -- Players.LocalPlayer -- who PromptGamePassPurchase prompts
		getLatestState      -- function() -> latest state table or nil (live getter,
		                        for reading ownedGamePassIds -- see Themes.lua's
		                        identical use of this same dep for its own gating)
		setCustomTrack      -- function(assetId) -- see Sound.lua
		clearCustomTrack    -- function() -- see Sound.lua
		hasCustomTrack      -- function() -> boolean -- see Sound.lua

	Returns:
		{
			settingsBackdrop = Frame, -- render() checks .Visible, same pattern as Themes.lua
			refreshJukeboxSection = function(), -- re-checks ownedGamePassIds; call while the panel's open too, not just on open
		}

	POLISH PASS (Batch 3): popIn/popOut replace the old bare
	Visible = true/false cut; the Close button gets addButtonHoverScale.

	QoL GAME PASS PASS (Phase 9): added a Custom Jukebox section below the
	Master Volume slider -- paste a Roblox audio asset id or a full asset
	link and it plays instead of the built-in soundtrack (see Sound.lua's
	setCustomTrack). Gated behind GamePasses' "custom_jukebox" entry, same
	3-state Buy/Get-Pass/Coming-Soon pattern Themes.lua already uses, just
	simplified to 2 states (owned vs not) since there's nothing to "buy"
	with Tips here -- it's real-money-only like every other Game Pass.
	refreshJukeboxSection() re-checks ownership every time the panel opens
	(not just once at build time), since a purchase can complete while this
	panel already exists.
]]

return function(deps)
	local screenGui = deps.screenGui
	local polishPanel = deps.polishPanel
	local polishButton = deps.polishButton
	local addSoftShadow = deps.addSoftShadow
	local playClickSfx = deps.playClickSfx
	local showWarning = deps.showWarning
	local settingsButton = deps.settingsButton
	local makeSliderRow = deps.makeSliderRow
	local backgroundMusic = deps.backgroundMusic
	local volumeButton = deps.volumeButton
	local VOLUME_ICONS = deps.VOLUME_ICONS
	local popIn = deps.popIn
	local popOut = deps.popOut
	local addButtonHoverScale = deps.addButtonHoverScale
	local GamePasses = deps.GamePasses
	local MarketplaceService = deps.MarketplaceService
	local player = deps.player
	local getLatestState = deps.getLatestState
	local setCustomTrack = deps.setCustomTrack
	local clearCustomTrack = deps.clearCustomTrack
	local hasCustomTrack = deps.hasCustomTrack

	local settingsBackdrop = Instance.new("Frame")
	settingsBackdrop.Name = "SettingsBackdrop"
	settingsBackdrop.Size = UDim2.fromScale(1, 1)
	settingsBackdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	settingsBackdrop.BackgroundTransparency = 0.4
	settingsBackdrop.Visible = false
	settingsBackdrop.ZIndex = 20
	settingsBackdrop.Parent = screenGui

	-- Grown from the original 0.4 x 0.3 (Master-Volume-only) size to fit
	-- the new Custom Jukebox section below the slider.
	local settingsPanel = Instance.new("Frame")
	settingsPanel.Size = UDim2.fromScale(0.46, 0.56)
	settingsPanel.Position = UDim2.fromScale(0.27, 0.22)
	settingsPanel.BackgroundColor3 = Color3.fromRGB(40, 30, 22)
	settingsPanel.ZIndex = 21
	settingsPanel.Parent = settingsBackdrop
	polishPanel(settingsPanel, 16)
	addSoftShadow(settingsPanel, 18)

	local settingsTitle = Instance.new("TextLabel")
	settingsTitle.Size = UDim2.new(1, 0, 0, 40)
	settingsTitle.BackgroundTransparency = 1
	settingsTitle.Font = Enum.Font.GothamBold
	settingsTitle.TextSize = 22
	settingsTitle.TextColor3 = Color3.fromRGB(250, 240, 220)
	settingsTitle.Text = "Settings"
	settingsTitle.ZIndex = 21
	settingsTitle.Parent = settingsPanel

	-- Sized to fit just the Master Volume row (46px, see makeSliderRow) --
	-- the Custom Jukebox section below gets its own sibling Frame with the
	-- rest of the panel's space, instead of both sharing one tall
	-- unstructured container.
	local settingsBody = Instance.new("Frame")
	settingsBody.Size = UDim2.new(1, -40, 0, 46)
	settingsBody.Position = UDim2.new(0, 20, 0, 50)
	settingsBody.BackgroundTransparency = 1
	settingsBody.ZIndex = 21
	settingsBody.Parent = settingsPanel

	-- A real click-and-drag slider (see VisualHelpers.lua's makeSliderRow) --
	-- continuous 0-100 control over the same Sound instance's Volume, in
	-- place of the old +/-10%-per-click stepper. Dragging it also nudges
	-- the corner volumeButton's icon between loud/muted so that button
	-- doesn't sit there showing a stale state right after you've just
	-- changed the volume from in here.
	local masterVolumeValue = math.floor(backgroundMusic.Volume * 100 + 0.5)

	makeSliderRow(
		settingsBody,
		"Master Volume",
		0,
		100,
		function()
			return masterVolumeValue
		end,
		function(newValue)
			masterVolumeValue = newValue
			backgroundMusic.Volume = newValue / 100
			if newValue <= 0 then
				backgroundMusic:Stop()
			elseif backgroundMusic.SoundId ~= "rbxassetid://0" and not backgroundMusic.IsPlaying then
				backgroundMusic:Play()
			end
			if volumeButton and VOLUME_ICONS then
				volumeButton.Text = (newValue <= 0) and VOLUME_ICONS[3] or VOLUME_ICONS[1]
			end
		end,
		function(value)
			return tostring(value) .. "%"
		end
	)

	-- ===== Custom Jukebox (QoL Game Pass, Phase 9) =====
	local jukeboxSection = Instance.new("Frame")
	jukeboxSection.Size = UDim2.new(1, -40, 1, -166)
	jukeboxSection.Position = UDim2.new(0, 20, 0, 106)
	jukeboxSection.BackgroundTransparency = 1
	jukeboxSection.ZIndex = 21
	jukeboxSection.Parent = settingsPanel

	local jukeboxTitle = Instance.new("TextLabel")
	jukeboxTitle.Size = UDim2.new(1, 0, 0, 22)
	jukeboxTitle.BackgroundTransparency = 1
	jukeboxTitle.Font = Enum.Font.GothamBold
	jukeboxTitle.TextSize = 16
	jukeboxTitle.TextXAlignment = Enum.TextXAlignment.Left
	jukeboxTitle.TextColor3 = Color3.fromRGB(255, 214, 130)
	jukeboxTitle.Text = "🎵 Custom Jukebox"
	jukeboxTitle.ZIndex = 21
	jukeboxTitle.Parent = jukeboxSection

	-- ----- Locked state: not owned yet -----
	local jukeboxLockedFrame = Instance.new("Frame")
	jukeboxLockedFrame.Size = UDim2.new(1, 0, 1, -26)
	jukeboxLockedFrame.Position = UDim2.new(0, 0, 0, 26)
	jukeboxLockedFrame.BackgroundTransparency = 1
	jukeboxLockedFrame.ZIndex = 21
	jukeboxLockedFrame.Parent = jukeboxSection

	local lockedDescLabel = Instance.new("TextLabel")
	lockedDescLabel.Size = UDim2.new(1, 0, 0, 40)
	lockedDescLabel.BackgroundTransparency = 1
	lockedDescLabel.Font = Enum.Font.Gotham
	lockedDescLabel.TextSize = 13
	lockedDescLabel.TextWrapped = true
	lockedDescLabel.TextXAlignment = Enum.TextXAlignment.Left
	lockedDescLabel.TextYAlignment = Enum.TextYAlignment.Top
	lockedDescLabel.TextColor3 = Color3.fromRGB(190, 175, 155)
	lockedDescLabel.Text = "Paste your own background music track in instead of the built-in soundtrack."
	lockedDescLabel.ZIndex = 21
	lockedDescLabel.Parent = jukeboxLockedFrame

	local jukeboxActionButton = Instance.new("TextButton")
	jukeboxActionButton.Size = UDim2.new(0, 150, 0, 34)
	jukeboxActionButton.Position = UDim2.new(0, 0, 0, 46)
	jukeboxActionButton.Font = Enum.Font.GothamBold
	jukeboxActionButton.TextSize = 14
	jukeboxActionButton.BackgroundColor3 = Color3.fromRGB(90, 60, 30)
	jukeboxActionButton.TextColor3 = Color3.fromRGB(250, 240, 220)
	jukeboxActionButton.ZIndex = 21
	jukeboxActionButton.Parent = jukeboxLockedFrame
	polishButton(jukeboxActionButton, 8)
	addButtonHoverScale(jukeboxActionButton)

	-- Wired ONCE here (not rebuilt per refresh, unlike Themes.lua's per-row
	-- buttons) -- the catalog entry this points at is static for the whole
	-- session, only whether it's OWNED changes, and that's just a Visible
	-- toggle on jukeboxLockedFrame/jukeboxUnlockedFrame below.
	local jukeboxPass = GamePasses and GamePasses.getById("custom_jukebox")
	if jukeboxPass and jukeboxPass.gamePassId and jukeboxPass.gamePassId > 0 then
		jukeboxActionButton.Text = "Get Pass"
		jukeboxActionButton.MouseButton1Click:Connect(function()
			playClickSfx()
			MarketplaceService:PromptGamePassPurchase(player, jukeboxPass.gamePassId)
		end)
	else
		-- gamePassId still the 0 placeholder -- see GamePasses.lua's header
		-- comment. Prompting Game Pass 0 would just error, so show this
		-- instead until the real Pass exists on the Creator Dashboard.
		jukeboxActionButton.Text = "Coming Soon"
		jukeboxActionButton.AutoButtonColor = false
		jukeboxActionButton.BackgroundColor3 = Color3.fromRGB(55, 45, 35)
	end

	-- ----- Unlocked state: owned -----
	local jukeboxUnlockedFrame = Instance.new("Frame")
	jukeboxUnlockedFrame.Size = UDim2.new(1, 0, 1, -26)
	jukeboxUnlockedFrame.Position = UDim2.new(0, 0, 0, 26)
	jukeboxUnlockedFrame.BackgroundTransparency = 1
	jukeboxUnlockedFrame.Visible = false
	jukeboxUnlockedFrame.ZIndex = 21
	jukeboxUnlockedFrame.Parent = jukeboxSection

	local unlockedDescLabel = Instance.new("TextLabel")
	unlockedDescLabel.Size = UDim2.new(1, 0, 0, 30)
	unlockedDescLabel.BackgroundTransparency = 1
	unlockedDescLabel.Font = Enum.Font.Gotham
	unlockedDescLabel.TextSize = 12
	unlockedDescLabel.TextWrapped = true
	unlockedDescLabel.TextXAlignment = Enum.TextXAlignment.Left
	unlockedDescLabel.TextYAlignment = Enum.TextYAlignment.Top
	unlockedDescLabel.TextColor3 = Color3.fromRGB(190, 175, 155)
	unlockedDescLabel.Text = "Paste a Roblox audio asset id or link (only plays if it's an asset you're allowed to use):"
	unlockedDescLabel.ZIndex = 21
	unlockedDescLabel.Parent = jukeboxUnlockedFrame

	local jukeboxTextBox = Instance.new("TextBox")
	jukeboxTextBox.Size = UDim2.new(1, 0, 0, 34)
	jukeboxTextBox.Position = UDim2.new(0, 0, 0, 34)
	jukeboxTextBox.Font = Enum.Font.Gotham
	jukeboxTextBox.TextSize = 14
	jukeboxTextBox.TextColor3 = Color3.fromRGB(250, 240, 220)
	jukeboxTextBox.PlaceholderText = "e.g. rbxassetid://123456789 or a library link"
	jukeboxTextBox.PlaceholderColor3 = Color3.fromRGB(150, 140, 130)
	jukeboxTextBox.Text = ""
	jukeboxTextBox.ClearTextOnFocus = false
	jukeboxTextBox.BackgroundColor3 = Color3.fromRGB(30, 22, 16)
	jukeboxTextBox.ZIndex = 21
	jukeboxTextBox.Parent = jukeboxUnlockedFrame
	polishButton(jukeboxTextBox, 8)

	local jukeboxPlayButton = Instance.new("TextButton")
	jukeboxPlayButton.Size = UDim2.new(0, 90, 0, 32)
	jukeboxPlayButton.Position = UDim2.new(0, 0, 0, 74)
	jukeboxPlayButton.Font = Enum.Font.GothamBold
	jukeboxPlayButton.TextSize = 14
	jukeboxPlayButton.Text = "Play"
	jukeboxPlayButton.BackgroundColor3 = Color3.fromRGB(70, 90, 60)
	jukeboxPlayButton.TextColor3 = Color3.fromRGB(250, 240, 220)
	jukeboxPlayButton.ZIndex = 21
	jukeboxPlayButton.Parent = jukeboxUnlockedFrame
	polishButton(jukeboxPlayButton, 8)
	addButtonHoverScale(jukeboxPlayButton)

	local jukeboxResetButton = Instance.new("TextButton")
	jukeboxResetButton.Size = UDim2.new(0, 90, 0, 32)
	jukeboxResetButton.Position = UDim2.new(0, 98, 0, 74)
	jukeboxResetButton.Font = Enum.Font.GothamBold
	jukeboxResetButton.TextSize = 14
	jukeboxResetButton.Text = "Reset"
	jukeboxResetButton.BackgroundColor3 = Color3.fromRGB(90, 60, 30)
	jukeboxResetButton.TextColor3 = Color3.fromRGB(250, 240, 220)
	jukeboxResetButton.ZIndex = 21
	jukeboxResetButton.Parent = jukeboxUnlockedFrame
	polishButton(jukeboxResetButton, 8)
	addButtonHoverScale(jukeboxResetButton)

	local jukeboxStatusLabel = Instance.new("TextLabel")
	jukeboxStatusLabel.Size = UDim2.new(1, 0, 0, 20)
	jukeboxStatusLabel.Position = UDim2.new(0, 0, 0, 112)
	jukeboxStatusLabel.BackgroundTransparency = 1
	jukeboxStatusLabel.Font = Enum.Font.Gotham
	jukeboxStatusLabel.TextSize = 12
	jukeboxStatusLabel.TextXAlignment = Enum.TextXAlignment.Left
	jukeboxStatusLabel.TextColor3 = Color3.fromRGB(150, 220, 160)
	jukeboxStatusLabel.Text = ""
	jukeboxStatusLabel.ZIndex = 21
	jukeboxStatusLabel.Parent = jukeboxUnlockedFrame

	local function refreshJukeboxStatus()
		if hasCustomTrack and hasCustomTrack() then
			jukeboxStatusLabel.TextColor3 = Color3.fromRGB(150, 220, 160)
			jukeboxStatusLabel.Text = "Now playing your custom track."
		else
			jukeboxStatusLabel.TextColor3 = Color3.fromRGB(190, 175, 155)
			jukeboxStatusLabel.Text = "Using the built-in soundtrack."
		end
	end

	-- Accepts a raw numeric id, an "rbxassetid://<id>" string, or a full
	-- library/catalog URL -- all 3 have the numeric asset id in them
	-- somewhere, so pulling out the first run of digits covers every case
	-- without needing to parse a real URL.
	jukeboxPlayButton.MouseButton1Click:Connect(function()
		local digits = jukeboxTextBox.Text:match("%d+")
		if not digits then
			playClickSfx()
			showWarning("Paste a valid asset id or link.")
			return
		end
		playClickSfx()
		setCustomTrack("rbxassetid://" .. digits)
		refreshJukeboxStatus()
	end)

	jukeboxResetButton.MouseButton1Click:Connect(function()
		playClickSfx()
		clearCustomTrack()
		refreshJukeboxStatus()
	end)

	-- Re-checks ownership every time the panel opens (see settingsButton's
	-- click handler below) -- a purchase can complete asynchronously while
	-- this panel already exists (same reasoning as Themes.lua's
	-- refreshThemesList being called on every open, not just once at
	-- build time).
	local function refreshJukeboxSection()
		local latest = getLatestState and getLatestState()
		local owned = false
		if latest and latest.ownedGamePassIds then
			owned = table.find(latest.ownedGamePassIds, "custom_jukebox") ~= nil
		end
		jukeboxLockedFrame.Visible = not owned
		jukeboxUnlockedFrame.Visible = owned
		if owned then
			refreshJukeboxStatus()
		end
	end
	refreshJukeboxSection() -- initial state at build time -- correct even if ownership isn't known yet, since it just reads whatever getLatestState() has right now

	local settingsCloseButton = Instance.new("TextButton")
	settingsCloseButton.Size = UDim2.new(0, 140, 0, 40)
	settingsCloseButton.Position = UDim2.new(0.5, -70, 1, -50)
	settingsCloseButton.Font = Enum.Font.GothamBold
	settingsCloseButton.TextSize = 16
	settingsCloseButton.Text = "Close"
	settingsCloseButton.BackgroundColor3 = Color3.fromRGB(90, 60, 30)
	settingsCloseButton.TextColor3 = Color3.fromRGB(250, 240, 220)
	settingsCloseButton.ZIndex = 21
	settingsCloseButton.Parent = settingsPanel
	polishButton(settingsCloseButton, 12)
	addButtonHoverScale(settingsCloseButton)

	settingsCloseButton.MouseButton1Click:Connect(function()
		playClickSfx()
		popOut(settingsBackdrop, settingsPanel)
	end)

	settingsButton.MouseButton1Click:Connect(function()
		playClickSfx()
		refreshJukeboxSection()
		popIn(settingsBackdrop, settingsPanel)
	end)

	-- BUGFIX (Phase 9, caught by independent review before shipping):
	-- returning {} (as this module always did before the Custom Jukebox
	-- section existed) meant render() had no way to keep this panel's
	-- ownership state fresh if a Get-Pass purchase completes WHILE the
	-- panel is already open -- unlike Themes.lua, which render() already
	-- refreshes on every state push whenever themesBackdrop.Visible (see
	-- init.client.lua). Exposing these two lets render() do the same thing
	-- here.
	return {
		settingsBackdrop = settingsBackdrop,
		refreshJukeboxSection = refreshJukeboxSection,
	}
end
