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
		                       content, same pattern as Patrons) --
		                       still needed for the My Recipes tab (looking
		                       up what a held recipe id actually does)
		HousePasses        -- the Shared/Engine/HousePasses module (static
		                       content, same pattern as Recipes/Patrons) --
		                       needed for the My Patrons tab's House Passes
		                       section (looking up a held pass id's name/
		                       icon/description)
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
		addButtonHoverScale -- function(button, opts?) -- POLISH PASS Batch 2
		revealStagger       -- function(instances, opts?) -- POLISH PASS Batch 2
		popScale            -- function(instance, fromScale?, duration?) -- POLISH PASS Batch 3
		shopBackgroundImage -- string, "rbxassetid://..." -- see Client/ArtAssets.lua

	AI ART: shopBackgroundImage is a wooden bar-backdrop illustration from
	the art brief, rendered as a plain background ImageLabel one ZIndex
	below every real piece of shop content (SHOP_ZINDEX below) -- currently
	still the "rbxassetid://0" placeholder, which Roblox just renders as no
	image, so shopFrame's own flat BackgroundColor3 shows through exactly
	as it always has until a real id is filled in.

	POLISH PASS (Batch 2): this is the single most-visited screen in the
	game and previously had ZERO animation of its own (every offer row,
	tab switch, and Buy click was a flat instant change). Two additions,
	both deliberately conservative given how much this file does and how
	often `rebuildShop` runs (see its own comment -- it fully rebuilds
	the whole offer list on EVERY render() while the Shop tab is open,
	not just when you open/reroll it):
	  1. Every Buy/Reroll/tab TextButton gets `addButtonHoverScale` for a
	     small hover/press bump -- safe to wire unconditionally since
	     each is a freshly created Instance every rebuild.
	  2. The offer ROWS themselves only get a staggered pop-in
	     (`revealStagger`) when the actual offer SET changed since the
	     last rebuild (a signature built from the Voucher/Patron/Pack
	     offer ids, cached in `lastShopOfferSignature`) -- NOT on every
	     single rebuild. Without that gate, buying one Patron would
	     re-trigger a pop-in on every OTHER still-unbought offer too
	     (rebuildShop tears down and rebuilds the whole list on that same
	     state push), which reads as flickery noise, not polish -- same
	     "only trust a change in a tracked key" rule the rest of this
	     project already uses (Journey.lua/RoundSelect.lua/GameOver.lua).

	POLISH PASS (Batch 3): `setShopTab` used to flip `frame.Visible`
	straight to true/false with no feedback at all -- the last raw cut
	flagged as a Batch 3 candidate. A true crossfade would need every tab's
	content wrapped in a CanvasGroup (Roblox has no way to fade a plain
	Frame's whole subtree at once), which is a bigger structural change
	than this pass's risk budget -- instead, the newly-shown tab now gets a
	`popScale` bump the moment it becomes visible, a lightweight "this just
	switched in" cue using a pattern already proven safe everywhere else in
	this file, without touching how any tab is actually built.

	Returns:
		{
			shopFrame = Frame,
			nextRoundButton = TextButton,
			rebuildShop = function(state),
			rebuildMyPatronsTab = function(state),
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
	local HousePasses = deps.HousePasses
	local BuyPatronRemote = deps.BuyPatronRemote
	local SellPatronRemote = deps.SellPatronRemote
	local UseRecipeRemote = deps.UseRecipeRemote
	local RerollShopRemote = deps.RerollShopRemote
	local BuyPackRemote = deps.BuyPackRemote
	-- TUTORIAL forced input: assigned once the walkthrough module exists (end of this file). Always true outside it.
	local tutorialAllows = function() return true end
	local tutorialReport = function() end -- tutorialReport(action): the walkthrough advances its step on a real action
	local ResolvePackRemote = deps.ResolvePackRemote
	local BuyHousePassRemote = deps.BuyHousePassRemote
	local RANK_NAMES = deps.RANK_NAMES
	local SUIT_SYMBOLS = deps.SUIT_SYMBOLS
	local getLatestState = deps.getLatestState
	local addButtonHoverScale = deps.addButtonHoverScale
	local revealStagger = deps.revealStagger
	local popScale = deps.popScale
	local shopBackgroundImage = deps.shopBackgroundImage
	-- INTERACTIVE TUTORIAL deps -- only used much further down, to build
	-- TutorialWalkthrough.lua (see the "===== TUTORIAL WALKTHROUGH" section
	-- near the bottom of this file for why it's required from in here).
	local tweenTo = deps.tweenTo
	local tutorialHandFrame = deps.handFrame
	local tutorialPlayButton = deps.playButton
	local tutorialDiscardButton = deps.discardButton
	local tutorialSidebarScoreBox = deps.sidebarScoreBox
	local tutorialSidebarTipsBox = deps.sidebarTipsBox
	local tutorialSidebarHandsDiscardsBox = deps.sidebarHandsDiscardsBox
	local tutorialSidebarPatronsBox = deps.sidebarPatronsBox
	local MarkTutorialSeenRemote = deps.MarkTutorialSeenRemote

	local PatronPlaqueModule = require(script.Parent.PatronPlaque)
	local Engine = game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine")
	local ShopRefusal = require(Engine:WaitForChild("ShopRefusal")) -- the words on Reroll and Haggle and every refusal's one line
	local ShopTrace = require(script.Parent.ShopTrace) -- Studio only: what the Reroll click did, step by step
	local ContentArt = require(Engine:WaitForChild("ContentArt"))
	local CollectionBook = require(Engine:WaitForChild("CollectionBook"))
	local RarityFrame = require(script.Parent.RarityFrame)
	local Packs = require(Engine:WaitForChild("Packs"))
	local ClientSettings = require(script.Parent.ClientSettings)
	local ShopCardsModule = require(script.Parent.ShopCards)
	-- Art-first item cards (Client/ShopCards.lua). Look only: remotes and rules stay in this file.
	local shopCards = ShopCardsModule.new({ playClickSfx = playClickSfx, particleBurst = deps.particleBurst, addTooltip = deps.addTooltip })
	-- Synergy tags (Engine/Synergy.lua): up to 2 small tags on a Patron card that fits what you own or play. Display only.
	-- Boss counter shield (Engine/BossCounters.lua): a small shield on an offer that helps against the Night's boss. Display only.
	local function shieldFor(def)
		local ok, shield = pcall(function()
			local st = getLatestState() or {}
			local scout = st.scout
			local boss = scout and require(Engine:WaitForChild("BossRounds")).getById(scout.id)
			return boss and def and require(Engine:WaitForChild("BossCounters")).shield(boss, def) or nil
		end)
		return ok and shield or nil
	end
	local function synergyTagsFor(patronId)
		local ok, tags = pcall(function()
			local Synergy = require(Engine:WaitForChild("Synergy"))
			local st = getLatestState() or {}
			return Synergy.tagsFor({ id = patronId }, Synergy.context(st.ownedPatrons, st.handStats))
		end)
		return ok and tags or nil
	end

	-- ----- Shop overlay -----
	-- A full-screen tabbed menu, not a small popup, on purpose: "Buy Patrons"
	-- is one tab among several, and "My Patrons"/"My Recipes" are where you
	-- manage/discard or use what you've already got -- important once the
	-- catalogs grow well past a handful.

	local shopFrame
	local shopScene -- ShopScene instance (nil if it failed to build)
	local shopBackdrop, shopStage -- Counter v2 painted scene and its stage director (nil until the art is recorded)
	local shopHaggle -- Haggle button, timing bar and Stranger card (Client/ShopHaggle.lua)
	local lastNoticeSeq -- the last server notice shown on the Counter (state.shopNotice.seq): each refusal is said once
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
	local packMakeRoom -- the "Make room" step (Client/PackMakeRoom): a pick that does not fit the table or the recipe box

	do
		shopFrame = Instance.new("Frame")
		shopFrame.Name = "Shop"
		-- Same SIDEBAR_WIDTH-aware horizontal convention as messageLabel
		-- in MessageBanner.lua, so the panel never sits under the
		-- fixed sidebar -- but full height (0 to 1, no top/bottom margin) so
		-- it fully covers the corner icon buttons (top) and the Play Hand/
		-- Discard bar (bottom) instead of leaving them peeking out above/
		-- below the panel.
		-- painted board: start 8 px right of the board (Engine/SidebarMetrics, one shared number), refit when it changes
		local SM = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("SidebarMetrics"))
		local function fitLeft()
			local vp = root.AbsoluteSize
			local left = SM.isPainted() and SM.contentLeft(vp.X, vp.Y) or (SIDEBAR_WIDTH + 20)
			-- the Counter is a full screen scene: the round sidebar slides away while it is open (hub, SidebarSlide)
			shopFrame.Size = UDim2.fromScale(1, 1)
			shopFrame.Position = UDim2.fromOffset(0, 0)
		end
		fitLeft()
		SM.onChange(fitLeft)
		root:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitLeft)
		shopFrame.BackgroundColor3 = Color3.fromRGB(40, 30, 22)
		shopFrame.Visible = false
		-- ZIndex 6, not 5: the corner icon buttons (help/mute/settings/etc.) are
		-- ALSO ZIndex 5, and the panel now overlaps their corner -- it needs to
		-- strictly beat them, not just tie, to reliably cover them.
		shopFrame.ZIndex = 6
		shopFrame.Parent = root
		polishPanel(shopFrame, 16, "wood")

		-- ART (placeholder-safe, see Client/ArtAssets.lua): the wooden bar
		-- backdrop illustration. ZIndex 5, one below every real shop child
		-- below (SHOP_ZINDEX = 6), so it always sits behind the title/tabs/
		-- offer rows regardless of creation order.
		local shopBackgroundArt = Instance.new("ImageLabel")
		shopBackgroundArt.Name = "ShopBackgroundArt"
		shopBackgroundArt.Size = UDim2.fromScale(1, 1)
		shopBackgroundArt.BackgroundTransparency = 1
		shopBackgroundArt.BorderSizePixel = 0
		shopBackgroundArt.ScaleType = Enum.ScaleType.Crop
		-- New counter art wins; the older shop_bg stays as the fallback.
		local counterArtId = ContentArt.getImageId("backgrounds", "shop_counter_bg")
		shopBackgroundArt.Image = counterArtId or shopBackgroundImage or "rbxassetid://0"
		shopBackgroundArt.Active = false
		shopBackgroundArt.ZIndex = 5
		shopBackgroundArt.Parent = shopFrame
		do
			local panelCorner = shopFrame:FindFirstChildOfClass("UICorner")
			local artCorner = Instance.new("UICorner")
			artCorner.CornerRadius = panelCorner and panelCorner.CornerRadius or UDim.new(0, 6)
			artCorner.Parent = shopBackgroundArt
			if counterArtId then
				-- Dark scrim behind the offer cards and prices (same box as shopContentArea).
				local shopScrim = Instance.new("Frame")
				shopScrim.Name = "ShopScrim"
				shopScrim.Position = UDim2.new(0, 10, 0, 84)
				shopScrim.Size = UDim2.new(1, -20, 1, -140)
				shopScrim.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
				shopScrim.BackgroundTransparency = 0.75 -- about a 0.25 dark scrim
				shopScrim.BorderSizePixel = 0
				shopScrim.Active = false
				shopScrim.ZIndex = 5
				shopScrim.Parent = shopFrame
				local scrimCorner = Instance.new("UICorner")
				scrimCorner.CornerRadius = UDim.new(0, 8)
				scrimCorner.Parent = shopScrim
			end
		end

		-- Counter v2 back layers (Client/ShopBackdrop.lua): painted wall, vignette, counter top and props. Mounts only once
		-- the shop_scene Image ids are recorded, so nothing changes before then. Look only.
		pcall(function()
			shopBackdrop = require(script.Parent.ShopBackdrop).new({ shopFrame = shopFrame })
		end)

		-- Peddler's Wagon dressing (Client/ShopScene.lua): counter strip, rail, Marlo and ambient motes. Look only.
		do
			local ok, built = pcall(function()
				return require(script.Parent.ShopScene).new({ shopFrame = shopFrame, getState = getLatestState, backdrop = shopBackdrop })
			end)
			shopScene = ok and built or nil
			local okH, haggle = pcall(function()
				return require(script.Parent.ShopHaggle).new({
					shopFrame = shopFrame, playClickSfx = playClickSfx, polishButton = polishButton,
					say = function(text) if shopScene then shopScene.sayText(text) end end,
					warn = showWarning, -- a refused click says why on the Counter as well as in Marlo's bubble
				})
			end)
			shopHaggle = okH and haggle or nil
		end

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

		-- Carved wood plaque: dark wood, gold rim, nail heads at both ends.
		local shopTitle = Instance.new("TextLabel")
		shopTitle.Name = "CounterPlaque"
		shopTitle.AnchorPoint = Vector2.new(0.5, 0)
		shopTitle.Size = UDim2.fromOffset(250, 36)
		shopTitle.Position = UDim2.new(0.5, 0, 0, 2)
		shopTitle.BackgroundColor3 = Color3.fromRGB(88, 60, 36)
		shopTitle.BorderSizePixel = 0
		shopTitle.Font = Enum.Font.GothamBold
		shopTitle.TextSize = 22
		shopTitle.TextColor3 = Color3.fromRGB(250, 235, 200)
		shopTitle.TextStrokeColor3 = Color3.fromRGB(40, 24, 12)
		shopTitle.TextStrokeTransparency = 1 -- crisp: one text, no stroke halo
		shopTitle.Text = "The Counter"
		shopTitle.ZIndex = SHOP_ZINDEX
		pcall(function() require(script.Parent.ConceptTSkin).title(shopTitle) end) -- serif cream with a dark outline
		shopTitle.Parent = shopFrame
		roundCorner(shopTitle, 8)
		do
			local rim = Instance.new("UIStroke")
			rim.Color = Color3.fromRGB(222, 182, 104)
			rim.Thickness = 2
			rim.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			rim.Parent = shopTitle
			for _, xScale in ipairs({ 0, 1 }) do
				local nail = Instance.new("Frame")
				nail.AnchorPoint = Vector2.new(0.5, 0.5)
				nail.Position = UDim2.new(xScale, xScale == 0 and 12 or -12, 0.5, 0)
				nail.Size = UDim2.fromOffset(8, 8)
				nail.BackgroundColor3 = Color3.fromRGB(222, 182, 104)
				nail.BorderSizePixel = 0
				nail.ZIndex = SHOP_ZINDEX
				nail.Parent = shopTitle
				roundCorner(nail, 4)
			end
		end

		local shopTabBar = Instance.new("Frame")
		shopTabBar.Size = UDim2.new(1, -20, 0, 44)
		shopTabBar.Position = UDim2.new(0, 10, 0, 40)
		shopTabBar.BackgroundTransparency = 1
		shopTabBar.ZIndex = SHOP_ZINDEX
		shopTabBar.Parent = shopFrame

		local shopTabBarLayout = Instance.new("UIListLayout")
		shopTabBarLayout.FillDirection = Enum.FillDirection.Horizontal
		-- SortOrder defaults to Enum.SortOrder.Name, NOT LayoutOrder -- every
		-- UIListLayout in this file explicitly sets it below. See the long
		-- comment above addSectionHeader for the bug this caused when it was missed.
		shopTabBarLayout.SortOrder = Enum.SortOrder.LayoutOrder
		shopTabBarLayout.Padding = UDim.new(0, 8)
		shopTabBarLayout.Parent = shopTabBar

		-- "Recipe box: n/m" chip on the same row as the tabs (filled in by rebuildMyRecipesTab)
		do
			local chip = Instance.new("TextLabel")
			chip.Name = "RecipeBoxChip"
			chip.AnchorPoint = Vector2.new(1, 0)
			chip.Size = UDim2.fromOffset(190, 30)
			chip.Position = UDim2.new(1, -14, 0, 43)
			chip.BackgroundColor3 = Color3.fromRGB(40, 28, 18)
			chip.BackgroundTransparency = 0.2
			chip.Font = Enum.Font.GothamBold
			chip.TextSize = 15
			chip.TextColor3 = Color3.fromRGB(255, 214, 130)
			chip.Text = ""
			chip.Visible = false
			chip.ZIndex = SHOP_ZINDEX
			chip.Parent = shopFrame
			roundCorner(chip, 8)
			local chipStroke = Instance.new("UIStroke")
			chipStroke.Color = Color3.fromRGB(222, 182, 104)
			chipStroke.Thickness = 1.5
			chipStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			chipStroke.Parent = chip
		end

		local shopContentArea = Instance.new("Frame")
		shopContentArea.Size = UDim2.new(1, -20, 1, -148) -- 84 top + 64 reserved footer (Next Round sits in it)
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
			layout.SortOrder = Enum.SortOrder.LayoutOrder
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
				local wasVisible = frame.Visible
				frame.Visible = (tabKey == key)
				if frame.Visible and not wasVisible then
					popScale(frame, 0.97, 0.16)
				end
			end
			local chipRef = shopFrame:FindFirstChild("RecipeBoxChip")
			if chipRef then chipRef.Visible = (key == "myrecipes") end
			if shopStage then shopStage.setTab(key) end
			for _, entry in ipairs(shopTabButtons) do
				local active = entry.key == key
				entry.button.BackgroundColor3 = active and Color3.fromRGB(128, 100, 58) or Color3.fromRGB(60, 45, 32)
				-- inactive: solid cream (about 235,222,190, well over 4.5:1 on the dark wood); active: gold on a lighter plate
				entry.button.TextColor3 = active and Color3.fromRGB(255, 214, 120) or Color3.fromRGB(235, 222, 190)
				entry.button.TextTransparency = 0
				entry.button.TextStrokeTransparency = 0.7
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
			addButtonHoverScale(tabButton)
			table.insert(shopTabButtons, { key = def.key, button = tabButton })

			-- TUTORIAL spotlight targets (cleared with the button when the Shop is rebuilt)
			local busNames = { buy = "shopTabBuy", mypatrons = "shopTabMyPatrons", myrecipes = "shopTabMyRecipes" }
			require(script.Parent.TutorialBus).register(busNames[def.key], tabButton)
			tabButton.MouseButton1Click:Connect(function()
				if not tutorialAllows("tab", { key = def.key }) then return end
				playClickSfx(0.4)
				setShopTab(def.key)
				tutorialReport("tab_" .. def.key)
			end)
		end

		setShopTab("buy")

		nextRoundButton = Instance.new("TextButton")
		nextRoundButton.Size = UDim2.new(0, 220, 0, 64)
		nextRoundButton.Position = UDim2.new(0.5, -110, 1, -76)
		nextRoundButton.Font = Enum.Font.GothamBold
		nextRoundButton.TextSize = 18
		nextRoundButton.Text = "Next Round"
		nextRoundButton.Name = "NextRound"
		nextRoundButton.BackgroundColor3 = Color3.fromRGB(118, 82, 48) -- wooden sign
		nextRoundButton.TextColor3 = Color3.fromRGB(250, 240, 220)
		nextRoundButton.ZIndex = SHOP_ZINDEX
		nextRoundButton:SetAttribute("FlatFace", true) -- the set's plate art has a baked mark at its left end
		nextRoundButton.Parent = shopFrame
		polishButton(nextRoundButton, 10)
		pcall(function() require(script.Parent.ConceptTSkin).plateButton(nextRoundButton) end) -- the one green plate style
		addButtonHoverScale(nextRoundButton)
		pcall(function() require(script.Parent.TavernScreens).apply(shopFrame, "counter") end) -- Gameplay v2 look: counter scene behind, green Next Round

		-- Counter v2 stage director (Client/ShopStage.lua): nil until the painted scene art is recorded.
		do
			local okStage, built = pcall(function()
				return require(script.Parent.ShopStage).new({
					shopFrame = shopFrame, buyList = shopBuyListFrame, contentArea = shopContentArea,
					tabBar = shopTabBar, plaque = shopTitle, nextRoundButton = nextRoundButton, backdrop = shopBackdrop,
					onLayout = function(r) if shopScene and shopScene.placeBubble then shopScene.placeBubble(r) end end,
				})
			end)
			shopStage = okStage and built or nil
		end

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
		polishPanel(shopTargetPanel, 12, "wood")

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
		targetHintLabel.TextSize = 14
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
		targetHandLayout.SortOrder = Enum.SortOrder.LayoutOrder
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
		targetSuitLayout.SortOrder = Enum.SortOrder.LayoutOrder
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
		shopPackPanel.BackgroundColor3 = Color3.fromRGB(16, 11, 8)
		shopPackPanel.BackgroundTransparency = 0.45 -- soft dim: the painted room and the oval table stay visible
		shopPackPanel.BorderSizePixel = 0
		shopPackPanel.Visible = false
		shopPackPanel.ZIndex = PANEL_ZINDEX
		shopPackPanel.Parent = shopFrame
		pcall(require(script.Parent.ModalStage).gateOnly, shopPackPanel) -- modal gate and click sink, no opaque stage

		local function packSign(name, size, pos, color, textColor, textSize, font)
			local l = Instance.new("TextLabel")
			l.Name = name
			l.AnchorPoint = Vector2.new(0.5, 0)
			l.Size = size
			l.Position = pos
			l.BackgroundColor3 = color
			l.BackgroundTransparency = 0
			l.Font = font
			l.TextSize = textSize
			l.TextColor3 = textColor
			l.Text = ""
			l.ZIndex = PANEL_ZINDEX
			l.Parent = shopPackPanel
			roundCorner(l, 8)
			local st = Instance.new("UIStroke")
			st.Color = Color3.fromRGB(150, 110, 52)
			st.Thickness = 2
			st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			st.Parent = l
			return l
		end
		-- "Pick 1 of 3": a small parchment sign top centre (dark ink on paper)
		packPanelTitleLabel = packSign("PackTitleSign", UDim2.fromOffset(220, 36), UDim2.new(0.5, 0, 0, 14),
			Color3.fromRGB(226, 208, 168), Color3.fromRGB(46, 32, 20), 20, Enum.Font.GothamBold)
		packPanelHintLabel = packSign("PackHintSign", UDim2.fromOffset(420, 24), UDim2.new(0.5, 0, 0, 56),
			Color3.fromRGB(30, 22, 16), Color3.fromRGB(240, 228, 200), 14, Enum.Font.Gotham)

		packItemsRow = Instance.new("Frame")
		packItemsRow.Name = "PackItemsRow"
		packItemsRow.Size = UDim2.new(1, -20, 0, 0)
		packItemsRow.AutomaticSize = Enum.AutomaticSize.Y -- grows with wrapped rows
		packItemsRow.Position = UDim2.new(0, 10, 0, 90)
		packItemsRow.BackgroundTransparency = 1
		packItemsRow.ZIndex = PANEL_ZINDEX
		packItemsRow.Parent = shopPackPanel
		local packItemsLayout = Instance.new("UIListLayout")
		packItemsLayout.FillDirection = Enum.FillDirection.Horizontal
		packItemsLayout.SortOrder = Enum.SortOrder.LayoutOrder
		packItemsLayout.Padding = UDim.new(0, 16)
		packItemsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		packItemsLayout.VerticalAlignment = Enum.VerticalAlignment.Top
		packItemsLayout.Wraps = true -- a second row on narrow screens (CardShape.pickLayout)
		packItemsLayout.Parent = packItemsRow

		-- Confirm and Skip Pack: two small wooden plates under the table, centred (same look as Haggle and Reroll)
		local function packPlate(name, text, x, color)
			local b = Instance.new("TextButton")
			b.Name = name
			b.AnchorPoint = Vector2.new(0.5, 0)
			b.Size = UDim2.fromOffset(150, 40)
			b.Position = UDim2.new(0.5, x, 1, -56)
			b.Font = Enum.Font.GothamBold
			b.TextSize = 16
			b.Text = text
			b.BackgroundColor3 = color
			b.TextColor3 = Color3.fromRGB(250, 240, 220)
			b.AutoButtonColor = true
			b.ZIndex = PANEL_ZINDEX + 1
			b.Parent = shopPackPanel
			polishButton(b, 8)
			local st = Instance.new("UIStroke")
			st.Color = Color3.fromRGB(150, 110, 52)
			st.Thickness = 2
			st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			st.Parent = b
			return b
		end
		packConfirmButton = packPlate("PackConfirm", "Confirm", -82, Color3.fromRGB(110, 72, 34))
		packSkipButton = packPlate("PackSkip", "Skip Pack", 102, Color3.fromRGB(70, 52, 40))
		packSkipButton.Size = UDim2.fromOffset(200, 40) -- room for "Skip Pack (+12 Tips)"
		packMakeRoom = require(script.Parent.PackMakeRoom).new({ parent = shopPackPanel, z = PANEL_ZINDEX + 12, playClick = playClickSfx, polishButton = polishButton })
	end -- do (Shop overlay)

	-- ----- Recipe target picker state + logic -----
	-- pendingUse holds { category = "house"|"menu"|"secret", id, recipe }
	-- while the picker is open; nil otherwise. Recipes with no cardCount
	-- (Tip Doubler, Menu Recipes, etc.) never go through this -- they use
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

		targetTitleLabel.Text = string.format("%s: %s", recipe.name, recipe.description)
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

		require(script.Parent.Cue).play("buy")
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
	local packBuiltSig, packCards = nil, {} -- the reveal the pick cards were built for, and the cards
	local PackPreviewModule = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("PackPreview"))
	local RANK_LABELS = { [11] = "J", [12] = "Q", [13] = "K", [14] = "A" }
	local SUIT_SYMBOLS_SHOP = { Hearts = "\226\153\165", Diamonds = "\226\153\166", Clubs = "\226\153\163", Spades = "\226\153\160" }
	local packPanelWasOpen = false
	local packReveal -- Client/PackRevealFX controller for the open pack

	local function selectedPackCount()
		local n = 0
		for _ in pairs(pendingPackSelected) do
			n = n + 1
		end
		return n
	end

	-- While the pack panel is open every other Counter piece (price tags, tooltip frame, Reroll, slots) is hidden;
	-- the marker attribute lets the close restore exactly what was hidden here.
	local function setCounterHiddenForPack(on)
		if on then -- Marlo's speech plate would sit on the pack screen's own hint line
			local plate = shopFrame:FindFirstChild("PeddlerBubble")
			if plate then plate.Visible = false end
		end
		for _, child in ipairs(shopFrame:GetChildren()) do
			if child:IsA("GuiObject") and child ~= shopPackPanel and child.Name ~= "ShopBackdrop" and child.Name ~= "PeddlerBubble" then
				if on then
					if child.Visible and not child:GetAttribute("PackHidden") then
						child:SetAttribute("PackHidden", true)
						child.Visible = false
					end
				elseif child:GetAttribute("PackHidden") then
					child:SetAttribute("PackHidden", nil)
					child.Visible = true
				end
			end
		end
	end

	local function refreshPackPanel(state)
		local pending = state and state.pendingPack
		setCounterHiddenForPack(pending ~= nil)
		if not pending then
			shopPackPanel.Visible = false
			pendingPackSelected = {}
			packPanelWasOpen = false
			packBuiltSig = nil
			if packReveal then packReveal.destroy() packReveal = nil end
			return
		end

		if not packPanelWasOpen then
			pendingPackSelected = {}
		end
		packPanelWasOpen = true
		shopPackPanel.Visible = true

		-- Large painted pick cards across the screen: art, name on a ribbon, the effect in the hover tooltip.
		-- The cards are built once per reveal; a click only updates which are marked.
		local sig = tostring(pending.packId)
		for _, item in ipairs(pending.items) do sig = sig .. "|" .. tostring(item.id) end
		if packBuiltSig ~= sig then
			packBuiltSig = sig
			for _, child in ipairs(packItemsRow:GetChildren()) do
				if not child:IsA("UIListLayout") then child:Destroy() end
			end
			packCards = {}
			-- Size the pick cards from the panel (as big as possible, wrapping to a second row if needed).
			do
				local cam = workspace.CurrentCamera
				local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
				local area = shopPackPanel.AbsoluteSize
				local pickScale = require(Engine:WaitForChild("CardShape")).pickLayout(
					area.X > 0 and area.X - 20 or (vp.X - 40), area.Y > 0 and area.Y or (vp.Y - 40), #pending.items, vp.X, vp.Y)
				ShopCardsModule.setScale(pickScale)
			end
			-- Cards are built at ShopCards' ZIndex 6, which is UNDER this panel's opaque background (ZIndex 7)
			-- in Global ZIndex mode: that is why the picks were invisible. Raise every card above the panel.
			local zDelta = shopPackPanel.ZIndex + 1 - 6
			for index, item in ipairs(pending.items) do
				local packArtCategory = (item.category == "patron" and "patrons")
					or ((item.category == "house" or item.category == "menu" or item.category == "secret") and "recipes")
					or nil
				local description = item.description
				local standardCard = item.category == "standard" and item.card or nil
				local match = standardCard and PackPreviewModule.matchFromDeckView((getLatestState() or {}).deckView, standardCard) or nil
				if standardCard then
					description = description .. "\n" .. PackPreviewModule.caption(match, standardCard)
				end
				local card = shopCards.card(packItemsRow, {
					synergy = packArtCategory == "patrons" and synergyTagsFor(item.id) or nil,
					shield = shieldFor(packArtCategory == "patrons" and Patrons.getById(item.id) or (function()
						local R = require(Engine:WaitForChild("Recipes"))
						return R.getHouseRecipeById(item.id) or R.getMenuRecipeById(item.id) or R.getSecretRecipeById(item.id)
					end)()),
					kind = "patron", layoutOrder = index, name = item.name, description = description, noAction = true, tipAlign = "below",
					emoji = item.icon, artTab = packArtCategory, artId = packArtCategory and item.id or nil,
					rarityTab = packArtCategory, rarityId = item.id, rarityWord = packArtCategory ~= nil, -- tier word on the card (patrons and recipes)
					rarity = standardCard and "common" or nil,
					onClick = function(c)
						if not tutorialAllows("packItem") then return end
						local pend = getLatestState() and getLatestState().pendingPack
						local limit = pend and pend.pickCount or 1
						if pendingPackSelected[index] then
							pendingPackSelected[index] = nil
						elseif selectedPackCount() >= limit then
							showWarning(string.format("You can only pick %d item%s from this pack.", limit, limit == 1 and "" or "s"))
							return
						else
							pendingPackSelected[index] = true
						end
						refreshPackPanel(getLatestState())
						if selectedPackCount() >= 1 then tutorialReport("pack_item") end
					end,
				})
				packCards[index] = card
				card.slot.Name = "Option_" .. tostring(item.id)
				local tiltWrap = card.slot:FindFirstChild("Tilt")
				if tiltWrap then -- cards lie on the table at the Counter's own angles
					local angle = require(Engine:WaitForChild("ShopSceneLayout")).cardTilt(index)
					tiltWrap.Rotation = angle
					card.slot:SetAttribute("Tilt", angle)
				end
				if packArtCategory and not ContentArt.getImageId(packArtCategory, item.id) then
					warn(string.format("[PackPick] no art for %s '%s' (emoji fallback shown)", tostring(item.category), tostring(item.id)))
				end
				if standardCard then
					-- a real card face (with its special pattern) instead of a picture
					local host = Instance.new("Frame")
					host.Name = "PickFace"
					host.AnchorPoint = Vector2.new(0.5, 0.5)
					host.Position = UDim2.fromScale(0.5, 0.5)
					host.Size = UDim2.fromScale(0.62, 0.92)
					host.BackgroundColor3 = Color3.fromRGB(246, 238, 220)
					host.BorderSizePixel = 0
					host.ZIndex = 7
					host.Parent = card.artClip
					local ar = Instance.new("UIAspectRatioConstraint")
					ar.AspectRatio = 1 / 1.45
					ar.Parent = host
					roundCorner(host, 8)
					require(script.Parent.CardFace).build(host, RANK_LABELS[standardCard.rank] or tostring(standardCard.rank),
						SUIT_SYMBOLS_SHOP[standardCard.suit] or "?", standardCard.suit == "Hearts" or standardCard.suit == "Diamonds", 8, false, standardCard)
					-- hover: the plain card of the same rank and suit that you already hold ghosts in beside it
					if match then
						local ghost
						card.hit.MouseEnter:Connect(function()
							if require(script.Parent.ModalStage).blocks(card.hit) then return end -- a modal is open: nothing behind it reacts
							if ghost then ghost:Destroy() end
							local slotPos = card.slot.AbsolutePosition - shopPackPanel.AbsolutePosition
							ghost = Instance.new("Frame")
							ghost.Name = "ReplacedGhost"
							ghost.Size = UDim2.fromOffset(64, 92)
							ghost.Position = UDim2.fromOffset(math.max(6, slotPos.X - 74), slotPos.Y + 70)
							ghost.BackgroundColor3 = Color3.fromRGB(246, 238, 220)
							ghost.BackgroundTransparency = 0.15
							ghost.BorderSizePixel = 0
							ghost.ZIndex = shopPackPanel.ZIndex + 5
							ghost.Parent = shopPackPanel
							roundCorner(ghost, 6)
							require(script.Parent.CardFace).build(ghost, RANK_LABELS[standardCard.rank] or tostring(standardCard.rank),
								SUIT_SYMBOLS_SHOP[standardCard.suit] or "?", standardCard.suit == "Hearts" or standardCard.suit == "Diamonds", shopPackPanel.ZIndex + 6, false, nil)
							local arrowLabel = Instance.new("TextLabel")
							arrowLabel.Size = UDim2.fromOffset(30, 92)
							arrowLabel.Position = UDim2.fromOffset(66, 0)
							arrowLabel.BackgroundTransparency = 1
							arrowLabel.Font = Enum.Font.GothamBlack
							arrowLabel.TextSize = 28
							arrowLabel.TextColor3 = Color3.fromRGB(255, 214, 130)
							arrowLabel.Text = ">"
							arrowLabel.ZIndex = shopPackPanel.ZIndex + 7
							arrowLabel.Parent = ghost
						end)
						card.hit.MouseLeave:Connect(function()
							if ghost then ghost:Destroy() ghost = nil end
						end)
					end
				end
				for _, d in ipairs(card.slot:GetDescendants()) do
					if d:IsA("GuiObject") then d.ZIndex = d.ZIndex + zDelta end
				end
				card.slot.ZIndex = card.slot.ZIndex + zDelta
			end
			-- the opening moment (Client/PackRevealFX): face down, tap to open, flips one at a time, Seat or Keep pill, Skip all
			if packReveal then packReveal.destroy() packReveal = nil end
			pcall(function()
				local CR = require(Engine:WaitForChild("ChoiceRarity"))
				local list, rarities = {}, {}
				for index, item in ipairs(pending.items) do
					list[index] = packCards[index]
					rarities[index] = CR.lookup(CR.tabFor(item.category), item.id) or (item.category == "standard" and "common" or nil)
				end
				packReveal = require(script.Parent.PackRevealFX).attach(shopPackPanel, packItemsRow, list, pending.items, rarities, {
					z = shopPackPanel.ZIndex + 20,
					isPicked = function(i) return pendingPackSelected[i] == true end,
					onPick = function(i) if packCards[i] then packCards[i].spec.onClick(packCards[i]) end end,
				})
			end)
		end
		if packReveal then packReveal.refresh() end
		for index, card in pairs(packCards) do
			card.setSelected(pendingPackSelected[index] == true)
			card.setPinned(pendingPackSelected[index] == true)
		end

		local count = selectedPackCount()
		packPanelTitleLabel.Text = string.format("Pick %d of %d", pending.pickCount, #pending.items)
		packPanelHintLabel.Text = string.format("Click an item to pick it (%d/%d), or Skip Pack.", count, pending.pickCount)
		packConfirmButton.BackgroundColor3 = (count == pending.pickCount) and Color3.fromRGB(90, 60, 30) or Color3.fromRGB(70, 60, 55)
		-- Skip Pack gives about half of what was paid back (Engine/Packs.skipRefund, applied by the server): the button says how much
		local refund = require(Engine:WaitForChild("Packs")).skipRefund(pending.paidPrice)
		packSkipButton.Text = refund > 0 and string.format("Skip Pack (+%d Tips)", refund) or "Skip Pack"
	end

	local function confirmPackPick()
		if not tutorialAllows("packConfirm") then return end
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
		-- a pick that does not fit the table (or the recipe box) is never silently lost: the Make room step asks which owned ones leave
		local PackRoom = require(Engine:WaitForChild("PackRoom"))
		local picked = {}
		for index in pairs(pendingPackSelected) do table.insert(picked, pending.items[index]) end
		table.sort(picked, function(a, b) return tostring(a.id) < tostring(b.id) end)
		local view = { ownedPatrons = {}, recipes = {}, patronLimit = state.patronSlotLimit or 0, recipeLimit = state.recipeSlotLimit or 0 }
		for _, o in ipairs(state.ownedPatrons or {}) do table.insert(view.ownedPatrons, o.id) end
		for _, inv in ipairs({ state.houseRecipeInventory or {}, state.menuRecipeInventory or {}, state.secretRecipeInventory or {} }) do
			for _, id in ipairs(inv) do table.insert(view.recipes, id) end
		end
		local over = PackRoom.overflow(view, picked)
		if (over.patrons > 0 or over.recipes > 0) and packMakeRoom then
			packMakeRoom.open(view, picked, function(replaceIds)
				require(script.Parent.Cue).play("buy")
				ResolvePackRemote:FireServer(chosen, replaceIds)
				pendingPackSelected = {}
				tutorialReport("pack_confirm")
			end)
			return
		end
		require(script.Parent.Cue).play("buy")
		ResolvePackRemote:FireServer(chosen)
		pendingPackSelected = {}
		tutorialReport("pack_confirm")
	end
	packConfirmButton.MouseButton1Click:Connect(confirmPackPick)

	packSkipButton.MouseButton1Click:Connect(function()
		if not tutorialAllows("packSkip") then return end -- never allowed in the tutorial
		playClickSfx(0.4)
		local pendingNow = getLatestState() and getLatestState().pendingPack
		local refund = pendingNow and require(Engine:WaitForChild("Packs")).skipRefund(pendingNow.paidPrice) or 0
		ResolvePackRemote:FireServer({})
		pendingPackSelected = {}
		if refund > 0 then
			-- the server pays it; this is only the words and the coin sound
			pcall(function() require(script.Parent.Cue).play("coin", 1.2) end)
			pcall(function() require(script.Parent.CornerToast).show({ id = "packRefund" .. tostring(os.clock()), text = string.format("%d Tips back", refund) }) end)
		end
	end)

	-- (The old text rows for offers were replaced by the art cards in Client/ShopCards.lua.)
	-- Every element parented into shopBuyListFrame, shopMyPatronsListFrame or shopMyRecipesListFrame
	-- must still get an explicit, sequential LayoutOrder: UIListLayout ties are broken by Name.
	local function addSectionHeader(parent, layoutOrder, text)
		-- full-width holder (hidden as one piece on the Shop tab) with a centred dark plate and cream text
		local header = Instance.new("Frame")
		header.Name = "SectionHeader"
		header.LayoutOrder = layoutOrder
		header.Size = UDim2.new(1, 0, 0, 30)
		header.BackgroundTransparency = 1
		header.ZIndex = 6
		header.Parent = parent
		local plate = Instance.new("TextLabel")
		plate.Name = "HeaderPlate"
		plate.AnchorPoint = Vector2.new(0.5, 0.5)
		plate.Position = UDim2.fromScale(0.5, 0.5)
		plate.AutomaticSize = Enum.AutomaticSize.X
		plate.Size = UDim2.fromOffset(0, 28)
		plate.BackgroundColor3 = Color3.fromRGB(26, 18, 12)
		plate.BackgroundTransparency = 0.1
		plate.BorderSizePixel = 0
		plate.Font = Enum.Font.GothamBold
		plate.TextSize = 16
		plate.TextColor3 = Color3.fromRGB(250, 238, 210)
		plate.TextStrokeTransparency = 1
		plate.TextTransparency = 0
		plate.Text = text
		plate.ZIndex = 7
		plate.Parent = header
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 16)
		pad.PaddingRight = UDim.new(0, 16)
		pad.Parent = plate
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, 8)
		c.Parent = plate
		local s = Instance.new("UIStroke")
		s.Color = Color3.fromRGB(214, 170, 90)
		s.Thickness = 1
		s.Transparency = 0.4
		s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		s.Parent = plate
		return header
	end

	-- POLISH PASS Batch 2: builds a cheap signature string out of the
	-- offer ids currently on the table (Voucher + Patron + Pack) --
	-- compared against `lastShopOfferSignature` (persists across
	-- rebuildShop calls, module-level) so the offer-row pop-in only fires
	-- when the offers actually CHANGED (a fresh shop visit or a Reroll),
	-- not on every one of the many unrelated re-renders that also happen
	-- to call rebuildShop while the tab's open (buying something, a Tips
	-- change, etc. -- see rebuildShop's own comment).
	local function buildOfferSignature(state)
		local parts = {}
		if state.voucherOffer then
			table.insert(parts, "v:" .. tostring(state.voucherOffer.id))
		end
		for _, offer in ipairs(state.shopOffers or {}) do
			table.insert(parts, "p:" .. tostring(offer.id))
		end
		for _, pack in ipairs(state.packOffers or {}) do
			table.insert(parts, "k:" .. tostring(pack.id))
		end
		return table.concat(parts, ",")
	end
	local lastShopOfferSignature = nil

	-- PERF (technical-debt pass): buildOfferSignature above only tracks
	-- WHICH offers are on the table (for the reveal-stagger gate), but
	-- rebuildShop was destroying and rebuilding all ~40+ row Instances on
	-- EVERY render() while the Shop tab was open, even when nothing about
	-- the Buy tab actually changed (e.g. a render triggered by opening the
	-- My Patrons tab, or a sidebar-only state change). This broader
	-- signature also captures everything a row's own label/button text
	-- depends on -- prices, rerollCost, and the owned/slotLimit numbers
	-- that gate each Patron row's buttonEnabled -- so a real price or
	-- table-fullness change still forces a rebuild, but an unrelated
	-- render doesn't.
	local function buildShopRenderSignature(state)
		if not state then
			return "nil"
		end
		local parts = { buildOfferSignature(state) }
		table.insert(parts, "reroll:" .. tostring(state.rerollCost or 0))
		local ownedCount = (state.ownedPatrons and #state.ownedPatrons) or 0
		local slotLimit = state.patronSlotLimit or ownedCount
		table.insert(parts, string.format("table:%d/%d", ownedCount, slotLimit))
		if state.voucherOffer then
			table.insert(parts, "vp:" .. tostring(state.voucherOffer.price))
		end
		for _, offer in ipairs(state.shopOffers or {}) do
			table.insert(parts, "pp:" .. tostring(offer.id) .. ":" .. tostring(offer.price))
		end
		for _, pack in ipairs(state.packOffers or {}) do
			table.insert(parts, "kp:" .. tostring(pack.id) .. ":" .. tostring(pack.price))
		end
		return table.concat(parts, "|")
	end
	local lastShopRenderSignature = nil

	-- The whole Shop tab: Reroll button, then the occasional Voucher offer,
	-- then Patron offers, then Pack offers -- all regenerated by the server
	-- each shop visit (or Reroll). Gated on buildShopRenderSignature above
	-- so this only actually destroys/rebuilds the row Instances when
	-- something the Buy tab shows has actually changed; refreshPackPanel
	-- (below) still runs on every call with a live state, since the Pack
	-- reveal panel's own visibility (state.pendingPack) is independent of
	-- this signature.
	-- Card slots for this visit, in display order. Buying removes an offer from the state; its slot
	-- stays as an empty shelf spot with a SOLD stamp until the offer set changes (Reroll / next visit).
	local lastCardSlots, lastPackSlots = nil, nil
	local soldShown = {}

	-- Keeps the previous slot list while every current offer is still in it (a purchase), otherwise
	-- starts a new list from the current offers (a Reroll or a new shop visit).
	local function reconcileSlots(previous, current)
		if previous then
			local known = {}
			for _, slotInfo in ipairs(previous) do
				known[slotInfo.key] = slotInfo
			end
			local allKnown = true
			for _, item in ipairs(current) do
				if not known[item.key] then
					allKnown = false
					break
				end
			end
			if allKnown then
				local present = {}
				for _, item in ipairs(current) do
					present[item.key] = item
				end
				local merged = {}
				for _, slotInfo in ipairs(previous) do
					local item = present[slotInfo.key]
					table.insert(merged, { key = slotInfo.key, kind = slotInfo.kind, offer = item and item.offer or slotInfo.offer, sold = item == nil })
				end
				return merged
			end
		end
		local fresh = {}
		for _, item in ipairs(current) do
			table.insert(fresh, { key = item.key, kind = item.kind, offer = item.offer, sold = false })
		end
		return fresh
	end

	-- How many spots a row will show once reconcileSlots has run (a purchase keeps its SOLD spot; a Reroll or a new
	-- visit starts over). The card sizes are planned for that number, before the rows are built.
	local function spotsAfter(previous, keys)
		if previous then
			local known = {}
			for _, slotInfo in ipairs(previous) do known[slotInfo.key] = true end
			local allKnown = true
			for _, key in ipairs(keys) do
				if not known[key] then
					allKnown = false
					break
				end
			end
			if allKnown then return #previous end
		end
		return #keys
	end

	local function rebuildShop(state)
		-- A refused Reroll or Haggle is never silent: the server sends the reason and the Counter says it once.
		if state and type(state.shopNotice) == "table" and state.shopNotice.seq ~= lastNoticeSeq then
			lastNoticeSeq = state.shopNotice.seq
			ShopTrace.log("the server refused: %s", tostring(state.shopNotice.text))
			if type(state.shopNotice.text) == "string" then showWarning(state.shopNotice.text) end
		end
		if shopHaggle and state then shopHaggle.update(state) end
		local renderSignature = buildShopRenderSignature(state)
		if state and renderSignature == lastShopRenderSignature then
			lastShopRenderSignature = renderSignature
			refreshPackPanel(state)
			return
		end
		lastShopRenderSignature = renderSignature

		for _, child in ipairs(shopBuyListFrame:GetChildren()) do
			if not child:IsA("UIListLayout") then
				child:Destroy()
			end
		end

		if not state then
			return
		end

		local ownedCount = (state.ownedPatrons and #state.ownedPatrons) or 0
		local slotLimit = state.patronSlotLimit or ownedCount
		local tableIsFull = ownedCount >= slotLimit
		local tips = state.tips or 0
		require(script.Parent.ShopPurse).update(shopFrame, tips)

		-- Every element added to this ScrollingFrame needs an explicit, sequential LayoutOrder
		-- (see the note on UIListLayout sorting by Name).
		local nextOrder = 0
		local function order()
			nextOrder = nextOrder + 1
			return nextOrder
		end

		local fitScaleValue, stageScales, patronRow, packRow, emptyScene -- Counter v2 stage (stageScales stays nil when the art is missing)

		-- Size the cards so the strip, both rows and their labels fit the panel (CardShape.fitScale);
		-- the footer with Next Round is reserved outside this scroll area, so no card sits under it.
		do
			local cam = workspace.CurrentCamera
			local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
			local area = shopBuyListFrame.AbsoluteSize
			local availW = area.X > 0 and area.X or (vp.X - 20)
			local availH = area.Y > 0 and area.Y or (vp.Y - 148)
			local widest = math.max(#(state.shopOffers or {}) + (state.voucherOffer and 1 or 0), #(state.packOffers or {}), 1)
			fitScaleValue = require(Engine:WaitForChild("CardShape")).fitScale(availW, availH, vp.X, vp.Y, widest)
			ShopCardsModule.setScale(fitScaleValue)
			if shopStage then
				-- The shelf is sized for every spot it will show, SOLD spots included. It used to be sized for what was
				-- still for sale, so the remaining cards shrank the moment something was bought (and the pack names
				-- no longer fitted their plates).
				local cardKeys, packKeys = {}, {}
				if state.voucherOffer then cardKeys[#cardKeys + 1] = "v:" .. tostring(state.voucherOffer.id) end
				for _, offer in ipairs(state.shopOffers or {}) do cardKeys[#cardKeys + 1] = "p:" .. tostring(offer.id) end
				for _, pack in ipairs(state.packOffers or {}) do packKeys[#packKeys + 1] = "k:" .. tostring(pack.id) end
				stageScales = shopStage.scales(state, { offers = spotsAfter(lastCardSlots, cardKeys), packs = spotsAfter(lastPackSlots, packKeys) })
				ShopCardsModule.setScale(stageScales.patron)
			end
		end

		-- ----- Slim top strip: Reroll and the table count -----
		local rerollRow = Instance.new("Frame")
		rerollRow.LayoutOrder = order()
		rerollRow.Size = UDim2.new(1, 0, 0, 44)
		rerollRow.BackgroundTransparency = 1
		rerollRow.ZIndex = 6
		rerollRow.Parent = shopBuyListFrame

		local rerollButton = Instance.new("TextButton")
		require(script.Parent.TutorialBus).register("reroll", rerollButton) -- TUTORIAL target (rebuilt with the shop)
		rerollButton.Size = UDim2.new(0, 190, 0, 38)
		rerollButton.Position = UDim2.new(0, 14, 0, 3)
		rerollButton.Font = Enum.Font.GothamBold
		rerollButton.TextSize = 16
		rerollButton.Text = ShopRefusal.rerollLabel(state.rerollCost) -- "Reroll 3": the price is on the control
		rerollButton.Name = "Reroll"
		rerollButton.BackgroundColor3 = Color3.fromRGB(118, 82, 48)
		rerollButton.TextColor3 = Color3.fromRGB(250, 235, 200)
		rerollButton.ZIndex = 6
		rerollButton:SetAttribute("FlatFace", true) -- same wood plate as Next Round
		rerollButton.Parent = rerollRow
		polishButton(rerollButton, 8)
		addButtonHoverScale(rerollButton)
		pcall(function() require(script.Parent.TavernScreens).skin(rerollRow, "counter") end) -- brown secondary

		local tableLabel = Instance.new("TextLabel")
		tableLabel.Size = UDim2.new(1, -230, 0, 38)
		tableLabel.Position = UDim2.new(0, 220, 0, 3)
		tableLabel.BackgroundTransparency = 1
		tableLabel.Font = Enum.Font.GothamBold
		tableLabel.TextSize = 15
		tableLabel.TextWrapped = true
		tableLabel.TextXAlignment = Enum.TextXAlignment.Left
		tableLabel.TextColor3 = Color3.fromRGB(255, 214, 130)
		tableLabel.TextStrokeColor3 = Color3.fromRGB(30, 18, 8)
		tableLabel.TextStrokeTransparency = 0.8
		tableLabel.BackgroundColor3 = Color3.fromRGB(118, 82, 48) -- wooden plate, like Reroll and Haggle
		tableLabel.BackgroundTransparency = 0.05
		tableLabel.TextColor3 = Color3.fromRGB(250, 235, 200)
		tableLabel.Text = string.format("Your table: %d/%d Patrons%s", ownedCount, slotLimit,
			tableIsFull and " is full! Sell one in My Patrons to make room." or "")
		tableLabel.ZIndex = 6
		tableLabel.Parent = rerollRow
		do -- same plate as the other labels: rounded, brass edge, padded
			local c = Instance.new("UICorner") c.CornerRadius = UDim.new(0, 8) c.Parent = tableLabel
			local s = Instance.new("UIStroke") s.Color = Color3.fromRGB(70, 46, 24) s.Thickness = 1.5 s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border s.Parent = tableLabel
			local p = Instance.new("UIPadding") p.PaddingLeft = UDim.new(0, 8) p.PaddingRight = UDim.new(0, 8) p.Parent = tableLabel
		end

		rerollButton.MouseButton1Click:Connect(function()
			ShopTrace.log("Reroll clicked")
			if not tutorialAllows("reroll") then
				ShopTrace.log("Reroll blocked by the tutorial")
				showWarning("Finish the tutorial step first.")
				return
			end
			local latestState = getLatestState()
			if not latestState or latestState.tips < (latestState.rerollCost or 0) then
				ShopTrace.log("Reroll refused here: tips %s, cost %s", tostring(latestState and latestState.tips), tostring(latestState and latestState.rerollCost))
				showWarning(ShopRefusal.REASONS.tips)
				playClickSfx()
				if shopScene then shopScene.onCantAfford() end
				return
			end
			playClickSfx(0.4)
			-- Ring the bell: a quick wobble (skipped on Fast / Reduce screen shake).
			if ClientSettings.get("animSpeed") ~= "fast" and not ClientSettings.get("reduceShake") then
				task.spawn(function()
					for _, angle in ipairs({ -5, 5, -3, 3, 0 }) do
						if not rerollButton.Parent then
							return
						end
						tweenTo(rerollButton, { Rotation = angle }, 0.05)
						task.wait(0.05)
					end
				end)
			end
			if shopScene then shopScene.onReroll() end
			ShopTrace.log("Reroll sent to the server (tips %s, cost %s)", tostring(latestState.tips), tostring(latestState.rerollCost))
			RerollShopRemote:FireServer()
			tutorialReport("reroll")
		end)

		-- Buy handlers: same checks and remotes as the old rows. They return true when a remote fired.
		local function buyVoucher(offer)
			local latestState = getLatestState()
			if not latestState or latestState.tips < offer.price then
				showWarning("Not enough tips for that.")
				playClickSfx()
				if shopScene then shopScene.onCantAfford() end
				return false
			end
			require(script.Parent.Cue).play("buy")
			if shopScene then shopScene.onBuy("buy") end
			BuyHousePassRemote:FireServer(offer.id)
			return true
		end
		local function buyPatron(offer)
			if not tutorialAllows("buy") then return false end
			local latestState = getLatestState()
			if not latestState or latestState.tips < offer.price then
				showWarning("Not enough tips for that.")
				playClickSfx()
				if shopScene then shopScene.onCantAfford() end
				return false
			end
			local liveOwnedCount = latestState.ownedPatrons and #latestState.ownedPatrons or 0
			if latestState.patronSlotLimit and liveOwnedCount >= latestState.patronSlotLimit then
				showWarning("Your table is full, sell a Patron in the My Patrons tab to make room.")
				playClickSfx()
				return false
			end
			require(script.Parent.Cue).play("buy")
			if shopScene then shopScene.onBuy("buyPatron") end
			BuyPatronRemote:FireServer(offer.id)
			tutorialReport("buy_patron")
			return true
		end
		local function buyPack(pack)
			if not tutorialAllows("pack") then return false end
			local latestState = getLatestState()
			if not latestState or latestState.tips < pack.price then
				showWarning("Not enough tips for that.")
				playClickSfx()
				if shopScene then shopScene.onCantAfford() end
				return false
			end
			require(script.Parent.Cue).play("buy")
			if shopScene then shopScene.onBuy("buyPack") end
			BuyPackRemote:FireServer(pack.id)
			tutorialReport("buy_pack")
			return true
		end

		-- ----- Patron + Voucher cards (one centered row) -----
		local current = {}
		if state.voucherOffer then
			table.insert(current, { key = "v:" .. tostring(state.voucherOffer.id), kind = "voucher", offer = state.voucherOffer })
		end
		for _, offer in ipairs(state.shopOffers or {}) do
			table.insert(current, { key = "p:" .. tostring(offer.id), kind = "patron", offer = offer })
		end
		lastCardSlots = reconcileSlots(lastCardSlots, current)

		local offerCardsThisRebuild = {}
		addSectionHeader(shopBuyListFrame, order(), "Patrons")
		if #lastCardSlots == 0 then
			emptyScene = shopCards.emptyScene(shopBuyListFrame, order(), "offers")
		else
			local row = shopCards.row(shopBuyListFrame, order(), ShopCardsModule.rowHeight("patron"), stageScales and stageScales.gap)
			patronRow = row
			for index, slotInfo in ipairs(lastCardSlots) do
				local offer = slotInfo.offer
				if slotInfo.sold then
					local animate = not soldShown[slotInfo.key]
					soldShown[slotInfo.key] = true
					shopCards.soldSpot(row, index, slotInfo.kind, animate)
				elseif slotInfo.kind == "voucher" then
					local card = shopCards.card(row, {
						shield = shieldFor(require(Engine:WaitForChild("HousePasses")).getById(offer.id)),
						kind = "voucher", layoutOrder = index, name = offer.name, description = offer.description,
						price = offer.price, affordable = tips >= offer.price, shortBy = math.max(0, offer.price - tips), actionText = "Buy", emoji = offer.icon, badge = "PASS",
						artTab = "house_passes", artId = offer.id, rarityTab = "housePasses", rarityId = offer.id,
						onAction = function()
							local fired = buyVoucher(offer)
							if fired then
								soldShown[slotInfo.key] = nil
							end
							return fired
						end,
					})
					table.insert(offerCardsThisRebuild, card.slot)
				else
					local fullPatron = Patrons.getById(offer.id)
					local card = shopCards.card(row, {
						synergy = synergyTagsFor(offer.id), shield = shieldFor(fullPatron),
						kind = "patron", layoutOrder = index, name = offer.name, description = offer.description,
						price = offer.price, affordable = tips >= offer.price, shortBy = math.max(0, offer.price - tips), actionText = "Buy", enabled = not tableIsFull, disabledText = "Full",
						emoji = fullPatron and fullPatron.icon, artTab = "patrons", artId = offer.id, rarityTab = "patrons", rarityId = offer.id,
						onAction = function()
							local fired = buyPatron(offer)
							if fired then
								soldShown[slotInfo.key] = nil
							end
							return fired
						end,
					})
					table.insert(offerCardsThisRebuild, card.slot)
				end
			end
		end

		-- ----- Pack cards (shorter) -----
		addSectionHeader(shopBuyListFrame, order(), "Packs")
		local currentPacks = {}
		for _, pack in ipairs(state.packOffers or {}) do
			table.insert(currentPacks, { key = "k:" .. tostring(pack.id), kind = "pack", offer = pack })
		end
		lastPackSlots = reconcileSlots(lastPackSlots, currentPacks)
		if #lastPackSlots > 0 then
			if stageScales then ShopCardsModule.setScale(stageScales.pack) end
			local row = shopCards.row(shopBuyListFrame, order(), ShopCardsModule.rowHeight("pack"), stageScales and stageScales.gap)
			packRow = row
			-- Pack tooltips open beside the pack row, clear of the offers and every control (Client/ShopTips.lua).
			local packTip = require(script.Parent.ShopTips).packPlacer({
				packRow = function() return packRow end,
				offerRow = function() return patronRow end,
				controls = function() return shopStage and shopStage.keepOut() or {} end,
			})
			for index, slotInfo in ipairs(lastPackSlots) do
				local pack = slotInfo.offer
				if slotInfo.sold then
					local animate = not soldShown[slotInfo.key]
					soldShown[slotInfo.key] = true
					shopCards.soldSpot(row, index, "pack", animate)
				else
					local baseId, sizeBadge, tierRarity = ShopCardsModule.packTier(pack.id)
					local definition = Packs.getById(pack.id)
					local line = definition and string.format("See %d, keep %d", definition.revealCount or 3, definition.pickCount or 1) or pack.description
					local card = shopCards.card(row, {
						kind = "pack", layoutOrder = index, name = pack.name, line = line, price = pack.price, tipAlign = packTip,
						ribbon = Packs.shelfName(pack.name), -- the small plate shows a name that fits it; the tooltip keeps the full one
						affordable = tips >= pack.price, shortBy = math.max(0, pack.price - tips), actionText = "Buy", emoji = pack.icon, badge = sizeBadge,
						artTab = "packs", artId = baseId, rarity = tierRarity,
						glow = (sizeBadge == "MEGA" and 2) or (sizeBadge == "JUMBO" and 1) or 0,
						onAction = function()
							local fired = buyPack(pack)
							if fired then
								soldShown[slotInfo.key] = nil
							end
							return fired
						end,
					})
					table.insert(offerCardsThisRebuild, card.slot)
				end
			end
		end

		if stageScales then ShopCardsModule.setScale(fitScaleValue) end -- My Patrons / My Recipes cards use the fit scale again

		-- Only pop the cards in when the offer SET actually changed (fresh visit / Reroll).
		local offerSignature = buildOfferSignature(state)
		if offerSignature ~= lastShopOfferSignature then
			soldShown = {}
			revealStagger(offerCardsThisRebuild, { stagger = 0.06, duration = 0.24, fromScale = 0.85 })
		end
		lastShopOfferSignature = offerSignature

		if shopStage then
			shopStage.arrange({
				patronRow = patronRow, packRow = packRow, rerollRow = rerollRow, rerollButton = rerollButton, tableLabel = tableLabel,
				emptyScene = emptyScene,
				patronRowHeight = patronRow and patronRow.Size.Y.Offset or 0,
				packRowHeight = packRow and packRow.Size.Y.Offset or 0,
				counts = { offers = math.max(#lastCardSlots, 1), packs = #lastPackSlots },
			})
		end

		refreshPackPanel(state)
	end

	local function clearTab(listFrame)
		for _, child in ipairs(listFrame:GetChildren()) do
			if not child:IsA("UIListLayout") then
				child:Destroy()
			end
		end
	end

	-- keeps the My Patrons / My Recipes content clear of Marlo (the stage knows where he stands)
	local function padForStage(listFrame)
		local pad = listFrame:FindFirstChild("StagePad")
		if not pad then
			pad = Instance.new("UIPadding")
			pad.Name = "StagePad"
			pad.Parent = listFrame
		end
		pad.PaddingLeft = UDim.new(0, shopStage and shopStage.tabPadLeft() or 0)
	end

	local lastPatronFitW = nil
	local rebuildMyPatronsTab
	function rebuildMyPatronsTab(state)
		local ownedPatrons = (state and state.ownedPatrons) or {}
		local housePassIds = (state and state.housePassIds) or {}
		clearTab(shopMyPatronsListFrame)
		padForStage(shopMyPatronsListFrame)

		-- Every element needs an explicit, sequential LayoutOrder (see rebuildShop).
		local nextOrder = 0
		local function order()
			nextOrder = nextOrder + 1
			return nextOrder
		end

		addSectionHeader(shopMyPatronsListFrame, order(), "Patrons")
		do
			local seats = math.max(math.floor(tonumber(state and state.patronSlotLimit) or #ownedPatrons), #ownedPatrons)
			-- size the seats so five fit the free area right of Marlo with no scrolling (more than five scroll)
			local zoneW = shopStage and shopStage.tabWidth() or 0
			-- the REAL viewport of the list (minus the stage pad) caps the zone, so the canvas can never be wider
			local realW = shopMyPatronsListFrame.AbsoluteSize.X - (shopStage and shopStage.tabPadLeft() or 0)
			if realW > 0 and (zoneW <= 0 or realW < zoneW) then zoneW = realW end
			if zoneW > 0 then
				local cam = workspace.CurrentCamera
				local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
				ShopCardsModule.setScale(require(Engine:WaitForChild("CardShape")).fitOwned(zoneW, math.min(seats, 5), vp.X, vp.Y))
			end
			local row = shopCards.row(shopMyPatronsListFrame, order(), ShopCardsModule.rowHeight("owned"), 10)
			row.CanvasPosition = Vector2.new(0, 0)
			row.ClipsDescendants = seats > 5
			-- if the first build ran before layout, refit once when the real width is known and the canvas overflows
			if seats <= 5 then
				row:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
					local w = row.AbsoluteSize.X
					if w > 0 and row.AbsoluteCanvasSize.X > w + 1 and lastPatronFitW ~= w then
						lastPatronFitW = w
						task.defer(function() rebuildMyPatronsTab(state) end)
					end
				end)
			end
			for seat = #ownedPatrons + 1, seats do
				shopCards.seatSlot(row, seat, "owned")
			end
			for index, owned in ipairs(ownedPatrons) do
				local fullPatron = Patrons.getById(owned.id)
				local refund = fullPatron and math.floor(fullPatron.price / 2) or 0
				shopCards.card(row, {
					kind = "owned", layoutOrder = index, name = owned.name, description = owned.description,
					actionText = "Discard", emoji = fullPatron and fullPatron.icon,
					artTab = "patrons", artId = owned.id, rarityTab = "patrons", rarityId = owned.id,
					onAction = function()
						playClickSfx(0.4)
						local copy = require(Engine:WaitForChild("ConfirmCopy")).sell(owned.name, refund)
						showConfirmDialog(copy.message, function()
							SellPatronRemote:FireServer(owned.id)
						end, copy)
						return false
					end,
				})
			end
		end

		-- ----- House Passes (Vouchers): permanent for the run, nothing to click -----
		local passesFrom = nextOrder + 1
		addSectionHeader(shopMyPatronsListFrame, order(), "House Passes")
		local passes = {}
		for _, passId in ipairs(housePassIds) do
			local pass = HousePasses.getById(passId)
			if pass then
				table.insert(passes, pass)
			end
		end
		if #passes == 0 then
			shopCards.emptyScene(shopMyPatronsListFrame, order(), "housePasses")
		else
			local row = shopCards.row(shopMyPatronsListFrame, order(), ShopCardsModule.rowHeight("owned", true))
			for index, pass in ipairs(passes) do
				shopCards.card(row, {
					kind = "owned", noAction = true, layoutOrder = index, name = pass.name, description = pass.description,
					emoji = pass.icon, artTab = "house_passes", artId = pass.id, rarityTab = "housePasses", rarityId = pass.id,
				})
			end
		end
		-- TUTORIAL targets for the My Patrons explanation steps: tag the owned-Patron rows and the House Passes area
		for _, child in ipairs(shopMyPatronsListFrame:GetChildren()) do
			if child:IsA("GuiObject") and child.LayoutOrder >= 2 then
				child:SetAttribute("TutorialKind", child.LayoutOrder >= passesFrom and "housePasses" or "myPatrons")
			end
		end
	end

	local function rebuildMyRecipesTab(state)
		clearTab(shopMyRecipesListFrame)
		padForStage(shopMyRecipesListFrame)

		local inventories = {
			house = (state and state.houseRecipeInventory) or {},
			menu = (state and state.menuRecipeInventory) or {},
			secret = (state and state.secretRecipeInventory) or {},
		}

		-- GENRE PARITY: House + Menu + Secret share ONE box (RunState.recipeSlotLimit).
		local heldCount = #inventories.house + #inventories.menu + #inventories.secret
		local recipeSlotLimit = (state and state.recipeSlotLimit) or heldCount
		local boxIsFull = heldCount >= recipeSlotLimit
		local chip = shopFrame:FindFirstChild("RecipeBoxChip")
		if chip then
			chip.Text = string.format("Recipe box: %d/%d%s", heldCount, recipeSlotLimit, boxIsFull and " (full)" or "")
			chip.TextColor3 = boxIsFull and Color3.fromRGB(255, 150, 120) or Color3.fromRGB(255, 214, 130)
		end

		-- If the recipe we're mid-targeting is gone from its inventory, close the stale picker.
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

		if heldCount == 0 then
			shopCards.emptyScene(shopMyRecipesListFrame, 1, "recipes")
			return
		end

		local nextOrder = 0
		local function order()
			nextOrder = nextOrder + 1
			return nextOrder
		end

		for _, categoryDef in ipairs(RECIPE_CATEGORY_LIST) do
			local inventory = inventories[categoryDef.key]
			if #inventory > 0 then
				addSectionHeader(shopMyRecipesListFrame, order(), categoryDef.label)
				local row = shopCards.row(shopMyRecipesListFrame, order(), ShopCardsModule.rowHeight("owned"))
				for index, recipeId in ipairs(inventory) do
					local recipe = findRecipeById(categoryDef.catalog, recipeId)
					if recipe then
						local categoryKey = categoryDef.key
						shopCards.card(row, {
							kind = "owned", layoutOrder = index, name = recipe.name, description = recipe.description,
							actionText = "Use", emoji = recipe.icon, artTab = "recipes", artId = recipe.id,
							rarityTab = "recipes", rarityId = recipe.id,
							onAction = function()
								playClickSfx(0.4)
								if recipe.cardCount then
									openTargetPanel(categoryKey, recipe.id, recipe)
								else
									local copy = require(Engine:WaitForChild("ConfirmCopy")).use(recipe.name, recipe.description)
									showConfirmDialog(copy.message, function()
										require(script.Parent.Cue).play("buy")
										UseRecipeRemote:FireServer(categoryKey, recipe.id)
									end, copy)
								end
								return false
							end,
						})
					end
				end
			end
		end
	end

	-- ===== TUTORIAL WALKTHROUGH =====
	-- Built and required HERE, not as its own top-level local in
	-- init.client.lua -- confirmed the hard way (same ceiling PhaseA.lua's
	-- own header describes): that chunk is already right up against Lua's
	-- 200-local-per-chunk limit, and this feature needs BOTH
	-- nextRoundButton/shopBuyListFrame (which don't exist until this very
	-- require() call finishes) AND handFrame/playButton/discardButton/the
	-- Sidebar boxes (which exist well before it). Building it in here means
	-- nextRoundButton/shopBuyListFrame are just the plain locals already
	-- sitting right above -- nothing extra has to thread back out through a
	-- deps table only to immediately thread back in. Purely a local-budget
	-- optimization, same as PhaseA.lua's own merge -- Shop.lua and the
	-- Tutorial Walkthrough are not otherwise coupled; see
	-- TutorialWalkthrough.lua's own header for the full feature.
	local TutorialWalkthroughModule = require(script.Parent.TutorialWalkthrough)({
		root = root,
		tweenTo = tweenTo,
		polishPanel = polishPanel,
		playClickSfx = playClickSfx,
		addButtonHoverScale = addButtonHoverScale,
		MarkTutorialSeenRemote = MarkTutorialSeenRemote,
		handFrame = tutorialHandFrame,
		playButton = tutorialPlayButton,
		discardButton = tutorialDiscardButton,
		nextRoundButton = nextRoundButton,
		sidebarScoreBox = tutorialSidebarScoreBox,
		sidebarTipsBox = tutorialSidebarTipsBox,
		sidebarHandsDiscardsBox = tutorialSidebarHandsDiscardsBox,
		sidebarPatronsBox = tutorialSidebarPatronsBox,
		shopBuyListFrame = shopBuyListFrame,
	})

	tutorialAllows = TutorialWalkthroughModule.allows
	tutorialReport = TutorialWalkthroughModule.report

	-- TUTORIAL spotlight targets that need a live scan (offer cards and the pack panel are rebuilt often).
	do
		local TB = require(script.Parent.TutorialBus)
		local function cards(root, kind)
			local found = {}
			if not root then return found end
			for _, d in ipairs(root:GetDescendants()) do
				if d:IsA("Frame") and d:GetAttribute("TutorialKind") == kind and d.Visible and d.AbsoluteSize.X > 0 then
					found[#found + 1] = d
				end
			end
			return found
		end
		local function cheapest(kind)
			local best
			for _, d in ipairs(cards(shopBuyListFrame, kind)) do
				if not best or (d:GetAttribute("TutorialPrice") or 0) < (best:GetAttribute("TutorialPrice") or 0) then best = d end
			end
			return best
		end
		TB.register("shopPatronsRow", function()
			local list = cards(shopBuyListFrame, "patron")
			return #list > 0 and list or nil
		end)
		TB.register("myPatronCards", function()
				if not (shopMyPatronsListFrame and shopMyPatronsListFrame.Visible) then return nil end
				local list = {}
				for _, d in ipairs(shopMyPatronsListFrame:GetChildren()) do
					if d:IsA("GuiObject") and d:GetAttribute("TutorialKind") == "myPatrons" and d.Visible and d.AbsoluteSize.X > 0 then list[#list + 1] = d end
				end
				return #list > 0 and list or nil
			end)
			TB.register("myPatronDiscard", function()
				if not (shopMyPatronsListFrame and shopMyPatronsListFrame.Visible) then return nil end
				local closed
				for _, d in ipairs(shopMyPatronsListFrame:GetDescendants()) do
					if d:IsA("TextButton") and d.Text == "Discard" and d.AbsoluteSize.X > 0 then
						if d.Visible then return d end
						closed = closed or d
					end
				end
				-- The Discard plate is only drawn while its card is hovered or picked, so there was nothing to point at
				-- and the tutorial stopped on a dim screen (always, on touch). The first card is asked to hold its
				-- plate open (Client/ShopCards "HoldOpen"); it is found on the next frame.
				if closed then closed:SetAttribute("HoldOpen", true) end
				return nil
			end)
			-- the Counter's own Tips plate (Client/ShopPurse): the left board with the Tips row is not on screen here
			TB.register("shopTips", function() return shopFrame:FindFirstChild("PursePlate") end)
			TB.register("myHousePasses", function()
				if not (shopMyPatronsListFrame and shopMyPatronsListFrame.Visible) then return nil end
				local list = {}
				for _, d in ipairs(shopMyPatronsListFrame:GetChildren()) do
					if d:IsA("GuiObject") and d:GetAttribute("TutorialKind") == "housePasses" and d.Visible and d.AbsoluteSize.X > 0 then list[#list + 1] = d end
				end
				return #list > 0 and list or nil
			end)
			TB.register("cheapestPatron", function() return cheapest("patron") end)
		TB.register("cheapestPack", function() return cheapest("pack") end)
		TB.register("packItems", function()
			local list = {}
			if shopPackPanel and shopPackPanel.Visible then
				for _, d in ipairs(shopPackPanel:GetDescendants()) do
					if d:IsA("Frame") and d:GetAttribute("TutorialKind") ~= nil and d.AbsoluteSize.X > 0 then list[#list + 1] = d end
				end
			end
			return #list > 0 and list or nil
		end)
		TB.register("packConfirm", function() return packConfirmButton end)
	end

	return {
		shopFrame = shopFrame,
		nextRoundButton = nextRoundButton,
		-- TUTORIAL WALKTHROUGH: the scrolling offer list itself (Patrons/
		-- Packs/Vouchers), so the walkthrough's one guided Shop step can
		-- spotlight the real list instead of guessing at one specific row
		-- (this run's actual offers are random -- there's no single
		-- "Buy" button guaranteed to exist every time).
		shopBuyListFrame = shopBuyListFrame,
		-- Exposed as a nested table (not 6 flat fields) so call sites in
		-- init.client.lua read clearly as what they are: Shop.tutorial.start(),
		-- Shop.tutorial.notifyHandPlayed(), etc.
		tutorial = TutorialWalkthroughModule,
		rebuildShop = rebuildShop,
		rebuildMyPatronsTab = rebuildMyPatronsTab,
		rebuildMyRecipesTab = rebuildMyRecipesTab,
		closeTargetPanel = closeTargetPanel,
		-- Studio only (Client/DebugGoto "packroom"): pick the n-th revealed item and press Confirm, so the Make room step can be looked at
		debugPackSelect = function(index)
			local state = getLatestState()
			if state and state.pendingPack and state.pendingPack.items[index] then
				pendingPackSelected = { [index] = true }
				refreshPackPanel(state)
			end
		end,
		debugPackConfirm = function()
			confirmPackPick()
		end,
	}
end
