--[[
	HandEvaluator.lua
	Figures out which poker hand a set of 1-5 played cards makes, and which
	of those cards actually "score" (contribute chip value). Pure Lua logic,
	no Roblox APIs -- fully unit-testable outside Studio.

	Hand names here are the generic, public-domain poker hand names
	(Pair, Flush, Full House, etc.) -- these are standard card-game
	terminology, not specific to any one game.
]]

local Card = require(script.Parent.Card)

local HandEvaluator = {}

-- Ordered weakest -> strongest. Used for shop/UI display and comparisons.
HandEvaluator.HandOrder = {
	"High Card",
	"Pair",
	"Two Pair",
	"Three of a Kind",
	"Straight",
	"Flush",
	"Full House",
	"Four of a Kind",
	"Straight Flush",
}

-- Example 5-card (or fewer) hands for the Poker Hands reference, as
-- { rank, suit } pairs. Display data only: a test checks that each one
-- really evaluates to its own hand name.
HandEvaluator.Examples = {
	["High Card"]       = { {14, "Spades"}, {10, "Hearts"}, {8, "Clubs"}, {5, "Diamonds"}, {3, "Spades"} },
	["Pair"]            = { {9, "Hearts"}, {9, "Clubs"}, {13, "Spades"}, {6, "Diamonds"}, {3, "Hearts"} },
	["Two Pair"]        = { {11, "Hearts"}, {11, "Spades"}, {6, "Clubs"}, {6, "Diamonds"}, {2, "Hearts"} },
	["Three of a Kind"] = { {8, "Hearts"}, {8, "Clubs"}, {8, "Spades"}, {13, "Diamonds"}, {4, "Hearts"} },
	["Straight"]        = { {5, "Hearts"}, {6, "Clubs"}, {7, "Spades"}, {8, "Diamonds"}, {9, "Hearts"} },
	["Flush"]           = { {14, "Hearts"}, {11, "Hearts"}, {8, "Hearts"}, {6, "Hearts"}, {3, "Hearts"} },
	["Full House"]      = { {10, "Hearts"}, {10, "Clubs"}, {10, "Spades"}, {4, "Diamonds"}, {4, "Hearts"} },
	["Four of a Kind"]  = { {12, "Hearts"}, {12, "Clubs"}, {12, "Spades"}, {12, "Diamonds"}, {7, "Hearts"} },
	["Straight Flush"]  = { {6, "Spades"}, {7, "Spades"}, {8, "Spades"}, {9, "Spades"}, {10, "Spades"} },
}

local function countBy(cards, key)
	local counts = {}
	for _, card in ipairs(cards) do
		local k = card[key]
		counts[k] = (counts[k] or 0) + 1
	end
	return counts
end

local function cardsWithRank(cards, rank)
	local out = {}
	for _, card in ipairs(cards) do
		if card.rank == rank then
			table.insert(out, card)
		end
	end
	return out
end

local function ranksSortedByCountThenValue(rankCounts)
	local ranks = {}
	for rank in pairs(rankCounts) do
		table.insert(ranks, rank)
	end
	table.sort(ranks, function(a, b)
		if rankCounts[a] ~= rankCounts[b] then
			return rankCounts[a] > rankCounts[b]
		end
		return a > b
	end)
	return ranks
end

-- A card with House Blend (wildSuit) Garnish counts toward EVERY suit for
-- flush purposes (see Card.hasSuit) -- so instead of counting each card's
-- own .suit directly, count how many cards qualify as each real suit and
-- look for any suit that reaches 5. This lets e.g. 4 Hearts + 1 House
-- Blend card complete a Flush, matching how House Blend already works for
-- suit-based Patron bonuses and Boss Round suit debuffs.
local function isFlush(cards)
	if #cards ~= 5 then
		return false
	end
	for _, suit in ipairs(Card.Suits) do
		local count = 0
		for _, card in ipairs(cards) do
			if Card.hasSuit(card, suit) then
				count = count + 1
			end
		end
		if count == 5 then
			return true
		end
	end
	return false
end

local function isStraight(cards)
	if #cards ~= 5 then
		return false
	end
	local ranks = {}
	local seen = {}
	for _, card in ipairs(cards) do
		if seen[card.rank] then
			return false -- duplicate rank, can't be a straight
		end
		seen[card.rank] = true
		table.insert(ranks, card.rank)
	end
	table.sort(ranks)

	-- Normal run of 5 consecutive ranks.
	local consecutive = true
	for i = 2, #ranks do
		if ranks[i] ~= ranks[i - 1] + 1 then
			consecutive = false
			break
		end
	end
	if consecutive then
		return true
	end

	-- Ace-low straight: A,2,3,4,5 (Ace stored as 14 -> treat as 1).
	if ranks[#ranks] == 14 then
		local lowRanks = { 1 }
		for i = 1, #ranks - 1 do
			table.insert(lowRanks, ranks[i])
		end
		table.sort(lowRanks)
		local lowConsecutive = true
		for i = 2, #lowRanks do
			if lowRanks[i] ~= lowRanks[i - 1] + 1 then
				lowConsecutive = false
				break
			end
		end
		return lowConsecutive
	end

	return false
end

local function highestCard(cards)
	local best = cards[1]
	for _, card in ipairs(cards) do
		if card.rank > best.rank then
			best = card
		end
	end
	return best
end

--[[
	Evaluate a played set of 1-5 cards.
	Returns { name = string, scoringCards = {Card, ...} }
]]
function HandEvaluator.evaluate(cards)
	assert(type(cards) == "table" and #cards >= 1 and #cards <= 5, "Play between 1 and 5 cards")

	local rankCounts = countBy(cards, "rank")
	local sortedRanks = ranksSortedByCountThenValue(rankCounts)
	local flush = isFlush(cards)
	local straight = isStraight(cards)

	if straight and flush then
		return { name = "Straight Flush", scoringCards = cards }
	end

	-- Four OR MORE of a rank. A deck can hold five cards of one rank (Standard Packs add cards, Recipes change ranks),
	-- and "== 4" let five Nines fall all the way through to High Card. There is no Five of a Kind hand yet, so five of
	-- a rank is Four of a Kind and every card of that rank scores.
	if rankCounts[sortedRanks[1]] >= 4 then
		return { name = "Four of a Kind", scoringCards = cardsWithRank(cards, sortedRanks[1]) }
	end

	if rankCounts[sortedRanks[1]] == 3 and sortedRanks[2] and rankCounts[sortedRanks[2]] >= 2 then
		return { name = "Full House", scoringCards = cards }
	end

	if flush then
		return { name = "Flush", scoringCards = cards }
	end

	if straight then
		return { name = "Straight", scoringCards = cards }
	end

	if rankCounts[sortedRanks[1]] == 3 then
		return { name = "Three of a Kind", scoringCards = cardsWithRank(cards, sortedRanks[1]) }
	end

	if rankCounts[sortedRanks[1]] == 2 and sortedRanks[2] and rankCounts[sortedRanks[2]] == 2 then
		local scoring = {}
		for _, c in ipairs(cardsWithRank(cards, sortedRanks[1])) do table.insert(scoring, c) end
		for _, c in ipairs(cardsWithRank(cards, sortedRanks[2])) do table.insert(scoring, c) end
		return { name = "Two Pair", scoringCards = scoring }
	end

	if rankCounts[sortedRanks[1]] == 2 then
		return { name = "Pair", scoringCards = cardsWithRank(cards, sortedRanks[1]) }
	end

	return { name = "High Card", scoringCards = { highestCard(cards) } }
end

return HandEvaluator
