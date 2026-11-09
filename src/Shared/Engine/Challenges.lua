--[[
	Challenges.lua
	Challenge runs: a normal run with one twist, picked in Run Setup. Six twists, each a small data entry. Clearing
	one (winning the run) awards its title once and is remembered in the profile (profile.challengesCleared).
	There are no separate boards: results stay in the profile. Pure Lua, no Roblox APIs.

	Fields per twist:
	  id, name, icon, text
	  titleId          Achievements reward title granted on the first clear
	  config           { key = delta }   added to state.config before the first round
	  setConfig        { key = value }   set on state.config
	  rules            scoring/economy rules copied into state.challenge (read by Engine/BossRules and RunState):
	                     noScoreHandTypes, patronPower, glassChance (percent), tipsPercent, speedSeconds

	A challenge run still counts for quests and XP (it is a normal run); it never unlocks the next Stake.
]]

local TavernRank = require(script.Parent.TavernRank)

local Challenges = {}

Challenges.GLASS_MIN_CARDS = 36 -- a Glass Deck never breaks below this many cards in the run
Challenges.SPEED_BONUS_XP = 150

Challenges.Definitions = {
	{
		id = "pairs_only", name = "Pairs Only", icon = "👯",
		text = "Only hands made of matching ranks score. Straights, Flushes and High Card score nothing.",
		titleId = "pair_master",
		rules = { noScoreHandTypes = { ["High Card"] = true, ["Straight"] = true, ["Flush"] = true, ["Straight Flush"] = true } },
	},
	{
		id = "no_discards", name = "No Discards", icon = "🚫",
		text = "You cannot discard, but every round gives 2 extra Hands.",
		titleId = "steady_dealer",
		config = { handsPerRound = 2 }, setConfig = { discardsPerRound = 0 },
	},
	{
		id = "one_seat", name = "One Seat", icon = "🪑",
		text = "Only one Patron seat, but every Patron effect counts double.",
		titleId = "solo_star",
		setConfig = { patronSlotLimit = 1 }, rules = { patronPower = 2 },
	},
	{
		id = "glass_deck", name = "Glass Deck", icon = "🔮",
		text = "Cards you play may break and leave your deck for good.",
		titleId = "careful_hands",
		rules = { glassChance = 20 },
	},
	{
		id = "speed_run", name = "Speed Run", icon = "⏱️",
		text = "Win within 15 minutes for a bonus. Taking longer still counts as a clear.",
		titleId = "quick_draw",
		rules = { speedSeconds = 900 },
	},
	{
		id = "tight_wallet", name = "Tight Wallet", icon = "👛",
		text = "Round rewards and interest pay only half the Tips.",
		titleId = "coin_keeper",
		rules = { tipsPercent = 50 },
	},
}

function Challenges.getById(id)
	for _, def in ipairs(Challenges.Definitions) do
		if def.id == id then
			return def
		end
	end
	return nil
end

local function copyRules(rules)
	local out = {}
	for key, value in pairs(rules or {}) do
		if type(value) == "table" then
			local inner = {}
			for k, v in pairs(value) do inner[k] = v end
			out[key] = inner
		else
			out[key] = value
		end
	end
	return out
end

-- Sets a fresh run up for a twist, before its first round is dealt. Returns true on success.
function Challenges.configure(state, id)
	local def = Challenges.getById(id)
	if not def then
		return false
	end
	local config = state.config
	for key, delta in pairs(def.config or {}) do
		config[key] = (config[key] or 0) + delta
	end
	for key, value in pairs(def.setConfig or {}) do
		config[key] = value
	end
	config.handsPerRound = math.max(1, config.handsPerRound)
	config.discardsPerRound = math.max(0, config.discardsPerRound)
	config.patronSlotLimit = math.max(1, config.patronSlotLimit)
	local challenge = copyRules(def.rules)
	challenge.id = def.id
	challenge.name = def.name
	state.challenge = challenge
	return true
end

-- Records a won challenge run: remembers the clear and grants the title once. `seconds` = how long the run took
-- (only the Speed Run looks at it). Returns { first, title, bonusXp } or nil when the id is unknown.
function Challenges.recordClear(profile, id, seconds)
	local def = Challenges.getById(id)
	if not def then
		return nil
	end
	profile.challengesCleared = profile.challengesCleared or {}
	local first = not profile.challengesCleared[id]
	profile.challengesCleared[id] = true
	profile.rewardTitleIds = profile.rewardTitleIds or {}
	local titleNew = not profile.rewardTitleIds[def.titleId]
	profile.rewardTitleIds[def.titleId] = true
	local bonusXp = 0
	if def.rules and def.rules.speedSeconds and type(seconds) == "number" and seconds <= def.rules.speedSeconds then
		bonusXp = Challenges.SPEED_BONUS_XP
		TavernRank.addXp(profile, bonusXp)
	end
	return { first = first, title = titleNew and def.titleId or nil, bonusXp = bonusXp }
end

-- Cleans a saved set: only real challenge ids survive.
function Challenges.cleanSaved(raw)
	local out = {}
	if type(raw) == "table" then
		for id, flag in pairs(raw) do
			if flag == true and type(id) == "string" and Challenges.getById(id) then
				out[id] = true
			end
		end
	end
	return out
end

-- What the Run Setup list draws: every twist with whether it was cleared.
function Challenges.view(profile)
	local rows = {}
	for _, def in ipairs(Challenges.Definitions) do
		rows[#rows + 1] = { id = def.id, name = def.name, icon = def.icon, text = def.text, cleared = (profile.challengesCleared or {})[def.id] == true }
	end
	return rows
end

return Challenges
