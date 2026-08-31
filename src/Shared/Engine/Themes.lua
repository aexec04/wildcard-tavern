--[[
	Themes.lua
	Purely cosmetic color palettes for the table and cards. No gameplay
	effect whatsoever -- that's deliberate, so this can't accidentally
	become pay-to-win.

	Two ways to unlock a Theme, both ending the same way -- an id landing
	in state.ownedThemes, which RunState.equipTheme checks:
	  - classic_felt (price 0) is always owned, free.
	  - GAME PASSES: the other 5 are gated behind the "Theme Vault" real-
	    money Robux Game Pass (see Shared/Engine/GamePasses.lua) instead
	    of a Tips price -- `price` is still set on each of them below for
	    display/back-compat, but Client/Themes.lua never shows a "Buy (N)"
	    button for a Theme GamePasses.passForTheme() returns non-nil for;
	    it shows "Get Pass" instead, and Server/init.server.lua grants
	    state.ownedThemes[id] = true automatically once MarketplaceService
	    confirms ownership (see applyGamePassGrants).

	Note: `equippedTheme` still resets to the free default every run (you
	re-equip your favorite each time, same as before) -- but as of
	PERSISTENT SAVE (Phase 10), OWNERSHIP no longer does. A Tips-bought
	Theme used to only last until the next "New Run.../restart, since
	`state.ownedThemes` was rebuilt from scratch by RunState.new every time
	-- now Server/init.server.lua passes this player's permanent
	PlayerProfile.ownedThemeIds into RunState.new(options.ownedThemeIds),
	so a bought Theme stays bought forever, same as it always felt like it
	should. Game Pass ownership was never affected by the old gap in the
	first place (Roblox remembers a Game Pass forever, independent of any
	one run) -- Server/init.server.lua re-grants gamepass-owned Themes to
	state.ownedThemes every time a fresh RunState is built, same as before.
]]

local Themes = {}

Themes.DefaultThemeId = "classic_felt"

Themes.Definitions = {
	{
		id = "classic_felt",
		name = "Classic Felt",
		description = "The default look. Always owned, free.",
		price = 0,
		colors = {
			background = Color3.fromRGB(24, 18, 14),
			panelBg = Color3.fromRGB(40, 30, 22),
			accent = Color3.fromRGB(90, 60, 30),
			cardBase = Color3.fromRGB(250, 245, 235),
			cardSelected = Color3.fromRGB(255, 214, 130),
		},
	},
	{
		id = "midnight_blue",
		name = "Midnight Blue",
		description = "Cool, late-night blues.",
		price = 8,
		colors = {
			background = Color3.fromRGB(14, 16, 26),
			panelBg = Color3.fromRGB(24, 28, 46),
			accent = Color3.fromRGB(50, 70, 120),
			cardBase = Color3.fromRGB(235, 240, 250),
			cardSelected = Color3.fromRGB(140, 170, 255),
		},
	},
	{
		id = "rose_gold",
		name = "Rose Gold",
		description = "Warm pinks and gold accents.",
		price = 10,
		colors = {
			background = Color3.fromRGB(30, 18, 20),
			panelBg = Color3.fromRGB(52, 30, 34),
			accent = Color3.fromRGB(150, 90, 90),
			cardBase = Color3.fromRGB(255, 240, 240),
			cardSelected = Color3.fromRGB(255, 180, 190),
		},
	},
	{
		id = "forest",
		name = "Forest Green",
		description = "Deep greens, like a back-room card table.",
		price = 8,
		colors = {
			background = Color3.fromRGB(14, 22, 16),
			panelBg = Color3.fromRGB(24, 38, 26),
			accent = Color3.fromRGB(50, 90, 55),
			cardBase = Color3.fromRGB(240, 250, 240),
			cardSelected = Color3.fromRGB(150, 220, 150),
		},
	},
	{
		id = "crimson",
		name = "Crimson",
		description = "Bold reds and blacks.",
		price = 12,
		colors = {
			background = Color3.fromRGB(26, 10, 10),
			panelBg = Color3.fromRGB(46, 18, 18),
			accent = Color3.fromRGB(140, 40, 40),
			cardBase = Color3.fromRGB(250, 235, 235),
			cardSelected = Color3.fromRGB(255, 140, 140),
		},
	},
	{
		id = "neon_joker",
		name = "Neon Joker",
		-- Re-sampled straight from the actual thumbnail/poster art (the
		-- tavern interior + the Joker card's magic glow), not just a
		-- guessed "gold and violet" -- the poster's base is dark WOOD
		-- brown with warm candlelight, not a straight purple wash; the
		-- violet only shows up as the Joker's glow/smoke, which is what
		-- `cardSelected` (the "lit up" state) represents here.
		description = "Warm tavern wood and candlelight, with the Joker card's violet glow -- straight off the game's own poster art.",
		price = 15,
		colors = {
			background = Color3.fromRGB(22, 14, 18),
			panelBg = Color3.fromRGB(46, 28, 40),
			accent = Color3.fromRGB(230, 175, 68),
			cardBase = Color3.fromRGB(250, 238, 220),
			cardSelected = Color3.fromRGB(205, 85, 245),
		},
	},
}

function Themes.getById(id)
	for _, theme in ipairs(Themes.Definitions) do
		if theme.id == id then
			return theme
		end
	end
	return nil
end

return Themes
