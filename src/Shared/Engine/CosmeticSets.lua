--[[
	CosmeticSets.lua
	Purely cosmetic "sets": a card back plus a backdrop variant (the same
	tavern in a different mood). No gameplay effect. Replaces the old
	Themes (color palettes); the UI now uses one fixed palette.

	Each set has `unlock`, one of:
	  { kind = "default" }                    always owned
	  { kind = "tips", price = N }            bought with Tips (kept in profile.ownedSetIds)
	  { kind = "journey", runsWon = N }       won N runs (profile.stats.runsWon)
	  { kind = "achievement", id = "..." }    an Achievements id is unlocked
	  { kind = "gamepass", passId = "..." }   a GamePasses id is owned

	`backdropImage` is an rbxassetid; "rbxassetid://0" is a placeholder and
	the client falls back to the default backdrop (see claude/ART_TODO.md).
	The equipped set is profile.equippedSetId and persists across runs.
]]

local Achievements = require(script.Parent.Achievements)

local CosmeticSets = {}

CosmeticSets.DefaultId = "classic_tavern"

CosmeticSets.Definitions = {
	{
		id = "classic_tavern",
		name = "Classic Tavern",
		icon = "🏠",
		description = "The everyday tavern. Always yours.",
		cardBackId = "classic",
		backdropImage = nil, -- nil = the default backdrop in ArtAssets
		unlock = { kind = "default" },
	},
	{
		id = "winter_evening",
		name = "Winter Evening",
		icon = "❄",
		description = "Snow on the windows and a warm fire inside.",
		cardBackId = "winter_frost",
		backdropImage = "rbxassetid://0", -- TODO art: tavern in winter
		unlock = { kind = "tips", price = 12 },
	},
	{
		id = "festival_night",
		name = "Festival Night",
		icon = "🎊",
		description = "Lanterns and ribbons for a night of celebration.",
		cardBackId = "festival_ribbon",
		backdropImage = "rbxassetid://0", -- TODO art: tavern festival
		unlock = { kind = "journey", runsWon = 1 },
	},
	{
		id = "closing_time",
		name = "Closing Time",
		icon = "🏮",
		description = "Dim lamps and a quiet room as the night winds down.",
		cardBackId = "closing_lantern",
		backdropImage = "rbxassetid://0", -- TODO art: tavern at closing time
		unlock = { kind = "achievement", id = "regular" },
	},
	{
		id = "golden_gala",
		name = "Golden Gala",
		icon = "✨",
		description = "The tavern dressed in gold for a grand evening.",
		cardBackId = "gilded_ledger",
		backdropImage = "rbxassetid://0", -- TODO art: tavern gala
		unlock = { kind = "gamepass", passId = "set_golden_gala" },
	},
}

function CosmeticSets.getById(id)
	for _, set in ipairs(CosmeticSets.Definitions) do
		if set.id == id then
			return set
		end
	end
	return nil
end

-- ownedPassIds: optional set { [passId] = true } of Game Passes the player owns.
function CosmeticSets.isUnlocked(profile, setId, ownedPassIds)
	local set = CosmeticSets.getById(setId)
	if not set then
		return false
	end
	local unlock = set.unlock
	-- A set granted as a reward (Journey) sits in ownedSetIds, whatever
	-- its normal unlock source is.
	if profile.ownedSetIds[setId] then
		return true
	end
	if unlock.kind == "default" then
		return true
	elseif unlock.kind == "tips" then
		return profile.ownedSetIds[setId] == true
	elseif unlock.kind == "journey" then
		return profile.stats.runsWon >= unlock.runsWon
	elseif unlock.kind == "achievement" then
		return Achievements.isUnlocked(profile, unlock.id)
	elseif unlock.kind == "gamepass" then
		return ownedPassIds ~= nil and ownedPassIds[unlock.passId] == true
	end
	return false
end

-- Short player-facing text for how to get a set.
function CosmeticSets.unlockText(set)
	local unlock = set.unlock
	if unlock.kind == "default" then
		return "Always unlocked"
	elseif unlock.kind == "tips" then
		return string.format("Buy for %d Tips", math.floor(unlock.price))
	elseif unlock.kind == "journey" then
		return string.format("Win %d run%s", math.floor(unlock.runsWon), unlock.runsWon == 1 and "" or "s")
	elseif unlock.kind == "achievement" then
		local a = Achievements.getById(unlock.id)
		return "Achievement: " .. (a and a.name or "?")
	elseif unlock.kind == "gamepass" then
		return "Game Pass"
	end
	return ""
end

-- The set to actually show: the equipped one if it still exists and is
-- unlocked, otherwise the default.
function CosmeticSets.effectiveId(profile, ownedPassIds)
	local id = profile.equippedSetId
	if id and CosmeticSets.isUnlocked(profile, id, ownedPassIds) then
		return id
	end
	return CosmeticSets.DefaultId
end

-- Buy a Tips set. `state` is the live RunState (Tips are spent from it).
function CosmeticSets.buy(profile, state, setId)
	local set = CosmeticSets.getById(setId)
	if not set then
		return false, "Unknown set"
	end
	if set.unlock.kind ~= "tips" then
		return false, "Not for sale"
	end
	if profile.ownedSetIds[setId] then
		return false, "Already owned"
	end
	if state.tips < set.unlock.price then
		return false, "Not enough tips"
	end
	state.tips = state.tips - set.unlock.price
	profile.ownedSetIds[setId] = true
	return true, set.name .. " unlocked."
end

function CosmeticSets.equip(profile, setId, ownedPassIds)
	if not CosmeticSets.isUnlocked(profile, setId, ownedPassIds) then
		return false, "Set not unlocked"
	end
	profile.equippedSetId = setId
	return true, "Equipped."
end

return CosmeticSets
