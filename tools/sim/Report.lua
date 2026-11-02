--[[
	Report.lua
	Turns per-run records from Sim.runOne into the balance report: aggregates
	them, prints a summary, and writes CSV/JSON. Also (de)serializes records
	so run_sim.lua can gather results from parallel worker processes.
]]

local Report = {}

local function sortedKeys(t)
	local keys = {}
	for key in pairs(t) do
		table.insert(keys, key)
	end
	table.sort(keys, function(a, b)
		return tostring(a) < tostring(b)
	end)
	return keys
end

-- ===== Worker record transport (a Lua table literal per line) =====

local function serialize(value)
	local kind = type(value)
	if kind == "number" or kind == "boolean" then
		return tostring(value)
	elseif kind == "string" then
		return string.format("%q", value)
	elseif kind == "table" then
		local parts = {}
		for _, key in ipairs(sortedKeys(value)) do
			local keyText = type(key) == "number" and ("[" .. key .. "]") or ("[" .. string.format("%q", key) .. "]")
			parts[#parts + 1] = keyText .. "=" .. serialize(value[key])
		end
		return "{" .. table.concat(parts, ",") .. "}"
	end
	return "nil"
end

Report.serialize = serialize

function Report.deserialize(line)
	local chunk, err = load("return " .. line, "record", "t", {})
	if not chunk then
		error("Bad worker record: " .. tostring(err))
	end
	return chunk()
end

-- ===== Aggregation =====

local function median(values)
	if #values == 0 then
		return 0
	end
	local copy = {}
	for i, v in ipairs(values) do
		copy[i] = v
	end
	table.sort(copy)
	return copy[math.ceil(#copy / 2)]
end

local function mean(values)
	if #values == 0 then
		return 0
	end
	local total = 0
	for _, v in ipairs(values) do
		total = total + v
	end
	return total / #values
end

function Report.aggregate(records)
	local s = {
		runs = #records,
		wins = 0,
		softLocks = 0,
		deathsByNight = {},
		deaths = 0,
		deathsOnBoss = 0,
		killers = {},
		bosses = {},
		patrons = {},
		levels = {},
		econ = {},
		rerolls = 0,
		recipesUsed = 0,
	}
	local deathNights, deathPcts, shopTips = {}, {}, {}

	for _, rec in ipairs(records) do
		s.softLocks = s.softLocks + rec.softLocks
		s.rerolls = s.rerolls + rec.rerolls
		s.recipesUsed = s.recipesUsed + rec.recipesUsed
		if rec.won then
			s.wins = s.wins + 1
			-- Winners rank past every losing run for the median.
			table.insert(deathNights, 99)
		elseif rec.deathNight then
			s.deaths = s.deaths + 1
			s.deathsByNight[rec.deathNight] = (s.deathsByNight[rec.deathNight] or 0) + 1
			table.insert(deathNights, rec.deathNight)
			table.insert(deathPcts, rec.deathPct)
			if rec.deathOnBoss then
				s.deathsOnBoss = s.deathsOnBoss + 1
			end
			if rec.deathBoss then
				s.killers[rec.deathBoss] = (s.killers[rec.deathBoss] or 0) + 1
			end
		end
		for _, tips in ipairs(rec.tipsAtShop) do
			table.insert(shopTips, tips)
		end
		for _, boss in ipairs(rec.bosses) do
			local b = s.bosses[boss.id] or { attempts = 0, clears = 0 }
			s.bosses[boss.id] = b
			b.attempts = b.attempts + 1
			if boss.cleared then
				b.clears = b.clears + 1
			end
		end
		for id in pairs(rec.patronsBought) do
			local p = s.patrons[id] or { runs = 0, wins = 0 }
			s.patrons[id] = p
			p.runs = p.runs + 1
			if rec.won then
				p.wins = p.wins + 1
			end
		end
		for name, level in pairs(rec.levels) do
			s.levels[name] = (s.levels[name] or 0) + level
		end
		for id, tips in pairs(rec.econTips) do
			local e = s.econ[id] or { runs = 0, tips = 0 }
			s.econ[id] = e
			e.runs = e.runs + 1
			e.tips = e.tips + tips
		end
	end

	s.winRate = s.runs > 0 and s.wins / s.runs or 0
	s.medianDeathNight = median(deathNights)
	s.medianPctAtDeath = median(deathPcts)
	s.meanTipsAtShop = mean(shopTips)
	s.medianTipsAtShop = median(shopTips)
	s.bossDeathShare = s.deaths > 0 and s.deathsOnBoss / s.deaths or 0
	s.night1DeathRate = s.runs > 0 and (s.deathsByNight[1] or 0) / s.runs or 0
	local levelTotal, pairLevels = 0, 0
	for name, level in pairs(s.levels) do
		levelTotal = levelTotal + level
		if name == "Pair" or name == "Two Pair" then
			pairLevels = pairLevels + level
		end
	end
	s.levelsPerRun = s.runs > 0 and levelTotal / s.runs or 0
	s.pairLevelShare = levelTotal > 0 and pairLevels / levelTotal or 0
	return s
end

-- ===== Output =====

local function pct(x)
	return string.format("%.1f%%", 100 * x)
end

local function nightText(n)
	return n >= 99 and "won" or ("N" .. n)
end

function Report.summaryLine(label, s)
	local parts = {}
	for night = 1, 10 do
		local deaths = s.deathsByNight[night] or 0
		if deaths > 0 then
			parts[#parts + 1] = string.format("N%d %s", night, pct(deaths / s.runs))
		end
	end
	return string.format("%-24s win %6s | median %-3s | N1 death %6s | boss deaths %6s | %s",
		label, pct(s.winRate), nightText(s.medianDeathNight), pct(s.night1DeathRate),
		pct(s.bossDeathShare), table.concat(parts, ", "))
end

function Report.printFull(label, s)
	print(Report.summaryLine(label, s))
	print(string.format("  runs %d, soft-locks %d, median %% of target at death %s, Tips at shop: mean %.1f, median %d",
		s.runs, s.softLocks, pct(s.medianPctAtDeath), s.meanTipsAtShop, s.medianTipsAtShop))
	print(string.format("  per run: %.2f rerolls, %.2f recipes used, %.2f hand levels (Pair+Two Pair share %s)",
		s.rerolls / s.runs, s.recipesUsed / s.runs, s.levelsPerRun, pct(s.pairLevelShare)))

	local levels = {}
	for _, name in ipairs(sortedKeys(s.levels)) do
		table.insert(levels, string.format("%s %d", name, s.levels[name]))
	end
	print("  levels: " .. table.concat(levels, ", "))

	local killers = sortedKeys(s.killers)
	table.sort(killers, function(a, b)
		if s.killers[a] ~= s.killers[b] then
			return s.killers[a] > s.killers[b]
		end
		return a < b
	end)
	local top = {}
	for i = 1, math.min(10, #killers) do
		table.insert(top, string.format("%s %d", killers[i], s.killers[killers[i]]))
	end
	print("  top killers: " .. table.concat(top, ", "))
end

function Report.bossRows(s)
	local rows = {}
	for _, id in ipairs(sortedKeys(s.bosses)) do
		local b = s.bosses[id]
		table.insert(rows, { id = id, attempts = b.attempts, clears = b.clears, rate = b.clears / b.attempts })
	end
	table.sort(rows, function(a, b)
		return a.rate < b.rate
	end)
	return rows
end

function Report.patronRows(s)
	local rows = {}
	for _, id in ipairs(sortedKeys(s.patrons)) do
		local p = s.patrons[id]
		local winRate = p.wins / p.runs
		local rest = s.runs - p.runs
		local restRate = rest > 0 and (s.wins - p.wins) / rest or 0
		table.insert(rows, { id = id, pickRate = p.runs / s.runs, winRate = winRate, lift = winRate - restRate })
	end
	table.sort(rows, function(a, b)
		return a.lift > b.lift
	end)
	return rows
end

local function toJson(value)
	local kind = type(value)
	if kind == "number" then
		if value ~= value or value == math.huge or value == -math.huge then
			return "null"
		end
		return tostring(value)
	elseif kind == "boolean" then
		return tostring(value)
	elseif kind == "string" then
		return '"' .. value:gsub('[\\"]', "\\%0") .. '"'
	elseif kind == "table" then
		local parts = {}
		if #value > 0 then
			for _, v in ipairs(value) do
				parts[#parts + 1] = toJson(v)
			end
			return "[" .. table.concat(parts, ",") .. "]"
		end
		for _, key in ipairs(sortedKeys(value)) do
			parts[#parts + 1] = '"' .. tostring(key) .. '":' .. toJson(value[key])
		end
		return "{" .. table.concat(parts, ",") .. "}"
	end
	return "null"
end

function Report.writeJson(path, label, s)
	local file = assert(io.open(path, "w"))
	file:write(toJson({ label = label, summary = s, bosses = Report.bossRows(s), patrons = Report.patronRows(s) }), "\n")
	file:close()
end

-- One row per run, for spreadsheets.
function Report.writeCsv(path, records)
	local file = assert(io.open(path, "w"))
	file:write("seed,won,deathNight,deathRound,deathOnBoss,deathBoss,deathPct,softLocks,finalTips,patrons\n")
	for _, rec in ipairs(records) do
		file:write(string.format("%s,%s,%s,%s,%s,%s,%s,%d,%d,%s\n",
			tostring(rec.seed), tostring(rec.won), tostring(rec.deathNight or ""), tostring(rec.deathRound or ""),
			tostring(rec.deathOnBoss or ""), tostring(rec.deathBoss or ""), rec.deathPct and string.format("%.3f", rec.deathPct) or "",
			rec.softLocks, rec.finalTips, table.concat(rec.finalPatrons, " ")))
	end
	file:close()
end

return Report
