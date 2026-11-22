--[[
	Engine/MenuDailyEntry.lua
	The Daily Challenge note on the Menu's Notice Board: its words and sizes, pure and tested (Client/MenuDailyEntry draws it).
	The note keeps the board's parchment look; its one button is the native TavernKit green plate. The Daily action row on the Quest
	Scroll stays, so the board may drop this note first when it is crowded (it has the highest layout order).

	TITLE, LINE, BUTTON      the three texts (no dashes, kid safe)
	NOTE_H                   the note's height, 110: taller than the other notes because the button sits under two text lines
	BUTTON                   { w, h } the green plate: 124 x 34
	ORDER                    layout order on the board: after news (-3), rank (-2), goal (-1) and the ticker (0)
]]

local M = {}

M.TITLE = "Daily Challenge"
M.LINE = "A new Daily starts every day at midnight UTC."
M.BUTTON_TEXT = "Play Daily"
M.NOTE_H = 110 -- title, two text lines, then the button, all inside the painted plate
M.BUTTON = { w = 124, h = 34 }
M.ORDER = 1

-- The note's line with today's twist (Engine/DailyModifiers): "Today: Golden Start. Start the run with 8 extra Tips."
-- Falls back to the plain line when the date key is not usable.
function M.lineFor(dateKey)
	local ok, DailyModifiers = pcall(require, script.Parent.DailyModifiers)
	if not ok or not DailyModifiers.dayNumber(dateKey) then
		return M.LINE
	end
	local def = DailyModifiers.forDate(dateKey)
	return "Today: " .. def.name .. ". " .. def.text
end

return M
