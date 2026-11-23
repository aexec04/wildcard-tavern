--[[
	Engine/HandHover.lua
	Which hand cards need repainting when the hover moves. Hover used to repaint every card (each with its own
	tweens) on both MouseLeave and MouseEnter, which stuttered on a big hand. Only the cards within `falloff`
	slots of the old or the new hovered card change look, so only those are returned. Pure.
]]
local M = {}

-- positions: { [cardIndex] = visualSlot }; from/to: card index or nil. Returns a sorted list of card indices.
function M.affected(positions, from, to, falloff)
	falloff = falloff or 2
	local out, seen = {}, {}
	local function add(center)
		local c = center and positions[center]
		if not c then return end
		for index, pos in pairs(positions) do
			if not seen[index] and math.abs(pos - c) < falloff then seen[index] = true; out[#out + 1] = index end
		end
		if not seen[center] then seen[center] = true; out[#out + 1] = center end
	end
	add(from); add(to)
	table.sort(out)
	return out
end

return M
