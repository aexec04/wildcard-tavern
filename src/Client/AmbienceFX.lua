--[[
	Client/AmbienceFX.lua
	A very quiet looping tavern bed (SoundIds.Ambience.tavern, silent while the id is empty). Volume and pause come from
	Engine/Ambience: ducked while a hand is scored (PlayReveal.waiting), muted by the Mute and SFX settings, paused while the
	window is hidden. Set directly each second, no tweens, so Calm mode and Reduce motion are unaffected. M.start() is safe to
	call twice.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")
local Engine = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine")
local Ambience = require(Engine:WaitForChild("Ambience"))
local SoundIds = require(Engine:WaitForChild("SoundIds"))
local ClientSettings = require(script.Parent.ClientSettings)

local M = {}
local started, sound, focused = false, nil, true

local function scoring()
	local ok, v = pcall(function() return require(script.Parent.PlayReveal).waiting() end)
	return ok and v == true
end

function M.step()
	if not sound then return end
	local muted = ClientSettings.get("muted") == true
	if Ambience.shouldPlay(sound.SoundId, muted, focused) then
		sound.Volume = Ambience.volume(muted, ClientSettings.get("sfxVolume"), scoring(), focused)
		if not sound.IsPlaying then sound:Play() end
	elseif sound.IsPlaying then
		sound:Pause()
	end
end

function M.start()
	if started then return end
	local id = SoundIds.Ambience and SoundIds.Ambience.tavern and SoundIds.Ambience.tavern.id or ""
	if not SoundIds.isValidId(id) then return end -- no id picked yet: stay silent
	started = true
	sound = Instance.new("Sound")
	sound.Name = "TavernAmbience"
	sound.SoundId = id
	sound.Looped = true
	sound.Volume = 0
	sound.Parent = SoundService
	UserInputService.WindowFocused:Connect(function() focused = true end)
	UserInputService.WindowFocusReleased:Connect(function() focused = false end)
	task.spawn(function()
		while sound and sound.Parent do
			pcall(M.step)
			task.wait(1)
		end
	end)
end

return M
