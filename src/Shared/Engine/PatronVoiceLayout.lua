--[[
	Engine/PatronVoiceLayout.lua
	Where a Patron's speech bubble stands on the Gameplay v2 table: below the Patron row (under the labels and pills), centred on its
	own Patron, at most 260 px wide, so it never covers another Patron's portrait. Pure numbers in root pixels.

	PatronVoiceLayout.rect(cardX, cardW, rowBottom, rootW) -> { x, y, w, h }   x, y = top left
]]

local M = {}

M.MAX_W = 260
M.H = 40
M.GAP = 6
M.EDGE = 8

function M.rect(cardX, cardW, rowBottom, rootW)
	local w = math.min(M.MAX_W, math.max(120, rootW - 2 * M.EDGE))
	local cx = cardX + cardW / 2
	local x = math.max(M.EDGE, math.min(cx - w / 2, rootW - M.EDGE - w))
	return { x = math.floor(x), y = math.floor(rowBottom + M.GAP), w = math.floor(w), h = M.H }
end

return M
