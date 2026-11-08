--[[
	Shared/Engine/CardShape.lua
	Pure sizing for the art-first item cards (Shop "The Counter", My Patrons, My Recipes), tested.
	The cards are art, a name ribbon and a price coin; the rules text lives in the hover tooltip.

	scaleFor(vpX, vpY) -> number   size multiplier from the viewport: big painted cards on big screens,
	                               still readable at phone width (0.7 .. 1.35)
	shape(kind, scale, noAction) -> { w, artH, artTop, bannerTop, h }
	    kind = "patron" | "voucher" | "pack" | "owned". There is no text strip, so a card ends just under
	    its ribbon: h = bannerTop + BANNER_H + 8. The Buy button slides up over the bottom of the art, so it
	    adds no height.
	fitsRow(count, rowW, shape, gap, pad) -> bool   all cards fit one row without sideways scrolling
]]

local CardShape = {}

CardShape.BANNER_H = 40
CardShape.BUTTON_H = 36
CardShape.MIN_SCALE = 0.7
CardShape.MAX_SCALE = 1.35

local BASE = {
	patron = { w = 220, artH = 250 },
	voucher = { w = 220, artH = 250 },
	pack = { w = 220, artH = 210 },
	owned = { w = 176, artH = 176 },
}

function CardShape.scaleFor(vpX, vpY)
	local s = math.min((vpX or 1280) / 1400, (vpY or 720) / 800)
	return math.max(CardShape.MIN_SCALE, math.min(CardShape.MAX_SCALE, s))
end

function CardShape.shape(kind, scale, noAction)
	local b = BASE[kind] or BASE.patron
	scale = scale or 1
	local w = math.floor(b.w * scale)
	local artH = math.floor(b.artH * scale)
	local artTop = 6
	local bannerTop = artTop + artH - 18
	return {
		w = w, artH = artH, artTop = artTop, bannerTop = bannerTop,
		h = bannerTop + CardShape.BANNER_H + 8,
		-- the Buy drawer sits over the bottom of the art, just above the ribbon
		drawerTop = bannerTop - CardShape.BUTTON_H - 8,
	}
end

function CardShape.fitsRow(count, rowW, shape, gap, pad)
	return count * shape.w + math.max(count - 1, 0) * gap + 2 * pad <= rowW
end

return CardShape
