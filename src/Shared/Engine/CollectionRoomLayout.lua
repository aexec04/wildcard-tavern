--[[
	Shared/Engine/CollectionRoomLayout.lua
	Pure geometry and wording for the Collection's gallery room (Client/CollectionRoom.lua): six objects on the room's walls, one per
	Collection section, each a hotspot with a carved name plate under it that carries the count ("Recipes 3/24"). It also holds the
	panel's vertical order (title, progress line, the quiet row of small tab plates, the room or section grid, the wooden rarity filter
	plate, the Close row), so the room, the section view and the filter all take their place from ONE set of tested numbers.

	M.SECTIONS                          { { id, object, aspect } } in room order; ids are CollectionBook.Tabs ids
	M.plateText(label, found, total)    "Recipes 3/24"
	M.plateTextSize(plateW)             16, or 14 on a narrow plate (never below 14)
	M.panel(W, H, legendH, chestX)      -> { title, bar, tabs, area, filter, close } rects in the panel's pixels
	M.rects(w, h)                       -> { spots = { [id] = { object, plate, hit } }, order, cols, rows } in the room's pixels
	M.inside(r, w, h) / M.intersects(a, b)
]]

local M = {}

-- Room order. `object` names the drawn furniture (a painted room replaces the drawing and keeps these hotspots); `aspect` is the
-- object's width over height.
M.SECTIONS = {
	{ id = "patrons", object = "portraits", aspect = 1.5 },
	{ id = "recipes", object = "cork", aspect = 1.35 },
	{ id = "bosses", object = "trophies", aspect = 1.5 },
	{ id = "housePasses", object = "keys", aspect = 1.4 },
	{ id = "titles", object = "plates", aspect = 1.6 },
	{ id = "bonds", object = "bonds", aspect = 1.35 },
}

-- ===== the panel's vertical order =====
M.SIDE = 15 -- side margin of everything under the title
M.BAR = { y = 36, h = 22 } -- overall progress line
M.TABS = { y = 62, h = 26 } -- the quiet row of small tab plates
M.AREA_TOP = 94 -- the room and the section grid start here
M.FOOTER = 58 -- the Close row at the bottom of the panel
M.FILTER_MAX_W = 620
M.FILTER_PAD = 4 -- room above and below the chips inside the wooden plate
M.FILTER_GAP = 6 -- between the area and the filter plate
M.FILTER_MIN_W = 160

-- legendH = the height of the rarity chips as laid out (they wrap on a narrow panel); chestX = the left edge of the milestone chest
-- when it is on screen (the centred filter plate stays left of it), else nil.
function M.panel(W, H, legendH, chestX)
	local side = M.SIDE
	local chipsH = math.max(24, math.ceil(legendH or 24))
	local filterH = chipsH + 2 * M.FILTER_PAD
	local filterW = math.min(M.FILTER_MAX_W, math.max(M.FILTER_MIN_W, W - 2 * side))
	if chestX then
		filterW = math.min(filterW, math.max(M.FILTER_MIN_W, 2 * (chestX - 8) - W))
	end
	filterW = math.floor(filterW)
	local filter = { x = math.floor((W - filterW) / 2), y = H - M.FOOTER - filterH, w = filterW, h = filterH }
	local areaH = math.max(60, filter.y - M.FILTER_GAP - M.AREA_TOP)
	return {
		title = { x = 0, y = 6, w = W, h = 28 },
		bar = { x = side, y = M.BAR.y, w = W - 2 * side, h = M.BAR.h },
		tabs = { x = side, y = M.TABS.y, w = W - 2 * side, h = M.TABS.h },
		area = { x = side, y = M.AREA_TOP, w = W - 2 * side, h = areaH },
		filter = filter,
		close = { x = math.floor(W / 2 - 70), y = H - 50, w = 140, h = 40 },
	}
end

-- ===== the room =====
M.MARGIN = 10 -- between the room's edge and the outer objects
M.GAP = 10 -- between two cells
M.PLATE_H = 28
M.PLATE_GAP = 4 -- object bottom to plate top
M.PLATE_MIN_W = 150 -- "House Passes 12/12" at 16 px bold fits in 150
M.MIN_OBJECT_H = 8

function M.columns(w)
	return w >= 560 and 3 or 2
end

function M.plateText(label, found, total)
	return string.format("%s %d/%d", tostring(label), math.floor(found or 0), math.floor(total or 0))
end

function M.plateTextSize(plateW)
	return plateW >= 180 and 16 or 14
end

local function union(a, b)
	local x0, y0 = math.min(a.x, b.x), math.min(a.y, b.y)
	local x1, y1 = math.max(a.x + a.w, b.x + b.w), math.max(a.y + a.h, b.y + b.h)
	return { x = x0, y = y0, w = x1 - x0, h = y1 - y0 }
end

function M.rects(w, h)
	local n = #M.SECTIONS
	local cols = M.columns(w)
	local rows = math.ceil(n / cols)
	local cellW = math.floor((w - 2 * M.MARGIN - (cols - 1) * M.GAP) / cols)
	local cellH = math.floor((h - 2 * M.MARGIN - (rows - 1) * M.GAP) / rows)
	local usedW = cols * cellW + (cols - 1) * M.GAP
	local usedH = rows * cellH + (rows - 1) * M.GAP
	local x0, y0 = math.floor((w - usedW) / 2), math.floor((h - usedH) / 2) -- slack from the integer division is split evenly
	local spots, order = {}, {}
	for i, s in ipairs(M.SECTIONS) do
		local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
		local cx, cy = x0 + col * (cellW + M.GAP), y0 + row * (cellH + M.GAP)
		local objH = math.max(M.MIN_OBJECT_H, cellH - M.PLATE_H - M.PLATE_GAP)
		local objW = math.min(cellW, math.floor(objH * s.aspect))
		local object = { x = cx + math.floor((cellW - objW) / 2), y = cy, w = objW, h = objH }
		local plateW = math.min(cellW, math.max(objW, M.PLATE_MIN_W))
		local plate = { x = cx + math.floor((cellW - plateW) / 2), y = cy + objH + M.PLATE_GAP, w = plateW, h = M.PLATE_H }
		spots[s.id] = { object = object, plate = plate, hit = union(object, plate) }
		order[i] = s.id
	end
	return { spots = spots, order = order, cols = cols, rows = rows }
end

function M.inside(r, w, h)
	return r.x >= 0 and r.y >= 0 and r.x + r.w <= w and r.y + r.h <= h
end

function M.intersects(a, b)
	return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

return M
