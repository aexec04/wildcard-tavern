--[[
	Client/PatronShineFX.lua
	Idle polish on Patron Row cards (numbers in Engine/PatronShine): a slow soft edge glow in the rarity colour on Rare, Epic and
	Legendary cards (3 s sine, 0.15 to 0.35 alpha) and a diagonal shine sweep every 6 s on Legendary only. Calm mode and Reduce
	motion (`calm`) draw nothing and make no tweens. Only Color and Transparency of plain Frames are touched, no gradients.

	sync(c, tier, calm, seat)   c.float and c.body from PatronRow; safe to call on every refresh (rebuilds only when the tier changes)
	clear(c)                    removes the glow and the shine (an emptied seat, or calm mode switched on)
]]

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shine = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("PatronShine"))

local M = {}

function M.clear(c)
	if c.glowTween then c.glowTween:Cancel(); c.glowTween = nil end
	c.shineToken = nil
	c.shineTier = nil
	local g = c.float and c.float:FindFirstChild("RarityGlow")
	if g then g:Destroy() end
	local s = c.body and c.body:FindFirstChild("ShineClip")
	if s then s:Destroy() end
end

function M.sync(c, tier, calm, seat)
	local g, s = Shine.glow(tier, calm), Shine.shine(tier, calm)
	if not g then
		if c.shineTier then M.clear(c) end
		return
	end
	local key = tostring(tier):lower()
	if c.shineTier == key and c.float:FindFirstChild("RarityGlow") then return end
	M.clear(c)
	c.shineTier = key
	local z = c.body.ZIndex
	-- a soft rounded rim in the rarity colour: no filled block, so no square edge shows behind the card
	local glow = Instance.new("Frame")
	glow.Name = "RarityGlow"
	glow.AnchorPoint = Vector2.new(0.5, 0.5)
	glow.Position = UDim2.fromScale(0.5, 0.5)
	glow.Size = UDim2.new(1, g.grow, 1, g.grow)
	glow.BackgroundTransparency = 1
	glow.BorderSizePixel = 0
	glow.Active = false
	glow.ZIndex = z - 1
	glow.Parent = c.float
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = glow
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(g.rgb[1], g.rgb[2], g.rgb[3])
	stroke.Thickness = 5
	stroke.Transparency = g.transMax
	stroke.Parent = glow
	c.glowTween = TweenService:Create(stroke, TweenInfo.new(g.period / 2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Transparency = g.transMin })
	c.glowTween:Play()
	if not s then return end
	local clip = Instance.new("Frame")
	clip.Name = "ShineClip"
	clip.Size = UDim2.fromScale(1, 1)
	clip.BackgroundTransparency = 1
	clip.ClipsDescendants = true
	local clipCorner = Instance.new("UICorner")
	clipCorner.CornerRadius = UDim.new(0, 12)
	clipCorner.Parent = clip
	clip.Active = false
	clip.ZIndex = z + 3
	clip.Parent = c.body
	local band = Instance.new("Frame")
	band.Name = "ShineBand"
	band.AnchorPoint = Vector2.new(0.5, 0.5)
	band.Size = UDim2.fromScale(s.width, 1.6)
	band.Position = UDim2.fromScale(s.fromX, 0.5)
	band.Rotation = s.angle
	band.BackgroundColor3 = Color3.fromRGB(255, 244, 205)
	band.BackgroundTransparency = s.transparency
	band.BorderSizePixel = 0
	band.Active = false
	band.ZIndex = z + 3
	band.Parent = clip
	local token = {}
	c.shineToken = token
	task.spawn(function()
		task.wait(Shine.shineOffset(seat))
		while c.shineToken == token and band.Parent do
			band.Position = UDim2.fromScale(s.fromX, 0.5)
			TweenService:Create(band, TweenInfo.new(s.dur, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), { Position = UDim2.fromScale(s.toX, 0.5) }):Play()
			task.wait(s.period)
		end
	end)
end

return M
