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
local TweenService = game:GetService("TweenService")

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

	function T.attach(button, text, align, anchor)
		button.MouseEnter:Connect(function()
			local side = align
			if side == nil and (button:FindFirstAncestor("Sidebar") or button:FindFirstAncestor("SidebarBoard")) then
				side = "right" -- every left HUD tooltip opens beside the panel, never over its controls
			end
			if require(script.Parent.ModalStage).blocks(button) then return end -- a modal is open: nothing behind it reacts
			label.Text = (type(text) == "function") and text() or text
			-- AutomaticSize settles a frame late, so place now and again next frame.
			local lastLog = false -- one Studio warn per hover
			local lastFix = false
			local nudge = Vector2.zero -- absorbed offset between the written and the live position
			local function placeRaw()
				local pos, size = button.AbsolutePosition, button.AbsoluteSize
				if side == "right" then -- measure from the HUD column's edge so the tip clears the whole panel
					local col = button:FindFirstAncestor("SidebarBoard") or button:FindFirstAncestor("Sidebar")
					if col then
						pos = Vector2.new(col.AbsolutePosition.X, pos.Y)
						size = Vector2.new(col.AbsoluteSize.X, size.Y)
					end
				end
				if side == "below" then
						-- measure live from the lowest of the hovered object and its anchor (name plate), so a
						-- hover lift or a small hit area can never put the tip over the plate text
						local bottom = pos.Y + size.Y
						if anchor and anchor.Parent and anchor:IsA("GuiObject") then
							bottom = math.max(bottom, anchor.AbsolutePosition.Y + anchor.AbsoluteSize.Y)
						end
						size = Vector2.new(size.X, bottom - pos.Y + 4) -- place() adds the 8 px gap: 12 in all
					end
					local x, y
					local rowFrame = side == "row" and button:FindFirstAncestor("CardRow") or nil
					if rowFrame then
						local rp, rs = rowFrame.AbsolutePosition, rowFrame.AbsoluteSize
						local tipSize = frame.AbsoluteSize
						x, y = TooltipSpec.placeRow({ X = pos.X, W = size.X },
							{ X = rp.X, Y = rp.Y, H = rs.Y },
							{ X = tipSize.X, Y = tipSize.Y }, screenGui.AbsoluteSize)
					else
						x, y = TooltipSpec.place(pos, size, frame.AbsoluteSize, screenGui.AbsoluteSize, side)
					end
				-- x, y are in absolute screen space; Position is relative to the tooltip's parent
				local origin = frame.Parent and frame.Parent:IsA("GuiObject") and frame.Parent.AbsolutePosition or Vector2.zero
				frame.AnchorPoint = Vector2.new(0, 0)
				frame.Position = UDim2.fromOffset(x - origin.X + nudge.X, y - origin.Y + nudge.Y)
				-- verify against the LIVE rect: whatever else shifts the frame (inset, scale, anchor) is absorbed
				local live = frame.AbsolutePosition
				local nx, ny, changed = TooltipSpec.correct({ X = x, Y = y }, { X = live.X, Y = live.Y }, { X = nudge.X, Y = nudge.Y })
				if changed then
					nudge = Vector2.new(nx, ny)
					frame.Position = UDim2.fromOffset(x - origin.X + nudge.X, y - origin.Y + nudge.Y)
					if RunService:IsStudio() and not lastFix then
						lastFix = true
						warn(string.format("[Tooltip fix] wanted %d,%d live %d,%d nudge %d,%d screen %dx%d",
							x, y, live.X, live.Y, nudge.X, nudge.Y, screenGui.AbsoluteSize.X, screenGui.AbsoluteSize.Y))
					end
				end
				if side == "below" and RunService:IsStudio() and not lastLog then
					lastLog = true
					warn(string.format("[Tooltip below] tip %d,%d size %dx%d anchorBottom %s origin %d,%d",
						x, y, frame.AbsoluteSize.X, frame.AbsoluteSize.Y,
						anchor and tostring(math.floor(anchor.AbsolutePosition.Y + anchor.AbsoluteSize.Y)) or "none", origin.X, origin.Y))
				end
			end
			local function place() -- never throws: a bad measurement must not kill the tooltip
				local ok, err = pcall(placeRaw)
				if not ok and RunService:IsStudio() and not lastLog then
					lastLog = true
					warn("[Tooltip] place failed: " .. tostring(err))
				end
			end
			place()
			frame.Visible = true
			task.defer(place)
			if activeConn then activeConn:Disconnect() end
			if leaveConn then leaveConn:Disconnect() end
			activeConn = RunService.Heartbeat:Connect(function()
				if frame.Visible and (side == "below" or side == "row") then place() end -- plates can still be sliding in or lifting
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
