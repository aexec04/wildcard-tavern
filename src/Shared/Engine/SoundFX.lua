--[[
	Shared/Engine/SoundFX.lua
	The pure rules behind the sound pass (tested; applied by Client/Sound.lua and Client/ScorePopup.lua). Only reuses ids that already work:
	nothing here invents an asset id.

	SoundFX.semitone(n)                    PlaybackSpeed for n semitones (2 ^ (n / 12))
	SoundFX.ladderSpeed(n)                 the scoring tally ladder: the n-th tick of a hand (1 = the first) rises a half step per tick, capped at +12
	SoundFX.tick(kind, chipOrMultCount, lastMultCount)   { speed, volume } for a "chips", "mult" or "xmult" tick; an xmult tick sits an octave
	                                       over the last mult tick
	SoundFX.jitter(base, pct, roll, last)  base varied by up to plus or minus pct, never equal to `last` (roll is a number 0 to 1)
	SoundFX.JITTERED                       cues that get pitch (6 percent) and volume (8 percent) jitter
	SoundFX.minInterval(cue)               seconds between two plays of a cue (hover 0.08, the rest 0.03)
	SoundFX.newGate()                      gate:allow(cue, now) -> bool, one per-cue minimum interval
	SoundFX.duck(t, deep, hold, release)   music gain at t seconds after a big beat starts: 4 dB down at once, held 1.2 s, back up over 0.6 s
	SoundFX.dbToGain(db)
	SoundFX.Layers                         composite cues: name -> { { cue, delay, speed (or semitones), volume, maxLength } }
	SoundFX.layersFor(name)                the layers of a composite cue or nil
	SoundFX.handSting(handName)            "quiet" | "medium" | "loud" | "biggest", by hand type
	SoundFX.stingLayers(tier)              the layers of a hand-type sting
	SoundFX.coinCascade(count, gap)        { { delay, speed } } coins staggered 60 ms apart at slightly different pitch
	SoundFX.isBigBeat(kind)                true for the moments that duck the music
	SoundFX.EMPTY_OK                       cues allowed to stay silent (boss_intro: the intro popup is gone)
]]

local SoundFX = {}

function SoundFX.semitone(n)
	return 2 ^ (n / 12)
end

SoundFX.LADDER_CAP = 12 -- semitones
function SoundFX.ladderSpeed(n)
	local steps = math.max(0, math.min(SoundFX.LADDER_CAP, (tonumber(n) or 1) - 1))
	return SoundFX.semitone(steps)
end

-- kind "chips" (and "tips") or "mult" climb on their own count; "xmult" sits an octave over the last mult tick. Volume rises a little with the rung.
function SoundFX.tick(kind, count, lastMultCount)
	if kind == "xmult" then
		local base = SoundFX.ladderSpeed(lastMultCount or 1)
		return { speed = math.min(base * 2, 2 ^ ((SoundFX.LADDER_CAP + 12) / 12)), volume = 0.45 }
	end
	local n = math.max(1, tonumber(count) or 1)
	return { speed = SoundFX.ladderSpeed(n), volume = math.min(0.6, 0.3 + 0.02 * (n - 1)) }
end

function SoundFX.jitter(base, pct, roll, last)
	local v = base * (1 + (roll * 2 - 1) * pct)
	if last ~= nil and math.abs(v - last) < base * 0.002 then
		-- never the same exact value twice in a row: nudge to the other side of the base
		v = base * (1 + (v >= base and -1 or 1) * pct * 0.5)
	end
	return v
end

SoundFX.PITCH_JITTER, SoundFX.VOLUME_JITTER = 0.06, 0.08
SoundFX.JITTERED = { card_select = true, card_play = true, card_deal = true, button_click = true, hover = true, chip = true, coin = true }

SoundFX.INTERVALS = { hover = 0.08 }
SoundFX.DEFAULT_INTERVAL = 0.03
function SoundFX.minInterval(cue)
	return SoundFX.INTERVALS[cue] or SoundFX.DEFAULT_INTERVAL
end

function SoundFX.newGate()
	local gate = { last = {} }
	function gate:allow(cue, now)
		local prev = self.last[cue]
		if prev ~= nil and now - prev < SoundFX.minInterval(cue) then return false end
		self.last[cue] = now
		return true
	end
	return gate
end

function SoundFX.dbToGain(db)
	return 10 ^ (db / 20)
end

SoundFX.DUCK_DB, SoundFX.DUCK_HOLD, SoundFX.DUCK_RELEASE = -4, 1.2, 0.6
function SoundFX.duck(t, deep, hold, release)
	deep = deep or SoundFX.dbToGain(SoundFX.DUCK_DB)
	hold = hold or SoundFX.DUCK_HOLD
	release = release or SoundFX.DUCK_RELEASE
	if t < 0 then return 1 end
	if t <= hold then return deep end
	if t >= hold + release then return 1 end
	local k = (t - hold) / release
	k = k * k * (3 - 2 * k) -- an eased return
	return deep + (1 - deep) * k
end

-- coins staggered 60 ms apart at slightly different pitch
function SoundFX.coinCascade(count, gap)
	local out = {}
	local speeds = { 1.0, 1.09, 0.95, 1.14 }
	for i = 1, count or 3 do
		out[i] = { delay = (i - 1) * (gap or 0.06), speed = speeds[(i - 1) % #speeds + 1] }
	end
	return out
end

-- Composite cues made only from sounds that already load. `semis` is a pitch in semitones, `speed` a plain PlaybackSpeed.
SoundFX.Layers = {
	card_flip = { { cue = "card_select", semis = 3, volume = 0.2 } },
	discard = { { cue = "card_deal", speed = 0.85 }, { cue = "scroll_close", delay = 0.04, volume = 0.18, speed = 1.3, maxLength = 0.3 } },
	hover = { { cue = "button_click", volume = 0.08, semis = 6, maxLength = 0.15 } },
	map_open = { { cue = "scroll_open" } },
	road_choose = { { cue = "page_turn" }, { cue = "chip", delay = 0.18, volume = 0.3, semis = 4 } },
	compass_turn = { { cue = "button_click", semis = -5, volume = 0.3, maxLength = 0.25, fade = 0.15 } },
	shop_enter = { { cue = "scroll_open", volume = 0.2 }, { cue = "chip", delay = 0.12, volume = 0.3, semis = 12 } },
	shop_buy = { { cue = "buy" }, { cue = "coin", delay = 0.08, volume = 0.3, speed = 1.0 }, { cue = "coin", delay = 0.14, volume = 0.25, speed = 1.09 }, { cue = "coin", delay = 0.2, volume = 0.2, speed = 0.95 } },
	shop_reroll = { { cue = "card_deal", speed = 1.0 }, { cue = "card_deal", delay = 0.09, speed = 1.18 } },
	shop_cant = { { cue = "lose", volume = 0.15, semis = 4, maxLength = 0.25 } },
	boss_defeat = { { cue = "win" }, { cue = "chip_big", delay = 0.1, volume = 0.45, speed = 0.6 } },
	-- card_play: the snap plus a soft cash rustle 40 ms later
	card_play = { { cue = "card_play", own = true }, { cue = "coin", delay = 0.04, volume = 0.12, speed = 1.4, maxLength = 0.25 } },
	-- a Legendary or True Wildcard moment: the win sting up 5 semitones, a low thud and a two note chime (chip tick +12 and +19, 90 ms apart)
	legendary_moment = { { cue = "win", semis = 5 }, { cue = "chip_big", volume = 0.5, speed = 0.55 },
		{ cue = "chip", delay = 0.0, semis = 12, volume = 0.45 }, { cue = "chip", delay = 0.09, semis = 19, volume = 0.45 } },
}

SoundFX.EMPTY_OK = { boss_intro = true }

function SoundFX.layersFor(name)
	return SoundFX.Layers[name]
end

-- hand-type stings by tier: High Card and Pair quiet, Two Pair and Three of a Kind medium, Straight and Flush loud, the rest biggest
SoundFX.STING_TIERS = {
	["High Card"] = "quiet", ["Pair"] = "quiet",
	["Two Pair"] = "medium", ["Three of a Kind"] = "medium",
	["Straight"] = "loud", ["Flush"] = "loud",
	["Full House"] = "biggest", ["Four of a Kind"] = "biggest", ["Straight Flush"] = "biggest",
}
function SoundFX.handSting(handName)
	local name = tostring(handName or "")
	if SoundFX.STING_TIERS[name] then return SoundFX.STING_TIERS[name] end
	if name:find("Five") or name:find("Royal") or name:find("Flush") or name:find("Four") then return "biggest" end
	return "medium"
end

SoundFX.STING_LAYERS = {
	quiet = { { cue = "chip", volume = 0.2 } },
	medium = { { cue = "chip_big", volume = 0.35 } },
	loud = { { cue = "chip_big", volume = 0.5 }, { cue = "chip", delay = 0.07, volume = 0.35, semis = 7 } },
	biggest = { { cue = "chip_big", volume = 0.6, speed = 0.8 }, { cue = "chip", delay = 0.07, volume = 0.4, semis = 7 }, { cue = "chip", delay = 0.14, volume = 0.4, semis = 12 } },
}
function SoundFX.stingLayers(tier)
	return SoundFX.STING_LAYERS[tier] or SoundFX.STING_LAYERS.medium
end

SoundFX.BIG_BEATS = { legendary = true, wildcard = true, four_of_a_kind = true, boss_defeat = true, round_win = true, biggest = true }
function SoundFX.isBigBeat(kind)
	return SoundFX.BIG_BEATS[kind] == true
end

return SoundFX
