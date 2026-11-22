--[[
	Engine/MenuDailyEntry.lua
	The Daily Challenge note on the Menu's Notice Board: its words and sizes, pure and tested (Client/MenuDailyEntry draws it).
	The note keeps the board's parchment look; its one button is the native TavernKit green plate. The Daily action row on the Quest
	Scroll stays, so the board may drop this note first when it is crowded (it has the highest layout order).

	TITLE, LINE, BUTTON      the three texts (no dashes, kid safe)
	NOTE_H                   the note's height, 124: taller than the other notes because the button sits under two text lines
	BUTTON                   { w, h } the green plate: 124 x 44
	tomorrowLine(login)      -> "Tomorrow: 40 XP" from Engine/LoginStreak.view data (state.login), nil with no streak yet
	ORDER                    layout order on the board: after news (-3), rank (-2), goal (-1) and the ticker (0)
]]

local M = {}

M.TITLE = "Daily Challenge"
M.LINE = "A new Daily starts every day at midnight UTC."
M.BUTTON_TEXT = "Play Daily"
M.NOTE_H = 124 -- title, two text lines, then a 44 px row with the tomorrow line and the button, all inside the painted plate
M.BUTTON = { w = 124, h = 44 }
M.TOMORROW_H = 44 -- the tomorrow line is a 44 px press target that opens the Daily Rewards panel
M.TOMORROW_MAX = 40
M.ORDER = 1

-- Tomorrow's slot on the 7 day ladder (the ladder loops, so after slot 7 comes slot 1). nil until the player has a streak.
function M.tomorrowLine(login)
	if type(login) ~= "table" or type(login.rewards) ~= "table" or #login.rewards == 0 then return nil end
	if (tonumber(login.streak) or 0) < 1 then return nil end
	local today = math.floor(tonumber(login.today) or 1)
	local nextRow
	for _, row in ipairs(login.rewards) do
		if row.day == (today % #login.rewards) + 1 then nextRow = row end
	end
	if not nextRow or type(nextRow.label) ~= "string" then return nil end
	local line = "Tomorrow: " .. nextRow.label
	if #line > M.TOMORROW_MAX then line = "Tomorrow: a new reward" end
	return line
end

return M
