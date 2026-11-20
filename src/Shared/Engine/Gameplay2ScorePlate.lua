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

-- The live plate (Client/Gameplay2): the score block (caption, numeral, "o of N" line) stands PAD px inside the carved border on every
-- side, so nothing touches the trim. `stage` is the layout stage rect, `sw` the screen width, capH/progH the caption and progress rows.
-- Returns { plate, box, inner, N }: plate = the painted frame, box = where the stack's own origin sits (stage inset PAD top and bottom),
-- inner = the plate minus its border, N = Layout.scoreStack for the inset height.
M.PAD = 8
M.MIN_FONT = 14
-- The idle Score plate must stay clear of the hand: the live hand frame rises above the layout rect (HandSizing.frameFor), so the stage the
-- plate may use ends GAP px above the highest card top. `handTop` is that frame's y; the stage only ever shrinks (never under MIN_H).
M.HAND_GAP = 12
M.MIN_H = 60
function M.idleStage(stage, handTop)
	if not handTop then return stage end
	local h = math.max(M.MIN_H, math.min(stage.h, handTop - M.HAND_GAP - stage.y))
	return { x = stage.x, y = stage.y, w = stage.w, h = h }
end

function M.live(stage, sw, capH, progH, compact)
	local pad = M.PAD
	local ih = math.max(1, stage.h - 2 * pad)
	local N = Layout.scoreStack(ih, capH, progH, compact)
	local pw = math.min(stage.w, math.max(240, math.floor(0.19 * sw))) -- the reference plate is 315 of 1672 wide (0.19)
	local shows = N.roomy and not N.noProgress -- the progress line only shows on a roomy stage
	local content = shows and N.bottom or (N.numTop + N.numH)
	local ph = math.min(stage.h, math.max(40, content + 2 * pad))
	local plate = { x = stage.x + math.floor((stage.w - pw) / 2), y = stage.y, w = pw, h = ph }
	return {
		plate = plate,
		box = { x = stage.x, y = stage.y + pad, w = stage.w, h = ih },
		inner = { x = plate.x + pad, y = plate.y + pad, w = plate.w - 2 * pad, h = plate.h - 2 * pad },
		N = N,
		contentBottom = stage.y + pad + content,
	}
end

-- the numeral shrinks (never grows) so `digits` figures fit the inner width; Gotham bold digits are about 0.62 of the font size wide
function M.fitSize(textSize, digits, innerW)
	digits = math.max(1, tonumber(digits) or 1)
	local fit = math.floor(innerW / (0.62 * digits))
	return math.max(M.MIN_FONT, math.min(textSize, fit))
end

function M.lingers(hold, calm)
	hold = tonumber(hold) or 0
	return hold <= M.MAX_LINGER
end

return M
