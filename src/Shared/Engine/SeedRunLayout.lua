--[[
	Shared/Engine/SeedRunLayout.lua
	Pixel rows of the Seed Run dialog (Client/SeedRunDialog reads them). Every button and the code box are 44 px tall, text is 14 px
	or more, the hint has room for three lines, and the panel is small enough for a phone screen (800x360). Pure Lua.

	SeedRunLayout.rects() -> { panel = {w,h}, title, hint, box, roll, start, cancel }  (x, y, w, h inside the panel)
]]
local SeedRunLayout = {}

SeedRunLayout.PANEL_W = 360
SeedRunLayout.PANEL_H = 252
SeedRunLayout.PAD = 15
SeedRunLayout.CONTROL_H = 44
SeedRunLayout.MIN_TEXT = 14
SeedRunLayout.TITLE_SIZE = 18
SeedRunLayout.HINT_SIZE = 14
SeedRunLayout.BOX_SIZE = 18
SeedRunLayout.BUTTON_SIZE = 15
SeedRunLayout.HINT_LINES = 3

function SeedRunLayout.rects()
	local L = SeedRunLayout
	local w, h, pad, c = L.PANEL_W, L.PANEL_H, L.PAD, L.CONTROL_H
	local hintH = L.HINT_LINES * 18 + 2
	local boxY = 46 + hintH + 8
	local btnY = h - 12 - c
	local rollW = 80
	return {
		panel = { w = w, h = h },
		title = { x = pad, y = 14, w = w - 2 * pad, h = 28 },
		hint = { x = pad, y = 46, w = w - 2 * pad, h = hintH },
		box = { x = pad, y = boxY, w = w - 2 * pad - rollW - 10, h = c },
		roll = { x = w - pad - rollW, y = boxY, w = rollW, h = c },
		start = { x = 20, y = btnY, w = 140, h = c },
		cancel = { x = w - 20 - 140, y = btnY, w = 140, h = c },
	}
end

return SeedRunLayout
