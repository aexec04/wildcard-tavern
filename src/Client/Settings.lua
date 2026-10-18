--[[
	Client/Settings.lua
	FEATURE 10: a simple audio-only settings panel, reachable via the gear
	corner button. Originally scoped down to just a single Master Volume
	row -- game options like animation speed/screenshake have no consumer
	code yet, so they're still deliberately left out -- but the audio
	section has grown a lot since: that row is now just labeled "Volume"
	(SFX VOLUME SLIDERS, see that comment further down, for why) and is
	immediately followed, with nothing visually separating them, by one
	slider per individual sound effect, so the whole scrollable audio
	section no longer fits in one glance the way the single row used to.

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
		-- JUKEBOX PLAYLIST (requested fix):
		AddPlaylistSongRemote    -- RemoteEvent, fired (assetId) to save a song
		RemovePlaylistSongRemote -- RemoteEvent, fired (assetId) to remove a saved song
		MAX_PLAYLIST_SIZE        -- number -- Shared/Engine/PlayerProfile.MAX_PLAYLIST_SIZE,
		                            the single source of truth for the cap (also enforced
		                            server-side -- this is just so the client can warn
		                            instead of silently no-opping)
		menuFrame           -- Frame, the main menu screen (see Menu.lua) -- shown
		                        by the new Main Menu button below
		root                -- Frame, the in-game gameplay root -- hidden by the
		                        new Main Menu button below (exact mirror of what
		                        menuPlayButton's handler does in init.client.lua,
		                        just in reverse)
		-- SFX VOLUME SLIDERS:
		SFX_CATALOG         -- { { label, id }, ... } -- see Sound.lua's own comment
		getSfxVolume        -- function(id) -> number, 0-1 -- see Sound.lua
		setSfxVolume        -- function(id, multiplier) -- see Sound.lua

	Returns:
		{
			settingsBackdrop = Frame, -- render() checks .Visible, same pattern as Themes.lua
			refreshJukeboxSection = function(), -- re-checks ownedGamePassIds; call while the panel's open too, not just on open
		}

	POLISH PASS (Batch 3): popIn/popOut replace the old bare
	Visible = true/false cut; the Close button gets addButtonHoverScale.

	MAIN MENU BUTTON (requested fix): before this, there was no way to get
	back to the main menu once a run started -- GameOver.lua only offers
	Play Again, and quitting meant literally leaving the game. Settings is
	reachable from both the menu screen and mid-run (it's the corner "⚙"
	button, parented straight to screenGui, not gated by root/menuFrame
	visibility), so it's the natural place for a way out. The handler is
	the exact mirror of menuPlayButton's in init.client.lua: hide root,
	show menuFrame. Nothing server-side is touched -- Phase 10's
	persistence already means whatever run was in progress just picks back
	up next time Play is pressed, same as it would after a disconnect.

	QoL GAME PASS PASS (Phase 9): added a Custom Jukebox section below the
	volume sliders -- paste a Roblox audio asset id or a full asset link
	and it plays instead of the built-in soundtrack (see Sound.lua's
	setCustomTrack). Gated behind GamePasses' "custom_jukebox" entry, same
	3-state Buy/Get-Pass/Coming-Soon pattern Themes.lua already uses, just
	simplified to 2 states (owned vs not) since there's nothing to "buy"
	with Tips here -- it's real-money-only like every other Game Pass.
	refreshJukeboxSection() re-checks ownership every time the panel opens
	(not just once at build time), since a purchase can complete while this
	panel already exists.

	JUKEBOX PLAYLIST (requested fix: "make it so if they put a song ID
	that it saves for them so if they have like 20 song IDs, they can
	create their own playlist"): the Custom Jukebox section used to only
	ever remember ONE pasted-in track at a time, purely in memory --
	closing the game lost it. "Add to Playlist" now ALSO saves the song to
	this player's permanent profile (Shared/Engine/PlayerProfile.lua's
	customPlaylist, via AddPlaylistSongRemote) while still playing it
	immediately, and "My Playlist" below lists every song saved that way
	with its own Play/Remove. Capped at PlayerProfile.MAX_PLAYLIST_SIZE
	(20) -- enforced server-side; the client just pre-checks the same 2
	conditions (duplicate, full) so a rejected add warns instead of
	silently doing nothing. A couple of curated PRESET playlists (for a
	player who can't be bothered picking their own) is a reasonable next
	step here, but deliberately not built this pass -- Ahmed's own request
	called it out as "eventually."
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
	-- JUKEBOX PLAYLIST (requested fix): see each dep's own comment further
	-- down (around refreshPlaylistRows) for how it's used.
	local AddPlaylistSongRemote = deps.AddPlaylistSongRemote
	local RemovePlaylistSongRemote = deps.RemovePlaylistSongRemote
	local MAX_PLAYLIST_SIZE = deps.MAX_PLAYLIST_SIZE
	local menuFrame = deps.menuFrame
	local root = deps.root
	-- SFX VOLUME SLIDERS: see Sound.lua's own header comment for what each
	-- of these 3 is.
	local SFX_CATALOG = deps.SFX_CATALOG
	local getSfxVolume = deps.getSfxVolume
	local setSfxVolume = deps.setSfxVolume
	-- BUGFIX (overlapping overlays): see Client/OverlayManager.lua's own
	-- header comment for the full story.
	local OverlayManager = require(script.Parent.OverlayManager)

	local settingsBackdrop = Instance.new("Frame")
	settingsBackdrop.Name = "SettingsBackdrop"
	settingsBackdrop.Size = UDim2.fromScale(1, 1)
	settingsBackdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	settingsBackdrop.BackgroundTransparency = 0.4
	settingsBackdrop.Visible = false
	settingsBackdrop.ZIndex = 20
	settingsBackdrop.Parent = screenGui

	-- Grown from the original 0.4 x 0.3 (Master-Volume-only) size, then
	-- again (SFX VOLUME SLIDERS) to fit a whole scrollable list of
	-- per-sound-effect sliders on top of the Custom Jukebox section.
	local settingsPanel = Instance.new("Frame")
	settingsPanel.Size = UDim2.fromScale(0.5, 0.8)
	settingsPanel.Position = UDim2.fromScale(0.25, 0.1)
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

	-- SFX VOLUME SLIDERS: used to be a single fixed-height Frame holding
	-- just the Master Volume row (46px) -- now a real ScrollingFrame, the
	-- same pattern Collection.lua's row list already uses, since this
	-- section now holds the renamed Volume row + one slider per
	-- Sound.lua SFX_CATALOG entry (folded directly in under it, no
	-- sub-header -- see that loop's own comment for why) + the Custom
	-- Jukebox section -- far more content than the panel can show at
	-- once. UIListLayout stacks everything by LayoutOrder (see each
	-- addition below for its own number) instead of hand-placed Y
	-- offsets, and AutomaticCanvasSize means the list simply grows --
	-- adding a new SFX to Sound.lua's SFX_CATALOG later needs zero layout
	-- math here.
	local settingsScroll = Instance.new("ScrollingFrame")
	settingsScroll.Size = UDim2.new(1, -40, 1, -130)
	settingsScroll.Position = UDim2.new(0, 20, 0, 50)
	settingsScroll.BackgroundTransparency = 1
	settingsScroll.BorderSizePixel = 0
	settingsScroll.ScrollBarThickness = 8
	settingsScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	settingsScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	settingsScroll.ZIndex = 21
	settingsScroll.Parent = settingsPanel

	local settingsLayout = Instance.new("UIListLayout")
	settingsLayout.Padding = UDim.new(0, 10)
	settingsLayout.Parent = settingsScroll

	-- A real click-and-drag slider (see VisualHelpers.lua's makeSliderRow) --
	-- continuous 0-100 control over the same Sound instance's Volume, in
	-- place of the old +/-10%-per-click stepper. Dragging it also nudges
	-- the corner volumeButton's icon between loud/muted so that button
	-- doesn't sit there showing a stale state right after you've just
	-- changed the volume from in here.
	local masterVolumeValue = math.floor(backgroundMusic.Volume * 100 + 0.5)

	makeSliderRow(
		settingsScroll,
		"Volume",
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
		end,
		1
	)

	-- SFX VOLUME SLIDERS (requested fix: "adjust all the sound effects, not
	-- just music ... every sfx that we have, they can all be sliders" --
	-- then, Ahmed's follow-up: "these should NOT be in setting, they
	-- should be in the Music Volume thing" -- i.e. NOT their own
	-- separately-labeled sub-section, just folded directly into the same
	-- Volume group as the row above with nothing visually separating
	-- them): one 0-100 slider per Sound.lua SFX_CATALOG entry, same real
	-- click-and-drag control as Volume above, each one scaling only that
	-- single sound (see Sound.lua's getSfxVolume/setSfxVolume and how
	-- playSfx/playPitched apply the multiplier). LayoutOrder 2 onward
	-- (Volume above is 1), so these always sit directly under Volume and
	-- above the Jukebox section regardless of catalog order.
	if SFX_CATALOG then
		for i, entry in ipairs(SFX_CATALOG) do
			local sfxValue = math.floor(getSfxVolume(entry.id) * 100 + 0.5)
			makeSliderRow(
				settingsScroll,
				entry.label,
				0,
				100,
				function()
					return sfxValue
				end,
				function(newValue)
					sfxValue = newValue
					setSfxVolume(entry.id, newValue / 100)
				end,
				function(value)
					return tostring(value) .. "%"
				end,
				1 + i
			)
		end
	end

	-- ===== Custom Jukebox (QoL Game Pass, Phase 9; JUKEBOX PLAYLIST added
	-- this pass) =====
	-- LayoutOrder 1000 (not just "after the SFX rows") so a future catalog
	-- addition in Sound.lua can never accidentally push past this section
	-- without the fixed-height math below needing to change too. Grown
	-- from 170 to 300 to fit the new "My Playlist" list below the
	-- add-a-song controls.
	local jukeboxSection = Instance.new("Frame")
	jukeboxSection.Size = UDim2.new(1, 0, 0, 300)
	jukeboxSection.BackgroundTransparency = 1
	jukeboxSection.LayoutOrder = 1000
	jukeboxSection.ZIndex = 21
	jukeboxSection.Parent = settingsScroll

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
	jukeboxLockedFrame.Size = UDim2.new(1, 0, 0, 144)
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
	lockedDescLabel.Text = "Paste in your own background music tracks and build a saved playlist, instead of just the built-in soundtrack."
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
	jukeboxUnlockedFrame.Size = UDim2.new(1, 0, 0, 274)
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
	unlockedDescLabel.Text = "Paste a Roblox audio asset id or link below to add it to your playlist (only plays if it's an asset you're allowed to use):"
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

	-- JUKEBOX PLAYLIST (requested fix): was "Play" (played the pasted
	-- track immediately, nothing saved) -- now also SAVES it to this
	-- player's persistent playlist (fires AddPlaylistSongRemote, see
	-- Shared/Engine/PlayerProfile.lua's addPlaylistSong), so it shows up
	-- in "My Playlist" below and survives a rejoin, while still playing
	-- it immediately too for the same instant feedback the old button had.
	local jukeboxAddButton = Instance.new("TextButton")
	jukeboxAddButton.Size = UDim2.new(0, 160, 0, 32)
	jukeboxAddButton.Position = UDim2.new(0, 0, 0, 74)
	jukeboxAddButton.Font = Enum.Font.GothamBold
	jukeboxAddButton.TextSize = 14
	jukeboxAddButton.Text = "Add to Playlist"
	jukeboxAddButton.BackgroundColor3 = Color3.fromRGB(70, 90, 60)
	jukeboxAddButton.TextColor3 = Color3.fromRGB(250, 240, 220)
	jukeboxAddButton.ZIndex = 21
	jukeboxAddButton.Parent = jukeboxUnlockedFrame
	polishButton(jukeboxAddButton, 8)
	addButtonHoverScale(jukeboxAddButton)

	local jukeboxResetButton = Instance.new("TextButton")
	jukeboxResetButton.Size = UDim2.new(0, 90, 0, 32)
	jukeboxResetButton.Position = UDim2.new(0, 170, 0, 74)
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

	-- ===== My Playlist (JUKEBOX PLAYLIST, requested fix) =====
	-- "make it so if they put a song ID that it saves for them so if they
	-- have like 20 song IDs, they can create their own playlist." One row
	-- per saved song, each with its own Play/Remove -- rebuilt from
	-- scratch (destroy + recreate every row) on every refresh, same
	-- pattern Collection.lua/Themes.lua already use for their own
	-- server-driven lists, rather than trying to diff the old rows
	-- against the new list.
	local playlistHeaderLabel = Instance.new("TextLabel")
	playlistHeaderLabel.Size = UDim2.new(1, 0, 0, 18)
	playlistHeaderLabel.Position = UDim2.new(0, 0, 0, 138)
	playlistHeaderLabel.BackgroundTransparency = 1
	playlistHeaderLabel.Font = Enum.Font.GothamBold
	playlistHeaderLabel.TextSize = 13
	playlistHeaderLabel.TextXAlignment = Enum.TextXAlignment.Left
	playlistHeaderLabel.TextColor3 = Color3.fromRGB(255, 214, 130)
	playlistHeaderLabel.Text = "My Playlist"
	playlistHeaderLabel.ZIndex = 21
	playlistHeaderLabel.Parent = jukeboxUnlockedFrame

	local playlistScroll = Instance.new("ScrollingFrame")
	playlistScroll.Size = UDim2.new(1, 0, 0, 110)
	playlistScroll.Position = UDim2.new(0, 0, 0, 160)
	playlistScroll.BackgroundColor3 = Color3.fromRGB(30, 22, 16)
	playlistScroll.BackgroundTransparency = 0.4
	playlistScroll.BorderSizePixel = 0
	playlistScroll.ScrollBarThickness = 6
	playlistScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	playlistScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	playlistScroll.ZIndex = 21
	playlistScroll.Parent = jukeboxUnlockedFrame
	polishButton(playlistScroll, 8)

	local playlistLayout = Instance.new("UIListLayout")
	playlistLayout.Padding = UDim.new(0, 4)
	playlistLayout.Parent = playlistScroll

	local playlistEmptyLabel = Instance.new("TextLabel")
	playlistEmptyLabel.Size = UDim2.new(1, -12, 0, 26)
	playlistEmptyLabel.Position = UDim2.new(0, 6, 0, 4)
	playlistEmptyLabel.BackgroundTransparency = 1
	playlistEmptyLabel.Font = Enum.Font.Gotham
	playlistEmptyLabel.TextSize = 12
	playlistEmptyLabel.TextXAlignment = Enum.TextXAlignment.Left
	playlistEmptyLabel.TextColor3 = Color3.fromRGB(150, 140, 130)
	playlistEmptyLabel.Text = "Nothing saved yet -- add a song above."
	playlistEmptyLabel.LayoutOrder = 0
	playlistEmptyLabel.ZIndex = 21
	playlistEmptyLabel.Parent = playlistScroll

	local function makePlaylistRow(order, assetId)
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, -12, 0, 26)
		row.Position = UDim2.new(0, 6, 0, 0)
		row.BackgroundTransparency = 1
		row.LayoutOrder = order
		row.ZIndex = 21
		row.Parent = playlistScroll

		local idLabel = Instance.new("TextLabel")
		idLabel.Size = UDim2.new(1, -120, 1, 0)
		idLabel.BackgroundTransparency = 1
		idLabel.Font = Enum.Font.Gotham
		idLabel.TextSize = 12
		idLabel.TextXAlignment = Enum.TextXAlignment.Left
		idLabel.TextTruncate = Enum.TextTruncate.AtEnd
		idLabel.TextColor3 = Color3.fromRGB(220, 210, 195)
		idLabel.Text = "🎵 " .. assetId
		idLabel.ZIndex = 21
		idLabel.Parent = row

		local rowPlayButton = Instance.new("TextButton")
		rowPlayButton.Size = UDim2.new(0, 56, 0, 24)
		rowPlayButton.Position = UDim2.new(1, -116, 0, 1)
		rowPlayButton.Font = Enum.Font.GothamBold
		rowPlayButton.TextSize = 12
		rowPlayButton.Text = "▶ Play"
		rowPlayButton.BackgroundColor3 = Color3.fromRGB(70, 90, 60)
		rowPlayButton.TextColor3 = Color3.fromRGB(250, 240, 220)
		rowPlayButton.ZIndex = 21
		rowPlayButton.Parent = row
		polishButton(rowPlayButton, 6)
		addButtonHoverScale(rowPlayButton)

		local rowRemoveButton = Instance.new("TextButton")
		rowRemoveButton.Size = UDim2.new(0, 56, 0, 24)
		rowRemoveButton.Position = UDim2.new(1, -56, 0, 1)
		rowRemoveButton.Font = Enum.Font.GothamBold
		rowRemoveButton.TextSize = 12
		rowRemoveButton.Text = "✕ Remove"
		rowRemoveButton.BackgroundColor3 = Color3.fromRGB(90, 45, 40)
		rowRemoveButton.TextColor3 = Color3.fromRGB(250, 240, 220)
		rowRemoveButton.ZIndex = 21
		rowRemoveButton.Parent = row
		polishButton(rowRemoveButton, 6)
		addButtonHoverScale(rowRemoveButton)

		rowPlayButton.MouseButton1Click:Connect(function()
			playClickSfx()
			setCustomTrack(assetId)
			refreshJukeboxStatus()
		end)

		rowRemoveButton.MouseButton1Click:Connect(function()
			playClickSfx()
			if RemovePlaylistSongRemote then
				RemovePlaylistSongRemote:FireServer(assetId)
			end
		end)
	end

	-- Rebuilds "My Playlist" from latest.customPlaylist (see
	-- Server/init.server.lua's serializeState) -- called from
	-- refreshJukeboxSection below, so every place that already refreshes
	-- the Jukebox section (panel open, and render() while it's open --
	-- see this file's own BUGFIX comment on that near the bottom) picks
	-- up an add/remove for free with no extra wiring.
	local function refreshPlaylistRows()
		for _, child in ipairs(playlistScroll:GetChildren()) do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
		local latest = getLatestState and getLatestState()
		local playlist = (latest and latest.customPlaylist) or {}
		local cap = MAX_PLAYLIST_SIZE or 20
		playlistHeaderLabel.Text = string.format("My Playlist (%d/%d)", #playlist, cap)
		playlistEmptyLabel.Visible = (#playlist == 0)
		for i, assetId in ipairs(playlist) do
			makePlaylistRow(i, assetId)
		end
	end

	-- Accepts a raw numeric id, an "rbxassetid://<id>" string, or a full
	-- library/catalog URL -- all 3 have the numeric asset id in them
	-- somewhere, so pulling out the first run of digits covers every case
	-- without needing to parse a real URL.
	jukeboxAddButton.MouseButton1Click:Connect(function()
		local digits = jukeboxTextBox.Text:match("%d+")
		if not digits then
			playClickSfx()
			showWarning("Paste a valid asset id or link.")
			return
		end
		local assetId = "rbxassetid://" .. digits
		-- Client-side pre-checks purely so a rejected add gives real
		-- feedback instead of silently doing nothing -- the server
		-- (PlayerProfile.addPlaylistSong) re-checks both of these
		-- independently and is the one actually enforced; never trust
		-- these checks alone.
		local latest = getLatestState and getLatestState()
		local playlist = (latest and latest.customPlaylist) or {}
		local cap = MAX_PLAYLIST_SIZE or 20
		if table.find(playlist, assetId) then
			playClickSfx()
			showWarning("Already in your playlist.")
			return
		end
		if #playlist >= cap then
			playClickSfx()
			showWarning(string.format("Your playlist is full (%d/%d).", cap, cap))
			return
		end
		playClickSfx()
		if AddPlaylistSongRemote then
			AddPlaylistSongRemote:FireServer(assetId)
		end
		setCustomTrack(assetId)
		refreshJukeboxStatus()
		jukeboxTextBox.Text = ""
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
	-- build time). Also rebuilds "My Playlist" every time, same reasoning.
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
			refreshPlaylistRows()
		end
	end
	refreshJukeboxSection() -- initial state at build time -- correct even if ownership isn't known yet, since it just reads whatever getLatestState() has right now

	-- Close + Main Menu sit side by side along the bottom edge (was just
	-- Close, centered) -- 140px each with a 12px gap, the pair centered as
	-- a unit: [-146, -6] and [6, 146] around the panel's horizontal middle.
	local settingsMainMenuButton = Instance.new("TextButton")
	settingsMainMenuButton.Size = UDim2.new(0, 140, 0, 40)
	settingsMainMenuButton.Position = UDim2.new(0.5, -146, 1, -50)
	settingsMainMenuButton.Font = Enum.Font.GothamBold
	settingsMainMenuButton.TextSize = 16
	settingsMainMenuButton.Text = "Main Menu"
	settingsMainMenuButton.BackgroundColor3 = Color3.fromRGB(70, 45, 25)
	settingsMainMenuButton.TextColor3 = Color3.fromRGB(250, 240, 220)
	settingsMainMenuButton.ZIndex = 21
	settingsMainMenuButton.Parent = settingsPanel
	polishButton(settingsMainMenuButton, 12)
	addButtonHoverScale(settingsMainMenuButton)

	local settingsCloseButton = Instance.new("TextButton")
	settingsCloseButton.Size = UDim2.new(0, 140, 0, 40)
	settingsCloseButton.Position = UDim2.new(0.5, 6, 1, -50)
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

	-- Mirrors menuPlayButton's handler in init.client.lua in reverse: hide
	-- root, show menuFrame, only once the panel has actually finished
	-- fading out (popOut's onHidden), same as RunSetup's Begin Run handoff.
	settingsMainMenuButton.MouseButton1Click:Connect(function()
		playClickSfx()
		popOut(settingsBackdrop, settingsPanel, nil, function()
			root.Visible = false
			menuFrame.Visible = true
		end)
	end)

	OverlayManager.register("settings", function()
		popOut(settingsBackdrop, settingsPanel)
	end)

	settingsButton.MouseButton1Click:Connect(function()
		playClickSfx()
		OverlayManager.closeAllExcept("settings")
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
