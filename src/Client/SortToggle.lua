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
SortToggle.TEXT_SIZE = 18 -- Fondamento draws small; 16 read as about 13 px. Never below 15.

local function c3(t)
	return Color3.fromRGB(t[1], t[2], t[3])
end

function SortToggle.build(parent, onPick)
	local frame = Instance.new("Frame")
	frame.Name = "SortToggle"
	frame.Size = UDim2.fromOffset(132, 28)
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
		b.TextSize = SortToggle.TEXT_SIZE
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
		-- Flat (Concept T play screen): a plain wood pill, no outer ring or divider line, the picked half in warm cream
		local flat = frame:GetAttribute("Flat") == true
		-- Split (Gameplay v2): no shared track; each half is its own brown plate with a gold edge (TavernKit secondary look)
		local split = frame:GetAttribute("Split") == true
		outer.Visible = not flat and not split
		divider.Visible = not flat and not split
		frame.BackgroundTransparency = split and 1 or 0
		inner.Enabled = not split
		frame.BackgroundColor3 = c3(p.fill)
		inner.Color = c3(p.inner)
		os.Color = c3(p.outer)
		divider.BackgroundColor3 = c3(p.inner)
		for key, b in pairs({ rank = rank, suit = suit }) do
			local on = mode == key
			local lit = on or hoverKey == key
			-- the picked half is an inset of the plate itself: a lighter tone of the plate's own wood with a thin gold line, not a flat cream block
			local lighter = flat and Color3.fromRGB(240, 222, 178) or c3(p.fill):Lerp(Color3.fromRGB(205, 160, 96), 0.22)
			local bg = on and lighter or c3(p.hover)
			b.BackgroundTransparency = (lit or split) and 0 or 1
			b.BackgroundColor3 = split and (on and Color3.fromRGB(118, 80, 42) or Color3.fromRGB(78, 50, 26)) or bg -- Gameplay v2: both halves are dark carved wood like Discard, the picked one a lighter wood with the gold glow
			local velvet = (split or flat) and HudStyle.velvetPlate(HudTheme.setId(), HudTheme.skin().colors) or nil -- Golden Gala: the Play Hand and Discard family
			if velvet then
				b.BackgroundColor3 = c3(on and velvet.lit or velvet.fill)
				b.BackgroundTransparency = 0
			end
			if split then bg = b.BackgroundColor3 end
			local tc = c3(p.text)
			if lit then
				local lum = bg.R * 0.299 + bg.G * 0.587 + bg.B * 0.114
				tc = lum > 0.5 and Color3.fromRGB(38, 24, 12) or Color3.fromRGB(246, 232, 200)
			end
			if split then tc = Color3.fromRGB(246, 232, 200) end -- cream lettering on dark wood, well over 4.5:1
			if velvet then tc = c3(on and velvet.litText or velvet.text) end -- the set's own text colour, 4.5:1 on its fill			b.TextColor3 = tc
			local pick = b:FindFirstChild("PickLine")
			if not pick then
				pick = Instance.new("UIStroke")
				pick.Name = "PickLine"
				pick.Thickness = 1
				pick.Color = Color3.fromRGB(214, 176, 92)
				pick.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
				pick.Parent = b
			end
			pick.Enabled = on or split
			pick.Color = split and (on and Color3.fromRGB(255, 214, 102) or Color3.fromRGB(150, 110, 50)) or Color3.fromRGB(214, 176, 92)
			pick.Thickness = split and 1.5 or 1
			b.TextStrokeColor3 = Color3.fromRGB(20, 12, 6)
			b.TextStrokeTransparency = 1
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
	frame:GetAttributeChangedSignal("Flat"):Connect(paint)
	frame:GetAttributeChangedSignal("Split"):Connect(paint)
	paint()

	return {
		frame = frame, rank = rank, suit = suit,
		setMode = function(m) mode = m paint() end,
	}
end

return SortToggle
