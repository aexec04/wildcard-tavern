--[[
	Client/Tutorial.lua
	TUTORIAL (Phase 16): a short, multi-step first-time-player walkthrough
	-- a Day 6 item on the original roadmap that never got built once the
	scope grew past a week. Auto-shows exactly once, for a genuinely
	brand-new player (PlayerProfile.hasSeenTutorial still false server-
	side -- see that file's header), and stays manually reopenable any
	time afterward from the "Tutorial" menu button (Client/Menu.lua).

	Mirrors ConfirmDialog.lua/SeedRunDialog.lua's backdrop+panel+popIn/
	popOut shape, with a Back/Next pager and small step-dot indicator
	instead of a single action row.

	deps fields:
		screenGui           -- ScreenGui, the panel's ultimate parent (via backdrop)
		polishPanel          -- function(instance, radius)
		polishButton         -- function(instance, radius)
		addSoftShadow        -- function(instance, radius)
		playClickSfx         -- function(volume?)
		popIn                -- function(backdrop, content, opts?)
		popOut               -- function(backdrop, content, opts?, onHidden?)
		addButtonHoverScale  -- function(button, opts?)
		MarkTutorialSeenRemote -- RemoteEvent, fired () once dismissed/skipped

	Returns:
		{
			openTutorial = function(), -- always resets to step 1
		}

	`openTutorial` is called 2 ways: manually, from Menu.lua's "Tutorial"
	button (deps.openTutorial there), and automatically, exactly once,
	from init.client.lua's render() the first time it sees
	state.hasSeenTutorial == false for this player.
]]

local STEPS = {
	{
		title = "Welcome to Wildcard Tavern!",
		body = "Each Round, you're dealt a hand of cards. Play the best poker hand you can to hit that Round's target score before you run out of Hands.",
	},
	{
		title = "Hands & Discards",
		body = "You get a few Hands (chances to play 5 cards) and Discards (chances to swap cards out) per Round. A stronger poker hand -- Pair, Flush, Full House, and so on -- scores more Chips and Mult, which multiply together for your final score.",
	},
	{
		title = "Tips: your currency",
		body = "Clearing a Round pays out Tips. Spend them in the Shop between Rounds on Patrons, Recipes, Packs, and cosmetic Themes -- Tips never affect how strong a hand scores on their own, they just buy things that do.",
	},
	{
		title = "Patrons",
		body = "Patrons sit at your table and passively boost your scoring -- extra Mult for a certain suit, bonus Chips for a hand type, and more. You've got a limited number of table seats, so choose the ones that fit your hand.",
	},
	{
		title = "Nights & Boss Rounds",
		body = "Every few Rounds is a Boss Round -- a tougher target with a twist (fewer cards, a debuffed suit, and so on). Clear one to advance to the next Night, where targets climb higher. Good luck out there!",
	},
}

return function(deps)
	local screenGui = deps.screenGui
	local polishPanel = deps.polishPanel
	local polishButton = deps.polishButton
	local addSoftShadow = deps.addSoftShadow
	local playClickSfx = deps.playClickSfx
	local popIn = deps.popIn
	local popOut = deps.popOut
	local addButtonHoverScale = deps.addButtonHoverScale
	local MarkTutorialSeenRemote = deps.MarkTutorialSeenRemote

	local tutorialBackdrop = Instance.new("Frame")
	tutorialBackdrop.Name = "TutorialBackdrop"
	tutorialBackdrop.Size = UDim2.fromScale(1, 1)
	tutorialBackdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	tutorialBackdrop.BackgroundTransparency = 0.35
	tutorialBackdrop.Visible = false
	tutorialBackdrop.ZIndex = 40
	tutorialBackdrop.Parent = screenGui

	local tutorialPanel = Instance.new("Frame")
	tutorialPanel.Size = UDim2.new(0, 440, 0, 260)
	tutorialPanel.Position = UDim2.fromScale(0.5, 0.5)
	tutorialPanel.AnchorPoint = Vector2.new(0.5, 0.5)
	tutorialPanel.BackgroundColor3 = Color3.fromRGB(40, 30, 22)
	tutorialPanel.ZIndex = 40
	tutorialPanel.Parent = tutorialBackdrop
	polishPanel(tutorialPanel, 16)
	addSoftShadow(tutorialPanel, 18)

	local tutorialSkipButton = Instance.new("TextButton")
	tutorialSkipButton.Size = UDim2.new(0, 60, 0, 26)
	tutorialSkipButton.Position = UDim2.new(1, -75, 0, 14)
	tutorialSkipButton.Font = Enum.Font.Gotham
	tutorialSkipButton.TextSize = 12
	tutorialSkipButton.Text = "Skip"
	tutorialSkipButton.BackgroundColor3 = Color3.fromRGB(60, 48, 38)
	tutorialSkipButton.TextColor3 = Color3.fromRGB(210, 195, 175)
	tutorialSkipButton.ZIndex = 40
	tutorialSkipButton.Parent = tutorialPanel
	polishButton(tutorialSkipButton, 8)
	addButtonHoverScale(tutorialSkipButton)

	local tutorialTitleLabel = Instance.new("TextLabel")
	tutorialTitleLabel.Size = UDim2.new(1, -100, 0, 30)
	tutorialTitleLabel.Position = UDim2.new(0, 20, 0, 16)
	tutorialTitleLabel.BackgroundTransparency = 1
	tutorialTitleLabel.Font = Enum.Font.GothamBold
	tutorialTitleLabel.TextSize = 20
	tutorialTitleLabel.TextXAlignment = Enum.TextXAlignment.Left
	tutorialTitleLabel.TextColor3 = Color3.fromRGB(255, 214, 130)
	tutorialTitleLabel.Text = ""
	tutorialTitleLabel.ZIndex = 40
	tutorialTitleLabel.Parent = tutorialPanel

	local tutorialBodyLabel = Instance.new("TextLabel")
	tutorialBodyLabel.Size = UDim2.new(1, -40, 0, 130)
	tutorialBodyLabel.Position = UDim2.new(0, 20, 0, 56)
	tutorialBodyLabel.BackgroundTransparency = 1
	tutorialBodyLabel.Font = Enum.Font.Gotham
	tutorialBodyLabel.TextSize = 15
	tutorialBodyLabel.TextWrapped = true
	tutorialBodyLabel.TextYAlignment = Enum.TextYAlignment.Top
	tutorialBodyLabel.TextColor3 = Color3.fromRGB(230, 218, 200)
	tutorialBodyLabel.Text = ""
	tutorialBodyLabel.ZIndex = 40
	tutorialBodyLabel.Parent = tutorialPanel

	-- Step-dot row, centered, just above the Back/Next buttons.
	local dotHolder = Instance.new("Frame")
	dotHolder.Size = UDim2.new(0, #STEPS * 18, 0, 10)
	dotHolder.Position = UDim2.new(0.5, 0, 1, -70)
	dotHolder.AnchorPoint = Vector2.new(0.5, 0)
	dotHolder.BackgroundTransparency = 1
	dotHolder.ZIndex = 40
	dotHolder.Parent = tutorialPanel

	local dotLayout = Instance.new("UIListLayout")
	dotLayout.FillDirection = Enum.FillDirection.Horizontal
	dotLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	dotLayout.Padding = UDim.new(0, 6)
	dotLayout.Parent = dotHolder

	local dots = {}
	for i = 1, #STEPS do
		local dot = Instance.new("Frame")
		dot.Size = UDim2.new(0, 8, 0, 8)
		dot.BackgroundColor3 = Color3.fromRGB(90, 75, 60)
		dot.LayoutOrder = i
		dot.ZIndex = 40
		dot.Parent = dotHolder
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = dot
		dots[i] = dot
	end

	local tutorialBackButton = Instance.new("TextButton")
	tutorialBackButton.Size = UDim2.new(0, 100, 0, 40)
	tutorialBackButton.Position = UDim2.new(0, 20, 1, -55)
	tutorialBackButton.Font = Enum.Font.GothamBold
	tutorialBackButton.TextSize = 14
	tutorialBackButton.Text = "Back"
	tutorialBackButton.BackgroundColor3 = Color3.fromRGB(70, 55, 40)
	tutorialBackButton.TextColor3 = Color3.fromRGB(250, 240, 220)
	tutorialBackButton.ZIndex = 40
	tutorialBackButton.Parent = tutorialPanel
	polishButton(tutorialBackButton, 10)
	addButtonHoverScale(tutorialBackButton)

	local tutorialNextButton = Instance.new("TextButton")
	tutorialNextButton.Size = UDim2.new(0, 140, 0, 40)
	tutorialNextButton.Position = UDim2.new(1, -160, 1, -55)
	tutorialNextButton.Font = Enum.Font.GothamBold
	tutorialNextButton.TextSize = 15
	tutorialNextButton.Text = "Next"
	tutorialNextButton.BackgroundColor3 = Color3.fromRGB(90, 60, 30)
	tutorialNextButton.TextColor3 = Color3.fromRGB(250, 240, 220)
	tutorialNextButton.ZIndex = 40
	tutorialNextButton.Parent = tutorialPanel
	polishButton(tutorialNextButton, 10)
	addButtonHoverScale(tutorialNextButton)

	local currentStep = 1

	local function renderStep()
		local step = STEPS[currentStep]
		tutorialTitleLabel.Text = step.title
		tutorialBodyLabel.Text = step.body
		tutorialBackButton.Visible = currentStep > 1
		tutorialNextButton.Text = (currentStep == #STEPS) and "Got it!" or "Next"
		for i, dot in ipairs(dots) do
			dot.BackgroundColor3 = (i == currentStep) and Color3.fromRGB(255, 214, 130) or Color3.fromRGB(90, 75, 60)
		end
	end

	-- Fired exactly once per dismissal path (Skip, or "Got it!" on the
	-- last step) -- idempotent server-side (PlayerProfile.markTutorialSeen)
	-- even if this somehow ran twice, so no extra guard needed here.
	local function dismiss()
		popOut(tutorialBackdrop, tutorialPanel)
		if MarkTutorialSeenRemote then
			MarkTutorialSeenRemote:FireServer()
		end
	end

	tutorialBackButton.MouseButton1Click:Connect(function()
		playClickSfx()
		if currentStep > 1 then
			currentStep = currentStep - 1
			renderStep()
		end
	end)

	tutorialNextButton.MouseButton1Click:Connect(function()
		playClickSfx()
		if currentStep < #STEPS then
			currentStep = currentStep + 1
			renderStep()
		else
			dismiss()
		end
	end)

	tutorialSkipButton.MouseButton1Click:Connect(function()
		playClickSfx()
		dismiss()
	end)

	local function openTutorial()
		currentStep = 1
		renderStep()
		popIn(tutorialBackdrop, tutorialPanel)
	end

	return {
		openTutorial = openTutorial,
	}
end
