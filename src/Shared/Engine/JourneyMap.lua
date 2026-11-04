--[[
	JourneyMap.lua
	The meta layer behind the Journey screen: 8 named tavern locations (one
	per Night), an Endless Mode node after them, and a cosmetic reward for
	clearing each Night for the first time. Content only; no gameplay effect.

	Night = { night, name, description, icon, reward }
	reward = { kind = "cardBack" | "set" | "title", id = <registry id> }
	  cardBack -> CardBacks id, goes into profile.unlockedCardBackIds
	  set      -> CosmeticSets id, goes into profile.ownedSetIds
	  title    -> Achievements id (milestoneReward), goes into profile.rewardTitleIds

	"Cleared" means the Night's last round (its boss round) was beaten. First
	clears are saved in profile.clearedNightIds. Revived runs don't count
	(the server checks RunState.countsForRecords before recording).
]]

local JourneyMap = {}

JourneyMap.NightCap = 8

JourneyMap.Nights = {
	{ night = 1, name = "The Front Porch", icon = "🏮",
		description = "Rocking chairs, lantern light and the first friendly faces.",
		reward = { kind = "title", id = "porch_regular" } },
	{ night = 2, name = "The Warm Kitchen", icon = "🍲",
		description = "Soup on the stove and a busy crowd at the counter.",
		reward = { kind = "cardBack", id = "kitchen_checks" } },
	{ night = 3, name = "The Snug Booth", icon = "🛋",
		description = "A quiet corner where the stakes quietly rise.",
		reward = { kind = "set", id = "winter_evening" } },
	{ night = 4, name = "The Cozy Loft", icon = "🪜",
		description = "Creaky stairs lead to sharper players.",
		reward = { kind = "title", id = "loft_climber" } },
	{ night = 5, name = "The Garden Terrace", icon = "🌿",
		description = "Fairy lights strung over a night of friendly games.",
		reward = { kind = "set", id = "festival_night" } },
	{ night = 6, name = "The Grand Hall", icon = "🏛",
		description = "Chandeliers, banners and a very serious crowd.",
		reward = { kind = "cardBack", id = "hall_banner" } },
	{ night = 7, name = "The Rooftop View", icon = "🌙",
		description = "The whole town sleeps below. The cards stay awake.",
		reward = { kind = "set", id = "closing_time" } },
	{ night = 8, name = "The Keeper's Table", icon = "👑",
		description = "The last table of the tavern. Win here and it's yours.",
		reward = { kind = "title", id = "tavern_keeper" } },
}

JourneyMap.Endless = {
	name = "Endless Nights",
	icon = "♾",
	description = "The doors never close. How far can you go?",
}

function JourneyMap.getNight(night)
	return JourneyMap.Nights[night]
end

-- Boss difficulty tier shown on the map (1-3), from BossRounds' minNight tiers.
function JourneyMap.bossTierFor(night)
	if night >= 6 then
		return 3
	elseif night >= 3 then
		return 2
	end
	return 1
end

-- How many Nights this run has cleared so far (0..NightCap): Nights before
-- the current one, plus the current one once its boss round is won (the
-- shop between Nights), or all 8 once the run is won.
function JourneyMap.nightsClearedFor(state)
	local cap = state.config and state.config.nightCap or JourneyMap.NightCap
	if state.wonRun then
		return math.min(cap, JourneyMap.NightCap)
	end
	local cleared = state.night - 1
	if state.roundOver and not state.runOver and state.round == state.config.roundsPerNight then
		cleared = state.night
	end
	return math.max(0, math.min(cleared, JourneyMap.NightCap))
end

local function grant(profile, reward)
	if reward.kind == "cardBack" then
		profile.unlockedCardBackIds[reward.id] = true
	elseif reward.kind == "set" then
		profile.ownedSetIds[reward.id] = true
	elseif reward.kind == "title" then
		profile.rewardTitleIds[reward.id] = true
	end
end

-- Records Nights 1..count as cleared and grants the reward for each Night
-- that is newly cleared. Returns the list of newly cleared Night numbers
-- (empty when nothing changed), so the caller can save and notify.
function JourneyMap.recordNightsCleared(profile, count)
	local fresh = {}
	if type(count) ~= "number" then
		return fresh
	end
	for night = 1, math.min(math.floor(count), JourneyMap.NightCap) do
		if not profile.clearedNightIds[night] then
			profile.clearedNightIds[night] = true
			grant(profile, JourneyMap.Nights[night].reward)
			table.insert(fresh, night)
		end
	end
	return fresh
end

-- Re-applies every earned reward (safe to repeat). Used after loading, so a
-- reward added to the table later still reaches players who already cleared.
function JourneyMap.regrantRewards(profile)
	for night in pairs(profile.clearedNightIds) do
		local entry = JourneyMap.Nights[night]
		if entry then
			grant(profile, entry.reward)
		end
	end
end

-- Display text for a reward, e.g. 'Title: "Porch Regular"'.
function JourneyMap.rewardLabel(reward, lookups)
	local def = lookups and lookups[reward.kind] and lookups[reward.kind].getById(reward.id)
	if reward.kind == "title" then
		return 'Title: "' .. (def and def.title or reward.id) .. '"'
	elseif reward.kind == "cardBack" then
		return "Card back: " .. (def and def.name or reward.id)
	elseif reward.kind == "set" then
		return "Card set: " .. (def and def.name or reward.id)
	end
	return tostring(reward.id)
end

return JourneyMap
