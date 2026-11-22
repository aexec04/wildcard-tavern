--[[
	Client/Sound.lua
	All audio setup for the client: background music, the SFX asset-ID
	table, a pooled-Sound-instance system so playSfx() never has to
	Instance.new() (and reload) a fresh Sound on every single click, and the
	loud/quiet/muted volume-cycling state used by the corner volume button.

	Extracted out of init.client.lua as part of splitting the client script
	into smaller, per-feature files. This is genuinely foundational --
	nearly every other module in the client takes playSfx/playClickSfx/
	SOUND_IDS as deps -- so it's required first, before anything else that
	needs sound.

	Real asset IDs, picked from the batch Ahmed found. backgroundMusic's
	default is just a placeholder pick (a later feature might let players
	choose/upload their own background tracks, maybe gamepass-gated -- not
	this week's scope, this is just something to hear for now).

	Unused alternates from the same batch, in case you want to swap later:
	  Shop-Buy (alt):    rbxassetid://117518868636544
	  Sears-Washing-Machine-8 (click alt): rbxassetid://9118892323
	  Falling-Down (music alt):    rbxassetid://122884689708268
	  Celestial-Walk (music alt, has a loud sax -- Ahmed didn't like it): rbxassetid://1836047913

	SCORING JUICE (added this pass): background music now SWITCHES between
	4 tracks depending on where you are (see MUSIC_IDS/setMusicTrack below)
	instead of one track for the whole session, and there's a small set of
	dedicated, independently-pitchable Sound instances (chipTickSound/
	multTickSound/xmultTickSound/payoutThudSound) that Client/ScorePopup.lua
	uses to play an escalating-pitch tick per scoring event, ending on a
	pitched-down "thud". They're SEPARATE Sound instances from sfxPool on
	purpose -- sfxPool dedups by id string, and these need their own
	PlaybackSpeed independent of (e.g.) the plain, unpitched cardToggle
	click that can fire at the same time from an unrelated card-selection
	click.

	REAL SFX PASS (Phase 13): the 4 juice sounds above used to just reuse
	existing SOUND_IDS as placeholders (cardToggle/uiClick/playHand/
	discard) since Ahmed's original asset batch didn't include anything
	dedicated for Chip/Mult/XMult/Thud. They're now their own dedicated
	free Roblox catalog SFX (JUICE_SOUND_IDS below), picked to escalate in
	weight the same way the reveal sequence itself does -- a light crisp
	blip for Chip (plays most often, needs to stay quick), a slightly
	richer pickup ding for Mult, a rising "power up" tone for XMult (the
	rare, biggest-feeling tier), and a real impact hit for the
	pitched-down finale Thud. Picked sight-unseen (no Roblox runtime in
	this sandbox to actually hear them against the sequence) from a
	well-known free community SFX set on the Roblox library, same
	"placeholder now, confirm the real feel in Studio" caveat every prior
	audio pick in this project has shipped under -- if any of the 4 don't
	actually land once you can hear them against the real reveal timing,
	swap the id string for that slot below (or one of the alternates) and
	nothing else needs to change.

	POLISH (Phase 14): exactly that caveat played out for the Thud pick --
	see JUICE_SOUND_IDS.payoutThud's own comment below for what changed and
	why. Also added SOUND_IDS.gameOverWin/gameOverLoss this same pass
	(GameOver.lua played no sound at all on either outcome before).

	deps fields:
		SoundService -- the SoundService, service parent for every Sound instance

	Returns:
		{
			SOUND_IDS = table,
			JUICE_SOUND_IDS = table, -- { chipTick, multTick, xmultTick, payoutThud } -- real ids, see header comment
			MUSIC_IDS = table, -- { title, gameplay, boss, shop }
			backgroundMusic = Sound,
			isMusicUnavailable = function(), -- true if the current track failed/timed out loading (warn() already printed)
			onMusicAvailability = function(listener(unavailable)),
			setMusicTrack = function(key), -- key is a MUSIC_IDS key; no-op if already that track
			setCustomTrack = function(assetId), -- QoL Game Pass (Custom Jukebox): overrides every phase track with assetId, applies immediately
			clearCustomTrack = function(), -- drops the override; next setMusicTrack call falls back to the real phase track
			hasCustomTrack = function(), -- true if a Custom Jukebox override is currently active
			playSfx = function(soundId, volume?, maxLength?),
			playClickSfx = function(volume?),
			playPitched = function(sound, pitch?, volume?), -- for chipTickSound etc below
			chipTickSound = Sound,   -- dedicated Chip SFX (real id, see header comment)
			multTickSound = Sound,   -- dedicated Mult SFX
			xmultTickSound = Sound,  -- dedicated XMult SFX
			payoutThudSound = Sound, -- low "payout" thud, meant to be played pitched down
			VOLUME_ICONS = { "♪", "♩", "×" }, -- [1] playing, [3] muted
			volumeStepIndex = 1, -- starting icon index
			getSfxVolume = function(id) -> number, -- 0-1, the saved SFX volume (0 when muted)
			-- JUKEBOX AUTOPLAY/SHUFFLE/PRESETS (requested fix): see each one's
			-- own comment further down for the full story.
			PRESET_PLAYLISTS = table, -- { { name, songs = {assetId,...}, isReady }, ... }
			playPlaylistFrom = function(songList, startIndex, label, shuffle), -- starts/replaces the active queue
			setShuffleEnabled = function(enabled),
			getShuffleEnabled = function() -> boolean,
			isPlayingQueue = function() -> boolean, -- true while a queue (not just a single preview track) is active
			getQueueIndex = function() -> number|nil, -- 1-based position in the active queue
			getQueueLength = function() -> number, -- 0 if no queue active
			getQueueLabel = function() -> string|nil, -- "My Playlist" or a preset's name
		}
]]

return function(deps)
	local SoundService = deps.SoundService

	local SOUND_IDS = {
		backgroundMusic = "rbxassetid://132846105965979", -- gameplay track (MUSIC_IDS.gameplay reads this)
		cardToggle = "rbxassetid://9117308777",      -- Photo-Flapping-Handling-Movement-Rubbing-1-SFX
		playHand = "rbxassetid://9113727134",        -- Cash-Movement-2-SFX
		discard = "rbxassetid://9114035597",         -- Deck-Of-Cards-7-SFX
		buyPatron = "rbxassetid://128537772502751",  -- Buy
		roundReward = "rbxassetid://133292918309565", -- buy (alt) -- distinct "you got paid" cash sound for round-complete
		uiClick = "rbxassetid://9118728158",         -- Rotary-Switch-10-SFX
		-- POLISH (requested fix: "there is no losing sound, it just brings
		-- up this screen") -- GameOver.lua previously played NOTHING at all
		-- on either outcome. These 2 play once, gated by GameOver.lua's own
		-- existing lastGameOverKey check, so a fresh run-ending state gets a
		-- sound but sitting on the screen afterward doesn't replay it.
		gameOverWin = "rbxassetid://1170853519",  -- "New Item" -- short fanfare-ish sting, from the same free set as JUICE_SOUND_IDS below
		gameOverLoss = "rbxassetid://7381722902", -- "mouse_cancel" -- soft negative UI cue, same trusted set as chipTick's "mouse_select"
	}

	-- REAL SFX PASS (Phase 13): dedicated ids for the 4 juice sounds below,
	-- replacing the old SOUND_IDS-reuse placeholders. See the header
	-- comment for how each was picked; alternates from the same free
	-- community set are listed in case a slot needs a different feel once
	-- it's actually heard in Studio.
	local JUICE_SOUND_IDS = {
		chipTick = "rbxassetid://7381722372",   -- mouse_select -- short, crisp, plays most often
		multTick = "rbxassetid://7381723507",   -- pick_up -- a bit richer than chipTick's blip
		xmultTick = "rbxassetid://7381724959",  -- life_up -- rising power-up tone for the rare big tier
		-- POLISH (Phase 14 playtest feedback): "magic_bomb" (the original
		-- Phase 13 pick, id 7489673348) played pitched way down read as "way
		-- too aggressive, sounds like a kamehameha from dragon ball z" once
		-- actually heard against the finale beat -- an energy-blast-charge
		-- sound was never going to land as a calm "payout landing" no matter
		-- how it was pitched. Swapped for "cash register" -- a completely
		-- different sound FAMILY (a register chime, not an impact/explosion)
		-- that's thematically on-the-nose for a payout besides. The old
		-- heavy pitch-down (0.55x, tuned for warping an impact sound into a
		-- bass thud) no longer applies -- see the playPitched call in
		-- ScorePopup.lua's finale, now a much gentler 0.85x just to land it
		-- with a touch of weight, not to disguise what it originally was.
		payoutThud = "rbxassetid://131886985", -- cash register
	}
	-- Unused alternates from the same free set, in case a slot needs
	-- swapping once you can actually hear it against the reveal sequence:
	--   Chip:   mouse_hover  rbxassetid://7381721556 (even lighter/quieter)
	--   Mult:   pick_up2     rbxassetid://7381723941 (slightly bigger pickup)
	--   XMult:  New Item     rbxassetid://1170853519 (shorter fanfare-ish alt -- now used for SOUND_IDS.gameOverWin instead)
	--   Thud:   the original "magic_bomb" rbxassetid://7489673348 -- do NOT bring this back, see the comment above
	--           lever_shotgun_bolt rbxassetid://7411274148 (still an "impact" family sound -- try only if cash register also doesn't land)

	-- SCORING JUICE: 4 background tracks, switched by Client/init.client.lua's
	-- render() (gameplay/boss/shop, based on state.phase/state.bossModifier)
	-- and once at load for "title" (the main menu, before a run starts --
	-- see setMusicTrack below and its call site in init.client.lua). Picked
	-- from Ahmed's newest batch; alternates from that SAME batch are listed
	-- below each pick in case you want to swap -- same pattern as the
	-- backgroundMusic alternates above.
	-- Cue and music ids live in Shared/Engine/SoundIds.lua (menu = the title track; region_* keys are empty
	-- until picked and setMusicTrack skips empty ids). "title" stays as an alias of "menu".
	local SoundIds = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("SoundIds"))
	local TweenService = game:GetService("TweenService") -- the biome music crossfade
	local SoundFX = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("SoundFX")) -- pitch ladder, jitter, gate, ducking, layers
	local MUSIC_IDS = {
		title = SoundIds.Music.menu,
		gameplay = SOUND_IDS.backgroundMusic,        -- rbxassetid://132846105965979
		boss = SoundIds.Music.boss,
		shop = SoundIds.Music.shop,
	}
	for key, id in pairs(SoundIds.Music) do
		if MUSIC_IDS[key] == nil then
			MUSIC_IDS[key] = id
		end
	end
	-- Alternates (backup tracks, verified loadable), in case you want to swap:
	--   Title:    rbxassetid://116079409060113
	--   Gameplay: rbxassetid://93176902923482
	--   Boss:     rbxassetid://126739564081315
	--   Shop:     rbxassetid://128505516414181

	-- Music / SFX / mute come from Client/ClientSettings.lua (saved in the
	-- player's profile, set from Client/VolumePanel.lua). One SFX volume
	-- scales every sound effect; mute silences music and SFX together.
	local ClientSettings = require(script.Parent.ClientSettings)

	-- Studio Play has sound by default; SoundService attribute StudioAudio = false mutes it (not saved, live servers unaffected)
	local StudioAudio = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("StudioAudio"))
	local studioMuted = StudioAudio.shouldMute(game:GetService("RunService"):IsStudio(), SoundService:GetAttribute("StudioAudio"))
	if studioMuted then print("[Audio] studio muted by StudioAudio=false") end

	local function getSfxVolume(_id)
		if studioMuted or ClientSettings.get("muted") then
			return 0
		end
		return ClientSettings.get("sfxVolume") or 1
	end

	-- JUKEBOX PRESET PLAYLISTS (requested fix: "a couple preset playlist
	-- they can listen to if they can't be bothered" -- the "eventually"
	-- Ahmed explicitly deferred when the saved-playlist feature first
	-- shipped, now being picked up): a few curated, built-in playlists
	-- nobody has to paste a single id for. Each entry's `songs` list is
	-- real Roblox asset ids, same "rbxassetid://<digits>" shape as a saved
	-- playlist song -- EXCEPT every slot below is still the "rbxassetid://0"
	-- placeholder (same convention GamePasses.lua already uses for a Pass
	-- that doesn't exist on the Creator Dashboard yet): nobody has picked
	-- real tracks for these 3 moods yet. VolumePanel.lua checks isReady
	-- (every song non-placeholder) and shows "Coming Soon" instead of a
	-- Play button for a preset that isn't ready -- swap these ids for real
	-- ones (same source Ahmed pulled backgroundMusic's batch from, or
	-- anything else you're both allowed to use) and that preset activates
	-- with no other code changes anywhere.
	local PRESET_PLAYLISTS = {
		{
			name = "Lo-Fi Lounge",
			songs = {
				"rbxassetid://140722099430139",
				"rbxassetid://140653696800228",
				"rbxassetid://140658234151287",
				"rbxassetid://140627598377770",
				"rbxassetid://123516194124949",
				"rbxassetid://140628387917926",
				"rbxassetid://140653878167561",
				"rbxassetid://9047105533",
				"rbxassetid://140699797365730",
				"rbxassetid://139031824972373",
				"rbxassetid://140277562613590",
				"rbxassetid://114213622974713",
				"rbxassetid://9047104336",
				"rbxassetid://9046863253",
				"rbxassetid://140674665585340",
				"rbxassetid://140663385665720",
			},
		},
		{
			name = "Tavern Jigs",
			songs = { "rbxassetid://9039477366", "rbxassetid://9039478813", "rbxassetid://76040041327326" },
		},
		{
			name = "Late Night Jazz Cafe",
			songs = { "rbxassetid://83241783099960", "rbxassetid://127468148248456", "rbxassetid://103245181853642" },
		},
	}
	for _, preset in ipairs(PRESET_PLAYLISTS) do
		preset.isReady = true
		for _, id in ipairs(preset.songs) do
			if id == "rbxassetid://0" or not id then
				preset.isReady = false
				break
			end
		end
	end

	local backgroundMusic = Instance.new("Sound")
	backgroundMusic.Name = "BackgroundMusic"
	backgroundMusic.SoundId = MUSIC_IDS.gameplay
	backgroundMusic.Looped = true
	backgroundMusic.Parent = SoundService

	-- QoL Game Pass (Custom Jukebox, Phase 9): a player-supplied asset id
	-- that overrides whichever phase track would otherwise play. nil
	-- (the common case) means "no override, use MUSIC_IDS[key] like
	-- always." Session-scoped, same as every other per-run choice in this
	-- game (no persistent save yet) -- set/cleared from Client/VolumePanel.lua
	-- via setCustomTrack/clearCustomTrack below.
	local customTrackId = nil

	-- JUKEBOX AUTOPLAY/SHUFFLE (requested fix: "autoplay through playlist",
	-- "shuffle mode"): when a queue is active, playlistQueue is a snapshot
	-- copy of whatever list is currently playing (either the player's saved
	-- customPlaylist, or a built-in preset -- see VolumePanel.lua), nil
	-- otherwise. playlistIndex is 1-based into that snapshot. playlistLabel
	-- is just a display string ("My Playlist" or the preset's name) so the
	-- UI can show what's playing without having to re-derive it.
	-- shuffleEnabled only matters while a queue is active, but is kept as
	-- its own toggle (not reset per-queue) so flipping it once sticks
	-- across switching between "My Playlist" and a preset.
	local playlistQueue = nil
	local playlistIndex = 0
	local playlistLabel = nil
	local shuffleEnabled = false

	-- Tracks the actual RESOLVED asset id currently loaded (not the phase
	-- key) so repeated calls that land on the same real track -- including
	-- every phase key collapsing onto the SAME custom override while one's
	-- active -- don't restart it from the beginning every time.
	local currentTrackId = nil
	-- Tracks the most recent phase KEY actually requested (regardless of
	-- whether a custom override was active at the time) -- clearCustomTrack
	-- below replays this so Reset snaps straight back to the correct phase
	-- track immediately, instead of silently keeping the custom track
	-- playing until the next unrelated render() call happens to fire.
	local lastRequestedKey = "gameplay"
	-- BIOME MUSIC: moving between gameplay-table tracks (the plain gameplay track and the per-biome ones in
	-- SoundIds.Music) fades out, swaps, fades in. The fade runs on a SoundGroup so the Music slider and Mute,
	-- which set backgroundMusic.Volume, are never touched. A biome with no track id keeps the current track.
	local fadeGroup = Instance.new("SoundGroup")
	fadeGroup.Name = "MusicFade"
	fadeGroup.Parent = SoundService
	backgroundMusic.SoundGroup = fadeGroup
	local fadeToken = 0
	local FADE_TIME = 0.5
	local function swapTo(id)
		currentTrackId = id
		local wasPlaying = backgroundMusic.IsPlaying
		backgroundMusic.SoundId = id
		-- Respect the volume button's current mute state -- only actually
		-- start playback if it was already playing (i.e. not muted), same
		-- as every other volume-aware Play() call in this file.
		if wasPlaying or backgroundMusic.Volume > 0 then
			backgroundMusic:Play()
		end
	end
	-- Bed crossfade (Engine/MusicMix): stepped volume on the fade group, never a tween, so Calm mode and Reduce motion get the
	-- same fade in fewer, bigger steps; `bedGain` is the screen's share (the Night map and Run Over beds are quieter).
	local MusicMix = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("MusicMix"))
	local bedGain = 1
	local function stepFade(from, to, calm, token, done)
		local list = MusicMix.fade(calm)
		local dt = MusicMix.stepTime(calm)
		task.spawn(function()
			for i, pair in ipairs(list) do
				if token ~= fadeToken then return end -- a newer request took over
				fadeGroup.Volume = from + (to - from) * (to > from and pair[2] or 1 - pair[1])
				task.wait(dt)
			end
			if token == fadeToken and done then done() end
		end)
	end
	local function setMusicTrack(key, gain)
		local previousKey = lastRequestedKey
		lastRequestedKey = key
		local id = customTrackId or MUSIC_IDS[key]
		if not id or id == "" then
			return
		end
		local newGain = gain or 1
		if id == currentTrackId then
			if MusicMix.needsLevelStep(fadeGroup.Volume, bedGain, newGain) then -- same song, new screen (or a cut short fade): only the bed's level changes, stepped
				bedGain = newGain
				fadeToken += 1
				stepFade(fadeGroup.Volume, bedGain, ClientSettings.get("reduceMotion") == true, fadeToken)
			end
			return
		end
		fadeToken += 1
		local mine = fadeToken
		local calm = ClientSettings.get("reduceMotion") == true
		if currentTrackId ~= nil and not customTrackId and MusicMix.shouldFade(previousKey, key) then
			local startVolume = fadeGroup.Volume
			stepFade(startVolume, 0, calm, mine, function()
				swapTo(id)
				bedGain = newGain
				stepFade(0, bedGain, calm, mine)
			end)
		else
			bedGain = newGain
			fadeGroup.Volume = bedGain
			swapTo(id)
		end
	end

	-- JUKEBOX AUTOPLAY/SHUFFLE: drops any active queue and goes back to
	-- Looped = true (a single song on repeat) -- the behavior every
	-- single-track path (setCustomTrack, clearCustomTrack, setMusicTrack)
	-- has always had. Called at the START of setCustomTrack so pasting in
	-- a one-off preview track (the Jukebox text box's "Add to Playlist")
	-- always interrupts/replaces whatever queue was playing, same as it
	-- always interrupted whatever single track was playing before.
	local function stopPlaylistQueue()
		playlistQueue = nil
		playlistIndex = 0
		playlistLabel = nil
		backgroundMusic.Looped = true
	end

	-- Shuffle: never immediately repeats the song that just finished
	-- (unless the queue only has 1 song, where that's unavoidable).
	-- Sequential: wraps back to song 1 after the last one.
	local function pickNextQueueIndex()
		local len = playlistQueue and #playlistQueue or 0
		if len == 0 then
			return 1
		end
		if shuffleEnabled and len > 1 then
			local nextIndex = math.random(1, len)
			while nextIndex == playlistIndex do
				nextIndex = math.random(1, len)
			end
			return nextIndex
		end
		return (playlistIndex % len) + 1
	end

	-- Jumps the active queue to a specific 1-based index and plays it.
	-- Keeps customTrackId/currentTrackId in lockstep with the queue
	-- position -- setMusicTrack (driven by render() every phase change)
	-- resolves `customTrackId or MUSIC_IDS[key]`, so if these two ever
	-- drifted out of sync with what's actually loaded, the very next
	-- phase change would yank playback back to a stale track.
	local function playQueueIndex(index)
		if not playlistQueue or #playlistQueue == 0 then
			return
		end
		playlistIndex = index
		local id = playlistQueue[index]
		customTrackId = id
		currentTrackId = id
		backgroundMusic.SoundId = id
		backgroundMusic.Looped = false
		if backgroundMusic.Volume > 0 then
			backgroundMusic:Play()
		end
	end

	-- JUKEBOX AUTOPLAY (requested fix: "it plays through your whole saved
	-- playlist in order ... like a real playlist"): songList is either the
	-- player's saved customPlaylist (from latestState, see VolumePanel.lua)
	-- or a built-in preset's song list -- either way, snapshotted into a
	-- fresh table here so a later add/remove to the player's real playlist
	-- mid-playback can't mutate the queue already in flight out from under
	-- it. startIndex lets "▶ Play" on one specific row start the queue
	-- there instead of always at song 1.
	local function playPlaylistFrom(songList, startIndex, label, shuffle)
		if not songList or #songList == 0 then
			return
		end
		local snapshot = {}
		for i, id in ipairs(songList) do
			snapshot[i] = id
		end
		playlistQueue = snapshot
		playlistLabel = label
		shuffleEnabled = shuffle or false
		local clampedStart = startIndex or 1
		if clampedStart < 1 then
			clampedStart = 1
		elseif clampedStart > #snapshot then
			clampedStart = #snapshot
		end
		playQueueIndex(clampedStart)
	end

	local function setShuffleEnabled(enabled)
		shuffleEnabled = enabled
	end

	local function getShuffleEnabled()
		return shuffleEnabled
	end

	local function isPlayingQueue()
		return playlistQueue ~= nil
	end

	local function getQueueIndex()
		return playlistQueue and playlistIndex or nil
	end

	local function getQueueLength()
		return playlistQueue and #playlistQueue or 0
	end

	local function getQueueLabel()
		return playlistLabel
	end

	-- Fires only when a sound finishes PLAYING THROUGH on its own (never
	-- fires for a Looped sound, which is every single-track path) -- so
	-- this is exclusively the "one queued song just finished" signal, and
	-- only ever actually advances anything while playlistQueue is active.
	backgroundMusic.Ended:Connect(function()
		if playlistQueue then
			playQueueIndex(pickNextQueueIndex())
		end
	end)

	-- setCustomTrack applies immediately (doesn't wait for the next
	-- render()-driven setMusicTrack call) so hitting Play in the Jukebox
	-- feels instant. clearCustomTrack (below) replays lastRequestedKey
	-- through setMusicTrack for the same reason -- Reset shouldn't have to
	-- wait on the next unrelated state push to actually take effect.
	local function setCustomTrack(assetId)
		stopPlaylistQueue()
		customTrackId = assetId
		currentTrackId = assetId
		local wasPlaying = backgroundMusic.IsPlaying
		backgroundMusic.SoundId = assetId
		if wasPlaying or backgroundMusic.Volume > 0 then
			backgroundMusic:Play()
		end
	end

	local function clearCustomTrack()
		stopPlaylistQueue()
		customTrackId = nil
		currentTrackId = nil
		setMusicTrack(lastRequestedKey) -- reapply immediately, don't wait for the next render()
	end

	-- FEATURE 3: cycle loud -> quiet -> muted, free for everyone (no paywall).
	-- Tuned down from the original { 0.5, 0.2, 0 } -- 0.5 came in hot on
	-- most people's volume/headphones, and the Settings slider (see
	-- Client/Settings.lua) is the real, fine-grained control now anyway --
	-- this is just a saner out-of-the-box "loud" step.
	local VOLUME_ICONS = { "♪", "♩", "×" }

	-- Applies the saved music volume / mute to backgroundMusic, starting or
	-- stopping it as it crosses 0 (same rule every Play() call here uses).
	local function applyMusicVolume()
		local volume = (studioMuted or ClientSettings.get("muted")) and 0 or (ClientSettings.get("musicVolume") or 0)
		backgroundMusic.Volume = volume
		if volume <= 0 then
			backgroundMusic:Stop()
		elseif backgroundMusic.SoundId ~= "rbxassetid://0" and not backgroundMusic.IsPlaying then
			backgroundMusic:Play()
		end
	end
	backgroundMusic.Volume = studioMuted and 0 or ClientSettings.get("musicVolume")
	ClientSettings.onChanged(function(key)
		if key == "musicVolume" or key == "muted" then
			applyMusicVolume()
		end
	end)

	-- One persistent Sound instance per SFX, created ONCE here and reused for
	-- every play, instead of Instance.new()'ing (and loading) a brand new Sound
	-- every single click. That repeated create+load was the real source of the
	-- "still delayed, not instant" symptom -- PreloadAsync warms the asset
	-- cache, but a fresh Sound object still has to resolve/initialize against
	-- that asset each time you make one, and that's what was costing the delay.
	local sfxPool = {} -- soundId -> persistent Sound instance
	for _, id in pairs(SOUND_IDS) do
		if id and id ~= "rbxassetid://0" and not sfxPool[id] then
			local pooled = Instance.new("Sound")
			pooled.SoundId = id
			pooled.Parent = SoundService
			sfxPool[id] = pooled
		end
	end

	ClientSettings.onChanged(function(key)
		if key == "muted" and ClientSettings.get("muted") == true then -- Mute cuts the effects that are playing too
			for _, pooled in pairs(sfxPool) do pcall(function() pooled:Stop() end) end
		end
	end)

	-- SCORING JUICE: 4 dedicated Sound instances for Client/ScorePopup.lua's
	-- chip/mult/xmult/thud reveal sequence, using their own real ids
	-- (JUICE_SOUND_IDS above -- see the header comment for how they were
	-- picked). Deliberately NOT part of sfxPool even though sfxPool would
	-- otherwise dedup by asset id string just fine here -- sharing a
	-- pooled instance would mean every OTHER play of the same underlying
	-- clip elsewhere in the game fights over the same Sound's
	-- PlaybackSpeed as the escalating-pitch reveal sequence. Owning
	-- separate instances means their pitch is 100% independent.
	local chipTickSound = Instance.new("Sound")
	chipTickSound.Name = "ChipTick"
	chipTickSound.SoundId = JUICE_SOUND_IDS.chipTick
	chipTickSound.Parent = SoundService

	local multTickSound = Instance.new("Sound")
	multTickSound.Name = "MultTick"
	multTickSound.SoundId = JUICE_SOUND_IDS.multTick
	multTickSound.Parent = SoundService

	local xmultTickSound = Instance.new("Sound")
	xmultTickSound.Name = "XMultTick"
	xmultTickSound.SoundId = JUICE_SOUND_IDS.xmultTick
	xmultTickSound.Parent = SoundService

	local payoutThudSound = Instance.new("Sound")
	payoutThudSound.Name = "PayoutThud"
	payoutThudSound.SoundId = JUICE_SOUND_IDS.payoutThud -- meant to be played
	payoutThudSound.Parent = SoundService                 -- pitched WAY down -- see playPitched/header comment

	-- pitch (PlaybackSpeed): 1 = normal. `sound` should be one of the 4
	-- dedicated Sounds above (or any other Sound you don't mind restarting
	-- from the top and re-pitching). Doesn't use the maxLength/StopToken
	-- machinery playSfx has -- the score-reveal sequence controls its own
	-- timing between ticks, so nothing here needs to be force-cut short.
	local function playPitched(sound, pitch, volume)
		sound.PlaybackSpeed = pitch or 1
		-- SFX VOLUME SLIDERS: sound.SoundId reliably identifies which of the
		-- 4 dedicated juice sounds this is -- each is set once at creation
		-- above and never reassigned elsewhere -- so this reads the same
		-- per-sound multiplier the Settings panel's sliders write.
		sound.Volume = (volume or 0.5) * getSfxVolume(sound.SoundId)
		sound.TimePosition = 0
		sound:Play()
	end

	-- Preload every pooled Sound (plus the 4 dedicated juice sounds above)
	-- up front so the FIRST play doesn't have to wait on streaming it from
	-- the CDN. Wrapped in task.spawn so it can't block the rest of the UI
	-- from building while it loads.
	task.spawn(function()
		local ContentProvider = game:GetService("ContentProvider")
		local toPreload = { chipTickSound, multTickSound, xmultTickSound, payoutThudSound }
		for _, pooled in pairs(sfxPool) do
			table.insert(toPreload, pooled)
		end
		if #toPreload > 0 then
			pcall(function()
				ContentProvider:PreloadAsync(toPreload)
			end)
		end
	end)

	-- maxLength (optional): cuts the sound off after that many seconds instead
	-- of letting it play out fully -- some of the free SFX clips (card
	-- handling, etc.) have a longer tail than you want for a quick UI moment.
	-- The "StopToken" attribute guards the delayed Stop() against a newer
	-- overlapping play of the SAME pooled sound, so rapid-fire clicks can't
	-- have an old click's delayed Stop() cut off a brand new click's playback
	-- early.
	local function playSfx(soundId, volume, maxLength, startAt, fade)
		if not soundId or soundId == "" or soundId == "rbxassetid://0" then
			return -- placeholder id, nothing to play yet
		end
		local sfx = sfxPool[soundId]
		if not sfx then
			-- Fallback for any id not in SOUND_IDS at load time -- shouldn't
			-- normally happen, but keeps this safe against future one-off calls.
			sfx = Instance.new("Sound")
			sfx.SoundId = soundId
			sfx.Parent = SoundService
			sfxPool[soundId] = sfx
		end
		-- SFX VOLUME SLIDERS: scales whatever volume this call would have
		-- used anyway by this specific sound's own slider (Settings.lua),
		-- same shape as Master Volume scales backgroundMusic.
		sfx.Volume = (volume or 0.6) * getSfxVolume(soundId)
		sfx.TimePosition = startAt or 0 -- startAt skips a silent lead-in so the sound lands with the visual
		sfx:Play()
		if maxLength then
			local myToken = (sfx:GetAttribute("StopToken") or 0) + 1
			sfx:SetAttribute("StopToken", myToken)
			if fade and fade > 0 and fade < maxLength then -- fade the tail instead of a hard cut
				local startVol = sfx.Volume
				task.delay(maxLength - fade, function()
					if sfx:GetAttribute("StopToken") == myToken then
						pcall(function() TweenService:Create(sfx, TweenInfo.new(fade), { Volume = 0 }):Play() end)
					end
				end)
			end
			task.delay(maxLength, function()
				if sfx:GetAttribute("StopToken") == myToken then
					sfx:Stop()
				end
			end)
		end
	end

	-- ONE SHOT: a throw-away clone of the pooled Sound, so layers and rapid repeats of the same clip can overlap at their own pitch
	-- (the pooled instance restarts when played again). `speed` is PlaybackSpeed. The SFX slider and Mute apply through getSfxVolume.
	local function playOneShot(soundId, volume, speed, maxLength, startAt, fade)
		if not soundId or soundId == "" or soundId == "rbxassetid://0" then
			return
		end
		local base = sfxPool[soundId]
		if not base then
			base = Instance.new("Sound")
			base.SoundId = soundId
			base.Parent = SoundService
			sfxPool[soundId] = base
		end
		local shot = base:Clone()
		shot.Volume = (volume or 0.5) * getSfxVolume(soundId)
		shot.PlaybackSpeed = speed or 1
		shot.TimePosition = startAt or 0
		shot.Parent = SoundService
		shot:Play()
		local life = (maxLength or 4) / math.max(0.25, speed or 1)
		if fade and fade > 0 and maxLength and fade < maxLength then
			task.delay(math.max(0, life - fade), function()
				pcall(function() TweenService:Create(shot, TweenInfo.new(fade), { Volume = 0 }):Play() end)
			end)
		end
		task.delay(life + 0.1, function()
			pcall(function() shot:Stop() shot:Destroy() end)
		end)
		return shot
	end

	-- MUSIC DUCKING: a big beat (Legendary, True Wildcard, Four of a Kind or better, a boss defeat, a round win) lowers the music by about
	-- 4 dB for 1.2 s and eases it back over 0.6 s (Engine/SoundFX.duck). The way back reads the Music slider and Mute AT THAT TIME, so a
	-- slider moved during the duck is respected.
	local duckToken = 0
	local function duckMusic()
		if backgroundMusic.Volume <= 0 then
			return
		end
		duckToken = duckToken + 1
		local myToken = duckToken
		local function target()
			return (studioMuted or ClientSettings.get("muted")) and 0 or (ClientSettings.get("musicVolume") or 0)
		end
		local started = os.clock()
		task.spawn(function()
			while duckToken == myToken do
				local t = os.clock() - started
				backgroundMusic.Volume = target() * SoundFX.duck(t)
				if t >= SoundFX.DUCK_HOLD + SoundFX.DUCK_RELEASE then
					break
				end
				task.wait(0.05)
			end
			if duckToken == myToken then
				backgroundMusic.Volume = target()
			end
		end)
	end

	-- Named cue from SoundIds.Cues: per-cue volume (times `scale`, default 1) and max length, then the
	-- player's SFX slider/Mute inside playSfx. Unknown cues and cues with no id yet are skipped silently.
	-- Every cue has a minimum interval (hover 80 ms, the rest 30 ms, Engine/SoundFX). Card, button, hover, chip and coin cues get a little
	-- pitch (6 percent) and volume (8 percent) variation, never the same exact value twice in a row. Composite cues (Engine/SoundFX.Layers)
	-- play their layers, each at its own delay, pitch and volume, using only sounds that already load.
	local gate = SoundFX.newGate()
	-- SOUND DIRECTOR (Engine/SoundDirector): one fanfare at a time, at most 2 small voices, a 90 ms gap per group, a coin burst becomes one
	-- rising run, and a fanfare ducks the rest by 50 percent. Studio logs "[SoundDirector] voices=N" every time a sound starts.
	local director = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("SoundDirector")).new()
	local logVoices = game:GetService("RunService"):IsStudio()
	local fanfareShots = {} -- the Sounds of the fanfare that is playing, so a higher priority one can turn it down
	local lastPitch, lastVolume = {}, {}
	local failedWarned = {}
	local function cueDelay(delay, fn)
		if delay and delay > 0 then
			task.delay(delay, fn)
		else
			fn()
		end
	end
	local function playCue(name, scale, layerSpeed)
		if not gate:allow(name, os.clock()) then
			return
		end
		local layers = SoundFX.layersFor(name)
		-- a cue with no sound (an id-less single cue) is silent and must not take a voice
		if not layers and not SoundIds.cueId(name) then
			return
		end
		local verdict = director:request(name, os.clock())
		if not verdict.play then
			return
		end
		if verdict.cut then
			for _, shot in ipairs(fanfareShots) do
				pcall(function() shot.Volume = shot.Volume * 0.4 end) -- the cut fanfare keeps 40 percent (60 percent down)
			end
			fanfareShots = {}
		end
		if logVoices then
			print(string.format("[SoundDirector] voices=%d cue=%s group=%s", verdict.voices, name, verdict.group))
		end
		scale = (scale or 1) * verdict.scale
		layerSpeed = (layerSpeed or 1) * verdict.speed
		local isFanfare = verdict.group == "fanfare"
		if layers then
			for _, layer in ipairs(layers) do
				cueDelay(layer.delay, function()
					local cue = SoundIds.Cues[layer.cue]
					local id = SoundIds.cueId(layer.cue)
					if not id then
						return
					end
					local speed = (layer.speed or (layer.semis and SoundFX.semitone(layer.semis)) or 1) * verdict.speed
					local shot = playOneShot(id, (layer.volume or cue.volume or 0.5) * (scale or 1), speed, layer.maxLength or cue.maxLength, cue.startAt, layer.fade or cue.fade)
					if isFanfare and shot then fanfareShots[#fanfareShots + 1] = shot end
				end)
			end
			return
		end
		local id = SoundIds.cueId(name)
		local cue = SoundIds.Cues[name]
		local volume = (cue.volume or 0.5) * (scale or 1)
		if verdict.speed ~= 1 or layerSpeed ~= 1 then
			-- a rising coin tick needs its own pitch: play it as a one shot
			playOneShot(id, volume, layerSpeed, cue.maxLength or 0.6, cue.startAt, cue.fade)
			return
		end
		if SoundFX.JITTERED[name] then
			local rollP, rollV = math.random(), math.random()
			local speed = SoundFX.jitter(1, SoundFX.PITCH_JITTER, rollP, lastPitch[name])
			lastPitch[name] = speed
			volume = SoundFX.jitter(volume, SoundFX.VOLUME_JITTER, rollV, lastVolume[name])
			lastVolume[name] = volume
			playOneShot(id, volume, speed * (layerSpeed or 1), cue.maxLength, cue.startAt, cue.fade)
			return
		end
		playSfx(id, volume, cue.maxLength, cue.startAt, cue.fade)
		if isFanfare and sfxPool[id] then fanfareShots = { sfxPool[id] } end
	end

	-- The coin cascade: a few coins 60 ms apart at slightly different pitch (the payout landing).
	local function coinCascade(volume)
		local id = SoundIds.cueId("coin")
		if not id then
			return
		end
		for _, coin in ipairs(SoundFX.coinCascade(3)) do
			cueDelay(coin.delay, function()
				playOneShot(id, (volume or 0.35) * (1 - coin.delay), coin.speed, 0.8)
			end)
		end
	end

	-- A hand-type sting by tier (quiet for High Card and Pair up to the biggest for Full House, Four of a Kind, Straight Flush).
	local function playSting(handName)
		local tier = SoundFX.handSting(handName)
		for _, layer in ipairs(SoundFX.stingLayers(tier)) do
			cueDelay(layer.delay, function()
				local id = SoundIds.cueId(layer.cue)
				if id then
					playOneShot(id, layer.volume or 0.4, layer.speed or (layer.semis and SoundFX.semitone(layer.semis)) or 1, SoundIds.Cues[layer.cue].maxLength)
				end
			end)
		end
		if tier == "biggest" then
			duckMusic()
		end
		return tier
	end

	-- Studio audition (DebugGoto "sfx:<cue>" and "sfx:ladder"): plays a cue once, or an 8 step pitch ladder. A cue whose Sound fails to load or
	-- has no length is named in a warning, so the QA loop can see which one is dead.
	local function auditionCue(name)
		if name == "roundwin" then
			-- the whole Round Complete sound set in the order the game fires it (a score tick burst, the round stinger, the Round Complete coin run,
			-- the Counter greeting, then a True Wildcard lock in), so QA can count voices: each sound that starts logs "[SoundDirector] voices=N"
			local script_ = {
				{ 0.00, "chip" }, { 0.05, "chip" }, { 0.10, "chip" }, { 0.15, "coin" }, { 0.20, "win" }, { 0.25, "coin" }, { 0.30, "coin" },
				{ 0.35, "coin" }, { 0.40, "coin" }, { 0.45, "coin" }, { 0.50, "coin" }, { 0.60, "shop_enter" }, { 0.70, "card_deal" }, { 0.90, "button_click" },
				{ 1.50, "legendary_moment" }, { 1.60, "win" },
			}
			for _, step in ipairs(script_) do
				task.delay(step[1], function() playCue(step[2], 1) end)
			end
			return true
		end
		if name == "ladder" then
			local id = JUICE_SOUND_IDS.chipTick
			for n = 1, 8 do
				task.delay((n - 1) * 0.22, function()
					playOneShot(id, 0.4, SoundFX.ladderSpeed(n), 0.5)
				end)
			end
			return true
		end
		if not SoundIds.Cues[name] then
			warn("[Sound] audition: no cue named " .. tostring(name))
			return false
		end
		local ids = {}
		local layers = SoundFX.layersFor(name)
		if layers then
			for _, layer in ipairs(layers) do ids[#ids + 1] = SoundIds.cueId(layer.cue) end
		else
			ids[1] = SoundIds.cueId(name)
		end
		if #ids == 0 then
			warn("[Sound] audition: cue " .. name .. " has no id and no layers (silent on purpose)")
			return false
		end
		for _, id in ipairs(ids) do
			local probe = sfxPool[id]
			if probe then
				task.delay(1.2, function()
					if probe.TimeLength == 0 and not failedWarned[id] then
						failedWarned[id] = true
						warn(string.format("[Sound] cue %s: %s failed to load or has no length (TimeLength 0)", name, id))
					end
				end)
			end
		end
		playCue(name, 1)
		return true
	end

	-- SOUND_IDS.uiClick (Rotary-Switch-10-SFX) has two audible clicks baked
	-- into the clip itself -- for a snappy UI button we only want the first
	-- one, so every generic click plays through this instead of calling
	-- playSfx(SOUND_IDS.uiClick, ...) directly.
	-- 0.15s cut it off too close to the sound's own startup latency, so on some
	-- clicks (e.g. the "not enough tips" error click) it ended up basically
	-- inaudible -- 0.25s gives it more room to actually be heard before the cut.
	local function playClickSfx(volume)
		playSfx(SOUND_IDS.uiClick, volume, 0.25)
	end

	-- MUSIC LOAD WATCH: warns (naming the id) when the current music track
	-- has a malformed id, fails to fetch, or never fires Loaded within
	-- MUSIC_LOAD_TIMEOUT seconds, and tells listeners (the corner music
	-- button) so it can show a disabled look. Runs on every SoundId change,
	-- so phase tracks, the Jukebox and playlists are all covered. It never
	-- changes which track plays.
	local MUSIC_LOAD_TIMEOUT = 6
	local musicUnavailable = false
	local musicListeners = {}
	local musicWatchToken = 0
	local function setMusicUnavailable(value)
		if musicUnavailable == value then
			return
		end
		musicUnavailable = value
		for _, listener in ipairs(musicListeners) do
			task.spawn(listener, value)
		end
	end
	local function watchMusicLoad()
		musicWatchToken = musicWatchToken + 1
		local token = musicWatchToken
		local id = backgroundMusic.SoundId
		local function fail(reason)
			if token ~= musicWatchToken or backgroundMusic.IsLoaded then
				return
			end
			warn(string.format("[Sound] Music track %q %s", id, reason))
			setMusicUnavailable(true)
		end
		if not string.match(id, "^rbxassetid://%d+$") then
			fail("is not in the rbxassetid://<number> form")
			return
		end
		if id == "rbxassetid://0" then
			fail("is the placeholder id (no track assigned)")
			return
		end
		if backgroundMusic.IsLoaded then
			setMusicUnavailable(false)
			return
		end
		local loadedConnection
		loadedConnection = backgroundMusic.Loaded:Connect(function()
			loadedConnection:Disconnect()
			if token == musicWatchToken then
				setMusicUnavailable(false)
			end
		end)
		task.spawn(function()
			pcall(function()
				game:GetService("ContentProvider"):PreloadAsync({ backgroundMusic }, function(_, status)
					if status == Enum.AssetFetchStatus.Failure then
						fail("failed to load (check the asset exists and this experience has permission to use it)")
					end
				end)
			end)
		end)
		task.delay(MUSIC_LOAD_TIMEOUT, function()
			fail(string.format("did not load within %d seconds", MUSIC_LOAD_TIMEOUT))
		end)
	end
	backgroundMusic:GetPropertyChangedSignal("SoundId"):Connect(watchMusicLoad)
	watchMusicLoad()

	return {
		SOUND_IDS = SOUND_IDS,
		JUICE_SOUND_IDS = JUICE_SOUND_IDS,
		MUSIC_IDS = MUSIC_IDS,
		backgroundMusic = backgroundMusic,
		isMusicUnavailable = function()
			return musicUnavailable
		end,
		onMusicAvailability = function(listener) -- listener(unavailable: boolean)
			table.insert(musicListeners, listener)
		end,
		setMusicTrack = setMusicTrack,
		setCustomTrack = setCustomTrack,
		clearCustomTrack = clearCustomTrack,
		hasCustomTrack = function()
			return customTrackId ~= nil
		end,
		playSfx = playSfx,
		playCue = playCue,
		playOneShot = playOneShot,
		coinCascade = coinCascade,
		playSting = playSting,
		duckMusic = duckMusic,
		auditionCue = auditionCue,
		SoundIds = SoundIds,
		playClickSfx = playClickSfx,
		playPitched = playPitched,
		chipTickSound = chipTickSound,
		multTickSound = multTickSound,
		xmultTickSound = xmultTickSound,
		payoutThudSound = payoutThudSound,
		VOLUME_ICONS = VOLUME_ICONS,
		volumeStepIndex = 1, -- starting icon index into VOLUME_ICONS
		getSfxVolume = getSfxVolume,
		-- JUKEBOX AUTOPLAY/SHUFFLE/PRESETS:
		PRESET_PLAYLISTS = PRESET_PLAYLISTS,
		playPlaylistFrom = playPlaylistFrom,
		setShuffleEnabled = setShuffleEnabled,
		getShuffleEnabled = getShuffleEnabled,
		isPlayingQueue = isPlayingQueue,
		getQueueIndex = getQueueIndex,
		getQueueLength = getQueueLength,
		getQueueLabel = getQueueLabel,
	}
end
