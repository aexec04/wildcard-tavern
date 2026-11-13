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
local RunService = game:GetService("RunService") -- STUDIO GAME PASS BYPASS (requested fix): see refreshOwnedGamePasses below

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Engine = Shared:WaitForChild("Engine")
local Tests = Shared:WaitForChild("Tests")

local RunState = require(Engine.RunState)
local RunSummary = require(Engine.RunSummary) -- Game Over summary data and the profile badge
local LoginStreak = require(Engine.LoginStreak) -- daily login streak rules
local Seasons = require(Engine.Seasons) -- limited-time seasonal set (dates, unlock, banner)
local NextUnlock = require(Engine.NextUnlock) -- menu 'Next unlock' strip and places seen
local JourneyMap = require(Engine.JourneyMap) -- Journey meta layer: first-clear rewards
local RunAbandon = require(Engine.RunAbandon) -- Settings > Restart Run rule
local TutorialStart = require(Engine.TutorialStart)
local TutorialScript = require(Engine.TutorialScript) -- scripted first-run hands (pair, two pair, flush, straight flush)
local WorldMap = require(Engine.WorldMap) -- branching adventure map: the road of each run
local BiomeRewards = require(Engine.BiomeRewards) -- biome rewards granted at branch ends
local Keys = require(Engine.Keys) -- locked roads and Keys
local Stakes = require(Engine.Stakes) -- difficulty ladder
local Unlocks = require(Engine.Unlocks) -- unlock drip (shop and pack pools, Collection hints)
local unlockSeqCounter = 0 -- ids unlock toasts across runs (see syncProfileFromSession)
local TavernRank = require(Engine.TavernRank) -- account level and rewards
local Quests = require(Engine.Quests) -- daily quests
local AccountProgress = require(Engine.AccountProgress) -- run counters to XP and quest progress
local progressSeqCounter = 0 -- ids progress toasts (rank ups, quests done)
local Analytics = require(Engine.Analytics) -- funnel steps and custom events; errors never reach gameplay
local NextGoal = require(Engine.NextGoal) -- the menu's Next Goal line
local FirstRewards = require(Engine.FirstRewards) -- tutorial and first-win rewards, the one-time follow prompt
local PatronsData = require(Engine.Patrons) -- display names for the Next Goal line
local rewardNotices = {} -- [player] = { seq, text }: one-time reward toasts that outlive a run
local followPrompts = {} -- [player] = seq: asks the client to offer experience notifications once
local storePrompts = {} -- [player] = seq: opens the Store on the Starter Pack once, after the second run
local rewardSeqCounter = 0
local EndlessRules = require(Engine.EndlessRules)
local SaveLock = require(Engine.SaveLock) -- session lease + load retry schedule
local RateLimit = (function() -- per-player token bucket on every remote; also the one place Card Set Preview (look only) rejects run remotes
	local base, Guard = require(Engine.RateLimit), require(Engine.PreviewGuard)
	local wrapped = setmetatable({}, { __index = base })
	function wrapped.allow(userId, key, now)
		local player = game:GetService("Players"):GetPlayerByUserId(userId)
		if player then
			if Guard.ENDS[key] then player:SetAttribute("PreviewMode", nil) end -- a new run or leaving one ends a preview
			if Guard.blocked(key, player:GetAttribute("PreviewMode") == true) then return false end
		end
		return base.allow(userId, key, now)
	end
	return wrapped
end)()
local RunChoice = require(Engine.RunChoice) -- start-of-run draft and between-Night events
local Discoveries = require(Engine.Discoveries) -- hidden map spots
local Challenges = require(Engine.Challenges) -- challenge runs with a twist
local BossRush = require(Engine.BossRush) -- back-to-back boss rounds
local Store = require(Engine.Store) -- the Tavern Store: cosmetics and convenience only
local LiveEvents = require(Engine.LiveEvents) -- timed events (News banner, double XP weekends); never changes fair boards
local funnelSessions = {} -- [player] = id of this visit, for the analytics funnel
local Badges = require(Engine.Badges) -- badges (biome first clear and Master)
local BadgeIds = require(Engine.BadgeIds) -- game badge id -> real Roblox badge id (empty until created)
local SideStops = require(Engine.SideStops) -- shop, shrine and rest stops off the main road
local Minigames = require(Engine.Minigames) -- the four map minigames, scored here
local CardBacks = require(Engine.CardBacks)
local CosmeticSets = require(Engine.CosmeticSets) -- Cosmetic Sets: profile-based, see PlayerProfile.ownedSetIds
local Deck = require(Engine.Deck)
local Recipes = require(Engine.Recipes)
local Shop = require(Engine.Shop)
local Onboarding = require(Engine.Onboarding)
local GamePasses = require(Engine.GamePasses) -- real-money Robux Game Passes (see that file's header for setup steps)
local PlayerProfile = require(Engine.PlayerProfile) -- PERSISTENT SAVE (Phase 10, see that file's header) -- the permanent, cross-run part of a player's progress
local SeededRng = require(Engine.SeededRng) -- DAILY CHALLENGE (Phase 11, see that file's header) -- deterministic rng + the daily seed/date-key it's derived from
local Achievements = require(Engine.Achievements) -- ACHIEVEMENTS + TITLES (Phase 16, see that file's header)
local CollectionBook = require(Engine.CollectionBook) -- COLLECTION: discovery gathering + milestone grants
local Leaderboards = require(Engine.Leaderboards) -- PAID CONTINUE: Standard vs Revived board routing + store names
local DeveloperProducts = require(Engine.DeveloperProducts) -- PAID CONTINUE: consumable Robux products (see that file's header)
local liveLookup = { -- display names for event reward text
	cardBackName = function(id) local d = CardBacks.getById(id) return d and d.name end,
	setName = function(id) local d = CosmeticSets.getById(id) return d and d.name end,
	titleName = function(id) local d = Achievements.getById(id) return d and d.title end,
}

-- ===== 1. Run engine tests on server start =====

-- Never gate startup on the tests: they run in their own thread with a time limit, so a
-- hung test can't stop the Remotes folder from being created (the client waits on it).
do
	local finished = false
	task.spawn(function()
		local okTests, errTests = pcall(function()
			local TestRunner = require(Tests.TestRunner)
			local engineTests = require(Tests.EngineTests)
			print("===== The Gilded Knave: running engine tests =====")
			local results = TestRunner.run(engineTests)
			if results.failed > 0 then
				warn(string.format("%d engine test(s) FAILED, fix these before trusting the game logic!", results.failed))
			end
			print("===================================================")
		end)
		if not okTests then
			warn("[Startup] engine tests could not run (server continues): " .. tostring(errTests))
		end
		finished = true
	end)
	task.delay(10, function()
		if not finished then
			warn("[Startup] engine tests timed out after 10s (a test is yielding); the server continues without them")
		end
	end)
end

-- ===== 2. RemoteEvents =====

local Rem = require(script:WaitForChild("Remotes")) -- all remotes, keyed by remote name (see Remotes.lua)

-- ===== 3. Persistent Player Profile (DataStoreService) =====
-- PERSISTENT SAVE (Phase 10): see Shared/Engine/PlayerProfile.lua's header
-- for exactly what this does and doesn't cover -- short version, discovered
-- Patrons, Tips-bought Cosmetic Sets, and a few small stats now survive a rejoin
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

-- FIRST 5 MINUTES: a one-time reward toast (survives the run that earned it) and the funnel logger.
local function pushRewardNotice(player, notice)
	rewardSeqCounter = rewardSeqCounter + 1
	rewardNotices[player] = { seq = rewardSeqCounter, text = notice.text, blessingId = notice.blessingId }
end
local function logStep(player, stepId)
	local profile = profiles[player]
	if not profile then
		return
	end
	funnelSessions[player] = funnelSessions[player] or (tostring(player.UserId) .. "-" .. tostring(os.time()))
	if Analytics.step(player, profile, stepId, funnelSessions[player]) then
		profileDirty[player] = true
	end
end
local AUTOSAVE_INTERVAL = 120 -- seconds; a crash-safety net between joins/leaves, not the primary save path (PlayerRemoving/BindToClose below are)

local function profileKey(player)
	return "Player_" .. tostring(player.UserId)
end

local saveBlocked = {} -- [player] = true when the stored profile could not be loaded or is held by another server

-- Loads and claims the profile. Retries with backoff (not in Studio); on failure the player still plays with a fresh
-- profile, but saveBlocked is set so that profile can never overwrite the real save.
local function loadProfile(player)
	local key = profileKey(player)
	local delays = RunService:IsStudio() and {} or SaveLock.RETRY_DELAYS
	local lastErr = "locked by another server"
	for attempt = 1, #delays + 1 do
		local claimed, stored = false, nil
		local ok, err = pcall(function()
			ProfileStore:UpdateAsync(key, function(old)
				if SaveLock.canClaim(old, game.JobId, os.time()) then
					claimed, stored = true, old
					local out = {}
					if type(old) == "table" then
						for k, v in pairs(old) do out[k] = v end
					end
					out.sessionLock = { jobId = game.JobId, t = os.time() }
					return out
				end
				claimed = false
				return nil -- cancel: a live server holds this profile
			end)
		end)
		if ok and claimed then
			return PlayerProfile.migrate(stored)
		end
		lastErr = ok and "locked by another server" or tostring(err)
		if attempt <= #delays then
			task.wait(delays[attempt])
		end
	end
	warn(string.format(
		"PlayerProfile load failed for %s (%s), playing with a fresh profile that will NOT be saved this session. In Studio, this usually means \"Enable Studio Access to API Services\" is off (Game Settings -> Security).",
		player.Name, lastErr
	))
	saveBlocked[player] = true
	return PlayerProfile.new()
end

-- `release` (the final save on leave) also clears the lease so the next server can claim at once.
local function saveProfile(player, release)
	local profile = profiles[player]
	if not profile or saveBlocked[player] then
		return
	end
	local written = false
	local ok, err = pcall(function()
		ProfileStore:UpdateAsync(profileKey(player), function(old)
			if not SaveLock.canClaim(old, game.JobId, os.time()) then
				return nil -- another live server owns this profile now: never overwrite it
			end
			written = true
			return SaveLock.stamp(profile, game.JobId, os.time(), release == true)
		end)
	end)
	if ok and written then
		profileDirty[player] = nil
	else
		warn(string.format("PlayerProfile save failed for %s: %s", player.Name, ok and "profile is held by another server" or tostring(err)))
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

-- PAID CONTINUE: every period has a "Standard" and a "Revived" board (see
-- Shared/Engine/Leaderboards.lua), so the pending/dirty tables below are
-- keyed by board too. A run's progress goes to Leaderboards.boardFor(state):
-- whatever it banked before a continue stays on Standard, and everything
-- after goes to Revived.
local boardStoreCache = {} -- [store name] = OrderedDataStore instance, so re-opening the same board doesn't re-fetch a fresh DataStore object every time
local dailyPending = {} -- [player] = { [board] = { dateKey, depth, tips } } -- this player's best Daily Challenge result per board not yet confirmed written
local dailyDirty = {} -- [player] = { [board] = true } while that board's pending entry hasn't been saved yet; nil once nothing is dirty
local lastLeaderboardRequest = {} -- [player] = os.clock() of their last GetDailyLeaderboard call
-- MENU TICKER (Engine/MenuTicker.lua): today's best run and a rounded run count, cached so every server reads the board and
-- the counter at most once a minute. `pending` runs are added to the shared DataStore counter on the same cadence.
local menuTicker = { at = -1e9, data = nil, pending = 0, flushedAt = -1e9 }
local FlairBoards = {} -- Name Aura on board rows (functions are attached further down, see "FLAIR NAME AURA ON BOARDS")

local function getBoardStore(kind, board, periodKey)
	local name = Leaderboards.storeName(kind, board, periodKey)
	if not boardStoreCache[name] then
		boardStoreCache[name] = DataStoreService:GetOrderedDataStore(name)
	end
	return boardStoreCache[name]
end

local function getDailyStore(dateKey, board)
	return getBoardStore("daily", board or Leaderboards.STANDARD, dateKey)
end

-- Writes every dirty board in pendingTable[player]. A board is only marked
-- clean if its pending entry wasn't replaced while SetAsync was yielding,
-- so a newer improvement queued mid-save still gets written next time.
local function flushBoardScores(player, pendingTable, dirtyTable, getStore, periodField, label)
	local dirty = dirtyTable[player]
	local pendingByBoard = pendingTable[player]
	if not dirty or not pendingByBoard then
		return
	end
	local boards = {}
	for board in pairs(dirty) do
		table.insert(boards, board)
	end
	for _, board in ipairs(boards) do
		local pending = pendingByBoard[board]
		if pending then
			local combinedScore = pending.depth * DAILY_SCORE_MULTIPLIER + pending.tips
			local store = getStore(pending[periodField], board)
			local ok, err = pcall(function()
				store:SetAsync(tostring(player.UserId), combinedScore)
			end)
			if ok then
				if dirtyTable[player] and pendingTable[player] and pendingTable[player][board] == pending then
					dirtyTable[player][board] = nil
				end
			else
				warn(string.format("%s %s leaderboard save failed for %s: %s", label, board, player.Name, tostring(err)))
				-- Leave it dirty -- the next autosave tick (or the final
				-- PlayerRemoving/BindToClose attempt) will retry with the
				-- freshest pending entry (see the section header above).
			end
		elseif dirtyTable[player] then
			dirtyTable[player][board] = nil
		end
	end
	if dirtyTable[player] and next(dirtyTable[player]) == nil then
		dirtyTable[player] = nil
	end
end

local function computeDailyDepth(state)
	return (state.night - 1) * state.config.roundsPerNight + (state.round - 1)
end

local function saveDailyScore(player)
	flushBoardScores(player, dailyPending, dailyDirty, getDailyStore, "dateKey", "Daily")
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

local weeklyPending = {} -- [player] = { [board] = { weekKey, depth, tips } }
local weeklyDirty = {} -- [player] = { [board] = true }; nil once nothing is dirty
local lastWeeklyLeaderboardRequest = {} -- [player] = os.clock() of their last GetWeeklyLeaderboard call

local function getWeeklyStore(weekKey, board)
	return getBoardStore("weekly", board or Leaderboards.STANDARD, weekKey)
end

local function saveWeeklyScore(player)
	flushBoardScores(player, weeklyPending, weeklyDirty, getWeeklyStore, "weekKey", "Weekly")
end

-- ===== 4c. Endless board (Phase 4) =====
-- All-time board per Standard / Revived: highest Night reached in Endless Mode, then the run's best single hand
-- (Leaderboards.combine). Entries come only from the server's own run state (Leaderboards.endlessEntry validates
-- it: a normal, won run past the Night cap), never from a client. Saved with UpdateAsync keeping the higher value,
-- because this board is not reset per day and an older, lower run must never overwrite a better one.
local endlessPending = {} -- [player] = { [board] = { periodKey, depth (Night), tips (best hand) } }
local endlessDirty = {} -- [player] = { [board] = true }
local lastEndlessRequest = {} -- [player] = os.clock() of their last GetEndlessLeaderboard call

local function getEndlessStore(_periodKey, board)
	return getBoardStore("endless", board or Leaderboards.STANDARD, Leaderboards.ENDLESS_PERIOD)
end

local function saveEndlessScore(player)
	local dirty, pendingByBoard = endlessDirty[player], endlessPending[player]
	if not dirty or not pendingByBoard then
		return
	end
	local boards = {}
	for board in pairs(dirty) do boards[#boards + 1] = board end
	for _, board in ipairs(boards) do
		local pending = pendingByBoard[board]
		if pending then
			local combined = Leaderboards.combine(pending.depth, pending.tips)
			local ok, err = pcall(function()
				getEndlessStore(nil, board):UpdateAsync(tostring(player.UserId), function(old)
					if type(old) == "number" and old >= combined then
						return nil -- keep the better stored run
					end
					return combined
				end)
			end)
			if ok then
				if endlessDirty[player] and endlessPending[player] and endlessPending[player][board] == pending then
					endlessDirty[player][board] = nil
				end
			else
				warn(string.format("Endless %s leaderboard save failed for %s: %s", board, player.Name, tostring(err)))
			end
		elseif endlessDirty[player] then
			endlessDirty[player][board] = nil
		end
	end
	if endlessDirty[player] and next(endlessDirty[player]) == nil then
		endlessDirty[player] = nil
	end
end

-- trackDailyProgress/trackWeeklyProgress (need `sessions`, declared just
-- below) are defined right next to syncProfileFromSession further down,
-- both called from pushState.

-- ===== 5. Session management =====

-- ROUND SELECT FEATURE: "roundSelect" is the new 4th phase -- shown at the
-- very start of a run, and every time right after leaving the shop
-- (instead of dropping straight into "playing"). RunState itself already
-- has a hand dealt and ready the instant a "roundSelect" phase begins
-- (RunState.startRound runs unconditionally) -- this phase is purely a
-- client-visibility gate, so no engine changes were needed to add it; see
-- Rem.SelectRound's handler below for the phase flip into "playing".
local sessions = {} -- [player] = { state = RunState, phase = "roundSelect" | "playing" | "shop" | "gameover", shopOffers = {patron, ...}, packOffers = {pack, ...}, voucherOffer = pass | nil, rerollCost = number }

-- Real-money Game Passes (see Shared/Engine/GamePasses.lua): deliberately
-- kept OUTSIDE the `sessions` table -- a Game Pass is owned by the PLAYER
-- forever (Roblox remembers it), not by any one run, so this must survive
-- `startNewSession` reassigning sessions[player] to a fresh table on every
-- "New Run.../restart -- unlike profile.ownedSetIds (Tips purchases), which
-- SHOULD reset with the run. The actual ownership-check/grant machinery
-- lives further down (right after pushState is defined, since it needs
-- to call that).
local ownedGamePasses = {} -- [player] = { [GamePasses catalog id] = true }

-- Rerolls just the offers, keeping whatever the current rerollCost climbed
-- to (the caller bumps it after using this). Opening a fresh shop visit
-- uses this too, via openShop below, which additionally resets the cost.
-- Offer generation itself lives in Shared/Engine/Shop.lua (pure, so the
-- headless simulator rolls offers through the same code).
local function rollShopOffers(session)
	local offers = Shop.rollOffers(session.state)
	if session.isTutorial then
		TutorialScript.shopFor(session.state, offers, session.rerollCost or Shop.REROLL_BASE_COST) -- scripted, affordable
	end
	session.shopOffers = offers.patrons
	session.packOffers = offers.packs
	session.voucherOffer = offers.voucher
end

local function openShop(session)
	rollShopOffers(session)
	session.rerollCost = Shop.REROLL_BASE_COST
	-- A new visit: one haggle again, and maybe the Wandering Stranger (1 in 6, normal runs from Night 3).
	require(Engine.Haggle).reset(session.state)
	session.state.strangerSeed = session.state.strangerSeed or (os.time() * 31 + math.floor(os.clock() * 1000)) -- fixed once per run, so repeat visits are stable
	session.strangerOffer = require(Engine.Strangers).rollVisit(session.state, require(Engine.Haggle).ctxFor(session))
end

local function serializeCard(card)
	return {
		rank = card.rank, suit = card.suit, garnish = card.garnish, special = card.special, stamp = card.stamp,
		-- PHASE C ("mind-blowing plan" Signature Mechanic): see
		-- TrueWildcard.lua. isTrueWildcard marks the one card in this run
		-- that is (or was) the True Wildcard; wildcardLocked is false right
		-- up until the first time it's actually played -- the client uses
		-- that combination to show "???" in the hand instead of its real
		-- (not-yet-relevant) dealt rank/suit. Omitted entirely for every
		-- other card, same as garnish/special/stamp above.
		isTrueWildcard = card.isTrueWildcard,
		wildcardLocked = card.wildcardLocked,
	}
end

-- PAID CONTINUE: whether the "continue" Developer Product can be granted
-- at all -- a real product id is set, or this is a Studio playtest (where
-- RequestContinue grants it free, see "Paid Continue" below).
local function continueProductAvailable()
	return DeveloperProducts.isConfigured(DeveloperProducts.getById("continue")) or RunService:IsStudio()
end

-- ONE MORE ROUND: today's free continue hasn't been spent yet.
local function hasFreeContinue(player)
	local profile = profiles[player]
	return profile ~= nil and PlayerProfile.hasFreeContinue(profile, SeededRng.dailyDateKey())
end

-- What the Game Over panel may offer: "free" (today's free continue),
-- "paid" (the Developer Product), or nil. The free one always comes first.
local function continueOffer(session, player)
	if session.phase ~= "gameover" or not RunState.canContinue(session.state) then
		return nil
	end
	if hasFreeContinue(player) then
		return "free"
	end
	if continueProductAvailable() then
		return "paid"
	end
	return nil
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
		roundStartHands = state.roundStartHands, -- the client's score preview needs it (Sleepy Cook: first hand of the round)
		challenge = state.challenge, -- the Challenge Run twist in force, or nil (Engine/Challenges.lua)
		discardsRemaining = state.discardsRemaining,
		roundScore = state.roundScore,
		targetScore = state.targetScore,
		ownedPatrons = owned,
		handsPlayedTotal = state.handsPlayedTotal, -- Night victory recap
		onboardingHint = session.onboardingHint,
		-- Scaling Patrons' inputs, so computeHandPreview matches playHand.
		runCounters = RunState.runCounters(state),
		patronSlotLimit = RunState.patronSlotLimit(state),
		-- GENRE PARITY: recipeSlotLimit/nightCap are static-per-run
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
		rerollCost = RunState.rerollCost(state, session.rerollCost or Shop.REROLL_BASE_COST),
		-- pendingPack is already the lightweight { packId, category, pickCount,
		-- items = {id,name,icon,description} } shape RunState.openPack builds
		-- -- safe to ship as-is, same as deckCounts/handLevels below.
		pendingPack = state.pendingPack,
		housePassIds = housePassIds,
		-- Real-money Game Pass ownership (see Shared/Engine/GamePasses.lua).
		ownedGamePassIds = (function()
			local ids = {}
			for passId in pairs(ownedGamePasses[player] or {}) do
				table.insert(ids, passId)
			end
			return ids
		end)(),
		-- Cosmetic Sets: owned = unlocked by any source; equipped = the set
		-- actually in effect (falls back to the default).
		cosmetics = (function()
			local profile = profiles[player]
			if not profile then
				return {
					equippedSetId = CosmeticSets.DefaultId,
					unlockedSetIds = { CosmeticSets.DefaultId },
					cardBackId = CardBacks.DefaultId,
					pickedCardBackId = nil,
					unlockedCardBackIds = { CardBacks.DefaultId },
				}
			end
			local passes = ownedGamePasses[player] or {}
			local unlocked = {}
			for _, set in ipairs(CosmeticSets.Definitions) do
				if CosmeticSets.isUnlocked(profile, set.id, passes) then
					table.insert(unlocked, set.id)
				end
			end
			local backs = {}
			for _, back in ipairs(CardBacks.Definitions) do
				if CosmeticSets.isCardBackUnlocked(profile, back.id, passes) then
					table.insert(backs, back.id)
				end
			end
			return {
				equippedSetId = CosmeticSets.effectiveId(profile, passes),
				unlockedSetIds = unlocked,
				-- cardBackId = the back in effect; pickedCardBackId = the player's
				-- own pick (nil = following the set).
				cardBackId = CosmeticSets.effectiveCardBackId(profile, passes),
				pickedCardBackId = profile.equippedCardBackId,
				unlockedCardBackIds = backs,
			}
		end)(),
		deckVariantId = state.deckVariantId,
		difficultyId = state.difficultyId,
		stake = state.stake,
		highestStakeUnlocked = Stakes.highestUnlocked(profiles[player]),
		stakeStamps = profiles[player] and profiles[player].stakeStamps or {},
		bossModifier = bossModifier,
		-- True on every Night's last round on every difficulty (Casual has
		-- no bossModifier but still pays the boss reward) -- see RunState.
		isBossRound = RunState.isBossRound(state),
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
		-- "Your Deck" viewer: every card with its status, sorted (never draw order).
		deckView = RunState.deckView(state),
		-- PERSISTENT SAVE (Phase 10): the permanent, cross-run part of this
		-- player's progress (Shared/Engine/PlayerProfile.lua) -- see that
		-- file's header for exactly what these mean. discoveredPatronIds
		-- powers Client/Collection.lua showing a Patron as found even in a
		-- brand-new run where you haven't re-bought it yet; profileStats is
		-- 3 small permanent counters shown alongside it.
		-- COLLECTION: { discovered = { [tabId] = {id...} }, claimedMilestoneIds,
		-- unlockedCardBackIds } -- plain copies for Client/Collection.lua.
		-- Titles aren't in `discovered`; the client uses unlockedAchievementIds.
		collection = (function()
			local profile = profiles[player]
			local discovered = {}
			local claimed = {}
			local cardBacks = {}
			if profile then
				for tabId, field in pairs(PlayerProfile.DISCOVERY_FIELDS) do
					local ids = {}
					for id in pairs(profile[field]) do
						table.insert(ids, id)
					end
					discovered[tabId] = ids
				end
				for id in pairs(profile.claimedMilestoneIds) do
					table.insert(claimed, id)
				end
				for id in pairs(profile.unlockedCardBackIds) do
					table.insert(cardBacks, id)
				end
			end
			return { discovered = discovered, claimedMilestoneIds = claimed, unlockedCardBackIds = cardBacks }
		end)(),
		-- One-shot: milestone ids claimed since the last push (nil otherwise).
		collectionMilestoneNotice = session.collectionMilestoneNotice,
		-- JOURNEY: Nights ever cleared (profile-wide), and the Night numbers
		-- newly cleared since the last push (one-shot, nil otherwise).
		clearedNightIds = (function()
			local ids = {}
			local profile = profiles[player]
			if profile then
				for night in pairs(profile.clearedNightIds) do
					table.insert(ids, night)
				end
				table.sort(ids)
			end
			return ids
		end)(),
		journeyNotice = session.journeyNotice,
		-- RUN SUMMARY: only at Game Over. `badgeSaved` = this run's badge is already the profile badge.
		runSummary = (function()
			if session.phase ~= "gameover" then
				return nil
			end
			local profile = profiles[player]
			local titleText
			local title = profile and profile.equippedTitleId and Achievements.getById(profile.equippedTitleId)
			if title then
				titleText = title.title
			end
			local summary = RunSummary.build(state, titleText)
		local _, badgeIcon = Badges.equippedText(profile)
		summary.badgeIcon = badgeIcon
			local saved = profile and profile.equippedBadge
			summary.stake = state.stake
			-- WIN CARD (Client/WinCard.lua): best Night so far counts as a new best (ties included), Night 3 and up
			summary.newBest = profile ~= nil and summary.night >= 3 and summary.night >= ((profile.stats and profile.stats.bestNightReached) or 0)
			summary.endlessBestByStake = profile and profile.endlessBestByStake or nil
			summary.totalScore = math.floor(state.totalScore or 0)
			summary.badgeSaved = saved ~= nil and saved.night == math.floor(summary.night)
				and saved.rarity == summary.rarity and saved.won == summary.won
				and saved.bestHandScore == (summary.bestHand and summary.bestHand.score or nil)
			return summary
		end)(),
		-- LOGIN STREAK + menu strip (display only; ClaimLoginReward re-checks everything).
		login = (function()
			local profile = profiles[player]
			if not profile then
				return nil
			end
			local view = LoginStreak.view(profile)
			view.secondsToNextDay = LoginStreak.secondsToNextDay(os.time())
			return view
		end)(),
		-- SEASON banner (display only; nil outside a season). Rewards are granted in syncProfileFromSession.
		season = (function()
			local profile = profiles[player]
			return profile and Seasons.view(profile, os.time()) or nil
		end)(),
		nextUnlock = (function()
			local profile = profiles[player]
			return profile and NextUnlock.compute(profile) or nil
		end)(),
		placesSeen = (function()
			local profile = profiles[player]
			return profile and NextUnlock.placesSeen(profile) or nil
		end)(),
		-- WORLD MAP: the road so far, the roads waiting to be picked (nil when none), and whether the route
		-- is fixed by the seed (Daily, Weekly, Seed). The client never decides any of this.
		worldRoute = state.worldRoute,
		worldChoices = session.phase == "roundSelect" and WorldMap.pendingChoices(state) or nil,
		worldFixed = state.worldPlan ~= nil,
		lastHand = state.lastHand and { name = state.lastHand.name, score = math.floor(state.lastHand.score) } or nil, -- Showdown banner
		-- THE COUNTER: the haggle bar, the Wandering Stranger's offer and the Dealer's Bargains taken this run.
		haggle = session.phase == "shop" and (function()
			require(Engine.Haggle).expire(state, os.clock())
			return require(Engine.Haggle).view(state, require(Engine.Haggle).ctxFor(session), session.phase)
		end)() or nil,
		stranger = session.phase == "shop" and require(Engine.Strangers).view(session.strangerOffer) or nil,
		shopNotice = session.shopNotice, -- the last one-line reason the Counter gave for a refused Reroll or Haggle
		bargains = state.bargains,
		-- Side stops open at this Night's stop (Round Select only): id, kind, name, icon and, for a shop, its offers.
		sideStops = (function()
			local list = {}
			for _, id in ipairs(SideStops.available(state, session.phase)) do
				local stop = WorldMap.Stops[id]
				local entry = { id = id, side = stop.side, name = stop.name, icon = stop.icon, game = stop.game }
				local offers = session.sideShops and session.sideShops[id]
				if offers then
					entry.offers = {}
					for _, p in ipairs(offers) do
						table.insert(entry.offers, { id = p.id, name = p.name, icon = p.icon, description = p.description,
							price = RunState.patronPrice(state, p) })
					end
				end
				if stop.side == "shrine" then
					entry.cost = SideStops.SHRINE_COST
				end
				table.insert(list, entry)
			end
			return list
		end)(),
		sideBonus = { tempPass = state.tempPass and state.tempPass.id or nil, bonusHandsNight = state.bonusHandsNight,
			extraContinues = state.extraContinues or 0 },
		mapTokens = state.mapTokens or 0,
		-- Hidden side stops: the ones revealed this run, and the ones that could be revealed right now.
		sideRevealed = (function()
			local list = {}
			for id in pairs(state.sideRevealed or {}) do
				list[#list + 1] = id
			end
			table.sort(list)
			return list
		end)(),
		sideHidden = SideStops.hiddenHere(state, session.phase),
		sideVisited = (function()
			local list = {}
			for id in pairs(state.sideVisited or {}) do
				list[#list + 1] = id
			end
			table.sort(list)
			return list
		end)(),
		-- The open minigame as the player may see it (never answers or hidden cards), plus how it ended.
		minigame = session.minigame and {
			stopId = session.minigame.stopId,
			view = Minigames.view(session.minigame.g, os.clock()),
			result = session.minigame.result,
		} or nil,
		compassCharges = profiles[player] and profiles[player].compassCharges or 0,
		keys = Keys.count(profiles[player]),
		badgeIds = Badges.list(profiles[player]),
		equippedBadgeId = profiles[player] and profiles[player].equippedBadgeId or nil,
		badgeNotice = session.badgeNotice,
		progressNotice = session.progressNotice, -- { seq, rankUps, quests, rewards }, shown once per seq by Client/UnlockToast
		rank = profiles[player] and TavernRank.view(profiles[player]) or nil,
		dailyQuests = profiles[player] and Quests.view(profiles[player], LoginStreak.dayNumber(os.time()), LoginStreak.secondsToNextDay(os.time())) or nil,
		nextGoal = profiles[player] and NextGoal.compute(profiles[player], LoginStreak.dayNumber(os.time()), {
			unlock = function(kind, id)
				local def = kind == "patron" and PatronsData.getById(id) or (Recipes.getHouseRecipeById(id) or Recipes.getSecretRecipeById(id))
				return def and def.name or nil
			end,
		}) or nil,
		saveDisabled = saveBlocked[player] == true, -- load failed or held by another server: progress will not save
		choice = session.choice, -- the open draft or event card (Engine/RunChoice.lua), nil when none
		-- CROWD RULES (Endless): the active rules as display data, and the one that joined this Night (nil when none)
		crowdRules = state.endlessRulesEnabled and (function()
			local out = {}
			for i, r in ipairs(EndlessRules.activeFor(state.night, state.config.nightCap)) do
				out[i] = { id = r.id, name = r.name, icon = r.icon, text = r.text }
			end
			return out
		end)() or nil,
		crowdRuleNew = state.endlessNewRule and { id = state.endlessNewRule.id, name = state.endlessNewRule.name, icon = state.endlessNewRule.icon, text = state.endlessNewRule.text, night = state.night } or nil,
		discoveries = profiles[player] and Discoveries.view(profiles[player]) or nil,
		challenges = profiles[player] and Challenges.view(profiles[player]) or nil,
		-- BOSS SCOUT (Engine/BossCounters.lua): the Night's boss from its first round on, and the Rule Ban tokens
		scout = (state.bossRoundsEnabled and not state.rush and state.nightBossModifier) and (function()
			local card = require(Engine.BossCounters).scout(state.nightBossModifier)
			card.banned = state.bannedBossNight == state.night
			return card
		end)() or nil,
		ruleBans = state.ruleBansEnabled and (state.ruleBans or 0) or nil,
		config = { roundsPerNight = state.config.roundsPerNight }, -- the Boss Scout banner needs to know which round is the boss round
		flairStore = profiles[player] and Store.view(profiles[player], ownedGamePasses[player], RunService:IsStudio(), "flair") or nil, -- Flair for sale
		seasonStore = profiles[player] and Store.view(profiles[player], ownedGamePasses[player], RunService:IsStudio(), "season") or nil, -- premium passes
		flair = profiles[player] and (function()
			local ok, view = pcall(function() return require(Engine.Flair).view(profiles[player]) end)
			return ok and view or nil
		end)() or nil, -- Flair slots, options and what is equipped (display only)
		legend = profiles[player] and (function()
			local ok, view = pcall(function() return require(Engine.Legend).view(profiles[player], liveLookup) end)
			return ok and view or nil
		end)() or nil, -- Legend prestige (level, rewards, aura)
		collectionRewards = profiles[player] and (function()
			local ok, view = pcall(function() return require(Engine.CollectionRewards).view(profiles[player], liveLookup) end)
			return ok and view or nil
		end)() or nil, -- Collection completion rings and milestones
		hintsSeen = profiles[player] and profiles[player].hintsSeen or nil, -- first time hints already shown (Engine/Hints.lua)
		lastInterest = state.lastInterest, -- the interest paid at the last round win (hint "first_interest")
		season = profiles[player] and require(Engine.SeasonTrack).view(profiles[player], LoginStreak.dayNumber(os.time()), liveLookup) or nil,
		news = profiles[player] and LiveEvents.view(profiles[player], LoginStreak.dayNumber(os.time()), liveLookup) or nil,
		dailyTheme = LiveEvents.dailyLabel(LoginStreak.dayNumber(os.time())), -- text beside the Daily date only
		store = profiles[player] and Store.view(profiles[player], ownedGamePasses[player], RunService:IsStudio()) or nil,
		storePrompt = storePrompts[player], -- seq: open the Store on the Starter Pack once
		equippedBadgeId2 = profiles[player] and profiles[player].equippedBadgeId2 or nil, -- VIP second badge slot
		bossRush = profiles[player] and BossRush.view(profiles[player]) or nil,
		runStats = profiles[player] and require(Engine.RunHistory).view(profiles[player]) or nil, -- Tavern Stats page
		regulars = profiles[player] and profiles[player].lifetime
			and require(Engine.Regulars).view(profiles[player].lifetime, math.floor(os.time() / 86400)) or nil, -- Menu Regulars
		isRush = state.rush ~= nil,
		runModifier = require(Engine.RunModifiers).view(state.runModifierId), -- the blessing and curse picked at run start
		rewardNotice = rewardNotices[player], -- { seq, text }, shown once per seq by Client/UnlockToast
		followPrompt = followPrompts[player], -- seq: the client offers Roblox experience notifications once
		unlockNotice = session.unlockNotice, -- { seq, items = { { kind, id, hint } } }, shown once per seq by Client/UnlockToast
		unlockHints = Unlocks.lockedHints(profiles[player]), -- Collection: hint per still-locked Patron and Recipe
		-- every road that still needs a Key, so the whole map can show padlocks (nil on fixed Daily/Weekly/Seed routes)
		lockedRoads = not state.worldPlan and (function()
			local list = {}
			for _, id in ipairs(Keys.lockedRoads()) do
				if not Keys.isRoadOpen(profiles[player], id) then
					list[#list + 1] = id
				end
			end
			return list
		end)() or nil,
		-- "open" / "unlocked" / "locked" for every road of the pending fork (all roads stay visible; locked ones show a padlock)
		roadStatus = session.phase == "roundSelect" and not state.worldPlan and Keys.statusMap(profiles[player], WorldMap.pendingChoices(state)) or nil,
		compassReveal = session.phase == "roundSelect" and BiomeRewards.revealedChoices(state) or nil,
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
		-- Player settings (copy). nil until the profile loads, so the client
		-- keeps its defaults instead of treating "loading" as saved values.
		settings = (function()
			local profile = profiles[player]
			if not profile then
				return nil
			end
			local copy = {}
			for key, value in pairs(profile.settings) do
				copy[key] = value
			end
			return copy
		end)(),
		-- TUTORIAL (Phase 16): `false` (not nil) here is what tells the
		-- client "genuinely show the auto-popup" -- a not-yet-loaded
		-- profile deliberately reports `true` instead (see the `or true`
		-- below), so a client that somehow renders before profiles[player]
		-- is ready doesn't mistake "still loading" for "brand new,
		-- auto-show the tutorial."
		--
		-- STUDIO TUTORIAL BYPASS (requested fix: testing the walkthrough
		-- in Studio was impossible once your own saved profile had already
		-- seen it once): same idea as refreshOwnedGamePasses' Studio
		-- bypass below -- while RunService:IsStudio() is true, a LOADED
		-- profile always reports false, so the walkthrough auto-starts on
		-- every Studio playtest. IsStudio() is always false in the
		-- published game, so a live player's real flag is untouched. The
		-- saved flag itself still flips true on dismiss (MarkTutorialSeen-
		-- Remote is unchanged) -- it's only ever ignored in Studio, and the
		-- client's own tutorialAutoShown guard keeps it to once per session.
		isTutorial = session.isTutorial == true,
		tutorialStage = session.tutorialStage, -- 1..4 while the scripted tutorial hands are being dealt
		hasSeenTutorial = (function()
			local profile = profiles[player]
			if not profile then
				return true
			end
			if RunService:IsStudio() then
				return false
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
		-- PAID CONTINUE: `revived` drives the Game Over panel's "Revived"
		-- badge; `continueOffer` ("free" | "paid" | nil) shows its One More
		-- Round button. Display only: RequestContinue re-checks everything.
		revived = state.revived == true,
		continueOffer = continueOffer(session, player),
	}
end

-- PERSISTENT SAVE (Phase 10): folds this player's CURRENT run into their
-- permanent profile -- every owned Patron this run into
-- discoveredPatronIds, every owned Cosmetic Set into ownedSetIds, the current
-- Night into the bestNightReached high-water mark, and (once, on the
-- false->true transition) a run win into stats.runsWon. Safe to call
-- unconditionally on every single pushState -- idempotent and cheap for
-- the small lists involved -- only actually marks the profile dirty
-- (needing a save) when something genuinely new happened, so a run of
-- unrelated state pushes (playing hands with nothing new discovered)
-- doesn't spam DataStore writes.
-- BADGES: a newly earned game Badge also awards the matching real Roblox Badge when BadgeIds has an id for it.
-- A missing id is skipped silently (Badges.awardPlan), everything runs in a spawned pcall and never blocks gameplay.
local BadgeService = game:GetService("BadgeService")
local function awardRobloxBadges(player, newIds)
	local plan = Badges.awardPlan(newIds, BadgeIds)
	if #plan == 0 then
		return
	end
	task.spawn(function()
		for _, award in ipairs(plan) do
			pcall(function()
				BadgeService:AwardBadge(player.UserId, award.robloxId)
			end)
		end
	end)
end

local function syncProfileFromSession(player)
	local session = sessions[player]
	local profile = profiles[player]
	if not session or not profile then
		return
	end
	if not TutorialStart.writesProfile(session) then
		return -- a tutorial run never touches stats, keys, discoveries or rewards
	end

	local changed = false
	local badgesBefore = {}
	for id, flag in pairs(profile.badgeIds or {}) do badgesBefore[id] = flag end
	-- COLLECTION: owned + offered in the shop + revealed in a pack + the
	-- boss being faced all count as discovered.
	local seen = CollectionBook.gatherSeen(session.state, {
		patrons = session.shopOffers,
		voucher = session.voucherOffer,
	})
	if PlayerProfile.recordDiscovered(profile, seen) then
		changed = true
	end
	-- PAID CONTINUE: a revived run stops counting toward high score
	-- records. Anything it reached before the continue was already
	-- recorded by earlier pushes.
	local countsForRecords = RunState.countsForRecords(session.state)
	if countsForRecords and PlayerProfile.recordNightReached(profile, session.state.night) then
		changed = true
	end
	if countsForRecords and session.state.endlessRulesEnabled and session.state.night > session.state.config.nightCap
		and PlayerProfile.recordEndlessBest(profile, session.state.stake, session.state.night) then
		changed = true -- personal best Endless Night per stake (Run Summary)
	end
	local justWon = false -- this sync saw a counted run flip to won (Tavern Rank win XP)
	if session.state.wonRun and not session.lastKnownWonRun then
		session.lastKnownWonRun = true
		if countsForRecords then
			PlayerProfile.recordRunWon(profile)
			justWon = true
			-- a WON run through a biome upgrades its badge and title (once per biome)
			BiomeRewards.recordRunWin(profile, session.state.worldRoute)
				-- STAKES: a standard run (not Daily, Weekly, Seed or revived) unlocks the next stake and stamps its roads
				if not (session.isDaily or session.isWeekly or session.isSeeded or session.state.challenge) then
					local regions = {}
					for _, stopId in ipairs(session.state.worldRoute or {}) do
						regions[#regions + 1] = WorldMap.regionOf(stopId)
					end
					Stakes.recordWin(profile, session.state.stake, regions)
					-- LEGEND PRESTIGE (Engine/Legend.lua): a standard stake 8 clear earns Legend points (a new road pays a bonus)
					if session.state.stake == Stakes.MAX and not session.state.quickRun then
						pcall(function()
							local Legend = require(Engine.Legend)
							local result = Legend.recordClear(profile, regions)
							if result.levelAfter > result.levelBefore then
								pushRewardNotice(player, { text = "Legend level " .. result.levelAfter .. "!" })
							end
						end)
					end
				end
			changed = true
		end
	end

	-- JOURNEY: first clears of each Night grant a cosmetic reward. Revived
	-- runs don't count, same as the other records.
	if countsForRecords then
		local worldChanged, worldCounted = PlayerProfile.recordWorldProgress(
			profile, session.state.worldRoute, JourneyMap.nightsClearedFor(session.state), session.worldCounted)
		session.worldCounted = worldCounted
		if worldChanged then
			changed = true
		end
		-- Biome rewards: branch ends, region bonuses (granted once each, see Engine/BiomeRewards.lua).
		local biomeFresh = BiomeRewards.recordProgress(profile, session.state.worldRoute, JourneyMap.nightsClearedFor(session.state), session.state)
		if #biomeFresh > 0 then
			changed = true
		end
		-- Seasonal set: clearing enough Nights in one run while a season is running grants its rewards once.
		if Seasons.recordProgress(profile, os.time(), JourneyMap.nightsClearedFor(session.state)) then
			changed = true
		end
		local fresh = JourneyMap.recordNightsCleared(profile, JourneyMap.nightsClearedFor(session.state))
		for _, night in ipairs(JourneyMap.recordEndlessCleared(profile, JourneyMap.totalNightsClearedFor(session.state))) do
			table.insert(fresh, night)
		end
		if #fresh > 0 then
			changed = true
			session.journeyNotice = fresh
		end
	end

	-- BADGES: rule badges (wins, Nights, minigames, Collection, streaks, seasons) are checked every sync; any badge
	-- earned since the start of this sync (rule or biome) also awards its real Roblox Badge, when one is configured.
	-- Collection milestones are granted just below, so evaluate after them (see the second pass).
	-- Checked every sync (not only when something new was found) so a
	-- profile loaded already past a milestone, or a title unlocked from
	-- stats, still gets its reward.
	local granted = CollectionBook.grantMilestones(profile)
	if #granted > 0 then
		changed = true
		local ids = {}
		for _, milestone in ipairs(granted) do
			table.insert(ids, milestone.id)
		end
		session.collectionMilestoneNotice = ids
	end

	-- BADGES: rule badges, then award every badge earned since the start of this sync.
	Badges.evaluate(profile)
	local earned = Badges.newlyEarned(badgesBefore, profile.badgeIds)
	-- UNLOCK DRIP: count this run's new hands, then open anything whose rule now passes (toast via state.unlockNotice).
	local handsNow = session.state.handsPlayedTotal or 0
	if handsNow > (session.handsSynced or 0) then
		profile.stats.handsPlayedTotal = (profile.stats.handsPlayedTotal or 0) + (handsNow - (session.handsSynced or 0))
		session.handsSynced = handsNow
		changed = true
	end
	local freshUnlocks, unlockSaved = Unlocks.evaluate(profile)
	if unlockSaved then
		changed = true
	end
	-- TAVERN RANK + DAILY QUESTS: counters turn into XP and quest progress (Engine/AccountProgress.lua).
	session.progressSnap = session.progressSnap or {}
	local progress = AccountProgress.sync(profile, session.progressSnap, session.state, LoginStreak.dayNumber(os.time()), justWon)
	if progress.changed then
		changed = true
	end
	if #progress.rankUps > 0 or #progress.quests > 0 then
		local lookup = {
			cardBackName = function(id) local d = CardBacks.getById(id) return d and d.name end,
			setName = function(id) local d = CosmeticSets.getById(id) return d and d.name end,
			titleName = function(id) local d = Achievements.getById(id) return d and d.title end,
		}
		local texts = {}
		for _, g in ipairs(progress.granted) do
			texts[#texts + 1] = "Rank " .. g.rank .. ": " .. TavernRank.rewardText(g.reward, lookup)
		end
		local questLines = {}
		for _, q in ipairs(progress.quests) do
			questLines[#questLines + 1] = { name = q.name, icon = q.icon, xp = q.xp }
		end
		progressSeqCounter = progressSeqCounter + 1
		session.progressNotice = { seq = progressSeqCounter, rankUps = progress.rankUps, quests = questLines, rewards = texts }
	end
	-- FIRST 5 MINUTES: funnel steps, run_end, the one-time first-win reward and follow prompt.
	local runState = session.state
	-- TUNING DATA (Engine/RunTelemetry.lua): a Boss Round that just ended is recorded in memory (a clear shows up as
	-- bossesCleared going up while its modifier is still current; a loss is recorded at Game Over below).
	if session.telemetry and (runState.bossesCleared or 0) > (session.telemetryBosses or 0) then
		session.telemetryBosses = runState.bossesCleared
		pcall(function()
			local mod = runState.bossModifier
			require(Engine.RunTelemetry).recordBoss(session.telemetry, mod and mod.id or "unknown", true,
				(runState.roundStartHands or 0) - (runState.handsRemaining or 0), runState.night)
			-- TAVERN REGULARS: the first clear of a Boss Round seats that boss in the Menu (Engine/Regulars.lua)
			if profile and mod and require(Engine.RunHistory).recordBoss(profile, mod.id, true) then
				changed = true
			end
		end)
	end
	if (runState.handsPlayedTotal or 0) >= 1 then logStep(player, "first_hand_played") end
	if (runState.roundsCleared or 0) >= 1 then logStep(player, "first_round_won") end
	if session.phase == "shop" then logStep(player, "first_shop_visit") end
	if session.phase == "gameover" then
		logStep(player, "first_run_ended")
		if not session.runEndLogged then
			session.runEndLogged = true
			local route = runState.worldRoute or {}
			Analytics.runEnd(player, runState.stake, WorldMap.regionOf(route[#route]), runState.night, runState.wonRun)
		end
		-- TUNING DATA: flush the run's aggregate once (a lost Boss Round is recorded first, then Patrons owned and bought).
		if session.telemetry and not session.telemetryFlushed then
			session.telemetryFlushed = true
			pcall(function()
				local RunTelemetry = require(Engine.RunTelemetry)
				if not runState.wonRun and RunState.isBossRound(runState) then
					local mod = runState.bossModifier
					RunTelemetry.recordBoss(session.telemetry, mod and mod.id or "unknown", false,
						(runState.roundStartHands or 0) - (runState.handsRemaining or 0), runState.night)
					if profile and mod then
						require(Engine.RunHistory).recordBoss(profile, mod.id, false) -- your record against them
						changed = true
					end
				end
				local ownedIds = {}
				for _, p in ipairs(runState.ownedPatrons or {}) do ownedIds[#ownedIds + 1] = p.id end
				Analytics.sendBatch(player, RunTelemetry.flush(session.telemetry, ownedIds, runState.wonRun == true), os.time())
			end)
		end
		-- RUN HISTORY (Engine/RunHistory.lua): once per run, only when it ends normally at Game Over (tutorial runs
		-- never get here: they return at the top). Tagged by mode so Daily, Weekly, Seed, Boss Rush and challenges show.
		if not session.historyRecorded then
			session.historyRecorded = true
			pcall(function()
				local RunHistory = require(Engine.RunHistory)
				local route = runState.worldRoute or {}
				local mode = RunHistory.modeOf({
					rush = runState.rush ~= nil, challenge = runState.challenge ~= nil,
					daily = session.isDaily, weekly = session.isWeekly, seeded = session.isSeeded,
					quick = runState.quickRun == true,
				})
				local entry = RunHistory.entryFromState(runState, mode, WorldMap.regionOf(route[#route]), os.time(), session.isSeeded and session.seedCode or nil)
				if entry and RunHistory.record(profile, entry, runState.tipsEarnedTotal) then
					changed = true
					if RunHistory.recordQuickBest(profile, entry) then
						pushRewardNotice(player, { text = "New Quick Run best!" })
					end
				end
			end)
		end
	end
	if justWon and profile.stats.runsWon == 1 then
		local notice = FirstRewards.firstWin(profile)
		if notice then
			pushRewardNotice(player, notice)
			changed = true
		end
		if FirstRewards.followDue(profile) then
			rewardSeqCounter = rewardSeqCounter + 1
			followPrompts[player] = rewardSeqCounter
			changed = true
		end
	end
	for _, q in ipairs(progress.quests) do Analytics.questDone(player, q.id) end
	for _, rank in ipairs(progress.rankUps) do Analytics.rankUp(player, rank) end
	-- LIVE EVENTS: report each running event to analytics once per player (the News banner is on the menu).
	for _, event in ipairs(LiveEvents.active(LoginStreak.dayNumber(os.time()))) do
		profile.liveEventsSeen = profile.liveEventsSeen or {}
		if not profile.liveEventsSeen[event.id] then
			profile.liveEventsSeen[event.id] = true
			changed = true
			Analytics.eventSeen(player, event.id)
		end
	end
	-- STORE: a one-time Starter Pack prompt once the second run has ended (never again, never when already bought).
	if session.phase == "gameover" and (profile.stats.runsStarted or 0) >= 2 and not profile.starterPrompted
		and not (profile.storePurchases and profile.storePurchases.starter_pack) then
		profile.starterPrompted = true
		changed = true
		rewardSeqCounter = rewardSeqCounter + 1
		storePrompts[player] = rewardSeqCounter
	end
	-- CHALLENGE RUNS / BOSS RUSH results live in the profile only (no boards).
	if justWon and session.state.challenge then
		local cleared = Challenges.recordClear(profile, session.state.challenge.id, os.time() - (session.startedAt or os.time()))
		if cleared then
			changed = true
			local def = Challenges.getById(session.state.challenge.id)
			local titleDef = cleared.title and Achievements.getById(cleared.title)
			local text = "Challenge cleared: " .. (def and def.name or "?")
			if titleDef then text = text .. ". Title: " .. titleDef.title end
			if cleared.bonusXp > 0 then text = text .. ". Speed bonus +" .. cleared.bonusXp .. " XP" end
			pushRewardNotice(player, { text = text })
		end
	end
	if session.state.rush then
		if BossRush.record(profile, session.state.bossesCleared) then
			changed = true
		end
		if session.phase == "gameover" and not session.rushEndLogged then
			session.rushEndLogged = true
			pushRewardNotice(player, { text = string.format("Boss Rush over: %d bosses beaten. Best: %d", session.state.bossesCleared, profile.bossRushBest or 0) })
		end
	end
	if #freshUnlocks > 0 then
		-- one counter for the whole server, so a new run's first notice still counts as new on the client
		unlockSeqCounter = unlockSeqCounter + 1
		session.unlockNotice = { seq = unlockSeqCounter, items = freshUnlocks }
	end

	if #earned > 0 then
		changed = true
		session.badgeNotice = earned
		awardRobloxBadges(player, earned)
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

	local board = Leaderboards.boardFor(session.state)
	local depth = computeDailyDepth(session.state)
	dailyPending[player] = dailyPending[player] or {}
	local pending = dailyPending[player][board]
	if pending and pending.dateKey == session.dailyDateKey and pending.depth >= depth then
		return -- nothing new to record
	end

	dailyPending[player][board] = {
		dateKey = session.dailyDateKey,
		depth = depth,
		tips = math.max(0, math.min(math.floor(session.state.tips), DAILY_TIPS_CAP)),
	}
	dailyDirty[player] = dailyDirty[player] or {}
	dailyDirty[player][board] = true
end

-- WEEKLY CHALLENGE (Phase 16): same idea as trackDailyProgress just
-- above, gated on session.isWeekly/session.weeklyDateKey instead.
-- ENDLESS BOARD: queue this run's entry when it beats what this player already queued.
local function trackEndlessProgress(player)
	local session = sessions[player]
	if not session then
		return
	end
	local night, score = Leaderboards.endlessEntry(session.state, {
		isDaily = session.isDaily, isWeekly = session.isWeekly, isSeeded = session.isSeeded, isTutorial = session.isTutorial,
	})
	if not night then
		return
	end
	local board = Leaderboards.boardFor(session.state)
	endlessPending[player] = endlessPending[player] or {}
	if not Leaderboards.improves(endlessPending[player][board], night, score) then
		return
	end
	endlessPending[player][board] = { periodKey = Leaderboards.ENDLESS_PERIOD, depth = night, tips = score }
	endlessDirty[player] = endlessDirty[player] or {}
	endlessDirty[player][board] = true
end

local function trackWeeklyProgress(player)
	local session = sessions[player]
	if not session or not session.isWeekly then
		return
	end

	local board = Leaderboards.boardFor(session.state)
	local depth = computeDailyDepth(session.state) -- same depth formula, not Daily-specific despite the name
	weeklyPending[player] = weeklyPending[player] or {}
	local pending = weeklyPending[player][board]
	if pending and pending.weekKey == session.weeklyDateKey and pending.depth >= depth then
		return -- nothing new to record
	end

	weeklyPending[player][board] = {
		weekKey = session.weeklyDateKey,
		depth = depth,
		tips = math.max(0, math.min(math.floor(session.state.tips), DAILY_TIPS_CAP)),
	}
	weeklyDirty[player] = weeklyDirty[player] or {}
	weeklyDirty[player][board] = true
end

-- ===== SPECTATE (Engine/Spectate.lua): watch a friend's run live, same server only =====
-- The server relays a compact, whitelisted event stream from the watched player's run to their spectators through the
-- `SpectateStream` remote (at most 4 snapshots a second per watched player). Spectators can only send a reaction
-- (preset, 3 s cooldown) and watch/stop/block requests; they have no way to send game input, and the watched player's
-- deck order, draw pile, rng seed, shop and profile are never part of any event (Spectate.snapshot is a whitelist).
local Spec = { M = require(Engine.Spectate) } -- one table: the main chunk is near Lua's 200 local limit
Spec.state = Spec.M.new()
Rem.SpectateStream = Rem._new("SpectateStream") -- (server to spectator and watched player) whitelisted events only

function Spec.name(player)
	return player.DisplayName ~= "" and player.DisplayName or player.Name
end

function Spec.send(viewers, event)
	event = Spec.M.outgoing(event)
	if not event or not Rem.SpectateStream then return end
	for _, viewerId in ipairs(viewers) do
		local viewer = Players:GetPlayerByUserId(viewerId)
		if viewer then
			pcall(function() Rem.SpectateStream:FireClient(viewer, event) end)
		end
	end
end

-- The watcher count for the watched player's own screen ("3 watching" with a tiny name row).
function Spec.notifyCount(target)
	local viewers = Spec.M.watchersOf(Spec.state, target.UserId)
	local names, rows = {}, {}
	for _, id in ipairs(viewers) do
		local v = Players:GetPlayerByUserId(id)
		if v then
			names[#names + 1] = Spec.name(v)
			rows[#rows + 1] = { id = id, name = Spec.name(v) } -- the watched player may block any of them
		end
	end
	if Rem.SpectateStream then
		pcall(function() Rem.SpectateStream:FireClient(target, { kind = "watchers", count = #viewers, names = names, viewers = rows }) end)
	end
end

function Spec.snapshotFor(player)
	local session, profile = sessions[player], profiles[player]
	if not session or not profile then return nil end
	local state = session.state
	local hand = {}
	for i, c in ipairs(state.hand or {}) do hand[i] = c end
	local patrons = {}
	for i, p in ipairs(state.ownedPatrons or {}) do patrons[i] = p.id end
	local mod = state.bossModifier
	local route = state.worldRoute or {}
	local region = WorldMap.regionOf(route[#route])
	local flairSet = require(Engine.Flair).equippedSet(profile)
	local auraOption = require(Engine.Flair).getById(flairSet.nameAura)
	local stakeDef = Stakes.get(state.stake or 1)
	return Spec.M.snapshot({
		name = Spec.name(player), crest = auraOption and auraOption.crest or nil,
		badge = profile.equippedBadge and profile.equippedBadge.rarity or nil,
		stake = state.stake, stakeName = stakeDef and stakeDef.name or nil,
		road = region, roadName = region and WorldMap.Regions[region] and WorldMap.Regions[region].name or nil,
		phase = session.phase, night = state.night, round = state.round, tips = state.tips,
		targetScore = state.targetScore, roundScore = state.roundScore,
		handsRemaining = state.handsRemaining, discardsRemaining = state.discardsRemaining,
		hand = hand, patrons = patrons, flair = flairSet,
		boss = mod and { id = mod.id, name = mod.name, text = mod.description } or nil,
	})
end

-- Called after a state push of `player`: spectators get a fresh snapshot (rate limited per watched player).
function Spec.pushed(player)
	if Spec.M.count(Spec.state, player.UserId) == 0 then return end
	if not Spec.M.streamAllowed(Spec.state, player.UserId, os.clock()) then return end
	local snap = Spec.snapshotFor(player)
	if snap then Spec.send(Spec.M.watchersOf(Spec.state, player.UserId), snap) end
end

function Spec.release(target, released, reason)
	Spec.send(released, { kind = "ended", reason = reason })
	Spec.notifyCount(target)
end

local function pushState(player)
	local session = sessions[player]
	if not session then
		return
	end
	syncProfileFromSession(player)
	trackDailyProgress(player)
	trackWeeklyProgress(player)
	trackEndlessProgress(player)
	Rem.StateUpdated:FireClient(player, serializeState(session, player))
	pcall(Spec.pushed, player) -- spectators see the same table a moment later
	-- a run that just ended frees its watchers (they can watch the next run)
	if session.phase == "gameover" and Spec.M.count(Spec.state, player.UserId) > 0 then
		pcall(function()
			local released = Spec.M.runEnded(Spec.state, player.UserId)
			Analytics.single(player, "spectator_count_peak", Spec.M.takePeak(Spec.state, player.UserId), {}) -- tuning data
			Spec.release(player, released, "The run ended.")
		end)
	end
	session.onboardingHint = nil -- one-shot: only the push right after it's set carries it
	session.collectionMilestoneNotice = nil -- one-shot, same as onboardingHint
	session.journeyNotice = nil -- one-shot
end

-- ===== Real-money Game Passes (see Shared/Engine/GamePasses.lua) =====
-- Placed here (not up by `ownedGamePasses`'s own declaration) because it
-- needs to call pushState, which -- as a `local function` -- only exists
-- for code appearing textually below its own definition.

-- Checks every catalog entry's real ownership via MarketplaceService and
-- caches the result. gamePassId == 0 means "not created on the Creator
-- Dashboard yet" (see GamePasses.lua's header) -- skipped entirely so
-- Studio testing before that setup doesn't spam failed lookups. Each
-- check is its own task.spawn so one slow/failed lookup can't hold up
-- the others.
--
-- STUDIO GAME PASS BYPASS (requested fix: testing Game Passes in
-- Studio and not seeing any of it -- every single Game Pass, including
-- fast_forward, is still gamePassId = 0, i.e. nothing's been created
-- on the Creator Dashboard yet, so this function used to just skip them
-- all forever -- "Coming Soon" in Studio is correct today, but it also
-- means NOTHING behind a Game Pass (Fast Forward, the Golden Gala set) can ever be play-tested before spending real money/creating
-- real Passes): a placeholder pass (gamePassId <= 0) is now treated as
-- OWNED, but only while RunService:IsStudio() is true. IsStudio() is
-- always false in the actual published game a real player connects to
-- -- this can never give a live player anything for free, it only
-- unblocks local testing. The moment a real gamePassId is pasted into
-- GamePasses.lua, that pass falls out of this branch entirely and goes
-- through the real MarketplaceService check below like normal.
-- VIP daily gift: +3 banked Tips once per UTC day, whenever the VIP pass is known to be owned (Engine/Store.lua).
local function grantVipDaily(player)
	local profile = profiles[player]
	if profile and Store.claimVipDaily(profile, LoginStreak.dayNumber(os.time())) > 0 then
		profileDirty[player] = true
	end
end

local function refreshOwnedGamePasses(player)
	ownedGamePasses[player] = ownedGamePasses[player] or {}
	for _, pass in ipairs(GamePasses.Definitions) do
		-- BUGFIX (Ahmed's report, repeated: "the multipliers are moving by
		-- so fast now"): fast_forward is excluded from the Studio bypass
		-- below. Every OTHER placeholder pass is something you need to
		-- actually SEE to verify (a Cosmetic Set) --
		-- fast_forward instead changes a timing constant (ScorePopup.lua's
		-- FAST_FORWARD_DIVISOR, 1.8x) that silently applies to literally
		-- every single Studio playtest the instant this pass exists in the
		-- catalog, even with its real gamePassId still unset. That made the
		-- 1.0x default pace (ENTRY_STAGGER, already slowed down once this
		-- same week) something nobody testing in Studio could ever actually
		-- see. Leaving fast_forward out of this bypass means Studio shows
		-- the TRUE default speed a real player gets until they buy the
		-- Pass, same as the published game -- exactly what testing should
		-- reflect. (Once a real gamePassId is pasted in, this branch stops
		-- applying to it anyway and it goes through the normal
		-- MarketplaceService check below like every other pass already does.)
		if (not pass.gamePassId or pass.gamePassId <= 0) and pass.id ~= "fast_forward" and RunService:IsStudio() then
			local alreadyKnown = ownedGamePasses[player][pass.id] == true
			ownedGamePasses[player][pass.id] = true
			if pass.id == "vip" then grantVipDaily(player) end
			if not alreadyKnown then
				pushState(player)
			end
		elseif pass.gamePassId and pass.gamePassId > 0 then
			task.spawn(function()
				local ok, owns = pcall(function()
					return MarketplaceService:UserOwnsGamePassAsync(player.UserId, pass.gamePassId)
				end)
				if not player.Parent then
					return -- left the game while this lookup was in flight
				end
				if ok then
					if owns then
						-- Push state when a pass is newly recorded as owned so the
						-- client's ownedGamePassIds (and set unlocks) update without
						-- waiting for an unrelated push. Skipped on redundant
						-- re-checks of an already-known pass.
						local alreadyKnown = ownedGamePasses[player][pass.id] == true
						ownedGamePasses[player][pass.id] = true
						if pass.id == "vip" then grantVipDaily(player) end
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
		Analytics.single(player, "store_bought", 1, { item = "pass_" .. tostring(gamePassId) }) -- tuning data
		refreshOwnedGamePasses(player)
	end
end)

-- ===== Paid Continue (Developer Product, see DeveloperProducts.lua) =====
-- One per run: RunState.canContinue refuses once state.revived is set.
-- Using it puts the session back at the start of the round that was lost
-- (RunState.useContinue), and from then on the run routes to the Revived
-- boards and stops counting toward high score records.

-- Returns true if the continue was applied to this player's current run.
local function applyContinue(player)
	local session = sessions[player]
	if not session or session.phase ~= "gameover" or not RunState.canContinue(session.state) then
		return false
	end
	RunState.useContinue(session.state)
	session.phase = "playing"
	pushState(player)
	return true
end

-- PurchaseIds already granted on this server. Roblox can call
-- ProcessReceipt more than once for the same purchase; without this, a
-- repeat call after the grant would see a revived run, refuse, and leave
-- the receipt unacknowledged forever.
local grantedReceipts = {}

-- The only ProcessReceipt in the game -- add any future Developer Products
-- here too, since Roblox allows a single callback.
--
-- If the run can't take the continue by the time the receipt arrives (the
-- player hit Play Again while the prompt was open, or left), this returns
-- NotProcessedYet: Roblox keeps the purchase and retries later (the next
-- time they join or buy something), so it lands on their next lost run
-- instead of vanishing.
MarketplaceService.ProcessReceipt = function(receiptInfo)
	if grantedReceipts[receiptInfo.PurchaseId] then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	-- STORE products (Starter Pack, Card Set Bundle): idempotent by purchase id, kept in the profile, saved before acknowledging.
	if Store.getByProductId(receiptInfo.ProductId) then
		local buyer = Players:GetPlayerByUserId(receiptInfo.PlayerId)
		local buyerProfile = buyer and profiles[buyer]
		if not buyerProfile then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		local okGrant, status = pcall(Store.processReceipt, buyerProfile, receiptInfo.ProductId, receiptInfo.PurchaseId)
		if okGrant and status == "granted" then
			local boughtItem = Store.getByProductId(receiptInfo.ProductId)
			Analytics.single(buyer, "store_bought", 1, { item = boughtItem and boughtItem.id or "unknown" }) -- tuning data
			profileDirty[buyer] = true
			pcall(saveProfile, buyer)
			if profileDirty[buyer] then
				return Enum.ProductPurchaseDecision.NotProcessedYet -- not saved yet: Roblox retries, the grant is idempotent
			end
			grantedReceipts[receiptInfo.PurchaseId] = true
			pushState(buyer)
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local product = DeveloperProducts.getByProductId(receiptInfo.ProductId)
	if not product then
		warn("ProcessReceipt: unknown Developer Product " .. tostring(receiptInfo.ProductId))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if product.id == "continue" and applyContinue(player) then
		grantedReceipts[receiptInfo.PurchaseId] = true
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	return Enum.ProductPurchaseDecision.NotProcessedYet
end

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
-- extra (optional) = { challengeId = string, rush = bool }: a Challenge Run twist or a Boss Rush. Both are for normal runs
-- only, so they are ignored for Daily, Weekly, Seed and the tutorial.
local function startNewSession(player, deckVariantId, difficultyId, seededRng, seedMode, seedLabel, isTutorial, stakeId, extra)
	local profile = profiles[player]
	-- STAKES: only an unlocked stake is honored; seeded and tutorial runs are always stake 1 (fair boards).
	local stake = Stakes.resolveStart(profile, stakeId, seededRng ~= nil or isTutorial == true)
	extra = (seededRng == nil and isTutorial ~= true and extra) or {}
	local rush = extra.rush == true and BossRush.isUnlocked(profile)
	local quick = extra.quick == true and not rush -- Quick Run (Engine/RunModes.lua): 4 Nights, stake 1, no challenge
	local challengeId = (not rush and not quick and Challenges.getById(extra.challengeId)) and extra.challengeId or nil
	if rush or quick then
		stake = 1 -- a Boss Rush or Quick Run ignores the stake and the challenge
	end

	local isDaily = seedMode == "daily"
	local isWeekly = seedMode == "weekly"
	local isSeeded = seedMode == "seed"
	local forceStandard = seededRng ~= nil -- every seeded mode (daily/weekly/seed) forces standard/standard, for the same "everyone/both of you actually start from the identical place" reason Daily always has

	sessions[player] = {
		state = RunState.new({
			deckVariantId = forceStandard and "standard" or deckVariantId,
			difficultyId = forceStandard and "standard" or difficultyId,
			stakeId = stake,
			endlessRules = seededRng == nil and isTutorial ~= true and not rush and challengeId == nil, -- Crowd Rules: normal runs only
			rush = rush,
			mode = quick and "quick" or nil,
			-- BOSS COUNTERPLAY: Rule Ban tokens for normal runs only (never Daily, Weekly, Seed, Boss Rush, challenge, Quick or the tutorial)
			ruleBans = seededRng == nil and isTutorial ~= true and not rush and not quick and challengeId == nil,
			challengeId = challengeId,
			-- UNLOCK DRIP: normal runs only; Daily, Weekly, Seed and the tutorial see every Patron and Recipe (fair boards)
			unlockedContent = (profile and seededRng == nil and isTutorial ~= true) and Unlocks.setFor(profile) or nil,
				nightOneBonusDiscards = Onboarding.bonusDiscards(profile and profile.stats.runsStarted, seededRng ~= nil),
			-- Ranked and shared boards walk a fixed road derived from the date key / seed code.
			worldPlan = seededRng ~= nil and WorldMap.routeFromSeed(tostring(seedMode) .. ":" .. tostring(seedLabel)) or nil,
		}, seededRng),
		-- ROUND SELECT FEATURE: every run now opens on the Round Select
		-- screen for Round 1 (matching the reference game showing Blind
		-- Select even before the very first blind), not straight into
		-- "playing".
		phase = "roundSelect",
		telemetry = require(Engine.RunTelemetry).new(), -- per-run tuning aggregate, flushed once at Game Over
		shopOffers = {},
		packOffers = {},
		voucherOffer = nil,
		rerollCost = Shop.REROLL_BASE_COST,
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
		-- First-run tutorial: a brand-new player's first normal run is dealt scripted hands (stage 1 to 4) so the
		-- guided steps can name an exact combo. nil for returning players and every seeded mode.
		-- Only the menu's Tutorial tile (StartTutorial remote) passes isTutorial; no other path starts it.
		tutorialStage = TutorialStart.initialStage(isTutorial, seededRng ~= nil),
		isTutorial = isTutorial == true and seededRng == nil,
	}

	if profile and TutorialStart.writesProfile(sessions[player]) then
		PlayerProfile.recordRunStarted(profile)
		menuTicker.pending = menuTicker.pending + 1 -- counted into today's run total (flushed at most once a minute)
		Analytics.runStart(player, stake, seedMode or "normal")
		if profile.stats.runsStarted >= 2 then
			logStep(player, "second_run_started")
		end
		-- TAVERN RANK / QUESTS / LOGIN: Tips banked for the next run are paid out here (normal runs only; seeded boards stay fair).
		if seededRng == nil then
			if rush then
				sessions[player].choice = RunChoice.rushDraft(sessions[player].state, 1, {}) -- Boss Rush: take 3 Patrons along
			else
				sessions[player].choice = RunChoice.startDraft(sessions[player].state, true) -- start-of-run draft
			end
			sessions[player].startedAt = os.time() -- the Speed Run challenge times the run from here
			local merchant = Discoveries.takeMerchantDiscount(profile) -- a map merchant: Tips off the first shop visit
			if merchant > 0 then
				sessions[player].state.nextShopDiscount = (sessions[player].state.nextShopDiscount or 0) + merchant
			end
			local bank = TavernRank.takeStartTips(profile)
			if bank > 0 then
				sessions[player].state.tips = sessions[player].state.tips + bank
			end
		end
		profileDirty[player] = true
	end

	pushState(player)
end

-- PERSISTENT SAVE (Phase 10): profile load has to happen (and finish --
-- GetAsync yields) BEFORE startNewSession, since it needs
-- profiles[player] (stats) for the fresh RunState. Consolidated
-- into one PlayerAdded handler instead of the 2 independent ones this used
-- to be, specifically to guarantee that ordering.
-- INVITES (Engine/Invites.lua): runs once per join inside a pcall, never blocks gameplay.
--  1. drain this player's own inbox (invitees credited while they were offline);
--  2. if this player arrived through an invite, grant them the starter card back (once, new players only) and credit
--     the inviter: directly when they are in this server, otherwise through a small DataStore inbox.
local function processInvites(player)
	local Invites = require(Engine.Invites)
	local profile = profiles[player]
	if not profile or saveBlocked[player] then
		return
	end
	local store = DataStoreService:GetDataStore("WildcardTavernInvites_v1")
	local inboxKey = "u" .. tostring(player.UserId)
	local okRead, inbox = pcall(function() return store:GetAsync(inboxKey) end)
	if okRead and type(inbox) == "table" and #inbox > 0 then
		local credited, titles = Invites.drainInbox(profile, player.UserId, inbox)
		if credited > 0 then
			profileDirty[player] = true
			pushRewardNotice(player, { text = string.format("%d friend%s joined through your invite. +%d Tips next run.", credited, credited == 1 and "" or "s", credited * Invites.INVITER_TIPS) })
		end
		pcall(function() store:RemoveAsync(inboxKey) end) -- credited ones are in the ledger, so a failed remove is harmless
	end
	local okJoin, joinData = pcall(function() return player:GetJoinData() end)
	local inviterId = okJoin and Invites.inviterFromJoinData(joinData) or nil
	if not inviterId or not Invites.acceptInvite(profile, player.UserId, inviterId) then
		return
	end
	profileDirty[player] = true
	pushRewardNotice(player, { text = "A friend invited you. Here is a starter card back!" })
	local inviter = Players:GetPlayerByUserId(inviterId)
	local inviterProfile = inviter and profiles[inviter]
	if inviterProfile then
		if Invites.creditInviter(inviterProfile, inviterId, player.UserId) then
			profileDirty[inviter] = true
			pushRewardNotice(inviter, { text = player.DisplayName .. " joined through your invite. +" .. Invites.INVITER_TIPS .. " Tips next run." })
		end
	else
		pcall(function()
			store:UpdateAsync("u" .. tostring(inviterId), function(old)
				return Invites.inboxAdd(old, player.UserId)
			end)
		end)
	end
end

local function onPlayerAdded(player)
	-- Each step is pcall'd and named so one failure can't leave the player
	-- without a session (every remote handler ignores players with none).
	local okLoad, profileOrErr = pcall(loadProfile, player)
	if okLoad then
		profiles[player] = profileOrErr
	else
		warn("[Startup] loadProfile failed for " .. player.Name .. ": " .. tostring(profileOrErr))
		profiles[player] = PlayerProfile.new()
	end
	-- LOGIN STREAK: one check-in per UTC day (a clock error just skips it).
	local okStreak, streakErr = pcall(function()
		if LoginStreak.checkIn(profiles[player], LoginStreak.dayNumber(os.time())) then
			profileDirty[player] = true
		end
	end)
	if not okStreak then
		warn("[Startup] login streak failed for " .. player.Name .. ": " .. tostring(streakErr))
	end
	if saveBlocked[player] then
		pushRewardNotice(player, { text = "Your progress can't be saved right now. You can still play." })
	end
	task.spawn(function()
		local okInv, errInv = pcall(processInvites, player)
		if not okInv then
			warn("[Startup] invites failed for " .. player.Name .. ": " .. tostring(errInv))
		end
		if FlairBoards.publish then
			pcall(FlairBoards.publish, player) -- put this player's Name Aura where the boards can read it
		end
	end)
	logStep(player, "menu_shown")
	local okSession, errSession = pcall(startNewSession, player)
	if not okSession then
		warn("[Startup] startNewSession failed for " .. player.Name .. ": " .. tostring(errSession))
	end
	local okPasses, errPasses = pcall(refreshOwnedGamePasses, player)
	if not okPasses then
		warn("[Startup] refreshOwnedGamePasses failed for " .. player.Name .. ": " .. tostring(errPasses))
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(function(player)
	-- Final save attempt before this player's data goes away -- on top of
	-- the AUTOSAVE_INTERVAL safety net, this is the normal/expected save
	-- path for a player who just leaves normally.
	pcall(function() -- QUIT POINT (tuning data): left in the middle of a real run
		local s = sessions[player]
		if s and s.phase ~= "gameover" and not s.isTutorial and (s.state.handsPlayedTotal or 0) > 0 then
			Analytics.single(player, "run_quit", s.state.night or 0, { phase = s.phase, stake = s.state.stake or 1 })
		end
		Analytics.forgetPlayer(player)
		-- SPECTATE: a leaving watcher frees the table, a leaving player releases everyone watching them
		local watchedBefore = Spec.M.watching(Spec.state, player.UserId)
		local released = Spec.M.leave(Spec.state, player.UserId)
		Spec.send(released, { kind = "ended", reason = "That player left." })
		local watchedPlayer = watchedBefore and Players:GetPlayerByUserId(watchedBefore)
		if watchedPlayer then Spec.notifyCount(watchedPlayer) end
	end)
	saveProfile(player, true) -- final save also releases the session lease
	saveDailyScore(player) -- DAILY CHALLENGE (Phase 11)
	saveWeeklyScore(player) -- WEEKLY CHALLENGE (Phase 16)
	saveEndlessScore(player)
	RateLimit.forget(player.UserId)
	saveBlocked[player] = nil
	sessions[player] = nil
	ownedGamePasses[player] = nil
	profiles[player] = nil
	rewardNotices[player] = nil
	followPrompts[player] = nil
	storePrompts[player] = nil
	funnelSessions[player] = nil
	profileDirty[player] = nil
	dailyPending[player] = nil
	dailyDirty[player] = nil
	lastLeaderboardRequest[player] = nil
	weeklyPending[player] = nil
	weeklyDirty[player] = nil
	lastWeeklyLeaderboardRequest[player] = nil
end)

-- In Studio, PlayerAdded may have already fired for existing test players.
-- Deferred (task.defer) so the profile load, which yields, can never hold up
-- the rest of this script: every remote handler below connects first.
task.defer(function()
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(onPlayerAdded, player)
	end
end)

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
			if weeklyDirty[player] or endlessDirty[player] then
				saveWeeklyScore(player)
				saveEndlessScore(player)
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
		pcall(function() -- QUIT POINT (tuning data): the server is closing in the middle of a real run
			local s = sessions[player]
			if s and s.phase ~= "gameover" and not s.isTutorial and (s.state.handsPlayedTotal or 0) > 0 then
				Analytics.single(player, "run_quit", s.state.night or 0, { phase = s.phase, stake = s.state.stake or 1 })
			end
		end)
		if profiles[player] then
			pending = pending + 1
			task.spawn(function()
				saveProfile(player, true)
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
		if weeklyDirty[player] or endlessDirty[player] then
			pending = pending + 1
			task.spawn(function()
				saveWeeklyScore(player)
				saveEndlessScore(player)
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

Rem.PlayHand.OnServerEvent:Connect(function(player, cardIndices)
	if not RateLimit.allow(player.UserId, "Rem.PlayHand", os.clock()) then return end
	local session = sessions[player]
	if not session or not RunState.phaseAllowsCardActions(session.phase) then
		return
	end
	if not isValidIndexList(cardIndices, #session.state.hand) then
		return
	end

	local spectated = Spec.M.count(Spec.state, player.UserId) > 0
	local playedCards = {}
	if spectated then
		for _, index in ipairs(cardIndices) do playedCards[#playedCards + 1] = session.state.hand[index] end
	end
	local ok, result = pcall(RunState.playHand, session.state, cardIndices)
	if not ok then
		warn("PlayHand error for " .. player.Name .. ": " .. tostring(result))
		return
	end
	if spectated then -- spectators see the hand, its type and score (never anything hidden)
		pcall(function()
			local viewers = Spec.M.watchersOf(Spec.state, player.UserId)
			Spec.send(viewers, Spec.M.handPlayed({
				cards = playedCards, handName = result.handName, score = result.score,
				legendary = result.isLegendary == true,
			}))
			if result.roundWon or result.runOver then
				Spec.send(viewers, Spec.M.roundResult({
					won = result.roundWon == true, night = session.state.night, round = session.state.round,
					banner = result.roundWon and "Round cleared" or "Run over",
				}))
			end
		end)
	end

	if result.roundWon and session.state.rush then
		-- BOSS RUSH: no shop, the next boss comes straight away (Engine/BossRush.lua)
		pcall(RunState.advanceToNextRound, session.state)
		session.phase = "roundSelect"
		session.state.pendingPack = nil
		pushRewardNotice(player, { text = string.format("Boss %d beaten! The next one is waiting.", session.state.bossesCleared) })
	elseif result.roundWon then
		session.phase = "shop"
		openShop(session)
		session.tutorialStage = nil -- the round ended: the scripted hands are done
	elseif result.runOver then
		session.phase = "gameover"
		session.tutorialStage = nil
	elseif session.tutorialStage then
		-- next scripted hand: two pair, then a flush, then a straight flush; then the deal is normal again
		session.tutorialStage = session.tutorialStage + 1
		if session.tutorialStage > #TutorialScript.Stages or not TutorialScript.applyStage(session.state, session.tutorialStage) then
			session.tutorialStage = nil
		end
	end

	local profile = profiles[player]
	if TutorialStart.writesProfile(session) and Onboarding.shouldShowHighCardHint(result.handName, session.state.discardsRemaining, profile) then
		PlayerProfile.markHighCardHintSeen(profile)
		profileDirty[player] = true
		session.onboardingHint = Onboarding.HIGH_CARD_HINT
	end

	pushState(player)
end)

Rem.Discard.OnServerEvent:Connect(function(player, cardIndices)
	if not RateLimit.allow(player.UserId, "Rem.Discard", os.clock()) then return end
	local session = sessions[player]
	if not session or not RunState.phaseAllowsCardActions(session.phase) then
		return
	end
	if not isValidIndexList(cardIndices, #session.state.hand) then
		return
	end
	if session.state.discardsRemaining <= 0 then
		return
	end

	local ok, result = pcall(RunState.discard, session.state, cardIndices)
	if not ok then
		warn("Discard error for " .. player.Name .. ": " .. tostring(result))
		return
	end

	-- A discard can now end the run (RunState's last-resort soft-lock
	-- guard), same as PlayHand's runOver branch above.
	if type(result) == "table" and result.runOver then
		session.phase = "gameover"
	end

	pushState(player)
end)

Rem.BuyPatron.OnServerEvent:Connect(function(player, patronId)
	if not RateLimit.allow(player.UserId, "Rem.BuyPatron", os.clock()) then return end
	local session = sessions[player]
	if not session or not RunState.phaseAllowsShopActions(session.phase) then
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
		pcall(function() -- tuning data: counted in memory, sent once at Game Over (Engine/RunTelemetry.lua)
			require(Engine.RunTelemetry).recordPatronBought(session.telemetry, patronId, session.state.stake, session.state.night)
		end)
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
Rem.SellPatron.OnServerEvent:Connect(function(player, patronId)
	if not RateLimit.allow(player.UserId, "Rem.SellPatron", os.clock()) then return end
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

Rem.BuyRecipe.OnServerEvent:Connect(function(player, category, id)
	if not RateLimit.allow(player.UserId, "Rem.BuyRecipe", os.clock()) then return end
	local session = sessions[player]
	if not session or not RunState.phaseAllowsShopActions(session.phase) then
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

Rem.UseRecipe.OnServerEvent:Connect(function(player, category, id, cardIndices, suit)
	if not RateLimit.allow(player.UserId, "Rem.UseRecipe", os.clock()) then return end
	local session = sessions[player]
	if not session or not RunState.phaseAllowsShopActions(session.phase) then
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

-- A refusal is never silent: the reason (Engine/ShopRefusal) goes to the client as state.shopNotice and the Counter shows it as
-- one line. `seq` changes with every notice so the client shows each one once. In Studio every request is traced to the Output.
local function counterNotice(player, session, text)
	session.shopNotice = { seq = math.floor(os.clock() * 1000), text = text }
	pushState(player)
end
local function counterTrace(...)
	if RunService:IsStudio() then
		print("[Shop server] " .. string.format(...))
	end
end

Rem.RerollShop.OnServerEvent:Connect(function(player)
	if not RateLimit.allow(player.UserId, "Rem.RerollShop", os.clock()) then
		counterTrace("RerollShop from %s dropped by the rate limit", player.Name)
		return
	end
	local session = sessions[player]
	if not session then
		return
	end
	local cost = RunState.rerollCost(session.state, session.rerollCost or Shop.REROLL_BASE_COST)
	local why = require(Engine.ShopRefusal).reroll(RunState.phaseAllowsShopActions(session.phase), session.state.pendingPack, session.state.tips, cost)
	counterTrace("RerollShop from %s: phase %s, tips %d, cost %d, pack open %s -> %s", player.Name, tostring(session.phase),
		math.floor(session.state.tips or 0), math.floor(cost), tostring(session.state.pendingPack ~= nil), why or "rerolled")
	if why then
		counterNotice(player, session, why)
		return
	end
	session.state.tips = session.state.tips - cost
	rollShopOffers(session)
	session.rerollCost = (session.rerollCost or Shop.REROLL_BASE_COST) + Shop.REROLL_COST_STEP
	pushState(player)
end)

-- HAGGLE: "start" opens the 3 second bar for one offered Patron or Pack, "stop" reads the needle from the
-- server clock (the client's own angle is never sent). One per shop visit; refused on ranked boards and in the tutorial.
Rem.Haggle.OnServerEvent:Connect(function(player, action, kind, id)
	if not RateLimit.allow(player.UserId, "Rem.Haggle", os.clock()) then
		counterTrace("Haggle from %s dropped by the rate limit", player.Name)
		return
	end
	local session = sessions[player]
	if not session then
		return
	end
	local Haggle = require(Engine.Haggle)
	local Refusal = require(Engine.ShopRefusal)
	if not RunState.phaseAllowsShopActions(session.phase) or session.state.pendingPack then
		counterTrace("Haggle %s from %s refused: phase %s, pack open %s", tostring(action), player.Name, tostring(session.phase), tostring(session.state.pendingPack ~= nil))
		if action == "start" then -- a stop after the bar timed out stays quiet; a start that goes nowhere says why
			counterNotice(player, session, Refusal.haggle(session.state.pendingPack and "pack_open" or "wrong_phase"))
		end
		return
	end
	if action == "start" then
		local list = (kind == "patron" and session.shopOffers) or (kind == "pack" and session.packOffers) or nil
		local offered = false
		for _, item in ipairs(list or {}) do
			if item.id == id then
				offered = true
			end
		end
		local started, code = false, "bad_item"
		if offered then
			started, code = Haggle.start(session.state, Haggle.ctxFor(session), session.phase, os.clock(), kind, id)
		end
		counterTrace("Haggle start %s %s from %s -> %s", tostring(kind), tostring(id), player.Name, started and "bar open" or tostring(code))
		if started then
			pushState(player)
		else
			counterNotice(player, session, Refusal.haggle(code))
		end
	elseif action == "stop" then
		if Haggle.stop(session.state, os.clock()) then
			pushState(player)
		end
	end
end)

-- WANDERING STRANGER: accept the one Dealer's Bargain on offer (charged and applied by Engine/Strangers.lua) or
-- decline (free, changes nothing). Only in the shop, only the bargain rolled for this visit.
Rem.Stranger.OnServerEvent:Connect(function(player, action)
	if not RateLimit.allow(player.UserId, "Rem.Stranger", os.clock()) then return end
	local session = sessions[player]
	if not session or not RunState.phaseAllowsShopActions(session.phase) or session.state.pendingPack then
		return
	end
	local offer = session.strangerOffer
	if not offer then
		return
	end
	if action == "accept" then
		if require(Engine.Strangers).accept(session.state, offer.id) then
			session.strangerOffer = nil
			pushState(player)
		end
	elseif action == "decline" then
		session.strangerOffer = nil
		pushState(player)
	end
end)

Rem.BuyPack.OnServerEvent:Connect(function(player, packId)
	if not RateLimit.allow(player.UserId, "Rem.BuyPack", os.clock()) then return end
	local session = sessions[player]
	if not session or not RunState.phaseAllowsShopActions(session.phase) then
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

Rem.ResolvePack.OnServerEvent:Connect(function(player, chosenIds, replaceIds)
	if not RateLimit.allow(player.UserId, "Rem.ResolvePack", os.clock()) then return end
	local session = sessions[player]
	if not session or not RunState.phaseAllowsShopActions(session.phase) then
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
	-- Make room (Engine/PackRoom): the owned items that leave so the picks fit. The client only names ids; the engine checks they are
	-- owned, distinct and exactly the overflow, and sells them at half price. Anything else is ignored.
	if replaceIds ~= nil then
		if type(replaceIds) ~= "table" or #replaceIds > 10 then
			return
		end
		for _, id in ipairs(replaceIds) do
			if type(id) ~= "string" then
				return
			end
		end
	end

	local ok, err, message = pcall(RunState.resolvePack, session.state, chosenIds, replaceIds)
	if not ok then
		warn("ResolvePack error for " .. player.Name .. ": " .. tostring(err))
		return
	end
	if err == false and type(message) == "string" then
		counterNotice(player, session, message) -- e.g. "Make room first": the pack stays open and the Counter says why
		return
	end

	pushState(player)
end)

Rem.BuyHousePass.OnServerEvent:Connect(function(player, passId)
	if not RateLimit.allow(player.UserId, "Rem.BuyHousePass", os.clock()) then return end
	local session = sessions[player]
	if not session or not RunState.phaseAllowsShopActions(session.phase) then
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

-- Cosmetic Set purchases/equips are allowed any time (not gated to the
-- shop phase). They live on the permanent profile; Tips come from the run.
-- LOGIN STREAK: claim one reward day. Allowed any time; Tips are added to the current run.
Rem.ClaimLoginReward.OnServerEvent:Connect(function(player, rewardDay)
	if not RateLimit.allow(player.UserId, "Rem.ClaimLoginReward", os.clock()) then return end
	local session = sessions[player]
	local profile = profiles[player]
	if not session or not profile or type(rewardDay) ~= "number" then
		return
	end
	local ok = LoginStreak.claim(profile, rewardDay, session.state)
	if ok then
		profileDirty[player] = true
		pushState(player)
	end
end)

-- RUN SUMMARY: the badge is rebuilt from the server's own run state, the client sends nothing.
Rem.SaveBadge.OnServerEvent:Connect(function(player)
	if not RateLimit.allow(player.UserId, "Rem.SaveBadge", os.clock()) then return end
	local session = sessions[player]
	local profile = profiles[player]
	if not session or not profile or session.phase ~= "gameover" then
		return
	end
	profile.equippedBadge = RunSummary.badgeFromSummary(RunSummary.build(session.state))
	profileDirty[player] = true
	pushState(player)
end)

Rem.BuyCosmeticSet.OnServerEvent:Connect(function(player, setId)
	if not RateLimit.allow(player.UserId, "Rem.BuyCosmeticSet", os.clock()) then return end
	local session = sessions[player]
	local profile = profiles[player]
	if not session or not profile or type(setId) ~= "string" then
		return
	end
	local didNotError, ok = pcall(CosmeticSets.buy, profile, session.state, setId)
	if not didNotError then
		warn("BuyCosmeticSet error for " .. player.Name .. ": " .. tostring(ok))
		return
	end
	if ok then
		profileDirty[player] = true
		pushState(player)
	end
end)

Rem.EquipCosmeticSet.OnServerEvent:Connect(function(player, setId)
	if not RateLimit.allow(player.UserId, "Rem.EquipCosmeticSet", os.clock()) then return end
	local profile = profiles[player]
	if not profile or type(setId) ~= "string" then
		return
	end
	local didNotError, ok = pcall(CosmeticSets.equip, profile, setId, ownedGamePasses[player])
	if not didNotError then
		warn("EquipCosmeticSet error for " .. player.Name .. ": " .. tostring(ok))
		return
	end
	if ok then
		profileDirty[player] = true
		pushState(player)
	end
end)

Rem.EquipCardBack.OnServerEvent:Connect(function(player, backId)
	if not RateLimit.allow(player.UserId, "Rem.EquipCardBack", os.clock()) then return end
	local profile = profiles[player]
	if not profile or (backId ~= nil and type(backId) ~= "string") then
		return
	end
	local didNotError, ok = pcall(CosmeticSets.equipCardBack, profile, backId, ownedGamePasses[player])
	if not didNotError then
		warn("EquipCardBack error for " .. player.Name .. ": " .. tostring(ok))
		return
	end
	if ok then
		profileDirty[player] = true
		pushState(player)
	end
end)

-- WORLD MAP: pick the next road at a fork. Only valid in roundSelect (the start of a Night, before its
-- first round is played or skipped), only for a stop that follows the current one, never on a seeded run.
Rem.ChooseRoad.OnServerEvent:Connect(function(player, stopId)
	if not RateLimit.allow(player.UserId, "Rem.ChooseRoad", os.clock()) then return end
	local session = sessions[player]
	if not session or session.choice then
		return
	end
	-- A locked road is refused here, so a client can never walk one (the compass pick goes through this too).
	local profile = profiles[player]
	local ok = WorldMap.chooseRoad(session.state, stopId, session.phase, function(id)
		return Keys.isRoadOpen(profile, id)
	end)
	if ok then
		pushState(player)
	end
end)

-- BADGES: equip an owned badge (nil clears); Badges.equip refuses anything not owned.
Rem.EquipBadge.OnServerEvent:Connect(function(player, badgeId, slot)
	if not RateLimit.allow(player.UserId, "Rem.EquipBadge", os.clock()) then return end
	if slot == 2 then
		-- VIP second badge slot (Engine/Store.lua): only VIP, only an owned badge
		local vipProfile = profiles[player]
		if vipProfile and (badgeId == nil or type(badgeId) == "string") and Store.equipSecondBadge(
			vipProfile, badgeId, ownedGamePasses[player] ~= nil and ownedGamePasses[player].vip == true,
			badgeId ~= nil and Badges.has(vipProfile, badgeId)
		) then
			profileDirty[player] = true
			pushState(player)
		end
		return
	end
	local profile = profiles[player]
	if not profile or (badgeId ~= nil and type(badgeId) ~= "string") then
		return
	end
	if Badges.equip(profile, badgeId) then
		profileDirty[player] = true
		pushState(player)
	end
end)

-- WORLD MAP: spend one Key to open a locked road for good (Engine/Keys.lua checks the phase, that the road is a
-- pending fork choice, that it is locked and that a Key is available; never on seeded boards).
Rem.UnlockRoad.OnServerEvent:Connect(function(player, stopId)
	if not RateLimit.allow(player.UserId, "Rem.UnlockRoad", os.clock()) then return end
	local session, profile = sessions[player], profiles[player]
	if not session or not profile then
		return
	end
	if Keys.unlock(profile, session.state, stopId, session.phase) then
		profileDirty[player] = true
		pushState(player)
	end
end)

-- WORLD MAP side stops (shop, shrine, rest): (player, stopId, action, arg). Round Select, first round of a
-- Night, standing at the stop's parent, once per run per stop. The rules and every rejection live in
-- Engine/SideStops.lua; this only routes the action.
Rem.SideStop.OnServerEvent:Connect(function(player, stopId, action, arg)
	if not RateLimit.allow(player.UserId, "Rem.SideStop", os.clock()) then return end
	local session = sessions[player]
	if not session or type(stopId) ~= "string" or type(action) ~= "string" then
		return
	end
	local state, phase = session.state, session.phase
	session.sideShops = session.sideShops or {}
	if action == "open" then
		if SideStops.blockedReason(state, stopId, phase) == nil and WorldMap.Stops[stopId].side == "shop"
			and not session.sideShops[stopId] then
			session.sideShops[stopId] = SideStops.rollShop(state)
		end
	elseif action == "buy" then
		SideStops.buy(state, stopId, phase, session.sideShops[stopId], arg)
	elseif action == "leave" then
		if SideStops.finish(state, stopId, phase) then
			session.sideShops[stopId] = nil
		end
	elseif action == "shrine" then
		SideStops.shrine(state, stopId, phase)
	elseif action == "rest" then
		SideStops.rest(state, stopId, phase, arg)
	elseif action == "reveal" then
		-- arg = "token" or "compass"; the rules (and the cost) live in SideStops.reveal
		local profile = profiles[player]
		if SideStops.reveal(state, profile, stopId, phase, arg) and arg == "compass" then
			profileDirty[player] = true
		end
	end
	pushState(player)
end)

-- WORLD MAP minigames: (player, stopId, action, arg). "start" opens the game of a minigame side stop (same
-- gate as the other side stops), the game's own moves ("roll", "hold", "flip", "stop", "answer") are scored by
-- Engine/Minigames.lua on the server, "close" leaves. When a game ends the stop counts as visited; a win gives
-- a token and maybe a compass charge (Minigames.reward). Losing costs nothing.
Rem.Minigame.OnServerEvent:Connect(function(player, stopId, action, arg)
	if not RateLimit.allow(player.UserId, "Rem.Minigame", os.clock()) then return end
	local session, profile = sessions[player], profiles[player]
	if not session or type(stopId) ~= "string" or type(action) ~= "string" then
		return
	end
	local state, phase = session.state, session.phase
	local mg = session.minigame
	if action == "start" then
		local stop = WorldMap.Stops[stopId]
		if mg or not stop or stop.side ~= "minigame" or SideStops.blockedReason(state, stopId, phase) ~= nil then
			return
		end
		local seed = os.time() * 7919 + player.UserId
		local rng = Minigames.newRng(seed)
		session.minigame = { stopId = stopId, g = Minigames.new(stop.game, rng, os.clock()), rng = rng }
	elseif action == "close" then
		session.minigame = nil
	elseif mg and mg.stopId == stopId and not mg.g.done and WorldMap.phaseAllowsRoadChoice(phase) then
		local ok = Minigames.act(mg.g, action, arg, os.clock())
		if ok and mg.g.done then
			SideStops.markVisited(state, stopId)
			if mg.g.won then
				mg.result = Minigames.reward(state, profile, mg.rng)
				PlayerProfile.recordMinigameWin(profile) -- feeds the minigame badges
				profileDirty[player] = true
				if mg.result.compass then
					profileDirty[player] = true
				end
			else
				mg.result = { token = false, compass = false }
			end
		end
	else
		return
	end
	pushState(player)
end)

-- WORLD MAP: spend a compass charge at a fork to reveal the reward at the end of each road.
Rem.UseCompass.OnServerEvent:Connect(function(player, target)
	if not RateLimit.allow(player.UserId, "Rem.UseCompass", os.clock()) then return end
	local session, profile = sessions[player], profiles[player]
	if not session or not profile then
		return
	end
	-- target = the road the client wants to take with it; a locked road is refused before a charge is spent
	local ok = BiomeRewards.useCompass(profile, session.state, session.phase, target, function(id)
		return Keys.isRoadOpen(profile, id)
	end)
	if ok then
		profileDirty[player] = true
		pushState(player)
	end
end)

-- JOURNEY: equip the reward of a cleared node. JourneyMap.equipReward
-- refuses anything not earned.
Rem.EquipJourneyReward.OnServerEvent:Connect(function(player, night)
	if not RateLimit.allow(player.UserId, "Rem.EquipJourneyReward", os.clock()) then return end
	local profile = profiles[player]
	if not profile or type(night) ~= "number" then
		return
	end
	local didNotError, ok = pcall(JourneyMap.equipReward, profile, night, ownedGamePasses[player])
	if not didNotError then
		warn("EquipJourneyReward error for " .. player.Name .. ": " .. tostring(ok))
		return
	end
	if ok then
		profileDirty[player] = true
		pushState(player)
	end
end)

-- ACHIEVEMENTS + TITLES (Phase 16): operates on the permanent
-- `profiles[player]`, not the per-run `session.state`, since a Title is
-- a cross-run choice (same reasoning as the rest of
-- PlayerProfile) -- still gated on an
-- active session existing, purely so a stray remote fire from a not-
-- fully-loaded client can't do anything. `titleId == nil` is a valid,
-- intentional "clear my equipped title" call, not a malformed one.
Rem.EquipTitle.OnServerEvent:Connect(function(player, titleId)
	if not RateLimit.allow(player.UserId, "Rem.EquipTitle", os.clock()) then return end
	local session = sessions[player]
	local profile = profiles[player]
	if not session or not profile then
		return
	end
	if titleId ~= nil and type(titleId) ~= "string" then
		return
	end

	-- This checks 2 separate
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

-- Settings panel / volume popup. No pushState: the client already applied
-- the change locally, and an echo could fight a slider mid-drag.
-- Studio only: DebugGoto patrons:<n> seats n different Patrons through the real grant path (no effect outside Studio).
Rem.DebugGrantPatrons.OnServerEvent:Connect(function(player, n)
	if not RunService:IsStudio() then return end
	local session = sessions[player]
	if not session or type(n) ~= "number" then return end
	n = math.max(0, math.min(8, math.floor(n)))
	local state = session.state
	local Patrons = require(Engine.Patrons)
	state.ownedPatrons = {}
	-- Patrons that fire on any hand (flat chips, flat mult, xmult first), so the debug hand always shows beats
	for _, id in ipairs(Patrons.alwaysFiring(n)) do
		local def = Patrons.getById(id)
		if def then table.insert(state.ownedPatrons, def) end -- straight in: the debug row may be longer than the table's seat limit
	end
	print("[DebugGoto server] patrons=" .. #state.ownedPatrons .. " requested=" .. n)
	pushState(player)
end)

-- Studio only: DebugGoto round1:tag=<id> makes that Tag the current round's skip Tag.
Rem.DebugSetTag.OnServerEvent:Connect(function(player, tagId)
	if not RunService:IsStudio() then return end
	local session = sessions[player]
	if not session or type(tagId) ~= "string" then return end
	local tag = require(Engine.Tags).getById(tagId)
	if not tag then return end
	session.state.currentRoundSkipTag = tag
	pushState(player)
end)

-- Studio only: DebugGoto round1:mod=<id> makes the open blessing draft offer that blessing (the player then picks it through
-- the normal Choice remote), or with report=true prints the applied numbers once the hand is dealt.
Rem.DebugSetMod.OnServerEvent:Connect(function(player, modId, report)
	if not RunService:IsStudio() then return end
	local session = sessions[player]
	if not session or type(modId) ~= "string" then return end
	if report == true then
		local st = session.state
		print("[DebugGoto server] mod=" .. tostring(st.runModifierId) .. " wanted=" .. modId .. " hands=" .. tostring(st.handsRemaining)
			.. " discards=" .. tostring(st.discardsRemaining) .. " patronSlots=" .. tostring(RunState.patronSlotLimit(st)))
		return
	end
	local ok = RunChoice.forceOption(session.choice, modId)
	print("[DebugGoto server] blessing " .. modId .. (ok and " is on offer" or " cannot be offered (unknown id or no blessing draft)"))
	pushState(player)
end)

-- Studio only: DebugGoto playhand:keep raises the round target so one hand scores and the round stays open.
Rem.DebugSetTarget.OnServerEvent:Connect(function(player, n)
	if not RunService:IsStudio() then return end
	local session = sessions[player]
	if not session or type(n) ~= "number" or n ~= n then return end
	session.state.targetScore = math.max(1, math.min(1e9, math.floor(n)))
	pushState(player)
end)

Rem.PreviewMode.OnServerEvent:Connect(function(player, on)
	if not RateLimit.allow(player.UserId, "Rem.PreviewMode", os.clock()) then return end
	player:SetAttribute("PreviewMode", on == true or nil)
end)
Rem.SetSetting.OnServerEvent:Connect(function(player, key, value)
	if not RateLimit.allow(player.UserId, "Rem.SetSetting", os.clock()) then return end
	local profile = profiles[player]
	if not profile then
		return
	end
	local didNotError, ok = pcall(PlayerProfile.setSetting, profile, key, value)
	if didNotError and ok then
		profileDirty[player] = true
		if key == "allowSpectators" and value == false then -- turning spectators off removes everyone watching now
			pcall(function()
				local removed = Spec.M.enforce(Spec.state, player.UserId, false)
				Spec.release(player, removed, "That player turned spectators off.")
			end)
		end
	end
end)

-- TUTORIAL (Phase 16): fired once by Client/Tutorial.lua when the
-- walkthrough is dismissed (either "Got it!" on the last step, or
-- "Skip") -- idempotent, so no harm if it somehow fires more than once
-- for the same player.
Rem.MarkTutorialSeen.OnServerEvent:Connect(function(player, finished)
	if not RateLimit.allow(player.UserId, "Rem.MarkTutorialSeen", os.clock()) then return end
	local profile = profiles[player]
	if not profile then
		return
	end
	-- FIRST 5 MINUTES: only FINISHING the tutorial (not skipping it) pays the reward, once, and only from a tutorial run.
	local tutorialSession = sessions[player]
	if finished == true and tutorialSession and tutorialSession.isTutorial then
		logStep(player, "tutorial_finished")
		local notice = FirstRewards.tutorial(profile)
		if notice then
			pushRewardNotice(player, notice)
			profileDirty[player] = true
			pushState(player)
		end
	end
	if profile.hasSeenTutorial then
		return -- already marked -- nothing changed, no need to dirty/push
	end
	PlayerProfile.markTutorialSeen(profile)
	profileDirty[player] = true
	pushState(player)
end)

Rem.AdvanceRound.OnServerEvent:Connect(function(player)
	if not RateLimit.allow(player.UserId, "Rem.AdvanceRound", os.clock()) then return end
	local session = sessions[player]
	if not session or not RunState.phaseAllowsShopActions(session.phase) then
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
	-- RUN EVENTS: about half the time a new Night opens with an event card (normal runs only).
	local fixedRun = session.isDaily or session.isWeekly or session.isSeeded or session.isTutorial
	if session.state.round == 1 and session.state.night >= 2 then
		session.choice = RunChoice.rollEvent(session.state, not fixedRun)
	end
	-- Studio dev hook: set the player attribute ForceEvent to an event id (see Engine/RunEvents) to see that card now.
	if RunService:IsStudio() and not session.choice and not fixedRun then
		local forced = player:GetAttribute("ForceEvent")
		if forced then
			player:SetAttribute("ForceEvent", nil)
			session.choice = RunChoice.forceEvent(forced)
		end
	end
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

-- MAP DISCOVERIES: claim a revealed spot once; reveal a region's spots with a compass charge.
Rem.ClaimDiscovery.OnServerEvent:Connect(function(player, spotId)
	if not RateLimit.allow(player.UserId, "Rem.ClaimDiscovery", os.clock()) then return end
	local profile = profiles[player]
	if not profile or type(spotId) ~= "string" then
		return
	end
	local ok, result = Discoveries.claim(profile, spotId, {
		patron = function(id) local d = PatronsData.getById(id) return d and d.name end,
		cardBack = function(id) local d = CardBacks.getById(id) return d and d.name end,
	})
	if ok then
		profileDirty[player] = true
		pushRewardNotice(player, { text = result.text })
	end
	pushState(player)
end)

Rem.RevealDiscoveries.OnServerEvent:Connect(function(player, region)
	if not RateLimit.allow(player.UserId, "Rem.RevealDiscoveries", os.clock()) then return end
	local profile = profiles[player]
	if not profile or type(region) ~= "string" then
		return
	end
	local ok, message = Discoveries.reveal(profile, region)
	if ok then
		profileDirty[player] = true
	end
	pushRewardNotice(player, { text = message })
	pushState(player)
end)

-- LIVE EVENTS: claim a running event's rewards once (Engine/LiveEvents.lua); the News panel's Claim button.
Rem.ClaimLiveEvent.OnServerEvent:Connect(function(player, eventId)
	if not RateLimit.allow(player.UserId, "Rem.ClaimLiveEvent", os.clock()) then return end
	local profile = profiles[player]
	if not profile or type(eventId) ~= "string" then
		return
	end
	local ok, result = LiveEvents.claim(profile, eventId, LoginStreak.dayNumber(os.time()), liveLookup)
	if ok then
		profileDirty[player] = true
		Analytics.eventClaimed(player, eventId)
		pushRewardNotice(player, { text = result.event.name .. ": " .. table.concat(result.texts, ", ") })
	else
		pushRewardNotice(player, { text = result })
	end
	pushState(player)
end)

-- RULE BAN (Engine/BossCounters.lua, RunState.useRuleBan): the server validates the phase (Round Select only), the token,
-- that the boss round has not begun and that this run may use tokens at all (normal runs only). The round is dealt again
-- without the rule; the client only asks.
Rem.UseRuleBan.OnServerEvent:Connect(function(player)
	if not RateLimit.allow(player.UserId, "UseRuleBanRemote", os.clock()) then return end
	local session = sessions[player]
	if not session or session.isTutorial or session.isDaily or session.isWeekly or session.isSeeded then
		return
	end
	local ok, reason = RunState.useRuleBan(session.state, session.phase)
	if ok then
		pushRewardNotice(player, { text = "Rule banned. Good luck!" })
	else
		pushRewardNotice(player, { text = reason })
	end
	pushState(player)
end)

-- SPECTATE (Engine/Spectate.lua): watch, stop, react, block, unblock. Everything is validated here: same server only, the
-- target must be in a run and allow spectators, blocks and the cap of 8 apply, reactions are presets with a cooldown.
Rem.SpectateAction.OnServerEvent:Connect(function(player, action, arg)
	if not RateLimit.allow(player.UserId, "Rem.SpectateAction", os.clock()) then return end
	if type(action) ~= "string" then return end
	local profile = profiles[player]
	if not profile then return end
	if action == "watch" then
		local target = type(arg) == "number" and Players:GetPlayerByUserId(arg) or nil -- same server only
		local targetProfile = target and profiles[target]
		local targetSession = target and sessions[target]
		if not target or not targetProfile or not targetSession or targetSession.phase == "gameover" or targetSession.isTutorial then
			Rem.SpectateStream:FireClient(player, { kind = "ended", reason = "That player is not in a run." })
			return
		end
		local previous = Spec.M.watching(Spec.state, player.UserId)
		local ok, reason = Spec.M.watch(Spec.state, player.UserId, target.UserId, {
			allows = Spec.M.allows(targetProfile), blocked = Spec.M.isBlocked(targetProfile, player.UserId),
		})
		if not ok then
			Rem.SpectateStream:FireClient(player, { kind = "ended", reason = reason })
			return
		end
		Analytics.single(player, "spectate_started", 1, {}) -- tuning data (capped)
		local previousPlayer = previous and Players:GetPlayerByUserId(previous)
		if previousPlayer then Spec.notifyCount(previousPlayer) end
		Spec.notifyCount(target)
		local snap = Spec.snapshotFor(target)
		if snap then Spec.send({ player.UserId }, snap) end
	elseif action == "stop" then
		local target = Spec.M.stop(Spec.state, player.UserId)
		local targetPlayer = target and Players:GetPlayerByUserId(target)
		if targetPlayer then Spec.notifyCount(targetPlayer) end
		Spec.send({ player.UserId }, { kind = "ended", reason = "Stopped watching." })
	elseif action == "react" then
		local ok, targetId = Spec.M.reaction(Spec.state, player.UserId, arg, os.clock())
		if ok then
			local event = Spec.M.reactionEvent(arg, Spec.name(player))
			local viewers = Spec.M.watchersOf(Spec.state, targetId)
			viewers[#viewers + 1] = targetId -- shown on both screens
			Spec.send(viewers, event)
		end
	elseif action == "block" or action == "unblock" then
		local targetId = type(arg) == "number" and arg or nil
		if targetId then
			if action == "block" then
				if Spec.M.block(profile, targetId) then
					profileDirty[player] = true
					local removed = Spec.M.enforce(Spec.state, player.UserId, true, function(id) return id == targetId end)
					Spec.release(player, removed, "You were removed from this table.")
				end
			elseif Spec.M.unblock(profile, targetId) then
				profileDirty[player] = true
			end
		end
	end
end)

-- FLAIR (Engine/Flair.lua): equip one option into its slot. The server checks the slot, the option and that the player
-- owns it (free unlock rules are recomputed here, store ones come from flairOwned); the client only asks.
Rem.EquipFlair.OnServerEvent:Connect(function(player, slot, flairId)
	if not RateLimit.allow(player.UserId, "Rem.EquipFlair", os.clock()) then return end
	local profile = profiles[player]
	if not profile or type(slot) ~= "string" or type(flairId) ~= "string" then
		return
	end
	local ok = require(Engine.Flair).equip(profile, slot, flairId)
	if ok then
		profileDirty[player] = true
		if slot == "nameAura" and FlairBoards.publish then
			task.spawn(function() FlairBoards.publish(player) end)
		end
	end
	pushState(player)
end)

-- COLLECTION COMPLETION REWARDS (Engine/CollectionRewards.lua): the server re-checks the progress before paying; once each.
Rem.ClaimCollectionReward.OnServerEvent:Connect(function(player, group, pct)
	if not RateLimit.allow(player.UserId, "Rem.ClaimCollectionReward", os.clock()) then return end
	local profile = profiles[player]
	if not profile or (group ~= "all" and (type(group) ~= "string" or type(pct) ~= "number")) then
		return
	end
	local CollectionRewards = require(Engine.CollectionRewards)
	local texts = {}
	if group == "all" then
		for _, c in ipairs(CollectionRewards.claimAll(profile)) do
			texts[#texts + 1] = CollectionRewards.rewardText(c.reward, liveLookup)
		end
	else
		local ok, reward = CollectionRewards.claim(profile, group, pct)
		if ok then
			texts[1] = CollectionRewards.rewardText(reward, liveLookup)
		end
	end
	if #texts > 0 then
		profileDirty[player] = true
		pushRewardNotice(player, { text = "Collection: " .. table.concat(texts, ", ") })
	end
	pushState(player)
end)

Rem.StoreOpened.OnServerEvent:Connect(function(player)
	if not RateLimit.allow(player.UserId, "Rem.StoreOpened", os.clock()) then return end
	Analytics.single(player, "store_opened", 1, {}) -- budgeted per player per hour like every tuning event
end)

-- FIRST TIME HINTS (Engine/Hints.lua): the client reports a hint it showed; unknown ids are refused. No state push:
-- the client already knows, and an echo could re-trigger a bubble.
Rem.HintSeen.OnServerEvent:Connect(function(player, hintId)
	if not RateLimit.allow(player.UserId, "Rem.HintSeen", os.clock()) then return end
	local profile = profiles[player]
	if profile and require(Engine.Hints).markSeen(profile, hintId) then
		profileDirty[player] = true
	end
end)
Rem.ResetHints.OnServerEvent:Connect(function(player)
	if not RateLimit.allow(player.UserId, "Rem.ResetHints", os.clock()) then return end
	local profile = profiles[player]
	if profile then
		require(Engine.Hints).reset(profile)
		profileDirty[player] = true
		pushState(player)
	end
end)

-- TAVERN SEASON (Engine/SeasonTrack.lua): claim one reached tier (a number) or every reached tier ("all").
-- The server checks the XP, the running season and the claimed set; the client only asks.
Rem.ClaimSeason.OnServerEvent:Connect(function(player, which, premium)
	if not RateLimit.allow(player.UserId, "Rem.ClaimSeason", os.clock()) then return end
	local profile = profiles[player]
	if not profile or (type(which) ~= "number" and which ~= "all") then
		return
	end
	local SeasonTrack = require(Engine.SeasonTrack)
	local day = LoginStreak.dayNumber(os.time())
	local texts = {}
	if which == "all" then
		for _, c in ipairs(SeasonTrack.claimAll(profile, day)) do
			texts[#texts + 1] = SeasonTrack.rewardText(c.reward, liveLookup)
		end
		for _, c in ipairs(SeasonTrack.claimAllPremium(profile, day)) do -- the premium row, only when the pass is owned
			texts[#texts + 1] = SeasonTrack.rewardText(c.reward, liveLookup)
		end
	else
		local ok, reward
		if premium == true then
			ok, reward = SeasonTrack.claimPremium(profile, which, day) -- validates ownership of the pass
		else
			ok, reward = SeasonTrack.claim(profile, which, day)
		end
		if ok then
			texts[1] = SeasonTrack.rewardText(reward, liveLookup)
		end
	end
	if #texts > 0 then
		profileDirty[player] = true
		pushRewardNotice(player, { text = "Season: " .. table.concat(texts, ", ") })
	end
	pushState(player)
end)

-- STORE: prompt a purchase (Roblox shows the real price; the grant happens in ProcessReceipt or on pass ownership).
-- A placeholder item (id 0) is "coming soon" in the live game and free in Studio so it can be playtested.
Rem.StorePurchase.OnServerEvent:Connect(function(player, itemId)
	if not RateLimit.allow(player.UserId, "Rem.StorePurchase", os.clock()) then return end
	local profile = profiles[player]
	local item = type(itemId) == "string" and Store.getById(itemId) or nil
	if not profile or not item or item.listOnly then
		return
	end
	Analytics.single(player, "store_prompt", 1, { item = item.id }) -- tuning data: a purchase prompt was requested
	if not Store.canBuy(item, LoginStreak.dayNumber(os.time())) then
		pushRewardNotice(player, { text = item.name .. " can only be bought while its season is running." })
		pushState(player)
		return
	end
	if Store.owned(profile, item, ownedGamePasses[player]) then
		pushRewardNotice(player, { text = item.name .. " is already yours." })
	elseif Store.isConfigured(item) then
		pcall(function()
			if item.kind == "pass" then
				MarketplaceService:PromptGamePassPurchase(player, Store.robloxId(item))
			else
				MarketplaceService:PromptProductPurchase(player, Store.robloxId(item))
			end
		end)
	elseif RunService:IsStudio() then
		if item.kind == "product" and Store.grant(profile, item.id) then
			profileDirty[player] = true
			pushRewardNotice(player, { text = item.name .. " added (free in Studio)." })
		end
	else
		pushRewardNotice(player, { text = item.name .. " is coming soon." })
	end
	pushState(player)
end)

-- RUN CHOICES: the player answers the open start-of-run draft or between-Nights event card.
Rem.Choice.OnServerEvent:Connect(function(player, optionId)
	if not RateLimit.allow(player.UserId, "Rem.Choice", os.clock()) then return end
	local session = sessions[player]
	if not session or not RunChoice.canAnswer(session.phase, session.choice, optionId) then
		return
	end
	local wasModifier = session.choice.kind == "modifier"
	local ok, message, nextChoice = RunChoice.pick(session.state, session.choice, optionId)
	if ok then
		session.choice = nextChoice
		RunState.refreshSnapshot(session.state) -- One More Round must not undo the pick
	end
	if message and message ~= "" then
		-- a picked blessing shows its painted icon on the plate (Client/UnlockToast), not an emoji
		pushRewardNotice(player, { text = message, blessingId = (ok and wasModifier) and optionId or nil })
	end
	pushState(player)
end)

Rem.SelectRound.OnServerEvent:Connect(function(player)
	if not RateLimit.allow(player.UserId, "Rem.SelectRound", os.clock()) then return end
	local session = sessions[player]
	if not session or session.phase ~= "roundSelect" then
		return
	end
	if session.choice then
		return -- a draft or event card is open: answer it first
	end
	WorldMap.fillDefault(session.state) -- no road picked at a fork: take the default one
	session.minigame = nil
	session.phase = "playing"
	if session.tutorialStage and session.isTutorial then
		TutorialScript.applyStage(session.state, session.tutorialStage) -- stage 1: the pair
	else
		session.tutorialStage = nil
	end
	pushState(player)
end)

Rem.SkipRound.OnServerEvent:Connect(function(player)
	if not RateLimit.allow(player.UserId, "Rem.SkipRound", os.clock()) then return end
	local session = sessions[player]
	if not session or session.phase ~= "roundSelect" then
		return
	end
	if session.choice or not RunState.canSkipRound(session.state) then
		return
	end
	WorldMap.fillDefault(session.state)

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

Rem.RestartRun.OnServerEvent:Connect(function(player)
	if not RateLimit.allow(player.UserId, "Rem.RestartRun", os.clock()) then return end
	local session = sessions[player]
	if not session then
		return
	end
	-- Quick restart: keep whatever Deck Variant/Difficulty this player last
	-- used. Use StartRun instead to pick fresh ones via the Run Setup screen.
	startNewSession(player, session.state.deckVariantId, session.state.difficultyId, nil, nil, nil, nil, session.state.stake,
		{ challengeId = session.state.challenge and session.state.challenge.id, rush = session.state.rush ~= nil, quick = session.state.quickRun == true })
end)

-- Settings > Restart Run: the client confirmed with a hold. Counted as abandoned (stats.runsAbandoned),
-- nothing is granted and nothing is submitted to a leaderboard; then a fresh session starts exactly like
-- New Run (same Deck Variant/Difficulty), so the menu's Play opens a clean run.
Rem.AbandonRun.OnServerEvent:Connect(function(player)
	if not RateLimit.allow(player.UserId, "Rem.AbandonRun", os.clock()) then return end
	local session = sessions[player]
	local ok = RunAbandon.abandon(session, profiles[player], PlayerProfile)
	if not ok then
		return
	end
	profileDirty[player] = true
	startNewSession(player, session.state.deckVariantId, session.state.difficultyId, nil, nil, nil, nil, session.state.stake)
end)

-- The ONLY way a tutorial run begins: the Tutorial tile on the main menu. Scripted hands, no profile writes.
Rem.StartTutorial.OnServerEvent:Connect(function(player)
	if not RateLimit.allow(player.UserId, "Rem.StartTutorial", os.clock()) then return end
	if not sessions[player] then
		return
	end
	startNewSession(player, nil, nil, nil, nil, nil, true)
	logStep(player, "tutorial_started")
end)

Rem.StartRun.OnServerEvent:Connect(function(player, deckVariantId, difficultyId, stakeId, challengeId, mode)
	if not RateLimit.allow(player.UserId, "Rem.StartRun", os.clock()) then return end
	if not sessions[player] then
		return
	end
	if type(stakeId) ~= "number" then
		stakeId = nil -- startNewSession validates it against the profile's highestStakeUnlocked
	end
	if type(deckVariantId) ~= "string" then
		deckVariantId = nil
	end
	if type(difficultyId) ~= "string" then
		difficultyId = nil
	end
	if type(challengeId) ~= "string" then
		challengeId = nil
	end
	startNewSession(player, deckVariantId, difficultyId, nil, nil, nil, nil, stakeId, { challengeId = challengeId, rush = mode == "rush", quick = mode == "quick" })
end)

-- ===== One More Round (see the section next to ProcessReceipt) =====
-- The client only asks; the server decides. Today's free continue
-- (PlayerProfile.freeContinueDateKey) is spent first, and only once the
-- continue has actually been applied. Otherwise this only prompts -- the
-- paid grant happens in ProcessReceipt once Roblox confirms payment. A
-- placeholder product (productId 0) can't be bought, so Studio applies it
-- directly for playtesting; the live game ignores the request until a
-- real id is set.
Rem.RequestState.OnServerEvent:Connect(function(player)
	if not RateLimit.allow(player.UserId, "Rem.RequestState", os.clock()) then return end
	if sessions[player] then pushState(player) end -- display only: re-sends the current table, changes nothing
end)

Rem.RequestContinue.OnServerEvent:Connect(function(player)
	if not RateLimit.allow(player.UserId, "Rem.RequestContinue", os.clock()) then return end
	local session = sessions[player]
	if not session or session.phase ~= "gameover" or not RunState.canContinue(session.state) then
		return
	end
	if hasFreeContinue(player) then
		if applyContinue(player) then
			PlayerProfile.useFreeContinue(profiles[player], SeededRng.dailyDateKey())
			profileDirty[player] = true
			-- Save now, so leaving and rejoining can't hand out a second
			-- free continue today.
			task.spawn(saveProfile, player)
		end
		return
	end
	local product = DeveloperProducts.getById("continue")
	if DeveloperProducts.isConfigured(product) then
		MarketplaceService:PromptProductPurchase(player, product.productId)
	elseif RunService:IsStudio() then
		applyContinue(player)
	end
end)

-- ===== Daily Challenge (Phase 11) =====

Rem.StartDailyChallenge.OnServerEvent:Connect(function(player)
	if not RateLimit.allow(player.UserId, "Rem.StartDailyChallenge", os.clock()) then return end
	if not sessions[player] then
		return
	end
	local seed = SeededRng.dailySeed()
	startNewSession(player, nil, nil, SeededRng.new(seed), "daily", SeededRng.dailyDateKey())
end)

-- ===== Friends scope (Daily and Weekly) =====
-- Friends tab: the player's Roblox friends (plus themselves) from the same store the Everyone
-- board reads. DataStore-cheap: one GetSortedAsync page per store and one friend list per player,
-- both cached for Leaderboards.FRIENDS_CACHE_SECONDS, so opening the tab repeatedly or many
-- players asking at once costs at most one read per minute per store. Friends who are in this
-- server also show their equipped card back and title (offline friends show none).
local friendsPageCache = Leaderboards.newCache(Leaderboards.FRIENDS_CACHE_SECONDS, os.clock) -- [store name] = rows
local friendListCache = Leaderboards.newCache(Leaderboards.FRIENDS_CACHE_SECONDS, os.clock) -- [userId] = { ids, names }

local function getFriendList(player)
	local cached = friendListCache.get(player.UserId)
	if cached then return cached end
	local ids, names = {}, {}
	pcall(function()
		local pages = Players:GetFriendsAsync(player.UserId)
		local count = 0
		while true do
			for _, item in ipairs(pages:GetCurrentPage()) do
				ids[item.Id] = true
				names[item.Id] = item.Username
				count += 1
			end
			if pages.IsFinished or count >= Leaderboards.MAX_FRIENDS then break end
			pages:AdvanceToNextPageAsync()
		end
	end)
	return friendListCache.set(player.UserId, { ids = ids, names = names })
end

Players.PlayerRemoving:Connect(function(p)
	friendListCache.entries[p.UserId] = nil
end)

-- VIP second badge slot: its icon follows the first one on the boards.
local function joinBadgeIcons(first, profile)
	local def2 = profile.equippedBadgeId2 and Badges.getById(profile.equippedBadgeId2)
	if def2 and Badges.has(profile, def2.id) then
		return (first and (first .. " ") or "") .. def2.icon
	end
	return first
end

local function friendFlair(userId)
	for p, profile in pairs(profiles) do
		if p.UserId == userId and profile then
			local backDef = profile.equippedCardBackId and CardBacks.getById(profile.equippedCardBackId)
			local titleDef = profile.equippedTitleId and Achievements.getById(profile.equippedTitleId)
			return backDef and backDef.name or nil, titleDef and titleDef.title or nil, joinBadgeIcons(select(2, Badges.equippedText(profile)), profile), TavernRank.rankFor(profile.tavernXp or 0),
				ownedGamePasses[p] ~= nil and ownedGamePasses[p].vip == true
		end
	end
	return nil, nil
end

local function friendsBoardResult(player, store, storeName, board, dateKey)
	local rows = friendsPageCache.get(storeName)
	local ok = true
	if not rows then
		rows = {}
		ok = pcall(function()
			local pages = store:GetSortedAsync(false, Leaderboards.FRIENDS_PAGE_SIZE)
			for _, entry in ipairs(pages:GetCurrentPage()) do
				local userId = tonumber(entry.key)
				if userId then
					table.insert(rows, {
						userId = userId,
						depth = math.floor(entry.value / DAILY_SCORE_MULTIPLIER),
						tips = entry.value % DAILY_SCORE_MULTIPLIER,
					})
				end
			end
		end)
		if ok then friendsPageCache.set(storeName, rows) end
	end
	local friends = getFriendList(player)
	local top = Leaderboards.friendRows(rows, friends.ids, player.UserId, 10)
	local yourBest = nil
	for _, row in ipairs(top) do
		if row.userId == player.UserId then
			yourBest = { depth = row.depth, tips = row.tips }
		else
			row.name = friends.names[row.userId] or "???"
			row.cardBackName, row.titleText, row.badgeIcon, row.tavernRank, row.vip = friendFlair(row.userId)
		end
		-- the player's own row gets their own name and flair too
		if row.userId == player.UserId then
			row.name = player.Name
			row.cardBackName, row.titleText, row.badgeIcon, row.tavernRank, row.vip = friendFlair(player.UserId)
		end
	end
	return {
		ok = ok,
		board = board,
		scope = Leaderboards.FRIENDS,
		dateKey = dateKey,
		top = top,
		yourBest = yourBest,
		yourBestOk = ok,
	}
end

-- GLOBAL scope (everyone in the game): the same cached sorted page the Friends board reads (one GetSortedAsync of the
-- top FRIENDS_PAGE_SIZE per store per FRIENDS_CACHE_SECONDS), so reopening the board costs no extra reads. Names are
-- cached for 10 minutes and "your best" for the same 60 seconds as the page. `pending` is this player's unsaved entry.
local nameCache = Leaderboards.newCache(600, os.clock) -- [userId] = name
local yourBestCache = Leaderboards.newCache(Leaderboards.FRIENDS_CACHE_SECONDS, os.clock) -- [store name .. userId] = { depth, tips } | false

local function globalBoardResult(player, store, storeName, board, periodKey, pending)
	local rows = friendsPageCache.get(storeName)
	local ok = true
	if not rows then
		rows = {}
		ok = pcall(function()
			local pages = store:GetSortedAsync(false, Leaderboards.FRIENDS_PAGE_SIZE)
			for _, entry in ipairs(pages:GetCurrentPage()) do
				local userId = tonumber(entry.key)
				if userId then
					table.insert(rows, { userId = userId, depth = math.floor(entry.value / DAILY_SCORE_MULTIPLIER), tips = entry.value % DAILY_SCORE_MULTIPLIER })
				end
			end
		end)
		if ok then friendsPageCache.set(storeName, rows) end
	end
	local top = Leaderboards.topRows(rows, 10)
	for _, row in ipairs(top) do
		local name = nameCache.get(row.userId)
		if not name then
			local nameOk, resolved = pcall(function() return Players:GetNameFromUserIdAsync(row.userId) end)
			name = nameOk and resolved or "???"
			if nameOk then nameCache.set(row.userId, name) end
		end
		row.name = name
		row.cardBackName, row.titleText, row.badgeIcon, row.tavernRank, row.vip = friendFlair(row.userId) -- only players in this server have flair
	end
	local yourKey = storeName .. ":" .. player.UserId
	local yourBest = yourBestCache.get(yourKey)
	local yourBestOk = true
	if yourBest == nil then
		yourBest = false
		yourBestOk = pcall(function()
			local raw = store:GetAsync(tostring(player.UserId))
			if type(raw) == "number" then
				yourBest = { depth = math.floor(raw / DAILY_SCORE_MULTIPLIER), tips = raw % DAILY_SCORE_MULTIPLIER }
			end
		end)
		if yourBestOk then yourBestCache.set(yourKey, yourBest) end
	end
	yourBest = yourBest or nil
	if pending and pending.periodKey == periodKey and Leaderboards.improves(yourBest and { depth = yourBest.depth, tips = yourBest.tips } or nil, pending.depth, pending.tips) then
		yourBest = { depth = pending.depth, tips = pending.tips }
	end
	return { ok = ok, board = board, scope = Leaderboards.GLOBAL, dateKey = periodKey, top = top, yourBest = yourBest, yourBestOk = yourBestOk }
end

Rem._lb = {}
Rem._lb.GetEndlessLeaderboard = function(player, board, scope)
	if not Leaderboards.isBoard(board) then
		board = Leaderboards.STANDARD
	end
	local now = os.clock()
	if lastEndlessRequest[player] and now - lastEndlessRequest[player] < LEADERBOARD_COOLDOWN then
		return { ok = false, board = board, dateKey = Leaderboards.ENDLESS_PERIOD, top = {}, yourBest = nil, yourBestOk = false }
	end
	lastEndlessRequest[player] = now
	local store = getEndlessStore(nil, board)
	local storeName = Leaderboards.storeName("endless", board, Leaderboards.ENDLESS_PERIOD)
	if Leaderboards.normalizeScope(scope) == Leaderboards.FRIENDS then
		return friendsBoardResult(player, store, storeName, board, Leaderboards.ENDLESS_PERIOD)
	end
	return globalBoardResult(player, store, storeName, board, Leaderboards.ENDLESS_PERIOD, endlessPending[player] and endlessPending[player][board])
end

-- CHALLENGE A FRIEND: a fresh seed code (the run summary shows it so a friend can enter it in Seed Run).
local lastSeedRequest = {}
Rem.MakeChallengeSeed.OnServerInvoke = function(player)
	local now = os.clock()
	if lastSeedRequest[player] and now - lastSeedRequest[player] < 1 then
		return nil
	end
	lastSeedRequest[player] = now
	return SeededRng.randomCode()
end

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
--
-- PAID CONTINUE: `board` is optional, Leaderboards.STANDARD (the default)
-- or Leaderboards.REVIVED; anything else falls back to Standard.
Rem._lb.GetDailyLeaderboard = function(player, board, scope)
	if not Leaderboards.isBoard(board) then
		board = Leaderboards.STANDARD
	end
	local now = os.clock()
	if lastLeaderboardRequest[player] and now - lastLeaderboardRequest[player] < LEADERBOARD_COOLDOWN then
		return { ok = false, board = board, dateKey = SeededRng.dailyDateKey(), top = {}, yourBest = nil, yourBestOk = false }
	end
	lastLeaderboardRequest[player] = now

	local dateKey = SeededRng.dailyDateKey()
	local store = getDailyStore(dateKey, board)
	if scope == Leaderboards.FRIENDS then
		return friendsBoardResult(player, store, Leaderboards.storeName("daily", board, dateKey), board, dateKey)
	end
	if scope == Leaderboards.GLOBAL then
		local pending = dailyPending[player] and dailyPending[player][board]
		return globalBoardResult(player, store, Leaderboards.storeName("daily", board, dateKey), board, dateKey, pending and { periodKey = pending.dateKey, depth = pending.depth, tips = pending.tips } or nil)
	end

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
	local pending = dailyPending[player] and dailyPending[player][board]
	if pending and pending.dateKey == dateKey and (not yourBest or pending.depth > yourBest.depth) then
		yourBest = { depth = pending.depth, tips = pending.tips }
	end

	return {
		ok = ok,
		board = board,
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

Rem.StartWeeklyChallenge.OnServerEvent:Connect(function(player)
	if not RateLimit.allow(player.UserId, "Rem.StartWeeklyChallenge", os.clock()) then return end
	if not sessions[player] then
		return
	end
	local seed = SeededRng.weeklySeed()
	startNewSession(player, nil, nil, SeededRng.new(seed), "weekly", SeededRng.weeklyDateKey())
end)

Rem._lb.GetWeeklyLeaderboard = function(player, board, scope)
	if not Leaderboards.isBoard(board) then
		board = Leaderboards.STANDARD
	end
	local now = os.clock()
	if lastWeeklyLeaderboardRequest[player] and now - lastWeeklyLeaderboardRequest[player] < LEADERBOARD_COOLDOWN then
		return { ok = false, board = board, dateKey = SeededRng.weeklyDateKey(), top = {}, yourBest = nil, yourBestOk = false }
	end
	lastWeeklyLeaderboardRequest[player] = now

	local weekKey = SeededRng.weeklyDateKey()
	local store = getWeeklyStore(weekKey, board)
	if scope == Leaderboards.FRIENDS then
		return friendsBoardResult(player, store, Leaderboards.storeName("weekly", board, weekKey), board, weekKey)
	end
	if scope == Leaderboards.GLOBAL then
		local pending = weeklyPending[player] and weeklyPending[player][board]
		return globalBoardResult(player, store, Leaderboards.storeName("weekly", board, weekKey), board, weekKey, pending and { periodKey = pending.weekKey, depth = pending.depth, tips = pending.tips } or nil)
	end

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
	local pending = weeklyPending[player] and weeklyPending[player][board]
	if pending and pending.weekKey == weekKey and (not yourBest or pending.depth > yourBest.depth) then
		yourBest = { depth = pending.depth, tips = pending.tips }
	end

	return {
		ok = ok,
		board = board,
		dateKey = weekKey,
		top = top,
		yourBest = yourBest,
		yourBestOk = yourBestOk,
	}
end

-- ===== Phase B ("mind-blowing plan", Alive & Social) =====
-- Two independent beats, both scoped from this pass's architecture
-- research: before this, there was ZERO existing broadcast mechanism in
-- the codebase (every FireClient call anywhere else targets exactly one
-- player) and ZERO existing Friends API usage anywhere. Both below are
-- genuinely new, not an extension of something already half-built.

local TICKER_INTERVAL = 45 -- seconds; ambient, not urgent -- see the task.spawn loop below

-- Reuses the exact Daily Challenge top-N query Rem.GetDailyLeaderboard
-- already does on request (see "Daily Challenge Leaderboard" above) --
-- same store, same combinedScore decoding -- just not gated behind the
-- player opening a menu. Every DataStore call here is independently
-- pcall-wrapped, same discipline as the rest of this file -- a failed
-- read just means this tick's broadcast is skipped, never an error that
-- takes down the ticker loop for good.
local function fetchDailyTickerTop(dateKey)
	local store = getDailyStore(dateKey)
	local top = {}
	local ok = pcall(function()
		local pages = store:GetSortedAsync(false, 5) -- ambient ticker: top 5 is plenty, keeps the read light
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
	if not ok then
		return nil
	end
	return top
end

local function broadcastLeaderboardTicker()
	if #Players:GetPlayers() == 0 then
		return -- nobody to show it to -- skip the DataStore read entirely
	end
	local dateKey = SeededRng.dailyDateKey()
	local top = fetchDailyTickerTop(dateKey)
	if top then
		Rem.LeaderboardTicker:FireAllClients({ dateKey = dateKey, top = top })
	end
end

-- FLAIR NAME AURA ON BOARDS (Engine/Flair.lua): every board row carries the Name Aura id of that player (`flair`) and the
-- aura's crest in front of the name, so other players' crests show on the Daily, Weekly, Endless and Friends boards.
-- The public tag of players in this server is read from their profile; everyone else from a small DataStore
-- (`WildcardTavernFlair_v1`, key u<userId>, written when the aura is equipped) through a 5 minute cache. Rows are copied,
-- never edited in place (the page caches are shared). Every call is pcall'd; a miss just means no crest.
do -- (FlairBoards is declared near the top of the file so the EquipFlair handler can reach it)
	local FlairModule = require(Engine.Flair)
	local tagCache = Leaderboards.newCache(300, os.clock)
	local function store()
		return DataStoreService:GetDataStore("WildcardTavernFlair_v1")
	end
	function FlairBoards.tagFor(userId)
		local inServer = Players:GetPlayerByUserId(userId)
		if inServer then
			local profile = profiles[inServer]
			return profile and FlairModule.publicTag(profile) or nil
		end
		local cached = tagCache.get(tostring(userId))
		if cached ~= nil then
			return cached or nil
		end
		local tag = false
		local ok = pcall(function()
			tag = FlairModule.cleanPublicTag(store():GetAsync("u" .. tostring(userId))) or false
		end)
		if ok then tagCache.set(tostring(userId), tag) end
		return tag or nil
	end
	function FlairBoards.publish(player)
		local profile = profiles[player]
		if not profile then return end
		local tag = FlairModule.publicTag(profile) or ""
		tagCache.set(tostring(player.UserId), tag ~= "" and tag or false)
		pcall(function() store():SetAsync("u" .. tostring(player.UserId), tag) end)
	end
	function FlairBoards.decorate(result)
		if type(result) ~= "table" or type(result.top) ~= "table" then return result end
		local rows = {}
		for i, row in ipairs(result.top) do
			local copy = {}
			for k, v in pairs(row) do copy[k] = v end
			local tag = type(row.userId) == "number" and FlairBoards.tagFor(row.userId) or nil
			local option = tag and FlairModule.getById(tag)
			if option then
				copy.flair = tag
				if option.crest and option.crest ~= "" then
					copy.name = option.crest .. " " .. tostring(copy.name)
				end
			end
			rows[i] = copy
		end
		local out = {}
		for k, v in pairs(result) do out[k] = v end
		out.top = rows
		return out
	end
	for _, remote in ipairs({ Rem.GetDailyLeaderboard, Rem.GetWeeklyLeaderboard, Rem.GetEndlessLeaderboard }) do
		local inner = Rem._lb[remote.Name] -- never read OnServerInvoke (write-only on a RemoteFunction)
		remote.OnServerInvoke = function(...)
			local result = inner(...)
			local ok, decorated = pcall(FlairBoards.decorate, result)
			return ok and decorated or result
		end
	end
end

-- MENU TICKER: GetMenuTicker returns { top = { name, depth, tips, title }, runs } for the main menu strip. One DataStore
-- read of the Daily board top and one of the run counter per minute per server (cached), one counter write per minute
-- (the runs started on this server since the last write). Every call is pcall'd: a failure returns the last data or
-- an empty table, and the client shows a flavor line instead.
do
	local TickerRemote = Instance.new("RemoteFunction")
	TickerRemote.Name = "GetMenuTicker"
	TickerRemote.Parent = Rem._folder
	local MenuTicker = require(Engine.MenuTicker)
	TickerRemote.OnServerInvoke = function(player)
		if not RateLimit.allow(player.UserId, "GetMenuTicker", os.clock()) then
			return menuTicker.data or {}
		end
		local now = os.clock()
		if menuTicker.data and now - menuTicker.at < MenuTicker.CACHE_SECONDS then
			return menuTicker.data
		end
		menuTicker.at = now
		local dateKey = SeededRng.dailyDateKey()
		local data = { dateKey = dateKey }
		pcall(function()
			local top = fetchDailyTickerTop(dateKey)
			local first = top and top[1]
			if first then
				local title
				local inServer = first.userId and Players:GetPlayerByUserId(first.userId)
				local profile = inServer and profiles[inServer]
				local def = profile and profile.equippedTitleId and Achievements.getById(profile.equippedTitleId)
				title = def and def.title or nil
				data.top = { name = first.name, depth = first.depth, tips = first.tips, title = title }
			end
		end)
		pcall(function()
			local counter = DataStoreService:GetDataStore("WildcardTavernDailyRuns_v1")
			local key = "d" .. tostring(dateKey)
			local total
			if menuTicker.pending > 0 and now - menuTicker.flushedAt >= MenuTicker.CACHE_SECONDS then
				local add = menuTicker.pending
				menuTicker.pending = 0
				menuTicker.flushedAt = now
				local ok, result = pcall(function()
					return counter:UpdateAsync(key, function(old) return (tonumber(old) or 0) + add end)
				end)
				if ok then total = result else menuTicker.pending = menuTicker.pending + add end
			end
			if not total then
				total = counter:GetAsync(key)
			end
			data.runs = tonumber(total) or 0
		end)
		if not data.top and not data.runs and menuTicker.data then
			return menuTicker.data -- the stores failed: keep showing the last good numbers
		end
		menuTicker.data = data
		return data
	end
end

-- FRIEND PRESENCE: deliberately NOT built on Players:GetFriendsAsync (a
-- paginated, "give me this player's WHOLE friends list" call) -- what
-- this actually needs is the opposite, much cheaper question: "of the
-- (at most a handful of) players already in THIS server, which ones is
-- this player friends with?" Player:IsFriendsWith(userId) answers that
-- directly, one call per other player in the server, no pagination and
-- no caching needed at this player count.
local function getFriendPresenceList(player)
	local list = {}
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= player then
			local ok, isFriend = pcall(function()
				return player:IsFriendsWith(other.UserId)
			end)
			if ok and isFriend then
				local otherSession = sessions[other]
				local otherState = otherSession and otherSession.state
				table.insert(list, {
					userId = other.UserId,
					name = other.Name,
					night = otherState and otherState.night or nil,
					round = otherState and otherState.round or nil,
					tips = otherState and otherState.tips or nil,
					-- SPECTATE: a Watch button shows for a friend in a run who allows it (the server re-checks on watch)
					canWatch = otherSession ~= nil and not otherSession.isTutorial and otherSession.phase ~= "gameover"
						and profiles[other] ~= nil and Spec.M.allows(profiles[other])
						and not Spec.M.isBlocked(profiles[other], player.UserId),
					watching = Spec.M.watching(Spec.state, player.UserId) == other.UserId,
					bestNightReached = profiles[other] and profiles[other].stats and profiles[other].stats.bestNightReached or nil,
				})
			end
		end
	end
	return list
end

local function pushFriendPresence(player)
	Rem.FriendPresence:FireClient(player, getFriendPresenceList(player))
end

local function pushAllFriendPresence()
	for _, player in ipairs(Players:GetPlayers()) do
		pushFriendPresence(player)
	end
end

-- One shared ambient loop for both beats -- a second independent loop on
-- the same interval would just be two timers doing the same "is anyone
-- here" check. Friend presence changes far less often than a Daily
-- Challenge leaderboard position might, but refreshing it this often
-- costs nothing (no DataStore call, just IsFriendsWith + in-memory
-- session reads) and keeps "who's playing right now" from ever going
-- stale for more than one tick.
task.spawn(function()
	while true do
		task.wait(TICKER_INTERVAL)
		broadcastLeaderboardTicker()
		pushAllFriendPresence()
	end
end)

-- Separate PlayerAdded/PlayerRemoving listeners (Roblox events support
-- multiple independent :Connect() callbacks just fine) instead of adding
-- calls into the EXISTING onPlayerAdded function/PlayerRemoving
-- connection far above -- those are defined textually BEFORE this
-- section, so a call from there into the functions just above would be
-- a forward-reference to a still-nil local. This way a newly-joined
-- player (and everyone already in the server) sees the ticker/friend
-- list within a second or two of a join/leave, instead of only ever on
-- the next up-to-TICKER_INTERVAL-seconds tick above.
Players.PlayerAdded:Connect(function(_player)
	-- Letting the OTHER PlayerAdded listener's own session/profile setup
	-- land first (it yields on a profile load) before reading sessions/
	-- profiles here -- a slightly-early read just undercounts this one
	-- refresh by one player for a tick, never an error.
	task.wait(1)
	broadcastLeaderboardTicker()
	pushAllFriendPresence()
end)
Players.PlayerRemoving:Connect(function(_player)
	-- task.defer (not task.wait(0)/task.spawn) specifically so this runs
	-- after Roblox actually removes the leaving player from
	-- Players:GetPlayers() -- otherwise everyone else's refreshed list
	-- would still include them for one more tick.
	task.defer(pushAllFriendPresence)
end)

-- ===== Shareable Seed Codes (Phase 16) =====
-- No leaderboard -- this is for two friends comparing one specific run
-- on demand (see SeededRng.lua's header for what "same seed" guarantees
-- once your choices start diverging from theirs), not a ranked board.
-- Server-side validation is deliberately light (just a length/type
-- check) since a bad/garbage code just produces SOME deterministic seed
-- -- there's no invalid input here, only "not the code your friend
-- typed," which is a matched-code problem between the two of you, not a
-- server-side error case.
Rem.StartSeedRun.OnServerEvent:Connect(function(player, code)
	if not RateLimit.allow(player.UserId, "Rem.StartSeedRun", os.clock()) then return end
	if not sessions[player] then
		return
	end
	if type(code) ~= "string" then
		return
	end
	local okCode, normalized = SeededRng.validateCode(code) -- 6 characters, A-Z without I and O, digits 2-9
	if not okCode then
		return
	end
	code = normalized
	local seed = SeededRng.codeToSeed(code)
	startNewSession(player, nil, nil, SeededRng.new(seed), "seed", code)
end)
