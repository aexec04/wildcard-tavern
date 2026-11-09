--[[
	TavernRank.lua
	The account level. 30 ranks. XP comes from hands played, rounds cleared, bosses beaten, run wins, the first win
	of the day and daily quests. Every rank has a reward (Tips for the next run, a title, a card back or a Card Set),
	all reused cosmetics or tiny numbers, never gameplay power. Pure Lua, no Roblox APIs.

	Profile fields: tavernXp (total XP), tavernRank (derived, kept so Engine/Unlocks can read it),
	pendingStartTips (Tips added to the next normal run's start, capped), rankRewardIds ([rank] = true, granted once),
	lastFirstWinDay (UTC day number of the last "first win of the day" bonus).
]]

local TavernRank = {}

TavernRank.MAX_RANK = 30
TavernRank.MAX_PENDING_TIPS = 30

-- XP needed to go from rank r to r + 1.
function TavernRank.xpToNext(rank)
	return 80 + 20 * (rank - 1)
end

-- Total XP at which `rank` is reached (rank 1 = 0).
function TavernRank.xpForRank(rank)
	local total = 0
	for r = 1, math.min(rank, TavernRank.MAX_RANK) - 1 do
		total = total + TavernRank.xpToNext(r)
	end
	return total
end

TavernRank.MAX_XP = TavernRank.xpForRank(TavernRank.MAX_RANK)

-- XP awards, in one place so they are easy to tune.
TavernRank.Xp = {
	hand = 1,
	round = 10,
	boss = 15,
	win = 150,
	firstWinOfDay = 50,
}

-- What a rank gives. kind: tips (next run), title (an Achievements id), cardBack (CardBacks id), set (CosmeticSets id).
TavernRank.Rewards = {
	[2] = { kind = "tips", amount = 3 }, [3] = { kind = "tips", amount = 3 },
	[4] = { kind = "cardBack", id = "kitchen_checks" },
	[5] = { kind = "title", id = "table_regular" },
	[6] = { kind = "tips", amount = 4 }, [7] = { kind = "tips", amount = 4 },
	[8] = { kind = "cardBack", id = "hall_banner" },
	[9] = { kind = "tips", amount = 5 },
	[10] = { kind = "title", id = "favorite_guest" },
	[11] = { kind = "tips", amount = 5 },
	[12] = { kind = "set", id = "winter_evening" },
	[13] = { kind = "tips", amount = 5 },
	[14] = { kind = "cardBack", id = "starlit_keeper" },
	[15] = { kind = "title", id = "house_captain" },
	[16] = { kind = "tips", amount = 6 }, [17] = { kind = "tips", amount = 6 },
	[18] = { kind = "tips", amount = 7 },
	[19] = { kind = "tips", amount = 6 },
	[20] = { kind = "title", id = "hall_warden" },
	[21] = { kind = "tips", amount = 7 }, [22] = { kind = "tips", amount = 7 },
	[23] = { kind = "cardBack", id = "winter_frost" },
	[24] = { kind = "set", id = "festival_night" },
	[25] = { kind = "tips", amount = 8 }, [26] = { kind = "tips", amount = 8 },
	[27] = { kind = "tips", amount = 10 },
	[28] = { kind = "tips", amount = 9 }, [29] = { kind = "tips", amount = 9 },
	[30] = { kind = "title", id = "grand_host" },
}

-- Painted medal art key for a rank: 6 tiers of 5 ranks each (ContentArt "rank_medals": tier_1 .. tier_6).
TavernRank.MEDAL_TIERS = 6
function TavernRank.medalKey(rank)
	local r = math.clamp and math.clamp(math.floor(tonumber(rank) or 1), 1, TavernRank.MAX_RANK)
		or math.max(1, math.min(TavernRank.MAX_RANK, math.floor(tonumber(rank) or 1)))
	return "tier_" .. math.ceil(r / (TavernRank.MAX_RANK / TavernRank.MEDAL_TIERS))
end

-- Short text for a reward ("+3 Tips next run"). `lookup` (optional) = { cardBackName = fn(id), setName = fn(id), titleName = fn(id) }.
function TavernRank.rewardText(reward, lookup)
	if not reward then
		return ""
	end
	lookup = lookup or {}
	if reward.kind == "tips" then
		return "+" .. reward.amount .. " Tips next run"
	elseif reward.kind == "title" then
		return "Title: " .. ((lookup.titleName and lookup.titleName(reward.id)) or reward.id)
	elseif reward.kind == "cardBack" then
		return "Card back: " .. ((lookup.cardBackName and lookup.cardBackName(reward.id)) or reward.id)
	elseif reward.kind == "set" then
		return "Card Set: " .. ((lookup.setName and lookup.setName(reward.id)) or reward.id)
	end
	return ""
end

-- Rank for a total XP amount.
function TavernRank.rankFor(xp)
	xp = math.max(0, xp or 0)
	local rank = 1
	while rank < TavernRank.MAX_RANK and xp >= TavernRank.xpForRank(rank + 1) do
		rank = rank + 1
	end
	return rank
end

-- The view the client draws: rank, XP into this rank, XP this rank needs, and the next reward.
function TavernRank.view(profile)
	local xp = math.min(profile.tavernXp or 0, TavernRank.MAX_XP)
	local rank = TavernRank.rankFor(xp)
	local maxed = rank >= TavernRank.MAX_RANK
	local into = xp - TavernRank.xpForRank(rank)
	local need = maxed and 0 or TavernRank.xpToNext(rank)
	local nextRank = maxed and nil or rank + 1
	return {
		rank = rank, xp = xp, into = into, need = need, maxed = maxed,
		nextRank = nextRank, nextReward = nextRank and TavernRank.Rewards[nextRank] or nil,
	}
end

local function grantReward(profile, reward)
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
	end
end

-- Grants every rank reward up to the profile's rank that was not granted yet (safe to call any time).
-- Returns the list of { rank, reward } granted just now.
function TavernRank.grantDue(profile)
	profile.rankRewardIds = profile.rankRewardIds or {}
	local rank = TavernRank.rankFor(profile.tavernXp or 0)
	profile.tavernRank = rank
	local granted = {}
	for r = 2, rank do
		local reward = TavernRank.Rewards[r]
		if reward and not profile.rankRewardIds[r] then
			profile.rankRewardIds[r] = true
			grantReward(profile, reward)
			granted[#granted + 1] = { rank = r, reward = reward }
		end
	end
	return granted
end

-- Adds XP (whole numbers only) and grants any rank rewards that became due.
-- Returns xpAdded, rankedUp (list of ranks gained), granted (list of { rank, reward }).
function TavernRank.addXp(profile, amount)
	amount = math.floor(tonumber(amount) or 0)
	if amount <= 0 then
		return 0, {}, {}
	end
	local before = TavernRank.rankFor(profile.tavernXp or 0)
	profile.tavernXp = math.min(TavernRank.MAX_XP, (profile.tavernXp or 0) + amount)
	local granted = TavernRank.grantDue(profile)
	local after = profile.tavernRank
	local ups = {}
	for r = before + 1, after do
		ups[#ups + 1] = r
	end
	return amount, ups, granted
end

-- XP for a batch of newly counted things: { hands, rounds, bosses, wins }.
function TavernRank.xpForCounts(counts)
	local x = TavernRank.Xp
	return (counts.hands or 0) * x.hand + (counts.rounds or 0) * x.round
		+ (counts.bosses or 0) * x.boss + (counts.wins or 0) * x.win
end

-- Takes the Tips banked for the next run (once), clearing the bank.
function TavernRank.takeStartTips(profile)
	local tips = math.max(0, math.floor(profile.pendingStartTips or 0))
	profile.pendingStartTips = 0
	return tips
end

-- First win of the UTC day: returns the bonus XP (0 when already taken today).
function TavernRank.firstWinBonus(profile, day)
	if type(day) ~= "number" or profile.lastFirstWinDay == day then
		return 0
	end
	profile.lastFirstWinDay = day
	return TavernRank.Xp.firstWinOfDay
end

return TavernRank
