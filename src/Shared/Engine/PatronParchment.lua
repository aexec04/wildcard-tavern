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

-- reference seat: the portrait fills about 80 percent of the card and the name ribbon overlaps the portrait's bottom
M.SIDE, M.TOP, M.RIBBON_H, M.PORTRAIT_H, M.OVERLAP = 0.05, 0.04, 0.17, 0.80, 0.07

function M.layout()
	return {
		portrait = { x = M.SIDE, y = M.TOP, w = 1 - 2 * M.SIDE, h = M.PORTRAIT_H },
		ribbon = { x = M.SIDE, y = M.TOP + M.PORTRAIT_H - M.OVERLAP, w = 1 - 2 * M.SIDE, h = M.RIBBON_H },
	}
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
