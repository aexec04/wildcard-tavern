--[[
	Client/QuitConfirm.lua
	The calm "Quit to the Tavern?" popup shared by the gear menu row and Settings > Quit to Tavern (rules in Engine/QuitFlow, tested).
	Stay is the default and highlighted; Escape and a click on the dark area mean Stay (PopupDismiss policy "cancel"). Quit goes back to
	the Menu once, however fast it is clicked. No tween, so Calm mode and Reduce motion need nothing extra.

	QuitConfirm.install(deps)  deps = { screenGui, root, menuFrame, polishPanel, polishButton, playClickSfx }  (called once, by Settings)
	QuitConfirm.ask()          opens the popup (also the OverlayManager opener "quitToTavern")
]]

local Layers = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("Layers"))
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Flow = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("QuitFlow"))
local OverlayManager = require(script.Parent.OverlayManager)

local TEXT = Color3.fromRGB(250, 240, 220)
local GOLD = Color3.fromRGB(222, 182, 104)

local M = {}
local api = nil

function M.ask()
	if api then api.open() end
end

function M.install(deps)
	if api then return api end
	local state = Flow.new()
	local root, menuFrame = deps.root, deps.menuFrame

	local function blocked()
		local pg = Players.LocalPlayer and Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
		return pg ~= nil and pg:FindFirstChild("TravelTransition") ~= nil
	end

	local backdrop = Instance.new("TextButton")
	backdrop.Name = "QuitConfirmBackdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	backdrop.BackgroundTransparency = 0.35
	backdrop.AutoButtonColor = false
	backdrop.Text = ""
	backdrop.Visible = false
	backdrop.ZIndex = Layers.confirm
	backdrop.Parent = deps.screenGui

	local panel = Instance.new("Frame")
	panel.Size = UDim2.new(0, 420, 0, 200)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.BackgroundColor3 = Color3.fromRGB(40, 30, 22)
	panel.Active = true
	panel.ZIndex = Layers.confirm + 1
	panel.Parent = backdrop
	deps.polishPanel(panel, 14, "wood")

	local function label(text, size, y, h, color, font)
		local l = Instance.new("TextLabel")
		l.Size = UDim2.new(1, -40, 0, h)
		l.Position = UDim2.new(0, 20, 0, y)
		l.BackgroundTransparency = 1
		l.Font = font
		l.TextSize = size
		l.TextWrapped = true
		l.TextColor3 = color
		l.TextYAlignment = Enum.TextYAlignment.Top
		l.Text = text
		l.ZIndex = Layers.confirm + 2
		l.Parent = panel
		return l
	end
	local titleLabel = label(Flow.TITLE, 22, 14, 30, Color3.fromRGB(255, 214, 130), Enum.Font.GothamBold)
	local message = label(Flow.MESSAGE, 16, 52, 60, TEXT, Enum.Font.Gotham)

	local function button(text, anchorX, posX, color, kind)
		local b = Instance.new("TextButton")
		b.Size = UDim2.new(0, 180, 0, 48)
		b.AnchorPoint = Vector2.new(anchorX, 0)
		b.Position = UDim2.new(anchorX, posX, 1, -64)
		b.Font = Enum.Font.GothamBold
		b.TextSize = 18
		b.Text = text
		b.BackgroundColor3 = color
		b.TextColor3 = TEXT
		b.ZIndex = Layers.confirm + 2
		b.Parent = panel
		deps.polishButton(b, 12)
		-- the equipped Card Set's plate (Stay green, Quit dark); classic keeps the flat buttons
		if pcall(function() return require(script.Parent.TavernKit).setPlateButton(b, kind) end) and b:GetAttribute("BasePiece") then b.TextColor3 = Color3.fromRGB(250, 240, 220) end
		return b
	end
	local stay = button(Flow.STAY, 0, 20, Color3.fromRGB(70, 110, 60), "primary")
	local stroke = Instance.new("UIStroke")
	stroke.Color = GOLD
	stroke.Thickness = 3
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = stay
	local quit = button(Flow.QUIT, 1, -20, Color3.fromRGB(110, 70, 40), "secondary")

	-- the equipped Card Set's panel colours and ink (7:1); classic keeps the wood panel and gold title
	pcall(function()
		local pStroke = panel:FindFirstChildOfClass("UIStroke")
		require(script.Parent.PopupSkin).dark(panel, pStroke, { { titleLabel, Color3.fromRGB(255, 214, 130) }, { message, TEXT } },
			{ plate = Color3.fromRGB(40, 30, 22), edge = pStroke and pStroke.Color })
	end)

	local function close()
		Flow.cancel(state)
		backdrop.Visible = false
	end

	local function open()
		if root.Visible ~= true or not Flow.canOpen(blocked()) then return end
		if not Flow.request(state) then return end
		OverlayManager.closeAllExcept("quit-confirm")
		message.Text = Flow.message(true)
		backdrop.Visible = true
		deps.playClickSfx()
	end

	stay.MouseButton1Click:Connect(function()
		deps.playClickSfx()
		close()
	end)
	quit.MouseButton1Click:Connect(function()
		if not Flow.confirm(state) then return end
		deps.playClickSfx()
		backdrop.Visible = false
		root.Visible = false
		menuFrame.Visible = true
		Flow.finish(state)
	end)
	backdrop.MouseButton1Click:Connect(close)
	OverlayManager.register("quit-confirm", close)
	pcall(function()
		require(script.Parent.PopupDismiss).attach(backdrop, { policy = "cancel", close = close, panel = panel, outside = false, button = true })
	end)

	api = { open = open, close = close }
	return api
end

return M
