--[[
	balance_late.lua
	Late game check: clear rates for Nights 5 to 12 (Nights 9 and up are Endless) and the bosses faced.
		lua tools/balance_late.lua [runs] [seed]
	Prints a markdown section for claude/BALANCE-REPORT.md.
]]
local toolsDir = arg[0]:match("(.*)/balance_late%.lua$") or "."
package.path = toolsDir .. "/sim/?.lua;" .. package.path
local EngineLoader = require("EngineLoader")
local Sim = require("Sim")
Sim.init(EngineLoader.load(toolsDir .. "/../src/Shared"))

local runs, seed = tonumber(arg[1]) or 100, tonumber(arg[2]) or 1
for _, bot in ipairs({ "greedy", "decent" }) do
	local reached, cleared, pct, rounds = {}, {}, {}, {}
	local newBosses, bossRuns = 0, 0
	for k = 0, runs - 1 do
		local r = Sim.runOne({ bot = bot, maxNight = 12, endless = true, bank = 0, difficulty = "standard", deck = "standard" }, seed + k)
		local allClear = {}
		for _, x in ipairs(r.rounds or {}) do
			rounds[x.night] = (rounds[x.night] or 0) + 1
			pct[x.night] = (pct[x.night] or 0) + x.pct
			if allClear[x.night] == nil then
				allClear[x.night] = true
			end
			allClear[x.night] = allClear[x.night] and x.cleared
		end
		for n, ok in pairs(allClear) do
			reached[n] = (reached[n] or 0) + 1
			cleared[n] = (cleared[n] or 0) + (ok and 1 or 0)
		end
		local seen, fresh, late = {}, 0, 0
		for _, b in ipairs(r.bosses or {}) do
			if b.night >= 6 then
				late = late + 1
				if not seen[b.id] then
					fresh = fresh + 1
				end
				seen[b.id] = true
			end
		end
		if late > 0 then
			bossRuns = bossRuns + 1
			newBosses = newBosses + fresh / late
		end
	end
	print(string.format("### %s bot, %d runs", bot, runs))
	print("")
	print("| Night | Runs reaching | Runs clearing | Avg score over target |")
	print("|---|---|---|---|")
	for n = 5, 12 do
		if reached[n] then
			print(string.format("| %d | %d | %d | %.0f%% |", n, reached[n], cleared[n] or 0, pct[n] / rounds[n] * 100))
		end
	end
	print("")
	print(string.format("Share of Night 6+ bosses that were a new rule for the run: %.0f%%", bossRuns > 0 and newBosses / bossRuns * 100 or 0))
	print("")
end
