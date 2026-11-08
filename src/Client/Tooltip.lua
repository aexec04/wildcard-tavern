--[[
	Client/Tooltip.lua
	THE shared tooltip. One Frame named "Tooltip" with a single outer border (UIStroke), padding inside it
	and a max width with wrapping (Engine/TooltipSpec), so text never touches a line and a long text never
	runs to the screen edge. No polishPanel here on purpose: its inner rim frame used to cut through the text.
	Every addTooltip call in the game goes through attach().

	  local tip = Tooltip.new(screenGui)
	  tip.attach(button, textOrFn, align?)   hover shows it above the button (below if no room), clamped
	  tip.hide()                            hides it now (overlays opening, phase changes)
	  tip.frame                             the Frame (InputGuard hides it while an overlay is open)

	It hides when the target is hidden or destroyed (MouseLeave never fires then). Text can be a string or
	a zero-arg function evaluated on each hover.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local TooltipSpec = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("TooltipSpec"))
local Spec = TooltipSpec.Spec

local Tooltip = {}

function Tooltip.new(screenGui)
	local frame = Instance.new("Frame")
	frame.Name = "Tooltip"
	frame.AutomaticSize = Enum.AutomaticSize.XY
	frame.Size = UDim2.fromOffset(0, 0)
	frame.BackgroundColor3 = Color3.fromRGB(26, 19, 13)
	frame.BackgroundTransparency = 0.04
	frame.BorderSizePixel = 0
	frame.Visible = false
	frame.Active = false
	frame.ZIndex = 100
	frame.Parent = screenGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = frame

	local border = Instance.new("UIStroke") -- the ONE border
	border.Name = "TooltipBorder"
	border.Color = Color3.fromRGB(205, 170, 95)
	border.Thickness = Spec.stroke
	border.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	border.Parent = frame

	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, Spec.padX)
	pad.PaddingRight = UDim.new(0, Spec.padX)
	pad.PaddingTop = UDim.new(0, Spec.padY)
	pad.PaddingBottom = UDim.new(0, Spec.padY)
	pad.Parent = frame

	local limit = Instance.new("UISizeConstraint") -- wrap long text instead of running to the screen edge
	limit.MaxSize = Vector2.new(Spec.maxWidth + 2 * Spec.padX, math.huge)
	limit.Parent = frame

	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.AutomaticSize = Enum.AutomaticSize.XY
	label.Size = UDim2.fromOffset(0, 0)
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.Font = Enum.Font.Gotham
	label.TextSize = Spec.textSize
	label.TextColor3 = Color3.fromRGB(250, 240, 220)
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.RichText = false
	label.Text = ""
	label.ZIndex = 101
	label.Parent = frame
	local labelLimit = Instance.new("UISizeConstraint")
	labelLimit.MaxSize = Vector2.new(Spec.maxWidth, math.huge)
	labelLimit.Parent = label

	local T = { frame = frame }
	local activeConn, leaveConn = nil, nil

	function T.hide()
		frame.Visible = false
		if activeConn then activeConn:Disconnect() activeConn = nil end
		if leaveConn then leaveConn:Disconnect() leaveConn = nil end
	end

	function T.attach(button, text, align)
		button.MouseEnter:Connect(function()
			label.Text = (type(text) == "function") and text() or text
			-- AutomaticSize settles a frame late, so place now and again next frame.
			local function place()
				local x, y = TooltipSpec.place(button.AbsolutePosition, button.AbsoluteSize, frame.AbsoluteSize, screenGui.AbsoluteSize, align)
				frame.AnchorPoint = Vector2.new(0, 0)
				frame.Position = UDim2.fromOffset(x, y)
			end
			place()
			frame.Visible = true
			task.defer(place)
			if activeConn then activeConn:Disconnect() end
			if leaveConn then leaveConn:Disconnect() end
			activeConn = RunService.Heartbeat:Connect(function()
				local alive = button.Parent ~= nil and frame.Visible
				if alive then
					local obj = button
					while obj and not obj:IsA("LayerCollector") do
						if obj:IsA("GuiObject") and not obj.Visible then alive = false break end
						obj = obj.Parent
					end
				end
				if not alive then T.hide() end
			end)
			leaveConn = button.MouseLeave:Connect(function() T.hide() end)
		end)
	end

	return T
end

return Tooltip
