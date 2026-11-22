--[[
	Client/CollectionWarm.lua
	Starts the Collection art download early, once: in the background a moment after the menu shows, on the first hover or press of a
	Collection or Tome button, and on the first open. Pure ContentArt preload calls (deduplicated there too), no panel is built.
	  warm()                  start the warm up unless it already ran or is running
	  hook(button)            warm on the first hover or press of `button`
	  scheduleIdle(seconds)   warm after `seconds` (default 6) when nothing asked sooner
	  cancel()                the Collection opened: stop the warm up between batches; hidden tabs are never fetched on open
]]

local Engine = game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine")
local TileCache = require(Engine:WaitForChild("CollectionTileCache"))

local M = {}
local done = {}

local cancelled = false

function M.warm()
	if not TileCache.shouldWarm(done, "all") then return false end
	task.spawn(function()
		local ContentArt = require(Engine:WaitForChild("ContentArt"))
		local CP = require(Engine:WaitForChild("CollectionPreload"))
		local t0 = os.clock()
		ContentArt.preload(CP.items(), "collection warm", { batch = CP.BATCH, pause = 0.03, cancelled = function() return cancelled end })
		if game:GetService("RunService"):IsStudio() then print(string.format("[Collection] warm up %s in %d ms", cancelled and "stopped" or "done", math.floor((os.clock() - t0) * 1000 + 0.5))) end
	end)
	return true
end

-- the Collection opened: the background warm up of every tab stops (the tab on screen is fetched by the Collection itself) and never restarts
function M.cancel()
	cancelled = true
	done.all = true
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
