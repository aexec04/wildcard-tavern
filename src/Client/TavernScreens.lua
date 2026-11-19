--[[
	Client/TavernScreens.lua
	Puts the TavernKit look on the screens that were not rebuilt: the Counter, Run Over (and the Boss scene art for later use).
	Every button stays the one real instance (same drawn rect and click rect, handlers untouched); it is only restyled by
	TavernKit.skin. A table scene sits behind the screen at ZIndex 0 as a darkened picture (a plain dark plate shows until the
	scene loads). All settings are in Engine/TavernScreens (tested).

	backdrop(screenFrame, screen)          scene picture behind the screen, idempotent, never takes clicks
	skin(screenFrame, screen)              restyle every named button found under screenFrame, idempotent
	apply(screenFrame, screen)             both
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Engine = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine")
local Screens = require(Engine:WaitForChild("TavernScreens"))
local TableArt = require(Engine:WaitForChild("TableSceneArt"))
local Flags = require(Engine:WaitForChild("FeatureFlags"))
local Kit = require(script.Parent.TavernKit)

local M = {}

function M.backdrop(screenFrame, screen)
	local s = Screens.SCREENS[screen]
	if not (s and screenFrame) then return end
	local img = screenFrame:FindFirstChild("TavernScene")
	if not img then
		img = Instance.new("ImageLabel")
		img.Name = "TavernScene"
		img.BackgroundTransparency = 1
		img.BorderSizePixel = 0
		img.Active = false
		img.Size = UDim2.fromScale(1, 1)
		img.ScaleType = Enum.ScaleType.Crop
		img.ZIndex = Screens.LAYERS.scene
		img.Parent = screenFrame
	end
	img.Image = TableArt[s.scene] or ""
	img.ImageColor3 = Color3.fromRGB(s.tint[1], s.tint[2], s.tint[3])
	img.Visible = Flags.gameplay() == 2 -- the v1 archive keeps its own look
end

-- pin one decor piece to its layer; a later writer (SetSkin puts its border at the element's own ZIndex) is put back
local function pin(inst, z)
	if not (inst and inst:IsA("GuiObject")) then return end
	inst.ZIndex = z
	if inst:GetAttribute("LayerPinned") then return end
	inst:SetAttribute("LayerPinned", true)
	inst:GetPropertyChangedSignal("ZIndex"):Connect(function()
		if inst.ZIndex ~= z then inst.ZIndex = z end
	end)
end

-- scene, border and rim below, the named buttons (and everything inside them) at LAYERS.controls or higher
function M.layer(screenFrame, screen)
	local s = Screens.SCREENS[screen]
	if not (s and screenFrame) then return end
	local L = Screens.LAYERS
	for _, child in ipairs(screenFrame:GetChildren()) do
		if child.Name == "TavernScene" then pin(child, L.scene)
		elseif Screens.DECOR_NAMES[child.Name] then pin(child, L.decor) end
	end
	for name in pairs(s.buttons) do
		local b = screenFrame:FindFirstChild(name, true)
		if b and b:IsA("GuiObject") and b.ZIndex < L.controls and not b:GetAttribute("LayerLifted") then
			b:SetAttribute("LayerLifted", true)
			local delta = L.controls - b.ZIndex
			b.ZIndex = b.ZIndex + delta
			for _, d in ipairs(b:GetDescendants()) do
				if d:IsA("GuiObject") then d.ZIndex = d.ZIndex + delta end
			end
		end
	end
end

function M.skin(screenFrame, screen)
	if not screenFrame or Flags.gameplay() ~= 2 then return end
	local s = Screens.SCREENS[screen]
	if not s then return end
	for name, kind in pairs(s.buttons) do
		local b = screenFrame:FindFirstChild(name, true)
		if b and b:IsA("TextButton") and b:GetAttribute("TavernKind") ~= kind then
			pcall(Kit.skin, b, nil, kind)
		end
	end
end

-- Next Round: brighter than the kit primary and a full outline so it can never read as dark text on dark green
function M.emphasizeNext(b)
	if not (b and b:IsA("TextButton")) or b:GetAttribute("NextEmph") then return end
	b:SetAttribute("NextEmph", true)
	local N = Screens.NEXT_ROUND
	local base = Color3.fromRGB(N.fill[1], N.fill[2], N.fill[3])
	local hot = Color3.fromRGB(N.hover[1], N.hover[2], N.hover[3])
	b.BackgroundColor3 = base
	b.BackgroundTransparency = 0
	b.TextSize = N.textSize
	b.TextScaled = true -- 24 px where it fits, down to 15 px on a narrow plate
	local cap = Instance.new("UITextSizeConstraint")
	cap.MaxTextSize, cap.MinTextSize = N.textSize, 15
	cap.Parent = b
	b.TextColor3 = Color3.fromRGB(250, 240, 220)
	b.TextTransparency = 0
	b.TextStrokeColor3 = Color3.fromRGB(N.stroke[1], N.stroke[2], N.stroke[3])
	b.TextStrokeTransparency = 0
	b.MouseEnter:Connect(function() b.BackgroundColor3 = hot end) -- a colour swap, no tween, so Calm mode is the same
	b.MouseLeave:Connect(function() b.BackgroundColor3 = base end)
end

function M.apply(screenFrame, screen)
	pcall(M.backdrop, screenFrame, screen)
	M.skin(screenFrame, screen)
	pcall(M.layer, screenFrame, screen)
	if screen == "counter" and screenFrame and Flags.gameplay() == 2 then
		pcall(M.emphasizeNext, screenFrame:FindFirstChild("NextRound", true))
	end
end

return M
