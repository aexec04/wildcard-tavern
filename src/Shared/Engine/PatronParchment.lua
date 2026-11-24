--[[
	Engine/PatronParchment.lua
	Gameplay v2 Patron seats: a cream parchment card, not the cut card's wood frame. The seat shows only the portrait window of
	the cut card (`PatronCardCrop`, measured per card by tools/patron_card_crops.py) on cream paper with a gold edge, the Patron's
	name on a cream ribbon under it (code text, so the baked name plate is cropped away), the tier ring and the gold power disc
	drawn by Client/PatronTierFX over it. Rarity stays in the ring colour and the corner letter, never colour alone.

	layout()          -> { portrait = {x,y,w,h}, ribbon = {x,y,w,h} } as fractions (0..1) of the seat
	imageRect(id)     -> { x, y, w, h } pixels of the portrait window in the cut card picture, nil when the card has no crop
	storedRect(id)    -> the same window in stored texture pixels (2/3 of the source), what ImageRectOffset and ImageRectSize take
	nameRect(w)       -> { x, w } of the name text inside the ribbon for a seat w px wide (clear of the power disc)
	contrast()        -> contrast ratio of the ink on the ribbon paper (tested at 4.5 or more)
]]

local Crop = require(script.Parent.PatronCardCrop)
local NameFit = require(script.Parent.PatronNameFit)

local M = {}

M.PAPER = { 240, 226, 196 }
M.RIBBON = { 232, 214, 172 }
M.INK = { 58, 38, 20 }
M.EDGE = { 205, 160, 70 } -- thin gold edge on the paper

-- reference seat: the portrait runs to the card bottom inside a thin cream border and the name ribbon (17 percent of the card) overlaps its bottom
M.SIDE, M.TOP, M.RIBBON_H, M.PORTRAIT_H, M.OVERLAP = 0.04, 0.03, 0.17, 0.93, 0.16

M.TWO_LINE_H = 22 -- two 10 px lines (line height 0.9) plus 2 px each side
M.NAME_FILL, M.NAME_MAX, M.TWO_LINE_AT = 0.66, 26, 11 -- name size is 0.66 of the ribbon height (the concept's ~20 px at 1672x941, 20 percent over the first 0.55 pass); names over 11 characters take two lines

-- slotH (px), wrapped (a name too long for one line) and size (the row's name size): a seat's 17 percent ribbon is too short for two
-- lines, so it grows upward to fit them, its bottom edge unchanged
function M.layout(slotH, wrapped, size)
	local rh = M.RIBBON_H
	if wrapped and slotH and slotH > 0 then
		local need = size and math.ceil(2 * size * 0.9) + 4 or M.TWO_LINE_H
		need = math.max(M.TWO_LINE_H, need)
		if slotH * rh < need then rh = need / slotH end
	end
	local bottom = M.TOP + M.PORTRAIT_H - M.OVERLAP + M.RIBBON_H
	return {
		portrait = { x = M.SIDE, y = M.TOP, w = 1 - 2 * M.SIDE, h = M.PORTRAIT_H },
		ribbon = { x = M.SIDE, y = bottom - rh, w = 1 - 2 * M.SIDE, h = rh },
	}
end

-- true when the name needs two lines in a seat w px wide (it does not fit on one line at the smallest size)
function M.wraps(name, w)
	local r = M.nameRect(w)
	return NameFit.textWidth(name, NameFit.MIN_SIZE) > math.max(0, r.w - 4)
end

M.WRAP_MIN = 12 -- never smaller than 12 px, even at 800x450; a word still too long is cut with an ellipsis (TextTruncate) rather than shrunk or drawn over the coin
M.COIN_GAP = 6 -- px kept clear between the end of a name and the power coin
M.CHAR_W = 0.62 -- Merriweather is wider than the engine's 0.56 estimate; sizes and label fits use this

-- left edge of the power coin in ribbon coordinates (the label's parent) for a seat w px wide: the coin sits on the seat's bottom
-- right corner, half of it hanging outside, and the ribbon starts SIDE of the seat in
function M.coinLeft(w)
	local Style = require(script.Parent.PatronTierStyle)
	local d = Style.discDiameter(w)
	local outX = math.floor(d * Style.DISC_OVERLAP_X + 0.5)
	return w - d + outX - M.SIDE * w
end
M.NAME_PAD = 4 -- px kept clear on each side of the name so no letter touches the ribbon edge

-- One name style for the whole row of seats (names = every Patron name shown, w = seat width, h = seat height, px).
-- size: the largest size at which the longest name fits one line (11 to 16 px), the same for every seat; when even 11 px does not
-- fit, every seat uses the 10 px wrapped style instead (wrapped = true, two lines in the taller ribbon, no ellipsis).
-- The label rect for the style: the one line style keeps clear of the power disc; the two line style (the 800x450 seats, where the
-- disc leaves only about 30 px) spans the whole ribbon so its words fit, the disc sitting over the lower line's empty right end.
function M.labelRect(w, wrapped)
	local x = wrapped and 1 or (M.nameRect(w).x + M.NAME_PAD)
	return { x = x, w = math.max(0, M.coinLeft(w) - M.COIN_GAP - x) }
end

function M.rowStyle(names, w, h)
	local avail = M.labelRect(w, false).w
	local CW = M.CHAR_W
	local longest = 0
	for _, n in ipairs(names or {}) do longest = math.max(longest, #tostring(n or "")) end
	if longest == 0 then return { size = NameFit.MAX_SIZE, wrapped = false } end
	local want = M.NAME_MAX -- about 0.55 of the ribbon height, one size for every seat
	if h and h > 0 then want = math.max(NameFit.WRAP_SIZE, math.min(M.NAME_MAX, math.floor(h * M.RIBBON_H * M.NAME_FILL))) end
	local fit = math.floor(avail / (longest * CW))
	if longest <= M.TWO_LINE_AT and fit >= NameFit.MIN_SIZE then return { size = math.max(NameFit.MIN_SIZE, math.min(fit, want)), wrapped = false } end
	-- wrapped: two lines at the fill size; 9 px for the rare name with a word too long for the seat (only the 800x450 seats get here)
	local w2 = M.labelRect(w, true).w
	local word = 0
	for _, n in ipairs(names) do for x in tostring(n):gmatch("%S+") do word = math.max(word, #x) end end
	local sz = math.floor(w2 / (math.max(1, word) * CW))
	return { size = math.max(M.WRAP_MIN, math.min(want, sz)), wrapped = true }
end

function M.imageRect(id)
	return Crop[tostring(id or "")]
end

-- The window in STORED texture pixels. Roblox keeps an upload at most 1024 px on its long side, so the 1024 x 1536 cut card is a
-- 683 x 1024 texture and ImageRectOffset/Size must be scaled by 2/3 (Engine/ImageSpace), or the window lands low and shows the baked name.
M.SOURCE_W, M.SOURCE_H = 1024, 1536
function M.storedRect(id)
	local r = Crop[tostring(id or "")]
	if not r then return nil end
	local ImageSpace = require(script.Parent.ImageSpace)
	local x, y, w, h = ImageSpace.rect(r.x, r.y, r.w, r.h, M.SOURCE_W, M.SOURCE_H)
	return { x = x, y = y, w = w, h = h }
end

function M.nameRect(w)
	local r = NameFit.rect(math.max(0, (tonumber(w) or 0) * (1 - 2 * M.SIDE)))
	return { x = r.x, w = r.w }
end

local function lum(c)
	local function ch(v)
		v = v / 255
		return v <= 0.03928 and v / 12.92 or ((v + 0.055) / 1.055) ^ 2.4
	end
	return 0.2126 * ch(c[1]) + 0.7152 * ch(c[2]) + 0.0722 * ch(c[3])
end

function M.contrast()
	local a, b = lum(M.RIBBON), lum(M.INK)
	if a < b then a, b = b, a end
	return (a + 0.05) / (b + 0.05)
end

return M
