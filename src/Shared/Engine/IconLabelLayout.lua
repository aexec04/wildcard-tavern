--[[
	Shared/Engine/IconLabelLayout.lua
	Where a plate's small icon and its word go: the icon stands at the left (14 px in), a square 0.53 of the plate height, centred
	vertically; the word starts 6 px right of the icon and ends 8 px before the right edge. The two rects never touch.
	IconLabelLayout.place(w, h) -> { icon = {x,y,w,h}, label = {x,y,w,h} }   (plate pixels, whole numbers)
]]
local M = {}
M.LEFT, M.GAP, M.RIGHT, M.ICON_K, M.MIN_ICON = 14, 6, 8, 0.53, 8

function M.place(w, h)
	w, h = math.max(1, math.floor(w)), math.max(1, math.floor(h))
	local s = math.max(M.MIN_ICON, math.floor(h * M.ICON_K + 0.5))
	local lx = M.LEFT + s + M.GAP
	return {
		icon = { x = M.LEFT, y = math.floor((h - s) / 2), w = s, h = s },
		label = { x = lx, y = 0, w = math.max(0, w - lx - M.RIGHT), h = h },
	}
end

return M
