--[[
	Client/ScreenFadeFX.lua
	Plays Engine/ScreenFade.
	  ScreenFadeFX.watch(root)      0.25 s fade through warm dark when MenuRoot, ShopBackdrop, RoundSelect or GameOver opens
	  ScreenFadeFX.hold(readyFn)    solid warm dark cover while a load runs; a painted "Dealing..." plate after 0.4 s; released
	                                when readyFn returns true (or after 8 s). Used when the travel cover is off (Reduce motion).
	The cover sits in its own ScreenGui below the travel cover and its sink button takes every click while it is up, so no
	input reaches the screen under it during a fade. Calm mode and Reduce motion: no tween is ever created; a fade
	does nothing and hold shows the static cover and plate.
]]
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SF = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("ScreenFade"))
local ClientSettings = require(script.Parent.ClientSettings)

local M = {}
local gui, cover, sink, plate, plateText
local token = 0
local holding = false -- a load cover is up on purpose (it ends itself after 8 s), so the watchdog leaves it alone

local function rgb(t) return Color3.fromRGB(t[1], t[2], t[3]) end
local function calm() return ClientSettings.get("reduceShake") == true end
local function still() return calm() or not ClientSettings.motionAllowed() end

local function ensure()
	if gui and gui.Parent then return true end
	local pg = Players.LocalPlayer and Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if not pg then return false end
	gui = Instance.new("ScreenGui")
	gui.Name = "ScreenFade"
	gui.DisplayOrder = 450
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.Enabled = false
	gui.Parent = pg
	cover = Instance.new("Frame")
	cover.Name = "Cover"
	cover.Size = UDim2.fromScale(1, 1)
	cover.BackgroundColor3 = rgb(SF.COVER)
	cover.BorderSizePixel = 0
	cover.Parent = gui
	sink = Instance.new("TextButton")
	sink.Name = "InputSink"
	sink.Size = UDim2.fromScale(1, 1)
	sink.BackgroundTransparency = 1
	sink.Text = ""
	sink.AutoButtonColor = false
	sink.Active = true
	sink.ZIndex = 2
	sink.Parent = cover
	plate = Instance.new("Frame")
	plate.Name = "DealingPlate"
	plate.AnchorPoint = Vector2.new(0.5, 0.5)
	plate.Position = UDim2.fromScale(0.5, 0.5)
	plate.Size = UDim2.fromOffset(220, 56)
	plate.BackgroundColor3 = rgb(SF.PLATE)
	plate.BorderSizePixel = 0
	plate.Visible = false
	plate.ZIndex = 3
	plate.Parent = cover
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 10); c.Parent = plate
	local s = Instance.new("UIStroke"); s.Color = Color3.fromRGB(222, 182, 104); s.Thickness = 1; s.Parent = plate
	plateText = Instance.new("TextLabel")
	plateText.Name = "Text"
	plateText.Size = UDim2.fromScale(1, 1)
	plateText.BackgroundTransparency = 1
	plateText.Font = Enum.Font.Garamond
	plateText.TextSize = SF.TEXT_SIZE
	plateText.Text = SF.DEALING_TEXT
	plateText.TextColor3 = rgb(SF.TEXT)
	plateText.TextStrokeColor3 = Color3.fromRGB(36, 22, 12)
	plateText.TextStrokeTransparency = 0.4
	plateText.TextTransparency = 0
	plateText.ZIndex = 4
	plateText.Parent = plate
	return true
end

local function release(my)
	if my ~= token or not gui then return end
	gui.Enabled = false
	plate.Visible = false
	cover.BackgroundTransparency = 0
end

-- Fade the cover out over `dur` (no tween when `dur` is 0).
local function fadeOut(my, dur)
	if dur <= 0 then release(my) return end
	local t = TweenService:Create(cover, TweenInfo.new(dur, Enum.EasingStyle.Quad), { BackgroundTransparency = SF.transparencyAt(dur, dur) })
	plate.Visible = false
	t.Completed:Connect(function() release(my) end)
	t:Play()
end

-- One screen opened: warm dark, then fade it away over 0.25 s. Nothing in Calm mode or Reduce motion.
function M.cross()
	local p = SF.plan(calm(), not ClientSettings.motionAllowed())
	if p.fade <= 0 or not ensure() then return end
	local pg = gui.Parent
	if pg and pg:FindFirstChild("TravelTransition") then return end -- the travel cover already hides the cut
	token += 1
	local my = token
	cover.BackgroundTransparency = 0
	plate.Visible = false
	gui.Enabled = true
	fadeOut(my, p.fade)
end

function M.hold(readyFn)
	if not ensure() then return end
	token += 1
	local my = token
	cover.BackgroundTransparency = 0
	plate.Visible = false
	gui.Enabled = true
	local start = os.clock()
	holding = true
	task.spawn(function()
		while my == token do
			local elapsed = os.clock() - start
			local ok, ready = pcall(readyFn)
			ready = ok and ready == true
			if SF.released(elapsed, ready) then break end
			plate.Visible = SF.dealingVisible(elapsed, ready)
			task.wait(0.05)
		end
		if my == token then holding = false fadeOut(my, still() and 0 or SF.DURATION) end
	end)
end

-- the watchdog (Client/InputWatchdogFX): a fade cover that stays up is stuck; a load cover ends itself
function M.busy()
	return gui ~= nil and gui.Parent ~= nil and gui.Enabled and not holding
end

function M.forceRelease()
	token += 1
	holding = false
	if gui and gui.Parent then
		gui.Enabled = false
		plate.Visible = false
		cover.BackgroundTransparency = 0
	end
end

function M.watch(root)
	local hooked = {}
	local function hook(obj)
		if hooked[obj] or not obj:IsA("GuiObject") or not SF.watches(obj.Name) then return end
		hooked[obj] = true
		obj:GetPropertyChangedSignal("Visible"):Connect(function()
			if obj.Visible then pcall(M.cross) end
		end)
	end
	for _, d in ipairs(root:GetDescendants()) do hook(d) end
	root.DescendantAdded:Connect(hook)
end

return M
