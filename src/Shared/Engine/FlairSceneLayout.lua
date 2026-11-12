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
-- the dark glass of the painted arched door, measured from flair_room_a.png (tools/_measure_flair_door.py draws it): straight sides and
-- floor, a semicircular top of radius w / 2
local MIRROR = { x = 1201, y = 241, w = 155, h = 455 }
local PLAQUE = { x = 1108, y = 868, w = 380, h = 74 }
local DETAIL = { x = 420, y = 790, w = 650, h = 190 }

-- smallest sizes (px) at which text stays readable (nothing under 14)
M.MIN = { tab = { 130, 40 }, cubby = { 80, 88 }, mirror = { 96, 200 }, detail = { 272, 110 } }

-- the arched glass as two pieces in the mirror's own pixels: a circle of diameter w on top and a rectangle below its centre line
function M.arch(mirror)
	local r = math.floor(mirror.w / 2)
	return { top = { x = 0, y = 0, w = mirror.w, h = mirror.w }, body = { x = 0, y = r, w = mirror.w, h = math.max(1, mirror.h - r) }, radius = r }
end

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

-- a flair tile that fills a cubby: round icon on top, the name on two lines (38 px: Roblox only fits two 14 px lines in 36 or more, a
-- 34 px box cut the second line and drew dots) and, when the cubby is tall enough, a one-line status
function M.cell(w, h)
	local tagH = 18
	local nameH = 38
	local showTag = h >= 112
	local med = math.max(28, math.min(68, h - (6 + 4 + nameH + 4 + (showTag and (tagH + 2) or 0))))
	return { med = med, nameH = nameH, tagH = tagH, showTag = showTag, w = w, h = h, lines = 2 }
end

-- The soft vignette that melts the picture's uncovered edges into the dark fill (geometry: Engine/PanelSceneLayout.feather).
function M.feather(p, areaW, areaH)
	return require(script.Parent.PanelSceneLayout).feather(p, areaW, areaH)
end

return M
