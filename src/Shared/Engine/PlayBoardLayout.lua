--[[
	Shared/Engine/PlayBoardLayout.lua
	Pure geometry for the painted left HUD board (art key play_board_a, 1024x1536, hangs from ropes). Slot rects are measured
	from the PNG (art-wip/play_scene/debug_board.png) in picture pixels; `map` scales them to a panel rect.

	PlayBoardLayout.size(screenW, screenH) -> w, h : the board fits the screen height at its 2:3 ratio, width at most 24 percent of the screen
	PlayBoardLayout.map(w, h)  -> { title, target, wide, hands, discards, rings = { {cx, cy, d} x5 }, ringInset }
	PlayBoardLayout.usable(screenW)  false under MIN_W: use the old layout
]]

local M = {}

M.IMG_W, M.IMG_H = 1024, 1536
M.MIN_W = 900
M.MAX_WIDTH_FRACTION = 0.24

M.SLOTS = {
	title = { x = 280, y = 388, w = 462, h = 110 }, -- Night 1/8 and Round
	target = { x = 232, y = 538, w = 560, h = 204 }, -- target and score, bar, Reward
	wide = { x = 236, y = 784, w = 554, h = 154 }, -- Tips and the round rule
	hands = { x = 232, y = 974, w = 264, h = 144 },
	discards = { x = 528, y = 974, w = 264, h = 144 },
}
M.RING_Y, M.RING_D = 1215, 100
M.RING_X = { 288, 396, 504, 612, 738 }
M.RING_INSET = 0.08 -- portraits are inset 8 percent so the brass ring shows

function M.usable(screenW)
	return screenW >= M.MIN_W
end

function M.size(screenW, screenH)
	local h = screenH
	local w = h * M.IMG_W / M.IMG_H
	local maxW = screenW * M.MAX_WIDTH_FRACTION
	if w > maxW then
		w = maxW
		h = w * M.IMG_H / M.IMG_W
	end
	return math.floor(w), math.floor(h)
end

function M.map(w, h)
	local sx, sy = w / M.IMG_W, h / M.IMG_H
	local function r(s)
		return { x = math.floor(s.x * sx + 0.5), y = math.floor(s.y * sy + 0.5), w = math.floor(s.w * sx + 0.5), h = math.floor(s.h * sy + 0.5) }
	end
	local out = { rings = {}, ringInset = M.RING_INSET }
	for k, s in pairs(M.SLOTS) do
		out[k] = r(s)
	end
	for i, cx in ipairs(M.RING_X) do
		out.rings[i] = { cx = math.floor(cx * sx + 0.5), cy = math.floor(M.RING_Y * sy + 0.5), d = math.floor(M.RING_D * sx + 0.5) }
	end
	return out
end

return M
