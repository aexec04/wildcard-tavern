-- Rows of the Menu Rank plate for a given text size. The board raises text sizes so they read at least 14 px after its scale
-- (24 px at a 0.59 scale), so the rows must follow the size: XP line, 4 px, bar, 4 px, Next line, 8 px bottom padding.
local M = {}

M.TOP, M.GAP, M.BAR, M.BOTTOM = 10, 4, 8, 8

function M.rows(textSize)
	local ts = math.max(14, math.floor(textSize or 16))
	local lineH = ts + 2
	local textY = M.TOP
	local barY = textY + lineH + M.GAP
	local rewardY = barY + M.BAR + M.GAP
	return { textY = textY, textH = lineH, barY = barY, barH = M.BAR, rewardY = rewardY, rewardH = lineH, h = rewardY + lineH + M.BOTTOM }
end

return M
