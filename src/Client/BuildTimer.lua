--[[
	Client/BuildTimer.lua
	Times a screen build. BuildTimer.time("Settings", fn) runs fn, returns what it returns, and in Studio prints
	"[Build] Settings 42 ms" (with OVER 150 ms past the Engine/PerformanceMode budget). Outside Studio it only runs fn.
]]

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PerformanceMode = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("PerformanceMode"))

local BuildTimer = {}
BuildTimer.samples = {}

function BuildTimer.time(name, fn, ...)
	if not RunService:IsStudio() then return fn(...) end
	local t0 = os.clock()
	local results = table.pack(fn(...))
	local ms = (os.clock() - t0) * 1000
	BuildTimer.samples[#BuildTimer.samples + 1] = { name = name, ms = ms }
	print(PerformanceMode.line(name, ms))
	return table.unpack(results, 1, results.n)
end

return BuildTimer
