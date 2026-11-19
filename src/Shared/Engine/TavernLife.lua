--[[
	Shared/Engine/TavernLife.lua
	Pure numbers (tested) for the second ambient and scoring juice pass. Client/TavernLifeFX plays them. Calm mode and Reduce motion
	return nil (or the resting value), so nothing tweens or loops.

	TavernLife.firePulse(t, calm) -> 0.9 .. 1.0 multiplier of the fireplace glow, a 3 s sine (1 in calm mode)
	TavernLife.catScale(t, calm) -> 1 .. 1.015, a 4 s breath (1 in calm mode)
	TavernLife.MOTES, MOTE_RISE   12 dust motes, each rising through the room in 8 s
	TavernLife.coinBurst(old, new, calm) -> nil | { count, dur, rise }   when the coin count went up
	TavernLife.warmFlash(score, target, calm) -> nil | { alpha, dur }   a big hand: at least a quarter of the Target
	TavernLife.patronHop(calm) -> nil | 8   pixels a Patron card hops when it triggers
	TavernLife.CAT   the sleeping cat's crop of the 1536 x 1024 room picture { x, y, w, h }
]]

local M = {}

local TAU = math.pi * 2

M.MOTES = 12
M.MOTE_RISE = 8
M.CAT = { x = 1295, y = 495, w = 230, h = 115 }

function M.firePulse(t, calm)
	if calm then return 1 end
	return 0.95 + 0.05 * math.sin(TAU * t / 3)
end

function M.catScale(t, calm)
	if calm then return 1 end
	return 1.0075 + 0.0075 * math.sin(TAU * t / 4)
end

function M.coinBurst(old, new, calm)
	old, new = tonumber(old), tonumber(new)
	if calm or not old or not new or new <= old then return nil end
	return { count = math.min(12, 4 + (new - old) // 2), dur = 0.5, rise = 40 }
end

function M.warmFlash(score, target, calm)
	if calm or not target or target <= 0 or (score or 0) < target * 0.25 then return nil end
	return { alpha = 0.08, dur = 0.2 }
end

function M.patronHop(calm)
	if calm then return nil end
	return 8
end

return M
