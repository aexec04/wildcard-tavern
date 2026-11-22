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
M.LINE = "One shared seed for every player. A new Daily starts at 00:00 UTC."
M.BUTTON_TEXT = "Play Daily"
M.NOTE_H = 110 -- title, two text lines, then the button, all inside the painted plate
M.BUTTON = { w = 124, h = 34 }
M.ORDER = 1

return M
