--[[
	Engine/GearMenu.lua
	The ONE Settings icon (the round gear at the top left, right of the speaker) on the table, the Counter and the Night map, and the toggle menu it drops down. Pure and
	tested; Client/GearMenu.lua draws it with TavernKit and calls the real settings and pause backends (nothing is duplicated).

	gearRect(w, h)            -> { x, y, w, h }   the round gear at the top left, right of the speaker, under Roblox's own top bar
	menuRect(w, h)            -> { x, y, w, h, scroll }   about 280 px wide, hangs under the gear at the top left, always fully on screen (scrolls when short)
	rowRects(menu)            -> list of { id, x, y, w, h }   44 px tall rows inside the menu, relative to the menu
	ROWS                      -> { { id, kind = "toggle" | "action", label } ... } in display order
	view(settings)            -> { [id] = { label, on, state } }   state is the word "On" or "Off" for a toggle, so colour is never the only signal
	writes(id, settings)      -> { key = value } for a toggle row (what the real setting becomes), empty for an action
	visibleOn(flags)          -> true on the table, the Counter and the Night map, never on the Menu or a Run Over plate
	duration(calm)            -> seconds the drop down takes (0 in Calm mode and Reduce motion, 0.15 otherwise)
]]

local Responsive = require(script.Parent:WaitForChild("ResponsiveLayout"))
local Quick = require(script.Parent:WaitForChild("Gameplay2Quick"))

local M = {}

M.SIZE = 44
M.MENU_W = 280
M.ROW_H = 44
M.ROW_GAP = 4
M.PAD = 8
M.MUSIC_DEFAULT = 0.35
M.SLIDE = 0.15

M.ROWS = {
	{ id = "sound", kind = "toggle", label = "Sound" },
	{ id = "music", kind = "toggle", label = "Music" },
	{ id = "tracks", kind = "action", label = "Music tracks" },
	{ id = "calm", kind = "toggle", label = "Calm mode" },
	{ id = "reduceMotion", kind = "toggle", label = "Reduce motion" },
	{ id = "hints", kind = "toggle", label = "Hints" },
	{ id = "settings", kind = "action", label = "Settings" },
	{ id = "howTo", kind = "action", label = "How to play" },
	{ id = "quit", kind = "action", label = "Quit to Tavern" },
}

local function round(n) return math.floor(n + 0.5) end

function M.margin(w) return math.max(8, round(0.012 * w)) end

-- the table's quick strip floor under Roblox's top bar
local function topY(w) return math.max(Responsive.TOPBAR_H, M.margin(w)) end

-- The ONE settings button is the round gear at the top left, right of the speaker; the menu drops down from it. There is no gear top right.
function M.gearRect(w, h)
	return M.quickRects(w, h).pause
end

-- the speaker (Sound toggle) and Pause round buttons sit in a row at the TOP LEFT (the reference puts them left of the Target plate), same size
-- and top as the gear, 8 px apart; they do what the menu rows do. The consumables tray starts one row lower (Gameplay2Layout, M.SIZE + QUICK_GAP).
M.QUICK_GAP = 12
-- reference: the two round gold buttons are about 95 px at 1672 wide, so 109 px at 1920; they scale with the width and never go under 44 px
M.QUICK_REF, M.QUICK_REF_W = 109, 1920
function M.quickSize(w)
	if (tonumber(w) or 0) < 1200 then return M.SIZE end -- compact windows keep the 44 px buttons (the tray needs the room)
	return math.max(M.SIZE, math.min(M.QUICK_REF, round((tonumber(w) or M.QUICK_REF_W) * M.QUICK_REF / M.QUICK_REF_W)))
end
function M.quickRects(w, h)
	local gy = topY(w)
	local q = M.quickSize(w)
	if q > M.SIZE then
		-- reference (1672 x 941, x 1.148): centres x 115 and 245 and the top of the top bar (y about 15 at 957), so they never sit over the candle
		local x0 = round(61 / M.QUICK_REF_W * w)
		local gap = round(21 / M.QUICK_REF_W * w)
		local y = math.max(4, round(0.016 * h))
		return { speaker = { x = x0, y = y, w = q, h = q }, pause = { x = x0 + q + gap, y = y, w = q, h = q } }
	end
	local x0 = M.margin(w)
	local speaker = { x = x0, y = gy, w = q, h = q }
	local pause = { x = x0 + q + M.QUICK_GAP, y = gy, w = q, h = q }
	return { speaker = speaker, pause = pause }
end

function M.contentHeight()
	local n = #M.ROWS
	return n * M.ROW_H + (n - 1) * M.ROW_GAP + 2 * M.PAD
end

function M.menuRect(w, h)
	local g = M.gearRect(w, h)
	local mw = math.min(M.MENU_W, w - 2 * M.margin(w))
	local y = g.y + g.h + 4
	local full = M.contentHeight()
	local mh = math.min(full, h - y - M.margin(w))
	local x = math.max(M.margin(w), math.min(g.x, w - M.margin(w) - mw)) -- hangs under the gear, left edges level, always on screen
	return { x = x, y = y, w = mw, h = math.max(M.ROW_H + 2 * M.PAD, mh), scroll = mh < full, contentH = full }
end

function M.rowRects(menu)
	local out = {}
	for i, row in ipairs(M.ROWS) do
		out[i] = { id = row.id, x = M.PAD, y = M.PAD + (i - 1) * (M.ROW_H + M.ROW_GAP), w = menu.w - 2 * M.PAD, h = M.ROW_H }
	end
	return out
end

local function isOn(v) return v == true end

function M.musicOn(s) return (tonumber(s.musicVolume) or 0) > 0 end
function M.soundOn(s) return (tonumber(s.sfxVolume) or 0) > 0 and not isOn(s.muted) end

function M.view(settings)
	settings = settings or {}
	local on = {
		sound = M.soundOn(settings),
		music = M.musicOn(settings) and not isOn(settings.muted),
		calm = Quick.calmOn(settings),
		reduceMotion = isOn(settings.reduceMotion),
		hints = settings.roundHints ~= false,
	}
	local out = {}
	for _, row in ipairs(M.ROWS) do
		if row.kind == "toggle" then
			out[row.id] = { label = row.label, on = on[row.id], state = on[row.id] and "On" or "Off" }
		else
			out[row.id] = { label = row.label }
		end
	end
	return out
end

function M.writes(id, settings)
	settings = settings or {}
	if id == "sound" then
		-- Sound is the master switch: the mute flag silences effects, music and the ambience bed together (Client/Sound, MusicMixFX,
		-- AmbienceFX all read it); the saved volumes stay so turning it back on restores the mix
		local want = not M.soundOn(settings)
		if want then return { muted = false, sfxVolume = (tonumber(settings.sfxVolume) or 0) > 0 and settings.sfxVolume or 1 } end
		return { muted = true }
	elseif id == "music" then
		local want = not (M.musicOn(settings) and not isOn(settings.muted))
		return { musicVolume = want and M.MUSIC_DEFAULT or 0, muted = false }
	elseif id == "calm" then
		return Quick.calmWrites(settings)
	elseif id == "reduceMotion" then
		return { reduceMotion = not isOn(settings.reduceMotion) }
	elseif id == "hints" then
		return { roundHints = not (settings.roundHints ~= false) }
	end
	return {}
end

-- flags: { root = bool, table = bool, counter = bool, map = bool, popup = bool }
function M.visibleOn(flags)
	flags = flags or {}
	if flags.popup then return false end
	return flags.root == true and (flags.table == true or flags.counter == true or flags.map == true)
end

function M.duration(calm)
	return calm and 0 or M.SLIDE
end

return M
