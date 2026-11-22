-- Daily Rewards panel: the permanent 7-day ladder. Opened from the Menu tile and from Settings, readable any
-- time (not only when a reward is ready): claimed days wear a green tick, today a gold highlight, then the next
-- reward, the streak and a live countdown to the next claim (UTC midnight, same clock as Engine/LoginStreak).
-- Display only: the server decides streaks and claims; the claim itself stays in the popup (LoginStreakUI).
--
-- init(deps): { screenGui, polishPanel, polishButton, roundCorner, playClickSfx, popIn, popOut, getLatestState }.
-- open() is safe to call before init (it does nothing). update(state) is called from render in a pcall.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LoginStreak = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("LoginStreak"))
local QuestsPanel = require(script.Parent.QuestsPanel) -- timeLeftText

local OverlayManager = require(script.Parent.OverlayManager)

local DailyRewardsPanel = {}

local INK = Color3.fromRGB(60, 40, 22)
local PARCHMENT = Color3.fromRGB(222, 198, 150)
local PARCHMENT_DIM = Color3.fromRGB(176, 158, 120)
local GOLD = Color3.fromRGB(222, 182, 104)
local CREAM = Color3.fromRGB(250, 235, 200)
local GREEN = Color3.fromRGB(86, 140, 80)

local ui

local function label(parent, props)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBold
	l.TextColor3 = CREAM
	l.TextTransparency = 0
	l.TextStrokeTransparency = 1
	l.ZIndex = 32
	for k, v in pairs(props) do
		l[k] = v
	end
	l.Parent = parent
	return l
end

-- Painted art for a reward row: the shared resolver (Tips coin purse, card back); the festival ribbon is the day 7 back.
local RewardArt = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("RewardArt"))
local function artFor(row)
	if row.kind == "cardBack" then return "card_backs", "festival_ribbon" end
	local category, key = RewardArt.resolve(row)
	return category, key
end

DailyRewardsPanel.PANEL_H = 360 -- fits the ladder, next reward and clock; the Close button is retired (the X closes)

function DailyRewardsPanel.countdownText(seconds)
	return QuestsPanel.timeLeftText(seconds)
end

local function secondsLeft()
	return LoginStreak.secondsToNextDay(os.time())
end

local function refresh()
	if not ui then return end
	for _, child in ipairs(ui.row:GetChildren()) do
		if child:IsA("Frame") then child:Destroy() end
	end
	local state = ui.getLatestState and ui.getLatestState()
	local login = state and state.login
	if not (login and login.rewards) then
		ui.streak.Text = "Join a run to see your streak."
		ui.next.Text = ""
		ui.countdown.Text = ""
		return
	end
	local nextRow
	for _, r in ipairs(login.rewards) do
		if r.claimable then nextRow = r end
	end
	for _, r in ipairs(login.rewards) do
		if not nextRow and r.day == ((login.today % #login.rewards) + 1) then nextRow = r end
	end
	for i, r in ipairs(login.rewards) do
		local tile = Instance.new("Frame")
		tile.Name = "Day" .. i
		tile.LayoutOrder = i
		tile.Size = UDim2.new(1 / 7, -8, 1, 0)
		tile.BackgroundColor3 = r.claimed and GREEN or (r.today and PARCHMENT or PARCHMENT_DIM)
		tile.ZIndex = 32
		tile.Parent = ui.row
		ui.roundCorner(tile, 10)
		local s = Instance.new("UIStroke")
		s.Color = r.today and require(script.Parent.TavernKit).ringColor(GOLD) or INK -- the equipped Card Set's accent ring for today; classic keeps gold
		s.Thickness = r.today and 3.5 or 1.5
		s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		s.Parent = tile
		label(tile, { Size = UDim2.new(1, 0, 0, 22), Position = UDim2.fromOffset(0, 4), Text = "Day " .. r.day, TextSize = 15, TextColor3 = INK })
		local icon = label(tile, {
			Size = UDim2.new(1, 0, 0, 56), Position = UDim2.fromOffset(0, 30), Text = r.icon or "🎁", TextSize = 34, ZIndex = 33,
		})
		local cat, key = artFor(r)
		if cat then
			require(script.Parent.ArtIcon).apply(tile, cat, key, icon, {
				zIndex = 34, cornerRadius = 8, size = UDim2.fromOffset(56, 56), position = UDim2.new(0.5, -28, 0, 30),
			})
		end
		label(tile, {
			Size = UDim2.new(1, -8, 0, 40), Position = UDim2.new(0, 4, 1, -46), Text = r.label or "", TextSize = 14,
			TextColor3 = INK, TextWrapped = true,
		})
		if r.claimed then
			local tick = label(tile, {
				Name = "Tick", Size = UDim2.fromOffset(28, 28), Position = UDim2.new(1, -30, 0, 2), Text = "✔", TextSize = 22,
				TextColor3 = CREAM, BackgroundTransparency = 0, BackgroundColor3 = Color3.fromRGB(56, 104, 56), ZIndex = 36,
			})
			ui.roundCorner(tick, 14)
		end
	end
	ui.streak.Text = string.format("Streak: %d day%s", login.streak or 0, (login.streak == 1) and "" or "s")
	ui.next.Text = nextRow and ((nextRow.claimable and "Ready now: " or "Next reward: ") .. (nextRow.label or "")) or ""
	DailyRewardsPanel.tick()
end

-- Called every second while the panel is open.
function DailyRewardsPanel.tick()
	if not ui then return end
	local state = ui.getLatestState and ui.getLatestState()
	local login = state and state.login
	if not (login and login.rewards) then return end
	local waiting = false
	for _, r in ipairs(login.rewards) do
		if r.claimable then waiting = true end
	end
	-- the real clock either way: time left to claim today's reward, or the wait for the next one
	ui.countdown.Text = (waiting and "Time left today: " or "Next reward in ") .. DailyRewardsPanel.countdownText(secondsLeft())
end

function DailyRewardsPanel.init(deps)
	local screenGui = deps.screenGui
	local backdrop = Instance.new("Frame")
	backdrop.Name = "DailyRewardsBackdrop" -- a "...Backdrop": locks the gameplay hit areas while open
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
	panel.Size = UDim2.fromOffset(760, DailyRewardsPanel.PANEL_H)
	panel.BackgroundColor3 = Color3.fromRGB(40, 30, 22)
	panel.ZIndex = 31
	panel.Parent = backdrop
	deps.polishPanel(panel, 16, "wood")
	require(script.Parent.TitleBand).attach(panel)
	local constraint = Instance.new("UISizeConstraint")
	constraint.MaxSize = Vector2.new(760, DailyRewardsPanel.PANEL_H)
	constraint.Parent = panel

	label(panel, { Size = UDim2.new(1, 0, 0, 44), Position = UDim2.fromOffset(0, 8), Text = "Daily Rewards", TextSize = 26 })
	local streak = label(panel, { Size = UDim2.new(1, 0, 0, 24), Position = UDim2.fromOffset(0, 52), Text = "", TextSize = 18, TextColor3 = GOLD })

	local row = Instance.new("Frame")
	row.Name = "Ladder"
	row.Size = UDim2.new(1, -32, 0, 168)
	row.Position = UDim2.fromOffset(16, 90)
	row.BackgroundTransparency = 1
	row.ZIndex = 31
	row.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 8)
	layout.Parent = row

	local nextLabel = label(panel, { Size = UDim2.new(1, -40, 0, 28), Position = UDim2.fromOffset(20, 268), Text = "", TextSize = 20 })
	local countdown = label(panel, { Size = UDim2.new(1, -40, 0, 26), Position = UDim2.fromOffset(20, 298), Text = "", TextSize = 17, TextColor3 = GOLD })

	local close = Instance.new("TextButton")
	close.Name = "Close"
	close.AnchorPoint = Vector2.new(0.5, 1)
	close.Position = UDim2.new(0.5, 0, 1, -16)
	close.Size = UDim2.fromOffset(140, 40)
	close.Font = Enum.Font.GothamBold
	close.TextSize = 17
	close.Text = "Close"
	close.BackgroundColor3 = Color3.fromRGB(90, 60, 30)
	close.TextColor3 = CREAM
	close.ZIndex = 33
	close.Parent = panel
	deps.polishButton(close, 10)

	ui = {
		backdrop = backdrop, panel = panel, row = row, streak = streak, next = nextLabel, countdown = countdown,
		getLatestState = deps.getLatestState, roundCorner = deps.roundCorner, playClickSfx = deps.playClickSfx,
		popIn = deps.popIn, popOut = deps.popOut,
	}
	require(script.Parent.CloseX).retire(close)
	require(script.Parent.CloseX).attach(panel, function()
		deps.playClickSfx()
		deps.popOut(backdrop, panel)
	end)
	-- a click on the dim area and Escape close it through Client/PopupDismiss (registered by PanelTabs.attach below)
	require(script.Parent.PanelTabs).attach(backdrop, "dailyRewards", deps.playClickSfx, panel) -- shared tab strip + Back
	OverlayManager.register("dailyRewards", function() deps.popOut(backdrop, panel) end)
	OverlayManager.registerOpener("dailyRewards", DailyRewardsPanel.open)
	task.spawn(function() -- live countdown, only while visible
		while backdrop.Parent do
			if backdrop.Visible then pcall(DailyRewardsPanel.tick) end
			task.wait(1)
		end
	end)
end

function DailyRewardsPanel.open()
	if not ui then return end
	ui.playClickSfx()
	OverlayManager.closeAllExcept("dailyRewards")
	refresh()
	ui.popIn(ui.backdrop, ui.panel)
end

function DailyRewardsPanel.update(_state)
	if ui and ui.backdrop.Visible then refresh() end
end

return DailyRewardsPanel
