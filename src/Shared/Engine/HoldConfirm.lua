--[[
	Shared/Engine/HoldConfirm.lua
	Pure state machine for a "hold to confirm" button (tested). Cancel is the default: nothing happens
	unless the button is held for the full duration without being released.

	  local h = HoldConfirm.new(1.5)
	  h:press(now)        start holding
	  h:release(now)      let go early: progress resets, never confirms
	  h:progress(now)     0..1 (fill amount for the ring / bar)
	  h:update(now)       returns true exactly once, when the hold reaches the full time
	  h:reset()
]]

local HoldConfirm = {}
HoldConfirm.__index = HoldConfirm

function HoldConfirm.new(duration)
	return setmetatable({ duration = duration or 1.5, startedAt = nil, done = false }, HoldConfirm)
end

function HoldConfirm:press(now)
	if self.done then return end
	self.startedAt = now
end

function HoldConfirm:release(_now)
	self.startedAt = nil
end

function HoldConfirm:progress(now)
	if self.done then return 1 end
	if not self.startedAt then return 0 end
	return math.max(0, math.min(1, (now - self.startedAt) / self.duration))
end

function HoldConfirm:update(now)
	if self.done or not self.startedAt then return false end
	if now - self.startedAt >= self.duration then
		self.done = true
		self.startedAt = nil
		return true
	end
	return false
end

function HoldConfirm:reset()
	self.startedAt = nil
	self.done = false
end

return HoldConfirm
