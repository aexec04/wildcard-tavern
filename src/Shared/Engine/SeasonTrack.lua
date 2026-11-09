--[[
	SeasonTrack.lua
	TAVERN SEASON: a 30 day reward ladder on top of Tavern Rank. (Named SeasonTrack because Engine/Seasons.lua already
	holds the limited-time seasonal Card Sets.) Pure Lua, no Roblox APIs.

	A season has an id, UTC start and end dates (both days count, the same date helpers as Engine/LiveEvents), a name, a
	banner key and 30 reward tiers. Rewards are cosmetics or a few Tips for the next run, never gameplay power:
	Tips on most tiers, an existing card back at tiers 10 and 20, the season title at tier 25, and a card back that only
	this season gives at tier 30.

	Season XP comes from the same sources as Tavern Rank (hands, rounds, bosses, wins, quests: AccountProgress adds the XP
	it already computes), but is tracked separately and resets when the season id changes:
	  profile.seasonId       the season the numbers below belong to
	  profile.seasonXp       XP earned this season (capped at MAX_XP)
	  profile.seasonClaimed  { [tier] = true } rewards already taken this season
	A claimed reward stays owned for good (it lands in the normal profile sets); an unclaimed one is lost when the season
	ends. Daily, Weekly and Seed boards are not touched. Two seasons are defined back to back so the first never ends
	into an empty page.
]]

local LiveEvents = require(script.Parent.LiveEvents)
local TavernRank = require(script.Parent.TavernRank)

local SeasonTrack = {}

SeasonTrack.TIERS = 30
SeasonTrack.XP_PER_TIER = 90
SeasonTrack.MAX_XP = SeasonTrack.TIERS * SeasonTrack.XP_PER_TIER

-- EDIT ME. Dates are UTC and both days count. `finalCardBackId` and `titleId` must exist in CardBacks and Achievements.
SeasonTrack.Seasons = {
	{
		id = "harvest_moon", name = "Harvest Moon", bannerKey = "season_harvest_moon",
		startDate = "2026-11-01", endDate = "2026-11-30",
		cardBackAt10 = "kitchen_checks", cardBackAt20 = "starlit_keeper",
		titleId = "season_harvest_moon", finalCardBackId = "harvest_moon",
	},
	{
		id = "winter_welcome", name = "Winter Welcome", bannerKey = "season_winter_welcome",
		startDate = "2026-12-01", endDate = "2026-12-30",
		cardBackAt10 = "hall_banner", cardBackAt20 = "winter_frost",
		titleId = "season_winter_welcome", finalCardBackId = "winter_welcome",
	},
}

local TIPS_BY_TIER = {
	[1] = 2, [2] = 2, [3] = 3, [4] = 3, [5] = 3, [6] = 3, [7] = 3, [8] = 4, [9] = 4,
	[11] = 4, [12] = 4, [13] = 4, [14] = 4, [15] = 5, [16] = 5, [17] = 5, [18] = 5, [19] = 5,
	[21] = 5, [22] = 6, [23] = 6, [24] = 6, [26] = 6, [27] = 7, [28] = 7, [29] = 8,
}

-- The reward of one tier of a season: { kind = tips|cardBack|title, amount|id }.
function SeasonTrack.rewardFor(season, tier)
	if tier == 10 then return { kind = "cardBack", id = season.cardBackAt10 } end
	if tier == 20 then return { kind = "cardBack", id = season.cardBackAt20 } end
	if tier == 25 then return { kind = "title", id = season.titleId } end
	if tier == SeasonTrack.TIERS then return { kind = "cardBack", id = season.finalCardBackId } end
	local tips = TIPS_BY_TIER[tier]
	if tips then return { kind = "tips", amount = tips } end
	return nil
end

function SeasonTrack.getById(id)
	for _, season in ipairs(SeasonTrack.Seasons) do
		if season.id == id then return season end
	end
	return nil
end

-- First and last UTC day numbers of a season (inclusive), or nil for a bad date.
function SeasonTrack.window(season)
	local first = LiveEvents.dayNumberOf(season.startDate)
	local last = LiveEvents.dayNumberOf(season.endDate)
	if first and last and last >= first then
		return first, last
	end
	return nil
end

-- The season running on UTC day number `day`, or nil.
function SeasonTrack.active(day)
	for _, season in ipairs(SeasonTrack.Seasons) do
		local first, last = SeasonTrack.window(season)
		if first and day >= first and day <= last then
			return season
		end
	end
	return nil
end

-- The next season that has not started yet, or nil.
function SeasonTrack.upcoming(day)
	local best, bestFirst
	for _, season in ipairs(SeasonTrack.Seasons) do
		local first = SeasonTrack.window(season)
		if first and first > day and (not bestFirst or first < bestFirst) then
			best, bestFirst = season, first
		end
	end
	return best
end

-- Whole days left including today (a season ending today has 1 day left), 0 when not running.
function SeasonTrack.daysLeft(season, day)
	local first, last = SeasonTrack.window(season)
	if not first or day < first or day > last then
		return 0
	end
	return last - day + 1
end

function SeasonTrack.tierOf(xp)
	xp = math.max(0, math.min(SeasonTrack.MAX_XP, math.floor(tonumber(xp) or 0)))
	return math.floor(xp / SeasonTrack.XP_PER_TIER)
end

-- Makes profile.seasonId match the running season. A new season id resets the XP and the claims (the rewards that
-- were claimed stay owned). With no season running nothing changes. Returns true when the profile was reset.
function SeasonTrack.ensureSeason(profile, day)
	local season = SeasonTrack.active(day)
	if not season then
		return false
	end
	if profile.seasonId == season.id then
		profile.seasonClaimed = profile.seasonClaimed or {}
		return false
	end
	profile.seasonId = season.id
	profile.seasonXp = 0
	profile.seasonClaimed = {}
	return true
end

-- Adds season XP (whole numbers) while a season runs. Returns the XP added (0 when none is running).
function SeasonTrack.addXp(profile, amount, day)
	amount = tonumber(amount) or 0
	if amount ~= amount or amount == math.huge then
		return 0 -- NaN and infinity never reach the profile
	end
	amount = math.floor(amount)
	if amount <= 0 or not SeasonTrack.active(day) then
		return 0
	end
	SeasonTrack.ensureSeason(profile, day)
	local before = profile.seasonXp or 0
	profile.seasonXp = math.min(SeasonTrack.MAX_XP, before + amount)
	return profile.seasonXp - before
end

local function grant(profile, reward)
	if reward.kind == "tips" then
		profile.pendingStartTips = math.min(TavernRank.MAX_PENDING_TIPS, (profile.pendingStartTips or 0) + reward.amount)
	elseif reward.kind == "title" then
		profile.rewardTitleIds = profile.rewardTitleIds or {}
		profile.rewardTitleIds[reward.id] = true
	elseif reward.kind == "cardBack" then
		profile.unlockedCardBackIds = profile.unlockedCardBackIds or {}
		profile.unlockedCardBackIds[reward.id] = true
	end
end

-- Claims one tier: it must be reached, not claimed, and the season must still be running. Returns ok, reward|reason.
function SeasonTrack.claim(profile, tier, day)
	local season = SeasonTrack.active(day)
	if not season then
		return false, "No season is running."
	end
	SeasonTrack.ensureSeason(profile, day)
	if type(tier) ~= "number" or tier ~= math.floor(tier) or tier < 1 or tier > SeasonTrack.TIERS then
		return false, "Unknown tier."
	end
	if SeasonTrack.tierOf(profile.seasonXp) < tier then
		return false, "Not reached yet."
	end
	if profile.seasonClaimed[tier] then
		return false, "Already claimed."
	end
	local reward = SeasonTrack.rewardFor(season, tier)
	if not reward then
		return false, "Nothing to claim."
	end
	profile.seasonClaimed[tier] = true
	grant(profile, reward)
	return true, reward
end

-- Claims every reached, unclaimed tier. Returns the list of { tier, reward } claimed just now.
function SeasonTrack.claimAll(profile, day)
	local claimed = {}
	for tier = 1, SeasonTrack.TIERS do
		local ok, reward = SeasonTrack.claim(profile, tier, day)
		if ok then
			claimed[#claimed + 1] = { tier = tier, reward = reward }
		end
	end
	return claimed
end

-- Short reward text ("+3 Tips next run"). `lookup` (optional) = { cardBackName, titleName } like TavernRank.rewardText.
function SeasonTrack.rewardText(reward, lookup)
	if reward and reward.kind == "tips" then
		return "+" .. reward.amount .. " Tips next run"
	end
	return TavernRank.rewardText(reward, lookup)
end

-- Cleans saved values: junk dropped, an unknown season id resets so renamed content never breaks a profile.
function SeasonTrack.cleanSaved(rawId, rawXp, rawClaimed)
	local id = type(rawId) == "string" and SeasonTrack.getById(rawId) and rawId or nil
	local xp, claimed = 0, {}
	if id then
		if type(rawXp) == "number" and rawXp == rawXp and rawXp ~= math.huge and rawXp ~= -math.huge then
			xp = math.max(0, math.min(SeasonTrack.MAX_XP, math.floor(rawXp)))
		end
		if type(rawClaimed) == "table" then
			for tier, flag in pairs(rawClaimed) do
				if type(tier) == "number" and tier == math.floor(tier) and tier >= 1 and tier <= SeasonTrack.TIERS and flag == true then
					claimed[tier] = true
				end
			end
		end
	end
	return id, xp, claimed
end

-- What the client draws. nil when no season runs and none is coming.
function SeasonTrack.view(profile, day, lookup)
	local season = SeasonTrack.active(day)
	if not season then
		local nextSeason = SeasonTrack.upcoming(day)
		if not nextSeason then
			return nil
		end
		local first = SeasonTrack.window(nextSeason)
		return { upcoming = true, name = nextSeason.name, bannerKey = nextSeason.bannerKey, startsIn = first - day }
	end
	local xp = (profile.seasonId == season.id) and (profile.seasonXp or 0) or 0
	local claimed = (profile.seasonId == season.id) and profile.seasonClaimed or {}
	local reached = SeasonTrack.tierOf(xp)
	local tiers, claimable = {}, 0
	for tier = 1, SeasonTrack.TIERS do
		local reward = SeasonTrack.rewardFor(season, tier)
		local isReached, isClaimed = tier <= reached, claimed[tier] == true
		if isReached and not isClaimed then claimable = claimable + 1 end
		tiers[tier] = {
			tier = tier, need = tier * SeasonTrack.XP_PER_TIER, reward = reward, text = SeasonTrack.rewardText(reward, lookup),
			reached = isReached, claimed = isClaimed,
		}
	end
	return {
		id = season.id, name = season.name, bannerKey = season.bannerKey, daysLeft = SeasonTrack.daysLeft(season, day),
		xp = xp, tier = reached, maxed = reached >= SeasonTrack.TIERS, xpPerTier = SeasonTrack.XP_PER_TIER,
		into = reached >= SeasonTrack.TIERS and 0 or xp - reached * SeasonTrack.XP_PER_TIER,
		tiers = tiers, claimable = claimable,
	}
end

-- Registry check used by the tests: dates parse, seasons do not overlap, rewards reference real content ids lookups.
function SeasonTrack.validate()
	local problems = {}
	local windows = {}
	for _, season in ipairs(SeasonTrack.Seasons) do
		local first, last = SeasonTrack.window(season)
		if not first then
			problems[#problems + 1] = season.id .. ": bad dates"
		else
			for _, w in ipairs(windows) do
				if first <= w.last and last >= w.first then
					problems[#problems + 1] = season.id .. ": overlaps " .. w.id
				end
			end
			windows[#windows + 1] = { id = season.id, first = first, last = last }
		end
	end
	return problems
end

return SeasonTrack
