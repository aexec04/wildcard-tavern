--[[
	MenuPanelHide: while any panel backdrop (a ScreenGui child named *Backdrop, see Engine/PopupRules.lua) is visible, the Menu's
	Notice Board is hidden so its pins and notes never show through the panel. Call attach(menuFrame, board).
]]
local Engine = game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine")
local Rules = require(Engine:WaitForChild("PopupRules"))

local M = {}

function M.attach(menuFrame, board)
	local gui = menuFrame:FindFirstAncestorWhichIsA("LayerCollector")
	if not gui or not board or not board.frame then return end
	local watched = {}
	local function sync()
		local names = {}
		for _, child in ipairs(gui:GetChildren()) do
			if child:IsA("GuiObject") and child.Visible then names[#names + 1] = child.Name end
		end
		local hide = Rules.hidesBoard(names)
		board.frame:SetAttribute("PanelOpen", hide)
		board.frame.Visible = not hide and board.frame:GetAttribute("Phone") ~= true
	end
	local function watch(child)
		if watched[child] or not child:IsA("GuiObject") or not Rules.shouldShield(child.Name) then return end
		watched[child] = true
		child:GetPropertyChangedSignal("Visible"):Connect(sync)
	end
	for _, child in ipairs(gui:GetChildren()) do watch(child) end
	gui.ChildAdded:Connect(function(child) watch(child) sync() end)
	sync()
end

return M
