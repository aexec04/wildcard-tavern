--[[
	Shared/Engine/PatronCardSpec.lua
	One look for a Patron's name, rarity word and price wherever the Patron shows: the Draft (ChoicePanel), the Counter shop
	(ShopCards), My Patrons (PatronRow seats) and the pick screens. Surfaces read these numbers instead of keeping their own.
	Pure Lua, tested in EngineTests ("PatronCardSpec").

	PatronCardSpec.NAME        { min, max } text size range of the Patron name (the name shrinks inside the range, never below min)
	PatronCardSpec.RARITY_SIZE size of the rarity word
	PatronCardSpec.PRICE_SIZE  size of the price number
	PatronCardSpec.nameOf(id)  the one registry name of a Patron, or nil
	PatronCardSpec.rarityWord(id) "Common" .. "Mythical" (same word and colours as the Tome), or nil
	PatronCardSpec.priceText(n) whole number text of a Tips price ("1,200"), floored
]]

local Patrons = require(script.Parent.Patrons)
local ChoiceRarity = require(script.Parent.ChoiceRarity)

local M = {}

M.NAME = { min = 14, max = 16 }
M.RARITY_SIZE = 15
M.PRICE_SIZE = 18

function M.nameOf(id)
	local p = Patrons.getById(id)
	return p and p.name or nil
end

function M.rarityWord(id)
	local info = ChoiceRarity.info("patrons", id)
	return info and info.word or nil
end

function M.priceText(n)
	local v = math.floor(tonumber(n) or 0)
	local s = tostring(v)
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

return M
