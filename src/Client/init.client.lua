--[[
	Client/init.client.lua
	Built entirely in code (no pre-made UI in Studio) so it works the moment
	you sync with Rojo. Nothing here is precious; feel free to gut this file
	once you're comfortable in Studio.

	This version adds: a hover "fan" effect on cards (hovering one lifts it
	and gently lifts its neighbors, falling off with distance), rounded
	corners + soft shadows + gloss on buttons/panels, a How to Play overlay
	with worked examples (the numbers are computed LIVE from the real
	HandEvaluator/Scoring modules, so they can never drift out of sync with
	actual game balance), a "Road Ahead" journey/roadmap overlay reachable
	from the menu or in-game, and a free volume-cycle button (loud / quiet /
	muted -- no paywall, per design decision).

	See the SOUND_IDS block below -- you still need to plug in real asset
	IDs from Roblox's audio library before you'll hear anything.
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

-- The engine is plain Lua with no Roblox API calls, so the client can
-- require it directly for read-only/pure-function use: static content
-- (Themes) and pure math (RunState.targetScoreFor, HandEvaluator, Scoring
-- for the tutorial examples). None of this touches gameplay state -- the
-- server remains the sole authority on that.
local Engine = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine")
local Themes = require(Engine.Themes)
local RunStateEngine = require(Engine.RunState)
local HandEvaluator = require(Engine.HandEvaluator)
local Scoring = require(Engine.Scoring)

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

-- Free for everyone: cycle loud -> quiet -> muted. No paywall.
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

-- ===== Visual polish helpers (rounded corners, soft gloss, soft shadow) =====
-- Applied everywhere so the whole game reads as one consistent, friendly,
-- rounded style instead of flat retro rectangles.

local function roundCorner(instance, radius)
	if instance:FindFirstChildOfClass("UICorner") then
		return
	end
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius or 10)
	corner.Parent = instance
end

local function addGloss(instance)
	if instance:FindFirstChildOfClass("UIGradient") then
		return
	end
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 255, 255)),
	})
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.75),
		NumberSequenceKeypoint.new(0.5, 0.9),
		NumberSequenceKeypoint.new(1, 1),
	})
	gradient.Parent = instance
end

local function polishButton(instance, radius)
	roundCorner(instance, radius or 10)
	addGloss(instance)
end

local function polishPanel(instance, radius)
	roundCorner(instance, radius or 16)
end

-- A soft drop shadow behind a panel -- pure UI trick (an offset, blurred-
-- looking translucent frame), no image assets required so there's nothing
-- to hallucinate an asset id for.
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
polishPanel(statusBar, 0) -- flush with the top edge -- no rounding, just here for consistency

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

-- ----- Corner icon buttons: volume / help / themes / journey -----

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
	polishButton(button, 12)
	return button
end

local volumeButton = makeCornerButton(VOLUME_ICONS[volumeStepIndex], -60)
local helpButton = makeCornerButton("?", -110)
local themesButton = makeCornerButton("🎨", -160)
local journeyButton = makeCornerButton("🗺", -210)

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
handFrame.Size = UDim2.new(1, -40, 0, 170)
handFrame.Position = UDim2.new(0, 20, 1, -240)
handFrame.BackgroundTransparency = 1
handFrame.Parent = root

local handLayout = Instance.new("UIListLayout")
handLayout.FillDirection = Enum.FillDirection.Horizontal
handLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
handLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
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
shopFrame.ZIndex = 2
shopFrame.Parent = root
polishPanel(shopFrame)
addSoftShadow(shopFrame)

local shopTitle = Instance.new("TextLabel")
shopTitle.Size = UDim2.new(1, 0, 0, 40)
shopTitle.BackgroundTransparency = 1
shopTitle.Font = Enum.Font.GothamBold
shopTitle.TextSize = 22
shopTitle.TextColor3 = Color3.fromRGB(250, 240, 220)
shopTitle.Text = "The Bar -- spend your Tips"
shopTitle.ZIndex = 2
shopTitle.Parent = shopFrame

local shopOffersFrame = Instance.new("Frame")
shopOffersFrame.Size = UDim2.new(1, -20, 1, -100)
shopOffersFrame.Position = UDim2.new(0, 10, 0, 45)
shopOffersFrame.BackgroundTransparency = 1
shopOffersFrame.ZIndex = 2
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
nextRoundButton.ZIndex = 2
nextRoundButton.Parent = shopFrame
polishButton(nextRoundButton, 12)

-- ----- Game over overlay -----

local gameOverFrame = Instance.new("Frame")
gameOverFrame.Name = "GameOver"
gameOverFrame.Size = UDim2.fromScale(0.5, 0.3)
gameOverFrame.Position = UDim2.fromScale(0.25, 0.35)
gameOverFrame.BackgroundColor3 = Color3.fromRGB(40, 30, 22)
gameOverFrame.Visible = false
gameOverFrame.ZIndex = 2
gameOverFrame.Parent = root
polishPanel(gameOverFrame)
addSoftShadow(gameOverFrame)

local gameOverLabel = Instance.new("TextLabel")
gameOverLabel.Size = UDim2.new(1, 0, 0, 60)
gameOverLabel.BackgroundTransparency = 1
gameOverLabel.Font = Enum.Font.GothamBold
gameOverLabel.TextSize = 22
gameOverLabel.TextColor3 = Color3.fromRGB(250, 240, 220)
gameOverLabel.Text = "Last call! Your run has ended."
gameOverLabel.ZIndex = 2
gameOverLabel.Parent = gameOverFrame

local playAgainButton = Instance.new("TextButton")
playAgainButton.Size = UDim2.new(0, 200, 0, 40)
playAgainButton.Position = UDim2.new(0.5, -100, 1, -60)
playAgainButton.Font = Enum.Font.GothamBold
playAgainButton.TextSize = 18
playAgainButton.Text = "Play Again"
playAgainButton.BackgroundColor3 = Color3.fromRGB(90, 60, 30)
playAgainButton.TextColor3 = Color3.fromRGB(250, 240, 220)
playAgainButton.ZIndex = 2
playAgainButton.Parent = gameOverFrame
polishButton(playAgainButton, 12)

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
menuTitle.Position = UDim2.fromScale(0, 0.24)
menuTitle.BackgroundTransparency = 1
menuTitle.Font = Enum.Font.GothamBold
menuTitle.TextSize = 48
menuTitle.TextColor3 = Color3.fromRGB(255, 214, 130)
menuTitle.Text = "Wildcard Tavern"
menuTitle.ZIndex = 10
menuTitle.Parent = menuFrame

local menuSubtitle = Instance.new("TextLabel")
menuSubtitle.Size = UDim2.new(1, 0, 0, 30)
menuSubtitle.Position = UDim2.fromScale(0, 0.36)
menuSubtitle.BackgroundTransparency = 1
menuSubtitle.Font = Enum.Font.Gotham
menuSubtitle.TextSize = 18
menuSubtitle.TextColor3 = Color3.fromRGB(200, 180, 160)
menuSubtitle.Text = "a poker-hand deckbuilder -- working title"
menuSubtitle.ZIndex = 10
menuSubtitle.Parent = menuFrame

local menuButtonHolder = Instance.new("Frame")
menuButtonHolder.Size = UDim2.new(0, 240, 0, 168)
menuButtonHolder.Position = UDim2.fromScale(0.5, 0.48)
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
-- Includes worked examples computed LIVE from the real HandEvaluator and
-- Scoring modules -- these numbers can never drift out of sync with
-- actual game balance, even if you retune Scoring.HandBase later.

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
polishPanel(howToPlayPanel)
addSoftShadow(howToPlayPanel)

local howToPlayTitle = Instance.new("TextLabel")
howToPlayTitle.Size = UDim2.new(1, 0, 0, 40)
howToPlayTitle.BackgroundTransparency = 1
howToPlayTitle.Font = Enum.Font.GothamBold
howToPlayTitle.TextSize = 22
howToPlayTitle.TextColor3 = Color3.fromRGB(250, 240, 220)
howToPlayTitle.Text = "How to Play"
howToPlayTitle.ZIndex = 21
howToPlayTitle.Parent = howToPlayPanel

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
howToPlayIntro.Size = UDim2.new(1, 0, 0, 130)
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
	"- Click Play Hand to score the best poker hand among your selected cards.",
	"- Reach the round's target score before you run out of hands to win it.",
	"- Discards swap selected cards for new ones without costing you a hand.",
	"- Win a round and visit The Bar to spend Tips on Patrons that boost future hands.",
	"- Survive as many Nights as you can!",
	"",
	"Here's exactly how scoring works, with real examples:",
}, "\n")
howToPlayIntro.Parent = howToPlayScroll

-- ----- Worked examples: built from real Card tables and run through the
-- actual HandEvaluator + Scoring modules, so the numbers shown are always
-- exactly what you'd see in a real game. -----

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
polishButton(howToPlayCloseButton, 12)

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
polishPanel(themesPanel)
addSoftShadow(themesPanel)

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
polishButton(themesCloseButton, 12)

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
-- Shows the Night/Round structure of a run and highlights where you
-- currently are. No save data involved -- like the rest of the run state,
-- this reflects the CURRENT run only and resets when it does.

local PREVIEW_NIGHTS = 3 -- how many Nights ahead to preview (the run itself continues indefinitely)

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
polishPanel(journeyPanel)
addSoftShadow(journeyPanel)

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
journeySubtitle.TextSize = 13
journeySubtitle.TextColor3 = Color3.fromRGB(200, 185, 165)
journeySubtitle.TextXAlignment = Enum.TextXAlignment.Left
journeySubtitle.Text = "Each Night has 3 Rounds. Rounds get tougher as you go -- and it keeps going after this preview."
journeySubtitle.ZIndex = 21
journeySubtitle.Parent = journeyPanel

local journeyListFrame = Instance.new("Frame")
journeyListFrame.Size = UDim2.new(1, -20, 1, -140)
journeyListFrame.Position = UDim2.new(0, 10, 0, 68)
journeyListFrame.BackgroundTransparency = 1
journeyListFrame.ZIndex = 21
journeyListFrame.Parent = journeyPanel

local journeyListLayout = Instance.new("UIListLayout")
journeyListLayout.Padding = UDim.new(0, 10)
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
local SELECTED_SCALE_BONUS = 0.05
local MAX_HOVER_SCALE_BONUS = 0.12
local SELECTED_LIFT = 10 -- pixels a selected card sits above baseline, even unhovered
local MAX_HOVER_LIFT = 26 -- pixels the directly-hovered card lifts
local HOVER_FALLOFF_DISTANCE = 3 -- neighbors this many slots away or farther get no lift

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
		roundCorner(swatch, 8)

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
		polishButton(actionButton, 10)

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
			elseif isCurrent then
				pipLabel.Text = string.format("R%d\n%d pts", round, targetScore)
			else
				pipLabel.Text = string.format("R%d\n%d pts", round, targetScore)
			end
			pipLabel.Parent = pip
		end
	end
end

refreshJourney = refreshJourneyImpl

local function selectedIndicesArray()
	local out = {}
	for index in pairs(selected) do
		table.insert(out, index)
	end
	table.sort(out)
	return out
end

-- ----- Card hover "fan": hovering a card lifts it; neighbors lift too,
-- falling off with distance, so it's always crystal clear which card is
-- actually being pointed at. -----

local function computeCardTarget(index)
	local isSelected = selected[index] == true
	local distance = hoveredIndex and math.abs(index - hoveredIndex) or nil
	local hoverFalloff = 0
	if distance ~= nil and distance < HOVER_FALLOFF_DISTANCE then
		hoverFalloff = 1 - (distance / HOVER_FALLOFF_DISTANCE)
	end

	local lift = (isSelected and SELECTED_LIFT or 0) + hoverFalloff * MAX_HOVER_LIFT
	local scale = BASE_SCALE + (isSelected and SELECTED_SCALE_BONUS or 0) + hoverFalloff * MAX_HOVER_SCALE_BONUS

	local color
	if isSelected then
		color = currentTheme.colors.cardSelected
	else
		color = currentTheme.colors.cardBase:Lerp(currentTheme.colors.cardSelected, hoverFalloff * 0.35)
	end

	return lift, scale, color
end

local function applyCardVisual(index, usePop)
	local button = cardButtons[index]
	local scaleObject = cardScales[index]
	if not button or not scaleObject then
		return
	end

	local lift, scale, color = computeCardTarget(index)
	local duration = usePop and 0.22 or 0.15
	local style = usePop and Enum.EasingStyle.Back or Enum.EasingStyle.Quad

	tweenTo(button, { Position = UDim2.new(0.5, 0, 0.5, -lift), BackgroundColor3 = color }, duration, style, Enum.EasingDirection.Out)
	tweenTo(scaleObject, { Scale = scale }, duration, style, Enum.EasingDirection.Out)
end

local function refreshAllCardVisuals()
	for index in pairs(cardButtons) do
		applyCardVisual(index, false)
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
	applyCardVisual(index, true)
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
		-- it can grow/lift past the slot's bounds on hover/select without
		-- shoving the other cards around.
		local slot = Instance.new("Frame")
		slot.Size = UDim2.new(0, 70, 0, 140) -- tall enough to show the lift headroom
		slot.BackgroundTransparency = 1
		slot.LayoutOrder = index
		slot.Parent = handFrame

		local button = Instance.new("TextButton")
		button.Size = UDim2.new(0, 70, 0, 100)
		button.Position = UDim2.fromScale(0.5, 1) -- anchored to the bottom of the tall slot
		button.AnchorPoint = Vector2.new(0.5, 1)
		button.Font = Enum.Font.GothamBold
		button.TextSize = 20
		button.BackgroundColor3 = currentTheme.colors.cardBase
		button.TextColor3 = RED_SUITS[card.suit] and Color3.fromRGB(180, 30, 30) or Color3.fromRGB(20, 20, 20)
		button.Text = string.format("%s\n%s", RANK_NAMES[card.rank] or tostring(card.rank), SUIT_SYMBOLS[card.suit] or "?")
		button.Parent = slot
		polishButton(button, 10)

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
		row.ZIndex = 2
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
		label.ZIndex = 2
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
		buyButton.ZIndex = 2
		buyButton.Parent = row
		polishButton(buyButton, 10)

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
