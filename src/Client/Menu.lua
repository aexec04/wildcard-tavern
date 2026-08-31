--[[
	Client/Menu.lua
	The main menu screen (title, subtitle, and the Play / How to Play /
	Road Ahead / New Run... buttons) shown before a run starts.

	Extracted out of init.client.lua as part of splitting the client script
	into smaller, per-feature files. Everything this builds is needed back
	in init.client.lua: menuFrame is toggled by the "Menu -> game
	transition" glue and by RunSetup's Begin Run handler, and the four
	buttons are each wired up elsewhere (menuPlayButton in the transition
	glue right after this; the other three are passed as deps into
	HowToPlay.lua/Journey.lua/RunSetup.lua, which wire their own click
	handlers).

	deps fields:
		screenGui           -- ScreenGui, menuFrame's parent
		polishButton         -- function(instance, radius)
		revealStagger        -- function(instances, opts?)
		addButtonHoverScale  -- function(button, opts?)

	Returns:
		{
			menuFrame = Frame,
			menuPlayButton = TextButton,
			menuHowToPlayButton = TextButton,
			menuJourneyButton = TextButton,
			menuNewRunButton = TextButton,
		}

	POLISH PASS (Batch 2): this is the very first thing every player
	sees, and previously had ZERO animation -- the whole screen (title,
	subtitle, 4 buttons) just appeared instantly, fully formed, the
	moment the LocalScript finished running, and the buttons themselves
	had no hover/press feedback at all. Now the title/subtitle/buttons
	cascade in with a staggered scale-and-fade (`revealStagger`,
	VisualHelpers.lua) the moment this module builds them -- a one-shot
	load-in animation, not tied to render() or any state -- and each
	button gets a small hover swell / press dip (`addButtonHoverScale`).
]]

return function(deps)
	local screenGui = deps.screenGui
	local polishButton = deps.polishButton
	local revealStagger = deps.revealStagger
	local addButtonHoverScale = deps.addButtonHoverScale

	local menuFrame = Instance.new("Frame")
	menuFrame.Name = "MenuRoot"
	menuFrame.Size = UDim2.fromScale(1, 1)
	menuFrame.BackgroundColor3 = Color3.fromRGB(18, 14, 10)
	menuFrame.BorderSizePixel = 0
	menuFrame.ZIndex = 10
	menuFrame.Parent = screenGui

	local menuTitle = Instance.new("TextLabel")
	menuTitle.Size = UDim2.new(1, 0, 0, 80)
	menuTitle.Position = UDim2.fromScale(0, 0.3)
	menuTitle.BackgroundTransparency = 1
	menuTitle.Font = Enum.Font.GothamBold
	menuTitle.TextSize = 48
	menuTitle.TextColor3 = Color3.fromRGB(255, 214, 130)
	menuTitle.Text = "Wildcard Tavern"
	menuTitle.ZIndex = 10
	menuTitle.Parent = menuFrame

	local menuSubtitle = Instance.new("TextLabel")
	menuSubtitle.Size = UDim2.new(1, 0, 0, 30)
	menuSubtitle.Position = UDim2.fromScale(0, 0.42)
	menuSubtitle.BackgroundTransparency = 1
	menuSubtitle.Font = Enum.Font.Gotham
	menuSubtitle.TextSize = 18
	menuSubtitle.TextColor3 = Color3.fromRGB(200, 180, 160)
	menuSubtitle.Text = "a poker-hand deckbuilder -- working title"
	menuSubtitle.ZIndex = 10
	menuSubtitle.Parent = menuFrame

	local menuButtonHolder = Instance.new("Frame")
	menuButtonHolder.Size = UDim2.new(0, 240, 0, 110)
	menuButtonHolder.Position = UDim2.fromScale(0.5, 0.55)
	menuButtonHolder.AnchorPoint = Vector2.new(0.5, 0)
	menuButtonHolder.BackgroundTransparency = 1
	menuButtonHolder.ZIndex = 10
	menuButtonHolder.Parent = menuFrame

	local menuButtonLayout = Instance.new("UIListLayout")
	menuButtonLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	menuButtonLayout.Padding = UDim.new(0, 12)
	menuButtonLayout.Parent = menuButtonHolder

	local function makeMenuButton(text)
		local button = Instance.new("TextButton")
		button.Size = UDim2.new(0, 220, 0, 48)
		button.Font = Enum.Font.GothamBold
		button.TextSize = 20
		button.Text = text
		button.BackgroundColor3 = Color3.fromRGB(90, 60, 30)
		button.TextColor3 = Color3.fromRGB(250, 240, 220)
		button.ZIndex = 10
		button.Parent = menuButtonHolder
		polishButton(button, 12)
		return button
	end

	local menuPlayButton = makeMenuButton("Play")
	local menuHowToPlayButton = makeMenuButton("How to Play")
	local menuJourneyButton = makeMenuButton("Road Ahead")
	local menuNewRunButton = makeMenuButton("New Run...")

	for _, button in ipairs({ menuPlayButton, menuHowToPlayButton, menuJourneyButton, menuNewRunButton }) do
		addButtonHoverScale(button)
	end

	-- One-shot load-in: title first, subtitle right after, then the 4
	-- buttons cascade in top-to-bottom. Fires immediately at build time
	-- (this screen is visible from the moment the game loads), not on any
	-- later event.
	revealStagger({ menuTitle, menuSubtitle, menuPlayButton, menuHowToPlayButton, menuJourneyButton, menuNewRunButton }, {
		stagger = 0.08,
		duration = 0.35,
		fromScale = 0.7,
	})

	return {
		menuFrame = menuFrame,
		menuPlayButton = menuPlayButton,
		menuHowToPlayButton = menuHowToPlayButton,
		menuJourneyButton = menuJourneyButton,
		menuNewRunButton = menuNewRunButton,
	}
end
