--[[
	NightTable.lua
	Per-Night clear table for the balance report. Plays seeded runs with a bot and, per Night,
	counts the runs that reached it, the runs that cleared every round of it, and the average
	score over target of the rounds played in it. Also counts Patron buys and wins.
]]
local NightTable = {}

local MAX_NIGHT = 8

function NightTable.collect(Sim, bot, runs, seed)
	local cfg = { bot = bot, maxNight = 10, bank = 0, difficulty = "standard", deck = "standard" }
	local nights = {}
	for n = 1, MAX_NIGHT do
		nights[n] = { reached = 0, cleared = 0, pctSum = 0, rounds = 0, bossPlayed = 0, bossCleared = 0 }
	end
	local patrons, wins = {}, 0
	for k = 0, runs - 1 do
		local r = Sim.runOne(cfg, seed + k)
		local perNight = {}
		for _, rd in ipairs(r.rounds or {}) do
			local row = nights[rd.night]
			if row then
				row.pctSum = row.pctSum + rd.pct
				row.rounds = row.rounds + 1
				if rd.boss then
					row.bossPlayed = row.bossPlayed + 1
					if rd.cleared then row.bossCleared = row.bossCleared + 1 end
				end
				local p = perNight[rd.night]
				if not p then
					p = { all = true }
					perNight[rd.night] = p
				end
				p.all = p.all and rd.cleared
			end
		end
		for n, p in pairs(perNight) do
			nights[n].reached = nights[n].reached + 1
			if p.all then
				nights[n].cleared = nights[n].cleared + 1
			end
		end
		if r.won then
			wins = wins + 1
		end
		for id in pairs(r.patronsBought) do
			local e = patrons[id] or { bought = 0, wins = 0 }
			e.bought = e.bought + 1
			e.wins = e.wins + (r.won and 1 or 0)
			patrons[id] = e
		end
	end
	return { bot = bot, runs = runs, nights = nights, patrons = patrons, wins = wins }
end

-- Share of all runs that cleared Night n (the number a new player feels).
function NightTable.clearShare(t, n)
	return t.nights[n].cleared / math.max(1, t.runs)
end

return NightTable
