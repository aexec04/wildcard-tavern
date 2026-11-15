--[[
	tools/run_fuzz.lua
	Stress test for the run engine. Plays random runs the way the server drives them (same phases, same guards on
	what a player may send) and checks a set of invariants after every action. The balance bots in tools/sim only
	make sensible moves; this makes every legal move, including the silly ones: one-card hands, selling mid-round,
	opening packs with a full table, garbage pack choices, Recipes on odd selections, skips, rule bans, continues.

	After every action: Tips, hands and discards are whole numbers that never go negative; scores are real numbers;
	no pile has a hole; no card sits in two piles; every card is a real card; every seat holds a real Patron; a round
	in progress can be played; everything the server reads for a state push still works. On every second run, luck is
	switched off and each hand's preview (Engine/HandPreview) is compared with what the play then pays.

	Usage, from the repository root:
	    lua tools/run_fuzz.lua [runs] [firstSeed] [maxActions] [easyPercent]
	    lua tools/run_fuzz.lua 2000            about a minute in plain Lua
	easyPercent (default 80) is the share of rounds given a low target, the way Studio's DebugSetTarget does, so runs
	reach every Night, boss and Counter. A finding prints its seed, step and the last eight actions; the same seed
	replays it. Pure Lua, no Roblox APIs. First full run, Nov 13 2026: 12,000 runs, 1.3 million actions, 0 findings.
]]

local RUNS = tonumber(arg and arg[1]) or 200
local FIRST_SEED = tonumber(arg and arg[2]) or 1
local MAX_ACTIONS = tonumber(arg and arg[3]) or 1500
local EASY_PERCENT = tonumber(arg and arg[4]) or 80 -- share of rounds given a low target, so runs go deep

-- ---------------------------------------------------------------- engine loader (same shim as tools/sim/EngineLoader.lua)
if not table.find then
	table.find = function(t, value)
		for i, v in ipairs(t) do
			if v == value then
				return i
			end
		end
		return nil
	end
end
if not Color3 then
	Color3 = { fromRGB = function(r, g, b) return { r = r, g = g, b = b } end }
end
local moduleCache = {}
local function makeProxy(path)
	return setmetatable({ __path = path }, {
		__index = function(_, key)
			if key == "Parent" then
				return makeProxy(path:match("(.*)/[^/]+$") or ".")
			end
			return makeProxy(path .. "/" .. key)
		end,
	})
end
local function loadModule(path)
	if moduleCache[path] ~= nil then
		return moduleCache[path]
	end
	local env = setmetatable({ script = makeProxy(path) }, { __index = _G })
	env.require = function(target)
		return loadModule(target.__path)
	end
	local chunk, err = loadfile(path .. ".lua", "t", env)
	if not chunk then
		error("Could not load " .. path .. ".lua: " .. tostring(err))
	end
	local result = chunk()
	moduleCache[path] = result
	return result
end
local function engine(name)
	return loadModule("src/Shared/Engine/" .. name)
end

local RunState, Shop, Patrons, Recipes = engine("RunState"), engine("Shop"), engine("Patrons"), engine("Recipes")
local Card, SeededRng, RunChoice, Strangers = engine("Card"), engine("SeededRng"), engine("RunChoice"), engine("Strangers")
local HousePasses, Packs = engine("HousePasses"), engine("Packs")
local okPreviewModule, HandPreview = pcall(engine, "HandPreview") -- only in a tree that has the shared preview
if not okPreviewModule then
	HandPreview = nil
end
-- Luck. A preview never rolls it, so for a play to be compared with its preview the play must not roll it either.
-- While `luckOff` is set, the run's rng and math.random both answer with the roll that never hits (the highest).
local luckOff = false
local realRandom = math.random
math.random = function(a, b)
	if not luckOff then
		if a == nil then
			return realRandom()
		elseif b == nil then
			return realRandom(a)
		end
		return realRandom(a, b)
	end
	if a == nil then
		return 0.999
	end
	return b or a
end

local STAKES = 8
local DECKS = { "standard", "steady_hand", "high_roller", "marathon" }
local CHALLENGES = { "pairs_only", "no_discards", "one_seat", "glass_deck", "speed_run", "tight_wallet" }
local CATEGORIES = {
	{ name = "house", catalog = Recipes.HouseRecipes, inventory = "houseRecipeInventory", buy = RunState.buyHouseRecipe, use = RunState.useHouseRecipe },
	{ name = "menu", catalog = Recipes.MenuRecipes, inventory = "menuRecipeInventory", buy = RunState.buyMenuRecipe, use = RunState.useMenuRecipe },
	{ name = "secret", catalog = Recipes.SecretRecipes, inventory = "secretRecipeInventory", buy = RunState.buySecretRecipe, use = RunState.useSecretRecipe },
}

-- The engine's own ways of saying no (asserts in RunState). The server wraps these calls in pcall.
local REFUSALS = {
	"This Boss Round requires exactly", "Play between 1 and 5 cards", "This round needs at least", "No hands remaining this round",
	"Round is already over", "Discard between 1 and 5 cards", "No discards remaining this round", "Can't advance", "Can't continue this run",
	"Can't skip this round",
}

-- ---------------------------------------------------------------- findings
local findings, findingKeys = {}, {}
local stats = { actions = 0, runs = 0, won = 0, refused = 0, byAction = {}, recipesUsed = {}, recipesRefused = {}, nights = {}, bosses = {}, previews = 0 }
local current -- { seed, step, trail }

local function note(kind, detail)
	local key = kind .. "|" .. tostring(detail):gsub("%d+", "#"):sub(1, 160)
	findingKeys[key] = (findingKeys[key] or 0) + 1
	if findingKeys[key] <= 2 then
		local trail = {}
		for i = math.max(1, #current.trail - 7), #current.trail do
			trail[#trail + 1] = current.trail[i]
		end
		findings[#findings + 1] = string.format("[%s] seed %d step %d: %s\n      after: %s", kind, current.seed, current.step, tostring(detail), table.concat(trail, " > "))
	end
end

-- Runs one engine call the way a remote handler would. Returns ok, ...results.
local function act(label, fn, ...)
	current.step = current.step + 1
	current.trail[#current.trail + 1] = label
	stats.actions = stats.actions + 1
	local short = label:match("^(open)_") or label:match("^(use)_") or label:match("^(get)_") or label:match("^(buy)_")
		or label:match("^(pass)_") or label:match("^(pick)_") or label:match("^(event)_") or label:match("^(bargain)_")
		or label:match("^[%a_]+") or label
	stats.byAction[short] = (stats.byAction[short] or 0) + 1
	local results = { pcall(fn, ...) }
	if not results[1] then
		local message = tostring(results[2])
		local refusal = false
		for _, text in ipairs(REFUSALS) do
			if message:find(text, 1, true) then
				refusal = true
				break
			end
		end
		if refusal then
			stats.refused = stats.refused + 1 -- the engine says no by raising; the server catches it
		else
			note("THROW", label .. ": " .. message)
		end
	end
	return (table.unpack or unpack)(results)
end

-- ---------------------------------------------------------------- invariants
local READERS = {
	deckView = RunState.deckView, runCounters = RunState.runCounters, hasLegalPlay = RunState.hasLegalPlay,
	isBossRound = RunState.isBossRound, patronSlotLimit = RunState.patronSlotLimit, recipeSlotLimit = RunState.recipeSlotLimit,
	canSkipRound = RunState.canSkipRound, canContinue = RunState.canContinue,
}
local function isWhole(n)
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge and n == math.floor(n)
end

local function countCards(state)
	return #state.deck + #state.hand + #state.discardPile
end

local function check(state, phase, label)
	if not (isWhole(state.tips) and state.tips >= 0) then
		note("TIPS", label .. " left tips = " .. tostring(state.tips))
	end
	if not (isWhole(state.handsRemaining) and state.handsRemaining >= 0) then
		note("HANDS", label .. " left handsRemaining = " .. tostring(state.handsRemaining))
	end
	if not (isWhole(state.discardsRemaining) and state.discardsRemaining >= 0) then
		note("DISCARDS", label .. " left discardsRemaining = " .. tostring(state.discardsRemaining))
	end
	for _, field in ipairs({ "roundScore", "targetScore" }) do
		local v = state[field]
		if type(v) ~= "number" or v ~= v or v < 0 or v == math.huge then
			note("SCORE", label .. " left " .. field .. " = " .. tostring(v))
		end
	end
	-- cards: every pile is a clean array, no card object sits in two places, every card is a real card
	local seen = {}
	for _, pileName in ipairs({ "deck", "hand", "discardPile" }) do
		local pile = state[pileName]
		local n = 0
		for _ in pairs(pile) do
			n = n + 1
		end
		if n ~= #pile then
			note("HOLE", label .. " left a hole in " .. pileName .. " (" .. #pile .. " by length, " .. n .. " entries)")
		end
		for _, card in ipairs(pile) do
			if seen[card] then
				note("ALIAS", label .. ": one card object is in " .. seen[card] .. " and " .. pileName)
			end
			seen[card] = pileName
			if not (isWhole(card.rank) and card.rank >= 2 and card.rank <= 14) or not table.find(Card.Suits, card.suit) then
				note("CARD", label .. " left a card " .. tostring(card.rank) .. " of " .. tostring(card.suit) .. " in " .. pileName)
			end
		end
	end
	-- seats
	for _, patron in ipairs(state.ownedPatrons) do
		if type(patron) ~= "table" or not Patrons.getById(patron.id) then
			note("SEAT", label .. " left a seat holding " .. tostring(patron and patron.id))
		end
	end
	-- a round in progress must be playable
	if phase == "playing" and not state.roundOver and not state.runOver then
		if state.handsRemaining <= 0 then
			note("STUCK", label .. ": round not over, run not over, and no hands left")
		end
		if #state.hand == 0 then
			note("STUCK", label .. ": round in progress with an empty hand (deck " .. #state.deck .. ", discard pile " .. #state.discardPile .. ")")
		end
	end
	-- what the server reads on every state push must never fail
	for name, fn in pairs(READERS) do
		local ok, err = pcall(fn, state)
		if not ok then
			note("READER", name .. " failed after " .. label .. ": " .. tostring(err))
		end
	end
end

-- ---------------------------------------------------------------- random helpers
local function pickIndices(rng, handSize, minCount, maxCount)
	local count = math.min(handSize, minCount + rng(maxCount - minCount + 1) - 1)
	local pool = {}
	for i = 1, handSize do
		pool[i] = i
	end
	local out = {}
	for _ = 1, count do
		out[#out + 1] = table.remove(pool, rng(#pool))
	end
	return out
end

local function recipeDef(category, id)
	for _, recipe in ipairs(category.catalog) do
		if recipe.id == id then
			return recipe
		end
	end
	return nil
end

-- The server's UseRecipe guard, then the engine call.
local function useRandomRecipe(state, rng)
	local held = {}
	for _, category in ipairs(CATEGORIES) do
		for _, id in ipairs(state[category.inventory]) do
			held[#held + 1] = { category = category, id = id }
		end
	end
	if #held == 0 then
		return
	end
	local pick = held[rng(#held)]
	local recipe = recipeDef(pick.category, pick.id)
	if not recipe then
		note("RECIPE", "held recipe " .. tostring(pick.id) .. " is not in the " .. pick.category.name .. " catalog")
		return
	end
	local opts = {}
	if recipe.cardCount then
		if #state.hand < recipe.cardCount.min then
			return -- the server refuses a selection that is too small
		end
		opts.cardIndices = pickIndices(rng, #state.hand, recipe.cardCount.min, recipe.cardCount.max)
	end
	if recipe.needsSuit then
		opts.suit = (rng(8) == 1) and "Bananas" or Card.Suits[rng(4)]
	end
	local before = countCards(state)
	local ok, used, message = act("use_" .. pick.id, pick.category.use, state, pick.id, opts)
	if ok then
		local bucket = used and stats.recipesUsed or stats.recipesRefused
		bucket[pick.id] = (bucket[pick.id] or 0) + 1
		if used and opts.suit == "Bananas" then
			note("SUIT", pick.id .. " accepted the suit Bananas")
		end
		if not used and countCards(state) ~= before then
			note("REFUSED_BUT_CHANGED", pick.id .. " said no (" .. tostring(message) .. ") and still changed the card count")
		end
	end
end

local function resolvePendingPack(state, rng)
	local pending = state.pendingPack
	if not pending then
		return
	end
	for attempt = 1, 6 do
		if not state.pendingPack then
			return
		end
		local chosen = {}
		local roll = rng(10)
		if roll <= 5 then -- a proper pick
			local pool = {}
			for _, item in ipairs(pending.items or {}) do
				pool[#pool + 1] = item.id
			end
			for _ = 1, math.min(pending.pickCount or 1, #pool) do
				chosen[#chosen + 1] = table.remove(pool, rng(#pool))
			end
		elseif roll <= 7 then -- take nothing
			chosen = {}
		elseif roll == 8 then -- the same item twice
			local first = pending.items and pending.items[1]
			chosen = first and { first.id, first.id } or {}
		elseif roll == 9 then -- something that is not in the pack
			chosen = { "the_regular", "not_a_real_id" }
		else -- too many
			for _, item in ipairs(pending.items or {}) do
				chosen[#chosen + 1] = item.id
			end
		end
		local ok, resolved, message = act("resolve_pack(" .. #chosen .. ")", RunState.resolvePack, state, chosen)
		if ok and resolved == false and tostring(message):find("Make room", 1, true) and #state.ownedPatrons > 0 and rng(2) == 1 then
			act("sell_for_room", RunState.sellPatron, state, state.ownedPatrons[rng(#state.ownedPatrons)].id)
		end
		check(state, "shop", "resolve_pack")
		if attempt == 6 and state.pendingPack then
			act("resolve_pack(skip)", RunState.resolvePack, state, {})
			if state.pendingPack then
				note("PACK", "an open pack could not be closed by taking nothing")
				state.pendingPack = nil
			end
		end
	end
end

-- ---------------------------------------------------------------- one run
local function runOne(seed)
	current = { seed = seed, step = 0, trail = {} }
	math.randomseed(seed)
	local seeded = SeededRng.new(seed)
	local function rng(n) -- the run's rng, with the luck switch
		if luckOff then
			return n
		end
		return seeded(n)
	end
	local comparePreview = HandPreview ~= nil and seed % 2 == 0
	local dice = SeededRng.new((seed * 7919 + 17) % 4294967296) -- the fuzzer's own dice, apart from the run's
	local options = { stakeId = dice(STAKES), deckVariantId = DECKS[dice(#DECKS)] }
	local flavour = dice(10)
	if flavour == 1 then
		options.mode = "quick"
	elseif flavour == 2 then
		options.challengeId = CHALLENGES[dice(#CHALLENGES)]
	elseif flavour == 3 then
		options.ruleBans = true
	elseif flavour == 4 then
		options.endlessRules = true
	elseif flavour == 5 then
		options.rush = true
	end
	local madeOk, state = act("new", RunState.new, options, rng)
	if not madeOk or type(state) ~= "table" then
		return
	end
	state.strangerSeed = seed * 31 + 7 -- the server sets one when the first Counter opens; it decides the Stranger's visits
	check(state, "roundSelect", "new")

	-- start-of-run draft, as a normal run gets
	if dice(2) == 1 then
		local ok, choice = act("start_draft", RunChoice.startDraft, state, true)
		local guard = 0
		while ok and choice and guard < 6 do
			guard = guard + 1
			local option = choice.options[dice(#choice.options)]
			local picked, _, _, nextChoice = act("pick_" .. tostring(option.id), RunChoice.pick, state, choice, option.id)
			choice = picked and nextChoice or nil
			check(state, "roundSelect", "draft pick")
		end
	end

	local phase = "playing"
	local continued = false
	local easyRound = nil -- decided once per round
	while current.step < MAX_ACTIONS do
		if state.runOver then
			if not continued and dice(3) == 1 and RunState.canContinue(state) then
				continued = true
				act("continue", RunState.useContinue, state)
				check(state, "playing", "continue")
				if state.runOver then
					note("CONTINUE", "useContinue returned and the run is still over")
					break
				end
				phase = "playing"
			else
				break
			end
		elseif phase == "playing" and not state.roundOver then
			if easyRound == nil then
				-- Most rounds get a low target (what Studio's DebugSetTarget does), so runs reach every Night, boss and Counter.
				easyRound = dice(100) <= EASY_PERCENT
				if easyRound then
					state.targetScore = math.max(1, math.floor(state.targetScore / (dice(2) == 1 and 1000 or 4)))
				end
				if state.bossModifier then
					stats.bosses[state.bossModifier.id] = (stats.bosses[state.bossModifier.id] or 0) + 1
				end
			end
			local roll = dice(100)
			if roll <= 6 and #state.ownedPatrons > 0 then
				act("sell_midround", RunState.sellPatron, state, state.ownedPatrons[dice(#state.ownedPatrons)].id)
			elseif roll <= 9 then
				act("rule_ban", RunState.useRuleBan, state, phase)
			elseif roll <= 40 and state.discardsRemaining > 0 and #state.hand > 0 then
				local before = countCards(state)
				local toss = pickIndices(dice, #state.hand, 1, 5)
				act("discard(" .. #toss .. ")", RunState.discard, state, toss)
				if countCards(state) ~= before then
					note("COUNT", "a discard changed the number of cards from " .. before .. " to " .. countCards(state))
				end
			elseif #state.hand > 0 then
				local play = pickIndices(dice, #state.hand, 1, 5)
				local preview, previewOk
				if comparePreview then
					previewOk, preview = pcall(HandPreview.compute, state, play)
					if not previewOk then
						note("PREVIEW_THROW", tostring(preview))
						preview = nil
					end
				end
				local tipsBefore, bossId = state.tips, state.bossModifier and state.bossModifier.id
				luckOff = comparePreview
				local ok, result = act("play(" .. #play .. ")", RunState.playHand, state, play)
				luckOff = false
				if ok and type(result) == "table" and comparePreview and previewOk then
					stats.previews = stats.previews + 1
					if preview == nil then
						note("PREVIEW", "no preview for a hand the engine played (" .. tostring(result.handName) .. ")")
					elseif preview.name ~= result.handName or math.abs((preview.score or -1) - (result.score or -2)) > 1e-6 then
						note("PREVIEW", string.format("preview said %s %s, the play paid %s %s (boss %s, tips %s, %d Patrons, bargains %d, challenge %s, stake %s)",
							tostring(preview.name), tostring(preview.score), tostring(result.handName), tostring(result.score), tostring(bossId), tostring(tipsBefore),
							#state.ownedPatrons, #(state.bargains or {}), tostring(state.challenge and state.challenge.id), tostring(state.stake)))
					end
				end
				if ok and type(result) == "table" then
					if type(result.score) ~= "number" or result.score ~= result.score or result.score < 0 then
						note("SCORE", "playHand reported score " .. tostring(result.score))
					end
					if result.roundWon ~= (state.roundOver and not state.runOver) and not result.runOver then
						note("RESULT", "roundWon " .. tostring(result.roundWon) .. " but roundOver " .. tostring(state.roundOver))
					end
				end
			else
				note("STUCK", "playing phase with nothing to play or discard")
				break
			end
			check(state, phase, "round action")
		elseif phase == "playing" and state.roundOver then
			-- the round is won: the Counter opens (Boss Rush goes straight to the next boss)
			if state.wonRun and not state.endlessRulesEnabled and dice(3) ~= 1 then
				break
			end
			if state.rush then
				if not act("advance_rush", RunState.advanceToNextRound, state) then
					break
				end
				state.pendingPack = nil
				easyRound = nil
				check(state, "roundSelect", "advance_rush")
			else
			phase = "shop"
			local ok, offers = act("roll_offers", Shop.rollOffers, state)
			offers = ok and offers or { patrons = {}, packs = {} }
			local rerollBase = Shop.REROLL_BASE_COST or 2
			for _ = 1, dice(10) do
				local roll = dice(100)
				if roll <= 22 and #(offers.patrons or {}) > 0 then
					local index = dice(#offers.patrons)
					local okBuy, bought = act("buy_" .. offers.patrons[index].id, RunState.buyPatron, state, offers.patrons[index].id)
					if okBuy and bought then
						table.remove(offers.patrons, index)
					end
				elseif roll <= 30 and offers.voucher then
					local okBuy, bought = act("pass_" .. offers.voucher.id, RunState.buyHousePass, state, offers.voucher.id)
					if okBuy and bought then
						offers.voucher = nil
					end
				elseif roll <= 55 and #(offers.packs or {}) > 0 then
					local index = dice(#offers.packs)
					local okOpen, reveal = act("open_" .. offers.packs[index].id, RunState.openPack, state, offers.packs[index].id)
					if okOpen and reveal then
						table.remove(offers.packs, index)
						check(state, "shop", "open pack")
						if dice(6) == 1 and #state.ownedPatrons > 0 then -- selling while a pack is open is allowed
							act("sell_packopen", RunState.sellPatron, state, state.ownedPatrons[dice(#state.ownedPatrons)].id)
						end
						resolvePendingPack(state, dice)
					end
				elseif roll <= 63 then
					-- a Recipe straight from a catalog (how packs and events hand them out): pay for it, as buy would
					local category = CATEGORIES[dice(#CATEGORIES)]
					local recipe = category.catalog[dice(#category.catalog)]
					state.tips = state.tips + (recipe.price or 0)
					act("get_" .. recipe.id, category.buy, state, recipe.id)
				elseif roll <= 82 then
					useRandomRecipe(state, dice)
				elseif roll <= 88 and #state.ownedPatrons > 0 then
					act("sell_shop", RunState.sellPatron, state, state.ownedPatrons[dice(#state.ownedPatrons)].id)
				elseif roll <= 92 then
					act("rule_ban", RunState.useRuleBan, state, phase)
				elseif roll <= 96 then
					local okVisit, offer = act("stranger", Strangers.rollVisit, state, {})
					if okVisit and offer and dice(2) == 1 then
						act("bargain_" .. tostring(offer.id), Strangers.accept, state, offer.id)
					end
				else
					local okCost, cost = act("reroll_cost", RunState.rerollCost, state, rerollBase)
					if okCost and isWhole(cost) and cost >= 1 and state.tips >= cost then
						state.tips = state.tips - cost
						rerollBase = rerollBase + (Shop.REROLL_COST_STEP or 1)
						local okRoll, fresh = act("reroll", Shop.rollOffers, state)
						if okRoll and fresh then
							offers = fresh
						end
					elseif okCost and not (isWhole(cost) and cost >= 1) then
						note("REROLL", "reroll cost came out as " .. tostring(cost))
					end
				end
				check(state, "shop", "shop action")
			end
			-- leave the Counter
			local before = countCards(state)
			local okAdvance = act("advance", RunState.advanceToNextRound, state)
			if not okAdvance then
				break
			end
			if countCards(state) ~= before then
				note("COUNT", "moving to the next round changed the number of cards from " .. before .. " to " .. countCards(state))
			end
			phase = "roundSelect"
			easyRound = nil
			check(state, phase, "advance")
			-- between Nights: an event card, then maybe skip the round
			if state.round == 1 and state.night >= 2 then
				local okEvent, choice = act("roll_event", RunChoice.rollEvent, state, true)
				local guard = 0
				while okEvent and choice and guard < 4 do
					guard = guard + 1
					local option = choice.options[dice(#choice.options)]
					local picked, _, _, nextChoice = act("event_" .. tostring(choice.eventId) .. "_" .. tostring(option.id), RunChoice.pick, state, choice, option.id)
					choice = picked and nextChoice or nil
					check(state, phase, "event pick")
				end
			end
			if dice(8) == 1 then
				local okCan, can = act("can_skip", RunState.canSkipRound, state)
				if okCan and can then
					act("skip", RunState.skipRound, state)
					check(state, phase, "skip")
				end
			end
			phase = "playing" -- a skipped round is already won, so the loop goes straight to the Counter again
			end
		else
			note("PHASE", "unexpected phase " .. tostring(phase))
			break
		end
	end
	if current.step >= MAX_ACTIONS then
		note("LONG", "run did not end within " .. MAX_ACTIONS .. " actions (night " .. tostring(state.night) .. ")")
	end
	stats.runs = stats.runs + 1
	stats.won = stats.won + (state.wonRun and 1 or 0)
	stats.nights[state.night] = (stats.nights[state.night] or 0) + 1
end

for seed = FIRST_SEED, FIRST_SEED + RUNS - 1 do
	local ok, err = pcall(runOne, seed)
	if not ok then
		findings[#findings + 1] = "[FUZZER] seed " .. seed .. ": the stress test itself failed: " .. tostring(err)
	end
end

print(string.format("%d runs, %d actions, %d runs won, %d moves refused by the engine", stats.runs, stats.actions, stats.won, stats.refused))
local bossCount = 0
for _ in pairs(stats.bosses) do
	bossCount = bossCount + 1
end
print("Boss Rounds met: " .. bossCount .. ", plays compared with their preview: " .. stats.previews)
local nights = {}
for night = 1, 12 do
	if stats.nights[night] then
		nights[#nights + 1] = "N" .. night .. " " .. stats.nights[night]
	end
end
print("ended on: " .. table.concat(nights, ", "))
local actions = {}
for name, count in pairs(stats.byAction) do
	actions[#actions + 1] = { name, count }
end
table.sort(actions, function(a, b) return a[2] > b[2] end)
local line = {}
for i = 1, #actions do
	line[#line + 1] = actions[i][1] .. " " .. actions[i][2]
end
print("actions: " .. table.concat(line, ", "))
local used, total, never = 0, 0, {}
for _, category in ipairs(CATEGORIES) do
	for _, recipe in ipairs(category.catalog) do
		total = total + 1
		if stats.recipesUsed[recipe.id] then
			used = used + 1
		else
			never[#never + 1] = recipe.id .. (stats.recipesRefused[recipe.id] and "(refused " .. stats.recipesRefused[recipe.id] .. ")" or "")
		end
	end
end
print(string.format("Recipes that took effect at least once: %d of %d%s", used, total, #never > 0 and ("; never: " .. table.concat(never, ", ")) or ""))
local kinds = {}
for key, count in pairs(findingKeys) do
	kinds[#kinds + 1] = string.format("%5d x %s", count, key)
end
table.sort(kinds, function(a, b) return a > b end)
print(#kinds .. " distinct findings:")
for _, entry in ipairs(kinds) do
	print("  " .. entry)
end
if #findings > 0 then
	print("--- first examples")
	for i = 1, math.min(#findings, 40) do
		print(findings[i])
	end
	os.exit(1)
end
