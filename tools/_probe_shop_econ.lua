local toolsDir = arg[0]:match("(.*)/_probe_shop_econ%.lua$") or "."
package.path = toolsDir .. "/sim/?.lua;" .. package.path
local EngineLoader = require("EngineLoader")
local Sim = require("Sim")
local E = EngineLoader.load(toolsDir .. "/../src/Shared")
Sim.init(E)
local orig = Sim.shopVisit
DEADBY = {}
local visits, dead, rich, n = {}, 0, 0, 0
Sim.shopVisit = function(state, cfg, rng, rec)
	if state.night <= 3 then
		local i = (state.night - 1) * 3 + state.round
		visits[i] = visits[i] or {}
		table.insert(visits[i], state.tips)
		local offers = E.Shop.rollOffers(state)
		local cheapest, total = math.huge, 0
		for _, p in ipairs(offers.patrons) do cheapest = math.min(cheapest, p.price); total = total + p.price end
		for _, p in ipairs(offers.packs) do cheapest = math.min(cheapest, p.price); total = total + p.price end
		n = n + 1
		if state.tips < cheapest and state.tips < E.RunState.rerollCost(state, E.Shop.REROLL_BASE_COST) then
			dead = dead + 1
			DEADBY[i] = (DEADBY[i] or 0) + 1
		end
		if state.tips >= total + 10 then rich = rich + 1 end
	end
	return orig(state, cfg, rng, rec)
end
for _, bot in ipairs({ "decent", "builder" }) do
	visits, dead, rich, n = {}, 0, 0, 0
	local sum, deaths, runs = 0, 0, 0
	for seed = 1, 60 do
		local rec = Sim.runOne({ bot = bot, maxNight = 3, bank = 0, difficulty = "standard", deck = "standard" }, seed)
		runs = runs + 1
		local c = 0
		for _ in pairs(rec.patronsBought) do c = c + 1 end
		sum = sum + c
		if rec.deathNight and rec.deathNight <= 3 then deaths = deaths + 1 end
	end
	print(bot, "runs", runs, "diedByN3", deaths, "avgPatronsBought", sum / runs)
	for i = 1, 9 do
		local v = visits[i]
		if v then
			local s = 0
			for _, t in ipairs(v) do s = s + t end
			table.sort(v)
			print(string.format("  visit %d (N%d R%d): n=%d avgTips=%.1f min=%d max=%d", i, math.ceil(i / 3), (i - 1) % 3 + 1, #v, s / #v, v[1], v[#v]))
		end
	end
	for k = 1, 8 do io.write(k, ":", DEADBY[k] or 0, " ") end
	print()
	DEADBY = {}
	print(string.format("  deadShop %d/%d  noTension %d/%d", dead, n, rich, n))
end
