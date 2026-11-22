--[[
	Engine/LoadingLayout.lua
	Pure layout and motion rules for the launch loading screen (ReplicatedFirst/LoadingScreenUI).
	LoadingLayout.rects(sw, sh)  pixel rects { title, bar, status, tip, skip } for a screen of sw x sh
	LoadingLayout.motion(calm)   which moving parts run: { shimmer, ember, tipFade, readyPulse }
	LoadingLayout.fadeTime(calm, normal)  seconds for the final fade (a short crossfade in calm mode, never a pop)
	Text is never under MIN_TEXT (16). Calm mode runs no looping motion and no tweens except the short final crossfade.
]]

local M = {}

M.MIN_TEXT = 16
M.BAR_ASPECT = 1536 / 305 -- the beam picture crop
M.BAR_WIDTH = 0.46 -- of the screen width
M.BAR_MIN_W = 280
M.BAR_CENTER_Y = 0.64 -- of the screen height
M.CALM_FADE = 0.12
M.SKIP = { w = 110, h = 44, margin = 20 }

local function rect(x, y, w, h)
	return { x = x, y = y, w = w, h = h, r = x + w, b = y + h }
end

function M.rects(sw, sh)
	local barW = math.max(M.BAR_MIN_W, sw * M.BAR_WIDTH)
	local barH = barW / M.BAR_ASPECT
	local cy = sh * M.BAR_CENTER_Y
	local bar = rect(sw / 2 - barW / 2, cy - barH / 2, barW, barH)
	local lineH = M.MIN_TEXT + 8
	local status = rect(sw * 0.15, bar.b + 6, sw * 0.7, lineH)
	-- the tip keeps clear of the Skip button at the right and may wrap to two lines on narrow screens
	local tipW = math.min(sw * 0.86, sw - 2 * (M.SKIP.w + M.SKIP.margin + 10))
	local tip = rect(sw / 2 - tipW / 2, status.b + 4, tipW, lineH * 2)
	local title = rect(sw * 0.1, sh * 0.09, sw * 0.8, sh * 0.12)
	local skip = rect(sw - M.SKIP.margin - M.SKIP.w, sh - M.SKIP.margin - M.SKIP.h, M.SKIP.w, M.SKIP.h)
	return { title = title, bar = bar, status = status, tip = tip, skip = skip }
end

function M.motion(calm)
	local on = not calm
	return { shimmer = on, ember = on, tipFade = on, readyPulse = on }
end

function M.fadeTime(calm, normal)
	if calm then return M.CALM_FADE end
	return normal
end

return M
