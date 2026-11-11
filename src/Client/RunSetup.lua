--[[
	Client/RunSetup.lua
	FEATURE 8: pick a Deck Variant + Difficulty before a new run begins,
	reachable from the main menu's "New Run..." button.

	Extracted out of init.client.lua as part of splitting the client script
	into smaller, per-feature files. Fully self-contained -- nothing outside
	this module needs anything it builds, so it returns an empty table.

	deps fields:
		screenGui         -- ScreenGui, the panel's ultimate parent (via backdrop)
		root              -- Frame, the main gameplay root (shown once a run starts)
		menuFrame         -- Frame, the main menu (hidden once a run starts)
		polishPanel        -- function(instance, radius)
		polishButton       -- function(instance, radius)
		roundCorner        -- function(instance, radius)
		addSoftShadow      -- function(instance, radius)
		playClickSfx       -- function(volume?)
		playSfx            -- function(soundId, volume?, maxLength?)
		SOUND_IDS          -- table, for SOUND_IDS.buyPatron
		DeckVariants       -- the Shared/Engine/DeckVariants module
		DifficultyTiers    -- the Shared/Engine/DifficultyTiers module
		StartRunRemote     -- RemoteEvent
		backgroundMusic    -- Sound instance, started once a run begins
		menuNewRunButton   -- TextButton, "New Run..." on the main menu
		popIn              -- function(backdrop, content, opts?)
		popOut             -- function(backdrop, content, opts?, onHidden?)
		addButtonHoverScale -- function(button, opts?)
		revealStagger      -- function(instances, opts?)

	Returns: {}

	POLISH PASS (Batch 3): popIn/popOut replace the old bare
	Visible = true/false cut on open/Cancel; Begin Run now fires the same
	popOut (with an onHidden callback doing the actual menu->game handoff,
	instead of cutting straight to it), so both exits from this screen look
	the same. Begin Run/Cancel and every Deck Variant/Difficulty pick card
	get addButtonHoverScale. The pick cards also cascade in with
	revealStagger -- but ONLY on the initial open (see the `reveal` param on
	refreshRunSetupCards below), never on a plain reselect: that function
	also runs on every card click (to redraw the new checkmark/highlight),
	and re-staggering all 7 cards in on every single click would read as
	flickery noise rather than useful feedback -- the exact same
	over-triggering trap Shop.lua's offer-row signature-gating (Batch 2)
	was built to avoid.
]]

return function(deps)
	local ArtIcon = require(script.Parent.ArtIcon) -- painted icons for stake / challenge / Boss Rush cards, emoji when no id
	local screenGui = deps.screenGui
	local root = deps.root
	local menuFrame = deps.menuFrame
	local polishPanel = deps.polishPanel
	local polishButton = deps.polishButton
	local roundCorner = deps.roundCorner
	local addSoftShadow = deps.addSoftShadow
	local playClickSfx = deps.playClickSfx
	local playSfx = deps.playSfx
	local SOUND_IDS = deps.SOUND_IDS
	local DeckVariants = deps.DeckVariants
	local DifficultyTiers = deps.DifficultyTiers
	local StartRunRemote = deps.StartRunRemote
	local backgroundMusic = deps.backgroundMusic
	local menuNewRunButton = deps.menuNewRunButton
	local popIn = deps.popIn
	local popOut = deps.popOut
	local addButtonHoverScale = deps.addButtonHoverScale
	local revealStagger = deps.revealStagger
	-- PHASE A (Spectacle pass): optional -- see Client/RunRecap.lua's own
	-- header for why "Begin Run" needs to reset that run-scoped tracker
	-- too, not just the gameover->playing transition render() handles.
	local onBeginRun = deps.onBeginRun

	local runSetupBackdrop = Instance.new("Frame")
	runSetupBackdrop.Name = "RunSetupBackdrop"
	runSetupBackdrop.Size = UDim2.fromScale(1, 1)
	runSetupBackdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	runSetupBackdrop.BackgroundTransparency = 0.4
	runSetupBackdrop.Visible = false
	runSetupBackdrop.ZIndex = 25 -- above the in-game overlays; it's reachable from the menu too
	runSetupBackdrop.Parent = screenGui
	require(script.Parent.MenuTitleHider).bind(screenGui, runSetupBackdrop)

	local runSetupPanel = Instance.new("Frame")
	runSetupPanel.Size = UDim2.fromScale(0.6, 0.72)
	runSetupPanel.Position = UDim2.fromScale(0.2, 0.13)
	runSetupPanel.BackgroundColor3 = Color3.fromRGB(40, 30, 22)
	runSetupPanel.ZIndex = 26
	runSetupPanel.Parent = runSetupBackdrop
	polishPanel(runSetupPanel, 16, "wood")
	-- Painted background (PanelArt): flat panel color if the art id is missing.
	local runSetupPanelArt = require(script.Parent.PanelArt).add(runSetupPanel, {
		key = "run_setup_bg", scrim = { position = UDim2.fromScale(0, 0), size = UDim2.fromScale(1, 1) },
		-- BackgroundTransparency 0.2 would be an 80% black layer (the old near-black panel);
		-- 0.65 keeps the room art visible and the parchment cards carry the text.
		scrimTransparency = 0.65,
	})
	if runSetupPanelArt then
		runSetupPanel.BackgroundTransparency = 1 -- art is the lowest layer, no opaque fill under it
	end
	addSoftShadow(runSetupPanel, 18)

	local runSetupTitle = Instance.new("TextLabel")
	runSetupTitle.Size = UDim2.new(1, 0, 0, 40)
	runSetupTitle.BackgroundTransparency = 1
	runSetupTitle.Font = Enum.Font.GothamBold
	runSetupTitle.TextSize = 22
	runSetupTitle.TextColor3 = Color3.fromRGB(250, 240, 220)
	runSetupTitle.Text = "Start a New Run"
	runSetupTitle.ZIndex = 26
	runSetupTitle.Parent = runSetupPanel

	local GOLD = Color3.fromRGB(222, 182, 104)
	local INK = Color3.fromRGB(60, 40, 22)
	-- LayoutOrder bands: each header must sort directly before its own cards.
	-- (The old Difficulty header used order 19, below Deck Variant cards numbered 3+,
	-- so with more than 16 variants the header landed in the wrong place.)
	local DECK_HEADER_ORDER, DECK_CARD_BASE = 1, 1
	local DIFF_HEADER_ORDER, DIFF_CARD_BASE = 1000, 1000

	local runSetupScroll = Instance.new("ScrollingFrame")
	runSetupScroll.Size = UDim2.new(1, -30, 1, -110)
	runSetupScroll.Position = UDim2.new(0, 15, 0, 45)
	runSetupScroll.BackgroundTransparency = 1
	runSetupScroll.BorderSizePixel = 0
	runSetupScroll.ScrollBarThickness = 8
	runSetupScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	runSetupScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	runSetupScroll.ZIndex = 26
	runSetupScroll.Parent = runSetupPanel

	local runSetupLayout = Instance.new("UIListLayout")
	runSetupLayout.SortOrder = Enum.SortOrder.LayoutOrder -- default is Name, which ignored the LayoutOrder bands
	runSetupLayout.Padding = UDim.new(0, 14)
	runSetupLayout.Parent = runSetupScroll

	-- accentColor: a whole colored bar (not just tinted text) so "which
	-- section am I in" is answerable at a glance while scrolling, even before
	-- reading the word -- Deck Variant is gold, Difficulty is crimson, and
	-- every card below carries a matching accent stripe (see makePickCard).
	local function makeRunSetupSectionLabel(text, icon, order, accentColor)
		-- Wood plaque (dark wood fill, gold stroke, cream text) like the sidebar header.
		local header = Instance.new("Frame")
		header.Size = UDim2.new(1, 0, 0, 36)
		header.BackgroundColor3 = Color3.fromRGB(86, 58, 34)
		header.LayoutOrder = order
		header.ZIndex = 26
		header.Parent = runSetupScroll
		roundCorner(header, 8)
		local headerStroke = Instance.new("UIStroke")
		headerStroke.Color = GOLD
		headerStroke.Thickness = 2
		headerStroke.Parent = header

		local stripe = Instance.new("Frame")
		stripe.Size = UDim2.new(0, 4, 1, -12)
		stripe.Position = UDim2.new(0, 6, 0, 6)
		stripe.BackgroundColor3 = accentColor
		stripe.BorderSizePixel = 0
		stripe.ZIndex = 27
		stripe.Parent = header
		roundCorner(stripe, 2)

		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(1, -30, 1, 0)
		label.Position = UDim2.new(0, 20, 0, 0)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamBold
		label.TextSize = 18
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextColor3 = Color3.fromRGB(250, 235, 200)
		label.Text = text -- plain text: no emoji in headers
		label.ZIndex = 27
		label.Parent = header
		return header
	end

	local selectedDeckVariantId = DeckVariants.DefaultId
	local selectedDifficultyId = DifficultyTiers.DefaultId
	local deckVariantCards = {}
	local difficultyCards = {}

	-- Deck Variant = gold (matches the game's card-suit gold), Difficulty =
	-- crimson (danger/stakes read) -- reused for both the section headers
	-- above and the accent stripe on every card in that section below.
	local DECK_VARIANT_ACCENT = Color3.fromRGB(255, 200, 90)
	local DIFFICULTY_ACCENT = Color3.fromRGB(210, 70, 70)

	makeRunSetupSectionLabel("Deck Variant", "", DECK_HEADER_ORDER, DECK_VARIANT_ACCENT)
	makeRunSetupSectionLabel("Difficulty", "", DIFF_HEADER_ORDER, DIFFICULTY_ACCENT)

	-- STAKES (Engine/Stakes.lua): eight tiers, each adds one rule. Win a run on a stake to open the next.
	-- Painted tier icons come later (prompts.json stake_subjects); the emoji icon is the fallback today.
	local Stakes = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("Stakes"))
	local STAKE_HEADER_ORDER, STAKE_CARD_BASE = 2000, 2000
	local STAKE_ACCENT = Color3.fromRGB(230, 150, 60)
	local selectedStake = 1
	local stakeCards = {}
	makeRunSetupSectionLabel("Stakes", "", STAKE_HEADER_ORDER, STAKE_ACCENT)
	-- CHALLENGE RUNS and BOSS RUSH (Engine/Challenges.lua, BossRush.lua): optional extras after the stakes.
	local Engine = game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine")
	local Challenges = require(Engine:WaitForChild("Challenges"))
	local RunModes = require(Engine:WaitForChild("RunModes"))
	local CHALLENGE_HEADER_ORDER, CHALLENGE_CARD_BASE = 3000, 3000
	local RUSH_HEADER_ORDER, RUSH_CARD_BASE = 4000, 4000
	local CHALLENGE_ACCENT = Color3.fromRGB(150, 110, 210)
	local RUSH_ACCENT = Color3.fromRGB(220, 90, 70)
	local selectedChallengeId = nil -- nil = a normal run
	local selectedMode = nil -- "rush" = Boss Rush, "quick" = Quick Run (Engine/RunModes.lua)
	local challengeCards, rushCards = {}, {}
	makeRunSetupSectionLabel("Challenge", "", CHALLENGE_HEADER_ORDER, CHALLENGE_ACCENT)
	makeRunSetupSectionLabel("Special Modes", "", RUSH_HEADER_ORDER, RUSH_ACCENT)
	local function highestStake()
		local state = deps.getLatestState and deps.getLatestState()
		return Stakes.clamp(state and state.highestStakeUnlocked)
	end

	local function makePickCard(parent, order, name, description, isSelected, accentColor, locked, art)
		local card = Instance.new("Frame")
		-- Parchment card: ink text; selected = darker fill, gold 2px stroke, checkmark.
		-- `locked` (stakes not yet won): dimmed parchment, never clickable by the caller.
		card.Size = UDim2.new(1, 0, 0, 66)
		card.BackgroundColor3 = isSelected and Color3.fromRGB(196, 168, 118) or Color3.fromRGB(222, 198, 150)
		if locked then
			card.BackgroundColor3 = Color3.fromRGB(150, 134, 104)
		end
		card.LayoutOrder = order
		card.ZIndex = 26
		card.Parent = parent
		roundCorner(card, 10)
		local cardStroke = Instance.new("UIStroke")
		cardStroke.Color = isSelected and GOLD or INK
		cardStroke.Thickness = isSelected and 2 or 1.5
		cardStroke.Parent = card

		local stripe = Instance.new("Frame")
		stripe.Size = UDim2.new(0, 4, 1, -12)
		stripe.Position = UDim2.new(0, 0, 0, 6)
		stripe.BackgroundColor3 = accentColor
		stripe.BorderSizePixel = 0
		stripe.ZIndex = 27
		stripe.Parent = card
		roundCorner(stripe, 2)

		local nameLabel = Instance.new("TextLabel")
		nameLabel.Size = UDim2.new(1, -30, 0, 24)
		nameLabel.Position = UDim2.new(0, 16, 0, 4)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Font = Enum.Font.GothamBold
		nameLabel.TextSize = 17
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.TextColor3 = INK
		nameLabel.Text = (isSelected and "Chosen: " or "") .. name
		nameLabel.ZIndex = 26
		nameLabel.Parent = card

		local descLabel = Instance.new("TextLabel")
		descLabel.Size = UDim2.new(1, -30, 0, 34)
		descLabel.Position = UDim2.new(0, 16, 0, 28)
		descLabel.BackgroundTransparency = 1
		descLabel.Font = Enum.Font.Gotham
		descLabel.TextSize = 15
		descLabel.TextWrapped = true
		descLabel.TextXAlignment = Enum.TextXAlignment.Left
		descLabel.TextColor3 = locked and Color3.fromRGB(90, 70, 48) or INK
		descLabel.Text = description
		descLabel.ZIndex = 26
		descLabel.Parent = card

		-- Optional painted icon (art = { category, key }) at the right; text narrows to make room.
		-- No id yet: nothing changes (callers keep their emoji prefix in that case).
		if art and ArtIcon.has(art[1], art[2]) then
			nameLabel.Size = UDim2.new(1, -92, 0, 24)
			descLabel.Size = UDim2.new(1, -92, 0, 34)
			local well = Instance.new("Frame")
			well.Name = "ArtWell"
			well.Size = UDim2.fromOffset(50, 50)
			well.Position = UDim2.new(1, -60, 0.5, -25)
			well.BackgroundTransparency = 1
			well.ZIndex = 26
			well.Parent = card
			local img = ArtIcon.apply(well, art[1], art[2], nil, { zIndex = 27, cornerRadius = 8 })
			if img and locked then img.ImageColor3 = Color3.fromRGB(130, 130, 130) end -- dimmed, never black
		end

		local clickCatcher = Instance.new("TextButton")
		clickCatcher.Size = UDim2.fromScale(1, 1)
		clickCatcher.BackgroundTransparency = 1
		clickCatcher.Text = ""
		clickCatcher.ZIndex = 26
		clickCatcher.Parent = card
		addButtonHoverScale(clickCatcher, { hoverScale = 1.02, pressScale = 0.98 })

		return card, clickCatcher
	end

	-- `reveal`: only true when this is the panel's initial open (see
	-- openRunSetup below) -- see the header comment for why a plain
	-- reselect must NOT re-trigger the cascade.
	local function refreshRunSetupCards(reveal)
		local newlyBuiltCards = {}

		for _, child in ipairs(deckVariantCards) do
			child:Destroy()
		end
		deckVariantCards = {}
		for i, variant in ipairs(DeckVariants.Definitions) do
			local card, clickCatcher = makePickCard(runSetupScroll, DECK_CARD_BASE + i, variant.name, variant.description, variant.id == selectedDeckVariantId, DECK_VARIANT_ACCENT)
			table.insert(deckVariantCards, card)
			table.insert(newlyBuiltCards, card)
			clickCatcher.MouseButton1Click:Connect(function()
				playClickSfx(0.4)
				selectedDeckVariantId = variant.id
				refreshRunSetupCards()
			end)
		end

		for _, child in ipairs(difficultyCards) do
			child:Destroy()
		end
		difficultyCards = {}
		for i, tier in ipairs(DifficultyTiers.Definitions) do
			local card, clickCatcher = makePickCard(runSetupScroll, DIFF_CARD_BASE + i, tier.name, tier.description, tier.id == selectedDifficultyId, DIFFICULTY_ACCENT)
			table.insert(difficultyCards, card)
			table.insert(newlyBuiltCards, card)
			clickCatcher.MouseButton1Click:Connect(function()
				playClickSfx(0.4)
				selectedDifficultyId = tier.id
				refreshRunSetupCards()
			end)
		end

		for _, child in ipairs(stakeCards) do
			child:Destroy()
		end
		stakeCards = {}
		local open = highestStake()
		selectedStake = math.min(selectedStake, open)
		for n, def in ipairs(Stakes.Definitions) do
			local locked = n > open
			local text = locked and ("Locked. " .. Stakes.unlockHint(n)) or def.hint
			local card, clickCatcher = makePickCard(runSetupScroll, STAKE_CARD_BASE + n,
				(ArtIcon.has("stakes", def.id) and "" or (def.icon .. " ")) .. n .. ". " .. def.name, text, n == selectedStake, STAKE_ACCENT, locked, { "stakes", def.id })
			table.insert(stakeCards, card)
			table.insert(newlyBuiltCards, card)
			if locked then
				clickCatcher.Active = false
			else
				clickCatcher.MouseButton1Click:Connect(function()
					playClickSfx(0.4)
					selectedStake = n
					if selectedMode == "quick" then selectedMode = nil end -- Quick Run is always stake 1
					refreshRunSetupCards()
				end)
			end
		end

		-- Legend progress (Engine/Legend.lua): the prestige after stake 8, shown at the end of the stake list. Not selectable.
		do
			local legendState = deps.getLatestState and deps.getLatestState()
			local view = legendState and legendState.legend
			if view then
				local name = view.open and ("Legend level " .. view.level .. " of " .. view.max) or "Legend"
				local text = view.open and view.hint or "Clear stake 8 to become a Legend. Rewards are cosmetic."
				local legendCard, legendClick = makePickCard(runSetupScroll, STAKE_CARD_BASE + 20, name, text, false, Color3.fromRGB(255, 214, 100), not view.open, nil)
				legendClick.Active = false
				table.insert(stakeCards, legendCard)
				table.insert(newlyBuiltCards, legendCard)
			end
		end

		-- Challenge twists: None, then one card per twist (a check when already cleared). Picking one drops the Boss Rush.
		for _, child in ipairs(challengeCards) do
			child:Destroy()
		end
		challengeCards = {}
		local latest = deps.getLatestState and deps.getLatestState()
		local clearedSet = {}
		for _, row in ipairs(latest and latest.challenges or {}) do
			if row.cleared then clearedSet[row.id] = true end
		end
		local function addChallengeCard(order, id, name, text)
			local isSelected = selectedMode == nil and selectedChallengeId == id
			local card, clickCatcher = makePickCard(runSetupScroll, CHALLENGE_CARD_BASE + order, name, text, isSelected, CHALLENGE_ACCENT, false, id and { "challenges", id } or nil)
			table.insert(challengeCards, card)
			table.insert(newlyBuiltCards, card)
			clickCatcher.MouseButton1Click:Connect(function()
				playClickSfx(0.4)
				selectedChallengeId = id
				selectedMode = nil
				refreshRunSetupCards()
			end)
		end
		addChallengeCard(1, nil, "No twist", "A normal run.")
		for i, def in ipairs(Challenges.Definitions) do
			addChallengeCard(i + 1, def.id, (ArtIcon.has("challenges", def.id) and "" or (def.icon .. " ")) .. def.name .. (clearedSet[def.id] and "  (cleared)" or ""), def.text)
		end

		-- Boss Rush: locked until the first win; picking it drops the stake and the challenge.
		for _, child in ipairs(rushCards) do
			child:Destroy()
		end
		rushCards = {}
		local rush = latest and latest.bossRush or { unlocked = false, best = 0 }
		local rushText = rush.unlocked
			and ("Boss after boss with 3 Patrons you pick. No shop. Best: " .. tostring(math.floor(rush.best or 0)))
			or "Locked. Win a run first."
		local rushCard, rushClick = makePickCard(runSetupScroll, RUSH_CARD_BASE + 1, "Boss Rush", rushText, selectedMode == "rush", RUSH_ACCENT, not rush.unlocked, { "menu_icons", "boss_rush" })
		table.insert(rushCards, rushCard)
		table.insert(newlyBuiltCards, rushCard)
		if rush.unlocked then
			rushClick.MouseButton1Click:Connect(function()
				playClickSfx(0.4)
				selectedMode = (selectedMode == "rush") and nil or "rush"
				if selectedMode == "rush" then selectedChallengeId = nil end
				refreshRunSetupCards()
			end)
		else
			rushClick.Active = false
		end

		-- Quick Run (Engine/RunModes.lua): 4 Nights for short sessions. Always stake 1; picking it drops the stake,
		-- the challenge and the Boss Rush (the server enforces the same).
		local quickDef = RunModes.get("quick")
		local quickCard, quickClick = makePickCard(runSetupScroll, RUSH_CARD_BASE + 2,
			(ArtIcon.has("challenges", "quick_run") and "" or (quickDef.icon .. " ")) .. quickDef.name,
			quickDef.hint .. " Always stake 1. Half rewards.", selectedMode == "quick", RUSH_ACCENT, false, { "challenges", "quick_run" })
		table.insert(rushCards, quickCard)
		table.insert(newlyBuiltCards, quickCard)
		quickClick.MouseButton1Click:Connect(function()
			playClickSfx(0.4)
			selectedMode = (selectedMode == "quick") and nil or "quick"
			if selectedMode == "quick" then
				selectedChallengeId = nil
				selectedStake = 1
			end
			refreshRunSetupCards()
		end)

		if reveal then
			revealStagger(newlyBuiltCards, { stagger = 0.05, duration = 0.25, fromScale = 0.85 })
		end
	end

	refreshRunSetupCards()

	local runSetupBeginButton = Instance.new("TextButton")
	runSetupBeginButton.Size = UDim2.new(0, 200, 0, 44)
	runSetupBeginButton.Position = UDim2.new(0.5, -210, 1, -55)
	runSetupBeginButton.Font = Enum.Font.GothamBold
	runSetupBeginButton.TextSize = 18
	runSetupBeginButton.Text = "Begin Run"
	runSetupBeginButton.BackgroundColor3 = Color3.fromRGB(70, 110, 65)
	runSetupBeginButton.TextColor3 = Color3.fromRGB(250, 240, 220)
	runSetupBeginButton.ZIndex = 26
	runSetupBeginButton.Parent = runSetupPanel
	polishButton(runSetupBeginButton, 12)
	addButtonHoverScale(runSetupBeginButton)

	local runSetupCancelButton = Instance.new("TextButton")
	runSetupCancelButton.Size = UDim2.new(0, 140, 0, 44)
	runSetupCancelButton.Position = UDim2.new(0.5, 10, 1, -55)
	runSetupCancelButton.Font = Enum.Font.GothamBold
	runSetupCancelButton.TextSize = 16
	runSetupCancelButton.Text = "Cancel"
	runSetupCancelButton.BackgroundColor3 = Color3.fromRGB(90, 60, 30)
	runSetupCancelButton.TextColor3 = Color3.fromRGB(250, 240, 220)
	runSetupCancelButton.ZIndex = 26
	runSetupCancelButton.Parent = runSetupPanel
	polishButton(runSetupCancelButton, 12)
	addButtonHoverScale(runSetupCancelButton)

	runSetupCancelButton.MouseButton1Click:Connect(function()
		playClickSfx()
		popOut(runSetupBackdrop, runSetupPanel)
	end)
	-- Escape and a click on the dark area close it like Cancel (Client/PopupDismiss); nothing has started until Begin Run.
	require(script.Parent.PopupDismiss).attach(runSetupBackdrop, { panel = runSetupPanel, close = function() popOut(runSetupBackdrop, runSetupPanel) end, button = true })

	-- POLISH PASS (Batch 3) re-entrancy guard: popOut no longer hides the
	-- backdrop SYNCHRONOUSLY the way the old bare `Visible = false` cut
	-- did -- the panel stays fully visible and clickable for the whole
	-- fade-out duration (popOut's default 0.15s), so without this flag a
	-- double-click (or Cancel-then-Begin-Run within that same window)
	-- would run this whole handler twice: firing StartRunRemote twice and
	-- queuing the popOut/onHidden handoff twice. Reset the moment the
	-- panel opens again (see openRunSetup below), same "guard state that
	-- must be reset on next open" shape ConfirmDialog's pendingConfirmAction
	-- already uses for its own re-entrancy protection.
	local runStarting = false

	runSetupBeginButton.MouseButton1Click:Connect(function()
		if runStarting then
			return
		end
		runStarting = true
		playSfx(SOUND_IDS.buyPatron)
		if onBeginRun then
			onBeginRun()
		end
		StartRunRemote:FireServer(selectedDeckVariantId, selectedDifficultyId, selectedStake, selectedChallengeId, selectedMode)
		popOut(runSetupBackdrop, runSetupPanel, nil, function()
			menuFrame.Visible = false
			root.Visible = true
			if backgroundMusic.SoundId ~= "rbxassetid://0" and backgroundMusic.Volume > 0 then
				backgroundMusic:Play()
			end
		end)
	end)

	local function openRunSetup()
		runStarting = false
		playClickSfx()
		refreshRunSetupCards(true)
		popIn(runSetupBackdrop, runSetupPanel)
	end

	menuNewRunButton.MouseButton1Click:Connect(openRunSetup)

	return {}
end
