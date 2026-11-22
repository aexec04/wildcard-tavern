--[[
	Client/GamepadMenuNav.lua
	D-pad focus for the Menu and every popup (Settings, Store, Collection, ...). Rules live in Engine/GamepadFocus (tested).
	Only runs while the last input was a gamepad, the table is not taking card keys (Client/TableKeys owns the hand), and no text
	box has focus. D-pad moves a gold ring across the visible buttons of the ONE active screen (the topmost popup, else the menu),
	A presses the focused button through the same click the mouse uses (GuiButton:Activate), B closes the top popup through
	PopupDismiss (TableKeys already routes B there).

	install(getMenuRoot, tableActive)   getMenuRoot() -> the menu frame; tableActive() -> true while the hand has focus
]]

local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Focus = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("GamepadFocus"))

local M = {}
local installed, usingPad = false, false
local current, ring, ringTarget, scopeOf
local ringColor = Color3.fromRGB(Focus.RING.color[1], Focus.RING.color[2], Focus.RING.color[3]) -- the equipped Card Set's accent, see setRingColor

local function ringFrame()
	if ring then return ring end
	ring = Instance.new("Frame")
	ring.Name = "GamepadFocusRing"
	ring.BackgroundTransparency = 1
	ring.Size = UDim2.new(1, 0, 1, 0)
	local stroke = Instance.new("UIStroke")
	stroke.Color = ringColor
	stroke.Thickness = Focus.RING.thickness
	stroke.Parent = ring
	local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0, 8); corner.Parent = ring
	return ring
end

local function visible(inst, scope)
	while inst and inst ~= scope do
		if inst:IsA("GuiObject") and not inst.Visible then return false end
		inst = inst.Parent
	end
	return inst == scope
end

local function collect(scope)
	local items, byId = {}, {}
	for _, d in ipairs(scope:GetDescendants()) do
		if d:IsA("GuiButton") and d.Active and d.AbsoluteSize.X >= 8 and visible(d, scope) and not d:GetAttribute("NoGamepadFocus") then
			local id = #items + 1
			items[id] = { id = id, x = d.AbsolutePosition.X, y = d.AbsolutePosition.Y, w = d.AbsoluteSize.X, h = d.AbsoluteSize.Y }
			byId[id] = d
		end
	end
	return items, byId
end

local function clear()
	if ring then ring.Parent = nil end
	ringTarget, current = nil, nil
end

local function focus(button)
	if not button then clear() return end
	ringTarget = button
	local f = ringFrame()
	f.ZIndex = button.ZIndex + 5
	f.Parent = button -- parented to the button so it follows it and survives a Clone of its slot
end

-- Called when the equipped Card Set changes: rgb table {r,g,b}. Colour only, no tween.
function M.setRingColor(c)
	if type(c) ~= "table" then return end
	ringColor = Color3.fromRGB(c[1], c[2], c[3])
	local stroke = ring and ring:FindFirstChildOfClass("UIStroke")
	if stroke then stroke.Color = ringColor end
end

function M.install(getMenuRoot, tableActive)
	if installed then return end
	installed = true
	pcall(function() GuiService.AutoSelectGuiEnabled = false end)
	UserInputService.LastInputTypeChanged:Connect(function(kind)
		usingPad = kind == Enum.UserInputType.Gamepad1
		if not usingPad then clear() end
	end)
	UserInputService.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.Gamepad1 or UserInputService:GetFocusedTextBox() then return end
		local name = input.KeyCode.Name
		local PopupDismiss = require(script.Parent.PopupDismiss)
		local scope = PopupDismiss.topBackdrop()
		if not scope then
			if tableActive and tableActive() then clear() return end -- the hand has the D-pad
			scope = getMenuRoot and getMenuRoot()
			if scope and not scope.Visible then scope = nil end
		end
		if not scope then clear() return end
		if scope ~= scopeOf then scopeOf = scope; clear() end
		if name == "ButtonA" then
			if ringTarget and ringTarget.Parent and ringTarget.Active then ringTarget:Activate() end
			return
		end
		if not Focus.DIRS[name] then return end
		local items, byId = collect(scope)
		current = Focus.next(items, current, name)
		focus(current and byId[current] or nil)
	end)
end

return M
