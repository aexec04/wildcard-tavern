--[[
	Shared/Engine/RoomGrid.lua
	Pure geometry for a "room with hotspots" (the Collection's gallery room, the Badges trophy room): the sections sit in a grid, each
	one an object with a carved name plate under it. Hotspots never overlap and always lie inside the room. Wording of the plates too.

	RoomGrid.rects(sections, w, h, cols) -> { spots = { [id] = { object, plate, hit } }, order, cols, rows }
	    sections = { { id, aspect } }: aspect = the object's width over its height. Rects are in the room's pixels.
	RoomGrid.plateText(label, found, total)  "Recipes 3/24"
	RoomGrid.plateTextSize(plateW)           16, or 14 on a narrow plate (never below 14)
	RoomGrid.inside(r, w, h) / RoomGrid.intersects(a, b)
]]

local M = {}

M.MARGIN = 10 -- between the room's edge and the outer objects
M.GAP = 10 -- between two cells
M.PLATE_H = 28
M.PLATE_GAP = 4 -- object bottom to plate top
M.PLATE_MIN_W = 150 -- "House Passes 12/12" at 16 px bold fits in 150
M.MIN_OBJECT_H = 8

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

function M.rects(sections, w, h, cols)
	local n = #sections
	local rows = math.ceil(n / cols)
	local cellW = math.floor((w - 2 * M.MARGIN - (cols - 1) * M.GAP) / cols)
	local cellH = math.floor((h - 2 * M.MARGIN - (rows - 1) * M.GAP) / rows)
	local usedW = cols * cellW + (cols - 1) * M.GAP
	local usedH = rows * cellH + (rows - 1) * M.GAP
	local x0, y0 = math.floor((w - usedW) / 2), math.floor((h - usedH) / 2) -- slack from the integer division is split evenly
	local spots, order = {}, {}
	for i, s in ipairs(sections) do
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
