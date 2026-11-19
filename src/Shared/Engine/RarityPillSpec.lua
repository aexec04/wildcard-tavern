--[[
	Shared/Engine/RarityPillSpec.lua
	Numbers for the native rarity pill under a Patron card (a rounded Frame, a 1.5 px stroke in the tier colour, a flat fill, serif
	word with a dark outline, the shape marker inside at the left). No image is scaled. Pure data, no Roblox calls, tested.
	Client/RarityPill draws it.

	RarityPillSpec.spec(tier, cardW) -> { w, h, textSize, pad, marker = { x, px }, text = { x, w }, fill, stroke, ink, word }
	Colours are {r,g,b}. Height is 22 px at a 130 px card, scaled by cardW / 130 (0.85 to 1.3); width is the word plus 28 px padding.
]]

local M = {}

M.REF_CARD_W, M.BASE_H, M.PAD, M.STROKE = 130, 22, 28, 1.5
M.WORD = { common = "Common", uncommon = "Uncommon", rare = "Rare", epic = "Epic", legendary = "Legendary" }
M.order = { "common", "uncommon", "rare", "epic", "legendary" }
M.INK = { 255, 244, 214 } -- cream, 4.5:1 or better on every fill below
M.FILL = {
	common = { 98, 86, 72 }, uncommon = { 40, 112, 56 }, rare = { 40, 92, 172 }, epic = { 108, 56, 156 }, legendary = { 138, 96, 10 },
}
M.STROKE_COLOR = {
	common = { 214, 204, 182 }, uncommon = { 120, 214, 120 }, rare = { 120, 176, 255 }, epic = { 200, 140, 255 }, legendary = { 255, 214, 90 },
}
M.GLYPH = 0.62 -- average glyph width as a fraction of the text size (bold serif)

local function lum(c)
	local function f(v) v = v / 255; return v <= 0.03928 and v / 12.92 or ((v + 0.055) / 1.055) ^ 2.4 end
	return 0.2126 * f(c[1]) + 0.7152 * f(c[2]) + 0.0722 * f(c[3])
end
function M.contrast(a, b)
	local la, lb = lum(a), lum(b)
	if la < lb then la, lb = lb, la end
	return (la + 0.05) / (lb + 0.05)
end

function M.textWidth(word, textSize)
	return math.ceil(#word * textSize * M.GLYPH)
end

function M.spec(tier, cardW)
	tier = type(tier) == "string" and M.WORD[tier:lower()] and tier:lower() or "common"
	local word = M.WORD[tier]
	local scale = math.max(0.85, math.min(1.3, (tonumber(cardW) or M.REF_CARD_W) / M.REF_CARD_W))
	local h = math.floor(M.BASE_H * scale + 0.5)
	local textSize = math.max(14, math.floor(14 * scale + 0.5))
	local pad = math.floor(M.PAD * scale + 0.5)
	local w = M.textWidth(word, textSize) + pad
	if cardW and w > cardW and textSize > 14 then -- the widest word on a narrow card: drop to the 14 px floor first
		textSize = 14
		w = M.textWidth(word, textSize) + pad
	end
	local markerPx = math.floor(12 * scale + 0.5)
	local markerX = math.floor(8 * scale + 0.5)
	local textX = markerX + markerPx + math.floor(4 * scale + 0.5)
	return {
		w = w, h = h, textSize = textSize, pad = pad, word = word, scale = scale,
		marker = { x = markerX, px = markerPx },
		text = { x = textX, w = w - textX - math.floor(4 * scale + 0.5) },
		fill = M.FILL[tier], stroke = M.STROKE_COLOR[tier], ink = M.INK,
	}
end

return M
