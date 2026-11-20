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

function M.cardSize(areaW, frameW, frameH, count)
	local maxW = M.maxCardWidth(areaW)
	local width = maxW
	if frameW > 0 and count > 0 then
		local byWidth = math.floor((frameW - 2 * M.PAD - M.GAP * (count - 1)) / count)
		local byHeight = math.floor((frameH - M.PAD) / M.ASPECT) -- cards stand on the bottom padding only
		width = math.max(M.MIN_WIDTH, math.min(maxW, byWidth, byHeight))
	end
	return width, math.floor(width * M.ASPECT)
end

return M
