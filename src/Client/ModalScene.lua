--[[
	Client/ModalScene.lua
	The painted tavern room under a modal, the same look as the Choice screens (Client/ChoicePanel.lua): the Menu room painting
	under ONE smooth scrim with soft edge vignettes and a candle glow at each side. The modal's own opaque stage stays under it, so
	nothing behind ever shows through. Used by RoadChoice ("Choose your road").

	ModalScene.build(backdrop, z)   backdrop = the full-screen modal frame, z = its ZIndex; returns the Scene frame (idempotent)
	Also hides the stage's old decor (the thin map strips that read as faint horizontal lines).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Engine = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine")
local Layout = require(Engine:WaitForChild("ChoiceSceneLayout"))
local MenuSceneArt = require(Engine:WaitForChild("MenuSceneArt"))
local SmoothVignette = require(script.Parent.SmoothVignette)
local SoftGlow = require(script.Parent.SoftGlow)

local ModalScene = {}

local function scrimColor()
	local c = Layout.PALETTE.scrim
	return Color3.fromRGB(c[1], c[2], c[3])
end

function ModalScene.build(backdrop, z)
	local existing = backdrop:FindFirstChild("Scene")
	if existing then return existing end
	local stage = backdrop:FindFirstChild("ModalStage")
	local decor = stage and stage:FindFirstChild("Decor")
	if decor then
		decor.Visible = false
		decor:GetPropertyChangedSignal("Visible"):Connect(function() decor.Visible = false end)
	end
	local scene = Instance.new("Frame")
	scene.Name = "Scene"
	scene.Size = UDim2.fromScale(1, 1)
	scene.BackgroundColor3 = Color3.fromRGB(34, 24, 16)
	scene.BorderSizePixel = 0
	scene.Active = false
	scene.ZIndex = z
	scene.Parent = backdrop
	local wood = Instance.new("UIGradient") -- colour stops only; the fallback when the painting has no Image id
	wood.Rotation = 90
	wood.Color = ColorSequence.new(Color3.fromRGB(58, 40, 26), Color3.fromRGB(22, 15, 10))
	wood.Parent = scene
	local art = MenuSceneArt["menu_scene_a"]
	if type(art) == "string" and art ~= "" then
		local painting = Instance.new("ImageLabel")
		painting.Name = "Painting"
		painting.Size = UDim2.fromScale(1, 1)
		painting.BackgroundTransparency = 1
		painting.Image = art
		painting.ScaleType = Enum.ScaleType.Crop
		painting.ZIndex = z
		painting.Parent = scene
	end
	local scrim = Instance.new("Frame")
	scrim.Name = "Scrim"
	scrim.Size = UDim2.fromScale(1, 1)
	scrim.BackgroundColor3 = scrimColor()
	scrim.BackgroundTransparency = 0.42
	scrim.BorderSizePixel = 0
	scrim.Active = false
	scrim.ZIndex = z
	scrim.Parent = scene
	SmoothVignette.build(scene, {
		zIndex = z, color = scrimColor(), name = "SceneVignette",
		top = { strength = 0.7, extent = 0.3 }, bottom = { strength = 0.7, extent = 0.3 },
		left = { strength = 0.5, extent = 0.2 }, right = { strength = 0.5, extent = 0.2 },
	})
	for _, side in ipairs({ 0.1, 0.9 }) do
		SoftGlow.build(scene, { name = "CandleGlow", color = Color3.fromRGB(255, 190, 100), position = UDim2.fromScale(side, 0.34), size = UDim2.fromOffset(420, 420), peak = 0.3, zIndex = z })
	end
	return scene
end

return ModalScene
