--[[
	Shared/Engine/BadgeRoomLayout.lua
	Pure geometry for the Badges trophy room (Client/BadgeRoom.lua, Client/BadgesPanel.lua): four objects on the room's walls, one per
	shelf of badges (the pinned road map, the velvet display board, the night window, the shelves), each a hotspot with a carved name
	plate that carries its count ("Roads 2/8"). Also the panel's vertical order (the small wooden plaque, the quiet row of tab plates,
	the room or the zoomed object, Close), so the room and the zoomed wall take their place from one set of tested numbers. The grid
	maths is Engine/RoomGrid.lua (shared with the Collection's gallery room).

	M.SECTIONS                  { { id, object, aspect } } in room order; ids are the Badges.Chips names
	M.panel(W, H)               -> { plaque, tabs, area, close } rects in the panel's pixels
	M.rects(w, h)               -> { spots = { [id] = { object, plate, hit } }, order, cols, rows } in the room's pixels
	M.plateText / M.plateTextSize / M.inside / M.intersects
]]

local Grid = require(script.Parent.RoomGrid)

local M = {}

M.SECTIONS = {
	{ id = "Roads", object = "map", aspect = 1.5 },
	{ id = "Masters", object = "velvet", aspect = 1.4 },
	{ id = "Night", object = "sky", aspect = 1.3 },
	{ id = "Special", object = "shelves", aspect = 1.5 },
}

M.SIDE = 15
M.PLAQUE = { y = 6, h = 48, maxW = 360 } -- the small wooden plaque: Badges, "x of 32 earned" and the progress rail
M.TABS = { y = 60, h = 26 } -- the quiet row of small plates
M.AREA_TOP = 94 -- the room (or the zoomed wall) starts here
M.FOOTER = 52 -- the Close row at the bottom

function M.panel(W, H)
	local plateW = math.min(M.PLAQUE.maxW, W - 2 * M.SIDE)
	return {
		plaque = { x = math.floor((W - plateW) / 2), y = M.PLAQUE.y, w = plateW, h = M.PLAQUE.h },
		tabs = { x = M.SIDE, y = M.TABS.y, w = W - 2 * M.SIDE, h = M.TABS.h },
		area = { x = M.SIDE, y = M.AREA_TOP, w = W - 2 * M.SIDE, h = math.max(60, H - M.AREA_TOP - M.FOOTER) },
		close = { x = math.floor(W / 2 - 55), y = H - 40, w = 110, h = 30 },
	}
end

function M.rects(w, h)
	return Grid.rects(M.SECTIONS, w, h, 2) -- always two by two: four big objects fill the room best
end

M.plateText = Grid.plateText
M.plateTextSize = Grid.plateTextSize
M.inside = Grid.inside
M.intersects = Grid.intersects

return M
