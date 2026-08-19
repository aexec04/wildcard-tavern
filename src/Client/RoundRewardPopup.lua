--[[
	Client/RoundRewardPopup.lua
	A visual callout ("+$X Tips") for how much you just earned when a round
	is won, plus a cash sound distinct from the shop Buy sound. render()
	calls showRoundReward(amount) once, right on the transition into the
	shop phase.

	Extracted out of init.client.lua as part of splitting the client script
	into smaller, per-feature files. Parented to screenGui directly (no
	backdrop), same as UnlockPopup.lua -- see that module's comment for why
	addSoftShadow is deliberately skipped here too.

	deps fields:
		screenGui   -- ScreenGui, this popup's parent (no backdrop)
		polishPanel  -- function(instance, radius)
		tweenTo      -- function(instance, props, duration, easingStyle?, easingDirection?)
		playSfx      -- function(soundId, volume?, maxLength?)
		SOUND_IDS    -- table, for SOUND_IDS.roundReward

	Returns:
		{
			showRoundReward = function(amount),
		}
]]

return function(deps)
	local screenGui = deps.screenGui
	local polishPanel = deps.polishPanel
	local tweenTo = deps.tweenTo
	local playSfx = deps.playSfx
	local SOUND_IDS = deps.SOUND_IDS

	local roundRewardPopup = Instance.new("Frame")
	roundRewardPopup.Name = "RoundRewardPopup"
	roundRewardPopup.Size = UDim2.new(0, 260, 0, 100)
	roundRewardPopup.AnchorPoint = Vector2.new(0.5, 0.5)
	roundRewardPopup.Position = UDim2.fromScale(0.5, 0.42)
	roundRewardPopup.BackgroundColor3 = Color3.fromRGB(40, 55, 35)
	roundRewardPopup.Visible = false
	roundRewardPopup.ZIndex = 28
	roundRewardPopup.Parent = screenGui
	polishPanel(roundRewardPopup, 18)

	local roundRewardTitle = Instance.new("TextLabel")
	roundRewardTitle.Size = UDim2.new(1, -20, 0, 30)
	roundRewardTitle.Position = UDim2.new(0, 10, 0, 12)
	roundRewardTitle.BackgroundTransparency = 1
	roundRewardTitle.Font = Enum.Font.GothamBold
	roundRewardTitle.TextSize = 20
	roundRewardTitle.TextColor3 = Color3.fromRGB(255, 230, 180)
	roundRewardTitle.Text = "Round Complete!"
	roundRewardTitle.ZIndex = 28
	roundRewardTitle.Parent = roundRewardPopup

	local roundRewardAmount = Instance.new("TextLabel")
	roundRewardAmount.Size = UDim2.new(1, -20, 0, 40)
	roundRewardAmount.Position = UDim2.new(0, 10, 0, 46)
	roundRewardAmount.BackgroundTransparency = 1
	roundRewardAmount.Font = Enum.Font.GothamBold
	roundRewardAmount.TextSize = 28
	roundRewardAmount.TextColor3 = Color3.fromRGB(150, 235, 140)
	roundRewardAmount.Text = ""
	roundRewardAmount.ZIndex = 28
	roundRewardAmount.Parent = roundRewardPopup

	local roundRewardScale = Instance.new("UIScale")
	roundRewardScale.Scale = 1
	roundRewardScale.Parent = roundRewardPopup

	local function showRoundReward(amount)
		roundRewardAmount.Text = string.format("+$%d Tips", amount)
		roundRewardPopup.Visible = true
		roundRewardScale.Scale = 0.6
		playSfx(SOUND_IDS.roundReward, 1)
		tweenTo(roundRewardScale, { Scale = 1.15 }, 0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		task.delay(0.2, function()
			tweenTo(roundRewardScale, { Scale = 1 }, 0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		end)
		task.delay(2.2, function()
			roundRewardPopup.Visible = false
		end)
	end

	return {
		showRoundReward = showRoundReward,
	}
end
