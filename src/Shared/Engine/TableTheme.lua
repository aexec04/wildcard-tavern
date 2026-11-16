--[[
	Engine/TableTheme.lua
	What a 3D table theme is, and the check every theme has to pass. A theme is a folder of four data modules under
	Shared/TableThemes/<Name>/ and nothing else:

	  Materials   name -> { material = "<Enum.Material name>", color = { r, g, b }, reflectance?, transparency? }
	  Lighting    { service = { <Lighting property> = number | { r, g, b } }, effects = { <Class> = { ... } },
	                lights = { { kind = "Spot" | "Point", at = { x, y, z }, lookAt?, color, brightness, range, angle?,
	                shadows?, flicker? } }, cards = { lightInfluence, brightness }, react = { ... } }
	  Props       list of { name, at = { x, y, z }, yaw?, hop?, parts = { { shape, size, offset?, rot?, mat } },
	                light? = { offset, color, brightness, range, shadows?, flicker? } }
	  Felt        { surface, body, floor, rail = { top, inner, trim, studs = { material, spacing, size } },
	                line = { material, inset, width } }

	Positions are in table space (Engine/TableScene): x right, y up from the felt, z toward the player, measured from
	the table's middle. The code that builds the scene (Client/Table3D/Scene) reads only these four tables, so a second
	theme is a second folder: no code changes.

	TableTheme.PARTS                the four module names
	TableTheme.REQUIRED_MATERIALS   names the code itself asks for (cards, chips)
	TableTheme.check(theme) -> ok, problems   theme = { Materials = ..., Lighting = ..., Props = ..., Felt = ... }
	TableTheme.default()            the theme the game uses
]]

local M = {}

M.PARTS = { "Materials", "Lighting", "Props", "Felt" }
M.REQUIRED_MATERIALS = { "cardEdge", "chipChips", "chipMult", "chipTips", "chipStripe", "board" }
M.SHAPES = { Block = true, Cylinder = true, Ball = true, Wedge = true }
M.MATERIALS = {
	Plastic = true, SmoothPlastic = true, Wood = true, WoodPlanks = true, Fabric = true, Metal = true, Brick = true,
	Cobblestone = true, Slate = true, Marble = true, Granite = true, Glass = true, Neon = true, Foil = true,
	Concrete = true, Leather = true, Sand = true, Ice = true, CorrodedMetal = true, Pebble = true, DiamondPlate = true,
	Cardboard = true, Carpet = true, CeramicTiles = true, Plaster = true, Rubber = true, Limestone = true,
}

function M.default()
	return "Tavern"
end

local function isColor(c)
	if type(c) ~= "table" or #c ~= 3 then return false end
	for i = 1, 3 do
		if type(c[i]) ~= "number" or c[i] < 0 or c[i] > 255 then return false end
	end
	return true
end

local function isPoint(p)
	return type(p) == "table" and type(p[1]) == "number" and type(p[2]) == "number" and type(p[3]) == "number"
end

function M.check(theme)
	local problems = {}
	local function bad(text) problems[#problems + 1] = text end
	if type(theme) ~= "table" then
		return false, { "the theme is not a table" }
	end
	for _, part in ipairs(M.PARTS) do
		if type(theme[part]) ~= "table" then bad(part .. " is missing") end
	end
	if #problems > 0 then return false, problems end

	local mats = theme.Materials
	for name, m in pairs(mats) do
		if type(m) ~= "table" or not M.MATERIALS[m.material] then
			bad("material " .. tostring(name) .. " has no known material")
		elseif not isColor(m.color) then
			bad("material " .. tostring(name) .. " has no color")
		end
	end
	for _, name in ipairs(M.REQUIRED_MATERIALS) do
		if not mats[name] then bad("material " .. name .. " is missing (the cards and chips use it)") end
	end
	local function known(name, where)
		if type(name) ~= "string" or not mats[name] then bad(where .. " names the unknown material " .. tostring(name)) end
	end

	local felt = theme.Felt
	known(felt.surface, "Felt.surface")
	known(felt.body, "Felt.body")
	known(felt.floor, "Felt.floor")
	if type(felt.rail) ~= "table" then
		bad("Felt.rail is missing")
	else
		known(felt.rail.top, "Felt.rail.top")
		known(felt.rail.inner, "Felt.rail.inner")
		known(felt.rail.trim, "Felt.rail.trim")
		if felt.rail.studs then known(felt.rail.studs.material, "Felt.rail.studs") end
	end
	if felt.line then known(felt.line.material, "Felt.line") end

	for i, prop in ipairs(theme.Props) do
		local where = "prop " .. tostring(prop.name or i)
		if not isPoint(prop.at) then bad(where .. " has no place") end
		if type(prop.parts) ~= "table" or #prop.parts == 0 then
			bad(where .. " has no parts")
		else
			for _, piece in ipairs(prop.parts) do
				if not M.SHAPES[piece.shape] then bad(where .. " has a part of unknown shape " .. tostring(piece.shape)) end
				if type(piece.size) ~= "table" then bad(where .. " has a part with no size") end
				known(piece.mat, where)
			end
		end
		if prop.light and not isColor(prop.light.color) then bad(where .. " has a light with no color") end
	end

	local lighting = theme.Lighting
	if type(lighting.service) ~= "table" then bad("Lighting.service is missing") end
	if type(lighting.lights) ~= "table" or #lighting.lights == 0 then
		bad("Lighting.lights is empty: the table needs at least one light")
	else
		for i, light in ipairs(lighting.lights) do
			local where = "light " .. tostring(light.name or i)
			if light.kind ~= "Spot" and light.kind ~= "Point" then bad(where .. " is neither Spot nor Point") end
			if not isPoint(light.at) then bad(where .. " has no place") end
			if not isColor(light.color) then bad(where .. " has no color") end
		end
	end
	return #problems == 0, problems
end

return M
