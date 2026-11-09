--[[
	Shared/Engine/CardFit.lua
	Pure sizing for the three Round Select cards (tested). The screen is full width, so the cards may
	grow above 1x on big viewports, and shrink to fit phone widths.

	  scale(vpY, rowW, rowH, cardH, cardW, maxFit) -> number in [0.6, maxFit]
]]

local CardFit = {}

CardFit.GAP = 24
CardFit.COUNT = 3
CardFit.MIN_GAP = 28 -- on-screen pixels between neighbouring cards, whatever the scale

-- UIListLayout.Padding for the card row. Measured in Studio: the layout already spaces by the SCALED
-- card size (a UIScale child counts at its scaled width), so Padding is the on-screen gap itself.
-- If a layout ever spaced by the unscaled size, pass scaledLayout=false and the shrink is added back.
function CardFit.padding(scale, cardW, scaledLayout)
	local gap = math.max(CardFit.MIN_GAP, CardFit.GAP * scale)
	if scaledLayout == false then gap = gap + cardW * (1 - scale) end
	return gap
end

-- Extra Padding needed so the measured gap (next.left - (prev.left + prev.width)) reaches MIN_GAP.
function CardFit.shortfall(measuredGap)
	return math.max(0, CardFit.MIN_GAP - measuredGap)
end

function CardFit.scale(vpY, rowW, rowH, cardH, cardW, maxFit)
	local h = math.min(cardH * maxFit, 0.80 * vpY)
	-- ~5% headroom so a hovered (1.04x) card never clips.
	if rowH > 0 then h = math.min(h, (rowH - 8) / 1.05) end
	if rowW > 0 then
		local w = (rowW - CardFit.MIN_GAP * (CardFit.COUNT - 1)) / CardFit.COUNT / 1.05
		h = math.min(h, w / cardW * cardH)
	end
	return math.max(0.6, math.min(maxFit, h / cardH))
end

return CardFit
