--[[
	BossCounters.lua
	BOSS COUNTERPLAY: a loss to a boss should feel avoidable. Pure Lua, no Roblox APIs, display and bookkeeping only (the
	Rule Ban in RunState is the only thing that changes a run, and only for a normal run).

	  * Boss Scout: `scout(boss)` is what Round Select and the Counter show for the Night's boss: id, name, a rule icon and a
	    one line rule of at most MAX_WORDS words (the registry description when short enough, otherwise an explicit short line).
	  * Counter tags: every Boss Round has 1 to 2 `rules` tags (Engine/BossRounds.lua); Patrons, Recipes and House Passes carry
	    an optional `counters` list of those tags where they truly help. `counters(boss, item)` is true when they share a tag.
	  * Coverage: every rule tag has at least MIN_COUNTERS counter items in the registries, so no boss is uncounterable.
]]

local BossRounds = require(script.Parent.BossRounds)
local Patrons = require(script.Parent.Patrons)
local Recipes = require(script.Parent.Recipes)
local HousePasses = require(script.Parent.HousePasses)

local BossCounters = {}

BossCounters.MAX_WORDS = 12
BossCounters.MIN_COUNTERS = 3

-- icon per rule tag (shown on the Scout card, the Counter chip and the shield tags)
BossCounters.TagIcons = {
	fewerHands = "⏳", fewerDiscards = "♻️", lowHandSize = "🃏", cardToss = "💨", cardCount = "🔢", suitDebuff = "🎴", faceDebuff = "👑",
	oddRank = "🔟", noRepeat = "🔁", handBan = "🚫", targetBoost = "🎯", weakenChips = "🔵", weakenMult = "🔴", tipsDrain = "🪙",
	patronLimit = "🧑‍🍳", slowStart = "🐌",
}

-- Short rule lines for the few bosses whose registry description runs past 12 words (EDIT ME).
BossCounters.ShortLines = {
	picked_over = "Hearts score nothing and you are dealt one fewer card.",
	stale_bread = "Chips and Mult are cut by 25% this round.",
	one_at_a_time = "Play exactly 1 card per hand, but the target is lower.",
	quick_service = "Only 2 hands, but the target is 25% lower.",
	lights_out = "Only 1 hand, but the target is halved.",
	double_tab = "Lose 1 Tip per card played, and the target is 20% higher.",
	everythings_out = "Chips and Mult are cut by 30% this round.",
	bare_bones = "Chips and Mult are cut by 28% this round.",
	empty_handed = "Only 1 discard and only 3 hands this round.",
	rowdy_crowd = "2 random cards are tossed after every hand you play.",
	wild_crowd = "3 random cards are tossed after every hand you play.",
	empty_pockets = "Playing your most used hand type wipes your Tips.",
	thin_chips = "Chips from played hands are cut by 40% this round.",
	flat_mult = "Mult from played hands is cut by 40% this round.",
	thin_soup = "Chips from played hands are cut by 20% this round.",
	slow_simmer = "Mult from played hands is cut by 20% this round.",
	crowded_counter = "Only your first 4 Patrons help you score.",
	penny_wise = "Tips from scoring are not paid this round.",
	slow_night = "1 random card is tossed after every hand you play.",
}

function BossCounters.wordCount(text)
	local n = 0
	for _ in tostring(text):gmatch("%S+") do n = n + 1 end
	return n
end

-- The one line rule: the registry description when it is short, else the explicit short line.
function BossCounters.ruleLine(boss)
	local override = BossCounters.ShortLines[boss.id]
	if override then
		return override
	end
	return boss.description
end

-- Card data for Round Select and the Counter chip (nil when there is no boss).
function BossCounters.scout(boss)
	if type(boss) ~= "table" then
		return nil
	end
	local tags = boss.rules or {}
	return {
		id = boss.id, name = boss.name, rules = tags, line = BossCounters.ruleLine(boss),
		icon = BossCounters.TagIcons[tags[1] or ""] or "👑",
	}
end

local function hasTag(list, tag)
	for _, t in ipairs(list or {}) do
		if t == tag then return true end
	end
	return false
end

-- Does `item` (a Patron, Recipe or House Pass definition) help against `boss`? Returns the shared tag or nil.
function BossCounters.counters(boss, item)
	if type(boss) ~= "table" or type(item) ~= "table" or not boss.rules or not item.counters then
		return nil
	end
	for _, tag in ipairs(boss.rules) do
		if hasTag(item.counters, tag) then
			return tag
		end
	end
	return nil
end

-- Every counter item of a boss: { { kind, id, name, icon, tag } }.
function BossCounters.itemsFor(boss)
	local out = {}
	local function scan(kind, list)
		for _, item in ipairs(list) do
			local tag = BossCounters.counters(boss, item)
			if tag then out[#out + 1] = { kind = kind, id = item.id, name = item.name, icon = item.icon, tag = tag } end
		end
	end
	scan("patron", Patrons.Definitions)
	scan("recipe", Recipes.HouseRecipes)
	scan("recipe", Recipes.MenuRecipes)
	scan("recipe", Recipes.SecretRecipes)
	scan("housePass", HousePasses.Definitions)
	return out
end

-- The shield tag for one offered item against the Night's boss: { icon, tag, line } or nil.
function BossCounters.shield(boss, item)
	local tag = BossCounters.counters(boss, item)
	if not tag then
		return nil
	end
	return { tag = tag, icon = "🛡️", ruleIcon = BossCounters.TagIcons[tag], line = "Helps against " .. boss.name .. "." }
end

-- Registry check for the tests: problems as a list of strings.
function BossCounters.validate()
	local problems = {}
	local known = {}
	for _, tag in ipairs(BossRounds.RuleTagIds) do known[tag] = true end
	for _, boss in ipairs(BossRounds.Definitions) do
		if type(boss.rules) ~= "table" or #boss.rules < 1 or #boss.rules > 2 then
			problems[#problems + 1] = boss.id .. ": needs 1 to 2 rules tags"
		else
			for _, tag in ipairs(boss.rules) do
				if not known[tag] then problems[#problems + 1] = boss.id .. ": unknown tag " .. tostring(tag) end
			end
		end
		if BossCounters.wordCount(BossCounters.ruleLine(boss)) > BossCounters.MAX_WORDS then
			problems[#problems + 1] = boss.id .. ": rule line is over " .. BossCounters.MAX_WORDS .. " words"
		end
		if #BossCounters.itemsFor(boss) < BossCounters.MIN_COUNTERS then
			problems[#problems + 1] = boss.id .. ": fewer than " .. BossCounters.MIN_COUNTERS .. " counter items"
		end
	end
	local function checkItems(list, kind)
		for _, item in ipairs(list) do
			for _, tag in ipairs(item.counters or {}) do
				if not known[tag] then problems[#problems + 1] = kind .. " " .. item.id .. ": unknown counter tag " .. tostring(tag) end
			end
		end
	end
	checkItems(Patrons.Definitions, "patron")
	checkItems(Recipes.HouseRecipes, "recipe"); checkItems(Recipes.MenuRecipes, "recipe"); checkItems(Recipes.SecretRecipes, "recipe")
	checkItems(HousePasses.Definitions, "housePass")
	return problems
end

return BossCounters
