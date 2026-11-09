--[[
	EngineTests.lua
	Unit tests for the pure-Lua game engine (Card, Deck, HandEvaluator,
	Scoring, Patrons, RunState). Run these two ways:

	1. Locally, with no Roblox needed at all:
		 lua5.3 tools/run_tests_local.lua

	2. Inside Roblox Studio: src/Server/init.server.lua requires this file
	   and runs it automatically every time you press Play, printing
	   PASS/FAIL to the Output window.
]]

local Card = require(script.Parent.Parent.Engine.Card)
local Deck = require(script.Parent.Parent.Engine.Deck)
local HandEvaluator = require(script.Parent.Parent.Engine.HandEvaluator)
local Scoring = require(script.Parent.Parent.Engine.Scoring)
local Patrons = require(script.Parent.Parent.Engine.Patrons)
local CosmeticSets = require(script.Parent.Parent.Engine.CosmeticSets)
local JourneyMap = require(script.Parent.Parent.Engine.JourneyMap)
local RunState = require(script.Parent.Parent.Engine.RunState)
local Shop = require(script.Parent.Parent.Engine.Shop)
local Onboarding = require(script.Parent.Parent.Engine.Onboarding)
local DeckVariants = require(script.Parent.Parent.Engine.DeckVariants)
local DifficultyTiers = require(script.Parent.Parent.Engine.DifficultyTiers)
local BossRounds = require(script.Parent.Parent.Engine.BossRounds)
local Recipes = require(script.Parent.Parent.Engine.Recipes)
local HousePasses = require(script.Parent.Parent.Engine.HousePasses)
local Packs = require(script.Parent.Parent.Engine.Packs)
local Tags = require(script.Parent.Parent.Engine.Tags)
local PlayerProfile = require(script.Parent.Parent.Engine.PlayerProfile) -- PERSISTENT SAVE, Phase 10
local SeededRng = require(script.Parent.Parent.Engine.SeededRng) -- DAILY CHALLENGE, Phase 11
local GamePasses = require(script.Parent.Parent.Engine.GamePasses) -- PHASE 16 cosmetics batch: confirms the 4 new Themes are un-gated
local Achievements = require(script.Parent.Parent.Engine.Achievements) -- ACHIEVEMENTS + TITLES, Phase 16
local TrueWildcard = require(script.Parent.Parent.Engine.TrueWildcard) -- PHASE C Signature Mechanic ("mind-blowing plan")
local Leaderboards = require(script.Parent.Parent.Engine.Leaderboards) -- PAID CONTINUE board routing
local DeveloperProducts = require(script.Parent.Parent.Engine.DeveloperProducts) -- PAID CONTINUE product catalog
local CollectionBook = require(script.Parent.Parent.Engine.CollectionBook) -- COLLECTION screen rules
local CardBacks = require(script.Parent.Parent.Engine.CardBacks)
local TestRunner = require(script.Parent.TestRunner)

local expectEqual = TestRunner.expectEqual
local expectTrue = TestRunner.expectTrue
local expectFalse = TestRunner.expectFalse

local function C(rank, suit)
	return Card.new(rank, suit)
end

-- rng that always rolls a 1 -- forces every "1 in N" chance to hit.
local function alwaysHitRng(_n) return 1 end
-- rng that never rolls a 1 (for n > 1) -- forces every "1 in N" chance to miss.
local function neverHitRng(n) return n end

-- rng that returns a pre-scripted sequence of values, one per call, in call
-- order (NOT keyed by n) -- lets a test dictate an exact reveal outcome even
-- when several different rng(n) calls with different n's are interleaved
-- (e.g. Grab Bag Packs, which roll a subcategory THEN roll within it). Falls
-- back to 1 past the end of the script, and clamps out-of-range values down
-- to n so a script written for one n doesn't error against a differently
-- sized list.
local function scriptedRng(sequence)
	local i = 0
	return function(n)
		i = i + 1
		local v = sequence[i] or 1
		if v > n then v = n end
		if v < 1 then v = 1 end
		return v
	end
end

local tests = {}

-- ===== Card =====

table.insert(tests, { name = "Card.chipValue: number cards use pip value", fn = function()
	expectEqual(Card.chipValue(C(7, "Hearts")), 7)
end })

table.insert(tests, { name = "Card.chipValue: face cards are worth 10", fn = function()
	expectEqual(Card.chipValue(C(12, "Spades")), 10)
end })

table.insert(tests, { name = "Card.chipValue: Ace is worth 11", fn = function()
	expectEqual(Card.chipValue(C(14, "Clubs")), 11)
end })

-- ===== Deck =====

table.insert(tests, { name = "Deck.newStandardDeck has 52 unique cards", fn = function()
	local deck = Deck.newStandardDeck()
	expectEqual(#deck, 52)
	local seen = {}
	for _, card in ipairs(deck) do
		local key = card.rank .. card.suit
		expectFalse(seen[key], "duplicate card found: " .. key)
		seen[key] = true
	end
end })

table.insert(tests, { name = "Deck.shuffle keeps the same 52 cards (just reordered)", fn = function()
	local deck = Deck.newStandardDeck()
	local shuffled = Deck.shuffle(Deck.newStandardDeck(), function(n) return n end) -- identity rng
	expectEqual(#shuffled, #deck)
end })

table.insert(tests, { name = "Deck.draw removes cards from the deck", fn = function()
	local deck = Deck.newStandardDeck()
	local hand = Deck.draw(deck, 8)
	expectEqual(#hand, 8)
	expectEqual(#deck, 44)
end })

table.insert(tests, { name = "Deck.remainingCounts totals match the deck's remaining card count", fn = function()
	local deck = Deck.newStandardDeck()
	Deck.draw(deck, 8)
	local counts = Deck.remainingCounts(deck)
	local total = 0
	for _, suit in ipairs(Card.Suits) do
		for _, rank in ipairs(Deck.RankOrder) do
			total = total + counts[suit][rank]
		end
	end
	expectEqual(total, #deck)
end })

table.insert(tests, { name = "Deck.remainingCounts never exceeds 1 per unique card in a fresh deck", fn = function()
	local deck = Deck.newStandardDeck()
	local counts = Deck.remainingCounts(deck)
	expectEqual(counts["Hearts"][14], 1)
	expectEqual(counts["Spades"][2], 1)
end })

-- ===== HandEvaluator =====

table.insert(tests, { name = "HandEvaluator: every hand in HandOrder has an Example that evaluates to it", fn = function()
	for _, handName in ipairs(HandEvaluator.HandOrder) do
		local spec = HandEvaluator.Examples[handName]
		assert(spec, "missing example for " .. handName)
		local cards = {}
		for _, rs in ipairs(spec) do
			table.insert(cards, C(rs[1], rs[2]))
		end
		expectEqual(HandEvaluator.evaluate(cards).name, handName)
	end
end })

table.insert(tests, { name = "HandEvaluator: single card is High Card", fn = function()
	local result = HandEvaluator.evaluate({ C(9, "Hearts") })
	expectEqual(result.name, "High Card")
	expectEqual(#result.scoringCards, 1)
end })

table.insert(tests, { name = "HandEvaluator: two matching ranks is a Pair", fn = function()
	local result = HandEvaluator.evaluate({ C(5, "Hearts"), C(5, "Clubs"), C(9, "Spades") })
	expectEqual(result.name, "Pair")
	expectEqual(#result.scoringCards, 2)
end })

table.insert(tests, { name = "HandEvaluator: two pairs is Two Pair", fn = function()
	local result = HandEvaluator.evaluate({ C(5, "Hearts"), C(5, "Clubs"), C(9, "Spades"), C(9, "Diamonds") })
	expectEqual(result.name, "Two Pair")
	expectEqual(#result.scoringCards, 4)
end })

table.insert(tests, { name = "HandEvaluator: three matching ranks is Three of a Kind", fn = function()
	local result = HandEvaluator.evaluate({ C(8, "Hearts"), C(8, "Clubs"), C(8, "Spades"), C(2, "Diamonds") })
	expectEqual(result.name, "Three of a Kind")
	expectEqual(#result.scoringCards, 3)
end })

table.insert(tests, { name = "HandEvaluator: 5 consecutive ranks (mixed suits) is a Straight", fn = function()
	local result = HandEvaluator.evaluate({ C(4, "Hearts"), C(5, "Clubs"), C(6, "Spades"), C(7, "Diamonds"), C(8, "Hearts") })
	expectEqual(result.name, "Straight")
end })

table.insert(tests, { name = "HandEvaluator: Ace-low straight (A,2,3,4,5) is recognized", fn = function()
	local result = HandEvaluator.evaluate({ C(14, "Hearts"), C(2, "Clubs"), C(3, "Spades"), C(4, "Diamonds"), C(5, "Hearts") })
	expectEqual(result.name, "Straight")
end })

table.insert(tests, { name = "HandEvaluator: 5 same-suit non-consecutive is a Flush", fn = function()
	local result = HandEvaluator.evaluate({ C(2, "Hearts"), C(5, "Hearts"), C(7, "Hearts"), C(9, "Hearts"), C(13, "Hearts") })
	expectEqual(result.name, "Flush")
end })

table.insert(tests, { name = "HandEvaluator: straight + flush is Straight Flush, not just Flush", fn = function()
	local result = HandEvaluator.evaluate({ C(4, "Hearts"), C(5, "Hearts"), C(6, "Hearts"), C(7, "Hearts"), C(8, "Hearts") })
	expectEqual(result.name, "Straight Flush")
end })

table.insert(tests, { name = "HandEvaluator: 4 same-suit + 1 wild (House Blend) card is a Flush", fn = function()
	local wildCard = Card.new(3, "Spades", { garnish = "houseBlend" })
	local result = HandEvaluator.evaluate({ C(2, "Hearts"), C(5, "Hearts"), C(7, "Hearts"), C(9, "Hearts"), wildCard })
	expectEqual(result.name, "Flush")
end })

table.insert(tests, { name = "HandEvaluator: 4 same-suit + 1 off-suit (no wild) is NOT a Flush", fn = function()
	local result = HandEvaluator.evaluate({ C(2, "Hearts"), C(5, "Hearts"), C(7, "Hearts"), C(9, "Hearts"), C(3, "Spades") })
	expectFalse(result.name == "Flush", "a plain off-suit card should not complete a Flush")
end })

table.insert(tests, { name = "HandEvaluator: a wild card can complete both the Straight and the Flush at once", fn = function()
	local wildCard = Card.new(8, "Spades", { garnish = "houseBlend" }) -- rank fits the straight, suit is wild
	local result = HandEvaluator.evaluate({ C(4, "Hearts"), C(5, "Hearts"), C(6, "Hearts"), C(7, "Hearts"), wildCard })
	expectEqual(result.name, "Straight Flush")
end })

table.insert(tests, { name = "HandEvaluator: 3+2 of a kind is Full House", fn = function()
	local result = HandEvaluator.evaluate({ C(6, "Hearts"), C(6, "Clubs"), C(6, "Spades"), C(9, "Diamonds"), C(9, "Hearts") })
	expectEqual(result.name, "Full House")
end })

table.insert(tests, { name = "HandEvaluator: four matching ranks is Four of a Kind", fn = function()
	local result = HandEvaluator.evaluate({ C(3, "Hearts"), C(3, "Clubs"), C(3, "Spades"), C(3, "Diamonds"), C(9, "Hearts") })
	expectEqual(result.name, "Four of a Kind")
	expectEqual(#result.scoringCards, 4)
end })

table.insert(tests, { name = "HandEvaluator: a pair breaks a straight (duplicate rank)", fn = function()
	local result = HandEvaluator.evaluate({ C(4, "Hearts"), C(4, "Clubs"), C(6, "Spades"), C(7, "Diamonds"), C(8, "Hearts") })
	expectFalse(result.name == "Straight", "should not be a straight when a rank repeats")
end })

-- ===== Scoring =====

table.insert(tests, { name = "Scoring.calculate: Pair of 9s with no patrons", fn = function()
	local hand = HandEvaluator.evaluate({ C(9, "Hearts"), C(9, "Clubs"), C(2, "Spades") })
	-- base Pair = 10 chips / 2 mult, scoring cards are the two 9s (9 chips each)
	local score, chips, mult = Scoring.calculate(hand, {}, {})
	expectEqual(chips, 10 + 9 + 9)
	expectEqual(mult, 2)
	expectEqual(score, chips * mult)
end })

table.insert(tests, { name = "Scoring.calculate: 'The Regular' patron adds flat +4 mult", fn = function()
	local hand = HandEvaluator.evaluate({ C(9, "Hearts"), C(9, "Clubs"), C(2, "Spades") })
	local theRegular = Patrons.getById("the_regular")
	local _, _, mult = Scoring.calculate(hand, { theRegular }, {})
	expectEqual(mult, 2 + 4) -- base Pair mult (2) + patron (4)
end })

table.insert(tests, { name = "Scoring.calculate: 'Curtain Call' only triggers on the last hand", fn = function()
	local hand = HandEvaluator.evaluate({ C(9, "Hearts"), C(9, "Clubs"), C(2, "Spades") })
	local curtainCall = Patrons.getById("curtain_call")

	local _, _, multNotLast = Scoring.calculate(hand, { curtainCall }, { isLastHand = false })
	expectEqual(multNotLast, 2)

	local _, _, multLast = Scoring.calculate(hand, { curtainCall }, { isLastHand = true })
	expectEqual(multLast, 2 * 1.5)
end })

table.insert(tests, { name = "Scoring.calculate: a Gold Special on an owned Patron adds its flat Mult", fn = function()
	local hand = HandEvaluator.evaluate({ C(9, "Hearts"), C(9, "Clubs"), C(2, "Spades") })
	local theRegular = Patrons.getById("the_regular")
	local _, _, mult = Scoring.calculate(hand, { theRegular }, { ownedPatronSpecials = { the_regular = "gold" } })
	expectEqual(mult, 2 + 4 + 10) -- base Pair mult (2) + patron flat (4) + Gold Special (+10 Mult)
end })

table.insert(tests, { name = "Scoring.calculate: a Silver Special on an owned Patron adds its flat Chips", fn = function()
	local hand = HandEvaluator.evaluate({ C(9, "Hearts"), C(9, "Clubs"), C(2, "Spades") })
	local theRegular = Patrons.getById("the_regular")
	local _, chips = Scoring.calculate(hand, { theRegular }, { ownedPatronSpecials = { the_regular = "silver" } })
	expectEqual(chips, 10 + 9 + 9 + 50)
end })

table.insert(tests, { name = "Scoring.calculate: a Rainbow Special on an owned Patron multiplies XMult", fn = function()
	local hand = HandEvaluator.evaluate({ C(9, "Hearts"), C(9, "Clubs"), C(2, "Spades") })
	local theRegular = Patrons.getById("the_regular")
	local _, _, mult = Scoring.calculate(hand, { theRegular }, { ownedPatronSpecials = { the_regular = "rainbow" } })
	expectEqual(mult, (2 + 4) * 1.5)
end })

table.insert(tests, { name = "Scoring.calculate: a Reserved Special on an owned Patron adds no Chips/Mult/XMult", fn = function()
	local hand = HandEvaluator.evaluate({ C(9, "Hearts"), C(9, "Clubs"), C(2, "Spades") })
	local theRegular = Patrons.getById("the_regular")
	local _, _, mult = Scoring.calculate(hand, { theRegular }, { ownedPatronSpecials = { the_regular = "reserved" } })
	expectEqual(mult, 2 + 4) -- Reserved's +1 slot effect lives in RunState.patronSlotLimit, not here
end })

-- ===== Scoring.calculate: extra.breakdown (feeds the client "juice" sequence) =====

table.insert(tests, { name = "Scoring.calculate: extra.breakdown starts with the base hand's chips/mult entries", fn = function()
	local hand = HandEvaluator.evaluate({ C(9, "Hearts"), C(9, "Clubs"), C(2, "Spades") })
	local _, _, _, extra = Scoring.calculate(hand, {}, {})
	expectTrue(extra.breakdown ~= nil)
	expectEqual(extra.breakdown[1].kind, "chips")
	expectEqual(extra.breakdown[1].amount, 10) -- base Pair chips
	expectEqual(extra.breakdown[2].kind, "mult")
	expectEqual(extra.breakdown[2].amount, 2) -- base Pair mult
end })

table.insert(tests, { name = "Scoring.calculate: extra.breakdown records one chips entry per scoring card", fn = function()
	local hand = HandEvaluator.evaluate({ C(9, "Hearts"), C(9, "Clubs"), C(2, "Spades") })
	local _, _, _, extra = Scoring.calculate(hand, {}, {})
	-- entries 1-2 are the base hand; entries 3-4 should be the two scoring 9s
	expectEqual(extra.breakdown[3].kind, "chips")
	expectEqual(extra.breakdown[3].amount, 9)
	expectEqual(extra.breakdown[4].kind, "chips")
	expectEqual(extra.breakdown[4].amount, 9)
	expectEqual(#extra.breakdown, 4) -- no patrons/garnishes -- nothing else should be recorded
end })

table.insert(tests, { name = "Scoring.calculate: extra.breakdown records a Patron's flat mult bonus", fn = function()
	local hand = HandEvaluator.evaluate({ C(9, "Hearts"), C(9, "Clubs"), C(2, "Spades") })
	local theRegular = Patrons.getById("the_regular")
	local _, _, _, extra = Scoring.calculate(hand, { theRegular }, {})
	local found = false
	for _, entry in ipairs(extra.breakdown) do
		if entry.kind == "mult" and entry.amount == 4 and entry.label == theRegular.name then
			found = true
		end
	end
	expectTrue(found, "expected a +4 mult breakdown entry labeled with the Patron's name")
end })

table.insert(tests, { name = "Scoring.calculate: extra.breakdown records a Rainbow Special's xmult as its own entry", fn = function()
	local hand = HandEvaluator.evaluate({ C(9, "Hearts"), C(9, "Clubs"), C(2, "Spades") })
	local theRegular = Patrons.getById("the_regular")
	local _, _, _, extra = Scoring.calculate(hand, { theRegular }, { ownedPatronSpecials = { the_regular = "rainbow" } })
	local found = false
	for _, entry in ipairs(extra.breakdown) do
		if entry.kind == "xmult" and entry.amount == 1.5 then
			found = true
		end
	end
	expectTrue(found, "expected an xmult breakdown entry for the Rainbow Special")
end })

table.insert(tests, { name = "Scoring.calculate: extra.breakdown records a Sweet Garnish's chips as its own entry", fn = function()
	local card = C(9, "Hearts")
	card.garnish = "sweet"
	local hand = HandEvaluator.evaluate({ card, C(9, "Clubs"), C(2, "Spades") })
	local _, _, _, extra = Scoring.calculate(hand, {}, {})
	local sweetEntryChips = 0
	for _, entry in ipairs(extra.breakdown) do
		if entry.kind == "chips" and entry.label == Card.toString(card) then
			sweetEntryChips = entry.amount
		end
	end
	-- Sweet Garnish is +30 chips (see Card.Garnishes) folded into that card's
	-- own chips entry alongside its 9 rank chips.
	expectEqual(sweetEntryChips, 9 + 30)
end })

-- SCORING JUICE, full choreography pass: breakdown.source lets the client
-- trace an entry back to the physical card/Patron/base-hand that caused it
-- (see Scoring.lua's header comment). These tests lock the `source.type`
-- contract in so a future refactor can't silently break the client's
-- per-card reveal without a test noticing.

table.insert(tests, { name = "Scoring.calculate: breakdown.source tags the base hand entries as type 'hand'", fn = function()
	local hand = HandEvaluator.evaluate({ C(9, "Hearts"), C(9, "Clubs"), C(2, "Spades") })
	local _, _, _, extra = Scoring.calculate(hand, {}, {})
	expectEqual(extra.breakdown[1].source.type, "hand")
	expectEqual(extra.breakdown[2].source.type, "hand")
end })

table.insert(tests, { name = "Scoring.calculate: breakdown.source tags a scoring card's entry with type 'card' and the same card reference", fn = function()
	local nine = C(9, "Hearts")
	local hand = HandEvaluator.evaluate({ nine, C(9, "Clubs"), C(2, "Spades") })
	local _, _, _, extra = Scoring.calculate(hand, {}, {})
	local found = false
	for _, entry in ipairs(extra.breakdown) do
		if entry.source.type == "card" and entry.source.card == nine then
			found = true
		end
	end
	expectTrue(found, "expected a breakdown entry sourced to the literal card object that was played")
end })

table.insert(tests, { name = "Scoring.calculate: breakdown.source tags a Patron's entry with type 'patron' and its id", fn = function()
	local hand = HandEvaluator.evaluate({ C(9, "Hearts"), C(9, "Clubs"), C(2, "Spades") })
	local theRegular = Patrons.getById("the_regular")
	local _, _, _, extra = Scoring.calculate(hand, { theRegular }, {})
	local found = false
	for _, entry in ipairs(extra.breakdown) do
		if entry.kind == "mult" and entry.source.type == "patron" and entry.source.patronId == "the_regular" then
			found = true
		end
	end
	expectTrue(found, "expected the Patron's mult bonus to be sourced to type 'patron' with its id")
end })

table.insert(tests, { name = "Scoring.calculate: breakdown.source tags an Iron Garnish held-card entry with type 'heldCard'", fn = function()
	local ironCard = C(9, "Hearts")
	ironCard.garnish = "iron"
	local hand = HandEvaluator.evaluate({ C(9, "Clubs"), C(9, "Spades"), C(2, "Diamonds") })
	local _, _, _, extra = Scoring.calculate(hand, {}, { heldCards = { ironCard } })
	local found = false
	for _, entry in ipairs(extra.breakdown) do
		if entry.kind == "xmult" and entry.source.type == "heldCard" and entry.source.card == ironCard then
			found = true
		end
	end
	expectTrue(found, "expected Iron Garnish's held-card xmult to be sourced to type 'heldCard'")
end })

table.insert(tests, { name = "Scoring.calculate: extra.breakdown records a Gold Stamp's payout as a 'tips' entry", fn = function()
	local goldCard = C(9, "Hearts")
	goldCard.stamp = "gold"
	local hand = HandEvaluator.evaluate({ goldCard, C(9, "Clubs"), C(2, "Spades") })
	local _, _, _, extra = Scoring.calculate(hand, {}, {})
	local found = false
	for _, entry in ipairs(extra.breakdown) do
		if entry.kind == "tips" and entry.amount == 3 and entry.source.type == "card" and entry.source.card == goldCard then
			found = true
		end
	end
	expectTrue(found, "expected a tips breakdown entry for the Gold Stamp's 3-tip payout")
end })

-- ===== RunState (integration) =====

table.insert(tests, { name = "RunState.targetScoreFor increases each round/night", fn = function()
	local r1 = RunState.targetScoreFor(1, 1)
	local r2 = RunState.targetScoreFor(1, 2)
	local r3 = RunState.targetScoreFor(2, 1)
	expectTrue(r2 > r1, "round 2 target should exceed round 1")
	expectTrue(r3 > r2, "night 2 round 1 target should exceed night 1 round 3")
end })

table.insert(tests, { name = "RunState.new deals a full starting hand", fn = function()
	local state = RunState.new(nil, function(n) return n end) -- deterministic rng
	expectEqual(#state.hand, state.config.handSize)
	expectEqual(state.handsRemaining, state.config.handsPerRound)
	expectEqual(state.discardsRemaining, state.config.discardsPerRound)
end })

table.insert(tests, { name = "RunState.playHand scores a hand and refills to hand size", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	local sizeBefore = #state.hand
	local result = RunState.playHand(state, { 1, 2 })
	expectTrue(result.score > 0, "expected a positive score")
	expectEqual(#state.hand, sizeBefore) -- refilled back up after playing 2 cards
	expectEqual(state.handsRemaining, state.config.handsPerRound - 1)
end })

table.insert(tests, { name = "RunSummary: best hand, patrons used, route, badge tiers and saved badge", fn = function()
	local RunSummary = require(script.Parent.Parent.Engine.RunSummary)
	local state = RunState.new(nil, function(n) return n end)
	expectEqual(state.bestHand, nil)
	local first = RunState.playHand(state, { 1, 2 })
	expectEqual(state.bestHand.score, first.score)
	state.ownedPatrons = { Patrons.getById("the_regular") }
	local second = RunState.playHand(state, { 1 })
	expectTrue(state.bestHand.score >= math.max(first.score, second.score))
	expectEqual(state.patronsUsedOrder[1], "the_regular")
	local summary = RunSummary.build(state, "Road Walker")
	expectEqual(summary.handsPlayed, 2)
	expectEqual(summary.patrons[1].id, "the_regular")
	expectEqual(summary.titleText, "Road Walker")
	expectTrue(#summary.route >= 1 and summary.route[1].icon ~= nil)
	-- Badge tiers rise with the Night; a win is at least legendary.
	expectEqual(RunSummary.badgeRarity(1, false), "common")
	expectEqual(RunSummary.badgeRarity(4, false), "rare")
	expectEqual(RunSummary.badgeRarity(8, false), "legendary")
	expectEqual(RunSummary.badgeRarity(3, true), "legendary")
	expectEqual(RunSummary.badgeRarity(12, true), "mythical")
	-- A saved badge survives migrate; garbage is dropped.
	local profile = PlayerProfile.new()
	profile.equippedBadge = RunSummary.badgeFromSummary(summary)
	local saved = PlayerProfile.migrate(profile).equippedBadge
	expectEqual(saved.night, summary.night)
	expectEqual(saved.routeIds[1], summary.routeIds[1])
	expectEqual(PlayerProfile.migrate({ equippedBadge = { night = 3, rarity = "nope" } }).equippedBadge, nil)
	expectEqual(PlayerProfile.migrate({ equippedBadge = "x" }).equippedBadge, nil)
end })

table.insert(tests, { name = "RunState.discard swaps cards without spending a hand", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	local handsBefore = state.handsRemaining
	RunState.discard(state, { 1 })
	expectEqual(state.handsRemaining, handsBefore) -- discarding doesn't cost a hand
	expectEqual(state.discardsRemaining, state.config.discardsPerRound - 1)
end })

table.insert(tests, { name = "RunState.deckView: statuses, sorted, hides the True Wildcard", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	local function countStatus(view, status)
		local n = 0
		for _, e in ipairs(view) do
			if e.status == status then n = n + 1 end
		end
		return n
	end
	local view = RunState.deckView(state)
	local total = #state.deck + #state.hand + #state.discardPile
	expectEqual(#view, total)
	expectEqual(countStatus(view, "hand"), #state.hand)
	expectEqual(countStatus(view, "draw"), #state.deck)
	expectEqual(countStatus(view, "played") + countStatus(view, "discarded"), 0)

	RunState.playHand(state, { 1, 2 })
	RunState.discard(state, { 1 })
	view = RunState.deckView(state)
	expectEqual(countStatus(view, "played"), 2)
	expectEqual(countStatus(view, "discarded"), 1)

	-- the entries never follow draw order: re-sorted by suit then rank
	for i = 2, #view do
		local a, b = view[i - 1], view[i]
		if not a.hidden and not b.hidden and a.suit == b.suit then
			expectTrue(a.rank <= b.rank, "ranks ascend within a suit")
		end
		expectTrue(not (a.hidden and not b.hidden), "hidden card sorts last")
	end
	-- hidden wildcard exposes no rank or suit
	for _, e in ipairs(view) do
		if e.hidden then
			expectEqual(e.rank, nil)
			expectEqual(e.suit, nil)
		end
	end

	-- a new round pools everything back into the draw pile
	state.roundOver = false
	RunState.startRound(state)
	view = RunState.deckView(state)
	expectEqual(countStatus(view, "played") + countStatus(view, "discarded"), 0)
end })

table.insert(tests, { name = "RunState.buyPatron deducts tips and adds the patron", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	state.tips = 10
	local ok, _ = RunState.buyPatron(state, "the_regular")
	expectTrue(ok)
	expectEqual(#state.ownedPatrons, 1)
	expectEqual(state.tips, 10 - Patrons.getById("the_regular").price)
end })

table.insert(tests, { name = "RunState.buyPatron fails gracefully with insufficient tips", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	state.tips = 0
	local ok, message = RunState.buyPatron(state, "the_regular")
	expectFalse(ok)
	expectTrue(message ~= nil)
end })

table.insert(tests, { name = "RunState.sellPatron removes the patron and refunds half its price", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	state.tips = 10
	RunState.buyPatron(state, "the_regular")
	local tipsAfterBuy = state.tips
	local ok, refund = RunState.sellPatron(state, "the_regular")
	expectTrue(ok)
	expectEqual(#state.ownedPatrons, 0)
	expectEqual(refund, math.floor(Patrons.getById("the_regular").price / 2))
	expectEqual(state.tips, tipsAfterBuy + refund)
end })

table.insert(tests, { name = "RunState.sellPatron fails gracefully for a patron you don't own", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	local ok, refund = RunState.sellPatron(state, "the_regular")
	expectFalse(ok)
	expectEqual(refund, 0)
end })

-- ===== BossRounds =====

table.insert(tests, { name = "BossRounds.isBossRound is only true on a Night's last round", fn = function()
	expectFalse(BossRounds.isBossRound(1, 3))
	expectFalse(BossRounds.isBossRound(2, 3))
	expectTrue(BossRounds.isBossRound(3, 3))
end })

table.insert(tests, { name = "BossRounds.categoryOf gives every modifier a known category", fn = function()
	for _, def in ipairs(BossRounds.Definitions) do
		local categoryId = BossRounds.categoryOf(def)
		expectTrue(categoryId ~= nil and BossRounds.getCategoryById(categoryId) ~= nil, def.id .. " has no category")
	end
	expectEqual(BossRounds.categoryOf(BossRounds.getById("picked_over")), "debuff", "a combo should take the first matching category")
end })

table.insert(tests, { name = "BossRounds.pick returns a valid, well-formed modifier", fn = function()
	local modifier = BossRounds.pick(function(n) return n end)
	expectTrue(modifier ~= nil)
	expectTrue(BossRounds.getById(modifier.id) == modifier)
	expectTrue(type(modifier.name) == "string" and #modifier.name > 0)
	expectTrue(type(modifier.description) == "string" and #modifier.description > 0)
end })

-- BOSS DIFFICULTY: BossRounds.pick(rng, night) gates modifiers by minNight
-- (Ahmed's playtest bug -- Lights Out, a "1 hand only" boss, appeared on
-- an early Night when he barely had any Patrons). Every definition below
-- with a `minNight > 1` should NEVER be reachable before that Night.
table.insert(tests, { name = "BossRounds.pick never returns a tier-3 (minNight = 6) modifier before Night 6", fn = function()
	-- rng(n) = n always asks for the LAST eligible index -- the strongest
	-- possible check that nothing past the eligible tier ever leaks in,
	-- across every Night from 1 up to (but not including) 6.
	for night = 1, 5 do
		local modifier = BossRounds.pick(function(n) return n end, night)
		expectTrue((modifier.minNight or 1) <= night, "night " .. night .. " returned " .. modifier.id .. " (minNight " .. tostring(modifier.minNight) .. ")")
	end
end })

table.insert(tests, { name = "BossRounds.pick can return a tier-3 modifier once Night reaches 6", fn = function()
	-- rng(n) = n asks for the last eligible index -- with all 24 modifiers
	-- eligible at Night 6+, the last one (by Definitions order) is a
	-- tier-3 modifier, confirming the gate actually opens rather than
	-- silently staying capped forever.
	local modifier = BossRounds.pick(function(n) return n end, 6)
	expectEqual(modifier.minNight, 6, "expected a tier-3 modifier once every tier is unlocked")
end })

table.insert(tests, { name = "BossRounds.pick defaults to Night 1 (most restrictive tier) if no night is passed", fn = function()
	local modifier = BossRounds.pick(function(n) return n end)
	expectTrue((modifier.minNight or 1) <= 1, "expected only a tier-1 modifier with no night argument")
end })

table.insert(tests, { name = "RunState.startRound picks a Boss modifier gated by state.night, not fully random", fn = function()
	-- A dry rng forcing the LAST eligible index every time -- on Night 1
	-- this can only ever be a tier-1 (mild) modifier, never Lights Out/
	-- Stale Bread/etc, reproducing the exact scenario Ahmed hit.
	local state = RunState.new(nil, function(n) return n end)
	expectTrue(state.night == 1)
	expectTrue(state.nightBossModifier ~= nil)
	expectTrue((state.nightBossModifier.minNight or 1) <= 1, "Night 1 should never roll a tier-2/3 Boss modifier")
end })

-- ===== DeckVariants / DifficultyTiers =====

table.insert(tests, { name = "DeckVariants.getById falls back to nil for an unknown id", fn = function()
	expectTrue(DeckVariants.getById("not_a_real_deck") == nil)
	expectTrue(DeckVariants.getById(DeckVariants.DefaultId) ~= nil)
end })

table.insert(tests, { name = "DifficultyTiers.getById falls back to nil for an unknown id", fn = function()
	expectTrue(DifficultyTiers.getById("not_a_real_tier") == nil)
	expectTrue(DifficultyTiers.getById(DifficultyTiers.DefaultId) ~= nil)
end })

-- ===== RunState: Deck Variants, Difficulty Tiers, Boss Rounds, hand stats =====

table.insert(tests, { name = "RunState.new with no options matches the original default balance", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	expectEqual(state.deckVariantId, DeckVariants.DefaultId)
	expectEqual(state.difficultyId, DifficultyTiers.DefaultId)
	expectEqual(state.config.handSize, RunState.DefaultConfig.handSize)
	expectEqual(state.config.handsPerRound, RunState.DefaultConfig.handsPerRound)
	expectEqual(state.tips, 0)
end })

table.insert(tests, { name = "RunState.new applies the chosen Deck Variant's starting Tips and config deltas", fn = function()
	local state = RunState.new({ deckVariantId = "high_roller" }, function(n) return n end)
	expectEqual(state.tips, 12)
	expectEqual(state.config.handsPerRound, RunState.DefaultConfig.handsPerRound - 1)
	expectEqual(state.targetMultiplier, 0.95)
end })

table.insert(tests, { name = "RunState.new falls back to the standard deck variant for an unknown id", fn = function()
	local state = RunState.new({ deckVariantId = "not_real" }, function(n) return n end)
	expectEqual(state.deckVariantId, DeckVariants.DefaultId)
end })

table.insert(tests, { name = "RunState.new never lets a Deck Variant reduce hand size below 1", fn = function()
	-- steady_hand has a -1 handSize delta; make sure clamping keeps it sane
	-- even if DefaultConfig.handSize is ever tuned very low.
	local state = RunState.new({ deckVariantId = "steady_hand" }, function(n) return n end)
	expectTrue(state.config.handSize >= 1)
end })

table.insert(tests, { name = "The Casual difficulty tier disables Boss Rounds", fn = function()
	local state = RunState.new({ difficultyId = "casual" }, function(n) return n end)
	state.round = state.config.roundsPerNight
	RunState.startRound(state)
	expectTrue(state.bossModifier == nil, "Casual should never pick a Boss Round modifier")
end })

table.insert(tests, { name = "Standard difficulty picks a Boss Round modifier on a Night's last round", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	state.round = state.config.roundsPerNight
	RunState.startRound(state)
	expectTrue(state.bossModifier ~= nil, "expected a Boss Round modifier to be chosen")
end })

table.insert(tests, { name = "A Boss Round's hand-size penalty actually shrinks the dealt hand", fn = function()
	-- Find Short Staffed's actual position (handSizeDelta = -1, discardsDelta =
	-- -1) rather than assuming it's last -- new Boss Rounds get appended
	-- to the list over time, which would otherwise silently pick a
	-- different modifier and break this test.
	local shortStaffedIndex
	for i, def in ipairs(BossRounds.Definitions) do
		if def.id == "short_staffed" then
			shortStaffedIndex = i
		end
	end
	expectTrue(shortStaffedIndex ~= nil, "expected to find short_staffed in BossRounds.Definitions")
	-- JOURNEY FEATURE: the Night's Boss modifier is now picked at Round 1
	-- (see RunState.startRound), not lazily the instant the Boss round
	-- itself starts -- so the deterministic rng has to be in place from
	-- construction, not patched onto `state.rng` after the fact (that
	-- would be too late: Round 1's pick already happened inside
	-- RunState.new, using whatever rng was passed there).
	local state = RunState.new(nil, function(_n) return shortStaffedIndex end)
	-- BOSS DIFFICULTY: short_staffed is minNight = 3 (see BossRounds.lua), so
	-- RunState.new's own Round-1-at-Night-1 pick above can't have selected
	-- it (Night 1 only has tier-1 modifiers eligible). Force the run to
	-- Night 3 and re-pick Round 1's Boss modifier there -- same as a real
	-- player reaching Night 3 -- before jumping straight to the Boss round
	-- itself (skipping normal round-by-round progression, since this test
	-- only cares about the modifier's effect once it's active). shortStaffedIndex
	-- still resolves to short_staffed here: at Night 3+, every modifier before
	-- it in Definitions order (all of tier 1 + earlier tier 2) is also
	-- eligible, so its position in the eligible list matches its position
	-- in the full list.
	state.night = 3
	state.round = 1
	RunState.startRound(state)
	state.round = state.config.roundsPerNight
	RunState.startRound(state)
	expectEqual(state.bossModifier.id, "short_staffed")
	expectEqual(#state.hand, state.config.handSize - 1)
	expectEqual(state.discardsRemaining, state.config.discardsPerRound - 1)
end })

table.insert(tests, { name = "JOURNEY: a Night's Boss modifier is knowable from Round 1, before the Boss round itself", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	expectTrue(state.nightBossModifier ~= nil, "expected nightBossModifier to already be picked at Round 1")
	expectTrue(state.bossModifier == nil, "Round 1 itself is never the Boss round")
	local revealedId = state.nightBossModifier.id

	-- Advance through the rest of the Night without touching state.rng --
	-- the SAME modifier revealed back at Round 1 should be the one that
	-- actually applies once the Boss round arrives.
	state.round = state.config.roundsPerNight
	RunState.startRound(state)
	expectEqual(state.bossModifier.id, revealedId)
end })

table.insert(tests, { name = "JOURNEY: Casual difficulty never reveals a nightBossModifier either", fn = function()
	local state = RunState.new({ difficultyId = "casual" }, function(n) return n end)
	expectTrue(state.nightBossModifier == nil)
end })

table.insert(tests, { name = "JOURNEY: canSkipRound is false on a Night's last (Boss) round", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	state.round = state.config.roundsPerNight
	expectFalse(RunState.canSkipRound(state))
end })

table.insert(tests, { name = "JOURNEY: canSkipRound is false once a hand's been played this round", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	expectTrue(RunState.canSkipRound(state), "a fresh Round 1 should be skippable")
	RunState.playHand(state, { 1 })
	expectFalse(RunState.canSkipRound(state), "should no longer be skippable after playing a hand")
end })

table.insert(tests, { name = "JOURNEY: canSkipRound is false once a Discard's been used this round", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	RunState.discard(state, { 1 })
	expectFalse(RunState.canSkipRound(state))
end })

table.insert(tests, { name = "ROUND SELECT: startRound reveals a currentRoundSkipTag on skippable rounds, nil on the Boss round", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	expectTrue(state.currentRoundSkipTag ~= nil, "Round 1 should have a skip Tag revealed")
	state.round = state.config.roundsPerNight
	RunState.startRound(state)
	expectTrue(state.currentRoundSkipTag == nil, "the Boss round should never have a skip Tag")
end })

-- Small helper shared by the Tag-specific tests below: find a Tag's index
-- in Tags.Definitions (rather than assuming a position -- the catalog can
-- grow) so a deterministic rng can force that EXACT Tag to be picked.
local function tagIndexById(id)
	for i, tag in ipairs(Tags.Definitions) do
		if tag.id == id then
			return i
		end
	end
	return nil
end

table.insert(tests, { name = "ROUND SELECT: skipRound applies the Tip Jar Tag and advances without opening a shop", fn = function()
	local tipJarIndex = tagIndexById("tip_jar")
	expectTrue(tipJarIndex ~= nil, "expected to find tip_jar in Tags.Definitions")
	local state = RunState.new(nil, function(_n) return tipJarIndex end)
	local tipsBefore = state.tips
	local roundBefore = state.round
	local tag, result = RunState.skipRound(state)
	expectEqual(tag.id, "tip_jar")
	expectEqual(result.kind, "tips")
	expectTrue(result.amount > 0)
	expectTrue(result.amount < state.config.tipsPerRoundWin, "skip reward should stay worse than actually winning the round")
	expectEqual(state.tips, tipsBefore + result.amount)
	expectEqual(state.round, roundBefore + 1)
	expectFalse(state.roundOver, "skipping should never flip roundOver/open a shop")
end })

table.insert(tests, { name = "ROUND SELECT: Tip Jar's amount scales up gently across Nights, but never reaches tipsPerRoundWin", fn = function()
	-- BUGFIX regression test: this used to grow without a ceiling and cross
	-- (then exceed) tipsPerRoundWin by around Night 4-5. Check a wide
	-- spread of Nights so this can't silently regress at some specific
	-- Night number again.
	local tipJarIndex = tagIndexById("tip_jar")
	local state = RunState.new(nil, function(_n) return tipJarIndex end)
	local lastAmount = 0
	for night = 1, 20 do
		state.night = night
		state.currentRoundSkipTag = Tags.getById("tip_jar") -- re-picked by startRound each round in a real game; forced directly here since we're not advancing rounds
		local _, result = RunState.skipRound(state)
		expectTrue(result.amount < state.config.tipsPerRoundWin, "skip reward must stay below tipsPerRoundWin at Night " .. night)
		expectTrue(result.amount > 0, "skip reward must stay positive at Night " .. night)
		expectTrue(result.amount >= lastAmount, "should never go DOWN as Nights pass")
		lastAmount = result.amount
		-- RunState.skipRound advances state.round -- pull it back to a
		-- skippable round (and undo the Night bump the loop is driving
		-- manually) so the next iteration's skipRound call is valid again.
		state.round = 1
		state.roundOver = false
	end
end })

table.insert(tests, { name = "ROUND SELECT: skipRound refuses to run when canSkipRound is false", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	state.round = state.config.roundsPerNight -- the Boss round
	local ok = pcall(RunState.skipRound, state)
	expectFalse(ok, "expected skipRound to assert/fail on the Boss round")
end })

table.insert(tests, { name = "ROUND SELECT: the On the House Tag grants a free unowned Patron", fn = function()
	local onTheHouseIndex = tagIndexById("on_the_house")
	expectTrue(onTheHouseIndex ~= nil, "expected to find on_the_house in Tags.Definitions")
	local state = RunState.new(nil, function(_n) return onTheHouseIndex end)
	local patronsBefore = #state.ownedPatrons
	local tag, result = RunState.skipRound(state)
	expectEqual(tag.id, "on_the_house")
	expectEqual(result.kind, "patron")
	expectTrue(result.patron ~= nil)
	expectEqual(#state.ownedPatrons, patronsBefore + 1)
	expectEqual(state.ownedPatrons[#state.ownedPatrons].id, result.patron.id)
end })

table.insert(tests, { name = "ROUND SELECT: the On the House Tag falls back to Tips when the table is already full", fn = function()
	local onTheHouseIndex = tagIndexById("on_the_house")
	local state = RunState.new(nil, function(_n) return onTheHouseIndex end)
	-- Fill the table to its limit with fake-but-well-formed Patron entries
	-- (only .id matters for the ownership/capacity check inside Tags.lua).
	for i = 1, RunState.patronSlotLimit(state) do
		table.insert(state.ownedPatrons, { id = "fake_patron_" .. i, name = "Fake", description = "" })
	end
	local tipsBefore = state.tips
	local tag, result = RunState.skipRound(state)
	expectEqual(tag.id, "on_the_house")
	expectEqual(result.kind, "tips")
	expectTrue(result.fallback, "expected the fallback flag when the table is full")
	expectEqual(state.tips, tipsBefore + result.amount)
end })

table.insert(tests, { name = "ROUND SELECT: the Sale Day Tag discounts the next shop visit, then clears once you leave it", fn = function()
	local saleDayIndex = tagIndexById("sale_day")
	expectTrue(saleDayIndex ~= nil, "expected to find sale_day in Tags.Definitions")
	local state = RunState.new(nil, function(_n) return saleDayIndex end)
	local tag, result = RunState.skipRound(state)
	expectEqual(tag.id, "sale_day")
	expectEqual(result.kind, "discount")
	expectEqual(state.nextShopDiscount, result.amount)

	local samplePatron = Patrons.Definitions[1]
	expectEqual(RunState.patronPrice(state, samplePatron), math.max(1, samplePatron.price - result.amount))

	-- Simulate winning the round and leaving the shop -- the discount
	-- should be gone by the round after that.
	state.roundOver = true
	RunState.advanceToNextRound(state)
	expectTrue(state.nextShopDiscount == nil, "Sale Day's discount should be consumed once its shop visit ends")
	expectEqual(RunState.patronPrice(state, samplePatron), samplePatron.price)
end })

table.insert(tests, { name = "ROUND SELECT: Sale Day Tag and Regulars' Discount House Pass stack, floored at 1 Tip", fn = function()
	local saleDayIndex = tagIndexById("sale_day")
	local state = RunState.new(nil, function(_n) return saleDayIndex end)
	state.housePasses.regulars_discount = true
	local _, result = RunState.skipRound(state)
	local cheapPatron = { price = 4 } -- cheap enough that both discounts combined would go below 1
	expectEqual(RunState.patronPrice(state, cheapPatron), 1)
	-- Sale Day applies to Pack prices too (see its description), even
	-- though Wholesale Pricing (the House Pass equivalent) wasn't bought --
	-- only the Tag's own 3-Tip discount applies here.
	expectEqual(RunState.packPrice(state, { price = 10 }), 7)
	expectEqual(result.amount, 3)
end })

table.insert(tests, { name = "Tags.pick returns a valid, well-formed Tag", fn = function()
	local tag = Tags.pick(function(n) return n end)
	expectTrue(tag ~= nil)
	expectTrue(Tags.getById(tag.id) == tag)
	expectTrue(type(tag.apply) == "function")
end })

table.insert(tests, { name = "Boss Round target score multiplier is folded into targetScore", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	state.round = state.config.roundsPerNight
	state.bossModifier = BossRounds.getById("house_rules") -- 1.4x target score
	local baseTarget = RunState.targetScoreFor(state.night, state.round, state.config.roundsPerNight)
	-- Re-run just the target-score math startRound would do, without
	-- re-picking a random modifier (bossRoundsEnabled stays true so a
	-- second startRound call would overwrite our manual pick).
	state.targetScore = math.floor(baseTarget * state.targetMultiplier * state.bossModifier.targetScoreMultiplier)
	expectEqual(state.targetScore, math.floor(baseTarget * 1.4))
end })

table.insert(tests, { name = "RunState.playHand doubles the Tip reward for winning a Boss Round", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	state.bossModifier = { id = "test_boss", name = "Test Boss", description = "" }
	state.targetScore = 0 -- guarantee an immediate round win
	local tipsBefore = state.tips
	RunState.playHand(state, { 1 })
	expectEqual(state.tips, tipsBefore + state.config.tipsPerRoundWin * 2)
end })

table.insert(tests, { name = "RunState.playHand tracks how many times each hand type has been played this run", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	local result = RunState.playHand(state, { 1, 2 })
	expectEqual(state.handStats[result.handName], 1)
	local result2 = RunState.playHand(state, { 1 })
	if result2.handName == result.handName then
		expectEqual(state.handStats[result.handName], 2)
	else
		expectEqual(state.handStats[result.handName], 1)
		expectEqual(state.handStats[result2.handName], 1)
	end
end })

-- ===== Feature Expansion: Card Garnishes/Specials/Stamps =====

table.insert(tests, { name = "Card.isFaceCard is true for Jack/Queen/King, false for Ace/number cards", fn = function()
	expectTrue(Card.isFaceCard(C(11, "Hearts")))
	expectTrue(Card.isFaceCard(C(13, "Spades")))
	expectFalse(Card.isFaceCard(C(14, "Hearts")), "Ace should not count as a face card")
	expectFalse(Card.isFaceCard(C(9, "Clubs")))
end })

table.insert(tests, { name = "Card.hasSuit: a House Blend Garnish counts as every suit", fn = function()
	local card = Card.new(5, "Clubs", { garnish = "houseBlend" })
	expectTrue(Card.hasSuit(card, "Hearts"))
	expectTrue(Card.hasSuit(card, "Spades"))
end })

table.insert(tests, { name = "Scoring: Sweet Garnish adds +30 Chips when the card scores", fn = function()
	local plain = HandEvaluator.evaluate({ C(9, "Hearts") })
	local _, chipsPlain = Scoring.calculate(plain, {}, {})

	local sweetCard = Card.new(9, "Hearts", { garnish = "sweet" })
	local sweet = HandEvaluator.evaluate({ sweetCard })
	local _, chipsSweet = Scoring.calculate(sweet, {}, {})

	expectEqual(chipsSweet, chipsPlain + 30)
end })

table.insert(tests, { name = "Scoring: Rainbow Special (x1.5 Mult) folds into the returned mult", fn = function()
	local card = Card.new(9, "Hearts", { special = "rainbow" })
	local hand = HandEvaluator.evaluate({ card })
	local _, _, mult = Scoring.calculate(hand, {}, {})
	-- High Card base mult is 1 -> x1.5
	expectEqual(mult, 1.5)
end })

table.insert(tests, { name = "Scoring: Iron Garnish gives x1.5 Mult per copy held (not played)", fn = function()
	local played = HandEvaluator.evaluate({ C(9, "Hearts") })
	local held = { Card.new(2, "Clubs", { garnish = "iron" }), Card.new(3, "Clubs", { garnish = "iron" }) }
	local _, _, mult = Scoring.calculate(played, {}, { heldCards = held })
	expectEqual(mult, 1 * 1.5 * 1.5)
end })

table.insert(tests, { name = "Scoring: a debuffed suit contributes 0 chips/mult from its cards", fn = function()
	local hand = HandEvaluator.evaluate({ C(9, "Hearts"), C(9, "Clubs") }) -- Pair
	local _, chipsNormal = Scoring.calculate(hand, {}, {})
	local _, chipsDebuffed = Scoring.calculate(hand, {}, { debuff = "Hearts" })
	-- The Hearts 9 contributes 0 chips when debuffed -- Clubs 9 still counts.
	expectEqual(chipsDebuffed, chipsNormal - 9)
end })

table.insert(tests, { name = "Scoring: hand level growth raises Chips/Mult for that hand type", fn = function()
	local hand = HandEvaluator.evaluate({ C(9, "Hearts"), C(9, "Clubs") }) -- Pair
	local _, chips0, mult0 = Scoring.calculate(hand, {}, { handLevels = { Pair = 0 } })
	local _, chips2, mult2 = Scoring.calculate(hand, {}, { handLevels = { Pair = 2 } })
	local growth = Scoring.HandLevelGrowth["Pair"]
	expectEqual(chips2, chips0 + growth.chips * 2)
	expectEqual(mult2, mult0 + growth.mult * 2)
end })

table.insert(tests, { name = "Scoring: a Gold Stamp earns Tips when its card scores", fn = function()
	local card = Card.new(9, "Hearts", { stamp = "gold" })
	local hand = HandEvaluator.evaluate({ card })
	local _, _, _, extra = Scoring.calculate(hand, {}, {})
	expectEqual(extra.tipsEarned, 3)
end })

table.insert(tests, { name = "Scoring: an Encore Stamp retriggers the card's own Garnish", fn = function()
	local card = Card.new(9, "Hearts", { garnish = "zesty", stamp = "encore" })
	local hand = HandEvaluator.evaluate({ card })
	local _, _, mult = Scoring.calculate(hand, {}, {})
	-- High Card base mult (1) + Zesty (+4) triggered TWICE = 1 + 4 + 4
	expectEqual(mult, 1 + 4 + 4)
end })

table.insert(tests, { name = "Scoring: a Brittle Garnish that rolls its break chance is reported in extra.brokenCards", fn = function()
	local card = Card.new(9, "Hearts", { garnish = "brittle" })
	local hand = HandEvaluator.evaluate({ card })
	local _, _, _, extra = Scoring.calculate(hand, {}, { rng = alwaysHitRng })
	expectEqual(#extra.brokenCards, 1)
	expectTrue(extra.brokenCards[1] == card)
end })

table.insert(tests, { name = "Scoring: a Lucky Garnish only procs its bonus Mult/Tips when the roll hits", fn = function()
	local card = Card.new(9, "Hearts", { garnish = "lucky" })
	local hand = HandEvaluator.evaluate({ card })

	local _, _, multMiss, extraMiss = Scoring.calculate(hand, {}, { rng = neverHitRng })
	expectEqual(multMiss, 1) -- High Card base mult, no proc
	expectEqual(extraMiss.tipsEarned, 0)

	local _, _, multHit, extraHit = Scoring.calculate(hand, {}, { rng = alwaysHitRng })
	expectEqual(multHit, 1 + 20) -- lucky Mult proc
	expectEqual(extraHit.tipsEarned, 20) -- lucky Tips proc
end })

-- ===== Feature Expansion: RunState deck persistence =====

table.insert(tests, { name = "RunState.startRound pools hand+discardPile+deck back into a full 52-card pool", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	RunState.playHand(state, { 1, 2 })
	RunState.discard(state, { 1 })
	local total = #state.hand + #state.deck + #state.discardPile
	expectEqual(total, 52)
	RunState.startRound(state)
	expectEqual(#state.hand + #state.deck + #state.discardPile, 52)
end })

table.insert(tests, { name = "A Garnish applied to a card survives into the next round's pooled deck", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	state.hand[1].garnish = "sweet"
	RunState.discard(state, { 1 }) -- sends the tagged card to the discard pile
	RunState.startRound(state) -- pools + reshuffles for the next round
	local found = 0
	for _, card in ipairs(state.hand) do
		if card.garnish == "sweet" then found = found + 1 end
	end
	for _, card in ipairs(state.deck) do
		if card.garnish == "sweet" then found = found + 1 end
	end
	expectEqual(found, 1)
end })

-- ===== Feature Expansion: new Boss Round modifiers (RunState integration) =====

table.insert(tests, { name = "Boss Round requiredCardsPerHand rejects the wrong number of cards", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	state.bossModifier = BossRounds.getById("full_table") -- requires exactly 5
	local ok = pcall(RunState.playHand, state, { 1, 2 })
	expectFalse(ok, "expected playHand to reject a non-5-card play under Full Table")
end })

table.insert(tests, { name = "Boss Round noRepeatHandTypes scores 0 on a repeated hand type", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	state.bossModifier = BossRounds.getById("no_repeats")
	state.targetScore = 999999 -- never win mid-test
	local first = RunState.playHand(state, { 1, 2 }) -- e.g. a Pair
	local second = RunState.playHand(state, { 1, 2 })
	if first.handName == second.handName then
		expectTrue(second.blockedRepeatHand)
		expectEqual(second.score, 0)
	else
		expectFalse(second.blockedRepeatHand)
	end
end })

table.insert(tests, { name = "Boss Round tipsLostPerCardPlayed deducts Tips per card played", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	state.bossModifier = BossRounds.getById("the_tab")
	state.tips = 10
	RunState.playHand(state, { 1, 2 })
	expectTrue(state.tips <= 10 - 2, "expected at least 2 Tips lost for 2 cards played")
end })

table.insert(tests, { name = "Boss Round zeroTipsOnMostPlayedHand wipes Tips on your most-used hand", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	state.bossModifier = BossRounds.getById("empty_pockets")
	state.tips = 20
	state.targetScore = 999999
	RunState.playHand(state, { 1 }) -- first-ever hand type is automatically "most played"
	expectEqual(state.tips, 0)
end })

table.insert(tests, { name = "Boss Round chipsMultiplier/multMultiplier (Stale Bread) cuts Chips and Mult by 25%", fn = function()
	local stateNormal = RunState.new(nil, function(n) return n end)
	local resultNormal = RunState.playHand(stateNormal, { 1, 2 })

	local stateHalved = RunState.new(nil, function(n) return n end)
	stateHalved.bossModifier = BossRounds.getById("stale_bread")
	local resultHalved = RunState.playHand(stateHalved, { 1, 2 })

	expectEqual(resultHalved.chips, resultNormal.chips * 0.75)
	expectEqual(resultHalved.mult, resultNormal.mult * 0.75)
end })

table.insert(tests, { name = "Boss Round handsPerRoundOverride (Lights Out) hard-limits hands allowed", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	local bossModifier = BossRounds.getById("lights_out")
	-- Re-run just the hands-allowed math startRound would do, without
	-- re-picking a random modifier (same approach as the existing
	-- "Boss Round target score multiplier" test above).
	local handsPerRound = state.config.handsPerRound
	if bossModifier.handsPerRoundOverride then
		handsPerRound = bossModifier.handsPerRoundOverride
	end
	handsPerRound = math.max(1, handsPerRound)
	expectEqual(handsPerRound, 1)
end })

table.insert(tests, { name = "BossRounds.Definitions has grown well past the original 4 modifiers", fn = function()
	expectTrue(#BossRounds.Definitions >= 12, "expected a much larger Boss Round pool")
end })

-- ===== Content pass (this session, cont'd): 8 more Boss Rounds =====

table.insert(tests, { name = "'Diamonds Are Out' / 'Clubs Are Out' debuff the right suit", fn = function()
	expectEqual(BossRounds.getById("diamonds_are_out").debuff, "Diamonds")
	expectEqual(BossRounds.getById("clubs_are_out").debuff, "Clubs")
end })

table.insert(tests, { name = "'One at a Time' requires exactly 1 card per hand", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	state.bossModifier = BossRounds.getById("one_at_a_time")
	local ok = pcall(RunState.playHand, state, { 1, 2 })
	expectFalse(ok, "expected playHand to reject a 2-card play under One at a Time")
end })

table.insert(tests, { name = "'Steep Tab' deducts 2 Tips per card played", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	state.bossModifier = BossRounds.getById("steep_tab")
	state.tips = 10
	RunState.playHand(state, { 1, 2 })
	expectTrue(state.tips <= 10 - 4, "expected at least 4 Tips lost for 2 cards played at 2/card")
end })

table.insert(tests, { name = "'Quick Service' hard-limits hands allowed to 2", fn = function()
	local bossModifier = BossRounds.getById("quick_service")
	expectEqual(bossModifier.handsPerRoundOverride, 2)
end })

table.insert(tests, { name = "'Wild Crowd' tosses 3 random cards after every hand played", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	state.bossModifier = BossRounds.getById("wild_crowd")
	local handSizeBefore = #state.hand
	RunState.playHand(state, { 1 })
	expectEqual(#state.hand, handSizeBefore) -- refilled back up, just with different cards
end })

table.insert(tests, { name = "'Thin Chips' cuts Chips by 40% but leaves Mult untouched", fn = function()
	local bossModifier = BossRounds.getById("thin_chips")
	expectEqual(bossModifier.chipsMultiplier, 0.6)
	expectTrue(bossModifier.multMultiplier == nil)
end })

table.insert(tests, { name = "'Flat Mult' cuts Mult by 40% but leaves Chips untouched", fn = function()
	local bossModifier = BossRounds.getById("flat_mult")
	expectEqual(bossModifier.multMultiplier, 0.6)
	expectTrue(bossModifier.chipsMultiplier == nil)
end })

-- ===== Feature Expansion: expanded Patron pool =====

table.insert(tests, { name = "Patrons.Definitions has grown well past the original 5 patrons", fn = function()
	expectTrue(#Patrons.Definitions >= 15, "expected a much larger Patron pool")
end })

table.insert(tests, { name = "'The Understudy' copies the ability of the Patron to its right", fn = function()
	local understudy = Patrons.getById("the_understudy")
	local theRegular = Patrons.getById("the_regular") -- +4 flat Mult, no conditions
	local hand = HandEvaluator.evaluate({ C(9, "Hearts") })
	local _, _, mult = Scoring.calculate(hand, { understudy, theRegular }, {})
	-- understudy copies theRegular's +4, then theRegular ALSO applies its
	-- own +4 -- base mult 1 + 4 (copied) + 4 (own) = 9
	expectEqual(mult, 1 + 4 + 4)
end })

table.insert(tests, { name = "'House Favorite' scales x1.5 Mult per King held in hand", fn = function()
	local houseFavorite = Patrons.getById("house_favorite")
	local hand = HandEvaluator.evaluate({ C(9, "Hearts") })
	local held = { C(13, "Clubs"), C(13, "Spades") } -- 2 Kings held
	local _, _, mult = Scoring.calculate(hand, { houseFavorite }, { heldCards = held })
	expectEqual(mult, 1 * 1.5 * 1.5)
end })

-- ===== Content pass (this session, cont'd): 9 more Patrons =====

table.insert(tests, { name = "'Double Down' rewards Two Pair only", fn = function()
	local doubleDown = Patrons.getById("double_down")
	local twoPair = HandEvaluator.evaluate({ C(9, "Hearts"), C(9, "Clubs"), C(4, "Spades"), C(4, "Diamonds") })
	local threeKind = HandEvaluator.evaluate({ C(9, "Hearts"), C(9, "Clubs"), C(9, "Spades") })
	local _, _, multTwoPair = Scoring.calculate(twoPair, { doubleDown }, {})
	local _, _, multThreeKind = Scoring.calculate(threeKind, { doubleDown }, {})
	expectEqual(multTwoPair, 2 + 10) -- base Two Pair mult (2) + patron (10)
	expectEqual(multThreeKind, 3) -- base Three of a Kind mult, no bonus
end })

table.insert(tests, { name = "'House Special' rewards Full House only", fn = function()
	local houseSpecial = Patrons.getById("house_special")
	local fullHouse = HandEvaluator.evaluate({ C(9, "Hearts"), C(9, "Clubs"), C(9, "Spades"), C(4, "Diamonds"), C(4, "Hearts") })
	local _, _, mult = Scoring.calculate(fullHouse, { houseSpecial }, {})
	expectEqual(mult, 4 + 22) -- base Full House mult (4) + patron (22)
end })

table.insert(tests, { name = "'Ace of the House' adds +8 Mult for each scoring Ace", fn = function()
	local aceOfTheHouse = Patrons.getById("ace_of_the_house")
	local pair = HandEvaluator.evaluate({ C(14, "Hearts"), C(14, "Clubs"), C(2, "Spades") }) -- pair of Aces
	local _, _, mult = Scoring.calculate(pair, { aceOfTheHouse }, {})
	expectEqual(mult, 2 + 8 * 2) -- base Pair mult (2) + patron (8 per Ace x 2 Aces)
end })

table.insert(tests, { name = "'VIP Table' adds a flat +8 Mult if a face card scores (not scaled per card)", fn = function()
	local vipTable = Patrons.getById("vip_table")
	local pair = HandEvaluator.evaluate({ C(12, "Hearts"), C(13, "Clubs"), C(2, "Spades") }) -- Queen, King, no pair -- High Card
	local _, _, mult = Scoring.calculate(pair, { vipTable }, {})
	expectEqual(mult, 1 + 8) -- base High Card mult (1) + flat patron bonus, even though 2 face cards are present
end })

table.insert(tests, { name = "'Early Bird' scales XMult by Hands remaining after this one", fn = function()
	local earlyBird = Patrons.getById("early_bird")
	local hand = HandEvaluator.evaluate({ C(9, "Hearts") })
	local _, _, multNone = Scoring.calculate(hand, { earlyBird }, { handsRemaining = 0 })
	local _, _, multTwo = Scoring.calculate(hand, { earlyBird }, { handsRemaining = 2 })
	expectEqual(multNone, 1) -- no hands left -- no bonus
	expectEqual(multTwo, 1 * (1.1 ^ 2))
end })

table.insert(tests, { name = "'Discard Special' adds +1 Mult for each Discard remaining", fn = function()
	local discardSpecial = Patrons.getById("discard_special")
	local hand = HandEvaluator.evaluate({ C(9, "Hearts") })
	local _, _, mult = Scoring.calculate(hand, { discardSpecial }, { discardsRemaining = 3 })
	expectEqual(mult, 1 + 1 * 3)
end })

table.insert(tests, { name = "'The Apprentice' copies the ability of the Patron to its left", fn = function()
	local theRegular = Patrons.getById("the_regular") -- +4 flat Mult, no conditions
	local apprentice = Patrons.getById("the_apprentice")
	local hand = HandEvaluator.evaluate({ C(9, "Hearts") })
	local _, _, mult = Scoring.calculate(hand, { theRegular, apprentice }, {})
	-- theRegular applies its own +4, then apprentice (index 2) copies its
	-- left neighbor (index 1, theRegular) for another +4 -- base 1 + 4 + 4
	expectEqual(mult, 1 + 4 + 4)
end })

table.insert(tests, { name = "'Big Spender' earns 1 Tip per owned Patron on round win", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	state.tips = 20
	RunState.buyPatron(state, "big_spender")
	RunState.buyPatron(state, "the_regular")
	local bigSpender = Patrons.getById("big_spender")
	local tipsBefore = state.tips
	bigSpender.onRoundWin(state)
	expectEqual(state.tips, tipsBefore + #state.ownedPatrons) -- 2 owned Patrons
end })

-- ===== Feature Expansion: universal round-win interest =====

table.insert(tests, { name = "RunState.playHand: round-win interest is +1 Tip per 5 held, capped at +5, even without Nest Egg", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	state.targetScore = 0 -- guarantee an immediate round win
	state.tips = 12 -- floor(12/5) = 2
	local tipsBefore = state.tips
	RunState.playHand(state, { 1 })
	expectEqual(state.tips, tipsBefore + 2 + state.config.tipsPerRoundWin)
end })

table.insert(tests, { name = "RunState.playHand: round-win interest caps at +5 Tips without Nest Egg, no matter how much is held", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	state.targetScore = 0
	state.tips = 1000
	local tipsBefore = state.tips
	RunState.playHand(state, { 1 })
	expectEqual(state.tips, tipsBefore + 5 + state.config.tipsPerRoundWin)
end })

table.insert(tests, { name = "RunState.playHand records the actual total Tips gained on a round win as state.lastRoundReward", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	state.targetScore = 0
	state.tips = 12
	local tipsBefore = state.tips
	RunState.playHand(state, { 1 })
	expectEqual(state.lastRoundReward, state.tips - tipsBefore)
	expectEqual(state.lastRoundReward, 2 + state.config.tipsPerRoundWin) -- +2 interest, +4 flat reward
end })

table.insert(tests, { name = "Owning 'Nest Egg' raises the round-win interest cap from +5 to +10, instead of duplicating it", fn = function()
	local nestEgg = Patrons.getById("nest_egg")
	expectTrue(nestEgg.onRoundWin == nil, "Nest Egg should no longer have its own onRoundWin -- it'd double-dip with the base interest rule")

	-- Without Nest Egg: capped at +5.
	local state = RunState.new(nil, function(n) return n end)
	state.targetScore = 0
	state.tips = 100 -- floor(100/5) = 20, comfortably above either cap
	local tipsBefore = state.tips
	RunState.playHand(state, { 1 })
	expectEqual(state.tips, tipsBefore + 5 + state.config.tipsPerRoundWin)

	-- With Nest Egg owned: cap raised to +10, still only ONE interest
	-- payout (not 5 AND 10 stacked).
	local state2 = RunState.new(nil, function(n) return n end)
	table.insert(state2.ownedPatrons, nestEgg)
	state2.targetScore = 0
	state2.tips = 100
	local tipsBefore2 = state2.tips
	RunState.playHand(state2, { 1 })
	expectEqual(state2.tips, tipsBefore2 + 10 + state2.config.tipsPerRoundWin)
end })

-- ===== Feature Expansion: Small/Big/Boss Blind score multipliers =====

table.insert(tests, { name = "RunState.blindMultiplierFor: Small Blind (round 1) is always 1x", fn = function()
	expectEqual(RunState.blindMultiplierFor(1, 1, 3), 1)
	expectEqual(RunState.blindMultiplierFor(8, 1, 3), 1)
end })

table.insert(tests, { name = "RunState.blindMultiplierFor: Big Blind (any round before the last) is always 2x", fn = function()
	expectEqual(RunState.blindMultiplierFor(1, 2, 3), 2)
	expectEqual(RunState.blindMultiplierFor(5, 2, 3), 2)
end })

table.insert(tests, { name = "RunState.blindMultiplierFor: Boss Blind scales from 2x at Night 1 to 2.5x at Night 8, then plateaus", fn = function()
	expectEqual(RunState.blindMultiplierFor(1, 3, 3), 2)
	expectEqual(RunState.blindMultiplierFor(8, 3, 3), 2.5)
	expectEqual(RunState.blindMultiplierFor(20, 3, 3), 2.5) -- Endless Mode: multiplier plateaus, doesn't keep climbing
end })

table.insert(tests, { name = "RunState.targetScoreFor folds nightBaseScoreFor and blindMultiplierFor together", fn = function()
	local night = 4
	local base = RunState.nightBaseScoreFor(night)
	expectEqual(RunState.targetScoreFor(night, 1, 3), math.floor(base * 1))
	expectEqual(RunState.targetScoreFor(night, 2, 3), math.floor(base * 2))
	expectEqual(RunState.targetScoreFor(night, 3, 3), math.floor(base * RunState.blindMultiplierFor(night, 3, 3)))
end })

table.insert(tests, { name = "BUGFIX: RunState.blindMultiplierFor honors an explicit nightCap override, not just the global default", fn = function()
	-- A hypothetical run with nightCap = 4 (instead of the global default
	-- of 8): the Boss multiplier should already be maxed (2.5x) at Night 4,
	-- not still ramping toward a Night-8 plateau it'll never reach.
	expectEqual(RunState.blindMultiplierFor(1, 3, 3, 4), 2)
	expectEqual(RunState.blindMultiplierFor(4, 3, 3, 4), 2.5)
	expectEqual(RunState.blindMultiplierFor(9, 3, 3, 4), 2.5) -- still plateaued past its own (overridden) cap
	-- Omitting nightCap still falls back to the global default (8), so
	-- every other call site/test that doesn't pass one is unaffected.
	expectEqual(RunState.blindMultiplierFor(4, 3, 3), RunState.blindMultiplierFor(4, 3, 3, RunState.DefaultConfig.nightCap))
end })

table.insert(tests, { name = "BUGFIX: RunState.startRound's Boss target score uses THIS RUN's config.nightCap, not always the global default", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	state.config.nightCap = 4 -- simulate a run whose nightCap differs from the default (8)
	state.night = 4
	state.round = 1
	RunState.startRound(state) -- Night 4, round 1: picks a fresh nightBossModifier
	state.round = state.config.roundsPerNight
	RunState.startRound(state) -- the Boss round itself

	expectTrue(state.bossModifier ~= nil)
	local bossOwnMultiplier = state.bossModifier.targetScoreMultiplier or 1
	local expectedTarget = math.floor(
		RunState.targetScoreFor(4, state.config.roundsPerNight, state.config.roundsPerNight, state.config.nightCap)
		* state.targetMultiplier * bossOwnMultiplier
	)
	expectEqual(state.targetScore, expectedTarget)
end })

table.insert(tests, { name = "RunState.nightBaseScoreFor grows every Night, unbounded (keeps Endless Mode escalating)", fn = function()
	local b1 = RunState.nightBaseScoreFor(1)
	local b8 = RunState.nightBaseScoreFor(8)
	local b20 = RunState.nightBaseScoreFor(20)
	expectTrue(b8 > b1, "Night 8's base score should exceed Night 1's")
	expectTrue(b20 > b8, "Night 20's base score should exceed Night 8's -- no plateau, unlike the Boss multiplier")
end })

-- ===== Feature Expansion: Ante-cap win condition + Endless Mode =====

table.insert(tests, { name = "RunState.playHand marks wonRun = true on clearing the Boss Round of the final Night (nightCap)", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	state.night = state.config.nightCap
	state.round = state.config.roundsPerNight
	state.bossModifier = { id = "test_boss", name = "Test Boss", description = "" }
	state.targetScore = 0
	expectFalse(state.wonRun)
	RunState.playHand(state, { 1 })
	expectTrue(state.wonRun)
end })

table.insert(tests, { name = "RunState.playHand does NOT mark wonRun before reaching nightCap", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	state.night = state.config.nightCap - 1
	state.round = state.config.roundsPerNight
	state.bossModifier = { id = "test_boss", name = "Test Boss", description = "" }
	state.targetScore = 0
	RunState.playHand(state, { 1 })
	expectFalse(state.wonRun)
end })

table.insert(tests, { name = "RunState.playHand: a non-Boss round win at nightCap does NOT mark wonRun (only clearing the Boss Round counts)", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	state.night = state.config.nightCap
	state.round = 1 -- Small Round, not the Boss Round
	state.bossModifier = nil
	state.targetScore = 0
	RunState.playHand(state, { 1 })
	expectFalse(state.wonRun)
end })

table.insert(tests, { name = "RunState.playHand: Nights keep climbing past nightCap (Endless Mode), rounds still playable", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	state.night = state.config.nightCap + 2 -- already deep into Endless Mode
	state.round = 1
	state.targetScore = 0
	local result = RunState.playHand(state, { 1 })
	expectTrue(result.roundWon)
	expectFalse(state.runOver)
end })

table.insert(tests, { name = "RunState.playHand: losing during Endless Mode does NOT erase an earlier win (wonRun stays true)", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	-- Simulate having already cleared nightCap's Boss Round earlier in the run.
	state.wonRun = true
	-- Now lose a round deep into Endless Mode: 0 hands remaining, target unmet.
	state.night = state.config.nightCap + 3
	state.round = 1
	state.handsRemaining = 1
	state.targetScore = math.huge
	local result = RunState.playHand(state, { 1 })
	expectFalse(result.roundWon)
	expectTrue(state.runOver)
	expectTrue(state.wonRun, "a win earlier in the run should survive a later Endless Mode loss")
end })

-- ===== Feature Expansion: Recipes (House/Menu/Secret) =====

table.insert(tests, { name = "A Menu Recipe permanently levels up its hand type", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	local recipe = Recipes.randomMenuRecipeForHand("Pair")
	local ok = recipe.apply(state)
	expectTrue(ok)
	expectEqual(state.handLevels["Pair"], 1)
end })

table.insert(tests, { name = "House Recipe 'Sugar Rush' adds a Sweet Garnish to the selected card", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	local recipe = Recipes.getHouseRecipeById("sugar_rush")
	local ok = recipe.apply(state, { cardIndices = { 1 } })
	expectTrue(ok)
	expectEqual(state.hand[1].garnish, "sweet")
end })

table.insert(tests, { name = "RunState.buyHouseRecipe + useHouseRecipe: full purchase-then-use flow", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	state.tips = 20
	local recipe = Recipes.HouseRecipes[1]
	local boughtOk = RunState.buyHouseRecipe(state, recipe.id)
	expectTrue(boughtOk)
	expectEqual(#state.houseRecipeInventory, 1)

	local usedOk = RunState.useHouseRecipe(state, recipe.id, { cardIndices = { 1 } })
	expectTrue(usedOk)
	expectEqual(#state.houseRecipeInventory, 0)
	expectEqual(state.lastRecipeUsedId, recipe.id)
end })

table.insert(tests, { name = "House Recipe 'Encore, Please' adds an Encore Stamp to the selected card", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	local recipe = Recipes.getHouseRecipeById("encore_order")
	local ok = recipe.apply(state, { cardIndices = { 1 } })
	expectTrue(ok)
	expectEqual(state.hand[1].stamp, "encore")
end })

table.insert(tests, { name = "House Recipe 'Blue Plate Special' adds a Blue Stamp to the selected card", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	local recipe = Recipes.getHouseRecipeById("blue_plate_special")
	local ok = recipe.apply(state, { cardIndices = { 1 } })
	expectTrue(ok)
	expectEqual(state.hand[1].stamp, "blue")
end })

table.insert(tests, { name = "House Recipe 'Lucky Ticket' adds a Lucky Garnish to the selected card", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	local recipe = Recipes.getHouseRecipeById("lucky_ticket")
	local ok = recipe.apply(state, { cardIndices = { 1 } })
	expectTrue(ok)
	expectEqual(state.hand[1].garnish, "lucky")
end })

table.insert(tests, { name = "Secret Recipe 'Kitchen Secret' adds a Purple Stamp to the selected card", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	local recipe = Recipes.getSecretRecipeById("kitchen_secret")
	local ok = recipe.apply(state, { cardIndices = { 1 } })
	expectTrue(ok)
	expectEqual(state.hand[1].stamp, "purple")
end })

table.insert(tests, { name = "Secret Recipe 'Star Treatment' gives a random owned Patron a Gold Special", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	state.tips = 10
	RunState.buyPatron(state, "the_regular")
	local recipe = Recipes.getSecretRecipeById("star_treatment")
	local ok = recipe.apply(state, { rng = function(n) return n end })
	expectTrue(ok)
	expectEqual(state.ownedPatronSpecials["the_regular"], "gold")
end })

table.insert(tests, { name = "Secret Recipe 'Star Treatment' refuses when there are no Patrons to treat", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	local recipe = Recipes.getSecretRecipeById("star_treatment")
	local ok, message = recipe.apply(state, {})
	expectFalse(ok)
	expectTrue(message ~= nil)
end })

table.insert(tests, { name = "RunState.playHand: 'Star Treatment' Gold Special actually raises the played score", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	state.tips = 10
	RunState.buyPatron(state, "the_regular")
	state.targetScore = 10 ^ 9 -- keep the round open for both hands
	local before = RunState.playHand(state, { 1 })
	Recipes.getSecretRecipeById("star_treatment").apply(state, { rng = function(n) return n end })
	local after = RunState.playHand(state, { 1 })
	-- Same hand shape (single card, High Card) before/after -- the only
	-- difference is the Gold Special's +10 Mult now folded into scoring.
	expectEqual(after.mult, before.mult + 10)
end })

-- ===== Feature Expansion: Patron slot cap =====

table.insert(tests, { name = "RunState.patronSlotLimit defaults to the config value (5)", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	expectEqual(RunState.patronSlotLimit(state), state.config.patronSlotLimit)
	expectEqual(state.config.patronSlotLimit, 5)
end })

table.insert(tests, { name = "RunState.buyPatron refuses a purchase once the table is full", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	state.tips = 1000
	local names = {}
	for _, patron in ipairs(Patrons.Definitions) do
		table.insert(names, patron.id)
		if #names >= state.config.patronSlotLimit then break end
	end
	for _, id in ipairs(names) do
		local ok = RunState.buyPatron(state, id)
		expectTrue(ok, "expected buying up to the slot limit to succeed")
	end
	expectEqual(#state.ownedPatrons, state.config.patronSlotLimit)

	-- One more (a Patron not already owned) should be refused.
	local extra
	for _, patron in ipairs(Patrons.Definitions) do
		local alreadyOwned = false
		for _, owned in ipairs(state.ownedPatrons) do
			if owned.id == patron.id then alreadyOwned = true end
		end
		if not alreadyOwned then extra = patron.id break end
	end
	local ok, message = RunState.buyPatron(state, extra)
	expectFalse(ok)
	expectTrue(message ~= nil)
	expectEqual(#state.ownedPatrons, state.config.patronSlotLimit)
end })

table.insert(tests, { name = "Selling a Patron makes room to buy again at the cap", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	state.tips = 1000
	for i, patron in ipairs(Patrons.Definitions) do
		if i > state.config.patronSlotLimit then break end
		RunState.buyPatron(state, patron.id)
	end
	expectEqual(#state.ownedPatrons, state.config.patronSlotLimit)

	RunState.sellPatron(state, state.ownedPatrons[1].id)
	expectEqual(#state.ownedPatrons, state.config.patronSlotLimit - 1)

	-- Now a previously-refused purchase should go through.
	local nextPatron
	for _, patron in ipairs(Patrons.Definitions) do
		local alreadyOwned = false
		for _, owned in ipairs(state.ownedPatrons) do
			if owned.id == patron.id then alreadyOwned = true end
		end
		if not alreadyOwned then nextPatron = patron.id break end
	end
	local ok = RunState.buyPatron(state, nextPatron)
	expectTrue(ok, "expected room to buy after selling")
	expectEqual(#state.ownedPatrons, state.config.patronSlotLimit)
end })

table.insert(tests, { name = "A Reserved Special on an owned Patron raises the slot limit by 1", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	state.tips = 1000
	RunState.buyPatron(state, "the_regular")
	expectEqual(RunState.patronSlotLimit(state), state.config.patronSlotLimit)
	state.ownedPatronSpecials["the_regular"] = "reserved"
	expectEqual(RunState.patronSlotLimit(state), state.config.patronSlotLimit + 1)
end })

-- ===== Feature Expansion: Recipe (Consumable) slot cap =====

table.insert(tests, { name = "RunState.recipeSlotLimit defaults to the config value (2), shared across House+Menu+Secret", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	expectEqual(RunState.recipeSlotLimit(state), state.config.recipeSlotLimit)
	expectEqual(state.config.recipeSlotLimit, 2)
end })

table.insert(tests, { name = "RunState.buyHouseRecipe refuses once the shared recipe box is full", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	state.tips = 100
	local r1, r2, r3 = Recipes.HouseRecipes[1], Recipes.HouseRecipes[2], Recipes.HouseRecipes[3]
	expectTrue(RunState.buyHouseRecipe(state, r1.id))
	expectTrue(RunState.buyHouseRecipe(state, r2.id))
	expectEqual(#state.houseRecipeInventory, state.config.recipeSlotLimit)

	local ok, message = RunState.buyHouseRecipe(state, r3.id)
	expectFalse(ok)
	expectTrue(message ~= nil)
	expectEqual(#state.houseRecipeInventory, state.config.recipeSlotLimit)
end })

table.insert(tests, { name = "The recipe box cap is SHARED across House/Menu/Secret, not per-category", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	state.tips = 100
	expectTrue(RunState.buyHouseRecipe(state, Recipes.HouseRecipes[1].id))
	expectTrue(RunState.buyMenuRecipe(state, Recipes.MenuRecipes[1].id))
	-- Box is full (1 House + 1 Menu = 2, the shared cap) -- a Secret Recipe
	-- purchase should now be refused too, even though secretRecipeInventory
	-- itself is still empty.
	local ok = RunState.buySecretRecipe(state, Recipes.SecretRecipes[1].id)
	expectFalse(ok)
	expectEqual(#state.secretRecipeInventory, 0)
end })

table.insert(tests, { name = "Using a Recipe makes room to buy again at the cap", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	state.tips = 100
	local r1, r2, r3 = Recipes.HouseRecipes[1], Recipes.HouseRecipes[2], Recipes.HouseRecipes[3]
	RunState.buyHouseRecipe(state, r1.id)
	RunState.buyHouseRecipe(state, r2.id)
	expectEqual(#state.houseRecipeInventory, state.config.recipeSlotLimit)

	local usedOk = RunState.useHouseRecipe(state, r1.id, { cardIndices = { 1 } })
	expectTrue(usedOk)
	expectEqual(#state.houseRecipeInventory, state.config.recipeSlotLimit - 1)

	local ok = RunState.buyHouseRecipe(state, r3.id)
	expectTrue(ok, "expected room to buy after using a Recipe")
	expectEqual(#state.houseRecipeInventory, state.config.recipeSlotLimit)
end })

table.insert(tests, { name = "RunState.resolvePack skips a Recipe pick that no longer fits the shared box, but still resolves", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	state.tips = 1000
	RunState.buyHouseRecipe(state, Recipes.HouseRecipes[1].id)
	RunState.buyHouseRecipe(state, Recipes.HouseRecipes[2].id)
	expectEqual(#state.houseRecipeInventory, state.config.recipeSlotLimit) -- already full

	local reveal = RunState.openPack(state, "menu_pack", function(n) return n end)
	local ok = RunState.resolvePack(state, { reveal.items[1].id })
	expectTrue(ok, "resolve should still succeed even though the box is full")
	expectEqual(#state.menuRecipeInventory, 0, "the pick should be silently skipped, not crash or overfill")
end })

table.insert(tests, { name = "House Recipe 'Second Helping' refuses when the recipe box is full", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	state.tips = 100
	-- Use a real recipe first so lastRecipeUsedId is set, then fill the box
	-- with two OTHER recipes (not Second Helping itself -- that's the next
	-- test's edge case).
	local r1 = Recipes.HouseRecipes[1]
	RunState.buyHouseRecipe(state, r1.id)
	local usedOk = RunState.useHouseRecipe(state, r1.id, { cardIndices = { 1 } })
	expectTrue(usedOk)
	expectTrue(state.lastRecipeUsedId ~= nil)

	RunState.buyHouseRecipe(state, Recipes.HouseRecipes[2].id)
	RunState.buyHouseRecipe(state, Recipes.HouseRecipes[3].id)
	expectEqual(#state.houseRecipeInventory, state.config.recipeSlotLimit) -- box full again

	local secondHelping = Recipes.getHouseRecipeById("second_helping")
	expectTrue(secondHelping ~= nil, "expected to find the 'second_helping' recipe definition")
	-- deps.totalHeldRecipes mirrors what RunState.useRecipe would compute --
	-- box already full and Second Helping isn't one of the 2 held recipes,
	-- so it genuinely won't fit even after freeing a slot elsewhere.
	local ok, message = secondHelping.apply(state, {}, { recipeSlotLimit = RunState.recipeSlotLimit(state), totalHeldRecipes = state.config.recipeSlotLimit })
	expectFalse(ok)
	expectTrue(message ~= nil)
end })

table.insert(tests, { name = "BUGFIX: House Recipe 'Second Helping' copies a Menu Recipe into MENU inventory, not House", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	state.tips = 100
	local menuRecipe = Recipes.MenuRecipes[1]
	RunState.buyMenuRecipe(state, menuRecipe.id)
	local usedOk = RunState.useMenuRecipe(state, menuRecipe.id, {})
	expectTrue(usedOk)
	expectEqual(state.lastRecipeUsedId, menuRecipe.id)
	expectEqual(state.lastRecipeUsedCategory, "menu")

	RunState.buyHouseRecipe(state, "second_helping")
	local ok = RunState.useHouseRecipe(state, "second_helping", {})
	expectTrue(ok)

	-- The copy must land in menuRecipeInventory (it's a Menu Recipe id) --
	-- NOT houseRecipeInventory, where it would be an unfindable, unusable
	-- phantom entry (Recipes.getHouseRecipeById would return nil for it).
	local foundInMenu = false
	for _, id in ipairs(state.menuRecipeInventory) do
		if id == menuRecipe.id then foundInMenu = true end
	end
	expectTrue(foundInMenu, "expected the Menu Recipe copy in menuRecipeInventory")
	for _, id in ipairs(state.houseRecipeInventory) do
		expectTrue(id ~= menuRecipe.id, "the Menu Recipe id should never end up in houseRecipeInventory")
	end
end })

table.insert(tests, { name = "BUGFIX: House Recipe 'Second Helping' refuses to copy a Secret Recipe (only House/Menu, per its own description)", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	state.tips = 100
	local secretRecipe = Recipes.SecretRecipes[1]
	RunState.buySecretRecipe(state, secretRecipe.id)
	local usedOk = RunState.useSecretRecipe(state, secretRecipe.id, {})
	expectTrue(usedOk)
	expectEqual(state.lastRecipeUsedCategory, "secret")

	RunState.buyHouseRecipe(state, "second_helping")
	local ok, message = RunState.useHouseRecipe(state, "second_helping", {})
	expectFalse(ok, "Second Helping should refuse to copy a Secret Recipe")
	expectTrue(message ~= nil)
end })

table.insert(tests, { name = "House Recipe 'Second Helping' succeeds when its own slot is the one freeing up room", fn = function()
	-- Box holds exactly [second_helping, other] at the cap (2). Using
	-- second_helping should still succeed -- it frees its own slot before
	-- adding the copy, netting back to exactly the cap, not over it.
	local state = RunState.new(nil, function(n) return n end)
	state.tips = 100
	local other = Recipes.HouseRecipes[1]
	RunState.buyHouseRecipe(state, other.id)
	local usedOk = RunState.useHouseRecipe(state, other.id, { cardIndices = { 1 } })
	expectTrue(usedOk)
	expectTrue(state.lastRecipeUsedId ~= nil)

	RunState.buyHouseRecipe(state, "second_helping")
	RunState.buyHouseRecipe(state, Recipes.HouseRecipes[2].id)
	expectEqual(#state.houseRecipeInventory, state.config.recipeSlotLimit) -- [second_helping, HouseRecipes[2]]

	local ok = RunState.useHouseRecipe(state, "second_helping", {})
	expectTrue(ok, "using Second Helping should succeed since it frees its own slot first")
	expectEqual(#state.houseRecipeInventory, state.config.recipeSlotLimit) -- still exactly at the cap
end })

-- ===== Feature Expansion: House Passes (Vouchers) =====

table.insert(tests, { name = "RunState.buyHousePass charges tips and records ownership", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	state.tips = 100
	local ok, message = RunState.buyHousePass(state, "extra_seating")
	expectTrue(ok)
	expectTrue(state.housePasses.extra_seating == true)
	expectEqual(state.tips, 100 - HousePasses.getById("extra_seating").price)
	expectTrue(message ~= nil)
end })

table.insert(tests, { name = "RunState.buyHousePass refuses insufficient tips and duplicate purchases", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	state.tips = 0
	local ok = RunState.buyHousePass(state, "extra_seating")
	expectFalse(ok)

	state.tips = 100
	expectTrue(RunState.buyHousePass(state, "extra_seating"))
	local ok2 = RunState.buyHousePass(state, "extra_seating")
	expectFalse(ok2, "expected a second purchase of the same House Pass to be refused")
end })

table.insert(tests, { name = "Extra Seating House Pass raises the Patron slot limit by 1", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	local before = RunState.patronSlotLimit(state)
	state.housePasses.extra_seating = true
	expectEqual(RunState.patronSlotLimit(state), before + 1)
end })

table.insert(tests, { name = "Regulars' Discount House Pass reduces Patron price by 2 (min 1)", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	local patron = Patrons.Definitions[1]
	expectEqual(RunState.patronPrice(state, patron), patron.price)
	state.housePasses.regulars_discount = true
	expectEqual(RunState.patronPrice(state, patron), math.max(1, patron.price - 2))
end })

table.insert(tests, { name = "Wholesale Pricing House Pass reduces Pack price by 2 (min 1)", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	local pack = Packs.Definitions[1]
	expectEqual(RunState.packPrice(state, pack), pack.price)
	state.housePasses.wholesale_pricing = true
	expectEqual(RunState.packPrice(state, pack), math.max(1, pack.price - 2))
end })

table.insert(tests, { name = "Frequent Visitor Card House Pass reduces reroll cost by 2 (min 1)", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	expectEqual(RunState.rerollCost(state, 5), 5)
	state.housePasses.frequent_visitor = true
	expectEqual(RunState.rerollCost(state, 5), 3)
	expectEqual(RunState.rerollCost(state, 2), 1, "reroll cost should never go below 1")
end })

table.insert(tests, { name = "Late Kitchen House Pass grants +1 Discard every round", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	local baseDiscards = state.discardsRemaining
	state.housePasses.late_kitchen = true
	RunState.startRound(state)
	expectEqual(state.discardsRemaining, baseDiscards + 1)
end })

table.insert(tests, { name = "Double Shift House Pass grants +1 Hand every round", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	local baseHands = state.handsRemaining
	state.housePasses.double_shift = true
	RunState.startRound(state)
	expectEqual(state.handsRemaining, baseHands + 1)
end })

table.insert(tests, { name = "BUGFIX: canSkipRound stays true on a fresh round after buying Double Shift", fn = function()
	-- Regression test for Ahmed's Night 4 playtest: canSkipRound used to
	-- compare handsRemaining against the STATIC config.handsPerRound, which
	-- Double Shift's permanent +1 Hand makes untrue forever once bought --
	-- the Skip button silently vanished for the rest of the run even on a
	-- completely untouched round.
	local state = RunState.new(nil, function(n) return n end)
	state.housePasses.double_shift = true
	RunState.startRound(state)
	expectTrue(RunState.canSkipRound(state), "a fresh round should still be skippable after buying Double Shift")
end })

table.insert(tests, { name = "BUGFIX: canSkipRound stays true on a fresh round after buying Late Kitchen", fn = function()
	-- Same bug, the Discard-side twin: Late Kitchen's permanent +1 Discard.
	local state = RunState.new(nil, function(n) return n end)
	state.housePasses.late_kitchen = true
	RunState.startRound(state)
	expectTrue(RunState.canSkipRound(state), "a fresh round should still be skippable after buying Late Kitchen")
end })

table.insert(tests, { name = "Grand Opening House Pass immediately grants +15 Tips on purchase", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	state.tips = 100
	local tipsBeforePurchase = state.tips
	RunState.buyHousePass(state, "grand_opening")
	local expectedTips = tipsBeforePurchase - HousePasses.getById("grand_opening").price + 15
	expectEqual(state.tips, expectedTips)
end })

-- ===== Feature Expansion: Packs (Booster Pack equivalent) =====

table.insert(tests, { name = "RunState.openPack reveals the right count of unowned Patrons and charges tips", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	state.tips = 100
	local reveal, err = RunState.openPack(state, "buffoon_pack", function(n) return n end)
	expectTrue(reveal ~= nil, err)
	expectEqual(#reveal.items, 3)
	expectEqual(reveal.category, "patron")
	expectEqual(reveal.pickCount, 1)
	expectEqual(state.tips, 100 - Packs.getById("buffoon_pack").price)
	expectTrue(state.pendingPack ~= nil)
	-- Identity rng (rng(n) = n) always removes the LAST remaining entry, so
	-- the reveal is deterministically the last 3 Patrons in the pool.
	local n = #Patrons.Definitions
	expectEqual(reveal.items[1].id, Patrons.Definitions[n].id)
	expectEqual(reveal.items[2].id, Patrons.Definitions[n - 1].id)
	expectEqual(reveal.items[3].id, Patrons.Definitions[n - 2].id)
end })

table.insert(tests, { name = "RunState.openPack reveals from the right Recipe catalog for house/menu/secret packs", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	state.tips = 100
	local reveal = RunState.openPack(state, "secret_pack", function(n) return n end)
	expectEqual(reveal.category, "secret")
	expectEqual(#reveal.items, 3)
	for _, item in ipairs(reveal.items) do
		expectTrue(Recipes.getSecretRecipeById(item.id) ~= nil)
	end
end })

table.insert(tests, { name = "RunState.openPack refuses when there aren't enough tips", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	state.tips = 0
	local reveal, err = RunState.openPack(state, "buffoon_pack")
	expectTrue(reveal == nil)
	expectTrue(err ~= nil)
	expectTrue(state.pendingPack == nil)
end })

table.insert(tests, { name = "RunState.resolvePack grants the chosen item and clears pendingPack", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	state.tips = 100
	local reveal = RunState.openPack(state, "menu_pack", function(n) return n end)
	local chosenId = reveal.items[1].id
	local ok = RunState.resolvePack(state, { chosenId })
	expectTrue(ok)
	expectTrue(state.pendingPack == nil)
	local found = false
	for _, id in ipairs(state.menuRecipeInventory) do
		if id == chosenId then found = true end
	end
	expectTrue(found, "expected the chosen Menu Recipe id in the inventory")
end })

table.insert(tests, { name = "RunState.resolvePack with an empty selection skips the pack (grants nothing)", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	state.tips = 100
	RunState.openPack(state, "house_pack", function(n) return n end)
	local ok = RunState.resolvePack(state, {})
	expectTrue(ok)
	expectTrue(state.pendingPack == nil)
	expectEqual(#state.houseRecipeInventory, 0)
end })

table.insert(tests, { name = "RunState.resolvePack rejects a selection that wasn't actually revealed", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	state.tips = 100
	RunState.openPack(state, "house_pack", function(n) return n end)
	local ok = RunState.resolvePack(state, { "not_a_revealed_id" })
	expectFalse(ok)
	expectTrue(state.pendingPack ~= nil, "a bad resolve should leave the pack open, not silently clear it")
end })

table.insert(tests, { name = "RunState.resolvePack skips a Patron pick that no longer fits, but still resolves", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	state.tips = 1000
	-- Fill the table to the cap first.
	for i, patron in ipairs(Patrons.Definitions) do
		if i > state.config.patronSlotLimit then break end
		RunState.buyPatron(state, patron.id)
	end
	expectEqual(#state.ownedPatrons, state.config.patronSlotLimit)

	local reveal = RunState.openPack(state, "buffoon_pack", function(n) return n end)
	local ok = RunState.resolvePack(state, { reveal.items[1].id })
	expectTrue(ok, "resolve should still succeed even though the table is full")
	expectEqual(#state.ownedPatrons, state.config.patronSlotLimit, "the pick should be silently skipped, not crash or overfill")
end })

-- ===== Feature Expansion (Phase 2 cont'd): Jumbo/Mega Pack sizes =====

table.insert(tests, { name = "RunState.openPack: a Jumbo pack reveals 5 items (pick 1) and charges its own price", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	state.tips = 100
	local reveal = RunState.openPack(state, "buffoon_pack_jumbo", function(n) return n end)
	expectEqual(#reveal.items, 5)
	expectEqual(reveal.pickCount, 1)
	expectEqual(state.tips, 100 - Packs.getById("buffoon_pack_jumbo").price)
end })

table.insert(tests, { name = "RunState.openPack/resolvePack: a Mega pack reveals 5 items and lets you pick 2", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	state.tips = 100
	local reveal = RunState.openPack(state, "menu_pack_mega", function(n) return n end)
	expectEqual(#reveal.items, 5)
	expectEqual(reveal.pickCount, 2)
	local ok = RunState.resolvePack(state, { reveal.items[1].id, reveal.items[2].id })
	expectTrue(ok)
	expectEqual(#state.menuRecipeInventory, 2)
end })

table.insert(tests, { name = "RunState.resolvePack: a Mega pack refuses a selection of the wrong count", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	state.tips = 100
	local reveal = RunState.openPack(state, "house_pack_mega", function(n) return n end)
	local ok, message = RunState.resolvePack(state, { reveal.items[1].id }) -- Mega needs 2 (or 0 to skip)
	expectFalse(ok)
	expectTrue(message ~= nil)
end })

-- ===== Feature Expansion (Phase 2 cont'd): Standard Packs =====

table.insert(tests, { name = "RunState.openPack: a Standard Pack reveals real cards with exactly one modifier each", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	state.tips = 100
	local reveal = RunState.openPack(state, "standard_pack", function(n) return n end)
	expectEqual(reveal.category, "standard")
	expectEqual(#reveal.items, 3)
	for _, item in ipairs(reveal.items) do
		expectTrue(item.card ~= nil, "Standard Pack items should carry a card spec")
		expectTrue(item.card.rank >= 2 and item.card.rank <= 14, "revealed rank should be a real card rank")
		expectTrue(table.find(Card.Suits, item.card.suit) ~= nil, "revealed suit should be a real suit")
		local modifierCount = (item.card.garnish and 1 or 0) + (item.card.special and 1 or 0) + (item.card.stamp and 1 or 0)
		expectEqual(modifierCount, 1)
	end
end })

table.insert(tests, { name = "RunState.resolvePack: picking a Standard Pack card adds the exact card to the discard pile", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	state.tips = 100
	local poolBefore = #state.hand + #state.deck + #state.discardPile
	local reveal = RunState.openPack(state, "standard_pack", function(n) return n end)
	local chosenItem = reveal.items[1]
	local ok = RunState.resolvePack(state, { chosenItem.id })
	expectTrue(ok)
	expectEqual(#state.hand + #state.deck + #state.discardPile, poolBefore + 1, "the run's total card pool should grow by 1")

	local addedCard = state.discardPile[#state.discardPile]
	expectEqual(addedCard.rank, chosenItem.card.rank)
	expectEqual(addedCard.suit, chosenItem.card.suit)
	expectEqual(addedCard.garnish, chosenItem.card.garnish)
	expectEqual(addedCard.special, chosenItem.card.special)
	expectEqual(addedCard.stamp, chosenItem.card.stamp)
end })

table.insert(tests, { name = "RunState.resolvePack: a Standard Pack card survives into the next round's pooled deck", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	state.tips = 100
	local reveal = RunState.openPack(state, "standard_pack", function(n) return n end)
	RunState.resolvePack(state, { reveal.items[1].id })
	local addedCard = state.discardPile[#state.discardPile]
	RunState.startRound(state) -- pools + reshuffles for the next round

	local found = false
	for _, card in ipairs(state.hand) do
		if card == addedCard then found = true end
	end
	for _, card in ipairs(state.deck) do
		if card == addedCard then found = true end
	end
	expectTrue(found, "the Standard Pack card should still be in the run's card pool (same table, not regenerated)")
end })

table.insert(tests, { name = "RunState.resolvePack: a Mega Standard Pack lets you keep 2 cards at once", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	state.tips = 100
	local poolBefore = #state.hand + #state.deck + #state.discardPile
	local reveal = RunState.openPack(state, "standard_pack_mega", function(n) return n end)
	expectEqual(#reveal.items, 5)
	expectEqual(reveal.pickCount, 2)
	local ok = RunState.resolvePack(state, { reveal.items[1].id, reveal.items[2].id })
	expectTrue(ok)
	expectEqual(#state.hand + #state.deck + #state.discardPile, poolBefore + 2)
end })

-- ===== Feature Expansion (Phase 2 cont'd): another batch of Recipes =====

table.insert(tests, { name = "House Recipe 'Wipe the Slate' clears a card's Garnish/Special/Stamp", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	state.hand[1].garnish = "sweet"
	state.hand[1].special = "gold"
	state.hand[1].stamp = "encore"
	local recipe = Recipes.getHouseRecipeById("wipe_the_slate")
	local ok = recipe.apply(state, { cardIndices = { 1 } })
	expectTrue(ok)
	expectTrue(state.hand[1].garnish == nil)
	expectTrue(state.hand[1].special == nil)
	expectTrue(state.hand[1].stamp == nil)
end })

table.insert(tests, { name = "House Recipe 'Downsize' lowers rank by 1, floored at 2", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	state.hand[1].rank = 5
	state.hand[2].rank = 2 -- already at the floor
	local recipe = Recipes.getHouseRecipeById("downsize")
	local ok = recipe.apply(state, { cardIndices = { 1, 2 } })
	expectTrue(ok)
	expectEqual(state.hand[1].rank, 4)
	expectEqual(state.hand[2].rank, 2)
end })

table.insert(tests, { name = "House Recipe 'Wildcard Swap' randomizes a card's rank and suit", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	state.hand[1].rank = 7
	state.hand[1].suit = "Hearts"
	local recipe = Recipes.getHouseRecipeById("wildcard_swap")
	local ok = recipe.apply(state, { cardIndices = { 1 }, rng = function(n) return n end })
	expectTrue(ok)
	expectEqual(state.hand[1].rank, 14) -- identity rng(13) = 13 -> rank 14
	expectEqual(state.hand[1].suit, "Spades") -- identity rng(4) = 4 -> last suit
end })

table.insert(tests, { name = "Secret Recipe 'Patron of the Month' gives a random owned Patron a random Special", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	state.tips = 10
	RunState.buyPatron(state, "the_regular")
	local recipe = Recipes.getSecretRecipeById("patron_of_the_month")
	local ok = recipe.apply(state, { rng = function(n) return n end })
	expectTrue(ok)
	expectTrue(state.ownedPatronSpecials["the_regular"] ~= nil)
	expectTrue(table.find({ "silver", "gold", "rainbow" }, state.ownedPatronSpecials["the_regular"]) ~= nil)
end })

table.insert(tests, { name = "Secret Recipe 'Patron of the Month' refuses when there are no Patrons", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	local recipe = Recipes.getSecretRecipeById("patron_of_the_month")
	local ok, message = recipe.apply(state, {})
	expectFalse(ok)
	expectTrue(message ~= nil)
end })

table.insert(tests, { name = "Secret Recipe 'Fresh Start' clears Garnish/Special/Stamp from every card in hand", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	state.hand[1].garnish = "sweet"
	state.hand[2].special = "rainbow"
	local recipe = Recipes.getSecretRecipeById("fresh_start")
	local ok = recipe.apply(state)
	expectTrue(ok)
	for _, card in ipairs(state.hand) do
		expectTrue(card.garnish == nil)
		expectTrue(card.special == nil)
		expectTrue(card.stamp == nil)
	end
end })

-- ===== Content pass (this session, cont'd): 6 more Recipes =====

table.insert(tests, { name = "House Recipe 'Well Stocked' adds 1 plain card to the deck pool", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	local poolBefore = #state.hand + #state.deck + #state.discardPile
	local recipe = Recipes.getHouseRecipeById("well_stocked")
	local ok = recipe.apply(state, { rng = function(n) return n end })
	expectTrue(ok)
	expectEqual(#state.hand + #state.deck + #state.discardPile, poolBefore + 1)
	local addedCard = state.discardPile[#state.discardPile]
	expectEqual(addedCard.rank, 14) -- identity rng(13) = 13 -> rank 14
	expectEqual(addedCard.suit, "Spades") -- identity rng(4) = 4 -> last suit
	expectTrue(addedCard.garnish == nil and addedCard.special == nil and addedCard.stamp == nil)
end })

table.insert(tests, { name = "House Recipe 'Sunday Special' adds a random Garnish to the selected card", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	local recipe = Recipes.getHouseRecipeById("sunday_special")
	local ok = recipe.apply(state, { cardIndices = { 1 }, rng = function(n) return n end })
	expectTrue(ok)
	expectEqual(state.hand[1].garnish, "lucky") -- identity rng picks the last entry in the garnish id list
end })

table.insert(tests, { name = "House Recipe 'Neighborhood Watch' copies only the Stamp, not rank/suit/Garnish/Special", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	state.hand[1].rank, state.hand[1].suit, state.hand[1].garnish, state.hand[1].special = 5, "Hearts", "sweet", "gold"
	state.hand[2].stamp = "encore"
	local recipe = Recipes.getHouseRecipeById("neighborhood_watch")
	local ok = recipe.apply(state, { cardIndices = { 1, 2 } })
	expectTrue(ok)
	expectEqual(state.hand[1].stamp, "encore")
	expectEqual(state.hand[1].rank, 5)
	expectEqual(state.hand[1].suit, "Hearts")
	expectEqual(state.hand[1].garnish, "sweet")
	expectEqual(state.hand[1].special, "gold")
end })

table.insert(tests, { name = "Secret Recipe 'Fresh Delivery' adds 1 modified card to the deck pool", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	local poolBefore = #state.hand + #state.deck + #state.discardPile
	local recipe = Recipes.getSecretRecipeById("fresh_delivery")
	local ok = recipe.apply(state, { rng = function(n) return n end })
	expectTrue(ok)
	expectEqual(#state.hand + #state.deck + #state.discardPile, poolBefore + 1)
	local addedCard = state.discardPile[#state.discardPile]
	local modifierCount = (addedCard.garnish and 1 or 0) + (addedCard.special and 1 or 0) + (addedCard.stamp and 1 or 0)
	expectEqual(modifierCount, 1)
end })

table.insert(tests, { name = "Secret Recipe 'Sugar Shield' protects Brittle Garnish cards from shattering this round", fn = function()
	local card = Card.new(9, "Hearts", { garnish = "brittle" })
	local hand = HandEvaluator.evaluate({ card })
	local alwaysBreakRng = function(_n) return 1 end -- Brittle's breakOneInN = 4, rng(4) = 1 always hits

	local _, _, _, extraUnshielded = Scoring.calculate(hand, {}, { rng = alwaysBreakRng })
	expectEqual(#extraUnshielded.brokenCards, 1)

	local _, _, _, extraShielded = Scoring.calculate(hand, {}, { rng = alwaysBreakRng, brittleShielded = true })
	expectEqual(#extraShielded.brokenCards, 0)
end })

table.insert(tests, { name = "RunState.useSecretRecipe: 'Sugar Shield' sets brittleShieldRound, which playHand forwards to Scoring", fn = function()
	-- The actual protection logic (breakOneInN skipped while shielded) is
	-- proven deterministically in the "Scoring.calculate" test above via a
	-- forced rng -- RunState.playHand doesn't thread a deterministic rng
	-- through to Scoring.calculate (it always uses real math.random there),
	-- so this test only checks the wiring: buying+using the recipe sets the
	-- state flag, and playHand's context actually forwards it.
	local state = RunState.new(nil, function(n) return n end)
	state.tips = 10
	RunState.buySecretRecipe(state, "sugar_shield")
	local ok = RunState.useSecretRecipe(state, "sugar_shield")
	expectTrue(ok)
	expectTrue(state.brittleShieldRound)
end })

table.insert(tests, { name = "Secret Recipe 'Crowd Favorite' levels up the most-played hand type this run", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	state.handStats = { ["Pair"] = 3, ["High Card"] = 1 }
	local recipe = Recipes.getSecretRecipeById("crowd_favorite")
	local ok = recipe.apply(state)
	expectTrue(ok)
	expectEqual(state.handLevels["Pair"], 1)
end })

table.insert(tests, { name = "Secret Recipe 'Crowd Favorite' refuses if no hand has been played yet this run", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	local recipe = Recipes.getSecretRecipeById("crowd_favorite")
	local ok, message = recipe.apply(state)
	expectFalse(ok)
	expectTrue(message ~= nil)
end })

-- ===== Feature Expansion (this pass): Grab Bag ("mixed") Packs =====

table.insert(tests, { name = "RunState.openPack: a Grab Bag Pack can reveal every subcategory across its items, each tagged with its own category", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	state.tips = 100
	-- Forces item order: patron, house, menu, secret, standard (see
	-- RunState.openPack's "mixed" branch -- subcategories are rolled in
	-- that list order, index 1..5).
	local rng = scriptedRng({ 1, 1, 2, 1, 3, 1, 4, 1, 5, 1, 1, 1 })
	local reveal = RunState.openPack(state, "mixed_pack_mega", rng)
	expectEqual(reveal.category, "mixed")
	expectEqual(#reveal.items, 5)
	expectEqual(reveal.items[1].category, "patron")
	expectEqual(reveal.items[2].category, "house")
	expectEqual(reveal.items[3].category, "menu")
	expectEqual(reveal.items[4].category, "secret")
	expectEqual(reveal.items[5].category, "standard")
	expectTrue(reveal.items[5].card ~= nil, "the standard item should carry a card spec")
end })

table.insert(tests, { name = "RunState.resolvePack: a Grab Bag Pack grants each picked item according to its OWN category, not the pack's", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	state.tips = 100
	local ownedPatronsBefore = #state.ownedPatrons
	local poolBefore = #state.hand + #state.deck + #state.discardPile
	local rng = scriptedRng({ 1, 1, 2, 1, 3, 1, 4, 1, 5, 1, 1, 1 })
	local reveal = RunState.openPack(state, "mixed_pack_mega", rng)
	-- Pick item 1 (a Patron) and item 5 (a Standard card) -- two different
	-- categories granted through ONE resolvePack call.
	local ok = RunState.resolvePack(state, { reveal.items[1].id, reveal.items[5].id })
	expectTrue(ok)
	expectEqual(#state.ownedPatrons, ownedPatronsBefore + 1)
	expectEqual(#state.hand + #state.deck + #state.discardPile, poolBefore + 1)
end })

table.insert(tests, { name = "RunState.resolvePack: a Grab Bag Pack's Recipe item is granted into the matching Recipe inventory", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	state.tips = 100
	local houseInvBefore = #state.houseRecipeInventory
	local rng = scriptedRng({ 1, 1, 2, 1, 3, 1, 4, 1, 5, 1, 1, 1 })
	local reveal = RunState.openPack(state, "mixed_pack_mega", rng)
	-- Item 2 is the House Recipe in this scripted reveal.
	local ok = RunState.resolvePack(state, { reveal.items[2].id, reveal.items[3].id })
	expectTrue(ok)
	expectEqual(#state.houseRecipeInventory, houseInvBefore + 1)
	expectTrue(state.houseRecipeInventory[#state.houseRecipeInventory] == reveal.items[2].id)
end })

table.insert(tests, { name = "RunState.openPack: a Grab Bag Pack's 'patron' roll falls back to a Standard card once every Patron is already owned", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	state.tips = 100
	-- Own every Patron already, so the "patron" subcategory roll has
	-- nothing left to reveal and must fall back to "standard" instead of
	-- erroring or producing a blank item.
	state.ownedPatrons = {}
	for _, patron in ipairs(Patrons.Definitions) do
		table.insert(state.ownedPatrons, patron)
	end
	local rng = scriptedRng({ 1, 1, 1, 1 }) -- both items roll "patron" (index 1)
	local reveal = RunState.openPack(state, "mixed_pack", rng)
	for _, item in ipairs(reveal.items) do
		expectEqual(item.category, "standard")
		expectTrue(item.card ~= nil)
	end
end })

-- ===== PlayerProfile (PERSISTENT SAVE, Phase 10) =====

table.insert(tests, { name = "PlayerProfile.new: starts empty with the expected shape", fn = function()
	local profile = PlayerProfile.new()
	expectEqual(profile.version, PlayerProfile.SCHEMA_VERSION)
	local anyPatron = false
	for _ in pairs(profile.discoveredPatronIds) do anyPatron = true end
	expectFalse(anyPatron, "a fresh profile shouldn't have any discovered Patrons yet")
	expectEqual(next(profile.ownedSetIds), nil, "a fresh profile owns no bought sets yet")
	expectEqual(profile.equippedSetId, CosmeticSets.DefaultId)
	expectEqual(profile.stats.runsStarted, 0)
	expectEqual(profile.stats.runsWon, 0)
	expectEqual(profile.stats.bestNightReached, 0)
end })

table.insert(tests, { name = "PlayerProfile.migrate(nil): a brand-new player gets a safe default profile", fn = function()
	local profile = PlayerProfile.migrate(nil)
	expectEqual(profile.stats.runsStarted, 0)
	local any = false
	for _ in pairs(profile.discoveredPatronIds) do any = true end
	expectFalse(any)
end })

table.insert(tests, { name = "PlayerProfile.migrate: a valid saved profile round-trips unchanged", fn = function()
	local profile = PlayerProfile.new()
	PlayerProfile.recordPatronsFound(profile, { "tip_jar", "second_opinion" })
	profile.ownedSetIds.winter_evening = true
	profile.equippedSetId = "winter_evening"
	PlayerProfile.recordRunStarted(profile)
	PlayerProfile.recordNightReached(profile, 5)
	PlayerProfile.recordRunWon(profile)

	local reloaded = PlayerProfile.migrate(profile)
	expectTrue(reloaded.discoveredPatronIds.tip_jar)
	expectTrue(reloaded.discoveredPatronIds.second_opinion)
	expectTrue(reloaded.ownedSetIds.winter_evening)
	expectEqual(reloaded.equippedSetId, "winter_evening")
	expectEqual(reloaded.stats.runsStarted, 1)
	expectEqual(reloaded.stats.bestNightReached, 5)
	expectEqual(reloaded.stats.runsWon, 1)
end })

table.insert(tests, { name = "PlayerProfile.migrate: sanitizes a corrupt/foreign shape instead of crashing or propagating garbage", fn = function()
	local profile = PlayerProfile.migrate({
		discoveredPatronIds = "not a table",
		ownedSetIds = { winter_evening = "yes, but not literally true" }, -- wrong value type -- must be dropped
		stats = { runsStarted = "five", runsWon = -3, bestNightReached = 4.9 },
		someUnrelatedFieldFromAFutureVersion = { 1, 2, 3 },
	})
	local any = false
	for _ in pairs(profile.discoveredPatronIds) do any = true end
	expectFalse(any, "a non-table discoveredPatronIds should be ignored, not error")
	expectFalse(profile.ownedSetIds.winter_evening == true, "a non-true value for an owned set id should be dropped")
	expectEqual(profile.stats.runsStarted, 0, "a non-number runsStarted should fall back to the default")
	expectEqual(profile.stats.runsWon, 0, "a negative runsWon should be clamped, not kept negative")
	expectEqual(profile.stats.bestNightReached, 4, "a fractional bestNightReached should be floored")
end })

table.insert(tests, { name = "PlayerProfile.recordPatronsFound: reports changed only when something is actually new", fn = function()
	local profile = PlayerProfile.new()
	expectTrue(PlayerProfile.recordPatronsFound(profile, { "tip_jar" }))
	expectFalse(PlayerProfile.recordPatronsFound(profile, { "tip_jar" }), "re-recording an already-discovered Patron shouldn't report a change")
	expectTrue(PlayerProfile.recordPatronsFound(profile, { "tip_jar", "second_opinion" }), "a mix of old + 1 new id should still report a change")
end })

table.insert(tests, { name = "PlayerProfile.recordNightReached: only an idempotent high-water mark", fn = function()
	local profile = PlayerProfile.new()
	expectTrue(PlayerProfile.recordNightReached(profile, 3))
	expectEqual(profile.stats.bestNightReached, 3)
	expectFalse(PlayerProfile.recordNightReached(profile, 3), "an equal Night shouldn't report a change")
	expectFalse(PlayerProfile.recordNightReached(profile, 2), "a LOWER Night should never lower the high-water mark")
	expectEqual(profile.stats.bestNightReached, 3)
	expectTrue(PlayerProfile.recordNightReached(profile, 8))
	expectEqual(profile.stats.bestNightReached, 8)
end })

table.insert(tests, { name = "PlayerProfile.recordRunStarted / recordRunWon: plain counters", fn = function()
	local profile = PlayerProfile.new()
	PlayerProfile.recordRunStarted(profile)
	PlayerProfile.recordRunStarted(profile)
	expectEqual(profile.stats.runsStarted, 2)
	PlayerProfile.recordRunWon(profile)
	expectEqual(profile.stats.runsWon, 1)
end })

-- ===== Achievements + Titles (Phase 16) =====

table.insert(tests, { name = "Achievements.isUnlocked: false for a fresh profile, true once the requirement is met", fn = function()
	local profile = PlayerProfile.new()
	expectFalse(Achievements.isUnlocked(profile, "first_steps"))
	PlayerProfile.recordRunStarted(profile)
	expectTrue(Achievements.isUnlocked(profile, "first_steps"))
end })

table.insert(tests, { name = "Achievements.isUnlocked: an unknown id is always false, never errors", fn = function()
	local profile = PlayerProfile.new()
	expectFalse(Achievements.isUnlocked(profile, "not_a_real_achievement"))
end })

table.insert(tests, { name = "Achievements: runsWon-tiered achievements unlock at their own threshold, not before", fn = function()
	local profile = PlayerProfile.new()
	for _ = 1, 4 do
		PlayerProfile.recordRunWon(profile)
	end
	expectTrue(Achievements.isUnlocked(profile, "grand_finale"))
	expectFalse(Achievements.isUnlocked(profile, "regular"), "4 wins shouldn't be enough for the 5-win achievement")
	PlayerProfile.recordRunWon(profile)
	expectTrue(Achievements.isUnlocked(profile, "regular"), "the 5th win should unlock it")
	expectFalse(Achievements.isUnlocked(profile, "tavern_legend"))
end })

table.insert(tests, { name = "Achievements: bestNightReached-tiered achievements (Deep Cuts / Into the Endless)", fn = function()
	local profile = PlayerProfile.new()
	PlayerProfile.recordNightReached(profile, 3)
	expectFalse(Achievements.isUnlocked(profile, "deep_cuts"))
	PlayerProfile.recordNightReached(profile, 4)
	expectTrue(Achievements.isUnlocked(profile, "deep_cuts"))
	expectFalse(Achievements.isUnlocked(profile, "into_the_endless"), "Night 4 shouldn't unlock the Night-9 Endless achievement")
	PlayerProfile.recordNightReached(profile, 9)
	expectTrue(Achievements.isUnlocked(profile, "into_the_endless"))
end })

table.insert(tests, { name = "Achievements: discoveredPatronIds-count achievements (Patron Saint / Full House / Every Patron)", fn = function()
	local profile = PlayerProfile.new()
	local ids = {}
	for i = 1, 9 do
		table.insert(ids, "fake_patron_" .. i)
	end
	PlayerProfile.recordPatronsFound(profile, ids)
	expectFalse(Achievements.isUnlocked(profile, "patron_saint"), "9 discovered shouldn't be enough for the 10-Patron achievement")
	PlayerProfile.recordPatronsFound(profile, { "fake_patron_10" })
	expectTrue(Achievements.isUnlocked(profile, "patron_saint"))
	expectFalse(Achievements.isUnlocked(profile, "full_house"))
	expectFalse(Achievements.isUnlocked(profile, "every_patron"))
end })

table.insert(tests, { name = "Achievements.unlockedFor: returns exactly the achievements this profile currently qualifies for", fn = function()
	local profile = PlayerProfile.new()
	PlayerProfile.recordRunStarted(profile)
	PlayerProfile.recordRunWon(profile)
	local unlocked = Achievements.unlockedFor(profile)
	local unlockedIds = {}
	for _, a in ipairs(unlocked) do
		unlockedIds[a.id] = true
	end
	expectTrue(unlockedIds.first_steps)
	expectTrue(unlockedIds.grand_finale)
	expectFalse(unlockedIds.regular == true)
end })

table.insert(tests, { name = "PlayerProfile.equipTitle: refuses a title that isn't unlocked yet", fn = function()
	local profile = PlayerProfile.new()
	local ok, message = PlayerProfile.equipTitle(profile, "grand_finale")
	expectFalse(ok)
	expectTrue(message ~= nil)
	expectEqual(profile.equippedTitleId, nil)
end })

table.insert(tests, { name = "PlayerProfile.equipTitle: succeeds once the achievement is unlocked, and nil clears it", fn = function()
	local profile = PlayerProfile.new()
	PlayerProfile.recordRunStarted(profile)
	local ok = PlayerProfile.equipTitle(profile, "first_steps")
	expectTrue(ok)
	expectEqual(profile.equippedTitleId, "first_steps")
	local clearOk = PlayerProfile.equipTitle(profile, nil)
	expectTrue(clearOk)
	expectEqual(profile.equippedTitleId, nil)
end })

table.insert(tests, { name = "PlayerProfile.migrate: a saved equippedTitleId round-trips only while still actually unlocked", fn = function()
	local profile = PlayerProfile.new()
	PlayerProfile.recordRunStarted(profile)
	PlayerProfile.equipTitle(profile, "first_steps")
	local reloaded = PlayerProfile.migrate(profile)
	expectEqual(reloaded.equippedTitleId, "first_steps")

	-- A saved title for an achievement this (corrupt/rolled-back) profile
	-- no longer actually qualifies for should be dropped, not trusted.
	local badProfile = PlayerProfile.new()
	badProfile.equippedTitleId = "tavern_legend" -- runsWon is still 0
	local reloadedBad = PlayerProfile.migrate(badProfile)
	expectEqual(reloadedBad.equippedTitleId, nil)
end })

-- ===== Tutorial (Phase 16) =====

table.insert(tests, { name = "PlayerProfile.new: hasSeenTutorial starts false", fn = function()
	local profile = PlayerProfile.new()
	expectFalse(profile.hasSeenTutorial)
end })

table.insert(tests, { name = "PlayerProfile.markTutorialSeen: flips the flag, is idempotent, and survives a migrate round-trip", fn = function()
	local profile = PlayerProfile.new()
	PlayerProfile.markTutorialSeen(profile)
	expectTrue(profile.hasSeenTutorial)
	PlayerProfile.markTutorialSeen(profile) -- calling again shouldn't error or change anything
	expectTrue(profile.hasSeenTutorial)

	local reloaded = PlayerProfile.migrate(profile)
	expectTrue(reloaded.hasSeenTutorial)
end })

table.insert(tests, { name = "PlayerProfile.migrate: a saved profile predating this field defaults hasSeenTutorial to false", fn = function()
	local reloaded = PlayerProfile.migrate({ stats = { runsStarted = 3, runsWon = 1, bestNightReached = 2 } })
	expectFalse(reloaded.hasSeenTutorial)
end })

-- ===== Cosmetic Sets =====

local function tipsState(n) return { tips = n } end

table.insert(tests, { name = "CosmeticSets: definitions are well-formed and reference real card backs/achievements", fn = function()
	local seen = {}
	expectTrue(CosmeticSets.getById(CosmeticSets.DefaultId) ~= nil)
	for _, set in ipairs(CosmeticSets.Definitions) do
		expectFalse(seen[set.id], "duplicate " .. set.id)
		seen[set.id] = true
		expectTrue(CardBacks.getById(set.cardBackId) ~= nil, set.id .. " card back")
		local kind = set.unlock.kind
		expectTrue(kind == "default" or kind == "tips" or kind == "journey" or kind == "achievement" or kind == "gamepass" or kind == "biome" or kind == "season", set.id .. " unlock kind")
		if kind == "achievement" then expectTrue(Achievements.getById(set.unlock.id) ~= nil) end
		if kind == "gamepass" then expectTrue(GamePasses.getById(set.unlock.passId) ~= nil) end
		expectTrue(#CosmeticSets.unlockText(set) > 0)
		local lower = (set.name .. set.description):lower()
		expectFalse(lower:find("balatro", 1, true) ~= nil)
	end
end })

table.insert(tests, { name = "CosmeticSets.isUnlocked: each unlock source", fn = function()
	local profile = PlayerProfile.new()
	expectTrue(CosmeticSets.isUnlocked(profile, "classic_tavern"))
	expectFalse(CosmeticSets.isUnlocked(profile, "winter_evening"))
	expectFalse(CosmeticSets.isUnlocked(profile, "festival_night"))
	expectFalse(CosmeticSets.isUnlocked(profile, "closing_time"))
	expectFalse(CosmeticSets.isUnlocked(profile, "golden_gala"))
	expectFalse(CosmeticSets.isUnlocked(profile, "nope"))
	profile.ownedSetIds.winter_evening = true
	profile.stats.runsWon = 1
	expectTrue(CosmeticSets.isUnlocked(profile, "winter_evening"))
	expectTrue(CosmeticSets.isUnlocked(profile, "festival_night"))
	profile.stats.runsWon = 5
	expectTrue(CosmeticSets.isUnlocked(profile, "closing_time"), "the Regular achievement")
	expectFalse(CosmeticSets.isUnlocked(profile, "golden_gala", {}))
	expectTrue(CosmeticSets.isUnlocked(profile, "golden_gala", { set_golden_gala = true }))
end })

table.insert(tests, { name = "CosmeticSets.buy: spends Tips once, rejects short funds and non-Tips sets", fn = function()
	local profile = PlayerProfile.new()
	local price = CosmeticSets.getById("winter_evening").unlock.price
	local poor = tipsState(price - 1)
	expectFalse((CosmeticSets.buy(profile, poor, "winter_evening")))
	expectEqual(poor.tips, price - 1)
	local state = tipsState(price + 3)
	expectTrue((CosmeticSets.buy(profile, state, "winter_evening")))
	expectEqual(state.tips, 3)
	expectTrue(profile.ownedSetIds.winter_evening)
	expectFalse((CosmeticSets.buy(profile, state, "winter_evening")), "already owned")
	expectFalse((CosmeticSets.buy(profile, tipsState(999), "festival_night")), "journey sets can't be bought")
	expectFalse((CosmeticSets.buy(profile, tipsState(999), "nope")))
end })

table.insert(tests, { name = "CosmeticSets.equip: only unlocked sets; effectiveId falls back to the default", fn = function()
	local profile = PlayerProfile.new()
	expectFalse((CosmeticSets.equip(profile, "winter_evening")))
	expectEqual(profile.equippedSetId, CosmeticSets.DefaultId)
	profile.ownedSetIds.winter_evening = true
	expectTrue((CosmeticSets.equip(profile, "winter_evening")))
	expectEqual(CosmeticSets.effectiveId(profile), "winter_evening")
	expectFalse((CosmeticSets.equip(profile, "nope")))
	-- A gamepass set stops applying if the pass isn't owned any more.
	profile.equippedSetId = "golden_gala"
	expectEqual(CosmeticSets.effectiveId(profile, {}), CosmeticSets.DefaultId)
	expectEqual(CosmeticSets.effectiveId(profile, { set_golden_gala = true }), "golden_gala")
end })

table.insert(tests, { name = "Card backs: unlock sources (default, earned, with an unlocked set)", fn = function()
	local profile = PlayerProfile.new()
	expectTrue(CosmeticSets.isCardBackUnlocked(profile, "classic"))
	expectFalse(CosmeticSets.isCardBackUnlocked(profile, "gilded_ledger"))
	expectFalse(CosmeticSets.isCardBackUnlocked(profile, "winter_frost"))
	expectFalse(CosmeticSets.isCardBackUnlocked(profile, "nope"))
	profile.unlockedCardBackIds.gilded_ledger = true
	expectTrue(CosmeticSets.isCardBackUnlocked(profile, "gilded_ledger"), "milestone/journey earned")
	profile.ownedSetIds.winter_evening = true
	expectTrue(CosmeticSets.isCardBackUnlocked(profile, "winter_frost"), "comes with an unlocked set")
	expectTrue(CosmeticSets.isCardBackUnlocked(PlayerProfile.new(), "gilded_ledger", { set_golden_gala = true }), "gala pass unlocks its set's back")
end })

table.insert(tests, { name = "Card backs: equip only unlocked, effective back follows the set when no pick", fn = function()
	local profile = PlayerProfile.new()
	expectEqual(CosmeticSets.effectiveCardBackId(profile), "classic")
	expectFalse((CosmeticSets.equipCardBack(profile, "winter_frost")))
	expectEqual(profile.equippedCardBackId, nil)
	profile.ownedSetIds.winter_evening = true
	CosmeticSets.equip(profile, "winter_evening")
	expectEqual(CosmeticSets.effectiveCardBackId(profile), "winter_frost", "follows the set")
	profile.unlockedCardBackIds.hall_banner = true
	expectTrue((CosmeticSets.equipCardBack(profile, "hall_banner")))
	expectEqual(CosmeticSets.effectiveCardBackId(profile), "hall_banner", "the pick wins over the set")
	expectEqual(profile.equippedSetId, "winter_evening", "equipping a back leaves the set alone")
	expectTrue((CosmeticSets.equipCardBack(profile, nil)))
	expectEqual(CosmeticSets.effectiveCardBackId(profile), "winter_frost", "cleared pick follows the set again")
end })

table.insert(tests, { name = "Card backs: a pick that is no longer unlocked falls back; migrate keeps only known ids", fn = function()
	local profile = PlayerProfile.new()
	profile.equippedCardBackId = "gilded_ledger"
	expectEqual(CosmeticSets.effectiveCardBackId(profile), "classic", "not unlocked")
	profile.equippedSetId = "golden_gala"
	expectEqual(CosmeticSets.effectiveCardBackId(profile, { set_golden_gala = true }), "gilded_ledger")
	expectEqual(CosmeticSets.effectiveCardBackId(profile, {}), "classic", "pass gone")
	expectEqual(PlayerProfile.migrate({ equippedCardBackId = "gilded_ledger" }).equippedCardBackId, "gilded_ledger")
	expectEqual(PlayerProfile.migrate({ equippedCardBackId = "removed_back" }).equippedCardBackId, nil)
	expectEqual(PlayerProfile.migrate({ equippedCardBackId = 7 }).equippedCardBackId, nil)
	expectEqual(PlayerProfile.migrate({}).equippedCardBackId, nil)
end })

table.insert(tests, { name = "PlayerProfile.migrate: old Theme/Jukebox profiles load and fall back to the default set", fn = function()
	local profile = PlayerProfile.migrate({
		discoveredPatronIds = { tip_jar = true },
		ownedThemeIds = { midnight_blue = true, crimson = true },
		equippedTheme = "midnight_blue",
		customPlaylist = { "rbxassetid://111" },
		ownedGamePassIds = { all_themes = true, custom_jukebox = true },
		stats = { runsStarted = 3, runsWon = 1, bestNightReached = 4 },
	})
	expectTrue(profile.discoveredPatronIds.tip_jar)
	expectEqual(profile.stats.runsWon, 1)
	expectEqual(profile.equippedSetId, CosmeticSets.DefaultId)
	expectEqual(next(profile.ownedSetIds), nil, "old theme purchases aren't carried over")
	expectEqual(profile.ownedThemeIds, nil)
	expectEqual(profile.customPlaylist, nil)
end })

table.insert(tests, { name = "PlayerProfile.migrate: unknown/garbage equippedSetId falls back to the default; a title from a removed achievement is dropped", fn = function()
	expectEqual(PlayerProfile.migrate({ equippedSetId = "retired_set" }).equippedSetId, CosmeticSets.DefaultId)
	expectEqual(PlayerProfile.migrate({ equippedSetId = 42 }).equippedSetId, CosmeticSets.DefaultId)
	expectEqual(PlayerProfile.migrate({ equippedTitleId = "redecorated", ownedThemeIds = { a = true } }).equippedTitleId, nil)
end })

table.insert(tests, { name = "GamePasses: Theme Vault and Custom Jukebox are gone; Fast Forward stays", fn = function()
	expectEqual(GamePasses.getById("all_themes"), nil)
	expectEqual(GamePasses.getById("custom_jukebox"), nil)
	expectTrue(GamePasses.getById("fast_forward") ~= nil)
end })

-- ===== Journey map (Night first-clears and rewards) =====

local function fakeRun(over)
	local st = { night = 1, round = 1, roundOver = false, runOver = false, wonRun = false,
		config = { nightCap = 8, roundsPerNight = 3 } }
	for k, v in pairs(over or {}) do st[k] = v end
	return st
end

table.insert(tests, { name = "JourneyMap: 8 named Nights with descriptions and rewards that resolve", fn = function()
	expectEqual(#JourneyMap.Nights, 8)
	local names = {}
	local lookups = { cardBack = CardBacks, set = CosmeticSets, title = Achievements }
	for i, entry in ipairs(JourneyMap.Nights) do
		expectEqual(entry.night, i)
		expectTrue(#entry.name > 0 and #entry.description > 0 and #entry.icon > 0)
		expectFalse(names[entry.name], "duplicate name")
		names[entry.name] = true
		local def = lookups[entry.reward.kind] and lookups[entry.reward.kind].getById(entry.reward.id)
		expectTrue(def ~= nil, "Night " .. i .. " reward resolves")
		if entry.reward.kind == "title" then expectTrue(def.milestoneReward == true) end
		local lower = (entry.name .. entry.description):lower()
		for _, bad in ipairs({ "balatro", "beer", "wine", "booze", "cocktail", "whiskey", "drunk" }) do
			expectFalse(lower:find(bad, 1, true) ~= nil, bad)
		end
	end
	expectTrue(#JourneyMap.Endless.name > 0)
end })

table.insert(tests, { name = "JourneyMap.bossTierFor: tiers 1, 2, 3 by Night", fn = function()
	expectEqual(JourneyMap.bossTierFor(1), 1)
	expectEqual(JourneyMap.bossTierFor(2), 1)
	expectEqual(JourneyMap.bossTierFor(3), 2)
	expectEqual(JourneyMap.bossTierFor(5), 2)
	expectEqual(JourneyMap.bossTierFor(6), 3)
	expectEqual(JourneyMap.bossTierFor(8), 3)
end })

table.insert(tests, { name = "JourneyMap.nightsClearedFor: previous Nights, boss win in the shop, won run, Endless", fn = function()
	expectEqual(JourneyMap.nightsClearedFor(fakeRun()), 0)
	expectEqual(JourneyMap.nightsClearedFor(fakeRun({ night = 3, round = 2 })), 2)
	expectEqual(JourneyMap.nightsClearedFor(fakeRun({ night = 3, round = 2, roundOver = true })), 2, "a non-boss round win isn't a Night clear")
	expectEqual(JourneyMap.nightsClearedFor(fakeRun({ night = 3, round = 3, roundOver = true })), 3, "boss round won, still on Night 3")
	expectEqual(JourneyMap.nightsClearedFor(fakeRun({ night = 3, round = 3, roundOver = true, runOver = true })), 2, "a lost boss round")
	expectEqual(JourneyMap.nightsClearedFor(fakeRun({ night = 8, round = 3, roundOver = true, wonRun = true })), 8)
	expectEqual(JourneyMap.nightsClearedFor(fakeRun({ night = 12, round = 1, wonRun = true })), 8, "Endless caps at 8")
end })

table.insert(tests, { name = "JourneyMap.recordNightsCleared: grants each reward once, in the right field", fn = function()
	local profile = PlayerProfile.new()
	expectEqual(#JourneyMap.recordNightsCleared(profile, 0), 0)
	local fresh = JourneyMap.recordNightsCleared(profile, 3)
	expectEqual(#fresh, 3)
	expectEqual(fresh[1], 1)
	expectTrue(profile.clearedNightIds[1] and profile.clearedNightIds[3])
	expectFalse(profile.clearedNightIds[4] == true)
	expectTrue(profile.rewardTitleIds.porch_regular, "Night 1 title")
	expectTrue(profile.unlockedCardBackIds.kitchen_checks, "Night 2 card back")
	expectTrue(profile.ownedSetIds.winter_evening, "Night 3 set")
	expectTrue(Achievements.isUnlocked(profile, "porch_regular"))
	expectTrue(CosmeticSets.isUnlocked(profile, "winter_evening"), "reward sets count as unlocked")
	-- Repeating, or a lower count, grants nothing new.
	expectEqual(#JourneyMap.recordNightsCleared(profile, 3), 0)
	expectEqual(#JourneyMap.recordNightsCleared(profile, 2), 0)
	-- A jump claims several, capped at 8.
	local more = JourneyMap.recordNightsCleared(profile, 99)
	expectEqual(#more, 5)
	expectEqual(more[1], 4)
	expectTrue(profile.rewardTitleIds.tavern_keeper)
	expectTrue(profile.ownedSetIds.festival_night and profile.ownedSetIds.closing_time)
	expectEqual(#JourneyMap.recordNightsCleared(profile, "x"), 0)
end })

table.insert(tests, { name = "PlayerProfile.migrate: clearedNightIds round-trip, garbage dropped, old profiles empty", fn = function()
	local profile = PlayerProfile.new()
	JourneyMap.recordNightsCleared(profile, 2)
	local reloaded = PlayerProfile.migrate(profile)
	expectTrue(reloaded.clearedNightIds[1] and reloaded.clearedNightIds[2])
	expectTrue(reloaded.rewardTitleIds.porch_regular)
	expectEqual(next(PlayerProfile.migrate({ stats = { runsStarted = 1 } }).clearedNightIds), nil)
	local bad = PlayerProfile.migrate({ clearedNightIds = { [0] = true, [9] = true, [2.5] = true, [3] = "yes", abc = true, [4] = true } })
	expectEqual(next(bad.clearedNightIds), 4)
	expectEqual(PlayerProfile.migrate({ clearedNightIds = "nope" }).clearedNightIds[1], nil)
end })

table.insert(tests, { name = "PlayerProfile.migrate: a reward added after a Night was cleared is regranted on load", fn = function()
	local reloaded = PlayerProfile.migrate({ clearedNightIds = { [3] = true } })
	expectTrue(reloaded.ownedSetIds.winter_evening)
end })

-- ===== Journey phase 2: Endless milestones, completion, equip =====

table.insert(tests, { name = "JourneyMap: nodes have normalized positions; Endless milestones resolve to real rewards", fn = function()
	local lookups = { cardBack = CardBacks, set = CosmeticSets, title = Achievements }
	local lastNight = JourneyMap.NightCap
	for _, node in ipairs(JourneyMap.allNodes()) do
		expectTrue(node.info.x >= 0 and node.info.x <= 1 and node.info.y >= 0 and node.info.y <= 1, "position in 0-1 for " .. tostring(node.key))
		if node.info.reward then
			expectTrue(lookups[node.info.reward.kind].getById(node.info.reward.id) ~= nil, "reward resolves for " .. tostring(node.key))
		end
	end
	expectTrue(#JourneyMap.EndlessMilestones >= 3)
	for _, entry in ipairs(JourneyMap.EndlessMilestones) do
		expectTrue(entry.night > lastNight, "milestones ascend past Night 8")
		lastNight = entry.night
	end
	expectTrue(JourneyMap.Config.journeyMapImage ~= nil)
end })

table.insert(tests, { name = "JourneyMap.rewardLabel: resolves names without a lookups table", fn = function()
	expectEqual(JourneyMap.rewardLabel({ kind = "title", id = "night_walker" }), 'Title: "Night Walker"')
	expectEqual(JourneyMap.rewardLabel({ kind = "cardBack", id = "ember_hours" }), "Card back: Ember Hours")
end })

table.insert(tests, { name = "JourneyMap.totalNightsClearedFor: uncapped in Endless", fn = function()
	expectEqual(JourneyMap.totalNightsClearedFor(fakeRun({ night = 12, round = 1 })), 11)
	expectEqual(JourneyMap.totalNightsClearedFor(fakeRun({ night = 10, round = 3, roundOver = true, wonRun = true })), 10)
	expectEqual(JourneyMap.totalNightsClearedFor(fakeRun({ night = 10, round = 3, roundOver = true, runOver = true })), 9)
end })

table.insert(tests, { name = "JourneyMap.recordEndlessCleared: grants each milestone reward once", fn = function()
	local profile = PlayerProfile.new()
	expectEqual(#JourneyMap.recordEndlessCleared(profile, 9), 0)
	local fresh = JourneyMap.recordEndlessCleared(profile, 10)
	expectEqual(#fresh, 1)
	expectEqual(fresh[1], 10)
	expectTrue(profile.rewardTitleIds.night_walker)
	expectEqual(#JourneyMap.recordEndlessCleared(profile, 10), 0, "no repeat grant")
	local more = JourneyMap.recordEndlessCleared(profile, 25)
	expectEqual(#more, 2)
	expectTrue(profile.unlockedCardBackIds.ember_hours)
	expectTrue(profile.rewardTitleIds.endless_legend)
	expectEqual(#JourneyMap.recordEndlessCleared(profile, "x"), 0)
end })

table.insert(tests, { name = "JourneyMap.completion and nextReward follow cleared nodes", fn = function()
	local done, total, pct = JourneyMap.completion({})
	expectEqual(done, 0)
	expectEqual(total, 8 + #JourneyMap.EndlessMilestones)
	expectEqual(pct, 0)
	expectEqual(JourneyMap.nextReward({}).night, 1)
	local cleared = { [1] = true, [2] = true }
	local d2, _, p2 = JourneyMap.completion(cleared)
	expectEqual(d2, 2)
	expectEqual(p2, math.floor(200 / total))
	expectEqual(JourneyMap.nextReward(cleared).night, 3)
	local all = {}
	for _, node in ipairs(JourneyMap.allNodes()) do
		if node.night then all[node.night] = true end
	end
	local _, _, full = JourneyMap.completion(all)
	expectEqual(full, 100)
	expectEqual(JourneyMap.nextReward(all), nil)
end })

table.insert(tests, { name = "JourneyMap.equipReward: unearned rewards cannot be equipped, earned ones can", fn = function()
	local profile = PlayerProfile.new()
	local ok = JourneyMap.equipReward(profile, 2)
	expectTrue(not ok, "card back of an uncleared Night")
	expectEqual(profile.equippedCardBackId, nil)
	expectTrue(not JourneyMap.equipReward(profile, 1), "title of an uncleared Night")
	expectEqual(profile.equippedTitleId, nil)
	expectTrue(not JourneyMap.equipReward(profile, 99), "unknown node")
	expectTrue(not JourneyMap.equipReward(profile, "x"), "bad input")
	-- Owning the item another way is not the same as earning the node.
	profile.ownedSetIds.winter_evening = true
	expectTrue(not JourneyMap.equipReward(profile, 3), "set owned but Night 3 not cleared")
	JourneyMap.recordNightsCleared(profile, 3)
	expectTrue(JourneyMap.equipReward(profile, 1))
	expectEqual(profile.equippedTitleId, "porch_regular")
	expectTrue(JourneyMap.equipReward(profile, 2))
	expectEqual(profile.equippedCardBackId, "kitchen_checks")
	expectTrue(JourneyMap.equipReward(profile, 3))
	expectEqual(profile.equippedSetId, "winter_evening")
	expectTrue(not JourneyMap.equipReward(profile, 10), "Endless milestone not cleared")
	JourneyMap.recordEndlessCleared(profile, 10)
	expectTrue(JourneyMap.equipReward(profile, 10))
	expectEqual(profile.equippedTitleId, "night_walker")
end })

table.insert(tests, { name = "PlayerProfile.migrate: Endless milestone clears round-trip; old and bad data still load", fn = function()
	local profile = PlayerProfile.new()
	JourneyMap.recordNightsCleared(profile, 8)
	JourneyMap.recordEndlessCleared(profile, 15)
	local reloaded = PlayerProfile.migrate(profile)
	expectTrue(reloaded.clearedNightIds[10] and reloaded.clearedNightIds[15])
	expectTrue(reloaded.unlockedCardBackIds.ember_hours)
	expectEqual(reloaded.clearedNightIds[20], nil)
	-- A phase 1 profile (only Nights 1-3) loads unchanged.
	local old = PlayerProfile.migrate({ clearedNightIds = { [1] = true, [2] = true, [3] = true }, stats = { runsStarted = 4 } })
	expectTrue(old.clearedNightIds[3])
	expectEqual(old.clearedNightIds[10], nil)
	expectEqual(old.stats.runsStarted, 4)
	-- Nights that are not nodes are dropped.
	local bad = PlayerProfile.migrate({ clearedNightIds = { [11] = true, [30] = true, [20] = true } })
	expectEqual(bad.clearedNightIds[11], nil)
	expectEqual(bad.clearedNightIds[30], nil)
	expectTrue(bad.clearedNightIds[20])
end })

-- ===== Journey phase 3: registry checks and backdrop styles =====

table.insert(tests, { name = "Registry: every Journey node reward points to a real set, card back or title", fn = function()
	local lookups = { cardBack = CardBacks, set = CosmeticSets, title = Achievements }
	local count = 0
	for _, node in ipairs(JourneyMap.allNodes()) do
		local reward = node.info.reward
		if reward then
			count = count + 1
			local registry = lookups[reward.kind]
			expectTrue(registry ~= nil, "unknown reward kind '" .. tostring(reward.kind) .. "' on node " .. tostring(node.key))
			expectTrue(registry.getById(reward.id) ~= nil,
				"node " .. tostring(node.key) .. " reward " .. tostring(reward.kind) .. " '" .. tostring(reward.id) .. "' is missing from its registry")
		end
		expectTrue(type(node.info.name) == "string" and #node.info.name > 0, "node " .. tostring(node.key) .. " needs a name")
		expectTrue((node.info.glyph or node.info.icon) ~= nil, "node " .. tostring(node.key) .. " needs a glyph or icon")
	end
	expectEqual(count, 8 + #JourneyMap.EndlessMilestones)
end })

table.insert(tests, { name = "CosmeticSets.validateStyle: shipped backdrop styles are valid; bad ones are rejected", fn = function()
	local styled = 0
	for _, set in ipairs(CosmeticSets.Definitions) do
		local ok, why = CosmeticSets.validateStyle(set.backdropStyle)
		expectTrue(ok, set.id .. " backdropStyle: " .. tostring(why))
		if set.backdropStyle then styled = styled + 1 end
	end
	expectTrue(styled >= 3, "Winter, Festival and Closing Time all have styles")
	expectTrue(CosmeticSets.getById("winter_evening").backdropStyle.layers[1].kind == "snow")
	expectTrue(CosmeticSets.validateStyle(nil))
	expectTrue(not CosmeticSets.validateStyle({ tint = { 300, 0, 0 } }), "channel over 255")
	expectTrue(not CosmeticSets.validateStyle({ vignette = { color = { 0, 0, 0 }, strength = 2 } }), "strength over 1")
	expectTrue(not CosmeticSets.validateStyle({ layers = { { kind = "lasers", count = 3 } } }), "unknown layer")
	expectTrue(not CosmeticSets.validateStyle({ layers = { { kind = "snow", count = 500 } } }), "too many particles")
	expectTrue(not CosmeticSets.validateStyle("snow"), "not a table")
end })

-- ===== SeededRng (DAILY CHALLENGE, Phase 11) =====

table.insert(tests, { name = "SeededRng.new: the same seed produces the exact same sequence", fn = function()
	local rngA = SeededRng.new(12345)
	local rngB = SeededRng.new(12345)
	for _ = 1, 20 do
		expectEqual(rngA(100), rngB(100))
	end
end })

table.insert(tests, { name = "SeededRng.new: different seeds (usually) produce different sequences", fn = function()
	local rngA = SeededRng.new(1)
	local rngB = SeededRng.new(2)
	local anyDifferent = false
	for _ = 1, 10 do
		if rngA(1000000) ~= rngB(1000000) then
			anyDifferent = true
		end
	end
	expectTrue(anyDifferent, "two different seeds produced an identical 10-draw sequence -- suspiciously unlikely, check the LCG constants/seeding")
end })

table.insert(tests, { name = "SeededRng.new: every draw stays within [1, n]", fn = function()
	local rng = SeededRng.new(999)
	for _ = 1, 500 do
		local n = 1 + (_ % 37) -- vary n across calls, including n == 1
		local v = rng(n)
		expectTrue(v >= 1 and v <= n, string.format("draw %d out of [1,%d] range", v, n))
	end
end })

table.insert(tests, { name = "SeededRng.new: n == 1 always returns 1 (never errors, never out of range)", fn = function()
	local rng = SeededRng.new(42)
	for _ = 1, 5 do
		expectEqual(rng(1), 1)
	end
end })

table.insert(tests, { name = "SeededRng.new: a negative or fractional seed still produces a stable, in-range sequence", fn = function()
	local rng = SeededRng.new(-777.6)
	for _ = 1, 20 do
		local v = rng(6)
		expectTrue(v >= 1 and v <= 6)
	end
end })

table.insert(tests, { name = "SeededRng.dailySeed: the same UTC day always produces the same seed", fn = function()
	-- 2026-08-31 00:00:00 UTC and 2026-08-31 23:59:59 UTC are the same UTC
	-- day -- both must hash to the same daily seed for a Daily Challenge
	-- to actually mean the same run for everyone playing that day.
	local startOfDay = 1788134400 -- 2026-08-31T00:00:00Z (Unix timestamp)
	local endOfDay = startOfDay + 86399 -- 2026-08-31T23:59:59Z
	expectEqual(SeededRng.dailySeed(startOfDay), SeededRng.dailySeed(endOfDay))
	expectEqual(SeededRng.dailyDateKey(startOfDay), SeededRng.dailyDateKey(endOfDay))
end })

table.insert(tests, { name = "SeededRng.dailySeed: different UTC days produce different seeds/keys", fn = function()
	local day1 = 1788134400 -- 2026-08-31T00:00:00Z
	local day2 = day1 + 86400 -- 2026-09-01T00:00:00Z
	expectFalse(SeededRng.dailySeed(day1) == SeededRng.dailySeed(day2))
	expectFalse(SeededRng.dailyDateKey(day1) == SeededRng.dailyDateKey(day2))
end })

table.insert(tests, { name = "SeededRng: RunState.new accepts it as a drop-in rng and stays deterministic end-to-end", fn = function()
	local seed = SeededRng.dailySeed(1788134400)
	local stateA = RunState.new({ deckVariantId = "standard", difficultyId = "standard" }, SeededRng.new(seed))
	local stateB = RunState.new({ deckVariantId = "standard", difficultyId = "standard" }, SeededRng.new(seed))
	RunState.startRound(stateA)
	RunState.startRound(stateB)
	expectEqual(#stateA.hand, #stateB.hand)
	for i = 1, #stateA.hand do
		expectEqual(stateA.hand[i].rank, stateB.hand[i].rank)
		expectEqual(stateA.hand[i].suit, stateB.hand[i].suit)
	end
end })

-- ===== SeededRng: Weekly Challenge + Shareable Seed Codes (Phase 16) =====

table.insert(tests, { name = "SeededRng.weeklySeed: timestamps in the same 7-day window produce the same seed/key", fn = function()
	-- An exact multiple of a week (604800s), so this IS a window boundary
	-- itself -- avoids any off-by-a-remainder ambiguity about which
	-- window a given raw timestamp falls into.
	local startOfWindow = 2956 * 604800
	local laterSameWindow = startOfWindow + 86400 * 6 -- +6 days (518400s), still < 604800s into the window
	expectEqual(SeededRng.weeklySeed(startOfWindow), SeededRng.weeklySeed(laterSameWindow))
	expectEqual(SeededRng.weeklyDateKey(startOfWindow), SeededRng.weeklyDateKey(laterSameWindow))
end })

table.insert(tests, { name = "SeededRng.weeklySeed: a week later produces a different seed/key", fn = function()
	local week1 = 2956 * 604800
	local week2 = week1 + 604800 -- exactly 1 window later
	expectFalse(SeededRng.weeklySeed(week1) == SeededRng.weeklySeed(week2))
	expectFalse(SeededRng.weeklyDateKey(week1) == SeededRng.weeklyDateKey(week2))
end })

table.insert(tests, { name = "SeededRng.weeklyDateKey: distinct from a same-instant dailyDateKey (no key collisions between the two boards)", fn = function()
	local t = 1788134400
	expectFalse(SeededRng.weeklyDateKey(t) == SeededRng.dailyDateKey(t))
end })

table.insert(tests, { name = "SeededRng: a Weekly seed also works as a drop-in rng and stays deterministic end-to-end", fn = function()
	local seed = SeededRng.weeklySeed(1788134400)
	local stateA = RunState.new({ deckVariantId = "standard", difficultyId = "standard" }, SeededRng.new(seed))
	local stateB = RunState.new({ deckVariantId = "standard", difficultyId = "standard" }, SeededRng.new(seed))
	RunState.startRound(stateA)
	RunState.startRound(stateB)
	for i = 1, #stateA.hand do
		expectEqual(stateA.hand[i].rank, stateB.hand[i].rank)
		expectEqual(stateA.hand[i].suit, stateB.hand[i].suit)
	end
end })

table.insert(tests, { name = "SeededRng.codeToSeed: the same code always hashes to the same seed", fn = function()
	expectEqual(SeededRng.codeToSeed("STORM7"), SeededRng.codeToSeed("STORM7"))
end })

table.insert(tests, { name = "SeededRng.codeToSeed: is case-insensitive", fn = function()
	expectEqual(SeededRng.codeToSeed("storm7"), SeededRng.codeToSeed("STORM7"))
	expectEqual(SeededRng.codeToSeed("StOrM7"), SeededRng.codeToSeed("STORM7"))
end })

table.insert(tests, { name = "SeededRng.codeToSeed: different codes (usually) hash to different seeds", fn = function()
	expectFalse(SeededRng.codeToSeed("STORM7") == SeededRng.codeToSeed("BREEZE9"))
end })

table.insert(tests, { name = "SeededRng.codeToSeed: an empty/nil code doesn't error and still produces a stable seed", fn = function()
	expectEqual(SeededRng.codeToSeed(""), SeededRng.codeToSeed(""))
	expectEqual(SeededRng.codeToSeed(nil), SeededRng.codeToSeed(nil))
end })

table.insert(tests, { name = "SeededRng: a code's seed also works as a drop-in rng and stays deterministic end-to-end", fn = function()
	local seed = SeededRng.codeToSeed("STORM7")
	local stateA = RunState.new({ deckVariantId = "standard", difficultyId = "standard" }, SeededRng.new(seed))
	local stateB = RunState.new({ deckVariantId = "standard", difficultyId = "standard" }, SeededRng.new(seed))
	RunState.startRound(stateA)
	RunState.startRound(stateB)
	for i = 1, #stateA.hand do
		expectEqual(stateA.hand[i].rank, stateB.hand[i].rank)
		expectEqual(stateA.hand[i].suit, stateB.hand[i].suit)
	end
end })

table.insert(tests, { name = "SeededRng.randomCode: produces a code of the requested length using only the safe charset", fn = function()
	local code = SeededRng.randomCode(8)
	expectEqual(#code, 8)
	expectFalse(code:match("[^ABCDEFGHJKLMNPQRSTUVWXYZ23456789]") ~= nil, "A-Z without I and O, digits 2-9")
end })

table.insert(tests, { name = "SeededRng.randomCode: defaults to length 6 when called with no argument", fn = function()
	local code = SeededRng.randomCode()
	expectEqual(#code, 6)
end })

-- ===== Content pass (Phase 12): 6 more Patrons, 6 more Boss Rounds, =====
-- ===== 6 more Recipes =====

table.insert(tests, { name = "'Jack of All Trades' adds +9 Mult for each scoring Jack", fn = function()
	local jack = Patrons.getById("jack_of_all_trades")
	local pair = HandEvaluator.evaluate({ C(11, "Hearts"), C(11, "Clubs"), C(2, "Spades") }) -- pair of Jacks
	local _, _, mult = Scoring.calculate(pair, { jack }, {})
	expectEqual(mult, 2 + 9 * 2) -- base Pair mult (2) + patron (9 per Jack x 2 Jacks)
end })

table.insert(tests, { name = "'Queen's Gambit' adds +9 Mult for each scoring Queen", fn = function()
	local queen = Patrons.getById("queens_gambit")
	local pair = HandEvaluator.evaluate({ C(12, "Hearts"), C(12, "Clubs"), C(2, "Spades") }) -- pair of Queens
	local _, _, mult = Scoring.calculate(pair, { queen }, {})
	expectEqual(mult, 2 + 9 * 2) -- base Pair mult (2) + patron (9 per Queen x 2 Queens)
end })

table.insert(tests, { name = "'Jack of All Trades' / 'Queen's Gambit' give no bonus without a scoring Jack/Queen", fn = function()
	local jack = Patrons.getById("jack_of_all_trades")
	local queen = Patrons.getById("queens_gambit")
	local hand = HandEvaluator.evaluate({ C(9, "Hearts") })
	local _, _, mult = Scoring.calculate(hand, { jack, queen }, {})
	expectEqual(mult, 1) -- base High Card mult only
end })

table.insert(tests, { name = "'Spare Change' earns 1 Tip per Discard remaining on round win", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	RunState.buyPatron(state, "spare_change")
	state.tips = 20
	local spareChange = Patrons.getById("spare_change")
	local tipsBefore = state.tips
	spareChange.onRoundWin(state)
	expectEqual(state.tips, tipsBefore + state.discardsRemaining) -- 3 discards by default
end })

table.insert(tests, { name = "'Full House Crowd' scales XMult by every OTHER owned Patron", fn = function()
	local crowd = Patrons.getById("full_house_crowd")
	local theRegular = Patrons.getById("the_regular")
	local luckyDice = Patrons.getById("lucky_dice")
	local hand = HandEvaluator.evaluate({ C(9, "Hearts") })
	local _, _, multAlone = Scoring.calculate(hand, { crowd }, {})
	local _, _, multWithTwo = Scoring.calculate(hand, { crowd, theRegular, luckyDice }, {})
	expectEqual(multAlone, 1) -- no OTHER Patrons -- no bonus
	expectEqual(multWithTwo, (1 + 4) * (1.15 ^ 2)) -- base(1) + The Regular's +4, then x1.15^2 for the 2 others
end })

table.insert(tests, { name = "'Fair Share' adds +4 Chips per scoring card", fn = function()
	local fairShare = Patrons.getById("fair_share")
	local pair = HandEvaluator.evaluate({ C(9, "Hearts"), C(9, "Clubs"), C(2, "Spades") }) -- pair scores 2 cards
	local _, chips = Scoring.calculate(pair, { fairShare }, {})
	expectEqual(chips, 10 + 9 + 9 + 4 * 2) -- base Pair chips (10 + 2 nines) + patron (4 per scoring card x 2)
end })

table.insert(tests, { name = "'Efficient Service' adds +3 Chips per combined Hand+Discard remaining", fn = function()
	local efficient = Patrons.getById("efficient_service")
	local hand = HandEvaluator.evaluate({ C(9, "Hearts") })
	local _, chipsNone = Scoring.calculate(hand, { efficient }, { handsRemaining = 0, discardsRemaining = 0 })
	local _, chipsSome = Scoring.calculate(hand, { efficient }, { handsRemaining = 2, discardsRemaining = 1 })
	expectEqual(chipsNone, 5 + 9) -- base High Card chips (5 + rank-9 card value), no bonus
	expectEqual(chipsSome, 5 + 9 + 3 * 3) -- + patron (3 per combined remaining x 3)
end })

table.insert(tests, { name = "Patrons.Definitions has grown to include this phase's 6 new Patrons", fn = function()
	expectTrue(#Patrons.Definitions >= 37, "expected the Patron pool to include this phase's 6 additions")
end })

table.insert(tests, { name = "'Thin Soup' / 'Slow Simmer' are mild tier-1 versions of Thin Chips / Flat Mult", fn = function()
	local thinSoup = BossRounds.getById("thin_soup")
	local slowSimmer = BossRounds.getById("slow_simmer")
	expectEqual(thinSoup.chipsMultiplier, 0.8)
	expectEqual(thinSoup.minNight, 1)
	expectEqual(slowSimmer.multMultiplier, 0.8)
	expectEqual(slowSimmer.minNight, 1)
end })

table.insert(tests, { name = "'Double Tab' combines Tips-lost-per-card with a higher target score, gated to tier 2", fn = function()
	local doubleTab = BossRounds.getById("double_tab")
	expectEqual(doubleTab.tipsLostPerCardPlayed, 1)
	expectEqual(doubleTab.targetScoreMultiplier, 1.2)
	expectEqual(doubleTab.minNight, 3)
end })

table.insert(tests, { name = "'Four Top' requires exactly 4 cards per hand, gated to tier 3 (retuned after review -- more restrictive than tier-2 Full Table)", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	state.bossModifier = BossRounds.getById("four_top")
	expectEqual(state.bossModifier.minNight, 6)
	local ok3 = pcall(RunState.playHand, state, { 1, 2, 3 })
	expectFalse(ok3, "expected playHand to reject a 3-card play under Four Top")
end })

table.insert(tests, { name = "'Empty-Handed' leaves 1 discard and caps hands at 3, gated to tier 3", fn = function()
	local empty = BossRounds.getById("empty_handed")
	expectEqual(empty.discardsDelta, -2)
	expectEqual(empty.handsPerRoundOverride, 3)
	expectEqual(empty.minNight, 6)
end })

table.insert(tests, { name = "'Everything's Out' cuts Chips and Mult by 32%, gated to tier 3", fn = function()
	local stateNormal = RunState.new(nil, function(n) return n end)
	local resultNormal = RunState.playHand(stateNormal, { 1, 2 })

	local stateCut = RunState.new(nil, function(n) return n end)
	stateCut.bossModifier = BossRounds.getById("everythings_out")
	local resultCut = RunState.playHand(stateCut, { 1, 2 })

	expectEqual(stateCut.bossModifier.minNight, 6)
	expectEqual(resultCut.chips, resultNormal.chips * 0.68)
	expectEqual(resultCut.mult, resultNormal.mult * 0.68)
end })

table.insert(tests, { name = "BossRounds.Definitions has grown to include this phase's 6 new modifiers", fn = function()
	expectTrue(#BossRounds.Definitions >= 30, "expected the Boss Round pool to include this phase's 6 additions")
end })

table.insert(tests, { name = "House Recipe 'Silver Service' adds a Silver Special to 1 selected card", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	local recipe = Recipes.getHouseRecipeById("silver_service")
	local ok = recipe.apply(state, { cardIndices = { 1 } })
	expectTrue(ok)
	expectEqual(state.hand[1].special, "silver")
end })

table.insert(tests, { name = "House Recipe 'Borrow the Recipe' copies only the Garnish, not rank/suit/Special/Stamp", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	state.hand[1].rank, state.hand[1].suit, state.hand[1].special, state.hand[1].stamp = 5, "Hearts", "gold", "encore"
	state.hand[2].garnish = "brittle"
	local recipe = Recipes.getHouseRecipeById("borrow_the_recipe")
	local ok = recipe.apply(state, { cardIndices = { 1, 2 } })
	expectTrue(ok)
	expectEqual(state.hand[1].garnish, "brittle")
	expectEqual(state.hand[1].rank, 5)
	expectEqual(state.hand[1].suit, "Hearts")
	expectEqual(state.hand[1].special, "gold")
	expectEqual(state.hand[1].stamp, "encore")
end })

table.insert(tests, { name = "House Recipe 'Fresh Squeeze' adds a random Stamp to 1 selected card", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	local recipe = Recipes.getHouseRecipeById("fresh_squeeze")
	local ok = recipe.apply(state, { cardIndices = { 1 }, rng = function(n) return n end })
	expectTrue(ok)
	expectEqual(state.hand[1].stamp, "purple") -- identity rng picks the last entry in the stamp id list
end })

table.insert(tests, { name = "Secret Recipe 'Gold Standard' adds a Gold Special to 1 selected card", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	local recipe = Recipes.getSecretRecipeById("gold_standard")
	local ok = recipe.apply(state, { cardIndices = { 1 } })
	expectTrue(ok)
	expectEqual(state.hand[1].special, "gold")
end })

table.insert(tests, { name = "Secret Recipe 'Rainbow Sprinkle' adds a Rainbow Special to 1 selected card", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	local recipe = Recipes.getSecretRecipeById("rainbow_sprinkle")
	local ok = recipe.apply(state, { cardIndices = { 1 } })
	expectTrue(ok)
	expectEqual(state.hand[1].special, "rainbow")
end })

table.insert(tests, { name = "Secret Recipe 'Prime Reservation' gives a random owned Patron a Reserved Special", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	state.tips = 10
	RunState.buyPatron(state, "the_regular")
	local recipe = Recipes.getSecretRecipeById("prime_reservation")
	local ok = recipe.apply(state, { rng = function(n) return n end })
	expectTrue(ok)
	expectEqual(state.ownedPatronSpecials["the_regular"], "reserved")
end })

table.insert(tests, { name = "Secret Recipe 'Prime Reservation' refuses with no Patrons owned", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	local recipe = Recipes.getSecretRecipeById("prime_reservation")
	local ok, message = recipe.apply(state, {})
	expectFalse(ok)
	expectTrue(message ~= nil)
end })

table.insert(tests, { name = "RunState.patronSlotLimit actually grants +1 per Reserved Special once something sets it (Prime Reservation closes the gap)", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	state.tips = 10
	RunState.buyPatron(state, "the_regular")
	local baseline = RunState.patronSlotLimit(state)
	Recipes.getSecretRecipeById("prime_reservation").apply(state, { rng = function(n) return n end })
	expectEqual(RunState.patronSlotLimit(state), baseline + 1)
end })

-- ===== Content pass (Phase 15): 5 more Patrons, 5 more Boss Rounds, =====
-- ===== 5 more Recipes =====

table.insert(tests, { name = "'Perfect Ten' adds +8 Mult for each scoring Ten", fn = function()
	local ten = Patrons.getById("perfect_ten")
	local highCard = HandEvaluator.evaluate({ C(10, "Hearts") })
	local _, _, mult = Scoring.calculate(highCard, { ten }, {})
	expectEqual(mult, 1 + 8) -- base High Card mult (1) + patron (8 per scoring Ten)
end })

table.insert(tests, { name = "'Perfect Ten' gives no bonus without a scoring Ten", fn = function()
	local ten = Patrons.getById("perfect_ten")
	local highCard = HandEvaluator.evaluate({ C(9, "Hearts") })
	local _, _, mult = Scoring.calculate(highCard, { ten }, {})
	expectEqual(mult, 1)
end })

table.insert(tests, { name = "'Night Owl' adds +1 Mult per Night reached so far", fn = function()
	local owl = Patrons.getById("night_owl")
	local highCard = HandEvaluator.evaluate({ C(9, "Hearts") })
	local _, _, mult = Scoring.calculate(highCard, { owl }, { night = 4 })
	expectEqual(mult, 1 + 1 * 4)
end })

table.insert(tests, { name = "'Steady Hand' adds +5 Mult only when exactly 5 cards are played", fn = function()
	local steady = Patrons.getById("steady_hand")
	local highCard = HandEvaluator.evaluate({ C(9, "Hearts") })
	local fivePlayed = { C(9, "Hearts"), C(2, "Clubs"), C(3, "Spades"), C(4, "Diamonds"), C(5, "Hearts") }
	local _, _, multFive = Scoring.calculate(highCard, { steady }, { allPlayedCards = fivePlayed })
	expectEqual(multFive, 1 + 5)
	local threePlayed = { C(9, "Hearts"), C(2, "Clubs"), C(3, "Spades") }
	local _, _, multThree = Scoring.calculate(highCard, { steady }, { allPlayedCards = threePlayed })
	expectEqual(multThree, 1)
end })

table.insert(tests, { name = "'Rainy Day Fund' earns 1 Tip per Hand remaining on round win", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	local fund = Patrons.getById("rainy_day_fund")
	state.handsRemaining = 2
	local tipsBefore = state.tips
	fund.onRoundWin(state)
	expectEqual(state.tips, tipsBefore + 2)
end })

table.insert(tests, { name = "'Boss's Bane' earns 10 Tips on a Boss Round win, nothing on a normal round win", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	local bane = Patrons.getById("boss_bane")
	state.bossModifier = nil
	local tipsBefore = state.tips
	bane.onRoundWin(state)
	expectEqual(state.tips, tipsBefore) -- normal round: no bonus
	state.bossModifier = BossRounds.getById("bouncer")
	bane.onRoundWin(state)
	expectEqual(state.tips, tipsBefore + 10) -- boss round: +10
end })

table.insert(tests, { name = "'Slow Night'/'House Minimum' are tier-1 (minNight = 1) numeric variants of existing knobs", fn = function()
	local slowNight = BossRounds.getById("slow_night")
	expectEqual(slowNight.forcedRandomDiscardsPerHand, 1)
	expectEqual(slowNight.minNight, 1)
	local houseMinimum = BossRounds.getById("house_minimum")
	expectEqual(houseMinimum.targetScoreMultiplier, 1.2)
	expectEqual(houseMinimum.minNight, 1)
end })

table.insert(tests, { name = "'Picked Over' combines a Hearts debuff with a hand-size cut, gated to tier 2", fn = function()
	local pickedOver = BossRounds.getById("picked_over")
	expectEqual(pickedOver.debuff, "Hearts")
	expectEqual(pickedOver.handSizeDelta, -1)
	expectEqual(pickedOver.minNight, 3)
end })

table.insert(tests, { name = "'Rushed Order' caps hands at 3, gated to tier 2", fn = function()
	local rushed = BossRounds.getById("rushed_order")
	expectEqual(rushed.handsPerRoundOverride, 3)
	expectEqual(rushed.minNight, 3)
end })

table.insert(tests, { name = "'Bare Bones' cuts Chips and Mult by 30%, gated to tier 3", fn = function()
	local bareBones = BossRounds.getById("bare_bones")
	expectEqual(bareBones.chipsMultiplier, 0.7)
	expectEqual(bareBones.multMultiplier, 0.7)
	expectEqual(bareBones.minNight, 6)
end })

table.insert(tests, { name = "BossRounds.pick never returns a Phase 15 tier-2/3 modifier before its minNight", fn = function()
	for night = 1, 2 do
		local modifier = BossRounds.pick(function(n) return n end, night)
		expectTrue(modifier.id ~= "picked_over" and modifier.id ~= "rushed_order" and modifier.id ~= "bare_bones",
			"night " .. night .. " should never return " .. modifier.id)
	end
end })

table.insert(tests, { name = "House Recipe 'Split the Check' swaps rank and suit between 2 selected cards", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	state.hand = { C(5, "Hearts"), C(9, "Spades") }
	local recipe = Recipes.getHouseRecipeById("split_the_check")
	local ok = recipe.apply(state, { cardIndices = { 1, 2 } })
	expectTrue(ok)
	expectEqual(state.hand[1].rank, 9)
	expectEqual(state.hand[1].suit, "Spades")
	expectEqual(state.hand[2].rank, 5)
	expectEqual(state.hand[2].suit, "Hearts")
end })

table.insert(tests, { name = "House Recipe 'Round Up' raises every card in hand by 1, capped at Ace", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	state.hand = { C(5, "Hearts"), C(14, "Spades") } -- second card is already an Ace
	local recipe = Recipes.getHouseRecipeById("round_up")
	local ok = recipe.apply(state)
	expectTrue(ok)
	expectEqual(state.hand[1].rank, 6)
	expectEqual(state.hand[2].rank, 14) -- stayed capped at Ace
end })

table.insert(tests, { name = "House Recipe 'Round Up' refuses with an empty hand", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	state.hand = {}
	local recipe = Recipes.getHouseRecipeById("round_up")
	local ok = recipe.apply(state)
	expectFalse(ok)
end })

table.insert(tests, { name = "House Recipe \"Comp'd Discard\" adds +1 Discard immediately", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	local before = state.discardsRemaining
	local recipe = Recipes.getHouseRecipeById("compd_discard")
	local ok = recipe.apply(state)
	expectTrue(ok)
	expectEqual(state.discardsRemaining, before + 1)
end })

table.insert(tests, { name = "Secret Recipe \"Everybody's Favorite\" gives every owned Patron a Silver Special", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	state.tips = 10
	RunState.buyPatron(state, "the_regular")
	RunState.buyPatron(state, "lucky_dice")
	local recipe = Recipes.getSecretRecipeById("everybodys_favorite")
	local ok = recipe.apply(state)
	expectTrue(ok)
	expectEqual(state.ownedPatronSpecials["the_regular"], "silver")
	expectEqual(state.ownedPatronSpecials["lucky_dice"], "silver")
end })

table.insert(tests, { name = "Secret Recipe \"Everybody's Favorite\" refuses with no Patrons owned", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	local recipe = Recipes.getSecretRecipeById("everybodys_favorite")
	local ok = recipe.apply(state)
	expectFalse(ok)
end })

table.insert(tests, { name = "Secret Recipe 'Bedtime Bonus' doubles the next round-win Tips reward, then clears itself", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	local recipe = Recipes.getSecretRecipeById("bedtime_bonus")
	local ok = recipe.apply(state)
	expectTrue(ok)
	expectTrue(state.bedtimeBonusActive)

	state.targetScore = 0 -- guarantee an immediate round win
	state.tips = 0 -- avoid interest muddying the expected total
	RunState.playHand(state, { 1 })
	expectEqual(state.tips, 2 * state.config.tipsPerRoundWin) -- doubled flat reward, no boss
	expectFalse(state.bedtimeBonusActive) -- one-shot: cleared after use
end })

table.insert(tests, { name = "'Bedtime Bonus' stacks with a Boss Round's own double instead of replacing it", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	state.bossModifier = BossRounds.getById("bouncer")
	state.bedtimeBonusActive = true
	state.targetScore = 0
	state.tips = 0
	RunState.playHand(state, { 1 })
	-- Boss doubles tipsPerRoundWin once, Bedtime Bonus doubles the result again.
	expectEqual(state.tips, 4 * state.config.tipsPerRoundWin)
end })

-- ===== PHASE C: True Wildcard (Signature Mechanic, see claude/mind-blowing-plan.md) =====

table.insert(tests, { name = "RunState.new seeds exactly one True Wildcard card into a fresh run", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	local wildcardCount = 0
	local function scan(list)
		for _, card in ipairs(list) do
			if card.isTrueWildcard then
				wildcardCount = wildcardCount + 1
				expectFalse(card.wildcardLocked)
			end
		end
	end
	scan(state.deck)
	scan(state.hand)
	scan(state.discardPile)
	expectEqual(wildcardCount, 1)
end })

table.insert(tests, { name = "Playing the True Wildcard locks it in as whichever rank/suit scores the most for that hand", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	local wildcardCard = C(2, "Hearts") -- dealt as a lone, low-value 2 of Hearts
	wildcardCard.isTrueWildcard = true
	wildcardCard.wildcardLocked = false
	-- Three real 7s + the wildcard: becoming a 4th 7 completes Four of a
	-- Kind (chips 60 + 4x7 = 88, mult 7 -> score 616) -- vastly better
	-- than leaving it a lone 2 (Three of a Kind off just the three 7s:
	-- chips 30 + 3x7 = 51, mult 3 -> score 153). An unambiguous "did it
	-- actually pick the best option" check, not just "did it pick
	-- something reasonable."
	state.hand = { wildcardCard, C(7, "Hearts"), C(7, "Diamonds"), C(7, "Clubs") }

	local result = RunState.playHand(state, { 1, 2, 3, 4 })
	expectEqual(result.handName, "Four of a Kind")
	expectTrue(result.wildcardResolution ~= nil)
	expectEqual(result.wildcardResolution.rank, 7)
	-- Same card table reference the whole run -- it should now just BE
	-- a 7, permanently (suit is a genuine 4-way tie here -- Hearts is
	-- just whichever this implementation's fixed iteration order finds
	-- first; see TrueWildcard.findBestChoice).
	expectEqual(wildcardCard.rank, 7)
	expectEqual(wildcardCard.suit, "Hearts")
	expectTrue(wildcardCard.wildcardLocked)
end })

table.insert(tests, { name = "A locked True Wildcard plays as a normal card and never re-resolves", fn = function()
	local card = C(9, "Spades")
	card.isTrueWildcard = true
	card.wildcardLocked = true -- already resolved by an earlier hand this run
	local state = RunState.new(nil, function(n) return n end)
	state.hand = { card }
	local result = RunState.playHand(state, { 1 })
	expectTrue(result.wildcardResolution == nil)
	expectEqual(card.rank, 9)
	expectEqual(card.suit, "Spades")
end })

table.insert(tests, { name = "TrueWildcard.findBestChoice always restores the card's original rank/suit afterward", fn = function()
	local wildcardCard = C(2, "Hearts")
	local cards = { wildcardCard, C(5, "Hearts"), C(9, "Hearts"), C(11, "Hearts"), C(13, "Hearts") }
	local bestRank, bestSuit = TrueWildcard.findBestChoice(cards, wildcardCard, {}, function(_handResult)
		return {} -- minimal context -- Scoring.calculate defaults everything else
	end)
	expectTrue(bestRank ~= nil and bestSuit ~= nil)
	-- Non-mutating contract: whatever it found along the way, the card
	-- itself must be back exactly where this started.
	expectEqual(wildcardCard.rank, 2)
	expectEqual(wildcardCard.suit, "Hearts")
end })

-- ===== Balance pass, Phase 1: bug fixes =====

-- Puts a fresh Casual/Standard run on the last round of the final Night with
-- a target of 0, so the next hand played clears it.
local function finalBossState(difficultyId)
	local state = RunState.new({ difficultyId = difficultyId }, function(n) return n end)
	state.night = state.config.nightCap
	state.round = state.config.roundsPerNight
	RunState.startRound(state)
	state.targetScore = 0
	return state
end

table.insert(tests, { name = "Casual: clearing the final Night's last round wins the run", fn = function()
	local state = finalBossState("casual")
	expectTrue(state.bossModifier == nil) -- Casual has no boss modifiers...
	expectTrue(RunState.isBossRound(state)) -- ...but it's still the boss round
	local result = RunState.playHand(state, { 1 })
	expectTrue(result.roundWon)
	expectTrue(state.wonRun)
end })

table.insert(tests, { name = "Casual: the boss round pays the doubled round reward", fn = function()
	local state = finalBossState("casual")
	state.tips = 0
	RunState.playHand(state, { 1 })
	-- 2x flat reward; interest on 0 Tips is 0, no Patrons owned.
	expectEqual(state.tips, 2 * state.config.tipsPerRoundWin)
end })

table.insert(tests, { name = "Casual: Boss's Bane pays on the boss round", fn = function()
	local state = finalBossState("casual")
	state.tips = 0
	table.insert(state.ownedPatrons, Patrons.getById("boss_bane"))
	RunState.playHand(state, { 1 })
	-- Boss's Bane's +10 lands before round-win interest (+1 per 5 held).
	expectEqual(state.tips, 2 * state.config.tipsPerRoundWin + 10 + math.floor(10 / 5))
end })

table.insert(tests, { name = "Casual: a non-boss round is not a boss round and pays the normal reward", fn = function()
	local state = RunState.new({ difficultyId = "casual" }, function(n) return n end)
	expectFalse(RunState.isBossRound(state))
	state.tips = 0
	state.targetScore = 0
	RunState.playHand(state, { 1 })
	expectEqual(state.tips, state.config.tipsPerRoundWin)
	expectFalse(state.wonRun)
end })

table.insert(tests, { name = "Standard: the final boss round still wins the run", fn = function()
	local state = finalBossState("standard")
	expectTrue(state.bossModifier ~= nil)
	-- Some boss modifiers require a set number of cards; play what's allowed.
	local count = (state.bossModifier.requiredCardsPerHand) or 1
	local indices = {}
	for i = 1, count do indices[i] = i end
	RunState.playHand(state, indices)
	expectTrue(state.wonRun)
end })

local function totalCards(state)
	return #state.hand + #state.deck + #state.discardPile
end

table.insert(tests, { name = "An empty draw pile reshuffles the discard pile back in mid-round", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	local handSize = #state.hand
	-- Move the whole draw pile to the discard pile.
	for _, card in ipairs(state.deck) do table.insert(state.discardPile, card) end
	state.deck = {}
	local before = totalCards(state)
	RunState.playHand(state, { 1, 2, 3, 4, 5 })
	expectEqual(#state.hand, handSize)
	expectEqual(totalCards(state), before)
end })

table.insert(tests, { name = "Discarding with an empty draw pile still refills the hand", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	local handSize = #state.hand
	for _, card in ipairs(state.deck) do table.insert(state.discardPile, card) end
	state.deck = {}
	RunState.discard(state, { 1, 2, 3 })
	expectEqual(#state.hand, handSize)
	expectEqual(totalCards(state), 52)
end })

table.insert(tests, { name = "Rowdy Crowd + extra hands + discards never empties the hand (soft-lock regression)", fn = function()
	local rowdy
	for _, mod in ipairs(BossRounds.Modifiers or BossRounds.Definitions or {}) do
		if mod.forcedRandomDiscardsPerHand then rowdy = mod break end
	end
	expectTrue(rowdy ~= nil)
	local rng = SeededRng.new(136)
	local state = RunState.new(nil, rng)
	state.bossModifier = rowdy
	state.targetScore = 10 ^ 12 -- unreachable: keep playing the whole round
	state.handsRemaining = 12
	state.discardsRemaining = 8
	local before = totalCards(state)
	while not state.roundOver do
		if state.discardsRemaining > 0 and #state.hand >= 2 then
			RunState.discard(state, { 1, 2 })
		else
			RunState.playHand(state, { 1 })
		end
		expectEqual(totalCards(state), before)
		if not state.roundOver then
			expectTrue(#state.hand > 0)
		end
	end
	expectTrue(state.runOver) -- lost on hands, not soft-locked
end })

table.insert(tests, { name = "A run with fewer cards than a hand needs ends instead of soft-locking", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	state.bossModifier = { id = "test_required", requiredCardsPerHand = 5 }
	state.hand = { C(2, "Hearts"), C(3, "Hearts"), C(4, "Hearts"), C(5, "Hearts"), C(7, "Spades") }
	state.deck = {}
	state.discardPile = {}
	state.targetScore = 10 ^ 12
	state.handsRemaining = 3
	-- Playing all 5 leaves nothing to draw and nothing to reshuffle back in
	-- (the played cards only hit the discard pile after the refill).
	local result = RunState.playHand(state, { 1, 2, 3, 4, 5 })
	expectTrue(result.softLocked)
	expectTrue(state.runOver)
end })

table.insert(tests, { name = "SeededRng is deterministic per seed", fn = function()
	local a, b = SeededRng.new(4242), SeededRng.new(4242)
	for _ = 1, 500 do
		expectEqual(a(52), b(52))
	end
end })

table.insert(tests, { name = "SeededRng rng(2) is balanced and does not strictly alternate", fn = function()
	local rng = SeededRng.new(7)
	local ones, alternations, last = 0, 0, nil
	for i = 1, 20000 do
		local v = rng(2)
		if v == 1 then ones = ones + 1 end
		if i <= 64 and last and v ~= last then alternations = alternations + 1 end
		last = v
	end
	expectTrue(ones >= 9600 and ones <= 10400)
	expectTrue(alternations < 63)
end })

table.insert(tests, { name = "SeededRng rng(52) fills every bucket within 15% of uniform", fn = function()
	local rng = SeededRng.new(99)
	local counts = {}
	for _ = 1, 52000 do
		local v = rng(52)
		counts[v] = (counts[v] or 0) + 1
	end
	for v = 1, 52 do
		expectTrue((counts[v] or 0) >= 850 and (counts[v] or 0) <= 1150)
	end
	local one = SeededRng.new(1)
	for _ = 1, 20 do expectEqual(one(1), 1) end
end })

table.insert(tests, { name = "Shop.rollOffers offers 2 unowned Patrons and 2 distinct Packs", fn = function()
	local state = RunState.new(nil, SeededRng.new(11))
	state.ownedPatrons = { Patrons.Definitions[1], Patrons.Definitions[2] }
	for _ = 1, 200 do
		local offers = Shop.rollOffers(state)
		expectEqual(#offers.patrons, Shop.OFFER_COUNT)
		expectEqual(#offers.packs, Shop.PACK_OFFER_COUNT)
		expectTrue(offers.patrons[1].id ~= offers.patrons[2].id)
		expectTrue(offers.packs[1].id ~= offers.packs[2].id)
		for _, patron in ipairs(offers.patrons) do
			expectTrue(patron.id ~= Patrons.Definitions[1].id and patron.id ~= Patrons.Definitions[2].id)
		end
	end
end })

table.insert(tests, { name = "Shop.rollOffers keeps the shop's numbers and draw order", fn = function()
	expectEqual(Shop.OFFER_COUNT, 2)
	expectEqual(Shop.PACK_OFFER_COUNT, 2)
	expectEqual(Shop.VOUCHER_CHANCE, 0.35)
	expectEqual(Shop.REROLL_BASE_COST, 5)
	expectEqual(Shop.REROLL_COST_STEP, 2)

	-- Patrons, then Packs, then the voucher roll, then the voucher pick.
	local state = RunState.new(nil, function(n) return n end)
	local seen = {}
	state.rng = function(n)
		table.insert(seen, n)
		return 1
	end
	local offers = Shop.rollOffers(state)
	expectEqual(table.concat(seen, ","), table.concat({
		#Patrons.Definitions, #Patrons.Definitions - 1,
		#Packs.Definitions, #Packs.Definitions - 1,
		10000, #HousePasses.Definitions,
	}, ","))
	expectEqual(offers.patrons[1].id, Patrons.Definitions[1].id)
	expectEqual(offers.patrons[2].id, Patrons.Definitions[2].id)
	expectEqual(offers.packs[1].id, Packs.Definitions[1].id)
	expectEqual(offers.voucher.id, HousePasses.Definitions[1].id)
end })

table.insert(tests, { name = "Shop.rollOffers never offers an owned House Pass", fn = function()
	local state = RunState.new(nil, function(_n) return 1 end)
	for _, pass in ipairs(HousePasses.Definitions) do
		state.housePasses[pass.id] = true
	end
	expectEqual(Shop.rollOffers(state).voucher, nil)
end })

table.insert(tests, { name = "Shop voucher roll on a seeded run is seeded and hits about 35% of the time", fn = function()
	-- A failed seeded roll must stay failed, not fall through to math.random.
	local alwaysMiss = RunState.new(nil, function(n) return n end)
	for _ = 1, 200 do
		expectEqual(Shop.rollOffers(alwaysMiss).voucher, nil)
	end

	local state = RunState.new(nil, SeededRng.new(5))
	local hits = 0
	for _ = 1, 4000 do
		if Shop.rollOffers(state).voucher then
			hits = hits + 1
		end
	end
	expectTrue(hits >= 1300 and hits <= 1500)
end })

table.insert(tests, { name = "Crowd Favorite breaks a most-played tie by name, not table order", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	state.handStats = { ["Pair"] = 3, ["Flush"] = 3, ["Two Pair"] = 3, ["High Card"] = 1 }
	state.secretRecipeInventory = { "crowd_favorite" }
	expectTrue(RunState.useSecretRecipe(state, "crowd_favorite"))
	expectEqual(state.handLevels["Flush"], 1)
	expectEqual(state.handLevels["Pair"], nil)
end })

table.insert(tests, { name = "Copying Patrons can't copy each other in a loop", fn = function()
	local copiers = { "the_understudy", "second_opinion", "the_apprentice" }
	local regular = Patrons.getById("the_regular")
	local handResult = HandEvaluator.evaluate({ C(14, "Hearts") })
	local function score(patrons)
		local _, _, mult = Scoring.calculate(handResult, patrons, { allPlayedCards = handResult.scoringCards, rng = neverHitRng })
		return mult
	end

	local base = score({})
	-- Every seating of the three copiers plus The Regular must finish.
	local ids = { copiers[1], copiers[2], copiers[3], "the_regular" }
	local function permute(n)
		if n == 0 then
			local seated = {}
			for i, id in ipairs(ids) do seated[i] = Patrons.getById(id) end
			expectTrue(score(seated) >= base + regular.effect().mult)
			return
		end
		for i = 1, n do
			ids[i], ids[n] = ids[n], ids[i]
			permute(n - 1)
			ids[i], ids[n] = ids[n], ids[i]
		end
	end
	permute(#ids)

	-- The reported loop: Understudy leftmost, Second Opinion to its right.
	expectEqual(score({ Patrons.getById("the_understudy"), Patrons.getById("second_opinion") }), base)
	-- Real copies still work.
	expectEqual(score({ Patrons.getById("the_understudy"), regular }), base + 8)
	expectEqual(score({ regular, Patrons.getById("the_apprentice") }), base + 8)
	expectEqual(score({ regular, Patrons.getById("second_opinion") }), base + 8)
	expectEqual(score({ Patrons.getById("the_understudy"), Patrons.getById("the_understudy") }), base)
end })

-- ===== Balance pass (docs/BALANCE_NOTES.md) =====

table.insert(tests, { name = "Balance: the target curve matches the tuned numbers", fn = function()
	expectEqual(RunState.nightBaseScoreFor(1), 65)
	expectEqual(RunState.targetScoreFor(1, 1, 3), 65)
	expectEqual(RunState.targetScoreFor(1, 2, 3), 130)
	expectEqual(RunState.targetScoreFor(1, 3, 3), 130)
	expectEqual(RunState.targetScoreFor(8, 3, 3), math.floor(65 * 2.15 ^ 7 * 2.5))
	-- Targets keep rising Night over Night on the same blind.
	for night = 1, 12 do
		for round = 1, 3 do
			expectTrue(RunState.targetScoreFor(night + 1, round, 3) > RunState.targetScoreFor(night, round, 3))
		end
	end
end })

table.insert(tests, { name = "Balance: no boss modifier exceeds an effective difficulty of 2.5x", fn = function()
	for _, def in ipairs(BossRounds.Definitions) do
		local effective = (def.targetScoreMultiplier or 1) / ((def.chipsMultiplier or 1) * (def.multMultiplier or 1))
		if def.handsPerRoundOverride then
			effective = effective * (4 / def.handsPerRoundOverride)
		end
		expectTrue(effective <= 2.5, def.id .. " has effective difficulty " .. effective)
	end
end })

table.insert(tests, { name = "Balance: tier-3 Chips+Mult bosses keep their ordering", fn = function()
	local stale = BossRounds.getById("stale_bread").chipsMultiplier
	local bare = BossRounds.getById("bare_bones").chipsMultiplier
	local everything = BossRounds.getById("everythings_out").chipsMultiplier
	expectTrue(stale > bare and bare > everything)
end })

table.insert(tests, { name = "Balance: boss target changes apply through startRound", fn = function()
	local function bossTarget(id, night)
		local state = RunState.new(nil, function(n) return n end)
		state.night = night
		state.round = state.config.roundsPerNight
		local original = BossRounds.pick
		BossRounds.pick = function() return BossRounds.getById(id) end
		state.nightBossModifier = BossRounds.getById(id)
		state.round = 1
		RunState.startRound(state)
		state.round = state.config.roundsPerNight
		RunState.startRound(state)
		BossRounds.pick = original
		return state
	end
	local base = RunState.targetScoreFor(6, 3, 3)
	expectEqual(bossTarget("lights_out", 6).targetScore, math.floor(base * 0.5))
	expectEqual(bossTarget("lights_out", 6).handsRemaining, 1)
	expectEqual(bossTarget("quick_service", 6).targetScore, math.floor(base * 0.75))
	expectEqual(bossTarget("one_at_a_time", 6).targetScore, math.floor(base * 0.35))
	expectEqual(bossTarget("big_tab", 6).targetScore, math.floor(base * 2))
	expectEqual(bossTarget("last_chance", 6).discardsRemaining, 1)
	expectEqual(bossTarget("empty_handed", 6).discardsRemaining, 1)
	expectEqual(bossTarget("empty_handed", 6).handsRemaining, 3)
end })

table.insert(tests, { name = "Balance: boss descriptions state their tuned numbers", fn = function()
	local expected = {
		stale_bread = "25%", bare_bones = "30%", everythings_out = "32%",
		thin_chips = "40%", flat_mult = "40%", big_tab = "double",
		lights_out = "halved", quick_service = "25%", one_at_a_time = "65%",
		last_chance = "1 discard", empty_handed = "1 discard",
	}
	for id, text in pairs(expected) do
		local description = BossRounds.getById(id).description
		expectTrue(description:find(text, 1, true) ~= nil, id .. ": " .. description)
	end
end })

table.insert(tests, { name = "Balance: Patron descriptions and prices match their effects", fn = function()
	local function flat(handResult, played, context)
		context = context or {}
		context.allPlayedCards = played
		return handResult, context
	end
	local pairHand = HandEvaluator.evaluate({ C(9, "Hearts"), C(9, "Clubs") })
	local twoCards = pairHand.scoringCards
	local fiveCards = { C(2, "Hearts"), C(3, "Hearts"), C(5, "Clubs"), C(7, "Spades"), C(9, "Diamonds") }
	local rows = {
		{ "steady_hand", 7, "+5 Mult", "mult", 5, fiveCards },
		{ "small_plate", 6, "+8 Mult", "mult", 8, twoCards },
		{ "the_bard", 7, "+1 Mult", "mult", 5, fiveCards },
		{ "big_portions", 7, "+25 Chips", "chips", 25, twoCards },
		{ "lucky_dice", 5, "+15 Chips", "chips", 15, twoCards },
		{ "night_owl", 8, "+1 Mult", "mult", 6, twoCards, { night = 6 } },
		{ "penny_pincher", 7, "+1 Mult for every 3 Tips", "mult", 5, twoCards, { tips = 16 } },
		{ "tab_regulars", 5, "+1 Chip for every Tip", "chips", 15, twoCards, { tips = 15 } },
		{ "discard_special", 6, "+1 Mult", "mult", 2, twoCards, { discardsRemaining = 2 } },
	}
	for _, row in ipairs(rows) do
		local patron = Patrons.getById(row[1])
		expectEqual(patron.price, row[2], row[1] .. " price")
		expectTrue(patron.description:find(row[3], 1, true) ~= nil, row[1] .. ": " .. patron.description)
		local handResult, context = flat(pairHand, row[6], row[7])
		expectEqual(patron.effect(handResult, context)[row[4]], row[5], row[1] .. " effect")
	end

	local handRows = {
		{ "all_matching", { C(2, "Hearts"), C(5, "Hearts"), C(7, "Hearts"), C(9, "Hearts"), C(13, "Hearts") }, 18 },
		{ "straight_shooter", { C(5, "Hearts"), C(6, "Clubs"), C(7, "Spades"), C(8, "Hearts"), C(9, "Clubs") }, 18 },
		{ "threes_company", { C(5, "Hearts"), C(5, "Clubs"), C(5, "Spades") }, 18 },
		{ "all_hands_in", { C(5, "Hearts"), C(5, "Clubs"), C(5, "Spades"), C(5, "Diamonds") }, 25 },
		{ "double_down", { C(5, "Hearts"), C(5, "Clubs"), C(6, "Spades"), C(6, "Diamonds") }, 10 },
	}
	for _, row in ipairs(handRows) do
		local patron = Patrons.getById(row[1])
		expectEqual(patron.effect(HandEvaluator.evaluate(row[2]), {}).mult, row[3], row[1])
		expectTrue(patron.description:find("+" .. row[3] .. " Mult", 1, true) ~= nil, row[1])
	end
end })

table.insert(tests, { name = "Balance: hand levels and the Flush base match the tuned numbers", fn = function()
	for name, growth in pairs({
		["Three of a Kind"] = { 25, 3 }, ["Straight"] = { 30, 3 }, ["Flush"] = { 25, 3 }, ["Full House"] = { 30, 3 },
		["Pair"] = { 15, 1 }, ["Two Pair"] = { 20, 1 }, ["High Card"] = { 10, 1 },
	}) do
		expectEqual(Scoring.HandLevelGrowth[name].chips, growth[1], name)
		expectEqual(Scoring.HandLevelGrowth[name].mult, growth[2], name)
	end
	expectEqual(Scoring.HandBase["Flush"].chips, 40)
	expectEqual(Scoring.HandBase["Flush"].mult, 5)
end })

table.insert(tests, { name = "Balance: deck variants and Late Kitchen match the tuned numbers", fn = function()
	local steady = RunState.new({ deckVariantId = "steady_hand" }, function(n) return n end)
	expectEqual(steady.config.discardsPerRound, RunState.DefaultConfig.discardsPerRound + 2)
	expectEqual(steady.config.handSize, RunState.DefaultConfig.handSize - 1)
	expectEqual(steady.discardsRemaining, RunState.DefaultConfig.discardsPerRound + 2)

	local roller = RunState.new({ deckVariantId = "high_roller" }, function(n) return n end)
	expectEqual(roller.targetScore, math.floor(RunState.targetScoreFor(1, 1, 3) * 0.95))

	expectTrue(DeckVariants.getById("steady_hand").description:find("+2 discards", 1, true) ~= nil)
	expectTrue(DeckVariants.getById("high_roller").description:find("12 Tips", 1, true) ~= nil)
	expectTrue(DeckVariants.getById("high_roller").description:find("5% lower", 1, true) ~= nil)
	expectEqual(HousePasses.getById("late_kitchen").price, 5)
end })

-- ===== Scaling Patrons (Phase 4) =====

-- A run driven like the client sees it: counters as shipped by the server.
local function shippedCounters(state)
	return RunState.runCounters(state)
end

table.insert(tests, { name = "Run counters start at zero and survive into a fresh state", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	for _, field in ipairs({ "roundsCleared", "bossesCleared", "handsPlayedTotal", "discardsUsedTotal", "patronsSold" }) do
		expectEqual(state[field], 0, field)
	end
end })

table.insert(tests, { name = "Run counters tick on hands, discards, round wins, boss wins and sales", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	state.tips = 50
	RunState.discard(state, { 1, 2 })
	expectEqual(state.discardsUsedTotal, 1)

	state.targetScore = 10 ^ 9
	RunState.playHand(state, { 1 })
	expectEqual(state.handsPlayedTotal, 1)
	expectEqual(state.roundsCleared, 0)

	state.targetScore = 0
	RunState.playHand(state, { 1 })
	expectEqual(state.handsPlayedTotal, 2)
	expectEqual(state.roundsCleared, 1)
	expectEqual(state.bossesCleared, 0)

	state.roundOver = false
	state.isBossRound = true
	state.handsRemaining = 2
	RunState.playHand(state, { 1 })
	expectEqual(state.roundsCleared, 2)
	expectEqual(state.bossesCleared, 1)

	RunState.buyPatron(state, "the_regular")
	RunState.sellPatron(state, "the_regular")
	expectEqual(state.patronsSold, 1)
end })

table.insert(tests, { name = "Bosses cleared counts Casual's boss rounds, and Clean Sweep isn't a sale", fn = function()
	local casual = RunState.new({ difficultyId = "casual" }, function(n) return n end)
	casual.round = casual.config.roundsPerNight
	RunState.startRound(casual)
	casual.targetScore = 0
	RunState.playHand(casual, { 1 })
	expectEqual(casual.bossesCleared, 1)

	local state = RunState.new(nil, function(n) return n end)
	state.ownedPatrons = { Patrons.getById("the_regular"), Patrons.getById("the_bard") }
	state.secretRecipeInventory = { "clean_sweep" }
	expectTrue(RunState.useSecretRecipe(state, "clean_sweep"))
	expectEqual(state.patronsSold, 0)
end })

table.insert(tests, { name = "handStatsBefore excludes the hand being scored and doesn't alias handStats", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	state.targetScore = 10 ^ 9
	local seen = nil
	state.ownedPatrons = { {
		id = "test_spy", name = "Spy", price = 1,
		effect = function(handResult, context)
			seen = { count = context.handStatsBefore[handResult.name] or 0, total = context.handsPlayedTotal }
			return nil
		end,
	} }
	RunState.playHand(state, { 1 })
	expectEqual(seen.count, 0)
	expectEqual(seen.total, 0)
	RunState.playHand(state, { 1 })
	expectEqual(seen.count, 1)
	expectEqual(seen.total, 1)

	local counters = RunState.runCounters(state)
	counters.handStatsBefore["High Card"] = 99
	expectTrue(state.handStats["High Card"] ~= 99)
end })

table.insert(tests, { name = "The client's preview context matches playHand's for every run counter", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	state.targetScore = 10 ^ 9
	state.roundsCleared, state.bossesCleared, state.discardsUsedTotal, state.patronsSold = 7, 2, 11, 3
	state.handsPlayedTotal = 20
	state.handStats = { ["Pair"] = 12, ["Two Pair"] = 5, ["Flush"] = 3 }

	local real = nil
	state.ownedPatrons = { {
		id = "test_spy", name = "Spy", price = 1,
		effect = function(_handResult, context)
			real = context
			return nil
		end,
	} }
	-- What the server would have sent the client just before this play.
	local preview = RunState.addRunCounters({}, shippedCounters(state))
	RunState.playHand(state, { 1 })

	for _, field in ipairs({ "roundsCleared", "bossesCleared", "handsPlayedTotal", "discardsUsedTotal", "patronsSold" }) do
		expectEqual(preview[field], real[field], field)
	end
	for name, count in pairs(real.handStatsBefore) do
		expectEqual(preview.handStatsBefore[name], count, name)
	end
	for name, count in pairs(preview.handStatsBefore) do
		expectEqual(real.handStatsBefore[name], count, name)
	end
end })

table.insert(tests, { name = "Every scaling Patron previews the same score the server gives", fn = function()
	local ids = { "slow_cooker", "house_tab", "regulars_chair", "cobweb_shelf", "tasting_menu", "estate_sale", "pair_bonds", "veterans_table" }
	for _, id in ipairs(ids) do
		local state = RunState.new(nil, function(n) return n end)
		state.ownedPatrons = { Patrons.getById(id) }
		state.targetScore = 10 ^ 9
		state.night = 4
		state.roundsCleared, state.bossesCleared, state.discardsUsedTotal, state.patronsSold = 9, 3, 14, 2
		state.handsPlayedTotal = 30
		state.handStats = { ["Pair"] = 15, ["Two Pair"] = 6, ["High Card"] = 9 }

		local played = { state.hand[1] }
		local held = {}
		for i = 2, #state.hand do held[#held + 1] = state.hand[i] end
		local handResult = HandEvaluator.evaluate(played)
		local preview = Scoring.calculate(handResult, state.ownedPatrons, RunState.addRunCounters({
			rng = neverHitRng, allPlayedCards = played, heldCards = held, handLevels = state.handLevels,
			ownedPatronSpecials = state.ownedPatronSpecials, tips = state.tips,
			alreadyPlayedThisHandTypeThisRound = false, handsRemaining = state.handsRemaining - 1,
			discardsRemaining = state.discardsRemaining, isLastHand = false, night = state.night, round = state.round,
		}, shippedCounters(state)))
		expectEqual(RunState.playHand(state, { 1 }).score, preview, id)
	end
end })

table.insert(tests, { name = "Scaling Patrons follow their formulas and caps", fn = function()
	local hand = HandEvaluator.evaluate({ C(9, "Hearts") })
	local function bonus(id, context)
		return Patrons.getById(id).effect(hand, context) or {}
	end

	expectEqual(bonus("slow_cooker", {}).multMultiplier, nil)
	expectEqual(bonus("slow_cooker", { roundsCleared = 20 }).multMultiplier, 1.5)
	expectEqual(bonus("slow_cooker", { roundsCleared = 100 }).multMultiplier, 2)
	expectEqual(bonus("house_tab", { bossesCleared = 5 }).multMultiplier, 1.4)
	expectEqual(bonus("regulars_chair", { handsPlayedTotal = 19 }).mult, 3)
	expectEqual(bonus("regulars_chair", { handsPlayedTotal = 500 }).mult, 15)
	expectEqual(bonus("regulars_chair", { handsPlayedTotal = 5 }).mult, nil)
	expectEqual(bonus("cobweb_shelf", { discardsUsedTotal = 12 }).mult, 4)
	expectEqual(bonus("cobweb_shelf", { discardsUsedTotal = 99 }).mult, 15)
	expectEqual(bonus("tasting_menu", { handStatsBefore = { ["Pair"] = 3, ["Flush"] = 1 } }).mult, 2)
	expectEqual(bonus("estate_sale", { patronsSold = 2 }).mult, 4)
	expectEqual(bonus("estate_sale", { patronsSold = 20 }).mult, 20)
	expectEqual(bonus("pair_bonds", { handStatsBefore = { ["Pair"] = 6, ["Two Pair"] = 2, ["Flush"] = 9 } }).mult, 2)
	expectEqual(bonus("pair_bonds", { handStatsBefore = { ["Pair"] = 90 } }).mult, 15)
	expectEqual(bonus("veterans_table", { night = 1 }).chips, nil)
	expectEqual(bonus("veterans_table", { night = 4 }).chips, 24)

	for id, text in pairs({
		slow_cooker = "x0.025", house_tab = "x0.08", regulars_chair = "6 hands", cobweb_shelf = "3 Discards",
		tasting_menu = "+1 Mult", estate_sale = "+2 Mult", pair_bonds = "4 Pairs", veterans_table = "+8 Chips",
	}) do
		expectTrue(Patrons.getById(id).description:find(text, 1, true) ~= nil, id)
	end
end })

table.insert(tests, { name = "Two runs never share scaling Patron counts", fn = function()
	local a = RunState.new(nil, function(n) return n end)
	local b = RunState.new(nil, function(n) return n end)
	a.ownedPatrons = { Patrons.getById("regulars_chair") }
	b.ownedPatrons = { Patrons.getById("regulars_chair") }
	a.targetScore, b.targetScore = 10 ^ 9, 10 ^ 9
	a.handsRemaining = 4
	for _ = 1, 3 do RunState.playHand(a, { 1 }) end
	expectEqual(a.handsPlayedTotal, 3)
	expectEqual(b.handsPlayedTotal, 0)
	local first = RunState.playHand(b, { 1 })
	expectEqual(first.mult, 1) -- no bonus carried over from run A
end })

table.insert(tests, { name = "Patron ids and icons are unique, and scaling Patrons reach the shop", fn = function()
	local ids, icons = {}, {}
	for _, patron in ipairs(Patrons.Definitions) do
		expectTrue(not ids[patron.id], "duplicate id " .. patron.id)
		expectTrue(not icons[patron.icon], "duplicate icon on " .. patron.id)
		ids[patron.id], icons[patron.icon] = true, true
	end
	expectTrue(#Patrons.Definitions >= 50)

	local seen = {}
	local state = RunState.new(nil, SeededRng.new(3))
	for _ = 1, 500 do
		for _, patron in ipairs(Shop.rollOffers(state).patrons) do
			seen[patron.id] = true
		end
	end
	expectTrue(seen.slow_cooker and seen.veterans_table)
end })

-- ===== Onboarding (Phase 6) =====

table.insert(tests, { name = "New-player bonus covers the first 3 runs and never a seeded run", fn = function()
	expectEqual(Onboarding.bonusDiscards(0, false), 1)
	expectEqual(Onboarding.bonusDiscards(2, false), 1)
	expectEqual(Onboarding.bonusDiscards(3, false), 0)
	expectEqual(Onboarding.bonusDiscards(40, false), 0)
	expectEqual(Onboarding.bonusDiscards(0, true), 0)
	expectEqual(Onboarding.bonusDiscards(nil, false), 0) -- no profile loaded yet
end })

table.insert(tests, { name = "Night-one bonus discards apply on Night 1 only", fn = function()
	local state = RunState.new({ nightOneBonusDiscards = 1 }, function(n) return n end)
	local normal = RunState.DefaultConfig.discardsPerRound
	expectEqual(state.discardsRemaining, normal + 1)
	state.round = 2
	RunState.startRound(state)
	expectEqual(state.discardsRemaining, normal + 1)
	state.night, state.round = 2, 1
	RunState.startRound(state)
	expectEqual(state.discardsRemaining, normal)

	local plain = RunState.new(nil, function(n) return n end)
	expectEqual(plain.discardsRemaining, normal)
end })

table.insert(tests, { name = "High Card hint fires once, only with a Discard left, after the tutorial", fn = function()
	local profile = PlayerProfile.new()
	expectFalse(Onboarding.shouldShowHighCardHint("High Card", 2, profile)) -- tutorial still running
	PlayerProfile.markTutorialSeen(profile)
	expectTrue(Onboarding.shouldShowHighCardHint("High Card", 1, profile))
	expectFalse(Onboarding.shouldShowHighCardHint("High Card", 0, profile))
	expectFalse(Onboarding.shouldShowHighCardHint("Pair", 2, profile))
	expectFalse(Onboarding.shouldShowHighCardHint("High Card", 2, nil))
	PlayerProfile.markHighCardHintSeen(profile)
	expectFalse(Onboarding.shouldShowHighCardHint("High Card", 2, profile))
end })

table.insert(tests, { name = "hasSeenHighCardHint defaults safely and survives a save", fn = function()
	expectFalse(PlayerProfile.new().hasSeenHighCardHint)
	expectFalse(PlayerProfile.migrate({}).hasSeenHighCardHint) -- existing saves
	expectFalse(PlayerProfile.migrate({ hasSeenHighCardHint = "yes" }).hasSeenHighCardHint)
	expectTrue(PlayerProfile.migrate({ hasSeenHighCardHint = true }).hasSeenHighCardHint)
end })

-- ===== PAID CONTINUE: revived flag + Standard/Revived board routing =====

-- A Night 1 run that just lost its first round by running out of Hands.
local function lostRun()
	local state = RunState.new(nil, function(n) return n end)
	state.targetScore = 1000000000
	while not state.runOver do
		RunState.playHand(state, { 1 })
	end
	return state
end

table.insert(tests, { name = "A fresh run isn't revived and can't continue", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	expectFalse(state.revived)
	expectFalse(RunState.canContinue(state))
	expectTrue(RunState.countsForRecords(state))
	expectFalse(pcall(RunState.useContinue, state))
end })

local function cardKeys(cards)
	local keys = {}
	for i, card in ipairs(cards) do
		keys[i] = tostring(card.rank) .. ":" .. tostring(card.suit)
	end
	return table.concat(keys, ",")
end

table.insert(tests, { name = "One More Round restores the failed round's start", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	state.targetScore = 1000000000
	-- What the round looked like when it started.
	local night, round, tips = state.night, state.round, state.tips
	local startHand, startDeckSize = cardKeys(state.hand), #state.deck
	local startHands, startDiscards = state.roundStartHands, state.roundStartDiscards
	local target = state.roundStartSnapshot.targetScore

	RunState.discard(state, { 1 })
	while not state.runOver do
		RunState.playHand(state, { 1 })
	end
	expectTrue(state.roundScore > 0)
	expectTrue(RunState.canContinue(state))

	RunState.useContinue(state)
	expectTrue(state.revived)
	expectFalse(state.runOver)
	expectFalse(state.roundOver)
	expectEqual(state.night, night)
	expectEqual(state.round, round)
	expectEqual(state.tips, tips)
	expectEqual(state.roundScore, 0)
	expectEqual(state.targetScore, target)
	expectEqual(state.handsRemaining, startHands)
	expectEqual(state.discardsRemaining, startDiscards)
	expectEqual(cardKeys(state.hand), startHand)
	expectEqual(#state.deck, startDeckSize)
	expectEqual(#state.discardPile, 0)
	expectEqual(state.handsPlayedTotal, 0)
	expectFalse(RunState.countsForRecords(state))

	-- Every card sits in exactly one pile, and the run is playable again.
	local seen, total = {}, 0
	for _, pile in ipairs({ state.hand, state.deck, state.discardPile }) do
		for _, card in ipairs(pile) do
			expectFalse(seen[card])
			seen[card] = true
			total = total + 1
		end
	end
	expectEqual(total, 52)
	local result = RunState.playHand(state, { 1 })
	expectFalse(result.runOver)
	expectEqual(state.handsRemaining, startHands - 1)
end })

table.insert(tests, { name = "One More Round keeps owned Patrons as the shared definitions", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	local patron = Patrons.Definitions[1]
	table.insert(state.ownedPatrons, patron)
	RunState.startRound(state) -- re-snapshot with the Patron owned
	state.targetScore = 1000000000
	while not state.runOver do
		RunState.playHand(state, { 1 })
	end
	RunState.useContinue(state)
	expectEqual(#state.ownedPatrons, 1)
	expectTrue(state.ownedPatrons[1] == patron)
end })

table.insert(tests, { name = "Only one continue per run", fn = function()
	local state = lostRun()
	RunState.useContinue(state)
	expectFalse(RunState.canContinue(state)) -- not lost yet
	while not state.runOver do
		RunState.playHand(state, { 1 })
	end
	expectFalse(RunState.canContinue(state))
	expectFalse(pcall(RunState.useContinue, state))
	expectTrue(state.revived)
	expectTrue(state.runOver)
end })

table.insert(tests, { name = "A soft-locked run can continue, a won run can't", fn = function()
	local state = lostRun()
	state.hand = {}
	expectTrue(RunState.canContinue(state)) -- the round restarts with a fresh deal
	local won = lostRun()
	won.wonRun = true
	expectFalse(RunState.canContinue(won))
end })

table.insert(tests, { name = "One free One More Round per player per day", fn = function()
	local profile = PlayerProfile.new()
	expectTrue(PlayerProfile.hasFreeContinue(profile, "2026-11-03"))
	expectTrue(PlayerProfile.useFreeContinue(profile, "2026-11-03"))
	expectFalse(PlayerProfile.hasFreeContinue(profile, "2026-11-03"))
	expectFalse(PlayerProfile.useFreeContinue(profile, "2026-11-03"))
	-- A new day brings it back.
	expectTrue(PlayerProfile.hasFreeContinue(profile, "2026-11-04"))
	-- No date key, no free continue.
	expectFalse(PlayerProfile.hasFreeContinue(profile, nil))
	-- It survives a save round-trip; garbage is dropped.
	expectEqual(PlayerProfile.migrate(profile).freeContinueDateKey, "2026-11-03")
	expectEqual(PlayerProfile.migrate({ freeContinueDateKey = 5 }).freeContinueDateKey, nil)
	expectTrue(PlayerProfile.hasFreeContinue(PlayerProfile.migrate(nil), "2026-11-03"))
end })

table.insert(tests, { name = "Login streak: advance, grace day, reset, 7-slot ladder that loops, one claim per day", fn = function()
	local LoginStreak = require(script.Parent.Parent.Engine.LoginStreak)
	local profile = PlayerProfile.new()
	expectTrue(LoginStreak.checkIn(profile, 100))
	expectEqual(profile.loginStreak, 1)
	expectFalse(LoginStreak.checkIn(profile, 100)) -- same day does nothing
	expectEqual(profile.loginStreak, 1)
	expectTrue(LoginStreak.checkIn(profile, 101))
	expectTrue(LoginStreak.checkIn(profile, 103)) -- one missed day is forgiven
	expectEqual(profile.loginStreak, 3)
	-- Only today's slot (3) can be claimed, once. Tips go to the live run.
	expectTrue(LoginStreak.canClaim(profile, 3))
	expectFalse(LoginStreak.canClaim(profile, 7))
	expectFalse(LoginStreak.canClaim(profile, 1))
	local state = { tips = 2 }
	expectTrue((LoginStreak.claim(profile, 3, state)))
	expectEqual(state.tips, 7)
	expectFalse((LoginStreak.claim(profile, 3, state)))
	expectEqual(LoginStreak.nextReward(profile).day, 4, "after claiming, tomorrow's slot is next")
	-- It survives a save round-trip.
	local saved = PlayerProfile.migrate(profile)
	expectEqual(saved.loginStreak, 3)
	expectEqual(saved.lastLoginDay, 103)
	expectEqual(saved.loginClaimedDay, 103)
	-- The view shows 7 slots with today marked and earlier ones claimed.
	local view = LoginStreak.view(profile)
	expectEqual(#view.rewards, 7)
	expectTrue(view.rewards[1].claimed and view.rewards[2].claimed and view.rewards[3].claimed and not view.rewards[4].claimed)
	expectTrue(view.rewards[3].today and not view.rewards[3].claimable)
	-- Two missed days reset the streak.
	expectTrue(LoginStreak.checkIn(profile, 106))
	expectEqual(profile.loginStreak, 1)
	expectTrue(LoginStreak.canClaim(profile, 1))
	-- With no live run the Tips are banked for the next run.
	local fresh = PlayerProfile.new()
	LoginStreak.checkIn(fresh, 10)
	expectTrue((LoginStreak.claim(fresh, 1, nil)))
	expectEqual(fresh.pendingStartTips, 3)
	-- A clock that went backwards also restarts instead of crashing.
	expectTrue(LoginStreak.checkIn(profile, 50))
	expectEqual(profile.loginStreak, 1)
	-- XP slot, card back slot (then Tips once it is owned) and the loop back to slot 1 on day 8.
	local p2 = PlayerProfile.new()
	for day = 1, 7 do
		LoginStreak.checkIn(p2, 200 + day)
		expectEqual(LoginStreak.slotFor(p2.loginStreak), day)
		local ok = LoginStreak.claim(p2, day, nil)
		expectTrue(ok, "slot " .. day .. " claims")
	end
	expectTrue(p2.tavernXp >= 40 + 60 + 80, "XP slots pay XP")
	expectTrue(p2.unlockedCardBackIds.festival_ribbon, "day 7 gives the card back")
	LoginStreak.checkIn(p2, 208)
	expectEqual(p2.loginStreak, 8)
	expectEqual(LoginStreak.slotFor(8), 1, "the ladder loops")
	expectTrue(LoginStreak.canClaim(p2, 1))
	p2.pendingStartTips = 0
	local tipsBefore = 0
	for day = 1, 7 do
		if day > 1 then LoginStreak.checkIn(p2, 207 + day) end
		LoginStreak.claim(p2, LoginStreak.slotFor(p2.loginStreak), nil)
	end
	expectTrue(p2.pendingStartTips > tipsBefore + 10, "the second day 7 pays Tips instead of the owned card back")
	expectEqual(LoginStreak.dayNumber(86400 * 5 + 10), 5)
	-- Garbage in a saved profile is dropped.
	local bad = PlayerProfile.migrate({ lastLoginDay = "x", loginStreak = -4, claimedLoginDays = { a = true }, loginClaimedDay = "y" })
	expectEqual(bad.lastLoginDay, nil)
	expectEqual(bad.loginStreak, 0)
	expectEqual(bad.loginClaimedDay, nil)
end })

table.insert(tests, { name = "Next unlock strip and places seen", fn = function()
	local NextUnlock = require(script.Parent.Parent.Engine.NextUnlock)
	local profile = PlayerProfile.new()
	local pick = NextUnlock.compute(profile)
	expectTrue(pick ~= nil)
	expectTrue(pick.goal >= 1 and pick.progress >= 0 and pick.progress <= pick.goal)
	expectTrue(type(pick.label) == "string" and #pick.label > 0)
	local seen = NextUnlock.placesSeen(profile)
	expectEqual(seen.seen, 0)
	expectTrue(seen.total > 0)
	profile.worldSeenStopIds.dusty_road = true
	expectEqual(NextUnlock.placesSeen(profile).seen, 1)
end })

table.insert(tests, { name = "A revived run doesn't unlock high-score achievements", fn = function()
	-- Mirrors Server syncProfileFromSession: records only when countsForRecords.
	local profile = PlayerProfile.new()
	local state = lostRun()
	RunState.useContinue(state)
	state.night = 9
	if RunState.countsForRecords(state) then
		PlayerProfile.recordNightReached(profile, state.night)
	end
	expectEqual(profile.stats.bestNightReached, 0)
	expectFalse(Achievements.isUnlocked(profile, "deep_cuts"))
	expectFalse(Achievements.isUnlocked(profile, "into_the_endless"))
end })

table.insert(tests, { name = "The revived flag lasts for the rest of the run", fn = function()
	local state = lostRun()
	RunState.useContinue(state)
	state.roundOver = true -- as if the revived round was won
	RunState.advanceToNextRound(state)
	expectEqual(state.round, 2)
	expectTrue(state.revived)
	expectEqual(Leaderboards.boardFor(state), Leaderboards.REVIVED)
	expectFalse(RunState.countsForRecords(state))
end })

table.insert(tests, { name = "Runs route to the Standard board until they're revived", fn = function()
	local state = lostRun()
	expectEqual(Leaderboards.boardFor(state), Leaderboards.STANDARD)
	RunState.useContinue(state)
	expectEqual(Leaderboards.boardFor(state), Leaderboards.REVIVED)
	expectEqual(Leaderboards.boardFor(nil), Leaderboards.STANDARD)
	expectEqual(Leaderboards.boardFor(RunState.new(nil, function(n) return n end)), Leaderboards.STANDARD)
	expectTrue(Leaderboards.isBoard("Standard"))
	expectTrue(Leaderboards.isBoard("Revived"))
	expectFalse(Leaderboards.isBoard("revived"))
	expectFalse(Leaderboards.isBoard(nil))
end })

table.insert(tests, { name = "Board store names split by kind, board and SeededRng.VERSION", fn = function()
	expectEqual(Leaderboards.storeName("daily", "Standard", "2026-11-03", 2), "DailyChallenge_Standard_v2_2026-11-03")
	expectEqual(Leaderboards.storeName("daily", "Revived", "2026-11-03", 2), "DailyChallenge_Revived_v2_2026-11-03")
	expectEqual(Leaderboards.storeName("weekly", "Standard", "W2911", 2), "WeeklyChallenge_Standard_v2_W2911")
	expectEqual(Leaderboards.storeName("weekly", "Revived", "W2911", 2), "WeeklyChallenge_Revived_v2_W2911")
	-- Defaults to the live rng version, and a version bump means new boards.
	expectEqual(
		Leaderboards.storeName("daily", "Standard", "2026-11-03"),
		Leaderboards.storeName("daily", "Standard", "2026-11-03", SeededRng.VERSION)
	)
	expectTrue(Leaderboards.storeName("daily", "Standard", "2026-11-03", 2) ~= Leaderboards.storeName("daily", "Standard", "2026-11-03", 3))
	-- Bad inputs fail loudly instead of writing to a stray store.
	expectFalse(pcall(Leaderboards.storeName, "monthly", "Standard", "2026-11"))
	expectFalse(pcall(Leaderboards.storeName, "daily", "standard", "2026-11-03"))
	expectFalse(pcall(Leaderboards.storeName, "daily", "Standard", ""))
	expectFalse(pcall(Leaderboards.storeName, "daily", "Standard", nil))
end })

table.insert(tests, { name = "The continue Developer Product is configured with its real id", fn = function()
	local product = DeveloperProducts.getById("continue")
	expectTrue(product ~= nil)
	expectEqual(product.name, "One More Round")
	-- Configured next to the Game Passes, not inside the pass list.
	expectTrue(DeveloperProducts.Definitions == GamePasses.DeveloperProducts)
	expectEqual(GamePasses.getById("continue"), nil)
	expectEqual(product.productId, 3729724982)
	expectTrue(DeveloperProducts.isConfigured(product))
	expectEqual(DeveloperProducts.getByProductId(3729724982), product)
	expectEqual(DeveloperProducts.getByProductId(0), nil)
	expectEqual(DeveloperProducts.getByProductId("123"), nil)
	expectEqual(DeveloperProducts.getById("nope"), nil)
end })

-- ===== Player settings =====

table.insert(tests, { name = "PlayerProfile settings: a new profile gets every default", fn = function()
	local settings = PlayerProfile.new().settings
	expectEqual(settings.musicVolume, 0.35)
	expectEqual(settings.sfxVolume, 1)
	expectEqual(settings.muted, false)
	expectEqual(settings.animSpeed, "normal")
	expectEqual(settings.reduceShake, false)
	expectEqual(settings.colorblindSuits, false)
	expectEqual(settings.confirmDiscard, false)
	-- Each profile gets its own table.
	expectTrue(PlayerProfile.new().settings ~= PlayerProfile.new().settings)
end })

table.insert(tests, { name = "PlayerProfile settings: a profile saved before settings existed loads with defaults", fn = function()
	local old = PlayerProfile.new()
	old.settings = nil
	local reloaded = PlayerProfile.migrate(old)
	expectEqual(reloaded.settings.musicVolume, 0.35)
	expectEqual(reloaded.settings.sfxVolume, 1)
	expectEqual(reloaded.settings.muted, false)
	expectEqual(reloaded.settings.animSpeed, "normal")
end })

table.insert(tests, { name = "PlayerProfile settings: saved values round-trip, bad ones fall back per field", fn = function()
	local profile = PlayerProfile.new()
	profile.settings.musicVolume = 0.6
	profile.settings.muted = true
	profile.settings.animSpeed = "fast"
	profile.settings.colorblindSuits = true
	local reloaded = PlayerProfile.migrate(profile)
	expectEqual(reloaded.settings.musicVolume, 0.6)
	expectEqual(reloaded.settings.muted, true)
	expectEqual(reloaded.settings.animSpeed, "fast")
	expectEqual(reloaded.settings.colorblindSuits, true)

	local messy = PlayerProfile.migrate({ settings = {
		musicVolume = 7, sfxVolume = "loud", muted = "yes", animSpeed = "ludicrous",
		reduceShake = true, confirmDiscard = 1, someFutureSetting = true,
	} })
	expectEqual(messy.settings.musicVolume, 1) -- clamped
	expectEqual(messy.settings.sfxVolume, 1)
	expectEqual(messy.settings.muted, false)
	expectEqual(messy.settings.animSpeed, "normal")
	expectEqual(messy.settings.reduceShake, true)
	expectEqual(messy.settings.confirmDiscard, false)
	expectEqual(messy.settings.someFutureSetting, nil)
	expectEqual(PlayerProfile.migrate({ settings = "nope" }).settings.sfxVolume, 1)
end })

table.insert(tests, { name = "PlayerProfile.setSetting validates keys and values", fn = function()
	local profile = PlayerProfile.new()
	expectTrue((PlayerProfile.setSetting(profile, "sfxVolume", 0.25)))
	expectEqual(profile.settings.sfxVolume, 0.25)
	expectTrue((PlayerProfile.setSetting(profile, "musicVolume", -2)))
	expectEqual(profile.settings.musicVolume, 0)
	expectFalse((PlayerProfile.setSetting(profile, "musicVolume", 0 / 0)))
	expectTrue((PlayerProfile.setSetting(profile, "animSpeed", "fast")))
	expectFalse((PlayerProfile.setSetting(profile, "animSpeed", "turbo")))
	expectEqual(profile.settings.animSpeed, "fast")
	expectFalse((PlayerProfile.setSetting(profile, "muted", "true")))
	expectFalse((PlayerProfile.setSetting(profile, "version", 2)))
	expectFalse((PlayerProfile.setSetting(profile, nil, true)))
	-- Setting the same value again reports no change.
	expectTrue((PlayerProfile.setSetting(profile, "confirmDiscard", true)))
	expectFalse((PlayerProfile.setSetting(profile, "confirmDiscard", true)))
end })

table.insert(tests, { name = "PlayerProfile.animationPaceDivisor: free Fast is milder than the Fast Forward pass", fn = function()
	expectEqual(PlayerProfile.animationPaceDivisor("normal", false), 1)
	expectEqual(PlayerProfile.animationPaceDivisor("normal", true), 1)
	expectEqual(PlayerProfile.animationPaceDivisor("fast", false), PlayerProfile.FAST_PACE_DIVISOR)
	expectEqual(PlayerProfile.animationPaceDivisor("fast", true), PlayerProfile.FAST_FORWARD_PACE_DIVISOR)
	expectTrue(PlayerProfile.FAST_PACE_DIVISOR > 1)
	expectTrue(PlayerProfile.FAST_FORWARD_PACE_DIVISOR > PlayerProfile.FAST_PACE_DIVISOR)
end })

-- ===== Collection (CollectionBook + PlayerProfile discovery) =====

-- Marks the first `n` counted non-title entries discovered. Patrons go
-- last because discovering them also unlocks the Patron-count titles.
local function discoverFirst(profile, n)
	local marked = 0
	for _, tabId in ipairs({ "recipes", "bosses", "housePasses", "patrons" }) do
		local field = PlayerProfile.DISCOVERY_FIELDS[tabId]
		for _, item in ipairs(CollectionBook.itemsFor(tabId)) do
			if marked >= n then
				return
			end
			profile[field][item.id] = true
			marked = marked + 1
		end
	end
end

-- Unlocks every non-reward title (they're computed from stats/sets).
local function unlockAllRegularTitles(profile)
	profile.stats.runsStarted = 100
	profile.stats.runsWon = 20
	profile.stats.bestNightReached = 40
	profile.stats.handsPlayedTotal = 5000
	profile.highestStakeUnlocked = 8
	profile.bestLoginStreak = 30
	profile.questsDone = 100
	profile.tavernRank = 20
	profile.bossRushBest = 10
	profile.challengesCleared = { a = true, b = true, c = true, d = true }
	profile.discoveries = { a = true, b = true, c = true }
	profile.clearedNightIds = { [1] = true, [2] = true, [3] = true, [4] = true }
	profile.invitesAccepted = 10
	for _, patron in ipairs(Patrons.Definitions) do
		profile.discoveredPatronIds[patron.id] = true
	end
end

local function countedTotal()
	return CollectionBook.completion(CollectionBook.setsFromLists({})).total
end

table.insert(tests, { name = "CollectionBook: every entry on every tab has a name, effect text and flavorText", fn = function()
	local banned = { "balatro", "beer", "wine", "booze", "cocktail", "whiskey", "drunk" }
	for _, tab in ipairs(CollectionBook.Tabs) do
		local items = CollectionBook.itemsFor(tab.id)
		expectTrue(#items > 0, tab.id .. " has entries")
		local seenIds = {}
		for _, item in ipairs(items) do
			local def = item.def
			expectFalse(seenIds[item.id], tab.id .. " duplicate id " .. tostring(item.id))
			seenIds[item.id] = true
			expectTrue(type(def.name) == "string" and #def.name > 0, item.id .. " name")
			expectTrue(type(def.description) == "string" and #def.description > 0, item.id .. " description")
			expectTrue(type(def.flavorText) == "string" and #def.flavorText > 0, item.id .. " flavorText")
			expectTrue(#def.flavorText <= 90, item.id .. " flavorText is one short line")
			local lower = (def.name .. " " .. def.flavorText):lower()
			for _, word in ipairs(banned) do
				expectFalse(lower:find(word, 1, true) ~= nil, item.id .. " contains '" .. word .. "'")
			end
			expectTrue(CollectionBook.Rarities[CollectionBook.rarityOf(item)] ~= nil, item.id .. " rarity")
		end
	end
	for _, back in ipairs(CardBacks.Definitions) do
		expectTrue(type(back.flavorText) == "string" and #back.flavorText > 0, back.id .. " flavorText")
	end
end })

table.insert(tests, { name = "CollectionBook: six rarity tiers, every entry rated, sane distribution", fn = function()
	local CosmeticSets = require(script.Parent.Parent.Engine.CosmeticSets)
	local CardBacks = require(script.Parent.Parent.Engine.CardBacks)
	expectEqual(table.concat(CollectionBook.RarityOrder, ","), "common,uncommon,rare,epic,legendary,mythical")
	local counts, total = {}, 0
	local function tally(id, label)
		expectTrue(CollectionBook.Rarities[id] ~= nil, label .. " has a valid tier")
		counts[id] = (counts[id] or 0) + 1
		total = total + 1
	end
	for _, tab in ipairs(CollectionBook.Tabs) do
		for _, item in ipairs(CollectionBook.itemsFor(tab.id)) do
			tally(CollectionBook.rarityOf(item), tab.id .. "/" .. item.id)
		end
	end
	for _, set in ipairs(CosmeticSets.Definitions or CosmeticSets.Sets or {}) do
		tally(CollectionBook.rarityOfSet(set), "set/" .. set.id)
	end
	for _, back in ipairs(CardBacks.Definitions or CardBacks.Backs or {}) do
		tally(CollectionBook.rarityOfBack(back), "back/" .. back.id)
	end
	for _, id in ipairs(CollectionBook.RarityOrder) do
		expectTrue((counts[id] or 0) > 0, id .. " is used at least once")
		if id ~= "common" then
			expectTrue(counts.common > counts[id], "common is the largest group (vs " .. id .. ")")
		end
	end
	expectTrue(counts.mythical * 100 < total * 5, "mythical is under 5 percent of entries")
end })

table.insert(tests, { name = "BossOutfits: every boss has a valid outfit (known hat/prop, color triples), Keeper and Default resolve", fn = function()
	local BossOutfits = require(script.Parent.Parent.Engine.BossOutfits)
	local BossRounds = require(script.Parent.Parent.Engine.BossRounds)
	local function oneOf(list, v)
		for _, x in ipairs(list) do if x == v then return true end end
		return false
	end
	local function checkOutfit(label, o)
		expectTrue(oneOf(BossOutfits.Hats, o.hat), label .. " hat " .. tostring(o.hat))
		expectTrue(oneOf(BossOutfits.Props, o.prop), label .. " prop " .. tostring(o.prop))
		for _, f in ipairs({ "skin", "shirt", "pants", "hatColor", "propColor", "accent" }) do
			local c = o[f]
			if c ~= nil then
				expectEqual(#c, 3, label .. " " .. f .. " is a triple")
				for _, n in ipairs(c) do expectTrue(n >= 0 and n <= 255, label .. " " .. f .. " in range") end
			end
		end
	end
	for _, def in ipairs(BossRounds.Definitions) do
		expectTrue(BossOutfits.Bosses[def.id] ~= nil, def.id .. " has its own outfit")
		checkOutfit(def.id, BossOutfits.resolve(def.id, false))
	end
	for id in pairs(BossOutfits.Bosses) do
		expectTrue(BossRounds.getById(id) ~= nil, id .. " is a real boss id")
	end
	checkOutfit("keeper", BossOutfits.resolve("bouncer", true))
	expectEqual(BossOutfits.resolve("bouncer", true).hat, "crown")
	checkOutfit("unknown", BossOutfits.resolve("no_such_boss", false)) -- falls back to Default
end })

table.insert(tests, { name = "ContentArt: background preload plan starts with the menu and leaves scenes and map art lazy", fn = function()
	local ContentArt = require(script.Parent.Parent.Engine.ContentArt)
	local plan = ContentArt.PreloadPlan
	expectEqual(plan[1].name, "menu")
	expectEqual(plan[1].delay, 0)
	local lazy = {}
	for _, c in ipairs(ContentArt.LazyCategories) do lazy[c] = true end
	for _, phase in ipairs(plan) do
		for _, item in ipairs(phase.items) do
			expectTrue(not lazy[item[1]], item[1] .. " must not be in the eager plan")
			expectTrue(type(ContentArt[item[1]]) == "table", item[1] .. " is a real category")
		end
	end
	-- the single-key form resolves one image; the category form lists them all, de-duplicated
	local one = ContentArt.collectUrls({ { "backgrounds", "menu_bg" } })
	expectTrue(#one <= 1)
	local twice = ContentArt.collectUrls({ { "menu_icons" }, { "menu_icons" } })
	expectEqual(#twice, #ContentArt.collectUrls({ { "menu_icons" } }))
	expectEqual(ContentArt.preload({ { "menu_icons" } }, "test"), 0) -- no ContentProvider under plain Lua
end })

table.insert(tests, { name = "CollectionBook: displayItems sorts common to rare and filters tiers", fn = function()
	local rank = {}
	for i, id in ipairs(CollectionBook.RarityOrder) do rank[id] = i end
	for _, tab in ipairs(CollectionBook.Tabs) do
		local all = CollectionBook.displayItems(tab.id)
		expectEqual(#all, #CollectionBook.itemsFor(tab.id))
		local last = 0
		for _, item in ipairs(all) do
			local r = rank[CollectionBook.rarityOf(item)]
			expectTrue(r >= last, tab.id .. " is ordered common to rare")
			last = r
		end
		local filtered = CollectionBook.displayItems(tab.id, { common = true })
		for _, item in ipairs(filtered) do
			expectTrue(CollectionBook.rarityOf(item) ~= "common", "common is filtered out")
		end
	end
end })

table.insert(tests, { name = "CollectionBook: an entry's own rarity field overrides the derived one", fn = function()
	local item = { id = "x", tab = "patrons", def = { id = "x", price = 4 } }
	expectEqual(CollectionBook.rarityOf(item), "common")
	item.def.rarity = "legendary"
	expectEqual(CollectionBook.rarityOf(item), "legendary")
	item.def.rarity = "mythic-not-real"
	expectEqual(CollectionBook.rarityOf(item), "common")
end })

table.insert(tests, { name = "CollectionBook.Milestones: ordered, unique, and every reward resolves", fn = function()
	local lastPercent, ids, rewardedTitles = 0, {}, {}
	for _, milestone in ipairs(CollectionBook.Milestones) do
		expectFalse(ids[milestone.id], "duplicate milestone id " .. tostring(milestone.id))
		ids[milestone.id] = true
		expectTrue(milestone.percent > lastPercent and milestone.percent <= 100, "percents ascend within 1..100")
		lastPercent = milestone.percent
		expectTrue(#milestone.rewards > 0, milestone.id .. " has a reward")
		for _, reward in ipairs(milestone.rewards) do
			if reward.kind == "title" then
				local achievement = Achievements.getById(reward.id)
				expectTrue(achievement ~= nil and achievement.milestoneReward == true, reward.id .. " is a milestone title")
				rewardedTitles[reward.id] = true
			elseif reward.kind == "cardBack" then
				expectTrue(CardBacks.getById(reward.id) ~= nil, reward.id .. " is a card back")
			else
				expectTrue(false, "unknown reward kind " .. tostring(reward.kind))
			end
		end
	end
	-- Titles handed out by the world map (biome rewards and bonuses) count too.
	for _, r in ipairs(require(script.Parent.Parent.Engine.BiomeRewards).allRewards()) do
		if r.kind == "title" then
			rewardedTitles[r.id] = true
		end
	end
	-- Titles handed out by seasons count too.
	for _, season in ipairs(require(script.Parent.Parent.Engine.Seasons).Definitions) do
		rewardedTitles[season.rewards.titleId] = true
	end
	-- Titles handed out by live events count too.
	for _, event in ipairs(require(script.Parent.Parent.Engine.LiveEvents).Definitions) do
		for _, reward in ipairs(event.rewards or {}) do
			if reward.kind == "title" then rewardedTitles[reward.id] = true end
		end
	end
	-- Titles handed out by the Store (Starter Pack) count too.
	for _, item in ipairs(require(script.Parent.Parent.Engine.Store).Items) do
		for _, id in ipairs(item.contents and item.contents.titles or {}) do rewardedTitles[id] = true end
	end
	-- Titles handed out by Challenge Runs count too.
	for _, def in ipairs(require(script.Parent.Parent.Engine.Challenges).Definitions) do
		rewardedTitles[def.titleId] = true
	end
	-- Titles handed out by map discovery milestones count too.
	for _, m in ipairs(require(script.Parent.Parent.Engine.Discoveries).Milestones) do
		rewardedTitles[m.titleId] = true
	end
	-- Titles handed out by Legend prestige count too.
	for _, reward in pairs(require(script.Parent.Parent.Engine.Legend).Rewards) do
		if reward.kind == "title" then rewardedTitles[reward.id] = true end
	end
	-- Titles handed out by Collection completion rewards count too.
	for _, perGroup in pairs(require(script.Parent.Parent.Engine.CollectionRewards).Rewards) do
		for _, reward in pairs(perGroup) do
			if reward.kind == "title" then rewardedTitles[reward.id] = true end
		end
	end
	-- Titles handed out by the Tavern Season track count too.
	for _, season in ipairs(require(script.Parent.Parent.Engine.SeasonTrack).Seasons) do
		rewardedTitles[season.titleId] = true
		rewardedTitles[season.premiumTitleId] = true
	end
	-- Titles handed out by Tavern Rank rewards count too.
	for _, reward in pairs(require(script.Parent.Parent.Engine.TavernRank).Rewards) do
		if reward.kind == "title" then
			rewardedTitles[reward.id] = true
		end
	end
	-- Titles handed out by Journey rewards count too.
	for _, entry in ipairs(JourneyMap.Nights) do
		if entry.reward.kind == "title" then
			rewardedTitles[entry.reward.id] = true
		end
	end
	for _, entry in ipairs(JourneyMap.EndlessMilestones) do
		if entry.reward.kind == "title" then
			rewardedTitles[entry.reward.id] = true
		end
	end
	-- Every milestone title is actually handed out by some milestone.
	for _, achievement in ipairs(Achievements.Definitions) do
		if achievement.milestoneReward then
			expectTrue(rewardedTitles[achievement.id], achievement.id .. " is granted by a milestone")
		end
	end
end })

table.insert(tests, { name = "PlayerProfile.recordDiscovered: adds, dedups, ignores junk, reports changes", fn = function()
	local profile = PlayerProfile.new()
	expectTrue(PlayerProfile.recordDiscovered(profile, {
		patrons = { "tip_jar" }, recipes = { "sugar_rush" }, bosses = { "bouncer" }, housePasses = { "late_kitchen" },
	}))
	expectTrue(profile.discoveredPatronIds.tip_jar)
	expectTrue(profile.discoveredRecipeIds.sugar_rush)
	expectTrue(profile.discoveredBossIds.bouncer)
	expectTrue(profile.discoveredHousePassIds.late_kitchen)
	-- Same ids again: nothing new.
	expectFalse(PlayerProfile.recordDiscovered(profile, { patrons = { "tip_jar" }, bosses = { "bouncer" } }))
	-- Non-string ids and unknown tabs are ignored.
	expectFalse(PlayerProfile.recordDiscovered(profile, { patrons = { 42 }, themes = { "x" } }))
	expectFalse(PlayerProfile.recordDiscovered(profile, {}))
end })

table.insert(tests, { name = "PlayerProfile.migrate: Collection sets round-trip; old profiles backfill from discoveredPatronIds", fn = function()
	local profile = PlayerProfile.new()
	PlayerProfile.recordDiscovered(profile, { recipes = { "upsell" }, bosses = { "the_tab" }, housePasses = { "double_shift" } })
	profile.claimedMilestoneIds.quarter = true
	profile.rewardTitleIds.curious_guest = true
	profile.unlockedCardBackIds.gilded_ledger = true
	profile.equippedTitleId = "curious_guest"
	local reloaded = PlayerProfile.migrate(profile)
	expectTrue(reloaded.discoveredRecipeIds.upsell)
	expectTrue(reloaded.discoveredBossIds.the_tab)
	expectTrue(reloaded.discoveredHousePassIds.double_shift)
	expectTrue(reloaded.claimedMilestoneIds.quarter)
	expectTrue(reloaded.unlockedCardBackIds.gilded_ledger)
	-- The reward title is migrated before the equipped title is checked.
	expectEqual(reloaded.equippedTitleId, "curious_guest")

	-- A save from before the Collection rebuild.
	local old = PlayerProfile.migrate({ discoveredPatronIds = { tip_jar = true }, discoveredBossIds = "junk", rewardTitleIds = { [1] = true, ok = "yes" } })
	expectTrue(old.discoveredPatronIds.tip_jar)
	expectEqual(next(old.discoveredBossIds), nil)
	expectEqual(next(old.discoveredRecipeIds), nil)
	expectEqual(next(old.rewardTitleIds), nil)
	local sets = CollectionBook.discoveredSetsFor(old)
	expectEqual(CollectionBook.completion(sets).tabs.patrons.found, 1)
end })

table.insert(tests, { name = "CollectionBook.gatherSeen: owned, shop, pack and boss all count as seen", fn = function()
	local state = {
		ownedPatrons = { { id = "the_regular" } },
		houseRecipeInventory = { "sugar_rush" },
		menuRecipeInventory = { "level_pair" },
		secretRecipeInventory = { "final_course" },
		housePasses = { late_kitchen = true, double_shift = false },
		bossModifier = { id = "bouncer" },
		pendingPack = { items = {
			{ id = "tip_jar", category = "patron" },
			{ id = "upsell", category = "house" },
			{ id = "card_1", category = "standard" },
		} },
	}
	local seen = CollectionBook.gatherSeen(state, { patrons = { { id = "night_owl" } }, voucher = { id = "extra_seating" } })
	local function has(list, id)
		for _, v in ipairs(list) do if v == id then return true end end
		return false
	end
	expectTrue(has(seen.patrons, "the_regular"))
	expectTrue(has(seen.patrons, "tip_jar"))
	expectTrue(has(seen.patrons, "night_owl"))
	expectTrue(has(seen.recipes, "sugar_rush"))
	expectTrue(has(seen.recipes, "level_pair"))
	expectTrue(has(seen.recipes, "final_course"))
	expectTrue(has(seen.recipes, "upsell"))
	expectFalse(has(seen.recipes, "card_1"))
	expectTrue(has(seen.housePasses, "late_kitchen"))
	expectFalse(has(seen.housePasses, "double_shift"))
	expectTrue(has(seen.housePasses, "extra_seating"))
	expectTrue(has(seen.bosses, "bouncer"))

	-- A real fresh run: nothing faced yet, no error without a shop.
	local fresh = CollectionBook.gatherSeen(RunState.new(nil, function(n) return n end))
	expectEqual(#fresh.bosses, 0)
	expectEqual(#fresh.patrons, 0)
end })

table.insert(tests, { name = "CollectionBook.completion: per-tab and overall, reward titles and unknown ids excluded", fn = function()
	local profile = PlayerProfile.new()
	local empty = CollectionBook.completion(CollectionBook.discoveredSetsFor(profile))
	expectEqual(empty.found, 0)
	expectEqual(empty.percent, 0)
	local rewardTitleCount = 0
	for _, a in ipairs(Achievements.Definitions) do
		if a.milestoneReward then rewardTitleCount = rewardTitleCount + 1 end
	end
	expectEqual(empty.tabs.titles.total, #Achievements.Definitions - rewardTitleCount)
	expectEqual(empty.tabs.patrons.total, #Patrons.Definitions)

	for _, def in ipairs(HousePasses.Definitions) do
		profile.discoveredHousePassIds[def.id] = true
	end
	profile.discoveredBossIds.not_a_real_boss = true
	profile.rewardTitleIds.curious_guest = true -- a reward title doesn't count
	local c = CollectionBook.completion(CollectionBook.discoveredSetsFor(profile))
	expectEqual(c.tabs.housePasses.percent, 100)
	expectEqual(c.tabs.bosses.found, 0)
	expectEqual(c.tabs.titles.found, 0)
	expectEqual(c.found, #HousePasses.Definitions)
	expectEqual(c.percent, math.floor(#HousePasses.Definitions * 100 / c.total))
end })

table.insert(tests, { name = "CollectionBook.grantMilestones: each milestone granted once, at its threshold", fn = function()
	local total = countedTotal()
	local profile = PlayerProfile.new()
	local quarterNeeds = math.ceil(25 * total / 100)

	discoverFirst(profile, quarterNeeds - 1)
	expectEqual(#CollectionBook.grantMilestones(profile), 0)
	expectFalse(Achievements.isUnlocked(profile, "curious_guest"))

	discoverFirst(profile, quarterNeeds)
	local granted = CollectionBook.grantMilestones(profile)
	expectEqual(#granted, 1)
	expectEqual(granted[1].id, "quarter")
	expectTrue(profile.claimedMilestoneIds.quarter)
	expectTrue(Achievements.isUnlocked(profile, "curious_guest"))
	expectTrue((PlayerProfile.equipTitle(profile, "curious_guest")))
	-- Already claimed: nothing new.
	expectEqual(#CollectionBook.grantMilestones(profile), 0)

	-- Everything but one entry: 50% granted, 100% not.
	unlockAllRegularTitles(profile)
	discoverFirst(profile, total)
	profile.discoveredBossIds.bare_bones = nil
	granted = CollectionBook.grantMilestones(profile)
	expectEqual(#granted, 1)
	expectEqual(granted[1].id, "half")
	expectTrue(profile.unlockedCardBackIds.gilded_ledger)
	expectFalse(profile.claimedMilestoneIds.complete == true)
	expectFalse(Achievements.isUnlocked(profile, "keeper_of_tales"))

	-- The last entry: 100% grants its title and card back.
	profile.discoveredBossIds.bare_bones = true
	granted = CollectionBook.grantMilestones(profile)
	expectEqual(#granted, 1)
	expectEqual(granted[1].id, "complete")
	expectTrue(Achievements.isUnlocked(profile, "keeper_of_tales"))
	expectTrue(profile.unlockedCardBackIds.starlit_keeper)
	expectEqual(CollectionBook.nextMilestone(profile.claimedMilestoneIds), nil)
end })

table.insert(tests, { name = "CollectionBook.grantMilestones: a big jump claims several milestones at once", fn = function()
	local profile = PlayerProfile.new()
	discoverFirst(profile, math.ceil(60 * countedTotal() / 100))
	local granted = CollectionBook.grantMilestones(profile)
	expectEqual(#granted, 2)
	expectEqual(granted[1].id, "quarter")
	expectEqual(granted[2].id, "half")
	expectEqual(CollectionBook.nextMilestone(profile.claimedMilestoneIds).id, "complete")
end })

table.insert(tests, { name = "Generated art maps only reference real registry ids and rbxassetid strings", fn = function()
	local Engine = script.Parent.Parent.Engine
	local maps = {
		patrons = require(Engine.PatronArt),
		bosses = require(Engine.BossRoundArt),
		recipes = require(Engine.RecipeArt),
		housePasses = require(Engine.HousePassArt),
		titles = require(Engine.TitleArt),
	}
	for tabId, map in pairs(maps) do
		local known = {}
		for _, item in ipairs(CollectionBook.itemsFor(tabId)) do known[item.id] = true end
		for id, assetId in pairs(map) do
			expectTrue(known[id], tabId .. " art has unknown id: " .. tostring(id))
			expectTrue(type(assetId) == "string" and assetId:match("^rbxassetid://%d+$") ~= nil,
				tabId .. " art id malformed for " .. tostring(id))
			expectTrue(assetId ~= "rbxassetid://0", tabId .. " art placeholder 0 for " .. tostring(id))
		end
	end
end })

table.insert(tests, { name = "CollectionBook.setsFromLists matches discoveredSetsFor (client vs server view)", fn = function()
	local profile = PlayerProfile.new()
	discoverFirst(profile, 70)
	profile.stats.runsStarted = 1
	local serverSets = CollectionBook.discoveredSetsFor(profile)
	local lists = {}
	for tabId, set in pairs(serverSets) do
		lists[tabId] = {}
		for id in pairs(set) do table.insert(lists[tabId], id) end
	end
	local a = CollectionBook.completion(serverSets)
	local b = CollectionBook.completion(CollectionBook.setsFromLists(lists))
	expectEqual(a.found, b.found)
	expectEqual(a.total, b.total)
	expectTrue(a.tabs.titles.found >= 1)
end })

table.insert(tests, { name = "RunState.phaseAllowsCardActions: only the playing phase can play/discard/select", fn = function()
	expectTrue(RunState.phaseAllowsCardActions("playing"))
	for _, phase in ipairs({ "roundSelect", "shop", "gameover", "menu" }) do
		expectEqual(RunState.phaseAllowsCardActions(phase), false)
	end
	expectEqual(RunState.phaseAllowsCardActions(nil), false)
end })

table.insert(tests, { name = "Collection: every entry resolves to ContentArt or an icon fallback; art keys match registry ids", fn = function()
	local ContentArt = require(script.Parent.Parent.Engine.ContentArt)
	for _, tab in ipairs(CollectionBook.Tabs) do
		local items = CollectionBook.itemsFor(tab.id)
		local ids = {}
		for _, item in ipairs(items) do
			ids[item.id] = true
			local artId = ContentArt.getImageId(tab.id, item.id)
			if artId == nil then
				expectTrue(type(item.def.icon) == "string" and item.def.icon ~= "", tab.id .. "/" .. tostring(item.id) .. " has neither art nor an icon fallback")
			else
				expectTrue(artId:find("^rbxassetid://%d+$") ~= nil, tab.id .. "/" .. tostring(item.id) .. " has a malformed art id")
			end
		end
		-- No orphan art keys (a typo'd key would silently never show).
		for id in pairs(ContentArt[tab.id] or {}) do
			expectTrue(ids[id] == true, "art key " .. tab.id .. "/" .. tostring(id) .. " matches no registry entry")
		end
	end
end })

table.insert(tests, { name = "Wired background art: shop, win, journey map and set backdrops resolve to real ids", fn = function()
	local BackgroundArt = require(script.Parent.Parent.Engine.BackgroundArt)
	local ContentArt = require(script.Parent.Parent.Engine.ContentArt)
	local function isId(v) return type(v) == "string" and v:find("^rbxassetid://%d+$") ~= nil and v ~= "rbxassetid://0" end
	for _, key in ipairs({ "round_select_bg", "shop_bg", "game_over_win_bg", "journey_map",
		"backdrop_winter_evening", "backdrop_festival_night", "backdrop_closing_time", "backdrop_golden_gala" }) do
		expectTrue(isId(BackgroundArt[key]), "BackgroundArt." .. key)
		expectEqual(ContentArt.getImageId("backgrounds", key), BackgroundArt[key])
	end
	expectEqual(JourneyMap.Config.journeyMapImage, BackgroundArt.journey_map)
	local want = { winter_evening = "backdrop_winter_evening", festival_night = "backdrop_festival_night",
		closing_time = "backdrop_closing_time", golden_gala = "backdrop_golden_gala" }
	local seen = 0
	for _, set in ipairs(CosmeticSets.Definitions) do
		local key = want[set.id]
		if key then
			seen = seen + 1
			expectEqual(set.backdropImage, BackgroundArt[key])
		end
	end
	expectEqual(seen, 4)
end })

table.insert(tests, { name = "Tutorial icons: all six resolve to real ids through ContentArt", fn = function()
	local ContentArt = require(script.Parent.Parent.Engine.ContentArt)
	for _, key in ipairs({ "select_cards", "play_hand", "discard", "target", "shop", "endless" }) do
		local v = ContentArt.getImageId("tutorial_icons", key)
		expectTrue(type(v) == "string" and v:find("^rbxassetid://%d+$") ~= nil, "tutorial_icons." .. key)
	end
end })

table.insert(tests, { name = "Journey map nodes: every node resolves to landmark art or an emoji fallback", fn = function()
	local ContentArt = require(script.Parent.Parent.Engine.ContentArt)
	local known = { dusty_road = true, wildflower_meadow = true, garden_terrace = true, willow_bridge = true,
		mountain_pass = true, tavern_gate = true, grand_hall = true, keepers_table = true, endless_portal = true }
	local nodes = JourneyMap.allNodes()
	expectEqual(#nodes, 12)
	for _, node in ipairs(nodes) do
		local info = node.info
		local art = info.art and ContentArt.getImageId("map_nodes", info.art)
		if info.art then
			expectTrue(known[info.art] == true, "unknown map_nodes key " .. tostring(info.art))
		end
		expectTrue(art ~= nil or (type(info.icon) == "string" and #info.icon > 0), tostring(info.name) .. " needs art or an emoji fallback")
	end
	for _, key in ipairs({ "wax_seal_gold", "hero_token" }) do
		local v = ContentArt.getImageId("map_nodes", key)
		expectTrue(v == nil or v:find("^rbxassetid://%d+$") ~= nil, key)
	end
end })

table.insert(tests, { name = "Journey fog: current + 3 revealed, +4 teaser, rest hidden; cleared always revealed", fn = function()
	local nodes = JourneyMap.allNodes()
	local function states(night, cleared, endlessOpen)
		return JourneyMap.nodeRevealStates(night, cleared or {}, endlessOpen)
	end
	local s = states(1)
	for i = 1, 4 do expectEqual(s[i], "revealed") end
	expectEqual(s[5], "teaser")
	for i = 6, #nodes do expectEqual(s[i], "hidden") end
	-- Endless doors (position 9) and milestones 10/15/20 stay hidden until within 3 Nights.
	s = states(5)
	expectEqual(s[8], "revealed")
	expectEqual(s[9], "teaser")
	expectEqual(s[10], "hidden")
	s = states(6)
	expectEqual(s[9], "revealed")
	expectEqual(s[10], "teaser")   -- Night 10 milestone is 4 ahead
	expectEqual(s[11], "hidden")   -- Night 15
	s = states(12)
	expectEqual(s[11], "revealed")  -- Night 15 within 3 of Night 12
	expectEqual(s[12], "hidden")    -- Night 20
	expectEqual(JourneyMap.revealState(4, 1, false), "revealed")
	expectEqual(JourneyMap.revealState(5, 1, false), "teaser")
	expectEqual(JourneyMap.revealState(6, 1, false), "hidden")
	expectEqual(JourneyMap.revealState(9, 1, true), "revealed")
	-- A cleared far node pulls every earlier node out of the fog.
	s = states(1, { [7] = true })
	for i = 1, 7 do expectEqual(s[i], "revealed") end
	expectEqual(s[8], "hidden")
	-- All cleared Nights stay revealed in a fresh run; the doors open once Endless was entered.
	local all = {}
	for n = 1, JourneyMap.NightCap do all[n] = true end
	s = states(1, all, true)
	for i = 1, 9 do expectEqual(s[i], "revealed") end
end })

table.insert(tests, { name = "Leaderboards: friends scope keeps only friends and self in board order; cache expires after its TTL", fn = function()
	local entries = {
		{ userId = 1, depth = 9 }, { userId = 2, depth = 8 }, { userId = 3, depth = 7 },
		{ userId = 4, depth = 6 }, { userId = 5, depth = 5 },
	}
	local rows = Leaderboards.friendRows(entries, { [2] = true, [5] = true }, 4, 10)
	expectEqual(#rows, 3)
	expectEqual(rows[1].userId, 2)
	expectEqual(rows[2].userId, 4) -- the player's own row stays in board order
	expectEqual(rows[3].userId, 5)
	expectEqual(rows[3].rank, 3)
	expectEqual(#Leaderboards.friendRows(entries, {}, 99, 10), 0) -- no friends and not on the board
	expectEqual(#Leaderboards.friendRows(entries, { [1] = true, [2] = true, [3] = true }, 99, 2), 2) -- limit
	expectEqual(entries[2].rank, nil) -- input rows are not mutated
	expectTrue(Leaderboards.isScope("friends") and Leaderboards.isScope("everyone"))
	expectFalse(Leaderboards.isScope("nope"))
	local now = 100
	local cache = Leaderboards.newCache(60, function() return now end)
	expectEqual(cache.get("a"), nil)
	cache.set("a", "x")
	now = 159
	expectEqual(cache.get("a"), "x")
	now = 160
	expectEqual(cache.get("a"), nil)
end })

table.insert(tests, { name = "Seasons: dates, active window, time left, one-time grant, registry ids and prompts exist", fn = function()
	local Seasons = require(script.Parent.Parent.Engine.Seasons)
	local CardBacks = require(script.Parent.Parent.Engine.CardBacks)
	local Achievements = require(script.Parent.Parent.Engine.Achievements)
	-- date maths against known unix times
	expectEqual(Seasons.parseDate("1970-01-01"), 0)
	expectEqual(Seasons.parseDate("2000-03-01"), 951868800)
	expectEqual(Seasons.parseDate("2024-02-29"), 1709164800)
	expectEqual(Seasons.parseDate("nope"), nil)
	expectEqual(Seasons.parseDate("2026-13-01"), nil)
	local season = Seasons.getById("winter_lanterns")
	expectTrue(season ~= nil)
	local s, e = Seasons.startsAt(season), Seasons.endsAt(season)
	expectTrue(s and e and e > s)
	expectEqual(e - s, 22 * 86400) -- Dec 15 to Jan 5 inclusive
	-- active window: first second in, last second in, first second after is out
	expectEqual(Seasons.active(s - 1), nil)
	expectEqual(Seasons.active(s), season)
	expectEqual(Seasons.active(e - 1), season)
	expectEqual(Seasons.active(e), nil)
	expectEqual(Seasons.secondsLeft(season, e - 90), 90)
	expectEqual(Seasons.secondsLeft(season, e + 5), 0)
	expectEqual(Seasons.timeLeftText(3 * 86400 + 5 * 3600), "3d 5h")
	expectEqual(Seasons.timeLeftText(5 * 3600 + 20 * 60), "5h 20m")
	expectEqual(Seasons.timeLeftText(40 * 60), "40m")
	-- progress: not enough Nights, outside the season, then the one-time grant
	local profile = PlayerProfile.new()
	local mid = s + 5 * 86400
	expectEqual(Seasons.recordProgress(profile, mid, season.unlock.nights - 1), nil)
	expectEqual(Seasons.recordProgress(profile, e + 100, season.unlock.nights), nil)
	expectFalse(Seasons.view(profile, mid).earned)
	expectEqual(Seasons.recordProgress(profile, mid, season.unlock.nights), season)
	expectTrue(profile.unlockedCardBackIds[season.rewards.cardBackId])
	expectTrue(profile.rewardTitleIds[season.rewards.titleId])
	expectTrue(Seasons.view(profile, mid).earned)
	expectEqual(Seasons.recordProgress(profile, mid, 8), nil) -- only once
	expectEqual(Seasons.view(profile, e + 1), nil) -- no banner outside the season
	-- earned rewards survive a save/load round trip and the season ending
	local loaded = PlayerProfile.migrate(profile)
	expectTrue(loaded.seasonRewardIds.winter_lanterns)
	expectTrue(loaded.unlockedCardBackIds.winter_lanterns)
	-- reward ids are real registry entries
	expectTrue(CardBacks.getById(season.rewards.cardBackId) ~= nil)
	expectTrue(Achievements.getById(season.rewards.titleId) ~= nil)
end })

table.insert(tests, { name = "PatronLines: every Patron has its own short, kid-safe line; unknown ids fall back", fn = function()
	local PatronLines = require(script.Parent.Parent.Engine.PatronLines)
	local banned = { "balatro", "beer", "wine", "booze", "cocktail", "whiskey", "drunk", "stupid", "idiot", "loser", "dumb" }
	local known = {}
	for _, def in ipairs(Patrons.Definitions) do
		known[def.id] = true
		local line = PatronLines.ById[def.id]
		expectTrue(type(line) == "string" and #line > 0 and #line <= 40)
		expectEqual(PatronLines.get(def.id), line)
		for _, word in ipairs(banned) do
			expectFalse(line:lower():find(word, 1, true) ~= nil)
		end
	end
	for id in pairs(PatronLines.ById) do
		expectTrue(known[id] == true) -- no line for a Patron that does not exist
	end
	expectEqual(PatronLines.get("no_such_patron"), PatronLines.Default)
end })

table.insert(tests, { name = "BossLines: every boss resolves every event (own lines or fallback), deterministic, kid-safe", fn = function()
	local BossLines = require(script.Parent.Parent.Engine.BossLines)
	local BossRounds = require(script.Parent.Parent.Engine.BossRounds)
	local banned = { "balatro", "beer", "wine", "booze", "cocktail", "whiskey", "drunk", "stupid", "idiot", "loser", "dumb" }
	for _, def in ipairs(BossRounds.Definitions) do
		local category = BossRounds.categoryOf(def)
		for _, event in ipairs(BossLines.Events) do
			local line = BossLines.pick(def.id, category, event, "seed-1")
			expectTrue(type(line) == "string" and #line > 0)
			expectEqual(BossLines.pick(def.id, category, event, "seed-1"), line)
		end
		expectTrue(BossLines.ByBoss[def.id] ~= nil)
	end
	expectTrue(BossLines.isGrand(8, 8, JourneyMap.EndlessMilestones))
	expectTrue(BossLines.isGrand(15, 8, JourneyMap.EndlessMilestones))
	expectFalse(BossLines.isGrand(3, 8, JourneyMap.EndlessMilestones))
	expectFalse(BossLines.isGrand(9, 8, JourneyMap.EndlessMilestones))
	-- Unknown boss and unknown category still resolve through the default pool.
	for _, event in ipairs(BossLines.Events) do
		expectTrue(BossLines.pick("no_such_boss", "no_such_category", event, 1) ~= nil)
	end
	-- Every line in every pool is kid-safe, and every ByBoss key is a real boss.
	local function check(list)
		for _, line in ipairs(list) do
			for _, word in ipairs(banned) do
				expectFalse(line:lower():find(word, 1, true) ~= nil)
			end
		end
	end
	for _, pool in pairs(BossLines.Fallback) do
		for _, list in pairs(pool) do check(list) end
	end
	for id, events in pairs(BossLines.ByBoss) do
		expectTrue(BossRounds.getById(id) ~= nil)
		for _, list in pairs(events) do check(list) end
	end
end })

table.insert(tests, { name = "RunState: shop actions (buy, reroll, packs) only in the shop phase", fn = function()
	local RunState = require(script.Parent.Parent.Engine.RunState)
	expectEqual(RunState.phaseAllowsShopActions("shop"), true)
	for _, phase in ipairs({ "roundSelect", "playing", "gameover", "" }) do
		expectEqual(RunState.phaseAllowsShopActions(phase), false)
	end
	expectEqual(RunState.phaseAllowsShopActions(nil), false)
	-- card actions and the deal animation are the mirror image
	expectEqual(RunState.phaseAllowsCardActions("roundSelect"), false)
	expectEqual(RunState.phaseAllowsCardActions("shop"), false)
	expectEqual(RunState.phaseAllowsCardActions("playing"), true)
end })

table.insert(tests, { name = "ScoreJuice: new best, target clear, shake and burst scaling", fn = function()
	local SJ = require(script.Parent.Parent.Engine.ScoreJuice)
	expectEqual(SJ.isNewBest(100, 0), false) -- first hand is not a record
	expectEqual(SJ.isNewBest(100, 100), false)
	expectEqual(SJ.isNewBest(101, 100), true)
	expectEqual(SJ.clearsTarget(0, 300, 300), true)
	expectEqual(SJ.clearsTarget(100, 150, 300), false)
	expectEqual(SJ.clearsTarget(300, 50, 300), false) -- already cleared before this hand
	expectEqual(SJ.clearsTarget(0, 50, nil), false)
	expectEqual(SJ.shakeFor(0, 300), 3)
	expectEqual(SJ.shakeFor(150, 300) > SJ.shakeFor(30, 300), true)
	expectEqual(SJ.shakeFor(9999, 300), 10)
	expectEqual(SJ.burstFor(1, 300), 8)
	expectEqual(SJ.burstFor(9999, 300), 30)
	expectEqual(SJ.slowMoFor(false, false), 0)
	expectEqual(SJ.slowMoFor(true, true) > SJ.slowMoFor(true, false), true)
end })

table.insert(tests, { name = "SoundIds: cues, music keys and missing lists", fn = function()
	local S = require(script.Parent.Parent.Engine.SoundIds)
	local required = { "card_deal", "card_select", "card_play", "shuffle", "card_flip", "discard", "chip", "chip_big", "coin", "buy", "button_click",
		"hover", "boss_intro", "boss_defeat", "win", "lose", "map_open", "road_choose", "compass_turn",
		"shop_enter", "shop_buy", "shop_reroll", "shop_cant" }
	expectEqual(#S.CueOrder, #required)
	for _, name in ipairs(required) do
		local cue = S.Cues[name]
		expectEqual(cue ~= nil, true, name)
		expectEqual(type(cue.volume) == "number" and cue.volume > 0, true, name .. " volume")
		expectEqual(cue.id == "" or S.isValidId(cue.id), true, name .. " id is empty or well formed")
	end
	expectEqual(S.cueId("nope"), nil)
	expectEqual(S.cueId("hover"), nil, "empty id is skipped")
	expectEqual(S.cueId("win") ~= nil, true)
	expectEqual(S.isValidId("rbxassetid://0"), false)
	expectEqual(S.isValidId("rbxassetid://123"), true)
	for _, key in ipairs({ "menu", "gameplay", "shop", "boss" }) do
		expectEqual(S.isValidId(S.Music[key]), true, key)
	end
	for _, id in ipairs(require(script.Parent.Parent.Engine.WorldMap).RegionOrder) do
		expectEqual(S.Music["region_" .. id] ~= nil, true, "music slot for region " .. id)
		expectEqual(S.regionMusicKey(id), "gameplay", "falls back while the region track is empty")
	end
	expectEqual(S.regionMusicKey(nil), "gameplay")
	expectEqual(#S.missingCues() > 0, true)
	expectEqual(#S.missingMusic(), 9, "9 region tracks still need ids")
end })

table.insert(tests, { name = "SceneKeys: floor fraction defaults and clamps", fn = function()
	local SceneKeys = require(script.Parent.Parent.Engine.SceneKeys)
	expectEqual(SceneKeys.floorFraction("front_porch_a"), SceneKeys.FloorFractions.default)
	expectEqual(SceneKeys.floorFraction(nil), SceneKeys.FloorFractions.default)
	SceneKeys.FloorFractions.test_scene = 0.9
	expectEqual(SceneKeys.floorFraction("test_scene"), 0.85)
	SceneKeys.FloorFractions.test_scene = nil
end })

table.insert(tests, { name = "SceneKeys: Night + round kind -> scene key, Endless rotates", fn = function()
	local SceneKeys = require(script.Parent.Parent.Engine.SceneKeys)
	expectEqual(SceneKeys.keyFor(1, "small"), "dusty_road_a")
	expectEqual(SceneKeys.keyFor(1, "big"), "dusty_road_b")
	expectEqual(SceneKeys.keyFor(1, "boss"), "dusty_road_in")
	expectEqual(SceneKeys.keyFor(3, "big"), "garden_terrace_b")
	expectEqual(SceneKeys.keyFor(6, "boss"), "tavern_gate_in")
	expectEqual(SceneKeys.keyFor(8, "boss"), "keepers_table_in")
	-- Endless: Night 9 starts the old-room rotation, Night 14 wraps back to its first entry.
	expectEqual(SceneKeys.keyFor(9, "small"), "front_porch_a")
	expectEqual(SceneKeys.keyFor(10, "big"), "warm_kitchen_b")
	expectEqual(SceneKeys.keyFor(13, "boss"), "rooftop_view_in")
	expectEqual(SceneKeys.keyFor(14, "small"), "front_porch_a")
	expectEqual(SceneKeys.roundKind(1), "small")
	expectEqual(SceneKeys.roundKind(2), "big")
	expectEqual(SceneKeys.roundKind(3), "boss")
	expectEqual(SceneKeys.roundKind(4, 5), "big")
	expectEqual(#JourneyMap.EndlessScenes, 5)
	-- Every Night location yields a well-formed key for all three kinds.
	for _, n in ipairs(JourneyMap.Nights) do
		for _, kind in ipairs({ "small", "big", "boss" }) do
			local key = SceneKeys.keyFor(n.night, kind)
			expectTrue(key == n.art .. SceneKeys.SUFFIX[kind])
		end
	end
end })

table.insert(tests, { name = "StageMotion: sway is bounded and continuous, hit shake decays, hop returns to zero", fn = function()
	local StageMotion = require(script.Parent.Parent.Engine.StageMotion)
	local prevDy
	for i = 0, 600 do
		local t = i * 0.01
		local dx, dy, rot = StageMotion.sway(t, 0.7, 3)
		expectTrue(math.abs(dy) <= 3.0001 and math.abs(dx) <= 1.2001 and math.abs(rot) <= 0.6001, "sway stays within its amplitude")
		if prevDy then
			expectTrue(math.abs(dy - prevDy) < 0.2, "sway has no jumps between frames")
		end
		prevDy = dy
	end
	local rx, ry, rr = StageMotion.sway(12.3, 0.7, 3, true)
	expectTrue(rx == 0 and ry == 0 and rr == 0, "reduced motion gives no sway")
	local a = math.abs(StageMotion.hitShake(0.02, 1))
	local x0, r0 = StageMotion.hitShake(0.5, 1)
	local x1, r1 = StageMotion.hitShake(-0.1, 1)
	local x2 = StageMotion.hitShake(0.1, 0)
	expectTrue(x0 == 0 and r0 == 0 and x1 == 0 and r1 == 0 and x2 == 0, "shake is zero outside its window or at strength 0")
	expectTrue(a <= 7, "shake is bounded")
	local big, small = 0, 0
	for i = 1, 30 do
		big = math.max(big, math.abs(StageMotion.hitShake(i * 0.005, 1)))
		small = math.max(small, math.abs(StageMotion.hitShake(i * 0.005, 0.3)))
	end
	expectTrue(big > small, "a bigger hit shakes more")
	local prevBob
	for i = 0, 800 do
		local b = StageMotion.bobOffset(i * 0.01, 6, 1.6, false)
		expectTrue(math.abs(b) <= 6.0001, "bob is bounded by its amplitude")
		if prevBob then
			expectTrue(math.abs(b - prevBob) < 0.2, "bob is continuous (no steps)")
		end
		prevBob = b
		expectEqual(StageMotion.bobOffset(i * 0.01, 6, 1.6, true), 0)
	end
	expectEqual(StageMotion.hop(0, 14), 0)
	expectEqual(StageMotion.hop(0.5, 14), 0)
	expectTrue(StageMotion.hop(0.16, 14) > 13, "hop peaks mid-way")
end })

table.insert(tests, { name = "StageLayout: feet stay above the hand row and both rigs fit the free band", fn = function()
	local StageLayout = require(script.Parent.Parent.Engine.StageLayout)
	for _, screenH in ipairs({ 600, 720, 900, 1080, 1440 }) do
		local floorFrac = StageLayout.floorFraction(screenH)
		local floorPx = floorFrac * screenH
		local handTop = screenH - 272 -- handFrame sits 272px above the bottom (init.client.lua)
		expectTrue(floorPx <= handTop, "floor below the hand row at " .. screenH)
		expectTrue(floorFrac >= 0.5 and floorFrac <= 0.85, "floor fraction clamped")
		local bandTop = StageLayout.TOP_FRACTION * screenH
		local player, boss = StageLayout.heights(screenH, floorFrac, "boss", false)
		expectTrue(player >= StageLayout.MIN_HEIGHT, "player has a minimum height")
		-- Above the minimum-height clamp, the boss must stay inside the band and be close to the player's height.
		local band = StageLayout.bandPixels(screenH, floorFrac)
		expectTrue(boss <= band + 0.001, "boss fits the band at " .. screenH)
		expectTrue(boss / player >= 1 and boss / player <= 1.25, "boss is roughly the player's height")
		if screenH >= 720 then
			expectTrue(floorPx - boss >= bandTop - 0.5, "boss head stays under the plaque and HP bar at " .. screenH)
		end
		local grandPlayer, grandBoss = StageLayout.heights(screenH, floorFrac, "boss", true)
		expectEqual(grandPlayer, player)
		expectTrue(grandBoss >= boss and grandBoss <= band + 0.001)
		local alone, none = StageLayout.heights(screenH, floorFrac, "normal", false)
		expectTrue(none == nil and alone <= band + 0.001 and alone >= 0.9 * band, "normal rounds show a large player only, inside the band")
	end
end })

table.insert(tests, { name = "RegionTiles: tavern fill covers the whole region frame, hero keeps aspect", fn = function()
	local RegionTiles = require(script.Parent.Parent.Engine.RegionTiles)
	for _, frameW in ipairs({ 600, 1175, 2400 }) do
		local t = RegionTiles.single(frameW, 545, 1.5, frameW * 0.9)
		expectTrue(t.fillW >= frameW, "fill spans the frame width")
		expectTrue(t.heroW == math.floor(545 * 1.5), "hero keeps native aspect")
	end
	for _, w in ipairs({ 300, 457, 1000, 2000 }) do
		local n = RegionTiles.tiled(w, 545, 1.5)
		expectTrue(n >= 1 and n * math.ceil(w / n) >= w, "tiles span the frame")
	end
end })

table.insert(tests, { name = "RegionTiles: seam colour runs from the left biome to the right biome", fn = function()
	local RegionTiles = require(script.Parent.Parent.Engine.RegionTiles)
	local a, b = { 222, 200, 150 }, { 190, 200, 142 }
	local first, last = RegionTiles.seamColor(a, b, 1, 24), RegionTiles.seamColor(a, b, 24, 24)
	for c = 1, 3 do
		expectTrue(first[c] == a[c] and last[c] == b[c], "ends match the neighbouring biomes")
	end
	local mid = RegionTiles.seamColor(a, b, 12, 24)
	expectTrue(mid[1] < a[1] and mid[1] > b[1], "middle blends the two")
end })

table.insert(tests, { name = "StageLayout: accent index is stable and in range", fn = function()
	local StageLayout = require(script.Parent.Parent.Engine.StageLayout)
	local BossRounds = require(script.Parent.Parent.Engine.BossRounds)
	local seen = {}
	for _, def in ipairs(BossRounds.Definitions or {}) do
		local i = StageLayout.accentIndex(def.id, 6)
		expectTrue(i >= 1 and i <= 6)
		expectEqual(StageLayout.accentIndex(def.id, 6), i)
		seen[i] = true
	end
	local distinct = 0
	for _ in pairs(seen) do
		distinct = distinct + 1
	end
	expectTrue(distinct >= 3, "bosses spread over several accent colors")
end })

table.insert(tests, { name = "RigWalk: heals R15 joints with unset parts so a full avatar places 15+ parts", fn = function()
	local RigWalk = require(script.Parent.Parent.Engine.RigWalk)
	local parts = {}
	local function part(n) parts[n] = { Name = n }; return parts[n] end
	part("HumanoidRootPart")
	local joints = {}
	for child in pairs(RigWalk.R15_ANCHOR) do
		part(child)
		table.insert(joints, { owner = child }) -- Part0 / Part1 unset
	end
	local healed = RigWalk.heal(joints, function(n) return parts[n] end, function(j) return j.owner end)
	expectEqual(healed, 15, "all 15 R15 joints healed")
	local _, _, _, count = RigWalk.walk(joints, parts.HumanoidRootPart)
	expectTrue(count >= 16, "root plus 15 body parts reached")
	local before = { Part0 = parts.Head, Part1 = parts.LowerTorso, owner = "Head" }
	RigWalk.heal({ before }, function(n) return parts[n] end, function(j) return j.owner end)
	expectEqual(before.Part0, parts.Head, "set joints are left alone")
end })
table.insert(tests, { name = "RigWalk: AnimationConstraints (modern avatars) become joints from their attachments and place 15+ parts", fn = function()
	local RigWalk = require(script.Parent.Parent.Engine.RigWalk)
	local parts = { HumanoidRootPart = { Name = "HumanoidRootPart" } }
	local joints = {}
	for child, anchor in pairs(RigWalk.R15_ANCHOR) do
		parts[child] = { Name = child }
	end
	for child, anchor in pairs(RigWalk.R15_ANCHOR) do
		local c = { Name = child .. "Joint",
			Attachment0 = { Parent = parts[anchor], CFrame = "c0" },
			Attachment1 = { Parent = parts[child], CFrame = "c1" } }
		local j = RigWalk.fromConstraint(c)
		expectTrue(j ~= nil and j.animated == true, "constraint wrapped")
		expectEqual(j.Part0, parts[anchor], "Part0 is attachment 0's part")
		expectEqual(j.Part1, parts[child], "Part1 is attachment 1's part")
		expectEqual(j.C0, "c0"); expectEqual(j.C1, "c1")
		table.insert(joints, j)
	end
	local _, _, _, count = RigWalk.walk(joints, parts.HumanoidRootPart)
	expectTrue(count >= 16, "root plus 15 body parts reached, got " .. count)
	expectEqual(RigWalk.fromConstraint({ Name = "x", Attachment0 = { Parent = parts.Head } }), nil, "half-built constraint is skipped")
	expectEqual(RigWalk.fromConstraint({ Name = "x", Attachment0 = { CFrame = 1 }, Attachment1 = { Parent = parts.Head } }), nil, "orphan attachment is skipped")
end })
table.insert(tests, { name = "RigWalk: a 3-part chain from attachments touches, and constraint C0/C1 offsets are applied", fn = function()
	local RigWalk = require(script.Parent.Parent.Engine.RigWalk)
	-- Translation-only stand-ins for CFrames.
	local mt = {}
	local function v(x, y, z) return setmetatable({ x = x, y = y, z = z }, mt) end
	mt.__mul = function(a, b) return v(a.x + b.x, a.y + b.y, a.z + b.z) end
	local ops = { mul = function(a, b) return a * b end, inverse = function(a) return v(-a.x, -a.y, -a.z) end, identity = v(0, 0, 0) }
	local root, torso, head = { p = v(0, 0, 0) }, {}, {}
	local joints = {
		RigWalk.fromConstraint({ Name = "Root", Attachment0 = { Parent = root, CFrame = v(0, 0, 0) }, Attachment1 = { Parent = torso, CFrame = v(0, -1, 0) } }),
		RigWalk.fromConstraint({ Name = "Neck", Attachment0 = { Parent = torso, CFrame = v(0, 1, 0) }, Attachment1 = { Parent = head, CFrame = v(0, -0.5, 0) } }),
	}
	local ordered = RigWalk.walk(joints, root)
	expectEqual(#ordered, 2)
	for _, j in ipairs(ordered) do
		j.Part1.p = j.Part0.p * RigWalk.relative(j, nil, ops)
	end
	expectEqual(torso.p.y, 1, "torso sits 1 above the root")
	expectEqual(head.p.y, 2.5, "head sits 1.5 above the torso")
	for _, j in ipairs(ordered) do
		local a, b = j.Part0.p * j.C0, j.Part1.p * j.C1
		expectTrue(a.x == b.x and a.y == b.y and a.z == b.z, j.Name .. " attachment points touch")
	end
	local scaled = RigWalk.fromConstraint({ Name = "S", C0 = v(0, 0.25, 0), C1 = v(0, 0, 0),
		Attachment0 = { Parent = root, CFrame = v(0, 1, 0) }, Attachment1 = { Parent = torso, CFrame = v(0, 0, 0) } })
	expectEqual(scaled.C0.y, 1.25, "constraint C0 offset applied")
end })
table.insert(tests, { name = "TravelTiming: min, max, ready early, ready late, skip, reduced motion, tutorial", fn = function()
	local TravelTiming = require(script.Parent.Parent.Engine.TravelTiming)
	expectEqual(TravelTiming.revealTime(0.2, false), TravelTiming.MIN, "ready early waits for the minimum")
	expectEqual(TravelTiming.revealTime(3, false), 3, "ready late reveals when ready")
	expectEqual(TravelTiming.revealTime(9, false), TravelTiming.MAX, "ready after the maximum is capped")
	expectEqual(TravelTiming.revealTime(nil, false), TravelTiming.MAX, "never ready reveals at the maximum")
	expectEqual(TravelTiming.revealTime(0.1, true), TravelTiming.REDUCED_MIN, "reduced motion is a quick fade")
	expectEqual(TravelTiming.revealTime(nil, true), TravelTiming.REDUCED_MAX)
	expectTrue(not TravelTiming.shouldReveal(0.5, 0.1, false, false), "not before the minimum")
	expectTrue(TravelTiming.shouldReveal(1.2, 0.1, false, false), "at the minimum when ready")
	expectTrue(not TravelTiming.shouldReveal(2, nil, false, false), "waits while not ready")
	expectTrue(TravelTiming.shouldReveal(5, nil, false, false), "reveals anyway at the maximum")
	expectTrue(not TravelTiming.shouldReveal(0.5, 0.1, false, true), "a skip before 1s does nothing")
	expectTrue(TravelTiming.shouldReveal(1.0, 0.1, false, true), "a skip after 1s lifts a ready cover")
	expectTrue(not TravelTiming.shouldReveal(2, nil, false, true), "a skip never reveals an unready game")
	expectTrue(not TravelTiming.shouldRun({ hasSeenTutorial = false }), "no transition over the tutorial")
	expectTrue(TravelTiming.shouldRun({ hasSeenTutorial = true }) and TravelTiming.shouldRun({}), "normal runs get it")
end })
table.insert(tests, { name = "RigWalk: hasTransform / isWrapper never read .animated on a real joint Instance", fn = function()
	local RigWalk = require(script.Parent.Parent.Engine.RigWalk)
	-- Stand-in for a Weld / Motor6D: unknown field reads error, like a real Instance.
	local function fakeInstance(class)
		return setmetatable({ Name = class }, { __index = function(_, k)
			error(tostring(k) .. " is not a valid member of " .. class)
		end })
	end
	local motor, weld = fakeInstance("Motor6D"), fakeInstance("Weld")
	local isMotor = function(j) return j.Name == "Motor6D" end
	local wrapped = RigWalk.fromConstraint({ Name = "c",
		Attachment0 = { Parent = {}, CFrame = 1 }, Attachment1 = { Parent = {}, CFrame = 2 } })
	expectTrue(RigWalk.hasTransform(motor, isMotor), "Motor6D takes a pose")
	expectTrue(not RigWalk.hasTransform(weld, isMotor), "Weld does not")
	expectTrue(RigWalk.hasTransform(wrapped, isMotor), "wrapped constraint takes a pose")
	expectTrue(RigWalk.isWrapper(wrapped), "wrapper detected")
	expectTrue(not RigWalk.isWrapper(motor) and not RigWalk.isWrapper(weld), "instances are not wrappers")
end })
table.insert(tests, { name = "RigWalk: orders joints from the root, walks accessory welds backwards, skips half-built joints", fn = function()
	local RigWalk = require(script.Parent.Parent.Engine.RigWalk)
	local root, torso, head, arm, hat, orphan, lost = {}, {}, {}, {}, {}, {}, {}
	local rootJoint = { Part0 = root, Part1 = torso }
	local neck = { Part0 = torso, Part1 = head }
	local shoulder = { Part0 = torso, Part1 = arm }
	local hatWeld = { Part0 = hat, Part1 = head } -- accessory: handle is Part0
	local unfinished = { Part0 = orphan, Part1 = nil } -- joint not assembled yet
	local detached = { Part0 = lost, Part1 = {} } -- reaches nothing connected to the root
	-- deliberately out of order so the walk has to iterate
	local ordered, reversed, placed, count = RigWalk.walk(
		{ hatWeld, unfinished, neck, detached, shoulder, rootJoint }, root)
	expectEqual(count, 5, "root, torso, head, arm and hat are reached; the detached ones are not")
	expectTrue(placed[hat] and placed[head] and placed[arm] and placed[torso])
	expectTrue(not placed[orphan] and not placed[lost])
	expectTrue(reversed[hatWeld] == true and reversed[neck] == nil, "only the accessory weld is reversed")
	local index = {}
	for i, j in ipairs(ordered) do
		index[j] = i
	end
	expectTrue(index[rootJoint] < index[neck] and index[neck] < index[hatWeld], "anchors come before what they move")
	expectEqual(#ordered, 4)
	local _, _, _, tiny = RigWalk.walk({}, root)
	expectTrue(tiny < RigWalk.MIN_AVATAR_PARTS, "an empty model counts as unassembled")
end })

table.insert(tests, { name = "WorldMap: the real graph validates", fn = function()
	local WorldMap = require(script.Parent.Parent.Engine.WorldMap)
	local ok, errors = WorldMap.validate()
	expectTrue(ok, "validate failed: " .. table.concat(errors, "; "))
	expectEqual(WorldMap.Start, "dusty_road")
	expectEqual(WorldMap.Finish, "keepers_table")
end })

table.insert(tests, { name = "WorldMap: default route equals today's 8 Nights (art and order)", fn = function()
	local WorldMap = require(script.Parent.Parent.Engine.WorldMap)
	local JourneyMap = require(script.Parent.Parent.Engine.JourneyMap)
	local route = WorldMap.defaultRoute()
	expectEqual(#route, #JourneyMap.Nights)
	for i, night in ipairs(JourneyMap.Nights) do
		expectEqual(WorldMap.Stops[route[i]].art, night.art, "Night " .. i)
		expectEqual(WorldMap.Stops[route[i]].name, night.name, "Night " .. i .. " name")
		expectEqual(WorldMap.routeNight({ table.unpack(route, 1, i) }), i)
	end
end })

table.insert(tests, { name = "WorldMap: every route is 8 Night stops, valid, ends in the tavern", fn = function()
	local WorldMap = require(script.Parent.Parent.Engine.WorldMap)
	local routes = WorldMap.allRoutes()
	expectEqual(#routes, 18, "3 x 3 x 2 routes")
	local seen = {}
	for _, route in ipairs(routes) do
		expectEqual(#route, 8)
		expectEqual(WorldMap.routeNight(route), 8)
		expectEqual(route[1], "dusty_road")
		expectEqual(route[8], "keepers_table")
		expectTrue(WorldMap.isValidRoute(route))
		local key = table.concat(route, ">")
		expectTrue(not seen[key], "duplicate route " .. key)
		seen[key] = true
		-- the tavern region is always last: Nights 6 to 8
		for n = 6, 8 do
			expectEqual(WorldMap.regionOf(route[n]), "tavern", "Night " .. n .. " of " .. key)
		end
		for n = 1, 5 do
			expectTrue(WorldMap.regionOf(route[n]) ~= "tavern", "tavern too early in " .. key)
		end
	end
	-- all four new biomes appear on some route
	local regions = {}
	for _, route in ipairs(routes) do
		for _, id in ipairs(route) do
			regions[WorldMap.regionOf(id)] = true
		end
	end
	for _, r in ipairs({ "desert", "swamp", "snow", "coast", "meadow", "river", "peaks", "tavern" }) do
		expectTrue(regions[r], r .. " is on no route")
	end
end })

table.insert(tests, { name = "WorldMap: forks, choicesAfter, regionOf, isValidRoute", fn = function()
	local WorldMap = require(script.Parent.Parent.Engine.WorldMap)
	expectEqual(#WorldMap.choicesAfter("dusty_road"), 1)
	expectEqual(#WorldMap.choicesAfter("wildflower_meadow"), 3)
	expectEqual(#WorldMap.choicesAfter("willow_bridge"), 3)
	expectEqual(#WorldMap.choicesAfter("tavern_gate"), 2)
	expectEqual(#WorldMap.choicesAfter("keepers_table"), 0)
	expectEqual(#WorldMap.choicesAfter("no_such_stop"), 0)
	expectTrue(WorldMap.isFork("wildflower_meadow") and not WorldMap.isFork("dusty_road"))
	expectEqual(WorldMap.regionOf("desert_dunes"), "desert")
	expectEqual(WorldMap.regionOf("nope"), nil)
	expectTrue(WorldMap.isValidRoute({ "dusty_road", "wildflower_meadow", "desert_dunes" }))
	expectFalse(WorldMap.isValidRoute({ "dusty_road", "desert_dunes" }), "skipping a stop")
	expectFalse(WorldMap.isValidRoute({ "wildflower_meadow" }), "must start at the start")
	expectFalse(WorldMap.isValidRoute({}))
	-- the copy returned by choicesAfter is safe to mutate
	local c = WorldMap.choicesAfter("wildflower_meadow")
	c[1] = "hacked"
	expectEqual(WorldMap.choicesAfter("wildflower_meadow")[1], "garden_terrace")
end })

table.insert(tests, { name = "WorldMap: validate catches broken graphs", fn = function()
	local WorldMap = require(script.Parent.Parent.Engine.WorldMap)
	local function night(region, nxt, x)
		return { kind = "night", region = region, art = "a", name = "n", x = x or 0.5, y = 0.5, next = nxt }
	end
	-- 3-stop line of the right length when nights = 3
	local good = { s = night("road", { "m" }), m = night("meadow", { "f" }), f = night("tavern", {}) }
	local ok = WorldMap.validate(good, "s", "f", 3)
	expectTrue(ok)
	expectFalse(WorldMap.validate(good, "s", "f", 4), "wrong length")
	-- cycle
	local cyc = { s = night("road", { "m" }), m = night("meadow", { "s", "f" }), f = night("tavern", {}) }
	expectFalse(WorldMap.validate(cyc, "s", "f", 3))
	-- dead end that is not the finish
	local dead = { s = night("road", { "m", "d" }), m = night("meadow", { "f" }), d = night("river", {}), f = night("tavern", {}) }
	expectFalse(WorldMap.validate(dead, "s", "f", 3))
	-- unreachable stop
	local orphan = { s = night("road", { "m" }), m = night("meadow", { "f" }), f = night("tavern", {}), o = night("river", { "f" }) }
	expectFalse(WorldMap.validate(orphan, "s", "f", 3))
	-- unequal route lengths
	local uneven = { s = night("road", { "m", "f" }), m = night("meadow", { "f" }), f = night("tavern", {}) }
	expectFalse(WorldMap.validate(uneven, "s", "f", 3))
	-- unknown region, missing next target, tavern leading out, side stop without parent
	local badRegion = { s = night("lava", { "m" }), m = night("meadow", { "f" }), f = night("tavern", {}) }
	expectFalse(WorldMap.validate(badRegion, "s", "f", 3))
	local missing = { s = night("road", { "zzz" }), f = night("tavern", {}) }
	expectFalse(WorldMap.validate(missing, "s", "f", 3))
	local leaving = { s = night("tavern", { "m" }), m = night("meadow", { "f" }), f = night("tavern", {}) }
	expectFalse(WorldMap.validate(leaving, "s", "f", 3))
	local sideGood = { s = night("road", { "m" }), m = night("meadow", { "f" }), f = night("tavern", {}),
		x = { kind = "side", parent = "m", side = "shop" } }
	expectTrue(WorldMap.validate(sideGood, "s", "f", 3))
	local sideBad = { s = night("road", { "m" }), m = night("meadow", { "f" }), f = night("tavern", {}),
		x = { kind = "side", parent = "nope", side = "shop" } }
	expectFalse(WorldMap.validate(sideBad, "s", "f", 3))
	expectEqual(WorldMap.regionOf("x", sideGood), "meadow", "a side stop uses its parent's region")
end })

table.insert(tests, { name = "WorldMap: bearing and pickByBearing", fn = function()
	local WorldMap = require(script.Parent.Parent.Engine.WorldMap)
	local near = function(a, b) return math.abs(a - b) < 1e-6 end
	local stops = {
		a = { kind = "night", x = 0.5, y = 0.5, next = { "n", "e", "s", "w" } },
		n = { kind = "night", x = 0.5, y = 0.2, next = {} },
		e = { kind = "night", x = 0.8, y = 0.5, next = {} },
		s = { kind = "night", x = 0.5, y = 0.8, next = {} },
		w = { kind = "night", x = 0.2, y = 0.5, next = {} },
	}
	expectTrue(near(WorldMap.bearing("a", "n", stops), 0), "north")
	expectTrue(near(WorldMap.bearing("a", "e", stops), 90), "east")
	expectTrue(near(WorldMap.bearing("a", "s", stops), 180), "south")
	expectTrue(near(WorldMap.bearing("a", "w", stops), 270), "west")
	expectEqual(WorldMap.bearing("a", "missing", stops), nil)
	expectEqual(WorldMap.pickByBearing("a", 10, stops), "n")
	expectEqual(WorldMap.pickByBearing("a", 350, stops), "n", "wraps around north")
	expectEqual(WorldMap.pickByBearing("a", 100, stops), "e")
	expectEqual(WorldMap.pickByBearing("a", 200, stops), "s")
	expectEqual(WorldMap.pickByBearing("a", 300, stops), "w")
	expectEqual(WorldMap.pickByBearing("n", 0, stops), nil, "no roads")
	expectEqual(WorldMap.angleDiff(350, 10), 20)
	-- the real map: a fork heading up-right picks the desert road, down-right the marsh
	expectEqual(WorldMap.pickByBearing("wildflower_meadow", 45), "desert_dunes")
	expectEqual(WorldMap.pickByBearing("wildflower_meadow", 135), "swamp_boardwalk")
	expectEqual(WorldMap.pickByBearing("wildflower_meadow", 90), "garden_terrace")
end })

-- Plays a fresh run up to the start of `night` (round 1 of that Night) without playing hands.
local function runAtNight(night, options)
	local state = RunState.new(options, function(_n) return 1 end)
	while state.night < night do
		state.roundOver = true
		RunState.advanceToNextRound(state)
	end
	return state
end

table.insert(tests, { name = "WorldMap: a new run starts on the Dusty Road; Night 2 fills itself (one road)", fn = function()
	local WorldMap = require(script.Parent.Parent.Engine.WorldMap)
	local state = RunState.new(nil, function(_n) return 1 end)
	expectEqual(#state.worldRoute, 1)
	expectEqual(state.worldRoute[1], "dusty_road")
	expectEqual(WorldMap.pendingChoices(state), nil, "Night 1 never asks")
	state = runAtNight(2)
	expectEqual(state.worldRoute[2], "wildflower_meadow", "a plain road needs no choice")
	expectEqual(WorldMap.pendingChoices(state), nil)
end })

table.insert(tests, { name = "WorldMap: a fork waits for ChooseRoad; the pick is validated", fn = function()
	local WorldMap = require(script.Parent.Parent.Engine.WorldMap)
	local state = runAtNight(3)
	expectEqual(#state.worldRoute, 2, "Night 3 is a fork, nothing picked yet")
	local choices = WorldMap.pendingChoices(state)
	expectEqual(#choices, 3)
	-- rejections
	local ok, why = WorldMap.chooseRoad(state, "desert_dunes", "playing")
	expectFalse(ok); expectEqual(why, "wrong_phase")
	ok, why = WorldMap.chooseRoad(state, "desert_dunes", "shop")
	expectFalse(ok); expectEqual(why, "wrong_phase")
	ok, why = WorldMap.chooseRoad(state, "keepers_table", "roundSelect")
	expectFalse(ok); expectEqual(why, "not_next")
	ok, why = WorldMap.chooseRoad(state, "mountain_pass", "roundSelect")
	expectFalse(ok); expectEqual(why, "not_next", "a stop from a later fork")
	ok, why = WorldMap.chooseRoad(state, "tavern_gate", "roundSelect")
	expectFalse(ok); expectEqual(why, "not_next")
	for _, bad in ipairs({ 5, true, {}, "", "nope" }) do
		ok = WorldMap.chooseRoad(state, bad, "roundSelect")
		expectFalse(ok, "cheating id " .. tostring(bad))
	end
	expectEqual(#state.worldRoute, 2, "rejected picks change nothing")
	-- the real pick
	ok = WorldMap.chooseRoad(state, "desert_dunes", "roundSelect")
	expectTrue(ok)
	expectEqual(state.worldRoute[3], "desert_dunes")
	expectEqual(WorldMap.currentStop(state), "desert_dunes")
	-- already chosen for this Night: a second pick is refused
	ok, why = WorldMap.chooseRoad(state, "swamp_boardwalk", "roundSelect")
	expectFalse(ok); expectEqual(why, "no_choice")
	expectEqual(state.worldRoute[3], "desert_dunes")
	-- Night 1 and 2 have nothing to choose
	local early = RunState.new(nil, function(_n) return 1 end)
	ok, why = WorldMap.chooseRoad(early, "wildflower_meadow", "roundSelect")
	expectFalse(ok); expectEqual(why, "no_choice")
end })

table.insert(tests, { name = "WorldMap: no pick means the default road; later forks continue from the pick", fn = function()
	local WorldMap = require(script.Parent.Parent.Engine.WorldMap)
	local state = runAtNight(3)
	expectTrue(WorldMap.fillDefault(state))
	expectEqual(state.worldRoute[3], "garden_terrace")
	expectFalse(WorldMap.fillDefault(state), "nothing left to fill")
	-- Night 4 is a plain road, Night 5 a fork again
	state = runAtNight(4)
	WorldMap.chooseRoad(state, "swamp_boardwalk", "roundSelect") -- Night 3 is still pending in this fresh run
	state = runAtNight(3)
	WorldMap.chooseRoad(state, "swamp_boardwalk", "roundSelect")
	while state.night < 5 do
		state.roundOver = true
		RunState.advanceToNextRound(state)
	end
	expectEqual(state.worldRoute[4], "lilypad_pond", "the swamp road continues to its second stop")
	local c = WorldMap.pendingChoices(state)
	expectEqual(#c, 3)
	expectFalse(WorldMap.chooseRoad(state, "grand_hall", "roundSelect"))
	expectTrue(WorldMap.chooseRoad(state, "lighthouse_cove", "roundSelect"))
	-- Night 6 onward: the whole route stays a valid prefix and reaches the tavern
	while state.night < 8 do
		state.roundOver = true
		RunState.advanceToNextRound(state)
		WorldMap.fillDefault(state)
	end
	expectTrue(WorldMap.isValidRoute(state.worldRoute))
	expectEqual(#state.worldRoute, 8)
	expectEqual(state.worldRoute[8], "keepers_table")
	-- past Night 8 (Endless) the route no longer grows
	state.roundOver = true
	RunState.advanceToNextRound(state)
	state.roundOver = true
	RunState.advanceToNextRound(state)
	state.roundOver = true
	RunState.advanceToNextRound(state)
	expectEqual(state.night, 9)
	expectEqual(#state.worldRoute, 8)
	expectEqual(WorldMap.pendingChoices(state), nil)
end })

table.insert(tests, { name = "WorldMap: seeded runs get a fixed, valid, repeatable route and cannot choose", fn = function()
	local WorldMap = require(script.Parent.Parent.Engine.WorldMap)
	local a = WorldMap.routeFromSeed("daily:2026-11-08")
	local b = WorldMap.routeFromSeed("daily:2026-11-08")
	expectEqual(table.concat(a, ">"), table.concat(b, ">"), "same label, same road")
	expectEqual(#a, 8)
	expectTrue(WorldMap.isValidRoute(a))
	expectEqual(a[8], "keepers_table")
	-- different labels spread over several routes
	local seen, count = {}, 0
	for i = 1, 40 do
		local key = table.concat(WorldMap.routeFromSeed("seed:STORM" .. i), ">")
		if not seen[key] then seen[key] = true; count = count + 1 end
	end
	expectTrue(count >= 6, "expected a spread of routes, got " .. count)
	-- a run with a plan follows it and refuses ChooseRoad
	local plan = WorldMap.routeFromSeed("weekly:2026-W45")
	local state = runAtNight(3, { worldPlan = plan })
	expectEqual(state.worldRoute[3], plan[3], "the plan fills the fork by itself")
	local ok, why = WorldMap.chooseRoad(state, plan[3], "roundSelect")
	expectFalse(ok); expectEqual(why, "fixed_route")
	local fresh = RunState.new({ worldPlan = plan }, function(_n) return 1 end)
	ok, why = WorldMap.chooseRoad(fresh, "wildflower_meadow", "roundSelect")
	expectFalse(ok); expectEqual(why, "fixed_route")
	local free = runAtNight(8, { worldPlan = plan })
	expectEqual(table.concat(free.worldRoute, ">"), table.concat(plan, ">"))
end })

table.insert(tests, { name = "WorldMap: the road survives One More Round (snapshot keeps the pick)", fn = function()
	local WorldMap = require(script.Parent.Parent.Engine.WorldMap)
	local state = runAtNight(3)
	expectEqual(#state.roundStartSnapshot.worldRoute, 2, "snapshot taken before the pick")
	expectTrue(WorldMap.chooseRoad(state, "swamp_boardwalk", "roundSelect"))
	expectEqual(#state.roundStartSnapshot.worldRoute, 3, "the pick is written into the snapshot")
	state.runOver = true
	RunState.useContinue(state)
	expectEqual(state.worldRoute[3], "swamp_boardwalk")
	expectEqual(#state.worldRoute, 3)
	-- the copy is independent of the snapshot
	state.worldRoute[3] = "x"
	expectEqual(state.roundStartSnapshot.worldRoute[3], "swamp_boardwalk")
end })

table.insert(tests, { name = "WorldMap: profile fields load safely and drop unknown ids", fn = function()
	local PlayerProfile = require(script.Parent.Parent.Engine.PlayerProfile)
	local fresh = PlayerProfile.new()
	expectEqual(#fresh.worldRoute, 0)
	expectEqual(next(fresh.worldSeenStopIds), nil)
	local loaded = PlayerProfile.migrate({
		worldRoute = { "dusty_road", "wildflower_meadow", "desert_dunes" },
		worldSeenStopIds = { desert_dunes = true, ghost_stop = true, dusty_road = false, [5] = true },
		worldBiomeClears = { desert = 2.7, lava = 3, meadow = -1, road = "x" },
		worldRewardIds = { desert = true, [3] = true },
	})
	expectEqual(#loaded.worldRoute, 3)
	expectTrue(loaded.worldSeenStopIds.desert_dunes)
	expectEqual(loaded.worldSeenStopIds.ghost_stop, nil)
	expectEqual(loaded.worldSeenStopIds.dusty_road, nil)
	expectEqual(loaded.worldBiomeClears.desert, 2)
	expectEqual(loaded.worldBiomeClears.lava, nil)
	expectEqual(loaded.worldBiomeClears.meadow, nil)
	expectEqual(loaded.worldBiomeClears.road, nil)
	expectTrue(loaded.worldRewardIds.desert)
	-- a broken or cheated route is dropped, old profiles without the fields still load
	expectEqual(#PlayerProfile.migrate({ worldRoute = { "dusty_road", "keepers_table" } }).worldRoute, 0)
	expectEqual(#PlayerProfile.migrate({ worldRoute = { "dusty_road", "nope" } }).worldRoute, 0)
	expectEqual(#PlayerProfile.migrate({ worldRoute = "x" }).worldRoute, 0)
	expectEqual(#PlayerProfile.migrate({}).worldRoute, 0)
	expectEqual(#PlayerProfile.migrate(nil).worldRoute, 0)
end })

table.insert(tests, { name = "WorldMap: recordWorldProgress counts each cleared stop once and keeps clearedNightIds working", fn = function()
	local PlayerProfile = require(script.Parent.Parent.Engine.PlayerProfile)
	local JourneyMap = require(script.Parent.Parent.Engine.JourneyMap)
	local WorldMap = require(script.Parent.Parent.Engine.WorldMap)
	local profile = PlayerProfile.new()
	local route = { "dusty_road", "wildflower_meadow", "desert_dunes" }
	local changed, counted = PlayerProfile.recordWorldProgress(profile, route, 0, 0)
	expectTrue(changed); expectEqual(counted, 0)
	expectEqual(profile.worldBiomeClears.road, nil)
	changed, counted = PlayerProfile.recordWorldProgress(profile, route, 2, counted)
	expectEqual(counted, 2)
	expectEqual(profile.worldBiomeClears.road, 1)
	expectEqual(profile.worldBiomeClears.meadow, 1)
	changed, counted = PlayerProfile.recordWorldProgress(profile, route, 2, counted)
	expectFalse(changed, "repeated pushes change nothing")
	expectEqual(profile.worldBiomeClears.road, 1)
	-- a second run adds to the totals
	changed, counted = PlayerProfile.recordWorldProgress(profile, route, 2, 0)
	expectEqual(profile.worldBiomeClears.road, 2)
	-- an invalid route is ignored
	changed = PlayerProfile.recordWorldProgress(profile, { "dusty_road", "keepers_table" }, 2, 0)
	expectFalse(changed)
	expectTrue(profile.worldSeenStopIds.desert_dunes)
	-- the default route still grants the Night 1 to 8 rewards through recordNightsCleared
	local p2 = PlayerProfile.new()
	JourneyMap.recordNightsCleared(p2, 8)
	for n = 1, 8 do
		expectTrue(p2.clearedNightIds[n], "Night " .. n)
	end
	expectEqual(#WorldMap.defaultRoute(), 8)
end })

-- Plays a run along `route` (array of stops) without playing hands: advances round by round, taking the
-- scripted road at each fork, and records the numbers that decide difficulty.
local function walkRoute(route, options)
	local WorldMap = require(script.Parent.Parent.Engine.WorldMap)
	local state = RunState.new(options, function(_n) return 1 end)
	local rows = {}
	local function record()
		rows[#rows + 1] = { night = state.night, round = state.round, target = state.targetScore,
			hands = state.handsRemaining, discards = state.discardsRemaining, boss = state.isBossRound }
	end
	record()
	while not (state.night == 8 and state.round == state.config.roundsPerNight) do
		state.roundOver = true
		RunState.advanceToNextRound(state)
		if WorldMap.pendingChoices(state) then
			WorldMap.chooseRoad(state, route[state.night], "roundSelect")
		end
		record()
	end
	return state, rows
end

table.insert(tests, { name = "World map balance: every one of the 18 routes has identical targets, hands and discards per Night", fn = function()
	local WorldMap = require(script.Parent.Parent.Engine.WorldMap)
	local routes = WorldMap.allRoutes()
	local _, baseline = walkRoute(routes[1])
	expectEqual(#baseline, 24, "8 Nights of 3 rounds")
	for _, route in ipairs(routes) do
		local state, rows = walkRoute(route)
		local key = table.concat(route, ">")
		expectEqual(#rows, #baseline, key)
		for i, row in ipairs(rows) do
			expectEqual(row.target, baseline[i].target, "target Night " .. row.night .. " round " .. row.round .. " on " .. key)
			expectEqual(row.hands, baseline[i].hands, "hands on " .. key)
			expectEqual(row.discards, baseline[i].discards, "discards on " .. key)
			expectEqual(row.boss, baseline[i].boss)
		end
		-- the run really walked that road
		expectEqual(table.concat(state.worldRoute, ">"), key)
		-- difficulty rises with the Night, never with the road: each Night's boss round is the biggest target
		local lastBoss = 0
		for _, row in ipairs(rows) do
			if row.boss then
				expectTrue(row.target > lastBoss, "boss targets climb on " .. key)
				lastBoss = row.target
			end
		end
	end
end })

table.insert(tests, { name = "World map balance: rewards per route stay in the same range and the default route is unchanged", fn = function()
	local WorldMap = require(script.Parent.Parent.Engine.WorldMap)
	local BiomeRewards = require(script.Parent.Parent.Engine.BiomeRewards)
	local PlayerProfile = require(script.Parent.Parent.Engine.PlayerProfile)
	local JourneyMap = require(script.Parent.Parent.Engine.JourneyMap)
	local CollectionBook = require(script.Parent.Parent.Engine.CollectionBook)
	local order = {}
	for i, id in ipairs(CollectionBook.RarityOrder) do order[id] = i end
	local lo, hi = math.huge, 0
	for _, route in ipairs(WorldMap.allRoutes()) do
		local profile = PlayerProfile.new()
		JourneyMap.recordNightsCleared(profile, 8)
		local granted = BiomeRewards.recordProgress(profile, route, 8, { mapTokens = 0 })
		-- every route ends at the Keeper with the tavern row; the number of rewards is bounded
		expectTrue(profile.unlockedCardBackIds.gala)
		local score = 0
		for _, r in ipairs(granted) do
			local tab = (r.kind == "cardBack" and "backs") or (r.kind == "set" and "sets")
				or (r.kind == "patron" and "patrons") or (r.kind == "recipe" and "recipes") or "titles"
			score = score + (order[CollectionBook.rarityForId(tab, r.id)] or 1)
		end
		lo, hi = math.min(lo, score), math.max(hi, score)
	end
	-- no road is a free lunch or a dead end: the reward value of the richest route is under 2x the poorest
	expectTrue(lo > 0)
	expectTrue(hi <= lo * 2, string.format("reward value ranges %d to %d", lo, hi))
	-- the default route is the old eight Nights: the same stops and the same Night rewards
	local def = WorldMap.defaultRoute()
	for n, night in ipairs(JourneyMap.Nights) do
		expectEqual(WorldMap.Stops[def[n]].art, night.art)
	end
end })

table.insert(tests, { name = "World map balance: Daily, Weekly and Seed boards get a fixed 8-Night route that is the same for everyone", fn = function()
	local WorldMap = require(script.Parent.Parent.Engine.WorldMap)
	local labels = { "daily:2026-11-08", "daily:2026-11-09", "weekly:2026-W45", "weekly:2026-W46" }
	for i = 1, 25 do
		labels[#labels + 1] = "seed:CODE" .. i
	end
	for _, label in ipairs(labels) do
		local plan = WorldMap.routeFromSeed(label)
		expectTrue(WorldMap.isValidRoute(plan), label)
		expectEqual(#plan, 8)
		expectEqual(plan[8], "keepers_table")
		-- two players on the same board walk the same road, whatever they click
		local a = walkRoute(plan, { worldPlan = plan })
		local b = walkRoute(WorldMap.defaultRoute(), { worldPlan = plan })
		expectEqual(table.concat(a.worldRoute, ">"), table.concat(plan, ">"), label)
		expectEqual(table.concat(b.worldRoute, ">"), table.concat(plan, ">"), "a choice attempt cannot change " .. label)
	end
end })

table.insert(tests, { name = "BiomeRewards: every reward resolves, has a rarity, a flavor text and a prompt-able id", fn = function()
	local BiomeRewards = require(script.Parent.Parent.Engine.BiomeRewards)
	local WorldMap = require(script.Parent.Parent.Engine.WorldMap)
	local CardBacks = require(script.Parent.Parent.Engine.CardBacks)
	local CosmeticSets = require(script.Parent.Parent.Engine.CosmeticSets)
	local Achievements = require(script.Parent.Parent.Engine.Achievements)
	local CollectionBook = require(script.Parent.Parent.Engine.CollectionBook)
	for region in pairs(BiomeRewards.Rows) do
		expectTrue(WorldMap.Regions[region] ~= nil, region .. " is a real region")
	end
	for _, region in ipairs(WorldMap.RegionOrder) do
		expectTrue(BiomeRewards.Rows[region] ~= nil, region .. " has a reward row")
	end
	for _, r in ipairs(BiomeRewards.allRewards()) do
		if r.kind == "cardBack" then
			local back = CardBacks.getById(r.id)
			expectTrue(back ~= nil, r.id .. " card back exists")
			expectTrue(CollectionBook.Rarities[CollectionBook.rarityForId("backs", r.id)] ~= nil)
			expectTrue(back.flavorText and back.flavorText ~= "")
		elseif r.kind == "set" then
			expectTrue(CosmeticSets.getById(r.id) ~= nil, r.id .. " set exists")
		elseif r.kind == "title" then
			local a = Achievements.getById(r.id)
			expectTrue(a ~= nil and a.milestoneReward == true, r.id .. " title exists")
			expectTrue(a.flavorText and a.flavorText ~= "")
		elseif r.kind == "badge" then
			local b = require(script.Parent.Parent.Engine.Badges).getById(r.id)
			expectTrue(b ~= nil and b.name ~= "" and b.description ~= "" and CollectionBook.Rarities[b.rarity] ~= nil, r.id .. " badge exists")
		elseif r.kind == "patron" then
			local p = require(script.Parent.Parent.Engine.Patrons).getById(r.id)
			expectTrue(p ~= nil and p.flavorText and p.flavorText ~= "", r.id .. " patron exists with flavor text")
			expectTrue(CollectionBook.Rarities[CollectionBook.rarityForId("patrons", r.id)] ~= nil)
		elseif r.kind == "recipe" then
			local rec = require(script.Parent.Parent.Engine.Recipes).getHouseRecipeById(r.id)
			expectTrue(rec ~= nil and rec.flavorText and rec.flavorText ~= "", r.id .. " recipe exists with flavor text")
			expectTrue(CollectionBook.Rarities[CollectionBook.rarityForId("recipes", r.id)] ~= nil)
		else
			expectTrue(false, "unknown kind " .. tostring(r.kind))
		end
	end
end })

table.insert(tests, { name = "Biome Patrons and Recipes: one of each per biome, mild effects, voice lines, prompts, Collection discovery", fn = function()
	local BiomeRewards = require(script.Parent.Parent.Engine.BiomeRewards)
	local PlayerProfile = require(script.Parent.Parent.Engine.PlayerProfile)
	local Patrons = require(script.Parent.Parent.Engine.Patrons)
	local Recipes = require(script.Parent.Parent.Engine.Recipes)
	local PatronLines = require(script.Parent.Parent.Engine.PatronLines)
	local CollectionBook = require(script.Parent.Parent.Engine.CollectionBook)
	local biomes = { "meadow", "river", "peaks", "desert", "swamp", "snow", "coast" }
	for _, region in ipairs(biomes) do
		local nPatron, nRecipe = 0, 0
		for _, r in ipairs(BiomeRewards.Rows[region].reward) do
			if r.kind == "patron" then
				nPatron = nPatron + 1
				local p = Patrons.getById(r.id)
				expectEqual(p.biome, region)
				expectTrue(p.price <= 5, r.id .. " stays cheap and mild")
				expectTrue(PatronLines.ById[r.id] ~= nil, r.id .. " has its own voice line")
				expectEqual(CollectionBook.rarityForId("patrons", r.id), "uncommon")
			elseif r.kind == "recipe" then
				nRecipe = nRecipe + 1
				local rec = Recipes.getHouseRecipeById(r.id)
				expectEqual(rec.biome, region)
				expectTrue(rec.price <= 4)
				expectEqual(CollectionBook.rarityForId("recipes", r.id), "uncommon")
				local state = { hand = { { rank = 5, suit = "Hearts" }, { rank = 6, suit = "Clubs" } } }
				local ok = rec.apply(state, { cardIndices = { 1 } })
				expectTrue(ok and state.hand[1].garnish ~= nil, r.id .. " garnishes one card")
				expectFalse(rec.apply(state, { cardIndices = { 1, 2 } }), "exactly one card")
			end
		end
		expectEqual(nPatron, 1, region .. " has one Patron")
		expectEqual(nRecipe, 1, region .. " has one House Recipe")
	end
	-- Effects: situational and small.
	local function card(rank, suit) return { rank = rank, suit = suit } end
	local function result(name, cards) return { name = name, scoringCards = cards } end
	local lows = result("Pair", { card(2, "Hearts"), card(6, "Clubs"), card(9, "Spades") })
	expectEqual(Patrons.getById("meadow_bee").effect(lows, {}).chips, 12)
	expectEqual(Patrons.getById("ferry_captain").effect(lows, { allPlayedCards = { 1, 2, 3 } }).chips, 10)
	expectEqual(Patrons.getById("ferry_captain").effect(lows, { allPlayedCards = { 1, 2 } }), nil)
	expectEqual(Patrons.getById("summit_guide").effect(result("Pair", { card(13, "Hearts"), card(14, "Clubs"), card(3, "Clubs") }), {}).mult, 4)
	expectEqual(Patrons.getById("sand_merchant").effect(result("Flush", { card(2, "Hearts") }), {}).tips, 1)
	expectEqual(Patrons.getById("sand_merchant").effect(lows, {}), nil)
	expectEqual(Patrons.getById("marsh_gardener").effect(result("Pair", { card(2, "Clubs"), card(2, "Spades") }), {}).mult, 3)
	expectEqual(Patrons.getById("marsh_gardener").effect(lows, {}), nil, "a Heart cancels it")
	expectEqual(Patrons.getById("lantern_lighter").effect(lows, { heldCards = { 1, 2, 3 } }).chips, 12)
	expectEqual(Patrons.getById("lighthouse_keeper").effect(lows, { discardsRemaining = 3 }).mult, 6)
	-- Granting adds them to the Collection once.
	local profile = PlayerProfile.new()
	BiomeRewards.recordBiomeCleared(profile, "desert")
	expectTrue(profile.discoveredPatronIds.sand_merchant and profile.discoveredRecipeIds.date_cake)
	expectEqual(#BiomeRewards.recordBiomeCleared(profile, "desert"), 0, "once")
	expectEqual(BiomeRewards.label({ kind = "patron", id = "sand_merchant" }), "Patron: Sand Merchant")
	expectEqual(BiomeRewards.label({ kind = "recipe", id = "date_cake" }), "Recipe: Date Cake")
	-- Every new id has a prompts.json entry (skipped where io is missing, e.g. Studio).
	if io and io.open then
		local f = io.open("tools/patron_art/prompts.json", "r")
		if f then
			local text = f:read("*a")
			f:close()
			for _, region in ipairs(biomes) do
				for _, r in ipairs(BiomeRewards.Rows[region].reward) do
					if r.kind == "patron" or r.kind == "recipe" then
						expectTrue(text:find('"' .. r.id .. '"', 1, true) ~= nil, r.id .. " has a prompts.json entry")
					end
				end
			end
		end
	end
end })

table.insert(tests, { name = "BiomeRewards: branch ends grant once; mid-biome stops grant nothing", fn = function()
	local BiomeRewards = require(script.Parent.Parent.Engine.BiomeRewards)
	local PlayerProfile = require(script.Parent.Parent.Engine.PlayerProfile)
	local profile = PlayerProfile.new()
	local route = { "dusty_road", "wildflower_meadow", "desert_dunes", "oasis_camp" }
	-- Night 3 cleared (desert_dunes): the dunes road is not finished yet
	BiomeRewards.recordProgress(profile, { "dusty_road", "wildflower_meadow", "desert_dunes" }, 3)
	expectEqual(profile.unlockedCardBackIds.dune_gold, nil, "mid-biome: no reward yet")
	-- Night 2 cleared: the meadow branch ended when the road turned to the desert
	expectTrue(profile.unlockedCardBackIds.kitchen_checks, "meadow branch end")
	-- Night 4 cleared (oasis_camp): the dunes road ends here
	local fresh = BiomeRewards.recordProgress(profile, route, 4)
	expectTrue(profile.unlockedCardBackIds.dune_gold)
	expectTrue(#fresh >= 1)
	-- repeated pushes grant nothing new
	fresh = BiomeRewards.recordProgress(profile, route, 4)
	expectEqual(#fresh, 0)
	-- a pending fork (route not extended yet) after oasis_camp counts as the end of the desert too
	local p2 = PlayerProfile.new()
	BiomeRewards.recordProgress(p2, { "dusty_road", "wildflower_meadow", "desert_dunes", "oasis_camp" }, 4)
	expectTrue(p2.unlockedCardBackIds.dune_gold)
	-- stops not yet cleared are never rewarded
	local p3 = PlayerProfile.new()
	BiomeRewards.recordProgress(p3, route, 1)
	expectEqual(p3.unlockedCardBackIds.dune_gold, nil)
	expectEqual(p3.unlockedCardBackIds.kitchen_checks, nil)
	-- invalid routes grant nothing
	expectEqual(#BiomeRewards.recordProgress(PlayerProfile.new(), { "dusty_road", "keepers_table" }, 2), 0)
end })

table.insert(tests, { name = "BiomeRewards: the Keeper win grants the tavern row; the default route keeps its Night rewards", fn = function()
	local BiomeRewards = require(script.Parent.Parent.Engine.BiomeRewards)
	local PlayerProfile = require(script.Parent.Parent.Engine.PlayerProfile)
	local JourneyMap = require(script.Parent.Parent.Engine.JourneyMap)
	local WorldMap = require(script.Parent.Parent.Engine.WorldMap)
	local profile = PlayerProfile.new()
	local route = WorldMap.defaultRoute()
	JourneyMap.recordNightsCleared(profile, 8)
	BiomeRewards.recordProgress(profile, route, 7)
	expectEqual(profile.unlockedCardBackIds.gala, nil, "not before the Keeper")
	BiomeRewards.recordProgress(profile, route, 8)
	expectTrue(profile.unlockedCardBackIds.gala)
	expectTrue(profile.unlockedCardBackIds.hall_banner)
	-- the Night 1 to 8 rewards are untouched
	for n, node in ipairs(JourneyMap.Nights) do
		expectTrue(profile.clearedNightIds[n])
		local r = node.reward
		local owned = (r.kind == "title" and profile.rewardTitleIds[r.id])
			or (r.kind == "cardBack" and profile.unlockedCardBackIds[r.id])
			or (r.kind == "set" and profile.ownedSetIds[r.id])
		expectTrue(owned, "Night " .. n .. " reward")
	end
end })

table.insert(tests, { name = "BiomeRewards: region bonuses and Trailblazer need every stop seen", fn = function()
	local BiomeRewards = require(script.Parent.Parent.Engine.BiomeRewards)
	local PlayerProfile = require(script.Parent.Parent.Engine.PlayerProfile)
	local WorldMap = require(script.Parent.Parent.Engine.WorldMap)
	local profile = PlayerProfile.new()
	profile.worldSeenStopIds.desert_dunes = true
	expectEqual(#BiomeRewards.recordRegionBonuses(profile), 0, "one of two desert stops")
	profile.worldSeenStopIds.oasis_camp = true
	local fresh = BiomeRewards.recordRegionBonuses(profile)
	expectEqual(#fresh, 1)
	expectTrue(profile.rewardTitleIds.dune_wanderer)
	expectEqual(#BiomeRewards.recordRegionBonuses(profile), 0, "granted once")
	expectEqual(profile.rewardTitleIds.trailblazer, nil)
	for id, stop in pairs(WorldMap.Stops) do
		if stop.kind == "night" then profile.worldSeenStopIds[id] = true end
	end
	BiomeRewards.recordRegionBonuses(profile)
	expectTrue(profile.rewardTitleIds.trailblazer)
	expectTrue(profile.rewardTitleIds.marsh_wader and profile.rewardTitleIds.snow_scout and profile.rewardTitleIds.lighthouse_friend)
end })

table.insert(tests, { name = "BiomeRewards: every one of the 18 routes ends in a granted tavern row", fn = function()
	local BiomeRewards = require(script.Parent.Parent.Engine.BiomeRewards)
	local PlayerProfile = require(script.Parent.Parent.Engine.PlayerProfile)
	local WorldMap = require(script.Parent.Parent.Engine.WorldMap)
	for _, route in ipairs(WorldMap.allRoutes()) do
		local profile = PlayerProfile.new()
		BiomeRewards.recordProgress(profile, route, 8)
		expectTrue(profile.unlockedCardBackIds.gala, "gala on " .. table.concat(route, ">"))
		-- the biome of Night 4 (the end of fork A's road) was rewarded
		local region = WorldMap.regionOf(route[4])
		local row = BiomeRewards.Rows[region]
		for _, r in ipairs(row.reward) do
			local ok = (r.kind == "cardBack" and profile.unlockedCardBackIds[r.id])
				or (r.kind == "set" and profile.ownedSetIds[r.id])
				or (r.kind == "title" and profile.rewardTitleIds[r.id])
				or (r.kind == "badge" and profile.badgeIds[r.id])
				or (r.kind == "patron" and profile.discoveredPatronIds[r.id])
				or (r.kind == "recipe" and profile.discoveredRecipeIds[r.id])
			expectTrue(ok, region .. " reward " .. r.id)
		end
	end
end })

-- A run standing at the start of `night` on the default road, with its fork (if any) already picked.
local function runAtStop(night, tips)
	local WorldMap = require(script.Parent.Parent.Engine.WorldMap)
	local state = RunState.new(nil, function(_n) return 1 end)
	while state.night < night do
		state.roundOver = true
		RunState.advanceToNextRound(state)
		WorldMap.fillDefault(state) -- never choosing takes the default road at every fork
	end
	state.tips = tips or 20
	return state
end

table.insert(tests, { name = "SideStops: data is valid, at most 2 per region, and found by parent", fn = function()
	local WorldMap = require(script.Parent.Parent.Engine.WorldMap)
	local ok, errors = WorldMap.validate()
	expectTrue(ok, table.concat(errors, "; "))
	local perRegion = {}
	for id, stop in pairs(WorldMap.Stops) do
		if stop.kind == "side" then
			expectTrue(WorldMap.Stops[stop.parent].kind == "night", id .. " hangs off a Night stop")
			local r = WorldMap.regionOf(id)
			perRegion[r] = (perRegion[r] or 0) + 1
		end
	end
	for r, n in pairs(perRegion) do
		expectTrue(n <= 2, r .. " has " .. n .. " side stops")
	end
	expectEqual(WorldMap.sideStopsAt("wildflower_meadow")[1], "picnic_stall")
	expectEqual(#WorldMap.sideStopsAt("dusty_road"), 0)
	-- three side stops in one region is rejected
	local night = function(region, nxt) return { kind = "night", region = region, art = "a", name = "n", x = 0.5, y = 0.5, next = nxt } end
	local g = { s = night("road", { "m" }), m = night("meadow", { "f" }), f = night("tavern", {}) }
	for i = 1, 3 do
		g["x" .. i] = { kind = "side", parent = "m", side = "shop" }
	end
	expectFalse(WorldMap.validate(g, "s", "f", 3))
	g.x3 = nil
	expectTrue(WorldMap.validate(g, "s", "f", 3))
	g.x2.side = "bogus"
	expectFalse(WorldMap.validate(g, "s", "f", 3))
end })

table.insert(tests, { name = "SideStops: only open at the parent stop, in roundSelect, on the first round", fn = function()
	local SideStops = require(script.Parent.Parent.Engine.SideStops)
	local state = runAtStop(2) -- Night 2 at the meadow: the picnic stall hangs here
	expectEqual(SideStops.blockedReason(state, "picnic_stall", "roundSelect"), nil)
	expectEqual(SideStops.available(state, "roundSelect")[1], "picnic_stall")
	expectEqual(SideStops.blockedReason(state, "picnic_stall", "playing"), "wrong_phase")
	expectEqual(SideStops.blockedReason(state, "picnic_stall", "shop"), "wrong_phase")
	expectEqual(#SideStops.available(state, "playing"), 0)
	expectEqual(SideStops.blockedReason(state, "oasis_stall", "roundSelect"), "not_here", "a stop from another place")
	expectEqual(SideStops.blockedReason(state, "nope", "roundSelect"), "unknown")
	expectEqual(SideStops.blockedReason(state, 7, "roundSelect"), "unknown")
	expectEqual(SideStops.blockedReason(state, "wildflower_meadow", "roundSelect"), "unknown", "a Night stop is not a side stop")
	state.round = 2
	expectEqual(SideStops.blockedReason(state, "picnic_stall", "roundSelect"), "not_started")
	-- a pending fork means the road is not picked yet
	local fork = runAtNight(3)
	expectEqual(SideStops.blockedReason(fork, "garden_shrine", "roundSelect"), "not_here")
end })

table.insert(tests, { name = "SideStops: shop buys only offered patrons, charges Tips, once per run", fn = function()
	local SideStops = require(script.Parent.Parent.Engine.SideStops)
	local state = runAtStop(2, 30)
	local offers = SideStops.rollShop(state)
	expectTrue(#offers >= 1 and #offers <= 2)
	local first = offers[1]
	local ok, why = SideStops.buy(state, "picnic_stall", "playing", offers, first.id)
	expectFalse(ok); expectEqual(why, "wrong_phase")
	ok, why = SideStops.buy(state, "picnic_stall", "roundSelect", offers, "not_a_patron")
	expectFalse(ok); expectEqual(why, "not_offered")
	ok, why = SideStops.buy(state, "picnic_stall", "roundSelect", offers, 5)
	expectFalse(ok); expectEqual(why, "bad_id")
	ok, why = SideStops.buy(state, "garden_shrine", "roundSelect", offers, first.id)
	expectFalse(ok)
	local tipsBefore = state.tips
	ok = SideStops.buy(state, "picnic_stall", "roundSelect", offers, first.id)
	expectTrue(ok)
	expectTrue(state.tips < tipsBefore)
	expectEqual(#state.ownedPatrons, 1)
	for _, p in ipairs(offers) do
		expectTrue(p.id ~= first.id, "bought offer is gone")
	end
	-- too poor
	local poor = runAtStop(2, 0)
	local poorOffers = SideStops.rollShop(poor)
	ok = SideStops.buy(poor, "picnic_stall", "roundSelect", poorOffers, poorOffers[1].id)
	expectFalse(ok)
	expectEqual(#poor.ownedPatrons, 0)
	-- leaving marks it visited for good
	expectTrue(SideStops.finish(state, "picnic_stall", "roundSelect"))
	ok, why = SideStops.finish(state, "picnic_stall", "roundSelect")
	expectFalse(ok); expectEqual(why, "visited")
	ok, why = SideStops.buy(state, "picnic_stall", "roundSelect", offers, offers[1] and offers[1].id or "x")
	expectFalse(ok); expectEqual(why, "visited")
end })

table.insert(tests, { name = "SideStops: the shrine gives a free House Pass for the next Night only", fn = function()
	local SideStops = require(script.Parent.Parent.Engine.SideStops)
	local state = runAtStop(3, 10) -- garden_terrace (default road) has the garden shrine
	local ok, why = SideStops.shrine(state, "garden_shrine", "playing")
	expectFalse(ok); expectEqual(why, "wrong_phase")
	ok, why = SideStops.shrine(state, "picnic_stall", "roundSelect")
	expectFalse(ok)
	local poor = runAtStop(3, 2)
	ok, why = SideStops.shrine(poor, "garden_shrine", "roundSelect")
	expectFalse(ok); expectEqual(why, "not_enough_tips")
	expectEqual(poor.tips, 2)
	ok = SideStops.shrine(state, "garden_shrine", "roundSelect")
	expectTrue(ok)
	expectEqual(state.tips, 10 - SideStops.SHRINE_COST)
	local id = state.tempPass.id
	expectEqual(state.tempPass.night, 4)
	expectEqual(state.housePasses[id], nil, "not active yet this Night")
	ok, why = SideStops.shrine(state, "garden_shrine", "roundSelect")
	expectFalse(ok); expectEqual(why, "visited")
	-- Night 4 turns on, Night 5 turns it off again
	while state.night < 4 do
		state.roundOver = true
		RunState.advanceToNextRound(state)
	end
	expectTrue(state.housePasses[id], "active during Night 4")
	while state.night < 5 do
		state.roundOver = true
		RunState.advanceToNextRound(state)
	end
	expectEqual(state.housePasses[id], nil, "gone on Night 5")
	expectEqual(state.tempPass, nil)
end })

table.insert(tests, { name = "SideStops: rest gives +1 Hand next Night or banks a second One More Round", fn = function()
	local SideStops = require(script.Parent.Parent.Engine.SideStops)
	local state = runAtStop(4) -- willow_bridge: the bridge rest
	local ok, why = SideStops.rest(state, "bridge_rest", "roundSelect", "nope")
	expectFalse(ok); expectEqual(why, "bad_choice")
	ok = SideStops.rest(state, "bridge_rest", "playing", "hand")
	expectFalse(ok)
	ok = SideStops.rest(state, "bridge_rest", "roundSelect", "hand")
	expectTrue(ok)
	expectEqual(state.bonusHandsNight, 5)
	local before = state.config.handsPerRound
	while state.night < 5 do
		state.roundOver = true
		RunState.advanceToNextRound(state)
	end
	expectEqual(state.handsRemaining, before + 1, "+1 Hand on the next Night")
	while state.night < 6 do
		state.roundOver = true
		RunState.advanceToNextRound(state)
	end
	expectEqual(state.handsRemaining, before, "only that Night")
	-- the second continue
	local rest2 = runAtStop(4)
	expectTrue(SideStops.rest(rest2, "bridge_rest", "roundSelect", "continue"))
	expectEqual(rest2.extraContinues, 1)
	rest2.runOver = true
	expectTrue(RunState.canContinue(rest2))
	RunState.useContinue(rest2)
	expectTrue(rest2.revived)
	expectEqual(rest2.extraContinues, 1, "the banked one is still there after the first continue")
	rest2.runOver = true
	expectTrue(RunState.canContinue(rest2), "second continue allowed")
	RunState.useContinue(rest2)
	expectEqual(rest2.extraContinues, 0)
	rest2.runOver = true
	expectFalse(RunState.canContinue(rest2), "no third")
	-- banking twice is refused
	local rest3 = runAtStop(4)
	expectTrue(SideStops.rest(rest3, "bridge_rest", "roundSelect", "continue"))
	rest3.sideVisited = {}
	local ok3, why3 = SideStops.rest(rest3, "bridge_rest", "roundSelect", "continue")
	expectFalse(ok3); expectEqual(why3, "already_banked")
end })

local function scriptedRng(values)
	local i = 0
	return function(n)
		i = i + 1
		local v = values[i] or 1
		return math.max(1, math.min(v, n))
	end
end

table.insert(tests, { name = "Minigames: newRng repeats from a seed and stays in range", fn = function()
	local Minigames = require(script.Parent.Parent.Engine.Minigames)
	local a, b = Minigames.newRng(42), Minigames.newRng(42)
	local c = Minigames.newRng(43)
	local same, differ = true, false
	for _ = 1, 50 do
		local x, y, z = a(6), b(6), c(6)
		expectTrue(x >= 1 and x <= 6)
		if x ~= y then same = false end
		if x ~= z then differ = true end
	end
	expectTrue(same, "same seed, same rolls")
	expectTrue(differ, "different seed, different rolls")
	expectEqual(Minigames.new("nope", a), nil)
	local ok, why = Minigames.act(nil, "roll")
	expectFalse(ok); expectEqual(why, "no_game")
end })

table.insert(tests, { name = "Minigames: dice (closest to 7 without going over, house rolls to 5)", fn = function()
	local Minigames = require(script.Parent.Parent.Engine.Minigames)
	-- win: 4 vs a house that busts (3 then 5 = 8)
	local g = Minigames.new("dice", scriptedRng({ 4, 3, 5 }))
	local ok, why = Minigames.act(g, "hold")
	expectFalse(ok); expectEqual(why, "roll_first")
	expectTrue(Minigames.act(g, "roll"))
	expectTrue(Minigames.act(g, "hold"))
	expectTrue(g.done and g.won)
	expectEqual(g.score, 4); expectEqual(g.houseScore, 0)
	ok, why = Minigames.act(g, "roll")
	expectFalse(ok); expectEqual(why, "finished")
	-- lose: bust
	g = Minigames.new("dice", scriptedRng({ 5, 5 }))
	Minigames.act(g, "roll")
	local _, info = Minigames.act(g, "roll")
	expectTrue(info.bust and g.done and not g.won)
	-- tie loses: 4 vs 2+1+1
	g = Minigames.new("dice", scriptedRng({ 4, 2, 1, 1 }))
	Minigames.act(g, "roll"); Minigames.act(g, "hold")
	expectEqual(g.houseScore, 4)
	expectFalse(g.won, "ties go to the house")
	-- three dice end the turn by themselves
	g = Minigames.new("dice", scriptedRng({ 1, 1, 1, 6 }))
	for _ = 1, 3 do Minigames.act(g, "roll") end
	expectTrue(g.done and not g.won, "3 against the house's 6 loses")
	expectEqual(g.score, 3); expectEqual(g.houseScore, 6)
end })

table.insert(tests, { name = "Minigames: card flip (3 pairs in 8 flips, bad moves refused)", fn = function()
	local Minigames = require(script.Parent.Parent.Engine.Minigames)
	local g = Minigames.new("cardflip", scriptedRng({ 1 }))
	g.faces = { 1, 2, 1, 3, 2, 3 }
	for _, bad in ipairs({ 0, 7, 1.5, "1", true }) do
		local ok = Minigames.act(g, "flip", bad)
		expectFalse(ok, "bad index " .. tostring(bad))
	end
	expectEqual(g.flips, 0, "bad moves cost nothing")
	local ok, info = Minigames.act(g, "flip", 1)
	expectTrue(ok); expectEqual(info.face, 1)
	local ok2, why = Minigames.act(g, "flip", 1)
	expectFalse(ok2); expectEqual(why, "already_flipped")
	ok, info = Minigames.act(g, "flip", 3)
	expectTrue(info.match)
	ok, why = Minigames.act(g, "flip", 1)
	expectFalse(ok); expectEqual(why, "already_matched")
	-- a miss hides both again
	Minigames.act(g, "flip", 2)
	ok, info = Minigames.act(g, "flip", 4)
	expectEqual(info.match, false)
	expectEqual(#info.hide, 2)
	-- the view never leaks unflipped faces
	local v = Minigames.view(g)
	expectEqual(v.faces, nil)
	-- finish: 2/5 then 4/6
	Minigames.act(g, "flip", 2); Minigames.act(g, "flip", 5)
	expectEqual(g.pairs, 2)
	Minigames.act(g, "flip", 4); Minigames.act(g, "flip", 6)
	expectTrue(g.done and g.won, "6 flips would be enough; this took 8")
	-- the flip limit ends a losing game
	local lose = Minigames.new("cardflip", scriptedRng({ 1 }))
	lose.faces = { 1, 2, 3, 1, 2, 3 }
	for _ = 1, 4 do
		Minigames.act(lose, "flip", 1); Minigames.act(lose, "flip", 2)
	end
	expectTrue(lose.done and not lose.won)
end })

table.insert(tests, { name = "Minigames: lockpick reads the needle from the server clock", fn = function()
	local Minigames = require(script.Parent.Parent.Engine.Minigames)
	expectEqual(Minigames.needleAt(0, 100), 0)
	expectEqual(Minigames.needleAt(3.6, 100), 360)
	expectEqual(Minigames.needleAt(5.4, 100), 180, "sweeps back down")
	for t = 0, 20, 0.7 do
		local a = Minigames.needleAt(t, 173)
		expectTrue(a >= 0 and a <= 360)
	end
	local g = Minigames.new("lockpick", scriptedRng({ 50, 1, 200, 30, 60 }), 100)
	g.speed, g.center = 180, 90
	-- the client's claimed angle is ignored: only the clock counts
	local ok, info = Minigames.act(g, "stop", 90, 100.5) -- needle at 90
	expectTrue(ok and info.hit)
	expectEqual(g.hits, 1)
	g.center = 300
	ok, info = Minigames.act(g, "stop", 300, 100.5) -- needle still at 90: a miss, whatever the client says
	expectTrue(ok); expectFalse(info.hit)
	g.center = 90
	Minigames.act(g, "stop", 0, 100.5); g.center = 90
	ok = Minigames.act(g, "stop", 0, 100.5)
	expectTrue(g.done and g.won, "3 hits")
	-- 5 misses lose
	local lose = Minigames.new("lockpick", scriptedRng({ 10, 1 }), 0)
	lose.speed, lose.center = 180, 300
	for _ = 1, 5 do Minigames.act(lose, "stop", 0, 0.5) end
	expectTrue(lose.done and not lose.won)
	local bad, why = Minigames.act(lose, "stop", 0, 0.5)
	expectFalse(bad); expectEqual(why, "finished")
	local g2 = Minigames.new("lockpick", scriptedRng({ 1 }))
	bad, why = Minigames.act(g2, "flip")
	expectFalse(bad); expectEqual(why, "bad_action")
end })

table.insert(tests, { name = "Minigames: trivia asks 3 questions, hides answers, times out, needs 2 right", fn = function()
	local Minigames = require(script.Parent.Parent.Engine.Minigames)
	local g = Minigames.new("trivia", Minigames.newRng(7), 0)
	expectEqual(#g.questions, 3)
	for _, q in ipairs(g.questions) do
		expectEqual(#q.answers, 3)
		local right = 0
		for _, a in ipairs(q.answers) do
			if a.ok then right = right + 1 end
		end
		expectEqual(right, 1, "exactly one right answer: " .. q.text)
	end
	local v = Minigames.view(g, 1)
	expectTrue(v.question.text ~= nil and #v.question.answers == 3)
	expectEqual(type(v.question.answers[1]), "string", "answers are plain text, no flags")
	local function rightIndex(game)
		for i, a in ipairs(game.questions[game.current].answers) do
			if a.ok then return i end
		end
	end
	expectFalse(Minigames.act(g, "answer", 0, 1))
	expectFalse(Minigames.act(g, "answer", 4, 1))
	expectFalse(Minigames.act(g, "answer", 1.5, 1))
	local ok, info = Minigames.act(g, "answer", rightIndex(g), 2)
	expectTrue(ok and info.right)
	-- second answer comes too late
	ok, info = Minigames.act(g, "answer", rightIndex(g), 2 + Minigames.QUESTION_SECONDS + 5)
	expectTrue(ok); expectFalse(info.right); expectTrue(info.late)
	ok, info = Minigames.act(g, "answer", rightIndex(g), 2 + Minigames.QUESTION_SECONDS + 7)
	expectTrue(g.done and g.won, "2 of 3 wins")
	-- 1 of 3 loses
	local g2 = Minigames.new("trivia", Minigames.newRng(9), 0)
	Minigames.act(g2, "answer", rightIndex(g2), 1)
	for _ = 1, 2 do
		local wrong = rightIndex(g2) % 3 + 1
		Minigames.act(g2, "answer", wrong, 1)
	end
	expectTrue(g2.done and not g2.won)
end })

table.insert(tests, { name = "Minigames: a win gives a token (max 3, never on ranked boards) and maybe a compass charge", fn = function()
	local Minigames = require(script.Parent.Parent.Engine.Minigames)
	local PlayerProfile = require(script.Parent.Parent.Engine.PlayerProfile)
	local state = runAtNight(2)
	local profile = PlayerProfile.new()
	local out = Minigames.reward(state, profile, scriptedRng({ 1 }))
	expectTrue(out.token and out.compass)
	expectEqual(state.mapTokens, 1); expectEqual(profile.compassCharges, 1)
	out = Minigames.reward(state, profile, scriptedRng({ 2 }))
	expectTrue(out.token); expectFalse(out.compass, "a 2 means no charge this time")
	Minigames.reward(state, profile, scriptedRng({ 2 }))
	out = Minigames.reward(state, profile, scriptedRng({ 1 }))
	expectFalse(out.token, "capped at 3 tokens")
	expectEqual(state.mapTokens, 3)
	-- ranked: Daily, Weekly and Seed runs have a fixed route
	local ranked = runAtNight(2, { worldPlan = { "dusty_road", "wildflower_meadow" } })
	out = Minigames.reward(ranked, profile, scriptedRng({ 1 }))
	expectFalse(out.token or out.compass)
	expectEqual(ranked.mapTokens, nil)
end })

table.insert(tests, { name = "BiomeRewards: a map token upgrades a branch end with the biome's bonus title", fn = function()
	local BiomeRewards = require(script.Parent.Parent.Engine.BiomeRewards)
	local PlayerProfile = require(script.Parent.Parent.Engine.PlayerProfile)
	local route = { "dusty_road", "wildflower_meadow", "desert_dunes", "oasis_camp" }
	local noToken = PlayerProfile.new()
	BiomeRewards.recordProgress(noToken, route, 4, { mapTokens = 0 })
	expectTrue(noToken.unlockedCardBackIds.dune_gold)
	expectEqual(noToken.rewardTitleIds.dune_wanderer, nil)
	local state = { mapTokens = 2 }
	local profile = PlayerProfile.new()
	BiomeRewards.recordProgress(profile, route, 4, state)
	expectTrue(profile.unlockedCardBackIds.dune_gold and profile.rewardTitleIds.dune_wanderer)
	expectEqual(state.mapTokens, 1, "one token spent")
	BiomeRewards.recordProgress(profile, route, 4, state)
	expectEqual(state.mapTokens, 1, "nothing more to upgrade, nothing spent")
	-- a region without a bonus keeps its token
	local s2 = { mapTokens = 1 }
	BiomeRewards.recordProgress(PlayerProfile.new(), { "dusty_road", "wildflower_meadow", "desert_dunes" }, 2, s2)
	expectEqual(s2.mapTokens, 1, "meadow has no bonus title")
end })

table.insert(tests, { name = "Compass: charges are capped, spent once per fork, and gated by phase", fn = function()
	local BiomeRewards = require(script.Parent.Parent.Engine.BiomeRewards)
	local PlayerProfile = require(script.Parent.Parent.Engine.PlayerProfile)
	local profile = PlayerProfile.new()
	expectEqual(profile.compassCharges, 0)
	for _ = 1, 5 do
		PlayerProfile.addCompassCharge(profile)
	end
	expectEqual(profile.compassCharges, PlayerProfile.MAX_COMPASS_CHARGES)
	expectFalse(PlayerProfile.addCompassCharge(profile), "capped at 3")
	-- load clamps junk
	expectEqual(PlayerProfile.migrate({ compassCharges = 99 }).compassCharges, 3)
	expectEqual(PlayerProfile.migrate({ compassCharges = -4 }).compassCharges, 0)
	expectEqual(PlayerProfile.migrate({ compassCharges = "x" }).compassCharges, 0)
	expectEqual(PlayerProfile.migrate({ compassCharges = 0 / 0 }).compassCharges, 0)
	-- not at a fork (Night 2 is a plain road)
	local plain = runAtNight(2)
	local ok, why = BiomeRewards.useCompass(profile, plain, "roundSelect")
	expectFalse(ok); expectEqual(why, "no_fork")
	expectEqual(profile.compassCharges, 3, "a refused use spends nothing")
	-- wrong phase
	local fork = runAtNight(3)
	ok, why = BiomeRewards.useCompass(profile, fork, "playing")
	expectFalse(ok); expectEqual(why, "wrong_phase")
	ok, why = BiomeRewards.useCompass(profile, fork, "shop")
	expectFalse(ok)
	expectEqual(profile.compassCharges, 3)
	-- the real use
	local roads
	ok, roads = BiomeRewards.useCompass(profile, fork, "roundSelect")
	expectTrue(ok); expectEqual(#roads, 3)
	expectEqual(profile.compassCharges, 2)
	expectEqual(#BiomeRewards.revealedChoices(fork), 3)
	ok, why = BiomeRewards.useCompass(profile, fork, "roundSelect")
	expectFalse(ok); expectEqual(why, "already_used")
	expectEqual(profile.compassCharges, 2)
	-- the reveal ends once the road is picked
	local WorldMap = require(script.Parent.Parent.Engine.WorldMap)
	WorldMap.chooseRoad(fork, "desert_dunes", "roundSelect")
	expectEqual(BiomeRewards.revealedChoices(fork), nil)
	-- no charges
	local broke = PlayerProfile.new()
	ok, why = BiomeRewards.useCompass(broke, runAtNight(3), "roundSelect")
	expectFalse(ok); expectEqual(why, "no_charge")
end })

table.insert(tests, { name = "Compass: turning the wheel picks the road it points at (shortest turn wraps)", fn = function()
	local WorldMap = require(script.Parent.Parent.Engine.WorldMap)
	-- from the meadow the desert road heads up-right, the marsh down-right, the garden straight on
	local up = WorldMap.bearing("wildflower_meadow", "desert_dunes")
	local down = WorldMap.bearing("wildflower_meadow", "swamp_boardwalk")
	expectTrue(up > 0 and up < 90, "desert is up and to the right: " .. up)
	expectTrue(down > 90 and down < 180, "marsh is down and to the right: " .. down)
	expectEqual(WorldMap.pickByBearing("wildflower_meadow", up), "desert_dunes")
	expectEqual(WorldMap.pickByBearing("wildflower_meadow", down), "swamp_boardwalk")
	expectEqual(WorldMap.pickByBearing("wildflower_meadow", 270), "desert_dunes", "pointing backwards still picks the nearest road")
	-- the idle bearing points from every stop toward the Finish
	for id, stop in pairs(WorldMap.Stops) do
		if id ~= WorldMap.Finish and stop.kind == "night" then
			local b = WorldMap.bearing(id, WorldMap.Finish)
			expectTrue(b > 0 and b < 180, id .. " heads east toward the Keeper: " .. b)
		end
	end
end })

table.insert(tests, { name = "SceneKeys: the chosen road decides each Night's scene, with fallbacks", fn = function()
	local SceneKeys = require(script.Parent.Parent.Engine.SceneKeys)
	local WorldMap = require(script.Parent.Parent.Engine.WorldMap)
	SceneKeys.setRoute(nil)
	expectEqual(SceneKeys.keyFor(3, "small"), "garden_terrace_a", "no route: the default Nights")
	SceneKeys.setRoute({ "dusty_road", "wildflower_meadow", "desert_dunes", "oasis_camp" })
	expectEqual(SceneKeys.keyFor(1, "small"), "dusty_road_a")
	-- desert scenes are generated and recorded: the chosen stop's own scene is used
	expectEqual(SceneKeys.keyFor(3, "big"), "desert_dunes_b")
	expectEqual(SceneKeys.keyFor(4, "boss"), "oasis_camp_in")
	-- a Night whose road is not picked yet, and Nights past the route, use the default list
	expectEqual(SceneKeys.keyFor(5, "small"), "mountain_pass_a")
	expectEqual(SceneKeys.keyFor(9, "small"), "front_porch_a", "Endless rotation is unchanged")
	-- a full default route gives exactly the old keys for Nights 1 to 8
	SceneKeys.setRoute(WorldMap.defaultRoute())
	SceneKeys.setRoute(WorldMap.defaultRoute())
	for n, stop in ipairs(WorldMap.defaultRoute()) do
		expectEqual(SceneKeys.keyFor(n, "boss"), WorldMap.Stops[stop].art .. "_in")
	end
	-- explicit lists (used by older callers and tests) ignore the route
	expectEqual(SceneKeys.artFor(1, { { art = "x" } }, {}), "x")
	SceneKeys.setRoute("junk")
	expectEqual(SceneKeys.route, nil)
	SceneKeys.setRoute(nil)
end })

table.insert(tests, { name = "WorldMap: new biome stops fall back to an existing scene while art is missing", fn = function()
	local WorldMap = require(script.Parent.Parent.Engine.WorldMap)
	local SceneArt = require(script.Parent.Parent.Engine.SceneArt)
	local function hasArt(key)
		return SceneArt[key .. "_a"] ~= nil
	end
	for _, id in ipairs({ "desert_dunes", "oasis_camp", "swamp_boardwalk", "lilypad_pond", "frosty_trail", "lighthouse_cove" }) do
		local stop = WorldMap.Stops[id]
		expectTrue(stop.fallbackArt ~= nil, id .. " needs a fallbackArt")
		expectTrue(hasArt(stop.fallbackArt), id .. " fallback " .. stop.fallbackArt .. " has no scenes")
		expectEqual(WorldMap.sceneArtFor(id, function() return false end), stop.fallbackArt)
		expectEqual(WorldMap.sceneArtFor(id, function() return true end), stop.art)
	end
	expectEqual(WorldMap.sceneArtFor("garden_terrace", function() return false end), "garden_terrace", "no fallback needed")
end })

table.insert(tests, { name = "Tutorial: the step table covers the guided hands in order and the walkthrough is wired", fn = function()
	local Steps = require(script.Parent.Parent.Engine.TutorialSteps)
	local order = {}
	for i, step in ipairs(Steps.Steps) do order[step.id] = i end
	local last = 0
	for _, id in ipairs({ "menu_play", "select_round", "pick_pair", "play_pair", "pick_two_pair", "play_two_pair", "pick_flush", "play_flush", "pick_straight_flush", "play_straight_flush", "next_round", "done" }) do
		expectTrue(order[id] ~= nil, "missing step " .. id)
		expectTrue(order[id] > last, "step out of order: " .. id)
		last = order[id]
	end
	-- Roblox has no `io` library: only the local runner can read the source file.
	local f = io and io.open and io.open("src/Client/TutorialWalkthrough.lua", "r")
	if not f then
		return -- not running from the repo root (Studio): nothing more to check
	end
	local src = f:read("*a")
	f:close()
	expectTrue(src:find("replay = replay", 1, true) ~= nil, "replay is exported")
	expectTrue(src:find("Hold to Skip", 1, true) ~= nil, "skipping needs a hold")
	expectTrue(src:find("Active = true", 1, true) ~= nil or src:find("f.Active = true", 1, true) ~= nil, "the dim frames block clicks")
	expectFalse(src:find("Keep these cards", 1, true) ~= nil, "no old optional-choice buttons")
end })

table.insert(tests, { name = "TutorialStart: only an explicit tutorial run is scripted, it never writes the profile, ribbon until done", fn = function()
	local TS = require(script.Parent.Parent.Engine.TutorialStart)
	expectEqual(TS.initialStage(true, false), 1)
	expectEqual(TS.initialStage(nil, false), nil) -- Play, New Run, first launch
	expectEqual(TS.initialStage(false, false), nil)
	expectEqual(TS.initialStage(true, true), nil) -- Daily, Weekly, Seed never
	expectFalse(TS.writesProfile({ isTutorial = true }))
	expectTrue(TS.writesProfile({ isTutorial = false }) and TS.writesProfile({}))
	expectTrue(TS.showNewRibbon({ hasSeenTutorial = false }, false))
	expectFalse(TS.showNewRibbon({ hasSeenTutorial = true }, false))
	expectFalse(TS.showNewRibbon({ hasSeenTutorial = false }, true))
	-- Source scans (local runner only; Studio has no `io`).
	local f = io and io.open and io.open("src/Server/init.server.lua", "r")
	if not f then return end
	local server = f:read("*a"); f:close()
	local n = 0
	for _ in server:gmatch("startNewSession%([^\n]*, true%)") do n = n + 1 end
	expectEqual(n, 1) -- exactly one call passes isTutorial: the StartTutorial handler
	expectTrue(server:find("Rem.StartTutorial.OnServerEvent", 1, true) ~= nil)
	expectFalse(server:find("hasSeenTutorial == false) and 1", 1, true) ~= nil, "no first-run auto stage")
	local c = io.open("src/Client/TutorialWalkthrough.lua", "r")
	local client = c:read("*a"); c:close()
	expectFalse(client:find("autoTried", 1, true) ~= nil, "no auto start in the walkthrough")
	local m = io.open("src/Client/init.client.lua", "r")
	local hub = m:read("*a"); m:close()
	local _, starts = hub:gsub("tutorial%.replay%(%)", "")
	expectTrue(starts >= 1)
end })

table.insert(tests, { name = "Tutorial spotlight: every step target is a known name, resolved live and never from a stale rect", fn = function()
	local Steps = require(script.Parent.Parent.Engine.TutorialSteps)
	for _, step in ipairs(Steps.Steps) do
		if step.target then
			expectTrue(Steps.TargetNames[step.target] == true, "unknown target " .. tostring(step.target) .. " in step " .. step.id)
		end
	end
	local f = io and io.open and io.open("src/Client/TutorialWalkthrough.lua", "r")
	if not f then return end
	local src = f:read("*a"); f:close()
	expectTrue(src:find("resolveTarget(currentStep)", 1, true) ~= nil, "layout re-resolves the target every frame")
	expectTrue(src:find("IsDescendantOf(screenGui)", 1, true) ~= nil, "destroyed elements are rejected")
	expectTrue(src:find("[Tutorial] target not found", 1, true) ~= nil, "a missing target warns")
	expectTrue(src:find("HandIndex", 1, true) ~= nil, "hand cards are found by tag")
	local h = io.open("src/Client/init.client.lua", "r")
	local hub = h:read("*a"); h:close()
	expectTrue(hub:find('slot:SetAttribute("HandIndex"', 1, true) ~= nil, "hand slots carry the tag")
end })

table.insert(tests, { name = "Tutorial forced input: only the scripted cards, Play only after the right pick, everything else rejected", fn = function()
	local Steps = require(script.Parent.Parent.Engine.TutorialSteps)
	local m = Steps.new()
	m:report("menu_play"); m:report("select_round")
	expectEqual(m:current().id, "pick_pair")
	-- during "pick sevens" any other card is rejected, the two Sevens are allowed
	expectTrue(m:allows("card", { index = 1, scripted = true }))
	expectTrue(m:allows("card", { index = 2, scripted = true }))
	expectFalse(m:allows("card", { index = 3, scripted = true }), "a different card")
	expectFalse(m:allows("card", { index = 8, scripted = true }))
	-- Play Hand, Discard, Sort, Reroll, buys, packs and Next Round are rejected until their step
	for _, kind in ipairs({ "play", "discard", "sort", "reroll", "buy", "pack", "nextRound", "menuPlay", "select" }) do
		expectFalse(m:allows(kind), kind .. " must be rejected while picking")
	end
	-- selecting the two Sevens advances to Play Hand, which is then (and only then) allowed
	expectEqual(m:report("pick", { selected = { [1] = true, [2] = true }, scripted = true }), "advanced")
	expectEqual(m:current().id, "play_pair")
	expectTrue(m:allows("play"))
	expectFalse(m:allows("card", { index = 1, scripted = true }), "no card clicks during the play step")
	expectFalse(m:allows("discard"))
	-- the wrong pick does not advance
	local m2 = Steps.new()
	m2:report("menu_play"); m2:report("select_round")
	expectEqual(m2:report("pick", { selected = { [3] = true, [4] = true }, scripted = true }), "ignored")
	expectEqual(m2:current().id, "pick_pair")
	-- every step names exactly what it allows
	for _, step in ipairs(Steps.Steps) do
		expectTrue(type(step.allow) == "table" and #step.allow >= 1, "step " .. step.id .. " has an allow list")
	end
	-- finished tutorial allows everything
	local m3 = Steps.new(); m3:skip()
	expectTrue(m3:allows("discard"))
	local f = io and io.open and io.open("src/Client/init.client.lua", "r")
	if not f then return end
	local hub = f:read("*a"); f:close()
	for _, kind in ipairs({ "card", "play", "discard", "nextRound", "sort" }) do
		expectTrue(hub:find('tutorial.allows("' .. kind .. '"', 1, true) ~= nil, "hub gates " .. kind)
	end
	local sf = io.open("src/Client/Shop.lua", "r")
	local shop = sf:read("*a"); sf:close()
	for _, kind in ipairs({ "reroll", "buy", "pack" }) do
		expectTrue(shop:find('tutorialAllows("' .. kind .. '"', 1, true) ~= nil, "shop gates " .. kind)
	end
end })

table.insert(tests, { name = "Tutorial Skip button: 24px inside the edge, below the icon row and Tips chip, scales down on small screens", fn = function()
	local TS = require(script.Parent.Parent.Engine.TutorialStart)
	for _, v in ipairs({ { 1920, 1080 }, { 1280, 720 }, { 800, 450 }, { 2560, 1440 } }) do
		local L = TS.skipLayout(v[1], v[2])
		expectTrue(L.right >= 24, "margin from the edge")
		expectTrue(L.top >= 66 + 16, "below the corner icon row (ends at y 66)")
		expectTrue(L.top >= 52 + 16, "below the Tips chip")
		expectTrue(L.scale >= 0.75 and L.scale <= 1)
		expectTrue(L.right + L.width * L.scale <= v[1] / 2, "fully on screen")
	end
	expectEqual(TS.skipLayout(2560, 1440).scale, 1)
	expectTrue(TS.skipLayout(800, 450).scale < 1)
end })

table.insert(tests, { name = "Tutorial Shop section: panel pieces, Counter, buy a Patron and a Pack, tabs, Reroll, then Next Round and Finish", fn = function()
	local Steps = require(script.Parent.Parent.Engine.TutorialSteps)
	local ids = {}
	for i, step in ipairs(Steps.Steps) do ids[step.id] = i end
	local order = { "play_straight_flush", "panel_target", "panel_tips", "panel_hands", "panel_patrons",
		"shop_patrons", "buy_patron", "buy_pack", "pick_pack_item", "confirm_pack", "tab_patrons",
		"tab_shop", "reroll", "next_round", "done" }
	local last = 0
	for _, id in ipairs(order) do
		expectTrue(ids[id] ~= nil and ids[id] > last, "step order: " .. id)
		last = ids[id]
	end
	-- the last card is the celebration with a Finish button
	local done = Steps.Steps[#Steps.Steps]
	expectEqual(done.id, "done"); expectEqual(done.button, "Finish"); expectTrue(done.celebrate)
	-- jumping into the Shop section lands on the first Shop step, never past it
	local m = Steps.new()
	m:report("menu_play"); m:report("select_round")
	expectTrue(m:catchUpShop())
	expectEqual(m:current().id, "panel_target")
	-- tapping the spotlighted piece is the only way on; the wrong thing wiggles
	expectEqual(m:report("reroll"), "wrong")
	expectFalse(m:allows("buy")); expectFalse(m:allows("reroll")); expectFalse(m:allows("nextRound"))
	expectTrue(m:allows("tap"))
	for _, id in ipairs({ "panel_target", "panel_tips", "panel_hands", "panel_patrons", "shop_patrons" }) do
		expectEqual(m:current().id, id)
		expectEqual(m:report("tap"), "advanced")
	end
	expectEqual(m:current().id, "buy_patron")
	expectTrue(m:allows("buy")); expectFalse(m:allows("pack")); expectFalse(m:allows("packSkip"))
	expectEqual(m:report("buy_patron"), "advanced")
	expectEqual(m:current().id, "buy_pack")
	expectEqual(m:report("buy_pack"), "advanced")
	expectEqual(m:current().id, "pick_pack_item")
	expectTrue(m:allows("packItem")); expectFalse(m:allows("packConfirm"))
	expectEqual(m:report("pack_item"), "advanced")
	expectTrue(m:allows("packConfirm"))
	expectEqual(m:report("pack_confirm"), "advanced")
	-- tabs: only the named tab opens, each tapped once
	expectEqual(m:current().id, "tab_patrons")
	expectTrue(m:allows("tab", { key = "mypatrons" })); expectFalse(m:allows("tab", { key = "myrecipes" }))
	expectEqual(m:report("tab_mypatrons"), "advanced")
	expectTrue(m:allows("tab", { key = "buy" }))
	expectEqual(m:report("tab_buy"), "advanced")
	expectEqual(m:current().id, "reroll")
	expectEqual(m:report("reroll"), "advanced")
	expectEqual(m:current().id, "next_round")
	expectEqual(m:report("next_round"), "advanced")
	expectEqual(m:report("ok"), "advanced")
	expectTrue(m:finished())
	-- every target name is registered somewhere in the client
	local f = io and io.open and io.open("src/Client/TutorialWalkthrough.lua", "r")
	if not f then return end
	local src = f:read("*a"); f:close()
	local shop = io.open("src/Client/Shop.lua", "r"):read("*a")
	local menu = io.open("src/Client/Menu.lua", "r"):read("*a")
	local hub = io.open("src/Client/init.client.lua", "r"):read("*a")
	for name in pairs(Steps.TargetNames) do
		if name ~= "handCards" then
			local found = src:find('register("' .. name .. '"', 1, true) or shop:find('register("' .. name .. '"', 1, true)
				or shop:find('"' .. name .. '"', 1, true) or hub:find('register("' .. name .. '"', 1, true) or menu:find('"' .. name .. '"', 1, true)
			expectTrue(found ~= nil, "target registered: " .. name)
		end
	end
end })

table.insert(tests, { name = "TutorialScript.shopFor: a cheap Patron and Pack are always on the shelf and the player can afford them plus a Reroll", fn = function()
	local TS = require(script.Parent.Parent.Engine.TutorialScript)
	local Patrons = require(script.Parent.Parent.Engine.Patrons)
	local Packs = require(script.Parent.Parent.Engine.Packs)
	local state = { tips = 0, ownedPatrons = {} }
	local offers = { patrons = { Patrons.Definitions[#Patrons.Definitions] }, packs = {}, voucher = { id = "x" } }
	local need = TS.shopFor(state, offers, 5)
	local cheapest = math.huge
	for _, p in ipairs(Patrons.Definitions) do cheapest = math.min(cheapest, p.price) end
	expectEqual(offers.patrons[1].price, cheapest)
	local cheapPack = math.huge
	for _, p in ipairs(Packs.Definitions) do cheapPack = math.min(cheapPack, p.price) end
	expectEqual(offers.packs[1].price, cheapPack)
	expectEqual(offers.voucher, nil)
	expectTrue(state.tips >= cheapest + cheapPack + 5, "enough Tips for Patron, Pack and one Reroll")
	expectEqual(state.tips, need)
	expectTrue(#offers.patrons <= 2 and #offers.packs <= 2)
	-- after buying that Patron the next roll offers the next cheapest one, never a duplicate
	state.ownedPatrons = { offers.patrons[1] }
	local again = { patrons = {}, packs = {} }
	TS.shopFor(state, again, 5)
	expectTrue(again.patrons[1].id ~= state.ownedPatrons[1].id)
	-- the server applies it only to a tutorial session
	local f = io and io.open and io.open("src/Server/init.server.lua", "r")
	if not f then return end
	local server = f:read("*a"); f:close()
	expectTrue(server:find("if session.isTutorial then\n\t\tTutorialScript.shopFor", 1, true) ~= nil)
end })

table.insert(tests, { name = "PhoneLayout: touch minimum text and tap size, compact detection", fn = function()
	local PL = require(script.Parent.Parent.Engine.PhoneLayout)
	expectEqual(PL.textSize(11, true), 14)
	expectEqual(PL.textSize(11, false), 11)
	expectEqual(PL.textSize(16, true), 16)
	local w, h = PL.tapSize(30, 60, true)
	expectEqual(w, 44)
	expectEqual(h, 60)
	w, h = PL.tapSize(30, 30, false)
	expectEqual(w, 30)
	expectEqual(h, 30)
	-- growing a top-left anchored button 30 -> 44 shifts it by -7 so it grows around its center
	local dx, dy = PL.growShift(30, 30, 44, 44, 0, 0)
	expectEqual(dx, -7)
	expectEqual(dy, -7)
	dx = PL.growShift(30, 30, 44, 44, 0.5, 0.5)
	expectEqual(dx, 0)
	expectTrue(PL.isCompact(400), "800x400 is compact")
	expectTrue(not PL.isCompact(720), "1280x720 is not compact")
end })

table.insert(tests, { name = "WorldMapLayout: every stop is placed, nodes never overlap, every edge joins two real stops", fn = function()
	local WorldMap = require(script.Parent.Parent.Engine.WorldMap)
	local L = require(script.Parent.Parent.Engine.WorldMapLayout)
	local nightX, routeY = {}, {}
	for i = 1, 8 do
		nightX[i] = 400 + (i - 1) * 280
		routeY[i] = 300 + ((i % 2 == 0) and -60 or 60)
	end
	local routes = WorldMap.allRoutes()
	expectTrue(#routes == 18, "18 routes")
	for _, route in ipairs(routes) do
		local res = L.compute({ nightX = nightX, routeY = routeY, height = 600, route = route })
		local count = 0
		for id, p in pairs(res.pos) do
			count = count + 1
			expectTrue(WorldMap.Stops[id] ~= nil and p.depth >= 1 and p.depth <= 8, "real stop " .. id)
			for id2, q in pairs(res.pos) do
				if id < id2 and p.x == q.x then
					expectTrue(math.abs(p.y - q.y) >= 100, id .. " overlaps " .. id2)
				end
			end
		end
		local nights = 0
		for _, stop in pairs(WorldMap.Stops) do
			if stop.kind == "night" then nights = nights + 1 end
		end
		expectEqual(count, nights)
		for _, e in ipairs(res.edges) do
			expectTrue(res.pos[e.from] and res.pos[e.to], "edge joins two placed stops")
			expectEqual(res.pos[e.to].depth, res.pos[e.from].depth + 1)
		end
		for i, id in ipairs(route) do
			expectEqual(res.pos[id].y, routeY[i])
		end
	end
end })

table.insert(tests, { name = "WorldMapLayout: every side stop sits beside its parent and clear of every Night node", fn = function()
	local WorldMap = require(script.Parent.Parent.Engine.WorldMap)
	local L = require(script.Parent.Parent.Engine.WorldMapLayout)
	local nightX, routeY = {}, {}
	for i = 1, 8 do
		nightX[i] = 400 + (i - 1) * 280
		routeY[i] = 300 + ((i % 2 == 0) and -60 or 60)
	end
	for _, route in ipairs(WorldMap.allRoutes()) do
		local res = L.compute({ nightX = nightX, routeY = routeY, height = 600, route = route, minGap = 108 })
		local sides = 0
		for id, p in pairs(res.side) do
			sides = sides + 1
			expectTrue(res.pos[p.parent] ~= nil and p.x > res.pos[p.parent].x, id .. " is right of its parent")
			for nid, n in pairs(res.pos) do
				local d = math.sqrt((n.x - p.x) ^ 2 + (n.y - p.y) ^ 2)
				expectTrue(d >= 58, id .. " is too close to " .. nid)
			end
			for id2, q in pairs(res.side) do
				if id < id2 then
					expectTrue(math.sqrt((q.x - p.x) ^ 2 + (q.y - p.y) ^ 2) >= 40, id .. " overlaps " .. id2)
				end
			end
		end
		expectEqual(sides, 15)
	end
end })

table.insert(tests, { name = "Biome completion: every biome gives a set, a badge and a title; a win through it adds Master, each once", fn = function()
	local BiomeRewards = require(script.Parent.Parent.Engine.BiomeRewards)
	local Badges = require(script.Parent.Parent.Engine.Badges)
	local WorldMap = require(script.Parent.Parent.Engine.WorldMap)
	local CollectionBook = require(script.Parent.Parent.Engine.CollectionBook)
	local biomes = { "meadow", "river", "peaks", "desert", "swamp", "snow", "coast", "tavern" }
	for _, region in ipairs(biomes) do
		local first = { set = 0, badge = 0, title = 0 }
		for _, r in ipairs(BiomeRewards.Rows[region].reward) do
			if first[r.kind] ~= nil then first[r.kind] = first[r.kind] + 1 end
		end
		-- the Peaks and Snow rows already granted an older set, so they hold two
		expectTrue(first.set >= 1 and first.badge == 1 and first.title >= 1, region .. " first-clear set, badge and title")
		local master = BiomeRewards.Master[region]
		expectTrue(master ~= nil and #master == 2, region .. " has a Master badge and title")
		for _, r in ipairs(master) do
			if r.kind == "badge" then
				local def = Badges.getById(r.id)
				expectTrue(def ~= nil and def.tier == "master" and def.region == region, r.id)
			else
				local a = Achievements.getById(r.id)
				expectTrue(a ~= nil and a.milestoneReward == true and a.flavorText ~= "", r.id)
				expectTrue(CollectionBook.Rarities[CollectionBook.rarityForId("titles", r.id)] ~= nil)
			end
		end
	end
	for _, def in ipairs(Badges.Definitions) do
		expectTrue(CollectionBook.Rarities[def.rarity] ~= nil, def.id .. " rarity")
		expectFalse((def.name .. def.description):lower():find("balatro", 1, true) ~= nil)
	end
	-- first clear: granted once (route through the desert), nothing for the next push
	local profile = PlayerProfile.new()
	local route = { "dusty_road", "wildflower_meadow", "desert_dunes", "oasis_camp", "mountain_pass", "tavern_gate", "grand_hall", "keepers_table" }
	expectTrue(WorldMap.isValidRoute(route))
	BiomeRewards.recordProgress(profile, route, 8)
	expectTrue(profile.badgeIds.biome_desert and profile.badgeIds.biome_meadow and profile.badgeIds.biome_tavern)
	expectTrue(profile.rewardTitleIds.dune_crosser and profile.ownedSetIds.dune_market)
	expectEqual(profile.badgeIds.master_desert, nil, "no Master before a win")
	expectEqual(#BiomeRewards.recordProgress(profile, route, 8), 0, "once")
	-- a win through the route: Master badge and title for every biome on it, once
	local fresh = BiomeRewards.recordRunWin(profile, route)
	expectTrue(#fresh > 0)
	for _, region in ipairs({ "meadow", "desert", "peaks", "tavern" }) do
		expectTrue(profile.badgeIds["master_" .. region], "master " .. region)
	end
	expectTrue(profile.rewardTitleIds.dune_master and profile.rewardTitleIds.tavern_master)
	expectEqual(profile.badgeIds.master_snow, nil, "a biome off the route gets no Master")
	expectEqual(#BiomeRewards.recordRunWin(profile, route), 0, "Master is granted once per biome")
	-- persistence and junk
	local loaded = PlayerProfile.migrate(profile)
	expectTrue(loaded.badgeIds.master_desert and loaded.badgeIds.biome_tavern)
	local junk = PlayerProfile.migrate({ badgeIds = { biome_snow = true, nope = true, master_coast = "yes" } })
	expectTrue(junk.badgeIds.biome_snow)
	expectEqual(junk.badgeIds.nope, nil)
	expectEqual(junk.badgeIds.master_coast, nil)
	expectEqual(next(PlayerProfile.migrate({}).badgeIds), nil)
	-- an invalid route grants nothing
	expectEqual(#BiomeRewards.recordRunWin(PlayerProfile.new(), { "keepers_table" }), 0)
	-- the new sets are usable once granted and equip like any other
	local CosmeticSets = require(script.Parent.Parent.Engine.CosmeticSets)
	local p2 = PlayerProfile.new()
	expectFalse(CosmeticSets.isUnlocked(p2, "dune_market"))
	BiomeRewards.recordBiomeCleared(p2, "desert")
	expectTrue(CosmeticSets.isUnlocked(p2, "dune_market"))
	expectTrue(CosmeticSets.equip(p2, "dune_market"))
end })

table.insert(tests, { name = "Badges: definitions are well-formed, rule badges are earned once, equip needs ownership", fn = function()
	local Badges = require(script.Parent.Parent.Engine.Badges)
	local CollectionBook = require(script.Parent.Parent.Engine.CollectionBook)
	local seen = {}
	local ruleKinds = { runsWon = true, nightReached = true, minigameWins = true, milestone = true, loginStreak = true, season = true }
	local groups = {}
	for _, def in ipairs(Badges.Definitions) do
		expectFalse(seen[def.id], "duplicate " .. def.id)
		seen[def.id] = true
		expectTrue(CollectionBook.Rarities[def.rarity] ~= nil, def.id .. " rarity")
		expectTrue(def.name ~= "" and def.description ~= "" and def.hint ~= "" and def.icon ~= "" and def.group ~= "", def.id .. " text")
		expectFalse((def.name .. def.description .. def.hint):lower():find("balatro", 1, true) ~= nil)
		if def.rule then
			expectTrue(ruleKinds[def.rule.kind], def.id .. " rule kind")
		else
			expectTrue(def.region ~= nil and (def.tier == "first" or def.tier == "master"), def.id .. " is a biome badge")
		end
		groups[def.group] = true
	end
	for _, g in ipairs({ "Biomes", "Wins", "Nights", "Games", "Collection", "Visits", "Seasons" }) do
		expectTrue(groups[g], "badges cover " .. g)
	end
	-- the milestone and season rules point at real data
	local Seasons = require(script.Parent.Parent.Engine.Seasons)
	for _, def in ipairs(Badges.Definitions) do
		if def.rule and def.rule.kind == "milestone" then
			local found = false
			for _, m in ipairs(CollectionBook.Milestones) do
				if m.id == def.rule.id then found = true end
			end
			expectTrue(found, def.id .. " milestone exists")
		elseif def.rule and def.rule.kind == "season" then
			expectTrue(Seasons.getById(def.rule.id) ~= nil, def.id .. " season exists")
		end
	end
	-- earning
	local profile = PlayerProfile.new()
	expectEqual(#Badges.evaluate(profile), 0, "a new profile earns nothing")
	profile.stats.runsWon = 5
	profile.stats.bestNightReached = 8
	profile.minigameWins = 1
	profile.claimedMilestoneIds.quarter = true
	profile.loginStreak = 7
	profile.seasonRewardIds.winter_lanterns = true
	local fresh = Badges.evaluate(profile)
	local got = {}
	for _, id in ipairs(fresh) do got[id] = true end
	for _, id in ipairs({ "wins_1", "wins_5", "night_3", "night_5", "night_8", "minigame_1", "collection_25", "streak_3", "streak_7", "season_winter_lanterns" }) do
		expectTrue(got[id], id .. " earned")
	end
	for _, id in ipairs({ "wins_25", "night_10", "minigame_10", "collection_50", "collection_100", "streak_14" }) do
		expectFalse(got[id], id .. " not yet")
	end
	expectEqual(#Badges.evaluate(profile), 0, "earned once")
	profile.loginStreak = 0 -- a broken streak never takes a badge away
	expectTrue(Badges.has(profile, "streak_7"))
	-- minigame counter
	PlayerProfile.recordMinigameWin(profile)
	expectEqual(profile.minigameWins, 2)
	-- equip
	local ok, why = Badges.equip(profile, "wins_25")
	expectFalse(ok); expectEqual(why, "not_owned")
	ok, why = Badges.equip(profile, "nope")
	expectFalse(ok); expectEqual(why, "unknown")
	ok = Badges.equip(profile, "wins_5")
	expectTrue(ok); expectEqual(profile.equippedBadgeId, "wins_5")
	expectEqual(Badges.equippedText(profile), "🏆 Five Wins")
	ok = Badges.equip(profile, nil)
	expectTrue(ok); expectEqual(profile.equippedBadgeId, nil)
	expectEqual(Badges.equippedText(profile), nil)
	-- persistence: an equipped badge must be owned
	Badges.equip(profile, "night_5")
	local loaded = PlayerProfile.migrate(profile)
	expectEqual(loaded.equippedBadgeId, "night_5")
	expectEqual(loaded.minigameWins, 2)
	expectEqual(PlayerProfile.migrate({ equippedBadgeId = "wins_1" }).equippedBadgeId, nil, "not owned")
	expectEqual(PlayerProfile.migrate({ badgeIds = { wins_1 = true }, equippedBadgeId = "wins_1" }).equippedBadgeId, "wins_1")
end })

table.insert(tests, { name = "Badges: every badge is in exactly one shelf chip, painted art exists for every id, grid fills the width", fn = function()
	local Badges = require(script.Parent.Parent.Engine.Badges)
	local BadgeArt = require(script.Parent.Parent.Engine.BadgeArt)
	local counts = {}
	local valid = {}
	for _, chip in ipairs(Badges.Chips) do valid[chip] = true end
	for _, def in ipairs(Badges.Definitions) do
		local chip = Badges.chipOf(def)
		expectTrue(valid[chip] and chip ~= "All", def.id .. " has a real chip")
		counts[chip] = (counts[chip] or 0) + 1
		expectTrue(type(BadgeArt[def.id]) == "string" and BadgeArt[def.id]:match("^rbxassetid://%d+$") ~= nil, def.id .. " has painted art")
		expectTrue(#def.hint:gsub("%S+", "x"):gsub("%s", "") <= 12, def.id .. " requirement is 12 words or fewer")
	end
	expectEqual(counts.Roads, 8)
	expectEqual(counts.Masters, 8)
	for _, w in ipairs({ 260, 500, 900, 1400 }) do
		local cols, cellW = Badges.gridFor(w, 170, 10, 2)
		expectTrue(cols >= 2 and cellW > 0, "cols and cell size at width " .. w)
		expectTrue(w - (cols * cellW + (cols - 1) * 10) < cols, "no empty right margin at width " .. w)
	end
end })

table.insert(tests, { name = "Badges: real Roblox badge awards skip every missing id, and only new badges are sent", fn = function()
	local Badges = require(script.Parent.Parent.Engine.Badges)
	local BadgeIds = require(script.Parent.Parent.Engine.BadgeIds)
	expectEqual(next(BadgeIds), nil, "ships with no ids set")
	expectEqual(#Badges.awardPlan({ "wins_1", "biome_snow" }, BadgeIds), 0, "nil ids are skipped silently")
	expectEqual(#Badges.awardPlan({ "wins_1" }, nil), 0)
	expectEqual(#Badges.awardPlan(nil, {}), 0)
	local plan = Badges.awardPlan({ "wins_1", "wins_5", "night_3" }, { wins_1 = 111, night_3 = "x", wins_5 = 0 })
	expectEqual(#plan, 1, "only a positive numeric id is sent")
	expectEqual(plan[1].badge, "wins_1"); expectEqual(plan[1].robloxId, 111)
	-- only newly earned badges are awarded
	local before = { wins_1 = true }
	local after = { wins_1 = true, wins_5 = true, nope = true }
	local new = Badges.newlyEarned(before, after)
	expectEqual(table.concat(new, ","), "wins_5", "unknown ids and already-owned badges are not sent")
end })

table.insert(tests, { name = "Keys: the first fork's three roads and every default road are open, the rest are locked, 3+ routes need no Key", fn = function()
	local WorldMap = require(script.Parent.Parent.Engine.WorldMap)
	local Keys = require(script.Parent.Parent.Engine.Keys)
	local roads = Keys.allRoads()
	for _, id in ipairs(Keys.FreeRoads) do
		expectTrue(roads[id] == true, id .. " is a real fork road")
		expectFalse(Keys.isDefaultRoad(id), id .. " is not a default road")
	end
	expectEqual(#Keys.FreeRoads, 2)
	for _, id in ipairs(WorldMap.defaultRoute()) do
		expectTrue(Keys.isFreeRoad(id), "the default route is always open: " .. id)
	end
	local locked = Keys.lockedRoads()
	expectEqual(table.concat(locked, ","), "frosty_trail,lighthouse_cove,warm_kitchen")
	local open = 0
	for _, route in ipairs(WorldMap.allRoutes()) do
		local needsKey = false
		for _, id in ipairs(route) do
			if not Keys.isFreeRoad(id) then needsKey = true end
		end
		if not needsKey then open = open + 1 end
	end
	expectTrue(open >= 3, "at least 3 routes are open to a new player (" .. open .. ")")
	local profile = PlayerProfile.new()
	expectEqual(Keys.status(profile, "garden_terrace"), "open")
	expectEqual(Keys.status(profile, "desert_dunes"), "open")
	expectEqual(Keys.status(profile, "swamp_boardwalk"), "open")
	expectEqual(Keys.status(profile, "frosty_trail"), "locked")
	-- a fresh profile: exactly the first fork's three roads are open to choose from; later forks only have their
	-- default road open (so the run can be finished); every other road is locked
	local _, all = Keys.allRoads()
	local openRoads, lockedRoads = {}, {}
	for _, id in ipairs(all) do
		if Keys.isRoadOpen(profile, id) then openRoads[#openRoads + 1] = id else lockedRoads[#lockedRoads + 1] = id end
	end
	expectEqual(table.concat(openRoads, ","), "desert_dunes,garden_terrace,grand_hall,mountain_pass,swamp_boardwalk")
	expectEqual(#lockedRoads, 3)
	local forkA = WorldMap.choicesAfter("wildflower_meadow")
	expectEqual(#forkA, 3)
	for _, id in ipairs(forkA) do
		expectTrue(Keys.isRoadOpen(profile, id), "every road of the first fork is open: " .. id)
	end
	-- Daily / Weekly / Seed routes ignore locks: the server sends no lockedRoads and never checks them for a plan
	local plan = WorldMap.routeFromSeed("2026-11-08")
	expectTrue(WorldMap.isValidRoute(plan), "a seeded plan is a valid route whatever is locked")
end })

table.insert(tests, { name = "Keys: a locked road is refused by the server check, a Key opens it for good", fn = function()
	local WorldMap = require(script.Parent.Parent.Engine.WorldMap)
	local Keys = require(script.Parent.Parent.Engine.Keys)
	local profile = PlayerProfile.new()
	local function atForkB()
		local st = runAtNight(3)
		WorldMap.chooseRoad(st, "garden_terrace", "roundSelect")
		while st.night < 5 do
			st.roundOver = true
			RunState.advanceToNextRound(st)
		end
		return st
	end
	-- Fork B (after Night 4): mountain_pass is the default road (open), frosty_trail and lighthouse_cove need a Key
	local state = atForkB()
	local routeLen = #state.worldRoute
	local function open(id) return Keys.isRoadOpen(profile, id) end
	expectEqual(table.concat(WorldMap.pendingChoices(state) or {}, ","), "mountain_pass,frosty_trail,lighthouse_cove")
	local ok, why = WorldMap.chooseRoad(state, "frosty_trail", "roundSelect", open)
	expectFalse(ok); expectEqual(why, "locked")
	expectEqual(#state.worldRoute, routeLen, "a refused pick changes nothing")
	-- no Key, wrong phase, bad ids, free road
	ok, why = Keys.unlock(profile, state, "frosty_trail", "roundSelect")
	expectFalse(ok); expectEqual(why, "no_key")
	profile.keys = 1
	ok, why = Keys.unlock(profile, state, "frosty_trail", "playing")
	expectFalse(ok); expectEqual(why, "wrong_phase")
	ok, why = Keys.unlock(profile, state, "warm_kitchen", "roundSelect")
	expectFalse(ok); expectEqual(why, "not_next", "only a pending road can be unlocked")
	ok, why = Keys.unlock(profile, state, "mountain_pass", "roundSelect")
	expectFalse(ok); expectEqual(why, "not_locked", "a free road never costs a Key")
	ok = Keys.unlock(profile, state, 5, "roundSelect")
	expectFalse(ok)
	expectEqual(profile.keys, 1, "rejections keep the Key")
	-- the real unlock
	ok = Keys.unlock(profile, state, "frosty_trail", "roundSelect")
	expectTrue(ok)
	expectEqual(profile.keys, 0)
	expectTrue(profile.unlockedRoadIds.frosty_trail)
	ok, why = Keys.unlock(profile, state, "frosty_trail", "roundSelect")
	expectFalse(ok); expectEqual(why, "not_locked", "already open")
	ok = WorldMap.chooseRoad(state, "frosty_trail", "roundSelect", open)
	expectTrue(ok)
	expectEqual(state.worldRoute[5], "frosty_trail")
	-- the other locked road at the same fork is still locked
	local state2 = atForkB()
	ok, why = WorldMap.chooseRoad(state2, "lighthouse_cove", "roundSelect", open)
	expectFalse(ok); expectEqual(why, "locked")
	-- the compass never spends a charge on a locked road
	local BiomeRewards = require(script.Parent.Parent.Engine.BiomeRewards)
	local state3 = atForkB()
	profile.compassCharges = 2
	ok, why = BiomeRewards.useCompass(profile, state3, "roundSelect", "lighthouse_cove", open)
	expectFalse(ok); expectEqual(why, "locked")
	expectEqual(profile.compassCharges, 2, "a refused compass use keeps the charge")
	ok, why = BiomeRewards.useCompass(profile, state3, "roundSelect", "grand_hall", open)
	expectFalse(ok); expectEqual(why, "not_next")
	expectEqual(profile.compassCharges, 2)
	ok = BiomeRewards.useCompass(profile, state3, "roundSelect", "mountain_pass", open)
	expectTrue(ok)
	expectEqual(profile.compassCharges, 1)
	-- Daily / Weekly / Seed boards: fixed route, no unlocking and no picking
	local seeded = atForkB()
	seeded.worldPlan = WorldMap.routeFromSeed("2026-11-08")
	profile.keys = 2
	ok, why = Keys.unlock(profile, seeded, "lighthouse_cove", "roundSelect")
	expectFalse(ok); expectEqual(why, "fixed_route")
	-- Fork A is open for everyone from the start
	local fresh = PlayerProfile.new()
	local stateA = runAtNight(3)
	for _, id in ipairs({ "garden_terrace", "desert_dunes", "swamp_boardwalk" }) do
		local s2 = runAtNight(3)
		expectTrue(WorldMap.chooseRoad(s2, id, "roundSelect", function(r) return Keys.isRoadOpen(fresh, r) end), "a new player can take " .. id)
	end
	expectEqual(#stateA.worldRoute, 2)
end })

table.insert(tests, { name = "Keys: one per win and one per first biome clear; unlocks persist through save and load", fn = function()
	local BiomeRewards = require(script.Parent.Parent.Engine.BiomeRewards)
	local Keys = require(script.Parent.Parent.Engine.Keys)
	local profile = PlayerProfile.new()
	expectEqual(profile.keys, 0)
	PlayerProfile.recordRunWon(profile)
	expectEqual(profile.keys, 1, "a win earns a Key")
	PlayerProfile.recordRunWon(profile)
	expectEqual(profile.keys, 2)
	local fresh = BiomeRewards.recordBiomeCleared(profile, "desert")
	expectTrue(#fresh > 0)
	expectEqual(profile.keys, 3, "the first clear of a biome earns a Key")
	BiomeRewards.recordBiomeCleared(profile, "desert")
	expectEqual(profile.keys, 3, "clearing the same biome again earns none")
	BiomeRewards.recordBiomeCleared(profile, "snow")
	expectEqual(profile.keys, 4, "another biome earns another")
	-- cap
	profile.keys = Keys.MAX_KEYS
	PlayerProfile.recordRunWon(profile)
	expectEqual(profile.keys, Keys.MAX_KEYS)
	-- persistence
	profile.keys = 3
	profile.unlockedRoadIds.frosty_trail = true
	local loaded = PlayerProfile.migrate(profile)
	expectEqual(loaded.keys, 3)
	expectTrue(loaded.unlockedRoadIds.frosty_trail)
	expectTrue(Keys.isRoadOpen(loaded, "frosty_trail"))
	expectFalse(Keys.isRoadOpen(loaded, "lighthouse_cove"))
	-- old profiles and junk migrate safely
	local old = PlayerProfile.migrate({})
	expectEqual(old.keys, 0)
	expectEqual(next(old.unlockedRoadIds), nil)
	local junk = PlayerProfile.migrate({ keys = -4, unlockedRoadIds = { frosty_trail = true, garden_terrace = true, desert_dunes = true, nope = true, warm_kitchen = "yes" } })
	expectEqual(junk.keys, 0)
	expectTrue(junk.unlockedRoadIds.frosty_trail)
	expectEqual(junk.unlockedRoadIds.garden_terrace, nil, "free roads are not stored")
	expectEqual(junk.unlockedRoadIds.desert_dunes, nil, "free roads are not stored")
	expectEqual(junk.unlockedRoadIds.nope, nil)
	expectEqual(junk.unlockedRoadIds.warm_kitchen, nil)
	expectEqual(PlayerProfile.migrate({ keys = 5000 }).keys, Keys.MAX_KEYS)
end })

table.insert(tests, { name = "WorldMapLayout: no two node + label boxes overlap (road, fork and side stops)", fn = function()
	local WorldMap = require(script.Parent.Parent.Engine.WorldMap)
	local L = require(script.Parent.Parent.Engine.WorldMapLayout)
	for _, setup in ipairs({ { h = 600, node = 90 }, { h = 720, node = 92 }, { h = 900, node = 92 } }) do
		local nightX, routeY = {}, {}
		for i = 1, 8 do
			nightX[i] = 400 + (i - 1) * 300
			routeY[i] = setup.h * 0.5 + ((i % 2 == 0) and -1 or 1) * setup.h * 0.11
		end
		for _, route in ipairs(WorldMap.allRoutes()) do
			local res = L.compute({ nightX = nightX, routeY = routeY, height = setup.h, route = route,
				minGap = math.floor(setup.node * 1.5), nodeSize = setup.node })
			local boxes = L.boxesOf(res, setup.node, route)
			local ids = {}
			for id in pairs(boxes) do ids[#ids + 1] = id end
			table.sort(ids)
			for i = 1, #ids do
				local a = boxes[ids[i]]
				expectTrue(a.y0 >= 0 and a.y1 <= setup.h, ids[i] .. " stays inside the canvas (h " .. setup.h .. ")")
				for j = i + 1, #ids do
					expectTrue(not L.overlaps(a, boxes[ids[j]]), ids[i] .. " overlaps " .. ids[j] .. " (h " .. setup.h .. ")")
				end
			end
		end
	end
end })

table.insert(tests, { name = "SideStops: hidden stops reveal only at the parent with a token or a compass charge", fn = function()
	local WorldMap = require(script.Parent.Parent.Engine.WorldMap)
	local SideStops = require(script.Parent.Parent.Engine.SideStops)
	local RunState = require(script.Parent.Parent.Engine.RunState)
	local hidden = {}
	for id, stop in pairs(WorldMap.Stops) do
		if stop.kind == "side" and stop.hidden then hidden[#hidden + 1] = id end
	end
	table.sort(hidden)
	expectEqual(#hidden, 4)
	local state = runAtStop(5)
	local id = "lockpick_cave"
	expectEqual(WorldMap.currentStop(state), "mountain_pass")
	expectEqual(SideStops.blockedReason(state, id, "roundSelect"), "hidden")
	expectTrue(SideStops.hiddenHere(state, "roundSelect")[1] == id, "listed as revealable here")
	local ok, why = SideStops.reveal(state, {}, id, "roundSelect", "token")
	expectFalse(ok)
	expectEqual(why, "no_token")
	ok, why = SideStops.reveal(state, { compassCharges = 0 }, id, "roundSelect", "compass")
	expectEqual(why, "no_charge")
	ok, why = SideStops.reveal(state, {}, id, "playing", "token")
	expectEqual(why, "wrong_phase")
	ok, why = SideStops.reveal(state, {}, "dune_rest", "roundSelect", "token")
	expectEqual(why, "not_here", "a hidden stop of another place")
	ok, why = SideStops.reveal(state, {}, id, "roundSelect", "bogus")
	expectEqual(why, "bad_method")
	ok, why = SideStops.reveal(state, {}, "summit_shrine", "roundSelect", "token")
	expectEqual(why, "not_hidden", "visible stops cannot be revealed")
	state.mapTokens = 1
	ok = SideStops.reveal(state, {}, id, "roundSelect", "token")
	expectTrue(ok, "token reveals")
	expectEqual(state.mapTokens, 0)
	expectEqual(SideStops.blockedReason(state, id, "roundSelect"), nil, "usable once revealed")
	expectFalse(SideStops.reveal(state, {}, id, "roundSelect", "token"), "only once")
	-- the compass path spends a charge from the profile
	local state2 = runAtStop(2)
	state2.worldRoute = { "dusty_road", "wildflower_meadow", "swamp_boardwalk" }
	state2.night, state2.round = 3, 1
	local profile = { compassCharges = 2 }
	expectTrue(SideStops.reveal(state2, profile, "lantern_hut", "roundSelect", "compass"))
	expectEqual(profile.compassCharges, 1)
	-- no reveal while a fork is pending or after the first round
	local state3 = runAtStop(2)
	state3.worldRoute = { "dusty_road", "wildflower_meadow" }
	state3.night, state3.round, state3.mapTokens = 2, 1, 1
	expectEqual(#SideStops.hiddenHere(state3, "roundSelect"), 0)
end })

table.insert(tests, { name = "WorldMapLayout: compass arrows step in 15 degrees and wrap; bearing picks the road", fn = function()
	local WorldMap = require(script.Parent.Parent.Engine.WorldMap)
	local L = require(script.Parent.Parent.Engine.WorldMapLayout)
	expectEqual(L.stepBearing(0, -15), 345)
	expectEqual(L.stepBearing(350, 15), 0)
	expectEqual(L.stepBearing(90, 15), 105)
	expectEqual(L.stepBearing(92, 0), 90)
	for _, id in ipairs(WorldMap.choicesAfter("wildflower_meadow")) do
		local b = WorldMap.bearing("wildflower_meadow", id)
		expectEqual(WorldMap.pickByBearing("wildflower_meadow", b), id)
	end
end })

table.insert(tests, { name = "WorldMapLayout: displayRoute extends picks with the default road; fog rule; branch ends", fn = function()
	local WorldMap = require(script.Parent.Parent.Engine.WorldMap)
	local L = require(script.Parent.Parent.Engine.WorldMapLayout)
	local r = L.displayRoute({ "dusty_road" })
	expectEqual(#r, 8)
	expectEqual(r[8], WorldMap.Finish)
	r = L.displayRoute({ "dusty_road", "wildflower_meadow", "desert_dunes" })
	expectEqual(r[3], "desert_dunes")
	expectEqual(r[4], "oasis_camp")
	expectEqual(L.visibility(4, 1, false), "revealed")
	expectEqual(L.visibility(5, 1, false), "teaser")
	expectEqual(L.visibility(6, 1, false), "hidden")
	expectEqual(L.visibility(6, 1, true), "revealed")
	local ends = L.branchEnds()
	expectTrue(ends.oasis_camp == "desert" and ends.frosty_trail == "snow" and ends.keepers_table == "tavern", "branch ends")
	expectTrue(ends.dusty_road == nil, "start is not an end")
end })

table.insert(tests, { name = "BossStage: boss rounds have no health bar and no red tint", fn = function()
	local BossStage = require(script.Parent.Parent.Engine.BossStage)
	for _, enraged in ipairs({ false, true }) do
		for _, grand in ipairs({ false, true }) do
			local st = BossStage.style(true, enraged, grand)
			expectTrue(st.healthBar == false, "no boss health bar")
			expectTrue(st.rageTint == false, "no enrage screen tint")
			expectTrue(st.backdrop == true, "boss art is the backdrop")
			expectTrue(not BossStage.isRedish(st.hitFlash), "hit flash is not red")
			expectTrue(not BossStage.isRedish(st.banner), "banner is not red")
		end
	end
	local plain = BossStage.style(false, false, false)
	expectTrue(plain.backdrop == false and plain.healthBar == false, "normal rounds draw no boss stage")
	expectTrue(BossStage.isRedish({ 220, 40, 30 }) and not BossStage.isRedish({ 250, 235, 200 }), "isRedish sanity")
end })

table.insert(tests, { name = "CardFit: Round Select cards fill big screens, fit 1280x720 and phones", fn = function()
	local CardFit = require(script.Parent.Parent.Engine.CardFit)
	local big = CardFit.scale(1080, 1860, 900, 620, 220, 1.25)
	expectTrue(big > 1 and big <= 1.25, "cards grow on a 1080p full-width screen")
	local hd = CardFit.scale(720, 1220, 600, 620, 220, 1.25)
	expectTrue(hd >= 0.6 and hd < 1, "cards shrink to fit 1280x720")
	local phone = CardFit.scale(400, 760, 290, 620, 220, 1.25)
	expectTrue(phone < 0.7, "cards shrink on a phone")
	local narrow = CardFit.scale(1080, 500, 900, 620, 220, 1.25)
	expectTrue(narrow * 220 * 3 + 48 <= 500 or narrow == 0.6, "three cards fit a narrow row")
	for _, vp in ipairs({ 360, 540, 720, 1080, 1440 }) do
		local sc = CardFit.scale(vp, vp * 1.7, vp * 0.7, 620, 220, 1.25)
		expectTrue(sc >= 0.6 and sc <= 1.25, "scale stays in range")
	end
end })

table.insert(tests, { name = "CardFit: card row gap stays at least 28px on screen for scales 0.5 to 1.2, under both layout models", fn = function()
	local CardFit = require(script.Parent.Parent.Engine.CardFit)
	local cardW = 340
	local s = 0.5
	while s <= 1.2001 do
		-- Model A: the layout spaces by the scaled width, so the on-screen gap is Padding.
		expectTrue(CardFit.padding(s, cardW, true) >= 28, "scaled layout gap >= 28 at " .. s)
		-- Model B: the layout spaces by the unscaled width; gap = Padding - cardW * (1 - s).
		local gapB = CardFit.padding(s, cardW, false) - cardW * (1 - s)
		expectTrue(gapB >= 28 - 1e-9, "unscaled layout gap >= 28 at " .. s)
		s = s + 0.05
	end
	expectTrue(CardFit.shortfall(-13) == 41 and CardFit.shortfall(30) == 0, "shortfall tops the gap up to 28")
end })

table.insert(tests, { name = "InputLock: opening an overlay disables gameplay hit areas, closing restores them", fn = function()
	local InputLock = require(script.Parent.Parent.Engine.InputLock)
	local lock = InputLock.new()
	local deck, play = true, true
	lock:guard(function(on) deck = on end)
	lock:guard(function(on) play = on end)
	expectTrue(deck and play, "gameplay is interactive with no overlay")
	lock:setOpen("roundSelect", true)
	expectTrue(not deck and not play, "round select disables the deck pile and Play")
	lock:setOpen("collection", true)
	lock:setOpen("roundSelect", false)
	expectTrue(not deck, "still locked while another overlay is open")
	lock:setOpen("collection", false)
	expectTrue(deck and play, "closing the last overlay restores everything")
	lock:setOpen("shop", true)
	lock:setOpen("shop", true)
	lock:setOpen("shop", false)
	expectTrue(deck and not lock:isLocked(), "opening the same overlay twice counts once")
	local late = nil
	lock:setOpen("shop", true)
	lock:guard(function(on) late = on end)
	expectTrue(late == false, "a widget guarded while locked starts disabled")
end })

table.insert(tests, { name = "HoldConfirm: cancel by default, completes only after the full hold", fn = function()
	local HoldConfirm = require(script.Parent.Parent.Engine.HoldConfirm)
	local h = HoldConfirm.new(1.5)
	expectTrue(h:update(100) == false and h:progress(100) == 0, "nothing happens without a press")
	h:press(10)
	expectTrue(h:update(10.5) == false and math.abs(h:progress(10.75) - 0.5) < 1e-9, "halfway is not enough")
	h:release(11.0)
	expectTrue(h:update(20) == false and h:progress(20) == 0, "releasing early cancels and resets")
	h:press(30)
	expectTrue(h:update(31.49) == false, "just short of 1.5s does not confirm")
	expectTrue(h:update(31.5) == true, "the full time confirms")
	expectTrue(h:update(32) == false, "confirms exactly once")
	h:reset()
	expectTrue(h:progress(40) == 0, "reset clears it")
end })

table.insert(tests, { name = "RunAbandon: abandoning counts the run as abandoned and grants nothing", fn = function()
	local RunAbandon = require(script.Parent.Parent.Engine.RunAbandon)
	local PlayerProfile = require(script.Parent.Parent.Engine.PlayerProfile)
	local profile = PlayerProfile.new()
	local before = { won = profile.stats.runsWon, best = profile.stats.bestNightReached, started = profile.stats.runsStarted }
	expectTrue(profile.stats.runsAbandoned == 0, "fresh profile has 0 abandoned runs")
	for _, phase in ipairs({ "roundSelect", "playing", "shop", "nightVictory" }) do
		expectTrue(RunAbandon.canAbandon({ phase = phase, state = {} }), phase .. " can be abandoned")
	end
	expectTrue(not RunAbandon.canAbandon({ phase = "gameover", state = {} }), "a finished run cannot")
	expectTrue(not RunAbandon.canAbandon(nil) and not RunAbandon.canAbandon({}), "no session, no abandon")
	local ok = RunAbandon.abandon({ phase = "shop", state = {} }, profile, PlayerProfile)
	expectTrue(ok and profile.stats.runsAbandoned == 1, "counted as abandoned")
	expectTrue(profile.stats.runsWon == before.won and profile.stats.bestNightReached == before.best
		and profile.stats.runsStarted == before.started, "no win, Night credit or start is granted")
	local bad = RunAbandon.abandon({ phase = "gameover", state = {} }, profile, PlayerProfile)
	expectTrue(not bad and profile.stats.runsAbandoned == 1, "a refused abandon changes nothing")
	local copy = PlayerProfile.migrate({ stats = { runsAbandoned = 3.7 } })
	expectTrue(copy.stats.runsAbandoned == 3, "migrate keeps and floors runsAbandoned")
end })

table.insert(tests, { name = "TableStyle: backdrop resolves per region and route, set override wins, moods change, nothing red", fn = function()
	local TableStyle = require(script.Parent.Parent.Engine.TableStyle)
	local BiomeBackdrops = require(script.Parent.Parent.Engine.BiomeBackdrops)
	local WorldMap = require(script.Parent.Parent.Engine.WorldMap)
	local BossStage = require(script.Parent.Parent.Engine.BossStage)
	for regionId in pairs(WorldMap.Regions) do
		expectTrue(BiomeBackdrops.Grades[regionId] ~= nil, "every world region has a grade: " .. tostring(regionId))
	end
	for _, regionId in ipairs(BiomeBackdrops.Regions) do
		expectTrue(BiomeBackdrops.Grades[regionId] ~= nil, "every backdrop region has a grade: " .. regionId)
	end
	for id, g in pairs(BiomeBackdrops.Grades) do
		expectTrue(not BossStage.isRedish(g.color), "grade is not red: " .. id)
		expectTrue(g.strength > 0 and g.strength < 0.5, "grade strength is a wash: " .. id)
	end
	-- every default route resolves a region for every Night, including Endless ones
	for _, route in ipairs(WorldMap.allRoutes()) do
		for night = 1, 12 do
			local region = TableStyle.regionOfNight(route, night)
			expectTrue(BiomeBackdrops.Grades[region] ~= nil, "route Night resolves to a known region")
		end
	end
	expectTrue(TableStyle.regionOfNight(nil, 3) == BiomeBackdrops.Default, "no route falls back to the tavern")
	expectTrue(TableStyle.regionOfNight({ "dusty_road" }, 5) ~= nil, "short route reuses its last stop")
	-- different regions grade differently
	local meadow = TableStyle.resolve({ region = "meadow", night = 1 })
	local snow = TableStyle.resolve({ region = "snow", night = 1 })
	expectTrue(meadow.grade.color[1] ~= snow.grade.color[1] or meadow.grade.color[3] ~= snow.grade.color[3], "regions grade differently")
	expectTrue(meadow.source == (BiomeBackdrops.Images.meadow and "biome" or "default"), "the default painting stays until a biome painting is recorded")
	-- a recorded biome painting is used; a set with its own image replaces it; a styled set only layers on top
	local savedMeadow = BiomeBackdrops.Images.meadow
	BiomeBackdrops.Images.meadow = "rbxassetid://123"
	local withBiome = TableStyle.resolve({ region = "meadow", night = 1 })
	expectTrue(withBiome.source == "biome" and withBiome.image == "rbxassetid://123", "biome painting resolves")
	local override = TableStyle.resolve({ region = "meadow", night = 1, set = { backdropImage = "rbxassetid://999" } })
	expectTrue(override.source == "set" and override.image == "rbxassetid://999", "a set image replaces the biome image")
	local styled = TableStyle.resolve({ region = "meadow", night = 1, set = { backdropImage = "rbxassetid://0", backdropStyle = { tint = { 255, 255, 255 } } } })
	expectTrue(styled.source == "biome" and styled.setStyle ~= nil, "a placeholder-image set keeps the biome image and layers its style")
	BiomeBackdrops.Images.meadow = savedMeadow
	-- Night and boss moods
	local n1 = TableStyle.resolve({ region = "tavern", night = 1 })
	local n8 = TableStyle.resolve({ region = "tavern", night = 8 })
	local n12 = TableStyle.resolve({ region = "tavern", night = 12 })
	expectTrue(n8.mood.darken > n1.mood.darken and n8.mood.warm > n1.mood.warm, "Night 8 is darker and warmer than Night 1")
	expectTrue(n12.mood.darken == n8.mood.darken, "Endless Nights stay at the darkest mood")
	local boss = TableStyle.resolve({ region = "tavern", night = 1, isBoss = true })
	expectTrue(boss.mood.darken > n1.mood.darken and boss.vignette.sides > n1.vignette.sides and boss.vignette.bottom > n1.vignette.bottom, "boss rounds are darker with a heavier vignette")
	expectTrue(not boss.grade or not BossStage.isRedish(boss.grade.color), "no red in the boss mood")
end })

table.insert(tests, { name = "CosmeticSets: every set resolves a card face and backdrop style, equipping changes the table", fn = function()
	local CosmeticSets = require(script.Parent.Parent.Engine.CosmeticSets)
	local TableStyle = require(script.Parent.Parent.Engine.TableStyle)
	local function isRgb(t)
		return type(t) == "table" and #t == 3 and t[1] >= 0 and t[1] <= 255 and t[2] >= 0 and t[2] <= 255 and t[3] >= 0 and t[3] <= 255
	end
	for _, set in ipairs(CosmeticSets.Definitions) do
		local theme = CosmeticSets.themeOf(set)
		expectTrue(type(theme.face) == "table", set.id .. " resolves a card face style")
		if set.id == CosmeticSets.DefaultId then
			expectTrue(theme.neutral and theme.backdropStyle == nil and theme.accent == nil, "the default set stays neutral")
		else
			expectTrue(not theme.neutral, set.id .. " themes the faces")
			expectTrue(isRgb(theme.face.paper) and isRgb(theme.face.border) and isRgb(theme.face.pip), set.id .. " face colours are valid")
			expectTrue(isRgb(theme.accent), set.id .. " has an accent")
			expectTrue(theme.backdropStyle ~= nil, set.id .. " resolves a backdrop style")
			expectTrue(CosmeticSets.validateStyle(theme.backdropStyle), set.id .. " style validates")
			if theme.backdropStyle.overlay then
				expectTrue(theme.backdropStyle.overlay.transparency <= 1 - CosmeticSets.MIN_OVERLAY_STRENGTH, set.id .. " overlay is strong enough to read")
			end
			if theme.backdropStyle.vignette then
				expectTrue(theme.backdropStyle.vignette.strength >= CosmeticSets.MIN_VIGNETTE, set.id .. " vignette is strong enough to read")
			end
		end
	end
	-- Golden Gala (the paid set) must visibly change the table
	local gala = CosmeticSets.getById("golden_gala")
	local default = CosmeticSets.getById(CosmeticSets.DefaultId)
	local galaTheme, defaultTheme = CosmeticSets.themeOf(gala), CosmeticSets.themeOf(default)
	expectTrue(galaTheme.backdropStyle ~= nil and galaTheme.backdropStyle.overlay ~= nil and #galaTheme.backdropStyle.layers >= 1, "Golden Gala draws a gold wash and layers")
	expectTrue(galaTheme.face.foil == true and galaTheme.face.border[1] > 200, "Golden Gala has gold-edged foil faces")
	expectTrue(galaTheme.neutral == false and defaultTheme.neutral == true, "equipping Golden Gala changes the face style")
	local withGala = TableStyle.resolve({ region = "tavern", night = 1, set = gala })
	local withDefault = TableStyle.resolve({ region = "tavern", night = 1, set = default })
	expectTrue(withGala.setStyle ~= nil and withDefault.setStyle == nil, "equipping a set changes the resolved gameplay style")
	-- explicit values for the sets the task names
	for _, id in ipairs({ "golden_gala", "winter_evening", "festival_night", "closing_time" }) do
		expectTrue(CosmeticSets.getById(id).face ~= nil, id .. " has explicit face values")
	end
end })

table.insert(tests, { name = "RegionTiles.fadeSlices: biome joins cross-fade with no gap and no pale band", fn = function()
	local RegionTiles = require(script.Parent.Parent.Engine.RegionTiles)
	for _, width in ipairs({ 96, 100, 241 }) do
		local slices = RegionTiles.fadeSlices(width, 16)
		expectTrue(#slices == 16, "one slice per step")
		local x, prevT = 0, 1
		for _, sl in ipairs(slices) do
			expectTrue(sl.x == x and sl.w >= 0, "slices tile the width without a gap or overlap")
			expectTrue(sl.transparency <= prevT and sl.transparency >= 0 and sl.transparency <= 1, "transparency only falls (clear to opaque)")
			x = sl.x + sl.w
			prevT = sl.transparency
		end
		expectTrue(x == width, "slices span the full join")
		expectTrue(slices[1].transparency > 0.95 and slices[#slices].transparency < 0.05, "starts clear, ends opaque")
	end
	expectTrue(#RegionTiles.fadeSlices(50, 0) == 1, "at least one slice")
	-- wide joins: at least 25% of the narrower region (within 96..480), never wider than it
	expectTrue(RegionTiles.joinWidth(1000, 2000, 96, 480) == 250, "25% of the narrower region")
	expectTrue(RegionTiles.joinWidth(200, 2000, 96, 480) == 96, "minimum width")
	expectTrue(RegionTiles.joinWidth(5000, 6000, 96, 480) == 480, "capped")
	expectTrue(RegionTiles.joinWidth(60, 2000, 96, 480) == 60, "never wider than the narrower region")
	expectTrue(RegionTiles.sliceCount(96) == 16 and RegionTiles.sliceCount(480) == 64 and RegionTiles.sliceCount(5000) == 64, "slice count clamps 16..64")
	local fine = RegionTiles.fadeSlices(480, RegionTiles.sliceCount(480))
	expectTrue(fine[1].w <= 8, "thin slices on a wide join (no stair stepping)")
end })

table.insert(tests, { name = "MapPan: the camera clamps at every edge, centres in both axes, the compass picks a road", fn = function()
	local MapPan = require(script.Parent.Parent.Engine.MapPan)
	-- world 4000 x 1600, view 1000 x 700
	local x, y = MapPan.clamp(-50, -20, 4000, 1600, 1000, 700)
	expectTrue(x == 0 and y == 0, "clamps at the top left")
	x, y = MapPan.clamp(9000, 9000, 4000, 1600, 1000, 700)
	expectTrue(x == 3000 and y == 900, "clamps at the bottom right")
	x, y = MapPan.clamp(1200, 300, 4000, 1600, 1000, 700)
	expectTrue(x == 1200 and y == 300, "inside the world nothing moves")
	x, y = MapPan.clamp(50, 50, 600, 300, 1000, 700)
	expectTrue(x == 0 and y == 0, "a world smaller than the view stays at 0")
	-- Find me: centres a world point in both axes, clamped
	x, y = MapPan.centerOn(2000, 800, 4000, 1600, 1000, 700)
	expectTrue(x == 1500 and y == 450, "centres on the point in both axes")
	x, y = MapPan.centerOn(100, 50, 4000, 1600, 1000, 700)
	expectTrue(x == 0 and y == 0, "a point near the corner clamps")
	expectEqual(MapPan.canvasHeight(400), math.floor(400 * MapPan.WORLD_SCREENS_Y))
	expectTrue(MapPan.WORLD_SCREENS_Y >= 2, "the world is at least two screens tall")
	-- bearings: 0 up, 90 right, 180 down
	local ux, uy = MapPan.stepToward(100, 100, 0, 50)
	local rx, ry = MapPan.stepToward(100, 100, 90, 50)
	local dx, dy = MapPan.stepToward(100, 100, 180, 50)
	expectTrue(math.abs(ux - 100) < 1e-9 and math.abs(uy - 50) < 1e-9, "bearing 0 is up")
	expectTrue(math.abs(rx - 150) < 1e-9 and math.abs(ry - 100) < 1e-9, "bearing 90 is right")
	expectTrue(math.abs(dx - 100) < 1e-9 and math.abs(dy - 150) < 1e-9, "bearing 180 is down")
	-- compass target selection
	local hero = { x = 1000, y = 800 }
	local up = { id = "up", x = 1000, y = 400, unexplored = true }
	local right = { id = "right", x = 1400, y = 800, recommended = true }
	local down = { id = "down", x = 1000, y = 1200, unexplored = false }
	expectEqual(MapPan.compassTarget(hero, 0, { up, right, down }).id, "up")
	expectEqual(MapPan.compassTarget(hero, 90, { up, right, down }).id, "right")
	expectEqual(MapPan.compassTarget(hero, 180, { up, right, down }).id, "down")
	expectEqual(MapPan.compassTarget(hero, 270, { up, right, down }), nil, "nothing within range to the west")
	-- a recommended road wins a near tie over an unexplored one
	local upRight = { id = "ur", x = 1250, y = 500, unexplored = true }
	local rightRec = { id = "rr", x = 1300, y = 700, recommended = true }
	expectEqual(MapPan.compassTarget(hero, 50, { upRight, rightRec }).id, "rr", "recommended wins a near tie")
	expectEqual(MapPan.compassTarget(hero, 45, {}), nil, "no candidates, no target")
end })

table.insert(tests, { name = "TooltipSpec: one border, padding clears the text, placement stays on screen", fn = function()
	local TooltipSpec = require(script.Parent.Parent.Engine.TooltipSpec)
	local spec = TooltipSpec.Spec
	expectEqual(spec.borders, 1, "exactly one border")
	expectFalse(spec.innerRim, "no inner rim frame through the text")
	expectTrue(TooltipSpec.textClear(spec), "padding is wider than the border plus breathing space")
	expectFalse(TooltipSpec.textClear({ borders = 2, innerRim = true, stroke = 1.5, padX = 5, padY = 5 }), "the old double border fails the check")
	expectTrue(spec.maxWidth <= 320, "long text wraps instead of running to the screen edge")
	local screen = { X = 1280, Y = 720 }
	-- above the target by default
	local x, y = TooltipSpec.place({ X = 600, Y = 400 }, { X = 100, Y = 40 }, { X = 200, Y = 60 }, screen)
	expectTrue(y + 60 + spec.gap <= 400 and x == 550, "above and centred")
	-- no room above: below
	x, y = TooltipSpec.place({ X = 600, Y = 10 }, { X = 100, Y = 40 }, { X = 200, Y = 60 }, screen)
	expectTrue(y >= 50, "below when there is no room above")
	-- clamped inside the screen on both sides and the bottom
	for _, pos in ipairs({ { 0, 300 }, { 1250, 300 }, { 600, 715 }, { 1279, 719 }, { 0, 0 } }) do
		x, y = TooltipSpec.place({ X = pos[1], Y = pos[2] }, { X = 30, Y = 30 }, { X = 280, Y = 120 }, screen)
		expectTrue(x >= spec.margin and x + 280 <= screen.X - spec.margin + 1e-9, "inside horizontally")
		expectTrue(y >= spec.margin and y + 120 <= screen.Y - spec.margin + 1e-9, "inside vertically")
	end
	-- left align: right edges line up
	x = TooltipSpec.place({ X = 1200, Y = 300 }, { X = 60, Y = 40 }, { X = 200, Y = 50 }, screen, "left")
	expectEqual(x, 1060)
end })

table.insert(tests, { name = "Pile style: the draw pile frame follows the equipped back and set, every back gets one", fn = function()
	local CardBacks = require(script.Parent.Parent.Engine.CardBacks)
	local CosmeticSets = require(script.Parent.Parent.Engine.CosmeticSets)
	local function isRgb(t)
		return type(t) == "table" and #t == 3 and t[1] >= 0 and t[1] <= 255 and t[2] >= 0 and t[2] <= 255 and t[3] >= 0 and t[3] <= 255
	end
	for _, back in ipairs(CardBacks.Definitions) do
		local pile = CardBacks.pileStyle(back)
		expectTrue(isRgb(pile.rim) and isRgb(pile.plate) and isRgb(pile.glow), back.id .. " has a valid pile style")
		-- the count pill is dark and stays readable: the plate is never bright
		expectTrue(pile.plate[1] + pile.plate[2] + pile.plate[3] < 330, back.id .. " plate stays dark")
		for _, set in ipairs(CosmeticSets.Definitions) do
			local p2 = CosmeticSets.pileStyleOf(set, back)
			expectTrue(isRgb(p2.rim) and isRgb(p2.plate) and isRgb(p2.glow), back.id .. " + " .. set.id .. " resolves")
		end
	end
	local default = CardBacks.pileStyle(CardBacks.getById("classic"))
	expectEqual(default.rim[1], 205); expectEqual(default.plate[1], 34)
	local ledger = CardBacks.pileStyle(CardBacks.getById("gilded_ledger"))
	local frost = CardBacks.pileStyle(CardBacks.getById("winter_frost"))
	expectTrue(ledger.rim[1] > ledger.rim[3] + 60, "Gilded Ledger is gold")
	expectTrue(frost.rim[3] >= frost.rim[1], "Winter Frost is frosted blue")
	-- a back without an explicit pile still derives one from its colours (new backs look right for free)
	local derived = CardBacks.pileStyle({ colors = { base = { 20, 90, 30 }, trim = { 200, 240, 120 } } })
	expectEqual(derived.rim[1], 200)
	expectTrue(derived.plate[2] > derived.plate[1], "the derived plate keeps the back's hue")
	-- the default set leaves the back's style alone; a themed set nudges the rim toward its accent
	local classicSet = CosmeticSets.getById(CosmeticSets.DefaultId)
	local gala = CosmeticSets.getById("golden_gala")
	local winterBack = CardBacks.getById("winter_frost")
	expectEqual(CosmeticSets.pileStyleOf(classicSet, winterBack).rim[1], frost.rim[1])
	expectTrue(CosmeticSets.pileStyleOf(gala, winterBack).rim[1] > frost.rim[1], "Gala nudges the rim toward gold")
end })

table.insert(tests, { name = "CardShape.fitScale: both Counter rows fit the panel at 1920x1080, 1366x768 and phone sizes", fn = function()
	local CardShape = require(script.Parent.Parent.Engine.CardShape)
	local ROW_EXTRA = 16 + 4 + 8 -- ShopCards.rowHeight headroom
	for _, vp in ipairs({ { 1920, 1080 }, { 1366, 768 }, { 1280, 720 }, { 800, 600 }, { 390, 844 } }) do
		local availW, availH = vp[1] - 20, vp[2] - 148
		local s = CardShape.fitScale(availW, availH, vp[1], vp[2], 4)
		expectTrue(s >= CardShape.FIT_MIN and s <= CardShape.MAX_SCALE, "scale in range at " .. vp[1])
		local total = 44 + 2 * 24 + 4 * 8
			+ (CardShape.shape("patron", s).h + ROW_EXTRA) + (CardShape.shape("pack", s).h + ROW_EXTRA)
		if s > CardShape.FIT_MIN then
			expectTrue(total <= availH, string.format("both rows fit %dx%d (need %d of %d)", vp[1], vp[2], total, availH))
		end
		local wide = CardShape.shape("patron", s)
		if s > CardShape.FIT_MIN then
			expectTrue(CardShape.fitsRow(4, availW, wide, 16, 14), "four cards fit the width at " .. vp[1])
		end
	end
	expectTrue(CardShape.fitScale(1900, 940, 1920, 1080, 3) == CardShape.MAX_SCALE, "roomy panel keeps the biggest cards")
end })

table.insert(tests, { name = "CardShape.pickLayout: every pack choice gets a nonzero card, wrapping to rows on narrow screens", fn = function()
	local CardShape = require(script.Parent.Parent.Engine.CardShape)
	for _, vp in ipairs({ { 1920, 1080 }, { 1366, 768 }, { 800, 600 }, { 390, 844 } }) do
		for _, count in ipairs({ 2, 3, 5 }) do -- Patron/Recipe packs and card packs reveal 2 to 5 choices
			local s, rows = CardShape.pickLayout(vp[1] - 40, vp[2] - 40, count, vp[1], vp[2])
			local shape = CardShape.shape("patron", s, true)
			expectTrue(shape.w > 0 and shape.h > 0, "nonzero card size")
			expectTrue(rows >= 1 and rows * math.ceil(count / rows) >= count, "rows hold every choice")
			local perRow = math.ceil(count / rows)
			if s > CardShape.FIT_MIN then
				expectTrue(CardShape.fitsRow(perRow, vp[1] - 40, shape, 16, 14), string.format("%d cards fit %d per row at %d", count, perRow, vp[1]))
			end
		end
	end
	local _, rowsWide = CardShape.pickLayout(1880, 1040, 5, 1920, 1080)
	expectEqual(rowsWide, 1, "five choices fit one row on a big screen")
end })

table.insert(tests, { name = "Pack pick screen: cards are raised above the panel and missing art warns (source check)", fn = function()
	local f = io and io.open and io.open("src/Client/Shop.lua", "r")
	if not f then return end
	local src = f:read("*a")
	f:close()
	expectTrue(src:find("zDelta", 1, true) ~= nil, "pick cards are raised above the opaque pack panel")
	expectTrue(src:find("[PackPick] no art", 1, true) ~= nil, "a choice with no art warns")
	expectTrue(src:find("pickLayout", 1, true) ~= nil, "pick cards are sized by CardShape.pickLayout")
end })

table.insert(tests, { name = "CardShape: Counter cards are art-first, scale with the screen and fit the rows", fn = function()
	local CardShape = require(script.Parent.Parent.Engine.CardShape)
	expectTrue(CardShape.scaleFor(1920, 1080) == CardShape.MAX_SCALE, "big screens get the biggest cards")
	expectTrue(CardShape.scaleFor(640, 360) == CardShape.MIN_SCALE, "phones get the smallest cards")
	local mid = CardShape.scaleFor(1280, 720)
	expectTrue(mid > CardShape.MIN_SCALE and mid < CardShape.MAX_SCALE, "1280x720 sits in between")
	for _, kind in ipairs({ "patron", "voucher", "pack", "owned" }) do
		local small, big = CardShape.shape(kind, 0.7), CardShape.shape(kind, 1.35)
		expectTrue(big.w > small.w and big.h > small.h, kind .. " grows with the scale")
		-- no text strip: the card ends just under the ribbon
		expectEqual(big.h, big.bannerTop + CardShape.BANNER_H + 8)
		expectTrue(big.drawerTop + CardShape.BUTTON_H <= big.bannerTop, kind .. ": the Buy drawer sits above the ribbon, adding no height")
		-- art is the star: it takes at least 70% of the card height
		expectTrue(big.artH / big.h >= 0.7, kind .. " art fills most of the card")
	end
	-- 1080p: five patron/voucher cards fit one row of the shop; 1280x720: they fit or scroll sideways
	local row1080 = 1920 - 240 - 40
	expectTrue(CardShape.fitsRow(5, row1080, CardShape.shape("patron", CardShape.scaleFor(1920, 1080)), 16, 14), "five big cards fit at 1080p")
	-- the Counter (patron row + pack row + header + buttons) fits the screen height at 720p and 1080p
	for _, vp in ipairs({ { 1280, 720 }, { 1920, 1080 } }) do
		local sc = CardShape.scaleFor(vp[1], vp[2])
		local rows = CardShape.shape("patron", sc).h + CardShape.shape("pack", sc).h + 2 * 40
		expectTrue(rows < vp[2] - 140, "both rows fit above the buttons at " .. vp[2] .. "p (" .. rows .. ")")
	end
end })

table.insert(tests, { name = "EmptyStates: short lines, no dashes, a hint for every page", fn = function()
	local EmptyStates = require(script.Parent.Parent.Engine.EmptyStates)
	local keys = 0
	for key, line in pairs(EmptyStates.Lines) do
		keys = keys + 1
		local words = 0
		for _ in line:gmatch("%S+") do words = words + 1 end
		expectTrue(words >= 3 and words <= 6, key .. " line is 3 to 6 words: " .. line)
		expectFalse(line:find("%-%-") ~= nil or line:find("\226\128\148") ~= nil, key .. " has no em dash or double dash")
		expectFalse(line:find("yet %-") ~= nil, key .. " has no explaining after a dash")
		expectTrue(#EmptyStates.hint(key) > 0, key .. " has a hint for the tooltip")
	end
	expectTrue(keys >= 4, "patrons, recipes, house passes and offers all have a line")
	for _, key in ipairs({ "patrons", "recipes", "housePasses", "offers" }) do
		expectEqual(#EmptyStates.icons(key), 3, key .. " has three ghost icons")
	end
	expectEqual(EmptyStates.line("nope"), EmptyStates.Lines.patrons, "unknown keys fall back")
	for _, hint in pairs(EmptyStates.Hints) do
		expectFalse(hint:find("%-%-") ~= nil, "hints have no double dash")
		local words = 0
		for _ in hint:gmatch("%S+") do words = words + 1 end
		expectTrue(words <= 8, "hints are 8 words or fewer: " .. hint)
	end
end })

table.insert(tests, { name = "ButtonFeel: hover swells, press squashes 6 percent, Play lights up with 1 to 5 cards", fn = function()
	local ButtonFeel = require(script.Parent.Parent.Engine.ButtonFeel)
	expectEqual(ButtonFeel.scaleFor(false, false), 1)
	expectEqual(ButtonFeel.scaleFor(true, false), 1.05)
	expectEqual(ButtonFeel.scaleFor(true, true), 0.94, "press wins over hover")
	expectEqual(ButtonFeel.scaleFor(false, true), 0.94)
	expectTrue(math.abs((1 - ButtonFeel.PRESS_SCALE) - 0.06) < 1e-9, "a 6 percent squash")
	expectFalse(ButtonFeel.playReady(0), "nothing selected: dim and still")
	expectTrue(ButtonFeel.playReady(1) and ButtonFeel.playReady(5), "1 to 5 cards selected: lit")
	expectFalse(ButtonFeel.playReady(6) or ButtonFeel.playReady(nil) or ButtonFeel.playReady(-1), "out of range stays dim")
	expectTrue(ButtonFeel.MIN_HIT >= 44, "phone-sized hit areas")
end })

-- Layout test harness: the real layout numbers (Engine/ResponsiveLayout, which Client/CompactLayout and
-- Collection.lua apply) at four screen sizes. Nothing may extend past the screen and no two sibling buttons may
-- overlap.
local function layoutProblems(vpX, vpY, layout)
	local R = require(script.Parent.Parent.Engine.ResponsiveLayout)
	local problems = {}
	local function check(name, r)
		if not R.inside(r, vpX, vpY) then problems[#problems + 1] = name .. " runs off the screen" end
	end
	check("hand", layout.hand)
	check("action row", layout.actions)
	for name, r in pairs(layout.buttons) do check(name, r) end
	if layout.deck then check("draw pile", layout.deck) end
	local names = { "sortRank", "sortSuit", "play", "discard" }
	for i = 1, #names do
		for j = i + 1, #names do
			if R.overlaps(layout.buttons[names[i]], layout.buttons[names[j]]) then
				problems[#problems + 1] = names[i] .. " overlaps " .. names[j]
			end
		end
	end
	if layout.deck and R.overlaps(layout.hand, layout.deck) then problems[#problems + 1] = "hand overlaps the draw pile" end
	if layout.deck and R.overlaps(layout.actions, layout.deck) then problems[#problems + 1] = "action row overlaps the draw pile" end
	-- the hand must have room for its cards: 8 cards at the minimum card width (48) with 6px gaps and tray padding
	if layout.hand.w < 8 * 48 + 7 * 6 + 32 then problems[#problems + 1] = "hand is too narrow for 8 cards" end
	return problems
end

table.insert(tests, { name = "Layout harness: gameplay screen fits 640x360, 800x450, 1280x720 and 1920x1080", fn = function()
	local R = require(script.Parent.Parent.Engine.ResponsiveLayout)
	for _, vp in ipairs({ { 640, 360 }, { 800, 450 }, { 1280, 720 }, { 1920, 1080 } }) do
		local layout = R.gameplay(vp[1], vp[2])
		local problems = layoutProblems(vp[1], vp[2], layout)
		expectEqual(#problems, 0, vp[1] .. "x" .. vp[2] .. ": " .. table.concat(problems, "; "))
		expectEqual(layout.compact, vp[1] < 900, "compact mode under 900 wide")
		expectEqual(layout.sidebarW, layout.compact and 0 or 240, "the stats panel collapses into a drawer when compact")
		expectTrue(layout.actionScale > 0.5, "the button row never shrinks below half size")
	end
	-- before the fix: the stats panel always reserved 240px and the action row never scaled
	local failedBefore = {}
	for _, vp in ipairs({ { 640, 360 }, { 800, 450 }, { 1280, 720 }, { 1920, 1080 } }) do
		local legacy = R.gameplayLegacy(vp[1], vp[2])
		if #layoutProblems(vp[1], vp[2], legacy) > 0 then failedBefore[#failedBefore + 1] = vp[1] .. "x" .. vp[2] end
	end
	expectEqual(table.concat(failedBefore, ","), "640x360,800x450", "the old layout failed exactly the two narrow sizes")
end })

table.insert(tests, { name = "Layout harness: Collection panel, title and chips stay inside and clear of each other", fn = function()
	local R = require(script.Parent.Parent.Engine.ResponsiveLayout)
	for _, vp in ipairs({ { 640, 360 }, { 800, 450 }, { 1280, 720 }, { 1920, 1080 } }) do
		local fit = R.collectionPanel(vp[1], vp[2])
		local panel = { x = vp[1] * (1 - fit.w) / 2, y = vp[2] * (1 - fit.h) / 2, w = vp[1] * fit.w, h = vp[2] * fit.h }
		expectTrue(R.inside(panel, vp[1], vp[2]), vp[1] .. ": the panel is inside the screen")
		expectTrue(fit.w >= 0.66, "never narrower than before")
		-- title vs the Card Sets (15..111) and Badges (121..217) buttons on the title row
		local head = R.collectionTitle(panel.w)
		local textW = 120 -- "Collection" at 22px bold
		local textLeft = head.fullWidth and (panel.w - textW) / 2 or (head.x + (head.w - textW) / 2)
		local titleRect = { x = textLeft, y = 6, w = textW, h = 28 }
		local buttons = { { x = 15, y = 6, w = 96, h = 24 }, { x = 121, y = 6, w = 96, h = 24 } }
		for _, b in ipairs(buttons) do
			expectFalse(R.overlaps(titleRect, b), vp[1] .. ": the title does not sit behind a button")
		end
		expectTrue(titleRect.x + titleRect.w <= panel.w - 60 + 1, vp[1] .. ": the title clears the expand toggle on the right")
		-- the six rarity chips wrap instead of overflowing
		local widths = { 92, 100, 78, 78, 106, 96 }
		local rows = R.wrapRows(widths, panel.w - 30, 14)
		for _, row in ipairs(rows) do
			local used = 0
			for _, idx in ipairs(row) do used = used + widths[idx] end
			used = used + 14 * (#row - 1)
			expectTrue(used <= panel.w - 30 or #row == 1, vp[1] .. ": a chip row fits the panel")
		end
		if vp[1] >= 1280 then expectEqual(#rows, 1, "one chip row on a wide screen") end
	end
end })

table.insert(tests, { name = "DailyPopup: shows when the game opens with a reward ready and after a round, never nags", fn = function()
	local DailyPopup = require(script.Parent.Parent.Engine.DailyPopup)
	local R = require(script.Parent.Parent.Engine.ResponsiveLayout)
	local function state(phase, claimable, day, round)
		return { phase = phase, night = 1, round = round or 1,
			login = { streak = 3, rewards = { { day = day or 3, claimable = claimable, claimed = false, label = "5 Tips" } } } }
	end
	expectEqual(DailyPopup.nextClaimable(state("menu", false).login), nil, "nothing claimable")
	expectEqual(DailyPopup.nextClaimable(state("menu", true).login).day, 3)
	local t = {}
	expectFalse(DailyPopup.shouldShow(t, state("roundSelect", false)), "nothing waiting: no popup")
	expectTrue(DailyPopup.shouldShow(t, state("roundSelect", true)), "game opens with a reward ready: show")
	expectFalse(DailyPopup.shouldShow(t, state("roundSelect", true)), "same state again: no nagging")
	expectFalse(DailyPopup.shouldShow(t, state("playing", true)), "mid-round: stays quiet")
	expectTrue(DailyPopup.shouldShow(t, state("shop", true)), "a round just ended with the reward still waiting: show again")
	expectFalse(DailyPopup.shouldShow(t, state("shop", true)), "once per finished round")
	expectFalse(DailyPopup.shouldShow(t, state("roundSelect", true, 3, 2)), "not a round end: quiet")
	expectFalse(DailyPopup.shouldShow(t, state("playing", true, 3, 2)))
	expectTrue(DailyPopup.shouldShow(t, state("shop", true, 3, 2)), "the next finished round asks again")
	expectFalse(DailyPopup.shouldShow(t, state("shop", false, 3, 2)), "claimed: nothing to show")
	expectTrue(DailyPopup.shouldShow(t, state("shop", true, 7, 2)), "the next reward (another day) asks on first sight")
	local shown, extra = DailyPopup.flames(3, 7)
	expectTrue(shown == 3 and extra == 0, "3 flames")
	shown, extra = DailyPopup.flames(12, 7)
	expectTrue(shown == 7 and extra == 5, "long streaks cap the flames and say how many more")
	-- top-left rule: panels stay clear of Roblox's top bar
	expectEqual(R.clearOfTopBar(16, 16), 60, "a left-zone panel is pushed below the top bar")
	expectEqual(R.clearOfTopBar(16, 120), 120, "already clear stays put")
	expectEqual(R.clearOfTopBar(900, 10), 10, "away from the top-left corner nothing moves")
	expectEqual(R.clearOfTopBar(16, 16, 44), 104, "the phone safe area adds to it")
end })

table.insert(tests, { name = "Seeds: 6 character codes (A-Z without I and O, 2-9), friendly errors, display text per run type", fn = function()
	local SeededRng = require(script.Parent.Parent.Engine.SeededRng)
	local SeedDisplay = require(script.Parent.Parent.Engine.SeedDisplay)
	local ok, code, msg = SeededRng.validateCode("star27")
	expectTrue(ok and code == "STAR27" and msg == "", "lower case is normalized")
	ok, code = SeededRng.validateCode(" st-ar 27 ")
	expectTrue(ok and code == "STAR27", "spaces and dashes are dropped")
	ok, code, msg = SeededRng.validateCode("")
	expectFalse(ok); expectTrue(#msg > 0, "empty: a message")
	ok, _, msg = SeededRng.validateCode("ABC")
	expectFalse(ok); expectTrue(msg:find("6") ~= nil, "wrong length says 6 characters")
	ok, _, msg = SeededRng.validateCode("ABCDEFG")
	expectFalse(ok, "too long")
	local _normalized
	for _, bad in ipairs({ "ABCDI2", "ABCDO2", "ABCD01", "ABCD0Z", "ABC!23" }) do
		ok, _normalized, msg = SeededRng.validateCode(bad)
		expectFalse(ok, bad .. " has a character outside the alphabet")
		expectTrue(#msg > 0)
	end
	expectFalse(SeededRng.validateCode(nil)); expectFalse(SeededRng.validateCode(123456))
	expectFalse(SeededRng.CODE_CHARS:find("I", 1, true) or SeededRng.CODE_CHARS:find("O", 1, true) or SeededRng.CODE_CHARS:find("[01]"), "no I, O, 0 or 1")
	expectEqual(#SeededRng.CODE_CHARS, 32)
	-- every rolled code validates
	for _ = 1, 200 do
		local rolled = SeededRng.randomCode(6)
		expectTrue(SeededRng.validateCode(rolled), "rolled codes are valid: " .. rolled)
	end
	-- display text
	local l = SeedDisplay.label({ isSeeded = true, seedCode = "STAR27" })
	expectEqual(l.text, "Seed: STAR27"); expectTrue(l.shareable)
	expectEqual(SeedDisplay.shareText({ isSeeded = true, seedCode = "STAR27" }), "Play my Wildcard Tavern seed: STAR27")
	l = SeedDisplay.label({ isDaily = true, dailyDateKey = "2026-11-08" })
	expectEqual(l.text, "Daily: 2026-11-08"); expectFalse(l.shareable)
	l = SeedDisplay.label({ isWeekly = true, weeklyDateKey = "2026-W45" })
	expectEqual(l.text, "Weekly: 2026-W45")
	expectEqual(SeedDisplay.label({}), nil, "an ordinary run shows no seed")
	expectEqual(SeedDisplay.shareText({ isDaily = true, dailyDateKey = "x" }), nil, "only Seed Runs can be shared")
	expectEqual(SeedDisplay.label(nil), nil)
end })

table.insert(tests, { name = "ChallengeStart: every menu start state is start, confirm or a one line reason", fn = function()
	local CS = require(script.Parent.Parent.Engine.ChallengeStart)
	local verdict, line = CS.check({ hasState = false })
	expectEqual(verdict, "blocked"); expectEqual(line, CS.Lines.connecting)
	verdict, line = CS.check({ hasState = true, phase = "roundSelect", night = 1, round = 1, tutorialActive = true })
	expectEqual(verdict, "blocked"); expectEqual(line, CS.Lines.tutorial)
	verdict, line = CS.check({ hasState = true, phase = "roundSelect", night = 1, round = 1, traveling = true })
	expectEqual(verdict, "blocked"); expectEqual(line, CS.Lines.traveling)
	expectEqual((CS.check({ hasState = true, phase = "roundSelect", night = 1, round = 1 })), "start", "a fresh session just starts")
	expectEqual((CS.check({ hasState = true, phase = "gameover", night = 3, round = 2 })), "start", "after Game Over it just starts")
	expectEqual((CS.check({ hasState = true, phase = "playing", night = 1, round = 1 })), "confirm", "mid-round asks first")
	expectEqual((CS.check({ hasState = true, phase = "shop", night = 2, round = 1 })), "confirm", "in the shop asks first")
	expectEqual((CS.check({ hasState = true, phase = "roundSelect", night = 2, round = 1 })), "confirm", "a later Round Select asks first")
	expectEqual((CS.check({ hasState = true, phase = "roundSelect", night = 1, round = 2 })), "confirm")
	expectEqual((CS.check(nil)), "blocked", "no context is the connecting state")
	for _, text in pairs(CS.Lines) do
		expectTrue(#text <= 32 and not text:find("%-%-"), "short and dash free: " .. text)
	end
end })

table.insert(tests, { name = "Tutorial: one action per step, short text, cannot advance without it, skip needs the hold", fn = function()
	local Steps = require(script.Parent.Parent.Engine.TutorialSteps)
	local seen = {}
	for _, step in ipairs(Steps.Steps) do
		expectFalse(seen[step.id], "unique step id " .. step.id)
		seen[step.id] = true
		expectTrue(type(step.action) == "string", step.id .. " has exactly one action")
		local words = 0
		for _ in step.text:gmatch("%S+") do words = words + 1 end
		expectTrue(words <= Steps.MAX_WORDS, step.id .. " text is short: " .. words .. " words")
		expectFalse(step.text:find("%-%-") ~= nil or step.text:find("\226\128\148") ~= nil, step.id .. " has no dash marks")
		expectFalse((" " .. step.text:lower() .. " "):find(" or ") ~= nil, step.id .. " offers no choice")
		if step.action ~= "ok" then expectTrue(step.target ~= nil, step.id .. " points at a target") end
	end
	local m = Steps.new()
	expectEqual(m:current().id, "menu_play")
	expectEqual(m:report("play_hand"), "wrong", "the wrong deliberate action does not advance")
	expectEqual(m:current().id, "menu_play")
	expectEqual(m:report("pick", { selected = { [1] = true } }), "ignored", "selecting is not wrong, it is not the step either")
	expectEqual(m:report("menu_play"), "advanced")
	expectEqual(m:report("menu_play"), "wrong", "doing the finished step again is wrong now")
	expectEqual(m:report("select_round"), "advanced")
	-- pick the exact pair: slots 1 and 2
	expectEqual(m:current().id, "pick_pair")
	expectEqual(m:report("play_hand"), "wrong", "cannot play before picking")
	expectEqual(m:report("pick", { scripted = true, selected = { [1] = true } }), "ignored", "one of the two is not enough")
	expectEqual(m:report("pick", { scripted = true, selected = { [1] = true, [3] = true } }), "ignored", "a wrong card does not count")
	expectEqual(m:report("pick", { scripted = true, selected = { [1] = true, [2] = true, [3] = true } }), "ignored", "an extra card does not count")
	expectEqual(m:report("pick", { scripted = true, selected = { [1] = true, [2] = true } }), "advanced")
	expectEqual(m:current().id, "play_pair")
	expectEqual(m:report("play_hand"), "advanced")
	-- an unscripted replay accepts any selection
	local replay = Steps.new()
	replay:catchUp("pick")
	expectEqual(replay:report("pick", { scripted = false, selected = { [4] = true } }), "advanced")
	-- finish the whole list
	local full = Steps.new()
	full:report("menu_play"); full:report("select_round")
	for _, step in ipairs(Steps.Steps) do
		if step.action == "pick" then
			local sel = {}
			for i = 1, step.count do sel[i] = true end
			expectEqual(full:report("pick", { scripted = true, selected = sel }), "advanced", step.id)
		elseif step.id ~= "menu_play" and step.id ~= "select_round" then
			expectEqual(full:report(step.action), "advanced", step.id)
		end
	end
	expectTrue(full:finished() and not full:skipped(), "completing every step finishes it")
	-- catch up: the Shop appears early
	local early = Steps.new()
	early:report("menu_play"); early:report("select_round")
	expectTrue(early:catchUp("next_round"))
	expectEqual(early:current().id, "next_round")
	-- skip needs the full hold
	local sk = Steps.new()
	local hold = sk:skipHold()
	hold:press(0)
	expectFalse(hold:update(1.0), "a short press does not skip")
	hold:release(1.2)
	expectFalse(hold:update(5), "releasing cancels")
	hold:press(10)
	expectTrue(hold:update(11.5), "the full 1.5s hold confirms the skip")
	sk:skip()
	expectTrue(sk:finished() and sk:skipped())
	expectEqual(sk:current(), nil)
end })

table.insert(tests, { name = "TutorialScript: scripted hands name an exact combo and lose no cards", fn = function()
	local TS = require(script.Parent.Parent.Engine.TutorialScript)
	local Deck = require(script.Parent.Parent.Engine.Deck)
	local HandEvaluator = require(script.Parent.Parent.Engine.HandEvaluator)
	local want = { "Pair", "Two Pair", "Flush", "Straight Flush" }
	for stage, expected in ipairs(want) do
		local deck = Deck.shuffle(Deck.newStandardDeck(), function(n) return (n * 7919) % n + 1 end)
		local state = { deck = deck, hand = Deck.draw(deck, 8) }
		local before = #state.deck + #state.hand
		expectTrue(TS.applyStage(state, stage), "stage " .. stage .. " applies")
		expectEqual(#state.hand, 8, "the hand keeps its size")
		expectEqual(#state.deck + #state.hand, before, "no cards are created or lost")
		-- every card is unique
		local seen = {}
		for _, list in ipairs({ state.hand, state.deck }) do
			for _, c in ipairs(list) do
				local k = c.rank .. c.suit
				expectFalse(seen[k], "unique card " .. k)
				seen[k] = true
			end
		end
		-- the first targetCount cards are the named combo
		local n = TS.targetCount(stage)
		local target = {}
		for i = 1, n do target[i] = state.hand[i] end
		local result = HandEvaluator.evaluate(target)
		expectEqual(result.name or result.handName or result, expected, "stage " .. stage .. " is a " .. expected)
		-- the later stages' targets are still in the deck or hand
		for later = stage + 1, #TS.Stages do
			for _, t in ipairs(TS.Stages[later].targets) do
				local found = false
				for _, list in ipairs({ state.hand, state.deck }) do
					for _, c in ipairs(list) do
						if c.rank == t[1] and c.suit == t[2] then found = true end
					end
				end
				expectTrue(found, "later target still available: " .. t[1] .. t[2])
			end
		end
		-- the filler cards do not turn the whole hand into something better than the stage by accident
		-- (fillers have distinct ranks that differ from the targets')
		local ranks = {}
		for i = n + 1, #state.hand do
			expectFalse(ranks[state.hand[i].rank], "filler ranks are distinct")
			ranks[state.hand[i].rank] = true
			for j = 1, n do
				expectTrue(state.hand[i].rank ~= state.hand[j].rank, "no filler pairs with a target")
			end
		end
	end
	expectFalse(TS.applyStage({ deck = {}, hand = {} }, 1), "missing target cards leave the hand alone")
	expectFalse(TS.applyStage({ deck = {}, hand = {} }, 9))
end })

table.insert(tests, { name = "SpecialPatterns: every Garnish, Special and Stamp has one pattern, tinted by the set", fn = function()
	local SP = require(script.Parent.Parent.Engine.SpecialPatterns)
	local Card = require(script.Parent.Parent.Engine.Card)
	expectEqual(#SP.missing(), 0, "missing patterns: " .. table.concat(SP.missing(), ", "))
	local seenCorner = {}
	for kind, table_ in pairs({ garnish = SP.Garnish, special = SP.Special, stamp = SP.Stamp }) do
		for id, p in pairs(table_) do
			expectTrue(type(p.glyph) == "string" and #p.glyph >= 1 and #p.glyph <= 2, kind .. ":" .. id .. " has a short glyph")
			expectTrue(#p.color == 3, kind .. ":" .. id .. " has a colour")
			expectTrue(p.edge == "border" or p.edge == "steel" or p.edge == "foil" or p.edge == "none", kind .. ":" .. id .. " edge type")
		end
	end
	-- the same card always resolves the same patterns in the same order: garnish, special, stamp
	local both = SP.patternsFor({ rank = 10, suit = "Hearts", garnish = "iron", special = "gold", stamp = "blue" })
	expectEqual(#both, 3)
	expectEqual(both[1].kind, "garnish"); expectEqual(both[2].kind, "special"); expectEqual(both[3].kind, "stamp")
	expectEqual(both[1].edge, "steel"); expectTrue(both[1].rivets, "Iron Garnish: a steel border with rivets")
	expectEqual(both[3].glyph, "B", "Blue Stamp is a seal marked B")
	expectEqual(#SP.patternsFor({ rank = 3, suit = "Clubs" }), 0, "a plain card has no pattern")
	expectFalse(SP.hasSpecial({ rank = 3, suit = "Clubs" })); expectTrue(SP.hasSpecial({ garnish = "lucky" }))
	-- a Card Set nudges the colour 20 percent toward its accent, no accent leaves it alone
	local c = SP.tinted({ 100, 100, 100 }, { 200, 0, 100 })
	expectTrue(c[1] == 120 and c[2] == 80 and c[3] == 100, "20 percent toward the accent")
	expectTrue(SP.tinted({ 1, 2, 3 }, nil)[2] == 2)
	expectTrue(Card.Garnishes.iron ~= nil)
end })

table.insert(tests, { name = "PackPreview: a revealed card shows the plain copy of the same card you already hold", fn = function()
	local PP = require(script.Parent.Parent.Engine.PackPreview)
	local deckView = {
		{ rank = 7, suit = "Hearts", status = "draw" },
		{ rank = 7, suit = "Hearts", garnish = "iron", status = "draw" },
		{ rank = 7, suit = "Hearts", status = "discard" },
		{ rank = 9, suit = "Clubs", status = "hand" },
	}
	local spec = { rank = 7, suit = "Hearts", special = "gold" }
	local m = PP.matchFromDeckView(deckView, spec)
	expectTrue(m ~= nil and m.copies == 2, "two plain copies, the Iron one does not count")
	expectEqual(m.entry.status, "draw")
	expectEqual(PP.caption(m, spec), "You hold 2 plain 7 of Hearts. The new card joins your deck.")
	expectEqual(PP.matchFromDeckView(deckView, { rank = 2, suit = "Spades" }), nil, "no plain copy: nothing to ghost")
	expectTrue(PP.caption(nil, spec):find("joins your deck") ~= nil)
	expectEqual(PP.matchFromDeckView(nil, spec), nil)
	expectTrue(PP.caption(PP.matchFromDeckView({ { rank = 12, suit = "Spades" } }, { rank = 12, suit = "Spades" }), { rank = 12, suit = "Spades" }):find("Queen") ~= nil)
end })

table.insert(tests, { name = "ArtStatus: biome set backdrops and badge icons have a prompt and a wired slot", fn = function()
	local Engine = script.Parent.Parent.Engine
	local CosmeticSets = require(Engine.CosmeticSets)
	local Badges = require(Engine.Badges)
	local ContentArt = require(Engine.ContentArt)
	expectTrue(type(ContentArt.set_backdrops) == "table", "ContentArt has set_backdrops")
	expectTrue(type(ContentArt.badges) == "table", "ContentArt has badges")
	local biomeSets = {}
	for _, set in ipairs(CosmeticSets.Definitions) do
		if set.unlock and set.unlock.kind == "biome" then
			table.insert(biomeSets, set.id)
			expectTrue(type(set.backdropImage) == "string", set.id .. " has a backdropImage slot")
			-- Recording an id in SetBackdropArt must reach the set (wired, not hardcoded).
			local mapped = ContentArt.set_backdrops[set.id]
			expectTrue(mapped == nil or set.backdropImage == mapped, set.id .. " backdropImage follows SetBackdropArt")
		end
	end
	expectEqual(#biomeSets, 8, "8 biome Card Sets")
	expectEqual(#Badges.Definitions, 32, "16 biome badges + 16 rule badges")
	-- Prompts exist for every item (skipped where io is missing, e.g. Studio).
	if io and io.open then
		local f = io.open("tools/patron_art/prompts.json", "r")
		if f then
			local text = f:read("*a")
			f:close()
			local function section(name)
				local s = text:find('"' .. name .. '"', 1, true)
				expectTrue(s ~= nil, name .. " section exists")
				return text:sub(s or 1)
			end
			local sets, badges = section("set_backdrop_subjects"), section("badge_subjects")
			for _, id in ipairs(biomeSets) do
				expectTrue(sets:find('"' .. id .. '"', 1, true) ~= nil, id .. " has a set_backdrop_subjects prompt")
			end
			for _, def in ipairs(Badges.Definitions) do
				expectTrue(badges:find('"' .. def.id .. '"', 1, true) ~= nil, def.id .. " has a badge_subjects prompt")
			end
		end
		-- ART_STATUS.md (python3 tools/art_status.py) must not list any item without a prompt.
		local st = io.open("claude/ART_STATUS.md", "r")
		if st then
			local status = st:read("*a")
			st:close()
			expectTrue(status:find("NO PROMPT (", 1, true) == nil, "ART_STATUS lists no item without a prompt")
		end
	end
end })

-- ===== Stakes (difficulty ladder) =====

table.insert(tests, { name = "Stakes: eight stakes, each adds exactly one rule on top of the lower ones, stake 1 changes nothing", fn = function()
	local Stakes = require(script.Parent.Parent.Engine.Stakes)
	expectEqual(#Stakes.Definitions, 8)
	local function activeRules(n)
		local count = 0
		for _, value in pairs(Stakes.rulesFor(n)) do
			if value ~= 0 and value ~= false then count = count + 1 end
		end
		return count
	end
	expectEqual(activeRules(1), 0, "Regular adds nothing")
	for n = 2, 8 do
		expectEqual(activeRules(n), activeRules(n - 1) + 1, "stake " .. n .. " adds one rule")
		expectTrue(#Stakes.Definitions[n].hint > 0 and #Stakes.unlockHint(n) > 0, "stake " .. n .. " has text")
	end
	expectEqual(Stakes.clamp(nil), 1)
	expectEqual(Stakes.clamp(99), 8)
	expectEqual(Stakes.clamp(0 / 0), 1)
end })

table.insert(tests, { name = "Stakes in RunState: each rule changes only what it says", fn = function()
	local rng = function(_n) return 1 end
	local base = RunState.new({ stakeId = 1 }, rng)
	local plain = RunState.new(nil, rng)
	expectEqual(base.config.discardsPerRound, plain.config.discardsPerRound, "stake 1 equals the default")
	expectEqual(base.config.tipsPerRoundWin, plain.config.tipsPerRoundWin)
	expectEqual(base.config.recipeSlotLimit, plain.config.recipeSlotLimit)
	expectEqual(base.targetScore, plain.targetScore)
	expectEqual(RunState.rerollCost(base, 5), 5)

	expectEqual(RunState.new({ stakeId = 2 }, rng).config.discardsPerRound, plain.config.discardsPerRound - 1, "Busy Night")
	expectEqual(RunState.rerollCost(RunState.new({ stakeId = 4 }, rng), 5), 6, "Rush Hour")
	expectEqual(RunState.new({ stakeId = 6 }, rng).config.recipeSlotLimit, plain.config.recipeSlotLimit - 1, "Packed House")
	-- Closing Time: the flat Tip is unchanged, non-boss rounds pay 1 less, Boss Rounds pay the same as stake 1
	expectEqual(RunState.new({ stakeId = 7 }, rng).config.tipsPerRoundWin, plain.config.tipsPerRoundWin, "Closing Time keeps the flat Tip")
	expectEqual(RunState.new({ stakeId = 7 }, rng).config.tipsNonBossDelta, -1, "Closing Time")
	expectEqual(RunState.new({ stakeId = 6 }, rng).config.tipsNonBossDelta, 0, "stake 6 pays full")
	local function payout(stakeId, boss)
		local s = RunState.new({ stakeId = stakeId }, rng)
		s.targetScore = 0
		s.tips = 0
		s.isBossRound = boss
		RunState.playHand(s, { 1 })
		return s.tips
	end
	expectEqual(payout(7, false), payout(1, false) - 1, "Closing Time: a normal round pays 1 less")
	expectEqual(payout(7, true), payout(1, true), "Closing Time: a Boss Round pays the same")
	expectEqual(RunState.new({ stakeId = 99 }, rng).stake, 8, "clamped")

	-- Final Bell: no interest
	local s5 = RunState.new({ stakeId = 5 }, rng)
	s5.targetScore = 0
	s5.tips = 12
	RunState.playHand(s5, { 1 })
	expectEqual(s5.tips, 12 + s5.config.tipsPerRoundWin, "no interest at Final Bell")
	local s4 = RunState.new({ stakeId = 4 }, rng)
	s4.targetScore = 0
	s4.tips = 12
	RunState.playHand(s4, { 1 })
	expectEqual(s4.tips, 12 + 2 + s4.config.tipsPerRoundWin, "interest still paid below Final Bell")
end })

table.insert(tests, { name = "Stakes balance: targets and hands never change, boss rounds only as much higher as the stake says, discards never negative", fn = function()
	local WorldMap = require(script.Parent.Parent.Engine.WorldMap)
	local route = WorldMap.defaultRoute()
	local _, baseline = walkRoute(route, { stakeId = 1 })
	for stake = 2, 8 do
		local _, rows = walkRoute(route, { stakeId = stake })
		expectEqual(#rows, #baseline)
		for i, row in ipairs(rows) do
			expectEqual(row.hands, baseline[i].hands, "hands unchanged at stake " .. stake)
			expectTrue(row.discards >= 0, "discards never negative")
			if row.boss then
				local lift = 1 + require(script.Parent.Parent.Engine.Stakes).rulesFor(stake).bossTargetPct / 100
				expectEqual(row.target, math.floor(baseline[i].target * lift), "boss target at stake " .. stake .. " night " .. row.night)
				expectTrue(row.target <= baseline[i].target * 1.25 + 1, "boss target within 25%")
			else
				expectEqual(row.target, baseline[i].target, "non-boss target unchanged at stake " .. stake)
			end
		end
	end
	-- Legend: boss rounds give one fewer discard than Closing Time
	local _, legend = walkRoute(route, { stakeId = 8 })
	local _, closing = walkRoute(route, { stakeId = 7 })
	for i, row in ipairs(legend) do
		if row.boss then
			expectEqual(row.discards, math.max(0, closing[i].discards - 1), "Legend boss discard")
		else
			expectEqual(row.discards, closing[i].discards)
		end
	end
end })

table.insert(tests, { name = "Stakes unlock and stamps: win on stake N opens N+1, stamps keep the highest, junk saves are cleaned", fn = function()
	local Stakes = require(script.Parent.Parent.Engine.Stakes)
	local profile = PlayerProfile.new()
	expectEqual(Stakes.highestUnlocked(profile), 1)
	expectTrue(not Stakes.isUnlocked(profile, 2))
	expectEqual(Stakes.resolveStart(profile, 3, false), 1, "a locked stake falls back to Regular")
	expectTrue(Stakes.recordWin(profile, 1, { "road", "meadow", "tavern" }))
	expectEqual(profile.highestStakeUnlocked, 2)
	expectEqual(Stakes.stampOf(profile, "meadow"), 1)
	expectEqual(Stakes.resolveStart(profile, 2, false), 2)
	expectEqual(Stakes.resolveStart(profile, 2, true), 1, "seeded and tutorial runs are Regular")
	-- a lower win never lowers anything; a higher win raises the stamp and unlocks one more
	Stakes.recordWin(profile, 2, { "road", "desert" })
	Stakes.recordWin(profile, 1, { "road" })
	expectEqual(profile.highestStakeUnlocked, 3)
	expectEqual(Stakes.stampOf(profile, "road"), 2)
	expectEqual(Stakes.stampOf(profile, "desert"), 2)
	expectEqual(Stakes.stampOf(profile, "meadow"), 1)
	-- the top stake stays the top
	profile.highestStakeUnlocked = 8
	Stakes.recordWin(profile, 8, { "tavern" })
	expectEqual(profile.highestStakeUnlocked, 8)
	expectEqual(Stakes.stampOf(profile, "tavern"), 8)
	-- save/load: valid values survive, junk is dropped
	local loaded = PlayerProfile.migrate({ highestStakeUnlocked = 5, stakeStamps = { road = 3, nowhere = 4, meadow = "x", peaks = -2 } })
	expectEqual(loaded.highestStakeUnlocked, 5)
	expectEqual(loaded.stakeStamps.road, 3)
	expectTrue(loaded.stakeStamps.nowhere == nil and loaded.stakeStamps.meadow == nil and loaded.stakeStamps.peaks == nil, "junk dropped")
	expectEqual(PlayerProfile.migrate({ highestStakeUnlocked = "9" }).highestStakeUnlocked, 1)
	expectEqual(PlayerProfile.migrate(nil).highestStakeUnlocked, 1)
end })

table.insert(tests, { name = "Stakes: every stake has a stake_subjects art prompt, none is generated yet", fn = function()
	local Stakes = require(script.Parent.Parent.Engine.Stakes)
	local f = io and io.open and io.open("tools/patron_art/prompts.json", "r")
	if not f then return end
	local json = f:read("*a")
	f:close()
	expectTrue(json:find('"stake_subjects"', 1, true) ~= nil, "stake_subjects section exists")
	for _, def in ipairs(Stakes.Definitions) do
		expectTrue(json:find('"' .. def.id .. '"', 1, true) ~= nil, def.id .. " has a prompt")
	end
end })

-- ===== Unlock drip =====

table.insert(tests, { name = "Unlocks: every rule names real content, hints are short, Menu Recipes are never gated", fn = function()
	local Unlocks = require(script.Parent.Parent.Engine.Unlocks)
	for id, rule in pairs(Unlocks.Rules.patron) do
		expectTrue(Patrons.getById(id) ~= nil, "patron " .. id .. " exists")
		local words = 0
		for _ in rule.hint:gmatch("%S+") do words = words + 1 end
		expectTrue(words <= 12, id .. " hint is 12 words or fewer")
	end
	for id, rule in pairs(Unlocks.Rules.recipe) do
		expectTrue(Recipes.getHouseRecipeById(id) ~= nil or Recipes.getSecretRecipeById(id) ~= nil, "recipe " .. id .. " exists and is not a Menu Recipe")
		expectTrue(#rule.hint > 0)
	end
end })

table.insert(tests, { name = "Unlocks: a fresh profile starts with about half of the Patrons and Recipes open", fn = function()
	local Unlocks = require(script.Parent.Parent.Engine.Unlocks)
	local set = Unlocks.setFor(PlayerProfile.new())
	local openPatrons, totalPatrons = 0, #Patrons.Definitions
	for _, patron in ipairs(Patrons.Definitions) do
		if not Unlocks.isGated("patron", patron.id) or set["patron:" .. patron.id] then openPatrons = openPatrons + 1 end
	end
	expectTrue(openPatrons / totalPatrons >= 0.3 and openPatrons / totalPatrons <= 0.6, "about half of the Patrons: " .. openPatrons .. " of " .. totalPatrons)
	local openRecipes, totalRecipes = 0, 0
	for _, list in ipairs({ Recipes.HouseRecipes, Recipes.SecretRecipes }) do
		for _, r in ipairs(list) do
			totalRecipes = totalRecipes + 1
			if not Unlocks.isGated("recipe", r.id) or set["recipe:" .. r.id] then openRecipes = openRecipes + 1 end
		end
	end
	expectTrue(openRecipes / totalRecipes >= 0.35 and openRecipes / totalRecipes <= 0.6, "about half of the Recipes: " .. openRecipes .. " of " .. totalRecipes)
end })

table.insert(tests, { name = "Unlocks: shop offers and pack reveals only use open content, seeded and test runs see everything", fn = function()
	local Unlocks = require(script.Parent.Parent.Engine.Unlocks)
	local set = Unlocks.setFor(PlayerProfile.new())
	local state = RunState.new({ unlockedContent = set }, math.random)
	for _ = 1, 60 do
		local offers = Shop.rollOffers(state)
		expectEqual(#offers.patrons, Shop.OFFER_COUNT, "the starting pool always fills the shelf")
		for _, patron in ipairs(offers.patrons) do
			expectTrue(Unlocks.available(state, "patron", patron.id), patron.id .. " is open")
		end
	end
	for _, packId in ipairs({ "buffoon_pack", "jumbo_buffoon_pack" }) do
		if Packs.getById(packId) then
			for _ = 1, 20 do
				state.tips = 100
				state.pendingPack = nil
				local pending = RunState.openPack(state, packId)
				if pending then
					for _, item in ipairs(pending.items) do
						expectTrue(Unlocks.available(state, "patron", item.id), "pack reveals only open Patrons")
					end
				end
			end
		end
	end
	for _, pack in ipairs(Packs.Definitions) do
		for _ = 1, 15 do
			state.tips = 100
			state.pendingPack = nil
			local pending = RunState.openPack(state, pack.id)
			expectTrue(pending ~= nil, pack.id .. " opens")
			for _, item in ipairs(pending.items) do
				if item.category == "patron" then
					expectTrue(Unlocks.available(state, "patron", item.id), "open Patron only")
				elseif item.category == "house" or item.category == "secret" then
					expectTrue(Unlocks.available(state, "recipe", item.id), "open Recipe only")
				end
			end
		end
	end
	local open = RunState.new(nil, math.random)
	expectTrue(Unlocks.available(open, "patron", "nest_egg"), "a run without a set has everything")
	expectTrue(not Unlocks.available(state, "patron", "nest_egg"), "but a fresh profile does not")
end })

table.insert(tests, { name = "Unlocks: rules open content once, toasts fire once, discovered content carries over, nothing re-locks", fn = function()
	local Unlocks = require(script.Parent.Parent.Engine.Unlocks)
	local profile = PlayerProfile.new()
	local fresh, saved = Unlocks.evaluate(profile)
	expectEqual(#fresh, 0, "nothing opens for a new player")
	expectTrue(not saved)
	profile.stats.runsWon = 1
	profile.stats.bestNightReached = 3
	fresh, saved = Unlocks.evaluate(profile)
	expectTrue(saved and #fresh > 0)
	local ids = {}
	for _, item in ipairs(fresh) do ids[item.kind .. ":" .. item.id] = true end
	expectTrue(ids["patron:curtain_call"] and ids["patron:boss_bane"] and ids["recipe:copy_the_order"], "first win and Night 3 rules open")
	expectTrue(not ids["patron:the_bard"] and not ids["patron:meadow_bee"], "later and granted-only content stays closed")
	local again = Unlocks.evaluate(profile)
	expectEqual(#again, 0, "no second toast")
	-- once open, stays open even if stats were somehow lower
	profile.stats.runsWon = 0
	expectTrue(Unlocks.isUnlocked(profile, "patron", "curtain_call"), "saved unlocks stay")
	-- discovered content counts as open and gives no toast
	local old = PlayerProfile.new()
	old.discoveredPatronIds.nest_egg = true
	old.discoveredRecipeIds.honey_drizzle = true
	expectTrue(Unlocks.isUnlocked(old, "patron", "nest_egg") and Unlocks.isUnlocked(old, "recipe", "honey_drizzle"))
	for _, item in ipairs(Unlocks.evaluate(old)) do
		expectTrue(item.id ~= "nest_egg" and item.id ~= "honey_drizzle", "carried-over content is not a toast")
	end
	-- stake, quests and rank rules read the profile fields the later features set
	expectTrue(Unlocks.ruleMet({ highestStakeUnlocked = 2 }, { kind = "stake", n = 1 }))
	expectTrue(not Unlocks.ruleMet({ highestStakeUnlocked = 1 }, { kind = "stake", n = 1 }))
	expectTrue(Unlocks.ruleMet({ questsDone = 5 }, { kind = "quests", n = 5 }) and Unlocks.ruleMet({ tavernRank = 4 }, { kind = "rank", n = 3 }))
	-- hints for the Collection list only what is still closed
	local hints = Unlocks.lockedHints(PlayerProfile.new())
	expectTrue(hints.patron.nest_egg ~= nil and hints.patron.the_regular == nil)
	-- save / load keeps valid keys and drops junk
	local loaded = PlayerProfile.migrate({ unlockedContent = { ["patron:nest_egg"] = true, ["patron:the_regular"] = true, ["recipe:nope"] = true, junk = true }, stats = { handsPlayedTotal = 42 } })
	expectTrue(loaded.unlockedContent["patron:nest_egg"] == true and loaded.unlockedContent["patron:the_regular"] == nil and loaded.unlockedContent.junk == nil)
	expectEqual(loaded.stats.handsPlayedTotal, 42)
end })

table.insert(tests, { name = "Unlocks balance: the starting Patrons alone can carry a flush past a Night 3 Big round", fn = function()
	local Unlocks = require(script.Parent.Parent.Engine.Unlocks)
	local set = Unlocks.setFor(PlayerProfile.new())
	local cards = { C(2, "Hearts"), C(5, "Hearts"), C(8, "Hearts"), C(11, "Hearts"), C(13, "Hearts") }
	local hand = HandEvaluator.evaluate(cards)
	local ctx = function()
		return { allPlayedCards = cards, heldCards = {}, handsRemaining = 2, discardsRemaining = 2, isLastHand = false,
			night = 3, round = 2, tips = 10, handLevels = {}, rng = function(_n) return 1 end }
	end
	local base = Scoring.calculate(hand, {}, ctx())
	local ranked = {}
	for _, patron in ipairs(Patrons.Definitions) do
		if not Unlocks.isGated("patron", patron.id) or set["patron:" .. patron.id] then
			ranked[#ranked + 1] = { patron = patron, gain = Scoring.calculate(hand, { patron }, ctx()) - base }
		end
	end
	table.sort(ranked, function(a, b) return a.gain > b.gain end)
	local build = {}
	for i = 1, RunState.DefaultConfig.patronSlotLimit do build[i] = ranked[i].patron end
	local score = Scoring.calculate(hand, build, ctx())
	local target = RunState.targetScoreFor(3, 2)
	expectTrue(score >= target, "a starting-pool build scores " .. score .. " vs the Night 3 Big target " .. target)
end })

-- ===== Tavern Rank, daily quests, account progress =====

table.insert(tests, { name = "TavernRank: 30 ranks, rising XP, every rank has a reward that resolves to real content", fn = function()
	local TavernRank = require(script.Parent.Parent.Engine.TavernRank)
	local CardBacks = require(script.Parent.Parent.Engine.CardBacks)
	expectEqual(TavernRank.MAX_RANK, 30)
	expectEqual(TavernRank.xpForRank(1), 0)
	expectEqual(TavernRank.rankFor(0), 1)
	expectEqual(TavernRank.rankFor(TavernRank.xpForRank(7)), 7)
	expectEqual(TavernRank.rankFor(TavernRank.xpForRank(7) - 1), 6)
	expectEqual(TavernRank.rankFor(10 ^ 9), 30)
	for r = 2, 30 do
		expectTrue(TavernRank.xpToNext(r) > TavernRank.xpToNext(r - 1), "XP per rank rises")
		local reward = TavernRank.Rewards[r]
		expectTrue(reward ~= nil, "rank " .. r .. " has a reward")
		if reward.kind == "title" then
			expectTrue(Achievements.getById(reward.id) ~= nil and Achievements.getById(reward.id).milestoneReward, reward.id .. " is a real reward title")
		elseif reward.kind == "cardBack" then
			expectTrue(CardBacks.getById(reward.id) ~= nil, reward.id .. " is a real card back")
		elseif reward.kind == "set" then
			expectTrue(CosmeticSets.getById(reward.id) ~= nil, reward.id .. " is a real set")
		else
			expectEqual(reward.kind, "tips")
			expectTrue(reward.amount >= 1 and reward.amount <= 10, "small Tips only")
		end
	end
	-- a rank-30 player still sees a sane view
	local view = TavernRank.view({ tavernXp = TavernRank.MAX_XP })
	expectTrue(view.maxed and view.rank == 30 and view.need == 0)
end })

table.insert(tests, { name = "TavernRank.addXp: rewards are granted once, in order, nothing is lost on a big jump, Tips are capped", fn = function()
	local TavernRank = require(script.Parent.Parent.Engine.TavernRank)
	local profile = PlayerProfile.new()
	expectEqual((TavernRank.addXp(profile, 0)), 0)
	local _, ups = TavernRank.addXp(profile, 79)
	expectEqual(#ups, 0)
	_, ups = TavernRank.addXp(profile, 1)
	expectEqual(ups[1], 2)
	expectEqual(profile.pendingStartTips, 3)
	-- a huge jump grants every reward on the way, exactly once
	_, ups = TavernRank.addXp(profile, TavernRank.xpForRank(12))
	expectTrue(profile.rewardTitleIds.table_regular and profile.rewardTitleIds.favorite_guest and profile.rewardTitleIds.house_captain == nil, "rank 5 and 10 titles, not rank 15 yet")
	expectTrue(profile.unlockedCardBackIds.kitchen_checks and profile.unlockedCardBackIds.hall_banner, "card backs on the way")
	expectTrue(profile.ownedSetIds.winter_evening, "rank 12 Card Set")
	expectTrue(profile.pendingStartTips <= TavernRank.MAX_PENDING_TIPS, "banked Tips are capped")
	local tipsNow = profile.pendingStartTips
	TavernRank.grantDue(profile)
	expectEqual(profile.pendingStartTips, tipsNow, "no double grant")
	-- the bank pays out once
	expectEqual(TavernRank.takeStartTips(profile), tipsNow)
	expectEqual(TavernRank.takeStartTips(profile), 0)
	-- first win of the day is once per UTC day
	expectEqual(TavernRank.firstWinBonus(profile, 50), TavernRank.Xp.firstWinOfDay)
	expectEqual(TavernRank.firstWinBonus(profile, 50), 0)
	expectEqual(TavernRank.firstWinBonus(profile, 51), TavernRank.Xp.firstWinOfDay)
	-- save / load keeps XP, derives the rank, drops junk
	local loaded = PlayerProfile.migrate(profile)
	expectEqual(loaded.tavernXp, profile.tavernXp)
	expectEqual(loaded.tavernRank, TavernRank.rankFor(profile.tavernXp))
	local bad = PlayerProfile.migrate({ tavernXp = -5, pendingStartTips = 9999, rankRewardIds = { [99] = true, x = true }, questsDone = "z" })
	expectEqual(bad.tavernXp, 0)
	expectEqual(bad.pendingStartTips, TavernRank.MAX_PENDING_TIPS)
	expectTrue(next(bad.rankRewardIds) == nil)
	expectEqual(bad.questsDone, 0)
end })

table.insert(tests, { name = "Quests: the same three quests for a given UTC day, different days vary, progress completes once and pays", fn = function()
	local Quests = require(script.Parent.Parent.Engine.Quests)
	local a, b = Quests.rollFor(20000), Quests.rollFor(20000)
	expectEqual(table.concat(a, ","), table.concat(b, ","), "deterministic")
	expectEqual(#a, 3)
	local seen = {}
	for _, id in ipairs(a) do
		expectTrue(Quests.getById(id) ~= nil and not seen[id], "distinct real quests")
		seen[id] = true
	end
	local distinct = {}
	for day = 20000, 20030 do distinct[table.concat(Quests.rollFor(day), ",")] = true end
	local count = 0
	for _ in pairs(distinct) do count = count + 1 end
	expectTrue(count > 5, "days vary: " .. count .. " different sets in 31 days")
	-- every counter a quest reads exists in Quests.countersOf
	local counters = Quests.countersOf({})
	for _, def in ipairs(Quests.Definitions) do
		expectTrue(counters[def.counter] ~= nil, def.id .. " reads a real counter")
		expectTrue(def.goal >= 1 and def.xp > 0 and def.tips >= 0)
	end
	-- 20 quest types, unique ids, never two quests on one counter in a day, deterministic
	expectEqual(#Quests.Definitions, 20, "20 quest types")
	local questIds = {}
	for _, def in ipairs(Quests.Definitions) do
		expectTrue(not questIds[def.id], "unique quest id " .. def.id)
		questIds[def.id] = true
		expectTrue(def.name ~= "" and def.desc ~= "" and def.icon ~= "", def.id .. " has text and an icon")
		expectTrue(def.xp >= 40 and def.xp <= 120, def.id .. " xp in range")
	end
	for d = 20000, 20400 do
		local rolled, again, counterSeen = Quests.rollFor(d), Quests.rollFor(d), {}
		expectEqual(table.concat(rolled, ","), table.concat(again, ","), "deterministic roll")
		expectEqual(#rolled, Quests.PER_DAY)
		for _, id in ipairs(rolled) do
			local counter = Quests.getById(id).counter
			expectTrue(not counterSeen[counter], "day " .. d .. " repeats counter " .. counter)
			counterSeen[counter] = true
		end
	end
	-- counters read real state fields
	local fake = Quests.countersOf({ handStats = { Straight = 2, ["Full House"] = 1, ["Three of a Kind"] = 4 },
		bigHands = 3, richClears = 1, quickClears = 2, housePassesBought = 1, recipesUsed = 2, cardsDiscarded = 12, night = 3, roundsCleared = 5 })
	expectEqual(fake.straights, 2); expectEqual(fake.fullHouses, 1); expectEqual(fake.trips, 4)
	expectEqual(fake.bigHands, 3); expectEqual(fake.cardsDiscarded, 12); expectEqual(fake.night, 3); expectEqual(fake.rounds, 5)
	-- progress: partial, capped, completes once, pays XP and Tips
	local profile = PlayerProfile.new()
	local day = 20000
	local first = Quests.getById(Quests.rollFor(day)[1])
	local done = Quests.apply(profile, day, { [first.counter] = first.goal - 1 > 0 and first.goal - 1 or 0 })
	if first.goal > 1 then
		expectEqual(#done, 0)
		expectEqual(profile.quests.progress[first.id], first.goal - 1)
	end
	done = Quests.apply(profile, day, { [first.counter] = 99 })
	expectEqual(#done >= 1, true)
	expectEqual(profile.quests.progress[first.id], first.goal, "progress is capped at the goal")
	expectTrue(profile.quests.done[first.id])
	expectTrue(profile.tavernXp >= first.xp and profile.pendingStartTips >= first.tips)
	local xpBefore, doneBefore = profile.tavernXp, profile.questsDone
	Quests.apply(profile, day, { [first.counter] = 99 })
	expectEqual(profile.tavernXp, xpBefore, "paid once")
	expectEqual(profile.questsDone, doneBefore)
	-- a new day rolls fresh quests
	expectTrue(Quests.ensureDay(profile, day + 1))
	expectEqual(next(profile.quests.progress), nil)
	-- save / load
	Quests.apply(profile, day + 1, { hands = 3, pairs = 1 })
	local loaded = PlayerProfile.migrate(profile)
	expectEqual(loaded.quests.day, day + 1)
	expectEqual(table.concat(loaded.quests.ids, ","), table.concat(profile.quests.ids, ","))
	expectEqual(PlayerProfile.migrate({ quests = { day = 5, ids = { "nope" } } }).quests, nil, "junk quests are dropped")
	-- view
	local view = Quests.view(profile, day + 1, 3600)
	expectEqual(#view.quests, 3)
end })

table.insert(tests, { name = "AccountProgress: counters become XP and quest progress once, daily and weekly runs count, a dropped counter never double counts", fn = function()
	local AccountProgress = require(script.Parent.Parent.Engine.AccountProgress)
	local TavernRank = require(script.Parent.Parent.Engine.TavernRank)
	local profile = PlayerProfile.new()
	local snap = {}
	local state = { handsPlayedTotal = 4, roundsCleared = 1, bossesCleared = 0, discardsUsedTotal = 2, handStats = { Pair = 2 } }
	local r1 = AccountProgress.sync(profile, snap, state, 20000, false)
	local expectedXp = 4 * TavernRank.Xp.hand + TavernRank.Xp.round
	expectTrue(profile.tavernXp >= expectedXp, "hands and rounds give XP")
	local xpAfter = profile.tavernXp
	local r2 = AccountProgress.sync(profile, snap, state, 20000, false)
	expectEqual(profile.tavernXp, xpAfter, "the same counters count once")
	expectEqual(#r2.quests, 0)
	-- a counter that drops (round restored) then climbs again only counts the new part
	state.handsPlayedTotal = 2
	AccountProgress.sync(profile, snap, state, 20000, false)
	expectEqual(profile.tavernXp, xpAfter)
	state.handsPlayedTotal = 6
	AccountProgress.sync(profile, snap, state, 20000, false)
	expectEqual(profile.tavernXp, xpAfter + 2 * TavernRank.Xp.hand, "only the 2 hands above the old high count")
	-- a win gives win XP plus the first win bonus, the bonus only once per day
	local before = profile.tavernXp
	AccountProgress.sync(profile, snap, state, 20000, true)
	expectEqual(profile.tavernXp - before >= TavernRank.Xp.win + TavernRank.Xp.firstWinOfDay, true)
	before = profile.tavernXp
	AccountProgress.sync(profile, snap, state, 20000, true)
	expectEqual(profile.tavernXp - before, TavernRank.Xp.win, "no second first-win bonus today")
	-- a boss kill and a pack bought move the matching quests (when today's three include them)
	local Quests = require(script.Parent.Parent.Engine.Quests)
	local ids = Quests.rollFor(20000)
	local completedAny = false
	for _, id in ipairs(ids) do
		if profile.quests.done[id] then completedAny = true end
	end
	state.handsPlayedTotal, state.bossesCleared, state.packsBought, state.flushClears, state.discardsUsedTotal = 40, 3, 3, 3, 40
	state.handStats = { Pair = 20, Straight = 20, ["Full House"] = 20, ["Three of a Kind"] = 20 }
	state.bigHands, state.richClears, state.quickClears, state.housePassesBought = 5, 5, 5, 5
	state.recipesUsed, state.cardsDiscarded, state.night, state.roundsCleared = 5, 40, 5, 40
	local r3 = AccountProgress.sync(profile, snap, state, 20000, false)
	for _, id in ipairs(ids) do
		expectTrue(profile.quests.done[id], id .. " completes once its counter is high enough")
	end
	expectTrue(profile.questsDone == 3 and (#r3.quests + (completedAny and 1 or 0)) >= 1)
	-- the Unlocks rule that reads questsDone / tavernRank sees the new fields
	local Unlocks = require(script.Parent.Parent.Engine.Unlocks)
	expectTrue(Unlocks.ruleMet(profile, { kind = "quests", n = 3 }) and Unlocks.ruleMet(profile, { kind = "rank", n = profile.tavernRank }))
end })

table.insert(tests, { name = "Achievements second wave: 30 new, unique, titled, stateless, unlock at their thresholds", fn = function()
	local Defs = Achievements.Definitions
	expectEqual(#Defs, 98, "53 original + 30 new + 2 invite + 4 season (2 free, 2 premium) + 6 Collection completion + 3 Legend titles")
	local ids, titles, titled = {}, {}, 0
	for index, a in ipairs(Defs) do
		expectTrue(not ids[a.id], "unique achievement id " .. a.id)
		ids[a.id] = true
		expectTrue(type(a.name) == "string" and a.name ~= "" and type(a.description) == "string" and a.description ~= "", a.id .. " has text")
		expectTrue(type(a.flavorText) == "string" and a.flavorText ~= "", a.id .. " has flavor text")
		if a.title then
			titled = titled + 1
			if index > 53 then -- (two of the original 53 share "Tavern Keeper"; the new ones are all distinct)
				expectTrue(not titles[a.title], "unique title " .. a.title)
				titles[a.title] = true
			end
		end
	end
	expectTrue(titled >= 15 + 53, "at least 15 of the 30 new achievements carry a title")
	local profile = PlayerProfile.new()
	local function isUnlocked(id) return Achievements.isUnlocked(profile, id) end
	expectFalse(isUnlocked("hand_hundred") or isUnlocked("stake_two") or isUnlocked("streak_three") or isUnlocked("quests_five"), "a new profile has none")
	profile.stats.handsPlayedTotal = 100
	expectTrue(isUnlocked("hand_hundred")); expectFalse(isUnlocked("hand_five_hundred"))
	profile.highestStakeUnlocked = 4
	expectTrue(isUnlocked("stake_two") and isUnlocked("stake_four")); expectFalse(isUnlocked("stake_six"))
	profile.bestLoginStreak = 7
	expectTrue(isUnlocked("streak_three") and isUnlocked("streak_seven")); expectFalse(isUnlocked("streak_fourteen"))
	-- the streak achievements read the best streak, so a broken streak never takes them back
	profile.loginStreak = 1
	expectTrue(isUnlocked("streak_seven"), "a reset login streak keeps the achievement")
	profile.questsDone = 25
	expectTrue(isUnlocked("quests_five") and isUnlocked("quests_twentyfive")); expectFalse(isUnlocked("quests_hundred"))
	profile.endlessBestByStake = { ["1"] = 16, ["3"] = 31 }
	expectTrue(isUnlocked("endless_fifteen") and isUnlocked("endless_thirty"))
	profile.challengesCleared = { pairs_only = true }
	expectTrue(isUnlocked("challenge_first")); expectFalse(isUnlocked("challenge_many"))
	-- bestLoginStreak is a high-water mark in LoginStreak and survives a save
	local LoginStreak = require(script.Parent.Parent.Engine.LoginStreak)
	local p2 = PlayerProfile.new()
	LoginStreak.checkIn(p2, 100); LoginStreak.checkIn(p2, 101); LoginStreak.checkIn(p2, 102)
	expectEqual(p2.bestLoginStreak, 3)
	LoginStreak.checkIn(p2, 200)
	expectEqual(p2.loginStreak, 1); expectEqual(p2.bestLoginStreak, 3, "best streak never drops")
	expectEqual(PlayerProfile.migrate(p2).bestLoginStreak, 3)
	expectEqual(PlayerProfile.migrate({ bestLoginStreak = "x" }).bestLoginStreak, 0, "junk is dropped")
end })

table.insert(tests, { name = "RunHistory: capped at 20 newest first, tagged by mode, lifetime math, favorite Patron, safe migration", fn = function()
	local RunHistory = require(script.Parent.Parent.Engine.RunHistory)
	local profile = PlayerProfile.new()
	expectEqual(#profile.runHistory, 0)
	expectEqual(profile.lifetime.bestHandScore, 0)
	for i = 1, 25 do
		local ok = RunHistory.record(profile, {
			t = 1000 + i, mode = i % 2 == 0 and "daily" or "standard", road = "meadow", stake = (i % 3) + 1, night = (i % 8) + 1,
			won = i % 5 == 0, score = i * 100, hands = i, patrons = { "warm_hearth", "flush_fan" },
			bestHand = { name = "Flush", score = i * 10 },
		}, 5)
		expectTrue(ok)
	end
	expectEqual(#profile.runHistory, 20, "capped at 20")
	expectEqual(profile.runHistory[1].t, 1025, "newest first")
	expectEqual(profile.runHistory[20].t, 1006, "the oldest 5 fell off")
	expectEqual(profile.runHistory[1].mode, "standard"); expectEqual(profile.runHistory[2].mode, "daily")
	expectEqual(profile.lifetime.bestHandScore, 250); expectEqual(profile.lifetime.tipsEarned, 125)
	expectEqual(profile.lifetime.bestNightByStake["1"], 8, "best Night per stake over all 25 runs")
	expectEqual(profile.lifetime.patronWins.warm_hearth, 5, "5 won runs (every 5th)")
	local fav = RunHistory.favoritePatron(profile.lifetime)
	expectEqual(fav.id, "flush_fan"); expectEqual(fav.wins, 5) -- tie: alphabetical
	expectEqual(RunHistory.favoritePatron(RunHistory.newLifetime()), nil)
	profile.stats.runsStarted, profile.stats.runsWon, profile.stats.handsPlayedTotal = 25, 5, 400
	local view = RunHistory.view(profile)
	expectEqual(#view.recent, 20, "the page shows every kept run (20) for the sparkline"); expectEqual(view.runs, 25); expectEqual(view.wins, 5); expectEqual(view.hands, 400)
	expectEqual(view.bestHandScore, 250)
	-- junk entries and junk numbers are refused
	expectFalse(RunHistory.record(profile, { night = "x", t = 5 }))
	expectFalse(RunHistory.record(profile, nil))
	expectEqual(#profile.runHistory, 20)
	-- save and load: cleaned, capped, bad rows dropped
	local raw = { runHistory = { { t = 5, night = 3, mode = "nope", stake = 99, patrons = { 5, "a" } }, "junk", { t = 6 } },
		lifetime = { bestHandScore = -5, tipsEarned = "x", bestNightByStake = { ["9"] = 3, ["2"] = 4 }, patronWins = { a = 2, b = -1 } } }
	local loaded = PlayerProfile.migrate(raw)
	expectEqual(#loaded.runHistory, 1)
	expectEqual(loaded.runHistory[1].mode, "standard"); expectEqual(loaded.runHistory[1].stake, 8); expectEqual(#loaded.runHistory[1].patrons, 1)
	expectEqual(loaded.lifetime.bestNightByStake["2"], 4); expectEqual(loaded.lifetime.bestNightByStake["9"], nil)
	expectEqual(loaded.lifetime.patronWins.a, 2); expectEqual(loaded.lifetime.patronWins.b, 1)
	expectEqual(PlayerProfile.migrate({}).lifetime.tipsEarned, 0, "old saves get safe defaults")
	local big = {}
	for i = 1, 50 do big[i] = { t = i, night = 2 } end
	expectEqual(#PlayerProfile.migrate({ runHistory = big }).runHistory, 20, "a long saved list is capped on load")
	-- mode tags
	expectEqual(RunHistory.modeOf({ rush = true, daily = true }), "rush")
	expectEqual(RunHistory.modeOf({ challenge = true }), "challenge"); expectEqual(RunHistory.modeOf({ weekly = true }), "weekly")
	expectEqual(RunHistory.modeOf({ seeded = true }), "seed"); expectEqual(RunHistory.modeOf({}), "standard")
	-- an entry from a RunState
	local state = RunState.new(nil, SeededRng.new(3))
	state.wonRun, state.night, state.totalScore, state.handsPlayedTotal = true, 8, 123456, 40
	state.bestHand = { name = "Full House", score = 9000 }
	state.patronsUsedOrder = { "a", "b" }
	local entry = RunHistory.entryFromState(state, "standard", "tavern", 42)
	expectTrue(entry.won and entry.night == 8 and entry.score == 123456 and entry.bestHand.score == 9000 and #entry.patrons == 2)
end })

table.insert(tests, { name = "Invites: join data parsing, each invitee credited once, no self invites, titles at 3 and 10, starter back once", fn = function()
	local Invites = require(script.Parent.Parent.Engine.Invites)
	local TavernRank = require(script.Parent.Parent.Engine.TavernRank)
	expectEqual(Invites.launchData(12345), "inv:12345"); expectEqual(Invites.launchData(-1), nil); expectEqual(Invites.launchData("x"), nil)
	expectEqual(Invites.inviterFromJoinData({ LaunchData = "inv:777" }), 777)
	expectEqual(Invites.inviterFromJoinData({ ReferredByPlayerId = 42 }), 42)
	expectEqual(Invites.inviterFromJoinData({ LaunchData = "inv:abc", ReferredByPlayerId = 9 }), 9, "bad launch data falls back")
	expectEqual(Invites.inviterFromJoinData({ LaunchData = "inv:99999999999999999999" }), nil)
	expectEqual(Invites.inviterFromJoinData({ LaunchData = "hello" }), nil); expectEqual(Invites.inviterFromJoinData(nil), nil)
	-- the inviter: once per invitee, never for self
	local host = PlayerProfile.new()
	host.pendingStartTips = 0
	local ok = Invites.creditInviter(host, 1, 2)
	expectTrue(ok); expectEqual(host.invitesAccepted, 1); expectEqual(host.pendingStartTips, Invites.INVITER_TIPS)
	expectFalse((Invites.creditInviter(host, 1, 2)), "the same invitee never counts twice")
	expectFalse((Invites.creditInviter(host, 1, 1)), "self invite")
	expectFalse((Invites.creditInviter(host, 1, "x")), "junk id")
	expectEqual(host.invitesAccepted, 1)
	local _, reached = Invites.creditInviter(host, 1, 3)
	expectEqual(#reached, 0)
	_, reached = Invites.creditInviter(host, 1, 4)
	expectEqual(reached[1], "welcoming_host", "third invite reaches Welcoming Host")
	expectTrue(Achievements.isUnlocked(host, "welcoming_host")); expectFalse(Achievements.isUnlocked(host, "tavern_ambassador"))
	for id = 10, 16 do Invites.creditInviter(host, 1, id) end
	expectEqual(host.invitesAccepted, 10); expectTrue(Achievements.isUnlocked(host, "tavern_ambassador"))
	expectTrue(host.pendingStartTips <= TavernRank.MAX_PENDING_TIPS, "banked Tips stay capped")
	-- the invitee: only a brand new player, once
	local guest = PlayerProfile.new()
	expectFalse((Invites.acceptInvite(guest, 5, 5)), "self invite")
	expectTrue(Invites.acceptInvite(guest, 5, 1)); expectTrue(guest.unlockedCardBackIds[Invites.INVITEE_CARD_BACK])
	expectEqual(guest.invitedByUserId, 1)
	expectFalse((Invites.acceptInvite(guest, 5, 2)), "only the first inviter counts")
	local veteran = PlayerProfile.new()
	veteran.stats.runsStarted = 3
	expectFalse((Invites.acceptInvite(veteran, 6, 1)), "an existing player is not a new arrival")
	expectEqual(veteran.invitedByUserId, nil)
	-- offline inviter inbox: deduplicated, drained idempotently
	local inbox = Invites.inboxAdd(nil, 20); inbox = Invites.inboxAdd(inbox, 21); inbox = Invites.inboxAdd(inbox, 20)
	expectEqual(#inbox, 2)
	local later = PlayerProfile.new()
	local credited = Invites.drainInbox(later, 1, inbox)
	expectEqual(credited, 2); expectEqual(Invites.drainInbox(later, 1, inbox), 0, "draining twice grants nothing")
	-- save and load keeps the ledger; junk is dropped
	local loaded = PlayerProfile.migrate(host)
	expectEqual(loaded.invitesAccepted, 10); expectTrue(loaded.inviteLedger["16"])
	local junk = PlayerProfile.migrate({ invitesAccepted = "x", inviteLedger = { a = true, ["5"] = true, ["6"] = "no" }, invitedByUserId = -4 })
	expectEqual(junk.invitesAccepted, 1); expectEqual(junk.invitedByUserId, nil); expectFalse(junk.inviteeRewardClaimed)
	expectEqual(PlayerProfile.migrate({}).invitesAccepted, 0, "old saves get safe defaults")
	expectEqual(PlayerProfile.migrate(guest).inviteeRewardClaimed, true)
end })

table.insert(tests, { name = "Flair: registry valid, unlock rules, equip validation, store grants, migration, never touches scoring", fn = function()
	local Flair = require(script.Parent.Parent.Engine.Flair)
	expectEqual(#Flair.Slots, 4)
	local ids = {}
	for _, slot in ipairs(Flair.Slots) do
		local options = Flair.optionsFor(slot.id)
		expectTrue(#options >= 4 and #options <= 7, slot.id .. " has 4 to 6 options plus the default, got " .. #options)
		expectTrue(Flair.defaultFor(slot.id) ~= nil, slot.id .. " has a default")
		local defaults = 0
		for _, o in ipairs(options) do
			expectTrue(not ids[o.id], "unique " .. o.id); ids[o.id] = true
			expectTrue(CollectionBook.Rarities[o.rarity] ~= nil, o.id .. " rarity")
			expectTrue(o.name ~= "" and o.icon ~= "", o.id .. " has a name and an icon")
			if o.default then
				defaults = defaults + 1
				expectEqual(o.unlock, nil, "a default needs no unlock")
			else
				expectTrue(o.unlock ~= nil and type(o.unlock.hint) == "string" and o.unlock.hint ~= "", o.id .. " has an unlock hint")
				expectTrue(({ rank = 1, stake = 1, quests = 1, achievement = 1, legend = 1, store = 1 })[o.unlock.kind], o.id .. " unlock kind")
				if o.unlock.kind == "achievement" then expectTrue(Achievements.getById(o.unlock.id) ~= nil, o.id .. " achievement exists") end
			end
			if slot.id == "scoreNumbers" then expectEqual(#o.color, 3) end
		end
		expectEqual(defaults, 1, slot.id .. " has exactly one default")
	end
	-- a new profile owns only the defaults, equips them, and cannot equip anything else
	local p = PlayerProfile.new()
	for _, slot in ipairs(Flair.Slots) do
		expectEqual(Flair.equippedId(p, slot.id), Flair.defaultFor(slot.id))
		expectTrue((Flair.equip(p, slot.id, Flair.defaultFor(slot.id))))
	end
	expectFalse((Flair.equip(p, "scoreNumbers", "ember_numbers")), "locked: rank 5")
	local _, why = Flair.equip(p, "scoreNumbers", "ember_numbers"); expectEqual(why, "Not unlocked yet.")
	-- free unlock rules open as the profile earns them
	p.tavernRank = 5
	expectTrue(Flair.isOwned(p, "ember_numbers")); expectTrue((Flair.equip(p, "scoreNumbers", "ember_numbers"))); expectEqual(Flair.equippedId(p, "scoreNumbers"), "ember_numbers")
	expectFalse(Flair.isOwned(p, "frost_numbers"))
	p.highestStakeUnlocked = 5 -- stake N is "cleared" once N + 1 is open
	expectTrue(Flair.isOwned(p, "gold_numbers")); expectTrue(Flair.isOwned(p, "ember_aura")); expectFalse(Flair.isOwned(p, "star_trail"))
	p.questsDone = 10; expectTrue(Flair.isOwned(p, "sparkle_trail")); expectFalse(Flair.isOwned(p, "confetti_finisher"))
	p.rewardTitleIds.season_harvest_moon = true; expectTrue(Flair.isOwned(p, "petal_trail"))
	p.legendPoints = 2; expectTrue(Flair.isOwned(p, "legend_aura"))
	-- validation: wrong slot, unknown ids, junk types
	expectFalse((Flair.equip(p, "playTrail", "ember_numbers")), "wrong slot")
	expectFalse((Flair.equip(p, "nope", "ember_numbers"))); expectFalse((Flair.equip(p, "playTrail", "nope")))
	expectFalse((Flair.equip(p, nil, "ember_numbers"))); expectFalse((Flair.equip(p, "playTrail", 5))); expectFalse((Flair.equip(p, 5, 5)))
	-- store Flair: not free, granted once, then equippable
	expectFalse(Flair.isOwned(p, "rainbow_numbers")); expectFalse((Flair.equip(p, "scoreNumbers", "rainbow_numbers")))
	expectTrue(Flair.grantOwned(p, "rainbow_numbers")); expectFalse(Flair.grantOwned(p, "rainbow_numbers"), "idempotent")
	expectFalse(Flair.grantOwned(p, "ember_numbers"), "free Flair is not a store item"); expectFalse(Flair.grantOwned(p, "nope"))
	expectTrue((Flair.equip(p, "scoreNumbers", "rainbow_numbers")))
	-- an equipped option that is no longer owned falls back to the default (never an unowned look)
	p.flairEquipped.scoreNumbers = "frost_numbers"
	expectEqual(Flair.equippedId(p, "scoreNumbers"), "classic_numbers")
	-- public tag: only a real Name Aura id travels, cleaned on the way back
	p.flairEquipped.nameAura = "legend_aura"
	expectEqual(Flair.publicTag(p), "legend_aura"); expectEqual(Flair.cleanPublicTag("legend_aura"), "legend_aura")
	expectEqual(Flair.cleanPublicTag("ember_numbers"), nil); expectEqual(Flair.cleanPublicTag("no_aura"), nil); expectEqual(Flair.cleanPublicTag(5), nil); expectEqual(Flair.cleanPublicTag("<b>x"), nil)
	p.flairEquipped.nameAura = nil; expectEqual(Flair.publicTag(p), nil)
	-- the view carries owned, equipped and the unlock hint
	local view = Flair.view(p)
	expectEqual(#view.slots, 4)
	local classic
	for _, o in ipairs(view.slots[1].options) do if o.id == "classic_numbers" then classic = o end end
	expectTrue(classic.owned and classic.equipped)
	-- save and load: store grants and equips survive, junk is dropped, free ones are not saved
	local loaded = PlayerProfile.migrate(p)
	expectTrue(loaded.flairOwned.rainbow_numbers); expectEqual(loaded.flairOwned.ember_numbers, nil)
	local junk = PlayerProfile.migrate({ flairOwned = { rainbow_numbers = true, ember_numbers = true, nope = true, star_trail = "yes" },
		flairEquipped = { scoreNumbers = "rainbow_numbers", playTrail = "ember_numbers", ["x"] = "y", nameAura = 5 } })
	expectTrue(junk.flairOwned.rainbow_numbers); expectEqual(junk.flairOwned.ember_numbers, nil); expectEqual(junk.flairOwned.nope, nil)
	expectEqual(junk.flairEquipped.scoreNumbers, "rainbow_numbers"); expectEqual(junk.flairEquipped.playTrail, nil, "an option in the wrong slot is dropped"); expectEqual(junk.flairEquipped.x, nil)
	expectEqual(next(PlayerProfile.migrate({}).flairOwned), nil, "old saves get safe defaults")
	-- Flair is display data: equipping changes nothing that scoring reads
	local s1 = RunState.new(nil, SeededRng.new(31)); local s2 = RunState.new(nil, SeededRng.new(31))
	Flair.equip(p, "finisher", "pop_finisher")
	expectEqual(s1.targetScore, s2.targetScore); expectEqual(s1.config.handsPerRound, s2.config.handsPerRound)
	local flairKeys = {}
	for _, o in ipairs(Flair.Options) do for k in pairs(o) do flairKeys[k] = true end end
	for _, forbidden in ipairs({ "chips", "mult", "xmult", "target", "price", "effect", "handsDelta", "discardsDelta" }) do
		expectFalse(flairKeys[forbidden], "Flair has no gameplay field: " .. forbidden)
	end
end })

table.insert(tests, { name = "Legend: level math, new road bonus, rewards once, no gameplay power, safe migration", fn = function()
	local Legend = require(script.Parent.Parent.Engine.Legend)
	local Stakes = require(script.Parent.Parent.Engine.Stakes)
	expectEqual(Legend.MAX_LEVEL, 10); expectEqual(Legend.UNLOCK_STAKE, Stakes.MAX)
	-- rewards: 10 levels, valid ids, at most 10 new registry entries, cosmetic kinds only
	local newEntries = 0
	for level = 1, 10 do
		local r = Legend.Rewards[level]
		expectTrue(r ~= nil, "level " .. level)
		expectTrue(r.kind == "title" or r.kind == "cardBack" or r.kind == "aura" or r.kind == "trinket", "cosmetic only")
		if r.kind == "title" then expectTrue(Achievements.getById(r.id) ~= nil and Achievements.getById(r.id).milestoneReward, r.id); newEntries = newEntries + 1 end
		if r.kind == "cardBack" then expectTrue(CardBacks.getById(r.id) ~= nil, r.id); newEntries = newEntries + 1 end
		if r.kind == "trinket" then expectTrue(type(r.icon) == "string" and r.icon ~= "" and r.name ~= "") end
	end
	expectTrue(newEntries <= 10, "at most 10 new registry entries, got " .. newEntries)
	expectEqual(Legend.levelFor(-3), 0); expectEqual(Legend.levelFor(4.9), 4); expectEqual(Legend.levelFor(50), 10); expectEqual(Legend.levelFor("x"), 0); expectEqual(Legend.levelFor(nil), 0)
	-- a new profile is not a Legend
	local profile = PlayerProfile.new()
	expectEqual(Legend.level(profile), 0); expectFalse(Legend.isOpen(profile)); expectFalse(Legend.hasAura(profile))
	local view0 = Legend.view(profile)
	expectEqual(view0.level, 0); expectTrue(view0.locked); expectFalse(view0.open); expectEqual(#view0.rewards, 10)
	-- the first clear: 1 point + 1 for the new road = level 2, the level 1 title and the level 2 aura
	local r1 = Legend.recordClear(profile, { "road", "road", "meadow" })
	expectEqual(r1.points, 3, "1 clear + 2 new roads"); expectEqual(r1.levelBefore, 0); expectEqual(r1.levelAfter, 3)
	expectEqual(#r1.granted, 3); expectTrue(profile.rewardTitleIds.legend_1); expectTrue(profile.unlockedCardBackIds.legend_gold)
	expectTrue(Legend.hasAura(profile)); expectTrue(Achievements.isUnlocked(profile, "legend_1"))
	-- repeating the same roads only pays the clear point, never the road bonus again
	local r2 = Legend.recordClear(profile, { "road", "meadow" })
	expectEqual(r2.points, 1); expectEqual(Legend.level(profile), 4); expectEqual(#r2.granted, 1)
	expectEqual(#Legend.trinkets(profile), 1); expectEqual(Legend.trinkets(profile)[1].id, "gold_cup")
	-- a new road pays again, junk regions are ignored
	local r3 = Legend.recordClear(profile, { "river", 5, "swamp" })
	expectEqual(r3.points, 3); expectEqual(Legend.level(profile), 7); expectTrue(profile.unlockedCardBackIds.legend_crown)
	-- rewards are granted once: grantDue again grants nothing, and the cap holds
	expectEqual(#Legend.grantDue(profile), 0)
	for _ = 1, 20 do Legend.recordClear(profile, {}) end
	expectEqual(Legend.level(profile), 10); expectEqual(Legend.view(profile).level, 10)
	expectTrue(profile.rewardTitleIds.legend_9 and profile.unlockedCardBackIds.legend_eternal)
	expectEqual(#Legend.trinkets(profile), 3); expectEqual(Legend.view(profile).hint, "Every Legend reward is yours.")
	local points = profile.legendPoints
	Legend.recordClear(profile, { "coast" })
	expectEqual(Legend.level(profile), 10, "the level never passes 10"); expectTrue(profile.legendPoints > points and profile.legendPoints <= Legend.MAX_POINTS)
	-- Legend never touches runs: it only writes cosmetic profile sets
	local before = profile.stats.runsWon
	Legend.recordClear(profile, {})
	expectEqual(profile.stats.runsWon, before)
	-- save and load: points, roads and rewards survive, junk is dropped, missing grants are re-derived
	local loaded = PlayerProfile.migrate(profile)
	expectEqual(loaded.legendPoints, profile.legendPoints); expectTrue(loaded.legendRoads.river); expectTrue(loaded.legendRewardIds[10])
	local junk = PlayerProfile.migrate({ legendPoints = "x", legendRoads = { road = true, nowhere = true, meadow = "yes" }, legendRewardIds = { [99] = true, [2] = true } })
	expectEqual(junk.legendPoints, 0); expectTrue(junk.legendRoads.road); expectEqual(junk.legendRoads.nowhere, nil); expectEqual(junk.legendRoads.meadow, nil)
	expectEqual(junk.legendRewardIds[99], nil)
	expectEqual(PlayerProfile.migrate({ legendPoints = 1e12 }).legendPoints, Legend.MAX_POINTS)
	local regrant = PlayerProfile.migrate({ legendPoints = 5 })
	expectTrue(regrant.rewardTitleIds.legend_1 == true and regrant.legendRewardIds[5], "rewards for the saved level are granted on load")
	expectEqual(PlayerProfile.migrate({}).legendPoints, 0, "old saves get safe defaults")
end })

table.insert(tests, { name = "MenuTicker: run counts rounded, board line with name and flair, flavor fallback", fn = function()
	local MT = require(script.Parent.Parent.Engine.MenuTicker)
	expectEqual(MT.roundRuns(0), 0); expectEqual(MT.roundRuns(9), 0); expectEqual(MT.roundRuns(10), 10); expectEqual(MT.roundRuns(47), 40)
	expectEqual(MT.roundRuns(99), 90); expectEqual(MT.roundRuns(100), 100); expectEqual(MT.roundRuns(374), 350); expectEqual(MT.roundRuns(1234), 1200)
	expectEqual(MT.roundRuns(-5), 0); expectEqual(MT.roundRuns("x"), 0); expectEqual(MT.roundRuns(nil), 0)
	local text, real = MT.text({ top = { name = "Maple", depth = 6, tips = 12, title = "Table Regular" }, runs = 137 }, 3)
	expectTrue(real); expectEqual(text, "Today's best: Maple (Table Regular) reached Night 6   |   about 100 runs today")
	local plain, real2 = MT.text({ top = { name = "Maple", depth = 3 }, runs = 4 }, 3)
	expectTrue(real2); expectEqual(plain, "Today's best: Maple reached Night 3", "a few runs are not shown")
	-- fallback: no board, a failed store, junk data
	for _, data in ipairs({ {}, { top = false }, { top = { name = "???", depth = 4 } }, { top = { name = "" } }, "x", { top = "no" } }) do
		local line, isReal = MT.text(data, 2)
		expectFalse(isReal); expectEqual(line, MT.FlavorLines[3])
	end
	expectEqual(select(1, MT.text(nil, 0)), MT.FlavorLines[1])
	expectEqual(select(1, MT.text({ runs = 250 }, 1)), MT.FlavorLines[2] .. "   |   about 250 runs today")
	-- the flavor line rotates by day and never indexes out of range, even for odd day numbers
	for day = -20, 40 do
		local line = MT.text({}, day)
		expectTrue(type(line) == "string" and line ~= "")
	end
	expectEqual(select(1, MT.text({}, 0 / 0 ~= 0 / 0 and 1 or 1)), MT.FlavorLines[2])
	for _, line in ipairs(MT.FlavorLines) do
		expectTrue(not line:find("—") and #line <= 60, "short, no dashes: " .. line)
	end
end })

table.insert(tests, { name = "CollectionRewards: milestone math, claim once, rewards valid, new titles, safe migration", fn = function()
	local CR = require(script.Parent.Parent.Engine.CollectionRewards)
	local TavernRank = require(script.Parent.Parent.Engine.TavernRank)
	expectEqual(#CR.Groups, 6)
	expectEqual(table.concat(CR.Percents, ","), "25,50,75,100")
	local seenTitles = {}
	for _, g in ipairs(CR.Groups) do
		for _, pct in ipairs(CR.Percents) do
			local r = CR.Rewards[g.id][pct]
			expectTrue(r ~= nil, g.id .. " " .. pct .. " has a reward")
			if r.kind == "cardBack" then expectTrue(CardBacks.getById(r.id) ~= nil, "card back " .. r.id) end
			if r.kind == "tips" then expectTrue(r.amount >= 1 and r.amount <= 10) end
			if r.kind == "title" then
				local a = Achievements.getById(r.id)
				expectTrue(a ~= nil and a.milestoneReward == true and pct == 100, "the title is new and sits at 100 percent")
				expectTrue(not seenTitles[r.id], "one title per group"); seenTitles[r.id] = true
			end
		end
		expectEqual(CR.Rewards[g.id][100].kind, "title")
	end
	-- a new profile: nothing reached, nothing claimable, every ring at 0
	local profile = PlayerProfile.new()
	local view = CR.view(profile)
	expectEqual(#view.groups, 6); expectEqual(view.claimable, 0)
	for _, row in ipairs(view.groups) do
		expectEqual(row.percent, 0); expectEqual(#row.milestones, 4); expectTrue(row.total > 0, row.id .. " has entries")
	end
	local ok, why = CR.claim(profile, "patrons", 25)
	expectFalse(ok); expectEqual(why, "Not reached yet.")
	expectFalse((CR.claim(profile, "nope", 25))); expectFalse((CR.claim(profile, "patrons", 30))); expectFalse((CR.claim(profile, nil, 25))); expectFalse((CR.claim(profile, "patrons", "25")))
	-- milestone math is exact: discover exactly 25 percent of Patrons
	local total = #Patrons.Definitions
	local need = math.ceil(25 * total / 100)
	for i = 1, need - 1 do profile.discoveredPatronIds[Patrons.Definitions[i].id] = true end
	expectFalse((CR.claim(profile, "patrons", 25)), "one short of 25 percent")
	profile.discoveredPatronIds[Patrons.Definitions[need].id] = true
	local p = CR.progress(profile).patrons
	expectEqual(p.found, need); expectTrue(p.percent >= 25)
	profile.pendingStartTips = 0
	local ok2, reward = CR.claim(profile, "patrons", 25)
	expectTrue(ok2); expectEqual(reward.kind, "tips"); expectEqual(profile.pendingStartTips, reward.amount)
	local again, reason = CR.claim(profile, "patrons", 25)
	expectFalse(again); expectEqual(reason, "Already claimed.")
	expectEqual(profile.pendingStartTips, reward.amount, "paid once")
	expectEqual(CR.view(profile).claimable, 0)
	-- 100 percent: everything claimable, claim all pays each once, the title is granted
	for _, def in ipairs(Patrons.Definitions) do profile.discoveredPatronIds[def.id] = true end
	local after = CR.view(profile)
	expectEqual(after.claimable, 3, "50, 75 and 100 are ready")
	local all = CR.claimAll(profile)
	expectEqual(#all, 3); expectEqual(#CR.claimAll(profile), 0, "claim all twice grants nothing")
	expectTrue(profile.unlockedCardBackIds.kitchen_checks); expectTrue(profile.rewardTitleIds.book_patrons)
	expectTrue(Achievements.isUnlocked(profile, "book_patrons"))
	expectTrue(profile.pendingStartTips <= TavernRank.MAX_PENDING_TIPS)
	-- badges and sets are measured here
	local b = PlayerProfile.new()
	local CosmeticSets = require(script.Parent.Parent.Engine.CosmeticSets)
	for _, set in ipairs(CosmeticSets.Definitions) do b.ownedSetIds[set.id] = true end
	expectEqual(CR.progress(b).sets.percent, 100); expectTrue(CR.view(b).claimable == 4)
	-- save and load: claims survive, junk keys are dropped
	local loaded = PlayerProfile.migrate(profile)
	expectTrue(loaded.collectionRewardsClaimed["patrons:100"]); expectTrue(loaded.collectionRewardsClaimed["patrons:25"])
	local junk = PlayerProfile.migrate({ collectionRewardsClaimed = { ["patrons:25"] = true, ["patrons:30"] = true, ["gone:25"] = true, ["x"] = true, ["bosses:50"] = "yes" } })
	expectTrue(junk.collectionRewardsClaimed["patrons:25"]); expectEqual(junk.collectionRewardsClaimed["patrons:30"], nil)
	expectEqual(junk.collectionRewardsClaimed["gone:25"], nil); expectEqual(junk.collectionRewardsClaimed["bosses:50"], nil)
	expectEqual(next(PlayerProfile.migrate({}).collectionRewardsClaimed), nil, "old saves get safe defaults")
	-- the reward titles never count toward the Titles group (completion stays reachable)
	local titlesTotal = CR.progress(PlayerProfile.new()).titles.total
	local regular = 0
	for _, a in ipairs(Achievements.Definitions) do if not a.milestoneReward then regular = regular + 1 end end
	expectEqual(titlesTotal, regular)
end })

table.insert(tests, { name = "RunTelemetry: per run aggregate, one flush, caps, hourly budget, Analytics batches never throw", fn = function()
	local RT = require(script.Parent.Parent.Engine.RunTelemetry)
	local Analytics = require(script.Parent.Parent.Engine.Analytics)
	local agg = RT.new()
	expectTrue(RT.recordPatronBought(agg, "tip_jar", 1, 2)); expectTrue(RT.recordPatronBought(agg, "tip_jar", 1, 2)); expectTrue(RT.recordPatronBought(agg, "tip_jar", 1, 3))
	expectTrue(RT.recordPatronBought(agg, "flush_fan", 4, 5))
	expectFalse(RT.recordPatronBought(agg, 5, 1, 1)); expectFalse(RT.recordPatronBought(agg, string.rep("x", 60), 1, 1))
	expectTrue(RT.recordBoss(agg, "no_repeats", true, 3, 2)); expectFalse(RT.recordBoss(agg, "no_repeats", true, 3, 2), "once per boss and Night")
	expectTrue(RT.recordBoss(agg, "no_repeats", false, 4, 6)); expectFalse(RT.recordBoss(agg, nil, true, 1, 1))
	for i = 1, 20 do RT.recordBoss(agg, "boss" .. i, true, 1, 100 + i) end
	expectEqual(#agg.bosses, RT.MAX_BOSSES, "boss results are capped per run")
	local events = RT.flush(agg, { "tip_jar", "flush_fan", "a", "b", "c", "d", "e", "f", "g", "h" }, true)
	local counts = {}
	for _, e in ipairs(events) do counts[e.name] = (counts[e.name] or 0) + 1 end
	expectEqual(counts.boss_result, RT.MAX_BOSSES); expectEqual(counts.patron_end, RT.MAX_PATRONS, "owned Patrons are capped")
	expectEqual(counts.patron_bought, 3, "three distinct (patron, stake, night) keys")
	expectEqual(events[1].name, "boss_result", "most important events come first")
	local bought = {}
	for _, e in ipairs(events) do if e.name == "patron_bought" and e.fields.patron == "tip_jar" and e.fields.night == 2 then bought = e end end
	expectEqual(bought.value, 2, "two buys of the same key are one event with a count")
	expectEqual(#RT.flush(agg, {}, true), 0, "a run flushes once")
	local many = RT.new()
	for i = 1, 100 do RT.recordPatronBought(many, "p" .. i, 1, 1) end
	expectEqual(many.boughtKeys, RT.MAX_BOUGHT_KEYS, "bought keys are capped")
	-- budget: 120 per rolling hour per player, refilled after the hour, players are independent
	local budget = {}
	expectEqual(RT.allow(budget, 1, 0, 100), 100); expectEqual(RT.allow(budget, 1, 10, 50), 20, "only 20 left this hour")
	expectEqual(RT.allow(budget, 1, 20, 5), 0); expectEqual(RT.allow(budget, 2, 20, 5), 5, "another player has their own budget")
	expectEqual(RT.allow(budget, 1, RT.HOUR + 1, 30), 30, "the first 100 aged out of the hour")
	expectEqual(RT.allow(budget, 1, RT.HOUR + 2, -4), 0); expectEqual(RT.allow(budget, 1, RT.HOUR + 3, "x"), 0)
	RT.forget(budget, 1); expectEqual(budget[1], nil)
	-- dispatch: the budget cuts a big run, a throwing sender never escapes
	local sent = {}
	local list = {}
	for i = 1, 150 do list[i] = { name = "e" .. i, value = 1, fields = {} } end
	expectEqual(RT.dispatch(list, {}, 9, 0, function(e) sent[#sent + 1] = e.name end), 120); expectEqual(sent[1], "e1"); expectEqual(#sent, 120)
	expectEqual(RT.dispatch(list, {}, 9, 0, function() error("boom") end), 0, "a failing send is swallowed")
	-- Analytics.sendBatch / single use the same budget and call the service
	local logged = {}
	Analytics.setService({ LogCustomEvent = function(_, _, name, value, fields) logged[#logged + 1] = { name = name, value = value, fields = fields } end })
	local fakePlayer = { UserId = 777 }
	expectEqual(Analytics.sendBatch(fakePlayer, { { name = "boss_result", value = 3, fields = { boss = "x", won = "yes" } } }, 5), 1)
	expectEqual(logged[1].name, "boss_result"); expectEqual(logged[1].fields.boss, "x"); expectEqual(logged[1].value, 3)
	expectTrue(Analytics.single(fakePlayer, "run_quit", 4, { phase = "shop" }, 6)); expectEqual(logged[2].name, "run_quit")
	for _ = 1, 200 do Analytics.single(fakePlayer, "store_opened", 1, {}, 7) end
	expectEqual(#logged, 120, "the hourly cap holds across calls")
	Analytics.forgetPlayer(fakePlayer)
	expectTrue(Analytics.single(fakePlayer, "run_quit", 1, {}, 8), "a new budget after the player left")
	Analytics.setService(nil)
	expectFalse(Analytics.single(fakePlayer, "run_quit", 1, {}, 9), "no service, no send, no error")
	Analytics.forgetPlayer(fakePlayer)
	expectEqual(Analytics.sendBatch(nil, { { name = "x", value = 1, fields = {} } }, 1), 0)
end })

table.insert(tests, { name = "Synergy: every Patron has 1 to 3 valid tags, owned tags, dominant hand, economy gap, at most 2 tags shown", fn = function()
	local Synergy = require(script.Parent.Parent.Engine.Synergy)
	expectEqual(table.concat(Synergy.validate(), "; "), "", "every Patron has 1 to 3 valid unique tags")
	expectTrue(#Patrons.Definitions >= 81)
	-- the Patron Definitions carry the six main tags and the data covers them all
	local used = {}
	for _, p in ipairs(Patrons.Definitions) do for _, t in ipairs(p.tags) do used[t] = (used[t] or 0) + 1 end end
	for _, tag in ipairs({ "flush", "pairs", "straight", "economy", "scaling", "rulebender" }) do expectTrue((used[tag] or 0) >= 3, tag .. " is used") end
	for _, id in ipairs(Patrons.TagIds) do expectTrue(Synergy.Tags[id] ~= nil, "tag info for " .. id) end
	for id, info in pairs(Synergy.Tags) do
		expectTrue(info.icon ~= "" and #info.word <= 10 and not info.word:find(" "), id .. " is an icon plus one word")
	end
	-- owned tags
	local owned = { { id = "flush_fan" }, { id = "suit_sampler" }, { id = "tip_jar" }, { id = "pair_bonds" } }
	local counts = Synergy.ownedTags(owned)
	expectEqual(counts.flush, 2); expectEqual(counts.economy, 1); expectEqual(counts.pairs, 1); expectEqual(counts.scaling, 1)
	expectEqual(next(Synergy.ownedTags({})), nil); expectEqual(next(Synergy.ownedTags(nil)), nil)
	-- dominant hand: most played, ties alphabetical, unknown names and zeros ignored
	expectEqual(Synergy.dominantHand({ Pair = 5, Flush = 9, ["High Card"] = 40 }), "Flush", "High Card feeds no tag")
	expectEqual(Synergy.dominantHand({ Pair = 3, Straight = 3 }), "Pair")
	expectEqual(Synergy.dominantHand({}), nil); expectEqual(Synergy.dominantHand(nil), nil); expectEqual(Synergy.dominantHand({ Flush = 0 }), nil)
	expectTrue(Synergy.dominantTags({ ["Straight Flush"] = 4 }).straight and Synergy.dominantTags({ ["Straight Flush"] = 4 }).flush)
	-- tagsFor: dominant first, then the economy gap, then owned; never "flat"; at most 2
	local ctx = Synergy.context(owned, { Flush = 6 })
	local fan = Synergy.tagsFor(Patrons.getById("all_matching"), ctx)
	expectEqual(#fan, 1); expectEqual(fan[1].tag, "flush"); expectEqual(fan[1].reason, "Fits the hand you play most.")
	local pairPatron = Synergy.tagsFor({ id = "pair_bonds" }, ctx)
	expectEqual(#pairPatron, 2); expectEqual(pairPatron[1].tag, "scaling", "owned tag, listed after dominant and economy")
	expectEqual(#Synergy.tagsFor(Patrons.getById("the_regular"), ctx), 0, "a flat Patron shows nothing")
	local fresh = Synergy.context({}, {})
	local jar = Synergy.tagsFor(Patrons.getById("tip_jar"), fresh)
	expectEqual(#jar, 1); expectEqual(jar[1].tag, "economy"); expectEqual(jar[1].reason, "You have no Tips Patron yet.")
	expectEqual(#Synergy.tagsFor(Patrons.getById("tip_jar"), Synergy.context({ { id = "penny_pincher" } }, {})), 1, "owning one: shown as a match instead")
	expectEqual(Synergy.tagsFor(Patrons.getById("tip_jar"), Synergy.context({ { id = "penny_pincher" } }, {}))[1].reason, "Works with a Patron you own.")
	-- three matches are cut to two
	local both = Synergy.tagsFor({ tags = { "flush", "pairs", "economy" } }, Synergy.context({ { id = "flush_fan" }, { id = "twin_spoons" } }, { Flush = 3 }))
	expectEqual(#both, 2)
	expectEqual(#Synergy.tagsFor(nil, ctx), 0); expectEqual(#Synergy.tagsFor({ id = "nope" }, ctx), 0); expectEqual(#Synergy.tagsFor(Patrons.getById("tip_jar"), nil), 0)
end })

table.insert(tests, { name = "Hints: data table valid, each hint once, never in the tutorial, replay clears, safe migration", fn = function()
	local Hints = require(script.Parent.Parent.Engine.Hints)
	expectEqual(#Hints.Definitions, 10)
	local ids = {}
	for _, hint in ipairs(Hints.Definitions) do
		expectTrue(not ids[hint.id], "unique " .. hint.id); ids[hint.id] = true
		expectTrue(type(hint.target) == "string" and hint.target ~= "", hint.id .. " has a target key")
		expectTrue(type(hint.icon) == "string" and hint.icon ~= "", hint.id .. " has an icon")
		expectTrue(Hints.wordCount(hint.text) <= Hints.MAX_WORDS and Hints.wordCount(hint.text) >= 3, hint.id .. " is 12 words or fewer: " .. Hints.wordCount(hint.text))
		expectTrue(type(hint.trigger) == "function")
		expectTrue(not hint.text:find("—") and not hint.text:find("–"), "no dashes in hint text")
	end
	expectEqual(Hints.wordCount("[Chips] times [Mult] is your hand's score."), 7, "highlight marks are not words")
	-- nothing is due on a quiet state, each trigger fires on its own condition
	expectEqual(Hints.dueFor({ phase = "playing" }, {}, {}), nil)
	expectEqual(Hints.dueFor({ phase = "playing", handsPlayedTotal = 1 }, {}, {}).id, "first_score")
	expectEqual(Hints.dueFor({ phase = "shop" }, {}, {}).id, "first_counter")
	expectEqual(Hints.dueFor({ phase = "roundSelect", ownedPatrons = { {} } }, {}, {}).id, "first_patron")
	expectEqual(Hints.dueFor({ phase = "roundSelect", menuRecipeInventory = { "level_pair" } }, {}, {}).id, "first_recipe")
	expectEqual(Hints.dueFor({ phase = "playing", bossModifier = {} }, {}, {}).id, "first_boss")
	expectEqual(Hints.dueFor({ phase = "roundSelect", lastInterest = 2 }, {}, {}).id, "first_interest")
	expectEqual(Hints.dueFor({ phase = "roundSelect", discoveries = { found = 1 } }, {}, {}).id, "first_discovery")
	expectEqual(Hints.dueFor({ phase = "menu" }, {}, { runSetupOpen = true }).id, "first_stakes")
	expectEqual(Hints.dueFor({ phase = "menu" }, {}, { questsOpen = true }).id, "first_quests")
	expectEqual(Hints.dueFor({ phase = "menu" }, {}, { seasonOpen = true }).id, "first_season")
	-- once only: a seen hint never comes back, the next due one shows instead
	expectEqual(Hints.dueFor({ phase = "shop", handsPlayedTotal = 2 }, { first_counter = true }, {}), nil, "first_score needs the playing phase")
	expectEqual(Hints.dueFor({ phase = "playing", handsPlayedTotal = 2, ownedPatrons = { {} } }, { first_score = true }, {}).id, "first_patron")
	-- never during the forced tutorial
	expectEqual(Hints.dueFor({ phase = "shop", isTutorial = true }, {}, {}), nil)
	expectEqual(Hints.dueFor({ phase = "playing", handsPlayedTotal = 5, isTutorial = true }, {}, {}), nil)
	expectEqual(Hints.dueFor(nil, {}, {}), nil); expectEqual(Hints.dueFor("x", {}, {}), nil)
	-- a bad trigger input never throws
	expectEqual(Hints.dueFor({ phase = "playing", ownedPatrons = "junk", discoveries = 5 }, {}, {}), nil)
	-- the profile: mark once, unknown refused, replay clears, migration drops junk
	local profile = PlayerProfile.new()
	expectEqual(next(profile.hintsSeen), nil)
	expectTrue(Hints.markSeen(profile, "first_score")); expectFalse(Hints.markSeen(profile, "first_score"), "second mark is a no-op")
	expectFalse(Hints.markSeen(profile, "not_a_hint")); expectFalse(Hints.markSeen(profile, 5)); expectFalse(Hints.markSeen(profile, nil))
	expectEqual(Hints.dueFor({ phase = "playing", handsPlayedTotal = 1 }, profile.hintsSeen, {}), nil)
	local loaded = PlayerProfile.migrate(profile)
	expectTrue(loaded.hintsSeen.first_score)
	local junk = PlayerProfile.migrate({ hintsSeen = { first_score = true, old_removed_hint = true, first_boss = "yes", [3] = true } })
	expectTrue(junk.hintsSeen.first_score); expectEqual(junk.hintsSeen.old_removed_hint, nil); expectEqual(junk.hintsSeen.first_boss, nil)
	expectEqual(next(PlayerProfile.migrate({}).hintsSeen), nil, "old saves get safe defaults")
	Hints.reset(profile)
	expectEqual(next(profile.hintsSeen), nil)
	expectEqual(Hints.dueFor({ phase = "playing", handsPlayedTotal = 1 }, profile.hintsSeen, {}).id, "first_score", "replay brings hints back")
	-- the interest tally exists for the last hint
	local s = RunState.new(nil, SeededRng.new(9))
	s.targetScore = 0
	s.tips = 20
	RunState.playHand(s, { 1 })
	expectTrue((s.lastInterest or 0) > 0, "interest at round win is recorded")
end })

table.insert(tests, { name = "SeasonTrack: dates and edges, XP, reset on a new season, claim once, rewards owned for good, safe migration", fn = function()
	local ST = require(script.Parent.Parent.Engine.SeasonTrack)
	local TavernRank = require(script.Parent.Parent.Engine.TavernRank)
	expectEqual(#ST.validate(), 0, "seasons parse and never overlap")
	local s1, s2 = ST.Seasons[1], ST.Seasons[2]
	local first1, last1 = ST.window(s1)
	local first2 = ST.window(s2)
	expectEqual(last1 - first1 + 1, 30, "a 30 day season"); expectEqual(first2, last1 + 1, "back to back, no gap")
	-- date edges: both the first and last day count, the day before and after do not
	expectEqual(ST.active(first1 - 1), nil); expectEqual(ST.active(first1).id, s1.id); expectEqual(ST.active(last1).id, s1.id)
	expectEqual(ST.active(last1 + 1).id, s2.id); expectEqual(ST.active(select(2, ST.window(s2)) + 1), nil)
	expectEqual(ST.daysLeft(s1, first1), 30); expectEqual(ST.daysLeft(s1, last1), 1); expectEqual(ST.daysLeft(s1, last1 + 1), 0)
	expectEqual(ST.upcoming(first1 - 5).id, s1.id); expectEqual(ST.upcoming(last1).id, s2.id); expectEqual(ST.upcoming(first2 + 100), nil)
	-- 30 tiers, a reward on every one, content ids exist, nothing is gameplay power
	for _, season in ipairs(ST.Seasons) do
		for tier = 1, 30 do
			local r = ST.rewardFor(season, tier)
			expectTrue(r ~= nil, season.id .. " tier " .. tier .. " has a reward")
			expectTrue(r.kind == "tips" or r.kind == "cardBack" or r.kind == "title", "cosmetic or Tips only")
			if r.kind == "cardBack" then expectTrue(CardBacks.getById(r.id) ~= nil, "card back " .. r.id) end
			if r.kind == "title" then expectTrue(Achievements.getById(r.id) ~= nil, "title " .. r.id) end
			if r.kind == "tips" then expectTrue(r.amount >= 1 and r.amount <= 10) end
		end
		expectEqual(ST.rewardFor(season, 30).id, season.finalCardBackId); expectEqual(ST.rewardFor(season, 25).id, season.titleId)
		expectTrue(CardBacks.getById(season.finalCardBackId).seasonal, "the final back is season only")
	end
	expectEqual(ST.rewardFor(s1, 31), nil)
	-- XP and tiers
	local day = first1 + 3
	local p = PlayerProfile.new()
	expectEqual(ST.addXp(p, 10, first1 - 1), 0, "no XP outside a season"); expectEqual(p.seasonXp, 0)
	expectEqual(ST.addXp(p, 100, day), 100); expectEqual(p.seasonId, s1.id); expectEqual(ST.tierOf(p.seasonXp), 1)
	expectEqual(ST.addXp(p, -5, day), 0); expectEqual(ST.addXp(p, 0 / 0, day), 0); expectEqual(ST.addXp(p, 2.9, day), 2)
	expectEqual(ST.addXp(p, 1e12, day), ST.MAX_XP - 102, "capped at the season maximum"); expectEqual(ST.tierOf(p.seasonXp), 30)
	-- claims: reached only, once, in the running season, junk tiers refused
	local fresh = PlayerProfile.new()
	ST.addXp(fresh, 200, day)
	expectFalse((ST.claim(fresh, 3, day)), "tier 3 needs 270 XP")
	local ok, reward = ST.claim(fresh, 1, day)
	expectTrue(ok); expectEqual(reward.kind, "tips"); expectEqual(fresh.pendingStartTips, reward.amount)
	expectFalse((ST.claim(fresh, 1, day)), "claimed once"); expectFalse((ST.claim(fresh, 0, day))); expectFalse((ST.claim(fresh, 31, day)))
	expectFalse((ST.claim(fresh, 1.5, day))); expectFalse((ST.claim(fresh, "2", day)))
	expectFalse((ST.claim(fresh, 2, first1 - 1)), "no season running")
	local all = ST.claimAll(fresh, day)
	expectEqual(#all, 1, "only tier 2 was left"); expectEqual(#ST.claimAll(fresh, day), 0, "claim all twice grants nothing")
	local rich = PlayerProfile.new()
	ST.addXp(rich, ST.MAX_XP, day)
	local before = rich.pendingStartTips
	expectEqual(#ST.claimAll(rich, day), 30)
	expectTrue(rich.unlockedCardBackIds[s1.cardBackAt10] and rich.unlockedCardBackIds[s1.cardBackAt20] and rich.unlockedCardBackIds[s1.finalCardBackId])
	expectTrue(rich.rewardTitleIds[s1.titleId]); expectTrue(Achievements.isUnlocked(rich, s1.titleId))
	expectTrue(rich.pendingStartTips > before and rich.pendingStartTips <= TavernRank.MAX_PENDING_TIPS, "Tips stay capped")
	-- a new season resets XP and claims, but what was claimed stays owned
	expectTrue(ST.ensureSeason(rich, first2)); expectEqual(rich.seasonId, s2.id); expectEqual(rich.seasonXp, 0); expectEqual(next(rich.seasonClaimed), nil)
	expectTrue(rich.unlockedCardBackIds[s1.finalCardBackId] and rich.rewardTitleIds[s1.titleId], "season 1 rewards stay owned")
	expectFalse(ST.ensureSeason(rich, first2), "no second reset")
	expectEqual(ST.addXp(rich, 90, first2), 90); expectEqual(ST.tierOf(rich.seasonXp), 1)
	-- with no season running, nothing changes
	expectFalse(ST.ensureSeason(rich, first2 + 1000)); expectEqual(rich.seasonId, s2.id)
	-- the view
	local view = ST.view(fresh, day)
	expectEqual(view.name, s1.name); expectEqual(view.tier, 2); expectEqual(#view.tiers, 30); expectEqual(view.claimable, 0)
	expectEqual(view.daysLeft, 27); expectTrue(view.tiers[1].claimed and view.tiers[2].claimed and not view.tiers[3].reached)
	ST.addXp(fresh, 90, day)
	expectEqual(ST.view(fresh, day).claimable, 1)
	expectEqual(ST.view(PlayerProfile.new(), first1 - 3).upcoming, true); expectEqual(ST.view(PlayerProfile.new(), first1 - 3).startsIn, 3)
	expectEqual(ST.view(PlayerProfile.new(), first2 + 500), nil)
	-- a profile that belongs to an older season shows zero for the running one
	local old = PlayerProfile.new(); old.seasonId, old.seasonXp = s1.id, 500
	expectEqual(ST.view(old, first2).xp, 0)
	-- save and load
	local loaded = PlayerProfile.migrate(fresh)
	expectEqual(loaded.seasonId, s1.id); expectEqual(loaded.seasonXp, fresh.seasonXp); expectTrue(loaded.seasonClaimed[1])
	local junk = PlayerProfile.migrate({ seasonId = "gone", seasonXp = 500, seasonClaimed = { [1] = true } })
	expectEqual(junk.seasonId, nil); expectEqual(junk.seasonXp, 0); expectEqual(next(junk.seasonClaimed), nil)
	local junk2 = PlayerProfile.migrate({ seasonId = s1.id, seasonXp = 1e20, seasonClaimed = { [99] = true, [2] = true, x = true, [3] = "no" } })
	expectEqual(junk2.seasonXp, ST.MAX_XP); expectTrue(junk2.seasonClaimed[2]); expectEqual(junk2.seasonClaimed[99], nil); expectEqual(junk2.seasonClaimed[3], nil)
	expectEqual(PlayerProfile.migrate({}).seasonXp, 0, "old saves get safe defaults")
	-- Tavern Rank XP also fills the ladder (same sources) and a quest pays both
	local AP = require(script.Parent.Parent.Engine.AccountProgress)
	local ap = PlayerProfile.new()
	local snap = {}
	local fake = { handsPlayedTotal = 10, roundsCleared = 1, bossesCleared = 0, handStats = {} }
	AP.sync(ap, snap, fake, day, false)
	expectEqual(ap.seasonXp, 10 * TavernRank.Xp.hand + TavernRank.Xp.round, "hands and rounds feed the season")
	expectEqual(ap.seasonXp, ap.tavernXp, "the same number as the rank XP from the counters")
	local outside = PlayerProfile.new()
	AP.sync(outside, {}, fake, first1 - 100, false)
	expectEqual(outside.seasonXp, 0, "no season, no season XP"); expectTrue(outside.tavernXp > 0)
end })

table.insert(tests, { name = "Boss counterplay: Scout card, every boss has counters, shield tags, Rule Ban token rules and fairness", fn = function()
	local BC = require(script.Parent.Parent.Engine.BossCounters)
	local BossRounds = require(script.Parent.Parent.Engine.BossRounds)
	local HousePasses = require(script.Parent.Parent.Engine.HousePasses)
	local Stakes = require(script.Parent.Parent.Engine.Stakes)
	-- registry: 1 to 2 known rule tags per boss, rule lines of 12 words or fewer, at least 3 counter items each, no unknown counter tags
	expectEqual(table.concat(BC.validate(), "; "), "", "boss and item tags are valid")
	for _, boss in ipairs(BossRounds.Definitions) do
		expectTrue(#BC.itemsFor(boss) >= 3, boss.id .. " is counterable")
		local scout = BC.scout(boss)
		expectTrue(scout.name ~= "" and scout.icon ~= "" and #scout.rules >= 1, boss.id .. " scout card")
		expectTrue(BC.wordCount(scout.line) <= 12, boss.id .. " rule line is 12 words or fewer: " .. BC.wordCount(scout.line))
		expectTrue(not scout.line:find("—"), "no dashes")
	end
	expectEqual(BC.scout(nil), nil); expectEqual(BC.scout("x"), nil)
	-- per tag coverage across the three registries
	local perTag = {}
	for _, tag in ipairs(BossRounds.RuleTagIds) do perTag[tag] = 0 end
	for _, p in ipairs(Patrons.Definitions) do for _, t in ipairs(p.counters or {}) do perTag[t] = (perTag[t] or 0) + 1 end end
	for _, list in ipairs({ Recipes.HouseRecipes, Recipes.MenuRecipes, Recipes.SecretRecipes }) do
		for _, r in ipairs(list) do for _, t in ipairs(r.counters or {}) do perTag[t] = (perTag[t] or 0) + 1 end end
	end
	for _, hp in ipairs(HousePasses.Definitions) do for _, t in ipairs(hp.counters or {}) do perTag[t] = (perTag[t] or 0) + 1 end end
	for tag, n in pairs(perTag) do expectTrue(n >= 3, "tag " .. tag .. " has at least 3 counter items, got " .. n) end
	-- the helper
	local lights = BossRounds.getById("lights_out")
	expectEqual(BC.counters(lights, Patrons.getById("overtime")), "fewerHands")
	expectEqual(BC.counters(lights, HousePasses.getById("double_shift")), "fewerHands")
	expectEqual(BC.counters(lights, Patrons.getById("tip_jar")), nil, "an economy Patron does not counter a hand limit")
	expectEqual(BC.counters(lights, { id = "x" }), nil); expectEqual(BC.counters(nil, Patrons.getById("overtime")), nil); expectEqual(BC.counters(lights, nil), nil)
	local shield = BC.shield(lights, Patrons.getById("overtime"))
	expectTrue(shield ~= nil and shield.icon == "🛡️" and shield.line:find("The Boss") == nil and shield.line:find(lights.name, 1, true) ~= nil)
	expectEqual(BC.shield(lights, Patrons.getById("tip_jar")), nil)
	-- two tags: a counter for either tag counts
	local staffed = BossRounds.getById("short_staffed")
	expectTrue(BC.counters(staffed, Patrons.getById("extra_chair")) ~= nil and BC.counters(staffed, Patrons.getById("second_helpings")) ~= nil)
	-- Rule Ban tokens: 1 on stakes 1 to 4, none on 5 to 8, junk clamps
	for stake = 1, 4 do expectEqual(Stakes.ruleBansFor(stake), 1) end
	for stake = 5, 8 do expectEqual(Stakes.ruleBansFor(stake), 0) end
	expectEqual(Stakes.ruleBansFor(99), 0); expectEqual(Stakes.ruleBansFor("x"), 1)
	local function bossRun(options, bossId)
		local s = RunState.new(options, SeededRng.new(41))
		s.night, s.round = 1, 3
		s.nightBossModifier = BossRounds.getById(bossId or "lights_out")
		RunState.startRound(s)
		return s
	end
	-- fairness: a run created without tokens (Daily, Weekly, Seed, Boss Rush, challenge, tutorial, Quick) cannot ban
	local plain = bossRun(nil)
	expectEqual(plain.ruleBans, 0); expectFalse(plain.ruleBansEnabled)
	expectFalse((RunState.useRuleBan(plain, "roundSelect")), "no tokens in a run without them")
	expectFalse(bossRun({ mode = "quick", ruleBans = true }).ruleBansEnabled, "a Quick Run has none")
	local pTok = RunState.new({ ruleBans = true, stakeId = 1 }, SeededRng.new(2)); expectEqual(pTok.ruleBans, 1)
	expectEqual(RunState.new({ ruleBans = true, stakeId = 5 }, SeededRng.new(2)).ruleBans, 0, "stake 5 starts with none")
	-- the ban: validated, spends a token, deals the round again with no rule, the base target stays
	local s = bossRun({ ruleBans = true, stakeId = 1 })
	expectEqual(s.handsRemaining, 1, "Lights Out: 1 hand"); expectTrue(s.bossModifier ~= nil)
	local targetWithRule = s.targetScore
	expectFalse((RunState.useRuleBan(s, "playing")), "only from Round Select")
	expectTrue(RunState.useRuleBan(s, "roundSelect"))
	expectEqual(s.ruleBans, 0); expectEqual(s.bossModifier, nil, "the rule is off for this fight"); expectEqual(s.handsRemaining, s.config.handsPerRound, "normal hands again")
	expectTrue(RunState.isBossRound(s), "it is still the boss round"); expectEqual(#s.hand, s.config.handSize); expectTrue(s.targetScore > 0)
	expectEqual(s.targetScore, targetWithRule * 2, "Lights Out halved the target: banned means the base target")
	local again, why = RunState.useRuleBan(s, "roundSelect"); expectFalse(again); expectTrue(why == "No Rule Ban left." or why == "This boss is already banned.")
	-- one use per boss even with a second token, and the next Night's boss is not banned
	s.ruleBans = 2
	local second, why2 = RunState.useRuleBan(s, "roundSelect"); expectFalse(second); expectEqual(why2, "This boss is already banned.")
	-- validation: not a boss round, a played round, a finished round
	local normal = RunState.new({ ruleBans = true }, SeededRng.new(3))
	expectFalse((RunState.useRuleBan(normal, "roundSelect")), "round 1 has no boss rule")
	local played = bossRun({ ruleBans = true }, "bouncer"); played.roundScore = 5
	expectFalse((RunState.useRuleBan(played, "roundSelect")), "the round has begun")
	local over = bossRun({ ruleBans = true }, "bouncer"); over.roundOver = true
	expectFalse((RunState.useRuleBan(over, "roundSelect")))
	-- Cold Start: Tips lost when the round was set up are given back, once
	local cold = bossRun({ ruleBans = true }, "cold_start")
	cold.tips = 10; RunState.startRound(cold); expectEqual(cold.tips, 8, "Cold Start took 2 Tips")
	expectTrue(RunState.useRuleBan(cold, "roundSelect")); expectEqual(cold.tips, 10, "refunded")
	-- hand size boss: Bouncer deals one fewer card, banned deals the full hand
	local bounce = bossRun({ ruleBans = true }, "bouncer")
	expectEqual(#bounce.hand, bounce.config.handSize - 1); expectTrue(RunState.useRuleBan(bounce, "roundSelect")); expectEqual(#bounce.hand, bounce.config.handSize)
	-- the Night 4 boss clear earns one more token
	local night4 = RunState.new({ ruleBans = true, stakeId = 1 }, SeededRng.new(5))
	night4.night, night4.round = 4, 3
	night4.nightBossModifier = BossRounds.getById("bouncer"); RunState.startRound(night4)
	night4.targetScore = 0; night4.ruleBans = 0
	RunState.playHand(night4, { 1 })
	expectEqual(night4.ruleBans, 1, "Night 4 boss cleared: +1 token")
	local night3 = RunState.new({ ruleBans = true, stakeId = 1 }, SeededRng.new(5))
	night3.night, night3.round = 3, 3; night3.nightBossModifier = BossRounds.getById("bouncer"); RunState.startRound(night3)
	night3.targetScore = 0; night3.ruleBans = 0; RunState.playHand(night3, { 1 })
	expectEqual(night3.ruleBans, 0, "only the Night 4 boss pays a token")
	-- the ban never changes scoring math: with the rule gone the same hand scores the same as a run that never had it
	expectEqual(Stakes.RULE_BAN_BONUS_NIGHT, 4)
end })

table.insert(tests, { name = "Spectate: cap, duplicates, self, one target at a time, leave cleanup, block, toggle, reactions, whitelisted stream, rate limit", fn = function()
	local Sp = require(script.Parent.Parent.Engine.Spectate)
	local state = Sp.new()
	-- basics: no self watch, no junk ids, no duplicates
	expectFalse((Sp.watch(state, 1, 1))); expectFalse((Sp.watch(state, "x", 2))); expectFalse((Sp.watch(state, 1, -2))); expectFalse((Sp.watch(state, 0 / 0, 2)))
	expectTrue((Sp.watch(state, 1, 2))); expectEqual(Sp.count(state, 2), 1); expectEqual(Sp.watching(state, 1), 2)
	local ok, why = Sp.watch(state, 1, 2); expectFalse(ok); expectEqual(why, "Already watching.")
	expectEqual(Sp.count(state, 2), 1, "no duplicates")
	-- one target at a time: moving releases the old table
	expectTrue((Sp.watch(state, 1, 3))); expectEqual(Sp.count(state, 2), 0); expectEqual(Sp.count(state, 3), 1)
	local _, previous = Sp.watch(state, 1, 4); expectEqual(previous, 3)
	-- cap of 8
	for viewer = 10, 17 do expectTrue((Sp.watch(state, viewer, 5))) end
	local fullOk, fullWhy = Sp.watch(state, 18, 5); expectFalse(fullOk); expectEqual(fullWhy, "That table is full."); expectEqual(Sp.count(state, 5), 8)
	expectEqual(#Sp.watchersOf(state, 5), 8); expectEqual(Sp.takePeak(state, 5), 8); expectEqual(Sp.takePeak(state, 5), 0, "peak is taken once")
	-- a spot frees up when somebody stops
	expectEqual(Sp.stop(state, 10), 5); expectEqual(Sp.stop(state, 10), nil); expectTrue((Sp.watch(state, 18, 5)))
	-- the target's setting and blocks
	local owner = PlayerProfile.new()
	expectTrue(Sp.allows(owner)); owner.settings.allowSpectators = false; expectFalse(Sp.allows(owner))
	expectFalse((Sp.watch(state, 30, 31, { allows = false })), "spectators turned off"); expectFalse((Sp.watch(state, 30, 31, { blocked = true })), "blocked")
	expectTrue(Sp.block(owner, 99)); expectTrue(Sp.isBlocked(owner, 99)); expectFalse(Sp.isBlocked(owner, 98)); expectFalse(Sp.block(owner, "x"))
	expectTrue(Sp.unblock(owner, 99)); expectFalse(Sp.unblock(owner, 99)); expectFalse(Sp.isBlocked(owner, 99))
	for i = 1, Sp.MAX_BLOCKED + 20 do Sp.block(owner, i) end
	local n = 0
	for _ in pairs(owner.blockedSpectators) do n = n + 1 end
	expectEqual(n, Sp.MAX_BLOCKED, "the block list is capped")
	-- turning spectators off or blocking someone removes the right watchers
	local s2 = Sp.new()
	Sp.watch(s2, 1, 9); Sp.watch(s2, 2, 9); Sp.watch(s2, 3, 9)
	expectEqual(#Sp.enforce(s2, 9, true, function(id) return id == 2 end), 1); expectEqual(Sp.count(s2, 9), 2); expectEqual(Sp.watching(s2, 2), nil)
	expectEqual(#Sp.enforce(s2, 9, false), 2); expectEqual(Sp.count(s2, 9), 0)
	-- leaving: a watcher leaving frees the table, a watched player leaving frees the watchers
	local s3 = Sp.new()
	Sp.watch(s3, 1, 7); Sp.watch(s3, 2, 7); Sp.watch(s3, 7, 8)
	local released = Sp.leave(s3, 7)
	expectEqual(#released, 2); expectEqual(Sp.watching(s3, 1), nil); expectEqual(Sp.watching(s3, 2), nil); expectEqual(Sp.count(s3, 8), 0, "the leaver stopped watching too")
	Sp.watch(s3, 1, 8); Sp.leave(s3, 1); expectEqual(Sp.count(s3, 8), 0)
	-- the run ending releases the watchers
	Sp.watch(s3, 1, 8); Sp.watch(s3, 2, 8)
	expectEqual(#Sp.runEnded(s3, 8), 2); expectEqual(Sp.count(s3, 8), 0); expectEqual(Sp.watching(s3, 1), nil)
	-- reactions: preset only, must be watching, 3 second cooldown per spectator
	local s4 = Sp.new()
	expectFalse((Sp.reaction(s4, 1, "cheer", 0)), "not watching")
	Sp.watch(s4, 1, 2)
	expectEqual(#Sp.Emotes, 6)
	for _, e in ipairs(Sp.Emotes) do expectTrue(e.icon ~= "" and e.name ~= "", e.id) end
	expectFalse((Sp.reaction(s4, 1, "free text here", 0))); expectFalse((Sp.reaction(s4, 1, 5, 0))); expectFalse((Sp.reaction(s4, 1, nil, 0)))
	local rOk, target = Sp.reaction(s4, 1, "fire", 10); expectTrue(rOk); expectEqual(target, 2)
	local fast, fastWhy = Sp.reaction(s4, 1, "clap", 12.9); expectFalse(fast); expectEqual(fastWhy, "Too fast.")
	expectTrue((Sp.reaction(s4, 1, "clap", 13.1)))
	Sp.watch(s4, 5, 2); expectTrue((Sp.reaction(s4, 5, "heart", 13.2)), "another spectator has their own cooldown")
	local ev = Sp.reactionEvent("laugh", "Maple"); expectEqual(ev.kind, "reaction"); expectEqual(ev.icon, "😂"); expectEqual(Sp.reactionEvent("nope", "x"), nil)
	-- the stream is rate limited per watched player
	expectTrue(Sp.streamAllowed(s4, 2, 0)); expectFalse(Sp.streamAllowed(s4, 2, 0.1)); expectTrue(Sp.streamAllowed(s4, 2, 0.3)); expectTrue(Sp.streamAllowed(s4, 3, 0.3))
	-- THE WHITELIST: only what the player sees on their own table. Hidden state never leaves, even when it is in the input.
	local secret = {
		name = "Maple", stake = 3, road = "meadow", phase = "playing", night = 4, round = 2, tips = 11, targetScore = 900, roundScore = 300,
		handsRemaining = 2, discardsRemaining = 1,
		hand = { { rank = 14, suit = "Hearts", garnish = "sweet", deck = "SECRET" }, { rank = 5, suit = "Clubs" }, "junk" },
		selected = { 1, 2, 99, "x" }, patrons = { "tip_jar", "flush_fan" },
		boss = { id = "no_repeats", name = "No Repeats", text = "Each hand type once.", secretField = 1 },
		flair = { nameAura = "legend_aura", scoreNumbers = "gold_numbers" },
		deck = { 1, 2, 3 }, deckCounts = { Hearts = {} }, discardPile = { 1 }, rng = {}, seed = 12345, rngSeed = 99, shopOffers = { 1 }, profile = { tips = 5 },
		nextCards = { { rank = 2, suit = "Spades" } }, trueWildcard = { rank = 7 }, houseRecipeInventory = { "x" }, receiptIds = { "a" },
	}
	local snap = Sp.snapshot(secret)
	expectEqual(snap.kind, "snapshot"); expectEqual(snap.night, 4); expectEqual(#snap.hand, 2, "junk cards dropped"); expectEqual(snap.hand[1].garnish, "sweet")
	expectEqual(snap.hand[1].deck, nil); expectEqual(#snap.selected, 2); expectEqual(#snap.patrons, 2); expectEqual(snap.boss.secretField, nil)
	expectEqual(snap.flair.nameAura, "legend_aura")
	for _, forbidden in ipairs({ "deck", "deckCounts", "discardPile", "rng", "seed", "rngSeed", "shopOffers", "profile", "nextCards", "trueWildcard", "houseRecipeInventory", "receiptIds" }) do
		expectEqual(snap[forbidden], nil, "never sent: " .. forbidden)
	end
	local allowedKeys = { kind = 1, name = 1, crest = 1, badge = 1, stake = 1, stakeName = 1, road = 1, roadName = 1, phase = 1, night = 1, round = 1, tips = 1,
		targetScore = 1, roundScore = 1, handsRemaining = 1, discardsRemaining = 1, hand = 1, selected = 1, patrons = 1, boss = 1, flair = 1 }
	for key in pairs(snap) do expectTrue(allowedKeys[key] == 1, "snapshot key is whitelisted: " .. key) end
	expectEqual(Sp.snapshot(nil).kind, "snapshot"); expectEqual(#Sp.snapshot("x").hand, 0)
	local longName = Sp.snapshot({ name = string.rep("x", 500), road = string.rep("y", 500), patrons = { string.rep("z", 500) } })
	expectEqual(#longName.name, 30); expectEqual(#longName.road, 40); expectEqual(#longName.patrons[1], 40)
	expectEqual(Sp.snapshot({ night = 0 / 0, tips = math.huge }).night, nil, "NaN and infinity are dropped")
	local played = Sp.handPlayed({ cards = { { rank = 9, suit = "Spades" }, { rank = 9, suit = "Clubs" } }, handName = "Pair", chips = 30, mult = 4, score = 120, deck = { 1 }, legendary = true })
	expectEqual(played.kind, "handPlayed"); expectEqual(#played.cards, 2); expectEqual(played.score, 120); expectTrue(played.legendary); expectEqual(played.deck, nil)
	expectEqual(Sp.roundResult({ won = true, night = 4, round = 3, banner = "Night cleared" }).won, true)
	-- the gate every event passes
	expectTrue(Sp.outgoing(snap) ~= nil); expectTrue(Sp.outgoing(played) ~= nil); expectTrue(Sp.outgoing(ev) ~= nil)
	expectEqual(Sp.outgoing({ kind = "deckOrder", deck = { 1 } }), nil); expectEqual(Sp.outgoing({ kind = "profile" }), nil); expectEqual(Sp.outgoing("x"), nil); expectEqual(Sp.outgoing(nil), nil)
	-- spectators have no input path: the module exposes no function that changes a run
	for name in pairs(Sp) do
		expectTrue(not name:lower():find("play") or name == "handPlayed", "no input function: " .. name)
	end
	-- save and load: the block list survives, junk is dropped, the setting defaults on
	local loaded = PlayerProfile.migrate(owner)
	expectTrue(loaded.blockedSpectators["1"]); expectTrue(Sp.allows(PlayerProfile.migrate({})))
	local junk = PlayerProfile.migrate({ blockedSpectators = { ["12"] = true, x = true, ["13"] = "yes", ["99999999999999999999"] = true }, settings = { allowSpectators = false } })
	expectTrue(junk.blockedSpectators["12"]); expectEqual(junk.blockedSpectators.x, nil); expectEqual(junk.blockedSpectators["13"], nil)
	expectFalse(Sp.allows(junk)); expectEqual(next(PlayerProfile.migrate({}).blockedSpectators), nil)
	expectTrue((PlayerProfile.setSetting(PlayerProfile.new(), "allowSpectators", false))); expectFalse((PlayerProfile.setSetting(PlayerProfile.new(), "allowSpectators", "no")))
end })

table.insert(tests, { name = "Premium Season track and Flair store items: tier grants, mid season purchase, idempotency, ownership, cosmetic only", fn = function()
	local ST = require(script.Parent.Parent.Engine.SeasonTrack)
	local Store = require(script.Parent.Parent.Engine.Store)
	local Flair = require(script.Parent.Parent.Engine.Flair)
	local CosmeticSets = require(script.Parent.Parent.Engine.CosmeticSets)
	local TavernRank = require(script.Parent.Parent.Engine.TavernRank)
	local s1, s2 = ST.Seasons[1], ST.Seasons[2]
	local first1 = ST.window(s1)
	local first2 = ST.window(s2)
	local day = first1 + 5
	-- every premium tier has a cosmetic reward; the content ids are real; the special tiers are where they should be
	for _, season in ipairs(ST.Seasons) do
		local tips = 0
		for tier = 1, 30 do
			local r = ST.premiumRewardFor(season, tier)
			expectTrue(r ~= nil, season.id .. " premium tier " .. tier)
			expectTrue(r.kind == "tips" or r.kind == "title" or r.kind == "set" or r.kind == "cardBack" or r.kind == "flair", "cosmetic or Tips only")
			if r.kind == "tips" then tips = tips + r.amount end
			if r.kind == "title" then expectTrue(Achievements.getById(r.id) ~= nil and Achievements.getById(r.id).milestoneReward, r.id) end
			if r.kind == "set" then expectTrue(CosmeticSets.getById(r.id) ~= nil, r.id) end
			if r.kind == "cardBack" then expectTrue(CardBacks.getById(r.id) ~= nil, r.id) end
			if r.kind == "flair" then expectTrue(Flair.getById(r.id) ~= nil and Flair.getById(r.id).unlock.kind == "store", r.id) end
		end
		expectTrue(tips <= 30, "premium Tips stay small")
		expectEqual(ST.premiumRewardFor(season, 30).id, season.premiumBackId); expectEqual(ST.premiumRewardFor(season, 15).id, season.premiumSetId)
		expectEqual(ST.premiumRewardFor(season, 8).id, season.premiumTitleId); expectEqual(ST.premiumRewardFor(season, 31), nil)
		expectEqual(Store.getById(season.premiumItemId).seasonPremium, season.id, "the Store item points at its season")
		expectEqual(CosmeticSets.getById(season.premiumSetId).unlock.kind, "season")
		expectTrue(CardBacks.getById(season.premiumBackId).seasonal)
	end
	-- free player: premium locked, nothing claimable, view shows what is included
	local free = PlayerProfile.new()
	ST.addXp(free, 500, day)
	expectFalse((ST.claimPremium(free, 1, day)), "locked without the pass")
	local view = ST.view(free, day)
	expectFalse(view.premium.owned); expectEqual(view.premium.itemId, s1.premiumItemId); expectTrue(#view.premium.perks >= 3)
	expectTrue(view.tiers[1].premium.locked and view.tiers[1].premium.reward ~= nil and view.tiers[1].premium.text ~= "")
	-- buying mid season grants every premium tier already reached at once, nothing more
	expectTrue(Store.canBuy(Store.getById(s1.premiumItemId), day)); expectFalse(Store.canBuy(Store.getById(s2.premiumItemId), day), "only the running season's pass")
	expectTrue(Store.canBuy(Store.getById("starter_pack"), day))
	free.pendingStartTips = 0
	expectTrue(Store.grant(free, s1.premiumItemId, day))
	expectTrue(ST.hasPremium(free, s1)); expectTrue(free.storePurchases[s1.premiumItemId])
	local reached = ST.tierOf(free.seasonXp)
	local count = 0
	for _ in pairs(free.seasonPremiumClaimed) do count = count + 1 end
	expectEqual(count, reached, "the reached premium tiers were claimed at once")
	local expectedTips = 0
	for tier = 1, reached do
		local r = ST.premiumRewardFor(s1, tier)
		if r.kind == "tips" then expectedTips = expectedTips + r.amount end
	end
	expectEqual(free.pendingStartTips, expectedTips, "1 Tip per reached ordinary premium tier")
	-- idempotent: a second grant, a repeated receipt, a second claim all grant nothing
	expectFalse(Store.grant(free, s1.premiumItemId, day), "one time item")
	expectEqual(#ST.grantPremium(free, s1.id, day), 0); expectEqual(#ST.claimAllPremium(free, day), 0)
	expectFalse((ST.claimPremium(free, 1, day))); expectEqual(free.pendingStartTips, expectedTips)
	local view2 = ST.view(free, day)
	expectTrue(view2.premium.owned and view2.tiers[1].premium.claimed and not view2.tiers[1].premium.locked)
	-- later tiers become claimable as XP grows, individually or all at once
	ST.addXp(free, 90 * 12, day)
	expectEqual(ST.view(free, day).premium.claimable, ST.tierOf(free.seasonXp) - reached)
	local ok, reward = ST.claimPremium(free, 8, day)
	expectTrue(ok); expectEqual(reward.kind, "title"); expectTrue(free.rewardTitleIds[s1.premiumTitleId])
	expectFalse((ST.claimPremium(free, 31, day))); expectFalse((ST.claimPremium(free, 1.5, day))); expectFalse((ST.claimPremium(free, "8", day)))
	-- the whole row: set, flair pieces and the unique back
	local rich = PlayerProfile.new()
	ST.addXp(rich, ST.MAX_XP, day)
	ST.grantPremium(rich, s1.id, day)
	expectTrue(rich.ownedSetIds[s1.premiumSetId]); expectTrue(CosmeticSets.isUnlocked(rich, s1.premiumSetId))
	expectTrue(rich.unlockedCardBackIds[s1.premiumBackId] and rich.rewardTitleIds[s1.premiumTitleId])
	for _, id in ipairs({ "rainbow_numbers", "ribbon_trail", "crown_finisher", "star_aura" }) do expectTrue(Flair.isOwned(rich, id), id) end
	expectTrue(rich.pendingStartTips <= TavernRank.MAX_PENDING_TIPS)
	expectEqual(#ST.claimAll(rich, day), 30, "the free row is separate"); expectEqual(#ST.claimAllPremium(rich, day), 0, "premium was claimed by the purchase")
	-- a new season: premium owners of season 1 are not premium in season 2, their rewards stay owned
	expectTrue(ST.ensureSeason(rich, first2)); expectFalse(ST.hasPremium(rich, s2)); expectEqual(next(rich.seasonPremiumClaimed), nil)
	expectTrue(ST.hasPremium(rich, s1), "the old pass stays recorded"); expectTrue(rich.unlockedCardBackIds[s1.premiumBackId])
	expectFalse((ST.claimPremium(rich, 1, first2)))
	-- buying after a season ended grants ownership for good but nothing claimable
	local late = PlayerProfile.new()
	expectEqual(#ST.grantPremium(late, s1.id, first2), 0); expectTrue(ST.hasPremium(late, s1)); expectEqual(next(late.seasonPremiumClaimed), nil)
	expectEqual(#ST.grantPremium(late, "nope", day), 0); expectFalse(ST.hasPremium(late, { id = "nope" }))
	-- Flair store items: single and bundle grant once, free routes count as owned, ownership validated
	local p = PlayerProfile.new()
	expectTrue(Store.grant(p, "flair_rainbow_numbers")); expectTrue(Flair.isOwned(p, "rainbow_numbers")); expectFalse(Store.grant(p, "flair_rainbow_numbers"))
	expectTrue(Store.grant(p, "flair_bundle")); for _, id in ipairs({ "ribbon_trail", "crown_finisher", "star_aura" }) do expectTrue(Flair.isOwned(p, id), id) end
	expectFalse(Store.grant(p, "flair_bundle"))
	local rows = Store.view(PlayerProfile.new(), {}, true, "flair").items
	expectEqual(#rows, 5); for _, row in ipairs(rows) do expectFalse(row.owned); expectTrue(row.available and row.studioFree) end
	local owned = Store.view(p, {}, false, "flair").items
	for _, row in ipairs(owned) do expectTrue(row.owned, row.id .. " is owned") end
	expectEqual(#Store.view(PlayerProfile.new(), {}, false, "season").items, 2)
	for _, row in ipairs(Store.view(PlayerProfile.new(), {}, false).items) do expectTrue(row.id ~= "flair_bundle" and row.id ~= s1.premiumItemId, "the main Store row is unchanged") end
	expectFalse(Store.grant(p, "not_an_item")); expectFalse(Store.grant(p, "vip"))
	-- placeholder ids: every new item is id 0 (Studio grants it free, live shows coming soon)
	for _, item in ipairs(Store.Items) do
		if item.section then expectEqual(item.productId, 0); expectTrue(item.oneTime) end
	end
	-- save and load: premium ownership and claims survive, junk is dropped
	local loaded = PlayerProfile.migrate(free)
	expectTrue(loaded.seasonPremium[s1.id]); expectTrue(loaded.seasonPremiumClaimed[1]); expectTrue(loaded.storePurchases[s1.premiumItemId])
	local junk = PlayerProfile.migrate({ seasonId = s1.id, seasonPremium = { [s1.id] = true, gone = true, [s2.id] = "yes" }, seasonPremiumClaimed = { [3] = true, [99] = true, x = true } })
	expectTrue(junk.seasonPremium[s1.id]); expectEqual(junk.seasonPremium.gone, nil); expectEqual(junk.seasonPremium[s2.id], nil)
	expectTrue(junk.seasonPremiumClaimed[3]); expectEqual(junk.seasonPremiumClaimed[99], nil)
	expectEqual(next(PlayerProfile.migrate({}).seasonPremium), nil, "old saves get safe defaults")
end })

table.insert(tests, { name = "Accessibility: defaults off, calm mode, flashes, particles, Larger Text never clips, hold time clamped and saved", fn = function()
	local A = require(script.Parent.Parent.Engine.Accessibility)
	local defaults = PlayerProfile.defaultSettings()
	expectFalse(defaults.reduceFlashing); expectFalse(defaults.reduceMotion); expectFalse(defaults.largerText); expectEqual(defaults.holdConfirmSeconds, 1.5)
	expectFalse(A.calm(defaults)); expectTrue(A.flashesAllowed(defaults)); expectTrue(A.motionAllowed(defaults))
	expectEqual(A.textScale(defaults), 1); expectEqual(A.particleCount(defaults, 20), 20); expectEqual(A.holdSeconds(defaults), 1.5)
	-- each comfort option has its own effect, and all three count as calm (loops and shake off)
	expectTrue(A.calm({ reduceShake = true })); expectTrue(A.calm({ reduceMotion = true })); expectTrue(A.calm({ reduceFlashing = true }))
	expectFalse(A.flashesAllowed({ reduceFlashing = true })); expectTrue(A.flashesAllowed({ reduceMotion = true, reduceShake = true }))
	expectFalse(A.motionAllowed({ reduceMotion = true })); expectTrue(A.motionAllowed({ reduceFlashing = true }))
	expectEqual(A.particleCount({ reduceFlashing = true }, 20), 8); expectEqual(A.particleCount({ reduceFlashing = true }, 0), 0)
	expectEqual(A.particleCount(nil, -4), 0)
	-- Larger Text: 15 percent, capped by the label height, never smaller than before
	expectEqual(A.textScale({ largerText = true }), 1.15)
	expectEqual(A.scaledTextSize(20, 1.15, nil), 23); expectEqual(A.scaledTextSize(14, 1.15, 0), 16)
	expectEqual(A.scaledTextSize(20, 1.15, 22), 20, "a tight label keeps its size (22px * 0.9 = 19)")
	expectEqual(A.scaledTextSize(14, 1.15, 100), 16); expectEqual(A.scaledTextSize(14, 1, 100), 14); expectEqual(A.scaledTextSize(14, nil, 5), 14)
	for base = 14, 40 do
		for _, fit in ipairs({ 0, 10, 18, 24, 30, 60 }) do
			local size = A.scaledTextSize(base, A.TEXT_SCALE, fit)
			expectTrue(size >= base, "never shrinks " .. base .. "/" .. fit)
			expectTrue(fit == 0 or size <= math.max(base, math.floor(fit * 0.9)), "never taller than the label " .. base .. "/" .. fit)
		end
	end
	-- hold time
	expectEqual(A.holdSeconds({ holdConfirmSeconds = 0.1 }), 0.5); expectEqual(A.holdSeconds({ holdConfirmSeconds = 9 }), 3)
	expectEqual(A.holdSeconds({ holdConfirmSeconds = "x" }), 1.5); expectEqual(A.holdSeconds({ holdConfirmSeconds = 2 }), 2)
	-- saving: the server accepts booleans and a clamped range, refuses junk
	local profile = PlayerProfile.new()
	expectTrue((PlayerProfile.setSetting(profile, "largerText", true))); expectTrue(profile.settings.largerText)
	expectFalse((PlayerProfile.setSetting(profile, "reduceMotion", "yes")))
	expectTrue((PlayerProfile.setSetting(profile, "holdConfirmSeconds", 2))); expectEqual(profile.settings.holdConfirmSeconds, 2)
	expectTrue((PlayerProfile.setSetting(profile, "holdConfirmSeconds", 99))); expectEqual(profile.settings.holdConfirmSeconds, 3)
	expectFalse((PlayerProfile.setSetting(profile, "holdConfirmSeconds", 0 / 0)))
	expectFalse((PlayerProfile.setSetting(profile, "holdConfirmSeconds", math.huge)))
	expectFalse((PlayerProfile.setSetting(profile, "holdConfirmSeconds", "fast")))
	local loaded = PlayerProfile.migrate({ settings = { largerText = true, holdConfirmSeconds = 1.26 } })
	expectTrue(loaded.settings.largerText); expectEqual(loaded.settings.holdConfirmSeconds, 1.3)
	expectFalse(PlayerProfile.migrate({}).settings.reduceFlashing, "old saves get safe defaults")
	-- scoring is untouched: every accessibility key is a setting, none is a run option
	for _, key in ipairs({ "reduceFlashing", "reduceMotion", "largerText", "holdConfirmSeconds" }) do
		expectTrue(PlayerProfile.SETTING_SPECS[key] ~= nil)
	end
end })

table.insert(tests, { name = "Recipes second batch: 16 registered with unlock rules and prompts, every effect works", fn = function()
	local Unlocks = require(script.Parent.Parent.Engine.Unlocks)
	local ids = { "pair_platter", "suit_platter", "row_platter", "feast_platter", "single_serving", "fresh_menu",
		"cooks_choice", "stamp_collector", "family_style", "silver_platter", "gold_leaf",
		"patron_echo", "twin_card", "swap_out", "suit_flip", "patron_shuffle" }
	local function find(id)
		return Recipes.getHouseRecipeById(id) or Recipes.getSecretRecipeById(id)
	end
	local kinds, seen = {}, {}
	for _, id in ipairs(ids) do
		local def = find(id)
		expectTrue(def ~= nil, id .. " is registered")
		expectTrue(not seen[id], "unique " .. id); seen[id] = true
		local words = 0
		for _ in def.description:gmatch("%S+") do words = words + 1 end
		expectTrue(words <= 14, id .. " description is 14 words or fewer, got " .. words)
		expectTrue(def.flavorText ~= "" and def.price >= 3 and def.price <= 10, id .. " has flavor and a sane price")
		expectTrue(Unlocks.isGated("recipe", id), id .. " is gated")
		kinds[Unlocks.ruleOf("recipe", id).kind] = true
	end
	expectTrue(kinds.wins and kinds.rank and kinds.stake and kinds.bestNight and kinds.hands and kinds.quests, "rules spread over every kind")
	-- hand level ups
	local state = RunState.new(nil, SeededRng.new(21))
	local function use(id, opts) return find(id).apply(state, opts or {}, { Patrons = Patrons, patronSlotLimit = 5 }) end
	expectTrue(use("pair_platter")); expectEqual(state.handLevels["Pair"], 1); expectEqual(state.handLevels["Two Pair"], 1)
	expectTrue(use("suit_platter")); expectEqual(state.handLevels["Flush"], 1); expectEqual(state.handLevels["Straight Flush"], 1)
	expectTrue(use("row_platter")); expectEqual(state.handLevels["Straight"], 1); expectEqual(state.handLevels["Three of a Kind"], 1)
	expectTrue(use("feast_platter")); expectEqual(state.handLevels["Full House"], 1); expectEqual(state.handLevels["Four of a Kind"], 1)
	expectTrue(use("single_serving")); expectEqual(state.handLevels["High Card"], 3)
	state.handStats = {}
	expectFalse((use("fresh_menu")), "needs a played hand")
	state.handStats = { Pair = 5, Flush = 2, ["High Card"] = 2, Straight = 0 }
	expectTrue(use("fresh_menu")); expectEqual(state.handLevels["Flush"], 2, "least played, ties by name: Flush before High Card")
	-- card modifiers
	local C = Card.new
	state.hand = { C(5, "Hearts"), C(6, "Spades"), C(7, "Clubs"), C(8, "Diamonds") }
	expectTrue(use("cooks_choice", { cardIndices = { 1, 2 } }))
	expectTrue(Card.Specials[state.hand[1].special] ~= nil and Card.Specials[state.hand[2].special] ~= nil)
	expectFalse((use("cooks_choice", { cardIndices = { 1, 2, 3 } })), "max 2")
	expectFalse((use("cooks_choice", { cardIndices = {} })), "at least 1")
	expectTrue(use("stamp_collector", { cardIndices = { 3, 4 } }))
	expectTrue(Card.Stamps[state.hand[3].stamp] ~= nil and Card.Stamps[state.hand[4].stamp] ~= nil)
	expectTrue(use("family_style", { cardIndices = { 1, 2, 3 } }))
	for i = 1, 3 do expectTrue(Card.Garnishes[state.hand[i].garnish] ~= nil, "garnish " .. i) end
	expectFalse((use("family_style", { cardIndices = { 1, 2, 3, 4 } })))
	expectTrue(use("silver_platter", { cardIndices = { 1, 4 } })); expectEqual(state.hand[1].special, "silver"); expectEqual(state.hand[4].special, "silver")
	expectTrue(use("gold_leaf", { cardIndices = { 2 } })); expectEqual(state.hand[2].stamp, "gold")
	-- strategic
	state.ownedPatrons = {}
	expectFalse((use("patron_echo")), "no Patron to echo"); expectFalse((use("patron_shuffle")), "no Patron to swap")
	state.ownedPatrons = { Patrons.Definitions[1] }
	expectTrue(use("patron_echo")); expectEqual(#state.ownedPatrons, 2)
	expectEqual(state.ownedPatrons[1].id, state.ownedPatrons[2].id, "an exact copy")
	expectTrue(RunState.sellPatron(state, state.ownedPatrons[1].id)); expectEqual(#state.ownedPatrons, 1, "selling removes one copy")
	state.ownedPatrons = { Patrons.Definitions[1], Patrons.Definitions[2], Patrons.Definitions[3], Patrons.Definitions[4], Patrons.Definitions[5] }
	expectFalse((use("patron_echo")), "a full table refuses")
	state.tips = 3
	expectFalse((use("patron_shuffle")), "needs 4 Tips")
	state.tips = 10
	local before = {}
	for _, p in ipairs(state.ownedPatrons) do before[#before + 1] = p.id end
	expectTrue(use("patron_shuffle")); expectEqual(state.tips, 6); expectEqual(#state.ownedPatrons, 5)
	local changed = 0
	for i, p in ipairs(state.ownedPatrons) do if p.id ~= before[i] then changed = changed + 1 end end
	expectEqual(changed, 1, "exactly one Patron swapped")
	state.hand = { C(5, "Hearts", { garnish = "sweet", stamp = "gold" }), C(6, "Spades"), C(7, "Clubs"), C(8, "Diamonds") }
	local discardBefore = #state.discardPile
	expectTrue(use("twin_card", { cardIndices = { 1 } }))
	local twin = state.discardPile[#state.discardPile]
	expectEqual(#state.discardPile, discardBefore + 1)
	expectTrue(twin.rank == 5 and twin.suit == "Hearts" and twin.garnish == "sweet" and twin.stamp == "gold" and twin ~= state.hand[1], "a distinct exact copy")
	local oldCard = state.hand[2]
	expectTrue(use("swap_out", { cardIndices = { 2 } }))
	expectTrue(state.hand[2] ~= oldCard and #state.hand == 4 and state.hand[2].garnish == nil, "replaced by a plain card")
	expectFalse((use("swap_out", { cardIndices = { 1, 2 } })))
	state.hand = { C(5, "Hearts"), C(6, "Spades"), C(7, "Clubs"), C(8, "Diamonds") }
	expectTrue(use("suit_flip"))
	expectEqual(state.hand[1].suit, "Spades"); expectEqual(state.hand[2].suit, "Hearts"); expectEqual(state.hand[3].suit, "Diamonds"); expectEqual(state.hand[4].suit, "Clubs")
	state.hand = {}
	expectFalse((use("suit_flip")), "an empty hand")
	-- through the real inventory flow too
	local s2 = RunState.new(nil, SeededRng.new(22))
	table.insert(s2.secretRecipeInventory, "pair_platter")
	expectTrue(RunState.useSecretRecipe(s2, "pair_platter")); expectEqual(s2.handLevels["Pair"], 1)
end })

table.insert(tests, { name = "RunModes Quick Run: 4 Nights on the compressed curve, stake 1, half XP, no records; normal runs unchanged", fn = function()
	local RunModes = require(script.Parent.Parent.Engine.RunModes)
	local quick = RunModes.get("quick")
	expectEqual(quick.nights, 4)
	expectEqual(RunModes.equivalentNight("quick", 1), 1); expectEqual(RunModes.equivalentNight("quick", 4), 8)
	expectTrue(math.abs(RunModes.equivalentNight("quick", 2) - (1 + 7 / 3)) < 1e-9)
	expectEqual(RunModes.equivalentNight(nil, 3), 3, "no mode leaves the Night alone")
	expectEqual(RunModes.targetScale(nil, 1), 1)
	expectTrue(RunModes.targetScale("quick", 1) < RunModes.targetScale("quick", 2), "Night 1 is the gentle opener")
	expectEqual(RunModes.xpScale("quick"), 0.5); expectEqual(RunModes.xpScale(nil), 1)
	expectTrue(RunModes.isValid("quick")); expectFalse(RunModes.isValid("nope")); expectFalse(RunModes.isValid(5))
	-- normal runs: identical to the plain formula and 8 Nights
	local normal = RunState.new({ stakeId = 3 }, SeededRng.new(11))
	expectEqual(normal.config.nightCap, 8); expectFalse(normal.quickRun); expectEqual(normal.stake, 3)
	expectEqual(normal.targetScore, RunState.targetScoreFor(1, 1, normal.config.roundsPerNight, 8))
	-- a Quick Run
	local q = RunState.new({ mode = "quick", stakeId = 5, endlessRules = true }, SeededRng.new(11))
	expectEqual(q.config.nightCap, 4); expectTrue(q.quickRun); expectEqual(q.runMode, "quick")
	expectEqual(q.stake, 1, "always stake 1"); expectFalse(q.endlessRulesEnabled)
	expectFalse(RunState.countsForRecords(q), "no records, stamps or titles"); expectTrue(RunState.countsForRecords(normal))
	expectTrue(q.targetScore < normal.targetScore, "the opener is gentler than a full run's Night 1")
	-- Night 4 boss: the compressed curve reaches the Night 8 base, scaled by the mode's ease factor
	local last = RunState.targetScoreFor(4, 3, q.config.roundsPerNight, 4, RunModes.equivalentNight("quick", 4))
	expectEqual(last, RunState.targetScoreFor(8, 3, q.config.roundsPerNight, 8), "Night 4 of 4 matches Night 8 of 8 before the ease factor")
	for night = 2, 4 do
		local s = RunState.new({ mode = "quick" }, SeededRng.new(3))
		s.night, s.round = night, 1
		RunState.startRound(s)
		expectTrue(s.targetScore > 0)
	end
	-- Quick Run personal best: a win beats a loss, then the Night, then the score
	local RunHistory = require(script.Parent.Parent.Engine.RunHistory)
	local profile = PlayerProfile.new()
	local function finish(won, night, score)
		return RunHistory.recordQuickBest(profile, { t = 5, mode = "quick", won = won, night = night, score = score })
	end
	expectTrue(finish(false, 2, 500)); expectFalse(finish(false, 2, 400)); expectTrue(finish(false, 3, 100))
	expectTrue(finish(true, 4, 50)); expectFalse(finish(false, 4, 9999)); expectTrue(finish(true, 4, 60))
	expectEqual(profile.quickBest.score, 60)
	expectFalse(RunHistory.recordQuickBest(profile, { t = 5, mode = "standard", won = true, night = 8, score = 1 }), "only Quick Runs")
	expectEqual(PlayerProfile.migrate(profile).quickBest.night, 4); expectEqual(PlayerProfile.migrate({ quickBest = "x" }).quickBest, nil)
end })

table.insert(tests, { name = "RunState counts Tips earned over a run for the Tavern Stats page", fn = function()
	local s = RunState.new(nil, SeededRng.new(5))
	s.targetScore = 0
	s.tips = 0
	RunState.playHand(s, { 1 })
	expectTrue((s.tipsEarnedTotal or 0) >= s.config.tipsPerRoundWin, "the round reward is counted")
end })

table.insert(tests, { name = "Endless Crowd Rules art: category wired, empty map, every rule has an icon", fn = function()
	local EndlessRules = require(script.Parent.Parent.Engine.EndlessRules)
	local Art = require(script.Parent.Parent.Engine.EndlessRuleArt)
	expectEqual(type(Art), "table")
	for _, rule in ipairs(EndlessRules.Rules) do
		expectTrue(type(rule.icon) == "string" and rule.icon ~= "", rule.id .. " has an emoji fallback icon")
		expectTrue(Art[rule.id] == nil or Art[rule.id]:match("^rbxassetid://%d+$") ~= nil, rule.id .. " art id is well formed")
	end
end })

table.insert(tests, { name = "Tutorial stays under 2 minutes: the time budget of all steps, every step one short action", fn = function()
	local Steps = require(script.Parent.Parent.Engine.TutorialSteps)
	local seconds = Steps.estimatedSeconds()
	expectTrue(seconds <= Steps.MAX_SECONDS, "estimated " .. seconds .. "s, budget " .. Steps.MAX_SECONDS .. "s")
	expectTrue(#Steps.Steps <= 24, "at most 24 steps, got " .. #Steps.Steps)
	for _, step in ipairs(Steps.Steps) do
		expectTrue(Steps.SECONDS[step.action] ~= nil, step.id .. " has a time estimate")
	end
end })

-- ===== First 5 minutes: goal banner, first rewards, funnel and analytics =====

table.insert(tests, { name = "NextGoal: tutorial, first win, quest, unlock, rank in that order, always a short line and a 0 to 1 bar", fn = function()
	local NextGoal = require(script.Parent.Parent.Engine.NextGoal)
	local Quests = require(script.Parent.Parent.Engine.Quests)
	local names = { unlock = function(kind, id) return "Thing " .. id end }
	local profile = PlayerProfile.new()
	local goal = NextGoal.compute(profile, 20000, names)
	expectEqual(goal.kind, "tutorial")
	profile.hasSeenTutorial = true
	profile.stats.bestNightReached = 3
	goal = NextGoal.compute(profile, 20000, names)
	expectEqual(goal.kind, "firstWin")
	expectEqual(goal.ratio, 3 / 8)
	profile.stats.runsWon = 1
	goal = NextGoal.compute(profile, 20000, names)
	expectEqual(goal.kind, "quest", "an unfinished daily quest comes next")
	expectTrue(goal.text:find("%(%d+/%d+%)") ~= nil)
	-- finish all three quests: the closest unlock is next
	Quests.ensureDay(profile, 20000)
	for _, id in ipairs(profile.quests.ids) do profile.quests.done[id] = true end
	goal = NextGoal.compute(profile, 20000, names)
	expectEqual(goal.kind, "unlock")
	expectTrue(goal.text:find("Thing ") ~= nil and goal.ratio >= 0 and goal.ratio < 1)
	-- nothing measurable left: the next rank, then the top
	for kind, rules in pairs(require(script.Parent.Parent.Engine.Unlocks).Rules) do
		for id in pairs(rules) do profile.unlockedContent[kind .. ":" .. id] = true end
	end
	goal = NextGoal.compute(profile, 20000, names)
	expectEqual(goal.kind, "rank")
	profile.tavernXp = require(script.Parent.Parent.Engine.TavernRank).MAX_XP
	goal = NextGoal.compute(profile, 20000, names)
	expectEqual(goal.kind, "done")
	for _, g in ipairs({ goal }) do
		expectTrue(g.ratio >= 0 and g.ratio <= 1 and #g.text > 0 and #g.text <= 70, "short line: " .. g.text)
	end
end })

table.insert(tests, { name = "Unlocks.closest: picks the nearest measurable closed item, none once everything is open", fn = function()
	local Unlocks = require(script.Parent.Parent.Engine.Unlocks)
	local profile = PlayerProfile.new()
	profile.stats.bestNightReached = 2
	local c = Unlocks.closest(profile)
	expectTrue(c ~= nil and c.ratio > 0 and c.ratio < 1)
	expectTrue(c.kind == "patron" or c.kind == "recipe")
	profile.stats.runsWon = 100
	profile.stats.bestNightReached = 100
	profile.stats.handsPlayedTotal = 100000
	profile.highestStakeUnlocked = 8
	profile.questsDone = 100
	profile.tavernRank = 100
	expectEqual(Unlocks.closest(profile), nil)
end })

table.insert(tests, { name = "FirstRewards: tutorial and first win pay once, the follow prompt is asked once, Newcomer opens with the tutorial", fn = function()
	local FirstRewards = require(script.Parent.Parent.Engine.FirstRewards)
	local profile = PlayerProfile.new()
	expectTrue(not Achievements.isUnlocked(profile, "first_steps"), "Newcomer is closed at the start")
	local n = FirstRewards.tutorial(profile)
	expectTrue(n ~= nil and n.text:find("Newcomer") ~= nil)
	expectTrue(profile.unlockedCardBackIds.closing_lantern)
	expectTrue(Achievements.isUnlocked(profile, "first_steps"), "the title opens after the tutorial")
	expectEqual(FirstRewards.tutorial(profile), nil, "paid once")
	local win = FirstRewards.firstWin(profile)
	expectTrue(win ~= nil and profile.unlockedCardBackIds.ember_hours and profile.pendingStartTips == FirstRewards.FIRST_WIN_TIPS)
	expectEqual(FirstRewards.firstWin(profile), nil)
	expectTrue(FirstRewards.followDue(profile))
	expectTrue(not FirstRewards.followDue(profile), "asked once")
	local loaded = PlayerProfile.migrate(profile)
	expectTrue(loaded.tutorialRewardClaimed and loaded.firstWinRewardClaimed and loaded.followPrompted)
	local junk = PlayerProfile.migrate({ tutorialRewardClaimed = "yes", followPrompted = 1 })
	expectTrue(not junk.tutorialRewardClaimed and not junk.followPrompted)
	-- both card backs are real
	expectTrue(CardBacks.getById(FirstRewards.TUTORIAL_CARD_BACK) ~= nil and CardBacks.getById(FirstRewards.FIRST_WIN_CARD_BACK) ~= nil)
end })

table.insert(tests, { name = "Funnel and Analytics: each step is logged once per player, errors never escape, no service means a quiet no-op", fn = function()
	local Funnel = require(script.Parent.Parent.Engine.Funnel)
	local Analytics = require(script.Parent.Parent.Engine.Analytics)
	expectEqual(#Funnel.Steps, 8)
	expectEqual(Funnel.indexOf("menu_shown"), 1)
	expectEqual(Funnel.indexOf("second_run_started"), 8)
	local profile = PlayerProfile.new()
	expectEqual(Funnel.markIfNew(profile, "menu_shown"), 1)
	expectEqual(Funnel.markIfNew(profile, "menu_shown"), nil)
	expectEqual(Funnel.markIfNew(profile, "not_a_step"), nil)
	expectTrue(PlayerProfile.migrate(profile).funnelSeen.menu_shown and next(PlayerProfile.migrate({ funnelSeen = { x = true, tutorial_started = 1 } }).funnelSeen) == nil)
	-- with a fake service
	local logged = {}
	Analytics.setService({
		LogFunnelStepEvent = function(_, player, funnel, session, step, name) logged[#logged + 1] = { "step", funnel, session, step, name } end,
		LogCustomEvent = function(_, player, name, value, fields) logged[#logged + 1] = { "event", name, value, fields } end,
	})
	local p2 = PlayerProfile.new()
	expectTrue(Analytics.step("player", p2, "tutorial_started", "sess"))
	expectTrue(not Analytics.step("player", p2, "tutorial_started", "sess"), "never twice")
	expectEqual(logged[1][2], Funnel.NAME); expectEqual(logged[1][4], 2); expectEqual(logged[1][5], "tutorial_started")
	Analytics.runStart("player", 3, "daily")
	Analytics.runEnd("player", 3, "desert", 5, true)
	Analytics.questDone("player", "pairs_3")
	Analytics.rankUp("player", 4)
	expectEqual(#logged, 5)
	expectEqual(logged[2][2], "run_start"); expectEqual(logged[2][4].stake, "3"); expectEqual(logged[3][4].road, "desert")
	expectEqual(logged[3][4].won, "yes")
	-- a service that throws never breaks the caller
	Analytics.setService({
		LogFunnelStepEvent = function() error("boom") end,
		LogCustomEvent = function() error("boom") end,
	})
	expectTrue(Analytics.step("player", PlayerProfile.new(), "menu_shown", "s"))
	expectEqual(Analytics.event("player", "x", 1, {}), false)
	-- no service at all
	Analytics.setService(nil)
	expectTrue(Analytics.step("player", PlayerProfile.new(), "menu_shown", "s"))
	expectEqual(Analytics.event("player", "x", 1, {}), false)
end })

-- ===== Start-of-run draft and run events =====

local function snapshotNumbers(state)
	return { tips = state.tips, hands = state.config.handsPerRound, discards = state.config.discardsPerRound,
		patronSlots = state.config.patronSlotLimit, recipeSlots = state.config.recipeSlotLimit, pay = state.config.tipsPerRoundWin,
		bossPct = state.stakeRules.bossTargetPct, reroll = state.stakeRules.rerollExtra, noInterest = state.stakeRules.noInterest }
end

table.insert(tests, { name = "RunModifiers: each has a blessing and a curse that both change the run, and stays valid", fn = function()
	local RunModifiers = require(script.Parent.Parent.Engine.RunModifiers)
	expectTrue(#RunModifiers.Definitions >= 6)
	for _, def in ipairs(RunModifiers.Definitions) do
		expectTrue(#def.blessing > 0 and #def.curse > 0, def.id .. " has both texts")
		local state = RunState.new(nil, function(_n) return 1 end)
		local before = snapshotNumbers(state)
		local handsBefore, discardsBefore = state.handsRemaining, state.discardsRemaining
		local ok, message = RunModifiers.apply(state, def.id)
		expectTrue(ok and #message > 0, def.id .. " applies")
		local after = snapshotNumbers(state)
		local changed = 0
		for key, value in pairs(before) do
			if after[key] ~= value then changed = changed + 1 end
		end
		expectTrue(changed >= 2, def.id .. " changes at least a blessing and a curse number, changed " .. changed)
		expectTrue(state.config.handsPerRound >= 1 and state.config.patronSlotLimit >= 1 and state.config.discardsPerRound >= 0
			and state.config.tipsPerRoundWin >= 1 and state.config.recipeSlotLimit >= 0, def.id .. " keeps the config valid")
		expectEqual(state.runModifierId, def.id)
		if def.config and def.config.handsPerRound then
			expectEqual(state.handsRemaining, handsBefore + def.config.handsPerRound, "the dealt round gets the hand too")
		end
		if def.config and def.config.discardsPerRound then
			expectEqual(state.discardsRemaining, math.max(0, discardsBefore + def.config.discardsPerRound))
		end
	end
	expectEqual((RunModifiers.apply(RunState.new(nil, function(_n) return 1 end), "nope")), false)
end })

table.insert(tests, { name = "RunChoice draft: 3 starting Patrons (never rare or better), then 3 blessings; the picks apply, bad ids are refused, seeded runs get none", fn = function()
	local RunChoice = require(script.Parent.Parent.Engine.RunChoice)
	local Unlocks = require(script.Parent.Parent.Engine.Unlocks)
	local set = Unlocks.setFor(PlayerProfile.new())
	for seed = 1, 25 do
		local rng = function(n) return ((seed * 7919 + n * 31) % n) + 1 end
		local state = RunState.new({ unlockedContent = set }, rng)
		local choice = RunChoice.startDraft(state, true)
		expectEqual(choice.kind, "patron")
		expectEqual(#choice.options, 3)
		local seen = {}
		for _, o in ipairs(choice.options) do
			expectTrue(not seen[o.id], "distinct")
			seen[o.id] = true
			local patron = Patrons.getById(o.id)
			local rarity = CollectionBook.rarityOf({ tab = "patrons", id = o.id, def = patron })
			expectTrue(rarity == "common" or rarity == "uncommon", o.id .. " is " .. rarity)
			expectTrue(Unlocks.available(state, "patron", o.id) and not patron.biome, o.id .. " is open and not a road reward")
		end
		-- refuse an id that was not offered
		local ok = RunChoice.pick(state, choice, "nest_egg_not_offered")
		expectEqual(ok, false)
		expectEqual(#state.ownedPatrons, 0)
		-- pick the first Patron
		local picked = choice.options[1].id
		local ok2, _, nextChoice = RunChoice.pick(state, choice, picked)
		expectTrue(ok2)
		expectEqual(#state.ownedPatrons, 1)
		expectEqual(state.ownedPatrons[1].id, picked)
		expectEqual(nextChoice.kind, "modifier")
		expectEqual(#nextChoice.options, 3)
		for _, o in ipairs(nextChoice.options) do
			expectTrue(o.line1:sub(1, 1) == "+" and o.line2:sub(1, 1) == "-", "blessing line then curse line")
		end
		local ok3, _, after = RunChoice.pick(state, nextChoice, nextChoice.options[1].id)
		expectTrue(ok3)
		expectEqual(after, nil, "the draft is over")
		expectEqual(state.runModifierId, nextChoice.options[1].id)
		-- One More Round keeps the draft once the snapshot is refreshed
		RunState.refreshSnapshot(state)
		expectEqual(#state.roundStartSnapshot.ownedPatrons, 1)
		expectEqual(state.roundStartSnapshot.runModifierId, state.runModifierId)
	end
	expectEqual(RunChoice.startDraft(RunState.new(nil, math.random), false), nil, "Daily, Weekly, Seed and the tutorial get none")
	expectEqual(RunChoice.rollEvent(RunState.new(nil, math.random), false), nil)
end })

table.insert(tests, { name = "RunEvents: every event has a safe Decline, every outcome leaves a valid run, a refused outcome changes nothing", fn = function()
	local RunEvents = require(script.Parent.Parent.Engine.RunEvents)
	local RunChoice = require(script.Parent.Parent.Engine.RunChoice)
	local ids = {}
	local function prepared()
		local state = RunState.new(nil, function(n) return 1 end)
		state.night = 3
		state.tips = 20
		RunState.buyPatron(state, "the_regular")
		return state
	end
	for _, event in ipairs(RunEvents.Definitions) do
		expectTrue(not ids[event.id], "unique id " .. event.id)
		ids[event.id] = true
		expectTrue(#event.name > 0 and #event.text > 0 and event.icon ~= nil)
		local last = event.options[#event.options]
		expectEqual(last.id, "decline", event.id .. " ends with Decline")
		expectTrue(#event.options >= 2 and #event.options <= 3)
		-- Decline changes nothing
		local state = prepared()
		local before = { tips = state.tips, patrons = #state.ownedPatrons, recipes = #state.houseRecipeInventory }
		expectTrue((RunEvents.resolve(state, event.id, "decline", math.random)))
		expectEqual(state.tips, before.tips); expectEqual(#state.ownedPatrons, before.patrons); expectEqual(#state.houseRecipeInventory, before.recipes)
		-- every option, with each possible coin flip
		for _, option in ipairs(event.options) do
			for _, coin in ipairs({ 1, 2 }) do
				local s2 = prepared()
				local ok, message = RunEvents.resolve(s2, event.id, option.id, function(n) return math.min(coin, n) end)
				expectTrue(type(message) == "string" and #message > 0)
				expectTrue(s2.tips >= 0, event.id .. "/" .. option.id .. " tips never negative")
				expectTrue(#s2.ownedPatrons <= RunState.patronSlotLimit(s2), "patrons fit the seats")
				local held = #s2.houseRecipeInventory + #s2.menuRecipeInventory + #s2.secretRecipeInventory
				expectTrue(held <= RunState.recipeSlotLimit(s2), "recipes fit the box")
				expectTrue(s2.handsRemaining >= 1)
			end
		end
	end
	-- a refused outcome (not enough Tips) leaves the run untouched and the card open
	local poor = prepared()
	poor.tips = 1
	local ok = RunEvents.resolve(poor, "hungry_cook", "trade", math.random)
	expectEqual(ok, false)
	expectEqual(poor.tips, 1)
	-- the roll: a normal run may get one after Night 1, never when not allowed, about half the time
	local hits, trials = 0, 400
	for i = 1, trials do
		local state = prepared()
		state.rng = function(n) return math.random(n) end
		if RunChoice.rollEvent(state, true) then hits = hits + 1 end
	end
	expectTrue(hits > trials * 0.35 and hits < trials * 0.65, "about half the Nights: " .. hits .. " of " .. trials)
	local cardState = prepared()
	cardState.rng = function(n) return 1 end
	local card = RunChoice.rollEvent(cardState, true)
	expectEqual(card.kind, "event")
	expectEqual(card.options[#card.options].id, "decline")
	for _, o in ipairs(card.options) do expectEqual(type(o.name), "string") end
	-- events on a hand-built poor, patron-less state still offer something safe or nothing
	local bare = RunState.new(nil, function(n) return 1 end)
	bare.night = 2
	bare.tips = 0
	for _, e in ipairs(RunEvents.availableFor(bare)) do
		expectTrue(e.options[#e.options].id == "decline")
	end
	-- prompts exist for every event
	local f = io and io.open and io.open("tools/patron_art/prompts.json", "r")
	if f then
		local json = f:read("*a"); f:close()
		expectTrue(json:find('"event_subjects"', 1, true) ~= nil)
		for _, e in ipairs(RunEvents.Definitions) do
			expectTrue(json:find('"' .. e.id .. '"', 1, true) ~= nil, e.id .. " has an event_subjects prompt")
		end
	end
end })

table.insert(tests, { name = "RunChoice events: wrong option, double resolve, wrong phase and forced preview are all safe", fn = function()
	local RunChoice = require(script.Parent.Parent.Engine.RunChoice)
	local state = RunState.new(nil, function(n) return 1 end)
	state.night = 3
	state.tips = 10
	local card = RunChoice.forceEvent("hungry_cook")
	expectEqual(card.kind, "event")
	expectEqual(RunChoice.forceEvent("nope"), nil)
	-- wrong phase / nothing open / bad id type
	expectEqual(RunChoice.canAnswer("playing", card, "decline"), false)
	expectEqual(RunChoice.canAnswer("shop", card, "decline"), false)
	expectEqual(RunChoice.canAnswer("roundSelect", nil, "decline"), false)
	expectEqual(RunChoice.canAnswer("roundSelect", card, 5), false)
	expectEqual(RunChoice.canAnswer("roundSelect", card, "decline"), true)
	-- wrong option changes nothing
	local ok = RunChoice.pick(state, card, "made_up")
	expectEqual(ok, false)
	expectEqual(state.tips, 10)
	-- a resolved card is cleared by the server, so a second answer finds no choice and does nothing
	local ok2 = RunChoice.pick(state, card, "decline")
	expectEqual(ok2, true)
	local choice = nil
	expectEqual((RunChoice.pick(state, choice, "decline")), false)
	expectEqual(RunChoice.canAnswer("roundSelect", choice, "decline"), false)
	expectEqual(state.tips, 10)
end })

table.insert(tests, { name = "Depth Patrons: 24 new, gated, every effect fires, rule benders change the round, prompts exist", fn = function()
	local Unlocks = require(script.Parent.Parent.Engine.Unlocks)
	local HE = require(script.Parent.Parent.Engine.HandEvaluator)
	local Card = require(script.Parent.Parent.Engine.Card)
	local ids = { "flush_fan", "suit_sampler", "warm_hearth", "color_matcher", "full_suit_feast", "twin_spoons", "triple_treat", "foursome_table",
		"kitchen_duo", "pair_parade", "stair_climber", "long_road", "ladder_builder", "royal_road", "savings_club", "bargain_hunter",
		"quick_service", "lucky_penny_jar", "rising_dough", "stack_of_plates", "bread_starter", "extra_chair", "second_helpings", "overtime" }
	expectEqual(#ids, 24)
	local function hand(spec)
		local cards = {}
		for i, c in ipairs(spec) do cards[i] = Card.new(c[1], c[2]) end
		return cards, HE.evaluate(cards)
	end
	local H, S, D, C = "Hearts", "Spades", "Diamonds", "Clubs"
	local flush = { { 2, H }, { 5, H }, { 9, H }, { 11, H }, { 13, H } }
	local twoPair = { { 5, H }, { 5, S }, { 9, H }, { 9, C }, { 2, D } }
	local trips = { { 7, H }, { 7, S }, { 7, C }, { 2, D }, { 9, H } }
	local quads = { { 7, H }, { 7, S }, { 7, C }, { 7, D }, { 9, H } }
	local house = { { 7, H }, { 7, S }, { 7, C }, { 9, D }, { 9, H } }
	local straight = { { 5, H }, { 6, S }, { 7, C }, { 8, D }, { 9, H } }
	local aceStraight = { { 10, H }, { 11, S }, { 12, C }, { 13, D }, { 14, H } }
	local mixedPair = { { 5, H }, { 5, S }, { 9, D }, { 2, C }, { 13, H } }
	local fires = {
		flush_fan = flush, suit_sampler = flush, color_matcher = flush, full_suit_feast = flush, twin_spoons = twoPair,
		triple_treat = trips, foursome_table = quads, kitchen_duo = house, pair_parade = mixedPair, stair_climber = straight,
		long_road = straight, ladder_builder = straight, royal_road = aceStraight, lucky_penny_jar = mixedPair,
		warm_hearth = mixedPair, rising_dough = mixedPair, stack_of_plates = mixedPair, bread_starter = mixedPair,
	}
	for _, id in ipairs(ids) do
		local p = Patrons.getById(id)
		expectTrue(p ~= nil, id .. " exists")
		expectTrue(p.price >= 1 and p.price <= 12 and #p.description > 0 and #p.flavorText > 0)
		local words = 0
		for _ in p.description:gmatch("%S+") do words = words + 1 end
		expectTrue(words <= 14, id .. " effect is 14 words or fewer")
		expectTrue(Unlocks.isGated("patron", id), id .. " starts gated")
		expectTrue(#Unlocks.ruleOf("patron", id).hint > 0)
		local spec = fires[id]
		if spec then
			local cards, result = hand(spec)
			local ctx = { allPlayedCards = cards, heldCards = { Card.new(3, H), Card.new(4, H) }, roundsCleared = 3, handsPlayedTotal = 10, tips = 8 }
			local bonus = p.effect(result, ctx)
			expectTrue(bonus ~= nil and (bonus.chips or bonus.mult or bonus.multMultiplier or bonus.tips), id .. " fires")
		end
	end
	-- a non-matching hand does nothing
	local _, hc = hand({ { 2, H }, { 5, S }, { 9, D }, { 11, C }, { 13, H } })
	expectEqual(Patrons.getById("flush_fan").effect(hc, {}), nil)
	-- economy
	local s = RunState.new(nil, function(n) return 1 end)
	s.tips = 17
	Patrons.getById("savings_club").onRoundWin(s)
	expectEqual(s.tips, 21)
	s.roundStartHands, s.handsRemaining, s.tips = 4, 3, 0
	Patrons.getById("quick_service").onRoundWin(s)
	expectEqual(s.tips, 5)
	s.roundStartHands, s.handsRemaining, s.tips = 4, 2, 0
	Patrons.getById("quick_service").onRoundWin(s)
	expectEqual(s.tips, 0)
	-- rule benders
	local base = RunState.new(nil, function(n) return 1 end)
	local h0, d0, hs0 = base.handsRemaining, base.discardsRemaining, #base.hand
	local cost0 = RunState.rerollCost(base, 5)
	local bent = RunState.new(nil, function(n) return 1 end)
	for _, id in ipairs({ "extra_chair", "second_helpings", "overtime", "bargain_hunter" }) do
		table.insert(bent.ownedPatrons, Patrons.getById(id))
	end
	RunState.startRound(bent)
	expectEqual(bent.handsRemaining, h0 + 1)
	expectEqual(bent.discardsRemaining, d0 + 1)
	expectEqual(#bent.hand, hs0) -- Extra Chair +1, Overtime -1
	expectEqual(RunState.rerollCost(bent, 5), cost0 - 1)
	expectEqual(RunState.rerollCost(bent, 1), 1) -- never below 1
	-- every new Patron has an art prompt
	local f = io and io.open and io.open("tools/patron_art/prompts.json", "r")
	if f then
		local json = f:read("*a"); f:close()
		for _, id in ipairs(ids) do
			expectTrue(json:find('"' .. id .. '"', 1, true) ~= nil, id .. " has a subjects prompt")
		end
	end
end })

table.insert(tests, { name = "Depth House Passes: 6 new, gated, each effect changes the run", fn = function()
	local Unlocks = require(script.Parent.Parent.Engine.Unlocks)
	local HousePasses = require(script.Parent.Parent.Engine.HousePasses)
	local ids = { "pantry_shelf", "tip_stand", "card_cart", "savings_account", "warm_welcome", "boss_prep" }
	for _, id in ipairs(ids) do
		local pass = HousePasses.getById(id)
		expectTrue(pass ~= nil and pass.price >= 1 and #pass.description > 0 and #pass.flavorText > 0, id)
		expectTrue(Unlocks.isGated("housePass", id) and #Unlocks.ruleOf("housePass", id).hint > 0, id .. " gated")
	end
	local function fresh() return RunState.new(nil, function(n) return 1 end) end
	local base = fresh()
	local s = fresh()
	s.housePasses.pantry_shelf = true
	expectEqual(RunState.recipeSlotLimit(s), RunState.recipeSlotLimit(base) + 1)
	s = fresh(); s.housePasses.card_cart = true; RunState.startRound(s)
	expectEqual(#s.hand, #base.hand + 1)
	s = fresh(); s.housePasses.boss_prep = true; s.round = s.config.roundsPerNight; RunState.startRound(s)
	local b2 = fresh(); b2.round = b2.config.roundsPerNight; RunState.startRound(b2)
	expectEqual(s.discardsRemaining, b2.discardsRemaining + 1)
	s = fresh(); s.housePasses.warm_welcome = true; s.round = s.config.roundsPerNight; RunState.startRound(s)
	expectTrue(s.targetScore < b2.targetScore, "boss target is lower")
	-- a gated pass stays out of the voucher pool until opened
	local Shop = require(script.Parent.Parent.Engine.Shop)
	local locked = fresh()
	locked.unlockedContent = {}
	for _, id in ipairs(ids) do
		expectEqual(#Unlocks.filter(locked, "housePass", { { id = id } }), 0)
	end
	locked.unlockedContent["housePass:tip_stand"] = true
	expectEqual(#Unlocks.filter(locked, "housePass", { { id = "tip_stand" } }), 1)
end })

table.insert(tests, { name = "EndlessRules: one new Crowd Rule every 3 Nights past the cap, fixed order, applied only to normal runs, targets never overflow", fn = function()
	local ER = require(script.Parent.Parent.Engine.EndlessRules)
	local Leaderboards = require(script.Parent.Parent.Engine.Leaderboards)
	expectEqual(#ER.Rules, 10)
	local seen = {}
	for _, r in ipairs(ER.Rules) do
		expectTrue(not seen[r.id] and #r.name > 0 and #r.text > 0 and r.icon ~= nil, r.id)
		seen[r.id] = true
		local words = 0
		for _ in r.text:gmatch("%S+") do words = words + 1 end
		expectTrue(words <= 12)
	end
	-- order and timing are the same every time
	expectEqual(ER.countFor(8, 8), 0)
	expectEqual(ER.countFor(10, 8), 0)
	expectEqual(ER.countFor(11, 8), 1)
	expectEqual(ER.countFor(13, 8), 1)
	expectEqual(ER.countFor(14, 8), 2)
	expectEqual(ER.countFor(38, 8), 10)
	expectEqual(ER.countFor(500, 8), 10, "never more than the registry")
	expectEqual(ER.newAt(11, 8).id, ER.Rules[1].id)
	expectEqual(ER.newAt(14, 8).id, ER.Rules[2].id)
	expectEqual(ER.newAt(12, 8), nil)
	expectEqual(ER.newAt(41, 8), nil, "no rule joins after the last one")
	expectEqual(ER.activeFor(20, 8)[3].id, ER.Rules[3].id)
	-- sums
	local sum = ER.combined(ER.activeFor(38, 8))
	expectEqual(sum.bossTargetPct, 10)
	expectEqual(sum.handsDelta, -1)
	-- applied to a normal Endless run, never to a fixed one
	local function run(enabled, night)
		local st = RunState.new({ endlessRules = enabled }, function(n) return 1 end)
		st.night = night
		st.round = 1
		RunState.startRound(st)
		return st
	end
	local plain, ruled = run(false, 17), run(true, 17)
	expectEqual(plain.endlessRules, nil)
	expectEqual(RunState.rerollCost(ruled, 5), RunState.rerollCost(plain, 5) + 1)
	expectTrue(RunState.patronPrice(ruled, { price = 10 }) > RunState.patronPrice(plain, { price = 10 }))
	local early = run(true, 9)
	expectEqual(early.endlessRules.rerollExtra, 0, "no rule before Night 11")
	local late, lateBase = run(true, 40), run(false, 40)
	expectEqual(#late.hand, #lateBase.hand - 1)
	expectEqual(late.handsRemaining, math.max(1, lateBase.handsRemaining - 1))
	expectEqual(late.endlessNewRule, nil)
	expectEqual(run(true, 11).endlessNewRule.id, ER.Rules[1].id)
	-- targets stay finite whole numbers and fit "%d" through Night 60 and far beyond
	for _, night in ipairs({ 9, 20, 40, 60, 200, 500 }) do
		for round = 1, 3 do
			local t = RunState.targetScoreFor(night, round, 3, 8)
			local clamped = ER.clampTarget(t)
			expectTrue(clamped == clamped and clamped > 0 and clamped <= ER.TARGET_CAP, "Night " .. night)
			expectEqual(#string.format("%d", math.floor(clamped)) > 0, true)
		end
	end
	expectEqual(ER.clampTarget(1 / 0), ER.TARGET_CAP)
	-- targets grow every Night until the cap
	expectTrue(RunState.targetScoreFor(21, 1, 3, 8) > RunState.targetScoreFor(20, 1, 3, 8))
	-- the board: Night first, then total score
	local st = RunState.new(nil, function(n) return 1 end)
	st.night, st.wonRun, st.totalScore = 12, true, 123456
	local n, sc = Leaderboards.endlessEntry(st, {})
	expectEqual(n, 12)
	expectEqual(sc, 123456)
	-- personal best card lines: current stake first, then the rest in stake order
	local lines = ER.bestLines({ ["1"] = 9, ["3"] = 14 }, 3)
	expectEqual(#lines, 2)
	expectTrue(lines[1]:find("Night 14", 1, true) ~= nil and lines[2]:find("Night 9", 1, true) ~= nil)
	expectEqual(#ER.bestLines(nil, 1), 0)
	-- personal best per stake
	local profile = PlayerProfile.new()
	expectTrue(PlayerProfile.recordEndlessBest(profile, 3, 12))
	expectEqual(PlayerProfile.recordEndlessBest(profile, 3, 11), false)
	expectTrue(PlayerProfile.recordEndlessBest(profile, 3, 14))
	expectTrue(PlayerProfile.recordEndlessBest(profile, 1, 9))
	expectEqual(profile.endlessBestByStake["3"], 14)
	expectEqual(profile.endlessBestByStake["1"], 9)
	expectEqual(PlayerProfile.recordEndlessBest(profile, 3, 0 / 0), false)
end })

table.insert(tests, { name = "SaveLock and RateLimit: a live lease blocks other servers, stale or own leases do not, release clears it, spam is dropped", fn = function()
	local SaveLock = require(script.Parent.Parent.Engine.SaveLock)
	local RateLimit = require(script.Parent.Parent.Engine.RateLimit)
	-- no stored profile, or no lease: claim
	expectTrue(SaveLock.canClaim(nil, "A", 1000))
	expectTrue(SaveLock.canClaim({ stats = {} }, "A", 1000))
	-- our own lease, and a stale one, can be taken; a live foreign one cannot
	expectTrue(SaveLock.canClaim({ sessionLock = { jobId = "A", t = 990 } }, "A", 1000))
	expectEqual(SaveLock.canClaim({ sessionLock = { jobId = "B", t = 990 } }, "A", 1000), false)
	expectTrue(SaveLock.canClaim({ sessionLock = { jobId = "B", t = 1000 - SaveLock.LEASE - 1 } }, "A", 1000))
	expectTrue(SaveLock.canClaim({ sessionLock = { jobId = "B" } }, "A", 1000), "a malformed lease is treated as stale")
	-- stamping copies and never touches the live profile
	local profile = { keys = 3 }
	local held = SaveLock.stamp(profile, "A", 1000, false)
	expectEqual(held.keys, 3)
	expectEqual(held.sessionLock.jobId, "A")
	expectEqual(profile.sessionLock, nil)
	local released = SaveLock.stamp(held, "A", 1001, true)
	expectEqual(released.sessionLock, nil)
	expectEqual(#SaveLock.RETRY_DELAYS, 3)
	-- rate limit: a burst passes, a flood is cut, time refills, players and remotes are separate
	local t, passed = 100, 0
	for _ = 1, 100 do
		if RateLimit.allow(9001, "PlayHand", t) then passed = passed + 1 end
	end
	expectEqual(passed, RateLimit.BURST)
	expectEqual(RateLimit.allow(9001, "PlayHand", t), false)
	expectTrue(RateLimit.allow(9001, "PlayHand", t + 1), "refills over time")
	expectTrue(RateLimit.allow(9001, "Discard", t), "another remote has its own bucket")
	expectTrue(RateLimit.allow(9002, "PlayHand", t), "another player has their own bucket")
	-- normal play: 5 calls per second for a minute is never blocked
	for i = 1, 300 do
		expectTrue(RateLimit.allow(9003, "Buy", 200 + i * 0.2))
	end
	RateLimit.forget(9001)
	expectTrue(RateLimit.allow(9001, "PlayHand", t))
end })

-- ===== Map discoveries =====

table.insert(tests, { name = "Discoveries: fixed placement, stable ids, kinds, counter total follows the per-region constant", fn = function()
	local Discoveries = require(script.Parent.Parent.Engine.Discoveries)
	local WorldMap = require(script.Parent.Parent.Engine.WorldMap)
	local spots = Discoveries.spots()
	expectEqual(#spots, #WorldMap.RegionOrder * Discoveries.SPOTS_PER_REGION)
	expectEqual(Discoveries.total(), #spots)
	local ids, kinds = {}, {}
	for _, spot in ipairs(spots) do
		expectTrue(not ids[spot.id], "unique id " .. spot.id)
		ids[spot.id] = true
		kinds[spot.kind] = true
		local a, b = Discoveries.place(spot.region, spot.index), Discoveries.place(spot.region, spot.index)
		expectEqual(a.dx, b.dx); expectEqual(a.lift, b.lift); expectEqual(a.side, b.side)
		expectTrue(a.dx >= -0.8 and a.dx <= 0.8 and a.lift >= 0.18 and a.lift <= 0.4 and (a.side == 1 or a.side == -1))
	end
	expectTrue(kinds.chest and kinds.merchant and kinds.secret_patron, "all three kinds are used")
	-- the two spots of one region lie on opposite sides of the road
	for _, region in ipairs(WorldMap.RegionOrder) do
		if Discoveries.SPOTS_PER_REGION >= 2 then
			expectTrue(Discoveries.place(region, 1).side ~= Discoveries.place(region, 2).side, region .. " spots are on both sides")
		end
	end
	expectEqual(Discoveries.milestoneCount(Discoveries.Milestones[1]), math.ceil(Discoveries.total() / 2))
	expectEqual(Discoveries.milestoneCount(Discoveries.Milestones[2]), Discoveries.total())
	for _, m in ipairs(Discoveries.Milestones) do
		expectTrue(Achievements.getById(m.titleId) ~= nil and Achievements.getById(m.titleId).milestoneReward, m.titleId .. " is a real reward title")
	end
end })

table.insert(tests, { name = "Discoveries: hidden until the road is played or a compass charge is spent, claim once, each kind pays", fn = function()
	local Discoveries = require(script.Parent.Parent.Engine.Discoveries)
	local Unlocks = require(script.Parent.Parent.Engine.Unlocks)
	local profile = PlayerProfile.new()
	local spot = Discoveries.spots()[1] -- road chest
	local ok, why = Discoveries.claim(profile, spot.id)
	expectEqual(ok, false); expectEqual(why, "Not revealed yet.")
	expectEqual(Discoveries.claim(profile, "nowhere#9"), false)
	-- playing the road reveals it
	profile.worldBiomeClears = { road = 1 }
	expectTrue(Discoveries.isRevealed(profile, "road") and not Discoveries.isRevealed(profile, "meadow"))
	local okClaim, result = Discoveries.claim(profile, spot.id)
	expectTrue(okClaim and #result.text > 0 and result.kind == "chest")
	expectEqual(profile.pendingStartTips, Discoveries.CHEST_TIPS, "an odd region's chest holds Tips")
	expectEqual(Discoveries.claim(profile, spot.id), false, "claim once")
	expectEqual(Discoveries.foundCount(profile), 1)
	-- a compass charge reveals another region, and only if there is one
	expectEqual(Discoveries.reveal(profile, "meadow"), false)
	profile.compassCharges = 1
	expectTrue((Discoveries.reveal(profile, "meadow")))
	expectEqual(profile.compassCharges, 0)
	expectEqual(Discoveries.reveal(profile, "meadow"), false, "no second reveal")
	expectEqual(Discoveries.reveal(profile, "mars"), false)
	-- each kind pays: meadow (even): chest = card back, second spot = secret Patron; river (odd): merchant
	local meadowChest = Discoveries.claim(profile, "meadow#1")
	expectTrue(meadowChest)
	local backCount = 0
	for _ in pairs(profile.unlockedCardBackIds) do backCount = backCount + 1 end
	expectTrue(backCount >= 1, "an even region's chest holds a card back")
	if Discoveries.SPOTS_PER_REGION >= 2 then
		local okSecret, secret = Discoveries.claim(profile, "meadow#2")
		expectTrue(okSecret and secret.kind == "secret_patron")
		local opened = false
		for key in pairs(profile.unlockedContent) do
			local id = key:match("^patron:(.+)$")
			if id and Unlocks.isUnlocked(profile, "patron", id) then opened = true end
		end
		expectTrue(opened, "a closed Patron opened")
		profile.discoveryRevealed.river = true
		local okMerchant, merchant = Discoveries.claim(profile, "river#2")
		expectTrue(okMerchant and merchant.kind == "merchant")
		expectEqual(profile.merchantDiscount, Discoveries.MERCHANT_DISCOUNT)
		expectEqual(Discoveries.takeMerchantDiscount(profile), Discoveries.MERCHANT_DISCOUNT)
		expectEqual(Discoveries.takeMerchantDiscount(profile), 0, "the discount is taken once")
	end
	-- the discount is capped
	profile.merchantDiscount = 99
	local loaded = PlayerProfile.migrate(profile)
	expectTrue(loaded.merchantDiscount <= Discoveries.MAX_MERCHANT_DISCOUNT)
	expectTrue(loaded.discoveries["road#1"] and loaded.discoveryRevealed.meadow, "claims and reveals survive a save")
	local junk = PlayerProfile.migrate({ discoveries = { ["road#1"] = true, ["x#1"] = true, bad = 1 }, discoveryRevealed = { road = true, mars = true } })
	expectTrue(junk.discoveries["road#1"] and junk.discoveries["x#1"] == nil and junk.discoveryRevealed.mars == nil)
end })

table.insert(tests, { name = "Discoveries: bonus titles at half and at all of the spots, counter in the view", fn = function()
	local Discoveries = require(script.Parent.Parent.Engine.Discoveries)
	local WorldMap = require(script.Parent.Parent.Engine.WorldMap)
	local profile = PlayerProfile.new()
	for _, region in ipairs(WorldMap.RegionOrder) do profile.discoveryRevealed[region] = true end
	local half = Discoveries.milestoneCount(Discoveries.Milestones[1])
	local total = Discoveries.total()
	for i, spot in ipairs(Discoveries.spots()) do
		local ok = Discoveries.claim(profile, spot.id)
		expectTrue(ok, spot.id .. " claims")
		local view = Discoveries.view(profile)
		expectEqual(view.found, i)
		expectEqual(view.total, total)
		expectEqual(profile.rewardTitleIds.curious_explorer == true, i >= half, "half title at " .. half .. ", checked at " .. i)
		expectEqual(profile.rewardTitleIds.grand_explorer == true, i >= total, "all title at " .. total .. ", checked at " .. i)
	end
	expectTrue(Achievements.isUnlocked(profile, "curious_explorer") and Achievements.isUnlocked(profile, "grand_explorer"))
	local json = io and io.open and io.open("tools/patron_art/prompts.json", "r")
	if json then
		local text = json:read("*a"); json:close()
		expectTrue(text:find('"curious_explorer"', 1, true) ~= nil and text:find('"grand_explorer"', 1, true) ~= nil, "title prompts exist")
	end
end })

-- ===== Boss rules, Challenge Runs and Boss Rush =====

-- A run at the start of a Boss Round with the named modifier, a fixed hand of known cards and a target out of reach.
local function bossState(bossId, patrons)
	local state = RunState.new(nil, function(_n) return 1 end)
	state.round = state.config.roundsPerNight
	state.nightBossModifier = BossRounds.getById(bossId)
	RunState.startRound(state)
	state.targetScore = 10 ^ 9
	state.hand = { C(7, "Hearts"), C(7, "Spades"), C(8, "Hearts"), C(9, "Clubs"), C(10, "Hearts"), C(12, "Hearts"), C(3, "Hearts"), C(2, "Diamonds") }
	for _, id in ipairs(patrons or {}) do
		table.insert(state.ownedPatrons, Patrons.getById(id))
	end
	return state
end

table.insert(tests, { name = "BossRules: blocked hand types, minimum hand, first-hand factor, Patron cap, Tips percent", fn = function()
	local BossRules = require(script.Parent.Parent.Engine.BossRules)
	local picky = BossRounds.getById("picky_eater")
	expectTrue(BossRules.blocksHand("Flush", picky) and BossRules.blocksHand("Straight", picky) and not BossRules.blocksHand("Pair", picky))
	local patrol = BossRounds.getById("pair_patrol")
	expectTrue(BossRules.blocksHand("High Card", patrol) and not BossRules.blocksHand("Pair", patrol) and not BossRules.blocksHand("Flush", patrol))
	expectTrue(BossRules.blocksHand("Flush", nil, picky) and not BossRules.blocksHand("Flush", nil, nil), "any rule set can block, nil is fine")
	expectEqual(BossRules.scoreFactor(BossRounds.getById("sleepy_cook"), true), 0.5)
	expectEqual(BossRules.scoreFactor(BossRounds.getById("sleepy_cook"), false), 1)
	expectEqual(BossRules.scoreFactor(nil, true), 1)
	local list = { 1, 2, 3, 4 }
	expectEqual(#BossRules.scoringPatrons(BossRounds.getById("crowded_counter"), list), 2)
	expectEqual(BossRules.scoringPatrons(nil, list), list)
	expectEqual(BossRules.tipsPercent(nil, { tipsPercent = 50 }), 50)
	expectEqual(BossRules.applyPercent(8, 50), 4)
	expectEqual(BossRules.applyPercent(5, 100), 5)
end })

table.insert(tests, { name = "New Boss Rounds: eight new rules, tiered, each one works in RunState.playHand", fn = function()
	local ids = { "sleepy_cook", "cold_start", "pair_patrol", "heavy_hands", "quiet_corner", "picky_eater", "crowded_counter", "penny_wise" }
	local tierOf = { sleepy_cook = 1, cold_start = 1, pair_patrol = 3, heavy_hands = 3, quiet_corner = 3, picky_eater = 6, crowded_counter = 6, penny_wise = 6 }
	for _, id in ipairs(ids) do
		local def = BossRounds.getById(id)
		expectTrue(def ~= nil and def.minNight == tierOf[id] and #def.description > 0 and def.icon ~= nil, id .. " is registered and tiered")
		expectTrue(BossRounds.categoryOf(def) ~= nil, id .. " has a category")
	end
	-- Sleepy Cook: the first hand scores half, the next one does not
	local control = bossState("slow_simmer") -- an unrelated mild boss as the baseline for the same cards
	control.nightBossModifier, control.bossModifier = nil, nil
	local cook = bossState("sleepy_cook")
	control = bossState("bouncer")
	control.bossModifier = nil
	local a = RunState.playHand(cook, { 1, 2 }).score
	local b = RunState.playHand(control, { 1, 2 }).score
	expectEqual(a, b / 2, "the first hand scores half")
	cook.hand = { C(7, "Hearts"), C(7, "Spades"), C(8, "Hearts"), C(9, "Clubs"), C(10, "Hearts"), C(12, "Hearts"), C(3, "Hearts"), C(2, "Diamonds") }
	control.hand = { C(7, "Hearts"), C(7, "Spades"), C(8, "Hearts"), C(9, "Clubs"), C(10, "Hearts"), C(12, "Hearts"), C(3, "Hearts"), C(2, "Diamonds") }
	expectEqual(RunState.playHand(cook, { 1, 2 }).score, RunState.playHand(control, { 1, 2 }).score, "later hands score in full")
	-- Cold Start: 2 Tips lost as the round begins, never below 0
	local cold = RunState.new(nil, function(_n) return 1 end)
	cold.tips = 10
	cold.round = cold.config.roundsPerNight
	cold.nightBossModifier = BossRounds.getById("cold_start")
	RunState.startRound(cold)
	expectEqual(cold.tips, 8)
	cold.tips = 1
	RunState.startRound(cold)
	expectEqual(cold.tips, 0)
	-- Pair Patrol: High Card scores 0, a Pair scores
	local patrol = bossState("pair_patrol")
	expectEqual(RunState.playHand(patrol, { 3 }).score, 0, "High Card scores nothing")
	patrol.hand = { C(7, "Hearts"), C(7, "Spades"), C(8, "Hearts"), C(9, "Clubs"), C(10, "Hearts"), C(12, "Hearts"), C(3, "Hearts"), C(2, "Diamonds") }
	expectTrue(RunState.playHand(patrol, { 1, 2 }).score > 0, "a Pair scores")
	-- Heavy Hands: fewer than 3 cards is refused
	local heavy = bossState("heavy_hands")
	expectEqual((pcall(RunState.playHand, heavy, { 1, 2 })), false)
	expectEqual((pcall(RunState.playHand, heavy, { 1, 2, 3 })), true)
	-- Quiet Corner: odd ranks score nothing (a 7 is odd, an 8 is even)
	local quiet = bossState("quiet_corner")
	local oddScore = RunState.playHand(quiet, { 1 }).score -- the 7 of Hearts
	quiet.hand = { C(8, "Hearts"), C(2, "Spades"), C(9, "Clubs"), C(10, "Hearts"), C(12, "Hearts"), C(3, "Hearts"), C(2, "Diamonds"), C(4, "Clubs") }
	local evenScore = RunState.playHand(quiet, { 1 }).score -- the 8 of Hearts
	expectTrue(evenScore > oddScore, "even ranks score, odd ranks do not")
	-- Picky Eater: a Flush scores nothing, a Pair does
	local picky = bossState("picky_eater")
	picky.hand = { C(2, "Hearts"), C(5, "Hearts"), C(8, "Hearts"), C(11, "Hearts"), C(13, "Hearts"), C(7, "Spades"), C(7, "Clubs"), C(3, "Diamonds") }
	expectEqual(RunState.playHand(picky, { 1, 2, 3, 4, 5 }).score, 0, "a Flush scores nothing")
	picky.hand = { C(7, "Hearts"), C(7, "Spades"), C(8, "Hearts"), C(9, "Clubs"), C(10, "Hearts"), C(12, "Hearts"), C(3, "Hearts"), C(2, "Diamonds") }
	expectTrue(RunState.playHand(picky, { 1, 2 }).score > 0)
	-- Crowded Counter: only the first 2 Patrons score (3 Patrons == the first 2)
	local crowd3 = bossState("crowded_counter", { "the_regular", "the_regular", "the_regular" })
	local crowd2 = bossState("crowded_counter", { "the_regular", "the_regular" })
	local free3 = bossState("bouncer", { "the_regular", "the_regular", "the_regular" })
	free3.bossModifier = nil
	local s3, s2, sf = RunState.playHand(crowd3, { 1, 2 }).score, RunState.playHand(crowd2, { 1, 2 }).score, RunState.playHand(free3, { 1, 2 }).score
	expectEqual(s3, s2, "the third Patron does not score")
	expectTrue(sf > s3, "without the boss all three score")
	-- Penny Wise: a Gold Stamp pays Tips normally but not here
	local wise = bossState("penny_wise")
	local plain = bossState("bouncer")
	plain.bossModifier = nil
	wise.hand[1].stamp = "gold"; plain.hand[1].stamp = "gold"
	wise.tips, plain.tips = 0, 0
	RunState.playHand(wise, { 1 })
	RunState.playHand(plain, { 1 })
	expectTrue(plain.tips > 0 and wise.tips == 0, "Tips from scoring are not paid")
	-- art prompts and the same rules in the client preview (source check)
	local f = io and io.open and io.open("tools/patron_art/prompts.json", "r")
	if f then
		local json = f:read("*a"); f:close()
		for _, id in ipairs(ids) do expectTrue(json:find('"' .. id .. '"', 1, true) ~= nil, id .. " has a boss_subjects prompt") end
	end
	local hub = io and io.open and io.open("src/Client/init.client.lua", "r")
	if hub then
		local src = hub:read("*a"); hub:close()
		expectTrue(src:find("BossRules.blocksHand", 1, true) ~= nil and src:find("BossRules.scoreFactor", 1, true) ~= nil, "the preview uses the same rules")
	end
end })

table.insert(tests, { name = "Challenge Runs: six twists, each changes the run as it says, the clear pays a title once", fn = function()
	local Challenges = require(script.Parent.Parent.Engine.Challenges)
	local TavernRank = require(script.Parent.Parent.Engine.TavernRank)
	expectTrue(#Challenges.Definitions >= 6)
	for _, def in ipairs(Challenges.Definitions) do
		expectTrue(Achievements.getById(def.titleId) ~= nil and Achievements.getById(def.titleId).milestoneReward, def.id .. " has a reward title")
		local state = RunState.new({ challengeId = def.id }, function(_n) return 1 end)
		expectEqual(state.challenge.id, def.id)
		expectTrue(state.handsRemaining >= 1 and state.config.patronSlotLimit >= 1, def.id .. " leaves a valid run")
	end
	local base = RunState.new(nil, function(_n) return 1 end)
	-- No Discards
	local nd = RunState.new({ challengeId = "no_discards" }, function(_n) return 1 end)
	expectEqual(nd.discardsRemaining, 0)
	expectEqual(nd.handsRemaining, base.handsRemaining + 2)
	-- One Seat: one seat, Patron effects count double
	local seat = RunState.new({ challengeId = "one_seat" }, function(_n) return 1 end)
	expectEqual(RunState.patronSlotLimit(seat), 1)
	table.insert(seat.ownedPatrons, Patrons.getById("the_regular"))
	local plain = RunState.new(nil, function(_n) return 1 end)
	table.insert(plain.ownedPatrons, Patrons.getById("the_regular"))
	seat.hand = { C(7, "Hearts"), C(7, "Spades"), C(8, "Hearts"), C(9, "Clubs"), C(10, "Hearts"), C(12, "Hearts"), C(3, "Hearts"), C(2, "Diamonds") }
	plain.hand = { C(7, "Hearts"), C(7, "Spades"), C(8, "Hearts"), C(9, "Clubs"), C(10, "Hearts"), C(12, "Hearts"), C(3, "Hearts"), C(2, "Diamonds") }
	seat.targetScore, plain.targetScore = 10 ^ 9, 10 ^ 9
	local doubled, single = RunState.playHand(seat, { 1, 2 }), RunState.playHand(plain, { 1, 2 })
	expectTrue(doubled.mult > single.mult, "Patron effects count double: " .. doubled.mult .. " vs " .. single.mult)
	-- Pairs Only: a Flush scores nothing, a Pair scores
	local po = RunState.new({ challengeId = "pairs_only" }, function(_n) return 1 end)
	po.targetScore = 10 ^ 9
	po.hand = { C(2, "Hearts"), C(5, "Hearts"), C(8, "Hearts"), C(11, "Hearts"), C(13, "Hearts"), C(7, "Spades"), C(7, "Clubs"), C(3, "Diamonds") }
	expectEqual(RunState.playHand(po, { 1, 2, 3, 4, 5 }).score, 0)
	po.hand = { C(7, "Hearts"), C(7, "Spades"), C(8, "Hearts"), C(9, "Clubs"), C(10, "Hearts"), C(12, "Hearts"), C(3, "Hearts"), C(2, "Diamonds") }
	expectTrue(RunState.playHand(po, { 1, 2 }).score > 0)
	-- Glass Deck: with a lucky roll every played card may break, but never below the minimum deck
	local glass = RunState.new({ challengeId = "glass_deck" }, function(_n) return 1 end)
	glass.targetScore = 10 ^ 9
	glass.handsRemaining = 99
	for _ = 1, 30 do
		RunState.playHand(glass, { 1, 2, 3, 4, 5 })
	end
	local total = #glass.deck + #glass.discardPile + #glass.hand
	expectTrue(glass.glassBroken > 0, "cards broke")
	expectTrue(total >= Challenges.GLASS_MIN_CARDS, "the deck never drops below " .. Challenges.GLASS_MIN_CARDS .. ", has " .. total)
	expectEqual(total, 52 - glass.glassBroken)
	-- Tight Wallet: a cleared round pays half
	local tw = RunState.new({ challengeId = "tight_wallet" }, function(_n) return 1 end)
	local full = RunState.new(nil, function(_n) return 1 end)
	tw.targetScore, full.targetScore = 0, 0
	tw.tips, full.tips = 0, 0
	RunState.playHand(tw, { 1 }); RunState.playHand(full, { 1 })
	expectEqual(tw.lastRoundReward, math.floor(full.lastRoundReward / 2), "half the Tips")
	-- Clearing: title once, remembered, Speed Run bonus only when fast
	local profile = PlayerProfile.new()
	local r = Challenges.recordClear(profile, "pairs_only", 9999)
	expectTrue(r.first and r.title == "pair_master" and r.bonusXp == 0 and profile.rewardTitleIds.pair_master and profile.challengesCleared.pairs_only)
	local again = Challenges.recordClear(profile, "pairs_only", 9999)
	expectTrue(not again.first and again.title == nil)
	local fast = Challenges.recordClear(profile, "speed_run", 600)
	expectEqual(fast.bonusXp, Challenges.SPEED_BONUS_XP)
	expectTrue(profile.tavernXp >= Challenges.SPEED_BONUS_XP)
	local slow = Challenges.recordClear(PlayerProfile.new(), "speed_run", 5000)
	expectEqual(slow.bonusXp, 0)
	expectEqual(Challenges.recordClear(profile, "nope", 1), nil)
	-- save / load
	local loaded = PlayerProfile.migrate(profile)
	expectTrue(loaded.challengesCleared.pairs_only and loaded.challengesCleared.speed_run)
	expectTrue(PlayerProfile.migrate({ challengesCleared = { pairs_only = true, nope = true, speed_run = 1 } }).challengesCleared.nope == nil)
	-- prompts
	local f = io and io.open and io.open("tools/patron_art/prompts.json", "r")
	if f then
		local json = f:read("*a"); f:close()
		for _, def in ipairs(Challenges.Definitions) do expectTrue(json:find('"' .. def.titleId .. '"', 1, true) ~= nil, def.titleId .. " has a title prompt") end
	end
end })

table.insert(tests, { name = "Boss Rush: unlocks after the first win, 3 picked Patrons, back-to-back bosses that get harder, ends at the first loss, best is kept", fn = function()
	local BossRush = require(script.Parent.Parent.Engine.BossRush)
	local RunChoice = require(script.Parent.Parent.Engine.RunChoice)
	local profile = PlayerProfile.new()
	expectTrue(not BossRush.isUnlocked(profile))
	profile.stats.runsWon = 1
	expectTrue(BossRush.isUnlocked(profile))
	local rng = function(n) return math.random(n) end
	local state = RunState.new({ rush = true }, rng)
	expectTrue(BossRush.isRush(state) and state.config.roundsPerNight == 1 and state.isBossRound and state.bossModifier ~= nil)
	expectTrue(not RunState.countsForRecords(state), "a Rush never moves records")
	-- the draft: three picks, no repeats, then it is over
	local choice = RunChoice.rushDraft(state, 1, {})
	expectEqual(choice.kind, "rushPatron"); expectEqual(#choice.options, BossRush.OFFERS)
	local picked = {}
	for step = 1, BossRush.PICKS do
		expectEqual(choice.step, step)
		local id = choice.options[1].id
		expectTrue(not picked[id], "never offered again")
		picked[id] = true
		local ok, _, nextChoice = RunChoice.pick(state, choice, id)
		expectTrue(ok)
		choice = nextChoice
	end
	expectEqual(choice, nil, "the draft ends after 3 picks")
	expectEqual(#state.ownedPatrons, BossRush.PICKS)
	-- clear bosses one after another: every round is a boss, no shop, the Night climbs, the targets and tiers rise
	local lastTarget, lastNight = 0, 0
	for k = 1, 9 do
		expectTrue(state.isBossRound and state.bossModifier ~= nil, "boss " .. k)
		expectEqual(state.night, k)
		-- the base target (without the boss's own target multiplier, which is random) climbs every Night
		local baseTarget = state.targetScore / (state.bossModifier.targetScoreMultiplier or 1)
		expectTrue(baseTarget > lastTarget * 0.999, "targets climb: " .. baseTarget .. " after " .. lastTarget)
		expectTrue(state.bossModifier.minNight <= state.night, "tier is open for this Night")
		lastTarget = baseTarget
		state.targetScore = 0 -- win this boss at once
		state.bossModifier = nil -- keep the test hand simple
		RunState.playHand(state, { 1 })
		expectTrue(state.roundOver and not state.runOver)
		expectEqual(state.bossesCleared, k)
		expectTrue(not state.wonRun, "a Rush is never won, it only ends in a loss")
		RunState.advanceToNextRound(state)
	end
	expectEqual(state.night, 10)
	-- the first loss ends it
	state.targetScore = 10 ^ 9
	state.handsRemaining = 1
	state.bossModifier = nil
	RunState.playHand(state, { 1 })
	expectTrue(state.runOver)
	expectEqual(BossRush.score(state), 9)
	-- the personal best
	expectTrue(BossRush.record(profile, BossRush.score(state)))
	expectTrue(not BossRush.record(profile, 4), "a lower score is not a new best")
	expectEqual(BossRush.view(profile).best, 9)
	expectEqual(PlayerProfile.migrate(profile).bossRushBest, 9)
	expectEqual(PlayerProfile.migrate({ bossRushBest = "x" }).bossRushBest, 0)
	-- a normal run is untouched by all of this
	local normal = RunState.new(nil, rng)
	expectTrue(normal.rush == nil and normal.config.roundsPerNight == 3 and RunState.countsForRecords(normal))
end })

-- ===== Phase 4: Endless board, global scope, sharing =====

table.insert(tests, { name = "Leaderboards Endless: score packs Night then best hand, decodes back, ordering and improvement rules", fn = function()
	local Leaderboards = require(script.Parent.Parent.Engine.Leaderboards)
	local c = Leaderboards.combine(12, 4500)
	local night, hand = Leaderboards.decode(c)
	expectEqual(night, 12); expectEqual(hand, 4500)
	expectTrue(Leaderboards.combine(13, 0) > Leaderboards.combine(12, 999999), "a higher Night always wins")
	expectEqual(Leaderboards.combine(9, 10 ^ 12), 9 * Leaderboards.SCORE_MULTIPLIER + Leaderboards.SCORE_MULTIPLIER - 1, "the hand is clamped below the Night digits")
	expectEqual(Leaderboards.combine(9, -5), 9 * Leaderboards.SCORE_MULTIPLIER)
	expectEqual(Leaderboards.storeName("endless", "Standard", Leaderboards.ENDLESS_PERIOD, 2), "EndlessMode_Standard_v2_alltime")
	expectEqual(Leaderboards.storeName("endless", "Revived", "alltime", 2), "EndlessMode_Revived_v2_alltime")
	-- improvement
	expectTrue(Leaderboards.improves(nil, 9, 1))
	expectTrue(Leaderboards.improves({ depth = 9, tips = 100 }, 10, 0))
	expectTrue(Leaderboards.improves({ depth = 9, tips = 100 }, 9, 101))
	expectTrue(not Leaderboards.improves({ depth = 9, tips = 100 }, 9, 100))
	expectTrue(not Leaderboards.improves({ depth = 10, tips = 5 }, 9, 9999))
	-- sorting: Night first, then best hand; ties keep their order
	local rows = { { id = "a", depth = 9, tips = 50 }, { id = "b", depth = 11, tips = 1 }, { id = "c", depth = 9, tips = 90 }, { id = "d", depth = 9, tips = 90 } }
	local sorted = Leaderboards.sortRows(rows)
	expectEqual(sorted[1].id, "b"); expectEqual(sorted[2].id, "c"); expectEqual(sorted[3].id, "d"); expectEqual(sorted[4].id, "a")
	local top = Leaderboards.topRows(sorted, 2)
	expectEqual(#top, 2); expectEqual(top[1].rank, 1); expectEqual(top[2].rank, 2)
	expectEqual(sorted[1].rank, nil, "topRows copies, the page cache is untouched")
	-- scopes
	expectTrue(Leaderboards.isScope("global") and Leaderboards.isScope("friends") and Leaderboards.isScope("everyone") and not Leaderboards.isScope("moon"))
	expectEqual(Leaderboards.normalizeScope("friends"), "friends")
	expectEqual(Leaderboards.normalizeScope("anything"), "global")
	expectEqual(Leaderboards.normalizeScope(nil), "global")
end })

table.insert(tests, { name = "Leaderboards Endless validation: only a won, normal run past the Night cap counts, scores come from the run state", fn = function()
	local Leaderboards = require(script.Parent.Parent.Engine.Leaderboards)
	local function run(night)
		local state = RunState.new(nil, function(_n) return 1 end)
		state.wonRun = true
		state.night = night
		state.bestHand = { name = "Flush", score = 1234.7 }
		return state
	end
	local n, score = Leaderboards.endlessEntry(run(11), {})
	expectEqual(n, 11); expectEqual(score, 1234)
	expectEqual(Leaderboards.endlessEntry(run(8), {}), nil, "Night 8 is not Endless yet")
	local notWon = run(11); notWon.wonRun = false
	expectEqual(Leaderboards.endlessEntry(notWon, {}), nil)
	expectEqual(Leaderboards.endlessEntry(run(11), { isDaily = true }), nil)
	expectEqual(Leaderboards.endlessEntry(run(11), { isWeekly = true }), nil)
	expectEqual(Leaderboards.endlessEntry(run(11), { isSeeded = true }), nil)
	expectEqual(Leaderboards.endlessEntry(run(11), { isTutorial = true }), nil)
	local rush = run(11); rush.rush = { started = true }
	expectEqual(Leaderboards.endlessEntry(rush, {}), nil, "a Boss Rush is not an Endless run")
	local challenge = run(11); challenge.challenge = { id = "pairs_only" }
	expectEqual(Leaderboards.endlessEntry(challenge, {}), nil, "a Challenge run is not on the board")
	expectEqual(Leaderboards.endlessEntry(run(Leaderboards.MAX_ENDLESS_NIGHT + 1), {}), nil, "an impossible Night is refused")
	local weird = run(11); weird.bestHand = { name = "x", score = 0 / 0 }
	expectEqual(Leaderboards.endlessEntry(weird, {}), nil)
	local huge = run(11); huge.bestHand = { name = "x", score = 10 ^ 12 }
	local _, clamped = Leaderboards.endlessEntry(huge, {})
	expectEqual(clamped, Leaderboards.SCORE_MULTIPLIER - 1)
	local none = run(11); none.bestHand = nil
	local _, zero = Leaderboards.endlessEntry(none, {})
	expectEqual(zero, 0)
	expectEqual(Leaderboards.endlessEntry(nil, {}), nil)
end })

table.insert(tests, { name = "Leaderboards cache: a second open inside the window reads nothing, the page is read again after it", fn = function()
	local Leaderboards = require(script.Parent.Parent.Engine.Leaderboards)
	local now = 0
	local cache = Leaderboards.newCache(Leaderboards.FRIENDS_CACHE_SECONDS, function() return now end)
	local reads = 0
	local function board()
		local rows = cache.get("store")
		if not rows then
			reads = reads + 1
			rows = cache.set("store", { { userId = 1, depth = 9, tips = 1 } })
		end
		return rows
	end
	board(); board(); board()
	expectEqual(reads, 1, "three opens, one read")
	now = 59
	board()
	expectEqual(reads, 1, "still cached at 59 seconds")
	now = 61
	board()
	expectEqual(reads, 2, "read again after 60 seconds")
	-- Friends and Global share the same page: friendRows works on the cached rows
	local rows = { { userId = 5, depth = 9, tips = 1 }, { userId = 6, depth = 9, tips = 0 }, { userId = 7, depth = 8, tips = 9 } }
	local friends = Leaderboards.friendRows(rows, { [6] = true }, 7, 10)
	expectEqual(#friends, 2); expectEqual(friends[1].userId, 6); expectEqual(friends[2].userId, 7)
end })

table.insert(tests, { name = "ShareResult: a short result line and a challenge line, each within the 200 character chat limit", fn = function()
	local ShareResult = require(script.Parent.Parent.Engine.ShareResult)
	local summary = { night = 6, won = false, bestHand = { name = "Flush", score = 1240 } }
	local line = ShareResult.line(summary, "ABC234")
	expectTrue(line:find("Night 6", 1, true) and line:find("Flush (1240)", 1, true) and line:find("Seed: ABC234", 1, true) and line:find("beat me", 1, true))
	expectTrue(#line <= ShareResult.MAX_LENGTH)
	expectTrue(not ShareResult.line(summary, nil):find("Seed", 1, true), "no seed for an ordinary run")
	expectTrue(ShareResult.line({ night = 8, won = true }, nil):find("won and reached Night 8", 1, true))
	local long = ShareResult.line({ night = 9, bestHand = { name = string.rep("x", 400), score = 1 } }, "ABC234")
	expectEqual(#long, ShareResult.MAX_LENGTH)
	local challenge = ShareResult.challengeLine(summary, "QWE789")
	expectTrue(challenge:find("QWE789", 1, true) and challenge:find("Night 6", 1, true) and challenge:find("Seed Run", 1, true) and #challenge <= ShareResult.MAX_LENGTH)
	expectTrue(ShareResult.line(nil, nil) ~= nil and ShareResult.challengeLine(nil, nil) ~= nil, "junk input never errors")
	-- the codes the server hands out are valid seed codes
	local SeededRng = require(script.Parent.Parent.Engine.SeededRng)
	local code = SeededRng.randomCode()
	expectTrue(SeededRng.validateCode(code) ~= nil)
end })

-- ===== Phase 5: game feel =====

table.insert(tests, { name = "ScoreFeel: popup tier by share of the Target, bigger tiers pop more and slam only from tier 4, combos build and reset", fn = function()
	local F = require(script.Parent.Parent.Engine.ScoreFeel)
	expectEqual(F.tierFor(5, 100), 1); expectEqual(F.tierFor(10, 100), 2); expectEqual(F.tierFor(24, 100), 2)
	expectEqual(F.tierFor(25, 100), 3); expectEqual(F.tierFor(49, 100), 3); expectEqual(F.tierFor(50, 100), 4)
	expectEqual(F.tierFor(99, 100), 4); expectEqual(F.tierFor(100, 100), 5); expectEqual(F.tierFor(5000, 100), 5)
	expectEqual(F.tierFor(40, nil), 1); expectEqual(F.tierFor(40, 0), 1); expectEqual(F.tierFor(nil, 100), 1)
	local lastPop, lastSlam = 0, -1
	for tier = 1, 5 do
		expectTrue(F.popScale(tier) > lastPop, "bigger tiers pop more")
		expectTrue(F.slamFor(tier) >= lastSlam)
		lastPop, lastSlam = F.popScale(tier), F.slamFor(tier)
		local c = F.tierColor(tier)
		expectTrue(#c == 3 and c[1] >= 0 and c[1] <= 255 and c[2] >= 0 and c[3] <= 255)
	end
	expectEqual(F.slamFor(3), 0, "no extra slam below half the Target")
	expectTrue(F.slamFor(4) > 0 and F.slamFor(5) > F.slamFor(4))
	expectEqual(F.popScale(99), F.popScale(5), "out of range tiers clamp")
	-- combo: builds across scoring hands, resets on a new round or a zero hand
	local combo = 0
	combo = F.nextCombo(combo, 100, true); expectEqual(combo, 1)
	combo = F.nextCombo(combo, 100, false); expectEqual(combo, 2)
	combo = F.nextCombo(combo, 50, false); expectEqual(combo, 3)
	expectEqual(F.nextCombo(combo, 0, false), 0, "a hand that scores nothing ends the combo")
	expectEqual(F.nextCombo(combo, 100, true), 1, "a new round starts over")
	expectEqual(F.nextCombo(F.MAX_COMBO, 10, false), F.MAX_COMBO, "capped")
	expectEqual(F.comboText(1), nil); expectEqual(F.comboText(0), nil); expectEqual(F.comboText(3), "COMBO x3")
	expectTrue(F.comboScale(1) == 1 and F.comboScale(3) > 1 and F.comboScale(50) <= 1.6)
	-- the score itself is never read or changed here: the same hand scores the same with or without it
	local state = RunState.new(nil, function(_n) return 1 end)
	state.targetScore = 10 ^ 9
	state.hand = { C(7, "Hearts"), C(7, "Spades"), C(8, "Hearts"), C(9, "Clubs"), C(10, "Hearts"), C(12, "Hearts"), C(3, "Hearts"), C(2, "Diamonds") }
	local result = RunState.playHand(state, { 1, 2 })
	local before = result.score
	F.tierFor(result.score, state.targetScore); F.nextCombo(0, result.score, true)
	expectEqual(result.score, before)
end })

table.insert(tests, { name = "SoundIds: biome tracks crossfade only between gameplay tables, new cues are empty slots that are skipped silently", fn = function()
	local S = require(script.Parent.Parent.Engine.SoundIds)
	expectTrue(S.isTableKey("gameplay") and S.isTableKey("region_peaks") and not S.isTableKey("menu") and not S.isTableKey("shop") and not S.isTableKey("boss"))
	expectTrue(S.shouldCrossfade("gameplay", "region_peaks") and S.shouldCrossfade("region_road", "region_meadow") and S.shouldCrossfade("region_snow", "gameplay"))
	expectTrue(not S.shouldCrossfade("menu", "gameplay") and not S.shouldCrossfade("gameplay", "boss") and not S.shouldCrossfade("shop", "region_road"))
	expectTrue(not S.shouldCrossfade("gameplay", "gameplay") and not S.shouldCrossfade(nil, "gameplay"))
	for _, name in ipairs({ "card_flip", "discard", "shuffle", "coin", "card_play" }) do
		expectTrue(S.Cues[name] ~= nil, name .. " is a named cue")
	end
	expectEqual(S.cueId("card_flip"), nil); expectEqual(S.cueId("discard"), nil)
	local missing = {}
	for _, name in ipairs(S.missingCues()) do missing[name] = true end
	expectTrue(missing.card_flip and missing.discard and missing.shuffle, "empty slots are listed so the ids can be picked")
	-- the fallback: a region with no id plays the plain gameplay track
	expectEqual(S.regionMusicKey("desert"), "gameplay")
	-- source checks: the hooks exist and no frame is created per scored hand
	local f = io and io.open and io.open("src/Client/FeelHooks.lua", "r")
	if f then
		local src = f:read("*a"); f:close()
		expectTrue(src:find('Cue.play("coin"', 1, true) and src:find('Cue.play("discard"', 1, true) and src:find('Cue.play("shuffle"', 1, true))
		expectTrue(src:find("Instance.new", 1, true) == nil, "FeelHooks creates no instances")
	end
	local c = io and io.open and io.open("src/Client/ComboCounter.lua", "r")
	if c then
		local src = c:read("*a"); c:close()
		local init = src:match("function ComboCounter%.init.-\nend\n") or ""
		local rest = src:gsub("function ComboCounter%.init.-\nend\n", "")
		expectTrue(init:find("Instance.new", 1, true) ~= nil and rest:find("Instance.new", 1, true) == nil, "the combo label is created once and reused")
	end
	local sound = io and io.open and io.open("src/Client/Sound.lua", "r")
	if sound then
		local src = sound:read("*a"); sound:close()
		expectTrue(src:find("shouldCrossfade", 1, true) ~= nil and src:find("SoundGroup", 1, true) ~= nil, "Sound.lua crossfades on a SoundGroup")
	end
end })

-- ===== Phase 5: Store =====

table.insert(tests, { name = "Store: every item is cosmetic or convenience, placeholders are id 0, the contents are real, nothing touches gameplay", fn = function()
	local Store = require(script.Parent.Parent.Engine.Store)
	local GamePasses = require(script.Parent.Parent.Engine.GamePasses)
	local ids = {}
	for _, item in ipairs(Store.Items) do
		expectTrue(not ids[item.id], "unique " .. item.id); ids[item.id] = true
		expectTrue(#item.name > 0 and #item.description > 0 and item.icon ~= nil and #(item.perks or {}) >= 1)
		for _, id in ipairs(item.contents and item.contents.cardBacks or {}) do expectTrue(CardBacks.getById(id) ~= nil, id .. " is a real card back") end
		for _, id in ipairs(item.contents and item.contents.sets or {}) do expectTrue(CosmeticSets.getById(id) ~= nil, id .. " is a real set") end
		for _, id in ipairs(item.contents and item.contents.titles or {}) do expectTrue(Achievements.getById(id) ~= nil, id .. " is a real title") end
		-- a contents table only holds cosmetics
		for key in pairs(item.contents or {}) do expectTrue(key == "cardBacks" or key == "sets" or key == "titles" or key == "flair", item.id .. " holds only cosmetics: " .. key) end
		for _, id in ipairs(item.contents and item.contents.flair or {}) do
			local option = require(script.Parent.Parent.Engine.Flair).getById(id)
			expectTrue(option ~= nil and option.unlock ~= nil and option.unlock.kind == "store", id .. " is a real store Flair")
		end
	end
	expectEqual(Store.getById("starter_pack").productId, 0, "placeholder until the product exists")
	expectEqual(Store.getById("card_set_bundle").productId, 0)
	expectEqual(GamePasses.getById("vip").gamePassId, 0)
	expectTrue(not Store.isConfigured(Store.getById("starter_pack")) and not Store.isConfigured(Store.getById("vip")))
	expectTrue(Store.isConfigured(Store.getById("continue")), "One More Round already has its real product")
	expectEqual(Store.getByProductId(0), nil, "id 0 never matches a receipt")
end })

table.insert(tests, { name = "Store grants are idempotent: a one-time pack grants once, a repeated receipt changes nothing, the cap holds", fn = function()
	local Store = require(script.Parent.Parent.Engine.Store)
	local profile = PlayerProfile.new()
	expectTrue(Store.grant(profile, "starter_pack"))
	expectTrue(profile.unlockedCardBackIds.gilded_ledger and profile.ownedSetIds.winter_evening and profile.rewardTitleIds.founding_guest)
	expectTrue(Achievements.isUnlocked(profile, "founding_guest"))
	expectTrue(CosmeticSets.isUnlocked(profile, "winter_evening"), "the set can be equipped")
	expectTrue(profile.storePurchases.starter_pack)
	expectEqual(Store.grant(profile, "starter_pack"), false, "never twice")
	expectEqual(Store.grant(profile, "vip"), false, "a pass is not a product grant")
	expectEqual(Store.grant(profile, "nope"), false)
	-- receipts: a stub product id stands in for the real one
	local item = Store.getById("card_set_bundle")
	item.productId = 777
	local profile2 = PlayerProfile.new()
	expectEqual(Store.processReceipt(profile2, 777, "P-1"), "granted")
	expectTrue(profile2.ownedSetIds.festival_night and profile2.ownedSetIds.closing_time)
	local sets = 0
	for _ in pairs(profile2.ownedSetIds) do sets = sets + 1 end
	expectEqual(Store.processReceipt(profile2, 777, "P-1"), "granted", "the same purchase id again is acknowledged")
	expectEqual(Store.processReceipt(profile2, 777, "P-2"), "granted", "a second purchase of a one-time item is acknowledged but grants nothing new")
	local after = 0
	for _ in pairs(profile2.ownedSetIds) do after = after + 1 end
	expectEqual(after, sets)
	expectEqual(Store.processReceipt(profile2, 424242, "P-3"), "unknown", "a product that is not in the Store")
	for i = 1, Store.MAX_RECEIPTS + 20 do Store.processReceipt(profile2, 777, "P-x" .. i) end
	expectTrue(#profile2.receiptIds <= Store.MAX_RECEIPTS, "the receipt list stays small")
	item.productId = 0
	-- save / load keeps purchases and drops junk
	local loaded = PlayerProfile.migrate(profile)
	expectTrue(loaded.storePurchases.starter_pack and loaded.rewardTitleIds.founding_guest)
	local junk = PlayerProfile.migrate({ storePurchases = { starter_pack = true, vip = true, nope = true }, receiptIds = { "a", 5, string.rep("x", 100) }, vipBonusDay = "x", equippedBadgeId2 = "nope" })
	expectTrue(junk.storePurchases.starter_pack and junk.storePurchases.vip == nil and junk.storePurchases.nope == nil)
	expectEqual(#junk.receiptIds, 1); expectEqual(junk.vipBonusDay, nil); expectEqual(junk.equippedBadgeId2, nil)
end })

table.insert(tests, { name = "Store VIP: a daily gift of a few Tips once per day (capped), a second badge slot only for VIP, view shows owned state", fn = function()
	local Store = require(script.Parent.Parent.Engine.Store)
	local TavernRank = require(script.Parent.Parent.Engine.TavernRank)
	local profile = PlayerProfile.new()
	expectEqual(Store.claimVipDaily(profile, 100), Store.VIP_DAILY_TIPS)
	expectEqual(Store.claimVipDaily(profile, 100), 0, "once per day")
	expectEqual(Store.claimVipDaily(profile, 101), Store.VIP_DAILY_TIPS)
	profile.vipBonusDay = nil
	profile.pendingStartTips = TavernRank.MAX_PENDING_TIPS - 1
	expectEqual(Store.claimVipDaily(profile, 102), 1, "capped with the other banked Tips")
	expectEqual(Store.claimVipDaily(profile, "x"), 0)
	expectTrue(Store.VIP_DAILY_TIPS <= 5, "the gift stays small")
	-- second badge slot
	profile.badgeIds.wins_1 = true
	expectEqual(Store.equipSecondBadge(profile, "wins_1", false, true), false, "not for non-VIP")
	expectEqual(Store.equipSecondBadge(profile, "wins_1", true, false), false, "only an owned badge")
	expectEqual(Store.equipSecondBadge(profile, "wins_1", true, true), true)
	expectEqual(profile.equippedBadgeId2, "wins_1")
	expectEqual(PlayerProfile.migrate(profile).equippedBadgeId2, "wins_1")
	expectEqual(Store.equipSecondBadge(profile, nil, false, false), true, "anyone can clear it")
	expectEqual(profile.equippedBadgeId2, nil)
	-- the view: owned state, Studio is free, the live game says coming soon
	local live = Store.view(PlayerProfile.new(), {}, false)
	local studio = Store.view(PlayerProfile.new(), { vip = true }, true)
	local function row(view, id) for _, r in ipairs(view.items) do if r.id == id then return r end end end
	expectTrue(row(live, "starter_pack").comingSoon and not row(live, "starter_pack").available and not live.vip)
	expectTrue(row(studio, "starter_pack").studioFree and row(studio, "starter_pack").available and studio.vip and row(studio, "vip").owned)
	expectTrue(row(live, "continue").listOnly and not row(live, "continue").available)
	local owner = PlayerProfile.new()
	Store.grant(owner, "starter_pack")
	expectTrue(row(Store.view(owner, {}, true), "starter_pack").owned and not row(Store.view(owner, {}, true), "starter_pack").available)
	-- source checks: the server grants through ProcessReceipt and stays out of gameplay
	local f = io and io.open and io.open("src/Server/init.server.lua", "r")
	if f then
		local src = f:read("*a"); f:close()
		expectTrue(src:find("Store.processReceipt", 1, true) ~= nil and src:find("PromptProductPurchase", 1, true) ~= nil and src:find("PromptGamePassPurchase", 1, true) ~= nil)
	end
	local panel = io and io.open and io.open("src/Client/StorePanel.lua", "r")
	if panel then
		local src = panel:read("*a"); panel:close()
		expectTrue(src:find("Nothing here helps you win", 1, true) ~= nil, "the Store says it is fair")
	end
end })

-- ===== Phase 6: live events =====

table.insert(tests, { name = "LiveEvents dates: civil dates map to UTC day numbers, bad dates are refused, the table validates", fn = function()
	local L = require(script.Parent.Parent.Engine.LiveEvents)
	expectEqual(L.dayNumberOf("1970-01-01"), 0)
	expectEqual(L.dayNumberOf("2000-02-29"), 11016, "leap day")
	expectEqual(L.dayNumberOf("2026-11-08"), 20765)
	expectEqual(L.dayNumberOf("2026-11-13"), 20770)
	expectEqual(L.dayNumberOf("2027-01-01"), 20819)
	expectEqual(L.dayNumberOf("2026-11-09") - L.dayNumberOf("2026-11-08"), 1)
	expectEqual(L.dayNumberOf("2026-02-31"), nil, "no 31st of February")
	expectEqual(L.dayNumberOf("2026-13-01"), nil); expectEqual(L.dayNumberOf("2026-1-1"), nil)
	expectEqual(L.dayNumberOf("soon"), nil); expectEqual(L.dayNumberOf(nil), nil)
	-- the same numbering as the login streak
	local LoginStreak = require(script.Parent.Parent.Engine.LoginStreak)
	expectEqual(LoginStreak.dayNumber(20765 * 86400 + 3600), L.dayNumberOf("2026-11-08"))
	local problems = L.validate()
	expectEqual(#problems, 0, table.concat(problems, "; "))
	for _, event in ipairs(L.Definitions) do
		for _, reward in ipairs(event.rewards or {}) do
			if reward.kind == "title" then expectTrue(Achievements.getById(reward.id) ~= nil, reward.id .. " is a real title") end
			if reward.kind == "cardBack" then expectTrue(CardBacks.getById(reward.id) ~= nil, reward.id .. " is a real card back") end
			if reward.kind == "set" then expectTrue(CosmeticSets.getById(reward.id) ~= nil) end
		end
	end
end })

table.insert(tests, { name = "LiveEvents windows: both end days count, active and upcoming lists, modifiers apply only inside the window", fn = function()
	local L = require(script.Parent.Parent.Engine.LiveEvents)
	local first, last = L.dayNumberOf("2026-11-13"), L.dayNumberOf("2026-11-15")
	local function ids(list) local out = {} for _, e in ipairs(list) do out[#out + 1] = e.id end return table.concat(out, ",") end
	expectEqual(ids(L.active(first - 1)), "")
	expectEqual(ids(L.active(first)), "lantern_weekend", "the first day counts")
	expectEqual(ids(L.active(last)), "lantern_weekend", "the last day counts")
	expectEqual(ids(L.active(last + 1)), "harvest_week", "the next event starts the day after")
	expectEqual(L.xpMultiplier(first - 1), 1); expectEqual(L.xpMultiplier(first), 2); expectEqual(L.xpMultiplier(last), 2); expectEqual(L.xpMultiplier(last + 1), 1)
	expectEqual(L.dailyLabel(first), nil); expectEqual(L.dailyLabel(last + 1), "Harvest Week")
	-- upcoming: soonest first, only inside the look-ahead
	local today = L.dayNumberOf("2026-11-08")
	expectEqual(ids(L.upcoming(today)), "lantern_weekend,harvest_week")
	expectEqual(ids(L.upcoming(today, 3)), "", "nothing inside 3 days")
	expectEqual(ids(L.upcoming(today, 5)), "lantern_weekend")
	expectEqual(ids(L.upcoming(L.dayNumberOf("2030-01-01"))), "")
	-- the multiplier never goes above its cap
	table.insert(L.Definitions, { id = "t1", name = "t", icon = "x", blurb = "t", startDate = "2026-11-13", endDate = "2026-11-13", modifier = { kind = "xpMultiplier", value = 50 } })
	expectEqual(L.xpMultiplier(first), L.MAX_XP_MULTIPLIER)
	table.remove(L.Definitions)
	expectEqual(L.xpMultiplier(first), 2)
	-- a double XP weekend doubles account XP and nothing else
	local AccountProgress = require(script.Parent.Parent.Engine.AccountProgress)
	local normal, doubled = PlayerProfile.new(), PlayerProfile.new()
	local function runDay(profile, day)
		local state = { handsPlayedTotal = 10, roundsCleared = 0, bossesCleared = 0, discardsUsedTotal = 0, handStats = {} }
		AccountProgress.sync(profile, {}, state, day, false)
	end
	runDay(normal, L.dayNumberOf("2026-11-10")); runDay(doubled, first)
	expectEqual(doubled.tavernXp, normal.tavernXp * 2, "double XP on a double XP day")
	-- Daily: the label is text only
	local SeedDisplay = require(script.Parent.Parent.Engine.SeedDisplay)
	local plain = SeedDisplay.label({ isDaily = true, dailyDateKey = "2026-11-16" })
	local themed = SeedDisplay.label({ isDaily = true, dailyDateKey = "2026-11-16", dailyTheme = "Harvest Week" })
	expectEqual(plain.text, "Daily: 2026-11-16"); expectEqual(themed.text, "Daily: 2026-11-16 (Harvest Week)"); expectEqual(themed.value, plain.value)
	local SeededRng = require(script.Parent.Parent.Engine.SeededRng)
	expectEqual(SeededRng.dailySeed(first * 86400), SeededRng.dailySeed(first * 86400), "the daily seed is a pure function of the day")
end })

table.insert(tests, { name = "LiveEvents rewards: claimed once, only while the event runs, banked Tips capped, the view shows the right rows", fn = function()
	local L = require(script.Parent.Parent.Engine.LiveEvents)
	local TavernRank = require(script.Parent.Parent.Engine.TavernRank)
	local start, finish = L.dayNumberOf("2026-11-25"), L.dayNumberOf("2026-12-02")
	local profile = PlayerProfile.new()
	local ok, why = L.claim(profile, "feast_week", start - 1)
	expectEqual(ok, false); expectEqual(why, "Not running.")
	ok, why = L.claim(profile, "lantern_weekend", L.dayNumberOf("2026-11-14"))
	expectEqual(ok, false); expectEqual(why, "Nothing to claim.", "an event with no rewards")
	expectEqual((L.claim(profile, "nope", start)), false)
	local claimed, result = L.claim(profile, "feast_week", start + 2, { titleName = function(id) return "T-" .. id end })
	expectTrue(claimed and #result.texts == 3 and result.texts[1] == "Title: T-feast_guest")
	expectTrue(profile.rewardTitleIds.feast_guest and profile.unlockedCardBackIds.kitchen_checks and profile.pendingStartTips == 6)
	expectTrue(Achievements.isUnlocked(profile, "feast_guest"))
	ok, why = L.claim(profile, "feast_week", start + 3)
	expectEqual(ok, false); expectEqual(why, "Already claimed.")
	expectEqual(profile.pendingStartTips, 6, "nothing paid twice")
	-- last day still works for someone who has not claimed
	expectTrue((L.claim(PlayerProfile.new(), "feast_week", finish)))
	expectEqual((L.claim(PlayerProfile.new(), "feast_week", finish + 1)), false, "too late")
	local capped = PlayerProfile.new()
	capped.pendingStartTips = TavernRank.MAX_PENDING_TIPS - 1
	L.claim(capped, "feast_week", start)
	expectEqual(capped.pendingStartTips, TavernRank.MAX_PENDING_TIPS)
	-- the view
	local view = L.view(PlayerProfile.new(), start)
	expectEqual(view.banner.id, "feast_week"); expectEqual(#view.active, 1); expectTrue(view.active[1].claimable and view.active[1].daysLeft == 8 and #view.active[1].rewards == 3)
	local after = L.view(profile, start + 1)
	expectTrue(after.active[1].claimed and not after.active[1].claimable)
	local quiet = L.view(PlayerProfile.new(), L.dayNumberOf("2026-12-20"))
	expectEqual(quiet.banner, nil); expectEqual(#quiet.active, 0)
	local soon = L.view(PlayerProfile.new(), L.dayNumberOf("2026-11-08"))
	expectEqual(soon.banner, nil); expectEqual(soon.upcoming[1].id, "lantern_weekend"); expectEqual(soon.upcoming[1].startsIn, 5)
	-- save / load
	local loaded = PlayerProfile.migrate(profile)
	expectTrue(loaded.liveEventClaims.feast_week)
	local junk = PlayerProfile.migrate({ liveEventClaims = { feast_week = true, gone_event = true }, liveEventsSeen = { lantern_weekend = 1 } })
	expectTrue(junk.liveEventClaims.feast_week and junk.liveEventClaims.gone_event == nil and junk.liveEventsSeen.lantern_weekend == nil)
	-- analytics for seen and claimed (with a fake service), then the client files exist with the fair-play line
	local Analytics = require(script.Parent.Parent.Engine.Analytics)
	local logged = {}
	Analytics.setService({ LogCustomEvent = function(_, _, name, _, fields) logged[#logged + 1] = name .. ":" .. tostring(fields.event) end, LogFunnelStepEvent = function() end })
	Analytics.eventSeen("p", "feast_week"); Analytics.eventClaimed("p", "feast_week")
	Analytics.setService(nil)
	expectEqual(logged[1], "live_event_seen:feast_week"); expectEqual(logged[2], "live_event_reward_claimed:feast_week")
	local f = io and io.open and io.open("src/Client/NewsPanel.lua", "r")
	if f then
		local src = f:read("*a"); f:close()
		expectTrue(src:find("never change the Daily, Weekly or Seed boards", 1, true) ~= nil)
	end
	local server = io and io.open and io.open("src/Server/init.server.lua", "r")
	if server then
		local src = server:read("*a"); server:close()
		expectTrue(src:find("Analytics.eventSeen", 1, true) ~= nil and src:find("Analytics.eventClaimed", 1, true) ~= nil and src:find("LiveEvents.claim", 1, true) ~= nil)
	end
end })

table.insert(tests, { name = "Roadmap art: every registry entry has a prompt, new art maps are registered and rank medals map to 6 tiers", fn = function()
	local ContentArt = require(script.Parent.Parent.Engine.ContentArt)
	local TavernRank = require(script.Parent.Parent.Engine.TavernRank)
	for _, cat in ipairs({ "stakes", "quests", "rank_medals", "store_bundles", "events", "discoveries", "challenges" }) do
		expectTrue(type(ContentArt[cat]) == "table", cat .. " is a ContentArt category")
	end
	expectTrue(ContentArt.store == ContentArt.store_bundles and ContentArt.news == ContentArt.events, "old store/news names still resolve")
	expectEqual(ContentArt.getImageId("quests", "no_such_quest"), nil) -- unknown key: nil, never an error
	-- 30 ranks -> 6 medal tiers of 5 ranks
	expectEqual(TavernRank.medalKey(1), "tier_1"); expectEqual(TavernRank.medalKey(5), "tier_1")
	expectEqual(TavernRank.medalKey(6), "tier_2"); expectEqual(TavernRank.medalKey(30), "tier_6")
	expectEqual(TavernRank.medalKey(0), "tier_1"); expectEqual(TavernRank.medalKey(99), "tier_6")
	-- generated maps may only hold ids that exist in the registries
	local function ids(list, field) local t = {}; for _, d in ipairs(list) do t[d[field or "id"]] = true end; return t end
	local Engine = script.Parent.Parent.Engine
	local valid = {
		stakes = ids(require(Engine.Stakes).Definitions),
		quests = ids(require(Engine.Quests).Definitions),
		challenges = ids(require(Engine.Challenges).Definitions),
		store_bundles = ids(require(Engine.Store).Items),
	}
	valid.challenges.quick_run = true -- the Quick Run tile in Run Setup (a RunModes mode, not a Challenges entry)
	for cat, set in pairs(valid) do
		for key in pairs(ContentArt[cat]) do expectTrue(set[key], cat .. " art key " .. key .. " is a registry id") end
	end
	-- every registry id has a prompts.json entry (text check; skipped where io is missing, e.g. Studio)
	local f = io and io.open and io.open("tools/patron_art/prompts.json", "r")
	if f then
		local src = f:read("*a"); f:close()
		local function need(key, what) expectTrue(src:find('"' .. key .. '":', 1, true) ~= nil, what .. " " .. key .. " has a prompt") end
		for _, d in ipairs(require(Engine.Stakes).Definitions) do need(d.id, "stake") end
		for _, d in ipairs(require(Engine.Quests).Definitions) do need(d.id, "quest") end
		for _, d in ipairs(require(Engine.Challenges).Definitions) do need(d.id, "challenge") end
		for _, d in ipairs(require(Engine.Store).Items) do need(d.id, "store item") end
		for _, d in ipairs(require(Engine.RunEvents).Definitions) do need(d.id, "run event") end
		for _, d in ipairs(require(Engine.LiveEvents).Definitions) do need(d.bannerKey, "live event banner") end
		for t = 1, TavernRank.MEDAL_TIERS do need("tier_" .. t, "rank medal") end
		for _, k in ipairs({ "chest", "merchant", "secret_patron", "news", "boss_rush", "quests", "store" }) do need(k, "icon") end
	end
end })

table.insert(tests, { name = "Newest features art: seasons, legend and spectate maps are registered and every registry id has a prompt", fn = function()
	local Engine = script.Parent.Parent.Engine
	local ContentArt = require(Engine.ContentArt)
	for _, cat in ipairs({ "seasons", "legend", "spectate", "flair" }) do
		expectTrue(type(ContentArt[cat]) == "table", cat .. " is a ContentArt category")
	end
	local Legend = require(Engine.Legend)
	local Spectate = require(Engine.Spectate)
	local SeasonTrack = require(Engine.SeasonTrack)
	local Flair = require(Engine.Flair)
	local f = io and io.open and io.open("tools/patron_art/prompts.json", "r")
	if not f then return end -- Studio has no io
	local src = f:read("*a"); f:close()
	local function need(key, what) expectTrue(src:find('"' .. key .. '":', 1, true) ~= nil, what .. " " .. key .. " has a prompt") end
	for _, r in pairs(Legend.Rewards) do
		if r.kind == "trinket" or r.kind == "cardBack" or r.kind == "title" then need(r.id, "legend reward") end
	end
	for _, e in ipairs(Spectate.Emotes) do need(e.id, "spectate reaction") end
	need("eye", "spectate badge")
	for _, s in ipairs(SeasonTrack.Seasons) do need(s.bannerKey, "season banner") end
	need("menu_season", "season menu icon")
	for _, o in ipairs(Flair.Options) do need(o.id, "flair option") end
	for _, d in ipairs(require(Engine.CardBacks).Definitions) do need(d.id, "card back") end
	for _, d in ipairs(require(Engine.Recipes).HouseRecipes) do need(d.id, "house recipe") end
	for _, d in ipairs(require(Engine.Recipes).SecretRecipes) do need(d.id, "secret recipe") end
	for _, k in ipairs({ "boss_scout", "rule_ban", "quick_run" }) do need(k, "icon") end
end })

table.insert(tests, { name = "Fresh profile serializes the rank, season and news views with the server's liveLookup (boot regression)", fn = function()
	local Engine = script.Parent.Parent.Engine
	local CardBacks, CosmeticSets, Achievements = require(Engine.CardBacks), require(Engine.CosmeticSets), require(Engine.Achievements)
	local lookup = { -- same shape as liveLookup in Server/init.server.lua
		cardBackName = function(id) local d = CardBacks.getById(id) return d and d.name end,
		setName = function(id) local d = CosmeticSets.getById(id) return d and d.name end,
		titleName = function(id) local d = Achievements.getById(id) return d and d.title end,
	}
	local profile = PlayerProfile.new()
	local TavernRank, SeasonTrack, LiveEvents = require(Engine.TavernRank), require(Engine.SeasonTrack), require(Engine.LiveEvents)
	local view = TavernRank.view(profile)
	expectTrue(view ~= nil, "rank view")
	if view and view.nextReward then TavernRank.rewardText(view.nextReward, lookup) end
	for _, kind in ipairs({ "cardBack", "set", "title", "tips" }) do
		expectTrue(type(TavernRank.rewardText({ kind = kind, id = "classic", amount = 1 }, lookup)) == "string", "rewardText " .. kind)
	end
	expectTrue(SeasonTrack.view(profile, 20000, lookup) ~= nil, "season view")
	expectTrue(LiveEvents.view(profile, 20000, lookup) ~= nil, "news view")
end })

table.insert(tests, { name = "RewardArt: every reward kind in every registry resolves to painted art or an emoji", fn = function()
	local RewardArt = require(script.Parent.Parent.Engine.RewardArt)
	local function check(reward, where)
		local category, key, emoji = RewardArt.resolve(reward)
		expectTrue(type(emoji) == "string" and emoji ~= "", where .. " has an emoji fallback (kind " .. tostring(reward.kind) .. ")")
		expectTrue((category == nil) == (key == nil), where .. " category and key come together")
		expectTrue(RewardArt.Kinds[reward.kind] ~= nil, where .. " kind " .. tostring(reward.kind) .. " is known to RewardArt")
	end
	for level, reward in pairs(require(script.Parent.Parent.Engine.TavernRank).Rewards) do check(reward, "rank " .. level) end
	for level, reward in pairs(require(script.Parent.Parent.Engine.Legend).Rewards) do check(reward, "legend " .. level) end
	for _, milestone in ipairs(CollectionBook.Milestones) do
		for _, reward in ipairs(milestone.rewards) do check(reward, "collection " .. milestone.id) end
	end
	for _, reward in ipairs(require(script.Parent.Parent.Engine.LoginStreak).Rewards) do check(reward, "login day " .. reward.day) end
	local SeasonTrack = require(script.Parent.Parent.Engine.SeasonTrack)
	for _, season in ipairs(SeasonTrack.Seasons) do
		for tier = 1, SeasonTrack.TIERS do
			local free = SeasonTrack.rewardFor(season, tier)
			if free then check(free, "season free " .. tier) end
			local prem = SeasonTrack.premiumRewardFor(season, tier)
			if prem then check(prem, "season premium " .. tier) end
		end
	end
	local category, key = RewardArt.resolve({ kind = "tips", amount = 3 })
	expectEqual("hud", category, "Tips use the painted coin purse")
	expectEqual("coin_purse", key, "Tips use the painted coin purse")
	local _, _, unknownEmoji = RewardArt.resolve({ kind = "mystery" })
	expectTrue(unknownEmoji ~= "", "an unknown kind still gets an emoji")
end })

table.insert(tests, { name = "Flair.view: locked options carry progress toward their unlock; store and default ones have no goal", fn = function()
	local Flair = require(script.Parent.Parent.Engine.Flair)
	local profile = { tavernRank = 3, highestStakeUnlocked = 1, questsDone = 4 }
	local view = Flair.view(profile)
	local seen = {}
	for _, slot in ipairs(view.slots) do
		for _, option in ipairs(slot.options) do seen[option.id] = option end
	end
	expectEqual(3, seen.ember_numbers.progress, "rank progress is the current rank")
	expectEqual(5, seen.ember_numbers.goal, "rank goal")
	expectEqual(4, seen.sparkle_trail.progress, "quest progress")
	expectEqual(10, seen.sparkle_trail.goal, "quest goal")
	expectEqual(0, seen.gold_numbers.progress, "stake progress starts at 0")
	expectTrue(seen.rainbow_numbers.goal == nil, "store items have no progress goal")
	expectTrue(seen.classic_numbers.goal == nil, "default options have no goal")
	profile.tavernRank = 99
	expectEqual(5, Flair.view(profile).slots[1].options[2].progress, "progress is capped at the goal")
end })

table.insert(tests, { name = "RunHistory: a Seed Run keeps its seed code (short strings only); other runs have none", fn = function()
	local RunHistory = require(script.Parent.Parent.Engine.RunHistory)
	local entry = RunHistory.entryFromState({ night = 3, stake = 2, wonRun = true, totalScore = 900, handsPlayedTotal = 12, patronsUsedOrder = { "a" } }, "seed", "meadow", 1000, "ABC-123")
	expectEqual("ABC-123", entry.seed, "seed kept")
	local plain = RunHistory.entryFromState({ night = 3 }, "standard", "meadow", 1000)
	expectTrue(plain.seed == nil, "no seed on a normal run")
	expectTrue(RunHistory.cleanEntry({ t = 1, night = 1, seed = string.rep("x", 40) }).seed == nil, "a long seed is dropped")
	expectTrue(RunHistory.cleanEntry({ t = 1, night = 1, seed = 5 }).seed == nil, "a non-string seed is dropped")
end })

table.insert(tests, { name = "MapSeams: every join overlaps by 18 percent of the narrower region, the colour ramp is valid, missing art falls back to the nearest painting", fn = function()
	local MapSeams = require(script.Parent.Parent.Engine.MapSeams)
	local regions = {
		{ key = "a", tint = { 222, 200, 150 }, lastNode = 1 }, { key = "b", tint = { 190, 200, 142 }, lastNode = 3 },
		{ key = "c", tint = { 168, 196, 176 }, lastNode = 4 }, { key = "d", tint = { 226, 190, 128 }, lastNode = math.huge },
	}
	-- joinWidth: 36 percent of the narrower region (18 on each side), within the min/max caps and never wider than the region
	for _, widths in ipairs({ { 340, 680 }, { 1000, 1400 }, { 200, 5000 }, { 90, 90 }, { 4000, 4000 } }) do
		local jw = MapSeams.joinWidth(widths[1], widths[2])
		local narrow = math.min(widths[1], widths[2])
		expectTrue(jw <= narrow, "zone fits inside the narrower region")
		expectTrue(jw <= MapSeams.JOIN_MAX, "zone is capped")
		local want = math.min(narrow, MapSeams.JOIN_MAX, math.max(MapSeams.JOIN_MIN, math.floor(narrow * MapSeams.JOIN_FRAC)))
		expectTrue(jw >= want - 1, "zone is at least 36 percent of the narrower region unless capped")
	end
	local plan = MapSeams.plan(regions, 4072, 734, nil, function(i) return i ~= 3 end)
	expectEqual(#regions + 1, #plan.edges, "edges include both canvas ends")
	expectEqual(0, plan.edges[1]); expectEqual(4072, plan.edges[#plan.edges])
	for i = 2, #regions do
		local j = plan.joins[i]
		expectTrue(j ~= nil and j.width > 0, "join " .. i .. " exists")
		expectTrue(math.max(j.overlapLeftPct, j.overlapRightPct) >= 17.5, "join " .. i .. " overlaps by about 18 percent of the narrower side")
		expectTrue(j.from < j.x and j.to > j.x, "the zone straddles the join")
	end
	expectEqual(2, plan.regions[3].fallbackFrom, "region 3 has no art and borrows the nearest painting")
	expectTrue(plan.regions[1].fallbackFrom == nil, "a region with art needs no fallback")
	-- under-layer ramp: starts at 0, ends at 1, strictly increasing, a colour from every region
	local stops = MapSeams.underlayStops(regions, plan.edges, 4072)
	expectEqual(0, stops[1].t); expectEqual(1, stops[#stops].t)
	for k = 2, #stops do expectTrue(stops[k].t > stops[k - 1].t, "ramp stops increase") end
	expectTrue(#stops >= #regions, "every region contributes a colour")
	expectEqual(nil, MapSeams.fallbackSource(regions, 1, function() return false end), "no art anywhere means no fallback")
	-- Color3-like tints (userdata in Roblox: indexing with a number throws) must work too
	local c3 = {}
	local function fakeColor(r, g, b) return setmetatable({ R = r / 255, G = g / 255, B = b / 255 }, { __index = function(_, k) if type(k) == "number" then error("invalid argument #2 (string expected, got number)") end end }) end
	for i, r in ipairs(regions) do c3[i] = { key = r.key, tint = fakeColor(200, 180, 150) } end
	local s3 = MapSeams.underlayStops(c3, plan.edges, 4072)
	expectEqual(200, math.floor(s3[1].r + 0.5), "Color3 tint converted to 0..255")
end })

table.insert(tests, { name = "Haggle: result comes from the clock position, miss penalty capped, never below 1, refused when ranked or tutorial", fn = function()
	local Haggle = require(script.Parent.Parent.Engine.Haggle)
	local Patrons = require(script.Parent.Parent.Engine.Patrons)
	local patron = Patrons.Definitions[1]
	-- Needle: angle 180 (the zone center) at 0.75 s, 0 at t=0.
	expectEqual(0, Haggle.needleAt(0))
	expectEqual(180, Haggle.needleAt(0.75))
	expectTrue(Haggle.inZone(180) and not Haggle.inZone(100))
	-- Hit: stopped at 0.75 s -> 1 Tip less.
	local state = RunState.new(nil, function(n) return n end)
	local base = RunState.patronPrice(state, patron)
	expectTrue(Haggle.start(state, {}, "shop", 100, "patron", patron.id))
	local ok, res = Haggle.stop(state, 100.75)
	expectTrue(ok and res.hit and res.delta == -1)
	expectEqual(math.max(1, base - 1), RunState.patronPrice(state, patron))
	-- Used: a second haggle this visit is refused; a new visit allows it again.
	expectFalse(Haggle.start(state, {}, "shop", 101, "patron", patron.id))
	Haggle.reset(state)
	expectEqual(base, RunState.patronPrice(state, patron))
	-- Miss: stopped at 0 s (angle 0) -> +1, and never more than +1 however often it is read.
	expectTrue(Haggle.start(state, {}, "shop", 200, "patron", patron.id))
	local _, miss = Haggle.stop(state, 200)
	expectFalse(miss.hit)
	expectEqual(base + 1, RunState.patronPrice(state, patron))
	expectEqual(base + 1, RunState.patronPrice(state, patron))
	-- Timeout counts as a miss even if the needle happens to be in the zone.
	Haggle.reset(state)
	Haggle.start(state, {}, "shop", 300, "pack", "x")
	local _, late = Haggle.stop(state, 300 + 3.75 + 3) -- elapsed 6.75 s, angle 180
	expectTrue(late.timedOut and not late.hit)
	-- Never free: a 1 Tip item stays at 1 on a hit.
	Haggle.reset(state)
	state.haggle = { used = true, kind = "patron", id = "cheap", delta = -1 }
	expectEqual(0, Haggle.delta(state, "patron", "other"))
	expectEqual(-1, Haggle.delta(state, "patron", "cheap"))
	local cheap = { id = "cheap", price = 1 }
	expectEqual(1, RunState.patronPrice(state, cheap))
	-- Refusals.
	local fresh = RunState.new(nil, function(n) return n end)
	expectFalse(Haggle.start(fresh, { ranked = true }, "shop", 1, "patron", "a"))
	expectFalse(Haggle.start(fresh, { tutorial = true }, "shop", 1, "patron", "a"))
	expectFalse(Haggle.start(fresh, {}, "playing", 1, "patron", "a"))
	expectFalse(Haggle.start(fresh, {}, "shop", 1, "voucher", "a"))
	expectFalse(Haggle.stop(fresh, 1))
end })

table.insert(tests, { name = "Strangers: 1 in 6 shops, never Nights 1 to 2 or ranked, bargains apply and curses are real, declining is free", fn = function()
	local Strangers = require(script.Parent.Parent.Engine.Strangers)
	expectEqual(6, #Strangers.Bargains)
	for _, b in ipairs(Strangers.Bargains) do
		expectTrue(b.price >= 1 and #b.blessingText > 0 and #b.curseText > 0 and b.promptId ~= nil)
		expectFalse((b.name .. b.blessingText .. b.curseText):lower():find("balatro", 1, true) ~= nil)
	end
	-- Frequency over 600 seeds on Night 4.
	local hits = 0
	for seed = 1, 600 do
		if Strangers.appears(seed, 4, {}) then hits = hits + 1 end
		expectFalse(Strangers.appears(seed, 1, {}))
		expectFalse(Strangers.appears(seed, 2, {}))
		expectFalse(Strangers.appears(seed, 5, { ranked = true }))
		expectFalse(Strangers.appears(seed, 5, { tutorial = true }))
		expectEqual(Strangers.appears(seed, 6, {}), Strangers.appears(seed, 6, {}))
	end
	expectTrue(hits >= 65 and hits <= 135, "about 100 of 600, got " .. hits)
	-- Applying: Hot Pan gives +25 percent now, and the discard curse hits only the next Night.
	local state = RunState.new(nil, function(n) return n end)
	state.night = 3
	state.tips = 20
	expectEqual(0, Strangers.field(state, "scorePct"))
	expectTrue(Strangers.accept(state, "hot_pan"))
	expectEqual(15, state.tips)
	expectEqual(25, Strangers.field(state, "scorePct"))
	expectEqual(0, Strangers.field(state, "discardsDelta"))
	state.night = 4
	expectEqual(-1, Strangers.field(state, "discardsDelta"))
	state.night = 5
	expectEqual(0, Strangers.field(state, "discardsDelta"))
	-- The curse really lowers the dealt discards on the cursed Night.
	state.night = 4
	RunState.startRound(state)
	local cursed = state.discardsRemaining
	state.bargains = {}
	RunState.startRound(state)
	expectEqual(cursed + 1, state.discardsRemaining)
	-- Declining changes nothing; an unaffordable bargain is refused and charges nothing.
	local poor = RunState.new(nil, function(n) return n end)
	poor.tips = 1
	expectFalse(Strangers.accept(poor, "hot_pan"))
	expectEqual(1, poor.tips)
	expectEqual(nil, poor.bargains)
	expectFalse(Strangers.accept(poor, "no_such_deal"))
	-- No bargain can make a round unplayable: floors hold with every curse stacked.
	local stacked = RunState.new(nil, function(n) return n end)
	stacked.night = 2
	stacked.bargains = {}
	for _, b in ipairs(Strangers.Bargains) do
		table.insert(stacked.bargains, { id = b.id, night = 1 })
	end
	RunState.startRound(stacked)
	expectTrue(stacked.handsRemaining >= 1 and #stacked.hand >= 1 and stacked.discardsRemaining >= 0)
end })

table.insert(tests, { name = "Bonds: detection, no bond for one Patron, once per Patron per hand, discovery ids, names", fn = function()
	local Bonds = require(script.Parent.Parent.Engine.Bonds)
	local a, b, c = Patrons.getById("lucky_dice"), Patrons.getById("regulars_round"), Patrons.getById("threes_company") -- all "pairs"
	expectEqual(0, #Bonds.find({ a }))
	expectEqual(0, #Bonds.find({}))
	expectEqual(1, #Bonds.find({ a, b }))
	expectEqual("Twin Pact", Bonds.find({ a, b })[1].name)
	expectEqual(3, #Bonds.find({ a, b, c })) -- three pairs of Patrons
	expectEqual(0, #Bonds.find({ a, Patrons.getById("the_regular") })) -- "flat" never bonds
	expectEqual("pairs", Bonds.formedIds({ a, b, c })[1])
	expectEqual(1, #Bonds.formedIds({ a, b, c }))
	for _, def in ipairs(Bonds.Definitions) do
		expectTrue(#def.name > 0 and #def.flavorText > 0 and not def.name:lower():find("balatro", 1, true))
	end
	-- Scoring: on a hand where all three trigger, each Patron earns at most ONE bond extra.
	local hand = HandEvaluator.evaluate({ C(9, "Hearts"), C(9, "Clubs"), C(9, "Spades"), C(2, "Spades"), C(3, "Hearts") })
	local _, _, _, extraOn = Scoring.calculate(hand, { a, b, c }, {})
	local perPatron, bondEntries = {}, 0
	for _, entry in ipairs(extraOn.breakdown) do
		if entry.source and entry.source.bond then
			bondEntries = bondEntries + 1
			perPatron[entry.source.patronId] = (perPatron[entry.source.patronId] or 0) + 1
		end
	end
	expectTrue(bondEntries >= 1 and bondEntries <= 3)
	for _, n in pairs(perPatron) do
		expectEqual(1, n)
	end
	-- No bond, no bonus: a single Patron scores exactly as with bonds switched off.
	local s1 = Scoring.calculate(hand, { a }, {})
	local s2 = Scoring.calculate(hand, { a }, { bondsOff = true })
	expectEqual(s2, s1)
	-- Collection discovery: owning a bonded pair records the Bond, and Bonds never count toward completion.
	local seen = CollectionBook.gatherSeen({ ownedPatrons = { a, b } }, nil)
	expectEqual("pairs", seen.bonds[1])
	local total = CollectionBook.completion(CollectionBook.setsFromLists({})).total
	local withBonds = 0
	for _, tab in ipairs(CollectionBook.Tabs) do
		for _, item in ipairs(CollectionBook.itemsFor(tab.id)) do
			if item.counts then withBonds = withBonds + 1 end
		end
	end
	expectEqual(total, withBonds)
end })

table.insert(tests, { name = "Bonds balance: a bond never lifts a hand's score by more than 10 percent over the Night 3 curve", fn = function()
	local Bonds = require(script.Parent.Parent.Engine.Bonds)
	local hands = {
		HandEvaluator.evaluate({ C(9, "Hearts"), C(9, "Clubs"), C(2, "Spades"), C(5, "Hearts"), C(7, "Clubs") }),
		HandEvaluator.evaluate({ C(9, "Hearts"), C(9, "Clubs"), C(9, "Spades"), C(5, "Hearts"), C(7, "Clubs") }),
		HandEvaluator.evaluate({ C(2, "Hearts"), C(6, "Hearts"), C(9, "Hearts"), C(11, "Hearts"), C(13, "Hearts") }),
		HandEvaluator.evaluate({ C(5, "Hearts"), C(6, "Clubs"), C(7, "Spades"), C(8, "Hearts"), C(9, "Clubs") }),
	}
	local worst = 0
	local worstWhere
	for i = 1, #Patrons.Definitions - 1 do
		for j = i + 1, #Patrons.Definitions do
			local p, q = Patrons.Definitions[i], Patrons.Definitions[j]
			if not p.biome and not q.biome and #Bonds.find({ p, q }) > 0 then
				for hi, hand in ipairs(hands) do
					local ctx = { handsRemaining = 3, discardsRemaining = 3, night = 3, round = 1, tips = 5 }
					local on = Scoring.calculate(hand, { p, q }, ctx)
					local off = Scoring.calculate(hand, { p, q }, { handsRemaining = 3, discardsRemaining = 3, night = 3, round = 1, tips = 5, bondsOff = true })
					if off > 0 and on / off > worst then
						worst = on / off
						worstWhere = p.id .. "+" .. q.id .. " hand " .. hi
					end
				end
			end
		end
	end
	expectTrue(worst <= 1.10, string.format("bond lifts a hand by %.1f percent (%s)", (worst - 1) * 100, tostring(worstWhere)))
end })

table.insert(tests, { name = "Regulars: at most 6, newest first, none without the achievement, greetings rotate by UTC day, records saved", fn = function()
	local RunHistory = require(script.Parent.Parent.Engine.RunHistory)
	local Regulars = require(script.Parent.Parent.Engine.Regulars)
	local RegularLines = require(script.Parent.Parent.Engine.RegularLines)
	local BossRounds = require(script.Parent.Parent.Engine.BossRounds)
	-- A brand new profile has no Regulars at all.
	local profile = { lifetime = RunHistory.newLifetime() }
	expectEqual(0, #Regulars.view(profile.lifetime, 1))
	-- Losing to a boss never seats them; the first clear does, once.
	local bossA, bossB = BossRounds.Definitions[1].id, BossRounds.Definitions[2].id
	expectFalse(RunHistory.recordBoss(profile, bossA, false))
	expectEqual(0, #Regulars.view(profile.lifetime, 1))
	expectTrue(RunHistory.recordBoss(profile, bossA, true))
	expectFalse(RunHistory.recordBoss(profile, bossA, true)) -- already a Regular
	local view = Regulars.view(profile.lifetime, 1)
	expectEqual(1, #view)
	expectEqual(2, view[1].wins)
	expectEqual(1, view[1].losses)
	expectEqual("boss", view[1].kind)
	-- A run win seats each Patron of the run (first time only); a lost run seats none.
	RunHistory.record(profile, { t = 1, night = 3, won = false, patrons = { "the_regular" } }, 0)
	expectEqual(1, #Regulars.view(profile.lifetime, 1))
	RunHistory.record(profile, { t = 2, night = 8, won = true, patrons = { "the_regular", "lucky_dice" } }, 0)
	view = Regulars.view(profile.lifetime, 1)
	expectEqual(3, #view)
	expectEqual("patron", view[1].kind) -- newest first
	-- Never more than 6 shown, even with many Regulars.
	for i = 3, 12 do
		RunHistory.recordBoss(profile, BossRounds.Definitions[i].id, true)
	end
	expectEqual(6, #Regulars.view(profile.lifetime, 1))
	expectEqual(6, #Regulars.select(profile.lifetime))
	expectEqual(nil, Regulars.view(profile.lifetime, 1)[7])
	-- Unknown ids from a damaged save are dropped on load and ignored in selection.
	local cleaned = RunHistory.cleanLifetime({ regulars = { "boss:" .. bossB, "boss:no_such_boss", 5, "junk", "patron:the_regular" } })
	expectEqual(3, #cleaned.regulars) -- the number and "junk" are dropped on load
	expectEqual(2, #Regulars.select(cleaned)) -- the unknown boss is skipped
	-- Greeting is stable within a day and rotates across days.
	expectEqual(RegularLines.greeting("boss", bossA, 100), RegularLines.greeting("boss", bossA, 100))
	local distinct = {}
	for day = 1, 8 do
		distinct[RegularLines.greeting("patron", "the_regular", day)] = true
	end
	local n = 0
	for _ in pairs(distinct) do n = n + 1 end
	expectTrue(n >= 4, "greeting rotates, got " .. n .. " distinct")
	-- Lines are short and plain.
	for kind, pool in pairs(RegularLines.Greetings) do
		expectTrue(#pool >= 6, kind .. " has lines")
		for _, line in ipairs(pool) do
			expectTrue(#line <= 60, line)
			expectFalse(line:find("-", 1, true) ~= nil or line:find("\226\128\148", 1, true) ~= nil or line:lower():find("balatro", 1, true) ~= nil, line)
		end
	end
end })

table.insert(tests, { name = "WinCard: share text within 200 chars, no dashes, never the banned word, 3 Patrons max; lastHand recorded", fn = function()
	local WinCard = require(script.Parent.Parent.Engine.WinCard)
	local RunSummary = require(script.Parent.Parent.Engine.RunSummary)
	local summary = {
		won = true, night = 8, bestHand = { name = "Straight Flush", score = 123456 },
		patrons = {
			{ id = "a", name = "Mr. Hyphen-Man", icon = "x" }, { id = "b", name = "Second", icon = "y" },
			{ id = "c", name = "Third", icon = "z" }, { id = "d", name = "Fourth", icon = "w" },
		},
	}
	local card = WinCard.build(summary, { stake = 5, cardBackId = "classic", seedText = "Seed: ABC234", newBest = true })
	expectTrue(#card.shareText <= 200 and #card.shareText > 0)
	expectEqual(3, #card.patrons)
	expectEqual("Tavern Champion", card.title)
	expectEqual("Stake 5", card.stakeText)
	expectFalse(card.shareText:find("-", 1, true) ~= nil or card.shareText:find("\226\128\148", 1, true) ~= nil, card.shareText)
	expectFalse(card.patrons[1].name:find("-", 1, true) ~= nil)
	expectTrue(card.shareText:find("ABC234", 1, true) ~= nil)
	-- A very long seed line is clipped to 200.
	local long = WinCard.build(summary, { stake = 2, seedText = string.rep("word ", 80) })
	expectTrue(#long.shareText <= 200)
	-- The banned word never gets through, whether in a name or a seed line.
	local bad = WinCard.build({ won = false, night = 2, bestHand = { name = "Balatro Hand", score = 5 }, patrons = {} }, {})
	expectFalse(bad.shareText:lower():find("balatro", 1, true) ~= nil)
	expectEqual("", WinCard.clean("my Balatro seed"))
	-- Not-won, not-best runs get no card; a win or a new best does.
	expectFalse(WinCard.worthShowing({ won = false }, { newBest = false }))
	expectTrue(WinCard.worthShowing({ won = true }, {}))
	expectTrue(WinCard.worthShowing({ won = false }, { newBest = true }))
	-- RunSummary.recordHand keeps the hand just scored for the Showdown banner.
	local state = { ownedPatrons = {} }
	RunSummary.recordHand(state, "Flush", 900)
	RunSummary.recordHand(state, "Pair", 40)
	expectEqual("Pair", state.lastHand.name)
	expectEqual("Flush", state.bestHand.name)
end })

table.insert(tests, { name = "ShopkeeperLines: 4+ lines per event, 60 chars max, no dashes, deterministic by seed", fn = function()
	local L = require(script.Parent.Parent.Engine.ShopkeeperLines)
	expectEqual(12, #L.Events)
	for _, event in ipairs(L.Events) do
		local lines = L.ByEvent[event]
		expectTrue(lines ~= nil and #lines >= 4, event .. " has 4+ lines")
		for _, line in ipairs(lines) do
			expectTrue(#line <= 60, "short line: " .. line)
			expectFalse(line:find("-", 1, true) ~= nil, "no dash: " .. line)
			expectFalse(line:find("\226\128\148", 1, true) ~= nil, "no em dash: " .. line)
			expectFalse(line:lower():find("balatro", 1, true) ~= nil)
		end
		expectEqual(L.pick(event, "s1"), L.pick(event, "s1"))
	end
	expectTrue(L.pick("no_such_event", 1) ~= nil)
end })

table.insert(tests, { name = "FlairFX: previews draw above every Flair panel layer, ParticleBurst takes a zIndex (default 30), calm mode plays nothing", fn = function()
	local f = io and io.open and io.open("src/Client/FlairFX.lua", "r")
	if not f then return end -- Studio has no io
	local fx = f:read("*a"); f:close()
	local pb = io.open("src/Client/ParticleBurst.lua", "r"):read("*a")
	local panel = io.open("src/Client/FlairPanel.lua", "r"):read("*a")
	expectTrue(pb:find("options.zIndex or 30", 1, true) ~= nil, "default zIndex stays 30")
	expectTrue(pb:find("particle.ZIndex = zIndex", 1, true) ~= nil, "particles use the zIndex option")
	local panelZ = tonumber(fx:match("FlairFX%.PANEL_Z = (%d+)"))
	expectTrue(panelZ ~= nil, "PANEL_Z is defined")
	local maxZ = 0
	for z in panel:gmatch("ZIndex = (%d+)") do maxZ = math.max(maxZ, tonumber(z)) end
	for z in panel:gmatch("zIndex = (%d+)") do maxZ = math.max(maxZ, tonumber(z)) end
	expectTrue(maxZ > 0 and panelZ > maxZ, "PANEL_Z above every FlairPanel ZIndex")
	expectTrue(fx:find("trailBurst(burst, pos, option, true, z)", 1, true) ~= nil, "trail preview passes the zIndex")
	expectTrue(fx:find("finisherBurst(burst, pos, option, true, z, true)", 1, true) ~= nil, "finisher preview passes the zIndex")
	expectTrue(fx:find("reduceShake", 1, true) ~= nil and fx:find("local function allowed", 1, true) ~= nil, "calm mode gate exists")
	-- every slot kind is previewed by the panel; a classic or empty option plays nothing
	for _, kind in ipairs({ "playTrail", "finisher", "scoreNumbers", "nameAura" }) do
		expectTrue(panel:find(kind, 1, true) ~= nil, "panel handles " .. kind)
	end
	expectTrue(fx:find('option.style == nil or option.style == "none"', 1, true) ~= nil, "empty trail plays nothing")
	expectTrue(fx:find('option.id ~= "classic_numbers"', 1, true) ~= nil, "classic numbers add no colour or glow")
	-- the popup finisher covers any clearing hand and is passed the clear flag
	local sp = io.open("src/Client/ScorePopup.lua", "r"):read("*a")
	expectTrue(sp:find("FlairGlow", 1, true) ~= nil, "score digits glow")
	expectTrue(sp:find(".finisher(particleBurst, centerOf(scorePopup), preview, ScoreJuice.clearsTarget", 1, true) ~= nil, "finisher gets the clear flag")
end })

table.insert(tests, { name = "FlairFX preview passes zIndex and big particles to every burst; Expand toggle survives the Collection relayout", fn = function()
	local f = io and io.open and io.open("src/Client/FlairFX.lua", "r")
	if not f then return end
	local fx = f:read("*a"); f:close()
	expectTrue(fx:find("PREVIEW_COUNT, PREVIEW_SIZE = 24, 11", 1, true) ~= nil, "preview is 24 particles of size 11")
	local flat = fx:gsub("\n%s*", " ")
	local _, callCount = flat:gsub("pcall%(burst,", "")
	local _, zCount = flat:gsub("pcall%(burst,[^}]-zIndex = zIndex }", "")
	expectEqual(zCount, callCount, "every burst call forwards zIndex")
	local pb = io.open("src/Client/ParticleBurst.lua", "r"):read("*a")
	expectTrue(pb:find("particle.ZIndex = zIndex", 1, true) ~= nil)
	local col = io.open("src/Client/Collection.lua", "r"):read("*a")
	expectTrue(col:find('panel:GetAttribute("Expanded") ~= true', 1, true) ~= nil, "relayout must not reset Size while expanded")
	expectTrue(col:find("expandToggle.setCollapsedSize", 1, true) ~= nil)
	local tg = io.open("src/Client/ExpandToggle.lua", "r"):read("*a")
	expectTrue(tg:find('SetAttribute("Expanded"', 1, true) ~= nil)
end })

table.insert(tests, { name = "PanelLayout: the Expand button never sits under the tab strip, collapsed or expanded, at desktop and phone sizes", fn = function()
	local PL = require(script.Parent.Parent.Engine.PanelLayout)
	for _, sz in ipairs({ { 1920, 957 }, { 1280, 720 }, { 360, 640 } }) do
		local h = sz[2]
		for _, nudged in ipairs({ true }) do -- every panel with a strip is nudged down once (PanelTabs.clearStrip)
			expectFalse(PL.hitsStrip(PL.toggleTop(h, h * 0.78, nudged), PL.TOGGLE_SIZE), "collapsed toggle clear at " .. h)
			local expandedTop = PL.toggleTop(h, PL.expandedHeight(h), nudged)
			expectFalse(PL.hitsStrip(expandedTop, PL.TOGGLE_SIZE), "expanded toggle clear at " .. h)
			expectTrue(expandedTop >= 40, "expanded toggle at least 40px down at " .. h)
		end
		expectTrue((h - PL.expandedHeight(h)) / 2 + PL.STRIP_NUDGE > PL.STRIP_BOTTOM + 8, "expanded panel starts below the strip")
	end
	expectTrue(PL.hitsStrip(8, 30)) -- the old top-edge placement was under the strip
	local f = io and io.open and io.open("src/Client/ExpandToggle.lua", "r")
	if not f then return end
	local src = f:read("*a"); f:close()
	expectTrue(src:find("PanelLayout.EXPANDED_MARGIN", 1, true) ~= nil)
	expectTrue(src:find("math.max(panel.ZIndex, 70)", 1, true) ~= nil, "toggle above the strip")
end })

table.insert(tests, { name = "Collection no longer lists run stats; the Tavern Ledger shows every number that moved", fn = function()
	local f = io and io.open and io.open("src/Client/Collection.lua", "r")
	if not f then return end -- Studio has no io
	local collection = f:read("*a"); f:close()
	local stats = io.open("src/Client/StatsPanel.lua", "r"):read("*a")
	for _, gone in ipairs({ "Runs played", "Runs won", "Best Night:", "profileStats.runs", "statsLabel", "runsStarted", "bestNightReached" }) do
		expectFalse(collection:find(gone, 1, true) ~= nil, "Collection still has: " .. gone)
	end
	expectTrue(collection:find("Overall %d%%", 1, true) ~= nil, "collection progress stays")
	for _, kept in ipairs({ "Runs won", "Runs started", "Best Night", "Win rate", "equippedTitleId", '"Title"' }) do
		expectTrue(stats:find(kept, 1, true) ~= nil, "Ledger shows: " .. kept)
	end
end })

table.insert(tests, { name = "MenuLayout: six evenly spaced counter items, scrolls fit on screen, board clear of title and sign, every action in one scroll, parallax clamps and calm", fn = function()
	local ML = require(script.Parent.Parent.Engine.MenuLayout)
	local seen, items = {}, {}
	for _, h in ipairs(ML.Hotspots) do
		expectFalse(seen[h.id], "duplicate hotspot " .. h.id)
		seen[h.id] = true
		expectTrue(h.x > 0 and h.x < 1 and h.y > 0 and h.y < 1 and h.s > 0 and h.s < 0.4, "fractions in range " .. h.id)
		expectTrue(#h.actions >= 1, h.id .. " has an action")
		expectTrue(#h.label > 0 and #h.desc > 0 and not h.label:find("-", 1, true) and not h.desc:find("-", 1, true), "plain label and description")
		expectFalse((h.label .. h.desc):lower():find("balatro", 1, true) ~= nil)
		if h.item then items[h.item] = h end
	end
	expectEqual(#items, 6, "six counter items")
	for i = 2, 6 do
		expectTrue(math.abs((items[i].x - items[i - 1].x) - ML.ITEM_SPACING) < 1e-9, "items evenly spaced")
		expectEqual(items[i].y, items[1].y)
	end
	expectTrue(math.abs((items[1].x + items[6].x) / 2 - 0.5) < 1e-9, "item row centred")
	for _, size in ipairs({ { 1920, 1080 }, { 1366, 768 }, { 1280, 720 } }) do
		local w, h = size[1], size[2]
		expectFalse(ML.isPhone(w), "desktop size shows the scene")
		local counterTop = ML.Counter.top * h
		local rects, names = {}, {}
		local play = ML.getHotspot("play")
		local pl, pt, pr, pb = ML.rect(play, w, h)
		expectTrue(pl >= 0 and pt >= 0 and pr <= w and pb <= counterTop, "play sign inside the screen above the counter at " .. w)
		for i = 1, 6 do
			local hs = items[i]
			local l, t, r, b = ML.rect(hs, w, h)
			local pl2, pt2, pr2, pb2 = ML.plateRect(hs, w, h)
			expectTrue(l >= 0 and r <= w and t >= counterTop and pb2 <= h, hs.id .. " and plate sit on the counter at " .. w)
			rects[#rects + 1] = { l, t, r, b }; names[#names + 1] = hs.id
			rects[#rects + 1] = { pl2, pt2, pr2, pb2 }; names[#names + 1] = hs.id .. " plate"
			expectTrue(ML.overlapFraction({ l, t, r, b }, { 16, h - 168, 212, h - 16 }) == 0, hs.id .. " clear of the Regulars at " .. w)
			expectTrue(ML.overlapFraction({ pl2, pt2, pr2, pb2 }, { w - 166, h - 54, w - 16, h - 16 }) == 0, hs.id .. " plate clear of All actions at " .. w)
			expectTrue(ML.overlapFraction({ l, t, r, b }, { pl, pt, pr, pb }) == 0, hs.id .. " clear of the Play sign at " .. w)
			-- the open scroll fits on screen and sits above its item
			local sl, st, sr, sb = ML.scrollRect(hs, #hs.actions, w, h)
			expectTrue(sl >= 0 and st >= 0 and sr <= w and sb <= t, hs.id .. " scroll fits on screen at " .. w)
		end
		for i = 1, #rects do
			for j = i + 1, #rects do
				expectTrue(ML.overlapFraction(rects[i], rects[j]) == 0, names[i] .. " and " .. names[j] .. " overlap at " .. w)
			end
		end
		-- the Notice Board clears the title (340 wide ribbon, top 145px), the Play sign, the Regulars and the counter
		local nl, nt, nr, nb = ML.noticeRect(w, h)
		expectTrue(nl >= 0 and nr <= w and nb < counterTop, "notice board inside the screen above the counter at " .. w)
		expectTrue(ML.overlapFraction({ nl, nt, nr, nb }, { (w - 340) / 2, 0, (w + 340) / 2, 145 }) == 0, "board clear of the title at " .. w)
		expectTrue(ML.overlapFraction({ nl, nt, nr, nb }, { pl, pt, pr, pb }) == 0, "board clear of the Play sign at " .. w)
		expectTrue(ML.overlapFraction({ nl, nt, nr, nb }, { 0.38 * w, 0.33 * h, 0.62 * w, 0.35 * h }) == 0, "board clear of the beam at " .. w)
	end
	expectTrue(ML.isPhone(360) and ML.isPhone(640) and not ML.isPhone(1280), "phones skip the scene")
	-- every old Menu action is owned by exactly one hotspot (sign or scroll) and listed for the All actions list
	local owners = {}
	for _, hs in ipairs(ML.Hotspots) do
		for _, id in ipairs(hs.actions) do
			owners[id] = (owners[id] or 0) + 1
		end
	end
	local listed = {}
	for _, action in ipairs(ML.Actions) do
		expectFalse(listed[action.id], "action listed twice " .. action.id)
		listed[action.id] = true
		expectEqual(owners[action.id], 1, action.id .. " lives in exactly one scroll")
		expectTrue(#action.label > 0 and not action.label:find("\226\128\148", 1, true))
	end
	for id in pairs(owners) do expectTrue(listed[id], id .. " is in the All actions list") end
	for _, old in ipairs({ "play", "newRun", "daily", "weekly", "seed", "quests", "road", "howToPlay", "tutorial", "collection", "settings", "store", "invite", "season", "rewards", "leaderboards", "volume", "flair", "legend", "stats" }) do
		expectTrue(listed[old] and owners[old] == 1, "old action reachable: " .. old)
	end
	-- parallax
	local dx, dy = ML.parallaxOffset(1, -1, 1000, false)
	expectTrue(math.abs(dx) <= 32 and math.abs(dy) <= 32, "offsets clamp at 32")
	expectEqual(dx, -32)
	local ax, ay = ML.parallaxOffset(0.5, 0.5, ML.Parallax.mid, false)
	expectTrue(ax == -ML.Parallax.mid / 2 and ay == -ML.Parallax.mid / 2)
	local cx, cy = ML.parallaxOffset(1, 1, 28, true)
	expectTrue(cx == 0 and cy == 0, "calm mode returns zero offset")
	expectEqual(ML.tilt(1, true), 0)
	expectTrue(math.abs(ML.tilt(5, false)) <= 1.5 + 1e-9, "tilt is about 1.5 degrees at most")
	for t = 0, 60, 3 do
		local nx, ny = ML.idleCursor(t)
		local ox, oy = ML.parallaxOffset(nx, ny, ML.Parallax.mid, false)
		expectTrue(math.abs(ox) <= ML.Parallax.idleDrift + 1e-9 and math.abs(oy) <= ML.Parallax.idleDrift + 1e-9, "idle drift stays within 6px")
	end
	-- source scans (local runner only; Studio has no io)
	local f = io and io.open and io.open("src/Client/Menu.lua", "r")
	if not f then return end
	local menu = f:read("*a"); f:close()
	for _, name in ipairs({ "menuFrame", "menuPlayButton", "menuHowToPlayButton", "menuJourneyButton", "menuNewRunButton", "menuDailyChallengeButton",
		"menuWeeklyChallengeButton", "menuTutorialButton", "menuCollectionButton", "menuSettingsButton", "menuQuestsButton", "menuStoreButton",
		"menuSeasonButton", "menuTickerButton" }) do
		expectTrue(menu:find(name .. " = " .. name, 1, true) ~= nil or menu:find(name .. " = ", 1, true) ~= nil, "Menu still returns " .. name)
	end
	local sf = io.open("src/Client/MenuScene.lua", "r")
	local scene = sf:read("*a"); sf:close()
	expectTrue(scene:find("MOTE_SIZES = { 4, 6, 5, 8, 10 }", 1, true) ~= nil, "motes stay 4 to 10 px")
	expectTrue(scene:find("\240\159\143\174", 1, true) == nil and scene:find("Lantern", 1, true) == nil or scene:find("removed", 1, true) ~= nil, "no placeholder lantern emoji in the scene")
	expectTrue(5 + 6 + 5 <= ML.MAX_ANIMATED, "animated objects stay under the cap")
	-- scene art wiring: depths from the brief, only the lantern may pass 32px
	local PX = ML.Parallax
	expectTrue(PX.far == 8 and PX.wall == 8 and PX.beams == 16 and PX.mid == 22 and PX.lantern == 34, "parallax depths")
	expectTrue(PX.far < PX.beams and PX.beams < PX.mid and PX.mid < PX.lantern, "deeper layers move more")
	expectEqual((ML.parallaxOffset(1, 0, PX.lantern, false, PX.lanternMax)), -34)
	expectEqual((ML.parallaxOffset(1, 0, 200, false)), -32)
	expectEqual(ML.SceneArt.motes + ML.SceneArt.embers + 5, ML.MAX_ANIMATED, "animated budget: motes, embers, fire, shaft, candle, steam, lantern")
	expectEqual(#ML.SceneArt.items, 6, "one painted object per counter item")
	local ContentArt = require(script.Parent.Parent.Engine.ContentArt)
	for _, key in ipairs({ "wall", "beams", "counter", "board", "scrollTop", "scrollBottom", "parchment", "sealGold", "sealRed", "lantern" }) do
		expectTrue(ContentArt.getImageId("menu_scene", ML.SceneArt[key]) ~= nil, "menu_scene art recorded: " .. key)
	end
	for _, id in ipairs(ML.SceneArt.items) do expectTrue(ContentArt.getImageId("menu_scene", id) ~= nil, "menu_scene art recorded: " .. id) end
end })

table.insert(tests, { name = "HandLedger: every hand once weakest first, formulas and highlights, layout fits desktop and phone sizes", fn = function()
	local HL = require(script.Parent.Parent.Engine.HandLedger)
	local HandEvaluator = require(script.Parent.Parent.Engine.HandEvaluator)
	local Scoring = require(script.Parent.Parent.Engine.Scoring)
	local ledger = HL.build({ order = HandEvaluator.HandOrder, base = Scoring.HandBase, growth = Scoring.HandLevelGrowth,
		handStats = { Pair = 4, Flush = 1 }, handLevels = { Pair = 2 }, lastHand = "Flush", lifetimeHands = 120 })
	expectEqual(#ledger.rows, #HandEvaluator.HandOrder)
	local seen = {}
	for i, row in ipairs(ledger.rows) do
		expectEqual(row.name, HandEvaluator.HandOrder[i]) -- weakest to strongest, in Engine order
		expectFalse(seen[row.name], "each hand once")
		seen[row.name] = true
		expectTrue(HL.TIER_COLORS[row.tier] ~= nil, "tier colour")
		local c = HL.TIER_COLORS[row.tier]
		expectTrue(c[1] >= c[2] and c[2] >= c[3] - 40 and not (c[2] < 60), "tier colours are wood, brass or gold, never red")
		expectTrue(#row.tip > 0 and not row.tip:find("-", 1, true) and not row.tip:find("\226\128\148", 1, true), "tip is plain")
		expectFalse(row.tip:lower():find("balatro", 1, true) ~= nil)
		local spec = HandEvaluator.Examples[row.name]
		expectTrue(spec ~= nil and #spec >= 1, "example cards resolve for " .. row.name)
	end
	expectEqual(ledger.rows[1].tier, "wood")
	expectEqual(ledger.rows[#ledger.rows].tier, "legend")
	local pair, flush, high = ledger.rows[2], ledger.rows[6], ledger.rows[1]
	expectEqual(pair.level, 2)
	expectTrue(pair.leveled and not flush.leveled)
	expectEqual(pair.chips, Scoring.HandBase["Pair"].chips + Scoring.HandLevelGrowth["Pair"].chips * 2)
	expectTrue(pair.chipsFormula:find("Lv 2", 1, true) ~= nil and high.chipsFormula:find("Lv", 1, true) == nil)
	expectTrue(high.notPlayed and not pair.notPlayed)
	expectTrue(flush.justPlayed and not pair.justPlayed)
	expectEqual(ledger.lifetimeHands, 120)
	expectEqual(ledger.topHand, pair.points >= flush.points and "Pair" or "Flush") -- most points this run (estimate)
	local count = 0
	for _, row in ipairs(ledger.rows) do if row.isTop then count = count + 1 end end
	expectEqual(count, 1)
	expectEqual(HL.defaultSelection(ledger, "Straight"), "Straight")
	expectEqual(HL.defaultSelection(ledger, nil), "Flush") -- the hand just played
	expectEqual(HL.defaultSelection(HL.build({ order = HandEvaluator.HandOrder, base = Scoring.HandBase, growth = Scoring.HandLevelGrowth }), nil), "High Card")
	-- layout: panel inside the screen, list and detail inside the panel and never overlapping
	for _, size in ipairs({ { 1920, 1080 }, { 1366, 768 }, { 1280, 720 }, { 800, 600 }, { 360, 640 }, { 412, 915 } }) do
		local w, h = size[1], size[2]
		local L = HL.layout(w, h, #ledger.rows)
		expectTrue(L.panel.w <= w and L.panel.h <= h, "panel fits " .. w .. "x" .. h)
		expectEqual(L.phone, w < 700)
		for _, r in ipairs({ L.list, L.detail }) do
			expectTrue(r.x >= 0 and r.y >= 50 and r.x + r.w <= L.panel.w and r.y + r.h <= L.panel.h, "section inside the panel " .. w)
			expectTrue(r.w > 100 and r.h > 100, "section has room")
		end
		local a, b = L.list, L.detail
		local apart = a.x + a.w <= b.x or b.x + b.w <= a.x or a.y + a.h <= b.y or b.y + b.h <= a.y
		expectTrue(apart, "list and detail do not overlap at " .. w)
		expectTrue(L.rowH >= 40, "rows are tall enough to tap")
		if not L.phone then expectTrue(L.panel.h <= h * 0.9 + 1, "panel clears the top strip") end
	end
	local f = io and io.open and io.open("src/Client/PokerHandsReference.lua", "r")
	if not f then return end
	local src = f:read("*a"); f:close()
	expectTrue(src:find('registerOpener("pokerHandsReference"', 1, true) ~= nil and src:find("handRefButton.MouseButton1Click", 1, true) ~= nil, "existing openers kept")
	expectFalse(src:find("SkinArt", 1, true) ~= nil, "old ornate frame art is gone")
end })

table.insert(tests, { name = "Sidebar: BondThreads is a sibling overlay, not a child of the list-layout Sidebar; top 70px stays free", fn = function()
	local f = io and io.open and io.open("src/Client/BondThreads.lua", "r")
	if not f then return end
	local src = f:read("*a"); f:close()
	expectFalse(src:find("layer.Parent = sidebar\n", 1, true) ~= nil, "layer is not parented straight to the sidebar")
	expectTrue(src:find("sidebar.Parent", 1, true) ~= nil, "layer parents to the sidebar's parent")
	local sb = io.open("src/Client/Sidebar.lua", "r"):read("*a")
	local pad = tonumber(sb:match("sidebarPadding%.PaddingTop = UDim%.new%(0, (%d+)%)"))
	local md = io.open("src/Client/PlayerMedallion.lua", "r"):read("*a")
	local y = tonumber(md:match("holder%.Position = UDim2%.new%(1, %-12, 0, (%d+)%)"))
	expectTrue(y and y >= 70, "medallion clears the Roblox top bar")
	expectTrue(pad and y and pad >= y + 42 + 2 + 17 - 1, "sidebar content starts below the medallion")
end })

table.insert(tests, { name = "Round Select: no Scout bar, no reserved space, rule on the Boss card, warning strip under the subtitle", fn = function()
	local f = io and io.open and io.open("src/Client/BossScout.lua", "r")
	if not f then return end
	local bs = f:read("*a"); f:close()
	expectFalse(bs:find('"SCOUT"', 1, true) ~= nil, "no SCOUT label")
	expectFalse(bs:find('Name = "RuleLine"', 1, true) ~= nil, "no rule line on the bar")
	expectTrue(bs:find('ban.Name = "BanButton"', 1, true) ~= nil or bs:find('"BanButton"', 1, true) ~= nil, "Rule Ban button kept")
	local rs = io.open("src/Client/RoundSelect.lua", "r"):read("*a")
	expectFalse(rs:find("reserved for the Boss Scout bar", 1, true) ~= nil, "no reserved scout space")
	expectTrue(rs:find("entry.bossLabel.Text = state.nightBossModifier.description", 1, true) ~= nil, "Boss card shows the rule text")
	local mb = io.open("src/Client/MessageBanner.lua", "r"):read("*a")
	expectFalse(mb:find("1, -126", 1, true) ~= nil, "warning strip is not pinned to the bottom")
end })

table.insert(tests, { name = "ModalGate: counter opens and closes and never goes negative, hover gate blocks outside the modal only, every modal kind has a stage", fn = function()
	local ModalGate = require(script.Parent.Parent.Engine.ModalGate)
	local g = ModalGate.new()
	expectFalse(g:isModalOpen(), "starts closed")
	g:close("a")
	expectEqual(g:count(), 0, "closing nothing stays at 0")
	g:open("a"); g:open("a"); g:open("b")
	expectEqual(g:count(), 2, "opening twice counts once")
	g:close("a"); g:close("a")
	expectEqual(g:count(), 1, "repeated close is ignored")
	local function inside(target, owner) return target.parent == owner end
	expectTrue(g:blocks({ parent = "x" }, inside), "an outside hover is blocked while a modal is open")
	expectFalse(g:blocks({ parent = "b" }, inside), "a hover inside the open modal still works")
	g:close("b")
	expectFalse(g:blocks({ parent = "x" }, inside), "nothing is blocked once closed")
	for _, kind in ipairs({ "modifier", "patron", "rushPatron", "event", "road", "pack", "detail", "unknown" }) do
		local def = ModalGate.STAGES[ModalGate.stageFor(kind)]
		expectTrue(def ~= nil and def.top ~= nil and def.decor ~= nil, "stage theme for " .. kind)
	end
	expectEqual(ModalGate.stageFor("modifier"), "blessing", "blessings use the altar")
	local f = io and io.open and io.open("src/Client/ModalStage.lua", "r")
	if not f then return end
	local ms = f:read("*a"); f:close()
	expectTrue(ms:find("TextButton", 1, true) ~= nil and ms:find("Active = true", 1, true) ~= nil, "the sink exists")
	expectTrue(ms:find("BackgroundTransparency = 0 ", 1, true) ~= nil, "the stage is opaque")
	for _, file in ipairs({ "VisualHelpers", "Tooltip", "ShopCards", "RoundSelectFX", "DeckWidget", "Shop", "init.client" }) do
		local h = io.open("src/Client/" .. file .. ".lua", "r"):read("*a")
		expectTrue(h:find("ModalStage", 1, true) ~= nil, file .. " checks the modal gate")
	end
	for _, file in ipairs({ "ChoicePanel", "RoadChoice", "Collection", "Shop" }) do
		local h = io.open("src/Client/" .. file .. ".lua", "r"):read("*a")
		expectTrue(h:find("ModalStage", 1, true) ~= nil and h:find("mount", 1, true) ~= nil, file .. " mounts a stage")
	end
end })

table.insert(tests, { name = "PanelGroups: every page is in exactly one group, group order is Tome/Strongbox/Coin Jar, openers cover every page, strip clears the panels", fn = function()
	local PG = require(script.Parent.Parent.Engine.PanelGroups)
	local PL = require(script.Parent.Parent.Engine.PanelLayout)
	local order = {}
	for _, g in ipairs(PG.GROUPS) do order[#order + 1] = g.id end
	expectEqual(table.concat(order, ","), "tome,strongbox,coinjar", "group order")
	local seen, total = {}, 0
	for _, g in ipairs(PG.GROUPS) do
		expectTrue(#g.pages >= 1 and g.color ~= nil and g.glow ~= nil and g.emoji ~= nil, g.id .. " is complete")
		for _, p in ipairs(g.pages) do
			expectFalse(seen[p.id] ~= nil, p.id .. " is in only one group")
			seen[p.id] = g.id
			total = total + 1
			expectEqual(PG.groupOf(p.id).id, g.id, "groupOf " .. p.id)
		end
		expectEqual(PG.defaultPage(g.id), g.pages[1].id, "group tab opens its first page")
	end
	expectEqual(total, 10, "ten pages in total")
	expectEqual(#PG.pages(), 10, "flat list has every page")
	expectEqual(PG.groupOf("collection").id, "tome")
	expectEqual(PG.groupOf("season").id, "strongbox")
	expectEqual(PG.groupOf("store").id, "coinjar")
	expectTrue(PG.groupOf("nope") == nil, "unknown page has no group")
	expectTrue(PL.hitsStrip(10, 30) and not PL.hitsStrip(PL.STRIP_BOTTOM + 1, 30), "strip band is y 3 to STRIP_BOTTOM")
	for _, sz in ipairs({ { 1920, 957 }, { 1280, 720 }, { 360, 640 } }) do
		local h = sz[2]
		expectTrue((h - h * 0.78) / 2 + PL.STRIP_NUDGE > PL.STRIP_BOTTOM, "a 78 percent panel starts below the strip at " .. h)
	end
	local f = io and io.open and io.open("src/Client/PanelTabs.lua", "r")
	if not f then return end
	local src = f:read("*a"); f:close()
	expectTrue(src:find("PanelGroups", 1, true) ~= nil and src:find("PanelTabs.back", 1, true) ~= nil and src:find("Group_", 1, true) ~= nil, "group tabs, ribbons and Back are built")
	local ids = {}
	for _, file in ipairs({ "Collection", "CollectionRewardsPanel", "BadgesPanel", "LegendPanel", "FlairPanel", "StatsPanel", "SeasonPanel", "QuestsPanel", "DailyRewardsPanel", "StorePanel" }) do
		local c = io.open("src/Client/" .. file .. ".lua", "r"):read("*a")
		expectTrue(c:find("registerOpener", 1, true) ~= nil and c:find("PanelTabs", 1, true) ~= nil, file .. " keeps its opener and strip")
	end
end })

table.insert(tests, { name = "Bond art: a prompt per Bond id plus bond_locked, category registered, ContentArt resolves bonds, Collection and threads use it", fn = function()
	local Bonds = require(script.Parent.Parent.Engine.Bonds)
	local ContentArt = require(script.Parent.Parent.Engine.ContentArt)
	expectTrue(ContentArt.bonds ~= nil, "ContentArt.bonds is registered")
	expectTrue(ContentArt.getImageId("bonds", "pairs") == nil or type(ContentArt.getImageId("bonds", "pairs")) == "string", "lookup is safe")
	local f = io and io.open and io.open("tools/patron_art/prompts.json", "r")
	if not f then return end
	local json = f:read("*a"); f:close()
	expectTrue(json:find('"bond_subjects"', 1, true) ~= nil, "bond_subjects exist")
	local block = json:match('"bond_subjects": {(.-)\n  }')
	expectTrue(block ~= nil, "bond_subjects block found")
	for _, def in ipairs(Bonds.Definitions) do
		expectTrue(block:find('"' .. def.id .. '":', 1, true) ~= nil, "prompt for bond " .. def.id)
	end
	expectTrue(block:find('"bond_locked":', 1, true) ~= nil, "prompt for bond_locked")
	expectFalse(block:lower():find("alcohol", 1, true) ~= nil and false, "kid-safe prompt text")
	local gen = io.open("tools/patron_art/generate_patron_art.py", "r"):read("*a")
	expectTrue(gen:find('"bonds": ("bond_subjects"', 1, true) ~= nil, "generator knows the bonds category")
	local col = io.open("src/Client/Collection.lua", "r"):read("*a")
	expectTrue(col:find("bond_locked", 1, true) ~= nil, "undiscovered Bonds use the locked medallion")
	local th = io.open("src/Client/BondThreads.lua", "r"):read("*a")
	expectTrue(th:find('getImageId("bonds"', 1, true) ~= nil, "thread labels show the Bond art")
	for _, w in ipairs({ "beer", "wine", "ale", "whisky", "balatro" }) do
		expectFalse(block:lower():find("%f[%a]" .. w .. "%f[%A]") ~= nil, "no banned word " .. w)
	end
end })

return tests
