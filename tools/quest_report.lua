--[[
	quest_report.lua
	Prints, for every daily quest, how many runs of the 20 minute session model (Engine/EconomySim.lua) finish it.

		lua tools/quest_report.lua
]]
local toolsDir = arg[0]:match("(.*)/quest_report%.lua$") or "."
package.path = toolsDir .. "/sim/?.lua;" .. package.path
local EngineLoader = require("EngineLoader")
local Engine = EngineLoader.load(toolsDir .. "/../src/Shared")
local EconomySim = Engine.loadEngineModule("EconomySim")
print(EconomySim.questMarkdown(EconomySim.questReport()))
