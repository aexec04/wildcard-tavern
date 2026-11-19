--[[
	Client/Gameplay2FeelFX.lua
	Plays Engine/Gameplay2Feel on the Gameplay v2 table. Only decoration: it never moves the real buttons (their rects are the
	click rects), it moves their label and adds a gold ring inside them.

	  setLegal(playButton, legal)  a gentle gold ring on Play Hand while the selection is a legal play (1.6 s sine, FxLoop;
	                               Calm mode: a steady ring and no loop)
	  wirePress(button)            on press the label drops 3 px and springs back (once per button; none in Calm mode)
	  shake(button)                a short sideways shake of the label when nothing is selected
	  tick(pill, old, new)         the pill number pops when it changes (HudTickFX)
]]

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Rules = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("Gameplay2Feel"))
local ClientSettings = require(script.Parent.ClientSettings)
local FxLoop = require(script.Parent.FxLoop)

local M = {}
local glowLoops = setmetatable({}, { __mode = "k" })

local function calm() return ClientSettings.get("reduceShake") == true end

local function ring(btn)
	local s = btn:FindFirstChild("ReadyGlow")
	if not s then
		s = Instance.new("UIStroke")
		s.Name = "ReadyGlow"
		s.Color = Color3.fromRGB(244, 196, 70)
		s.Thickness = 4
		s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		s.Transparency = 1
		s.Parent = btn
	end
	return s
end

function M.setLegal(btn, legal)
	if not btn or not btn.Parent then return end
	local s = ring(btn)
	local loop = glowLoops[btn]
	if not legal then
		if loop then loop.cancel(); glowLoops[btn] = nil end
		s.Transparency = 1
		return
	end
	if calm() then
		if loop then loop.cancel(); glowLoops[btn] = nil end
		s.Transparency = 1 - Rules.glow(0, true)
		return
	end
	if loop then return end
	local t0 = os.clock()
	glowLoops[btn] = FxLoop.add(function()
		if not btn.Parent then glowLoops[btn] = nil; return true end
		s.Transparency = 1 - Rules.glow(os.clock() - t0, false)
	end, 0.05)
end

local function label(btn) return btn:FindFirstChild("KitLabel") end

function M.wirePress(btn)
	if not btn or btn:GetAttribute("FeelPress") then return end
	btn:SetAttribute("FeelPress", true)
	local function move(down)
		local l = label(btn)
		local p = Rules.press(calm())
		if not l or not p then return end
		TweenService:Create(l, TweenInfo.new(down and p.down or p.up, down and Enum.EasingStyle.Quad or Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Position = UDim2.fromOffset(0, down and p.px or 0) }):Play()
	end
	btn.MouseButton1Down:Connect(function() move(true) end)
	btn.MouseButton1Up:Connect(function() move(false) end)
	btn.MouseLeave:Connect(function() move(false) end)
end

function M.shake(btn)
	local l = btn and label(btn)
	local p = Rules.shake(calm())
	if not l or not p then return end
	task.spawn(function()
		for i = 1, p.count do
			if not l.Parent then return end
			TweenService:Create(l, TweenInfo.new(p.dur, Enum.EasingStyle.Sine), { Position = UDim2.fromOffset(i % 2 == 0 and -p.px or p.px, 0) }):Play()
			task.wait(p.dur)
		end
		if l.Parent then TweenService:Create(l, TweenInfo.new(p.dur), { Position = UDim2.fromOffset(0, 0) }):Play() end
	end)
end

function M.tick(pill, old, new)
	if not pill or Rules.pillTick(old, new, calm()) == nil then return end
	pcall(function() require(script.Parent.HudTickFX).pop(pill, old, new) end)
end

return M
