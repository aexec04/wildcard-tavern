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
			background = Color3.fromRGB(54, 42, 32),
			panelBg = Color3.fromRGB(74, 58, 44),
			accent = Color3.fromRGB(150, 105, 55),
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
			background = Color3.fromRGB(38, 42, 64),
			panelBg = Color3.fromRGB(56, 62, 92),
			accent = Color3.fromRGB(80, 105, 170),
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
			background = Color3.fromRGB(64, 42, 46),
			panelBg = Color3.fromRGB(90, 58, 64),
			accent = Color3.fromRGB(190, 120, 120),
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
			background = Color3.fromRGB(36, 54, 40),
			panelBg = Color3.fromRGB(54, 78, 58),
			accent = Color3.fromRGB(80, 130, 85),
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
			background = Color3.fromRGB(58, 26, 26),
			panelBg = Color3.fromRGB(84, 40, 40),
			accent = Color3.fromRGB(180, 60, 60),
			cardBase = Color3.fromRGB(250, 235, 235),
			cardSelected = Color3.fromRGB(255, 140, 140),
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
