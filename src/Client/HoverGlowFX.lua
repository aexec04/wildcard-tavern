--[[
	Client/HoverGlowFX.lua
	The shared hover and pick glow (rules in Engine/HoverGlow, from the Round Select blind cards): the card grows 1.04 with a UIScale,
	a cream wash brightens the art a little, a gold rim swells and one slow shine passes. Nothing rests visible: every part is
	Visible = false and fully transparent until hovered or picked. Calm mode (Reduce shake) and `strokeOnly` keep only the rim.

	attach(target, opts) -> handle { setHover(on), destroy() }
	  target   the card frame (the UIScale and the parts are parented to it, so they survive a Clone of the target)
	  opts     hit = GuiObject with MouseEnter and MouseLeave (default target), radius = 8, strokeOnly = false, manual = true (no mouse hooks: the owner calls setHover), zIndex = target.ZIndex + 3,
	           calm = function() -> bool (default reads the Reduce shake setting)
]]

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Rules = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("HoverGlow"))

local GOLD = Color3.fromRGB(222, 182, 104)
local CREAM = Color3.fromRGB(250, 235, 200)

local M = {}

local function defaultCalm()
	local ok, v = pcall(function() return require(script.Parent.ClientSettings).get("reduceShake") end)
	return ok and v == true
end

local function ease(inst, props, seconds)
	if seconds <= 0 then
		for k, v in pairs(props) do inst[k] = v end
		return
	end
	TweenService:Create(inst, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props):Play()
end

function M.attach(target, opts)
	opts = opts or {}
	local calmFn = opts.calm or defaultCalm
	local z = opts.zIndex or (target.ZIndex + 3)
	local radius = opts.radius or 8
	local hit = (opts.manual ~= true) and (opts.hit or target) or nil

	local scale = Instance.new("UIScale")
	scale.Name = "HoverGlowScale"
	scale.Scale = 1
	scale.Parent = target

	local rim = Instance.new("Frame") -- gold rim, hover only
	rim.Name = "HoverRim"
	rim.Size = UDim2.fromScale(1, 1)
	rim.BackgroundTransparency = 1
	rim.BorderSizePixel = 0
	rim.Active = false
	rim.Visible = false
	rim.ZIndex = z
	rim.Parent = target
	local rc = Instance.new("UICorner"); rc.CornerRadius = UDim.new(0, radius); rc.Parent = rim
	local stroke = Instance.new("UIStroke")
	stroke.Color = GOLD
	stroke.Thickness = 0
	stroke.Transparency = 1
	stroke.Parent = rim

	local wash = Instance.new("Frame") -- brightens the art a little
	wash.Name = "HoverBrighten"
	wash.Size = UDim2.fromScale(1, 1)
	wash.BackgroundColor3 = CREAM
	wash.BackgroundTransparency = 1
	wash.BorderSizePixel = 0
	wash.Active = false
	wash.Visible = false
	wash.ZIndex = z
	wash.Parent = target
	local wc = Instance.new("UICorner"); wc.CornerRadius = UDim.new(0, radius); wc.Parent = wash

	local clip = Instance.new("Frame") -- the slow shine passes inside the card
	clip.Name = "HoverShineClip"
	clip.Size = UDim2.fromScale(1, 1)
	clip.BackgroundTransparency = 1
	clip.BorderSizePixel = 0
	clip.ClipsDescendants = true
	clip.Active = false
	clip.Visible = false
	clip.ZIndex = z
	clip.Parent = target
	local cc = Instance.new("UICorner"); cc.CornerRadius = UDim.new(0, radius); cc.Parent = clip
	local strip = Instance.new("Frame")
	strip.Name = "HoverShine"
	strip.AnchorPoint = Vector2.new(0.5, 0.5)
	strip.Size = UDim2.new(0.16, 0, 1.8, 0)
	strip.Position = UDim2.new(-0.3, 0, 0.5, 0)
	strip.Rotation = 20
	strip.BackgroundColor3 = CREAM
	strip.BackgroundTransparency = 0.8
	strip.BorderSizePixel = 0
	strip.Active = false
	strip.ZIndex = z
	strip.Parent = clip

	local hovered = false
	local handle = {}

	function handle.setHover(on)
		if hovered == on then return end
		hovered = on
		local calm = calmFn()
		local p = Rules.plan(calm, opts.strokeOnly)
		if on then
			rim.Visible = true
			ease(stroke, { Thickness = p.rimThickness, Transparency = p.rimT }, p.seconds)
			if p.scale ~= 1 then
				wash.Visible = true
				ease(scale, { Scale = p.scale }, p.seconds)
				ease(wash, { BackgroundTransparency = p.brightenT }, p.seconds)
			end
			if p.shine then
				clip.Visible = true
				strip.Position = UDim2.new(-0.3, 0, 0.5, 0)
				local tw = TweenService:Create(strip, TweenInfo.new(Rules.SHINE_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), { Position = UDim2.new(1.3, 0, 0.5, 0) })
				tw.Completed:Connect(function() if not hovered then clip.Visible = false end end)
				tw:Play()
			end
		else
			ease(stroke, { Thickness = 0, Transparency = 1 }, p.restSeconds)
			ease(scale, { Scale = 1 }, p.restSeconds)
			ease(wash, { BackgroundTransparency = 1 }, p.restSeconds)
			task.delay(p.restSeconds + 0.02, function()
				if hovered then return end -- hovered again meanwhile: leave it shown
				rim.Visible, wash.Visible, clip.Visible = false, false, false
			end)
		end
	end

	local conns = {}
	if hit and hit.MouseEnter then
		conns[#conns + 1] = hit.MouseEnter:Connect(function() handle.setHover(true) end)
		conns[#conns + 1] = hit.MouseLeave:Connect(function() handle.setHover(false) end)
	end

	function handle.destroy()
		for _, c in ipairs(conns) do c:Disconnect() end
		for _, inst in ipairs({ scale, rim, wash, clip }) do inst:Destroy() end
	end

	return handle
end

return M
