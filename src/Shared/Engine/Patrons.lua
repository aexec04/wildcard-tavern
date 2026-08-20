--[[
	Patrons.lua
	"Patrons" are our equivalent of a passive modifier card that sits in your
	party and boosts hands as you play them (own original names/effects --
	swap in your own art & flavor text freely).

	Each patron is data + a pure `effect(handResult, context)` function that
	returns an optional { chips = n, mult = n, multMultiplier = n, tips = n }
	bonus. Keeping effects as pure functions of (handResult, context) means
	they're trivially unit-testable in isolation. A patron can also define
	`onRoundWin(state)` for a once-per-round-won effect that isn't tied to
	any particular hand (e.g. flat Tip income) -- that one DOES touch state
	directly, called by RunState after a round is won.
]]

local Card = require(script.Parent.Card)

local Patrons = {}

-- context fields you can use in an effect function:
--   allPlayedCards   -- every card in the hand that was played (not just scoring ones)
--   heldCards        -- cards left in hand, NOT played, at the moment of scoring
--   handsRemaining   -- hands left to play this round, before this one
--   discardsRemaining
--   isLastHand       -- true if this is the last hand of the round
--   night, round     -- current progress
--   tips             -- Tips held before this hand's reward is added
--   ownedPatrons, patronIndex -- this patron's own list/position, for
--                                "copy a neighbor's ability" patrons

Patrons.Definitions = {
	{
		id = "the_regular",
		name = "The Regular",
		icon = "☕",
		description = "+4 Mult on every hand.",
		price = 4,
		effect = function(_handResult, _context)
			return { mult = 4 }
		end,
	},
	{
		id = "lucky_dice",
		name = "Lucky Dice",
		icon = "🎲",
		description = "+20 Chips if the hand contains a Pair (or better).",
		price = 5,
		effect = function(handResult, _context)
			local pairLike = {
				["Pair"] = true, ["Two Pair"] = true, ["Three of a Kind"] = true,
				["Full House"] = true, ["Four of a Kind"] = true,
			}
			if pairLike[handResult.name] then
				return { chips = 20 }
			end
			return nil
		end,
	},
	{
		id = "suit_yourself",
		name = "Suit Yourself",
		icon = "♥️",
		description = "+3 Mult for each Heart among the scoring cards.",
		price = 6,
		effect = function(handResult, _context)
			local hearts = 0
			for _, card in ipairs(handResult.scoringCards) do
				if Card.hasSuit(card, "Hearts") then
					hearts = hearts + 1
				end
			end
			if hearts > 0 then
				return { mult = 3 * hearts }
			end
			return nil
		end,
	},
	{
		id = "last_call",
		name = "Last Call",
		icon = "🌙",
		description = "Mult x1.5 when played as your last hand of the round.",
		price = 7,
		effect = function(_handResult, context)
			if context.isLastHand then
				return { multMultiplier = 1.5 }
			end
			return nil
		end,
	},
	{
		id = "the_bard",
		name = "The Bard",
		icon = "🎻",
		description = "+2 Mult for every card played (not just scoring cards).",
		price = 5,
		effect = function(_handResult, context)
			local played = context.allPlayedCards or {}
			if #played > 0 then
				return { mult = 2 * #played }
			end
			return nil
		end,
	},

	-- ===== +MULT: rewards a specific hand type =====
	{
		id = "regulars_round", name = "Regulars' Round", icon = "🤝", price = 5,
		description = "+8 Mult if the hand contains a Pair (or better).",
		effect = function(handResult, _context)
			local pairLike = {
				["Pair"] = true, ["Two Pair"] = true, ["Three of a Kind"] = true,
				["Full House"] = true, ["Four of a Kind"] = true,
			}
			if pairLike[handResult.name] then
				return { mult = 8 }
			end
			return nil
		end,
	},
	{
		id = "threes_company", name = "Three's Company", icon = "🎊", price = 5,
		description = "+12 Mult if the hand contains a Three of a Kind.",
		effect = function(handResult, _context)
			if handResult.name == "Three of a Kind" or handResult.name == "Full House" then
				return { mult = 12 }
			end
			return nil
		end,
	},
	{
		id = "all_hands_in", name = "All Hands In", icon = "🙌", price = 7,
		description = "+10 Mult if the hand contains a Four of a Kind.",
		effect = function(handResult, _context)
			if handResult.name == "Four of a Kind" then
				return { mult = 10 }
			end
			return nil
		end,
	},
	{
		id = "straight_shooter", name = "Straight Shooter", icon = "🎯", price = 6,
		description = "+12 Mult if the hand contains a Straight.",
		effect = function(handResult, _context)
			if handResult.name == "Straight" or handResult.name == "Straight Flush" then
				return { mult = 12 }
			end
			return nil
		end,
	},
	{
		id = "all_matching", name = "All Matching", icon = "🃏", price = 6,
		description = "+10 Mult if the hand contains a Flush.",
		effect = function(handResult, _context)
			if handResult.name == "Flush" or handResult.name == "Straight Flush" then
				return { mult = 10 }
			end
			return nil
		end,
	},
	{
		id = "small_plate", name = "Small Plate", icon = "🍽️", price = 5,
		description = "+20 Mult if you play 3 or fewer cards.",
		effect = function(_handResult, context)
			local played = context.allPlayedCards or {}
			if #played > 0 and #played <= 3 then
				return { mult = 20 }
			end
			return nil
		end,
	},

	-- ===== +CHIPS =====
	{
		id = "big_portions", name = "Big Portions", icon = "🍖", price = 5,
		description = "+50 Chips if the hand contains a Pair (or better).",
		effect = function(handResult, _context)
			local pairLike = {
				["Pair"] = true, ["Two Pair"] = true, ["Three of a Kind"] = true,
				["Full House"] = true, ["Four of a Kind"] = true,
			}
			if pairLike[handResult.name] then
				return { chips = 50 }
			end
			return nil
		end,
	},
	{
		id = "tab_regulars", name = "Tab Regulars", icon = "💰", price = 5,
		description = "+1 Chip for every 2 Tips you're currently holding (rounded down).",
		effect = function(_handResult, context)
			local tips = context.tips or 0
			if tips >= 2 then
				return { chips = math.floor(tips / 2) }
			end
			return nil
		end,
	},

	-- ===== XMULT =====
	{
		id = "house_favorite", name = "House Favorite", icon = "👑", price = 8,
		description = "x1.5 Mult for each King held in your hand (not played).",
		effect = function(_handResult, context)
			local count = 0
			for _, card in ipairs(context.heldCards or {}) do
				if card.rank == 13 then
					count = count + 1
				end
			end
			if count > 0 then
				return { multMultiplier = 1.5 ^ count }
			end
			return nil
		end,
	},
	{
		id = "repeat_customer", name = "Repeat Customer", icon = "🔁", price = 7,
		description = "x3 Mult if you've already played this poker hand type this round.",
		effect = function(_handResult, context)
			if context.alreadyPlayedThisHandTypeThisRound then
				return { multMultiplier = 3 }
			end
			return nil
		end,
	},

	-- ===== UTILITY =====
	{
		id = "the_understudy", name = "The Understudy", icon = "🎭", price = 6,
		description = "Copies the ability of the Patron to its right.",
		effect = function(handResult, context)
			local patrons = context.ownedPatrons or {}
			local i = context.patronIndex or 0
			local rightNeighbor = patrons[i + 1]
			if rightNeighbor and rightNeighbor.id ~= "the_understudy" then
				return rightNeighbor.effect(handResult, context)
			end
			return nil
		end,
	},
	{
		id = "second_opinion", name = "Second Opinion", icon = "💡", price = 6,
		description = "Copies the ability of your leftmost Patron.",
		effect = function(handResult, context)
			local patrons = context.ownedPatrons or {}
			local leftmost = patrons[1]
			if leftmost and leftmost.id ~= "second_opinion" then
				return leftmost.effect(handResult, context)
			end
			return nil
		end,
	},

	-- ===== ECONOMY =====
	{
		id = "tip_jar", name = "Tip Jar", icon = "🫙", price = 6,
		description = "Earn 4 Tips at the end of each round you win.",
		effect = function() return nil end,
		onRoundWin = function(state)
			state.tips = state.tips + 4
		end,
	},
	{
		id = "penny_pincher", name = "Penny Pincher", icon = "🪙", price = 6,
		description = "+2 Mult for every 5 Tips you're currently holding.",
		effect = function(_handResult, context)
			local tips = context.tips or 0
			if tips >= 5 then
				return { mult = 2 * math.floor(tips / 5) }
			end
			return nil
		end,
	},

	-- ===== More suit specialists (mirrors Suit Yourself, one per remaining suit) =====
	{
		id = "sparkling_service", name = "Sparkling Service", icon = "💎", price = 6,
		description = "+3 Mult for each Diamond among the scoring cards.",
		effect = function(handResult, _context)
			local count = 0
			for _, card in ipairs(handResult.scoringCards) do
				if Card.hasSuit(card, "Diamonds") then
					count = count + 1
				end
			end
			if count > 0 then
				return { mult = 3 * count }
			end
			return nil
		end,
	},
	{
		id = "rowdy_bunch", name = "Rowdy Bunch", icon = "♣️", price = 6,
		description = "+3 Mult for each Club among the scoring cards.",
		effect = function(handResult, _context)
			local count = 0
			for _, card in ipairs(handResult.scoringCards) do
				if Card.hasSuit(card, "Clubs") then
					count = count + 1
				end
			end
			if count > 0 then
				return { mult = 3 * count }
			end
			return nil
		end,
	},
	{
		id = "sharp_dressed", name = "Sharp Dressed", icon = "♠️", price = 6,
		description = "+3 Mult for each Spade among the scoring cards.",
		effect = function(handResult, _context)
			local count = 0
			for _, card in ipairs(handResult.scoringCards) do
				if Card.hasSuit(card, "Spades") then
					count = count + 1
				end
			end
			if count > 0 then
				return { mult = 3 * count }
			end
			return nil
		end,
	},
}

function Patrons.getById(id)
	for _, patron in ipairs(Patrons.Definitions) do
		if patron.id == id then
			return patron
		end
	end
	return nil
end

return Patrons
