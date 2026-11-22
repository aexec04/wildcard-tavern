--[[
	Engine/LoadingLook.lua
	Numbers for the launch loading screen's look (ReplicatedFirst/LoadingScreenUI). The painting stays clearly visible: only ONE soft
	scrim at the bottom (under the status and tip lines) and a lighter one at the top (under the title), each a single frame with a
	UIGradient fade from Engine/ScrimGradient, never stacked bands.

	LoadingLook.scrimOpacity(spec, y)  how opaque the black scrim is at screen height y (0 to 1)
	LoadingLook.worstContrast(textColor, spec, y)  contrast of the text against the BRIGHTEST possible painting under the scrim
]]

local M = {}

M.CREAM = { 240, 225, 190 }
M.TITLE_GOLD = { 232, 196, 112 }
M.STATUS_SIZE, M.TIP_SIZE = 18, 16
M.STATUS_Y, M.TIP_Y = 0.73, 0.78 -- top of each line, fractions of the screen height

-- the bottom scrim is clear at `from` and `peak` opaque at `to`; the top one is opaque at `from` and clear at `to`
M.BOTTOM = { from = 0.4, to = 1, peak = 0.9, exponent = 0.5, flip = false }
M.TOP = { from = 0.0, to = 0.3, peak = 0.45, exponent = 1.0, flip = true }

function M.scrimOpacity(spec, y)
	local t = (y - spec.from) / (spec.to - spec.from)
	if spec.flip then t = 1 - t end
	t = math.max(0, math.min(1, t))
	return spec.peak * (t ^ spec.exponent)
end

local function lin(v)
	v = v / 255
	return v <= 0.03928 and v / 12.92 or ((v + 0.055) / 1.055) ^ 2.4
end
local function lum(c) return 0.2126 * lin(c[1]) + 0.7152 * lin(c[2]) + 0.0722 * lin(c[3]) end

function M.worstContrast(text, spec, y)
	local g = 255 * (1 - M.scrimOpacity(spec, y)) -- a white painting darkened by the scrim
	local a, b = lum(text), lum({ g, g, g })
	if a < b then a, b = b, a end
	return (a + 0.05) / (b + 0.05)
end

return M
