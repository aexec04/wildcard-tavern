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
	and Client/Themes.lua both read this catalog, nothing else needs to
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
		id = "all_themes",
		name = "Theme Vault",
		icon = "🎨",
		description = "Unlocks every table Theme at once -- Midnight Blue, Rose Gold, Forest Green, Crimson, and Neon Joker. Classic Felt stays free for everyone, always.",
		gamePassId = 0, -- TODO: paste the real Game Pass ID here once created (see the header comment above)
		grantsThemes = { "midnight_blue", "rose_gold", "forest", "crimson", "neon_joker" },
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

-- themeId -> the GamePasses entry that gates it, or nil if that theme
-- isn't gamepass-gated at all (the free default, classic_felt, or any
-- future Tips-priced theme you decide not to paywall).
function GamePasses.passForTheme(themeId)
	for _, pass in ipairs(GamePasses.Definitions) do
		if pass.grantsThemes then
			for _, grantedId in ipairs(pass.grantsThemes) do
				if grantedId == themeId then
					return pass
				end
			end
		end
	end
	return nil
end

return GamePasses
