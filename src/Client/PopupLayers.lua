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
	local holds = {} -- inst -> connection that keeps it hidden while a popup is open (the table render re-shows layers every frame)
	local function hide(inst)
		if inst:IsA("GuiObject") and Rules.shouldHide(inst.Name) and not insidePopup(inst) then
			if inst.Visible then
				hidden[inst] = true
				inst.Visible = false
			end
			if hidden[inst] and not holds[inst] then
				holds[inst] = inst:GetPropertyChangedSignal("Visible"):Connect(function()
					if openCount > 0 and inst.Visible then inst.Visible = false end
				end)
			end
		end
	end
	local function restore()
		for inst, c in pairs(holds) do c:Disconnect() end
		holds = {}
		for inst in pairs(hidden) do
			if inst.Parent then inst.Visible = true end
		end
		hidden = {}
		if conn then conn:Disconnect() conn = nil end
	end
	-- One switch for full screen pages: hide the whole table (GameRoot) so nothing from it can show through or sit above the page.
	local coverCount, rootHeld, rootConn = 0, false, nil
	-- a solid base under every full screen page, so the 3D world (sky) never shows through a page that has a see through strip
	local base = Instance.new("Frame")
	base.Name = "FullScreenBase"
	base.Size = UDim2.fromScale(1, 1)
	base.Position = UDim2.fromScale(0, 0)
	base.BackgroundColor3 = Color3.fromRGB(26, 17, 10)
	base.BorderSizePixel = 0
	base.Visible = false
	base.Active = false
	base.ZIndex = 2
	base.Parent = screenGui
	local function applyCover()
		base.Visible = coverCount > 0
		local root = screenGui:FindFirstChild("GameRoot")
		if not (root and root:IsA("GuiObject")) then return end
		if coverCount > 0 then
			if root.Visible then rootHeld = true; root.Visible = false end
			if rootHeld and not rootConn then
				rootConn = root:GetPropertyChangedSignal("Visible"):Connect(function()
					if coverCount > 0 and root.Visible then root.Visible = false end
				end)
			end
		else
			if rootConn then rootConn:Disconnect(); rootConn = nil end
			if rootHeld then rootHeld = false; root.Visible = true end
		end
	end
	local function refresh()
		screenGui:SetAttribute("PopupsOpen", openCount) -- read by the boss rule chip so its first-moment line never opens over a popup
		applyCover()
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
				if Rules.coversTable(popup.Name) then coverCount = coverCount + 1 end
			elseif not now and openPopups[popup] then
				openPopups[popup] = nil
				openCount = openCount - 1
				if Rules.coversTable(popup.Name) then coverCount = coverCount - 1 end
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
