--[[
	Shared/Engine/GamePasses.lua
	Catalog of real-money Robux Game Passes. Every entry's `gamePassId`
	is a PLACEHOLDER (0) until the real Game Pass exists on the Roblox
	Creator Dashboard -- same "placeholder now, swap the real id in
	later" pattern Client/Sound.lua already uses for its music/SFX asset
	ids.

	HOW TO SET THIS UP (a one-time step on roblox.com, not in code): open
	your game's page on the Creator Dashboard -> Monetization -> Passes
	-> Create a Pass. Give it a name, icon, and price THERE -- that's
	where the real price and icon actually live, nothing in this file
	charges anyone anything or shows any art. Roblox hands back a numeric
	Game Pass ID once it's created -- paste that number into the matching
	entry's `gamePassId` field below and you're done; Server/init.server.lua
	and Client/Collection.lua both read this catalog, nothing else needs to
	change.

	Deliberately cosmetic/convenience only -- see design-doc.md's
	no-pay-to-win stance. Nothing a Game Pass unlocks changes target
	scores, hand sizes, Patron slots, or anything else that affects
	whether you WIN a run -- only how the game looks or feels while you
	play it.
]]

local GamePasses = {}

GamePasses.Definitions = {
	{
		id = "fast_forward",
		name = "Fast Forward",
		icon = "⏩",
		description = "Speeds up the hand-scoring reveal sequence -- same numbers, same result, just quicker to sit through on a run you already know by heart.",
		gamePassId = 0, -- TODO: paste the real Game Pass ID here once created (see the header comment above)
	},
	{
		id = "set_golden_gala",
		name = "Golden Gala Set",
		icon = "✨",
		description = "Unlocks the Golden Gala cosmetic set: a gold-trimmed card back and a dressed-up tavern backdrop. Looks only.",
		gamePassId = 0, -- TODO: paste the real Game Pass ID here once created
	},
}

--[[
	DEVELOPER PRODUCTS (consumables) -- deliberately NOT in Definitions
	above: a Game Pass is owned forever, a Developer Product is bought again
	and again and granted in MarketplaceService.ProcessReceipt
	(Server/init.server.lua). Engine/DeveloperProducts.lua has the lookups.

	`productId` is a PLACEHOLDER (0) until the product exists: Creator
	Dashboard -> your experience -> Monetization -> Developer Products ->
	Create. Set the name, icon and price there, then paste its numeric id
	below. While it's 0 the product can't be bought in the live game;
	Studio grants it free so it can be playtested.
]]
GamePasses.DeveloperProducts = {
	{
		-- ONE MORE ROUND: the run's single continue (RunState.canContinue).
		-- Each player also gets one free per day (PlayerProfile.
		-- hasFreeContinue), used before this paid one is offered.
		id = "continue",
		productId = 0, -- TODO: paste the real Developer Product ID here once created
		name = "One More Round",
		description = "Replay the round you lost from its start, with full Hands and Discards.",
	},
}

function GamePasses.getById(id)
	for _, pass in ipairs(GamePasses.Definitions) do
		if pass.id == id then
			return pass
		end
	end
	return nil
end

return GamePasses
