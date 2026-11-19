--[[
	Engine/Gameplay2Feel.lua
	Gameplay v2: the small feel rules of the new table, pure numbers (tested). Client/Gameplay2FeelFX plays them.
	Hover, select lift, neighbour spread (FeelTuning) and the deal timing (PlayMotion.dealTiming) are tested elsewhere; this adds:

	Gameplay2Feel.legalPlay(selected, minCards, maxCards) -> true when the Play Hand plate may glow (1..5 cards, round rules respected)
	Gameplay2Feel.glow(t, calm) -> alpha 0..1 of the gold glow ring at time t (sine, period 1.6 s); calm mode: a steady 0.35, no loop
	Gameplay2Feel.press(calm) -> nil | { px = 3, down, up }   the plate content drops 3 px and springs back
	Gameplay2Feel.shake(calm) -> nil | { px, count, dur }   a short no-select shake, never an error popup
	Gameplay2Feel.pillTick(oldText, newText, calm)   same pop as the HUD ticks (HudTick.pop)
	Gameplay2Feel.discardPoint(rects, w, h) -> x, y   where discarded cards fly: the bottom right, under the deck count
]]

local M = {}

M.GLOW_PERIOD = 1.6
M.GLOW_MIN, M.GLOW_MAX = 0.2, 0.7
M.CALM_GLOW = 0.35

function M.legalPlay(selected, minCards, maxCards)
	selected = tonumber(selected) or 0
	return selected >= (minCards or 1) and selected <= (maxCards or 5)
end

function M.glow(t, calm)
	if calm then return M.CALM_GLOW end
	local phase = (t % M.GLOW_PERIOD) / M.GLOW_PERIOD
	local s = (math.sin(phase * 2 * math.pi - math.pi / 2) + 1) / 2 -- 0 at t = 0, 1 at half the period
	return M.GLOW_MIN + (M.GLOW_MAX - M.GLOW_MIN) * s
end

function M.press(calm)
	if calm then return nil end
	return { px = 3, down = 0.05, up = 0.14 }
end

function M.shake(calm)
	if calm then return nil end
	return { px = 4, count = 4, dur = 0.05 }
end

function M.pillTick(oldText, newText, calm)
	if calm or oldText == nil or oldText == newText then return nil end
	return { scale = 1.14, up = 0.08, down = 0.14 }
end

function M.discardPoint(r, w, h)
	local c = r.deckCount
	local x = c.x + c.w / 2
	local y = math.min(h - 12, c.y + c.h + 18)
	return x, y
end

return M
