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
-- PatronBoost.placePanel(tray, cardsY, rootW, dock) -> nil | { x, y, w, h, compact }   right of the display, level with
--   the cards. dock = the corner icon row's { x, y, w, h } (optional): a panel that would stand under the icons moves
--   below them and is compact (no label row, LABEL_H shorter), so its bottom stays where it was.
M.LABEL = "MULTIPLIER"
M.HINT = "Select cards to see your Mult"
M.PANEL_W, M.PANEL_H = 188, 112
M.LABEL_H = 19 -- the "MULTIPLIER" label row, left out of a compact panel
M.DOCK_AIR = 6 -- clear space between the corner icons and a panel moved below them

-- Up to two decimals, no trailing zeros: 8 -> "8", 6.6 -> "6.6", 6.65 -> "6.65" (one decimal turned 6.65 into 6.7,
-- and "15 Chips x 6.7 Mult" then did not add up to the 99 the hand paid).
local function fmtMult(mult)
	local text = string.format("%.2f", tonumber(mult) or 0)
	text = text:gsub("0+$", ""):gsub("%.$", "")
	return text
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

function M.placePanel(tray, cardsY, rootW, dock)
	if not tray then return nil end
	local x = tray.x + tray.w + M.GAP
	if x + M.PANEL_W > rootW - M.MARGIN then return nil end
	local y, h, compact = cardsY or tray.y, M.PANEL_H, false
	-- On a short screen the display drops its heading and the cards start at the top of the nook, level with the corner
	-- icons: the panel then ran 15 to 28 px under them (1506 x 630, 1366 x 657, 1024 x 768).
	if type(dock) == "table" and (dock.w or 0) > 0 and x < dock.x + dock.w and x + M.PANEL_W > dock.x
		and y < dock.y + dock.h + M.DOCK_AIR then
		y = dock.y + dock.h + M.DOCK_AIR
		h = M.PANEL_H - M.LABEL_H
		compact = true
	end
	return { x = x, y = y, w = M.PANEL_W, h = h, compact = compact }
end

return M
