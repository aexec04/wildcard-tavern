--[[
	Deck.lua
	Builds and shuffles a standard 52-card deck. Pure Lua, no Roblox APIs.
]]

local Card = require(script.Parent.Card)

local Deck = {}

-- Builds a fresh, ordered 52-card deck (no jokers/wildcards in the MVP).
function Deck.newStandardDeck()
	local deck = {}
	for _, suit in ipairs(Card.Suits) do
		for rank = 2, 14 do
			table.insert(deck, Card.new(rank, suit))
		end
	end
	return deck
end

-- Fisher-Yates shuffle. `rng` is optional (defaults to Lua's math.random)
-- so tests can pass a seeded/deterministic generator.
function Deck.shuffle(deck, rng)
	rng = rng or math.random
	for i = #deck, 2, -1 do
		local j = rng(i)
		deck[i], deck[j] = deck[j], deck[i]
	end
	return deck
end

-- Removes and returns `count` cards from the top of the deck.
function Deck.draw(deck, count)
	local drawn = {}
	for _ = 1, count do
		if #deck == 0 then
			break
		end
		table.insert(drawn, table.remove(deck))
	end
	return drawn
end

-- Rank display order, Ace-high down to 2 -- matches how the Deck Tracker
-- UI lists ranks left-to-right.
Deck.RankOrder = { 14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2 }

-- Counts how many of each (suit, rank) card are still left in `deck`.
-- Returns { [suit] = { [rank] = count, ... }, ... } with every suit/rank
-- combination present (defaulting to 0) so UI code never has to nil-check.
function Deck.remainingCounts(deck)
	local counts = {}
	for _, suit in ipairs(Card.Suits) do
		counts[suit] = {}
		for _, rank in ipairs(Deck.RankOrder) do
			counts[suit][rank] = 0
		end
	end
	for _, card in ipairs(deck) do
		counts[card.suit][card.rank] = counts[card.suit][card.rank] + 1
	end
	return counts
end

return Deck
