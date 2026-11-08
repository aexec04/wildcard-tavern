--[[
	Shared/Engine/CardFit.lua
	Pure sizing for the three Round Select cards (tested). The screen is full width, so the cards may
	grow above 1x on big viewports, and shrink to fit phone widths.

	  scale(vpY, rowW, rowH, cardH, cardW, maxFit) -> number in [0.6, maxFit]
]]

local CardFit = {}

CardFit.GAP = 24
CardFit.COUNT = 3

function CardFit.scale(vpY, rowW, rowH, cardH, cardW, maxFit)
	local h = math.min(cardH * maxFit, 0.80 * vpY)
	-- ~5% headroom so a hovered (1.04x) card never clips.
	if rowH > 0 then h = math.min(h, (rowH - 8) / 1.05) end
	if rowW > 0 then
		local w = (rowW - CardFit.GAP * (CardFit.COUNT - 1)) / CardFit.COUNT / 1.05
		h = math.min(h, w / cardW * cardH)
	end
	return math.max(0.6, math.min(maxFit, h / cardH))
end

return CardFit
