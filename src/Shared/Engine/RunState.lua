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
local Card = require(script.Parent.Card)
local HandEvaluator = require(script.Parent.HandEvaluator)
local Scoring = require(script.Parent.Scoring)
local Patrons = require(script.Parent.Patrons)
local Themes = require(script.Parent.Themes)
local DeckVariants = require(script.Parent.DeckVariants)
local DifficultyTiers = require(script.Parent.DifficultyTiers)
local BossRounds = require(script.Parent.BossRounds)
local Recipes = require(script.Parent.Recipes)
local HousePasses = require(script.Parent.HousePasses)
local Packs = require(script.Parent.Packs)

local RunState = {}

RunState.DefaultConfig = {
	handSize = 8,
	handsPerRound = 4,
	discardsPerRound = 3,
	roundsPerNight = 3,
	tipsPerRoundWin = 4,
	-- How many Patrons can sit at your table at once. With 22 Patrons in
	-- the pool, "buy every single one" would make the choice of WHICH
	-- Patrons to run meaningless -- a real cap is what makes selling one
	-- to make room for a better fit an actual decision (RunState.sellPatron
	-- already exists for exactly this). A Reserved Special on an owned
	-- Patron (see RunState.patronSlotLimit) is the intended way to grow
	-- past this over the course of a run.
	patronSlotLimit = 5,
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
	config.patronSlotLimit = math.max(1, config.patronSlotLimit)

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
		-- Persistent, run-long card pool: `deck` is the draw pile, `discardPile`
		-- is everything played/discarded so far this run waiting to be
		-- reshuffled back in at the start of the next round. Cards are the
		-- SAME Lua tables all run (never regenerated), so a Garnish/Special/
		-- Stamp a House Recipe adds to a card sticks with it for the run.
		deck = Deck.newStandardDeck(), -- unshuffled; startRound below shuffles+deals
		discardPile = {},
		hand = {},
		handsRemaining = config.handsPerRound,
		discardsRemaining = config.discardsPerRound,
		roundScore = 0,
		targetScore = 0, -- computed by startRound below
		handStats = {}, -- [handName] = times played this run, for the Poker Hands reference screen
		handTypesPlayedThisRound = {}, -- reset each round; used by the "No Repeats" Boss Round
		handLevels = {}, -- [handName] = level, raised by Menu Recipes -- see Scoring.HandLevelGrowth
		houseRecipeInventory = {}, -- array of Recipes.HouseRecipes ids currently owned, unused
		menuRecipeInventory = {},
		secretRecipeInventory = {},
		lastRecipeUsedId = nil, -- for the "Second Helping" House Recipe
		ownedPatronSpecials = {}, -- [patronId] = Card.Specials id (not yet folded into Scoring -- see design doc)
		housePasses = {}, -- [passId] = true, permanent for the rest of the run -- see HousePasses.lua
		pendingPack = nil, -- set by RunState.openPack, cleared by RunState.resolvePack -- see below
		bossModifier = nil,
		roundOver = false,
		runOver = false,
		wonRun = false,
	}
	RunState.startRound(state)
	return state
end

-- Pools whatever's left in the draw pile + discard pile + hand back
-- together, reshuffles, picks this round's Boss modifier (if any), and
-- deals a new starting hand. Cards are never regenerated -- this is what
-- lets a Garnish/Special/Stamp persist across rounds (see RunState.new).
function RunState.startRound(state)
	for _, card in ipairs(state.hand) do
		table.insert(state.deck, card)
	end
	for _, card in ipairs(state.discardPile) do
		table.insert(state.deck, card)
	end
	state.discardPile = {}
	state.hand = {}
	state.deck = Deck.shuffle(state.deck, state.rng)

	local isBoss = state.bossRoundsEnabled and BossRounds.isBossRound(state.round, state.config.roundsPerNight)
	state.bossModifier = isBoss and BossRounds.pick(state.rng) or nil
	local bossModifier = state.bossModifier

	local handSize = state.config.handSize + ((bossModifier and bossModifier.handSizeDelta) or 0)
	handSize = math.max(1, handSize)
	-- Late Kitchen House Pass: +1 Discard every round, permanent for the run.
	local discards = state.config.discardsPerRound + ((bossModifier and bossModifier.discardsDelta) or 0)
		+ (state.housePasses.late_kitchen and 1 or 0)
	discards = math.max(0, discards)

	local handsPerRound = state.config.handsPerRound
	if bossModifier and bossModifier.handsPerRoundOverride then
		handsPerRound = bossModifier.handsPerRoundOverride
	end
	-- Double Shift House Pass: +1 Hand every round, permanent for the run --
	-- applies even on a Boss Round that overrides handsPerRound, same as
	-- everything else here layering on top of the boss's base number.
	handsPerRound = handsPerRound + (state.housePasses.double_shift and 1 or 0)
	handsPerRound = math.max(1, handsPerRound)

	state.hand = Deck.draw(state.deck, handSize)
	state.handsRemaining = handsPerRound
	state.discardsRemaining = discards
	state.roundScore = 0
	state.handTypesPlayedThisRound = {}

	local bossMultiplier = (bossModifier and bossModifier.targetScoreMultiplier) or 1
	local baseTarget = RunState.targetScoreFor(state.night, state.round, state.config.roundsPerNight)
	state.targetScore = math.floor(baseTarget * state.targetMultiplier * bossMultiplier)

	state.roundOver = false
end

-- Applies Golden Garnish (+3 Tips) and Blue Stamp (creates a Menu Recipe
-- for the hand that just won) for every card still held at round-end.
-- `lastHandName` is the poker hand that won the round.
local function settleHeldCardsAtRoundEnd(state, lastHandName)
	for _, card in ipairs(state.hand) do
		local garnish = card.garnish and Card.Garnishes[card.garnish]
		if garnish and garnish.heldEndOfRoundTips then
			state.tips = state.tips + garnish.heldEndOfRoundTips
		end
		local stamp = card.stamp and Card.Stamps[card.stamp]
		if stamp and stamp.createsMenuRecipeIfHeld and lastHandName then
			local recipe = Recipes.randomMenuRecipeForHand(lastHandName)
			if recipe then
				table.insert(state.menuRecipeInventory, recipe.id)
			end
		end
	end
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
	Play 1-5 cards from the hand (by 1-based index into state.hand) -- or
	exactly however many a Boss Round's requiredCardsPerHand demands.
	Returns a result table: { handName, score, chips, mult, roundWon, runOver, wonRun }
]]
function RunState.playHand(state, cardIndices)
	assert(not state.roundOver, "Round is already over -- advance to the next round first")
	local bossModifier = state.bossModifier
	if bossModifier and bossModifier.requiredCardsPerHand then
		assert(#cardIndices == bossModifier.requiredCardsPerHand,
			"This Boss Round requires exactly " .. bossModifier.requiredCardsPerHand .. " cards")
	else
		assert(#cardIndices >= 1 and #cardIndices <= 5, "Play between 1 and 5 cards")
	end
	assert(state.handsRemaining > 0, "No hands remaining this round")

	local playedCards = removeIndicesFromHand(state, cardIndices)
	local handResult = HandEvaluator.evaluate(playedCards)

	-- Was this exact hand type already played earlier this round? Captured
	-- BEFORE marking it played below -- used by the "No Repeats" Boss
	-- Round (blocks scoring) and the "Repeat Customer" Patron (rewards it).
	local alreadyPlayedThisHandTypeThisRound = state.handTypesPlayedThisRound[handResult.name] == true
	local blockedRepeatHand = bossModifier and bossModifier.noRepeatHandTypes
		and alreadyPlayedThisHandTypeThisRound
	state.handTypesPlayedThisRound[handResult.name] = true

	state.handStats[handResult.name] = (state.handStats[handResult.name] or 0) + 1

	-- "Empty Pockets" Boss Round: playing your most-used hand type wipes
	-- your Tips right away (checked using counts AFTER this play).
	if bossModifier and bossModifier.zeroTipsOnMostPlayedHand then
		local maxCount = 0
		for _, count in pairs(state.handStats) do
			maxCount = math.max(maxCount, count)
		end
		if state.handStats[handResult.name] == maxCount then
			state.tips = 0
		end
	end

	state.handsRemaining = state.handsRemaining - 1
	local isLastHand = state.handsRemaining == 0

	local score, chips, mult, extra = 0, 0, 0, { tipsEarned = 0, brokenCards = {} }
	if not blockedRepeatHand then
		score, chips, mult, extra = Scoring.calculate(handResult, state.ownedPatrons, {
			allPlayedCards = playedCards,
			heldCards = state.hand, -- cards left in hand, not played -- Iron Garnish reads this
			handLevels = state.handLevels,
			ownedPatronSpecials = state.ownedPatronSpecials, -- Silver/Gold/Rainbow on a Patron
			debuff = bossModifier and bossModifier.debuff,
			tips = state.tips, -- Tips held BEFORE this hand's reward -- Penny Pincher/Tab Regulars read this
			alreadyPlayedThisHandTypeThisRound = alreadyPlayedThisHandTypeThisRound, -- Repeat Customer reads this
			handsRemaining = state.handsRemaining,
			discardsRemaining = state.discardsRemaining,
			isLastHand = isLastHand,
			night = state.night,
			round = state.round,
		})
		if bossModifier and bossModifier.chipsMultiplier then
			chips = chips * bossModifier.chipsMultiplier
		end
		if bossModifier and bossModifier.multMultiplier then
			mult = mult * bossModifier.multMultiplier
		end
		score = chips * mult
	end

	state.roundScore = state.roundScore + score
	state.tips = state.tips + (extra.tipsEarned or 0)

	-- Brittle Garnish cards that shattered leave the run's card pool for
	-- good -- everything else goes to the discard pile to reshuffle back
	-- in next round (see RunState.startRound).
	local brokenSet = {}
	for _, card in ipairs(extra.brokenCards or {}) do
		brokenSet[card] = true
	end
	for _, card in ipairs(playedCards) do
		if not brokenSet[card] then
			table.insert(state.discardPile, card)
		end
	end

	-- "The Tab" Boss Round: lose Tips for every card played.
	if bossModifier and bossModifier.tipsLostPerCardPlayed then
		state.tips = math.max(0, state.tips - bossModifier.tipsLostPerCardPlayed * #playedCards)
	end

	-- Refill hand from the deck.
	local drawn = Deck.draw(state.deck, #playedCards)
	for _, card in ipairs(drawn) do
		table.insert(state.hand, card)
	end

	-- "Rowdy Crowd" Boss Round: toss out extra random held cards after
	-- every hand played (a penalty, doesn't cost a Discard).
	if bossModifier and bossModifier.forcedRandomDiscardsPerHand and #state.hand > 0 then
		local rng = state.rng or math.random
		for _ = 1, bossModifier.forcedRandomDiscardsPerHand do
			if #state.hand > 0 then
				local i = rng(#state.hand)
				table.insert(state.discardPile, table.remove(state.hand, i))
				local replacement = Deck.draw(state.deck, 1)
				for _, card in ipairs(replacement) do
					table.insert(state.hand, card)
				end
			end
		end
	end

	local roundWon = state.roundScore >= state.targetScore
	if roundWon then
		state.roundOver = true
		settleHeldCardsAtRoundEnd(state, handResult.name)
		for _, patron in ipairs(state.ownedPatrons) do
			if patron.onRoundWin then
				patron.onRoundWin(state)
			end
		end
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
		blockedRepeatHand = blockedRepeatHand or false,
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

	-- Purple Stamp: discarding this card creates a random House Recipe.
	local rng = state.rng or math.random
	for _, card in ipairs(discarded) do
		local stamp = card.stamp and Card.Stamps[card.stamp]
		if stamp and stamp.createsHouseRecipeOnDiscard then
			table.insert(state.houseRecipeInventory, Recipes.randomHouseRecipeId(rng))
		end
	end

	for _, card in ipairs(discarded) do
		table.insert(state.discardPile, card)
	end

	local drawn = Deck.draw(state.deck, #discarded)
	for _, card in ipairs(drawn) do
		table.insert(state.hand, card)
	end

	return { discarded = #discarded, discardsRemaining = state.discardsRemaining }
end

-- How many Patrons can currently sit at the table: the base config value,
-- plus 1 for every owned Patron carrying a Reserved Special (see Card.lua),
-- plus 1 more if the Extra Seating House Pass has been bought this run.
function RunState.patronSlotLimit(state)
	local bonus = 0
	for _, patron in ipairs(state.ownedPatrons) do
		if state.ownedPatronSpecials[patron.id] == "reserved" then
			bonus = bonus + 1
		end
	end
	if state.housePasses.extra_seating then
		bonus = bonus + 1
	end
	return state.config.patronSlotLimit + bonus
end

-- What a Patron actually costs THIS player right now -- the Regulars'
-- Discount House Pass knocks 2 off (never below 1). Shop offer prices are
-- computed with this (server-side, in serializeState) so the client never
-- needs to duplicate the discount math -- it just displays whatever price
-- it was sent.
function RunState.patronPrice(state, patron)
	local price = patron.price
	if state.housePasses.regulars_discount then
		price = math.max(1, price - 2)
	end
	return price
end

-- Same idea for Packs -- Wholesale Pricing knocks 2 off (never below 1).
function RunState.packPrice(state, pack)
	local price = pack.price
	if state.housePasses.wholesale_pricing then
		price = math.max(1, price - 2)
	end
	return price
end

-- The Frequent Visitor Card House Pass knocks 2 off whatever the current
-- reroll cost is (never below 1). `baseCost` is the session's running
-- reroll price (it climbs each reroll within a shop visit -- see the
-- server) -- this just applies the discount on top of it.
function RunState.rerollCost(state, baseCost)
	local cost = baseCost
	if state.housePasses.frequent_visitor then
		cost = cost - 2
	end
	return math.max(1, cost)
end

-- Spend tips on a patron from the shop. Returns true/false, message.
function RunState.buyPatron(state, patronId)
	local patron = Patrons.getById(patronId)
	if not patron then
		return false, "Unknown patron: " .. tostring(patronId)
	end
	if #state.ownedPatrons >= RunState.patronSlotLimit(state) then
		return false, "Your table is full -- sell a Patron to make room"
	end
	local price = RunState.patronPrice(state, patron)
	if state.tips < price then
		return false, "Not enough tips"
	end
	state.tips = state.tips - price
	table.insert(state.ownedPatrons, patron)
	return true, patron.name .. " joins your table."
end

-- Spend tips on a House Pass from the shop's occasional Voucher slot.
-- Permanent for the rest of the run -- see HousePasses.lua for what each
-- one does and which RunState helper reads it.
function RunState.buyHousePass(state, passId)
	local pass = HousePasses.getById(passId)
	if not pass then
		return false, "Unknown House Pass: " .. tostring(passId)
	end
	if state.housePasses[passId] then
		return false, "You already have that House Pass"
	end
	if state.tips < pass.price then
		return false, "Not enough tips"
	end
	state.tips = state.tips - pass.price
	state.housePasses[passId] = true
	if pass.onBuy then
		pass.onBuy(state)
	end
	return true, pass.name .. " is now permanent for this run."
end

local function recipeCatalogForCategory(category)
	if category == "house" then
		return Recipes.HouseRecipes
	elseif category == "menu" then
		return Recipes.MenuRecipes
	elseif category == "secret" then
		return Recipes.SecretRecipes
	end
	return nil
end

local function inventoryForCategory(state, category)
	if category == "house" then
		return state.houseRecipeInventory
	elseif category == "menu" then
		return state.menuRecipeInventory
	elseif category == "secret" then
		return state.secretRecipeInventory
	end
	return nil
end

--[[
	Buys a Pack (deducts its price, respecting Wholesale Pricing) and
	reveals `revealCount` random items from its category. Returns the
	reveal table (also stored as state.pendingPack) on success, or nil,
	message on failure. Nothing is granted yet -- that's resolvePack below,
	once the player picks which of the revealed items to keep.

	Only ONE pack can be open at a time (matches the client only ever
	showing one reveal panel) -- callers should check state.pendingPack is
	nil before calling this, same as the server's BuyPackRemote does.

	`items` are lightweight display copies { id, name, icon, description },
	not the real Patron/Recipe tables, so nothing is granted just by being
	revealed.
]]
function RunState.openPack(state, packId, rng)
	local pack = Packs.getById(packId)
	if not pack then
		return nil, "Unknown pack: " .. tostring(packId)
	end
	local price = RunState.packPrice(state, pack)
	if state.tips < price then
		return nil, "Not enough tips"
	end

	rng = rng or state.rng or math.random
	local items = {}

	if pack.category == "patron" then
		local available = {}
		for _, patron in ipairs(Patrons.Definitions) do
			local owned = false
			for _, o in ipairs(state.ownedPatrons) do
				if o.id == patron.id then
					owned = true
					break
				end
			end
			if not owned then
				table.insert(available, patron)
			end
		end
		for _ = 1, math.min(pack.revealCount, #available) do
			local picked = table.remove(available, rng(#available))
			table.insert(items, { id = picked.id, name = picked.name, icon = picked.icon, description = picked.description })
		end
	else
		local catalog = recipeCatalogForCategory(pack.category)
		for _ = 1, pack.revealCount do
			local picked = catalog[rng(#catalog)]
			table.insert(items, { id = picked.id, name = picked.name, icon = picked.icon, description = picked.description })
		end
	end

	state.tips = state.tips - price
	state.pendingPack = {
		packId = packId,
		category = pack.category,
		pickCount = math.min(pack.pickCount, #items),
		items = items,
	}
	return state.pendingPack
end

--[[
	Resolves the currently open pack (state.pendingPack). `chosenIds` is a
	list of item ids from the reveal -- either exactly `pickCount` of them
	(to keep those), or an empty list to skip the pack entirely (you keep
	nothing, but you don't get your Tips back either -- same as the
	reference game). Returns true/false, message.

	Granting a chosen Patron silently no-ops (instead of failing the whole
	resolve) if the table's already full by the time you confirm -- you
	still keep whatever OTHER picks fit, and you don't lose the pack you
	already paid for over one pick not landing.
]]
function RunState.resolvePack(state, chosenIds)
	local pending = state.pendingPack
	if not pending then
		return false, "No pack is open"
	end
	if type(chosenIds) ~= "table" then
		return false, "Invalid selection"
	end
	if #chosenIds ~= 0 and #chosenIds ~= pending.pickCount then
		return false, "Pick exactly " .. pending.pickCount .. " item(s), or none to skip"
	end

	-- Validate every chosen id against a shrinking copy of the revealed
	-- pool, so you can't pick more copies of an id than were actually
	-- revealed (packs can reveal the same Recipe id twice).
	local pool = {}
	for _, item in ipairs(pending.items) do
		table.insert(pool, item.id)
	end
	for _, chosenId in ipairs(chosenIds) do
		local foundAt = nil
		for i, poolId in ipairs(pool) do
			if poolId == chosenId then
				foundAt = i
				break
			end
		end
		if not foundAt then
			return false, "Invalid selection"
		end
		table.remove(pool, foundAt)
	end

	for _, chosenId in ipairs(chosenIds) do
		if pending.category == "patron" then
			if #state.ownedPatrons < RunState.patronSlotLimit(state) then
				local patron = Patrons.getById(chosenId)
				local alreadyOwned = false
				for _, o in ipairs(state.ownedPatrons) do
					if o.id == chosenId then
						alreadyOwned = true
						break
					end
				end
				if patron and not alreadyOwned then
					table.insert(state.ownedPatrons, patron)
				end
			end
		else
			local inventory = inventoryForCategory(state, pending.category)
			if inventory then
				table.insert(inventory, chosenId)
			end
		end
	end

	state.pendingPack = nil
	return true, "Picked!"
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

--[[
	Recipes (House/Menu/Secret) -- see Recipes.lua. ENGINE-ONLY IN THIS
	PASS: nothing in the shop UI sells these or lets a player pick target
	cards yet, but the buy -> inventory -> use flow below is fully
	implemented and tested, ready for that UI to call into.
]]

local function buyRecipe(state, inventory, catalog, id)
	local recipe
	for _, r in ipairs(catalog) do
		if r.id == id then
			recipe = r
			break
		end
	end
	if not recipe then
		return false, "Unknown recipe: " .. tostring(id)
	end
	if state.tips < recipe.price then
		return false, "Not enough tips"
	end
	state.tips = state.tips - recipe.price
	table.insert(inventory, id)
	return true, recipe.name .. " added to your recipe box."
end

local function useRecipe(state, inventory, catalog, id, opts)
	local index
	for i, ownedId in ipairs(inventory) do
		if ownedId == id then
			index = i
			break
		end
	end
	if not index then
		return false, "You don't have that recipe"
	end
	local recipe
	for _, r in ipairs(catalog) do
		if r.id == id then
			recipe = r
			break
		end
	end
	if not recipe then
		return false, "Unknown recipe: " .. tostring(id)
	end
	opts = opts or {}
	opts.rng = opts.rng or state.rng or math.random
	local ok, message = recipe.apply(state, opts, { Patrons = Patrons, patronSlotLimit = RunState.patronSlotLimit(state) })
	if ok then
		table.remove(inventory, index)
		state.lastRecipeUsedId = id
	end
	return ok, message
end

function RunState.buyHouseRecipe(state, id)
	return buyRecipe(state, state.houseRecipeInventory, Recipes.HouseRecipes, id)
end
function RunState.buyMenuRecipe(state, id)
	return buyRecipe(state, state.menuRecipeInventory, Recipes.MenuRecipes, id)
end
function RunState.buySecretRecipe(state, id)
	return buyRecipe(state, state.secretRecipeInventory, Recipes.SecretRecipes, id)
end

-- opts (optional, only some recipes need these): { cardIndices = {1,2}, suit = "Hearts" }
function RunState.useHouseRecipe(state, id, opts)
	return useRecipe(state, state.houseRecipeInventory, Recipes.HouseRecipes, id, opts)
end
function RunState.useMenuRecipe(state, id, opts)
	return useRecipe(state, state.menuRecipeInventory, Recipes.MenuRecipes, id, opts)
end
function RunState.useSecretRecipe(state, id, opts)
	return useRecipe(state, state.secretRecipeInventory, Recipes.SecretRecipes, id, opts)
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
