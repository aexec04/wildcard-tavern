-- Pure text fit estimates for plates and banners (no TextService in tests): about CHAR em per glyph, a line is size + 2 tall.
--   width(text, size)                       -> estimated pixel width on one line
--   lines(text, size, w)                    -> lines needed inside w
--   clip(text, w, size)                     -> text, or a shortened start ending in "..." that fits one line
--   bestSize(text, w, h, minSize, maxSize)  -> the largest size in [minSize, maxSize] whose lines fit w by h, or nil
local M = {}

M.CHAR = 0.56
M.SIDE = 12 -- clear space kept at each side of a plate

function M.width(text, size)
	return #tostring(text or "") * size * M.CHAR
end

function M.lines(text, size, w)
	if w <= 0 then return math.huge end
	return math.max(1, math.ceil(M.width(text, size) / w))
end

function M.bestSize(text, w, h, minSize, maxSize)
	for s = maxSize, minSize, -1 do
		if M.lines(text, s, w) * (s + 2) <= h then return s end
	end
	return nil
end

-- The text itself when one line fits w at `size`, else the longest start of it plus "..." that does.
function M.clip(text, w, size)
	text = tostring(text or "")
	if M.width(text, size) <= w then return text end
	local keep = math.max(1, math.floor(w / (size * M.CHAR)) - 3)
	return text:sub(1, keep):gsub("%s+$", "") .. "..."
end

return M
