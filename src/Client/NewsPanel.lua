-- News: a slim banner at the top of the main menu for the running live event (one line, art first, emoji until the
-- news art exists) and a small panel listing what is on now and what is coming up. Display only: the data and the
-- rewards come from the server (Engine/LiveEvents.lua -> state.news); Claim fires `ClaimLiveEvent`. Events never
-- change a fair board, and the panel says so.
--
-- attach(parent, layoutOrder)  called by Menu.lua once, builds the banner
-- init(deps)                   { screenGui, polishPanel, polishButton, roundCorner, playClickSfx, popIn, popOut, claimRemote }
-- update(state)                called from render in a pcall
local NewsPanel = {}

local INK = Color3.fromRGB(60, 40, 22)
local PARCHMENT = Color3.fromRGB(222, 198, 150)
local GOLD = Color3.fromRGB(222, 182, 104)
local CREAM = Color3.fromRGB(250, 235, 200)
local WOOD = Color3.fromRGB(86, 58, 34)
local GREEN = Color3.fromRGB(70, 110, 65)

local banner
local ui
local lastNews

-- "2 days left", "Last day", "Starts tomorrow", "Starts in 5 days"
function NewsPanel.timeText(row)
	if row.daysLeft then
		return row.daysLeft <= 1 and "Last day" or (tostring(row.daysLeft) .. " days left")
	end
	local n = row.startsIn or 0
	return n <= 1 and "Starts tomorrow" or ("Starts in " .. tostring(n) .. " days")
end

-- The one line on the banner for the news view, or nil when there is nothing to show.
function NewsPanel.bannerLine(news)
	if type(news) ~= "table" then
		return nil
	end
	local row = news.banner
	if row then
		return row.icon, row.name .. ": " .. row.blurb, NewsPanel.timeText(row)
	end
	local soon = news.upcoming and news.upcoming[1]
	if soon then
		return soon.icon, "Coming up: " .. soon.name, NewsPanel.timeText(soon)
	end
	return nil
end

local function label(parent, props)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBold
	l.TextColor3 = INK
	l.TextTransparency = 0
	l.TextStrokeTransparency = 1
	l.ZIndex = 33
	for k, v in pairs(props) do
		l[k] = v
	end
	l.Parent = parent
	return l
end

function NewsPanel.attach(parent, layoutOrder)
	local frame = Instance.new("TextButton")
	frame.Name = "NewsBanner"
	frame.Size = UDim2.fromOffset(460, 42)
	frame.LayoutOrder = layoutOrder
	frame.BackgroundColor3 = WOOD
	frame.AutoButtonColor = true
	frame.Text = ""
	frame.ZIndex = 10
	frame.Visible = false
	frame.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.Color = GOLD
	stroke.Thickness = 2
	stroke.Parent = frame
	local icon = label(frame, { Name = "Icon", Size = UDim2.fromOffset(40, 40), Position = UDim2.fromOffset(4, 1), Text = "📰", TextSize = 26, TextColor3 = CREAM, ZIndex = 11 })
	local text = label(frame, {
		Name = "Text", Size = UDim2.new(1, -150, 1, 0), Position = UDim2.fromOffset(46, 0), Text = "", TextSize = 15, TextColor3 = CREAM,
		TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 11,
	})
	local time = label(frame, {
		Name = "Time", Size = UDim2.fromOffset(100, 42), Position = UDim2.new(1, -104, 0, 0), Text = "", TextSize = 14, TextColor3 = GOLD,
		TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 11,
	})
	banner = { frame = frame, icon = icon, text = text, time = time }
	frame.MouseButton1Click:Connect(function()
		if ui then
			ui.playClickSfx()
			NewsPanel.open()
		end
	end)
	return frame
end

local function buildActive(row, order)
	local card = Instance.new("Frame")
	card.Name = "Event_" .. row.id
	card.Size = UDim2.new(1, -10, 0, 104)
	card.LayoutOrder = order
	card.BackgroundColor3 = PARCHMENT
	card.ZIndex = 32
	card.Parent = ui.list
	ui.roundCorner(card, 10)
	local stroke = Instance.new("UIStroke")
	stroke.Color = GOLD
	stroke.Thickness = 2
	stroke.Parent = card
	local well = Instance.new("Frame")
	well.Size = UDim2.fromOffset(64, 64)
	well.Position = UDim2.fromOffset(12, 20)
	well.BackgroundColor3 = WOOD
	well.ZIndex = 33
	well.Parent = card
	ui.roundCorner(well, 32)
	local emoji = label(well, { Size = UDim2.fromScale(1, 1), Text = row.icon, TextSize = 34, TextColor3 = CREAM, ZIndex = 34 })
	pcall(function()
		local ContentArt = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("ContentArt"))
		local artId = ContentArt.getImageId("news", row.bannerKey)
		if artId then
			require(script.Parent.PatronPlaque).applyById(well, artId, { emojiLabel = emoji, zIndex = 35, cornerRadius = 32 })
		end
	end)
	label(card, { Size = UDim2.new(1, -230, 0, 24), Position = UDim2.fromOffset(88, 8), Text = row.name, TextSize = 19, TextXAlignment = Enum.TextXAlignment.Left })
	label(card, {
		Size = UDim2.new(1, -230, 0, 40), Position = UDim2.fromOffset(88, 32), Text = row.blurb, TextSize = 15, Font = Enum.Font.GothamMedium,
		TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
	})
	label(card, {
		Size = UDim2.new(1, -230, 0, 22), Position = UDim2.fromOffset(88, 76),
		Text = (#row.rewards > 0 and (table.concat(row.rewards, ", ") .. "  |  ") or "") .. NewsPanel.timeText(row), TextSize = 14,
		TextColor3 = Color3.fromRGB(110, 78, 40), TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
	})
	if row.hasRewards then
		local button = Instance.new("TextButton")
		button.Name = "Claim"
		button.Size = UDim2.fromOffset(110, 38)
		button.Position = UDim2.new(1, -122, 0.5, -19)
		button.Font = Enum.Font.GothamBold
		button.TextSize = 17
		button.TextColor3 = CREAM
		button.ZIndex = 34
		button.Parent = card
		ui.polishButton(button, 10)
		if row.claimed then
			button.Text = "Claimed"
			button.BackgroundColor3 = Color3.fromRGB(110, 120, 90)
			button.Active = false
		else
			button.Text = "Claim"
			button.BackgroundColor3 = GREEN
			button.MouseButton1Click:Connect(function()
				ui.playClickSfx()
				ui.claimRemote:FireServer(row.id)
			end)
		end
	end
end

local function buildUpcoming(row, order)
	local line = label(ui.list, {
		Name = "Soon_" .. row.id, Size = UDim2.new(1, -10, 0, 30), LayoutOrder = order, TextSize = 16, TextColor3 = CREAM,
		Text = string.format("%s %s   %s", row.icon, row.name, NewsPanel.timeText(row)), TextXAlignment = Enum.TextXAlignment.Left,
	})
	line.Font = Enum.Font.GothamMedium
end

local function heading(text, order)
	label(ui.list, { Name = "Head_" .. order, Size = UDim2.new(1, -10, 0, 26), LayoutOrder = order, Text = text, TextSize = 18, TextColor3 = GOLD, TextXAlignment = Enum.TextXAlignment.Left })
end

function NewsPanel.refresh()
	if not ui or not lastNews then
		return
	end
	for _, child in ipairs(ui.list:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local order = 1
	if #lastNews.active > 0 then
		heading("Happening now", order); order += 1
		for _, row in ipairs(lastNews.active) do
			buildActive(row, order); order += 1
		end
	end
	if #lastNews.upcoming > 0 then
		heading("Coming up", order); order += 1
		for _, row in ipairs(lastNews.upcoming) do
			buildUpcoming(row, order); order += 1
		end
	end
	if order == 1 then
		heading("Nothing is on right now. Check back soon!", order)
	end
end

function NewsPanel.open()
	if not ui then
		return
	end
	NewsPanel.refresh()
	ui.popIn(ui.backdrop, ui.panel)
end

function NewsPanel.init(deps)
	local backdrop = Instance.new("Frame")
	backdrop.Name = "NewsBackdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	backdrop.BackgroundTransparency = 0.4
	backdrop.Visible = false
	backdrop.ZIndex = 30
	backdrop.Parent = deps.screenGui
	require(script.Parent.MenuTitleHider).bind(deps.screenGui, backdrop)

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(600, 440)
	panel.BackgroundColor3 = Color3.fromRGB(40, 30, 22)
	panel.ZIndex = 31
	panel.Parent = backdrop
	deps.polishPanel(panel, 16, "wood")
	local constraint = Instance.new("UISizeConstraint")
	constraint.MaxSize = Vector2.new(600, 440)
	constraint.Parent = panel

	label(panel, { Size = UDim2.new(1, 0, 0, 36), Position = UDim2.fromOffset(0, 8), Text = "Tavern News", TextSize = 26, TextColor3 = CREAM })
	label(panel, {
		Size = UDim2.new(1, -40, 0, 22), Position = UDim2.fromOffset(20, 44), TextSize = 15, TextColor3 = GOLD, Font = Enum.Font.GothamMedium,
		Text = "Events never change the Daily, Weekly or Seed boards.",
	})
	local list = Instance.new("ScrollingFrame")
	list.Name = "List"
	list.Size = UDim2.new(1, -40, 1, -150)
	list.Position = UDim2.fromOffset(20, 74)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 6
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new(0, 0, 0, 0)
	list.ZIndex = 31
	list.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 8)
	layout.Parent = list

	local close = Instance.new("TextButton")
	close.Name = "Close"
	close.Size = UDim2.fromOffset(140, 38)
	close.AnchorPoint = Vector2.new(0.5, 1)
	close.Position = UDim2.new(0.5, 0, 1, -12)
	close.Font = Enum.Font.GothamBold
	close.TextSize = 17
	close.Text = "Close"
	close.BackgroundColor3 = Color3.fromRGB(90, 60, 30)
	close.TextColor3 = CREAM
	close.ZIndex = 33
	close.Parent = panel
	deps.polishButton(close, 10)

	ui = {
		backdrop = backdrop, panel = panel, list = list, roundCorner = deps.roundCorner, polishButton = deps.polishButton,
		playClickSfx = deps.playClickSfx, popIn = deps.popIn, popOut = deps.popOut, claimRemote = deps.claimRemote,
	}
	close.MouseButton1Click:Connect(function()
		deps.playClickSfx()
		deps.popOut(backdrop, panel)
	end)
end

function NewsPanel.update(state)
	if type(state) ~= "table" or type(state.news) ~= "table" then
		return
	end
	lastNews = state.news
	if banner then
		local icon, line, time = NewsPanel.bannerLine(lastNews)
		banner.frame.Visible = icon ~= nil
		if icon then
			banner.icon.Text = icon
			banner.text.Text = line
			banner.time.Text = time
		end
	end
	if ui and ui.backdrop.Visible then
		NewsPanel.refresh()
	end
end

return NewsPanel
