--[[
	Client/NightIntroFX.lua
	Gameplay v2 Night intro: when the table opens for a round, a plate with "Night N", the room name and the round's rule in one line
	fades in over a soft dim, holds, and fades out (1.2 s in all). A tap anywhere skips it. Calm mode and Reduce motion: none.
	Rules, timing and rects: Engine/Gameplay2Moments (nightIntroKey, nightIntro, nightIntroLines, nightIntroPlate). A Boss round is
	left to the boss intro. The Night map art is not touched.

	update(layer, state, w, h)   called with every table update; shows the intro once per Night and Round
	skip(layer)                  removes it at once (the tap does this)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Engine = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine")
local Rules = require(Engine:WaitForChild("Gameplay2Moments"))
local JourneyMap = require(Engine:WaitForChild("JourneyMap"))
local Style = require(Engine:WaitForChild("TavernStyle"))
local ClientSettings = require(script.Parent.ClientSettings)

local M = {}

local function calm() return ClientSettings.get("reduceShake") == true or ClientSettings.get("reduceMotion") == true end
local function fast() return ClientSettings.get("animSpeed") == "fast" end
local function color(name) local c = Style.rgb(name); return Color3.fromRGB(c[1], c[2], c[3]) end

function M.skip(layer)
	local old = layer:FindFirstChild("NightIntro")
	if old then old:Destroy() end
end

local function label(parent, name, text, size, colorName, font, y, h)
	local t = Instance.new("TextLabel")
	t.Name = name
	t.BackgroundTransparency = 1
	t.Position = UDim2.new(0, 12, 0, y)
	t.Size = UDim2.new(1, -24, 0, h)
	t.Font = Enum.Font[font]
	t.TextSize = size
	t.Text = text
	t.TextColor3 = color(colorName)
	t.TextTransparency = 0
	t.TextStrokeTransparency = 0.4
	t.TextStrokeColor3 = color("outline")
	t.TextWrapped = true
	t.TextTruncate = Enum.TextTruncate.None
	t.Active = false
	t.ZIndex = 36
	t.Parent = parent
	return t
end

local function show(layer, state, w, h, timing)
	M.skip(layer)
	pcall(function() require(script.Parent.Cue).play("scroll_open", 0.6) end) -- the Night plate arrives with a soft scroll sound
	local night = JourneyMap.getNight(math.floor(state.night or 1))
	local lines = Rules.nightIntroLines(state, night and night.name or "Endless Nights")
	local holder = Instance.new("Frame")
	holder.Name = "NightIntro"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromScale(1, 1)
	holder.Active = false
	holder.ZIndex = 34
	holder.Parent = layer
	local dim = Instance.new("TextButton") -- the whole screen: a tap skips
	dim.Name = "Dim"
	dim.Text = ""
	dim.AutoButtonColor = false
	dim.BorderSizePixel = 0
	dim.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	dim.BackgroundTransparency = 1
	dim.Size = UDim2.fromScale(1, 1)
	dim.ZIndex = 34
	dim.Parent = holder
	local rect = Rules.nightIntroPlate(w, h)
	local plate = Instance.new("CanvasGroup")
	plate.Name = "Plate"
	plate.BorderSizePixel = 0
	plate.BackgroundColor3 = color("plateDark")
	plate.BackgroundTransparency = 0.05
	plate.GroupTransparency = 1
	plate.Position = UDim2.fromOffset(rect.x, rect.y)
	plate.Size = UDim2.fromOffset(rect.w, rect.h)
	plate.ZIndex = 35
	plate.Active = false
	local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0, 12); corner.Parent = plate
	local stroke = Instance.new("UIStroke"); stroke.Color = color("goldTrim"); stroke.Thickness = 3; stroke.Parent = plate
	plate.Parent = holder
	label(plate, "Title", lines.title, 30, "gold", Style.FONTS.title, 8, 38)
	label(plate, "Room", lines.room, 20, "cream", Style.FONTS.title, 48, 26)
	label(plate, "Rule", lines.rule, 17, "cream", Style.FONTS.ui, 76, 24)
	for _, l in ipairs(plate:GetChildren()) do
		if l:IsA("TextLabel") then l.TextXAlignment = Enum.TextXAlignment.Center end
	end
	dim.MouseButton1Click:Connect(function() if holder.Parent then holder:Destroy() end end)
	TweenService:Create(dim, TweenInfo.new(timing.fadeIn), { BackgroundTransparency = timing.dim }):Play()
	TweenService:Create(plate, TweenInfo.new(timing.fadeIn), { GroupTransparency = 0 }):Play()
	task.delay(timing.fadeIn + timing.hold, function()
		if not holder.Parent then return end
		TweenService:Create(dim, TweenInfo.new(timing.fade), { BackgroundTransparency = 1 }):Play()
		TweenService:Create(plate, TweenInfo.new(timing.fade), { GroupTransparency = 1 }):Play()
		task.delay(timing.fade + 0.05, function() if holder.Parent then holder:Destroy() end end)
	end)
end

function M.update(layer, state, w, h)
	local key = Rules.nightIntroKey(state)
	if not key then
		layer:SetAttribute("NightIntroKey", nil)
		return
	end
	if layer:GetAttribute("NightIntroKey") == key then return end
	layer:SetAttribute("NightIntroKey", key)
	local timing = Rules.nightIntro(calm(), fast())
	if timing then pcall(show, layer, state, w, h, timing) end
end

-- the table closed (Round Select, the Counter, the Menu): the next round shows its intro again
function M.reset(layer)
	layer:SetAttribute("NightIntroKey", nil)
	M.skip(layer)
end

return M
