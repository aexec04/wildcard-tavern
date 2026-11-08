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
Leaderboards.FRIENDS = "friends"
Leaderboards.FRIENDS_CACHE_SECONDS = 60
Leaderboards.FRIENDS_PAGE_SIZE = 100 -- how deep into the sorted board friends are looked up
Leaderboards.MAX_FRIENDS = 200 -- friend list cap per lookup

function Leaderboards.isScope(scope)
	return scope == Leaderboards.EVERYONE or scope == Leaderboards.FRIENDS
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

return Leaderboards
