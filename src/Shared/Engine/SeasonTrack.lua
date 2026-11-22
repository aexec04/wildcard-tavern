--[[
	SeasonTrack.lua
	TAVERN SEASON: a 30 day reward ladder on top of Tavern Rank. (Named SeasonTrack because Engine/Seasons.lua already
	holds the limited-time seasonal Card Sets.) Pure Lua, no Roblox APIs.

	A season has an id, UTC start and end dates (both days count, the same date helpers as Engine/LiveEvents), a name, a
	banner key and 30 reward tiers. Rewards are cosmetics or a few Tips for the next run, never gameplay power:
	Tips on most tiers (free track only; the paid row never gives Tips), an existing card back at tiers 10 and 20, the season title at tier 25, and a card back that only
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
SeasonTrack.XP_PER_TIER = 225 -- a 20 minute a day player (about 270 Season XP a day) finishes the 30 tiers around day 25 of the 30 day Season
SeasonTrack.MAX_XP = SeasonTrack.TIERS * SeasonTrack.XP_PER_TIER

-- EDIT ME. Dates are UTC and both days count. `finalCardBackId` and `titleId` must exist in CardBacks and Achievements.
SeasonTrack.Seasons = {
	{
		id = "harvest_moon", name = "Harvest Moon", bannerKey = "season_harvest_moon",
		startDate = "2026-11-01", endDate = "2026-11-30",
		cardBackAt10 = "kitchen_checks", cardBackAt20 = "starlit_keeper",
		titleId = "season_harvest_moon", finalCardBackId = "harvest_moon",
		premiumItemId = "premium_harvest_moon", premiumTitleId = "season_premium_harvest", premiumSetId = "harvest_table", premiumBackId = "harvest_premium",
	},
	{
		id = "winter_welcome", name = "Winter Welcome", bannerKey = "season_winter_welcome",
		startDate = "2026-12-01", endDate = "2026-12-30",
		cardBackAt10 = "hall_banner", cardBackAt20 = "winter_frost",
		titleId = "season_winter_welcome", finalCardBackId = "winter_welcome",
		premiumItemId = "premium_winter_welcome", premiumTitleId = "season_premium_winter", premiumSetId = "winter_table", premiumBackId = "winter_premium",
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

-- PREMIUM ROW: a second reward on the same 30 tiers, bought once per season (Engine/Store.lua `premium_<season>`).
-- Cosmetic only: a Season Card Set (tier 15), Store Flair pieces (5, 10, 18, 24), a premium title (8), a card back only
-- premium owners get (tier 30) and a Season Stamp on every other tier (the claim itself is the stamp; no Tips, no power).
local PREMIUM_FLAIR = { [5] = "rainbow_numbers", [10] = "ribbon_trail", [18] = "crown_finisher", [24] = "star_aura" }

function SeasonTrack.premiumRewardFor(season, tier)
	if tier == 8 then return { kind = "title", id = season.premiumTitleId } end
	if tier == 15 then return { kind = "set", id = season.premiumSetId } end
	if tier == SeasonTrack.TIERS then return { kind = "cardBack", id = season.premiumBackId } end
	if PREMIUM_FLAIR[tier] then return { kind = "flair", id = PREMIUM_FLAIR[tier] } end
	if tier >= 1 and tier < SeasonTrack.TIERS then return { kind = "stamp" } end -- a keepsake mark only, never Tips or power
	return nil
end

function SeasonTrack.hasPremium(profile, season)
	return type(profile.seasonPremium) == "table" and profile.seasonPremium[season.id] == true
end

-- What the premium pass includes, for the "exactly what is included" line before buying.
function SeasonTrack.premiumPerks(season)
	return {
		"Card Set: " .. season.premiumSetId, "4 Flair pieces", "Title and a tier 30 card back only for premium",
		"1 Tip on 22 more tiers",
	}
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
	profile.seasonPremiumClaimed = {} -- the premium pass of an old season stays recorded (seasonPremium), its claims reset
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
	elseif reward.kind == "set" then
		profile.ownedSetIds = profile.ownedSetIds or {}
		profile.ownedSetIds[reward.id] = true
	elseif reward.kind == "flair" then
		require(script.Parent.Flair).grantOwned(profile, reward.id)
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

-- Claims one PREMIUM tier: the season's premium pass must be owned, the tier reached and not claimed, the season running.
function SeasonTrack.claimPremium(profile, tier, day)
	local season = SeasonTrack.active(day)
	if not season then
		return false, "No season is running."
	end
	SeasonTrack.ensureSeason(profile, day)
	if not SeasonTrack.hasPremium(profile, season) then
		return false, "Needs the premium pass."
	end
	if type(tier) ~= "number" or tier ~= math.floor(tier) or tier < 1 or tier > SeasonTrack.TIERS then
		return false, "Unknown tier."
	end
	profile.seasonPremiumClaimed = profile.seasonPremiumClaimed or {}
	if SeasonTrack.tierOf(profile.seasonXp) < tier then
		return false, "Not reached yet."
	end
	if profile.seasonPremiumClaimed[tier] then
		return false, "Already claimed."
	end
	local reward = SeasonTrack.premiumRewardFor(season, tier)
	if not reward then
		return false, "Nothing to claim."
	end
	profile.seasonPremiumClaimed[tier] = true
	grant(profile, reward)
	return true, reward
end

function SeasonTrack.claimAllPremium(profile, day)
	local claimed = {}
	for tier = 1, SeasonTrack.TIERS do
		local ok, reward = SeasonTrack.claimPremium(profile, tier, day)
		if ok then
			claimed[#claimed + 1] = { tier = tier, reward = reward, premium = true }
		end
	end
	return claimed
end

-- The premium pass of `seasonId` was bought (Engine/Store.lua): owned for good, and every premium tier already reached is
-- claimed at once when that season is running (a mid season purchase). Idempotent. Returns the claimed list.
function SeasonTrack.grantPremium(profile, seasonId, day)
	if not SeasonTrack.getById(seasonId) then
		return {}
	end
	profile.seasonPremium = type(profile.seasonPremium) == "table" and profile.seasonPremium or {}
	profile.seasonPremium[seasonId] = true
	local active = SeasonTrack.active(day)
	if active and active.id == seasonId then
		return SeasonTrack.claimAllPremium(profile, day)
	end
	return {}
end

-- Season panel numbers (Client/SeasonPanel.lua): 128 px tiles with 12 px gaps, so the track shows 10 full tiles.
SeasonTrack.TILE_W, SeasonTrack.TILE_GAP, SeasonTrack.TILES_VISIBLE = 128, 12, 10

-- Season panel fit for a screen (Client/SeasonPanel.lua uses it, tests check it). Claim buttons are 44 px tall.
-- Whole tiles only: narrow screens show fewer tiles; short screens scale the panel down (never below 0.8).
SeasonTrack.BUTTON_H = 44
SeasonTrack.TILE_H, SeasonTrack.PREMIUM_H, SeasonTrack.PANEL_EXTRA_H = 170, 118, 194
-- Claim All and Premium plate height in panel pixels that still measures 44 px on screen after the panel shrinks by `scale`, and its top
-- (56, or higher when the plate grows so it stays 2 px clear of the track at 104).
function SeasonTrack.touchH(scale)
	return math.max(SeasonTrack.BUTTON_H, math.ceil(SeasonTrack.BUTTON_H / math.max(0.01, scale or 1) - 0.0001))
end
function SeasonTrack.buttonTop(bh) return math.min(56, 102 - bh) end

function SeasonTrack.fit(viewW, viewH, hasPremium)
	local step = SeasonTrack.TILE_W + SeasonTrack.TILE_GAP
	local availW = math.floor(viewW * 0.94) - 30
	local tiles = math.max(3, math.min(SeasonTrack.TILES_VISIBLE, math.floor((availW + SeasonTrack.TILE_GAP) / step)))
	local trackW = tiles * step - SeasonTrack.TILE_GAP
	local trackH = SeasonTrack.TILE_H + (hasPremium and SeasonTrack.PREMIUM_H or 0) + 26
	local panelW, panelH = trackW + 30, trackH + SeasonTrack.PANEL_EXTRA_H
	local scale = math.min(1, (viewH - 24) / panelH, (viewW - 12) / panelW)
	scale = math.max(0.8, scale)
	return { tiles = tiles, trackW = trackW, trackH = trackH, panelW = panelW, panelH = panelH, scale = scale,
		shownW = panelW * scale, shownH = panelH * scale }
end

-- Painted art for a Tips reward by size: small pouch (up to 3), coin purse (4 to 5), big pouch (6 to 7), chest (8 and up).
-- Returns the ContentArt category and key (all four already exist).
function SeasonTrack.tipsArt(amount)
	amount = tonumber(amount) or 0
	if amount <= 3 then return "rewards_emblems", "rewards_pouch_small" end
	if amount <= 5 then return "hud", "coin_purse" end
	if amount <= 7 then return "rewards_emblems", "rewards_pouch_full" end
	return "discoveries", "chest"
end

-- The reward line under a Premium cell: shown once per run of identical rewards ("Season Stamp" only on the first of a run).
function SeasonTrack.premiumLabelShown(prevText, text)
	return text ~= nil and text ~= "" and text ~= prevText
end

-- Short reward text ("+3 Tips next run"). `lookup` (optional) = { cardBackName, titleName } like TavernRank.rewardText.
function SeasonTrack.rewardText(reward, lookup)
	if reward and reward.kind == "tips" then
		return "+" .. reward.amount .. " Tips next run"
	elseif reward and reward.kind == "stamp" then
		return "Season Stamp"
	elseif reward and reward.kind == "set" then
		return "Card Set: " .. ((lookup and lookup.setName and lookup.setName(reward.id)) or reward.id)
	elseif reward and reward.kind == "flair" then
		local option = require(script.Parent.Flair).getById(reward.id)
		return "Flair: " .. (option and option.name or reward.id)
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

-- Cleans saved premium ownership and claims: only known season ids and real tiers survive.
function SeasonTrack.cleanPremium(rawPremium, rawClaimed)
	local owned, claimed = {}, {}
	if type(rawPremium) == "table" then
		for id, flag in pairs(rawPremium) do
			if flag == true and type(id) == "string" and SeasonTrack.getById(id) then owned[id] = true end
		end
	end
	if type(rawClaimed) == "table" then
		for tier, flag in pairs(rawClaimed) do
			if flag == true and type(tier) == "number" and tier == math.floor(tier) and tier >= 1 and tier <= SeasonTrack.TIERS then
				claimed[tier] = true
			end
		end
	end
	return owned, claimed
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
	local premiumOwned = SeasonTrack.hasPremium(profile, season)
	local premiumClaimed = (profile.seasonId == season.id) and profile.seasonPremiumClaimed or {}
	premiumClaimed = premiumClaimed or {}
	local premiumClaimable = 0
	for tier = 1, SeasonTrack.TIERS do
		local reward = SeasonTrack.rewardFor(season, tier)
		local isReached, isClaimed = tier <= reached, claimed[tier] == true
		if isReached and not isClaimed then claimable = claimable + 1 end
		local premiumReward = SeasonTrack.premiumRewardFor(season, tier)
		local premiumDone = premiumClaimed[tier] == true
		if premiumOwned and isReached and not premiumDone then premiumClaimable = premiumClaimable + 1 end
		tiers[tier] = {
			tier = tier, need = tier * SeasonTrack.XP_PER_TIER, reward = reward, text = SeasonTrack.rewardText(reward, lookup),
			reached = isReached, claimed = isClaimed,
			premium = { reward = premiumReward, text = SeasonTrack.rewardText(premiumReward, lookup), claimed = premiumDone, locked = not premiumOwned },
		}
	end
	return {
		id = season.id, name = season.name, bannerKey = season.bannerKey, daysLeft = SeasonTrack.daysLeft(season, day),
		xp = xp, tier = reached, maxed = reached >= SeasonTrack.TIERS, xpPerTier = SeasonTrack.XP_PER_TIER,
		into = reached >= SeasonTrack.TIERS and 0 or xp - reached * SeasonTrack.XP_PER_TIER,
		tiers = tiers, claimable = claimable + premiumClaimable,
		premium = { owned = premiumOwned, itemId = season.premiumItemId, claimable = premiumClaimable, perks = SeasonTrack.premiumPerks(season) },
	}
end

-- The first tier whose free reward is not claimed yet (nil when every tier is claimed).
function SeasonTrack.nextTier(view)
	for _, row in ipairs(view and view.tiers or {}) do
		if not row.claimed then return row end
	end
	return nil
end

-- One short line for the footer: what the next unclaimed tier gives, plus its Premium reward when Premium is not owned and it fits.
SeasonTrack.NEXT_LINE_MAX = 80
function SeasonTrack.nextLine(view)
	local row = SeasonTrack.nextTier(view)
	if not row then return "Every tier claimed. Nice work!" end
	local line
	if row.reached then
		line = "Tier " .. row.tier .. " is ready: " .. row.text .. ". Tap it to claim."
	else
		line = "Next reward at tier " .. row.tier .. ": " .. row.text .. "."
	end
	local prem = row.premium
	if prem and prem.locked and prem.text and prem.text ~= "" then
		local more = line .. " Premium adds " .. prem.text .. "."
		if #more <= SeasonTrack.NEXT_LINE_MAX then line = more end
	end
	return line
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
