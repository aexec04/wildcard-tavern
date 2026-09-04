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
		screenGui              -- ScreenGui, menuFrame's parent
		polishButton            -- function(instance, radius)
		revealStagger           -- function(instances, opts?)
		addButtonHoverScale     -- function(button, opts?)
		StartDailyChallengeRemote -- RemoteEvent, fired on Daily Challenge click
		playClickSfx            -- function(), played on Daily Challenge click
		StartWeeklyChallengeRemote -- RemoteEvent, fired on Weekly Challenge click (Phase 16)
		openSeedRunDialog       -- function(), opens SeedRunDialog.lua's modal (Phase 16)
		openTutorial            -- function(), opens Tutorial.lua's walkthrough (Phase 16)

	Returns:
		{
			menuFrame = Frame,
			menuPlayButton = TextButton,
			menuHowToPlayButton = TextButton,
			menuJourneyButton = TextButton,
			menuNewRunButton = TextButton,
		}

	DAILY CHALLENGE (Phase 11): a 5th button ("Daily Challenge") is added
	to the button holder below. Deliberately NOT returned from this
	module and NOT captured as a new top-level local in init.client.lua --
	its click handler is wired entirely inside this file (fire
	StartDailyChallengeRemote, play the click sfx) since init.client.lua
	is already right up against Lua's 200-local-per-chunk ceiling. Both
	`StartDailyChallengeRemote` and `playClickSfx` are passed in via deps
	as either an inline expression or a reused existing local -- neither
	needs a new local in init.client.lua either.

	WEEKLY CHALLENGE + SEED CODES (Phase 16): same treatment, 2 more
	buttons ("Weekly Challenge", "Seed Run..."), same reasoning -- neither
	captured as a new top-level local, both click handlers wired entirely
	inside this file. "Seed Run..." doesn't fire a remote directly (it
	needs a code from the player first) -- it just calls
	`openSeedRunDialog()`, a callback built by Client/SeedRunDialog.lua
	and threaded through as a dep, same "pass the finished function in,
	don't make this module know how the dialog works" shape as everything
	else here.

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
	local StartDailyChallengeRemote = deps.StartDailyChallengeRemote
	local playClickSfx = deps.playClickSfx
	local StartWeeklyChallengeRemote = deps.StartWeeklyChallengeRemote
	local openSeedRunDialog = deps.openSeedRunDialog
	local openTutorial = deps.openTutorial

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
	menuSubtitle.Text = "a poker hand deckbuilder game!"
	menuSubtitle.ZIndex = 10
	menuSubtitle.Parent = menuFrame

	-- BUGFIX (Daily Challenge cutoff): this holder used to be a FIXED
	-- 240x110 box, top-anchored at 0.55 down the screen -- sized back when
	-- there were only 4 buttons, and even then 110px was already short of
	-- the ~228px 4 buttons actually need (it just happened not to matter,
	-- since a Frame with ClipsDescendants off doesn't clip its own
	-- children -- it only stopped mattering because nothing ever ran past
	-- the bottom of the *screen* itself). Adding the 5th (Daily Challenge)
	-- button pushed the real content height to ~288px, which on a
	-- shorter/smaller Studio play window runs past the bottom screen edge
	-- and gets cut off there -- nothing to do with this Frame's own
	-- bounds. Fixed properly instead of just re-guessing a bigger fixed
	-- box: AutomaticSize.Y makes the holder always exactly as tall as its
	-- buttons, and anchoring/positioning it by its own CENTER (rather than
	-- top-down from a fixed fraction) keeps the whole block roughly
	-- centered in the space below the subtitle regardless of how many
	-- buttons it holds or how tall the screen actually is.
	local menuButtonHolder = Instance.new("Frame")
	menuButtonHolder.Size = UDim2.new(0, 240, 0, 0)
	menuButtonHolder.AutomaticSize = Enum.AutomaticSize.Y
	menuButtonHolder.Position = UDim2.fromScale(0.5, 0.74)
	menuButtonHolder.AnchorPoint = Vector2.new(0.5, 0.5)
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
	local menuDailyChallengeButton = makeMenuButton("\240\159\147\133 Daily Challenge")
	local menuWeeklyChallengeButton = makeMenuButton("\240\159\151\147 Weekly Challenge")
	local menuSeedRunButton = makeMenuButton("\240\159\142\178 Seed Run...")
	local menuTutorialButton = makeMenuButton("🔰 Tutorial")

	menuDailyChallengeButton.MouseButton1Click:Connect(function()
		if playClickSfx then
			playClickSfx()
		end
		if StartDailyChallengeRemote then
			StartDailyChallengeRemote:FireServer()
		end
	end)

	menuWeeklyChallengeButton.MouseButton1Click:Connect(function()
		if playClickSfx then
			playClickSfx()
		end
		if StartWeeklyChallengeRemote then
			StartWeeklyChallengeRemote:FireServer()
		end
	end)

	menuSeedRunButton.MouseButton1Click:Connect(function()
		if playClickSfx then
			playClickSfx()
		end
		if openSeedRunDialog then
			openSeedRunDialog()
		end
	end)

	menuTutorialButton.MouseButton1Click:Connect(function()
		if playClickSfx then
			playClickSfx()
		end
		if openTutorial then
			openTutorial()
		end
	end)

	for _, button in ipairs({
		menuPlayButton,
		menuHowToPlayButton,
		menuJourneyButton,
		menuNewRunButton,
		menuDailyChallengeButton,
		menuWeeklyChallengeButton,
		menuSeedRunButton,
		menuTutorialButton,
	}) do
		addButtonHoverScale(button)
	end

	-- One-shot load-in: title first, subtitle right after, then the 5
	-- buttons cascade in top-to-bottom. Fires immediately at build time
	-- (this screen is visible from the moment the game loads), not on any
	-- later event.
	revealStagger({
		menuTitle,
		menuSubtitle,
		menuPlayButton,
		menuHowToPlayButton,
		menuJourneyButton,
		menuNewRunButton,
		menuDailyChallengeButton,
		menuWeeklyChallengeButton,
		menuSeedRunButton,
		menuTutorialButton,
	}, {
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
