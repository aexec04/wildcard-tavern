--[[
	Client/ClassicCardFrame.lua
	The Classic Tavern card edge: a thin 1 px brass stroke on the card, no oak band and no corner caps.
	(Engine/HudStyle.classicFrame still describes the old band geometry; it is no longer drawn.) Called from SetSkin.cardLayers for the neutral default set.

	ClassicCardFrame.draw(face, zIndex)   adds a child "ClassicFrame" to the card face; refits when the card resizes
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HudStyle = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("HudStyle"))

local ClassicCardFrame = {}

local function c3(t)
	return Color3.fromRGB(t[1], t[2], t[3])
end

local function bar(parent, name, color, z)
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundColor3 = c3(color)
	f.BorderSizePixel = 0
	f.Active = false
	f.ZIndex = z
	f.Parent = parent
	return f
end

function ClassicCardFrame.draw(face, zIndex)
	local old = face:FindFirstChild("ClassicFrame")
	if old then old:Destroy() end
	local holder = Instance.new("Frame")
	holder.Name = "ClassicFrame"
	holder.Size = UDim2.fromScale(1, 1)
	holder.BackgroundTransparency = 1
	holder.BorderSizePixel = 0
	holder.Active = false
	holder.ClipsDescendants = true
	holder.ZIndex = zIndex + 1
	holder.Parent = face
	local corner = Instance.new("UICorner")
	local faceCorner = face:FindFirstChildOfClass("UICorner") -- match the card's own corner radius
	corner.CornerRadius = faceCorner and faceCorner.CornerRadius or UDim.new(0, 6)
	corner.Parent = holder

	-- Thin edge only: one 1 px brass stroke on the transparent holder. The oak band and brass corner caps
	-- (the heavy dark frame and the pale gold corner blocks) are no longer built.
	local stroke = Instance.new("UIStroke")
	stroke.Name = "BrassEdge"
	stroke.Thickness = 1
	stroke.Color = c3(HudStyle.CLASSIC_BRASS)
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = holder
	if not ClassicCardFrame._warned then
		ClassicCardFrame._warned = true
		warn("[CardEdge] hidden: the oak bands and the four corner cap blocks (ClassicFrame); kept: 1 px BrassEdge stroke, radius " .. tostring(corner.CornerRadius.Offset))
	end
	return holder
end

return ClassicCardFrame
