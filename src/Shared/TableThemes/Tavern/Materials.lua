--[[
	TableThemes/Tavern/Materials.lua
	The palette of the Tavern table: every surface in the scene names one of these. A material is a Roblox material
	name, a color and optionally reflectance and transparency (Engine/TableTheme has the full shape).
	cardEdge and the four chip entries are the ones the code itself asks for; the rest are named by Felt and Props.
]]

return {
	-- the table
	felt = { material = "Fabric", color = { 22, 72, 48 } },
	feltLine = { material = "Metal", color = { 186, 148, 78 }, reflectance = 0.12 },
	rail = { material = "WoodPlanks", color = { 104, 64, 36 } },
	railEdge = { material = "Wood", color = { 74, 44, 24 } },
	brass = { material = "Metal", color = { 206, 166, 86 }, reflectance = 0.28 },
	body = { material = "Wood", color = { 54, 33, 19 } },
	floor = { material = "WoodPlanks", color = { 46, 29, 18 } },

	-- the things on it
	wax = { material = "SmoothPlastic", color = { 232, 212, 168 } },
	wick = { material = "SmoothPlastic", color = { 36, 26, 20 } },
	flame = { material = "Neon", color = { 255, 178, 84 } },
	pewter = { material = "Metal", color = { 148, 146, 150 }, reflectance = 0.18 },
	iron = { material = "Metal", color = { 54, 50, 48 } },
	ale = { material = "SmoothPlastic", color = { 190, 122, 36 } },
	foam = { material = "SmoothPlastic", color = { 244, 234, 210 } },
	bottle = { material = "Glass", color = { 58, 124, 80 }, transparency = 0.15, reflectance = 0.12 },
	cork = { material = "Wood", color = { 156, 114, 72 } },
	coin = { material = "Metal", color = { 224, 184, 82 }, reflectance = 0.32 },
	bone = { material = "SmoothPlastic", color = { 236, 226, 202 } },
	leather = { material = "Leather", color = { 92, 48, 30 } },
	page = { material = "SmoothPlastic", color = { 226, 208, 170 } },

	-- the room
	wall = { material = "WoodPlanks", color = { 72, 46, 32 } },
	stone = { material = "Cobblestone", color = { 84, 74, 66 } },
	beam = { material = "Wood", color = { 44, 28, 18 } },
	banner = { material = "Fabric", color = { 104, 22, 24 } },
	bannerGold = { material = "Fabric", color = { 176, 134, 62 } },
	ember = { material = "Neon", color = { 235, 92, 30 } },
	fire = { material = "Neon", color = { 255, 150, 48 } },
	soot = { material = "Slate", color = { 22, 18, 16 } },
	lampGlass = { material = "Neon", color = { 236, 156, 72 } },
	barrel = { material = "WoodPlanks", color = { 96, 62, 36 } },

	-- the pieces the code builds
	board = { material = "Wood", color = { 82, 52, 30 } }, -- the boards the HUD's pieces stand on
	cardEdge = { material = "SmoothPlastic", color = { 226, 200, 158 } },
	chipChips = { material = "SmoothPlastic", color = { 58, 108, 198 } },
	chipMult = { material = "SmoothPlastic", color = { 194, 58, 48 } },
	chipTips = { material = "Metal", color = { 224, 184, 82 }, reflectance = 0.3 },
	chipStripe = { material = "SmoothPlastic", color = { 240, 230, 208 } },
}
