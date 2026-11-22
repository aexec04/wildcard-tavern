--[[
	Shared/Engine/TwistPreview.lua
	The words of the small "Today's twist" popup that opens when the Daily twist plate is tapped (Client/TwistPopup draws it, set paper and
	ink come from Client/PopupSkin). Pure and tested, display only: the twist itself is picked by Engine/DailyModifiers.

	TwistPreview.view(dateKey) -> { title, name, icon, line, nextLine, close, empty }   never nil; a bad date key gives the safe EMPTY line
	TwistPreview.next(dateKey) -> the next day's twist definition, nil for a bad key
]]

local DailyModifiers = require(script.Parent.DailyModifiers)
local EmptyStates = require(script.Parent.EmptyStates)

local M = {}

M.TITLE = "Today's twist"
M.CLOSE = "Got it"
M.EMPTY = EmptyStates.screenLine("twistNone") -- one editable table for every empty or failed line

function M.next(dateKey)
	local day = DailyModifiers.dayNumber(dateKey)
	local defs = DailyModifiers.Definitions
	if not day then return nil end
	return defs[((day + 1) * 5) % #defs + 1]
end

function M.view(dateKey)
	local def = DailyModifiers.dayNumber(dateKey) and DailyModifiers.forDate(dateKey) or nil
	if not def then
		return { title = M.TITLE, name = "", icon = "", line = M.EMPTY, nextLine = "", close = M.CLOSE, empty = true }
	end
	local nxt = M.next(dateKey)
	return {
		title = M.TITLE,
		name = def.name,
		icon = def.icon,
		line = def.text,
		nextLine = nxt and ("Tomorrow: " .. nxt.name) or "",
		close = M.CLOSE,
		empty = false,
	}
end

return M
