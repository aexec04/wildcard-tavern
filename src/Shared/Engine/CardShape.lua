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
CardShape.PRICE_STRIP = 36 -- a priced card ends in a strip that holds the 28 px price pill with 4 px margins, so nothing hangs outside the card
CardShape.PRICE_GAP = 4
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

-- Counter layout: the largest scale (never above scaleFor, never below FIT_MIN) at which the strip, two
-- section labels, the Patron/Voucher row and the Pack row all fit availH, and the widest row fits availW.
-- 252 + 460 * s is the stacked height at scale s (strip 44 + labels 48 + 4 gaps of 8 = 124; rows add 64 each
-- on top of the art heights 250 and 210).
CardShape.FIT_MIN = 0.6
CardShape.FIT_FIXED_H = 308 -- 252 + 2 rows x 28 px price strip
CardShape.FIT_PER_SCALE_H = 460
function CardShape.fitScale(availW, availH, vpX, vpY, widestRow)
	local s = CardShape.scaleFor(vpX, vpY)
	if availH and availH > 0 then
		s = math.min(s, (availH - CardShape.FIT_FIXED_H) / CardShape.FIT_PER_SCALE_H)
	end
	local n = math.max(widestRow or 1, 1)
	if availW and availW > 0 then
		s = math.min(s, (availW - 28 - (n - 1) * 16) / (n * BASE.patron.w))
	end
	return math.max(CardShape.FIT_MIN, s)
end

-- My Patrons seats: the largest scale (never above scaleFor, never below 0.4) at which n owned cards fit availW in one row.
CardShape.OWNED_GAP = 10
function CardShape.fitOwned(availW, n, vpX, vpY)
	local s = CardShape.scaleFor(vpX, vpY)
	n = math.max(n or 1, 1)
	if availW and availW > 0 then
		-- seatW = floor((viewportW - 2 * 14 padding - (n - 1) * gap) / n); the scale is that width over the base width
		s = math.min(s, (availW - 28 - (n - 1) * CardShape.OWNED_GAP) / (n * BASE.owned.w))
	end
	return math.max(0.4, s)
end

-- Pack pick screen: one centered row when it fits, else 2 or 3 wrapped rows, picking the layout with the
-- biggest cards. Reserves 78px for the title/hint and 64px for the Confirm / Skip row. Returns scale, rows.
CardShape.PICK_TOP, CardShape.PICK_BOTTOM = 78, 64
function CardShape.pickLayout(availW, availH, count, vpX, vpY)
	local s0 = CardShape.scaleFor(vpX, vpY)
	local n = math.max(count or 1, 1)
	local bestS, bestRows = 0, 1
	for rows = 1, math.min(3, n) do
		local perRow = math.ceil(n / rows)
		local sW = (availW - 28 - (perRow - 1) * 16) / (perRow * BASE.patron.w)
		local sH = (availH - CardShape.PICK_TOP - CardShape.PICK_BOTTOM - (rows - 1) * 8 - rows * 64) / (rows * BASE.patron.artH)
		local s = math.min(s0, sW, sH)
		if s > bestS + 0.001 then
			bestS, bestRows = s, rows
		end
	end
	return math.max(CardShape.FIT_MIN, bestS), bestRows
end

function CardShape.shape(kind, scale, noAction)
	local b = BASE[kind] or BASE.patron
	scale = scale or 1
	local w = math.floor(b.w * scale)
	local artH = math.floor(b.artH * scale)
	local artTop = 6
	local bannerTop = artTop + artH - 18
	local tail = (kind == "owned") and 8 or CardShape.PRICE_STRIP
	return {
		w = w, artH = artH, artTop = artTop, bannerTop = bannerTop,
		h = bannerTop + CardShape.BANNER_H + tail,
		-- the Buy drawer sits over the bottom of the art, just above the ribbon
		drawerTop = bannerTop - CardShape.BUTTON_H - 8,
	}
end

function CardShape.fitsRow(count, rowW, shape, gap, pad)
	return count * shape.w + math.max(count - 1, 0) * gap + 2 * pad <= rowW
end

return CardShape
