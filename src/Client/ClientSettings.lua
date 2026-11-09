--[[
	Client/ClientSettings.lua
	The client's copy of the player's settings (PlayerProfile.SETTING_SPECS):
	volume, mute, animation speed, reduce shake, colorblind suits, confirm
	before discard. Plain module (not a deps factory), so any client module
	can require it and read the same values.

	- loadFromServer(settings): called on every StateUpdated. Applies the
	  saved values only the first time a real settings table arrives; after
	  that the client is the source of truth and the server just stores.
	- get(key) / set(key, value): set applies locally, tells listeners, and
	  sends SetSetting to the server (debounced so a slider drag sends one
	  save, not one per pixel).
	- onChanged(fn): fn(key, value) on every change, including keys the
	  initial load changes from their defaults.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PlayerProfile = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("PlayerProfile"))

local Accessibility = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("Accessibility"))

local ClientSettings = {}

local SAVE_DEBOUNCE = 0.4

local values = PlayerProfile.defaultSettings()
local listeners = {}
local loaded = false
local pendingSave = {} -- [key] = token, latest wins
local setSettingRemote = nil

local function notify(key, value)
	for _, fn in ipairs(listeners) do
		task.spawn(fn, key, value)
	end
end

local function sendToServer(key)
	local token = {}
	pendingSave[key] = token
	task.delay(SAVE_DEBOUNCE, function()
		if pendingSave[key] ~= token then
			return
		end
		pendingSave[key] = nil
		if not setSettingRemote then
			local remotes = ReplicatedStorage:FindFirstChild("Remotes")
			setSettingRemote = remotes and remotes:FindFirstChild("SetSetting")
		end
		if setSettingRemote then
			setSettingRemote:FireServer(key, values[key])
		end
	end)
end

-- Every module that skips loops, pulses and shake asks get("reduceShake"); that now also answers true under
-- Reduce Motion and Reduce Flashing (calm mode, Engine/Accessibility). The Settings panel shows the raw
-- switch through getRaw so the three toggles stay independent.
function ClientSettings.get(key)
	if key == "reduceShake" then
		return Accessibility.calm(values)
	end
	return values[key]
end

function ClientSettings.getRaw(key)
	return values[key]
end

-- Accessibility helpers (see Engine/Accessibility.lua).
function ClientSettings.flashesAllowed()
	return Accessibility.flashesAllowed(values)
end
function ClientSettings.motionAllowed()
	return Accessibility.motionAllowed(values)
end
function ClientSettings.particleCount(count)
	return Accessibility.particleCount(values, count)
end
function ClientSettings.holdSeconds()
	return Accessibility.holdSeconds(values)
end

function ClientSettings.isLoaded()
	return loaded
end

function ClientSettings.set(key, value)
	if PlayerProfile.SETTING_SPECS[key] == nil or values[key] == value then
		return
	end
	values[key] = value
	notify(key, value)
	if key == "reduceMotion" or key == "reduceFlashing" then
		notify("reduceShake", Accessibility.calm(values)) -- listeners of the old calm switch hear about it too
	end
	sendToServer(key)
end

function ClientSettings.onChanged(fn)
	table.insert(listeners, fn)
end

function ClientSettings.loadFromServer(settings)
	if loaded or type(settings) ~= "table" then
		return
	end
	loaded = true
	-- Run through migrate's checks so a bad payload can't break the client.
	local clean = PlayerProfile.migrate({ settings = settings }).settings
	for key, value in pairs(clean) do
		-- A setting the player already changed this session wins over the load.
		if pendingSave[key] == nil and values[key] ~= value then
			values[key] = value
			notify(key, value)
		end
	end
end

return ClientSettings
