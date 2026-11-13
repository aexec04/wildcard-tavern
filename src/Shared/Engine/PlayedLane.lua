--[[
	Engine/PlayedLane.lua
	Where a played hand lands: its own lane between the Patron nook and the hand, never over either. Pure numbers, all in
	root-relative pixels. The cards shrink to at most 75 percent (at least 50) so the lane fits; the score readout hangs
	above the lane when there is room for it.

	PlayedLane.rect(o) -> { scale, rowY, cardW, cardH, readoutY, fits }
	  o.nookBottom  lowest edge of the Patron row (nil when none shows)
	  o.handTop     top edge of the hand
	  o.cardW, o.cardH  the hand card's size before shrinking
	  o.popupH      height of the score readout
]]

local PlayedLane = {}

PlayedLane.MAX_SCALE = 0.75
PlayedLane.MIN_SCALE = 0.5
PlayedLane.GAP = 10

function PlayedLane.rect(o)
	local gap = PlayedLane.GAP
	local top = math.max(20, (o.nookBottom or 0) + gap)
	local bottom = o.handTop - gap
	local avail = bottom - top
	local reserve = o.popupH + 8
	-- keep the readout above the lane only while the cards can still stay at a readable size
	if avail - reserve < o.cardH * PlayedLane.MIN_SCALE then reserve = 0 end
	local scale = math.min(PlayedLane.MAX_SCALE, (avail - reserve) / o.cardH)
	scale = math.max(PlayedLane.MIN_SCALE, scale)
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
	}
end

return PlayedLane
