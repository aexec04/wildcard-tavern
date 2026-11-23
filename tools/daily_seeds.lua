-- Daily seed check: 100 consecutive UTC days, each with the real Daily seed (SeededRng.dailySeed) and the twist of that day
-- (DailyModifiers.forDate). The best bot ("builder") tries every seed several times with different bot choices; a seed is
-- "unwinnable" when it never wins. Prints the worst seeds. Run: lua tools/daily_seeds.lua [days] [tries] [startTimestamp]
local loader = dofile("tools/sim/EngineLoader.lua")
local Sim = dofile("tools/sim/Sim.lua")
local engine = loader.load("src/Shared")
Sim.init(engine)
local DailyModifiers = engine.loadEngineModule("DailyModifiers")

local days = tonumber(arg[1]) or 100
local tries = tonumber(arg[2]) or 4
local start = tonumber(arg[3]) or 1767225600 -- 2026-01-01 UTC

local rows, unwinnable, stuck = {}, 0, 0
for d = 0, days - 1 do
	local ts = start + d * 86400
	local seed = engine.SeededRng.dailySeed(ts)
	local key = engine.SeededRng.dailyDateKey(ts)
	local twist = DailyModifiers.forDate(key)
	local wins, bestNight, nightSum = 0, 0, 0
	for t = 1, tries do
		local cfg = { bot = "builder", difficulty = "standard", deck = "standard", startDeck = "classic", maxNight = 8, bank = 0,
			bossNight = 6, dailyTwist = twist and twist.id or nil, botSeedOffset = (t - 1) * 101 }
		local ok, rec = pcall(Sim.runOne, cfg, seed)
		if ok and rec then
			if rec.won then wins = wins + 1 end
			bestNight = math.max(bestNight, rec.nightReached or 0)
			nightSum = nightSum + (rec.nightReached or 0)
		end
	end
	rows[#rows + 1] = { key = key, seed = seed, twist = twist and twist.id or "none", wins = wins, best = bestNight, mean = nightSum / tries }
	if wins == 0 then unwinnable = unwinnable + 1 end
	if bestNight <= 5 then stuck = stuck + 1 end
end
table.sort(rows, function(a, b)
	if a.best ~= b.best then return a.best < b.best end
	if a.mean ~= b.mean then return a.mean < b.mean end
	return a.wins < b.wins
end)
print(string.format("Daily seeds: %d days from %s, bot builder, %d tries per seed", days, rows[1] and "2026-01-01" or "", tries))
print(string.format("Seeds with no win in %d tries: %d of %d", tries, unwinnable, days))
print(string.format("Seeds where the best try never got past Night 5 (unwinnable in practice): %d of %d", stuck, days))
print("Worst five (lowest best Night, then lowest mean Night):")
for i = 1, math.min(5, #rows) do
	local r = rows[i]
	print(string.format("  %s seed %d twist %s: %d of %d won, best Night %d, mean %.1f", r.key, r.seed, r.twist, r.wins, tries, r.best, r.mean))
end
local total = 0
for _, r in ipairs(rows) do total = total + r.wins end
print(string.format("Win rate over all seeds: %.1f%%", 100 * total / (days * tries)))
