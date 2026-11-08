-- Daily login streak (pure rules, server authoritative, UTC days).
--
-- Profile fields: lastLoginDay (UTC day number, floor(unix / 86400)), loginStreak (consecutive days),
-- claimedLoginDays ([reward day] = true, cleared when the streak resets).
--
-- Rules:
--   * checkIn(profile, day) runs once per UTC day. Same day: nothing. Next day: streak + 1.
--     Exactly one missed day (a gap of 2) is forgiven (the "grace day"): streak + 1. A longer gap restarts at 1.
--   * Rewards unlock at streak >= reward.day and are claimed once per streak (claim, not automatic).
--   * Tips go to the live run (Tips only exist inside a run); a card back or patron goes to the profile.
local LoginStreak = {}

local SECONDS_PER_DAY = 86400
LoginStreak.GRACE_DAYS = 1

-- EDIT ME. `day` is the streak length that unlocks the reward.
LoginStreak.Rewards = {
	{ day = 3, kind = "tips", amount = 5, label = "5 Tips" },
	{ day = 7, kind = "cardBack", id = "festival_ribbon", label = "Card back: Festival Ribbon" },
	{ day = 14, kind = "patron", id = "the_bard", label = "Patron: The Bard (added to your Collection)" },
}

function LoginStreak.dayNumber(timestamp)
	return math.floor(timestamp / SECONDS_PER_DAY)
end

-- Seconds until the next UTC day starts.
function LoginStreak.secondsToNextDay(timestamp)
	return SECONDS_PER_DAY - (timestamp % SECONDS_PER_DAY)
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
	local gap = last and (day - last) or nil
	if gap and gap >= 1 and gap <= 1 + LoginStreak.GRACE_DAYS then
		profile.loginStreak = (profile.loginStreak or 0) + 1
	else
		-- First login, a long gap, or a clock that went backwards: start over.
		profile.loginStreak = 1
		profile.claimedLoginDays = {}
	end
	profile.lastLoginDay = day
	profile.claimedLoginDays = profile.claimedLoginDays or {}
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

function LoginStreak.canClaim(profile, rewardDay)
	local reward = LoginStreak.rewardForDay(rewardDay)
	if not reward then
		return false
	end
	local claimed = profile.claimedLoginDays or {}
	return (profile.loginStreak or 0) >= reward.day and not claimed[reward.day]
end

-- The first reward still ahead (claimable or not), or nil when all are claimed.
function LoginStreak.nextReward(profile)
	local claimed = profile.claimedLoginDays or {}
	for _, reward in ipairs(LoginStreak.Rewards) do
		if not claimed[reward.day] then
			return reward
		end
	end
	return nil
end

-- Claims one reward. `state` is the live RunState (needed for Tips). Returns (ok, rewardOrMessage).
function LoginStreak.claim(profile, rewardDay, state)
	if not LoginStreak.canClaim(profile, rewardDay) then
		return false, "Not available"
	end
	local reward = LoginStreak.rewardForDay(rewardDay)
	if reward.kind == "tips" then
		if type(state) ~= "table" or type(state.tips) ~= "number" then
			return false, "Start a run to claim Tips"
		end
		state.tips = state.tips + reward.amount
	elseif reward.kind == "cardBack" then
		profile.unlockedCardBackIds = profile.unlockedCardBackIds or {}
		profile.unlockedCardBackIds[reward.id] = true
	elseif reward.kind == "patron" then
		profile.discoveredPatronIds = profile.discoveredPatronIds or {}
		profile.discoveredPatronIds[reward.id] = true
	else
		return false, "Unknown reward"
	end
	profile.claimedLoginDays = profile.claimedLoginDays or {}
	profile.claimedLoginDays[reward.day] = true
	return true, reward
end

-- What the client shows: streak, each reward with its status.
function LoginStreak.view(profile)
	local rows = {}
	local claimed = profile.claimedLoginDays or {}
	for _, reward in ipairs(LoginStreak.Rewards) do
		table.insert(rows, {
			day = reward.day,
			label = reward.label,
			claimed = claimed[reward.day] == true,
			claimable = LoginStreak.canClaim(profile, reward.day),
		})
	end
	return { streak = profile.loginStreak or 0, rewards = rows }
end

return LoginStreak
