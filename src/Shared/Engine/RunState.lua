--[[
	RunState.lua
	The single-player run/round state machine: nights -> rounds -> hands,
	with a shop between rounds. Pure Lua -- no Roblox APIs -- so the whole
	run can be simulated and unit tested without ever opening Studio.

	A "state" here is a plain table (see RunState.new). Every function takes
	the state as its first argument and mutates it in place, then returns
	whatever result info is useful to the caller (server script / tests).
]]

local Deck = require(script.Parent.Deck)
local Card = require(script.Parent.Card)
local HandEvaluator = require(script.Parent.HandEvaluator)
local Scoring = require(script.Parent.Scoring)
local Patrons = require(script.Parent.Patrons)
local EndlessRules = require(script.Parent.EndlessRules)
local RunModes = require(script.Parent.RunModes) -- Quick Run (4 Nights)
local DeckVariants = require(script.Parent.DeckVariants)
local NightBoons = require(script.Parent.NightBoons)
local StartingDecks = require(script.Parent.StartingDecks)
local DifficultyTiers = require(script.Parent.DifficultyTiers)
local BossRounds = require(script.Parent.BossRounds)
local Tags = require(script.Parent.Tags)
local Recipes = require(script.Parent.Recipes)
local HousePasses = require(script.Parent.HousePasses)
local Packs = require(script.Parent.Packs)
local PackRoom = require(script.Parent.PackRoom)
local TrueWildcard = require(script.Parent.TrueWildcard)
local WorldMap = require(script.Parent.WorldMap)
local RunSummary = require(script.Parent.RunSummary)
local Stakes = require(script.Parent.Stakes)
local Unlocks = require(script.Parent.Unlocks)
local BossRules = require(script.Parent.BossRules)
local Challenges = require(script.Parent.Challenges)
local BossRush = require(script.Parent.BossRush)
local WelcomeEase = require(script.Parent.WelcomeEase) -- eased Night 1 and 2 targets for a new profile's first runs
local DailyModifiers = require(script.Parent.DailyModifiers) -- the Daily Run's twist of the day
local Haggle = require(script.Parent.Haggle) -- one haggle per shop visit moves one price by 1 Tip
local Strangers = require(script.Parent.Strangers) -- Dealer's Bargains: numeric run effects

local RunState = {}

RunState.DefaultConfig = {
	handSize = 8,
	handsPerRound = 4,
	discardsPerRound = 3,
	roundsPerNight = 3,
	tipsPerRoundWin = 4,
	-- How many Patrons can sit at your table at once. With 22 Patrons in
	-- the pool, "buy every single one" would make the choice of WHICH
	-- Patrons to run meaningless -- a real cap is what makes selling one
	-- to make room for a better fit an actual decision (RunState.sellPatron
	-- already exists for exactly this). A Reserved Special on an owned
	-- Patron (see RunState.patronSlotLimit) is the intended way to grow
	-- past this over the course of a run.
	patronSlotLimit = 5,
	-- GENRE PARITY: how many House+Menu+Secret Recipes can be held at
	-- once, COMBINED -- one shared "recipe box", matching the genre's single
	-- consumable-slot area rather than a separate cap per category. See
	-- RunState.recipeSlotLimit.
	recipeSlotLimit = 2,
	-- GENRE PARITY: clear the Boss Round of this Night and the run is
	-- marked WON (state.wonRun) -- the usual 8-stage win in this genre. The run
	-- doesn't stop there, though -- Nights keep climbing past this exactly
	-- like they always did, so this is really just "which Night does
	-- Endless Mode start after." See RunState.playHand/targetScoreFor.
	nightCap = 8,
}

--[[
	GENRE PARITY: Small/Big/Boss Blind distinct score multipliers (Ahmed:
	"Small/Big/Boss Blind at distinct score multipliers"),
	replacing the old single continuous curve. Two independent knobs now,
	multiplied together in targetScoreFor:
		1) nightBaseScoreFor(night) -- how hard THIS NIGHT is, growing
		   exponentially with Night (unbounded -- this is what keeps Endless
		   Mode getting harder forever, see below).
		2) blindMultiplierFor(night, round, roundsPerNight) -- which Blind
		   you're on this round: Small (round 1) = 1x, Big (any round
		   between) = 1.5x, Boss (the Night's last round) scales from 2x at
		   Night 1 up to 2.5x at Night `nightCap` (8, the genre's usual run length),
		   then plateaus at 2.5x forever after -- Endless Mode keeps escalating
		   purely through nightBaseScoreFor's unbounded growth instead of an
		   ever-climbing Boss multiplier.
	Public (not just internal) so tests/UI can reason about either knob on
	its own without re-deriving the formula.
]]
local TARGET_BASE_SCORE = 65
local TARGET_NIGHT_GROWTH = 2.15
local BLIND_MULTIPLIER_SMALL = 1
local BLIND_MULTIPLIER_BIG = 1.5
local BOSS_BLIND_MULTIPLIER_MIN = 2
local BOSS_BLIND_MULTIPLIER_MAX = 2.5

-- Modest lift for Nights 2 and 3: the sim's strong bot cleared both 100% of the time.
-- Night 1 stays as is (WelcomeEase and the first-five-minutes win). Nights 4 and 5 got a 10 percent step
-- after the --late sim cleared them 89 to 92 percent with a 4 Patron build. Night 6 and later unchanged.
local NIGHT_TUNE = { [2] = 1.12, [3] = 1.2, [4] = 1.1, [5] = 1.1 }

-- Endless Nights (past the Night 8 cap) climb a little slower per Night, so a good run ends around Night 10 to 14
-- (the --endless sim). Nights 1 to 8 are untouched.
local ENDLESS_NIGHT_GROWTH = 1.5
local ENDLESS_FROM_NIGHT = 8

function RunState.nightBaseScoreFor(night)
	local plainNights = math.min(night, ENDLESS_FROM_NIGHT)
	local base = TARGET_BASE_SCORE * (TARGET_NIGHT_GROWTH ^ (plainNights - 1)) * (NIGHT_TUNE[night] or 1)
	if night > ENDLESS_FROM_NIGHT then
		base = base * (ENDLESS_NIGHT_GROWTH ^ (night - ENDLESS_FROM_NIGHT))
	end
	return base
end

function RunState.blindMultiplierFor(night, round, roundsPerNight, nightCap)
	roundsPerNight = roundsPerNight or RunState.DefaultConfig.roundsPerNight
	-- BUGFIX: accept nightCap as a parameter (defaulting to the global
	-- constant only when the caller doesn't pass one -- same pattern as
	-- roundsPerNight above), instead of always reading
	-- RunState.DefaultConfig.nightCap directly. RunState.startRound
	-- already threads its OWN run's state.config.nightCap through (see
	-- below) -- reading the global default here instead would silently
	-- desync the Boss multiplier's ramp/plateau from whatever Night
	-- the run's actual win condition (RunState.playHand) fires at, the
	-- moment anything (a future deck variant's configOverrides, say) ever
	-- makes a run's nightCap differ from the default.
	if round >= roundsPerNight then
		-- Boss Blind: 2x at Night 1, linearly up to 2.5x at Night `nightCap`,
		-- then held flat at 2.5x for every Night after that.
		nightCap = nightCap or RunState.DefaultConfig.nightCap
		local growthSteps = nightCap - 1
		if growthSteps <= 0 then
			return BOSS_BLIND_MULTIPLIER_MAX
		end
		local cappedNight = math.min(night, nightCap)
		local progress = (cappedNight - 1) / growthSteps
		return BOSS_BLIND_MULTIPLIER_MIN + progress * (BOSS_BLIND_MULTIPLIER_MAX - BOSS_BLIND_MULTIPLIER_MIN)
	elseif round <= 1 then
		return BLIND_MULTIPLIER_SMALL
	else
		return BLIND_MULTIPLIER_BIG
	end
end

-- `baseNight` (optional) is the Night the BASE score is read at (a Quick Run compresses its curve); the Blind
-- multiplier always follows the real `night` and `nightCap`.
function RunState.targetScoreFor(night, round, roundsPerNight, nightCap, baseNight)
	roundsPerNight = roundsPerNight or RunState.DefaultConfig.roundsPerNight
	local base = RunState.nightBaseScoreFor(baseNight or night)
	local blindMultiplier = RunState.blindMultiplierFor(night, round, roundsPerNight, nightCap)
	return math.floor(base * blindMultiplier)
end

-- How many Recipes (House + Menu + Secret combined) are currently held.
local function totalHeldRecipes(state)
	return #state.houseRecipeInventory + #state.menuRecipeInventory + #state.secretRecipeInventory
end

--[[
	options (all optional): { deckVariantId = string, difficultyId = string,
	nightOneBonusDiscards = number, welcomeEase = boolean }
	Unknown/omitted deckVariantId/difficultyId fall back to the standard deck
	variant and standard difficulty, so `RunState.new()` and
	`RunState.new(nil, rng)` both still produce the original default-balance
	run.
]]
function RunState.new(options, rng)
	options = options or {}

	local deckVariant = DeckVariants.getById(options.deckVariantId) or DeckVariants.getById(DeckVariants.DefaultId)
	local difficulty = DifficultyTiers.getById(options.difficultyId) or DifficultyTiers.getById(DifficultyTiers.DefaultId)

	local config = {}
	for key, value in pairs(RunState.DefaultConfig) do
		config[key] = value
	end
	for key, delta in pairs(deckVariant.configOverrides or {}) do
		config[key] = config[key] + delta
	end
	for key, delta in pairs((StartingDecks.getById(options.startingDeckId) or {}).configDelta or {}) do
		config[key] = config[key] + delta -- Slim Deck: 1 fewer Discard
	end
	config.handSize = math.max(1, config.handSize)
	config.handsPerRound = math.max(1, config.handsPerRound)
	config.discardsPerRound = math.max(0, config.discardsPerRound)
	config.roundsPerNight = math.max(1, config.roundsPerNight)
	config.patronSlotLimit = math.max(1, config.patronSlotLimit)
	config.recipeSlotLimit = math.max(0, config.recipeSlotLimit)
	config.nightCap = math.max(1, config.nightCap)
	-- RUN MODE (Engine/RunModes.lua): a Quick Run is 4 Nights, always stake 1, no Crowd Rules. Normal runs pass no mode.
	local quick = options.mode == "quick"
	if quick then
		config.nightCap = RunModes.get("quick").nights
		options.stakeId = 1
		options.endlessRules = false
	end

	-- STAKES (Engine/Stakes.lua): each stake adds one rule; stake 1 changes nothing.
	local stake = Stakes.clamp(options.stakeId)
	local stakeRules = Stakes.rulesFor(stake)
	config.discardsPerRound = math.max(0, config.discardsPerRound + stakeRules.discardsDelta)
	config.recipeSlotLimit = math.max(0, config.recipeSlotLimit + stakeRules.recipeSlotDelta)
	config.tipsPerRoundWin = math.max(1, config.tipsPerRoundWin + stakeRules.tipsPerRoundDelta)
	config.tipsNonBossDelta = stakeRules.tipsNonBossDelta

	local state = {
		config = config,
		rng = rng,
		stake = stake,
		stakeRules = stakeRules,
		-- ENDLESS (Engine/EndlessRules.lua): Crowd Rules after the Night cap, normal runs only.
		endlessRulesEnabled = options.endlessRules == true,
		-- RULE BAN tokens (Engine/Stakes.lua RuleBansAtStart): only a run created with options.ruleBans = true has them, so the
		-- server decides which runs may use them (normal runs; never Daily, Weekly, Seed, Boss Rush, challenge or tutorial).
		ruleBansEnabled = options.ruleBans == true and not quick,
		ruleBans = (options.ruleBans == true and not quick) and Stakes.ruleBansFor(stake) or 0,
		quickRun = quick, -- Engine/RunModes.lua
		runMode = quick and "quick" or nil,
		-- UNLOCK DRIP (Engine/Unlocks.lua): set of open gated content, nil = everything is available.
		unlockedContent = options.unlockedContent,
		deckVariantId = deckVariant.id,
		startingDeckId = (StartingDecks.getById(options.startingDeckId) or StartingDecks.getById(StartingDecks.DefaultId)).id,
		difficultyId = difficulty.id,
		targetMultiplier = (deckVariant.targetScoreMultiplier or 1) * (difficulty.targetScoreMultiplier or 1),
		bossRoundsEnabled = difficulty.bossRoundsEnabled ~= false,
		night = 1,
		round = 1,
		-- WORLD MAP: the stop of each Night chosen so far (Night n = worldRoute[n]); worldPlan is a fixed
		-- route for Daily, Weekly and Seed runs (see WorldMap.routeFromSeed), nil on free runs.
		worldRoute = { WorldMap.Start },
		worldPlan = options.worldPlan,
		tips = deckVariant.startingTips or 0,
		ownedPatrons = {},
		-- Persistent, run-long card pool: `deck` is the draw pile, `discardPile`
		-- is everything played/discarded so far this run waiting to be
		-- reshuffled back in at the start of the next round. Cards are the
		-- SAME Lua tables all run (never regenerated), so a Garnish/Special/
		-- Stamp a House Recipe adds to a card sticks with it for the run.
		deck = StartingDecks.build(options.startingDeckId), -- Classic, Lucky or Slim (Engine/StartingDecks), unshuffled; startRound below shuffles+deals
		discardPile = {},
		hand = {},
		handsRemaining = config.handsPerRound,
		discardsRemaining = config.discardsPerRound,
		roundScore = 0,
		targetScore = 0, -- computed by startRound below
		handStats = {}, -- [handName] = times played this run, for the Poker Hands reference screen
		handTypesPlayedThisRound = {}, -- reset each round; used by the "No Repeats" Boss Round
		handLevels = {}, -- [handName] = level, raised by Menu Recipes -- see Scoring.HandLevelGrowth
		houseRecipeInventory = {}, -- array of Recipes.HouseRecipes ids currently owned, unused
		menuRecipeInventory = {},
		secretRecipeInventory = {},
		lastRecipeUsedId = nil, -- for the "Second Helping" House Recipe
		lastRecipeUsedCategory = nil, -- "house" | "menu" | "secret" -- see RunState.useRecipe's BUGFIX comment
		ownedPatronSpecials = {}, -- [patronId] = Card.Specials id, folded into Scoring.calculate
		housePasses = {}, -- [passId] = true, permanent for the rest of the run -- see HousePasses.lua
		pendingPack = nil, -- set by RunState.openPack, cleared by RunState.resolvePack -- see below
		brittleShieldRound = false, -- set by the "Sugar Shield" Secret Recipe, reset each round -- see below
		bossModifier = nil,
		-- True on the last round of every Night, on EVERY difficulty --
		-- including Casual, where bossModifier stays nil (no modifier) but
		-- the round is still the Night's boss-sized finale. Use
		-- RunState.isBossRound(state) for "is this a boss round?" checks;
		-- bossModifier is only for the modifier's actual effects.
		isBossRound = false,
		-- JOURNEY FEATURE: this Night's Boss Round modifier, picked once
		-- when the Night's first round starts (see startRound below) and
		-- held for the rest of the Night, so the Journey map can reveal
		-- which specific Boss you're walking toward before you ever reach
		-- Round `roundsPerNight` -- it used to only get picked at the
		-- instant the Boss round itself started, so there was no way to
		-- know in advance. `bossModifier` (above) still only gets set to
		-- this on the actual Boss round itself -- everywhere else that
		-- reads bossModifier for scoring/hand-size/etc purposes is
		-- unaffected.
		nightBossModifier = nil,
		-- ROUND SELECT FEATURE: the Tag you'd get for skipping the round
		-- you're CURRENTLY on, picked fresh every startRound (see below) --
		-- nil on the Boss round (never skippable). See Tags.lua.
		currentRoundSkipTag = nil,
		-- Set by the "Sale Day Tag" (Tags.lua): a flat Tips-off discount
		-- applied to Patron/Pack prices for the very next shop visit only,
		-- then cleared when that visit ends -- see patronPrice/packPrice
		-- and advanceToNextRound below.
		nextShopDiscount = nil,
		roundOver = false,
		runOver = false,
		wonRun = false,
		-- Actual total Tips gained on the most recent round win (flat
		-- reward + boss double + every Patron onRoundWin bonus + the
		-- universal interest rule) -- see RunState.playHand.
		lastRoundReward = 0,
		-- Run-long tallies that scaling Patrons read through the scoring
		-- context -- see RunState.runCounters.
		roundsCleared = 0,
		bossesCleared = 0,
		handsPlayedTotal = 0,
		discardsUsedTotal = 0,
		patronsSold = 0,
		-- Extra discards each round of Night 1, for brand-new profiles --
		-- see Onboarding.bonusDiscards.
		nightOneBonusDiscards = options.nightOneBonusDiscards or 0,
		-- WELCOME EASE (Engine/WelcomeEase.lua): the server sets this for a new profile's first normal runs only.
		welcomeEase = options.welcomeEase == true and not quick,
		-- PAID CONTINUE: true once this run has used its one continue (see
		-- RunState.useContinue). Never resets for the rest of the run. A
		-- revived run submits to the "Revived" leaderboards instead of
		-- "Standard" and stops counting toward high score records (see
		-- Leaderboards.lua and RunState.countsForRecords).
		revived = false,
	}

	-- PHASE C ("mind-blowing plan" Signature Mechanic): seed exactly ONE
	-- True Wildcard into this run's deck -- see TrueWildcard.lua's header
	-- and RunState.playHand's matching block for how/when it resolves.
	-- Picked from the fresh, still-UNSHUFFLED 52-card deck (any index is
	-- equally likely to end up anywhere once RunState.startRound shuffles
	-- it below) -- it keeps its normal dealt rank/suit and plays like any
	-- other card right up until the first time it's actually played.
	local wildcardRng = state.rng or math.random
	local wildcardIndex = wildcardRng(#state.deck)
	state.deck[wildcardIndex].isTrueWildcard = true
	state.deck[wildcardIndex].wildcardLocked = false

	-- BOSS RUSH / CHALLENGE RUN: set the run up before its first round is dealt (Engine/BossRush.lua, Challenges.lua).
	if options.rush then
		BossRush.configure(state)
	elseif options.challengeId then
		Challenges.configure(state, options.challengeId)
	elseif options.dailyModifierId then
		DailyModifiers.configure(state, options.dailyModifierId) -- the Daily Run's twist of the day (Engine/DailyModifiers.lua)
	end
	RunState.startRound(state)
	return state
end

-- ONE MORE ROUND: a deep copy of the run for state.roundStartSnapshot (see
-- RunState.useContinue). The memo keeps shared tables shared -- a card is
-- one table wherever it sits, and bossModifier is nightBossModifier on a
-- Boss round. Registry definitions (Patrons, Boss modifiers, Tags) and the
-- rng are kept by reference: they're never mutated per run, and Patron
-- definitions hold functions.
local SNAPSHOT_BY_REFERENCE = {
	rng = true,
	bossModifier = true,
	nightBossModifier = true,
	currentRoundSkipTag = true,
	pendingPack = true,
}

local function holdsFunction(value)
	for _, field in pairs(value) do
		if type(field) == "function" then
			return true
		end
	end
	return false
end

local function deepCopy(value, memo)
	if type(value) ~= "table" then
		return value
	end
	if memo[value] then
		return memo[value]
	end
	if holdsFunction(value) then
		return value
	end
	local copy = {}
	memo[value] = copy
	for key, field in pairs(value) do
		copy[deepCopy(key, memo)] = deepCopy(field, memo)
	end
	return copy
end

local function copyForSnapshot(state)
	local memo = {}
	local copy = {}
	for key, value in pairs(state) do
		if key ~= "roundStartSnapshot" then
			copy[key] = SNAPSHOT_BY_REFERENCE[key] and value or deepCopy(value, memo)
		end
	end
	return copy
end

-- Pools whatever's left in the draw pile + discard pile + hand back
-- together, reshuffles, picks this round's Boss modifier (if any), and
-- deals a new starting hand. Cards are never regenerated -- this is what
-- lets a Garnish/Special/Stamp persist across rounds (see RunState.new).
-- One Crowd Rule number (0 when Endless rules are off or not active yet).
local function endlessField(state, field)
	return state.endlessRules and state.endlessRules[field] or 0
end

-- The target a round of the current Night has, by ONE set of sums: startRound uses it for the round that begins, and
-- the server sends it for every round of the Night, so Round Select shows the number the table will show. Round Select
-- used to work its number out from the Night and the round alone, which left out the run's deck and difficulty, Quick
-- Run's curve and everything that moves a Boss Round's target (the boss's own multiplier, the stake, Warm Welcome,
-- the Crowd Rules).
function RunState.targetForRound(state, round)
	local roundsPerNight = state.config.roundsPerNight
	local isBossRound = BossRounds.isBossRound(round, roundsPerNight)
	-- (a boss banned with a Rule Ban fights with no rule, so its target multiplier is off as well)
	local bossModifier = (state.bossRoundsEnabled and isBossRound and state.bannedBossNight ~= state.night) and state.nightBossModifier or nil
	local bossMultiplier = (bossModifier and bossModifier.targetScoreMultiplier) or 1
	if isBossRound and state.stakeRules then
		bossMultiplier = bossMultiplier * (1 + state.stakeRules.bossTargetPct / 100) -- Rowdy Crowd stake
	end
	if isBossRound and state.housePasses.warm_welcome then
		bossMultiplier = bossMultiplier * 0.9 -- Warm Welcome
	end
	if isBossRound then
		bossMultiplier = bossMultiplier * (1 + endlessField(state, "bossTargetPct") / 100)
	end
	local baseTarget
	if state.quickRun then
		-- Quick Run: the compressed curve (Night n of 4 scores like Night 1 + (n - 1) * 7 / 3), gentle first Night
		baseTarget = RunState.targetScoreFor(state.night, round, roundsPerNight, state.config.nightCap,
			RunModes.equivalentNight("quick", state.night)) * RunModes.targetScale("quick", state.night)
	else
		baseTarget = RunState.targetScoreFor(state.night, round, roundsPerNight, state.config.nightCap)
	end
	local target = math.floor(EndlessRules.clampTarget(baseTarget * state.targetMultiplier * bossMultiplier))
	if state.welcomeEase then
		target = WelcomeEase.scale(target, state.night)
	end
	return target
end

function RunState.startRound(state)
	for _, card in ipairs(state.hand) do
		table.insert(state.deck, card)
	end
	for _, card in ipairs(state.discardPile) do
		card.usedAs = nil
		table.insert(state.deck, card)
	end
	state.discardPile = {}
	state.hand = {}
	state.deck = Deck.shuffle(state.deck, state.rng)

	-- JOURNEY FEATURE: pick this Night's Boss modifier as soon as its FIRST
	-- round starts (not lazily, only once you reach the Boss round itself)
	-- so it's knowable -- and can be shown on the Journey map -- for the
	-- whole Night leading up to it. `state.round == 1` is the "a new Night
	-- just started" signal here (RunState.new's initial startRound call
	-- also lands here, since every run/Night begins at round 1).
	if state.bossRoundsEnabled then
		if state.round == 1 then
			-- BUGFIX (Ahmed's playtest): pass state.night so BossRounds.pick
			-- can gate out the brutal tier-3 modifiers (Lights Out, Stale
			-- Bread, ...) until Night 6+ -- see BossRounds.lua's header
			-- comment. Previously this picked uniformly across ALL 24
			-- modifiers regardless of Night, so a run-ending "1 hand only"
			-- boss was exactly as likely on Night 1 as Night 10.
			-- (a Quick Run picks by the full-run Night its Night is scored like, see Engine/RunModes.lua)
			local bossNight = state.quickRun and math.floor(RunModes.equivalentNight("quick", state.night)) or state.night
			state.bossesFaced = state.bossesFaced or {} -- ids met this run: a Night never repeats an earlier boss while fresh ones remain
			state.nightBossModifier = BossRounds.pick(state.rng, bossNight, state.bossesFaced, state.config.nightCap)
			if state.nightBossModifier then table.insert(state.bossesFaced, state.nightBossModifier.id) end
			if state.nightBossModifier and state.night >= state.config.nightCap then state.finalBoss = state.nightBossModifier end -- the last Night's boss, named on the win screen
		end
	else
		state.nightBossModifier = nil
	end

	-- CROWD RULES: recomputed every round from the Night (nil when off), plus the rule that joins this Night.
	if state.endlessRulesEnabled then
		state.endlessRules = EndlessRules.combined(EndlessRules.activeFor(state.night, state.config.nightCap))
		state.endlessNewRule = EndlessRules.newAt(state.night, state.config.nightCap)
	else
		state.endlessRules, state.endlessNewRule = nil, nil
	end
	state.isBossRound = BossRounds.isBossRound(state.round, state.config.roundsPerNight)
	local isBoss = state.bossRoundsEnabled and state.isBossRound
	-- RULE BAN (RunState.useRuleBan): a banned boss fights with no rule this round (the Night's base target still applies)
	state.bossModifier = isBoss and state.bannedBossNight ~= state.night and state.nightBossModifier or nil
	local bossModifier = state.bossModifier

	-- ROUND SELECT FEATURE: a fresh Tag for whichever round we're now on,
	-- IF it's skippable (see RunState.canSkipRound -- the last round of a
	-- Night is never skippable, independent of bossRoundsEnabled). Picked
	-- here so it's already known -- and can be shown on the Round Select
	-- screen -- before the player ever acts on this round.
	if state.round < state.config.roundsPerNight then
		state.currentRoundSkipTag = Tags.pick(state.rng)
	else
		state.currentRoundSkipTag = nil
	end

	local handSize = state.config.handSize + ((bossModifier and bossModifier.handSizeDelta) or 0)
		+ Patrons.sum(state.ownedPatrons, "handSizeDelta") -- Extra Chair, Overtime
		+ (state.housePasses.card_cart and 1 or 0) -- Card Cart
		+ endlessField(state, "handSizeDelta")
		+ Strangers.field(state, "handSizeDelta")
		+ NightBoons.field(state, "handSize")
	handSize = math.max(5, handSize) -- never fewer than 5 cards
	-- Late Kitchen House Pass: +1 Discard every round, permanent for the run.
	local discards = state.config.discardsPerRound + ((bossModifier and bossModifier.discardsDelta) or 0)
		+ (state.housePasses.late_kitchen and 1 or 0)
		+ Patrons.sum(state.ownedPatrons, "discardsDelta") -- Second Helpings
		+ endlessField(state, "discardsDelta")
		+ Strangers.field(state, "discardsDelta")
		+ (state.night == 1 and state.nightOneBonusDiscards or 0)
		+ NightBoons.field(state, "discards") + NightBoons.field(state, "bossDiscards")
	if state.isBossRound and state.housePasses.boss_prep then
		discards = discards + 1 -- Boss Prep
	end
	if state.isBossRound then
		discards = discards + endlessField(state, "bossExtraDiscards")
	end
	if state.isBossRound and state.stakeRules then
		discards = discards + state.stakeRules.bossExtraDiscards -- Legend stake: a second small boss debuff
	end
	local discardsWithoutBoss = math.max(0, discards - ((bossModifier and bossModifier.discardsDelta) or 0))
	discards = math.max(0, discards)
	if bossModifier and bossModifier.minDiscards then
		-- Last Chance, Empty Handed: "only 1 discard" was none at all from the Busy Night stake up. The boss never
		-- takes the last discard. It never hands one out either: a round that has none without the boss (the No
		-- Discards Challenge Run) still has none.
		discards = math.max(discards, math.min(bossModifier.minDiscards, discardsWithoutBoss))
	end

	local handsPerRound = state.config.handsPerRound
	if bossModifier and bossModifier.handsPerRoundOverride then
		handsPerRound = bossModifier.handsPerRoundOverride
	end
	-- Double Shift House Pass: +1 Hand every round, permanent for the run --
	-- applies even on a Boss Round that overrides handsPerRound, same as
	-- everything else here layering on top of the boss's base number.
	handsPerRound = handsPerRound + (state.housePasses.double_shift and 1 or 0)
	handsPerRound = handsPerRound + Patrons.sum(state.ownedPatrons, "handsDelta") -- Overtime
	handsPerRound = handsPerRound + endlessField(state, "handsDelta")
	handsPerRound = handsPerRound + Strangers.field(state, "handsDelta")
	handsPerRound = handsPerRound + NightBoons.field(state, "hands") + NightBoons.field(state, "bossHands")
	-- Rest stop on the world map (Engine/SideStops.lua): +1 Hand for every round of the Night after the visit.
	if state.bonusHandsNight and state.bonusHandsNight == state.night then
		handsPerRound = handsPerRound + 1
	end
	handsPerRound = math.max(1, handsPerRound)

	state.hand = Deck.draw(state.deck, handSize)
	state.handsRemaining = handsPerRound
	state.discardsRemaining = discards
	-- BUGFIX (Ahmed's playtest, Night 4+): canSkipRound below used to compare
	-- state.handsRemaining/discardsRemaining against the STATIC
	-- state.config.handsPerRound/discardsPerRound -- but handsPerRound/
	-- discards just above already layer the Double Shift (+1 hand) and Late
	-- Kitchen (+1 discard) House Passes on top of that static config value.
	-- The moment either House Pass is bought, a freshly-started round's
	-- handsRemaining/discardsRemaining permanently never equal the static
	-- config numbers again, so canSkipRound returned false forever after --
	-- the Skip button silently vanished for the rest of the run even on a
	-- completely untouched round. Recording THIS round's real starting
	-- numbers here (after House Passes/boss overrides are applied) gives
	-- canSkipRound something that's actually still correct to compare
	-- against.
	state.roundStartHands = handsPerRound
	state.roundStartDiscards = discards
	state.roundScore = 0
	state.handTypesPlayedThisRound = {}
	state.brittleShieldRound = false -- "Sugar Shield" only protects for the round it was used in

	state.targetScore = RunState.targetForRound(state, state.round) -- one set of sums, shared with Round Select

	-- Cold Start Boss Round: Tips are lost as the round begins
	state.bossTipsLostAtStart = 0
	if bossModifier and bossModifier.tipsLostAtStart then
		local before = state.tips
		state.tips = math.max(0, state.tips - bossModifier.tipsLostAtStart)
		state.bossTipsLostAtStart = before - state.tips -- a Rule Ban refunds exactly this
	end

	state.roundOver = false
	state.roundStartSnapshot = copyForSnapshot(state)
end

-- Applies Golden Garnish (+3 Tips) and Blue Stamp (creates a Menu Recipe
-- for the hand that just won) for every card still held at round-end.
-- `lastHandName` is the poker hand that won the round.
local function settleHeldCardsAtRoundEnd(state, lastHandName)
	for _, card in ipairs(state.hand) do
		local garnish = card.garnish and Card.Garnishes[card.garnish]
		if garnish and garnish.heldEndOfRoundTips then
			state.tips = state.tips + garnish.heldEndOfRoundTips
		end
		local stamp = card.stamp and Card.Stamps[card.stamp]
		if stamp and stamp.createsMenuRecipeIfHeld and lastHandName then
			-- RECIPE CAP (genre parity, "fixed cap ~2" consumable slots):
			-- a passive reward like this can't prompt the player to make
			-- room, so it silently does nothing once the shared recipe box
			-- (RunState.recipeSlotLimit, House+Menu+Secret combined) is
			-- full -- same "skip, don't crash or overfill" precedent
			-- already used for a Patron pick landing on a full table (see
			-- RunState.resolvePack).
			if totalHeldRecipes(state) < RunState.recipeSlotLimit(state) then
				local recipe = Recipes.randomMenuRecipeForHand(lastHandName)
				if recipe then
					table.insert(state.menuRecipeInventory, recipe.id)
				end
			end
		end
	end
end

-- Re-takes the One More Round snapshot of the current round start, after a start-of-run or between-Nights choice
-- (Engine/RunChoice.lua) changed the run, so a continue does not undo the pick.
function RunState.refreshSnapshot(state)
	state.roundStartSnapshot = copyForSnapshot(state)
end

-- True on the last round of every Night on every difficulty (see the
-- isBossRound state field). Also true for any state with a bossModifier
-- set directly, so hand-built test states keep working.
function RunState.isBossRound(state)
	return state.bossModifier ~= nil or state.isBossRound == true
end

-- What scaling Patrons may read about the run so far, as of BEFORE the hand
-- being scored. The server ships this table to the client (serializeState),
-- and playHand and the client's computeHandPreview both feed it through
-- addRunCounters, so the preview and the real score can't disagree.
function RunState.runCounters(state)
	local handStatsBefore = {}
	for handName, count in pairs(state.handStats) do
		handStatsBefore[handName] = count
	end
	return {
		roundsCleared = state.roundsCleared,
		bossesCleared = state.bossesCleared,
		handsPlayedTotal = state.handsPlayedTotal,
		discardsUsedTotal = state.discardsUsedTotal,
		patronsSold = state.patronsSold,
		boonsPicked = state.boonsPicked or 0,
		handStatsBefore = handStatsBefore,
	}
end

-- Copies a runCounters table's fields into a Scoring.calculate context.
function RunState.addRunCounters(context, counters)
	for key, value in pairs(counters or {}) do
		context[key] = value
	end
	return context
end

-- Draws `count` cards. If the draw pile runs dry mid-round, shuffles the
-- discard pile back in and keeps drawing, so a round can never run out of
-- cards while any exist in the run. (Before this, the discard pile was only
-- pooled back at startRound, and a long round -- e.g. Rowdy Crowd's forced
-- discards plus extra hands/discards -- could empty the hand and soft-lock.)
local function drawCards(state, count)
	local drawn = Deck.draw(state.deck, count)
	if #drawn < count and #state.discardPile > 0 then
		for _, card in ipairs(state.discardPile) do
			card.usedAs = nil
			table.insert(state.deck, card)
		end
		state.discardPile = {}
		Deck.shuffle(state.deck, state.rng)
		for _, card in ipairs(Deck.draw(state.deck, count - #drawn)) do
			table.insert(drawn, card)
		end
	end
	return drawn
end

-- Whether the current hand can make any legal play at all.
function RunState.hasLegalPlay(state)
	if #state.hand == 0 then
		return false
	end
	local required = state.bossModifier and state.bossModifier.requiredCardsPerHand
	if required and #state.hand < required then
		return false
	end
	return true
end

-- THE PLAY REPORT (state.lastPlay): what a played hand really scored, entry by entry, as plain data the server can
-- send. The client's score reveal plays this, so a lucky hit, a shattered card or a Bargain on screen is always the
-- one the server rolled, never a second roll made on the client. Cards are named by position, not by table:
--   source.played = position among the played cards (hand order), source.held = position among the cards kept in hand.
--   { seq, handName, chips, mult, score, entries = { { kind, amount, label, source = { type, played, held, patronId, bond } } },
--     broken = { played positions that shattered }, wildcard = { rank, suit } or nil }
-- seq goes up by one per played hand, so the client can tell a new report from the one it has already shown.
local function buildPlayReport(previous, handResult, playedCards, heldCards, chips, mult, score, extra, wildcardResolution)
	local playedAt, heldAt = {}, {}
	for i, card in ipairs(playedCards) do
		playedAt[card] = i
	end
	for i, card in ipairs(heldCards) do
		heldAt[card] = i
	end
	local entries = {}
	for _, entry in ipairs(extra and extra.breakdown or {}) do
		local source = entry.source or {}
		entries[#entries + 1] = {
			kind = entry.kind, amount = entry.amount, label = entry.label,
			source = {
				type = source.type,
				played = source.card and playedAt[source.card] or nil,
				held = source.card and heldAt[source.card] or nil,
				patronId = source.patronId,
				bond = source.bond,
				set = source.set,
			},
		}
	end
	local broken = {}
	for _, card in ipairs(extra and extra.brokenCards or {}) do
		if playedAt[card] then
			broken[#broken + 1] = playedAt[card]
		end
	end
	return {
		seq = (previous and previous.seq or 0) + 1,
		handName = handResult.name, chips = chips, mult = mult, score = score,
		entries = entries, broken = broken, wildcard = wildcardResolution,
	}
end

-- TRANSACTION SAFETY: playHand and discard change a dozen fields (the hand, the counters, Tips, the wildcard lock)
-- before the last Patron effect has run. If anything in between throws, the run must not be left half played (cards
-- gone from the hand but never scored, a hand spent for nothing). So both run against a copy: on an error the state
-- table is put back exactly as it was and the error is raised again for the caller to log. The rng is not rewound.
local function transact(state, action, cardIndices)
	local before = copyForSnapshot(state)
	local ok, result = pcall(action, state, cardIndices)
	if ok then
		return result
	end
	local roundStart = state.roundStartSnapshot
	for key in pairs(state) do
		state[key] = nil
	end
	for key, value in pairs(before) do
		state[key] = value
	end
	state.roundStartSnapshot = roundStart
	error(result, 0)
end

local function removeIndicesFromHand(state, indices)
	-- indices: array of 1-based positions into state.hand, must be unique.
	local indexSet = {}
	for _, i in ipairs(indices) do
		indexSet[i] = true
	end
	local played, kept = {}, {}
	for i, card in ipairs(state.hand) do
		if indexSet[i] then
			table.insert(played, card)
		else
			table.insert(kept, card)
		end
	end
	state.hand = kept
	return played
end

--[[
	Play 1-5 cards from the hand (by 1-based index into state.hand) -- or
	exactly however many a Boss Round's requiredCardsPerHand demands.
	Returns a result table: { handName, score, chips, mult, roundWon, runOver, wonRun }
]]
-- Hand cards, Play and Discard only respond during an active round. Server
-- and client both gate on this so e.g. the Round Select screen can never
-- leak clicks through to the hand underneath.
-- Deck viewer payload ("Your Deck"): one entry per card still in the run's
-- deck, with where it is right now: "draw" (draw pile), "hand", "played" or
-- "discarded" (both sit in the discard pile; playHand tags `usedAs`).
-- Only membership is exposed: entries are sorted by suit then rank, never in
-- draw order. The hidden True Wildcard (not locked in yet) has no rank/suit
-- (hidden = true) so it can't be read off the payload.
local VIEW_SUIT_ORDER = { Spades = 1, Hearts = 2, Clubs = 3, Diamonds = 4 }
function RunState.deckView(state)
	local entries = {}
	local function add(card, status)
		local entry = { status = status }
		if card.isTrueWildcard and not card.wildcardLocked then
			entry.hidden = true
		else
			entry.rank = card.rank
			entry.suit = card.suit
			entry.garnish = card.garnish
			entry.special = card.special
			entry.stamp = card.stamp
			entry.mark = card.mark
		end
		table.insert(entries, entry)
	end
	for _, card in ipairs(state.deck or {}) do add(card, "draw") end
	for _, card in ipairs(state.hand or {}) do add(card, "hand") end
	for _, card in ipairs(state.discardPile or {}) do
		add(card, card.usedAs == "played" and "played" or "discarded")
	end
	table.sort(entries, function(a, b)
		if (a.hidden == true) ~= (b.hidden == true) then
			return b.hidden == true -- hidden card sorts last
		end
		if a.hidden then
			return a.status < b.status
		end
		local sa, sb = VIEW_SUIT_ORDER[a.suit] or 9, VIEW_SUIT_ORDER[b.suit] or 9
		if sa ~= sb then return sa < sb end
		if a.rank ~= b.rank then return a.rank < b.rank end
		return a.status < b.status
	end)
	return entries
end

function RunState.phaseAllowsCardActions(phase)
	return phase == "playing"
end

-- Buy, Reroll, packs, House Passes and Next Round are only valid in the
-- "shop" phase (which only follows a PLAYED and cleared round; a skip goes
-- straight back to "roundSelect"). The server checks this on every shop remote.
function RunState.phaseAllowsShopActions(phase)
	return phase == "shop"
end

local function playHandNow(state, cardIndices)
	assert(not state.roundOver, "Round is already over, advance to the next round first")
	local bossModifier = state.bossModifier
	if bossModifier and bossModifier.requiredCardsPerHand then
		assert(#cardIndices == bossModifier.requiredCardsPerHand,
			"This Boss Round requires exactly " .. bossModifier.requiredCardsPerHand .. " cards")
	else
		assert(#cardIndices >= 1 and #cardIndices <= 5, "Play between 1 and 5 cards")
	end
	local minCards = BossRules.minCards(bossModifier) or BossRules.minCards(state.challenge)
	if minCards then
		assert(#cardIndices >= minCards, "This round needs at least " .. minCards .. " cards per hand")
	end
	assert(state.handsRemaining > 0, "No hands remaining this round")

	local playedCards = removeIndicesFromHand(state, cardIndices)

	-- PHASE C ("mind-blowing plan" Signature Mechanic): TRUE WILDCARD.
	-- The FIRST time the run's one True Wildcard card (see RunState.new)
	-- is actually played, lock it in as whichever of the 52 real rank/
	-- suit combinations scores the MOST for exactly this hand -- see
	-- TrueWildcard.findBestChoice's header for why the comparison itself
	-- stays deterministic (no lucky-garnish noise) even though the real
	-- hand below still scores with the run's real rng as always.
	-- wildcardLocked flips true right away, so every hand after this one
	-- just plays it as a normal card with its new permanent rank/suit.
	-- Client/init.client.lua's computeHandPreview runs this exact same
	-- search (and always restores afterward -- see findBestChoice's own
	-- comment) so the live preview/Play popup already shows the true
	-- number before this ever fires for real.
	local wildcardResolution = nil
	for _, card in ipairs(playedCards) do
		if card.isTrueWildcard and not card.wildcardLocked then
			local bossMod = state.bossModifier
			local bestRank, bestSuit = TrueWildcard.findBestChoice(playedCards, card, state.ownedPatrons, function(candidateHandResult)
				local blocked = bossMod and bossMod.noRepeatHandTypes
					and state.handTypesPlayedThisRound[candidateHandResult.name] == true
				if blocked then
					return nil
				end
				return RunState.addRunCounters({
					rng = Scoring.noLuck, -- which card it becomes never hangs on a Lucky roll (the preview picks the same way)
					allPlayedCards = playedCards,
					heldCards = state.hand, -- cards left in hand after removeIndicesFromHand, above
					handLevels = state.handLevels,
					ownedPatronSpecials = state.ownedPatronSpecials,
					brittleShielded = state.brittleShieldRound,
					debuff = bossMod and bossMod.debuff,
					firstCardOut = bossMod and bossMod.firstCardOut, patronChipsFactor = bossMod and bossMod.patronChipsFactor,
					tips = state.tips,
					alreadyPlayedThisHandTypeThisRound = state.handTypesPlayedThisRound[candidateHandResult.name] == true,
					handsRemaining = math.max(0, state.handsRemaining - 1),
					discardsRemaining = state.discardsRemaining,
					isLastHand = state.handsRemaining - 1 <= 0,
					night = state.night,
					round = state.round,
				}, RunState.runCounters(state))
			end)
			card.rank = bestRank
			card.suit = bestSuit
			card.wildcardLocked = true
			wildcardResolution = { rank = bestRank, suit = bestSuit }
			break -- only one True Wildcard card can ever exist in a run
		end
	end

	local handResult = HandEvaluator.evaluate(playedCards)

	-- Was this exact hand type already played earlier this round? Captured
	-- BEFORE marking it played below -- used by the "No Repeats" Boss
	-- Round (blocks scoring) and the "Repeat Customer" Patron (rewards it).
	local alreadyPlayedThisHandTypeThisRound = state.handTypesPlayedThisRound[handResult.name] == true
	local blockedRepeatHand = bossModifier and bossModifier.noRepeatHandTypes
		and alreadyPlayedThisHandTypeThisRound
	state.handTypesPlayedThisRound[handResult.name] = true

	-- Snapshot before this hand counts toward anything, matching what the
	-- client's preview sees.
	local runCounters = RunState.runCounters(state)

	state.handStats[handResult.name] = (state.handStats[handResult.name] or 0) + 1

	-- "Empty Pockets" Boss Round: playing your most-used hand type wipes
	-- your Tips right away, before the hand scores. The rule lives in
	-- BossRules.wipesTips so the hand preview (Engine/HandPreview) applies it too.
	if BossRules.wipesTips(bossModifier, runCounters.handStatsBefore, handResult.name) then
		state.tips = 0
	end

	state.handsRemaining = state.handsRemaining - 1
	local isLastHand = state.handsRemaining == 0

	local score, chips, mult, extra = 0, 0, 0, { tipsEarned = 0, brokenCards = {} }
	-- Boss Round / Challenge rules that make this hand type score nothing (Pair Patrol, Picky Eater, Pairs Only)
	local blockedByRule = BossRules.blocksHand(handResult.name, bossModifier, state.challenge)
	if not (blockedRepeatHand or blockedByRule) then
		score, chips, mult, extra = Scoring.calculate(handResult, BossRules.scoringPatrons(bossModifier, state.ownedPatrons), RunState.addRunCounters({
			patronPower = (state.challenge and state.challenge.patronPower) or (state.dailyModifier and state.dailyModifier.patronPower),
			allPlayedCards = playedCards,
			heldCards = state.hand, -- cards left in hand, not played -- Iron Garnish reads this
			rng = state.rng, -- a seeded run (Daily, Weekly, Seed) rolls its luck from its own stream, never the shared math.random
			handLevels = state.handLevels,
			ownedPatronSpecials = state.ownedPatronSpecials, -- Silver/Gold/Rainbow on a Patron
			brittleShielded = state.brittleShieldRound, -- "Sugar Shield" Secret Recipe
			debuff = bossModifier and bossModifier.debuff,
			firstCardOut = bossModifier and bossModifier.firstCardOut, patronChipsFactor = bossModifier and bossModifier.patronChipsFactor, -- Frozen Hand, Quiet Tavern
			tips = state.tips, -- Tips held BEFORE this hand's reward -- Penny Pincher/Tab Regulars read this
			alreadyPlayedThisHandTypeThisRound = alreadyPlayedThisHandTypeThisRound, -- Repeat Customer reads this
			handsRemaining = state.handsRemaining,
			discardsRemaining = state.discardsRemaining,
			isLastHand = isLastHand,
			night = state.night,
			round = state.round,
		}, runCounters))
		if (bossModifier and bossModifier.noScoringTips) or (state.challenge and state.challenge.noScoringTips) then
			extra.tipsEarned = 0 -- Penny Wise
		end
		-- boss Chips and Mult factors, Sleepy Cook's first hand, the Dealer's Bargain: one shared function with the preview
		chips, mult, score = BossRules.finishScore(chips, mult, bossModifier, state.handsRemaining + 1 == state.roundStartHands,
			Strangers.field(state, "scorePct") + NightBoons.scorePct(state, state.handsRemaining + 1 == state.roundStartHands))
	end

	-- What this hand really did, as plain data for the client's score reveal (cards by position, no table references).
	-- Built now, while state.hand is still exactly the held cards: the draw and any thrown card come after.
	state.lastPlay = buildPlayReport(state.lastPlay, handResult, playedCards, state.hand, chips, mult, score, extra, wildcardResolution)

	state.handsPlayedTotal = state.handsPlayedTotal + 1
	if score >= 500 then
		state.bigHands = (state.bigHands or 0) + 1 -- daily quest: score 500 in one hand
	end
	RunSummary.recordHand(state, handResult.name, score) -- best hand + Patrons used, for the end-of-run summary
	require(script.Parent.NightStar).record(state, extra and extra.breakdown, chips, mult) -- the Night clear toast names the best card or Patron
	state.roundScore = math.min(EndlessRules.TARGET_CAP, state.roundScore + (score == score and score or 0)) -- finite and capped, so no display or compare ever sees inf or NaN
	state.tips = state.tips + (extra.tipsEarned or 0)
	state.tipsEarnedTotal = (state.tipsEarnedTotal or 0) + math.max(0, extra.tipsEarned or 0) -- Tavern Stats: lifetime Tips earned

	-- Brittle Garnish cards that shattered leave the run's card pool for
	-- good -- everything else goes to the discard pile to reshuffle back
	-- in next round (see RunState.startRound).
	local brokenSet = {}
	for _, card in ipairs(extra.brokenCards or {}) do
		brokenSet[card] = true
	end
	-- Refill hand from the deck. Drawn BEFORE the played cards go to the
	-- discard pile, so a mid-round reshuffle (see drawCards) can't hand you
	-- straight back the cards you just played.
	local drawn = drawCards(state, #playedCards)
	for _, card in ipairs(drawn) do
		table.insert(state.hand, card)
	end

	-- Glass Deck challenge: played cards may break and leave the run for good (never below a minimum deck size).
	local glassChance = state.challenge and state.challenge.glassChance
	if glassChance then
		local rng = state.rng or math.random
		local remaining = #state.deck + #state.discardPile + #state.hand + #playedCards
		for _, card in ipairs(playedCards) do
			if not brokenSet[card] and remaining > Challenges.GLASS_MIN_CARDS and rng(100) <= glassChance then
				brokenSet[card] = true
				remaining = remaining - 1
				state.glassBroken = (state.glassBroken or 0) + 1
			end
		end
	end

	for _, card in ipairs(playedCards) do
		if not brokenSet[card] then
			card.usedAs = "played" -- lets the Deck viewer tell played from discarded
			table.insert(state.discardPile, card)
		end
	end

	-- "The Tab" Boss Round: lose Tips for every card played.
	if bossModifier and bossModifier.tipsLostPerCardPlayed then
		state.tips = math.max(0, state.tips - bossModifier.tipsLostPerCardPlayed * #playedCards)
	end

	-- "Rowdy Crowd" Boss Round: toss out extra random held cards after
	-- every hand played (a penalty, doesn't cost a Discard).
	if bossModifier and bossModifier.forcedRandomDiscardsPerHand and #state.hand > 0 then
		local rng = state.rng or math.random
		for _ = 1, bossModifier.forcedRandomDiscardsPerHand do
			if #state.hand > 0 then
				local thrown = table.remove(state.hand, rng(#state.hand))
				for _, card in ipairs(drawCards(state, 1)) do
					table.insert(state.hand, card)
				end
				table.insert(state.discardPile, thrown)
			end
		end
	end

	local roundWon = state.roundScore >= state.targetScore
	if roundWon then
		state.roundOver = true
		state.roundsCleared = state.roundsCleared + 1
			if handResult.name == "Flush" or handResult.name == "Straight Flush" then
				state.flushClears = (state.flushClears or 0) + 1 -- daily quest: clear a round with a Flush
			end
			-- daily quests: clear with 3+ Tips in hand, clear using 2 or fewer hands
			if state.tips >= 3 then
				state.richClears = (state.richClears or 0) + 1
			end
			if (state.roundStartHands or 0) - state.handsRemaining <= 2 then
				state.quickClears = (state.quickClears or 0) + 1
			end
		if RunState.isBossRound(state) then
			state.bossesCleared = state.bossesCleared + 1
			if state.ruleBansEnabled and state.night == Stakes.RULE_BAN_BONUS_NIGHT then
				state.ruleBans = (state.ruleBans or 0) + 1 -- clearing the Night 4 boss earns one more Rule Ban
			end
		end
		local tipsBeforeRoundEndRewards = state.tips
		settleHeldCardsAtRoundEnd(state, handResult.name)
		for _, patron in ipairs(state.ownedPatrons) do
			if patron.onRoundWin then
				patron.onRoundWin(state)
			end
		end

		-- GENRE PARITY: round-win interest is now a universal base rule
		-- (+1 Tip per 5 held, capped at +5) instead of something you had to
		-- buy the Nest Egg Patron for. See Patrons.lua's "nest_egg" entry
		-- for why it was reworked to raise this cap to +10 instead of
		-- keeping its own onRoundWin doing the identical math -- that would
		-- have silently double-dipped once this base rule shipped.
		local interestCap = 5 + (state.housePasses.savings_account and 3 or 0) -- Savings Account
		for _, patron in ipairs(state.ownedPatrons) do
			if patron.id == "nest_egg" then
				interestCap = 10 + (state.housePasses.savings_account and 3 or 0)
				break
			end
		end
		interestCap = math.max(0, interestCap + endlessField(state, "interestCapDelta")) -- Thin Interest
		if not (state.stakeRules and state.stakeRules.noInterest) then -- Final Bell stake: no interest
			local interest = BossRules.applyPercent(math.min(interestCap, math.floor(state.tips / 5)), BossRules.tipsPercent(state.challenge, state.dailyModifier))
			state.tips = state.tips + interest
			state.lastInterest = interest -- first time hints: "interest paid" (Engine/Hints.lua)
			state.tipsEarnedTotal = (state.tipsEarnedTotal or 0) + math.max(0, interest)
		end

		-- GENRE PARITY: clearing the Boss Round of the final capped Night
		-- (nightCap, 8 -- the genre's usual run length) marks the run WON. Nothing
		-- else changes here -- state.night keeps climbing exactly like it
		-- already did before this existed, so you're now in Endless Mode
		-- (see RunState.blindMultiplierFor/targetScoreFor). This can only
		-- ever go true once a run: state.night only ever increases, so
		-- night == nightCap is never true again after this Night ends.
		-- BUGFIX (balance pass): was `state.bossModifier and ...`, which is
		-- nil on Casual (no Boss modifiers), so Casual runs could never be
		-- won. RunState.isBossRound works on every difficulty.
		if RunState.isBossRound(state) and state.night == state.config.nightCap then
			state.wonRun = true
		end

		-- Clearing a Boss Round pays double -- it's the harder ask each Night.
		local reward = math.max(1, state.config.tipsPerRoundWin + (state.housePasses.tip_stand and 1 or 0) + endlessField(state, "tipsDelta") + Strangers.field(state, "tipsDelta")) -- Tip Stand, Lean Tips, Dealer's Bargain
		if RunState.isBossRound(state) then
			reward = reward + state.config.tipsPerRoundWin
		else
			reward = math.max(1, reward + (state.config.tipsNonBossDelta or 0)) -- Closing Time (stake 7): non-boss rounds only
		end
		-- PHASE 15: "Bedtime Bonus" (Secret Recipe) sets this one-shot flag
		-- to double whatever reward THIS round-win was already going to pay
		-- (stacks on top of a Boss Round's own double, rather than
		-- replacing it) -- cleared immediately after, so it only ever
		-- applies to the next single round win, never lingers.
		if state.bedtimeBonusActive then
			reward = reward * 2
			state.bedtimeBonusActive = false
		end
		reward = BossRules.applyPercent(reward, BossRules.tipsPercent(state.challenge, state.dailyModifier)) -- Tight Wallet
		state.tips = state.tips + reward
		state.tipsEarnedTotal = (state.tipsEarnedTotal or 0) + math.max(0, reward)

		-- Actual total Tips gained this round-win (flat reward + boss
		-- double + every Patron onRoundWin bonus + the interest above) --
		-- lets the client show the real number instead of independently
		-- re-deriving just the flat/boss-doubled part, which under-reports
		-- Patron bonuses and interest (see RoundRewardPopup's
		-- showRoundReward caller in init.client.lua).
		state.lastRoundReward = state.tips - tipsBeforeRoundEndRewards
	elseif isLastHand then
		-- Out of hands and didn't reach the target: the run ends. NOTE:
		-- deliberately NOT touching state.wonRun here -- if it's already
		-- true (this run already cleared Night nightCap earlier and is now
		-- losing during Endless Mode), losing later doesn't erase having
		-- already won, same as the reference game. It only ever starts
		-- false and flips true above, so there's nothing stale to clear.
		state.roundOver = true
		state.runOver = true
	end

	-- Last-resort soft-lock guard (see drawCards / hasLegalPlay): a round
	-- that's still going but has no legal play ends the run instead of
	-- hanging. Only reachable if the run has fewer cards than a hand needs.
	local softLocked = false
	if not state.roundOver and state.handsRemaining > 0 and not RunState.hasLegalPlay(state) then
		state.roundOver = true
		state.runOver = true
		softLocked = true
	end

	return {
		softLocked = softLocked,
		handName = handResult.name,
		score = score,
		chips = chips,
		mult = mult,
		roundScore = state.roundScore,
		targetScore = state.targetScore,
		roundWon = roundWon,
		runOver = state.runOver,
		wonRun = state.wonRun,
		blockedRepeatHand = blockedRepeatHand or false,
		bossModifierId = state.bossModifier and state.bossModifier.id or nil,
		wildcardResolution = wildcardResolution,
	}
end

function RunState.playHand(state, cardIndices)
	return transact(state, playHandNow, cardIndices)
end

-- Discard 1-5 cards from the hand and draw replacements.
local function discardNow(state, cardIndices)
	assert(not state.roundOver, "Round is already over")
	assert(#cardIndices >= 1 and #cardIndices <= 5, "Discard between 1 and 5 cards")
	assert(state.discardsRemaining > 0, "No discards remaining this round")

	local discarded = removeIndicesFromHand(state, cardIndices)
	state.discardsRemaining = state.discardsRemaining - 1
	state.discardsUsedTotal = state.discardsUsedTotal + 1
	state.cardsDiscarded = (state.cardsDiscarded or 0) + #cardIndices -- daily quest: discard 10 cards

	-- Purple Stamp: discarding this card creates a random House Recipe.
	-- RECIPE CAP: same silent-skip-if-full rule as the Blue Stamp reward in
	-- settleHeldCardsAtRoundEnd -- see that function's comment.
	local rng = state.rng or math.random
	for _, card in ipairs(discarded) do
		local stamp = card.stamp and Card.Stamps[card.stamp]
		if stamp and stamp.createsHouseRecipeOnDiscard and totalHeldRecipes(state) < RunState.recipeSlotLimit(state) then
			table.insert(state.houseRecipeInventory, Recipes.randomHouseRecipeId(rng))
		end
	end

	local drawn = drawCards(state, #discarded)
	for _, card in ipairs(drawn) do
		table.insert(state.hand, card)
	end

	for _, card in ipairs(discarded) do
		table.insert(state.discardPile, card)
	end

	-- Last-resort guard: only reachable if the whole run has fewer cards
	-- than a hand needs. End the run instead of leaving it unplayable.
	if state.handsRemaining > 0 and not RunState.hasLegalPlay(state) then
		state.roundOver = true
		state.runOver = true
		return { discarded = #discarded, discardsRemaining = state.discardsRemaining, runOver = true, softLocked = true }
	end

	return { discarded = #discarded, discardsRemaining = state.discardsRemaining }
end

-- How many Patrons can currently sit at the table: the base config value,
-- plus 1 for every owned Patron carrying a Reserved Special (see Card.lua),
-- plus 1 more if the Extra Seating House Pass has been bought this run.
function RunState.patronSlotLimit(state)
	local bonus = 0
	for _, patron in ipairs(state.ownedPatrons) do
		if state.ownedPatronSpecials[patron.id] == "reserved" then
			bonus = bonus + 1
		end
	end
	if state.housePasses.extra_seating then
		bonus = bonus + 1
	end
	return state.config.patronSlotLimit + bonus
end

-- GENRE PARITY: how many Recipes (House+Menu+Secret combined -- one
-- shared "recipe box") can be held at once. A plain wrapper today (no
-- bonus sources yet), kept as its own function -- like patronSlotLimit --
-- so a future Recipe-slot-raising House Pass/Special has one obvious place
-- to hook into instead of every call site re-reading state.config directly.
function RunState.recipeSlotLimit(state)
	return math.max(0, state.config.recipeSlotLimit + (state.housePasses.pantry_shelf and 1 or 0) + endlessField(state, "recipeSlotDelta")) -- Pantry Shelf, Packed Shelf
end

function RunState.discard(state, cardIndices)
	return transact(state, discardNow, cardIndices)
end

-- What a Patron actually costs THIS player right now -- the Regulars'
-- Discount House Pass and a "Sale Day Tag" (see Tags.lua/
-- state.nextShopDiscount) both knock Tips off. Shop offer prices are
-- computed with this (server-side, in serializeState) so the client never
-- needs to duplicate the discount math -- it just displays whatever price
-- it was sent. Both discounts are combined BEFORE clamping to a 1-Tip
-- floor (not clamped one at a time) so stacking them never rounds more
-- generously than the sum of the two actually is.
function RunState.patronPrice(state, patron)
	local price = patron.price
	if state.housePasses.regulars_discount then
		price = price - 2
	end
	price = price - (state.nextShopDiscount or 0) - NightBoons.priceOff(state, "patron")
	price = math.max(1, price + Haggle.delta(state, "patron", patron.id))
	local pct = endlessField(state, "patronPricePct")
	if pct ~= 0 then
		price = math.ceil(price * (1 + pct / 100)) -- Pricey Patrons
	end
	return price
end

-- Same idea for Packs -- Wholesale Pricing + a Sale Day Tag both apply.
function RunState.packPrice(state, pack)
	local price = pack.price
	if state.housePasses.wholesale_pricing then
		price = price - 2
	end
	price = price - (state.nextShopDiscount or 0) - NightBoons.priceOff(state, "pack")
	return math.max(1, price + Haggle.delta(state, "pack", pack.id))
end

-- The Frequent Visitor Card House Pass knocks 2 off whatever the current
-- reroll cost is (never below 1). `baseCost` is the session's running
-- reroll price (it climbs each reroll within a shop visit -- see the
-- server) -- this just applies the discount on top of it.
function RunState.rerollCost(state, baseCost)
	local cost = baseCost
	if state.housePasses.frequent_visitor then
		cost = cost - 2
	end
	cost = cost + Patrons.sum(state.ownedPatrons, "rerollDelta") -- Bargain Hunter
	if state.stakeRules then
		cost = cost + state.stakeRules.rerollExtra -- Rush Hour stake
	end
	cost = cost + endlessField(state, "rerollExtra") -- Costly Rerolls
	if NightBoons.freeRerollReady(state) then
		return 0 -- Free Reroll Night boon
	end
	return math.max(1, cost)
end

-- Spend tips on a patron from the shop. Returns true/false, message.
function RunState.buyPatron(state, patronId)
	local patron = Patrons.getById(patronId)
	if not patron then
		return false, "Unknown patron: " .. tostring(patronId)
	end
	if #state.ownedPatrons >= RunState.patronSlotLimit(state) then
		return false, "Your table is full, sell a Patron to make room"
	end
	local price = RunState.patronPrice(state, patron)
	if state.tips < price then
		return false, "Not enough tips"
	end
	state.tips = state.tips - price
	table.insert(state.ownedPatrons, patron)
	return true, patron.name .. " joins your table."
end

-- Seats a Patron for free (the start-of-run draft, Engine/RunChoice.lua). Same limits as buying: no duplicates, a free seat.
function RunState.grantPatron(state, patronId)
	local patron = Patrons.getById(patronId)
	if not patron then
		return false, "Unknown patron: " .. tostring(patronId)
	end
	for _, owned in ipairs(state.ownedPatrons) do
		if owned.id == patron.id then
			return false, "Already at your table"
		end
	end
	if #state.ownedPatrons >= RunState.patronSlotLimit(state) then
		return false, "Your table is full"
	end
	table.insert(state.ownedPatrons, patron)
	return true, patron.name .. " joins your table."
end

-- Spend tips on a House Pass from the shop's occasional Voucher slot.
-- Permanent for the rest of the run -- see HousePasses.lua for what each
-- one does and which RunState helper reads it.
function RunState.buyHousePass(state, passId)
	local pass = HousePasses.getById(passId)
	if not pass then
		return false, "Unknown House Pass: " .. tostring(passId)
	end
	if state.housePasses[passId] then
		return false, "You already have that House Pass"
	end
	if state.tips < pass.price then
		return false, "Not enough tips"
	end
	state.tips = state.tips - pass.price
	state.housePasses[passId] = true
	state.housePassesBought = (state.housePassesBought or 0) + 1 -- daily quest: buy a House Pass
	if pass.onBuy then
		pass.onBuy(state)
	end
	return true, pass.name .. " is now permanent for this run."
end

-- `state` (optional) applies the unlock drip: a run with state.unlockedContent only reveals open Recipes.
local function recipeCatalogForCategory(category, state)
	local catalog
	if category == "house" then
		catalog = Recipes.HouseRecipes
	elseif category == "menu" then
		catalog = Recipes.MenuRecipes
	elseif category == "secret" then
		catalog = Recipes.SecretRecipes
	end
	if catalog and state then
		local open = Unlocks.filter(state, "recipe", catalog)
		if #open > 0 then
			return open
		end
	end
	return catalog
end

local function inventoryForCategory(state, category)
	if category == "house" then
		return state.houseRecipeInventory
	elseif category == "menu" then
		return state.menuRecipeInventory
	elseif category == "secret" then
		return state.secretRecipeInventory
	end
	return nil
end

-- Standard Packs (category = "standard") reveal actual playing cards with a
-- modifier already applied, instead of Patrons/Recipes -- picking one adds
-- that exact card to your run's card pool. Every Garnish/Special/Stamp that
-- makes sense on a random card is in this pool (Reserved is Patron-only, so
-- it's excluded); each is equally likely.
local STANDARD_MODIFIER_POOL = {
	{ kind = "garnish", id = "sweet" },
	{ kind = "garnish", id = "zesty" },
	{ kind = "garnish", id = "houseBlend" },
	{ kind = "garnish", id = "brittle" },
	{ kind = "garnish", id = "iron" },
	{ kind = "garnish", id = "houseToken" },
	{ kind = "garnish", id = "golden" },
	{ kind = "garnish", id = "lucky" },
	{ kind = "special", id = "silver" },
	{ kind = "special", id = "gold" },
	{ kind = "special", id = "rainbow" },
	{ kind = "stamp", id = "gold" },
	{ kind = "stamp", id = "encore" },
	{ kind = "stamp", id = "blue" },
	{ kind = "stamp", id = "purple" },
}

local function modifierDef(kind, id)
	if kind == "garnish" then
		return Card.Garnishes[id]
	elseif kind == "special" then
		return Card.Specials[id]
	elseif kind == "stamp" then
		return Card.Stamps[id]
	end
	return nil
end

-- Builds one random-rank/random-suit card with one random modifier applied,
-- as a Standard Pack reveal item. `id` is a synthetic per-reveal index (NOT
-- a catalog id -- Standard Pack cards aren't drawn from a fixed catalog like
-- Patrons/Recipes are), unique within this one reveal, which is all
-- resolvePack needs to match a chosen id back to its item. The `card` field
-- carries everything needed to instantiate the real Card.new(...) once
-- chosen -- see RunState.resolvePack's "standard" branch below.
local function randomStandardPackItem(rng, index)
	local rank = 1 + rng(13) -- rng(13) in [1,13] -> rank in [2,14]
	local suit = Card.Suits[rng(#Card.Suits)]
	local choice = STANDARD_MODIFIER_POOL[rng(#STANDARD_MODIFIER_POOL)]
	local def = modifierDef(choice.kind, choice.id)
	local cardSpec = { rank = rank, suit = suit }
	cardSpec[choice.kind] = choice.id
	return {
		id = tostring(index),
		name = string.format("%s of %s (%s)", Card.RankNames[rank], suit, def.name),
		icon = def.icon,
		description = def.description,
		card = cardSpec,
		category = "standard",
	}
end

--[[
	Buys a Pack (deducts its price, respecting Wholesale Pricing) and
	reveals `revealCount` random items from its category. Returns the
	reveal table (also stored as state.pendingPack) on success, or nil,
	message on failure. Nothing is granted yet -- that's resolvePack below,
	once the player picks which of the revealed items to keep.

	Only ONE pack can be open at a time (matches the client only ever
	showing one reveal panel) -- callers should check state.pendingPack is
	nil before calling this, same as the server's BuyPackRemote does.

	`items` are lightweight display copies { id, name, icon, description },
	not the real Patron/Recipe tables, so nothing is granted just by being
	revealed. Standard Pack items additionally carry a `card` field (see
	randomStandardPackItem above) -- still nothing is granted/mutated until
	resolvePack.
]]
function RunState.openPack(state, packId, rng)
	local pack = Packs.getById(packId)
	if not pack then
		return nil, "Unknown pack: " .. tostring(packId)
	end
	local price = RunState.packPrice(state, pack)
	if state.tips < price then
		return nil, "Not enough tips"
	end

	rng = rng or state.rng or math.random
	local items = {}

	if pack.category == "patron" then
		local available = {}
		for _, patron in ipairs(Unlocks.filter(state, "patron", Patrons.Definitions)) do
			local owned = false
			for _, o in ipairs(state.ownedPatrons) do
				if o.id == patron.id then
					owned = true
					break
				end
			end
			if not owned then
				table.insert(available, patron)
			end
		end
		for _ = 1, math.min(pack.revealCount, #available) do
			local picked = table.remove(available, rng(#available))
			table.insert(items, { id = picked.id, name = picked.name, icon = picked.icon, description = picked.description, category = "patron" })
		end
	elseif pack.category == "standard" then
		for i = 1, pack.revealCount do
			table.insert(items, randomStandardPackItem(rng, i))
		end
	elseif pack.category == "mixed" then
		-- Grab Bag Packs: EACH revealed item independently rolls its own
		-- random category (Patron, one of the 3 Recipe types, or a
		-- Standard-Pack-style card), instead of a pack committing to one
		-- category up front. `availablePatrons` is built once and shared
		-- across iterations so a "patron" roll never reveals the same
		-- Patron twice in one pack, same as the pure Buffoon Pack branch
		-- above; if every Patron is already owned/exhausted mid-reveal, a
		-- "patron" roll falls back to "standard" instead of producing
		-- nothing.
		local availablePatrons = {}
		for _, patron in ipairs(Unlocks.filter(state, "patron", Patrons.Definitions)) do
			local owned = false
			for _, o in ipairs(state.ownedPatrons) do
				if o.id == patron.id then
					owned = true
					break
				end
			end
			if not owned then
				table.insert(availablePatrons, patron)
			end
		end
		local subcategories = { "patron", "house", "menu", "secret", "standard" }
		for i = 1, pack.revealCount do
			local sub = subcategories[rng(#subcategories)]
			if sub == "patron" and #availablePatrons == 0 then
				sub = "standard"
			end
			if sub == "patron" then
				local picked = table.remove(availablePatrons, rng(#availablePatrons))
				table.insert(items, { id = picked.id, name = picked.name, icon = picked.icon, description = picked.description, category = "patron" })
			elseif sub == "standard" then
				table.insert(items, randomStandardPackItem(rng, i))
			else
				local catalog = recipeCatalogForCategory(sub, state)
				local picked = catalog[rng(#catalog)]
				table.insert(items, { id = picked.id, name = picked.name, icon = picked.icon, description = picked.description, category = sub })
			end
		end
	else
		local catalog = recipeCatalogForCategory(pack.category, state)
		for _ = 1, pack.revealCount do
			local picked = catalog[rng(#catalog)]
			table.insert(items, { id = picked.id, name = picked.name, icon = picked.icon, description = picked.description, category = pack.category })
		end
	end

	state.tips = state.tips - price
	state.packsBought = (state.packsBought or 0) + 1 -- daily quest: buy a pack
	state.pendingPack = {
		packId = packId,
		category = pack.category,
		pickCount = math.min(pack.pickCount, #items),
		items = items,
		paidPrice = price, -- what was actually paid after discounts: Skip Pack gives half of it back (Packs.skipRefund)
	}
	return state.pendingPack
end

--[[
	Resolves the currently open pack (state.pendingPack). `chosenIds` is a
	list of item ids from the reveal -- either exactly `pickCount` of them
	(to keep those), or an empty list to skip the pack entirely (you keep
	nothing, and you get about half of what you paid back: Packs.skipRefund of
	state.pendingPack.paidPrice, never more than the price paid). Returns true/false, message[, Tips back].

	Granting a chosen Patron silently no-ops (instead of failing the whole
	resolve) if the table's already full by the time you confirm -- you
	still keep whatever OTHER picks fit, and you don't lose the pack you
	already paid for over one pick not landing.
]]
function RunState.resolvePack(state, chosenIds, replaceIds)
	local pending = state.pendingPack
	if not pending then
		return false, "No pack is open"
	end
	if type(chosenIds) ~= "table" then
		return false, "Invalid selection"
	end
	if #chosenIds ~= 0 and #chosenIds ~= pending.pickCount then
		return false, "Pick exactly " .. pending.pickCount .. " item(s), or none to skip"
	end

	-- Validate every chosen id against a shrinking copy of the revealed
	-- pool, so you can't pick more copies of an id than were actually
	-- revealed (packs can reveal the same Recipe id twice).
	local pool = {}
	for _, item in ipairs(pending.items) do
		table.insert(pool, item.id)
	end
	for _, chosenId in ipairs(chosenIds) do
		local foundAt = nil
		for i, poolId in ipairs(pool) do
			if poolId == chosenId then
				foundAt = i
				break
			end
		end
		if not foundAt then
			return false, "Invalid selection"
		end
		table.remove(pool, foundAt)
	end

	-- MAKE ROOM: a Patron pick with every seat full (or a recipe with the box full) is never silently lost. The player names which owned
	-- items leave (replaceIds, validated by Engine/PackRoom: owned, no duplicates, exactly the overflow); without them the pack stays open and
	-- the answer is "Make room first". Replaced items are sold at their normal sell value (half the price, rounded down).
	local function pickedItem(chosenId)
		for _, item in ipairs(pending.items) do
			if item.id == chosenId then
				return item
			end
		end
		return nil
	end
	local sold = 0
	if #chosenIds > 0 then
		local picked = {}
		for _, chosenId in ipairs(chosenIds) do
			picked[#picked + 1] = pickedItem(chosenId) or { category = pending.category }
		end
		local ownedIds, recipeIds = {}, {}
		for _, o in ipairs(state.ownedPatrons) do ownedIds[#ownedIds + 1] = o.id end
		for _, inv in ipairs({ state.houseRecipeInventory, state.menuRecipeInventory, state.secretRecipeInventory }) do
			for _, id in ipairs(inv) do recipeIds[#recipeIds + 1] = id end
		end
		local ok, plan = PackRoom.check({ ownedPatrons = ownedIds, recipes = recipeIds, patronLimit = RunState.patronSlotLimit(state),
			recipeLimit = RunState.recipeSlotLimit(state) }, picked, replaceIds)
		if not ok then
			return false, plan
		end
		for _, id in ipairs(plan.patrons) do
			local sellOk, refund = RunState.sellPatron(state, id)
			if sellOk then sold = sold + refund end
		end
		for _, id in ipairs(plan.recipes) do
			for _, inv in ipairs({ state.houseRecipeInventory, state.menuRecipeInventory, state.secretRecipeInventory }) do
				local at
				for i, owned in ipairs(inv) do
					if owned == id then at = i break end
				end
				if at then
					table.remove(inv, at)
					local refund = PackRoom.sellValue("recipe", id)
					state.tips = state.tips + refund
					sold = sold + refund
					break
				end
			end
		end
	end

	-- Every revealed item carries its OWN `category` tag (see RunState.openPack)
	-- -- for single-category packs (patron/house/menu/secret/standard) that
	-- always matches the pack-level `pending.category`, but "mixed" packs
	-- (Grab Bag) reveal a different category per item, so granting MUST
	-- dispatch off the item's own category, not the pack's. Look up each
	-- chosen id's item once, then branch on itemCategory below.
	local function findItem(chosenId)
		for _, item in ipairs(pending.items) do
			if item.id == chosenId then
				return item
			end
		end
		return nil
	end

	for _, chosenId in ipairs(chosenIds) do
		local item = findItem(chosenId)
		local itemCategory = item and item.category or pending.category

		if itemCategory == "patron" then
			if #state.ownedPatrons < RunState.patronSlotLimit(state) then
				local patron = Patrons.getById(chosenId)
				local alreadyOwned = false
				for _, o in ipairs(state.ownedPatrons) do
					if o.id == chosenId then
						alreadyOwned = true
						break
					end
				end
				if patron and not alreadyOwned then
					table.insert(state.ownedPatrons, patron)
				end
			end
		elseif itemCategory == "standard" then
			-- Instantiate a real card from the revealed item's spec, then
			-- drop it in the discard pile -- same place "86 It"/Brittle
			-- Garnish breakage etc. leave/remove cards -- so it reshuffles
			-- into the deck at the next RunState.startRound, same as every
			-- other persistent-deck card.
			if item and item.card then
				local spec = item.card
				local newCard = Card.new(spec.rank, spec.suit, {
					garnish = spec.garnish,
					special = spec.special,
					stamp = spec.stamp,
					mark = spec.mark,
				})
				table.insert(state.discardPile, newCard)
			end
		else
			-- RECIPE CAP: mirror the Patron branch above -- a pick that no
			-- longer fits by the time this resolves (box already at
			-- RunState.recipeSlotLimit, House+Menu+Secret combined) is
			-- silently skipped, not a reason to fail the whole resolve.
			-- Re-checked fresh every iteration so a multi-pick pack (Mega
			-- pack: pick 2) fills up to the cap and then skips the rest,
			-- rather than reading a stale count from before this loop.
			local inventory = inventoryForCategory(state, itemCategory)
			if inventory and totalHeldRecipes(state) < RunState.recipeSlotLimit(state) then
				table.insert(inventory, chosenId)
			end
		end
	end

	state.pendingPack = nil
	if #chosenIds == 0 then
		-- Skip Pack: half the price actually paid comes back (the amount is read from the server's own record, never from the client)
		local refund = math.min(Packs.skipRefund(pending.paidPrice), math.floor(tonumber(pending.paidPrice) or 0))
		state.tips = state.tips + refund
		return true, string.format("Pack skipped, %d Tips back.", refund), refund
	end
	return true, "Picked!", sold
end

-- Discard an owned Patron for half its price back (rounded down). Allowed
-- any time -- like theme purchases, this doesn't need to be gated to the
-- shop phase; it's tidying up your table, not a purchasing decision made
-- under shop-visit constraints. Returns true/false, refundAmount.
function RunState.sellPatron(state, patronId)
	for i, patron in ipairs(state.ownedPatrons) do
		if patron.id == patronId then
			table.remove(state.ownedPatrons, i)
			local refund = math.floor(patron.price / 2)
			state.tips = state.tips + refund
			state.patronsSold = state.patronsSold + 1
			return true, refund
		end
	end
	return false, 0
end

-- Recipes are used from the shop or at the table while a round is being played (the consumables tray); selling one is free of
-- phase like selling a Patron. Returns true, refund or false, 0.
function RunState.phaseAllowsRecipeUse(phase)
	return phase == "shop" or phase == "playing"
end

function RunState.sellRecipe(state, category, id)
	local inv = category == "house" and state.houseRecipeInventory or category == "menu" and state.menuRecipeInventory
		or category == "secret" and state.secretRecipeInventory
	if not inv or type(id) ~= "string" then return false, 0 end
	for i, owned in ipairs(inv) do
		if owned == id then
			table.remove(inv, i)
			local refund = PackRoom.sellValue("recipe", id)
			state.tips = state.tips + refund
			return true, refund
		end
	end
	return false, 0
end

-- Move an owned Patron one seat left (dir -1) or right (dir 1). Seat order matters for neighbour Patrons. Free, any time,
-- like selling. Returns true, newIndex or false.
function RunState.movePatron(state, patronId, dir)
	if dir ~= -1 and dir ~= 1 then return false end
	local list = state.ownedPatrons
	for i, patron in ipairs(list) do
		if patron.id == patronId then
			local j = i + dir
			if j < 1 or j > #list then return false end
			list[i], list[j] = list[j], list[i]
			return true, j
		end
	end
	return false
end

--[[
	Recipes (House/Menu/Secret) -- see Recipes.lua. ENGINE-ONLY IN THIS
	PASS: nothing in the shop UI sells these or lets a player pick target
	cards yet, but the buy -> inventory -> use flow below is fully
	implemented and tested, ready for that UI to call into.
]]

local function buyRecipe(state, inventory, catalog, id)
	local recipe
	for _, r in ipairs(catalog) do
		if r.id == id then
			recipe = r
			break
		end
	end
	if not recipe then
		return false, "Unknown recipe: " .. tostring(id)
	end
	-- RECIPE CAP: a shop purchase is a deliberate spend, so refuse it
	-- outright (same shape as RunState.buyPatron's full-table refusal)
	-- rather than charging Tips for a Recipe that won't fit.
	if totalHeldRecipes(state) >= RunState.recipeSlotLimit(state) then
		return false, "Your recipe box is full, use one to make room"
	end
	if state.tips < recipe.price then
		return false, "Not enough tips"
	end
	state.tips = state.tips - recipe.price
	table.insert(inventory, id)
	return true, recipe.name .. " added to your recipe box."
end

local function useRecipe(state, inventory, catalog, id, opts, category)
	local index
	for i, ownedId in ipairs(inventory) do
		if ownedId == id then
			index = i
			break
		end
	end
	if not index then
		return false, "You don't have that recipe"
	end
	local recipe
	for _, r in ipairs(catalog) do
		if r.id == id then
			recipe = r
			break
		end
	end
	if not recipe then
		return false, "Unknown recipe: " .. tostring(id)
	end
	opts = opts or {}
	opts.rng = opts.rng or state.rng or math.random
	-- RECIPE CAP: totalHeldRecipes is computed here, BEFORE this recipe is
	-- removed from its inventory below -- so it's off by one for a recipe
	-- (like Second Helping) whose OWN effect adds another Recipe: using it
	-- always frees its own slot first, so subtract 1 to give apply() the
	-- count as it will actually be right after this use succeeds, not the
	-- stale count from right before it.
	local deps = {
		Patrons = Patrons,
		patronSlotLimit = RunState.patronSlotLimit(state),
		recipeSlotLimit = RunState.recipeSlotLimit(state),
		totalHeldRecipes = totalHeldRecipes(state) - 1,
	}
	local ok, message = recipe.apply(state, opts, deps)
	if ok then
		table.remove(inventory, index)
		state.lastRecipeUsedId = id
		-- BUGFIX: "Second Helping" ("Creates a copy of the last House or
		-- Menu Recipe you used") always inserted the copy into
		-- houseRecipeInventory, but lastRecipeUsedId got set here for
		-- EVERY category including Secret Recipes -- using a Menu or
		-- Secret Recipe, then Second Helping, copied an id that only
		-- exists in a DIFFERENT catalog into houseRecipeInventory. That
		-- phantom entry can't be found (Shop.lua's findRecipeById silently
		-- drops it from the UI) or used (useHouseRecipe looks it up in the
		-- wrong catalog and refuses it as "Unknown recipe") -- with no way
		-- to sell/discard a Recipe, it permanently occupied one of only 2
		-- shared recipe slots for the rest of the run. Tracking WHICH
		-- category it came from lets Second Helping insert into the right
		-- inventory (and refuse cleanly for a Secret Recipe, matching its
		-- own "House or Menu" description) instead of guessing "House".
		state.lastRecipeUsedCategory = category
		state.recipesUsed = (state.recipesUsed or 0) + 1 -- daily quest: use a Recipe
	end
	return ok, message
end

function RunState.buyHouseRecipe(state, id)
	return buyRecipe(state, state.houseRecipeInventory, Recipes.HouseRecipes, id)
end
function RunState.buyMenuRecipe(state, id)
	return buyRecipe(state, state.menuRecipeInventory, Recipes.MenuRecipes, id)
end
function RunState.buySecretRecipe(state, id)
	return buyRecipe(state, state.secretRecipeInventory, Recipes.SecretRecipes, id)
end

-- opts (optional, only some recipes need these): { cardIndices = {1,2}, suit = "Hearts" }
function RunState.useHouseRecipe(state, id, opts)
	return useRecipe(state, state.houseRecipeInventory, Recipes.HouseRecipes, id, opts, "house")
end
function RunState.useMenuRecipe(state, id, opts)
	return useRecipe(state, state.menuRecipeInventory, Recipes.MenuRecipes, id, opts, "menu")
end
function RunState.useSecretRecipe(state, id, opts)
	return useRecipe(state, state.secretRecipeInventory, Recipes.SecretRecipes, id, opts, "secret")
end

-- Call after a round is won (and shopping is done) to move on.
function RunState.advanceToNextRound(state)
	assert(state.roundOver and not state.runOver, "Can't advance: round not won or run already over")

	-- A Sale Day Tag (Tags.lua) only ever covers the shop visit right
	-- after you skipped for it -- clear it here, at the moment that visit
	-- actually ends, whether or not it got used on a purchase.
	state.nextShopDiscount = nil

	state.round = state.round + 1
	if state.round > state.config.roundsPerNight then
		state.round = 1
		state.night = state.night + 1
		WorldMap.extendRoute(state) -- plain roads and fixed plans fill in; a fork waits for ChooseRoad
		-- Shrine on the world map: a free House Pass for exactly one Night (see Engine/SideStops.lua).
		local temp = state.tempPass
		if temp then
			if state.night == temp.night and not state.housePasses[temp.id] then
				state.housePasses[temp.id] = true
				temp.active = true
			elseif state.night > temp.night then
				if temp.active then
					state.housePasses[temp.id] = nil
				end
				state.tempPass = nil
			end
		end
	end
	RunState.startRound(state)
end

--[[
	ONE MORE ROUND (the run's single continue -- free once a day, otherwise
	the "continue" Developer Product; see GamePasses.DeveloperProducts and
	Server/init.server.lua). Using it puts the run back exactly where the
	failed round started (state.roundStartSnapshot, taken by startRound):
	same dealt hand, deck order, Tips, inventories, and that round's full
	Hands and Discards. It marks the run `revived` for good.

	The rng is NOT rewound, so later draws in the replayed round (deck
	reshuffles mid-round, random Recipe effects) can come out differently.
]]
function RunState.canContinue(state)
	return state.runOver == true
		and not state.wonRun
		and (not state.revived or (state.extraContinues or 0) > 0) -- a Rest stop can bank a second continue
		and state.roundStartSnapshot ~= nil
end

function RunState.useContinue(state)
	assert(RunState.canContinue(state), "Can't continue this run")
	local snapshot = state.roundStartSnapshot
	local restored = copyForSnapshot(snapshot)
	-- A banked second continue is used up now; the run stays "revived" for the boards either way.
	local extraLeft = state.revived and math.max(0, (state.extraContinues or 0) - 1) or (state.extraContinues or 0)
	for key in pairs(state) do
		if key ~= "rng" and key ~= "roundStartSnapshot" then
			state[key] = nil
		end
	end
	for key, value in pairs(restored) do
		state[key] = value
	end
	state.roundStartSnapshot = snapshot
	state.extraContinues = extraLeft
	state.revived = true
	state.runOver = false
	state.roundOver = false
end

-- Whether this run's progress still counts toward the player's permanent
-- high score records (bestNightReached, runsWon). A revived run doesn't.
-- RULE BAN: spend one token to fight the Night's boss with no rule (its own target modifier goes too; the Night's base
-- target stays). Only before the boss round has begun (Round Select, nothing played), once per boss, and only in a run
-- that was created with tokens. The round is dealt again without the rule. Returns ok, reason.
function RunState.useRuleBan(state, phase)
	if not state.ruleBansEnabled then
		return false, "Rule Bans are not part of this run."
	end
	if (state.ruleBans or 0) < 1 then
		return false, "No Rule Ban left."
	end
	if phase ~= nil and phase ~= "roundSelect" then
		return false, "Only before the boss round starts."
	end
	if state.runOver or state.roundOver or not state.isBossRound or not state.nightBossModifier or not state.bossRoundsEnabled then
		return false, "There is no boss rule to ban."
	end
	if state.bannedBossNight == state.night then
		return false, "This boss is already banned."
	end
	if state.roundScore > 0 or state.handsRemaining ~= state.roundStartHands then
		return false, "The round has already started."
	end
	state.ruleBans = state.ruleBans - 1
	state.bannedBossNight = state.night
	state.tips = state.tips + (state.bossTipsLostAtStart or 0) -- Cold Start took Tips as the round was set up: give them back
	RunState.startRound(state) -- deals the round again, now with no rule
	return true
end

function RunState.countsForRecords(state)
	return not state.revived and not state.rush and not state.quickRun -- a Boss Rush or Quick Run never moves Night records, wins, stamps or titles
end

--[[
	ROUND SELECT FEATURE: skip the current round outright instead of
	playing it, for whatever Tag is currently revealed (see
	state.currentRoundSkipTag/Tags.lua) -- mirrors "you can skip the
	Small/Big Blind for a Tag, but never the Boss Blind" from the reference
	game.

	Deliberately narrow about WHEN skipping is allowed (see canSkipRound):
	only the last round of a Night (the Boss round) is permanently
	unskippable; any earlier round in the Night can be skipped, but only
	before you've touched it (no hand played, no Discard used, no score on
	the board yet) -- once you've started a round for real, skipping away
	from it would be forfeiting real progress, which isn't the tradeoff
	this feature is for.

	Skipping bypasses the normal roundOver -> shop -> advanceToNextRound
	flow entirely (it jumps straight into the next round's startRound) --
	on purpose, so skipping a round always means missing that round's shop
	visit too. That's the real cost of the Tag: you don't play the round,
	but you don't get to spend at The Counter afterward either.
]]
function RunState.canSkipRound(state)
	if state.roundOver or state.runOver then
		return false
	end
	if state.round >= state.config.roundsPerNight then
		return false -- the Boss round (last round of the Night) is never skippable
	end
	-- See the BUGFIX comment on state.roundStartHands/roundStartDiscards in
	-- startRound above -- these already account for House Pass bonuses and
	-- any Boss Round override, unlike the static state.config numbers.
	-- Falls back to the static config for a state that predates this field
	-- (shouldn't happen in practice -- startRound always sets it -- but
	-- keeps this from hard-erroring on an old/malformed state table).
	return state.handsRemaining == (state.roundStartHands or state.config.handsPerRound)
		and state.discardsRemaining == (state.roundStartDiscards or state.config.discardsPerRound)
		and state.roundScore == 0
end

-- Returns tag, result -- the Tag that was applied (Tags.Definitions entry,
-- for id/name/icon/description) and the result table its own `apply`
-- returned (see Tags.lua's header comment for the result shapes), so the
-- caller can show a confirmation that matches what ACTUALLY happened.
function RunState.skipRound(state)
	assert(RunState.canSkipRound(state), "Can't skip this round")
	local tag = state.currentRoundSkipTag
	assert(tag, "No skip Tag available for this round, startRound should always pick one for a skippable round")

	local result = tag.apply(state, {
		rng = state.rng,
		patronSlotLimit = RunState.patronSlotLimit(state),
	})

	state.round = state.round + 1
	RunState.startRound(state)
	return tag, result
end

return RunState
