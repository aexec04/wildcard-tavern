--[[
	Client/SortGlideFX.lua
	Smooth reorder when Rank or Suit sorting rebuilds the hand. Numbers are Engine/SortGlide (tested).

	capture(handFrame)       -> { [handIndex] = slot centre X } read before the hand is rebuilt
	play(handFrame, before)  after the rebuild: each card that changed place starts where it was and slides to its resting spot
	                         (the fan position the slot carries). Calm mode and Reduce motion: nothing, cards stay where the sort put them.
	Only the card button moves, never its slot, so clicks, hover and the layout are untouched; a hover or tween from another module
	simply overrides the glide.
]]

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Engine = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine")
local Glide = require(Engine:WaitForChild("SortGlide"))
local ClientSettings = require(script.Parent.ClientSettings)

local M = {}

local function calm()
	local ok, v = pcall(function() return ClientSettings.get("reduceShake") end)
	return ok and v == true
end

local function fast()
	local ok, v = pcall(function() return ClientSettings.get("animSpeed") end)
	return ok and v == "fast"
end

local function slots(handFrame)
	local out = {}
	for _, c in ipairs(handFrame:GetChildren()) do
		local idx = c:IsA("Frame") and c:GetAttribute("HandIndex")
		if idx then out[#out + 1] = { slot = c, index = idx } end
	end
	table.sort(out, function(a, b) return a.slot.LayoutOrder < b.slot.LayoutOrder end)
	return out
end

function M.capture(handFrame)
	local map = {}
	if calm() or not handFrame then return map end
	for _, s in ipairs(slots(handFrame)) do map[s.index] = s.slot.AbsolutePosition.X + s.slot.AbsoluteSize.X / 2 end
	return map
end

function M.play(handFrame, before)
	if calm() or not handFrame or next(before or {}) == nil then return end
	local timing = Glide.timing(false, fast())
	task.defer(function()
		if not handFrame.Parent then return end
		local list = slots(handFrame)
		local after = {}
		for _, s in ipairs(list) do after[s.index] = s.slot.AbsolutePosition.X + s.slot.AbsoluteSize.X / 2 end
		local offs = Glide.offsets(before, after)
		for order, s in ipairs(list) do
			local dx = offs[s.index]
			local button = dx and s.slot:FindFirstChildWhichIsA("TextButton")
			if button then
				local rest = UDim2.new(0.5, s.slot:GetAttribute("FanX") or 0, 0.5, s.slot:GetAttribute("FanY") or 0)
				button.Position = UDim2.new(rest.X.Scale, rest.X.Offset + dx, rest.Y.Scale, rest.Y.Offset)
				task.delay(Glide.delay(order, #list, fast()), function()
					if not button.Parent then return end
					TweenService:Create(button, TweenInfo.new(timing.time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = rest }):Play()
				end)
			end
		end
	end)
end

return M
