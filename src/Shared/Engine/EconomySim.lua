--[[
	EconomySim.lua
	Plays a week of 20 minute sessions through the real account systems (Daily chest ladder, Daily quests,
	run XP, Season XP) and reports what each day paid. Pure Lua, no Roblox APIs. Used by a test and by
	tools/economy_report.lua (which writes claude/ECONOMY.md).

	Session model (about 20 minutes): two runs, each 12 hands, 4 rounds cleared, 1 Boss Round cleared, Night 3
	reached, no win. Hand mix and shop use are the same every day, so differences between days come only from
	the chest ladder slot and the three quests rolled for that day.

	In-run Tips are not counted here (they never leave the run). "Tips" below means Tips banked for the next run
	(chest, quests, rank rewards); "XP" is Tavern Rank XP; "Season XP" is the Tavern Season ladder.
]]

local PlayerProfile = require(script.Parent.PlayerProfile)
local LoginStreak = require(script.Parent.LoginStreak)
local AccountProgress = require(script.Parent.AccountProgress)
local TavernRank = require(script.Parent.TavernRank)

local EconomySim = {}

-- What one run of the session model does (cumulative counters, like a RunState).
EconomySim.RunModel = {
	handsPlayedTotal = 12, handStats = { Pair = 4, Straight = 1, ["Three of a Kind"] = 1, ["Full House"] = 0 },
	discardsUsedTotal = 5, cardsDiscarded = 10, flushClears = 0, packsBought = 1, bossesCleared = 1,
	bigHands = 0, richClears = 1, quickClears = 0, housePassesBought = 1, recipesUsed = 1,
	night = 3, roundsCleared = 4,
}
EconomySim.RunsPerSession = 2

local function copyRun()
	local run = {}
	for k, v in pairs(EconomySim.RunModel) do
		if type(v) == "table" then
			local t = {}
			for k2, v2 in pairs(v) do t[k2] = v2 end
			run[k] = t
		else
			run[k] = v
		end
	end
	return run
end

-- Plays one session on `day`. Returns { tips, xp, seasonXp, chest, quests }.
local function playSession(profile, day)
	local before = { xp = profile.tavernXp or 0, season = profile.seasonXp or 0, pending = profile.pendingStartTips or 0 }
	local row = { chest = nil, quests = 0 }
	-- the chest
	LoginStreak.checkIn(profile, day)
	local slot = LoginStreak.slotFor(profile.loginStreak)
	local ok, reward = LoginStreak.claim(profile, slot, nil)
	if ok then
		row.chest = reward.label
	end
	-- the runs
	for _ = 1, EconomySim.RunsPerSession do
		local snap = {}
		local result = AccountProgress.sync(profile, snap, copyRun(), day, false)
		row.quests = row.quests + #result.quests
	end
	-- the Tips banked for the next run are taken at run start; count them the day they were earned
	local tips = (profile.pendingStartTips or 0) - before.pending
	profile.pendingStartTips = 0
	row.tips = tips
	row.xp = (profile.tavernXp or 0) - before.xp
	row.seasonXp = (profile.seasonXp or 0) - before.season
	return row
end

-- A week of sessions from `startDay` (a UTC day number). Returns { days = { {day, tips, xp, seasonXp, chest, quests} }, flags = { text } }.
function EconomySim.week(startDay)
	local profile = PlayerProfile.new()
	profile.hasSeenTutorial = true
	local days = {}
	for i = 0, 6 do
		local row = playSession(profile, startDay + i)
		row.day = startDay + i
		row.slot = i + 1
		days[#days + 1] = row
	end
	local flags = {}
	for _, metric in ipairs({ "tips", "xp", "seasonXp" }) do
		for i, row in ipairs(days) do
			local others, n = 0, 0
			for j, other in ipairs(days) do
				if j ~= i then others = others + other[metric]; n = n + 1 end
			end
			local mean = others / n
			if mean > 0 and row[metric] > 3 * mean then
				flags[#flags + 1] = string.format("day %d %s %d is over 3x the others (%.1f)", i, metric, row[metric], mean)
			elseif mean > 0 and row[metric] < mean / 3 then
				flags[#flags + 1] = string.format("day %d %s %d is under a third of the others (%.1f)", i, metric, row[metric], mean)
			end
		end
	end
	return { days = days, flags = flags }
end

function EconomySim.markdown(result)
	local lines = {
		"| Day | Chest | Quests done | Tips banked | Rank XP | Season XP |",
		"| --- | --- | --- | --- | --- | --- |",
	}
	local t = { tips = 0, xp = 0, seasonXp = 0 }
	for _, row in ipairs(result.days) do
		lines[#lines + 1] = string.format("| %d | %s | %d | %d | %d | %d |", row.slot, row.chest or "none", row.quests, row.tips, row.xp, row.seasonXp)
		t.tips, t.xp, t.seasonXp = t.tips + row.tips, t.xp + row.xp, t.seasonXp + row.seasonXp
	end
	lines[#lines + 1] = string.format("| Week | | | %d | %d | %d |", t.tips, t.xp, t.seasonXp)
	return table.concat(lines, "\n")
end

EconomySim.MAX_RANK = TavernRank.MAX_RANK

return EconomySim
