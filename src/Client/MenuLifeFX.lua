--[[
	Client/MenuLifeFX.lua
	Plays Engine/MenuLife on the main menu: the logo rises 16 px and fades in over 0.5 s, buttons lift 4 px on hover (with the
	hover sound), and a one line tip under the buttons rotates every 6 s. Calm mode and Reduce motion create no tween and no
	loop: the logo is simply there, a button does not move, and the first tip stays. The fire pulse and dust motes already live in
	MenuScene (Menu keeps its own fire, candle and motes), so they are not repeated here.

	new(menuFrame, calmFn)  -> { logoOffset(now) -> rise px, begin(now), stop(), hover(object, on) }
]]

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Life = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("MenuLife"))

local M = {}

function M.new(menuFrame, calm)
	local self = {}
	local startedAt = os.clock()
	local token = 0

	local tip = Instance.new("TextLabel")
	tip.Name = "MenuTip"
	tip.AnchorPoint = Vector2.new(0, 0)
	tip.BackgroundColor3 = Color3.fromRGB(58, 38, 22) -- dark wood plate (cream text is over 10:1), like All actions
	tip.BackgroundTransparency = 0
	tip.Font = Enum.Font.Garamond
	tip.TextSize = 18
	tip.TextColor3 = Color3.fromRGB(255, 244, 214)
	tip.TextTransparency = 0
	tip.TextStrokeColor3 = Color3.fromRGB(30, 20, 12)
	tip.TextStrokeTransparency = 0.4
	tip.TextWrapped = false
	tip.TextTruncate = Enum.TextTruncate.AtEnd
	tip.Text = Life.tipAt(0)
	tip.Active = false
	tip.ZIndex = 12
	tip.Parent = menuFrame
	do
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, 7)
		c.Parent = tip
		local st = Instance.new("UIStroke")
		st.Color = Color3.fromRGB(201, 162, 77)
		st.Thickness = 2
		st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		st.Parent = tip
	end

	local function fit()
		local size = menuFrame.AbsoluteSize
		local r = Life.tipRect(size.X, size.Y)
		tip.Visible = r ~= nil
		if r then
			tip.Position = UDim2.fromOffset(r.x, r.y)
			tip.Size = UDim2.fromOffset(r.w, r.h)
		end
	end
	menuFrame:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	fit()
	pcall(function() require(script.Parent.TavernKit).paintedButton(tip, "secondary") end) -- ornate dark wood plate like All actions, flat look if it does not load
	local pad = Instance.new("UIPadding"); pad.Name = "TipPad"; pad.PaddingLeft = UDim.new(0, 28); pad.PaddingRight = UDim.new(0, 28); pad.Parent = tip -- text clear of the gold frame ends

	function self.begin(now)
		startedAt = now or os.clock()
		token += 1
		tip.Text = Life.tipAt(0)
		if calm() then return end -- the first tip stays
		local mine = token
		task.spawn(function()
			while mine == token and tip.Parent do
				task.wait(Life.TIP_SECONDS)
				if mine ~= token or not menuFrame.Visible then return end
				tip.Text = Life.tipAt(os.clock() - startedAt)
			end
		end)
	end
	function self.stop() token += 1 end

	-- pixels the logo still has to climb; fed to the parallax layer base each frame
	function self.logoOffset(now)
		return Life.logo((now or os.clock()) - startedAt, calm()).rise
	end

	-- a menu button object rises 4 px while hovered, with the hover sound
	function self.hover(object, on)
		local lift = Life.hoverLift(calm())
		if not lift or not object or not object.Parent then return end
		TweenService:Create(object, TweenInfo.new(Life.HOVER_SECONDS, Enum.EasingStyle.Quad), {
			Position = UDim2.new(0.5, 0, 0.5, on and -lift or 0),
		}):Play()
		if on then pcall(require(script.Parent.Cue).play, "hover") end
	end

	return self
end

return M
