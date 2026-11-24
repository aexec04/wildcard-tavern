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
	riverside_evening = { tint = { 70, 100, 170 },  ambient = "firefly",   accent = { 215, 228, 255 } },
	summit_camp       = { tint = { 110, 140, 190 }, ambient = "snow",      accent = { 225, 238, 255 }, frost = true },
	dune_market       = { tint = { 220, 160, 80 },  ambient = "sand",      accent = { 255, 224, 170 } },
	marsh_lanterns    = { tint = { 60, 130, 100 },  ambient = "firefly",   accent = { 220, 250, 190 } },
	snowy_hearth      = { tint = { 120, 160, 210 }, ambient = "snow",      accent = { 255, 226, 190 }, frost = true },
	harbor_lights     = { tint = { 50, 110, 160 },  ambient = "glow",      accent = { 255, 224, 160 } },
	tavern_feast      = { tint = { 200, 120, 50 },  ambient = "dust",      accent = { 255, 224, 150 } },
	harvest_table     = { tint = { 190, 120, 40 },  ambient = "leaf",      accent = { 255, 218, 150 } },
	winter_table      = { tint = { 100, 150, 210 }, ambient = "snow",      accent = { 225, 240, 255 }, frost = true },
}

-- the backdrop layer kinds Client/BackdropStyles can draw (CosmeticSets.BackdropLimits.layerKinds) for each ambient kind
local LAYER_OF = { snow = "snow", ember = "sparks", dust = "dust", mote = "dust", pollen = "dust", firefly = "dust", leaf = "dust", sand = "dust" }

-- painted per theme scenes (table_scene ids, see claude/THEMES.md): menu, boss table and map ground. The table room itself is the set's PlayRoomArt pair.
-- boss and map ids are registered; their screens (Gameplay2, Tavern Map) read the art key when those lanes wire it.
local THEME_ART = {
	winter_evening = { menuBackdrop = "table_scene:theme_ice_menu", bossTableBackground = "table_scene:theme_ice_boss", mapBackdrop = "table_scene:theme_ice_map", shopBackdrop = "shop_scene:shop_room_frost" },
	festival_night = { shopBackdrop = "shop_scene:shop_room_fest" },
	closing_time = { shopBackdrop = "shop_scene:shop_room_close" },
	dune_market = { shopBackdrop = "shop_scene:shop_room_dune" },
	marsh_lanterns = { shopBackdrop = "shop_scene:shop_room_marsh" },
	snowy_hearth = { shopBackdrop = "shop_scene:shop_room_hearth" },
	harbor_lights = { shopBackdrop = "shop_scene:shop_room_harbor" },
	tavern_feast = { shopBackdrop = "shop_scene:shop_room_feast" },
	harvest_table = { shopBackdrop = "shop_scene:shop_room_harvest" },
	winter_table = { shopBackdrop = "shop_scene:shop_room_wtable" },
	meadow_picnic = { shopBackdrop = "shop_scene:shop_room_meadow" },
	riverside_evening = { shopBackdrop = "shop_scene:shop_room_river" },
	summit_camp = { shopBackdrop = "shop_scene:shop_room_summit" },
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
local PROP_OF = { snow = "snowflakes", glow = "lantern", cloud = "snowflakes", lantern = "lantern", mote = "lantern", mist = "lantern", firefly = "lantern", shimmer = "lantern",
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

-- The picture the live play table (Client/Gameplay2) draws for a set: its own painted theme art, else on a normal round its own room
-- (play_room_<set>_bg), else on a Boss round the boss fallback. nil keeps the classic tavern. `art` is the generated PlaySceneArt map.
-- One answer per set, so switching sets can never leave the previous set's room on screen.
function ThemeScenes.liveTableId(setId, boss, art)
	local own = ThemeScenes.themeImageId(setId, boss and "bossTableBackground" or "tablePlay")
	if own then return own end
	if ThemeScenes.known(setId) and setId ~= ThemeScenes.DEFAULT and PlayRoomArt.SETS[setId] then
		local v = art and art[PlayRoomArt.keys(setId).bg]
		if type(v) == "string" and v ~= "" and v ~= "rbxassetid://0" then return v end
	end
	return nil
end

-- The paper of the Stranger's offer scroll (Client/ShopHaggle): "frost", "gala" or "harvest" for the sets that have a variant, nil keeps the
-- cream scroll (shop_offer_scroll_a / _b). Variants are edits of scroll a, so they only replace the normal offer.
ThemeScenes.SCROLL_PAPER = { winter_evening = "frost", winter_table = "frost", golden_gala = "gala", harvest_table = "harvest" }
function ThemeScenes.scrollPaper(setId)
	return ThemeScenes.SCROLL_PAPER[setId]
end

-- Which picture a boss round table draws for a set: "own" (the set's boss table art), "room" (no boss art yet: the set's own play room, key
-- play_room_<set>_bg, never the classic tavern) or "classic" (Classic Tavern and unknown sets). Returns source, key-or-slot.
function ThemeScenes.bossBackdrop(setId)
	if ThemeScenes.known(setId) and setId ~= ThemeScenes.DEFAULT then
		if THEME_ART[setId] and THEME_ART[setId].bossTableBackground then return "own", "bossTableBackground" end
		if PlayRoomArt.SETS[setId] then return "room", PlayRoomArt.keys(setId).bg end
	end
	return "classic", nil
end

-- The Counter room picture for a set: its own painted shop room (golden_gala) or the classic shop_room_a.
-- Returns id, own (own is true only when the set has its own picture; Client/ShopBackdrop then hides the classic strip and tavern layer).
function ThemeScenes.shopRoomId(setId)
	local ContentArt = require(script.Parent.ContentArt)
	local own = ThemeScenes.themeImageId(setId, "shopBackdrop")
	if own then return own, true end
	return ContentArt.getImageId("shop_scene", "shop_room_a"), false
end

-- The Counter props sheet (bell, ledger, mug, candle) for a set: its own repainted sheet shop_counter_props_<setId> when that art exists,
-- otherwise the classic shop_counter_props. Same four crops on every sheet (ShopSceneLayout.PROP_CROP). Returns id, own.
function ThemeScenes.shopPropsId(setId)
	local ContentArt = require(script.Parent.ContentArt)
	if setId and setId ~= ThemeScenes.DEFAULT and ThemeScenes.known(setId) then
		local own = ContentArt.getImageId("shop_scene", "shop_counter_props_" .. setId)
		if own then return own, true end
	end
	return ContentArt.getImageId("shop_scene", "shop_counter_props"), false
end

-- The keeper pieces for a set: its own painted keeper (golden_gala courtier) or the classic Marlo pieces.
-- Returns behindId, waveId, own. Classic and every other set get shop_marlo_behind and shop_marlo_wave.
local KEEPER_OF = {
	golden_gala = { behind = "shop_marlo_gala_behind", wave = "shop_marlo_gala_wave" },
	winter_evening = { behind = "shop_marlo_frost_behind", wave = "shop_marlo_frost_wave" },
	festival_night = { behind = "shop_marlo_fest_behind", wave = "shop_marlo_fest_wave" },
	closing_time = { behind = "shop_marlo_close_behind", wave = "shop_marlo_close_wave" },
	dune_market = { behind = "shop_marlo_dune_behind", wave = "shop_marlo_dune_wave" },
	marsh_lanterns = { behind = "shop_marlo_marsh_behind", wave = "shop_marlo_marsh_wave" },
	snowy_hearth = { behind = "shop_marlo_hearth_behind", wave = "shop_marlo_hearth_wave" },
	harbor_lights = { behind = "shop_marlo_harbor_behind", wave = "shop_marlo_harbor_wave" },
	tavern_feast = { behind = "shop_marlo_feast_behind", wave = "shop_marlo_feast_wave" },
	harvest_table = { behind = "shop_marlo_harvest_behind", wave = "shop_marlo_harvest_wave" },
	winter_table = { behind = "shop_marlo_wtable_behind", wave = "shop_marlo_wtable_wave" },
	meadow_picnic = { behind = "shop_marlo_meadow_behind", wave = "shop_marlo_meadow_wave" },
	riverside_evening = { behind = "shop_marlo_river_behind", wave = "shop_marlo_river_wave" },
	summit_camp = { behind = "shop_marlo_summit_behind", wave = "shop_marlo_summit_wave" },
}
function ThemeScenes.shopKeeperIds(setId)
	local ContentArt = require(script.Parent.ContentArt)
	local k = KEEPER_OF[setId]
	if k then
		local b, w = ContentArt.getImageId("shop_scene", k.behind), ContentArt.getImageId("shop_scene", k.wave)
		if b then return b, w, true end
	end
	return ContentArt.getImageId("shop_scene", "shop_marlo_behind"), ContentArt.getImageId("shop_scene", "shop_marlo_wave"), false
end

-- Share of the Card Set room tint kept on a set's own painted Counter room: 0.3 means the gold wash is 70 percent lighter.
ThemeScenes.OWN_ROOM_TINT_KEEP = 0.3
-- tint is {r,g,b} 0..255 (PlayRoomArt.tint); an own room moves each channel 70 percent of the way back to white, others are unchanged.
function ThemeScenes.shopRoomTint(own, tint)
	if own ~= true then return tint end
	local k = ThemeScenes.OWN_ROOM_TINT_KEEP
	return { math.floor(255 + (tint[1] - 255) * k + 0.5), math.floor(255 + (tint[2] - 255) * k + 0.5), math.floor(255 + (tint[3] - 255) * k + 0.5) }
end

-- Whether the drawn green round card table is shown on the Counter: never on a set's own painted room (golden_gala), where the marble
-- floor and shelves read; the classic room and every other set keep the existing rule (hidden only inside the painted classic room).
function ThemeScenes.shopTableShown(own, hasTable, inPaintedRoom)
	if own == true then return false end
	return hasTable == true and inPaintedRoom ~= true
end

-- Which set a backdrop (menu, shop, map) shows: a Studio/Card Sets preview wins over the equipped skin, never saved.
function ThemeScenes.effectiveSetId(skinId, previewId)
	if previewId ~= nil and ThemeScenes.known(previewId) then return previewId end
	return ThemeScenes.known(skinId) and skinId or ThemeScenes.DEFAULT
end

-- Score pop-up colours per set: a dark plate (the set tint pulled toward black) and an accent that reads on it at 7:1 or more
-- (the set accent lifted toward white until it does). Returns nil for classic_tavern, which keeps its own look. Pure.
ThemeScenes.SCORE_MIN_CONTRAST = 7
local function lum(c)
	local function ch(v)
		v = v / 255
		return v <= 0.03928 and v / 12.92 or ((v + 0.055) / 1.055) ^ 2.4
	end
	return 0.2126 * ch(c[1]) + 0.7152 * ch(c[2]) + 0.0722 * ch(c[3])
end
local function ratio(a, b)
	local la, lb = lum(a), lum(b)
	if la < lb then la, lb = lb, la end
	return (la + 0.05) / (lb + 0.05)
end
function ThemeScenes.scoreStyle(setId)
	local t = ThemeScenes.of(setId)
	if t.setId == ThemeScenes.DEFAULT then return nil end
	local plate = { math.floor(t.tint[1] * 0.18), math.floor(t.tint[2] * 0.18), math.floor(t.tint[3] * 0.18) }
	local accent = { t.accent[1], t.accent[2], t.accent[3] }
	local step = 0
	while ratio(accent, plate) < ThemeScenes.SCORE_MIN_CONTRAST and step < 20 do
		step = step + 1
		for i = 1, 3 do accent[i] = math.floor(accent[i] + (255 - accent[i]) * 0.2) end
	end
	return { plate = plate, accent = accent, ratio = ratio(accent, plate) }
end

function ThemeScenes.known(setId)
	return type(setId) == "string" and DATA[setId] ~= nil
end

-- The set's own hue as a plate multiplier colour: its wash tint scaled so the brightest channel is 255 (hue kept, brightness not lost).
-- Warm text accents barely move a brown plate; this does (Harbor Lights turns blue, Meadow Picnic green). nil for classic or unknown.
function ThemeScenes.hueOf(setId)
	if not ThemeScenes.known(setId) or setId == ThemeScenes.DEFAULT then return nil end
	local t = DATA[setId].tint
	local top = math.max(t[1], t[2], t[3], 1)
	return { math.floor(t[1] * 255 / top + 0.5), math.floor(t[2] * 255 / top + 0.5), math.floor(t[3] * 255 / top + 0.5) }
end

ThemeScenes.COLLECTION_WALL_TINT = 0.3 -- Collection wall
ThemeScenes.RESULT_WASH_TINT = 0.25 -- Run Over and Victory room pictures

-- A light multiplier a painted picture wears for a set: white pulled `amount` (0..1) toward the set hue. nil for classic or unknown, so classic is untouched.
function ThemeScenes.washTint(setId, amount)
	local h = ThemeScenes.hueOf(setId)
	if not h then return nil end
	amount = math.max(0, math.min(1, amount or 0.3))
	return { math.floor(255 + (h[1] - 255) * amount + 0.5), math.floor(255 + (h[2] - 255) * amount + 0.5), math.floor(255 + (h[3] - 255) * amount + 0.5) }
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
