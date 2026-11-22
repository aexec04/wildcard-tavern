--[[
	Shared/Engine/ReplayFlow.lua
	The rules and words of the "Replay the tutorial?" confirm in Settings (Client/ReplayConfirm draws it). Replaying only walks through the
	short tutorial again: it never touches progress, Tips, unlocks, Patrons, Card Sets or the saved tutorial flag, so the words say so.
	One confirm per request: a second tap cannot start two replays. Same state machine as QuitFlow.

	  ReplayFlow.new() / request(s) / cancel(s) / confirm(s) / finish(s)   (see QuitFlow)
]]

local QuitFlow = require(script.Parent.QuitFlow)

local M = {}

M.TITLE = "Replay the tutorial?"
M.MESSAGE = "You will see the short tutorial again. Your progress, Tips and unlocks stay safe."
M.YES = "Replay"
M.NO = "Not now"

M.new = QuitFlow.new
M.request = QuitFlow.request
M.cancel = QuitFlow.cancel
M.confirm = QuitFlow.confirm
M.finish = QuitFlow.finish

return M
