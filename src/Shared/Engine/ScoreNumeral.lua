-- Engine/ScoreNumeral.lua
-- What the Score plate's numeral does when the round score changes (Client/Gameplay2). The count-up only runs while the phase is
-- "playing"; a total that arrives in any other phase (the round just cleared, the shop state is on its way) must still be written,
-- or the plate keeps the number it had before the hand (the bug: 0 while TARGET CLEARED showed).
local M = {}

-- returns "count" (animate old -> new), "set" (write the new number now) or "keep" (nothing to write)
function M.action(last, now, phase)
	now = math.floor(tonumber(now) or 0)
	if last == nil then return "set" end
	if now > last then return phase == "playing" and "count" or "set" end
	if now < last then return "set" end
	return "keep"
end

-- the numeral is gold once the total has reached the Target
function M.cleared(score, target)
	score, target = tonumber(score) or 0, tonumber(target) or 0
	return target > 0 and score >= target
end

return M
