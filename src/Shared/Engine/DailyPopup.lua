--[[
	Shared/Engine/DailyPopup.lua
	When the daily-reward popup shows (pure, tested). Display only: the server (Engine/LoginStreak) decides
	streaks and claims; this only decides when to ask the player.

	nextClaimable(login) -> reward | nil     the first reward that can be claimed now
	flames(streak, max) -> shown, extra      streak as flame icons (capped), "+extra" for a long streak
	runActive(state), canOffer(state, menuVisible) -> bool    no plate and no chest icon while a run is on
	shouldShow(tracker, state, menuVisible) -> bool    call on every state push with a persistent tracker table:
	    * shows once when the game opens with a reward ready (the first state that carries one),
	    * shows again once when the player is back at the Menu after a run,
	    * never during a run (playing, shop, roundSelect), never twice for the same waiting reward, never when nothing is claimable.
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

local RUN_PHASES = { playing = true, shop = true, roundSelect = true }

-- True while a run is in progress (round, shop, round select, boss, haggle all live in these phases).
function DailyPopup.runActive(state)
	return type(state) == "table" and RUN_PHASES[state.phase] == true
end

-- The daily reward is only offered (plate and top-right chest) away from a run, with the Menu showing.
function DailyPopup.canOffer(state, menuVisible)
	return menuVisible ~= false and not DailyPopup.runActive(state)
end

function DailyPopup.shouldShow(tracker, state, menuVisible)
	local login = type(state) == "table" and state.login or nil
	local reward = DailyPopup.nextClaimable(login)
	if DailyPopup.runActive(state) then
		tracker.sawRun = true
		return false -- never during a run; it waits for the Menu
	end
	if not reward then
		tracker.waitingKey = nil
		tracker.sawRun = nil
		return false
	end
	if not DailyPopup.canOffer(state, menuVisible) then return false end
	local key = tostring(login.streak) .. ":" .. tostring(reward.day)
	if tracker.waitingKey ~= key or tracker.sawRun then
		-- first sight of this waiting reward (game open, new day, next reward after a claim), or back at the Menu after a run
		tracker.waitingKey = key
		tracker.sawRun = nil
		return true
	end
	return false
end

return DailyPopup
