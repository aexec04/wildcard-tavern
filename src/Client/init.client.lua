--[[
	Client/init.client.lua
	A deliberately plain, functional UI so the game is playable and
	publishable this week. It is built entirely in code (no pre-made UI in
	Studio) so it works the moment you sync with Rojo -- swap in your own
	art, fonts, and layout once the loop feels fun. Nothing here is
	precious; feel free to gut this file once you're comfortable in Studio.

	This version adds: a menu screen, a How to Play overlay, card
	hover/select animations, and sound hooks (menu + card clicks + a
	looping background track). See the SoundModule.SOUND_IDS block below -- you need
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
local UserInputService = game:GetService("UserInputService")
local MarketplaceService = game:GetService("MarketplaceService") -- Game Pass purchase prompts (see Shared/Engine/GamePasses.lua)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local PlayHandRemote = remotes:WaitForChild("PlayHand")
local DiscardRemote = remotes:WaitForChild("Discard")
local BuyPatronRemote = remotes:WaitForChild("BuyPatron")
local SellPatronRemote = remotes:WaitForChild("SellPatron")
local AdvanceRoundRemote = remotes:WaitForChild("AdvanceRound")
-- ROUND SELECT FEATURE: confirm playing the current round, or skip it for
-- its currently-revealed Tag instead (see Client/RoundSelect.lua).
local SelectRoundRemote = remotes:WaitForChild("SelectRound")
local SkipRoundRemote = remotes:WaitForChild("SkipRound")
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

-- Real-money Robux Game Passes (see Shared/Engine/GamePasses.lua) -- static
-- content read straight from Shared, static content read straight from Shared.
local GamePasses = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("GamePasses"))
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
-- Patrons above -- the server only sends which ones are OWNED.
local Recipes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("Recipes"))
-- PHASE 1B (hand visual treatment): need Card.Garnishes/Specials/Stamps'
-- icon fields to show a small corner badge on modified cards in the hand.
local Card = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("Card"))
-- PHASE 2 (My House Passes display): HousePasses.Definitions is static
-- content, same "client reads the catalog directly" pattern as
-- Patrons/Recipes above -- the server only sends which ids are owned
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

-- The UI uses one fixed palette (Client/Palette.lua). Declared up here so
-- every overlay can read it (same reasoning as latestState).
local currentTheme = require(script.Palette)

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
-- SoundModule.playSfx/SoundModule.playClickSfx/SoundModule.SOUND_IDS as deps, so this is required first.
local SoundModule = require(script.Sound)({
	SoundService = SoundService,
})
require(script.Cue).set(SoundModule.playCue) -- named cues (Engine/SoundIds) for any module
-- VOLUME_STEPS (the old loud/quiet/mute click-to-cycle table) is gone --
-- volumeButton opens VolumePanel.lua's real slider panel now instead of
-- cycling, so only the icon table + its initial index are still needed
-- (for the button's starting glyph; VolumePanel.lua takes it from here).

-- Title theme starts the instant the game loads (the main menu is visible
-- from the very first frame -- see Client/Menu.lua) -- everything after
-- this point that leaves the menu (either button below) hands music
-- control off to render()'s own SoundModule.setMusicTrack call, which switches to
-- gameplay/boss/shop based on live state every time it's called.
SoundModule.setMusicTrack("title")

-- ===== Visual + stepper-row helpers =====
-- Extracted into Client/VisualHelpers.lua. Required right after Sound.lua
-- since VisualHelpersModule.makeStepperRow needs SoundModule.playClickSfx. Nearly every overlay module
-- below takes VisualHelpersModule.tweenTo/VisualHelpersModule.polishPanel/VisualHelpersModule.polishButton/VisualHelpersModule.roundCorner/VisualHelpersModule.addSoftShadow
-- as deps.
local VisualHelpersModule = require(script.VisualHelpers)({
	TweenService = TweenService,
	UserInputService = UserInputService,
	playClickSfx = SoundModule.playClickSfx,
})
-- POLISH PASS (post-Phase-7): generic modal pop-in/out + the two small
-- "react to a value changing" pulses, see VisualHelpers.lua's own header
-- comment for what each is for and why they're split the way they are.
-- POLISH PASS Batch 2: button hover/press feedback + a one-shot staggered
-- reveal for a list of instances (Menu.lua's load-in, Shop.lua's offer rows).

-- ===== Root UI =====

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "GameUI"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.Parent = playerGui
do -- touch/phone pass (safe area, 14px text, 44px taps); no-op on desktop
	pcall(function() require(script.PhoneUI).install(screenGui) end)
end

-- REFERENCE-MATCH PASS (Nov 1 2026): the reference mockup uses a warm
-- book-style serif everywhere; the game used Gotham (a modern sans) in
-- ~180 separate places across every Client module. Rather than touch all
-- of them, swap any Gotham-family font on anything inside this ScreenGui
-- to Merriweather, both for what already exists and for everything
-- created later (cards, shop rows, popups...). task.defer runs the swap
-- after the creating code has finished setting its properties. Wrapped in
-- do...end -- this file is at Lua's 200-local ceiling.
do
	local serif = "rbxasset://fonts/families/Merriweather.json"
	local fontSwap = {
		[Enum.Font.Gotham] = Font.new(serif, Enum.FontWeight.Regular),
		[Enum.Font.GothamMedium] = Font.new(serif, Enum.FontWeight.Regular),
		[Enum.Font.GothamBold] = Font.new(serif, Enum.FontWeight.Bold),
		[Enum.Font.GothamBlack] = Font.new(serif, Enum.FontWeight.Heavy),
	}
	local function swapFont(instance)
		if instance:IsA("TextLabel") or instance:IsA("TextButton") or instance:IsA("TextBox") then
			local replacement = fontSwap[instance.Font]
			if replacement then
				instance.FontFace = replacement
			end
		end
	end
	for _, descendant in ipairs(screenGui:GetDescendants()) do
		swapFont(descendant)
	end
	screenGui.DescendantAdded:Connect(function(descendant)
		task.defer(swapFont, descendant)
	end)
end

local root = Instance.new("Frame")
root.Name = "GameRoot"
root.Size = UDim2.fromScale(1, 1)
root.BackgroundColor3 = Color3.fromRGB(24, 18, 14) -- warm dark "tavern" backdrop
root.BorderSizePixel = 0
root.Visible = false -- hidden until the player presses Play on the menu
root.Parent = screenGui

-- ART (Nov 1 2026): the actual gameplay backdrop -- see
-- Client/ArtAssets.lua's gameplayBackground for the full story. Same
-- placeholder-safe pattern as Menu.lua's menuBackgroundArt: image stays
-- fully transparent-backed, root's own flat BackgroundColor3 above is
-- the fallback for as long as this is still "rbxassetid://0", and
-- ZIndex 0 guarantees it sits behind every other root-level child
-- (SidebarModule.sidebar is ZIndex 2, everything else defaults to ZIndex 1) no
-- matter what order they're created in.
local gameBackgroundArt = Instance.new("ImageLabel")
gameBackgroundArt.Name = "GameBackgroundArt"
gameBackgroundArt.Size = UDim2.fromScale(1, 1)
-- BUGFIX (reference-match pass, round 2): this ScreenGui never sets
-- ZIndexBehavior, so it uses Global layering -- and in Global mode a
-- ZIndex-0 child draws UNDER its ZIndex-1 parent's own fill. root's
-- opaque brown was painting right over this image (and over the hand
-- tray CardFace.lua hangs off it). Fix: root itself is now see-through,
-- and the flat fallback color lives on this ImageLabel's own background
-- instead (an ImageLabel draws its background first, image on top), so a
-- placeholder/failed image still shows the same flat brown as before.
gameBackgroundArt.BackgroundColor3 = Color3.fromRGB(24, 18, 14)
gameBackgroundArt.BackgroundTransparency = 0
gameBackgroundArt.BorderSizePixel = 0
gameBackgroundArt.ScaleType = Enum.ScaleType.Crop
gameBackgroundArt.Image = require(script.ArtAssets).gameplayBackground or "rbxassetid://0"
gameBackgroundArt.ZIndex = 0
-- Slight dim so the warm art reads as a backdrop and never fights the
-- cream UI text on top of it (the reference's room is fairly dark).
gameBackgroundArt.ImageColor3 = Color3.fromRGB(215, 205, 195)
gameBackgroundArt.Parent = root
-- Per-round scene art over the default backdrop (falls back to it while ids are missing).
do
	require(script.GameplayScene).init({
		root = root,
		gameBackgroundArt = gameBackgroundArt,
		playSfx = SoundModule.playSfx,
		soundId = SoundModule.SOUND_IDS.cardToggle, -- soft whoosh-like rub, played quietly
	})
end
root.BackgroundTransparency = 1
-- (Removed Nov 1 2026: a ContentProvider:PreloadAsync check used to swap
-- this to a blurry thumbnail on "Failure" -- but PreloadAsync reports
-- Failure even for images that load fine, so it was blanking good art.)

-- ----- Left SidebarModule.sidebar: round/blind info -----
-- Extracted into Client/Sidebar.lua (round/blind labels, Patron slot row,
-- score preview box). SidebarModule.SIDEBAR_WIDTH/labels/SidebarModule.patronSlots come back out since
-- render() and refreshScorePreview() below still drive them every frame.
local SidebarModule = require(script.Sidebar)({
	root = root,
	polishPanel = VisualHelpersModule.polishPanel,
	roundCorner = VisualHelpersModule.roundCorner,
	Patrons = Patrons,
})

-- ----- Help (?) and mute buttons, top-right corner -----

-- CORNER ICON SET (Oct 25 2026): one top-level local, same reasoning as
-- SidebarModule etc. just above -- read by makeCornerButton AND by every
-- corner-button call site below it (6 separate reads), so it can't be an
-- inline single-use require the way DeckWidget.lua's own ArtAssets read
-- further down is. Settings.lua's 2 icon buttons (How to Play,
-- Leaderboards) read ArtAssets.lua independently with their own
-- require(script.Parent.ArtAssets) instead of taking this as a dep --
-- same self-contained-module pattern Settings.lua already uses for
-- OverlayManager just above its own buttons.
local ArtAssetsModule = require(script.ArtAssets)

local function makeCornerButton(text, order, iconId)
	-- Corner buttons live in one right-aligned UIListLayout row, so a
	-- hidden or removed button closes up instead of leaving a gap. `order`
	-- is the LayoutOrder (1 = leftmost). Only buttons are parented to the
	-- row; all ornaments live inside each button.
	local row = root:FindFirstChild("CornerIconRow")
	if not row then
		row = Instance.new("Frame")
		row.Name = "CornerIconRow"
		row.AnchorPoint = Vector2.new(1, 0)
		row.Position = UDim2.new(1, -16, 0, 12)
		row.Size = UDim2.new(0, 0, 0, 54)
		row.AutomaticSize = Enum.AutomaticSize.X
		row.BackgroundTransparency = 1
		row.ZIndex = 5
		row.Parent = root
		local layout = Instance.new("UIListLayout")
		layout.FillDirection = Enum.FillDirection.Horizontal
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
		layout.VerticalAlignment = Enum.VerticalAlignment.Center
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Padding = UDim.new(0, 10)
		layout.Parent = row
	end
	local hasIcon = iconId and iconId ~= "rbxassetid://0"
	local button = Instance.new("TextButton")
	button.Size = UDim2.new(0, 54, 0, 54)
	button.LayoutOrder = order
	button.Font = Enum.Font.GothamBold
	button.TextSize = 24
	button.Text = hasIcon and "" or text
	button.BackgroundColor3 = Color3.fromRGB(38, 26, 16)
	button.TextColor3 = Color3.fromRGB(250, 240, 220)
	button.TextTransparency = 0
	button.TextStrokeTransparency = 1
	button.ZIndex = 5
	button.Parent = row
	VisualHelpersModule.polishButton(button, 27)
	-- Ring matched to the SidebarModule.sidebar frame (bronze outer line + the shared
	-- gold inner rim), thinner than before.
	local rim = button:FindFirstChildOfClass("UIStroke")
	if rim then
		rim.Color = Color3.fromRGB(168, 128, 66)
		rim.Thickness = 2
		rim.Transparency = 0
	end

	-- Optional icon image (a real id; rbxassetid://0 keeps the text glyph).
	-- Named "Icon" so VolumePanel can dim it for the muted look.
	if hasIcon then
		local icon = Instance.new("ImageLabel")
		icon.Name = "Icon"
		icon.Size = UDim2.new(0, 40, 0, 40)
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Position = UDim2.fromScale(0.5, 0.5)
		icon.BackgroundTransparency = 1
		icon.Image = iconId
		icon.ScaleType = Enum.ScaleType.Crop
		icon.ZIndex = 6
		icon.Parent = button
		-- Full-radius corner: clips the image to a circle inside the ring.
		local iconCorner = Instance.new("UICorner")
		iconCorner.CornerRadius = UDim.new(0.5, 0)
		iconCorner.Parent = icon
	end

	return button
end

local volumeButton = makeCornerButton(SoundModule.VOLUME_ICONS[SoundModule.volumeStepIndex], 5, ArtAssetsModule.cornerIconVolume)
-- CORNER ROW CLEANUP: no "?" (How to Play) or "🏆" (Leaderboards) corner
-- icons anymore -- both moved into the Settings panel (see Settings.lua),
-- and everything right of Volume shifted 50px to close the gap.
local journeyButton = makeCornerButton("🗺", 4, ArtAssetsModule.cornerIconJourney)
local handRefButton = makeCornerButton("📖", 3, ArtAssetsModule.cornerIconHandReference)
-- No corner button for the Deck Tracker anymore -- the blue deck widget
-- (bottom-right) is clickable and opens it directly instead (see
-- DeckWidgetModule.deckWidgetButton). Settings/Collection shifted left by 50px to close
-- the gap left behind.
local settingsButton = makeCornerButton("⚙", 2, ArtAssetsModule.cornerIconSettings)
local collectionButton = makeCornerButton("📔", 1, ArtAssetsModule.cornerIconCollection)
for piece, b in pairs({ btn_volume = volumeButton, btn_journey = journeyButton, btn_hand_ref = handRefButton, btn_settings = settingsButton, btn_collection = collectionButton }) do
	pcall(require(script.HudTheme).styleIcon, b, piece) -- ring, glow, disc tint and motif (or the painted kit button) follow the equipped Card Set
end

-- ----- Generic hover tooltip -----
-- Ahmed: "whenever you hover over a button any UI, it should give you the
-- name of what it does." One shared label, repositioned/retexted for
-- whichever button is currently hovered, instead of a separate Instance
-- per button.
local addTooltip
do

-- The one shared tooltip (single outer border, padding, max width with wrapping): Client/Tooltip.lua.
-- align "left": the tooltip's right edge lines up with the button's right edge (buttons near the right
-- screen edge). Text can be a string or a zero-arg function evaluated on each hover.
addTooltip = require(script.Tooltip).new(screenGui).attach

addTooltip(volumeButton, "Volume", "left")
addTooltip(journeyButton, "Journey", "left")
addTooltip(handRefButton, "Poker Hands reference", "left")
addTooltip(settingsButton, "Settings", "left")
addTooltip(collectionButton, "Collection", "left")

end -- Generic hover tooltip

-- Sidebar Patron slot tooltips: slot i shows whichever Patron currently
-- sits in seat i of YOUR table (state.ownedPatrons[i]), not a fixed
-- roster entry -- that changes as you buy/sell, so this has to be a
-- function (not a plain string) re-evaluated fresh every hover, via
-- latestState, rather than bound once at construction time.
for i = 1, SidebarModule.MAX_SIDEBAR_PATRON_SLOTS do
	local slot = SidebarModule.patronSlots[i]
	if slot then
		addTooltip(slot.frame, function()
			local owned = latestState and latestState.ownedPatrons and latestState.ownedPatrons[i]
			if owned then
				return string.format("%s\n%s", owned.name, owned.description)
			end
			return require(ReplicatedStorage.Shared.Engine.EmptyStates).hint("seat")
		end)
	end
end

-- ===== Message banner (hand result / round result) =====
-- Extracted into Client/MessageBanner.lua. showWarning is passed as a dep
-- into Shop.lua below, so it comes back out of the require()
-- call. (The old persistent Boss Round banner is gone -- see
-- MessageBanner.lua's header.)
local MessageBannerModule = require(script.MessageBanner)({
	SIDEBAR_WIDTH = SidebarModule.SIDEBAR_WIDTH,
	root = root,
	polishPanel = VisualHelpersModule.polishPanel,
	tweenTo = VisualHelpersModule.tweenTo,
})
local showWarning = MessageBannerModule.showWarning

-- ----- Hand area -----

-- 110px reserved on the right so a full hand of cards never fans out under
-- the deck-remaining widget added further down (bottom-right, ~94px wide
-- including its margin).
local handFrame = Instance.new("Frame")
handFrame.Name = "HandFrame"
-- REFERENCE-MATCH PASS: taller (cards are bigger now, see
-- Client/CardFace.lua) and lifted so there's breathing room above the
-- action buttons; 150px reserved on the right for the bigger deck widget.
handFrame.Size = UDim2.new(1, -(SidebarModule.SIDEBAR_WIDTH + 40 + 150), 0, 176)
handFrame.Position = UDim2.new(0, SidebarModule.SIDEBAR_WIDTH + 20, 1, -272)
handFrame.BackgroundTransparency = 1
handFrame.Parent = root

local handLayout = Instance.new("UIListLayout")
handLayout.FillDirection = Enum.FillDirection.Horizontal
handLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
handLayout.VerticalAlignment = Enum.VerticalAlignment.Center
handLayout.Padding = UDim.new(0, 6)
-- Explicit: UIListLayout's default SortOrder can be Name, which ignores
-- the slots' LayoutOrder (same bug class as Shop.lua's Phase 1c fix).
handLayout.SortOrder = Enum.SortOrder.LayoutOrder
handLayout.Parent = handFrame

-- ----- Action buttons -----

local actionFrame = Instance.new("Frame")
actionFrame.Name = "Actions"
actionFrame.Size = UDim2.new(1, -(SidebarModule.SIDEBAR_WIDTH + 40 + 150), 0, 54)
actionFrame.Position = UDim2.new(0, SidebarModule.SIDEBAR_WIDTH + 20, 1, -80)
actionFrame.BackgroundTransparency = 1
actionFrame.Parent = root

local actionLayout = Instance.new("UIListLayout")
actionLayout.FillDirection = Enum.FillDirection.Horizontal
actionLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
actionLayout.Padding = UDim.new(0, 20)
-- Explicit LayoutOrder sorting: with the default (Name) sort, the Sort
-- group ("Frame") and its "Sort:" caption ("TextLabel" sorts after
-- "TextButton") landed in accidental positions -- that's why the caption
-- showed up AFTER the Rank/Suit buttons. Now: [Sort: Rank Suit] [Play
-- Hand] [Discard], left to right.
actionLayout.SortOrder = Enum.SortOrder.LayoutOrder
actionLayout.Parent = actionFrame

local function makeActionButton(text, role)
	local button = Instance.new("TextButton")
	button.Size = UDim2.new(0, 200, 1, 0)
	button.Font = Enum.Font.GothamBold
	button.TextSize = 20
	button.Text = text
	button.BackgroundColor3 = Color3.fromRGB(56, 37, 20)
	button.TextColor3 = Color3.fromRGB(250, 240, 220)
	button.Parent = actionFrame
	VisualHelpersModule.polishButton(button, 8)
	-- Code-drawn themed base (Client/HudTheme.lua): solid rounded fill, two rings in the Card Set accent, Color-only
	-- gradient, hover and pressed states; text always sits on the solid base. The painted plate is no longer used here.
	button.ZIndex = 2
	require(script.HudTheme).styleAction(button, role)
	return button
end

local playButton = makeActionButton("Play Hand", "play")
playButton.LayoutOrder = 1
-- (no tooltip: the label already says Play Hand)

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
local Shop -- forward declaration: the sort handlers below use it; assigned where Shop.lua is required
do

local sortFrame = Instance.new("Frame")
sortFrame.Size = UDim2.new(0, 214, 1, 0)
sortFrame.BackgroundTransparency = 1
sortFrame.LayoutOrder = 0
sortFrame.Parent = actionFrame

local sortFrameLayout = Instance.new("UIListLayout")
sortFrameLayout.FillDirection = Enum.FillDirection.Horizontal
sortFrameLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
sortFrameLayout.VerticalAlignment = Enum.VerticalAlignment.Center
sortFrameLayout.Padding = UDim.new(0, 8)
sortFrameLayout.SortOrder = Enum.SortOrder.LayoutOrder
sortFrameLayout.Parent = sortFrame

-- User feedback: "make it more obvious that it's sorting buttons" -- a
-- small "Sort:" caption to the left of the two buttons, so they don't read
-- as two random unlabeled buttons.
local sortCaptionLabel = Instance.new("TextLabel")
sortCaptionLabel.Size = UDim2.new(0, 46, 1, 0)
sortCaptionLabel.BackgroundTransparency = 1
sortCaptionLabel.Font = Enum.Font.Gotham
sortCaptionLabel.TextSize = 17
sortCaptionLabel.TextColor3 = Color3.fromRGB(220, 210, 190)
sortCaptionLabel.Text = "Sort:"
sortCaptionLabel.LayoutOrder = 1
sortCaptionLabel.Parent = sortFrame

-- One segmented Rank | Suit toggle in the Card Set colours (Client/SortToggle.lua) replaces the two old buttons.
local sortToggle
local function refreshSortButtonHighlight()
	if sortToggle then sortToggle.setMode(handSortMode) end
end

local function applyHandSortMode(mode)
	handSortMode = mode
	refreshSortButtonHighlight()
	if refreshHandSort then
		refreshHandSort()
	end
end

sortToggle = require(script.SortToggle).build(sortFrame, function(mode)
	if not Shop.tutorial.allows("sort") then return end
	SoundModule.playClickSfx(0.35)
	applyHandSortMode(mode)
end)

end -- do (Sort Hand buttons)

local discardButton = makeActionButton("Discard", "discard")
discardButton.LayoutOrder = 3
-- (no tooltip: the label already says Discard)

-- ===== Deck-remaining widget, bottom-right =====
-- Extracted into Client/DeckWidget.lua. DeckWidgetModule.deckCountLabel is driven every
-- render() call, and DeckWidgetModule.deckWidgetButton is passed as a dep into
-- DeckTracker.lua below, so both come back out of the require() call.
local DeckWidgetModule = require(script.DeckWidget)({
	root = root,
	polishPanel = VisualHelpersModule.polishPanel,
	addSoftShadow = VisualHelpersModule.addSoftShadow,
	addTooltip = addTooltip,
	roundCorner = VisualHelpersModule.roundCorner,
	-- CARD ART: DeckWidget.lua reads cardBackTemplate off this. Inline
	-- require(), not a new top-level local, same reasoning as everywhere
	-- else that reads ArtAssets.lua in this file.
	ArtAssetsModule = require(script.ArtAssets),
})

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

-- ===== Particle burst (SCORING JUICE) =====
-- Extracted into Client/ParticleBurst.lua. Only ScorePopup.lua uses it right
-- now, so nothing needs to come back out of the require() call besides the
-- module table itself, passed straight through as a dep below.
local ParticleBurstModule = require(script.ParticleBurst)({
	screenGui = screenGui,
	tweenTo = VisualHelpersModule.tweenTo,
})

-- Boss fight presence (portrait, HP bar, hit reactions); visual only, driven by render().
do
	-- Live characters (prototype): a click-through ViewportFrame under the boss plaque and the hand.
	local okStage, stageErr = pcall(function()
		require(script.CharacterStage).init({ root = root, SIDEBAR_WIDTH = SidebarModule.SIDEBAR_WIDTH }).prewarm() -- build the avatar at menu time
	end)
	if not okStage then
		warn("[Client] CharacterStage failed to build: " .. tostring(stageErr))
	end
	pcall(function() require(script.AccessibilityFX).init(screenGui) end) -- Larger Text (Settings), no new locals here
	pcall(function() require(script.FirstTimeHints).init(screenGui) end) -- first time hint bubbles
	pcall(function() require(script.SpectatePanel).init({ screenGui = screenGui, particleBurst = ParticleBurstModule.burst }) end) -- watch a friend (same server)
	require(script.BossFight).init({
		root = root,
		SIDEBAR_WIDTH = SidebarModule.SIDEBAR_WIDTH,
		burst = ParticleBurstModule.burst,
		screenShake = VisualHelpersModule.screenShake,
		playThump = function() SoundModule.playPitched(SoundModule.payoutThudSound, 0.4, 0.7) end,
		playFanfare = function() SoundModule.playCue("win") end,
		music = SoundModule.backgroundMusic,
	})
	require(script.EndlessChips).init({ root = root, addTooltip = addTooltip }) -- Crowd Rule chips and banner (Endless)
	require(script.BlessingChip).init({ root = root, addTooltip = addTooltip }) -- blessing and curse chip under the sidebar
	require(script.SidebarTheme).init(root) -- left HUD panel follows the Card Set
end

-- ===== Score popup: chips x mult animation on Play Hand =====
-- Extracted into Client/ScorePopup.lua. ScorePopupModule.showScorePopup is called from
-- playButton's click handler elsewhere in this file, so it comes back out
-- of the require() call. SCORING JUICE: now takes the escalating-pitch SFX/
-- screen shake/particle burst deps too, since it plays back preview.breakdown
-- (see Scoring.lua) as a sequenced chips/mult/xmult reveal instead of just
-- flashing the final numbers once.
local ScorePopupModule = require(script.ScorePopup)({
	root = root,
	tweenTo = VisualHelpersModule.tweenTo,
	screenShake = VisualHelpersModule.screenShake,
	particleBurst = ParticleBurstModule.burst,
	playPitched = SoundModule.playPitched,
	chipTickSound = SoundModule.chipTickSound,
	multTickSound = SoundModule.multTickSound,
	xmultTickSound = SoundModule.xmultTickSound,
	payoutThudSound = SoundModule.payoutThudSound,
	-- SCORING JUICE, full choreography pass: played-card ghosts drop off
	-- toward this (bottom-right, see Client/DeckWidget.lua) at the end of
	-- the reveal, mirroring how a fresh hand deals IN from the same spot
	-- (see rebuildHand's LAYOUT FEATURE 8) -- symmetric "cards live here"
	-- landmark instead of just flying off an arbitrary screen edge.
	deckWidgetButton = DeckWidgetModule.deckWidgetButton,
	-- QoL Game Pass (Fast Forward, Phase 9): reads latestState fresh every
	-- call (a live getter, not a one-time snapshot) -- ownership can flip
	-- true mid-session the moment a purchase resolves (see
	-- Server/init.server.lua's PromptGamePassPurchaseFinished handler).
	-- Inlined here rather than a separate named top-level helper -- this
	-- is its only use site, and this file sits right at Lua's
	-- 200-local-per-chunk ceiling.
	hasFastForwardPass = function()
		return latestState ~= nil and latestState.ownedGamePassIds ~= nil and table.find(latestState.ownedGamePassIds, "fast_forward") ~= nil
	end,
})

-- ===== PHASE A (Spectacle pass, see claude/mind-blowing-plan.md) =====
-- Boss Intro (a one-shot "arrival" beat the first time a new Boss Round
-- shows up) + Run Recap (tracks the biggest hand played so far this run,
-- for GameOver's recap) -- merged into ONE module/require on purpose, see
-- PhaseA.lua's header: this file is already right at Lua's
-- 200-local-per-chunk ceiling, and 2 separate top-level locals for these
-- tipped it over (confirmed) where 1 doesn't.
local PhaseAModule = require(script.PhaseA)({
	root = root,
	tweenTo = VisualHelpersModule.tweenTo,
	screenShake = VisualHelpersModule.screenShake,
	playPitched = SoundModule.playPitched,
	payoutThudSound = SoundModule.payoutThudSound,
})

-- ===== PHASE B (Alive & Social pass, see claude/mind-blowing-plan.md) =====
-- Live Leaderboard Ticker + Friend Presence -- both purely ambient corner
-- panels, driven entirely by their own RemoteEvents (server broadcasts/
-- pushes, this file never requests anything) -- merged into ONE module/
-- require for the same 200-local-per-chunk reason as PhaseA above. Its
-- return value is intentionally unused ({} -- see PhaseB.lua's header);
-- requiring it is all that's needed to stand both panels up.
require(script.PhaseB)({
	root = root,
	remotes = remotes,
})

-- ===== Confirm dialog (generic, reusable) =====
-- Extracted into Client/ConfirmDialog.lua. ConfirmDialogModule.showConfirmDialog is passed as a
-- dep into Shop.lua below, so it comes back out of the require() call.
local ConfirmDialogModule = require(script.ConfirmDialog)({
	screenGui = screenGui,
	polishPanel = VisualHelpersModule.polishPanel,
	polishButton = VisualHelpersModule.polishButton,
	addSoftShadow = VisualHelpersModule.addSoftShadow,
	playClickSfx = SoundModule.playClickSfx,
	popIn = VisualHelpersModule.popIn,
	popOut = VisualHelpersModule.popOut,
	addButtonHoverScale = VisualHelpersModule.addButtonHoverScale,
})

-- ----- Shop overlay -----
-- Extracted into Client/Shop.lua (see that file for the deps list and the
-- full breakdown of what it builds) -- this is the first piece pulled out
-- as the client script gets split into smaller, per-feature files. It's a
-- ModuleScript, so it can't see this script's locals directly; everything
-- it needs is passed in explicitly via the deps table below. It hands back
-- Shop.shopFrame/Shop.nextRoundButton (still needed here for theme tweening and for
-- Shop.nextRoundButton's click handler, both wired further down) and the two
-- rebuild functions (called from render() whenever the shop's contents
-- need to refresh).
Shop = require(script.Shop)({
	root = root,
	SIDEBAR_WIDTH = SidebarModule.SIDEBAR_WIDTH,
	polishPanel = VisualHelpersModule.polishPanel,
	shopBackgroundImage = require(script.ArtAssets).shopBackground,
	polishButton = VisualHelpersModule.polishButton,
	roundCorner = VisualHelpersModule.roundCorner,
	showWarning = showWarning,
	showConfirmDialog = ConfirmDialogModule.showConfirmDialog,
	playClickSfx = SoundModule.playClickSfx,
	playSfx = SoundModule.playSfx,
	SOUND_IDS = SoundModule.SOUND_IDS,
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
	addButtonHoverScale = VisualHelpersModule.addButtonHoverScale,
	revealStagger = VisualHelpersModule.revealStagger,
	popScale = VisualHelpersModule.popScale,
	particleBurst = ParticleBurstModule.burst,
	addTooltip = addTooltip, -- art cards show their rules text in the shared hover tooltip
	-- INTERACTIVE TUTORIAL: see this file's own "INTERACTIVE TUTORIAL"
	-- comment further down (just above Menu.lua's require) for why TutorialWalkthrough.lua is required FROM INSIDE
	-- Shop.lua instead of getting its own top-level local here.
	tweenTo = VisualHelpersModule.tweenTo,
	handFrame = handFrame,
	playButton = playButton,
	discardButton = discardButton,
	sidebarScoreBox = SidebarModule.scoreBox,
	sidebarTipsBox = SidebarModule.tipsBox,
	sidebarHandsDiscardsBox = SidebarModule.handsDiscardsBox,
	sidebarPatronsBox = SidebarModule.patronsInset,
	MarkTutorialSeenRemote = remotes:WaitForChild("MarkTutorialSeen"),
})
local closeRecipeTargetPanel = Shop.closeTargetPanel

-- ===== Game over overlay + Menu screen =====
-- Extracted into Client/GameOver.lua and Client/Menu.lua. and
-- render() further down still need GameOverPanel.gameOverFrame/GameOverPanel.playAgainButton, and the
-- menu buttons are needed both by the "Menu -> game transition" glue right
-- below and as deps into HowToPlay.lua/Journey.lua/RunSetup.lua (which wire
-- their own click handlers onto the menu buttons), so everything comes
-- back out of both require() calls.
local GameOverPanel = require(script.GameOver)({
	root = root,
	polishPanel = VisualHelpersModule.polishPanel,
	polishButton = VisualHelpersModule.polishButton,
	gameOverWinBackgroundImage = require(script.ArtAssets).gameOverWinBackground,
	addSoftShadow = VisualHelpersModule.addSoftShadow,
	tweenTo = VisualHelpersModule.tweenTo,
	-- Win/loss sound (Phase 14 fix): this panel played nothing before.
	playSfx = SoundModule.playSfx,
	SOUND_IDS = SoundModule.SOUND_IDS,
})

-- INTERACTIVE TUTORIAL (requested directly by Ahmed -- see
-- TutorialWalkthrough.lua's own header for the full brief). No longer
-- auto-starts for new players -- the ONLY way in is Menu.lua's "Tutorial"
-- button (wired next to MenuScreen.menuPlayButton's click further down), which
-- hides the menu and starts it straight away. The old static Tutorial.lua
-- modal is no longer required anywhere.
--
-- Built and required FROM INSIDE Shop.lua, not as its own top-level local
-- here (confirmed the hard way, same as PhaseA.lua's own header describes:
-- this chunk is already right up against Lua's 200-local-per-chunk
-- ceiling, and this feature's targets span handFrame/playButton/
-- discardButton (all available by this point) AND Shop.nextRoundButton/
-- shopBuyListFrame, which don't exist until Shop.lua's own require() call
-- further up finishes -- Shop.lua already HAS those two as its own plain
-- local variables, so merging there (purely for budget reasons, not a
-- real coupling -- see its own "===== TUTORIAL WALKTHROUGH" section) means
-- Shop.nextRoundButton/shopBuyListFrame never have to be threaded back out
-- through a deps table at all. Exposed as Shop.tutorial.<method>, called
-- from onCardClicked, the Play/Discard/Next Round click handlers, and
-- render() -- all further down, which costs nothing against THIS chunk's
-- own ceiling (that 200 limit is per-function, not per-file; only locals
-- declared directly in this top-level chunk are the scarce resource).

-- WEEKLY CHALLENGE + SEED CODES (Phase 16): SeedRunDialog.lua is built
-- INLINE, right inside Menu.lua's own deps table below, deliberately NOT
-- captured as its own top-level local (init.client.lua is already right
-- up against Lua's 200-local-per-chunk ceiling, same constraint the
-- Daily Challenge button comment above documents) -- only its
-- `.showSeedRunDialog` field is threaded through, as `openSeedRunDialog`,
-- for Menu.lua's "Seed Run..." button to call. Same reasoning for
-- requiring Shared/Engine/SeededRng inline right there too, rather than
-- as its own local -- nothing else client-side needs it.
local MenuScreen = require(script.Menu)({
	screenGui = screenGui,
	polishButton = VisualHelpersModule.polishButton,
	revealStagger = VisualHelpersModule.revealStagger,
	addButtonHoverScale = VisualHelpersModule.addButtonHoverScale,
	menuBackgroundImage = require(script.ArtAssets).menuBackground,
	StartDailyChallengeRemote = remotes:WaitForChild("StartDailyChallenge"),
	playClickSfx = SoundModule.playClickSfx,
	StartWeeklyChallengeRemote = remotes:WaitForChild("StartWeeklyChallenge"),
	openSeedRunDialog = require(script.SeedRunDialog)({
		screenGui = screenGui,
		polishPanel = VisualHelpersModule.polishPanel,
		polishButton = VisualHelpersModule.polishButton,
		addSoftShadow = VisualHelpersModule.addSoftShadow,
		playClickSfx = SoundModule.playClickSfx,
		popIn = VisualHelpersModule.popIn,
		popOut = VisualHelpersModule.popOut,
		addButtonHoverScale = VisualHelpersModule.addButtonHoverScale,
		StartSeedRunRemote = remotes:WaitForChild("StartSeedRun"),
		SeededRng = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("SeededRng")),
	}).showSeedRunDialog,
})

do -- End-of-run summary and badge (Client/RunSummaryUI.lua), shown over Game Over from render()
	local ok, err = pcall(function()
		require(script.RunSummaryUI).init(screenGui, {
			playClick = SoundModule.playClickSfx,
			restart = function() remotes:WaitForChild("RestartRun"):FireServer() end,
			saveBadge = function() remotes:WaitForChild("SaveBadge"):FireServer() end,
			makeSeed = function() return remotes:WaitForChild("MakeChallengeSeed"):InvokeServer() end, -- Challenge a friend
		})
	end)
	if not ok then warn("[Client] RunSummaryUI failed: " .. tostring(err)) end
end
do -- Start-of-run draft and between-Nights event cards (Client/ChoicePanel.lua); fed from render()
	local ok, err = pcall(function()
		require(script.ChoicePanel).init({
			screenGui = screenGui, menuFrame = MenuScreen.menuFrame, polishButton = VisualHelpersModule.polishButton, roundCorner = VisualHelpersModule.roundCorner,
			playClickSfx = SoundModule.playClickSfx, choiceRemote = remotes:WaitForChild("Choice"), root = root, -- root: Back to menu
		})
	end)
	if not ok then warn("[Client] ChoicePanel failed: " .. tostring(err)) end
end
do -- Daily Quests panel (Client/QuestsPanel.lua), opened from the Quests tile on the main menu
	local ok, err = pcall(function()
		require(script.QuestsPanel).init({
			screenGui = screenGui, openButton = MenuScreen.menuQuestsButton, polishPanel = VisualHelpersModule.polishPanel, polishButton = VisualHelpersModule.polishButton,
			roundCorner = VisualHelpersModule.roundCorner, playClickSfx = SoundModule.playClickSfx, popIn = VisualHelpersModule.popIn, popOut = VisualHelpersModule.popOut,
			getLatestState = function() return latestState end,
		})
	end)
	if not ok then warn("[Client] QuestsPanel failed: " .. tostring(err)) end
end
do -- Daily Rewards ladder (Client/DailyRewardsPanel.lua), opened from the Menu tile and from Settings
	local ok, err = pcall(function()
		require(script.DailyRewardsPanel).init({
			screenGui = screenGui, polishPanel = VisualHelpersModule.polishPanel, polishButton = VisualHelpersModule.polishButton,
			roundCorner = VisualHelpersModule.roundCorner, playClickSfx = SoundModule.playClickSfx, popIn = VisualHelpersModule.popIn, popOut = VisualHelpersModule.popOut,
			getLatestState = function() return latestState end,
		})
	end)
	if not ok then warn("[Client] DailyRewardsPanel failed: " .. tostring(err)) end
end
do -- Tavern Season panel (Client/SeasonPanel.lua): the 30 day reward ladder, opened from the Season tile on the main menu
	local ok, err = pcall(function()
		require(script.SeasonPanel).init({
			screenGui = screenGui, openButton = MenuScreen.menuSeasonButton, polishPanel = VisualHelpersModule.polishPanel, polishButton = VisualHelpersModule.polishButton,
			roundCorner = VisualHelpersModule.roundCorner, addSoftShadow = VisualHelpersModule.addSoftShadow, playClickSfx = SoundModule.playClickSfx, addTooltip = addTooltip,
			popIn = VisualHelpersModule.popIn, popOut = VisualHelpersModule.popOut, addButtonHoverScale = VisualHelpersModule.addButtonHoverScale,
			getLatestState = function() return latestState end, StateUpdatedRemote = StateUpdatedRemote,
		})
	end)
	if not ok then warn("[Client] SeasonPanel failed: " .. tostring(err)) end
end
do -- Tavern News panel (Client/NewsPanel.lua): the banner on the menu opens it
	local ok, err = pcall(function()
		require(script.NewsPanel).init({
			screenGui = screenGui, polishPanel = VisualHelpersModule.polishPanel, polishButton = VisualHelpersModule.polishButton, roundCorner = VisualHelpersModule.roundCorner,
			playClickSfx = SoundModule.playClickSfx, popIn = VisualHelpersModule.popIn, popOut = VisualHelpersModule.popOut, claimRemote = remotes:WaitForChild("ClaimLiveEvent"),
		})
	end)
	if not ok then warn("[Client] NewsPanel failed: " .. tostring(err)) end
end
do -- The Tavern Store (Client/StorePanel.lua): opened from the menu tile and once after the second run
	local ok, err = pcall(function()
		require(script.StorePanel).init({
			screenGui = screenGui, openButton = MenuScreen.menuStoreButton, polishPanel = VisualHelpersModule.polishPanel, polishButton = VisualHelpersModule.polishButton,
			roundCorner = VisualHelpersModule.roundCorner, playClickSfx = SoundModule.playClickSfx, popIn = VisualHelpersModule.popIn, popOut = VisualHelpersModule.popOut,
			purchaseRemote = remotes:WaitForChild("StorePurchase"), getLatestState = function() return latestState end,
		})
	end)
	if not ok then warn("[Client] StorePanel failed: " .. tostring(err)) end
end
do -- Combo counter (Client/ComboCounter.lua), driven by the score popup
	local ok, err = pcall(function() require(script.ComboCounter).init(screenGui) end)
	if not ok then warn("[Client] ComboCounter failed: " .. tostring(err)) end
end
do -- Unlock toast (Client/UnlockToast.lua); fed from render()
	local ok, err = pcall(function() require(script.UnlockToast).init(screenGui) end)
	if not ok then warn("[Client] UnlockToast failed: " .. tostring(err)) end
end
do -- Daily login streak popup and Next unlock strip (Client/LoginStreakUI.lua); fed from render()
	local ok, err = pcall(function()
		require(script.LoginStreakUI).init(MenuScreen.menuFrame, remotes:WaitForChild("ClaimLoginReward"), SoundModule.playClickSfx)
	end)
	if not ok then warn("[Client] LoginStreakUI failed: " .. tostring(err)) end
end

-- Warm the image cache for all content art (non-blocking) so Collection tiles
-- and other art find their images already loaded.
task.spawn(function()
	local ok, err = pcall(function()
		require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("ContentArt")).preloadAll()
	end)
	if not ok then warn("[Client] art preload failed: " .. tostring(err)) end
end)

-- Menu buttons connect BEFORE any optional panel is built, so a broken
-- panel can never leave the menu dead.
MenuScreen.menuPlayButton.MouseButton1Click:Connect(function()
	SoundModule.playClickSfx()
	require(script.TutorialBus).fire("menu_play")
	MenuScreen.menuFrame.Visible = false
	root.Visible = true
	if SoundModule.backgroundMusic.SoundId ~= "rbxassetid://0" and SoundModule.backgroundMusic.Volume > 0 then
		SoundModule.backgroundMusic:Play()
	end
end)

MenuScreen.menuTutorialButton.MouseButton1Click:Connect(function()
	SoundModule.playClickSfx()
	MenuScreen.menuFrame.Visible = false
	root.Visible = true
	if SoundModule.backgroundMusic.SoundId ~= "rbxassetid://0" and SoundModule.backgroundMusic.Volume > 0 then
		SoundModule.backgroundMusic:Play()
	end
	Shop.tutorial.replay()
end)

-- ===== Settings overlay =====
-- Extracted into Client/Settings.lua. Main Menu / Close, plus How to Play
-- and Leaderboards (CORNER ROW CLEANUP: those used to be their own "?" /
-- "🏆" corner icons). Built here, before HowToPlay.lua/DailyLeaderboard.lua,
-- because those two wire their "open" onto these buttons. Captured via a
-- do-block (no SettingsModule local) -- this chunk is right at Lua's
-- 200-local ceiling.
local settingsHowToPlayButton, settingsLeaderboardButton, SettingsOverlay
do
	local SettingsModule = require(script.Settings)({
		screenGui = screenGui,
		polishPanel = VisualHelpersModule.polishPanel,
		polishButton = VisualHelpersModule.polishButton,
		addSoftShadow = VisualHelpersModule.addSoftShadow,
		playClickSfx = SoundModule.playClickSfx,
		settingsButton = settingsButton,
		menuSettingsButton = MenuScreen.menuSettingsButton,
		popIn = VisualHelpersModule.popIn,
		popOut = VisualHelpersModule.popOut,
		addButtonHoverScale = VisualHelpersModule.addButtonHoverScale,
		-- BUGFIX (Oct 29 2026): Settings.lua's 2 icon badges need
		-- VisualHelpersModule.roundCorner to clip them into circles (see that file's own
		-- comment) -- deps, not a second require(VisualHelpers) in
		-- there, since VisualHelpers.lua's require() returns a FACTORY
		-- FUNCTION (return function(deps) ... end), not the helpers
		-- table directly -- that's only resolved to the real table HERE,
		-- by actually calling it with deps (see VisualHelpersModule just
		-- above). Settings.lua's own require(script.Parent.VisualHelpers)
		-- skipped that call and indexed .roundCorner straight off the
		-- function, which threw "attempt to index a function value" and
		-- aborted this whole script before it reached MenuScreen.menuPlayButton's
		-- own click wiring further down -- why Play stopped responding.
		roundCorner = VisualHelpersModule.roundCorner,
		-- Main Menu button (requested fix): the only place in the whole game
		-- that lets a player back out of an in-progress run to the menu.
		menuFrame = MenuScreen.menuFrame,
		root = root,
	})
	settingsHowToPlayButton = SettingsModule.settingsHowToPlayButton
	settingsLeaderboardButton = SettingsModule.settingsLeaderboardButton
	SettingsOverlay = SettingsModule
end

-- ===== How to Play overlay (reachable from menu or in-game) =====
-- Extracted into Client/HowToPlay.lua -- fully self-contained (both buttons
-- that open it are wired from inside the module), so nothing needs to come
-- back out of the require() call.
xpcall(function()
require(script.HowToPlay)({
	screenGui = screenGui,
	polishPanel = VisualHelpersModule.polishPanel,
	polishButton = VisualHelpersModule.polishButton,
	roundCorner = VisualHelpersModule.roundCorner,
	addSoftShadow = VisualHelpersModule.addSoftShadow,
	playClickSfx = SoundModule.playClickSfx,
	RED_SUITS = RED_SUITS,
	RANK_NAMES = RANK_NAMES,
	SUIT_SYMBOLS = SUIT_SYMBOLS,
	HandEvaluator = HandEvaluator,
	Scoring = Scoring,
	menuHowToPlayButton = MenuScreen.menuHowToPlayButton,
	helpButton = settingsHowToPlayButton,
	popIn = VisualHelpersModule.popIn,
	popOut = VisualHelpersModule.popOut,
	addButtonHoverScale = VisualHelpersModule.addButtonHoverScale,
	replayTutorial = function()
		MenuScreen.menuFrame.Visible = false
		root.Visible = true
		Shop.tutorial.replay()
	end,
})
end, function(e)
	warn("[Client] HowToPlay panel failed to build: " .. tostring(e))
end)

-- ===== Poker Hands reference overlay =====
-- Extracted into Client/PokerHandsReference.lua. Fully self-contained (only
-- opened from its own corner button), so nothing needs to come back out of
-- the require() call.
xpcall(function()
require(script.PokerHandsReference)({
	screenGui = screenGui,
	polishPanel = VisualHelpersModule.polishPanel,
	polishButton = VisualHelpersModule.polishButton,
	addSoftShadow = VisualHelpersModule.addSoftShadow,
	playClickSfx = SoundModule.playClickSfx,
	handRefButton = handRefButton,
	HandEvaluator = HandEvaluator,
	Scoring = Scoring,
	getLatestState = function()
		return latestState
	end,
	popIn = VisualHelpersModule.popIn,
	popOut = VisualHelpersModule.popOut,
	addButtonHoverScale = VisualHelpersModule.addButtonHoverScale,
})
end, function(e)
	warn("[Client] PokerHandsReference panel failed to build: " .. tostring(e))
end)

-- ===== Deck Tracker overlay =====
-- Extracted into Client/DeckTracker.lua. Fully self-contained (only opened
-- from DeckWidgetModule.deckWidgetButton, which is passed in as a dep), so nothing needs to
-- come back out of the require() call.
xpcall(function()
require(script.DeckTracker)({
	screenGui = screenGui,
	polishPanel = VisualHelpersModule.polishPanel,
	polishButton = VisualHelpersModule.polishButton,
	roundCorner = VisualHelpersModule.roundCorner,
	addSoftShadow = VisualHelpersModule.addSoftShadow,
	playClickSfx = SoundModule.playClickSfx,
	deckWidgetButton = DeckWidgetModule.deckWidgetButton,
	Deck = Deck,
	RANK_NAMES = RANK_NAMES,
	SUIT_SYMBOLS = SUIT_SYMBOLS,
	SUIT_DISPLAY_ORDER = SUIT_DISPLAY_ORDER,
	RED_SUITS = RED_SUITS,
	getLatestState = function()
		return latestState
	end,
	popIn = VisualHelpersModule.popIn,
	popOut = VisualHelpersModule.popOut,
	addButtonHoverScale = VisualHelpersModule.addButtonHoverScale,
})
end, function(e)
	warn("[Client] DeckTracker panel failed to build: " .. tostring(e))
end)

-- ===== Volume popup =====
-- Client/VolumePanel.lua: Music slider, SFX slider, Mute. Nothing comes
-- back out of it that the hub needs, so no local.
xpcall(function()
require(script.VolumePanel)({
	screenGui = screenGui,
	polishPanel = VisualHelpersModule.polishPanel,
	polishButton = VisualHelpersModule.polishButton,
	addSoftShadow = VisualHelpersModule.addSoftShadow,
	playClickSfx = SoundModule.playClickSfx,
	volumeButton = volumeButton,
	isMusicUnavailable = SoundModule.isMusicUnavailable,
	onMusicAvailability = SoundModule.onMusicAvailability,
	makeSliderRow = VisualHelpersModule.makeSliderRow,
	VOLUME_ICONS = SoundModule.VOLUME_ICONS,
	popIn = VisualHelpersModule.popIn,
	popOut = VisualHelpersModule.popOut,
	addButtonHoverScale = VisualHelpersModule.addButtonHoverScale,
})
end, function(e)
	warn("[Client] VolumePanel panel failed to build: " .. tostring(e))
end)

-- ===== Run Setup overlay =====
-- Extracted into Client/RunSetup.lua. Fully self-contained (only opened
-- from the menu's "New Run..." button), so nothing needs to come back out
-- of the require() call.
xpcall(function()
require(script.RunSetup)({
	screenGui = screenGui,
	root = root,
	menuFrame = MenuScreen.menuFrame,
	polishPanel = VisualHelpersModule.polishPanel,
	polishButton = VisualHelpersModule.polishButton,
	roundCorner = VisualHelpersModule.roundCorner,
	addSoftShadow = VisualHelpersModule.addSoftShadow,
	playClickSfx = SoundModule.playClickSfx,
	playSfx = SoundModule.playSfx,
	SOUND_IDS = SoundModule.SOUND_IDS,
	DeckVariants = DeckVariants,
	DifficultyTiers = DifficultyTiers,
	getLatestState = function() return latestState end, -- Stakes: highestStakeUnlocked
	StartRunRemote = StartRunRemote,
	backgroundMusic = SoundModule.backgroundMusic,
	menuNewRunButton = MenuScreen.menuNewRunButton,
	popIn = VisualHelpersModule.popIn,
	popOut = VisualHelpersModule.popOut,
	addButtonHoverScale = VisualHelpersModule.addButtonHoverScale,
	revealStagger = VisualHelpersModule.revealStagger,
	-- PHASE A (Spectacle pass): the OTHER "Biggest Hand" reset path --
	-- see RunRecap.lua's own header for why this needs 2 call sites, not
	-- just the gameover->playing transition render() already covers.
	onBeginRun = function()
		PhaseAModule.resetRun()
		require(script.GameplayScene).get().reset()
	end,
})
end, function(e)
	warn("[Client] RunSetup panel failed to build: " .. tostring(e))
end)

-- ===== Menu -> game transition, volume cycling =====

-- volumeButton's click used to cycle loud/quiet/mute right here -- it now
-- opens VolumePanel.lua's real slider panel instead (that module wires
-- the click itself), so there's nothing left to connect in this file.

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

-- PERF (technical-debt pass): lastHandSignature above only ever gated the
-- deal-in animation offset -- rebuildHand() itself still destroyed and
-- rebuilt every single card Instance (and unconditionally wiped `selected`/
-- `hoveredIndex`) on EVERY call, including the ~18 unrelated state pushes
-- (buying in the Shop, equipping a Theme, etc. -- see Server/init.server.lua's
-- pushState call sites) that fire render() -> rebuildHand() without the hand
-- itself changing at all. That was also a latent UX bug: a Shop purchase
-- mid-hand-selection would silently clear your card selection. This second
-- signature adds handSortMode (Sort Hand needs a real rebuild even when the
-- cards are identical, since only the display order changed) and gates the
-- whole destroy/rebuild block on it -- an unrelated render now leaves the
-- existing card Instances, and the player's in-progress selection, alone.
local lastHandRenderSignature = nil

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

-- ===== Collection Gallery overlay =====
-- Extracted into Client/Collection.lua. Fully self-contained (only opened
-- from its own corner button), so nothing needs to come back out of the
-- require() call -- see Collection.lua's own StateUpdatedRemote comment
-- for how it now keeps itself live-refreshed without needing anything
-- back out of here (capturing the return value as a new top-level local
-- here blew straight through Lua's 200-local ceiling -- this file is
-- already right up against it, same lesson as ArtAssets.lua's).
require(script.Collection)({
	addTooltip = addTooltip,
	screenGui = screenGui,
	polishPanel = VisualHelpersModule.polishPanel,
	polishButton = VisualHelpersModule.polishButton,
	roundCorner = VisualHelpersModule.roundCorner,
	addSoftShadow = VisualHelpersModule.addSoftShadow,
	playClickSfx = SoundModule.playClickSfx,
	collectionButton = collectionButton,
	menuCollectionButton = MenuScreen.menuCollectionButton,
	particleBurst = ParticleBurstModule.burst, -- Flair panel previews
	-- ACHIEVEMENTS + TITLES (Phase 16): required inline rather than as
	-- its own top-level local -- init.client.lua is already right up
	-- against Lua's 200-local-per-chunk ceiling (Menu.lua's header
	-- comment has the fuller explanation), and nothing else client-side
	-- needs this module.
	Achievements = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("Achievements")),
	EquipTitleRemote = remotes:WaitForChild("EquipTitle"),
	-- BUGFIX (Ahmed's report, see Collection.lua's own comment on this
	-- same dep for the full story): reusing the ALREADY-declared
	-- top-level `StateUpdatedRemote` local from this file's top (zero new
	-- locals) so Collection.lua can keep its own panel live-refreshed
	-- without init.client.lua's render() needing to call back out to it.
	StateUpdatedRemote = StateUpdatedRemote,
	getLatestState = function()
		return latestState
	end,
	popIn = VisualHelpersModule.popIn,
	popOut = VisualHelpersModule.popOut,
	addButtonHoverScale = VisualHelpersModule.addButtonHoverScale,
})

-- ===== Daily Challenge Leaderboard overlay (Phase 11) =====
-- Extracted into Client/DailyLeaderboard.lua. Fully self-contained (only
-- opened from Settings' Leaderboards button), so nothing needs to come back out of
-- the require() call -- same pattern as Collection.lua just above.
require(script.DailyLeaderboard)({
	screenGui = screenGui,
	polishPanel = VisualHelpersModule.polishPanel,
	polishButton = VisualHelpersModule.polishButton,
	roundCorner = VisualHelpersModule.roundCorner,
	addSoftShadow = VisualHelpersModule.addSoftShadow,
	playClickSfx = SoundModule.playClickSfx,
	leaderboardButton = settingsLeaderboardButton,
	menuTickerButton = MenuScreen.menuTickerButton,
	GetDailyLeaderboardRemote = remotes:WaitForChild("GetDailyLeaderboard"),
	GetWeeklyLeaderboardRemote = remotes:WaitForChild("GetWeeklyLeaderboard"),
	GetEndlessLeaderboardRemote = remotes:WaitForChild("GetEndlessLeaderboard"),
	localPlayer = player,
	popIn = VisualHelpersModule.popIn,
	popOut = VisualHelpersModule.popOut,
	addButtonHoverScale = VisualHelpersModule.addButtonHoverScale,
})

-- ===== "Unlocked!" popup + Round reward popup =====
-- Extracted into Client/UnlockPopup.lua and Client/RoundRewardPopup.lua.
-- render() further down still needs to call UnlockPopupModule.showUnlockPopup()/
-- RoundRewardPopupModule.showRoundReward() (and tracks its own lastOwnedPatronIds/
-- hasRenderedOnce/lastPhase state to know when to), so
-- both functions come back out of their require() calls.
local UnlockPopupModule = require(script.UnlockPopup)({
	screenGui = screenGui,
	polishPanel = VisualHelpersModule.polishPanel,
	tweenTo = VisualHelpersModule.tweenTo,
})

local RoundRewardPopupModule = require(script.RoundRewardPopup)({
	screenGui = screenGui,
	polishPanel = VisualHelpersModule.polishPanel,
	tweenTo = VisualHelpersModule.tweenTo,
	playSfx = SoundModule.playSfx,
	SOUND_IDS = SoundModule.SOUND_IDS,
})

-- ===== Road Ahead (journey/roadmap) overlay =====
-- Extracted into Client/Journey.lua. render() still needs to check
-- JourneyOverlay.journeyBackdrop.Visible and call JourneyOverlay.refreshJourney(), so both come back out
-- of the require() call, same pattern as Shop.lua. Purely informational
-- now -- skipping a round lives on its own dedicated screen (ROUND SELECT
-- FEATURE, right below) -- so it no longer needs RoundRewardPopupModule.showRoundReward or a way
-- to fire SkipRound.
local JourneyOverlay = require(script.Journey)({
	screenGui = screenGui,
	getBestHand = function() return PhaseAModule.getBest() end, -- Night victory recap
	polishPanel = VisualHelpersModule.polishPanel,
	polishButton = VisualHelpersModule.polishButton,
	roundCorner = VisualHelpersModule.roundCorner,
	addSoftShadow = VisualHelpersModule.addSoftShadow,
	playClickSfx = SoundModule.playClickSfx,
	tweenTo = VisualHelpersModule.tweenTo,
	DifficultyTiers = DifficultyTiers,
	BossRounds = BossRounds,
	RunStateEngine = RunStateEngine,
	Players = Players,
	player = player,
	journeyButton = journeyButton,
	menuJourneyButton = MenuScreen.menuJourneyButton,
	getLatestState = function()
		return latestState
	end,
	getCurrentTheme = function()
		return currentTheme
	end,
	addTooltip = addTooltip,
	StateUpdatedRemote = StateUpdatedRemote,
})

-- ===== Round Select screen =====
-- Extracted into Client/RoundSelect.lua. render() needs to toggle
-- RoundSelectOverlay.roundSelectFrame.Visible and call RoundSelectOverlay.rebuildRoundSelect() whenever
-- phase == "roundSelect", so both come back out of the require() call.
-- Needs RoundRewardPopupModule.showRoundReward/UnlockPopupModule.showUnlockPopup as deps (for its Tag-result
-- confirmation popups), which is why this is required down here, after
-- RoundRewardPopupModule/UnlockPopupModule above have already run.
local RoundSelectOverlay = require(script.RoundSelect)({
	root = root,
	SIDEBAR_WIDTH = SidebarModule.SIDEBAR_WIDTH,
	polishPanel = VisualHelpersModule.polishPanel,
	polishButton = VisualHelpersModule.polishButton,
	roundCorner = VisualHelpersModule.roundCorner,
	playClickSfx = SoundModule.playClickSfx,
	tweenTo = VisualHelpersModule.tweenTo,
	addTooltip = addTooltip,
	BossRounds = BossRounds,
	RunStateEngine = RunStateEngine,
	SelectRoundRemote = SelectRoundRemote,
	SkipRoundRemote = SkipRoundRemote,
	showRoundReward = RoundRewardPopupModule.showRoundReward,
	showUnlockPopup = UnlockPopupModule.showUnlockPopup,
	showWarning = showWarning,
	getLatestState = function()
		return latestState
	end,
})
do -- overlays disable the gameplay hit areas (deck pile, hand, Play/Discard/Sort); see Client/InputGuard.lua
	local okGuard, errGuard = pcall(function()
		require(script.InputGuard).install({
			root = root,
			overlays = { RoundSelectOverlay.roundSelectFrame, Shop.shopFrame, GameOverPanel.gameOverFrame },
			guarded = { root:FindFirstChild("DeckWidget"), handFrame, actionFrame },
			menuGuarded = MenuScreen.menuFrame,
			tooltip = screenGui:FindFirstChild("Tooltip"),
		})
		require(script.PopupShield).install(screenGui, root) -- popup roots are Active: nothing behind them gets clicks
		require(script.PopupDismiss).install(screenGui, root) -- Escape and a click on the dark area exit every popup; Studio lists the exits
	end)
	if not okGuard then warn("[Client] InputGuard failed: " .. tostring(errGuard)) end

	pcall(function() require(script.PlayerMedallion).install(root) end) -- headshot at the top of the left panel
	pcall(function() -- tutorial targets owned by other modules (Client/TutorialBus.lua)
		local bus = require(script.TutorialBus)
		bus.register("menuPlay", MenuScreen.menuPlayButton)
		bus.register("selectButton", function()
			for _, d in ipairs(RoundSelectOverlay.roundSelectFrame:GetDescendants()) do
				if d.Name == "SelectButton" and d:IsA("TextButton") and d.Visible then return d end
			end
			return nil
		end)
	end)
	pcall(function() -- Daily / Weekly / Seed starts from the menu (Client/ChallengeStart.lua)
		require(script.ChallengeStart).init({
			root = root, menuFrame = MenuScreen.menuFrame, music = SoundModule.backgroundMusic,
			remotes = {
				daily = remotes:WaitForChild("StartDailyChallenge"),
				weekly = remotes:WaitForChild("StartWeeklyChallenge"),
				seed = remotes:WaitForChild("StartSeedRun"),
			},
			getState = function() return latestState end,
			warn = function(line) showWarning(line) end,
		})
	end)
	pcall(function() -- narrow windows and phones: stats drawer, wider hand, scaled button row (Client/CompactLayout.lua)
		require(script.CompactLayout).install({ root = root, handFrame = handFrame, actionFrame = actionFrame, SIDEBAR_WIDTH = SidebarModule.SIDEBAR_WIDTH })
	end)
	pcall(function() -- painted table foreground, hand on the rail (Client/PlayScenePaint.lua)
		require(script.PlayScenePaint).install({ root = root, handFrame = handFrame, actionFrame = actionFrame, SIDEBAR_WIDTH = SidebarModule.SIDEBAR_WIDTH })
	end)
	pcall(function() -- flavor and motion for Play Hand, Discard, Rank and Suit (Client/ActionButtonFX.lua)
		local sortFrame = nil
		for _, c in ipairs(actionFrame:GetChildren()) do
			if c:IsA("Frame") then sortFrame = c end
		end
		require(script.ActionButtonFX).install({
			play = playButton, discard = discardButton,
			rank = sortFrame:FindFirstChild("SortRank", true), suit = sortFrame:FindFirstChild("SortSuit", true),
			burst = ParticleBurstModule.burst,
		})
	end)
end

local lastOwnedPatronIds = {}
local hasRenderedOnce = false
local lastPhase = nil

-- POLISH PASS: SidebarModule.sidebar pulse tracking -- Tips/Hands/Discards/Patron-slot
-- flashes below (see the LAYOUT FEATURE 5 / SidebarModule.tipsLabel/SidebarModule.handsDiscardsLabel
-- assignments in render()) only fire when a value actually changed since
-- the last render, and never on the very first render (same
-- `hasRenderedOnce` guard FEATURE 12 above already uses for the Unlocked
-- popup) -- otherwise every single state push, even ones that don't touch
-- these values at all (buying a Theme, opening a menu), would re-flash
-- them for no reason.
local lastTipsValue = nil
local lastHandsRemaining = nil
local lastDiscardsRemaining = nil
local lastPatronSlotOwned = {}
local SIDEBAR_TIPS_GAIN_COLOR = Color3.fromRGB(255, 214, 130) -- gold, matches the Tips/reward color used everywhere else
local SIDEBAR_SPEND_COLOR = Color3.fromRGB(200, 90, 80) -- muted red, "you just spent/lost some"

local function selectedIndicesArray()
	local out = {}
	for index in pairs(selected) do
		table.insert(out, index)
	end
	-- BUGFIX (Ahmed's playtest -- scoring choreography popped cards in a
	-- seemingly random order instead of left-to-right): this used to sort
	-- by raw hand index (table.sort(out) with no comparator = numeric
	-- ascending), NOT by where the cards actually sit on screen. Sort Hand
	-- (the Rank/Suit buttons) reorders the on-screen DISPLAY without
	-- changing any card's underlying hand index, so as soon as a non-
	-- default sort was active, the raw-index order sent here could be a
	-- totally different order than what's visually laid out left to
	-- right. That order flows straight through: this array becomes both
	-- the cardIndices sent to PlayHandRemote AND (via computeHandPreview)
	-- HandEvaluator.evaluate's `cards` input, whose `scoringCards` order
	-- Scoring.calculate's breakdown -- and therefore ScorePopup.lua's
	-- entire reveal sequence -- plays back verbatim. Sorting by
	-- cardVisualPosition (the same left-to-right on-screen order
	-- buildScoreSourceInfo already uses to lay out the played-card row)
	-- instead of raw index makes the highlight order always match the
	-- row's actual left-to-right layout, whatever the current sort mode.
	table.sort(out, function(a, b)
		return (cardVisualPosition[a] or a) < (cardVisualPosition[b] or b)
	end)
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

	VisualHelpersModule.tweenTo(button, {
		Position = UDim2.new(0.5, 0, 0.5, -lift),
	}, 0.15)

	-- SELECTION/HOVER CUE: see the UIStroke's own comment back in
	-- rebuildHand for why this moved off button.BackgroundColor3. Looked
	-- up rather than tracked in a parallel table, same pattern
	-- VisualHelpers.lua's own functions use for UIScale (:FindFirstChildOfClass).
	local stroke = button:FindFirstChild("SelectionStroke")
	if stroke then
		local strokeThickness, strokeTransparency
		if isSelected and isHovering then
			strokeThickness, strokeTransparency = 4, 0
		elseif isSelected then
			strokeThickness, strokeTransparency = 3, 0.05
		elseif isHovering then
			strokeThickness, strokeTransparency = 2, 0.5
		else
			strokeThickness, strokeTransparency = 1, 1
		end
		VisualHelpersModule.tweenTo(stroke, {
			Color = currentTheme.colors.cardSelected,
			Thickness = strokeThickness,
			Transparency = strokeTransparency,
		}, 0.15)
	end

	if usePop then
		VisualHelpersModule.tweenTo(scaleObject, { Scale = targetScale }, 0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	else
		VisualHelpersModule.tweenTo(scaleObject, { Scale = targetScale }, 0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
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
-- SCORING JUICE fix: this used to only pass a handful of the fields
-- RunState.playHand's own Scoring.calculate call passes -- missing
-- heldCards (Iron Garnish), handLevels, ownedPatronSpecials, Sugar
-- Shield's brittleShielded flag, the active Boss Round's debuff, and the
-- Boss Round's post-hoc chips/mult scaling. That was already a latent gap
-- before this pass (the OLD single-flash popup could show a slightly-off
-- number in those situations too), but the new sequenced breakdown reveal
-- makes it a lot more visible, so this now mirrors RunState.playHand's
-- context construction (see RunState.lua) field-for-field.
local function computeHandPreview(cardIndices)
	if not latestState then
		return nil
	end

	local selectedSet = {} -- [handIndex] = true, for the heldCards pass below
	local selectedCards = {}
	for _, index in ipairs(cardIndices) do
		local card = latestState.hand[index]
		if card then
			table.insert(selectedCards, card)
			selectedSet[index] = true
		end
	end

	if #selectedCards == 0 then
		return nil
	end

	local ownedPatronInstances = {}
	for _, patron in ipairs(latestState.ownedPatrons or {}) do
		local def = Patrons.getById(patron.id)
		if def then
			table.insert(ownedPatronInstances, def)
		end
	end

	-- BossRounds is a Shared module, so looking up the full definition
	-- (debuff/chipsMultiplier/multMultiplier/noRepeatHandTypes -- none of
	-- which the server actually sends, since it only ships
	-- id/name/description for display) by the id the server DOES send is
	-- exactly as accurate as reading it server-side would be.
	local bossModifierDef = latestState.bossModifier and BossRounds.getById(latestState.bossModifier.id)

	-- heldCards: the cards that would remain in hand (NOT played) if this
	-- selection is played -- Iron Garnish's held-card bonus reads this.
	local heldCards = {}
	for index, card in ipairs(latestState.hand) do
		if not selectedSet[index] then
			table.insert(heldCards, card)
		end
	end

	local previewHandsRemaining = math.max(0, latestState.handsRemaining - 1)

	-- PHASE C ("mind-blowing plan" Signature Mechanic): TRUE WILDCARD
	-- preview -- see TrueWildcard.lua's header and RunState.playHand's
	-- matching block. If the one True Wildcard card is part of THIS
	-- selection and hasn't locked in yet, resolve it the exact same
	-- deterministic way the server will for real the moment Play is
	-- actually clicked, so this preview (both the live SidebarModule.sidebar score AND
	-- the popup it drives at Play-time, below) always shows the TRUE
	-- number, never a "whatever it happened to be dealt as" guess.
	-- findBestChoice always restores the card's current rank/suit before
	-- returning -- Lua has no preemption, so nothing else can ever
	-- observe it mid-search -- and the extra set/restore around the real
	-- evaluate+calculate pass below means latestState.hand is back to
	-- exactly how it started by the time this function returns, even
	-- though the hand grid is deliberately showing "???" for this card
	-- the whole time anyway (see the RankSuit label code below).
	local TrueWildcardModule = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("TrueWildcard"))
	local wildcardCard = nil
	for _, card in ipairs(selectedCards) do
		if card.isTrueWildcard and not card.wildcardLocked then
			wildcardCard = card
			break
		end
	end

	local function buildWildcardContext(candidateHandResult)
		local blocked = bossModifierDef and bossModifierDef.noRepeatHandTypes
			and latestState.handTypesPlayedThisRound
			and latestState.handTypesPlayedThisRound[candidateHandResult.name] == true
		if blocked then
			return nil
		end
		return RunStateEngine.addRunCounters({
			allPlayedCards = selectedCards,
			heldCards = heldCards,
			handLevels = latestState.handLevels,
			ownedPatronSpecials = latestState.ownedPatronSpecials,
			brittleShielded = latestState.brittleShieldRound,
			debuff = bossModifierDef and bossModifierDef.debuff,
			tips = latestState.tips,
			alreadyPlayedThisHandTypeThisRound = latestState.handTypesPlayedThisRound
				and latestState.handTypesPlayedThisRound[candidateHandResult.name] == true,
			handsRemaining = previewHandsRemaining,
			discardsRemaining = latestState.discardsRemaining,
			isLastHand = previewHandsRemaining == 0,
			night = latestState.night,
			round = latestState.round,
		}, latestState.runCounters)
	end

	local wildcardResolution = nil
	local originalWildcardRank, originalWildcardSuit
	if wildcardCard then
		originalWildcardRank, originalWildcardSuit = wildcardCard.rank, wildcardCard.suit
		local bestRank, bestSuit = TrueWildcardModule.findBestChoice(selectedCards, wildcardCard, ownedPatronInstances, buildWildcardContext)
		wildcardCard.rank, wildcardCard.suit = bestRank, bestSuit
		wildcardResolution = { rank = bestRank, suit = bestSuit, label = (RANK_NAMES[bestRank] or tostring(bestRank)) .. " of " .. bestSuit }
	end

	local ok, handResult = pcall(HandEvaluator.evaluate, selectedCards)
	if not ok or not handResult then
		if wildcardCard then
			wildcardCard.rank, wildcardCard.suit = originalWildcardRank, originalWildcardSuit
		end
		return nil
	end

	local alreadyPlayed = latestState.handTypesPlayedThisRound and latestState.handTypesPlayedThisRound[handResult.name] == true

	-- Boss Round / Challenge scoring rules (Engine/BossRules): the same helpers RunState.playHand uses, so the preview matches.
	local BossRules = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("BossRules"))
	if BossRules.blocksHand(handResult.name, bossModifierDef, latestState.challenge) then
		if wildcardCard then
			wildcardCard.rank, wildcardCard.suit = originalWildcardRank, originalWildcardSuit
		end
		return { name = handResult.name, chips = 0, mult = 0, score = 0, breakdown = {}, brokenCards = {}, wildcardResolution = wildcardResolution }
	end

	-- "No Repeats" Boss Round: the server scores a repeated hand type as a
	-- flat 0 with no Scoring.calculate call at all -- match that exactly
	-- instead of showing a nonzero preview you'd never actually get paid.
	if bossModifierDef and bossModifierDef.noRepeatHandTypes and alreadyPlayed then
		if wildcardCard then
			wildcardCard.rank, wildcardCard.suit = originalWildcardRank, originalWildcardSuit
		end
		return { name = handResult.name, chips = 0, mult = 0, score = 0, breakdown = {}, brokenCards = {}, wildcardResolution = wildcardResolution }
	end

	local ok2, score, chips, mult, extra = pcall(Scoring.calculate, handResult, BossRules.scoringPatrons(bossModifierDef, ownedPatronInstances), RunStateEngine.addRunCounters({
		patronPower = latestState.challenge and latestState.challenge.patronPower,
		allPlayedCards = selectedCards,
		heldCards = heldCards,
		handLevels = latestState.handLevels,
		ownedPatronSpecials = latestState.ownedPatronSpecials,
		brittleShielded = latestState.brittleShieldRound,
		debuff = bossModifierDef and bossModifierDef.debuff,
		tips = latestState.tips,
		alreadyPlayedThisHandTypeThisRound = alreadyPlayed,
		handsRemaining = previewHandsRemaining,
		discardsRemaining = latestState.discardsRemaining,
		isLastHand = previewHandsRemaining == 0,
		night = latestState.night,
		round = latestState.round,
	}, latestState.runCounters))

	-- Restore now that the breakdown's own per-card LABELS (plain strings,
	-- baked in by Scoring.calculate -- see its header) are already built --
	-- nothing downstream of this point ever needs to re-read the wildcard
	-- card's live rank/suit again. See this block's own comment above.
	if wildcardCard then
		wildcardCard.rank, wildcardCard.suit = originalWildcardRank, originalWildcardSuit
	end

	if not ok2 then
		return nil
	end

	-- Boss Rounds that flatten Chips/Mult (Stale Bread, Thin Chips, Flat
	-- Mult, ...) apply AFTER Scoring.calculate, same as RunState.playHand.
	-- Note this happens after extra.breakdown was already built, so the
	-- ANIMATED running total during ScorePopup's reveal sequence tracks
	-- the hand's own pre-boss-scaling buildup, then the finale visibly
	-- snaps to these final, correctly-scaled numbers -- intentional, reads
	-- like the boss's discount/surcharge landing at the very end.
	if bossModifierDef and bossModifierDef.chipsMultiplier then
		chips = chips * bossModifierDef.chipsMultiplier
	end
	if bossModifierDef and bossModifierDef.multMultiplier then
		mult = mult * bossModifierDef.multMultiplier
	end
	mult = mult * BossRules.scoreFactor(bossModifierDef, latestState.roundStartHands ~= nil and latestState.handsRemaining == latestState.roundStartHands)
	score = chips * mult

	-- extra.breakdown (see Scoring.lua) drives ScorePopup.lua's sequenced
	-- chips/mult/xmult reveal -- see ScorePopupModule.showScorePopup's call site below.
	-- brokenCards (SCORING JUICE, full choreography pass): Brittle Garnish
	-- cards that shattered this hand -- ScorePopup uses this to play a
	-- shatter effect on the matching played-card ghost. Matched by the same
	-- literal card reference as breakdown.source.card (see Scoring.lua).
	return {
		name = handResult.name,
		chips = chips,
		mult = mult,
		score = score,
		breakdown = extra and extra.breakdown,
		brokenCards = extra and extra.brokenCards,
		-- PHASE C: only set when THIS selection includes the unresolved
		-- True Wildcard -- ScorePopup.lua uses this (Play-time call only;
		-- the live SidebarModule.sidebar preview never calls ScorePopupModule.showScorePopup at all) to
		-- play a one-time "locks in" reveal banner.
		wildcardResolution = wildcardResolution,
	}
end

-- SCORING JUICE, full choreography pass: snapshot every hand card's ON-
-- SCREEN button as a screen-space "ghost" clone BEFORE firing PlayHand --
-- the server round-trip's response triggers rebuildHand(), which destroys
-- every card button in handFrame (including cards that are about to be
-- kept, not just played), often well before ScorePopup's animated reveal
-- finishes. Ghosts are cloned Instances parented straight to `root` (not
-- handFrame), positioned with an absolute pixel Position/Size baked in at
-- clone time, so they're completely immune to rebuildHand()'s destroy loop
-- and to the hand re-flowing/re-sorting underneath them. Played cards'
-- REAL buttons are hidden immediately (their ghost visually replaces them
-- in place); held cards' real buttons stay visible and untouched -- their
-- ghost only exists to show a brief Iron Garnish highlight/number-float
-- overlay, and starts invisible.
local function buildScoreSourceInfo(indices)
	if not latestState then
		return { cardGhosts = {}, patronSlotFrames = {} }
	end

	local playedSet = {}
	for _, index in ipairs(indices) do
		playedSet[index] = true
	end

	local cardGhosts = {}
	for index, card in ipairs(latestState.hand) do
		local button = cardButtons[index]
		if button and button.Parent then
			local isPlayed = playedSet[index] == true
			local absPos = button.AbsolutePosition
			local absSize = button.AbsoluteSize
			local ghost = button:Clone()
			ghost.Name = "ScoreGhost"
			ghost.Active = false
			ghost.AutoButtonColor = false
			ghost.AnchorPoint = Vector2.new(0, 0)
			ghost.Position = UDim2.fromOffset(absPos.X, absPos.Y)
			ghost.Size = UDim2.fromOffset(absSize.X, absSize.Y)
			ghost.ZIndex = 30
			-- BUGFIX (Nov 1 2026, played cards lose their art): this
			-- ScreenGui uses Global ZIndex layering, where a child does NOT
			-- inherit its parent's layer. The cloned CardArt image kept its
			-- hand-card ZIndex of 1, so it drew far BELOW the ghost's own
			-- ZIndex-30 white fill and vanished. Lift every cloned piece up
			-- with the ghost (keeping their order); the dim/highlight
			-- overlays ScorePopup adds at 31/32 and the rank/suit face at
			-- 40 still sit above the art as intended.
			for _, piece in ipairs(ghost:GetDescendants()) do
				if piece:IsA("GuiObject") then
					piece.ZIndex = 30 + math.max(0, piece.ZIndex - 1)
				end
			end
			-- BUGFIX (Ahmed's report, repeated twice now: played cards
			-- still render blank/white during the score reveal, even
			-- though the hand itself always shows readable rank/suit
			-- text, and even after forcing the CLONED RankSuit label's
			-- Visible back to true -- that alone wasn't enough, which
			-- means something else (most likely one of ScorePopup.lua's
			-- own per-ghost overlay Frames -- ensureDimOverlay/
			-- ensureHighlightOverlay, both parented on top of this clone
			-- at a higher ZIndex for their focus-dim/highlight-flash
			-- beats) can end up covering it. Rather than keep chasing
			-- exactly which overlay and exactly when, this gives up on
			-- trusting anything inherited from the clone at all: a brand
			-- new label, built fresh from this card's own real
			-- rank/suit, parented LAST so it's always the topmost sibling
			-- (ZIndex 40 -- above the ghost's own art/text AND above
			-- every overlay ScorePopup.lua creates at ghost.ZIndex+1/+2).
			-- A played ghost is short-lived and destroyed right after its
			-- reveal finishes, so there's no later moment this ever needs
			-- to be hidden again -- it only ever needs to be correct.
			--
			-- REFERENCE-MATCH PASS: same idea, now with the full card
			-- layout. CardFace.build destroys the cloned "CardFace" first,
			-- so the ghost never shows a doubled-up face.
			require(script.CardFace).build(
				ghost,
				RANK_NAMES[card.rank] or tostring(card.rank),
				SUIT_SYMBOLS[card.suit] or "?",
				RED_SUITS[card.suit] == true,
				40,
				false,
				card
			)
			-- Held-card ghosts start hidden -- the real card is still
			-- visible and correct in the hand; this ghost only appears for
			-- its own brief Iron Garnish beat. Played-card ghosts start
			-- visible immediately, replacing the (about to be hidden) real
			-- button in place.
			ghost.Visible = isPlayed
			ghost.Parent = root

			local scale = ghost:FindFirstChildOfClass("UIScale")
			if not scale then
				scale = Instance.new("UIScale")
				scale.Parent = ghost
			end

			table.insert(cardGhosts, {
				card = card,
				ghost = ghost,
				scale = scale,
				isPlayed = isPlayed,
				visualPosition = cardVisualPosition[index] or index,
			})

			if isPlayed then
				button.Visible = false
			end
		end
	end

	-- visualPosition (left-to-right ON-SCREEN order, see cardVisualPosition
	-- above) drives the played row's left-to-right reveal, matching how the
	-- cards actually looked in-hand -- NOT click/selection order, which can
	-- be any order the player happened to click them in.
	table.sort(cardGhosts, function(a, b)
		return a.visualPosition < b.visualPosition
	end)

	-- Patron SidebarModule.sidebar slot i always mirrors state.ownedPatrons[i] (see
	-- Sidebar.lua) -- map patronId -> that live Frame reference so
	-- ScorePopup can pulse the right seat. These Frames are NOT cloned --
	-- they're permanent, never destroyed/recreated, so a live reference is
	-- safe to hand off and animate directly.
	local patronSlotFrames = {}
	for i, patron in ipairs(latestState.ownedPatrons or {}) do
		local slot = SidebarModule.patronSlots[i]
		if slot then
			patronSlotFrames[patron.id] = slot.frame
		end
	end

	return { cardGhosts = cardGhosts, patronSlotFrames = patronSlotFrames }
end

local function refreshScorePreview()
	if not latestState then
		SidebarModule.scorePreviewLabel.Text = "0  x  0"
		return
	end

	local selectedIndices = {}
	for index in pairs(selected) do
		table.insert(selectedIndices, index)
	end
	pcall(function()
		local PR = require(game:GetService("ReplicatedStorage").Shared.Engine.PlayRules)
		local okPlay = #selectedIndices == 0 or PR.allows(latestState, #selectedIndices)
		require(script.ActionButtonFX).setSelection(#selectedIndices, okPlay) -- Play/Discard light up or dim (a round's card-count rule keeps Play dim)
		if #selectedIndices > 0 and not okPlay then SidebarModule.scorePreviewLabel.Text = PR.hint(latestState) or "Select cards..." end
	end)

	local preview = computeHandPreview(selectedIndices)
	require(script.HandHighlight).set(preview and preview.name or nil)
	if not preview then
		SidebarModule.scorePreviewLabel.Text = "Select cards..."
		return
	end

	-- Floor before %d -- chips/mult/score can all end up fractional (a
	-- Rainbow/Iron-Garnish-style xmult, or a Boss Round's chips/mult
	-- halving applied to an odd number), and Lua 5.3's %d hard-errors on
	-- a non-integral float. (See ScorePopup.lua's same guard on the
	-- sequenced reveal's own numbers.)
	SidebarModule.scorePreviewLabel.Text = string.format(
		"%s\n%d x %d = %d",
		preview.name,
		math.floor(preview.chips + 0.5),
		math.floor(preview.mult + 0.5),
		math.floor(preview.score + 0.5)
	)
end

local function onCardClicked(index)
	if not latestState or not RunStateEngine.phaseAllowsCardActions(latestState.phase) then
		return
	end
	if not Shop.tutorial.allows("card", { index = index }) then
		return -- tutorial: only the scripted cards can be picked
	end
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
	SoundModule.playCue("card_select")
	refreshCardVisual(index, true)
	refreshScorePreview()

	-- INTERACTIVE TUTORIAL: a no-op unless the walkthrough is both active
	-- AND currently sitting on its "select cards" step -- see that
	-- module's own header. Recounts rather than reusing `count` above
	-- since that local is only computed on the "selecting" branch, not
	-- the "deselecting" one.
	local selectedCount = 0
	for _ in pairs(selected) do
		selectedCount = selectedCount + 1
	end
	local preview = selectedCount > 0 and computeHandPreview(selectedIndicesArray())
	local weakHand = preview and preview.name == "High Card" and latestState.discardsRemaining > 0
	Shop.tutorial.notifySelectionChanged(selectedCount, weakHand, selected)
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

local function rebuildHand(handData, phase)
	-- CARD ART: function-scoped, NOT a new top-level local (this file is
	-- right up against Lua's 200-local-per-chunk ceiling). require() is
	-- cached by Roblox, so once per rebuildHand is cheap.
	local cardArtModule = require(script.ArtAssets)
	local cardFaceTemplate = cardArtModule.cardFaceTemplate
	local cardFaceModule = require(script.CardFace)

	local newSignature = handSignature(handData)
	local isNewHand = newSignature ~= lastHandSignature
	lastHandSignature = newSignature
	-- FLOW FIX: deal animations (fly-in, DealFlip) only run while the phase
	-- is "playing". A skip deals the next round's hand while Round Select is
	-- up; build it silently now and forget the signatures, so pressing Select
	-- rebuilds the hand as a fresh deal with the animation.
	local mayAnimate = RunStateEngine.phaseAllowsCardActions(phase)
	if not mayAnimate then
		isNewHand = false
		lastHandSignature = nil
		pendingNewCardCount = nil
	end

	-- See lastHandRenderSignature's comment above. Skips the whole
	-- destroy/rebuild below when neither the hand's cards nor its sort mode
	-- have changed since the last call -- cardButtons/cardScales/
	-- cardVisualPosition/selected/hoveredIndex are all left exactly as they
	-- were, so an unrelated render (Shop purchase, Theme equip, a Tips
	-- pulse, ...) no longer costs a full hand rebuild or clears the
	-- player's selection.
	local renderSignature = newSignature .. "|" .. tostring(handSortMode)
	if renderSignature == lastHandRenderSignature then
		return
	end
	lastHandRenderSignature = mayAnimate and renderSignature or nil

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
		-- Real size is set by CardFace.layoutHand after the loop (fits the
		-- window); this is just a sane starting value.
		slot.Size = UDim2.new(0, 84, 0, 122)
		slot.BackgroundTransparency = 1
		slot.LayoutOrder = visualPosition
		slot:SetAttribute("HandIndex", index) -- stable tag for the tutorial spotlight (hand is rebuilt every deal)
		slot.Parent = handFrame

		local button = Instance.new("TextButton")
		button.Size = UDim2.fromScale(1, 1)
		button.Position = UDim2.fromScale(0.5, 0.5)
		button.AnchorPoint = Vector2.new(0.5, 0.5)
		button.Font = Enum.Font.GothamBold
		button.TextSize = 20
		-- Fallback fill -- shown if cardFaceTemplate below is ever the
		-- "rbxassetid://0" placeholder or fails to load (see
		-- Client/ArtAssets.lua). No longer tweened for selection; see the
		-- UIStroke-based cue below and in refreshCardVisual.
		button.BackgroundColor3 = currentTheme.colors.cardBase
		-- Own Text left blank -- rank/suit render via cardRankSuitLabel
		-- below instead, a CHILD of button, so it's guaranteed to draw on
		-- top of cardArt regardless of how a TextButton's own Text and its
		-- children's render order interact.
		button.Text = ""
		button.Parent = slot
		-- VisualHelpersModule.roundCorner, not VisualHelpersModule.polishButton: VisualHelpersModule.polishButton now also adds the
		-- gold-chrome UIStroke, and a card already has its own
		-- SelectionStroke below -- the card art shouldn't get a permanent
		-- gold border, and the selection cue needs to be its only stroke.
		VisualHelpersModule.roundCorner(button, 8)

		-- CARD ART: the single blank-centered card-face template (see
		-- ArtAssets.lua's header), the same image for all 52 cards --
		-- rank/suit is cardRankSuitLabel's text on top of it. Stretch, not
		-- Crop, so the whole template fits the portrait button. ZIndex 1 -- one
		-- below cardRankSuitLabel and the Garnish/Special/Stamp badge
		-- further below (both ZIndex 2) -- so it's always a backdrop,
		-- never covering the text or badge. VisualHelpersModule.roundCorner matches
		-- VisualHelpersModule.polishButton's own radius above so the image's corners read as
		-- rounded too, without needing button.ClipsDescendants (untouched
		-- elsewhere).
		local cardArt = Instance.new("ImageLabel")
		cardArt.Name = "CardArt"
		cardArt.Size = UDim2.fromScale(1, 1)
		cardArt.BackgroundTransparency = 1
		cardArt.BorderSizePixel = 0
		cardArt.ScaleType = Enum.ScaleType.Stretch
		cardArt.Image = cardFaceTemplate
		cardArt.ZIndex = 1
		cardArt.Parent = button
		VisualHelpersModule.roundCorner(cardArt, 8)

		-- The card's rank/suit -- always shown. Not a fallback anymore:
		-- the face template's center is blank on purpose, so this text IS
		-- how every card reads its rank/suit, art or no art.
		--
		-- REFERENCE-MATCH PASS (Nov 1 2026): a real card layout instead of
		-- one centered "A\n♥" label -- corner rank + small suit, big
		-- center suit, small bottom-right suit. See Client/CardFace.lua.
		local isHiddenWildcard = card.isTrueWildcard and not card.wildcardLocked
		cardFaceModule.build(
			button,
			RANK_NAMES[card.rank] or tostring(card.rank),
			SUIT_SYMBOLS[card.suit] or "?",
			RED_SUITS[card.suit] == true,
			2,
			isHiddenWildcard,
			card -- Garnish / Special / Stamp: the universal pattern is drawn from it (Engine/SpecialPatterns)
		)

		-- PHASE C ("mind-blowing plan" Signature Mechanic): the one True
		-- Wildcard card shows "???" instead of its real dealt rank/suit
		-- right up until it actually resolves (RunState.playHand) --
		-- its real identity isn't the point yet, so showing it would just
		-- spoil the reveal. The card-face template carries no rank/suit of
		-- its own, so swapping this label's text is all it takes.
		-- (Handled by CardFace.build's hiddenWildcard argument above.)

		-- SELECTION/HOVER CUE (redesign for the card-art rollout): this
		-- used to be button.BackgroundColor3 tweening between the theme's
		-- cardBase/cardSelected colors -- completely invisible now that
		-- cardArt sits on top of it. Replaced with a UIStroke glow, tweened
		-- in refreshCardVisual below -- stays visible with or without the
		-- art image, and reads at least as clearly as the old color swap
		-- did. Starts fully transparent; refreshCardVisual dials it in the
		-- moment this card is first hovered/selected.
		local cardStroke = Instance.new("UIStroke")
		cardStroke.Name = "SelectionStroke"
		cardStroke.Color = currentTheme.colors.cardSelected
		cardStroke.Thickness = 1
		cardStroke.Transparency = 1
		cardStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		cardStroke.Parent = button

		-- PHASE 1B: Garnish/Special/Stamp visual treatment. Doesn't need
		-- full card art (see the feature-expansion project doc's stated v1
		-- scope) -- just a small corner badge with the relevant icon(s) so a
		-- modified card visibly reads as modified in the hand. Priority
		-- order (rarest/most-impactful first) when a card has more than one:
		-- Special, then Stamp, then Garnish.
		if card.garnish or card.special or card.stamp or card.isTrueWildcard then
			local icons = {}
			-- PHASE C: the True Wildcard's own marker always leads -- it's
			-- a once-per-run identity, not a stacking modifier, so it
			-- reads first regardless of whatever else this card also
			-- carries (before OR after it resolves -- see the RankSuit
			-- "???" override above for the part that's ONLY pre-resolution).
			if card.isTrueWildcard then
				table.insert(icons, "🎴")
			end
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
			badge.Size = UDim2.new(0, 0, 0, 18)
			badge.AutomaticSize = Enum.AutomaticSize.X
			badge.BackgroundTransparency = 1
			badge.Font = Enum.Font.GothamBold
			badge.TextSize = 14
			badge.TextColor3 = Color3.fromRGB(255, 255, 255)
			badge.TextStrokeTransparency = 0.3
			badge.Text = table.concat(icons, "")
			badge.ZIndex = 2
			-- Parented to `button`, NOT `slot` -- button fills slot exactly
			-- (see button.Size/Position above), so the badge's corner
			-- position reads identically either way, BUT `button` is what
			-- ScorePopup.lua's buildScoreSourceInfo clones into a "ghost"
			-- for the scoring choreography (button:Clone()). A `slot`-
			-- parented badge is a sibling of button, not a descendant, so
			-- Instance:Clone() would never carry it over -- every played/
			-- held card ghost shown during Play Hand's reveal sequence
			-- would silently be missing its Garnish/Special/Stamp icon.
			-- Found via independent review before shipping.
			badge.Parent = button
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
					VisualHelpersModule.tweenTo(button, { Position = UDim2.fromScale(0.5, 0.5), Rotation = 0 }, 0.24, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
				end
			end)
			-- Cosmetic back-to-face flip (overlay child of the button; no input/state effect).
			pcall(function()
				local cos = latestState and latestState.cosmetics
				require(script.DealFlip).play(button, visualPosition, cos and cos.cardBackId)
			end)
		end

		cardButtons[index] = button
		cardScales[index] = scaleObject
		cardVisualPosition[index] = visualPosition

		button.MouseButton1Click:Connect(function()
			onCardClicked(index)
		end)
		button.MouseEnter:Connect(function()
			if require(script.ModalStage).blocks(button) then return end -- a modal is open: hand cards ignore hover
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

	-- REFERENCE-MATCH PASS: size cards to the window + draw the tray.
	cardFaceModule.layoutHand(handFrame)
end

refreshHandSort = function()
	if latestState then
		rebuildHand(latestState.hand, latestState.phase)
	end
end

local function render(state)
	latestState = state

	-- INTERACTIVE TUTORIAL: started only from the menu's "Tutorial"
	-- button now (no auto-start) -- onRender just lets an in-progress
	-- walkthrough react to the new state (e.g. advance once a hand's dealt).
	Shop.tutorial.onRender(state)

	-- BUGFIX (Ahmed's Studio screenshot): a score reveal sequence can
	-- easily still be mid-animation (several anticipation pauses stacked
	-- up) when the hand that was just played WINS the round and the
	-- server's response pushes phase away from "playing" -- e.g. straight
	-- to "shop". Nothing used to stop the in-flight sequence when that
	-- happened, so its played-card ghosts (parented to `root`, which
	-- stays around underneath every overlay) kept flying around ON TOP of
	-- the Shop screen. Cancel any in-flight popup the instant we're no
	-- longer in "playing" -- cheap and safe to call unconditionally
	-- (ScorePopupModule.cancelScorePopup no-ops visually if nothing was showing).
	if state.phase ~= "playing" then
		ScorePopupModule.cancelScorePopup()
	end

	-- SCORING JUICE: background music track, picked from live state every
	-- render -- SoundModule.setMusicTrack no-ops if it's already the right track, so
	-- calling it unconditionally on every state push is cheap. Priority:
	-- Shop (you're browsing, not playing a hand) beats Boss (the target-
	-- score banner) beats plain Gameplay -- matches which one is actually
	-- true first in RunState's own phase/round flow.
	if state.phase == "shop" then
		SoundModule.setMusicTrack("shop")
	elseif state.bossModifier then
		SoundModule.setMusicTrack("boss")
	else
		-- per-region track when one is set in Engine/SoundIds (else the plain gameplay track)
		local okRegion, musicKey = pcall(function()
			local engine = game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine")
			local route = state.worldRoute
			local regionId = route and #route > 0 and require(engine:WaitForChild("WorldMap")).regionOf(route[#route])
			return SoundModule.SoundIds.regionMusicKey(regionId)
		end)
		SoundModule.setMusicTrack(okRegion and musicKey or "gameplay")
	end

	-- visual extras never stop the HUD and the Choice screen below from updating
	local okExtras, errExtras = pcall(function()
		require(script.CosmeticSetsView).apply(state)
		require(script.GameplayScene).get().update(state)
	end)
	if not okExtras then warn("[Client] scene update failed: " .. tostring(errExtras)) end
	pcall(function() require(script.CharacterStage).get().update(state) end) -- live characters (before BossFight so it can hide the portrait)
	pcall(require(script.BossFight).get().update, state) -- visual only, never break render
	pcall(require(script.EndlessChips).update, state) -- Crowd Rule chips and banner, display only
	pcall(require(script.BlessingChip).update, state) -- blessing and curse chip, display only
	pcall(require(script.LoginStreakUI).update, state) -- menu strip and login popup, display only
	pcall(require(script.RunSummaryUI).update, state) -- Game Over summary and badge, display only
	pcall(require(script.UnlockToast).update, state) -- "Unlocked: ..." toast, display only
	pcall(require(script.MenuRank).update, state) -- Tavern Rank bar on the menu, display only
	pcall(require(script.MenuRegulars).update, state, MenuScreen.menuFrame) -- Tavern Regulars row on the menu, display only
	pcall(require(script.NextGoalBanner).update, state) -- Next Goal line on the menu, display only
	pcall(require(script.StorePanel).update, state) -- keeps an open Store current; opens it once after the second run
	pcall(require(script.NewsPanel).update, state) -- News banner on the menu and the News panel, display only
	pcall(require(script.FeelHooks).update, state) -- coin, discard and shuffle sounds from state changes, audio only
	pcall(require(script.ChoicePanel).update, state) -- start-of-run draft and event cards, display only
	pcall(require(script.FollowPrompt).update, state) -- one-time experience notifications prompt after the first win
	pcall(require(script.QuestsPanel).update, state) -- keeps an open Quests panel current, display only
	pcall(require(script.DailyRewardsPanel).update, state) -- keeps an open Daily Rewards ladder current, display only
	pcall(require(script.FirstTimeHints).update, state) -- one shot hint bubbles (Engine/Hints.lua), display only
	pcall(require(script.LegendCrest).update, screenGui, state) -- Legend crest and gold aura on the name medallion, display only
	pcall(require(script.FlairFX).setState, state) -- equipped Flair for the popups (visual only)
	pcall(require(script.BossScout).update, screenGui, state) -- Boss Scout banner, Counter chip and Rule Ban tokens

	-- GENRE PARITY: an "Ante counter" (1/8, then Endless Mode) -- once
	-- state.night passes the server's nightCap (default 8), there's no
	-- more "/8" to show (you're past it for good), so switch to an
	-- "(Endless)" tag instead.
	local nightCap = state.nightCap or 8
	local clearedHeader = require(ReplicatedStorage.Shared.Engine.PostBoss).sidebarHeader(state)
	if clearedHeader then
		SidebarModule.nightRoundLabel.Text = clearedHeader
	elseif state.night > nightCap then
		SidebarModule.nightRoundLabel.Text = string.format("Night %d (Endless) · Round %d", state.night, state.round)
	else
		SidebarModule.nightRoundLabel.Text = string.format("Night %d/%d · Round %d", state.night, nightCap, state.round)
	end
	-- DAILY CHALLENGE (Phase 11) / WEEKLY CHALLENGE + SEED CODES (Phase
	-- 16): show/hide the SidebarModule.sidebar badge based on whatever the server says
	-- THIS run is -- state.isDaily/dailyDateKey (and their Weekly/Seeded
	-- counterparts) are shipped fresh in every serializeState() call, so
	-- this always reflects the actual current run, including after
	-- "New Run..." swaps a seeded run back out for a normal one.
	SidebarModule.setRunModeBadge(state.isDaily, state.dailyDateKey, state.isWeekly, state.weeklyDateKey, state.isSeeded, state.seedCode)
	root:SetAttribute("ToastScreen", require(ReplicatedStorage.Shared.Engine.ToastPlacement).screenOf(state)) -- toasts never cover titles
	pcall(SettingsOverlay.setBlessing, state.runModifier) -- "This run: <blessing>" row in Settings
	pcall(function() -- the seed / date / week also shows in Settings
		local info = require(ReplicatedStorage.Shared.Engine.SeedDisplay).label(state)
		SettingsOverlay.setRunLabel(info and ("This run  |  " .. info.text) or nil)
	end)
	-- POLISH PASS: flash the Tips box gold on a gain, red on a loss/spend --
	-- and the Hands/Discards box red whenever either ticks down (a hand
	-- played or a discard used). Guarded by hasRenderedOnce so a fresh
	-- render (session start, or resyncing into an already-in-progress run)
	-- never flashes for state that was already true, only for something
	-- that visibly CHANGED.
	if hasRenderedOnce and state.tips ~= lastTipsValue then
		VisualHelpersModule.pulseFrame(SidebarModule.tipsBox, state.tips > lastTipsValue and SIDEBAR_TIPS_GAIN_COLOR or SIDEBAR_SPEND_COLOR)
	end
	lastTipsValue = state.tips
	do
		local tipsText = string.format("Tips: %d", state.tips)
		SidebarModule.setIconText("tips", tipsText, "💰 " .. tipsText, tipsText, SidebarModule.tipsLabel.TextSize)
	end

	if hasRenderedOnce
		and (state.handsRemaining < lastHandsRemaining or state.discardsRemaining < lastDiscardsRemaining) then
		VisualHelpersModule.pulseFrame(SidebarModule.handsDiscardsBox, SIDEBAR_SPEND_COLOR)
	end
	lastHandsRemaining = state.handsRemaining
	lastDiscardsRemaining = state.discardsRemaining
	do
		local handsText = string.format("Hands: %d   Discards: %d", state.handsRemaining, state.discardsRemaining)
		SidebarModule.setIconText("hands", handsText, "🃏 " .. handsText, handsText, SidebarModule.handsDiscardsLabel.TextSize)
	end
	DeckWidgetModule.deckCountLabel.Text = string.format("%d/52", countRemainingInDeck(state.deckCounts))

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
		local PatronPlaqueModule = require(script.PatronPlaque)
		local ownedPatrons = state.ownedPatrons or {}
		local slotLimit = math.min(state.patronSlotLimit or #ownedPatrons, SidebarModule.MAX_SIDEBAR_PATRON_SLOTS)
		if SidebarModule.fitSeats then SidebarModule.fitSeats(slotLimit) end
		for i = 1, SidebarModule.MAX_SIDEBAR_PATRON_SLOTS do
			local slot = SidebarModule.patronSlots[i]
			if slot then
				if i > slotLimit then
					slot.frame.Visible = false
				else
					slot.frame.Visible = true
					local owned = ownedPatrons[i]
					if slot.pulse then slot.pulse.Visible = (owned == nil) end
					if owned then
						slot.frame.BackgroundColor3 = Color3.fromRGB(78, 52, 26)
						slot.label.TextColor3 = Color3.fromRGB(255, 222, 150)
						slot.label.Text = owned.name:sub(1, 1)
						PatronPlaqueModule.updateSlot(slot, owned.id)
						-- Tier ring color (ring only, no ornaments on seats).
						pcall(function()
							local seatRing = slot.frame:FindFirstChildOfClass("UIStroke")
							local tier = require(ReplicatedStorage.Shared.Engine.CollectionBook).rarityForId("patrons", owned.id)
							if seatRing then
								seatRing.Color = tier == "common" and Color3.fromRGB(96, 64, 36) or require(script.RarityFrame).colorFor(tier)
							end
						end)
						-- POLISH PASS: a fresh Patron pop into this seat gets a
						-- one-off scale pop (VisualHelpersModule.popScale -- NOT VisualHelpersModule.pulseFrame, since
						-- this frame's BackgroundColor3 is already meaningful
						-- state that flips every render between owned/empty;
						-- VisualHelpersModule.pulseFrame's color-revert-on-settle would fight that).
						if hasRenderedOnce and not lastPatronSlotOwned[i] then
							VisualHelpersModule.popScale(slot.frame, 1.35, 0.3)
						end
					else
						PatronPlaqueModule.updateSlot(slot, nil)
						local emptyRing = slot.frame:FindFirstChildOfClass("UIStroke")
						if emptyRing then
							emptyRing.Color = Color3.fromRGB(96, 64, 36)
						end
						slot.frame.BackgroundColor3 = Color3.fromRGB(196, 168, 118)
						slot.label.TextColor3 = Color3.fromRGB(120, 88, 54)
						slot.label.Text = "+" -- open seat, not "?" -- there's nothing hidden here anymore
					end
					lastPatronSlotOwned[i] = (owned ~= nil)
				end
			end
		end
		SidebarModule.patronsCountLabel.Text = string.format("%d/%d", #ownedPatrons, slotLimit)
		-- PATRON BONDS: glowing threads between bonded seats (Client/BondThreads.lua), built lazily, never fatal.
		pcall(function()
			local threads = SidebarModule.bondThreads
			if not threads then
				threads = require(script.BondThreads).new(SidebarModule.sidebar, SidebarModule.patronSlots)
				SidebarModule.bondThreads = threads
			end
			threads.update(state)
		end)
	end

	-- LAYOUT FEATURE 2: reward mirrors RunState.lua's playHand payout exactly
	-- (tipsPerRoundWin, doubled on a Boss Round) so the SidebarModule.sidebar never shows a
	-- number that doesn't match what you actually get paid.
	local reward = RunStateEngine.DefaultConfig.tipsPerRoundWin
	if state.bossModifier or state.isBossRound then
		reward = reward + RunStateEngine.DefaultConfig.tipsPerRoundWin
	end
	SidebarModule.scoreLabel.Text = string.format("Score: %d / %d\nReward: $%d", state.roundScore, state.targetScore, reward)
	SidebarModule.placeRewardIcon(string.format("Reward: $%d", reward))

	if state.bossModifier and not clearedHeader then
		-- REFERENCE-MATCH PASS: name on a bigger first line, rule text
		-- smaller underneath (SidebarModule.blindInfoLabel has RichText on -- escape so
		-- a "&" or "<" in a description can't break the markup).
		local function esc(text)
			return (tostring(text):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
		end
		local bossLine = '<font size="17">%s%s</font>\n<font size="13" color="#E6D2AA">%s</font>'
		local bossName = esc(state.bossModifier.name)
		local bossRule = esc(state.bossModifier.description)
		SidebarModule.setIconText(
			"boss",
			string.format(bossLine, "", bossName, bossRule),
			string.format(bossLine, "👑 ", bossName, bossRule),
			tostring(state.bossModifier.name),
			17
		)
	else
		-- GENRE PARITY: Small Blind (round 1) / Big Blind (everything
		-- else before the Boss) -- matches RoundSelect.lua's round panel
		-- labels and the 1x/2x score multiplier each one actually gets
		-- (see RunState.blindMultiplierFor).
		-- No crown on a normal round: set the text directly, and make sure
		-- a crown left over from a Boss Round is hidden.
		local postTitle, postRule = require(ReplicatedStorage.Shared.Engine.PostBoss).sidebarRule(state)
		SidebarModule.blindInfoLabel.Text = string.format(
			'<font size="17">%s</font>\n<font size="13" color="#E6D2AA">%s</font>',
			postTitle or (state.round == 1 and "Small Round" or string.format("Big Round %d", state.round)),
			postRule or "No special rules this round."
		)
		SidebarModule.hideLineIcon("boss")
	end

	-- PHASE A (Spectacle pass): one-shot "arrival" beat the first time a
	-- NEW Boss Round shows up -- see BossIntro.lua's header. Gated on
	-- hasRenderedOnce for the same reason the "Unlocked!" popup below is --
	-- resuming/reconnecting mid-Boss-Round shouldn't replay the intro.
	if hasRenderedOnce then
		-- The scene walk-in (GameplayScene) plays first; the intro follows when it ends.
		local scene = require(script.GameplayScene).get()
		if scene.walkInActive() then
			scene.afterWalkIn(function(latest)
				PhaseAModule.announceBossIfNew(latest)
			end)
		else
			PhaseAModule.announceBossIfNew(state)
		end
	end

	rebuildHand(state.hand, state.phase)
	-- rebuildHand resets `selected` to empty on an actual hand change, and
	-- otherwise leaves it (and the preview) exactly as the player left it --
	-- either way, recomputing here keeps the preview in sync.
	refreshScorePreview()

	if JourneyOverlay.journeyBackdrop.Visible then
		JourneyOverlay.refreshJourney() -- keep "you are here" accurate if it's open across a round change
	end

	-- FEATURE 12: detect newly-owned Patrons and celebrate the first
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

		if newPatron then
			local okTier, tier = pcall(function()
				return require(ReplicatedStorage.Shared.Engine.CollectionBook).rarityForId("patrons", newPatron.id)
			end)
			UnlockPopupModule.showUnlockPopup(newPatron.name, newPatron.description, okTier and tier or nil)
		end

		lastOwnedPatronIds = ownedPatronIds
		hasRenderedOnce = true
	end

	-- INTERACTIVE TUTORIAL: captured here, BEFORE lastPhase gets reassigned
	-- just below (same "true previous phase" need as RoundSelectOverlay.rebuildRoundSelect's
	-- own comment a few lines down) -- notifyEnteredShop() itself fires
	-- later, after Shop.rebuildShop(state) actually builds shopBuyListFrame's
	-- rows, not here.
	local justEnteredShop = state.phase == "shop" and lastPhase ~= "shop" and hasRenderedOnce

	-- Round reward popup: fire once, right on the transition INTO "shop"
	-- (i.e. the round was just won), not on every re-render while already
	-- shopping (e.g. after buying a Patron, phase is still "shop").
	if state.phase == "shop" and lastPhase ~= "shop" and hasRenderedOnce and RoundRewardPopupModule.showRoundReward then
		-- BUGFIX: `reward` above only ever mirrored the flat/boss-doubled
		-- payout, so it silently under-reported Patron onRoundWin bonuses
		-- and the universal interest rule -- state.lastRoundReward (set by
		-- RunState.playHand) is the ACTUAL total Tips gained, so prefer it
		-- and only fall back to the old estimate if it's somehow missing.
		local actualReward = state.lastRoundReward or reward
		-- GENRE PARITY: this is also the one moment a win at nightCap
		-- (state.night hasn't advanced past it yet -- that only happens
		-- once "Next Round" is clicked) is visible, so give it a
		-- celebratory headline instead of the usual "Round Complete!".
		-- Can only ever be true for ONE shop visit per run -- state.night
		-- only increases, so this exact equality never holds again.
		local title = nil
		if state.wonRun and state.night == (state.nightCap or 8) then
			title = string.format("🏆 Night %d Cleared: Endless Mode Unlocked!", state.night)
		end
		RoundRewardPopupModule.showRoundReward(actualReward, title)
	end

	-- ROUND SELECT FEATURE: rebuild BEFORE `lastPhase` gets reassigned just
	-- below, so RoundSelectOverlay.rebuildRoundSelect receives the TRUE previous phase (see its
	-- own header comment for why it needs that to tell a confirmed skip
	-- apart from a normal play-through that also ends up back on this
	-- screen).
	if state.phase == "roundSelect" then
		RoundSelectOverlay.rebuildRoundSelect(state, lastPhase)
	end
	-- PHASE A (Spectacle pass): a fresh run starting right after a
	-- gameover screen (by far the common "Play Again" path) clears last
	-- run's "Biggest Hand" stat before GameOver.lua could ever show it
	-- again. The OTHER reset path (RunSetup.lua's "Begin Run", for
	-- starting a new run without ever reaching gameover) is wired via
	-- onBeginRun below.
	if lastPhase == "gameover" and state.phase ~= "gameover" then
		PhaseAModule.resetRun()
		require(script.GameplayScene).get().reset()
	end
	lastPhase = state.phase

	RoundSelectOverlay.roundSelectFrame.Visible = (state.phase == "roundSelect")
	pcall(require(script.SidebarSlide).set, root, SidebarModule.SIDEBAR_WIDTH, state.phase == "roundSelect") -- stats panel away on Round Select
	Shop.shopFrame.Visible = (state.phase == "shop")
	GameOverPanel.gameOverFrame.Visible = (state.phase == "gameover")
	if state.phase == "shop" then
		Shop.rebuildShop(state)
		Shop.rebuildMyPatronsTab(state)
		Shop.rebuildMyRecipesTab(state)
		if justEnteredShop then
			Shop.tutorial.notifyEnteredShop()
		end
	else
		-- Left the shop (round advanced, or the run ended) -- close the
		-- Recipe card/suit picker if it was left open, so it doesn't show up
		-- stale (still mid-selection for a recipe from last visit) the next
		-- time the shop opens.
		closeRecipeTargetPanel()
	end

	-- BUGFIX: this used to set gameOverLabel.Text directly, but
	-- gameOverLabel was never actually destructured from GameOverPanel (see
	-- that module's header comment) -- so this line threw "attempt to
	-- index nil with 'Text'" on every single state push once phase ==
	-- "gameover", right up until whatever the LAST successful render() call
	-- managed to draw stayed frozen (in practice, the panel's original
	-- build-time static text, never the dynamic Night/Round line). Fixed by
	-- moving this panel's own text/stats/reveal-animation logic into
	-- GameOver.lua's GameOverPanel.refreshGameOver, which owns its own labels directly.
	if state.phase == "gameover" then
		GameOverPanel.refreshGameOver(state, PhaseAModule.getBest())
	end
end

-- ===== Wire up buttons =====

playButton.MouseButton1Click:Connect(function()
	if not latestState or not RunStateEngine.phaseAllowsCardActions(latestState.phase) then
		return
	end
	if not Shop.tutorial.allows("play") then return end
	local indices = selectedIndicesArray()
	if #indices < 1 then
		showWarning(require(game:GetService("ReplicatedStorage").Shared.Engine.PlayRules).hint(latestState) or "Select 1-5 cards first.")
		return
	end
	do -- the round's card-count rule (Full Table, One at a Time, Four on Top, minimums): never send a play the server refuses
		local okCount, why = require(game:GetService("ReplicatedStorage").Shared.Engine.PlayRules).allows(latestState, #indices)
		if not okCount then
			showWarning(why)
			return
		end
	end
	SoundModule.playCue("card_play")

	-- LAYOUT FEATURE 7: pop the score BEFORE firing the remote, off the same
	-- preview computation the SidebarModule.sidebar already uses -- see computeHandPreview.
	local preview = computeHandPreview(indices)

	if preview then
		-- PHASE A (Spectacle pass, see claude/mind-blowing-plan.md): decide
		-- "legendary" here, not inside ScorePopup.lua, since it needs
		-- latestState.targetScore -- a dependency ScorePopup.lua
		-- deliberately doesn't take (see its own comment). Relative to the
		-- round's OWN target rather than a fixed score, so this keeps
		-- meaning "a genuinely overkill hand" at Night 1 AND at Night
		-- 8/Endless Mode, where target scores are an order of magnitude
		-- apart (see RunState.targetScoreFor). The xmult check catches the
		-- other case: a single huge multiplier chain feels legendary even
		-- on an easy early round that a big score alone wouldn't flag.
		--
		-- PLAYTEST FEEDBACK (Ahmed, right after this first shipped): 1.5x/
		-- xmult>=3 fired constantly once a deck was reasonably built (his
		-- screenshot: 376 vs a 240 target, just 1.57x) -- "too much", it
		-- "stays like this the whole time" because a new one kept
		-- retriggering before the last one finished. Raised meaningfully
		-- so this is a genuinely rare, special moment again, not a
		-- once-or-twice-a-round occurrence.
		-- Score juice inputs (ScorePopup finale: NEW BEST, target-clear pulse).
		preview.targetScore = latestState.targetScore
		preview.roundScoreBefore = latestState.roundScore or 0
		preview.isRunStart = latestState.night == 1 and latestState.round == 1 and (latestState.roundScore or 0) == 0
		preview.isLegendary = false
		if latestState.targetScore and latestState.targetScore > 0 and preview.score >= latestState.targetScore * 2.2 then
			preview.isLegendary = true
		end
		if not preview.isLegendary and preview.breakdown then
			for _, entry in ipairs(preview.breakdown) do
				if entry.kind == "xmult" and entry.amount >= 4 then
					preview.isLegendary = true
					break
				end
			end
		end
		PhaseAModule.recordHand(preview)

		-- BUGFIX (Ahmed's report, "SFX doesn't work anymore and when you
		-- play a card, nothing shows" -- right after the card-art rollout):
		-- buildScoreSourceInfo/ScorePopupModule.showScorePopup is pure animation/choreography
		-- -- the card-art rollout added a Clone() of a now-more-complex card
		-- button (CardArt image, RankSuit label, SelectionStroke) plus new
		-- overlay-Frame logic in ScorePopup.lua, any one of which erroring
		-- on some particular hand (a nil/odd card, an asset that hasn't
		-- finished uploading, anything) used to take the ENTIRE click
		-- handler down with it -- which skipped not just the popup's OWN
		-- tick/thud SFX (explaining "SFX doesn't work") but also the
		-- PlayHandRemote:FireServer call below (explaining "nothing shows"
		-- -- the hand doesn't even advance). pcall isolates the
		-- choreography so a bug in the JUICE can never again block the
		-- actual Play Hand action -- worst case now is a silent/missing
		-- popup with the hand still advancing normally and the real error
		-- logged to Output (warn(), not a hard error) so it's easy to spot
		-- and fix for real, instead of silently eating the whole turn.
		--
		-- sourceInfo built ONLY once we know the popup will actually show --
		-- buildScoreSourceInfo hides the played cards' real buttons, so
		-- skipping it on a nil preview avoids ever leaving a card
		-- permanently hidden with nothing showing in its place.
		local ok, sourceInfoOrErr = pcall(buildScoreSourceInfo, indices)
		if ok then
			local ok2, err2 = pcall(ScorePopupModule.showScorePopup, preview, sourceInfoOrErr)
			if not ok2 then
				warn("[WildcardTavern] ScorePopupModule.showScorePopup errored, hand still playing normally: " .. tostring(err2))
			end
		else
			warn("[WildcardTavern] buildScoreSourceInfo errored, hand still playing normally: " .. tostring(sourceInfoOrErr))
		end
	end

	-- The server (RunState.playHand -> removeIndicesFromHand) always keeps
	-- surviving cards in their original relative order and appends the
	-- newly-drawn replacements at the END of state.hand -- so the next
	-- rebuildHand() knows exactly how many trailing raw indices are the
	-- freshly dealt ones. See pendingNewCardCount / dealFromIndex there.
	pendingNewCardCount = #indices

	PlayHandRemote:FireServer(indices)
	Shop.tutorial.notifyHandPlayed()
end)

discardButton.MouseButton1Click:Connect(function()
	if not latestState or not RunStateEngine.phaseAllowsCardActions(latestState.phase) then
		return
	end
	if not Shop.tutorial.allows("discard") then return end
	if latestState.discardsRemaining <= 0 then
		showWarning("No discards left this round.")
		return
	end
	local indices = selectedIndicesArray()
	if #indices < 1 then
		showWarning("Select 1-5 cards to discard.")
		return
	end
	local function doDiscard()
		SoundModule.playSfx(SoundModule.SOUND_IDS.discard)
		pendingNewCardCount = #indices -- see the matching comment on Play Hand above
		DiscardRemote:FireServer(indices)
		Shop.tutorial.notifyDiscardUsed()
	end
	-- Settings > Gameplay > Confirm Before Discard.
	if require(script.ClientSettings).get("confirmDiscard") then
		local count = math.floor(#indices)
		ConfirmDialogModule.showConfirmDialog(string.format("Discard %d card%s?", count, count == 1 and "" or "s"), doDiscard)
	else
		doDiscard()
	end
end)

Shop.nextRoundButton.MouseButton1Click:Connect(function()
	if not Shop.tutorial.allows("nextRound") then return end
	SoundModule.playClickSfx()
	AdvanceRoundRemote:FireServer()
	Shop.tutorial.notifyNextRoundClicked()
end)

GameOverPanel.playAgainButton.MouseButton1Click:Connect(function()
	SoundModule.playClickSfx()
	RestartRunRemote:FireServer()
end)

-- PAID CONTINUE: the server prompts the Developer Product purchase and
-- grants it in ProcessReceipt; the next state push takes us back to play.
-- No new top-level locals here: this script's main chunk is at Luau's
-- 200-local limit.
GameOverPanel.continueButton.MouseButton1Click:Connect(function()
	SoundModule.playClickSfx()
	remotes:WaitForChild("RequestContinue"):FireServer()
end)

-- SERVER-REPLY TIMEOUT: menu buttons that need the server go inactive until a
-- StateUpdated arrives; after 5s with no reply they show a message and re-enable.
do
	local REPLY_TIMEOUT = 5
	local stateCount = 0
	StateUpdatedRemote.OnClientEvent:Connect(function()
		stateCount += 1
	end)
	local function guard(button, needsFreshState)
		button.MouseButton1Click:Connect(function()
			if not button.Active then
				return
			end
			if not needsFreshState and latestState ~= nil then
				return -- already have server data, nothing to wait for
			end
			local startCount = stateCount
			button.Active = false
			task.delay(REPLY_TIMEOUT, function()
				button.Active = true
				if stateCount == startCount then
					showWarning("The tavern server isn't answering yet. Please try again in a moment.")
				end
			end)
			-- Re-enable early as soon as the reply lands.
			task.spawn(function()
				local t = 0
				while t < REPLY_TIMEOUT and stateCount == startCount do
					t += 0.1
					task.wait(0.1)
				end
				button.Active = true
			end)
		end)
	end
	guard(MenuScreen.menuPlayButton, false)
	guard(MenuScreen.menuJourneyButton, false)
	guard(MenuScreen.menuDailyChallengeButton, true)
	guard(MenuScreen.menuWeeklyChallengeButton, true)
end

StateUpdatedRemote.OnClientEvent:Connect(function(state)
	require(script.ClientSettings).loadFromServer(state.settings)
	if state.onboardingHint then
		-- After the score reveal, which would otherwise cover the banner.
		local hint = state.onboardingHint
		task.delay(4.5, function()
			showWarning(hint)
		end)
	end
	render(state)
end)

do -- STATE RESYNC: the push sent at join can land before this listener exists, which left an empty table behind Play.
	-- Ask once now, and again every 2 s until a state has arrived (the server answers with the current table).
	local request = remotes:WaitForChild("RequestState")
	task.spawn(function()
		for _ = 1, 8 do
			if latestState ~= nil then return end
			request:FireServer()
			task.wait(2)
		end
	end)
end
do -- Studio trace: Play pressed but the run never showed (prints the open popup stack so the blocker can be named)
	MenuScreen.menuPlayButton.MouseButton1Click:Connect(function()
		task.delay(2, function()
			if latestState == nil then
				warn("[Play trace] no table state received 2 s after Play (asking the server again)")
				remotes:WaitForChild("RequestState"):FireServer()
				return
			end
			local gui = screenGui
			local choiceUp = gui:FindFirstChild("ChoiceBackdrop")
			if latestState.choice and choiceUp and not choiceUp.Visible and not MenuScreen.menuFrame.Visible then
				local open = {}
				for _, child in ipairs(gui:GetChildren()) do
					if child:IsA("GuiObject") and child.Visible and child.Name:sub(-8) == "Backdrop" then open[#open + 1] = child.Name end
				end
				warn("[Play trace] choice pending but not shown; open popups: " .. (#open > 0 and table.concat(open, ", ") or "none"))
				pcall(require(script.ChoicePanel).refresh)
			end
		end)
	end)
end
