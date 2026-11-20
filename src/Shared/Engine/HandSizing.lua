--[[
	Engine/HandSizing.lua
	Pure size math for the hand row. On roomy windows (width 1200 or more) cards grow from 114 to 124 wide (180 tall) so the
	felt above the hand is used; narrower windows keep the old size. The hand frame is taller by the same amount
	(cards plus 2 x 16 padding), its bottom stays on the seat line so the buttons keep their clearance.

	HandSizing.maxCardWidth(areaW) -> widest a hand card may be
	HandSizing.frameHeight(areaW)  -> hand frame height holding that card plus padding
	HandSizing.cardSize(areaW, frameW, frameH, count) -> width, height the hand will actually use
]]

local M = {}

M.ASPECT = 1.45 -- height / width, same as CardFace
M.PAD = 16
M.GAP = 6 -- equals the hub hand UIListLayout padding
M.MIN_WIDTH = 48
M.BASE_MAX = 114
M.BIG_MAX = 124
M.BIG_FROM = 1200
M.BASE_FRAME_H = 200

M.WIDE_SHARE = 0.084 -- reference cards are 8.4 percent of the width (140 of 1672); the byWidth and byHeight limits in cardSize still keep 8 or more cards inside the fan
M.WIDE_CAP = 160
M.OVERLAP = 0.18 -- on roomy windows neighbouring cards overlap by this share of a card width up to 8 cards (the reference shows 8 cards with a small overlap, every corner readable)
M.OVERLAP_MAX_SHARE = 0.22 -- the 8 card overlap stays under this share (test)
M.OVERLAP_PER_CARD = 0.045 -- each card past 8 adds this much overlap, so big hands compress gradually
M.OVERLAP_CAP = 0.5

-- overlap share for a hand of `count` cards
function M.overlapFor(count)
	local extra = math.max(0, (count or 8) - 8)
	return math.min(M.OVERLAP_CAP, M.OVERLAP + M.OVERLAP_PER_CARD * extra)
end

-- width of the fan (first card left edge to last card right edge) for `count` cards of width `cardW`
function M.fanSpan(areaW, cardW, count)
	count = count or 1
	if count <= 1 then return cardW end
	return cardW + (count - 1) * (cardW + M.gap(areaW, cardW, count))
end

-- gap between neighbouring cards: the old 6 px, or a negative overlap on roomy windows
function M.gap(areaW, cardW, count)
	if (areaW or 0) >= M.BIG_FROM then return -math.floor((cardW or 0) * M.overlapFor(count)) end
	return M.GAP
end

function M.maxCardWidth(areaW)
	if (areaW or 0) >= M.BIG_FROM then return math.max(M.BIG_MAX, math.min(M.WIDE_CAP, math.floor(areaW * M.WIDE_SHARE))) end
	return M.BASE_MAX
end

-- The frame stays 200 tall (the boss bubble and the lane keep-out rects read it): a 180 tall card fits above the 16 px of
-- bottom padding, with 4 px to spare, so only the cards' tops rise.
function M.frameHeight(_areaW)
	return M.BASE_FRAME_H
end

-- Frame width that holds `count` cards of the big size (cards, gaps, 2 x padding); 0 on windows that keep the base size.
function M.wantWidth(areaW, count)
	if (areaW or 0) < M.BIG_FROM then return 0 end
	return M.maxCardWidth(areaW) * count + M.GAP * (count - 1) + 2 * M.PAD
end

-- The live hand frame: the layout rect, grown upward (never down, so the pills and buttons keep their clearance) until the frame is tall
-- enough for cards at their wide target size. The frame is transparent, so the cards just rise into the open stage like the reference.
M.MAX_RISE = 70
function M.frameFor(areaW, rect, count)
	if (areaW or 0) < M.BIG_FROM or (count or 0) < 1 then return rect end
	local byWidth = math.floor((rect.w - 2 * M.PAD) / (count - M.overlapFor(count) * (count - 1)))
	local want = math.min(M.maxCardWidth(areaW), byWidth)
	local need = math.floor(want * M.ASPECT) + M.PAD
	local extra = math.max(0, math.min(M.MAX_RISE, need - rect.h))
	return { x = rect.x, y = rect.y - extra, w = rect.w, h = rect.h + extra }
end

function M.cardSize(areaW, frameW, frameH, count)
	local maxW = M.maxCardWidth(areaW)
	local width = maxW
	if frameW > 0 and count > 0 then
		local byWidth
		if (areaW or 0) >= M.BIG_FROM then
			byWidth = math.floor((frameW - 2 * M.PAD) / (count - M.overlapFor(count) * (count - 1)))
		else
			byWidth = math.floor((frameW - 2 * M.PAD - M.GAP * (count - 1)) / count)
		end
		local byHeight = math.floor((frameH - M.PAD) / M.ASPECT) -- cards stand on the bottom padding only
		width = math.max(M.MIN_WIDTH, math.min(maxW, byWidth, byHeight))
	end
	return width, math.floor(width * M.ASPECT)
end

return M
