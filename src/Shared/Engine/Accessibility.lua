--[[
	Accessibility.lua
	The comfort options as pure rules (the client reads these through Client/ClientSettings and Client/AccessibilityFX).
	Settings (saved in PlayerProfile.settings, all off by default except the hold time):
	  reduceShake       no screen shake (existing)
	  reduceFlashing    no screen flashes or rapid pulses, fewer particles
	  reduceMotion      static backgrounds, no travel or walk-in animation, no looping idle motion
	  largerText        text 15 percent bigger where the label has room (never clipped)
	  colorblindSuits   every suit gets its own color and a corner letter (existing, Client/CardFace)
	  holdConfirmSeconds how long destructive buttons must be held (0.5 to 3, default 1.5)
	Scoring and the Fast animation speed are never touched. Pure Lua, no Roblox APIs.
]]

local Accessibility = {}

Accessibility.TEXT_SCALE = 1.15
Accessibility.PARTICLE_SCALE = 0.4 -- particle counts under Reduce Flashing
Accessibility.HOLD_MIN, Accessibility.HOLD_MAX, Accessibility.HOLD_DEFAULT = 0.5, 3, 1.5
Accessibility.HoldChoices = { 0.5, 1, 1.5, 2, 3 }

local function on(settings, key)
	return type(settings) == "table" and settings[key] == true
end

-- Calm mode: every loop, shake and idle pulse stays off. This is what the old "reduceShake" check means everywhere.
function Accessibility.calm(settings)
	return on(settings, "reduceShake") or on(settings, "reduceMotion") or on(settings, "reduceFlashing")
end

function Accessibility.flashesAllowed(settings)
	return not on(settings, "reduceFlashing")
end

-- Travel and walk-in animations and moving backgrounds.
function Accessibility.motionAllowed(settings)
	return not on(settings, "reduceMotion")
end

function Accessibility.particleCount(settings, count)
	count = math.max(0, math.floor(tonumber(count) or 0))
	if on(settings, "reduceFlashing") then
		return math.floor(count * Accessibility.PARTICLE_SCALE)
	end
	return count
end

function Accessibility.textScale(settings)
	return on(settings, "largerText") and Accessibility.TEXT_SCALE or 1
end

-- Larger Text for one label: the base size times the scale, but never taller than the label can hold
-- (fitHeight = its pixel height, nil or 0 when unknown) and never below the base size.
function Accessibility.scaledTextSize(base, scale, fitHeight)
	base = math.max(1, math.floor(tonumber(base) or 14))
	local target = math.floor(base * (scale or 1) + 0.5)
	if scale and scale > 1 and fitHeight and fitHeight > 0 then
		target = math.min(target, math.floor(fitHeight * 0.9))
	end
	return math.max(base, target)
end

-- The hold time for destructive buttons, clamped to its range.
function Accessibility.holdSeconds(settings)
	local v = type(settings) == "table" and tonumber(settings.holdConfirmSeconds) or nil
	if not v or v ~= v then
		return Accessibility.HOLD_DEFAULT
	end
	return math.max(Accessibility.HOLD_MIN, math.min(Accessibility.HOLD_MAX, v))
end

return Accessibility
