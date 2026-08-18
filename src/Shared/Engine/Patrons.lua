--[[
	Patrons.lua
	"Patrons" are our equivalent of a passive modifier card that sits in your
	party and boosts hands as you play them (own original names/effects --
	swap in your own art & flavor text freely).

	Each patron is data + a pure `effect(handResult, context)` function that
	returns an optional { chips = n, mult = n, multMultiplier = n } bonus.
	Keeping effects as pure functions of (handResult, context) means they're
	trivially unit-testable in isolation.
]]

local Patrons = {}

-- context fields you can use in an effect function:
--   allPlayedCards   -- every card in the hand that was played (not just scoring ones)
--   handsRemaining   -- hands left to play this round, before this one
--   discardsRemaining
--   isLastHand       -- true if this is the last hand of the round
--   night, round     -- current progress

Patrons.Definitions = {
	{
		id = "the_regular",
		name = "The Regular",
		description = "+4 Mult on every hand.",
		price = 4,
		effect = function(_handResult, _context)
			return { mult = 4 }
		end,
	},
	{
		id = "lucky_dice",
		name = "Lucky Dice",
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
		description = "+3 Mult for each Heart among the scoring cards.",
		price = 6,
		effect = function(handResult, _context)
			local hearts = 0
			for _, card in ipairs(handResult.scoringCards) do
				if card.suit == "Hearts" then
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
