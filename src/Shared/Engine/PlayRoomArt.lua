--[[
	Shared/Engine/PlayRoomArt.lua
	Per Card Set play rooms. Each of 14 sets has a painted room (`play_room_<setId>_bg`, an opaque 1536x1024 room with an oval table) and
	a matching wood front (`play_room_<setId>_front`, transparent above the table, with the hand groove and the deck recess where
	play_table_front_c has them). Classic Tavern keeps play_table_bg_b + play_table_front_c. Pure Lua, tested in EngineTests ("PlayRoomArt").

	PlayRoomArt.roomArt(setId, art)   { bg, front, layout, room } the art keys to draw for the set. `art` is the generated PlaySceneArt map:
	    a set whose pair is not recorded (or an unknown set) gets the classic pair, `room` = nil and `layout` = nil.
	PlayRoomArt.keys(setId)           the two art keys of a set's room, whether or not they are recorded
	PlayRoomArt.SETS                  per set: dy = how many picture px the groove, recess and wooden front sit below play_table_front_c's
	                                  (measured, see below), felt = the rect where played cards land when the room's oval differs
	PlayRoomArt.tint(accent)          { r, g, b } multiplier (0..255) that gives the left board, the plates and the Counter a low contrast
	                                  hint of the set accent; never darker than TINT_FLOOR so ink and cream text keep 4.5:1

	Measured on art-wip/play_scene/play_room_<set>_front.png against play_table_front_c.png (debug sheets debug_fronts_sheet_1 to 3 and
	debug_bgs_sheet_1 to 3): the top of the dark groove band (classic 754), a gradient correlation of the groove strip and of the deck
	recess, each compared to the classic picture; the three agree within 5 px, the value is their middle. The groove's x range and the
	recess's x position match the classic picture within 10 px for every set (the hand row is centred on the classic groove in every set).
]]

local PlayRoomArt = {}

PlayRoomArt.CLASSIC = { bg = "play_table_bg_b", front = "play_table_front_c" }
PlayRoomArt.PREFIX = "layout:" -- PlayTableLayout.SETS key of a room is PREFIX .. setId

PlayRoomArt.SETS = {
	winter_evening = { dy = -1, felt = { x = 120, y = 470, w = 1300, h = 215 } },
	festival_night = { dy = 0 },
	closing_time = { dy = -2 },
	golden_gala = { dy = -26, felt = { x = 140, y = 480, w = 1260, h = 205 } },
	meadow_picnic = { dy = 16 },
	riverside_evening = { dy = 0 },
	summit_camp = { dy = 0 },
	dune_market = { dy = -4, felt = { x = 140, y = 480, w = 1260, h = 205 } },
	marsh_lanterns = { dy = 33 },
	snowy_hearth = { dy = 0 },
	harbor_lights = { dy = 28 },
	tavern_feast = { dy = -2 },
	harvest_table = { dy = 17 },
	winter_table = { dy = 0 },
}
-- set ids in a stable order (for tests and the debug sheets)
PlayRoomArt.ORDER = { "winter_evening", "festival_night", "closing_time", "golden_gala", "meadow_picnic", "riverside_evening", "summit_camp",
	"dune_market", "marsh_lanterns", "snowy_hearth", "harbor_lights", "tavern_feast", "harvest_table", "winter_table" }

PlayRoomArt.TINT_AMOUNT = 0.14 -- share of the way from white to the accent
PlayRoomArt.TINT_FLOOR = 205 -- no channel of the multiplier goes below this

function PlayRoomArt.keys(setId)
	return { bg = "play_room_" .. tostring(setId) .. "_bg", front = "play_room_" .. tostring(setId) .. "_front" }
end

local function recorded(art, key)
	local v = art and art[key]
	return type(v) == "string" and v ~= "" and v ~= "rbxassetid://0"
end

-- The backdrop the play screen draws: a set with its own recorded room keeps it; everything else (Classic Tavern) gets the reference
-- tavern scene (`table_play_ref` in TableSceneArt) and falls back to the old classic picture when that id is missing.
-- Returns key, id (the rbxassetid string or nil).
PlayRoomArt.REF_BG = "table_play_ref"
function PlayRoomArt.backdrop(setId, art, tableArt)
	local room = PlayRoomArt.roomArt(setId, art)
	if room.room then return room.bg, art[room.bg] end
	if recorded(tableArt, PlayRoomArt.REF_BG) then return PlayRoomArt.REF_BG, tableArt[PlayRoomArt.REF_BG] end
	return room.bg, art and art[room.bg]
end

function PlayRoomArt.roomArt(setId, art)
	if type(setId) == "string" and PlayRoomArt.SETS[setId] then
		local k = PlayRoomArt.keys(setId)
		if art == nil or (recorded(art, k.bg) and recorded(art, k.front)) then
			return { bg = k.bg, front = k.front, layout = PlayRoomArt.PREFIX .. setId, room = setId }
		end
	end
	return { bg = PlayRoomArt.CLASSIC.bg, front = PlayRoomArt.CLASSIC.front, layout = nil, room = nil }
end

-- Which of Classic's table pieces (carved rim, felt inlay, bottom rail) draw over the backdrop. A set room that paints its own table
-- (`ownTable`: the backdrop is a set room, not the reference tavern) hides all three, since they would be a second table; Golden Gala's
-- backdrop was painted to the same footprint, so it keeps them. Used by Client/Gameplay2.
function PlayRoomArt.furniture(setId, ownTable)
	local show = not ownTable or setId == "golden_gala"
	return { rim = show, inlay = show, rail = show }
end

function PlayRoomArt.tint(accent)
	if type(accent) ~= "table" then return { 255, 255, 255 } end
	local out = {}
	for i = 1, 3 do
		local v = 255 + (accent[i] - 255) * PlayRoomArt.TINT_AMOUNT
		out[i] = math.max(PlayRoomArt.TINT_FLOOR, math.min(255, math.floor(v + 0.5)))
	end
	return out
end

return PlayRoomArt
