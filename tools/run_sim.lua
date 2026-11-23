--[[
	run_sim.lua
	Command line for the headless balance simulator (tools/sim). Needs any
	Lua 5.3 interpreter:

		lua5.3 tools/run_sim.lua --ladder --runs 1000 --jobs 8
		lua5.3 tools/run_sim.lua --bot decent --deck high_roller --runs 500
		lua5.3 tools/run_sim.lua --bosses --runs 200 --jobs 8
		lua5.3 tools/run_sim.lua --patron-table
		lua5.3 tools/run_sim.lua --patron-lift --runs 300 --jobs 8
		lua5.3 tools/run_sim.lua --chase-table --runs 300 --build mid

	Options:
		--bot random|greedy|decent|builder   (default decent; builder also picks which draw to chase)
		--stake N                    run on stake 1 to 8 (default 1)
		--stakes                     every stake x every bot, one summary line each
		--ladder                     all three bots, one summary line each
		--variants                   decent bot on every deck and difficulty
		--start-decks                decent bot on Classic, Lucky and Slim (Engine/StartingDecks), --start-deck ID for one
		--bosses                     force each boss on --boss-night, report clear rates
		--boss-list ID,ID            limit --bosses to these
		--patron-lift                start with each Patron for free, report win-rate lift
		--patron-table               Patron marginal value table
		--chase-table                Patron value for a player who spends discards (the builder bot's play)
		    --build open|mid         table each Patron is added to (default open: Night 1, nobody seated)
		    --discards N             discards to spend on each hand (default 2)
		    --patron-list ID,ID      limit the rows to these
		--runs N  --seed N  --jobs N
		--difficulty ID  --deck ID
		--max-night N                stop after this Night's boss (default 10)
		--endless                    keep playing after a win, up to --max-night
		--bank N                     banking bot: never spend below N Tips
		--night-one-discards N       extra discards on Night 1 (new-player bonus)
		--force-boss ID  --boss-night N
		--force-patron ID,ID         own these Patrons from the start
		--force-passes ID,ID         own these House Passes from the start
		--patron-offers N  --pack-offers N  --voucher-chance X   shop generosity
		--src PATH                   engine to load (default src/Shared)
		--json PATH  --csv PATH
]]

local toolsDir = arg[0]:match("(.*)/run_sim%.lua$") or "."
package.path = toolsDir .. "/sim/?.lua;" .. package.path

local EngineLoader = require("EngineLoader")
local Sim = require("Sim")
local Report = require("Report")

local function parseArgs(argv)
	local cfg = {
		bot = "decent", runs = 300, seed = 1, jobs = 1, maxNight = 10, bank = 0,
		difficulty = "standard", deck = "standard", bossNight = 6,
		src = toolsDir .. "/../src/Shared",
	}
	local names = {
		["--bot"] = "bot", ["--difficulty"] = "difficulty", ["--deck"] = "deck", ["--start-deck"] = "startDeck", ["--src"] = "src",
		["--json"] = "json", ["--csv"] = "csv", ["--force-boss"] = "forceBoss", ["--mode"] = "mode",
		["--force-patron"] = "forcePatron", ["--force-passes"] = "forcePasses", ["--boss-list"] = "bossList", ["--worker-out"] = "workerOut",
		["--build"] = "build", ["--patron-list"] = "patronList", ["--daily-twist"] = "dailyTwist", ["--boon"] = "boon", ["--boon-list"] = "boonList",
	}
	local numbers = {
		["--runs"] = "runs", ["--seed"] = "seed", ["--jobs"] = "jobs", ["--max-night"] = "maxNight",
		["--bank"] = "bank", ["--marks"] = "marks", ["--boss-night"] = "bossNight", ["--patron-offers"] = "patronOffers",
		["--pack-offers"] = "packOffers", ["--voucher-chance"] = "voucherChance",
		["--first-run"] = "firstRun", ["--start-tips"] = "startTips", ["--shop-nights"] = "shopNights", ["--stake"] = "stake", ["--night-one-discards"] = "nightOneDiscards",
		["--discards"] = "discards", ["--late-start"] = "lateStart", ["--late-count"] = "lateCount", ["--min-builds"] = "minBuilds", ["--boss-from"] = "bossFrom",
	}
	local flags = {
		["--ladder"] = "ladder", ["--variants"] = "variants", ["--start-decks"] = "startDecks", ["--bosses"] = "bosses",
		["--patron-lift"] = "patronLift", ["--patron-table"] = "patronTable", ["--stakes"] = "stakes", ["--endless"] = "endless",
		["--chase-table"] = "chaseTable", ["--random-patrons"] = "randomPatrons", ["--combos"] = "combos", ["--late"] = "late", ["--patron-rates"] = "patronRates", ["--boss-rules"] = "bossRules", ["--pair-rates"] = "pairRates", ["--daily-twists"] = "dailyTwists", ["--boss-late"] = "bossLate", ["--offers"] = "offers", ["--shop-econ"] = "shopEcon", ["--welcome"] = "welcome", ["--pacing"] = "pacing", ["--boons"] = "boons", ["--boss-boons"] = "bossBoons",
	}
	local i = 1
	while i <= #argv do
		local a = argv[i]
		if names[a] then
			cfg[names[a]] = argv[i + 1]
			i = i + 2
		elseif numbers[a] then
			cfg[numbers[a]] = assert(tonumber(argv[i + 1]), a .. " needs a number")
			i = i + 2
		elseif flags[a] then
			cfg[flags[a]] = true
			i = i + 1
		else
			error("Unknown option: " .. tostring(a))
		end
	end
	return cfg
end

local cfg = parseArgs(arg)
local engine = EngineLoader.load(cfg.src)
Sim.init(engine)

if cfg.patronOffers then engine.Shop.OFFER_COUNT = cfg.patronOffers end
if cfg.packOffers then engine.Shop.PACK_OFFER_COUNT = cfg.packOffers end
if cfg.voucherChance then engine.Shop.VOUCHER_CHANCE = cfg.voucherChance end

local function runConfig(overrides)
	local run = {}
	for k, v in pairs(cfg) do
		run[k] = v
	end
	for k, v in pairs(overrides or {}) do
		run[k] = v
	end
	run.forceBossNight = run.bossNight
	return run
end

-- ===== Worker mode: run one slice and write records to a file =====

local function workerArgs(run, firstRun, count, outPath)
	local parts = {
		"--bot", run.bot, "--difficulty", run.difficulty, "--deck", run.deck, "--start-deck", run.startDeck or "classic",
		"--max-night", run.maxNight, "--bank", run.bank, "--seed", run.seed,
		"--src", run.src, "--boss-night", run.bossNight,
		"--runs", count, "--first-run", firstRun, "--worker-out", outPath,
	}
	if run.marks then
		table.insert(parts, "--marks"); table.insert(parts, run.marks)
	end
	if run.boon then table.insert(parts, "--boon"); table.insert(parts, run.boon) end
	if run.startTips then table.insert(parts, "--start-tips"); table.insert(parts, run.startTips) end
	if run.forceBoss then
		table.insert(parts, "--force-boss"); table.insert(parts, run.forceBoss)
	end
	if run.forcePatron then
		table.insert(parts, "--force-patron"); table.insert(parts, run.forcePatron)
	end
	if run.bossFrom then table.insert(parts, "--boss-from"); table.insert(parts, run.bossFrom) end
	if run.dailyTwist then
		table.insert(parts, "--daily-twist"); table.insert(parts, run.dailyTwist)
	end
	if run.forcePasses then
		table.insert(parts, "--force-passes"); table.insert(parts, run.forcePasses)
	end
	if run.nightOneDiscards then
		table.insert(parts, "--night-one-discards"); table.insert(parts, run.nightOneDiscards)
	end
	if run.stake then table.insert(parts, "--stake"); table.insert(parts, run.stake) end
	if run.mode then table.insert(parts, "--mode"); table.insert(parts, run.mode) end
	if run.endless then table.insert(parts, "--endless") end
	if run.welcome then table.insert(parts, "--welcome") end
	if run.lateStart then
		table.insert(parts, "--late-start"); table.insert(parts, run.lateStart)
		table.insert(parts, "--late-count"); table.insert(parts, run.lateCount)	end
	if run.randomPatrons then table.insert(parts, "--random-patrons") end
	if run.patronOffers then table.insert(parts, "--patron-offers"); table.insert(parts, run.patronOffers) end
	if run.packOffers then table.insert(parts, "--pack-offers"); table.insert(parts, run.packOffers) end
	if run.voucherChance then table.insert(parts, "--voucher-chance"); table.insert(parts, run.voucherChance) end
	local quoted = {}
	for i, part in ipairs(parts) do
		quoted[i] = "'" .. tostring(part) .. "'"
	end
	return table.concat(quoted, " ")
end

if cfg.workerOut then
	local file = assert(io.open(cfg.workerOut, "w"))
	local run = runConfig()
	for i = cfg.firstRun, cfg.firstRun + cfg.runs - 1 do
		file:write(Report.serialize(Sim.runOne(run, cfg.seed + i)), "\n")
	end
	file:close()
	os.exit(0)
end

-- Seeds come from the run index, so results don't depend on --jobs.
local function collect(run)
	local records = {}
	if run.jobs <= 1 then
		for i = 0, run.runs - 1 do
			table.insert(records, Sim.runOne(run, run.seed + i))
		end
		return records
	end

	local interpreter = os.getenv("SIM_LUA") or arg[-1]
	local script = arg[0]
	local jobs = math.min(run.jobs, run.runs)
	local outPaths, commands = {}, {}
	local start = 0
	for j = 1, jobs do
		local count = math.floor(run.runs / jobs) + (j <= run.runs % jobs and 1 or 0)
		local outPath = os.tmpname()
		outPaths[j] = outPath
		commands[j] = string.format("'%s' '%s' %s &", interpreter, script, workerArgs(run, start, count, outPath))
		start = start + count
	end
	local shellOk = os.execute("{ " .. table.concat(commands, " ") .. " wait; }")
	assert(shellOk, "A simulator worker failed to start")
	for _, outPath in ipairs(outPaths) do
		for line in io.lines(outPath) do
			table.insert(records, Report.deserialize(line))
		end
		os.remove(outPath)
	end
	assert(#records == run.runs, string.format("Expected %d records, got %d (a worker crashed)", run.runs, #records))
	return records
end

local function runAndSummarize(label, overrides)
	local run = runConfig(overrides)
	local records = collect(run)
	local summary = Report.aggregate(records)
	print(Report.summaryLine(label, summary))
	io.stdout:flush()
	return summary, records
end

-- ===== Report modes =====

if cfg.patronTable then
	local rows, base = Sim.patronTable(cfg.runs, cfg.seed)
	local gains = {}
	for _, row in ipairs(rows) do
		if row.gain > 0 then
			table.insert(gains, row.gainPerPrice)
		end
	end
	table.sort(gains)
	local median = gains[math.ceil(#gains / 2)] or 1
	print(string.format("Average best hand at mid-build: %.0f (%d sampled hands). Median gain/price of Patrons with a scoring effect: %.2f%%", base, cfg.runs, 100 * median))
	print(string.format("%-22s %5s %8s %10s %8s", "patron", "price", "gain", "gain/price", "x median"))
	for _, row in ipairs(rows) do
		print(string.format("%-22s %5d %7.1f%% %9.2f%% %8.2f", row.id, row.price, 100 * row.gain, 100 * row.gainPerPrice, row.gainPerPrice / median))
	end
elseif cfg.chaseTable then
	local discards = cfg.discards or 2
	local rows, base, baseTop, baseShare = Sim.chaseTable(cfg.runs, cfg.seed, cfg.build, discards, cfg.patronList)
	print(string.format("Build %s, %d deals, %d %s to spend on each hand. Without the Patron: average hand %.0f, mostly %s (%.0f%% of hands).",
		cfg.build or "open", cfg.runs, discards, discards == 1 and "discard" or "discards", base, baseTop, 100 * baseShare))
	print(string.format("%-22s %5s %9s %8s   %s", "patron", "price", "avg hand", "gain", "plays mostly"))
	for _, row in ipairs(rows) do
		print(string.format("%-22s %5d %9.0f %+7.1f%%   %s %.0f%%", row.id, row.price, row.value, 100 * row.gain, row.top, 100 * row.share))
	end
elseif cfg.stakes then
	-- every stake x every bot, one summary line each
	for stake = 1, engine.Stakes.MAX do
		for _, bot in ipairs({ "random", "greedy", "decent" }) do
			runAndSummarize(string.format("stake %d %s", stake, bot), { bot = bot, stake = stake })
		end
	end
elseif cfg.ladder then
	local summaries = {}
	for _, bot in ipairs({ "random", "greedy", "decent" }) do
		summaries[bot] = runAndSummarize(bot, { bot = bot })
	end
	if cfg.json then
		Report.writeJson(cfg.json, "ladder", summaries.decent)
	end
elseif cfg.boons then
	-- Night boons (Engine/NightBoons): the bot takes the same boon on every Night 2 to 12 ("none" is the baseline)
	local only = cfg.boonList and ("," .. cfg.boonList .. ",")
	runAndSummarize("boon=none", { boon = nil })
	for _, def in ipairs(engine.NightBoons.Definitions) do
		if not only or only:find("," .. def.id .. ",", 1, true) then
			runAndSummarize("boon=" .. def.id, { boon = def.id })
		end
	end
elseif cfg.startDecks then
	for _, def in ipairs(engine.StartingDecks.Definitions) do
		runAndSummarize("start-deck=" .. def.id, { startDeck = def.id })
	end
elseif cfg.variants then
	for _, def in ipairs(engine.DeckVariants.Definitions) do
		runAndSummarize("deck=" .. def.id, { deck = def.id })
	end
	for _, def in ipairs(engine.DifficultyTiers.Definitions) do
		runAndSummarize("difficulty=" .. def.id, { difficulty = def.id })
	end
elseif cfg.bosses then
	local rows = {}
	local attempts, clears = 0, 0
	local onlyThese = cfg.bossList and ("," .. cfg.bossList .. ",")
	for _, def in ipairs(engine.BossRounds.Definitions) do
		local records = (not onlyThese or onlyThese:find("," .. def.id .. ",", 1, true))
			and collect(runConfig({ forceBoss = def.id })) or {}
		local tries, wins = 0, 0
		for _, rec in ipairs(records) do
			for _, boss in ipairs(rec.bosses) do
				if boss.id == def.id and boss.night == cfg.bossNight then
					tries = tries + 1
					if boss.cleared then
						wins = wins + 1
					end
				end
			end
		end
		if tries > 0 then
			table.insert(rows, { id = def.id, minNight = def.minNight, tries = tries, wins = wins, rate = wins / tries })
		end
		attempts = attempts + tries
		clears = clears + wins
	end
	local average = clears / math.max(1, attempts)
	table.sort(rows, function(a, b)
		return a.rate < b.rate
	end)
	print(string.format("Boss clear rate on forced Night %d, bot %s. All-boss average %.1f%%", cfg.bossNight, cfg.bot, 100 * average))
	print(string.format("%-20s %8s %9s %8s %10s", "boss", "minNight", "attempts", "clear", "x average"))
	for _, row in ipairs(rows) do
		print(string.format("%-20s %8d %9d %7.1f%% %10.2f", row.id, row.minNight, row.tries, 100 * row.rate, row.rate / math.max(0.0001, average)))
	end
elseif cfg.endless and cfg.maxNight >= 15 then
	-- Endless run length: full runs with random Patron picks, clear rate per Night 9 to 15 and median Night reached
	cfg.randomPatrons = true
	local records = collect(runConfig())
	local entered, cleared, reached, endlessReached = {}, {}, {}, {}
	for _, rec in ipairs(records) do
		local last = rec.deathNight or rec.nightReached or 1
		reached[#reached + 1] = last
		if last >= 9 then endlessReached[#endlessReached + 1] = last end
		for night = 7, 20 do
			if night <= last then entered[night] = (entered[night] or 0) + 1 end
			if night < last or (night == last and not rec.deathNight) then cleared[night] = (cleared[night] or 0) + 1 end
		end
	end
	table.sort(reached)
	table.sort(endlessReached)
	print(string.format("Endless, bot %s, %d seeds, random Patron picks. Median Night reached %d (all runs); %d runs got past Night 8, their median Night %d",
		cfg.bot, #records, reached[math.ceil(#reached / 2)] or 0, #endlessReached, endlessReached[math.ceil(#endlessReached / 2)] or 0))
	local heads, cells, counts = {}, {}, {}
	for night = 7, math.min(20, cfg.maxNight) do
		heads[#heads + 1] = string.format("%6d", night)
		cells[#cells + 1] = string.format("%5.1f%%", 100 * (cleared[night] or 0) / math.max(1, entered[night] or 0))
		counts[#counts + 1] = string.format("%6d", entered[night] or 0)
	end
	print(string.format("%-9s %s", "Night", table.concat(heads, " ")))
	print(string.format("%-9s %s", "runs in", table.concat(counts, " ")))
	print(string.format("%-9s %s", "clear", table.concat(cells, " ")))
elseif cfg.pacing then
	-- First run pacing: eased new profile, Nights 1 to 3, hands and discards used per round and clear rate per Night
	cfg.welcome = true
	local records = collect(runConfig({ maxNight = 3 }))
	local stats = {}
	for night = 1, 3 do
		stats[night] = { rounds = 0, hands = 0, discards = 0, cleared = 0, entered = 0 }
	end
	for _, rec in ipairs(records) do
		for _, r in ipairs(rec.rounds or {}) do
			local st = stats[r.night]
			if st then
				st.rounds, st.hands, st.discards = st.rounds + 1, st.hands + (r.hands or 0), st.discards + (r.discards or 0)
			end
		end
		local last = rec.deathNight or 99
		for night = 1, 3 do
			stats[night].entered = stats[night].entered + 1
			if night < last then stats[night].cleared = stats[night].cleared + 1 end
		end
	end
	print(string.format("First run pacing, bot %s, %d seeds, Welcome ease on. Per Night:", cfg.bot, #records))
	print(string.format("%-6s %12s %16s %12s", "Night", "hands/round", "discards/round", "Night clear"))
	for night = 1, 3 do
		local st = stats[night]
		print(string.format("%-6d %12.2f %16.2f %11.1f%%", night, st.hands / math.max(1, st.rounds), st.discards / math.max(1, st.rounds), 100 * st.cleared / math.max(1, st.entered)))
	end
elseif cfg.late then
	-- Night 4 to 8 clear rate with 3, 4 and 5 random Patrons (cleared the Night / entered the Night)
	print(string.format("Late Nights, bot %s, %d seeds per Patron count. Clear rate per Night:", cfg.bot, cfg.runs))
	print(string.format("%-9s %7s %7s %7s %7s %7s", "Patrons", "N4", "N5", "N6", "N7", "N8"))
	for _, count in ipairs({ 3, 4, 5 }) do
		local records = collect(runConfig({ lateStart = 4, lateCount = count, maxNight = 8 }))
		local entered, cleared = {}, {}
		for _, rec in ipairs(records) do
			local reached = rec.deathNight or rec.nightReached or 4
			for night = 4, 8 do
				if night <= reached then entered[night] = (entered[night] or 0) + 1 end
				if night < reached or (night == reached and not rec.deathNight) then cleared[night] = (cleared[night] or 0) + 1 end
			end
		end
		local cells = {}
		for night = 4, 8 do
			cells[#cells + 1] = string.format("%6.1f%%", 100 * (cleared[night] or 0) / math.max(1, entered[night] or 0))
		end
		print(string.format("%-9d %s", count, table.concat(cells, " ")))
	end
elseif cfg.shopEcon then
	-- Tips on hand and Patrons held at each Counter visit, Night 1 to 8 (runs that reach the visit)
	local records = collect(runConfig({ maxNight = cfg.shopNights or 8 }))
	local agg = {}
	local function key(night, round) return (night - 1) * 3 + round end
	for _, rec in ipairs(records) do
		for _, v in ipairs(rec.shopVisits or {}) do
			local a = agg[key(v.night, v.round)] or { n = 0, tips = 0, patrons = 0, dead = 0, night = v.night, round = v.round }
			a.n, a.tips, a.patrons = a.n + 1, a.tips + v.tips, a.patrons + v.patrons
			agg[key(v.night, v.round)] = a
		end
	end
	print(string.format("Shop economy, bot %s, %d seeds. Counter visits, Night 1 to 8:", cfg.bot, #records))
	print(string.format("%-12s %6s %9s %9s", "Visit", "runs", "avg Tips", "Patrons"))
	for k = 1, 3 * (cfg.shopNights or 8) do
		local a = agg[k]
		if a then print(string.format("N%d R%d %12d %9.1f %9.2f", a.night, a.round, a.n, a.tips / a.n, a.patrons / a.n)) end
	end
	-- Patrons held on entering the Night 4 and Night 8 Round 1 Counter visit (the first visit of that Night is after Round 1)
	local function held(night)
		local n, sum = 0, 0
		for _, rec in ipairs(records) do
			local last
			for _, v in ipairs(rec.shopVisits or {}) do if v.night < night or (v.night == night and v.round == 1) then last = v end end
			if last and last.night == night then n, sum = n + 1, sum + last.patrons end
		end
		return n, sum / math.max(1, n)
	end
	for _, night in ipairs({ 4, 8 }) do
		local n, avg = held(night)
		print(string.format("Patrons held at the first Night %d Counter visit: %.2f (%d runs)", night, avg, n))
	end
elseif cfg.offers then
	-- Patron offer audit, Night 1 to 8 Counter visits: how often the first roll repeats the previous visit's roll,
	-- offers a Patron already owned, or has nothing the player can afford (seats full visits are counted apart)
	local records = collect(runConfig({ maxNight = 8 }))
	local agg = {}
	for _, rec in ipairs(records) do
		local prev
		for _, v in ipairs(rec.shopVisits or {}) do
			if v.offerIds then
				local a = agg[v.night] or { n = 0, same = 0, overlap = 0, owned = 0, broke = 0, open = 0, poor = 0 }
				agg[v.night] = a
				a.n = a.n + 1
				if prev then
					local cnt, same = 0, #v.offerIds == #prev and #prev > 0
					for _, id in ipairs(v.offerIds) do
						local found = false
						for _, pid in ipairs(prev) do if pid == id then found = true end end
						if found then cnt = cnt + 1 else same = false end
					end
					if same then a.same = a.same + 1 end
					if cnt > 0 then a.overlap = a.overlap + 1 end
				end
				if v.offerOwned > 0 then a.owned = a.owned + 1 end
				if not v.seatsFull then
					a.open = a.open + 1
					if v.poolFloor > v.tips then a.poor = a.poor + 1 end -- no Patron in the pool fits: Tips are the limit, not the picker
					if #v.offerIds > 0 and v.cheapest > v.tips and v.poolFloor <= v.tips then a.broke = a.broke + 1 end
				end
				prev = v.offerIds
			end
		end
	end
	local function pct(x, n) return n > 0 and 100 * x / n or 0 end
	print(string.format("Patron offers, bot %s, %d seeds, first roll of each Counter visit (visit 1 of a run has no previous roll):", cfg.bot, #records))
	print("nothing affordable = every offer costs more than the Tips on hand although a cheaper Patron existed (picker fault). Tips under the cheapest Patron in the pool are shown apart as poor.")
	print(string.format("%-6s %7s %12s %14s %9s %20s %8s", "Night", "visits", "same offer", "any repeated", "owned", "nothing affordable", "poor"))
	local total = { n = 0, same = 0, overlap = 0, owned = 0, broke = 0, open = 0, poor = 0 }
	for night = 1, 8 do
		local a = agg[night]
		if a then
			print(string.format("%-6d %7d %11.1f%% %13.1f%% %8.1f%% %19.1f%% %7.1f%%", night, a.n, pct(a.same, a.n), pct(a.overlap, a.n), pct(a.owned, a.n), pct(a.broke, a.open), pct(a.poor, a.open)))
			for k in pairs(total) do total[k] = total[k] + a[k] end
		end
	end
	print(string.format("%-6s %7d %11.1f%% %13.1f%% %8.1f%% %19.1f%% %7.1f%%", "all", total.n, pct(total.same, total.n), pct(total.overlap, total.n), pct(total.owned, total.n), pct(total.broke, total.open), pct(total.poor, total.open)))
elseif cfg.bossLate then
	-- Boss fairness Nights 7 to 12: each boss is forced on every boss round from Night 7 up, runs are full and Endless, random Patron buys.
	-- One pass per boss covers six Nights; a cell counts only the runs that reached that Night's boss. Flag below 15 or over 85 percent (n of 20+).
	local rows = {}
	local onlyThese = cfg.bossList and ("," .. cfg.bossList .. ",")
	for _, def in ipairs(engine.BossRounds.Definitions) do
		if not onlyThese or onlyThese:find("," .. def.id .. ",", 1, true) then
			local tries, wins = {}, {}
			for _, rec in ipairs(collect(runConfig({ forceBoss = def.id, bossFrom = 7, randomPatrons = true, endless = true, maxNight = 12 }))) do
				for _, boss in ipairs(rec.bosses or {}) do
					if boss.id == def.id and boss.night >= 7 and boss.night <= 12 then
						tries[boss.night] = (tries[boss.night] or 0) + 1
						if boss.cleared then wins[boss.night] = (wins[boss.night] or 0) + 1 end
					end
				end
			end
			rows[#rows + 1] = { id = def.id, tries = tries, wins = wins }
		end
	end
	print(string.format("Boss rules Night 7 to 12, bot %s, %d runs per boss, random Patron buys. Cell = clear percent (runs that reached it).", cfg.bot, cfg.runs))
	print(string.format("%-20s %s", "boss", "N7          N8          N9          N10         N11         N12         N7-12 all"))
	for _, row in ipairs(rows) do
		local cells, allT, allW, flag = {}, 0, 0, ""
		for night = 7, 12 do
			local t, w = row.tries[night] or 0, row.wins[night] or 0
			allT, allW = allT + t, allW + w
			cells[#cells + 1] = t > 0 and string.format("%4.0f%% (%3d)", 100 * w / t, t) or "     --    "
		end
		local rate = allT > 0 and 100 * allW / allT or nil
		if rate and allT >= 20 and (rate < 15 or rate > 85) then flag = "  <-- outside" end
		print(string.format("%-20s %s  %s%s", row.id, table.concat(cells, " "), rate and string.format("%4.0f%% (%d)", rate, allT) or "--", flag))
	end
elseif cfg.bossBoons then
	-- Boss rule x Night boon, Nights 7 to 12: one cell = boss clear percent over every boss round of that run set (n attempts).
	-- Flags a cell under 5 percent (unwinnable) or over 95 percent (trivial) with at least 20 attempts. --boss-list limits the bosses.
	local onlyThese = cfg.bossList and ("," .. cfg.bossList .. ",")
	local boons = { false }
	for _, def in ipairs(engine.NightBoons.Definitions) do boons[#boons + 1] = def.id end
	local flagged, header = {}, { string.format("%-18s", "boss") }
	for _, b in ipairs(boons) do header[#header + 1] = string.format("%5.5s", b or "none") end
	print(string.format("Boss rule x boon, Nights 7 to 12, bot %s, %d runs per cell, random Patron buys, clear percent.", cfg.bot, cfg.runs))
	print(table.concat(header, " "))
	for _, def in ipairs(engine.BossRounds.Definitions) do
		if not onlyThese or onlyThese:find("," .. def.id .. ",", 1, true) then
			local cells = { string.format("%-18.18s", def.id) }
			for _, b in ipairs(boons) do
				local tries, wins = 0, 0
				for _, rec in ipairs(collect(runConfig({ forceBoss = def.id, bossFrom = 7, randomPatrons = true, endless = true, maxNight = 12, boon = b or nil }))) do
					for _, boss in ipairs(rec.bosses or {}) do
						if boss.id == def.id and boss.night >= 7 and boss.night <= 12 then
							tries = tries + 1
							if boss.cleared then wins = wins + 1 end
						end
					end
				end
				local rate = tries > 0 and 100 * wins / tries or nil
				cells[#cells + 1] = rate and string.format("%5.0f", rate) or "   --"
				if rate and tries >= 20 and (rate < 5 or rate > 95) then
					flagged[#flagged + 1] = string.format("%s + %s: %.0f%% of %d", def.id, b or "none", rate, tries)
				end
			end
			print(table.concat(cells, " "))
		end
	end
	print("Flagged (under 5 or over 95 percent, 20+ attempts): " .. (#flagged == 0 and "none" or ""))
	for _, line in ipairs(flagged) do print("  " .. line) end
elseif cfg.dailyTwists then
	-- Daily twists: win rate of every twist against the no twist baseline (same seeds, same bot). Within 15 points is fair.
	local function winRate(twist)
		local records = collect(runConfig({ dailyTwist = twist }))
		local wins = 0
		for _, rec in ipairs(records) do if rec.won then wins = wins + 1 end end
		return 100 * wins / math.max(1, #records), #records
	end
	local base, n = winRate(nil)
	print(string.format("Daily twists, bot %s, %d runs each, same seeds. Baseline (no twist) win rate %.1f%%. Outside 15 points is flagged.", cfg.bot, n, base))
	print(string.format("%-16s %8s %9s", "twist", "win", "vs base"))
	for _, def in ipairs(engine.loadEngineModule("DailyModifiers").Definitions) do
		local rate = winRate(def.id)
		print(string.format("%-16s %7.1f%% %+8.1f%s", def.id, rate, rate - base, math.abs(rate - base) > 15 and "  <-- outside" or ""))
	end
elseif cfg.pairRates then
	-- Patron synergy pairs: random 4 Patron builds from Night 4, round clear rate of every pair held together (6 pairs per build)
	local records = collect(runConfig({ lateStart = 4, lateCount = 4, maxNight = 8 }))
	local per, total, totalRounds = {}, 0, 0
	for _, rec in ipairs(records) do
		local cleared, played = 0, 0
		for _, r in ipairs(rec.rounds or {}) do
			played = played + 1
			if r.cleared then cleared = cleared + 1 end
		end
		total, totalRounds = total + cleared, totalRounds + played
		local ids = rec.startPatrons or {}
		table.sort(ids)
		for a = 1, #ids do
			for b = a + 1, #ids do
				local key = ids[a] .. " + " .. ids[b]
				local s = per[key] or { builds = 0, cleared = 0, played = 0 }
				s.builds, s.cleared, s.played = s.builds + 1, s.cleared + cleared, s.played + played
				per[key] = s
			end
		end
	end
	local avg = 100 * total / math.max(1, totalRounds)
	local rows = {}
	for key, s in pairs(per) do
		if s.builds >= (cfg.minBuilds or 25) then rows[#rows + 1] = { key = key, s = s, rate = 100 * s.cleared / math.max(1, s.played) } end
	end
	table.sort(rows, function(a, b) if a.rate ~= b.rate then return a.rate > b.rate end return a.key < b.key end)
	print(string.format("Patron pairs, bot %s, %d builds of 4 from Night 4, average round clear %.1f%%, %d pairs with %d or more builds", cfg.bot, #records, avg, #rows, cfg.minBuilds or 25))
	local function show(from, to)
		for i = from, to do
			local r = rows[i]
			if r then print(string.format("%3d. %-46s %6d %8.1f%% %+7.1f%s", i, r.key, r.s.builds, r.rate, r.rate - avg, math.abs(r.rate - avg) > 15 and "  <-- outlier" or "")) end
		end
	end
	print("Top 10:")
	show(1, math.min(10, #rows))
	print("Bottom 10:")
	show(math.max(1, #rows - 9), #rows)
elseif cfg.patronRates then
	-- Per Patron clear rate: random 4 Patron builds from Night 4, score = share of Night 4 to 8 rounds cleared by builds holding the Patron
	local records = collect(runConfig({ lateStart = 4, lateCount = 4, maxNight = 8 }))
	local per, total, totalRounds = {}, 0, 0
	for _, rec in ipairs(records) do
		local cleared, played = 0, 0
		for _, r in ipairs(rec.rounds or {}) do
			played = played + 1
			if r.cleared then cleared = cleared + 1 end
		end
		total, totalRounds = total + cleared, totalRounds + played
		for _, id in ipairs(rec.startPatrons or {}) do
			local s = per[id] or { builds = 0, cleared = 0, played = 0, nights = 0 }
			s.builds, s.cleared, s.played = s.builds + 1, s.cleared + cleared, s.played + played
			s.nights = s.nights + (rec.won and 1 or 0)
			per[id] = s
		end
	end
	local avg = 100 * total / math.max(1, totalRounds)
	local rows = {}
	for id, s in pairs(per) do rows[#rows + 1] = { id = id, s = s, rate = 100 * s.cleared / math.max(1, s.played) } end
	table.sort(rows, function(a, b) return a.rate > b.rate end)
	print(string.format("Patron rates, bot %s, %d builds of 4 from Night 4, average round clear %.1f%%", cfg.bot, #records, avg))
	print(string.format("%-22s %7s %9s %8s", "Patron", "builds", "clear", "vs avg"))
	for _, r in ipairs(rows) do
		print(string.format("%-22s %7d %8.1f%% %+7.1f%s", r.id, r.s.builds, r.rate, r.rate - avg, math.abs(r.rate - avg) > 15 and "  <-- outlier" or ""))
	end
elseif cfg.bossRules then
	-- Clear rate per boss rule on Nights 3, 6 and 9: random 4 Patron builds start on the Night, the boss is forced on that Night's boss round
	local nights = { 3, 6, 9 }
	local onlyThese = cfg.bossList and ("," .. cfg.bossList .. ",")
	local rows = {}
	for _, def in ipairs(engine.BossRounds.Definitions) do
		if not onlyThese or onlyThese:find("," .. def.id .. ",", 1, true) then
			local row = { id = def.id, minNight = def.minNight, rate = {}, tries = {} }
			for _, night in ipairs(nights) do
				local tries, wins = 0, 0
				for _, rec in ipairs(collect(runConfig({ forceBoss = def.id, bossNight = night, randomPatrons = true, maxNight = night, endless = true }))) do
					for _, boss in ipairs(rec.bosses or {}) do
						if boss.id == def.id and boss.night == night then
							tries = tries + 1
							if boss.cleared then wins = wins + 1 end
						end
					end
				end
				row.tries[night], row.rate[night] = tries, tries > 0 and 100 * wins / tries or nil
			end
			rows[#rows + 1] = row
		end
	end
	print(string.format("Boss rules, bot %s, %d runs per cell, full runs with random Patron buys, (n) = runs that reached the boss. Outside 40 to 95 percent with n of 20 or more is flagged.", cfg.bot, cfg.runs))
	print(string.format("%-22s %8s %13s %13s %13s", "boss", "minNight", "Night 3", "Night 6", "Night 9"))
	for _, row in ipairs(rows) do
		local cells, flag = {}, ""
		for _, night in ipairs(nights) do
			local r = row.rate[night]
			cells[#cells + 1] = r and string.format("%5.1f%% (%3d)", r, row.tries[night]) or "      --     "
			if r and row.tries[night] >= 20 and (r < 40 or r > 95) then flag = "  <-- outside band" end
		end
		print(string.format("%-22s %8d %s%s", row.id, row.minNight, table.concat(cells, " "), flag))
	end
elseif cfg.combos then
	-- Patron variety audit: random Patron buys, report picks, pairs and any Patron or pair that wins more than 90 percent
	cfg.randomPatrons = true
	local records = collect(runConfig())
	local wins, single, pairsT = 0, {}, {}
	for _, rec in ipairs(records) do
		if rec.won then wins = wins + 1 end
		local ids = rec.finalPatrons or {}
		table.sort(ids)
		for a = 1, #ids do
			local s = single[ids[a]] or { n = 0, w = 0 }
			s.n, s.w = s.n + 1, s.w + (rec.won and 1 or 0)
			single[ids[a]] = s
			for b = a + 1, #ids do
				local key = ids[a] .. " + " .. ids[b]
				local c = pairsT[key] or { n = 0, w = 0 }
				c.n, c.w = c.n + 1, c.w + (rec.won and 1 or 0)
				pairsT[key] = c
			end
		end
	end
	local function rows(t, minN)
		local out = {}
		for k, v in pairs(t) do if v.n >= minN then out[#out + 1] = { key = k, n = v.n, rate = v.w / v.n } end end
		table.sort(out, function(x, y) if x.n ~= y.n then return x.n > y.n end return x.key < y.key end)
		return out
	end
	print(string.format("Random Patron picks, bot %s, %d runs: win rate %.1f%%", cfg.bot, #records, 100 * wins / math.max(1, #records)))
	print("Most picked Patrons (in the final seats):")
	for i, r in ipairs(rows(single, 1)) do if i <= 10 then print(string.format("  %-22s %4d runs  win %5.1f%%", r.key, r.n, 100 * r.rate)) end end
	print("Most picked pairs:")
	for i, r in ipairs(rows(pairsT, 1)) do if i <= 10 then print(string.format("  %-40s %4d runs  win %5.1f%%", r.key, r.n, 100 * r.rate)) end end
	print("Over 90 percent (at least 5 runs):")
	local flagged = 0
	for _, r in ipairs(rows(single, 5)) do if r.rate > 0.9 then flagged = flagged + 1; print(string.format("  Patron %s %d runs %.1f%%", r.key, r.n, 100 * r.rate)) end end
	for _, r in ipairs(rows(pairsT, 5)) do if r.rate > 0.9 then flagged = flagged + 1; print(string.format("  Pair %s %d runs %.1f%%", r.key, r.n, 100 * r.rate)) end end
	if flagged == 0 then print("  none") end
elseif cfg.patronLift then
	local control = Report.aggregate(collect(runConfig()))
	print(Report.summaryLine("control (no free Patron)", control))
	local rows = {}
	local only
	if cfg.patronList then
		only = {}
		for id in tostring(cfg.patronList):gmatch("[^,]+") do only[id] = true end
	end
	for _, def in ipairs(engine.Patrons.Definitions) do
		if only and not only[def.id] then goto skipLift end
		local summary = Report.aggregate(collect(runConfig({ forcePatron = def.id })))
		local econ = summary.econ[def.id]
		table.insert(rows, {
			id = def.id, price = def.price, win = summary.winRate, median = summary.medianDeathNight,
			econTips = econ and econ.tips / summary.runs or 0,
		})
		::skipLift::
	end
	table.sort(rows, function(a, b)
		return a.win > b.win
	end)
	print(string.format("%-22s %5s %8s %8s %7s %10s", "free from start", "price", "win", "lift", "median", "Tips/run"))
	for _, row in ipairs(rows) do
		print(string.format("%-22s %5d %7.1f%% %+7.1f%% %7s %10.1f", row.id, row.price, 100 * row.win,
			100 * (row.win - control.winRate), row.median >= 99 and "won" or "N" .. row.median, row.econTips))
	end
else
	local run = runConfig()
	local records = collect(run)
	local summary = Report.aggregate(records)
	Report.printFull(string.format("%s (%s, %s)", run.bot, run.difficulty, run.deck), summary)
	print("  lowest natural boss clear rates (20+ attempts):")
	local shown = 0
	for _, row in ipairs(Report.bossRows(summary)) do
		if row.attempts >= 20 and shown < 8 then
			print(string.format("    %-18s %5.1f%% of %d", row.id, 100 * row.rate, row.attempts))
			shown = shown + 1
		end
	end
	if cfg.json then
		Report.writeJson(cfg.json, run.bot, summary)
	end
	if cfg.csv then
		Report.writeCsv(cfg.csv, records)
	end
end
