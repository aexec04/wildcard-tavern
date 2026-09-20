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
		menuBackgroundImage     -- string, "rbxassetid://..." -- see Client/ArtAssets.lua

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

	REVERTED "SHOWCASE PASS": for a while this screen was a transparent
	panel over a scrim card, with a camera (Client/MenuCamera.lua) orbiting
	the 3D tavern scene behind it, glossy gradient buttons, and text-stroke
	titles. Ahmed asked to scratch that and go back to a plain 2D menu, so
	this file is back to the simple opaque panel + flat buttons it was
	before that pass (Client/MenuCamera.lua is no longer required by
	anything and init.client.lua no longer wires it up). The one thing kept
	from that whole detour: the ScrollingFrame button layout below, which
	fixed a real title/button overlap bug on short/landscape screens and
	has nothing to do with the showcase idea itself.

	AI ART (post-revert, different from the showcase pass above): a plain
	background ImageLabel behind the flat panel color, sourced from
	Client/ArtAssets.lua -- NOT the code-only gradient/glow pass that was
	tried and reverted earlier. This is a real illustrated background
	image (an empty tavern-room scene from the art brief), currently still
	the "rbxassetid://0" placeholder until it's uploaded to Roblox. No
	camera, no 3D reveal, no transparency tricks -- same flat 2D menu,
	just with a real picture behind it once the id is filled in.
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
	local menuBackgroundImage = deps.menuBackgroundImage

	local menuFrame = Instance.new("Frame")
	menuFrame.Name = "MenuRoot"
	menuFrame.Size = UDim2.fromScale(1, 1)
	menuFrame.BackgroundColor3 = Color3.fromRGB(18, 14, 10)
	menuFrame.BorderSizePixel = 0
	menuFrame.ZIndex = 10
	menuFrame.Parent = screenGui

	-- ART (placeholder-safe, see Client/ArtAssets.lua): background art from
	-- the art brief. BackgroundTransparency on the IMAGE stays 1 -- it's
	-- menuFrame's own flat BackgroundColor3 above that acts as the fallback
	-- for as long as menuBackgroundImage is still the "rbxassetid://0"
	-- placeholder (Roblox renders that as simply no image, never an
	-- error). ZIndex 9 (menuFrame's other children are all 10) guarantees
	-- this sits behind everything regardless of creation order.
	local menuBackgroundArt = Instance.new("ImageLabel")
	menuBackgroundArt.Name = "MenuBackgroundArt"
	menuBackgroundArt.Size = UDim2.fromScale(1, 1)
	menuBackgroundArt.BackgroundTransparency = 1
	menuBackgroundArt.BorderSizePixel = 0
	menuBackgroundArt.ScaleType = Enum.ScaleType.Crop
	menuBackgroundArt.Image = menuBackgroundImage or "rbxassetid://0"
	menuBackgroundArt.ZIndex = 9
	menuBackgroundArt.Parent = menuFrame

	local menuTitle = Instance.new("TextLabel")
	menuTitle.Size = UDim2.new(1, 0, 0, 70)
	menuTitle.Position = UDim2.new(0, 0, 0, 18)
	menuTitle.BackgroundTransparency = 1
	menuTitle.Font = Enum.Font.GothamBold
	menuTitle.TextSize = 48
	menuTitle.TextColor3 = Color3.fromRGB(255, 214, 130)
	menuTitle.Text = "Wildcard Tavern"
	menuTitle.ZIndex = 10
	menuTitle.Parent = menuFrame

	local menuSubtitle = Instance.new("TextLabel")
	menuSubtitle.Size = UDim2.new(1, 0, 0, 26)
	menuSubtitle.Position = UDim2.new(0, 0, 0, 92)
	menuSubtitle.BackgroundTransparency = 1
	menuSubtitle.Font = Enum.Font.Gotham
	menuSubtitle.TextSize = 18
	menuSubtitle.TextColor3 = Color3.fromRGB(200, 180, 160)
	menuSubtitle.Text = "a poker hand deckbuilder game!"
	menuSubtitle.ZIndex = 10
	menuSubtitle.Parent = menuFrame

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
	local menuButtonScroll = Instance.new("ScrollingFrame")
	menuButtonScroll.Name = "MenuButtonScroll"
	menuButtonScroll.Position = UDim2.new(0.5, 0, 0, 124)
	menuButtonScroll.AnchorPoint = Vector2.new(0.5, 0)
	menuButtonScroll.Size = UDim2.new(0, 260, 1, -134)
	menuButtonScroll.BackgroundTransparency = 1
	menuButtonScroll.BorderSizePixel = 0
	menuButtonScroll.ScrollBarThickness = 6
	menuButtonScroll.ScrollBarImageColor3 = Color3.fromRGB(200, 170, 120)
	menuButtonScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	menuButtonScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	menuButtonScroll.ZIndex = 10
	menuButtonScroll.Parent = menuFrame

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
