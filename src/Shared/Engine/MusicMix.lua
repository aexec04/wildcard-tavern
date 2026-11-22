-- MusicMix: the rules of the music beds, pure and tested (Client/MusicMixFX plays them; Client/Sound owns the Sound objects).
-- Only existing ids are used (SoundIds.Music: menu, gameplay, shop, boss). One bed per screen, a short stepped crossfade between
-- beds, a tension layer on the last hand of a round when the score is under half the Target, and a win sting. At most 3 voices.
local MusicMix = {}

MusicMix.MAX_VOICES = 3
MusicMix.TENSION_BELOW = 0.5 -- the tension layer starts when the round score is under this share of the Target on the last hand
MusicMix.FADE_TIME = 1.0 -- seconds for a bed crossfade
MusicMix.STEPS, MusicMix.STEPS_CALM = 12, 4 -- volume steps in a crossfade (no tween either way; Calm uses fewer, bigger steps)
MusicMix.MIN_CLEAR_STEP = 0.01

-- the screen a state is on: "menu" (not in a run, the caller says so), "map", "table", "boss", "shop", "runover"
MusicMix.MAP_PHASES = { roundSelect = true, roundselect = true, road = true, map = true }
function MusicMix.screenOf(state, inMenu)
	if inMenu then return "menu" end
	if type(state) ~= "table" then return "table" end
	if state.runOver then return "runover" end
	if state.phase == "shop" then return "shop" end
	if MusicMix.MAP_PHASES[state.phase] then return "map" end
	if state.bossModifier then return "boss" end
	return "table"
end

-- the music key (a SoundIds.Music / Sound.lua MUSIC_IDS key) and the bed's gain per screen. The Night map is a quieter table bed,
-- Run Over a quieter menu bed; a Boss round keeps the boss track.
MusicMix.BEDS = {
	menu = { key = "title", gain = 1 },
	map = { key = "gameplay", gain = 0.6 },
	table = { key = "gameplay", gain = 1 },
	boss = { key = "boss", gain = 1 },
	shop = { key = "shop", gain = 1 },
	runover = { key = "title", gain = 0.6 },
}

-- bed for a screen; `regionKey` replaces "gameplay" on the table and map when the Night's region has its own track
function MusicMix.bedFor(screen, regionKey)
	local bed = MusicMix.BEDS[screen] or MusicMix.BEDS.table
	local key = bed.key
	if key == "gameplay" and type(regionKey) == "string" and regionKey ~= "" then key = regionKey end
	return { key = key, gain = bed.gain }
end

-- the tension layer: playing the last hand of a round with the score under half the Target (never on a won or finished round)
function MusicMix.tension(state)
	if type(state) ~= "table" or state.phase ~= "playing" or state.runOver or state.roundOver then return false end
	local target = tonumber(state.targetScore) or 0
	if target <= 0 or state.handsRemaining ~= 1 then return false end
	return (tonumber(state.roundScore) or 0) < target * MusicMix.TENSION_BELOW
end

-- gain of the tension layer on top of its bed (the boss track is already tense, so it adds nothing there)
function MusicMix.tensionGain(screen)
	if screen == "table" or screen == "map" then return 0.5 end
	return 0
end

-- the win sting is the existing "win" cue (Client/GameOver plays it once when a run is won); the mix only budgets its voice, and a
-- won Run Over keeps the bed at the quiet Run Over level so the sting stays on top
MusicMix.STING_CUE = "win"

-- Voices actually allowed to play. `want` = { bed = true, outgoing = bool, sting = bool, tension = bool } -> ordered list of names,
-- cut to MAX_VOICES by priority bed, sting, outgoing, tension (a crossfade or a sting costs the tension layer its voice).
MusicMix.PRIORITY = { "bed", "sting", "outgoing", "tension" }
function MusicMix.voices(want)
	local out = {}
	for _, name in ipairs(MusicMix.PRIORITY) do
		if want and want[name] and #out < MusicMix.MAX_VOICES then out[#out + 1] = name end
	end
	return out
end

-- Crossfade volumes as a list of { out, in } fractions, one per step, never a pop: out falls and in rises, equal power, last
-- step is { 0, 1 }. Calm gets fewer, larger steps (still gradual).
function MusicMix.fade(calm)
	local n = calm and MusicMix.STEPS_CALM or MusicMix.STEPS
	local list = {}
	for i = 1, n do
		local t = i / n
		list[i] = { math.cos(t * math.pi / 2), math.sin(t * math.pi / 2) }
	end
	list[n] = { 0, 1 }
	return list
end

-- seconds between steps
function MusicMix.stepTime(calm)
	return MusicMix.FADE_TIME / (calm and MusicMix.STEPS_CALM or MusicMix.STEPS)
end

-- final volume of a voice: the player's Music slider and Mute always win
function MusicMix.volume(musicVolume, muted, gain, fraction)
	if muted then return 0 end
	return math.max(0, tonumber(musicVolume) or 0) * (gain or 1) * (fraction or 1)
end

-- should a new bed crossfade? Any change of key while something plays; the same key never restarts
function MusicMix.shouldFade(fromKey, toKey)
	return fromKey ~= nil and toKey ~= nil and fromKey ~= toKey
end

-- same song asked for again: does the bed level need a step? A fade that was cut short leaves the level off the gain, so the
-- same key and gain still steps back up (otherwise the bed would stay quiet)
function MusicMix.needsLevelStep(currentVolume, bedGain, newGain)
	return newGain ~= bedGain or math.abs((tonumber(currentVolume) or 0) - newGain) > MusicMix.MIN_CLEAR_STEP
end

return MusicMix
