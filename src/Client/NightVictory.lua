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

	local CREAM = Color3.fromRGB(250, 240, 220)
	local GOLD = Color3.fromRGB(255, 214, 130)
	local PURPLE = Color3.fromRGB(JourneyMap.EndlessTheme.accent[1], JourneyMap.EndlessTheme.accent[2], JourneyMap.EndlessTheme.accent[3])
	local ClientSettings = require(script.Parent.ClientSettings)
	local TweenService = game:GetService("TweenService")

	local backdrop = Instance.new("Frame")
	backdrop.Name = "NightVictoryBackdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	backdrop.BackgroundTransparency = 0.35
	backdrop.Visible = false
	backdrop.ZIndex = 60
	backdrop.Parent = deps.screenGui

	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Size = UDim2.fromOffset(460, 340)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.BackgroundColor3 = Color3.fromRGB(40, 30, 22)
	panel.ZIndex = 61
	panel.Parent = backdrop
	deps.polishPanel(panel, 16, "parchment")
	deps.addSoftShadow(panel, 18)

	local function label(props)
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Font = Enum.Font.Gotham
		l.TextColor3 = CREAM
		l.TextTransparency = 0
		l.TextStrokeTransparency = 1
		l.TextWrapped = true
		l.ZIndex = 62
		for k, v in pairs(props) do
			l[k] = v
		end
		l.Parent = panel
		return l
	end

	label({ Size = UDim2.new(1, 0, 0, 40), Position = UDim2.fromOffset(0, 16), Font = Enum.Font.GothamBold,
		TextSize = 28, TextColor3 = GOLD, Text = "👑 Tavern Champion! 👑" })
	label({ Size = UDim2.new(1, -40, 0, 20), Position = UDim2.fromOffset(20, 60), TextSize = 14,
		Text = "You cleared Night 8: " .. JourneyMap.Nights[JourneyMap.NightCap].name .. ". The tavern is yours!" })

	-- Run stats: three tiles.
	local function statTile(x, caption)
		local tile = Instance.new("Frame")
		tile.Size = UDim2.new(0.333, -10, 0, 74)
		tile.Position = UDim2.new(x, 5, 0, 94)
		tile.BackgroundColor3 = Color3.fromRGB(28, 20, 14)
		tile.ZIndex = 62
		tile.Parent = panel
		deps.roundCorner(tile, 8)
		local value = Instance.new("TextLabel")
		value.Size = UDim2.new(1, -8, 0, 44)
		value.Position = UDim2.fromOffset(4, 6)
		value.BackgroundTransparency = 1
		value.Font = Enum.Font.GothamBold
		value.TextSize = 18
		value.TextColor3 = GOLD
		value.TextTransparency = 0
		value.TextStrokeTransparency = 1
		value.TextWrapped = true
		value.ZIndex = 63
		value.Parent = tile
		local cap = Instance.new("TextLabel")
		cap.Size = UDim2.new(1, -8, 0, 18)
		cap.Position = UDim2.fromOffset(4, 52)
		cap.BackgroundTransparency = 1
		cap.Font = Enum.Font.Gotham
		cap.TextSize = 14
		cap.TextColor3 = Color3.fromRGB(215, 200, 178)
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

	local rewardLabel = label({ Size = UDim2.new(1, -40, 0, 36), Position = UDim2.fromOffset(20, 180), TextSize = 14,
		TextColor3 = GOLD, Text = "" })
	label({ Size = UDim2.new(1, -40, 0, 36), Position = UDim2.fromOffset(20, 222), TextSize = 14,
		TextColor3 = PURPLE, Text = "The doors stay open. Endless Nights await, with new rewards at Nights 10, 15 and 20." })

	local button = Instance.new("TextButton")
	button.Size = UDim2.fromOffset(240, 40)
	button.AnchorPoint = Vector2.new(0.5, 1)
	button.Position = UDim2.new(0.5, 0, 1, -18)
	button.Font = Enum.Font.GothamBold
	button.TextSize = 16
	button.TextColor3 = CREAM
	button.BackgroundColor3 = Color3.fromRGB(90, 60, 30)
	button.Text = "Enter Endless Nights ♾"
	button.ZIndex = 62
	button.Parent = panel
	deps.polishButton(button, 12)

	local function proceed()
		deps.playClickSfx()
		backdrop.Visible = false
	end
	button.MouseButton1Click:Connect(proceed)
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
			rewardLabel.Text = "🎁 " .. JourneyMap.rewardLabel(JourneyMap.Nights[JourneyMap.NightCap].reward, lookups)
		else
			rewardLabel.Text = "Night 8 already cleared before. Welcome back, Keeper."
		end
		local best = deps.getBestHand and deps.getBestHand() or nil
		handsValue.Text = tostring(math.floor(state.handsPlayedTotal or 0))
		bestValue.Text = best and string.format("%s (%d)", best.name, math.floor(best.score)) or "-"
		patronsValue.Text = tostring(#(state.ownedPatrons or {}))
		backdrop.Visible = true
		if not ClientSettings.get("reduceShake") then
			-- Pop in (skipped when screen shake is reduced).
			local scale = panel:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
			scale.Scale = 0.85
			scale.Parent = panel
			TweenService:Create(scale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		end
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
