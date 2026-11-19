--[[
	Client/TavernKit.lua
	Shared UI pieces in the look of the main menu and the Night screen, drawn only with Frame, UICorner, UIStroke, UIGradient and
	text (no images, so nothing is stretched). Numbers and colors: Engine/TavernStyle, written up in claude/STYLE-TAVERN.md.

	TavernKit.plate(parent, size)            -> Frame      dark brown plate, thin gold trim
	TavernKit.primaryButton(parent, text)    -> TextButton green, one drawn rect that is also the click rect
	TavernKit.secondaryButton(parent, text)  -> TextButton brown
	TavernKit.pill(parent, text, color)      -> Frame      small rounded chip; color is a TavernStyle.PILLS name
	TavernKit.goldBox(parent, text)          -> Frame      the dark Target box with a gold number
	TavernKit.title(parent, text)            -> TextLabel  serif cream title with a dark outline
	TavernKit.skin(button, text, kind)       style an existing TextButton as primary or secondary (the real instance stays the click target)
	TavernKit.feel(button)                   hover lift and press squeeze, a no-op in Calm mode, Reduce motion and Fast speed

	Gradients are Color only, never Transparency. Position the returned instance yourself.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Style = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("TavernStyle"))

local TavernKit = {}

local function rgb(c) return Color3.fromRGB(c[1], c[2], c[3]) end
local function col(name) return rgb(Style.rgb(name)) end

-- Calm mode, Reduce motion (both end in reduceShake) or Fast speed: no motion at all.
local function still()
	local ok, ClientSettings = pcall(function() return require(script.Parent.ClientSettings) end)
	if not ok then return true end
	return ClientSettings.get("reduceShake") == true or ClientSettings.get("animSpeed") == "fast"
end
TavernKit.still = still

local function corner(inst, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = inst
	return c
end

local function stroke(inst, colorName, thickness)
	local s = Instance.new("UIStroke")
	s.Color = col(colorName)
	s.Thickness = thickness
	s.Transparency = Style.STROKE.transparency
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = inst
	return s
end

local function shade(inst, top, bottom)
	local g = Instance.new("UIGradient")
	g.Name = "Shade"
	g.Rotation = 90
	g.Color = ColorSequence.new(top, bottom) -- Color only, never Transparency
	g.Parent = inst
	return g
end

function TavernKit.plate(parent, size)
	local w, h = size and size.X.Offset or 0, size and size.Y.Offset or 0
	local f = Instance.new("Frame")
	f.Name = "TavernPlate"
	f.Size = size or UDim2.fromOffset(Style.plateSize(w, h))
	f.BackgroundColor3 = col("plateFill")
	f.BorderSizePixel = 0
	corner(f, Style.RADIUS.panel)
	stroke(f, "goldTrim", Style.STROKE.plate)
	shade(f, Color3.new(1, 1, 1), Color3.fromRGB(190, 185, 180))
	f.Parent = parent
	return f
end

function TavernKit.feel(button)
	if still() then return end
	local f = Style.feel(false)
	local scale = button:FindFirstChild("PressScale")
	if not scale then
		scale = Instance.new("UIScale")
		scale.Name = "PressScale"
		scale.Parent = button
	end
	local base = button.Position
	local TweenService = game:GetService("TweenService")
	local info = TweenInfo.new(f.seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	button.MouseEnter:Connect(function()
		if still() then return end
		TweenService:Create(button, info, { Position = base - UDim2.fromOffset(0, f.lift) }):Play()
	end)
	button.MouseLeave:Connect(function()
		if still() then return end
		TweenService:Create(button, info, { Position = base }):Play()
		TweenService:Create(scale, info, { Scale = 1 }):Play()
	end)
	button.MouseButton1Down:Connect(function()
		if still() then return end
		TweenService:Create(scale, info, { Scale = f.press }):Play()
	end)
	button.MouseButton1Up:Connect(function()
		if still() then return end
		TweenService:Create(scale, info, { Scale = 1 }):Play()
	end)
end

-- Style a TextButton as a kit button. Used by button() for a new one and by Gameplay v2 for the real Play Hand and Discard
-- instances, so the drawn rect and the click rect are one object. Idempotent (a second call changes nothing visible).
function TavernKit.skin(b, text, kind)
	local k = Style.BUTTONS[kind]
	b:SetAttribute("TavernKind", kind)
	b.AutoButtonColor = false
	b.BackgroundTransparency = 0
	b.BackgroundColor3 = col(k.fill)
	b.BorderSizePixel = 0
	b.Font = Enum.Font[Style.FONTS.ui]
	b.TextSize = Style.TEXT.button
	b.TextColor3 = col(k.text)
	b.TextTransparency = 0
	b.TextStrokeTransparency = 0.3
	b.TextStrokeColor3 = col(kind == "primary" and "buttonStroke" or "outline")
	if text then b.Text = text end
	for _, c in ipairs(b:GetChildren()) do
		if c:IsA("GuiObject") then c.Visible = false -- old art and labels on a reused button
		elseif c:IsA("UICorner") or c:IsA("UIStroke") or c:IsA("UIGradient") then c:Destroy() end
	end
	corner(b, Style.RADIUS.button)
	stroke(b, k.stroke, Style.STROKE.button)
	local base = rgb(Style.rgb(k.fill))
	shade(b, base:Lerp(Color3.new(1, 1, 1), 0.06), base:Lerp(Color3.new(0, 0, 0), 0.15))
	return b
end

local function button(parent, text, kind)
	local k = Style.BUTTONS[kind]
	local b = Instance.new("TextButton")
	b.Name = kind == "primary" and "TavernPrimary" or "TavernSecondary"
	b.Size = UDim2.new(1, 0, 0, k.height)
	TavernKit.skin(b, text or "", kind)
	b.Parent = parent
	TavernKit.feel(b)
	return b
end

function TavernKit.primaryButton(parent, text) return button(parent, text, "primary") end
function TavernKit.secondaryButton(parent, text) return button(parent, text, "secondary") end

function TavernKit.pill(parent, text, color)
	local fill = Style.PILLS[color or "wood"] or Style.PILLS.wood
	local f = Instance.new("Frame")
	f.Name = "TavernPill"
	f.Size = UDim2.fromOffset(Style.SIZES.pillH * 4, Style.SIZES.pillH)
	f.BackgroundColor3 = rgb(fill)
	f.BorderSizePixel = 0
	corner(f, Style.SIZES.pillH // 2)
	stroke(f, "goldTrimPlate", Style.STROKE.button)
	local t = Instance.new("TextLabel")
	t.Name = "Word"
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.Font = Enum.Font[Style.FONTS.ui]
	t.TextSize = Style.TEXT.min
	t.TextColor3 = col("creamChip")
	t.TextTransparency = 0
	t.TextStrokeTransparency = 0.3
	t.TextStrokeColor3 = col("outline")
	t.Text = text or ""
	t.Parent = f
	f.Parent = parent
	return f
end

function TavernKit.goldBox(parent, text)
	local f = Instance.new("Frame")
	f.Name = "TavernGoldBox"
	f.Size = UDim2.new(1, 0, 0, Style.SIZES.boxH)
	f.BackgroundColor3 = col("plateDark")
	f.BorderSizePixel = 0
	corner(f, Style.RADIUS.chip)
	stroke(f, "goldTrim", Style.STROKE.button)
	local t = Instance.new("TextLabel")
	t.Name = "Value"
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.Font = Enum.Font[Style.FONTS.ui]
	t.TextSize = Style.TEXT.box
	t.TextColor3 = col("gold")
	t.TextTransparency = 0
	t.TextStrokeTransparency = 0.4
	t.TextStrokeColor3 = col("outline")
	t.Text = text or ""
	t.Parent = f
	f.Parent = parent
	return f
end

function TavernKit.title(parent, text)
	local t = Instance.new("TextLabel")
	t.Name = "TavernTitle"
	t.Size = UDim2.new(1, 0, 0, Style.TEXT.title + 10)
	t.BackgroundTransparency = 1
	t.Font = Enum.Font[Style.FONTS.title]
	t.TextSize = Style.TEXT.title
	t.TextColor3 = col("cream")
	t.TextTransparency = 0
	t.TextStrokeTransparency = 0
	t.TextStrokeColor3 = col("outline")
	t.Text = text or ""
	t.Parent = parent
	return t
end

return TavernKit
