--[[
	scoring_perf.lua
	Times Scoring.calculate over N hands (default 10000) with 5 Patrons, in the sim loader, and prints hands per second.
	Optional second argument: a budget in seconds; exits 1 when it is exceeded.

		lua tools/scoring_perf.lua [hands] [budgetSeconds]
]]
local toolsDir = arg[0]:match("(.*)/scoring_perf%.lua$") or "."
package.path = toolsDir .. "/sim/?.lua;" .. package.path
local EngineLoader = require("EngineLoader")
local E = EngineLoader.load(toolsDir .. "/../src/Shared")
local hands, budget = tonumber(arg[1]) or 10000, tonumber(arg[2])
local rng = E.SeededRng.new(5)
local owned = {}
for i = 1, 5 do owned[i] = E.Patrons.Definitions[i * 7] end
local deck = E.Deck.newStandardDeck()
local t0 = os.clock()
for _ = 1, hands do
	deck = E.Deck.shuffle(deck, rng)
	local hand = {}
	for k = 1, 5 do hand[k] = deck[k] end
	E.Scoring.calculate(E.HandEvaluator.evaluate(hand), owned, { handLevels = {}, rng = rng })
end
local took = os.clock() - t0
print(string.format("%d hands scored in %.3f s (%.0f hands a second, %.1f microseconds each, including the shuffle and the evaluation)", hands, took, hands / took, 1e6 * took / hands))
if budget and took > budget then print("OVER BUDGET " .. budget .. " s"); os.exit(1) end
