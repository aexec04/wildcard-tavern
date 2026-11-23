--[[
	sim_sets.lua
	Per Night clear rate (cleared / reached) for three bots with the default deck, to back claude/sim-sets.md.
	Card Sets are cosmetic and the engine never reads them, so one run covers all 14 sets.
		lua tools/sim_sets.lua [runs] [seed]
]]
local toolsDir = arg[0]:match("(.*)/sim_sets%.lua$") or "."
package.path = toolsDir .. "/sim/?.lua;" .. package.path
local EngineLoader = require("EngineLoader")
local Sim = require("Sim")
local NightTable = require("NightTable")
Sim.init(EngineLoader.load(toolsDir .. "/../src/Shared"))
local runs, seed = tonumber(arg[1]) or 300, tonumber(arg[2]) or 1
for _, bot in ipairs({ "random", "greedy", "decent" }) do
	local t = NightTable.collect(Sim, bot, runs, seed)
	local cells = {}
	for n = 1, 8 do
		local r = t.nights[n]
		cells[#cells + 1] = string.format("%d:%.0f%%(%d)", n, r.reached > 0 and r.cleared / r.reached * 100 or 0, r.reached)
	end
	print(bot, table.concat(cells, " "))
end
