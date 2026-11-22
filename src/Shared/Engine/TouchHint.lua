--[[
	Engine/TouchHint.lua
	Tap-to-hint rules for touch screens (phones have no hover). Pure Lua, no Roblox APIs; Client/TouchHelp.lua drives it.

	  local h = TouchHint.new(3)
	  h:tap(target, now) -> "show"  first tap on a target (or after its hint timed out): show its hint
	                        "act"   second tap on the same target while its hint is up: perform the action
	  h:tapElsewhere()               a tap on anything else clears the hint
	  h:active(now) -> target|nil    the target whose hint should be showing right now
]]

local TouchHint = {}
TouchHint.__index = TouchHint

TouchHint.DURATION = 3 -- seconds a tapped hint stays up

function TouchHint.new(duration)
	return setmetatable({ duration = duration or TouchHint.DURATION, target = nil, shownAt = 0 }, TouchHint)
end

function TouchHint:active(now)
	if self.target ~= nil and now - self.shownAt < self.duration then return self.target end
	return nil
end

function TouchHint:tap(target, now)
	if self:active(now) == target then
		self.target = nil
		return "act"
	end
	self.target = target
	self.shownAt = now
	return "show"
end

function TouchHint:tapElsewhere()
	self.target = nil
end

return TouchHint
