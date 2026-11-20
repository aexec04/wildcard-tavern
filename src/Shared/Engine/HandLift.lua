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

-- A card whose lift tween ended (SETTLE seconds after the pick) must rest at fan Y minus its lift. Returns the Y to write, or nil
-- when the card is already there or the tween may still be running. Guards against any later write that drops the lift.
M.SETTLE = 0.2
function M.enforceY(currentY, fanY, liftY, age)
	if not age or age < M.SETTLE then return nil end
	local want = M.landY(fanY, liftY)
	if math.abs((currentY or 0) - want) < 0.5 then return nil end
	return want
end

return M
