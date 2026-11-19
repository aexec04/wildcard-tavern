--[[
	Engine/GearMenu.lua
	The ONE Settings icon at the top right of the table, the Counter and the Night map, and the toggle menu it drops down. Pure and
	tested; Client/GearMenu.lua draws it with TavernKit and calls the real settings and pause backends (nothing is duplicated).

	gearRect(w, h)            -> { x, y, w, h }   44 px round button in the top right corner, under Roblox's own top bar
	menuRect(w, h)            -> { x, y, w, h, scroll }   about 280 px wide, hangs under the gear, always fully on screen (scrolls when short)
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
	{ id = "calm", kind = "toggle", label = "Calm mode" },
	{ id = "reduceMotion", kind = "toggle", label = "Reduce motion" },
	{ id = "hints", kind = "toggle", label = "Hints" },
	{ id = "pause", kind = "action", label = "Pause" },
	{ id = "howTo", kind = "action", label = "How to play" },
	{ id = "quit", kind = "action", label = "Quit to Tavern" },
}

local function round(n) return math.floor(n + 0.5) end

function M.margin(w) return math.max(8, round(0.012 * w)) end

function M.gearRect(w, h)
	local m = M.margin(w)
	local y = math.max(Responsive.TOPBAR_H, m) -- the table's quick strip used the same floor under Roblox's top bar
	return { x = w - m - M.SIZE, y = y, w = M.SIZE, h = M.SIZE }
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
	return { x = w - M.margin(w) - mw, y = y, w = mw, h = math.max(M.ROW_H + 2 * M.PAD, mh), scroll = mh < full, contentH = full }
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
		local want = not M.soundOn(settings)
		return { sfxVolume = want and 1 or 0, muted = false }
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
