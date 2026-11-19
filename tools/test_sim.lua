--[[
	test_sim.lua
	Sanity checks for the balance simulator itself. Usage:
		lua5.3 tools/test_sim.lua
]]

local toolsDir = arg[0]:match("(.*)/test_sim%.lua$") or "."
package.path = toolsDir .. "/sim/?.lua;" .. package.path

local EngineLoader = require("EngineLoader")
local Sim = require("Sim")
local Report = require("Report")

local engine = EngineLoader.load(toolsDir .. "/../src/Shared")
Sim.init(engine)

local function config(overrides)
	local cfg = { bot = "decent", maxNight = 10, bank = 0, difficulty = "standard", deck = "standard" }
	for k, v in pairs(overrides or {}) do
		cfg[k] = v
	end
	cfg.forceBossNight = cfg.bossNight
	return cfg
end

local failed = 0
local function check(name, ok, detail)
	print(string.format("  [%s] %s%s", ok and "PASS" or "FAIL", name, detail and (" -- " .. detail) or ""))
	if not ok then
		failed = failed + 1
	end
end

for _, bot in ipairs({ "random", "greedy", "decent", "builder" }) do
	local same = true
	for seed = 1, 10 do
		local a = Report.serialize(Sim.runOne(config({ bot = bot }), seed))
		local b = Report.serialize(Sim.runOne(config({ bot = bot }), seed))
		same = same and a == b
	end
	check(bot .. " bot is deterministic per seed", same)
end

do
	local function soldKey(rec)
		local keys = {}
		for id, k in pairs(rec.patronsSold) do
			keys[#keys + 1] = id .. "=" .. k
		end
		table.sort(keys)
		return table.concat(keys, ",")
	end
	local same = true
	for seed = 1, 10 do
		same = same and soldKey(Sim.runOne(config({ bot = "greedy" }), seed)) == soldKey(Sim.runOne(config({ bot = "greedy" }), seed))
	end
	check("greedy bot sells the same Patrons per seed", same)
end

local a = Report.serialize(Sim.runOne(config(), 1))
local b = Report.serialize(Sim.runOne(config(), 2))
check("different seeds play differently", a ~= b)

-- The record's fields round-trip through the worker file format.
local rec = Sim.runOne(config(), 3)
check("records survive serialization", Report.serialize(Report.deserialize(Report.serialize(rec))) == Report.serialize(rec))

-- A Patron-less, one-hand-to-go state plays the visible best hand.
local state = engine.RunState.new(nil, engine.SeededRng.new(1))
local C = engine.Card.new
state.hand = { C(14, "Hearts"), C(14, "Spades"), C(14, "Clubs"), C(14, "Diamonds"), C(2, "Hearts"), C(9, "Clubs"), C(5, "Spades"), C(3, "Diamonds") }
local best, combo = Sim.bestPlay(state)
local played = {}
for i, index in ipairs(combo.played) do
	played[i] = state.hand[index]
end
check("bestPlay finds four of a kind", engine.HandEvaluator.evaluate(played).name == "Four of a Kind", tostring(best))

state.bossModifier = engine.BossRounds.getById("full_table")
local _, comboFive = Sim.bestPlay(state)
check("bestPlay obeys requiredCardsPerHand", #comboFive.played == 5)

state.bossModifier = engine.BossRounds.getById("no_repeats")
state.handTypesPlayedThisRound = { ["Four of a Kind"] = true }
local _, comboNew = Sim.bestPlay(state)
local playedNew = {}
for i, index in ipairs(comboNew.played) do
	playedNew[i] = state.hand[index]
end
check("bestPlay avoids a blocked repeat", engine.HandEvaluator.evaluate(playedNew).name ~= "Four of a Kind")

-- chooseKeep's three rules.
local suited = { C(2, "Hearts"), C(5, "Hearts"), C(9, "Hearts"), C(13, "Hearts"), C(3, "Spades"), C(4, "Clubs"), C(6, "Spades"), C(7, "Clubs") }
check("chooseKeep keeps a 4-card suit", #Sim.chooseKeep(suited) == 4)
local paired = { C(2, "Hearts"), C(2, "Spades"), C(9, "Hearts"), C(9, "Clubs"), C(3, "Spades"), C(4, "Clubs"), C(6, "Spades"), C(7, "Diamonds") }
check("chooseKeep keeps paired ranks", #Sim.chooseKeep(paired) == 4)
local loose = { C(2, "Hearts"), C(4, "Spades"), C(6, "Hearts"), C(8, "Clubs"), C(10, "Spades"), C(12, "Clubs"), C(14, "Spades"), C(3, "Diamonds") }
check("chooseKeep keeps the 3 highest", #Sim.chooseKeep(loose) == 3)

-- The builder bot says which draw each discard went for, and goes for more than one kind.
do
	local draws, kinds = 0, {}
	for seed = 1, 5 do
		for kind, count in pairs(Sim.runOne(config({ bot = "builder" }), seed).draws) do
			draws = draws + count
			kinds[kind] = true
		end
	end
	check("builder bot discards when behind pace", draws >= 10, draws .. " discards in 5 runs")
	check("builder bot chases Flush and Straight draws", kinds.flush == true and kinds.straight == true)
	local none = 0
	for _ in pairs(Sim.runOne(config({ bot = "decent" }), 1).draws) do
		none = none + 1
	end
	check("the other bots record no draws", none == 0)
end

-- The value table with discards: the same seed gives the same rows, a Patron that pays for a Flush makes the player
-- go and make Flushes, and it is worth more than a flat +4 Mult to a player who can chase it.
do
	local rows = Sim.chaseTable(24, 7, "open", 2, "all_matching,the_regular")
	local again = Sim.chaseTable(24, 7, "open", 2, "all_matching,the_regular")
	local byId, same = {}, #rows == #again
	for i, row in ipairs(rows) do
		byId[row.id] = row
		same = same and again[i] and again[i].id == row.id and again[i].value == row.value
	end
	check("chase table is deterministic per seed", same)
	check("chase table lists the Patrons asked for", byId.all_matching ~= nil and byId.the_regular ~= nil and #rows == 2)
	check("a Flush Patron sends the player after Flushes", byId.all_matching.top == "Flush", tostring(byId.all_matching.top))
	check("and is worth more than a flat Mult Patron to them", byId.all_matching.gain > byId.the_regular.gain,
		string.format("%.2f against %.2f", byId.all_matching.gain, byId.the_regular.gain))
	local economy = Sim.chaseTable(6, 7, "open", 2, "tip_jar")
	check("an economy Patron reads as zero", #economy == 1 and economy[1].gain == 0)
end

-- The bots know the Boss Rounds that zero a hand type: on Picky Eater a made Flush is not the best play.
do
	local picky = engine.RunState.new(nil, engine.SeededRng.new(1))
	picky.hand = { C(2, "Hearts"), C(5, "Hearts"), C(9, "Hearts"), C(11, "Hearts"), C(13, "Hearts"), C(13, "Clubs"), C(4, "Spades"), C(3, "Diamonds") }
	local _, free = Sim.bestPlay(picky)
	local freeCards = {}
	for i, index in ipairs(free.played) do
		freeCards[i] = picky.hand[index]
	end
	check("bestPlay takes the Flush on a normal round", engine.HandEvaluator.evaluate(freeCards).name == "Flush")
	picky.bossModifier = engine.BossRounds.getById("picky_eater")
	local score, blocked = Sim.bestPlay(picky)
	local blockedCards = {}
	for i, index in ipairs(blocked.played) do
		blockedCards[i] = picky.hand[index]
	end
	check("bestPlay leaves the Flush alone on Picky Eater", engine.HandEvaluator.evaluate(blockedCards).name == "Pair" and score > 0,
		engine.HandEvaluator.evaluate(blockedCards).name)
end

local forced = Sim.runOne(config({ forceBoss = "lights_out", bossNight = 1 }), 4)
check("forced boss appears on its Night", forced.bosses[1] and forced.bosses[1].id == "lights_out")

-- Balance regression (50 runs, fixed seeds): the decent bot's median death Night stays in its band on stakes 1 and 8
-- and nothing soft-locks. Measured 2026-11-08 (600 runs, balance pass 2): decent median N8 / N7 / N6 on stakes 1 / 4 / 8.
-- Balance pass 3 (600 runs): decent win 29.0 / 26.3 / 23.0 / 20.2 / 16.5 / 12.8 / 7.0 / 6.0 on stakes 1 to 8; stake 7 median N6.
for _, stake in ipairs({ 1, 4, 7, 8 }) do
	local nights, softLocks = {}, 0
	for seed = 1, 50 do
		local r = Sim.runOne(config({ stake = stake }), seed)
		nights[#nights + 1] = r.won and 99 or (r.deathNight or r.nightReached)
		softLocks = softLocks + r.softLocks
	end
	table.sort(nights)
	local median = nights[25]
	check("decent bot median Night in band on stake " .. stake, median >= 5 and median <= 9, "median " .. median)
	check("no soft locks on stake " .. stake, softLocks == 0, tostring(softLocks))
end

-- Quick Run (Engine/RunModes.lua): the decent bot wins 35 to 45 percent at stake 1 (measured 38.3 over 600 runs); this
-- 50 run check uses a wide band so it only trips on a real shift, and nothing soft-locks.
do
	local wins, softLocks = 0, 0
	for seed = 1, 50 do
		local r = Sim.runOne(config({ mode = "quick", stake = 1 }), seed)
		wins = wins + (r.won and 1 or 0)
		softLocks = softLocks + r.softLocks
	end
	check("decent bot Quick Run win rate in band", wins >= 12 and wins <= 33, wins .. " of 50")
	check("no soft locks in Quick Runs", softLocks == 0, tostring(softLocks))
end

-- Balance pass (Nov 19, 200 seeded runs, tools/balance_report.lua): greedy bot wins 20.5 percent, clears Night 3 in 87 and
-- Night 8 in 20.5; decent bot wins 32.5. This 40 run check only trips on a real shift.
do
	local wins, softLocks = 0, 0
	for seed = 1, 40 do
		local r = Sim.runOne(config({ bot = "greedy" }), seed)
		wins = wins + (r.won and 1 or 0)
		softLocks = softLocks + r.softLocks
	end
	check("greedy bot win rate in band", wins >= 3 and wins <= 16, wins .. " of 40")
	check("no soft locks for the greedy bot", softLocks == 0, tostring(softLocks))
end

print(failed == 0 and "\nAll simulator checks passed" or ("\n" .. failed .. " simulator check(s) failed"))
os.exit(failed == 0 and 0 or 1)
