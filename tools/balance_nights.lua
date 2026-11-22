--[[
	balance_nights.lua
	Writes claude/BALANCE-REPORT.md: clear rates by Night for three bots.
		lua tools/balance_nights.lua [runs] [seed]
]]
local toolsDir = arg[0]:match("(.*)/balance_nights%.lua$") or "."
package.path = toolsDir .. "/sim/?.lua;" .. package.path
local EngineLoader = require("EngineLoader")
local Sim = require("Sim")
local NightTable = require("NightTable")
Sim.init(EngineLoader.load(toolsDir .. "/../src/Shared"))

local runs, seed = tonumber(arg[1]) or 300, tonumber(arg[2]) or 1
local GOAL = { [1] = 0.80, [2] = 0.55, [3] = 0.35 }
local bots = { "random", "greedy", "decent" }
local out = {}
local function add(s)
	out[#out + 1] = s
end

add("# Balance report: clear rates by Night")
add("")
add(string.format("Seeded headless runs (%d per bot, seeds %d to %d), standard difficulty and deck, through the real engine. Regenerate with `lua tools/balance_nights.lua %d %d`.", runs, seed, seed + runs - 1, runs, seed))
add("")
add("Bots: random (random legal hand, no discards), greedy (best scoring hand, no discards), decent (greedy that discards when behind pace). All three share one shop policy that buys the best value Patron on offer, so the shop bot is not a separate column.")
add("")
add("Targets for a new player: Night 1 about 80%, Night 2 about 55%, Night 3 about 35% of runs clearing the Night.")
add("")
local results = {}
for _, bot in ipairs(bots) do
	local t = NightTable.collect(Sim, bot, runs, seed)
	results[bot] = t
	add(string.format("## %s bot (win rate %.1f%%)", bot, t.wins / runs * 100))
	add("")
	add("| Night | Runs reaching | Runs clearing | Cleared (of all runs) | Avg score over target | Boss Round cleared (of those faced) |")
	add("|---|---|---|---|---|---|")
	for n = 1, 8 do
		local row = t.nights[n]
		add(string.format("| %d | %d | %d | %.1f%% | %s | %s |", n, row.reached, row.cleared,
			NightTable.clearShare(t, n) * 100,
			row.rounds > 0 and string.format("%.0f%%", row.pctSum / row.rounds * 100) or "n/a",
			row.bossPlayed > 0 and string.format("%.0f%% (%d)", row.bossCleared / row.bossPlayed * 100, row.bossPlayed) or "n/a"))
	end
	add("")
end

add("## Patrons (decent bot): bought and win rate")
add("")
add("| Patron | Runs bought | Win rate when bought |")
add("|---|---|---|")
local list = {}
for id, e in pairs(results.decent.patrons) do
	list[#list + 1] = { id = id, e = e }
end
table.sort(list, function(a, b)
	if a.e.bought ~= b.e.bought then
		return a.e.bought > b.e.bought
	end
	return a.id < b.id
end)
for k = 1, math.min(15, #list) do
	local x = list[k]
	add(string.format("| %s | %d | %.0f%% |", x.id, x.e.bought, x.e.wins / x.e.bought * 100))
end
add("")
add("## Recommendation")
add("")
for n = 1, 3 do
	local d = NightTable.clearShare(results.decent, n)
	local g = NightTable.clearShare(results.greedy, n)
	local r = NightTable.clearShare(results.random, n)
	local verdict = "near goal"
	if d > GOAL[n] + 0.15 then
		verdict = "too easy"
	elseif d < GOAL[n] - 0.15 then
		verdict = "too hard"
	end
	add(string.format("- Night %d (goal %.0f%%): random %.0f%%, greedy %.0f%%, decent %.0f%%. Looks %s for the decent bot.", n, GOAL[n] * 100, r * 100, g * 100, d * 100, verdict))
end
add("")
add("Bots see every card combination (better than a new player) but do not plan Patron builds (worse than a practiced one). Read the random bot as a floor and the decent bot as a practiced ceiling; a new player should land between them. Targets were not changed.")
local f = assert(io.open(toolsDir .. "/../claude/BALANCE-REPORT.md", "w"))
f:write(table.concat(out, "\n") .. "\n")
f:close()
print(table.concat(out, "\n"))
