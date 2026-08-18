--[[
	Card.lua
	Pure data + helper functions for a single playing card.
	No Roblox APIs used here on purpose -- this module can be required
	and tested from plain Lua (outside Roblox) or from inside Studio.
]]

local Card = {}

Card.Suits = { "Hearts", "Diamonds", "Clubs", "Spades" }

-- Rank is stored as a number 2-14 (11=Jack, 12=Queen, 13=King, 14=Ace)
Card.RankNames = {
	[2] = "2", [3] = "3", [4] = "4", [5] = "5", [6] = "6", [7] = "7",
	[8] = "8", [9] = "9", [10] = "10",
	[11] = "Jack", [12] = "Queen", [13] = "King", [14] = "Ace",
}

-- Chip value each rank contributes to a scored hand.
-- (Original numbers -- not copied from any other game's balance table.)
Card.RankChipValue = {
	[2] = 2, [3] = 3, [4] = 4, [5] = 5, [6] = 6, [7] = 7, [8] = 8, [9] = 9, [10] = 10,
	[11] = 10, [12] = 10, [13] = 10, [14] = 11,
}

function Card.new(rank, suit)
	assert(type(rank) == "number" and rank >= 2 and rank <= 14, "Card rank must be 2-14")
	assert(table.find(Card.Suits, suit) ~= nil, "Card suit must be one of Card.Suits")
	return { rank = rank, suit = suit }
end

function Card.chipValue(card)
	return Card.RankChipValue[card.rank]
end

function Card.toString(card)
	return Card.RankNames[card.rank] .. " of " .. card.suit
end

return Card
