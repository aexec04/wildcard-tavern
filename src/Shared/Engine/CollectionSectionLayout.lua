--[[
	Shared/Engine/CollectionSectionLayout.lua
	Pure geometry for the Collection's painted section scenes (Client/CollectionSection.lua). Each section opened from the gallery room is
	ONE painted close-up of its own furniture (art `collection_scene`, keys coll_sec_<section>_a, 1536x1024) with a fixed number of empty
	painted slots; the code puts each entry into a slot and pages through the section (12 entries a page, Bonds 8).

	The slot rectangles were read off the generated PNGs (art-wip/collection_scene, with debug overlays in art-wip/collection_scene/debug_*.png)
	and are stored in the picture's own 1536x1024 pixels; every public function turns them into the area's pixels, so they are fractions of
	the picture in effect (px / 1536, px / 1024).

	M.IMAGE_W, M.IMAGE_H                    1536, 1024
	M.PAGER_H                               height of the strip under the scene that holds the page arrows and the page plate
	M.has(tabId)                            true for the six sections that have a scene
	M.artKey(tabId)                         the collection_scene key ("coll_sec_patrons_a")
	M.perPage(tabId)                        12 (Bonds 8)
	M.pageCount(n, tabId)                   at least 1
	M.clampPage(page, n, tabId)
	M.pageItems(items, tabId, page)         the entries of one page, in order
	M.pageText(page, pages)                 "Page 2 of 7"
	M.place(tabId, areaW, areaH, pages)     -> { ok, image = {x,y,w,h}, view = {x,y,w,h}, slots = { { x,y,w,h, inner, plate } },
	                                             pager = { prev, label, next } | nil }
	                                        all in the area's pixels. The picture is cover-fitted into `view` (the area minus the pager
	                                        strip) and only shrinks below cover when a crop would cut a slot; it is never stretched.
	                                        ok is false when a slot would be too small to read (the caller keeps the old grid).
	M.inside(r, w, h) / M.intersects(a, b)
]]

local Grid = require(script.Parent.RoomGrid)

local M = {}

M.IMAGE_W, M.IMAGE_H = 1536, 1024
M.PAGER_H = 40
M.PAD = 14 -- picture pixels of wall kept around the outermost slots

-- cols = { { x, w } }, rows = { { y, h } } of the slot in picture pixels; `inset` = { left, top, right, bottom } fractions of the slot kept
-- clear of text (pins, tag holes, screws); `plate` = { { y }, h } the brass plate row under each slot (Patrons, Boss Rounds); `min` = the
-- smallest slot (in screen pixels) the scene is used at, below it the section keeps its scrolling grid (a paper tag is narrow, a plate wide).
local SCENES = {
	patrons = {
		art = "coll_sec_patrons_a", per = 12, kind = "portrait", min = { 80, 56 },
		cols = { { 242, 181 }, { 525, 182 }, { 817, 175 }, { 1088, 174 } },
		rows = { { 147, 145 }, { 380, 143 }, { 610, 142 } },
		plate = { ys = { 296, 529, 756 }, h = 24 },
	},
	recipes = {
		art = "coll_sec_recipes_a", per = 12, kind = "card", min = { 90, 60 },
		cols = { { 227, 247 }, { 511, 240 }, { 788, 240 }, { 1064, 244 } },
		rows = { { 157, 198 }, { 393, 196 }, { 626, 202 } },
		inset = { 0.06, 0.16, 0.06, 0.06 },
	},
	bosses = {
		art = "coll_sec_bosses_a", per = 12, kind = "portrait", min = { 72, 60 },
		cols = { { 259, 170 }, { 535, 170 }, { 817, 170 }, { 1098, 170 } },
		rows = { { 166, 134 }, { 394, 134 }, { 618, 134 } }, -- bottoms on the pedestal tops; the tops leave room for the plates above
		plate = { ys = { 349, 579, 811 }, h = 26 },
	},
	housePasses = {
		art = "coll_sec_passes_a", per = 12, kind = "tag", min = { 60, 70 },
		cols = { { 388, 109 }, { 588, 111 }, { 810, 109 }, { 1026, 110 } },
		rows = { { 240, 155 }, { 517, 151 }, { 790, 153 } },
		inset = { 0.08, 0.28, 0.08, 0.06 },
	},
	titles = {
		art = "coll_sec_titles_a", per = 12, kind = "plate", min = { 100, 50 },
		cols = { { 145, 282 }, { 477, 267 }, { 798, 264 }, { 1112, 281 } },
		rows = { { 222, 143 }, { 415, 143 }, { 605, 143 } },
		inset = { 0.12, 0.1, 0.12, 0.1 },
	},
	bonds = {
		art = "coll_sec_bonds_a", per = 8, kind = "card", min = { 90, 90 },
		cols = { { 242, 239 }, { 534, 214 }, { 797, 213 }, { 1067, 231 } },
		rows = { { 203, 272 }, { 540, 266 } },
		inset = { 0.07, 0.1, 0.07, 0.06 },
	},
}
M.SCENES = SCENES

function M.has(tabId) return SCENES[tabId] ~= nil end
function M.scene(tabId) return SCENES[tabId] end
function M.artKey(tabId) return SCENES[tabId] and SCENES[tabId].art end
function M.kind(tabId) return SCENES[tabId] and SCENES[tabId].kind end
function M.perPage(tabId) return SCENES[tabId] and SCENES[tabId].per or 12 end

function M.pageCount(n, tabId)
	return math.max(1, math.ceil((n or 0) / M.perPage(tabId)))
end

function M.clampPage(page, n, tabId)
	return math.max(1, math.min(M.pageCount(n, tabId), math.floor(tonumber(page) or 1)))
end

function M.pageItems(items, tabId, page)
	local per = M.perPage(tabId)
	local first = (M.clampPage(page, #items, tabId) - 1) * per
	local out = {}
	for i = first + 1, math.min(#items, first + per) do out[#out + 1] = items[i] end
	return out
end

function M.pageText(page, pages)
	return string.format("Page %d of %d", math.floor(page), math.floor(pages))
end

-- every slot of a scene in picture pixels, row by row: { x, y, w, h, plateY }
local function pictureSlots(tabId)
	local scene = SCENES[tabId]
	local out = {}
	for r, row in ipairs(scene.rows) do
		for _, col in ipairs(scene.cols) do
			out[#out + 1] = { x = col[1], y = row[1], w = col[2], h = row[2], plateY = scene.plate and scene.plate.ys[r] or nil }
		end
	end
	return out
end

local function clampRange(v, lo, hi)
	if lo > hi then return (lo + hi) / 2 end -- an exact fit can come out a rounding error apart
	return math.max(lo, math.min(hi, v))
end

-- the offset of the picture along one axis: centred like a cover crop, kept covering the view when it can, and always keeping the
-- slots' extent (b0..b1, in picture pixels) inside the view
local function offset(viewLen, picLen, s, b0, b1)
	local o = (viewLen - picLen * s) / 2
	local lo, hi
	if picLen * s >= viewLen then lo, hi = viewLen - picLen * s, 0 else lo, hi = o, o end
	local lo2, hi2 = -b0 * s, viewLen - b1 * s
	local a, b = math.max(lo, lo2), math.min(hi, hi2)
	if a > b then return clampRange(o, lo2, hi2) end
	return clampRange(o, a, b)
end

function M.place(tabId, areaW, areaH, pages)
	local scene = SCENES[tabId]
	if not scene then return nil end
	local pagerH = (pages or 1) > 1 and M.PAGER_H or 0
	local view = { x = 0, y = 0, w = areaW, h = math.max(1, areaH - pagerH) }
	local slots = pictureSlots(tabId)
	local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
	for _, s in ipairs(slots) do
		x0, y0 = math.min(x0, s.x), math.min(y0, s.y)
		x1, y1 = math.max(x1, s.x + s.w), math.max(y1, s.y + s.h)
		if s.plateY then y1 = math.max(y1, s.plateY + scene.plate.h) end
	end
	x0, y0, x1, y1 = x0 - M.PAD, y0 - M.PAD, x1 + M.PAD, y1 + M.PAD
	local cover = math.max(view.w / M.IMAGE_W, view.h / M.IMAGE_H)
	local fit = math.min(view.w / (x1 - x0), view.h / (y1 - y0))
	local s = math.min(cover, fit)
	local iw, ih = M.IMAGE_W * s, M.IMAGE_H * s
	local ix, iy = offset(view.w, M.IMAGE_W, s, x0, x1), offset(view.h, M.IMAGE_H, s, y0, y1)
	local out = { image = { x = ix, y = iy, w = iw, h = ih }, view = view, slots = {}, ok = true }
	local inset = scene.inset or { 0, 0, 0, 0 }
	for _, p in ipairs(slots) do
		local r = { x = math.floor(ix + p.x * s), y = math.floor(iy + p.y * s) }
		r.w, r.h = math.floor(p.w * s), math.floor(p.h * s)
		r.inner = {
			x = r.x + math.floor(r.w * inset[1]), y = r.y + math.floor(r.h * inset[2]),
			w = math.floor(r.w * (1 - inset[1] - inset[3])), h = math.floor(r.h * (1 - inset[2] - inset[4])),
		}
		if p.plateY then
			local ph = math.max(18, math.floor(scene.plate.h * s))
			-- wide enough to read a name at 14 px, but never into the next column's plate
			local pitch = (scene.cols[2][1] - scene.cols[1][1]) * s
			local pw = math.floor(math.min(pitch - 8, math.max(r.w * 0.94, 112)))
			r.plate = { x = math.max(0, math.min(view.w - pw, r.x + math.floor((r.w - pw) / 2))), y = math.floor(iy + (p.plateY + scene.plate.h / 2) * s - ph / 2), w = pw, h = ph }
		end
		out.slots[#out.slots + 1] = r
		if r.w < scene.min[1] or r.h < scene.min[2] then out.ok = false end
	end
	if pagerH > 0 then
		local by = view.h + 2
		local bh = pagerH - 6
		local plateW = 150
		local cx = math.floor(areaW / 2)
		out.pager = {
			prev = { x = cx - plateW / 2 - 8 - 44, y = by, w = 44, h = bh },
			label = { x = cx - plateW / 2, y = by, w = plateW, h = bh },
			next = { x = cx + plateW / 2 + 8, y = by, w = 44, h = bh },
		}
	end
	return out
end

M.inside = Grid.inside
M.intersects = Grid.intersects

return M
