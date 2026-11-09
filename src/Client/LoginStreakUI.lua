-- Daily login rewards, as a small popup during play (not a permanent menu panel).
-- Self-contained so the hub only calls init(menuFrame, remote, playClick) once and update(state) from render.
-- Display only: the server (Engine/LoginStreak.lua) decides streaks and claims.
--
-- The popup (chest/gift art, the streak as flame icons, the reward, a Claim button) opens when the game opens
-- with a reward ready and again when a played round ends with one still waiting (Engine/DailyPopup decides),
-- dismisses itself after 12s if ignored, and a claimed reward flies to the Tips counter. A small gift icon sits
-- in the top-right icon row only while a reward is waiting. The "Next unlock" info lives in the Collection
-- header and the run summary now. Nothing sits in the top-left 60px (Roblox's own buttons).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local DailyPopup = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("DailyPopup"))
local ResponsiveLayout = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("ResponsiveLayout"))
local ClientSettings = require(script.Parent.ClientSettings)

local LoginStreakUI = {}

local INK = Color3.fromRGB(60, 40, 22)
local PARCHMENT = Color3.fromRGB(222, 198, 150)
local GOLD = Color3.fromRGB(222, 182, 104)
local GREEN = Color3.fromRGB(86, 140, 80)
local CREAM = Color3.fromRGB(250, 235, 200)
local WOOD = Color3.fromRGB(92, 62, 36)

local AUTO_DISMISS = 12

local ui = { want = {} } -- built pieces, filled by init; want = what the state asks to show
local tracker = {} -- Engine/DailyPopup state
local lastState
local shownToken = 0

local function label(parent, props)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBold
	l.TextColor3 = INK
	l.TextTransparency = 0
	l.TextStrokeTransparency = 1
	l.ZIndex = 91
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
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border -- Contextual would also outline the button text
	s.Parent = parent
end

local function corner(parent, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function overlayOpen(gui, except)
	if not gui then return false end
	for _, child in ipairs(gui:GetChildren()) do
		if child ~= except and child:IsA("GuiObject") and child.Visible and string.sub(child.Name, -8) == "Backdrop" then
			return true
		end
	end
	return false
end

local function flameText(streak)
	local shown, extra = DailyPopup.flames(streak, 7)
	local text = string.rep("🔥", shown)
	if extra > 0 then text = text .. " +" .. extra end
	return text == "" and "🔥" or text
end

local function refreshPopup(login)
	local reward = DailyPopup.nextClaimable(login)
	if not reward then return end
	ui.flames.Text = flameText(login.streak)
	ui.streak.Text = string.format("Day %d streak", login.streak)
	ui.reward.Text = "Today: " .. reward.label
	ui.claimDay = reward.day
	-- the 7-slot ladder (loops): claimed = green check, today = gold ring, later = dim
	for i, slot in ipairs(ui.slots or {}) do
		local row = login.rewards and login.rewards[i]
		if row then
			slot.icon.Text = row.claimed and "✔" or (row.icon or "🎁")
			slot.frame.BackgroundColor3 = row.claimed and GREEN or (row.today and PARCHMENT or Color3.fromRGB(150, 134, 104))
			slot.stroke.Color = row.today and GOLD or INK
			slot.stroke.Thickness = row.today and 3 or 1.5
			slot.icon.TextTransparency = (row.claimed or row.today) and 0 or 0.45
		end
	end
end

local function hidePopup(instant)
	shownToken = shownToken + 1
	if not ui.popup.Visible then return end
	if instant or ClientSettings.get("animSpeed") == "fast" then
		ui.popup.Visible = false
		return
	end
	local mine = shownToken
	TweenService:Create(ui.scale, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0.85 }):Play()
	task.delay(0.15, function()
		if shownToken == mine then ui.popup.Visible = false end
	end)
end

local function showPopup()
	local login = lastState and lastState.login
	if not (login and DailyPopup.nextClaimable(login)) then return end
	refreshPopup(login)
	shownToken = shownToken + 1
	local mine = shownToken
	ui.popup.Visible = true
	if ClientSettings.get("reduceShake") == true or ClientSettings.get("animSpeed") == "fast" then
		ui.scale.Scale = 1
	else
		ui.scale.Scale = 0.8
		TweenService:Create(ui.scale, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end
	task.delay(AUTO_DISMISS, function()
		if shownToken == mine and ui.popup.Visible then hidePopup() end
	end)
end

-- A coin flies from the popup to the Tips counter (the left panel) when a reward is claimed.
local function flyCoin()
	local gui = ui.gui
	if not gui or ClientSettings.get("reduceShake") == true then return end
	local from = ui.popup.AbsolutePosition + ui.popup.AbsoluteSize / 2
	local board = gui:FindFirstChild("SidebarBoard", true)
	local to = board and (board.AbsolutePosition + Vector2.new(70, 330)) or Vector2.new(70, 330)
	local coin = Instance.new("TextLabel")
	coin.AnchorPoint = Vector2.new(0.5, 0.5)
	coin.Position = UDim2.fromOffset(from.X, from.Y)
	coin.Size = UDim2.fromOffset(40, 40)
	coin.BackgroundTransparency = 1
	coin.Text = "💰"
	coin.TextSize = 34
	coin.ZIndex = 120
	coin.Parent = gui
	local t = TweenService:Create(coin, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ Position = UDim2.fromOffset(to.X, to.Y), TextTransparency = 0.6 })
	t:Play()
	t.Completed:Once(function() coin:Destroy() end)
end

-- menuFrame: the Menu root; remote: ClaimLoginReward; playClick: optional click sfx.
function LoginStreakUI.init(menuFrame, remote, playClick)
	ui.remote = remote
	ui.playClick = playClick
	local gui = menuFrame:FindFirstAncestorOfClass("ScreenGui")
	ui.gui = gui
	local host = gui or menuFrame

	-- The popup (a ScreenGui child so it also shows during play).
	local popup = Instance.new("Frame")
	popup.Name = "DailyRewardPopup" -- not a "...Backdrop": it never locks the gameplay hit areas
	popup.AnchorPoint = Vector2.new(0.5, 0.5)
	popup.Position = UDim2.fromScale(0.5, 0.42)
	popup.Size = UDim2.fromOffset(380, 316)
	popup.BackgroundColor3 = PARCHMENT
	popup.BorderSizePixel = 0
	popup.Visible = false
	popup.Active = true
	popup.ZIndex = 90
	popup.Parent = host
	corner(popup, 12)
	stroke(popup, GOLD, 3)
	ui.popup = popup
	ui.scale = Instance.new("UIScale")
	ui.scale.Parent = popup
	-- Painted chest (discoveries/chest, already recorded) over the gift emoji, which stays as the fallback.
	local giftEmoji = label(popup, { Position = UDim2.new(0, 0, 0, 8), Size = UDim2.new(1, 0, 0, 54), Text = "🎁", TextSize = 46 })
	pcall(function()
		require(script.Parent.ArtIcon).apply(popup, "discoveries", "chest", giftEmoji, {
			zIndex = 93, cornerRadius = 8, size = UDim2.fromOffset(60, 56), position = UDim2.new(0.5, -30, 0, 4),
		})
	end)
	label(popup, { Position = UDim2.new(0, 0, 0, 62), Size = UDim2.new(1, 0, 0, 28), Text = "Daily reward ready!", TextSize = 22 })
	ui.flames = label(popup, { Position = UDim2.new(0, 10, 0, 92), Size = UDim2.new(1, -20, 0, 30), Text = "", TextSize = 24 })
	ui.streak = label(popup, { Position = UDim2.new(0, 0, 0, 122), Size = UDim2.new(1, 0, 0, 22), Text = "", TextSize = 16 })
	-- Ladder slots: seven small painted medallions (parchment, ink ring), numbered by day.
	ui.slots = {}
	for i = 1, 7 do
		local slotFrame = Instance.new("Frame")
		slotFrame.Name = "LadderSlot" .. i
		slotFrame.Size = UDim2.fromOffset(44, 44)
		slotFrame.Position = UDim2.new(0.5, (i - 4) * 50 - 22, 0, 150)
		slotFrame.BackgroundColor3 = Color3.fromRGB(150, 134, 104)
		slotFrame.ZIndex = 91
		slotFrame.Parent = popup
		corner(slotFrame, 22)
		local slotStroke = Instance.new("UIStroke")
		slotStroke.Color = INK
		slotStroke.Thickness = 1.5
		slotStroke.Parent = slotFrame
		local slotIcon = label(slotFrame, { Size = UDim2.fromScale(1, 1), Text = "", TextSize = 22, ZIndex = 92 })
		label(slotFrame, { Size = UDim2.fromOffset(18, 14), Position = UDim2.new(0.5, -9, 1, -2), Text = tostring(i), TextSize = 14, ZIndex = 92 })
		ui.slots[i] = { frame = slotFrame, icon = slotIcon, stroke = slotStroke }
	end
	ui.reward = label(popup, {
		Position = UDim2.new(0, 16, 0, 206), Size = UDim2.new(1, -32, 0, 28), Text = "", TextSize = 17,
		Font = Enum.Font.GothamMedium, TextWrapped = true,
	})
	local claim = Instance.new("TextButton")
	claim.Name = "Claim"
	claim.AnchorPoint = Vector2.new(0.5, 1)
	claim.Position = UDim2.new(0.5, 0, 1, -14)
	claim.Size = UDim2.fromOffset(180, 46)
	claim.BackgroundColor3 = GREEN
	claim.BorderSizePixel = 0
	claim.AutoButtonColor = true
	claim.Font = Enum.Font.GothamBold
	claim.TextSize = 20
	claim.TextColor3 = CREAM
	claim.Text = "Claim"
	claim.ZIndex = 92
	claim.Parent = popup
	corner(claim, 8)
	stroke(claim, GOLD, 2)
	local later = Instance.new("TextButton") -- small "x" so it can be waved away; it also dismisses itself
	later.Name = "Later"
	later.AnchorPoint = Vector2.new(1, 0)
	later.Position = UDim2.new(1, -8, 0, 8)
	later.Size = UDim2.fromOffset(32, 32)
	later.BackgroundTransparency = 1
	later.Font = Enum.Font.GothamBold
	later.TextSize = 20
	later.TextColor3 = INK
	later.Text = "X"
	later.ZIndex = 92
	later.Parent = popup

	claim.MouseButton1Click:Connect(function()
		if playClick then playClick() end
		if ui.claimDay then
			remote:FireServer(ui.claimDay)
			flyCoin()
		end
		hidePopup()
	end)
	later.MouseButton1Click:Connect(function()
		if playClick then playClick() end
		hidePopup()
	end)

	-- A popup that was waiting on an overlay opens as soon as the overlay closes.
	task.spawn(function()
		while host.Parent do
			pcall(function()
				if ui.pending and not overlayOpen(gui, nil) then
					ui.pending = false
					showPopup()
				end
			end)
			task.wait(0.2)
		end
	end)
end

-- The gift icon in the top-right icon row: only while a reward is waiting.
local function ensureGift()
	if ui.gift and ui.gift.Parent then return ui.gift end
	local gui = ui.gui
	local row = gui and gui:FindFirstChild("CornerIconRow", true)
	if not row then return nil end
	local sibling = row:FindFirstChildWhichIsA("TextButton") or row:FindFirstChildWhichIsA("ImageButton")
	local gift = Instance.new("TextButton")
	gift.Name = "DailyGiftIcon"
	gift.LayoutOrder = 99
	gift.Size = sibling and sibling.Size or UDim2.fromOffset(44, 44)
	gift.BackgroundColor3 = Color3.fromRGB(70, 48, 30)
	gift.Font = Enum.Font.GothamBold
	gift.TextSize = 24
	gift.Text = "🎁"
	gift.Visible = false
	gift.ZIndex = sibling and sibling.ZIndex or 10
	gift.Parent = row
	corner(gift, 10)
	stroke(gift, GOLD, 2)
	gift.MouseButton1Click:Connect(function()
		if ui.playClick then ui.playClick() end
		showPopup()
	end)
	ui.gift = gift
	return gift
end

-- Called from the hub's render with every state push (pcall'd there).
function LoginStreakUI.update(state)
	if not ui.popup or type(state) ~= "table" then
		return
	end
	lastState = state
	local waiting = DailyPopup.nextClaimable(state.login) ~= nil
	local gift = ensureGift()
	if gift then gift.Visible = waiting end
	if waiting then
		if DailyPopup.shouldShow(tracker, state) then
			ui.pending = true -- opens at once unless an overlay is up (the spawn loop above retries)
			if not overlayOpen(ui.gui, nil) then
				ui.pending = false
				showPopup()
			end
		elseif ui.popup.Visible then
			refreshPopup(state.login)
		end
	elseif ui.popup.Visible then
		hidePopup(true) -- claimed (or a new day with nothing to claim)
	end
end

return LoginStreakUI
