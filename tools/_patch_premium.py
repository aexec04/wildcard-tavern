p = "src/Shared/Engine/SeasonTrack.lua"
s = open(p, encoding="utf-8").read()

# grants: flair and set
s = s.replace('''	elseif reward.kind == "cardBack" then
		profile.unlockedCardBackIds = profile.unlockedCardBackIds or {}
		profile.unlockedCardBackIds[reward.id] = true
	end
end

-- Claims one tier:''', '''	elseif reward.kind == "cardBack" then
		profile.unlockedCardBackIds = profile.unlockedCardBackIds or {}
		profile.unlockedCardBackIds[reward.id] = true
	elseif reward.kind == "set" then
		profile.ownedSetIds = profile.ownedSetIds or {}
		profile.ownedSetIds[reward.id] = true
	elseif reward.kind == "flair" then
		require(script.Parent.Flair).grantOwned(profile, reward.id)
	end
end

-- Claims one tier:''')

# reset also clears premium claims
s = s.replace('''	profile.seasonId = season.id
	profile.seasonXp = 0
	profile.seasonClaimed = {}
	return true
end''', '''	profile.seasonId = season.id
	profile.seasonXp = 0
	profile.seasonClaimed = {}
	profile.seasonPremiumClaimed = {} -- the premium pass of an old season stays recorded (seasonPremium), its claims reset
	return true
end''')

# premium claims after claimAll
s = s.replace('''-- Short reward text ("+3 Tips next run").''', '''-- Claims one PREMIUM tier: the season's premium pass must be owned, the tier reached and not claimed, the season running.
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

-- Short reward text ("+3 Tips next run").''')

# rewardText knows set and flair
s = s.replace('''function SeasonTrack.rewardText(reward, lookup)
	if reward and reward.kind == "tips" then
		return "+" .. reward.amount .. " Tips next run"
	end''', '''function SeasonTrack.rewardText(reward, lookup)
	if reward and reward.kind == "tips" then
		return "+" .. reward.amount .. " Tips next run"
	elseif reward and reward.kind == "set" then
		return "Card Set: " .. ((lookup and lookup.setName and lookup.setName(reward.id)) or reward.id)
	elseif reward and reward.kind == "flair" then
		local option = require(script.Parent.Flair).getById(reward.id)
		return "Flair: " .. (option and option.name or reward.id)
	end''')

# view: premium
s = s.replace('''	local tiers, claimable = {}, 0
	for tier = 1, SeasonTrack.TIERS do
		local reward = SeasonTrack.rewardFor(season, tier)
		local isReached, isClaimed = tier <= reached, claimed[tier] == true
		if isReached and not isClaimed then claimable = claimable + 1 end
		tiers[tier] = {
			tier = tier, need = tier * SeasonTrack.XP_PER_TIER, reward = reward, text = SeasonTrack.rewardText(reward, lookup),
			reached = isReached, claimed = isClaimed,
		}
	end''', '''	local tiers, claimable = {}, 0
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
	end''')
s = s.replace('''		tiers = tiers, claimable = claimable,
	}
end''', '''		tiers = tiers, claimable = claimable + premiumClaimable,
		premium = { owned = premiumOwned, itemId = season.premiumItemId, claimable = premiumClaimable, perks = SeasonTrack.premiumPerks(season) },
	}
end''')

# save / load for the premium fields
s = s.replace('''-- What the client draws. nil when no season runs and none is coming.''', '''-- Cleans saved premium ownership and claims: only known season ids and real tiers survive.
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

-- What the client draws. nil when no season runs and none is coming.''')
open(p, "w", encoding="utf-8").write(s)
print("patched")
