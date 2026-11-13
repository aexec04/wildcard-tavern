--[[
	Shared/Engine/PatronRowLayout.lua
	Pure layout (tested) for the Patron Row: big Patron cards standing on the table above the hand.

	  PatronRowLayout.compute(rootW, rootH, hand, count, opts) -> layout | nil
	    rootW, rootH  size of the play area in px
	    hand          { x, y, w, h } the live hand frame (the row is centred over it and ends above the cards)
	    count         cards to draw (owned Patrons plus free seats), 0 gives nil
	    opts.topLimit lowest y the row may start at (the dock icons end there), default 92

	  layout = { cards = { {x, y, w, h} per card, left to right }, cardW, cardH, plaqueH, step, overlap (bool),
	             rect = {x, y, w, h} bounding box of cards and plaques }

	Card size is 96 x 132 at 1506 px wide and scales with the screen (never under 72 x 100 unless the free height
	forces it). Up to five cards sit side by side with a 10 px gap; when more do not fit they overlap evenly, each
	card keeping at least 60 percent of its width visible. The row ends 8 px above the top of the hand cards, so it
	never covers the hand, and the plaque (name, 15 px text) hangs under each card inside the row's box.
]]

local M = {}

M.BASE_W, M.BASE_H, M.BASE_SCREEN = 96, 132, 1506
M.MIN_W, M.MIN_H = 72, 100
M.GAP = 10
M.PLAQUE_H = 22
M.MIN_VISIBLE = 0.6
M.TOP_LIMIT = 92
M.HAND_TOP_PAD = 19 -- cards in a 200 px hand frame stand at most 165 px tall with 16 px under them
M.AIR = 8 -- clear space between the plaques and the hand cards

local function floor(n) return math.floor(n + 0.5) end

function M.scale(rootW)
	return math.max(0.75, math.min(1.3, rootW / M.BASE_SCREEN))
end

function M.compute(rootW, rootH, hand, count, opts)
	if not count or count <= 0 or not hand then return nil end
	local topLimit = opts and opts.topLimit or M.TOP_LIMIT
	local k = M.scale(rootW)
	local handTop = hand.y + (hand.h >= 200 and M.HAND_TOP_PAD or 0)
	local bottom = handTop - M.AIR
	local availH = bottom - topLimit - M.PLAQUE_H
	local cardH = math.min(M.BASE_H * k, availH)
	if cardH < M.MIN_H and availH >= M.MIN_H then cardH = M.MIN_H end
	if cardH < 24 then return nil end -- no room at all: the row hides rather than covering something
	local cardW = cardH * M.BASE_W / M.BASE_H
	-- width: centred over the hand, which never reaches the left board or the draw pile
	local availW = math.min(hand.w, rootW)
	local gap = M.GAP
	local step = cardW + gap
	local overlap = false
	if count * cardW + (count - 1) * gap > availW and count > 1 then
		overlap = true
		step = (availW - cardW) / (count - 1)
		local minStep = cardW * M.MIN_VISIBLE
		if step < minStep then
			-- too many for the width: shrink the cards so 60 percent of each still shows
			step = minStep
			cardW = availW / (1 + M.MIN_VISIBLE * (count - 1))
			cardH = cardW * M.BASE_H / M.BASE_W
			step = cardW * M.MIN_VISIBLE
		end
	end
	local totalW = cardW + step * (count - 1)
	local x0 = hand.x + (hand.w - totalW) / 2
	x0 = math.max(0, math.min(x0, rootW - totalW))
	local y = bottom - M.PLAQUE_H - cardH
	local out = { cards = {}, cardW = floor(cardW), cardH = floor(cardH), plaqueH = M.PLAQUE_H, step = step, overlap = overlap }
	for i = 1, count do
		out.cards[i] = { x = floor(x0 + (i - 1) * step), y = floor(y), w = floor(cardW), h = floor(cardH) }
	end
	local last = out.cards[count]
	out.rect = { x = out.cards[1].x, y = floor(y), w = last.x + last.w - out.cards[1].x, h = floor(cardH) + M.PLAQUE_H }
	return out
end

-- The Patron Nook: a carved ledge against the far rim that the cards stand in.
--   PatronRowLayout.nook(lay, rootW, hand, opts) -> { back, ledge, trim, glow = rects {x,y,w,h},
--     rivets = { {x,y}, {x,y} } (size RIVET), alcoves = { rect per card } (empty when the cards overlap) }
-- The back panel pads the row by 12 px at the sides and 10 above, but never above the dock limit, never outside
-- the hand frame's span (so the board stays clear) and ends 4 px under the plaques, above the hand cards.
M.NOOK_PAD_X, M.NOOK_PAD_TOP, M.NOOK_PAD_BOTTOM = 12, 10, 4
M.LEDGE_OVERLAP = 4 -- cards stand this far down over the ledge front
M.RIVET = 8
M.GLOW_H = 18

function M.nook(lay, rootW, hand, opts)
	if not lay or not lay.rect then return nil end
	local topLimit = opts and opts.topLimit or M.TOP_LIMIT
	local r = lay.rect
	local spanL = math.max(0, math.min(r.x, hand.x))
	local spanR = math.min(rootW, math.max(r.x + r.w, hand.x + hand.w))
	local x0 = math.max(r.x - M.NOOK_PAD_X, spanL)
	local x1 = math.min(r.x + r.w + M.NOOK_PAD_X, spanR)
	local y0 = math.max(r.y - M.NOOK_PAD_TOP, topLimit)
	local y1 = r.y + r.h + M.NOOK_PAD_BOTTOM
	local back = { x = floor(x0), y = floor(y0), w = floor(x1 - x0), h = floor(y1 - y0) }
	local ledgeY = floor(r.y + lay.cardH - M.LEDGE_OVERLAP)
	local ledge = { x = back.x, y = ledgeY, w = back.w, h = back.y + back.h - ledgeY }
	local trim = { x = back.x, y = ledgeY, w = back.w, h = 2 }
	local ry = ledge.y + ledge.h - M.RIVET - 4
	local rivets = { { x = back.x + 4, y = ry }, { x = back.x + back.w - M.RIVET - 4, y = ry } }
	local alcoves = {}
	if not lay.overlap then
		for i, c in ipairs(lay.cards) do
			alcoves[i] = { x = c.x - 4, y = c.y - 4, w = c.w + 8, h = c.h + 4 }
		end
	end
	local glow = { x = back.x, y = back.y, w = back.w, h = math.min(M.GLOW_H, back.h) }
	return { back = back, ledge = ledge, trim = trim, rivets = rivets, alcoves = alcoves, glow = glow }
end

-- The painted nook strip (`play_nook_strip_b`, trimmed to 1508 x 480), drawn whole at its own aspect (never stretched).
-- Its five arches are not equal, so the measured centres, opening widths and floor line (picture pixels, measured from
-- art-wip/play_scene/play_nook_strip_b.png) place the cards: each card stands on the arch floor, centred in its arch.
M.STRIP_W, M.STRIP_H = 1508, 480
M.ARCH_CX = { 192, 477, 755, 1035, 1316 }
M.ARCH_W = { 195, 225, 236, 230, 197 }
M.ARCH_FLOOR = 375
M.ARCH_SEATS = { { 3 }, { 2, 4 }, { 2, 3, 4 }, { 1, 2, 4, 5 }, { 1, 2, 3, 4, 5 } } -- arches used for 1 to 5 cards
M.TUCK = 10 -- the strip's bottom edge slips this far under the top of the hand frame

--   PatronRowLayout.painted(rootW, rootH, hand, count, opts) -> layout | nil (same shape as compute, plus
--     strip = {x,y,w,h}, scale). 1 to 5 cards sit one per arch; 6 to 8 overlap evenly from the first arch centre to the last.
function M.painted(rootW, rootH, hand, count, opts)
	if not count or count <= 0 or not hand then return nil end
	local topLimit = opts and opts.topLimit or M.TOP_LIMIT
	local handTop = hand.y + (hand.h >= 200 and M.HAND_TOP_PAD or 0)
	local stripBottom = handTop - M.AIR + M.TUCK
	local availW = math.min(hand.w, rootW)
	local s = math.min(availW / M.STRIP_W, (stripBottom - topLimit) / M.STRIP_H)
	if s * M.ARCH_W[1] < 60 then return nil end
	local sw, sh = floor(M.STRIP_W * s), floor(M.STRIP_H * s)
	local sx = floor(hand.x + (hand.w - sw) / 2)
	sx = math.max(0, math.min(sx, rootW - sw))
	local sy = floor(stripBottom - sh)
	local floorY = sy + M.ARCH_FLOOR * s
	local cardW = math.min(M.BASE_W * M.scale(rootW), M.ARCH_W[1] * s * 0.92)
	local cardH = cardW * M.BASE_H / M.BASE_W
	local maxH = floorY - topLimit
	if cardH > maxH then cardH = maxH; cardW = cardH * M.BASE_W / M.BASE_H end
	if cardH < 24 then return nil end
	local centers = {}
	local overlap = count > 5
	if not overlap then
		for i, a in ipairs(M.ARCH_SEATS[count]) do centers[i] = sx + M.ARCH_CX[a] * s end
	else
		local c0, c1 = sx + M.ARCH_CX[1] * s, sx + M.ARCH_CX[5] * s
		for i = 1, count do centers[i] = c0 + (c1 - c0) * (i - 1) / (count - 1) end
		local step = (c1 - c0) / (count - 1)
		if step < cardW * M.MIN_VISIBLE then
			cardW = step / M.MIN_VISIBLE
			cardH = cardW * M.BASE_H / M.BASE_W
		end
	end
	local y = floor(floorY - cardH + 4) -- cards stand 4 px down over the arch floor
	local out = { cards = {}, cardH = floor(cardH), cardW = floor(cardW), plaqueH = M.PLAQUE_H, overlap = overlap,
		strip = { x = sx, y = sy, w = sw, h = sh }, scale = s }
	for i = 1, count do
		out.cards[i] = { x = floor(centers[i] - cardW / 2), y = y, w = floor(cardW), h = floor(cardH) }
	end
	out.step = count > 1 and (centers[count] - centers[1]) / (count - 1) or 0
	local first, last = out.cards[1], out.cards[count]
	out.rect = { x = first.x, y = y, w = last.x + last.w - first.x, h = floor(cardH) + M.PLAQUE_H }
	return out
end

return M
