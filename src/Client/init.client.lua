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
--[[
	Real asset IDs, picked from the batch Ahmed found. backgroundMusic default
	is just a placeholder pick (Ahmed said he wants a later feature letting
	players choose/upload their own background tracks, maybe gamepass-gated --
	that's a separate feature for later, this is just something to hear for now.

	Unused alternates from the same batch, in case you want to swap later:
	  Balatro-Shop-Buy:   rbxassetid://117518868636544
	  Sears-Washing-Machine-8 (click alt): rbxassetid://9118892323
	  Falling-Down (music alt):    rbxassetid://122884689708268
	  Celestial-Walk (music alt, has a loud sax -- Ahmed didn't like it): rbxassetid://1836047913
]]
local SOUND_IDS = {
	backgroundMusic = "rbxassetid://138172142909285", -- Retro-Impact-Zone (placeholder default, see above)
	cardToggle = "rbxassetid://9117308777",      -- Photo-Flapping-Handling-Movement-Rubbing-1-SFX
	playHand = "rbxassetid://9113727134",        -- Cash-Movement-2-SFX
	discard = "rbxassetid://9114035597",         -- Deck-Of-Cards-7-SFX
	buyPatron = "rbxassetid://128537772502751",  -- Buy
	roundReward = "rbxassetid://133292918309565", -- buy (alt) -- distinct "you got paid" cash sound for round-complete
	uiClick = "rbxassetid://9118728158",         -- Rotary-Switch-10-SFX
}

local backgroundMusic = Instance.new("Sound")
backgroundMusic.Name = "BackgroundMusic"
backgroundMusic.SoundId = SOUND_IDS.backgroundMusic
backgroundMusic.Looped = true
backgroundMusic.Parent = SoundService

-- FEATURE 3: cycle loud -> quiet -> muted, free for everyone (no paywall).
local VOLUME_STEPS = { 0.5, 0.2, 0 }
local VOLUME_ICONS = { "♪", "♩", "×" }
local volumeStepIndex = 1
backgroundMusic.Volume = VOLUME_STEPS[volumeStepIndex]

-- One persistent Sound instance per SFX, created ONCE here and reused for
-- every play, instead of Instance.new()'ing (and loading) a brand new Sound
-- every single click. That repeated create+load was the real source of the
-- "still delayed, not instant" symptom -- PreloadAsync warms the asset
-- cache, but a fresh Sound object still has to resolve/initialize against
-- that asset each time you make one, and that's what was costing the delay.
local sfxPool = {} -- soundId -> persistent Sound instance
for _, id in pairs(SOUND_IDS) do
	if id and id ~= "rbxassetid://0" and not sfxPool[id] then
		local pooled = Instance.new("Sound")
		pooled.SoundId = id
		pooled.Parent = SoundService
		sfxPool[id] = pooled
	end
end

-- Preload every pooled Sound up front so the FIRST play doesn't have to
-- wait on streaming it from the CDN. Wrapped in task.spawn so it can't
-- block the rest of the UI from building while it loads.
task.spawn(function()
	local ContentProvider = game:GetService("ContentProvider")
	local toPreload = {}
	for _, pooled in pairs(sfxPool) do
		table.insert(toPreload, pooled)
	end
	if #toPreload > 0 then
		pcall(function()
			ContentProvider:PreloadAsync(toPreload)
		end)
	end
end)

-- maxLength (optional): cuts the sound off after that many seconds instead
-- of letting it play out fully -- some of the free SFX clips (card
-- handling, etc.) have a longer tail than you want for a quick UI moment.
-- The "StopToken" attribute (not a Lua local -- see the LOCAL VARIABLE
-- BUDGET note up top) guards the delayed Stop() against a newer overlapping
-- play of the SAME pooled sound, so rapid-fire clicks can't have an old
-- click's delayed Stop() cut off a brand new click's playback early.
local function playSfx(soundId, volume, maxLength)
	if not soundId or soundId == "" or soundId == "rbxassetid://0" then
		return -- placeholder id, nothing to play yet
	end
	local sfx = sfxPool[soundId]
	if not sfx then
		-- Fallback for any id not in SOUND_IDS at load time -- shouldn't
		-- normally happen, but keeps this safe against future one-off calls.
		sfx = Instance.new("Sound")
		sfx.SoundId = soundId
		sfx.Parent = SoundService
		sfxPool[soundId] = sfx
	end
	sfx.Volume = volume or 0.6
	sfx.TimePosition = 0
	sfx:Play()
	if maxLength then
		local myToken = (sfx:GetAttribute("StopToken") or 0) + 1
		sfx:SetAttribute("StopToken", myToken)
		task.delay(maxLength, function()
			if sfx:GetAttribute("StopToken") == myToken then
				sfx:Stop()
			end
		end)
	end
end

-- SOUND_IDS.uiClick (Rotary-Switch-10-SFX) has two audible clicks baked
-- into the clip itself -- for a snappy UI button we only want the first
-- one, so every generic click plays through this instead of calling
-- playSfx(SOUND_IDS.uiClick, ...) directly.
-- 0.15s cut it off too close to the sound's own startup latency, so on some
-- clicks (e.g. the "not enough tips" error click) it ended up basically
-- inaudible -- 0.25s gives it more room to actually be heard before the cut.
local function playClickSfx(volume)
	playSfx(SOUND_IDS.uiClick, volume, 0.25)
end

-- ===== Tween helper =====

local function tweenTo(instance, properties, duration, style, direction)
	local tween = TweenService:Create(
		instance,
		TweenInfo.new(duration, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out),
		properties
	)
	tween:Play()
	return tween
end

-- ===== Visual polish helpers (rounded corners) =====
-- FEATURE 1 of the rebuild-from-known-good pass.
--
-- FOUND IT: an earlier version of this helper set also had an addGloss()
-- that layered a near-white UIGradient on top of buttons/cards using a
-- Transparency sequence of 0.75 -> 0.9 -> 1.0 to fake a subtle highlight.
-- In Roblox, UIGradient.Transparency does NOT add a highlight on top of the
-- object's own color -- it OVERRIDES how see-through the object is at each
-- point. A sequence that's 75-100% transparent across almost the whole
-- object means you're mostly looking straight through the button/card to
-- whatever's behind it (the dark table background), not seeing a gloss at
-- all. That's the actual cause of the "everything looks near-black" bug
-- this whole project has been chasing. Leaving addGloss out entirely here;
-- rounded corners alone are zero-risk since they don't touch color or
-- transparency.

local function roundCorner(instance, radius)
	if instance:FindFirstChildOfClass("UICorner") then
		return
	end
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius or 10)
	corner.Parent = instance
end

local function polishButton(instance, radius)
	roundCorner(instance, radius or 10)
end

local function polishPanel(instance, radius)
	roundCorner(instance, radius or 16)
end

-- FEATURE 3: a soft drop shadow behind a panel -- a plain, offset,
-- fixed-transparency black Frame placed just behind it. Unlike addGloss,
-- this uses ordinary BackgroundTransparency (0.55, constant, not a
-- gradient), which blends normally -- it can only ever darken the thin
-- offset border area behind a panel, never the panel's own content.
local function addSoftShadow(panel, radius)
	local shadow = Instance.new("Frame")
	shadow.Name = "Shadow"
	shadow.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	shadow.BackgroundTransparency = 0.55
	shadow.Size = UDim2.new(1, 14, 1, 14)
	shadow.Position = UDim2.new(0, -7, 0, 4)
	shadow.BorderSizePixel = 0
	shadow.ZIndex = math.max(0, panel.ZIndex - 1)
	shadow.Parent = panel.Parent
	roundCorner(shadow, radius or 18)
	return shadow
end

-- ===== Reusable small UI helper: stepper row =====
-- Used by the Settings overlay. Roblox has no built-in drag-slider widget,
-- so this is a simple "- value +" stepper instead -- far less to get wrong
-- than hand-rolled drag physics, and just as usable.

local function makeStepperRow(parent, labelText, min, max, step, getValue, setValue, formatValue)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, 46)
	row.BackgroundTransparency = 1
	row.Parent = parent

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(0.5, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.Gotham
	label.TextSize = 15
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextColor3 = Color3.fromRGB(240, 230, 215)
	label.Text = labelText
	label.ZIndex = 21
	label.Parent = row

	local controlHolder = Instance.new("Frame")
	controlHolder.Size = UDim2.new(0.5, 0, 1, 0)
	controlHolder.Position = UDim2.new(0.5, 0, 0, 0)
	controlHolder.BackgroundTransparency = 1
	controlHolder.ZIndex = 21
	controlHolder.Parent = row

	local controlLayout = Instance.new("UIListLayout")
	controlLayout.FillDirection = Enum.FillDirection.Horizontal
	controlLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	controlLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	controlLayout.Padding = UDim.new(0, 10)
	controlLayout.Parent = controlHolder

	local minusButton = Instance.new("TextButton")
	minusButton.Size = UDim2.new(0, 34, 0, 34)
	minusButton.Font = Enum.Font.GothamBold
	minusButton.TextSize = 18
	minusButton.Text = "-"
	minusButton.BackgroundColor3 = Color3.fromRGB(60, 45, 32)
	minusButton.TextColor3 = Color3.fromRGB(250, 240, 220)
	minusButton.ZIndex = 21
	minusButton.Parent = controlHolder
	polishButton(minusButton, 8)

	local valueLabel = Instance.new("TextLabel")
	valueLabel.Size = UDim2.new(0, 60, 1, 0)
	valueLabel.BackgroundTransparency = 1
	valueLabel.Font = Enum.Font.GothamBold
	valueLabel.TextSize = 15
	valueLabel.TextColor3 = Color3.fromRGB(255, 214, 130)
	valueLabel.ZIndex = 21
	valueLabel.Parent = controlHolder

	local plusButton = Instance.new("TextButton")
	plusButton.Size = UDim2.new(0, 34, 0, 34)
	plusButton.Font = Enum.Font.GothamBold
	plusButton.TextSize = 18
	plusButton.Text = "+"
	plusButton.BackgroundColor3 = Color3.fromRGB(60, 45, 32)
	plusButton.TextColor3 = Color3.fromRGB(250, 240, 220)
	plusButton.ZIndex = 21
	plusButton.Parent = controlHolder
	polishButton(plusButton, 8)

	local function refresh()
		local value = getValue()
		valueLabel.Text = formatValue and formatValue(value) or tostring(value)
	end

	minusButton.MouseButton1Click:Connect(function()
		playClickSfx(0.35)
		setValue(math.max(min, getValue() - step))
		refresh()
	end)
	plusButton.MouseButton1Click:Connect(function()
		playClickSfx(0.35)
		setValue(math.min(max, getValue() + step))
		refresh()
	end)

	refresh()
	return refresh
end

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
-- LAYOUT FEATURE 1: replaces the old full-width top status bar, which had
-- started colliding with the top-right corner icon buttons as more got
-- added (a real bug -- the "Hands" label was getting cut off). Balatro
-- keeps this info in a dedicated left-side column instead of a top bar, so
-- this moves the same data there and leaves the whole top edge free for
-- the corner icon buttons with no shared space to collide over.

local SIDEBAR_WIDTH = 240

local sidebar = Instance.new("Frame")
sidebar.Name = "Sidebar"
sidebar.Size = UDim2.new(0, SIDEBAR_WIDTH, 1, 0)
sidebar.BackgroundColor3 = Color3.fromRGB(40, 30, 22)
sidebar.BorderSizePixel = 0
sidebar.ZIndex = 2
sidebar.Parent = root

local sidebarPadding = Instance.new("UIPadding")
-- 76px, not 16 -- Roblox's own top-left system UI (menu/chat/voice icons)
-- lives in roughly that space and was overlapping the "Round" box's text.
sidebarPadding.PaddingTop = UDim.new(0, 76)
sidebarPadding.PaddingLeft = UDim.new(0, 12)
sidebarPadding.PaddingRight = UDim.new(0, 12)
sidebarPadding.Parent = sidebar

local sidebarLayout = Instance.new("UIListLayout")
sidebarLayout.FillDirection = Enum.FillDirection.Vertical
sidebarLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
sidebarLayout.Padding = UDim.new(0, 10)
sidebarLayout.Parent = sidebar

local function makeSidebarBox(height)
	local box = Instance.new("Frame")
	box.Size = UDim2.new(1, 0, 0, height or 46)
	box.BackgroundColor3 = Color3.fromRGB(60, 45, 32)
	box.ZIndex = 2
	box.Parent = sidebar
	polishPanel(box, 10)
	return box
end

local function makeSidebarLabel(parent, textSize, color)
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = textSize or 16
	label.TextColor3 = color or Color3.fromRGB(240, 220, 190)
	label.TextWrapped = true
	label.Text = ""
	label.ZIndex = 2
	label.Parent = parent
	return label
end

local nightRoundBox = makeSidebarBox(40)
local nightRoundLabel = makeSidebarLabel(nightRoundBox, 16)

-- LAYOUT FEATURE 2: blind/round name + ability (mirrors the existing
-- bossBanner content, just always-visible in the sidebar instead of a
-- banner that only appears mid-round) and the target score + tip reward
-- for clearing it, computed the same way the server does (see RunState.lua
-- playHand: tipsPerRoundWin, doubled on a Boss Round) so it never drifts
-- out of sync with the actual payout.
local blindInfoBox = makeSidebarBox(56)
local blindInfoLabel = makeSidebarLabel(blindInfoBox, 13)
blindInfoLabel.TextWrapped = true
blindInfoLabel.TextYAlignment = Enum.TextYAlignment.Top

local scoreBox = makeSidebarBox(66)
local scoreLabel = makeSidebarLabel(scoreBox, 16, Color3.fromRGB(255, 214, 130))

local tipsBox = makeSidebarBox(40)
local tipsLabel = makeSidebarLabel(tipsBox, 16)

local handsDiscardsBox = makeSidebarBox(40)
local handsDiscardsLabel = makeSidebarLabel(handsDiscardsBox, 15)

-- LAYOUT FEATURE 5: Patron slot icons, mirroring Balatro's persistent
-- Joker-slot row -- shows how many Patrons you've picked up this run at a
-- glance, without opening the Collection Gallery. This game has no hard
-- cap on Patrons owned (unlike Balatro's Joker slots), so this shows
-- owned-out-of-total-in-the-game rather than a hard capacity.
local patronsBox = makeSidebarBox(58)

local patronsHeader = Instance.new("TextLabel")
patronsHeader.Size = UDim2.new(0.6, 0, 0, 16)
patronsHeader.Position = UDim2.new(0, 0, 0, 4)
patronsHeader.BackgroundTransparency = 1
patronsHeader.Font = Enum.Font.GothamBold
patronsHeader.TextSize = 12
patronsHeader.TextColor3 = Color3.fromRGB(200, 185, 165)
patronsHeader.TextXAlignment = Enum.TextXAlignment.Left
patronsHeader.Text = "Patrons"
patronsHeader.ZIndex = 2
patronsHeader.Parent = patronsBox

local patronsCountLabel = Instance.new("TextLabel")
patronsCountLabel.Size = UDim2.new(0.4, 0, 0, 16)
patronsCountLabel.Position = UDim2.new(0.6, 0, 0, 4)
patronsCountLabel.BackgroundTransparency = 1
patronsCountLabel.Font = Enum.Font.GothamBold
patronsCountLabel.TextSize = 12
patronsCountLabel.TextColor3 = Color3.fromRGB(255, 214, 130)
patronsCountLabel.TextXAlignment = Enum.TextXAlignment.Right
patronsCountLabel.Text = ""
patronsCountLabel.ZIndex = 2
patronsCountLabel.Parent = patronsBox

local patronsSlotRow = Instance.new("Frame")
patronsSlotRow.Size = UDim2.new(1, 0, 0, 30)
patronsSlotRow.Position = UDim2.new(0, 0, 0, 24)
patronsSlotRow.BackgroundTransparency = 1
patronsSlotRow.ZIndex = 2
patronsSlotRow.Parent = patronsBox

local patronsSlotLayout = Instance.new("UIListLayout")
patronsSlotLayout.FillDirection = Enum.FillDirection.Horizontal
patronsSlotLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
patronsSlotLayout.Padding = UDim.new(0, 6)
patronsSlotLayout.Parent = patronsSlotRow

-- Built once, refreshed in render() below each time state.ownedPatrons
-- changes. Capped at MAX_SIDEBAR_PATRON_SLOTS regardless of how big the
-- Patron catalog grows -- this is a quick-glance strip, not the full
-- browser (that's the Shop's "My Patrons" tab / Collection Gallery), and
-- a catalog of 50+ would otherwise overflow the sidebar entirely. The
-- exact "X / Y owned" count (patronsCountLabel above) is always accurate
-- even when the icon row itself is truncated.
local MAX_SIDEBAR_PATRON_SLOTS = 14
local patronSlots = {}
for i = 1, math.min(MAX_SIDEBAR_PATRON_SLOTS, #Patrons.Definitions) do
	local slot = Instance.new("Frame")
	slot.Size = UDim2.new(0, 30, 0, 30)
	slot.BackgroundColor3 = Color3.fromRGB(45, 40, 38)
	slot.LayoutOrder = i
	slot.ZIndex = 2
	slot.Parent = patronsSlotRow
	roundCorner(slot, 6)

	local slotLabel = Instance.new("TextLabel")
	slotLabel.Size = UDim2.fromScale(1, 1)
	slotLabel.BackgroundTransparency = 1
	slotLabel.Font = Enum.Font.GothamBold
	slotLabel.TextSize = 14
	slotLabel.TextColor3 = Color3.fromRGB(140, 135, 130)
	slotLabel.Text = "?"
	slotLabel.ZIndex = 2
	slotLabel.Parent = slot

	patronSlots[i] = { frame = slot, label = slotLabel }
end

-- LAYOUT FEATURE 6: live chips x mult preview for the currently-selected
-- cards, mirroring Balatro's running score readout. Computed with the same
-- HandEvaluator/Scoring modules the server uses (already required above
-- for Feature 5's worked examples), so the preview can't drift out of sync
-- with the real payout -- see refreshScorePreview() further down, which
-- wires this up once `selected`/`latestState` exist.
local scorePreviewBox = makeSidebarBox(50)
local scorePreviewLabel = makeSidebarLabel(scorePreviewBox, 15, Color3.fromRGB(190, 215, 255))

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

-- Sidebar Patron slot tooltips: slot i always represents
-- Patrons.Definitions[i] for its whole lifetime (see the comment on the
-- patronSlots loop above), so each slot's Patron identity is fixed even
-- though whether it's OWNED changes as you buy/discard -- use a function
-- (not a plain string) so the tooltip re-checks ownership fresh every
-- time you hover, via latestState, rather than freezing it at load time.
for i, patron in ipairs(Patrons.Definitions) do
	local slot = patronSlots[i]
	if slot then
		addTooltip(slot.frame, function()
			local owned = false
			if latestState then
				for _, owned_patron in ipairs(latestState.ownedPatrons or {}) do
					if owned_patron.id == patron.id then
						owned = true
						break
					end
				end
			end
			if owned then
				return string.format("%s\n%s", patron.name, patron.description)
			end
			return "??? -- not yet unlocked"
		end)
	end
end

-- ----- Message banner (hand result / round result) -----

local messageLabel = Instance.new("TextLabel")
messageLabel.Name = "Message"
messageLabel.Size = UDim2.new(1, -(SIDEBAR_WIDTH + 40), 0, 30)
messageLabel.Position = UDim2.new(0, SIDEBAR_WIDTH + 20, 0, 20)
messageLabel.BackgroundTransparency = 1
messageLabel.Font = Enum.Font.Gotham
messageLabel.TextSize = 16
messageLabel.TextColor3 = Color3.fromRGB(255, 214, 130)
messageLabel.Text = ""
messageLabel.Parent = root

-- Every warning shown through this ("Not enough tips", "Select 1-5 cards...")
-- used to just sit on screen forever once set. This clears it back to ""
-- after a few seconds. The "MessageToken" attribute (not a new top-level
-- local -- see LOCAL VARIABLE BUDGET above) guards against a newer message
-- getting wiped early by an older message's stale clear-timer.
local function showWarning(text)
	messageLabel.Text = text
	local myToken = (messageLabel:GetAttribute("MessageToken") or 0) + 1
	messageLabel:SetAttribute("MessageToken", myToken)
	task.delay(3, function()
		if messageLabel:GetAttribute("MessageToken") == myToken then
			messageLabel.Text = ""
		end
	end)
end

-- FEATURE 9: a banner announcing this round's Boss modifier, if any.
local bossBanner = Instance.new("Frame")
bossBanner.Name = "BossBanner"
bossBanner.Size = UDim2.new(1, -(SIDEBAR_WIDTH + 40), 0, 40)
bossBanner.Position = UDim2.new(0, SIDEBAR_WIDTH + 20, 0, 56)
bossBanner.BackgroundColor3 = Color3.fromRGB(90, 40, 40)
bossBanner.Visible = false
bossBanner.ZIndex = 3
bossBanner.Parent = root
polishPanel(bossBanner, 10)

local bossBannerLabel = Instance.new("TextLabel")
bossBannerLabel.Size = UDim2.fromScale(1, 1)
bossBannerLabel.BackgroundTransparency = 1
bossBannerLabel.Font = Enum.Font.GothamBold
bossBannerLabel.TextSize = 15
bossBannerLabel.TextColor3 = Color3.fromRGB(255, 225, 210)
bossBannerLabel.Text = ""
bossBannerLabel.ZIndex = 3
bossBannerLabel.Parent = bossBanner

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

-- ----- Deck-remaining widget, bottom-right -----
-- LAYOUT FEATURE 3: always-visible "how many cards are left" readout with a
-- card-back icon, instead of that info only being reachable through the
-- Deck Tracker overlay. Parented under `root` (not screenGui directly), so
-- its addSoftShadow correctly cascades hidden/visible with the menu <->
-- gameplay toggle -- see the addSoftShadow note on the Unlock popup for why
-- that parenting choice matters.

-- Wrapped in do...end per the LOCAL VARIABLE BUDGET note up top --
-- deckCountLabel and deckWidgetButton are the only pieces render()/the
-- click handler further down need to reach later, so they're
-- forward-declared and assigned (not re-`local`-declared) inside the block.
local deckCountLabel
local deckWidgetButton
do

local deckWidget = Instance.new("Frame")
deckWidget.Name = "DeckWidget"
deckWidget.AnchorPoint = Vector2.new(1, 1)
deckWidget.Position = UDim2.new(1, -20, 1, -70)
deckWidget.Size = UDim2.new(0, 74, 0, 118)
deckWidget.BackgroundTransparency = 1
deckWidget.ZIndex = 2
deckWidget.Parent = root

-- The deck widget itself IS the Deck Tracker entry point now (no separate
-- corner button) -- a transparent click-catcher over the whole widget, so
-- clicking the card-back icon or the count label both open the tracker.
-- Its click handler is wired inside Client/DeckTracker.lua, which takes
-- this button as a dep (see the require(script.DeckTracker) call below).
deckWidgetButton = Instance.new("TextButton")
deckWidgetButton.Name = "ClickCatcher"
deckWidgetButton.Size = UDim2.fromScale(1, 1)
deckWidgetButton.BackgroundTransparency = 1
deckWidgetButton.Text = ""
deckWidgetButton.ZIndex = 3
deckWidgetButton.Parent = deckWidget
addTooltip(deckWidgetButton, "Deck Tracker -- click to see what's left in the deck")

local deckCardBack = Instance.new("Frame")
deckCardBack.Size = UDim2.new(1, 0, 0, 96)
deckCardBack.BackgroundColor3 = Color3.fromRGB(50, 70, 110)
deckCardBack.ZIndex = 2
deckCardBack.Parent = deckWidget
polishPanel(deckCardBack, 8)
addSoftShadow(deckCardBack, 10)

local deckCardBackIcon = Instance.new("TextLabel")
deckCardBackIcon.Size = UDim2.fromScale(1, 1)
deckCardBackIcon.BackgroundTransparency = 1
deckCardBackIcon.Font = Enum.Font.GothamBold
deckCardBackIcon.TextSize = 30
deckCardBackIcon.TextColor3 = Color3.fromRGB(220, 225, 240)
deckCardBackIcon.Text = "🂠"
deckCardBackIcon.ZIndex = 2
deckCardBackIcon.Parent = deckCardBack

deckCountLabel = Instance.new("TextLabel")
deckCountLabel.Size = UDim2.new(1, 0, 0, 20)
deckCountLabel.Position = UDim2.new(0, 0, 0, 98)
deckCountLabel.BackgroundTransparency = 1
deckCountLabel.Font = Enum.Font.GothamBold
deckCountLabel.TextSize = 14
deckCountLabel.TextColor3 = Color3.fromRGB(240, 230, 215)
deckCountLabel.Text = ""
deckCountLabel.ZIndex = 2
deckCountLabel.Parent = deckWidget

end -- do (Deck widget)

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

-- ----- Score popup: chips x mult animation on Play Hand -----
-- LAYOUT FEATURE 7: Balatro's signature score-pop. Parented to `root` (not
-- handFrame -- rebuildHand() destroys every Frame child of handFrame on
-- every render(), which would destroy this the instant a hand is played)
-- and centered on the full screen rather than the narrower play area, to
-- avoid hand-crafting sidebar/deck-widget-aware centering math for a
-- element that's only ever on screen for about a second.
--
-- Wrapped in do...end per the LOCAL VARIABLE BUDGET note above -- showScorePopup
-- is called from playButton's click handler far below, so it's forward-declared
-- and assigned inside the block (not `local function`) to survive past `end`.
local showScorePopup
do

local scorePopup = Instance.new("Frame")
scorePopup.Name = "ScorePopup"
scorePopup.Size = UDim2.new(0, 240, 0, 90)
scorePopup.AnchorPoint = Vector2.new(0.5, 1)
scorePopup.Position = UDim2.new(0.5, 0, 1, -240)
scorePopup.BackgroundTransparency = 1
scorePopup.Visible = false
scorePopup.ZIndex = 25
scorePopup.Parent = root

local scorePopupHandName = Instance.new("TextLabel")
scorePopupHandName.Size = UDim2.new(1, 0, 0, 24)
scorePopupHandName.BackgroundTransparency = 1
scorePopupHandName.Font = Enum.Font.GothamBold
scorePopupHandName.TextSize = 18
scorePopupHandName.TextColor3 = Color3.fromRGB(255, 230, 180)
scorePopupHandName.TextStrokeTransparency = 0.5
scorePopupHandName.Text = ""
scorePopupHandName.ZIndex = 25
scorePopupHandName.Parent = scorePopup

local scorePopupMath = Instance.new("TextLabel")
scorePopupMath.Size = UDim2.new(1, 0, 0, 50)
scorePopupMath.Position = UDim2.new(0, 0, 0, 26)
scorePopupMath.BackgroundTransparency = 1
scorePopupMath.Font = Enum.Font.GothamBold
scorePopupMath.TextSize = 36
scorePopupMath.TextColor3 = Color3.fromRGB(255, 255, 255)
scorePopupMath.TextStrokeTransparency = 0.4
scorePopupMath.Text = ""
scorePopupMath.ZIndex = 25
scorePopupMath.Parent = scorePopup

local scorePopupScale = Instance.new("UIScale")
scorePopupScale.Scale = 1
scorePopupScale.Parent = scorePopup

local scorePopupToken = 0

-- preview: { name, chips, mult, score } from computeHandPreview(). Values
-- are computed at the moment Play Hand is clicked, using the exact same
-- scoring call RunState.playHand makes server-side, so this can never show
-- a number that doesn't match what you actually get paid.
showScorePopup = function(preview)
	scorePopupToken = scorePopupToken + 1
	local myToken = scorePopupToken

	scorePopupHandName.Text = preview.name
	scorePopupMath.Text = string.format("%d x %d", preview.chips, preview.mult)
	scorePopup.Visible = true
	scorePopupScale.Scale = 0.6
	tweenTo(scorePopupScale, { Scale = 1.15 }, 0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

	task.delay(0.18, function()
		if scorePopupToken == myToken then
			tweenTo(scorePopupScale, { Scale = 1 }, 0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		end
	end)

	task.delay(1.1, function()
		if scorePopupToken == myToken then
			scorePopup.Visible = false
		end
	end)
end

end -- do (Score popup)

-- ----- Confirm dialog (generic, reusable) -----
-- A yes/no modal for anything destructive/irreversible -- right now just
-- "discard this Patron?", but written generically so future confirmations
-- (selling a special card, resetting something) can reuse it instead of
-- each building their own popup.

local showConfirmDialog

do
	local confirmBackdrop = Instance.new("Frame")
	confirmBackdrop.Name = "ConfirmBackdrop"
	confirmBackdrop.Size = UDim2.fromScale(1, 1)
	confirmBackdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	confirmBackdrop.BackgroundTransparency = 0.35
	confirmBackdrop.Visible = false
	confirmBackdrop.ZIndex = 35
	confirmBackdrop.Parent = screenGui

	local confirmPanel = Instance.new("Frame")
	confirmPanel.Size = UDim2.new(0, 360, 0, 170)
	confirmPanel.Position = UDim2.fromScale(0.5, 0.5)
	confirmPanel.AnchorPoint = Vector2.new(0.5, 0.5)
	confirmPanel.BackgroundColor3 = Color3.fromRGB(40, 30, 22)
	confirmPanel.ZIndex = 35
	confirmPanel.Parent = confirmBackdrop
	polishPanel(confirmPanel, 14)
	addSoftShadow(confirmPanel, 16)

	local confirmMessageLabel = Instance.new("TextLabel")
	confirmMessageLabel.Size = UDim2.new(1, -30, 0, 90)
	confirmMessageLabel.Position = UDim2.new(0, 15, 0, 16)
	confirmMessageLabel.BackgroundTransparency = 1
	confirmMessageLabel.Font = Enum.Font.Gotham
	confirmMessageLabel.TextSize = 15
	confirmMessageLabel.TextWrapped = true
	confirmMessageLabel.TextColor3 = Color3.fromRGB(250, 240, 220)
	confirmMessageLabel.Text = ""
	confirmMessageLabel.ZIndex = 35
	confirmMessageLabel.Parent = confirmPanel

	local confirmYesButton = Instance.new("TextButton")
	confirmYesButton.Size = UDim2.new(0, 140, 0, 40)
	confirmYesButton.Position = UDim2.new(0, 20, 1, -55)
	confirmYesButton.Font = Enum.Font.GothamBold
	confirmYesButton.TextSize = 15
	confirmYesButton.Text = "Yes, discard it"
	confirmYesButton.BackgroundColor3 = Color3.fromRGB(140, 50, 45)
	confirmYesButton.TextColor3 = Color3.fromRGB(250, 240, 220)
	confirmYesButton.ZIndex = 35
	confirmYesButton.Parent = confirmPanel
	polishButton(confirmYesButton, 10)

	local confirmNoButton = Instance.new("TextButton")
	confirmNoButton.Size = UDim2.new(0, 140, 0, 40)
	confirmNoButton.Position = UDim2.new(1, -160, 1, -55)
	confirmNoButton.Font = Enum.Font.GothamBold
	confirmNoButton.TextSize = 15
	confirmNoButton.Text = "Cancel"
	confirmNoButton.BackgroundColor3 = Color3.fromRGB(70, 55, 40)
	confirmNoButton.TextColor3 = Color3.fromRGB(250, 240, 220)
	confirmNoButton.ZIndex = 35
	confirmNoButton.Parent = confirmPanel
	polishButton(confirmNoButton, 10)

	-- Reassigned on every showConfirmDialog call; Yes just calls whatever's
	-- currently pending, so there's only ever one live confirmation at a time.
	local pendingConfirmAction = nil

	confirmYesButton.MouseButton1Click:Connect(function()
		playClickSfx()
		confirmBackdrop.Visible = false
		if pendingConfirmAction then
			pendingConfirmAction()
			pendingConfirmAction = nil
		end
	end)

	confirmNoButton.MouseButton1Click:Connect(function()
		playClickSfx()
		confirmBackdrop.Visible = false
		pendingConfirmAction = nil
	end)

	showConfirmDialog = function(message, onConfirm)
		confirmMessageLabel.Text = message
		pendingConfirmAction = onConfirm
		confirmBackdrop.Visible = true
	end
end -- do (Confirm dialog)

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
	BuyPatronRemote = BuyPatronRemote,
	SellPatronRemote = SellPatronRemote,
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

	-- LAYOUT FEATURE 5: fill in the Patron slot icons.
	do
		local ownedPatronIds = {}
		for _, patron in ipairs(state.ownedPatrons or {}) do
			ownedPatronIds[patron.id] = true
		end

		local ownedCount = 0
		for i, patron in ipairs(Patrons.Definitions) do
			local slot = patronSlots[i]
			if slot then
				local isOwned = ownedPatronIds[patron.id] == true
				if isOwned then
					ownedCount = ownedCount + 1
					slot.frame.BackgroundColor3 = Color3.fromRGB(90, 60, 30)
					slot.label.TextColor3 = Color3.fromRGB(250, 240, 220)
					slot.label.Text = patron.name:sub(1, 1)
				else
					slot.frame.BackgroundColor3 = Color3.fromRGB(45, 40, 38)
					slot.label.TextColor3 = Color3.fromRGB(140, 135, 130)
					slot.label.Text = "?"
				end
			end
		end
		patronsCountLabel.Text = string.format("%d/%d", ownedCount, #Patrons.Definitions)
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
		rebuildShop(state.shopOffers)
		rebuildMyPatronsTab(state.ownedPatrons)
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
