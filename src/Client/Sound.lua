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
			VOLUME_STEPS = { 0.35, 0.15, 0 },
			VOLUME_ICONS = { "♪", "♩", "×" },
			volumeStepIndex = number, -- initial value (1); the caller owns
			                             mutating this as the volume button cycles
			SFX_CATALOG = table, -- { { label, id }, ... } -- see its own comment below
			getSfxVolume = function(id) -> number, -- 0-1, defaults to 1 (full)
			setSfxVolume = function(id, multiplier), -- 0-1
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
	local MUSIC_IDS = {
		title = "rbxassetid://122891883598211",    -- Warm Signals in Silence
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

	-- SFX VOLUME SLIDERS (requested fix: "adjust all the sound effects, not
	-- just music, so every sfx that we have, they can all be sliders"):
	-- before this, every playSfx/playPitched call used whatever volume the
	-- CALL SITE hardcoded (0.6 default, or a one-off override) with no way
	-- for the player to turn any of them up or down -- only backgroundMusic
	-- had a real slider (Settings.lua's Master Volume). Keyed by the actual
	-- asset id string (every SOUND_IDS/JUICE_SOUND_IDS entry is a distinct
	-- id, so this never collides), a multiplier that scales whatever volume
	-- a given play call would have used otherwise -- 1 (full, the default
	-- for anything never touched) down to 0 (silent), same 0-100% shape as
	-- Master Volume. Session-only, same as Master Volume and the Custom
	-- Jukebox override -- no persistent save for audio settings yet (see
	-- Settings.lua's own Custom Jukebox comment).
	local sfxVolumeMultipliers = {} -- [assetId] = multiplier, 0-1; missing = 1 (full)

	local function getSfxVolume(id)
		if not id then
			return 1
		end
		local multiplier = sfxVolumeMultipliers[id]
		if multiplier == nil then
			return 1
		end
		return multiplier
	end

	local function setSfxVolume(id, multiplier)
		if not id then
			return
		end
		sfxVolumeMultipliers[id] = multiplier
	end

	-- Ordered catalog for Settings.lua to build one slider row per SFX from
	-- -- label is what the player sees, id is the actual key into
	-- sfxVolumeMultipliers above. backgroundMusic is deliberately excluded
	-- (that's Master Volume, its own separate slider, not an "effect").
	-- chipTick/multTick/xmultTick/payoutThud are the 4 dedicated
	-- ScorePopup.lua reveal-sequence sounds (see playPitched below for how
	-- THEIR multiplier gets applied, since they're played by Sound instance
	-- rather than by id string).
	local SFX_CATALOG = {
		{ label = "Card Select", id = SOUND_IDS.cardToggle },
		{ label = "Play Hand", id = SOUND_IDS.playHand },
		{ label = "Discard", id = SOUND_IDS.discard },
		{ label = "Buy / Use", id = SOUND_IDS.buyPatron },
		{ label = "Round Reward", id = SOUND_IDS.roundReward },
		{ label = "UI Click", id = SOUND_IDS.uiClick },
		{ label = "Game Over (Win)", id = SOUND_IDS.gameOverWin },
		{ label = "Game Over (Loss)", id = SOUND_IDS.gameOverLoss },
		{ label = "Chip Tick", id = JUICE_SOUND_IDS.chipTick },
		{ label = "Mult Tick", id = JUICE_SOUND_IDS.multTick },
		{ label = "XMult Tick", id = JUICE_SOUND_IDS.xmultTick },
		{ label = "Payout Thud", id = JUICE_SOUND_IDS.payoutThud },
	}

	local backgroundMusic = Instance.new("Sound")
	backgroundMusic.Name = "BackgroundMusic"
	backgroundMusic.SoundId = MUSIC_IDS.gameplay
	backgroundMusic.Looped = true
	backgroundMusic.Parent = SoundService

	-- QoL Game Pass (Custom Jukebox, Phase 9): a player-supplied asset id
	-- that overrides whichever phase track would otherwise play. nil
	-- (the common case) means "no override, use MUSIC_IDS[key] like
	-- always." Session-scoped, same as every other per-run choice in this
	-- game (no persistent save yet) -- set/cleared from Client/Settings.lua
	-- via setCustomTrack/clearCustomTrack below.
	local customTrackId = nil

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
	local function setMusicTrack(key)
		lastRequestedKey = key
		local id = customTrackId or MUSIC_IDS[key]
		if not id or id == "" then
			return
		end
		if id == currentTrackId then
			return
		end
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

	-- setCustomTrack applies immediately (doesn't wait for the next
	-- render()-driven setMusicTrack call) so hitting Play in Settings
	-- feels instant. clearCustomTrack (below) replays lastRequestedKey
	-- through setMusicTrack for the same reason -- Reset shouldn't have to
	-- wait on the next unrelated state push to actually take effect.
	local function setCustomTrack(assetId)
		customTrackId = assetId
		currentTrackId = assetId
		local wasPlaying = backgroundMusic.IsPlaying
		backgroundMusic.SoundId = assetId
		if wasPlaying or backgroundMusic.Volume > 0 then
			backgroundMusic:Play()
		end
	end

	local function clearCustomTrack()
		customTrackId = nil
		currentTrackId = nil
		setMusicTrack(lastRequestedKey) -- reapply immediately, don't wait for the next render()
	end

	-- FEATURE 3: cycle loud -> quiet -> muted, free for everyone (no paywall).
	-- Tuned down from the original { 0.5, 0.2, 0 } -- 0.5 came in hot on
	-- most people's volume/headphones, and the Settings slider (see
	-- Client/Settings.lua) is the real, fine-grained control now anyway --
	-- this is just a saner out-of-the-box "loud" step.
	local VOLUME_STEPS = { 0.35, 0.15, 0 }
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
		-- SFX VOLUME SLIDERS: scales whatever volume this call would have
		-- used anyway by this specific sound's own slider (Settings.lua),
		-- same shape as Master Volume scales backgroundMusic.
		sfx.Volume = (volume or 0.6) * getSfxVolume(soundId)
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
		JUICE_SOUND_IDS = JUICE_SOUND_IDS,
		MUSIC_IDS = MUSIC_IDS,
		backgroundMusic = backgroundMusic,
		setMusicTrack = setMusicTrack,
		setCustomTrack = setCustomTrack,
		clearCustomTrack = clearCustomTrack,
		hasCustomTrack = function()
			return customTrackId ~= nil
		end,
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
		SFX_CATALOG = SFX_CATALOG,
		getSfxVolume = getSfxVolume,
		setSfxVolume = setSfxVolume,
	}
end
