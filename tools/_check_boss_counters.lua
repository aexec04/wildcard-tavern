-- one-off: prints the problems of BossCounters.validate() under plain lua
package.path = "src/Shared/Engine/?.lua;" .. package.path
local loader = dofile("tools/sim/EngineLoader.lua")
local engine = loader.load("src/Shared")
local problems = engine.BossCounters and engine.BossCounters.validate() or { "BossCounters is not loaded by EngineLoader" }
for _, p in ipairs(problems) do print(p) end
print(#problems .. " problems")
