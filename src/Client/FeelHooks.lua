-- Sound hooks that follow the game state: a coin when Tips go up, a discard sound when a Discard is used, a shuffle
-- when a new round is dealt. All through Cue (Engine/SoundIds); a cue with no id yet is skipped silently. Display
-- and audio only: it never changes the game. The hub calls update(state) from render in a pcall.
local Cue = require(script.Parent.Cue)

local FeelHooks = {}

local lastTips, lastDiscards, lastRoundKey
local lastCoinAt = 0

function FeelHooks.update(state)
	if type(state) ~= "table" or type(state.tips) ~= "number" then
		return
	end
	local roundKey = tostring(state.night) .. "-" .. tostring(state.round)
	local discards = state.discardsRemaining

	-- the first state only sets the baseline (joining or starting a run is not "gaining" anything)
	if lastTips ~= nil then
		if roundKey ~= lastRoundKey then
			if state.phase == "playing" or state.phase == "roundSelect" then
				Cue.play("shuffle")
			end
		elseif type(discards) == "number" and type(lastDiscards) == "number" and discards < lastDiscards then
			Cue.play("discard")
		end
		if state.tips > lastTips and roundKey == lastRoundKey then
			local now = os.clock()
			if now - lastCoinAt > 0.25 then
				lastCoinAt = now
				Cue.play("coin", 0.8)
			end
		end
	end
	lastTips, lastDiscards, lastRoundKey = state.tips, discards, roundKey
end

return FeelHooks
