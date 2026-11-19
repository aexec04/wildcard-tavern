--[[
	Shared/Engine/PatronCallout.lua
	Pure numbers (tested) for the small serif popup that rises above a Patron card when it triggers during scoring
	(for example "+4 Mult"). Presentation only, it never changes a score. Client/PatronCalloutFX draws it.

	PatronCallout.colorKey(kind)        -> "green" (chips, mult) | "blue" (xmult) | "gold" (money)
	PatronCallout.color(kind)           -> { r, g, b }, all at least 4.5:1 on the dark popup plate
	PatronCallout.spec(calm)            -> { rise, dur, hop, static }  rises 24 px and fades over 0.6 s, hop 0.12 s;
	                                       calm: no rise, no hop, a static label held 0.4 s
	PatronCallout.schedule(now, freeAt, calm) -> startAt, newFreeAt   one popup at a time per card, in order
]]

local M = {}

M.RISE, M.DUR, M.HOP, M.STATIC_HOLD = 24, 0.6, 0.12, 0.4

local KEY = { chips = "green", mult = "green", xmult = "blue", money = "gold" }
local COLOR = { green = { 120, 226, 130 }, blue = { 120, 180, 255 }, gold = { 246, 206, 112 } }

function M.colorKey(kind) return KEY[kind] or "green" end

function M.color(kind)
	local c = COLOR[M.colorKey(kind)]
	return { c[1], c[2], c[3] }
end

function M.spec(calm)
	if calm then return { rise = 0, dur = M.STATIC_HOLD, hop = 0, static = true } end
	return { rise = M.RISE, dur = M.DUR, hop = M.HOP, static = false }
end

-- a card's popups queue: the next one starts when the last has finished, so two never overlap on one card
function M.schedule(now, freeAt, calm)
	local startAt = math.max(now or 0, freeAt or 0)
	return startAt, startAt + M.spec(calm).dur
end

return M
