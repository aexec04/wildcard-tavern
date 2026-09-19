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
		polishPanel             -- function(instance, radius)
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

	SHOWCASE PASS: Ahmed pointed out the menu "looks so wonky" -- a flat
	solid-brown panel sitting in front of whatever the camera happened to
	be pointed at. Two changes address that without needing any new art
	assets: (1) `menuFrame` is no longer an opaque full-screen panel --
	it's transparent, with a single semi-opaque, rounded "menuScrim" panel
	behind just the title/subtitle/buttons for readability, so the tavern
	room built in the Visual Life Pass (table, lit chandelier, seated
	Patron NPCs) is actually visible around the edges instead of hidden
	behind a flat rectangle -- see Client/MenuCamera.lua (wired in
	init.client.lua) for the camera side of this. (2) buttons get a subtle
	vertical gloss gradient + a warm gold UIStroke border instead of one
	flat fill color, and the title/subtitle get a dark TextStroke for
	contrast now that they're sitting over a busier, moving background
	instead of a flat one.
]]

return function(deps)
	local screenGui = deps.screenGui
	local polishButton = deps.polishButton
	local polishPanel = deps.polishPanel
	local revealStagger = deps.revealStagger
	local addButtonHoverScale = deps.addButtonHoverScale
	local StartDailyChallengeRemote = deps.StartDailyChallengeRemote
	local playClickSfx = deps.playClickSfx
	local StartWeeklyChallengeRemote = deps.StartWeeklyChallengeRemote
	local openSeedRunDialog = deps.openSeedRunDialog
	local openTutorial = deps.openTutorial

	-- No longer an opaque full-screen panel -- see the SHOWCASE PASS note
	-- above. This Frame now only exists to parent/layer everything else;
	-- with BackgroundTransparency 1 it paints nothing, so the 3D tavern
	-- scene behind it (see Client/MenuCamera.lua) shows through anywhere
	-- menuScrim/the title/the buttons don't cover.
	local menuFrame = Instance.new("Frame")
	menuFrame.Name = "MenuRoot"
	menuFrame.Size = UDim2.fromScale(1, 1)
	menuFrame.BackgroundTransparency = 1
	menuFrame.BorderSizePixel = 0
	menuFrame.ZIndex = 10
	menuFrame.Parent = screenGui

	-- A single semi-opaque, rounded panel sitting behind just the title/
	-- subtitle/buttons (ZIndex 9, one below everything else parented to
	-- menuFrame at ZIndex 10) so that content stays readable over a
	-- moving 3D background, while the space AROUND it still shows the
	-- tavern scene clearly.
	local menuScrim = Instance.new("Frame")
	menuScrim.Name = "MenuScrim"
	-- Scale-based height (92% of whatever the screen actually is) rather
	-- than a fixed pixel height, so this card always fits with a small
	-- margin top and bottom no matter the screen's aspect ratio -- the
	-- same reasoning as the ScrollingFrame fix below, applied one level
	-- up.
	menuScrim.Size = UDim2.new(0, 340, 0.92, 0)
	menuScrim.Position = UDim2.fromScale(0.5, 0.5)
	menuScrim.AnchorPoint = Vector2.new(0.5, 0.5)
	menuScrim.BackgroundColor3 = Color3.fromRGB(18, 14, 10)
	-- POLISH PASS: Ahmed's feedback after seeing the Showcase Pass in Play
	-- mode was "the UI isnt as transparent" -- 0.3 was still reading as a
	-- mostly-solid panel. Raised to 0.55 so the tavern room actually shows
	-- through the card behind the title/buttons, not just around its edges.
	menuScrim.BackgroundTransparency = 0.55
	menuScrim.BorderSizePixel = 0
	menuScrim.ZIndex = 9
	menuScrim.Parent = menuFrame
	if polishPanel then
		polishPanel(menuScrim, 24)
	end

	local menuScrimGradient = Instance.new("UIGradient")
	menuScrimGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(34, 24, 14)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(12, 9, 6)),
	})
	menuScrimGradient.Rotation = 90
	menuScrimGradient.Parent = menuScrim

	local menuTitle = Instance.new("TextLabel")
	menuTitle.Size = UDim2.new(1, 0, 0, 70)
	menuTitle.Position = UDim2.new(0, 0, 0, 18)
	menuTitle.BackgroundTransparency = 1
	menuTitle.Font = Enum.Font.GothamBold
	menuTitle.TextSize = 48
	menuTitle.TextColor3 = Color3.fromRGB(255, 214, 130)
	menuTitle.TextStrokeColor3 = Color3.fromRGB(20, 12, 6)
	menuTitle.TextStrokeTransparency = 0.15
	menuTitle.Text = "Wildcard Tavern"
	menuTitle.ZIndex = 10
	menuTitle.Parent = menuScrim

	local menuSubtitle = Instance.new("TextLabel")
	menuSubtitle.Size = UDim2.new(1, 0, 0, 26)
	menuSubtitle.Position = UDim2.new(0, 0, 0, 92)
	menuSubtitle.BackgroundTransparency = 1
	menuSubtitle.Font = Enum.Font.Gotham
	menuSubtitle.TextSize = 18
	menuSubtitle.TextColor3 = Color3.fromRGB(200, 180, 160)
	menuSubtitle.TextStrokeColor3 = Color3.fromRGB(10, 8, 6)
	menuSubtitle.TextStrokeTransparency = 0.4
	menuSubtitle.Text = "a poker hand deckbuilder game!"
	menuSubtitle.ZIndex = 10
	menuSubtitle.Parent = menuScrim

	-- BUGFIX (title/button overlap on short & landscape screens): the
	-- title/subtitle used to sit at fixed SCALE positions (0.3 / 0.42 down
	-- the screen) while the button holder was centered around another
	-- fixed scale point (0.74) -- neither side knew about the other's
	-- actual size. That was fragile even at 4 buttons, and became a real,
	-- visible bug once this grew to 8 buttons (Phases 9/11/16 each added
	-- one): the button stack's real height (~470px) frequently doesn't
	-- fit in whatever fraction of a short/landscape screen "0.74 centered"
	-- happens to land on, so the block rides up and overlaps the title
	-- text -- exactly what a phone-landscape Studio preview showed.
	--
	-- Fixed properly, not by re-guessing another magic percentage: title/
	-- subtitle now sit in a small FIXED-pixel region pinned to the very
	-- top of the screen (safe on any screen height), and the buttons live
	-- inside a ScrollingFrame that fills whatever space is left below
	-- that region. AutomaticCanvasSize.Y means the scroll area always
	-- matches the buttons' real content height, and on a screen too short
	-- to show all 8 at once, it scrolls internally instead of overlapping
	-- or clipping anything above it -- same "convert to a ScrollingFrame
	-- instead of guessing a fixed size" fix already used for the Themes
	-- panel (Phase 14) and the Road Ahead map (Phase 7).
	-- Sized relative to menuScrim (not the full screen) now that title/
	-- subtitle/buttons all live inside that one card -- fills whatever
	-- room is left in the card below the subtitle, with a small bottom
	-- margin, and scrolls internally if the card ends up too short for
	-- all 8 buttons at once.
	local menuButtonScroll = Instance.new("ScrollingFrame")
	menuButtonScroll.Name = "MenuButtonScroll"
	menuButtonScroll.Position = UDim2.new(0.5, 0, 0, 124)
	menuButtonScroll.AnchorPoint = Vector2.new(0.5, 0)
	menuButtonScroll.Size = UDim2.new(0, 260, 1, -144)
	menuButtonScroll.BackgroundTransparency = 1
	menuButtonScroll.BorderSizePixel = 0
	menuButtonScroll.ScrollBarThickness = 6
	menuButtonScroll.ScrollBarImageColor3 = Color3.fromRGB(200, 170, 120)
	menuButtonScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	menuButtonScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	menuButtonScroll.ZIndex = 10
	menuButtonScroll.Parent = menuScrim

	local menuButtonHolder = Instance.new("Frame")
	menuButtonHolder.Size = UDim2.new(1, 0, 0, 0)
	menuButtonHolder.AutomaticSize = Enum.AutomaticSize.Y
	menuButtonHolder.Position = UDim2.new(0.5, 0, 0, 0)
	menuButtonHolder.AnchorPoint = Vector2.new(0.5, 0)
	menuButtonHolder.BackgroundTransparency = 1
	menuButtonHolder.ZIndex = 10
	menuButtonHolder.Parent = menuButtonScroll

	local menuButtonLayout = Instance.new("UIListLayout")
	menuButtonLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	menuButtonLayout.Padding = UDim.new(0, 12)
	menuButtonLayout.Parent = menuButtonHolder

	-- Vertical gloss gradient (lighter near the top, darker near the
	-- bottom -- a consistent light direction, same idea as the Road
	-- Ahead map's landmark shading from Phase 7) plus a warm gold
	-- border, replacing one flat fill color with something that reads as
	-- a deliberately-finished button rather than a placeholder rectangle.
	local function addButtonGloss(button)
		local gradient = Instance.new("UIGradient")
		gradient.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(138, 94, 48)),
			ColorSequenceKeypoint.new(0.55, Color3.fromRGB(96, 64, 32)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(68, 45, 22)),
		})
		gradient.Rotation = 90
		gradient.Parent = button

		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.fromRGB(214, 170, 100)
		stroke.Thickness = 1.5
		stroke.Transparency = 0.25
		stroke.Parent = button
	end

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
		addButtonGloss(button)
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
