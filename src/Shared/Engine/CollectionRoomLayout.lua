--[[
	Shared/Engine/CollectionRoomLayout.lua
	Pure geometry and wording for the Collection's gallery room (Client/CollectionRoom.lua): six objects on the room's walls, one per
	Collection section, each a hotspot with a carved name plate under it that carries the count ("Recipes 3/24"). It also holds the
	panel's vertical order (title, progress line, the quiet row of small tab plates, the room or section grid, the wooden rarity filter
	plate, the Close row), so the room, the section view and the filter all take their place from ONE set of tested numbers.

	M.SECTIONS                          { { id, object, aspect } } in room order; ids are CollectionBook.Tabs ids
	M.plateText(label, found, total)    "Recipes 3/24"
	M.plateTextSize(plateW)             16, or 14 on a narrow plate (never below 14)
	M.chrome(mode)                      -> { tabs, rarityFilter } booleans: shown in "section", hidden in "room"
	M.panel(W, H, legendH, chestX, mode) -> { title, bar, tabs, area, filter, close } rects in the panel's pixels
	M.rects(w, h)                       -> { spots = { [id] = { object, plate, hit } }, order, cols, rows } in the room's pixels
	M.inside(r, w, h) / M.intersects(a, b)
]]

local Grid = require(script.Parent.RoomGrid)

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

-- The painted room (art `collection_scene` / `collection_room`, 1536x1024): the six objects as fractions of the picture, measured from
-- the generated PNG (x0, y0, x1, y1). The picture is cover-fitted into the room; see RoomGrid.painted.
M.PAINTED = {
	aspect = 1.5,
	order = { "patrons", "recipes", "bosses", "housePasses", "titles", "bonds" },
	rects = {
		patrons = { 0.117, 0.215, 0.342, 0.400 },
		recipes = { 0.411, 0.215, 0.594, 0.436 },
		bosses = { 0.661, 0.244, 0.884, 0.454 },
		housePasses = { 0.118, 0.542, 0.337, 0.725 },
		titles = { 0.398, 0.559, 0.607, 0.708 },
		bonds = { 0.682, 0.537, 0.856, 0.729 },
	},
}

function M.paintedRects(w, h)
	return Grid.painted(M.PAINTED, w, h)
end

-- ===== the panel's vertical order =====
M.SIDE = 15 -- side margin of everything under the title
M.BAR = { y = 36, h = 22 } -- overall progress line
M.TABS = { y = 62, h = 26 } -- the quiet row of small tab plates
M.AREA_TOP = 94 -- (the old top of the section area; a section now starts under the progress line, see panel)
M.STRIP_H = 28 -- the slim strip along the bottom of a section: tab plates on the left, the page arrows and plate on the right
M.STRIP_GAP = 6
M.PAGER_W = 184 -- two 36 px arrows, the 104 px page plate and their gaps (CollectionSectionLayout.pager)
M.FOOTER = 58 -- the Close row at the bottom of the panel
M.FILTER_MAX_W = 620
M.FILTER_PAD = 4 -- room above and below the chips inside the wooden plate
M.FILTER_GAP = 6 -- between the area and the filter plate
M.FILTER_MIN_W = 160

-- legendH = the height of the rarity chips as laid out (they wrap on a narrow panel); chestX = the left edge of the milestone chest
-- when it is on screen (the centred filter plate stays left of it), else nil.
-- What the panel shows per view: the gallery room has its own hotspots, so the section plates and the rarity filter (nothing there can
-- be sorted) are hidden and the room takes their height; a section shows both.
function M.chrome(mode)
	local section = mode == "section"
	return { tabs = section, rarityFilter = section }
end

function M.panel(W, H, legendH, chestX, mode)
	local side = M.SIDE
	local chrome = M.chrome(mode or "section")
	local chipsH = math.max(24, math.ceil(legendH or 24))
	local filterH = chipsH + 2 * M.FILTER_PAD
	local filterW = math.min(M.FILTER_MAX_W, math.max(M.FILTER_MIN_W, W - 2 * side))
	if chestX then
		filterW = math.min(filterW, math.max(M.FILTER_MIN_W, 2 * (chestX - 8) - W))
	end
	filterW = math.floor(filterW)
	local filter = { x = math.floor((W - filterW) / 2), y = H - M.FOOTER - filterH, w = filterW, h = filterH }
	-- the scene (or grid) gets its own region: under the one-line banner (title and progress), above ONE slim strip that holds the
	-- tab plates, the rarity filter and the page plate; nothing else is drawn over it
	local areaTop, areaBottom = M.TABS.y, filter.y - M.FILTER_GAP
	local tabs = { x = side, y = M.TABS.y, w = W - 2 * side, h = M.TABS.h }
	local pager
	if chrome.tabs then
		local stripY = filter.y - M.FILTER_GAP - M.STRIP_H
		local pagerW = W >= 560 and M.PAGER_W or 0
		tabs = { x = side, y = stripY, w = W - 2 * side - (pagerW > 0 and pagerW + 8 or 0), h = M.TABS.h }
		if pagerW > 0 then pager = { x = W - side - pagerW, y = stripY, w = pagerW, h = M.STRIP_H } end
		areaBottom = stripY - M.STRIP_GAP
	end
	if not chrome.rarityFilter then areaBottom = H - M.FOOTER end
	local areaH = math.max(60, areaBottom - areaTop)
	return {
		title = { x = 0, y = 6, w = W, h = 28 },
		bar = { x = side, y = M.BAR.y, w = W - 2 * side, h = M.BAR.h },
		tabs = tabs,
		pager = pager,
		area = { x = side, y = areaTop, w = W - 2 * side, h = areaH },
		filter = filter,
		close = { x = math.floor(W / 2 - 70), y = H - 50, w = 140, h = 40 },
	}
end

-- ===== the room (the grid maths is Engine/RoomGrid.lua, shared with the Badges trophy room) =====
M.MARGIN, M.GAP, M.PLATE_H, M.PLATE_GAP, M.PLATE_MIN_W, M.MIN_OBJECT_H = Grid.MARGIN, Grid.GAP, Grid.PLATE_H, Grid.PLATE_GAP, Grid.PLATE_MIN_W, Grid.MIN_OBJECT_H

function M.columns(w)
	return w >= 560 and 3 or 2
end

M.plateText = Grid.plateText
M.plateTextSize = Grid.plateTextSize
M.inside = Grid.inside
M.intersects = Grid.intersects

function M.rects(w, h)
	return Grid.rects(M.SECTIONS, w, h, M.columns(w))
end

return M
