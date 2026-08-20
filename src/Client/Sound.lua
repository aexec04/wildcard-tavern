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
	  Balatro-Shop-Buy:   rbxassetid://117518868636544
	  Sears-Washing-Machine-8 (click alt): rbxassetid://9118892323
	  Falling-Down (music alt):    rbxassetid://122884689708268
	  Celestial-Walk (music alt, has a loud sax -- Ahmed didn't like it): rbxassetid://1836047913

	SCORING JUICE (added this pass): background music now SWITCHES between
	4 tracks depending on where you are (see MUSIC_IDS/setMusicTrack below)
	instead of one track for the whole session, and there's a small set of
	dedicated, independently-pitchable Sound instances (chipTickSound/
	multTickSound/xmultTickSound/payoutThudSound) that Client/ScorePopup.lua
	uses to play an escalating-pitch tick per scoring event, ending on a
	pitched-down "thud". Ahmed's asset batch didn't include dedicated Chip/
	Mult/XMult/thud SFX, so -- per his own call when asked -- these reuse
	existing SFX ids as placeholders (clearly marked below) until real ones
	exist to swap in; same "placeholder now, swap the id string later"
	pattern this file already used for backgroundMusic. They're SEPARATE
	Sound instances from sfxPool on purpose, even where they share an
	asset id with an existing SOUND_IDS entry -- sfxPool dedups by id
	string, and these need their own PlaybackSpeed independent of (e.g.)
	the plain, unpitched cardToggle click that can fire at the same time
	from an unrelated card-selection click.

	deps fields:
		SoundService -- the SoundService, service parent for every Sound instance

	Returns:
		{
			SOUND_IDS = table,
			MUSIC_IDS = table, -- { title, gameplay, boss, shop }
			backgroundMusic = Sound,
			setMusicTrack = function(key), -- key is a MUSIC_IDS key; no-op if already that track
			playSfx = function(soundId, volume?, maxLength?),
			playClickSfx = function(volume?),
			playPitched = function(sound, pitch?, volume?), -- for chipTickSound etc below
			chipTickSound = Sound,   -- placeholder Chip SFX (see comment above)
			multTickSound = Sound,   -- placeholder Mult SFX
			xmultTickSound = Sound,  -- placeholder XMult SFX
			payoutThudSound = Sound, -- placeholder low "payout" thud, meant to be played pitched down
			VOLUME_STEPS = { 0.5, 0.2, 0 },
			VOLUME_ICONS = { "♪", "♩", "×" },
			volumeStepIndex = number, -- initial value (1); the caller owns
			                             mutating this as the volume button cycles
		}
]]

return function(deps)
	local SoundService = deps.SoundService

	local SOUND_IDS = {
		backgroundMusic = "rbxassetid://138172142909285", -- Retro-Impact-Zone (placeholder default, see above)
		cardToggle = "rbxassetid://9117308777",      -- Photo-Flapping-Handling-Movement-Rubbing-1-SFX
		playHand = "rbxassetid://9113727134",        -- Cash-Movement-2-SFX
		discard = "rbxassetid://9114035597",         -- Deck-Of-Cards-7-SFX
		buyPatron = "rbxassetid://128537772502751",  -- Buy
		roundReward = "rbxassetid://133292918309565", -- buy (alt) -- distinct "you got paid" cash sound for round-complete
		uiClick = "rbxassetid://9118728158",         -- Rotary-Switch-10-SFX
	}

	-- SCORING JUICE: 4 background tracks, switched by Client/init.client.lua's
	-- render() (gameplay/boss/shop, based on state.phase/state.bossModifier)
	-- and once at load for "title" (the main menu, before a run starts --
	-- see setMusicTrack below and its call site in init.client.lua). Picked
	-- from Ahmed's newest batch; alternates from that SAME batch are listed
	-- below each pick in case you want to swap -- same pattern as the
	-- backgroundMusic alternates above.
	local MUSIC_IDS = {
		title = "rbxassetid://120237941989190",    -- Warm Signals in Silence
		gameplay = SOUND_IDS.backgroundMusic,        -- Retro Impact Zone -- unchanged existing default
		boss = "rbxassetid://112062136718839",       -- Into Battle
		shop = "rbxassetid://71016453281056",        -- Rare Spawn
	}
	-- Unused alternates from the same batch, in case you want to swap later:
	--   Title:   Hollywood Romance rbxassetid://9045322793
	--            XVII Composition 1952 rbxassetid://122891883598211
	--            XV Composition 1947 rbxassetid://121483308829289
	--            Ambient Dreams rbxassetid://124567288309185
	--            Falling Down rbxassetid://122884689708268
	--            (Celestial Walk rbxassetid://1836047913 was in this same
	--            batch too, but skipped on purpose here -- see the
	--            "Ahmed didn't like it" note above, same track.)
	--   Boss:    Moonlight rbxassetid://9039974099
	--   Shop:    Guilty Pleasure rbxassetid://1842100660
	--            Ambient Dreams rbxassetid://124567288309185

	local backgroundMusic = Instance.new("Sound")
	backgroundMusic.Name = "BackgroundMusic"
	backgroundMusic.SoundId = MUSIC_IDS.gameplay
	backgroundMusic.Looped = true
	backgroundMusic.Parent = SoundService

	-- Tracks which MUSIC_IDS key is currently loaded, so repeated calls
	-- with the same key (e.g. every single render() while sitting in the
	-- shop) don't restart the track from the beginning every time.
	local currentMusicKey = "gameplay"
	local function setMusicTrack(key)
		if key == currentMusicKey then
			return
		end
		local id = MUSIC_IDS[key]
		if not id or id == "" then
			return
		end
		currentMusicKey = key
		local wasPlaying = backgroundMusic.IsPlaying
		backgroundMusic.SoundId = id
		-- Respect the volume button's current mute state -- only actually
		-- start playback if it was already playing (i.e. not muted), same
		-- as every other volume-aware Play() call in this file.
		if wasPlaying or backgroundMusic.Volume > 0 then
			backgroundMusic:Play()
		end
	end

	-- FEATURE 3: cycle loud -> quiet -> muted, free for everyone (no paywall).
	local VOLUME_STEPS = { 0.5, 0.2, 0 }
	local VOLUME_ICONS = { "♪", "♩", "×" }
	local volumeStepIndex = 1
	backgroundMusic.Volume = VOLUME_STEPS[volumeStepIndex]

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

	-- SCORING JUICE: 4 dedicated Sound instances for Client/ScorePopup.lua's
	-- chip/mult/xmult/thud reveal sequence. Deliberately NOT part of
	-- sfxPool -- sfxPool dedups by asset id string, and these reuse ids
	-- that already exist elsewhere in SOUND_IDS (see the placeholder note
	-- in this file's header comment), so sharing the pooled instance would
	-- mean every card-toggle/click/etc. play elsewhere fights over the
	-- same Sound's PlaybackSpeed as the escalating-pitch reveal sequence.
	-- Owning separate instances means their pitch is 100% independent.
	local chipTickSound = Instance.new("Sound")
	chipTickSound.Name = "ChipTick"
	chipTickSound.SoundId = SOUND_IDS.cardToggle -- placeholder -- see header comment
	chipTickSound.Parent = SoundService

	local multTickSound = Instance.new("Sound")
	multTickSound.Name = "MultTick"
	multTickSound.SoundId = SOUND_IDS.uiClick -- placeholder -- see header comment
	multTickSound.Parent = SoundService

	local xmultTickSound = Instance.new("Sound")
	xmultTickSound.Name = "XMultTick"
	xmultTickSound.SoundId = SOUND_IDS.playHand -- placeholder (Cash-Movement) -- see header comment
	xmultTickSound.Parent = SoundService

	local payoutThudSound = Instance.new("Sound")
	payoutThudSound.Name = "PayoutThud"
	payoutThudSound.SoundId = SOUND_IDS.discard -- placeholder (Deck-Of-Cards), meant to be played
	payoutThudSound.Parent = SoundService         -- pitched WAY down -- see playPitched/header comment

	-- pitch (PlaybackSpeed): 1 = normal. `sound` should be one of the 4
	-- dedicated Sounds above (or any other Sound you don't mind restarting
	-- from the top and re-pitching). Doesn't use the maxLength/StopToken
	-- machinery playSfx has -- the score-reveal sequence controls its own
	-- timing between ticks, so nothing here needs to be force-cut short.
	local function playPitched(sound, pitch, volume)
		sound.PlaybackSpeed = pitch or 1
		sound.Volume = volume or 0.5
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
	local function playSfx(soundId, volume, maxLength)
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
		sfx.Volume = volume or 0.6
		sfx.TimePosition = 0
		sfx:Play()
		if maxLength then
			local myToken = (sfx:GetAttribute("StopToken") or 0) + 1
			sfx:SetAttribute("StopToken", myToken)
			task.delay(maxLength, function()
				if sfx:GetAttribute("StopToken") == myToken then
					sfx:Stop()
				end
			end)
		end
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

	return {
		SOUND_IDS = SOUND_IDS,
		MUSIC_IDS = MUSIC_IDS,
		backgroundMusic = backgroundMusic,
		setMusicTrack = setMusicTrack,
		playSfx = playSfx,
		playClickSfx = playClickSfx,
		playPitched = playPitched,
		chipTickSound = chipTickSound,
		multTickSound = multTickSound,
		xmultTickSound = xmultTickSound,
		payoutThudSound = payoutThudSound,
		VOLUME_STEPS = VOLUME_STEPS,
		VOLUME_ICONS = VOLUME_ICONS,
		volumeStepIndex = volumeStepIndex,
	}
end
