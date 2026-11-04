--[[
	JourneyMap.lua
	The meta layer behind the Journey screen: 8 named tavern locations (one
	per Night), an Endless Mode node after them, and a cosmetic reward for
	clearing each Night for the first time. Content only; no gameplay effect.

	Night = { night, name, description, icon, x, y, reward }
	x, y are normalized (0-1) positions on the map image, so nodes can be
	moved by editing numbers here only.
	reward = { kind = "cardBack" | "set" | "title", id = <registry id> }
	  cardBack -> CardBacks id, goes into profile.unlockedCardBackIds
	  set      -> CosmeticSets id, goes into profile.ownedSetIds
	  title    -> Achievements id (milestoneReward), goes into profile.rewardTitleIds

	Endless milestones (JourneyMap.EndlessMilestones) are extra nodes past
	Night 8: clearing that Endless Night for the first time grants the reward.
	They are saved in the same profile.clearedNightIds (keyed by Night number).

	"Cleared" means the Night's last round (its boss round) was beaten. First
	clears are saved in profile.clearedNightIds. Revived runs don't count
	(the server checks RunState.countsForRecords before recording).
]]

local CosmeticSets = require(script.Parent.CosmeticSets)
local CardBacks = require(script.Parent.CardBacks)
local Achievements = require(script.Parent.Achievements)

local JourneyMap = {}

JourneyMap.NightCap = 8

JourneyMap.Nights = {
	{ night = 1, name = "The Front Porch", icon = "🏮",
		x = 0.05, y = 0.62,
		description = "Rocking chairs, lantern light and the first friendly faces.",
		reward = { kind = "title", id = "porch_regular" } },
	{ night = 2, name = "The Warm Kitchen", icon = "🍲",
		x = 0.14, y = 0.3,
		description = "Soup on the stove and a busy crowd at the counter.",
		reward = { kind = "cardBack", id = "kitchen_checks" } },
	{ night = 3, name = "The Snug Booth", icon = "🛋",
		x = 0.23, y = 0.64,
		description = "A quiet corner where the stakes quietly rise.",
		reward = { kind = "set", id = "winter_evening" } },
	{ night = 4, name = "The Cozy Loft", icon = "🪜",
		x = 0.32, y = 0.3,
		description = "Creaky stairs lead to sharper players.",
		reward = { kind = "title", id = "loft_climber" } },
	{ night = 5, name = "The Garden Terrace", icon = "🌿",
		x = 0.41, y = 0.66,
		description = "Fairy lights strung over a night of friendly games.",
		reward = { kind = "set", id = "festival_night" } },
	{ night = 6, name = "The Grand Hall", icon = "🏛",
		x = 0.5, y = 0.3,
		description = "Chandeliers, banners and a very serious crowd.",
		reward = { kind = "cardBack", id = "hall_banner" } },
	{ night = 7, name = "The Rooftop View", icon = "🌙",
		x = 0.59, y = 0.64,
		description = "The whole town sleeps below. The cards stay awake.",
		reward = { kind = "set", id = "closing_time" } },
	{ night = 8, name = "The Keeper's Table", icon = "👑",
		x = 0.68, y = 0.32,
		description = "The last table of the tavern. Win here and it's yours.",
		reward = { kind = "title", id = "tavern_keeper" } },
}

-- Painted map image. Fill in a real id; "rbxassetid://0" (or a failed load)
-- falls back to the UI-built parchment look.
JourneyMap.Config = {
	journeyMapImage = "rbxassetid://0",
	mapAspect = 2.8, -- canvas width / height; the image should match it
}

JourneyMap.Endless = {
	name = "Endless Nights",
	icon = "♾",
	description = "The doors never close. How far can you go?",
	x = 0.77, y = 0.64,
}

-- Extra nodes past the Endless doors. Clearing Night `night` (the boss round
-- of that Endless Night) for the first time grants the reward.
JourneyMap.EndlessMilestones = {
	{ night = 10, name = "Night Ten", icon = "🌠",
		description = "Ten nights in. The lanterns have all burned low.",
		x = 0.84, y = 0.32, reward = { kind = "title", id = "night_walker" } },
	{ night = 15, name = "Night Fifteen", icon = "🔥",
		description = "Fifteen nights. Even the stars are watching your table.",
		x = 0.91, y = 0.64, reward = { kind = "cardBack", id = "ember_hours" } },
	{ night = 20, name = "Night Twenty", icon = "🌌",
		description = "Twenty nights. They will tell stories about this one.",
		x = 0.96, y = 0.30, reward = { kind = "title", id = "endless_legend" } },
}

-- Endless header colors ({r, g, b} 0-255) shared by Journey and Round Select.
JourneyMap.EndlessTheme = {
	accent = { 180, 140, 255 },
	background = { 34, 26, 54 },
	subtitle = { 205, 190, 240 },
}

-- Icon and wording per boss tier (see bossTierFor).
JourneyMap.BossTiers = {
	{ icon = "⚔", label = "Boss ★" },
	{ icon = "🛡", label = "Boss ★★" },
	{ icon = "👑", label = "Boss ★★★" },
}

-- Icon and noun per reward kind, for previews.
JourneyMap.RewardKinds = {
	cardBack = { icon = "🃏", noun = "Card back" },
	set = { icon = "🖼", noun = "Card set" },
	title = { icon = "🏅", noun = "Title" },
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
		local entry = JourneyMap.Nights[night] or JourneyMap.getMilestone(night)
		if entry then
			grant(profile, entry.reward)
		end
	end
end


-- ===== Endless milestones =====

function JourneyMap.getMilestone(night)
	for _, entry in ipairs(JourneyMap.EndlessMilestones) do
		if entry.night == night then
			return entry
		end
	end
	return nil
end

-- Nights cleared this run with no cap (Endless Nights count). Same rules as
-- nightsClearedFor, but a won run isn't snapped back to 8.
function JourneyMap.totalNightsClearedFor(state)
	local cleared = state.night - 1
	if state.roundOver and not state.runOver and state.round == state.config.roundsPerNight then
		cleared = state.night
	end
	return math.max(0, cleared)
end

-- Records every Endless milestone whose Night is <= `count` as cleared and
-- grants its reward once. Returns the newly cleared Night numbers.
function JourneyMap.recordEndlessCleared(profile, count)
	local fresh = {}
	if type(count) ~= "number" then
		return fresh
	end
	for _, entry in ipairs(JourneyMap.EndlessMilestones) do
		if count >= entry.night and not profile.clearedNightIds[entry.night] then
			profile.clearedNightIds[entry.night] = true
			grant(profile, entry.reward)
			table.insert(fresh, entry.night)
		end
	end
	return fresh
end

-- Every node in map order: Nights 1-8, the Endless doors, then milestones.
-- Each: { key, kind = "night"|"endless"|"milestone", night, info }
function JourneyMap.allNodes()
	local list = {}
	for _, entry in ipairs(JourneyMap.Nights) do
		table.insert(list, { key = entry.night, kind = "night", night = entry.night, info = entry })
	end
	table.insert(list, { key = "endless", kind = "endless", info = JourneyMap.Endless })
	for _, entry in ipairs(JourneyMap.EndlessMilestones) do
		table.insert(list, { key = entry.night, kind = "milestone", night = entry.night, info = entry })
	end
	return list
end

-- Journey completion across every reward node. `cleared` = { [night] = true }.
-- Returns cleared count, total, whole percent.
function JourneyMap.completion(cleared)
	local done, total = 0, 0
	for _, node in ipairs(JourneyMap.allNodes()) do
		if node.info.reward then
			total = total + 1
			if cleared[node.night] then
				done = done + 1
			end
		end
	end
	return done, total, total > 0 and math.floor(done * 100 / total) or 0
end

-- The first reward node (in map order) not cleared yet, or nil when done.
function JourneyMap.nextReward(cleared)
	for _, node in ipairs(JourneyMap.allNodes()) do
		if node.info.reward and not cleared[node.night] then
			return node
		end
	end
	return nil
end

-- ===== Rewards: earned and equip =====

-- A reward is earned once its node is cleared on this profile.
function JourneyMap.isRewardEarned(profile, night)
	local entry = JourneyMap.Nights[night] or JourneyMap.getMilestone(night)
	return entry ~= nil and profile.clearedNightIds[night] == true
end

-- Equips the reward of the node for `night`, only if it was earned.
-- Returns (ok, message). Uses the same equip logic as the cosmetics panel.
function JourneyMap.equipReward(profile, night, ownedPassIds)
	if type(night) ~= "number" then
		return false, "Unknown reward"
	end
	local entry = JourneyMap.Nights[night] or JourneyMap.getMilestone(night)
	if not entry then
		return false, "Unknown reward"
	end
	if not JourneyMap.isRewardEarned(profile, night) then
		return false, "Reward not earned yet"
	end
	local reward = entry.reward
	if reward.kind == "cardBack" then
		return CosmeticSets.equipCardBack(profile, reward.id, ownedPassIds)
	elseif reward.kind == "set" then
		return CosmeticSets.equip(profile, reward.id, ownedPassIds)
	elseif reward.kind == "title" then
		if not profile.rewardTitleIds[reward.id] then
			return false, "Title not unlocked"
		end
		profile.equippedTitleId = reward.id
		return true, "Title equipped."
	end
	return false, "Unknown reward"
end

-- How a reward unlocks, for the detail card.
function JourneyMap.unlockText(node)
	if node.kind == "night" then
		return string.format("Beat the boss round of Night %d for the first time.", node.night)
	end
	return string.format("Reach and beat the boss round of Endless Night %d.", node.night)
end

-- Display text for a reward, e.g. 'Title: "Porch Regular"'.
function JourneyMap.rewardLabel(reward, lookups)
	lookups = lookups or { cardBack = CardBacks, set = CosmeticSets, title = Achievements }
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
