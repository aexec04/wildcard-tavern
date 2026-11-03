--[[
	Client/JukeboxSection.lua
	The Custom Jukebox block (QoL Game Pass "custom_jukebox"): locked
	"Get Pass" view for non-owners; for owners, a track id box, Shuffle,
	"My Playlist" (play/reorder/remove) and the Preset Playlists. Built into
	Settings > Audio (Client/Settings.lua). Ownership is re-checked on every
	refreshJukeboxSection() call, from latestState.ownedGamePassIds.

	deps fields:
		parent, layoutOrder  -- where the section frame goes (a UIListLayout list)
		isVisible            -- function() -> boolean, true while its panel is open
		polishButton, addButtonHoverScale, playClickSfx, showWarning
		GamePasses, MarketplaceService, player, getLatestState
		setCustomTrack, clearCustomTrack, hasCustomTrack -- see Sound.lua
		AddPlaylistSongRemote, RemovePlaylistSongRemote, MovePlaylistSongRemote
		MAX_PLAYLIST_SIZE
		PRESET_PLAYLISTS, playPlaylistFrom, setShuffleEnabled, getShuffleEnabled,
		isPlayingQueue, getQueueIndex, getQueueLength, getQueueLabel -- see Sound.lua

	Returns: { frame = Frame, refreshJukeboxSection = function() }
]]

return function(deps)
	local polishButton = deps.polishButton
	local addButtonHoverScale = deps.addButtonHoverScale
	local playClickSfx = deps.playClickSfx
	local showWarning = deps.showWarning
	local isVisible = deps.isVisible
	local GamePasses = deps.GamePasses
	local MarketplaceService = deps.MarketplaceService
	local player = deps.player
	local getLatestState = deps.getLatestState
	local setCustomTrack = deps.setCustomTrack
	local clearCustomTrack = deps.clearCustomTrack
	local hasCustomTrack = deps.hasCustomTrack
	local AddPlaylistSongRemote = deps.AddPlaylistSongRemote
	local RemovePlaylistSongRemote = deps.RemovePlaylistSongRemote
	local MovePlaylistSongRemote = deps.MovePlaylistSongRemote
	local MAX_PLAYLIST_SIZE = deps.MAX_PLAYLIST_SIZE
	local PRESET_PLAYLISTS = deps.PRESET_PLAYLISTS
	local playPlaylistFrom = deps.playPlaylistFrom
	local setShuffleEnabled = deps.setShuffleEnabled
	local getShuffleEnabled = deps.getShuffleEnabled
	local isPlayingQueue = deps.isPlayingQueue
	local getQueueIndex = deps.getQueueIndex
	local getQueueLength = deps.getQueueLength
	local getQueueLabel = deps.getQueueLabel
	local RunService = game:GetService("RunService")

	-- ===== Custom Jukebox (QoL Game Pass; JUKEBOX PLAYLIST; JUKEBOX
	-- AUTOPLAY/SHUFFLE/PRESETS) =====
	-- LayoutOrder 1000 (not just "after the SFX rows") so a future catalog
	-- addition in Sound.lua can never accidentally push past this section
	-- without the fixed-height math below needing to change too. Grown
	-- from 300 to 440 to fit the Shuffle toggle, "Play All", reorder
	-- buttons, and the new Preset Playlists list below "My Playlist".
	local jukeboxSection = Instance.new("Frame")
	jukeboxSection.Size = UDim2.new(1, 0, 0, 440)
	jukeboxSection.BackgroundTransparency = 1
	jukeboxSection.LayoutOrder = deps.layoutOrder or 0
	jukeboxSection.ZIndex = 21
	jukeboxSection.Parent = deps.parent

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
	jukeboxUnlockedFrame.Size = UDim2.new(1, 0, 0, 410)
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

	-- "Add to Playlist" SAVES it to this player's persistent playlist
	-- (fires AddPlaylistSongRemote, see Shared/Engine/PlayerProfile.lua's
	-- addPlaylistSong), so it shows up in "My Playlist" below and survives
	-- a rejoin, while still playing it immediately too for instant feedback.
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
	jukeboxStatusLabel.Size = UDim2.new(1, -110, 0, 22)
	jukeboxStatusLabel.Position = UDim2.new(0, 0, 0, 112)
	jukeboxStatusLabel.BackgroundTransparency = 1
	jukeboxStatusLabel.Font = Enum.Font.Gotham
	jukeboxStatusLabel.TextSize = 12
	jukeboxStatusLabel.TextWrapped = true
	jukeboxStatusLabel.TextXAlignment = Enum.TextXAlignment.Left
	jukeboxStatusLabel.TextColor3 = Color3.fromRGB(150, 220, 160)
	jukeboxStatusLabel.Text = ""
	jukeboxStatusLabel.ZIndex = 21
	jukeboxStatusLabel.Parent = jukeboxUnlockedFrame

	-- JUKEBOX SHUFFLE (requested fix: "a shuffle toggle that plays your
	-- saved songs in random order"): a simple on/off toggle, not per-queue
	-- -- flipping it once sticks whether you're playing "My Playlist" or a
	-- preset next (see Sound.lua's shuffleEnabled, which this just mirrors
	-- into button text).
	local shuffleToggleButton = Instance.new("TextButton")
	shuffleToggleButton.Size = UDim2.new(0, 104, 0, 24)
	shuffleToggleButton.Position = UDim2.new(1, -104, 0, 110)
	shuffleToggleButton.Font = Enum.Font.GothamBold
	shuffleToggleButton.TextSize = 12
	shuffleToggleButton.Text = "🔀 Shuffle: Off"
	shuffleToggleButton.BackgroundColor3 = Color3.fromRGB(90, 60, 30)
	shuffleToggleButton.TextColor3 = Color3.fromRGB(250, 240, 220)
	shuffleToggleButton.ZIndex = 21
	shuffleToggleButton.Parent = jukeboxUnlockedFrame
	polishButton(shuffleToggleButton, 8)
	addButtonHoverScale(shuffleToggleButton)

	-- Forward-declared (used by refreshJukeboxStatus below, defined after
	-- it) -- the button's own text needs the same "which queue/index" read
	-- refreshJukeboxStatus already does, so this just folds into it
	-- instead of needing a second, separately-triggered update function.
	local function refreshJukeboxStatus()
		shuffleToggleButton.Text = (getShuffleEnabled and getShuffleEnabled()) and "🔀 Shuffle: On" or "🔀 Shuffle: Off"
		if isPlayingQueue and isPlayingQueue() then
			local label = (getQueueLabel and getQueueLabel()) or "your playlist"
			local index = (getQueueIndex and getQueueIndex()) or 1
			local total = (getQueueLength and getQueueLength()) or 0
			jukeboxStatusLabel.TextColor3 = Color3.fromRGB(150, 220, 160)
			jukeboxStatusLabel.Text = string.format("Playing %s -- track %d/%d", label, math.floor(index), math.floor(total))
		elseif hasCustomTrack and hasCustomTrack() then
			jukeboxStatusLabel.TextColor3 = Color3.fromRGB(150, 220, 160)
			jukeboxStatusLabel.Text = "Now playing your custom track."
		else
			jukeboxStatusLabel.TextColor3 = Color3.fromRGB(190, 175, 155)
			jukeboxStatusLabel.Text = "Using the built-in soundtrack."
		end
	end

	shuffleToggleButton.MouseButton1Click:Connect(function()
		playClickSfx()
		if setShuffleEnabled and getShuffleEnabled then
			setShuffleEnabled(not getShuffleEnabled())
		end
		refreshJukeboxStatus()
	end)

	-- Keeps the "track i/n" status line live while a queue autoplays
	-- through on its own (Sound.lua advances it internally on each
	-- song's natural end -- nothing else tells this panel that happened),
	-- without needing a poll anywhere except while the panel/section is
	-- actually visible.
	RunService.Heartbeat:Connect(function()
		if isVisible() and jukeboxUnlockedFrame.Visible then
			refreshJukeboxStatus()
		end
	end)

	-- ===== My Playlist =====
	-- One row per saved song, each with its own Play/Remove -- rebuilt
	-- from scratch (destroy + recreate every row) on every refresh, same
	-- pattern Collection.lua/Themes.lua already use for their own
	-- server-driven lists, rather than trying to diff the old rows
	-- against the new list.
	local playlistHeaderLabel = Instance.new("TextLabel")
	playlistHeaderLabel.Size = UDim2.new(1, -80, 0, 18)
	playlistHeaderLabel.Position = UDim2.new(0, 0, 0, 142)
	playlistHeaderLabel.BackgroundTransparency = 1
	playlistHeaderLabel.Font = Enum.Font.GothamBold
	playlistHeaderLabel.TextSize = 13
	playlistHeaderLabel.TextXAlignment = Enum.TextXAlignment.Left
	playlistHeaderLabel.TextColor3 = Color3.fromRGB(255, 214, 130)
	playlistHeaderLabel.Text = "My Playlist"
	playlistHeaderLabel.ZIndex = 21
	playlistHeaderLabel.Parent = jukeboxUnlockedFrame

	-- JUKEBOX AUTOPLAY (requested fix): plays the whole saved playlist in
	-- order starting from song 1, instead of making the player click a
	-- specific row's own ▶ Play just to get the autoplay going.
	local playAllButton = Instance.new("TextButton")
	playAllButton.Size = UDim2.new(0, 76, 0, 20)
	playAllButton.Position = UDim2.new(1, -76, 0, 140)
	playAllButton.Font = Enum.Font.GothamBold
	playAllButton.TextSize = 11
	playAllButton.Text = "▶ Play All"
	playAllButton.BackgroundColor3 = Color3.fromRGB(70, 90, 60)
	playAllButton.TextColor3 = Color3.fromRGB(250, 240, 220)
	playAllButton.ZIndex = 21
	playAllButton.Parent = jukeboxUnlockedFrame
	polishButton(playAllButton, 6)
	addButtonHoverScale(playAllButton)

	local playlistScroll = Instance.new("ScrollingFrame")
	playlistScroll.Size = UDim2.new(1, 0, 0, 110)
	playlistScroll.Position = UDim2.new(0, 0, 0, 166)
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

	-- order/total (JUKEBOX AUTOPLAY/reorder): order is this row's 1-based
	-- position in the CURRENT playlist (matches its LayoutOrder); total is
	-- the playlist's current length -- both only needed to know whether
	-- the ▲/▼ buttons should be clickable (greyed out past either edge,
	-- same "Coming Soon"-style disabled look GamePasses buttons use) and
	-- so ▶ Play can start the autoplay queue AT this row instead of
	-- always from song 1.
	local function makePlaylistRow(order, assetId, total)
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, -12, 0, 26)
		row.Position = UDim2.new(0, 6, 0, 0)
		row.BackgroundTransparency = 1
		row.LayoutOrder = order
		row.ZIndex = 21
		row.Parent = playlistScroll

		local idLabel = Instance.new("TextLabel")
		idLabel.Size = UDim2.new(1, -168, 1, 0)
		idLabel.BackgroundTransparency = 1
		idLabel.Font = Enum.Font.Gotham
		idLabel.TextSize = 12
		idLabel.TextXAlignment = Enum.TextXAlignment.Left
		idLabel.TextTruncate = Enum.TextTruncate.AtEnd
		idLabel.TextColor3 = Color3.fromRGB(220, 210, 195)
		idLabel.Text = "🎵 " .. assetId
		idLabel.ZIndex = 21
		idLabel.Parent = row

		-- JUKEBOX REORDER (requested fix: "move songs up/down in My
		-- Playlist"): fires MovePlaylistSongRemote; the server is the one
		-- actually enforced (see PlayerProfile.movePlaylistSong), this is
		-- just so a button at either edge visibly can't be clicked instead
		-- of silently no-opping.
		local upButton = Instance.new("TextButton")
		upButton.Size = UDim2.new(0, 20, 0, 24)
		upButton.Position = UDim2.new(1, -164, 0, 1)
		upButton.Font = Enum.Font.GothamBold
		upButton.TextSize = 12
		upButton.Text = "▲"
		upButton.ZIndex = 21
		upButton.Parent = row
		polishButton(upButton, 6)

		local downButton = Instance.new("TextButton")
		downButton.Size = UDim2.new(0, 20, 0, 24)
		downButton.Position = UDim2.new(1, -140, 0, 1)
		downButton.Font = Enum.Font.GothamBold
		downButton.TextSize = 12
		downButton.Text = "▼"
		downButton.ZIndex = 21
		downButton.Parent = row
		polishButton(downButton, 6)

		if order <= 1 then
			upButton.AutoButtonColor = false
			upButton.BackgroundColor3 = Color3.fromRGB(55, 45, 35)
			upButton.TextColor3 = Color3.fromRGB(140, 130, 120)
		else
			upButton.BackgroundColor3 = Color3.fromRGB(90, 60, 30)
			upButton.TextColor3 = Color3.fromRGB(250, 240, 220)
			addButtonHoverScale(upButton)
			upButton.MouseButton1Click:Connect(function()
				playClickSfx()
				if MovePlaylistSongRemote then
					MovePlaylistSongRemote:FireServer(assetId, -1)
				end
			end)
		end

		if order >= total then
			downButton.AutoButtonColor = false
			downButton.BackgroundColor3 = Color3.fromRGB(55, 45, 35)
			downButton.TextColor3 = Color3.fromRGB(140, 130, 120)
		else
			downButton.BackgroundColor3 = Color3.fromRGB(90, 60, 30)
			downButton.TextColor3 = Color3.fromRGB(250, 240, 220)
			addButtonHoverScale(downButton)
			downButton.MouseButton1Click:Connect(function()
				playClickSfx()
				if MovePlaylistSongRemote then
					MovePlaylistSongRemote:FireServer(assetId, 1)
				end
			end)
		end

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

		-- JUKEBOX AUTOPLAY: used to just setCustomTrack(assetId) (loop
		-- this one song forever) -- now starts the whole saved playlist
		-- autoplaying, beginning at THIS row, so clicking Play on song 3
		-- plays 3, then 4, then 5, ... wrapping back to 1, instead of
		-- just looping song 3 alone.
		rowPlayButton.MouseButton1Click:Connect(function()
			playClickSfx()
			local latest = getLatestState and getLatestState()
			local playlist = (latest and latest.customPlaylist) or {}
			playPlaylistFrom(playlist, order, "My Playlist", getShuffleEnabled and getShuffleEnabled())
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
			makePlaylistRow(i, assetId, #playlist)
		end
	end

	-- JUKEBOX AUTOPLAY: starts the whole saved playlist from song 1 --
	-- the same thing clicking row 1's own ▶ Play does, just without
	-- having to scroll to find it.
	playAllButton.MouseButton1Click:Connect(function()
		playClickSfx()
		local latest = getLatestState and getLatestState()
		local playlist = (latest and latest.customPlaylist) or {}
		if #playlist == 0 then
			showWarning("Add a song to your playlist first.")
			return
		end
		playPlaylistFrom(playlist, 1, "My Playlist", getShuffleEnabled and getShuffleEnabled())
		refreshJukeboxStatus()
	end)

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

	-- ===== Preset Playlists (JUKEBOX PRESETS, requested fix: "a couple
	-- preset playlist they can listen to if they can't be bothered") =====
	-- Built ONCE here (not rebuilt per refresh, same reasoning as
	-- jukeboxActionButton above) -- Sound.lua's PRESET_PLAYLISTS is a
	-- fixed, built-in list for the whole session, nothing about it is
	-- player-specific or server-driven, so there's nothing to re-check on
	-- every panel open the way ownership/My Playlist need.
	local presetHeaderLabel = Instance.new("TextLabel")
	presetHeaderLabel.Size = UDim2.new(1, 0, 0, 18)
	presetHeaderLabel.Position = UDim2.new(0, 0, 0, 284)
	presetHeaderLabel.BackgroundTransparency = 1
	presetHeaderLabel.Font = Enum.Font.GothamBold
	presetHeaderLabel.TextSize = 13
	presetHeaderLabel.TextXAlignment = Enum.TextXAlignment.Left
	presetHeaderLabel.TextColor3 = Color3.fromRGB(255, 214, 130)
	presetHeaderLabel.Text = "🎧 Preset Playlists"
	presetHeaderLabel.ZIndex = 21
	presetHeaderLabel.Parent = jukeboxUnlockedFrame

	local presetRowsContainer = Instance.new("Frame")
	presetRowsContainer.Size = UDim2.new(1, 0, 0, 94)
	presetRowsContainer.Position = UDim2.new(0, 0, 0, 306)
	presetRowsContainer.BackgroundTransparency = 1
	presetRowsContainer.ZIndex = 21
	presetRowsContainer.Parent = jukeboxUnlockedFrame

	local presetRowsLayout = Instance.new("UIListLayout")
	presetRowsLayout.Padding = UDim.new(0, 4)
	presetRowsLayout.Parent = presetRowsContainer

	-- A preset that still has its "rbxassetid://0" placeholder ids (see
	-- Sound.lua's own comment on PRESET_PLAYLISTS -- nobody's picked real
	-- tracks for these 3 moods yet) shows "Coming Soon" instead of a
	-- working Play button, same pattern GamePasses with gamePassId = 0
	-- already uses elsewhere in this file/Themes.lua -- swap in real ids
	-- there and this activates with no code change here at all.
	local function makePresetRow(order, preset)
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, 0, 0, 24)
		row.BackgroundTransparency = 1
		row.LayoutOrder = order
		row.ZIndex = 21
		row.Parent = presetRowsContainer

		local nameLabel = Instance.new("TextLabel")
		nameLabel.Size = UDim2.new(1, -90, 1, 0)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Font = Enum.Font.Gotham
		nameLabel.TextSize = 12
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
		nameLabel.TextColor3 = Color3.fromRGB(220, 210, 195)
		nameLabel.Text = string.format("%s (%d songs)", preset.name, #preset.songs)
		nameLabel.ZIndex = 21
		nameLabel.Parent = row

		local presetPlayButton = Instance.new("TextButton")
		presetPlayButton.Size = UDim2.new(0, 84, 0, 22)
		presetPlayButton.Position = UDim2.new(1, -84, 0, 1)
		presetPlayButton.Font = Enum.Font.GothamBold
		presetPlayButton.TextSize = 12
		presetPlayButton.ZIndex = 21
		presetPlayButton.Parent = row
		polishButton(presetPlayButton, 6)

		if preset.isReady then
			presetPlayButton.Text = "▶ Play"
			presetPlayButton.BackgroundColor3 = Color3.fromRGB(70, 90, 60)
			presetPlayButton.TextColor3 = Color3.fromRGB(250, 240, 220)
			addButtonHoverScale(presetPlayButton)
			presetPlayButton.MouseButton1Click:Connect(function()
				playClickSfx()
				playPlaylistFrom(preset.songs, 1, preset.name, getShuffleEnabled and getShuffleEnabled())
				refreshJukeboxStatus()
			end)
		else
			presetPlayButton.Text = "Coming Soon"
			presetPlayButton.AutoButtonColor = false
			presetPlayButton.BackgroundColor3 = Color3.fromRGB(55, 45, 35)
			presetPlayButton.TextColor3 = Color3.fromRGB(190, 175, 155)
		end
	end

	if PRESET_PLAYLISTS then
		for i, preset in ipairs(PRESET_PLAYLISTS) do
			makePresetRow(i, preset)
		end
	end

	-- Re-checks ownership; called every time Settings opens and from
	-- render() while it's open -- a purchase can complete asynchronously while
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
		-- Locked view is much shorter; don't leave a gap under it in the list.
		jukeboxSection.Size = UDim2.new(1, 0, 0, owned and 440 or 175)
		if owned then
			refreshJukeboxStatus()
			refreshPlaylistRows()
		end
	end
	refreshJukeboxSection() -- initial state at build time -- correct even if ownership isn't known yet, since it just reads whatever getLatestState() has right now

	return {
		frame = jukeboxSection,
		refreshJukeboxSection = refreshJukeboxSection,
	}
end
