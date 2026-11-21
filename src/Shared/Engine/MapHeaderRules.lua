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
M.STAT_WEIGHT = { night = 0.34, journey = 0.39, keys = 0.27 }
M.NODE_BAND_H = 150 -- node + name + tag, tallest stack on the road

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

function M.layout(sw, sh)
	local m = M.MARGIN
	local barH = clamp(math.floor(sh * 0.085), 44, FullScreen.STRIP_H) -- never taller than the strip the Find me controls sit under
	local xs = 40 -- Client/CloseX draws a 40 px disc
	local xr = { x = sw - m - xs, y = math.floor((barH - xs) / 2), w = xs, h = xs }
	local bw, bh = clamp(math.floor(sw * 0.034), 34, 66), barH + clamp(math.floor(sh * 0.07), 20, 64) -- hangs below the bar with a pointed bottom
	local left = math.min(FullScreen.HEADER_LEFT, math.floor(sw * 0.3))
	local wide = sw >= 1100 -- the banners need room: under 1100 px the plates take it
	local bannerL = wide and { x = left, y = 0, w = bw, h = bh } or nil
	local bannerR = wide and { x = xr.x - m - bw, y = 0, w = bw, h = bh } or nil
	local cursor = bannerL and (bannerL.x + bw + 8) or left
	local limit = (bannerR and bannerR.x or xr.x) - 6
	local avail = limit - cursor - 8
	local plateH = barH - 14
	local titleW = clamp(math.floor(avail * 0.3), 150, 320)
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
	local L = {
		bar = { x = 0, y = 0, w = sw, h = barH }, title = title, stats = stats, x = xr, bannerL = bannerL, bannerR = bannerR,
		candleL = candleL, candleR = candleR, panelZone = panelZone, stat = stat,
		band = { x = 0, y = barH, w = sw, h = sh - barH }, -- where nodes may sit
		textSize = clamp(math.floor(barH * 0.36), M.MIN_TEXT, 24),
	}
	-- sizes: title 28 px and stats 22 px at the full header, icons 28 px; each shrinks (never under 14) so its words fit their own plate
	return M.sized(L)
end

-- Fixed texts of the header plates (the numbers stay at most two digits).
M.TITLE_TEXT = "The Tavern Map"
M.STAT_CHARS = { night = 13, journey = 16, keys = 9 } -- "Night 8 / 8", "Journey 11 / 11", "Keys 99" with their spaces round the slash
M.STAT_CHARS_COMPACT = { night = 10, journey = 12, keys = 7 } -- narrow plate: "Night 8/8", "Journey 11/11"
function M.statChars(compact) return compact and M.STAT_CHARS_COMPACT or M.STAT_CHARS end
M.COMPACT_BELOW = 500 -- a stats plate narrower than this drops the spaces round the slash
M.CHAR_EM = 0.66 -- average advance of a bold Gotham letter, in em (a wide estimate)

function M.textWidth(chars, size) return math.ceil(chars * size * M.CHAR_EM) end

function M.sized(L)
	local bar = L.bar.h
	local compact = L.stats.w < M.COMPACT_BELOW
	local chars = M.statChars(compact)
	local titleSize = clamp(math.floor(bar * 0.44), M.MIN_TEXT, 28)
	while titleSize > M.MIN_TEXT and M.textWidth(#M.TITLE_TEXT, titleSize) > L.title.w - 20 do titleSize = titleSize - 1 end
	local function fit(iconSize)
		local size = clamp(math.floor(bar * 0.35), M.MIN_TEXT, 22)
		local ok = true
		for k, cell in pairs(L.stat) do
			local room = cell.w - (iconSize > 0 and (iconSize + 14) or 14) - 6
			while size > M.MIN_TEXT and M.textWidth(chars[k], size) > room do size = size - 1 end
			if M.textWidth(chars[k], size) > room then ok = false end
		end
		return size, ok
	end
	local iconSize = clamp(math.floor(bar * 0.44), M.MIN_TEXT, 28)
	local statSize, ok = fit(iconSize)
	if not ok then -- no room for the icons: the words alone
		iconSize = 0
		statSize = fit(0)
	end
	L.titleSize, L.statSize, L.iconSize, L.compact = titleSize, statSize, iconSize, compact
	-- icon then text inside each stat cell, relative to the cell
	L.cellParts = {}
	for k, cell in pairs(L.stat) do
		if iconSize > 0 then
			local ih = iconSize + 4
			L.cellParts[k] = {
				icon = { x = 6, y = math.floor((cell.h - ih) / 2), w = iconSize + 4, h = ih },
				text = { x = 6 + iconSize + 6, y = 0, w = cell.w - iconSize - 14, h = cell.h },
			}
		else
			L.cellParts[k] = { text = { x = 7, y = 0, w = cell.w - 14, h = cell.h } }
		end
	end
	return L
end

function M.overlaps(a, b)
	return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

return M
