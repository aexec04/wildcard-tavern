--[[
	Client/NightVictory.lua
	The short "Night 8 cleared" moment: when a run's wonRun flag flips to
	true, a banner pops up with a gold burst, the Night 8 name, and the
	reward earned (if it's new). One button continues into Endless Mode.
	No new gameplay: the run was already won and keeps going exactly as before.

	Listens to StateUpdatedRemote itself (task.defer so latestState is
	current). Never fires for the first state it sees, so joining or
	restarting never shows it by accident.

	deps: screenGui, polishPanel, polishButton, roundCorner, addSoftShadow,
	playClickSfx, tweenTo, getLatestState, StateUpdatedRemote

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
	panel.Size = UDim2.fromOffset(420, 250)
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

	label({ Size = UDim2.new(1, 0, 0, 40), Position = UDim2.fromOffset(0, 18), Font = Enum.Font.GothamBold,
		TextSize = 28, TextColor3 = GOLD, Text = "👑 The Tavern Is Yours! 👑" })
	label({ Size = UDim2.new(1, -40, 0, 40), Position = UDim2.fromOffset(20, 68), TextSize = 15,
		Text = "You cleared Night 8: " .. JourneyMap.Nights[JourneyMap.NightCap].name .. "." })
	local rewardLabel = label({ Size = UDim2.new(1, -40, 0, 40), Position = UDim2.fromOffset(20, 110), TextSize = 14,
		TextColor3 = GOLD, Text = "" })
	label({ Size = UDim2.new(1, -40, 0, 20), Position = UDim2.fromOffset(20, 152), TextSize = 12,
		TextColor3 = Color3.fromRGB(215, 200, 178), Text = "The doors stay open. Endless Nights await." })

	local button = Instance.new("TextButton")
	button.Size = UDim2.fromOffset(220, 40)
	button.AnchorPoint = Vector2.new(0.5, 1)
	button.Position = UDim2.new(0.5, 0, 1, -18)
	button.Font = Enum.Font.GothamBold
	button.TextSize = 16
	button.TextColor3 = CREAM
	button.BackgroundColor3 = Color3.fromRGB(90, 60, 30)
	button.Text = "Continue to Endless ♾"
	button.ZIndex = 62
	button.Parent = panel
	deps.polishButton(button, 12)

	button.MouseButton1Click:Connect(function()
		deps.playClickSfx()
		backdrop.Visible = false
	end)

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
		backdrop.Visible = true
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
