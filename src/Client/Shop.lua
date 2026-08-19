--[[
	Client/Shop.lua
	The Shop overlay (full-screen tabbed menu: Buy Patrons / My Patrons /
	Special Cards stub / Night Upgrades stub) -- extracted out of
	init.client.lua on its own, since it's the single most self-contained
	UI system in the client and the one we understand best right now.

	This is a ModuleScript, not a LocalScript, so it has no access to
	init.client.lua's local variables -- everything it needs from the rest
	of the client is passed in explicitly via `deps` (see the field list
	below). It returns a small table of the pieces the rest of the client
	still needs to reach: the panel itself (for Visible toggling and theme
	tweening), the Next Round button (for its click handler and theme
	tweening, both wired in init.client.lua), and the two rebuild functions
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
		BuyPatronRemote    -- RemoteEvent
		SellPatronRemote   -- RemoteEvent
		getLatestState     -- function() -> latest state table or nil (latestState
		                       is reassigned, not mutated, each render() call in
		                       init.client.lua, so this needs to be a live getter,
		                       not a value passed once at construction time)

	Returns:
		{
			shopFrame = Frame,
			nextRoundButton = TextButton,
			rebuildShop = function(shopOffers),
			rebuildMyPatronsTab = function(ownedPatrons),
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
	local BuyPatronRemote = deps.BuyPatronRemote
	local SellPatronRemote = deps.SellPatronRemote
	local getLatestState = deps.getLatestState

	-- ----- Shop overlay -----
	-- A full-screen tabbed menu, not a small popup, on purpose: "Buy Patrons"
	-- is one tab among what will eventually be several (Special Cards, Night
	-- Upgrades are stubbed in now so the tab bar itself doesn't need to change
	-- shape later), and "My Patrons" is where you manage/discard what you've
	-- already got -- important once the catalog grows well past a handful.

	local shopFrame
	local nextRoundButton
	local shopBuyListFrame
	local shopMyPatronsListFrame

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

		local function makeComingSoonTab(emoji, title, description)
			local tab = Instance.new("Frame")
			tab.Size = UDim2.fromScale(1, 1)
			tab.BackgroundTransparency = 1
			tab.Visible = false
			tab.ZIndex = SHOP_ZINDEX
			tab.Parent = shopContentArea

			local emojiLabel = Instance.new("TextLabel")
			emojiLabel.Size = UDim2.new(1, 0, 0, 60)
			emojiLabel.Position = UDim2.new(0, 0, 0.3, 0)
			emojiLabel.BackgroundTransparency = 1
			emojiLabel.Font = Enum.Font.GothamBold
			emojiLabel.TextSize = 40
			emojiLabel.Text = emoji
			emojiLabel.ZIndex = SHOP_ZINDEX
			emojiLabel.Parent = tab

			local titleLabel = Instance.new("TextLabel")
			titleLabel.Size = UDim2.new(1, -60, 0, 26)
			titleLabel.Position = UDim2.new(0.5, 0, 0.3, 66)
			titleLabel.AnchorPoint = Vector2.new(0.5, 0)
			titleLabel.BackgroundTransparency = 1
			titleLabel.Font = Enum.Font.GothamBold
			titleLabel.TextSize = 18
			titleLabel.TextColor3 = Color3.fromRGB(230, 215, 195)
			titleLabel.Text = title .. " -- coming soon"
			titleLabel.ZIndex = SHOP_ZINDEX
			titleLabel.Parent = tab

			local descLabel = Instance.new("TextLabel")
			descLabel.Size = UDim2.new(0, 420, 0, 40)
			descLabel.Position = UDim2.new(0.5, 0, 0.3, 96)
			descLabel.AnchorPoint = Vector2.new(0.5, 0)
			descLabel.BackgroundTransparency = 1
			descLabel.Font = Enum.Font.Gotham
			descLabel.TextSize = 14
			descLabel.TextWrapped = true
			descLabel.TextColor3 = Color3.fromRGB(190, 175, 155)
			descLabel.Text = description
			descLabel.ZIndex = SHOP_ZINDEX
			descLabel.Parent = tab

			return tab
		end

		shopBuyListFrame = makeShopListTab()
		shopMyPatronsListFrame = makeShopListTab()
		local shopSpecialCardsTab = makeComingSoonTab("🃏", "Special Cards", "One-off cards you can add to your deck for a run -- planned for a future update.")
		local shopNightUpgradesTab = makeComingSoonTab("⬆️", "Night Upgrades", "Permanent boosts that last the whole Night -- planned for a future update.")

		local shopTabContents = {
			buy = shopBuyListFrame,
			mypatrons = shopMyPatronsListFrame,
			specialcards = shopSpecialCardsTab,
			nightupgrades = shopNightUpgradesTab,
		}

		local SHOP_TAB_DEFS = {
			{ key = "buy", label = "Buy Patrons" },
			{ key = "mypatrons", label = "My Patrons" },
			{ key = "specialcards", label = "Special Cards" },
			{ key = "nightupgrades", label = "Night Upgrades" },
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
	end -- do (Shop overlay)

	-- A small colored badge with an icon (emoji glyph, not an uploaded image --
	-- see the TavernScene comment for why we don't guess catalog asset IDs)
	-- standing in for "a picture" for each Patron until real art exists.
	-- ZIndex = 6 everywhere below matches SHOP_ZINDEX from the Shop overlay's
	-- construction block above (that local isn't in scope down here, so this
	-- repeats the literal -- see the comment there for why every descendant
	-- needs it explicitly rather than inheriting shopFrame's ZIndex).
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

	local function rebuildShop(shopOffers)
		for _, child in ipairs(shopBuyListFrame:GetChildren()) do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end

		if #shopOffers == 0 then
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
			return
		end

		for _, offer in ipairs(shopOffers) do
			local fullPatron = Patrons.getById(offer.id)

			local row = Instance.new("Frame")
			row.Size = UDim2.new(1, 0, 0, 64)
			row.BackgroundColor3 = Color3.fromRGB(60, 45, 32)
			row.ZIndex = 6
			row.Parent = shopBuyListFrame
			polishPanel(row, 10)

			makePatronIconBadge(row, fullPatron and fullPatron.icon)

			local label = Instance.new("TextLabel")
			label.Size = UDim2.new(1, -170, 1, -8)
			label.Position = UDim2.new(0, 64, 0, 4)
			label.BackgroundTransparency = 1
			label.Font = Enum.Font.Gotham
			label.TextSize = 14
			label.TextWrapped = true
			label.TextXAlignment = Enum.TextXAlignment.Left
			label.TextColor3 = Color3.fromRGB(250, 240, 220)
			label.Text = string.format("%s (%d tips)\n%s", offer.name, offer.price, offer.description)
			label.ZIndex = 6
			label.Parent = row

			local buyButton = Instance.new("TextButton")
			buyButton.Size = UDim2.new(0, 90, 0, 36)
			buyButton.Position = UDim2.new(1, -100, 0.5, -18)
			buyButton.Font = Enum.Font.GothamBold
			buyButton.TextSize = 15
			buyButton.Text = "Buy"
			buyButton.BackgroundColor3 = Color3.fromRGB(90, 60, 30)
			buyButton.TextColor3 = Color3.fromRGB(250, 240, 220)
			buyButton.ZIndex = 6
			buyButton.Parent = row
			polishButton(buyButton, 8)

			buyButton.MouseButton1Click:Connect(function()
				local latestState = getLatestState()
				if not latestState or latestState.tips < offer.price then
					showWarning("Not enough tips for that.")
					playClickSfx()
					return
				end
				playSfx(SOUND_IDS.buyPatron)
				BuyPatronRemote:FireServer(offer.id)
			end)
		end
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
			emptyLabel.Text = "No Patrons yet -- buy some in the Buy Patrons tab!"
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

	return {
		shopFrame = shopFrame,
		nextRoundButton = nextRoundButton,
		rebuildShop = rebuildShop,
		rebuildMyPatronsTab = rebuildMyPatronsTab,
	}
end
