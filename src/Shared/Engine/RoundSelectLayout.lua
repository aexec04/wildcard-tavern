--[[
	Shared/Engine/RoundSelectLayout.lua
	The Night map (Round Select) layout as pure numbers, so a test can check every clickable rect at any screen size.
	Client/RoundSelect builds the live Instances from the same constants and the same CardFit scale.

	scale(w, h)                     -> number   the UIScale every card gets (Engine/CardFit, down to MIN_FIT on short screens)
	rects(w, h, hasSkip)            -> { scale, cards = { { panel, select, skip, target } x3 }, tips }   screen px
	tipSpot(w, h, card, tipW, tipH) -> x, y     where the Skip tooltip stands: never over Select, Skip or the Target plate
]]

local CardFit = require(script.Parent.CardFit)

local M = {}

M.CARD_W, M.CARD_H, M.MAX_FIT, M.MIN_FIT = 340, 620, 1.25, 0.4
M.ROW_TOP, M.ROW_SIDE, M.ROW_BOTTOM = 104, 20, 72 -- 72 bottom keeps the 48 px Daily strip (12 px margin, 8 px gap) clear of the cards
M.STRIP_RESERVE = 68 -- the band the tooltip also stays out of
M.SELECT_H, M.SKIP_H, M.TARGET_H, M.EDGE = 44, 44, 36, 10 -- SKIP_H is Engine/SkipPlate.HEIGHT
M.TIPS_W, M.TIPS_H, M.TIPS_RIGHT, M.TIPS_TOP = 150, 34, 20, 18
M.TIP_GAP = 8

-- COMPACT cards: windows shorter than COMPACT_BELOW px. The card is built shorter (no tall image area, so the title, Tag line, Target plate,
-- Select and Skip keep their real 44 px size) instead of shrinking the 620 px card under a UIScale, which made the buttons 17 to 36 px.
M.COMPACT_BELOW = 800
M.CW_C, M.CH_C, M.MAX_FIT_C = 210, 256, 1.5
M.CH_MAX_C = 440 -- the tallest a compact card grows
M.PHONE_BELOW = 600 -- under this the header shrinks to the title and the strip gap closes up
M.ROW_TOP_PHONE, M.ROW_BOTTOM_PHONE, M.TIPS_TOP_PHONE = 48, 12, 6

function M.isCompact(h) return h < M.COMPACT_BELOW end

-- { compact, cardW, cardH, rowTop, rowBottom, scale } for a screen of w x h.
function M.metrics(w, h)
	local rowW = w - 2 * M.ROW_SIDE
	if not M.isCompact(h) then
		local rowH = h - M.ROW_TOP - M.ROW_BOTTOM
		return { compact = false, cardW = M.CARD_W, cardH = M.CARD_H, rowTop = M.ROW_TOP, rowBottom = M.ROW_BOTTOM,
			scale = CardFit.scale(h, rowW, rowH, M.CARD_H, M.CARD_W, M.MAX_FIT, M.MIN_FIT) }
	end
	local phone = h < M.PHONE_BELOW
	local top, bottom = phone and M.ROW_TOP_PHONE or M.ROW_TOP, phone and M.ROW_BOTTOM_PHONE or M.ROW_BOTTOM
	local rowH = h - top - bottom
	local s = CardFit.scale(h, rowW, rowH, M.CH_C, M.CW_C, M.MAX_FIT_C, 0.5)
	-- the card grows taller (not wider) to fill the free row height, so the art keeps its room; the plates stay real size
	local tall = math.max(M.CH_C, math.min(M.CH_MAX_C, math.floor(rowH / s)))
	return { compact = true, cardW = M.CW_C, cardH = tall, rowTop = top, rowBottom = bottom, scale = s }
end

function M.scale(w, h)
	return M.metrics(w, h).scale
end

local function rect(x, y, w, h) return { x = x, y = y, w = w, h = h } end

function M.rects(w, h, hasSkip)
	local m = M.metrics(w, h)
	local s, rowTop = m.scale, m.rowTop
	local cw, ch, gap = m.cardW * s, m.cardH * s, CardFit.padding(s, m.cardW)
	local x0 = (w - (cw * CardFit.COUNT + gap * (CardFit.COUNT - 1))) / 2
	local out = { scale = s, cards = {} }
	for i = 1, CardFit.COUNT do
		local x, bottom = x0 + (i - 1) * (cw + gap), rowTop + ch
		local inner = cw - 2 * M.EDGE * s
		out.cards[i] = {
			panel = rect(x, rowTop, cw, ch),
			select = rect(x + M.EDGE * s, bottom - (M.EDGE + M.SKIP_H + 6 + M.SELECT_H) * s, inner, M.SELECT_H * s),
			skip = hasSkip and rect(x + M.EDGE * s, bottom - (M.EDGE + M.SKIP_H) * s, inner, M.SKIP_H * s) or nil,
			target = rect(x + M.EDGE * s, bottom - (M.EDGE + M.SKIP_H + 6 + M.SELECT_H + 8 + M.TARGET_H) * s, inner, M.TARGET_H * s),
		}
	end
	out.tips = rect(w - M.TIPS_RIGHT - M.TIPS_W, (m.compact and h < M.PHONE_BELOW) and M.TIPS_TOP_PHONE or M.TIPS_TOP, M.TIPS_W, M.TIPS_H)
	return out
end

-- Preferred: straight under the Skip plate when it fits on screen. Otherwise above the Target plate (over the card text, which is
-- not clickable). Never above Skip, because that is where Select sits. x is clamped inside the screen.
function M.tipSpot(w, h, card, tipW, tipH)
	local skip = card.skip or card.select
	local x = math.max(4, math.min(w - tipW - 4, skip.x + (skip.w - tipW) / 2))
	local below = skip.y + skip.h + M.TIP_GAP
	if below + tipH <= h - 4 - M.STRIP_RESERVE then return x, below end
	return x, math.max(4, card.target.y - M.TIP_GAP - tipH)
end

return M
