--[[
	Achievements.lua
	ACHIEVEMENTS + TITLES (Phase 16): a small catalog of permanent
	milestones, each tied to a PlayerProfile stat that was already being
	tracked (Shared/Engine/PlayerProfile.lua's `stats`, plus
	discoveredPatronIds) but, until now, only ever shown as
	a plain "Runs Won: 3" style stat line on Client/Collection.lua.
	Earning one unlocks a Title the player can equip (see
	PlayerProfile.equipTitle) and show off next to their name.

	DELIBERATELY STATELESS ("unlocked" is a computed property, not a
	saved one): every stat these check is monotonic -- runsStarted/
	runsWon only ever go up, bestNightReached is already a high-water
	mark, discoveredPatronIds are sets that only ever
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
		description = "Start your first run or finish the tutorial.",
		flavorText = "The door creaks open. Welcome in, stranger.",
		requirement = function(profile) return profile.stats.runsStarted >= 1 or profile.tutorialRewardClaimed == true end,
	},
	{
		id = "grand_finale",
		name = "Grand Finale",
		icon = "🌙",
		title = "Tavern Keeper",
		description = "Win your first run.",
		flavorText = "The last candle is out and the night was yours.",
		requirement = function(profile) return profile.stats.runsWon >= 1 end,
	},
	{
		id = "regular",
		name = "Regular",
		icon = "🍵",
		title = "Regular",
		description = "Win 5 runs.",
		flavorText = "The keeper starts your cocoa when you walk in.",
		requirement = function(profile) return profile.stats.runsWon >= 5 end,
	},
	{
		id = "tavern_legend",
		name = "Legend of the Tavern",
		icon = "🏆",
		title = "Tavern Legend",
		description = "Win 20 runs.",
		flavorText = "They tell stories about you by the fireplace.",
		requirement = function(profile) return profile.stats.runsWon >= 20 end,
	},
	{
		id = "deep_cuts",
		name = "Deep Cuts",
		icon = "🕯",
		title = "Deep Diver",
		description = "Reach Night 4 in a single run.",
		flavorText = "Few guests stay this late. You did.",
		requirement = function(profile) return profile.stats.bestNightReached >= 4 end,
	},
	{
		id = "into_the_endless",
		name = "Into the Endless",
		icon = "♾",
		title = "Endless Wanderer",
		description = "Push past Night 8 into Endless Mode in a single run.",
		flavorText = "The night keeps going and so do you.",
		requirement = function(profile) return profile.stats.bestNightReached >= 9 end,
	},
	{
		id = "patron_saint",
		name = "Patron Saint",
		icon = "🫂",
		title = "Patron Saint",
		description = "Discover 10 different Patrons across all your runs.",
		flavorText = "Ten new friends and counting.",
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
		flavorText = "Your guest book is getting heavy.",
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
		flavorText = "Every face in town knows your name.",
		requirement = function(profile)
			local count = 0
			for _ in pairs(profile.discoveredPatronIds) do
				count = count + 1
			end
			return count >= #Patrons.Definitions
		end,
	},
	-- COLLECTION MILESTONE TITLES: granted (and saved in
	-- profile.rewardTitleIds) by CollectionBook.grantMilestones, which
	-- reads CollectionBook.Milestones to decide which title goes with
	-- which completion %. Marked milestoneReward so they don't count
	-- toward Collection completion themselves.
	{
		id = "curious_guest",
		name = "Curious Guest",
		icon = "🔍",
		title = "Curious Guest",
		description = "A Collection milestone reward.",
		flavorText = "You've peeked behind a quarter of the tavern's doors.",
		milestoneReward = true,
		requirement = function(profile)
			return profile.rewardTitleIds ~= nil and profile.rewardTitleIds.curious_guest == true
		end,
	},
	{
		id = "keeper_of_tales",
		name = "Keeper of Tales",
		icon = "📖",
		title = "Keeper of Tales",
		description = "A Collection milestone reward.",
		flavorText = "Every story in the tavern has been told to you.",
		milestoneReward = true,
		requirement = function(profile)
			return profile.rewardTitleIds ~= nil and profile.rewardTitleIds.keeper_of_tales == true
		end,
	},
	-- JOURNEY REWARD TITLES: granted (and saved in profile.rewardTitleIds)
	-- by JourneyMap.recordNightsCleared when a Night is cleared for the
	-- first time. milestoneReward keeps them out of Collection completion.
	{
		id = "porch_regular",
		name = "Road Walker",
		icon = "🏮",
		title = "Road Walker",
		description = "A Journey reward: clear Night 1.",
		flavorText = "The dust of the old road never quite washes off.",
		milestoneReward = true,
		requirement = function(profile)
			return profile.rewardTitleIds ~= nil and profile.rewardTitleIds.porch_regular == true
		end,
	},
	{
		id = "loft_climber",
		name = "Bridge Crosser",
		icon = "🪜",
		title = "Bridge Crosser",
		description = "A Journey reward: clear Night 4.",
		flavorText = "The old planks hold steady under your boots.",
		milestoneReward = true,
		requirement = function(profile)
			return profile.rewardTitleIds ~= nil and profile.rewardTitleIds.loft_climber == true
		end,
	},
	{
		id = "tavern_keeper",
		name = "Tavern Keeper",
		icon = "👑",
		title = "Tavern Keeper",
		description = "A Journey reward: clear Night 8.",
		flavorText = "The keys are yours now.",
		milestoneReward = true,
		requirement = function(profile)
			return profile.rewardTitleIds ~= nil and profile.rewardTitleIds.tavern_keeper == true
		end,
	},
	-- TAVERN RANK TITLES: granted (and saved in profile.rewardTitleIds) by Engine/TavernRank.lua on a rank up.
	{
		id = "table_regular",
		name = "Table Regular",
		icon = "🪑",
		title = "Table Regular",
		description = "Reach Tavern Rank 5.",
		flavorText = "Your chair is warm before you sit.",
		milestoneReward = true,
		requirement = function(profile)
			return profile.rewardTitleIds ~= nil and profile.rewardTitleIds.table_regular == true
		end,
	},
	{
		id = "favorite_guest",
		name = "Favorite Guest",
		icon = "💛",
		title = "Favorite Guest",
		description = "Reach Tavern Rank 10.",
		flavorText = "The kitchen sends out your favorite without asking.",
		milestoneReward = true,
		requirement = function(profile)
			return profile.rewardTitleIds ~= nil and profile.rewardTitleIds.favorite_guest == true
		end,
	},
	{
		id = "house_captain",
		name = "House Captain",
		icon = "🧭",
		title = "House Captain",
		description = "Reach Tavern Rank 15.",
		flavorText = "Even the new regulars look to you for the way.",
		milestoneReward = true,
		requirement = function(profile)
			return profile.rewardTitleIds ~= nil and profile.rewardTitleIds.house_captain == true
		end,
	},
	{
		id = "hall_warden",
		name = "Hall Warden",
		icon = "🔔",
		title = "Hall Warden",
		description = "Reach Tavern Rank 20.",
		flavorText = "You know every creak and every corner of the hall.",
		milestoneReward = true,
		requirement = function(profile)
			return profile.rewardTitleIds ~= nil and profile.rewardTitleIds.hall_warden == true
		end,
	},
	{
		id = "grand_host",
		name = "Grand Host",
		icon = "🏛️",
		title = "Grand Host",
		description = "Reach Tavern Rank 30.",
		flavorText = "The whole tavern stands to cheer your name.",
		milestoneReward = true,
		requirement = function(profile)
			return profile.rewardTitleIds ~= nil and profile.rewardTitleIds.grand_host == true
		end,
	},
	-- DISCOVERY TITLES: granted (and saved in profile.rewardTitleIds) by Engine/Discoveries.lua at half and all of the map's spots.
	{
		id = "curious_explorer",
		name = "Curious Explorer",
		icon = "🔭",
		title = "Curious Explorer",
		description = "Find half of the Tavern Map's hidden spots.",
		flavorText = "You always look behind the signpost.",
		milestoneReward = true,
		requirement = function(profile)
			return profile.rewardTitleIds ~= nil and profile.rewardTitleIds.curious_explorer == true
		end,
	},
	{
		id = "grand_explorer",
		name = "Grand Explorer",
		icon = "🗺️",
		title = "Grand Explorer",
		description = "Find every hidden spot on the Tavern Map.",
		flavorText = "There is no corner of the map you have not poked.",
		milestoneReward = true,
		requirement = function(profile)
			return profile.rewardTitleIds ~= nil and profile.rewardTitleIds.grand_explorer == true
		end,
	},
	-- CHALLENGE TITLES: granted (and saved in profile.rewardTitleIds) by Engine/Challenges.lua on the first clear of a twist.
	{
		id = "pair_master",
		name = "Pair Master",
		icon = "👯",
		title = "Pair Master",
		description = "Win a Pairs Only challenge run.",
		flavorText = "Two of a kind, every single time.",
		milestoneReward = true,
		requirement = function(profile)
			return profile.rewardTitleIds ~= nil and profile.rewardTitleIds.pair_master == true
		end,
	},
	{
		id = "steady_dealer",
		name = "Steady Dealer",
		icon = "🎴",
		title = "Steady Dealer",
		description = "Win a No Discards challenge run.",
		flavorText = "You never needed a second chance.",
		milestoneReward = true,
		requirement = function(profile)
			return profile.rewardTitleIds ~= nil and profile.rewardTitleIds.steady_dealer == true
		end,
	},
	{
		id = "solo_star",
		name = "Solo Star",
		icon = "🌟",
		title = "Solo Star",
		description = "Win a One Seat challenge run.",
		flavorText = "One helper was all the help you needed.",
		milestoneReward = true,
		requirement = function(profile)
			return profile.rewardTitleIds ~= nil and profile.rewardTitleIds.solo_star == true
		end,
	},
	{
		id = "careful_hands",
		name = "Careful Hands",
		icon = "🔮",
		title = "Careful Hands",
		description = "Win a Glass Deck challenge run.",
		flavorText = "You handled every card like glass.",
		milestoneReward = true,
		requirement = function(profile)
			return profile.rewardTitleIds ~= nil and profile.rewardTitleIds.careful_hands == true
		end,
	},
	{
		id = "quick_draw",
		name = "Quick Draw",
		icon = "⏱️",
		title = "Quick Draw",
		description = "Win a Speed Run challenge run.",
		flavorText = "The candles had barely burned down.",
		milestoneReward = true,
		requirement = function(profile)
			return profile.rewardTitleIds ~= nil and profile.rewardTitleIds.quick_draw == true
		end,
	},
	{
		id = "coin_keeper",
		name = "Coin Keeper",
		icon = "👛",
		title = "Coin Keeper",
		description = "Win a Tight Wallet challenge run.",
		flavorText = "You made every coin count twice.",
		milestoneReward = true,
		requirement = function(profile)
			return profile.rewardTitleIds ~= nil and profile.rewardTitleIds.coin_keeper == true
		end,
	},
	-- STORE TITLE: granted (and saved in profile.rewardTitleIds) by the Starter Pack (Engine/Store.lua).
	{
		id = "founding_guest",
		name = "Founding Guest",
		icon = "🏮",
		title = "Founding Guest",
		description = "Part of the Starter Pack.",
		flavorText = "You were here when the first lanterns were lit.",
		milestoneReward = true,
		requirement = function(profile)
			return profile.rewardTitleIds ~= nil and profile.rewardTitleIds.founding_guest == true
		end,
	},
	-- LIVE EVENT TITLE: a limited reward from Engine/LiveEvents.lua (The Founders' Feast), kept for good once claimed.
	{
		id = "feast_guest",
		name = "Feast Guest",
		icon = "🍲",
		title = "Feast Guest",
		description = "Claimed during The Founders' Feast.",
		flavorText = "You sat at the long table when the first stew was served.",
		milestoneReward = true,
		requirement = function(profile)
			return profile.rewardTitleIds ~= nil and profile.rewardTitleIds.feast_guest == true
		end,
	},
	-- MAP BONUS TITLES: granted by Engine/BiomeRewards.lua when every stop of a biome has been seen.
	{
		id = "dune_wanderer",
		name = "Dune Wanderer",
		icon = "🏜",
		title = "Dune Wanderer",
		description = "A Map reward: see every stop of the Golden Dunes.",
		flavorText = "Sand in your boots, a smile on your face.",
		milestoneReward = true,
		requirement = function(profile)
			return profile.rewardTitleIds ~= nil and profile.rewardTitleIds.dune_wanderer == true
		end,
	},
	{
		id = "marsh_wader",
		name = "Marsh Wader",
		icon = "🐸",
		title = "Marsh Wader",
		description = "A Map reward: see every stop of the Misty Marsh.",
		flavorText = "Knows which lily pads hold your weight.",
		milestoneReward = true,
		requirement = function(profile)
			return profile.rewardTitleIds ~= nil and profile.rewardTitleIds.marsh_wader == true
		end,
	},
	{
		id = "snow_scout",
		name = "Snow Scout",
		icon = "❄",
		title = "Snow Scout",
		description = "A Map reward: see every stop of the Frosty Hills.",
		flavorText = "Leaves the neatest footprints in the whole valley.",
		milestoneReward = true,
		requirement = function(profile)
			return profile.rewardTitleIds ~= nil and profile.rewardTitleIds.snow_scout == true
		end,
	},
	{
		id = "lighthouse_friend",
		name = "Lighthouse Friend",
		icon = "🗼",
		title = "Lighthouse Friend",
		description = "A Map reward: see every stop of the Lantern Coast.",
		flavorText = "The lamp keeper always saves you a warm seat.",
		milestoneReward = true,
		requirement = function(profile)
			return profile.rewardTitleIds ~= nil and profile.rewardTitleIds.lighthouse_friend == true
		end,
	},
	{
		id = "trailblazer",
		name = "Trailblazer",
		icon = "🧭",
		title = "Trailblazer",
		description = "A Map reward: see every region of the world.",
		flavorText = "Every road on the map has felt your footsteps.",
		milestoneReward = true,
		requirement = function(profile)
			return profile.rewardTitleIds ~= nil and profile.rewardTitleIds.trailblazer == true
		end,
	},
	-- SEASONAL TITLE (Engine/Seasons.lua): granted into rewardTitleIds by Seasons.recordProgress.
	{
		id = "lantern_keeper",
		name = "Lantern Keeper",
		icon = "🏮",
		title = "Lantern Keeper",
		description = "A seasonal reward: clear 3 Nights in one run during Winter Lanterns.",
		flavorText = "Keeps the lanterns lit through the longest nights.",
		milestoneReward = true,
		seasonal = true,
		requirement = function(profile)
			return profile.rewardTitleIds ~= nil and profile.rewardTitleIds.lantern_keeper == true
		end,
	},
	-- BIOME COMPLETION TITLES (Engine/BiomeRewards.lua): first clear, and Master (a won run through the biome).
	{
		id = "meadow_walker",
		name = "Meadow Walker",
		icon = "🌼",
		title = "Meadow Walker",
		description = "A Map reward: reach the end of the Wildflower Meadow road for the first time.",
		flavorText = "Knows every flower by its first name.",
		milestoneReward = true,
		requirement = function(profile)
			return profile.rewardTitleIds ~= nil and profile.rewardTitleIds.meadow_walker == true
		end,
	},
	{
		id = "meadow_master",
		name = "Meadow Master",
		icon = "🌻",
		title = "Meadow Master",
		description = "A Map reward: win a run that travels through the Wildflower Meadow.",
		flavorText = "The bees wave when you pass.",
		milestoneReward = true,
		requirement = function(profile)
			return profile.rewardTitleIds ~= nil and profile.rewardTitleIds.meadow_master == true
		end,
	},
	{
		id = "river_crosser",
		name = "River Crosser",
		icon = "🌉",
		title = "River Crosser",
		description = "A Map reward: reach the end of the Willow River road for the first time.",
		flavorText = "Never once wobbled on the stepping stones.",
		milestoneReward = true,
		requirement = function(profile)
			return profile.rewardTitleIds ~= nil and profile.rewardTitleIds.river_crosser == true
		end,
	},
	{
		id = "river_master",
		name = "River Master",
		icon = "🐟",
		title = "River Master",
		description = "A Map reward: win a run that travels through the Willow River.",
		flavorText = "The willows bow as you cross.",
		milestoneReward = true,
		requirement = function(profile)
			return profile.rewardTitleIds ~= nil and profile.rewardTitleIds.river_master == true
		end,
	},
	{
		id = "peak_climber",
		name = "Peak Climber",
		icon = "⛰",
		title = "Peak Climber",
		description = "A Map reward: reach the end of the Mountain Peaks road for the first time.",
		flavorText = "Has a very good view and says so.",
		milestoneReward = true,
		requirement = function(profile)
			return profile.rewardTitleIds ~= nil and profile.rewardTitleIds.peak_climber == true
		end,
	},
	{
		id = "peak_master",
		name = "Peak Master",
		icon = "🏔",
		title = "Peak Master",
		description = "A Map reward: win a run that travels through the Mountain Peaks.",
		flavorText = "The mountain keeps a spot warm for you.",
		milestoneReward = true,
		requirement = function(profile)
			return profile.rewardTitleIds ~= nil and profile.rewardTitleIds.peak_master == true
		end,
	},
	{
		id = "dune_crosser",
		name = "Dune Crosser",
		icon = "🏜",
		title = "Dune Crosser",
		description = "A Map reward: reach the end of the Golden Dunes road for the first time.",
		flavorText = "Sand in every pocket, a map in every hand.",
		milestoneReward = true,
		requirement = function(profile)
			return profile.rewardTitleIds ~= nil and profile.rewardTitleIds.dune_crosser == true
		end,
	},
	{
		id = "dune_master",
		name = "Dune Master",
		icon = "🐪",
		title = "Dune Master",
		description = "A Map reward: win a run that travels through the Golden Dunes.",
		flavorText = "The dunes shift to make way for you.",
		milestoneReward = true,
		requirement = function(profile)
			return profile.rewardTitleIds ~= nil and profile.rewardTitleIds.dune_master == true
		end,
	},
	{
		id = "marsh_strider",
		name = "Marsh Strider",
		icon = "🐸",
		title = "Marsh Strider",
		description = "A Map reward: reach the end of the Misty Marsh road for the first time.",
		flavorText = "Hops from plank to plank without a splash.",
		milestoneReward = true,
		requirement = function(profile)
			return profile.rewardTitleIds ~= nil and profile.rewardTitleIds.marsh_strider == true
		end,
	},
	{
		id = "marsh_master",
		name = "Marsh Master",
		icon = "🪷",
		title = "Marsh Master",
		description = "A Map reward: win a run that travels through the Misty Marsh.",
		flavorText = "The fireflies light your way.",
		milestoneReward = true,
		requirement = function(profile)
			return profile.rewardTitleIds ~= nil and profile.rewardTitleIds.marsh_master == true
		end,
	},
	{
		id = "snow_trekker",
		name = "Snow Trekker",
		icon = "❄",
		title = "Snow Trekker",
		description = "A Map reward: reach the end of the Frosty Hills road for the first time.",
		flavorText = "Leaves the deepest, happiest footprints.",
		milestoneReward = true,
		requirement = function(profile)
			return profile.rewardTitleIds ~= nil and profile.rewardTitleIds.snow_trekker == true
		end,
	},
	{
		id = "snow_master",
		name = "Snow Master",
		icon = "⛄",
		title = "Snow Master",
		description = "A Map reward: win a run that travels through the Frosty Hills.",
		flavorText = "The snowflakes line up to greet you.",
		milestoneReward = true,
		requirement = function(profile)
			return profile.rewardTitleIds ~= nil and profile.rewardTitleIds.snow_master == true
		end,
	},
	{
		id = "cove_sailor",
		name = "Cove Sailor",
		icon = "⛵",
		title = "Cove Sailor",
		description = "A Map reward: reach the end of the Lantern Coast road for the first time.",
		flavorText = "Waves at every lighthouse, and they wave back.",
		milestoneReward = true,
		requirement = function(profile)
			return profile.rewardTitleIds ~= nil and profile.rewardTitleIds.cove_sailor == true
		end,
	},
	{
		id = "coast_master",
		name = "Coast Master",
		icon = "🌊",
		title = "Coast Master",
		description = "A Map reward: win a run that travels through the Lantern Coast.",
		flavorText = "The tide times itself to suit you.",
		milestoneReward = true,
		requirement = function(profile)
			return profile.rewardTitleIds ~= nil and profile.rewardTitleIds.coast_master == true
		end,
	},
	{
		id = "tavern_guest",
		name = "Tavern Guest",
		icon = "🏠",
		title = "Tavern Guest",
		description = "A Map reward: reach the end of the Tavern road for the first time.",
		flavorText = "Always gets the best seat by the fire.",
		milestoneReward = true,
		requirement = function(profile)
			return profile.rewardTitleIds ~= nil and profile.rewardTitleIds.tavern_guest == true
		end,
	},
	{
		id = "tavern_master",
		name = "Tavern Master",
		icon = "🎉",
		title = "Tavern Master",
		description = "A Map reward: win a run that travels through the Tavern.",
		flavorText = "Welcome home, champion.",
		milestoneReward = true,
		requirement = function(profile)
			return profile.rewardTitleIds ~= nil and profile.rewardTitleIds.tavern_master == true
		end,
	},
	{
		id = "night_walker",
		name = "Night Walker",
		icon = "🌠",
		title = "Night Walker",
		description = "A Journey reward: clear Endless Night 10.",
		flavorText = "Past the eighth night, the road keeps going.",
		milestoneReward = true,
		requirement = function(profile)
			return profile.rewardTitleIds ~= nil and profile.rewardTitleIds.night_walker == true
		end,
	},
	{
		id = "endless_legend",
		name = "Endless Legend",
		icon = "🌌",
		title = "Endless Legend",
		description = "A Journey reward: clear Endless Night 20.",
		flavorText = "The story of this table never ends.",
		milestoneReward = true,
		requirement = function(profile)
			return profile.rewardTitleIds ~= nil and profile.rewardTitleIds.endless_legend == true
		end,
	},
}

-- SECOND WAVE (30): all computed from monotonic profile fields, so they stay stateless like the rest.
-- Themes: hands, runs, stakes, Endless, daily streaks, quests, rank, bosses, challenges, collection, exploration.
-- Every one has a title (prompts in tools/patron_art/prompts.json `title_subjects`, art ids recorded later).
local function countOf(t)
	local n = 0
	if type(t) == "table" then
		for _ in pairs(t) do n = n + 1 end
	end
	return n
end
local function bestEndless(profile)
	local best = 0
	for _, night in pairs(profile.endlessBestByStake or {}) do
		if type(night) == "number" and night > best then best = night end
	end
	return best
end
local function stat(profile, key) return (profile.stats and profile.stats[key]) or 0 end

-- Rarity of the wave (explicit, edit me; anything not listed is common). Harder goal, higher tier.
local WAVE_RARITY = {
	fifty_runs = "uncommon", stake_four = "uncommon", endless_fifteen = "uncommon", streak_seven = "uncommon",
	quests_twentyfive = "uncommon", rank_ten = "uncommon", hand_five_hundred = "uncommon",
	hand_thousand = "rare", stake_six = "rare", streak_fourteen = "rare", rank_fifteen = "rare",
	rush_six = "rare", challenge_many = "rare", endless_thirty = "rare",
	welcoming_host = "uncommon", tavern_ambassador = "epic",
	stake_eight = "epic", streak_thirty = "epic", quests_hundred = "epic", hand_two_thousand = "epic",
}

local function addWave(id, name, icon, title, description, flavorText, requirement)
	table.insert(Achievements.Definitions, {
		id = id, name = name, icon = icon, title = title, rarity = WAVE_RARITY[id] or "common",
		description = description, flavorText = flavorText, requirement = requirement,
	})
end

-- hands and runs
addWave("hand_hundred", "Hundred Hands", "🃏", "Hand Hundred", "Play 100 hands.", "The cards are warm from your fingers.",
	function(p) return stat(p, "handsPlayedTotal") >= 100 end)
addWave("hand_five_hundred", "Card Shark Pup", "🦈", "Card Shark Pup", "Play 500 hands.", "You shuffle in your sleep now.",
	function(p) return stat(p, "handsPlayedTotal") >= 500 end)
addWave("hand_two_thousand", "Dealer Supreme", "🎩", "Dealer Supreme", "Play 2000 hands.", "The deck knows your name.",
	function(p) return stat(p, "handsPlayedTotal") >= 2000 end)
addWave("ten_runs", "Familiar Face", "🙂", "Familiar Face", "Start 10 runs.", "The keeper nods when you walk in.",
	function(p) return stat(p, "runsStarted") >= 10 end)
addWave("fifty_runs", "Tavern Fixture", "🪑", "Tavern Fixture", "Start 50 runs.", "Your stool has your name on it.",
	function(p) return stat(p, "runsStarted") >= 50 end)
-- stakes
addWave("stake_two", "Rowdier Crowd", "📈", "Crowd Pleaser", "Unlock stake 2.", "The crowd wants a better show.",
	function(p) return (p.highestStakeUnlocked or 1) >= 2 end)
addWave("stake_four", "Rush Hour Regular", "⏰", "Rush Hour Regular", "Unlock stake 4.", "Busy nights are your kind of night.",
	function(p) return (p.highestStakeUnlocked or 1) >= 4 end)
addWave("stake_six", "Packed House Pro", "🎪", "Packed House Pro", "Unlock stake 6.", "Standing room only, and you still shine.",
	function(p) return (p.highestStakeUnlocked or 1) >= 6 end)
addWave("stake_eight", "Closing Time Hero", "🌟", "Closing Time Hero", "Unlock stake 8.", "The last lantern is yours to blow out.",
	function(p) return (p.highestStakeUnlocked or 1) >= 8 end)
-- Endless Nights
addWave("endless_twelve", "Past the Ninth", "🌒", "Past the Ninth", "Reach Night 12.", "The map ran out, the road did not.",
	function(p) return stat(p, "bestNightReached") >= 12 end)
addWave("endless_fifteen", "Long Haul", "🧭", "Long Haul", "Reach Night 15 in any run.", "You stopped counting the lanterns.",
	function(p) return math.max(stat(p, "bestNightReached"), bestEndless(p)) >= 15 end)
addWave("endless_thirty", "Marathon Keeper", "♾️", "Marathon Keeper", "Reach Night 30 in Endless.", "Dawn came and went. You stayed.",
	function(p) return math.max(stat(p, "bestNightReached"), bestEndless(p)) >= 30 end)
-- daily streaks
addWave("streak_three", "Three Day Guest", "📅", "Three Day Guest", "Visit three days in a row.", "Back again, and glad of it.",
	function(p) return (p.bestLoginStreak or 0) >= 3 end)
addWave("streak_seven", "Week at the Table", "🗓️", "Week at the Table", "Visit seven days in a row.", "A whole week of warm welcomes.",
	function(p) return (p.bestLoginStreak or 0) >= 7 end)
addWave("streak_fourteen", "Fortnight Friend", "🔥", "Fortnight Friend", "Visit fourteen days in a row.", "The fire stays lit for you.",
	function(p) return (p.bestLoginStreak or 0) >= 14 end)
addWave("streak_thirty", "Moon After Moon", "🌕", "Moon After Moon", "Visit thirty days in a row.", "A full moon of mornings.",
	function(p) return (p.bestLoginStreak or 0) >= 30 end)
-- quests and rank
addWave("quests_five", "Errand Runner", "📜", "Errand Runner", "Finish 5 daily quests.", "Small jobs, tidy work.",
	function(p) return (p.questsDone or 0) >= 5 end)
addWave("quests_twentyfive", "Quest Regular", "🗒️", "Quest Regular", "Finish 25 daily quests.", "The board is never empty when you are around.",
	function(p) return (p.questsDone or 0) >= 25 end)
addWave("quests_hundred", "Board Master", "🏅", "Board Master", "Finish 100 daily quests.", "You could read the quest board blindfolded.",
	function(p) return (p.questsDone or 0) >= 100 end)
addWave("rank_five", "Rising Host", "⭐", "Rising Host", "Reach Tavern Rank 5.", "Word of your table is spreading.",
	function(p) return (p.tavernRank or 1) >= 5 end)
addWave("rank_fifteen", "Beloved Host", "💛", "Beloved Host", "Reach Tavern Rank 15.", "Everyone asks for your table.",
	function(p) return (p.tavernRank or 1) >= 15 end)
-- bosses and challenges
addWave("rush_three", "Boss Dodger", "🥊", "Boss Dodger", "Beat 3 bosses in one Boss Rush.", "Three big guests, three polite goodbyes.",
	function(p) return (p.bossRushBest or 0) >= 3 end)
addWave("rush_six", "Boss Wrangler", "🐂", "Boss Wrangler", "Beat 6 bosses in one Boss Rush.", "Even the grumpy ones tip their hats.",
	function(p) return (p.bossRushBest or 0) >= 6 end)
addWave("challenge_first", "Twist Taker", "🌀", "Twist Taker", "Clear a challenge run.", "You like your nights with a twist.",
	function(p) return countOf(p.challengesCleared) >= 1 end)
addWave("challenge_many", "Twist Master", "🎭", "Twist Master", "Clear 4 different challenge runs.", "No twist can surprise you now.",
	function(p) return countOf(p.challengesCleared) >= 4 end)
-- collection and exploration
addWave("rank_ten", "Trusted Host", "🧡", "Trusted Host", "Reach Tavern Rank 10.", "Regulars save your table a seat.",
	function(p) return (p.tavernRank or 1) >= 10 end)
addWave("hat_trick", "Hat Trick", "🎩", "Hat Trick", "Win 3 runs.", "Three nights, three cheers.",
	function(p) return stat(p, "runsWon") >= 3 end)
addWave("hand_thousand", "Thousand Hands", "🎴", "Thousand Hands", "Play 1000 hands.", "A thousand hands, a thousand little stories.",
	function(p) return stat(p, "handsPlayedTotal") >= 1000 end)
addWave("map_spots", "Corner Peeker", "🔍", "Corner Peeker", "Find 3 hidden spots on the Tavern Map.", "You always check behind the barrel.",
	function(p) return countOf(p.discoveries) >= 3 end)
-- Tavern Season titles (Engine/SeasonTrack.lua tier 25): granted into rewardTitleIds when the tier is claimed
local function seasonTitle(id, name, icon, flavor)
	table.insert(Achievements.Definitions, {
		id = id, name = name, icon = icon, title = name, rarity = "epic", milestoneReward = true,
		description = "A Tavern Season reward: reach tier 25 of the season.", flavorText = flavor,
		requirement = function(p) return p.rewardTitleIds ~= nil and p.rewardTitleIds[id] == true end,
	})
end
seasonTitle("season_harvest_moon", "Harvest Regular", "🌕", "You were there when the lanterns lit the fields.")
seasonTitle("season_winter_welcome", "Winter Regular", "🧣", "You kept the fire going all winter.")
-- Collection completion titles (Engine/CollectionRewards.lua, 100 percent of a group): granted into rewardTitleIds on claim
for _, spec in ipairs({
	{ "book_patrons", "Patron Whisperer", "🧑‍🍳", "Every Patron has sat at your table." },
	{ "book_recipes", "Master Cook", "📖", "Not one recipe is a mystery to you." },
	{ "book_bosses", "Giant Tamer", "👑", "Every big guest has shaken your hand." },
	{ "book_sets", "Table Dresser", "🎴", "Every table in the tavern wears your colors." },
	{ "book_titles", "Title Hoarder", "🏷️", "You have a name for every occasion." },
	{ "book_badges", "Badge Collector", "🏅", "Your sash has no room left." },
}) do
	local id = spec[1]
	table.insert(Achievements.Definitions, {
		id = id, name = spec[2], icon = spec[3], title = spec[2], rarity = "legendary", milestoneReward = true,
		description = "A Collection reward: complete this part of the Collection.", flavorText = spec[4],
		requirement = function(p) return p.rewardTitleIds ~= nil and p.rewardTitleIds[id] == true end,
	})
end
-- Legend prestige titles (Engine/Legend.lua levels 1, 5 and 9): granted into rewardTitleIds
for _, spec in ipairs({
	{ "legend_1", "Legend", "👑", "legendary", "You cleared the hardest night." },
	{ "legend_5", "Living Legend", "🌟", "legendary", "Stories about you are told at every table." },
	{ "legend_9", "Legend of Legends", "🏆", "mythical", "Even the Keeper tips a hat to you." },
}) do
	local id = spec[1]
	table.insert(Achievements.Definitions, {
		id = id, name = spec[2], icon = spec[3], title = spec[2], rarity = spec[4], milestoneReward = true,
		description = "A Legend reward: climb the Legend levels after stake 8.", flavorText = spec[5],
		requirement = function(p) return p.rewardTitleIds ~= nil and p.rewardTitleIds[id] == true end,
	})
end
-- invites (Engine/Invites.lua): distinct friends who joined through your invite
addWave("welcoming_host", "Welcoming Host", "💌", "Welcoming Host", "Bring 3 friends in through an invite.", "The door is open and the lanterns are lit.",
	function(p) return (p.invitesAccepted or 0) >= 3 end)
addWave("tavern_ambassador", "Tavern Ambassador", "🎺", "Tavern Ambassador", "Bring 10 friends in through an invite.", "Half the town knows your table.",
	function(p) return (p.invitesAccepted or 0) >= 10 end)
addWave("nights_cleared", "Road Regular", "🛤️", "Road Regular", "Clear 4 different Nights.", "The road knows your footsteps.",
	function(p) return countOf(p.clearedNightIds) >= 4 end)

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
