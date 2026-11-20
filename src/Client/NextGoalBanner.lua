-- Next Goal banner for the main menu: one line and a progress bar showing the nearest meaningful goal
-- (finish the tutorial, win a first run, a daily quest, the next unlock, the next Tavern Rank).
-- Display only: the server computes it (Engine/NextGoal.lua) and ships it as state.nextGoal.
-- Menu.lua calls attach(parent, layoutOrder) once; the hub calls update(state) from render in a pcall.
local TweenService = game:GetService("TweenService")

local NextGoalBanner = {}

local GOLD = Color3.fromRGB(222, 182, 104)
local CREAM = Color3.fromRGB(250, 235, 200)
local INK = Color3.fromRGB(60, 40, 22)
local WOOD = Color3.fromRGB(86, 58, 34)

local ui
local shownText, shownRatio

function NextGoalBanner.attach(parent, layoutOrder)
	local frame = Instance.new("Frame")
	frame.Name = "NextGoalBanner"
	frame.Size = UDim2.fromOffset(460, 64) -- same plate and width as the Rank and News notes
	frame.LayoutOrder = layoutOrder
	frame.BackgroundColor3 = WOOD -- the flat look if the painted plate is missing, cream text stays readable
	frame.ZIndex = 10
	frame.Visible = false -- shown once the server sends a goal
	frame.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.Color = GOLD
	stroke.Thickness = 2
	stroke.Parent = frame

	local well = Instance.new("Frame")
	well.Size = UDim2.fromOffset(40, 40)
	well.Position = UDim2.fromOffset(24, 12)
	well.BackgroundColor3 = WOOD
	well.ZIndex = 11
	well.Parent = frame
	local wellCorner = Instance.new("UICorner")
	wellCorner.CornerRadius = UDim.new(0, 20)
	wellCorner.Parent = well
	local wellStroke = Instance.new("UIStroke")
	wellStroke.Color = GOLD
	wellStroke.Thickness = 1.5
	wellStroke.Parent = well
	local icon = Instance.new("TextLabel")
	icon.Name = "Icon"
	icon.Size = UDim2.fromScale(1, 1)
	icon.BackgroundTransparency = 1
	icon.Font = Enum.Font.GothamBold
	icon.TextSize = 22
	icon.TextColor3 = CREAM
	icon.Text = "🎯"
	icon.ZIndex = 12
	icon.Parent = well

	local text = Instance.new("TextLabel")
	text.Name = "Text"
	text.Size = UDim2.new(1, -(72 + 30), 0, 34) -- two lines fit; the board wraps it
	text.Position = UDim2.fromOffset(72, 8)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.GothamBold
	text.TextSize = 15
	text.TextXAlignment = Enum.TextXAlignment.Left
	text.TextTruncate = Enum.TextTruncate.AtEnd
	text.TextColor3 = CREAM -- on the dark painted plate
	text.TextTransparency = 0
	text.TextStrokeTransparency = 1
	text.Text = ""
	text.ZIndex = 11
	text.Parent = frame

	local track = Instance.new("Frame")
	track.Name = "Track"
	track.Size = UDim2.new(1, -(72 + 30), 0, 10)
	track.Position = UDim2.fromOffset(72, 46)
	track.BackgroundColor3 = Color3.fromRGB(40, 28, 18)
	track.ZIndex = 11
	track.Parent = frame
	local trackCorner = Instance.new("UICorner")
	trackCorner.CornerRadius = UDim.new(0, 5)
	trackCorner.Parent = track
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = GOLD
	fill.BorderSizePixel = 0
	fill.ZIndex = 12
	fill.Parent = track
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 5)
	fillCorner.Parent = fill

	ui = { frame = frame, icon = icon, text = text, fill = fill }
	return frame
end

function NextGoalBanner.update(state)
	if not ui or type(state) ~= "table" or type(state.nextGoal) ~= "table" then
		return
	end
	local goal = state.nextGoal
	NextGoalBanner.kind = goal.kind -- the Menu's Notice Board uses it to open the right scroll
	ui.frame.Visible = true
	if shownText ~= goal.text then
		shownText = goal.text
		ui.text.Text = goal.text
		ui.icon.Text = goal.icon or "🎯"
	end
	local ratio = math.clamp(tonumber(goal.ratio) or 0, 0, 1)
	if shownRatio ~= ratio then
		shownRatio = ratio
		TweenService:Create(ui.fill, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = UDim2.fromScale(ratio, 1) }):Play()
	end
end

return NextGoalBanner
