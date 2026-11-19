--[[
	Client/GuidedHint.lua
	The guided first hand hint (Engine/GuidedHand): a small two line parchment plate between the Patron row and the hand and a gold
	outline on the first card, then on Play Hand, until the first hand is played. Display only: it never takes clicks and never
	changes the run. The outline pulses only when Calm mode is off.

	update(layer, state, selectedCount, firstCard, playButton, r)   r = Layout rects of the screen (pixels)
]]

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Engine = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine")
local Guided = require(Engine:WaitForChild("GuidedHand"))
local ClientSettings = require(script.Parent.ClientSettings)

local M = {}
local plate, line1, line2, outline, outlineOn

local GOLD = Color3.fromRGB(246, 196, 70)

local function build(layer)
	plate = Instance.new("Frame")
	plate.Name = "GuidedHint"
	plate.AnchorPoint = Vector2.new(0.5, 0)
	plate.BackgroundColor3 = Color3.fromRGB(46, 28, 14)
	plate.BackgroundTransparency = 0.05
	plate.BorderSizePixel = 0
	plate.Active = false
	plate.ZIndex = 30
	plate.Parent = layer
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 10); c.Parent = plate
	local st = Instance.new("UIStroke"); st.Color = GOLD; st.Thickness = 2; st.Parent = plate
	local function line(name, y, size, color)
		local t = Instance.new("TextLabel")
		t.Name = name
		t.BackgroundTransparency = 1
		t.Font = Enum.Font.GothamBold
		t.TextSize = size
		t.TextColor3 = color
		t.TextTransparency = 0
		t.TextStrokeTransparency = 1
		t.Size = UDim2.new(1, -16, 0.5, 0)
		t.Position = UDim2.new(0, 8, y, 0)
		t.ZIndex = 31
		t.Parent = plate
		return t
	end
	line1 = line("Line1", 0, 18, Color3.fromRGB(255, 244, 214))
	line2 = line("Line2", 0.5, 15, Color3.fromRGB(235, 218, 180))
	outline = Instance.new("UIStroke")
	outline.Name = "GuidedOutline"
	outline.Color = GOLD
	outline.Thickness = 4
	outline.Enabled = false
end

function M.update(layer, state, selectedCount, firstCard, playButton, r)
	local calm = ClientSettings.get("reduceShake") == true
	local hint = Guided.hint(state and state.guidedFirstHand == true, state and state.handsPlayedTotal, selectedCount, calm)
	if not plate or plate.Parent ~= layer then build(layer) end
	if not hint then
		plate.Visible = false
		outline.Enabled = false
		outline.Parent = nil
		return
	end
	plate.Visible = true
	line1.Text, line2.Text = hint.line1, hint.line2
	local w, h = math.max(220, math.floor(r.stage.w * 0.8)), math.max(52, math.floor(r.stage.h * 0.45))
	plate.Size = UDim2.fromOffset(w, h)
	plate.Position = UDim2.fromOffset(r.stage.x + r.stage.w / 2, r.stage.y)
	local target = hint.target == "card" and firstCard or playButton
	if target and target.Parent then
		if outline.Parent ~= target then outline.Parent = target end
		outline.Enabled = true
		if hint.pulse and outlineOn ~= target then
			outlineOn = target
			outline.Transparency = 0
			TweenService:Create(outline, TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Transparency = 0.6 }):Play()
		elseif not hint.pulse then
			outlineOn = nil
			outline.Transparency = 0
		end
	end
end

return M
