--[[
	Client/RestartRun.lua
	Settings > Restart Run. A danger button in the Settings panel opens a confirm popup:
	  "Restart this run? You will lose your progress on this run. Your Collection, Keys and badges are kept."
	Cancel is the default (highlighted). Restart needs a deliberate hold of 1.5s with a filling bar
	(works with a finger too); Esc and a click outside the popup cancel. On confirm the client fires the
	AbandonRun remote (the server validates and counts the run as abandoned, no rewards), returns to the
	main menu and shows a short toast. The button is hidden when no run is active (the in-run root is
	not visible) and disabled while the travel transition is covering the screen.
	The hold rule is Engine/HoldConfirm (tested).

	deps: screenGui, root, menuFrame, polishPanel, polishButton, playClickSfx, addSoftShadow,
	      addButtonHoverScale, popIn, popOut, parent (the Settings scroll), layoutOrder
	Returns: { button, refresh() }  refresh() re-evaluates visible/enabled (call when Settings opens)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local HoldConfirm = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("HoldConfirm"))
local OverlayManager = require(script.Parent.OverlayManager)

local HOLD_SECONDS = 1.5
local TEXT = Color3.fromRGB(250, 240, 220)
local DANGER = Color3.fromRGB(150, 50, 40)
local GOLD = Color3.fromRGB(222, 182, 104)

local MESSAGE = "Restart this run? You will lose your progress on this run. Your Collection, Keys and badges are kept."

local instance = nil

local function build(deps)
	local screenGui = deps.screenGui
	local root = deps.root
	local playClickSfx = deps.playClickSfx
	local polishButton = deps.polishButton

	local function travelActive()
		local player = Players.LocalPlayer
		local pg = player and player:FindFirstChildOfClass("PlayerGui")
		return pg ~= nil and pg:FindFirstChild("TravelTransition") ~= nil
	end

	-- ===== the Settings button =====
	local button = Instance.new("TextButton")
	button.Name = "RestartRunButton"
	button.Size = UDim2.new(1, 0, 0, 40)
	button.LayoutOrder = deps.layoutOrder or 99
	button.Font = Enum.Font.GothamBold
	button.TextSize = 16
	button.Text = "Restart Run"
	button.BackgroundColor3 = DANGER
	button.TextColor3 = TEXT
	button.ZIndex = 21
	button.Parent = deps.parent
	polishButton(button, 12)
	deps.addButtonHoverScale(button)

	local function refresh()
		local inRun = root.Visible == true
		button.Visible = inRun
		local blocked = travelActive()
		button.Active = not blocked
		button.AutoButtonColor = not blocked
		button.BackgroundColor3 = blocked and Color3.fromRGB(90, 70, 65) or DANGER
		button.Text = blocked and "Restart Run (traveling...)" or "Restart Run"
	end
	refresh()

	-- ===== confirm popup =====
	local backdrop = Instance.new("TextButton") -- a click on the dim area (outside the panel) cancels
	backdrop.Name = "RestartConfirmBackdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	backdrop.BackgroundTransparency = 0.35
	backdrop.AutoButtonColor = false
	backdrop.Text = ""
	backdrop.Visible = false
	backdrop.ZIndex = 5040
	backdrop.Parent = screenGui

	local panel = Instance.new("Frame")
	panel.Size = UDim2.new(0, 440, 0, 250)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.BackgroundColor3 = Color3.fromRGB(40, 30, 22)
	panel.Active = true -- sinks clicks so only the dim area cancels
	panel.ZIndex = 5041
	panel.Parent = backdrop
	deps.polishPanel(panel, 14, "wood")
	if deps.addSoftShadow then deps.addSoftShadow(panel, 16) end

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -30, 0, 30)
	title.Position = UDim2.new(0, 15, 0, 14)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.TextSize = 22
	title.TextColor3 = Color3.fromRGB(255, 214, 130)
	title.Text = "Restart Run?"
	title.ZIndex = 5042
	title.Parent = panel

	local message = Instance.new("TextLabel")
	message.Size = UDim2.new(1, -40, 0, 96)
	message.Position = UDim2.new(0, 20, 0, 50)
	message.BackgroundTransparency = 1
	message.Font = Enum.Font.Gotham
	message.TextSize = 16
	message.TextWrapped = true
	message.TextColor3 = TEXT
	message.TextYAlignment = Enum.TextYAlignment.Top
	message.Text = MESSAGE
	message.ZIndex = 5042
	message.Parent = panel

	-- Cancel: the default, highlighted
	local cancel = Instance.new("TextButton")
	cancel.Size = UDim2.new(0, 190, 0, 50)
	cancel.Position = UDim2.new(0, 20, 1, -70)
	cancel.Font = Enum.Font.GothamBold
	cancel.TextSize = 18
	cancel.Text = "Cancel"
	cancel.BackgroundColor3 = Color3.fromRGB(70, 110, 60)
	cancel.TextColor3 = TEXT
	cancel.ZIndex = 5042
	cancel.Parent = panel
	polishButton(cancel, 12)
	local cancelStroke = Instance.new("UIStroke")
	cancelStroke.Color = GOLD
	cancelStroke.Thickness = 3
	cancelStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	cancelStroke.Parent = cancel

	pcall(function() -- the equipped Card Set's plate for Cancel (the red Hold button keeps its danger colour)
		require(script.Parent.TavernKit).setPlateButton(cancel, "primary")
	end)

	-- Restart: hold to confirm, with a fill bar
	local restart = Instance.new("TextButton")
	restart.Size = UDim2.new(0, 190, 0, 50)
	restart.AnchorPoint = Vector2.new(1, 0)
	restart.Position = UDim2.new(1, -20, 1, -70)
	restart.Font = Enum.Font.GothamBold
	restart.TextSize = 17
	restart.Text = "Hold to Restart"
	restart.BackgroundColor3 = DANGER
	restart.TextColor3 = TEXT
	restart.AutoButtonColor = false
	restart.ClipsDescendants = true
	restart.ZIndex = 5042
	restart.Parent = panel
	polishButton(restart, 12)
	local fill = Instance.new("Frame") -- parented to the button so it survives clones/hover scale
	fill.Name = "HoldFill"
	fill.Size = UDim2.new(0, 0, 1, 0)
	fill.BackgroundColor3 = Color3.fromRGB(255, 214, 130)
	fill.BackgroundTransparency = 0.45
	fill.BorderSizePixel = 0
	fill.Active = false
	fill.ZIndex = 5043
	fill.Parent = restart
	restart.TextTransparency = 0
	restart.TextStrokeTransparency = 0.5

	pcall(function() -- the equipped Card Set's panel colours and ink (7:1); classic keeps the wood panel and gold title
		local pStroke = panel:FindFirstChildOfClass("UIStroke")
		require(script.Parent.PopupSkin).dark(panel, pStroke, { { title, Color3.fromRGB(255, 214, 130) }, { message, TEXT } },
			{ plate = Color3.fromRGB(40, 30, 22), edge = pStroke and pStroke.Color })
	end)

	local hold = HoldConfirm.new(HOLD_SECONDS)
	local holdConn = nil
	local isOpen = false

	local function stopHoldLoop()
		if holdConn then
			holdConn:Disconnect()
			holdConn = nil
		end
	end

	local custom = nil -- ask(): a different question with its own onConfirm (default = abandon the run)
	local function resetTexts()
		custom = nil
		title.Text = "Restart Run?"
		message.Text = MESSAGE
		restart.Text = "Hold to Restart"
	end

	local onCloseHook = nil
	local function close()
		local hook = onCloseHook
		onCloseHook = nil
		isOpen = false
		stopHoldLoop()
		hold:reset()
		fill.Size = UDim2.new(0, 0, 1, 0)
		backdrop.Visible = false
		resetTexts()
		if hook then hook() end
	end

	local function toast(text)
		local label = Instance.new("TextLabel")
		label.AnchorPoint = Vector2.new(0.5, 0)
		label.Position = UDim2.new(0.5, 0, 0, 40)
		label.Size = UDim2.new(0, 520, 0, 44)
		label.BackgroundColor3 = Color3.fromRGB(26, 17, 10)
		label.BackgroundTransparency = 0.1
		label.Font = Enum.Font.GothamBold
		label.TextSize = 17
		label.TextColor3 = TEXT
		label.TextWrapped = true
		label.Text = text
		label.ZIndex = 5060
		label.Parent = screenGui
		deps.polishPanel(label, 8, "wood")
		task.delay(2.6, function()
			if require(script.Parent.ClientSettings).motionAllowed() then
				TweenService:Create(label, TweenInfo.new(0.4), { BackgroundTransparency = 1, TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
			else
				label.BackgroundTransparency, label.TextTransparency, label.TextStrokeTransparency = 1, 1, 1 -- Calm: no fade
			end
			task.delay(0.45, function() label:Destroy() end)
		end)
	end

	local function confirmed()
		local action = custom
		close()
		if action then
			action()
			return
		end
		OverlayManager.closeAllExcept("restart-run")
		local remote = ReplicatedStorage:WaitForChild("Remotes"):FindFirstChild("AbandonRun")
		if remote then remote:FireServer() end
		root.Visible = false
		deps.menuFrame.Visible = true
		toast("Run abandoned. Your Collection, Keys and badges are kept.")
	end

	local function startHold()
		if not isOpen or holdConn then return end
		hold = HoldConfirm.new(require(script.Parent.ClientSettings).holdSeconds()) -- Settings > Hold to Confirm
		hold:press(os.clock())
		holdConn = RunService.Heartbeat:Connect(function()
			local now = os.clock()
			fill.Size = UDim2.new(hold:progress(now), 0, 1, 0)
			if hold:update(now) then
				confirmed()
			end
		end)
	end

	local function endHold()
		hold:release(os.clock())
		stopHoldLoop()
		fill.Size = UDim2.new(0, 0, 1, 0)
	end

	restart.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			startHold()
		end
	end)
	restart.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			endHold()
		end
	end)
	restart.MouseLeave:Connect(endHold) -- sliding off the button cancels the hold

	cancel.MouseButton1Click:Connect(function()
		playClickSfx()
		close()
	end)
	backdrop.MouseButton1Click:Connect(function()
		close() -- click outside the panel
	end)
	-- Escape means Cancel (never Restart): Client/PopupDismiss, policy "cancel". The click on the dim area stays above (the backdrop is a button).
	require(script.Parent.PopupDismiss).attach(backdrop, { policy = "cancel", close = close, panel = panel, outside = false, button = true })

	local function open()
		if root.Visible ~= true or travelActive() then return end
		playClickSfx()
		OverlayManager.closeAllExcept("restart-run") -- the gear menu and any other panel close first, so nothing sits over the confirm
		hold:reset()
		fill.Size = UDim2.new(0, 0, 1, 0)
		isOpen = true
		backdrop.Visible = true
	end
	button.MouseButton1Click:Connect(open)
	OverlayManager.register("restart-run", close)
	OverlayManager.registerOpener("restartRun", open) -- the gear menu's Restart run row

	-- Reuse the same hold-to-confirm popup for another question (for example "start a Daily Challenge and
	-- leave this run?"). opts = { title, message, holdText, onConfirm }. Cancel stays the default.
	local function ask(opts)
		resetTexts()
		custom = opts.onConfirm
		onCloseHook = opts.onClose
		title.Text = opts.title or title.Text
		message.Text = opts.message or message.Text
		restart.Text = opts.holdText or restart.Text
		playClickSfx()
		OverlayManager.closeAllExcept("restart-run")
		hold:reset()
		fill.Size = UDim2.new(0, 0, 1, 0)
		isOpen = true
		backdrop.Visible = true
	end

	return { button = button, refresh = refresh, open = open, close = close, ask = ask }
end

return setmetatable({
	get = function() return instance end,
}, {
	__call = function(_, deps)
		instance = build(deps)
		return instance
	end,
})
