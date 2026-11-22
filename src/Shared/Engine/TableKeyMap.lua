--[[
	Engine/TableKeyMap.lua
	The keyboard and gamepad map for the table (pure, tested). Client/TableKeys.lua listens to the devices and asks this
	file what a key means; the actions it names are the same ones the on-screen buttons run, so no new remote exists.

	action(device, keyName, ctx) -> { type = ... } or nil
	  device   "keyboard" | "gamepad"
	  keyName  an Enum.KeyCode name: "One".."Eight", "Space", "Return", "D", "X", "S", "Q", "Escape",
	           "DPadLeft", "DPadRight", "ButtonA", "ButtonX", "ButtonY", "ButtonB"
	  ctx      { tableActive, popupOpen, textBox } booleans
	Types: card (pos 1..8), play, discard, sort, patron, move (dir -1|1), toggle (the highlighted card), back.
	Nothing fires while a text box has focus. While a popup is open only "back" (gamepad B) answers; Escape on the keyboard
	belongs to PopupDismiss and is never mapped here. Nothing fires unless the table is active.

	nextHighlight(current, dir, count) -> the new highlighted position (1..count), nil when the hand is empty.
	hintLines() -> the lines How to play and Settings show.
]]

local M = {}

M.MAX_CARDS = 8

local NUMBERS = { One = 1, Two = 2, Three = 3, Four = 4, Five = 5, Six = 6, Seven = 7, Eight = 8 }

local KEYBOARD = { Space = "play", Return = "play", KeypadEnter = "play", D = "discard", X = "discard", S = "sort", R = "sort", Q = "patron" }
local GAMEPAD = { ButtonX = "play", ButtonY = "discard", ButtonA = "toggle", ButtonB = "back" }

function M.action(device, keyName, ctx)
	ctx = ctx or {}
	if ctx.textBox or type(keyName) ~= "string" then return nil end
	if device == "gamepad" then
		if keyName == "DPadLeft" or keyName == "DPadRight" then
			if ctx.popupOpen or not ctx.tableActive then return nil end
			return { type = "move", dir = keyName == "DPadLeft" and -1 or 1 }
		end
		local kind = GAMEPAD[keyName]
		if kind == "back" then
			return ctx.popupOpen and { type = "back" } or nil
		end
		if not kind or ctx.popupOpen or not ctx.tableActive then return nil end
		return { type = kind }
	end
	if device ~= "keyboard" or ctx.popupOpen or not ctx.tableActive then return nil end
	local n = NUMBERS[keyName]
	if n then return { type = "card", pos = n } end
	local kind = KEYBOARD[keyName]
	if kind == "sort" then return { type = "sort", mode = keyName == "R" and "rank" or "suit" } end -- R sorts by rank, S by suit
	return kind and { type = kind } or nil
end

-- Runs the mapped action through `handlers` (card(pos), play(), discard(), sort(), patron(), move(dir), toggle(), back()).
-- Returns true when a handler ran. A missing handler or a failing one never throws: a key can never break the table.
function M.dispatch(device, keyName, ctx, handlers)
	local act = M.action(device, keyName, ctx)
	if not act then return false end
	local fn = handlers and handlers[act.type]
	if type(fn) ~= "function" then return false end
	local arg = act.pos or act.dir or act.mode
	local ok = pcall(fn, arg)
	return ok
end

function M.nextHighlight(current, dir, count)
	count = math.floor(tonumber(count) or 0)
	if count < 1 then return nil end
	if type(current) ~= "number" or current < 1 or current > count then
		return dir < 0 and count or 1
	end
	return math.max(1, math.min(count, current + (dir < 0 and -1 or 1)))
end

function M.hintLines()
	return {
		"Keys: 1 to 8 pick a card, Space or Enter plays, D or X discards, R sorts by rank, S by suit, Q shows the Patron Power tip, Esc closes a popup.",
		"Gamepad: D-pad moves, A picks, X plays, Y discards, B goes back.",
	}
end

return M
