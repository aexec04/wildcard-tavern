--[[
	Engine/PlayedLane.lua
	Where a played hand lands: its own lane between the Patron nook and the hand, never over either. Pure numbers, all in
	root-relative pixels. The cards shrink to at most 70 percent (at least 50) so the lane fits; the score readout hangs
	above the lane when there is room for it.

	PlayedLane.rect(o) -> { scale, rowY, cardW, cardH, readoutY, fits, side, sideY }
	  o.nookBottom  lowest edge of the Patron row (nil when none shows)
	  o.handTop     top edge of the hand
	  o.cardW, o.cardH  the hand card's size before shrinking
	  o.popupH      height of the score readout
	  o.maxScale    optional cap above MAX_SCALE (the v2 table asks for a 90 px wide card, PlayedLane.goalScale)
]]

local PlayedLane = {}

PlayedLane.MAX_SCALE = 0.7
PlayedLane.MIN_SCALE = 0.5
PlayedLane.GAP = 10

-- the scale that gives a played card goalW pixels of width from a hand card baseW wide (never under MAX_SCALE, never over 1)
function PlayedLane.goalScale(baseW, goalW)
	return math.max(PlayedLane.MAX_SCALE, math.min(1, goalW / math.max(1, baseW)))
end

function PlayedLane.rect(o)
	local gap = o.gap or PlayedLane.GAP
	local minScale = o.minScale or PlayedLane.MIN_SCALE
	local top = math.max(20, (o.nookBottom or 0) + gap)
	local bottom = o.handTop - gap
	local avail = bottom - top
	local reserve = o.popupH > 0 and o.popupH + 8 or 0 -- no readout above the cards (the v2 table), nothing to reserve
	-- keep the readout above the lane only while the cards can still stay at a readable size; otherwise it moves to the felt beside the cards
	local side = false
	if avail - reserve < o.cardH * minScale then reserve = 0; side = true end
	local scale = math.min(o.maxScale or PlayedLane.MAX_SCALE, (avail - reserve) / o.cardH)
	scale = math.max(minScale, scale)
	local cardH = o.cardH * scale
	local rowY = bottom - cardH
	local fits = rowY >= top + reserve - 0.5
	return {
		scale = scale,
		rowY = rowY,
		cardW = o.cardW * scale,
		cardH = cardH,
		readoutY = reserve > 0 and math.max(4, rowY - 8 - o.popupH) or math.max(4, top - 4),
		fits = fits,
		side = side, -- true: the readout stands beside the played cards (right, else left), vertically centred on the row
		sideY = rowY + (cardH - o.popupH) / 2,
	}
end

return PlayedLane
