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
	-- identity rng => BossRounds.pick always selects the last Definitions
	-- entry, which is Dry Spell (handSizeDelta = -1, discardsDelta = -1).
	local state = RunState.new(nil, function(n) return n end)
	state.round = state.config.roundsPerNight
	RunState.startRound(state)
	expectEqual(state.bossModifier.id, "dry_spell")
	expectEqual(#state.hand, state.config.handSize - 1)
	expectEqual(state.discardsRemaining, state.config.discardsPerRound - 1)
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

return tests
