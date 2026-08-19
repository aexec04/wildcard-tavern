--[[
	Client/ScorePopup.lua
	LAYOUT FEATURE 7: Balatro's signature score-pop -- the "Hand Name / chips
	x mult" callout shown when Play Hand is clicked. Parented to root (not
	handFrame -- rebuildHand() destroys every Frame child of handFrame on
	every render(), which would destroy this the instant a hand is played)
	and centered on the full screen rather than the narrower play area, to
	avoid hand-crafting sidebar/deck-widget-aware centering math for an
	element that's only ever on screen for about a second.

	Extracted out of init.client.lua as part of splitting the client script
	into smaller, per-feature files. showScorePopup is called from
	playButton's click handler elsewhere in init.client.lua, so it comes
	back out of the require() call.

	deps fields:
		root    -- Frame, the popup's parent
		tweenTo -- function(instance, props, duration, easingStyle?, easingDirection?)

	Returns:
		{
			showScorePopup = function(preview),
			-- preview: { name, chips, mult, score } from computeHandPreview().
		}
]]

return function(deps)
	local root = deps.root
	local tweenTo = deps.tweenTo

	local scorePopup = Instance.new("Frame")
	scorePopup.Name = "ScorePopup"
	scorePopup.Size = UDim2.new(0, 240, 0, 90)
	scorePopup.AnchorPoint = Vector2.new(0.5, 1)
	scorePopup.Position = UDim2.new(0.5, 0, 1, -240)
	scorePopup.BackgroundTransparency = 1
	scorePopup.Visible = false
	scorePopup.ZIndex = 25
	scorePopup.Parent = root

	local scorePopupHandName = Instance.new("TextLabel")
	scorePopupHandName.Size = UDim2.new(1, 0, 0, 24)
	scorePopupHandName.BackgroundTransparency = 1
	scorePopupHandName.Font = Enum.Font.GothamBold
	scorePopupHandName.TextSize = 18
	scorePopupHandName.TextColor3 = Color3.fromRGB(255, 230, 180)
	scorePopupHandName.TextStrokeTransparency = 0.5
	scorePopupHandName.Text = ""
	scorePopupHandName.ZIndex = 25
	scorePopupHandName.Parent = scorePopup

	local scorePopupMath = Instance.new("TextLabel")
	scorePopupMath.Size = UDim2.new(1, 0, 0, 50)
	scorePopupMath.Position = UDim2.new(0, 0, 0, 26)
	scorePopupMath.BackgroundTransparency = 1
	scorePopupMath.Font = Enum.Font.GothamBold
	scorePopupMath.TextSize = 36
	scorePopupMath.TextColor3 = Color3.fromRGB(255, 255, 255)
	scorePopupMath.TextStrokeTransparency = 0.4
	scorePopupMath.Text = ""
	scorePopupMath.ZIndex = 25
	scorePopupMath.Parent = scorePopup

	local scorePopupScale = Instance.new("UIScale")
	scorePopupScale.Scale = 1
	scorePopupScale.Parent = scorePopup

	local scorePopupToken = 0

	-- preview: { name, chips, mult, score } from computeHandPreview(). Values
	-- are computed at the moment Play Hand is clicked, using the exact same
	-- scoring call RunState.playHand makes server-side, so this can never show
	-- a number that doesn't match what you actually get paid.
	local function showScorePopup(preview)
		scorePopupToken = scorePopupToken + 1
		local myToken = scorePopupToken

		scorePopupHandName.Text = preview.name
		scorePopupMath.Text = string.format("%d x %d", preview.chips, preview.mult)
		scorePopup.Visible = true
		scorePopupScale.Scale = 0.6
		tweenTo(scorePopupScale, { Scale = 1.15 }, 0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

		task.delay(0.18, function()
			if scorePopupToken == myToken then
				tweenTo(scorePopupScale, { Scale = 1 }, 0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			end
		end)

		task.delay(1.1, function()
			if scorePopupToken == myToken then
				scorePopup.Visible = false
			end
		end)
	end

	return {
		showScorePopup = showScorePopup,
	}
end
