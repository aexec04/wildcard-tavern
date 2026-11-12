--[[
	Shared/Engine/FlairSceneLayout.lua
	Pure geometry for the Flair dressing room painted scene (art `panel_scene`, key flair_room_a, 1536x1024; Client/FlairDressingRoom.lua).
	The slots were read off the PNG (art-wip/panel_scene/flair_room_slots.py draws them on debug_flair_room_a.png) and are stored in the
	picture's own pixels; place() turns them into the area's pixels. The picture is cover-fitted into the area and shrinks below cover so every
	slot keeps MARGIN of clear room; it is never stretched. ok is false when a slot would be too small to read (the caller keeps the plain layout).

	M.IMAGE_W, M.IMAGE_H, M.MARGIN, M.ART_KEY
	M.place(areaW, areaH) -> { ok, image = {x,y,w,h}, tabs = { rect x6 }, cubbies = { rect x12, row by row }, bounds = rect of all cubbies,
	                           mirror, plaque, detail }   all in the area's pixels
	M.cell(w, h)          -> { med, nameH, tagH, w, h } for a flair tile that fills a cubby of w x h
	M.CUBBIES             12 (4 columns x 3 rows); a category with more pieces is not possible (tested against Flair)
]]

local M = {}

M.IMAGE_W, M.IMAGE_H = 1536, 1024
M.MARGIN = 8
M.PAD = 14
M.ART_KEY = "flair_room_a"
M.CUBBIES = 12

local TABS = {}
for i = 0, 5 do TABS[#TABS + 1] = { x = 110, y = 170 + 97 * i, w = 230, h = 76 } end
local COLS = { { 432, 142 }, { 606, 136 }, { 772, 134 }, { 936, 134 } }
local ROWS = { { 200, 155 }, { 395, 150 }, { 590, 148 } }
local MIRROR = { x = 1205, y = 252, w = 158, h = 450 }
local PLAQUE = { x = 1108, y = 868, w = 380, h = 74 }
local DETAIL = { x = 420, y = 790, w = 650, h = 190 }

-- smallest sizes (px) at which text stays readable (nothing under 14)
M.MIN = { tab = { 130, 40 }, cubby = { 80, 88 }, mirror = { 96, 200 }, detail = { 272, 110 } }

M.PICTURE = { tabs = TABS, mirror = MIRROR, plaque = PLAQUE, detail = DETAIL }

local function pictureCubbies()
	local out = {}
	for _, r in ipairs(ROWS) do
		for _, c in ipairs(COLS) do out[#out + 1] = { x = c[1], y = r[1], w = c[2], h = r[2] } end
	end
	return out
end
M.pictureCubbies = pictureCubbies

local function clampRange(v, lo, hi)
	if lo > hi then return (lo + hi) / 2 end
	return math.max(lo, math.min(hi, v))
end

-- offset of the picture along one axis: centred, covering the view when it can, keeping b0..b1 (picture px) inside
local function offset(viewLen, picLen, s, b0, b1)
	local o = (viewLen - picLen * s) / 2
	local lo, hi
	if picLen * s >= viewLen then lo, hi = viewLen - picLen * s, 0 else lo, hi = o, o end
	local lo2, hi2 = -b0 * s, viewLen - b1 * s
	local a, b = math.max(lo, lo2), math.min(hi, hi2)
	if a > b then return clampRange(o, lo2, hi2) end
	return clampRange(o, a, b)
end

function M.place(areaW, areaH)
	local mg = M.MARGIN
	local cubs = pictureCubbies()
	local all = { MIRROR, PLAQUE, DETAIL }
	for _, t in ipairs(TABS) do all[#all + 1] = t end
	for _, c in ipairs(cubs) do all[#all + 1] = c end
	local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
	for _, r in ipairs(all) do
		x0, y0 = math.min(x0, r.x), math.min(y0, r.y)
		x1, y1 = math.max(x1, r.x + r.w), math.max(y1, r.y + r.h)
	end
	x0, y0, x1, y1 = x0 - M.PAD, y0 - M.PAD, x1 + M.PAD, y1 + M.PAD
	local W, H = math.max(1, areaW), math.max(1, areaH)
	local cover = math.max(W / M.IMAGE_W, H / M.IMAGE_H)
	local fit = math.min((W - 2 * mg) / (x1 - x0), (H - 2 * mg) / (y1 - y0))
	local s = math.min(cover, fit)
	local ix, iy = offset(W, M.IMAGE_W, s, x0 - mg / s, x1 + mg / s), offset(H, M.IMAGE_H, s, y0 - mg / s, y1 + mg / s)
	local function map(r)
		return { x = math.floor(ix + r.x * s), y = math.floor(iy + r.y * s), w = math.floor(r.w * s), h = math.floor(r.h * s) }
	end
	local out = { image = { x = ix, y = iy, w = M.IMAGE_W * s, h = M.IMAGE_H * s }, tabs = {}, cubbies = {}, ok = true, scale = s }
	for i, t in ipairs(TABS) do
		out.tabs[i] = map(t)
		if out.tabs[i].w < M.MIN.tab[1] or out.tabs[i].h < M.MIN.tab[2] then out.ok = false end
	end
	local bx0, by0, bx1, by1 = math.huge, math.huge, -math.huge, -math.huge
	for i, c in ipairs(cubs) do
		local r = map(c)
		out.cubbies[i] = r
		bx0, by0 = math.min(bx0, r.x), math.min(by0, r.y)
		bx1, by1 = math.max(bx1, r.x + r.w), math.max(by1, r.y + r.h)
		if r.w < M.MIN.cubby[1] or r.h < M.MIN.cubby[2] then out.ok = false end
	end
	out.bounds = { x = bx0, y = by0, w = bx1 - bx0, h = by1 - by0 }
	out.mirror, out.plaque, out.detail = map(MIRROR), map(PLAQUE), map(DETAIL)
	if out.mirror.w < M.MIN.mirror[1] or out.mirror.h < M.MIN.mirror[2] then out.ok = false end
	if out.detail.w < M.MIN.detail[1] or out.detail.h < M.MIN.detail[2] then out.ok = false end
	return out
end

-- a flair tile that fills a cubby: round icon on top, then a name (two lines when the cubby is tall enough) and a one-line status (14 px each)
function M.cell(w, h)
	local tagH = 18
	local nameH = h >= 110 and 34 or 18
	local med = math.max(30, math.min(68, h - (6 + 4 + nameH + 2 + tagH + 4)))
	return { med = med, nameH = nameH, tagH = tagH, w = w, h = h, lines = nameH >= 30 and 2 or 1 }
end

-- Pieces that make the one picture cover the whole body when it cannot (it shrinks so every slot keeps its room): eight slices of
-- the picture's own edge (4 px) stretched over the uncovered bands and corners, each { name, rect (area px), src = { x, y, w, h } (picture px) }.
-- They run 1 px under the picture, which is drawn after them.
M.EDGE = 4
function M.edgeFill(p, areaW, areaH)
	local I, e, E = p.image, M.EDGE, M.EDGE
	local W, H = M.IMAGE_W, M.IMAGE_H
	local out = {}
	local x1, y1 = I.x + I.w, I.y + I.h
	local function add(name, x, y, w, h, sx, sy, sw, sh)
		if w > 0.5 and h > 0.5 then
			out[#out + 1] = { name = name, rect = { x = math.floor(x), y = math.floor(y), w = math.ceil(w), h = math.ceil(h) }, src = { x = sx, y = sy, w = sw, h = sh } }
		end
	end
	local midY0, midY1 = math.max(0, I.y), math.min(areaH, y1)
	local midX0, midX1 = math.max(0, I.x), math.min(areaW, x1)
	-- left / right bands sit level with the picture, top / bottom above and below it, the corners take the corner pixels
	add("Left", 0, midY0, I.x + 1, midY1 - midY0, 0, 0, e, H)
	add("Right", x1 - 1, midY0, areaW - x1 + 1, midY1 - midY0, W - e, 0, e, H)
	add("Top", midX0, 0, midX1 - midX0, I.y + 1, 0, 0, W, E)
	add("Bottom", midX0, y1 - 1, midX1 - midX0, areaH - y1 + 1, 0, H - E, W, E)
	add("TopLeft", 0, 0, I.x + 1, I.y + 1, 0, 0, e, E)
	add("TopRight", x1 - 1, 0, areaW - x1 + 1, I.y + 1, W - e, 0, e, E)
	add("BottomLeft", 0, y1 - 1, I.x + 1, areaH - y1 + 1, 0, H - E, e, E)
	add("BottomRight", x1 - 1, y1 - 1, areaW - x1 + 1, areaH - y1 + 1, W - e, H - E, e, E)
	return out
end

-- the plates of categories that do not exist stay unused: a patch of plain stucco wall (picture px 110,108 230x56, above the first plate)
-- is stretched over each one and a little beyond its brass edge
M.WALL = { x = 110, y = 108, w = 230, h = 56 }
function M.platePatches(p, categories)
	local out = {}
	local g = 4 * (p.scale or 1)
	for i = categories + 1, #p.tabs do
		local t = p.tabs[i]
		out[#out + 1] = { index = i, rect = { x = math.floor(t.x - g), y = math.floor(t.y - g), w = math.ceil(t.w + 2 * g), h = math.ceil(t.h + 2 * g) }, src = M.WALL }
	end
	return out
end

return M
