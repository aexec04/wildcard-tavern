--[[
	Client/Menu.lua
	The main menu screen (title, subtitle, and the Play / New Run... /
	Daily / Weekly / Seed / How to Play / Tutorial buttons) shown before a run starts.

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
		menuBackgroundImage     -- string, "rbxassetid://..." -- see Client/ArtAssets.lua

	Returns:
		{
			menuFrame = Frame,
			menuPlayButton = TextButton,
			menuHowToPlayButton = TextButton,
			menuJourneyButton = TextButton,
			menuNewRunButton = TextButton,
			menuTutorialButton = TextButton, -- click wired in init.client.lua (starts the live walkthrough)
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
	panel over a scrim card, with a camera orbiting a 3D tavern scene
	behind it, glossy gradient buttons, and text-stroke titles. Ahmed asked
	to scratch that and go back to a plain 2D menu, so this file is back to
	the simple opaque panel + flat buttons it was before that pass (the 3D
	scene and its camera have since been deleted entirely). The one thing kept
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
	local menuBackgroundImage = deps.menuBackgroundImage
	local TweenService = game:GetService("TweenService")
	local ContentArt = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("ContentArt"))
	local ClientSettings = require(script.Parent.ClientSettings)
	local SkinArt = require(script.Parent.SkinArt)
	local ArtAssets = require(script.Parent.ArtAssets)
	local function calm()
		return ClientSettings.get("reduceShake") == true -- Reduce Shake: no glow, lift or flicker
	end

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
	-- Nov 1 2026: reads ArtAssets.lua (via deps) instead of a hardcoded
	-- DECAL id, which never loaded from code. Thumbnail fallback below.
	-- menu_bg (house style) wins; the older ArtAssets image / flat color is the fallback.
	local menuArtId = ContentArt.getImageId("backgrounds", "menu_bg")
	menuBackgroundArt.Image = menuArtId or menuBackgroundImage or "rbxassetid://0"
	menuBackgroundArt.Active = false
	-- BUGFIX (Nov 1 2026): this ScreenGui uses Global ZIndex layering, so
	-- this ZIndex-9 image drew UNDER its own ZIndex-10 parent's opaque fill
	-- -- the menu art never showed. Same fix as the gameplay screen: the
	-- image now sits at the parent's ZIndex (children draw after their
	-- parent at equal ZIndex, and every menu button is created after it, so
	-- they still draw on top), the parent's fill goes see-through, and the
	-- flat fallback color moves onto the image's own background.
	menuBackgroundArt.ZIndex = 10
	menuBackgroundArt.BackgroundColor3 = menuFrame.BackgroundColor3
	menuBackgroundArt.BackgroundTransparency = 0
	menuFrame.BackgroundTransparency = 1
	menuBackgroundArt.Parent = menuFrame
	if menuArtId then
		-- Dark edge vignette (stepped Frames, Color stops only) above the art, below the logo and buttons.
		require(script.Parent.PanelArt).vignette(menuFrame, 10)
	end
	-- (Removed Nov 1 2026: a ContentProvider:PreloadAsync check used to swap
	-- this to a blurry thumbnail on "Failure" -- but PreloadAsync reports
	-- Failure even for images that load fine, so it was blanking good art.)

	local GOLD = Color3.fromRGB(255, 214, 130)
	local CREAM = Color3.fromRGB(250, 240, 220)
	local ART_Z = 10 -- button art; the buttons themselves sit one above

	-- ===== Title: carved gold look (gold fill, dark stroke, soft drop shadow) =====
	local menuTitleShadow = Instance.new("TextLabel")
	menuTitleShadow.Name = "MenuTitleShadow"
	menuTitleShadow.Size = UDim2.new(1, 0, 0, 80)
	menuTitleShadow.Position = UDim2.new(0, 3, 0, 23)
	menuTitleShadow.BackgroundTransparency = 1
	menuTitleShadow.Font = Enum.Font.GothamBold
	menuTitleShadow.TextSize = 58
	menuTitleShadow.TextColor3 = Color3.fromRGB(0, 0, 0)
	menuTitleShadow.TextTransparency = 0.6
	menuTitleShadow.TextStrokeTransparency = 1
	menuTitleShadow.Text = "Wildcard Tavern"
	menuTitleShadow.ZIndex = 10
	menuTitleShadow.Parent = menuFrame

	local menuTitle = Instance.new("TextLabel")
	menuTitle.Name = "MenuTitle"
	menuTitle.Size = UDim2.new(1, 0, 0, 80)
	menuTitle.Position = UDim2.new(0, 0, 0, 20)
	menuTitle.BackgroundTransparency = 1
	menuTitle.Font = Enum.Font.GothamBold
	menuTitle.TextSize = 58
	menuTitle.TextColor3 = GOLD
	menuTitle.TextTransparency = 0
	menuTitle.TextStrokeColor3 = Color3.fromRGB(60, 36, 14)
	menuTitle.TextStrokeTransparency = 0.1
	menuTitle.Text = "Wildcard Tavern"
	menuTitle.ZIndex = 11
	menuTitle.Parent = menuFrame

	-- Subtitle text lives on a small ribbon banner under the title.
	local menuSubtitle = Instance.new("TextLabel")
	menuSubtitle.Name = "MenuRibbon"
	menuSubtitle.AnchorPoint = Vector2.new(0.5, 0)
	menuSubtitle.Size = UDim2.fromOffset(340, 32)
	menuSubtitle.Position = UDim2.new(0.5, 0, 0, 108)
	menuSubtitle.BackgroundColor3 = Color3.fromRGB(150, 48, 40)
	menuSubtitle.Font = Enum.Font.GothamBold
	menuSubtitle.TextSize = 16
	menuSubtitle.TextColor3 = CREAM
	menuSubtitle.Text = "a poker hand deckbuilder game!"
	menuSubtitle.ZIndex = 11
	menuSubtitle.Parent = menuFrame
	do
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, 4)
		c.Parent = menuSubtitle
		local st = Instance.new("UIStroke")
		st.Color = Color3.fromRGB(214, 172, 88)
		st.Thickness = 1.5
		st.Parent = menuSubtitle
		for side = 1, 2 do -- ribbon tails
			local tail = Instance.new("Frame")
			tail.AnchorPoint = Vector2.new(0.5, 0)
			tail.Size = UDim2.fromOffset(26, 24)
			tail.Position = UDim2.new(0.5, (side == 1 and -1 or 1) * 182, 0, 114)
			tail.BackgroundColor3 = Color3.fromRGB(110, 34, 30)
			tail.BorderSizePixel = 0
			tail.Rotation = side == 1 and -8 or 8
			tail.ZIndex = 10
			tail.Parent = menuFrame
		end
	end

	-- Scrolling holder for the buttons (short screens scroll instead of overlapping the title).
	local menuButtonScroll = Instance.new("ScrollingFrame")
	menuButtonScroll.Name = "MenuButtonScroll"
	menuButtonScroll.Position = UDim2.new(0.5, 0, 0, 160)
	menuButtonScroll.AnchorPoint = Vector2.new(0.5, 0)
	menuButtonScroll.Size = UDim2.new(0, 560, 1, -172)
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
	menuButtonHolder.BackgroundTransparency = 1
	menuButtonHolder.ZIndex = 10
	menuButtonHolder.Parent = menuButtonScroll

	local menuButtonLayout = Instance.new("UIListLayout")
	menuButtonLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	menuButtonLayout.SortOrder = Enum.SortOrder.LayoutOrder
	menuButtonLayout.Padding = UDim.new(0, 18)
	menuButtonLayout.Parent = menuButtonHolder
	local holderPad = Instance.new("UIPadding")
	holderPad.PaddingTop = UDim.new(0, 10)
	holderPad.PaddingBottom = UDim.new(0, 24)
	holderPad.Parent = menuButtonHolder

	local function makeRow(order, height, padding)
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, 0, 0, height)
		row.BackgroundTransparency = 1
		row.LayoutOrder = order
		row.ZIndex = 10
		row.Parent = menuButtonHolder
		local layout = Instance.new("UIListLayout")
		layout.FillDirection = Enum.FillDirection.Horizontal
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		layout.VerticalAlignment = Enum.VerticalAlignment.Center
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Padding = UDim.new(0, padding)
		layout.Parent = row
		return row
	end

	local slots = {} -- stagger-in targets (the slot holds the button so hover can lift it)
	local glowTweens = {}

	-- Ornate wood-and-gold button (the same carved art as Play Hand / Discard), a TextButton
	-- inside a fixed slot. opts: { text, textSize, iconKey, emoji, iconSize, parent, order, width, height, glow }
	local function makeFrameButton(opts)
		local slot = Instance.new("Frame")
		slot.Size = UDim2.fromOffset(opts.width, opts.height)
		slot.BackgroundTransparency = 1
		slot.LayoutOrder = opts.order or 0
		slot.ZIndex = 10
		slot.Parent = opts.parent
		table.insert(slots, slot)

		local button = Instance.new("TextButton")
		button.Size = UDim2.fromScale(1, 1)
		button.Font = Enum.Font.GothamBold
		button.TextSize = opts.textSize
		button.Text = opts.text
		button.TextWrapped = true
		button.TextYAlignment = opts.iconKey and Enum.TextYAlignment.Bottom or Enum.TextYAlignment.Center
		button.TextColor3 = CREAM
		button.TextTransparency = 0
		button.TextStrokeColor3 = Color3.fromRGB(40, 24, 10)
		button.TextStrokeTransparency = 0.5
		button.BackgroundColor3 = Color3.fromRGB(90, 60, 30)
		button.AutoButtonColor = false
		button.ZIndex = ART_Z + 1
		button.Parent = slot
		polishButton(button, 12)
		local rim = button:FindFirstChildOfClass("UIStroke")
		if rim then
			rim.Color = Color3.fromRGB(214, 172, 88)
			rim.Thickness = 2
		end
		local small = opts.width < 120
		local slice = SkinArt.Slices.button
		SkinArt.apply(button, ArtAssets.actionButtonArt, {
			tint = SkinArt.Tints.button,
			zIndex = ART_Z,
			sliceCenter = slice.center,
			sliceScale = small and 0.18 or slice.scale,
			onLoaded = function()
				SkinArt.hideCodeChrome(button)
			end,
		})

		if opts.iconKey then
			-- LABEL CLEARANCE (measured in Studio): the frame art has a thick bottom
			-- border, so padding from the outer edge was not enough. The label lives
			-- in its own TextLabel whose BOTTOM edge is 26px above the button bottom
			-- (24px tall, so text center is 38px above it; minimum 24 / 30). Tiles
			-- (138 tall): icon 10..80, label 88..112. Small (114): icon 8..54, label 64..88.
			button.Text = ""
			local labelBox = Instance.new("TextLabel")
			labelBox.Name = "Label"
			labelBox.AnchorPoint = Vector2.new(0.5, 1)
			labelBox.Position = UDim2.new(0.5, 0, 1, -26)
			labelBox.Size = UDim2.new(1, -16, 0, 24)
			labelBox.BackgroundTransparency = 1
			labelBox.Font = Enum.Font.GothamBold
			labelBox.TextSize = opts.textSize
			labelBox.Text = opts.text
			labelBox.TextWrapped = false
			labelBox.TextXAlignment = Enum.TextXAlignment.Center
			labelBox.TextYAlignment = Enum.TextYAlignment.Center
			labelBox.TextColor3 = CREAM
			labelBox.TextTransparency = 0
			labelBox.TextStrokeColor3 = Color3.fromRGB(40, 24, 10)
			labelBox.TextStrokeTransparency = 0.5
			labelBox.Active = false
			labelBox.ZIndex = ART_Z + 2
			labelBox.Parent = button
			local size = opts.iconSize
			local artId = ContentArt.getImageId("menu_icons", opts.iconKey)
			local holder = Instance.new("Frame")
			holder.AnchorPoint = Vector2.new(0.5, 0)
			holder.Position = UDim2.new(0.5, 0, 0, small and 8 or 10)
			holder.Size = UDim2.fromOffset(size, size)
			holder.BackgroundTransparency = 1
			holder.Active = false
			holder.ZIndex = ART_Z + 2
			holder.Parent = button
			if artId then
				local img = Instance.new("ImageLabel")
				img.Size = UDim2.fromScale(1, 1)
				img.BackgroundTransparency = 1
				img.Image = artId
				img.ScaleType = Enum.ScaleType.Fit
				img.Active = false
				img.ZIndex = ART_Z + 2
				img.Parent = holder
				local c = Instance.new("UICorner")
				c.CornerRadius = UDim.new(0, 8)
				c.Parent = img
			else
				local emoji = Instance.new("TextLabel")
				emoji.Size = UDim2.fromScale(1, 1)
				emoji.BackgroundTransparency = 1
				emoji.Font = Enum.Font.Gotham
				emoji.TextSize = math.floor(size * 0.8)
				emoji.Text = opts.emoji
				emoji.TextTransparency = 0
				emoji.TextStrokeTransparency = 1
				emoji.ZIndex = ART_Z + 2
				emoji.Parent = holder
			end
		end

		-- Hover ring (a separate frame so the art's chrome-hiding never touches it).
		local ring = Instance.new("Frame")
		ring.Name = "HoverRing"
		ring.Size = UDim2.fromScale(1, 1)
		ring.BackgroundTransparency = 1
		ring.Active = false
		ring.ZIndex = ART_Z + 3
		ring.Parent = button
		do
			local c = Instance.new("UICorner")
			c.CornerRadius = UDim.new(0, 10)
			c.Parent = ring
		end
		local ringStroke = Instance.new("UIStroke")
		ringStroke.Color = Color3.fromRGB(255, 232, 160)
		ringStroke.Thickness = 3
		ringStroke.Transparency = 1
		ringStroke.Parent = ring

		local press = Instance.new("UIScale")
		press.Name = "PressScale"
		press.Parent = button

		button.MouseEnter:Connect(function()
			require(script.Parent.Cue).play("hover")
			TweenService:Create(ringStroke, TweenInfo.new(0.12), { Transparency = 0.1 }):Play()
			if not calm() then
				TweenService:Create(button, TweenInfo.new(0.12, Enum.EasingStyle.Quad), { Position = UDim2.fromOffset(0, -3) }):Play()
			end
			if playClickSfx then
				playClickSfx(0.15)
			end
		end)
		local function rest()
			TweenService:Create(ringStroke, TweenInfo.new(0.12), { Transparency = 1 }):Play()
			TweenService:Create(button, TweenInfo.new(0.12, Enum.EasingStyle.Quad), { Position = UDim2.fromOffset(0, 0) }):Play()
			TweenService:Create(press, TweenInfo.new(0.08), { Scale = 1 }):Play()
		end
		button.MouseLeave:Connect(rest)
		button.MouseButton1Down:Connect(function()
			TweenService:Create(press, TweenInfo.new(0.06), { Scale = 0.97 }):Play()
		end)
		button.MouseButton1Up:Connect(function()
			TweenService:Create(press, TweenInfo.new(0.1), { Scale = 1 }):Play()
		end)

		if opts.glow then
			local glow = Instance.new("Frame")
			glow.Name = "PlayGlow"
			glow.AnchorPoint = Vector2.new(0.5, 0.5)
			glow.Position = UDim2.fromScale(0.5, 0.5)
			glow.Size = UDim2.new(1, 8, 1, 8)
			glow.BackgroundTransparency = 1
			glow.Active = false
			glow.ZIndex = ART_Z
			glow.Parent = slot
			local c = Instance.new("UICorner")
			c.CornerRadius = UDim.new(0, 14)
			c.Parent = glow
			local gs = Instance.new("UIStroke")
			gs.Color = Color3.fromRGB(255, 190, 90)
			gs.Thickness = 2
			gs.Transparency = 0.6
			gs.Parent = glow
			-- 1.25s each way = a 2.5s loop; stopped while the menu is closed
			table.insert(glowTweens, TweenService:Create(gs, TweenInfo.new(1.25, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
				{ Thickness = 6, Transparency = 0.15 }))
			table.insert(glowTweens, { reset = function()
				gs.Thickness, gs.Transparency = 2, 0.6
			end })
		end
		return button
	end

	local menuPlayButton = makeFrameButton({
		text = "Play", textSize = 36, parent = menuButtonHolder, order = 1, width = 360, height = 88, glow = true,
	})
	local menuNewRunButton = makeFrameButton({
		text = "New Run...", textSize = 24, parent = menuButtonHolder, order = 2, width = 300, height = 62,
	})
	local tileRow = makeRow(3, 138, 16)
	local menuDailyChallengeButton = makeFrameButton({
		text = "Daily Challenge", textSize = 15, parent = tileRow, order = 1, width = 150, height = 138,
		iconKey = "daily", emoji = "\240\159\147\133", iconSize = 70,
	})
	local menuWeeklyChallengeButton = makeFrameButton({
		text = "Weekly Challenge", textSize = 15, parent = tileRow, order = 2, width = 150, height = 138,
		iconKey = "weekly", emoji = "\240\159\151\147", iconSize = 70,
	})
	local menuSeedRunButton = makeFrameButton({
		text = "Seed Run...", textSize = 15, parent = tileRow, order = 3, width = 150, height = 138,
		iconKey = "seed", emoji = "\240\159\142\178", iconSize = 70,
	})
	local bottomRow = makeRow(4, 114, 16)
	local menuJourneyButton = makeFrameButton({
		text = "Road Ahead", textSize = 14, parent = bottomRow, order = 1, width = 114, height = 114,
		iconKey = "road_ahead", emoji = "\240\159\151\186", iconSize = 46,
	})
	local menuHowToPlayButton = makeFrameButton({
		text = "How to Play", textSize = 14, parent = bottomRow, order = 2, width = 114, height = 114,
		iconKey = "how_to_play", emoji = "\240\159\147\150", iconSize = 46,
	})
	local menuTutorialButton = makeFrameButton({
		text = "Tutorial", textSize = 14, parent = bottomRow, order = 3, width = 114, height = 114,
		iconKey = "tutorial", emoji = "\240\159\148\176", iconSize = 46,
	})

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

	-- One-shot load-in: title, ribbon, then the button slots top to bottom.
	local reveal = { menuTitleShadow, menuTitle, menuSubtitle }
	for _, slot in ipairs(slots) do
		table.insert(reveal, slot)
	end
	revealStagger(reveal, { stagger = 0.08, duration = 0.35, fromScale = 0.7 })

	-- ===== Loops (only while the menu is open; skipped under Reduce Shake) =====
	local loopToken = 0
	local function stopLoops()
		loopToken += 1
		for _, t in ipairs(glowTweens) do
			if t.Cancel then
				t:Cancel()
			elseif t.reset then
				t.reset()
			end
		end
		menuTitle.TextTransparency = 0
	end
	local function startLoops()
		stopLoops()
		if calm() then
			return
		end
		local my = loopToken
		for _, t in ipairs(glowTweens) do
			if t.Play then
				t:Play()
			end
		end
		task.spawn(function()
			task.wait(1.5) -- let the load-in finish first
			while loopToken == my and menuFrame.Visible do
				local d = 0.2 + math.random() * 0.3
				local info = TweenInfo.new(d, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
				TweenService:Create(menuTitle, info, { TextTransparency = math.random() * 0.12 }):Play()
				task.wait(d)
			end
		end)
	end
	menuFrame:GetPropertyChangedSignal("Visible"):Connect(function()
		if menuFrame.Visible then
			startLoops()
		else
			stopLoops()
		end
	end)
	if menuFrame.Visible then
		startLoops()
	end

	return {
		menuFrame = menuFrame,
		menuPlayButton = menuPlayButton,
		menuHowToPlayButton = menuHowToPlayButton,
		menuJourneyButton = menuJourneyButton,
		menuNewRunButton = menuNewRunButton,
		menuDailyChallengeButton = menuDailyChallengeButton,
		menuWeeklyChallengeButton = menuWeeklyChallengeButton,
		menuTutorialButton = menuTutorialButton,
	}
end
