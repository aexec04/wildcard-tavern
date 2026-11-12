--[[
	Client/PanelFullScreen.lua
	Collection, Card Sets, Badges, Legend, Flair and Stats open as full-screen scenes like the Tavern Map (Engine/PanelLayout.FULL_SCREEN).
	PanelTabs.attach calls apply(backdrop, panel) for them: the panel fills the screen below the tab strip, its outer border, corner
	radius and shadow are gone, the backdrop is opaque, and a panel that sets its own Size or Position (a painted room, the Expand toggle)
	is put back at once. The corner dock is hidden by PanelTabs while the page is open. Painted scenes are cover-fitted into the panel,
	so they fill the screen without stretching.

	apply(backdrop, panel)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PanelLayout = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("PanelLayout"))

local PanelFullScreen = {}

local DECOR = { Shadow = true, SetSkinBorder = true, InnerRim = true, CornerStud = true, Brackets = true, BracketH = true, BracketV = true }

local function flatten(panel)
	for _, c in ipairs(panel:GetChildren()) do
		if c:IsA("UIStroke") then
			c.Enabled = false
		elseif c:IsA("UICorner") then
			c.CornerRadius = UDim.new(0, 0)
		elseif c:IsA("UISizeConstraint") then
			c.MaxSize = Vector2.new(math.huge, math.huge)
			c.MinSize = Vector2.new(0, 0)
		elseif DECOR[c.Name] then
			c.Visible = false
		end
	end
end

function PanelFullScreen.apply(backdrop, panel)
	if panel:GetAttribute("FullScreenPanel") then return end
	panel:SetAttribute("FullScreenPanel", true)
	local top = PanelLayout.fullScreenRect(0, 0).y
	local forcing = false
	local function force()
		if forcing then return end
		forcing = true
		backdrop.BackgroundTransparency = 0
		backdrop.BackgroundColor3 = Color3.fromRGB(26, 20, 14)
		panel.AnchorPoint = Vector2.new(0, 0)
		panel.Position = UDim2.fromOffset(0, top)
		panel.Size = UDim2.new(1, 0, 1, -top)
		flatten(panel)
		forcing = false
	end
	force()
	for _, prop in ipairs({ "Size", "Position", "AnchorPoint" }) do
		panel:GetPropertyChangedSignal(prop):Connect(function()
			if forcing then return end
			if panel.Size ~= UDim2.new(1, 0, 1, -top) or panel.Position ~= UDim2.fromOffset(0, top) or panel.AnchorPoint ~= Vector2.new(0, 0) then
				task.defer(force)
			end
		end)
	end
	backdrop:GetPropertyChangedSignal("Visible"):Connect(function()
		if backdrop.Visible then force() end
	end)
end

return PanelFullScreen
