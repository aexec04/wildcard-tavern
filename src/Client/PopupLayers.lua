--[[
	Client/PopupLayers.lua
	While any popup backdrop is open (Deck tracker, Hand reference, Seed run, Settings, Confirm ...), the boss card, boss banners
	and tooltips, HUD plates, gear and sort buttons are hidden, then restored when the last popup closes. One helper for every popup.

	PopupLayers.install(screenGui)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Engine = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine")
local PopupRules = require(Engine:WaitForChild("PopupRules"))
local Rules = require(Engine:WaitForChild("PopupLayers"))

local PopupLayers = {}

function PopupLayers.install(screenGui)
	local openPopups, openCount = {}, 0
	local hidden = {} -- inst -> true: what we hid, so we only restore our own
	local conn

	local function insidePopup(inst)
		local p = inst.Parent
		while p and p ~= screenGui do
			if PopupRules.isPopupName(p.Name) then return true end
			p = p.Parent
		end
		return false
	end
	local function hide(inst)
		if inst:IsA("GuiObject") and Rules.shouldHide(inst.Name) and inst.Visible and not insidePopup(inst) then
			hidden[inst] = true
			inst.Visible = false
		end
	end
	local function restore()
		for inst in pairs(hidden) do
			if inst.Parent then inst.Visible = true end
		end
		hidden = {}
		if conn then conn:Disconnect() conn = nil end
	end
	local function refresh()
		screenGui:SetAttribute("PopupsOpen", openCount) -- read by the boss rule chip so its first-moment line never opens over a popup
		if openCount > 0 then
			if not conn then
				for _, d in ipairs(screenGui:GetDescendants()) do hide(d) end
				conn = screenGui.DescendantAdded:Connect(function(d) task.defer(hide, d) end)
			end
		else
			restore()
		end
	end

	local function watch(popup)
		if not popup:IsA("GuiObject") then return end
		local function changed()
			local now = popup.Parent ~= nil and popup.Visible
			if now and not openPopups[popup] then
				openPopups[popup] = true
				openCount = openCount + 1
			elseif not now and openPopups[popup] then
				openPopups[popup] = nil
				openCount = openCount - 1
			end
			refresh()
		end
		popup:GetPropertyChangedSignal("Visible"):Connect(changed)
		popup.AncestryChanged:Connect(changed)
		changed()
	end
	local function consider(child)
		if PopupRules.isPopupName(child.Name) then watch(child) end
	end
	for _, c in ipairs(screenGui:GetChildren()) do consider(c) end
	screenGui.ChildAdded:Connect(consider)
end

return PopupLayers
