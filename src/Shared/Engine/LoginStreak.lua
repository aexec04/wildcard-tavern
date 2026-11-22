-- Daily login streak (pure rules, server authoritative, UTC days).
--
-- Profile fields: lastLoginDay (UTC day number, floor(unix / 86400)), loginStreak (consecutive days),
-- loginClaimedDay (the lastLoginDay whose reward was already claimed).
--
-- Rules:
--   * checkIn(profile, day) runs once per UTC day. Same day: nothing. Next day: streak + 1.
--     Exactly one missed day (a gap of 2) is forgiven (the "grace day"): streak + 1. A longer gap restarts at 1.
--   * The reward ladder has 7 slots and loops: streak 1 is slot 1, streak 7 is slot 7, streak 8 is slot 1 again.
--     Each day has exactly one reward (today's slot), claimed once with claim(), never automatic.
--   * Tips go to the live run when there is one, otherwise they are banked for the next run
--     (profile.pendingStartTips). XP goes to the Tavern Rank. A card back or a Tips fallback never repeats a freebie.
local TavernRank = require(script.Parent.TavernRank)

local LoginStreak = {}

local SECONDS_PER_DAY = 86400
LoginStreak.GRACE_DAYS = 1
LoginStreak.LADDER = 7

-- EDIT ME. `day` is the slot on the 7-day ladder. `art` picks the painted icon (no emoji in UI).
LoginStreak.Rewards = {
	{ day = 1, kind = "tips", amount = 3, label = "3 Tips", art = "tips" },
	{ day = 2, kind = "xp", amount = 40, label = "40 XP", art = "xp" },
	{ day = 3, kind = "tips", amount = 5, label = "5 Tips", art = "tips" },
	{ day = 4, kind = "xp", amount = 60, label = "60 XP", art = "xp" },
	{ day = 5, kind = "tips", amount = 6, label = "6 Tips", art = "tips" },
	{ day = 6, kind = "xp", amount = 80, label = "80 XP", art = "xp" },
	{ day = 7, kind = "cardBack", id = "festival_ribbon", fallbackTips = 10, label = "Card back: Festival Ribbon", art = "cardBack" },
}

-- The line under the ladder: tomorrow's reward, or the loop note after the last slot.
function LoginStreak.laterLabel(day)
	if day >= LoginStreak.LADDER then return "Next week: a new streak starts" end
	local nextReward = LoginStreak.rewardForDay(day + 1)
	return "Tomorrow: " .. (nextReward and nextReward.label or "a new reward")
end

function LoginStreak.dayNumber(timestamp)
	return math.floor(timestamp / SECONDS_PER_DAY)
end

-- Seconds until the next UTC day starts.
function LoginStreak.secondsToNextDay(timestamp)
	return SECONDS_PER_DAY - (timestamp % SECONDS_PER_DAY)
end

-- The ladder slot (1..7) that a streak length is on. Streak 0 (never logged in) is slot 1.
function LoginStreak.slotFor(streak)
	streak = math.max(1, math.floor(streak or 1))
	return ((streak - 1) % LoginStreak.LADDER) + 1
end

-- Returns true when the streak changed (the caller should save).
function LoginStreak.checkIn(profile, day)
	if type(day) ~= "number" then
		return false
	end
	local last = profile.lastLoginDay
	if last == day then
		return false
	end
	if last and day < last then
		-- A clock that went backwards (Studio clock change, bad server time): change nothing, so the streak,
		-- today's slot and the claimed mark stay exactly as saved and a reward can never be claimed twice.
		return false
	end
	local gap = last and (day - last) or nil
	if gap and gap >= 1 and gap <= 1 + LoginStreak.GRACE_DAYS then
		profile.loginStreak = (profile.loginStreak or 0) + 1
	else
		-- First login, a long gap, or a clock that went backwards: start over.
		profile.loginStreak = 1
	end
	profile.bestLoginStreak = math.max(profile.bestLoginStreak or 0, profile.loginStreak) -- high-water mark for achievements
	profile.lastLoginDay = day
	return true
end

function LoginStreak.rewardForDay(day)
	for _, reward in ipairs(LoginStreak.Rewards) do
		if reward.day == day then
			return reward
		end
	end
	return nil
end

local function claimedToday(profile)
	return profile.lastLoginDay ~= nil and profile.loginClaimedDay == profile.lastLoginDay
end

-- Only today's slot can be claimed, once per UTC day.
function LoginStreak.canClaim(profile, rewardDay)
	if (profile.loginStreak or 0) < 1 or claimedToday(profile) then
		return false
	end
	return rewardDay == LoginStreak.slotFor(profile.loginStreak) and LoginStreak.rewardForDay(rewardDay) ~= nil
end

-- Today's reward if it is still waiting, else the next slot's reward (for "come back tomorrow"), or nil with no streak.
function LoginStreak.nextReward(profile)
	local streak = profile.loginStreak or 0
	if streak < 1 then
		return LoginStreak.rewardForDay(1)
	end
	local slot = LoginStreak.slotFor(streak)
	if not claimedToday(profile) then
		return LoginStreak.rewardForDay(slot)
	end
	return LoginStreak.rewardForDay((slot % LoginStreak.LADDER) + 1)
end

-- Claims today's reward. `state` is the live RunState (Tips go straight in; without one they are banked).
-- Returns (ok, rewardOrMessage). `ranked` (third value) lists rank ups when the reward was XP.
function LoginStreak.claim(profile, rewardDay, state)
	if not LoginStreak.canClaim(profile, rewardDay) then
		return false, "Not available"
	end
	local reward = LoginStreak.rewardForDay(rewardDay)
	local function giveTips(amount)
		if type(state) == "table" and type(state.tips) == "number" then
			state.tips = state.tips + amount
		else
			profile.pendingStartTips = math.min(TavernRank.MAX_PENDING_TIPS, (profile.pendingStartTips or 0) + amount)
		end
	end
	local ups = {}
	if reward.kind == "tips" then
		giveTips(reward.amount)
	elseif reward.kind == "xp" then
		local _, rankUps = TavernRank.addXp(profile, reward.amount)
		ups = rankUps
	elseif reward.kind == "cardBack" then
		profile.unlockedCardBackIds = profile.unlockedCardBackIds or {}
		if profile.unlockedCardBackIds[reward.id] then
			giveTips(reward.fallbackTips or 0) -- already owned: the loop pays Tips instead
		else
			profile.unlockedCardBackIds[reward.id] = true
		end
	else
		return false, "Unknown reward"
	end
	profile.loginClaimedDay = profile.lastLoginDay
	return true, reward, ups
end

-- What the client shows: the streak, today's slot and all 7 slots with their status.
function LoginStreak.view(profile)
	local streak = profile.loginStreak or 0
	local today = LoginStreak.slotFor(streak)
	local waiting = streak >= 1 and not claimedToday(profile)
	local rows = {}
	for _, reward in ipairs(LoginStreak.Rewards) do
		local claimed
		if reward.day < today then
			claimed = streak >= 1
		elseif reward.day == today then
			claimed = streak >= 1 and not waiting
		else
			claimed = false
		end
		table.insert(rows, {
			day = reward.day,
			label = reward.label,
			icon = reward.icon,
			art = reward.art,
			id = reward.id,
			kind = reward.kind,
			claimed = claimed,
			claimable = waiting and reward.day == today,
			today = reward.day == today,
		})
	end
	return { streak = streak, best = profile.bestLoginStreak or streak, today = today, rewards = rows }
end

return LoginStreak
