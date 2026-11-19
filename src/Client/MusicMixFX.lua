-- MusicMixFX: picks the music bed for the screen in `state` and runs the tension layer (Engine/MusicMix has every rule).
-- The bed is Client/Sound's one background Sound (stepped crossfade, per screen gain); the tension layer is a second looping Sound
-- that fades in by volume steps on the last hand of a round with the score under half the Target. No tweens in any mode: Calm mode
-- and Reduce motion fade in fewer, bigger steps. The Music slider and Mute always scale it.
local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Engine = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine")
local MusicMix = require(Engine:WaitForChild("MusicMix"))
local SoundIds = require(Engine:WaitForChild("SoundIds"))
local ClientSettings = require(script.Parent.ClientSettings)

local M = {}

local layer, level, token = nil, 0, 0 -- the tension Sound, its current fraction (0 to 1), a fade id

local function calm() return ClientSettings.get("reduceMotion") == true end

local function applyVolume()
	if not layer then return end
	local v = MusicMix.volume(ClientSettings.get("musicVolume"), ClientSettings.get("muted") == true, MusicMix.tensionGain("table"), level)
	layer.Volume = v
	if v <= 0 then
		if layer.IsPlaying then layer:Stop() end
	elseif not layer.IsPlaying then
		layer:Play()
	end
end

local function fadeTo(target)
	if not layer or math.abs(level - target) < MusicMix.MIN_CLEAR_STEP then return end
	token += 1
	local mine, from, isCalm = token, level, calm()
	task.spawn(function()
		local list = MusicMix.fade(isCalm)
		local dt = MusicMix.stepTime(isCalm)
		for _, pair in ipairs(list) do
			if mine ~= token then return end
			level = from + (target - from) * (target > from and pair[2] or 1 - pair[1])
			applyVolume()
			task.wait(dt)
		end
	end)
end

local function ensureLayer()
	if layer then return layer end
	local id = SoundIds.Music.boss
	if not SoundIds.isValidId(id) then return nil end -- an existing id only; none, no layer
	layer = Instance.new("Sound")
	layer.Name = "TensionLayer"
	layer.SoundId = id
	layer.Looped = true
	layer.Volume = 0
	layer.Parent = SoundService
	ClientSettings.onChanged(function(key)
		if key == "musicVolume" or key == "muted" then applyVolume() end
	end)
	return layer
end

-- called on every state push (cheap): bed first, then the tension layer
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
	local wantTension = MusicMix.tensionGain(screen) > 0 and MusicMix.tension(state)
	if wantTension and not ensureLayer() then wantTension = false end
	if wantTension or layer then fadeTo(wantTension and 1 or 0) end
end

return M
