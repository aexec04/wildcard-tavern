--[[
	Client/RarityFrame.lua
	One reusable rarity frame for any GuiObject (Collection tiles and detail card,
	Shop cards, pack reveals, the unlock popup, sidebar patron seats).

	  RarityFrame.apply(frame, rarityId, opts) -> { stroke = UIStroke, destroy = fn }

	Looks (rarity ids come from CollectionBook.RarityOrder):
	  common     plain wood-brown frame
	  uncommon   green frame with a small gem on top
	  rare       blue frame with silver filigree corners
	  epic       purple frame with a slow shimmer sweep
	  legendary  gold ornate frame, soft pulsing glow and a few drifting sparks
	  mythical   prismatic border (UIGradient Color stops cycling slowly) with sparkles

	opts:
	  thickness   stroke thickness (default 2; 3 for big frames)
	  ringOnly    only the stroke color (sidebar seats): no ornaments, no motion
	  locked      silhouette: dim tier color, no ornaments, no motion
	  zIndex      ZIndex for the ornaments (default frame.ZIndex + 3)
	  radius      corner radius used to clip the shimmer (default 8)

	Only Color stops are ever touched on UIGradient (never Transparency).
	Motion is skipped under the "Reduce screen shake" setting; loops stop when
	the frame is destroyed or hidden. Ornaments live inside one child named
	"RarityOrnaments", so apply() can be called again on the same frame.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local CollectionBook = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("CollectionBook"))
local ClientSettings = require(script.Parent.ClientSettings)

local M = {}

local WOOD = Color3.fromRGB(120, 88, 56)
local SILVER = Color3.fromRGB(215, 222, 232)
local GOLD_LIGHT = Color3.fromRGB(255, 232, 160)

local function rgb(t)
	return Color3.fromRGB(t[1], t[2], t[3])
end

local function reduced()
	local ok, value = pcall(function()
		return ClientSettings.get("reduceShake")
	end)
	return ok and value == true
end

local function plain(parent, props)
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	f.Active = false
	for k, v in pairs(props) do
		f[k] = v
	end
	f.Parent = parent
	return f
end

-- Runs step() every `interval` seconds while holder is alive and visible.
local function loop(holder, interval, step)
	task.spawn(function()
		while holder.Parent do
			if holder.Parent:IsA("GuiObject") and holder.Parent.Visible then
				pcall(step)
			end
			task.wait(interval)
		end
	end)
end

function M.colorFor(rarityId)
	local def = CollectionBook.Rarities[rarityId] or CollectionBook.Rarities.common
	if rarityId == "common" or not CollectionBook.Rarities[rarityId] then
		return WOOD
	end
	return rgb(def.color)
end

function M.apply(frame, rarityId, opts)
	opts = opts or {}
	if not CollectionBook.Rarities[rarityId] then
		rarityId = "common"
	end
	local color = M.colorFor(rarityId)
	local thickness = opts.thickness or 2

	local old = frame:FindFirstChild("RarityOrnaments")
	if old then
		old:Destroy()
	end
	local stroke = frame:FindFirstChild("RarityStroke")
	if not stroke then
		stroke = Instance.new("UIStroke")
		stroke.Name = "RarityStroke"
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Parent = frame
	end
	local oldGradient = stroke:FindFirstChildOfClass("UIGradient")
	if oldGradient then
		oldGradient:Destroy()
	end
	stroke.Thickness = thickness
	stroke.Transparency = 0
	stroke.Color = opts.locked and color:Lerp(Color3.fromRGB(40, 36, 32), 0.55) or color

	local handle = { stroke = stroke }
	function handle.destroy()
		local o = frame:FindFirstChild("RarityOrnaments")
		if o then
			o:Destroy()
		end
		stroke:Destroy()
	end

	if opts.ringOnly or opts.locked then
		return handle
	end

	local z = opts.zIndex or (frame.ZIndex + 3)
	local radius = opts.radius or 8
	local still = reduced()

	local holder = plain(frame, {
		Name = "RarityOrnaments",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		ZIndex = z,
	})
	local holderCorner = Instance.new("UICorner")
	holderCorner.CornerRadius = UDim.new(0, radius)
	holderCorner.Parent = holder

	if rarityId == "uncommon" then
		-- a small green gem set on the top edge
		local gem = plain(holder, {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 2),
			Size = UDim2.fromOffset(10, 10),
			Rotation = 45,
			BackgroundColor3 = Color3.fromRGB(110, 215, 140),
			ZIndex = z,
		})
		local gemStroke = Instance.new("UIStroke")
		gemStroke.Color = Color3.fromRGB(40, 100, 60)
		gemStroke.Thickness = 1
		gemStroke.Parent = gem
	elseif rarityId == "rare" then
		-- silver filigree corners: two short bars per corner
		for _, corner in ipairs({ { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 } }) do
			local ax, ay = corner[1], corner[2]
			plain(holder, {
				AnchorPoint = Vector2.new(ax, ay),
				Position = UDim2.new(ax, ax == 0 and 3 or -3, ay, ay == 0 and 3 or -3),
				Size = UDim2.fromOffset(14, 2),
				BackgroundColor3 = SILVER,
				ZIndex = z,
			})
			plain(holder, {
				AnchorPoint = Vector2.new(ax, ay),
				Position = UDim2.new(ax, ax == 0 and 3 or -3, ay, ay == 0 and 3 or -3),
				Size = UDim2.fromOffset(2, 14),
				BackgroundColor3 = SILVER,
				ZIndex = z,
			})
		end
	elseif rarityId == "epic" then
		-- A soft upright band that sweeps across INSIDE the frame. It is not rotated and never leaves the frame's bounds: Roblox ignores
		-- ClipsDescendants under a rotated ancestor (the tilted Counter cards), so a rotated or overshooting strip escaped as a diagonal streak.
		local strip = plain(holder, {
			AnchorPoint = Vector2.new(0, 0),
			Position = UDim2.fromScale(0, 0),
			Size = UDim2.fromScale(0.22, 1),
			BackgroundColor3 = Color3.fromRGB(235, 215, 255),
			BackgroundTransparency = 0.8,
			ZIndex = z,
		})
		if not still then
			loop(holder, 3.2, function()
				strip.Position = UDim2.fromScale(0, 0)
				TweenService:Create(strip, TweenInfo.new(1.1, Enum.EasingStyle.Sine), {
					Position = UDim2.fromScale(0.78, 0),
				}):Play()
			end)
		end
	elseif rarityId == "legendary" then
		-- gold ornate frame: inner second ring, pulsing outer stroke, drifting sparks
		local inner = plain(holder, {
			Position = UDim2.fromOffset(3, 3),
			Size = UDim2.new(1, -6, 1, -6),
			BackgroundTransparency = 1,
			ZIndex = z,
		})
		local innerCorner = Instance.new("UICorner")
		innerCorner.CornerRadius = UDim.new(0, math.max(2, radius - 2))
		innerCorner.Parent = inner
		local innerStroke = Instance.new("UIStroke")
		innerStroke.Color = GOLD_LIGHT
		innerStroke.Thickness = 1
		innerStroke.Transparency = 0.35
		innerStroke.Parent = inner
		if not still then
			TweenService:Create(stroke, TweenInfo.new(1.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
				Thickness = thickness + 1.5,
			}):Play()
			for i = 1, 3 do
				local spark = plain(holder, {
					Size = UDim2.fromOffset(4, 4),
					Rotation = 45,
					BackgroundColor3 = GOLD_LIGHT,
					BackgroundTransparency = 1,
					ZIndex = z + 1,
				})
				local sparkIndex = i
				task.spawn(function()
					task.wait(sparkIndex * 0.7)
					while spark.Parent do
						if holder.Parent and holder.Parent:IsA("GuiObject") and holder.Parent.Visible then
							spark.Position = UDim2.new(0.15 + 0.3 * ((sparkIndex + math.random()) % 3) / 2, 0, 1, -4)
							spark.BackgroundTransparency = 0.1
							TweenService:Create(spark, TweenInfo.new(2.2, Enum.EasingStyle.Sine), {
								Position = UDim2.new(spark.Position.X.Scale, 0, 0.1, 0),
								BackgroundTransparency = 1,
							}):Play()
						end
						task.wait(2.4)
					end
				end)
			end
		end
	elseif rarityId == "mythical" then
		local gradient = Instance.new("UIGradient")
		gradient.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 110, 150)),
			ColorSequenceKeypoint.new(0.25, Color3.fromRGB(255, 220, 110)),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(110, 240, 190)),
			ColorSequenceKeypoint.new(0.75, Color3.fromRGB(120, 170, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 110, 150)),
		})
		gradient.Parent = stroke
		stroke.Color = Color3.fromRGB(255, 255, 255)
		if not still then
			-- slow color cycle by rotating the stops around the border
			TweenService:Create(gradient, TweenInfo.new(6, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1), {
				Rotation = 360,
			}):Play()
			for i = 1, 4 do
				local sparkle = plain(holder, {
					AnchorPoint = Vector2.new(0.5, 0.5),
					Size = UDim2.fromOffset(5, 5),
					Rotation = 45,
					BackgroundColor3 = Color3.fromRGB(255, 255, 255),
					BackgroundTransparency = 1,
					ZIndex = z + 1,
				})
				local sparkleIndex = i
				task.spawn(function()
					task.wait(sparkleIndex * 0.45)
					while sparkle.Parent do
						if holder.Parent and holder.Parent:IsA("GuiObject") and holder.Parent.Visible then
							sparkle.Position = UDim2.fromScale(0.1 + 0.8 * math.random(), 0.1 + 0.8 * math.random())
							sparkle.BackgroundTransparency = 0.1
							TweenService:Create(sparkle, TweenInfo.new(0.9, Enum.EasingStyle.Sine), {
								BackgroundTransparency = 1,
							}):Play()
						end
						task.wait(1.8)
					end
				end)
			end
		end
	end

	return handle
end

return M
