--[[
	Server/init.server.lua
	Runs once on the server when the game starts. Responsibilities:
	  1. Run the engine unit tests and print PASS/FAIL to the Output window
	     every time you hit Play in Studio -- this is our "very testable"
	     safety net without needing anything installed outside Roblox.
	  2. Set up RemoteEvents for the client to call.
	  3. Own the authoritative RunState per player and respond to their
	     actions (play a hand, discard, buy a patron, advance a round).

	This is intentionally a single flat script for the MVP. Once the core
	loop feels good, split it into smaller modules (e.g. SessionManager,
	RemoteHandlers) -- but don't do that until you actually feel the pain
	of one big file; premature splitting costs more than it saves this week.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local DataStoreService = game:GetService("DataStoreService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Engine = Shared:WaitForChild("Engine")
local Tests = Shared:WaitForChild("Tests")

local RunState = require(Engine.RunState)
local Patrons = require(Engine.Patrons)
local Themes = require(Engine.Themes) -- PERSISTENT SAVE (Phase 10): needed for Themes.DefaultThemeId, see syncProfileFromSession's BUGFIX comment
local Deck = require(Engine.Deck)
local Recipes = require(Engine.Recipes)
local Packs = require(Engine.Packs)
local HousePasses = require(Engine.HousePasses)
local GamePasses = require(Engine.GamePasses) -- real-money Robux Game Passes (see that file's header for setup steps)
local PlayerProfile = require(Engine.PlayerProfile) -- PERSISTENT SAVE (Phase 10, see that file's header) -- the permanent, cross-run part of a player's progress
local SeededRng = require(Engine.SeededRng) -- DAILY CHALLENGE (Phase 11, see that file's header) -- deterministic rng + the daily seed/date-key it's derived from
local Achievements = require(Engine.Achievements) -- ACHIEVEMENTS + TITLES (Phase 16, see that file's header)

-- ===== 1. Run engine tests on server start =====

do
	local TestRunner = require(Tests.TestRunner)
	local engineTests = require(Tests.EngineTests)
	print("===== Wildcard Tavern: running engine tests =====")
	local results = TestRunner.run(engineTests)
	if results.failed > 0 then
		warn(string.format("%d engine test(s) FAILED -- fix these before trusting the game logic!", results.failed))
	end
	print("===================================================")
end

-- ===== 2. RemoteEvents =====

local remotes = Instance.new("Folder")
remotes.Name = "Remotes"
remotes.Parent = ReplicatedStorage

local function newRemote(name)
	local r = Instance.new("RemoteEvent")
	r.Name = name
	r.Parent = remotes
	return r
end

local PlayHandRemote = newRemote("PlayHand")
local DiscardRemote = newRemote("Discard")
local BuyPatronRemote = newRemote("BuyPatron")
local SellPatronRemote = newRemote("SellPatron") -- "Discard" was already taken by the card-discard remote above
local BuyThemeRemote = newRemote("BuyTheme")
local EquipThemeRemote = newRemote("EquipTheme")
local EquipTitleRemote = newRemote("EquipTitle") -- ACHIEVEMENTS + TITLES (Phase 16): (player, achievementId or nil)
local AddPlaylistSongRemote = newRemote("AddPlaylistSong") -- JUKEBOX PLAYLIST (requested fix): (player, assetId string, e.g. "rbxassetid://123")
local RemovePlaylistSongRemote = newRemote("RemovePlaylistSong") -- (player, assetId string)
local MovePlaylistSongRemote = newRemote("MovePlaylistSong") -- JUKEBOX PLAYLIST REORDER (requested fix): (player, assetId string, direction number -1/+1)
local MarkTutorialSeenRemote = newRemote("MarkTutorialSeen") -- TUTORIAL (Phase 16): (player) -- fired once the walkthrough is dismissed/skipped
local BuyRecipeRemote = newRemote("BuyRecipe")   -- (player, category, id) -- see the comment above its handler: direct-buy is unreachable from the current UI, kept for direct engine/test use
local UseRecipeRemote = newRemote("UseRecipe")   -- (player, category, id, cardIndices, suit)
local RerollShopRemote = newRemote("RerollShop") -- (player) -- pay tips to reroll Patron/Pack/Voucher offers
local BuyPackRemote = newRemote("BuyPack")       -- (player, packId)
local ResolvePackRemote = newRemote("ResolvePack") -- (player, chosenIds)
local BuyHousePassRemote = newRemote("BuyHousePass") -- (player, passId)
local AdvanceRoundRemote = newRemote("AdvanceRound")
-- ROUND SELECT FEATURE: fired from Client/RoundSelect.lua, the screen
-- shown whenever phase == "roundSelect" (start of a run, and every time
-- after leaving the shop -- see below). SelectRound confirms "play this
-- round"; SkipRound takes this round's revealed Tag instead (see
-- RunState.canSkipRound/skipRound/Tags.lua).
local SelectRoundRemote = newRemote("SelectRound") -- (player)
local SkipRoundRemote = newRemote("SkipRound") -- (player)
local RestartRunRemote = newRemote("RestartRun")
local StartRunRemote = newRemote("StartRun") -- like RestartRun, but with a chosen Deck Variant + Difficulty
local StateUpdatedRemote = newRemote("StateUpdated") -- server -> client
-- DAILY CHALLENGE (Phase 11): a seeded standard/standard run, same for
-- every player on the same UTC day -- see Shared/Engine/SeededRng.lua's
-- header for exactly what "same" means once player choices start
-- diverging. GetDailyLeaderboard is a RemoteFunction (request/response,
-- not fire-and-forget) since the client needs the actual leaderboard data
-- back -- Roblox's RemoteFunction handles that yield/return shape
-- directly, no separate "here's your answer" RemoteEvent needed.
local StartDailyChallengeRemote = newRemote("StartDailyChallenge") -- (player)
local GetDailyLeaderboardRemote = Instance.new("RemoteFunction")
GetDailyLeaderboardRemote.Name = "GetDailyLeaderboard"
GetDailyLeaderboardRemote.Parent = remotes

-- WEEKLY CHALLENGE (Phase 16): same shape as Daily Challenge above, just
-- bucketed into 7-day windows (SeededRng.weeklySeed/weeklyDateKey)
-- instead of calendar days -- gives the two of you a longer-running
-- comparison than the Daily board resets away every midnight.
local StartWeeklyChallengeRemote = newRemote("StartWeeklyChallenge") -- (player)
local GetWeeklyLeaderboardRemote = Instance.new("RemoteFunction")
GetWeeklyLeaderboardRemote.Name = "GetWeeklyLeaderboard"
GetWeeklyLeaderboardRemote.Parent = remotes

-- SHAREABLE SEED CODES (Phase 16): (player, code) -- starts a seeded
-- standard/standard run from a player-typed/shared code
-- (SeededRng.codeToSeed) instead of a date-derived seed. No leaderboard
-- of its own -- this is for two friends comparing a specific run
-- on demand, not a ranked board, so it's deliberately just the one
-- fire-and-forget remote.
local StartSeedRunRemote = newRemote("StartSeedRun") -- (player, code)

-- ===== 3. Persistent Player Profile (DataStoreService) =====
-- PERSISTENT SAVE (Phase 10): see Shared/Engine/PlayerProfile.lua's header
-- for exactly what this does and doesn't cover -- short version, discovered
-- Patrons, Tips-bought Themes, and a few small stats now survive a rejoin
-- or server restart; an in-progress RUN itself still doesn't (a deliberate
-- scope decision, not a gap).
--
-- ONE-TIME STUDIO SETUP: DataStoreService calls fail in Studio unless
-- "Enable Studio Access to API Services" is turned on (Studio's Home tab ->
-- Game Settings -> Security). Every DataStore call below is wrapped in
-- pcall specifically so testing BEFORE that's turned on doesn't error out
-- the whole server -- it just falls back to a fresh, unsaved profile for
-- the session, with a warn() explaining why. Once this game is actually
-- published, DataStores work automatically for every player with zero
-- Roblox Creator Dashboard setup needed (unlike Game Passes, which need a
-- real Game Pass ID created first -- see GamePasses.lua) -- this Studio
-- setting only matters for local testing.

-- Bump the trailing version only for a clean-break reset of every existing
-- player's save (extremely rare -- PlayerProfile.migrate already absorbs a
-- missing/extra/renamed field on an old save without needing this).
local ProfileStore = DataStoreService:GetDataStore("WildcardTavernProfile_v1")

local profiles = {} -- [player] = PlayerProfile-shaped table, the live working copy
local profileDirty = {} -- [player] = true once something's changed since the last successful save
local AUTOSAVE_INTERVAL = 120 -- seconds; a crash-safety net between joins/leaves, not the primary save path (PlayerRemoving/BindToClose below are)

local function profileKey(player)
	return "Player_" .. tostring(player.UserId)
end

local function loadProfile(player)
	local ok, raw = pcall(function()
		return ProfileStore:GetAsync(profileKey(player))
	end)
	if not ok then
		warn(string.format(
			"PlayerProfile load failed for %s (%s) -- starting with a fresh, unsaved profile this session. In Studio, this usually means \"Enable Studio Access to API Services\" is off (Game Settings -> Security).",
			player.Name, tostring(raw)
		))
		return PlayerProfile.new()
	end
	return PlayerProfile.migrate(raw)
end

local function saveProfile(player)
	local profile = profiles[player]
	if not profile then
		return
	end
	local ok, err = pcall(function()
		ProfileStore:SetAsync(profileKey(player), profile)
	end)
	if ok then
		profileDirty[player] = nil
	else
		warn(string.format("PlayerProfile save failed for %s: %s", player.Name, tostring(err)))
		-- Leave profileDirty set -- the next autosave tick (or the final
		-- PlayerRemoving/BindToClose attempt) will retry.
	end
end

-- syncProfileFromSession (needs `sessions`, declared just below) is defined
-- right before pushState further down, the one place it's actually called.

-- ===== 4. Daily Challenge Leaderboard (OrderedDataStoreService) =====
-- DAILY CHALLENGE (Phase 11): see Shared/Engine/SeededRng.lua's header for
-- what "same seed" actually guarantees. This section is the leaderboard
-- half -- same one-time Studio setup ("Enable Studio Access to API
-- Services") and pcall-everywhere caution as Persistent Player Profile
-- above.
--
-- "Depth" is this project's single comparable leaderboard number: rounds
-- FULLY CLEARED so far this run -- (night - 1) * roundsPerNight +
-- (round - 1) -- monotonically non-decreasing across a run, finer-grained
-- than raw Night alone (which would tie constantly), and naturally keeps
-- climbing through Endless Mode past Night 8 too, with no special-casing
-- needed. Tips banked is folded in as a tiebreaker only (see
-- DAILY_SCORE_MULTIPLIER below), never the primary sort.
--
-- SAVE TIMING, deliberately mirrors PERSISTENT SAVE (Phase 10)'s
-- profileDirty/autosave/PlayerRemoving/BindToClose shape rather than
-- inventing a new one: an improvement just updates an in-memory
-- `dailyPending[player]` snapshot and marks `dailyDirty[player]` --
-- nothing calls DataStoreService directly from inside a remote-event
-- handler's response path. Two reasons, both deliberate: (1) a
-- synchronous yielding SetAsync call there would visibly lag that exact
-- round-win's state push to the client, and (2) firing an unbounded
-- number of overlapping `task.spawn`-ed saves (one per improvement) could
-- let an OLDER, LOWER save finish after a newer one and leave a stale
-- score as the final written value -- keeping exactly one pending
-- snapshot per player and only ever reading it fresh at actual save time
-- (never capturing a value that could go stale while queued) avoids that
-- race entirely.

local DAILY_SCORE_MULTIPLIER = 1000000 -- combinedScore = depth * this + tips; tips is clamped below this so it can never bleed into depth's digits
local DAILY_TIPS_CAP = DAILY_SCORE_MULTIPLIER - 1
local LEADERBOARD_COOLDOWN = 2 -- seconds; a simple per-player throttle so mashing the leaderboard-open button can't hammer DataStore with reads

local dailyBoardCache = {} -- [dateKey] = OrderedDataStore instance, so re-opening the same day's board doesn't re-fetch a fresh DataStore object every time
local dailyPending = {} -- [player] = { dateKey, depth, tips } -- this player's best Daily Challenge result not yet confirmed written to that day's board
local dailyDirty = {} -- [player] = true while dailyPending[player] hasn't been successfully saved yet
local lastLeaderboardRequest = {} -- [player] = os.clock() of their last GetDailyLeaderboard call

local function getDailyStore(dateKey)
	if not dailyBoardCache[dateKey] then
		dailyBoardCache[dateKey] = DataStoreService:GetOrderedDataStore("DailyChallenge_" .. dateKey)
	end
	return dailyBoardCache[dateKey]
end

local function computeDailyDepth(state)
	return (state.night - 1) * state.config.roundsPerNight + (state.round - 1)
end

local function saveDailyScore(player)
	local pending = dailyPending[player]
	if not pending then
		return
	end
	local combinedScore = pending.depth * DAILY_SCORE_MULTIPLIER + pending.tips
	local store = getDailyStore(pending.dateKey)
	local ok, err = pcall(function()
		store:SetAsync(tostring(player.UserId), combinedScore)
	end)
	if ok then
		dailyDirty[player] = nil
	else
		warn(string.format("Daily leaderboard save failed for %s: %s", player.Name, tostring(err)))
		-- Leave dailyDirty set -- the next autosave tick (or the final
		-- PlayerRemoving/BindToClose attempt) will retry with whatever
		-- dailyPending[player] holds by then (always the freshest known
		-- best, never a stale snapshot -- see the section header above).
	end
end

-- ===== 4b. Weekly Challenge Leaderboard (Phase 16) =====
-- Deliberately a straight copy of the Daily Challenge Leaderboard shape
-- just above -- same combinedScore encoding, same pending/dirty snapshot
-- pattern and the exact same reasoning for it (see that section's header
-- comment), just keyed by SeededRng.weeklyDateKey() instead of a
-- calendar-day string. Kept as fully separate tables/functions rather
-- than parameterizing the Daily ones over a "kind" flag -- more lines,
-- but zero risk of a Weekly bug ever touching the Daily path or vice
-- versa.

local weeklyBoardCache = {} -- [weekKey] = OrderedDataStore instance
local weeklyPending = {} -- [player] = { weekKey, depth, tips }
local weeklyDirty = {} -- [player] = true while weeklyPending[player] hasn't been successfully saved yet
local lastWeeklyLeaderboardRequest = {} -- [player] = os.clock() of their last GetWeeklyLeaderboard call

local function getWeeklyStore(weekKey)
	if not weeklyBoardCache[weekKey] then
		weeklyBoardCache[weekKey] = DataStoreService:GetOrderedDataStore("WeeklyChallenge_" .. weekKey)
	end
	return weeklyBoardCache[weekKey]
end

local function saveWeeklyScore(player)
	local pending = weeklyPending[player]
	if not pending then
		return
	end
	local combinedScore = pending.depth * DAILY_SCORE_MULTIPLIER + pending.tips
	local store = getWeeklyStore(pending.weekKey)
	local ok, err = pcall(function()
		store:SetAsync(tostring(player.UserId), combinedScore)
	end)
	if ok then
		weeklyDirty[player] = nil
	else
		warn(string.format("Weekly leaderboard save failed for %s: %s", player.Name, tostring(err)))
	end
end

-- trackDailyProgress/trackWeeklyProgress (need `sessions`, declared just
-- below) are defined right next to syncProfileFromSession further down,
-- both called from pushState.

-- ===== 5. Session management =====

-- Matches the reference game's usual shop layout more closely than our old
-- "3 Patron offers, nothing else" did: 2 Patron offers + 2 Pack offers
-- every visit, plus an occasional single Voucher (House Pass) offer -- see
-- VOUCHER_CHANCE. Reroll cost climbs by REROLL_COST_STEP each reroll
-- within a single shop visit, then resets to REROLL_BASE_COST next visit.
local SHOP_OFFER_COUNT = 2
local PACK_OFFER_COUNT = 2
local VOUCHER_CHANCE = 0.35
local REROLL_BASE_COST = 5
local REROLL_COST_STEP = 2

-- ROUND SELECT FEATURE: "roundSelect" is the new 4th phase -- shown at the
-- very start of a run, and every time right after leaving the shop
-- (instead of dropping straight into "playing"). RunState itself already
-- has a hand dealt and ready the instant a "roundSelect" phase begins
-- (RunState.startRound runs unconditionally) -- this phase is purely a
-- client-visibility gate, so no engine changes were needed to add it; see
-- SelectRoundRemote's handler below for the phase flip into "playing".
local sessions = {} -- [player] = { state = RunState, phase = "roundSelect" | "playing" | "shop" | "gameover", shopOffers = {patron, ...}, packOffers = {pack, ...}, voucherOffer = pass | nil, rerollCost = number }

-- Real-money Game Passes (see Shared/Engine/GamePasses.lua): deliberately
-- kept OUTSIDE the `sessions` table -- a Game Pass is owned by the PLAYER
-- forever (Roblox remembers it), not by any one run, so this must survive
-- `startNewSession` reassigning sessions[player] to a fresh table on every
-- "New Run.../restart -- unlike state.ownedThemes (Tips purchases), which
-- SHOULD reset with the run. The actual ownership-check/grant machinery
-- lives further down (right after pushState is defined, since it needs
-- to call that).
local ownedGamePasses = {} -- [player] = { [GamePasses catalog id] = true }

-- DAILY CHALLENGE (Phase 11) FIX: all three of these used to call the
-- global `math.random` directly, completely bypassing `state.rng` (the
-- seeded rng RunState.new stores on the state table -- see
-- Shared/Engine/RunState.lua line ~160 and its Deck.shuffle/BossRounds.pick/
-- Tags.pick call sites, which DO thread it through correctly). That made a
-- Daily Challenge run's shop offers (Patrons/Packs/Vouchers) random and
-- different for every player from the very first shop visit, even though
-- the deck order and Boss Round were correctly identical -- silently
-- defeating the whole point of a Daily Challenge ("everyone starts from
-- the identical first shop/Boss/deck order"). Found via independent
-- review; fixed by threading `state.rng or math.random` through here too,
-- same fallback pattern RunState.lua itself already uses everywhere (a nil
-- rng -- a normal, non-Daily run -- transparently falls back to
-- `math.random`, so this changes nothing for regular runs).
local function pickShopOffers(state)
	local rng = state.rng or math.random

	local available = {}
	for _, patron in ipairs(Patrons.Definitions) do
		local alreadyOwned = false
		for _, owned in ipairs(state.ownedPatrons) do
			if owned.id == patron.id then
				alreadyOwned = true
				break
			end
		end
		if not alreadyOwned then
			table.insert(available, patron)
		end
	end

	-- shuffle-ish pick
	local offers = {}
	for _ = 1, math.min(SHOP_OFFER_COUNT, #available) do
		local i = rng(#available)
		table.insert(offers, table.remove(available, i))
	end
	return offers
end

local function pickPackOffers(state)
	local rng = state.rng or math.random

	local pool = {}
	for _, pack in ipairs(Packs.Definitions) do
		table.insert(pool, pack)
	end
	local offers = {}
	for _ = 1, math.min(PACK_OFFER_COUNT, #pool) do
		local i = rng(#pool)
		table.insert(offers, table.remove(pool, i))
	end
	return offers
end

-- Only offers a House Pass the player doesn't already own, and only some of
-- the time -- "shows up from time to time," not every visit, same as the
-- reference game's Voucher slot. `rng(n)` only supports integer picks in
-- [1, n], not a float roll like `math.random()`'s no-arg form -- rolling a
-- 1-in-10000 draw against a scaled integer threshold (rng(10000) <=
-- VOUCHER_CHANCE * 10000) gets the same 35% probability out of the same
-- integer-only contract every other rng() call site in this codebase uses.
local function pickVoucherOffer(state)
	local rng = state.rng or math.random
	local roll = state.rng and (rng(10000) <= math.floor(VOUCHER_CHANCE * 10000)) or (math.random() <= VOUCHER_CHANCE)
	if not roll then
		return nil
	end
	local available = {}
	for _, pass in ipairs(HousePasses.Definitions) do
		if not state.housePasses[pass.id] then
			table.insert(available, pass)
		end
	end
	if #available == 0 then
		return nil
	end
	return available[rng(#available)]
end

-- Rerolls just the offers, keeping whatever the current rerollCost climbed
-- to (the caller bumps it after using this). Opening a fresh shop visit
-- uses this too, via openShop below, which additionally resets the cost.
local function rollShopOffers(session)
	session.shopOffers = pickShopOffers(session.state)
	session.packOffers = pickPackOffers(session.state)
	session.voucherOffer = pickVoucherOffer(session.state)
end

local function openShop(session)
	rollShopOffers(session)
	session.rerollCost = REROLL_BASE_COST
end

local function serializeCard(card)
	return { rank = card.rank, suit = card.suit, garnish = card.garnish, special = card.special, stamp = card.stamp }
end

local function serializeState(session, player)
	local state = session.state
	local hand = {}
	for _, card in ipairs(state.hand) do
		table.insert(hand, serializeCard(card))
	end

	local owned = {}
	for _, patron in ipairs(state.ownedPatrons) do
		table.insert(owned, { id = patron.id, name = patron.name, description = patron.description })
	end

	-- Prices below go through RunState.patronPrice/packPrice so the client
	-- never has to duplicate House Pass discount math -- it just displays
	-- whatever price it's sent.
	local shopOffers = {}
	for _, patron in ipairs(session.shopOffers) do
		table.insert(shopOffers, {
			id = patron.id, name = patron.name, description = patron.description,
			price = RunState.patronPrice(state, patron),
		})
	end

	local packOffers = {}
	for _, pack in ipairs(session.packOffers or {}) do
		table.insert(packOffers, {
			id = pack.id, name = pack.name, icon = pack.icon, description = pack.description,
			price = RunState.packPrice(state, pack),
		})
	end

	local voucherOffer = nil
	if session.voucherOffer then
		voucherOffer = {
			id = session.voucherOffer.id, name = session.voucherOffer.name, icon = session.voucherOffer.icon,
			description = session.voucherOffer.description, price = session.voucherOffer.price,
		}
	end

	local housePassIds = {}
	for passId in pairs(state.housePasses) do
		table.insert(housePassIds, passId)
	end

	-- Themes are static content data (colors, price) that the client can
	-- already read directly from ReplicatedStorage.Shared.Engine.Themes --
	-- we only need to tell the client WHICH ones this player owns/has
	-- equipped, not resend the whole catalog every update.
	local ownedThemeIds = {}
	for themeId in pairs(state.ownedThemes) do
		table.insert(ownedThemeIds, themeId)
	end

	local bossModifier = nil
	if state.bossModifier then
		bossModifier = {
			id = state.bossModifier.id,
			name = state.bossModifier.name,
			description = state.bossModifier.description,
		}
	end

	-- JOURNEY FEATURE: this Night's Boss modifier, revealed from Round 1
	-- onward (see RunState.startRound) -- lets the Journey map show WHICH
	-- Boss is coming, not just a generic crown icon, for every round of
	-- the current Night leading up to it. Same sanitized id/name/
	-- description shape as bossModifier above, for the same reason: only
	-- ship what the client actually needs to display.
	local nightBossModifier = nil
	if state.nightBossModifier then
		nightBossModifier = {
			id = state.nightBossModifier.id,
			name = state.nightBossModifier.name,
			description = state.nightBossModifier.description,
		}
	end

	-- ROUND SELECT FEATURE: the Tag you'd get for skipping the round
	-- you're currently on, if any (nil on the Boss round -- see
	-- RunState.startRound/Tags.lua). Same sanitized id/name/icon/
	-- description shape as nightBossModifier above -- `apply` is a
	-- function and never needs to leave the server.
	local currentRoundSkipTag = nil
	if state.currentRoundSkipTag then
		currentRoundSkipTag = {
			id = state.currentRoundSkipTag.id,
			name = state.currentRoundSkipTag.name,
			icon = state.currentRoundSkipTag.icon,
			description = state.currentRoundSkipTag.description,
		}
	end

	return {
		phase = session.phase,
		night = state.night,
		round = state.round,
		tips = state.tips,
		hand = hand,
		handsRemaining = state.handsRemaining,
		discardsRemaining = state.discardsRemaining,
		roundScore = state.roundScore,
		targetScore = state.targetScore,
		ownedPatrons = owned,
		patronSlotLimit = RunState.patronSlotLimit(state),
		-- BALATRO PARITY: recipeSlotLimit/nightCap are static-per-run
		-- numbers (same pattern as patronSlotLimit above) -- the client
		-- reads them to show "X/2 Recipes" and "Night N/8" without
		-- hardcoding a second copy of either constant. wonRun/
		-- lastRoundReward are the Ante-cap win flag and the actual Tips
		-- total from the most recent round win (see RunState.playHand).
		recipeSlotLimit = RunState.recipeSlotLimit(state),
		nightCap = state.config.nightCap,
		wonRun = state.wonRun,
		lastRoundReward = state.lastRoundReward,
		shopOffers = shopOffers,
		packOffers = packOffers,
		voucherOffer = voucherOffer,
		rerollCost = RunState.rerollCost(state, session.rerollCost or REROLL_BASE_COST),
		-- pendingPack is already the lightweight { packId, category, pickCount,
		-- items = {id,name,icon,description} } shape RunState.openPack builds
		-- -- safe to ship as-is, same as deckCounts/handLevels below.
		pendingPack = state.pendingPack,
		housePassIds = housePassIds,
		ownedThemeIds = ownedThemeIds,
		-- Real-money Game Pass ownership (see Shared/Engine/GamePasses.lua) --
		-- separate from ownedThemeIds above even though owning "all_themes"
		-- also populates ownedThemeIds (via applyGamePassGrants): this is
		-- what Client/Themes.lua uses to tell "you already own the Game
		-- Pass, equip is free" apart from "buy this Theme with Tips".
		ownedGamePassIds = (function()
			local ids = {}
			for passId in pairs(ownedGamePasses[player] or {}) do
				table.insert(ids, passId)
			end
			return ids
		end)(),
		equippedTheme = state.equippedTheme,
		deckVariantId = state.deckVariantId,
		difficultyId = state.difficultyId,
		bossModifier = bossModifier,
		-- JOURNEY FEATURE / ROUND SELECT FEATURE
		nightBossModifier = nightBossModifier,
		canSkipRound = RunState.canSkipRound(state),
		currentRoundSkipTag = currentRoundSkipTag,
		handStats = state.handStats,
		handLevels = state.handLevels,
		-- SCORING JUICE fix: computeHandPreview (init.client.lua) needs
		-- these 3 to build the EXACT same Scoring.calculate context
		-- RunState.playHand does server-side -- without them, the preview
		-- (and the new sequenced chip/mult/xmult reveal built on top of it)
		-- could show a hand-shape/number that doesn't match what actually
		-- gets paid whenever a Patron Special, Sugar Shield, or a repeated
		-- hand type under a "No Repeats" Boss Round is in play.
		ownedPatronSpecials = state.ownedPatronSpecials,
		brittleShieldRound = state.brittleShieldRound,
		handTypesPlayedThisRound = state.handTypesPlayedThisRound,
		-- Recipes.HouseRecipes/MenuRecipes/SecretRecipes are static content
		-- the client already reads straight from
		-- ReplicatedStorage.Shared.Engine.Recipes (same pattern as Themes
		-- above) -- we only need to say WHICH ones this player owns.
		houseRecipeInventory = state.houseRecipeInventory,
		menuRecipeInventory = state.menuRecipeInventory,
		secretRecipeInventory = state.secretRecipeInventory,
		-- Deck.remainingCounts is [suit] = { [rank] = count } -- RemoteEvents
		-- serialize nested tables fine, so this ships as-is.
		deckCounts = Deck.remainingCounts(state.deck),
		-- PERSISTENT SAVE (Phase 10): the permanent, cross-run part of this
		-- player's progress (Shared/Engine/PlayerProfile.lua) -- see that
		-- file's header for exactly what these mean. discoveredPatronIds
		-- powers Client/Collection.lua showing a Patron as found even in a
		-- brand-new run where you haven't re-bought it yet; profileStats is
		-- 3 small permanent counters shown alongside it. Note ownedThemeIds
		-- above is ALSO now effectively permanent (RunState.new seeds it
		-- from this same profile -- see startNewSession) even though it's
		-- not read from `profiles` directly here.
		discoveredPatronIds = (function()
			local ids = {}
			local profile = profiles[player]
			if profile then
				for id in pairs(profile.discoveredPatronIds) do
					table.insert(ids, id)
				end
			end
			return ids
		end)(),
		profileStats = (function()
			local profile = profiles[player]
			if not profile then
				return { runsStarted = 0, runsWon = 0, bestNightReached = 0 }
			end
			return {
				runsStarted = profile.stats.runsStarted,
				runsWon = profile.stats.runsWon,
				bestNightReached = profile.stats.bestNightReached,
			}
		end)(),
		-- ACHIEVEMENTS + TITLES (Phase 16): unlockedAchievementIds is
		-- recomputed fresh from the profile every single serializeState
		-- call (see Achievements.lua's header for why that's cheap and
		-- safe -- nothing here is stored) -- the client uses it to draw
		-- the Collection screen's badge grid and to know which titles are
		-- selectable in the equip dropdown. equippedTitleId is the one
		-- actual saved field (PlayerProfile.equippedTitleId).
		unlockedAchievementIds = (function()
			local profile = profiles[player]
			if not profile then
				return {}
			end
			local ids = {}
			for _, achievement in ipairs(Achievements.unlockedFor(profile)) do
				table.insert(ids, achievement.id)
			end
			return ids
		end)(),
		equippedTitleId = (function()
			local profile = profiles[player]
			return profile and profile.equippedTitleId or nil
		end)(),
		-- JUKEBOX PLAYLIST (requested fix): the player's saved list of
		-- Custom Jukebox track ids (Shared/Engine/PlayerProfile.lua's
		-- customPlaylist) -- Client/Settings.lua reads this to draw the
		-- "My Playlist" rows. A plain copy, not a reference, same
		-- reasoning as discoveredPatronIds above (never hand the live
		-- server-side table straight to a RemoteEvent).
		customPlaylist = (function()
			local profile = profiles[player]
			if not profile then
				return {}
			end
			local ids = {}
			for _, id in ipairs(profile.customPlaylist) do
				table.insert(ids, id)
			end
			return ids
		end)(),
		-- TUTORIAL (Phase 16): `false` (not nil) here is what tells the
		-- client "genuinely show the auto-popup" -- a not-yet-loaded
		-- profile deliberately reports `true` instead (see the `or true`
		-- below), so a client that somehow renders before profiles[player]
		-- is ready doesn't mistake "still loading" for "brand new,
		-- auto-show the tutorial."
		hasSeenTutorial = (function()
			local profile = profiles[player]
			if not profile then
				return true
			end
			return profile.hasSeenTutorial
		end)(),
		-- DAILY CHALLENGE (Phase 11): lets the client show a "Daily
		-- Challenge" badge/HUD state -- dailyDateKey is the UTC day this
		-- specific run started on (fixed at startNewSession, see that
		-- function's comment), not necessarily "today" if the run has been
		-- going since before a UTC midnight.
		isDaily = session.isDaily or false,
		dailyDateKey = session.dailyDateKey,
		-- WEEKLY CHALLENGE / SEED CODES (Phase 16): same idea as the Daily
		-- fields just above, one pair per run mode. At most one of
		-- isDaily/isWeekly/isSeeded is ever true for a given session --
		-- startNewSession only ever sets one seedMode per call.
		isWeekly = session.isWeekly or false,
		weeklyDateKey = session.weeklyDateKey,
		isSeeded = session.isSeeded or false,
		seedCode = session.seedCode,
	}
end

-- PERSISTENT SAVE (Phase 10): folds this player's CURRENT run into their
-- permanent profile -- every owned Patron this run into
-- discoveredPatronIds, every owned Theme into ownedThemeIds, the current
-- Night into the bestNightReached high-water mark, and (once, on the
-- false->true transition) a run win into stats.runsWon. Safe to call
-- unconditionally on every single pushState -- idempotent and cheap for
-- the small lists involved -- only actually marks the profile dirty
-- (needing a save) when something genuinely new happened, so a run of
-- unrelated state pushes (playing hands with nothing new discovered)
-- doesn't spam DataStore writes.
local function syncProfileFromSession(player)
	local session = sessions[player]
	local profile = profiles[player]
	if not session or not profile then
		return
	end

	local patronIds = {}
	for _, patron in ipairs(session.state.ownedPatrons) do
		table.insert(patronIds, patron.id)
	end
	-- BUGFIX (caught by independent review before shipping): only fold
	-- TIPS-bought Themes into the permanent profile -- session.state.ownedThemes
	-- also contains the always-free default AND any Game-Pass-granted Themes
	-- (via applyGamePassGrants), and neither of those belongs in
	-- profile.ownedThemeIds. The free default doesn't need remembering (it's
	-- always free regardless). A Game-Pass Theme baking itself into the
	-- permanent profile would be worse than redundant -- MarketplaceService
	-- ownership can be REVOKED (a Robux refund), and startNewSession seeds a
	-- fresh RunState straight from this profile with no ownership re-check,
	-- so a revoked Theme would stay permanently equippable forever if it
	-- ever got recorded here. GamePasses.passForTheme(themeId) is exactly
	-- the same "is this Theme gamepass-gated" check Themes.lua's header
	-- describes -- excluding anything it returns non-nil for keeps this
	-- field scoped to what its own name/comment promise: Tips purchases only.
	local themeIds = {}
	for themeId in pairs(session.state.ownedThemes) do
		if themeId ~= Themes.DefaultThemeId and not GamePasses.passForTheme(themeId) then
			table.insert(themeIds, themeId)
		end
	end

	local changed = false
	if PlayerProfile.recordPatronsFound(profile, patronIds) then
		changed = true
	end
	if PlayerProfile.recordThemesOwned(profile, themeIds) then
		changed = true
	end
	if PlayerProfile.recordNightReached(profile, session.state.night) then
		changed = true
	end
	if session.state.wonRun and not session.lastKnownWonRun then
		session.lastKnownWonRun = true
		PlayerProfile.recordRunWon(profile)
		changed = true
	end

	if changed then
		profileDirty[player] = true
	end
end

-- DAILY CHALLENGE (Phase 11): updates dailyPending[player] whenever THIS
-- player's depth in their current Daily Challenge run improves on
-- whatever's already queued -- see the "Daily Challenge Leaderboard"
-- section above for why this never calls DataStoreService directly.
-- No-ops entirely for a non-Daily session (session.isDaily false/nil).
local function trackDailyProgress(player)
	local session = sessions[player]
	if not session or not session.isDaily then
		return
	end

	local depth = computeDailyDepth(session.state)
	local pending = dailyPending[player]
	if pending and pending.dateKey == session.dailyDateKey and pending.depth >= depth then
		return -- nothing new to record
	end

	dailyPending[player] = {
		dateKey = session.dailyDateKey,
		depth = depth,
		tips = math.max(0, math.min(math.floor(session.state.tips), DAILY_TIPS_CAP)),
	}
	dailyDirty[player] = true
end

-- WEEKLY CHALLENGE (Phase 16): same idea as trackDailyProgress just
-- above, gated on session.isWeekly/session.weeklyDateKey instead.
local function trackWeeklyProgress(player)
	local session = sessions[player]
	if not session or not session.isWeekly then
		return
	end

	local depth = computeDailyDepth(session.state) -- same depth formula, not Daily-specific despite the name
	local pending = weeklyPending[player]
	if pending and pending.weekKey == session.weeklyDateKey and pending.depth >= depth then
		return -- nothing new to record
	end

	weeklyPending[player] = {
		weekKey = session.weeklyDateKey,
		depth = depth,
		tips = math.max(0, math.min(math.floor(session.state.tips), DAILY_TIPS_CAP)),
	}
	weeklyDirty[player] = true
end

local function pushState(player)
	local session = sessions[player]
	if not session then
		return
	end
	syncProfileFromSession(player)
	trackDailyProgress(player)
	trackWeeklyProgress(player)
	StateUpdatedRemote:FireClient(player, serializeState(session, player))
end

-- ===== Real-money Game Passes (see Shared/Engine/GamePasses.lua) =====
-- Placed here (not up by `ownedGamePasses`'s own declaration) because it
-- needs to call pushState, which -- as a `local function` -- only exists
-- for code appearing textually below its own definition.

-- Copies whatever this player currently owns from ownedGamePasses into
-- their live RunState.ownedThemes, so RunState.equipTheme's existing
-- "owned themes only" check just works for gamepass-granted themes with
-- zero changes needed to RunState.lua itself. Safe to call repeatedly
-- (only ever sets true, never unsets) -- called both right after a fresh
-- RunState is built (startNewSession, below) and again whenever a Game
-- Pass ownership check finishes, since the async check can resolve
-- after that.
local function applyGamePassGrants(player)
	local session = sessions[player]
	local owned = ownedGamePasses[player]
	if not session or not owned then
		return
	end
	local grantedAny = false
	for _, pass in ipairs(GamePasses.Definitions) do
		if owned[pass.id] and pass.grantsThemes then
			for _, themeId in ipairs(pass.grantsThemes) do
				if not session.state.ownedThemes[themeId] then
					session.state.ownedThemes[themeId] = true
					grantedAny = true
				end
			end
		end
	end
	if grantedAny then
		pushState(player)
	end
end

-- Checks every catalog entry's real ownership via MarketplaceService and
-- caches the result. gamePassId == 0 means "not created on the Creator
-- Dashboard yet" (see GamePasses.lua's header) -- skipped entirely so
-- Studio testing before that setup doesn't spam failed lookups. Each
-- check is its own task.spawn so one slow/failed lookup can't hold up
-- the others.
local function refreshOwnedGamePasses(player)
	ownedGamePasses[player] = ownedGamePasses[player] or {}
	for _, pass in ipairs(GamePasses.Definitions) do
		if pass.gamePassId and pass.gamePassId > 0 then
			task.spawn(function()
				local ok, owns = pcall(function()
					return MarketplaceService:UserOwnsGamePassAsync(player.UserId, pass.gamePassId)
				end)
				if not player.Parent then
					return -- left the game while this lookup was in flight
				end
				if ok then
					if owns then
						-- BUGFIX (Phase 9 QoL passes, caught by independent
						-- review before shipping): applyGamePassGrants only
						-- calls pushState when it actually grants a Theme --
						-- correct for all_themes, but fast_forward/
						-- custom_jukebox grant nothing into RunState at all
						-- (ownership alone is the whole feature, checked
						-- client-side via ownedGamePassIds), so that branch
						-- never fired for them. A player buying either one
						-- would have this recorded server-side immediately,
						-- but the client's ownedGamePassIds would stay stale
						-- -- Settings' Custom Jukebox section (or Fast
						-- Forward) would keep showing "Get Pass" -- until
						-- some UNRELATED action happened to trigger any of
						-- the other pushState call sites. Fixed by pushing
						-- state here too, specifically when a pass is newly
						-- recorded as owned (not on every redundant re-check
						-- -- PlayerAdded/a repeat purchase-finished event can
						-- call this again for an already-known pass, and
						-- that shouldn't cost a render on the client).
						local alreadyKnown = ownedGamePasses[player][pass.id] == true
						ownedGamePasses[player][pass.id] = true
						applyGamePassGrants(player)
						if not alreadyKnown then
							pushState(player)
						end
					end
				else
					warn(string.format("UserOwnsGamePassAsync failed for %s / %s: %s", player.Name, pass.id, tostring(owns)))
				end
			end)
		end
	end
end

-- Refresh the cache the moment a purchase prompt closes -- if it was
-- actually bought, this fires almost immediately after PromptGamePassPurchase
-- resolves, so the newly-owned Theme becomes equippable without needing a
-- rejoin. Fires on the server regardless of which client (if any) prompted it.
MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, gamePassId, wasPurchased)
	if wasPurchased then
		refreshOwnedGamePasses(player)
	end
end)

-- deckVariantId/difficultyId are optional -- RunState.new falls back to the
-- standard/standard defaults for nil or unrecognized ids. Requires
-- profiles[player] to already be loaded (see onPlayerAdded below) -- every
-- call site in this file is after that, including the initial join.
--
-- DAILY CHALLENGE (Phase 11) / WEEKLY CHALLENGE + SEED CODES (Phase 16):
-- pass a `seededRng` (from SeededRng.new) plus a `seedMode` of
-- "daily"/"weekly"/"seed" to start a seeded run instead of a normal one
-- -- forces deckVariantId/difficultyId to "standard"/"standard"
-- regardless of what was passed in, same as every seeded run, so
-- everyone actually starts from the identical place. `seedLabel` is the
-- dateKey (daily/weekly) or the code itself (seed), shipped to the
-- client via serializeState so the HUD can show which mode this run is
-- and, for seed runs, which code. Omitted/nil seededRng behaves exactly
-- like before this parameter existed -- a normal math.random run.
local function startNewSession(player, deckVariantId, difficultyId, seededRng, seedMode, seedLabel)
	-- PERSISTENT SAVE (Phase 10): seed the fresh RunState's owned Themes
	-- with whatever this player has permanently bought with Tips in a past
	-- run, on top of the always-free default RunState.new adds on its own
	-- -- see RunState.new's own comment on ownedThemeIds and
	-- Themes.lua's header for the gap this closes.
	local ownedThemeIds = {}
	local profile = profiles[player]
	if profile then
		for themeId in pairs(profile.ownedThemeIds) do
			table.insert(ownedThemeIds, themeId)
		end
	end

	local isDaily = seedMode == "daily"
	local isWeekly = seedMode == "weekly"
	local isSeeded = seedMode == "seed"
	local forceStandard = seededRng ~= nil -- every seeded mode (daily/weekly/seed) forces standard/standard, for the same "everyone/both of you actually start from the identical place" reason Daily always has

	sessions[player] = {
		state = RunState.new({
			deckVariantId = forceStandard and "standard" or deckVariantId,
			difficultyId = forceStandard and "standard" or difficultyId,
			ownedThemeIds = ownedThemeIds,
		}, seededRng),
		-- ROUND SELECT FEATURE: every run now opens on the Round Select
		-- screen for Round 1 (matching the reference game showing Blind
		-- Select even before the very first blind), not straight into
		-- "playing".
		phase = "roundSelect",
		shopOffers = {},
		packOffers = {},
		voucherOffer = nil,
		rerollCost = REROLL_BASE_COST,
		-- PERSISTENT SAVE (Phase 10): tracks the wonRun false->true
		-- transition so syncProfileFromSession's PlayerProfile.recordRunWon
		-- fires exactly once per run, not on every pushState after Night 8
		-- clears (wonRun stays true for the rest of that Endless Mode run).
		lastKnownWonRun = false,
		-- DAILY CHALLENGE (Phase 11): isDaily gates trackDailyProgress
		-- above and is shipped to the client (serializeState) so the HUD
		-- can show it's a Daily Challenge run. dailyDateKey is fixed at
		-- the moment the run STARTS (not re-derived later), so a run that
		-- happens to cross a UTC midnight while still in progress keeps
		-- submitting to the day it actually started on, not "today."
		isDaily = isDaily,
		dailyDateKey = isDaily and seedLabel or nil,
		-- WEEKLY CHALLENGE / SEED CODES (Phase 16): same fixed-at-start
		-- reasoning as dailyDateKey's comment above -- a Weekly run that
		-- happens to cross into a new 7-day window while still in
		-- progress keeps submitting to the window it actually started
		-- on. Seed runs have no leaderboard, so seedCode is purely a
		-- label for the HUD ("Seed Run: STORM7") -- nothing reads it
		-- back out for scoring.
		isWeekly = isWeekly,
		weeklyDateKey = isWeekly and seedLabel or nil,
		isSeeded = isSeeded,
		seedCode = isSeeded and seedLabel or nil,
	}

	if profile then
		PlayerProfile.recordRunStarted(profile)
		profileDirty[player] = true
	end

	-- Re-grant any already-known-owned Game Pass Themes to this fresh
	-- RunState immediately (covers "New Run..."/restart -- ownership was
	-- already fetched once for this player and doesn't need re-checking).
	applyGamePassGrants(player)
	pushState(player)
end

-- PERSISTENT SAVE (Phase 10): profile load has to happen (and finish --
-- GetAsync yields) BEFORE startNewSession, since it needs
-- profiles[player].ownedThemeIds to seed the fresh RunState. Consolidated
-- into one PlayerAdded handler instead of the 2 independent ones this used
-- to be, specifically to guarantee that ordering.
local function onPlayerAdded(player)
	profiles[player] = loadProfile(player)
	startNewSession(player)
	refreshOwnedGamePasses(player)
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(function(player)
	-- Final save attempt before this player's data goes away -- on top of
	-- the AUTOSAVE_INTERVAL safety net, this is the normal/expected save
	-- path for a player who just leaves normally.
	saveProfile(player)
	saveDailyScore(player) -- DAILY CHALLENGE (Phase 11)
	saveWeeklyScore(player) -- WEEKLY CHALLENGE (Phase 16)
	sessions[player] = nil
	ownedGamePasses[player] = nil
	profiles[player] = nil
	profileDirty[player] = nil
	dailyPending[player] = nil
	dailyDirty[player] = nil
	lastLeaderboardRequest[player] = nil
	weeklyPending[player] = nil
	weeklyDirty[player] = nil
	lastWeeklyLeaderboardRequest[player] = nil
end)

-- In Studio, PlayerAdded may have already fired for existing test players.
for _, player in ipairs(Players:GetPlayers()) do
	onPlayerAdded(player)
end

-- PERSISTENT SAVE (Phase 10) / DAILY CHALLENGE (Phase 11): a lightweight
-- crash-safety net between joins/leaves -- PlayerRemoving above is the
-- normal save path for both, this just covers a server crash/unexpected
-- shutdown that skips straight past it.
task.spawn(function()
	while true do
		task.wait(AUTOSAVE_INTERVAL)
		for _, player in ipairs(Players:GetPlayers()) do
			if profileDirty[player] then
				saveProfile(player)
			end
			if dailyDirty[player] then
				saveDailyScore(player)
			end
			if weeklyDirty[player] then
				saveWeeklyScore(player)
			end
		end
	end
end)

-- PERSISTENT SAVE (Phase 10) / DAILY CHALLENGE (Phase 11): flush every
-- remaining player's profile AND pending Daily Challenge score before the
-- server actually shuts down (Studio Stop, or a live server closing).
-- Roblox gives BindToClose roughly 30s (often less in Studio) before
-- forcing the shutdown regardless of whether this callback has returned,
-- so this polls a bounded number of times instead of waiting unboundedly
-- on a stuck DataStore call.
game:BindToClose(function()
	local pending = 0
	for _, player in ipairs(Players:GetPlayers()) do
		if profiles[player] then
			pending = pending + 1
			task.spawn(function()
				saveProfile(player)
				pending = pending - 1
			end)
		end
		if dailyDirty[player] then
			pending = pending + 1
			task.spawn(function()
				saveDailyScore(player)
				pending = pending - 1
			end)
		end
		if weeklyDirty[player] then
			pending = pending + 1
			task.spawn(function()
				saveWeeklyScore(player)
				pending = pending - 1
			end)
		end
	end
	local waited = 0
	while pending > 0 and waited < 25 do
		task.wait(0.25)
		waited = waited + 0.25
	end
end)

-- ===== 6. Remote handlers =====
-- NOTE: every handler re-validates on the server. Never trust the client --
-- a player could fire these remotes directly with bogus data.

local function isValidIndexList(list, handSize)
	if type(list) ~= "table" or #list < 1 or #list > 5 then
		return false
	end
	local seen = {}
	for _, i in ipairs(list) do
		if type(i) ~= "number" or i < 1 or i > handSize or seen[i] then
			return false
		end
		seen[i] = true
	end
	return true
end

PlayHandRemote.OnServerEvent:Connect(function(player, cardIndices)
	local session = sessions[player]
	if not session or session.phase ~= "playing" then
		return
	end
	if not isValidIndexList(cardIndices, #session.state.hand) then
		return
	end

	local ok, result = pcall(RunState.playHand, session.state, cardIndices)
	if not ok then
		warn("PlayHand error for " .. player.Name .. ": " .. tostring(result))
		return
	end

	if result.roundWon then
		session.phase = "shop"
		openShop(session)
	elseif result.runOver then
		session.phase = "gameover"
	end

	pushState(player)
end)

DiscardRemote.OnServerEvent:Connect(function(player, cardIndices)
	local session = sessions[player]
	if not session or session.phase ~= "playing" then
		return
	end
	if not isValidIndexList(cardIndices, #session.state.hand) then
		return
	end
	if session.state.discardsRemaining <= 0 then
		return
	end

	local ok, err = pcall(RunState.discard, session.state, cardIndices)
	if not ok then
		warn("Discard error for " .. player.Name .. ": " .. tostring(err))
		return
	end

	pushState(player)
end)

BuyPatronRemote.OnServerEvent:Connect(function(player, patronId)
	local session = sessions[player]
	if not session or session.phase ~= "shop" then
		return
	end
	-- Finish resolving an open Pack reveal before doing anything else in the
	-- shop -- same as the reference game, a Pack takes over the whole shop
	-- screen until you pick (or skip).
	if session.state.pendingPack then
		return
	end
	if type(patronId) ~= "string" then
		return
	end

	-- Only allow buying patrons that were actually offered this shop visit.
	local offered = false
	for _, patron in ipairs(session.shopOffers) do
		if patron.id == patronId then
			offered = true
			break
		end
	end
	if not offered then
		return
	end

	local ok = RunState.buyPatron(session.state, patronId)
	if ok then
		-- Remove the bought offer so it can't be bought twice this visit.
		for i, patron in ipairs(session.shopOffers) do
			if patron.id == patronId then
				table.remove(session.shopOffers, i)
				break
			end
		end
	end

	pushState(player)
end)

-- Discarding an owned Patron, like theme purchases below, isn't gated to
-- the shop phase -- it's tidying up your table, not a purchase decision
-- tied to a specific shop visit's offers.
SellPatronRemote.OnServerEvent:Connect(function(player, patronId)
	local session = sessions[player]
	if not session then
		return
	end
	if type(patronId) ~= "string" then
		return
	end

	RunState.sellPatron(session.state, patronId)
	pushState(player)
end)

-- ===== Recipes (House/Menu/Secret) -- Phase 1b =====
-- Buying AND using are both gated to the shop phase: House/Secret
-- Recipes target cards in state.hand, and the only hand a player can see
-- while the shop overlay is open is whatever's left over from the round
-- they just won -- so "shop visit" is the one moment using one makes
-- sense in the current UI. Menu Recipes don't need cards at all but are
-- gated the same way for a single consistent rule.

local RECIPE_CATEGORIES = {
	house = { catalog = Recipes.HouseRecipes, buy = RunState.buyHouseRecipe, use = RunState.useHouseRecipe },
	menu = { catalog = Recipes.MenuRecipes, buy = RunState.buyMenuRecipe, use = RunState.useMenuRecipe },
	secret = { catalog = Recipes.SecretRecipes, buy = RunState.buySecretRecipe, use = RunState.useSecretRecipe },
}

local function findRecipe(catalog, id)
	for _, recipe in ipairs(catalog) do
		if recipe.id == id then
			return recipe
		end
	end
	return nil
end

BuyRecipeRemote.OnServerEvent:Connect(function(player, category, id)
	local session = sessions[player]
	if not session or session.phase ~= "shop" then
		return
	end
	if session.state.pendingPack then
		return
	end
	local def = RECIPE_CATEGORIES[category]
	if not def or type(id) ~= "string" or not findRecipe(def.catalog, id) then
		return
	end

	local ok, err = pcall(def.buy, session.state, id)
	if not ok then
		warn("BuyRecipe error for " .. player.Name .. ": " .. tostring(err))
		return
	end

	pushState(player)
end)

UseRecipeRemote.OnServerEvent:Connect(function(player, category, id, cardIndices, suit)
	local session = sessions[player]
	if not session or session.phase ~= "shop" then
		return
	end
	if session.state.pendingPack then
		return
	end
	local def = RECIPE_CATEGORIES[category]
	if not def or type(id) ~= "string" then
		return
	end
	local recipe = findRecipe(def.catalog, id)
	if not recipe then
		return
	end

	local opts = {}
	if recipe.cardCount then
		if not isValidIndexList(cardIndices, #session.state.hand) then
			return
		end
		if #cardIndices < recipe.cardCount.min or #cardIndices > recipe.cardCount.max then
			return
		end
		opts.cardIndices = cardIndices
	end
	if recipe.needsSuit then
		if type(suit) ~= "string" then
			return
		end
		opts.suit = suit
	end

	local ok, err = pcall(def.use, session.state, id, opts)
	if not ok then
		warn("UseRecipe error for " .. player.Name .. ": " .. tostring(err))
		return
	end

	pushState(player)
end)

-- ===== Reroll / Packs / House Passes (Vouchers) =====
-- The shop is now randomized every visit (2 Patron offers + 2 Pack offers +
-- an occasional Voucher, see openShop/pickVoucherOffer above) instead of a
-- static full-catalog browse -- matches the reference game and makes the
-- Reroll button a real decision (spend Tips now for a fresh set of offers).

RerollShopRemote.OnServerEvent:Connect(function(player)
	local session = sessions[player]
	if not session or session.phase ~= "shop" then
		return
	end
	if session.state.pendingPack then
		return
	end
	local cost = RunState.rerollCost(session.state, session.rerollCost or REROLL_BASE_COST)
	if session.state.tips < cost then
		return
	end
	session.state.tips = session.state.tips - cost
	rollShopOffers(session)
	session.rerollCost = (session.rerollCost or REROLL_BASE_COST) + REROLL_COST_STEP
	pushState(player)
end)

BuyPackRemote.OnServerEvent:Connect(function(player, packId)
	local session = sessions[player]
	if not session or session.phase ~= "shop" then
		return
	end
	if session.state.pendingPack then
		return
	end
	if type(packId) ~= "string" then
		return
	end

	-- Only allow buying packs that were actually offered this shop visit --
	-- same rule as Patron offers above.
	local offered = false
	for _, pack in ipairs(session.packOffers) do
		if pack.id == packId then
			offered = true
			break
		end
	end
	if not offered then
		return
	end

	local ok, revealOrErr = pcall(RunState.openPack, session.state, packId)
	if not ok then
		warn("BuyPack error for " .. player.Name .. ": " .. tostring(revealOrErr))
		return
	end
	if not revealOrErr then
		-- Logical failure (e.g. not enough tips) -- leave the offer in place,
		-- nothing was charged.
		return
	end

	for i, pack in ipairs(session.packOffers) do
		if pack.id == packId then
			table.remove(session.packOffers, i)
			break
		end
	end
	pushState(player)
end)

ResolvePackRemote.OnServerEvent:Connect(function(player, chosenIds)
	local session = sessions[player]
	if not session or session.phase ~= "shop" then
		return
	end
	if type(chosenIds) ~= "table" or #chosenIds > 10 then
		return
	end
	for _, id in ipairs(chosenIds) do
		if type(id) ~= "string" then
			return
		end
	end

	local ok, err = pcall(RunState.resolvePack, session.state, chosenIds)
	if not ok then
		warn("ResolvePack error for " .. player.Name .. ": " .. tostring(err))
		return
	end

	pushState(player)
end)

BuyHousePassRemote.OnServerEvent:Connect(function(player, passId)
	local session = sessions[player]
	if not session or session.phase ~= "shop" then
		return
	end
	if session.state.pendingPack then
		return
	end
	if type(passId) ~= "string" then
		return
	end
	if not session.voucherOffer or session.voucherOffer.id ~= passId then
		return
	end

	local ok = RunState.buyHousePass(session.state, passId)
	if ok then
		session.voucherOffer = nil
	end
	pushState(player)
end)

-- Cosmetic theme purchases/equips are allowed any time (not gated to the
-- shop phase) -- they don't affect gameplay, so there's no reason to lock
-- them to between-round moments the way Patron purchases are.

BuyThemeRemote.OnServerEvent:Connect(function(player, themeId)
	local session = sessions[player]
	if not session then
		return
	end
	if type(themeId) ~= "string" then
		return
	end

	local ok, err = pcall(RunState.buyTheme, session.state, themeId)
	if not ok then
		warn("BuyTheme error for " .. player.Name .. ": " .. tostring(err))
		return
	end

	pushState(player)
end)

EquipThemeRemote.OnServerEvent:Connect(function(player, themeId)
	local session = sessions[player]
	if not session then
		return
	end
	if type(themeId) ~= "string" then
		return
	end

	local ok, err = pcall(RunState.equipTheme, session.state, themeId)
	if not ok then
		warn("EquipTheme error for " .. player.Name .. ": " .. tostring(err))
		return
	end

	pushState(player)
end)

-- ACHIEVEMENTS + TITLES (Phase 16): operates on the permanent
-- `profiles[player]`, not the per-run `session.state`, since a Title is
-- a cross-run choice (same reasoning ownedThemeIds moved to
-- PlayerProfile for in PERSISTENT SAVE, Phase 10) -- still gated on an
-- active session existing, purely so a stray remote fire from a not-
-- fully-loaded client can't do anything. `titleId == nil` is a valid,
-- intentional "clear my equipped title" call, not a malformed one.
EquipTitleRemote.OnServerEvent:Connect(function(player, titleId)
	local session = sessions[player]
	local profile = profiles[player]
	if not session or not profile then
		return
	end
	if titleId ~= nil and type(titleId) ~= "string" then
		return
	end

	-- Unlike BuyTheme/EquipTheme's handlers above, this checks 2 separate
	-- things: `didNotError` (pcall's own "didn't throw" result) AND
	-- `equipOk` (PlayerProfile.equipTitle's own true/false return) -- so a
	-- REJECTED equip (not unlocked, bad id -- equipTitle returning false,
	-- not throwing) doesn't fall through to an unnecessary
	-- profileDirty/pushState the way a genuine successful change should.
	local didNotError, equipOk = pcall(PlayerProfile.equipTitle, profile, titleId)
	if not didNotError then
		warn("EquipTitle error for " .. player.Name .. ": " .. tostring(equipOk))
		return
	end
	if not equipOk then
		return
	end

	profileDirty[player] = true
	pushState(player)
end)

-- JUKEBOX PLAYLIST (requested fix): same shape as EquipTitleRemote's
-- handler just above -- operates on the permanent `profiles[player]` (a
-- saved track list is a cross-run choice, same reasoning as
-- equippedTitleId), gated on an active session existing purely so a stray
-- remote fire from a not-fully-loaded client can't do anything, and
-- checks BOTH pcall's own success AND PlayerProfile's own true/false
-- result so a rejected add (malformed id, duplicate, playlist full)
-- doesn't fall through to an unnecessary profileDirty/pushState.
AddPlaylistSongRemote.OnServerEvent:Connect(function(player, assetId)
	local session = sessions[player]
	local profile = profiles[player]
	if not session or not profile then
		return
	end
	if type(assetId) ~= "string" then
		return
	end

	local didNotError, ok = pcall(PlayerProfile.addPlaylistSong, profile, assetId)
	if not didNotError then
		warn("AddPlaylistSong error for " .. player.Name .. ": " .. tostring(ok))
		return
	end
	if not ok then
		return
	end

	profileDirty[player] = true
	pushState(player)
end)

RemovePlaylistSongRemote.OnServerEvent:Connect(function(player, assetId)
	local session = sessions[player]
	local profile = profiles[player]
	if not session or not profile then
		return
	end
	if type(assetId) ~= "string" then
		return
	end

	local didNotError, ok = pcall(PlayerProfile.removePlaylistSong, profile, assetId)
	if not didNotError then
		warn("RemovePlaylistSong error for " .. player.Name .. ": " .. tostring(ok))
		return
	end
	if not ok then
		return
	end

	profileDirty[player] = true
	pushState(player)
end)

-- JUKEBOX PLAYLIST REORDER (requested fix: "reordering songs ... move
-- songs up/down in My Playlist"): same shape as Add/RemovePlaylistSong
-- just above. direction must be exactly -1 or 1 -- anything else (a typo,
-- a tampered client) is rejected the same way PlayerProfile.
-- movePlaylistSong itself rejects it, just one layer earlier so a
-- malformed number can't even reach pcall.
MovePlaylistSongRemote.OnServerEvent:Connect(function(player, assetId, direction)
	local session = sessions[player]
	local profile = profiles[player]
	if not session or not profile then
		return
	end
	if type(assetId) ~= "string" then
		return
	end
	if direction ~= -1 and direction ~= 1 then
		return
	end

	local didNotError, ok = pcall(PlayerProfile.movePlaylistSong, profile, assetId, direction)
	if not didNotError then
		warn("MovePlaylistSong error for " .. player.Name .. ": " .. tostring(ok))
		return
	end
	if not ok then
		return
	end

	profileDirty[player] = true
	pushState(player)
end)

-- TUTORIAL (Phase 16): fired once by Client/Tutorial.lua when the
-- walkthrough is dismissed (either "Got it!" on the last step, or
-- "Skip") -- idempotent, so no harm if it somehow fires more than once
-- for the same player.
MarkTutorialSeenRemote.OnServerEvent:Connect(function(player)
	local profile = profiles[player]
	if not profile then
		return
	end
	if profile.hasSeenTutorial then
		return -- already marked -- nothing changed, no need to dirty/push
	end
	PlayerProfile.markTutorialSeen(profile)
	profileDirty[player] = true
	pushState(player)
end)

AdvanceRoundRemote.OnServerEvent:Connect(function(player)
	local session = sessions[player]
	if not session or session.phase ~= "shop" then
		return
	end
	-- Resolve (or skip) any open Pack before leaving the shop.
	if session.state.pendingPack then
		return
	end

	local ok, err = pcall(RunState.advanceToNextRound, session.state)
	if not ok then
		warn("AdvanceRound error for " .. player.Name .. ": " .. tostring(err))
		return
	end

	-- ROUND SELECT FEATURE: land on the Round Select screen for the new
	-- round instead of dropping straight into "playing" -- gives the
	-- player a chance to see (and possibly skip) it first, same as
	-- opening a fresh run.
	session.phase = "roundSelect"
	session.shopOffers = {}
	session.packOffers = {}
	session.voucherOffer = nil
	-- Safety net, not the normal path: a pack should always be resolved
	-- (or skipped) before Next Round is even clickable client-side, but
	-- don't leave a stale one open across the round boundary if it happens.
	session.state.pendingPack = nil
	pushState(player)
end)

-- JOURNEY FEATURE: skip the current round outright for a smaller Tips
-- reward -- see RunState.skipRound's header comment for the full rules
-- (never the Boss round, never once you've touched the round). Only
-- reachable from the "playing" phase, same as PlayHand/Discard -- there's
-- nothing to skip while the shop or game-over screen is up.
-- ROUND SELECT FEATURE: both only fire from the "roundSelect" phase --
-- there's nothing to Select/Skip once you've already committed to playing
-- (or you're mid-shop/game-over). See RunState.canSkipRound/skipRound and
-- Tags.lua for the actual rules/rewards.

SelectRoundRemote.OnServerEvent:Connect(function(player)
	local session = sessions[player]
	if not session or session.phase ~= "roundSelect" then
		return
	end
	session.phase = "playing"
	pushState(player)
end)

SkipRoundRemote.OnServerEvent:Connect(function(player)
	local session = sessions[player]
	if not session or session.phase ~= "roundSelect" then
		return
	end
	if not RunState.canSkipRound(session.state) then
		return
	end

	local ok, err = pcall(RunState.skipRound, session.state)
	if not ok then
		warn("SkipRound error for " .. player.Name .. ": " .. tostring(err))
		return
	end

	-- Stays in "roundSelect" -- skipping shows the SAME screen again for
	-- whatever round you're now on (skipRound already advanced state.round
	-- and dealt it fresh), same as the reference game returning you to
	-- Blind Select for the next blind after a skip.
	pushState(player)
end)

RestartRunRemote.OnServerEvent:Connect(function(player)
	local session = sessions[player]
	if not session then
		return
	end
	-- Quick restart: keep whatever Deck Variant/Difficulty this player last
	-- used. Use StartRun instead to pick fresh ones via the Run Setup screen.
	startNewSession(player, session.state.deckVariantId, session.state.difficultyId)
end)

StartRunRemote.OnServerEvent:Connect(function(player, deckVariantId, difficultyId)
	if not sessions[player] then
		return
	end
	if type(deckVariantId) ~= "string" then
		deckVariantId = nil
	end
	if type(difficultyId) ~= "string" then
		difficultyId = nil
	end
	startNewSession(player, deckVariantId, difficultyId)
end)

-- ===== Daily Challenge (Phase 11) =====

StartDailyChallengeRemote.OnServerEvent:Connect(function(player)
	if not sessions[player] then
		return
	end
	local seed = SeededRng.dailySeed()
	startNewSession(player, nil, nil, SeededRng.new(seed), "daily", SeededRng.dailyDateKey())
end)

-- RemoteFunction, not RemoteEvent -- the client needs the actual
-- leaderboard data BACK, not just a fire-and-forget notification. Always
-- returns TODAY's board (no "browse past days" in this pass). Fetches 2
-- things: the top 10 by combinedScore (GetSortedAsync), and this player's
-- own best for today specifically (a direct GetAsync by their own key,
-- NOT scraped out of the top-10 page -- correct even when their best
-- isn't good enough to place in the top 10 at all). Whichever of the two
-- DataStore calls fails, the OTHER still returns normally -- `ok`/
-- `yourBestOk` are reported separately so the client can tell "nobody's
-- beaten you yet" apart from "couldn't check."
GetDailyLeaderboardRemote.OnServerInvoke = function(player)
	local now = os.clock()
	if lastLeaderboardRequest[player] and now - lastLeaderboardRequest[player] < LEADERBOARD_COOLDOWN then
		return { ok = false, dateKey = SeededRng.dailyDateKey(), top = {}, yourBest = nil, yourBestOk = false }
	end
	lastLeaderboardRequest[player] = now

	local dateKey = SeededRng.dailyDateKey()
	local store = getDailyStore(dateKey)

	local top = {}
	local ok = pcall(function()
		local pages = store:GetSortedAsync(false, 10) -- false = descending, highest combinedScore first
		local page = pages:GetCurrentPage()
		for _, entry in ipairs(page) do
			local userId = tonumber(entry.key)
			local combinedScore = entry.value
			local name = nil
			if userId then
				local nameOk, resolvedName = pcall(function()
					return Players:GetNameFromUserIdAsync(userId)
				end)
				if nameOk then
					name = resolvedName
				end
			end
			table.insert(top, {
				userId = userId,
				name = name or "???",
				depth = math.floor(combinedScore / DAILY_SCORE_MULTIPLIER),
				tips = combinedScore % DAILY_SCORE_MULTIPLIER,
			})
		end
	end)

	-- Authoritative "your best" comes from the DataStore itself (this
	-- player's own already-SAVED entry), not just the in-memory
	-- dailyPending snapshot -- covers a player who submitted a score in an
	-- earlier server session (e.g. before a rejoin) and hasn't started a
	-- new Daily Challenge run yet THIS session, where dailyPending would
	-- otherwise be empty. If they DO have a higher not-yet-saved
	-- improvement pending this session, that's shown instead, so a fresh
	-- personal best doesn't look like it "didn't count" just because the
	-- autosave hasn't flushed it yet.
	local yourBest = nil
	local yourBestOk = pcall(function()
		local raw = store:GetAsync(tostring(player.UserId))
		if type(raw) == "number" then
			yourBest = {
				depth = math.floor(raw / DAILY_SCORE_MULTIPLIER),
				tips = raw % DAILY_SCORE_MULTIPLIER,
			}
		end
	end)
	local pending = dailyPending[player]
	if pending and pending.dateKey == dateKey and (not yourBest or pending.depth > yourBest.depth) then
		yourBest = { depth = pending.depth, tips = pending.tips }
	end

	return {
		ok = ok,
		dateKey = dateKey,
		top = top,
		yourBest = yourBest,
		yourBestOk = yourBestOk,
	}
end

-- ===== Weekly Challenge (Phase 16) =====
-- Deliberately a straight copy of the Daily Challenge handlers just
-- above -- same request/response shape, just Weekly's tables/store/seed
-- functions in place of Daily's. See "Weekly Challenge Leaderboard"
-- section (near saveDailyScore) for why these stayed separate functions
-- instead of a parameterized shared one.

StartWeeklyChallengeRemote.OnServerEvent:Connect(function(player)
	if not sessions[player] then
		return
	end
	local seed = SeededRng.weeklySeed()
	startNewSession(player, nil, nil, SeededRng.new(seed), "weekly", SeededRng.weeklyDateKey())
end)

GetWeeklyLeaderboardRemote.OnServerInvoke = function(player)
	local now = os.clock()
	if lastWeeklyLeaderboardRequest[player] and now - lastWeeklyLeaderboardRequest[player] < LEADERBOARD_COOLDOWN then
		return { ok = false, dateKey = SeededRng.weeklyDateKey(), top = {}, yourBest = nil, yourBestOk = false }
	end
	lastWeeklyLeaderboardRequest[player] = now

	local weekKey = SeededRng.weeklyDateKey()
	local store = getWeeklyStore(weekKey)

	local top = {}
	local ok = pcall(function()
		local pages = store:GetSortedAsync(false, 10)
		local page = pages:GetCurrentPage()
		for _, entry in ipairs(page) do
			local userId = tonumber(entry.key)
			local combinedScore = entry.value
			local name = nil
			if userId then
				local nameOk, resolvedName = pcall(function()
					return Players:GetNameFromUserIdAsync(userId)
				end)
				if nameOk then
					name = resolvedName
				end
			end
			table.insert(top, {
				userId = userId,
				name = name or "???",
				depth = math.floor(combinedScore / DAILY_SCORE_MULTIPLIER),
				tips = combinedScore % DAILY_SCORE_MULTIPLIER,
			})
		end
	end)

	local yourBest = nil
	local yourBestOk = pcall(function()
		local raw = store:GetAsync(tostring(player.UserId))
		if type(raw) == "number" then
			yourBest = {
				depth = math.floor(raw / DAILY_SCORE_MULTIPLIER),
				tips = raw % DAILY_SCORE_MULTIPLIER,
			}
		end
	end)
	local pending = weeklyPending[player]
	if pending and pending.weekKey == weekKey and (not yourBest or pending.depth > yourBest.depth) then
		yourBest = { depth = pending.depth, tips = pending.tips }
	end

	return {
		ok = ok,
		dateKey = weekKey,
		top = top,
		yourBest = yourBest,
		yourBestOk = yourBestOk,
	}
end

-- ===== Shareable Seed Codes (Phase 16) =====
-- No leaderboard -- this is for two friends comparing one specific run
-- on demand (see SeededRng.lua's header for what "same seed" guarantees
-- once your choices start diverging from theirs), not a ranked board.
-- Server-side validation is deliberately light (just a length/type
-- check) since a bad/garbage code just produces SOME deterministic seed
-- -- there's no invalid input here, only "not the code your friend
-- typed," which is a matched-code problem between the two of you, not a
-- server-side error case.
StartSeedRunRemote.OnServerEvent:Connect(function(player, code)
	if not sessions[player] then
		return
	end
	if type(code) ~= "string" then
		return
	end
	code = string.upper(code)
	if #code < 1 or #code > 20 then
		return
	end
	local seed = SeededRng.codeToSeed(code)
	startNewSession(player, nil, nil, SeededRng.new(seed), "seed", code)
end)
