--[[
	Client/PatronCalloutFX.lua
	The serif popup above a Patron card when it triggers: rises 24 px and fades over 0.6 s in the kind colour (green for
	Chips and Mult, blue for x Mult, gold for money). Numbers in Engine/PatronCallout (tested). Calm mode and Reduce motion
	show a static label for 0.4 s with no tween. One popup at a time per card key, in order.

	show(parent, key, text, kind, x, topY) -> starts (or queues) the popup; x is the card centre, topY the card top edge
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local PC = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("PatronCallout"))
local ClientSettings = require(script.Parent.ClientSettings)

local M = {}
local freeAt = {} -- [key] = os.clock() time the card's last popup ends

local function calm()
	local ok, v = pcall(function() return ClientSettings.get("reduceShake") end)
	return ok and v == true
end

function M.show(parent, key, text, kind, x, topY)
	if not parent or not parent.Parent or text == "" then return nil end
	local isCalm = calm()
	local spec = PC.spec(isCalm)
	local now = os.clock()
	local startAt, endAt = PC.schedule(now, freeAt[key], isCalm)
	freeAt[key] = endAt
	local c = PC.color(kind)
	local label = Instance.new("TextLabel")
	label.Name = "PatronCallout"
	label.AnchorPoint = Vector2.new(0.5, 1)
	label.Position = UDim2.fromOffset(x, topY)
	label.AutomaticSize = Enum.AutomaticSize.X
	label.Size = UDim2.fromOffset(0, 26)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.Garamond
	label.TextSize = 22
	label.TextColor3 = Color3.fromRGB(c[1], c[2], c[3])
	label.TextTransparency = 1
	label.TextStrokeColor3 = Color3.fromRGB(28, 18, 10)
	label.TextStrokeTransparency = 1
	label.Text = text
	label.ZIndex = 80
	label.Active = false
	label.Visible = false
	label.Parent = parent
	task.delay(math.max(0, startAt - now), function()
		if not label.Parent then return end
		label.Visible = true
		label.TextTransparency = 0
		label.TextStrokeTransparency = 0.2
		if spec.static then
			task.delay(spec.dur, function() if label.Parent then label:Destroy() end end)
			return
		end
		local info = TweenInfo.new(spec.dur, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		TweenService:Create(label, info, { Position = UDim2.fromOffset(x, topY - spec.rise), TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		task.delay(spec.dur + 0.05, function() if label.Parent then label:Destroy() end end)
	end)
	return label
end

return M
