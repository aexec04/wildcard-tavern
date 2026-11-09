--[[
	Shared/Engine/Bonds.lua
	Patron Bonds: any two owned Patrons that share a synergy tag (Engine/Synergy.lua, Patrons `tags`, never "flat")
	form a Bond. When BOTH bonded Patrons trigger on the same hand, each of them gets one small extra, once per hand:
	  * a Patron that gave Mult        -> 7 percent more of that Mult
	  * else one that gave x-Mult      -> 7 percent more of its x-Mult above 1
	  * else one that gave Chips       -> 7 percent more Chips
	  * else one that gave Tips        -> +1 Tip
	A Patron gets at most one bond bonus per hand however many bonds it is in, so scoring stays bounded.
	Each tag has a Bond name (shown on hover and in the Collection). Pure Lua, no Roblox APIs.

	Bonds.find(owned) -> { { tag, name, a = indexA, b = indexB, aId, bId }, ... }  (indices into `owned`)
]]

local Patrons = require(script.Parent.Patrons)

local Bonds = {}

Bonds.RATIO = 0.07 -- the extra is 7 percent of what the Patron itself gave this hand (Mult, x-Mult above 1, or Chips)
Bonds.TIP_EXTRA = 1 -- a Patron that gave Tips earns 1 more Tip

-- One Bond per tag, in display order. `rarity` feeds the Collection tab.
Bonds.Tags = { "pairs", "flush", "straight", "economy", "scaling", "rulebender", "ranks" }

Bonds.Definitions = {
	{ id = "pairs", name = "Twin Pact", icon = "\u{1F46F}", description = "Both bonded Patrons score on one hand: each earns a small bonus, once per hand.", flavorText = "Two pair-minded Patrons sit together.", rarity = "common" },
	{ id = "flush", name = "Tidal Pact", icon = "\u{1F30A}", description = "Both bonded Patrons score on one hand: each earns a small bonus, once per hand.", flavorText = "Two suit lovers share a table.", rarity = "common" },
	{ id = "straight", name = "Long Road Pact", icon = "\u{1F4CF}", description = "Both bonded Patrons score on one hand: each earns a small bonus, once per hand.", flavorText = "Two stair climbers walk side by side.", rarity = "common" },
	{ id = "economy", name = "Piggy Pact", icon = "\u{1FA99}", description = "Both bonded Patrons score on one hand: each earns a small bonus, once per hand.", flavorText = "Two penny savers swap tips.", rarity = "common" },
	{ id = "scaling", name = "Seedling Pact", icon = "\u{1F331}", description = "Both bonded Patrons score on one hand: each earns a small bonus, once per hand.", flavorText = "Two growing Patrons cheer each other on.", rarity = "common" },
	{ id = "rulebender", name = "Tinkerer Pact", icon = "\u{1F527}", description = "Both bonded Patrons score on one hand: each earns a small bonus, once per hand.", flavorText = "Two rule benchers trade tricks.", rarity = "common" },
	{ id = "ranks", name = "Crown Pact", icon = "\u{1F451}", description = "Both bonded Patrons score on one hand: each earns a small bonus, once per hand.", flavorText = "Two rank fans toast the faces.", rarity = "common" },
}

local byId = {}
for _, def in ipairs(Bonds.Definitions) do
	byId[def.id] = def
end

function Bonds.getById(id)
	return byId[id]
end

local function tagsOf(entry)
	local def = entry.tags and entry or Patrons.getById(entry.id)
	return (def and def.tags) or {}
end

-- Every Bond among the owned Patrons: each pair that shares a tag gets ONE bond (the first shared tag in
-- Bonds.Tags order), so the list is stable.
function Bonds.find(owned)
	local out = {}
	local tagSets = {}
	for i, entry in ipairs(owned or {}) do
		local set = {}
		for _, tag in ipairs(tagsOf(entry)) do
			set[tag] = true
		end
		tagSets[i] = set
	end
	for i = 1, #tagSets - 1 do
		for j = i + 1, #tagSets do
			for _, tag in ipairs(Bonds.Tags) do
				if tagSets[i][tag] and tagSets[j][tag] then
					out[#out + 1] = { tag = tag, name = byId[tag].name, a = i, b = j, aId = owned[i].id, bId = owned[j].id }
					break
				end
			end
		end
	end
	return out
end

-- The distinct Bond ids formed by the owned Patrons (for the Collection).
function Bonds.formedIds(owned)
	local seen, ids = {}, {}
	for _, bond in ipairs(Bonds.find(owned)) do
		if not seen[bond.tag] then
			seen[bond.tag] = true
			ids[#ids + 1] = bond.tag
		end
	end
	return ids
end

-- The bonds a given owned index is part of (for hover text).
function Bonds.forIndex(bonds, index)
	local out = {}
	for _, bond in ipairs(bonds) do
		if bond.a == index or bond.b == index then
			out[#out + 1] = bond
		end
	end
	return out
end

local function triggered(bonus)
	return bonus ~= nil and ((bonus.chips or 0) ~= 0 or (bonus.mult or 0) ~= 0 or (bonus.multMultiplier or 1) ~= 1 or (bonus.tips or 0) ~= 0)
end

-- Given each owned Patron's effect result this hand (`bonuses[i]`), returns { [index] = { kind, amount, bond } }:
-- the single bond extra each qualifying Patron earns. Both ends of a bond must have triggered.
function Bonds.extras(bonds, bonuses)
	local out = {}
	for _, bond in ipairs(bonds or {}) do
		if triggered(bonuses[bond.a]) and triggered(bonuses[bond.b]) then
			for _, index in ipairs({ bond.a, bond.b }) do
				if not out[index] then
					local own = bonuses[index]
					local kind
					if (own.mult or 0) ~= 0 then
						kind = "mult"
					elseif (own.multMultiplier or 1) ~= 1 then
						kind = "multMultiplier"
					elseif (own.chips or 0) ~= 0 then
						kind = "chips"
					else
						kind = "tips"
					end
					local amount
					if kind == "tips" then
						amount = Bonds.TIP_EXTRA
					elseif kind == "multMultiplier" then
						amount = (own.multMultiplier - 1) * Bonds.RATIO
					else
						amount = own[kind] * Bonds.RATIO
					end
					out[index] = { kind = kind, amount = math.floor(amount * 100 + 0.5) / 100, bond = bond }
				end
			end
		end
	end
	return out
end

return Bonds
