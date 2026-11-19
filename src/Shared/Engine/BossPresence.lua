--[[
	Shared/Engine/BossPresence.lua
	Pure numbers (tested) for the Boss Round presentation on the Concept T play screen. Client/BossPresenceFX plays them.

	  BossPresence.plate(w, h, layoutRects, patronsRect) -> { x, y, w, h, textSize }   the red name and rule plate, in the
	      band between the Round banner and the Patron row, so it never covers either
	  BossPresence.line(boss) -> "Name: rule" in plain words on one line (first sentence of the rule)
	  BossPresence.slide(calm) -> nil | { dur, rise }   plate slides in from above over 0.4 s
	  BossPresence.pulse(t, calm) -> nil | alpha   red edge vignette alpha at time t, 0.12 to 0.2 on a 3 s sine
	  BossPresence.crownText(roundText, isBoss) -> the Round title with a crown mark on a Boss Round
	  BossPresence.fanfare(calm, fast) -> nil | { big, pieces }   the stronger clear: the large confetti burst
]]

local M = {}

M.SLIDE_SECONDS = 0.4
M.PULSE_SECONDS = 3
M.PULSE_MIN = 0.12
M.PULSE_MAX = 0.20
M.CROWN = "\u{265B}" -- a plain chess queen glyph, in the text so it reads without colour
M.MIN_TEXT = 15
M.MAX_LINE = 80

function M.plate(w, h, rects, patrons)
	local round = rects.round
	local top = round.y + round.h + 2
	local bottom = patrons.y - 2
	local ph = math.max(0, bottom - top)
	local pw = math.min(math.floor(w * 0.42), 620)
	local x = math.floor((w - pw) / 2)
	local textSize = math.max(M.MIN_TEXT, math.min(20, ph - 8))
	return { x = x, y = top, w = pw, h = ph, textSize = textSize }
end

function M.line(boss)
	if type(boss) ~= "table" then return "" end
	local name = tostring(boss.name or "")
	local rule = tostring(boss.description or "")
	local first = rule:match("^(.-[%.!])%s") or rule
	first = first:gsub("%.$", "")
	local s = name ~= "" and (name .. ": " .. first) or first
	if #s > M.MAX_LINE then s = s:sub(1, M.MAX_LINE - 3) .. "..." end
	return s
end

function M.slide(calm)
	if calm then return nil end
	return { dur = M.SLIDE_SECONDS, rise = 40 }
end

function M.pulse(t, calm)
	if calm then return nil end
	local mid = (M.PULSE_MIN + M.PULSE_MAX) / 2
	local amp = (M.PULSE_MAX - M.PULSE_MIN) / 2
	return mid + amp * math.sin(2 * math.pi * (tonumber(t) or 0) / M.PULSE_SECONDS)
end

function M.crownText(text, isBoss)
	if isBoss then return M.CROWN .. " " .. tostring(text) end
	return tostring(text)
end

function M.fanfare(calm, fast)
	if calm then return nil end
	return { big = true, pieces = require(script.Parent.Confetti).count(false, fast, true) }
end

return M
