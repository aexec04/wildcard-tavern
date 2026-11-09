--[[
	Quests.lua
	Three daily quests per UTC day, picked deterministically from a registry (the same three for every player on a
	given day, so friends can compare). Pure Lua, no Roblox APIs. Server authoritative: the server turns run
	counters into progress deltas (see Server syncProfileFromSession) and calls Quests.apply.

	A quest reads one run counter (the `counter` field):
		hands     hands played                       state.handsPlayedTotal
		pairs     Pair hands played                  state.handStats["Pair"]
		discards  discards used                      state.discardsUsedTotal
		flushWins rounds cleared with a Flush        state.flushClears
		packs     Packs bought                       state.packsBought
		bosses    Boss Rounds cleared                state.bossesCleared
	Daily, Weekly and Seed runs count too.

	Profile: quests = { day, ids = { questId x3 }, progress = { [questId] = n }, done = { [questId] = true } },
	questsDone (all-time count, read by Engine/Unlocks), questSnapshot is kept by the server per session, not saved.
]]

local TavernRank = require(script.Parent.TavernRank)

local Quests = {}

Quests.PER_DAY = 3
Quests.MAX_PENDING_TIPS = TavernRank.MAX_PENDING_TIPS

Quests.Definitions = {
	{ id = "pairs_3", name = "Pair Up", icon = "👯", desc = "Play 3 Pair hands.", counter = "pairs", goal = 3, xp = 40, tips = 2 },
	{ id = "flush_clear", name = "Flush Finish", icon = "🌊", desc = "Clear a round with a Flush.", counter = "flushWins", goal = 1, xp = 60, tips = 3 },
	{ id = "buy_pack", name = "Pack Shopper", icon = "🎁", desc = "Buy a Pack.", counter = "packs", goal = 1, xp = 40, tips = 2 },
	{ id = "discard_5", name = "Fresh Draw", icon = "♻️", desc = "Use 5 discards.", counter = "discards", goal = 5, xp = 40, tips = 2 },
	{ id = "boss_win", name = "Boss Beater", icon = "🥊", desc = "Win a Boss Round.", counter = "bosses", goal = 1, xp = 80, tips = 4 },
	{ id = "hands_10", name = "Busy Hands", icon = "🃏", desc = "Play 10 hands.", counter = "hands", goal = 10, xp = 50, tips = 2 },
}

function Quests.getById(id)
	for _, q in ipairs(Quests.Definitions) do
		if q.id == id then
			return q
		end
	end
	return nil
end

-- The three quest ids of a UTC day number: a small LCG seeded from the day, no global state, same everywhere.
function Quests.rollFor(day)
	local pool = {}
	for _, q in ipairs(Quests.Definitions) do
		pool[#pool + 1] = q.id
	end
	-- Park-Miller generator: every product stays below 2^53, so Lua 5.3 and Luau give the same numbers.
	local seed = (math.floor(day) * 40503 + 7919) % 2147483647
	if seed == 0 then seed = 1 end
	local function nextInt(n)
		seed = (seed * 48271) % 2147483647
		return (math.floor(seed / 256) % n) + 1
	end
	local ids = {}
	for _ = 1, math.min(Quests.PER_DAY, #pool) do
		ids[#ids + 1] = table.remove(pool, nextInt(#pool))
	end
	return ids
end

local function freshState(day)
	return { day = day, ids = Quests.rollFor(day), progress = {}, done = {} }
end

-- Makes sure profile.quests is today's. Returns true when it was rolled (new day).
function Quests.ensureDay(profile, day)
	local q = profile.quests
	if type(q) == "table" and q.day == day and type(q.ids) == "table" and #q.ids == Quests.PER_DAY then
		q.progress = q.progress or {}
		q.done = q.done or {}
		return false
	end
	profile.quests = freshState(day)
	return true
end

-- Adds counter deltas ({ pairs = 2, hands = 5, ... }, whole numbers, never negative) to today's quests.
-- Completed quests pay their XP (TavernRank.addXp) and bank their Tips for the next run.
-- Returns the completed quests (definitions) and the rank ups / rewards caused by their XP.
function Quests.apply(profile, day, deltas)
	Quests.ensureDay(profile, day)
	local q = profile.quests
	local completed, rankUps, granted = {}, {}, {}
	for _, id in ipairs(q.ids) do
		local def = Quests.getById(id)
		if def and not q.done[id] then
			local add = math.floor(tonumber(deltas[def.counter]) or 0)
			if add > 0 then
				q.progress[id] = math.min(def.goal, (q.progress[id] or 0) + add)
			end
			if (q.progress[id] or 0) >= def.goal then
				q.done[id] = true
				profile.questsDone = (profile.questsDone or 0) + 1
				profile.pendingStartTips = math.min(Quests.MAX_PENDING_TIPS, (profile.pendingStartTips or 0) + def.tips)
				local _, ups, rewards = TavernRank.addXp(profile, def.xp)
				for _, r in ipairs(ups) do rankUps[#rankUps + 1] = r end
				for _, r in ipairs(rewards) do granted[#granted + 1] = r end
				completed[#completed + 1] = def
			end
		end
	end
	return completed, rankUps, granted
end

-- What the client draws.
function Quests.view(profile, day, secondsLeft)
	Quests.ensureDay(profile, day)
	local q = profile.quests
	local rows = {}
	for _, id in ipairs(q.ids) do
		local def = Quests.getById(id)
		if def then
			rows[#rows + 1] = {
				id = id, name = def.name, icon = def.icon, desc = def.desc,
				progress = math.min(def.goal, q.progress[id] or 0), goal = def.goal,
				done = q.done[id] == true, xp = def.xp, tips = def.tips,
			}
		end
	end
	return { day = day, quests = rows, secondsLeft = secondsLeft, doneCount = (function()
		local n = 0
		for _, r in ipairs(rows) do if r.done then n = n + 1 end end
		return n
	end)() }
end

-- Turns run counters into deltas against a per-session snapshot (monotonic: a counter that drops, e.g. after
-- One More Round restores the round start, never counts twice). `snapshot` is updated in place.
function Quests.deltas(snapshot, counters)
	local out = {}
	for key, now in pairs(counters) do
		local before = snapshot[key] or 0
		if now > before then
			out[key] = now - before
			snapshot[key] = now
		end
	end
	return out
end

-- The counters of a RunState.
function Quests.countersOf(state)
	local stats = state.handStats or {}
	return {
		hands = state.handsPlayedTotal or 0,
		pairs = stats["Pair"] or 0,
		discards = state.discardsUsedTotal or 0,
		flushWins = state.flushClears or 0,
		packs = state.packsBought or 0,
		bosses = state.bossesCleared or 0,
	}
end

return Quests
