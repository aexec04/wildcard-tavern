-- The Select and Skip plates at the foot of a Round Select card, as numbers. Both use a centred anchor (0.5, 1) so the hover grow
-- (UIScale, RoundSelectFX) spreads evenly and the plate centre stays put; an anchor at the left edge slid it to the right.
--   RoundSelectPlates.rect(cardW, which)          -> { x, y, w, h } at rest, card-relative top-left
--   RoundSelectPlates.centre(rect, anchorX, anchorY, scale) -> centre of the plate after a UIScale of `scale` (the anchor stays fixed)
local M = {}

M.HOVER_SCALE, M.MARGIN, M.SELECT_H, M.SKIP_H, M.GAP = 1.05, 10, 44, 40, 6
M.ANCHOR_X, M.ANCHOR_Y = 0.5, 1
M.CARD_H = 620

function M.rect(cardW, which)
	local w = cardW - 2 * M.MARGIN
	if which == "skip" then
		return { x = M.MARGIN, y = M.CARD_H - M.MARGIN - M.SKIP_H, w = w, h = M.SKIP_H }
	end
	local bottom = M.MARGIN + M.SKIP_H + M.GAP
	return { x = M.MARGIN, y = M.CARD_H - bottom - M.SELECT_H, w = w, h = M.SELECT_H }
end

function M.centre(rect, anchorX, anchorY, scale)
	local ax, ay = rect.x + anchorX * rect.w, rect.y + anchorY * rect.h -- the fixed anchor point
	local w, h = rect.w * scale, rect.h * scale
	return { x = ax - anchorX * w + w / 2, y = ay - anchorY * h + h / 2 }
end

-- While the card grows by `k` (hover) about `anchor` (card-local px, the card's own AnchorPoint times its size), a plate at `rect` moves
-- on screen by (centre - anchor) * (k - 1). The offset to ADD to the plate's Position (card-local px, before the grow) so its centre stays
-- under the pointer: (centre - anchor) * (1 / k - 1). With k = 1 it is zero.
--   RoundSelectPlates.holdOffset(rect, anchorXpx, anchorYpx, k) -> dx, dy
function M.holdOffset(rect, anchorX, anchorY, k)
	k = (tonumber(k) and k > 0) and k or 1
	local cx, cy = rect.x + rect.w / 2, rect.y + rect.h / 2
	local f = 1 / k - 1
	return (cx - anchorX) * f, (cy - anchorY) * f
end

return M
