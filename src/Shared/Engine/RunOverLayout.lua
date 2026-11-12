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
	RunOverLayout.SCROLLS                               the two painted scrolls (run_over_scroll_a for a loss, _b for a win) with their measured boxes
	RunOverLayout.scroll(sw, sh, spec, key)             the same content drawn ON a scroll: { key, card, safe, fit, origin, inner } or nil when the
	                                                    window is too small for 15 px text on the paper (then the plain panel shows)
]]

local RunOverLayout = {}

RunOverLayout.TEXT_MIN = 15
RunOverLayout.MARGIN = 20
RunOverLayout.GAP = 12
RunOverLayout.TITLE_H = 64
RunOverLayout.BTN_H = 46
RunOverLayout.SMALL_H = 38
RunOverLayout.SEAT_W, RunOverLayout.SEAT_H = 72, 96
RunOverLayout.WIDE_FROM = 720 -- screen width from which the two columns show
RunOverLayout.LEFT_W = 280
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

-- The painted scrolls (1536 x 1024 pictures), boxes measured from the PNGs (art-wip/shop_scene/debug_run_over_scroll_*_boxes.png), picture pixels:
-- art = the opaque scroll, sheet = the paper between the rolls, safe = where content may go (clear of the seal and the stains), seal = the wax
-- seal, leftRod / rightRod = the rolls with their rods.
RunOverLayout.SCROLLS = {
	a = { art = { x = 53, y = 34, w = 1475, h = 990 }, sheet = { x = 226, y = 140, w = 1084, h = 760 }, safe = { x = 250, y = 170, w = 1036, h = 610 },
		seal = { x = 704, y = 800, w = 136, h = 120 }, leftRod = { x = 66, y = 36, w = 164, h = 950 }, rightRod = { x = 1308, y = 40, w = 150, h = 940 } },
	b = { art = { x = 53, y = 56, w = 1483, h = 966 }, sheet = { x = 200, y = 150, w = 1130, h = 730 }, safe = { x = 230, y = 190, w = 1070, h = 560 },
		seal = { x = 700, y = 760, w = 150, h = 130 }, leftRod = { x = 54, y = 56, w = 160, h = 909 }, rightRod = { x = 1316, y = 56, w = 150, h = 909 } },
}
RunOverLayout.SCROLL_MIN_FIT = 0.95 -- the content must fit the safe rect at nearly full size: text is never shrunk below 15 px by much
RunOverLayout.SCROLL_MAX_SCALE = 1.15
RunOverLayout.SCROLL_WIDTH_FRACTION = 0.78 -- the scroll is about 78 percent of the screen width when the content still fits
RunOverLayout.Z_LIFT = 400 -- added to every ZIndex on the screen so it draws above the play HUD

function RunOverLayout.scroll(sw, sh, spec, key)
	local S = RunOverLayout.SCROLLS[key or "a"]
	if not S then return nil end
	local maxScale = math.min((sw - 24) / S.art.w, (sh - 16) / S.art.h, RunOverLayout.SCROLL_MAX_SCALE)
	if maxScale <= 0 then return nil end
	-- try the 78 percent width first, then the largest scale that fits the window
	local pref = math.min(maxScale, RunOverLayout.SCROLL_WIDTH_FRACTION * sw / S.art.w)
	local result = RunOverLayout.scrollAt(sw, sh, spec, key, S, pref)
	if result or pref >= maxScale then return result end
	return RunOverLayout.scrollAt(sw, sh, spec, key, S, maxScale)
end

function RunOverLayout.scrollAt(sw, sh, spec, key, S, scale)
	local function m(r) return rect((r.x - S.art.x) * scale, (r.y - S.art.y) * scale, r.w * scale, r.h * scale) end
	local safe = m(S.safe)
	-- the content is laid out for a window as wide as the safe rect (two columns from 720 px) and as tall as it needs
	local inner = RunOverLayout.compute(safe.w + 32, 100000, spec)
	local fit = math.min(1, safe.w / inner.panel.w, safe.h / inner.panel.h)
	if fit < RunOverLayout.SCROLL_MIN_FIT then return nil end
	local w, h = inner.panel.w * fit, inner.panel.h * fit
	local origin = { x = safe.x + math.floor((safe.w - w) / 2 + 0.5), y = safe.y + math.floor((safe.h - h) / 2 + 0.5) }
	return { key = key or "a", scale = scale, card = { w = math.floor(S.art.w * scale + 0.5), h = math.floor(S.art.h * scale + 0.5) }, safe = safe, seal = m(S.seal),
		leftRod = m(S.leftRod), rightRod = m(S.rightRod), fit = fit, origin = origin, inner = inner }
end

return RunOverLayout
