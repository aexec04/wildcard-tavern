--[[
	Shared/Engine/Leaderboards.lua
	Which Daily/Weekly board a run submits to, and the OrderedDataStore name
	for that board. Pure Lua (no Roblox APIs) so the routing is covered by
	the local test suite; Server/init.server.lua owns the actual DataStore
	calls.

	Every Daily and Weekly period has two boards:
	  - "Standard" -- runs that never used the paid continue.
	  - "Revived"  -- runs that did (RunState's `revived` flag).
	A revived run never reaches the Standard board.

	Store names are also bucketed on SeededRng.VERSION. A seed plays out
	differently once the rng changes, so scores from different versions
	aren't comparable and each version gets fresh boards:
	  DailyChallenge_Standard_v2_2026-11-03
	  WeeklyChallenge_Revived_v2_W2911
]]

local SeededRng = require(script.Parent.SeededRng)

local Leaderboards = {}

Leaderboards.STANDARD = "Standard"
Leaderboards.REVIVED = "Revived"
Leaderboards.Boards = { Leaderboards.STANDARD, Leaderboards.REVIVED }

local STORE_PREFIX = {
	daily = "DailyChallenge",
	weekly = "WeeklyChallenge",
	endless = "EndlessMode", -- all-time board, one store per board, period key "alltime"
}

-- The board a run's progress belongs on right now.
function Leaderboards.boardFor(state)
	if state and state.revived then
		return Leaderboards.REVIVED
	end
	return Leaderboards.STANDARD
end

function Leaderboards.isBoard(board)
	return board == Leaderboards.STANDARD or board == Leaderboards.REVIVED
end

-- kind: "daily" | "weekly"; board: Leaderboards.STANDARD | REVIVED;
-- periodKey: SeededRng.dailyDateKey() / weeklyDateKey(). `version`
-- defaults to the current SeededRng.VERSION (overridable for tests).
function Leaderboards.storeName(kind, board, periodKey, version)
	local prefix = STORE_PREFIX[kind]
	assert(prefix, "Leaderboards.storeName: unknown kind " .. tostring(kind))
	assert(Leaderboards.isBoard(board), "Leaderboards.storeName: unknown board " .. tostring(board))
	assert(type(periodKey) == "string" and periodKey ~= "", "Leaderboards.storeName: periodKey required")
	return string.format("%s_%s_v%d_%s", prefix, board, version or SeededRng.VERSION, periodKey)
end

-- ===== Friends scope =====
-- The Friends tab shows only the player's Roblox friends (plus themselves) from the SAME store
-- the Everyone board reads. To stay cheap on the DataStore budget the server reads one sorted
-- page per store and one friend list per player, each cached for FRIENDS_CACHE_SECONDS.
Leaderboards.EVERYONE = "everyone"
Leaderboards.GLOBAL = "global" -- the whole game; same data as EVERYONE, but read through the 60s page cache
Leaderboards.FRIENDS = "friends"
Leaderboards.FRIENDS_CACHE_SECONDS = 60
Leaderboards.FRIENDS_PAGE_SIZE = 100 -- how deep into the sorted board friends are looked up
Leaderboards.MAX_FRIENDS = 200 -- friend list cap per lookup

function Leaderboards.isScope(scope)
	return scope == Leaderboards.EVERYONE or scope == Leaderboards.GLOBAL or scope == Leaderboards.FRIENDS
end

-- Tiny time-to-live cache. `clock` is a function returning seconds (os.clock on the server).
function Leaderboards.newCache(ttl, clock)
	local cache = { entries = {} }
	function cache.get(key)
		local e = cache.entries[key]
		if e and clock() - e.at < ttl then
			return e.value
		end
		cache.entries[key] = nil
		return nil
	end
	function cache.set(key, value)
		cache.entries[key] = { value = value, at = clock() }
		return value
	end
	return cache
end

-- entries: sorted board rows ({ userId = n, ... }, best first). friendIds: { [userId] = true }.
-- Keeps the player's own row and their friends' rows in board order, at most `limit` rows.
-- Returns copies with a `rank` field set to the position on the Friends board.
function Leaderboards.friendRows(entries, friendIds, selfId, limit)
	local out = {}
	for _, entry in ipairs(entries or {}) do
		local id = entry.userId
		if id ~= nil and (id == selfId or (friendIds and friendIds[id])) then
			local row = {}
			for k, v in pairs(entry) do row[k] = v end
			row.rank = #out + 1
			table.insert(out, row)
			if limit and #out >= limit then break end
		end
	end
	return out
end

-- ===== Endless board =====
-- Highest Night reached in Endless Mode, then the run's total score as the tiebreak. One all-time board per
-- Standard / Revived. Scores are computed from the server's own run state, never sent by a client.
Leaderboards.ENDLESS_PERIOD = "alltime"
Leaderboards.SCORE_MULTIPLIER = 1000000000 -- combined = night * this + total score (the score is clamped below it)
Leaderboards.MAX_ENDLESS_NIGHT = 500 -- a sanity ceiling: nothing above it is ever written

function Leaderboards.combine(night, score)
	score = math.max(0, math.min(Leaderboards.SCORE_MULTIPLIER - 1, math.floor(score or 0)))
	return night * Leaderboards.SCORE_MULTIPLIER + score
end

function Leaderboards.decode(combined)
	return math.floor(combined / Leaderboards.SCORE_MULTIPLIER), combined % Leaderboards.SCORE_MULTIPLIER
end

-- The Endless entry of a run, or nil when the run does not qualify. `flags` = { isDaily, isWeekly, isSeeded, isTutorial }.
-- Qualifies: a normal run (no seed, no tutorial, no Boss Rush, no Challenge twist) that has won and is now past the
-- Night cap, with sane numbers. Returns night, score.
function Leaderboards.endlessEntry(state, flags)
	flags = flags or {}
	if type(state) ~= "table" or flags.isDaily or flags.isWeekly or flags.isSeeded or flags.isTutorial then
		return nil
	end
	if state.rush or state.challenge or not state.wonRun then
		return nil
	end
	local cap = state.config and state.config.nightCap or 8
	local night = state.night
	if type(night) ~= "number" or night ~= night or night <= cap or night > Leaderboards.MAX_ENDLESS_NIGHT then
		return nil
	end
	local best = state.totalScore or (state.bestHand and state.bestHand.score) or 0 -- total score of the run (older states: best hand)
	if type(best) ~= "number" or best ~= best or best < 0 then
		return nil
	end
	return math.floor(night), math.min(Leaderboards.SCORE_MULTIPLIER - 1, math.floor(best))
end

-- True when (night, score) beats the pending entry (higher Night, or the same Night and a higher hand).
function Leaderboards.improves(pending, night, score)
	if not pending then
		return true
	end
	return night > pending.depth or (night == pending.depth and score > pending.tips)
end

-- Sorts board rows best first: higher depth, then higher tips. Returns a new list, ties keep their order.
function Leaderboards.sortRows(rows)
	local indexed = {}
	for i, row in ipairs(rows) do
		indexed[i] = { row = row, i = i }
	end
	table.sort(indexed, function(a, b)
		if a.row.depth ~= b.row.depth then return a.row.depth > b.row.depth end
		if a.row.tips ~= b.row.tips then return a.row.tips > b.row.tips end
		return a.i < b.i
	end)
	local out = {}
	for i, entry in ipairs(indexed) do
		out[i] = entry.row
	end
	return out
end

-- The first `limit` rows of a cached sorted page, each with its rank. Returns copies.
function Leaderboards.topRows(rows, limit)
	local out = {}
	for i, entry in ipairs(rows or {}) do
		if limit and i > limit then break end
		local row = {}
		for k, v in pairs(entry) do row[k] = v end
		row.rank = i
		out[#out + 1] = row
	end
	return out
end

-- ===== Entry guard (Daily, Weekly, Endless) =====
-- Every board entry is built by the server from its own run state; this is the last check before it is queued.
-- Refused: a run that used any Debug remote (state.usedDebug), and numbers that are not whole sane values.
Leaderboards.MAX_DEPTH = 5000 -- Daily/Weekly depth ceiling ((night - 1) * rounds + round - 1; Endless is capped at MAX_ENDLESS_NIGHT)
Leaderboards.MAX_TIPS = 999999 -- Daily/Weekly tiebreak ceiling (the server clamps to this before it asks)

-- Returns true, or false and a short reason (the server logs the reason, the entry is dropped).
function Leaderboards.acceptEntry(state, depth, tips, maxTips)
	if type(state) ~= "table" then
		return false, "no run"
	end
	if state.usedDebug then
		return false, "debug remote used"
	end
	if type(depth) ~= "number" or type(tips) ~= "number" or depth ~= depth or tips ~= tips then
		return false, "not a number"
	end
	if depth < 0 or tips < 0 or depth ~= math.floor(depth) or tips ~= math.floor(tips) then
		return false, "negative or fractional"
	end
	if depth > Leaderboards.MAX_DEPTH then
		return false, "depth above the sane maximum"
	end
	if tips > (maxTips or Leaderboards.MAX_TIPS) then
		return false, "score above the sane maximum"
	end
	return true
end

-- What a board row holds after a write: the higher of the stored value and the new one (so one row per player per
-- period, and a worse later run, or a second server, never lowers it). Used as the UpdateAsync callback.
function Leaderboards.keepBest(old, new)
	if type(old) == "number" and old == old and old >= new then
		return old
	end
	return new
end

-- Normalises a scope string from a client: anything unknown means the global board.
function Leaderboards.normalizeScope(scope)
	if scope == Leaderboards.FRIENDS then
		return Leaderboards.FRIENDS
	end
	return Leaderboards.GLOBAL
end

return Leaderboards
