--[[
	Shared/Engine/DailyStamps.lua
	What the Daily Rewards ladder shows for the streak: one stamp per day in the equipped Card Set accent (Client/DailyRewardsPanel draws them),
	a gentle pulse on today's tile while its reward waits (none in Calm mode or Reduce motion), and a kind line after a missed day. Pure Lua.

	DailyStamps.states(login) -> { { day, state = "stamped" | "today" | "ahead", pulse = bool }, ... } from LoginStreak.view
	DailyStamps.pulse(calm, claimable) -> nil | { seconds = 1.2 }   a slow breathing ring, well under 3 flashes a second
	DailyStamps.streakLine(login) -> string   "Streak: 3 days", or a fresh start line after a break
]]

local CosmeticSets = require(script.Parent.CosmeticSets)

local M = {}

M.CREAM = { 250, 240, 220 }
M.DARK = { 30, 18, 10 }

M.PULSE_SECONDS = 1.2

function M.states(login)
	local out = {}
	for _, r in ipairs((login and login.rewards) or {}) do
		local state = r.claimed and "stamped" or (r.today and "today" or "ahead")
		out[#out + 1] = { day = r.day, state = state, pulse = r.claimable == true }
	end
	return out
end

function M.pulse(calm, claimable)
	if calm == true or claimable ~= true then return nil end
	return { seconds = M.PULSE_SECONDS }
end

-- The stamp fill is the set accent (gold for classic or an unknown set); its check mark is whichever of cream or dark ink reads better on it.
function M.stampColors(setId)
	local fill = CosmeticSets.ringColorOf(setId) or { 246, 196, 70 }
	local ink = CosmeticSets.contrastRatio(fill, M.CREAM) >= CosmeticSets.contrastRatio(fill, M.DARK) and M.CREAM or M.DARK
	return { fill = fill, ink = ink }
end

-- A missed day is never a scolding: the ladder simply starts again and says what the best streak was.
function M.streakLine(login)
	local streak = math.max(0, math.floor(tonumber(login and login.streak) or 0))
	local best = math.max(0, math.floor(tonumber(login and login.best) or 0))
	if streak == 1 and best > 1 then
		return string.format("Fresh start! Your best streak is %d days.", best)
	end
	return string.format("Streak: %d day%s", streak, streak == 1 and "" or "s")
end

return M
