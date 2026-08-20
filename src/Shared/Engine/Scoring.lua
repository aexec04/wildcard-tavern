--[[
	Scoring.lua
	Turns an evaluated hand into a final score.

	Formula (same shape as the reference genre convention, our own numbers):
		Chips  = HandBase.chips + HandLevelGrowth.chips*level + per-card chips
		Mult   = HandBase.mult  + HandLevelGrowth.mult*level  + per-card mult
		            + Patron flat-mult bonuses
		XMult  = product of every x-multiplier source (card Specials/Garnishes,
		            Patron multMultiplier bonuses, Iron Garnish held-in-hand bonus)
		Score  = Chips * (Mult * XMult)

	The returned `mult` value already has XMult folded in (mult = Mult * XMult)
	-- callers that just want "the number to multiply chips by" use it as-is;
	callers that want the breakdown get it in the 4th return value.

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

-- Menu Recipes (see Recipes.lua) permanently raise a hand type's Level,
-- which raises its base chips/mult by this much per Level. Original
-- numbers, tuned so leveling up a hand you use often is a real strategy,
-- not just a shop side-grade.
Scoring.HandLevelGrowth = {
	["High Card"]       = { chips = 10, mult = 1 },
	["Pair"]             = { chips = 15, mult = 1 },
	["Two Pair"]          = { chips = 20, mult = 1 },
	["Three of a Kind"]   = { chips = 20, mult = 2 },
	["Straight"]          = { chips = 25, mult = 2 },
	["Flush"]             = { chips = 20, mult = 2 },
	["Full House"]        = { chips = 25, mult = 2 },
	["Four of a Kind"]    = { chips = 30, mult = 3 },
	["Straight Flush"]    = { chips = 40, mult = 4 },
}

-- `rng` follows the same convention as Deck.shuffle/BossRounds.pick:
-- rng(n) returns an integer in [1, n]. A "1 in N" chance hits when that
-- roll comes up 1, so tests can force a hit with `function() return 1 end`
-- or force a miss with the default identity-style rng (as long as N > 1).
local function chanceHits(rng, oneInN)
	if not oneInN or oneInN < 1 then
		return false
	end
	return rng(oneInN) == 1
end

--[[
	handResult: result of HandEvaluator.evaluate(cards)
	ownedPatrons: array of Patron instances (see Patrons.lua), may be empty
	context: table with extra info patrons/effects might care about:
		{
			allPlayedCards, handsRemaining, discardsRemaining, isLastHand,
			night, round,
			heldCards,   -- cards left in hand (NOT played) at scoring time --
			             -- drives Iron Garnish's "while held" bonus
			handLevels,  -- { [handName] = level }, from RunState -- drives
			             -- Menu Recipe hand-leveling bonuses
			debuff,      -- nil | "FaceCards" | "Hearts" | "Diamonds" | "Clubs" | "Spades"
			             -- from a Boss Round modifier -- matching scoring
			             -- cards contribute nothing this hand
			rng,         -- optional, defaults to math.random; rng(n) -> [1,n]
		}

	Returns: score, chips, mult, extra
		extra = { tipsEarned = number, brokenCards = {card, ...}, breakdown = {...} }
		  tipsEarned   -- Tips to award immediately (Gold Stamp / Lucky Garnish
		                  procs / patron `tips` bonuses) -- caller adds this
		                  to state.tips
		  brokenCards  -- Brittle Garnish cards that shattered this hand --
		                  caller should remove these from the deck for good
		  breakdown    -- ordered list of every individual scoring event that
		                  contributed to this hand's final Chips/Mult/XMult,
		                  in the exact order they're applied below (base hand
		                  value, then each scoring card's rank/Garnish/Special/
		                  Stamp, then held-card Iron Garnish, then each owned
		                  Patron's effect + Special). Each entry is
		                  { kind = "chips"|"mult"|"xmult", amount = number,
		                  label = string }. This is ADDITIVE data purely for
		                  client-side scoring "juice" (Client/ScorePopup.lua
		                  plays it back as a sequenced chips/mult/xmult reveal)
		                  -- nothing in the engine reads its own breakdown
		                  back, so it can never desync the actual chips/mult/
		                  score math above.
]]
function Scoring.calculate(handResult, ownedPatrons, context)
	ownedPatrons = ownedPatrons or {}
	context = context or {}
	local rng = context.rng or math.random

	local base = Scoring.HandBase[handResult.name]
	assert(base, "Unknown hand name: " .. tostring(handResult.name))

	local level = (context.handLevels and context.handLevels[handResult.name]) or 0
	local growth = Scoring.HandLevelGrowth[handResult.name] or { chips = 0, mult = 0 }

	local chips = base.chips + growth.chips * level
	local mult = base.mult + growth.mult * level -- flat mult; xmult folded in at the end
	local xmult = 1
	local tipsEarned = 0
	local brokenCards = {}

	-- See the big comment above Scoring.calculate -- this only ever gets
	-- APPENDED to, never read back into the actual chips/mult/xmult math.
	local breakdown = {}
	table.insert(breakdown, { kind = "chips", amount = chips, label = handResult.name })
	table.insert(breakdown, { kind = "mult", amount = mult, label = handResult.name })

	local debuff = context.debuff
	local function isDebuffed(card)
		if not debuff then
			return false
		end
		if debuff == "FaceCards" then
			return Card.isFaceCard(card)
		end
		return Card.hasSuit(card, debuff)
	end

	-- Scores ONE trigger of a single card's own rank + Garnish + Special +
	-- Stamp. Called twice for a card with an Encore Stamp.
	local function scoreCardOnce(card)
		local dChips, dMult, dXMult, dTips = Card.chipValue(card), 0, 1, 0

		local g = card.garnish and Card.Garnishes[card.garnish]
		if g then
			dChips = dChips + (g.chips or 0)
			dMult = dMult + (g.mult or 0)
			if g.xmult then
				dXMult = dXMult * g.xmult
			end
			if g.luckyMultOneInN and chanceHits(rng, g.luckyMultOneInN) then
				dMult = dMult + g.luckyMult
			end
			if g.luckyTipsOneInN and chanceHits(rng, g.luckyTipsOneInN) then
				dTips = dTips + g.luckyTips
			end
		end

		local s = card.special and Card.Specials[card.special]
		if s then
			dChips = dChips + (s.chips or 0)
			dMult = dMult + (s.mult or 0)
			if s.xmult then
				dXMult = dXMult * s.xmult
			end
		end

		local st = card.stamp and Card.Stamps[card.stamp]
		if st and st.scoreTips then
			dTips = dTips + st.scoreTips
		end

		return dChips, dMult, dXMult, dTips
	end

	for _, card in ipairs(handResult.scoringCards) do
		if not isDebuffed(card) then
			local triggers = 1
			local stamp = card.stamp and Card.Stamps[card.stamp]
			if stamp and stamp.retrigger then
				triggers = 2
			end

			for _ = 1, triggers do
				local dChips, dMult, dXMult, dTips = scoreCardOnce(card)
				chips = chips + dChips
				mult = mult + dMult
				xmult = xmult * dXMult
				tipsEarned = tipsEarned + dTips

				local cardLabel = Card.toString(card)
				if dChips ~= 0 then
					table.insert(breakdown, { kind = "chips", amount = dChips, label = cardLabel })
				end
				if dMult ~= 0 then
					table.insert(breakdown, { kind = "mult", amount = dMult, label = cardLabel })
				end
				if dXMult ~= 1 then
					table.insert(breakdown, { kind = "xmult", amount = dXMult, label = cardLabel })
				end
			end

			-- "Sugar Shield" Secret Recipe protects Brittle Garnish cards
			-- from shattering for the rest of the round it was used in.
			local garnish = card.garnish and Card.Garnishes[card.garnish]
			if garnish and garnish.breakOneInN and not context.brittleShielded and chanceHits(rng, garnish.breakOneInN) then
				table.insert(brokenCards, card)
			end
		end
	end

	-- Iron Garnish: x1.5 Mult for each copy held in hand (NOT played).
	for _, card in ipairs(context.heldCards or {}) do
		local g = card.garnish and Card.Garnishes[card.garnish]
		if g and g.heldXMult then
			xmult = xmult * g.heldXMult
			table.insert(breakdown, { kind = "xmult", amount = g.heldXMult, label = Card.toString(card) .. " (held)" })
		end
	end

	-- ownedPatrons/patronIndex let a patron's effect look at (or copy) its
	-- neighbors' abilities (see "The Understudy" / "Second Opinion").
	local ownedPatronSpecials = context.ownedPatronSpecials or {}
	context.ownedPatrons = ownedPatrons
	for i, patron in ipairs(ownedPatrons) do
		context.patronIndex = i
		local bonus = patron.effect(handResult, context) or {}
		chips = chips + (bonus.chips or 0)
		mult = mult + (bonus.mult or 0)
		if bonus.chips and bonus.chips ~= 0 then
			table.insert(breakdown, { kind = "chips", amount = bonus.chips, label = patron.name })
		end
		if bonus.mult and bonus.mult ~= 0 then
			table.insert(breakdown, { kind = "mult", amount = bonus.mult, label = patron.name })
		end
		if bonus.multMultiplier then
			xmult = xmult * bonus.multMultiplier
			table.insert(breakdown, { kind = "xmult", amount = bonus.multMultiplier, label = patron.name })
		end
		tipsEarned = tipsEarned + (bonus.tips or 0)

		-- A Special applied to this Patron (Silver/Gold/Rainbow -- e.g. via
		-- the "Clean Sweep" or "Star Treatment" Secret Recipes) contributes
		-- its Chips/Mult/XMult every hand, same numbers as on a card. The
		-- Reserved Special has no chips/mult/xmult fields, so it's a no-op
		-- here -- its +1 Patron slot effect is handled separately in
		-- RunState.patronSlotLimit.
		local specialId = ownedPatronSpecials[patron.id]
		local special = specialId and Card.Specials[specialId]
		if special then
			chips = chips + (special.chips or 0)
			mult = mult + (special.mult or 0)
			if special.chips and special.chips ~= 0 then
				table.insert(breakdown, { kind = "chips", amount = special.chips, label = patron.name .. "'s Special" })
			end
			if special.mult and special.mult ~= 0 then
				table.insert(breakdown, { kind = "mult", amount = special.mult, label = patron.name .. "'s Special" })
			end
			if special.xmult then
				xmult = xmult * special.xmult
				table.insert(breakdown, { kind = "xmult", amount = special.xmult, label = patron.name .. "'s Special" })
			end
		end
	end

	mult = mult * xmult
	local score = chips * mult
	return score, chips, mult, { tipsEarned = tipsEarned, brokenCards = brokenCards, breakdown = breakdown }
end

return Scoring
