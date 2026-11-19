--[[
	Engine/Gameplay2ScorePlate.lua
	Gameplay v2: where the hand result lives. The reference mockup (claude/reference/concept-table-reference.png, 1672 x 941) has the
	framed Score plate at x 680 to 995, y 365 to 455. This module turns that into rects for any window, always inside the stage
	(Gameplay2Layout.rects(w, h).stage), and splits it into rows: hand name, chips x mult, total, flourish line. Pure numbers, tested.
	Nothing on the plate stays longer than MAX_LINGER seconds after the hand lands. Presentation only: it never changes a score.

	plate(w, h)          -> { x, y, w, h } the Score plate, inside the stage
	rows(w, h)           -> { name, counters, total, flourish } rects inside the plate, stacked, none overlapping
	lingers(hold, calm)  -> true when an element held `hold` seconds is gone by MAX_LINGER (calm and static labels count too)
]]

local Layout = require(script.Parent.Gameplay2Layout)

local M = {}

M.REF_W, M.REF_H = 1672, 941
M.REF = { x = 680, y = 365, w = 315, h = 90 }
M.MAX_LINGER = 3 -- seconds
M.MIN_W = 180

local function round(n) return math.floor(n + 0.5) end

function M.plate(w, h)
	local st = Layout.rects(w, h).stage
	local pw = math.max(M.MIN_W, round(M.REF.w / M.REF_W * w))
	pw = math.min(pw, st.w)
	local ph = math.min(st.h, math.max(round(M.REF.h / M.REF_H * h), 60))
	local x = round((w - pw) / 2)
	local y = round(M.REF.y / M.REF_H * h)
	y = math.max(st.y, math.min(y, st.y + st.h - ph)) -- never outside the stage, so never over a Patron row or the hand
	return { x = x, y = y, w = pw, h = ph }
end

-- rows stacked top to bottom inside the plate with a 2 px gap: name 24 percent, counters 22, total 40, flourish 14
function M.rows(w, h)
	local p = M.plate(w, h)
	local fr = { { "name", 0.24 }, { "counters", 0.22 }, { "total", 0.40 }, { "flourish", 0.14 } }
	local out, y = {}, p.y
	for i, f in ipairs(fr) do
		local rh = (i == #fr) and (p.y + p.h - y) or round(p.h * f[2])
		out[f[1]] = { x = p.x, y = y, w = p.w, h = math.max(1, rh - (i < #fr and 2 or 0)) }
		y = y + rh
	end
	return out
end

function M.lingers(hold, calm)
	hold = tonumber(hold) or 0
	return hold <= M.MAX_LINGER
end

return M
