--[[
	Client/SortToggle.lua
	One small segmented "Rank | Suit" toggle for Sort Hand, in the equipped Card Set's colours (Engine/HudStyle, text at
	4.5:1). The picked half is lit with the set accent; picking the same half again leaves the sort as it is (the hub keeps
	the as-dealt order until a half is first picked). Replaces the two old Sort Rank and Sort Suit buttons.

	SortToggle.build(parent, onPick)  -> { frame, rank, suit, setMode }
	  onPick(mode)    "rank" | "suit", called on a click
	  setMode(mode)   "rank" | "suit" | nil, lights the picked half

	The halves are TextButtons named SortRank and SortSuit with the attribute Segment (Client/ActionButtonFX skips them).
	Everything is a child of the toggle frame, so Clone() keeps it.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HudStyle = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("HudStyle"))
local HudTheme = require(script.Parent.HudTheme)

local SortToggle = {}

local function c3(t)
	return Color3.fromRGB(t[1], t[2], t[3])
end

function SortToggle.build(parent, onPick)
	local frame = Instance.new("Frame")
	frame.Name = "SortToggle"
	frame.Size = UDim2.fromOffset(150, 36)
	frame.BackgroundTransparency = 0
	frame.BorderSizePixel = 0
	frame.LayoutOrder = 2
	frame.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = frame
	local inner = Instance.new("UIStroke")
	inner.Thickness = 2
	inner.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	inner.Parent = frame

	-- dark outer ring, a sibling frame just outside (a UIStroke holds only one colour)
	local outer = Instance.new("Frame")
	outer.Name = "ToggleOuter"
	outer.AnchorPoint = Vector2.new(0.5, 0.5)
	outer.Position = UDim2.fromScale(0.5, 0.5)
	outer.Size = UDim2.new(1, 6, 1, 6)
	outer.BackgroundTransparency = 1
	outer.BorderSizePixel = 0
	outer.Active = false
	outer.ZIndex = 0
	outer.Parent = frame
	local oc = Instance.new("UICorner")
	oc.CornerRadius = UDim.new(0, 12)
	oc.Parent = outer
	local os = Instance.new("UIStroke")
	os.Thickness = 3
	os.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	os.Parent = outer

	local function half(name, text, x)
		local b = Instance.new("TextButton")
		b.Name = name
		b.Size = UDim2.new(0.5, -5, 1, -6) -- an inset pill inside the rounded track
		b.Position = UDim2.new(x, x == 0 and 3 or 2, 0, 3)
		local pill = Instance.new("UICorner")
		pill.CornerRadius = UDim.new(0, 8)
		pill.Parent = b
		b.BorderSizePixel = 0
		b.AutoButtonColor = false
		b.Font = Enum.Font.Fondamento
		b.TextSize = 18
		b.Text = text
		b.TextTransparency = 0
		b.TextStrokeTransparency = 1
		b.ZIndex = 2
		b:SetAttribute("Segment", true)
		b:SetAttribute("HudThemed", true)
		b.Parent = frame
		return b
	end
	local rank = half("SortRank", "Rank", 0)
	local suit = half("SortSuit", "Suit", 0.5)

	local divider = Instance.new("Frame")
	divider.Name = "Divider"
	divider.AnchorPoint = Vector2.new(0.5, 0)
	divider.Position = UDim2.fromScale(0.5, 0.2)
	divider.Size = UDim2.new(0, 2, 0.6, 0)
	divider.BorderSizePixel = 0
	divider.ZIndex = 3
	divider.Active = false
	divider.Parent = frame

	local mode = nil
	local hoverKey = nil
	local function paint()
		local p = HudStyle.buttonPalette(HudTheme.skin().colors, "sort")
		frame.BackgroundColor3 = c3(p.fill)
		inner.Color = c3(p.inner)
		os.Color = c3(p.outer)
		divider.BackgroundColor3 = c3(p.inner)
		for key, b in pairs({ rank = rank, suit = suit }) do
			local on = mode == key
			local lit = on or hoverKey == key
			b.BackgroundTransparency = lit and 0 or 1
			b.BackgroundColor3 = c3(on and p.active or p.hover)
			local tc = on and p.activeText or p.text
			b.TextColor3 = c3(tc)
			local lum = (tc[1] * 0.299 + tc[2] * 0.587 + tc[3] * 0.114) / 255
			b.TextStrokeColor3 = Color3.fromRGB(20, 12, 6)
			b.TextStrokeTransparency = lum > 0.55 and 0.55 or 1
		end
	end
	for key, b in pairs({ rank = rank, suit = suit }) do
		b.MouseEnter:Connect(function() hoverKey = key paint() end)
		b.MouseLeave:Connect(function() if hoverKey == key then hoverKey = nil end paint() end)
		b.MouseButton1Click:Connect(function() onPick(key) end)
	end
	HudTheme.onSkin(function()
		if frame.Parent then paint() end
	end)
	paint()

	return {
		frame = frame, rank = rank, suit = suit,
		setMode = function(m) mode = m paint() end,
	}
end

return SortToggle
