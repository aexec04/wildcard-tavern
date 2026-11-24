--[[
	Client/NightVictory.lua
	The "Tavern Champion" moment: when a run's wonRun flag flips to true, a
	panel pops up with a gold burst, the Night 8 name, run stats (hands
	played, best hand, Patrons used) and the reward earned (if it's new).
	One button continues into Endless Mode.
	No new gameplay: the run was already won and keeps going exactly as before.

	Listens to StateUpdatedRemote itself (task.defer so latestState is
	current). Never fires for the first state it sees, so joining or
	restarting never shows it by accident.

	deps: screenGui, polishPanel, polishButton, roundCorner, addSoftShadow,
	playClickSfx, tweenTo, getLatestState, StateUpdatedRemote,
	getBestHand (function -> { name, score } | nil)

	Returns: {}
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

return function(deps)
	local Engine = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine")
	local JourneyMap = require(Engine:WaitForChild("JourneyMap"))
	local CardBacks = require(Engine:WaitForChild("CardBacks"))
	local CosmeticSets = require(Engine:WaitForChild("CosmeticSets"))
	local Achievements = require(Engine:WaitForChild("Achievements"))
	local lookups = { cardBack = CardBacks, set = CosmeticSets, title = Achievements }
	local burst = require(script.Parent.ParticleBurst)({ screenGui = deps.screenGui, tweenTo = deps.tweenTo }).burst

	pcall(function() require(script.Parent.VictoryScreen).setBestHand(deps.getBestHand) end) -- the Victory screen's Best Hand row
	local CREAM = Color3.fromRGB(250, 240, 220)
	local GOLD = Color3.fromRGB(255, 214, 130)
	local ClientSettings = require(script.Parent.ClientSettings)
	local TweenService = game:GetService("TweenService")

	local Rules = require(Engine:WaitForChild("OverlayQueueRules"))
	local HudKit = require(Engine:WaitForChild("HudKit"))
	local ResultButtonHit = require(Engine:WaitForChild("ResultButtonHit"))
	local HudTheme = require(script.Parent.HudTheme)
	local Style = require(Engine:WaitForChild("TavernStyle"))
	local SERIF = Enum.Font[Style.FONTS.title] or Enum.Font.GothamBold -- the same painted serif as TavernKit.title
	local INK = Color3.fromRGB(52, 34, 18)
	local INK_TITLE = Color3.fromRGB(104, 54, 12)
	local TILE = Color3.fromRGB(236, 220, 184) -- parchment stat tiles

	-- The plate art is a wide wooden frame stretched to this box; its parchment is the middle 72 x 54 percent
	-- (measured from the art: x 0.139 to 0.863, y 0.242 to 0.780). Everything must sit inside it.
	local PLATE_W, PLATE_H = 560, 520 -- the widest the plate ever gets (the painted plate is sized from its content below)
	-- Content rows (title, body, stat tiles, reward line, button) plus the gaps: the plate is sized from this, never the reverse.
	local CONTENT_W = 480
	local ROW_TITLE, ROW_BODY, ROW_TILES, ROW_REWARD, ROW_BUTTON, GAP = 36, 60, 62, 40, 46, 10
	local CONTENT_H = ROW_TITLE + ROW_BODY + ROW_TILES + ROW_REWARD + ROW_BUTTON + 4 * GAP
	local DARK_MARGIN = 28
	local PARCH = { x = 0.139, w = 0.724, y = 0.242, h = 0.538, inset = 12 }

	local backdrop = Instance.new("Frame")
	backdrop.Name = "NightVictoryBackdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	backdrop.BackgroundTransparency = 0.2 -- dims the shop behind it enough that nothing competes
	backdrop.Visible = false
	backdrop.ZIndex = 60
	backdrop.Parent = deps.screenGui

	-- Same painted plate as Round Complete (the equipped set's kit plate), dark code-drawn plate when the set has none.
	local panel = Instance.new("ImageLabel")
	panel.Name = "Plate"
	panel.ScaleType = Enum.ScaleType.Fit -- the painted plate is always sized at the art's own aspect (PLATE_W : PLATE_H), so Fit never letterboxes or squashes it
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Size = UDim2.fromOffset(PLATE_W, PLATE_H)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.BackgroundColor3 = Color3.fromRGB(46, 34, 24)
	panel.ZIndex = 61
	panel.Parent = backdrop
	local panelLimit = Instance.new("UISizeConstraint")
	panelLimit.MaxSize = Vector2.new(PLATE_W, PLATE_H)
	panelLimit.Parent = panel
	local panelCorner = Instance.new("UICorner")
	panelCorner.CornerRadius = UDim.new(0, 14)
	panelCorner.Parent = panel
	local panelStroke = Instance.new("UIStroke")
	panelStroke.Color = Color3.fromRGB(200, 160, 84)
	panelStroke.Thickness = 3
	panelStroke.Parent = panel
	deps.addSoftShadow(panel, 18)

		local content = Instance.new("Frame") -- text area inside the plate's painted border
	content.Name = "Content"
	content.BackgroundTransparency = 1
	content.Size = UDim2.new(PARCH.w, -2 * PARCH.inset, PARCH.h, -2 * PARCH.inset)
	content.Position = UDim2.new(PARCH.x, PARCH.inset, PARCH.y, PARCH.inset)
	content.ZIndex = 62
	content.Parent = panel

	-- Even vertical rhythm: one centred list inside the painted border.
	local flow = Instance.new("UIListLayout")
	flow.SortOrder = Enum.SortOrder.LayoutOrder
	flow.FillDirection = Enum.FillDirection.Vertical
	flow.HorizontalAlignment = Enum.HorizontalAlignment.Center
	flow.VerticalAlignment = Enum.VerticalAlignment.Center
	flow.Padding = UDim.new(0, GAP)
	flow.Parent = content
	local order = 0
	local function nextOrder() order = order + 1 return order end

	local inkLabels = {} -- { label, paintedColor, darkColor }
	local function label(props, paintedColor)
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Font = Enum.Font.Gotham
		l.TextColor3 = CREAM
		l.TextTransparency = 0
		l.TextStrokeTransparency = 1
		l.TextWrapped = true
		l.ZIndex = 62
		l.LayoutOrder = nextOrder()
		for k, v in pairs(props) do
			l[k] = v
		end
		l.Parent = content
		inkLabels[#inkLabels + 1] = { l, paintedColor, l.TextColor3 }
		return l
	end

	label({ Size = UDim2.new(1, 0, 0, ROW_TITLE), Font = SERIF, TextStrokeTransparency = 0.5, TextStrokeColor3 = Color3.fromRGB(52, 34, 18),
		TextSize = 24, TextColor3 = GOLD, Text = "Tavern Champion" }, INK_TITLE)
	label({ Size = UDim2.new(1, 0, 0, ROW_BODY), TextSize = 16,
		Text = "You cleared Night 8: " .. JourneyMap.Nights[JourneyMap.NightCap].name .. ". The doors stay open for Endless Nights." }, INK)

	-- Run stats: three parchment tiles. An unfilled value shows a dash, never a placeholder word.
	local tileRow = Instance.new("Frame")
	tileRow.Name = "Tiles"
	tileRow.BackgroundTransparency = 1
	tileRow.Size = UDim2.new(1, 0, 0, ROW_TILES)
	tileRow.LayoutOrder = nextOrder()
	tileRow.ZIndex = 62
	tileRow.Parent = content
	local function statTile(x, caption)
		local tile = Instance.new("Frame")
		tile.Size = UDim2.new(0.333, -8, 0, 62)
		tile.Position = UDim2.new(x, 4, 0, 0)
		tile.BackgroundColor3 = TILE
		tile.ZIndex = 62
		tile.Parent = tileRow
		deps.roundCorner(tile, 8)
		local value = Instance.new("TextLabel")
		value.Size = UDim2.new(1, -8, 0, 38)
		value.Position = UDim2.fromOffset(4, 4)
		value.BackgroundTransparency = 1
		value.Font = SERIF
		value.TextSize = 18
		value.TextColor3 = INK_TITLE
		value.TextTransparency = 0
		value.TextStrokeTransparency = 1
		value.TextWrapped = true
		value.Text = "-"
		value.ZIndex = 63
		value.Parent = tile
		local cap = Instance.new("TextLabel")
		cap.Size = UDim2.new(1, -8, 0, 16)
		cap.Position = UDim2.fromOffset(4, 42)
		cap.BackgroundTransparency = 1
		cap.Font = Enum.Font.Gotham
		cap.TextSize = 14
		cap.TextColor3 = INK
		cap.TextTransparency = 0
		cap.TextStrokeTransparency = 1
		cap.Text = caption
		cap.ZIndex = 63
		cap.Parent = tile
		return value
	end
	local handsValue = statTile(0, "Hands played")
	local bestValue = statTile(0.333, "Best hand")
	local patronsValue = statTile(0.666, "Patrons used")

	local rewardLabel = label({ Size = UDim2.new(1, 0, 0, ROW_REWARD), TextSize = 16,
		TextColor3 = GOLD, Text = "" }, INK_TITLE)

	local button = Instance.new("TextButton")
	button.Size = UDim2.fromOffset(240, ROW_BUTTON)
	button.LayoutOrder = nextOrder()
	button.Font = Enum.Font.GothamBold
	button.TextSize = 16
	button.TextColor3 = CREAM
	button.BackgroundColor3 = Color3.fromRGB(90, 60, 30)
	button.Text = "Enter Endless Nights"
	button.ZIndex = 62
	button.Parent = content
	deps.roundCorner(button, 12) -- no gold chrome or ornate rim: it drew a dark line under the label
	button.AutoButtonColor = true

	-- Kit plate art + dark ink on its parchment, or the dark code-drawn plate with light text.
	local function dress()
		local setId = HudTheme.setId()
		local kitId = setId and HudKit.piece(setId, Rules.KIT_PLATE) or nil
		-- Size the plate from its content. The painted plate's parchment is PARCH of the art, so the art is grown until the
		-- parchment holds every row; a window too small for that gets the dark code-drawn plate, which is tighter.
		local win = deps.screenGui.AbsoluteSize
		local paintW = math.max((CONTENT_W + 2 * PARCH.inset) / PARCH.w, (CONTENT_H + 2 * PARCH.inset) / PARCH.h * PLATE_W / PLATE_H)
		local paintH = paintW * PLATE_H / PLATE_W -- the art's own aspect: the parchment fractions only hold when the frame is not letterboxed
		local fitsPainted = win.Y <= 0 or (paintH <= win.Y - 16 and paintW <= win.X - 16)
		local painted = kitId ~= nil and fitsPainted
		local darkW = CONTENT_W + 2 * DARK_MARGIN
		if win.X > 0 then darkW = math.min(darkW, win.X - 16) end
		local w, h = darkW, CONTENT_H + 2 * DARK_MARGIN
		if painted then w, h = paintW, paintH end
		panel.Size = UDim2.fromOffset(math.floor(w), math.floor(h))
		panelLimit.MaxSize = Vector2.new(math.floor(w), math.floor(h))
		panel.Image = painted and kitId or ""
		panel.BackgroundTransparency = painted and 1 or 0
		panelStroke.Enabled = not painted
		panelCorner.CornerRadius = UDim.new(0, painted and 0 or 14)
		local shadow = backdrop:FindFirstChild("Shadow") -- the soft shadow frame is a dark box behind the painted plate
		if shadow and shadow:IsA("GuiObject") then shadow.Visible = not painted end
		if painted then
			content.Position = UDim2.new(PARCH.x, PARCH.inset, PARCH.y, PARCH.inset)
			content.Size = UDim2.new(PARCH.w, -2 * PARCH.inset, PARCH.h, -2 * PARCH.inset)
		else
			content.Position = UDim2.fromOffset(DARK_MARGIN, DARK_MARGIN)
			content.Size = UDim2.new(1, -2 * DARK_MARGIN, 1, -2 * DARK_MARGIN)
		end
		for _, e in ipairs(inkLabels) do
			e[1].TextColor3 = painted and e[2] or e[3]
		end
	end

	dress() -- paint now, and again whenever the plate becomes visible or the set changes
	backdrop:GetPropertyChangedSignal("Visible"):Connect(function()
		if backdrop.Visible then dress() end
	end)
	HudTheme.onSkin(dress)
	deps.screenGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		if backdrop.Visible then dress() end
	end)

	local function proceed()
		if not backdrop.Visible then return end -- one press only: the click, Activated and the pointer check can all arrive
		deps.playClickSfx()
		backdrop.Visible = false
	end
	button.MouseButton1Click:Connect(proceed)
	button.Activated:Connect(proceed)
	-- Safety net: if anything invisible ever eats the click before the button gets it, a press that lands inside the
	-- button's own rect still continues (Engine/ResultButtonHit, tested). Only while this plate is up.
	game:GetService("UserInputService").InputBegan:Connect(function(input)
		if not backdrop.Visible then return end
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
		local inset = game:GetService("GuiService"):GetGuiInset()
		local x, y = ResultButtonHit.pointer(input.Position.X, input.Position.Y, inset.Y, deps.screenGui.IgnoreGuiInset)
		local p, s = button.AbsolutePosition, button.AbsoluteSize
		if ResultButtonHit.inside({ x = p.X, y = p.Y, w = s.X, h = s.Y }, x, y) then proceed() end
	end)
	-- Result screen: its one button is its exit, and Escape presses it (Client/PopupDismiss, policy "button").
	require(script.Parent.PopupDismiss).attach(backdrop, { policy = "button", press = proceed, button = true })

	local function show(state)
		local newlyCleared = false
		for _, n in ipairs(state.journeyNotice or {}) do
			if n == JourneyMap.NightCap then
				newlyCleared = true
			end
		end
		if newlyCleared then
			rewardLabel.Text = ResultButtonHit.rewardLine(JourneyMap.rewardLabel(JourneyMap.Nights[JourneyMap.NightCap].reward, lookups))
		else
			rewardLabel.Text = "Night 8 already cleared before. Welcome back, Keeper."
		end
		dress()
		local best = deps.getBestHand and deps.getBestHand() or nil
		handsValue.Text = tostring(math.floor(state.handsPlayedTotal or 0))
		bestValue.Text = best and string.format("%s (%d)", best.name, math.floor(best.score)) or "-"
		patronsValue.Text = tostring(#(state.ownedPatrons or {}))
		-- an account panel (Store with its tab strip) must not stay up behind the plate
		local store = backdrop.Parent and backdrop.Parent:FindFirstChild("StoreBackdrop")
		if store and store:IsA("GuiObject") then
			store.Visible = false
		end
		pcall(function() require(script.Parent.ResultGuard).hold(backdrop.Parent) end) -- keeps the Store hidden while this plate is up
		pcall(function() require(script.Parent.Cue).play("night_clear") end)
		button.Active = true
		pcall(function() button.Interactable = true end) -- nothing may leave the one exit switched off
		backdrop.Visible = true
		if not ClientSettings.get("reduceShake") then
			-- Pop in (skipped when screen shake is reduced).
			local scale = panel:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
			scale.Scale = 0.85
			scale.Parent = panel
			TweenService:Create(scale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		end
		if ClientSettings.get("reduceShake") then return end -- calm mode: no gold burst
		task.delay(0.1, function()
			local size = deps.screenGui.AbsoluteSize
			burst(UDim2.fromOffset(size.X / 2, size.Y * 0.4), GOLD, 40)
			burst(UDim2.fromOffset(size.X / 2 - 120, size.Y * 0.45), CREAM, 20)
			burst(UDim2.fromOffset(size.X / 2 + 120, size.Y * 0.45), CREAM, 20)
		end)
	end

	local lastWon = nil
	deps.StateUpdatedRemote.OnClientEvent:Connect(function()
		task.defer(function()
			local state = deps.getLatestState()
			if not state then
				return
			end
			local won = state.wonRun == true
			if lastWon == false and won then
				-- Let the round-win scoring finish before the banner.
				task.delay(1.5, function()
					show(state)
				end)
			end
			lastWon = won
		end)
	end)

	return {}
end
