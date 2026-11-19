--[[
	Client/IdleLifeFX.lua
	Plays Engine/IdleLife on the Concept T play screen: after 8 s without input the hand cards breathe, Play Hand glows softly
	while a legal selection exists, and after 20 s a one line hint fades in. The first input stops it all. One 15 Hz step on
	the shared Client/FxLoop, no tweens; Calm mode and Reduce motion never start the loop.

	attach({ layer, handFrame, playButton, cards = fn -> table, selectedCount = fn -> n, rect = fn -> stage rect or nil,
	         visible = fn -> bool }) -> { destroy() }
]]

local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Idle = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("IdleLife"))
local ClientSettings = require(script.Parent.ClientSettings)

local M = {}

function M.attach(deps)
	local self = {}
	local lastInput = os.clock()
	local lifted = {} -- card -> { base = its own AnchorPoint, wrote = the one this breath set }, given back on input
	local function calm() return ClientSettings.get("reduceShake") == true end

	local function settle()
		for card, e in pairs(lifted) do
			-- give the base back only while the anchor is still the one this breath wrote (another module may have moved it since)
			if card.Parent and card.AnchorPoint == e.wrote then card.AnchorPoint = e.base end
		end
		lifted = {}
	end

	local plate = Instance.new("TextLabel")
	plate.Name = "IdleHint"
	plate.AnchorPoint = Vector2.new(0.5, 0)
	plate.BackgroundColor3 = Color3.fromRGB(28, 18, 12)
	plate.BackgroundTransparency = 1
	plate.BorderSizePixel = 0
	plate.Active = false
	plate.Visible = false
	plate.Font = Enum.Font.Merriweather
	plate.TextSize = 16
	plate.TextColor3 = Color3.fromRGB(255, 244, 214)
	plate.TextStrokeColor3 = Color3.fromRGB(30, 18, 8)
	plate.TextTransparency = 1
	plate.TextStrokeTransparency = 1
	plate.Text = Idle.HINT_TEXT
	plate.ZIndex = 8
	plate.Parent = deps.layer
	local pc = Instance.new("UICorner")
	pc.CornerRadius = UDim.new(0, 10)
	pc.Parent = plate

	local glow = Instance.new("Frame")
	glow.Name = "IdleGlow"
	glow.BackgroundTransparency = 1
	glow.BorderSizePixel = 0
	glow.Active = false
	glow.Size = UDim2.fromScale(1, 1)
	glow.ZIndex = deps.playButton.ZIndex + 1
	glow.Visible = false
	glow.Parent = deps.playButton
	local gc = Instance.new("UICorner")
	gc.CornerRadius = UDim.new(0, 14)
	gc.Parent = glow
	local gs = Instance.new("UIStroke")
	gs.Color = Color3.fromRGB(255, 226, 120)
	gs.Thickness = 3
	gs.Transparency = 1
	gs.Parent = glow

	local function reset()
		lastInput = os.clock()
		settle()
		glow.Visible = false
		plate.Visible = false
	end

	local conns = {
		UserInputService.InputBegan:Connect(reset),
		UserInputService.InputChanged:Connect(function(i)
			if i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch then reset() end
		end),
	}

	local loop = require(script.Parent.FxLoop).add(function()
		if calm() or not deps.visible() then
			if next(lifted) or glow.Visible or plate.Visible then reset() end
			return
		end
		local idle = os.clock() - lastInput
		if idle < Idle.IDLE_AFTER then return end
		local cards = deps.cards()
		for i = 1, #cards do
			local c = cards[i]
			if c and c.Parent and c.AbsoluteSize.Y > 0 then
				local e = lifted[c]
				if not e then e = { base = c.AnchorPoint, wrote = c.AnchorPoint }; lifted[c] = e
				elseif c.AnchorPoint ~= e.wrote then e.base = c.AnchorPoint end -- someone else moved it: that is the new base
				local px = Idle.breath(i, idle, false)
				e.wrote = Vector2.new(e.base.X, e.base.Y - px / c.AbsoluteSize.Y)
				c.AnchorPoint = e.wrote
			end
		end
		local n = deps.selectedCount()
		local g = Idle.playGlow(idle, n >= 1 and n <= 5, false)
		glow.Visible = g > 0
		gs.Transparency = 1 - 0.7 * g
		local h = Idle.hint(idle, false)
		local rect = deps.rect and deps.rect()
		local guided = deps.layer:FindFirstChild("GuidedHint")
		if h and rect and not (guided and guided.Visible) then
			plate.Visible = true
			plate.Size = UDim2.fromOffset(rect.w, rect.h)
			plate.Position = UDim2.fromOffset(rect.x + rect.w / 2, rect.y)
			plate.BackgroundTransparency = 1 - 0.9 * h.alpha
			plate.TextTransparency = 1 - h.alpha
			plate.TextStrokeTransparency = 1 - 0.8 * h.alpha
		else
			plate.Visible = false
		end
	end, 1 / 15)

	function self.destroy()
		loop.cancel()
		for _, c in ipairs(conns) do c:Disconnect() end
		settle()
		glow:Destroy()
		plate:Destroy()
	end
	return self
end

return M
