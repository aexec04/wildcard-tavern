--[[
	Client/CollectionWarm.lua
	Starts the Collection art download early, once: in the background a moment after the menu shows, on the first hover or press of a
	Collection or Tome button, and on the first open. Pure ContentArt preload calls (deduplicated there too), no panel is built.
	  warm()                  start the warm up unless it already ran or is running
	  hook(button)            warm on the first hover or press of `button`
	  scheduleIdle(seconds)   warm after `seconds` (default 6) when nothing asked sooner
]]

local Engine = game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine")
local TileCache = require(Engine:WaitForChild("CollectionTileCache"))

local M = {}
local done = {}

function M.warm()
	if not TileCache.shouldWarm(done, "all") then return false end
	task.spawn(function()
		local ContentArt = require(Engine:WaitForChild("ContentArt"))
		local CP = require(Engine:WaitForChild("CollectionPreload"))
		local t0 = os.clock()
		ContentArt.preload(CP.items(), "collection warm", { batch = CP.BATCH, pause = 0.03 })
		if game:GetService("RunService"):IsStudio() then print(string.format("[Collection] warm up done in %d ms", math.floor((os.clock() - t0) * 1000 + 0.5))) end
	end)
	return true
end

function M.hook(button)
	if typeof(button) ~= "Instance" then return end
	pcall(function() button.MouseEnter:Connect(M.warm) end)
	pcall(function() button.MouseButton1Down:Connect(M.warm) end)
	pcall(function() button.TouchTap:Connect(M.warm) end)
end

function M.scheduleIdle(seconds)
	task.delay(tonumber(seconds) or 6, M.warm)
end

return M
