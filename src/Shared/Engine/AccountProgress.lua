--[[
	AccountProgress.lua
	Turns what happened in a run into account progress: Tavern Rank XP and daily quest progress. Pure Lua, no
	Roblox APIs; the server calls AccountProgress.sync from syncProfileFromSession on every state push.

	It works on monotonic run counters against a per-session snapshot (`snap`, a plain table the server keeps on
	the session), so calling it many times never double counts, and a counter that drops (One More Round restores
	the round start) never counts twice.
]]

local Quests = require(script.Parent.Quests)
local TavernRank = require(script.Parent.TavernRank)
local RunModes = require(script.Parent.RunModes)
local LiveEvents = require(script.Parent.LiveEvents) -- a double XP weekend multiplies account XP only

local AccountProgress = {}

function AccountProgress.countersOf(state)
	local counters = Quests.countersOf(state)
	counters.rounds = state.roundsCleared or 0
	return counters
end

--[[
	profile, snap, state, day (UTC day number), justWon (bool: this sync saw the run flip to won, already filtered
	for revived runs by the caller).
	Returns { changed, xp, rankUps = {rank..}, granted = { { rank, reward } }, quests = { definition.. } }.
]]
function AccountProgress.sync(profile, snap, state, day, justWon)
	local deltas = Quests.deltas(snap, AccountProgress.countersOf(state))
	local result = { changed = false, xp = 0, rankUps = {}, granted = {}, quests = {} }

	local function addXp(amount)
		local added, ups, granted = TavernRank.addXp(profile, amount)
		if added > 0 then
			result.changed = true
			result.xp = result.xp + added
			for _, r in ipairs(ups) do result.rankUps[#result.rankUps + 1] = r end
			for _, g in ipairs(granted) do result.granted[#result.granted + 1] = g end
		end
	end

	local rolled = Quests.ensureDay(profile, day)
	if rolled then
		result.changed = true
	end

	local xp = TavernRank.xpForCounts({
		hands = deltas.hands, rounds = deltas.rounds, bosses = deltas.bosses, wins = justWon and 1 or 0,
	})
	if justWon then
		xp = xp + TavernRank.firstWinBonus(profile, day)
	end
	addXp(math.floor(xp * LiveEvents.xpMultiplier(day) * RunModes.xpScale(state.runMode))) -- a Quick Run pays about half

	local completed, ups, granted = Quests.apply(profile, day, deltas)
	if #completed > 0 then
		result.changed = true
		result.quests = completed
		for _, r in ipairs(ups) do result.rankUps[#result.rankUps + 1] = r end
		for _, g in ipairs(granted) do result.granted[#result.granted + 1] = g end
	elseif next(deltas) ~= nil then
		-- progress moved on an unfinished quest: worth saving
		for _, key in ipairs({ "hands", "pairs", "discards", "flushWins", "packs", "bosses" }) do
			if deltas[key] then result.changed = true end
		end
	end
	return result
end

return AccountProgress
