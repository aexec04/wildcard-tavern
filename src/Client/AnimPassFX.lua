--[[
	Client/AnimPassFX.lua
	Plays Engine/AnimPass: barShine(fill, oldP, newP), nameSlam(label, big), cardFlip(guiObject, index), menuFade(frame) and
	countFlip(label, oldText, newText). Every call checks Calm mode (reduceShake, which also covers Reduce motion) and
	does nothing then, so no tween is ever created. Call each from a pcall.
]]

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AP = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("AnimPass"))
local ClientSettings = require(script.Parent.ClientSettings)

local M = {}

local function calm() return ClientSettings.get("reduceShake") == true end
local function tw(obj, dur, props, style, dir)
	local t = TweenService:Create(obj, TweenInfo.new(dur, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
	t:Play()
	return t
end
local function scaleOf(obj, name)
	local sc = obj:FindFirstChild(name)
	if not sc then
		sc = Instance.new("UIScale")
		sc.Name = name
		sc.Parent = obj
	end
	return sc
end

-- a soft light band crosses the gold bar fill once when it grows
function M.barShine(fill, oldP, newP)
	local p = AP.barShine(oldP, newP, calm())
	if not p or not fill.Parent then return end
	local band = fill:FindFirstChild("Shine")
	if not band then
		fill.ClipsDescendants = true
		band = Instance.new("Frame")
		band.Name = "Shine"
		band.BackgroundColor3 = Color3.fromRGB(255, 250, 220)
		band.BackgroundTransparency = 0.55
		band.BorderSizePixel = 0
		band.ZIndex = fill.ZIndex + 1
		band.Size = UDim2.fromScale(p.width, 1)
		band.Parent = fill
	end
	band.Position = UDim2.fromScale(-p.width, 0)
	band.Visible = true
	local t = tw(band, p.dur, { Position = UDim2.fromScale(1, 0) }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	t.Completed:Connect(function() band.Visible = false end)
end

-- the hand name drops in large, squashes and settles to 1
function M.nameSlam(label, big)
	local p = AP.nameSlam(calm(), big)
	if not p or not label.Parent then return end
	local sc = scaleOf(label, "SlamScale")
	sc.Scale = p.from
	local t = tw(sc, p.down, { Scale = p.squash }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	t.Completed:Connect(function() tw(sc, p.settle, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out) end)
end

-- shop cards turn up one by one: each grows from a thin sliver, in order
function M.cardFlip(obj, index)
	local p = AP.cardFlip(index, calm())
	if not p or not obj.Parent then return end
	local sc = scaleOf(obj, "FlipScale")
	sc.Scale = p.from
	task.delay(p.delay, function()
		if sc.Parent then tw(sc, p.dur, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out) end
	end)
end

-- a menu or panel frame grows a little as it appears
function M.menuFade(frame)
	local p = AP.menuFade(calm())
	if not p or not frame.Parent then return end
	local sc = scaleOf(frame, "FadeScale")
	sc.Scale = p.from
	tw(sc, p.dur, { Scale = 1 })
end

-- the deck count flips: the old number fades out, the new one fades in
function M.countFlip(label, oldText, newText)
	local p = AP.countFlip(oldText, newText, calm())
	if not p or not label.Parent then return end
	label.Text = oldText
	local out = tw(label, p.half, { TextTransparency = 1 })
	out.Completed:Connect(function()
		if not label.Parent then return end
		label.Text = newText
		tw(label, p.half, { TextTransparency = 0 })
	end)
end

return M
