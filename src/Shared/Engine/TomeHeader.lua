--[[
	Shared/Engine/TomeHeader.lua
	The header treatment every Tome page shares (first landed on the Collection hub): the title and the info line each sit on a dark
	wood plate, the text has 16 px of inner padding on both sides, and nothing touches the panel border. Pure numbers, tested by a table
	that visits every page (Client/TomeHeaderPlate.lua draws the plates).

	M.PAGES                  { { id, title, sub, titleInk, subInk, tiles, drawn } } for Card Sets, Legend, Stats, Badges and the six
	                         Collection detail pages (the Collection hub draws its own bar, see CollectionRoomLayout)
	M.page(id)               the entry or nil
	M.layout(w, h, hasSub)   -> { title = rect, sub = rect or nil, bodyTop } in the panel's pixels; rects are { x, y, w, h }
	M.textRect(plate)        the plate's rect shrunk by PAD on both sides: where the label goes
	M.contrast(page)         lowest title or sub text contrast against the plate colour
]]

local M = {}

M.PAD = 16 -- inner padding of plate text, both sides
M.SIDE = 16 -- clear space between a plate and the panel border
M.PLATE = { 28, 18, 12 } -- dark wood
M.PLATE_ALPHA = 0.1 -- BackgroundTransparency of the plate (about 90 percent solid)
M.TITLE_H = 36
M.SUB_H = 28
M.GAP = 6 -- between the two plates
M.TOP = 8 -- the title plate's distance from the panel top
M.BODY_GAP = 8 -- under the last plate
M.MIN_TEXT = 15 -- smallest header text

local CREAM = { 250, 240, 220 }
local SOFT = { 226, 210, 176 }
local GOLD = { 255, 226, 140 }
local TAB_TILES = "uniform" -- every tile on the page shares one size (the page's own grid fixes it)

-- `drawn = "shared"`: Client/TomeHeaderPlate draws the plates. "badges": the Badges plaque pads its own labels (M.PAD). "collection": the
-- Collection hub bar and its section pages (CollectionRoomLayout.BAR_PAD, same 16 px). Flair has no title row (its tabs name the page).
M.PAGES = {
	{ id = "cosmeticSets", title = "Card Sets & Backs", sub = "Sets theme the table. Backs can be picked on their own. Looks only.", titleInk = CREAM, subInk = SOFT, tiles = TAB_TILES, drawn = "shared" },
	{ id = "legend", title = "Legend", sub = "", titleInk = GOLD, subInk = CREAM, tiles = TAB_TILES, drawn = "shared" },
	{ id = "stats", title = "Tavern Ledger", titleInk = GOLD, subInk = GOLD, tiles = TAB_TILES, drawn = "shared", follow = true },
	{ id = "badges", title = "Badges", sub = "x of 32 earned", titleInk = CREAM, subInk = SOFT, tiles = TAB_TILES, drawn = "badges" },
	{ id = "patrons", title = "Patrons", titleInk = CREAM, subInk = SOFT, tiles = TAB_TILES, drawn = "collection" },
	{ id = "recipes", title = "Recipes", titleInk = CREAM, subInk = SOFT, tiles = TAB_TILES, drawn = "collection" },
	{ id = "bosses", title = "Boss Rounds", titleInk = CREAM, subInk = SOFT, tiles = TAB_TILES, drawn = "collection" },
	{ id = "housePasses", title = "House Passes", titleInk = CREAM, subInk = SOFT, tiles = TAB_TILES, drawn = "collection" },
	{ id = "titles", title = "Titles", titleInk = CREAM, subInk = SOFT, tiles = TAB_TILES, drawn = "collection" },
	{ id = "bonds", title = "Bonds", titleInk = CREAM, subInk = SOFT, tiles = TAB_TILES, drawn = "collection" },
}

function M.page(id)
	for _, p in ipairs(M.PAGES) do
		if p.id == id then return p end
	end
	return nil
end

function M.layout(w, h, hasSub)
	local pw = math.max(0, w - 2 * M.SIDE)
	local title = { x = M.SIDE, y = M.TOP, w = pw, h = M.TITLE_H }
	local out = { title = title }
	local bottom = title.y + title.h
	if hasSub then
		out.sub = { x = M.SIDE, y = bottom + M.GAP, w = pw, h = M.SUB_H }
		bottom = out.sub.y + out.sub.h
	end
	out.bodyTop = bottom + M.BODY_GAP
	return out
end

function M.textRect(plate)
	return { x = plate.x + M.PAD, y = plate.y, w = math.max(0, plate.w - 2 * M.PAD), h = plate.h }
end

local function lum(c)
	local function f(v)
		v = v / 255
		return v <= 0.03928 and v / 12.92 or ((v + 0.055) / 1.055) ^ 2.4
	end
	return 0.2126 * f(c[1]) + 0.7152 * f(c[2]) + 0.0722 * f(c[3])
end

local function ratio(a, b)
	local la, lb = lum(a), lum(b)
	if la < lb then la, lb = lb, la end
	return (la + 0.05) / (lb + 0.05)
end

function M.contrast(page)
	return math.min(ratio(page.titleInk, M.PLATE), ratio(page.subInk, M.PLATE))
end

return M
