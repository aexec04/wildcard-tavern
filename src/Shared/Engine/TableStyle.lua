--[[
	Shared/Engine/TableStyle.lua
	Resolves how the gameplay table backdrop looks for the current run state (pure, tested).
	The client (Client/TableLook.lua, Client/GameplayScene.lua) only draws what this returns.

	resolve{ region, night, nightCap, isBoss, set }  ->
	  {
	    region,                 the biome region id (falls back to "tavern")
	    image, source,          image id + "set" | "biome" | nil ("default": keep the current painting)
	    grade = { color, strength },     biome colour wash
	    mood  = { darken, warm },        Night mood: Night 1 light -> Night 8 darkest, a touch warmer
	    vignette = { bottom, sides },    behind the card row; heavier on boss rounds
	    setStyle,                        the set's backdropStyle (tint / overlay / layers), drawn over the biome
	  }
	Layering rule: a set with its own real backdropImage replaces the biome image; any other set keeps
	the biome image and applies its tint and decor layers over it. Nothing here is ever red (no tint tied
	to boss progress; the boss mood is only darker).

	regionOfNight(worldRoute, night) -> region id: Daily, Weekly and Seed runs walk a fixed worldPlan that the
	state already exposes as worldRoute, so every run type resolves the same way.
]]

local BiomeBackdrops = require(script.Parent.BiomeBackdrops)
local WorldMap = require(script.Parent.WorldMap)

local TableStyle = {}

local function realImage(id)
	return type(id) == "string" and id ~= "" and id ~= "rbxassetid://0"
end

function TableStyle.regionOfNight(worldRoute, night)
	local route = type(worldRoute) == "table" and worldRoute or {}
	local stopId = route[night or 1] or route[#route]
	local region = stopId and WorldMap.regionOf(stopId)
	if region and BiomeBackdrops.Grades[region] then
		return region
	end
	return BiomeBackdrops.Default
end

-- Night mood: t runs 0 (Night 1) to 1 (Night 8 and every Endless Night).
function TableStyle.mood(night, nightCap)
	local cap = math.max(nightCap or 8, 2)
	local t = math.max(0, math.min(1, ((night or 1) - 1) / (cap - 1)))
	return { darken = 0.04 + 0.30 * t, warm = 0.02 + 0.06 * t }
end

function TableStyle.resolve(opts)
	opts = opts or {}
	local region = BiomeBackdrops.Grades[opts.region] and opts.region or BiomeBackdrops.Default
	local isBoss = opts.isBoss == true
	local set = opts.set

	local image, source = nil, "default"
	if set and realImage(set.scenery) then
		image, source = set.scenery, "set"
	elseif set and realImage(set.backdropImage) then
		image, source = set.backdropImage, "set"
	elseif realImage(BiomeBackdrops.Images[region]) then
		image, source = BiomeBackdrops.Images[region], "biome"
	end

	local grade = BiomeBackdrops.Grades[region]
	local mood = TableStyle.mood(opts.night, opts.nightCap)
	local vignette = { bottom = 0.5, sides = 0.15 }
	if isBoss then
		mood.darken = mood.darken + 0.10
		vignette = { bottom = 0.62, sides = 0.35 }
	end

	if source == "set" then
		-- Set scenery can be bright anywhere: keep a soft dark vignette behind the hand tray and side panel.
		vignette = { bottom = math.max(vignette.bottom, 0.8), sides = math.max(vignette.sides, 0.4) }
	end

	return {
		region = region,
		image = image,
		source = source,
		grade = { color = { grade.color[1], grade.color[2], grade.color[3] }, strength = grade.strength },
		mood = mood,
		vignette = vignette,
		setStyle = set and set.backdropStyle or nil,
		isBoss = isBoss,
	}
end

return TableStyle
