-- Daily Quests panel: three parchment quest cards (icon, name, one line, progress bar, reward chip) and a
-- "new quests in 5h 20m" footer. Opened from the Quests tile on the main menu. Display only: the server picks
-- the quests (Engine/Quests.lua, same three for everyone each UTC day) and pays them when they complete.
--
-- init(deps): { screenGui, openButton, polishPanel, polishButton, roundCorner, playClickSfx, popIn, popOut,
--               getLatestState }.  update(state) is called from render in a pcall to keep an open panel live.
local OverlayManager = require(script.Parent.OverlayManager)

local QuestsPanel = {}

local INK = Color3.fromRGB(60, 40, 22)
local PARCHMENT = Color3.fromRGB(222, 198, 150)
local PARCHMENT_DONE = Color3.fromRGB(176, 190, 140)
local GOLD = Color3.fromRGB(222, 182, 104)
local CREAM = Color3.fromRGB(250, 235, 200)
local WOOD = Color3.fromRGB(86, 58, 34)
local GREEN = Color3.fromRGB(86, 140, 80)

local ui

-- "5h 20m", "42m", "less than a minute"
function QuestsPanel.timeLeftText(seconds)
	seconds = math.max(0, math.floor(seconds or 0))
	local h = math.floor(seconds / 3600)
	local m = math.floor((seconds % 3600) / 60)
	if h > 0 then
		return string.format("%dh %dm", h, m)
	elseif m > 0 then
		return string.format("%dm", m)
	end
	return "less than a minute"
end

local function label(parent, props)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBold
	l.TextColor3 = INK
	l.TextTransparency = 0
	l.TextStrokeTransparency = 1
	l.ZIndex = 32
	for k, v in pairs(props) do
		l[k] = v
	end
	l.Parent = parent
	return l
end

local function buildCard(parent, row, order, roundCorner)
	local card = Instance.new("Frame")
	card.Name = "Quest_" .. row.id
	card.Size = UDim2.new(1, 0, 0, 96)
	card.LayoutOrder = order
	card.BackgroundColor3 = row.done and PARCHMENT_DONE or PARCHMENT
	card.ZIndex = 31
	card.Parent = parent
	roundCorner(card, 10)
	local stroke = Instance.new("UIStroke")
	stroke.Color = row.done and GREEN or INK
	stroke.Thickness = row.done and 2.5 or 1.5
	stroke.Parent = card

	local well = Instance.new("Frame")
	well.Size = UDim2.fromOffset(60, 60)
	well.Position = UDim2.fromOffset(12, 18)
	well.BackgroundColor3 = WOOD
	well.ZIndex = 32
	well.Parent = card
	roundCorner(well, 30)
	local ring = Instance.new("UIStroke")
	ring.Color = GOLD
	ring.Thickness = 2
	ring.Parent = well
	local wellIcon = label(well, { Size = UDim2.fromScale(1, 1), Text = row.done and "✔" or row.icon, TextSize = 30, TextColor3 = CREAM, ZIndex = 33 })
	if not row.done then -- a finished quest keeps its check mark
		require(script.Parent.ArtIcon).apply(well, "quests", row.id, wellIcon, { zIndex = 34, cornerRadius = 30 })
	end

	label(card, {
		Name = "Name", Size = UDim2.new(1, -200, 0, 24), Position = UDim2.fromOffset(86, 8), Text = row.name, TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	label(card, {
		Name = "Desc", Size = UDim2.new(1, -200, 0, 22), Position = UDim2.fromOffset(86, 32), Text = row.desc, TextSize = 15,
		Font = Enum.Font.GothamMedium, TextXAlignment = Enum.TextXAlignment.Left,
	})
	local track = Instance.new("Frame")
	track.Name = "Track"
	track.Size = UDim2.new(1, -200, 0, 14)
	track.Position = UDim2.fromOffset(86, 62)
	track.BackgroundColor3 = Color3.fromRGB(120, 96, 66)
	track.ZIndex = 32
	track.Parent = card
	roundCorner(track, 7)
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(math.clamp(row.progress / math.max(1, row.goal), 0, 1), 1)
	fill.BackgroundColor3 = row.done and GREEN or GOLD
	fill.BorderSizePixel = 0
	fill.ZIndex = 33
	fill.Parent = track
	roundCorner(fill, 7)
	label(card, {
		Name = "Count", Size = UDim2.fromOffset(60, 20), Position = UDim2.new(1, -190, 0, 59), Text = string.format("%d/%d", row.progress, row.goal),
		TextSize = 15, TextXAlignment = Enum.TextXAlignment.Left,
	})

	local reward = Instance.new("Frame")
	reward.Name = "Reward"
	reward.Size = UDim2.fromOffset(104, 56)
	reward.Position = UDim2.new(1, -116, 0, 20)
	reward.BackgroundColor3 = WOOD
	reward.ZIndex = 32
	reward.Parent = card
	roundCorner(reward, 8)
	local rewardStroke = Instance.new("UIStroke")
	rewardStroke.Color = GOLD
	rewardStroke.Thickness = 1.5
	rewardStroke.Parent = reward
	label(reward, { Size = UDim2.new(1, 0, 0.5, 0), Text = "+" .. row.xp .. " XP", TextSize = 16, TextColor3 = CREAM, ZIndex = 33 })
	label(reward, { Size = UDim2.new(1, 0, 0.5, 0), Position = UDim2.fromScale(0, 0.5), Text = "+" .. row.tips .. " Tips", TextSize = 15, TextColor3 = GOLD, ZIndex = 33 })
	return card
end

local function refresh()
	if not ui then
		return
	end
	local state = ui.getLatestState and ui.getLatestState()
	local view = state and state.dailyQuests
	for _, child in ipairs(ui.list:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	if not view then
		ui.footer.Text = "Quests load when you join a run."
		return
	end
	for i, row in ipairs(view.quests) do
		buildCard(ui.list, row, i, ui.roundCorner)
	end
	ui.header.Text = string.format("Daily Quests   %d / %d done", view.doneCount or 0, #view.quests)
	ui.footer.Text = "New quests in " .. QuestsPanel.timeLeftText(view.secondsLeft)
end

function QuestsPanel.init(deps)
	local screenGui = deps.screenGui
	local roundCorner = deps.roundCorner

	local backdrop = Instance.new("Frame")
	backdrop.Name = "QuestsBackdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	backdrop.BackgroundTransparency = 0.4
	backdrop.Visible = false
	backdrop.ZIndex = 30
	backdrop.Parent = screenGui
	require(script.Parent.MenuTitleHider).bind(screenGui, backdrop)

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(560, 440)
	panel.BackgroundColor3 = Color3.fromRGB(40, 30, 22)
	panel.ZIndex = 31
	panel.Parent = backdrop
	deps.polishPanel(panel, 16, "wood")
	local constraint = Instance.new("UISizeConstraint")
	constraint.MaxSize = Vector2.new(560, 440)
	constraint.Parent = panel

	local header = label(panel, {
		Name = "Header", Size = UDim2.new(1, 0, 0, 44), Position = UDim2.fromOffset(0, 6), Text = "Daily Quests", TextSize = 22, TextColor3 = CREAM,
	})

	local list = Instance.new("Frame")
	list.Name = "List"
	list.Size = UDim2.new(1, -40, 0, 3 * 96 + 2 * 10)
	list.Position = UDim2.fromOffset(20, 56)
	list.BackgroundTransparency = 1
	list.ZIndex = 31
	list.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 10)
	layout.Parent = list

	local footer = label(panel, {
		Name = "Footer", Size = UDim2.new(1, -170, 0, 30), Position = UDim2.new(0, 20, 1, -44), Text = "", TextSize = 16, TextColor3 = CREAM,
		TextXAlignment = Enum.TextXAlignment.Left,
	})

	local close = Instance.new("TextButton")
	close.Name = "Close"
	close.Size = UDim2.fromOffset(120, 38)
	close.Position = UDim2.new(1, -140, 1, -48)
	close.Font = Enum.Font.GothamBold
	close.TextSize = 17
	close.Text = "Close"
	close.BackgroundColor3 = Color3.fromRGB(90, 60, 30)
	close.TextColor3 = CREAM
	close.ZIndex = 33
	close.Parent = panel
	deps.polishButton(close, 10)

	ui = {
		backdrop = backdrop, panel = panel, list = list, footer = footer, header = header,
		getLatestState = deps.getLatestState, roundCorner = roundCorner,
	}

	local function open()
		deps.playClickSfx()
		OverlayManager.closeAllExcept("quests")
		refresh()
		deps.popIn(backdrop, panel)
	end
	local function closePanel()
		deps.playClickSfx()
		deps.popOut(backdrop, panel)
	end
	require(script.Parent.PanelTabs).attach(backdrop, "quests", deps.playClickSfx) -- shared tab strip + Back
	OverlayManager.register("quests", function() deps.popOut(backdrop, panel) end)
	OverlayManager.registerOpener("quests", open)
	deps.openButton.MouseButton1Click:Connect(open)
	close.MouseButton1Click:Connect(closePanel)
	-- a click on the dim area closes it too
	backdrop.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			local p = input.Position
			local pos, size = panel.AbsolutePosition, panel.AbsoluteSize
			if p.X < pos.X or p.X > pos.X + size.X or p.Y < pos.Y or p.Y > pos.Y + size.Y then
				closePanel()
			end
		end
	end)
end

-- Called from render() with every state push: keeps an open panel current (a quest just finished).
function QuestsPanel.update(_state)
	if ui and ui.backdrop.Visible then
		refresh()
	end
end

return QuestsPanel
