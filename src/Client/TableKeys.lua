--[[
	Client/TableKeys.lua
	Keyboard and gamepad controls for the table. What a key means lives in Engine/TableKeyMap (tested); this file listens to
	UserInputService.InputBegan (keyboard and Gamepad1), and runs the SAME functions the on-screen buttons run, so the
	server sees the same PlayHand / Discard remotes it already validates. Nothing new is sent.

	The hub (init.client.lua) fills TableKeys.actions once its handlers exist (no new hub locals):
	  isActive()        true while the table takes card actions (a run is on screen, not Round Select or the Shop)
	  popupOpen()       true while any overlay or popup is up (InputGuard's lock)
	  handCount()       cards in the hand
	  pick(pos)         toggle the card at on-screen position pos
	  highlight(pos)    show the gamepad highlight on position pos (nil clears it)
	  play(), discard(), sort(), patron(), back()
	Keys never fire while a TextBox has focus. Escape stays with PopupDismiss.
]]

local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Map = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("TableKeyMap"))

local M = { actions = {} }
local installed = false
local cursor = nil -- gamepad highlight position

local function call(name, ...)
	local fn = M.actions[name]
	if fn then return fn(...) end
end

local function context()
	return {
		tableActive = call("isActive") == true,
		popupOpen = call("popupOpen") == true,
		textBox = UserInputService:GetFocusedTextBox() ~= nil,
	}
end

local function handlers()
	return {
		card = function(pos) call("pick", pos) end,
		play = function() call("play") end,
		discard = function() call("discard") end,
		sort = function(mode) call("sort", mode) end,
		patron = function() call("patron") end,
		back = function() call("back") end,
		move = function(dir)
			cursor = Map.nextHighlight(cursor, dir, call("handCount") or 0)
			call("highlight", cursor)
		end,
		toggle = function()
			local n = call("handCount") or 0
			if cursor and cursor >= 1 and cursor <= n then call("pick", cursor) end
		end,
	}
end

function M.handle(input)
	local device = input.UserInputType == Enum.UserInputType.Keyboard and "keyboard"
		or input.UserInputType == Enum.UserInputType.Gamepad1 and "gamepad" or nil
	if not device then return false end
	return Map.dispatch(device, input.KeyCode.Name, context(), handlers())
end

function M.install()
	if installed then return end
	installed = true
	UserInputService.InputBegan:Connect(function(input, processed)
		-- processed is true for GUI-consumed input (a text box, a pressed button); gamepad A on a focused button is also processed
		if processed and input.UserInputType ~= Enum.UserInputType.Gamepad1 then return end
		M.handle(input)
	end)
end

return M
