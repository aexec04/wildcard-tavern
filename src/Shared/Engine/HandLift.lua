-- Where a hand card rests: its fan Y minus the lift a pick gave it. The deal landing used to reset every card to the bare fan Y,
-- which dropped a card picked while the deal was still flying.
local M = {}

function M.landY(fanY, liftY)
	return (fanY or 0) - math.max(0, liftY or 0)
end

-- The lift one card shows: a pick lifts it by selLift, a hover adds hoverLift on the hovered card only. Hovering another card never
-- changes this card, so a picked card never drops.
function M.cardLift(picked, hovered, selLift, hoverLift)
	return (picked and (selLift or 0) or 0) + (hovered and (hoverLift or 0) or 0)
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

-- The one rule for the whole hand: every card whose pick is settled rests at fan Y minus its lift, whatever else wrote Position.
-- cards: list of { picked, y, fanY, liftY, age }; returns a list of the Y to write per card (nil = leave it). A picked card with no
-- recorded lift is not trusted to rest flat: it takes `want`.
function M.plan(cards, want)
	local out = {}
	for i, c in ipairs(cards) do
		if c.picked then
			local lift = (c.liftY and c.liftY > 0) and c.liftY or want
			out[i] = M.enforceY(c.y, c.fanY, lift, c.age)
		end
	end
	return out
end

-- a deal flag older than this is stale (the landing tween never cleared it), so it no longer blocks the lift guard
M.DEAL_STALE = 3

return M
