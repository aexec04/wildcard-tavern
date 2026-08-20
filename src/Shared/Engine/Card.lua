--[[
	Card.lua
	Pure data + helper functions for a single playing card.
	No Roblox APIs used here on purpose -- this module can be required
	and tested from plain Lua (outside Roblox) or from inside Studio.

	FEATURE EXPANSION (see the "Feature Expansion Plan" project doc for the
	full naming/design writeup): a card can now optionally carry one
	Garnish (enhancement), one Special (edition), and one Stamp (seal) --
	same "up to 1 of each, they stack" shape as the reference this was
	modeled after, renamed to fit our tavern theme and kept kid-friendly
	(no real alcohol references -- "garnish" here means things like sugar,
	spice, or a candy-glass decoration, same as any all-ages diner/cafe).

	These are pure data tags read by Scoring.lua -- Card.lua itself never
	touches score math, it just describes what a card IS.
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

-- ===== Garnishes (our Enhancement equivalent) =====
-- A permanent property baked onto ONE physical card. Applied by House
-- Recipes (see Recipes.lua). At most one Garnish per card.
Card.Garnishes = {
	sweet = {
		name = "Sweet Garnish", icon = "🍬",
		description = "+30 Chips when this card scores.",
		chips = 30,
	},
	zesty = {
		name = "Zesty Garnish", icon = "🌶️",
		description = "+4 Mult when this card scores.",
		mult = 4,
	},
	houseBlend = {
		name = "House Blend", icon = "🍹",
		description = "Counts as every suit at once (for suit-based bonuses and penalties).",
		wildSuit = true,
	},
	brittle = {
		name = "Brittle Garnish", icon = "🍭",
		description = "x2 Mult when this card scores. Made of spun sugar -- 1 in 4 chance it shatters and leaves your deck for good after scoring.",
		xmult = 2,
		breakOneInN = 4,
	},
	iron = {
		name = "Iron Garnish", icon = "🍳",
		description = "x1.5 Mult for each of these held in your hand (not played).",
		heldXMult = 1.5,
	},
	barToken = {
		name = "Bar Token", icon = "🪙",
		description = "+50 Chips. A wooden token, not a real card -- no rank or suit, fits any hand.",
		chips = 50,
		blank = true,
	},
	golden = {
		name = "Golden Garnish", icon = "🌟",
		description = "Earn 3 Tips if this card is held in your hand at the end of the round.",
		heldEndOfRoundTips = 3,
	},
	lucky = {
		name = "Lucky Garnish", icon = "🍀",
		description = "When scored: 1 in 5 chance for +20 Mult, and separately 1 in 15 chance to earn 20 Tips.",
		luckyMultOneInN = 5, luckyMult = 20,
		luckyTipsOneInN = 15, luckyTips = 20,
	},
}

-- ===== Specials (our Edition equivalent) =====
-- A rarer finish that can be applied to either a playing card OR a Patron
-- (Reserved Special only makes sense on a Patron). Stacks with a Garnish.
Card.Specials = {
	silver = { name = "Silver Special", icon = "⚪", description = "+50 Chips.", chips = 50 },
	gold = { name = "Gold Special", icon = "🟡", description = "+10 Mult.", mult = 10 },
	rainbow = { name = "Rainbow Special", icon = "🌈", description = "x1.5 Mult.", xmult = 1.5 },
	-- Patron-only: opens an extra seat at the table (+1 Patron slot).
	reserved = { name = "Reserved Special", icon = "🎫", description = "+1 Patron slot.", patronSlotDelta = 1 },
}

-- ===== Stamps (our Seal equivalent) =====
-- A loyalty-card-style stamp on a card, granted by certain House Recipes.
Card.Stamps = {
	gold = { name = "Gold Stamp", icon = "🟨", description = "Earn 3 Tips when this card scores.", scoreTips = 3 },
	encore = { name = "Encore Stamp", icon = "🔁", description = "Retriggers this card's own Garnish/Special/Stamp effects one extra time.", retrigger = true },
	blue = {
		name = "Blue Stamp", icon = "🟦",
		description = "If held in hand at the end of the round, creates a Menu Recipe for the last hand you played.",
		createsMenuRecipeIfHeld = true,
	},
	purple = {
		name = "Purple Stamp", icon = "🟪",
		description = "Creates a random House Recipe when this card is discarded.",
		createsHouseRecipeOnDiscard = true,
	},
}

function Card.new(rank, suit, opts)
	assert(type(rank) == "number" and rank >= 2 and rank <= 14, "Card rank must be 2-14")
	assert(table.find(Card.Suits, suit) ~= nil, "Card suit must be one of Card.Suits")
	opts = opts or {}
	return {
		rank = rank,
		suit = suit,
		garnish = opts.garnish, -- id into Card.Garnishes, or nil
		special = opts.special, -- id into Card.Specials, or nil
		stamp = opts.stamp,     -- id into Card.Stamps, or nil
	}
end

function Card.chipValue(card)
	return Card.RankChipValue[card.rank]
end

function Card.toString(card)
	return Card.RankNames[card.rank] .. " of " .. card.suit
end

function Card.isFaceCard(card)
	return card.rank >= 11 and card.rank <= 13 -- Jack, Queen, King (not Ace)
end

-- True if this card should be treated as belonging to `suit` for
-- suit-based bonuses/penalties (House Blend counts as every suit).
function Card.hasSuit(card, suit)
	local garnish = card.garnish and Card.Garnishes[card.garnish]
	if garnish and garnish.wildSuit then
		return true
	end
	return card.suit == suit
end

return Card
