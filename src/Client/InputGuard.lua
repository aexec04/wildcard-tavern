--[[
	Client/InputGuard.lua
	Every full-screen overlay (Round Select, Shop, Game Over, and every "...Backdrop" panel such as
	Collection, Journey, Settings) must stop the gameplay widgets underneath from reacting. The overlay
	backdrops already sink clicks, but the deck pile still showed its tooltip and opened the deck viewer
	from the uncovered right edge of Round Select. This module is the shared, default-on fix:

	  install{ root, overlays = {frames}, guarded = {containers}, tooltip = TextLabel? }

	Overlays: the listed frames plus any child of root / its ScreenGui whose name ends in "Backdrop"
	(found now and as they are added). Guarded containers: every GuiButton inside them (now and added
	later) gets Interactable = false while any overlay is Visible, and the tooltip is hidden. Closing
	the last overlay restores everything. The top-right corner icons are NOT guarded: they are how a
	player switches panels and reaches Settings during Round Select. The model is Engine/InputLock.

	DeckTrackerBackdrop is skipped (the deck pile is what opens and toggles it).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local InputLock = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("InputLock"))

local InputGuard = {}

local SKIP = { DeckTrackerBackdrop = true }

function InputGuard.install(opts)
	local root = opts.root
	local lock = InputLock.new()
	local watched = {}

	local function watch(frame)
		if watched[frame] or not frame:IsA("GuiObject") or SKIP[frame.Name] then return end
		watched[frame] = true
		local function sync()
			lock:setOpen(frame, frame.Visible)
			if frame.Visible and opts.tooltip then opts.tooltip.Visible = false end
		end
		frame:GetPropertyChangedSignal("Visible"):Connect(sync)
		sync()
	end

	local function scan(parent)
		for _, child in ipairs(parent:GetChildren()) do
			if child.Name:sub(-8) == "Backdrop" then watch(child) end
		end
		parent.ChildAdded:Connect(function(child)
			if child.Name:sub(-8) == "Backdrop" then watch(child) end
		end)
	end

	for _, frame in ipairs(opts.overlays or {}) do watch(frame) end
	scan(root)
	if root.Parent and root.Parent:IsA("LayerCollector") then scan(root.Parent) end

	local function guardContainer(container)
		local disabled = {} -- buttons we turned off (so closing only restores those)
		local function setButton(btn, interactable)
			if interactable then
				if disabled[btn] then
					disabled[btn] = nil
					pcall(function() btn.Interactable = true end)
				end
			else
				if btn.Interactable ~= false then
					disabled[btn] = true
					pcall(function() btn.Interactable = false end)
				end
			end
		end
		local function each(fn)
			if container:IsA("GuiButton") then fn(container) end
			for _, d in ipairs(container:GetDescendants()) do
				if d:IsA("GuiButton") then fn(d) end
			end
		end
		lock:guard(function(interactable)
			each(function(btn) setButton(btn, interactable) end)
		end)
		container.DescendantAdded:Connect(function(d)
			if d:IsA("GuiButton") and lock:isLocked() then setButton(d, false) end
		end)
	end
	for _, container in ipairs(opts.guarded or {}) do
		if container then guardContainer(container) end
	end

	return lock
end

return InputGuard
