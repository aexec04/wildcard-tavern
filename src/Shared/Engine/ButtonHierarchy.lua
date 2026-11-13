--[[
	Engine/ButtonHierarchy.lua
	Pure math for the action plates and the Hands / Discards tile text.

	ButtonHierarchy.FACTOR            size factor per plate, relative to the Play Hand plate (aspect is kept, the painted plate is never stretched)
	ButtonHierarchy.plateRects(...)   the three plates' rects, all standing on ONE baseline (the Play Hand plate's bottom edge)
	ButtonHierarchy.tileText(text)    "Hands 3" -> "Hands", "3" (nil when it does not match)
	ButtonHierarchy.tileRich(word, number) -> rich text: word 15 px on top, number 28 px bold below
]]

local M = {}

M.FACTOR = { sort = 1, play = 1, discard = 0.8 } -- Play Hand is the dominant primary, Discard secondary, Rank | Suit a small utility group
M.WORD_SIZE, M.NUMBER_SIZE = 15, 28

-- boxes: { sort = {w,h}, play = {w,h}, discard = {w,h} } at scale ps; gap between plates; centre x; stripY, stripH = band they stand in.
function M.plateRects(boxes, ps, gap, centreX, stripY, stripH)
	local w, h = {}, {}
	local total = 0
	for _, k in ipairs({ "sort", "play", "discard" }) do
		local f = M.FACTOR[k]
		w[k], h[k] = boxes[k].w * ps * f, boxes[k].h * ps * f
		total = total + w[k]
	end
	total = total + 2 * gap
	-- the Play Hand plate stays centred in the strip, the others stand on its bottom edge (whole pixels, so the baseline is exact)
	local baseline = math.floor(stripY + (stripH - h.play) / 2 + 0.5) + math.floor(h.play + 0.5)
	local x = centreX - total / 2
	local out = {}
	for _, k in ipairs({ "sort", "play", "discard" }) do
		local ph = math.floor(h[k] + 0.5)
		out[k] = { x = math.floor(x + 0.5), y = baseline - ph, w = math.floor(w[k] + 0.5), h = ph }
		x = x + w[k] + gap
	end
	return out
end

function M.tileText(text)
	local word, number = tostring(text or ""):match("^(%a+)%s+([%d%.%-]+)$")
	if not word then return nil end
	return word, number
end

function M.tileRich(word, number)
	return string.format('<font size="%d">%s</font>\n<font size="%d"><b>%s</b></font>', M.WORD_SIZE, word, M.NUMBER_SIZE, number)
end

return M
