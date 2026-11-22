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
M.EDGE = 12 -- the Boss card stands at least this far from the left screen edge
M.PLATE_AIR = 10 -- clear space between the plate and the Patron row (never less than 8)

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

local function hit(a, b) return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h end

-- The Boss round row: the boss takes the middle seat (BOSS_SEAT), so the first two Patrons keep seats 1 and 2, the next two move to seats 4 and 5
-- and a fifth Patron stays out of the row for the round (it is still in the My Patrons list and still scores).
M.BOSS_SEAT = 3
function M.active(state)
	return type(state) == "table" and state.phase == "playing" and state.bossModifier ~= nil and (tonumber(state.round) or 0) >= 3
end

-- seat (1..5) that owned Patron i stands in, or nil when it is out of the row; outside a boss round every Patron keeps its own seat
function M.seatFor(i, boss)
	if not boss then return i end
	if i <= 2 then return i end
	if i <= 4 then return i + 1 end
	return nil
end

-- the Boss card stands in the middle seat: the same rect as a Patron card
function M.seatRect(r)
	local s = r and r.slots and r.slots[M.BOSS_SEAT]
	return s and s.card or nil
end

-- the left panel: just under the top row, level with the Patron row, about 190 px tall on the 957 px screen (reference y 185 to 375, x 20 to 380)
M.PANEL_Y = 0.193
M.PANEL_H = 0.199
M.PORTRAIT = 120

function M.cardRect(r, viewW, viewH)
	local spot = PatronPowerPanel.place(r, viewW, viewH, {})
	local pl = spot and spot.plate
	if not pl then return nil end
	local x, w = pl.x, pl.w
	if x < M.EDGE then x = M.EDGE; w = pl.w - (M.EDGE - pl.x) end -- 12 px from the screen edge, the right side stays put
	local top = math.floor(M.PANEL_Y * viewH + 0.5)
	for _, key in ipairs({ "traySlot1", "traySlot2", "trayUse", "traySell", "trayPrompt" }) do
		local t = r[key]
		if t then top = math.max(top, t.y + t.h + 6) end
	end
	local bottom = pl.y + pl.h
	local h = math.min(math.floor(M.PANEL_H * viewH + 0.5), bottom - top)
	if h > pl.h then
		local try = { x = x, y = top, w = w, h = h }
		local ok = true
		for name, rect in pairs(r) do
			if name ~= "slots" and name ~= "bar" and type(rect) == "table" and rect.x and hit(try, rect) then ok = false end
		end
		for _, s in ipairs(r.slots or {}) do
			for _, part in ipairs({ s.card, s.label, s.pill }) do if part and hit(try, part) then ok = false end end
		end
		if ok then return try end
	end
	return { x = x, y = pl.y, w = w, h = pl.h }
end

-- How far the Boss card's glow rings may reach past each edge, and how far a Patron card's halo may: both stop GLOW_CLEAR px short of the
-- next card (the halo of two neighbours shares the gap), so a glow never washes over a neighbouring seat or its badges.
M.GLOW_CLEAR = 6
function M.seatGap(r)
	local s = r and r.slots
	if not (s and s[1] and s[2] and s[1].card and s[2].card) then return 0 end
	return math.max(0, s[2].card.x - (s[1].card.x + s[1].card.w))
end
function M.bossReach(gap) return math.max(0, math.min(30, math.floor((tonumber(gap) or 0) - M.GLOW_CLEAR))) end
function M.haloReach(gap, want) return math.max(0, math.min(want or 24, math.floor(((tonumber(gap) or 0) - M.GLOW_CLEAR) / 2))) end

function M.cardParts(rect)
	local pad = 8
	local side = math.max(24, math.min(M.PORTRAIT, rect.h - 2 * pad))
	local portrait = { x = pad, y = pad, w = side, h = side }
	local tx = portrait.x + side + pad
	return { portrait = portrait, text = { x = tx, y = pad, w = math.max(20, rect.w - tx - pad), h = rect.h - 2 * pad } }
end

function M.plateRect(r)
	-- the boss plate: up to PLATE_H tall, from just above the scroll down to PLATE_AIR px clear of the first Patron seat; nil when there is no extra room
	local R = r.round
	local seatTop = math.huge
	for _, s in ipairs(r.slots or {}) do
		if s.card then seatTop = math.min(seatTop, s.card.y) end
	end
	local y = math.max(2, R.y - 4)
	local h = seatTop < math.huge and math.min(M.PLATE_H, seatTop - M.PLATE_AIR - y) or R.h
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

-- stroke = 3 px gold on the Boss card, outer = soft rings reaching 28 px past each edge that pulse between lo and hi transparency,
-- seatStroke = the steady 2 px gold edge on the other Patron cards, seatHalo = their steady soft 24 px halo at seatHaloT transparency
function M.glow(calm)
	return { pulse = (not calm) and M.PULSE_SECONDS or nil, stroke = 3, softStroke = 2, seatStroke = 2, outer = 30, lo = 0.2, hi = 0.5, seatHalo = 24, seatHaloT = 0.5, bossHaloT = 0.2 }
end

return M
