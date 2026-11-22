--[[
	Shared/Engine/ThemeScenes.lua
	One equipped Card Set dresses every screen. Per set: the art key for each scene slot, a tint, an ambient particle kind and a text accent.
	Layouts, rects and hit targets never come from here: only art keys and colours. Pure Lua, tested in EngineTests ("ThemeScenes").

	ThemeScenes.of(setId)            -> { setId, art = { <slot> = key }, painted = { <slot> = true|nil }, tint, ambient, accent }
	                                    Every art slot falls back per key to classic_tavern; an unknown set is classic_tavern.
	ThemeScenes.washStyle(setId, slot) -> a Client/BackdropStyles style (overlay at WASH_TRANSPARENCY, frost vignette for cold sets,
	                                    ambient particles) or nil when the slot is painted for this set or the set is classic_tavern.
	ThemeScenes.SLOTS                the six art slots
	ThemeScenes.ORDER                set ids, stable order

	Slots: menuBackdrop, tableBackground, tableFront (rail), bossTableBackground, mapBackdrop, shopBackdrop.
	An art value is a registry key ("play_room_<set>_bg") or "<ContentArt category>:<key>" for the classic menu, map and shop pictures.
	painted[slot] is true only when that slot has a set specific picture (the 14 table rooms today). Every other slot of a non
	classic set uses the interim procedural wash, so equipping any set visibly changes every screen (see claude/THEMES.md).
]]

local PlayRoomArt = require(script.Parent.PlayRoomArt)

local ThemeScenes = {}

ThemeScenes.DEFAULT = "classic_tavern"
ThemeScenes.WASH_TRANSPARENCY = 0.78
ThemeScenes.SLOTS = { "menuBackdrop", "tableBackground", "tableFront", "bossTableBackground", "mapBackdrop", "shopBackdrop", "tablePlay" }
ThemeScenes.ORDER = { "classic_tavern", "winter_evening", "festival_night", "closing_time", "golden_gala", "meadow_picnic", "riverside_evening",
	"summit_camp", "dune_market", "marsh_lanterns", "snowy_hearth", "harbor_lights", "tavern_feast", "harvest_table", "winter_table" }

-- the classic scenes, the fallback of every slot
local CLASSIC_ART = {
	menuBackdrop = "menu_scene:wall",
	tableBackground = PlayRoomArt.CLASSIC.bg,
	tableFront = PlayRoomArt.CLASSIC.front,
	bossTableBackground = "table_scene:table_boss_ref",
	tablePlay = "table_scene:table_play_ref", -- the live table (Client/Gameplay2) scene for a normal round
	mapBackdrop = "map:journeyMapImage",
	shopBackdrop = "shop_scene:shop_room_a",
}

-- tint = wash colour, ambient = first AmbientLayout kind of the set, accent = text accent (cream on dark washes, never below 4.5:1 on them)
-- frost = true gives the wash a cold vignette
local DATA = {
	classic_tavern    = { tint = { 0, 0, 0 },       ambient = "dust",      accent = { 255, 224, 150 } },
	winter_evening    = { tint = { 60, 110, 190 },  ambient = "snow",      accent = { 200, 228, 255 }, frost = true },
	festival_night    = { tint = { 255, 170, 80 },  ambient = "lantern",   accent = { 255, 214, 150 } },
	closing_time      = { tint = { 170, 80, 40 },   ambient = "ember",     accent = { 255, 200, 140 } },
	golden_gala       = { tint = { 230, 180, 60 },  ambient = "mote",      accent = { 255, 230, 150 } },
	meadow_picnic     = { tint = { 90, 170, 80 },   ambient = "butterfly", accent = { 235, 250, 200 } },
	riverside_evening = { tint = { 70, 100, 170 },  ambient = "mist",      accent = { 215, 228, 255 } },
	summit_camp       = { tint = { 110, 140, 190 }, ambient = "cloud",     accent = { 225, 238, 255 }, frost = true },
	dune_market       = { tint = { 220, 160, 80 },  ambient = "sand",      accent = { 255, 224, 170 } },
	marsh_lanterns    = { tint = { 60, 130, 100 },  ambient = "firefly",   accent = { 220, 250, 190 } },
	snowy_hearth      = { tint = { 120, 160, 210 }, ambient = "snow",      accent = { 255, 226, 190 }, frost = true },
	harbor_lights     = { tint = { 50, 110, 160 },  ambient = "shimmer",   accent = { 255, 224, 160 } },
	tavern_feast      = { tint = { 200, 120, 50 },  ambient = "dust",      accent = { 255, 224, 150 } },
	harvest_table     = { tint = { 190, 120, 40 },  ambient = "leaf",      accent = { 255, 218, 150 } },
	winter_table      = { tint = { 100, 150, 210 }, ambient = "snow",      accent = { 225, 240, 255 }, frost = true },
}

-- the backdrop layer kinds Client/BackdropStyles can draw (CosmeticSets.BackdropLimits.layerKinds) for each ambient kind
local LAYER_OF = { snow = "snow", ember = "sparks", dust = "dust", mote = "dust", pollen = "dust", firefly = "dust", leaf = "dust", sand = "dust" }

-- painted per theme scenes (table_scene ids, see claude/THEMES.md): menu, boss table and map ground. The table room itself is the set's PlayRoomArt pair.
-- boss and map ids are registered; their screens (Gameplay2, Tavern Map) read the art key when those lanes wire it.
local THEME_ART = {
	winter_evening = { menuBackdrop = "table_scene:theme_ice_menu", bossTableBackground = "table_scene:theme_ice_boss", mapBackdrop = "table_scene:theme_ice_map" },
	golden_gala = { menuBackdrop = "table_scene:theme_gala_menu", bossTableBackground = "table_scene:theme_gala_boss", tablePlay = "table_scene:theme_gala_play", shopBackdrop = "shop_scene:shop_room_gala" },
}

local function setArt(setId)
	local art = {}
	for k, v in pairs(CLASSIC_ART) do art[k] = v end
	local painted = {}
	-- per Card Set rooms are painted: the table, the boss table and the rail follow the set's room pair
	if setId ~= ThemeScenes.DEFAULT and PlayRoomArt.SETS[setId] then
		local k = PlayRoomArt.keys(setId)
		art.tableBackground, art.tableFront, art.bossTableBackground = k.bg, k.front, k.bg
		painted.tableBackground, painted.tableFront, painted.bossTableBackground = true, true, true
	end
	for slot, key in pairs(THEME_ART[setId] or {}) do art[slot] = key end
	return art, painted
end

-- the one small prop a set's mini table scene shows (Client/CardSetsRoom): candle, lantern, snowflakes or leaves
local PROP_OF = { snow = "snowflakes", cloud = "snowflakes", lantern = "lantern", mote = "lantern", mist = "lantern", firefly = "lantern", shimmer = "lantern",
	butterfly = "leaves", leaf = "leaves", ember = "candle", dust = "candle", sand = "candle" }
function ThemeScenes.propOf(setId)
	return PROP_OF[ThemeScenes.of(setId).ambient] or "candle"
end

-- the Image id of a set's own painted art for a slot ("table_scene:<id>" keys), or nil to keep the classic picture
function ThemeScenes.themeImageId(setId, slot)
	local own = THEME_ART[setId]
	local key = own and own[slot]
	if not key then return nil end
	local tab, id = string.match(key, "^(%w+_%w+):(.+)$")
	if not tab then return nil end
	return require(script.Parent.ContentArt).getImageId(tab, id)
end

-- The Counter room picture for a set: its own painted shop room (golden_gala) or the classic shop_room_a.
-- Returns id, own (own is true only when the set has its own picture; Client/ShopBackdrop then hides the classic strip and tavern layer).
function ThemeScenes.shopRoomId(setId)
	local ContentArt = require(script.Parent.ContentArt)
	local own = ThemeScenes.themeImageId(setId, "shopBackdrop")
	if own then return own, true end
	return ContentArt.getImageId("shop_scene", "shop_room_a"), false
end

-- Which set a backdrop (menu, shop, map) shows: a Studio/Card Sets preview wins over the equipped skin, never saved.
function ThemeScenes.effectiveSetId(skinId, previewId)
	if previewId ~= nil and ThemeScenes.known(previewId) then return previewId end
	return ThemeScenes.known(skinId) and skinId or ThemeScenes.DEFAULT
end

function ThemeScenes.known(setId)
	return type(setId) == "string" and DATA[setId] ~= nil
end

function ThemeScenes.of(setId)
	local id = ThemeScenes.known(setId) and setId or ThemeScenes.DEFAULT
	local d = DATA[id]
	local art, painted = setArt(id)
	return { setId = id, art = art, painted = painted, tint = d.tint, ambient = d.ambient, accent = d.accent, frost = d.frost == true }
end

-- true when the slot of this set is the interim wash (no set specific picture)
function ThemeScenes.washed(setId, slot)
	local t = ThemeScenes.of(setId)
	return t.setId ~= ThemeScenes.DEFAULT and not t.painted[slot]
end

function ThemeScenes.washStyle(setId, slot)
	if not ThemeScenes.washed(setId, slot) then return nil end
	local t = ThemeScenes.of(setId)
	local style = { overlay = { color = t.tint, transparency = ThemeScenes.WASH_TRANSPARENCY } }
	if t.frost then style.vignette = { color = { 190, 225, 255 }, strength = 0.5 } end
	local kind = LAYER_OF[t.ambient]
	if kind then style.layers = { { kind = kind, count = kind == "snow" and 18 or 8, speed = 0.5 } } end
	return style
end

return ThemeScenes
