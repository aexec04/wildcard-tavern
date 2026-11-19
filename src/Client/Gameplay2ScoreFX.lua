--[[
	Client/Gameplay2ScoreFX.lua
	Plays Engine/Gameplay2Score on the centre score of the Gameplay v2 table: the number counts up in 12 steps with a rising
	tick, then slams in (1.25x and back) with a small gold burst and a one second hold. A tap or click skips to the end value.
	Calm mode and Reduce motion: the end value is set at once, no tween, no burst. Fast speed halves the times.

	Gameplay2ScoreFX.play(scoreNum, burstParent, oldScore, newScore, setText)
	  scoreNum    the TextLabel that shows the number; setText(n) writes it (so the caller keeps its own format)
	  burstParent the Frame the gold dots live in (the centre score box)
]]

local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Engine = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine")
local Rules = require(Engine:WaitForChild("Gameplay2Score"))
local PlayerProfile = require(Engine:WaitForChild("PlayerProfile"))
local ClientSettings = require(script.Parent.ClientSettings)
local Cue = require(script.Parent.Cue)

local M = {}
local running = 0 -- id of the sequence that owns the label; a newer one cancels the older

local function calm() return ClientSettings.get("reduceShake") == true end

local function burst(parent, n)
	local gold = Color3.fromRGB(244, 196, 70)
	for i = 1, n do
		local d = Instance.new("Frame")
		d.Name = "ScoreBurst"
		d.BorderSizePixel = 0
		d.BackgroundColor3 = gold
		d.BackgroundTransparency = 0.1
		d.Size = UDim2.fromOffset(6, 6)
		d.AnchorPoint = Vector2.new(0.5, 0.5)
		d.Position = UDim2.fromScale(0.5, 0.45)
		d.ZIndex = 4
		d.Active = false
		local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(1, 0); c.Parent = d
		d.Parent = parent
		local a = (i / n) * math.pi * 2
		local dist = 60 + (i % 3) * 18
		local tw = TweenService:Create(d, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = UDim2.new(0.5, math.cos(a) * dist, 0.45, math.sin(a) * dist * 0.5), BackgroundTransparency = 1 })
		tw.Completed:Connect(function() d:Destroy() end)
		tw:Play()
	end
end

function M.play(scoreNum, burstParent, oldScore, newScore, setText, target)
	local fast = ClientSettings.get("animSpeed") == "fast" and PlayerProfile.animationPaceDivisor("fast", false) > 1
	local plan = Rules.plan(oldScore, newScore, { calm = calm(), fast = fast, target = target })
	running = running + 1
	local id = running
	if not plan then setText(newScore); return end
	if not plan.slam then setText(plan.final); return end -- calm: the end value, nothing else
	local sc = scoreNum:FindFirstChild("SlamScale")
	if not sc then sc = Instance.new("UIScale"); sc.Name = "SlamScale"; sc.Parent = scoreNum end
	local skipped = false
	local conn
	conn = UserInputService.InputBegan:Connect(function(input)
		local t = input.UserInputType
		if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then skipped = true end
	end)
	task.spawn(function()
		local n = #plan.steps
		for i, v in ipairs(plan.steps) do
			if id ~= running or skipped then break end
			setText(v)
			Cue.play("score_tick", 1, Rules.pitch(i, n))
			task.wait(plan.stepDur)
		end
		conn:Disconnect()
		if id ~= running then return end
		setText(plan.final)
		if skipped then sc.Scale = 1; return end
		Cue.play("score_total")
		burst(burstParent, plan.burst)
		local up = TweenService:Create(sc, TweenInfo.new(plan.slam.up, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = plan.slam.peak })
		up.Completed:Connect(function()
			TweenService:Create(sc, TweenInfo.new(plan.slam.settle, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		end)
		up:Play()
	end)
end

return M
