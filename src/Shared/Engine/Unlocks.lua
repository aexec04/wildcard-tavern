--[[
	Unlocks.lua
	The unlock drip: a new player starts with about half of the Patrons and House/Secret Recipes in the shop
	and pack pools, and the rest open up through play. Pure Lua, no Roblox APIs.

	Rules are data. Only GATED content is listed here; anything not listed is available from the start.
		{ kind = "wins", n }          runs won (profile.stats.runsWon)
		{ kind = "bestNight", n }     best Night reached (profile.stats.bestNightReached)
		{ kind = "hands", n }         hands played over all runs (profile.stats.handsPlayedTotal)
		{ kind = "stake", n }         stake n cleared (won a standard run on it, see Stakes.lua)
		{ kind = "quests", n }        daily quests done (profile.questsDone, set by the quests feature)
		{ kind = "rank", n }          Tavern Rank level (profile.tavernRank, set by the rank feature)
		{ kind = "grant" }            never by progress alone, only granted (biome rewards, login streak)

	Content stays unlocked for good: once a rule passes it is saved in profile.unlockedContent, and anything
	the player already discovered in the Collection (owned, offered, revealed) counts as unlocked, so existing
	profiles lose nothing. Never lock anything a player paid for: Card Sets and Titles keep their own rules
	(CosmeticSets, Achievements) and are not gated here.

	A run reads `state.unlockedContent` (a set of "kind:id" keys, see Unlocks.setFor). A nil set means
	everything is available (tests, Daily, Weekly, Seed and the tutorial, so shared boards stay fair).
]]

local Unlocks = {}

Unlocks.START_PATRONS_NOTE = "about half of the Patrons and Recipes are open at the start"

local function wins(n) return { kind = "wins", n = n, hint = n == 1 and "Win a run." or ("Win " .. n .. " runs.") } end
local function night(n) return { kind = "bestNight", n = n, hint = "Reach Night " .. n .. "." } end
local function hands(n) return { kind = "hands", n = n, hint = "Play " .. n .. " hands." } end
local function stake(n) return { kind = "stake", n = n, hint = "Clear stake " .. n .. "." } end
local function quests(n) return { kind = "quests", n = n, hint = "Finish " .. n .. " daily quests." } end
local function rank(n) return { kind = "rank", n = n, hint = "Reach Tavern Rank " .. n .. "." } end
local function grant(hint) return { kind = "grant", hint = hint } end

-- [contentKind][id] = rule. contentKind is "patron" or "recipe" (House and Secret Recipes; Menu Recipes are free).
Unlocks.Rules = {
	patron = {
		-- Night 2
		all_hands_in = night(2), repeat_customer = night(2), spare_change = night(2),
		efficient_service = night(2), steady_hand = night(2),
		-- Night 3
		rainy_day_fund = night(3), boss_bane = night(3), slow_cooker = night(3),
		cobweb_shelf = night(3), estate_sale = night(3),
		-- hands played
		house_special = hands(100), early_bird = hands(100), night_owl = hands(100), the_apprentice = hands(100),
		-- first win
		curtain_call = wins(1), house_favorite = wins(1), the_understudy = wins(1),
		second_opinion = wins(1), nest_egg = wins(1), full_house_crowd = wins(1),
		-- more wins
		house_tab = wins(2), tasting_menu = wins(2), veterans_table = wins(2),
		the_bard = wins(5),
		penny_pincher = stake(1),
		-- depth Patrons (suit, pair, straight, economy, scaling, rule benders)
		flush_fan = night(4),
		suit_sampler = hands(250),
		warm_hearth = quests(5),
		color_matcher = rank(2),
		full_suit_feast = wins(3),
		twin_spoons = night(2),
		triple_treat = hands(200),
		foursome_table = stake(2),
		kitchen_duo = wins(1),
		pair_parade = quests(10),
		stair_climber = night(3),
		long_road = rank(3),
		ladder_builder = hands(300),
		royal_road = wins(4),
		savings_club = night(4),
		bargain_hunter = quests(3),
		quick_service = rank(4),
		lucky_penny_jar = hands(120),
		rising_dough = wins(2),
		stack_of_plates = quests(8),
		bread_starter = stake(3),
		extra_chair = rank(5),
		second_helpings = night(6),
		overtime = wins(6),
		-- road Patrons arrive with the biome reward
		meadow_bee = grant("Clear the Wildflower Meadow."), ferry_captain = grant("Clear the Willow River."),
		summit_guide = grant("Clear the Mountain Peaks."), sand_merchant = grant("Clear the Golden Dunes."),
		marsh_gardener = grant("Clear the Misty Marsh."), lantern_lighter = grant("Clear the Frosty Hills."),
		lighthouse_keeper = grant("Clear the Lantern Coast."),
	},
	housePass = {
		pantry_shelf = wins(1),
		tip_stand = night(4),
		card_cart = wins(3),
		savings_account = quests(6),
		warm_welcome = stake(2),
		boss_prep = rank(3),
	},
	recipe = {
		house_token_order = night(2), golden_hour = night(2),
		copy_the_order = wins(1), tip_doubler = wins(1), tabs_on_the_house = wins(1), new_regular = wins(1),
		encore_order = night(3), blue_plate_special = night(3), wildcard_swap = night(3), neighborhood_watch = night(3),
		borrow_the_recipe = hands(150), fresh_squeeze = hands(150), split_the_check = hands(150),
		-- Secret Recipes
		whole_menu_upgrade = wins(2), fresh_start = night(4), sugar_shield = night(5), crowd_favorite = wins(1), gold_standard = night(5),
		rainbow_sprinkle = wins(3), prime_reservation = wins(2), everybodys_favorite = wins(5), bedtime_bonus = night(6),
		-- second batch (16): level-ups, card modifiers and strategic Recipes, spread over every rule kind
		single_serving = night(2), swap_out = night(2), cooks_choice = rank(2), family_style = night(3),
		pair_platter = hands(150), stamp_collector = hands(200), fresh_menu = quests(5), suit_flip = quests(8),
		suit_platter = wins(2), silver_platter = wins(3), patron_echo = wins(4),
		row_platter = night(4), feast_platter = rank(4), patron_shuffle = rank(6),
		gold_leaf = stake(1), twin_card = stake(2),
		-- road Recipes arrive with the biome reward
		honey_drizzle = grant("Clear the Wildflower Meadow."), riverside_chowder = grant("Clear the Willow River."),
		summit_stew = grant("Clear the Mountain Peaks."), date_cake = grant("Clear the Golden Dunes."),
		bog_stew = grant("Clear the Misty Marsh."), frost_pudding = grant("Clear the Frosty Hills."),
		sea_biscuit = grant("Clear the Lantern Coast."),
	},
}

local DISCOVERED_FIELD = { patron = "discoveredPatronIds", recipe = "discoveredRecipeIds", housePass = "discoveredHousePassIds" }

local function key(kind, id)
	return kind .. ":" .. id
end

function Unlocks.ruleOf(kind, id)
	local rules = Unlocks.Rules[kind]
	return rules and rules[id] or nil
end

function Unlocks.isGated(kind, id)
	return Unlocks.ruleOf(kind, id) ~= nil
end

-- Does the profile's progress satisfy a rule right now?
function Unlocks.ruleMet(profile, rule)
	local stats = (profile and profile.stats) or {}
	local n = rule.n or 0
	if rule.kind == "wins" then
		return (stats.runsWon or 0) >= n
	elseif rule.kind == "bestNight" then
		return (stats.bestNightReached or 0) >= n
	elseif rule.kind == "hands" then
		return (stats.handsPlayedTotal or 0) >= n
	elseif rule.kind == "stake" then
		return ((profile and profile.highestStakeUnlocked) or 1) >= n + 1
	elseif rule.kind == "quests" then
		return ((profile and profile.questsDone) or 0) >= n
	elseif rule.kind == "rank" then
		return ((profile and profile.tavernRank) or 1) >= n
	end
	return false -- "grant" and unknown kinds never open by progress
end

-- True when this content may appear for this profile.
function Unlocks.isUnlocked(profile, kind, id)
	local rule = Unlocks.ruleOf(kind, id)
	if not rule then
		return true
	end
	if profile and profile.unlockedContent and profile.unlockedContent[key(kind, id)] then
		return true
	end
	local field = DISCOVERED_FIELD[kind]
	if profile and field and profile[field] and profile[field][id] then
		return true -- already seen or owned: existing profiles keep everything
	end
	return Unlocks.ruleMet(profile, rule)
end

-- Saves every newly satisfied rule into profile.unlockedContent and returns them as
-- { { kind, id, hint } } in a stable order (for the unlock toast), plus whether the profile changed.
-- Call on every server sync.
function Unlocks.evaluate(profile)
	profile.unlockedContent = profile.unlockedContent or {}
	local fresh = {}
	local saved = false -- true when the profile changed, even for silently carried-over content
	for _, kind in ipairs({ "patron", "recipe", "housePass" }) do
		local ids = {}
		for id in pairs(Unlocks.Rules[kind]) do
			ids[#ids + 1] = id
		end
		table.sort(ids)
		for _, id in ipairs(ids) do
			local k = key(kind, id)
			if not profile.unlockedContent[k] and Unlocks.isUnlocked(profile, kind, id) then
				profile.unlockedContent[k] = true
				saved = true
				-- Content that was already discovered before this feature is not "new": no toast for it.
				local field = DISCOVERED_FIELD[kind]
				local seen = profile[field] and profile[field][id]
				if not seen then
					fresh[#fresh + 1] = { kind = kind, id = id, hint = Unlocks.Rules[kind][id].hint }
				end
			end
		end
	end
	return fresh, saved
end

-- The set a run reads: "kind:id" -> true for every gated item this profile has open.
function Unlocks.setFor(profile)
	local set = {}
	for kind, rules in pairs(Unlocks.Rules) do
		for id in pairs(rules) do
			if Unlocks.isUnlocked(profile, kind, id) then
				set[key(kind, id)] = true
			end
		end
	end
	return set
end

-- Is this content in the pools of a run? A run without `unlockedContent` has everything.
function Unlocks.available(state, kind, id)
	local set = state and state.unlockedContent
	if set == nil or not Unlocks.isGated(kind, id) then
		return true
	end
	return set[key(kind, id)] == true
end

-- Filters a list of definitions ({ id = ... }) for a run.
function Unlocks.filter(state, kind, list)
	if not (state and state.unlockedContent) then
		return list
	end
	local out = {}
	for _, def in ipairs(list) do
		if Unlocks.available(state, kind, def.id) then
			out[#out + 1] = def
		end
	end
	return out
end

-- How far along a measurable rule is: current, needed. nil for rules progress alone cannot open.
local function progressOf(profile, rule)
	local stats = (profile and profile.stats) or {}
	if rule.kind == "wins" then
		return stats.runsWon or 0, rule.n
	elseif rule.kind == "bestNight" then
		return stats.bestNightReached or 0, rule.n
	elseif rule.kind == "hands" then
		return stats.handsPlayedTotal or 0, rule.n
	elseif rule.kind == "stake" then
		return math.max(0, ((profile and profile.highestStakeUnlocked) or 1) - 1), rule.n
	elseif rule.kind == "quests" then
		return (profile and profile.questsDone) or 0, rule.n
	elseif rule.kind == "rank" then
		return ((profile and profile.tavernRank) or 1) - 1, rule.n - 1
	end
	return nil
end

-- The closed item that is closest to opening, for the "next goal" line:
-- { kind, id, hint, current, needed, ratio } or nil when nothing measurable is left.
function Unlocks.closest(profile)
	local best
	for _, kind in ipairs({ "patron", "recipe", "housePass" }) do
		local ids = {}
		for id in pairs(Unlocks.Rules[kind]) do
			ids[#ids + 1] = id
		end
		table.sort(ids)
		for _, id in ipairs(ids) do
			local rule = Unlocks.Rules[kind][id]
			if not Unlocks.isUnlocked(profile, kind, id) then
				local current, needed = progressOf(profile, rule)
				if current and needed and needed > 0 then
					local ratio = math.max(0, math.min(1, current / needed))
					if ratio < 1 and (best == nil or ratio > best.ratio) then
						best = { kind = kind, id = id, hint = rule.hint, current = current, needed = needed, ratio = ratio }
					end
				end
			end
		end
	end
	return best
end

-- Hints for the Collection: [kind][id] = hint for gated content this profile has NOT opened yet.
function Unlocks.lockedHints(profile)
	local out = { patron = {}, recipe = {}, housePass = {} }
	for kind, rules in pairs(Unlocks.Rules) do
		for id, rule in pairs(rules) do
			if not Unlocks.isUnlocked(profile, kind, id) then
				out[kind][id] = rule.hint
			end
		end
	end
	return out
end

return Unlocks
