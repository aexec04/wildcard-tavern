--[[
	Packs.lua
	Our Booster Pack equivalent. Buying a pack from the shop reveals several
	random items from ONE category (Patrons, or one of the 3 Recipe types)
	and lets you keep a smaller number of them for free -- see
	RunState.openPack/RunState.resolvePack.

	This is what Recipes are sold through now -- there's no longer a "browse
	the whole catalog, buy exactly what you want" tab (that undercut the
	whole point of packs being a random, exciting reveal, and doesn't match
	the reference game). RunState.buyHouseRecipe/buyMenuRecipe/
	buySecretRecipe still exist for direct engine use/testing, they're just
	not wired to a client Buy button anymore.

	v1 ships ONE size per category (reveal 3, keep 1) -- Jumbo/Mega sizes
	(reveal more, keep more) are a natural follow-up once this base loop is
	proven fun, not built this pass.
]]

local Packs = {}

Packs.Definitions = {
	{
		id = "buffoon_pack", name = "Buffoon Pack", icon = "🃏", price = 6,
		category = "patron", revealCount = 3, pickCount = 1,
		description = "Reveals 3 random Patrons -- pick 1 to join your table for free.",
	},
	{
		id = "house_pack", name = "House Recipe Pack", icon = "🍹", price = 5,
		category = "house", revealCount = 3, pickCount = 1,
		description = "Reveals 3 random House Recipes -- pick 1 to keep for free.",
	},
	{
		id = "menu_pack", name = "Menu Recipe Pack", icon = "📖", price = 5,
		category = "menu", revealCount = 3, pickCount = 1,
		description = "Reveals 3 random Menu Recipes -- pick 1 to keep for free.",
	},
	{
		id = "secret_pack", name = "Secret Recipe Pack", icon = "🎭", price = 7,
		category = "secret", revealCount = 3, pickCount = 1,
		description = "Reveals 3 random Secret Recipes -- pick 1 to keep for free.",
	},
}

function Packs.getById(id)
	for _, pack in ipairs(Packs.Definitions) do
		if pack.id == id then
			return pack
		end
	end
	return nil
end

return Packs
