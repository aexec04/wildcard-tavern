--[[
	ReplicatedFirst/LoadingScreen.client.lua
	Runs before everything else. Shows the painted launch screen, preloads the menu art (40 percent) then the
	gameplay art (40 percent) through ContentArt, and waits for the hub to report the Menu visible (20 percent,
	Engine/LoadProgress.menuShown). Fades out when the bar is full; a Skip button appears after 25 s.
]]

local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local shared = ReplicatedStorage:WaitForChild("Shared")
local Engine = shared:WaitForChild("Engine")

local okUI, UI = pcall(function() return require(script.Parent:WaitForChild("LoadingScreenUI")) end)
local handle = okUI and UI.show(playerGui, { shared = shared, calm = player:GetAttribute("CalmMode") == true }) or nil
pcall(function() ReplicatedFirst:RemoveDefaultLoadingScreen() end)
if handle and handle.setSet then
	-- the server publishes the equipped Card Set as a Player attribute once the profile loads; classic (or none) keeps the painted look
	handle.setSet(player:GetAttribute("EquippedCardSet"))
	player:GetAttributeChangedSignal("EquippedCardSet"):Connect(function()
		if handle.isAlive and handle.isAlive() then handle.setSet(player:GetAttribute("EquippedCardSet")) end
	end)
end
if not handle then
	warn("[LoadingScreen] could not build the screen: " .. tostring(UI))
	return
end

local LoadProgress = require(Engine:WaitForChild("LoadProgress"))
local progress = LoadProgress.shared
local ContentArt = require(Engine:WaitForChild("ContentArt"))

local skipped = false
local plan = {}
for _, phase in ipairs(ContentArt.PreloadPlan) do plan[phase.name] = phase end

task.spawn(function()
	for _, name in ipairs({ "menu", "gameplay" }) do
		if skipped then break end
		local phase = plan[name]
		if phase then pcall(ContentArt.preload, phase.items, name, { batch = 8 }) end
		progress.complete(name)
	end
end)

task.spawn(function()
	while handle.isAlive() do
		handle.setTarget(progress.value())
		if progress.isReady() then handle.setReady() end
		task.wait(0.1)
	end
end)

-- Studio only: DataStore calls hang there, so end the screen by itself after LoadProgress.STUDIO_CAP seconds (or sooner if ready)
do
	local okRun, isStudio = pcall(function() return game:GetService("RunService"):IsStudio() end)
	if okRun and isStudio then
		local startedAt = os.clock()
		task.spawn(function()
			while handle.isAlive() do
				local elapsed = os.clock() - startedAt
				if LoadProgress.studioCap(true, elapsed) then
					skipped = true
					print(string.format("[LoadDone] %.1f s (Studio cap)", elapsed))
					handle.fadeOut()
					return
				end
				task.wait(0.1)
			end
			print(string.format("[LoadDone] %.1f s", os.clock() - startedAt))
		end)
	end
end

-- a Skip click fades the screen anyway; the assets keep streaming
task.delay(LoadProgress.SKIP_AFTER + 1, function()
	if handle.isAlive() then skipped = true end
end)
