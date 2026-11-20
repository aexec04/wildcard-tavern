--[[
	ClearTag: where the "TARGET CLEARED!" / "NEW BEST!" banner goes on the v2 table. It is a small tag in the Score plate's
	progress row (inside the carved border, 12 px side padding, 16 px text at most), never a wide banner over the numeral.
]]
local ClearTag = {}

ClearTag.MAX_SIZE = 16
ClearTag.MIN_SIZE = 14
ClearTag.SIDE = 12
ClearTag.CHAR_W = 0.72 -- GothamBlack capitals: width of a letter as a share of the text size

-- row = { x, y, w, h } of the plate's progress row (root pixels). Returns the tag rect and its text size.
function ClearTag.fit(row, text)
	local n = math.max(1, #text)
	local room = math.max(0, row.w - 2 * ClearTag.SIDE)
	local size = math.min(ClearTag.MAX_SIZE, math.floor(room / (n * ClearTag.CHAR_W)))
	local ok = size >= ClearTag.MIN_SIZE
	if not ok then size = ClearTag.MIN_SIZE end
	local w = math.min(room, math.ceil(n * ClearTag.CHAR_W * size) + 4)
	return { cx = row.x + row.w / 2, cy = row.y + row.h / 2, w = w, h = math.max(row.h, size + 4), size = size, fits = ok and w <= room }
end

return ClearTag
