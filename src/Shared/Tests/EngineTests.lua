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
		expectTrue(kind == "default" or kind == "tips" or kind == "journey" or kind == "achievement" or kind == "gamepass", set.id .. " unlock kind")
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
	expectFalse(code:match("[^ABCDEFGHJKMNPQRSTUVWXYZ23456789]") ~= nil)
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
	expectEqual(RunState.targetScoreFor(8, 3, 3), math.floor(65 * 2.26 ^ 7 * 2.5))
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

table.insert(tests, { name = "The continue Developer Product is a placeholder until it's created", fn = function()
	local product = DeveloperProducts.getById("continue")
	expectTrue(product ~= nil)
	expectEqual(product.name, "One More Round")
	-- Configured next to the Game Passes, not inside the pass list.
	expectTrue(DeveloperProducts.Definitions == GamePasses.DeveloperProducts)
	expectEqual(GamePasses.getById("continue"), nil)
	expectEqual(product.productId, 0)
	expectFalse(DeveloperProducts.isConfigured(product))
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
	profile.stats.runsStarted = 1
	profile.stats.runsWon = 20
	profile.stats.bestNightReached = 9
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
		expectTrue(none == nil and alone <= player, "normal rounds show a smaller player only")
	end
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

return tests
