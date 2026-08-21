--[[
	Themes.lua
	Purely cosmetic. Spend Tips (the same currency you earn from winning
	rounds -- no separate/real-money currency) to unlock and equip color
	palettes for the table and cards. No gameplay effect whatsoever --
	that's deliberate, so this can't accidentally become pay-to-win.

	Note: like the rest of the run state, owned/equipped themes reset when
	a run restarts (RunState.new) -- there's no save-across-sessions
	(DataStore) yet in this MVP. That's an easy thing to add later if you
	want purchases to persist for real.
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
