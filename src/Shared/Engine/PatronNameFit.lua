-- Where a Patron's name sits on the plaque strip so the power disc never covers it.
--   inset(w)            -> right inset: the part of the disc that hangs over the strip, plus a gap
--   rect(w)             -> { x, w } of the name label inside a strip w wide
--   textWidth(name, s)  -> estimated pixel width of the name at size s (Gotham Medium, about 0.56 of the size per letter)
--   fits(name, w)       -> true when the name fits at MIN_SIZE inside rect(w)
local Style = require(script.Parent.PatronTierStyle)
local M = {}

M.MIN_SIZE, M.MAX_SIZE, M.GAP, M.CHAR = 11, 16, 4, 0.56
M.WRAP_SIZE = 10 -- a name too long for the strip at MIN_SIZE wraps to two lines at this size (the 800x450 seats)

function M.inset(w)
	local d = Style.discDiameter(w)
	local out = math.floor(d * Style.DISC_OVERLAP_X + 0.5)
	return d - out + M.GAP -- the disc shows 40 percent of its width over the strip
end

function M.rect(w)
	local inset = M.inset(w)
	return { x = 2, w = math.max(0, w - inset - 2) }
end

function M.textWidth(name, size)
	return #tostring(name or "") * size * M.CHAR
end

function M.fits(name, w)
	return M.textWidth(name, M.MIN_SIZE) <= M.rect(w).w
end

return M
