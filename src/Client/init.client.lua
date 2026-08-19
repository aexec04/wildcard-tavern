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
local deckTrackerButton = makeCornerButton("🂠", -310)
local settingsButton = makeCornerButton("⚙", -360)
local collectionButton = makeCornerButton("📔", -410)

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
	button.MouseEnter:Connect(function()
		tooltipLabel.Text = text
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
addTooltip(deckTrackerButton, "Deck Tracker -- see what's left in the deck", "left")
addTooltip(settingsButton, "Settings", "left")
addTooltip(collectionButton, "Collection -- Patrons & Themes you've unlocked", "left")

end -- Generic hover tooltip

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
-- deckCountLabel is the only piece render() needs to reach later, so it's
-- forward-declared and assigned (not re-`local`-declared) inside the block.
local deckCountLabel
do

local deckWidget = Instance.new("Frame")
deckWidget.Name = "DeckWidget"
deckWidget.AnchorPoint = Vector2.new(1, 1)
deckWidget.Position = UDim2.new(1, -20, 1, -70)
deckWidget.Size = UDim2.new(0, 74, 0, 118)
deckWidget.BackgroundTransparency = 1
deckWidget.ZIndex = 2
deckWidget.Parent = root

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
	-- Same SIDEBAR_WIDTH-aware sizing/position convention as messageLabel/
	-- bossBanner above, so the panel never sits under the fixed sidebar.
	shopFrame.Size = UDim2.new(1, -(SIDEBAR_WIDTH + 40), 0.86, 0)
	shopFrame.Position = UDim2.new(0, SIDEBAR_WIDTH + 20, 0.07, 0)
	shopFrame.BackgroundColor3 = Color3.fromRGB(40, 30, 22)
	shopFrame.Visible = false
	shopFrame.ZIndex = 5 -- sidebar is ZIndex 2; without this the sidebar wins the z-fight where they overlap
	shopFrame.Parent = root
	polishPanel(shopFrame, 16)
	addSoftShadow(shopFrame, 18)

	local shopTitle = Instance.new("TextLabel")
	shopTitle.Size = UDim2.new(1, 0, 0, 36)
	shopTitle.BackgroundTransparency = 1
	shopTitle.Font = Enum.Font.GothamBold
	shopTitle.TextSize = 22
	shopTitle.TextColor3 = Color3.fromRGB(250, 240, 220)
	shopTitle.Text = "The Bar -- spend your Tips"
	shopTitle.Parent = shopFrame

	local shopTabBar = Instance.new("Frame")
	shopTabBar.Size = UDim2.new(1, -20, 0, 36)
	shopTabBar.Position = UDim2.new(0, 10, 0, 40)
	shopTabBar.BackgroundTransparency = 1
	shopTabBar.Parent = shopFrame

	local shopTabBarLayout = Instance.new("UIListLayout")
	shopTabBarLayout.FillDirection = Enum.FillDirection.Horizontal
	shopTabBarLayout.Padding = UDim.new(0, 8)
	shopTabBarLayout.Parent = shopTabBar

	local shopContentArea = Instance.new("Frame")
	shopContentArea.Size = UDim2.new(1, -20, 1, -140)
	shopContentArea.Position = UDim2.new(0, 10, 0, 84)
	shopContentArea.BackgroundTransparency = 1
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
		tab.Parent = shopContentArea

		local emojiLabel = Instance.new("TextLabel")
		emojiLabel.Size = UDim2.new(1, 0, 0, 60)
		emojiLabel.Position = UDim2.new(0, 0, 0.3, 0)
		emojiLabel.BackgroundTransparency = 1
		emojiLabel.Font = Enum.Font.GothamBold
		emojiLabel.TextSize = 40
		emojiLabel.Text = emoji
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
	nextRoundButton.Parent = shopFrame
	polishButton(nextRoundButton, 10)
end -- do (Shop overlay)

-- ----- Game over overlay -----

local gameOverFrame = Instance.new("Frame")
gameOverFrame.Name = "GameOver"
gameOverFrame.Size = UDim2.fromScale(0.5, 0.3)
gameOverFrame.Position = UDim2.fromScale(0.25, 0.35)
gameOverFrame.BackgroundColor3 = Color3.fromRGB(40, 30, 22)
gameOverFrame.Visible = false
gameOverFrame.Parent = root
polishPanel(gameOverFrame, 16)
addSoftShadow(gameOverFrame, 18)

local gameOverLabel = Instance.new("TextLabel")
gameOverLabel.Size = UDim2.new(1, 0, 0, 60)
gameOverLabel.BackgroundTransparency = 1
gameOverLabel.Font = Enum.Font.GothamBold
gameOverLabel.TextSize = 22
gameOverLabel.TextColor3 = Color3.fromRGB(250, 240, 220)
gameOverLabel.Text = "Last call! Your run has ended."
gameOverLabel.Parent = gameOverFrame

local playAgainButton = Instance.new("TextButton")
playAgainButton.Size = UDim2.new(0, 200, 0, 40)
playAgainButton.Position = UDim2.new(0.5, -100, 1, -60)
playAgainButton.Font = Enum.Font.GothamBold
playAgainButton.TextSize = 18
playAgainButton.Text = "Play Again"
playAgainButton.BackgroundColor3 = Color3.fromRGB(90, 60, 30)
playAgainButton.TextColor3 = Color3.fromRGB(250, 240, 220)
playAgainButton.Parent = gameOverFrame
polishButton(playAgainButton, 10)

-- ===== Menu screen =====

local menuFrame = Instance.new("Frame")
menuFrame.Name = "MenuRoot"
menuFrame.Size = UDim2.fromScale(1, 1)
menuFrame.BackgroundColor3 = Color3.fromRGB(18, 14, 10)
menuFrame.BorderSizePixel = 0
menuFrame.ZIndex = 10
menuFrame.Parent = screenGui

local menuTitle = Instance.new("TextLabel")
menuTitle.Size = UDim2.new(1, 0, 0, 80)
menuTitle.Position = UDim2.fromScale(0, 0.3)
menuTitle.BackgroundTransparency = 1
menuTitle.Font = Enum.Font.GothamBold
menuTitle.TextSize = 48
menuTitle.TextColor3 = Color3.fromRGB(255, 214, 130)
menuTitle.Text = "Wildcard Tavern"
menuTitle.ZIndex = 10
menuTitle.Parent = menuFrame

local menuSubtitle = Instance.new("TextLabel")
menuSubtitle.Size = UDim2.new(1, 0, 0, 30)
menuSubtitle.Position = UDim2.fromScale(0, 0.42)
menuSubtitle.BackgroundTransparency = 1
menuSubtitle.Font = Enum.Font.Gotham
menuSubtitle.TextSize = 18
menuSubtitle.TextColor3 = Color3.fromRGB(200, 180, 160)
menuSubtitle.Text = "a poker-hand deckbuilder -- working title"
menuSubtitle.ZIndex = 10
menuSubtitle.Parent = menuFrame

local menuButtonHolder = Instance.new("Frame")
menuButtonHolder.Size = UDim2.new(0, 240, 0, 110)
menuButtonHolder.Position = UDim2.fromScale(0.5, 0.55)
menuButtonHolder.AnchorPoint = Vector2.new(0.5, 0)
menuButtonHolder.BackgroundTransparency = 1
menuButtonHolder.ZIndex = 10
menuButtonHolder.Parent = menuFrame

local menuButtonLayout = Instance.new("UIListLayout")
menuButtonLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
menuButtonLayout.Padding = UDim.new(0, 12)
menuButtonLayout.Parent = menuButtonHolder

local function makeMenuButton(text)
	local button = Instance.new("TextButton")
	button.Size = UDim2.new(0, 220, 0, 48)
	button.Font = Enum.Font.GothamBold
	button.TextSize = 20
	button.Text = text
	button.BackgroundColor3 = Color3.fromRGB(90, 60, 30)
	button.TextColor3 = Color3.fromRGB(250, 240, 220)
	button.ZIndex = 10
	button.Parent = menuButtonHolder
	polishButton(button, 12)
	return button
end

local menuPlayButton = makeMenuButton("Play")
local menuHowToPlayButton = makeMenuButton("How to Play")
local menuJourneyButton = makeMenuButton("Road Ahead")
local menuNewRunButton = makeMenuButton("New Run...")

-- ===== How to Play overlay (reachable from menu or in-game) =====
-- Ahmed: "no kid on roblox will want to read words upon words with barely
-- any visuals" -- replaced the old 9-line paragraph with a grid of icon +
-- short-caption tiles below, same idea as the worked scoring examples
-- (which were already visual and stay as-is).
--
-- Wrapped in do/end -- nothing in this whole overlay is referenced from
-- outside it (both buttons that open it are connected from inside), so
-- it's fully self-contained. See the local-variable-budget note near the
-- top of the file.
do

local howToPlayBackdrop = Instance.new("Frame")
howToPlayBackdrop.Name = "HowToPlayBackdrop"
howToPlayBackdrop.Size = UDim2.fromScale(1, 1)
howToPlayBackdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
howToPlayBackdrop.BackgroundTransparency = 0.4
howToPlayBackdrop.Visible = false
howToPlayBackdrop.ZIndex = 20
howToPlayBackdrop.Parent = screenGui

local howToPlayPanel = Instance.new("Frame")
howToPlayPanel.Size = UDim2.fromScale(0.6, 0.75)
howToPlayPanel.Position = UDim2.fromScale(0.2, 0.12)
howToPlayPanel.BackgroundColor3 = Color3.fromRGB(40, 30, 22)
howToPlayPanel.ZIndex = 21
howToPlayPanel.Parent = howToPlayBackdrop
polishPanel(howToPlayPanel, 16)
addSoftShadow(howToPlayPanel, 18)

local howToPlayTitle = Instance.new("TextLabel")
howToPlayTitle.Size = UDim2.new(1, 0, 0, 40)
howToPlayTitle.BackgroundTransparency = 1
howToPlayTitle.Font = Enum.Font.GothamBold
howToPlayTitle.TextSize = 22
howToPlayTitle.TextColor3 = Color3.fromRGB(250, 240, 220)
howToPlayTitle.Text = "How to Play"
howToPlayTitle.ZIndex = 21
howToPlayTitle.Parent = howToPlayPanel

-- FEATURE 5: worked examples, scrollable. Built from real Card tables and
-- run through the actual HandEvaluator + Scoring modules, so the numbers
-- shown are always exactly what you'd see in a real game.

local howToPlayScroll = Instance.new("ScrollingFrame")
howToPlayScroll.Size = UDim2.new(1, -30, 1, -100)
howToPlayScroll.Position = UDim2.new(0, 15, 0, 45)
howToPlayScroll.BackgroundTransparency = 1
howToPlayScroll.BorderSizePixel = 0
howToPlayScroll.ScrollBarThickness = 8
howToPlayScroll.CanvasSize = UDim2.new(0, 0, 0, 0) -- grown automatically below
howToPlayScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
howToPlayScroll.ZIndex = 21
howToPlayScroll.Parent = howToPlayPanel

local howToPlayLayout = Instance.new("UIListLayout")
howToPlayLayout.Padding = UDim.new(0, 14)
howToPlayLayout.Parent = howToPlayScroll

-- A grid of icon + short-caption tiles instead of a paragraph -- one glance
-- per rule, not a page of reading.
local HOW_TO_PLAY_STEPS = {
	{ icon = "👆", text = "Click cards to select up to 5" },
	{ icon = "▶️", text = "Play Hand to score your best poker hand" },
	{ icon = "🔄", text = "Discard to swap cards -- free, no hand cost" },
	{ icon = "🎯", text = "Reach the target score before hands run out" },
	{ icon = "🍺", text = "Win a round -- spend Tips on Patrons at the Bar" },
	{ icon = "🌙", text = "Survive as many Nights as you can!" },
}

local howToPlayStepsGrid = Instance.new("Frame")
-- AutomaticSize (not a hardcoded pixel height) so the grid always grows to
-- fit exactly however many rows the tiles need -- a fixed height here was
-- the bug: it was too short for 3 rows, so the bottom row spilled out and
-- covered "How scoring works" and the example hands right below it.
howToPlayStepsGrid.Size = UDim2.new(1, 0, 0, 0)
howToPlayStepsGrid.AutomaticSize = Enum.AutomaticSize.Y
howToPlayStepsGrid.BackgroundTransparency = 1
howToPlayStepsGrid.ZIndex = 21
howToPlayStepsGrid.LayoutOrder = 1
howToPlayStepsGrid.Parent = howToPlayScroll

local howToPlayGridLayout = Instance.new("UIGridLayout")
howToPlayGridLayout.CellSize = UDim2.new(1 / 3, -6, 0, 96)
howToPlayGridLayout.CellPadding = UDim2.new(0, 8, 0, 8)
howToPlayGridLayout.Parent = howToPlayStepsGrid

for stepIndex, step in ipairs(HOW_TO_PLAY_STEPS) do
	local tile = Instance.new("Frame")
	tile.BackgroundColor3 = Color3.fromRGB(60, 45, 32)
	tile.LayoutOrder = stepIndex
	tile.ZIndex = 21
	tile.Parent = howToPlayStepsGrid
	polishPanel(tile, 10)

	local iconLabel = Instance.new("TextLabel")
	iconLabel.Size = UDim2.new(1, 0, 0, 40)
	iconLabel.Position = UDim2.new(0, 0, 0, 8)
	iconLabel.BackgroundTransparency = 1
	iconLabel.Font = Enum.Font.GothamBold
	iconLabel.TextSize = 28
	iconLabel.Text = step.icon
	iconLabel.ZIndex = 21
	iconLabel.Parent = tile

	local captionLabel = Instance.new("TextLabel")
	captionLabel.Size = UDim2.new(1, -16, 0, 42)
	captionLabel.Position = UDim2.new(0, 8, 0, 50)
	captionLabel.BackgroundTransparency = 1
	captionLabel.Font = Enum.Font.Gotham
	captionLabel.TextSize = 13
	captionLabel.TextColor3 = Color3.fromRGB(235, 225, 210)
	captionLabel.TextWrapped = true
	captionLabel.Text = step.text
	captionLabel.ZIndex = 21
	captionLabel.Parent = tile
end

local howToPlayExamplesLabel = Instance.new("TextLabel")
howToPlayExamplesLabel.Size = UDim2.new(1, 0, 0, 24)
howToPlayExamplesLabel.BackgroundTransparency = 1
howToPlayExamplesLabel.Font = Enum.Font.GothamBold
howToPlayExamplesLabel.TextSize = 15
howToPlayExamplesLabel.TextColor3 = Color3.fromRGB(255, 214, 130)
howToPlayExamplesLabel.TextXAlignment = Enum.TextXAlignment.Left
howToPlayExamplesLabel.Text = "How scoring works -- every hand, weakest to strongest:"
howToPlayExamplesLabel.ZIndex = 21
howToPlayExamplesLabel.LayoutOrder = 2
howToPlayExamplesLabel.Parent = howToPlayScroll

-- Ahmed: "the Poker Hands [reference] has all ways to score points, why is
-- that not being visually shown in the how to play?" -- one worked example
-- per HandEvaluator.HandOrder entry now (was only 3 of 9), weakest to
-- strongest, same visual mini-card format as before.
local EXAMPLE_HANDS = {
	{ -- High Card
		{ rank = 2, suit = "Hearts" },
		{ rank = 5, suit = "Diamonds" },
		{ rank = 9, suit = "Clubs" },
		{ rank = 11, suit = "Spades" },
		{ rank = 13, suit = "Hearts" },
	},
	{ -- Pair
		{ rank = 7, suit = "Hearts" },
		{ rank = 7, suit = "Spades" },
	},
	{ -- Two Pair
		{ rank = 9, suit = "Diamonds" },
		{ rank = 9, suit = "Clubs" },
		{ rank = 2, suit = "Hearts" },
		{ rank = 2, suit = "Diamonds" },
	},
	{ -- Three of a Kind
		{ rank = 5, suit = "Spades" },
		{ rank = 5, suit = "Hearts" },
		{ rank = 5, suit = "Diamonds" },
	},
	{ -- Straight
		{ rank = 4, suit = "Hearts" },
		{ rank = 5, suit = "Diamonds" },
		{ rank = 6, suit = "Clubs" },
		{ rank = 7, suit = "Spades" },
		{ rank = 8, suit = "Hearts" },
	},
	{ -- Flush
		{ rank = 2, suit = "Hearts" },
		{ rank = 5, suit = "Hearts" },
		{ rank = 9, suit = "Hearts" },
		{ rank = 11, suit = "Hearts" },
		{ rank = 13, suit = "Hearts" },
	},
	{ -- Full House
		{ rank = 9, suit = "Diamonds" },
		{ rank = 9, suit = "Clubs" },
		{ rank = 9, suit = "Spades" },
		{ rank = 2, suit = "Hearts" },
		{ rank = 2, suit = "Diamonds" },
	},
	{ -- Four of a Kind
		{ rank = 8, suit = "Hearts" },
		{ rank = 8, suit = "Diamonds" },
		{ rank = 8, suit = "Clubs" },
		{ rank = 8, suit = "Spades" },
	},
	{ -- Straight Flush
		{ rank = 4, suit = "Clubs" },
		{ rank = 5, suit = "Clubs" },
		{ rank = 6, suit = "Clubs" },
		{ rank = 7, suit = "Clubs" },
		{ rank = 8, suit = "Clubs" },
	},
}

local function makeMiniCard(card, parent, layoutOrder)
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(0, 34, 0, 46)
	label.BackgroundColor3 = Color3.fromRGB(250, 245, 235)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 13
	label.TextColor3 = RED_SUITS[card.suit] and Color3.fromRGB(180, 30, 30) or Color3.fromRGB(20, 20, 20)
	label.Text = string.format("%s\n%s", RANK_NAMES[card.rank] or tostring(card.rank), SUIT_SYMBOLS[card.suit] or "?")
	label.LayoutOrder = layoutOrder or 0
	label.ZIndex = 21
	label.Parent = parent
	roundCorner(label, 6)
	return label
end

for exampleIndex, cards in ipairs(EXAMPLE_HANDS) do
	local handResult = HandEvaluator.evaluate(cards)
	local score, chips, mult = Scoring.calculate(handResult, {}, {})

	local exampleRow = Instance.new("Frame")
	exampleRow.Size = UDim2.new(1, 0, 0, 70)
	exampleRow.BackgroundColor3 = Color3.fromRGB(60, 45, 32)
	exampleRow.ZIndex = 21
	exampleRow.LayoutOrder = 2 + exampleIndex
	exampleRow.Parent = howToPlayScroll
	polishPanel(exampleRow, 10)

	local cardsHolder = Instance.new("Frame")
	cardsHolder.Size = UDim2.new(0, 34 * #cards + 6 * (#cards - 1) + 16, 1, 0)
	cardsHolder.Position = UDim2.new(0, 10, 0, 0)
	cardsHolder.BackgroundTransparency = 1
	cardsHolder.ZIndex = 21
	cardsHolder.Parent = exampleRow

	local cardsLayout = Instance.new("UIListLayout")
	cardsLayout.FillDirection = Enum.FillDirection.Horizontal
	cardsLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	cardsLayout.Padding = UDim.new(0, 6)
	cardsLayout.Parent = cardsHolder

	for cardIndex, card in ipairs(cards) do
		makeMiniCard(card, cardsHolder, cardIndex)
	end

	local resultLabel = Instance.new("TextLabel")
	resultLabel.Size = UDim2.new(1, -(34 * #cards + 6 * (#cards - 1) + 30), 1, 0)
	resultLabel.Position = UDim2.new(0, 34 * #cards + 6 * (#cards - 1) + 20, 0, 0)
	resultLabel.BackgroundTransparency = 1
	resultLabel.Font = Enum.Font.Gotham
	resultLabel.TextSize = 14
	resultLabel.TextWrapped = true
	resultLabel.TextXAlignment = Enum.TextXAlignment.Left
	resultLabel.TextColor3 = Color3.fromRGB(255, 214, 130)
	resultLabel.ZIndex = 21
	resultLabel.Text = string.format(
		"%s\n%d chips x %d mult = %d points",
		handResult.name, chips, mult, score
	)
	resultLabel.Parent = exampleRow
end

local howToPlayCloseButton = Instance.new("TextButton")
howToPlayCloseButton.Size = UDim2.new(0, 140, 0, 40)
howToPlayCloseButton.Position = UDim2.new(0.5, -70, 1, -50)
howToPlayCloseButton.Font = Enum.Font.GothamBold
howToPlayCloseButton.TextSize = 16
howToPlayCloseButton.Text = "Got it"
howToPlayCloseButton.BackgroundColor3 = Color3.fromRGB(90, 60, 30)
howToPlayCloseButton.TextColor3 = Color3.fromRGB(250, 240, 220)
howToPlayCloseButton.ZIndex = 21
howToPlayCloseButton.Parent = howToPlayPanel
polishButton(howToPlayCloseButton, 10)

howToPlayCloseButton.MouseButton1Click:Connect(function()
	playClickSfx()
	howToPlayBackdrop.Visible = false
end)

local function openHowToPlay()
	playClickSfx()
	howToPlayBackdrop.Visible = true
end

menuHowToPlayButton.MouseButton1Click:Connect(openHowToPlay)
helpButton.MouseButton1Click:Connect(openHowToPlay)

end -- How to Play overlay

-- ===== Themes (cosmetics) overlay =====
-- Purely visual -- spend Tips on table/card color palettes. No gameplay
-- effect. Buyable/equippable any time, not just during the shop phase.

local themesBackdrop = Instance.new("Frame")
themesBackdrop.Name = "ThemesBackdrop"
themesBackdrop.Size = UDim2.fromScale(1, 1)
themesBackdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
themesBackdrop.BackgroundTransparency = 0.4
themesBackdrop.Visible = false
themesBackdrop.ZIndex = 20
themesBackdrop.Parent = screenGui

local themesPanel = Instance.new("Frame")
themesPanel.Size = UDim2.fromScale(0.55, 0.6)
themesPanel.Position = UDim2.fromScale(0.225, 0.2)
themesPanel.BackgroundColor3 = Color3.fromRGB(40, 30, 22)
themesPanel.ZIndex = 21
themesPanel.Parent = themesBackdrop
polishPanel(themesPanel, 16)
addSoftShadow(themesPanel, 18)

local themesTitle = Instance.new("TextLabel")
themesTitle.Size = UDim2.new(1, 0, 0, 40)
themesTitle.BackgroundTransparency = 1
themesTitle.Font = Enum.Font.GothamBold
themesTitle.TextSize = 22
themesTitle.TextColor3 = Color3.fromRGB(250, 240, 220)
themesTitle.Text = "Themes -- cosmetic only, spend Tips"
themesTitle.ZIndex = 21
themesTitle.Parent = themesPanel

local themesListFrame = Instance.new("Frame")
themesListFrame.Size = UDim2.new(1, -20, 1, -100)
themesListFrame.Position = UDim2.new(0, 10, 0, 45)
themesListFrame.BackgroundTransparency = 1
themesListFrame.ZIndex = 21
themesListFrame.Parent = themesPanel

local themesListLayout = Instance.new("UIListLayout")
themesListLayout.Padding = UDim.new(0, 8)
themesListLayout.Parent = themesListFrame

local themesCloseButton = Instance.new("TextButton")
themesCloseButton.Size = UDim2.new(0, 140, 0, 40)
themesCloseButton.Position = UDim2.new(0.5, -70, 1, -50)
themesCloseButton.Font = Enum.Font.GothamBold
themesCloseButton.TextSize = 16
themesCloseButton.Text = "Close"
themesCloseButton.BackgroundColor3 = Color3.fromRGB(90, 60, 30)
themesCloseButton.TextColor3 = Color3.fromRGB(250, 240, 220)
themesCloseButton.ZIndex = 21
themesCloseButton.Parent = themesPanel
polishButton(themesCloseButton, 10)

themesCloseButton.MouseButton1Click:Connect(function()
	playClickSfx()
	themesBackdrop.Visible = false
end)

-- Forward-declared: assigned further down once client-side state (like
-- latestState) exists. Lua closures capture the local by reference, so
-- this works as long as the assignment happens before it's ever called.
local refreshThemesList

themesButton.MouseButton1Click:Connect(function()
	playClickSfx()
	if refreshThemesList then
		refreshThemesList()
	end
	themesBackdrop.Visible = true
end)

-- ===== Road Ahead (journey/roadmap) overlay =====
-- LAYOUT FEATURE 9: Ahmed wanted his own creative spin here instead of
-- copying Balatro's plain list -- a 2D, Mario-map-style path where your
-- own Roblox avatar (real headshot thumbnail) stands on your current
-- stage and hops/walks to the next one when you win a round.
--
-- latestState is declared near the top of the file specifically so this
-- (and every overlay) can read it from inside a do/end block -- see that
-- comment. journeyBackdrop and refreshJourney are both forward-declared/
-- needed outside -- render() checks journeyBackdrop.Visible and calls
-- refreshJourney() to keep the map accurate while it's open across a round
-- change.
local journeyBackdrop
local refreshJourney

do

local PREVIEW_NIGHTS = 3 -- how many Nights ahead to show on the map
local ROUNDS_PER_NIGHT = 3
local NODE_SIZE = 64
local NIGHT_GAP_EXTRA = 60 -- extra width of the spacer between night clusters

journeyBackdrop = Instance.new("Frame")
journeyBackdrop.Name = "JourneyBackdrop"
journeyBackdrop.Size = UDim2.fromScale(1, 1)
journeyBackdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
journeyBackdrop.BackgroundTransparency = 0.4
journeyBackdrop.Visible = false
journeyBackdrop.ZIndex = 20
journeyBackdrop.Parent = screenGui

local journeyPanel = Instance.new("Frame")
journeyPanel.Size = UDim2.fromScale(0.7, 0.55)
journeyPanel.Position = UDim2.fromScale(0.15, 0.22)
journeyPanel.BackgroundColor3 = Color3.fromRGB(40, 30, 22)
journeyPanel.ZIndex = 21
journeyPanel.Parent = journeyBackdrop
polishPanel(journeyPanel, 16)
addSoftShadow(journeyPanel, 18)

local journeyTitle = Instance.new("TextLabel")
journeyTitle.Size = UDim2.new(1, 0, 0, 40)
journeyTitle.BackgroundTransparency = 1
journeyTitle.Font = Enum.Font.GothamBold
journeyTitle.TextSize = 22
journeyTitle.TextColor3 = Color3.fromRGB(250, 240, 220)
journeyTitle.Text = "The Road Ahead"
journeyTitle.ZIndex = 21
journeyTitle.Parent = journeyPanel

local journeySubtitle = Instance.new("TextLabel")
journeySubtitle.Size = UDim2.new(1, -30, 0, 24)
journeySubtitle.Position = UDim2.new(0, 15, 0, 38)
journeySubtitle.BackgroundTransparency = 1
journeySubtitle.Font = Enum.Font.Gotham
journeySubtitle.TextSize = 14
journeySubtitle.TextColor3 = Color3.fromRGB(220, 205, 185)
journeySubtitle.TextXAlignment = Enum.TextXAlignment.Left
journeySubtitle.Text = "Your table walks the road one Round at a time. 👑 = Boss Round."
journeySubtitle.ZIndex = 21
journeySubtitle.Parent = journeyPanel

-- Horizontal, scrollable map strip. Both the stage nodes AND the avatar
-- marker live directly in here (as siblings, not nested inside each
-- other) so they share one coordinate space -- the marker's X position can
-- just be read off a node's AbsolutePosition and it'll line up correctly,
-- including while scrolled.
local journeyMapScroll = Instance.new("ScrollingFrame")
journeyMapScroll.Size = UDim2.new(1, -20, 1, -160)
journeyMapScroll.Position = UDim2.new(0, 10, 0, 68)
journeyMapScroll.BackgroundTransparency = 1
journeyMapScroll.BorderSizePixel = 0
journeyMapScroll.ScrollBarThickness = 8
journeyMapScroll.ScrollingDirection = Enum.ScrollingDirection.X
journeyMapScroll.CanvasSize = UDim2.new(0, 0, 0, 0) -- grown automatically below
journeyMapScroll.AutomaticCanvasSize = Enum.AutomaticSize.X
journeyMapScroll.ZIndex = 21
-- ClipsDescendants intentionally left at its ScrollingFrame default (true):
-- this is a horizontally-scrolling strip, and the whole point of clipping
-- is that only the currently-scrolled-into-view slice of the (much wider)
-- node row shows. Turning it off -- tried briefly while chasing the avatar
-- visibility bug -- let the ENTIRE node row + path line render unclipped,
-- spilling out past the panel. The real avatar bug turned out to be the
-- currentTheme crash below, not clipping, so this stays at the default.
journeyMapScroll.Parent = journeyPanel

-- A thin path line behind the nodes, purely decorative -- gives the "walk
-- along a road" read even before the avatar marker is on top of it.
local journeyStagesHolder = Instance.new("Frame")
journeyStagesHolder.Size = UDim2.new(0, 0, 1, 0)
journeyStagesHolder.AutomaticSize = Enum.AutomaticSize.X
journeyStagesHolder.BackgroundTransparency = 1
journeyStagesHolder.ZIndex = 22
journeyStagesHolder.Parent = journeyMapScroll

-- A thin path line behind the nodes, purely decorative -- gives the "walk
-- along a road" read even before the avatar marker is on top of it. Parented
-- INSIDE journeyStagesHolder (not journeyMapScroll) and sized to 100% of it,
-- so it automatically spans exactly the row of nodes -- no matter how wide
-- that row ends up being -- instead of a hardcoded guess.
local journeyPathLine = Instance.new("Frame")
journeyPathLine.Size = UDim2.new(1, 0, 0, 6)
journeyPathLine.Position = UDim2.new(0, 0, 0.5, -3)
journeyPathLine.BackgroundColor3 = Color3.fromRGB(90, 70, 50)
journeyPathLine.BorderSizePixel = 0
journeyPathLine.ZIndex = 21
journeyPathLine.Parent = journeyStagesHolder
roundCorner(journeyPathLine, 3)

local journeyStagesLayout = Instance.new("UIListLayout")
journeyStagesLayout.FillDirection = Enum.FillDirection.Horizontal
journeyStagesLayout.VerticalAlignment = Enum.VerticalAlignment.Center
journeyStagesLayout.SortOrder = Enum.SortOrder.LayoutOrder
journeyStagesLayout.Padding = UDim.new(0, 30)
journeyStagesLayout.Parent = journeyStagesHolder
local JOURNEY_NODE_PADDING = 30 -- must match journeyStagesLayout.Padding above

-- The player's actual avatar, standing on the map -- fetched once
-- (yielding call, so it's off in a task.spawn) and applied whenever ready.
local journeyAvatarMarker = Instance.new("ImageLabel")
journeyAvatarMarker.Name = "AvatarMarker"
journeyAvatarMarker.Size = UDim2.new(0, 46, 0, 46)
journeyAvatarMarker.AnchorPoint = Vector2.new(0.5, 1)
journeyAvatarMarker.Position = UDim2.new(0, 0, 0.5, -NODE_SIZE / 2 - 8)
journeyAvatarMarker.BackgroundColor3 = Color3.fromRGB(250, 240, 220)
journeyAvatarMarker.Image = ""
journeyAvatarMarker.ZIndex = 24
journeyAvatarMarker.Parent = journeyMapScroll
roundCorner(journeyAvatarMarker, 23)

-- Fallback glyph: always visible until (if ever) the real avatar thumbnail
-- loads. Covers the case where GetUserThumbnailAsync is slow, fails, or
-- returns a placeholder (a known quirk of solo Play-testing in Studio) --
-- the marker should never just be an empty/invisible square.
local journeyAvatarFallback = Instance.new("TextLabel")
journeyAvatarFallback.Size = UDim2.fromScale(1, 1)
journeyAvatarFallback.BackgroundTransparency = 1
journeyAvatarFallback.Font = Enum.Font.GothamBold
journeyAvatarFallback.TextSize = 24
journeyAvatarFallback.Text = "🧑"
journeyAvatarFallback.ZIndex = 25
journeyAvatarFallback.Parent = journeyAvatarMarker

task.spawn(function()
	local ok, content = pcall(function()
		return Players:GetUserThumbnailAsync(player.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
	end)
	if ok and content and content ~= "" then
		journeyAvatarMarker.Image = content
		journeyAvatarFallback.Visible = false
	end
end)

-- (No continuous idle-bob animation -- it would fight with the walk/hop
-- tween below for control of the same Position property. The hop-on-walk
-- animation is enough life for now; a proper idle bob would need its own
-- separate UI element layered under a static-position parent to avoid
-- that conflict, which isn't worth the complexity yet.)

local journeyStageNodes = {} -- flat array, index 1..(PREVIEW_NIGHTS*ROUNDS_PER_NIGHT), in map order
local layoutOrderCounter = 0
-- xCursor tracks each node's left edge as we build the row, mirroring
-- exactly what journeyStagesLayout (a UIListLayout) will compute. We use
-- this instead of reading node.Position back after the fact -- reading a
-- UIListLayout-controlled Position depends on the layout engine having
-- already run a pass over this (currently invisible) overlay, which isn't
-- guaranteed the first time the map is opened. A precomputed value is
-- always correct, immediately.
local xCursor = 0

for night = 1, PREVIEW_NIGHTS do
	if night > 1 then
		local spacer = Instance.new("Frame")
		spacer.Size = UDim2.new(0, NIGHT_GAP_EXTRA, 1, 0)
		spacer.BackgroundTransparency = 1
		layoutOrderCounter = layoutOrderCounter + 1
		spacer.LayoutOrder = layoutOrderCounter
		spacer.Parent = journeyStagesHolder
		xCursor = xCursor + NIGHT_GAP_EXTRA + JOURNEY_NODE_PADDING
	end

	for round = 1, ROUNDS_PER_NIGHT do
		layoutOrderCounter = layoutOrderCounter + 1

		local node = Instance.new("Frame")
		node.Size = UDim2.new(0, NODE_SIZE, 0, NODE_SIZE)
		node.BackgroundColor3 = Color3.fromRGB(60, 45, 32)
		node.LayoutOrder = layoutOrderCounter
		node.ZIndex = 22
		node.Parent = journeyStagesHolder
		roundCorner(node, NODE_SIZE / 2)

		if night == 1 and round == 1 then
			-- Underneath everything else, so it doesn't shift layout order.
			local nightLabel = Instance.new("TextLabel")
			nightLabel.Size = UDim2.new(0, 90, 0, 20)
			nightLabel.Position = UDim2.new(0.5, -45, 0, -30)
			nightLabel.BackgroundTransparency = 1
			nightLabel.Font = Enum.Font.GothamBold
			nightLabel.TextSize = 13
			nightLabel.TextColor3 = Color3.fromRGB(220, 205, 185)
			nightLabel.Text = "Night 1"
			nightLabel.ZIndex = 22
			nightLabel.Parent = node
		end

		local roundLabel = Instance.new("TextLabel")
		roundLabel.Size = UDim2.fromScale(1, 0.55)
		roundLabel.Position = UDim2.fromScale(0, 0.02)
		roundLabel.BackgroundTransparency = 1
		roundLabel.Font = Enum.Font.GothamBold
		roundLabel.TextSize = 16
		roundLabel.TextColor3 = Color3.fromRGB(240, 230, 215)
		roundLabel.Text = string.format("R%d", round)
		roundLabel.ZIndex = 23
		roundLabel.Parent = node

		local scoreLabel = Instance.new("TextLabel")
		scoreLabel.Size = UDim2.fromScale(1, 0.4)
		scoreLabel.Position = UDim2.fromScale(0, 0.55)
		scoreLabel.BackgroundTransparency = 1
		scoreLabel.Font = Enum.Font.Gotham
		scoreLabel.TextSize = 11
		scoreLabel.TextColor3 = Color3.fromRGB(220, 210, 195)
		scoreLabel.Text = tostring(RunStateEngine.targetScoreFor(night, round))
		scoreLabel.ZIndex = 23
		scoreLabel.Parent = node

		table.insert(journeyStageNodes, {
			node = node,
			roundLabel = roundLabel,
			scoreLabel = scoreLabel,
			night = night,
			round = round,
			centerX = xCursor + NODE_SIZE / 2,
		})
		xCursor = xCursor + NODE_SIZE + JOURNEY_NODE_PADDING

		-- Night labels for nights 2/3 -- placed after node 1 of that night
		-- exists, same idea as Night 1's label above.
		if round == 1 and night > 1 then
			local nightLabel = Instance.new("TextLabel")
			nightLabel.Size = UDim2.new(0, 90, 0, 20)
			nightLabel.Position = UDim2.new(0.5, -45, 0, -30)
			nightLabel.BackgroundTransparency = 1
			nightLabel.Font = Enum.Font.GothamBold
			nightLabel.TextSize = 13
			nightLabel.TextColor3 = Color3.fromRGB(220, 205, 185)
			nightLabel.Text = string.format("Night %d", night)
			nightLabel.ZIndex = 22
			nightLabel.Parent = node
		end
	end
end

local journeyCloseButton = Instance.new("TextButton")
journeyCloseButton.Size = UDim2.new(0, 140, 0, 40)
journeyCloseButton.Position = UDim2.new(0.5, -70, 1, -50)
journeyCloseButton.Font = Enum.Font.GothamBold
journeyCloseButton.TextSize = 16
journeyCloseButton.Text = "Close"
journeyCloseButton.BackgroundColor3 = Color3.fromRGB(90, 60, 30)
journeyCloseButton.TextColor3 = Color3.fromRGB(250, 240, 220)
journeyCloseButton.ZIndex = 21
journeyCloseButton.Parent = journeyPanel
polishButton(journeyCloseButton, 12)

journeyCloseButton.MouseButton1Click:Connect(function()
	playClickSfx()
	journeyBackdrop.Visible = false
end)

-- lastJourneyStageKey: which stage the avatar was last shown on, so we only
-- play the walk animation when it actually CHANGES (not every time the
-- overlay happens to refresh while you're on the same stage).
local lastJourneyStageKey = nil

local function refreshJourneyImpl(animateWalk)
	local currentNight = (latestState and latestState.night) or 1
	local currentRound = (latestState and latestState.round) or 1

	local journeyDifficulty = DifficultyTiers.getById((latestState and latestState.difficultyId) or DifficultyTiers.DefaultId)
		or DifficultyTiers.getById(DifficultyTiers.DefaultId)
	local bossRoundsEnabled = journeyDifficulty.bossRoundsEnabled ~= false

	local targetNode = nil
	for _, entry in ipairs(journeyStageNodes) do
		local isPast = (entry.night < currentNight) or (entry.night == currentNight and entry.round < currentRound)
		local isCurrent = (entry.night == currentNight and entry.round == currentRound)
		local isBoss = bossRoundsEnabled and BossRounds.isBossRound(entry.round, ROUNDS_PER_NIGHT)

		entry.node.BackgroundColor3 = isCurrent and currentTheme.colors.cardSelected
			or (isPast and Color3.fromRGB(90, 130, 90) or (isBoss and Color3.fromRGB(90, 45, 45) or Color3.fromRGB(60, 45, 32)))
		local bossTag = isBoss and " 👑" or ""
		entry.roundLabel.Text = isPast and string.format("R%d ✓", entry.round) or string.format("R%d%s", entry.round, bossTag)

		if isCurrent then
			targetNode = entry
		end
	end

	if targetNode then
		local stageKey = targetNode.night .. "-" .. targetNode.round
		local targetX = targetNode.centerX
		local newPosition = UDim2.new(0, targetX, journeyAvatarMarker.Position.Y.Scale, journeyAvatarMarker.Position.Y.Offset)

		if animateWalk and lastJourneyStageKey and lastJourneyStageKey ~= stageKey then
			-- A little hop while walking over: up, across, down.
			local hopUp = journeyAvatarMarker.Position - UDim2.new(0, 0, 0, 20)
			tweenTo(journeyAvatarMarker, { Position = UDim2.new(0, journeyAvatarMarker.Position.X.Offset, hopUp.Y.Scale, hopUp.Y.Offset) }, 0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			task.delay(0.15, function()
				tweenTo(journeyAvatarMarker, { Position = UDim2.new(0, targetX, hopUp.Y.Scale, hopUp.Y.Offset) }, 0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
			end)
			task.delay(0.5, function()
				tweenTo(journeyAvatarMarker, newPosition, 0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			end)
		else
			journeyAvatarMarker.Position = newPosition
		end

		lastJourneyStageKey = stageKey
	end
end

refreshJourney = function()
	refreshJourneyImpl(true)
end

local function openJourney()
	playClickSfx()
	refreshJourneyImpl(false) -- snap to the right stage on open, no walk animation
	journeyBackdrop.Visible = true
	-- Scroll so the current stage is in view.
	if journeyAvatarMarker.Position.X.Offset > 0 then
		journeyMapScroll.CanvasPosition = Vector2.new(math.max(0, journeyAvatarMarker.Position.X.Offset - 200), 0)
	end
end

journeyButton.MouseButton1Click:Connect(openJourney)
menuJourneyButton.MouseButton1Click:Connect(openJourney)

end -- Road Ahead (journey/roadmap) overlay

-- ===== Poker Hands reference overlay =====
-- FEATURE 6: a live lookup table -- every hand type this game recognizes,
-- its base chips/mult (straight from Scoring.HandBase, so it can't drift
-- out of sync with actual balance), and how many times you've played it
-- this run. Plain Frames/TextLabels/UICorner only, no gradients.
--
-- refreshHandReference is defined much further down (once latestState
-- exists), and it needs to reach handRefListFrame -- so both are declared
-- here (outside the do/end below) and assigned (not `local`-declared again)
-- from inside. BUG FIX: this used to be handRefListFrame alone with
-- refreshHandReferenceImpl defined AFTER the block closed -- handRefListFrame
-- was already out of scope by then, so opening Poker Hands reference
-- silently errored out before Visible=true ran (button did nothing). See
-- the local-variable-budget note near the top of the file.
local refreshHandReference
local handRefListFrame

do

local handRefBackdrop = Instance.new("Frame")
handRefBackdrop.Name = "HandRefBackdrop"
handRefBackdrop.Size = UDim2.fromScale(1, 1)
handRefBackdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
handRefBackdrop.BackgroundTransparency = 0.4
handRefBackdrop.Visible = false
handRefBackdrop.ZIndex = 20
handRefBackdrop.Parent = screenGui

local handRefPanel = Instance.new("Frame")
handRefPanel.Size = UDim2.fromScale(0.5, 0.65)
handRefPanel.Position = UDim2.fromScale(0.25, 0.17)
handRefPanel.BackgroundColor3 = Color3.fromRGB(40, 30, 22)
handRefPanel.ZIndex = 21
handRefPanel.Parent = handRefBackdrop
polishPanel(handRefPanel, 16)
addSoftShadow(handRefPanel, 18)

local handRefTitle = Instance.new("TextLabel")
handRefTitle.Size = UDim2.new(1, 0, 0, 40)
handRefTitle.BackgroundTransparency = 1
handRefTitle.Font = Enum.Font.GothamBold
handRefTitle.TextSize = 22
handRefTitle.TextColor3 = Color3.fromRGB(250, 240, 220)
handRefTitle.Text = "Poker Hands"
handRefTitle.ZIndex = 21
handRefTitle.Parent = handRefPanel

local handRefHeaderRow = Instance.new("Frame")
handRefHeaderRow.Size = UDim2.new(1, -30, 0, 22)
handRefHeaderRow.Position = UDim2.new(0, 15, 0, 42)
handRefHeaderRow.BackgroundTransparency = 1
handRefHeaderRow.ZIndex = 21
handRefHeaderRow.Parent = handRefPanel

local function makeHandRefHeaderLabel(text, xScale, widthScale, alignment)
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(widthScale, 0, 1, 0)
	label.Position = UDim2.new(xScale, 0, 0, 0)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = 13
	label.TextColor3 = Color3.fromRGB(200, 185, 165)
	label.TextXAlignment = alignment or Enum.TextXAlignment.Left
	label.Text = text
	label.ZIndex = 21
	label.Parent = handRefHeaderRow
	return label
end

makeHandRefHeaderLabel("Hand", 0, 0.4)
makeHandRefHeaderLabel("Chips x Mult", 0.4, 0.35)
makeHandRefHeaderLabel("Played", 0.78, 0.22, Enum.TextXAlignment.Right)

handRefListFrame = Instance.new("ScrollingFrame")
handRefListFrame.Size = UDim2.new(1, -20, 1, -145)
handRefListFrame.Position = UDim2.new(0, 10, 0, 68)
handRefListFrame.BackgroundTransparency = 1
handRefListFrame.BorderSizePixel = 0
handRefListFrame.ScrollBarThickness = 8
handRefListFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
handRefListFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
handRefListFrame.ZIndex = 21
handRefListFrame.Parent = handRefPanel

local handRefListLayout = Instance.new("UIListLayout")
handRefListLayout.Padding = UDim.new(0, 6)
handRefListLayout.Parent = handRefListFrame

local handRefCloseButton = Instance.new("TextButton")
handRefCloseButton.Size = UDim2.new(0, 140, 0, 40)
handRefCloseButton.Position = UDim2.new(0.5, -70, 1, -50)
handRefCloseButton.Font = Enum.Font.GothamBold
handRefCloseButton.TextSize = 16
handRefCloseButton.Text = "Close"
handRefCloseButton.BackgroundColor3 = Color3.fromRGB(90, 60, 30)
handRefCloseButton.TextColor3 = Color3.fromRGB(250, 240, 220)
handRefCloseButton.ZIndex = 21
handRefCloseButton.Parent = handRefPanel
polishButton(handRefCloseButton, 12)

handRefCloseButton.MouseButton1Click:Connect(function()
	playClickSfx()
	handRefBackdrop.Visible = false
end)

handRefButton.MouseButton1Click:Connect(function()
	playClickSfx()
	if refreshHandReference then
		refreshHandReference()
	end
	handRefBackdrop.Visible = true
end)

end -- Poker Hands reference overlay

-- ===== Deck Tracker overlay =====
-- FEATURE 7: shows exactly how many of each card are still left to be
-- drawn this round -- reads directly off the server-computed
-- Deck.remainingCounts snapshot already included in the state payload.
--
-- refreshDeckTracker is defined much further down (once latestState
-- exists), and it needs to reach deckTrackerGrid -- so both are declared
-- here (outside the do/end below) and assigned (not `local`-declared
-- again) from inside. Same bug/fix as the Poker Hands reference overlay
-- right above -- see that comment for the full story. (makeDeckTrackerCell
-- doesn't need this treatment -- it's a stateless helper, redefined as a
-- nested local inside refreshDeckTrackerImpl instead of costing another
-- persistent top-level local.)
local refreshDeckTracker
local deckTrackerGrid

do

local deckTrackerBackdrop = Instance.new("Frame")
deckTrackerBackdrop.Name = "DeckTrackerBackdrop"
deckTrackerBackdrop.Size = UDim2.fromScale(1, 1)
deckTrackerBackdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
deckTrackerBackdrop.BackgroundTransparency = 0.4
deckTrackerBackdrop.Visible = false
deckTrackerBackdrop.ZIndex = 20
deckTrackerBackdrop.Parent = screenGui

local deckTrackerPanel = Instance.new("Frame")
deckTrackerPanel.Size = UDim2.fromScale(0.72, 0.5)
deckTrackerPanel.Position = UDim2.fromScale(0.14, 0.24)
deckTrackerPanel.BackgroundColor3 = Color3.fromRGB(40, 30, 22)
deckTrackerPanel.ZIndex = 21
deckTrackerPanel.Parent = deckTrackerBackdrop
polishPanel(deckTrackerPanel, 16)
addSoftShadow(deckTrackerPanel, 18)

local deckTrackerTitle = Instance.new("TextLabel")
deckTrackerTitle.Size = UDim2.new(1, 0, 0, 40)
deckTrackerTitle.BackgroundTransparency = 1
deckTrackerTitle.Font = Enum.Font.GothamBold
deckTrackerTitle.TextSize = 22
deckTrackerTitle.TextColor3 = Color3.fromRGB(250, 240, 220)
deckTrackerTitle.Text = "What's Left in the Deck"
deckTrackerTitle.ZIndex = 21
deckTrackerTitle.Parent = deckTrackerPanel

deckTrackerGrid = Instance.new("Frame")
deckTrackerGrid.Size = UDim2.new(1, -30, 1, -110)
deckTrackerGrid.Position = UDim2.new(0, 15, 0, 45)
deckTrackerGrid.BackgroundTransparency = 1
deckTrackerGrid.ZIndex = 21
deckTrackerGrid.Parent = deckTrackerPanel

local deckTrackerGridLayout = Instance.new("UIListLayout")
deckTrackerGridLayout.Padding = UDim.new(0, 4)
deckTrackerGridLayout.Parent = deckTrackerGrid

local deckTrackerCloseButton = Instance.new("TextButton")
deckTrackerCloseButton.Size = UDim2.new(0, 140, 0, 40)
deckTrackerCloseButton.Position = UDim2.new(0.5, -70, 1, -50)
deckTrackerCloseButton.Font = Enum.Font.GothamBold
deckTrackerCloseButton.TextSize = 16
deckTrackerCloseButton.Text = "Close"
deckTrackerCloseButton.BackgroundColor3 = Color3.fromRGB(90, 60, 30)
deckTrackerCloseButton.TextColor3 = Color3.fromRGB(250, 240, 220)
deckTrackerCloseButton.ZIndex = 21
deckTrackerCloseButton.Parent = deckTrackerPanel
polishButton(deckTrackerCloseButton, 12)

deckTrackerCloseButton.MouseButton1Click:Connect(function()
	playClickSfx()
	deckTrackerBackdrop.Visible = false
end)

deckTrackerButton.MouseButton1Click:Connect(function()
	playClickSfx()
	if refreshDeckTracker then
		refreshDeckTracker()
	end
	deckTrackerBackdrop.Visible = true
end)

end -- Deck Tracker overlay

-- ===== Settings overlay: simple audio-only settings panel. FEATURE 10,
-- reachable via the gear corner button. Scoped down to just Master Volume --
-- game options like animation speed/screenshake have no consumer code yet,
-- so they're deliberately left out to keep this one piece small. =====
--
-- Wrapped in do/end: Lua caps a single function (this whole script is one
-- top-level chunk) at 200 simultaneously-active local variables. None of
-- this section's locals are referenced outside it, so scoping them to a
-- block frees their slots once the block ends instead of holding them for
-- the rest of the file -- see the LOCAL VARIABLE BUDGET note near the top
-- of the file for the full explanation.
do

local settingsBackdrop = Instance.new("Frame")
settingsBackdrop.Name = "SettingsBackdrop"
settingsBackdrop.Size = UDim2.fromScale(1, 1)
settingsBackdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
settingsBackdrop.BackgroundTransparency = 0.4
settingsBackdrop.Visible = false
settingsBackdrop.ZIndex = 20
settingsBackdrop.Parent = screenGui

local settingsPanel = Instance.new("Frame")
settingsPanel.Size = UDim2.fromScale(0.4, 0.3)
settingsPanel.Position = UDim2.fromScale(0.3, 0.35)
settingsPanel.BackgroundColor3 = Color3.fromRGB(40, 30, 22)
settingsPanel.ZIndex = 21
settingsPanel.Parent = settingsBackdrop
polishPanel(settingsPanel, 16)
addSoftShadow(settingsPanel, 18)

local settingsTitle = Instance.new("TextLabel")
settingsTitle.Size = UDim2.new(1, 0, 0, 40)
settingsTitle.BackgroundTransparency = 1
settingsTitle.Font = Enum.Font.GothamBold
settingsTitle.TextSize = 22
settingsTitle.TextColor3 = Color3.fromRGB(250, 240, 220)
settingsTitle.Text = "Settings"
settingsTitle.ZIndex = 21
settingsTitle.Parent = settingsPanel

local settingsBody = Instance.new("Frame")
settingsBody.Size = UDim2.new(1, -40, 1, -110)
settingsBody.Position = UDim2.new(0, 20, 0, 50)
settingsBody.BackgroundTransparency = 1
settingsBody.ZIndex = 21
settingsBody.Parent = settingsPanel

-- Independent of the corner volumeButton's loud/quiet/muted cycle -- this
-- gives fine-grained 0-100 control over the same Sound instance's Volume.
local masterVolumeValue = math.floor(backgroundMusic.Volume * 100 + 0.5)

makeStepperRow(
	settingsBody,
	"Master Volume",
	0,
	100,
	10,
	function()
		return masterVolumeValue
	end,
	function(newValue)
		masterVolumeValue = newValue
		backgroundMusic.Volume = newValue / 100
	end,
	function(value)
		return tostring(value) .. "%"
	end
)

local settingsCloseButton = Instance.new("TextButton")
settingsCloseButton.Size = UDim2.new(0, 140, 0, 40)
settingsCloseButton.Position = UDim2.new(0.5, -70, 1, -50)
settingsCloseButton.Font = Enum.Font.GothamBold
settingsCloseButton.TextSize = 16
settingsCloseButton.Text = "Close"
settingsCloseButton.BackgroundColor3 = Color3.fromRGB(90, 60, 30)
settingsCloseButton.TextColor3 = Color3.fromRGB(250, 240, 220)
settingsCloseButton.ZIndex = 21
settingsCloseButton.Parent = settingsPanel
polishButton(settingsCloseButton, 12)

settingsCloseButton.MouseButton1Click:Connect(function()
	playClickSfx()
	settingsBackdrop.Visible = false
end)

settingsButton.MouseButton1Click:Connect(function()
	playClickSfx()
	settingsBackdrop.Visible = true
end)

end -- Settings overlay

-- ===== Run Setup overlay: pick a Deck Variant + Difficulty before a new
-- run begins. FEATURE 8, reachable from the main menu ("New Run..."). =====

local runSetupBackdrop = Instance.new("Frame")
runSetupBackdrop.Name = "RunSetupBackdrop"
runSetupBackdrop.Size = UDim2.fromScale(1, 1)
runSetupBackdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
runSetupBackdrop.BackgroundTransparency = 0.4
runSetupBackdrop.Visible = false
runSetupBackdrop.ZIndex = 25 -- above the in-game overlays; it's reachable from the menu too
runSetupBackdrop.Parent = screenGui

local runSetupPanel = Instance.new("Frame")
runSetupPanel.Size = UDim2.fromScale(0.6, 0.72)
runSetupPanel.Position = UDim2.fromScale(0.2, 0.13)
runSetupPanel.BackgroundColor3 = Color3.fromRGB(40, 30, 22)
runSetupPanel.ZIndex = 26
runSetupPanel.Parent = runSetupBackdrop
polishPanel(runSetupPanel, 16)
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
runSetupLayout.Padding = UDim.new(0, 14)
runSetupLayout.Parent = runSetupScroll

-- accentColor: a whole colored bar (not just tinted text) so "which
-- section am I in" is answerable at a glance while scrolling, even before
-- reading the word -- Deck Variant is gold, Difficulty is crimson, and
-- every card below carries a matching accent stripe (see makePickCard).
local function makeRunSetupSectionLabel(text, icon, order, accentColor)
	local header = Instance.new("Frame")
	header.Size = UDim2.new(1, 0, 0, 32)
	header.BackgroundColor3 = accentColor
	header.BackgroundTransparency = 0.75
	header.LayoutOrder = order
	header.ZIndex = 26
	header.Parent = runSetupScroll
	polishPanel(header, 8)

	local stripe = Instance.new("Frame")
	stripe.Size = UDim2.new(0, 4, 1, -10)
	stripe.Position = UDim2.new(0, 0, 0, 5)
	stripe.BackgroundColor3 = accentColor
	stripe.BorderSizePixel = 0
	stripe.ZIndex = 27
	stripe.Parent = header
	roundCorner(stripe, 2)

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, -20, 1, 0)
	label.Position = UDim2.new(0, 14, 0, 0)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = 17
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextColor3 = Color3.fromRGB(255, 240, 215)
	label.Text = icon .. "  " .. text
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

makeRunSetupSectionLabel("Deck Variant", "🃏", 1, DECK_VARIANT_ACCENT)
makeRunSetupSectionLabel("Difficulty", "⚔️", 19, DIFFICULTY_ACCENT)

local function makePickCard(parent, order, name, description, isSelected, accentColor)
	local card = Instance.new("Frame")
	card.Size = UDim2.new(1, 0, 0, 60)
	card.BackgroundColor3 = isSelected and Color3.fromRGB(90, 70, 40) or Color3.fromRGB(60, 45, 32)
	card.LayoutOrder = order
	card.ZIndex = 26
	card.Parent = parent
	polishPanel(card, 10)

	local stripe = Instance.new("Frame")
	stripe.Size = UDim2.new(0, 4, 1, -12)
	stripe.Position = UDim2.new(0, 0, 0, 6)
	stripe.BackgroundColor3 = accentColor
	stripe.BorderSizePixel = 0
	stripe.ZIndex = 27
	stripe.Parent = card
	roundCorner(stripe, 2)

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, -30, 0, 22)
	nameLabel.Position = UDim2.new(0, 16, 0, 4)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 15
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextColor3 = Color3.fromRGB(250, 240, 220)
	nameLabel.Text = (isSelected and "✓ " or "") .. name
	nameLabel.ZIndex = 26
	nameLabel.Parent = card

	local descLabel = Instance.new("TextLabel")
	descLabel.Size = UDim2.new(1, -30, 0, 30)
	descLabel.Position = UDim2.new(0, 16, 0, 26)
	descLabel.BackgroundTransparency = 1
	descLabel.Font = Enum.Font.Gotham
	descLabel.TextSize = 13
	descLabel.TextWrapped = true
	descLabel.TextXAlignment = Enum.TextXAlignment.Left
	descLabel.TextColor3 = Color3.fromRGB(210, 195, 175)
	descLabel.Text = description
	descLabel.ZIndex = 26
	descLabel.Parent = card

	local clickCatcher = Instance.new("TextButton")
	clickCatcher.Size = UDim2.fromScale(1, 1)
	clickCatcher.BackgroundTransparency = 1
	clickCatcher.Text = ""
	clickCatcher.ZIndex = 26
	clickCatcher.Parent = card

	return card, clickCatcher
end

local function refreshRunSetupCards()
	for _, child in ipairs(deckVariantCards) do
		child:Destroy()
	end
	deckVariantCards = {}
	for i, variant in ipairs(DeckVariants.Definitions) do
		local card, clickCatcher = makePickCard(runSetupScroll, 2 + i, variant.name, variant.description, variant.id == selectedDeckVariantId, DECK_VARIANT_ACCENT)
		table.insert(deckVariantCards, card)
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
		local card, clickCatcher = makePickCard(runSetupScroll, 20 + i, tier.name, tier.description, tier.id == selectedDifficultyId, DIFFICULTY_ACCENT)
		table.insert(difficultyCards, card)
		clickCatcher.MouseButton1Click:Connect(function()
			playClickSfx(0.4)
			selectedDifficultyId = tier.id
			refreshRunSetupCards()
		end)
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

runSetupCancelButton.MouseButton1Click:Connect(function()
	playClickSfx()
	runSetupBackdrop.Visible = false
end)

runSetupBeginButton.MouseButton1Click:Connect(function()
	playSfx(SOUND_IDS.buyPatron)
	StartRunRemote:FireServer(selectedDeckVariantId, selectedDifficultyId)
	runSetupBackdrop.Visible = false
	menuFrame.Visible = false
	root.Visible = true
	if backgroundMusic.SoundId ~= "rbxassetid://0" and backgroundMusic.Volume > 0 then
		backgroundMusic:Play()
	end
end)

local function openRunSetup()
	playClickSfx()
	refreshRunSetupCards()
	runSetupBackdrop.Visible = true
end

menuNewRunButton.MouseButton1Click:Connect(openRunSetup)

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

local function refreshThemesListImpl()
	for _, child in ipairs(themesListFrame:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	local ownedSet = {}
	local equippedId = Themes.DefaultThemeId
	if latestState then
		for _, id in ipairs(latestState.ownedThemeIds or {}) do
			ownedSet[id] = true
		end
		equippedId = latestState.equippedTheme or equippedId
	end

	for _, theme in ipairs(Themes.Definitions) do
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, 0, 0, 50)
		row.BackgroundColor3 = Color3.fromRGB(60, 45, 32)
		row.Parent = themesListFrame
		polishPanel(row, 10)

		local swatch = Instance.new("Frame")
		swatch.Size = UDim2.new(0, 30, 0, 30)
		swatch.Position = UDim2.new(0, 10, 0.5, -15)
		swatch.BackgroundColor3 = theme.colors.accent
		swatch.Parent = row
		roundCorner(swatch, 6)

		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(1, -220, 1, 0)
		label.Position = UDim2.new(0, 50, 0, 0)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.Gotham
		label.TextSize = 15
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextColor3 = Color3.fromRGB(250, 240, 220)
		label.Text = string.format("%s -- %s", theme.name, theme.description)
		label.Parent = row

		local actionButton = Instance.new("TextButton")
		actionButton.Size = UDim2.new(0, 130, 0, 36)
		actionButton.Position = UDim2.new(1, -140, 0.5, -18)
		actionButton.Font = Enum.Font.GothamBold
		actionButton.TextSize = 14
		actionButton.BackgroundColor3 = Color3.fromRGB(90, 60, 30)
		actionButton.TextColor3 = Color3.fromRGB(250, 240, 220)
		actionButton.Parent = row
		polishButton(actionButton, 8)

		if theme.id == equippedId then
			actionButton.Text = "Equipped"
			actionButton.AutoButtonColor = false
			actionButton.BackgroundColor3 = Color3.fromRGB(70, 90, 55)
		elseif ownedSet[theme.id] then
			actionButton.Text = "Equip"
			actionButton.MouseButton1Click:Connect(function()
				playClickSfx()
				EquipThemeRemote:FireServer(theme.id)
			end)
		else
			actionButton.Text = string.format("Buy (%d)", theme.price)
			actionButton.MouseButton1Click:Connect(function()
				if not latestState or latestState.tips < theme.price then
					showWarning("Not enough tips for that.")
					playClickSfx()
					return
				end
				playSfx(SOUND_IDS.buyPatron)
				BuyThemeRemote:FireServer(theme.id)
			end)
		end
	end
end

refreshThemesList = refreshThemesListImpl

-- ----- Poker Hands reference -----

local function refreshHandReferenceImpl()
	for _, child in ipairs(handRefListFrame:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	local handStats = (latestState and latestState.handStats) or {}

	-- Strongest hand first, matching how most poker reference charts read.
	for i = #HandEvaluator.HandOrder, 1, -1 do
		local handName = HandEvaluator.HandOrder[i]
		local base = Scoring.HandBase[handName]

		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, 0, 0, 34)
		row.BackgroundColor3 = Color3.fromRGB(60, 45, 32)
		row.ZIndex = 21
		row.Parent = handRefListFrame
		polishPanel(row, 8)

		local nameLabel = Instance.new("TextLabel")
		nameLabel.Size = UDim2.new(0.4, 0, 1, 0)
		nameLabel.Position = UDim2.new(0, 10, 0, 0)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Font = Enum.Font.Gotham
		nameLabel.TextSize = 14
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.TextColor3 = Color3.fromRGB(250, 240, 220)
		nameLabel.Text = handName
		nameLabel.ZIndex = 21
		nameLabel.Parent = row

		local valueLabel = Instance.new("TextLabel")
		valueLabel.Size = UDim2.new(0.35, 0, 1, 0)
		valueLabel.Position = UDim2.new(0.4, 0, 0, 0)
		valueLabel.BackgroundTransparency = 1
		valueLabel.Font = Enum.Font.Gotham
		valueLabel.TextSize = 14
		valueLabel.TextXAlignment = Enum.TextXAlignment.Left
		valueLabel.TextColor3 = Color3.fromRGB(255, 214, 130)
		valueLabel.Text = string.format("%d x %d", base.chips, base.mult)
		valueLabel.ZIndex = 21
		valueLabel.Parent = row

		local playedLabel = Instance.new("TextLabel")
		playedLabel.Size = UDim2.new(0.2, -10, 1, 0)
		playedLabel.Position = UDim2.new(0.8, 0, 0, 0)
		playedLabel.BackgroundTransparency = 1
		playedLabel.Font = Enum.Font.GothamBold
		playedLabel.TextSize = 14
		playedLabel.TextXAlignment = Enum.TextXAlignment.Right
		playedLabel.TextColor3 = Color3.fromRGB(200, 220, 200)
		playedLabel.Text = tostring(handStats[handName] or 0)
		playedLabel.ZIndex = 21
		playedLabel.Parent = row
	end
end

refreshHandReference = refreshHandReferenceImpl

-- ----- Deck Tracker -----

local function refreshDeckTrackerImpl()
	local function makeDeckTrackerCell(parent, text, widthScale, isHeader, textColor)
		local cell = Instance.new("TextLabel")
		cell.Size = UDim2.new(widthScale, 0, 1, 0)
		cell.BackgroundTransparency = 1
		cell.Font = isHeader and Enum.Font.GothamBold or Enum.Font.Gotham
		cell.TextSize = 13
		cell.TextColor3 = textColor or Color3.fromRGB(230, 220, 205)
		cell.Text = text
		cell.ZIndex = 21
		cell.Parent = parent
		return cell
	end

	for _, child in ipairs(deckTrackerGrid:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	local deckCounts = latestState and latestState.deckCounts
	local cellWidth = 1 / (#Deck.RankOrder + 1)

	local headerRow = Instance.new("Frame")
	headerRow.Size = UDim2.new(1, 0, 0, 24)
	headerRow.BackgroundTransparency = 1
	headerRow.ZIndex = 21
	headerRow.Parent = deckTrackerGrid
	local headerLayout = Instance.new("UIListLayout")
	headerLayout.FillDirection = Enum.FillDirection.Horizontal
	headerLayout.Parent = headerRow
	makeDeckTrackerCell(headerRow, "", cellWidth, true)
	for _, rank in ipairs(Deck.RankOrder) do
		makeDeckTrackerCell(headerRow, RANK_NAMES[rank], cellWidth, true, Color3.fromRGB(200, 185, 165))
	end

	for _, suit in ipairs(SUIT_DISPLAY_ORDER) do
		local suitRow = Instance.new("Frame")
		suitRow.Size = UDim2.new(1, 0, 0, 26)
		suitRow.BackgroundColor3 = Color3.fromRGB(50, 38, 28)
		suitRow.ZIndex = 21
		suitRow.Parent = deckTrackerGrid
		roundCorner(suitRow, 6)
		local suitLayout = Instance.new("UIListLayout")
		suitLayout.FillDirection = Enum.FillDirection.Horizontal
		suitLayout.Parent = suitRow

		local suitColor = RED_SUITS[suit] and Color3.fromRGB(230, 140, 140) or Color3.fromRGB(220, 220, 230)
		makeDeckTrackerCell(suitRow, SUIT_SYMBOLS[suit], cellWidth, true, suitColor)
		for _, rank in ipairs(Deck.RankOrder) do
			local count = (deckCounts and deckCounts[suit] and deckCounts[suit][rank]) or 0
			local cellColor = count > 0 and Color3.fromRGB(230, 220, 205) or Color3.fromRGB(110, 100, 90)
			makeDeckTrackerCell(suitRow, tostring(count), cellWidth, false, cellColor)
		end
	end
end

refreshDeckTracker = refreshDeckTrackerImpl

-- ===== Collection Gallery overlay =====
-- FEATURE 11: a grid of every Patron and Theme in the game -- owned ones
-- shown in full, locked ones silhouetted with a "?". Session-scoped like
-- the rest of the run state (no DataStore yet -- see the Themes.lua
-- comment), so this shows what's been found so far THIS run.
--
-- Wrapped in do/end -- see the local-variable-budget note near the top of
-- the file. Everything here (including refreshCollection's forward-declare
-- and its use in the button click handler below) is self-contained to this
-- section, so it's safe to scope it entirely.
do

local collectionBackdrop = Instance.new("Frame")
collectionBackdrop.Name = "CollectionBackdrop"
collectionBackdrop.Size = UDim2.fromScale(1, 1)
collectionBackdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
collectionBackdrop.BackgroundTransparency = 0.4
collectionBackdrop.Visible = false
collectionBackdrop.ZIndex = 20
collectionBackdrop.Parent = screenGui

local collectionPanel = Instance.new("Frame")
collectionPanel.Size = UDim2.fromScale(0.6, 0.7)
collectionPanel.Position = UDim2.fromScale(0.2, 0.15)
collectionPanel.BackgroundColor3 = Color3.fromRGB(40, 30, 22)
collectionPanel.ZIndex = 21
collectionPanel.Parent = collectionBackdrop
polishPanel(collectionPanel, 16)
addSoftShadow(collectionPanel, 18)

local collectionTitle = Instance.new("TextLabel")
collectionTitle.Size = UDim2.new(1, 0, 0, 40)
collectionTitle.BackgroundTransparency = 1
collectionTitle.Font = Enum.Font.GothamBold
collectionTitle.TextSize = 22
collectionTitle.TextColor3 = Color3.fromRGB(250, 240, 220)
collectionTitle.Text = "Collection -- this run"
collectionTitle.ZIndex = 21
collectionTitle.Parent = collectionPanel

local collectionScroll = Instance.new("ScrollingFrame")
collectionScroll.Size = UDim2.new(1, -30, 1, -110)
collectionScroll.Position = UDim2.new(0, 15, 0, 45)
collectionScroll.BackgroundTransparency = 1
collectionScroll.BorderSizePixel = 0
collectionScroll.ScrollBarThickness = 8
collectionScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
collectionScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
collectionScroll.ZIndex = 21
collectionScroll.Parent = collectionPanel

local collectionLayout = Instance.new("UIListLayout")
collectionLayout.Padding = UDim.new(0, 10)
collectionLayout.Parent = collectionScroll

local collectionCloseButton = Instance.new("TextButton")
collectionCloseButton.Size = UDim2.new(0, 140, 0, 40)
collectionCloseButton.Position = UDim2.new(0.5, -70, 1, -50)
collectionCloseButton.Font = Enum.Font.GothamBold
collectionCloseButton.TextSize = 16
collectionCloseButton.Text = "Close"
collectionCloseButton.BackgroundColor3 = Color3.fromRGB(90, 60, 30)
collectionCloseButton.TextColor3 = Color3.fromRGB(250, 240, 220)
collectionCloseButton.ZIndex = 21
collectionCloseButton.Parent = collectionPanel
polishButton(collectionCloseButton, 12)

collectionCloseButton.MouseButton1Click:Connect(function()
	playClickSfx()
	collectionBackdrop.Visible = false
end)

local function makeCollectionSectionHeader(text, order)
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 0, 22)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = 16
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextColor3 = Color3.fromRGB(255, 214, 130)
	label.Text = text
	label.LayoutOrder = order
	label.ZIndex = 21
	label.Parent = collectionScroll
	return label
end

local function makeCollectionRow(order, name, description, isOwned, swatchColor, icon)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, 50)
	row.BackgroundColor3 = isOwned and Color3.fromRGB(60, 50, 32) or Color3.fromRGB(45, 40, 38)
	row.LayoutOrder = order
	row.ZIndex = 21
	row.Parent = collectionScroll
	polishPanel(row, 10)

	local swatch = Instance.new("Frame")
	swatch.Size = UDim2.new(0, 30, 0, 30)
	swatch.Position = UDim2.new(0, 10, 0.5, -15)
	swatch.BackgroundColor3 = isOwned and (swatchColor or Color3.fromRGB(200, 170, 100)) or Color3.fromRGB(70, 65, 60)
	swatch.ZIndex = 21
	swatch.Parent = row
	roundCorner(swatch, 8)

	local swatchLabel = Instance.new("TextLabel")
	swatchLabel.Size = UDim2.fromScale(1, 1)
	swatchLabel.BackgroundTransparency = 1
	swatchLabel.Font = Enum.Font.GothamBold
	swatchLabel.TextSize = 16
	swatchLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	swatchLabel.Text = isOwned and (icon or "") or "?"
	swatchLabel.ZIndex = 21
	swatchLabel.Parent = swatch

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, -60, 0, 22)
	nameLabel.Position = UDim2.new(0, 50, 0, 4)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 15
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextColor3 = isOwned and Color3.fromRGB(250, 240, 220) or Color3.fromRGB(140, 135, 130)
	nameLabel.Text = isOwned and name or "???"
	nameLabel.ZIndex = 21
	nameLabel.Parent = row

	local descLabel = Instance.new("TextLabel")
	descLabel.Size = UDim2.new(1, -60, 0, 20)
	descLabel.Position = UDim2.new(0, 50, 0, 24)
	descLabel.BackgroundTransparency = 1
	descLabel.Font = Enum.Font.Gotham
	descLabel.TextSize = 12
	descLabel.TextWrapped = true
	descLabel.TextXAlignment = Enum.TextXAlignment.Left
	descLabel.TextColor3 = isOwned and Color3.fromRGB(210, 195, 175) or Color3.fromRGB(120, 115, 110)
	descLabel.Text = isOwned and description or "Not found yet this run."
	descLabel.ZIndex = 21
	descLabel.Parent = row
end

-- Forward-declared for the same reason as the other refresh* functions.
local refreshCollection

local function refreshCollectionImpl()
	for _, child in ipairs(collectionScroll:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	local ownedPatronIds = {}
	local ownedThemeIds = {}
	if latestState then
		for _, patron in ipairs(latestState.ownedPatrons or {}) do
			ownedPatronIds[patron.id] = true
		end
		for _, id in ipairs(latestState.ownedThemeIds or {}) do
			ownedThemeIds[id] = true
		end
	end

	local ownedPatronCount = 0
	for _ in pairs(ownedPatronIds) do
		ownedPatronCount = ownedPatronCount + 1
	end
	local ownedThemeCount = 0
	for _ in pairs(ownedThemeIds) do
		ownedThemeCount = ownedThemeCount + 1
	end

	makeCollectionSectionHeader(string.format("Patrons -- %d / %d found", ownedPatronCount, #Patrons.Definitions), 1)
	for i, patron in ipairs(Patrons.Definitions) do
		makeCollectionRow(1 + i, patron.name, patron.description, ownedPatronIds[patron.id] == true, Color3.fromRGB(200, 170, 100), patron.icon)
	end

	makeCollectionSectionHeader(string.format("Themes -- %d / %d found", ownedThemeCount, #Themes.Definitions), 100)
	for i, theme in ipairs(Themes.Definitions) do
		makeCollectionRow(100 + i, theme.name, theme.description, ownedThemeIds[theme.id] == true, theme.colors.accent)
	end
end

refreshCollection = refreshCollectionImpl

collectionButton.MouseButton1Click:Connect(function()
	playClickSfx()
	refreshCollection()
	collectionBackdrop.Visible = true
end)

end -- Collection Gallery overlay

-- ===== "Unlocked!" popup =====
-- FEATURE 12: a quick celebratory card shown whenever a NEW Patron or Theme
-- appears in the state compared to the previous render() -- see the diff
-- check inside render() further down.
--
-- NOTE: deliberately NOT using addSoftShadow() here, unlike every other
-- overlay. addSoftShadow() parents its shadow Frame into panel.Parent and
-- sizes it to 100% of that parent -- every other overlay's panel lives
-- inside a full-screen "xBackdrop" Frame whose Visible=false cascades down
-- to hide the shadow too. This popup is a small floating card parented
-- directly to screenGui (no backdrop), so that shadow would default to
-- Visible=true and sit as a permanent ~full-screen 55%-opaque black layer
-- over everything -- this was root-caused as the cause of a "dark right
-- away" regression and reverted once already. Skipping the shadow avoids
-- it entirely; the rounded corners from polishPanel are enough polish.
--
-- lastOwnedPatronIds/lastOwnedThemeIds/hasRenderedOnce and showUnlockPopup
-- are all read/called from render() much further down in the file, so
-- they're declared here (outside the do/end below) and assigned to from
-- inside it -- everything else in this section is self-contained and can
-- be safely scoped to the block. See the local-variable-budget note near
-- the top of the file.
local lastOwnedPatronIds = {}
local lastOwnedThemeIds = {}
local hasRenderedOnce = false
local showUnlockPopup

-- lastPhase/showRoundReward: same forward-declare pattern, for the round
-- reward popup below -- lastPhase is read/written from render() to detect
-- the moment a round is WON (phase transitions into "shop"), not just
-- "currently in the shop" (which stays true across unrelated re-renders
-- while shopping, e.g. buying a Patron).
local lastPhase = nil
local showRoundReward

do

local unlockPopup = Instance.new("Frame")
unlockPopup.Name = "UnlockPopup"
unlockPopup.Size = UDim2.new(0, 280, 0, 140)
unlockPopup.AnchorPoint = Vector2.new(0.5, 0.5)
unlockPopup.Position = UDim2.fromScale(0.5, 0.5)
unlockPopup.BackgroundColor3 = Color3.fromRGB(50, 40, 26)
unlockPopup.Visible = false
unlockPopup.ZIndex = 30
unlockPopup.Parent = screenGui
polishPanel(unlockPopup, 18)

local unlockPopupHeader = Instance.new("TextLabel")
unlockPopupHeader.Size = UDim2.new(1, 0, 0, 34)
unlockPopupHeader.Position = UDim2.new(0, 0, 0, 12)
unlockPopupHeader.BackgroundTransparency = 1
unlockPopupHeader.Font = Enum.Font.GothamBold
unlockPopupHeader.TextSize = 20
unlockPopupHeader.TextColor3 = Color3.fromRGB(255, 214, 130)
unlockPopupHeader.Text = "Unlocked!"
unlockPopupHeader.ZIndex = 30
unlockPopupHeader.Parent = unlockPopup

local unlockPopupName = Instance.new("TextLabel")
unlockPopupName.Size = UDim2.new(1, -30, 0, 26)
unlockPopupName.Position = UDim2.new(0, 15, 0, 48)
unlockPopupName.BackgroundTransparency = 1
unlockPopupName.Font = Enum.Font.GothamBold
unlockPopupName.TextSize = 17
unlockPopupName.TextColor3 = Color3.fromRGB(250, 240, 220)
unlockPopupName.Text = ""
unlockPopupName.ZIndex = 30
unlockPopupName.Parent = unlockPopup

local unlockPopupDescription = Instance.new("TextLabel")
unlockPopupDescription.Size = UDim2.new(1, -30, 0, 40)
unlockPopupDescription.Position = UDim2.new(0, 15, 0, 76)
unlockPopupDescription.BackgroundTransparency = 1
unlockPopupDescription.Font = Enum.Font.Gotham
unlockPopupDescription.TextSize = 13
unlockPopupDescription.TextWrapped = true
unlockPopupDescription.TextColor3 = Color3.fromRGB(215, 200, 180)
unlockPopupDescription.Text = ""
unlockPopupDescription.ZIndex = 30
unlockPopupDescription.Parent = unlockPopup

local unlockPopupScale = Instance.new("UIScale")
unlockPopupScale.Scale = 1
unlockPopupScale.Parent = unlockPopup

local unlockPopupDismissCatcher = Instance.new("TextButton")
unlockPopupDismissCatcher.Size = UDim2.fromScale(1, 1)
unlockPopupDismissCatcher.BackgroundTransparency = 1
unlockPopupDismissCatcher.Text = ""
unlockPopupDismissCatcher.ZIndex = 30
unlockPopupDismissCatcher.Parent = unlockPopup

local unlockPopupToken = 0

showUnlockPopup = function(name, description)
	unlockPopupToken = unlockPopupToken + 1
	local myToken = unlockPopupToken

	unlockPopupName.Text = name
	unlockPopupDescription.Text = description or ""
	unlockPopup.Visible = true
	unlockPopupScale.Scale = 0.7
	tweenTo(unlockPopupScale, { Scale = 1 }, 0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

	local function dismiss()
		if unlockPopupToken ~= myToken then
			return
		end
		unlockPopup.Visible = false
	end

	unlockPopupDismissCatcher.MouseButton1Click:Connect(dismiss)
	task.delay(2.4, dismiss)
end

end -- "Unlocked!" popup

-- ----- Round reward popup: "+$X Tips!" on round win, with its own cash SFX -----
-- Requested by Ahmed: a visual callout for how much you just earned when a
-- round is won, plus a cash sound distinct from the shop Buy sound. Parented
-- to screenGui directly (no backdrop) same as the Unlock popup right above
-- -- see that block's comment for why addSoftShadow is deliberately skipped
-- here too.
do

local roundRewardPopup = Instance.new("Frame")
roundRewardPopup.Name = "RoundRewardPopup"
roundRewardPopup.Size = UDim2.new(0, 260, 0, 100)
roundRewardPopup.AnchorPoint = Vector2.new(0.5, 0.5)
roundRewardPopup.Position = UDim2.fromScale(0.5, 0.42)
roundRewardPopup.BackgroundColor3 = Color3.fromRGB(40, 55, 35)
roundRewardPopup.Visible = false
roundRewardPopup.ZIndex = 28
roundRewardPopup.Parent = screenGui
polishPanel(roundRewardPopup, 18)

local roundRewardTitle = Instance.new("TextLabel")
roundRewardTitle.Size = UDim2.new(1, -20, 0, 30)
roundRewardTitle.Position = UDim2.new(0, 10, 0, 12)
roundRewardTitle.BackgroundTransparency = 1
roundRewardTitle.Font = Enum.Font.GothamBold
roundRewardTitle.TextSize = 20
roundRewardTitle.TextColor3 = Color3.fromRGB(255, 230, 180)
roundRewardTitle.Text = "Round Complete!"
roundRewardTitle.ZIndex = 28
roundRewardTitle.Parent = roundRewardPopup

local roundRewardAmount = Instance.new("TextLabel")
roundRewardAmount.Size = UDim2.new(1, -20, 0, 40)
roundRewardAmount.Position = UDim2.new(0, 10, 0, 46)
roundRewardAmount.BackgroundTransparency = 1
roundRewardAmount.Font = Enum.Font.GothamBold
roundRewardAmount.TextSize = 28
roundRewardAmount.TextColor3 = Color3.fromRGB(150, 235, 140)
roundRewardAmount.Text = ""
roundRewardAmount.ZIndex = 28
roundRewardAmount.Parent = roundRewardPopup

local roundRewardScale = Instance.new("UIScale")
roundRewardScale.Scale = 1
roundRewardScale.Parent = roundRewardPopup

showRoundReward = function(amount)
	roundRewardAmount.Text = string.format("+$%d Tips", amount)
	roundRewardPopup.Visible = true
	roundRewardScale.Scale = 0.6
	playSfx(SOUND_IDS.roundReward, 1)
	tweenTo(roundRewardScale, { Scale = 1.15 }, 0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	task.delay(0.2, function()
		tweenTo(roundRewardScale, { Scale = 1 }, 0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	end)
	task.delay(2.2, function()
		roundRewardPopup.Visible = false
	end)
end

end -- Round reward popup

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

-- A small colored badge with an icon (emoji glyph, not an uploaded image --
-- see the TavernScene comment for why we don't guess catalog asset IDs)
-- standing in for "a picture" for each Patron until real art exists.
local function makePatronIconBadge(parent, icon)
	local badge = Instance.new("TextLabel")
	badge.Size = UDim2.new(0, 46, 0, 46)
	badge.Position = UDim2.new(0, 8, 0.5, -23)
	badge.BackgroundColor3 = Color3.fromRGB(45, 35, 25)
	badge.Font = Enum.Font.GothamBold
	badge.TextSize = 22
	badge.Text = icon or "🎴"
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
		emptyLabel.Parent = shopBuyListFrame
		return
	end

	for _, offer in ipairs(shopOffers) do
		local fullPatron = Patrons.getById(offer.id)

		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, 0, 0, 64)
		row.BackgroundColor3 = Color3.fromRGB(60, 45, 32)
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
		label.Parent = row

		local buyButton = Instance.new("TextButton")
		buyButton.Size = UDim2.new(0, 90, 0, 36)
		buyButton.Position = UDim2.new(1, -100, 0.5, -18)
		buyButton.Font = Enum.Font.GothamBold
		buyButton.TextSize = 15
		buyButton.Text = "Buy"
		buyButton.BackgroundColor3 = Color3.fromRGB(90, 60, 30)
		buyButton.TextColor3 = Color3.fromRGB(250, 240, 220)
		buyButton.Parent = row
		polishButton(buyButton, 8)

		buyButton.MouseButton1Click:Connect(function()
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
		emptyLabel.Parent = shopMyPatronsListFrame
		return
	end

	for _, owned in ipairs(ownedPatrons) do
		local fullPatron = Patrons.getById(owned.id)
		local refund = fullPatron and math.floor(fullPatron.price / 2) or 0

		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, 0, 0, 64)
		row.BackgroundColor3 = Color3.fromRGB(60, 45, 32)
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
		label.Parent = row

		local discardButton = Instance.new("TextButton")
		discardButton.Size = UDim2.new(0, 110, 0, 36)
		discardButton.Position = UDim2.new(1, -120, 0.5, -18)
		discardButton.Font = Enum.Font.GothamBold
		discardButton.TextSize = 14
		discardButton.Text = "Discard"
		discardButton.BackgroundColor3 = Color3.fromRGB(110, 55, 45)
		discardButton.TextColor3 = Color3.fromRGB(250, 240, 220)
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
