--[[
	Shared/Engine/DailyPopup.lua
	When the daily-reward popup shows (pure, tested). Display only: the server (Engine/LoginStreak) decides
	streaks and claims; this only decides when to ask the player.

	nextClaimable(login) -> reward | nil     the first reward that can be claimed now
	flames(streak, max) -> shown, extra      streak as flame icons (capped), "+extra" for a long streak
	shouldShow(tracker, state) -> bool       call on every state push with a persistent tracker table:
	    * shows once when the game opens with a reward ready (the first state that carries one),
	    * shows again when a played round has just ended (phase went playing -> shop / roundSelect /
	      nightVictory) and a reward is still waiting,
	    * never twice for the same waiting reward within the same round, and never when nothing is claimable.
	    A claim or a new day changes the "waiting key", so the next reward can ask again.
]]

local DailyPopup = {}

function DailyPopup.nextClaimable(login)
	for _, reward in ipairs(login and login.rewards or {}) do
		if reward.claimable then
			return reward
		end
	end
	return nil
end

function DailyPopup.flames(streak, max)
	streak = math.max(0, math.floor(streak or 0))
	max = max or 7
	if streak <= max then
		return streak, 0
	end
	return max, streak - max
end

local ROUND_END = { shop = true, roundSelect = true, nightVictory = true }

function DailyPopup.shouldShow(tracker, state)
	local login = type(state) == "table" and state.login or nil
	local reward = DailyPopup.nextClaimable(login)
	local phase = type(state) == "table" and state.phase or nil
	local previousPhase = tracker.phase
	tracker.phase = phase
	if not reward then
		tracker.waitingKey = nil
		return false
	end
	local key = tostring(login.streak) .. ":" .. tostring(reward.day)
	local roundKey = tostring(state.night) .. "-" .. tostring(state.round)
	local roundJustEnded = previousPhase == "playing" and ROUND_END[phase] == true
	if tracker.waitingKey ~= key then
		-- the first sight of this waiting reward (game open, new day, or the next reward after a claim)
		tracker.waitingKey = key
		return true
	end
	if roundJustEnded and tracker.endShown ~= roundKey then
		tracker.endShown = roundKey -- once per finished round
		return true
	end
	return false
end

return DailyPopup
