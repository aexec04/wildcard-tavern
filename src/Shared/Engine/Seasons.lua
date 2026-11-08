--[[
	Shared/Engine/Seasons.lua
	Limited-time seasonal sets: data and rules only (pure Lua, tested).

	A season has UTC start and end dates (both days included), a card back and a title as rewards, and an
	unlock path: clear `unlock.nights` Nights in one run while the season is active. Earned rewards are
	permanent (they land in the normal profile sets) and are remembered in profile.seasonRewardIds, so a
	season can end without taking anything away.

	EDIT ME: add a season by adding a row to Definitions. Reward ids must exist in CardBacks and
	Achievements, with art prompts in tools/patron_art/prompts.json.
]]

local Seasons = {}

Seasons.Definitions = {
	{
		id = "winter_lanterns",
		name = "Winter Lanterns",
		startDate = "2026-12-15", -- first day (UTC)
		endDate = "2027-01-05", -- last day (UTC), included
		blurb = "Clear 3 Nights in one run to earn the Winter Lanterns card back and title.",
		unlock = { kind = "nightsInRun", nights = 3 },
		rewards = { cardBackId = "winter_lanterns", titleId = "lantern_keeper" },
	},
}

local SECONDS_PER_DAY = 86400

-- Days since 1970-01-01 for a civil date (proleptic Gregorian). Pure integer maths.
local function daysFromCivil(y, m, d)
	if m <= 2 then y = y - 1 end
	local era = math.floor(y / 400)
	local yoe = y - era * 400
	local mp = (m + 9) % 12
	local doy = math.floor((153 * mp + 2) / 5) + d - 1
	local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
	return era * 146097 + doe - 719468
end

-- "YYYY-MM-DD" -> unix seconds at 00:00 UTC, or nil when malformed.
function Seasons.parseDate(text)
	if type(text) ~= "string" then return nil end
	local y, m, d = text:match("^(%d%d%d%d)-(%d%d)-(%d%d)$")
	y, m, d = tonumber(y), tonumber(m), tonumber(d)
	if not y or m < 1 or m > 12 or d < 1 or d > 31 then return nil end
	return daysFromCivil(y, m, d) * SECONDS_PER_DAY
end

function Seasons.startsAt(season)
	return Seasons.parseDate(season.startDate)
end

-- First second AFTER the last day.
function Seasons.endsAt(season)
	local last = Seasons.parseDate(season.endDate)
	return last and (last + SECONDS_PER_DAY) or nil
end

function Seasons.getById(id)
	for _, season in ipairs(Seasons.Definitions) do
		if season.id == id then return season end
	end
	return nil
end

-- The season running at `now` (unix seconds), or nil.
function Seasons.active(now)
	for _, season in ipairs(Seasons.Definitions) do
		local s, e = Seasons.startsAt(season), Seasons.endsAt(season)
		if s and e and now >= s and now < e then
			return season
		end
	end
	return nil
end

function Seasons.secondsLeft(season, now)
	local e = Seasons.endsAt(season)
	return e and math.max(0, e - now) or 0
end

-- "12d 4h" / "5h 20m" / "40m"
function Seasons.timeLeftText(seconds)
	seconds = math.max(0, math.floor(seconds))
	local days = math.floor(seconds / SECONDS_PER_DAY)
	local hours = math.floor(seconds % SECONDS_PER_DAY / 3600)
	local minutes = math.floor(seconds % 3600 / 60)
	if days > 0 then return string.format("%dd %dh", days, hours) end
	if hours > 0 then return string.format("%dh %02dm", hours, minutes) end
	return string.format("%dm", minutes)
end

function Seasons.isEarned(profile, season)
	return type(profile.seasonRewardIds) == "table" and profile.seasonRewardIds[season.id] == true
end

-- Called when a run syncs to the profile (not for revived runs). `nightsClearedInRun` is the number of
-- Nights beaten in the current run. Grants the season's rewards once, only while the season is active.
-- Returns the season when something was granted (the caller should save), otherwise nil.
function Seasons.recordProgress(profile, now, nightsClearedInRun)
	local season = Seasons.active(now)
	if not season or Seasons.isEarned(profile, season) then
		return nil
	end
	if (nightsClearedInRun or 0) < season.unlock.nights then
		return nil
	end
	profile.seasonRewardIds = profile.seasonRewardIds or {}
	profile.seasonRewardIds[season.id] = true
	profile.unlockedCardBackIds = profile.unlockedCardBackIds or {}
	profile.unlockedCardBackIds[season.rewards.cardBackId] = true
	profile.rewardTitleIds = profile.rewardTitleIds or {}
	profile.rewardTitleIds[season.rewards.titleId] = true
	return season
end

-- What the client shows: nil when no season is running, otherwise the banner data.
function Seasons.view(profile, now)
	local season = Seasons.active(now)
	if not season then return nil end
	return {
		id = season.id,
		name = season.name,
		blurb = season.blurb,
		secondsLeft = Seasons.secondsLeft(season, now),
		timeLeft = Seasons.timeLeftText(Seasons.secondsLeft(season, now)),
		earned = Seasons.isEarned(profile, season),
	}
end

return Seasons
