--[[
	Client/HudKitPreload.lua
	Loads a Card Set's painted HUD kit images before the set is applied, so the round buttons and left panel never flash empty
	rings for a couple of seconds. whenReady(setId, fn) runs fn at once when the set has no kit or its images were loaded before;
	otherwise the old look stays and fn runs after ContentProvider:PreloadAsync finishes (or fails: never block the set).
]]
local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HudKit = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("HudKit"))

local HudKitPreload = {}
local loaded = {} -- setId -> true

function HudKitPreload.whenReady(setId, fn)
	local images = setId and not loaded[setId] and HudKit.images(setId) or nil
	if not images then
		fn()
		return
	end
	local list = {}
	for _, id in pairs(images) do list[#list + 1] = id end
	task.spawn(function()
		pcall(function() ContentProvider:PreloadAsync(list) end)
		loaded[setId] = true
		fn()
	end)
end

return HudKitPreload
