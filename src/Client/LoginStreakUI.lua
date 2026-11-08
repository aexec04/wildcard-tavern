-- Menu extras: the "Next unlock" strip, the daily-rewards calendar button and its popup.
-- Self-contained so the hub only calls init(menuFrame, remote) once and update(state) from render.
-- Display only: the server (Engine/LoginStreak.lua) decides streaks and claims.
local TweenService = game:GetService("TweenService")

local LoginStreakUI = {}

local INK = Color3.fromRGB(60, 40, 22)
local PARCHMENT = Color3.fromRGB(222, 198, 150)
local PARCHMENT_DARK = Color3.fromRGB(199, 178, 137)
local GOLD = Color3.fromRGB(222, 182, 104)
local GREEN = Color3.fromRGB(86, 140, 80)
local CREAM = Color3.fromRGB(250, 235, 200)
local WOOD = Color3.fromRGB(92, 62, 36)

local ui = {} -- built pieces, filled by init
local lastState

local function label(parent, props)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBold
	l.TextColor3 = INK
	l.TextTransparency = 0
	l.TextStrokeTransparency = 1
	l.ZIndex = 40
	for k, v in pairs(props) do
		l[k] = v
	end
	l.Parent = parent
	return l
end

local function stroke(parent, color, thickness)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.Parent = parent
end

local function corner(parent, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function formatLeft(seconds)
	seconds = math.max(0, math.floor(seconds))
	return string.format("%dh %02dm", math.floor(seconds / 3600), math.floor(seconds % 3600 / 60))
end

local function rebuildPopup(login)
	for _, child in ipairs(ui.rows:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	ui.streakLabel.Text = string.format("Login streak: %d day%s", login.streak, login.streak == 1 and "" or "s")
	ui.footer.Text = "A new day starts in " .. formatLeft(login.secondsToNextDay or 0)
		.. ". Miss one day and your streak is safe; miss two and it restarts."
	for index, reward in ipairs(login.rewards) do
		local row = Instance.new("Frame")
		row.LayoutOrder = index
		row.Size = UDim2.new(1, 0, 0, 52)
		row.BackgroundColor3 = PARCHMENT_DARK
		row.BorderSizePixel = 0
		row.ZIndex = 40
		row.Parent = ui.rows
		corner(row, 8)
		stroke(row, reward.claimable and GOLD or INK, reward.claimable and 2 or 1.5)
		label(row, {
			Position = UDim2.new(0, 12, 0, 0), Size = UDim2.new(0, 70, 1, 0), Text = "Day " .. reward.day,
			TextSize = 18, TextXAlignment = Enum.TextXAlignment.Left,
		})
		label(row, {
			Position = UDim2.new(0, 84, 0, 0), Size = UDim2.new(1, -200, 1, 0), Text = reward.label,
			TextSize = 15, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left,
		})
		local button = Instance.new("TextButton")
		button.AnchorPoint = Vector2.new(1, 0.5)
		button.Position = UDim2.new(1, -8, 0.5, 0)
		button.Size = UDim2.new(0, 100, 0, 36)
		button.Font = Enum.Font.GothamBold
		button.TextSize = 16
		button.TextColor3 = CREAM
		button.AutoButtonColor = false
		button.BorderSizePixel = 0
		button.ZIndex = 41
		button.Parent = row
		corner(button, 6)
		if reward.claimed then
			button.Text = "Claimed"
			button.BackgroundColor3 = Color3.fromRGB(120, 110, 95)
		elseif reward.claimable then
			button.Text = "Claim"
			button.BackgroundColor3 = GREEN
			stroke(button, GOLD, 1.5)
			button.MouseButton1Click:Connect(function()
				if ui.playClick then
					ui.playClick()
				end
				ui.remote:FireServer(reward.day)
			end)
		else
			button.Text = "Locked"
			button.BackgroundColor3 = Color3.fromRGB(100, 80, 60)
		end
	end
end

-- menuFrame: the Menu root; remote: ClaimLoginReward; playClick: optional click sfx.
function LoginStreakUI.init(menuFrame, remote, playClick)
	ui.remote = remote
	ui.playClick = playClick

	local strip = Instance.new("Frame")
	strip.Name = "NextUnlockStrip"
	strip.Position = UDim2.new(0, 16, 0, 16)
	strip.Size = UDim2.new(0, 320, 0, 86)
	strip.BackgroundColor3 = PARCHMENT
	strip.BorderSizePixel = 0
	strip.ZIndex = 20
	strip.Visible = false
	strip.Parent = menuFrame
	corner(strip, 8)
	stroke(strip, INK, 1.5)
	ui.strip = strip
	label(strip, {
		Position = UDim2.new(0, 10, 0, 4), Size = UDim2.new(1, -20, 0, 20), Text = "Next unlock",
		TextSize = 16, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 21,
	})
	ui.unlockText = label(strip, {
		Position = UDim2.new(0, 10, 0, 24), Size = UDim2.new(1, -20, 0, 36), Text = "",
		TextSize = 15, Font = Enum.Font.GothamMedium, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 21,
	})
	local barBack = Instance.new("Frame")
	barBack.Position = UDim2.new(0, 10, 1, -20)
	barBack.Size = UDim2.new(1, -20, 0, 10)
	barBack.BackgroundColor3 = PARCHMENT_DARK
	barBack.BorderSizePixel = 0
	barBack.ZIndex = 21
	barBack.Parent = strip
	corner(barBack, 5)
	stroke(barBack, INK, 1)
	ui.barFill = Instance.new("Frame")
	ui.barFill.Size = UDim2.new(0, 0, 1, 0)
	ui.barFill.BackgroundColor3 = GOLD
	ui.barFill.BorderSizePixel = 0
	ui.barFill.ZIndex = 22
	ui.barFill.Parent = barBack
	corner(ui.barFill, 5)

	local open = Instance.new("TextButton")
	open.Name = "DailyRewardsButton"
	open.Position = UDim2.new(0, 16, 0, 110)
	open.Size = UDim2.new(0, 320, 0, 44)
	open.BackgroundColor3 = WOOD
	open.BorderSizePixel = 0
	open.AutoButtonColor = false
	open.Font = Enum.Font.GothamBold
	open.TextSize = 16
	open.TextColor3 = CREAM
	open.Text = "Daily rewards"
	open.ZIndex = 20
	open.Visible = false
	open.Parent = menuFrame
	corner(open, 8)
	stroke(open, GOLD, 2)
	ui.open = open

	-- Popup (parented to the menu so it hides with it).
	local popup = Instance.new("Frame")
	popup.Name = "LoginStreakPopup"
	popup.AnchorPoint = Vector2.new(0.5, 0.5)
	popup.Position = UDim2.fromScale(0.5, 0.5)
	popup.Size = UDim2.new(0, 480, 0, 380)
	popup.BackgroundColor3 = PARCHMENT
	popup.BorderSizePixel = 0
	popup.Visible = false
	popup.Active = true
	popup.ZIndex = 39
	popup.Parent = menuFrame
	corner(popup, 10)
	stroke(popup, GOLD, 3)
	ui.popup = popup
	label(popup, {
		Position = UDim2.new(0, 0, 0, 10), Size = UDim2.new(1, 0, 0, 30), Text = "Daily Rewards", TextSize = 24,
	})
	ui.streakLabel = label(popup, {
		Position = UDim2.new(0, 0, 0, 44), Size = UDim2.new(1, 0, 0, 24), Text = "", TextSize = 18,
	})
	ui.rows = Instance.new("Frame")
	ui.rows.Position = UDim2.new(0, 16, 0, 78)
	ui.rows.Size = UDim2.new(1, -32, 0, 180)
	ui.rows.BackgroundTransparency = 1
	ui.rows.ZIndex = 40
	ui.rows.Parent = popup
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 8)
	layout.Parent = ui.rows
	ui.footer = label(popup, {
		Position = UDim2.new(0, 20, 0, 270), Size = UDim2.new(1, -40, 0, 44), Text = "", TextSize = 15,
		Font = Enum.Font.GothamMedium, TextWrapped = true,
	})
	local close = Instance.new("TextButton")
	close.AnchorPoint = Vector2.new(0.5, 1)
	close.Position = UDim2.new(0.5, 0, 1, -12)
	close.Size = UDim2.new(0, 140, 0, 40)
	close.BackgroundColor3 = WOOD
	close.BorderSizePixel = 0
	close.AutoButtonColor = false
	close.Font = Enum.Font.GothamBold
	close.TextSize = 17
	close.TextColor3 = CREAM
	close.Text = "Close"
	close.ZIndex = 41
	close.Parent = popup
	corner(close, 8)
	stroke(close, GOLD, 1.5)

	local function setOpen(visible)
		popup.Visible = visible
		if visible then
			popup.Size = UDim2.new(0, 440, 0, 350)
			TweenService:Create(popup, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
				{ Size = UDim2.new(0, 480, 0, 380) }):Play()
		end
	end
	open.MouseButton1Click:Connect(function()
		if playClick then
			playClick()
		end
		if lastState and lastState.login then
			rebuildPopup(lastState.login)
		end
		setOpen(not popup.Visible)
	end)
	close.MouseButton1Click:Connect(function()
		if playClick then
			playClick()
		end
		setOpen(false)
	end)
	menuFrame:GetPropertyChangedSignal("Visible"):Connect(function()
		if not menuFrame.Visible then
			popup.Visible = false
		end
	end)
end

-- Called from the hub's render with every state push (pcall'd there).
function LoginStreakUI.update(state)
	if not ui.strip or type(state) ~= "table" then
		return
	end
	lastState = state
	local pick = state.nextUnlock
	ui.strip.Visible = pick ~= nil
	if pick then
		ui.unlockText.Text = pick.label
		ui.barFill.Size = UDim2.new(math.clamp(pick.progress / math.max(1, pick.goal), 0, 1), 0, 1, 0)
	end
	local login = state.login
	ui.open.Visible = login ~= nil
	if login then
		local claimable = false
		for _, reward in ipairs(login.rewards) do
			claimable = claimable or reward.claimable
		end
		if claimable then
			ui.open.Text = string.format("Daily rewards: claim now! (day %d)", login.streak)
		else
			ui.open.Text = string.format("Daily rewards (streak %d)", login.streak)
		end
		if ui.popup.Visible then
			rebuildPopup(login)
		end
	end
end

return LoginStreakUI
