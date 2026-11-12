--[[
	Shared/Engine/InputLock.lua
	Pure model of "while any overlay is open, the gameplay hit areas underneath are disabled" (tested).
	The client wraps it (Client/InputGuard.lua): overlays report open/closed, gameplay widgets register
	a setter, and every change re-applies the setters.

	  local lock = InputLock.new()
	  lock:setOpen(id, bool)      an overlay opened / closed
	  lock:isLocked()             true while at least one overlay is open
	  lock:guard(setFn)           setFn(interactable: bool) is called now and on every change; returns an unguard fn
]]

local InputLock = {}
InputLock.__index = InputLock

function InputLock.new()
	return setmetatable({ open = {}, count = 0, setters = {}, nextId = 0 }, InputLock)
end

function InputLock:isLocked()
	return self.count > 0
end

function InputLock:_apply()
	local interactable = not self:isLocked()
	for _, fn in pairs(self.setters) do
		fn(interactable)
	end
end

function InputLock:setOpen(id, isOpen)
	isOpen = isOpen == true
	local was = self.open[id] == true
	if was == isOpen then return end
	self.open[id] = isOpen or nil
	self.count = self.count + (isOpen and 1 or -1)
	self:_apply()
end

function InputLock:guard(setFn)
	self.nextId = self.nextId + 1
	local key = self.nextId
	self.setters[key] = setFn
	setFn(not self:isLocked())
	return function()
		self.setters[key] = nil
	end
end

-- Pure rule: an overlay counts as open only when it and every ancestor up to the ScreenGui is visible.
-- ancestors = list of Visible booleans (nil entries are ignored, e.g. non-GuiObject ancestors).
function InputLock.effectivelyVisible(selfVisible, ancestors)
	if selfVisible ~= true then return false end
	for _, v in pairs(ancestors or {}) do
		if v == false then return false end
	end
	return true
end

-- A backdrop whose last popup action was popOut and which is STILL visible a second later is stuck: its fade-out never finished, and while
-- it stays up it swallows clicks and locks the gameplay buttons (InputGuard). Client/InputGuard checks this once a second.
InputLock.STUCK_AFTER = 1
function InputLock.isStuck(popState, popOutAt, visible, now)
	return visible == true and popState == "out" and type(popOutAt) == "number" and (now - popOutAt) > InputLock.STUCK_AFTER
end

return InputLock
