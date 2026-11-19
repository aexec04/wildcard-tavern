--[[
	Client/FriendlyErrorFX.lua
	A small painted toast (dark plate, serif text, gold edge, 3 s) for a failed save, a rejected action, a lost connection or a
	reset screen. Words and placement are the tested Engine/FriendlyErrors; a raw error string never reaches the screen.
	A Try again button shows only where it makes sense (a retry function was passed and the kind allows it). The toast never
	takes clicks outside itself and creates no tween, so Calm mode and Reduce motion are the same.

	FriendlyErrorFX.show(kind, retryFn?)     kind = "save" | "rejected" | "offline" | "stuck" | "busy" | "generic"
	FriendlyErrorFX.showRaw(raw, retryFn?)   maps a raw error string to a kind first and shows only the friendly line
	FriendlyErrorFX.watchState(state)        shows the save line once when the server says progress will not save
	FriendlyErrorFX.expect(token, retryFn)   a server reply is expected: no state arrives in 6 s, a "rejected" toast shows
	FriendlyErrorFX.arrived()                a state arrived: cancels every pending expectation
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local FE = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("FriendlyErrors"))
local Watchdog = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("InputWatchdog"))

local M = {}

local gui, plate, label, retryBtn
local lastShown = {}
local shownToken = 0
local savedWarned = false
local pending = {}

local CREAM = Color3.fromRGB(245, 232, 200)
local GOLD = Color3.fromRGB(214, 168, 70)

local function ensure()
	if gui and gui.Parent then return true end
	local pg = Players.LocalPlayer and Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if not pg then return false end
	gui = Instance.new("ScreenGui")
	gui.Name = "FriendlyError"
	gui.DisplayOrder = 460
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.Parent = pg
	plate = Instance.new("Frame")
	plate.Name = "ErrorPlate"
	plate.BackgroundColor3 = Color3.fromRGB(46, 30, 17)
	plate.BackgroundTransparency = 0.04
	plate.BorderSizePixel = 0
	plate.Visible = false
	plate.ZIndex = 10
	plate.Parent = gui
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 10)
	c.Parent = plate
	local s = Instance.new("UIStroke")
	s.Color = GOLD
	s.Thickness = 1
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = plate
	label = Instance.new("TextLabel")
	label.Name = "Text"
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.Merriweather
	label.TextSize = 16
	label.TextColor3 = CREAM
	label.TextTransparency = 0
	label.TextStrokeTransparency = 1
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.ZIndex = 11
	label.Parent = plate
	retryBtn = Instance.new("TextButton")
	retryBtn.Name = "TryAgain"
	retryBtn.AnchorPoint = Vector2.new(1, 0.5)
	retryBtn.Position = UDim2.new(1, -4, 0.5, 0)
	retryBtn.Size = UDim2.fromOffset(FE.BUTTON.w, FE.BUTTON.h)
	retryBtn.BackgroundColor3 = Color3.fromRGB(70, 128, 62)
	retryBtn.BorderSizePixel = 0
	retryBtn.AutoButtonColor = true
	retryBtn.Font = Enum.Font.Merriweather
	retryBtn.TextSize = 16
	retryBtn.TextColor3 = Color3.fromRGB(255, 250, 235)
	retryBtn.TextTransparency = 0
	retryBtn.TextStrokeTransparency = 1
	retryBtn.Text = "Try again"
	retryBtn.ZIndex = 12
	retryBtn.Visible = false
	retryBtn.Parent = plate
	local bc = Instance.new("UICorner")
	bc.CornerRadius = UDim.new(0, 8)
	bc.Parent = retryBtn
	return true
end

local function place()
	local screen = gui.AbsoluteSize
	if screen.X <= 0 then screen = Vector2.new(1920, 1080) end
	local r = FE.rect(screen.X, screen.Y)
	plate.Position = UDim2.fromOffset(r.x, r.y)
	plate.Size = UDim2.fromOffset(r.w, r.h)
	return r
end

function M.show(kind, retryFn)
	local now = os.clock()
	if not FE.shouldShow(kind, lastShown[kind], now) then return false end
	if not ensure() then return false end
	lastShown[kind] = now
	shownToken += 1
	local my = shownToken
	local r = place()
	local withRetry = retryFn ~= nil and FE.retryable(kind)
	label.Text = FE.message(kind)
	label.Position = UDim2.fromOffset(12, 0)
	label.Size = UDim2.new(1, -(withRetry and (FE.BUTTON.w + 24) or 24), 1, 0)
	retryBtn.Visible = withRetry
	if withRetry then
		retryBtn.Active = true
		local conn
		conn = retryBtn.MouseButton1Click:Connect(function()
			conn:Disconnect()
			plate.Visible = false
			pcall(retryFn)
		end)
	end
	plate.Visible = true
	task.delay(FE.HOLD, function()
		if my == shownToken then plate.Visible = false end
	end)
	return true
end

function M.showRaw(raw, retryFn)
	return M.show(FE.kindOf(raw), retryFn)
end

function M.watchState(state)
	if state and state.saveDisabled == true and not savedWarned then
		savedWarned = true
		M.show("save")
	end
end

local wd = Watchdog.new(6)
function M.expect(token, retryFn)
	pending[token] = retryFn or false
	wd:arm(token, os.clock())
	task.delay(wd.limit + 0.1, function()
		for _, id in ipairs(wd:expired(os.clock())) do
			local fn = pending[id]
			pending[id] = nil
			M.show("rejected", fn or nil)
		end
	end)
end

function M.arrived()
	for id in pairs(pending) do
		wd:clear(id)
		pending[id] = nil
	end
end

return M
