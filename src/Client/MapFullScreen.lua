--[[
	Client/MapFullScreen.lua
	Makes the Tavern Map overlay a true full-screen scene (rules in Engine/FullScreenRules): the panel is 100 percent of the screen with no
	outer border, shadow or corner marks, the map fills it, the title and the stats line sit in a soft 64 px dark ink strip across the top
	(80 percent), one brass Close sits bottom centre and a small round X top right (Escape closes through PopupDismiss), and the corner icon
	dock is hidden while it is open (Client/FullScreenHud) and restored on any close.

	apply{ screenGui, backdrop, panel, title, subtitle, mapFrame, closeButton, sizeConstraint }   idempotent: safe on every open
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Rules = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("FullScreenRules"))
local FullScreenHud = require(script.Parent.FullScreenHud)

local MapFullScreen = {}

local INK = Color3.fromRGB(34, 24, 16)
local CREAM = Color3.fromRGB(250, 240, 220)
local BRASS = Color3.fromRGB(176, 138, 66)
local DECOR = { Shadow = true, SetSkinBorder = true, InnerRim = true, CornerStud = true, Brackets = true, BracketH = true, BracketV = true }

local function flatten(frame)
	for _, c in ipairs(frame:GetChildren()) do
		if c:IsA("UIStroke") then
			c.Enabled = false
		elseif c:IsA("UICorner") then
			c.CornerRadius = UDim.new(0, 0)
		elseif DECOR[c.Name] then
			c.Visible = false
		end
	end
end

function MapFullScreen.apply(p)
	local root = p.screenGui:FindFirstChild("GameRoot") or p.screenGui
	p.backdrop.BackgroundTransparency = 0
	p.backdrop.BackgroundColor3 = Color3.fromRGB(26, 20, 14)
	if p.sizeConstraint then p.sizeConstraint.MinSize = Vector2.new(0, 0) end
	local panel = p.panel
	panel.AnchorPoint = Vector2.new(0, 0)
	panel.Position = UDim2.fromOffset(0, 0)
	panel.Size = UDim2.fromScale(1, 1)
	flatten(panel)
	local map = p.mapFrame
	map.Position = UDim2.fromOffset(0, 0)
	map.Size = UDim2.fromScale(1, 1)
	flatten(map)

	local strip = panel:FindFirstChild("MapHeaderStrip")
	if not strip then
		strip = Instance.new("Frame")
		strip.Name = "MapHeaderStrip"
		strip.BackgroundColor3 = INK
		strip.BackgroundTransparency = 0.2 -- 80 percent
		strip.BorderSizePixel = 0
		strip.Active = false
		strip.ZIndex = 40 -- above every map layer (fog is 35)
		strip.Parent = panel
		require(script.Parent.CloseX).attach(panel, function() p.backdrop.Visible = false end, { inset = Rules.MARGIN, top = 10, z = 42 })
	end
	strip.Size = UDim2.new(1, 0, 0, Rules.STRIP_H)
	strip.Position = UDim2.fromOffset(0, 0)

	p.title.ZIndex, p.subtitle.ZIndex = 41, 41
	p.title.BackgroundTransparency = 1
	p.title.Position = UDim2.fromOffset(Rules.MARGIN, 3)
	p.title.Size = UDim2.new(1, -(Rules.X + Rules.MARGIN * 3), 0, 26)
	p.title.TextXAlignment = Enum.TextXAlignment.Left
	p.title.TextSize = 22
	p.subtitle.BackgroundTransparency = 1 -- the strip is the plate
	p.subtitle.Position = UDim2.fromOffset(Rules.MARGIN, 28)
	p.subtitle.Size = UDim2.new(1, -(Rules.X + Rules.MARGIN * 3), 0, 34)
	p.subtitle.TextSize = 15

	local close = p.closeButton
	close.Parent = panel
	close.AnchorPoint = Vector2.new(0.5, 1)
	close.Size = UDim2.fromOffset(Rules.CLOSE.w, Rules.CLOSE.h)
	close.Position = UDim2.new(0.5, 0, 1, -Rules.MARGIN)
	close.BackgroundColor3 = BRASS
	close.TextColor3 = INK
	close.ZIndex = 42

	FullScreenHud.enter(root, "tavernMap")
	if not p.backdrop:GetAttribute("FullScreenWired") then
		p.backdrop:SetAttribute("FullScreenWired", true)
		p.backdrop:GetPropertyChangedSignal("Visible"):Connect(function()
			if not p.backdrop.Visible then FullScreenHud.leave(root, "tavernMap") end -- Close, Escape, X or another popup replacing it
		end)
	end
end

return MapFullScreen
