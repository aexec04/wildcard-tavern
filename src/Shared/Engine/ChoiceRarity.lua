--[[
	Shared/Engine/ChoiceRarity.lua
	Rarity for the option cards of the pick screens (the start-of-run Patron draft, Pick 1 of N pack picks), so a player can judge a pick.
	The same tiers and colours as the Shop and the Tome (CollectionBook.Rarities). An item with no rarity gets nothing: lookup returns nil
	for an id that is not in its tab, never "Common" by mistake. Pure Lua, tested in EngineTests ("ChoiceRarity").

	ChoiceRarity.tabFor(kind)          Collection tab for a choice kind or pack item category (nil when it has no rarity)
	ChoiceRarity.lookup(tab, id)       the rarity id, or nil when the item is unknown
	ChoiceRarity.info(tab, id)         { rarity, word, color, rim, plate, text, glow } or nil
	    word   "Common" .. "Mythical"; color the tier colour; rim the muted rim colour; plate the very dark name-plate fill
	    text   the colour of the word on the plate (at least 4.5:1); glow the soft-glow peak for Rare and above (nil below)
]]

local CollectionBook = require(script.Parent.CollectionBook)
local SectionLayout = require(script.Parent.CollectionSectionLayout)

local ChoiceRarity = {}

ChoiceRarity.TABS = {
	patron = "patrons", rushPatron = "patrons", reward = "patrons", draft = "patrons",
	house = "recipes", menu = "recipes", secret = "recipes", recipe = "recipes",
	housePass = "housePasses",
}

function ChoiceRarity.tabFor(kind)
	return kind and ChoiceRarity.TABS[kind] or nil
end

function ChoiceRarity.lookup(tab, id)
	if type(tab) ~= "string" or type(id) ~= "string" then return nil end
	for _, item in ipairs(CollectionBook.itemsFor(tab)) do
		if item.id == id then return CollectionBook.rarityOf(item) end
	end
	return nil
end

local DARK = { 12, 8, 6 }
local RIM_DARK = { 60, 44, 28 }

local function lerp(a, b, t)
	return { math.floor(a[1] + (b[1] - a[1]) * t + 0.5), math.floor(a[2] + (b[2] - a[2]) * t + 0.5), math.floor(a[3] + (b[3] - a[3]) * t + 0.5) }
end

-- The look of one tier (no item lookup): the tier colour, a muted rim, the very dark name plate and the word colour on it.
function ChoiceRarity.styleOf(rarity)
	local def = rarity and CollectionBook.Rarities[rarity]
	if not def then return nil end
	local c = def.color
	local common = rarity == "common"
	return {
		rarity = rarity,
		word = def.name,
		color = { c[1], c[2], c[3] },
		rim = lerp(c, RIM_DARK, 0.1), -- muted: low contrast against the card
		plate = common and { 44, 32, 22 } or lerp(c, DARK, 0.78), -- very dark, tinted from Uncommon up
		-- Common stays quiet cream; the rest wear their tier colour, lightened a little so every tier reads at 4.5:1 on its plate
		text = common and { 220, 210, 190 } or lerp(c, { 255, 255, 255 }, 0.3),
		glow = SectionLayout.glowPeak(rarity),
	}
end

function ChoiceRarity.info(tab, id)
	return ChoiceRarity.styleOf(ChoiceRarity.lookup(tab, id))
end

return ChoiceRarity
