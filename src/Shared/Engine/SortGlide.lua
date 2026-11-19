--[[
	Engine/SortGlide.lua
	Pure numbers for the smooth reorder when Rank or Suit sorting rebuilds the hand (Client/SortGlideFX draws it).

	SortGlide.offsets(before, after)  before and after map a card's HandIndex to its slot centre X on screen; returns
	                                  { [handIndex] = dx } where dx is how far left or right of its NEW place the card starts
	                                  (old minus new), leaving out cards that did not move (under MIN_MOVE px) or are new.
	SortGlide.timing(calm, fast)      { time, stagger, maxTotal } or nil when Calm mode / Reduce motion is on (no tween then)
	SortGlide.delay(order, n)         start delay of the card standing at position order (1 = left), capped so the whole glide ends by
	                                  TOTAL_CAP seconds
]]

local M = {}

M.MIN_MOVE = 2 -- px; under this a card is already where it belongs
M.TIME = 0.22
M.STAGGER = 0.02
M.TOTAL_CAP = 0.5 -- the last card has landed by this many seconds

function M.offsets(before, after)
	local out = {}
	for index, newX in pairs(after or {}) do
		local oldX = before and before[index]
		if oldX ~= nil and math.abs(oldX - newX) >= M.MIN_MOVE then out[index] = oldX - newX end
	end
	return out
end

function M.timing(calm, fast)
	if calm then return nil end
	local k = fast and 0.5 or 1
	return { time = M.TIME * k, stagger = M.STAGGER * k }
end

function M.delay(order, n, fast)
	local t = M.timing(false, fast)
	local step = t.stagger
	if n and n > 1 then step = math.min(step, math.max(0, (M.TOTAL_CAP - t.time) / (n - 1))) end
	return (order - 1) * step
end

return M
