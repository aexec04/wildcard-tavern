--[[
	Client/ArtFade.lua
	No pop-in: an image that has not loaded yet stays clear and fades in over 0.15 s when it has (ImageLabel.IsLoaded), or after
	1.5 s at the latest (IsLoaded reads false in Studio for a hidden label). Already loaded images are not touched. Calm mode: no fade.

	apply(imageLabel)
]]

local TweenService = game:GetService("TweenService")
local ClientSettings = require(script.Parent.ClientSettings)

local ArtFade = {}

ArtFade.DURATION = 0.15
ArtFade.MAX_WAIT = 1.5

function ArtFade.apply(art)
	if not art or art.IsLoaded then return end
	local target = art.ImageTransparency
	art.ImageTransparency = 1
	task.spawn(function()
		local waited = 0
		while art.Parent and not art.IsLoaded and waited < ArtFade.MAX_WAIT do
			task.wait(0.03)
			waited += 0.03
		end
		if not art.Parent then return end
		if ClientSettings.motionAllowed() then
			TweenService:Create(art, TweenInfo.new(ArtFade.DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { ImageTransparency = target }):Play()
		else
			art.ImageTransparency = target
		end
	end)
end

return ArtFade
