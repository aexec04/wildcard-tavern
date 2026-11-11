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
local BackgroundArt = require(script.Parent.BackgroundArt)

local JourneyMap = {}

JourneyMap.NightCap = 8

-- The road to the tavern: sandy road, flower fields, a garden, a river, mountains,
-- and only then the tavern itself (gate, grand hall, the Keeper's table).
-- `art` is the SceneArt / map_nodes key; x, y are rough canvas fractions (the Journey
-- view spaces nodes itself; they only matter for the Studio Nudge tool).
JourneyMap.Nights = {
	{ night = 1, name = "The Dusty Road", art = "dusty_road", icon = "DR",
		x = 0.05, y = 0.62,
		description = "Sandy gravel underfoot and a long road ahead. Every journey starts somewhere.",
		reward = { kind = "title", id = "porch_regular" } },
	{ night = 2, name = "The Wildflower Meadow", art = "wildflower_meadow", icon = "WM",
		x = 0.2, y = 0.3,
		description = "Fields of bright flowers hum with bees, and the first lanterns glow far off.",
		reward = { kind = "cardBack", id = "kitchen_checks" } },
	{ night = 3, name = "The Lantern Garden", art = "garden_terrace", icon = "LG",
		x = 0.33, y = 0.64,
		description = "Fairy lights and flower beds make a calm stop before the harder road.",
		reward = { kind = "set", id = "winter_evening" } },
	{ night = 4, name = "The Willow Bridge", art = "willow_bridge", icon = "WB",
		x = 0.47, y = 0.3,
		description = "A stone bridge over a quiet river. Cross it and the road gets steeper.",
		reward = { kind = "title", id = "loft_climber" } },
	{ night = 5, name = "The Mountain Pass", art = "mountain_pass", icon = "MP",
		x = 0.64, y = 0.66,
		description = "A narrow trail over snowy peaks, with the tavern lights somewhere beyond.",
		reward = { kind = "set", id = "festival_night" } },
	{ night = 6, name = "The Tavern Gate", art = "tavern_gate", icon = "TG",
		x = 0.76, y = 0.3,
		description = "Lanterns and cobblestones. The tavern is finally in sight.",
		reward = { kind = "cardBack", id = "hall_banner" } },
	{ night = 7, name = "The Grand Hall", art = "grand_hall", icon = "GH",
		x = 0.84, y = 0.64,
		description = "Chandeliers, banners and a very serious crowd.",
		reward = { kind = "set", id = "closing_time" } },
	{ night = 8, name = "The Keeper's Table", art = "keepers_table", icon = "KT",
		x = 0.91, y = 0.32,
		description = "The last table of the tavern. Win here and it's yours.",
		reward = { kind = "title", id = "tavern_keeper" } },
}

-- Endless Nights (9 and beyond) are played back in the old tavern rooms, in this
-- order (SceneKeys.artFor). These keys exist in SceneArt but have no map node.
JourneyMap.EndlessScenes = { "front_porch", "warm_kitchen", "snug_booth", "cozy_loft", "rooftop_view" }

-- Painted map image. Fill in a real id; "rbxassetid://0" (or a failed load)
-- falls back to the UI-built parchment look.
JourneyMap.Config = {
	journeyMapImage = BackgroundArt.journey_map or "rbxassetid://0",
	mapAspect = 7.5, -- canvas width / height: five region tiles of 1.5 each (the view sizes its canvas from its nodes)
}

JourneyMap.Endless = {
	name = "Endless Nights",
	art = "endless_portal",
	icon = "oo",
	description = "The doors never close. How far can you go?",
	x = 0.77, y = 0.64,
}

-- Extra nodes past the Endless doors. Clearing Night `night` (the boss round
-- of that Endless Night) for the first time grants the reward.
JourneyMap.EndlessMilestones = {
	{ night = 10, name = "Night Ten", icon = "10",
		description = "Ten nights in. The lanterns have all burned low.",
		x = 0.84, y = 0.32, reward = { kind = "title", id = "night_walker" } },
	{ night = 15, name = "Night Fifteen", icon = "15",
		description = "Fifteen nights. Even the stars are watching your table.",
		x = 0.91, y = 0.64, reward = { kind = "cardBack", id = "ember_hours" } },
	{ night = 20, name = "Night Twenty", icon = "20",
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
	{ icon = "I", label = "Boss I" },
	{ icon = "II", label = "Boss II" },
	{ icon = "III", label = "Boss III" },
}

-- Icon and noun per reward kind, for previews.
JourneyMap.RewardKinds = {
	cardBack = { icon = "", noun = "Card back" },
	set = { icon = "", noun = "Card set" },
	title = { icon = "", noun = "Title" },
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

-- ===== Fog of war =====
-- A node's place on the Night line: Nights are themselves, the Endless doors
-- sit just past the cap, milestones are their Endless Night.
function JourneyMap.nodePosition(node)
	if node.kind == "endless" then
		return JourneyMap.NightCap + 1
	end
	return node.night
end

JourneyMap.RevealAhead = 3 -- Nights past the current one that are fully drawn

-- "revealed" (current Night and the next RevealAhead, or anything cleared),
-- "teaser" (the Night right after those), or "hidden" (everything beyond).
function JourneyMap.revealState(position, currentNight, cleared)
	if cleared then
		return "revealed"
	end
	local ahead = position - math.max(currentNight, 1)
	if ahead <= JourneyMap.RevealAhead then
		return "revealed"
	elseif ahead == JourneyMap.RevealAhead + 1 then
		return "teaser"
	end
	return "hidden"
end

-- Reveal state for every node in allNodes() order. `clearedNights` =
-- { [night] = true }; `endlessOpen` marks the Endless doors as seen. Fog
-- rolls back from the left only: any node before a revealed one is revealed.
function JourneyMap.nodeRevealStates(currentNight, clearedNights, endlessOpen)
	local nodes = JourneyMap.allNodes()
	local states = {}
	for i, node in ipairs(nodes) do
		local isCleared
		if node.kind == "endless" then
			isCleared = endlessOpen == true
		else
			isCleared = clearedNights[node.night] == true
		end
		states[i] = JourneyMap.revealState(JourneyMap.nodePosition(node), currentNight, isCleared)
	end
	local lastRevealed = 0
	for i = #states, 1, -1 do
		if states[i] == "revealed" then
			lastRevealed = i
			break
		end
	end
	for i = 1, lastRevealed do
		states[i] = "revealed"
	end
	return states
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

-- Display text for a reward, e.g. 'Title: "Road Walker"'.
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
