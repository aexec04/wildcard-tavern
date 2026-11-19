--[[
	Client/RarityShape.lua
	A small cream marker with a dark outline drawn at the left end of a rarity label pill, one shape per tier (Engine/RarityCues,
	tested), so rarity is never colour alone. Parented to the label so it survives a clone; static, no tweens.

	RarityShape.set(label, tier, px)   px = marker size in pixels (default 12)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Cues = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("RarityCues"))

local M = {}

function M.set(label, tier, px)
	px = px or 12
	local holder = label:FindFirstChild("RarityShape")
	if holder and label:GetAttribute("ShapeTier") == tier then return end -- set() runs on every refresh; rebuild only on a change
	if holder then holder:Destroy() end
	label:SetAttribute("ShapeTier", tier)
	holder = Instance.new("Frame")
	holder.Name = "RarityShape"
	holder.BackgroundTransparency = 1
	holder.BorderSizePixel = 0
	holder.Active = false
	holder.AnchorPoint = Vector2.new(0, 0.5)
	holder.Position = UDim2.new(0, 6, 0.5, 0)
	holder.Size = UDim2.fromOffset(px, px)
	holder.ZIndex = label.ZIndex + 1
	holder.Parent = label
	for _, part in ipairs(Cues.shape(tier).parts) do
		local f = Instance.new("Frame")
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Position = UDim2.fromScale(0.5, 0.5)
		f.Size = UDim2.fromOffset(math.floor(px * part.size), math.floor(px * part.size))
		f.Rotation = part.rot
		f.BackgroundColor3 = Color3.fromRGB(250, 238, 212)
		f.BackgroundTransparency = 0
		f.BorderSizePixel = 0
		f.Active = false
		f.ZIndex = holder.ZIndex
		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.fromRGB(36, 22, 12)
		stroke.Thickness = 1
		stroke.Parent = f
		if part.round then
			local c = Instance.new("UICorner")
			c.CornerRadius = UDim.new(1, 0)
			c.Parent = f
		end
		f.Parent = holder
	end
end

return M
