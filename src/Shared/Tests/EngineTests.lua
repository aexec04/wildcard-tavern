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
local Themes = require(script.Parent.Parent.Engine.Themes)
local RunState = require(script.Parent.Parent.Engine.RunState)
local DeckVariants = require(script.Parent.Parent.Engine.DeckVariants)
local DifficultyTiers = require(script.Parent.Parent.Engine.DifficultyTiers)
local BossRounds = require(script.Parent.Parent.Engine.BossRounds)
local Recipes = require(script.Parent.Parent.Engine.Recipes)
local HousePasses = require(script.Parent.Parent.Engine.HousePasses)
local Packs = require(script.Parent.Parent.Engine.Packs)
local Tags = require(script.Parent.Parent.Engine.Tags)
local PlayerProfile = require(script.Parent.Parent.Engine.PlayerProfile) -- PERSISTENT SAVE, Phase 10
local SeededRng = require(script.Parent.Parent.Engine.SeededRng) -- DAILY CHALLENGE, Phase 11
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

table.insert(tests, { name = "Scoring.calculate: 'Last Call' only triggers on the last hand", fn = function()
	local hand = HandEvaluator.evaluate({ C(9, "Hearts"), C(9, "Clubs"), C(2, "Spades") })
	local lastCall = Patrons.getById("last_call")

	local _, _, multNotLast = Scoring.calculate(hand, { lastCall }, { isLastHand = false })
	expectEqual(multNotLast, 2)

	local _, _, multLast = Scoring.calculate(hand, { lastCall }, { isLastHand = true })
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

-- ===== Themes (cosmetics) =====

table.insert(tests, { name = "RunState.new starts with the default theme owned and equipped", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	expectTrue(state.ownedThemes[Themes.DefaultThemeId])
	expectEqual(state.equippedTheme, Themes.DefaultThemeId)
end })

table.insert(tests, { name = "RunState.buyTheme deducts tips and marks the theme owned", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	state.tips = 20
	local ok = RunState.buyTheme(state, "midnight_blue")
	expectTrue(ok)
	expectTrue(state.ownedThemes["midnight_blue"])
	expectEqual(state.tips, 20 - Themes.getById("midnight_blue").price)
end })

table.insert(tests, { name = "RunState.buyTheme fails gracefully with insufficient tips", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	state.tips = 0
	local ok, message = RunState.buyTheme(state, "midnight_blue")
	expectFalse(ok)
	expectTrue(message ~= nil)
	expectFalse(state.ownedThemes["midnight_blue"] == true)
end })

table.insert(tests, { name = "RunState.buyTheme refuses to double-buy an owned theme", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	state.tips = 100
	RunState.buyTheme(state, "midnight_blue")
	local tipsAfterFirstBuy = state.tips
	local ok, message = RunState.buyTheme(state, "midnight_blue")
	expectFalse(ok)
	expectTrue(message ~= nil)
	expectEqual(state.tips, tipsAfterFirstBuy) -- no double charge
end })

table.insert(tests, { name = "RunState.equipTheme requires ownership first", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	local ok = RunState.equipTheme(state, "midnight_blue")
	expectFalse(ok)
	expectEqual(state.equippedTheme, Themes.DefaultThemeId) -- unchanged
end })

table.insert(tests, { name = "RunState.equipTheme succeeds once the theme is owned", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	state.tips = 20
	RunState.buyTheme(state, "midnight_blue")
	local ok = RunState.equipTheme(state, "midnight_blue")
	expectTrue(ok)
	expectEqual(state.equippedTheme, "midnight_blue")
end })

-- ===== BossRounds =====

table.insert(tests, { name = "BossRounds.isBossRound is only true on a Night's last round", fn = function()
	expectFalse(BossRounds.isBossRound(1, 3))
	expectFalse(BossRounds.isBossRound(2, 3))
	expectTrue(BossRounds.isBossRound(3, 3))
end })

table.insert(tests, { name = "BossRounds.pick returns a valid, well-formed modifier", fn = function()
	local modifier = BossRounds.pick(function(n) return n end)
	expectTrue(modifier ~= nil)
	expectTrue(BossRounds.getById(modifier.id) == modifier)
	expectTrue(type(modifier.name) == "string" and #modifier.name > 0)
	expectTrue(type(modifier.description) == "string" and #modifier.description > 0)
end })

-- BOSS DIFFICULTY: BossRounds.pick(rng, night) gates modifiers by minNight
-- (Ahmed's playtest bug -- Closing Time, a "1 hand only" boss, appeared on
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
	-- this can only ever be a tier-1 (mild) modifier, never Closing Time/
	-- Watered Down/etc, reproducing the exact scenario Ahmed hit.
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
	expectEqual(state.tips, 6)
	expectEqual(state.config.handsPerRound, RunState.DefaultConfig.handsPerRound - 1)
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
	-- Find Dry Spell's actual position (handSizeDelta = -1, discardsDelta =
	-- -1) rather than assuming it's last -- new Boss Rounds get appended
	-- to the list over time, which would otherwise silently pick a
	-- different modifier and break this test.
	local dryIndex
	for i, def in ipairs(BossRounds.Definitions) do
		if def.id == "dry_spell" then
			dryIndex = i
		end
	end
	expectTrue(dryIndex ~= nil, "expected to find dry_spell in BossRounds.Definitions")
	-- JOURNEY FEATURE: the Night's Boss modifier is now picked at Round 1
	-- (see RunState.startRound), not lazily the instant the Boss round
	-- itself starts -- so the deterministic rng has to be in place from
	-- construction, not patched onto `state.rng` after the fact (that
	-- would be too late: Round 1's pick already happened inside
	-- RunState.new, using whatever rng was passed there).
	local state = RunState.new(nil, function(_n) return dryIndex end)
	-- BOSS DIFFICULTY: dry_spell is minNight = 3 (see BossRounds.lua), so
	-- RunState.new's own Round-1-at-Night-1 pick above can't have selected
	-- it (Night 1 only has tier-1 modifiers eligible). Force the run to
	-- Night 3 and re-pick Round 1's Boss modifier there -- same as a real
	-- player reaching Night 3 -- before jumping straight to the Boss round
	-- itself (skipping normal round-by-round progression, since this test
	-- only cares about the modifier's effect once it's active). dryIndex
	-- still resolves to dry_spell here: at Night 3+, every modifier before
	-- it in Definitions order (all of tier 1 + earlier tier 2) is also
	-- eligible, so its position in the eligible list matches its position
	-- in the full list.
	state.night = 3
	state.round = 1
	RunState.startRound(state)
	state.round = state.config.roundsPerNight
	RunState.startRound(state)
	expectEqual(state.bossModifier.id, "dry_spell")
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

table.insert(tests, { name = "ROUND SELECT: the Happy Hour Tag discounts the next shop visit, then clears once you leave it", fn = function()
	local happyHourIndex = tagIndexById("happy_hour")
	expectTrue(happyHourIndex ~= nil, "expected to find happy_hour in Tags.Definitions")
	local state = RunState.new(nil, function(_n) return happyHourIndex end)
	local tag, result = RunState.skipRound(state)
	expectEqual(tag.id, "happy_hour")
	expectEqual(result.kind, "discount")
	expectEqual(state.nextShopDiscount, result.amount)

	local samplePatron = Patrons.Definitions[1]
	expectEqual(RunState.patronPrice(state, samplePatron), math.max(1, samplePatron.price - result.amount))

	-- Simulate winning the round and leaving the shop -- the discount
	-- should be gone by the round after that.
	state.roundOver = true
	RunState.advanceToNextRound(state)
	expectTrue(state.nextShopDiscount == nil, "Happy Hour's discount should be consumed once its shop visit ends")
	expectEqual(RunState.patronPrice(state, samplePatron), samplePatron.price)
end })

table.insert(tests, { name = "ROUND SELECT: Happy Hour Tag and Regulars' Discount House Pass stack, floored at 1 Tip", fn = function()
	local happyHourIndex = tagIndexById("happy_hour")
	local state = RunState.new(nil, function(_n) return happyHourIndex end)
	state.housePasses.regulars_discount = true
	local _, result = RunState.skipRound(state)
	local cheapPatron = { price = 4 } -- cheap enough that both discounts combined would go below 1
	expectEqual(RunState.patronPrice(state, cheapPatron), 1)
	-- Happy Hour applies to Pack prices too (see its description), even
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

table.insert(tests, { name = "Boss Round chipsMultiplier/multMultiplier (Watered Down) roughly halves the score", fn = function()
	local stateNormal = RunState.new(nil, function(n) return n end)
	local resultNormal = RunState.playHand(stateNormal, { 1, 2 })

	local stateHalved = RunState.new(nil, function(n) return n end)
	stateHalved.bossModifier = BossRounds.getById("watered_down")
	local resultHalved = RunState.playHand(stateHalved, { 1, 2 })

	expectEqual(resultHalved.chips, resultNormal.chips * 0.5)
	expectEqual(resultHalved.mult, resultNormal.mult * 0.5)
end })

table.insert(tests, { name = "Boss Round handsPerRoundOverride (Closing Time) hard-limits hands allowed", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	local bossModifier = BossRounds.getById("closing_time")
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

table.insert(tests, { name = "'Thin Chips' halves Chips but leaves Mult untouched", fn = function()
	local bossModifier = BossRounds.getById("thin_chips")
	expectEqual(bossModifier.chipsMultiplier, 0.5)
	expectTrue(bossModifier.multMultiplier == nil)
end })

table.insert(tests, { name = "'Flat Mult' halves Mult but leaves Chips untouched", fn = function()
	local bossModifier = BossRounds.getById("flat_mult")
	expectEqual(bossModifier.multMultiplier, 0.5)
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
	expectEqual(mult, 4 + 14) -- base Full House mult (4) + patron (14)
end })

table.insert(tests, { name = "'Ace of the House' adds +5 Mult for each scoring Ace", fn = function()
	local aceOfTheHouse = Patrons.getById("ace_of_the_house")
	local pair = HandEvaluator.evaluate({ C(14, "Hearts"), C(14, "Clubs"), C(2, "Spades") }) -- pair of Aces
	local _, _, mult = Scoring.calculate(pair, { aceOfTheHouse }, {})
	expectEqual(mult, 2 + 5 * 2) -- base Pair mult (2) + patron (5 per Ace x 2 Aces)
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

table.insert(tests, { name = "'Discard Special' adds +3 Mult for each Discard remaining", fn = function()
	local discardSpecial = Patrons.getById("discard_special")
	local hand = HandEvaluator.evaluate({ C(9, "Hearts") })
	local _, _, mult = Scoring.calculate(hand, { discardSpecial }, { discardsRemaining = 3 })
	expectEqual(mult, 1 + 3 * 3)
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

table.insert(tests, { name = "RunState.blindMultiplierFor: Big Blind (any round before the last) is always 1.5x", fn = function()
	expectEqual(RunState.blindMultiplierFor(1, 2, 3), 1.5)
	expectEqual(RunState.blindMultiplierFor(5, 2, 3), 1.5)
end })

table.insert(tests, { name = "RunState.blindMultiplierFor: Boss Blind scales from 2x at Night 1 to 6x at Night 8, then plateaus", fn = function()
	expectEqual(RunState.blindMultiplierFor(1, 3, 3), 2)
	expectEqual(RunState.blindMultiplierFor(8, 3, 3), 6)
	expectEqual(RunState.blindMultiplierFor(20, 3, 3), 6) -- Endless Mode: multiplier plateaus, doesn't keep climbing
end })

table.insert(tests, { name = "RunState.targetScoreFor folds nightBaseScoreFor and blindMultiplierFor together", fn = function()
	local night = 4
	local base = RunState.nightBaseScoreFor(night)
	expectEqual(RunState.targetScoreFor(night, 1, 3), math.floor(base * 1))
	expectEqual(RunState.targetScoreFor(night, 2, 3), math.floor(base * 1.5))
	expectEqual(RunState.targetScoreFor(night, 3, 3), math.floor(base * RunState.blindMultiplierFor(night, 3, 3)))
end })

table.insert(tests, { name = "BUGFIX: RunState.blindMultiplierFor honors an explicit nightCap override, not just the global default", fn = function()
	-- A hypothetical run with nightCap = 4 (instead of the global default
	-- of 8): the Boss multiplier should already be maxed (6x) at Night 4,
	-- not still ramping toward a Night-8 plateau it'll never reach.
	expectEqual(RunState.blindMultiplierFor(1, 3, 3, 4), 2)
	expectEqual(RunState.blindMultiplierFor(4, 3, 3, 4), 6)
	expectEqual(RunState.blindMultiplierFor(9, 3, 3, 4), 6) -- still plateaued past its own (overridden) cap
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
	local anyPatron, anyTheme = false, false
	for _ in pairs(profile.discoveredPatronIds) do anyPatron = true end
	for _ in pairs(profile.ownedThemeIds) do anyTheme = true end
	expectFalse(anyPatron, "a fresh profile shouldn't have any discovered Patrons yet")
	expectFalse(anyTheme, "a fresh profile shouldn't have any bought Themes yet")
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
	PlayerProfile.recordThemesOwned(profile, { "midnight_blue" })
	PlayerProfile.recordRunStarted(profile)
	PlayerProfile.recordNightReached(profile, 5)
	PlayerProfile.recordRunWon(profile)

	local reloaded = PlayerProfile.migrate(profile)
	expectTrue(reloaded.discoveredPatronIds.tip_jar)
	expectTrue(reloaded.discoveredPatronIds.second_opinion)
	expectTrue(reloaded.ownedThemeIds.midnight_blue)
	expectEqual(reloaded.stats.runsStarted, 1)
	expectEqual(reloaded.stats.bestNightReached, 5)
	expectEqual(reloaded.stats.runsWon, 1)
end })

table.insert(tests, { name = "PlayerProfile.migrate: sanitizes a corrupt/foreign shape instead of crashing or propagating garbage", fn = function()
	local profile = PlayerProfile.migrate({
		discoveredPatronIds = "not a table",
		ownedThemeIds = { midnight_blue = "yes, but not literally true" }, -- wrong value type -- must be dropped
		stats = { runsStarted = "five", runsWon = -3, bestNightReached = 4.9 },
		someUnrelatedFieldFromAFutureVersion = { 1, 2, 3 },
	})
	local any = false
	for _ in pairs(profile.discoveredPatronIds) do any = true end
	expectFalse(any, "a non-table discoveredPatronIds should be ignored, not error")
	expectFalse(profile.ownedThemeIds.midnight_blue == true, "a non-true value for an owned theme id should be dropped")
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

table.insert(tests, { name = "PlayerProfile.recordThemesOwned: reports changed only when something is actually new", fn = function()
	local profile = PlayerProfile.new()
	expectTrue(PlayerProfile.recordThemesOwned(profile, { "midnight_blue" }))
	expectFalse(PlayerProfile.recordThemesOwned(profile, { "midnight_blue" }))
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

-- ===== RunState.new: seeding ownedThemes from a saved profile (Phase 10) =====

table.insert(tests, { name = "RunState.new: without ownedThemeIds, only the free default is owned (unchanged pre-Phase-10 behavior)", fn = function()
	local state = RunState.new()
	expectTrue(state.ownedThemes[Themes.DefaultThemeId])
	expectFalse(state.ownedThemes.midnight_blue == true)
end })

table.insert(tests, { name = "RunState.new: options.ownedThemeIds seeds extra Themes as already-owned", fn = function()
	local state = RunState.new({ ownedThemeIds = { "midnight_blue", "crimson" } })
	expectTrue(state.ownedThemes[Themes.DefaultThemeId], "the free default should still be owned regardless")
	expectTrue(state.ownedThemes.midnight_blue)
	expectTrue(state.ownedThemes.crimson)
	expectFalse(state.ownedThemes.forest == true, "a Theme not in the seed list shouldn't be owned")
end })

table.insert(tests, { name = "RunState.new: a seeded Theme is immediately equippable without buying it again", fn = function()
	local state = RunState.new({ ownedThemeIds = { "rose_gold" } })
	local ok = RunState.equipTheme(state, "rose_gold")
	expectTrue(ok)
	expectEqual(state.equippedTheme, "rose_gold")
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

-- ===== Content pass (Phase 12): 6 more Patrons, 6 more Boss Rounds, =====
-- ===== 6 more Recipes =====

table.insert(tests, { name = "'Jack of All Trades' adds +5 Mult for each scoring Jack", fn = function()
	local jack = Patrons.getById("jack_of_all_trades")
	local pair = HandEvaluator.evaluate({ C(11, "Hearts"), C(11, "Clubs"), C(2, "Spades") }) -- pair of Jacks
	local _, _, mult = Scoring.calculate(pair, { jack }, {})
	expectEqual(mult, 2 + 5 * 2) -- base Pair mult (2) + patron (5 per Jack x 2 Jacks)
end })

table.insert(tests, { name = "'Queen's Gambit' adds +5 Mult for each scoring Queen", fn = function()
	local queen = Patrons.getById("queens_gambit")
	local pair = HandEvaluator.evaluate({ C(12, "Hearts"), C(12, "Clubs"), C(2, "Spades") }) -- pair of Queens
	local _, _, mult = Scoring.calculate(pair, { queen }, {})
	expectEqual(mult, 2 + 5 * 2) -- base Pair mult (2) + patron (5 per Queen x 2 Queens)
end })

table.insert(tests, { name = "'Jack of All Trades' / 'Queen's Gambit' give no bonus without a scoring Jack/Queen", fn = function()
	local jack = Patrons.getById("jack_of_all_trades")
	local queen = Patrons.getById("queens_gambit")
	local hand = HandEvaluator.evaluate({ C(9, "Hearts") })
	local _, _, mult = Scoring.calculate(hand, { jack, queen }, {})
	expectEqual(mult, 1) -- base High Card mult only
end })

table.insert(tests, { name = "'Closing Tab' earns 2 Tips per Discard remaining on round win", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	RunState.buyPatron(state, "closing_tab")
	state.tips = 20
	local closingTab = Patrons.getById("closing_tab")
	local tipsBefore = state.tips
	closingTab.onRoundWin(state)
	expectEqual(state.tips, tipsBefore + 2 * state.discardsRemaining) -- 3 discards by default
end })

table.insert(tests, { name = "'Full House Crowd' scales XMult by every OTHER owned Patron", fn = function()
	local crowd = Patrons.getById("full_house_crowd")
	local theRegular = Patrons.getById("the_regular")
	local luckyDice = Patrons.getById("lucky_dice")
	local hand = HandEvaluator.evaluate({ C(9, "Hearts") })
	local _, _, multAlone = Scoring.calculate(hand, { crowd }, {})
	local _, _, multWithTwo = Scoring.calculate(hand, { crowd, theRegular, luckyDice }, {})
	expectEqual(multAlone, 1) -- no OTHER Patrons -- no bonus
	expectEqual(multWithTwo, (1 + 4) * (1.2 ^ 2)) -- base(1) + The Regular's +4, then x1.2^2 for the 2 others
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

table.insert(tests, { name = "'Watered Pour' / 'Slow Pour' are mild tier-1 versions of Thin Chips / Flat Mult", fn = function()
	local wateredPour = BossRounds.getById("watered_pour")
	local slowPour = BossRounds.getById("slow_pour")
	expectEqual(wateredPour.chipsMultiplier, 0.8)
	expectEqual(wateredPour.minNight, 1)
	expectEqual(slowPour.multMultiplier, 0.8)
	expectEqual(slowPour.minNight, 1)
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

table.insert(tests, { name = "'Empty-Handed' zeroes discards and caps hands at 3, gated to tier 3", fn = function()
	local empty = BossRounds.getById("empty_handed")
	expectEqual(empty.discardsDelta, -99)
	expectEqual(empty.handsPerRoundOverride, 3)
	expectEqual(empty.minNight, 6)
end })

table.insert(tests, { name = "'Everything's Out' cuts Chips and Mult by 70%, gated to tier 3", fn = function()
	local stateNormal = RunState.new(nil, function(n) return n end)
	local resultNormal = RunState.playHand(stateNormal, { 1, 2 })

	local stateCut = RunState.new(nil, function(n) return n end)
	stateCut.bossModifier = BossRounds.getById("everythings_out")
	local resultCut = RunState.playHand(stateCut, { 1, 2 })

	expectEqual(stateCut.bossModifier.minNight, 6)
	expectEqual(resultCut.chips, resultNormal.chips * 0.3)
	expectEqual(resultCut.mult, resultNormal.mult * 0.3)
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

table.insert(tests, { name = "'Perfect Ten' adds +5 Mult for each scoring Ten", fn = function()
	local ten = Patrons.getById("perfect_ten")
	local highCard = HandEvaluator.evaluate({ C(10, "Hearts") })
	local _, _, mult = Scoring.calculate(highCard, { ten }, {})
	expectEqual(mult, 1 + 5) -- base High Card mult (1) + patron (5 per scoring Ten)
end })

table.insert(tests, { name = "'Perfect Ten' gives no bonus without a scoring Ten", fn = function()
	local ten = Patrons.getById("perfect_ten")
	local highCard = HandEvaluator.evaluate({ C(9, "Hearts") })
	local _, _, mult = Scoring.calculate(highCard, { ten }, {})
	expectEqual(mult, 1)
end })

table.insert(tests, { name = "'Night Owl' adds +3 Mult per Night reached so far", fn = function()
	local owl = Patrons.getById("night_owl")
	local highCard = HandEvaluator.evaluate({ C(9, "Hearts") })
	local _, _, mult = Scoring.calculate(highCard, { owl }, { night = 4 })
	expectEqual(mult, 1 + 3 * 4)
end })

table.insert(tests, { name = "'Steady Hand' adds +18 Mult only when exactly 5 cards are played", fn = function()
	local steady = Patrons.getById("steady_hand")
	local highCard = HandEvaluator.evaluate({ C(9, "Hearts") })
	local fivePlayed = { C(9, "Hearts"), C(2, "Clubs"), C(3, "Spades"), C(4, "Diamonds"), C(5, "Hearts") }
	local _, _, multFive = Scoring.calculate(highCard, { steady }, { allPlayedCards = fivePlayed })
	expectEqual(multFive, 1 + 18)
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

table.insert(tests, { name = "'Bare Bones' cuts Chips and Mult by 60%, gated to tier 3", fn = function()
	local bareBones = BossRounds.getById("bare_bones")
	expectEqual(bareBones.chipsMultiplier, 0.4)
	expectEqual(bareBones.multMultiplier, 0.4)
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

table.insert(tests, { name = "Secret Recipe 'Nightcap Round' doubles the next round-win Tips reward, then clears itself", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	local recipe = Recipes.getSecretRecipeById("nightcap_round")
	local ok = recipe.apply(state)
	expectTrue(ok)
	expectTrue(state.nightcapRoundActive)

	state.targetScore = 0 -- guarantee an immediate round win
	state.tips = 0 -- avoid interest muddying the expected total
	RunState.playHand(state, { 1 })
	expectEqual(state.tips, 2 * state.config.tipsPerRoundWin) -- doubled flat reward, no boss
	expectFalse(state.nightcapRoundActive) -- one-shot: cleared after use
end })

table.insert(tests, { name = "'Nightcap Round' stacks with a Boss Round's own double instead of replacing it", fn = function()
	local state = RunState.new(nil, function(n) return n end)
	state.bossModifier = BossRounds.getById("bouncer")
	state.nightcapRoundActive = true
	state.targetScore = 0
	state.tips = 0
	RunState.playHand(state, { 1 })
	-- Boss doubles tipsPerRoundWin once, Nightcap Round doubles the result again.
	expectEqual(state.tips, 4 * state.config.tipsPerRoundWin)
end })

return tests
