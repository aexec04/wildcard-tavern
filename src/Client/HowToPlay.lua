--[[
	Client/HowToPlay.lua
	The "How to Play" overlay: a full-screen backdrop + a two-page panel. Page 1
	is a 3x2 grid of painted-icon rule tiles, page 2 lists every hand type with
	an example and its base chips x mult. Reachable from the main menu's "How to
	Play" button and from the Settings panel's "How to Play" button.

	Extracted out of init.client.lua as part of splitting the client script
	into smaller, per-feature files. Fully self-contained: nothing outside
	this module needs anything it builds (both buttons that open it are
	wired from inside), so unlike Shop.lua this module returns an empty
	table -- it's here purely so init.client.lua doesn't have to carry this
	~280-line block inline anymore.

	deps fields:
		screenGui           -- ScreenGui, the panel's ultimate parent (via backdrop)
		polishPanel          -- function(instance, radius)
		polishButton         -- function(instance, radius)
		roundCorner          -- function(instance, radius)
		addSoftShadow        -- function(instance, radius)
		playClickSfx         -- function(volume?)
		RED_SUITS            -- table, suit name -> true for red suits
		RANK_NAMES           -- table, rank number -> display name
		SUIT_SYMBOLS         -- table, suit name -> unicode symbol
		HandEvaluator         -- the Shared/Engine/HandEvaluator module
		Scoring              -- the Shared/Engine/Scoring module
		menuHowToPlayButton  -- TextButton, "How to Play" on the main menu
		helpButton           -- TextButton, Settings.lua's "How to Play" button (was the "?" corner icon)
		popIn                -- function(backdrop, content, opts?)
		popOut               -- function(backdrop, content, opts?, onHidden?)
		addButtonHoverScale  -- function(button, opts?)

	Returns: {} (nothing else in the client needs to reach into this overlay)

	POLISH PASS (Batch 3): this overlay used to show/hide with a bare
	Visible = true/false, one of several remaining screens flagged at the
	end of Batch 2 as still doing a hard cut. Now uses the shared
	popIn/popOut helpers (same family ConfirmDialog/GameOver already use)
	plus addButtonHoverScale on the "Got it" button.
]]

return function(deps)
	local screenGui = deps.screenGui
	local polishPanel = deps.polishPanel
	local polishButton = deps.polishButton
	local roundCorner = deps.roundCorner
	local addSoftShadow = deps.addSoftShadow
	local playClickSfx = deps.playClickSfx
	local RED_SUITS = deps.RED_SUITS
	local RANK_NAMES = deps.RANK_NAMES
	local SUIT_SYMBOLS = deps.SUIT_SYMBOLS
	local HandEvaluator = deps.HandEvaluator
	local Scoring = deps.Scoring
	local menuHowToPlayButton = deps.menuHowToPlayButton
	local helpButton = deps.helpButton
	local popIn = deps.popIn
	local popOut = deps.popOut
	local addButtonHoverScale = deps.addButtonHoverScale
	local replayTutorial = deps.replayTutorial -- optional function()
	-- BUGFIX (overlapping overlays): see Client/OverlayManager.lua's own
	-- header comment for the full story.
	local OverlayManager = require(script.Parent.OverlayManager)

	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local ContentProvider = game:GetService("ContentProvider")
	local ContentArt = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("ContentArt"))

	local GOLD = Color3.fromRGB(255, 214, 130)
	local CREAM = Color3.fromRGB(250, 240, 220)
	local TILE_BG = Color3.fromRGB(60, 45, 32)
	local Z = 21
	local PANEL_W, TITLE_H, BODY_H, NAV_H = 760, 56, 440, 64
	local PAD = 16

	-- Full-screen dim backdrop. Active = true so clicks never reach the game.
	local howToPlayBackdrop = Instance.new("Frame")
	howToPlayBackdrop.Name = "HowToPlayBackdrop"
	howToPlayBackdrop.Size = UDim2.fromScale(1, 1)
	howToPlayBackdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	howToPlayBackdrop.BackgroundTransparency = 0.45
	howToPlayBackdrop.Active = true
	howToPlayBackdrop.Visible = false
	howToPlayBackdrop.ZIndex = 20
	howToPlayBackdrop.Parent = screenGui

	local howToPlayPanel = Instance.new("Frame")
	howToPlayPanel.Name = "HowToPlayPanel"
	howToPlayPanel.Size = UDim2.new(0, PANEL_W, 0, TITLE_H + BODY_H + NAV_H)
	howToPlayPanel.AnchorPoint = Vector2.new(0.5, 0.5)
	howToPlayPanel.Position = UDim2.fromScale(0.5, 0.5)
	howToPlayPanel.BackgroundColor3 = Color3.fromRGB(40, 30, 22)
	howToPlayPanel.ZIndex = Z
	howToPlayPanel.Parent = howToPlayBackdrop
	polishPanel(howToPlayPanel, 16, "parchment")
	addSoftShadow(howToPlayPanel, 18)
	-- Notice-board art; the dark scrim sits behind the text area so cream text stays readable.
	require(script.Parent.PanelArt).add(howToPlayPanel, {
		key = "how_to_play_bg",
		scrim = { position = UDim2.fromOffset(PAD, TITLE_H), size = UDim2.new(1, -2 * PAD, 0, BODY_H) },
		scrimTransparency = 0.3,
	})
	-- Lazy build (GUI weight): pages, nav and title are created on first open;
	-- the backdrop and empty panel stay so PopupDismiss and OverlayManager list them.
	local showPage, howToPlayTitle
	local built = false
	local function build()
		if built then return end
		built = true
		-- Shrink on small screens instead of clipping.
		local fitScale = Instance.new("UIScale")
		fitScale.Parent = howToPlayPanel
		local function refit()
			local vp = screenGui.AbsoluteSize
			local s = math.min(1, (vp.X - 24) / PANEL_W, (vp.Y - 24) / (TITLE_H + BODY_H + NAV_H))
			fitScale.Scale = math.max(0.4, s)
		end
		screenGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(refit)
		refit()

		howToPlayTitle = Instance.new("TextLabel")
		howToPlayTitle.Size = UDim2.new(1, 0, 0, TITLE_H)
		howToPlayTitle.BackgroundTransparency = 1
		howToPlayTitle.Font = Enum.Font.GothamBold
		howToPlayTitle.TextSize = 26
		howToPlayTitle.TextColor3 = CREAM
		howToPlayTitle.ZIndex = Z
		howToPlayTitle.Parent = howToPlayPanel

		local function makePage(name)
			local f = Instance.new("Frame")
			f.Name = name
			f.Size = UDim2.new(1, -2 * PAD, 0, BODY_H)
			f.Position = UDim2.new(0, PAD, 0, TITLE_H)
			f.BackgroundTransparency = 1
			f.ZIndex = Z
			f.Visible = false
			f.Parent = howToPlayPanel
			return f
		end

		-- ===== Page 1: The Basics (3x2 tiles) =====
		local basicsPage = makePage("BasicsPage")
		local STEPS = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("HowToPlayText")).Tiles
		local GAP = 12
		local TILE_W = (PANEL_W - 2 * PAD - 2 * GAP) / 3
		local TILE_H = (BODY_H - GAP) / 2

		for i, step in ipairs(STEPS) do
			local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
			local tile = Instance.new("Frame")
			tile.Size = UDim2.new(0, math.floor(TILE_W), 0, math.floor(TILE_H))
			tile.Position = UDim2.new(0, math.floor(col * (TILE_W + GAP)), 0, math.floor(row * (TILE_H + GAP)))
			tile.BackgroundColor3 = TILE_BG
			tile.ZIndex = Z
			tile.Parent = basicsPage
			polishPanel(tile, 10)
			-- Icon (72) + title (28) + body (72) block, centered vertically in the tile.
			local blockTop = math.max(8, math.floor((math.floor(TILE_H) - (72 + 8 + 28 + 4 + 72)) / 2))

			-- Emoji sits under the painted icon and only shows if the art is missing or fails to load.
			local emoji = Instance.new("TextLabel")
			emoji.Size = UDim2.new(0, 72, 0, 72)
			emoji.Position = UDim2.new(0.5, -36, 0, blockTop)
			emoji.BackgroundTransparency = 1
			emoji.Font = Enum.Font.GothamBold
			emoji.TextSize = 48
			emoji.Text = step.icon
			emoji.TextTransparency = 0
			emoji.TextStrokeTransparency = 1
			emoji.ZIndex = Z
			emoji.Visible = false
			emoji.Parent = tile

			local artId = ContentArt.getImageId("tutorial_icons", step.key)
			if artId then
				local img = Instance.new("ImageLabel")
				img.Size = UDim2.new(0, 72, 0, 72)
				img.Position = UDim2.new(0.5, -36, 0, blockTop)
				img.BackgroundTransparency = 1
				img.Image = artId
				img.ScaleType = Enum.ScaleType.Fit
				img.ZIndex = Z
				img.Parent = tile
				roundCorner(img, 10)
				task.spawn(function()
					-- Never gate on img.IsLoaded after PreloadAsync (reads false before first render).
					-- Only Failure/TimedOut (or 8s with no load) brings the emoji back; the art
					-- stays Visible so a late load still shows.
					local artOk = false
					local function showEmoji()
						emoji.Visible = true
						img.ImageTransparency = 1
					end
					img:GetPropertyChangedSignal("IsLoaded"):Connect(function()
						if img.IsLoaded then
							artOk = true
							emoji.Visible = false
							img.ImageTransparency = 0
						end
					end)
					task.delay(8, function()
						if img.Parent and not artOk and not img.IsLoaded then showEmoji() end
					end)
					local ok = pcall(function()
						ContentProvider:PreloadAsync({ img }, function(_, status)
							if status == Enum.AssetFetchStatus.Success then
								artOk = true
								emoji.Visible = false
							elseif status == Enum.AssetFetchStatus.Failure or status == Enum.AssetFetchStatus.TimedOut then
								showEmoji()
							end
						end)
					end)
					if not ok then showEmoji() end
				end)
			else
				emoji.Visible = true
			end

			local titleLabel = Instance.new("TextLabel")
			titleLabel.Size = UDim2.new(1, -16, 0, 28)
			titleLabel.Position = UDim2.new(0, 8, 0, blockTop + 80)
			titleLabel.BackgroundTransparency = 1
			titleLabel.Font = Enum.Font.GothamBold
			titleLabel.TextSize = 20
			titleLabel.TextColor3 = GOLD
			titleLabel.Text = step.title
			titleLabel.ZIndex = Z
			titleLabel.Parent = tile

			local captionLabel = Instance.new("TextLabel")
			captionLabel.Size = UDim2.new(1, -20, 0, 72)
			captionLabel.Position = UDim2.new(0, 10, 0, blockTop + 112)
			captionLabel.BackgroundTransparency = 1
			captionLabel.Font = Enum.Font.Gotham
			captionLabel.TextSize = 17
			captionLabel.TextColor3 = Color3.fromRGB(235, 225, 210)
			captionLabel.TextWrapped = true
			captionLabel.TextXAlignment = Enum.TextXAlignment.Center
			captionLabel.TextYAlignment = Enum.TextYAlignment.Top
			captionLabel.Text = step.text
			captionLabel.ZIndex = Z
			captionLabel.Parent = tile
		end

		-- ===== Page 2: Hand Rankings (two columns, strongest first) =====
		-- Examples come from HandEvaluator.Examples; chips x mult from Scoring.HandBase
		-- (level 0), so nothing here is hardcoded.
		local rankingsPage = makePage("RankingsPage")
		local order = HandEvaluator.HandOrder
		local COLS, ROWS = 2, math.ceil(#order / 2)
		local COL_W = (PANEL_W - 2 * PAD - GAP) / COLS
		local ROW_H = (BODY_H - (ROWS - 1) * 8) / ROWS
		local CARD_W, CARD_H, CARD_GAP = 40, 56, 3

		local function makeMiniCard(card, parent, layoutOrder)
			local label = Instance.new("TextLabel")
			label.Size = UDim2.new(0, CARD_W, 0, CARD_H)
			label.BackgroundColor3 = Color3.fromRGB(250, 245, 235)
			label.Font = Enum.Font.GothamBold
			label.TextSize = 16
			label.TextColor3 = RED_SUITS[card.suit] and Color3.fromRGB(180, 30, 30) or Color3.fromRGB(20, 20, 20)
			label.Text = string.format("%s\n%s", RANK_NAMES[card.rank] or tostring(card.rank), SUIT_SYMBOLS[card.suit] or "?")
			label.LayoutOrder = layoutOrder or 0
			label.ZIndex = Z
			label.Parent = parent
			roundCorner(label, 6)
			return label
		end

		for i = 1, #order do
			local name = order[#order + 1 - i] -- strongest first
			-- fill column by column: left column strongest, right column weakest
			local col, row = math.floor((i - 1) / ROWS), (i - 1) % ROWS
			local base = Scoring.HandBase[name]
			local spec = HandEvaluator.Examples and HandEvaluator.Examples[name]
			if base and spec then
				local rowFrame = Instance.new("Frame")
				rowFrame.Size = UDim2.new(0, math.floor(COL_W), 0, math.floor(ROW_H))
				rowFrame.Position = UDim2.new(0, math.floor(col * (COL_W + GAP)), 0, math.floor(row * (ROW_H + 8)))
				rowFrame.BackgroundColor3 = TILE_BG
				rowFrame.ZIndex = Z
				rowFrame.Parent = rankingsPage
				polishPanel(rowFrame, 10)

				local holder = Instance.new("Frame")
				local cardsW = CARD_W * #spec + CARD_GAP * (#spec - 1)
				holder.Size = UDim2.new(0, cardsW, 1, 0)
				holder.Position = UDim2.new(0, 8, 0, 0)
				holder.BackgroundTransparency = 1
				holder.ZIndex = Z
				holder.Parent = rowFrame
				local lay = Instance.new("UIListLayout")
				lay.FillDirection = Enum.FillDirection.Horizontal
				lay.VerticalAlignment = Enum.VerticalAlignment.Center
				lay.SortOrder = Enum.SortOrder.LayoutOrder
				lay.Padding = UDim.new(0, CARD_GAP)
				lay.Parent = holder
				for ci, c in ipairs(spec) do
					makeMiniCard({ rank = c[1], suit = c[2] }, holder, ci)
				end

				local info = Instance.new("TextLabel")
				info.Size = UDim2.new(1, -(cardsW + 24), 1, -4)
				info.Position = UDim2.new(0, cardsW + 16, 0, 2)
				info.BackgroundTransparency = 1
				info.Font = Enum.Font.GothamBold
				info.TextSize = 16
				info.TextWrapped = true
				info.TextXAlignment = Enum.TextXAlignment.Left
				info.TextColor3 = GOLD
				info.ZIndex = Z
				info.Text = string.format("%s\n%d x %d", name, math.floor(base.chips), math.floor(base.mult))
				info.Parent = rowFrame
			end
		end

		-- ===== Page 3: Keys (lines come from Engine/TableKeyMap so the hint and the key map never drift) =====
		local keysPage = makePage("KeysPage")
		do
			local tile = Instance.new("Frame")
			tile.Size = UDim2.fromScale(1, 1)
			tile.BackgroundColor3 = TILE_BG
			tile.ZIndex = Z
			tile.Parent = keysPage
			polishPanel(tile, 10)
			local hint = Instance.new("TextLabel")
			hint.Name = "KeysHint"
			hint.Size = UDim2.new(1, -40, 1, -40)
			hint.Position = UDim2.fromOffset(20, 20)
			hint.BackgroundTransparency = 1
			hint.Font = Enum.Font.Gotham
			hint.TextSize = 20
			hint.TextColor3 = Color3.fromRGB(235, 225, 210)
			hint.TextTransparency = 0
			hint.TextStrokeTransparency = 1
			hint.TextWrapped = true
			hint.TextXAlignment = Enum.TextXAlignment.Left
			hint.TextYAlignment = Enum.TextYAlignment.Top
			hint.Text = table.concat(require(ReplicatedStorage.Shared.Engine.TableKeyMap).hintLines(), "\n\n")
			hint.ZIndex = Z
			hint.Parent = tile
		end

		-- ===== Navigation =====
		local pages = {
			{ frame = basicsPage, title = "The Basics" },
			{ frame = rankingsPage, title = "Hand Rankings" },
			{ frame = keysPage, title = "Keyboard and Gamepad" },
		}
		local currentPage = 1

		local function makeNavButton(text, w)
			local b = Instance.new("TextButton")
			b.Size = UDim2.new(0, w, 0, 42)
			b.AnchorPoint = Vector2.new(0, 0)
			b.Font = Enum.Font.GothamBold
			b.TextSize = 18
			b.Text = text
			b.BackgroundColor3 = Color3.fromRGB(90, 60, 30)
			b.TextColor3 = CREAM
			b.ZIndex = Z
			b.Parent = howToPlayPanel
			polishButton(b, 10)
			addButtonHoverScale(b)
			return b
		end
		local navY = TITLE_H + BODY_H + 11
		local howToPlayBackButton = makeNavButton("Back", 130)
		howToPlayBackButton.Position = UDim2.new(0, PAD, 0, navY)
		local howToPlayCloseButton = makeNavButton("Next", 130) -- becomes "Got it" on the last page
		howToPlayCloseButton.Position = UDim2.new(1, -PAD - 130, 0, navY)

		-- "Replay tutorial" sits in the middle of the nav row on the last page.
		local replayButton = makeNavButton("Replay tutorial", 190)
		replayButton.Position = UDim2.new(1, -PAD - 130 - 12 - 190, 0, navY)
		replayButton.Visible = false
		replayButton.MouseButton1Click:Connect(function()
			playClickSfx()
			popOut(howToPlayBackdrop, howToPlayPanel)
			if replayTutorial then
				replayTutorial()
			end
		end)

		local pageIndicator = Instance.new("TextLabel")
		pageIndicator.Size = UDim2.new(0, 200, 0, 42)
		pageIndicator.Position = UDim2.new(0, 160, 0, navY) -- left of the Replay button (last page)
		pageIndicator.BackgroundTransparency = 1
		pageIndicator.Font = Enum.Font.Gotham
		pageIndicator.TextSize = 16
		pageIndicator.TextColor3 = Color3.fromRGB(235, 225, 210)
		pageIndicator.ZIndex = Z
		pageIndicator.Parent = howToPlayPanel

		showPage = function(n)
			currentPage = math.clamp(n, 1, #pages)
			for i, p in ipairs(pages) do
				p.frame.Visible = (i == currentPage)
			end
			howToPlayTitle.Text = pages[currentPage].title
			pageIndicator.Text = string.format("Page %d of %d", currentPage, #pages)
			howToPlayBackButton.Visible = currentPage > 1
			replayButton.Visible = (currentPage == #pages) and replayTutorial ~= nil
			howToPlayCloseButton.Text = (currentPage == #pages) and "Got it" or "Next"
		end
		showPage(1)

		howToPlayBackButton.MouseButton1Click:Connect(function()
			playClickSfx()
			showPage(currentPage - 1)
		end)
		howToPlayCloseButton.MouseButton1Click:Connect(function()
			playClickSfx()
			if currentPage < #pages then
				showPage(currentPage + 1)
			else
				popOut(howToPlayBackdrop, howToPlayPanel)
			end
		end)
	end


	OverlayManager.register("howToPlay", function()
		popOut(howToPlayBackdrop, howToPlayPanel)
	end)
	-- Escape and a click on the dark area close it at any page (Client/PopupDismiss).
	require(script.Parent.PopupDismiss).attach(howToPlayBackdrop, { id = "howToPlay", panel = howToPlayPanel, button = true })

	-- Hide the dark menu title/shadow/ribbon while How to Play is open (they bled through above the panel).
	local menuRoot = menuHowToPlayButton:FindFirstAncestor("MenuRoot")
	howToPlayBackdrop:GetPropertyChangedSignal("Visible"):Connect(function()
		if not menuRoot then return end
		for _, n in ipairs({ "MenuTitle", "MenuTitleShadow", "MenuRibbon" }) do
			local o = menuRoot:FindFirstChild(n)
			if o then o.Visible = not howToPlayBackdrop.Visible end
		end
	end)

	local function openHowToPlay()
		playClickSfx()
		OverlayManager.closeAllExcept("howToPlay")
		build()
		showPage(1)
		popIn(howToPlayBackdrop, howToPlayPanel)
	end

	menuHowToPlayButton.MouseButton1Click:Connect(openHowToPlay)
	helpButton.MouseButton1Click:Connect(openHowToPlay)
	OverlayManager.registerOpener("howToPlay", openHowToPlay) -- the gear menu's How to play row

	return {}
end
