-- "Next unlock" strip for the main menu: the closest Collection milestone or Journey reward, with progress.
-- Pure: reads a profile only. Also the map's "places seen" counter.
local CollectionBook = require(script.Parent.CollectionBook)
local JourneyMap = require(script.Parent.JourneyMap)
local WorldMap = require(script.Parent.WorldMap)

local NextUnlock = {}

local function collectionCandidate(profile)
	local milestone = CollectionBook.nextMilestone(profile.claimedMilestoneIds)
	if not milestone then
		return nil
	end
	local completion = CollectionBook.completion(CollectionBook.discoveredSetsFor(profile))
	local goal = math.max(1, math.ceil(milestone.percent * completion.total / 100))
	local labels = {}
	for _, reward in ipairs(milestone.rewards) do
		table.insert(labels, CollectionBook.rewardLabel(reward))
	end
	return {
		kind = "collection",
		label = string.format("Collection %d%%: %s", milestone.percent, table.concat(labels, " + ")),
		progress = math.min(completion.found, goal),
		goal = goal,
	}
end

local function journeyCandidate(profile)
	local node = JourneyMap.nextReward(profile.clearedNightIds or {})
	if not node then
		return nil
	end
	local best = profile.stats and profile.stats.bestNightReached or 0
	local goal = math.max(1, node.night or 1)
	local name = node.info.name or ("Night " .. tostring(node.night))
	return {
		kind = "journey",
		label = string.format("Beat Night %d (%s): %s", node.night or 0, name, JourneyMap.rewardLabel(node.info.reward)),
		progress = math.min(best, goal),
		goal = goal,
	}
end

-- The candidate that is furthest along (ties go to the Collection). nil when everything is claimed.
function NextUnlock.compute(profile)
	local best
	for _, candidate in ipairs({ collectionCandidate(profile), journeyCandidate(profile) }) do
		if candidate then
			if not best or candidate.progress / candidate.goal > best.progress / best.goal then
				best = candidate
			end
		end
	end
	return best
end

-- { seen, total } over every stop of the world map.
function NextUnlock.placesSeen(profile)
	local total, seen = 0, 0
	for id in pairs(WorldMap.Stops) do
		total = total + 1
		if profile.worldSeenStopIds and profile.worldSeenStopIds[id] then
			seen = seen + 1
		end
	end
	return { seen = seen, total = total }
end

return NextUnlock
