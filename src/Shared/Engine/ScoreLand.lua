--[[
	Engine/ScoreLand.lua
	When the round score on the left board changes. The server's answer to a played hand carries the new total, and
	the board used to show it at once, a few seconds before the reveal had counted the hand up: the payoff was on
	screen before the reveal reached it. Now the board keeps the score from before the hand while the reveal plays and
	counts up to the new total when the payout lands (Client/ScoreLand draws; these are the pure, tested rules).

	  ScoreLand.keepsOld(shownScore, shownTarget, newScore, newTarget) -> bool
	  ScoreLand.rolled(from, to, t, duration) -> number
	  ScoreLand.MAX_HOLD, ScoreLand.ROLL_TIME
]]

local ScoreLand = {}

ScoreLand.MAX_HOLD = 12     -- seconds: a payout that never lands cannot leave an old score on the board
ScoreLand.ROLL_TIME = 0.35  -- seconds the number takes to count up when it lands

-- While a reveal plays the board keeps the old score only for the same round: a new target, or a score lower than the
-- one shown, means a new round has begun and its numbers are shown at once.
function ScoreLand.keepsOld(shownScore, shownTarget, newScore, newTarget)
	if type(shownScore) ~= "number" or type(newScore) ~= "number" then return false end
	return newTarget == shownTarget and newScore >= shownScore
end

-- The score shown `t` seconds into the count-up from `from` to `to`: whole numbers, eased out, never past the end.
function ScoreLand.rolled(from, to, t, duration)
	if duration <= 0 or t >= duration then return to end
	local a = math.max(0, t / duration)
	local eased = 1 - (1 - a) * (1 - a)
	local value = math.floor(from + (to - from) * eased + 0.5)
	if to >= from then return math.min(to, math.max(from, value)) end
	return math.max(to, math.min(from, value))
end

return ScoreLand
