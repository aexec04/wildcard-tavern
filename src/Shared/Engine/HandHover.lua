--[[
	Engine/HandHover.lua
	Which hand cards need repainting when the hover moves. A hover only ever changes the hovered card (lift, plain
	outline): no neighbour lifts or slides, picked or not, so only the card losing and the card gaining the hover
	are returned. Pure.
]]
local M = {}

-- positions: { [cardIndex] = visualSlot } (kept for callers); from/to: card index or nil. Returns a sorted list.
function M.affected(positions, from, to, falloff)
	local out = {}
	if from ~= nil and positions[from] then out[#out + 1] = from end
	if to ~= nil and to ~= from and positions[to] then out[#out + 1] = to end
	table.sort(out)
	return out
end

-- Offsets a card other than the hovered one gets from the hover: always none.
function M.neighbourOffset(positions, hovered, index)
	return 0, 0
end

return M
