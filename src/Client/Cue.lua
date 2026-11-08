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

-- Cue.play("map_open") or Cue.play("hover", 0.8) (second argument scales the cue's own volume).
function Cue.play(name, scale)
	if impl then
		pcall(impl, name, scale)
	end
end

return Cue
