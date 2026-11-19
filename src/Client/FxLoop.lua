--[[
	Client/FxLoop.lua
	The one Heartbeat for every looping effect (rules and tests in Engine/FxLoop). The connection exists only while an effect is
	registered. All effects pause while the window is unfocused or a full screen overlay asks (FxLoop.setOverlay(true)).

	FxLoop.add(fn, interval) -> { cancel() }   fn(dt, now) returns true when finished
	FxLoop.setOverlay(on)
]]

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Hub = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("FxLoop"))

local M = {}
local hub = Hub.new()
local conn

local function ensure()
	if conn then return end
	conn = RunService.Heartbeat:Connect(function(dt)
		hub.step(dt, os.clock())
		if hub.count() == 0 then
			conn:Disconnect()
			conn = nil
		end
	end)
end

function M.add(fn, interval)
	local h = hub.add(fn, interval)
	ensure()
	return h
end

function M.setOverlay(on) hub.setPaused("overlay", on == true) end

pcall(function()
	UserInputService.WindowFocusReleased:Connect(function() hub.setPaused("hidden", true) end)
	UserInputService.WindowFocused:Connect(function() hub.setPaused("hidden", false) end)
end)

return M
