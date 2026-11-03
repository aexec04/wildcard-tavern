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

return Leaderboards
