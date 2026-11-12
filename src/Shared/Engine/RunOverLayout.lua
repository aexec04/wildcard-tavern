--[[
	Shared/Engine/RunOverLayout.lua
	Pure layout for the ONE Run Over screen (Client/GameOver.lua, the frame named RunOverPanel): a loss ("Last call! You made it to
	Night N, Round R.") and a win share it. Two columns on wide screens (left: the run facts, right: Patrons used and the actions),
	one column on narrow screens (phones). Everything is in panel pixels; a UIScale is the last resort when the panel is still taller
	than the screen, so nothing scrolls. Tested in EngineTests ("RunOverLayout").

	RunOverLayout.columns(sw)                          { mode = "wide"|"narrow", panelW, leftW, rightW }
	RunOverLayout.estimateLines(text, width, size)     wrapped line count of a text (no real fonts needed)
	RunOverLayout.compute(sw, sh, spec)                spec = { factsH, patrons, primary, more }; returns the rects
	RunOverLayout.TEXT_MIN                              smallest text size on the screen (15)
]]

local RunOverLayout = {}

RunOverLayout.TEXT_MIN = 15
RunOverLayout.MARGIN = 20
RunOverLayout.GAP = 12
RunOverLayout.TITLE_H = 64
RunOverLayout.BTN_H = 46
RunOverLayout.SMALL_H = 38
RunOverLayout.SEAT_W, RunOverLayout.SEAT_H = 84, 96
RunOverLayout.WIDE_FROM = 720 -- screen width from which the two columns show
RunOverLayout.LEFT_W = 300
RunOverLayout.LABEL_H = 24

function RunOverLayout.columns(sw)
	local M = RunOverLayout.MARGIN
	if sw >= RunOverLayout.WIDE_FROM then
		local panelW = math.min(880, sw - 32)
		local leftW = RunOverLayout.LEFT_W
		return { mode = "wide", panelW = panelW, leftW = leftW, rightW = panelW - M - leftW - M - M }
	end
	local panelW = math.max(280, sw - 16)
	return { mode = "narrow", panelW = panelW, leftW = panelW - 2 * M, rightW = panelW - 2 * M }
end

-- a rough wrapped-line count: average glyph width 0.55 of the size
function RunOverLayout.estimateLines(text, width, size)
	text = tostring(text or "")
	if text == "" then return 0 end
	local per = math.max(1, math.floor(width / ((size or 16) * 0.55)))
	local lines = 0
	for part in (text .. "\n"):gmatch("(.-)\n") do
		lines = lines + math.max(1, math.ceil(#part / per))
	end
	return lines
end

local function rect(x, y, w, h) return { x = x, y = y, w = w, h = h } end

-- n equal cells across width w, left to right
local function row(x, y, w, h, n, gap)
	local cells = {}
	if n <= 0 then return cells end
	local cw = (w - (n - 1) * gap) / n
	for i = 1, n do cells[i] = rect(x + (i - 1) * (cw + gap), y, cw, h) end
	return cells
end

-- items in rows of `perRow`, each row full width
local function grid(x, y, w, h, count, perRow, gap)
	local cells, y0 = {}, y
	local left = count
	while left > 0 do
		local n = math.min(perRow, left)
		-- a short last row keeps the same cell width as the rows above (left aligned)
		local cw = (w - (perRow - 1) * gap) / perRow
		for i = 1, n do cells[#cells + 1] = rect(x + (i - 1) * (cw + gap), y0, cw, h) end
		y0 = y0 + h + gap
		left = left - n
	end
	return cells, (#cells > 0 and (y0 - gap) or y)
end

function RunOverLayout.compute(sw, sh, spec)
	spec = spec or {}
	local C = RunOverLayout.columns(sw)
	local M, G = RunOverLayout.MARGIN, RunOverLayout.GAP
	local patrons = math.max(0, spec.patrons or 0)
	local primary = math.max(1, spec.primary or 2)
	local more = math.max(0, spec.more or 0)
	local factsH = math.max(0, spec.factsH or 0)
	local out = { mode = C.mode }
	local titleH = C.mode == "wide" and RunOverLayout.TITLE_H or 56
	out.title = rect(M, M, C.panelW - 2 * M, titleH)
	local y0 = M + titleH + G

	local function patronBlock(x, y, w)
		local cols = math.max(1, math.floor((w + 8) / (RunOverLayout.SEAT_W + 8)))
		local rows = math.max(1, math.ceil(patrons / cols))
		local h = patrons == 0 and 44 or (rows * (RunOverLayout.SEAT_H + 8) - 8 + 16)
		out.patronsLabel = rect(x, y, w, RunOverLayout.LABEL_H)
		out.patrons = rect(x, y + RunOverLayout.LABEL_H + 4, w, h)
		out.patrons.cols, out.patrons.rows = cols, rows
		return y + RunOverLayout.LABEL_H + 4 + h
	end

	if C.mode == "wide" then
		out.facts = rect(M, y0, C.leftW, factsH)
		local rx = M + C.leftW + M
		local y = patronBlock(rx, y0, C.rightW) + G
		out.primary = row(rx, y, C.rightW, RunOverLayout.BTN_H, primary, 8)
		y = y + RunOverLayout.BTN_H + G
		local cells, bottom = grid(rx, y, C.rightW, RunOverLayout.SMALL_H, more, 3, 8)
		out.more = cells
		local rightBottom = math.max(y, bottom)
		out.panel = rect(0, 0, C.panelW, math.max(y0 + factsH, rightBottom) + M)
	else
		local w = C.panelW - 2 * M
		out.facts = rect(M, y0, w, factsH)
		local y = y0 + factsH + G
		y = patronBlock(M, y, w) + G
		out.primary = {}
		for i = 1, primary do
			out.primary[i] = rect(M, y, w, RunOverLayout.BTN_H)
			y = y + RunOverLayout.BTN_H + 8
		end
		y = y - 8 + G
		local cells, bottom = grid(M, y, w, RunOverLayout.SMALL_H, more, 2, 8)
		out.more = cells
		out.panel = rect(0, 0, C.panelW, math.max(y, bottom) + M)
	end
	local fit = math.min(1, (sh - 16) / out.panel.h, (sw - 8) / out.panel.w)
	out.scale = math.max(0.4, fit)
	out.columns = C
	return out
end

return RunOverLayout
