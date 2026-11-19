--[[
	Client/GuidedHint.lua
	The guided first hand hint (Engine/GuidedHand): a small two line parchment plate between the Patron row and the hand and a gold
	outline on the first card, then on Play Hand, until the first hand is played. Display only: it never takes clicks and never
	changes the run. The outline pulses only when Calm mode is off.

	update(layer, state, selectedCount, firstCard, playButton, r, cards)   r = Layout rects of the screen (pixels); cards = the hand's card
	buttons (the first two get the outline). A small Skip plate beside the hint ends it; it is the only thing here that takes a click.
]]

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Engine = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine")
local Guided = require(Engine:WaitForChild("GuidedHand"))
local ClientSettings = require(script.Parent.ClientSettings)

local M = {}
local plate, line1, line2, outline, outline2, outlineOn, skipBtn
local skipped = false -- Skip hides the hint for the rest of this session; the server flag already makes it once per profile

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
	outline2 = outline:Clone()
	outline2.Name = "GuidedOutline2"
	skipBtn = Instance.new("TextButton")
	skipBtn.Name = "GuidedSkip"
	skipBtn.ZIndex = 32
	pcall(function() require(script.Parent.TavernKit).skin(skipBtn, "Skip", "secondary") end)
	skipBtn.Parent = layer
	skipBtn.MouseButton1Click:Connect(function() skipped = true; M.hide() end)
end

function M.hide()
	if plate then plate.Visible = false end
	if skipBtn then skipBtn.Visible = false end
	if outline then outline.Enabled = false; outline.Parent = nil end
	if outline2 then outline2.Enabled = false; outline2.Parent = nil end
end

function M.update(layer, state, selectedCount, firstCard, playButton, r, cards)
	local calm = ClientSettings.get("reduceShake") == true
	local hint = Guided.hint(state and state.guidedFirstHand == true, state and state.handsPlayedTotal, selectedCount, calm)
	if not plate or plate.Parent ~= layer then build(layer) end
	if not hint or skipped then
		M.hide()
		return
	end
	plate.Visible = true
	line1.Text, line2.Text = hint.line1, hint.line2
	local pr = Guided.plateRect(r, layer.AbsoluteSize.Y)
	-- a short window leaves under 44 px: one line only, so nothing is cut
	local one = pr.h < 44
	line2.Visible = not one
	line1.Size = UDim2.new(1, -16, one and 1 or 0.5, 0)
	line1.TextSize = one and math.max(14, math.min(18, pr.h - 6)) or 18
	plate.Size = UDim2.fromOffset(pr.w, pr.h)
	plate.Position = UDim2.fromOffset(pr.x + pr.w / 2, pr.y)
	local sr = Guided.skipRect(pr, layer.AbsoluteSize.X)
	skipBtn.Visible = true
	skipBtn.Size = UDim2.fromOffset(sr.w, sr.h)
	skipBtn.Position = UDim2.fromOffset(sr.x, sr.y)
	local target = hint.target == "card" and firstCard or playButton
	outline2.Enabled = false
	outline2.Parent = nil
	if hint.target == "card" and cards and cards[2] and cards[2].Parent then
		outline2.Parent = cards[2]
		outline2.Enabled = true
	end
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
