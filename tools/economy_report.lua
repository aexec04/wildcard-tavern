--[[
	economy_report.lua
	Prints the simulated week of 20 minute sessions (Engine/EconomySim.lua) as markdown for claude/ECONOMY.md.

		lua tools/economy_report.lua [startDay]
]]
local toolsDir = arg[0]:match("(.*)/economy_report%.lua$") or "."
package.path = toolsDir .. "/sim/?.lua;" .. package.path
local EngineLoader = require("EngineLoader")
local Engine = EngineLoader.load(toolsDir .. "/../src/Shared")
local EconomySim = Engine.loadEngineModule("EconomySim")
local startDay = tonumber(arg[1]) or math.floor(os.time({ year = 2026, month = 11, day = 23, hour = 12 }) / 86400)
local result = EconomySim.week(startDay)
print(EconomySim.markdown(result))
print()
if #result.flags == 0 then
	print("No day is over 3x or under a third of the others.")
else
	for _, f in ipairs(result.flags) do print("- " .. f) end
end
