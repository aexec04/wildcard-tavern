--[[
	Shared/Engine/PlayTableLayout.lua
	Pure geometry for the painted play table (art key play_table_front_b, 1536x1024, transparent above the table) and the
	three painted plates (play_plates_b, 1536x1024). Rects are measured from the PNGs (art-wip/play_scene/debug_table.png) and kept as
	pixels of the picture; `map` turns them into screen rects for a play area. The table is bottom anchored, full width, never stretched.

	PlayTableLayout.map(areaW, areaH) -> { image, felt, rail, deck, plates = { sort, play, discard } }
	    image = the table picture's screen rect (cover crop: width = areaW, height by aspect, bottom on the area's bottom)
	    felt  = where played cards land, rail = hand groove, deck = the recess, plates = Sort/Play/Discard rects under the rail
	PlayTableLayout.usable(areaW)    false under MIN_W: use the old layout
	PlayTableLayout.PLATE_BOXES      the three plate boxes inside play_plates_b (ImageRectOffset / ImageRectSize)
]]

local M = {}

M.IMG_W, M.IMG_H = 1536, 1024
M.MIN_W = 900 -- below this the old flat layout stays

-- Measured on play_table_front_b.png (pixels of the 1536x1024 picture).
M.FELT = { x = 30, y = 490, w = 1470, h = 290 }
M.RAIL = { x = 340, y = 800, w = 850, h = 45 }
M.DECK = { x = 1275, y = 700, w = 200, h = 95 }

-- Measured on play_plates_b.png (alpha above 128; the bar above each face is inside the box).
M.PLATE_BOXES = {
	sort = { x = 28, y = 369, w = 356, h = 289 },
	play = { x = 437, y = 364, w = 533, h = 294 },
	discard = { x = 997, y = 364, w = 512, h = 294 },
}
M.PLATES_IMG_W, M.PLATES_IMG_H = 1536, 1024

function M.usable(areaW)
	return areaW >= M.MIN_W
end

local function scaleRect(r, s, ox, oy)
	return { x = math.floor(ox + r.x * s + 0.5), y = math.floor(oy + r.y * s + 0.5), w = math.floor(r.w * s + 0.5), h = math.floor(r.h * s + 0.5) }
end

-- Plates sit under the rail on the wooden front of the table (picture y 860 to 1010), scaled to fit the strip.
local PLATE_STRIP = { y = 862, h = 150 }

function M.map(areaW, areaH)
	local s = areaW / M.IMG_W
	local imgH = math.floor(M.IMG_H * s + 0.5)
	local oy = areaH - imgH
	local out = { scale = s, image = { x = 0, y = oy, w = areaW, h = imgH } }
	out.felt = scaleRect(M.FELT, s, 0, oy)
	out.rail = scaleRect(M.RAIL, s, 0, oy)
	out.deck = scaleRect(M.DECK, s, 0, oy)
	-- plate rects: scale so the tallest plate fills the strip height, keep the three boxes' relative spacing centred under the rail.
	local ps = (PLATE_STRIP.h * s) / M.PLATE_BOXES.play.h
	local gap = 24 * s
	local sortW, playW, disW = M.PLATE_BOXES.sort.w * ps, M.PLATE_BOXES.play.w * ps, M.PLATE_BOXES.discard.w * ps
	local total = sortW + playW + disW + 2 * gap
	local railCx = out.rail.x + out.rail.w / 2
	local x = railCx - total / 2
	local y0 = oy + PLATE_STRIP.y * s
	local function plate(box, w)
		local h = box.h * ps
		local r = { x = math.floor(x + 0.5), y = math.floor(y0 + (PLATE_STRIP.h * s - h) / 2 + 0.5), w = math.floor(w + 0.5), h = math.floor(h + 0.5) }
		x = x + w + gap
		return r
	end
	out.plates = { sort = plate(M.PLATE_BOXES.sort, sortW), play = plate(M.PLATE_BOXES.play, playW), discard = plate(M.PLATE_BOXES.discard, disW) }
	return out
end

return M
