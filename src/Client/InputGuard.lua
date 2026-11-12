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
	local lock = InputLock.new() -- gameplay hit areas: any open overlay
	local menuLock = InputLock.new() -- Menu buttons: only real "...Backdrop" panels, never gameplay overlays
	local watched = {}

	local function effective(frame)
		local ancestors = {}
		local p = frame.Parent
		while p and p:IsA("GuiObject") do
			ancestors[#ancestors + 1] = p.Visible
			p = p.Parent
		end
		return InputLock.effectivelyVisible(frame.Visible, ancestors)
	end

	local function watch(frame, isBackdrop)
		if watched[frame] or not frame:IsA("GuiObject") or SKIP[frame.Name] then return end
		watched[frame] = true
		local function sync()
			local open = effective(frame)
			lock:setOpen(frame, open)
			if isBackdrop then menuLock:setOpen(frame, open) end
			if open and opts.tooltip then opts.tooltip.Visible = false end
		end
		frame:GetPropertyChangedSignal("Visible"):Connect(sync)
		local p = frame.Parent
		while p and p:IsA("GuiObject") do -- a hidden ancestor (GameRoot) hides the overlay too
			p:GetPropertyChangedSignal("Visible"):Connect(sync)
			p = p.Parent
		end
		sync()
	end

	local function scan(parent)
		for _, child in ipairs(parent:GetChildren()) do
			if child.Name:sub(-8) == "Backdrop" then watch(child, true) end
		end
		parent.ChildAdded:Connect(function(child)
			if child.Name:sub(-8) == "Backdrop" then watch(child, true) end
		end)
	end

	for _, frame in ipairs(opts.overlays or {}) do watch(frame) end
	scan(root)
	if root.Parent and root.Parent:IsA("LayerCollector") then scan(root.Parent) end

	-- Menu popups that must stay clickable while open (they sit above the Notice Board by ZIndex)
	local function exempt(btn)
		local p = btn
		while p do
			local n = p.Name
			if n == "FanCatcher" or n == "AllActions" or n:sub(1, 7) == "Scroll_" then return true end
			p = p.Parent
		end
		return false
	end

	local function guardContainer(container, useLock)
		local disabled = {} -- buttons we turned off (so closing only restores those)
		local function setButton(btn, interactable)
			if exempt(btn) then return end
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
		useLock:guard(function(interactable)
			each(function(btn) setButton(btn, interactable) end)
		end)
		container.DescendantAdded:Connect(function(d)
			if d:IsA("GuiButton") and useLock:isLocked() then setButton(d, false) end
		end)
	end
	for _, container in ipairs(opts.guarded or {}) do
		if container then guardContainer(container, lock) end
	end
	if opts.menuGuarded then guardContainer(opts.menuGuarded, menuLock) end

	-- SAFETY NET: once a second while the game is up, a backdrop that was popped out more than a second ago and is still visible is stuck
	-- (a fade-out that never completed): log "[InputGuard] stuck <name>" and hide it so the board is clickable again.
	task.spawn(function()
		while root.Parent do
			task.wait(1)
			if root.Visible then
				local hosts = { root }
				if root.Parent and root.Parent:IsA("LayerCollector") then hosts[2] = root.Parent end
				for _, host in ipairs(hosts) do
					for _, child in ipairs(host:GetChildren()) do
						if child:IsA("GuiObject") and InputLock.isStuck(child:GetAttribute("PopState"), child:GetAttribute("PopOutAt"), child.Visible, os.clock()) then
							warn("[InputGuard] stuck " .. child.Name)
							child.Visible = false
							child.Active = false
						end
					end
				end
			end
		end
	end)

	return lock
end

return InputGuard
