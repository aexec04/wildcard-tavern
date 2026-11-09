--[[
	PlayerProfile.lua
	PERSISTENT SAVE (Phase 10): the permanent, cross-run part of a player's
	progress -- everything that should survive "New Run...", a rejoin, or a
	server restart, as opposed to `RunState` (Shared/Engine/RunState.lua),
	which is deliberately scoped to a single run and thrown away when that
	run ends or restarts.

	What lives here, and why each one needed this file to exist at all:
	  - `discoveredPatronIds` -- every Patron id ever owned in ANY run. Before
	    this, Client/Collection.lua's "Collection" screen only ever showed
	    the CURRENT run's `ownedPatrons` (see that file's old title,
	    "Collection -- this run") -- so finding a rare Patron, then starting
	    a fresh run, made it look undiscovered again. Patrons themselves
	    still correctly reset every run (that's the roguelike loop, not a
	    bug) -- this just remembers that you'd found it before.
	  - `ownedSetIds` / `equippedSetId` -- Cosmetic Sets (CosmeticSets.lua):
	    Tips-bought set ids, and the equipped set (falls back to the default
	    if missing, unknown or locked). Old `ownedThemeIds`/`equippedTheme`
	    are ignored by `migrate`. `equippedCardBackId` is an optional
	    separate card back pick (nil = the set's back).
	  - `stats` -- a few small permanent numbers (runs started/won, best
	    Night reached) for the Collection screen to show alongside the
	    discovered-Patron grid. Deliberately minimal -- this is not a
	    full stats/leaderboard system, just enough to answer "have I ever
	    actually won a run, and how far did I get."
	  - `hasSeenTutorial` -- TUTORIAL (Phase 16): flips true the first time
	    this player dismisses (or skips) the first-time-player walkthrough
	    (Client/Tutorial.lua) -- lets the client auto-show it exactly once
	    ever, for a genuinely brand-new player, without it ever popping up
	    again on a later run/rejoin. Manually reopenable any time from the
	    menu regardless of this flag -- this only gates the AUTOMATIC
	    first-time popup.
	  - `equippedTitleId` -- ACHIEVEMENTS + TITLES (Phase 16): which of
	    Shared/Engine/Achievements.lua's titles this player has chosen to
	    show off, or nil for none equipped. This is the one piece of the
	    achievements feature that actually needs saving -- which
	    achievements are UNLOCKED is deliberately never stored (see
	    Achievements.lua's header for why that's safe to just recompute
	    from `stats`/discoveredPatronIds every time) -- but
	    which one you've chosen to WEAR is a real, unrecoverable player
	    choice, so it's the only new field this file needed to gain.

	Deliberately NOT covered by this file (a scope decision, not an
	oversight): an in-progress RUN itself. Closing the game mid-run still
	loses that run, exactly like before -- resuming a run from a checkpoint
	would mean persisting the entire live RunState (deck/hand/rng/etc), which
	is a much bigger, riskier undertaking than remembering what's been
	discovered. If that's ever wanted, it's a separate, deliberately-scoped
	future phase.

	Pure Lua, no Roblox APIs -- same reasoning as every other Shared/Engine
	module: testable with plain `lua5.3`, no Studio required. The actual
	DataStoreService calls (which DO need Roblox) live in
	Server/init.server.lua; this file only ever touches plain Lua tables.
]]

local Achievements = require(script.Parent.Achievements) -- ACHIEVEMENTS + TITLES, Phase 16
local CosmeticSets = require(script.Parent.CosmeticSets)
local CardBacks = require(script.Parent.CardBacks)
local JourneyMap = require(script.Parent.JourneyMap)
local WorldMap = require(script.Parent.WorldMap)
local Keys = require(script.Parent.Keys) -- locked roads on the world map
local Badges = require(script.Parent.Badges)
local Stakes = require(script.Parent.Stakes) -- difficulty ladder
local Unlocks = require(script.Parent.Unlocks) -- unlock drip
local TavernRank = require(script.Parent.TavernRank) -- account level
local Quests = require(script.Parent.Quests) -- daily quests

local PlayerProfile = {}

-- Bumped only if the SHAPE of a saved profile ever needs to change in a way
-- `migrate` can't already absorb (e.g. renaming a field). Not used for
-- anything yet -- present so a future migration has somewhere to branch on.
PlayerProfile.SCHEMA_VERSION = 1

-- Player settings (Settings panel + volume popup). Each entry is the
-- default plus the rule a saved/client-sent value must pass. Profiles
-- saved before settings existed have no `settings` table and get these
-- defaults; musicVolume 0.35 matches the old session-only starting volume.
PlayerProfile.SETTING_SPECS = {
	musicVolume = { default = 0.35, kind = "fraction" },
	sfxVolume = { default = 1, kind = "fraction" },
	muted = { default = false, kind = "boolean" },
	animSpeed = { default = "normal", kind = "choice", choices = { normal = true, fast = true } },
	reduceShake = { default = false, kind = "boolean" },
	colorblindSuits = { default = false, kind = "boolean" },
	confirmDiscard = { default = false, kind = "boolean" },
	-- accessibility and comfort (Engine/Accessibility.lua)
	reduceFlashing = { default = false, kind = "boolean" },
	reduceMotion = { default = false, kind = "boolean" },
	largerText = { default = false, kind = "boolean" },
	holdConfirmSeconds = { default = 1.5, kind = "range", min = 0.5, max = 3 },
}

-- Animation pace divisors. The free "fast" speed is milder than the
-- Fast Forward Game Pass, which upgrades "fast" to the full speed-up.
PlayerProfile.FAST_PACE_DIVISOR = 1.35
PlayerProfile.FAST_FORWARD_PACE_DIVISOR = 1.8

function PlayerProfile.defaultSettings()
	local settings = {}
	for key, spec in pairs(PlayerProfile.SETTING_SPECS) do
		settings[key] = spec.default
	end
	return settings
end

-- Returns the cleaned value, or nil if `value` isn't valid for `key`.
local function cleanSetting(key, value)
	local spec = PlayerProfile.SETTING_SPECS[key]
	if not spec then
		return nil
	end
	if spec.kind == "fraction" then
		if type(value) ~= "number" or value ~= value then
			return nil
		end
		return math.max(0, math.min(1, value))
	elseif spec.kind == "boolean" then
		if type(value) ~= "boolean" then
			return nil
		end
		return value
	elseif spec.kind == "range" then
		if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
			return nil
		end
		return math.floor(math.max(spec.min, math.min(spec.max, value)) * 10 + 0.5) / 10
	elseif spec.kind == "choice" then
		if type(value) ~= "string" or not spec.choices[value] then
			return nil
		end
		return value
	end
	return nil
end

-- COLLECTION: [id] = true sets copied as-is by migrate.
PlayerProfile.ID_SET_FIELDS = {
	"discoveredRecipeIds",
	"discoveredBossIds",
	"discoveredHousePassIds",
	"claimedMilestoneIds",
	"rewardTitleIds",
	"unlockedCardBackIds",
	"seasonRewardIds", -- [Seasons id] = true, seasonal rewards already earned (Engine/Seasons.lua)
}

-- Which saved set each Collection tab's discoveries go into.
PlayerProfile.DISCOVERY_FIELDS = {
	patrons = "discoveredPatronIds",
	recipes = "discoveredRecipeIds",
	bosses = "discoveredBossIds",
	housePasses = "discoveredHousePassIds",
}

local function copyIdSet(rawSet, into)
	if type(rawSet) ~= "table" then
		return
	end
	for id, flag in pairs(rawSet) do
		if type(id) == "string" and flag == true then
			into[id] = true
		end
	end
end

-- What a player who has never been saved before starts with.
function PlayerProfile.new()
	return {
		version = PlayerProfile.SCHEMA_VERSION,
		discoveredPatronIds = {}, -- [patronId] = true
		-- COLLECTION: the other discovered sets (see CollectionBook.Tabs).
		discoveredRecipeIds = {}, -- [recipeId] = true
		discoveredBossIds = {}, -- [bossRoundId] = true
		discoveredHousePassIds = {}, -- [housePassId] = true
		claimedMilestoneIds = {}, -- [CollectionBook.Milestones id] = true
		rewardTitleIds = {}, -- [Achievements id] = true, titles granted by milestones
		unlockedCardBackIds = {}, -- [CardBacks id] = true
		seasonRewardIds = {}, -- [Seasons id] = true
		seasonId = nil, -- Tavern Season track (Engine/SeasonTrack.lua): the season the next two fields belong to
		seasonXp = 0,
		seasonClaimed = {}, -- [tier] = true
		ownedSetIds = {}, -- [CosmeticSets id] = true: Tips-bought or Journey-reward sets
		clearedNightIds = {}, -- [night number] = true, first clears of Nights 1-8 and Endless milestone Nights (JourneyMap)
		-- WORLD MAP (Engine/WorldMap.lua): the road of the current/last run, every stop ever seen (map memory
		-- and fog), how many Night stops of each region were cleared, and the biome rewards already granted.
		worldRoute = {}, -- array of WorldMap stop ids
		worldSeenStopIds = {}, -- [stop id] = true
		worldBiomeClears = {}, -- [region id] = count
		worldRewardIds = {}, -- [reward row id] = true (granted once, step 4)
		compassCharges = 0, -- 0 to PlayerProfile.MAX_COMPASS_CHARGES, earned by winning map minigames, spent at a fork
		keys = 0, -- Keys (Engine/Keys.lua): +1 per run win and per first biome clear, one opens a locked road for good
		unlockedRoadIds = {}, -- [stop id] = true, roads opened with a Key
		highestStakeUnlocked = 1, -- Engine/Stakes.lua: the highest stake a run may start on
		stakeStamps = {}, -- [region id] = highest stake won on a run through that road
		endlessBestByStake = {}, -- [stake number as text] = best Endless Night reached on that stake
		unlockedContent = {}, -- ["patron:id" / "recipe:id"] = true, gated content already opened (Engine/Unlocks.lua)
		badgeIds = {}, -- [Badges id] = true, earned once (Engine/Badges.lua)
		equippedBadgeId = nil, -- one Badges id shown beside the name on leaderboards and the results screen
		minigameWins = 0, -- map minigames won (feeds the minigame badges)
		equippedSetId = CosmeticSets.DefaultId,
		equippedCardBackId = nil, -- a CardBacks id, or nil = use the equipped set's back
		stats = {
			runsStarted = 0,
			runsAbandoned = 0, -- runs given up from Settings > Restart Run
			runsWon = 0,
			bestNightReached = 0,
			handsPlayedTotal = 0, -- hands played over all runs (feeds the unlock drip)
		},
		equippedTitleId = nil, -- ACHIEVEMENTS + TITLES (Phase 16): an Achievements.Definitions id, or nil for no title equipped
		hasSeenTutorial = false, -- TUTORIAL (Phase 16)
		hasSeenHighCardHint = false, -- see Onboarding.shouldShowHighCardHint
		freeContinueDateKey = nil, -- ONE MORE ROUND: SeededRng.dailyDateKey() of the day the free daily continue was last used, see hasFreeContinue
		-- LOGIN STREAK (Engine/LoginStreak.lua)
		lastLoginDay = nil, -- UTC day number of the last check-in
		loginStreak = 0,
		bestLoginStreak = 0, -- longest login streak ever (Engine/Achievements reads it; never goes down)
		claimedLoginDays = {}, -- [reward day] = true
		loginClaimedDay = nil, -- the lastLoginDay whose ladder reward was claimed (Engine/LoginStreak.lua)
		-- TAVERN RANK (Engine/TavernRank.lua)
		tavernXp = 0,
		tavernRank = 1,
		pendingStartTips = 0, -- Tips banked for the next normal run
		rankRewardIds = {}, -- [rank] = true, rewards already granted
		lastFirstWinDay = nil, -- UTC day of the last first-win-of-the-day XP bonus
		-- DAILY QUESTS (Engine/Quests.lua)
		quests = nil, -- { day, ids, progress, done } for today
		questsDone = 0,
		-- MAP DISCOVERIES (Engine/Discoveries.lua)
		discoveries = {}, -- [spot id] = true, claimed
		discoveryRevealed = {}, -- [region] = true, revealed with a compass charge
		merchantDiscount = 0, -- Tips off the first shop visit of the next normal run
		challengesCleared = {}, -- [challenge id] = true (Engine/Challenges.lua)
		bossRushBest = 0, -- most bosses beaten in one Boss Rush (Engine/BossRush.lua)
		invitesAccepted = 0, -- Engine/Invites.lua: distinct invitees credited
		inviteLedger = {}, -- [invitee userId as text] = true (idempotency record)
		inviteeRewardClaimed = false, -- the starter card back for arriving through an invite
		runHistory = {}, -- the last 20 finished runs, newest first (Engine/RunHistory.lua)
		lifetime = { bestHandScore = 0, tipsEarned = 0, bestNightByStake = {}, patronWins = {} }, -- Tavern Stats
		-- STORE (Engine/Store.lua)
		storePurchases = {}, -- [one-time item id] = true
		receiptIds = {}, -- recent Developer Product purchase ids, so a repeated receipt never grants twice
		vipBonusDay = nil, -- UTC day of the last VIP daily gift
		starterPrompted = false, -- the one-time Starter Pack prompt was shown
		equippedBadgeId2 = nil, -- VIP second badge slot
		liveEventClaims = {}, -- [event id] = true, rewards already claimed (Engine/LiveEvents.lua)
		liveEventsSeen = {}, -- [event id] = true, the News banner already reported to analytics
		-- FIRST 5 MINUTES (Engine/Funnel.lua, NextGoal.lua)
		funnelSeen = {}, -- [funnel step id] = true, each analytics funnel step is sent once per player
		tutorialRewardClaimed = false, -- the card back and the Newcomer title for finishing the tutorial
		firstWinRewardClaimed = false, -- the bigger first-win reward
		followPrompted = false, -- the one-time experience notifications prompt was already shown
		equippedBadge = nil, -- RUN SUMMARY badge (Engine/RunSummary.badgeFromSummary), or nil
		settings = PlayerProfile.defaultSettings(), -- see SETTING_SPECS
	}
end

-- Turns whatever DataStore handed back into a SAFE profile to actually use.
-- This is the one function standing between a corrupt/foreign/missing
-- DataStore entry and a hard crash elsewhere -- deliberately paranoid:
-- every field is independently type-checked and falls back to
-- PlayerProfile.new()'s default rather than trusting the raw shape. Handles
-- three cases the same way: a brand-new player (raw == nil), a player saved
-- before this feature existed (raw is some other shape or missing fields),
-- and a normal valid profile.
function PlayerProfile.migrate(raw)
	local profile = PlayerProfile.new()
	if type(raw) ~= "table" then
		return profile
	end

	if type(raw.discoveredPatronIds) == "table" then
		for id, owned in pairs(raw.discoveredPatronIds) do
			if type(id) == "string" and owned == true then
				profile.discoveredPatronIds[id] = true
			end
		end
	end

	-- COLLECTION: older profiles only have discoveredPatronIds (copied
	-- above), so the other sets start empty and fill in from the next run.
	for _, field in ipairs(PlayerProfile.ID_SET_FIELDS) do
		copyIdSet(raw[field], profile[field])
	end

	copyIdSet(raw.ownedSetIds, profile.ownedSetIds)
	if type(raw.clearedNightIds) == "table" then
		for night, flag in pairs(raw.clearedNightIds) do
			if type(night) == "number" and flag == true and night == math.floor(night)
				and (JourneyMap.Nights[night] or JourneyMap.getMilestone(night)) then
				profile.clearedNightIds[night] = true
			end
		end
	end
	-- WORLD MAP: only ids that exist in the current graph survive a load (content can be renamed freely).
	if type(raw.worldRoute) == "table" then
		local route = {}
		for i, id in ipairs(raw.worldRoute) do
			if type(id) ~= "string" or not WorldMap.Stops[id] then
				route = {}
				break
			end
			route[i] = id
		end
		if WorldMap.isValidRoute(route) then
			profile.worldRoute = route
		end
	end
	if type(raw.worldSeenStopIds) == "table" then
		for id, flag in pairs(raw.worldSeenStopIds) do
			if type(id) == "string" and flag == true and WorldMap.Stops[id] then
				profile.worldSeenStopIds[id] = true
			end
		end
	end
	if type(raw.worldBiomeClears) == "table" then
		for region, count in pairs(raw.worldBiomeClears) do
			if type(region) == "string" and WorldMap.Regions[region] and type(count) == "number" and count > 0 then
				profile.worldBiomeClears[region] = math.min(9999, math.floor(count))
			end
		end
	end
	copyIdSet(raw.worldRewardIds, profile.worldRewardIds)
	if type(raw.badgeIds) == "table" then
		for id, flag in pairs(raw.badgeIds) do
			if type(id) == "string" and flag == true and Badges.getById(id) then
				profile.badgeIds[id] = true -- unknown ids are dropped
			end
		end
	end
	if type(raw.minigameWins) == "number" and raw.minigameWins == raw.minigameWins then
		profile.minigameWins = math.max(0, math.min(99999, math.floor(raw.minigameWins)))
	end
	if type(raw.equippedBadgeId) == "string" and profile.badgeIds[raw.equippedBadgeId] then
		profile.equippedBadgeId = raw.equippedBadgeId -- only an owned badge stays equipped
	end
	-- UNLOCK DRIP: only keys of content that is still gated survive a load (content can be renamed freely).
	if type(raw.unlockedContent) == "table" then
		for k, flag in pairs(raw.unlockedContent) do
			local kind, id = tostring(k):match("^(%a+):(.+)$")
			if flag == true and kind and Unlocks.isGated(kind, id) then
				profile.unlockedContent[k] = true
			end
		end
	end
	profile.highestStakeUnlocked, profile.stakeStamps = Stakes.cleanSaved(raw.highestStakeUnlocked, raw.stakeStamps, function(region)
		return WorldMap.Regions[region] ~= nil
	end)
	if type(raw.endlessBestByStake) == "table" then
		for k, v in pairs(raw.endlessBestByStake) do
			local stake = tonumber(k)
			if stake and stake >= 1 and stake <= 8 and stake == math.floor(stake) and type(v) == "number" and v == v and v >= 1 and v <= 500 then
				profile.endlessBestByStake[tostring(stake)] = math.floor(v)
			end
		end
	end
	if type(raw.keys) == "number" and raw.keys == raw.keys then
		profile.keys = math.max(0, math.min(Keys.MAX_KEYS, math.floor(raw.keys)))
	end
	if type(raw.unlockedRoadIds) == "table" then
		local locked = {}
		for _, id in ipairs(Keys.lockedRoads()) do locked[id] = true end
		for id, flag in pairs(raw.unlockedRoadIds) do
			if type(id) == "string" and flag == true and locked[id] then -- unknown or free ids are dropped
				profile.unlockedRoadIds[id] = true
			end
		end
	end
	if type(raw.compassCharges) == "number" and raw.compassCharges == raw.compassCharges then
		profile.compassCharges = math.max(0, math.min(PlayerProfile.MAX_COMPASS_CHARGES, math.floor(raw.compassCharges)))
	end
	if type(raw.equippedSetId) == "string" and CosmeticSets.getById(raw.equippedSetId) then
		profile.equippedSetId = raw.equippedSetId
	end
	-- Whether the pick is still unlocked is checked when it's read
	-- (CosmeticSets.effectiveCardBackId), since it can depend on a Game Pass.
	if type(raw.equippedCardBackId) == "string" and CardBacks.getById(raw.equippedCardBackId) then
		profile.equippedCardBackId = raw.equippedCardBackId
	end

	if type(raw.stats) == "table" then
		local rawStats = raw.stats
		if type(rawStats.runsStarted) == "number" then
			profile.stats.runsStarted = math.max(0, math.floor(rawStats.runsStarted))
		end
		if type(rawStats.runsAbandoned) == "number" then
			profile.stats.runsAbandoned = math.max(0, math.floor(rawStats.runsAbandoned))
		end
		if type(rawStats.runsWon) == "number" then
			profile.stats.runsWon = math.max(0, math.floor(rawStats.runsWon))
		end
		if type(rawStats.bestNightReached) == "number" then
			profile.stats.bestNightReached = math.max(0, math.floor(rawStats.bestNightReached))
			end
			if type(rawStats.handsPlayedTotal) == "number" and rawStats.handsPlayedTotal == rawStats.handsPlayedTotal then
				profile.stats.handsPlayedTotal = math.max(0, math.min(99999999, math.floor(rawStats.handsPlayedTotal)))
		end
	end

	-- ACHIEVEMENTS + TITLES (Phase 16): validated AFTER everything above
	-- (discoveredPatronIds/stats) is already settled onto
	-- `profile`, since checking whether this title is still actually
	-- unlocked needs all of those. Deliberately just drops an
	-- invalid/no-longer-unlocked saved title rather than erroring --
	-- e.g. if a future balance change ever raised a requirement's
	-- threshold past what this player has, they'd simply need to
	-- re-equip once they qualify again, same as any other soft
	-- migration in this function.
	if type(raw.equippedTitleId) == "string" and Achievements.isUnlocked(profile, raw.equippedTitleId) then
		profile.equippedTitleId = raw.equippedTitleId
	end

	if raw.hasSeenTutorial == true then
		profile.hasSeenTutorial = true
	end

	if raw.hasSeenHighCardHint == true then
		profile.hasSeenHighCardHint = true
	end

	if type(raw.freeContinueDateKey) == "string" then
		profile.freeContinueDateKey = raw.freeContinueDateKey
	end

	if type(raw.lastLoginDay) == "number" and raw.lastLoginDay == raw.lastLoginDay and raw.lastLoginDay >= 0 then
		profile.lastLoginDay = math.floor(raw.lastLoginDay)
	end
	if type(raw.loginStreak) == "number" and raw.loginStreak == raw.loginStreak then
		profile.loginStreak = math.max(0, math.min(9999, math.floor(raw.loginStreak)))
	end
	if type(raw.bestLoginStreak) == "number" and raw.bestLoginStreak == raw.bestLoginStreak then
		profile.bestLoginStreak = math.max(0, math.min(9999, math.floor(raw.bestLoginStreak)))
	end
	profile.bestLoginStreak = math.max(profile.bestLoginStreak or 0, profile.loginStreak or 0)
	if type(raw.claimedLoginDays) == "table" then
		for day, flag in pairs(raw.claimedLoginDays) do
			if type(day) == "number" and flag == true then
				profile.claimedLoginDays[day] = true
			end
		end
	end

	local function wholeNumber(v, lo, hi)
		if type(v) == "number" and v == v then
			return math.max(lo, math.min(hi, math.floor(v)))
		end
		return nil
	end
	profile.loginClaimedDay = wholeNumber(raw.loginClaimedDay, 0, 1e9)
	profile.tavernXp = wholeNumber(raw.tavernXp, 0, TavernRank.MAX_XP) or 0
	profile.pendingStartTips = wholeNumber(raw.pendingStartTips, 0, TavernRank.MAX_PENDING_TIPS) or 0
	profile.lastFirstWinDay = wholeNumber(raw.lastFirstWinDay, 0, 1e9)
	profile.questsDone = wholeNumber(raw.questsDone, 0, 1e7) or 0
	if type(raw.rankRewardIds) == "table" then
		for rank, flag in pairs(raw.rankRewardIds) do
			if type(rank) == "number" and flag == true and TavernRank.Rewards[rank] then
				profile.rankRewardIds[rank] = true
			end
		end
	end
	profile.tavernRank = TavernRank.rankFor(profile.tavernXp)
	profile.funnelSeen = require(script.Parent.Funnel).clean(raw.funnelSeen)
	profile.challengesCleared = require(script.Parent.Challenges).cleanSaved(raw.challengesCleared)
	profile.bossRushBest = require(script.Parent.BossRush).cleanSaved(raw.bossRushBest)
	profile.runHistory, profile.lifetime = require(script.Parent.RunHistory).cleanSaved(raw.runHistory, raw.lifetime)
	require(script.Parent.Invites).cleanSaved(profile, raw)
	profile.seasonId, profile.seasonXp, profile.seasonClaimed = require(script.Parent.SeasonTrack).cleanSaved(raw.seasonId, raw.seasonXp, raw.seasonClaimed)
	profile.quickBest = require(script.Parent.RunHistory).cleanQuickBest(raw.quickBest) -- Quick Run personal best (Engine/RunModes.lua)
	profile.storePurchases, profile.receiptIds, profile.vipBonusDay = require(script.Parent.Store).cleanSaved(raw.storePurchases, raw.receiptIds, raw.vipBonusDay)
	profile.starterPrompted = raw.starterPrompted == true
	profile.liveEventClaims = require(script.Parent.LiveEvents).cleanSaved(raw.liveEventClaims)
	profile.liveEventsSeen = require(script.Parent.LiveEvents).cleanSaved(raw.liveEventsSeen)
	if type(raw.equippedBadgeId2) == "string" and profile.badgeIds[raw.equippedBadgeId2] then
		profile.equippedBadgeId2 = raw.equippedBadgeId2
	end
	profile.discoveries, profile.discoveryRevealed, profile.merchantDiscount =
		require(script.Parent.Discoveries).cleanSaved(raw.discoveries, raw.discoveryRevealed, raw.merchantDiscount)
	profile.tutorialRewardClaimed = raw.tutorialRewardClaimed == true
	profile.firstWinRewardClaimed = raw.firstWinRewardClaimed == true
	profile.followPrompted = raw.followPrompted == true
	if type(raw.quests) == "table" and wholeNumber(raw.quests.day, 0, 1e9) and type(raw.quests.ids) == "table" then
		local quests = { day = wholeNumber(raw.quests.day, 0, 1e9), ids = {}, progress = {}, done = {} }
		for _, id in ipairs(raw.quests.ids) do
			if type(id) == "string" and Quests.getById(id) then
				quests.ids[#quests.ids + 1] = id
			end
		end
		if #quests.ids == Quests.PER_DAY then
			for id, n in pairs(type(raw.quests.progress) == "table" and raw.quests.progress or {}) do
				if Quests.getById(id) and wholeNumber(n, 0, 1e6) then
					quests.progress[id] = wholeNumber(n, 0, 1e6)
				end
			end
			for id, flag in pairs(type(raw.quests.done) == "table" and raw.quests.done or {}) do
				if Quests.getById(id) and flag == true then
					quests.done[id] = true
				end
			end
			profile.quests = quests
		end
	end

	profile.equippedBadge = require(script.Parent.RunSummary).cleanBadge(raw.equippedBadge)

	-- Each setting is checked on its own; a missing or bad one keeps its default.
	if type(raw.settings) == "table" then
		for key in pairs(PlayerProfile.SETTING_SPECS) do
			local cleaned = cleanSetting(key, raw.settings[key])
			if cleaned ~= nil then
				profile.settings[key] = cleaned
			end
		end
	end

	JourneyMap.regrantRewards(profile)
	return profile
end

-- Safe to call straight off a remote handler. Returns (ok, message);
-- ok is false for an unknown key or a bad value, or when nothing changed
-- (so the caller can skip a save).
function PlayerProfile.setSetting(profile, key, value)
	if type(key) ~= "string" or not PlayerProfile.SETTING_SPECS[key] then
		return false, "Unknown setting"
	end
	local cleaned = cleanSetting(key, value)
	if cleaned == nil then
		return false, "Invalid value"
	end
	if profile.settings[key] == cleaned then
		return false, "Unchanged"
	end
	profile.settings[key] = cleaned
	return true, "Saved."
end

-- How much to divide animation durations by (1 = normal speed).
function PlayerProfile.animationPaceDivisor(animSpeed, hasFastForwardPass)
	if animSpeed ~= "fast" then
		return 1
	end
	if hasFastForwardPass then
		return PlayerProfile.FAST_FORWARD_PACE_DIVISOR
	end
	return PlayerProfile.FAST_PACE_DIVISOR
end

-- ONE MORE ROUND: every player gets one free continue per day (the UTC day
-- of SeededRng.dailyDateKey(), same as the Daily Challenge). The server
-- offers it before the paid Developer Product.
function PlayerProfile.hasFreeContinue(profile, dateKey)
	return type(dateKey) == "string" and profile.freeContinueDateKey ~= dateKey
end

-- Spends today's free continue. Returns false if it was already spent.
function PlayerProfile.useFreeContinue(profile, dateKey)
	if not PlayerProfile.hasFreeContinue(profile, dateKey) then
		return false
	end
	profile.freeContinueDateKey = dateKey
	return true
end

-- Merges a list of Patron ids (e.g. this run's state.ownedPatrons, mapped to
-- just their ids) into the permanent discovered set. Returns true if
-- anything NEW was added, so the caller (Server/init.server.lua) knows
-- whether this player's profile actually needs saving, instead of writing
-- to DataStore on every single state push regardless of whether anything
-- changed.
function PlayerProfile.recordPatronsFound(profile, patronIds)
	local changed = false
	for _, id in ipairs(patronIds) do
		if type(id) == "string" and not profile.discoveredPatronIds[id] then
			profile.discoveredPatronIds[id] = true
			changed = true
		end
	end
	return changed
end

-- COLLECTION: merges { [tabId] = {id, ...} } (CollectionBook.gatherSeen's
-- result) into the discovered sets. Unknown tab ids are ignored. Returns
-- true if anything new was added.
function PlayerProfile.recordDiscovered(profile, seen)
	local changed = false
	for tabId, field in pairs(PlayerProfile.DISCOVERY_FIELDS) do
		local set = profile[field]
		for _, id in ipairs(seen[tabId] or {}) do
			if type(id) == "string" and not set[id] then
				set[id] = true
				changed = true
			end
		end
	end
	return changed
end

-- Call once, right when a fresh run actually starts (Server/init.server.lua's
-- startNewSession). Always "changes" the profile (the counter always goes
-- up), so the caller doesn't need to check a return value here.
function PlayerProfile.recordRunStarted(profile)
	profile.stats.runsStarted = profile.stats.runsStarted + 1
end

-- Settings > Restart Run: counts the run as abandoned. Grants nothing (no win, no Night credit beyond
-- what syncProfileFromSession already recorded as the run went).
function PlayerProfile.recordRunAbandoned(profile)
	profile.stats.runsAbandoned = (profile.stats.runsAbandoned or 0) + 1
end

-- Idempotent high-water mark -- safe to call with the current Night on every
-- single state push (same pattern as recordPatronsFound
-- above: returns whether it actually moved, so the caller can skip a save
-- when it didn't).
function PlayerProfile.recordNightReached(profile, night)
	if type(night) == "number" and night > profile.stats.bestNightReached then
		profile.stats.bestNightReached = night
		return true
	end
	return false
end

-- Personal best Endless Night per stake. Idempotent high-water mark; returns true when it moved.
function PlayerProfile.recordEndlessBest(profile, stake, night)
	if type(stake) ~= "number" or type(night) ~= "number" or night ~= night or night < 1 or night > 500 then
		return false
	end
	profile.endlessBestByStake = profile.endlessBestByStake or {}
	local key = tostring(math.floor(stake))
	night = math.floor(night)
	if night > (profile.endlessBestByStake[key] or 0) then
		profile.endlessBestByStake[key] = night
		return true
	end
	return false
end

-- WORLD MAP compass charges. Earned by winning a map minigame (steps 7a/7b), spent on a fork to reveal the
-- exact reward at the end of each road. Returns true if a charge was added / spent.
PlayerProfile.MAX_COMPASS_CHARGES = 3

function PlayerProfile.addCompassCharge(profile)
	if profile.compassCharges >= PlayerProfile.MAX_COMPASS_CHARGES then return false end
	profile.compassCharges = profile.compassCharges + 1
	return true
end

function PlayerProfile.spendCompassCharge(profile)
	if profile.compassCharges <= 0 then return false end
	profile.compassCharges = profile.compassCharges - 1
	return true
end

-- WORLD MAP: mirrors the run's road into the profile and counts cleared Night stops per region.
-- `cleared` is how many Nights of the route are cleared so far; `counted` is how many of those were already
-- added to worldBiomeClears for this run (the caller keeps it, so repeated pushes never double count).
-- Returns changed, newCounted. Every stop on the route is marked seen.
function PlayerProfile.recordWorldProgress(profile, route, cleared, counted)
	counted = counted or 0
	if not WorldMap.isValidRoute(route) then
		return false, counted
	end
	local changed = false
	local same = #profile.worldRoute == #route
	if same then
		for i, id in ipairs(route) do
			if profile.worldRoute[i] ~= id then
				same = false
				break
			end
		end
	end
	if not same then
		profile.worldRoute = { table.unpack(route) }
		changed = true
	end
	for _, id in ipairs(route) do
		if not profile.worldSeenStopIds[id] then
			profile.worldSeenStopIds[id] = true
			changed = true
		end
	end
	local upTo = math.min(math.floor(cleared or 0), #route)
	for i = counted + 1, upTo do
		local region = WorldMap.regionOf(route[i])
		if region then
			profile.worldBiomeClears[region] = (profile.worldBiomeClears[region] or 0) + 1
			changed = true
		end
		counted = i
	end
	return changed, counted
end

-- Called once when a map minigame is won (the server, right after scoring it).
function PlayerProfile.recordMinigameWin(profile)
	profile.minigameWins = math.min(99999, (profile.minigameWins or 0) + 1)
end

-- Call exactly once, the moment a run's wonRun flag flips from false to
-- true (Server/init.server.lua tracks that transition itself -- this
-- function just does the counter increment once told to).
function PlayerProfile.recordRunWon(profile)
	profile.stats.runsWon = profile.stats.runsWon + 1
	Keys.add(profile) -- a win earns one Key (called once per win by the server)
end

-- ACHIEVEMENTS + TITLES (Phase 16): equips (or, passing nil, un-equips)
-- a Title -- re-validates against Achievements.isUnlocked every call
-- (never trusts a client-supplied id blindly), so this is safe to call
-- directly off a remote handler with zero other server-side checks.
function PlayerProfile.equipTitle(profile, achievementId)
	if achievementId == nil then
		profile.equippedTitleId = nil
		return true, "Title cleared."
	end
	if type(achievementId) ~= "string" then
		return false, "Invalid title"
	end
	if not Achievements.isUnlocked(profile, achievementId) then
		return false, "Title not unlocked"
	end
	profile.equippedTitleId = achievementId
	return true, "Title equipped."
end

-- TUTORIAL (Phase 16): idempotent -- safe to call even if already true
-- (Server/init.server.lua's handler doesn't bother checking first).
function PlayerProfile.markTutorialSeen(profile)
	profile.hasSeenTutorial = true
end

function PlayerProfile.markHighCardHintSeen(profile)
	profile.hasSeenHighCardHint = true
end

return PlayerProfile
