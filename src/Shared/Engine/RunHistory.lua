--[[
	RunHistory.lua
	The last 20 finished runs and the lifetime stats of the Tavern Stats page. Pure Lua, no Roblox APIs.

	Profile fields:
	  runHistory = { entry, ... }   newest first, at most RunHistory.CAP (20)
	    entry = { t = unix seconds, mode, road = region id, stake, night, won, score, hands,
	              patrons = { id, ... } (at most 8), bestHand = { name, score } | nil }
	  lifetime = { bestHandScore, tipsEarned, bestNightByStake = { ["1"] = n }, patronWins = { [patronId] = wins },
	               bossRecord = { [bossId] = { w, l } }, regulars = { "boss:<id>" | "patron:<id>", ... } oldest first }
	  The Tavern Regulars (Engine/Regulars.lua) read bossRecord and regulars: a Regular is added the first time you
	  beat that Boss Round or win a run with that Patron.

	Runs, wins and hands played come from profile.stats (already saved). The server records a run only when it ends
	normally (Game Over), never a tutorial or an abandoned run; every mode is tagged (standard, daily, weekly, seed,
	challenge, rush, quick). All input is cleaned on load (cleanSaved), so a damaged save can never break the page.
]]

local RunHistory = {}

RunHistory.CAP = 20
RunHistory.MAX_PATRONS = 8
RunHistory.MAX_REGULARS = 60
RunHistory.MAX_BOSS_RECORDS = 80
RunHistory.Modes = { "standard", "daily", "weekly", "seed", "challenge", "rush", "quick" }

local MODE_OK = {}
for _, m in ipairs(RunHistory.Modes) do MODE_OK[m] = true end

local function whole(n, lo, hi)
	if type(n) ~= "number" or n ~= n or n == math.huge or n == -math.huge then
		return nil
	end
	return math.max(lo, math.min(hi, math.floor(n)))
end

-- A raw entry (state data or a saved one) into a clean entry, or nil when unusable.
function RunHistory.cleanEntry(raw)
	if type(raw) ~= "table" then
		return nil
	end
	local night = whole(raw.night, 1, 500)
	local t = whole(raw.t, 0, 4e9)
	if not night or not t then
		return nil
	end
	local patrons = {}
	if type(raw.patrons) == "table" then
		for _, id in ipairs(raw.patrons) do
			if type(id) == "string" and #id <= 40 and #patrons < RunHistory.MAX_PATRONS then
				patrons[#patrons + 1] = id
			end
		end
	end
	local bestHand
	if type(raw.bestHand) == "table" and type(raw.bestHand.name) == "string" and #raw.bestHand.name <= 30 then
		local s = whole(raw.bestHand.score, 0, 9e15)
		if s then
			bestHand = { name = raw.bestHand.name, score = s }
		end
	end
	return {
		t = t,
		mode = MODE_OK[raw.mode] and raw.mode or "standard",
		road = type(raw.road) == "string" and #raw.road <= 40 and raw.road or nil,
		stake = whole(raw.stake, 1, 8) or 1,
		night = night,
		won = raw.won == true,
		score = whole(raw.score, 0, 9e15) or 0,
		hands = whole(raw.hands, 0, 1e6) or 0,
		patrons = patrons,
		bestHand = bestHand,
		seed = type(raw.seed) == "string" and raw.seed ~= "" and #raw.seed <= 24 and raw.seed or nil,
	}
end

function RunHistory.newLifetime()
	return { bestHandScore = 0, tipsEarned = 0, bestNightByStake = {}, patronWins = {}, bossRecord = {}, regulars = {} }
end

function RunHistory.cleanLifetime(raw)
	local out = RunHistory.newLifetime()
	if type(raw) ~= "table" then
		return out
	end
	out.bestHandScore = whole(raw.bestHandScore, 0, 9e15) or 0
	out.tipsEarned = whole(raw.tipsEarned, 0, 9e15) or 0
	if type(raw.bestNightByStake) == "table" then
		for k, v in pairs(raw.bestNightByStake) do
			local stake, night = tonumber(k), whole(v, 1, 500)
			if stake and stake >= 1 and stake <= 8 and stake == math.floor(stake) and night then
				out.bestNightByStake[tostring(stake)] = night
			end
		end
	end
	if type(raw.patronWins) == "table" then
		local count = 0
		for id, wins in pairs(raw.patronWins) do
			local w = whole(wins, 1, 1e6)
			if type(id) == "string" and #id <= 40 and w and count < 200 then
				out.patronWins[id] = w
				count = count + 1
			end
		end
	end
	if type(raw.bossRecord) == "table" then
		local count = 0
		for id, rec in pairs(raw.bossRecord) do
			if type(id) == "string" and #id <= 40 and type(rec) == "table" and count < RunHistory.MAX_BOSS_RECORDS then
				local w, l = whole(rec.w, 0, 1e6) or 0, whole(rec.l, 0, 1e6) or 0
				if w + l > 0 then
					out.bossRecord[id] = { w = w, l = l }
					count = count + 1
				end
			end
		end
	end
	if type(raw.regulars) == "table" then
		local seen = {}
		for _, key in ipairs(raw.regulars) do
			if type(key) == "string" and #key <= 50 and not seen[key] and (key:sub(1, 5) == "boss:" or key:sub(1, 7) == "patron:")
				and #out.regulars < RunHistory.MAX_REGULARS then
				seen[key] = true
				out.regulars[#out.regulars + 1] = key
			end
		end
	end
	return out
end

-- A new Regular the first time (key is "boss:<id>" or "patron:<id>"); the list keeps the newest MAX_REGULARS.
local function addRegular(life, key)
	for _, existing in ipairs(life.regulars) do
		if existing == key then
			return false
		end
	end
	life.regulars[#life.regulars + 1] = key
	while #life.regulars > RunHistory.MAX_REGULARS do
		table.remove(life.regulars, 1)
	end
	return true
end

-- { runHistory, lifetime } cleaned from raw saved values.
function RunHistory.cleanSaved(rawHistory, rawLifetime)
	local list = {}
	if type(rawHistory) == "table" then
		for _, raw in ipairs(rawHistory) do
			local entry = RunHistory.cleanEntry(raw)
			if entry and #list < RunHistory.CAP then
				list[#list + 1] = entry
			end
		end
	end
	return list, RunHistory.cleanLifetime(rawLifetime)
end

-- The mode of a session: pass the flags the server already has.
function RunHistory.modeOf(flags)
	flags = flags or {}
	if flags.rush then return "rush" end
	if flags.challenge then return "challenge" end
	if flags.daily then return "daily" end
	if flags.weekly then return "weekly" end
	if flags.seeded then return "seed" end
	if flags.quick then return "quick" end
	return "standard"
end

-- Builds an entry from a finished RunState. `region` is the road's region id (the server knows it).
function RunHistory.entryFromState(state, mode, region, now, seed)
	local patrons = {}
	for _, id in ipairs(state.patronsUsedOrder or {}) do
		if #patrons < RunHistory.MAX_PATRONS then
			patrons[#patrons + 1] = id
		end
	end
	return RunHistory.cleanEntry({
		t = now, mode = mode, road = region, stake = state.stake or 1, night = state.night or 1,
		won = state.wonRun == true, score = state.totalScore or 0, hands = state.handsPlayedTotal or 0,
		patrons = patrons,
		bestHand = state.bestHand and { name = state.bestHand.name, score = state.bestHand.score } or nil,
		seed = seed ~= nil and tostring(seed) or nil,
	})
end

-- Records one finished run: newest first, capped, lifetime numbers folded in. Returns true when saved.
-- `tipsEarned` is the run's Tips income (RunState.tipsEarnedTotal).
function RunHistory.record(profile, entry, tipsEarned)
	entry = RunHistory.cleanEntry(entry)
	if not entry then
		return false
	end
	profile.runHistory = profile.runHistory or {}
	table.insert(profile.runHistory, 1, entry)
	while #profile.runHistory > RunHistory.CAP do
		table.remove(profile.runHistory)
	end
	local life = RunHistory.cleanLifetime(profile.lifetime)
	profile.lifetime = life
	if entry.bestHand and entry.bestHand.score > life.bestHandScore then
		life.bestHandScore = entry.bestHand.score
	end
	life.tipsEarned = math.min(9e15, life.tipsEarned + (whole(tipsEarned, 0, 1e9) or 0))
	local key = tostring(entry.stake)
	if entry.night > (life.bestNightByStake[key] or 0) then
		life.bestNightByStake[key] = entry.night
	end
	if entry.won then
		for _, id in ipairs(entry.patrons) do
			life.patronWins[id] = (life.patronWins[id] or 0) + 1
			addRegular(life, "patron:" .. id) -- first win with a Patron makes them a Regular
		end
	end
	return true
end

-- A Boss Round ended: won = you cleared it. The first clear makes the boss a Regular. Returns true if a Regular was added.
function RunHistory.recordBoss(profile, bossId, won)
	if type(bossId) ~= "string" or #bossId > 40 or bossId == "unknown" then
		return false
	end
	local life = RunHistory.cleanLifetime(profile.lifetime)
	profile.lifetime = life
	local rec = life.bossRecord[bossId]
	if not rec then
		local count = 0
		for _ in pairs(life.bossRecord) do count = count + 1 end
		if count >= RunHistory.MAX_BOSS_RECORDS then
			return false
		end
		rec = { w = 0, l = 0 }
		life.bossRecord[bossId] = rec
	end
	if won then
		rec.w = math.min(1e6, rec.w + 1)
		return addRegular(life, "boss:" .. bossId)
	end
	rec.l = math.min(1e6, rec.l + 1)
	return false
end

-- Quick Run personal best (its own board-free record): a win beats any loss, then the higher Night, then the score.
function RunHistory.cleanQuickBest(raw)
	if type(raw) ~= "table" then
		return nil
	end
	local night, score = whole(raw.night, 1, 500), whole(raw.score, 0, 9e15)
	if not night or not score then
		return nil
	end
	return { won = raw.won == true, night = night, score = score }
end

-- Updates profile.quickBest from a finished Quick Run entry. Returns true when it improved.
function RunHistory.recordQuickBest(profile, entry)
	entry = RunHistory.cleanEntry(entry)
	if not entry or entry.mode ~= "quick" then
		return false
	end
	local old = RunHistory.cleanQuickBest(profile.quickBest)
	local better = not old
		or (entry.won and not old.won)
		or (entry.won == old.won and (entry.night > old.night or (entry.night == old.night and entry.score > old.score)))
	if better then
		profile.quickBest = { won = entry.won, night = entry.night, score = entry.score }
	end
	return better
end

-- Most wins with one Patron (ties: the alphabetically first id so the answer is stable). nil when no wins yet.
function RunHistory.favoritePatron(lifetime)
	local bestId, bestWins
	for id, wins in pairs((lifetime and lifetime.patronWins) or {}) do
		if not bestId or wins > bestWins or (wins == bestWins and id < bestId) then
			bestId, bestWins = id, wins
		end
	end
	if bestId then
		return { id = bestId, wins = bestWins }
	end
	return nil
end

-- What the client draws: three headline numbers, the last runs (up to CAP, for the sparkline) and the lifetime list.
function RunHistory.view(profile)
	local life = RunHistory.cleanLifetime(profile.lifetime)
	local stats = profile.stats or {}
	local runs = {}
	for i, entry in ipairs(profile.runHistory or {}) do
		if i > RunHistory.CAP then break end
		runs[i] = entry
	end
	local bestNight = 0
	for _, night in pairs(life.bestNightByStake) do
		if night > bestNight then bestNight = night end
	end
	return {
		runs = stats.runsStarted or 0,
		wins = stats.runsWon or 0,
		hands = stats.handsPlayedTotal or 0,
		bestHandScore = life.bestHandScore,
		tipsEarned = life.tipsEarned,
		bestNightByStake = life.bestNightByStake,
		bestNight = math.max(bestNight, stats.bestNightReached or 0),
		favoritePatron = RunHistory.favoritePatron(life),
		quickBest = RunHistory.cleanQuickBest(profile.quickBest),
		recent = runs,
	}
end

return RunHistory
