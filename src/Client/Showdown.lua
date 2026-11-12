--[[
	Client/Showdown.lua
	The boss clear beat. When a Boss Round is cleared, a gold banner slams in over the table reading the winning
	hand and its score, holds for about 1.2 seconds with a warm vignette and a bright edge flash, then fades. It plays
	alongside the existing defeat beat (Client/BossFight.lua), so the reward flow is never delayed.

	Honest note on "slow motion": there is no global time dilation in this client, so the slow beat is the banner's
	long hold, a soft zoom on the banner and the dimmed table around it. Reduced motion and the Fast animation
	speed skip all of it.

	Showdown.play(state, root): state.lastHand = { name, score } (server payload, from Engine/RunSummary).
]]

local TweenService = game:GetService("TweenService")

local Showdown = {}

local GOLD = Color3.fromRGB(255, 214, 130)
local DARK = Color3.fromRGB(40, 24, 10)
local CREAM = Color3.fromRGB(250, 235, 200)

local busy = false

function Showdown.play(state, root)
	local ClientSettings = require(script.Parent.ClientSettings)
	if busy or not root or ClientSettings.get("reduceShake") == true or ClientSettings.get("animSpeed") == "fast" then
		return
	end
	local hand = state and state.lastHand
	if not hand or not hand.name then
		return
	end
	busy = true

	local layer = Instance.new("Frame")
	layer.Name = "ShowdownLayer"
	layer.Size = UDim2.fromScale(1, 1)
	layer.BackgroundTransparency = 1
	layer.Active = false -- never blocks input
	layer.ZIndex = 60
	layer.Parent = root

	-- the old flat dark dim over the whole table is gone: a soft gold glow on the banner, a faint edge vignette and a few drifting motes
	local FlashFX = require(script.Parent.FlashFX)
	local effect = FlashFX.play(root, "showdown", UDim2.fromScale(0.5, 0.42), { zIndex = 60 })

	local banner = Instance.new("Frame")
	banner.Name = "ShowdownBanner"
	banner.AnchorPoint = Vector2.new(0.5, 0.5)
	banner.Position = UDim2.fromScale(0.5, 0.42)
	banner.Size = UDim2.fromOffset(460, 96)
	banner.BackgroundColor3 = DARK
	banner.BackgroundTransparency = 0.05
	banner.BorderSizePixel = 0
	banner.Active = false
	banner.ZIndex = 61
	banner.Parent = layer
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = banner
	local stroke = Instance.new("UIStroke")
	stroke.Color = GOLD
	stroke.Thickness = 3
	stroke.Parent = banner
	local scale = Instance.new("UIScale")
	scale.Scale = 1.5
	scale.Parent = banner

	local function label(text, y, h, size, color)
		local l = Instance.new("TextLabel")
		l.Position = UDim2.fromOffset(0, y)
		l.Size = UDim2.new(1, 0, 0, h)
		l.BackgroundTransparency = 1
		l.Font = Enum.Font.GothamBlack
		l.TextSize = size
		l.TextColor3 = color
		l.TextTransparency = 0
		l.TextStrokeTransparency = 0.3
		l.Text = text
		l.ZIndex = 62
		l.Parent = banner
		return l
	end
	label("FINAL BLOW", 6, 22, 16, GOLD)
	label(string.upper(tostring(hand.name)), 28, 36, 30, CREAM)
	label(string.format("%d", math.floor(tonumber(hand.score) or 0)), 62, 30, 24, GOLD)

	TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	-- the long hold is a slow push-in on the banner
	task.delay(0.3, function()
		if layer.Parent then
			TweenService:Create(scale, TweenInfo.new(1.0, Enum.EasingStyle.Sine), { Scale = 1.06 }):Play()
		end
	end)
	-- 1.2 seconds after it lands, everything fades
	task.delay(1.45, function()
		if not layer.Parent then
			busy = false
			return
		end
		TweenService:Create(banner, TweenInfo.new(0.3), { BackgroundTransparency = 1 }):Play()
		TweenService:Create(stroke, TweenInfo.new(0.3), { Transparency = 1 }):Play()
		for _, child in ipairs(banner:GetChildren()) do
			if child:IsA("TextLabel") then
				TweenService:Create(child, TweenInfo.new(0.3), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
			end
		end
		task.delay(0.35, function()
			effect.stop()
			layer:Destroy()
			busy = false
		end)
	end)
end

return Showdown
