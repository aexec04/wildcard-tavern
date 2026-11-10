--[[
	Client/ClassicCardFrame.lua
	The Classic Tavern card border, drawn in code on the full card edge: a dark oak band (7 percent of the card width on
	every side), a brass line just inside it and small brass corner caps. Geometry comes from Engine/HudStyle.classicFrame
	(tested: at least 6 percent of the width on each side). Called from SetSkin.cardLayers for the neutral default set.

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

	local parts = {}
	for _, side in ipairs({ "top", "bottom", "left", "right" }) do
		parts["band_" .. side] = bar(holder, "Oak_" .. side, HudStyle.CLASSIC_OAK, zIndex + 1)
		parts["line_" .. side] = bar(holder, "Brass_" .. side, HudStyle.CLASSIC_BRASS, zIndex + 1)
	end
	for i = 1, 4 do
		parts["cap" .. i] = bar(holder, "Cap" .. i, HudStyle.CLASSIC_CAP, zIndex + 1)
	end
	local function put(inst, r)
		inst.Position = UDim2.fromOffset(r.x, r.y)
		inst.Size = UDim2.fromOffset(r.w, r.h)
	end
	local function fit()
		local size = face.AbsoluteSize
		if size.X <= 0 or size.Y <= 0 then return end
		local l = HudStyle.classicFrame(size.X, size.Y)
		for _, side in ipairs({ "top", "bottom", "left", "right" }) do
			put(parts["band_" .. side], l.band[side])
			put(parts["line_" .. side], l.line[side])
		end
		for i, r in ipairs(l.caps) do put(parts["cap" .. i], r) end
	end
	fit()
	face:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	return holder
end

return ClassicCardFrame
