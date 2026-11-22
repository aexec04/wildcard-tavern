--[[
	CollectionRewards.lua
	Completion rewards per Collection group: at 25, 50, 75 and 100 percent of Patrons, Recipes, Boss Rounds, Card Sets,
	Titles and Badges a cosmetic or a few Tips are waiting, claimed with a button, once each. Pure Lua, no Roblox APIs.

	Progress: Patrons, Recipes, Bosses and Titles come from Engine/CollectionBook.completion (reward titles do not count);
	Card Sets are the owned sets of the CosmeticSets registry; Badges are the earned badges of the Badges registry.
	Rewards come from existing registries (Tips for the next run, card backs) and one NEW title per group at 100 percent
	(Achievements entries flagged milestoneReward, granted into rewardTitleIds). Nothing has gameplay power.

	Profile field: collectionRewardsClaimed = { ["patrons:50"] = true, ... }, cleaned on load (unknown keys are dropped).
]]

local CollectionBook = require(script.Parent.CollectionBook)
local CosmeticSets = require(script.Parent.CosmeticSets)
local Badges = require(script.Parent.Badges)
local Flair = require(script.Parent.Flair)
local TavernRank = require(script.Parent.TavernRank)

local CollectionRewards = {}

CollectionRewards.Percents = { 25, 50, 75, 100 }

-- display order; `tab` = the CollectionBook tab that measures it (nil: measured here)
CollectionRewards.Groups = {
	{ id = "patrons", name = "Patrons", icon = "🧑‍🍳", tab = "patrons" },
	{ id = "recipes", name = "Recipes", icon = "📖", tab = "recipes" },
	{ id = "bosses", name = "Boss Rounds", icon = "👑", tab = "bosses" },
	{ id = "sets", name = "Card Sets", icon = "🎴" },
	{ id = "titles", name = "Titles", icon = "🏷️", tab = "titles" },
	{ id = "badges", name = "Badges", icon = "🏅" },
	{ id = "flair", name = "Flair", icon = "✨" },
}

-- EDIT ME. kind: tips (next run) | cardBack (CardBacks id) | title (an Achievements id with milestoneReward = true).
CollectionRewards.Rewards = {
	patrons = { [25] = { kind = "tips", amount = 2 }, [50] = { kind = "tips", amount = 3 }, [75] = { kind = "cardBack", id = "kitchen_checks" }, [100] = { kind = "title", id = "book_patrons" } },
	recipes = { [25] = { kind = "tips", amount = 2 }, [50] = { kind = "tips", amount = 3 }, [75] = { kind = "cardBack", id = "hall_banner" }, [100] = { kind = "title", id = "book_recipes" } },
	bosses = { [25] = { kind = "tips", amount = 2 }, [50] = { kind = "tips", amount = 3 }, [75] = { kind = "cardBack", id = "winter_frost" }, [100] = { kind = "title", id = "book_bosses" } },
	sets = { [25] = { kind = "tips", amount = 2 }, [50] = { kind = "tips", amount = 3 }, [75] = { kind = "cardBack", id = "dune_gold" }, [100] = { kind = "title", id = "book_sets" } },
	titles = { [25] = { kind = "tips", amount = 2 }, [50] = { kind = "tips", amount = 3 }, [75] = { kind = "cardBack", id = "lilypad_green" }, [100] = { kind = "title", id = "book_titles" } },
	-- Flair has no Achievements title, so every step pays Tips only.
	flair = { [25] = { kind = "tips", amount = 2 }, [50] = { kind = "tips", amount = 3 }, [75] = { kind = "tips", amount = 4 }, [100] = { kind = "tips", amount = 5 } },
	badges = { [25] = { kind = "tips", amount = 2 }, [50] = { kind = "tips", amount = 3 }, [75] = { kind = "cardBack", id = "shell_pearl" }, [100] = { kind = "title", id = "book_badges" } },
}

local GROUP_BY_ID = {}
for _, g in ipairs(CollectionRewards.Groups) do GROUP_BY_ID[g.id] = g end

local function countIn(set, registry)
	local n = 0
	for _, def in ipairs(registry) do
		if type(set) == "table" and set[def.id] == true then n = n + 1 end
	end
	return n
end

-- { found, total, percent } for each group id.
function CollectionRewards.progress(profile)
	local completion = CollectionBook.completion(CollectionBook.discoveredSetsFor(profile))
	local out = {}
	for _, g in ipairs(CollectionRewards.Groups) do
		local found, total
		if g.tab then
			local t = completion.tabs[g.tab]
			found, total = t.found, t.total
		elseif g.id == "sets" then
			found, total = countIn(profile.ownedSetIds, CosmeticSets.Definitions), #CosmeticSets.Definitions
		elseif g.id == "flair" then
			found, total = 0, 0
			for _, slot in ipairs(Flair.Slots) do
				for _, option in ipairs(Flair.optionsFor(slot.id)) do
					if not option.default then
						total = total + 1
						if Flair.isOwned(profile, option.id) then found = found + 1 end
					end
				end
			end
		else
			found, total = countIn(profile.badgeIds, Badges.Definitions), #Badges.Definitions
		end
		out[g.id] = { found = found, total = total, percent = total > 0 and math.floor(found * 100 / total) or 0 }
	end
	return out
end

-- Integer rule, like CollectionBook.isMilestoneReached: 100 means every entry, not 99.6 rounded up.
local function reached(p, pct)
	return p.total > 0 and p.found * 100 >= pct * p.total
end

local function key(group, pct)
	return group .. ":" .. pct
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

-- Claims one milestone once. Returns ok, reward | reason.
function CollectionRewards.claim(profile, group, pct)
	if type(group) ~= "string" or not GROUP_BY_ID[group] or type(pct) ~= "number" then
		return false, "Unknown reward."
	end
	local reward = CollectionRewards.Rewards[group][pct]
	if not reward then
		return false, "Unknown reward."
	end
	profile.collectionRewardsClaimed = profile.collectionRewardsClaimed or {}
	if profile.collectionRewardsClaimed[key(group, pct)] then
		return false, "Already claimed."
	end
	if not reached(CollectionRewards.progress(profile)[group], pct) then
		return false, "Not reached yet."
	end
	profile.collectionRewardsClaimed[key(group, pct)] = true
	grant(profile, reward)
	return true, reward
end

-- Claims everything that is ready. Returns the list of { group, pct, reward }.
function CollectionRewards.claimAll(profile)
	local claimed = {}
	for _, g in ipairs(CollectionRewards.Groups) do
		for _, pct in ipairs(CollectionRewards.Percents) do
			local ok, reward = CollectionRewards.claim(profile, g.id, pct)
			if ok then claimed[#claimed + 1] = { group = g.id, pct = pct, reward = reward } end
		end
	end
	return claimed
end

-- Short text for a reward. `lookup` (optional) = { cardBackName = fn(id), titleName = fn(id) } like TavernRank.rewardText.
function CollectionRewards.rewardText(reward, lookup)
	return TavernRank.rewardText(reward, lookup)
end

-- What the client draws: per group a ring percent and four milestones { pct, reward, text, reached, claimed }.
function CollectionRewards.view(profile, lookup)
	local progress = CollectionRewards.progress(profile)
	local claimedSet = profile.collectionRewardsClaimed or {}
	local rows, claimable = {}, 0
	for _, g in ipairs(CollectionRewards.Groups) do
		local p = progress[g.id]
		local milestones = {}
		for _, pct in ipairs(CollectionRewards.Percents) do
			local reward = CollectionRewards.Rewards[g.id][pct]
			local isReached, isClaimed = reached(p, pct), claimedSet[key(g.id, pct)] == true
			if isReached and not isClaimed then claimable = claimable + 1 end
			milestones[#milestones + 1] = {
				pct = pct, reward = reward, text = CollectionRewards.rewardText(reward, lookup), reached = isReached, claimed = isClaimed,
			}
		end
		rows[#rows + 1] = { id = g.id, name = g.name, icon = g.icon, found = p.found, total = p.total, percent = p.percent, milestones = milestones }
	end
	return { groups = rows, claimable = claimable }
end

-- Cleans saved claims: only real (group, percent) pairs survive.
function CollectionRewards.cleanSaved(raw)
	local out = {}
	if type(raw) == "table" then
		for k, flag in pairs(raw) do
			local group, pct = tostring(k):match("^(%a+):(%d+)$")
			if flag == true and group and GROUP_BY_ID[group] and CollectionRewards.Rewards[group][tonumber(pct)] then
				out[key(group, tonumber(pct))] = true
			end
		end
	end
	return out
end

return CollectionRewards
