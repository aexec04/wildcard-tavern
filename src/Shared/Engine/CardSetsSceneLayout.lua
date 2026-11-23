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

-- The room (second pass): one large hero preview on the left (about 40 percent of the width) and a shelf of 5 tile columns on the right,
-- each row of tiles standing on a drawn shelf board. Single Equip or Buy button under the hero. Everything is drawn in code over the
-- Collection wall (no grid of identical boxes). Rects are in the area's pixels (the panel body between TOP and BOTTOM).
-- room(areaW, areaH, n, page) -> { ok, cols, rows, perPage, pages, page, plates = { tabs = {sets, backs}, page, prev, next }, hero, parts, shelf,
--                                  cells = { { tile, pic, name, state, board } ... } }
M.ROOM = { side = 24, gap = 16, tileGap = 10, nameH = 30, stateH = 22, boardH = 8, barTop = 4, barH = 44, heroFrac = 0.40, cols = 5 }
M.ROOM_PANEL_FRAC = { 0.94, 0.94 }
M.ROOM_PANEL_MAX = { 1500, 900 }
M.ROOM_MIN = { w = 640, h = 400 }

function M.roomPanel(screenW, screenH)
	return PS.panelSize(screenW, screenH, M.ROOM_PANEL_FRAC[1], M.ROOM_PANEL_FRAC[2], M.ROOM_PANEL_MAX[1], M.ROOM_PANEL_MAX[2])
end

-- inside the hero: name plate, a mini table (with a fan of 5 cards and the back on a stand, or one large back), a description, the button
-- The card back turns over once when a different tile is picked: { seconds = 0.25 }, or nil in Calm mode and Reduce motion (no cover, no
-- tween) and when the pick did not change (a repaint of the same entry).
M.FLIP_SECONDS = 0.25
function M.flipPlan(calm, lastKey, key)
	if calm == true or key == nil or key == lastKey then return nil end
	return { seconds = M.FLIP_SECONDS }
end

function M.heroParts(hero)
	local plate = { x = hero.x + 12, y = hero.y + 10, w = hero.w - 24, h = 34 }
	local bw = math.min(200, hero.w - 24)
	local button = { x = hero.x + math.floor((hero.w - bw) / 2), y = hero.y + hero.h - 10 - 44, w = bw, h = 44 }
	local descH = hero.h < 300 and 0 or 30 -- a short window drops the description line, the table keeps its size
	local desc = { x = hero.x + 12, y = button.y - 6 - descH, w = hero.w - 24, h = descH }
	local ty = plate.y + plate.h + 8
	local tbl = { x = hero.x + 12, y = ty, w = hero.w - 24, h = desc.y - 6 - ty }
	local sp = M.sceneParts(tbl)
	local fp = M.fanParts(sp.felt)
	local bh = sp.felt.h - 32 -- 16 px clear all round, so a tilted back and its shadow stay on the felt
	local bw2 = math.floor(bh * 2 / 3)
	local big = { x = sp.felt.x + math.floor((sp.felt.w - bw2) / 2), y = sp.felt.y + 16, w = bw2, h = bh }
	return { plate = plate, button = button, desc = desc, table = tbl, rail = sp.rail, felt = sp.felt, prop = sp.prop, fan = fp.fan, back = fp.back,
		stand = fp.stand, fanInfo = fp, big = big }
end

-- The mini table scene (hero and tiles): the room picture fills `scene`, a wooden rail and the felt sit inset in it, a prop (candle, lantern,
-- snowflakes, leaves) stands in the free band above the table. A short scene (small window) uses the whole scene as the table, no prop.
M.RAIL = 9
M.FAN_ROT = 4 -- degrees per fan step (cards 1 to 5 turn -8, -4, 0, 4, 8)
function M.sceneParts(scene)
	local tall = scene.h >= 150
	local mx, top, bot = math.floor(scene.w * 0.06), math.floor(scene.h * 0.22), math.floor(scene.h * 0.05)
	local rail = tall and { x = scene.x + mx, y = scene.y + top, w = scene.w - 2 * mx, h = scene.h - top - bot }
		or { x = scene.x, y = scene.y, w = scene.w, h = scene.h }
	local rw = tall and M.RAIL or 5
	local felt = { x = rail.x + rw, y = rail.y + rw, w = rail.w - 2 * rw, h = rail.h - 2 * rw }
	local prop = tall and { x = scene.x + mx, y = scene.y + 4, w = math.floor(scene.w * 0.2), h = top - 8 } or nil
	return { rail = rail, felt = felt, prop = prop }
end

-- Five fanned cards plus the back on its stand, all inside the felt with `margin` (24 px, less on a very short felt) around the turned
-- extent of every card (ex, ey = extra half extents a turned card takes).
function M.fanParts(felt)
	local margin = felt.h >= 140 and 24 or math.max(6, math.floor(felt.h / 6))
	local gap = 10
	local byW = (felt.w - 2 * margin - gap) / 4.04
	local byH = (felt.h - 2 * margin - 6) / 1.9
	local cardW = math.max(8, math.floor(math.min(byW, byH)))
	local cardH = math.floor(cardW * 3 / 2)
	local ex, ey = math.ceil(cardH * 0.08), math.ceil(cardW * 0.2)
	local step = math.floor(cardW * 0.45)
	local y = felt.y + math.floor((felt.h - cardH - 6) / 2)
	local fan = {}
	for i = 1, 5 do fan[i] = { x = felt.x + margin + ex + (i - 1) * step, y = y, w = cardW, h = cardH } end
	local back = { x = felt.x + felt.w - margin - ex - cardW, y = y, w = cardW, h = cardH }
	local stand = { x = back.x - 6, y = back.y + back.h, w = cardW + 12, h = 6 }
	return { cardW = cardW, cardH = cardH, margin = margin, ex = ex, ey = ey, fan = fan, back = back, stand = stand }
end

-- a tile picture: the room picture fills `pic`, a small table inset in it with three cards (A K Q) side by side
function M.tileScene(pic)
	local mx, top, bot = math.floor(pic.w * 0.08), math.floor(pic.h * 0.26), math.floor(pic.h * 0.08)
	local rail = { x = pic.x + mx, y = pic.y + top, w = pic.w - 2 * mx, h = pic.h - top - bot }
	local felt = { x = rail.x + 3, y = rail.y + 3, w = rail.w - 6, h = rail.h - 6 }
	local ch = math.floor(math.min(felt.h - 8, (felt.w - 8) / 2.56 * 1.5))
	local cw = math.floor(ch * 2 / 3)
	local step = math.floor(cw * 0.78)
	local x0 = felt.x + math.floor((felt.w - (cw + 2 * step)) / 2)
	local y = felt.y + math.floor((felt.h - ch) / 2)
	local cards = {}
	for k = 1, 3 do cards[k] = { x = x0 + (k - 1) * step, y = y, w = cw, h = ch } end
	return { rail = rail, felt = felt, cards = cards }
end

-- One preview answer per Card Set tile: every set returns the same keys, so every tile has the same layout with its own room, keeper and
-- plate accent. The plate fill is the accent pulled toward dark until the cream ink reads at 4.5:1.
-- tilePreview(setId) -> { setId, room, keeperBehind, keeperWave, plateFill, plateInk, ratio }
M.INK = { 250, 240, 220 }
M.MIN_INK_CONTRAST = 4.5
function M.tilePreview(setId)
	local TS = require(script.Parent.ThemeScenes)
	local CS = require(script.Parent.CosmeticSets)
	local sc = TS.of(setId)
	local set = CS.getById(sc.setId)
	local a = (set and CS.accentOf(set)) or sc.tint or { 170, 126, 60 }
	local dark = { 30, 20, 12 }
	local t, fill = 0.3, nil
	for _ = 1, 20 do
		fill = {}
		for i = 1, 3 do fill[i] = math.floor(a[i] + (dark[i] - a[i]) * t + 0.5) end
		if CS.contrastRatio(M.INK, fill) >= M.MIN_INK_CONTRAST then break end
		t = math.min(1, t + 0.05)
	end
	local behind, wave = TS.shopKeeperIds(sc.setId)
	return {
		setId = sc.setId,
		room = TS.themeImageId(sc.setId, "tableBackground"),
		keeperBehind = behind, keeperWave = wave,
		plateFill = fill, plateInk = M.INK, ratio = CS.contrastRatio(M.INK, fill),
	}
end

function M.room(areaW, areaH, n, page)
	local R = M.ROOM
	local top = R.barTop + R.barH + 8
	local hero = { x = R.side, y = top, w = math.floor(areaW * R.heroFrac) - R.side, h = areaH - top - 10 }
	local shelf = { x = hero.x + hero.w + R.gap, y = top, w = areaW - R.side - (hero.x + hero.w + R.gap), h = hero.h - R.barH - 8 } -- the page plates take the foot
	local cols = R.cols
	local tileW = math.floor((shelf.w - (cols - 1) * R.tileGap) / cols)
	local picH = math.floor(tileW * 0.8)
	local fixed = R.nameH + R.stateH + 6 + R.boardH + 8 -- name, state line, padding and the shelf board under every tile
	if shelf.h < picH + fixed then
		picH = math.max(28, shelf.h - fixed) -- a short window shrinks the picture so one full row still fits
	else
		local needRows = math.ceil(n / cols)
		if needRows > 1 and math.floor(shelf.h / (picH + fixed)) < needRows then
			local fit = math.floor(shelf.h / needRows) - fixed -- a little shorter picture keeps every entry on one page when it can
			if fit >= math.floor(tileW * 0.55) then picH = fit end
		end
	end
	local tileH = picH + R.nameH + R.stateH + 6
	local rowH = tileH + R.boardH + 8
	local rows = math.max(0, math.floor(shelf.h / rowH))
	local parts = M.heroParts(hero)
	local out = { cols = cols, rows = math.max(rows, 1), hero = hero, shelf = shelf, parts = parts, cells = {} }
	out.ok = hero.w >= 200 and hero.h >= 160 and tileW >= 60 and rows >= 1 and parts.table.h >= 56
	out.perPage = cols * out.rows
	out.pages = math.max(1, math.ceil(n / out.perPage))
	out.page = math.max(1, math.min(out.pages, page or 1))
	local first = (out.page - 1) * out.perPage
	local onPage = math.max(0, math.min(out.perPage, n - first))
	local x0 = shelf.x + math.floor((shelf.w - (cols * tileW + (cols - 1) * R.tileGap)) / 2)
	for i = 1, onPage do
		local r, c = math.floor((i - 1) / cols), (i - 1) % cols
		local x, y = x0 + c * (tileW + R.tileGap), shelf.y + r * rowH
		out.cells[i] = {
			tile = { x = x, y = y, w = tileW, h = tileH },
			pic = { x = x + 3, y = y + 3, w = tileW - 6, h = picH },
			name = { x = x + 2, y = y + picH + 5, w = tileW - 4, h = R.nameH },
			state = { x = x + 2, y = y + picH + 5 + R.nameH, w = tileW - 4, h = R.stateH },
			board = { x = shelf.x - 4, y = y + tileH + 1, w = shelf.w + 8, h = R.boardH },
		}
	end
	local bw, cw, y = 150, 104, R.barTop
	local py = shelf.y + shelf.h + 8 -- the three page plates stand in a row under the shelf
	local px = shelf.x + math.floor((shelf.w - (3 * cw + 20)) / 2)
	out.plates = {
		tabs = { { x = R.side, y = y, w = bw, h = R.barH }, { x = R.side + bw + 10, y = y, w = bw, h = R.barH } },
		prev = { x = px, y = py, w = cw, h = R.barH },
		page = { x = px + cw + 10, y = py, w = cw, h = R.barH },
		next = { x = px + 2 * (cw + 10), y = py, w = cw, h = R.barH },
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
