--[[
	Client/Menu.lua
	The main menu: the tavern IS the menu. A painted backdrop with parallax layers, a title ribbon, slim parchment strips
	(news, rank, next goal, today's board) and painted hotspots instead of a button grid.

	Modules: Engine/MenuLayout.lua (hotspot positions, parallax numbers, tested), Client/MenuHotspots.lua (objects, carved
	wooden plaques, fans, the All actions list), Client/MenuParallax.lua (cursor parallax), Client/MenuScene.lua (lantern, motes,
	candle glow, smoke). Reduce Shake / Reduce Motion (calm mode) turns parallax, flicker and drops off. Phones show only the
	All actions list (Play first).

	Every action is ONE real TextButton (MenuHotspots.newAction) that other scripts wire their click handlers to, so the names
	returned below are unchanged: the hotspots and the list only move those buttons around.

	deps fields:
		screenGui, polishButton, revealStagger, addButtonHoverScale -- as before (polishButton / addButtonHoverScale unused now)
		StartDailyChallengeRemote, StartWeeklyChallengeRemote, openSeedRunDialog, playClickSfx
		menuBackgroundImage -- string, "rbxassetid://..." -- see Client/ArtAssets.lua (fallback when menu_bg is missing)

	Returns the same table as before (menuFrame and the action buttons the hub wires up).
]]

return function(deps)
	local screenGui = deps.screenGui
	local revealStagger = deps.revealStagger
	local StartDailyChallengeRemote = deps.StartDailyChallengeRemote
	local playClickSfx = deps.playClickSfx
	local StartWeeklyChallengeRemote = deps.StartWeeklyChallengeRemote
	local openSeedRunDialog = deps.openSeedRunDialog
	local menuBackgroundImage = deps.menuBackgroundImage
	local TweenService = game:GetService("TweenService")
	local Engine = game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine")
	local ContentArt = require(Engine:WaitForChild("ContentArt"))
	local Layout = require(Engine:WaitForChild("MenuLayout"))
	local ClientSettings = require(script.Parent.ClientSettings)
	local Hotspots = require(script.Parent.MenuHotspots)
	local OverlayManager = require(script.Parent.OverlayManager)
	local function calm()
		return ClientSettings.get("reduceShake") == true -- Reduce Shake / Reduce Motion: no parallax, glow, lift or flicker
	end

	local menuFrame = Instance.new("Frame")
	menuFrame.Name = "MenuRoot"
	menuFrame.Size = UDim2.fromScale(1, 1)
	menuFrame.BackgroundColor3 = Color3.fromRGB(18, 14, 10)
	menuFrame.BackgroundTransparency = 1
	menuFrame.BorderSizePixel = 0
	menuFrame.ZIndex = 10
	menuFrame.Parent = screenGui

	-- Far layer: the painted backdrop, drawn 8 percent larger so parallax never shows an edge. Global ZIndex layering: the image
	-- sits at the parent's ZIndex and everything else is created after it.
	local menuBackgroundArt = Instance.new("ImageLabel")
	menuBackgroundArt.Name = "MenuBackgroundArt"
	menuBackgroundArt.AnchorPoint = Vector2.new(0.5, 0.5)
	menuBackgroundArt.Position = UDim2.fromScale(0.5, 0.5)
	menuBackgroundArt.Size = UDim2.fromScale(Layout.Parallax.backdropScale, Layout.Parallax.backdropScale)
	menuBackgroundArt.BorderSizePixel = 0
	menuBackgroundArt.ScaleType = Enum.ScaleType.Crop
	local menuArtId = ContentArt.getImageId("backgrounds", "menu_bg") -- house style art wins; ArtAssets image / flat colour is the fallback
	menuBackgroundArt.Image = menuArtId or menuBackgroundImage or "rbxassetid://0"
	menuBackgroundArt.Active = false
	menuBackgroundArt.ZIndex = 10
	menuBackgroundArt.BackgroundColor3 = Color3.fromRGB(18, 14, 10)
	menuBackgroundArt.BackgroundTransparency = 0
	menuBackgroundArt.Parent = menuFrame
	if menuArtId then
		require(script.Parent.PanelArt).vignette(menuFrame, 10) -- dark edge vignette (stepped Frames, Color stops only)
	end

	-- Hovering a hotspot dims the rest of the scene by 20 percent.
	local sceneDim = Instance.new("Frame")
	sceneDim.Name = "SceneDim"
	sceneDim.Size = UDim2.fromScale(1, 1)
	sceneDim.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	sceneDim.BackgroundTransparency = 1
	sceneDim.BorderSizePixel = 0
	sceneDim.Active = false
	sceneDim.ZIndex = 10
	sceneDim.Parent = menuFrame

	local GOLD = Color3.fromRGB(255, 214, 130)
	local CREAM = Color3.fromRGB(250, 240, 220)

	-- ===== Near layer: the carved gold title and the ribbon =====
	local titleGroup = Instance.new("Frame")
	titleGroup.Name = "TitleGroup"
	titleGroup.Size = UDim2.fromScale(1, 1)
	titleGroup.BackgroundTransparency = 1
	titleGroup.Active = false
	titleGroup.ZIndex = 11
	titleGroup.Parent = menuFrame

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
	menuTitleShadow.Parent = titleGroup

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
	menuTitle.Parent = titleGroup

	local menuSubtitle = Instance.new("TextLabel")
	menuSubtitle.Name = "MenuRibbon"
	menuSubtitle.AnchorPoint = Vector2.new(0.5, 0)
	menuSubtitle.Size = UDim2.fromOffset(340, 32)
	menuSubtitle.Position = UDim2.new(0.5, 0, 0, 108)
	menuSubtitle.BackgroundColor3 = Color3.fromRGB(150, 48, 40)
	menuSubtitle.Font = Enum.Font.GothamBold
	menuSubtitle.TextSize = 16
	menuSubtitle.TextColor3 = CREAM
	menuSubtitle.TextTransparency = 0
	menuSubtitle.TextStrokeTransparency = 1
	menuSubtitle.Text = "a poker hand deckbuilder game!"
	menuSubtitle.ZIndex = 11
	menuSubtitle.Parent = titleGroup
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
			tail.Parent = titleGroup
		end
	end

	-- ===== Slim parchment strips: news, rank, next goal, today's board =====
	local menuButtonScroll = Instance.new("ScrollingFrame")
	menuButtonScroll.Name = "MenuButtonScroll"
	menuButtonScroll.Position = UDim2.new(0.5, 0, 0, 146)
	menuButtonScroll.AnchorPoint = Vector2.new(0.5, 0)
	menuButtonScroll.Size = UDim2.new(1, -16, 0, 176)
	menuButtonScroll.BackgroundTransparency = 1
	menuButtonScroll.BorderSizePixel = 0
	menuButtonScroll.ScrollBarThickness = 6
	menuButtonScroll.ScrollingEnabled = true
	menuButtonScroll.ScrollBarImageColor3 = Color3.fromRGB(200, 170, 120)
	menuButtonScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	menuButtonScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	menuButtonScroll.ZIndex = 12
	menuButtonScroll.Parent = menuFrame
	local scrollLimit = Instance.new("UISizeConstraint")
	scrollLimit.MaxSize = Vector2.new(700, 1000)
	scrollLimit.Parent = menuButtonScroll

	local menuButtonHolder = Instance.new("Frame")
	menuButtonHolder.Size = UDim2.new(1, 0, 0, 0)
	menuButtonHolder.AutomaticSize = Enum.AutomaticSize.Y
	menuButtonHolder.BackgroundTransparency = 1
	menuButtonHolder.ZIndex = 12
	menuButtonHolder.Parent = menuButtonScroll
	local menuButtonLayout = Instance.new("UIListLayout")
	menuButtonLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	menuButtonLayout.SortOrder = Enum.SortOrder.LayoutOrder
	menuButtonLayout.Padding = UDim.new(0, 6)
	menuButtonLayout.Parent = menuButtonHolder
	local holderPad = Instance.new("UIPadding")
	holderPad.PaddingTop = UDim.new(0, 8)
	holderPad.PaddingBottom = UDim.new(0, 8)
	holderPad.Parent = menuButtonHolder

	require(script.Parent.NewsPanel).attach(menuButtonHolder, -3) -- News banner for the running live event (state.news)
	require(script.Parent.MenuRank).attach(menuButtonHolder, -2) -- Tavern Rank bar (state.rank)
	require(script.Parent.NextGoalBanner).attach(menuButtonHolder, -1) -- Next Goal line (state.nextGoal)
	-- Today's best run and a rounded run count (Client/MenuTicker.lua); its button opens the Daily board (wired by the hub)
	local menuTickerButton = require(script.Parent.MenuTicker).attach(menuButtonHolder, 0)

	-- ===== Actions: one real button each =====
	local buttons = {}
	for _, action in ipairs(Layout.Actions) do
		local hotspot = Layout.hotspotOf(action.id)
		local single = hotspot and #hotspot.actions == 1
		buttons[action.id] = Hotspots.newAction(action.id, {
			actionLabel = action.label,
			hotspotLabel = (single or action.id == "play") and hotspot.label or action.label,
			desc = (single or action.id == "play") and hotspot.desc or "",
		})
		buttons[action.id].MouseEnter:Connect(function()
			require(script.Parent.Cue).play("hover")
		end)
	end
	local menuPlayButton = buttons.play
	local menuNewRunButton = buttons.newRun
	local menuDailyChallengeButton = buttons.daily
	local menuWeeklyChallengeButton = buttons.weekly
	local menuSeedRunButton = buttons.seed
	local menuQuestsButton = buttons.quests
	local menuJourneyButton = buttons.road
	local menuHowToPlayButton = buttons.howToPlay
	local menuTutorialButton = buttons.tutorial
	local menuCollectionButton = buttons.collection
	local menuSettingsButton = buttons.settings
	local menuStoreButton = buttons.store
	local menuInviteButton = buttons.invite
	local menuSeasonButton = buttons.season
	local menuDailyRewardsButton = buttons.rewards
	require(script.Parent.InvitePrompt).bind(menuInviteButton)

	-- Panels that open through OverlayManager openers (no old Menu button): Flair, Legend, Ledger, Leaderboards, Volume.
	for id, overlay in pairs({ flair = "flair", legend = "legend", stats = "stats", leaderboards = "dailyLeaderboard", volume = "volume" }) do
		buttons[id].MouseButton1Click:Connect(function()
			pcall(OverlayManager.open, overlay) -- each panel's opener plays its own click sound
		end)
	end
	menuDailyRewardsButton.MouseButton1Click:Connect(function()
		pcall(function() require(script.Parent.DailyRewardsPanel).open() end)
	end)
	menuDailyChallengeButton.MouseButton1Click:Connect(function()
		if playClickSfx then
			playClickSfx()
		end
		local CS = require(script.Parent.ChallengeStart)
		if CS.ready() then
			CS.start("daily", menuDailyChallengeButton) -- checks the state, asks first if a run is in progress, shows the table
		elseif StartDailyChallengeRemote then
			StartDailyChallengeRemote:FireServer()
		end
	end)
	menuWeeklyChallengeButton.MouseButton1Click:Connect(function()
		if playClickSfx then
			playClickSfx()
		end
		local CS = require(script.Parent.ChallengeStart)
		if CS.ready() then
			CS.start("weekly", menuWeeklyChallengeButton)
		elseif StartWeeklyChallengeRemote then
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

	-- "New" ribbon until the tutorial has been completed once or dismissed. It is a child of the button (survives Clone, never
	-- blocks clicks); TutorialWalkthrough hides it via TutorialBus "tutorialNew". The Open Book hotspot mirrors it.
	local ribbon = Instance.new("TextLabel")
	ribbon.Name = "NewRibbon"
	ribbon.AnchorPoint = Vector2.new(1, 0)
	ribbon.Position = UDim2.new(1, -2, 0, 2)
	ribbon.Size = UDim2.fromOffset(44, 22)
	ribbon.BackgroundColor3 = Color3.fromRGB(176, 52, 40)
	ribbon.Font = Enum.Font.GothamBold
	ribbon.Text = "New"
	ribbon.TextSize = 15
	ribbon.TextColor3 = Color3.fromRGB(250, 235, 200)
	ribbon.TextTransparency = 0
	ribbon.TextStrokeTransparency = 1
	ribbon.Rotation = 8
	ribbon.ZIndex = 20
	ribbon.Active = false
	ribbon:SetAttribute("ZOff", 6)
	ribbon.Parent = menuTutorialButton
	do
		local rc = Instance.new("UICorner")
		rc.CornerRadius = UDim.new(0, 5)
		rc.Parent = ribbon
		require(script.Parent.TutorialBus).register("tutorialNew", function() return ribbon end)
		ribbon:SetAttribute("Dismiss", false)
		ribbon:GetAttributeChangedSignal("Dismiss"):Connect(function()
			if ribbon:GetAttribute("Dismiss") then
				ribbon.Visible = false
			end
		end)
	end

	-- ===== Mid layer: the hotspots =====
	local hotspotLayer = Instance.new("Frame")
	hotspotLayer.Name = "HotspotLayer"
	hotspotLayer.Size = UDim2.fromScale(1, 1)
	hotspotLayer.BackgroundTransparency = 1
	hotspotLayer.Active = false
	hotspotLayer.ZIndex = 13
	hotspotLayer.Parent = menuFrame

	local hotspots = Hotspots.build({
		menuFrame = menuFrame,
		layer = hotspotLayer,
		buttons = buttons,
		calm = calm,
		tutorialRibbon = ribbon,
		onHover = function(on)
			TweenService:Create(sceneDim, TweenInfo.new(0.12), { BackgroundTransparency = on and 0.8 or 1 }):Play()
		end,
	})
	local function viewport()
		local v = screenGui.AbsoluteSize
		if v.X <= 0 or v.Y <= 0 then
			local camera = workspace.CurrentCamera
			v = camera and camera.ViewportSize or Vector2.new(1920, 1080)
		end
		return v
	end
	hotspots.applyViewport(viewport().X, viewport().Y)
	screenGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		local v = viewport()
		hotspots.applyViewport(v.X, v.Y)
	end)

	-- ===== Foreground and parallax =====
	local scene = require(script.Parent.MenuScene).build(menuFrame)
	local P = Layout.Parallax
	local parallax = require(script.Parent.MenuParallax).new({
		screenGui = screenGui,
		calm = calm,
		layers = {
			{ inst = menuBackgroundArt, base = UDim2.fromScale(0.5, 0.5), px = P.far },
			{ inst = hotspotLayer, base = UDim2.new(), px = P.mid },
			{ inst = titleGroup, base = UDim2.new(), px = P.near },
			{ inst = menuTitle, base = UDim2.new(0, 0, 0, 20), px = 0, tilt = true },
		},
		onStep = scene.update,
	})

	-- One-shot load-in: title and ribbon fade up, the hotspots drop in with a 0.06s stagger.
	revealStagger({ menuTitleShadow, menuTitle, menuSubtitle }, { stagger = 0.08, duration = 0.35, fromScale = 0.7 })

	-- ===== Loops (only while the menu is open; skipped under Reduce Shake) =====
	local loopToken = 0
	local function stopLoops()
		loopToken += 1
		hotspots.stopLoops()
		hotspots.closeAll()
		parallax.stop()
		menuTitle.TextTransparency = 0
	end
	local function startLoops()
		stopLoops()
		hotspots.entry()
		parallax.start() -- holds still in calm mode
		if calm() then
			return
		end
		local my = loopToken
		hotspots.startLoops()
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
		menuCollectionButton = menuCollectionButton,
		menuSettingsButton = menuSettingsButton,
		menuQuestsButton = menuQuestsButton,
		menuStoreButton = menuStoreButton,
		menuSeasonButton = menuSeasonButton,
		menuTickerButton = menuTickerButton,
	}
end
