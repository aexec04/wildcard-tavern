--[[
	Engine/PopMotion.lua
	One motion style for every popup and page (Client/VisualHelpers popIn and popOut): the backdrop fades and the panel slides up a few pixels
	while it settles from a slightly smaller size, all in 0.15 s. A full screen page only fades (its layout measures the panel, so it never
	moves or scales). Calm mode is static: no fade, no slide, no scale, the popup is simply there. Pure numbers, no Roblox calls.
]]
local M = {}

M.DURATION = 0.15
M.SLIDE_PX = 12
M.FROM_SCALE = 0.95
M.OUT_SCALE = 0.95

-- calm: Calm mode on. fullScreen: a full screen page. Returns what to tween on the way in (`in`) and out (`out`).
function M.plan(calm, fullScreen)
	if calm then
		return { animate = false, duration = 0, slide = 0, fromScale = 1, outScale = 1, fade = false }
	end
	return {
		animate = true,
		duration = M.DURATION,
		slide = fullScreen and 0 or M.SLIDE_PX,
		fromScale = fullScreen and 1 or M.FROM_SCALE,
		outScale = fullScreen and 1 or M.OUT_SCALE,
		fade = true,
	}
end

return M
