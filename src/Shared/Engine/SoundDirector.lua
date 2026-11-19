--[[
	Shared/Engine/SoundDirector.lua
	The pure rules that keep the sound calm (applied by Client/Sound.lua playCue, tested in EngineTests "SoundDirector"). Every cue has a group
	(ui, coin, card, fanfare, ambient) and a priority. Time is passed in, so the rules need no clock.

	  SoundDirector.info(cue)            { group, priority, length } (estimated seconds the sound is audible)
	  SoundDirector.new()                a director
	  director:request(cue, now)         { play, reason, group, scale, speed, voices, cut } for a cue that wants to start now
	      play    false when a rule drops the cue; reason says which: "repeat", "gap", "fanfare", "voices", "burst"
	      scale   volume multiplier: 0.5 for every non fanfare cue while a fanfare plays (they duck by 50 percent)
	      speed   playback speed (1 normally; the coin ticks of a burst rise a whole tone each, at most 4 ticks)
	      voices  how many sounds are audible right after this one started (logged as "[SoundDirector] voices=N")
	      cut     a lower priority fanfare that is still playing: the client turns it down by 60 percent (SoundDirector.CUT_SCALE)
	  director:voices(now)               sounds audible at `now`

	Rules: at most 1 fanfare at a time (a higher priority one cuts the lower, an equal or lower one is dropped); at most 2 sounds at once from
	ui, coin and card together; 90 ms minimum gap between sounds of the same group; the same cue twice within 120 ms is dropped; a burst of
	coin ticks (tip count up, interest) becomes ONE rising run of at most 4; a fanfare ducks everything else by 50 percent for its length;
	a lower priority fanfare is muted while a higher one plays or has just played (a True Wildcard lock in mutes the round stinger).
]]

local SoundDirector = {}

SoundDirector.MAX_SMALL_VOICES = 2
SoundDirector.GROUP_GAP = 0.09
SoundDirector.REPEAT_GAP = 0.12
SoundDirector.DUCK_SCALE = 0.5
SoundDirector.CUT_SCALE = 0.4 -- a cut fanfare keeps 40 percent of its volume (60 percent down)
SoundDirector.BURST_MAX = 4
SoundDirector.BURST_WINDOW = 0.6 -- coin ticks closer together than this belong to one run
SoundDirector.TAIL = 0.5 -- a lower fanfare stays muted this long after a higher one ends

-- cue -> group, priority (higher wins), length in seconds. Anything not listed is a quiet ui sound.
local TABLE = {
	-- fanfares and stingers
	legendary_moment = { "fanfare", 5, 2.0 }, wildcard_lock = { "fanfare", 5, 2.0 },
	boss_defeat = { "fanfare", 4, 2.0 }, round_win = { "fanfare", 3, 1.8 }, win = { "fanfare", 3, 1.8 }, lose = { "fanfare", 3, 1.5 },
	defeat = { "fanfare", 3, 1.5 }, round_clear = { "fanfare", 3, 1.8 },
	boss_intro = { "fanfare", 2, 1.5 },
	-- coin
	coin = { "coin", 1, 0.5 }, chip = { "coin", 1, 0.3 }, chip_big = { "coin", 1, 0.5 }, buy = { "coin", 1, 0.6 }, shop_buy = { "coin", 1, 0.6 },
	-- card
	card_deal = { "card", 1, 0.4 }, card_select = { "card", 1, 0.3 }, card_play = { "card", 1, 0.5 }, card_flip = { "card", 1, 0.3 },
	shuffle = { "card", 1, 1.3 }, discard = { "card", 1, 0.5 }, shop_reroll = { "card", 1, 0.5 },
	-- ambient
	shop_enter = { "ambient", 0, 0.8 },
}

function SoundDirector.info(cue)
	local row = TABLE[cue]
	if row then return { group = row[1], priority = row[2], length = row[3] } end
	return { group = "ui", priority = 1, length = 0.4 }
end

function SoundDirector.new()
	local d = { active = {}, lastGroup = {}, lastCue = {}, burst = nil, lastFanfare = nil }

	local function prune(now)
		local keep = {}
		for _, v in ipairs(d.active) do
			if v.endsAt > now then keep[#keep + 1] = v end
		end
		d.active = keep
	end

	function d:voices(now)
		prune(now)
		return #self.active
	end

	local function activeFanfare()
		for _, v in ipairs(d.active) do
			if v.group == "fanfare" then return v end
		end
		return nil
	end

	function d:request(cue, now)
		prune(now)
		local info = SoundDirector.info(cue)
		local result = { play = false, group = info.group, scale = 1, speed = 1, voices = #self.active }

		-- the same cue twice within 120 ms: a double trigger
		local prevCue = self.lastCue[cue]
		if prevCue and now - prevCue < SoundDirector.REPEAT_GAP then
			result.reason = "repeat"
			return result
		end

		local fanfare = activeFanfare()
		if info.group == "fanfare" then
			-- a lower priority stinger stays muted while a higher one plays and for a short tail after it
			local higher = self.lastFanfare
			if higher and higher.priority > info.priority and now < higher.endsAt + SoundDirector.TAIL then
				result.reason = "fanfare"
				return result
			end
			if fanfare then
				if info.priority > fanfare.priority then
					result.cut = fanfare
					fanfare.endsAt = now -- the cut one is over
				else
					result.reason = "fanfare"
					return result
				end
			end
		else
			-- a rapid run of the same group
			local prevGroup = self.lastGroup[info.group]
			if prevGroup and now - prevGroup < SoundDirector.GROUP_GAP then
				result.reason = "gap"
				return result
			end
			if info.group ~= "ambient" then
				local small = 0
				for _, v in ipairs(self.active) do
					if v.group == "ui" or v.group == "coin" or v.group == "card" then small = small + 1 end
				end
				if small >= SoundDirector.MAX_SMALL_VOICES then
					result.reason = "voices"
					return result
				end
			end
			-- coin ticks: ONE rising run of at most 4
			if info.group == "coin" then
				local b = self.burst
				if b and now - b.last < SoundDirector.BURST_WINDOW then
					if b.count >= SoundDirector.BURST_MAX then
						b.last = now
						result.reason = "burst"
						return result
					end
					b.count = b.count + 1
					b.last = now
				else
					b = { count = 1, last = now }
					self.burst = b
				end
				result.speed = 2 ^ (2 * (b.count - 1) / 12) -- a whole tone higher per tick
			end
			if fanfare then result.scale = SoundDirector.DUCK_SCALE end
		end

		result.play = true
		self.lastCue[cue] = now
		self.lastGroup[info.group] = now
		local voice = { cue = cue, group = info.group, priority = info.priority, endsAt = now + info.length }
		self.active[#self.active + 1] = voice
		if info.group == "fanfare" then self.lastFanfare = voice end
		result.voices = #self.active
		return result
	end

	return d
end

return SoundDirector
