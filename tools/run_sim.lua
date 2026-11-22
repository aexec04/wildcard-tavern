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
		["--bot"] = "bot", ["--difficulty"] = "difficulty", ["--deck"] = "deck", ["--src"] = "src",
		["--json"] = "json", ["--csv"] = "csv", ["--force-boss"] = "forceBoss", ["--mode"] = "mode",
		["--force-patron"] = "forcePatron", ["--force-passes"] = "forcePasses", ["--boss-list"] = "bossList", ["--worker-out"] = "workerOut",
		["--build"] = "build", ["--patron-list"] = "patronList",
	}
	local numbers = {
		["--runs"] = "runs", ["--seed"] = "seed", ["--jobs"] = "jobs", ["--max-night"] = "maxNight",
		["--bank"] = "bank", ["--boss-night"] = "bossNight", ["--patron-offers"] = "patronOffers",
		["--pack-offers"] = "packOffers", ["--voucher-chance"] = "voucherChance",
		["--first-run"] = "firstRun", ["--stake"] = "stake", ["--night-one-discards"] = "nightOneDiscards",
		["--discards"] = "discards", ["--late-start"] = "lateStart", ["--late-count"] = "lateCount",
	}
	local flags = {
		["--ladder"] = "ladder", ["--variants"] = "variants", ["--bosses"] = "bosses",
		["--patron-lift"] = "patronLift", ["--patron-table"] = "patronTable", ["--stakes"] = "stakes", ["--endless"] = "endless",
		["--chase-table"] = "chaseTable", ["--random-patrons"] = "randomPatrons", ["--combos"] = "combos", ["--late"] = "late", ["--patron-rates"] = "patronRates", ["--shop-econ"] = "shopEcon", ["--welcome"] = "welcome", ["--pacing"] = "pacing",
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
		"--bot", run.bot, "--difficulty", run.difficulty, "--deck", run.deck,
		"--max-night", run.maxNight, "--bank", run.bank, "--seed", run.seed,
		"--src", run.src, "--boss-night", run.bossNight,
		"--runs", count, "--first-run", firstRun, "--worker-out", outPath,
	}
	if run.forceBoss then
		table.insert(parts, "--force-boss"); table.insert(parts, run.forceBoss)
	end
	if run.forcePatron then
		table.insert(parts, "--force-patron"); table.insert(parts, run.forcePatron)
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
		table.insert(parts, "--late-count"); table.insert(parts, run.lateCount)
	end
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
		for night = 9, 15 do
			if night <= last then entered[night] = (entered[night] or 0) + 1 end
			if night < last or (night == last and not rec.deathNight) then cleared[night] = (cleared[night] or 0) + 1 end
		end
	end
	table.sort(reached)
	table.sort(endlessReached)
	print(string.format("Endless, bot %s, %d seeds, random Patron picks. Median Night reached %d (all runs); %d runs got past Night 8, their median Night %d",
		cfg.bot, #records, reached[math.ceil(#reached / 2)] or 0, #endlessReached, endlessReached[math.ceil(#endlessReached / 2)] or 0))
	print(string.format("%-9s %s", "Night", "9      10     11     12     13     14     15"))
	local cells = {}
	for night = 9, 15 do
		cells[#cells + 1] = string.format("%5.1f%%", 100 * (cleared[night] or 0) / math.max(1, entered[night] or 0))
	end
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
	local records = collect(runConfig({ maxNight = 8 }))
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
	for k = 1, 24 do
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
	for _, def in ipairs(engine.Patrons.Definitions) do
		local summary = Report.aggregate(collect(runConfig({ forcePatron = def.id })))
		local econ = summary.econ[def.id]
		table.insert(rows, {
			id = def.id, price = def.price, win = summary.winRate, median = summary.medianDeathNight,
			econTips = econ and econ.tips / summary.runs or 0,
		})
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
