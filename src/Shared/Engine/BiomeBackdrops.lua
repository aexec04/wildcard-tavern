--[[
	Shared/Engine/BiomeBackdrops.lua
	Data for the gameplay table backdrop of each biome (region). Used by Engine/TableStyle.

	Images: region id -> image id ("rbxassetid://<digits>"), nil until a painting exists. This is the generated
	        BiomeBackdropArt map (art category `biome_backdrops`, prompts in prompts.json
	        `biome_backdrop_subjects`); until ids are recorded the default painting (and the per-Night scene
	        art) shows with the colour grade below.
	Grades: region id -> { color = {r,g,b}, strength = 0..1 }: a flat colour wash laid over the picture
	        (a Frame with BackgroundTransparency = 1 - strength; never a UIGradient Transparency), so each
	        biome already looks different. None of them is red.
]]

local BiomeBackdrops = {}

BiomeBackdrops.Regions = { "meadow", "river", "peaks", "desert", "swamp", "snow", "coast", "tavern" } -- the 8 painted backdrops (the start "road" region only has a grade)
BiomeBackdrops.Default = "tavern"

-- Recorded ids come from the generated map (`record-image <region> <imageId> -c biome_backdrops`).
BiomeBackdrops.Images = require(script.Parent.BiomeBackdropArt)

BiomeBackdrops.Grades = {
	meadow = { color = { 190, 200, 90 }, strength = 0.16 }, -- warm green-gold
	river = { color = { 90, 150, 200 }, strength = 0.18 }, -- cool blue
	peaks = { color = { 130, 150, 175 }, strength = 0.18 }, -- grey-blue
	desert = { color = { 225, 170, 70 }, strength = 0.18 }, -- amber
	swamp = { color = { 90, 120, 60 }, strength = 0.20 }, -- murky green
	snow = { color = { 200, 225, 245 }, strength = 0.14 }, -- pale blue-white
	coast = { color = { 70, 170, 170 }, strength = 0.17 }, -- teal
	tavern = { color = { 150, 100, 60 }, strength = 0.14 }, -- warm brown
	road = { color = { 175, 145, 95 }, strength = 0.12 }, -- the Dusty Road start: dry dirt
}

return BiomeBackdrops
