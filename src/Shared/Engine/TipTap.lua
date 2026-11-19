--[[
	Shared/Engine/TipTap.lua
	Pure rules (tested) for the Patron tooltip on touch: a tap on a Patron card opens its plate, a tap on the same card again or
	anywhere else closes it, and a long press opens it and leaves it open (lifting the finger no longer closes it). Mouse hover is
	unchanged: it opens on enter and closes on leave. Client/PatronRow feeds it taps and draws the result.

	TipTap.new() -> state { open = nil | seat }
	TipTap.tapCard(state, seat) -> "open" | "close"     (sets state.open)
	TipTap.tapAway(state, x, y, rect) -> true when the tap closed an open plate (rect = the open card's { x, y, w, h })
	TipTap.longPress(state, seat) -> "open"
	TipTap.isTap(dist, held) -> true for a short press that barely moved (the same numbers as TouchGestures)
]]

local TG = require(script.Parent:WaitForChild("TouchGestures"))

local M = {}

function M.new() return { open = nil } end

function M.isTap(dist, held)
	return TG.classify(dist, held, true) == "tap"
end

function M.tapCard(state, seat)
	if state.open == seat then
		state.open = nil
		return "close"
	end
	state.open = seat
	return "open"
end

function M.longPress(state, seat)
	state.open = seat
	return "open"
end

local function inside(rect, x, y, slack)
	return x >= rect.x - slack and y >= rect.y - slack and x <= rect.x + rect.w + slack and y <= rect.y + rect.h + slack
end

function M.tapAway(state, x, y, rect)
	if not state.open then return false end
	if rect and inside(rect, x, y, TG.SLACK) then return false end -- on the card itself: tapCard decides
	state.open = nil
	return true
end

return M
