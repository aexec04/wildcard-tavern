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
	  - `ownedThemeIds` -- every Theme ever bought with Tips. This was a
	    genuine, previously-unflagged gap: `RunState.new` used to always
	    reset `state.ownedThemes` back to just the free default, so buying a
	    Theme with Tips only lasted until your next "New Run..." -- you'd
	    have to re-buy it every single run. (Game-Pass-granted Themes were
	    never affected by this -- Server/init.server.lua already tracks real
	    Game Pass ownership outside any one run's state, same idea as this
	    file just applied to Tips purchases too.)
	  - `stats` -- a few small permanent numbers (runs started/won, best
	    Night reached) for the Collection screen to show alongside the
	    discovered-Patron/Theme grid. Deliberately minimal -- this is not a
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
	    from `stats`/discoveredPatronIds/ownedThemeIds every time) -- but
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

local PlayerProfile = {}

-- Bumped only if the SHAPE of a saved profile ever needs to change in a way
-- `migrate` can't already absorb (e.g. renaming a field). Not used for
-- anything yet -- present so a future migration has somewhere to branch on.
PlayerProfile.SCHEMA_VERSION = 1

-- What a player who has never been saved before starts with.
function PlayerProfile.new()
	return {
		version = PlayerProfile.SCHEMA_VERSION,
		discoveredPatronIds = {}, -- [patronId] = true
		ownedThemeIds = {}, -- [themeId] = true -- Tips-bought only; the free default theme is always owned regardless, RunState.new adds it unconditionally
		stats = {
			runsStarted = 0,
			runsWon = 0,
			bestNightReached = 0,
		},
		equippedTitleId = nil, -- ACHIEVEMENTS + TITLES (Phase 16): an Achievements.Definitions id, or nil for no title equipped
		hasSeenTutorial = false, -- TUTORIAL (Phase 16)
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

	if type(raw.ownedThemeIds) == "table" then
		for id, owned in pairs(raw.ownedThemeIds) do
			if type(id) == "string" and owned == true then
				profile.ownedThemeIds[id] = true
			end
		end
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
	-- (discoveredPatronIds/ownedThemeIds/stats) is already settled onto
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

	return profile
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

-- Same shape as recordPatronsFound, for Themes. Deliberately a SEPARATE
-- function (not a shared generic) even though the bodies are identical --
-- these track conceptually different things (permanent "have I found this"
-- vs "have I bought this"), and a future change to one's rules (e.g.
-- discovered Patrons someday needing a rarity weight) shouldn't have to
-- worry about accidentally affecting the other.
function PlayerProfile.recordThemesOwned(profile, themeIds)
	local changed = false
	for _, id in ipairs(themeIds) do
		if type(id) == "string" and not profile.ownedThemeIds[id] then
			profile.ownedThemeIds[id] = true
			changed = true
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
-- single state push (same pattern as recordPatronsFound/recordThemesOwned
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

return PlayerProfile
