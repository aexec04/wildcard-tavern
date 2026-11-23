-- MusicMixFX: picks the music bed for the screen in `state` (Engine/MusicMix has every rule).
-- The bed is Client/Sound's one background Sound (stepped crossfade, per screen gain): exactly one music loop plays at a time.
-- No tweens in any mode: Calm mode and Reduce motion fade in fewer, bigger steps. The Music slider and Mute always scale it.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Engine = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine")
local MusicMix = require(Engine:WaitForChild("MusicMix"))
local SoundIds = require(Engine:WaitForChild("SoundIds"))

local M = {}

-- No second music loop: the tension moment is carried by the one bed (a second looping track played over the bed doubled the music).

-- called on every state push (cheap)
function M.update(state, sound, inMenu)
	local screen = MusicMix.screenOf(state, inMenu)
	local regionKey
	if screen == "table" or screen == "map" then
		pcall(function()
			local route = state.worldRoute
			local regionId = route and #route > 0 and require(Engine:WaitForChild("WorldMap")).regionOf(route[#route])
			regionKey = SoundIds.regionMusicKey(regionId)
		end)
	end
	local bed = MusicMix.bedFor(screen, regionKey)
	sound.setMusicTrack(bed.key, bed.gain)
end

return M
