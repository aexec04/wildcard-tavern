-- Keeps the Store (and its tab strip, a child of StoreBackdrop) hidden for as long as a result plate is up.
-- Call ResultGuard.hold(gui) once per ScreenGui; later calls do nothing.
local Rules = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("ResultGuard"))

local ResultGuard = {}

local function visibleMap(gui)
	local map = {}
	for _, name in ipairs(Rules.RESULTS) do
		local f = gui:FindFirstChild(name)
		map[name] = f ~= nil and f:IsA("GuiObject") and f.Visible == true
	end
	return map
end

function ResultGuard.enforce(gui)
	if not Rules.mustHide(visibleMap(gui)) then return end
	for _, name in ipairs(Rules.HIDDEN) do
		local f = gui:FindFirstChild(name)
		if f and f:IsA("GuiObject") and f.Visible then f.Visible = false end
	end
end

function ResultGuard.hold(gui)
	if not gui or gui:GetAttribute("ResultGuardHeld") then return end
	gui:SetAttribute("ResultGuardHeld", true)
	local hooked = {}
	local function hook(child)
		if hooked[child] or not child:IsA("GuiObject") then return end
		local watch = table.find(Rules.HIDDEN, child.Name) or table.find(Rules.RESULTS, child.Name)
		if not watch then return end
		hooked[child] = true
		child:GetPropertyChangedSignal("Visible"):Connect(function() ResultGuard.enforce(gui) end)
	end
	for _, child in ipairs(gui:GetChildren()) do hook(child) end
	gui.ChildAdded:Connect(hook)
	ResultGuard.enforce(gui)
end

return ResultGuard
