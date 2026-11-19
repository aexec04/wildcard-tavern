--[[
	Client/CelebrationFX.lua
	Plays Engine/Celebration for the round clear, win and defeat moments. Every call reads Calm mode (reduceShake, which also covers
	Reduce motion) first and then creates no tween and no loop: the end state is shown at once. Call each from a pcall.

	countUp(label, total, textFor)   Tips count up one coin at a time with the score_tick sound; textFor(n) gives the label text
	winConfetti(screenGui)           40 gold and red card-suit shapes fall over 2.5 s, take no input
	titleIn(label)                   the title scales in from 0.6 with a slight overshoot
	defeatWash(dim) -> fn            a gentle grey wash fades in over 0.8 s behind the panel; call the returned fn to remove it
]]

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local C = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("Celebration"))
local SoundFX = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("SoundFX"))
local ClientSettings = require(script.Parent.ClientSettings)

local M = {}

local function calm() return ClientSettings.get("reduceShake") == true end

function M.countUp(label, total, textFor)
	local plan = C.countSteps(total, calm())
	label.Text = textFor(plan and 0 or total)
	if not plan then return end
	task.spawn(function()
		for i, v in ipairs(plan.values) do
			task.wait(plan.step)
			if not label.Parent then return end
			label.Text = textFor(v)
			pcall(function() require(script.Parent.Cue).play("score_tick", 1, SoundFX.tickSpeed(i)) end) -- pitch rises 1.0 to 1.3
		end
	end)
end

function M.winConfetti(screenGui)
	local plan = C.confetti(math.floor(os.clock() * 1000), calm())
	if not plan or not screenGui then return 0 end
	local holder = Instance.new("Frame")
	holder.Name = "WinConfetti"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromScale(1, 1)
	holder.Active = false
	holder.ZIndex = 200
	holder.Parent = screenGui
	local parts = {}
	for i, p in ipairs(plan.pieces) do
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.AnchorPoint = Vector2.new(0.5, 0.5)
		l.Size = UDim2.fromOffset(p.size, p.size)
		l.Font = Enum.Font.GothamBold
		l.TextSize = p.size
		l.Text = p.glyph
		l.TextColor3 = Color3.fromRGB(p.color[1], p.color[2], p.color[3])
		l.TextTransparency = 0
		l.TextStrokeTransparency = 0.5
		l.TextStrokeColor3 = Color3.fromRGB(40, 24, 14)
		l.Active = false
		l.ZIndex = 200
		l.Visible = false
		l.Parent = holder
		parts[i] = l
	end
	local t0 = os.clock()
	local conn
	conn = RunService.Heartbeat:Connect(function()
		local t = os.clock() - t0
		if t > plan.dur + 0.1 or not holder.Parent then
			conn:Disconnect()
			holder:Destroy()
			return
		end
		local h = holder.AbsoluteSize.Y
		for i, p in ipairs(plan.pieces) do
			local l = parts[i]
			local lt = t - p.delay
			if lt >= 0 and lt <= p.fall then
				local f = lt / p.fall
				l.Visible = true
				l.Position = UDim2.new(p.x, p.sway * math.sin(f * 3), 0, -30 + (h + 60) * f)
				l.Rotation = p.spin * f
				l.TextTransparency = math.max(0, (f - 0.8) / 0.2)
			else
				l.Visible = false
			end
		end
	end)
	return #plan.pieces
end

function M.titleIn(label)
	local p = C.titleIn(calm())
	if not p or not label.Parent then return end
	local sc = label:FindFirstChild("TitleIn")
	if not sc then
		sc = Instance.new("UIScale")
		sc.Name = "TitleIn"
		sc.Parent = label
	end
	sc.Scale = p.from
	TweenService:Create(sc, TweenInfo.new(p.dur * 0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = p.peak }):Play()
	task.delay(p.dur * 0.7, function()
		if sc.Parent then
			TweenService:Create(sc, TweenInfo.new(p.dur * 0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), { Scale = 1 }):Play()
		end
	end)
end

function M.defeatWash(dim)
	local p = C.defeat(calm())
	if not p or not dim then return function() end end
	local wash = dim:FindFirstChild("DefeatWash")
	if not wash then
		wash = Instance.new("Frame")
		wash.Name = "DefeatWash"
		wash.Size = UDim2.fromScale(1, 1)
		wash.BackgroundColor3 = Color3.fromRGB(128, 122, 116)
		wash.BorderSizePixel = 0
		wash.Active = false
		wash.ZIndex = dim.ZIndex
		wash.Parent = dim
	end
	wash.BackgroundTransparency = 1
	TweenService:Create(wash, TweenInfo.new(p.dur, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), { BackgroundTransparency = 1 - p.tint * 0.5 }):Play()
	return function()
		if wash.Parent then wash:Destroy() end
	end
end

return M
