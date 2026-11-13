--[[
	Engine/PatronBoost.lua
	The small "Your Patrons are boosting your score!" panel next to the Patron nook.
	Our scoring has no single standing multiplier (Patron effects depend on the hand played), so the panel shows the real
	running Chips x Mult of the last scored hand, read from Scoring's breakdown (the same numbers PatronEvents.replay gives).

	PatronBoost.summary(breakdown) -> nil | { chips, mult, text, line }
	    nil unless at least one Patron entry (chips, mult or xmult) is in the breakdown.
	PatronBoost.place(nookBack, rootW, w, h) -> nil | { x, y, w, h }   (nookBack = {x,y,w,h} in root pixels)
	    right of the nook's back panel, same top, 8 px gap; nil when it would not fit inside the root (the panel hides).
]]

local PatronEvents = require(script.Parent.PatronEvents)

local M = {}

M.LINE = "Your Patrons are boosting your score!"
M.W, M.H = 200, 78
M.GAP, M.MARGIN = 8, 8

function M.summary(breakdown)
	local boosted = false
	for _, e in ipairs(breakdown or {}) do
		local src = e.source
		if src and src.type == "patron" and (e.kind == "chips" or e.kind == "mult" or e.kind == "xmult") then boosted = true end
	end
	if not boosted then return nil end
	local chips, mult = PatronEvents.replay(breakdown)
	local c, m = math.floor(chips + 0.5), math.floor(mult * 10 + 0.5) / 10
	local mtext = (m == math.floor(m)) and string.format("%d", math.floor(m)) or tostring(m)
	return { chips = chips, mult = mult, text = string.format("%d x %s", c, mtext), line = M.LINE }
end

function M.place(nookBack, rootW, w, h)
	if not nookBack then return nil end
	w, h = w or M.W, h or M.H
	local x = nookBack.x + nookBack.w + M.GAP
	if x + w > rootW - M.MARGIN then return nil end
	return { x = x, y = nookBack.y, w = w, h = h }
end

return M
