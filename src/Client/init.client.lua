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
local BuyThemeRemote = remotes:WaitForChild("BuyTheme")
local EquipThemeRemote = remotes:WaitForChild("EquipTheme")
local AdvanceRoundRemote = remotes:WaitForChild("AdvanceRound")
local RestartRunRemote = remotes:WaitForChild("RestartRun")
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

local RANK_NAMES = {
	[2] = "2", [3] = "3", [4] = "4", [5] = "5", [6] = "6", [7] = "7", [8] = "8", [9] = "9", [10] = "10",
	[11] = "J", [12] = "Q", [13] = "K", [14] = "A",
}
local SUIT_SYMBOLS = { Hearts = "♥", Diamonds = "♦", Clubs = "♣", Spades = "♠" }
local RED_SUITS = { Hearts = true, Diamonds = true }

-- ===== Sound (fill these in!) =====
--[[
	These are placeholders (asset id 0 == silent, no crash). To add real
	sound: in Studio, Home tab -> Toolbox -> Audio, filter Creator = "Roblox"
	for guaranteed free-to-use tracks/SFX, right-click a result -> Copy ID,
	and paste it in as "rbxassetid://<the number>" below.
]]
local SOUND_IDS = {
	backgroundMusic = "rbxassetid://0", -- TODO: pick a looping tavern/ambient track
	cardToggle = "rbxassetid://0",      -- TODO: short click/tap sound
	playHand = "rbxassetid://0",        -- TODO: a "whoosh" or chime
	buyPatron = "rbxassetid://0",       -- TODO: a coin/purchase sound
	uiClick = "rbxassetid://0",         -- TODO: generic button click
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

local function playSfx(soundId, volume)
	if not soundId or soundId == "" or soundId == "rbxassetid://0" then
		return -- placeholder id, nothing to play yet
	end
	local sfx = Instance.new("Sound")
	sfx.SoundId = soundId
	sfx.Volume = volume or 0.6
	sfx.Parent = SoundService
	sfx:Play()
	task.delay(5, function()
		if sfx then
			sfx:Destroy()
		end
	end)
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

-- ----- Top status bar -----

local statusBar = Instance.new("Frame")
statusBar.Name = "StatusBar"
statusBar.Size = UDim2.new(1, 0, 0, 60)
statusBar.BackgroundColor3 = Color3.fromRGB(40, 30, 22)
statusBar.BorderSizePixel = 0
statusBar.Parent = root

local statusLayout = Instance.new("UIListLayout")
statusLayout.FillDirection = Enum.FillDirection.Horizontal
statusLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
statusLayout.VerticalAlignment = Enum.VerticalAlignment.Center
statusLayout.Padding = UDim.new(0, 24)
statusLayout.Parent = statusBar

local function makeStatusLabel()
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(0, 180, 1, 0)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = 18
	label.TextColor3 = Color3.fromRGB(240, 220, 190)
	label.Text = ""
	label.Parent = statusBar
	return label
end

local nightRoundLabel = makeStatusLabel()
local tipsLabel = makeStatusLabel()
local scoreLabel = makeStatusLabel()
local handsDiscardsLabel = makeStatusLabel()

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

-- ----- Message banner (hand result / round result) -----

local messageLabel = Instance.new("TextLabel")
messageLabel.Name = "Message"
messageLabel.Size = UDim2.new(1, 0, 0, 30)
messageLabel.Position = UDim2.new(0, 0, 0, 60)
messageLabel.BackgroundTransparency = 1
messageLabel.Font = Enum.Font.Gotham
messageLabel.TextSize = 16
messageLabel.TextColor3 = Color3.fromRGB(255, 214, 130)
messageLabel.Text = ""
messageLabel.Parent = root

-- ----- Hand area -----

local handFrame = Instance.new("Frame")
handFrame.Name = "HandFrame"
handFrame.Size = UDim2.new(1, -40, 0, 160)
handFrame.Position = UDim2.new(0, 20, 1, -230)
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
actionFrame.Size = UDim2.new(1, -40, 0, 50)
actionFrame.Position = UDim2.new(0, 20, 1, -60)
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
local discardButton = makeActionButton("Discard")

-- ----- Shop overlay -----

local shopFrame = Instance.new("Frame")
shopFrame.Name = "Shop"
shopFrame.Size = UDim2.fromScale(0.6, 0.6)
shopFrame.Position = UDim2.fromScale(0.2, 0.2)
shopFrame.BackgroundColor3 = Color3.fromRGB(40, 30, 22)
shopFrame.Visible = false
shopFrame.Parent = root
polishPanel(shopFrame, 16)
addSoftShadow(shopFrame, 18)

local shopTitle = Instance.new("TextLabel")
shopTitle.Size = UDim2.new(1, 0, 0, 40)
shopTitle.BackgroundTransparency = 1
shopTitle.Font = Enum.Font.GothamBold
shopTitle.TextSize = 22
shopTitle.TextColor3 = Color3.fromRGB(250, 240, 220)
shopTitle.Text = "The Bar -- spend your Tips"
shopTitle.Parent = shopFrame

local shopOffersFrame = Instance.new("Frame")
shopOffersFrame.Size = UDim2.new(1, -20, 1, -100)
shopOffersFrame.Position = UDim2.new(0, 10, 0, 45)
shopOffersFrame.BackgroundTransparency = 1
shopOffersFrame.Parent = shopFrame

local shopOffersLayout = Instance.new("UIListLayout")
shopOffersLayout.Padding = UDim.new(0, 8)
shopOffersLayout.Parent = shopOffersFrame

local nextRoundButton = Instance.new("TextButton")
nextRoundButton.Size = UDim2.new(0, 200, 0, 40)
nextRoundButton.Position = UDim2.new(0.5, -100, 1, -50)
nextRoundButton.Font = Enum.Font.GothamBold
nextRoundButton.TextSize = 18
nextRoundButton.Text = "Next Round"
nextRoundButton.BackgroundColor3 = Color3.fromRGB(90, 60, 30)
nextRoundButton.TextColor3 = Color3.fromRGB(250, 240, 220)
nextRoundButton.Parent = shopFrame
polishButton(nextRoundButton, 10)

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

-- ===== How to Play overlay (reachable from menu or in-game) =====

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

local howToPlayIntro = Instance.new("TextLabel")
howToPlayIntro.Size = UDim2.new(1, 0, 0, 150)
howToPlayIntro.BackgroundTransparency = 1
howToPlayIntro.Font = Enum.Font.Gotham
howToPlayIntro.TextSize = 15
howToPlayIntro.TextColor3 = Color3.fromRGB(235, 225, 210)
howToPlayIntro.TextWrapped = true
howToPlayIntro.TextXAlignment = Enum.TextXAlignment.Left
howToPlayIntro.TextYAlignment = Enum.TextYAlignment.Top
howToPlayIntro.ZIndex = 21
howToPlayIntro.LayoutOrder = 1
howToPlayIntro.Text = table.concat({
	"- Click cards in your hand to select up to 5 of them.",
	"- Click Play Hand to score the best poker hand among your selected cards",
	"  (Pair, Flush, Full House, etc). Chips x Mult = your score.",
	"- Reach the round's target score before you run out of hands to win it.",
	"- Not happy with your hand? Use a Discard to swap selected cards for new ones",
	"  (this doesn't cost you a hand).",
	"- Win a round and visit The Bar to spend Tips on Patrons -- helpers that",
	"  boost your future hands.",
	"- Survive as many Nights as you can. Good luck!",
	"",
	"Here's exactly how scoring works, with real examples:",
}, "\n")
howToPlayIntro.Parent = howToPlayScroll

local EXAMPLE_HANDS = {
	{
		{ rank = 7, suit = "Hearts" },
		{ rank = 7, suit = "Spades" },
	},
	{
		{ rank = 9, suit = "Diamonds" },
		{ rank = 9, suit = "Clubs" },
		{ rank = 9, suit = "Spades" },
		{ rank = 2, suit = "Hearts" },
		{ rank = 2, suit = "Diamonds" },
	},
	{
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
	exampleRow.LayoutOrder = 1 + exampleIndex
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
	playSfx(SOUND_IDS.uiClick)
	howToPlayBackdrop.Visible = false
end)

local function openHowToPlay()
	playSfx(SOUND_IDS.uiClick)
	howToPlayBackdrop.Visible = true
end

menuHowToPlayButton.MouseButton1Click:Connect(openHowToPlay)
helpButton.MouseButton1Click:Connect(openHowToPlay)

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
	playSfx(SOUND_IDS.uiClick)
	themesBackdrop.Visible = false
end)

-- Forward-declared: assigned further down once client-side state (like
-- latestState) exists. Lua closures capture the local by reference, so
-- this works as long as the assignment happens before it's ever called.
local refreshThemesList

themesButton.MouseButton1Click:Connect(function()
	playSfx(SOUND_IDS.uiClick)
	if refreshThemesList then
		refreshThemesList()
	end
	themesBackdrop.Visible = true
end)

-- ===== Road Ahead (journey/roadmap) overlay =====
-- FEATURE 4: a preview of upcoming Nights/Rounds and their target scores,
-- with a "you are here" marker. Pure UI (Frames, TextLabels, UICorner) --
-- no gradients, so it's safe against the darkness bug.

local PREVIEW_NIGHTS = 3 -- how many Nights ahead to preview

local journeyBackdrop = Instance.new("Frame")
journeyBackdrop.Name = "JourneyBackdrop"
journeyBackdrop.Size = UDim2.fromScale(1, 1)
journeyBackdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
journeyBackdrop.BackgroundTransparency = 0.4
journeyBackdrop.Visible = false
journeyBackdrop.ZIndex = 20
journeyBackdrop.Parent = screenGui

local journeyPanel = Instance.new("Frame")
journeyPanel.Size = UDim2.fromScale(0.6, 0.6)
journeyPanel.Position = UDim2.fromScale(0.2, 0.2)
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
journeySubtitle.Text = "Each Night is 3 Rounds. Target scores climb every Round."
journeySubtitle.ZIndex = 21
journeySubtitle.Parent = journeyPanel

local journeyListFrame = Instance.new("Frame")
journeyListFrame.Size = UDim2.new(1, -20, 1, -130)
journeyListFrame.Position = UDim2.new(0, 10, 0, 68)
journeyListFrame.BackgroundTransparency = 1
journeyListFrame.ZIndex = 21
journeyListFrame.Parent = journeyPanel

local journeyListLayout = Instance.new("UIListLayout")
journeyListLayout.Padding = UDim.new(0, 6)
journeyListLayout.Parent = journeyListFrame

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
	playSfx(SOUND_IDS.uiClick)
	journeyBackdrop.Visible = false
end)

-- Forward-declared for the same reason as refreshThemesList above.
local refreshJourney

local function openJourney()
	playSfx(SOUND_IDS.uiClick)
	if refreshJourney then
		refreshJourney()
	end
	journeyBackdrop.Visible = true
end

journeyButton.MouseButton1Click:Connect(openJourney)
menuJourneyButton.MouseButton1Click:Connect(openJourney)

-- ===== Poker Hands reference overlay =====
-- FEATURE 6: a live lookup table -- every hand type this game recognizes,
-- its base chips/mult (straight from Scoring.HandBase, so it can't drift
-- out of sync with actual balance), and how many times you've played it
-- this run. Plain Frames/TextLabels/UICorner only, no gradients.

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

local handRefListFrame = Instance.new("ScrollingFrame")
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
	playSfx(SOUND_IDS.uiClick)
	handRefBackdrop.Visible = false
end)

-- Forward-declared for the same reason as refreshThemesList/refreshJourney
-- above -- assigned further down once latestState exists.
local refreshHandReference

handRefButton.MouseButton1Click:Connect(function()
	playSfx(SOUND_IDS.uiClick)
	if refreshHandReference then
		refreshHandReference()
	end
	handRefBackdrop.Visible = true
end)

-- ===== Menu -> game transition, volume cycling =====

menuPlayButton.MouseButton1Click:Connect(function()
	playSfx(SOUND_IDS.uiClick)
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

local latestState = nil
local selected = {} -- [handIndex] = true
local hoveredIndex = nil -- single index or nil; only one card can be "pointed at"
local cardButtons = {} -- [handIndex] = TextButton
local cardScales = {} -- [handIndex] = UIScale

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

local currentTheme = Themes.getById(Themes.DefaultThemeId)
local lastEquippedThemeId = nil

local function applyTheme(themeId)
	currentTheme = Themes.getById(themeId) or Themes.getById(Themes.DefaultThemeId)
	local colors = currentTheme.colors

	tweenTo(root, { BackgroundColor3 = colors.background }, 0.25)
	tweenTo(statusBar, { BackgroundColor3 = colors.panelBg }, 0.25)
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
				playSfx(SOUND_IDS.uiClick)
				EquipThemeRemote:FireServer(theme.id)
			end)
		else
			actionButton.Text = string.format("Buy (%d)", theme.price)
			actionButton.MouseButton1Click:Connect(function()
				playSfx(SOUND_IDS.buyPatron)
				BuyThemeRemote:FireServer(theme.id)
			end)
		end
	end
end

refreshThemesList = refreshThemesListImpl

-- ----- Journey / roadmap -----

local function refreshJourneyImpl()
	for _, child in ipairs(journeyListFrame:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	local currentNight = (latestState and latestState.night) or 1
	local currentRound = (latestState and latestState.round) or 1

	for night = 1, PREVIEW_NIGHTS do
		local nightRow = Instance.new("Frame")
		nightRow.Size = UDim2.new(1, 0, 0, 54)
		nightRow.BackgroundTransparency = 1
		nightRow.LayoutOrder = night
		nightRow.Parent = journeyListFrame

		local nightLabel = Instance.new("TextLabel")
		nightLabel.Size = UDim2.new(0, 70, 1, 0)
		nightLabel.BackgroundTransparency = 1
		nightLabel.Font = Enum.Font.GothamBold
		nightLabel.TextSize = 15
		nightLabel.TextColor3 = Color3.fromRGB(240, 220, 190)
		nightLabel.Text = string.format("Night %d", night)
		nightLabel.Parent = nightRow

		local pipsHolder = Instance.new("Frame")
		pipsHolder.Size = UDim2.new(1, -80, 1, 0)
		pipsHolder.Position = UDim2.new(0, 80, 0, 0)
		pipsHolder.BackgroundTransparency = 1
		pipsHolder.Parent = nightRow

		local pipsLayout = Instance.new("UIListLayout")
		pipsLayout.FillDirection = Enum.FillDirection.Horizontal
		pipsLayout.VerticalAlignment = Enum.VerticalAlignment.Center
		pipsLayout.Padding = UDim.new(0, 10)
		pipsLayout.Parent = pipsHolder

		for round = 1, 3 do
			local isPast = (night < currentNight) or (night == currentNight and round < currentRound)
			local isCurrent = (night == currentNight and round == currentRound)

			local pip = Instance.new("Frame")
			pip.Size = isCurrent and UDim2.new(0, 60, 0, 44) or UDim2.new(0, 52, 0, 38)
			pip.BackgroundColor3 = isCurrent and currentTheme.colors.cardSelected
				or (isPast and Color3.fromRGB(90, 130, 90) or Color3.fromRGB(60, 45, 32))
			pip.Parent = pipsHolder
			roundCorner(pip, 10)

			local pipLabel = Instance.new("TextLabel")
			pipLabel.Size = UDim2.fromScale(1, 1)
			pipLabel.BackgroundTransparency = 1
			pipLabel.Font = Enum.Font.GothamBold
			pipLabel.TextSize = isCurrent and 15 or 13
			pipLabel.TextColor3 = isCurrent and Color3.fromRGB(30, 24, 18) or Color3.fromRGB(240, 230, 215)
			local targetScore = RunStateEngine.targetScoreFor(night, round)
			if isPast then
				pipLabel.Text = string.format("R%d ✓", round)
			else
				pipLabel.Text = string.format("R%d\n%d pts", round, targetScore)
			end
			pipLabel.Parent = pip
		end
	end
end

refreshJourney = refreshJourneyImpl

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
	local fanLift = 0
	if hoveredIndex ~= nil and not isHovering then
		local distance = math.abs(index - hoveredIndex)
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
	playSfx(SOUND_IDS.cardToggle, 0.5)
	refreshCardVisual(index, true)
end

local function rebuildHand(handData)
	for _, child in ipairs(handFrame:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	cardButtons = {}
	cardScales = {}
	selected = {}
	hoveredIndex = nil

	for index, card in ipairs(handData) do
		-- A fixed-size "slot" keeps UIListLayout stable; the button inside
		-- it can grow past the slot's bounds on hover/select without
		-- shoving the other cards around.
		local slot = Instance.new("Frame")
		slot.Size = UDim2.new(0, 70, 0, 100)
		slot.BackgroundTransparency = 1
		slot.LayoutOrder = index
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

		cardButtons[index] = button
		cardScales[index] = scaleObject

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

local function rebuildShop(shopOffers)
	for _, child in ipairs(shopOffersFrame:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	for _, offer in ipairs(shopOffers) do
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, 0, 0, 50)
		row.BackgroundColor3 = Color3.fromRGB(60, 45, 32)
		row.Parent = shopOffersFrame
		polishPanel(row, 10)

		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(1, -110, 1, 0)
		label.Position = UDim2.new(0, 10, 0, 0)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.Gotham
		label.TextSize = 15
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextColor3 = Color3.fromRGB(250, 240, 220)
		label.Text = string.format("%s (%d tips) -- %s", offer.name, offer.price, offer.description)
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
			playSfx(SOUND_IDS.buyPatron)
			BuyPatronRemote:FireServer(offer.id)
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
	scoreLabel.Text = string.format("Score: %d / %d", state.roundScore, state.targetScore)
	handsDiscardsLabel.Text = string.format("Hands: %d  Discards: %d", state.handsRemaining, state.discardsRemaining)

	rebuildHand(state.hand)

	if themesBackdrop.Visible then
		refreshThemesList() -- keep the panel accurate if it's open across a purchase
	end
	if journeyBackdrop.Visible then
		refreshJourney() -- keep "you are here" accurate if it's open across a round change
	end

	shopFrame.Visible = (state.phase == "shop")
	gameOverFrame.Visible = (state.phase == "gameover")
	if state.phase == "shop" then
		rebuildShop(state.shopOffers)
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
		messageLabel.Text = "Select 1-5 cards first."
		return
	end
	playSfx(SOUND_IDS.playHand)
	PlayHandRemote:FireServer(indices)
end)

discardButton.MouseButton1Click:Connect(function()
	if not latestState or latestState.phase ~= "playing" then
		return
	end
	if latestState.discardsRemaining <= 0 then
		messageLabel.Text = "No discards left this round."
		return
	end
	local indices = selectedIndicesArray()
	if #indices < 1 then
		messageLabel.Text = "Select 1-5 cards to discard."
		return
	end
	playSfx(SOUND_IDS.uiClick)
	DiscardRemote:FireServer(indices)
end)

nextRoundButton.MouseButton1Click:Connect(function()
	playSfx(SOUND_IDS.uiClick)
	AdvanceRoundRemote:FireServer()
end)

playAgainButton.MouseButton1Click:Connect(function()
	playSfx(SOUND_IDS.uiClick)
	RestartRunRemote:FireServer()
end)

StateUpdatedRemote.OnClientEvent:Connect(function(state)
	render(state)
end)
