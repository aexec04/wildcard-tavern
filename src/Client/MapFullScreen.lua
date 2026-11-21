--[[
	Client/MapFullScreen.lua
	Makes the Tavern Map overlay a true full-screen scene (rules in Engine/FullScreenRules): the panel is 100 percent of the screen with no
	outer border, shadow or corner marks, the map fills it, the dark carved wood header (title plate, Night / Journey / Keys plate, round X, banners,
	candles; Client/MapHeaderBar) frames it (Escape closes through PopupDismiss), and the corner icon
	dock is hidden while it is open (Client/FullScreenHud) and restored on any close.

	apply{ screenGui, backdrop, panel, title, subtitle, mapFrame, closeButton, sizeConstraint }   idempotent: safe on every open
]]

local FullScreenHud = require(script.Parent.FullScreenHud)

local MapFullScreen = {}

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

	-- the dark carved wood header, banners, rails, candles and the round X (Client/MapHeaderBar; the title and stats are its plates)
	require(script.Parent.MapHeaderBar).attach(panel, function() p.backdrop.Visible = false end)
	p.title.Visible, p.subtitle.Visible = false, false
	require(script.Parent.CloseX).retire(p.closeButton) -- the round X is the close button now

	FullScreenHud.enter(root, "tavernMap")
	pcall(function() require(script.Parent.CornerDock).register(p.backdrop) end) -- the dock hides while the map backdrop is visible
	if not p.backdrop:GetAttribute("FullScreenWired") then
		p.backdrop:SetAttribute("FullScreenWired", true)
		p.backdrop:GetPropertyChangedSignal("Visible"):Connect(function()
			if not p.backdrop.Visible then FullScreenHud.leave(root, "tavernMap") end -- Close, Escape, X or another popup replacing it
		end)
	end
end

return MapFullScreen
