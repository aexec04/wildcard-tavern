local Layers = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("Layers"))
-- Daily login rewards, shown as a plate in the post-round overlay queue (Client/OverlayQueue.lua).
-- Self-contained so the hub only calls init(menuFrame, remote, playClick) once and update(state) from render.
-- Display only: the server (Engine/LoginStreak.lua) decides streaks and claims.
--
-- The plate (painted chest, the streak as a row of flame dots, the 7-day ladder, a Claim button, a Not now button) wears
-- the equipped Card Set's reward plate like the other overlay plates. It opens when the game opens with a reward
-- ready and again back at the Menu after a run, never during a run (Engine/DailyPopup decides), closes itself after
-- 12s if ignored, and a claimed reward flies to the Tips counter. A small gift icon sits in the top-right icon row
-- only while a reward is waiting and no run is in progress. No emoji anywhere: painted pieces, with a plain drawn dot when art is missing.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Engine = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine")
local DailyPopup = require(Engine:WaitForChild("DailyPopup"))
local LoginStreak = require(Engine:WaitForChild("LoginStreak"))
local HudKit = require(Engine:WaitForChild("HudKit"))
local ContentArt = require(Engine:WaitForChild("ContentArt"))
local ClientSettings = require(script.Parent.ClientSettings)
local HudTheme = require(script.Parent.HudTheme)
local OverlayQueue = require(script.Parent.OverlayQueue)

local LoginStreakUI = {}

local INK = Color3.fromRGB(52, 34, 18)
local PARCHMENT = Color3.fromRGB(222, 198, 150)
local DIM = Color3.fromRGB(150, 134, 104)
local GOLD = Color3.fromRGB(222, 182, 104)
local GREEN = Color3.fromRGB(86, 140, 80)
local CREAM = Color3.fromRGB(250, 238, 212)
local FLAME = Color3.fromRGB(226, 120, 52)

local AUTO_DISMISS = OverlayQueue.rules.DAILY_AUTO_SECONDS -- 12

local ui = {} -- gui, remote, playClick, queuedId (the daily plate waiting or showing), gift, pending
local tracker = {} -- Engine/DailyPopup state
local lastState
local counter = 0

local function label(parent, props)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBold
	l.TextColor3 = INK
	l.TextTransparency = 0
	l.TextStrokeTransparency = 1
	l.ZIndex = Layers.effect + 53
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
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

local function corner(parent, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function overlayOpen(gui)
	if not gui then return false end
	for _, child in ipairs(gui:GetChildren()) do
		if child:IsA("GuiObject") and child.Visible and string.sub(child.Name, -8) == "Backdrop" then
			return true
		end
	end
	return false
end

local function menuShown()
	return not (ui.menuFrame and ui.menuFrame.Visible == false)
end

local function artId(category, key)
	local ok, id = pcall(ContentArt.getImageId, category, key)
	if ok and type(id) == "string" and id ~= "" then return id end
	return nil
end

-- Painted image id for a reward row (kit icon of the equipped set, else the shared painted art), or nil.
local function iconId(row)
	local setId = HudTheme.setId()
	if row.art == "tips" then
		return (setId and HudKit.piece(setId, "icon_tips")) or artId("hud", "coin_purse")
	elseif row.art == "xp" then
		return HudKit.piece(setId, "icon_target")
	elseif row.art == "cardBack" then
		return (row.id and artId("card_backs", row.id)) or HudKit.piece(setId, "icon_slot")
	end
	return nil
end

local function dot(parent, size, color, z)
	local d = Instance.new("Frame")
	d.AnchorPoint = Vector2.new(0.5, 0.5)
	d.Position = UDim2.fromScale(0.5, 0.5)
	d.Size = UDim2.fromOffset(size, size)
	d.BackgroundColor3 = color
	d.BorderSizePixel = 0
	d.ZIndex = z
	d.Parent = parent
	corner(d, size)
	stroke(d, INK, 1.5)
	return d
end

-- A drawn check mark: two rotated bars.
local function check(parent, z)
	local holder = Instance.new("Frame")
	holder.Name = "Check"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromScale(1, 1)
	holder.ZIndex = z
	holder.Parent = parent
	local function bar(w, h, x, y, rot)
		local f = Instance.new("Frame")
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Size = UDim2.fromOffset(w, h)
		f.Position = UDim2.fromScale(x, y)
		f.Rotation = rot
		f.BackgroundColor3 = CREAM
		f.BorderSizePixel = 0
		f.ZIndex = z
		f.Parent = holder
		corner(f, 2)
	end
	bar(5, 12, 0.38, 0.58, -45)
	bar(5, 20, 0.58, 0.5, 40)
	return holder
end

-- The picture for a ladder slot or the flying coin: a painted image, else a drawn dot.
local function paintIcon(parent, row, size, z)
	local id = iconId(row)
	if id then
		local img = Instance.new("ImageLabel")
		img.Name = "RewardIcon"
		img.AnchorPoint = Vector2.new(0.5, 0.5)
		img.Position = UDim2.fromScale(0.5, 0.5)
		img.Size = UDim2.fromOffset(size, size)
		img.BackgroundTransparency = 1
		img.ScaleType = Enum.ScaleType.Fit
		img.Image = id
		img.ZIndex = z
		img.Parent = parent
		return img
	end
	return dot(parent, math.floor(size * 0.55), GOLD, z)
end

-- A coin flies from the plate to the Tips counter (the left panel) when a reward is claimed.
local function flyCoin()
	local gui = ui.gui
	if not gui or ClientSettings.get("reduceShake") == true then return end
	local plate = gui:FindFirstChild("Plate", true)
	local from = plate and (plate.AbsolutePosition + plate.AbsoluteSize / 2) or (gui.AbsoluteSize / 2)
	local board = gui:FindFirstChild("SidebarBoard", true)
	local to = board and (board.AbsolutePosition + Vector2.new(70, 330)) or Vector2.new(70, 330)
	local coin = Instance.new("Frame")
	coin.AnchorPoint = Vector2.new(0.5, 0.5)
	coin.Position = UDim2.fromOffset(from.X, from.Y)
	coin.Size = UDim2.fromOffset(40, 40)
	coin.BackgroundTransparency = 1
	coin.ZIndex = Layers.effect + 120
	coin.Parent = gui
	local img = paintIcon(coin, { art = "tips" }, 40, 221)
	local t = TweenService:Create(coin, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ Position = UDim2.fromOffset(to.X, to.Y) })
	t:Play()
	if img:IsA("ImageLabel") then
		TweenService:Create(img, TweenInfo.new(0.7), { ImageTransparency = 0.6 }):Play()
	end
	t.Completed:Once(function() coin:Destroy() end)
end

-- Builds the ladder inside the plate's custom holder (OverlayQueue item.custom).
local function buildLadder(holder, painted, login, plateId, laterText)
	local ink = painted and INK or CREAM
	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.Padding = UDim.new(0, 6)
	list.Parent = holder
	local screenW = ui.gui and ui.gui.AbsoluteSize.X or 800
	local availW = math.min(520, screenW - 48) - (painted and 152 or 40)
	local slot = math.max(26, math.min(44, math.floor((availW - 36) / 7)))
	local ladder = Instance.new("Frame")
	ladder.BackgroundTransparency = 1
	ladder.LayoutOrder = 2
	ladder.Size = UDim2.new(1, 0, 0, slot + 16)
	ladder.ZIndex = Layers.effect + 53
	ladder.Parent = holder
	local ll = Instance.new("UIListLayout")
	ll.FillDirection = Enum.FillDirection.Horizontal
	ll.HorizontalAlignment = Enum.HorizontalAlignment.Center
	ll.SortOrder = Enum.SortOrder.LayoutOrder
	ll.Padding = UDim.new(0, 6)
	ll.Parent = ladder
	for i, row in ipairs(login.rewards or {}) do
		local cell = Instance.new("Frame")
		cell.Name = "LadderSlot" .. i
		cell.LayoutOrder = i
		cell.BackgroundTransparency = 1
		cell.Size = UDim2.fromOffset(slot, slot + 16)
		cell.ZIndex = Layers.effect + 53
		cell.Parent = ladder
		local disc = Instance.new("Frame")
		disc.Size = UDim2.fromOffset(slot, slot)
		disc.BackgroundColor3 = row.claimed and GREEN or (row.today and PARCHMENT or DIM)
		disc.BorderSizePixel = 0
		disc.ZIndex = Layers.effect + 54
		disc.Parent = cell
		corner(disc, slot)
		stroke(disc, row.today and GOLD or INK, row.today and 3 or 1.5)
		if row.claimed then
			check(disc, 156)
		else
			local pic = paintIcon(disc, row, math.floor(slot * 0.8), 155)
			if not row.today then
				if pic:IsA("ImageLabel") then pic.ImageTransparency = 0.3 else pic.BackgroundTransparency = 0.3 end
			end
		end
		label(cell, {
			Size = UDim2.new(1, 0, 0, 14), Position = UDim2.fromOffset(0, slot + 1), Text = tostring(i), TextSize = 14, TextColor3 = ink,
		})
	end
	local hint = label(holder, {
		Name = "LaterHint", LayoutOrder = 3, Size = UDim2.new(1, 0, 0, 18), Text = laterText, TextSize = 15, TextColor3 = ink,
		Font = Enum.Font.Gotham,
	})
	hint.ZIndex = Layers.effect + 54
	local later = Instance.new("TextButton") -- "Not now": same brass plate look as Claim, keeps the reward claimable
	later.Name = "NotNow"
	later.LayoutOrder = 4
	later.Size = UDim2.fromOffset(120, 34)
	later.BackgroundColor3 = Color3.fromRGB(70, 48, 30)
	later.Font = Enum.Font.GothamBold
	later.TextSize = 16
	later.TextColor3 = CREAM
	later.Text = "Not now"
	later.AutoButtonColor = true
	later.ZIndex = Layers.effect + 54
	later.Parent = holder
	corner(later, 8)
	stroke(later, GOLD, 2)
	later.Activated:Connect(function()
		if ui.playClick then ui.playClick() end
		OverlayQueue.closeIfCurrent(plateId)
	end)
end

local function showPopup()
	local login = lastState and lastState.login
	local reward = login and DailyPopup.nextClaimable(login)
	if not reward or ui.queuedId or DailyPopup.runActive(lastState) then return end -- nothing to claim, or the daily plate is already queued or showing
	counter += 1
	local id = "daily:" .. counter
	ui.queuedId = id
	local claimDay = reward.day
	local queued = OverlayQueue.enqueue({
		id = id,
		plate = true, -- the daily reward is one of the two big plates (the other is Round Complete); everything else is a corner toast
		priority = OverlayQueue.rules.PRIORITY.daily,
		title = "Daily reward ready!",
		text = string.format("Day %d streak. Today: %s", math.floor(login.streak or 0), reward.label or ""),
		artId = artId("hud", "coin_purse"), -- the chest image has an opaque black background; the purse is the same one the ladder uses
		button = "Claim",
		autoAfter = AUTO_DISMISS,
		customHeight = 60 + 6 + 18 + 6 + 34,
			escapeDismisses = true, -- Escape means Not now, never Claim
		custom = function(holder, painted) buildLadder(holder, painted, login, id, LoginStreak.laterLabel(claimDay)) end,
		onButton = function()
			if ui.remote then ui.remote:FireServer(claimDay) end
			pcall(function() require(script.Parent.Cue).play("reward_claim") end)
			flyCoin()
		end,
		onClose = function() ui.queuedId = nil end,
	})
	if not queued then ui.queuedId = nil end
end

-- menuFrame: the Menu root; remote: ClaimLoginReward; playClick: optional click sfx.
function LoginStreakUI.init(menuFrame, remote, playClick)
	ui.remote = remote
	ui.menuFrame = menuFrame
	ui.playClick = playClick
	local gui = menuFrame:FindFirstAncestorOfClass("ScreenGui")
	ui.gui = gui
	local host = gui or menuFrame
	if gui then OverlayQueue.init(gui) end

	-- A plate that was waiting on another overlay opens as soon as that overlay closes.
	task.spawn(function()
		while host.Parent do
			pcall(function()
				if ui.pending and not ui.suppressed and not overlayOpen(gui) then
					ui.pending = false
					showPopup()
				end
			end)
			task.wait(0.2)
		end
	end)
	ui.ready = true
end

-- Studio DebugGoto only: keeps the daily reward plate from opening on its own (the gift icon still works) and closes one that is up.
function LoginStreakUI.suppress(on)
	ui.suppressed = on and true or false
	if ui.suppressed then
		ui.pending = false
		if ui.queuedId then pcall(OverlayQueue.closeIfCurrent, ui.queuedId) end
	end
end

-- The gift icon in the top-right icon row: only while a reward is waiting and no run is in progress. Painted chest, else a drawn dot.
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
	gift.Text = ""
	gift.Visible = false
	gift.ZIndex = sibling and sibling.ZIndex or 10
	gift.Parent = row
	corner(gift, 27)
	stroke(gift, GOLD, 2)
	pcall(HudTheme.styleIcon, gift) -- same set ring, disc and diamond as the other round buttons
	local chest = artId("discoveries", "chest")
	if chest then
		local img = Instance.new("ImageLabel")
		img.Name = "GiftArt"
		img.AnchorPoint = Vector2.new(0.5, 0.5)
		img.Position = UDim2.fromScale(0.5, 0.5)
		img.Size = UDim2.fromScale(0.62, 0.62)
		img.BackgroundTransparency = 1
		img.ScaleType = Enum.ScaleType.Fit
		img.Image = chest
		img.ZIndex = gift.ZIndex + 4
		img.Parent = gift
	else
		dot(gift, 16, GOLD, gift.ZIndex + 4)
	end
	gift.MouseButton1Click:Connect(function()
		if ui.playClick then ui.playClick() end
		showPopup()
	end)
	ui.gift = gift
	return gift
end

-- Called from the hub's render with every state push (pcall'd there).
function LoginStreakUI.update(state)
	if not ui.ready or type(state) ~= "table" then
		return
	end
	lastState = state
	pcall(function() require(script.Parent.MenuDailyEntry).update(state) end) -- tomorrow's reward line on the Daily note
	local waiting = DailyPopup.nextClaimable(state.login) ~= nil
	local offerable = DailyPopup.canOffer(state, true) -- the chest icon is hidden while a run is in progress
	local gift = ensureGift()
	if gift then gift.Visible = waiting and offerable end
	if DailyPopup.runActive(state) then
		ui.pending = false
		if ui.queuedId then pcall(OverlayQueue.closeIfCurrent, ui.queuedId) end -- a plate that became ready mid run waits for the Menu
		DailyPopup.shouldShow(tracker, state, false) -- records that a run happened
	elseif waiting and not ui.suppressed then
		if DailyPopup.shouldShow(tracker, state, menuShown()) then
			ui.pending = true -- opens at once unless another overlay is up (the spawn loop above retries)
			if not overlayOpen(ui.gui) then
				ui.pending = false
				showPopup()
			end
		end
	elseif ui.queuedId then
		OverlayQueue.closeIfCurrent(ui.queuedId) -- claimed (or a new day with nothing to claim)
	end
end

return LoginStreakUI
