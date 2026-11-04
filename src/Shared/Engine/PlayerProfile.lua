--[[
	PlayerProfile.lua
	PERSISTENT SAVE (Phase 10): the permanent, cross-run part of a player's
	progress -- everything that should survive "New Run...", a rejoin, or a
	server restart, as opposed to `RunState` (Shared/Engine/RunState.lua),
	which is deliberately scoped to a single run and thrown away when that
	run ends or restarts.

	What lives here, and why each one needed this file to exist at all:
	  - `discoveredPatronIds` -- every Patron id ever owned in ANY run. Before
	    this, Client/Collection.lua's "Collection" screen only ever showed
	    the CURRENT run's `ownedPatrons` (see that file's old title,
	    "Collection -- this run") -- so finding a rare Patron, then starting
	    a fresh run, made it look undiscovered again. Patrons themselves
	    still correctly reset every run (that's the roguelike loop, not a
	    bug) -- this just remembers that you'd found it before.
	  - `ownedSetIds` / `equippedSetId` -- Cosmetic Sets (CosmeticSets.lua):
	    Tips-bought set ids, and the equipped set (falls back to the default
	    if missing, unknown or locked). Old `ownedThemeIds`/`equippedTheme`
	    are ignored by `migrate`.
	  - `stats` -- a few small permanent numbers (runs started/won, best
	    Night reached) for the Collection screen to show alongside the
	    discovered-Patron grid. Deliberately minimal -- this is not a
	    full stats/leaderboard system, just enough to answer "have I ever
	    actually won a run, and how far did I get."
	  - `hasSeenTutorial` -- TUTORIAL (Phase 16): flips true the first time
	    this player dismisses (or skips) the first-time-player walkthrough
	    (Client/Tutorial.lua) -- lets the client auto-show it exactly once
	    ever, for a genuinely brand-new player, without it ever popping up
	    again on a later run/rejoin. Manually reopenable any time from the
	    menu regardless of this flag -- this only gates the AUTOMATIC
	    first-time popup.
	  - `equippedTitleId` -- ACHIEVEMENTS + TITLES (Phase 16): which of
	    Shared/Engine/Achievements.lua's titles this player has chosen to
	    show off, or nil for none equipped. This is the one piece of the
	    achievements feature that actually needs saving -- which
	    achievements are UNLOCKED is deliberately never stored (see
	    Achievements.lua's header for why that's safe to just recompute
	    from `stats`/discoveredPatronIds every time) -- but
	    which one you've chosen to WEAR is a real, unrecoverable player
	    choice, so it's the only new field this file needed to gain.

	Deliberately NOT covered by this file (a scope decision, not an
	oversight): an in-progress RUN itself. Closing the game mid-run still
	loses that run, exactly like before -- resuming a run from a checkpoint
	would mean persisting the entire live RunState (deck/hand/rng/etc), which
	is a much bigger, riskier undertaking than remembering what's been
	discovered. If that's ever wanted, it's a separate, deliberately-scoped
	future phase.

	Pure Lua, no Roblox APIs -- same reasoning as every other Shared/Engine
	module: testable with plain `lua5.3`, no Studio required. The actual
	DataStoreService calls (which DO need Roblox) live in
	Server/init.server.lua; this file only ever touches plain Lua tables.
]]

local Achievements = require(script.Parent.Achievements) -- ACHIEVEMENTS + TITLES, Phase 16
local CosmeticSets = require(script.Parent.CosmeticSets)
local JourneyMap = require(script.Parent.JourneyMap)

local PlayerProfile = {}

-- Bumped only if the SHAPE of a saved profile ever needs to change in a way
-- `migrate` can't already absorb (e.g. renaming a field). Not used for
-- anything yet -- present so a future migration has somewhere to branch on.
PlayerProfile.SCHEMA_VERSION = 1

-- Player settings (Settings panel + volume popup). Each entry is the
-- default plus the rule a saved/client-sent value must pass. Profiles
-- saved before settings existed have no `settings` table and get these
-- defaults; musicVolume 0.35 matches the old session-only starting volume.
PlayerProfile.SETTING_SPECS = {
	musicVolume = { default = 0.35, kind = "fraction" },
	sfxVolume = { default = 1, kind = "fraction" },
	muted = { default = false, kind = "boolean" },
	animSpeed = { default = "normal", kind = "choice", choices = { normal = true, fast = true } },
	reduceShake = { default = false, kind = "boolean" },
	colorblindSuits = { default = false, kind = "boolean" },
	confirmDiscard = { default = false, kind = "boolean" },
}

-- Animation pace divisors. The free "fast" speed is milder than the
-- Fast Forward Game Pass, which upgrades "fast" to the full speed-up.
PlayerProfile.FAST_PACE_DIVISOR = 1.35
PlayerProfile.FAST_FORWARD_PACE_DIVISOR = 1.8

function PlayerProfile.defaultSettings()
	local settings = {}
	for key, spec in pairs(PlayerProfile.SETTING_SPECS) do
		settings[key] = spec.default
	end
	return settings
end

-- Returns the cleaned value, or nil if `value` isn't valid for `key`.
local function cleanSetting(key, value)
	local spec = PlayerProfile.SETTING_SPECS[key]
	if not spec then
		return nil
	end
	if spec.kind == "fraction" then
		if type(value) ~= "number" or value ~= value then
			return nil
		end
		return math.max(0, math.min(1, value))
	elseif spec.kind == "boolean" then
		if type(value) ~= "boolean" then
			return nil
		end
		return value
	elseif spec.kind == "choice" then
		if type(value) ~= "string" or not spec.choices[value] then
			return nil
		end
		return value
	end
	return nil
end

-- COLLECTION: [id] = true sets copied as-is by migrate.
PlayerProfile.ID_SET_FIELDS = {
	"discoveredRecipeIds",
	"discoveredBossIds",
	"discoveredHousePassIds",
	"claimedMilestoneIds",
	"rewardTitleIds",
	"unlockedCardBackIds",
}

-- Which saved set each Collection tab's discoveries go into.
PlayerProfile.DISCOVERY_FIELDS = {
	patrons = "discoveredPatronIds",
	recipes = "discoveredRecipeIds",
	bosses = "discoveredBossIds",
	housePasses = "discoveredHousePassIds",
}

local function copyIdSet(rawSet, into)
	if type(rawSet) ~= "table" then
		return
	end
	for id, flag in pairs(rawSet) do
		if type(id) == "string" and flag == true then
			into[id] = true
		end
	end
end

-- What a player who has never been saved before starts with.
function PlayerProfile.new()
	return {
		version = PlayerProfile.SCHEMA_VERSION,
		discoveredPatronIds = {}, -- [patronId] = true
		-- COLLECTION: the other discovered sets (see CollectionBook.Tabs).
		discoveredRecipeIds = {}, -- [recipeId] = true
		discoveredBossIds = {}, -- [bossRoundId] = true
		discoveredHousePassIds = {}, -- [housePassId] = true
		claimedMilestoneIds = {}, -- [CollectionBook.Milestones id] = true
		rewardTitleIds = {}, -- [Achievements id] = true, titles granted by milestones
		unlockedCardBackIds = {}, -- [CardBacks id] = true
		ownedSetIds = {}, -- [CosmeticSets id] = true: Tips-bought or Journey-reward sets
		clearedNightIds = {}, -- [night number 1..8] = true, first clears (JourneyMap)
		equippedSetId = CosmeticSets.DefaultId,
		stats = {
			runsStarted = 0,
			runsWon = 0,
			bestNightReached = 0,
		},
		equippedTitleId = nil, -- ACHIEVEMENTS + TITLES (Phase 16): an Achievements.Definitions id, or nil for no title equipped
		hasSeenTutorial = false, -- TUTORIAL (Phase 16)
		hasSeenHighCardHint = false, -- see Onboarding.shouldShowHighCardHint
		freeContinueDateKey = nil, -- ONE MORE ROUND: SeededRng.dailyDateKey() of the day the free daily continue was last used, see hasFreeContinue
		settings = PlayerProfile.defaultSettings(), -- see SETTING_SPECS
	}
end

-- Turns whatever DataStore handed back into a SAFE profile to actually use.
-- This is the one function standing between a corrupt/foreign/missing
-- DataStore entry and a hard crash elsewhere -- deliberately paranoid:
-- every field is independently type-checked and falls back to
-- PlayerProfile.new()'s default rather than trusting the raw shape. Handles
-- three cases the same way: a brand-new player (raw == nil), a player saved
-- before this feature existed (raw is some other shape or missing fields),
-- and a normal valid profile.
function PlayerProfile.migrate(raw)
	local profile = PlayerProfile.new()
	if type(raw) ~= "table" then
		return profile
	end

	if type(raw.discoveredPatronIds) == "table" then
		for id, owned in pairs(raw.discoveredPatronIds) do
			if type(id) == "string" and owned == true then
				profile.discoveredPatronIds[id] = true
			end
		end
	end

	-- COLLECTION: older profiles only have discoveredPatronIds (copied
	-- above), so the other sets start empty and fill in from the next run.
	for _, field in ipairs(PlayerProfile.ID_SET_FIELDS) do
		copyIdSet(raw[field], profile[field])
	end

	copyIdSet(raw.ownedSetIds, profile.ownedSetIds)
	if type(raw.clearedNightIds) == "table" then
		for night, flag in pairs(raw.clearedNightIds) do
			if type(night) == "number" and flag == true and night >= 1 and night <= JourneyMap.NightCap
				and night == math.floor(night) then
				profile.clearedNightIds[night] = true
			end
		end
	end
	if type(raw.equippedSetId) == "string" and CosmeticSets.getById(raw.equippedSetId) then
		profile.equippedSetId = raw.equippedSetId
	end

	if type(raw.stats) == "table" then
		local rawStats = raw.stats
		if type(rawStats.runsStarted) == "number" then
			profile.stats.runsStarted = math.max(0, math.floor(rawStats.runsStarted))
		end
		if type(rawStats.runsWon) == "number" then
			profile.stats.runsWon = math.max(0, math.floor(rawStats.runsWon))
		end
		if type(rawStats.bestNightReached) == "number" then
			profile.stats.bestNightReached = math.max(0, math.floor(rawStats.bestNightReached))
		end
	end

	-- ACHIEVEMENTS + TITLES (Phase 16): validated AFTER everything above
	-- (discoveredPatronIds/stats) is already settled onto
	-- `profile`, since checking whether this title is still actually
	-- unlocked needs all of those. Deliberately just drops an
	-- invalid/no-longer-unlocked saved title rather than erroring --
	-- e.g. if a future balance change ever raised a requirement's
	-- threshold past what this player has, they'd simply need to
	-- re-equip once they qualify again, same as any other soft
	-- migration in this function.
	if type(raw.equippedTitleId) == "string" and Achievements.isUnlocked(profile, raw.equippedTitleId) then
		profile.equippedTitleId = raw.equippedTitleId
	end

	if raw.hasSeenTutorial == true then
		profile.hasSeenTutorial = true
	end

	if raw.hasSeenHighCardHint == true then
		profile.hasSeenHighCardHint = true
	end

	if type(raw.freeContinueDateKey) == "string" then
		profile.freeContinueDateKey = raw.freeContinueDateKey
	end

	-- Each setting is checked on its own; a missing or bad one keeps its default.
	if type(raw.settings) == "table" then
		for key in pairs(PlayerProfile.SETTING_SPECS) do
			local cleaned = cleanSetting(key, raw.settings[key])
			if cleaned ~= nil then
				profile.settings[key] = cleaned
			end
		end
	end

	JourneyMap.regrantRewards(profile)
	return profile
end

-- Safe to call straight off a remote handler. Returns (ok, message);
-- ok is false for an unknown key or a bad value, or when nothing changed
-- (so the caller can skip a save).
function PlayerProfile.setSetting(profile, key, value)
	if type(key) ~= "string" or not PlayerProfile.SETTING_SPECS[key] then
		return false, "Unknown setting"
	end
	local cleaned = cleanSetting(key, value)
	if cleaned == nil then
		return false, "Invalid value"
	end
	if profile.settings[key] == cleaned then
		return false, "Unchanged"
	end
	profile.settings[key] = cleaned
	return true, "Saved."
end

-- How much to divide animation durations by (1 = normal speed).
function PlayerProfile.animationPaceDivisor(animSpeed, hasFastForwardPass)
	if animSpeed ~= "fast" then
		return 1
	end
	if hasFastForwardPass then
		return PlayerProfile.FAST_FORWARD_PACE_DIVISOR
	end
	return PlayerProfile.FAST_PACE_DIVISOR
end

-- ONE MORE ROUND: every player gets one free continue per day (the UTC day
-- of SeededRng.dailyDateKey(), same as the Daily Challenge). The server
-- offers it before the paid Developer Product.
function PlayerProfile.hasFreeContinue(profile, dateKey)
	return type(dateKey) == "string" and profile.freeContinueDateKey ~= dateKey
end

-- Spends today's free continue. Returns false if it was already spent.
function PlayerProfile.useFreeContinue(profile, dateKey)
	if not PlayerProfile.hasFreeContinue(profile, dateKey) then
		return false
	end
	profile.freeContinueDateKey = dateKey
	return true
end

-- Merges a list of Patron ids (e.g. this run's state.ownedPatrons, mapped to
-- just their ids) into the permanent discovered set. Returns true if
-- anything NEW was added, so the caller (Server/init.server.lua) knows
-- whether this player's profile actually needs saving, instead of writing
-- to DataStore on every single state push regardless of whether anything
-- changed.
function PlayerProfile.recordPatronsFound(profile, patronIds)
	local changed = false
	for _, id in ipairs(patronIds) do
		if type(id) == "string" and not profile.discoveredPatronIds[id] then
			profile.discoveredPatronIds[id] = true
			changed = true
		end
	end
	return changed
end

-- COLLECTION: merges { [tabId] = {id, ...} } (CollectionBook.gatherSeen's
-- result) into the discovered sets. Unknown tab ids are ignored. Returns
-- true if anything new was added.
function PlayerProfile.recordDiscovered(profile, seen)
	local changed = false
	for tabId, field in pairs(PlayerProfile.DISCOVERY_FIELDS) do
		local set = profile[field]
		for _, id in ipairs(seen[tabId] or {}) do
			if type(id) == "string" and not set[id] then
				set[id] = true
				changed = true
			end
		end
	end
	return changed
end

-- Call once, right when a fresh run actually starts (Server/init.server.lua's
-- startNewSession). Always "changes" the profile (the counter always goes
-- up), so the caller doesn't need to check a return value here.
function PlayerProfile.recordRunStarted(profile)
	profile.stats.runsStarted = profile.stats.runsStarted + 1
end

-- Idempotent high-water mark -- safe to call with the current Night on every
-- single state push (same pattern as recordPatronsFound
-- above: returns whether it actually moved, so the caller can skip a save
-- when it didn't).
function PlayerProfile.recordNightReached(profile, night)
	if type(night) == "number" and night > profile.stats.bestNightReached then
		profile.stats.bestNightReached = night
		return true
	end
	return false
end

-- Call exactly once, the moment a run's wonRun flag flips from false to
-- true (Server/init.server.lua tracks that transition itself -- this
-- function just does the counter increment once told to).
function PlayerProfile.recordRunWon(profile)
	profile.stats.runsWon = profile.stats.runsWon + 1
end

-- ACHIEVEMENTS + TITLES (Phase 16): equips (or, passing nil, un-equips)
-- a Title -- re-validates against Achievements.isUnlocked every call
-- (never trusts a client-supplied id blindly), so this is safe to call
-- directly off a remote handler with zero other server-side checks.
function PlayerProfile.equipTitle(profile, achievementId)
	if achievementId == nil then
		profile.equippedTitleId = nil
		return true, "Title cleared."
	end
	if type(achievementId) ~= "string" then
		return false, "Invalid title"
	end
	if not Achievements.isUnlocked(profile, achievementId) then
		return false, "Title not unlocked"
	end
	profile.equippedTitleId = achievementId
	return true, "Title equipped."
end

-- TUTORIAL (Phase 16): idempotent -- safe to call even if already true
-- (Server/init.server.lua's handler doesn't bother checking first).
function PlayerProfile.markTutorialSeen(profile)
	profile.hasSeenTutorial = true
end

function PlayerProfile.markHighCardHintSeen(profile)
	profile.hasSeenHighCardHint = true
end

return PlayerProfile
