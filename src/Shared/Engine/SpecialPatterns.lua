--[[
	Shared/Engine/SpecialPatterns.lua
	ONE universal visual pattern per special card modifier (every Garnish, Special and Stamp), drawn the same way
	everywhere a card appears: the hand, the deck viewer, played cards, the pack pick screen and the shop
	(Client/CardFace.build draws it from this table, using UI shapes only, no art needed).

	Each pattern: { kind, label, glyph, color = {r,g,b}, edge = "border"|"steel"|"foil"|"none", rivets = bool,
	                corner = "tr"|"bl"|"br" }
	  * a corner stamp (a small round seal in the corner with the glyph) tells WHICH modifier it is at a glance;
	  * an edge treatment (a border, a steel border with rivets, or a foil sheen) tells the TYPE: garnishes get a
	    border, specials get a foil, stamps get the wax seal alone.
	patternsFor(card) -> list of patterns (garnish, then special, then stamp)
	tinted(color, accent) -> {r,g,b}   the colour mixed 20 percent toward the equipped Card Set's accent
	replacedCardFor(state, spec) lives in RunState; this file only describes how things look.
]]

local Card = require(script.Parent.Card)

local SpecialPatterns = {}

SpecialPatterns.Garnish = {
	sweet = { label = "Sweet", glyph = "S", color = { 240, 150, 190 }, edge = "border", corner = "tr" },
	zesty = { label = "Zesty", glyph = "Z", color = { 240, 200, 70 }, edge = "border", corner = "tr" },
	houseBlend = { label = "House Blend", glyph = "H", color = { 170, 120, 80 }, edge = "border", corner = "tr" },
	brittle = { label = "Brittle", glyph = "B", color = { 160, 220, 235 }, edge = "border", corner = "tr" },
	iron = { label = "Iron", glyph = "I", color = { 150, 160, 175 }, edge = "steel", rivets = true, corner = "tr" },
	houseToken = { label = "House Token", glyph = "T", color = { 205, 170, 95 }, edge = "border", corner = "tr" },
	golden = { label = "Golden", glyph = "G", color = { 235, 190, 70 }, edge = "border", corner = "tr" },
	lucky = { label = "Lucky", glyph = "L", color = { 110, 200, 110 }, edge = "border", corner = "tr" },
}

SpecialPatterns.Special = {
	silver = { label = "Silver", glyph = "Ag", color = { 205, 212, 225 }, edge = "foil", corner = "bl" },
	gold = { label = "Gold", glyph = "Au", color = { 240, 200, 80 }, edge = "foil", corner = "bl" },
	rainbow = { label = "Rainbow", glyph = "R", color = { 190, 130, 235 }, edge = "foil", corner = "bl" },
	reserved = { label = "Reserved", glyph = "R", color = { 120, 170, 230 }, edge = "foil", corner = "bl" },
}

SpecialPatterns.Stamp = {
	gold = { label = "Gold Stamp", glyph = "G", color = { 235, 190, 70 }, edge = "none", corner = "br" },
	encore = { label = "Encore Stamp", glyph = "E", color = { 235, 120, 90 }, edge = "none", corner = "br" },
	blue = { label = "Blue Stamp", glyph = "B", color = { 70, 110, 215 }, edge = "none", corner = "br" },
	purple = { label = "Purple Stamp", glyph = "P", color = { 150, 90, 205 }, edge = "none", corner = "br" },
}

local function add(list, kind, table_, id)
	local p = id and table_[id]
	if p then
		local copy = { kind = kind }
		for k, v in pairs(p) do copy[k] = v end
		list[#list + 1] = copy
	end
end

function SpecialPatterns.patternsFor(card)
	local out = {}
	if type(card) ~= "table" then return out end
	add(out, "garnish", SpecialPatterns.Garnish, card.garnish)
	add(out, "special", SpecialPatterns.Special, card.special)
	add(out, "stamp", SpecialPatterns.Stamp, card.stamp)
	return out
end

function SpecialPatterns.hasSpecial(card)
	return type(card) == "table" and (card.garnish ~= nil or card.special ~= nil or card.stamp ~= nil)
end

-- Missing patterns for any modifier id in Card (used by the test, so a new modifier cannot ship without one).
function SpecialPatterns.missing()
	local gaps = {}
	for id in pairs(Card.Garnishes) do if not SpecialPatterns.Garnish[id] then gaps[#gaps + 1] = "garnish:" .. id end end
	for id in pairs(Card.Specials) do if not SpecialPatterns.Special[id] then gaps[#gaps + 1] = "special:" .. id end end
	for id in pairs(Card.Stamps) do if not SpecialPatterns.Stamp[id] then gaps[#gaps + 1] = "stamp:" .. id end end
	table.sort(gaps)
	return gaps
end

-- Mix a pattern colour 20 percent toward the equipped Card Set's accent (nil accent = unchanged).
function SpecialPatterns.tinted(color, accent)
	if not accent then return { color[1], color[2], color[3] } end
	local out = {}
	for i = 1, 3 do out[i] = math.floor(color[i] + (accent[i] - color[i]) * 0.2 + 0.5) end
	return out
end

return SpecialPatterns
