--[[
	Shared/Engine/StageMotion.lua
	Pure motion math for the 2D stage (boss portrait and the player's avatar image), so it can be tested.
	Every function returns offsets in pixels / degrees for a time value; the caller applies them.

	  sway(t, phase, amp)        continuous idle sine (breathing + a slight lean), bounded by amp
	  hitShake(elapsed, k, dur)  decaying horizontal shake and tilt after a hit, 0 outside [0, dur]
	  hop(elapsed, height, dur)  one upward hop (pixels, positive = up), 0 outside [0, dur]
]]

local StageMotion = {}

StageMotion.SWAY_Y_SPEED = 1.6 -- radians per second
StageMotion.SWAY_ROT_SPEED = 1.1

-- Returns dx, dy, rot. dy is in screen pixels (negative = up). reduced = true gives (0, 0, 0).
function StageMotion.sway(t, phase, amp, reduced)
	if reduced then
		return 0, 0, 0
	end
	phase = phase or 0
	amp = amp or 3
	local dy = math.sin(t * StageMotion.SWAY_Y_SPEED + phase) * amp
	local dx = math.sin(t * 0.8 + phase * 1.7) * amp * 0.4
	local rot = math.sin(t * StageMotion.SWAY_ROT_SPEED + phase) * 0.6
	return dx, dy, rot
end

-- Returns dx (pixels), rot (degrees). strength 0..1.
function StageMotion.hitShake(elapsed, strength, duration)
	duration = duration or 0.35
	strength = math.max(0, math.min(1, strength or 0))
	if elapsed < 0 or elapsed >= duration or strength == 0 then
		return 0, 0
	end
	local left = 1 - elapsed / duration
	local env = left * left * strength
	return math.sin(elapsed * 62) * 7 * env, math.sin(elapsed * 47) * 4 * env
end

-- Returns pixels of lift (>= 0).
function StageMotion.hop(elapsed, height, duration)
	duration = duration or 0.32
	height = height or 14
	if elapsed < 0 or elapsed >= duration then
		return 0
	end
	return math.sin(math.pi * elapsed / duration) * height
end

return StageMotion
