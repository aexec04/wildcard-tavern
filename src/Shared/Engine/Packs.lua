--[[
	Packs.lua
	Our Booster Pack equivalent. Buying a pack from the shop reveals several
	random items from ONE category (Patrons, one of the 3 Recipe types, or --
	as of Phase 2 -- actual playing cards with a modifier already on them)
	and lets you keep a smaller number of them for free -- see
	RunState.openPack/RunState.resolvePack.

	This is what Recipes are sold through now -- there's no longer a "browse
	the whole catalog, buy exactly what you want" tab (that undercut the
	whole point of packs being a random, exciting reveal, and doesn't match
	the reference game). RunState.buyHouseRecipe/buyMenuRecipe/
	buySecretRecipe still exist for direct engine use/testing, they're just
	not wired to a client Buy button anymore.

	PHASE 2: v1 only shipped ONE size per category (reveal 3, keep 1) --
	Jumbo (reveal 5, keep 1) and Mega (reveal 5, keep 2) sizes are added
	below for every category, plus a new "standard" category (playing cards
	with a Garnish/Special/Stamp already applied, matching the reference
	game's Standard Pack -- previously those modifiers were ONLY obtainable
	via House Recipes). `size` is informational (normal/jumbo/mega) --
	RunState.openPack/resolvePack only actually care about revealCount/
	pickCount/category, `size` is just there for anything that wants to
	group/label packs by size later.
]]

local Packs = {}

Packs.Definitions = {
	-- ===== Normal (reveal 3, pick 1) =====
	{
		id = "buffoon_pack", name = "Patron Pack", icon = "🃏", price = 6,
		category = "patron", size = "normal", revealCount = 3, pickCount = 1,
		description = "Reveals 3 random Patrons, pick 1 to join your table for free.",
	},
	{
		id = "house_pack", name = "House Recipe Pack", icon = "🧃", price = 4,
		category = "house", size = "normal", revealCount = 3, pickCount = 1,
		description = "Reveals 3 random House Recipes, pick 1 to keep for free.",
	},
	{
		id = "menu_pack", name = "Menu Recipe Pack", icon = "📖", price = 4,
		category = "menu", size = "normal", revealCount = 3, pickCount = 1,
		description = "Reveals 3 random Menu Recipes, pick 1 to keep for free.",
	},
	{
		id = "secret_pack", name = "Secret Recipe Pack", icon = "🎭", price = 7,
		category = "secret", size = "normal", revealCount = 3, pickCount = 1,
		description = "Reveals 3 random Secret Recipes, pick 1 to keep for free.",
	},
	{
		id = "standard_pack", name = "Standard Pack", icon = "🎴", price = 4,
		category = "standard", size = "normal", revealCount = 3, pickCount = 1,
		description = "Reveals 3 random dressed playing cards, pick 1 to add to your deck for free.",
		short = "Pick 1 of 3 dressed cards for your deck",
	},

	-- ===== Jumbo (reveal 5, pick 1 -- better odds at the item you want) =====
	{
		id = "buffoon_pack_jumbo", name = "Jumbo Patron Pack", icon = "🃏", price = 9,
		category = "patron", size = "jumbo", revealCount = 5, pickCount = 1,
		description = "JUMBO: Reveals 5 random Patrons, pick 1 to join your table for free.",
	},
	{
		id = "house_pack_jumbo", name = "Jumbo House Recipe Pack", icon = "🧃", price = 8,
		category = "house", size = "jumbo", revealCount = 5, pickCount = 1,
		description = "JUMBO: Reveals 5 random House Recipes, pick 1 to keep for free.",
	},
	{
		id = "menu_pack_jumbo", name = "Jumbo Menu Recipe Pack", icon = "📖", price = 8,
		category = "menu", size = "jumbo", revealCount = 5, pickCount = 1,
		description = "JUMBO: Reveals 5 random Menu Recipes, pick 1 to keep for free.",
	},
	{
		id = "secret_pack_jumbo", name = "Jumbo Secret Recipe Pack", icon = "🎭", price = 10,
		category = "secret", size = "jumbo", revealCount = 5, pickCount = 1,
		description = "JUMBO: Reveals 5 random Secret Recipes, pick 1 to keep for free.",
	},
	{
		id = "standard_pack_jumbo", name = "Jumbo Standard Pack", icon = "🎴", price = 8,
		category = "standard", size = "jumbo", revealCount = 5, pickCount = 1,
		description = "JUMBO: Reveals 5 random dressed playing cards, pick 1 to add to your deck for free.",
		short = "Pick 1 of 5 dressed cards for your deck",
	},

	-- ===== Mega (reveal 5, pick 2 -- two keepers from one pack) =====
	{
		id = "buffoon_pack_mega", name = "Mega Patron Pack", icon = "🃏", price = 12,
		category = "patron", size = "mega", revealCount = 5, pickCount = 2,
		description = "MEGA: Reveals 5 random Patrons, pick 2 to join your table for free.",
	},
	{
		id = "house_pack_mega", name = "Mega House Recipe Pack", icon = "🧃", price = 11,
		category = "house", size = "mega", revealCount = 5, pickCount = 2,
		description = "MEGA: Reveals 5 random House Recipes, pick 2 to keep for free.",
	},
	{
		id = "menu_pack_mega", name = "Mega Menu Recipe Pack", icon = "📖", price = 11,
		category = "menu", size = "mega", revealCount = 5, pickCount = 2,
		description = "MEGA: Reveals 5 random Menu Recipes, pick 2 to keep for free.",
	},
	{
		id = "secret_pack_mega", name = "Mega Secret Recipe Pack", icon = "🎭", price = 13,
		category = "secret", size = "mega", revealCount = 5, pickCount = 2,
		description = "MEGA: Reveals 5 random Secret Recipes, pick 2 to keep for free.",
	},
	{
		id = "standard_pack_mega", name = "Mega Standard Pack", icon = "🎴", price = 11,
		category = "standard", size = "mega", revealCount = 5, pickCount = 2,
		description = "MEGA: Reveals 5 random dressed playing cards, pick 2 to add to your deck for free.",
		short = "Pick 2 of 5 dressed cards for your deck",
	},

	-- ===== Mixed / Grab Bag (each revealed item independently rolls its own
	-- category -- Patron, House/Menu/Secret Recipe, or Standard card) =====
	{
		id = "mixed_pack", name = "Grab Bag Pack", icon = "🎁", price = 7,
		category = "mixed", size = "normal", revealCount = 3, pickCount = 1,
		description = "Reveals 3 random items (Patron, Recipe or card), pick 1 to keep for free.",
	},
	{
		id = "mixed_pack_jumbo", name = "Jumbo Grab Bag Pack", icon = "🎁", price = 10,
		category = "mixed", size = "jumbo", revealCount = 5, pickCount = 1,
		description = "JUMBO: Reveals 5 random items (Patron, Recipe or card), pick 1 to keep for free.",
	},
	{
		id = "mixed_pack_mega", name = "Mega Grab Bag Pack", icon = "🎁", price = 13,
		category = "mixed", size = "mega", revealCount = 5, pickCount = 2,
		description = "MEGA: Reveals 5 random items (Patron, Recipe or card), pick 2 to keep for free.",
	},
}

-- Skipping a pack you bought gives about half of what you paid back (after discounts): half rounded down, at least 1 when you paid 2 or more,
-- nothing for a free pack. Server side only (RunState.resolvePack); the client only shows the number on the Skip Pack button.
function Packs.skipRefund(paidPrice)
	local paid = math.floor(tonumber(paidPrice) or 0)
	if paid < 2 then return 0 end
	return math.max(1, math.floor(paid / 2))
end

-- The name on a pack's small shelf card. The card's badge already says JUMBO or MEGA and its plate holds two short
-- words, so the size word is left off and, from a name of three words or more, the closing "Pack" too. The full name
-- stays in the tooltip and on the pack screen. ("Jumbo Secret Recipe Pack" was cut after "Jumbo Secret".)
function Packs.shelfName(name)
	local short = tostring(name or "")
	short = short:gsub("^Jumbo ", "")
	short = short:gsub("^Mega ", "")
	local words = 0
	for _ in short:gmatch("%S+") do words = words + 1 end
	if words > 2 then short = short:gsub(" Pack$", "") end
	return short
end

function Packs.getById(id)
	for _, pack in ipairs(Packs.Definitions) do
		if pack.id == id then
			return pack
		end
	end
	return nil
end

return Packs
