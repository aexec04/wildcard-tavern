--[[
	Client/Collection.lua
	The Collection screen (parchment panel), opened from the "📔" corner
	button. It opens on a gallery room (Client/CollectionRoom.lua): six objects
	on its walls, one per section -- Patrons, Recipes, Boss Rounds, House
	Passes, Titles, Bonds -- each a hotspot with a name plate and its count.
	A click zooms into that section's furniture (the scroll and grid); the
	"< Gallery" plate in the quiet row of small tab plates, or Escape, goes
	back. An overall % bar shows the next milestone reward, and the rarity
	filter is a small wooden plate above Close. Engine/CollectionRoomLayout.lua
	holds the panel's vertical order and the room's hotspot rects (tested).

	All content and rules come from Shared/Engine/CollectionBook.lua, which
	reads the registries. Nothing here lists content by hand.

	Tiles: every entry of the section is drawn. Discovered entries show their
	icon, name and a glow in their rarity's color; locked ones are a dim
	silhouette with their name on the plate (never "???", never a blank note).
	Tapping a tile opens a detail card with the effect text and flavor
	line. A Title's detail card has the Equip button (fires EquipTitle;
	clicking the equipped title's button un-equips it).

	Data comes from the server's state push:
	  state.collection = { discovered = { [tabId] = {id...} },
	                       claimedMilestoneIds = {id...}, unlockedCardBackIds = {id...} }
	  state.unlockedAchievementIds  -- the Titles tab's "discovered" list
	  state.equippedTitleId, state.profileStats
	  state.collectionMilestoneNotice -- one-shot milestone ids, shown as a toast

	This module listens to StateUpdatedRemote itself (with task.defer, so
	init.client.lua's render() has already updated latestState) instead of
	returning a refresh function -- init.client.lua has no spare locals.

	deps: screenGui, polishPanel, polishButton, roundCorner, addSoftShadow,
	playClickSfx, collectionButton, Achievements, EquipTitleRemote,
	getLatestState, popIn, popOut, addButtonHoverScale, StateUpdatedRemote.

	A hidden "Card Sets" button (the Tome tab and Menu open it) opens CosmeticSetsPanel.lua (equip
	and buy cosmetic sets).

	Returns: {}
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

return function(deps)
	local screenGui = deps.screenGui
	local polishPanel = deps.polishPanel
	local polishButton = deps.polishButton
	local roundCorner = deps.roundCorner
	local addSoftShadow = deps.addSoftShadow
	local playClickSfx = deps.playClickSfx
	local Achievements = deps.Achievements
	local EquipTitleRemote = deps.EquipTitleRemote
	local getLatestState = deps.getLatestState
	local popIn = deps.popIn
	local popOut = deps.popOut
	local addButtonHoverScale = deps.addButtonHoverScale
	local addTooltip = deps.addTooltip -- the shared hover tooltip: tiles show the effect text there
	local OverlayManager = require(script.Parent.OverlayManager)
	local PatronPlaqueModule = require(script.Parent.PatronPlaque)
	local Engine = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine")
	local CollectionBook = require(Engine:WaitForChild("CollectionBook"))
	local ContentArt = require(Engine:WaitForChild("ContentArt"))
	local SceneLayout = require(Engine:WaitForChild("CollectionSceneLayout"))
	local RarityFrame = require(script.Parent.RarityFrame)
	local ClientSettings = require(script.Parent.ClientSettings)
	local StageMotion = require(Engine:WaitForChild("StageMotion"))
	local RoomLayout = require(Engine:WaitForChild("CollectionRoomLayout")) -- the panel's vertical order and the gallery room's hotspots

	local CREAM = Color3.fromRGB(250, 240, 220)
	local SOFT_CREAM = Color3.fromRGB(215, 200, 178)
	local GOLD = Color3.fromRGB(255, 214, 130)
	local DIM = Color3.fromRGB(140, 130, 120)
	local BUTTON_BROWN = Color3.fromRGB(70, 55, 40)
	local ACTIVE_BROWN = Color3.fromRGB(150, 115, 50)
	local ITALIC = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Regular, Enum.FontStyle.Italic)
	-- Boss Rounds have no icon of their own.
	local FALLBACK_ICONS = { bosses = "⚡" }

	local function rgb(triple)
		return Color3.fromRGB(triple[1], triple[2], triple[3])
	end

	local function label(parent, props)
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Font = Enum.Font.Gotham
		l.TextColor3 = CREAM
		l.TextStrokeTransparency = 1
		l.ZIndex = 21
		for k, v in pairs(props) do
			l[k] = v
		end
		l.Parent = parent
		return l
	end

	local function button(parent, props)
		local b = Instance.new("TextButton")
		b.Font = Enum.Font.GothamBold
		b.TextColor3 = CREAM
		b.BackgroundColor3 = BUTTON_BROWN
		b.AutoButtonColor = true
		b.ZIndex = 21
		for k, v in pairs(props) do
			b[k] = v
		end
		b.Parent = parent
		return b
	end

	-- ===== Panel =====
	local backdrop = Instance.new("Frame")
	backdrop.Name = "CollectionBackdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	backdrop.BackgroundTransparency = 0.4
	backdrop.Visible = false
	backdrop.ZIndex = 20
	backdrop.Parent = screenGui

	local PANEL_SIZE = UDim2.fromScale(0.66, 0.78)
	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Size = PANEL_SIZE
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.BackgroundColor3 = Color3.fromRGB(40, 30, 22)
	panel.ZIndex = 21
	panel.Parent = backdrop
	polishPanel(panel, 16, "parchment")
	addSoftShadow(panel, 18)
	-- Painted alcove behind everything; a dark scrim keeps the tile grid readable.
	require(script.Parent.PanelArt).add(panel, {
		key = "collection_bg",
		scrim = { position = UDim2.fromOffset(15, 138), size = UDim2.new(1, -30, 1, -196) },
	})

	-- Gallery back wall (Client/CollectionWall.lua): mounts only once the collection_scene Image ids are recorded.
	local Gallery = require(script.Parent.CollectionGallery)
	-- Per-cell furniture (Client/CollectionFurniture.lua). Always a table: if the require fails, kind() is nil and every tab draws plain cells.
	local Furn
	do
		local okFurn, mod = pcall(require, script.Parent.CollectionFurniture)
		Furn = okFurn and type(mod) == "table" and mod or { kind = function() return nil end }
	end
	-- The tab on screen: its items, the furniture records of the tiles built (for refurnish below) and its furniture kind (nil = plain
	-- tiles). refresh() sets them; makeTile, furnCols and refurnish read them. They were never declared, so they were accidental globals.
	local currentItems, furnRecords, currentKind, lastFurnCols = {}, {}, nil, nil
	pcall(function()
		local wall = require(script.Parent.CollectionWall).mount(panel)
		if wall then Gallery.mountAlive(wall, panel, backdrop) end -- lantern flicker and the moth (off in calm mode)
	end)

	-- No title sign: the active sub tab already says Collection, and the plate used to cover the tab row and the progress bar.
	local titleLabel = label(panel, {
		Size = UDim2.new(1, 0, 0, 28), Position = UDim2.fromOffset(0, 6),
		Font = Enum.Font.GothamBold, TextSize = 22, Text = "Collection", Visible = false,
	})
	pcall(function() require(script.Parent.ConceptTSkin).title(titleLabel) end) -- serif cream with a dark outline (hidden: the active sub tab names the page)

	local expandToggle = require(script.Parent.ExpandToggle)(panel, {
		collapsedSize = PANEL_SIZE,
		polishButton = polishButton,
		addButtonHoverScale = addButtonHoverScale,
		playClickSfx = playClickSfx,
	})

	if expandToggle.button then expandToggle.button.Visible = false end -- the Collection is always full screen (Client/PanelFullScreen), so no expand arrow
	-- Card Sets (cosmetic card back + backdrop) live in their own panel.
	local setsButton = button(panel, {
		Size = UDim2.fromOffset(104, 28), Position = UDim2.fromOffset(15, 4),
		TextSize = 14, Text = "Card Sets",
	})
	polishButton(setsButton, 8)
	setsButton.Visible = false -- navigation lives in PanelTabs (Tome > Card Sets) and the Menu; the panel still opens via its opener
	require(script.Parent.CosmeticSetsPanel)({
		screenGui = screenGui,
		polishPanel = polishPanel,
		polishButton = polishButton,
		roundCorner = roundCorner,
		addSoftShadow = addSoftShadow,
		playClickSfx = playClickSfx,
		openButton = setsButton,
		collectionButton = deps.collectionButton,
		getLatestState = getLatestState,
		popIn = popIn,
		popOut = popOut,
		addButtonHoverScale = addButtonHoverScale,
		StateUpdatedRemote = deps.StateUpdatedRemote,
	})

	-- Badges (earned collectibles, one can be equipped beside your name) have their own shelf panel.
	do -- (a do-block keeps this chunk's local count down)
		local badgesButton = button(panel, {
			Size = UDim2.fromOffset(104, 28), Position = UDim2.fromOffset(125, 4),
			TextSize = 14, Text = "Badges",
		})
		polishButton(badgesButton, 8)
			badgesButton.Visible = false -- navigation lives in PanelTabs; panels still open via their openers
		require(script.Parent.LazyPanel).wrap("badges", require(script.Parent.BadgesPanel))({
			screenGui = screenGui,
			polishPanel = polishPanel,
			polishButton = polishButton,
			roundCorner = roundCorner,
			addSoftShadow = addSoftShadow,
			playClickSfx = playClickSfx,
			openButton = badgesButton,
			addTooltip = addTooltip,
			getLatestState = getLatestState,
			popIn = popIn,
			popOut = popOut,
			addButtonHoverScale = addButtonHoverScale,
			StateUpdatedRemote = deps.StateUpdatedRemote,
		})
	end

	-- Collection completion rewards (rings and 25/50/75/100 percent milestones) open from a fourth header button.
	do
		local rewardsButton = button(panel, {
			Size = UDim2.fromOffset(104, 28), Position = UDim2.fromOffset(345, 4),
			TextSize = 14, Text = "Rewards",
		})
		polishButton(rewardsButton, 8)
			rewardsButton.Visible = false -- navigation lives in PanelTabs; panels still open via their openers
		require(script.Parent.CollectionRewardsPanel).init({
			screenGui = screenGui,
			polishPanel = polishPanel,
			polishButton = polishButton,
			roundCorner = roundCorner,
			addSoftShadow = addSoftShadow,
			playClickSfx = playClickSfx,
			openButton = rewardsButton,
			addTooltip = addTooltip,
			getLatestState = getLatestState,
			popIn = popIn,
			popOut = popOut,
			addButtonHoverScale = addButtonHoverScale,
			StateUpdatedRemote = deps.StateUpdatedRemote,
		})
	end

	-- Flair (score numbers, play trail, finisher, name aura) opens from a sixth header button.
	do
		local flairButton = button(panel, {
			Size = UDim2.fromOffset(104, 28), Position = UDim2.fromOffset(565, 4),
			TextSize = 14, Text = "Flair",
		})
		polishButton(flairButton, 8)
			flairButton.Visible = false -- navigation lives in PanelTabs; panels still open via their openers
		require(script.Parent.LazyPanel).wrap("flair", require(script.Parent.FlairPanel).init)({
			screenGui = screenGui,
			polishPanel = polishPanel,
			polishButton = polishButton,
			roundCorner = roundCorner,
			addSoftShadow = addSoftShadow,
			playClickSfx = playClickSfx,
			openButton = flairButton,
			addTooltip = addTooltip,
			getLatestState = getLatestState,
			popIn = popIn,
			popOut = popOut,
			addButtonHoverScale = addButtonHoverScale,
			StateUpdatedRemote = deps.StateUpdatedRemote,
			particleBurst = deps.particleBurst,
		})
	end

	-- Legend prestige (levels after stake 8, cosmetic rewards) opens from a fifth header button.
	do
		local legendButton = button(panel, {
			Size = UDim2.fromOffset(104, 28), Position = UDim2.fromOffset(455, 4),
			TextSize = 14, Text = "Legend",
		})
		polishButton(legendButton, 8)
			legendButton.Visible = false -- navigation lives in PanelTabs; panels still open via their openers
		require(script.Parent.LegendPanel).init({
			screenGui = screenGui,
			polishPanel = polishPanel,
			polishButton = polishButton,
			roundCorner = roundCorner,
			addSoftShadow = addSoftShadow,
			playClickSfx = playClickSfx,
			openButton = legendButton,
			addTooltip = addTooltip,
			getLatestState = getLatestState,
			popIn = popIn,
			popOut = popOut,
			addButtonHoverScale = addButtonHoverScale,
			StateUpdatedRemote = deps.StateUpdatedRemote,
		})
	end

	-- Tavern Stats (run history and lifetime numbers) opens from a third header button.
	do
		local statsButton = button(panel, {
			Size = UDim2.fromOffset(104, 28), Position = UDim2.fromOffset(235, 4),
			TextSize = 14, Text = "Stats",
		})
		polishButton(statsButton, 8)
			statsButton.Visible = false -- navigation lives in PanelTabs; panels still open via their openers
		require(script.Parent.LazyPanel).wrap("stats", require(script.Parent.StatsPanel))({
			screenGui = screenGui,
			polishPanel = polishPanel,
			polishButton = polishButton,
			roundCorner = roundCorner,
			addSoftShadow = addSoftShadow,
			playClickSfx = playClickSfx,
			openButton = statsButton,
			addTooltip = addTooltip,
			getLatestState = getLatestState,
			popIn = popIn,
			popOut = popOut,
			addButtonHoverScale = addButtonHoverScale,
			StateUpdatedRemote = deps.StateUpdatedRemote,
		})
	end

	-- Run numbers (runs, wins, best Night, title) live in the Tavern Ledger (StatsPanel); Collection shows collection progress only.

	-- Overall completion bar + next milestone.
	local overallBar = Instance.new("Frame")
	overallBar.Size = UDim2.new(1, -(15 + 56), 0, RoomLayout.BAR.h) -- 56 px on the right stay clear of the round close X
	overallBar.Position = UDim2.fromOffset(15, RoomLayout.BAR.y)
	overallBar.BackgroundColor3 = Color3.fromRGB(35, 26, 18)
	overallBar.ZIndex = 21
	overallBar.Parent = panel
	roundCorner(overallBar, 6)
	do -- the progress line sits on a brass-edged plaque under the sign (dark inside, so the text keeps its contrast)
		local plaque = Instance.new("UIStroke")
		plaque.Color = Color3.fromRGB(190, 146, 64)
		plaque.Thickness = 2
		plaque.Parent = overallBar
	end

	local overallFill = Instance.new("Frame")
	overallFill.Size = UDim2.fromScale(0, 1)
	overallFill.BackgroundColor3 = Color3.fromRGB(190, 145, 60)
	overallFill.ZIndex = 22
	overallFill.Parent = overallBar
	roundCorner(overallFill, 6)

	-- Line one: Overall on the left, the next milestone on the right. Line two: the next unlock. 15 px cream, never truncated.
	local BAR_PAD = RoomLayout.BAR_PAD -- 16 px inside the plate on both sides
	local function barLine(y, align, width)
		return label(overallBar, {
			Size = UDim2.new(width, width >= 1 and -2 * BAR_PAD or -BAR_PAD, 0.5, 0), Position = UDim2.new(align == Enum.TextXAlignment.Right and 1 - width or 0, align == Enum.TextXAlignment.Right and 0 or BAR_PAD, y, 0),
			Font = Enum.Font.GothamBold, TextSize = 15, ZIndex = 23, TextWrapped = false,
			TextColor3 = Color3.fromRGB(245, 232, 200), TextTransparency = 0, TextStrokeTransparency = 1,
			TextXAlignment = align, Text = "",
		})
	end
	local overallText = barLine(0, Enum.TextXAlignment.Left, 0.3)
	local overallNext = barLine(0, Enum.TextXAlignment.Right, 0.7)
	local overallUnlock = barLine(0.5, Enum.TextXAlignment.Left, 1)

	-- Tabs: the gallery room is the way in, so these are only a quiet row of small plates (for the keyboard and for phones). They scroll
	-- sideways when the panel is narrower than the row.
	local tabRow = Instance.new("ScrollingFrame")
	tabRow.Name = "QuietTabs"
	tabRow.Size = UDim2.new(1, -30, 0, RoomLayout.TABS.h)
	tabRow.Position = UDim2.fromOffset(RoomLayout.SIDE, RoomLayout.TABS.y)
	tabRow.BackgroundTransparency = 1
	tabRow.BorderSizePixel = 0
	tabRow.ScrollBarThickness = 0
	tabRow.ScrollingDirection = Enum.ScrollingDirection.X
	tabRow.AutomaticCanvasSize = Enum.AutomaticSize.X
	tabRow.CanvasSize = UDim2.new(0, 0, 0, 0)
	tabRow.ZIndex = 21
	tabRow.Parent = panel

	local tabLayout = Instance.new("UIListLayout")
	tabLayout.FillDirection = Enum.FillDirection.Horizontal
	tabLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	tabLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
	tabLayout.Padding = UDim.new(0, 6)
	tabLayout.Parent = tabRow

	-- Rarity filter: one swatch + name per tier, in order, on a small wooden plate at the bottom (relayout() places it above Close).
	local legendRow = Instance.new("Frame")
	legendRow.Name = "RarityLegend"
	legendRow.AnchorPoint = Vector2.new(0.5, 1)
	legendRow.Size = UDim2.fromOffset(RoomLayout.FILTER_MAX_W, 32)
	legendRow.Position = UDim2.new(0.5, 0, 1, -RoomLayout.FOOTER)
	legendRow.BackgroundColor3 = Color3.fromRGB(62, 42, 26)
	legendRow.BackgroundTransparency = 0
	legendRow.BorderSizePixel = 0
	legendRow.ZIndex = 21
	legendRow.Parent = panel
	roundCorner(legendRow, 8)
	do
		local rim = Instance.new("UIStroke")
		rim.Color = Color3.fromRGB(196, 156, 74)
		rim.Thickness = 1.5
		rim.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		rim.Parent = legendRow
		local pad = Instance.new("UIPadding")
		pad.PaddingTop = UDim.new(0, RoomLayout.FILTER_PAD)
		pad.PaddingBottom = UDim.new(0, RoomLayout.FILTER_PAD)
		pad.PaddingLeft = UDim.new(0, 8)
		pad.PaddingRight = UDim.new(0, 8)
		pad.Parent = legendRow
	end
	local legendLayout = Instance.new("UIListLayout")
	legendLayout.FillDirection = Enum.FillDirection.Horizontal
	legendLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	legendLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	legendLayout.SortOrder = Enum.SortOrder.LayoutOrder
	legendLayout.Padding = UDim.new(0, 14)
	legendLayout.Wraps = true -- on a narrow panel the chips wrap onto a second line instead of running off the edge
	legendLayout.Parent = legendRow
	-- Each chip is a toggle: click to hide/show that tier in the grid.
	local hiddenRarities = {}
	local refresh -- assigned below; chips call it
	for i, rarityId in ipairs(CollectionBook.RarityOrder) do
		local tierColor = rgb(CollectionBook.Rarities[rarityId].color)
		local chip = Instance.new("TextButton")
		chip.Name = "Chip_" .. rarityId
		chip.Text = ""
		chip.AutoButtonColor = false
		chip.LayoutOrder = i
		chip.AutomaticSize = Enum.AutomaticSize.X
		chip.Size = UDim2.fromOffset(0, require(Engine:WaitForChild("CollectionCards")).CHIP_H) -- a 44 px touch target
		chip.BackgroundTransparency = 1
		chip.ZIndex = 21
		chip.Parent = legendRow
		local swatch = Instance.new("Frame")
		swatch.Size = UDim2.fromOffset(16, 16)
		swatch.Position = UDim2.new(0, 0, 0.5, -8)
		swatch.BackgroundColor3 = tierColor
		swatch.ZIndex = 22
		swatch.Parent = chip
		roundCorner(swatch, 4)
		RarityFrame.apply(swatch, rarityId, { ringOnly = true, thickness = 2 })
		local check = label(swatch, {
			Size = UDim2.fromScale(1, 1), Font = Enum.Font.GothamBold, TextSize = 15,
			TextColor3 = Color3.fromRGB(30, 22, 14), ZIndex = 24, Text = "✓",
		})
		local name = label(chip, {
			AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromScale(0, 1), Position = UDim2.fromOffset(22, 0),
			Font = Enum.Font.GothamBold, TextSize = 15, TextColor3 = SOFT_CREAM,
			Text = CollectionBook.Rarities[rarityId].name,
		})
		local function paint()
			local on = not hiddenRarities[rarityId]
			-- unchecked: dark swatch, no tick, dim name (the ring keeps the tier color)
			swatch.BackgroundColor3 = on and tierColor or Color3.fromRGB(34, 26, 18)
			check.Visible = on
			name.TextColor3 = on and SOFT_CREAM or Color3.fromRGB(176, 164, 148) -- an unchecked tier is dimmer but still 5:1 on the wooden plate
		end
		paint()
		chip.MouseButton1Click:Connect(function()
			playClickSfx()
			hiddenRarities[rarityId] = (not hiddenRarities[rarityId]) or nil
			paint()
			if refresh then refresh() end
		end)
	end

	local furniture = Gallery.mountFurniture(panel) -- the tab's painted board or shelf, behind the grid (made before it)
	Gallery.chestApi = Gallery.mountChest(panel) -- milestone chest on the floor, bottom right
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "SectionGrid"
	scroll.Size = UDim2.new(1, -30, 1, -196)
	scroll.Position = UDim2.fromOffset(15, 138)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 8
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.ZIndex = 21
	scroll.Parent = panel
	furniture.follow(scroll)

	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(92, 108)
	grid.CellPadding = UDim2.fromOffset(10, 10)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.HorizontalAlignment = Enum.HorizontalAlignment.Center
	grid.Parent = scroll

	-- Grid cells need a little inset so the rarity stroke isn't clipped.
	local gridPadding = Instance.new("UIPadding")
	gridPadding.PaddingTop = UDim.new(0, 4)
	gridPadding.PaddingBottom = UDim.new(0, 4)
	gridPadding.Parent = scroll

	-- ===== The gallery room: the way into the Collection =====
	-- The room is the first view. A click on one of its six objects zooms into that section's furniture (the scroll and grid above), and
	-- the "< Gallery" plate or Escape returns. mode is "room" or "section"; showSection / showRoom are assigned below the tab plates.
	local mode = "room"
	local showSection, showRoom
	local room
	local Sec = { painted = false } -- the painted section scene (Client/CollectionSection.lua, built below the detail card); painted = it is on screen
	do
		local names = {}
		for _, tab in ipairs(CollectionBook.Tabs) do names[tab.id] = tab.name end
		room = require(script.Parent.CollectionRoom).new({
			parent = panel, names = names, zIndex = 22,
			onPick = function(tabId)
				playClickSfx()
				showSection(tabId)
			end,
		})
	end

	-- ===== Responsive layout (narrow windows and phones) =====
	-- The panel grows toward the full width as the window narrows (Engine/ResponsiveLayout), the title steps aside of the Card Sets /
	-- Badges buttons, and the rarity chips wrap on their wooden plate. Engine/CollectionRoomLayout.panel gives the vertical order: the
	-- room and the section grid fill the area between the quiet tab row and the plate.
	local ResponsiveLayout = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("ResponsiveLayout"))
	local FullScreen = require(script.Parent.PanelFullScreen)
	local function relayout()
		local cam = workspace.CurrentCamera
		local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
		local fit = ResponsiveLayout.collectionPanel(vp.X, vp.Y)
		-- the responsive size is the collapsed size; while expanded the toggle owns Size (resetting it here undid the tween)
		expandToggle.setCollapsedSize(UDim2.fromScale(fit.w, fit.h))
		-- PanelFullScreen owns the size of the full screen panel: writing the windowed size here fought it on every AbsoluteSize change
		-- (this was the wrong size source: the layout below measured the transient 66 percent panel and painted at that size)
		if panel:GetAttribute("Expanded") ~= true then
			FullScreen.setRect(panel, UDim2.fromScale(fit.w, fit.h))
		end
		local fullW, fullH = FullScreen.fit(panel, vp.X * fit.w, vp.Y * fit.h, vp.X, vp.Y)
		local panelW = panel.AbsoluteSize.X > 0 and panel.AbsoluteSize.X or fullW
		local panelH = panel.AbsoluteSize.Y > 0 and panel.AbsoluteSize.Y or fullH
		local head = ResponsiveLayout.collectionTitle(panelW)
		titleLabel.Position = UDim2.fromOffset(head.x, 6)
		titleLabel.Size = head.fullWidth and UDim2.new(1, 0, 0, 28) or UDim2.fromOffset(head.w, 28)
		local legendH = math.max(24, math.ceil(legendLayout.AbsoluteContentSize.Y))
		local chest = Gallery.chestApi and SceneLayout.chest(panelW, panelH) or nil
		local P = RoomLayout.panel(panelW, panelH, legendH, chest and chest.x or nil, mode)
		local chrome = RoomLayout.chrome(mode)
		tabRow.Visible, legendRow.Visible = chrome.tabs, chrome.rarityFilter
		tabRow.Position, tabRow.Size = UDim2.fromOffset(P.tabs.x, P.tabs.y), UDim2.fromOffset(P.tabs.w, P.tabs.h)
		legendRow.Size = UDim2.fromOffset(P.filter.w, P.filter.h)
		legendRow.Position = UDim2.new(0.5, 0, 1, -RoomLayout.FOOTER)
		-- bottom inset, not a height: the area follows the panel while it is resized or expanded between two layouts
		local inset = panelH - (P.area.y + P.area.h)
		scroll.Position = UDim2.fromOffset(P.area.x, P.area.y)
		scroll.Size = UDim2.new(1, -2 * P.area.x, 1, -(P.area.y + inset))
		room.frame.Position, room.frame.Size = scroll.Position, scroll.Size
		room.layout(P.area.w, P.area.h)
		if Sec.scene then -- the painted section follows the same area; a window that changes what fits swaps it with the old grid
			Sec.scene.frame.Position, Sec.scene.frame.Size = scroll.Position, scroll.Size
			Sec.scene.setPager(P.pager)
			Sec.scene.layout(P.area.w, P.area.h)
			if mode == "section" and Sec.refit then Sec.refit() end
		end
		local back = panel:FindFirstChild("PanelScrim") -- the painted alcove's dark wash behind the grid follows the same area
		if back then back.Position, back.Size = scroll.Position, scroll.Size end
	end
	legendLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(relayout)
	panel:GetPropertyChangedSignal("AbsoluteSize"):Connect(relayout)
	do
		local cam = workspace.CurrentCamera
		if cam then cam:GetPropertyChangedSignal("ViewportSize"):Connect(relayout) end
	end
	relayout()

	local closeButton = button(panel, {
		Size = UDim2.fromOffset(140, 40), Position = UDim2.new(0.5, -70, 1, -50),
		TextSize = 16, Text = "Close", BackgroundColor3 = Color3.fromRGB(90, 60, 30),
	})
	polishButton(closeButton, 12)
	addButtonHoverScale(closeButton)
	require(script.Parent.CloseX).retire(closeButton)
	require(script.Parent.CloseX).attach(panel, function()
		playClickSfx()
		popOut(backdrop, panel)
	end)

	-- ===== Detail card =====
	-- `detailShade` covers the panel; hiding it hides the card too.
	local detailShade = Instance.new("TextButton")
	detailShade.Name = "DetailShade"
	detailShade.Text = ""
	detailShade.AutoButtonColor = false
	detailShade.Size = UDim2.fromScale(1, 1)
	detailShade.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	detailShade.BackgroundTransparency = 0.35
	detailShade.Visible = false
	detailShade.ZIndex = 30
	detailShade.Parent = panel
	roundCorner(detailShade, 16)
	pcall(require(script.Parent.ModalStage).mount, detailShade, "detail") -- pinned card on a cork wall + modal gate

	local card = Instance.new("TextButton") -- a button so clicks on it don't close it
	card.Text = ""
	card.AutoButtonColor = false
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.5)
	-- Art-first layout: a big 2:3 portrait on the left in a rarity frame with
	-- the name banner overlapping its bottom edge; the effect strip, flavor
	-- text and buttons sit to the right. The card is sized to its content.
	local INK = Color3.fromRGB(60, 40, 22)
	local CARD_W, CARD_H = 600, 420
	local PORTRAIT_W, PORTRAIT_H = 230, 345
	card.Size = UDim2.fromOffset(CARD_W, CARD_H)
	card.BackgroundColor3 = Color3.fromRGB(222, 198, 150)
	card.ZIndex = 31
	card.Parent = detailShade
	polishPanel(card, 14, "parchment")
	local cardSize = Instance.new("UISizeConstraint")
	cardSize.MaxSize = Vector2.new(CARD_W, CARD_H)
	cardSize.Parent = card

	local portrait = Instance.new("Frame")
	portrait.Name = "Portrait"
	portrait.Position = UDim2.fromOffset(22, 22)
	portrait.Size = UDim2.fromOffset(PORTRAIT_W, PORTRAIT_H)
	portrait.BackgroundColor3 = Color3.fromRGB(34, 26, 18)
	portrait.ClipsDescendants = true
	portrait.ZIndex = 32
	portrait.Parent = card
	roundCorner(portrait, 10)
	local cardIcon = label(portrait, {
		Size = UDim2.fromScale(1, 1), TextSize = 96, ZIndex = 33, Text = "",
	})

	local cardName = label(card, {
		Size = UDim2.fromOffset(PORTRAIT_W + 24, 36), Position = UDim2.fromOffset(22 - 12, 22 + PORTRAIT_H - 18),
		BackgroundTransparency = 0, BackgroundColor3 = Color3.fromRGB(58, 40, 26),
		Font = Enum.Font.GothamBold, TextSize = 18, ZIndex = 36, TextWrapped = true, Text = "",
		TextColor3 = CREAM,
	})
	roundCorner(cardName, 6)
	local bannerStroke = Instance.new("UIStroke")
	bannerStroke.Color = Color3.fromRGB(222, 182, 104)
	bannerStroke.Thickness = 1.5
	bannerStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	bannerStroke.Parent = cardName

	local RIGHT_X = 22 + PORTRAIT_W + 24
	local RIGHT_W = CARD_W - RIGHT_X - 22
	local cardKind = label(card, {
		Size = UDim2.fromOffset(RIGHT_W, 28), Position = UDim2.fromOffset(RIGHT_X, 22),
		BackgroundTransparency = 0, BackgroundColor3 = Color3.fromRGB(58, 40, 26),
		Font = Enum.Font.GothamBold, TextSize = 16, ZIndex = 32, Text = "",
	})
	roundCorner(cardKind, 14)
	local effectStrip = Instance.new("Frame")
	effectStrip.Position = UDim2.fromOffset(RIGHT_X, 62)
	effectStrip.Size = UDim2.fromOffset(RIGHT_W, 118)
	effectStrip.BackgroundColor3 = Color3.fromRGB(199, 178, 137)
	effectStrip.ZIndex = 32
	effectStrip.Parent = card
	roundCorner(effectStrip, 8)
	local effectStripStroke = Instance.new("UIStroke")
	effectStripStroke.Color = Color3.fromRGB(120, 88, 56)
	effectStripStroke.Thickness = 1.5
	effectStripStroke.Parent = effectStrip
	local cardEffect = label(effectStrip, {
		Size = UDim2.new(1, -20, 1, -12), Position = UDim2.fromOffset(10, 6),
		Font = Enum.Font.GothamBold, TextSize = 18, ZIndex = 33, TextWrapped = true,
		TextColor3 = INK, TextYAlignment = Enum.TextYAlignment.Center, Text = "",
	})
	local cardFlavor = label(card, {
		Size = UDim2.fromOffset(RIGHT_W, 100), Position = UDim2.fromOffset(RIGHT_X, 192),
		TextSize = 15, ZIndex = 32, TextWrapped = true, TextColor3 = INK,
		FontFace = ITALIC, TextYAlignment = Enum.TextYAlignment.Top, Text = "",
	})
	local cardEquip = button(card, {
		Size = UDim2.fromOffset(120, 38), Position = UDim2.new(0, RIGHT_X, 1, -62),
		TextSize = 16, ZIndex = 32, Text = "Equip", Visible = false,
	})
	polishButton(cardEquip, 8)
	local cardClose = button(card, {
		Size = UDim2.fromOffset(120, 38), Position = UDim2.new(0, RIGHT_X, 1, -62),
		TextSize = 16, ZIndex = 32, Text = "Back",
	})
	polishButton(cardClose, 8)
	-- Compatibility handle: showDetail recolors this with the rarity.
	local cardStroke = card:FindFirstChildOfClass("UIStroke")

	-- ===== Milestone toast =====
	local toast = Instance.new("Frame")
	toast.AnchorPoint = Vector2.new(0.5, 0)
	toast.Position = UDim2.new(0.5, 0, 0, 70)
	toast.Size = UDim2.fromOffset(420, 64)
	toast.BackgroundColor3 = Color3.fromRGB(40, 30, 22)
	toast.Visible = false
	toast.ZIndex = 60
	toast.Parent = screenGui
	polishPanel(toast, 12, "parchment")
	local toastText = label(toast, {
		Size = UDim2.new(1, -24, 1, -8), Position = UDim2.fromOffset(12, 4),
		Font = Enum.Font.GothamBold, TextSize = 14, TextWrapped = true, ZIndex = 61,
		TextColor3 = GOLD, Text = "",
	})

	-- ===== State =====
	local activeTabId = CollectionBook.Tabs[1].id
	local tabButtons = {}
	local openItem = nil -- the item shown on the detail card, if any

	local function currentView()
		local state = getLatestState()
		local collection = state and state.collection or {}
		local lists = {}
		for tabId, ids in pairs(collection.discovered or {}) do
			lists[tabId] = ids
		end
		lists.titles = state and state.unlockedAchievementIds or {}
		local claimed = {}
		for _, id in ipairs(collection.claimedMilestoneIds or {}) do
			claimed[id] = true
		end
		local sets = CollectionBook.setsFromLists(lists)
		return {
			state = state,
			sets = sets,
			completion = CollectionBook.completion(sets),
			claimed = claimed,
			equippedTitleId = state and state.equippedTitleId,
		}
	end

	local function iconFor(item)
		return item.def.icon or FALLBACK_ICONS[item.tab] or "❔"
	end

	-- The name a tile or a plate shows. Locked entries keep their name: a dim silhouette with its name on the plate, never "???".
	local function shownName(item)
		return tostring(item.tab == "titles" and item.def.title or item.def.name)
	end

	local function milestoneFor(titleId)
		for _, milestone in ipairs(CollectionBook.Milestones) do
			for _, reward in ipairs(milestone.rewards) do
				if reward.kind == "title" and reward.id == titleId then
					return milestone
				end
			end
		end
		return nil
	end

	-- UNLOCK DRIP: gated Patrons and Recipes that are still closed carry a short "how to open" hint (state.unlockHints).
	local HINT_KIND = { patrons = "patron", recipes = "recipe", housePasses = "housePass" }
	local function unlockRuleHint(item, view)
		local hints = view and view.state and view.state.unlockHints
		local kind = HINT_KIND[item.tab]
		return hints and kind and hints[kind] and hints[kind][item.id] or nil
	end

	local function undiscoveredHint(item, view)
		local ruleHint = unlockRuleHint(item, view)
		if ruleHint then
			return "Locked. " .. ruleHint
		end
		if item.tab == "titles" then
			local milestone = item.def.milestoneReward and milestoneFor(item.id)
			if milestone then
				return "Reach " .. milestone.percent .. "% Collection completion to earn this title."
			end
			return "Not unlocked yet. Keep playing to earn this title."
		elseif item.tab == "bosses" then
			return "Not discovered yet. Face this boss on a Boss Round to add it."
		end
		return "Not discovered yet. Spot it in the shop or a pack to add it."
	end

	local cardFloat = nil -- RBXScriptConnection: the detail card's levitation (only while the card is open)
	local function showDetail(item, view)
		openItem = item
		local found = CollectionBook.isDiscovered(view.sets, item)
		local rarity = CollectionBook.Rarities[CollectionBook.rarityOf(item)]
		local def = item.def

		cardIcon.Text = iconFor(item)
		cardIcon.Visible = true
		cardIcon.TextTransparency = found and 0 or 0.55
		cardIcon.TextStrokeTransparency = 1
		local rarityId = CollectionBook.rarityOf(item)
		cardStroke.Color = RarityFrame.colorFor(rarityId)
		cardKind.TextColor3 = found and CREAM or DIM
		cardKind.BackgroundColor3 = found and rgb(rarity.color):Lerp(Color3.fromRGB(30, 22, 16), 0.45) or Color3.fromRGB(58, 40, 26)
		RarityFrame.apply(portrait, rarityId, { thickness = 4, radius = 10, locked = not found, zIndex = 38 })

		-- Portrait art: Crop fills the whole 2:3 frame.
		local prevArt = portrait:FindFirstChild("ContentDetailArt")
		if prevArt then prevArt:Destroy() end
		do
			local artId = ContentArt.getImageId(item.tab, (not found and item.tab == "bonds") and "bond_locked" or item.id)
			local detailArt = artId and PatronPlaqueModule.applyById(portrait, artId, {
				emojiLabel = cardIcon,
				fade = true,
				dim = not found,
				zIndex = 33,
				cornerRadius = 10,
				category = item.tab,
			})
			if detailArt then
				detailArt.Name = "ContentDetailArt"
				detailArt.ScaleType = Enum.ScaleType.Crop
			end
			-- a discovered Patron shows its large Concept T cut card (frame, gem and name plate are in the picture)
			local CC = require(Engine:WaitForChild("CollectionCards"))
			local cutOk = CC.useCutCard(item.tab, found, require(Engine:WaitForChild("ConceptTPatronArt"))["ctp_" .. tostring(item.id)] ~= nil)
			if cutOk then
				local cut = PatronPlaqueModule.apply(portrait, item.id, { cornerRadius = 10, zIndex = 34, fade = true })
				if cut then
					cut.Name = "ContentDetailArt"
					cut.ScaleType = Enum.ScaleType.Fit
					if detailArt then detailArt:Destroy() end
				end
			end
		end
		-- (a locked entry reads as locked from its dim portrait and the "Locked." line below; no padlock emoji)

		if found then
			cardName.Text = item.tab == "titles" and ('"' .. def.title .. '"') or def.name
			cardKind.Text = rarity.name .. " " .. CollectionBook.kindLabel(item)
			local effect = def.description
			if item.tab == "titles" then
				local milestone = def.milestoneReward and milestoneFor(item.id)
				effect = milestone and ("Reward for reaching " .. milestone.percent .. "% Collection completion.")
					or (def.name .. ": " .. def.description)
			end
			cardEffect.Text = effect
			cardFlavor.Text = def.flavorText and ('"' .. def.flavorText .. '"') or ""
			if item.tab == "patrons" then -- synergy tags, so a Patron's detail says what it works with
				local line = require(Engine:WaitForChild("CollectionCards")).synergyLine(item.id)
				if line ~= "" then cardFlavor.Text = (cardFlavor.Text ~= "" and (cardFlavor.Text .. "\n") or "") .. line end
			end
		else
			cardName.Text = shownName(item)
			cardKind.Text = rarity.name .. " " .. CollectionBook.kindLabel(item)
			cardEffect.Text = undiscoveredHint(item, view)
			cardFlavor.Text = ""
		end

		local canEquip = found and item.tab == "titles"
		cardEquip.Visible = canEquip
		cardClose.Position = UDim2.new(0, RIGHT_X + (canEquip and 130 or 0), 1, -62)
		if canEquip then
			local equipped = view.equippedTitleId == item.id
			cardEquip.Text = equipped and "Unequip" or "Equip"
			cardEquip.BackgroundColor3 = equipped and ACTIVE_BROWN or BUTTON_BROWN
		end

		-- Levitate: ONE RenderStepped connection, a continuous sine of the clock applied as a fractional
		-- Position offset (no tweens, so no restarts or stepping). Re-showing the card keeps the same
		-- connection. Skipped under Reduce shake; disconnected in hideDetail.
		card.Position = UDim2.fromScale(0.5, 0.5)
		if not cardFloat then
			cardFloat = game:GetService("RunService").RenderStepped:Connect(function()
				if not (detailShade.Visible and backdrop.Visible) then return end
				local reduce = ClientSettings.get("reduceShake") == true
				card.Position = UDim2.new(0.5, 0, 0.5, StageMotion.bobOffset(os.clock(), 6, 1.6, reduce))
			end)
		end
		detailShade.Visible = true
	end

	local function hideDetail()
		openItem = nil
		if cardFloat then
			cardFloat:Disconnect()
			cardFloat = nil
		end
		detailShade.Visible = false
	end

	cardClose.MouseButton1Click:Connect(function()
		playClickSfx()
		hideDetail()
	end)
	detailShade.MouseButton1Click:Connect(hideDetail)
	cardEquip.MouseButton1Click:Connect(function()
		playClickSfx()
		if openItem and openItem.tab == "titles" and EquipTitleRemote then
			local state = getLatestState()
			local equipped = state and state.equippedTitleId == openItem.id
			EquipTitleRemote:FireServer(not equipped and openItem.id or nil)
		end
	end)

	-- Grid tiles do not animate at all (159+ tiles must cost nothing); only the open detail card levitates.
	local TileCache = require(Engine:WaitForChild("CollectionTileCache"))
	local gridKey, gridDone = nil, false -- what the grid shows now (CollectionTileCache.key) and whether its last build finished
	local warmed = {} -- preloads already started: a tab or the whole warm up never starts twice
	local loadJob = require(Engine:WaitForChild("CollectionLoadJob")).new() -- the first 12 tiles now, the rest one chunk per frame; cancelled by a tab switch or by closing
	-- "New" state: the ids found since the Collection was last opened (this session; the first open marks nothing)
	local lastKeys -- set of discovered "tab:id" keys at the previous open
	local freshKeys, dropArmed = {}, {}
	local function discoveredKeys(view)
		local keys = {}
		for _, tab in ipairs(CollectionBook.Tabs) do
			for _, item in ipairs(CollectionBook.displayItems(tab.id, {})) do
				if CollectionBook.isDiscovered(view.sets, item) then keys[#keys + 1] = tab.id .. ":" .. tostring(item.id) end
			end
		end
		return keys
	end

	-- Columns the furniture grid lays out right now: CollectionFurnitureLayout.colsIn (the UIGridLayout rule, tested) on the scroll's visible
	-- width less the grid's side padding. Before the first layout that width is 0 (the panel is still hidden when the tiles are built), so
	-- the panel's responsive size stands in. Never below 1; a plain tab has no furniture and counts as one column.
	-- (This was called by makeTile but never defined: the nil call aborted refresh(), popIn never ran and the Collection would not open.)
	local function furnCols()
		if not currentKind then
			return 1
		end
		-- This runs in the middle of building a tile, so it must never throw: any failure counts as one column.
		local ok, cols = pcall(function()
			local cam = workspace.CurrentCamera
			local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
			local fitW = ResponsiveLayout.collectionPanel(vp.X, vp.Y).w
			local standIn = FullScreen.fit(panel, vp.X * fitW, 0, vp.X, vp.Y) - 30 - scroll.ScrollBarThickness
			local okWindow, window = pcall(function() return scroll.AbsoluteWindowSize.X end) -- visible width, scroll bar excluded
			return Furn.layout.colsIn(currentKind, okWindow and window or scroll.AbsoluteSize.X, Furn.padding(currentKind).side, standIn)
		end)
		return ok and cols or 1
	end

	-- The panel can change width while it is open (Expand, a resized window), and then the column count can change: the board edges and the
	-- red strings of the tiles already built are rebuilt from their records, which is what Furn.furnish is for.
	local function refurnish()
		if not currentKind or #furnRecords == 0 then
			return
		end
		local cols = furnCols()
		if cols == lastFurnCols then
			return
		end
		lastFurnCols = cols
		for _, rec in ipairs(furnRecords) do
			if rec.tile.Parent then
				pcall(Furn.furnish, rec.kind, rec.tile, { index = rec.index, n = #currentItems, cols = cols, tie = rec.tie })
			end
		end
	end
	scroll:GetPropertyChangedSignal("AbsoluteSize"):Connect(refurnish)
	pcall(function() -- the visible width also changes when a scroll bar appears; a missing property signal must not stop the panel
		scroll:GetPropertyChangedSignal("AbsoluteWindowSize"):Connect(refurnish)
	end)

	local function makeTile(item, order, view)
		local found = CollectionBook.isDiscovered(view.sets, item)
		local rarity = CollectionBook.Rarities[CollectionBook.rarityOf(item)]

		local tile = Instance.new("TextButton")
		tile.Text = ""
		tile.AutoButtonColor = true
		tile.LayoutOrder = order
		tile.BackgroundColor3 = found and Color3.fromRGB(58, 44, 30) or Color3.fromRGB(22, 18, 15)
		tile.ZIndex = 21
		tile.Parent = scroll
		local framed = Gallery.framed(item.tab) -- Patrons hang as framed portraits on the Gallery wall
		local fxKind = Furn.kind(item.tab) -- cork cards, trophy planks, key rails, title rails: furniture drawn from the cells
		local parts
		if fxKind then
			tile.AutoButtonColor = false
		elseif framed then
			tile.AutoButtonColor = false
			parts = Gallery.frameTile(tile, found, rgb(rarity.color), shownName(item))
		end
		if not framed and not fxKind then
			roundCorner(tile, 8)
			-- Rarity glow: a colored stroke plus a soft wash behind the icon.
			-- Tier frame (RarityFrame); locked entries keep a dim silhouette of the tier color.
			RarityFrame.apply(tile, CollectionBook.rarityOf(item), {
				thickness = found and 2 or 1.5, radius = 8, locked = not found, zIndex = 27,
			})
		end

		do -- tier shape mark in the tile's top left corner, so rarity is never colour alone (also on locked tiles)
			local mark = Instance.new("Frame")
			mark.Name = "TierMark"
			mark.Size = UDim2.fromOffset(20, 20)
			mark.Position = UDim2.fromOffset(4, 4)
			mark.BackgroundColor3 = Color3.fromRGB(30, 20, 14)
			mark.BackgroundTransparency = 0.1
			mark.BorderSizePixel = 0
			mark.Active = false
			mark.ZIndex = 30
			mark.Parent = tile
			roundCorner(mark, 10)
			pcall(function() require(script.Parent.RarityShape).set(mark, CollectionBook.rarityOf(item), 12, 4) end)
		end
		local iconWell = Instance.new("Frame")
		iconWell.Name = "IconWell"
		local wellSize = framed and parts.icon.w or 60
		local wellRadius = framed and 6 or 30
		iconWell.Size = UDim2.fromOffset(wellSize, framed and parts.icon.h or 60)
		iconWell.Position = framed and UDim2.fromOffset(parts.icon.x, parts.icon.y) or UDim2.new(0.5, -30, 0, 8)
		iconWell.BackgroundColor3 = found and rgb(rarity.color) or Color3.fromRGB(35, 28, 20)
		iconWell.BackgroundTransparency = found and 0.72 or 0.35
		iconWell.ZIndex = 23
		iconWell.Parent = tile
		roundCorner(iconWell, wellRadius)
		-- a locked entry stays on show as a dim silhouette with its name on the plate (never "???" and an empty hole)

		local icon = label(iconWell, {
			Size = UDim2.fromScale(1, 1), TextSize = framed and 28 or 34, ZIndex = 23, Text = iconFor(item),
		})
		if not found then
			-- TextTransparency dims emojis even though TextColor3 doesn't.
			icon.TextTransparency = 0.55
			icon.TextStrokeTransparency = 1
		end
		do
			local artId = ContentArt.getImageId(item.tab, (not found and item.tab == "bonds") and "bond_locked" or item.id)
			if artId then
				local art = PatronPlaqueModule.applyById(iconWell, artId, {
					emojiLabel = icon,
					fade = true,
					dim = not found,
					zIndex = 24,
					cornerRadius = wellRadius,
				})
				-- locked: an unlit silhouette (the locked Bond medallion is already its own picture)
				if art and not found and item.tab ~= "bonds" then art.ImageColor3 = Color3.fromRGB(78, 72, 66) end
			end
		end

		do -- a locked Patron, Recipe or Boss entry is a dark silhouette with a question mark; the unlock hint is in its tooltip and detail card
			local glyph = require(Engine:WaitForChild("CollectionCards")).lockedGlyph(item.tab, found)
			if glyph then
				local q = label(iconWell, {
					Name = "LockedGlyph", Size = UDim2.fromScale(1, 1), TextSize = 28, ZIndex = 26, Text = glyph,
					Font = Enum.Font.GothamBold, TextColor3 = CREAM, TextTransparency = 0, TextStrokeTransparency = 0.3,
				})
				q.TextStrokeColor3 = Color3.fromRGB(20, 12, 6)
				icon.Visible = false
			end
		end

		local nameLabel
		if not framed then -- framed portraits carry their name on the frame's brass plate
			nameLabel = label(tile, {
				Size = UDim2.new(1, -8, 0, 36), Position = UDim2.new(0, 4, 0, 68),
				Font = Enum.Font.GothamBold, TextSize = 14, TextWrapped = true, ZIndex = 22,
				TextColor3 = found and CREAM or DIM,
				Text = shownName(item),
			})
		end

		-- hand-hung: a fixed tiny tilt and offset per Patron (the "New" tag and the drop-in follow it)
		local hang = framed and Gallery.hangTile(tile, item.id) or nil
		local fx
		if fxKind then
			local nextFound = currentItems[order + 1] and CollectionBook.isDiscovered(view.sets, currentItems[order + 1])
			fx = Furn.style(fxKind, tile, {
				found = found, iconWell = iconWell, nameLabel = nameLabel, rarityColor = rgb(rarity.color), id = item.id,
				equipped = found and item.tab == "titles" and view.equippedTitleId == item.id,
			})
			hang = fx.hang
			local rec = { tile = tile, kind = fxKind, index = order, tie = item.tab == "bonds" and found and nextFound == true }
			furnRecords[#furnRecords + 1] = rec
			local cols = furnCols()
			lastFurnCols = cols
			Furn.furnish(fxKind, tile, { index = order, n = #currentItems, cols = cols, tie = rec.tie })
		end

		-- newly found since the Collection was last opened: a brass "New" tag, and (once) a drop-in
		local freshKey = item.tab .. ":" .. tostring(item.id)
		if found and freshKeys[freshKey] then
			Gallery.newTag(tile)
			if dropArmed[freshKey] then
				dropArmed[freshKey] = nil
				Gallery.dropIn(tile)
			end
		end
		if hang then Gallery.bindHover(tile, hang, fx and fx.target) end -- hover straightens, lifts 3 px and sways once

		if found and not fxKind and item.tab == "titles" and view.equippedTitleId == item.id then
			label(tile, {
				Size = UDim2.new(1, 0, 0, 18), Position = UDim2.fromOffset(0, 2),
				Font = Enum.Font.GothamBold, TextSize = 14, ZIndex = 25, TextColor3 = GOLD,
				Text = "EQUIPPED",
			})
		end

		tile.MouseButton1Click:Connect(function()
			playClickSfx()
			showDetail(item, view)
		end)
		-- Locked tiles with an unlock rule: the hint in the shared tooltip (padlock and dark silhouette stay on the tile).
		if not found and addTooltip then
			local ruleHint = unlockRuleHint(item, view)
			if ruleHint then
				addTooltip(tile, function()
					return "Locked\n" .. ruleHint
				end)
			end
		end
		-- Discovered tiles: name and effect in the shared hover tooltip (the tile itself stays art and a name).
		if found and addTooltip and item.def and item.def.description then
			addTooltip(tile, function()
				local name = item.tab == "titles" and item.def.title or item.def.name
				return tostring(name) .. "\n" .. item.def.description
			end)
		end
	end

	-- One tile that cannot be built must not stop the other tiles or the panel opening. The first failure of a refresh is warned (not one
	-- warning per tile).
	local tileFailed = false
	local function safeTile(item, order, view)
		local ok, err = pcall(makeTile, item, order, view)
		if not ok and not tileFailed then
			tileFailed = true
			warn("[Collection] tile " .. tostring(item and item.id) .. " could not be built: " .. tostring(err))
		end
	end

	-- ===== Painted section scenes: the entries sit in the painted slots of the section's own close-up =====
	do
		Sec.scene = require(script.Parent.CollectionSection).new({
			parent = panel, zIndex = 22, addTooltip = addTooltip,
			isActive = function() return backdrop.Visible and mode == "section" end,
		})
		Sec.scene.frame.Position, Sec.scene.frame.Size = scroll.Position, scroll.Size
		local function describe(item, view)
			local found = CollectionBook.isDiscovered(view.sets, item)
			local def = item.def
			local info = {
				found = found, name = shownName(item), icon = iconFor(item), rarityColor = rgb(CollectionBook.Rarities[CollectionBook.rarityOf(item)].color),
					rarity = CollectionBook.rarityOf(item),
				artId = ContentArt.getImageId(item.tab, (not found and item.tab == "bonds") and "bond_locked" or item.id),
				fresh = freshKeys[item.tab .. ":" .. tostring(item.id)] == true,
			}
			-- a locked entry never prints what it does: name only, plus the unlock rule when the server sent one
			if not found then info.line = unlockRuleHint(item, view)
			elseif item.tab == "recipes" then info.line = def.description
			elseif item.tab == "bonds" then info.line = def.flavorText
			elseif item.tab == "titles" and view.equippedTitleId == item.id then info.line = "Equipped" end
			if found then
				info.tip = def.description and (shownName(item) .. "\n" .. def.description) or nil
			else
				local hint = unlockRuleHint(item, view)
				info.tip = hint and ("Locked\n" .. hint) or nil
			end
			return info
		end
		-- show the painted scene for the section on screen; false = the old scrolling grid takes over (no art id, or slots too small)
		function Sec.show(items, view)
			if not Sec.scene.canShow(activeTabId, #items) then
				Sec.painted = false
				Sec.scene.hide()
				scroll.Visible = true
				return false
			end
			Sec.painted = true
			scroll.Visible = false
			Sec.scene.show(activeTabId, items, function(item) return describe(item, view) end, function(item)
				playClickSfx()
				showDetail(item, view)
			end)
			return true
		end
		function Sec.refit() -- the window changed: swap between the scene and the grid when what fits changed
			if mode ~= "section" then return end
			if Sec.scene.canShow(activeTabId, #currentItems) ~= Sec.painted then pcall(refresh) end
		end
	end

	refresh = function()
		tileFailed = false
		local refreshT0 = os.clock()
		loadJob:cancel() -- a tab switch or a new refresh: the build and the art download of the tab before stop at their next chunk
		local tabToken = loadJob.token
		if mode == "section" and TileCache.shouldWarm(warmed, "tab:" .. tostring(activeTabId)) then -- only the tab on screen is fetched, never a hidden one
			task.spawn(function() -- current tab first (a tab already loaded or loading is not asked again). One timing line per tab for the slowest-tab report.
				local t0, tabName = os.clock(), activeTabId
				ContentArt.preload({ { tabName } }, "collection tab " .. tabName, { batch = 12, pause = 0.02, cancelled = function() return not loadJob:alive(tabToken) end })
				if not loadJob:alive(tabToken) then warmed["tab:" .. tabName] = nil return end -- cancelled: the next visit asks again
				print(string.format("[Collection] tab=%s ready_ms=%d", tabName, math.floor((os.clock() - t0) * 1000 + 0.5)))
			end)
		end
		local view = currentView()
		local completion = view.completion

		-- Overall bar.
		overallFill.Size = UDim2.fromScale(completion.total > 0 and completion.found / completion.total or 0, 1)
		local nextMilestone = CollectionBook.nextMilestone(view.claimed)
		local nextText
		if nextMilestone then
			local rewards = {}
			for _, reward in ipairs(nextMilestone.rewards) do
				table.insert(rewards, CollectionBook.rewardLabel(reward))
			end
			nextText = "Next at " .. nextMilestone.percent .. "%: " .. table.concat(rewards, " + ")
		else
			nextText = "Every milestone claimed!"
		end
		if Gallery.chestApi then Gallery.chestApi.setNext(nextMilestone and ("Next at " .. nextMilestone.percent .. "%") or "All claimed") end
		-- Next unlock (moved here from the main menu strip)
		local pick = view.state and view.state.nextUnlock
		overallUnlock.Text = (pick and pick.label) and ("Next unlock: " .. pick.label) or ""
		overallNext.Text = nextText
		overallText.Text = string.format("Overall %d%%  (%d / %d)",
			math.floor(completion.percent), math.floor(completion.found), math.floor(completion.total))
		do -- on a section page the plain count of that page: "Patrons: 23 of 81 found"
			local counts = mode == "section" and CollectionBook.tabCounts(view.sets)[activeTabId]
			local tab = counts and CollectionBook.getTab(activeTabId)
			if tab then
				overallText.Text = overallText.Text .. "   " .. tab.name .. ": " .. require(Engine:WaitForChild("CollectionCards")).foundText(counts.found, counts.total)
			end
		end

		-- Quiet tab plates: the lit one is the section on screen, or "< Gallery" while the room shows.
		for _, tab in ipairs(CollectionBook.Tabs) do
			local tabButton = tabButtons[tab.id]
			do -- the count pill of each tab plate ("Patrons  12 / 81")
				local counts = CollectionBook.tabCounts(view.sets)[tab.id]
				tabButton.Text = counts and require(Engine:WaitForChild("CollectionCards")).tabText(tab.name, counts.found, counts.total) or tab.name
			end
			tabButton.BackgroundColor3 = (mode == "section" and tab.id == activeTabId) and ACTIVE_BROWN or BUTTON_BROWN
		end
		tabButtons.room.BackgroundColor3 = mode == "room" and ACTIVE_BROWN or BUTTON_BROWN

		-- The gallery room: the count on every name plate, and a New tag where something was found since the last visit.
		do
			local fresh = {}
			for key in pairs(freshKeys) do
				local tabId = key:match("^(.-):")
				if tabId then fresh[tabId] = (fresh[tabId] or 0) + 1 end
			end
			room.update(CollectionBook.tabCounts(view.sets), fresh)
		end

		-- Grid. A click on the tab already showing, with nothing in it changed, keeps the finished tiles (no teardown, no rebuild).
		do
			local keyItems = {}
			local shownItems = mode == "section" and CollectionBook.displayItems(activeTabId, hiddenRarities) or {}
			for i, it in ipairs(shownItems) do keyItems[i] = { id = it.id, found = CollectionBook.isDiscovered(view.sets, it) } end
			local fresh = 0
			for _ in pairs(freshKeys) do fresh = fresh + 1 end
			local key = mode == "section" and TileCache.key({ tab = activeTabId, width = scroll.AbsoluteSize.X, hidden = hiddenRarities, items = keyItems, equipped = view.equippedTitleId, fresh = fresh, extra = tostring(openItem and openItem.id) }) or nil
			if key and key == gridKey and gridDone and not Sec.painted then
				if openItem then showDetail(openItem, view) end
				return
			end
			gridKey, gridDone = key, false
		end
		for _, child in ipairs(scroll:GetChildren()) do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		-- Build tiles in small batches (12 per frame, Engine/CollectionLoadJob) so opening the Collection does not stutter; a newer
		-- refresh, a tab switch or closing the Collection cancels the job and the old batch loop stops.
		if mode ~= "section" then
			currentItems, furnRecords = {}, {} -- the room is showing: no section tiles are kept
			Sec.painted = false
			Sec.scene.hide()
			return
		end
		do -- a painted section scene replaces the scrolling grid when its art is recorded and its slots are readable at this size
			local items = CollectionBook.displayItems(activeTabId, hiddenRarities)
			currentItems, furnRecords = items, {}
			if Sec.show(items, view) then
				if openItem then showDetail(openItem, view) end
				return
			end
		end
		furniture.setTab(activeTabId)
		grid.CellSize = Gallery.cellSize(activeTabId) -- framed portraits are taller than the plain tiles
		local hungGap = Gallery.framed(activeTabId) and SceneLayout.FRAMED_GAP or nil -- wider gaps so chains and shadows fit
		grid.CellPadding = hungGap and UDim2.fromOffset(hungGap.x, hungGap.y) or UDim2.fromOffset(10, 10)
		gridPadding.PaddingTop = UDim.new(0, hungGap and (SceneLayout.CHAIN_H + 8) or 4)
		local items = CollectionBook.displayItems(activeTabId, hiddenRarities)
		currentItems, furnRecords, currentKind = items, {}, Furn.kind(activeTabId)
		do -- furniture tabs: the grid takes the kind's cell size and gap, and room for the board's outer margin
			local pad = currentKind and Furn.padding(currentKind)
			if currentKind then grid.CellSize, grid.CellPadding = Furn.cellSize(currentKind), Furn.gap(currentKind) end
			gridPadding.PaddingTop = UDim.new(0, pad and pad.top or gridPadding.PaddingTop.Offset)
			gridPadding.PaddingBottom = UDim.new(0, pad and pad.top or 4)
			gridPadding.PaddingLeft = UDim.new(0, pad and pad.side or 0)
			gridPadding.PaddingRight = UDim.new(0, pad and pad.side or 0)
		end
		local function buildChunk(from, to) for j = from, to do safeTile(items[j], j, view) end end
		local function finishBuild(tabName)
			gridDone = true
			print(string.format("[Collection] tab=%s build_ms=%d", tostring(tabName), math.floor((os.clock() - refreshT0) * 1000 + 0.5)))
		end
		local rest = loadJob:begin(#items, buildChunk) -- the visible rows (12 tiles) paint this frame
		do -- Studio only: the time to the first visible tile, and a warning when that took more than 150 ms
			local firstMs = (os.clock() - refreshT0) * 1000
			if game:GetService("RunService"):IsStudio() then
				print(string.format("[Collection] tab=%s first_tile_ms=%d", tostring(activeTabId), math.floor(firstMs + 0.5)))
				if firstMs > 150 then warn(string.format("[Collection] tab=%s first paint took %d ms (over 150)", tostring(activeTabId), math.floor(firstMs))) end
			end
		end
		if rest then
			local tabName = activeTabId
			task.spawn(function()
				if rest(task.wait) and scroll.Parent then finishBuild(tabName) end
			end)
		elseif loadJob.open then
			finishBuild(activeTabId)
		end

		-- Keep an open detail card current (e.g. after an Equip click).
		if openItem then
			showDetail(openItem, view)
		end
	end

	-- A tab that fails to build must never stop the panel: refresh() ran bare inside openCollection, so one error skipped popIn and the
	-- corner button hovered but nothing opened. The error is warned once instead.
	local function safeRefresh(what)
		local ok, err = pcall(refresh)
		if not ok then
			warn("[Collection] " .. what .. " could not be built: " .. tostring(err))
		end
		return ok
	end

	-- The quiet row: "< Gallery" (back to the room) and one small plate per section, for the keyboard and for phones.
	local function quietPlate(text, order)
		local plate = button(tabRow, {
			AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, RoomLayout.TABS.h - 2),
			TextSize = 14, LayoutOrder = order, Text = text, BorderSizePixel = 0,
		})
		roundCorner(plate, 6)
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 10)
		pad.PaddingRight = UDim.new(0, 10)
		pad.Parent = plate
		local rim = Instance.new("UIStroke")
		rim.Color = Color3.fromRGB(110, 90, 54)
		rim.Thickness = 1
		rim.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		rim.Parent = plate
		return plate
	end

	local function setMode(newMode) -- which view shows; the caller refreshes
		mode = newMode
		relayout() -- the room takes the height of the hidden tab row and rarity filter
		room.frame.Visible = newMode == "room"
		scroll.Visible = newMode == "section"
		if Gallery.chestApi and Gallery.chestApi.setShown then Gallery.chestApi.setShown(false) end -- the chest and its plate cover the last row of a section; "Next at N%" is on the banner line
	end
	local function pageSound(fromTab, toTab, fromMode, toMode) -- page flip cue when the page really changes (Engine/CollectionCards)
		pcall(function()
			local cue = require(Engine:WaitForChild("CollectionCards")).pageCue(fromTab, toTab, fromMode, toMode)
			if cue then require(script.Parent.Cue).play(cue) end
		end)
	end
	showSection = function(tabId)
		pageSound(activeTabId, tabId, mode, "section")
		activeTabId = tabId
		hideDetail()
		setMode("section")
		scroll.CanvasPosition = Vector2.new(0, 0)
		safeRefresh("tab " .. tabId)
	end
	showRoom = function()
		pageSound(activeTabId, activeTabId, mode, "room")
		hideDetail()
		setMode("room")
		safeRefresh("the gallery room")
	end
	-- Escape (PopupDismiss `step`): close the detail card first, then leave a section for the room; false = nothing to step back from,
	-- so Escape closes the Collection as it always did.
	local function stepBack()
		if detailShade.Visible then
			hideDetail()
			return true
		end
		if mode == "section" then
			showRoom()
			return true
		end
		return false
	end

	do
		local galleryPlate = quietPlate("< Gallery", 0)
		tabButtons.room = galleryPlate
		galleryPlate.MouseButton1Click:Connect(function()
			playClickSfx()
			if mode ~= "room" then showRoom() end
		end)
	end
	for i, tab in ipairs(CollectionBook.Tabs) do
		local tabButton = quietPlate(tab.name, i)
		tabButtons[tab.id] = tabButton
		tabButton.MouseButton1Click:Connect(function()
			playClickSfx()
			if mode ~= "section" or activeTabId ~= tab.id then showSection(tab.id) end
		end)
	end

	local function showMilestoneToast(milestoneIds)
		local lines = {}
		for _, id in ipairs(milestoneIds) do
			for _, milestone in ipairs(CollectionBook.Milestones) do
				if milestone.id == id then
					local rewards = {}
					for _, reward in ipairs(milestone.rewards) do
						table.insert(rewards, CollectionBook.rewardLabel(reward))
					end
					table.insert(lines, "Collection " .. milestone.percent .. "%! " .. table.concat(rewards, " + "))
				end
			end
		end
		if #lines == 0 then
			return
		end
		if Gallery.chestApi then Gallery.chestApi.open() end -- the chest on the floor opens with gold motes
		toastText.Text = table.concat(lines, "\n")
		toast.Size = UDim2.fromOffset(420, 40 + 20 * #lines)
		toast.Visible = true
		local shownText = toastText.Text
		task.delay(5, function()
			if toastText.Text == shownText then
				toast.Visible = false
			end
		end)
	end

	-- shared tab strip + Back; Escape steps back (detail card, then section, then the room) before it closes the Collection
	-- Warm every sub-tab and the painted scenes when the Collection opens (batches of 20, a short pause between), so no click shows art loading in
	-- Opening no longer warms every tab: the full background warm up (CollectionWarm) stops so the tab on screen gets the bandwidth, and only
	-- that tab is fetched (refresh). Closing cancels the tile build and the tab download; nothing runs while the Collection is shut.
	backdrop:GetPropertyChangedSignal("Visible"):Connect(function()
		if backdrop.Visible then
			loadJob:reopen()
			pcall(function() require(script.Parent.CollectionWarm).cancel() end)
		else
			loadJob:close()
		end
	end)
	require(script.Parent.PanelTabs).attach(backdrop, "collection", playClickSfx, panel)
	require(script.Parent.PanelTabs).setStep("collection", stepBack)
	OverlayManager.register("collection", function()
		loadJob:close() -- no tile is built or downloaded after the Collection closes
		hideDetail()
		popOut(backdrop, panel)
	end)

	local function openCollection()
		playClickSfx()
		loadJob:reopen()
		pcall(function() require(script.Parent.CollectionWarm).cancel() end)
		OverlayManager.closeAllExcept("collection")
		-- Building the tab may fail (it did: an undefined function aborted refresh and the panel never opened). The panel opens regardless;
		-- the error is warned, and a tab that failed shows whatever tiles were built.
		local okPrep, prepErr = pcall(function()
			hideDetail()
			do -- what was found since the last open gets a "New" tag and a one-time drop-in
				local keys = discoveredKeys(currentView())
				freshKeys, dropArmed = {}, {}
				if lastKeys then
					for _, key in ipairs(SceneLayout.newIds(lastKeys, keys)) do freshKeys[key] = true; dropArmed[key] = true end
				end
				lastKeys = keys
			end
		end)
		if not okPrep then
			warn("[Collection] could not read what is new: " .. tostring(prepErr))
		end
		setMode("room") -- the gallery room is always the first view
		safeRefresh("the gallery room")
		popIn(backdrop, panel)
	end
	OverlayManager.registerOpener("collection", openCollection)
	deps.collectionButton.MouseButton1Click:Connect(openCollection)
	if deps.menuCollectionButton then
		deps.menuCollectionButton.MouseButton1Click:Connect(openCollection)
	end

	if deps.StateUpdatedRemote then
		deps.StateUpdatedRemote.OnClientEvent:Connect(function()
			task.defer(function()
				local state = getLatestState()
				if state and state.collectionMilestoneNotice then
					showMilestoneToast(state.collectionMilestoneNotice)
				end
				if backdrop.Visible then
					safeRefresh("the open tab")
				end
			end)
		end)
	end

	return { notice = showMilestoneToast } -- the lazy wrapper in the hub builds the panel and calls this when a milestone arrives before first open
end
