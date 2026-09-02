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
		description = "Unlocks 5 table Themes at once -- Midnight Blue, Rose Gold, Forest Green, Crimson, and Neon Joker. Classic Felt stays free for everyone, always. (Golden Hour and Obsidian Ice below are sold separately, not part of this bundle.)",
		gamePassId = 0, -- TODO: paste the real Game Pass ID here once created (see the header comment above)
		grantsThemes = { "midnight_blue", "rose_gold", "forest", "crimson", "neon_joker" },
	},
	-- 2 NEW PREMIUM THEMES (requested fix: "the themes are way too simple,
	-- lets have a couple that they can buy with robux in the shop") -- each
	-- sold as its OWN individual Pass instead of folded into Theme Vault
	-- above, so someone who just wants one flashy Theme isn't forced to buy
	-- all 5 old ones to get it. Same placeholder-gamePassId setup as every
	-- other entry here: create each Pass for real on the Creator Dashboard,
	-- paste its ID in, done.
	{
		id = "theme_golden_hour",
		name = "Golden Hour Theme",
		icon = "🌇",
		description = "Unlocks the Golden Hour table Theme on its own -- warm sunset ambers and gold.",
		gamePassId = 0, -- TODO: paste the real Game Pass ID here once created (see the header comment above)
		grantsThemes = { "golden_hour" },
	},
	{
		id = "theme_obsidian_ice",
		name = "Obsidian Ice Theme",
		icon = "🧊",
		description = "Unlocks the Obsidian Ice table Theme on its own -- near-black with a sharp icy cyan glow.",
		gamePassId = 0, -- TODO: paste the real Game Pass ID here once created (see the header comment above)
		grantsThemes = { "obsidian_ice" },
	},
	-- Phase 9: the 2 QoL passes flagged alongside Theme Vault back in Phase 7,
	-- picked from the doc's own candidate list. Neither grants anything into
	-- RunState (no `grantsThemes`-style field, no server-side effect at all)
	-- -- ownership alone is the whole feature. `ownedGamePassIds` already
	-- ships to the client generically for every catalog entry (see
	-- Server/init.server.lua's serializeState), so both of these "just work"
	-- the instant a real Game Pass ID replaces the `0` placeholder below --
	-- nothing else in Server/init.server.lua needed to change for these two.
	{
		id = "fast_forward",
		name = "Fast Forward",
		icon = "⏩",
		description = "Speeds up the hand-scoring reveal sequence -- same numbers, same result, just quicker to sit through on a run you already know by heart.",
		gamePassId = 0, -- TODO: paste the real Game Pass ID here once created (see the header comment above)
	},
	{
		id = "custom_jukebox",
		name = "Custom Jukebox",
		icon = "🎵",
		description = "Paste your own background music track (a Roblox audio asset you own the rights to play) and it plays instead of the built-in soundtrack. Purely a convenience for you -- nothing else about the game changes.",
		gamePassId = 0, -- TODO: paste the real Game Pass ID here once created (see the header comment above)
	},
}

-- Generic "does this passId gate anything" lookup isn't needed the way
-- passForTheme is (fast_forward/custom_jukebox aren't associated with a
-- specific piece of content the way a Theme is) -- callers just check
-- `GamePasses.getById(passId)` directly against a live ownedGamePassIds
-- list shipped from the server. See Client/Settings.lua and
-- Client/ScorePopup.lua for the 2 new call sites.

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
