--[[
	Client/ReplayConfirm.lua
	The calm "Replay the tutorial?" popup for Settings > Replay Tutorial (rules and words in Engine/ReplayFlow, tested). Not now is the
	default; Escape and a click on the dark area mean Not now. Replay runs the walkthrough once and changes no saved progress.
	No tween, so Calm mode and Reduce motion need nothing extra.

	ReplayConfirm.ask(onReplay)  opens the popup; onReplay() runs once when the player taps Replay
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Flow = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("ReplayFlow"))
local OverlayManager = require(script.Parent.OverlayManager)

local TEXT = Color3.fromRGB(250, 240, 220)
local GOLD = Color3.fromRGB(222, 182, 104)

local M = {}
local api = nil

function M.install(deps)
	if api then return api end
	local state = Flow.new()
	local pending = nil

	local backdrop = Instance.new("TextButton")
	backdrop.Name = "ReplayConfirmBackdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	backdrop.BackgroundTransparency = 0.35
	backdrop.AutoButtonColor = false
	backdrop.Text = ""
	backdrop.Visible = false
	backdrop.ZIndex = 6000
	backdrop.Parent = deps.screenGui

	local panel = Instance.new("Frame")
	panel.Size = UDim2.new(0, 420, 0, 200)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.BackgroundColor3 = Color3.fromRGB(40, 30, 22)
	panel.Active = true
	panel.ZIndex = 6001
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
		l.ZIndex = 6002
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
		b.ZIndex = 6002
		b.Parent = panel
		deps.polishButton(b, 12)
		-- the equipped Card Set's plate; classic keeps the flat buttons
		if pcall(function() return require(script.Parent.TavernKit).setPlateButton(b, kind) end) and b:GetAttribute("BasePiece") then b.TextColor3 = TEXT end
		return b
	end
	local notNow = button(Flow.NO, 0, 20, Color3.fromRGB(70, 110, 60), "primary")
	local ring = Instance.new("UIStroke")
	ring.Color = GOLD
	ring.Thickness = 3
	ring.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	ring.Parent = notNow
	local yes = button(Flow.YES, 1, -20, Color3.fromRGB(110, 70, 40), "secondary")

	pcall(function()
		local pStroke = panel:FindFirstChildOfClass("UIStroke")
		require(script.Parent.PopupSkin).dark(panel, pStroke, { { titleLabel, Color3.fromRGB(255, 214, 130) }, { message, TEXT } },
			{ plate = Color3.fromRGB(40, 30, 22), edge = pStroke and pStroke.Color })
	end)

	local function close()
		Flow.cancel(state)
		backdrop.Visible = false
	end

	notNow.MouseButton1Click:Connect(function()
		deps.playClickSfx()
		close()
	end)
	yes.MouseButton1Click:Connect(function()
		if not Flow.confirm(state) then return end
		deps.playClickSfx()
		backdrop.Visible = false
		local go = pending
		pending = nil
		Flow.finish(state)
		if go then pcall(go) end
	end)
	backdrop.MouseButton1Click:Connect(close)
	OverlayManager.register("replay-confirm", close)
	pcall(function()
		require(script.Parent.PopupDismiss).attach(backdrop, { policy = "cancel", close = close, panel = panel, outside = false, button = true })
	end)

	api = {
		ask = function(onReplay)
			if not Flow.request(state) then return end
			pending = onReplay
			backdrop.Visible = true
			deps.playClickSfx()
		end,
	}
	return api
end

function M.ask(onReplay)
	if api then api.ask(onReplay) end
end

return M
