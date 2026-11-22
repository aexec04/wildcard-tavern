--[[
	Engine/HoverIntent.lua
	When a hover hint shows and hides, so tiny pointer moves or a lifting button cannot make it flicker. Pure, tested.

	new(showAfter, hideAfter) -> ctl      seconds the pointer must rest before the hint shows, and stay away before it hides
	ctl:enter(now), ctl:leave(now)        pointer events (now = any steady clock in seconds)
	ctl:poll(now) -> shown                the answer at `now`; ctl.shown keeps the last one
]]

local M = {}
M.__index = M

function M.new(showAfter, hideAfter)
	return setmetatable({ showAfter = showAfter or 0.15, hideAfter = hideAfter or 0.2, inside = false, shown = false, since = 0 }, M)
end

function M:enter(now)
	if not self.inside then self.inside = true; self.since = now end
end

function M:leave(now)
	if self.inside then self.inside = false; self.since = now end
end

function M:poll(now)
	if not self.shown and self.inside and now - self.since >= self.showAfter then
		self.shown = true
	elseif self.shown and not self.inside and now - self.since >= self.hideAfter then
		self.shown = false
	end
	return self.shown
end

return M
