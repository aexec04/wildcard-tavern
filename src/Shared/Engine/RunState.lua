--[[
	RunState.lua
	The single-player run/round state machine: nights -> rounds -> hands,
	with a shop between rounds. Pure Lua -- no Roblox APIs -- so the whole
	run can be simulated and unit tested without ever opening Studio.

	A "state" here is a plain table (see RunState.new). Every function takes
	the state as its first argument and mutates it in place, then returns
	whatever result info is useful to the caller (server script / tests).
]]

local Deck = require(script.Parent.Deck)
local HandEvaluator = require(script.Parent.HandEvaluator)
local Scoring = require(script.Parent.Scoring)
local Patrons = require(script.Parent.Patrons)
local Themes = require(script.Parent.Themes)
local DeckVariants = require(script.Parent.DeckVariants)
local DifficultyTiers = require(script.Parent.DifficultyTiers)
local BossRounds = require(script.Parent.BossRounds)

local RunState = {}

RunState.DefaultConfig = {
	handSize = 8,
	handsPerRound = 4,
	discardsPerRound = 3,
	roundsPerNight = 3,
	tipsPerRoundWin = 4,
}

-- Target score curve. Original formula/numbers -- tune freely.
function RunState.targetScoreFor(night, round, roundsPerNight)
	roundsPerNight = roundsPerNight or RunState.DefaultConfig.roundsPerNight
	local step = (night - 1) * roundsPerNight + (round - 1)
	return math.floor(100 * (1.35 ^ step))
end

--[[
	options (all optional): { deckVariantId = string, difficultyId = string }
	Unknown/omitted ids fall back to the standard deck variant and standard
	difficulty, so `RunState.new()` and `RunState.new(nil, rng)` both still
	produce the original default-balance run.
]]
function RunState.new(options, rng)
	options = options or {}

	local deckVariant = DeckVariants.getById(options.deckVariantId) or DeckVariants.getById(DeckVariants.DefaultId)
	local difficulty = DifficultyTiers.getById(options.difficultyId) or DifficultyTiers.getById(DifficultyTiers.DefaultId)

	local config = {}
	for key, value in pairs(RunState.DefaultConfig) do
		config[key] = value
	end
	for key, delta in pairs(deckVariant.configOverrides or {}) do
		config[key] = config[key] + delta
	end
	config.handSize = math.max(1, config.handSize)
	config.handsPerRound = math.max(1, config.handsPerRound)
	config.discardsPerRound = math.max(0, config.discardsPerRound)
	config.roundsPerNight = math.max(1, config.roundsPerNight)

	local state = {
		config = config,
		rng = rng,
		deckVariantId = deckVariant.id,
		difficultyId = difficulty.id,
		targetMultiplier = (deckVariant.targetScoreMultiplier or 1) * (difficulty.targetScoreMultiplier or 1),
		bossRoundsEnabled = difficulty.bossRoundsEnabled ~= false,
		night = 1,
		round = 1,
		tips = deckVariant.startingTips or 0,
		ownedPatrons = {},
		ownedThemes = { [Themes.DefaultThemeId] = true },
		equippedTheme = Themes.DefaultThemeId,
		deck = {},
		hand = {},
		handsRemaining = config.handsPerRound,
		discardsRemaining = config.discardsPerRound,
		roundScore = 0,
		targetScore = 0, -- computed by startRound below
		handStats = {}, -- [handName] = times played this run, for the Poker Hands reference screen
		bossModifier = nil,
		roundOver = false,
		runOver = false,
		wonRun = false,
	}
	RunState.startRound(state)
	return state
end

-- Shuffles a fresh deck, picks this round's Boss modifier (if any), and
-- deals a new starting hand for the current round.
function RunState.startRound(state)
	state.deck = Deck.shuffle(Deck.newStandardDeck(), state.rng)

	local isBoss = state.bossRoundsEnabled and BossRounds.isBossRound(state.round, state.config.roundsPerNight)
	state.bossModifier = isBoss and BossRounds.pick(state.rng) or nil

	local handSize = state.config.handSize + ((state.bossModifier and state.bossModifier.handSizeDelta) or 0)
	handSize = math.max(1, handSize)
	local discards = state.config.discardsPerRound + ((state.bossModifier and state.bossModifier.discardsDelta) or 0)
	discards = math.max(0, discards)

	state.hand = Deck.draw(state.deck, handSize)
	state.handsRemaining = state.config.handsPerRound
	state.discardsRemaining = discards
	state.roundScore = 0

	local bossMultiplier = (state.bossModifier and state.bossModifier.targetScoreMultiplier) or 1
	local baseTarget = RunState.targetScoreFor(state.night, state.round, state.config.roundsPerNight)
	state.targetScore = math.floor(baseTarget * state.targetMultiplier * bossMultiplier)

	state.roundOver = false
end

local function removeIndicesFromHand(state, indices)
	-- indices: array of 1-based positions into state.hand, must be unique.
	local indexSet = {}
	for _, i in ipairs(indices) do
		indexSet[i] = true
	end
	local played, kept = {}, {}
	for i, card in ipairs(state.hand) do
		if indexSet[i] then
			table.insert(played, card)
		else
			table.insert(kept, card)
		end
	end
	state.hand = kept
	return played
end

--[[
	Play 1-5 cards from the hand (by 1-based index into state.hand).
	Returns a result table: { handName, score, chips, mult, roundWon, runOver, wonRun }
]]
function RunState.playHand(state, cardIndices)
	assert(not state.roundOver, "Round is already over -- advance to the next round first")
	assert(#cardIndices >= 1 and #cardIndices <= 5, "Play between 1 and 5 cards")
	assert(state.handsRemaining > 0, "No hands remaining this round")

	local playedCards = removeIndicesFromHand(state, cardIndices)
	local handResult = HandEvaluator.evaluate(playedCards)

	state.handStats[handResult.name] = (state.handStats[handResult.name] or 0) + 1

	state.handsRemaining = state.handsRemaining - 1
	local isLastHand = state.handsRemaining == 0

	local score, chips, mult = Scoring.calculate(handResult, state.ownedPatrons, {
		allPlayedCards = playedCards,
		handsRemaining = state.handsRemaining,
		discardsRemaining = state.discardsRemaining,
		isLastHand = isLastHand,
		night = state.night,
		round = state.round,
	})

	state.roundScore = state.roundScore + score

	-- Refill hand from the deck.
	local drawn = Deck.draw(state.deck, #playedCards)
	for _, card in ipairs(drawn) do
		table.insert(state.hand, card)
	end

	local roundWon = state.roundScore >= state.targetScore
	if roundWon then
		state.roundOver = true
		-- Clearing a Boss Round pays double -- it's the harder ask each Night.
		local reward = state.config.tipsPerRoundWin
		if state.bossModifier then
			reward = reward + state.config.tipsPerRoundWin
		end
		state.tips = state.tips + reward
	elseif isLastHand then
		-- Out of hands and didn't reach the target: the run ends.
		state.roundOver = true
		state.runOver = true
		state.wonRun = false
	end

	return {
		handName = handResult.name,
		score = score,
		chips = chips,
		mult = mult,
		roundScore = state.roundScore,
		targetScore = state.targetScore,
		roundWon = roundWon,
		runOver = state.runOver,
		bossModifierId = state.bossModifier and state.bossModifier.id or nil,
	}
end

-- Discard 1-5 cards from the hand and draw replacements.
function RunState.discard(state, cardIndices)
	assert(not state.roundOver, "Round is already over")
	assert(#cardIndices >= 1 and #cardIndices <= 5, "Discard between 1 and 5 cards")
	assert(state.discardsRemaining > 0, "No discards remaining this round")

	local discarded = removeIndicesFromHand(state, cardIndices)
	state.discardsRemaining = state.discardsRemaining - 1

	local drawn = Deck.draw(state.deck, #discarded)
	for _, card in ipairs(drawn) do
		table.insert(state.hand, card)
	end

	return { discarded = #discarded, discardsRemaining = state.discardsRemaining }
end

-- Spend tips on a patron from the shop. Returns true/false, message.
function RunState.buyPatron(state, patronId)
	local patron = Patrons.getById(patronId)
	if not patron then
		return false, "Unknown patron: " .. tostring(patronId)
	end
	if state.tips < patron.price then
		return false, "Not enough tips"
	end
	state.tips = state.tips - patron.price
	table.insert(state.ownedPatrons, patron)
	return true, patron.name .. " joins your table."
end

-- Discard an owned Patron for half its price back (rounded down). Allowed
-- any time -- like theme purchases, this doesn't need to be gated to the
-- shop phase; it's tidying up your table, not a purchasing decision made
-- under shop-visit constraints. Returns true/false, refundAmount.
function RunState.sellPatron(state, patronId)
	for i, patron in ipairs(state.ownedPatrons) do
		if patron.id == patronId then
			table.remove(state.ownedPatrons, i)
			local refund = math.floor(patron.price / 2)
			state.tips = state.tips + refund
			return true, refund
		end
	end
	return false, 0
end

-- Purely cosmetic: unlock a table/card color theme with tips. No gameplay
-- effect. Can be called any time -- not gated to the shop phase.
function RunState.buyTheme(state, themeId)
	local theme = Themes.getById(themeId)
	if not theme then
		return false, "Unknown theme: " .. tostring(themeId)
	end
	if state.ownedThemes[themeId] then
		return false, "Already owned"
	end
	if state.tips < theme.price then
		return false, "Not enough tips"
	end
	state.tips = state.tips - theme.price
	state.ownedThemes[themeId] = true
	return true, theme.name .. " unlocked."
end

-- Equip a previously-purchased theme. No gameplay effect.
function RunState.equipTheme(state, themeId)
	if not state.ownedThemes[themeId] then
		return false, "Theme not owned"
	end
	state.equippedTheme = themeId
	return true, "Equipped."
end

-- Call after a round is won (and shopping is done) to move on.
function RunState.advanceToNextRound(state)
	assert(state.roundOver and not state.runOver, "Can't advance: round not won or run already over")

	state.round = state.round + 1
	if state.round > state.config.roundsPerNight then
		state.round = 1
		state.night = state.night + 1
	end
	RunState.startRound(state)
end

return RunState
