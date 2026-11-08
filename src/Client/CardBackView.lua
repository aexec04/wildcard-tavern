--[[
	Client/CardBackView.lua
	Helpers for painted card backs. Art comes from ContentArt (category
	card_backs, keyed by CardBacks id); a missing id falls back to a flat color
	in the back's own base/trim colors plus its emoji, so nothing breaks.

	M.imageFor(backId)                    -> rbxassetid string or nil
	M.thumb(parent, back, opts)           -> Frame (card thumbnail)
	    opts: { size = Vector2 (default 90x135), equipped, locked, zIndex,
	            shimmer (default true), isActive = function -> bool }
	Shimmer: a thin white diagonal strip sweeps across every 3s (strip
	BackgroundTransparency tweened; no UIGradient). The loop ends when the
	thumb is destroyed or isActive() returns false.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Engine = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine")
local ContentArt = require(Engine:WaitForChild("ContentArt"))

local GOLD = Color3.fromRGB(222, 182, 104)
local LOCKED_TINT = Color3.fromRGB(120, 120, 120) -- never black

local M = {}

function M.imageFor(backId)
	return backId and ContentArt.getImageId("card_backs", backId) or nil
end

local function rgb(t)
	return Color3.fromRGB(t[1], t[2], t[3])
end

local function startShimmer(thumb, strip, isActive)
	task.spawn(function()
		task.wait(math.random() * 2) -- desync tiles
		while thumb.Parent do
			if not isActive or isActive() then
				strip.Position = UDim2.fromScale(-0.4, 0.5)
				strip.BackgroundTransparency = 0.75
				local sweep = TweenService:Create(strip, TweenInfo.new(0.7, Enum.EasingStyle.Sine), {
					Position = UDim2.fromScale(1.4, 0.5),
				})
				sweep:Play()
				sweep.Completed:Wait()
				strip.BackgroundTransparency = 1
			end
			task.wait(2.3)
		end
	end)
end

function M.thumb(parent, back, opts)
	opts = opts or {}
	local size = opts.size or Vector2.new(90, 135)
	local z = opts.zIndex or 42

	local frame = Instance.new("Frame")
	frame.Name = "BackThumb"
	frame.Size = UDim2.fromOffset(size.X, size.Y)
	frame.BackgroundColor3 = back and rgb(back.colors.base) or Color3.fromRGB(60, 50, 42)
	frame.ClipsDescendants = true
	frame.ZIndex = z
	frame.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = opts.equipped and 3 or 1.5
	stroke.Color = opts.equipped and GOLD or (back and rgb(back.colors.trim) or Color3.fromRGB(140, 130, 120))
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = frame

	local imageId = back and M.imageFor(back.id)
	if imageId then
		local art = Instance.new("ImageLabel")
		art.Name = "Art"
		art.Size = UDim2.fromScale(1, 1)
		art.BackgroundTransparency = 1
		art.Image = imageId
		art.ScaleType = Enum.ScaleType.Crop
		art.ImageColor3 = opts.locked and LOCKED_TINT or Color3.new(1, 1, 1)
		art.Active = false
		art.ZIndex = z + 1
		art.Parent = frame
	else
		local icon = Instance.new("TextLabel")
		icon.Size = UDim2.fromScale(1, 1)
		icon.BackgroundTransparency = 1
		icon.Font = Enum.Font.GothamBold
		icon.TextSize = 34
		icon.Text = back and back.icon or "?"
		icon.TextTransparency = opts.locked and 0.5 or 0
		icon.TextColor3 = back and rgb(back.colors.trim) or Color3.fromRGB(140, 130, 120)
		icon.ZIndex = z + 1
		icon.Parent = frame
		if opts.locked then
			frame.BackgroundColor3 = Color3.fromRGB(70, 62, 54)
		end
	end

	if opts.shimmer ~= false and not opts.locked then
		local strip = Instance.new("Frame")
		strip.Name = "Shimmer"
		strip.AnchorPoint = Vector2.new(0.5, 0.5)
		strip.Size = UDim2.new(0, 10, 1.6, 0)
		strip.Position = UDim2.fromScale(-0.4, 0.5)
		strip.Rotation = 20
		strip.BackgroundColor3 = Color3.new(1, 1, 1)
		strip.BackgroundTransparency = 1
		strip.BorderSizePixel = 0
		strip.Active = false
		strip.ZIndex = z + 3
		strip.Parent = frame
		startShimmer(frame, strip, opts.isActive)
	end

	return frame
end

return M
