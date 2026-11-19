--[[
	Cue.lua
	Tiny bridge so any client module can play a named cue (Engine/SoundIds) without a new dependency.
	The hub calls `Cue.set(SoundModule.playCue)` once after Sound.lua is built; until then (or if the
	cue has no id yet) `Cue.play` does nothing. Never throws.
]]

local Cue = {}

local impl = nil

function Cue.set(fn)
	impl = fn
end

-- The sound pass helpers (Client/Sound.lua): the coin cascade, a hand-type sting, a music duck and the Studio audition.
local extras = {}
function Cue.setExtras(t)
	extras = t or {}
end
function Cue.coinCascade(volume)
	if extras.coinCascade then pcall(extras.coinCascade, volume) end
end
function Cue.sting(handName)
	if extras.sting then
		local ok, tier = pcall(extras.sting, handName)
		return ok and tier or nil
	end
end
function Cue.duck()
	if extras.duck then pcall(extras.duck) end
end
function Cue.audition(name)
	if extras.audition then
		local ok, played = pcall(extras.audition, name)
		return ok and played == true
	end
	return false
end

-- Cue.play("map_open") or Cue.play("hover", 0.8) (second argument scales the cue's own volume, the third is a PlaybackSpeed).
function Cue.play(name, scale, speed)
	if impl then
		pcall(impl, name, scale, speed)
	end
end

return Cue
