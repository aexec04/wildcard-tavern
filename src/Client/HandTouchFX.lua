--[[
	Client/HandTouchFX.lua
	Touch controls for the hand and the Patron row (numbers and maths are the tested Engine/TouchGestures):
	  - a tap selects a card through the hub's normal click (the hub lifts it 24 px), a second tap deselects
	  - dragging a hand card sideways reorders the hand; neighbours slide aside over 0.12 s and a soft card_flip cue plays
	    on drop. Reordering is cosmetic: only LayoutOrder changes, the server's hand is never touched
	  - holding a card 0.35 s shows its tooltip (hand card here, Patron card through PatronRow)
	Touch input only, so mouse hover and click on desktop are unchanged. Calm mode and Reduce motion: the same result with no
	tween (the slide and the return are direct writes).

	HandTouchFX.attach(handFrame, slot, button, opts)   opts = { card, onReorder(map index -> position) }
	HandTouchFX.press(guiObject, onLong, onEnd)         long press helper for any object (used by PatronRow)
	HandTouchFX.swallow() -> true while a click that follows a drag or long press must be ignored
]]

local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Engine = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine")
local TG = require(Engine:WaitForChild("TouchGestures"))
local CardData = require(Engine:WaitForChild("Card"))
local ClientSettings = require(script.Parent.ClientSettings)
local Cue = require(script.Parent.Cue)

local M = {}

local swallowUntil = 0
local tipPlate = nil

local function calm()
	local ok, v = pcall(function() return ClientSettings.get("reduceShake") end)
	return ok and v == true
end

function M.swallow()
	return os.clock() < swallowUntil
end

local function markSwallow()
	swallowUntil = os.clock() + TG.SWALLOW
end

local function hideTip()
	if tipPlate then tipPlate:Destroy() tipPlate = nil end
end

-- a small dark wood plate with cream text above (or below) the card, kept on screen
local function showTip(anchor, text)
	hideTip()
	local gui = anchor:FindFirstAncestorOfClass("ScreenGui")
	if not gui or text == "" then return end
	local plate = Instance.new("TextLabel")
	plate.Name = "HandTouchTip"
	plate.BackgroundColor3 = Color3.fromRGB(46, 30, 17)
	plate.BackgroundTransparency = 0.06
	plate.TextColor3 = Color3.fromRGB(245, 232, 200)
	plate.Font = Enum.Font.Merriweather
	plate.TextSize = 16
	plate.TextWrapped = true
	plate.Text = text
	plate.ZIndex = 400
	local w = 260
	local lines = math.max(1, math.ceil(#text / 30)) + select(2, text:gsub("\n", ""))
	local h = 20 + lines * 20
	plate.Size = UDim2.fromOffset(w, h)
	local screen = gui.AbsoluteSize
	local ap, as = anchor.AbsolutePosition, anchor.AbsoluteSize
	local x = math.clamp(ap.X + as.X / 2 - w / 2, 8, math.max(8, screen.X - w - 8))
	local y = ap.Y - h - 8
	if y < 8 then y = math.min(ap.Y + as.Y + 8, math.max(8, screen.Y - h - 8)) end
	plate.Position = UDim2.fromOffset(x - gui.AbsolutePosition.X, y - gui.AbsolutePosition.Y)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = plate
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(214, 168, 70)
	stroke.Thickness = 1
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = plate
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 10), UDim.new(0, 10)
	pad.Parent = plate
	plate.Parent = gui
	tipPlate = plate
end

-- press and hold on any object: onLong() after 0.35 s without moving, onEnd() when the finger lifts
function M.press(obj, onLong, onEnd)
	obj.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.Touch then return end
		local start = input.Position
		local done = false
		task.delay(TG.LONG_PRESS, function()
			if done or input.UserInputState == Enum.UserInputState.End then return end
			local d = (input.Position - start).Magnitude
			if TG.classify(d, TG.LONG_PRESS, false) == "long" then
				markSwallow()
				onLong()
			end
		end)
		local conn
		conn = input.Changed:Connect(function()
			if input.UserInputState == Enum.UserInputState.End then
				done = true
				conn:Disconnect()
				if onEnd then onEnd() end
			end
		end)
	end)
end

local function sortedSlots(handFrame)
	local slots = {}
	for _, c in ipairs(handFrame:GetChildren()) do
		if c:IsA("Frame") and c:GetAttribute("HandIndex") then slots[#slots + 1] = c end
	end
	table.sort(slots, function(a, b) return a.LayoutOrder < b.LayoutOrder end)
	return slots
end

local function restPosition(button)
	local slot = button.Parent
	return UDim2.new(0.5, slot:GetAttribute("FanX") or 0, 0.5, slot:GetAttribute("FanY") or 0)
end

function M.attach(handFrame, slot, button, opts)
	local drag = nil -- { input, startX, startY, t0, state }

	local function finish()
		if not drag then return end
		local d = drag
		drag = nil
		hideTip()
		if d.state == "drag" then
			markSwallow()
			local rest = restPosition(button)
			local motion = TG.motion(calm())
			if motion then
				TweenService:Create(button, TweenInfo.new(motion.drop, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = rest }):Play()
			else
				button.Position = rest
			end
			Cue.play(TG.CUE)
			if opts.onReorder then
				local map = {}
				for pos, s in ipairs(sortedSlots(handFrame)) do map[s:GetAttribute("HandIndex")] = pos end
				opts.onReorder(map)
			end
		elseif d.state == "long" then
			markSwallow()
		end
	end

	button.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.Touch or drag then return end
		drag = { input = input, startX = input.Position.X, startY = input.Position.Y, t0 = os.clock(), state = "pending" }
		local d = drag
		task.delay(TG.LONG_PRESS, function()
			if drag ~= d or d.state ~= "pending" then return end
			local dist = (Vector2.new(d.input.Position.X, d.input.Position.Y) - Vector2.new(d.startX, d.startY)).Magnitude
			if TG.classify(dist, TG.LONG_PRESS, false) == "long" then
				d.state = "long"
				markSwallow()
				showTip(button, TG.cardTip(opts.card, CardData))
			end
		end)
		local conn
		conn = input.Changed:Connect(function()
			if input.UserInputState == Enum.UserInputState.End then
				conn:Disconnect()
				finish()
			end
		end)
	end)

	UserInputService.InputChanged:Connect(function(input)
		local d = drag
		if not d or input ~= d.input or not slot.Parent then return end
		local dx = input.Position.X - d.startX
		if d.state == "pending" and TG.classify(math.abs(dx), os.clock() - d.t0, false) == "drag" then
			d.state = "drag"
			hideTip()
		end
		if d.state ~= "drag" then return end
		-- the card follows the finger; the slot it sits in is the one nearest the finger
		local slots = sortedSlots(handFrame)
		local centers, mine = {}, nil
		for i, s in ipairs(slots) do
			centers[i] = s.AbsolutePosition.X + s.AbsoluteSize.X / 2
			if s == slot then mine = i end
		end
		local target = TG.slotAt(input.Position.X, centers)
		if mine and target and target ~= mine then
			-- the layout settles on the next frame, so work from the positions read before the change
			local oldX, xs = {}, {}
			for i, s in ipairs(slots) do oldX[s] = s.AbsolutePosition.X xs[i] = s.AbsolutePosition.X end
			local newOrder = TG.reorder(slots, mine, target)
			for i, s in ipairs(newOrder) do s.LayoutOrder = i end
			d.cx = centers[target]
			local motion = TG.motion(calm())
			if motion then
				for _, s in ipairs(newOrder) do
					local b = s:FindFirstChildOfClass("TextButton")
					local newX = xs[table.find(newOrder, s)]
					if s ~= slot and b and newX ~= oldX[s] then
						-- the layout moved the slot at once; start the card where it was and slide it in
						local rest = restPosition(b)
						b.Position = rest + UDim2.fromOffset(oldX[s] - newX, 0)
						TweenService:Create(b, TweenInfo.new(motion.slide, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = rest }):Play()
					end
				end
			end
		end
		local cx = d.cx or (slot.AbsolutePosition.X + slot.AbsoluteSize.X / 2)
		local scale = slot:FindFirstChild("DepthScale")
		local k = (scale and scale.Scale > 0) and scale.Scale or 1
		button.Position = restPosition(button) + UDim2.fromOffset((input.Position.X - cx) / k, 0)
	end)
end

return M
