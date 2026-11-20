--[[
	Engine/CardLook.lua
	Gameplay v2: the look of a hand card on the tavern table, pure and tested. The card faces are warm aged paper with a thin dark
	outline; a selected card wears a thin warm gold edge (never a bright cyan or white glow); the corner rank stays readable.

	edge(selected, hovering)   -> { thickness, transparency, rgb } for the card's selection stroke
	EDGE_RGB                   the gold of the edge (warm, deeper than the old pale gold, so it never reads as white on paper)
	rankPx(cardW, cardH)       -> pixels the code-drawn corner rank gets (its box is 0.36 x 0.18 of the card, two characters wide at most)
	MIN_RANK_1280              the smallest rank at 1280 x 720 (18)
	isCoolGlow(rgb)            -> true for a blue, cyan or near white colour (blue at least as strong as red, or all channels above 235)
]]

local M = {}

M.EDGE_RGB = { 255, 214, 102 }
M.MIN_RANK_1280 = 18
M.RANK_BOX = { w = 0.36, h = 0.18 } -- Client/CardFace default index box, as fractions of the card
M.RANK_FLOOR = 15 -- the UITextSizeConstraint minimum in Client/CardFace

function M.edge(selected, hovering)
	local rgb = M.EDGE_RGB
	if selected and hovering then return { thickness = 3, transparency = 0, rgb = rgb } end
	if selected then return { thickness = 3, transparency = 0, rgb = rgb } end
	if hovering then return { thickness = 1.5, transparency = 0.5, rgb = rgb } end
	return { thickness = 1, transparency = 1, rgb = rgb }
end

function M.rankPx(cardW, cardH)
	local byHeight = M.RANK_BOX.h * cardH
	local byWidth = M.RANK_BOX.w * cardW / 1.2 -- "10" is about 1.2 text heights wide
	return math.max(M.RANK_FLOOR, math.floor(math.min(byHeight, byWidth)))
end

function M.isCoolGlow(rgb)
	local r, g, b = rgb[1], rgb[2], rgb[3]
	if r > 235 and g > 235 and b > 235 then return true end
	return b >= r
end

return M
