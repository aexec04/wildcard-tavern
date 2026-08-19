--[[
	Client/UnlockPopup.lua
	FEATURE 12: a quick celebratory card shown whenever a NEW Patron or Theme
	appears in the state compared to the previous render() -- render() does
	the "is this actually new" diff check and calls showUnlockPopup() when
	it finds one.

	Extracted out of init.client.lua as part of splitting the client script
	into smaller, per-feature files.

	NOTE: deliberately NOT using addSoftShadow() here, unlike most other
	overlays. addSoftShadow() parents its shadow Frame into panel.Parent and
	sizes it to 100% of that parent -- every backdrop-based overlay's panel
	lives inside a full-screen "xBackdrop" Frame whose Visible=false cascades
	down to hide the shadow too. This popup is a small floating card parented
	directly to screenGui (no backdrop), so that shadow would default to
	Visible=true and sit as a permanent ~full-screen 55%-opaque black layer
	over everything -- this was root-caused as the cause of a "dark right
	away" regression once already. Skipping the shadow avoids it entirely;
	the rounded corners from polishPanel are enough polish.

	deps fields:
		screenGui   -- ScreenGui, this popup's parent (no backdrop)
		polishPanel  -- function(instance, radius)
		tweenTo      -- function(instance, props, duration, easingStyle?, easingDirection?)

	Returns:
		{
			showUnlockPopup = function(name, description),
		}
]]

return function(deps)
	local screenGui = deps.screenGui
	local polishPanel = deps.polishPanel
	local tweenTo = deps.tweenTo

	local unlockPopup = Instance.new("Frame")
	unlockPopup.Name = "UnlockPopup"
	unlockPopup.Size = UDim2.new(0, 280, 0, 140)
	unlockPopup.AnchorPoint = Vector2.new(0.5, 0.5)
	unlockPopup.Position = UDim2.fromScale(0.5, 0.5)
	unlockPopup.BackgroundColor3 = Color3.fromRGB(50, 40, 26)
	unlockPopup.Visible = false
	unlockPopup.ZIndex = 30
	unlockPopup.Parent = screenGui
	polishPanel(unlockPopup, 18)

	local unlockPopupHeader = Instance.new("TextLabel")
	unlockPopupHeader.Size = UDim2.new(1, 0, 0, 34)
	unlockPopupHeader.Position = UDim2.new(0, 0, 0, 12)
	unlockPopupHeader.BackgroundTransparency = 1
	unlockPopupHeader.Font = Enum.Font.GothamBold
	unlockPopupHeader.TextSize = 20
	unlockPopupHeader.TextColor3 = Color3.fromRGB(255, 214, 130)
	unlockPopupHeader.Text = "Unlocked!"
	unlockPopupHeader.ZIndex = 30
	unlockPopupHeader.Parent = unlockPopup

	local unlockPopupName = Instance.new("TextLabel")
	unlockPopupName.Size = UDim2.new(1, -30, 0, 26)
	unlockPopupName.Position = UDim2.new(0, 15, 0, 48)
	unlockPopupName.BackgroundTransparency = 1
	unlockPopupName.Font = Enum.Font.GothamBold
	unlockPopupName.TextSize = 17
	unlockPopupName.TextColor3 = Color3.fromRGB(250, 240, 220)
	unlockPopupName.Text = ""
	unlockPopupName.ZIndex = 30
	unlockPopupName.Parent = unlockPopup

	local unlockPopupDescription = Instance.new("TextLabel")
	unlockPopupDescription.Size = UDim2.new(1, -30, 0, 40)
	unlockPopupDescription.Position = UDim2.new(0, 15, 0, 76)
	unlockPopupDescription.BackgroundTransparency = 1
	unlockPopupDescription.Font = Enum.Font.Gotham
	unlockPopupDescription.TextSize = 13
	unlockPopupDescription.TextWrapped = true
	unlockPopupDescription.TextColor3 = Color3.fromRGB(215, 200, 180)
	unlockPopupDescription.Text = ""
	unlockPopupDescription.ZIndex = 30
	unlockPopupDescription.Parent = unlockPopup

	local unlockPopupScale = Instance.new("UIScale")
	unlockPopupScale.Scale = 1
	unlockPopupScale.Parent = unlockPopup

	local unlockPopupDismissCatcher = Instance.new("TextButton")
	unlockPopupDismissCatcher.Size = UDim2.fromScale(1, 1)
	unlockPopupDismissCatcher.BackgroundTransparency = 1
	unlockPopupDismissCatcher.Text = ""
	unlockPopupDismissCatcher.ZIndex = 30
	unlockPopupDismissCatcher.Parent = unlockPopup

	local unlockPopupToken = 0

	local function showUnlockPopup(name, description)
		unlockPopupToken = unlockPopupToken + 1
		local myToken = unlockPopupToken

		unlockPopupName.Text = name
		unlockPopupDescription.Text = description or ""
		unlockPopup.Visible = true
		unlockPopupScale.Scale = 0.7
		tweenTo(unlockPopupScale, { Scale = 1 }, 0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

		local function dismiss()
			if unlockPopupToken ~= myToken then
				return
			end
			unlockPopup.Visible = false
		end

		unlockPopupDismissCatcher.MouseButton1Click:Connect(dismiss)
		task.delay(2.4, dismiss)
	end

	return {
		showUnlockPopup = showUnlockPopup,
	}
end
