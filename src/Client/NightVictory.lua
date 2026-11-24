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

	local ResultButtonHit = require(Engine:WaitForChild("ResultButtonHit"))
	local Style = require(Engine:WaitForChild("TavernStyle"))
	local ContentArt = require(Engine:WaitForChild("ContentArt"))
	local ImageSpace = require(Engine:WaitForChild("ImageSpace"))
	local RunOverLayout = require(Engine:WaitForChild("RunOverLayout"))
	local SERIF = Enum.Font[Style.FONTS.title] or Enum.Font.GothamBold -- the same painted serif as TavernKit.title
	local INK = Color3.fromRGB(52, 34, 18)
	local INK_TITLE = Color3.fromRGB(104, 54, 12)
	local TILE = Color3.fromRGB(236, 220, 184) -- parchment stat tiles
	local WOOD = Color3.fromRGB(46, 32, 20) -- the dark facts plate, the same wood as the Run Over screen

	-- Built like the Run Over win screen: the painted scroll (run_over_scroll_b) is only the backdrop, and every word sits on a dark
	-- wood facts plate drawn on top of it (higher ZIndex, never under the art), so no painted band can hide text. The plate is sized
	-- from its rows and centred in the scroll's measured safe rect; a window too small for that gets the plate alone.
	local CONTENT_W = 480
	local ROW_TITLE, ROW_BODY, ROW_TILES, ROW_REWARD, ROW_BUTTON, GAP = 36, 60, 62, 40, 46, 10
	local CONTENT_H = ROW_TITLE + ROW_BODY + ROW_TILES + ROW_REWARD + ROW_BUTTON + 4 * GAP
	local PAD = 14
	local PLATE_W, PLATE_H = CONTENT_W + 2 * PAD, CONTENT_H + 2 * PAD
	local SCROLL = RunOverLayout.SCROLLS.b
	local MIN_SCROLL_SCALE = math.max((PLATE_W + 16) / SCROLL.safe.w, (PLATE_H + 16) / SCROLL.safe.h)
	local Z = 61

	local backdrop = Instance.new("Frame")
	backdrop.Name = "NightVictoryBackdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	backdrop.BackgroundTransparency = 0.2 -- dims the shop behind it enough that nothing competes
	backdrop.Visible = false
	backdrop.ZIndex = 60
	backdrop.Parent = deps.screenGui

	local panel = Instance.new("Frame") -- holds the scroll picture and the facts plate
	panel.Name = "Plate"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Size = UDim2.fromOffset(PLATE_W, PLATE_H)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.BackgroundTransparency = 1
	panel.ZIndex = Z
	panel.Parent = backdrop

	local picture = Instance.new("ImageLabel") -- the painted scroll, cropped to the art's own box and shown at its own aspect (Fit never squashes it)
	picture.Name = "ScrollPicture"
	picture.BackgroundTransparency = 1
	picture.BorderSizePixel = 0
	picture.Active = false
	picture.ScaleType = Enum.ScaleType.Fit
	picture.Size = UDim2.fromScale(1, 1)
	picture.ZIndex = Z
	picture.Visible = false
	picture.Parent = panel

	local plate = Instance.new("Frame") -- solid dark wood: all text sits on it, above the picture
	plate.Name = "FactsPlate"
	plate.AnchorPoint = Vector2.new(0.5, 0.5)
	plate.Position = UDim2.fromScale(0.5, 0.5)
	plate.Size = UDim2.fromOffset(PLATE_W, PLATE_H)
	plate.BackgroundColor3 = WOOD
	plate.BackgroundTransparency = 0.04
	plate.ZIndex = Z + 2
	plate.Parent = panel
	deps.roundCorner(plate, 14)
	local panelStroke = Instance.new("UIStroke")
	panelStroke.Color = Color3.fromRGB(200, 160, 84)
	panelStroke.Thickness = 3
	panelStroke.Parent = plate
	deps.addSoftShadow(panel, 18)

	local content = Instance.new("Frame") -- the rows, inset from the plate edge
	content.Name = "Content"
	content.BackgroundTransparency = 1
	content.Size = UDim2.new(1, -2 * PAD, 1, -2 * PAD)
	content.Position = UDim2.fromOffset(PAD, PAD)
	content.ZIndex = Z + 3
	content.Parent = plate

	local flow = Instance.new("UIListLayout")
	flow.SortOrder = Enum.SortOrder.LayoutOrder
	flow.FillDirection = Enum.FillDirection.Vertical
	flow.HorizontalAlignment = Enum.HorizontalAlignment.Center
	flow.VerticalAlignment = Enum.VerticalAlignment.Center
	flow.Padding = UDim.new(0, GAP)
	flow.Parent = content
	local order = 0
	local function nextOrder() order = order + 1 return order end

	local function label(props)
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Font = Enum.Font.Gotham
		l.TextColor3 = CREAM
		l.TextTransparency = 0
		l.TextStrokeTransparency = 1
		l.TextWrapped = true
		l.ZIndex = Z + 4
		l.LayoutOrder = nextOrder()
		for k, v in pairs(props) do
			l[k] = v
		end
		l.Parent = content
		return l
	end

	label({ Size = UDim2.new(1, 0, 0, ROW_TITLE), Font = SERIF, TextSize = 24, TextColor3 = GOLD, Text = "Tavern Champion" })
	label({ Size = UDim2.new(1, 0, 0, ROW_BODY), TextSize = 16,
		Text = "You cleared Night 8: " .. JourneyMap.Nights[JourneyMap.NightCap].name .. ". The doors stay open for Endless Nights." })

	-- Run stats: three parchment tiles. An unfilled value shows a dash, never a placeholder word.
	local tileRow = Instance.new("Frame")
	tileRow.Name = "Tiles"
	tileRow.BackgroundTransparency = 1
	tileRow.Size = UDim2.new(1, 0, 0, ROW_TILES)
	tileRow.LayoutOrder = nextOrder()
	tileRow.ZIndex = Z + 4
	tileRow.Parent = content
	local function statTile(x, caption)
		local tile = Instance.new("Frame")
		tile.Size = UDim2.new(0.333, -8, 0, 62)
		tile.Position = UDim2.new(x, 4, 0, 0)
		tile.BackgroundColor3 = TILE
		tile.ZIndex = Z + 4
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
		value.ZIndex = Z + 5
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
		cap.ZIndex = Z + 5
		cap.Parent = tile
		return value
	end
	local handsValue = statTile(0, "Hands played")
	local bestValue = statTile(0.333, "Best hand")
	local patronsValue = statTile(0.666, "Patrons used")

	local rewardLabel = label({ Size = UDim2.new(1, 0, 0, ROW_REWARD), TextSize = 16, TextColor3 = GOLD, Text = "" })

	local button = Instance.new("TextButton")
	button.Name = "Continue"
	button.Size = UDim2.fromOffset(240, ROW_BUTTON)
	button.LayoutOrder = nextOrder()
	button.Font = Enum.Font.GothamBold
	button.TextSize = 16
	button.TextColor3 = CREAM
	button.BackgroundColor3 = Color3.fromRGB(90, 60, 30)
	button.Text = "Enter Endless Nights"
	button.ZIndex = Z + 4
	button.Parent = content
	deps.roundCorner(button, 12) -- the sliced primary plate below replaces this when the kit has one
	button.AutoButtonColor = true
	pcall(function() require(script.Parent.TavernKit).paintedButton(button, "primary") end)

	-- Scroll behind the plate when the window can hold the scroll at a readable size, else the dark plate alone.
	local function dress()
		local win = deps.screenGui.AbsoluteSize
		local artId = ContentArt.getImageId("shop_scene", "run_over_scroll_b")
		local scale = 0
		if artId and win.X > 0 and win.Y > 0 then
			local maxScale = math.min((win.X - 24) / SCROLL.art.w, (win.Y - 16) / SCROLL.art.h, 1)
			scale = math.min(maxScale, RunOverLayout.SCROLL_WIDTH_FRACTION * win.X / SCROLL.art.w)
			if scale < MIN_SCROLL_SCALE then scale = maxScale end -- the preferred width is too small for the plate: use the largest that fits the window
		end
		local onScroll = artId ~= nil and scale >= MIN_SCROLL_SCALE
		picture.Visible = onScroll
		local shadow = panel:FindFirstChild("Shadow") -- the soft shadow frame is a dark box behind the panel; the scroll has its own edge
		if shadow and shadow:IsA("GuiObject") then shadow.Visible = not onScroll end
		if onScroll then
			local cw, ch = math.floor(SCROLL.art.w * scale + 0.5), math.floor(SCROLL.art.h * scale + 0.5)
			panel.Size = UDim2.fromOffset(cw, ch)
			local ix, iy, iw, ih = ImageSpace.rect(SCROLL.art.x, SCROLL.art.y, SCROLL.art.w, SCROLL.art.h, 1536, 1024)
			picture.Image = artId
			picture.ImageRectOffset = Vector2.new(ix, iy)
			picture.ImageRectSize = Vector2.new(iw, ih)
			-- centre the plate in the measured safe rect of the scroll (panel pixels), anchored top left
			local sx = (SCROLL.safe.x - SCROLL.art.x) * scale + ((SCROLL.safe.w * scale) - PLATE_W) / 2
			local sy = (SCROLL.safe.y - SCROLL.art.y) * scale + ((SCROLL.safe.h * scale) - PLATE_H) / 2
			plate.AnchorPoint = Vector2.new(0, 0)
			plate.Position = UDim2.fromOffset(math.floor(sx + 0.5), math.floor(sy + 0.5))
		else
			local w = PLATE_W
			if win.X > 0 then w = math.min(w, win.X - 16) end
			panel.Size = UDim2.fromOffset(w, PLATE_H)
			plate.AnchorPoint = Vector2.new(0.5, 0.5)
			plate.Position = UDim2.fromScale(0.5, 0.5)
		end
		plate.Size = UDim2.fromOffset(math.min(PLATE_W, panel.Size.X.Offset), PLATE_H)
	end

	dress() -- paint now, and again whenever the plate becomes visible or the window changes
	backdrop:GetPropertyChangedSignal("Visible"):Connect(function()
		if backdrop.Visible then dress() end
	end)
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
