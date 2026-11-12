--[[
	Client/FlairPanel.lua
	FLAIR (Engine/Flair.lua), opened from the Collection group's Flair tab. The panel shell (backdrop, wooden panel, open and
	close, OverlayManager, PanelTabs) lives here; everything inside it is the dressing room (Client/FlairDressingRoom.lua:
	curtained mirror stage, drawers per category, equipped slots). Refreshes on every StateUpdated while open.
	Display only: the server validates the slot, the option and ownership (remote EquipFlair) and sends state.flair.

	init(deps): { screenGui, openButton, polishPanel, polishButton, roundCorner, addSoftShadow, playClickSfx, addTooltip,
	              popIn, popOut, addButtonHoverScale, getLatestState, StateUpdatedRemote, particleBurst }
]]

local FlairPanel = {}
local FullScreen = require(script.Parent.PanelFullScreen)

function FlairPanel.init(deps)
	local OverlayManager = require(script.Parent.OverlayManager)
	local FlairDressingRoom = require(script.Parent.FlairDressingRoom)

	local backdrop = Instance.new("Frame")
	backdrop.Name = "FlairBackdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	backdrop.BackgroundTransparency = 0.4
	backdrop.Visible = false
	backdrop.ZIndex = 40
	backdrop.Parent = deps.screenGui

	local panel = Instance.new("Frame")
	panel.Name = "FlairPanel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Size = UDim2.fromScale(0.86, 0.9)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.BackgroundColor3 = Color3.fromRGB(40, 30, 22)
	panel.ZIndex = 41
	panel.Parent = backdrop
	deps.polishPanel(panel, 16, "wood")
	deps.addSoftShadow(panel, 18)

	local function fitPanel() -- keeps the panel off the HUD sidebar (Engine/FlairRoomLayout.panelRect)
		local cam = workspace.CurrentCamera
		if not cam then return end
		local vp = cam.ViewportSize
		local r = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("FlairRoomLayout")).panelRect(vp.X, vp.Y)
		if FullScreen.owns(panel) then return end -- PanelFullScreen owns the rect
		panel.AnchorPoint = Vector2.new(0, 0.5)
		panel.Size = UDim2.new(0, r.w, 0, r.h)
		panel.Position = UDim2.new(0, r.x, 0.5, 0)
	end
	fitPanel()
	if workspace.CurrentCamera then workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fitPanel) end

	local room = FlairDressingRoom.build(deps, panel)

	local function refresh()
		local state = deps.getLatestState and deps.getLatestState() or nil
		if state then room.refresh(state) end
	end

	local function closePanel()
		room.stopStage()
		room.hideTip()
		deps.popOut(backdrop, panel)
	end

	require(script.Parent.PanelTabs).attach(backdrop, "flair", deps.playClickSfx, panel) -- shared tab strip + Back
	OverlayManager.register("flair", closePanel)
	local function openThisPanel()
		deps.playClickSfx()
		OverlayManager.closeAllExcept("flair")
		room.reset()
		refresh()
		deps.popIn(backdrop, panel)
		room.startStage()
	end
	OverlayManager.registerOpener("flair", openThisPanel)
	deps.openButton.MouseButton1Click:Connect(openThisPanel)
	require(script.Parent.CloseX).retire(room.closeButton)
	require(script.Parent.CloseX).attach(panel, function()
		deps.playClickSfx()
		closePanel()
	end)
	deps.StateUpdatedRemote.OnClientEvent:Connect(function()
		task.defer(function()
			if backdrop.Visible then
				refresh()
			end
		end)
	end)
end

return FlairPanel
