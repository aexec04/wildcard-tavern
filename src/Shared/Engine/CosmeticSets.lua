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

	Whole-table theme (no image assets needed): besides the backdrop, an equipped set themes
	  face   = { paper = {r,g,b}, border = {r,g,b}, pip = {r,g,b}, foil = true|nil }   the card faces
	  accent = {r,g,b}                                                            the side panel, hand tray and table edge
	Sets without explicit values get them derived from their backdropStyle (themeOf), so every set,
	including the biome sets, themes the card faces and panels; the default set stays neutral (today's
	look). Use CosmeticSets.themeOf(set) -> { backdropStyle, face, accent, neutral, skin }.

	Skin slots (Client/SetSkin.lua applies them): CosmeticSets.skinOf(set) -> { images, colors, neutral } where
	images = { faceFrame, facePaper, faceCourt, panelFrame, buttonPlate, tabPlate } are optional image ids read from
	Engine/SetSkinArt.lua (keys "<setId>_face_frame", "<setId>_face_paper", ...; nil while the art is missing) and
	colors = { paper, border, pip, panel, button, tab } are present for every non-default set (derived from the
	set's face and accent), so each set already looks different without art. The default set has colors = nil.
]]

local Achievements = require(script.Parent.Achievements)
local CardBacks = require(script.Parent.CardBacks)
local BackgroundArt = require(script.Parent.BackgroundArt)
local SetBackdropArt = require(script.Parent.SetBackdropArt) -- biome sets: generated map, empty until recorded
local SetPanelArt = require(script.Parent.SetPanelArt) -- slice-friendly panel borders, one per set (generated)
local SetPanelFit = require(script.Parent.SetPanelFit) -- which of them pass the slice fit test (generated)
local SetSkinArt = require(script.Parent.SetSkinArt) -- per-set UI skin images: generated map, empty until recorded
local SetSceneryArt = require(script.Parent.SetSceneryArt) -- per-set gameplay scenery: generated map, empty until recorded

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
		cardBackId = "back_winter_evening",
		-- readable card: the painted ivory face stands alone (classicFace, same big indices as Golden Gala), deep navy ink at 7:1 on ivory
		face = { paper = { 248, 246, 236 }, border = { 150, 195, 235 }, pip = { 18, 34, 84 } },
		classicFace = true,
		minIndexContrast = 7,
		accent = { 140, 185, 230 },
		backdropImage = BackgroundArt.backdrop_winter_evening or "rbxassetid://0",
		backdropStyle = {
			tint = { 190, 210, 245 },
			overlay = { color = { 60, 100, 170 }, transparency = 0.86 },
			vignette = { color = { 200, 228, 255 }, strength = 0.5 },
			layers = { { kind = "snow", count = 22, speed = 0.6 } },
		},
		-- cool icy blue felt, a pale frosted wood lip
		tableTint = { felt = { 110, 150, 215 }, wood = { 200, 220, 245 } },
		unlock = { kind = "tips", price = 12 },
	},
	{
		id = "festival_night",
		name = "Mountain Festival",
		icon = "🎊",
		description = "Lanterns and ribbons for a night of celebration.",
		cardBackId = "back_festival_night",
		-- same readable card as Frosted Garden: ivory face alone, warm cream paper, deep brown ink at 7:1
		face = { paper = { 252, 242, 218 }, border = { 240, 160, 80 }, pip = { 96, 40, 20 }, foil = true },
		classicFace = true,
		minIndexContrast = 7,
		accent = { 240, 170, 90 },
		-- the painted play table is multiplied by `felt` (a deep midnight pine green leaning blue) and its rail lip by `wood` (a warm festival tone)
		tableTint = { felt = { 70, 120, 120 }, wood = { 255, 205, 160 } },
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
		cardBackId = "back_closing_time",
		-- same readable card: ivory face alone, a lamp-lit cream paper, dark umber ink at 7:1
		face = { paper = { 240, 228, 204 }, border = { 150, 105, 60 }, pip = { 60, 40, 28 } },
		classicFace = true,
		minIndexContrast = 7,
		accent = { 150, 105, 60 },
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
		cardBackId = "back_golden_gala",
		backdropImage = BackgroundArt.backdrop_golden_gala or "rbxassetid://0",
		-- No painted backdrop yet, so the style carries the look: a warm gold wash, gold drapes along the
		-- top, a dark gilded vignette and drifting gold sparks. Gold-edged ivory faces with gold pips.
		backdropStyle = {
			tint = { 255, 236, 190 },
			overlay = { color = { 240, 190, 70 }, transparency = 0.78 },
			vignette = { color = { 90, 60, 10 }, strength = 0.55 },
			layers = {
				{ kind = "bunting", count = 16, colors = { { 235, 190, 80 }, { 190, 140, 40 }, { 250, 232, 170 } } },
				{ kind = "sparks", count = 16, speed = 0.5 },
			},
		},
		-- A premium classic card: the painted ivory face stands alone (classicFace), the gold shows as a thin edge and foil.
		-- Ink is near black and deep red, at least 7:1 on the ivory paper.
		face = { paper = { 252, 240, 208 }, border = { 222, 182, 104 }, pip = { 96, 66, 8 }, foil = true },
		classicFace = true,
		minIndexContrast = 7,
		accent = { 222, 182, 104 },
		unlock = { kind = "gamepass", passId = "set_golden_gala" },
	},
	{
		id = "meadow_picnic",
		name = "Meadow Picnic",
		icon = "🧺",
		description = "A Map reward for finishing the Wildflower Meadow road for the first time.",
		cardBackId = "back_meadow_picnic",
		backdropImage = SetBackdropArt.meadow_picnic or "rbxassetid://0",
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
		cardBackId = "back_riverside_evening",
		backdropImage = SetBackdropArt.riverside_evening or "rbxassetid://0",
		backdropStyle = {
			tint = { 210, 232, 228 },
			overlay = { color = { 168, 196, 176 }, transparency = 0.88 },
			vignette = { color = { 20, 50, 60 }, strength = 0.35 },
			layers = { { kind = "dust", count = 6, speed = 0.3 } },
		},
		face = { paper = { 224, 240, 230 }, border = { 181, 205, 189 }, pip = { 24, 39, 43 } }, -- seafoam paper
		unlock = { kind = "biome", region = "river" },
	},
	{
		id = "summit_camp",
		name = "Summit Camp",
		icon = "⛺",
		description = "A Map reward for finishing the Mountain Peaks road for the first time.",
		cardBackId = "back_summit_camp",
		backdropImage = SetBackdropArt.summit_camp or "rbxassetid://0",
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
		cardBackId = "back_dune_market",
		backdropImage = SetBackdropArt.dune_market or "rbxassetid://0",
		backdropStyle = {
			tint = { 255, 236, 200 },
			overlay = { color = { 232, 190, 110 }, transparency = 0.88 },
			vignette = { color = { 90, 50, 10 }, strength = 0.3 },
			layers = { { kind = "dust", count = 14, speed = 0.5 } },
		},
		face = { paper = { 240, 212, 164 }, border = { 235, 200, 129 }, pip = { 66, 39, 13 } }, -- sandy paper, distinct from Golden Gala
		unlock = { kind = "biome", region = "desert" },
	},
	{
		id = "marsh_lanterns",
		name = "Marsh Lanterns",
		icon = "🏮",
		description = "A Map reward for finishing the Misty Marsh road for the first time.",
		cardBackId = "back_marsh_lanterns",
		backdropImage = SetBackdropArt.marsh_lanterns or "rbxassetid://0",
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
		cardBackId = "back_snowy_hearth",
		backdropImage = SetBackdropArt.snowy_hearth or "rbxassetid://0",
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
		cardBackId = "back_harbor_lights",
		backdropImage = SetBackdropArt.harbor_lights or "rbxassetid://0",
		backdropStyle = {
			tint = { 205, 228, 235 },
			overlay = { color = { 120, 170, 190 }, transparency = 0.88 },
			vignette = { color = { 16, 40, 56 }, strength = 0.4 },
			layers = { { kind = "sparks", count = 8, speed = 0.5 } },
		},
		face = { paper = { 220, 234, 248 }, border = { 140, 183, 200 }, pip = { 22, 33, 41 } }, -- pale harbor blue paper
		darkFace = true, -- the painted face art is dark navy: the index wears light ink on a dark plate (see indexStyle)
		unlock = { kind = "biome", region = "coast" },
	},
	{
		id = "tavern_feast",
		name = "Tavern Feast",
		icon = "🍲",
		description = "A Map reward for finishing the Tavern road for the first time.",
		cardBackId = "back_tavern_feast",
		backdropImage = SetBackdropArt.tavern_feast or "rbxassetid://0",
		backdropStyle = {
			tint = { 255, 232, 196 },
			overlay = { color = { 255, 170, 80 }, transparency = 0.88 },
			vignette = { color = { 70, 30, 10 }, strength = 0.3 },
			layers = { { kind = "sparks", count = 12, speed = 0.7 } },
		},
		face = { paper = { 255, 224, 186 }, border = { 255, 183, 106 }, pip = { 54, 27, 13 } }, -- warm feast paper
		unlock = { kind = "biome", region = "tavern" },
	},
	-- SEASON PREMIUM SETS (Engine/SeasonTrack.lua tier 15 of the premium row): granted into ownedSetIds with the pass.
	{
		id = "harvest_table",
		name = "Harvest Table",
		icon = "🌕",
		description = "A Tavern Season premium reward: a table dressed for the Harvest Moon.",
		cardBackId = "back_harvest_table",
		face = { paper = { 248, 228, 192 }, border = { 214, 140, 60 }, pip = { 150, 80, 30 } },
		accent = { 220, 150, 70 },
		backdropImage = SetBackdropArt.harvest_table or "rbxassetid://0",
		backdropStyle = {
			tint = { 255, 225, 180 },
			overlay = { color = { 220, 140, 50 }, transparency = 0.88 },
			vignette = { color = { 60, 28, 8 }, strength = 0.35 },
			layers = { { kind = "sparks", count = 12, speed = 0.5 }, { kind = "dust", count = 8, speed = 0.4 } },
		},
		unlock = { kind = "season", seasonId = "harvest_moon" },
	},
	{
		id = "winter_table",
		name = "Winter Welcome Table",
		icon = "🧣",
		description = "A Tavern Season premium reward: a cozy table for the snowy months.",
		cardBackId = "back_winter_table",
		face = { paper = { 214, 232, 250 }, border = { 120, 160, 215 }, pip = { 50, 80, 140 } },
		accent = { 120, 165, 220 },
		backdropImage = SetBackdropArt.winter_table or "rbxassetid://0",
		backdropStyle = {
			tint = { 205, 220, 250 },
			overlay = { color = { 70, 100, 170 }, transparency = 0.86 },
			vignette = { color = { 190, 215, 250 }, strength = 0.45 },
			layers = { { kind = "snow", count = 20, speed = 0.5 } },
		},
		unlock = { kind = "season", seasonId = "winter_welcome" },
	},
}

-- Every set gets a `scenery` slot (SetSceneryArt[id], "rbxassetid://0" while missing). In gameplay it wins
-- over backdropImage, which wins over the biome painting (Engine/TableStyle).
for _, set in ipairs(CosmeticSets.Definitions) do
	set.scenery = SetSceneryArt[set.id] or "rbxassetid://0"
end

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

-- Optional painted-table tint of a set (or set id): { felt = {r,g,b}, wood = {r,g,b} } multipliers, nil keeps the table exactly as painted.
function CosmeticSets.tableTintOf(setOrId)
	local set = type(setOrId) == "string" and CosmeticSets.getById(setOrId) or setOrId
	if type(set) ~= "table" or set.id == CosmeticSets.DefaultId then return nil end
	local t = set.tableTint
	if type(t) == "table" and type(t.felt) == "table" and type(t.wood) == "table" then return t end
	-- no explicit tint: derive one from the set's accent so every non-default set changes the felt (calm, never below 90)
	local a = CosmeticSets.accentOf(set)
	if type(a) ~= "table" then return nil end
	local function lift(c, k) return math.max(90, math.floor(255 + (c - 255) * k + 0.5)) end
	return {
		felt = { lift(a[1], 0.62), lift(a[2], 0.62), lift(a[3], 0.62) },
		wood = { lift(a[1], 0.35), lift(a[2], 0.35), lift(a[3], 0.35) },
	}
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

CosmeticSets.RegionNames = {
	meadow = "the Wildflower Meadow", river = "the Willow River", peaks = "the Mountain Peaks", desert = "the Golden Dunes",
	swamp = "the Misty Marsh", snow = "the Frosty Hills", coast = "the Lantern Coast", tavern = "the Tavern Gate",
}

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
		return "Get it in the Shop with a Game Pass."
	elseif unlock.kind == "biome" then
		return "Clear " .. (CosmeticSets.RegionNames[unlock.region] or "the road") .. " on the Map."
	elseif unlock.kind == "season" then
		local name = tostring(unlock.seasonId):gsub("_", " "):gsub("(%a)(%a*)", function(a, b) return a:upper() .. b end)
		return "Season reward: " .. name .. "."
	end
	return "Keep playing to unlock."
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

-- ===== whole-table theme =====

CosmeticSets.NEUTRAL_FACE = { neutral = true } -- the default set keeps today's cream faces and gold rims

-- A themed set is never drawn faintly: at least this much overlay and vignette, so it reads at a glance.
CosmeticSets.MIN_OVERLAY_STRENGTH = 0.2 -- overlay transparency is capped at 1 - this
CosmeticSets.MIN_VIGNETTE = 0.35

local function mix(a, b, t)
	return {
		math.floor(a[1] + (b[1] - a[1]) * t + 0.5),
		math.floor(a[2] + (b[2] - a[2]) * t + 0.5),
		math.floor(a[3] + (b[3] - a[3]) * t + 0.5),
	}
end

-- The backdrop style actually drawn for a set (nil for the plain default).
function CosmeticSets.backdropStyleOf(set)
	local style = set and set.backdropStyle
	if not style then
		return nil
	end
	local out = {}
	for k, v in pairs(style) do out[k] = v end
	if out.overlay then
		out.overlay = { color = out.overlay.color, transparency = math.min(out.overlay.transparency, 1 - CosmeticSets.MIN_OVERLAY_STRENGTH) }
	end
	if out.vignette then
		out.vignette = { color = out.vignette.color, strength = math.max(out.vignette.strength, CosmeticSets.MIN_VIGNETTE) }
	end
	return out
end

-- Card face treatment: explicit `face`, else derived from the backdrop style (tint -> paper,
-- overlay colour -> border, vignette colour darkened -> pip), else neutral.
function CosmeticSets.faceStyleOf(set)
	if not set then return CosmeticSets.NEUTRAL_FACE end
	if set.face then return set.face end
	local style = set.backdropStyle
	if not style or set.id == CosmeticSets.DefaultId then return CosmeticSets.NEUTRAL_FACE end
	local base = { 250, 240, 215 }
	local border = style.overlay and style.overlay.color or style.tint or { 200, 170, 110 }
	local pipSource = style.vignette and style.vignette.color or border
	return {
		paper = mix(base, style.tint or base, 0.5),
		border = mix(border, { 255, 255, 255 }, 0.15),
		pip = mix(pipSource, { 30, 22, 18 }, 0.4),
	}
end

-- Accent for the side panel, hand tray and table edge: explicit `accent`, else the face border.
function CosmeticSets.accentOf(set)
	if not set then return nil end
	if set.accent then return set.accent end
	return CosmeticSets.faceStyleOf(set).border
end

-- The colour of a claim glow or current-tier ring (Season tiles, Daily Rewards today): the set accent, nil for classic or an unknown set so
-- those keep their gold. A stroke only; text colours never come from here.
function CosmeticSets.ringColorOf(setId)
	if not setId or setId == CosmeticSets.DefaultId then return nil end
	local set = CosmeticSets.getById(setId)
	local a = set and CosmeticSets.accentOf(set)
	if type(a) ~= "table" or #a < 3 then return nil end
	return { a[1], a[2], a[3] }
end

-- Colours for the draw pile's frame and plate: the equipped back's pile style, nudged toward the equipped
-- set's accent (a non-default set) so the pile matches the table. Returns { rim, plate, glow }.
function CosmeticSets.pileStyleOf(set, back)
	local pile = CardBacks.pileStyle(back)
	local accent = set and set.id ~= CosmeticSets.DefaultId and CosmeticSets.accentOf(set) or nil
	if not accent then
		return pile
	end
	return { rim = mix(pile.rim, accent, 0.35), plate = pile.plate, glow = mix(pile.glow, accent, 0.35) }
end

-- The tint the draw pile layers and the discard ghosts wear: the set's own card back colours ({ base, trim, edge } as rgb triples).
-- nil for the default set (classic is unchanged) or a set without a known back. Pure.
function CosmeticSets.deckTint(setId)
	if setId == nil or setId == CosmeticSets.DefaultId then return nil end
	local set = CosmeticSets.getById(setId)
	local back = set and CardBacks.getById(set.cardBackId)
	local colors = back and back.colors
	if not colors then return nil end
	return { base = colors.base, trim = colors.trim, edge = mix(colors.base, { 14, 10, 7 }, 0.55) }
end

CosmeticSets.SKIN_SLOTS = {
	{ slot = "faceFrame", key = "face_frame" },
	{ slot = "facePaper", key = "face_paper" },
	{ slot = "faceCourt", key = "face_court" },
	{ slot = "panelFrame", key = "panel_frame" },
	{ slot = "panelFrame9", key = "panel_frame9" }, -- slice-friendly border art (set_panels); without it panels use the code border
	{ slot = "buttonPlate", key = "button_plate" },
	{ slot = "tabPlate", key = "tab_plate" },
}

-- Skin for a set: { images = { slot = id|nil }, colors = {...}|nil, neutral }. Pure.
function CosmeticSets.skinOf(set)
	local images = {}
	if set and set.id then
		for _, def in ipairs(CosmeticSets.SKIN_SLOTS) do
			local id = SetSkinArt[set.id .. "_" .. def.key]
			if type(id) == "string" and id ~= "" and id ~= "rbxassetid://0" then images[def.slot] = id end
		end
		-- cleaned button plate (no stud block in the stretchable middle) wins over the original, which stays as the fallback
		local slice = SetSkinArt[set.id .. "_button_plate_slice"]
		if type(slice) == "string" and slice ~= "" and slice ~= "rbxassetid://0" then images.buttonPlate = slice end
		-- slice-friendly panel border (set_panels): only for sets whose art passed the fit test (SetPanelFit)
		local panel, fit = SetPanelArt[set.id], SetPanelFit[set.id]
		if not images.panelFrame9 and type(panel) == "string" and panel ~= "" and fit and fit.pass then
			images.panelFrame9 = panel
		end
	end
	local face = CosmeticSets.faceStyleOf(set)
	if face.neutral then
		-- plates only when frame or court art exists (otherwise the default look is untouched)
		local index = nil
		if images.faceFrame or images.faceCourt then
			index = { red = CosmeticSets.indexStyle(set, true), black = CosmeticSets.indexStyle(set, false) }
		end
		return { id = set and set.id, images = images, colors = nil, neutral = true, index = index }
	end
	local accent = CosmeticSets.accentOf(set) or face.border
	local dark = { 28, 20, 14 }
	-- button fill dark enough that cream button text reads at 4.5:1 (mid-tone accents otherwise fail both colours)
	local buttonFill = mix(accent, dark, 0.3)
	local fillSteps = 0
	while CosmeticSets.contrastRatio({ 250, 244, 226 }, buttonFill) < 4.5 and fillSteps < 12 do
		buttonFill = mix(buttonFill, dark, 0.15)
		fillSteps = fillSteps + 1
	end
	return {
		id = set and set.id,
		images = images,
		neutral = false,
		classicFace = set and set.classicFace == true or nil,
		index = { red = CosmeticSets.indexStyle(set, true), black = CosmeticSets.indexStyle(set, false) },
		colors = {
			paper = face.paper, border = face.border, pip = face.pip,
			panel = mix(accent, dark, 0.45),
			button = buttonFill,
			tab = mix(accent, dark, 0.55),
		},
	}
end

-- Card index legibility. No plate is drawn: the corners sit on the card paper; ink is the suit colour (leaning toward the
-- set's pip colour) darkened until it reaches 4.5:1 against the paper colour. Pure.
CosmeticSets.RED_INK = { 165, 28, 28 }
CosmeticSets.BLACK_INK = { 30, 22, 18 }
CosmeticSets.MIN_INDEX_CONTRAST = 4.5

local function channel(v)
	v = v / 255
	if v <= 0.03928 then return v / 12.92 end
	return ((v + 0.055) / 1.055) ^ 2.4
end

local function luminance(c)
	return 0.2126 * channel(c[1]) + 0.7152 * channel(c[2]) + 0.0722 * channel(c[3])
end

function CosmeticSets.contrastRatio(a, b)
	local la, lb = luminance(a), luminance(b)
	if la < lb then la, lb = lb, la end
	return (la + 0.05) / (lb + 0.05)
end

-- The Menu wordmark in a Card Set's accent: { top, bottom, image } (rgb tables), the wordmark gold pulled 35 percent toward the accent and
-- lightened until BOTH gradient stops keep 7:1 against the wordmark outline. `image` is the multiply tint for the painted wordmark (white
-- pulled 30 percent toward the accent, never darker than the gold stops). nil for classic or an unknown set, so classic is untouched.
CosmeticSets.WORDMARK_GOLD = { top = { 236, 205, 134 }, bottom = { 184, 146, 80 }, outline = { 46, 30, 14 } }
CosmeticSets.WORDMARK_MIN_CONTRAST = 7
function CosmeticSets.wordmarkTint(setId)
	local ring = CosmeticSets.ringColorOf(setId)
	if not ring then return nil end
	local g = CosmeticSets.WORDMARK_GOLD
	local function lit(gold)
		local c = mix(gold, ring, 0.35)
		local guard = 0
		while CosmeticSets.contrastRatio(c, g.outline) < CosmeticSets.WORDMARK_MIN_CONTRAST and guard < 40 do
			c = mix(c, { 255, 255, 255 }, 0.1)
			guard = guard + 1
		end
		return c
	end
	local image = mix({ 255, 255, 255 }, ring, 0.30)
	return { top = lit(g.top), bottom = lit(g.bottom), image = image }
end

-- The round close X disc in a Card Set's accent: { rest, hover } (rgb tables), brass pulled 50 percent toward the accent and darkened until the
-- cream cross keeps 3:1 (a graphic needs 3:1); hover is a lighter step. nil for classic or an unknown set, so classic keeps its brass.
CosmeticSets.CLOSE_BRASS = { 176, 138, 66 }
CosmeticSets.CLOSE_CROSS = { 250, 240, 220 }
function CosmeticSets.closeDiscOf(setId)
	local ring = CosmeticSets.ringColorOf(setId)
	if not ring then return nil end
	local c = mix(CosmeticSets.CLOSE_BRASS, ring, 0.5)
	local guard = 0
	while CosmeticSets.contrastRatio(c, CosmeticSets.CLOSE_CROSS) < 3 and guard < 40 do
		c = mix(c, { 30, 20, 12 }, 0.1)
		guard = guard + 1
	end
	return { rest = c, hover = mix(c, { 255, 255, 255 }, 0.18) }
end

-- Settings controls in the set accent: slider fill (4.5:1 on the dark track) and the On switch (white text 4.5:1 on its fill). nil for classic.
CosmeticSets.SLIDER_TRACK = { 60, 45, 32 }
CosmeticSets.SWITCH_ON_TEXT = { 255, 255, 255 }
CosmeticSets.CONTROL_MIN_CONTRAST = 4.5
function CosmeticSets.controlAccentOf(setId)
	local ring = CosmeticSets.ringColorOf(setId)
	if not ring then return nil end
	local fill = ring
	local guard = 0
	while CosmeticSets.contrastRatio(fill, CosmeticSets.SLIDER_TRACK) < CosmeticSets.CONTROL_MIN_CONTRAST and guard < 40 do
		fill = mix(fill, { 255, 244, 226 }, 0.12)
		guard = guard + 1
	end
	local onFill = ring
	guard = 0
	while CosmeticSets.contrastRatio(onFill, CosmeticSets.SWITCH_ON_TEXT) < CosmeticSets.CONTROL_MIN_CONTRAST and guard < 40 do
		onFill = mix(onFill, { 20, 14, 10 }, 0.12)
		guard = guard + 1
	end
	return { sliderFill = fill, onFill = onFill, onText = CosmeticSets.SWITCH_ON_TEXT }
end

-- Hint plates (tooltips, the guided hint, the Next goal banner): the same dark accent tint and cream ink, 7:1. nil for classic.
function CosmeticSets.hintStyleOf(setId)
	local b = CosmeticSets.titleBandOf(setId)
	if not b then return nil end
	return { plate = b.fill, edge = b.edge, ink = b.ink }
end

-- List rows (Leaderboards, Quests, Daily Rewards): a dark set-tinted row plate with cream ink (7:1), a lighter "you or today" row, a muted
-- second line and a rank badge in the accent (each 4.5:1 or more on its own fill), and a claim chip in the control accent with white text.
-- nil for classic so the parchment and brown rows stay as they are.
CosmeticSets.ROW_MIN_CONTRAST = 4.5
function CosmeticSets.rowStyleOf(setId)
	local band = CosmeticSets.titleBandOf(setId)
	local control = CosmeticSets.controlAccentOf(setId)
	if not band or not control then return nil end
	local row, ink = band.fill, band.ink
	local hot = mix(row, band.edge, 0.22)
	local guard = 0
	while CosmeticSets.contrastRatio(hot, ink) < CosmeticSets.TITLE_MIN_CONTRAST and guard < 40 do
		hot = mix(hot, { 20, 14, 10 }, 0.15)
		guard = guard + 1
	end
	local sub = mix(ink, row, 0.25)
	guard = 0
	while (CosmeticSets.contrastRatio(sub, row) < CosmeticSets.ROW_MIN_CONTRAST or CosmeticSets.contrastRatio(sub, hot) < CosmeticSets.ROW_MIN_CONTRAST) and guard < 40 do
		sub = mix(sub, ink, 0.2)
		guard = guard + 1
	end
	local badge = band.edge
	local dark, light = { 12, 8, 6 }, { 255, 255, 255 }
	local badgeInk = CosmeticSets.contrastRatio(badge, dark) >= CosmeticSets.contrastRatio(badge, light) and dark or light
	return { row = row, hot = hot, ink = ink, sub = sub, edge = band.edge, badge = badge, badgeInk = badgeInk, chip = control.onFill, chipInk = control.onText }
end

-- Small popups (Confirm, Choice, Quit, Restart): `dark` is the wood-panel look (fill, edge, cream ink, 7:1) and `paper` is the parchment look
-- (top and bottom paper stops tinted toward the accent, dark ink kept at 7:1 on both, accent edge). nil for classic so those popups stay as built.
CosmeticSets.PAPER_INK = { 46, 32, 20 }
CosmeticSets.POPUP_MIN_CONTRAST = 7
function CosmeticSets.popupStyleOf(setId)
	local b = CosmeticSets.titleBandOf(setId)
	if not b then return nil end
	local function paperStop(base, t)
		local c = mix(base, b.edge, t)
		local guard = 0
		while CosmeticSets.contrastRatio(c, CosmeticSets.PAPER_INK) < CosmeticSets.POPUP_MIN_CONTRAST and guard < 40 do
			c = mix(c, { 250, 244, 226 }, 0.15)
			guard = guard + 1
		end
		return c
	end
	return {
		dark = { fill = b.fill, edge = b.edge, ink = b.ink },
		paper = { top = paperStop({ 246, 232, 198 }, 0.16), bottom = paperStop({ 228, 210, 172 }, 0.24), edge = b.edge, ink = CosmeticSets.PAPER_INK },
	}
end

-- Tavern Map: the header bar, rails, banners, select panel frame and Go plate take the set. `bar` and `inset` are dark fills, `edge` is the
-- accent lifted until it reads 4.5:1 on both (gold lines, rails, studs), `ink` stays cream 7:1 on `bar`, `go` is the control accent with white
-- ink 4.5:1. nil for classic so the map keeps its wood and gold.
CosmeticSets.MAP_MIN_CONTRAST = 4.5
function CosmeticSets.mapStyleOf(setId)
	local band = CosmeticSets.titleBandOf(setId)
	local control = CosmeticSets.controlAccentOf(setId)
	if not band or not control then return nil end
	local bar = band.fill
	local inset = mix({ 88, 58, 34 }, band.edge, 0.2)
	local guard = 0
	while CosmeticSets.contrastRatio(inset, band.ink) < CosmeticSets.TITLE_MIN_CONTRAST and guard < 40 do
		inset = mix(inset, { 20, 14, 10 }, 0.15)
		guard = guard + 1
	end
	local edge = band.edge
	guard = 0
	while (CosmeticSets.contrastRatio(edge, bar) < CosmeticSets.MAP_MIN_CONTRAST or CosmeticSets.contrastRatio(edge, inset) < CosmeticSets.MAP_MIN_CONTRAST) and guard < 40 do
		edge = mix(edge, { 255, 244, 214 }, 0.15)
		guard = guard + 1
	end
	return {
		bar = bar, sheen = mix(bar, edge, 0.14), inset = inset, frame = mix({ 150, 104, 62 }, band.edge, 0.3),
		edge = edge, ink = band.ink, banner = mix({ 92, 46, 130 }, band.edge, 0.5), go = control.onFill, goInk = control.onText,
	}
end

-- The dark plate behind the Counter's My Patrons and My Recipes tabs: the set's map bar as fill and its lifted edge as the rim (edge reads 4.5:1
-- on the fill). nil for classic, which keeps its brown plate and gold rim.
function CosmeticSets.tabPlateStyleOf(setId)
	local m = CosmeticSets.mapStyleOf(setId)
	if not m then return nil end
	return { fill = m.bar, edge = m.edge }
end

-- Tavern Ledger: the desk, leather cover, bookmark ribbons and run rows take the set. Ribbons keep cream ink at 4.5:1 (open one lighter), the
-- two run-row papers keep the soft ledger ink (70,48,28) at 4.5:1. nil for classic so the ledger keeps its leather, red silk and cream paper.
CosmeticSets.LEDGER_INK = { 70, 48, 28 }
CosmeticSets.LEDGER_TAB_INK = { 255, 236, 190 }
function CosmeticSets.ledgerStyleOf(setId)
	local band = CosmeticSets.titleBandOf(setId)
	local popup = CosmeticSets.popupStyleOf(setId)
	if not band or not popup then return nil end
	local function darkenFor(c, ink, minRatio)
		local guard = 0
		while CosmeticSets.contrastRatio(c, ink) < minRatio and guard < 40 do
			c = mix(c, { 20, 14, 10 }, 0.12)
			guard = guard + 1
		end
		return c
	end
	local function lightenFor(c, ink, minRatio)
		local guard = 0
		while CosmeticSets.contrastRatio(c, ink) < minRatio and guard < 40 do
			c = mix(c, { 250, 244, 226 }, 0.12)
			guard = guard + 1
		end
		return c
	end
	local tabOff = darkenFor(mix({ 108, 34, 34 }, band.edge, 0.3), CosmeticSets.LEDGER_TAB_INK, CosmeticSets.MAP_MIN_CONTRAST)
	local tabOn = darkenFor(mix({ 150, 44, 44 }, band.edge, 0.35), CosmeticSets.LEDGER_TAB_INK, CosmeticSets.MAP_MIN_CONTRAST)
	return {
		deskTop = mix({ 86, 58, 36 }, band.edge, 0.22), deskFoot = mix({ 36, 24, 16 }, band.edge, 0.12), leather = mix({ 88, 52, 30 }, band.edge, 0.3),
		tabOn = tabOn, tabOff = tabOff, tabInk = CosmeticSets.LEDGER_TAB_INK,
		row = lightenFor(popup.paper.top, CosmeticSets.LEDGER_INK, CosmeticSets.MAP_MIN_CONTRAST),
		rowOpen = lightenFor(popup.paper.bottom, CosmeticSets.LEDGER_INK, CosmeticSets.MAP_MIN_CONTRAST), edge = band.edge,
	}
end

-- The Tavern Map road: the sandy dash and its edge tinted toward the set accent, edge kept 3:1 under the fill. nil for classic.
function CosmeticSets.mapPathOf(setId, fill, edge)
	local band = CosmeticSets.titleBandOf(setId)
	if not band then return nil end
	local f = mix(fill, band.edge, 0.3)
	local e = mix(edge, band.edge, 0.3)
	local guard = 0
	while CosmeticSets.contrastRatio(f, e) < 3 and guard < 40 do
		e = mix(e, { 20, 14, 10 }, 0.15)
		guard = guard + 1
	end
	return f, e
end

-- Loading screen: the equipped set's dark plate, accent edge and cream ink (7:1) for the tip plate, Skip plate and bar trim. nil for classic,
-- an unknown id or no id (a first join has no profile yet), so the screen keeps its painted look.
function CosmeticSets.loadingStyleOf(setId)
	local h = CosmeticSets.hintStyleOf(setId)
	if not h then return nil end
	return { plate = h.plate, edge = h.edge, ink = h.ink, tipAlpha = 0.35 }
end

-- Popup title band: a dark strip tinted toward the equipped set accent behind a cream title, edge in the accent. Cream text keeps 7:1 on the fill.
-- nil for classic or an unknown set so classic popups stay as they are.
CosmeticSets.TITLE_INK = { 250, 240, 220 }
CosmeticSets.TITLE_MIN_CONTRAST = 7
function CosmeticSets.titleBandOf(setId)
	local ring = CosmeticSets.ringColorOf(setId)
	if not ring then return nil end
	local fill = mix({ 40, 28, 20 }, ring, 0.3)
	local guard = 0
	while CosmeticSets.contrastRatio(fill, CosmeticSets.TITLE_INK) < CosmeticSets.TITLE_MIN_CONTRAST and guard < 40 do
		fill = mix(fill, { 20, 14, 10 }, 0.15)
		guard = guard + 1
	end
	return { fill = fill, edge = ring, ink = CosmeticSets.TITLE_INK }
end

-- { plate = {r,g,b}, ink = {r,g,b} } for one suit colour of a set (isRed true or false).
function CosmeticSets.minContrastOf(set)
	return set and set.minIndexContrast or CosmeticSets.MIN_INDEX_CONTRAST
end

function CosmeticSets.indexStyle(set, isRed)
	local face = CosmeticSets.faceStyleOf(set)
	local base = isRed and CosmeticSets.RED_INK or CosmeticSets.BLACK_INK
	local cream = { 250, 244, 226 }
	local plate, ink
	if face.neutral then
		-- warm the near-white plate about 25 percent toward parchment so it reads as printed on the card
		plate = mix(cream, { 226, 208, 170 }, 0.25)
		ink = base
	else
		plate = face.paper -- the paper colour itself (field name kept: it is the surface the ink sits on)
		ink = mix(base, face.pip, isRed and 0.2 or 0.5)
	end
	if set and set.darkFace and not face.neutral then
		-- dark painted face: light ink (cream, a warm coral for red suits) on the face's own deep tone, 7:1 at least
		plate = mix(face.pip, { 8, 14, 24 }, 0.5)
		ink = isRed and { 255, 176, 160 } or { 250, 244, 226 }
		local lift = 0
		while CosmeticSets.contrastRatio(ink, plate) < math.max(7, CosmeticSets.minContrastOf(set)) and lift < 10 do
			plate = mix(plate, { 0, 0, 0 }, 0.25)
			lift = lift + 1
		end
		return { plate = plate, ink = ink, edge = mix(plate, ink, 0.35), dark = true }
	end
	local dark = CosmeticSets.BLACK_INK
	local steps = 0
	while CosmeticSets.contrastRatio(ink, plate) < CosmeticSets.minContrastOf(set) and steps < 10 do
		ink = mix(ink, dark, 0.25)
		steps = steps + 1
	end
	return { plate = plate, ink = ink, edge = mix(plate, ink, 0.55) }
end

-- Centre pip look on a dark painted face: { ink, outline } (light ink, dark outline) with ink at 4.5:1 or more against the
-- face's deep tone. Returns nil for classic and light faces (they keep the set pip ink).
function CosmeticSets.darkPipStyle(set, isRed)
	if not (set and set.darkFace) then return nil end
	local face = CosmeticSets.faceStyleOf(set)
	if face.neutral then return nil end
	local ground = mix(face.pip, { 8, 14, 24 }, 0.5)
	local ink = isRed and { 255, 176, 160 } or { 250, 244, 226 }
	local n = 0
	while CosmeticSets.contrastRatio(ink, ground) < 4.5 and n < 10 do
		ink = mix(ink, { 255, 255, 255 }, 0.2)
		n = n + 1
	end
	return { ink = ink, outline = { 8, 14, 24 } }
end

-- Gamepad focus ring colour for a set: the set accent lightened toward white until it keeps 3:1 against the dark wood behind buttons;
-- classic and unknown sets keep the gold ring. Returns {r,g,b}.
CosmeticSets.FOCUS_RING_GOLD = { 246, 196, 70 }
CosmeticSets.FOCUS_RING_BACKING = { 40, 26, 16 }
function CosmeticSets.focusRingOf(setId)
	local set = CosmeticSets.getById(setId)
	if not set or set.id == CosmeticSets.DefaultId then return CosmeticSets.FOCUS_RING_GOLD end
	local ring = CosmeticSets.accentOf(set)
	if not ring then return CosmeticSets.FOCUS_RING_GOLD end
	local steps = 0
	while CosmeticSets.contrastRatio(ring, CosmeticSets.FOCUS_RING_BACKING) < 3 and steps < 10 do
		ring = mix(ring, { 255, 255, 255 }, 0.2)
		steps = steps + 1
	end
	return ring
end

-- Colorblind Suits ink for one suit mark ({r,g,b}) on a set's card: darkened toward black until it reads at the set's
-- minimum contrast on both the face paper and the index plate. Returns {r,g,b}.
function CosmeticSets.colorblindInkOf(set, markInk)
	local paper = CosmeticSets.cardLook(set).paper
	local plate = CosmeticSets.indexStyle(set, false).plate
	local need = math.max(4.5, CosmeticSets.minContrastOf(set))
	if set and set.darkFace then
		-- dark painted face: lighten toward cream until the mark reads on the dark plate
		local light, n = markInk, 0
		while CosmeticSets.contrastRatio(light, plate) < need and n < 12 do
			light = mix(light, { 250, 244, 226 }, 0.2)
			n = n + 1
		end
		return light
	end
	local ink, steps = markInk, 0
	while (CosmeticSets.contrastRatio(ink, paper) < need or CosmeticSets.contrastRatio(ink, plate) < need) and steps < 12 do
		ink = mix(ink, CosmeticSets.BLACK_INK, 0.2)
		steps = steps + 1
	end
	return ink
end

-- Text colour for a button whose plate fill is `fill` ({r,g,b}): cream or near-black, whichever reads better (4.5:1 or more
-- for every fill the sets use; the larger of the two is returned when neither reaches it).
function CosmeticSets.buttonTextColor(fill)
	local cream, dark = { 250, 244, 226 }, { 30, 20, 12 }
	if CosmeticSets.contrastRatio(cream, fill) >= CosmeticSets.contrastRatio(dark, fill) then
		return cream
	end
	return dark
end

-- Worst ink-vs-plate contrast over both suit colours.
function CosmeticSets.indexContrast(set)
	local worst = math.huge
	for _, red in ipairs({ true, false }) do
		local st = CosmeticSets.indexStyle(set, red)
		worst = math.min(worst, CosmeticSets.contrastRatio(st.ink, st.plate))
	end
	return worst
end

-- Card look on the thin-edge ivory card: every set shows on the card itself without the old heavy frame.
-- { edge, paper, wash, washTransparency, ink = { red, black }, motif = "frost"|"warm"|nil }. Pure.
--   edge  the 1 px edge stroke and corner pips colour (the set accent; Classic keeps the brass)
--   wash  the set's paper colour laid over the ivory at 1 - washTransparency (10 percent, within 5 to 12)
--   paper the resulting face colour the index ink must read on (4.5:1)
CosmeticSets.IVORY = { 246, 236, 214 }
CosmeticSets.CLASSIC_EDGE = { 214, 172, 88 }
CosmeticSets.WASH_STRENGTH = 0.10
CosmeticSets.CARD_MOTIF = {
	winter_evening = "frost", snowy_hearth = "frost", winter_table = "frost", summit_camp = "frost",
	harvest_table = "warm", tavern_feast = "warm", meadow_picnic = "warm",
}

function CosmeticSets.cardLook(set)
	local face = CosmeticSets.faceStyleOf(set)
	if face.neutral then
		return { edge = CosmeticSets.CLASSIC_EDGE, paper = CosmeticSets.IVORY, wash = CosmeticSets.IVORY, washTransparency = 1, ink = { red = CosmeticSets.RED_INK, black = CosmeticSets.BLACK_INK } }
	end
	local edge = CosmeticSets.accentOf(set) or face.border
	local paper = mix(CosmeticSets.IVORY, face.paper, CosmeticSets.WASH_STRENGTH)
	local function inkOn(isRed)
		local ink = mix(isRed and CosmeticSets.RED_INK or CosmeticSets.BLACK_INK, face.pip, isRed and 0.2 or 0.5)
		local steps = 0
		while CosmeticSets.contrastRatio(ink, paper) < CosmeticSets.minContrastOf(set) and steps < 10 do
			ink = mix(ink, CosmeticSets.BLACK_INK, 0.25)
			steps = steps + 1
		end
		return ink
	end
	return {
		edge = edge, paper = paper, wash = face.paper, washTransparency = 1 - CosmeticSets.WASH_STRENGTH,
		ink = { red = inkOn(true), black = inkOn(false) }, motif = CosmeticSets.CARD_MOTIF[set and set.id or ""],
	}
end

function CosmeticSets.themeOf(set)
	local face = CosmeticSets.faceStyleOf(set)
	return {
		skin = CosmeticSets.skinOf(set),
		backdropStyle = CosmeticSets.backdropStyleOf(set),
		face = face,
		accent = face.neutral and nil or CosmeticSets.accentOf(set),
		neutral = face.neutral == true,
	}
end

return CosmeticSets
