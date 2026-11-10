--[[
	Client/StatsPanel.lua
	The Tavern Ledger, opened from the Collection group tabs: a shell (backdrop, desk panel, title, Close) around the
	open leather ledger book built by Client/LedgerBook.lua (pages, ribbon tabs, count-up, stamps). Data mapping is in
	Engine/LedgerPages.lua. Reads state.runStats (Engine/RunHistory.view) and refreshes on every StateUpdated while open.
	deps: screenGui, polishPanel, polishButton, roundCorner, addSoftShadow, playClickSfx, openButton, addTooltip,
	      getLatestState, popIn, popOut, addButtonHoverScale, StateUpdatedRemote
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

return function(deps)
	local OverlayManager = require(script.Parent.OverlayManager)
	local Pages = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("LedgerPages"))
	local LedgerBook = require(script.Parent.LedgerBook)

	local GOLD = Color3.fromRGB(232, 190, 108)
	local WOOD = Color3.fromRGB(86, 58, 34)

	local backdrop = Instance.new("Frame")
	backdrop.Name = "StatsBackdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	backdrop.BackgroundTransparency = 0.4
	backdrop.Visible = false
	backdrop.ZIndex = 40
	backdrop.Parent = deps.screenGui

	local panel = Instance.new("Frame")
	panel.Name = "LedgerDesk"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Size = UDim2.fromScale(0.82, 0.9)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.BackgroundTransparency = 1
	panel.ZIndex = 41
	panel.Parent = backdrop
	deps.addSoftShadow(panel, 18)

	local book = LedgerBook.build(deps, panel)

	local L = Pages.LAYOUT
	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.TextSize = 28
	title.TextColor3 = GOLD
	title.TextTransparency = 0
	title.TextStrokeTransparency = 0.6
	title.Text = "Tavern Ledger"
	title.Position = UDim2.fromScale(L.title.x, L.title.y)
	title.Size = UDim2.fromScale(L.title.w, L.title.h)
	title.ZIndex = 45
	title.Parent = panel

	local closeButton = Instance.new("TextButton")
	closeButton.Size = UDim2.fromOffset(120, 38)
	closeButton.AnchorPoint = Vector2.new(0.5, 1)
	closeButton.Position = UDim2.new(L.close.x, 0, 1, -8)
	closeButton.Font = Enum.Font.GothamBold
	closeButton.TextSize = 17
	closeButton.TextColor3 = Color3.fromRGB(240, 232, 208)
	closeButton.BackgroundColor3 = WOOD
	closeButton.Text = "Close"
	closeButton.ZIndex = 46
	closeButton.Parent = panel
	deps.polishButton(closeButton, 8)
	deps.addButtonHoverScale(closeButton)

	require(script.Parent.PanelTabs).attach(backdrop, "stats", deps.playClickSfx) -- shared tab strip + Back
	OverlayManager.register("stats", function()
		deps.popOut(backdrop, panel)
	end)
	local function openThisPanel()
		deps.playClickSfx()
		OverlayManager.closeAllExcept("stats")
		book.setPage(1)
		book.refresh(true)
		deps.popIn(backdrop, panel)
	end
	OverlayManager.registerOpener("stats", openThisPanel)
	deps.openButton.MouseButton1Click:Connect(openThisPanel)
	closeButton.MouseButton1Click:Connect(function()
		deps.playClickSfx()
		deps.popOut(backdrop, panel)
	end)
	deps.StateUpdatedRemote.OnClientEvent:Connect(function()
		task.defer(function()
			if backdrop.Visible then
				book.refresh(false)
			end
		end)
	end)

	return {}
end
