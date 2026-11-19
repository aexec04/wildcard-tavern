--[[
	balance_report.lua
	Studio-free balance pass: plays N seeded runs with a sim bot and prints the share of runs that
	cleared each Night, the win rate, the average score versus target at death, and the Patrons whose
	win rate (among runs that bought them) is furthest above and below the average.

		lua tools/balance_report.lua [--bot greedy|decent] [--runs 200] [--seed 1]
]]
local toolsDir = arg[0]:match("(.*)/balance_report%.lua$") or "."
package.path = toolsDir .. "/sim/?.lua;" .. package.path
local EngineLoader = require("EngineLoader")
local Sim = require("Sim")

local opts = { bot = "greedy", runs = 200, seed = 1 }
local i = 1
while arg[i] do
	local key = arg[i]:match("^%-%-(%w+)$")
	if key and opts[key] ~= nil then
		opts[key] = type(opts[key]) == "number" and tonumber(arg[i + 1]) or arg[i + 1]
		i = i + 1
	end
	i = i + 1
end

Sim.init(EngineLoader.load(toolsDir .. "/../src/Shared"))
local cfg = { bot = opts.bot, maxNight = 10, bank = 0, difficulty = "standard", deck = "standard" }
cfg.forceBossNight = cfg.bossNight

local wins, pctSum, pctN = 0, 0, 0
local cleared = {}
local perPatron = {}
for n = 0, opts.runs - 1 do
	local r = Sim.runOne(cfg, opts.seed + n)
	local reached = r.won and 99 or ((r.deathNight or r.nightReached or 1) - 1)
	for night = 1, math.min(reached, 8) do
		cleared[night] = (cleared[night] or 0) + 1
	end
	if r.won then
		wins = wins + 1
	elseif r.deathPct then
		pctSum, pctN = pctSum + r.deathPct, pctN + 1
	end
	for id in pairs(r.patronsBought) do
		local p = perPatron[id] or { n = 0, w = 0, sold = 0 }
		p.n, p.w = p.n + 1, p.w + (r.won and 1 or 0)
		perPatron[id] = p
	end
	for id, k in pairs(r.patronsSold or {}) do
		local p = perPatron[id] or { n = 0, w = 0, sold = 0 }
		p.sold = p.sold + k
		perPatron[id] = p
	end
end

local avg = wins / opts.runs
print(string.format("%s bot, %d runs, seed %d: win %.1f%%", opts.bot, opts.runs, opts.seed, avg * 100))
local row = {}
for night = 1, 8 do
	row[#row + 1] = string.format("N%d %.1f%%", night, (cleared[night] or 0) / opts.runs * 100)
end
print("cleared: " .. table.concat(row, ", "))
print(string.format("average score at death: %.1f%% of target", pctN > 0 and pctSum / pctN * 100 or 0))

local list = {}
for id, p in pairs(perPatron) do
	if p.n >= 10 then
		list[#list + 1] = { id = id, n = p.n, rate = p.w / p.n }
	end
end
table.sort(list, function(a, b)
	if a.rate ~= b.rate then
		return a.rate > b.rate
	end
	return a.id < b.id
end)
local function show(title, from, to, step)
	print(title)
	for k = from, to, step do
		local e = list[k]
		if e then
			print(string.format("  %-22s win %5.1f%% (%+.1f vs avg, %d runs)%s", e.id, e.rate * 100,
				(e.rate - avg) * 100, e.n, math.abs(e.rate - avg) > 0.30 and "  FLAG" or ""))
		end
	end
end
show("top 5 Patrons (runs that bought them):", 1, math.min(5, #list), 1)
show("bottom 5 Patrons:", #list, math.max(1, #list - 4), -1)

-- share of winning runs that bought each Patron (target: none above 25 percent)
local shares = {}
for id, p in pairs(perPatron) do
	if wins > 0 and p.w > 0 then
		shares[#shares + 1] = { id = id, share = p.w / wins, n = p.n, sold = p.sold }
	end
end
table.sort(shares, function(a, b)
	if a.share ~= b.share then
		return a.share > b.share
	end
	return a.id < b.id
end)
print(string.format("share of the %d winning runs that bought the Patron (limit 25%%), with runs bought and times sold:", wins))
for k = 1, math.min(8, #shares) do
	local e = shares[k]
	print(string.format("  %-22s %5.1f%%  bought in %d runs, sold %d times%s", e.id, e.share * 100, e.n, e.sold,
		e.share > 0.25 and "  OVER" or ""))
end
