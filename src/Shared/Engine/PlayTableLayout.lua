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

-- Painted fronts of Card Sets with their own table (the art already carries the colour, so no felt tint goes on top). Each picture is
-- 1536x1024 like the default, but its felt, rail groove, deck recess and wooden front sit elsewhere; measured by eye from the PNGs with
-- art-wip/play_scene/table_set_crop.py (grid every 50 px). `strip` is where the Sort / Play / Discard plates stand (picture y and height).
M.SETS = {
	festival_night = { art = "play_table_front_festival_a",
		felt = { x = 30, y = 505, w = 1470, h = 250 }, rail = { x = 300, y = 790, w = 800, h = 50 }, deck = { x = 1295, y = 770, w = 185, h = 95 } },
	winter_evening = { art = "play_table_front_frosted_a",
		felt = { x = 30, y = 618, w = 1470, h = 205 }, rail = { x = 385, y = 858, w = 550, h = 38 }, deck = { x = 1280, y = 800, w = 175, h = 72 },
		strip = { y = 915, h = 100 } },
}

-- the painted front's art key for a Card Set id, nil for a set without its own table (the default front plus tint)
function M.artKeyOf(setId)
	local s = setId and M.SETS[setId]
	return s and s.art or nil
end

-- Measured on play_plates_b.png (alpha above 128; the bar above each face is inside the box).
M.PLATE_BOXES = {
	sort = { x = 28, y = 369, w = 356, h = 289 },
	play = { x = 437, y = 364, w = 533, h = 294 },
	discard = { x = 997, y = 364, w = 512, h = 294 },
}
M.PLATES_IMG_W, M.PLATES_IMG_H = 1536, 1024
-- The writing face inside a plate, as fractions of the plate box (below the top bar, inside the corner studs); read by eye from
-- play_plates_b.png: the bar and its posts end at about 0.30, the face is the dark wood from 0.34 to 0.82.
M.FACE = { x = 0.12, y = 0.34, w = 0.76, h = 0.48 }

-- Inside the deck recess (rw x rh px, widget-local): a portrait card back at 85 percent of the height (5:7) in the left part and the
-- count board filling the right part, text 20 px, so the board is at least 28 px tall and 56 px wide.
M.CARD_ASPECT = 5 / 7
function M.deckRects(rw, rh)
	local pad = math.max(4, math.floor(rh * 0.06 + 0.5))
	local ch = math.floor(rh * 0.85 + 0.5)
	local cw = math.floor(ch * M.CARD_ASPECT + 0.5)
	local card = { x = pad + 2, y = math.floor((rh - ch) / 2 + 0.5), w = cw, h = ch }
	local cx = card.x + cw + pad
	local bh = math.max(28, math.min(48, math.floor(rh * 0.5 + 0.5)))
	local count = { x = cx, y = math.floor((rh - bh) / 2 + 0.5), w = math.max(56, rw - cx - pad - 2), h = bh }
	return { card = card, count = count }
end

function M.usable(areaW)
	return areaW >= M.MIN_W
end

local function scaleRect(r, s, ox, oy)
	return { x = math.floor(ox + r.x * s + 0.5), y = math.floor(oy + r.y * s + 0.5), w = math.floor(r.w * s + 0.5), h = math.floor(r.h * s + 0.5) }
end

-- Plates sit under the rail on the wooden front of the table (picture y 860 to 1010), scaled to fit the strip.
local PLATE_STRIP = { y = 862, h = 150 }

-- setId (optional): a Card Set with its own painted front (M.SETS) uses that picture's measured rects; anything else the default's.
function M.map(areaW, areaH, setId)
	local set = setId and M.SETS[setId] or nil
	local s = areaW / M.IMG_W
	local imgH = math.floor(M.IMG_H * s + 0.5)
	local oy = areaH - imgH
	local out = { scale = s, image = { x = 0, y = oy, w = areaW, h = imgH }, set = set and setId or nil }
	out.felt = scaleRect(set and set.felt or M.FELT, s, 0, oy)
	out.rail = scaleRect(set and set.rail or M.RAIL, s, 0, oy)
	out.deck = scaleRect(set and set.deck or M.DECK, s, 0, oy)
	local PLATE_STRIP = set and set.strip or PLATE_STRIP
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

-- Where the live hand row and the Actions row go on the painted table. The cards (144 px tall in a 176 px frame, 16 px of
-- padding under them) stand with their bottom edge on the middle of the rail groove; the Actions row is centred in the plate strip.
-- Returns nil when the painted layout cannot hold them (the old layout stays). left = sidebar edge, rightReserve = the draw pile.
M.HAND_H, M.ACTION_H, M.CARD_PAD = 176, 54, 16

function M.placement(areaW, areaH, left, rightReserve, setId)
	if not M.usable(areaW) then return nil end
	local m = M.map(areaW, areaH, setId)
	local right = math.min(areaW - rightReserve, m.deck.x - 8)
	local w = math.min(math.floor(m.rail.w * 1.3), right - left)
	if w < 400 then return nil end
	local x = math.max(left, math.min(m.rail.x + m.rail.w / 2 - w / 2, right - w))
	x = math.floor(x + 0.5)
	local handY = math.floor(m.rail.y + m.rail.h / 2 + M.CARD_PAD - M.HAND_H + 0.5)
	-- the Actions row IS the three painted plates in a row (Sort, Play Hand, Discard), as tall as the tallest
	local pl = m.plates
	local actY = pl.play.y
	local actH = math.max(pl.sort.h, pl.play.h, pl.discard.h)
	local actX = pl.sort.x
	local actW = pl.discard.x + pl.discard.w - pl.sort.x
	if handY < 0 or actY + actH > areaH or actY < handY + M.HAND_H - M.CARD_PAD then return nil end
	local dx = math.max(0, left - actX) -- a narrow window slides the row clear of the sidebar
	actX = actX + dx
	if actX + actW > areaW then return nil end
	return { map = m, hand = { x = x, y = handY, w = w, h = M.HAND_H }, actions = { x = actX, y = actY, w = actW, h = actH }, gap = math.floor(24 * m.scale + 0.5), dx = dx }
end

return M
