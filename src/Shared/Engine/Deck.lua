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

return Deck
