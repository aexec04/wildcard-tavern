--[[
	Client/Shop.lua
	The Shop overlay (full-screen tabbed menu: Shop / My Patrons / My
	Recipes) -- extracted out of init.client.lua on its own, since it's the
	single most self-contained UI system in the client and the one we
	understand best right now.

	PHASE 1C (shop randomization): the shop used to be "3 static Patron
	offers" plus a separate always-buyable full Recipes catalog. That
	undercut the whole point of a shop being exciting/random, and doesn't
	match the reference game (2 Joker offers, a Reroll button, an
	occasional Voucher, and Packs you buy to reveal-then-pick from instead
	of directly browsing every card). Now: the "Shop" tab shows 2 Patron
	offers + 2 Pack offers + an occasional Voucher offer + a Reroll button,
	all regenerated (except Reroll's escalating cost) each shop visit or
	Reroll. Recipes are ONLY obtainable via Packs now -- there's no more
	direct-buy Recipes catalog tab (BuyRecipeRemote/RunState.buyHouseRecipe
	etc still exist for direct engine use, just nothing in this UI calls
	them anymore). Buying a Pack opens a reveal panel (see the
	pendingPack/packPanel block below) where you pick which of the 3
	revealed items to keep, or Skip.

	Recipes that need target cards (and/or a suit, for Suit Swap) open a
	small in-panel picker instead of using immediately -- see the
	pendingUse/targetPanel block below. That's a SEPARATE panel from the
	Pack reveal panel (different job: picking hand cards vs. picking which
	revealed item to keep).

	This is a ModuleScript, not a LocalScript, so it has no access to
	init.client.lua's local variables -- everything it needs from the rest
	of the client is passed in explicitly via `deps` (see the field list
	below). It returns a small table of the pieces the rest of the client
	still needs to reach: the panel itself (for Visible toggling and theme
	tweening), the Next Round button (for its click handler and theme
	tweening, both wired in init.client.lua), and the rebuild functions
	(called from render() whenever the shop's contents need to refresh).

	deps fields:
		root              -- Frame, shopFrame's parent (the game's root UI frame)
		SIDEBAR_WIDTH      -- number, for the sidebar-aware horizontal layout
		polishPanel        -- function(instance, radius)
		polishButton       -- function(instance, radius)
		roundCorner        -- function(instance, radius)
		showWarning        -- function(text)
		showConfirmDialog  -- function(message, onConfirm)
		playClickSfx       -- function(volume?)
		playSfx            -- function(soundId, volume?, maxLength?)
		SOUND_IDS          -- table, for SOUND_IDS.buyPatron
		Patrons            -- the Shared/Engine/Patrons module (for Patrons.getById)
		Recipes            -- the Shared/Engine/Recipes module (HouseRecipes/
		                       MenuRecipes/SecretRecipes catalogs -- static
		                       content, same pattern as Patrons/Themes) --
		                       still needed for the My Recipes tab (looking
		                       up what a held recipe id actually does)
		BuyPatronRemote    -- RemoteEvent
		SellPatronRemote   -- RemoteEvent
		UseRecipeRemote    -- RemoteEvent (category, id, cardIndices?, suit?)
		RerollShopRemote   -- RemoteEvent ()
		BuyPackRemote      -- RemoteEvent (packId)
		ResolvePackRemote  -- RemoteEvent (chosenIds -- array of item ids, or {} to skip)
		BuyHousePassRemote -- RemoteEvent (passId)
		RANK_NAMES         -- table, [rank] = display string, for the card picker
		SUIT_SYMBOLS       -- table, [suit] = display glyph, for the card picker
		getLatestState     -- function() -> latest state table or nil (latestState
		                       is reassigned, not mutated, each render() call in
		                       init.client.lua, so this needs to be a live getter,
		                       not a value passed once at construction time)

	Returns:
		{
			shopFrame = Frame,
			nextRoundButton = TextButton,
			rebuildShop = function(state),
			rebuildMyPatronsTab = function(ownedPatrons),
			rebuildMyRecipesTab = function(state),
			closeTargetPanel = function(),
		}
]]

return function(deps)
	local root = deps.root
	local SIDEBAR_WIDTH = deps.SIDEBAR_WIDTH
	local polishPanel = deps.polishPanel
	local polishButton = deps.polishButton
	local roundCorner = deps.roundCorner
	local showWarning = deps.showWarning
	local showConfirmDialog = deps.showConfirmDialog
	local playClickSfx = deps.playClickSfx
	local playSfx = deps.playSfx
	local SOUND_IDS = deps.SOUND_IDS
	local Patrons = deps.Patrons
	local Recipes = deps.Recipes
	local BuyPatronRemote = deps.BuyPatronRemote
	local SellPatronRemote = deps.SellPatronRemote
	local UseRecipeRemote = deps.UseRecipeRemote
	local RerollShopRemote = deps.RerollShopRemote
	local BuyPackRemote = deps.BuyPackRemote
	local ResolvePackRemote = deps.ResolvePackRemote
	local BuyHousePassRemote = deps.BuyHousePassRemote
	local RANK_NAMES = deps.RANK_NAMES
	local SUIT_SYMBOLS = deps.SUIT_SYMBOLS
	local getLatestState = deps.getLatestState

	-- ----- Shop overlay -----
	-- A full-screen tabbed menu, not a small popup, on purpose: "Buy Patrons"
	-- is one tab among several, and "My Patrons"/"My Recipes" are where you
	-- manage/discard or use what you've already got -- important once the
	-- catalogs grow well past a handful.

	local shopFrame
	local nextRoundButton
	local shopBuyListFrame
	local shopMyPatronsListFrame
	local shopMyRecipesListFrame

	-- The card/suit target picker for Recipes that need one (e.g. Sugar
	-- Rush needs 1-2 cards, Suit Swap needs cards AND a suit). Built once
	-- here, shown/hidden and refreshed by openTargetPanel/refreshTargetPanel/
	-- closeTargetPanel below -- declared before the `do` block per this
	-- file's established "assign inside, read outside" pattern so the
	-- functions further down can reach them.
	local shopTargetPanel
	local targetTitleLabel
	local targetHintLabel
	local targetHandRow
	local targetSuitRow
	local targetConfirmButton
	local targetCancelButton

	-- The Pack reveal panel -- a SEPARATE picker from the one above (that
	-- one picks hand cards for a Recipe you already own; this one picks
	-- which of a Pack's 3 revealed items to keep). Sized to cover the
	-- WHOLE shop, including the Next Round button, since the server hard-
	-- blocks every other shop action (including AdvanceRound) while a pack
	-- is open -- see the "Reroll / Packs / House Passes" section of
	-- Server/init.server.lua.
	local shopPackPanel
	local packPanelTitleLabel
	local packPanelHintLabel
	local packItemsRow
	local packConfirmButton
	local packSkipButton

	do
		shopFrame = Instance.new("Frame")
		shopFrame.Name = "Shop"
		-- Same SIDEBAR_WIDTH-aware horizontal convention as messageLabel/
		-- bossBanner in init.client.lua, so the panel never sits under the
		-- fixed sidebar -- but full height (0 to 1, no top/bottom margin) so
		-- it fully covers the corner icon buttons (top) and the Play Hand/
		-- Discard bar (bottom) instead of leaving them peeking out above/
		-- below the panel.
		shopFrame.Size = UDim2.new(1, -(SIDEBAR_WIDTH + 40), 1, 0)
		shopFrame.Position = UDim2.new(0, SIDEBAR_WIDTH + 20, 0, 0)
		shopFrame.BackgroundColor3 = Color3.fromRGB(40, 30, 22)
		shopFrame.Visible = false
		-- ZIndex 6, not 5: the corner icon buttons (help/mute/settings/etc.) are
		-- ALSO ZIndex 5, and the panel now overlaps their corner -- it needs to
		-- strictly beat them, not just tie, to reliably cover them.
		shopFrame.ZIndex = 6
		shopFrame.Parent = root
		polishPanel(shopFrame, 16)

		-- Deliberately NOT calling addSoftShadow(shopFrame, ...) here.
		-- addSoftShadow sizes its shadow Frame using UDim2.new(1, 14, 1, 14) --
		-- scale 1 of the SHADOW'S OWN PARENT (root, i.e. the full screen), not
		-- of shopFrame itself. For most other panels in the client that's masked
		-- because their parent is a purpose-built backdrop already the same
		-- size as the panel (or the shadow's resulting ZIndex happens to match
		-- that backdrop's ZIndex, so the mismatch is invisible). shopFrame has
		-- no backdrop and is parented straight to root, so its shadow would be
		-- a screen-covering rectangle, not a thin border -- and once ZIndex = 5
		-- makes that shadow visible (needed to beat the sidebar), it reads as
		-- the whole screen going dark. Simplest correct fix: skip the shadow
		-- embellishment for this one panel rather than hand-deriving a shadow
		-- Size/Position that tracks shopFrame's own SIDEBAR_WIDTH-aware math.

		-- Every descendant below explicitly gets ZIndex = SHOP_ZINDEX, matching
		-- shopFrame itself. This mirrors the convention every OTHER elevated-
		-- ZIndex panel in the client already follows (howToPlayPanel/
		-- howToPlayTitle/... all share one ZIndex, themesPanel/themesTitle/...
		-- likewise, etc.) -- and it's required here: shopFrame's own children
		-- previously had no explicit ZIndex (defaulting to 1), and with
		-- shopFrame elevated to beat the sidebar, that mismatch was letting
		-- shopFrame's own background paint over its un-elevated children
		-- instead of showing them, which is what made the panel render as an
		-- empty rectangle the first time this bug was hit.
		local SHOP_ZINDEX = 6

		local shopTitle = Instance.new("TextLabel")
		shopTitle.Size = UDim2.new(1, 0, 0, 36)
		shopTitle.BackgroundTransparency = 1
		shopTitle.Font = Enum.Font.GothamBold
		shopTitle.TextSize = 22
		shopTitle.TextColor3 = Color3.fromRGB(250, 240, 220)
		shopTitle.Text = "The Bar -- spend your Tips"
		shopTitle.ZIndex = SHOP_ZINDEX
		shopTitle.Parent = shopFrame

		local shopTabBar = Instance.new("Frame")
		shopTabBar.Size = UDim2.new(1, -20, 0, 36)
		shopTabBar.Position = UDim2.new(0, 10, 0, 40)
		shopTabBar.BackgroundTransparency = 1
		shopTabBar.ZIndex = SHOP_ZINDEX
		shopTabBar.Parent = shopFrame

		local shopTabBarLayout = Instance.new("UIListLayout")
		shopTabBarLayout.FillDirection = Enum.FillDirection.Horizontal
		shopTabBarLayout.Padding = UDim.new(0, 8)
		shopTabBarLayout.Parent = shopTabBar

		local shopContentArea = Instance.new("Frame")
		shopContentArea.Size = UDim2.new(1, -20, 1, -140)
		shopContentArea.Position = UDim2.new(0, 10, 0, 84)
		shopContentArea.BackgroundTransparency = 1
		shopContentArea.ZIndex = SHOP_ZINDEX
		shopContentArea.Parent = shopFrame

		local function makeShopListTab()
			local tab = Instance.new("ScrollingFrame")
			tab.Size = UDim2.fromScale(1, 1)
			tab.BackgroundTransparency = 1
			tab.BorderSizePixel = 0
			tab.ScrollBarThickness = 8
			tab.AutomaticCanvasSize = Enum.AutomaticSize.Y
			tab.CanvasSize = UDim2.new(0, 0, 0, 0)
			tab.Visible = false
			tab.ZIndex = SHOP_ZINDEX
			tab.Parent = shopContentArea
			local layout = Instance.new("UIListLayout")
			layout.Padding = UDim.new(0, 8)
			layout.Parent = tab
			return tab
		end

		shopBuyListFrame = makeShopListTab()
		shopMyPatronsListFrame = makeShopListTab()
		shopMyRecipesListFrame = makeShopListTab()

		local shopTabContents = {
			buy = shopBuyListFrame,
			mypatrons = shopMyPatronsListFrame,
			myrecipes = shopMyRecipesListFrame,
		}

		local SHOP_TAB_DEFS = {
			{ key = "buy", label = "Shop" },
			{ key = "mypatrons", label = "My Patrons" },
			{ key = "myrecipes", label = "My Recipes" },
		}

		local shopTabButtons = {}

		local function setShopTab(key)
			for tabKey, frame in pairs(shopTabContents) do
				frame.Visible = (tabKey == key)
			end
			for _, entry in ipairs(shopTabButtons) do
				entry.button.BackgroundColor3 = (entry.key == key) and Color3.fromRGB(110, 85, 50) or Color3.fromRGB(60, 45, 32)
			end
		end

		for i, def in ipairs(SHOP_TAB_DEFS) do
			local tabButton = Instance.new("TextButton")
			tabButton.Size = UDim2.new(0, 150, 1, 0)
			tabButton.LayoutOrder = i
			tabButton.Font = Enum.Font.GothamBold
			tabButton.TextSize = 14
			tabButton.Text = def.label
			tabButton.BackgroundColor3 = Color3.fromRGB(60, 45, 32)
			tabButton.TextColor3 = Color3.fromRGB(230, 215, 195)
			tabButton.ZIndex = SHOP_ZINDEX
			tabButton.Parent = shopTabBar
			polishButton(tabButton, 8)
			table.insert(shopTabButtons, { key = def.key, button = tabButton })

			tabButton.MouseButton1Click:Connect(function()
				playClickSfx(0.4)
				setShopTab(def.key)
			end)
		end

		setShopTab("buy")

		nextRoundButton = Instance.new("TextButton")
		nextRoundButton.Size = UDim2.new(0, 200, 0, 40)
		nextRoundButton.Position = UDim2.new(0.5, -100, 1, -50)
		nextRoundButton.Font = Enum.Font.GothamBold
		nextRoundButton.TextSize = 18
		nextRoundButton.Text = "Next Round"
		nextRoundButton.BackgroundColor3 = Color3.fromRGB(90, 60, 30)
		nextRoundButton.TextColor3 = Color3.fromRGB(250, 240, 220)
		nextRoundButton.ZIndex = SHOP_ZINDEX
		nextRoundButton.Parent = shopFrame
		polishButton(nextRoundButton, 10)

		-- ----- Recipe target picker panel -----
		-- Sits directly on shopFrame (a sibling of the tab bar/content area,
		-- not inside any one tab) so it can cover the WHOLE shop -- including
		-- the tab bar, so you can't switch tabs mid-selection -- regardless of
		-- which tab was active when "Use" was clicked. ZIndex one above
		-- SHOP_ZINDEX so it wins.
		local PANEL_ZINDEX = SHOP_ZINDEX + 1

		shopTargetPanel = Instance.new("Frame")
		shopTargetPanel.Name = "TargetPanel"
		shopTargetPanel.Size = UDim2.new(1, -20, 1, -90)
		shopTargetPanel.Position = UDim2.new(0, 10, 0, 40)
		shopTargetPanel.BackgroundColor3 = Color3.fromRGB(30, 22, 16)
		shopTargetPanel.Visible = false
		shopTargetPanel.ZIndex = PANEL_ZINDEX
		shopTargetPanel.Parent = shopFrame
		polishPanel(shopTargetPanel, 12)

		targetTitleLabel = Instance.new("TextLabel")
		targetTitleLabel.Size = UDim2.new(1, -20, 0, 44)
		targetTitleLabel.Position = UDim2.new(0, 10, 0, 10)
		targetTitleLabel.BackgroundTransparency = 1
		targetTitleLabel.Font = Enum.Font.GothamBold
		targetTitleLabel.TextSize = 16
		targetTitleLabel.TextWrapped = true
		targetTitleLabel.TextXAlignment = Enum.TextXAlignment.Left
		targetTitleLabel.TextYAlignment = Enum.TextYAlignment.Top
		targetTitleLabel.TextColor3 = Color3.fromRGB(250, 240, 220)
		targetTitleLabel.Text = ""
		targetTitleLabel.ZIndex = PANEL_ZINDEX
		targetTitleLabel.Parent = shopTargetPanel

		targetHintLabel = Instance.new("TextLabel")
		targetHintLabel.Size = UDim2.new(1, -20, 0, 20)
		targetHintLabel.Position = UDim2.new(0, 10, 0, 58)
		targetHintLabel.BackgroundTransparency = 1
		targetHintLabel.Font = Enum.Font.Gotham
		targetHintLabel.TextSize = 13
		targetHintLabel.TextXAlignment = Enum.TextXAlignment.Left
		targetHintLabel.TextColor3 = Color3.fromRGB(190, 175, 155)
		targetHintLabel.Text = "Click cards below to select them."
		targetHintLabel.ZIndex = PANEL_ZINDEX
		targetHintLabel.Parent = shopTargetPanel

		targetHandRow = Instance.new("Frame")
		targetHandRow.Size = UDim2.new(1, -20, 0, 100)
		targetHandRow.Position = UDim2.new(0, 10, 0, 86)
		targetHandRow.BackgroundTransparency = 1
		targetHandRow.ZIndex = PANEL_ZINDEX
		targetHandRow.Parent = shopTargetPanel
		local targetHandLayout = Instance.new("UIListLayout")
		targetHandLayout.FillDirection = Enum.FillDirection.Horizontal
		targetHandLayout.Padding = UDim.new(0, 6)
		targetHandLayout.Parent = targetHandRow

		targetSuitRow = Instance.new("Frame")
		targetSuitRow.Size = UDim2.new(1, -20, 0, 40)
		targetSuitRow.Position = UDim2.new(0, 10, 0, 196)
		targetSuitRow.BackgroundTransparency = 1
		targetSuitRow.ZIndex = PANEL_ZINDEX
		targetSuitRow.Parent = shopTargetPanel
		local targetSuitLayout = Instance.new("UIListLayout")
		targetSuitLayout.FillDirection = Enum.FillDirection.Horizontal
		targetSuitLayout.Padding = UDim.new(0, 6)
		targetSuitLayout.Parent = targetSuitRow

		targetConfirmButton = Instance.new("TextButton")
		targetConfirmButton.Size = UDim2.new(0, 160, 0, 36)
		targetConfirmButton.Position = UDim2.new(1, -330, 1, -50)
		targetConfirmButton.Font = Enum.Font.GothamBold
		targetConfirmButton.TextSize = 14
		targetConfirmButton.Text = "Confirm"
		targetConfirmButton.BackgroundColor3 = Color3.fromRGB(90, 60, 30)
		targetConfirmButton.TextColor3 = Color3.fromRGB(250, 240, 220)
		targetConfirmButton.ZIndex = PANEL_ZINDEX
		targetConfirmButton.Parent = shopTargetPanel
		polishButton(targetConfirmButton, 8)

		targetCancelButton = Instance.new("TextButton")
		targetCancelButton.Size = UDim2.new(0, 150, 0, 36)
		targetCancelButton.Position = UDim2.new(1, -160, 1, -50)
		targetCancelButton.Font = Enum.Font.GothamBold
		targetCancelButton.TextSize = 14
		targetCancelButton.Text = "Cancel"
		targetCancelButton.BackgroundColor3 = Color3.fromRGB(70, 55, 45)
		targetCancelButton.TextColor3 = Color3.fromRGB(250, 240, 220)
		targetCancelButton.ZIndex = PANEL_ZINDEX
		targetCancelButton.Parent = shopTargetPanel
		polishButton(targetCancelButton, 8)

		-- ----- Pack reveal panel -----
		-- Bigger than the target picker above -- covers nearly the ENTIRE
		-- shopFrame (including the Next Round button's corner), since a Pack
		-- must be resolved (or skipped) before anything else in the shop is
		-- allowed, server-side.
		shopPackPanel = Instance.new("Frame")
		shopPackPanel.Name = "PackPanel"
		shopPackPanel.Size = UDim2.new(1, -20, 1, -20)
		shopPackPanel.Position = UDim2.new(0, 10, 0, 10)
		shopPackPanel.BackgroundColor3 = Color3.fromRGB(30, 22, 16)
		shopPackPanel.Visible = false
		shopPackPanel.ZIndex = PANEL_ZINDEX
		shopPackPanel.Parent = shopFrame
		polishPanel(shopPackPanel, 12)

		packPanelTitleLabel = Instance.new("TextLabel")
		packPanelTitleLabel.Size = UDim2.new(1, -20, 0, 30)
		packPanelTitleLabel.Position = UDim2.new(0, 10, 0, 14)
		packPanelTitleLabel.BackgroundTransparency = 1
		packPanelTitleLabel.Font = Enum.Font.GothamBold
		packPanelTitleLabel.TextSize = 20
		packPanelTitleLabel.TextXAlignment = Enum.TextXAlignment.Left
		packPanelTitleLabel.TextColor3 = Color3.fromRGB(250, 240, 220)
		packPanelTitleLabel.Text = ""
		packPanelTitleLabel.ZIndex = PANEL_ZINDEX
		packPanelTitleLabel.Parent = shopPackPanel

		packPanelHintLabel = Instance.new("TextLabel")
		packPanelHintLabel.Size = UDim2.new(1, -20, 0, 22)
		packPanelHintLabel.Position = UDim2.new(0, 10, 0, 46)
		packPanelHintLabel.BackgroundTransparency = 1
		packPanelHintLabel.Font = Enum.Font.Gotham
		packPanelHintLabel.TextSize = 14
		packPanelHintLabel.TextXAlignment = Enum.TextXAlignment.Left
		packPanelHintLabel.TextColor3 = Color3.fromRGB(190, 175, 155)
		packPanelHintLabel.Text = ""
		packPanelHintLabel.ZIndex = PANEL_ZINDEX
		packPanelHintLabel.Parent = shopPackPanel

		packItemsRow = Instance.new("Frame")
		packItemsRow.Size = UDim2.new(1, -20, 0, 150)
		packItemsRow.Position = UDim2.new(0, 10, 0, 78)
		packItemsRow.BackgroundTransparency = 1
		packItemsRow.ZIndex = PANEL_ZINDEX
		packItemsRow.Parent = shopPackPanel
		local packItemsLayout = Instance.new("UIListLayout")
		packItemsLayout.FillDirection = Enum.FillDirection.Horizontal
		packItemsLayout.Padding = UDim.new(0, 10)
		packItemsLayout.Parent = packItemsRow

		packConfirmButton = Instance.new("TextButton")
		packConfirmButton.Size = UDim2.new(0, 170, 0, 40)
		packConfirmButton.Position = UDim2.new(1, -350, 1, -56)
		packConfirmButton.Font = Enum.Font.GothamBold
		packConfirmButton.TextSize = 15
		packConfirmButton.Text = "Confirm"
		packConfirmButton.BackgroundColor3 = Color3.fromRGB(90, 60, 30)
		packConfirmButton.TextColor3 = Color3.fromRGB(250, 240, 220)
		packConfirmButton.ZIndex = PANEL_ZINDEX
		packConfirmButton.Parent = shopPackPanel
		polishButton(packConfirmButton, 8)

		packSkipButton = Instance.new("TextButton")
		packSkipButton.Size = UDim2.new(0, 160, 0, 40)
		packSkipButton.Position = UDim2.new(1, -170, 1, -56)
		packSkipButton.Font = Enum.Font.GothamBold
		packSkipButton.TextSize = 15
		packSkipButton.Text = "Skip Pack"
		packSkipButton.BackgroundColor3 = Color3.fromRGB(70, 55, 45)
		packSkipButton.TextColor3 = Color3.fromRGB(250, 240, 220)
		packSkipButton.ZIndex = PANEL_ZINDEX
		packSkipButton.Parent = shopPackPanel
		polishButton(packSkipButton, 8)
	end -- do (Shop overlay)

	-- A small colored badge with an icon (emoji glyph, not an uploaded image --
	-- see the TavernScene comment for why we don't guess catalog asset IDs)
	-- standing in for "a picture" for each Patron/Recipe until real art exists.
	-- ZIndex = 6 everywhere below matches SHOP_ZINDEX from the Shop overlay's
	-- construction block above (that local isn't in scope down here, so this
	-- repeats the literal -- see the comment there for why every descendant
	-- needs it explicitly rather than inheriting shopFrame's ZIndex). The
	-- target picker's own controls (built inside the do block, where
	-- PANEL_ZINDEX = 7 IS in scope) don't use this function.
	local function makePatronIconBadge(parent, icon)
		local badge = Instance.new("TextLabel")
		badge.Size = UDim2.new(0, 46, 0, 46)
		badge.Position = UDim2.new(0, 8, 0.5, -23)
		badge.BackgroundColor3 = Color3.fromRGB(45, 35, 25)
		badge.Font = Enum.Font.GothamBold
		badge.TextSize = 22
		badge.Text = icon or "🎴"
		badge.ZIndex = 6
		badge.Parent = parent
		roundCorner(badge, 10)
		return badge
	end

	-- ----- Recipe target picker state + logic -----
	-- pendingUse holds { category = "house"|"menu"|"secret", id, recipe }
	-- while the picker is open; nil otherwise. Recipes with no cardCount
	-- (Happy Hour, Menu Recipes, etc.) never go through this -- they use
	-- immediately via a plain confirm dialog instead (see rebuildMyRecipesTab).
	local pendingUse = nil
	local pendingSelected = {} -- [handIndex] = true
	local pendingSuit = nil

	local SUIT_ORDER = { "Hearts", "Diamonds", "Clubs", "Spades" }

	local function selectedCount()
		local n = 0
		for _ in pairs(pendingSelected) do
			n = n + 1
		end
		return n
	end

	local function closeTargetPanel()
		pendingUse = nil
		pendingSelected = {}
		pendingSuit = nil
		shopTargetPanel.Visible = false
	end

	local function refreshTargetPanel()
		if not pendingUse then
			return
		end
		local recipe = pendingUse.recipe

		for _, child in ipairs(targetHandRow:GetChildren()) do
			if child:IsA("TextButton") then
				child:Destroy()
			end
		end
		for _, child in ipairs(targetSuitRow:GetChildren()) do
			if child:IsA("TextButton") then
				child:Destroy()
			end
		end

		local latestState = getLatestState()
		local hand = (latestState and latestState.hand) or {}

		for index, card in ipairs(hand) do
			local cardButton = Instance.new("TextButton")
			cardButton.Size = UDim2.new(0, 56, 0, 78)
			cardButton.LayoutOrder = index
			cardButton.Font = Enum.Font.GothamBold
			cardButton.TextSize = 16
			cardButton.Text = string.format("%s\n%s", RANK_NAMES[card.rank] or tostring(card.rank), SUIT_SYMBOLS[card.suit] or "?")
			cardButton.TextColor3 = (card.suit == "Hearts" or card.suit == "Diamonds") and Color3.fromRGB(180, 30, 30) or Color3.fromRGB(20, 20, 20)
			cardButton.BackgroundColor3 = pendingSelected[index] and Color3.fromRGB(255, 214, 130) or Color3.fromRGB(235, 225, 205)
			cardButton.ZIndex = 7
			cardButton.Parent = targetHandRow
			roundCorner(cardButton, 6)

			cardButton.MouseButton1Click:Connect(function()
				if pendingSelected[index] then
					pendingSelected[index] = nil
				elseif selectedCount() >= recipe.cardCount.max then
					showWarning(string.format("You can only select up to %d card%s for this.", recipe.cardCount.max, recipe.cardCount.max == 1 and "" or "s"))
					return
				else
					pendingSelected[index] = true
				end
				playClickSfx(0.3)
				refreshTargetPanel()
			end)
		end

		targetSuitRow.Visible = recipe.needsSuit == true
		if recipe.needsSuit then
			for _, suit in ipairs(SUIT_ORDER) do
				local suitButton = Instance.new("TextButton")
				suitButton.Size = UDim2.new(0, 84, 0, 36)
				suitButton.Font = Enum.Font.GothamBold
				suitButton.TextSize = 14
				suitButton.Text = (SUIT_SYMBOLS[suit] or "") .. " " .. suit
				suitButton.TextColor3 = Color3.fromRGB(250, 240, 220)
				suitButton.BackgroundColor3 = (pendingSuit == suit) and Color3.fromRGB(255, 214, 130) or Color3.fromRGB(70, 55, 40)
				suitButton.ZIndex = 7
				suitButton.Parent = targetSuitRow
				polishButton(suitButton, 8)

				suitButton.MouseButton1Click:Connect(function()
					pendingSuit = suit
					playClickSfx(0.3)
					refreshTargetPanel()
				end)
			end
		end

		local count = selectedCount()
		local needSuitOk = (not recipe.needsSuit) or pendingSuit ~= nil
		local countOk = count >= recipe.cardCount.min and count <= recipe.cardCount.max
		local ready = countOk and needSuitOk

		local countText = (recipe.cardCount.min == recipe.cardCount.max)
			and tostring(recipe.cardCount.min)
			or string.format("%d-%d", recipe.cardCount.min, recipe.cardCount.max)

		targetTitleLabel.Text = string.format("%s -- %s", recipe.name, recipe.description)
		targetHintLabel.Text = string.format(
			"Select %s card%s%s (%d selected)",
			countText,
			recipe.cardCount.max == 1 and "" or "s",
			recipe.needsSuit and " and a suit" or "",
			count
		)

		targetConfirmButton.Text = ready and "Confirm" or "Select cards..."
		targetConfirmButton.BackgroundColor3 = ready and Color3.fromRGB(90, 60, 30) or Color3.fromRGB(70, 60, 55)
	end

	local function openTargetPanel(category, id, recipe)
		pendingUse = { category = category, id = id, recipe = recipe }
		pendingSelected = {}
		pendingSuit = nil
		shopTargetPanel.Visible = true
		refreshTargetPanel()
	end

	targetConfirmButton.MouseButton1Click:Connect(function()
		if not pendingUse then
			return
		end
		local recipe = pendingUse.recipe
		local indices = {}
		for index in pairs(pendingSelected) do
			table.insert(indices, index)
		end
		table.sort(indices)

		local count = #indices
		local countOk = count >= recipe.cardCount.min and count <= recipe.cardCount.max
		local needSuitOk = (not recipe.needsSuit) or pendingSuit ~= nil
		if not (countOk and needSuitOk) then
			showWarning("Finish making your selection first.")
			return
		end

		playSfx(SOUND_IDS.buyPatron)
		UseRecipeRemote:FireServer(pendingUse.category, pendingUse.id, indices, pendingSuit)
		closeTargetPanel()
	end)

	targetCancelButton.MouseButton1Click:Connect(function()
		playClickSfx(0.4)
		closeTargetPanel()
	end)

	-- ----- Recipes catalog (used by My Recipes to look up what a held id does) -----

	local RECIPE_CATEGORY_LIST = {
		{ key = "house", label = "House Recipes", catalog = Recipes.HouseRecipes },
		{ key = "menu", label = "Menu Recipes", catalog = Recipes.MenuRecipes },
		{ key = "secret", label = "Secret Recipes", catalog = Recipes.SecretRecipes },
	}

	local function findRecipeById(catalog, id)
		for _, recipe in ipairs(catalog) do
			if recipe.id == id then
				return recipe
			end
		end
		return nil
	end

	-- ----- Pack reveal panel state + logic -----
	-- `pendingPackSelected` is keyed by INDEX into state.pendingPack.items
	-- (not by id -- a pack can reveal the same id more than once, e.g. two
	-- copies of the same Menu Recipe, and each occurrence needs to be
	-- individually selectable). `packPanelWasOpen` is how refreshPackPanel
	-- tells "still showing the same reveal, keep the selection" apart from
	-- "a brand new reveal just arrived, clear the selection."
	local pendingPackSelected = {} -- [itemIndex] = true
	local packPanelWasOpen = false

	local function selectedPackCount()
		local n = 0
		for _ in pairs(pendingPackSelected) do
			n = n + 1
		end
		return n
	end

	local function refreshPackPanel(state)
		local pending = state and state.pendingPack
		if not pending then
			shopPackPanel.Visible = false
			pendingPackSelected = {}
			packPanelWasOpen = false
			return
		end

		if not packPanelWasOpen then
			pendingPackSelected = {}
		end
		packPanelWasOpen = true
		shopPackPanel.Visible = true

		for _, child in ipairs(packItemsRow:GetChildren()) do
			if child:IsA("TextButton") then
				child:Destroy()
			end
		end

		for index, item in ipairs(pending.items) do
			local itemButton = Instance.new("TextButton")
			itemButton.Size = UDim2.new(0, 160, 1, 0)
			itemButton.LayoutOrder = index
			itemButton.Font = Enum.Font.Gotham
			itemButton.TextSize = 13
			itemButton.TextWrapped = true
			itemButton.TextColor3 = Color3.fromRGB(250, 240, 220)
			itemButton.Text = string.format("%s\n%s\n\n%s", item.icon or "🎴", item.name, item.description)
			itemButton.BackgroundColor3 = pendingPackSelected[index] and Color3.fromRGB(110, 85, 50) or Color3.fromRGB(60, 45, 32)
			itemButton.ZIndex = 7
			itemButton.Parent = packItemsRow
			polishPanel(itemButton, 10)

			itemButton.MouseButton1Click:Connect(function()
				if pendingPackSelected[index] then
					pendingPackSelected[index] = nil
				elseif selectedPackCount() >= pending.pickCount then
					showWarning(string.format("You can only pick %d item%s from this pack.", pending.pickCount, pending.pickCount == 1 and "" or "s"))
					return
				else
					pendingPackSelected[index] = true
				end
				playClickSfx(0.3)
				refreshPackPanel(getLatestState())
			end)
		end

		local count = selectedPackCount()
		packPanelTitleLabel.Text = string.format("Pick %d of %d", pending.pickCount, #pending.items)
		packPanelHintLabel.Text = string.format("Click an item to select it (%d/%d picked), or Skip to take nothing.", count, pending.pickCount)
		packConfirmButton.BackgroundColor3 = (count == pending.pickCount) and Color3.fromRGB(90, 60, 30) or Color3.fromRGB(70, 60, 55)
	end

	packConfirmButton.MouseButton1Click:Connect(function()
		local state = getLatestState()
		local pending = state and state.pendingPack
		if not pending then
			return
		end
		local chosen = {}
		for index in pairs(pendingPackSelected) do
			table.insert(chosen, pending.items[index].id)
		end
		if #chosen ~= pending.pickCount then
			showWarning(string.format("Pick %d item%s first, or use Skip Pack.", pending.pickCount, pending.pickCount == 1 and "" or "s"))
			return
		end
		playSfx(SOUND_IDS.buyPatron)
		ResolvePackRemote:FireServer(chosen)
		pendingPackSelected = {}
	end)

	packSkipButton.MouseButton1Click:Connect(function()
		playClickSfx(0.4)
		ResolvePackRemote:FireServer({})
		pendingPackSelected = {}
	end)

	-- Shared row builder for the Shop tab's Patron/Pack/Voucher offers --
	-- they're all "icon badge + name/price/description + one action
	-- button" rows, just with a different icon lookup and click handler.
	local function addOfferRow(parent, icon, name, price, description, buttonText, buttonEnabled, onClick)
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, 0, 0, 64)
		row.BackgroundColor3 = Color3.fromRGB(60, 45, 32)
		row.ZIndex = 6
		row.Parent = parent
		polishPanel(row, 10)

		makePatronIconBadge(row, icon)

		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(1, -170, 1, -8)
		label.Position = UDim2.new(0, 64, 0, 4)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.Gotham
		label.TextSize = 14
		label.TextWrapped = true
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextColor3 = Color3.fromRGB(250, 240, 220)
		label.Text = string.format("%s (%d tips)\n%s", name, price, description)
		label.ZIndex = 6
		label.Parent = row

		local actionButton = Instance.new("TextButton")
		actionButton.Size = UDim2.new(0, 90, 0, 36)
		actionButton.Position = UDim2.new(1, -100, 0.5, -18)
		actionButton.Font = Enum.Font.GothamBold
		actionButton.TextSize = 15
		actionButton.Text = buttonEnabled and buttonText or "Full"
		actionButton.BackgroundColor3 = buttonEnabled and Color3.fromRGB(90, 60, 30) or Color3.fromRGB(70, 60, 55)
		actionButton.TextColor3 = buttonEnabled and Color3.fromRGB(250, 240, 220) or Color3.fromRGB(180, 170, 160)
		actionButton.ZIndex = 6
		actionButton.Parent = row
		polishButton(actionButton, 8)

		actionButton.MouseButton1Click:Connect(onClick)
		return row
	end

	local function addSectionHeader(parent, text)
		local header = Instance.new("TextLabel")
		header.Size = UDim2.new(1, 0, 0, 24)
		header.BackgroundTransparency = 1
		header.Font = Enum.Font.GothamBold
		header.TextSize = 15
		header.TextXAlignment = Enum.TextXAlignment.Left
		header.TextColor3 = Color3.fromRGB(255, 214, 130)
		header.Text = text
		header.ZIndex = 6
		header.Parent = parent
		return header
	end

	-- The whole Shop tab: Reroll button, then the occasional Voucher offer,
	-- then Patron offers, then Pack offers -- all regenerated by the server
	-- each shop visit (or Reroll), so this fully rebuilds every render()
	-- while the shop's open rather than trying to patch specific rows.
	local function rebuildShop(state)
		for _, child in ipairs(shopBuyListFrame:GetChildren()) do
			if child:IsA("Frame") or child:IsA("TextLabel") then
				child:Destroy()
			end
		end

		if not state then
			return
		end

		local ownedCount = (state.ownedPatrons and #state.ownedPatrons) or 0
		local slotLimit = state.patronSlotLimit or ownedCount
		local tableIsFull = ownedCount >= slotLimit

		-- ----- Reroll row -----
		local rerollRow = Instance.new("Frame")
		rerollRow.Size = UDim2.new(1, 0, 0, 44)
		rerollRow.BackgroundTransparency = 1
		rerollRow.ZIndex = 6
		rerollRow.Parent = shopBuyListFrame

		local rerollButton = Instance.new("TextButton")
		rerollButton.Size = UDim2.new(0, 170, 0, 36)
		rerollButton.Position = UDim2.new(0, 0, 0, 4)
		rerollButton.Font = Enum.Font.GothamBold
		rerollButton.TextSize = 14
		rerollButton.Text = string.format("Reroll (%d tips)", state.rerollCost or 0)
		rerollButton.BackgroundColor3 = Color3.fromRGB(70, 90, 60)
		rerollButton.TextColor3 = Color3.fromRGB(250, 240, 220)
		rerollButton.ZIndex = 6
		rerollButton.Parent = rerollRow
		polishButton(rerollButton, 8)

		local tableLabel = Instance.new("TextLabel")
		tableLabel.Size = UDim2.new(1, -190, 0, 36)
		tableLabel.Position = UDim2.new(0, 190, 0, 4)
		tableLabel.BackgroundTransparency = 1
		tableLabel.Font = Enum.Font.GothamBold
		tableLabel.TextSize = 14
		tableLabel.TextXAlignment = Enum.TextXAlignment.Left
		tableLabel.TextColor3 = Color3.fromRGB(255, 214, 130)
		tableLabel.Text = string.format("Your table: %d/%d Patrons%s", ownedCount, slotLimit,
			tableIsFull and " -- full! Sell one in My Patrons to make room." or "")
		tableLabel.ZIndex = 6
		tableLabel.Parent = rerollRow

		rerollButton.MouseButton1Click:Connect(function()
			local latestState = getLatestState()
			if not latestState or latestState.tips < (latestState.rerollCost or 0) then
				showWarning("Not enough tips to reroll.")
				playClickSfx()
				return
			end
			playClickSfx(0.4)
			RerollShopRemote:FireServer()
		end)

		-- ----- Voucher (House Pass) offer -- only shows up some visits -----
		if state.voucherOffer then
			addSectionHeader(shopBuyListFrame, "Voucher")
			local offer = state.voucherOffer
			addOfferRow(shopBuyListFrame, offer.icon, offer.name, offer.price, offer.description, "Buy", true, function()
				local latestState = getLatestState()
				if not latestState or latestState.tips < offer.price then
					showWarning("Not enough tips for that.")
					playClickSfx()
					return
				end
				playSfx(SOUND_IDS.buyPatron)
				BuyHousePassRemote:FireServer(offer.id)
			end)
		end

		-- ----- Patron offers -----
		addSectionHeader(shopBuyListFrame, "Patrons")
		if #(state.shopOffers or {}) == 0 then
			local emptyLabel = Instance.new("TextLabel")
			emptyLabel.Size = UDim2.new(1, 0, 0, 40)
			emptyLabel.BackgroundTransparency = 1
			emptyLabel.Font = Enum.Font.Gotham
			emptyLabel.TextSize = 14
			emptyLabel.TextWrapped = true
			emptyLabel.TextColor3 = Color3.fromRGB(190, 175, 155)
			emptyLabel.Text = "No new Patrons to offer this visit -- you've met everyone available so far!"
			emptyLabel.ZIndex = 6
			emptyLabel.Parent = shopBuyListFrame
		else
			for _, offer in ipairs(state.shopOffers) do
				local fullPatron = Patrons.getById(offer.id)
				addOfferRow(shopBuyListFrame, fullPatron and fullPatron.icon, offer.name, offer.price, offer.description,
					"Buy", not tableIsFull, function()
						local latestState = getLatestState()
						if not latestState or latestState.tips < offer.price then
							showWarning("Not enough tips for that.")
							playClickSfx()
							return
						end
						local liveOwnedCount = latestState.ownedPatrons and #latestState.ownedPatrons or 0
						if latestState.patronSlotLimit and liveOwnedCount >= latestState.patronSlotLimit then
							showWarning("Your table is full -- sell a Patron in the My Patrons tab to make room.")
							playClickSfx()
							return
						end
						playSfx(SOUND_IDS.buyPatron)
						BuyPatronRemote:FireServer(offer.id)
					end)
			end
		end

		-- ----- Pack offers -----
		addSectionHeader(shopBuyListFrame, "Packs")
		for _, pack in ipairs(state.packOffers or {}) do
			addOfferRow(shopBuyListFrame, pack.icon, pack.name, pack.price, pack.description, "Buy", true, function()
				local latestState = getLatestState()
				if not latestState or latestState.tips < pack.price then
					showWarning("Not enough tips for that.")
					playClickSfx()
					return
				end
				playSfx(SOUND_IDS.buyPatron)
				BuyPackRemote:FireServer(pack.id)
			end)
		end

		refreshPackPanel(state)
	end

	local function rebuildMyPatronsTab(ownedPatrons)
		for _, child in ipairs(shopMyPatronsListFrame:GetChildren()) do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end

		if #ownedPatrons == 0 then
			local emptyLabel = Instance.new("TextLabel")
			emptyLabel.Size = UDim2.new(1, 0, 0, 40)
			emptyLabel.BackgroundTransparency = 1
			emptyLabel.Font = Enum.Font.Gotham
			emptyLabel.TextSize = 14
			emptyLabel.TextWrapped = true
			emptyLabel.TextColor3 = Color3.fromRGB(190, 175, 155)
			emptyLabel.Text = "No Patrons yet -- buy some in the Shop tab!"
			emptyLabel.ZIndex = 6
			emptyLabel.Parent = shopMyPatronsListFrame
			return
		end

		for _, owned in ipairs(ownedPatrons) do
			local fullPatron = Patrons.getById(owned.id)
			local refund = fullPatron and math.floor(fullPatron.price / 2) or 0

			local row = Instance.new("Frame")
			row.Size = UDim2.new(1, 0, 0, 64)
			row.BackgroundColor3 = Color3.fromRGB(60, 45, 32)
			row.ZIndex = 6
			row.Parent = shopMyPatronsListFrame
			polishPanel(row, 10)

			makePatronIconBadge(row, fullPatron and fullPatron.icon)

			local label = Instance.new("TextLabel")
			label.Size = UDim2.new(1, -190, 1, -8)
			label.Position = UDim2.new(0, 64, 0, 4)
			label.BackgroundTransparency = 1
			label.Font = Enum.Font.Gotham
			label.TextSize = 14
			label.TextWrapped = true
			label.TextXAlignment = Enum.TextXAlignment.Left
			label.TextColor3 = Color3.fromRGB(250, 240, 220)
			label.Text = string.format("%s\n%s", owned.name, owned.description)
			label.ZIndex = 6
			label.Parent = row

			local discardButton = Instance.new("TextButton")
			discardButton.Size = UDim2.new(0, 110, 0, 36)
			discardButton.Position = UDim2.new(1, -120, 0.5, -18)
			discardButton.Font = Enum.Font.GothamBold
			discardButton.TextSize = 14
			discardButton.Text = "Discard"
			discardButton.BackgroundColor3 = Color3.fromRGB(110, 55, 45)
			discardButton.TextColor3 = Color3.fromRGB(250, 240, 220)
			discardButton.ZIndex = 6
			discardButton.Parent = row
			polishButton(discardButton, 8)

			discardButton.MouseButton1Click:Connect(function()
				playClickSfx(0.4)
				showConfirmDialog(
					string.format("Discard %s?\n\nYou'll get %d tips back. This can't be undone.", owned.name, refund),
					function()
						SellPatronRemote:FireServer(owned.id)
					end
				)
			end)
		end
	end

	local function rebuildMyRecipesTab(state)
		for _, child in ipairs(shopMyRecipesListFrame:GetChildren()) do
			if child:IsA("Frame") or child:IsA("TextLabel") then
				child:Destroy()
			end
		end

		local inventories = {
			house = (state and state.houseRecipeInventory) or {},
			menu = (state and state.menuRecipeInventory) or {},
			secret = (state and state.secretRecipeInventory) or {},
		}

		-- If the recipe we're mid-targeting is no longer in its inventory
		-- (used some other way than the picker's own Confirm button -- e.g. a
		-- fresh state push raced the picker), close the stale picker instead
		-- of leaving it open pointing at a recipe that's gone.
		if pendingUse then
			local stillOwned = false
			for _, ownedId in ipairs(inventories[pendingUse.category] or {}) do
				if ownedId == pendingUse.id then
					stillOwned = true
					break
				end
			end
			if not stillOwned then
				closeTargetPanel()
			end
		end

		local anyOwned = #inventories.house > 0 or #inventories.menu > 0 or #inventories.secret > 0
		if not anyOwned then
			local emptyLabel = Instance.new("TextLabel")
			emptyLabel.Size = UDim2.new(1, 0, 0, 40)
			emptyLabel.BackgroundTransparency = 1
			emptyLabel.Font = Enum.Font.Gotham
			emptyLabel.TextSize = 14
			emptyLabel.TextWrapped = true
			emptyLabel.TextColor3 = Color3.fromRGB(190, 175, 155)
			emptyLabel.Text = "No Recipes yet -- buy a Pack in the Shop tab and pick one!"
			emptyLabel.ZIndex = 6
			emptyLabel.Parent = shopMyRecipesListFrame
			return
		end

		for _, categoryDef in ipairs(RECIPE_CATEGORY_LIST) do
			local inventory = inventories[categoryDef.key]
			if #inventory > 0 then
				local header = Instance.new("TextLabel")
				header.Size = UDim2.new(1, 0, 0, 24)
				header.BackgroundTransparency = 1
				header.Font = Enum.Font.GothamBold
				header.TextSize = 15
				header.TextXAlignment = Enum.TextXAlignment.Left
				header.TextColor3 = Color3.fromRGB(255, 214, 130)
				header.Text = categoryDef.label
				header.ZIndex = 6
				header.Parent = shopMyRecipesListFrame

				for _, recipeId in ipairs(inventory) do
					local recipe = findRecipeById(categoryDef.catalog, recipeId)
					if recipe then
						local row = Instance.new("Frame")
						row.Size = UDim2.new(1, 0, 0, 64)
						row.BackgroundColor3 = Color3.fromRGB(60, 45, 32)
						row.ZIndex = 6
						row.Parent = shopMyRecipesListFrame
						polishPanel(row, 10)

						makePatronIconBadge(row, recipe.icon)

						local label = Instance.new("TextLabel")
						label.Size = UDim2.new(1, -170, 1, -8)
						label.Position = UDim2.new(0, 64, 0, 4)
						label.BackgroundTransparency = 1
						label.Font = Enum.Font.Gotham
						label.TextSize = 14
						label.TextWrapped = true
						label.TextXAlignment = Enum.TextXAlignment.Left
						label.TextColor3 = Color3.fromRGB(250, 240, 220)
						label.Text = string.format("%s\n%s", recipe.name, recipe.description)
						label.ZIndex = 6
						label.Parent = row

						local useButton = Instance.new("TextButton")
						useButton.Size = UDim2.new(0, 90, 0, 36)
						useButton.Position = UDim2.new(1, -100, 0.5, -18)
						useButton.Font = Enum.Font.GothamBold
						useButton.TextSize = 15
						useButton.Text = "Use"
						useButton.BackgroundColor3 = Color3.fromRGB(90, 60, 30)
						useButton.TextColor3 = Color3.fromRGB(250, 240, 220)
						useButton.ZIndex = 6
						useButton.Parent = row
						polishButton(useButton, 8)

						local categoryKey = categoryDef.key
						useButton.MouseButton1Click:Connect(function()
							if recipe.cardCount then
								playClickSfx(0.4)
								openTargetPanel(categoryKey, recipe.id, recipe)
							else
								playClickSfx(0.4)
								showConfirmDialog(
									string.format("Use %s?\n\n%s", recipe.name, recipe.description),
									function()
										playSfx(SOUND_IDS.buyPatron)
										UseRecipeRemote:FireServer(categoryKey, recipe.id)
									end
								)
							end
						end)
					end
				end
			end
		end
	end

	return {
		shopFrame = shopFrame,
		nextRoundButton = nextRoundButton,
		rebuildShop = rebuildShop,
		rebuildMyPatronsTab = rebuildMyPatronsTab,
		rebuildMyRecipesTab = rebuildMyRecipesTab,
		closeTargetPanel = closeTargetPanel,
	}
end
