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
	  { kind = "biome", region = "..." }      granted into ownedSetIds by BiomeRewards (first clear of that biome)

	`backdropImage` is an rbxassetid; "rbxassetid://0" is a placeholder and
	the client falls back to the default backdrop (see claude/ART_TODO.md).
	The equipped set is profile.equippedSetId and persists across runs.

	`backdropStyle` (optional) is a stack of effects drawn over the base
	backdrop with UI elements only (Client/BackdropStyles.lua), so a set looks
	different without new art. Colors are {r, g, b} 0-255.
	  tint     = {r,g,b}                        multiplies the base image (ImageColor3)
	  overlay  = { color = {r,g,b}, transparency = 0-1 }   flat tinted layer
	  vignette = { color = {r,g,b}, strength = 0-1 }       darkened/colored edges
	  layers   = { { kind = "snow" | "sparks" | "dust" | "bunting", count = N, ... } }
	Particle layers are capped at BackdropLimits.maxParticles each.
]]

local Achievements = require(script.Parent.Achievements)
local CardBacks = require(script.Parent.CardBacks)
local BackgroundArt = require(script.Parent.BackgroundArt)

local CosmeticSets = {}

CosmeticSets.BackdropLimits = {
	maxParticles = 30,
	layerKinds = { snow = true, sparks = true, dust = true, bunting = true },
}

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
		name = "Frosted Garden",
		icon = "❄",
		description = "Frost on the garden path and lanterns glowing in the snow.",
		cardBackId = "winter_frost",
		backdropImage = BackgroundArt.backdrop_winter_evening or "rbxassetid://0",
		backdropStyle = {
			tint = { 190, 210, 245 },
			overlay = { color = { 60, 100, 170 }, transparency = 0.86 },
			vignette = { color = { 200, 228, 255 }, strength = 0.5 },
			layers = { { kind = "snow", count = 22, speed = 0.6 } },
		},
		unlock = { kind = "tips", price = 12 },
	},
	{
		id = "festival_night",
		name = "Mountain Festival",
		icon = "🎊",
		description = "Lanterns and ribbons for a night of celebration.",
		cardBackId = "festival_ribbon",
		backdropImage = BackgroundArt.backdrop_festival_night or "rbxassetid://0",
		backdropStyle = {
			tint = { 255, 235, 205 },
			overlay = { color = { 255, 170, 80 }, transparency = 0.88 },
			vignette = { color = { 90, 30, 20 }, strength = 0.25 },
			layers = {
				{ kind = "bunting", count = 14, colors = { { 230, 80, 90 }, { 250, 200, 70 }, { 90, 170, 230 }, { 120, 200, 120 } } },
				{ kind = "sparks", count = 14, speed = 0.8 },
			},
		},
		unlock = { kind = "journey", runsWon = 1 },
	},
	{
		id = "closing_time",
		name = "Closing Time",
		icon = "🏮",
		description = "Dim lamps and a quiet room as the night winds down.",
		cardBackId = "closing_lantern",
		backdropImage = BackgroundArt.backdrop_closing_time or "rbxassetid://0",
		backdropStyle = {
			tint = { 160, 130, 105 },
			overlay = { color = { 50, 25, 10 }, transparency = 0.8 },
			vignette = { color = { 8, 4, 2 }, strength = 0.85 },
			layers = { { kind = "dust", count = 8, speed = 0.4 } },
		},
		unlock = { kind = "achievement", id = "regular" },
	},
	{
		id = "golden_gala",
		name = "Golden Gala",
		icon = "✨",
		description = "The tavern dressed in gold for a grand evening.",
		cardBackId = "gilded_ledger",
		backdropImage = BackgroundArt.backdrop_golden_gala or "rbxassetid://0",
		unlock = { kind = "gamepass", passId = "set_golden_gala" },
	},
	{
		id = "meadow_picnic",
		name = "Meadow Picnic",
		icon = "🧺",
		description = "A Map reward for finishing the Wildflower Meadow road for the first time.",
		cardBackId = "kitchen_checks",
		backdropImage = "rbxassetid://0",
		backdropStyle = {
			tint = { 236, 240, 205 },
			overlay = { color = { 190, 200, 142 }, transparency = 0.88 },
			vignette = { color = { 60, 80, 30 }, strength = 0.3 },
			layers = { { kind = "dust", count = 8, speed = 0.4 } },
		},
		unlock = { kind = "biome", region = "meadow" },
	},
	{
		id = "riverside_evening",
		name = "Riverside Evening",
		icon = "🌉",
		description = "A Map reward for finishing the Willow River road for the first time.",
		cardBackId = "winter_frost",
		backdropImage = "rbxassetid://0",
		backdropStyle = {
			tint = { 210, 232, 228 },
			overlay = { color = { 168, 196, 176 }, transparency = 0.88 },
			vignette = { color = { 20, 50, 60 }, strength = 0.35 },
			layers = { { kind = "dust", count = 6, speed = 0.3 } },
		},
		unlock = { kind = "biome", region = "river" },
	},
	{
		id = "summit_camp",
		name = "Summit Camp",
		icon = "⛺",
		description = "A Map reward for finishing the Mountain Peaks road for the first time.",
		cardBackId = "hall_banner",
		backdropImage = "rbxassetid://0",
		backdropStyle = {
			tint = { 225, 228, 220 },
			overlay = { color = { 120, 130, 140 }, transparency = 0.88 },
			vignette = { color = { 30, 36, 48 }, strength = 0.4 },
			layers = { { kind = "snow", count = 10, speed = 0.4 } },
		},
		unlock = { kind = "biome", region = "peaks" },
	},
	{
		id = "dune_market",
		name = "Dune Market",
		icon = "🏜",
		description = "A Map reward for finishing the Golden Dunes road for the first time.",
		cardBackId = "dune_gold",
		backdropImage = "rbxassetid://0",
		backdropStyle = {
			tint = { 255, 236, 200 },
			overlay = { color = { 232, 190, 110 }, transparency = 0.88 },
			vignette = { color = { 90, 50, 10 }, strength = 0.3 },
			layers = { { kind = "dust", count = 14, speed = 0.5 } },
		},
		unlock = { kind = "biome", region = "desert" },
	},
	{
		id = "marsh_lanterns",
		name = "Marsh Lanterns",
		icon = "🏮",
		description = "A Map reward for finishing the Misty Marsh road for the first time.",
		cardBackId = "lilypad_green",
		backdropImage = "rbxassetid://0",
		backdropStyle = {
			tint = { 200, 225, 195 },
			overlay = { color = { 90, 130, 90 }, transparency = 0.87 },
			vignette = { color = { 12, 30, 20 }, strength = 0.5 },
			layers = { { kind = "sparks", count = 10, speed = 0.4 } },
		},
		unlock = { kind = "biome", region = "swamp" },
	},
	{
		id = "snowy_hearth",
		name = "Snowy Hearth",
		icon = "🔥",
		description = "A Map reward for finishing the Frosty Hills road for the first time.",
		cardBackId = "frost_walker",
		backdropImage = "rbxassetid://0",
		backdropStyle = {
			tint = { 215, 230, 250 },
			overlay = { color = { 70, 110, 180 }, transparency = 0.86 },
			vignette = { color = { 200, 228, 255 }, strength = 0.45 },
			layers = { { kind = "snow", count = 24, speed = 0.6 } },
		},
		unlock = { kind = "biome", region = "snow" },
	},
	{
		id = "harbor_lights",
		name = "Harbor Lights",
		icon = "⚓",
		description = "A Map reward for finishing the Lantern Coast road for the first time.",
		cardBackId = "shell_pearl",
		backdropImage = "rbxassetid://0",
		backdropStyle = {
			tint = { 205, 228, 235 },
			overlay = { color = { 120, 170, 190 }, transparency = 0.88 },
			vignette = { color = { 16, 40, 56 }, strength = 0.4 },
			layers = { { kind = "sparks", count = 8, speed = 0.5 } },
		},
		unlock = { kind = "biome", region = "coast" },
	},
	{
		id = "tavern_feast",
		name = "Tavern Feast",
		icon = "🍲",
		description = "A Map reward for finishing the Tavern road for the first time.",
		cardBackId = "gala",
		backdropImage = "rbxassetid://0",
		backdropStyle = {
			tint = { 255, 232, 196 },
			overlay = { color = { 255, 170, 80 }, transparency = 0.88 },
			vignette = { color = { 70, 30, 10 }, strength = 0.3 },
			layers = { { kind = "sparks", count = 12, speed = 0.7 } },
		},
		unlock = { kind = "biome", region = "tavern" },
	},
}

local function isRgb(t)
	if type(t) ~= "table" or #t ~= 3 then
		return false
	end
	for i = 1, 3 do
		if type(t[i]) ~= "number" or t[i] < 0 or t[i] > 255 then
			return false
		end
	end
	return true
end

-- Returns (ok, reason). A nil style is valid (no effects).
function CosmeticSets.validateStyle(style)
	if style == nil then
		return true
	end
	if type(style) ~= "table" then
		return false, "style is not a table"
	end
	if style.tint ~= nil and not isRgb(style.tint) then
		return false, "bad tint"
	end
	if style.overlay ~= nil then
		local o = style.overlay
		if type(o) ~= "table" or not isRgb(o.color) or type(o.transparency) ~= "number" or o.transparency < 0 or o.transparency > 1 then
			return false, "bad overlay"
		end
	end
	if style.vignette ~= nil then
		local v = style.vignette
		if type(v) ~= "table" or not isRgb(v.color) or type(v.strength) ~= "number" or v.strength < 0 or v.strength > 1 then
			return false, "bad vignette"
		end
	end
	for _, layer in ipairs(style.layers or {}) do
		if not CosmeticSets.BackdropLimits.layerKinds[layer.kind] then
			return false, "unknown layer " .. tostring(layer.kind)
		end
		if type(layer.count) ~= "number" or layer.count < 1 or layer.count > CosmeticSets.BackdropLimits.maxParticles then
			return false, "layer count out of range"
		end
		for _, c in ipairs(layer.colors or {}) do
			if not isRgb(c) then
				return false, "bad layer color"
			end
		end
	end
	return true
end

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
	elseif unlock.kind == "biome" then
		return "Reach the end of the " .. tostring(unlock.region) .. " road"
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

-- ===== Card backs =====
-- A card back can be equipped on its own. profile.equippedCardBackId is
-- the player's pick; nil means "use whatever back the equipped set has".
-- A back is unlocked when it is the default, was earned directly
-- (profile.unlockedCardBackIds: Collection milestones, Journey rewards),
-- or belongs to a set the player has unlocked.

function CosmeticSets.isCardBackUnlocked(profile, backId, ownedPassIds)
	if not CardBacks.getById(backId) then
		return false
	end
	if backId == CardBacks.DefaultId or profile.unlockedCardBackIds[backId] then
		return true
	end
	for _, set in ipairs(CosmeticSets.Definitions) do
		if set.cardBackId == backId and CosmeticSets.isUnlocked(profile, set.id, ownedPassIds) then
			return true
		end
	end
	return false
end

-- The back actually shown: the player's pick if still unlocked, otherwise
-- the equipped set's back.
function CosmeticSets.effectiveCardBackId(profile, ownedPassIds)
	local picked = profile.equippedCardBackId
	if picked and CosmeticSets.isCardBackUnlocked(profile, picked, ownedPassIds) then
		return picked
	end
	local set = CosmeticSets.getById(CosmeticSets.effectiveId(profile, ownedPassIds))
	return set and set.cardBackId or CardBacks.DefaultId
end

-- backId nil clears the pick (match the equipped set again).
function CosmeticSets.equipCardBack(profile, backId, ownedPassIds)
	if backId == nil then
		profile.equippedCardBackId = nil
		return true, "Card back follows your set."
	end
	if not CosmeticSets.isCardBackUnlocked(profile, backId, ownedPassIds) then
		return false, "Card back not unlocked"
	end
	profile.equippedCardBackId = backId
	return true, "Equipped."
end

return CosmeticSets
