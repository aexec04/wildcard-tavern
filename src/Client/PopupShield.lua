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

local Cue = require(script.Parent.Cue)

local PopupShield = {}

-- One shared gate: scroll_open when a popup becomes visible, scroll_close when it hides or goes away (never both in one
-- debounce window). Ledger page turns use their own cue and are not popups.
local gate = Rules.newCueGate()
local function isOpen(popup)
	return popup.Parent ~= nil and popup:IsA("GuiObject") and popup.Visible
end
local function watchSound(popup)
	if not Rules.makesSound(popup.Name) then return end
	local open = isOpen(popup)
	local function changed()
		local now = isOpen(popup)
		if now == open then return end
		open = now
		local cue = gate(now, os.clock())
		if cue then Cue.play(cue) end
	end
	popup:GetPropertyChangedSignal("Visible"):Connect(changed)
	popup.AncestryChanged:Connect(changed)
	if open then
		local cue = gate(true, os.clock())
		if cue then Cue.play(cue) end
	end
end

local function sinks(obj)
	return obj:IsA("Frame") or obj:IsA("ImageLabel") or obj:IsA("ScrollingFrame")
end

local shielded = {} -- every popup root that was shielded (the watchdog releases hidden ones)
local function shield(popup)
	shielded[popup] = true
	watchSound(popup)
	if sinks(popup) then popup.Active = true end
	for _, child in ipairs(popup:GetChildren()) do
		if sinks(child) then child.Active = true end
	end
	popup.ChildAdded:Connect(function(child)
		if sinks(child) then child.Active = true end
	end)
end

-- Menu scroll layers live inside the Menu, not at the root, so MenuHotspots registers them here.
PopupShield.watchSound = watchSound

-- the watchdog's release: a popup that is hidden or destroyed stops sinking input
function PopupShield.releaseHidden()
	local n = 0
	for popup in pairs(shielded) do
		if popup.Parent == nil or not popup.Visible then
			if popup.Parent ~= nil and popup.Active then popup.Active = false n = n + 1 end
			if popup.Parent == nil then shielded[popup] = nil end
		end
	end
	return n
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
