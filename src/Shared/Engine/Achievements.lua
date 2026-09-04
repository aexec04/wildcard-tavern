--[[
	Achievements.lua
	ACHIEVEMENTS + TITLES (Phase 16): a small catalog of permanent
	milestones, each tied to a PlayerProfile stat that was already being
	tracked (Shared/Engine/PlayerProfile.lua's `stats`, plus
	discoveredPatronIds/ownedThemeIds) but, until now, only ever shown as
	a plain "Runs Won: 3" style stat line on Client/Collection.lua.
	Earning one unlocks a Title the player can equip (see
	PlayerProfile.equipTitle) and show off next to their name.

	DELIBERATELY STATELESS ("unlocked" is a computed property, not a
	saved one): every stat these check is monotonic -- runsStarted/
	runsWon only ever go up, bestNightReached is already a high-water
	mark, discoveredPatronIds/ownedThemeIds are sets that only ever
	grow (see PlayerProfile.lua's own functions for each of those --
	none of them ever remove anything). That means "is this achievement
	unlocked" can be recomputed fresh from the profile on every single
	call, cheaply, with zero risk of it ever flickering back off --
	so unlike `equippedTitleId` (an actual player CHOICE, which does
	need saving, see PlayerProfile.lua), nothing here needs its own
	persisted "unlocked achievements" list at all. One less thing that
	could ever drift out of sync with the stats it's derived from.

	Pure Lua, no Roblox APIs -- testable with plain `lua5.3`, same as
	every other Shared/Engine module.
]]

local Patrons = require(script.Parent.Patrons)

local Achievements = {}

Achievements.Definitions = {
	{
		id = "first_steps",
		name = "First Steps",
		icon = "👣",
		title = "Newcomer",
		description = "Start your first run.",
		requirement = function(profile) return profile.stats.runsStarted >= 1 end,
	},
	{
		id = "closing_time",
		name = "Closing Time",
		icon = "🌙",
		title = "Tavern Keeper",
		description = "Win your first run.",
		requirement = function(profile) return profile.stats.runsWon >= 1 end,
	},
	{
		id = "regular",
		name = "Regular",
		icon = "🍺",
		title = "Regular",
		description = "Win 5 runs.",
		requirement = function(profile) return profile.stats.runsWon >= 5 end,
	},
	{
		id = "tavern_legend",
		name = "Legend of the Tavern",
		icon = "🏆",
		title = "Tavern Legend",
		description = "Win 20 runs.",
		requirement = function(profile) return profile.stats.runsWon >= 20 end,
	},
	{
		id = "deep_cuts",
		name = "Deep Cuts",
		icon = "🕯",
		title = "Deep Diver",
		description = "Reach Night 4 in a single run.",
		requirement = function(profile) return profile.stats.bestNightReached >= 4 end,
	},
	{
		id = "into_the_endless",
		name = "Into the Endless",
		icon = "♾",
		title = "Endless Wanderer",
		description = "Push past Night 8 into Endless Mode in a single run.",
		requirement = function(profile) return profile.stats.bestNightReached >= 9 end,
	},
	{
		id = "patron_saint",
		name = "Patron Saint",
		icon = "🫂",
		title = "Patron Saint",
		description = "Discover 10 different Patrons across all your runs.",
		requirement = function(profile)
			local count = 0
			for _ in pairs(profile.discoveredPatronIds) do
				count = count + 1
			end
			return count >= 10
		end,
	},
	{
		id = "full_house",
		name = "Full House",
		icon = "🏘",
		title = "Collector",
		description = "Discover 25 different Patrons across all your runs.",
		requirement = function(profile)
			local count = 0
			for _ in pairs(profile.discoveredPatronIds) do
				count = count + 1
			end
			return count >= 25
		end,
	},
	{
		id = "every_patron",
		name = "Every Patron",
		icon = "💯",
		title = "Completionist",
		description = "Discover every single Patron in the game.",
		requirement = function(profile)
			local count = 0
			for _ in pairs(profile.discoveredPatronIds) do
				count = count + 1
			end
			return count >= #Patrons.Definitions
		end,
	},
	{
		id = "redecorated",
		name = "Redecorated",
		icon = "🖼",
		title = "Interior Decorator",
		description = "Buy your first Theme with Tips.",
		requirement = function(profile)
			local count = 0
			for _ in pairs(profile.ownedThemeIds) do
				count = count + 1
			end
			return count >= 1
		end,
	},
	{
		id = "theme_connoisseur",
		name = "Theme Connoisseur",
		icon = "🎨",
		title = "Connoisseur",
		description = "Own 4 different Themes bought with Tips.",
		requirement = function(profile)
			local count = 0
			for _ in pairs(profile.ownedThemeIds) do
				count = count + 1
			end
			return count >= 4
		end,
	},
}

function Achievements.getById(id)
	for _, achievement in ipairs(Achievements.Definitions) do
		if achievement.id == id then
			return achievement
		end
	end
	return nil
end

function Achievements.isUnlocked(profile, achievementId)
	local achievement = Achievements.getById(achievementId)
	if not achievement then
		return false
	end
	return achievement.requirement(profile) == true
end

-- Every achievement currently unlocked for this profile, in catalog
-- order. See this file's header for why this is safe to recompute on
-- every call instead of reading from a saved list.
function Achievements.unlockedFor(profile)
	local unlocked = {}
	for _, achievement in ipairs(Achievements.Definitions) do
		if achievement.requirement(profile) then
			table.insert(unlocked, achievement)
		end
	end
	return unlocked
end

return Achievements
