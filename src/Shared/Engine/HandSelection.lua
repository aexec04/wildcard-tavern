--[[
	Engine/HandSelection.lua
	Which picked cards survive a rebuild of the hand row. Sorting by Rank or Suit only reorders the cards, so the picked ones
	(keyed by raw hand index, which a sort never changes) stay picked; an index past the hand size is dropped.

	restore(keep, handSize) -> { [index] = true }  the picked indices that still exist
]]
local M = {}

function M.restore(keep, handSize)
	local out = {}
	for i, v in pairs(keep or {}) do
		if v and type(i) == "number" and i >= 1 and i <= (handSize or 0) then out[i] = true end
	end
	return out
end

return M
