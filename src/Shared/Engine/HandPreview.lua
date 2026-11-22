--[[
	HandPreview.lua
	What a selection of cards would score if it were played right now, worked out without playing it. The play screen
	shows this before the player commits (the Multiplier panel, the score line, the Poker Hands highlight), so it has to
	be the number RunState.playHand pays.

	This used to be a second, hand-written copy of playHand's scoring inside the client hub. Each rule added to one and
	not the other made the preview drift: the Dealer's Bargain percent was missing from it, and on Empty Pockets it kept
	the Tips the play was about to wipe. Now the preview is engine code, and the test "Hand preview: what it shows is
	what the hand pays" plays random hands on every Boss Round and requires the two numbers to match.

	`view` is a run state, or the copy of one the server sends to the client. The fields read here have the same names
	in both. Luck never rolls in a preview (Scoring.noLuck), so a Lucky Garnish shows its sure value only.
	Pure Lua, no Roblox APIs.
]]

local BossRounds = require(script.Parent.BossRounds)
local BossRules = require(script.Parent.BossRules)
local HandEvaluator = require(script.Parent.HandEvaluator)
local PatronEvents = require(script.Parent.PatronEvents)
local Patrons = require(script.Parent.Patrons)
local RunState = require(script.Parent.RunState)
local Scoring = require(script.Parent.Scoring)
local Strangers = require(script.Parent.Strangers)
local NightBoons = require(script.Parent.NightBoons)
local TrueWildcard = require(script.Parent.TrueWildcard)

local HandPreview = {}

-- The cards at `cardIndices` and the cards left behind, both in hand order: the order RunState.playHand takes them in.
local function split(hand, cardIndices)
	local picked = {}
	for _, index in ipairs(cardIndices or {}) do
		picked[index] = true
	end
	local played, held = {}, {}
	for index, card in ipairs(hand) do
		if picked[index] then
			played[#played + 1] = card
		else
			held[#held + 1] = card
		end
	end
	return played, held
end

local function seatedPatrons(view)
	local seated = {}
	for _, patron in ipairs(view.ownedPatrons or {}) do
		local def = Patrons.getById(patron.id)
		if def then
			seated[#seated + 1] = def
		end
	end
	return seated
end

-- A hand the round's rules zero: same shape as a scored preview, nothing in it.
local function nothing(handName, wildcardResolution)
	return { name = handName, chips = 0, mult = 0, score = 0, breakdown = {}, brokenCards = {}, wildcardResolution = wildcardResolution }
end

-- Returns nil for an empty selection, else
--   { name, chips, mult, score, breakdown, brokenCards, tavernNotes, wildcardResolution = { rank, suit } or nil }
function HandPreview.compute(view, cardIndices)
	if not view or not view.hand then
		return nil
	end
	local played, held = split(view.hand, cardIndices)
	if #played == 0 then
		return nil
	end

	local patrons = seatedPatrons(view)
	local boss = view.bossModifier and BossRounds.getById(view.bossModifier.id)
	local playedThisRound = view.handTypesPlayedThisRound or {}
	local handsAfter = math.max(0, (view.handsRemaining or 1) - 1)
	local counters = view.runCounters or RunState.runCounters(view)
	local isFirstHand = view.roundStartHands ~= nil and view.handsRemaining == view.roundStartHands

	-- Everything Scoring reads about the moment of the play. `tips` is passed in because Empty Pockets changes it.
	local function context(handName, tips)
		return RunState.addRunCounters({
			rng = Scoring.noLuck,
			allPlayedCards = played,
			heldCards = held,
			handLevels = view.handLevels,
			ownedPatronSpecials = view.ownedPatronSpecials,
			brittleShielded = view.brittleShieldRound,
			debuff = boss and boss.debuff,
			tips = tips,
			alreadyPlayedThisHandTypeThisRound = playedThisRound[handName] == true,
			handsRemaining = handsAfter,
			discardsRemaining = view.discardsRemaining,
			isLastHand = handsAfter == 0,
			night = view.night,
			round = view.round,
		}, counters)
	end

	-- The run's True Wildcard locks in as whatever scores best. Try it on, and put the card back before returning.
	local wildcard, wildRank, wildSuit, wildcardResolution
	for _, card in ipairs(played) do
		if card.isTrueWildcard and not card.wildcardLocked then
			wildcard, wildRank, wildSuit = card, card.rank, card.suit
			break
		end
	end
	if wildcard then
		local bestRank, bestSuit = TrueWildcard.findBestChoice(played, wildcard, patrons, function(candidate)
			if boss and boss.noRepeatHandTypes and playedThisRound[candidate.name] == true then
				return nil
			end
			return context(candidate.name, view.tips)
		end)
		wildcard.rank, wildcard.suit = bestRank, bestSuit
		wildcardResolution = { rank = bestRank, suit = bestSuit }
	end
	local function restore()
		if wildcard then
			wildcard.rank, wildcard.suit = wildRank, wildSuit
		end
	end

	local evaluated, handResult = pcall(HandEvaluator.evaluate, played)
	if not evaluated or not handResult then
		restore()
		return nil
	end
	local handName = handResult.name
	if BossRules.blocksHand(handName, boss, view.challenge)
		or (boss and boss.noRepeatHandTypes and playedThisRound[handName] == true) then
		restore()
		return nothing(handName, wildcardResolution)
	end

	local tips = BossRules.wipesTips(boss, counters.handStatsBefore, handName) and 0 or view.tips
	local scoringContext = context(handName, tips)
	scoringContext.patronPower = (view.challenge and view.challenge.patronPower) or (view.dailyModifier and view.dailyModifier.patronPower)
	local scored, _, chips, mult, extra = pcall(Scoring.calculate, handResult, BossRules.scoringPatrons(boss, patrons), scoringContext)
	restore()
	if not scored then
		return nil
	end

	local bargainPct = Strangers.field(view, "scorePct")
	local score
	chips, mult, score = BossRules.finishScore(chips, mult, boss, isFirstHand, bargainPct + NightBoons.scorePct(view, isFirstHand))
	return {
		name = handName,
		chips = chips,
		mult = mult,
		score = score,
		breakdown = extra and extra.breakdown,
		brokenCards = extra and extra.brokenCards,
		tavernNotes = PatronEvents.tavernNotes(boss, isFirstHand, bargainPct),
		wildcardResolution = wildcardResolution,
	}
end

return HandPreview
