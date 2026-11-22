--[[
	Shared/Engine/TravelTiming.lua
	Pure timing rules for Client/TravelTransition (the map walk shown while a round loads).
	elapsed / readyAt are seconds since the transition started; readyAt is nil while the game is not ready.
]]

local TravelTiming = {}

TravelTiming.MIN = 0.8 -- never flash: the cover stays at least this long
TravelTiming.MAX = 3 -- reveal anyway after this long (a wait over 3 s that is not a choice is cut)
TravelTiming.SKIP_AFTER = 0.5 -- a tap skips the wait only after this long
TravelTiming.REDUCED_MIN = 0.35 -- reduce-motion: a plain quick fade
TravelTiming.REDUCED_MAX = 1.5

-- Seconds (since start) at which the cover should lift. Ready early -> MIN; ready late -> when ready;
-- never ready -> MAX. reduced uses the short limits.
function TravelTiming.revealTime(readyAt, reduced)
	local min = reduced and TravelTiming.REDUCED_MIN or TravelTiming.MIN
	local max = reduced and TravelTiming.REDUCED_MAX or TravelTiming.MAX
	if readyAt == nil then
		return max
	end
	return math.max(min, math.min(readyAt, max))
end

-- True when the cover should lift now: the reveal time has passed, or the player skipped after SKIP_AFTER
-- and the game is ready (a skip never reveals an unready game before MAX).
function TravelTiming.shouldReveal(elapsed, readyAt, reduced, skipRequested)
	if elapsed >= TravelTiming.revealTime(readyAt, reduced) then
		return true
	end
	if skipRequested and readyAt ~= nil and elapsed >= TravelTiming.SKIP_AFTER then
		return true
	end
	return false
end

-- The first-run tutorial walks the player through its own hand; no transition over it.
function TravelTiming.shouldRun(state)
	if type(state) ~= "table" then
		return false
	end
	return state.hasSeenTutorial ~= false
end

return TravelTiming
