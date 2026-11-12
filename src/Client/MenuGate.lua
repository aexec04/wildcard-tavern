--[[
	Client/MenuGate.lua
	Keeps the Main Menu usable until Play is pressed (rules in Engine/MenuGate, tested). While the Menu is open:
	  - GameRoot cannot become visible (Play, Run Setup, challenge launches and the tutorial hide the Menu first);
	  - the run modals in MenuGate.RUN_MODALS (the opening blessing, road choice, Night Victory ...) are switched off again if a state
	    push turns them on; when the Menu closes, deps.rerender() draws the pending state, so Play still brings the same choice back.
	Studio prints one `[MenuGate] over the Menu: ...` line each time the Menu opens, naming every visible Active top-level object
	(the objects that can sink clicks over it).

	install{ screenGui, root, menuFrame, rerender? }
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Rules = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("MenuGate"))

local MenuGate = {}

function MenuGate.install(deps)
	local screenGui, root, menuFrame = deps.screenGui, deps.root, deps.menuFrame
	if not (screenGui and root and menuFrame) then return end
	local pending = false
	local hooked = {}

	local function open() return menuFrame.Visible == true end

	local function guardModal(inst)
		if hooked[inst] or not inst:IsA("GuiObject") or not Rules.RUN_MODALS[inst.Name] then return end
		hooked[inst] = true
		local function check()
			if inst.Visible and Rules.mustHide(inst.Name, open()) then
				inst.Visible = false
				pending = true
			end
		end
		inst:GetPropertyChangedSignal("Visible"):Connect(check)
		check()
	end
	for _, child in ipairs(screenGui:GetChildren()) do guardModal(child) end
	screenGui.ChildAdded:Connect(guardModal)

	root:GetPropertyChangedSignal("Visible"):Connect(function()
		if root.Visible and not Rules.rootAllowed(open()) then
			root.Visible = false
			pending = true
		end
	end)

	local function report()
		local list = {}
		for _, child in ipairs(screenGui:GetChildren()) do
			if child:IsA("GuiObject") then
				table.insert(list, { name = child.Name, visible = child.Visible, active = child.Active == true or child:IsA("GuiButton") })
			end
		end
		local sinks = Rules.sinks(list, menuFrame.Name)
		print("[MenuGate] over the Menu: " .. (#sinks > 0 and table.concat(sinks, ", ") or "nothing that sinks clicks"))
	end

	menuFrame:GetPropertyChangedSignal("Visible"):Connect(function()
		if open() then
			if RunService:IsStudio() then task.delay(0.5, function() if open() then report() end end) end
		elseif pending then
			pending = false
			if deps.rerender then task.defer(deps.rerender) end
		end
	end)
end

return MenuGate
