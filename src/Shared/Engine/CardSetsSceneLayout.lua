--[[
	Shared/Engine/CardSetsSceneLayout.lua
	The painted Card Sets shelf wall (art `panel_scene`, key cardsets_room_a, 1024x1024; Client/CardSetsRoom.lua, used by
	Client/CosmeticSetsPanel.lua). Slots were read off the PNG (art-wip/panel_scene/cardsets_room_slots.py draws them on
	debug_cardsets_room_a.png), in the picture's own pixels; geometry is in Engine/PanelSceneLayout.lua.

	CardSetsSceneLayout.place(areaW, areaH) -> { ok, scale, image, plates = { rect x5 }, frames = { rect x10, row by row },
	                                              plaques = { rect x10, same order } } in the area's pixels
	CardSetsSceneLayout.tileParts(frame) -> { cardW, cardH, face, back, name, preview, single } rects relative to a frame
	CardSetsSceneLayout.pageCount(n) / pageSlice(list, page) -> paging of PER_PAGE entries
	CardSetsSceneLayout.panel(screenW, screenH) -> panel w, h the scene wants on that screen
	CardSetsSceneLayout.TOP, BOTTOM   header (title, hint) above and Close below the body
]]

local PS = require(script.Parent.PanelSceneLayout)

local M = {}

M.ART_KEY = "cardsets_room_a"
M.PER_PAGE = 10
-- the velvet openings inside the wooden frames (the frame border, about 12 px, is left out)
local COLS = { { 112, 125 }, { 279, 125 }, { 447, 125 }, { 615, 125 }, { 784, 125 } }
local ROWS = { { 312, 196 }, { 610, 182 } }
local PLAQUE_COLS = { { 118, 103 }, { 288, 102 }, { 457, 103 }, { 627, 101 }, { 798, 103 } }
local PLAQUE_ROWS = { { 531, 29 }, { 817, 29 } }
local function frames()
	local out = {}
	for _, r in ipairs(ROWS) do for _, c in ipairs(COLS) do out[#out + 1] = { c[1], r[1], c[2], r[2] } end end
	return out
end
local function plaques()
	local out = {}
	for _, r in ipairs(PLAQUE_ROWS) do for _, c in ipairs(PLAQUE_COLS) do out[#out + 1] = { c[1], r[1], c[2], r[2] } end end
	return out
end
M.DEF = {
	w = 1024, h = 1024, margin = 8, pad = 14,
	groups = {
		plates = { { 85, 168, 152, 72 }, { 255, 168, 150, 72 }, { 424, 168, 158, 72 }, { 600, 168, 170, 72 }, { 786, 168, 150, 72 } },
		frames = frames(),
		plaques = plaques(),
	},
	-- smallest sizes (px) at which text stays readable (nothing under 14)
	min = { plates = { 96, 40 }, frames = { 84, 124 }, plaques = { 70, 20 } },
}
M.PANEL_FRAC = { 0.92, 0.94 }
M.PANEL_MAX = { 1200, 900 }
M.TOP, M.BOTTOM = 62, 46

-- The picture is square, so the panel is only as wide as the picture comes out at the height-limited scale (no flat band at the sides);
-- its height never passes screen height minus 96 (PanelLayout.expandedHeight), so Close stays on screen under the tab strip's nudge.
function M.panel(screenW, screenH)
	local fw, fh = PS.panelSize(screenW, screenH, M.PANEL_FRAC[1], M.PANEL_FRAC[2], M.PANEL_MAX[1], M.PANEL_MAX[2])
	local x0, y0, x1, y1 = PS.bounds(M.DEF)
	local s = (fh - M.TOP - M.BOTTOM - 2 * (M.DEF.margin or 8)) / (y1 - y0)
	return math.max(640, math.min(fw, math.ceil(M.DEF.w * s))), fh
end

-- Plaque and plate colours (rgb, tested at 4.5:1): Locked, Buy and the page texts are cream on a small dark pill (cream straight on the
-- brass plaque is only about 3.8:1), Equip stays dark ink on the brass.
M.COLORS = { cream = { 250, 240, 220 }, pill = { 40, 26, 16 }, ink = { 44, 26, 12 }, brass = { 170, 126, 60 } }

function M.place(areaW, areaH)
	local p = PS.place(M.DEF, areaW, areaH)
	p.plates, p.frames, p.plaques = p.groups.plates, p.groups.frames, p.groups.plaques
	return p
end

-- inside one frame: two cards side by side (a sample face and the back, for a set) or one big back (single), the name on two lines
-- (38 px: Roblox only fits two 14 px lines in 36 or more) and a Preview plate at the foot
function M.tileParts(f)
	local pad, gap = 4, 6
	local nameH, btnH = 37, 24
	local avail = f.h - (pad + 4 + nameH + 3 + btnH + pad)
	local swatchH = avail >= 48 + 20 and 18 or 0 -- a mini table swatch under the cards (Card Sets), only when it fits
	local cardH = math.max(48, avail - (swatchH > 0 and swatchH + 2 or 0))
	local cardW = math.floor(math.min((f.w - 2 * pad - gap) / 2, cardH * 2 / 3))
	cardH = math.floor(cardW * 3 / 2)
	local top = pad
	local rowW = cardW * 2 + gap
	local x0 = math.floor((f.w - rowW) / 2)
	local swatch = swatchH > 0 and { x = x0, y = top + cardH + 3, w = cardW * 2 + gap, h = swatchH } or nil
	local nameY = top + cardH + 4 + (swatch and swatchH + 2 or 0)
	local single = { x = math.floor((f.w - cardW) / 2), y = top, w = cardW, h = cardH }
	return {
		cardW = cardW, cardH = cardH,
		face = { x = x0, y = top, w = cardW, h = cardH },
		back = { x = x0 + cardW + gap, y = top, w = cardW, h = cardH },
		single = single,
		swatch = swatch,
		name = { x = 4, y = nameY, w = f.w - 8, h = nameH },
		preview = { x = 8, y = f.h - pad - btnH, w = f.w - 16, h = btnH },
	}
end

-- Full-width grid (the painted picture is no longer drawn): columns = floor(usable width / cell pitch), rows = floor(usable height / row
-- pitch), cells spread over the whole width, a short last row centred, never an empty cell. perPage = cols * rows.
-- grid(areaW, areaH, n, page) -> { ok, cols, rows, perPage, pages, page, plates = { tabs = {sets, backs}, page, prev, next },
--                                  cells = { { frame, plaque, shelf } ... for the entries on that page } } in the area's pixels
M.CELL = { frameW = 124, frameH = 184, plaqueH = 28, gapX = 22, gapY = 18, side = 28, barH = 40, barTop = 8 }
function M.grid(areaW, areaH, n, page)
	local C = M.CELL
	local top = C.barTop + C.barH + 22 -- room for the frame border and its shadow
	local usableW, usableH = areaW - 2 * C.side, areaH - top - 10
	local rowH = C.frameH + C.plaqueH + 6
	local cols, rows = math.floor((usableW + C.gapX) / (C.frameW + C.gapX)), math.floor((usableH + C.gapY) / (rowH + C.gapY))
	local out = { ok = cols >= 1 and rows >= 1, cols = math.max(cols, 1), rows = math.max(rows, 1), cells = {} }
	cols, rows = out.cols, out.rows
	out.perPage = cols * rows
	out.pages = math.max(1, math.ceil(n / out.perPage))
	out.page = math.max(1, math.min(out.pages, page or 1))
	local gx = cols > 1 and math.min(C.gapX * 3, (usableW - cols * C.frameW) / (cols - 1)) or 0
	local gy = rows > 1 and math.min(C.gapY * 2, (usableH - rows * rowH) / (rows - 1)) or 0
	local first = (out.page - 1) * out.perPage
	local onPage = math.max(0, math.min(out.perPage, n - first))
	local y0 = top -- grid starts right under the tab row (no dead band)
	for i = 1, onPage do
		local r, c = math.floor((i - 1) / cols), (i - 1) % cols
		local inRow = math.min(cols, onPage - r * cols)
		local rowW = inRow * C.frameW + (inRow - 1) * gx
		local x = math.floor((areaW - rowW) / 2 + c * (C.frameW + gx))
		local y = math.floor(y0 + r * (rowH + gy))
		out.cells[i] = {
			frame = { x = x, y = y, w = C.frameW, h = C.frameH },
			plaque = { x = x + 10, y = y + C.frameH + 6, w = C.frameW - 20, h = C.plaqueH },
			shelf = { x = 0, y = y + C.frameH + 6 + C.plaqueH + 2, w = areaW, h = 6 },
		}
	end
	local bw, y = 150, C.barTop
	out.plates = {
		tabs = { { x = C.side, y = y, w = bw, h = C.barH }, { x = C.side + bw + 10, y = y, w = bw, h = C.barH } },
		page = { x = areaW - C.side - 3 * bw - 20, y = y, w = bw, h = C.barH },
		prev = { x = areaW - C.side - 2 * bw - 10, y = y, w = bw, h = C.barH },
		next = { x = areaW - C.side - bw, y = y, w = bw, h = C.barH },
	}
	return out
end

function M.pageCount(n)
	return math.max(1, math.ceil(n / M.PER_PAGE))
end

function M.pageSlice(list, page)
	local pages = M.pageCount(#list)
	page = math.max(1, math.min(pages, page))
	local out = {}
	for i = (page - 1) * M.PER_PAGE + 1, math.min(#list, page * M.PER_PAGE) do out[#out + 1] = list[i] end
	return out, page, pages
end

return M
