--[[
	Quests.lua
	Three daily quests per UTC day, picked deterministically from a registry (the same three for every player on a
	given day, so friends can compare). Pure Lua, no Roblox APIs. Server authoritative: the server turns run
	counters into progress deltas (see Server syncProfileFromSession) and calls Quests.apply.

	A quest reads one run counter (the `counter` field):
		hands     hands played                       state.handsPlayedTotal
		pairs     Pair hands played                  state.handStats["Pair"]
		discards  discards used                      state.discardsUsedTotal
		flushWins rounds cleared with a Flush        state.flushClears
		packs     Packs bought                       state.packsBought
		bosses    Boss Rounds cleared                state.bossesCleared
		straights / fullHouses / trips  hands of that type          state.handStats
		bigHands  hands scoring 500+                 state.bigHands
		richClears / quickClears  rounds cleared with 3+ Tips / in 2 or fewer hands
		housePasses / recipes / cardsDiscarded  bought / used / cards thrown away
		night     highest Night of the run           state.night
		rounds    rounds cleared                     state.roundsCleared
		boonsPicked  Night boons picked              state.boonsPicked
		deckRounds / deckBosses  rounds / Boss Rounds cleared with the Lucky or Slim Deck (state.startingDeckId is not classic)
		marksBought  Marks bought for a card         state.marksBought
		slimRounds   rounds cleared with the Slim Deck (state.startingDeckId is "slim")
	Daily, Weekly and Seed runs count too.

	Profile: quests = { day, ids = { questId x3 }, progress = { [questId] = n }, done = { [questId] = true } },
	questsDone (all-time count, read by Engine/Unlocks), questSnapshot is kept by the server per session, not saved.
]]

local TavernRank = require(script.Parent.TavernRank)
local LiveEvents = require(script.Parent.LiveEvents) -- a double XP weekend also doubles quest XP

local Quests = {}

Quests.PER_DAY = 3

-- Quest card text box (Client/QuestsPanel): the card is 520 wide, the words start 86 px in and stop 12 px before the 104 px reward plate
-- that sits 12 px from the right edge. fitSize gives the largest size (12 at the least) at which one line fits that width.
Quests.CARD_W, Quests.TEXT_X, Quests.REWARD_W, Quests.REWARD_RIGHT, Quests.TEXT_GAP = 520, 86, 104, 12, 12
Quests.TEXT_W = Quests.CARD_W - Quests.TEXT_X - (Quests.REWARD_W + Quests.REWARD_RIGHT + Quests.TEXT_GAP)
function Quests.fitSize(text, maxSize, w)
	local TextFit = require(script.Parent.TextFit)
	for s = maxSize, 12, -1 do
		if TextFit.width(text, s) <= (w or Quests.TEXT_W) then return s end
	end
	return 12
end
Quests.MAX_PENDING_TIPS = TavernRank.MAX_PENDING_TIPS

Quests.Definitions = {
	{ id = "pairs_3", name = "Pair Up", icon = "👯", desc = "Play 3 Pair hands.", counter = "pairs", goal = 3, xp = 40, tips = 2 },
	{ id = "flush_clear", name = "Flush Finish", icon = "🌊", desc = "Clear a round with a Flush.", counter = "flushWins", goal = 1, xp = 60, tips = 3 },
	{ id = "buy_pack", name = "Pack Shopper", icon = "🎁", desc = "Buy a Pack.", counter = "packs", goal = 1, xp = 40, tips = 2 },
	{ id = "discard_5", name = "Fresh Draw", icon = "♻️", desc = "Use 5 discards.", counter = "discards", goal = 5, xp = 40, tips = 2 },
	{ id = "boss_win", name = "Boss Beater", icon = "🥊", desc = "Win a Boss Round.", counter = "bosses", goal = 1, xp = 80, tips = 4 },
	{ id = "hands_10", name = "Busy Hands", icon = "🃏", desc = "Play 10 hands.", counter = "hands", goal = 10, xp = 50, tips = 2 },
	-- Second batch (every id has a quest_subjects prompt in tools/patron_art/prompts.json, emoji until art is recorded).
	{ id = "straight_play", name = "Straight Shooter", icon = "📏", desc = "Play a Straight.", counter = "straights", goal = 1, xp = 50, tips = 2 },
	{ id = "full_house_play", name = "Full House Party", icon = "🏠", desc = "Play a Full House.", counter = "fullHouses", goal = 1, xp = 60, tips = 3 },
	{ id = "trips_play", name = "Triple Threat", icon = "3️⃣", desc = "Play 2 Three of a Kind hands.", counter = "trips", goal = 2, xp = 50, tips = 2 },
	{ id = "big_swing", name = "Big Swing", icon = "💥", desc = "Score 500 in one hand.", counter = "bigHands", goal = 1, xp = 70, tips = 3 },
	{ id = "tips_left", name = "Coin Purse", icon = "👛", desc = "Finish a round with 3 Tips left.", counter = "richClears", goal = 1, xp = 50, tips = 2 },
	{ id = "quick_win", name = "Swift Win", icon = "⚡", desc = "Win a round using 2 or fewer hands.", counter = "quickClears", goal = 1, xp = 60, tips = 3 },
	{ id = "buy_pass", name = "Pass Collector", icon = "🎟️", desc = "Buy a House Pass.", counter = "housePasses", goal = 1, xp = 50, tips = 2 },
	{ id = "use_recipe", name = "Home Cook", icon = "🍲", desc = "Use a Recipe.", counter = "recipes", goal = 1, xp = 40, tips = 2 },
	{ id = "discard_cards_10", name = "Clean Sweep", icon = "🧹", desc = "Discard 10 cards.", counter = "cardsDiscarded", goal = 10, xp = 40, tips = 2 },
	{ id = "boss_streak", name = "Giant Slayer", icon = "🗡️", desc = "Clear 2 Boss Rounds.", counter = "bosses", goal = 2, xp = 120, tips = 5 },
	{ id = "hands_15", name = "Marathon Hands", icon = "🏃", desc = "Play 15 hands.", counter = "hands", goal = 15, xp = 70, tips = 3 },
	{ id = "reach_night_3", name = "Third Night", icon = "🌙", desc = "Reach Night 3.", counter = "night", goal = 3, xp = 80, tips = 3 },
	{ id = "rounds_5", name = "Round Runner", icon = "🔔", desc = "Clear 5 rounds.", counter = "rounds", goal = 5, xp = 60, tips = 3 },
	{ id = "pairs_8", name = "Pair Parade", icon = "🎎", desc = "Play 8 Pair hands.", counter = "pairs", goal = 8, xp = 60, tips = 3 },
	-- Third batch: a week needs 21 different quests (3 a day, none repeated), so the pool holds 24.
	{ id = "discard_8", name = "Fresh Start", icon = "🔄", desc = "Use 8 discards.", counter = "discards", goal = 8, xp = 60, tips = 3 },
	{ id = "straight_2", name = "Straight Ahead", icon = "🛤️", desc = "Play 2 Straights.", counter = "straights", goal = 2, xp = 70, tips = 3 },
	{ id = "packs_2", name = "Pack Parade", icon = "🎀", desc = "Buy 2 Packs.", counter = "packs", goal = 2, xp = 60, tips = 3 },
	{ id = "rounds_3", name = "Warm Up", icon = "🔥", desc = "Clear 3 rounds.", counter = "rounds", goal = 3, xp = 40, tips = 2 },
	-- Night boons and Starting Decks (a deck quest is swapped for another quest while the Lucky and Slim decks are still locked, see idsFor)
	{ id = "boon_1", name = "Boon Taker", icon = "✨", desc = "Pick a Night boon.", counter = "boonsPicked", goal = 1, xp = 40, tips = 2 },
	{ id = "boon_3", name = "Boon Collector", icon = "🎁", desc = "Pick 3 Night boons.", counter = "boonsPicked", goal = 3, xp = 70, tips = 3 },
	{ id = "deck_rounds", name = "Deck Explorer", icon = "🃏", desc = "Clear 3 rounds with the Lucky or Slim Deck.", counter = "deckRounds", goal = 3, xp = 70, tips = 3 },
	{ id = "deck_boss", name = "Deck Boss Beater", icon = "🏆", desc = "Win a Boss Round with the Lucky or Slim Deck.", counter = "deckBosses", goal = 1, xp = 80, tips = 4 },
	-- Marks (bought at the Counter from Night 2, Tips only) and the Slim Deck (open at Night 5)
	{ id = "mark_1", name = "Mark Maker", icon = "🔖", desc = "Buy a Mark for one of your cards.", counter = "marksBought", goal = 1, xp = 50, tips = 2 },
	{ id = "mark_2", name = "Mark Collector", icon = "🏷️", desc = "Buy 2 Marks for your cards.", counter = "marksBought", goal = 2, xp = 70, tips = 3 },
	{ id = "slim_rounds", name = "Slim Sprint", icon = "✂️", desc = "Clear 3 rounds with the Slim Deck.", counter = "slimRounds", goal = 3, xp = 80, tips = 4 },
}
Quests.DECK_COUNTERS = { deckRounds = true, deckBosses = true, slimRounds = true } -- these need the Lucky or Slim deck, which open at Night 3 and 5
Quests.SLIM_ONLY = { slimRounds = true } -- this one needs the Slim deck itself

function Quests.getById(id)
	for _, q in ipairs(Quests.Definitions) do
		if q.id == id then
			return q
		end
	end
	return nil
end

-- The quest plan of one week (UTC day // 7): a seeded shuffle of the pool dealt out three a day, so no quest shows twice in a
-- week and no day has two quests on the same counter (Busy Hands + Marathon Hands). Returns { [0..6] = { id, id, id } }.
function Quests.weekPlan(week)
	-- Park-Miller generator: every product stays below 2^53, so Lua 5.3 and Luau give the same numbers.
	local seed = (math.floor(week) * 40503 + 7919) % 2147483647
	if seed == 0 then seed = 1 end
	local function nextInt(n)
		seed = (seed * 48271) % 2147483647
		return (math.floor(seed / 256) % n) + 1
	end
	local pool = {}
	for _, q in ipairs(Quests.Definitions) do
		pool[#pool + 1] = q.id
	end
	local order = {}
	while #pool > 0 do
		order[#order + 1] = table.remove(pool, nextInt(#pool))
	end
	local plan, used = {}, {}
	for d = 0, 6 do
		local ids, counters = {}, {}
		for pass = 1, 2 do -- pass 1 honours the counter rule; pass 2 only fills a gap if the pool ran dry
			for _, id in ipairs(order) do
				if #ids >= Quests.PER_DAY then break end
				local counter = Quests.getById(id).counter
				if not used[id] and (pass == 2 or not counters[counter]) then
					ids[#ids + 1] = id
					used[id] = true
					counters[counter] = true
				end
			end
		end
		plan[d] = ids
	end
	return plan
end

-- The three quest ids of a UTC day number, the same everywhere (see weekPlan).
function Quests.rollFor(day)
	day = math.floor(day)
	local ids = Quests.weekPlan(day // 7)[day % 7]
	local out = {}
	for i, id in ipairs(ids) do out[i] = id end
	return out
end

-- The three quest ids a profile sees on a day: the shared roll, except that while no Starting Deck besides Classic is open the deck quests
-- are swapped for the first spare quest (not in this week's plan, not on a counter already in the day), so nothing offered is impossible.
function Quests.idsFor(profile, day)
	local ids = Quests.rollFor(day)
	if profile == nil then return ids end
	local StartingDecks = require(script.Parent.StartingDecks)
	local luckyOpen, slimOpen = StartingDecks.isUnlocked(profile, "lucky"), StartingDecks.isUnlocked(profile, "slim")
	local function locked(def) -- a deck quest whose deck is still shut
		if not def or not Quests.DECK_COUNTERS[def.counter] then return false end
		return not luckyOpen or (Quests.SLIM_ONLY[def.counter] == true and not slimOpen)
	end
	local any = false
	for _, id in ipairs(ids) do
		if locked(Quests.getById(id)) then any = true end
	end
	if not any then return ids end
	local inWeek, counters = {}, {}
	for _, list in pairs(Quests.weekPlan(math.floor(day) // 7)) do
		for _, id in ipairs(list) do inWeek[id] = true end
	end
	for _, id in ipairs(ids) do
		local def = Quests.getById(id)
		if def and not locked(def) then counters[def.counter] = true end
	end
	for i, id in ipairs(ids) do
		if locked(Quests.getById(id)) then
			for _, q in ipairs(Quests.Definitions) do
				if not inWeek[q.id] and not Quests.DECK_COUNTERS[q.counter] and not counters[q.counter] then
					ids[i] = q.id
					inWeek[q.id] = true
					counters[q.counter] = true
					break
				end
			end
		end
	end
	return ids
end

local function freshState(day, profile)
	return { day = day, ids = Quests.idsFor(profile, day), progress = {}, done = {} }
end

-- Makes sure profile.quests is today's. Returns true when it was rolled (new day).
function Quests.ensureDay(profile, day)
	local q = profile.quests
	if type(q) == "table" and q.day == day and type(q.ids) == "table" and #q.ids == Quests.PER_DAY then
		q.progress = q.progress or {}
		q.done = q.done or {}
		return false
	end
	profile.quests = freshState(day, profile)
	return true
end

-- Adds counter deltas ({ pairs = 2, hands = 5, ... }, whole numbers, never negative) to today's quests.
-- Completed quests pay their XP (TavernRank.addXp) and bank their Tips for the next run.
-- Returns the completed quests (definitions) and the rank ups / rewards caused by their XP.
function Quests.apply(profile, day, deltas)
	Quests.ensureDay(profile, day)
	local q = profile.quests
	local completed, rankUps, granted = {}, {}, {}
	for _, id in ipairs(q.ids) do
		local def = Quests.getById(id)
		if def and not q.done[id] then
			local add = math.floor(tonumber(deltas[def.counter]) or 0)
			if add > 0 then
				q.progress[id] = math.min(def.goal, (q.progress[id] or 0) + add)
			end
			if (q.progress[id] or 0) >= def.goal then
				q.done[id] = true
				profile.questsDone = (profile.questsDone or 0) + 1
				profile.pendingStartTips = math.min(Quests.MAX_PENDING_TIPS, (profile.pendingStartTips or 0) + def.tips)
				local _, ups, rewards = TavernRank.addXp(profile, math.floor(def.xp * LiveEvents.xpMultiplier(day)))
				for _, r in ipairs(ups) do rankUps[#rankUps + 1] = r end
				for _, r in ipairs(rewards) do granted[#granted + 1] = r end
				completed[#completed + 1] = def
			end
		end
	end
	return completed, rankUps, granted
end

-- "2 of 3" while open, "Done" once claimed (rewards are paid the moment a quest completes).
function Quests.progressText(row)
	if row.done then
		return "Done"
	end
	return string.format("%d of %d", math.floor(row.progress or 0), math.floor(row.goal or 0))
end

-- "+40 XP, +2 Tips" (Tips are banked for the next run).
function Quests.rewardText(def)
	return string.format("+%d XP, +%d Tips", math.floor(def.xp), math.floor(def.tips))
end

-- What the client draws.
function Quests.view(profile, day, secondsLeft)
	Quests.ensureDay(profile, day)
	local q = profile.quests
	local rows = {}
	for _, id in ipairs(q.ids) do
		local def = Quests.getById(id)
		if def then
			rows[#rows + 1] = {
				id = id, name = def.name, icon = def.icon, desc = def.desc,
				progress = math.min(def.goal, q.progress[id] or 0), goal = def.goal,
				done = q.done[id] == true, xp = def.xp, tips = def.tips,
			}
		end
	end
	return { day = day, quests = rows, secondsLeft = secondsLeft, doneCount = (function()
		local n = 0
		for _, r in ipairs(rows) do if r.done then n = n + 1 end end
		return n
	end)() }
end

-- Turns run counters into deltas against a per-session snapshot (monotonic: a counter that drops, e.g. after
-- One More Round restores the round start, never counts twice). `snapshot` is updated in place.
function Quests.deltas(snapshot, counters)
	local out = {}
	for key, now in pairs(counters) do
		local before = snapshot[key] or 0
		if now > before then
			out[key] = now - before
			snapshot[key] = now
		end
	end
	return out
end

-- The counters of a RunState.
function Quests.countersOf(state)
	local stats = state.handStats or {}
	return {
		hands = state.handsPlayedTotal or 0,
		pairs = stats["Pair"] or 0,
		discards = state.discardsUsedTotal or 0,
		flushWins = state.flushClears or 0,
		packs = state.packsBought or 0,
		bosses = state.bossesCleared or 0,
		straights = stats["Straight"] or 0,
		fullHouses = stats["Full House"] or 0,
		trips = stats["Three of a Kind"] or 0,
		bigHands = state.bigHands or 0,
		richClears = state.richClears or 0,
		quickClears = state.quickClears or 0,
		housePasses = state.housePassesBought or 0,
		recipes = state.recipesUsed or 0,
		cardsDiscarded = state.cardsDiscarded or 0,
		night = state.night or 0, -- highest Night reached; deltas add up to the Night number
		rounds = state.roundsCleared or 0,
		boonsPicked = state.boonsPicked or 0,
		deckRounds = (state.startingDeckId and state.startingDeckId ~= "classic") and (state.roundsCleared or 0) or 0,
		deckBosses = (state.startingDeckId and state.startingDeckId ~= "classic") and (state.bossesCleared or 0) or 0,
		marksBought = state.marksBought or 0,
		slimRounds = state.startingDeckId == "slim" and (state.roundsCleared or 0) or 0,
	}
end

return Quests
