--[[
	Shared/Engine/RunSetupLayout.lua
	Pure numbers for the pre run screen (Client/RunSetup.lua): the panel is 0.6 x 0.72 of the window at (0.2, 0.13), the title bar is 45 px,
	the option scroll fills the rest down to 65 px above the foot (115 px of chrome in all), and Begin Run (200 x 44) and Cancel (140 x 44)
	sit side by side 55 px above the panel foot. Tested in EngineTests ("Pre run screen").
	  RunSetupLayout.rects(w, h) -> { panel, scroll, begin, cancel }  each { x, y, w, h }
]]

local M = {}

M.PANEL_W, M.PANEL_H, M.PANEL_X, M.PANEL_Y = 0.6, 0.72, 0.2, 0.13
M.SCROLL_TOP, M.SCROLL_BOTTOM_CLEAR = 45, 65 -- scroll Size is (1, -30, 1, -110) at y 45: it ends 65 px above the foot
M.BEGIN = { w = 200, h = 44 }
M.CANCEL = { w = 140, h = 44 }
M.FOOT = 55
M.TILE_H = 66

function M.rects(w, h)
	local px, py = w * M.PANEL_X, h * M.PANEL_Y
	local pw, ph = w * M.PANEL_W, h * M.PANEL_H
	local r = { panel = { x = px, y = py, w = pw, h = ph } }
	r.scroll = { x = px + 15, y = py + M.SCROLL_TOP, w = pw - 30, h = ph - 110 }
	r.begin = { x = px + pw / 2 - 210, y = py + ph - M.FOOT, w = M.BEGIN.w, h = M.BEGIN.h }
	r.cancel = { x = px + pw / 2 + 10, y = py + ph - M.FOOT, w = M.CANCEL.w, h = M.CANCEL.h }
	return r
end

return M
