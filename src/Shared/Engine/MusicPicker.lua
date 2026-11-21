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
	{ id = "auto", name = "Tavern Mix", key = nil, pack = false }, -- the default: the right tune for each screen, free
	{ id = "gameplay", name = "Card Table", key = "gameplay", pack = false },
	{ id = "shop", name = "Counter Tune", key = "shop", pack = true },
	{ id = "menu", name = "Tavern Doors", key = "menu", pack = true },
	{ id = "boss", name = "Boss Round", key = "boss", pack = true },
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

function M.assetFor(trackId)
	local t = BY_ID[trackId]
	if not t or not t.key then return nil end
	return SoundIds.Music[t.key]
end

return M
