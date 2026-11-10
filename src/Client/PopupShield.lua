--[[
	Client/PopupShield.lua
	Every popup root (any "...Backdrop" child of the ScreenGui or root, plus SpectateOverlay and ModalStage) must
	swallow clicks so nothing behind it reacts (the Menu Notice Board used to take clicks through the scrolls and
	panels). Frames only sink input when Active = true, so this marks the popup root and its direct panel children
	Active, now and as they are added. InputGuard.install also switches the Menu's buttons off while a popup is up,
	because Notice Board pins sit at a higher ZIndex than the older panel backdrops.

	PopupShield.install(screenGui, root)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Rules = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("PopupRules"))

local PopupShield = {}

local function sinks(obj)
	return obj:IsA("Frame") or obj:IsA("ImageLabel") or obj:IsA("ScrollingFrame")
end

local function shield(popup)
	if sinks(popup) then popup.Active = true end
	for _, child in ipairs(popup:GetChildren()) do
		if sinks(child) then child.Active = true end
	end
	popup.ChildAdded:Connect(function(child)
		if sinks(child) then child.Active = true end
	end)
end

function PopupShield.install(screenGui, root)
	local seen = {}
	local function scan(parent)
		if not parent then return end
		local function consider(child)
			if not seen[child] and child:IsA("GuiObject") and Rules.shouldShield(child.Name) then
				seen[child] = true
				shield(child)
			end
		end
		for _, child in ipairs(parent:GetChildren()) do consider(child) end
		parent.ChildAdded:Connect(consider)
	end
	scan(screenGui)
	if root ~= screenGui then scan(root) end
end

return PopupShield
