--[[
	Client/init.client.lua
	A deliberately plain, functional UI so the game is playable and
	publishable this week. It is built entirely in code (no pre-made UI in
	Studio) so it works the moment you sync with Rojo -- swap in your own
	art, fonts, and layout once the loop feels fun. Nothing here is
	precious; feel free to gut this file once you're comfortable in Studio.

	This version adds: a menu screen, a How to Play overlay, card
	hover/select animations, and sound hooks (menu + card clicks + a
	looping background track). See the SOUND_IDS block below -- you need
	to plug in real asset IDs from Roblox's audio library before you'll
	hear anything; the code is ready, the actual sounds are a content
	choice that's up to you two.

	LOCAL VARIABLE BUDGET: this whole file is one big top-level script, not
	broken into separate modules -- and Lua caps a single function at 200
	simultaneously-active local variables. We hit that ceiling once (every
	`local` for every Frame/Button/Label in every overlay all count against
	the SAME budget, forever, for the rest of the file). The fix, used
	throughout below: wrap a self-contained overlay's construction code in
	`do ... end`. Locals declared inside a `do/end` block are freed when the
	block ends, instead of eating into the budget for the rest of the file.
	If something outside the block needs to reach in (e.g. a `refreshX`
	function called from render(), far below), declare that ONE name with
	`local refreshX` BEFORE the `do`, and assign to it (not re-`local`-declare
	it) from inside the block -- see the Poker Hands / Deck Tracker / Unlock
	popup sections for the pattern. When adding a new overlay, wrap its
	construction in `do ... end` from the start rather than waiting to hit
	this ceiling again.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local PlayHandRemote = remotes:WaitForChild("PlayHand")
local DiscardRemote = remotes:WaitForChild("Discard")
local BuyPatronRemote = remotes:WaitForChild("BuyPatron")
local SellPatronRemote = remotes:WaitForChild("SellPatron")
local BuyThemeRemote = remotes:WaitForChild("BuyTheme")
local EquipThemeRemote = remotes:WaitForChild("EquipTheme")
local AdvanceRoundRemote = remotes:WaitForChild("AdvanceRound")
local RestartRunRemote = remotes:WaitForChild("RestartRun")
local StartRunRemote = remotes:WaitForChild("StartRun")
local StateUpdatedRemote = remotes:WaitForChild("StateUpdated")
-- PHASE 1B (Recipes UI)
local BuyRecipeRemote = remotes:WaitForChild("BuyRecipe") -- kept for direct engine use; no UI calls this anymore, see PHASE 1C below
local UseRecipeRemote = remotes:WaitForChild("UseRecipe")
-- PHASE 1C (shop randomization: Reroll/Packs/House Passes)
local RerollShopRemote = remotes:WaitForChild("RerollShop")
local BuyPackRemote = remotes:WaitForChild("BuyPack")
local ResolvePackRemote = remotes:WaitForChild("ResolvePack")
local BuyHousePassRemote = remotes:WaitForChild("BuyHousePass")

-- Theme *data* (names/prices/colors) is static content, so the client just
-- reads it straight from Shared -- only ownership/equipped state needs to
-- travel over the StateUpdated remote.
local Themes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("Themes"))
-- FEATURE 4 (Road Ahead / Journey overlay) needs the target-score formula,
-- which already exists in RunState -- no engine changes needed.
local RunStateEngine = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("RunState"))
-- FEATURE 5 (worked scoring examples in How to Play) runs real example
-- hands through the actual engine so the numbers shown are never stale.
local HandEvaluator = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("HandEvaluator"))
local Scoring = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("Scoring"))
-- FEATURE 7 (Deck Tracker) needs Deck.RankOrder + reads state.deckCounts
-- (already serialized server-side in the Boss Rounds/Deck Variants batch).
local Deck = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("Deck"))
-- FEATURE 8 (Run Setup) needs these to build the variant/difficulty picker.
local DeckVariants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("DeckVariants"))
local DifficultyTiers = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("DifficultyTiers"))
-- FEATURE 9 (Boss Round awareness) needs this for the Journey pip coloring.
local BossRounds = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("BossRounds"))
-- FEATURE 11 (Collection Gallery) needs the full Patron catalog to show
-- locked ("???") entries for ones not owned yet -- the server only sends
-- OWNED patrons over the state payload.
local Patrons = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("Patrons"))
-- PHASE 1B (Recipes UI): Recipes.HouseRecipes/MenuRecipes/SecretRecipes are
-- static content, same "client reads the catalog directly" pattern as
-- Patrons/Themes above -- the server only sends which ones are OWNED.
local Recipes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("Recipes"))
-- PHASE 1B (hand visual treatment): need Card.Garnishes/Specials/Stamps'
-- icon fields to show a small corner badge on modified cards in the hand.
local Card = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("Card"))
-- PHASE 2 (My House Passes display): HousePasses.Definitions is static
-- content, same "client reads the catalog directly" pattern as
-- Patrons/Recipes/Themes above -- the server only sends which ids are owned
-- (state.housePassIds, already shipped since Phase 1c but unused client-side
-- until now).
local HousePasses = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("HousePasses"))

-- Declared up here (not down by the rest of "Client-side state" below) so
-- ANY overlay's refresh function -- including ones built inside a do/end
-- block for the local-variable budget -- can read the latest server state
-- without needing its own forward-declare dance for it. This is what the
-- Deck Tracker / Poker Hands reference bug (fixed earlier) was fighting
-- around; moving this one declaration up avoids that whole category of bug
-- for every overlay from here on, including the new Journey map below.
local latestState = nil

-- Same reasoning as latestState above: currentTheme used to be declared
-- much further down (right before applyTheme), which is exactly what bit
-- the new Journey map -- refreshJourneyImpl (defined near the top of the
-- file, in its own do/end block) referenced "currentTheme" before that
-- point, so it silently resolved to an undefined GLOBAL instead of the
-- real local, and indexing .colors on nil crashed the whole overlay open.
-- Moving the declaration up here avoids this bug for every overlay,
-- current and future, same fix as latestState.
local currentTheme = Themes.getById(Themes.DefaultThemeId)

local RANK_NAMES = {
	[2] = "2", [3] = "3", [4] = "4", [5] = "5", [6] = "6", [7] = "7", [8] = "8", [9] = "9", [10] = "10",
	[11] = "J", [12] = "Q", [13] = "K", [14] = "A",
}
local SUIT_SYMBOLS = { Hearts = "♥", Diamonds = "♦", Clubs = "♣", Spades = "♠" }
local RED_SUITS = { Hearts = true, Diamonds = true }
local SUIT_DISPLAY_ORDER = { "Spades", "Hearts", "Clubs", "Diamonds" }

-- ===== Sound =====
-- Extracted into Client/Sound.lua (asset IDs and the "why this default
-- track" note now live there too). Nearly everything below takes
-- playSfx/playClickSfx/SOUND_IDS as deps, so this is required first.
local SoundModule = require(script.Sound)({
	SoundService = SoundService,
})
local SOUND_IDS = SoundModule.SOUND_IDS
local backgroundMusic = SoundModule.backgroundMusic
local playSfx = SoundModule.playSfx
local playClickSfx = SoundModule.playClickSfx
local VOLUME_STEPS = SoundModule.VOLUME_STEPS
local VOLUME_ICONS = SoundModule.VOLUME_ICONS
local volumeStepIndex = SoundModule.volumeStepIndex

-- ===== Visual + stepper-row helpers =====
-- Extracted into Client/VisualHelpers.lua. Required right after Sound.lua
-- since makeStepperRow needs playClickSfx. Nearly every overlay module
-- below takes tweenTo/polishPanel/polishButton/roundCorner/addSoftShadow
-- as deps.
local VisualHelpersModule = require(script.VisualHelpers)({
	TweenService = TweenService,
	playClickSfx = playClickSfx,
})
local tweenTo = VisualHelpersModule.tweenTo
local roundCorner = VisualHelpersModule.roundCorner
local polishButton = VisualHelpersModule.polishButton
local polishPanel = VisualHelpersModule.polishPanel
local addSoftShadow = VisualHelpersModule.addSoftShadow
local makeStepperRow = VisualHelpersModule.makeStepperRow

-- ===== Root UI =====

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "GameUI"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.Parent = playerGui

local root = Instance.new("Frame")
root.Name = "GameRoot"
root.Size = UDim2.fromScale(1, 1)
root.BackgroundColor3 = Color3.fromRGB(24, 18, 14) -- warm dark "tavern" backdrop
root.BorderSizePixel = 0
root.Visible = false -- hidden until the player presses Play on the menu
root.Parent = screenGui

-- ----- Left sidebar: round/blind info -----
-- Extracted into Client/Sidebar.lua (round/blind labels, Patron slot row,
-- score preview box). SIDEBAR_WIDTH/labels/patronSlots come back out since
-- render() and refreshScorePreview() below still drive them every frame.
local SidebarModule = require(script.Sidebar)({
	root = root,
	polishPanel = polishPanel,
	roundCorner = roundCorner,
	Patrons = Patrons,
})
local SIDEBAR_WIDTH = SidebarModule.SIDEBAR_WIDTH
local sidebar = SidebarModule.sidebar
local nightRoundLabel = SidebarModule.nightRoundLabel
local blindInfoLabel = SidebarModule.blindInfoLabel
local scoreLabel = SidebarModule.scoreLabel
local tipsLabel = SidebarModule.tipsLabel
local handsDiscardsLabel = SidebarModule.handsDiscardsLabel
local patronsCountLabel = SidebarModule.patronsCountLabel
local patronSlots = SidebarModule.patronSlots
local MAX_SIDEBAR_PATRON_SLOTS = SidebarModule.MAX_SIDEBAR_PATRON_SLOTS
local scorePreviewBox = SidebarModule.scorePreviewBox
local scorePreviewLabel = SidebarModule.scorePreviewLabel

-- ----- Help (?) and mute buttons, top-right corner -----

local function makeCornerButton(text, xOffset)
	local button = Instance.new("TextButton")
	button.Size = UDim2.new(0, 44, 0, 44)
	button.Position = UDim2.new(1, xOffset, 0, 8)
	button.Font = Enum.Font.GothamBold
	button.TextSize = 20
	button.Text = text
	button.BackgroundColor3 = Color3.fromRGB(60, 45, 32)
	button.TextColor3 = Color3.fromRGB(250, 240, 220)
	button.ZIndex = 5
	button.Parent = root
	polishButton(button, 22)
	return button
end

local volumeButton = makeCornerButton(VOLUME_ICONS[volumeStepIndex], -60)
local helpButton = makeCornerButton("?", -110)
local themesButton = makeCornerButton("🎨", -160)
local journeyButton = makeCornerButton("🗺", -210)
local handRefButton = makeCornerButton("📖", -260)
-- No corner button for the Deck Tracker anymore -- the blue deck widget
-- (bottom-right) is clickable and opens it directly instead (see
-- deckWidgetButton). Settings/Collection shifted left by 50px to close
-- the gap left behind.
local settingsButton = makeCornerButton("⚙", -310)
local collectionButton = makeCornerButton("📔", -360)

-- ----- Generic hover tooltip -----
-- Ahmed: "whenever you hover over a button any UI, it should give you the
-- name of what it does." One shared label, repositioned/retexted for
-- whichever button is currently hovered, instead of a separate Instance
-- per button.
local addTooltip
do

local tooltipLabel = Instance.new("TextLabel")
tooltipLabel.Name = "Tooltip"
tooltipLabel.AutomaticSize = Enum.AutomaticSize.XY
tooltipLabel.Size = UDim2.new(0, 0, 0, 0)
tooltipLabel.BackgroundColor3 = Color3.fromRGB(20, 16, 12)
tooltipLabel.BackgroundTransparency = 0.05
tooltipLabel.Font = Enum.Font.Gotham
tooltipLabel.TextSize = 14
tooltipLabel.TextColor3 = Color3.fromRGB(250, 240, 220)
tooltipLabel.Text = ""
tooltipLabel.Visible = false
tooltipLabel.ZIndex = 100
tooltipLabel.Parent = screenGui
polishPanel(tooltipLabel, 6)

local tooltipPadding = Instance.new("UIPadding")
tooltipPadding.PaddingLeft = UDim.new(0, 8)
tooltipPadding.PaddingRight = UDim.new(0, 8)
tooltipPadding.PaddingTop = UDim.new(0, 5)
tooltipPadding.PaddingBottom = UDim.new(0, 5)
tooltipPadding.Parent = tooltipLabel

-- align "left": tooltip's RIGHT edge lines up with the button's right edge
-- (for buttons near the right side of the screen, so the tooltip doesn't
-- run off-screen). Default: centered under the button.
addTooltip = function(button, text, align)
	-- text can be a plain string (most callers) or a zero-arg function
	-- returning a string, for tooltips whose content can change after this
	-- is wired up (e.g. a Patron slot's tooltip depends on whether that
	-- Patron is currently owned, which changes as you buy/discard them).
	button.MouseEnter:Connect(function()
		tooltipLabel.Text = (type(text) == "function") and text() or text
		local pos = button.AbsolutePosition
		local size = button.AbsoluteSize
		if align == "left" then
			tooltipLabel.AnchorPoint = Vector2.new(1, 0)
			tooltipLabel.Position = UDim2.fromOffset(pos.X + size.X, pos.Y + size.Y + 6)
		else
			tooltipLabel.AnchorPoint = Vector2.new(0.5, 0)
			tooltipLabel.Position = UDim2.fromOffset(pos.X + size.X / 2, pos.Y + size.Y + 6)
		end
		tooltipLabel.Visible = true
	end)
	button.MouseLeave:Connect(function()
		tooltipLabel.Visible = false
	end)
end

addTooltip(volumeButton, "Music volume (click to cycle loud / quiet / mute)", "left")
addTooltip(helpButton, "How to Play", "left")
addTooltip(themesButton, "Themes -- change your table's look", "left")
addTooltip(journeyButton, "Journey -- see the road ahead", "left")
addTooltip(handRefButton, "Poker Hands reference", "left")
addTooltip(settingsButton, "Settings", "left")
addTooltip(collectionButton, "Collection -- Patrons & Themes you've unlocked", "left")

end -- Generic hover tooltip

-- Sidebar Patron slot tooltips: slot i shows whichever Patron currently
-- sits in seat i of YOUR table (state.ownedPatrons[i]), not a fixed
-- roster entry -- that changes as you buy/sell, so this has to be a
-- function (not a plain string) re-evaluated fresh every hover, via
-- latestState, rather than bound once at construction time.
for i = 1, MAX_SIDEBAR_PATRON_SLOTS do
	local slot = patronSlots[i]
	if slot then
		addTooltip(slot.frame, function()
			local owned = latestState and latestState.ownedPatrons and latestState.ownedPatrons[i]
			if owned then
				return string.format("%s\n%s", owned.name, owned.description)
			end
			return "Empty seat -- visit The Bar to recruit a Patron"
		end)
	end
end

-- ===== Message banner (hand result / round result) =====
-- Extracted into Client/MessageBanner.lua. showWarning is passed as a dep
-- into Shop.lua/Themes.lua below, and render() drives bossBanner directly,
-- so all three come back out of the require() call.
local MessageBannerModule = require(script.MessageBanner)({
	SIDEBAR_WIDTH = SIDEBAR_WIDTH,
	root = root,
	polishPanel = polishPanel,
})
local showWarning = MessageBannerModule.showWarning
local bossBanner = MessageBannerModule.bossBanner
local bossBannerLabel = MessageBannerModule.bossBannerLabel

-- ----- Hand area -----

-- 110px reserved on the right so a full hand of cards never fans out under
-- the deck-remaining widget added further down (bottom-right, ~94px wide
-- including its margin).
local handFrame = Instance.new("Frame")
handFrame.Name = "HandFrame"
handFrame.Size = UDim2.new(1, -(SIDEBAR_WIDTH + 40 + 110), 0, 160)
handFrame.Position = UDim2.new(0, SIDEBAR_WIDTH + 20, 1, -230)
handFrame.BackgroundTransparency = 1
handFrame.Parent = root

local handLayout = Instance.new("UIListLayout")
handLayout.FillDirection = Enum.FillDirection.Horizontal
handLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
handLayout.VerticalAlignment = Enum.VerticalAlignment.Center
handLayout.Padding = UDim.new(0, 10)
handLayout.Parent = handFrame

-- ----- Action buttons -----

local actionFrame = Instance.new("Frame")
actionFrame.Name = "Actions"
actionFrame.Size = UDim2.new(1, -(SIDEBAR_WIDTH + 40), 0, 50)
actionFrame.Position = UDim2.new(0, SIDEBAR_WIDTH + 20, 1, -60)
actionFrame.BackgroundTransparency = 1
actionFrame.Parent = root

local actionLayout = Instance.new("UIListLayout")
actionLayout.FillDirection = Enum.FillDirection.Horizontal
actionLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
actionLayout.Padding = UDim.new(0, 20)
actionLayout.Parent = actionFrame

local function makeActionButton(text)
	local button = Instance.new("TextButton")
	button.Size = UDim2.new(0, 160, 1, 0)
	button.Font = Enum.Font.GothamBold
	button.TextSize = 18
	button.Text = text
	button.BackgroundColor3 = Color3.fromRGB(90, 60, 30)
	button.TextColor3 = Color3.fromRGB(250, 240, 220)
	button.Parent = actionFrame
	polishButton(button, 12)
	return button
end

local playButton = makeActionButton("Play Hand")
playButton.LayoutOrder = 1
addTooltip(playButton, "Play your selected cards as a hand")

-- LAYOUT FEATURE 4: Sort Hand (Rank/Suit), between Play Hand and Discard --
-- purely a client-side DISPLAY order (see sortedHandIndices + rebuildHand
-- further down). It never touches the server's actual hand array, so
-- there's no risk of the visual order and the real card-selection indices
-- (used by PlayHand/Discard) drifting apart.
local handSortMode = nil -- nil (as dealt) | "rank" | "suit"

-- Forward-declared for the same reason as the other refresh* functions --
-- assigned further down once rebuildHand/latestState exist.
local refreshHandSort

-- Wrapped in do...end per the LOCAL VARIABLE BUDGET note up top -- nothing
-- built in here needs to be reachable from outside except handSortMode and
-- refreshHandSort, both already forward-declared above.
do

local sortFrame = Instance.new("Frame")
sortFrame.Size = UDim2.new(0, 195, 1, 0)
sortFrame.BackgroundTransparency = 1
sortFrame.LayoutOrder = 2
sortFrame.Parent = actionFrame

local sortFrameLayout = Instance.new("UIListLayout")
sortFrameLayout.FillDirection = Enum.FillDirection.Horizontal
sortFrameLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
sortFrameLayout.VerticalAlignment = Enum.VerticalAlignment.Center
sortFrameLayout.Padding = UDim.new(0, 6)
sortFrameLayout.Parent = sortFrame

-- User feedback: "make it more obvious that it's sorting buttons" -- a
-- small "Sort:" caption to the left of the two buttons, so they don't read
-- as two random unlabeled buttons.
local sortCaptionLabel = Instance.new("TextLabel")
sortCaptionLabel.Size = UDim2.new(0, 40, 1, 0)
sortCaptionLabel.BackgroundTransparency = 1
sortCaptionLabel.Font = Enum.Font.Gotham
sortCaptionLabel.TextSize = 13
sortCaptionLabel.TextColor3 = Color3.fromRGB(220, 210, 190)
sortCaptionLabel.Text = "Sort:"
sortCaptionLabel.LayoutOrder = 1
sortCaptionLabel.Parent = sortFrame

local SORT_BUTTON_DEFAULT_COLOR = Color3.fromRGB(60, 45, 32)
local SORT_BUTTON_ACTIVE_COLOR = Color3.fromRGB(120, 90, 45)

local function makeSortButton(text, order)
	local button = Instance.new("TextButton")
	button.Size = UDim2.new(0, 65, 1, 0)
	button.Font = Enum.Font.GothamBold
	button.TextSize = 13
	button.Text = text
	button.BackgroundColor3 = SORT_BUTTON_DEFAULT_COLOR
	button.TextColor3 = Color3.fromRGB(250, 240, 220)
	button.LayoutOrder = order
	button.Parent = sortFrame
	polishButton(button, 8)
	return button
end

local sortByRankButton = makeSortButton("Rank", 2)
local sortBySuitButton = makeSortButton("Suit", 3)
addTooltip(sortByRankButton, "Sort your hand by card rank (2-A)")
addTooltip(sortBySuitButton, "Sort your hand by suit")

-- Highlights whichever sort mode is currently active, so the buttons also
-- double as a status readout ("Rank" lit up = your hand is sorted by rank).
local function refreshSortButtonHighlight()
	sortByRankButton.BackgroundColor3 = (handSortMode == "rank") and SORT_BUTTON_ACTIVE_COLOR or SORT_BUTTON_DEFAULT_COLOR
	sortBySuitButton.BackgroundColor3 = (handSortMode == "suit") and SORT_BUTTON_ACTIVE_COLOR or SORT_BUTTON_DEFAULT_COLOR
end

local function applyHandSortMode(mode)
	handSortMode = mode
	refreshSortButtonHighlight()
	if refreshHandSort then
		refreshHandSort()
	end
end

sortByRankButton.MouseButton1Click:Connect(function()
	playClickSfx(0.35)
	applyHandSortMode("rank")
end)
sortBySuitButton.MouseButton1Click:Connect(function()
	playClickSfx(0.35)
	applyHandSortMode("suit")
end)

end -- do (Sort Hand buttons)

local discardButton = makeActionButton("Discard")
discardButton.LayoutOrder = 3
addTooltip(discardButton, "Discard your selected cards and draw new ones")

-- ===== Deck-remaining widget, bottom-right =====
-- Extracted into Client/DeckWidget.lua. deckCountLabel is driven every
-- render() call, and deckWidgetButton is passed as a dep into
-- DeckTracker.lua below, so both come back out of the require() call.
local DeckWidgetModule = require(script.DeckWidget)({
	root = root,
	polishPanel = polishPanel,
	addSoftShadow = addSoftShadow,
	addTooltip = addTooltip,
})
local deckCountLabel = DeckWidgetModule.deckCountLabel
local deckWidgetButton = DeckWidgetModule.deckWidgetButton

-- deckCounts is [suit][rank] = count (see Deck.remainingCounts) -- sum it
-- up rather than hardcoding suit/rank names, so it stays correct even if
-- the engine's card set ever changes.
local function countRemainingInDeck(deckCounts)
	local total = 0
	if not deckCounts then
		return total
	end
	for _, suitCounts in pairs(deckCounts) do
		for _, count in pairs(suitCounts) do
			total = total + count
		end
	end
	return total
end

-- ===== Score popup: chips x mult animation on Play Hand =====
-- Extracted into Client/ScorePopup.lua. showScorePopup is called from
-- playButton's click handler elsewhere in this file, so it comes back out
-- of the require() call.
local ScorePopupModule = require(script.ScorePopup)({
	root = root,
	tweenTo = tweenTo,
})
local showScorePopup = ScorePopupModule.showScorePopup

-- ===== Confirm dialog (generic, reusable) =====
-- Extracted into Client/ConfirmDialog.lua. showConfirmDialog is passed as a
-- dep into Shop.lua below, so it comes back out of the require() call.
local ConfirmDialogModule = require(script.ConfirmDialog)({
	screenGui = screenGui,
	polishPanel = polishPanel,
	polishButton = polishButton,
	addSoftShadow = addSoftShadow,
	playClickSfx = playClickSfx,
})
local showConfirmDialog = ConfirmDialogModule.showConfirmDialog

-- ----- Shop overlay -----
-- Extracted into Client/Shop.lua (see that file for the deps list and the
-- full breakdown of what it builds) -- this is the first piece pulled out
-- as the client script gets split into smaller, per-feature files. It's a
-- ModuleScript, so it can't see this script's locals directly; everything
-- it needs is passed in explicitly via the deps table below. It hands back
-- shopFrame/nextRoundButton (still needed here for theme tweening and for
-- nextRoundButton's click handler, both wired further down) and the two
-- rebuild functions (called from render() whenever the shop's contents
-- need to refresh).
local Shop = require(script.Shop)({
	root = root,
	SIDEBAR_WIDTH = SIDEBAR_WIDTH,
	polishPanel = polishPanel,
	polishButton = polishButton,
	roundCorner = roundCorner,
	showWarning = showWarning,
	showConfirmDialog = showConfirmDialog,
	playClickSfx = playClickSfx,
	playSfx = playSfx,
	SOUND_IDS = SOUND_IDS,
	Patrons = Patrons,
	Recipes = Recipes,
	HousePasses = HousePasses,
	BuyPatronRemote = BuyPatronRemote,
	SellPatronRemote = SellPatronRemote,
	UseRecipeRemote = UseRecipeRemote,
	RerollShopRemote = RerollShopRemote,
	BuyPackRemote = BuyPackRemote,
	ResolvePackRemote = ResolvePackRemote,
	BuyHousePassRemote = BuyHousePassRemote,
	RANK_NAMES = RANK_NAMES,
	SUIT_SYMBOLS = SUIT_SYMBOLS,
	-- latestState is REASSIGNED (not mutated) each render() call, so Shop
	-- needs a live getter, not a value snapshotted once at construction time.
	getLatestState = function()
		return latestState
	end,
})
local shopFrame = Shop.shopFrame
local nextRoundButton = Shop.nextRoundButton
local rebuildShop = Shop.rebuildShop
local rebuildMyPatronsTab = Shop.rebuildMyPatronsTab
local rebuildMyRecipesTab = Shop.rebuildMyRecipesTab
local closeRecipeTargetPanel = Shop.closeTargetPanel

-- ===== Game over overlay + Menu screen =====
-- Extracted into Client/GameOver.lua and Client/Menu.lua. applyTheme() and
-- render() further down still need gameOverFrame/playAgainButton, and the
-- menu buttons are needed both by the "Menu -> game transition" glue right
-- below and as deps into HowToPlay.lua/Journey.lua/RunSetup.lua (which wire
-- their own click handlers onto the menu buttons), so everything comes
-- back out of both require() calls.
local GameOverPanel = require(script.GameOver)({
	root = root,
	polishPanel = polishPanel,
	polishButton = polishButton,
	addSoftShadow = addSoftShadow,
})
local gameOverFrame = GameOverPanel.gameOverFrame
local playAgainButton = GameOverPanel.playAgainButton

local MenuScreen = require(script.Menu)({
	screenGui = screenGui,
	polishButton = polishButton,
})
local menuFrame = MenuScreen.menuFrame
local menuPlayButton = MenuScreen.menuPlayButton
local menuHowToPlayButton = MenuScreen.menuHowToPlayButton
local menuJourneyButton = MenuScreen.menuJourneyButton
local menuNewRunButton = MenuScreen.menuNewRunButton

-- ===== How to Play overlay (reachable from menu or in-game) =====
-- Extracted into Client/HowToPlay.lua -- fully self-contained (both buttons
-- that open it are wired from inside the module), so nothing needs to come
-- back out of the require() call.
require(script.HowToPlay)({
	screenGui = screenGui,
	polishPanel = polishPanel,
	polishButton = polishButton,
	roundCorner = roundCorner,
	addSoftShadow = addSoftShadow,
	playClickSfx = playClickSfx,
	RED_SUITS = RED_SUITS,
	RANK_NAMES = RANK_NAMES,
	SUIT_SYMBOLS = SUIT_SYMBOLS,
	HandEvaluator = HandEvaluator,
	Scoring = Scoring,
	menuHowToPlayButton = menuHowToPlayButton,
	helpButton = helpButton,
})

-- ===== Themes (cosmetics) overlay =====
-- Extracted into Client/Themes.lua. render() still needs to check
-- themesBackdrop.Visible and call refreshThemesList() (see below), so both
-- come back out of the require() call, same pattern as Shop.lua.
local ThemesOverlay = require(script.Themes)({
	screenGui = screenGui,
	polishPanel = polishPanel,
	polishButton = polishButton,
	roundCorner = roundCorner,
	addSoftShadow = addSoftShadow,
	playClickSfx = playClickSfx,
	playSfx = playSfx,
	SOUND_IDS = SOUND_IDS,
	Themes = Themes,
	BuyThemeRemote = BuyThemeRemote,
	EquipThemeRemote = EquipThemeRemote,
	showWarning = showWarning,
	themesButton = themesButton,
	getLatestState = function()
		return latestState
	end,
})
local themesBackdrop = ThemesOverlay.themesBackdrop
local refreshThemesList = ThemesOverlay.refreshThemesList

-- ===== Road Ahead (journey/roadmap) overlay =====
-- Extracted into Client/Journey.lua. render() still needs to check
-- journeyBackdrop.Visible and call refreshJourney(), so both come back out
-- of the require() call, same pattern as Themes.lua.
local JourneyOverlay = require(script.Journey)({
	screenGui = screenGui,
	polishPanel = polishPanel,
	polishButton = polishButton,
	roundCorner = roundCorner,
	addSoftShadow = addSoftShadow,
	playClickSfx = playClickSfx,
	tweenTo = tweenTo,
	DifficultyTiers = DifficultyTiers,
	BossRounds = BossRounds,
	RunStateEngine = RunStateEngine,
	Players = Players,
	player = player,
	journeyButton = journeyButton,
	menuJourneyButton = menuJourneyButton,
	getLatestState = function()
		return latestState
	end,
	getCurrentTheme = function()
		return currentTheme
	end,
})
local journeyBackdrop = JourneyOverlay.journeyBackdrop
local refreshJourney = JourneyOverlay.refreshJourney

-- ===== Poker Hands reference overlay =====
-- Extracted into Client/PokerHandsReference.lua. Fully self-contained (only
-- opened from its own corner button), so nothing needs to come back out of
-- the require() call.
require(script.PokerHandsReference)({
	screenGui = screenGui,
	polishPanel = polishPanel,
	polishButton = polishButton,
	addSoftShadow = addSoftShadow,
	playClickSfx = playClickSfx,
	handRefButton = handRefButton,
	HandEvaluator = HandEvaluator,
	Scoring = Scoring,
	getLatestState = function()
		return latestState
	end,
})

-- ===== Deck Tracker overlay =====
-- Extracted into Client/DeckTracker.lua. Fully self-contained (only opened
-- from deckWidgetButton, which is passed in as a dep), so nothing needs to
-- come back out of the require() call.
require(script.DeckTracker)({
	screenGui = screenGui,
	polishPanel = polishPanel,
	polishButton = polishButton,
	roundCorner = roundCorner,
	addSoftShadow = addSoftShadow,
	playClickSfx = playClickSfx,
	deckWidgetButton = deckWidgetButton,
	Deck = Deck,
	RANK_NAMES = RANK_NAMES,
	SUIT_SYMBOLS = SUIT_SYMBOLS,
	SUIT_DISPLAY_ORDER = SUIT_DISPLAY_ORDER,
	RED_SUITS = RED_SUITS,
	getLatestState = function()
		return latestState
	end,
})

-- ===== Settings overlay =====
-- Extracted into Client/Settings.lua. Fully self-contained (only opened
-- from its own corner button), so nothing needs to come back out of the
-- require() call.
require(script.Settings)({
	screenGui = screenGui,
	polishPanel = polishPanel,
	polishButton = polishButton,
	addSoftShadow = addSoftShadow,
	playClickSfx = playClickSfx,
	settingsButton = settingsButton,
	makeStepperRow = makeStepperRow,
	backgroundMusic = backgroundMusic,
})

-- ===== Run Setup overlay =====
-- Extracted into Client/RunSetup.lua. Fully self-contained (only opened
-- from the menu's "New Run..." button), so nothing needs to come back out
-- of the require() call.
require(script.RunSetup)({
	screenGui = screenGui,
	root = root,
	menuFrame = menuFrame,
	polishPanel = polishPanel,
	polishButton = polishButton,
	roundCorner = roundCorner,
	addSoftShadow = addSoftShadow,
	playClickSfx = playClickSfx,
	playSfx = playSfx,
	SOUND_IDS = SOUND_IDS,
	DeckVariants = DeckVariants,
	DifficultyTiers = DifficultyTiers,
	StartRunRemote = StartRunRemote,
	backgroundMusic = backgroundMusic,
	menuNewRunButton = menuNewRunButton,
})

-- ===== Menu -> game transition, volume cycling =====

menuPlayButton.MouseButton1Click:Connect(function()
	playClickSfx()
	menuFrame.Visible = false
	root.Visible = true
	if backgroundMusic.SoundId ~= "rbxassetid://0" and backgroundMusic.Volume > 0 then
		backgroundMusic:Play()
	end
end)

volumeButton.MouseButton1Click:Connect(function()
	volumeStepIndex = (volumeStepIndex % #VOLUME_STEPS) + 1
	local newVolume = VOLUME_STEPS[volumeStepIndex]
	backgroundMusic.Volume = newVolume
	volumeButton.Text = VOLUME_ICONS[volumeStepIndex]
	if newVolume <= 0 then
		backgroundMusic:Stop()
	elseif backgroundMusic.SoundId ~= "rbxassetid://0" and not backgroundMusic.IsPlaying then
		backgroundMusic:Play()
	end
end)

-- ===== Client-side state =====
-- (latestState itself now declared near the top of the file -- see the
-- comment there.)

local selected = {} -- [handIndex] = true
local hoveredIndex = nil -- single index or nil; only one card can be "pointed at"
local cardButtons = {} -- [handIndex] = TextButton
local cardScales = {} -- [handIndex] = UIScale
-- LAYOUT FEATURE 4 (Sort Hand): [handIndex] = visual left-to-right position
-- (1, 2, 3, ...). Needed because the hover neighbor-lift effect below has to
-- compare who's actually NEXT TO whom on screen, not whose server-side hand
-- index happens to be numerically close -- those two stop matching as soon
-- as a sort mode is active.
local cardVisualPosition = {}

-- Tracks what the hand actually WAS last rebuild (order-independent), so
-- the deal-in animation below only plays when the cards themselves
-- changed (a fresh hand after Play/Discard) -- not on every single
-- rebuildHand() call, which also fires for unrelated state pushes (buying
-- in the shop, equipping a theme) and for Sort Hand clicks, where the
-- exact same cards just need to reflow, not re-deal from the deck.
local lastHandSignature = nil

-- Set right before firing PlayHand/Discard to the number of cards being
-- replaced -- consumed by the very next rebuildHand() to animate ONLY the
-- newly-drawn replacement cards, not the ones you kept. nil (not just
-- unset-and-ignored) whenever a full fresh hand should deal in instead
-- (round start / Next Round / Restart / New Run), since those don't go
-- through Play/Discard at all.
local pendingNewCardCount = nil

local BASE_SCALE = 1.0
local HOVER_SCALE = 1.06
local SELECTED_SCALE = 1.08
local SELECTED_HOVER_SCALE = 1.14

-- FEATURE 2: card hover "fan" -- hovering a card lifts it; its immediate
-- neighbors lift a little too, falling off with distance, like fanning a
-- hand of cards toward your thumb. Pure position/scale tweening, no color
-- or transparency tricks, so this is safe against the addGloss-style bug.
local HOVER_LIFT = 10
local SELECTED_LIFT = 6
local HOVER_FALLOFF_DISTANCE = 2 -- neighbors within this many slots lift a bit too

-- ----- Theme (cosmetics) application -----
-- (currentTheme itself now declared near the top of the file -- see the
-- comment there.)

local lastEquippedThemeId = nil

local function applyTheme(themeId)
	currentTheme = Themes.getById(themeId) or Themes.getById(Themes.DefaultThemeId)
	local colors = currentTheme.colors

	tweenTo(root, { BackgroundColor3 = colors.background }, 0.25)
	tweenTo(sidebar, { BackgroundColor3 = colors.panelBg }, 0.25)
	tweenTo(shopFrame, { BackgroundColor3 = colors.panelBg }, 0.25)
	tweenTo(gameOverFrame, { BackgroundColor3 = colors.panelBg }, 0.25)
	tweenTo(playButton, { BackgroundColor3 = colors.accent }, 0.25)
	tweenTo(discardButton, { BackgroundColor3 = colors.accent }, 0.25)
	tweenTo(nextRoundButton, { BackgroundColor3 = colors.accent }, 0.25)
	tweenTo(playAgainButton, { BackgroundColor3 = colors.accent }, 0.25)
end

-- ===== Collection Gallery overlay =====
-- Extracted into Client/Collection.lua. Fully self-contained (only opened
-- from its own corner button), so nothing needs to come back out of the
-- require() call.
require(script.Collection)({
	screenGui = screenGui,
	polishPanel = polishPanel,
	polishButton = polishButton,
	roundCorner = roundCorner,
	addSoftShadow = addSoftShadow,
	playClickSfx = playClickSfx,
	collectionButton = collectionButton,
	Patrons = Patrons,
	Themes = Themes,
	getLatestState = function()
		return latestState
	end,
})

-- ===== "Unlocked!" popup + Round reward popup =====
-- Extracted into Client/UnlockPopup.lua and Client/RoundRewardPopup.lua.
-- render() further down still needs to call showUnlockPopup()/
-- showRoundReward() (and tracks its own lastOwnedPatronIds/
-- lastOwnedThemeIds/hasRenderedOnce/lastPhase state to know when to), so
-- both functions come back out of their require() calls.
local UnlockPopupModule = require(script.UnlockPopup)({
	screenGui = screenGui,
	polishPanel = polishPanel,
	tweenTo = tweenTo,
})
local showUnlockPopup = UnlockPopupModule.showUnlockPopup

local RoundRewardPopupModule = require(script.RoundRewardPopup)({
	screenGui = screenGui,
	polishPanel = polishPanel,
	tweenTo = tweenTo,
	playSfx = playSfx,
	SOUND_IDS = SOUND_IDS,
})
local showRoundReward = RoundRewardPopupModule.showRoundReward

local lastOwnedPatronIds = {}
local lastOwnedThemeIds = {}
local hasRenderedOnce = false
local lastPhase = nil

local function selectedIndicesArray()
	local out = {}
	for index in pairs(selected) do
		table.insert(out, index)
	end
	table.sort(out)
	return out
end

-- usePop: true gives a snappy "Back" easing overshoot (used on click),
-- false gives a smooth hover-in/out (used on MouseEnter/MouseLeave).
local function refreshCardVisual(index, usePop)
	local button = cardButtons[index]
	local scaleObject = cardScales[index]
	if not button or not scaleObject then
		return
	end

	local isSelected = selected[index] == true
	local isHovering = hoveredIndex == index

	-- Fan falloff: neighbors near the hovered card lift a little too,
	-- fading out with distance. Distance 0 (the hovered card itself) is
	-- handled by isHovering above.
	--
	-- LAYOUT FEATURE 4 (Sort Hand): "neighbor" has to mean visually adjacent
	-- on screen, not adjacent server-side hand index -- those two only match
	-- when the hand is unsorted. Compare cardVisualPosition (left-to-right
	-- display slot), not index/hoveredIndex directly.
	local fanLift = 0
	if hoveredIndex ~= nil and not isHovering then
		local myPosition = cardVisualPosition[index]
		local hoveredPosition = cardVisualPosition[hoveredIndex]
		local distance = (myPosition and hoveredPosition) and math.abs(myPosition - hoveredPosition) or math.huge
		if distance < HOVER_FALLOFF_DISTANCE then
			fanLift = (1 - (distance / HOVER_FALLOFF_DISTANCE)) * (HOVER_LIFT * 0.4)
		end
	end

	local targetColor
	if isSelected then
		targetColor = currentTheme.colors.cardSelected
	else
		targetColor = currentTheme.colors.cardBase
	end

	local targetScale
	if isSelected and isHovering then
		targetScale = SELECTED_HOVER_SCALE
	elseif isSelected then
		targetScale = SELECTED_SCALE
	elseif isHovering then
		targetScale = HOVER_SCALE
	else
		targetScale = BASE_SCALE
	end

	local lift = (isSelected and SELECTED_LIFT or 0) + (isHovering and HOVER_LIFT or fanLift)

	tweenTo(button, {
		BackgroundColor3 = targetColor,
		Position = UDim2.new(0.5, 0, 0.5, -lift),
	}, 0.15)
	if usePop then
		tweenTo(scaleObject, { Scale = targetScale }, 0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	else
		tweenTo(scaleObject, { Scale = targetScale }, 0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	end
end

local function refreshAllCardVisuals()
	for index in pairs(cardButtons) do
		refreshCardVisual(index, false)
	end
end

-- LAYOUT FEATURE 6 (and 7's score popup below): the one place that knows
-- how to preview a hand's score. Mirrors RunState.lua's playHand exactly:
-- same HandEvaluator.evaluate + Scoring.calculate calls, same context shape
-- (handsRemaining is "if I played this NOW", i.e. one less than current,
-- since that's what the real call would see). ownedPatrons has to be
-- turned from the server's lightweight {id,name,description} payload back
-- into real Patron instances via Patrons.getById, since only the real
-- instances carry the .effect(...) function Scoring.calculate needs.
-- Returns nil if cardIndices doesn't resolve to a previewable hand.
local function computeHandPreview(cardIndices)
	if not latestState then
		return nil
	end

	local selectedCards = {}
	for _, index in ipairs(cardIndices) do
		local card = latestState.hand[index]
		if card then
			table.insert(selectedCards, card)
		end
	end

	if #selectedCards == 0 then
		return nil
	end

	local ok, handResult = pcall(HandEvaluator.evaluate, selectedCards)
	if not ok or not handResult then
		return nil
	end

	local ownedPatronInstances = {}
	for _, patron in ipairs(latestState.ownedPatrons or {}) do
		local def = Patrons.getById(patron.id)
		if def then
			table.insert(ownedPatronInstances, def)
		end
	end

	local previewHandsRemaining = math.max(0, latestState.handsRemaining - 1)
	local ok2, score, chips, mult = pcall(Scoring.calculate, handResult, ownedPatronInstances, {
		allPlayedCards = selectedCards,
		handsRemaining = previewHandsRemaining,
		discardsRemaining = latestState.discardsRemaining,
		isLastHand = previewHandsRemaining == 0,
		night = latestState.night,
		round = latestState.round,
	})

	if not ok2 then
		return nil
	end

	return { name = handResult.name, chips = chips, mult = mult, score = score }
end

local function refreshScorePreview()
	if not latestState then
		scorePreviewLabel.Text = "0  x  0"
		return
	end

	local selectedIndices = {}
	for index in pairs(selected) do
		table.insert(selectedIndices, index)
	end

	local preview = computeHandPreview(selectedIndices)
	if not preview then
		scorePreviewLabel.Text = "Select cards..."
		return
	end

	scorePreviewLabel.Text = string.format("%s\n%d x %d = %d", preview.name, preview.chips, preview.mult, preview.score)
end

local function onCardClicked(index)
	if selected[index] then
		selected[index] = nil
	else
		-- Cap selection at 5 cards (max hand size in this game).
		local count = 0
		for _ in pairs(selected) do
			count = count + 1
		end
		if count >= 5 then
			return
		end
		selected[index] = true
	end
	playSfx(SOUND_IDS.cardToggle, 3, 0.35)
	refreshCardVisual(index, true)
	refreshScorePreview()
end

-- LAYOUT FEATURE 4 (Sort Hand): returns an array of indices INTO handData,
-- in the order cards should be displayed left-to-right. Purely a display
-- order -- handData itself (the server's actual hand array) is never
-- reordered, so selection/PlayHand/Discard (which work off the ORIGINAL
-- index, not visual position) stay correct regardless of sort mode.
local RANK_SORT_INDEX = {}
for i, rank in ipairs(Deck.RankOrder) do
	RANK_SORT_INDEX[rank] = i
end
local SUIT_SORT_INDEX = {}
for i, suit in ipairs(SUIT_DISPLAY_ORDER) do
	SUIT_SORT_INDEX[suit] = i
end

local function sortedHandIndices(handData, sortMode)
	local order = {}
	for i in ipairs(handData) do
		table.insert(order, i)
	end
	if sortMode == "rank" then
		table.sort(order, function(a, b)
			local cardA, cardB = handData[a], handData[b]
			local rankA, rankB = RANK_SORT_INDEX[cardA.rank] or 99, RANK_SORT_INDEX[cardB.rank] or 99
			if rankA ~= rankB then
				return rankA < rankB
			end
			return (SUIT_SORT_INDEX[cardA.suit] or 99) < (SUIT_SORT_INDEX[cardB.suit] or 99)
		end)
	elseif sortMode == "suit" then
		table.sort(order, function(a, b)
			local cardA, cardB = handData[a], handData[b]
			local suitA, suitB = SUIT_SORT_INDEX[cardA.suit] or 99, SUIT_SORT_INDEX[cardB.suit] or 99
			if suitA ~= suitB then
				return suitA < suitB
			end
			return (RANK_SORT_INDEX[cardA.rank] or 99) < (RANK_SORT_INDEX[cardB.rank] or 99)
		end)
	end
	return order
end

-- Order-independent so a Sort Hand click (same cards, different order)
-- doesn't register as a "new" hand -- see lastHandSignature above.
local function handSignature(handData)
	local parts = {}
	for _, card in ipairs(handData) do
		table.insert(parts, card.suit .. tostring(card.rank))
	end
	table.sort(parts)
	return table.concat(parts, ",")
end

local function rebuildHand(handData)
	local newSignature = handSignature(handData)
	local isNewHand = newSignature ~= lastHandSignature
	lastHandSignature = newSignature

	-- dealFromIndex: raw hand indices >= this are the ones that should fly
	-- in. If pendingNewCardCount is set, only the trailing N raw indices
	-- (the newly-drawn replacements -- see removeIndicesFromHand in
	-- RunState.lua) deal in; everything before that is a KEPT card and
	-- should just be redrawn in place. Otherwise (round start / Next Round
	-- / Restart / New Run) the whole hand is fresh, so deal everyone in.
	local dealFromIndex = 1
	if isNewHand and pendingNewCardCount then
		dealFromIndex = math.max(1, #handData - pendingNewCardCount + 1)
	end
	pendingNewCardCount = nil

	for _, child in ipairs(handFrame:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	cardButtons = {}
	cardScales = {}
	cardVisualPosition = {}
	selected = {}
	hoveredIndex = nil

	local displayOrder = sortedHandIndices(handData, handSortMode)

	for visualPosition, index in ipairs(displayOrder) do
		local card = handData[index]

		-- A fixed-size "slot" keeps UIListLayout stable; the button inside
		-- it can grow past the slot's bounds on hover/select without
		-- shoving the other cards around.
		local slot = Instance.new("Frame")
		slot.Size = UDim2.new(0, 70, 0, 100)
		slot.BackgroundTransparency = 1
		slot.LayoutOrder = visualPosition
		slot.Parent = handFrame

		local button = Instance.new("TextButton")
		button.Size = UDim2.fromScale(1, 1)
		button.Position = UDim2.fromScale(0.5, 0.5)
		button.AnchorPoint = Vector2.new(0.5, 0.5)
		button.Font = Enum.Font.GothamBold
		button.TextSize = 20
		button.BackgroundColor3 = currentTheme.colors.cardBase
		button.TextColor3 = RED_SUITS[card.suit] and Color3.fromRGB(180, 30, 30) or Color3.fromRGB(20, 20, 20)
		button.Text = string.format("%s\n%s", RANK_NAMES[card.rank] or tostring(card.rank), SUIT_SYMBOLS[card.suit] or "?")
		button.Parent = slot
		polishButton(button, 8)

		-- PHASE 1B: Garnish/Special/Stamp visual treatment. Doesn't need
		-- full card art (see the feature-expansion project doc's stated v1
		-- scope) -- just a small corner badge with the relevant icon(s) so a
		-- modified card visibly reads as modified in the hand. Priority
		-- order (rarest/most-impactful first) when a card has more than one:
		-- Special, then Stamp, then Garnish.
		if card.garnish or card.special or card.stamp then
			local icons = {}
			if card.special and Card.Specials[card.special] then
				table.insert(icons, Card.Specials[card.special].icon)
			end
			if card.stamp and Card.Stamps[card.stamp] then
				table.insert(icons, Card.Stamps[card.stamp].icon)
			end
			if card.garnish and Card.Garnishes[card.garnish] then
				table.insert(icons, Card.Garnishes[card.garnish].icon)
			end

			local badge = Instance.new("TextLabel")
			badge.AnchorPoint = Vector2.new(1, 0)
			badge.Position = UDim2.new(1, -2, 0, 2)
			badge.Size = UDim2.new(0, 0, 0, 16)
			badge.AutomaticSize = Enum.AutomaticSize.X
			badge.BackgroundTransparency = 1
			badge.Font = Enum.Font.GothamBold
			badge.TextSize = 12
			badge.TextColor3 = Color3.fromRGB(255, 255, 255)
			badge.TextStrokeTransparency = 0.3
			badge.Text = table.concat(icons, "")
			badge.ZIndex = 2
			badge.Parent = slot
		end

		local scaleObject = Instance.new("UIScale")
		scaleObject.Scale = BASE_SCALE
		scaleObject.Parent = button

		-- LAYOUT FEATURE 8: deal the card in from the deck widget (bottom
		-- right of the screen) instead of it just popping into place --
		-- only for cards that are actually new (index >= dealFromIndex; see
		-- above), so kept cards after a Play/Discard don't re-deal too.
		if isNewHand and index >= dealFromIndex then
			button.Position = UDim2.new(0.5, 380, 0.5, 50)
			button.Rotation = 14
			task.delay((visualPosition - 1) * 0.05, function()
				if button.Parent then
					tweenTo(button, { Position = UDim2.fromScale(0.5, 0.5), Rotation = 0 }, 0.24, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
				end
			end)
		end

		cardButtons[index] = button
		cardScales[index] = scaleObject
		cardVisualPosition[index] = visualPosition

		button.MouseButton1Click:Connect(function()
			onCardClicked(index)
		end)
		button.MouseEnter:Connect(function()
			hoveredIndex = index
			refreshAllCardVisuals()
		end)
		button.MouseLeave:Connect(function()
			if hoveredIndex == index then
				hoveredIndex = nil
			end
			refreshAllCardVisuals()
		end)
	end
end

refreshHandSort = function()
	if latestState then
		rebuildHand(latestState.hand)
	end
end

local function render(state)
	latestState = state

	if state.equippedTheme ~= lastEquippedThemeId then
		applyTheme(state.equippedTheme)
		lastEquippedThemeId = state.equippedTheme
	end

	nightRoundLabel.Text = string.format("Night %d - Round %d", state.night, state.round)
	tipsLabel.Text = string.format("Tips: %d", state.tips)
	handsDiscardsLabel.Text = string.format("Hands: %d  Discards: %d", state.handsRemaining, state.discardsRemaining)
	deckCountLabel.Text = string.format("%d/52", countRemainingInDeck(state.deckCounts))

	-- LAYOUT FEATURE 5: fill in the Patron slot icons. Since the Patron
	-- slot cap (RunState.patronSlotLimit, default 5) went in, this row
	-- shows YOUR TABLE -- exactly `slotLimit` boxes, filled with the
	-- Patrons you actually own -- NOT a 22-wide preview of the whole
	-- roster (that "which have I collected" view already lives on the
	-- Collection Gallery screen, where it belongs). Slot i shows
	-- state.ownedPatrons[i] if you own that many, otherwise it's an open
	-- seat; slots past the current limit are hidden entirely so the row
	-- never implies more capacity than you actually have.
	do
		local ownedPatrons = state.ownedPatrons or {}
		local slotLimit = math.min(state.patronSlotLimit or #ownedPatrons, MAX_SIDEBAR_PATRON_SLOTS)
		for i = 1, MAX_SIDEBAR_PATRON_SLOTS do
			local slot = patronSlots[i]
			if slot then
				if i > slotLimit then
					slot.frame.Visible = false
				else
					slot.frame.Visible = true
					local owned = ownedPatrons[i]
					if owned then
						slot.frame.BackgroundColor3 = Color3.fromRGB(90, 60, 30)
						slot.label.TextColor3 = Color3.fromRGB(250, 240, 220)
						slot.label.Text = owned.name:sub(1, 1)
					else
						slot.frame.BackgroundColor3 = Color3.fromRGB(45, 40, 38)
						slot.label.TextColor3 = Color3.fromRGB(120, 115, 110)
						slot.label.Text = "+" -- open seat, not "?" -- there's nothing hidden here anymore
					end
				end
			end
		end
		patronsCountLabel.Text = string.format("%d/%d", #ownedPatrons, slotLimit)
	end

	-- LAYOUT FEATURE 2: reward mirrors RunState.lua's playHand payout exactly
	-- (tipsPerRoundWin, doubled on a Boss Round) so the sidebar never shows a
	-- number that doesn't match what you actually get paid.
	local reward = RunStateEngine.DefaultConfig.tipsPerRoundWin
	if state.bossModifier then
		reward = reward + RunStateEngine.DefaultConfig.tipsPerRoundWin
	end
	scoreLabel.Text = string.format("Score: %d / %d\nReward: $%d", state.roundScore, state.targetScore, reward)

	if state.bossModifier then
		blindInfoLabel.Text = string.format("👑 %s\n%s", state.bossModifier.name, state.bossModifier.description)
	else
		blindInfoLabel.Text = string.format("Round %d", state.round)
	end

	if state.bossModifier then
		bossBanner.Visible = true
		bossBannerLabel.Text = string.format("👑 Boss Round -- %s: %s", state.bossModifier.name, state.bossModifier.description)
	else
		bossBanner.Visible = false
	end

	rebuildHand(state.hand)
	refreshScorePreview() -- rebuildHand just reset `selected` to empty

	if themesBackdrop.Visible then
		refreshThemesList() -- keep the panel accurate if it's open across a purchase
	end
	if journeyBackdrop.Visible then
		refreshJourney() -- keep "you are here" accurate if it's open across a round change
	end

	-- FEATURE 12: detect newly-owned Patrons/Themes and celebrate the first
	-- one with an "Unlocked!" popup. Skipped on the very first render
	-- (session start) so the default theme/starting state doesn't look
	-- "unlocked".
	do
		local ownedPatronIds = {}
		local newPatron = nil
		for _, patron in ipairs(state.ownedPatrons or {}) do
			ownedPatronIds[patron.id] = true
			if hasRenderedOnce and not lastOwnedPatronIds[patron.id] and not newPatron then
				newPatron = patron
			end
		end

		local ownedThemeIdSet = {}
		local newThemeId = nil
		for _, id in ipairs(state.ownedThemeIds or {}) do
			ownedThemeIdSet[id] = true
			if hasRenderedOnce and not lastOwnedThemeIds[id] and not newThemeId then
				newThemeId = id
			end
		end

		if newPatron then
			showUnlockPopup(newPatron.name, newPatron.description)
		elseif newThemeId then
			local theme = Themes.getById(newThemeId)
			if theme then
				showUnlockPopup(theme.name, theme.description)
			end
		end

		lastOwnedPatronIds = ownedPatronIds
		lastOwnedThemeIds = ownedThemeIdSet
		hasRenderedOnce = true
	end

	-- Round reward popup: fire once, right on the transition INTO "shop"
	-- (i.e. the round was just won), not on every re-render while already
	-- shopping (e.g. after buying a Patron, phase is still "shop").
	if state.phase == "shop" and lastPhase ~= "shop" and hasRenderedOnce and showRoundReward then
		showRoundReward(reward)
	end
	lastPhase = state.phase

	shopFrame.Visible = (state.phase == "shop")
	gameOverFrame.Visible = (state.phase == "gameover")
	if state.phase == "shop" then
		rebuildShop(state)
		rebuildMyPatronsTab(state)
		rebuildMyRecipesTab(state)
	else
		-- Left the shop (round advanced, or the run ended) -- close the
		-- Recipe card/suit picker if it was left open, so it doesn't show up
		-- stale (still mid-selection for a recipe from last visit) the next
		-- time the shop opens.
		closeRecipeTargetPanel()
	end

	if state.phase == "gameover" then
		gameOverLabel.Text = string.format(
			"Last call! You made it to Night %d, Round %d.",
			state.night, state.round
		)
	end
end

-- ===== Wire up buttons =====

playButton.MouseButton1Click:Connect(function()
	if not latestState or latestState.phase ~= "playing" then
		return
	end
	local indices = selectedIndicesArray()
	if #indices < 1 then
		showWarning("Select 1-5 cards first.")
		return
	end
	playSfx(SOUND_IDS.playHand)

	-- LAYOUT FEATURE 7: pop the score BEFORE firing the remote, off the same
	-- preview computation the sidebar already uses -- see computeHandPreview.
	local preview = computeHandPreview(indices)
	if preview then
		showScorePopup(preview)
	end

	-- The server (RunState.playHand -> removeIndicesFromHand) always keeps
	-- surviving cards in their original relative order and appends the
	-- newly-drawn replacements at the END of state.hand -- so the next
	-- rebuildHand() knows exactly how many trailing raw indices are the
	-- freshly dealt ones. See pendingNewCardCount / dealFromIndex there.
	pendingNewCardCount = #indices

	PlayHandRemote:FireServer(indices)
end)

discardButton.MouseButton1Click:Connect(function()
	if not latestState or latestState.phase ~= "playing" then
		return
	end
	if latestState.discardsRemaining <= 0 then
		showWarning("No discards left this round.")
		return
	end
	local indices = selectedIndicesArray()
	if #indices < 1 then
		showWarning("Select 1-5 cards to discard.")
		return
	end
	playSfx(SOUND_IDS.discard)
	pendingNewCardCount = #indices -- see the matching comment on Play Hand above
	DiscardRemote:FireServer(indices)
end)

nextRoundButton.MouseButton1Click:Connect(function()
	playClickSfx()
	AdvanceRoundRemote:FireServer()
end)

playAgainButton.MouseButton1Click:Connect(function()
	playClickSfx()
	RestartRunRemote:FireServer()
end)

StateUpdatedRemote.OnClientEvent:Connect(function(state)
	render(state)
end)
