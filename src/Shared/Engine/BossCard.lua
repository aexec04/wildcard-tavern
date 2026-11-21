--[[
	Shared/Engine/BossCard.lua
	Pure rules for the Gameplay2 boss round presentation (display only, never changes a run).

	BossCard.health(target, score) -> current, total     boss health = max(0, Target - Score), total = Target (floored)
	BossCard.healthText(cur, total) -> "300 / 300"
	BossCard.fraction(cur, total) -> 0..1                 width of the red fill
	BossCard.cardRect(r, viewW, viewH) -> rect | nil      the left Boss card: the same rect as the Patron Power panel (nil = nothing fits)
	BossCard.cardParts(rect) -> { portrait, text }        portrait square at the left, name plus rule at the right (card-local px)
	BossCard.topParts(r) -> { name, bar, night|nil }      rows inside the top scroll (r.round): name large, red bar under it, small Night line
	BossCard.glow(calm) -> { pulse, stroke, softStroke }  pulse seconds (nil when calm), stroke widths
]]

local PatronPowerPanel = require(script.Parent.PatronPowerPanel)

local M = {}

M.PULSE_SECONDS = 0.9
M.TWEEN_SECONDS = 0.3
M.NIGHT_MIN_H = 60 -- the scroll must be at least this tall for the small Night line

function M.health(target, score)
	local t = math.max(0, math.floor(tonumber(target) or 0))
	local s = math.max(0, math.floor(tonumber(score) or 0))
	return math.max(0, t - s), t
end

function M.healthText(cur, total)
	return string.format("%d / %d", math.floor(cur or 0), math.floor(total or 0))
end

function M.fraction(cur, total)
	if (tonumber(total) or 0) <= 0 then return 0 end
	return math.max(0, math.min(1, (tonumber(cur) or 0) / total))
end

function M.cardRect(r, viewW, viewH)
	local spot = PatronPowerPanel.place(r, viewW, viewH, {})
	return spot and spot.plate or nil
end

function M.cardParts(rect)
	local pad = 8
	local side = math.max(24, rect.h - 2 * pad)
	local portrait = { x = pad, y = pad, w = side, h = side }
	local tx = portrait.x + side + pad
	return { portrait = portrait, text = { x = tx, y = pad, w = math.max(20, rect.w - tx - pad), h = rect.h - 2 * pad } }
end

function M.topParts(r)
	local R = r.round
	local pad = R.h >= 40 and 4 or 2
	local innerW = R.w - 2 * pad
	local innerH = R.h - 2 * pad
	local x = R.x + pad
	local parts
	if R.h >= M.NIGHT_MIN_H then
		local nameH = math.floor(innerH * 0.42)
		local barH = math.floor(innerH * 0.30)
		local nightH = innerH - nameH - barH
		parts = {
			name = { x = x, y = R.y + pad, w = innerW, h = nameH },
			bar = { x = x, y = R.y + pad + nameH, w = innerW, h = barH },
			night = { x = x, y = R.y + pad + nameH + barH, w = innerW, h = nightH },
		}
	else
		local nameH = math.floor(innerH * 0.5)
		parts = {
			name = { x = x, y = R.y + pad, w = innerW, h = nameH },
			bar = { x = x, y = R.y + pad + nameH, w = innerW, h = innerH - nameH },
		}
	end
	return parts
end

function M.glow(calm)
	return { pulse = (not calm) and M.PULSE_SECONDS or nil, stroke = 3, softStroke = 2 }
end

return M
