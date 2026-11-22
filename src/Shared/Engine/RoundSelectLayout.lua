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
M.ROW_TOP, M.ROW_SIDE, M.ROW_BOTTOM = 104, 20, 16
M.SELECT_H, M.SKIP_H, M.TARGET_H, M.EDGE = 44, 44, 36, 10 -- SKIP_H is Engine/SkipPlate.HEIGHT
M.TIPS_W, M.TIPS_H, M.TIPS_RIGHT, M.TIPS_TOP = 150, 34, 20, 18
M.TIP_GAP = 8

function M.scale(w, h)
	local rowW, rowH = w - 2 * M.ROW_SIDE, h - M.ROW_TOP - M.ROW_BOTTOM
	return CardFit.scale(h, rowW, rowH, M.CARD_H, M.CARD_W, M.MAX_FIT, M.MIN_FIT)
end

local function rect(x, y, w, h) return { x = x, y = y, w = w, h = h } end

function M.rects(w, h, hasSkip)
	local s = M.scale(w, h)
	local cw, ch, gap = M.CARD_W * s, M.CARD_H * s, CardFit.padding(s, M.CARD_W)
	local x0 = (w - (cw * CardFit.COUNT + gap * (CardFit.COUNT - 1))) / 2
	local out = { scale = s, cards = {} }
	for i = 1, CardFit.COUNT do
		local x, bottom = x0 + (i - 1) * (cw + gap), M.ROW_TOP + ch
		local inner = cw - 2 * M.EDGE * s
		out.cards[i] = {
			panel = rect(x, M.ROW_TOP, cw, ch),
			select = rect(x + M.EDGE * s, bottom - (M.EDGE + M.SKIP_H + 6 + M.SELECT_H) * s, inner, M.SELECT_H * s),
			skip = hasSkip and rect(x + M.EDGE * s, bottom - (M.EDGE + M.SKIP_H) * s, inner, M.SKIP_H * s) or nil,
			target = rect(x + M.EDGE * s, bottom - (M.EDGE + M.SKIP_H + 6 + M.SELECT_H + 8 + M.TARGET_H) * s, inner, M.TARGET_H * s),
		}
	end
	out.tips = rect(w - M.TIPS_RIGHT - M.TIPS_W, M.TIPS_TOP, M.TIPS_W, M.TIPS_H)
	return out
end

-- Preferred: straight under the Skip plate when it fits on screen. Otherwise above the Target plate (over the card text, which is
-- not clickable). Never above Skip, because that is where Select sits. x is clamped inside the screen.
function M.tipSpot(w, h, card, tipW, tipH)
	local skip = card.skip or card.select
	local x = math.max(4, math.min(w - tipW - 4, skip.x + (skip.w - tipW) / 2))
	local below = skip.y + skip.h + M.TIP_GAP
	if below + tipH <= h - 4 then return x, below end
	return x, math.max(4, card.target.y - M.TIP_GAP - tipH)
end

return M
