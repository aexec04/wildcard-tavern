--[[
	BossRules.lua
	Pure helpers for the "scoring rule" fields that Boss Rounds (Engine/BossRounds.lua) and Challenge Runs
	(Engine/Challenges.lua) share, so the server (RunState.playHand) and the client's score preview read ONE
	implementation. No Roblox APIs.

	A rule set is a plain table; a Boss Round modifier and a Challenge twist can both be passed. Fields read here:
	  noScoreHandTypes   { [handName] = true }   these hands score 0 (Picky Eater, Pairs Only)
	  minHandName        handName                hands that rank below it in HandEvaluator.HandOrder score 0
	  firstHandMultiplier number                 the first hand played in a round scores x this
	  patronCap          number                  only the first N owned Patrons take part in scoring
	  patronPower        number                  every Patron's Chips and Mult bonus is multiplied by this
	  noScoringTips      true                    Tips from scoring (Patron tips, Gold Stamps, Lucky) are not paid
	  tipsPercent        number (1..100)         percent of Tips paid at round end (flat reward and interest)
	  minCardsPerHand    number                  a hand needs at least this many cards
]]

local HandEvaluator = require(script.Parent.HandEvaluator)

local BossRules = {}

local function rankIndex(handName)
	for i, name in ipairs(HandEvaluator.HandOrder) do
		if name == handName then
			return i
		end
	end
	return nil
end

-- True when a hand of this type scores 0 under any of the given rule sets.
function BossRules.blocksHand(handName, ...)
	for i = 1, select("#", ...) do
		local rules = select(i, ...)
		if rules then
			if rules.noScoreHandTypes and rules.noScoreHandTypes[handName] then
				return true
			end
			if rules.minHandName then
				local have, need = rankIndex(handName), rankIndex(rules.minHandName)
				if have and need and have < need then
					return true
				end
			end
		end
	end
	return false
end

-- The factor a hand's score is scaled by (only firstHandMultiplier today). `isFirstHand`: no hand played yet this round.
function BossRules.scoreFactor(rules, isFirstHand)
	if rules and rules.firstHandMultiplier and isFirstHand then
		return rules.firstHandMultiplier
	end
	return 1
end

-- The Patrons that take part in scoring: capped to the first N when a rule says so.
function BossRules.scoringPatrons(rules, ownedPatrons)
	local cap = rules and rules.patronCap
	if not cap or #ownedPatrons <= cap then
		return ownedPatrons
	end
	local list = {}
	for i = 1, cap do
		list[i] = ownedPatrons[i]
	end
	return list
end

function BossRules.minCards(rules)
	return rules and rules.minCardsPerHand or nil
end

-- Percent of a Tips payout that is kept (100 when no rule applies).
function BossRules.tipsPercent(...)
	local percent = 100
	for i = 1, select("#", ...) do
		local rules = select(i, ...)
		if rules and rules.tipsPercent then
			percent = math.min(percent, rules.tipsPercent)
		end
	end
	return percent
end

function BossRules.applyPercent(amount, percent)
	if percent >= 100 then
		return amount
	end
	return math.floor(amount * percent / 100)
end

-- The rules that change a hand's Chips and Mult AFTER Scoring.calculate, in one place and one order: the boss's
-- Chips factor, the boss's Mult factor, the first-hand factor (Sleepy Cook), then the Dealer's Bargain percent.
-- RunState.playHand (the real score) and the client's hand preview both call this, so the preview cannot leave a
-- rule out again (it used to skip the Bargain percent and showed a different number than the hand then paid).
--   BossRules.finishScore(chips, mult, rules, isFirstHand, bargainPct) -> chips, mult, score
function BossRules.finishScore(chips, mult, rules, isFirstHand, bargainPct)
	if rules and rules.chipsMultiplier then
		chips = chips * rules.chipsMultiplier
	end
	if rules and rules.multMultiplier then
		mult = mult * rules.multMultiplier
	end
	mult = mult * BossRules.scoreFactor(rules, isFirstHand)
	bargainPct = tonumber(bargainPct) or 0
	if bargainPct ~= 0 then
		mult = mult * math.max(0.1, 1 + bargainPct / 100)
	end
	return chips, mult, chips * mult
end

return BossRules
