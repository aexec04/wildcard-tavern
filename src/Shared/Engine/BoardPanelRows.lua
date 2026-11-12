--[[
	Engine/BoardPanelRows.lua
	Pure layout of the lower half of the tall left board: ONE panel hung under the painted board that holds, top to bottom,
	the Tips row, the Select cards hint row, the Blessing row and the Run row ("Seeded run" / Daily / Weekly with the seed).
	No Roblox types. Coordinates are board coordinates (top left origin, the same as Engine/PlayBoardLayout.hud).

	plan{ x, w, top, avail, want } -> {
		panel = { x, y, w, h }, rows = { tips = {x,y,w,h}, hint = ..., blessing = ..., run = ... }, order = { "tips", ... },
		seps = { y, ... }  (the thin brass lines between rows), blessing = "full" | "compact" | nil, level, fits
	}
	x, w   the panel's left edge and width (the board's inner column)
	top    where the panel starts (the painted board's bottom)
	avail  pixels from top to the bottom margin of the screen
	want   { tips = bool, hint = bool, blessing = bool, run = bool }  rows that exist right now (a missing row collapses)

	Rows shrink first (level 1: compact Blessing, level 2: every row at its minimum). If even that is too tall the Run row and then the
	Blessing row are dropped, in that order, and `fits` says whether the rest fits. Text never goes under 15 px: the minimum heights
	keep a 15 px line plus its padding.
]]

local M = {}

M.PAD = 8 -- panel padding top, bottom and sides
M.SEP = 3 -- gap that holds the brass line between two rows
M.ORDER = { "tips", "hint", "blessing", "run" }
-- nominal and minimum heights per row; the Blessing row has a full (name, blessing, curse) and a compact (name only) form
M.HEIGHTS = {
	tips = { 38, 34 }, hint = { 34, 28 }, run = { 30, 26 },
	blessingFull = { 102, 102 }, blessingCompact = { 44, 40 },
}
M.MIN_TEXT = 15

local function heightsFor(level, want, drop)
	local rows = {}
	for _, k in ipairs(M.ORDER) do
		if want[k] and not drop[k] then
			local pair
			if k == "blessing" then pair = (level == 0) and M.HEIGHTS.blessingFull or M.HEIGHTS.blessingCompact else pair = M.HEIGHTS[k] end
			rows[#rows + 1] = { key = k, h = (level >= 2) and pair[2] or pair[1] }
		end
	end
	return rows
end

local function totalOf(rows)
	if #rows == 0 then return 0 end
	local t = 2 * M.PAD + (#rows - 1) * M.SEP
	for _, r in ipairs(rows) do t = t + r.h end
	return t
end

function M.plan(p)
	local want = p.want or {}
	local avail = p.avail or 0
	local drop = {}
	local rows, level
	-- try each level, then drop the Run row, then the Blessing row
	local attempts = { {}, { run = true }, { run = true, blessing = true } }
	for _, d in ipairs(attempts) do
		drop = d
		for lv = 0, 2 do
			local r = heightsFor(lv, want, drop)
			if totalOf(r) <= avail or (lv == 2 and d == attempts[#attempts]) then rows, level = r, lv end
			if rows then break end
		end
		if rows then break end
	end
	local out = { rows = {}, order = {}, seps = {}, level = level, fits = totalOf(rows) <= avail, blessing = nil }
	local y = (p.top or 0)
	local top = y
	local inner = (p.w or 0) - 2 * M.PAD
	y = y + M.PAD
	for i, r in ipairs(rows) do
		out.rows[r.key] = { x = (p.x or 0) + M.PAD, y = y, w = inner, h = r.h }
		out.order[#out.order + 1] = r.key
		if r.key == "blessing" then out.blessing = (level == 0) and "full" or "compact" end
		y = y + r.h
		if i < #rows then
			out.seps[#out.seps + 1] = y + math.floor(M.SEP / 2)
			y = y + M.SEP
		end
	end
	y = y + M.PAD
	out.panel = { x = p.x or 0, y = top, w = p.w or 0, h = #rows > 0 and (y - top) or 0 }
	return out
end

return M
