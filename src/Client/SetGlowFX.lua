--[[
	Client/SetGlowFX.lua
	When a Patron set bonus forms, the member seats at the table glow in the set's accent once for 2.4 seconds (Engine/SetGlow).
	Static outline frames shown then hidden by a timer: no tween, so Calm mode and Reduce motion are the same. Display only.

	SetGlowFX.update(layer, rects, ownedIds)   call on every table refresh; only a newly formed set lights up
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SetGlow = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("SetGlow"))

local M = {}

local known = {}
local token = 0
local Z = 6 -- over the Patron cards' backdrop, under the pills and popups

local function frame(layer, i)
	local f = layer:FindFirstChild("SetGlow" .. i)
	if f then return f end
	f = Instance.new("Frame")
	f.Name = "SetGlow" .. i
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	f.Active = false
	f.ZIndex = Z
	f.Visible = false
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 10); c.Parent = f
	local s = Instance.new("UIStroke"); s.Name = "Ring"; s.Thickness = 3; s.Transparency = 0; s.Parent = f
	f.Parent = layer
	return f
end

local function hideAll(layer)
	local i = 1
	while true do
		local f = layer:FindFirstChild("SetGlow" .. i)
		if not f then break end
		f.Visible = false
		i += 1
	end
end

function M.update(layer, rects, ownedIds)
	local fresh = SetGlow.fresh(known, ownedIds)
	if #fresh == 0 then return end
	token += 1
	local mine = token
	hideAll(layer)
	local used = 0
	for _, set in ipairs(fresh) do
		local a = SetGlow.accent(set.id)
		for _, r in ipairs(SetGlow.rings(rects, set)) do
			used += 1
			local f = frame(layer, used)
			f.Position = UDim2.fromOffset(r.x, r.y)
			f.Size = UDim2.fromOffset(r.w, r.h)
			f.Ring.Color = Color3.fromRGB(a[1], a[2], a[3])
			f.Visible = true
		end
	end
	task.delay(SetGlow.DURATION, function()
		if mine == token and layer.Parent then hideAll(layer) end
	end)
end

return M
