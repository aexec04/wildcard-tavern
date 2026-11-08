--[[
	Shared/Engine/Badges.lua
	Badge registry (pure, no Roblox APIs). A Badge is a collectible mark earned once and kept in
	profile.badgeIds ([badge id] = true).

	Today it holds the biome badges (granted by Engine/BiomeRewards.lua):
	  biome_<region>   first clear of the biome (reaching its branch end)
	  master_<region>  WINNING a run through that biome upgrades the badge to a gold "Master" version
	Regions: meadow, river, peaks, desert, swamp, snow, coast, tavern. Art is not generated yet (emoji icons);
	the needed art is listed in claude/ART_TODO.md.
]]

local Badges = {}

-- region -> { name, icon } (display names of the biome, kid-safe)
local BIOMES = {
	{ region = "meadow", name = "Meadow", icon = "🌼" },
	{ region = "river", name = "River", icon = "🌉" },
	{ region = "peaks", name = "Peaks", icon = "⛰" },
	{ region = "desert", name = "Dunes", icon = "🏜" },
	{ region = "swamp", name = "Marsh", icon = "🐸" },
	{ region = "snow", name = "Frost", icon = "❄" },
	{ region = "coast", name = "Coast", icon = "🗼" },
	{ region = "tavern", name = "Tavern", icon = "🏠" },
}

Badges.Definitions = {}
for _, b in ipairs(BIOMES) do
	table.insert(Badges.Definitions, {
		id = "biome_" .. b.region,
		name = b.name .. " Badge",
		icon = b.icon,
		region = b.region,
		tier = "first",
		rarity = b.region == "tavern" and "epic" or "uncommon",
		description = "Reach the end of the " .. b.name .. " road for the first time.",
	})
	table.insert(Badges.Definitions, {
		id = "master_" .. b.region,
		name = "Master " .. b.name .. " Badge",
		icon = b.icon,
		region = b.region,
		tier = "master",
		rarity = b.region == "tavern" and "legendary" or "epic",
		description = "Win a run that travels through the " .. b.name .. " road.",
	})
end

function Badges.getById(id)
	for _, def in ipairs(Badges.Definitions) do
		if def.id == id then
			return def
		end
	end
	return nil
end

function Badges.has(profile, id)
	return type(profile) == "table" and type(profile.badgeIds) == "table" and profile.badgeIds[id] == true
end

-- Grants once. Returns true only the first time.
function Badges.grant(profile, id)
	if not Badges.getById(id) then return false end
	profile.badgeIds = profile.badgeIds or {}
	if profile.badgeIds[id] then return false end
	profile.badgeIds[id] = true
	return true
end

-- Sorted list of the profile's badge ids (for the state push).
function Badges.list(profile)
	local out = {}
	for id, flag in pairs(type(profile) == "table" and profile.badgeIds or {}) do
		if flag == true and Badges.getById(id) then
			out[#out + 1] = id
		end
	end
	table.sort(out)
	return out
end

return Badges
