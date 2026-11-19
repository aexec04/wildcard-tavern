--[[
	Shared/Engine/FriendlyErrors.lua
	Calm, plain words for things that go wrong (a failed save, a rejected action, a lost connection, a stuck screen) and the
	rules for the small painted toast that shows them (Client/FriendlyErrorFX). The player never sees a raw error string or a
	stack trace: anything unknown reads as the generic line. Every line is under 80 characters of plain ASCII.

	FriendlyErrors.message(kind) -> text            unknown kinds read as "generic"
	FriendlyErrors.kindOf(raw) -> kind              maps a raw error string to a kind (the raw text is never shown)
	FriendlyErrors.retryable(kind) -> bool          true when a Try again button makes sense
	FriendlyErrors.shouldShow(kind, lastShownAt, now) -> bool   the same kind is not repeated while its toast is up
	FriendlyErrors.rect(w, h) -> { x, y, w, h }     the toast, centred under the Round banner, clear of the HUD, hand and buttons
]]

local Layout = require(script.Parent:WaitForChild("ConceptTLayout"))

local M = {}

M.HOLD = 3 -- seconds a toast stays
M.HEIGHT = 52
M.MAX_WIDTH = 440
M.BUTTON = { w = 108, h = 44 } -- Try again

M.MESSAGES = {
	save = "Your progress could not be saved. We will keep trying.",
	rejected = "That did not go through. Please try again.",
	offline = "Connection lost. Check your internet and try again.",
	stuck = "That took too long, so we reset the screen.",
	busy = "One moment, the tavern is catching up.",
	generic = "Something went wrong. Please try again.",
}

M.RETRY = { rejected = true, offline = true, generic = true }

function M.message(kind)
	return M.MESSAGES[kind] or M.MESSAGES.generic
end

function M.retryable(kind)
	return M.RETRY[kind] == true
end

function M.kindOf(raw)
	local s = string.lower(tostring(raw or ""))
	if s:find("datastore", 1, true) or s:find("save", 1, true) or s:find("profile", 1, true) then return "save" end
	if s:find("timeout", 1, true) or s:find("timed out", 1, true) or s:find("network", 1, true)
		or s:find("connection", 1, true) or s:find("offline", 1, true) or s:find("http", 1, true) then
		return "offline"
	end
	if s:find("reject", 1, true) or s:find("invalid", 1, true) or s:find("not allowed", 1, true) then return "rejected" end
	return "generic"
end

function M.shouldShow(kind, lastShownAt, now)
	if type(lastShownAt) ~= "number" then return true end
	return (now - lastShownAt) >= M.HOLD
end

-- the toast sits between the Round banner and the Patron row, centred in the 3:2 frame, so it never covers the HUD pills,
-- the gear, the hand, Play Hand, Discard or the deck
function M.rect(w, h)
	local r, f = Layout.rectsIn(w, h)
	local width = math.min(M.MAX_WIDTH, math.floor(f.w * 0.5))
	return {
		x = f.x + math.floor((f.w - width) / 2),
		y = r.round.y + r.round.h + 4,
		w = width,
		h = M.HEIGHT,
	}
end

return M
