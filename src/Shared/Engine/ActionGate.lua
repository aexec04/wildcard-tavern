--[[
	ActionGate.lua
	A short cool-down for actions that move the run along without a new screen in between (Skip a round): a double
	click lands twice in one frame, and each call would be legal on its own, so the server must refuse the second.
	Pure Lua; the caller passes the time (os.clock()).

	  ActionGate.MIN_GAP                      seconds between two accepted calls
	  ActionGate.take(holder, key, now) -> true when the call may run (and stamps it), false when it is too soon
]]

local ActionGate = {}

ActionGate.MIN_GAP = 0.4

function ActionGate.take(holder, key, now)
	local last = holder[key]
	if last and now >= last and now - last < ActionGate.MIN_GAP then
		return false
	end
	holder[key] = now
	return true
end

return ActionGate
