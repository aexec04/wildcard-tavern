-- Where a hand card rests: its fan Y minus the lift a pick gave it. The deal landing used to reset every card to the bare fan Y,
-- which dropped a card picked while the deal was still flying.
local M = {}

function M.landY(fanY, liftY)
	return (fanY or 0) - math.max(0, liftY or 0)
end

-- offsets for a hand: picked cards lift, others do not
function M.offsets(selectedByIndex, count, lift)
	local out = {}
	for i = 1, count do out[i] = selectedByIndex[i] and lift or 0 end
	return out
end

return M
