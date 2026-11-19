--[[
	Client/InputWatchdogFX.lua
	A 6 second safety net so input can never stay blocked: once a second it looks at the screen fade cover and at InputGuard's
	locks. If the cover has been up for 6 s, or a lock is held by an overlay that is hidden or gone, it is released (the cover
	hides, the lock closes, PopupShield stops sinking clicks for hidden popups) and a friendly "stuck" toast shows. Overlays that
	are really open keep their locks. Timing is the tested Engine/InputWatchdog. No tweens.

	InputWatchdogFX.start()   called once from the hub; safe to call twice
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Watchdog = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("InputWatchdog"))

local M = {}
local started = false

function M.start()
	if started then return end
	started = true
	local wd = Watchdog.new()
	task.spawn(function()
		local ticks = 0
		while true do
			task.wait(1)
			ticks = ticks + 1
			if ticks % 5 == 0 then -- every 5 s: a button whose plate or rim draws over its word gets the label on top
				pcall(function()
					local gui = game:GetService("Players").LocalPlayer:FindFirstChild("PlayerGui")
					if gui then local BLT = require(script.Parent.ButtonLabelTop); BLT.sweep(gui); BLT.doubled(gui, true) end
				end)
			end
			local now = os.clock()
			local Fade = require(script.Parent.ScreenFadeFX)
			local Guard = require(script.Parent.InputGuard)
			local Shield = require(script.Parent.PopupShield)
			if Fade.busy() then wd:arm("fade", now) else wd:clear("fade") end
			if Guard.stale() then wd:arm("guard", now) else wd:clear("guard") end
			for _, id in ipairs(wd:expired(now)) do
				warn("[InputWatchdog] released " .. id)
				if id == "fade" then Fade.forceRelease() end
				if id == "guard" then
					Guard.resync()
					Shield.releaseHidden()
				end
				pcall(function() require(script.Parent.FriendlyErrorFX).show("stuck") end)
			end
		end
	end)
end

return M
