-- Rows of the Menu Rank plate for a given text size. The board raises text sizes so they read at least 14 px after its scale
-- (24 px at a 0.59 scale), so the rows must follow the size: Rank line, 4 px, bar with the XP line on it, 4 px, Next line, 8 px bottom padding.
local M = {}

M.TOP, M.GAP, M.BOTTOM = 10, 4, 8

function M.rows(textSize)
	local ts = math.max(14, math.floor(textSize or 16))
	local lineH = ts + 2
	local textY = M.TOP
	local barH = ts + 6 -- the bar carries the "90 / 260 XP" line, so it is as tall as a line of text
	local barY = textY + lineH + M.GAP
	local rewardY = barY + barH + M.GAP
	return { textY = textY, textH = lineH, barY = barY, barH = barH, rewardY = rewardY, rewardH = lineH, h = rewardY + lineH + M.BOTTOM }
end

return M
