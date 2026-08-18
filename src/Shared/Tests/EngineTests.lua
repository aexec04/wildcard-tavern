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
local RunState = require(script.Parent.Parent.Engine.RunState)
local TestRunner = require(script.Parent.TestRunner)

local expectEqual = TestRunner.expectEqual
local expectTrue = TestRunner.expectTrue
local expectFalse = TestRunner.expectFalse

local function C(rank, suit)
	return Card.new(rank, suit)
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

return tests
