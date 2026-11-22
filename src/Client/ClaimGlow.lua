--[[
	Client/ClaimGlow.lua
	ClaimGlow.glow(button) flashes a 0.4 s outline on a claim button in the equipped Card Set accent (rules in Engine/ClaimMoment).
	The claim sound stays where it was (each claim site plays the existing "reward_claim" cue itself). Calm mode and Reduce motion:
	no stroke and no tween. Never throws: a claim must not break on a missing piece.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local ClaimMoment = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("ClaimMoment"))

local ClaimGlow = {}

function ClaimGlow.glow(button)
	pcall(function()
		local calm = require(script.Parent.ClientSettings).get("reduceShake") == true
		local plan = ClaimMoment.plan(require(script.Parent.TavernKit).plateSetId(), calm)
		if not plan.glow or not button or not button.Parent then return end
		local c = plan.glow.color
		local stroke = Instance.new("UIStroke")
		stroke.Name = "ClaimGlow"
		stroke.Color = Color3.fromRGB(c[1], c[2], c[3])
		stroke.Thickness = 4
		stroke.Transparency = 0
		stroke.Parent = button -- on the button itself so it follows it and survives a Clone
		local tween = TweenService:Create(stroke, TweenInfo.new(plan.glow.seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Transparency = 1 })
		tween.Completed:Connect(function() stroke:Destroy() end)
		tween:Play()
	end)
end

return ClaimGlow
