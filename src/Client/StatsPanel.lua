--[[
	Client/StatsPanel.lua
	The Tavern Ledger, opened from the Collection group tabs: a shell (backdrop, desk panel, title, Close) around the
	open leather ledger book built by Client/LedgerBook.lua (pages, ribbon tabs, count-up, stamps). Data mapping is in
	Engine/LedgerPages.lua. Reads state.runStats (Engine/RunHistory.view) and refreshes on every StateUpdated while open.
	deps: screenGui, polishPanel, polishButton, roundCorner, addSoftShadow, playClickSfx, openButton, addTooltip,
	      getLatestState, popIn, popOut, addButtonHoverScale, StateUpdatedRemote
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local FullScreen = require(script.Parent.PanelFullScreen)

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
	panel.AnchorPoint = Vector2.new(0, 0.5)
	panel.Size = UDim2.new(1, -280, 0.9, 0) -- right of the HUD sidebar (fitPanel keeps it exact)
	panel.Position = UDim2.new(0, 260, 0.5, 0)
	panel.BackgroundTransparency = 1
	panel.ZIndex = 41
	panel.Parent = backdrop
	deps.addSoftShadow(panel, 18)

	local function fitPanel() -- Engine/LedgerPages.panelRect keeps the desk off the sidebar
		local cam = workspace.CurrentCamera
		if not cam then return end
		local vp = cam.ViewportSize
		local r = Pages.panelRect(vp.X, vp.Y)
		FullScreen.setRect(panel, UDim2.new(0, r.w, 0, r.h), UDim2.new(0, r.x, 0.5, 0))
	end
	fitPanel()
	local bookLayer = Instance.new("Frame") -- everything the old open ledger book draws; hidden while the painted desk is up
	bookLayer.Name = "BookLayer"
	bookLayer.BackgroundTransparency = 1
	bookLayer.Size = UDim2.fromScale(1, 1)
	bookLayer.Active = false
	bookLayer.ZIndex = 41
	bookLayer.Parent = panel
	local book = LedgerBook.build(deps, bookLayer)
	local L = Pages.LAYOUT
	local title -- the "Tavern Ledger" label, made below; the room moves it into a one-line strip above the picture
	-- the painted ledger desk (stats_room_a): used when the window is big enough and the Image id is recorded, else the book above
	local room = require(script.Parent.StatsRoom).new({
		panel = panel, screenGui = deps.screenGui, hide = { bookLayer }, getState = deps.getLatestState, backdrop = backdrop,
		onMode = function(on)
			if not title then return end
			if on then -- one line in the header strip (the picture starts below it), never over the painted lamps
				title.Position, title.Size, title.TextSize = UDim2.fromOffset(0, 6), UDim2.new(1, 0, 0, 40), 26
			else
				title.Position, title.Size, title.TextSize = UDim2.fromScale(L.title.x, L.title.y), UDim2.fromScale(L.title.w, L.title.h), 28
			end
		end,
		plainRect = function()
			local cam = workspace.CurrentCamera
			local vp = cam and cam.ViewportSize or Vector2.new(1920, 1080)
			return Pages.panelRect(vp.X, vp.Y)
		end,
	})

	title = Instance.new("TextLabel")
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
	pcall(function() require(script.Parent.TomeHeaderPlate).attach(panel, "stats", title, nil, { follow = true }) end)

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

	require(script.Parent.PanelTabs).attach(backdrop, "stats", deps.playClickSfx, panel) -- shared tab strip + Back
	OverlayManager.register("stats", function()
		deps.popOut(backdrop, panel)
	end)
	local function openThisPanel()
		deps.playClickSfx()
		OverlayManager.closeAllExcept("stats")
		fitPanel()
		if room.layout() then
			room.paint()
		else
			book.setPage(1)
			book.refresh(true)
		end
		deps.popIn(backdrop, panel)
	end
	do -- a resized window re-decides painted desk or book
		local cam = workspace.CurrentCamera
		if cam then
			cam:GetPropertyChangedSignal("ViewportSize"):Connect(function()
				if backdrop.Visible then
					if room.layout() then room.paint() else book.refresh(false) end
				end
			end)
		end
	end
	OverlayManager.registerOpener("stats", openThisPanel)
	deps.openButton.MouseButton1Click:Connect(openThisPanel)
	require(script.Parent.CloseX).retire(closeButton)
	require(script.Parent.CloseX).attach(panel, function()
		deps.playClickSfx()
		deps.popOut(backdrop, panel)
	end)
	deps.StateUpdatedRemote.OnClientEvent:Connect(function()
		task.defer(function()
			if backdrop.Visible then
				if room.on then room.paint() else book.refresh(false) end
			end
		end)
	end)

	return {}
end
