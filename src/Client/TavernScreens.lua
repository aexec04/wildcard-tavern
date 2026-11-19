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
		img.ZIndex = 0
		img.Parent = screenFrame
	end
	img.Image = TableArt[s.scene] or ""
	img.ImageColor3 = Color3.fromRGB(s.tint[1], s.tint[2], s.tint[3])
	img.Visible = Flags.gameplay() == 2 -- the v1 archive keeps its own look
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

function M.apply(screenFrame, screen)
	pcall(M.backdrop, screenFrame, screen)
	M.skin(screenFrame, screen)
end

return M
