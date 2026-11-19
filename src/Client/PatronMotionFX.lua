--[[
	Client/PatronMotionFX.lua
	Plays Engine/PatronMotion on a Patron Row card `c` (the pool entry from PatronRow): a drop-in entrance with a small bounce
	and a rarity glow sweep (Legendary adds light rays), and a hover or tap lift with a larger effect pill. Calm mode and
	Reduce motion make no tweens at all: the card appears and the larger pill is set directly.

	enter(c, tier, calm)    c.slot, c.float; sets c.hopping while it plays and calls c.afterMotion() when done
	hover(c, on, calm)      c.hovering is true while lifted
]]

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Motion = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("PatronMotion"))

local M = {}

local function glowFrame(slot, rgb, rounded)
	local f = Instance.new("Frame")
	f.Name = "EntranceGlow"
	f.BackgroundColor3 = Color3.fromRGB(rgb[1], rgb[2], rgb[3])
	f.BackgroundTransparency = 0.5
	f.BorderSizePixel = 0
	f.Active = false
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromScale(0.5, 0.5)
	f.Size = UDim2.fromScale(1, 1)
	f.ZIndex = 14
	f.Parent = slot
	if rounded then
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, 8)
		c.Parent = f
	end
	return f
end

function M.enter(c, tier, calm)
	local p = Motion.entrance(tier, calm)
	if not p then return end
	if c.floatTween then c.floatTween:Cancel(); c.floatTween = nil end
	c.hopping = true
	c.float.Position = UDim2.fromOffset(0, p.drop)
	local t1 = TweenService:Create(c.float, TweenInfo.new(p.dur, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = UDim2.fromOffset(0, 0) })
	t1.Completed:Connect(function()
		local t2 = TweenService:Create(c.float, TweenInfo.new(p.settle, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = UDim2.fromOffset(0, -p.bounce) })
		t2.Completed:Connect(function()
			local t3 = TweenService:Create(c.float, TweenInfo.new(p.settle, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = UDim2.fromOffset(0, 0) })
			t3.Completed:Connect(function()
				c.hopping = false
				if c.afterMotion then c.afterMotion() end
			end)
			t3:Play()
		end)
		t2:Play()
	end)
	t1:Play()
	-- glow sweep: a soft tinted wash that grows slightly and fades
	local g = glowFrame(c.slot, p.glow, true)
	local info = TweenInfo.new(p.glowDur, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(g, info, { BackgroundTransparency = 1, Size = UDim2.fromScale(1.18, 1.12) }):Play()
	task.delay(p.glowDur + 0.05, function() g:Destroy() end)
	if p.rays then
		for i = 0, 3 do
			local r = glowFrame(c.slot, p.glow, false)
			r.Name = "EntranceRay"
			r.BackgroundTransparency = 0.35
			r.Size = UDim2.new(0.12, 0, 1.5, 0)
			r.Rotation = i * 45
			r.ZIndex = 13
			TweenService:Create(r, info, { BackgroundTransparency = 1, Size = UDim2.new(0.04, 0, 1.9, 0) }):Play()
			task.delay(p.glowDur + 0.05, function() r:Destroy() end)
		end
	end
end

function M.hover(c, on, calm)
	local p = Motion.hover(calm)
	c.hovering = on == true
	local pill = c.slot:FindFirstChild("CTPill")
	if pill then
		local sc = pill:FindFirstChild("HoverScale")
		if not sc then
			sc = Instance.new("UIScale")
			sc.Name = "HoverScale"
			sc.Parent = pill
		end
		local target = on and p.pillScale or 1
		if p.animate then
			TweenService:Create(sc, TweenInfo.new(p.dur, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = target }):Play()
		else
			sc.Scale = target
		end
	end
	if p.animate and not c.hopping then
		if c.floatTween then c.floatTween:Cancel(); c.floatTween = nil end
		TweenService:Create(c.float, TweenInfo.new(p.dur, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Position = UDim2.fromOffset(0, on and -p.lift or 0) }):Play()
	end
end

return M
