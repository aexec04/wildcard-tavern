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

	deps fields:
		SoundService -- the SoundService, service parent for every Sound instance

	Returns:
		{
			SOUND_IDS = table,
			backgroundMusic = Sound,
			playSfx = function(soundId, volume?, maxLength?),
			playClickSfx = function(volume?),
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

	local backgroundMusic = Instance.new("Sound")
	backgroundMusic.Name = "BackgroundMusic"
	backgroundMusic.SoundId = SOUND_IDS.backgroundMusic
	backgroundMusic.Looped = true
	backgroundMusic.Parent = SoundService

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

	-- Preload every pooled Sound up front so the FIRST play doesn't have to
	-- wait on streaming it from the CDN. Wrapped in task.spawn so it can't
	-- block the rest of the UI from building while it loads.
	task.spawn(function()
		local ContentProvider = game:GetService("ContentProvider")
		local toPreload = {}
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
		backgroundMusic = backgroundMusic,
		playSfx = playSfx,
		playClickSfx = playClickSfx,
		VOLUME_STEPS = VOLUME_STEPS,
		VOLUME_ICONS = VOLUME_ICONS,
		volumeStepIndex = volumeStepIndex,
	}
end
