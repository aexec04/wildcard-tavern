--[[
	Sim.lua
	Headless bots that play Wildcard Tavern through the real engine. Rounds
	go through RunState.playHand/discard, offers through Shop.rollOffers and
	purchases through RunState.buy*/openPack/resolvePack, so a balance number
	can never drift from what the game does. Only the decisions live here.

	Bots:
		random  -- plays a random legal selection, never discards
		greedy  -- plays the highest-scoring subset, never discards
		decent  -- as greedy, but discards when behind pace
		builder -- as decent, but it picks the draw: it tries holding its best
		           play, a Flush draw, a Straight draw, its pairs and its high
		           cards on sampled redraws and goes for whichever scores best
		           with its own Patrons. Sim.chaseTable plays hands this way.
	All four share the shop policy in Sim.shopVisit.

	Determinism: each run is a pure function of (config, seed). playHand rolls
	Lucky/Brittle procs with math.random, so runOne reseeds that too.

	Written in the Lua subset Luau also accepts (no //, bit ops or goto).
]]

local Sim = {}

-- Set by Sim.init.
local E

local MAX_ACTIONS_PER_ROUND = 200
local SAMPLE_HANDS = 3 -- hands drawn per marginal-value estimate
local MAX_REROLLS_PER_VISIT = 3
local RICH_MARGIN = 10 -- Tips to keep beyond a reroll's cost before rerolling
local SWAP_FACTOR = 1.3 -- a new Patron must beat the weakest seat by this much
local ROLLOUTS = 6 -- builder bot: sampled redraws per draw it weighs

local VOUCHERS_WANTED = { double_shift = true, late_kitchen = true, grand_opening = true }

-- Standard Pack keep priority; a card is kept at 3 or above.
local GARNISH_PRIORITY = { brittle = 8, iron = 7, zesty = 5, lucky = 4, sweet = 3 }
local SPECIAL_PRIORITY = { rainbow = 9, gold = 6, silver = 4 }
local STAMP_PRIORITY = { encore = 3 }
local STANDARD_KEEP_PRIORITY = 3

-- Rough relative gains the score probe can't see: these Patrons pay out in
-- Tips, or only trigger in a situation the neutral probe doesn't set up.
local UNSEEN_GAIN = {
	tip_jar = 0.12, big_spender = 0.10, spare_change = 0.08, rainy_day_fund = 0.05,
	boss_bane = 0.08, nest_egg = 0.05, curtain_call = 0.15, repeat_customer = 0.5,
	-- Scaling Patrons: what the probe's "today" misses of their later growth.
	slow_cooker = 0.3, house_tab = 0.25, regulars_chair = 0.2, cobweb_shelf = 0.15,
	tasting_menu = 0.1, pair_bonds = 0.2, veterans_table = 0.15, estate_sale = 0.05,
}

-- How to use each Recipe from the shop, where `hand` is whatever is left over
-- from the round just won. `pick` chooses card positions; `value` ranks the
-- Recipe when picking from a pack. Anything not listed is never picked.
--   best = highest rank first, worst = lowest rank first
local RECIPE_USE = {
	-- House
	sugar_rush = { value = 4, pick = "best", count = 2 },
	spice_rack = { value = 6, pick = "best", count = 2 },
	cast_iron_order = { value = 7, pick = "worst", count = 1 },
	candy_order = { value = 8, pick = "best", count = 1 },
	golden_hour = { value = 3, pick = "worst", count = 1 },
	house_token_order = { value = 3, pick = "worst", count = 1 },
	eighty_six_it = { value = 5, pick = "worst", count = 2 },
	copy_the_order = { value = 5, pick = "copy" },
	suit_swap = { value = 3, pick = "suit" },
	tip_doubler = { value = 6 },
	tabs_on_the_house = { value = 5 },
	new_regular = { value = 7, needsSeat = true },
	encore_order = { value = 4, pick = "best", count = 1 },
	blue_plate_special = { value = 3, pick = "worst", count = 1 },
	lucky_ticket = { value = 4, pick = "best", count = 1 },
	sunday_special = { value = 4, pick = "best", count = 1 },
	silver_service = { value = 4, pick = "best", count = 1 },
	fresh_squeeze = { value = 2, pick = "best", count = 1 },
	round_up = { value = 3 },
	-- Secret
	mystery_guest = { value = 5 },
	final_course = { value = 5 },
	loyalty_punch = { value = 3, pick = "best", count = 1 },
	chefs_special = { value = 6, pick = "best", count = 1 },
	whole_menu_upgrade = { value = 9 },
	star_treatment = { value = 7, needsPatron = true },
	patron_of_the_month = { value = 6, needsPatron = true },
	prime_reservation = { value = 7, needsPatron = true },
	everybodys_favorite = { value = 6, needsPatron = true },
	fresh_delivery = { value = 3 },
	crowd_favorite = { value = 7 },
	gold_standard = { value = 7, pick = "best", count = 1 },
	rainbow_sprinkle = { value = 8, pick = "best", count = 1 },
	bedtime_bonus = { value = 4 },
}

-- Tips each Patron actually pays out, reported per run by wrapping its
-- onRoundWin. Wrapped once per process, on the shared definitions.
local function trackEconomyPatrons()
	for _, patron in ipairs(E.Patrons.Definitions) do
		local original = patron.onRoundWin
		if original then
			patron.onRoundWin = function(state)
				local before = state.tips
				original(state)
				local econ = state.simRecord and state.simRecord.econTips
				if econ then
					econ[patron.id] = (econ[patron.id] or 0) + (state.tips - before)
				end
			end
		end
	end
end

function Sim.init(engine)
	E = engine
	trackEconomyPatrons()
	-- MenuRecipes is built with pairs(), whose string-key order changes per
	-- process in Lua 5.3. Sorting keeps a seed's pack reveals reproducible.
	table.sort(E.Recipes.MenuRecipes, function(a, b)
		return a.id < b.id
	end)
end

local function noLuck(n)
	return n
end

-- ===== Subset enumeration =====

local comboCache = {}

-- All index subsets of 1..n per size, each with its complement.
local function combosFor(n)
	if comboCache[n] then
		return comboCache[n]
	end
	local bySize = {}
	for size = 1, math.min(5, n) do
		bySize[size] = {}
	end
	local current = {}
	local function walk(start, size)
		if #current == size then
			local chosen, inChosen, held = {}, {}, {}
			for i, v in ipairs(current) do
				chosen[i] = v
				inChosen[v] = true
			end
			for i = 1, n do
				if not inChosen[i] then
					held[#held + 1] = i
				end
			end
			table.insert(bySize[size], { played = chosen, held = held })
			return
		end
		for i = start, n do
			current[#current + 1] = i
			walk(i + 1, size)
			current[#current] = nil
		end
	end
	for size = 1, math.min(5, n) do
		walk(1, size)
	end
	comboCache[n] = bySize
	return bySize
end

local function pickCards(hand, indices)
	local cards = {}
	for i, index in ipairs(indices) do
		cards[i] = hand[index]
	end
	return cards
end

-- ===== Scoring a candidate play (mirrors RunState.playHand) =====

local function scorePlay(state, hand, combo, patrons)
	local played = pickCards(hand, combo.played)
	local handResult = E.HandEvaluator.evaluate(played)
	local boss = state.bossModifier
	local alreadyPlayed = state.handTypesPlayedThisRound[handResult.name] == true
	if boss and boss.noRepeatHandTypes and alreadyPlayed then
		return 0, handResult
	end
	-- Boss Rounds that zero a hand type (Picky Eater, Pair Patrol) or let fewer Patrons score (Crowded Counter): the
	-- helpers RunState.playHand uses. Before this the bots kept playing Flushes into Picky Eater for nothing.
	local rules = E.BossRules
	if rules then
		if rules.blocksHand(handResult.name, boss, state.challenge) then
			return 0, handResult
		end
		patrons = rules.scoringPatrons(boss, patrons)
	end
	local handsLeft = state.handsRemaining - 1
	local _, chips, mult = E.Scoring.calculate(handResult, patrons, E.RunState.addRunCounters({
		rng = noLuck,
		allPlayedCards = played,
		heldCards = pickCards(hand, combo.held),
		handLevels = state.handLevels,
		ownedPatronSpecials = state.ownedPatronSpecials,
		debuff = boss and boss.debuff,
		tips = state.tips,
		alreadyPlayedThisHandTypeThisRound = alreadyPlayed,
		handsRemaining = handsLeft,
		discardsRemaining = state.discardsRemaining,
		isLastHand = handsLeft <= 0,
		night = state.night,
		round = state.round,
	}, state.simCounters))
	if boss and boss.chipsMultiplier then
		chips = chips * boss.chipsMultiplier
	end
	if boss and boss.multMultiplier then
		mult = mult * boss.multMultiplier
	end
	if rules and state.roundStartHands then
		mult = mult * rules.scoreFactor(boss, state.handsRemaining == state.roundStartHands) -- Sleepy Cook
	end
	return chips * mult, handResult
end

-- Best legal play for the current hand. Ties keep the fewest cards.
function Sim.bestPlay(state)
	local hand = state.hand
	local bySize = combosFor(#hand)
	local boss = state.bossModifier
	local required = boss and boss.requiredCardsPerHand
	local minCards = (boss and boss.minCardsPerHand) or (state.challenge and state.challenge.minCardsPerHand) or 1
	state.simCounters = E.RunState.runCounters(state)
	local bestScore, bestCombo = -1, nil
	for size = math.min(minCards, #hand), math.min(5, #hand) do
		if not required or size == required then
			for _, combo in ipairs(bySize[size]) do
				local score = scorePlay(state, hand, combo, state.ownedPatrons)
				if score > bestScore then
					bestScore, bestCombo = score, combo
				end
			end
		end
	end
	return bestScore, bestCombo
end

-- ===== Discard heuristic (decent bot) =====

-- Positions to keep: a 4+ card suit group, else all paired ranks, else the 3
-- highest cards.
function Sim.chooseKeep(hand)
	local bySuit, byRank = {}, {}
	for i, card in ipairs(hand) do
		bySuit[card.suit] = bySuit[card.suit] or {}
		table.insert(bySuit[card.suit], i)
		byRank[card.rank] = byRank[card.rank] or {}
		table.insert(byRank[card.rank], i)
	end

	local bestSuit
	for _, suit in ipairs(E.Card.Suits) do
		local group = bySuit[suit]
		if group and #group >= 4 and (not bestSuit or #group > #bestSuit) then
			bestSuit = group
		end
	end
	if bestSuit then
		return bestSuit
	end

	local keep = {}
	for rank = 14, 2, -1 do
		local group = byRank[rank]
		if group and #group >= 2 then
			for _, i in ipairs(group) do
				table.insert(keep, i)
			end
		end
	end
	if #keep > 0 then
		return keep
	end

	local order = {}
	for i = 1, #hand do
		order[i] = i
	end
	table.sort(order, function(a, b)
		if hand[a].rank ~= hand[b].rank then
			return hand[a].rank > hand[b].rank
		end
		return a < b
	end)
	return { order[1], order[2], order[3] }
end

-- Positions to toss when keeping `keep`: everything else, lowest rank first, 5 at most.
local function tossFor(hand, keep)
	local kept = {}
	for _, i in ipairs(keep) do
		kept[i] = true
	end
	local out = {}
	for i = 1, #hand do
		if not kept[i] then
			table.insert(out, i)
		end
	end
	table.sort(out, function(a, b)
		if hand[a].rank ~= hand[b].rank then
			return hand[a].rank < hand[b].rank
		end
		return a < b
	end)
	while #out > 5 do
		table.remove(out)
	end
	return out
end

local function discardList(hand)
	return tossFor(hand, Sim.chooseKeep(hand))
end

-- ===== Build-aware discards (builder bot) =====

-- The biggest suit group, 3 cards or more. A House Blend card counts for every suit, as it does for a real Flush.
local function flushDraw(hand)
	local best
	for _, suit in ipairs(E.Card.Suits) do
		local group = {}
		for i, card in ipairs(hand) do
			if E.Card.hasSuit(card, suit) then
				group[#group + 1] = i
			end
		end
		if #group >= 3 and (not best or #group > #best) then
			best = group
		end
	end
	return best
end

-- The best Straight draw: the run of five ranks (Ace low or high) holding the most different ranks, 3 or more. Ties go
-- to the higher run.
local function straightDraw(hand)
	local byRank = {}
	for i, card in ipairs(hand) do
		if not byRank[card.rank] then
			byRank[card.rank] = i
		end
	end
	if byRank[14] then
		byRank[1] = byRank[14]
	end
	local best, bestCount = nil, 0
	for low = 1, 10 do
		local group = {}
		for rank = low, low + 4 do
			if byRank[rank] then
				group[#group + 1] = byRank[rank]
			end
		end
		if #group >= 3 and #group >= bestCount then
			best, bestCount = group, #group
		end
	end
	return best
end

-- Every card of a rank held twice or more, or nil without one.
local function pairKeep(hand)
	local byRank = {}
	for i, card in ipairs(hand) do
		byRank[card.rank] = byRank[card.rank] or {}
		table.insert(byRank[card.rank], i)
	end
	local keep = {}
	for rank = 14, 2, -1 do
		local group = byRank[rank]
		if group and #group >= 2 then
			for _, i in ipairs(group) do
				keep[#keep + 1] = i
			end
		end
	end
	return #keep > 0 and keep or nil
end

local function highKeep(hand)
	local order = {}
	for i = 1, #hand do
		order[i] = i
	end
	table.sort(order, function(a, b)
		if hand[a].rank ~= hand[b].rank then
			return hand[a].rank > hand[b].rank
		end
		return a < b
	end)
	return { order[1], order[2], order[3] }
end

-- `count` cards from `pool` added to `into`, no card twice, without changing `pool`.
local function drawFrom(pool, count, rng, into)
	local taken, got = {}, 0
	count = math.min(count, #pool)
	while got < count do
		local j = rng(#pool)
		if not taken[j] then
			taken[j] = true
			got = got + 1
			into[#into + 1] = pool[j]
		end
	end
	return into
end

-- The hand left after tossing `toss`.
local function withoutTossed(hand, toss)
	local tossed = {}
	for _, i in ipairs(toss) do
		tossed[i] = true
	end
	local kept = {}
	for i, card in ipairs(hand) do
		if not tossed[i] then
			kept[#kept + 1] = card
		end
	end
	return kept
end

-- Best score among one play per (hand type, size): the one with the highest ranks. A redraw estimate needs the size of
-- the best score, not the exact cards, and this costs about a third of the full search in Sim.bestPlay.
local function quickBest(state)
	local hand = state.hand
	local bySize = combosFor(#hand)
	local boss = state.bossModifier
	local required = boss and boss.requiredCardsPerHand
	local minCards = (boss and boss.minCardsPerHand) or (state.challenge and state.challenge.minCardsPerHand) or 1
	local best = {}
	for size = math.min(minCards, #hand), math.min(5, #hand) do
		if not required or size == required then
			for _, combo in ipairs(bySize[size]) do
				local handResult = E.HandEvaluator.evaluate(pickCards(hand, combo.played))
				local weight = 0
				for _, card in ipairs(handResult.scoringCards) do
					weight = weight + card.rank
				end
				local key = handResult.name .. size
				local entry = best[key]
				if not entry or weight > entry.weight then
					best[key] = { weight = weight, combo = combo }
				end
			end
		end
	end
	local bestScore = -1
	for _, entry in pairs(best) do
		local score = scorePlay(state, hand, entry.combo, state.ownedPatrons)
		if score > bestScore then
			bestScore = score
		end
	end
	return bestScore
end

-- Average best play after tossing `toss` and drawing that many cards at random from what is left of the deck. The bot
-- knows which cards are left (a player who counts does too), never their order.
local function rolloutValue(state, toss, rng)
	local realHand, realDiscards = state.hand, state.discardsRemaining
	local kept = withoutTossed(realHand, toss)
	state.discardsRemaining = realDiscards - 1
	local total = 0
	for _ = 1, ROLLOUTS do
		local hand = {}
		for i, card in ipairs(kept) do
			hand[i] = card
		end
		state.hand = drawFrom(state.deck, #toss, rng, hand)
		total = total + quickBest(state)
	end
	state.hand, state.discardsRemaining = realHand, realDiscards
	return total / ROLLOUTS
end

-- The toss that scores best on sampled redraws, or nothing when every draw would average less than the play in hand
-- (`holding`). Keeping the cards of that play and tossing the rest is always one of the choices.
local function builderToss(state, combo, holding, rng, rec)
	local hand = state.hand
	if #state.deck == 0 then
		return {}
	end
	local candidates, seen = {}, {}
	local function add(kind, keep)
		if not keep then
			return
		end
		local toss = tossFor(hand, keep)
		local key = table.concat(toss, ",")
		if #toss > 0 and not seen[key] then
			seen[key] = true
			candidates[#candidates + 1] = { kind = kind, toss = toss }
		end
	end
	add("hold", combo.played)
	add("flush", flushDraw(hand))
	add("straight", straightDraw(hand))
	add("pairs", pairKeep(hand))
	add("high", highKeep(hand))
	local best, bestValue = nil, -1
	for _, candidate in ipairs(candidates) do
		local value = rolloutValue(state, candidate.toss, rng)
		if value > bestValue then
			best, bestValue = candidate, value
		end
	end
	if not best or bestValue < holding then
		return {}
	end
	rec.draws[best.kind] = (rec.draws[best.kind] or 0) + 1
	return best.toss
end

-- ===== Round play =====

local function randomPlay(state, rng)
	local boss = state.bossModifier
	local size = boss and boss.requiredCardsPerHand or rng(math.min(5, #state.hand))
	local minCards = (boss and boss.minCardsPerHand) or (state.challenge and state.challenge.minCardsPerHand)
	if minCards and size < minCards then
		size = math.min(minCards, #state.hand) -- the random bot still has to follow "play at least N cards"
	end
	local pool = {}
	for i = 1, #state.hand do
		pool[i] = i
	end
	local chosen = {}
	for _ = 1, size do
		table.insert(chosen, table.remove(pool, rng(#pool)))
	end
	return chosen
end

local function playRound(state, cfg, rng, rec)
	for _ = 1, MAX_ACTIONS_PER_ROUND do
		if state.roundOver then
			return
		end
		local result
		if cfg.bot == "random" then
			result = E.RunState.playHand(state, randomPlay(state, rng))
		else
			local bestScore, combo = Sim.bestPlay(state)
			local pace = (state.targetScore - state.roundScore) / state.handsRemaining
			local toss = {}
			if bestScore < pace and state.discardsRemaining > 0 then
				if cfg.bot == "decent" then
					toss = discardList(state.hand)
				elseif cfg.bot == "builder" then
					toss = builderToss(state, combo, bestScore, rng, rec)
				end
			end
			if #toss > 0 then
				result = E.RunState.discard(state, toss)
			else
				result = E.RunState.playHand(state, combo.played)
				rec.handsPlayed[result.handName] = (rec.handsPlayed[result.handName] or 0) + 1
			end
		end
		if result.softLocked then
			rec.softLocks = rec.softLocks + 1
		end
	end
	error("Round did not finish within " .. MAX_ACTIONS_PER_ROUND .. " actions (seed " .. tostring(rec.seed) .. ")")
end

-- ===== Patron value estimates =====

local function allCards(state)
	local pool = {}
	for _, list in ipairs({ state.hand, state.deck, state.discardPile }) do
		for _, card in ipairs(list) do
			table.insert(pool, card)
		end
	end
	return pool
end

local function sampleHand(pool, size, rng)
	local copy = {}
	for i, card in ipairs(pool) do
		copy[i] = card
	end
	local hand = {}
	for _ = 1, math.min(size, #copy) do
		table.insert(hand, table.remove(copy, rng(#copy)))
	end
	return hand
end

local function neutralContext(state)
	return {
		handTypesPlayedThisRound = {},
		handLevels = state.handLevels,
		ownedPatronSpecials = state.ownedPatronSpecials,
		tips = state.tips,
		handsRemaining = 3,
		discardsRemaining = 2,
		night = state.night,
		round = 1,
		simCounters = E.RunState.runCounters(state),
	}
end

-- Keeps the best subset per (hand type, size) under a Patron-less score, so
-- comparing tables costs ~25 evaluations per hand instead of 218. Only value
-- estimates use this; real plays always search every subset.
local function representatives(probe, hand)
	local best = {}
	local bySize = combosFor(#hand)
	for size = 1, math.min(5, #hand) do
		for _, combo in ipairs(bySize[size]) do
			local score, handResult = scorePlay(probe, hand, combo, {})
			local key = handResult.name .. size
			if not best[key] or score > best[key].score then
				best[key] = { score = score, combo = combo }
			end
		end
	end
	local list = {}
	for _, entry in pairs(best) do
		table.insert(list, entry.combo)
	end
	-- pairs() order isn't stable across runs; keep the estimate reproducible.
	table.sort(list, function(a, b)
		return table.concat(a.played, ",") < table.concat(b.played, ",")
	end)
	return list
end

local function tableValue(probe, samples, patrons)
	local total = 0
	for _, sample in ipairs(samples) do
		local best = 0
		for _, combo in ipairs(sample.combos) do
			local score = scorePlay(probe, sample.hand, combo, patrons)
			if score > best then
				best = score
			end
		end
		total = total + best
	end
	return total / #samples
end

local function buildSamples(state, rng, count)
	local probe = neutralContext(state)
	local pool = allCards(state)
	local samples = {}
	for _ = 1, count do
		local hand = sampleHand(pool, state.config.handSize, rng)
		table.insert(samples, { hand = hand, combos = representatives(probe, hand) })
	end
	return probe, samples
end

local function withPatron(patrons, patron)
	local list = {}
	for i, p in ipairs(patrons) do
		list[i] = p
	end
	table.insert(list, patron)
	return list
end

local function withoutPatron(patrons, patronId)
	local list = {}
	for _, p in ipairs(patrons) do
		if p.id ~= patronId then
			table.insert(list, p)
		end
	end
	return list
end

-- Relative gain from adding each patron, keyed by id.
local function patronGains(state, rng, patrons)
	local probe, samples = buildSamples(state, rng, SAMPLE_HANDS)
	local base = math.max(1, tableValue(probe, samples, state.ownedPatrons))
	local gains = {}
	for _, patron in ipairs(patrons) do
		local value = tableValue(probe, samples, withPatron(state.ownedPatrons, patron))
		gains[patron.id] = (value - base) / base + (UNSEEN_GAIN[patron.id] or 0)
	end
	return gains, probe, samples, base
end

local function weakestSeat(state, probe, samples, base)
	local weakest, weakestLoss = nil, math.huge
	for _, patron in ipairs(state.ownedPatrons) do
		local value = tableValue(probe, samples, withoutPatron(state.ownedPatrons, patron.id))
		local loss = (base - value) / base + (UNSEEN_GAIN[patron.id] or 0)
		if loss < weakestLoss then
			weakest, weakestLoss = patron, loss
		end
	end
	return weakest, weakestLoss
end

-- ===== Recipes =====

local function indicesByRank(hand, ascending)
	local order = {}
	for i = 1, #hand do
		order[i] = i
	end
	table.sort(order, function(a, b)
		if hand[a].rank ~= hand[b].rank then
			if ascending then
				return hand[a].rank < hand[b].rank
			end
			return hand[a].rank > hand[b].rank
		end
		return a < b
	end)
	return order
end

local function firstCards(order, count)
	local out = {}
	for i = 1, math.min(count, #order) do
		out[i] = order[i]
	end
	return out
end

local function dominantSuit(hand)
	local counts, best = {}, nil
	for _, card in ipairs(hand) do
		counts[card.suit] = (counts[card.suit] or 0) + 1
	end
	for _, suit in ipairs(E.Card.Suits) do
		if counts[suit] and (not best or counts[suit] > counts[best]) then
			best = suit
		end
	end
	return best
end

local function recipeOptions(state, use)
	local hand = state.hand
	if use.pick == "best" or use.pick == "worst" then
		if #hand < use.count then
			return nil
		end
		return { cardIndices = firstCards(indicesByRank(hand, use.pick == "worst"), use.count) }
	elseif use.pick == "copy" then
		if #hand < 2 then
			return nil
		end
		local ascending = indicesByRank(hand, true)
		return { cardIndices = { ascending[1], ascending[#ascending] } }
	elseif use.pick == "suit" then
		if #hand < 1 then
			return nil
		end
		local suit = dominantSuit(hand)
		local off = {}
		for _, i in ipairs(indicesByRank(hand, true)) do
			if hand[i].suit ~= suit and #off < 3 then
				table.insert(off, i)
			end
		end
		if #off == 0 then
			return nil
		end
		return { cardIndices = off, suit = suit }
	end
	return {}
end

local function recipeUsable(state, use)
	if not use then
		return false
	end
	if use.needsPatron and #state.ownedPatrons == 0 then
		return false
	end
	if use.needsSeat and #state.ownedPatrons >= E.RunState.patronSlotLimit(state) then
		return false
	end
	return true
end

local function useHeldRecipes(state, rec)
	for _, group in ipairs({
		{ list = state.menuRecipeInventory, fn = E.RunState.useMenuRecipe },
		{ list = state.houseRecipeInventory, fn = E.RunState.useHouseRecipe },
		{ list = state.secretRecipeInventory, fn = E.RunState.useSecretRecipe },
	}) do
		for i = #group.list, 1, -1 do
			local id = group.list[i]
			local use = RECIPE_USE[id]
			if group.list == state.menuRecipeInventory then
				use = {}
			end
			if recipeUsable(state, use) then
				local opts = recipeOptions(state, use)
				if opts and group.fn(state, id, opts) then
					rec.recipesUsed = rec.recipesUsed + 1
				end
			end
		end
	end
end

-- ===== Pack picks =====

local function mostPlayedHand(rec)
	local best, bestCount = "Pair", 0
	for _, name in ipairs(E.HandEvaluator.HandOrder) do
		local count = rec.handsPlayed[name] or 0
		if count > bestCount then
			best, bestCount = name, count
		end
	end
	return best
end

local function standardPriority(card)
	return math.max(
		GARNISH_PRIORITY[card.garnish] or 0,
		SPECIAL_PRIORITY[card.special] or 0,
		STAMP_PRIORITY[card.stamp] or 0
	)
end

-- A common 0-10 scale, so a mixed pack can compare across categories.
local function itemValue(state, item, gains, topHand, rec)
	if item.category == "patron" then
		if #state.ownedPatrons >= E.RunState.patronSlotLimit(state) then
			return 0
		end
		return math.min(10, 3 + 10 * (gains[item.id] or 0))
	elseif item.category == "menu" then
		local recipe = E.Recipes.getMenuRecipeById(item.id)
		if recipe.handName == topHand then
			return 8
		end
		return 2 + math.min(4, (rec.handsPlayed[recipe.handName] or 0) / 3)
	elseif item.category == "standard" then
		local priority = standardPriority(item.card)
		return priority >= STANDARD_KEEP_PRIORITY and priority or 0
	end
	local use = RECIPE_USE[item.id]
	if recipeUsable(state, use) then
		return use.value
	end
	return 0
end

local function resolveOpenPack(state, rng, rec)
	local pending = state.pendingPack
	local patrons = {}
	for _, item in ipairs(pending.items) do
		if item.category == "patron" then
			table.insert(patrons, E.Patrons.getById(item.id))
		end
	end
	local gains = #patrons > 0 and patronGains(state, rng, patrons) or {}
	local topHand = mostPlayedHand(rec)

	local ranked = {}
	for i, item in ipairs(pending.items) do
		table.insert(ranked, { index = i, id = item.id, value = itemValue(state, item, gains, topHand, rec), item = item })
	end
	table.sort(ranked, function(a, b)
		if a.value ~= b.value then
			return a.value > b.value
		end
		return a.index < b.index
	end)

	local chosen = {}
	for i = 1, pending.pickCount do
		local entry = ranked[i]
		if entry and entry.value > 0 then
			table.insert(chosen, entry.id)
		end
	end
	if #chosen ~= pending.pickCount then
		chosen = {}
	end
	local ok, why = E.RunState.resolvePack(state, chosen)
	if not ok and tostring(why):find("Make room", 1, true) then
		-- MAKE ROOM (RunState.resolvePack): a pick that would overflow the Patron seats or the recipe box needs the player to
		-- name what leaves. These bots never sell to make room, so they leave the pack instead (an empty pick is a skip).
		-- Before this branch the simulator stopped with "Make room first" as soon as a bot with a full table opened a pack.
		chosen = {}
		ok, why = E.RunState.resolvePack(state, chosen)
	end
	assert(ok, why)
	for _, id in ipairs(chosen) do
		for _, entry in ipairs(ranked) do
			if entry.id == id and entry.item.category == "patron" then
				rec.patronsBought[id] = true
			end
		end
	end
end

-- ===== Shop =====

local function buyPatrons(state, offers, cfg, rng, rec)
	if #offers.patrons == 0 then
		return
	end
	local gains, probe, samples, base = patronGains(state, rng, offers.patrons)
	table.sort(offers.patrons, function(a, b)
		if gains[a.id] ~= gains[b.id] then
			return gains[a.id] > gains[b.id]
		end
		return a.id < b.id
	end)
	local remaining = {}
	for _, patron in ipairs(offers.patrons) do
		local gain = gains[patron.id]
		local price = E.RunState.patronPrice(state, patron)
		local bought = false
		if gain > 0.01 and state.tips - cfg.bank >= price then
			if #state.ownedPatrons >= E.RunState.patronSlotLimit(state) then
				local seat, loss = weakestSeat(state, probe, samples, base)
				if seat and gain > loss * SWAP_FACTOR + 0.02 then
					E.RunState.sellPatron(state, seat.id)
					base = math.max(1, tableValue(probe, samples, state.ownedPatrons))
				end
			end
			if #state.ownedPatrons < E.RunState.patronSlotLimit(state) then
				bought = E.RunState.buyPatron(state, patron.id)
			end
		end
		if bought then
			rec.patronsBought[patron.id] = true
		else
			table.insert(remaining, patron)
		end
	end
	offers.patrons = remaining
end

local function buyVoucher(state, offers, cfg, rec)
	local voucher = offers.voucher
	if not voucher or state.tips - cfg.bank < voucher.price then
		return
	end
	local wanted = VOUCHERS_WANTED[voucher.id]
		or (voucher.id == "extra_seating" and #state.ownedPatrons >= 5)
	if wanted and E.RunState.buyHousePass(state, voucher.id) then
		rec.vouchers[voucher.id] = true
		offers.voucher = nil
	end
end

local function totalHeldRecipes(state)
	return #state.houseRecipeInventory + #state.menuRecipeInventory + #state.secretRecipeInventory
end

local function buyPacks(state, offers, cfg, rng, rec)
	local remaining = {}
	for _, pack in ipairs(offers.packs) do
		local boxFull = totalHeldRecipes(state) >= E.RunState.recipeSlotLimit(state)
		local tableFull = #state.ownedPatrons >= E.RunState.patronSlotLimit(state)
		local useless = (pack.category == "patron" and tableFull)
			or ((pack.category == "menu" or pack.category == "house" or pack.category == "secret") and boxFull)
		local bought = false
		if not useless and state.tips - cfg.bank >= E.RunState.packPrice(state, pack) then
			if E.RunState.openPack(state, pack.id) then
				resolveOpenPack(state, rng, rec)
				useHeldRecipes(state, rec)
				bought = true
			end
		end
		if not bought then
			table.insert(remaining, pack)
		end
	end
	offers.packs = remaining
end

function Sim.shopVisit(state, cfg, rng, rec)
	rec.tipsAtShop[#rec.tipsAtShop + 1] = state.tips
	useHeldRecipes(state, rec)
	local rerollCost = E.Shop.REROLL_BASE_COST
	local offers = E.Shop.rollOffers(state)
	for rerolls = 0, MAX_REROLLS_PER_VISIT do
		buyVoucher(state, offers, cfg, rec)
		buyPatrons(state, offers, cfg, rng, rec)
		buyPacks(state, offers, cfg, rng, rec)
		local cost = E.RunState.rerollCost(state, rerollCost)
		if rerolls == MAX_REROLLS_PER_VISIT or state.tips - cfg.bank < cost + RICH_MARGIN then
			break
		end
		state.tips = state.tips - cost
		rerollCost = rerollCost + E.Shop.REROLL_COST_STEP
		offers = E.Shop.rollOffers(state)
		rec.rerolls = rec.rerolls + 1
	end
end

-- ===== One run =====

local function newRecord(seed)
	return {
		seed = seed,
		won = false,
		softLocks = 0,
		rerolls = 0,
		recipesUsed = 0,
		handsPlayed = {},
		draws = {},
		patronsBought = {},
		vouchers = {},
		tipsAtShop = {},
		bosses = {},
		econTips = {},
	}
end

-- Forces one boss on one Night; every other Night stays random. Lets clear
-- rates compare bosses on equal footing, whatever their natural minNight.
local function installBossOverride(cfg)
	local originalPick = E.BossRounds.pick
	E.BossRounds.pick = function(rng, night)
		local picked = originalPick(rng, night)
		if cfg.forceBoss and night == cfg.forceBossNight then
			return E.BossRounds.getById(cfg.forceBoss)
		end
		return picked
	end
	return function()
		E.BossRounds.pick = originalPick
	end
end

function Sim.runOne(cfg, seed)
	math.randomseed(seed)
	local rng = E.SeededRng.new(seed)
	local botRng = E.SeededRng.new((seed * 7 + 13) % 4294967296)
	local restoreBoss = installBossOverride(cfg)

	local state = E.RunState.new({
		deckVariantId = cfg.deck,
		difficultyId = cfg.difficulty,
		nightOneBonusDiscards = cfg.nightOneDiscards,
		stakeId = cfg.stake,
		mode = cfg.mode,
	}, rng)
	local rec = newRecord(seed)
	state.simRecord = rec
	if cfg.forcePatron then
		for id in string.gmatch(cfg.forcePatron, "[^,]+") do
			table.insert(state.ownedPatrons, E.Patrons.getById(id))
		end
	end
	if cfg.forcePasses then
		for id in string.gmatch(cfg.forcePasses, "[^,]+") do
			state.housePasses[id] = true
		end
		E.RunState.startRound(state)
	end

	while true do
		local isBoss = E.RunState.isBossRound(state)
		local bossId = state.bossModifier and state.bossModifier.id
		local night, round = state.night, state.round
		playRound(state, cfg, botRng, rec)

		if bossId then
			table.insert(rec.bosses, { id = bossId, night = night, cleared = not state.runOver })
		end
		if state.runOver then
			rec.deathNight, rec.deathRound = night, round
			rec.deathOnBoss = isBoss
			rec.deathBoss = bossId
			rec.deathPct = state.roundScore / math.max(1, state.targetScore)
			break
		end
		if state.wonRun then
			rec.won = true
		end
		if night >= cfg.maxNight and isBoss then
			rec.reachedCap = true
			break
		end
		if rec.won and not cfg.endless then
			break
		end
		Sim.shopVisit(state, cfg, botRng, rec)
		E.RunState.advanceToNextRound(state)
	end

	rec.finalTips = state.tips
	rec.levels = state.handLevels
	rec.nightReached = state.night
	rec.finalPatrons = {}
	for _, patron in ipairs(state.ownedPatrons) do
		table.insert(rec.finalPatrons, patron.id)
	end
	restoreBoss()
	return rec
end

-- ===== Patron marginal value table (a fixed mid-build, no run needed) =====

local MID_BUILD_PATRONS = { "the_regular", "regulars_round" }
local MID_BUILD_LEVELS = { ["Pair"] = 3, ["Two Pair"] = 3 }

-- Gain from adding each Patron to a mid-game table, averaged over `count`
-- sampled hands. Only scoring effects show up here.
function Sim.patronTable(count, seed)
	local rng = E.SeededRng.new(seed or 1)
	local state = E.RunState.new({}, E.SeededRng.new(seed or 1))
	state.night = 5
	for _, id in ipairs(MID_BUILD_PATRONS) do
		table.insert(state.ownedPatrons, E.Patrons.getById(id))
	end
	for name, level in pairs(MID_BUILD_LEVELS) do
		state.handLevels[name] = level
	end
	state.tips = 15

	local probe = neutralContext(state)
	local pool = allCards(state)
	local samples = {}
	local bySize = combosFor(state.config.handSize)
	local everySubset = {}
	for size = 1, 5 do
		for _, combo in ipairs(bySize[size]) do
			table.insert(everySubset, combo)
		end
	end
	for _ = 1, count do
		table.insert(samples, { hand = sampleHand(pool, state.config.handSize, rng), combos = everySubset })
	end

	local base = tableValue(probe, samples, state.ownedPatrons)
	local rows = {}
	for _, patron in ipairs(E.Patrons.Definitions) do
		local owned = false
		for _, id in ipairs(MID_BUILD_PATRONS) do
			owned = owned or id == patron.id
		end
		if not owned then
			local value = tableValue(probe, samples, withPatron(state.ownedPatrons, patron))
			local gain = (value - base) / base
			table.insert(rows, { id = patron.id, price = patron.price, gain = gain, gainPerPrice = gain / patron.price })
		end
	end
	table.sort(rows, function(a, b)
		return a.gainPerPrice > b.gainPerPrice
	end)
	return rows, base
end

-- ===== Patron value with discards (the builder bot's play, no run needed) =====

-- The two tables a Patron is tried on. "open" is Night 1: nobody seated, every hand at its base level. "mid" seats two
-- Patrons that pay any hand the same (so no build is favoured) and has every hand leveled twice.
local CHASE_BUILDS = {
	open = { night = 1, tips = 4, patrons = {}, level = 0 },
	mid = { night = 5, tips = 15, patrons = { "the_regular", "the_bard" }, level = 2 },
}

-- `count` fixed deals: a starting hand and the order the rest of the deck will come in.
local function chaseDeals(pool, handSize, count, rng)
	local deals = {}
	for _ = 1, count do
		local deck = {}
		for i, card in ipairs(pool) do
			deck[i] = card
		end
		for i = #deck, 2, -1 do
			local j = rng(i)
			deck[i], deck[j] = deck[j], deck[i]
		end
		local hand = {}
		for _ = 1, math.min(handSize, #deck) do
			hand[#hand + 1] = table.remove(deck)
		end
		deals[#deals + 1] = { hand = hand, deck = deck }
	end
	return deals
end

-- One hand the way the builder bot plays it: up to `discards` draws, then its best play.
local function chaseHand(state, deal, discards, rng, rec)
	state.hand, state.deck = {}, {}
	for i, card in ipairs(deal.hand) do
		state.hand[i] = card
	end
	for i, card in ipairs(deal.deck) do
		state.deck[i] = card
	end
	state.discardsRemaining = discards
	while true do
		local bestScore, combo = Sim.bestPlay(state)
		local toss = state.discardsRemaining > 0 and builderToss(state, combo, bestScore, rng, rec) or {}
		if #toss == 0 then
			local _, handResult = scorePlay(state, state.hand, combo, state.ownedPatrons)
			return bestScore, handResult.name
		end
		state.hand = withoutTossed(state.hand, toss)
		for _ = 1, math.min(#toss, #state.deck) do
			state.hand[#state.hand + 1] = table.remove(state.deck)
		end
		state.discardsRemaining = state.discardsRemaining - 1
	end
end

-- Average score of `deals` for the Patrons now seated, and the hand type played most often with its share.
local function chaseValue(state, deals, discards, seed)
	local rng = E.SeededRng.new(seed)
	local rec = { draws = {} }
	local total, played = 0, {}
	for _, deal in ipairs(deals) do
		local score, name = chaseHand(state, deal, discards, rng, rec)
		total = total + score
		played[name] = (played[name] or 0) + 1
	end
	local top, topCount = "High Card", 0
	for _, name in ipairs(E.HandEvaluator.HandOrder) do
		if (played[name] or 0) > topCount then
			top, topCount = name, played[name]
		end
	end
	return total / #deals, top, topCount / #deals
end

-- What each Patron adds to the hand a practiced player ends up playing. The builder bot plays `count` deals with
-- `discards` discards to spend on each, first with the build's table alone, then with each Patron added. Every row sees
-- the same deals and the same deck order, so the difference between two rows is the Patron and the draws it made worth
-- chasing. Unlike Sim.patronTable, a Patron that pays for a Flush or a Straight gets credit for the Flushes and
-- Straights a player would go and make once they own it. Economy Patrons, Patrons that grow over a run and Patrons that
-- need a set-up (a repeat hand, a last hand, a neighbour to copy) read as zero here.
-- `only` limits the rows to a comma-separated list of ids.
function Sim.chaseTable(count, seed, buildName, discards, only)
	seed = seed or 1
	discards = discards or 2
	local build = assert(CHASE_BUILDS[buildName or "open"], "Unknown build: " .. tostring(buildName))
	local state = E.RunState.new({}, E.SeededRng.new(seed))
	local deals = chaseDeals(allCards(state), state.config.handSize, count, E.SeededRng.new(seed))
	state.night, state.tips = build.night, build.tips
	state.handsRemaining = 3
	state.roundScore, state.targetScore = 0, math.huge
	local seated = {}
	for _, id in ipairs(build.patrons) do
		table.insert(state.ownedPatrons, E.Patrons.getById(id))
		seated[id] = true
	end
	for _, name in ipairs(E.HandEvaluator.HandOrder) do
		state.handLevels[name] = build.level
	end
	local wanted = only and ("," .. only .. ",")

	local table0 = state.ownedPatrons
	local base, baseTop, baseShare = chaseValue(state, deals, discards, seed)
	local rows = {}
	for _, patron in ipairs(E.Patrons.Definitions) do
		if patron.effect and not seated[patron.id] and (not wanted or wanted:find("," .. patron.id .. ",", 1, true)) then
			state.ownedPatrons = withPatron(table0, patron)
			local value, top, share = chaseValue(state, deals, discards, seed)
			table.insert(rows, {
				id = patron.id, price = patron.price or 0, value = value, gain = (value - base) / base,
				top = top, share = share,
			})
		end
	end
	state.ownedPatrons = table0
	table.sort(rows, function(a, b)
		if a.gain ~= b.gain then
			return a.gain > b.gain
		end
		return a.id < b.id
	end)
	return rows, base, baseTop, baseShare
end

return Sim
