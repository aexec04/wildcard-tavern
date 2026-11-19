--[[
	Client/HudTickFX.lua
	Plays Engine/HudTick on the Concept T HUD: pop(label, old, new) scales a number when it changes, gear(image, hovering)
	turns the gear on hover, deckShake(frame, old, new) wiggles the deck pile when a card is drawn. Every call checks Calm
	mode (reduceShake) and does nothing then, so no tween is ever created.
]]

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Tick = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("HudTick"))
local ClientSettings = require(script.Parent.ClientSettings)

local M = {}

local function calm() return ClientSettings.get("reduceShake") == true end

function M.pop(label, old, new)
	local p = Tick.pop(old, new, calm())
	if not p then return end
	local sc = label:FindFirstChild("TickScale")
	if not sc then
		sc = Instance.new("UIScale")
		sc.Name = "TickScale"
		sc.Parent = label
	end
	local up = TweenService:Create(sc, TweenInfo.new(p.up, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = p.scale })
	up.Completed:Connect(function()
		TweenService:Create(sc, TweenInfo.new(p.down, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 1 }):Play()
	end)
	up:Play()
end

function M.gear(image, hovering)
	local p = Tick.gear(hovering, calm())
	if not p then return end
	TweenService:Create(image, TweenInfo.new(p.dur, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Rotation = p.rotation }):Play()
end

function M.deckShake(frame, old, new)
	local p = Tick.deckShake(old, new, calm())
	if not p then return end
	local base = frame.Rotation
	for i = 1, p.count do
		task.delay((i - 1) * p.dur, function()
			if frame.Parent then
				TweenService:Create(frame, TweenInfo.new(p.dur, Enum.EasingStyle.Sine), { Rotation = base + (i % 2 == 0 and -p.px or p.px) }):Play()
			end
		end)
	end
	task.delay(p.count * p.dur, function()
		if frame.Parent then TweenService:Create(frame, TweenInfo.new(p.dur), { Rotation = base }):Play() end
	end)
end

return M
