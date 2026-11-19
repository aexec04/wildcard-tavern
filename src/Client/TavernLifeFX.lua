--[[
	Client/TavernLifeFX.lua
	Plays Engine/TavernLife: a breathing sleeping cat on the painted room, a gold coin burst on the coin pill and a brief warm flash
	on a big hand. Calm mode and Reduce motion create no loop and no tween (the cat stays a still part of the picture).

	cat(layer, roomImage)      -> { place(rect), destroy() }   rect = the room picture rect in layer pixels; one 30 Hz loop
	coinBurst(layer, pill, old, new)   pill = the coin pill GuiObject
	warmFlash(root, score, target)
]]

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Life = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("TavernLife"))
local ClientSettings = require(script.Parent.ClientSettings)

local M = {}

local function calm() return ClientSettings.get("reduceShake") == true end

-- the cat is a crop of the room picture drawn over itself, so its pixels match; it scales 1.5 percent about its base
function M.cat(layer, roomImage)
	local self = {}
	local c = Life.CAT
	local holder = Instance.new("ImageLabel")
	holder.Name = "RoomCat"
	holder.BackgroundTransparency = 1
	holder.BorderSizePixel = 0
	holder.Active = false
	holder.Image = roomImage.Image
	holder.ImageRectOffset = Vector2.new(c.x, c.y)
	holder.ImageRectSize = Vector2.new(c.w, c.h)
	holder.AnchorPoint = Vector2.new(0.5, 1)
	holder.ZIndex = 1
	holder.Visible = false
	holder.Parent = layer
	local sc = Instance.new("UIScale")
	sc.Parent = holder
	local rect, shown = nil, false
	function self.place(r, visible)
		rect, shown = r, visible ~= false
		holder.Image = roomImage.Image
		holder.Visible = Life.CAT_OVERLAY and r ~= nil and shown and holder.Image ~= ""
		if not r then return end
		holder.Position = UDim2.fromOffset(r.x + (c.x + c.w / 2) / 1536 * r.w, r.y + (c.y + c.h) / 1024 * r.h)
		holder.Size = UDim2.fromOffset(c.w / 1536 * r.w, c.h / 1024 * r.h)
	end
	local acc = 0
	local conn = RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 1 / 30 then return end
		acc = 0
		if not Life.CAT_OVERLAY or not rect or not shown then return end
		sc.Scale = Life.catScale(os.clock(), calm())
	end)
	function self.destroy()
		conn:Disconnect()
		holder:Destroy()
	end
	return self
end

function M.coinBurst(layer, pill, old, new)
	local p = Life.coinBurst(old, new, calm())
	if not p or not pill or not pill.Parent then return end
	local lr = layer.AbsolutePosition
	local cx = pill.AbsolutePosition.X - lr.X + pill.AbsoluteSize.X * 0.3
	local cy = pill.AbsolutePosition.Y - lr.Y + pill.AbsoluteSize.Y * 0.5
	for i = 1, p.count do
		local d = Instance.new("Frame")
		d.Name = "CoinBurst"
		d.AnchorPoint = Vector2.new(0.5, 0.5)
		d.Size = UDim2.fromOffset(8, 8)
		d.Position = UDim2.fromOffset(cx, cy)
		d.BackgroundColor3 = Color3.fromRGB(246, 196, 70)
		d.BackgroundTransparency = 0
		d.BorderSizePixel = 0
		d.Active = false
		d.ZIndex = 5
		d.Parent = layer
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = d
		local ang = -math.pi / 2 + ((i - 0.5) / p.count - 0.5) * math.pi * 0.9
		local info = TweenInfo.new(p.dur, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		TweenService:Create(d, info, {
			Position = UDim2.fromOffset(cx + math.cos(ang) * p.rise, cy + math.sin(ang) * p.rise),
			BackgroundTransparency = 1,
		}):Play()
		task.delay(p.dur + 0.05, function() d:Destroy() end)
	end
end

function M.warmFlash(root, score, target)
	local p = Life.warmFlash(score, target, calm())
	if not p or not root then return end
	local f = Instance.new("Frame")
	f.Name = "WarmFlash"
	f.Size = UDim2.fromScale(1, 1)
	f.BackgroundColor3 = Color3.fromRGB(255, 190, 100)
	f.BackgroundTransparency = 1 - p.alpha
	f.BorderSizePixel = 0
	f.Active = false
	f.ZIndex = 4
	f.Parent = root
	TweenService:Create(f, TweenInfo.new(p.dur, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 1 }):Play()
	task.delay(p.dur + 0.05, function() f:Destroy() end)
end

return M
