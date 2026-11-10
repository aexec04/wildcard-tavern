--[[
	Client/CompactLayout.lua
	Narrow windows and phones (viewport width under 900). Applies the numbers of Engine/ResponsiveLayout.gameplay
	(the same ones the layout test harness checks at 640x360, 800x450, 1280x720 and 1920x1080):

	  * the left stats panel collapses into a slide-out drawer (Client/SidebarSlide, reason "compact") opened by
	    a "Stats" tab at the left edge, so the cards, buttons and the draw pile get the whole width;
	  * the hand row and the action row (Rank, Suit, Play Hand, Discard) use the freed width, and the action row
	    scales down together (a UIScale, so the buttons keep their relative sizes) when it would not fit;
	  * wide windows get today's layout back.

	install{ root, handFrame, actionFrame, SIDEBAR_WIDTH }   once, from the hub; it follows viewport changes.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local R = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("ResponsiveLayout"))
local SidebarSlide = require(script.Parent.SidebarSlide)

local CompactLayout = {}

function CompactLayout.install(deps)
	local root, handFrame, actionFrame = deps.root, deps.handFrame, deps.actionFrame
	local sidebarWidth = deps.SIDEBAR_WIDTH or R.SIDEBAR_W

	local scale = Instance.new("UIScale")
	scale.Name = "CompactScale"
	scale.Parent = actionFrame

	-- the drawer's tab (hit area 44x64, kept clear of Roblox's top-left menu buttons)
	local tab = Instance.new("TextButton")
	tab.Name = "StatsTab"
	tab.Size = UDim2.fromOffset(44, 64)
	tab.Position = UDim2.new(0, 0, 0, 96)
	tab.BackgroundColor3 = Color3.fromRGB(70, 48, 30)
	tab.AutoButtonColor = true
	tab.Font = Enum.Font.GothamBold
	tab.TextSize = 15
	tab.TextColor3 = Color3.fromRGB(250, 235, 200)
	tab.Text = "Stats\n>"
	tab.Visible = false
	tab.ZIndex = 12
	tab.Parent = root
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = tab
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(222, 182, 104)
	stroke.Thickness = 2
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = tab

	local compact, drawerOpen = false, false
	local function apply()
		local cam = workspace.CurrentCamera
		local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
		local layout = R.gameplay(vp.X, vp.Y)
		compact = layout.compact
		if compact then
			handFrame.Position = UDim2.new(0, layout.left, 1, -272)
			handFrame.Size = UDim2.new(0, layout.availW, 0, 176)
			scale.Scale = layout.actionScale
			-- the scaled frame is wider on paper by 1/scale, so its on-screen width is exactly availW
			actionFrame.Position = UDim2.new(0, layout.left, 1, -80)
			actionFrame.Size = UDim2.new(0, layout.availW / layout.actionScale, 0, R.ACTION_H)
		else
			drawerOpen = false
			handFrame.Position = UDim2.new(0, sidebarWidth + 20, 1, -272)
			handFrame.Size = UDim2.new(1, -(sidebarWidth + 40 + R.PILE_RESERVE), 0, 176)
			scale.Scale = 1
			actionFrame.Position = UDim2.new(0, sidebarWidth + 20, 1, -80)
			actionFrame.Size = UDim2.new(1, -(sidebarWidth + 40 + R.PILE_RESERVE), 0, R.ACTION_H)
		end
		tab.Visible = compact
		tab.Position = UDim2.new(0, drawerOpen and sidebarWidth or 0, 0, 96)
		tab.Text = drawerOpen and "Stats\n<" or "Stats\n>"
		SidebarSlide.setReason(root, sidebarWidth, "compact", compact and not drawerOpen)
	end

	tab.MouseButton1Click:Connect(function()
		drawerOpen = not drawerOpen
		apply()
	end)
	local cam = workspace.CurrentCamera
	if cam then cam:GetPropertyChangedSignal("ViewportSize"):Connect(apply) end
	apply()
end

return CompactLayout
