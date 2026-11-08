--[[
	CollectionBook.lua
	The rules behind the Collection screen (Client/Collection.lua): which
	registry entries go on which tab, whether each is discovered, rarity,
	completion %, and the milestone rewards for overall completion.

	Entry data (names, icons, descriptions, flavorText, optional `rarity`)
	stays in the registries. This file only reads them.

	Discovered:
	  patrons / recipes / bosses / housePasses -- id sets saved in
	    PlayerProfile (see Tabs[i].profileField). An entry counts once it
	    was seen in a shop or pack, owned in a run, or faced as a boss
	    (see gatherSeen).
	  titles -- an Achievements entry that is currently unlocked.

	Milestone-reward titles (Achievements entries with milestoneReward =
	true) are shown on the Titles tab but never count toward completion,
	otherwise the 100% milestone could only be reached by already having
	its own reward.

	Pure Lua, no Roblox APIs.
]]

local Patrons = require(script.Parent.Patrons)
local Recipes = require(script.Parent.Recipes)
local BossRounds = require(script.Parent.BossRounds)
local HousePasses = require(script.Parent.HousePasses)
local Achievements = require(script.Parent.Achievements)
local CardBacks = require(script.Parent.CardBacks)

local CollectionBook = {}

-- `color` is {r, g, b}; the client turns it into the tile's glow.
CollectionBook.Rarities = {
	common = { order = 1, name = "Common", color = { 175, 165, 150 } },
	uncommon = { order = 2, name = "Uncommon", color = { 95, 185, 115 } },
	rare = { order = 3, name = "Rare", color = { 85, 145, 235 } },
	epic = { order = 4, name = "Epic", color = { 165, 100, 230 } },
	legendary = { order = 5, name = "Legendary", color = { 245, 185, 60 } },
	mythical = { order = 6, name = "Mythical", color = { 255, 120, 190 } },
}

-- Tier ids in order, for legends and tests.
CollectionBook.RarityOrder = { "common", "uncommon", "rare", "epic", "legendary", "mythical" }

CollectionBook.Tabs = {
	{ id = "patrons", name = "Patrons", profileField = "discoveredPatronIds" },
	{ id = "recipes", name = "Recipes", profileField = "discoveredRecipeIds" },
	{ id = "bosses", name = "Boss Rounds", profileField = "discoveredBossIds" },
	{ id = "housePasses", name = "House Passes", profileField = "discoveredHousePassIds" },
	{ id = "titles", name = "Titles" },
}

-- EDIT ME: overall-completion milestones. Each is granted once, the first
-- time overall completion reaches `percent`. Reward kinds:
--   { kind = "title", id = <Achievements id with milestoneReward = true> }
--   { kind = "cardBack", id = <CardBacks id> }
-- `id` on the milestone itself is what gets saved, so don't rename it
-- once players have claimed it.
CollectionBook.Milestones = {
	{ id = "quarter", percent = 25, rewards = { { kind = "title", id = "curious_guest" } } },
	{ id = "half", percent = 50, rewards = { { kind = "cardBack", id = "gilded_ledger" } } },
	{
		id = "complete",
		percent = 100,
		rewards = {
			{ kind = "title", id = "keeper_of_tales" },
			{ kind = "cardBack", id = "starlit_keeper" },
		},
	},
}

function CollectionBook.getTab(tabId)
	for _, tab in ipairs(CollectionBook.Tabs) do
		if tab.id == tabId then
			return tab
		end
	end
	return nil
end

-- ===== Entries per tab =====
-- Each item is { id, tab, def, kind, counts }: `def` is the registry entry
-- itself, `kind` is "house"/"menu"/"secret" for recipes (nil otherwise),
-- `counts` is false for milestone-reward titles.

local RECIPE_KIND_LABELS = { house = "House Recipe", menu = "Menu Recipe", secret = "Secret Recipe" }

local function buildItems(tabId)
	local items = {}
	local function add(def, kind)
		table.insert(items, {
			id = def.id,
			tab = tabId,
			def = def,
			kind = kind,
			counts = not def.milestoneReward,
		})
	end
	if tabId == "patrons" then
		for _, def in ipairs(Patrons.Definitions) do add(def) end
	elseif tabId == "recipes" then
		for _, def in ipairs(Recipes.HouseRecipes) do add(def, "house") end
		-- MenuRecipes is built with pairs() so its order isn't stable; sort it.
		local menu = {}
		for _, def in ipairs(Recipes.MenuRecipes) do table.insert(menu, def) end
		table.sort(menu, function(a, b) return a.name < b.name end)
		for _, def in ipairs(menu) do add(def, "menu") end
		for _, def in ipairs(Recipes.SecretRecipes) do add(def, "secret") end
	elseif tabId == "bosses" then
		for _, def in ipairs(BossRounds.Definitions) do add(def) end
	elseif tabId == "housePasses" then
		for _, def in ipairs(HousePasses.Definitions) do add(def) end
	elseif tabId == "titles" then
		for _, def in ipairs(Achievements.Definitions) do add(def) end
	end
	return items
end

-- Items of a tab for display: most common first, rarest last (ties keep the
-- registry order). `hidden` is an optional set { [rarityId] = true } of tiers
-- to leave out. Pure; needs CollectionBook.rarityOf (defined below).
function CollectionBook.displayItems(tabId, hidden)
	local rank = {}
	for i, id in ipairs(CollectionBook.RarityOrder) do rank[id] = i end
	local out = {}
	for index, item in ipairs(CollectionBook.itemsFor(tabId)) do
		local rarityId = CollectionBook.rarityOf(item)
		if not (hidden and hidden[rarityId]) then
			table.insert(out, { item = item, rank = rank[rarityId] or 1, index = index })
		end
	end
	table.sort(out, function(a, b)
		if a.rank ~= b.rank then return a.rank < b.rank end
		return a.index < b.index
	end)
	local items = {}
	for i, entry in ipairs(out) do items[i] = entry.item end
	return items
end

local itemCache = {}
function CollectionBook.itemsFor(tabId)
	if not itemCache[tabId] then
		itemCache[tabId] = buildItems(tabId)
	end
	return itemCache[tabId]
end

-- Short label for the detail card, e.g. "Secret Recipe" or "Boss Round".
function CollectionBook.kindLabel(item)
	if item.tab == "recipes" then
		return RECIPE_KIND_LABELS[item.kind] or "Recipe"
	elseif item.tab == "patrons" then
		return "Patron"
	elseif item.tab == "bosses" then
		return "Boss Round"
	elseif item.tab == "housePasses" then
		return "House Pass"
	elseif item.tab == "titles" then
		return "Title"
	end
	return ""
end

-- ===== Rarity =====
-- Six tiers (CollectionBook.RarityOrder). Order of precedence:
--   1. the entry's own `rarity` field,
--   2. CollectionBook.RarityOverrides[tab][id] (explicit, edit me),
--   3. a rule from data the entry already has:
--        patrons      price 8 rare, 7 uncommon, else common
--        recipes      secret rare, house price 5+ uncommon, menu common
--        bosses       minNight 6+ rare, 3+ uncommon, else common
--        housePasses  price 12 legendary, 10 epic, 8 rare, 6 uncommon, else common
--        titles       milestone rewards epic, others uncommon
-- Mythical is kept for a handful of top-end things (Night 8 and 100% rewards,
-- the Golden Gala set); everything else tops out at legendary.
-- Tabs "sets" (Cosmetic Sets) and "backs" (Card Backs) are rated only by overrides.
CollectionBook.RarityOverrides = {
	patrons = {
		house_favorite = "legendary",
		veterans_table = "epic",
		house_tab = "epic",
		full_house_crowd = "epic",
		house_special = "epic",
	},
	recipes = { star_treatment = "epic" },
	titles = {
		curious_guest = "rare",
		tavern_legend = "rare",
		patron_saint = "rare",
		every_patron = "epic",
		endless_legend = "legendary",
		tavern_keeper = "mythical",
		keeper_of_tales = "mythical",
		dune_wanderer = "rare",
		marsh_wader = "rare",
		snow_scout = "rare",
		lighthouse_friend = "rare",
		trailblazer = "legendary",
		lantern_keeper = "epic", -- seasonal (Engine/Seasons.lua)
	},
	sets = {
		classic_tavern = "common",
		winter_evening = "rare",
		festival_night = "rare",
		closing_time = "epic",
		golden_gala = "mythical",
	},
	backs = {
		classic = "common",
		winter_frost = "uncommon",
		festival_ribbon = "uncommon",
		kitchen_checks = "uncommon",
		hall_banner = "uncommon",
		gilded_ledger = "rare",
		closing_lantern = "rare",
		ember_hours = "epic",
		starlit_keeper = "mythical",
		dune_gold = "rare",
		lilypad_green = "rare",
		shell_pearl = "rare",
		frost_walker = "epic",
		gala = "legendary",
		winter_lanterns = "epic", -- seasonal (Engine/Seasons.lua)
	},
}

function CollectionBook.rarityOf(item)
	local def = item.def
	if type(def.rarity) == "string" and CollectionBook.Rarities[def.rarity] then
		return def.rarity
	end
	local override = CollectionBook.RarityOverrides[item.tab]
	if override and override[item.id] then
		return override[item.id]
	end
	local price = def.price or 0
	if item.tab == "patrons" then
		if price >= 8 then return "rare" end
		if price >= 7 then return "uncommon" end
		return "common"
	elseif item.tab == "recipes" then
		if item.kind == "secret" then
			return "rare"
		elseif item.kind == "menu" then
			return "common"
		end
		return price >= 5 and "uncommon" or "common"
	elseif item.tab == "bosses" then
		local minNight = def.minNight or 1
		if minNight >= 6 then return "rare" end
		if minNight >= 3 then return "uncommon" end
		return "common"
	elseif item.tab == "housePasses" then
		if price >= 12 then return "legendary" end
		if price >= 10 then return "epic" end
		if price >= 8 then return "rare" end
		if price >= 6 then return "uncommon" end
		return "common"
	elseif item.tab == "titles" then
		return def.milestoneReward and "epic" or "uncommon"
	end
	return "common"
end

-- Accepts Collection tab ids and ContentArt category names ("boss_rounds",
-- "house_passes"). Returns "common" for an unknown id.
local TAB_ALIASES = { boss_rounds = "bosses", house_passes = "housePasses" }
function CollectionBook.rarityForId(tabId, id)
	tabId = TAB_ALIASES[tabId] or tabId
	for _, item in ipairs(CollectionBook.itemsFor(tabId)) do
		if item.id == id then
			return CollectionBook.rarityOf(item)
		end
	end
	return "common"
end

-- Rarity for a Cosmetic Set / Card Back definition (not Collection tabs).
function CollectionBook.rarityOfSet(set)
	return CollectionBook.rarityOf({ id = set.id, tab = "sets", def = set })
end

function CollectionBook.rarityOfBack(back)
	return CollectionBook.rarityOf({ id = back.id, tab = "backs", def = back })
end

-- ===== Discovery =====

-- { [tabId] = { [id] = true } } for a full profile (server side).
function CollectionBook.discoveredSetsFor(profile)
	local sets = {}
	for _, tab in ipairs(CollectionBook.Tabs) do
		if tab.profileField then
			sets[tab.id] = profile[tab.profileField] or {}
		end
	end
	local titles = {}
	for _, achievement in ipairs(Achievements.unlockedFor(profile)) do
		titles[achievement.id] = true
	end
	sets.titles = titles
	return sets
end

-- Turns { [tabId] = { id, id, ... } } (the shape the server sends the
-- client) back into sets.
function CollectionBook.setsFromLists(lists)
	local sets = {}
	for _, tab in ipairs(CollectionBook.Tabs) do
		local set = {}
		for _, id in ipairs((lists and lists[tab.id]) or {}) do
			set[id] = true
		end
		sets[tab.id] = set
	end
	return sets
end

function CollectionBook.isDiscovered(sets, item)
	local set = sets[item.tab]
	return set ~= nil and set[item.id] == true
end

-- Returns {
--   tabs = { [tabId] = { found, total, percent } },
--   found, total, percent  -- overall
-- } counting only items with counts = true. Percents are floored whole
-- numbers, so 100 only shows once everything is found.
function CollectionBook.completion(sets)
	local result = { tabs = {}, found = 0, total = 0, percent = 0 }
	for _, tab in ipairs(CollectionBook.Tabs) do
		local found, total = 0, 0
		for _, item in ipairs(CollectionBook.itemsFor(tab.id)) do
			if item.counts then
				total = total + 1
				if CollectionBook.isDiscovered(sets, item) then
					found = found + 1
				end
			end
		end
		result.tabs[tab.id] = {
			found = found,
			total = total,
			percent = total > 0 and math.floor(found * 100 / total) or 0,
		}
		result.found = result.found + found
		result.total = result.total + total
	end
	if result.total > 0 then
		result.percent = math.floor(result.found * 100 / result.total)
	end
	return result
end

-- Integer comparison, so 100% means every counted entry, not 99.6% rounded.
function CollectionBook.isMilestoneReached(milestone, completion)
	return completion.found * 100 >= milestone.percent * completion.total
end

-- The first milestone not yet claimed, or nil when all are claimed.
function CollectionBook.nextMilestone(claimedIds)
	for _, milestone in ipairs(CollectionBook.Milestones) do
		if not (claimedIds and claimedIds[milestone.id]) then
			return milestone
		end
	end
	return nil
end

-- Display name for one reward, e.g. 'Title: "Curious Guest"'.
function CollectionBook.rewardLabel(reward)
	if reward.kind == "title" then
		local achievement = Achievements.getById(reward.id)
		return 'Title: "' .. (achievement and achievement.title or reward.id) .. '"'
	elseif reward.kind == "cardBack" then
		local back = CardBacks.getById(reward.id)
		return "Card back: " .. (back and back.name or reward.id)
	end
	return tostring(reward.id)
end

-- Claims every milestone the profile has reached but not yet claimed,
-- and grants its rewards. Returns the list of newly claimed milestones
-- (empty when nothing changed), so the caller knows to save and can tell
-- the player.
function CollectionBook.grantMilestones(profile)
	profile.claimedMilestoneIds = profile.claimedMilestoneIds or {}
	profile.rewardTitleIds = profile.rewardTitleIds or {}
	profile.unlockedCardBackIds = profile.unlockedCardBackIds or {}

	local completion = CollectionBook.completion(CollectionBook.discoveredSetsFor(profile))
	local granted = {}
	for _, milestone in ipairs(CollectionBook.Milestones) do
		if not profile.claimedMilestoneIds[milestone.id] and CollectionBook.isMilestoneReached(milestone, completion) then
			profile.claimedMilestoneIds[milestone.id] = true
			for _, reward in ipairs(milestone.rewards) do
				if reward.kind == "title" then
					profile.rewardTitleIds[reward.id] = true
				elseif reward.kind == "cardBack" then
					profile.unlockedCardBackIds[reward.id] = true
				end
			end
			table.insert(granted, milestone)
		end
	end
	return granted
end

-- ===== What a run has shown the player =====
-- Gathers every id the player has seen in this run, per tab: owned
-- Patrons/Recipes/House Passes, Patron and House Pass shop offers, items
-- in the open pack, and the boss being faced. `shop` is
-- { patrons = {patronDef...}, voucher = passDef|nil } (may be nil).
function CollectionBook.gatherSeen(state, shop)
	local seen = { patrons = {}, recipes = {}, bosses = {}, housePasses = {} }

	for _, patron in ipairs(state.ownedPatrons or {}) do
		table.insert(seen.patrons, patron.id)
	end
	for _, field in ipairs({ "houseRecipeInventory", "menuRecipeInventory", "secretRecipeInventory" }) do
		for _, id in ipairs(state[field] or {}) do
			table.insert(seen.recipes, id)
		end
	end
	for passId, owned in pairs(state.housePasses or {}) do
		if owned then
			table.insert(seen.housePasses, passId)
		end
	end
	if state.bossModifier and state.bossModifier.id then
		table.insert(seen.bosses, state.bossModifier.id)
	end

	local pack = state.pendingPack
	if type(pack) == "table" then
		for _, item in ipairs(pack.items or {}) do
			if item.category == "patron" then
				table.insert(seen.patrons, item.id)
			elseif RECIPE_KIND_LABELS[item.category] then
				table.insert(seen.recipes, item.id)
			end
		end
	end

	if shop then
		for _, patron in ipairs(shop.patrons or {}) do
			table.insert(seen.patrons, patron.id)
		end
		if shop.voucher and shop.voucher.id then
			table.insert(seen.housePasses, shop.voucher.id)
		end
	end

	return seen
end

return CollectionBook
