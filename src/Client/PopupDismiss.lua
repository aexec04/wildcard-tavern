--[[
	Client/PopupDismiss.lua
	Every screen can be exited: Escape and a click on the dark area, wired ONCE for every popup (rules and policies in
	Engine/PopupDismissRules.lua, tested). Each popup module registers its backdrop next to where it builds it:

	  PopupDismiss.attach(backdrop, {
	    panel   = the panel (or a list, or a function returning one): a click on it is never "outside". Leave it out and the
	              outside click stays off for this popup (Escape still works).
	    id      = the OverlayManager id the panel registered its close function under; used when `close` is not given.
	    close   = function(), how this popup closes itself (the same thing its Close button does).
	    policy  = "dismiss" (default) | "cancel" | "button" | "locked", or a function returning one (see the rules file).
	    press   = function(), for policy "button": what its one button does (Escape presses it).
	    step    = function() -> true when it went back one level (the Collection: detail card, section, room); Escape calls it first and only
	              closes the popup when it answers anything else.
	    escape / outside = false to leave that exit to the module (PokerHandsReference and RestartRun keep their own clicks).
	    button  = true | false, whether it shows a Back, Close, Cancel or Continue button (otherwise found by name, for the report).
	  })

	Escape reaches the TOPMOST visible registered popup only (highest ZIndex, ties to the one opened last), ignoring
	gameProcessed because Escape is also Roblox's own menu key (as PokerHandsReference always did). A click counts as outside when
	it lands on the backdrop or on a child that covers the whole backdrop (a scene, a stage, a vignette): the tab strip, the shadow
	and the panel are smaller and never count. No pointer coordinates are involved.

	A "locked" screen (a mid-run choice) cannot be abandoned, but Escape opens Settings above it (PopupDismiss.openSettings lifts
	the Settings popup by LIFT ZIndex while it is up, because ZIndex is absolute under ZIndexBehavior.Global), so nobody is stuck.

	PopupDismiss.install(screenGui, root)  next to PopupShield.install: starts listening and, in Studio only, prints one report of
	                                       every popup root and its exits after a few seconds.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local Engine = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine")
local Rules = require(Engine:WaitForChild("PopupDismissRules"))
local PopupRules = require(Engine:WaitForChild("PopupRules"))
local OverlayManager = require(script.Parent.OverlayManager)

local PopupDismiss = {}
PopupDismiss.VERSION = "v1"

local LIFT = 100 -- ZIndex added to the Settings popup while it is opened over a locked screen
local entries = {} -- backdrop -> entry
local byId = {} -- OverlayManager id -> entry
local order = 0 -- opening sequence
local listening = false

local function shown(inst)
	if inst.Parent == nil then return false end
	while inst and inst:IsA("GuiObject") do
		if not inst.Visible then return false end
		inst = inst.Parent
	end
	return true
end

local function nameOf(entry)
	return entry.backdrop.Name
end

local function policyOf(entry)
	local p = entry.spec.policy
	if p == nil then return "dismiss" end
	if type(p) == "function" then
		local ok, value = pcall(p)
		p = ok and value or nil
	end
	-- an unreadable policy must never close a screen the player is in the middle of
	return Rules.isPolicy(p) and p or "locked"
end

local function panelsOf(entry)
	local p = entry.spec.panel
	if type(p) == "function" then
		local ok, value = pcall(p)
		p = ok and value or nil
	end
	if typeof(p) == "Instance" then return { p } end
	return type(p) == "table" and p or {}
end

-- ===== lift: Settings above a locked screen (ZIndex is absolute under Global) =====
local function lift(entry)
	if entry.lifted then return end
	entry.lifted = true
	local function bump(inst)
		if inst:IsA("GuiObject") and not inst:GetAttribute("PopupLifted") then
			inst.ZIndex += LIFT
			inst:SetAttribute("PopupLifted", true)
		end
	end
	bump(entry.backdrop)
	for _, d in ipairs(entry.backdrop:GetDescendants()) do bump(d) end
end

local function lower(entry)
	if not entry.lifted then return end
	entry.lifted = false
	local function drop(inst)
		if inst:IsA("GuiObject") and inst:GetAttribute("PopupLifted") then
			inst.ZIndex -= LIFT
			inst:SetAttribute("PopupLifted", nil)
		end
	end
	drop(entry.backdrop)
	for _, d in ipairs(entry.backdrop:GetDescendants()) do drop(d) end
end

-- ===== what the exits do =====
local function topmostEntry()
	local list = {}
	for backdrop, entry in pairs(entries) do
		list[#list + 1] = { entry = entry, z = backdrop.ZIndex, order = entry.openedAt, visible = shown(backdrop) }
	end
	local best = Rules.topmost(list)
	return best and best.entry or nil
end

function PopupDismiss.openSettings()
	local entry = byId.settings
	if not entry then return false end
	if not shown(entry.backdrop) then
		if not OverlayManager.open("settings") then return false end
	end
	lift(entry)
	return true
end

local function closeEntry(entry)
	local spec = entry.spec
	local ok, err = pcall(function()
		if spec.close then
			spec.close()
		elseif spec.id and OverlayManager.close(spec.id) then
			return
		else
			entry.backdrop.Visible = false
		end
	end)
	if not ok then warn("[PopupDismiss] " .. nameOf(entry) .. " could not close: " .. tostring(err)) end
end

local function run(entry, action)
	if action == "close" then
		closeEntry(entry)
	elseif action == "press" then
		if entry.spec.press then
			local ok, err = pcall(entry.spec.press)
			if not ok then warn("[PopupDismiss] " .. nameOf(entry) .. " button failed: " .. tostring(err)) end
		end
	elseif action == "pause" then
		local ok, err = pcall(PopupDismiss.openSettings)
		if not ok then warn("[PopupDismiss] Settings could not open over " .. nameOf(entry) .. ": " .. tostring(err)) end
	end
end

function PopupDismiss.escape()
	local entry = topmostEntry()
	if entry and entry.spec.escape ~= false then
		-- a popup with levels (the Collection: detail card, section, room) steps back one level before it closes
		if entry.spec.step then
			local ok, handled = pcall(entry.spec.step)
			if not ok then
				warn("[PopupDismiss] " .. nameOf(entry) .. " could not step back: " .. tostring(handled))
			elseif handled == true then
				return
			end
		end
		run(entry, Rules.action(policyOf(entry), "escape"))
	end
end

local function ensureListening()
	if listening then return end
	listening = true
	-- Escape is also Roblox's own menu key, so gameProcessed is ignored.
	UserInputService.InputBegan:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.Escape then
			PopupDismiss.escape()
		end
	end)
end

-- ===== outside clicks =====
local function insidePanel(entry, obj)
	for _, panel in ipairs(panelsOf(entry)) do
		if obj == panel or obj:IsAncestorOf(panel) or panel:IsAncestorOf(obj) then return true end
	end
	return false
end

local function outside(entry, obj)
	if entry.spec.outside == false or #panelsOf(entry) == 0 then return end
	if obj ~= entry.backdrop then
		if insidePanel(entry, obj) then return end
		local a, b = obj.AbsoluteSize, entry.backdrop.AbsoluteSize
		if not Rules.isDimLayer(a.X, a.Y, b.X, b.Y) then return end
	end
	if topmostEntry() ~= entry then return end
	run(entry, Rules.action(policyOf(entry), "outside"))
end

local function wire(entry, obj)
	if entry.wired[obj] or not obj:IsA("GuiObject") then return end
	entry.wired[obj] = true
	obj.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			outside(entry, obj)
		end
	end)
end

-- ===== registration =====
function PopupDismiss.attach(backdrop, spec)
	local okAttach, entry = pcall(function()
		spec = spec or {}
		local e = { backdrop = backdrop, spec = spec, openedAt = 0, wired = {}, lifted = false }
		entries[backdrop] = e
		if spec.id then byId[spec.id] = e end
		local function visibility()
			if shown(backdrop) then
				if e.openedAt == 0 or not e.wasShown then
					order += 1
					e.openedAt = order
				end
				e.wasShown = true
			else
				e.wasShown = false
				if e.lifted and not backdrop.Visible then lower(e) end
			end
		end
		backdrop:GetPropertyChangedSignal("Visible"):Connect(visibility)
		visibility()
		-- popups that are built again each time (the Win Card) must not pile up in the registry
		backdrop.Destroying:Connect(function()
			if entries[backdrop] == e then entries[backdrop] = nil end
			if spec.id and byId[spec.id] == e then byId[spec.id] = nil end
		end)
		wire(e, backdrop)
		for _, child in ipairs(backdrop:GetChildren()) do wire(e, child) end
		backdrop.ChildAdded:Connect(function(child) wire(e, child) end)
		ensureListening()
		return e
	end)
	if not okAttach then
		warn("[PopupDismiss] could not register " .. tostring(backdrop and backdrop.Name) .. ": " .. tostring(entry))
		return nil
	end
	return entry
end

-- ===== Studio report =====
local BUTTON_WORDS = { back = true, close = true, cancel = true, continue = true, done = true, ok = true, later = true, menu = true, x = true }

local function hasButton(entry)
	if type(entry.spec.button) == "boolean" then return entry.spec.button end
	for _, d in ipairs(entry.backdrop:GetDescendants()) do
		if d:IsA("GuiButton") and d:IsA("TextButton") then
			local text = d.Text:lower():gsub("[^%a ]", ""):gsub("^%s+", ""):gsub("%s+$", "")
			if BUTTON_WORDS[text] or text:find("^back") or text:find("^close") then return true end
		end
	end
	return false
end

function PopupDismiss.report(screenGui, root)
	local lines, count, missing = {}, 0, 0
	local seen = {}
	local function line(name, text)
		count += 1
		lines[#lines + 1] = string.format("  %-28s %s", name, text)
	end
	local function consider(parent)
		if not parent then return end
		for _, child in ipairs(parent:GetChildren()) do
			if child:IsA("GuiObject") and PopupRules.isPopupName(child.Name) and not seen[child] then
				seen[child] = true
				local entry = entries[child]
				if entry then
					local policy = policyOf(entry)
					local exits = Rules.exits(policy, hasButton(entry))
					if entry.spec.escape == false then exits.escape = "module" end
					if entry.spec.outside == false then exits.outside = "module" end
					if #panelsOf(entry) == 0 and exits.outside == true then exits.outside = false end
					line(child.Name, string.format("%-8s button=%s escape=%s outside=%s", policy, tostring(exits.button), tostring(exits.escape), tostring(exits.outside)))
				elseif Rules.EXCEPTIONS[child.Name] then
					line(child.Name, "EXCEPTION: " .. Rules.EXCEPTIONS[child.Name])
				else
					missing += 1
					line(child.Name, "NO EXIT: not registered with PopupDismiss")
				end
			end
		end
	end
	consider(screenGui)
	if root ~= screenGui then consider(root) end
	table.sort(lines)
	warn(string.format("[PopupDismiss] %s %d popup roots, %d without an exit:\n%s", PopupDismiss.VERSION, count, missing, table.concat(lines, "\n")))
end

function PopupDismiss.install(screenGui, root)
	ensureListening()
	if RunService:IsStudio() then
		task.delay(6, function() -- after every panel has been built
			pcall(PopupDismiss.report, screenGui, root)
		end)
	end
end

return PopupDismiss
