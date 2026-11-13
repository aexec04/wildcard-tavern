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

-- ===== the standing Mult panel beside the Patron display =====
-- Our scoring has no single standing multiplier, so the panel never invents one. It shows, in this order:
--   the hub's live hand preview for the selected cards (the same Scoring.calculate call RunState.playHand makes),
--   else the last scored hand's totals (PatronEvents.replay of its breakdown),
--   else no figure at all, only the hint line.
-- PatronBoost.totals(breakdown) -> nil | { chips, mult }
-- PatronBoost.panel(preview, last) -> { label, value (string or nil), line }   preview and last are { chips, mult } or nil
-- PatronBoost.placePanel(tray, cardsY, rootW) -> nil | { x, y, w, h }   right of the display, level with the cards
M.LABEL = "MULTIPLIER"
M.HINT = "Select cards to see your Mult"
M.PANEL_W, M.PANEL_H = 188, 112

local function fmtMult(mult)
	local m = math.floor((tonumber(mult) or 0) * 10 + 0.5) / 10
	return (m == math.floor(m)) and string.format("%d", math.floor(m)) or tostring(m)
end
M.fmtMult = fmtMult

function M.totals(breakdown)
	if type(breakdown) ~= "table" or #breakdown == 0 then return nil end
	local chips, mult = PatronEvents.replay(breakdown)
	return { chips = chips, mult = mult }
end

function M.panel(preview, last)
	local src, lead = nil, nil
	if type(preview) == "table" and tonumber(preview.mult) and tonumber(preview.chips) then
		src, lead = preview, "This hand"
	elseif type(last) == "table" and tonumber(last.mult) and tonumber(last.chips) then
		src, lead = last, "Last hand"
	end
	if not src then return { label = M.LABEL, value = nil, line = M.HINT } end
	local m = fmtMult(src.mult)
	return { label = M.LABEL, value = "x" .. m, line = string.format("%s\n%d Chips x %s Mult", lead, math.floor(src.chips + 0.5), m) }
end

function M.placePanel(tray, cardsY, rootW)
	if not tray then return nil end
	local x = tray.x + tray.w + M.GAP
	if x + M.PANEL_W > rootW - M.MARGIN then return nil end
	return { x = x, y = cardsY or tray.y, w = M.PANEL_W, h = M.PANEL_H }
end

return M
