--[[
	Scoring.lua
	Turns an evaluated hand into a final score: (base chips + card chips + patron
	bonuses) x (base mult + patron bonuses), with patron multipliers applied last.

	This "chips x mult" shape is a common pattern across many card-battler
	roguelikes -- the specific numbers below are our own original balance
	pass, not copied from any other game.
]]

local Card = require(script.Parent.Card)

local Scoring = {}

-- Base chips/mult per hand name. Original numbers.
Scoring.HandBase = {
	["High Card"]       = { chips = 5,   mult = 1 },
	["Pair"]             = { chips = 10,  mult = 2 },
	["Two Pair"]          = { chips = 20,  mult = 2 },
	["Three of a Kind"]   = { chips = 30,  mult = 3 },
	["Straight"]          = { chips = 30,  mult = 4 },
	["Flush"]             = { chips = 35,  mult = 4 },
	["Full House"]        = { chips = 40,  mult = 4 },
	["Four of a Kind"]    = { chips = 60,  mult = 7 },
	["Straight Flush"]    = { chips = 100, mult = 8 },
}

--[[
	handResult: result of HandEvaluator.evaluate(cards)
	ownedPatrons: array of Patron instances (see Patrons.lua), may be empty
	context: table with extra info patrons might care about, e.g.
		{ allPlayedCards, handsRemaining, discardsRemaining, isLastHand, night, round }

	Returns: score (number), chips (number), mult (number)
]]
function Scoring.calculate(handResult, ownedPatrons, context)
	ownedPatrons = ownedPatrons or {}
	context = context or {}

	local base = Scoring.HandBase[handResult.name]
	assert(base, "Unknown hand name: " .. tostring(handResult.name))

	local chips = base.chips
	local mult = base.mult

	for _, card in ipairs(handResult.scoringCards) do
		chips = chips + Card.chipValue(card)
	end

	for _, patron in ipairs(ownedPatrons) do
		local bonus = patron.effect(handResult, context) or {}
		chips = chips + (bonus.chips or 0)
		mult = mult + (bonus.mult or 0)
		if bonus.multMultiplier then
			mult = mult * bonus.multMultiplier
		end
	end

	local score = chips * mult
	return score, chips, mult
end

return Scoring
