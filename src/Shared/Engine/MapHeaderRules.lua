--[[
	Shared/Engine/MapHeaderRules.lua
	Pure layout of the Tavern Map frame (Client/MapHeaderBar draws it): the carved wood header bar, the title plate, the Night / Journey / Keys
	plate, the round X, the purple crown banners, the candles and the strip kept free for the selection panel (lower left). No Roblox types.

	layout(sw, sh) -> { bar, title, stats, x, bannerL, bannerR (nil on narrow screens), candleL, candleR, panelZone, band, stat = { night, journey, keys }, textSize }
	Every rect is { x, y, w, h } in screen pixels. Header content starts right of Roblox's own buttons (FullScreenRules.HEADER_LEFT).
]]

local FullScreen = require(script.Parent.FullScreenRules)

local M = {}
M.MARGIN = 12
M.MIN_TEXT = 14
M.STAT_WEIGHT = { night = 0.33, journey = 0.4, keys = 0.27 }
M.NODE_BAND_H = 150 -- node + name + tag, tallest stack on the road

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

function M.layout(sw, sh)
	local m = M.MARGIN
	local barH = clamp(math.floor(sh * 0.085), 44, FullScreen.STRIP_H) -- never taller than the strip the Find me controls sit under
	local xs = 40 -- Client/CloseX draws a 40 px disc
	local xr = { x = sw - m - xs, y = math.floor((barH - xs) / 2), w = xs, h = xs }
	local bw, bh = clamp(math.floor(sw * 0.026), 30, 46), barH + clamp(math.floor(sh * 0.04), 12, 30)
	local left = math.min(FullScreen.HEADER_LEFT, math.floor(sw * 0.3))
	local bannerL = { x = left, y = 0, w = bw, h = bh }
	local wide = sw >= 1100
	local bannerR = wide and { x = xr.x - m - bw, y = 0, w = bw, h = bh } or nil
	local cursor = bannerL.x + bw + 8
	local limit = (bannerR and bannerR.x or xr.x) - 8
	local avail = limit - cursor - 8
	local plateH = barH - 14
	local titleW = clamp(math.floor(avail * (wide and 0.3 or 0.3)), 120, 320)
	local title = { x = cursor, y = 7, w = titleW, h = plateH }
	local stats = { x = title.x + titleW + 8, y = 7, w = limit - (title.x + titleW + 8), h = plateH }
	local stat, cx = {}, stats.x
	for _, k in ipairs({ "night", "journey", "keys" }) do
		local w = math.floor(stats.w * M.STAT_WEIGHT[k])
		stat[k] = { x = cx, y = stats.y, w = w, h = stats.h }
		cx = cx + w
	end
	local panelH = clamp(math.floor(sh * 0.29), 110, 300)
	local panelW = clamp(math.floor(sw * 0.40), 300, 760)
	local panelZone = { x = m, y = sh - panelH - m, w = panelW, h = panelH }
	local cs = clamp(math.floor(sh * 0.07), 30, 64)
	local candleR = { x = sw - m - cs, y = sh - cs - m, w = cs, h = cs }
	local candleL = { x = panelZone.x + panelZone.w + 8, y = sh - cs - m, w = cs, h = cs }
	return {
		bar = { x = 0, y = 0, w = sw, h = barH }, title = title, stats = stats, x = xr, bannerL = bannerL, bannerR = bannerR,
		candleL = candleL, candleR = candleR, panelZone = panelZone, stat = stat,
		band = { x = 0, y = barH, w = sw, h = sh - barH }, -- where nodes may sit
		textSize = clamp(math.floor(barH * 0.36), M.MIN_TEXT, 24),
	}
end

function M.overlaps(a, b)
	return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

return M
