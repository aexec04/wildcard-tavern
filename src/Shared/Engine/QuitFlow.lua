--[[
	Shared/Engine/QuitFlow.lua
	The rules of "Quit to Tavern" (tested; Client/QuitConfirm draws it). Quitting only returns to the Menu: the run stays saved on the
	server and the Menu offers to continue it, so the confirmation is calm (a plain Stay or Quit choice, no hold) and says so.

	  QuitFlow.new()            -> state
	  QuitFlow.request(s)       -> true when the confirm should open; false while it is already open or a quit is under way
	  QuitFlow.cancel(s)        -> closes the confirm (Escape, Stay, a click on the dark area)
	  QuitFlow.confirm(s)       -> true exactly once per request: a double click cannot quit twice
	  QuitFlow.finish(s)        -> the quit is done (the Menu is showing), a new request may open
	  QuitFlow.canOpen(blocked) -> false while another popup or the travel transition is on top, so nothing opens behind a modal
]]

local M = {}

M.TITLE = "Quit to the Tavern?"
M.MESSAGE = "Your run is saved. You can pick it up again from the Menu."
M.MESSAGE_NO_RUN = "Back to the Menu. You can start a new run any time."
M.STAY = "Stay"
M.QUIT = "Quit to Tavern"

function M.new()
	return { open = false, quitting = false }
end

function M.message(hasRun)
	if hasRun == false then return M.MESSAGE_NO_RUN end
	return M.MESSAGE
end

function M.request(s)
	if s.open or s.quitting then return false end
	s.open = true
	return true
end

function M.cancel(s)
	s.open = false
end

function M.confirm(s)
	if not s.open or s.quitting then return false end
	s.open = false
	s.quitting = true
	return true
end

function M.finish(s)
	s.quitting = false
end

function M.canOpen(blocked)
	return blocked ~= true
end

return M
