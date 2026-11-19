--[[
	Client/Gameplay2MomentsFX.lua
	Draws Engine/Gameplay2Moments on the Gameplay v2 table.

	clear(root, lines)               centred "Target cleared" plate: slides in, tips count up, fades out. Takes no input.
	boss(layer, rects, state, w, h)  the boss rule banner under the top bar plus a static red candle tint; hides when not a boss round
	Calm mode and Reduce motion: the plate just shows, then goes; no tween, no count, no slide. Fast speed halves the times.
]]

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Engine = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine")
local Rules = require(Engine:WaitForChild("Gameplay2Moments"))
local Style = require(Engine:WaitForChild("TavernStyle"))
local Celebration = require(Engine:WaitForChild("Celebration"))
local ClientSettings = require(script.Parent.ClientSettings)
local Kit = require(script.Parent.TavernKit)

local M = {}

local function calm() return ClientSettings.get("reduceShake") == true end
local function fast() return ClientSettings.get("animSpeed") == "fast" end
local function color(name) local c = Style.rgb(name); return Color3.fromRGB(c[1], c[2], c[3]) end

local function text(parent, name, str, size, colorName, font, y, h)
	local t = Instance.new("TextLabel")
	t.Name = name
	t.BackgroundTransparency = 1
	t.Size = UDim2.new(1, -24, 0, h)
	t.Position = UDim2.fromOffset(12, y)
	t.Font = Enum.Font[font]
	t.TextSize = size
	t.Text = str
	t.TextColor3 = color(colorName)
	t.TextTransparency = 0
	t.TextStrokeTransparency = 0.3
	t.TextStrokeColor3 = color("outline")
	t.TextTruncate = Enum.TextTruncate.AtEnd
	t.Active = false
	t.ZIndex = 42
	t.Parent = parent
	return t
end

function M.clear(root, lines)
	if not root or not lines then return end
	local old = root:FindFirstChild("TargetClearedPlate")
	if old then old:Destroy() end
	local size = root.AbsoluteSize
	local rect = Rules.clearPlate(size.X, size.Y)
	local timing = Rules.clearTiming(calm(), fast())
	local plate = Kit.plate(root, UDim2.fromOffset(rect.w, rect.h))
	plate.Name = "TargetClearedPlate"
	plate.Active = false
	plate.AnchorPoint = Vector2.new(0.5, 0)
	plate.Position = UDim2.fromOffset(rect.x + rect.w / 2, rect.y)
	plate.ZIndex = 41
	local gap = math.floor(rect.h / 4)
	local title = text(plate, "Title", lines.title, 28, "gold", Style.FONTS.title, 6, gap + 8)
	text(plate, "Score", lines.score, 20, "cream", Style.FONTS.ui, 6 + gap + 8, gap)
	local tips = text(plate, "Tips", lines.tipsEarned > 0 and "Tips +0" or lines.tips, 20, "cream", Style.FONTS.ui, 6 + 2 * gap + 8, gap)
	if timing.slide == 0 then
		tips.Text = lines.tips
		task.delay(timing.hold, function() if plate.Parent then plate:Destroy() end end)
		return
	end
	local fall = 18
	plate.Position = UDim2.fromOffset(rect.x + rect.w / 2, rect.y - fall)
	TweenService:Create(plate, TweenInfo.new(timing.slide, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = UDim2.fromOffset(rect.x + rect.w / 2, rect.y) }):Play()
	task.spawn(function()
		local steps = Celebration.countSteps(lines.tipsEarned, false)
		if steps then
			for _, v in ipairs(steps.values) do
				if not tips.Parent then return end
				tips.Text = string.format("Tips +%d", v)
				task.wait(math.min(steps.step, timing.hold / math.max(1, #steps.values)))
			end
		end
		task.wait(math.max(0, timing.hold - 0.2))
		if not plate.Parent then return end
		for _, d in ipairs(plate:GetDescendants()) do
			if d:IsA("TextLabel") then
				TweenService:Create(d, TweenInfo.new(timing.fade), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
			end
		end
		local fadeTween = TweenService:Create(plate, TweenInfo.new(timing.fade), { BackgroundTransparency = 1 })
		fadeTween.Completed:Connect(function() if plate.Parent then plate:Destroy() end end)
		fadeTween:Play()
		task.delay(timing.fade + 0.5, function() if plate.Parent then plate:Destroy() end end)
	end)
end

-- the banner and tint live inside the Gameplay2 layer so they hide with it
function M.boss(layer, rects, state, w, h)
	local tint = layer:FindFirstChild("BossTint")
	local banner = layer:FindFirstChild("BossBanner")
	local name, rule = Rules.bossText(state)
	if not name then
		if tint then tint.Visible = false end
		if banner then banner.Visible = false end
		return
	end
	if not tint then
		tint = Instance.new("Frame")
		tint.Name = "BossTint"
		tint.BorderSizePixel = 0
		tint.Size = UDim2.fromScale(1, 1)
		tint.Active = false
		tint.ZIndex = 2
		tint.Parent = layer
	end
	local g = Rules.bossGlow(calm())
	tint.BackgroundColor3 = Color3.fromRGB(g.color[1], g.color[2], g.color[3])
	tint.BackgroundTransparency = g.transparency
	tint.Visible = true
	local rect = Rules.bossBanner(rects, w, h)
	if not rect then
		if banner then banner.Visible = false end
		return
	end
	if not banner then
		banner = Instance.new("Frame")
		banner.Name = "BossBanner"
		banner.BorderSizePixel = 0
		banner.BackgroundColor3 = Color3.fromRGB(70, 22, 20)
		banner.BackgroundTransparency = 0.15
		banner.Active = false
		banner.ZIndex = 4
		local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 6); c.Parent = banner
		local s = Instance.new("UIStroke"); s.Color = color("gold"); s.Thickness = 1; s.Parent = banner
		local n = Instance.new("TextLabel"); n.Name = "BossName"; n.BackgroundTransparency = 1
		n.Font = Enum.Font[Style.FONTS.title]; n.TextColor3 = color("gold"); n.TextXAlignment = Enum.TextXAlignment.Left
		n.TextTruncate = Enum.TextTruncate.AtEnd; n.TextStrokeTransparency = 0.4; n.TextStrokeColor3 = color("outline"); n.ZIndex = 5; n.Active = false; n.Parent = banner
		local r = Instance.new("TextLabel"); r.Name = "BossRule"; r.BackgroundTransparency = 1
		r.Font = Enum.Font[Style.FONTS.ui]; r.TextColor3 = color("cream"); r.TextXAlignment = Enum.TextXAlignment.Left
		r.TextTruncate = Enum.TextTruncate.AtEnd; r.TextStrokeTransparency = 0.5; r.TextStrokeColor3 = color("outline"); r.ZIndex = 5; r.Active = false; r.Parent = banner
		banner.Parent = layer
	end
	banner.Visible = true
	banner.Position = UDim2.fromOffset(rect.x, rect.y)
	banner.Size = UDim2.fromOffset(rect.w, rect.h)
	local ts = math.max(14, math.min(18, rect.h - 8))
	local n, r = banner.BossName, banner.BossRule
	n.Text = name
	n.TextSize = ts
	n.Size = UDim2.new(0.34, -10, 1, 0); n.Position = UDim2.fromOffset(10, 0)
	r.Text = rule
	r.TextSize = ts
	r.Size = UDim2.new(0.66, -14, 1, 0); r.Position = UDim2.new(0.34, 4, 0, 0)
end

return M
