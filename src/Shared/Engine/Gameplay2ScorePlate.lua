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
M.HAND_GAP = 10
M.PICK_LIFT = 28 -- a picked card rises this far above the card tops: the idle plate ends HAND_GAP above the highest picked card
M.IDLE_MIN_FONT = 18 -- idle numeral minimum: the caption and the "o of N" line stay even on a short stage
M.NAME_NUDGE = 6 -- the hand name in the caption row drops this far so it clears the carved top border
M.CAP_H = 30-- the caption row (reference: Score about 28 px)
M.MIN_H = 2 * M.PAD + M.IDLE_MIN_FONT + M.CAP_H + 12 + 22 -- caption CAP_H, numeral, 12 px gap, progress 22: the smallest stage that holds the whole stack
M.WIDE_STAGE = 780 -- stage width (0.42 of the screen) from which the plate keeps its full size
M.IDEAL_H = 2 * M.PAD + 30 + 54 + 12 + 22 -- pad, caption, numeral, gap, progress line
-- numeral and caption row scale with the screen width (54 and 30 at 1920, 41 and 26 at 1506), never above those
function M.numeralFor(sw) return math.max(30, math.min(M.NUMERAL, round((tonumber(sw) or 1920) * 0.028125))) end
function M.capFor(sw) return math.max(26, math.min(M.CAP_H, round((tonumber(sw) or 1920) * 0.0173))) end
function M.idealH(sw) return 2 * M.PAD + M.capFor(sw) + M.numeralFor(sw) + M.PROGRESS_GAP + 22 end
function M.idleStage(stage, handTop, sw)
	if not handTop then return stage end
	local h = math.max(M.MIN_H, math.min(stage.h, handTop - M.PICK_LIFT - M.HAND_GAP - stage.y))
	local wide = (sw and stage.w >= 0.4 * sw) or (not sw and stage.w >= M.WIDE_STAGE) -- the stage is 0.42 of the screen at every size
	if wide then h = math.max(h, math.min(stage.h, sw and M.idealH(sw) or M.IDEAL_H)) end -- a wide table keeps the 100 px plate; a picked card may then rise over the line under it
	return { x = stage.x, y = stage.y, w = stage.w, h = h }
end

-- Idle plate like the reference: the plate holds the caption and a 48 px numeral only; the "o of N" line (with its arrow flourishes) stands
-- BELOW the plate, PROGRESS_GAP under its border. N.progressY is where that line starts, in the score box's own coordinates.
M.NUMERAL = 54 -- plate about 100 px tall at 1920: caption 30 + numeral 54 + 2 x 8
M.PROGRESS_GAP = 12
local function idleStack(ih, capH, progH, sw)
	local numH = math.min(sw and M.numeralFor(sw) or M.NUMERAL, ih - M.PROGRESS_GAP - progH - capH)
	if numH >= M.IDLE_MIN_FONT then
		local content = capH + numH
		local py = content + M.PAD + M.PROGRESS_GAP -- plate bottom is PAD under the numeral, then the gap
		return { roomy = true, numTop = capH, numH = numH, textSize = numH, lineY = content - 2, progressY = py, bottom = py + progH, below = true }
	end
	local N = Layout.scoreStack(ih, capH, progH, false, M.IDLE_MIN_FONT)
	return N -- a stage too short for the whole stack keeps the older shape (progress inside or dropped)
end

function M.live(stage, sw, capH, progH, compact)
	local pad = M.PAD
	local ih = math.max(1, stage.h - 2 * pad)
	local N = compact and Layout.scoreStack(ih, capH, progH, true, nil) or idleStack(ih, capH, progH, sw)
	local pw = math.min(stage.w, math.max(240, math.floor(0.19 * sw))) -- the reference plate is 315 of 1672 wide (0.19)
	local shows = N.roomy and not N.noProgress -- the progress line only shows on a roomy stage
	local content = (shows and not N.below) and N.bottom or (N.numTop + N.numH)
	local ph = math.min(stage.h, math.max(40, content + 2 * pad))
	local plate = { x = stage.x + math.floor((stage.w - pw) / 2), y = stage.y, w = pw, h = ph }
	return {
		plate = plate,
		box = { x = stage.x, y = stage.y + pad, w = stage.w, h = ih },
		inner = { x = plate.x + pad, y = plate.y + pad, w = plate.w - 2 * pad, h = plate.h - 2 * pad },
		N = N,
		contentBottom = stage.y + pad + content,
		progress = shows and N.below and { x = plate.x, y = stage.y + pad + N.progressY, w = plate.w, h = progH } or nil, -- the line under the plate (idle)
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
