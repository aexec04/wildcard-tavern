--[[
	Shared/Engine/TableDress.lua
	The painted table furniture that is the same picture for every Card Set (draw pile book, wall banners, Patron seat faces) wears the
	set's colours through ImageColor3. Pure: Client/TableDress.lua applies it to the live instances.

	TableDress.PARTS            part -> { instance names }
	TableDress.partOf(name)     "deck" | "banner" | "seat" | nil
	TableDress.tintFor(setId, part) -> { r, g, b } 0..255 (classic and unknown sets: white, the art untouched)
]]
local CosmeticSets = require(script.Parent.CosmeticSets)

local TableDress = {}

TableDress.PARTS = {
	deck = { "DeckBook" },
	banner = { "WallBannerLeft", "WallBannerRight" },
	seat = { "SeatFacePicture" },
}
-- how far each part leans from white toward the set's card back colour (the painted purple needs a firm lean to read as another set)
TableDress.STRENGTH = { deck = 0.7, banner = 0.7, seat = 0.45 }

local byName = {}
for part, names in pairs(TableDress.PARTS) do
	for _, n in ipairs(names) do byName[n] = part end
end

function TableDress.partOf(name)
	return byName[name]
end

function TableDress.tintFor(setId, part)
	local tint = CosmeticSets.deckTint(setId)
	local k = TableDress.STRENGTH[part]
	if not tint or not k then return { 255, 255, 255 } end
	local out = {}
	for i = 1, 3 do
		out[i] = math.floor(255 + (tint.base[i] - 255) * k + 0.5)
	end
	return out
end

return TableDress
