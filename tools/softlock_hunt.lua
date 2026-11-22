--[[
	softlock_hunt.lua
	Plays thousands of random runs through the real engine (every deck, boss rule, difficulty, run mode and three bots)
	and fails if a run errors, ends in a soft lock, or never ends. Usage:
		lua tools/softlock_hunt.lua [runs] [firstSeed]
]]
local toolsDir = arg[0]:match("(.*)/softlock_hunt%.lua$") or "."
package.path = toolsDir .. "/sim/?.lua;" .. package.path
local E = require("EngineLoader").load(toolsDir .. "/../src/Shared")
local Sim = require("Sim")
Sim.init(E)

local runs = tonumber(arg[1]) or 5000
local first = tonumber(arg[2]) or 1
local bots = { "random", "greedy", "decent" }
local decks, bosses, modes, diffs = {}, {}, { false }, {}
for _, d in ipairs(E.DeckVariants.Definitions) do decks[#decks + 1] = d.id end
for _, b in ipairs(E.BossRounds.Definitions) do bosses[#bosses + 1] = b.id end
for id in pairs(E.loadEngineModule("RunModes").Modes) do modes[#modes + 1] = id end
for _, d in ipairs(E.DifficultyTiers.Definitions) do diffs[#diffs + 1] = d.id end
table.sort(modes, function(a, b) return tostring(a) < tostring(b) end)

local failures, errors, ended = 0, 0, 0
for i = 0, runs - 1 do
	local seed = first + i
	local cfg = {
		bot = bots[seed % #bots + 1], maxNight = 6 + seed % 5, bank = 0,
		difficulty = diffs[(seed // 3) % #diffs + 1], deck = decks[(seed // 5) % #decks + 1],
		forceBoss = bosses[(seed // 2) % #bosses + 1], bossFrom = 1,
		mode = modes[(seed // 7) % #modes + 1] or nil,
	}
	local ok, rec = pcall(Sim.runOne, cfg, seed)
	if not ok then
		errors = errors + 1
		print("ERROR seed " .. seed .. ": " .. tostring(rec))
	else
		if rec.softLocks > 0 then
			failures = failures + 1
			print("SOFT LOCK seed " .. seed .. " deck " .. cfg.deck .. " boss " .. cfg.forceBoss)
		end
		if rec.won or rec.deathNight or rec.reachedCap then ended = ended + 1 end
	end
end
print(string.format("%d runs, %d ended cleanly, %d soft locks, %d errors", runs, ended, failures, errors))
os.exit((failures + errors == 0 and ended == runs) and 0 or 1)
