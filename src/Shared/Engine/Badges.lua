--[[
	Shared/Engine/Badges.lua
	Badge registry and earning rules (pure, no Roblox APIs, unit-tested). A Badge is a collectible mark earned once
	and kept for good in profile.badgeIds ([badge id] = true); one can be equipped (profile.equippedBadgeId) and is
	shown beside the player's name on the leaderboards and the results screen.

	Two sources:
	  - biome badges (`biome_<region>` first clear, gold `master_<region>` for a won run through it), granted by
	    Engine/BiomeRewards.lua;
	  - rule badges, granted by Badges.evaluate(profile) from data the profile already holds:
	      runsWon        stats.runsWon >= n            (wins_1, wins_5, wins_25)
	      nightReached   stats.bestNightReached >= n   (night_3, night_5, night_8, night_10)
	      minigameWins   profile.minigameWins >= n     (minigame_1, minigame_10)
	      milestone      CollectionBook milestone id claimed (collection_25, collection_50, collection_100)
	      loginStreak    profile.loginStreak >= n      (streak_3, streak_7, streak_14)
	      season         profile.seasonRewardIds[id]   (season_winter_lanterns)
	Art is not generated yet (emoji icons); the needed art is listed in claude/ART_TODO.md.

	Real Roblox Badges: Engine/BadgeIds.lua maps a game badge id to a Roblox badge id (nil until created in Creator
	Hub). Badges.awardPlan(newIds, ids) turns newly earned badges into the awards to send, skipping every nil id.
]]

local Badges = {}

-- region -> display name and icon (kid-safe)
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
		group = "Biomes",
		rarity = b.region == "tavern" and "epic" or "uncommon",
		description = "Reach the end of the " .. b.name .. " road for the first time.",
		hint = "Finish the " .. b.name .. " road.",
	})
	table.insert(Badges.Definitions, {
		id = "master_" .. b.region,
		name = "Master " .. b.name .. " Badge",
		icon = b.icon,
		region = b.region,
		tier = "master",
		group = "Biomes",
		rarity = b.region == "tavern" and "legendary" or "epic",
		description = "Win a run that travels through the " .. b.name .. " road.",
		hint = "Win a run through the " .. b.name .. " road.",
	})
end

local function rule(id, name, icon, rarity, group, description, hint, kind, n)
	table.insert(Badges.Definitions, {
		id = id, name = name, icon = icon, rarity = rarity, group = group, description = description, hint = hint,
		rule = { kind = kind, n = n, id = type(n) == "string" and n or nil },
	})
end

rule("wins_1", "First Win", "🏆", "uncommon", "Wins", "Win a run.", "Win a run.", "runsWon", 1)
rule("wins_5", "Five Wins", "🏆", "rare", "Wins", "Win 5 runs.", "Win 5 runs.", "runsWon", 5)
rule("wins_25", "Tavern Legend", "👑", "epic", "Wins", "Win 25 runs.", "Win 25 runs.", "runsWon", 25)
rule("night_3", "Night 3", "🌙", "common", "Nights", "Reach Night 3.", "Reach Night 3.", "nightReached", 3)
rule("night_5", "Night 5", "🌙", "uncommon", "Nights", "Reach Night 5.", "Reach Night 5.", "nightReached", 5)
rule("night_8", "Keeper's Table", "🌟", "rare", "Nights", "Reach Night 8.", "Reach Night 8.", "nightReached", 8)
rule("night_10", "Endless Walker", "🌌", "epic", "Nights", "Reach Endless Night 10.", "Reach Night 10.", "nightReached", 10)
rule("minigame_1", "Lucky Break", "🎲", "uncommon", "Games", "Win a map minigame.", "Win a minigame on the map.", "minigameWins", 1)
rule("minigame_10", "Game Master", "🃏", "rare", "Games", "Win 10 map minigames.", "Win 10 minigames on the map.", "minigameWins", 10)
rule("collection_25", "Curious Collector", "📖", "uncommon", "Collection", "Fill 25% of the Collection.", "Fill 25% of the Collection.", "milestone", "quarter")
rule("collection_50", "Keen Collector", "📖", "rare", "Collection", "Fill half of the Collection.", "Fill half of the Collection.", "milestone", "half")
rule("collection_100", "Keeper of Tales", "📚", "legendary", "Collection", "Fill the whole Collection.", "Fill the whole Collection.", "milestone", "complete")
rule("streak_3", "Regular", "🔥", "common", "Visits", "Visit 3 days in a row.", "Visit 3 days in a row.", "loginStreak", 3)
rule("streak_7", "Week at the Tavern", "🔥", "uncommon", "Visits", "Visit 7 days in a row.", "Visit 7 days in a row.", "loginStreak", 7)
rule("streak_14", "Fortnight Friend", "🔥", "rare", "Visits", "Visit 14 days in a row.", "Visit 14 days in a row.", "loginStreak", 14)
rule("season_winter_lanterns", "Winter Lanterns", "🏮", "epic", "Seasons", "Earn the Winter Lanterns rewards during the season.", "Clear 3 Nights in one run during Winter Lanterns.", "season", "winter_lanterns")

-- Shelf filter chips on the Badges panel: Roads (first-clear biome badges), Masters, Night (reach-a-Night
-- badges) and Special (wins, games, collection, visits, seasons). Every badge is in exactly one chip.
Badges.Chips = { "All", "Roads", "Masters", "Night", "Special" }
function Badges.chipOf(def)
	if def.tier == "first" then return "Roads" end
	if def.tier == "master" then return "Masters" end
	if def.group == "Nights" then return "Night" end
	return "Special"
end

-- Grid sizing for the shelf: as many columns as fit (at least minCols), cells stretched so the grid fills
-- the whole width with no empty right margin. Returns cols, cellW.
function Badges.gridFor(width, minCell, gap, minCols)
	local cols = math.max(minCols or 2, math.floor((width + gap) / (minCell + gap)))
	local cellW = math.floor((width - (cols - 1) * gap) / cols)
	return cols, cellW
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

-- Does the profile meet this badge's rule right now? (Biome badges have no rule: BiomeRewards grants them.)
function Badges.meetsRule(profile, def)
	local r = def.rule
	if not r or type(profile) ~= "table" then return false end
	local stats = profile.stats or {}
	if r.kind == "runsWon" then
		return (stats.runsWon or 0) >= r.n
	elseif r.kind == "nightReached" then
		return (stats.bestNightReached or 0) >= r.n
	elseif r.kind == "minigameWins" then
		return (profile.minigameWins or 0) >= r.n
	elseif r.kind == "milestone" then
		return type(profile.claimedMilestoneIds) == "table" and profile.claimedMilestoneIds[r.id] == true
	elseif r.kind == "loginStreak" then
		return (profile.loginStreak or 0) >= r.n
	elseif r.kind == "season" then
		return type(profile.seasonRewardIds) == "table" and profile.seasonRewardIds[r.id] == true
	end
	return false
end

-- Grants every rule badge whose rule is met and that is not owned yet. Returns the new ids (sorted).
-- Safe to call on every state push.
function Badges.evaluate(profile)
	local fresh = {}
	for _, def in ipairs(Badges.Definitions) do
		if def.rule and not Badges.has(profile, def.id) and Badges.meetsRule(profile, def) then
			Badges.grant(profile, def.id)
			fresh[#fresh + 1] = def.id
		end
	end
	return fresh
end

-- Badge ids in `after` that were not in `before` (both are { [id] = true }), sorted.
function Badges.newlyEarned(before, after)
	local out = {}
	for id, flag in pairs(after or {}) do
		if flag == true and not (before and before[id]) and Badges.getById(id) then
			out[#out + 1] = id
		end
	end
	table.sort(out)
	return out
end

-- Equip a badge (nil clears). Only an owned badge can be equipped. Returns true, or false and a reason.
function Badges.equip(profile, id)
	if id == nil then
		profile.equippedBadgeId = nil
		return true
	end
	if type(id) ~= "string" or not Badges.getById(id) then return false, "unknown" end
	if not Badges.has(profile, id) then return false, "not_owned" end
	profile.equippedBadgeId = id
	return true
end

-- Display text of the equipped badge ("🏅 Meadow Badge") or nil.
function Badges.equippedText(profile)
	local def = type(profile) == "table" and profile.equippedBadgeId and Badges.getById(profile.equippedBadgeId)
	if def and Badges.has(profile, def.id) then
		return def.icon .. " " .. def.name, def.icon
	end
	return nil, nil
end

-- The awards to send to Roblox for newly earned game badges. `ids` maps a game badge id to a Roblox badge id
-- (Engine/BadgeIds.lua); a missing or non-numeric entry is skipped silently.
function Badges.awardPlan(newIds, ids)
	local plan = {}
	for _, id in ipairs(newIds or {}) do
		local robloxId = type(ids) == "table" and ids[id] or nil
		if type(robloxId) == "number" and robloxId > 0 then
			plan[#plan + 1] = { badge = id, robloxId = robloxId }
		end
	end
	return plan
end

return Badges
