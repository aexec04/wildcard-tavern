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

for _, bot in ipairs({ "random", "greedy", "decent" }) do
	local same = true
	for seed = 1, 10 do
		local a = Report.serialize(Sim.runOne(config({ bot = bot }), seed))
		local b = Report.serialize(Sim.runOne(config({ bot = bot }), seed))
		same = same and a == b
	end
	check(bot .. " bot is deterministic per seed", same)
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

print(failed == 0 and "\nAll simulator checks passed" or ("\n" .. failed .. " simulator check(s) failed"))
os.exit(failed == 0 and 0 or 1)
