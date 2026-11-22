--[[
	Shared/Engine/MusicPicker.lua
	The Music panel's rules: which soundtrack choices exist, which are free, which need the Music pack, and what the player hears.
	Pure Lua, no Roblox APIs. Tracks come from Engine/SoundIds.Music only (a track whose id is empty is not listed).

	MusicPicker.TRACKS                      list of { id, name, key, pack }: id is the saved musicTrack value, key the SoundIds.Music key
	                                        (nil for "auto": the normal music for each screen), pack = needs the Music pack
	MusicPicker.list(ownsPack)              the listed tracks with { owned, locked } for this player
	MusicPicker.effective(selected, owns)   the track id that really plays: the selection when it is listed and unlocked, else "auto"
	MusicPicker.buyButton(passId, owns)     { show, enabled, text } for the Get Music pack button (id 0 is "Coming soon", disabled)
	MusicPicker.ownsPack(ids)               true when the owned pass ids (the state's ownedGamePassIds) include the Music pack
	MusicPicker.assetFor(trackId)           the rbxassetid for a track, or nil for auto
]]

local SoundIds = require(script.Parent.SoundIds)

local M = {}

M.PACK_PASS_ID = "music_pack"

local ALL = {
	{ id = "auto", name = "Tavern Mix", key = nil, pack = false }, -- the default: a shuffle of the tavern tracks (Engine/MusicRotation), free
	{ id = "lantern_waltz", name = "Lantern Waltz", key = "lantern_waltz", pack = false },
	{ id = "midnight_fiddle", name = "Midnight Fiddle", key = "midnight_fiddle", pack = false },
	{ id = "harvest_jig", name = "Harvest Jig", key = "harvest_jig", pack = false },
	{ id = "dragons_breath_inn", name = "Dragon's Breath Inn", key = "dragons_breath_inn", pack = false },
	{ id = "dragon_hearth", name = "The Dragon's Hearth", key = "dragon_hearth", pack = false },
	{ id = "through_the_trees", name = "Through the Trees", key = "through_the_trees", pack = false },
	{ id = "would_have_followed", name = "I Would Have Followed", key = "would_have_followed", pack = false },
	{ id = "boss", name = "Boss Theme", key = "boss", pack = false },
	{ id = "victory_fanfare", name = "Victory Fanfare", key = "victory_fanfare", pack = false },
	{ id = "shop", name = "Counter Tune", key = "shop", pack = true }, -- the one older track kept for the Music pack
}

M.TRACKS = {}
for _, t in ipairs(ALL) do
	if t.key == nil or SoundIds.isValidId(SoundIds.Music[t.key]) then M.TRACKS[#M.TRACKS + 1] = t end
end

local BY_ID = {}
for _, t in ipairs(M.TRACKS) do BY_ID[t.id] = t end

function M.ownsPack(ids)
	if type(ids) ~= "table" then return false end
	for _, v in ipairs(ids) do if v == M.PACK_PASS_ID then return true end end
	return false
end

function M.list(ownsPack)
	local out = {}
	for i, t in ipairs(M.TRACKS) do
		out[i] = { id = t.id, name = t.name, key = t.key, pack = t.pack, owned = (not t.pack) or ownsPack == true, locked = t.pack and ownsPack ~= true }
	end
	return out
end

function M.effective(selected, ownsPack)
	local t = BY_ID[selected]
	if not t then return "auto" end
	if t.pack and ownsPack ~= true then return "auto" end
	return t.id
end

function M.buyButton(passId, ownsPack)
	if ownsPack == true then return { show = false, enabled = false, text = "Music pack owned" } end
	if (tonumber(passId) or 0) <= 0 then return { show = true, enabled = false, text = "Coming soon" } end
	return { show = true, enabled = true, text = "Get Music pack" }
end

-- The Music shop section: PLACEHOLDER tracks. They stay locked and unplayable until a real SoundIds.Music entry exists for their key
-- (nothing plays from these rows today; the names are stand-ins for the real pack).
M.SHOP_TITLE = "Music pack"
M.SHOP_LINE = "More tunes for your tavern"
M.PACK_LINE_H = 24 -- the second line under the title: what the pack is and its price or Owned state

-- What you get and what it costs, one short line (no random odds, no power): "Owned" once the pass is owned, "Coming soon" while the pass id
-- is 0, otherwise the price is read at the Roblox checkout. 36 characters or less so it fits the 360 px panel at 16 px.
function M.packLine(passId, ownsPack)
	if ownsPack == true then return "Sound only. Owned, enjoy!" end
	if (tonumber(passId) or 0) <= 0 then return "Sound only. Coming soon." end
	return "Sound only. Price at checkout."
end
M.SHOP_TRACKS = {} -- empty until the Music pack has real tracks; the section keeps its button for them

-- The three shop rows for this player: { id, name, locked, playable, tag } where tag is the small right-hand word
-- ("" when playable, "Coming soon" when owned but no real id yet, "Locked" when the pack is not owned).
function M.shopRows(ownsPack)
	local out = {}
	for i, t in ipairs(M.SHOP_TRACKS) do
		local real = SoundIds.isValidId(SoundIds.Music[t.key])
		local owned = ownsPack == true
		local playable = owned and real
		local tag = "Music pack" -- the unlock hint: the pack opens these rows
		if playable then tag = "" elseif owned then tag = "Coming soon" end
		out[i] = { id = t.id, name = t.name, key = t.key, locked = not playable, playable = playable, tag = tag, placeholder = t.placeholder == true }
	end
	return out
end

-- Panel rectangles for a viewport (pure, tested at 1920x957, 1280x720, 1024x768, 800x450). The panel is at most 360 wide and the
-- viewport height minus a 16 px margin; the body between the title bar and the panel bottom scrolls when it does not fit.
-- Returns { panel = {x,y,w,h}, closeX = {x,y,w,h} (screen coords), body = {h = visible, content = full height}, contentH }.
M.ROW_H, M.ROW_GAP, M.TITLE_H = 44, 8, 84 -- title bar 56 plus a 28 px Now playing line
function M.shopHeight() -- plate pad, title, line, rows (each with its gap), button, pad
	return 12 + 28 + 2 + 22 + M.PACK_LINE_H + 6 + #M.SHOP_TRACKS * (M.ROW_H - 4 + M.ROW_GAP) + 44 + 12
end
function M.contentHeight()
	return #M.TRACKS * (M.ROW_H + M.ROW_GAP) + M.shopHeight() + 8
end

function M.layout(vw, vh)
	local w = math.min(360, vw - 16)
	local contentH = M.contentHeight()
	local h = math.min(M.TITLE_H + contentH, vh - 16)
	local x, y = math.floor((vw - w) / 2), math.floor((vh - h) / 2)
	local cx = 36 -- X button size
	return {
		panel = { x = x, y = y, w = w, h = h },
		closeX = { x = x + w - cx - 8, y = y + 8, w = cx, h = cx },
		body = { h = h - M.TITLE_H - 8, content = contentH },
		contentH = contentH,
	}
end

-- The Now playing line: names the track that really plays (auto is the Tavern Mix).
function M.nowPlaying(selected, ownsPack)
	local t = BY_ID[M.effective(selected, ownsPack)] or BY_ID.auto
	return "Now playing: " .. (t and t.name or "Tavern Mix")
end

function M.assetFor(trackId)
	local t = BY_ID[trackId]
	if not t or not t.key then return nil end
	return SoundIds.Music[t.key]
end

return M
