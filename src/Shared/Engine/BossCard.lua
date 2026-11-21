--[[
	Shared/Engine/BossCard.lua
	Pure rules for the Gameplay2 boss round presentation (display only, never changes a run).

	BossCard.health(target, score) -> current, total     boss health = max(0, Target - Score), total = Target (floored)
	BossCard.healthText(cur, total) -> "300 / 300"
	BossCard.fraction(cur, total) -> 0..1                 width of the red fill
	BossCard.cardRect(r, viewW, viewH) -> rect | nil      the left Boss card: the same rect as the Patron Power panel (nil = nothing fits)
	BossCard.cardParts(rect) -> { portrait, text }        portrait square at the left, name plus rule at the right (card-local px)
	BossCard.plateRect(r) -> rect | nil                   the taller boss plate over the scroll (nil when the room is short)
	BossCard.topParts(r) -> { plate|nil, name, bar, night|nil }  rows inside the plate (or the scroll): name large, red bar under it, small Night line
	BossCard.glow(calm) -> { pulse, stroke, softStroke }  pulse seconds (nil when calm), stroke widths
]]

local PatronPowerPanel = require(script.Parent.PatronPowerPanel)

local M = {}

M.PULSE_SECONDS = 0.9
M.TWEEN_SECONDS = 0.3
M.NIGHT_MIN_H = 60 -- the plate or scroll must be at least this tall for the small Night line
M.PLATE_H = 96 -- the boss plate height on a roomy screen

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

function M.plateRect(r)
	-- the boss plate: up to PLATE_H tall, from just above the scroll down to 4 px clear of the first Patron seat; nil when there is no extra room
	local R = r.round
	local seatTop = math.huge
	for _, s in ipairs(r.slots or {}) do
		if s.card then seatTop = math.min(seatTop, s.card.y) end
	end
	local y = math.max(2, R.y - 4)
	local h = seatTop < math.huge and math.min(M.PLATE_H, seatTop - 4 - y) or R.h
	if h <= R.h + 8 then return nil end
	return { x = R.x, y = y, w = R.w, h = h }
end

function M.topParts(r)
	local R = r.round
	local plate = M.plateRect(r)
	if plate and plate.h >= M.NIGHT_MIN_H then
		local pad = 4
		local avail = plate.h - 2 * pad
		local nameH = math.min(30, math.floor(avail * 0.38)) -- 26 px words in a 30 px row on the tallest plate
		local barH = math.min(22, math.floor(avail * 0.30))
		local nightH = math.min(18, avail - nameH - barH - 4)
		local used = nameH + barH + nightH + 4
		local y0 = plate.y + pad + math.floor((avail - used) / 2)
		local x, w = plate.x + pad, plate.w - 2 * pad
		return {
			plate = plate,
			name = { x = x, y = y0, w = w, h = nameH },
			bar = { x = x, y = y0 + nameH + 2, w = w, h = barH },
			night = { x = x, y = y0 + nameH + barH + 4, w = w, h = nightH },
		}
	end
	local pad = R.h >= 40 and 4 or 2
	local innerW = R.w - 2 * pad
	local innerH = R.h - 2 * pad
	local x = R.x + pad
	if R.h >= M.NIGHT_MIN_H then
		local nameH = math.floor(innerH * 0.42)
		local barH = math.floor(innerH * 0.30)
		return {
			name = { x = x, y = R.y + pad, w = innerW, h = nameH },
			bar = { x = x, y = R.y + pad + nameH, w = innerW, h = barH },
			night = { x = x, y = R.y + pad + nameH + barH, w = innerW, h = innerH - nameH - barH },
		}
	end
	local nameH = math.floor(innerH * 0.5)
	return {
		name = { x = x, y = R.y + pad, w = innerW, h = nameH },
		bar = { x = x, y = R.y + pad + nameH, w = innerW, h = innerH - nameH },
	}
end

-- stroke = 3 px gold on the Boss card, outer = soft rings reaching 24 px past each edge that pulse between lo and hi transparency,
-- seatStroke = the steady 2 px gold edge on the other Patron cards
function M.glow(calm)
	return { pulse = (not calm) and M.PULSE_SECONDS or nil, stroke = 3, softStroke = 2, seatStroke = 2, outer = 24, lo = 0.35, hi = 0.7 }
end

return M
