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
local StartRunRemote = remotes:WaitForChild("StartRun")
local StateUpdatedRemote = remotes:WaitForChild("StateUpdated")

-- The engine is plain Lua with no Roblox API calls, so the client can
-- require it directly for read-only/pure-function use: static content
-- (Themes, DeckVariants, DifficultyTiers, BossRounds) and pure math
-- (RunState.targetScoreFor, HandEvaluator, Scoring for the tutorial
-- examples). None of this touches gameplay state -- the server remains the
-- sole authority on that.
local Engine = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine")
local Themes = require(Engine.Themes)
local RunStateEngine = require(Engine.RunState)
local HandEvaluator = require(Engine.HandEvaluator)
local Scoring = require(Engine.Scoring)
local DeckVariants = require(Engine.DeckVariants)
local DifficultyTiers = require(Engine.DifficultyTiers)
local BossRounds = require(Engine.BossRounds)
local Deck = require(Engine.Deck)
local Patrons = require(Engine.Patrons)

local RANK_NAMES = {
	[2] = "2", [3] = "3", [4] = "4", [5] = "5", [6] = "6", [7] = "7", [8] = "8", [9] = "9", [10] = "10",
	[11] = "J", [12] = "Q", [13] = "K", [14] = "A",
}
local SUIT_SYMBOLS = { Hearts = "♥", Diamonds = "♦", Clubs = "♣", Spades = "♠" }
local RED_SUITS = { Hearts = true, Diamonds = true }
local SUIT_DISPLAY_ORDER = { "Spades", "Hearts", "Clubs", "Diamonds" }

-- ===== Settings (client-local only) =====
-- These live in memory for this play session and reset when you rejoin --
-- there's no DataStore/save-across-sessions in this MVP (a deliberate
-- scope call; see the Themes.lua comment for the same tradeoff on
-- cosmetics). Every number here is a 0-100 percentage; code that consumes
-- them divides by 100.
local settings = {
	masterVolume = 50,
	musicVolume = 100,
	sfxVolume = 100,
	animationSpeed = 100, -- 50 = half speed (slower/longer tweens), 200 = double speed
	screenshakeIntensity = 50,
	reducedMotion = false,
	highContrastCards = false,
}

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

-- Free for everyone: cycle loud -> quiet -> muted via the toolbar button.
-- No paywall -- these are just presets for settings.masterVolume; the
-- Settings overlay's Audio tab lets you fine-tune every 10%.
local VOLUME_PRESETS = { 50, 20, 0 }
local VOLUME_ICONS = { "♪", "♩", "×" }
local volumePresetIndex = 1

local function currentVolumeIcon()
	if settings.masterVolume <= 0 then
		return "×"
	elseif settings.masterVolume <= 25 then
		return "♩"
	else
		return "♪"
	end
end

local function applyMusicVolume()
	backgroundMusic.Volume = (settings.masterVolume / 100) * (settings.musicVolume / 100)
	if backgroundMusic.Volume <= 0 then
		backgroundMusic:Stop()
	elseif backgroundMusic.SoundId ~= "rbxassetid://0" and not backgroundMusic.IsPlaying then
		backgroundMusic:Play()
	end
end

applyMusicVolume()

local function playSfx(soundId, volume)
	if not soundId or soundId == "" or soundId == "rbxassetid://0" then
		return -- placeholder id, nothing to play yet
	end
	local effectiveVolume = (volume or 0.6) * (settings.masterVolume / 100) * (settings.sfxVolume / 100)
	if effectiveVolume <= 0 then
		return
	end
	local sfx = Instance.new("Sound")
	sfx.SoundId = soundId
	sfx.Volume = effectiveVolume
	sfx.Parent = SoundService
	sfx:Play()
	task.delay(5, function()
		if sfx then
			sfx:Destroy()
		end
	end)
end

-- ===== Tween helper =====
-- Every tween in the game routes through here so the Settings overlay's
-- Animation Speed slider and Reduced Motion toggle affect the whole game
-- uniformly, instead of needing to be threaded through every call site.

local function scaledDuration(duration)
	if settings.reducedMotion then
		return math.min(duration, 0.08)
	end
	local speedFactor = math.max(settings.animationSpeed, 10) / 100
	return duration / speedFactor
end

local function tweenTo(instance, properties, duration, style, direction)
	local tween = TweenService:Create(
		instance,
		TweenInfo.new(scaledDuration(duration), style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out),
		properties
	)
	tween:Play()
	return tween
end

-- ===== Screen shake (a small, tasteful jolt on big moments) =====

local function screenShake(root, magnitude)
	local intensity = settings.screenshakeIntensity / 100
	if settings.reducedMotion or intensity <= 0 then
		return
	end
	magnitude = (magnitude or 6) * intensity
	local originalPosition = root.Position
	local shakes = 4
	local function step(n)
		if n > shakes then
			tweenTo(root, { Position = originalPosition }, 0.06)
			return
		end
		local offset = UDim2.new(0, (math.random() - 0.5) * 2 * magnitude, 0, (math.random() - 0.5) * 2 * magnitude)
		tweenTo(root, { Position = originalPosition + offset }, 0.05)
		task.delay(scaledDuration(0.05), function()
			step(n + 1)
		end)
	end
	step(1)
end

-- ===== Visual polish helpers (rounded corners, soft shadow) =====
-- Applied everywhere so the whole game reads as one consistent, friendly,
-- rounded style instead of flat retro rectangles.
--
-- NOTE: this used to also have an addGloss() that layered a near-white
-- UIGradient on top using a Transparency sequence of 0.75 -> 0.9 -> 1.0 to
-- fake a subtle highlight. In Roblox, UIGradient.Transparency overrides how
-- see-through the object is at each point rather than adding a highlight on
-- top of its own color -- so at 75-100% transparent across nearly the whole
-- surface, buttons/cards were mostly see-through to the dark background
-- behind them. That was the actual cause of the long-running "everything
-- looks dark in Play mode" bug. Removed for good; rounded corners alone are
-- zero-risk since they don't touch color or transparency.

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

-- ----- Toolbar: a vertical stack of icon buttons, top-right. A vertical
-- list (instead of hand-placed corner buttons with manual x-offsets) means
-- adding a new button is just one more makeToolbarButton call -- nothing
-- else needs to shift. -----

local toolbarFrame = Instance.new("Frame")
toolbarFrame.Name = "Toolbar"
toolbarFrame.Size = UDim2.new(0, 44, 0, 0)
toolbarFrame.AutomaticSize = Enum.AutomaticSize.Y
toolbarFrame.Position = UDim2.new(1, -54, 0, 8)
toolbarFrame.BackgroundTransparency = 1
toolbarFrame.ZIndex = 5
toolbarFrame.Parent = root

local toolbarLayout = Instance.new("UIListLayout")
toolbarLayout.Padding = UDim.new(0, 8)
toolbarLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
toolbarLayout.Parent = toolbarFrame

local function makeToolbarButton(text)
	local button = Instance.new("TextButton")
	button.Size = UDim2.new(0, 44, 0, 44)
	button.Font = Enum.Font.GothamBold
	button.TextSize = 20
	button.Text = text
	button.BackgroundColor3 = Color3.fromRGB(60, 45, 32)
	button.TextColor3 = Color3.fromRGB(250, 240, 220)
	button.ZIndex = 5
	button.Parent = toolbarFrame
	polishButton(button, 12)
	return button
end

local volumeButton = makeToolbarButton(VOLUME_ICONS[1])
local helpButton = makeToolbarButton("?")
local themesButton = makeToolbarButton("🎨")
local journeyButton = makeToolbarButton("🗺")
local handRefButton = makeToolbarButton("♣")
local deckTrackerButton = makeToolbarButton("🂠")
local collectionButton = makeToolbarButton("★")
local settingsButton = makeToolbarButton("⚙")

-- ----- Boss Round banner: appears under the status bar only during a
-- Night's final round, so it's obvious something's different about it. -----

local bossBanner = Instance.new("Frame")
bossBanner.Name = "BossBanner"
bossBanner.Size = UDim2.new(1, -40, 0, 40)
bossBanner.Position = UDim2.new(0, 20, 0, 66)
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

-- ----- Message banner (hand result / round result) -----

local messageLabel = Instance.new("TextLabel")
messageLabel.Name = "Message"
messageLabel.Size = UDim2.new(1, 0, 0, 30)
messageLabel.Position = UDim2.new(0, 0, 0, 112)
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
menuButtonHolder.Size = UDim2.new(0, 240, 0, 228)
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
local menuNewRunButton = makeMenuButton("New Run...")
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

-- Forward-declared: assigned much further down (in the "Client-side state"
-- section) once card-rendering state exists. The High Contrast Cards
-- toggle below needs to call it immediately when flipped, well before
-- that section runs -- same forward-declaration pattern as
-- refreshThemesList/refreshJourney above.
local rebuildHand

--[[
	The rest of this file builds a LOT of UI. Lua/Luau caps a single
	function at 200 active local variables, and this whole script is one
	big top-level "main function" -- so every overlay below is wrapped in
	its own `do ... end` block. Locals declared inside a `do...end` go out
	of scope (and free their slot) at that block's `end`, which is what
	keeps the running total under the cap even though we build a dozen+
	overlays. Only the handful of names another part of the file actually
	needs later (a backdrop's .Visible, a "refresh this overlay" function)
	are forward-declared here and assigned (without `local`) inside their
	block, same pattern as rebuildHand/refreshThemesList/refreshJourney.
]]
local latestState = nil
local handRefBackdrop
local refreshHandReferenceImpl
local deckTrackerBackdrop
local refreshDeckTrackerImpl
local settingsBackdrop
local settingsRefreshAudioTab
local newRunFromSettingsButton
local collectionBackdrop
local refreshCollectionImpl
local showUnlockPopup
local lastOwnedPatronIds = {}
local lastOwnedThemeIds = {}
local hasRenderedOnce = false

-- ===== Reusable small UI helpers: stepper rows + toggle rows =====
-- Used by the Settings overlay. Roblox has no built-in drag-slider widget,
-- so these are simple "- value +" steppers instead -- far less to get
-- wrong than hand-rolled drag physics, and just as usable.

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
		playSfx(SOUND_IDS.uiClick, 0.35)
		setValue(math.max(min, getValue() - step))
		refresh()
	end)
	plusButton.MouseButton1Click:Connect(function()
		playSfx(SOUND_IDS.uiClick, 0.35)
		setValue(math.min(max, getValue() + step))
		refresh()
	end)

	refresh()
	return refresh
end

local function makeToggleRow(parent, labelText, getValue, setValue)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, 46)
	row.BackgroundTransparency = 1
	row.Parent = parent

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(0.6, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.Gotham
	label.TextSize = 15
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextColor3 = Color3.fromRGB(240, 230, 215)
	label.Text = labelText
	label.ZIndex = 21
	label.Parent = row

	local toggleButton = Instance.new("TextButton")
	toggleButton.Size = UDim2.new(0, 90, 0, 34)
	toggleButton.Position = UDim2.new(1, -90, 0.5, -17)
	toggleButton.Font = Enum.Font.GothamBold
	toggleButton.TextSize = 14
	toggleButton.TextColor3 = Color3.fromRGB(250, 240, 220)
	toggleButton.ZIndex = 21
	toggleButton.Parent = row
	polishButton(toggleButton, 8)

	local function refresh()
		local value = getValue()
		toggleButton.Text = value and "On" or "Off"
		toggleButton.BackgroundColor3 = value and Color3.fromRGB(70, 110, 65) or Color3.fromRGB(90, 45, 40)
	end

	toggleButton.MouseButton1Click:Connect(function()
		playSfx(SOUND_IDS.uiClick, 0.35)
		setValue(not getValue())
		refresh()
	end)

	refresh()
	return refresh
end

-- ===== Poker Hands reference overlay =====
-- A live lookup table: every hand type this game recognizes, its base
-- chips/mult (straight from Scoring.HandBase -- can't drift out of sync
-- with actual balance), and how many times you've played it this run.
do

handRefBackdrop = Instance.new("Frame")
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
polishPanel(handRefPanel)
addSoftShadow(handRefPanel)

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

refreshHandReferenceImpl = function()
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

handRefButton.MouseButton1Click:Connect(function()
	playSfx(SOUND_IDS.uiClick)
	refreshHandReferenceImpl()
	handRefBackdrop.Visible = true
end)

end -- Poker Hands reference overlay

-- ===== Deck Tracker overlay =====
-- Shows exactly how many of each card are still left to be drawn this
-- round -- reads directly off the server-computed Deck.remainingCounts
-- snapshot included in the state payload.
do

deckTrackerBackdrop = Instance.new("Frame")
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
polishPanel(deckTrackerPanel)
addSoftShadow(deckTrackerPanel)

local deckTrackerTitle = Instance.new("TextLabel")
deckTrackerTitle.Size = UDim2.new(1, 0, 0, 40)
deckTrackerTitle.BackgroundTransparency = 1
deckTrackerTitle.Font = Enum.Font.GothamBold
deckTrackerTitle.TextSize = 22
deckTrackerTitle.TextColor3 = Color3.fromRGB(250, 240, 220)
deckTrackerTitle.Text = "What's Left in the Deck"
deckTrackerTitle.ZIndex = 21
deckTrackerTitle.Parent = deckTrackerPanel

local deckTrackerGrid = Instance.new("Frame")
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
	playSfx(SOUND_IDS.uiClick)
	deckTrackerBackdrop.Visible = false
end)

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

refreshDeckTrackerImpl = function()
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

deckTrackerButton.MouseButton1Click:Connect(function()
	playSfx(SOUND_IDS.uiClick)
	refreshDeckTrackerImpl()
	deckTrackerBackdrop.Visible = true
end)

end -- Deck Tracker overlay

-- ===== Settings overlay =====
-- Game tab: animation speed / screenshake / reduced motion / high contrast.
-- Audio tab: master / music / sound-effects volume. Everything here is
-- client-local (see the `settings` table comment near the top of the
-- file) -- no save-across-sessions yet.

do

settingsBackdrop = Instance.new("Frame")
settingsBackdrop.Name = "SettingsBackdrop"
settingsBackdrop.Size = UDim2.fromScale(1, 1)
settingsBackdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
settingsBackdrop.BackgroundTransparency = 0.4
settingsBackdrop.Visible = false
settingsBackdrop.ZIndex = 20
settingsBackdrop.Parent = screenGui

local settingsPanel = Instance.new("Frame")
settingsPanel.Size = UDim2.fromScale(0.5, 0.62)
settingsPanel.Position = UDim2.fromScale(0.25, 0.19)
settingsPanel.BackgroundColor3 = Color3.fromRGB(40, 30, 22)
settingsPanel.ZIndex = 21
settingsPanel.Parent = settingsBackdrop
polishPanel(settingsPanel)
addSoftShadow(settingsPanel)

local settingsTitle = Instance.new("TextLabel")
settingsTitle.Size = UDim2.new(1, 0, 0, 40)
settingsTitle.BackgroundTransparency = 1
settingsTitle.Font = Enum.Font.GothamBold
settingsTitle.TextSize = 22
settingsTitle.TextColor3 = Color3.fromRGB(250, 240, 220)
settingsTitle.Text = "Settings"
settingsTitle.ZIndex = 21
settingsTitle.Parent = settingsPanel

local settingsTabHolder = Instance.new("Frame")
settingsTabHolder.Size = UDim2.new(1, -30, 0, 34)
settingsTabHolder.Position = UDim2.new(0, 15, 0, 42)
settingsTabHolder.BackgroundTransparency = 1
settingsTabHolder.ZIndex = 21
settingsTabHolder.Parent = settingsPanel

local settingsTabLayout = Instance.new("UIListLayout")
settingsTabLayout.FillDirection = Enum.FillDirection.Horizontal
settingsTabLayout.Padding = UDim.new(0, 8)
settingsTabLayout.Parent = settingsTabHolder

local function makeSettingsTabButton(text)
	local button = Instance.new("TextButton")
	button.Size = UDim2.new(0, 110, 1, 0)
	button.Font = Enum.Font.GothamBold
	button.TextSize = 14
	button.Text = text
	button.BackgroundColor3 = Color3.fromRGB(60, 45, 32)
	button.TextColor3 = Color3.fromRGB(250, 240, 220)
	button.ZIndex = 21
	button.Parent = settingsTabHolder
	polishButton(button, 8)
	return button
end

local settingsGameTabButton = makeSettingsTabButton("Game")
local settingsAudioTabButton = makeSettingsTabButton("Audio")

local settingsGameTab = Instance.new("Frame")
settingsGameTab.Size = UDim2.new(1, -30, 1, -160)
settingsGameTab.Position = UDim2.new(0, 15, 0, 84)
settingsGameTab.BackgroundTransparency = 1
settingsGameTab.ZIndex = 21
settingsGameTab.Parent = settingsPanel

local settingsGameLayout = Instance.new("UIListLayout")
settingsGameLayout.Padding = UDim.new(0, 4)
settingsGameLayout.Parent = settingsGameTab

local settingsAudioTab = Instance.new("Frame")
settingsAudioTab.Size = UDim2.new(1, -30, 1, -160)
settingsAudioTab.Position = UDim2.new(0, 15, 0, 84)
settingsAudioTab.BackgroundTransparency = 1
settingsAudioTab.Visible = false
settingsAudioTab.ZIndex = 21
settingsAudioTab.Parent = settingsPanel

local settingsAudioLayout = Instance.new("UIListLayout")
settingsAudioLayout.Padding = UDim.new(0, 4)
settingsAudioLayout.Parent = settingsAudioTab

makeStepperRow(settingsGameTab, "Animation Speed", 50, 200, 25, function() return settings.animationSpeed end,
	function(v) settings.animationSpeed = v end, function(v) return v .. "%" end)
makeStepperRow(settingsGameTab, "Screenshake", 0, 100, 10, function() return settings.screenshakeIntensity end,
	function(v) settings.screenshakeIntensity = v end, function(v) return v .. "%" end)
makeToggleRow(settingsGameTab, "Reduced Motion", function() return settings.reducedMotion end,
	function(v) settings.reducedMotion = v end)
makeToggleRow(settingsGameTab, "High Contrast Cards", function() return settings.highContrastCards end,
	function(v)
		settings.highContrastCards = v
		if latestState then
			rebuildHand(latestState.hand) -- re-render cards immediately with the new contrast setting
		end
	end)

newRunFromSettingsButton = Instance.new("TextButton")
newRunFromSettingsButton.Size = UDim2.new(1, 0, 0, 42)
newRunFromSettingsButton.Font = Enum.Font.GothamBold
newRunFromSettingsButton.TextSize = 15
newRunFromSettingsButton.Text = "Start a New Run..."
newRunFromSettingsButton.BackgroundColor3 = Color3.fromRGB(110, 50, 50)
newRunFromSettingsButton.TextColor3 = Color3.fromRGB(250, 240, 220)
newRunFromSettingsButton.LayoutOrder = 10
newRunFromSettingsButton.ZIndex = 21
newRunFromSettingsButton.Parent = settingsGameTab
polishButton(newRunFromSettingsButton, 10)

local refreshMasterVolumeRow = makeStepperRow(settingsAudioTab, "Master Volume", 0, 100, 10, function() return settings.masterVolume end,
	function(v)
		settings.masterVolume = v
		volumeButton.Text = currentVolumeIcon()
		applyMusicVolume()
	end, function(v) return v .. "%" end)
local refreshMusicVolumeRow = makeStepperRow(settingsAudioTab, "Music Volume", 0, 100, 10, function() return settings.musicVolume end,
	function(v)
		settings.musicVolume = v
		applyMusicVolume()
	end, function(v) return v .. "%" end)
local refreshSfxVolumeRow = makeStepperRow(settingsAudioTab, "Sound Effects Volume", 0, 100, 10, function() return settings.sfxVolume end,
	function(v) settings.sfxVolume = v end, function(v) return v .. "%" end)

-- Referenced by the toolbar volume button (defined further down the file)
-- so the sliders stay in sync if Settings is open while it's clicked.
settingsRefreshAudioTab = function()
	refreshMasterVolumeRow()
	refreshMusicVolumeRow()
	refreshSfxVolumeRow()
end

local function showSettingsTab(tab)
	settingsGameTab.Visible = (tab == "game")
	settingsAudioTab.Visible = (tab == "audio")
	settingsGameTabButton.BackgroundColor3 = (tab == "game") and Color3.fromRGB(90, 60, 30) or Color3.fromRGB(60, 45, 32)
	settingsAudioTabButton.BackgroundColor3 = (tab == "audio") and Color3.fromRGB(90, 60, 30) or Color3.fromRGB(60, 45, 32)
end

settingsGameTabButton.MouseButton1Click:Connect(function()
	playSfx(SOUND_IDS.uiClick)
	showSettingsTab("game")
end)
settingsAudioTabButton.MouseButton1Click:Connect(function()
	playSfx(SOUND_IDS.uiClick)
	showSettingsTab("audio")
end)

showSettingsTab("game")

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
	playSfx(SOUND_IDS.uiClick)
	settingsBackdrop.Visible = false
end)

settingsButton.MouseButton1Click:Connect(function()
	playSfx(SOUND_IDS.uiClick)
	settingsBackdrop.Visible = true
end)

end -- Settings overlay

-- ===== Run Setup overlay: pick a Deck Variant + Difficulty before a new
-- run begins. Reachable from the main menu ("New Run...") or from Settings
-- ("Start a New Run..." while already playing). =====

do

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
polishPanel(runSetupPanel)
addSoftShadow(runSetupPanel)

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

local function makeRunSetupSectionLabel(text, order)
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 0, 22)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = 16
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextColor3 = Color3.fromRGB(255, 214, 130)
	label.Text = text
	label.LayoutOrder = order
	label.ZIndex = 26
	label.Parent = runSetupScroll
	return label
end

local selectedDeckVariantId = DeckVariants.DefaultId
local selectedDifficultyId = DifficultyTiers.DefaultId
local deckVariantCards = {}
local difficultyCards = {}

makeRunSetupSectionLabel("Deck Variant", 1)
makeRunSetupSectionLabel("Difficulty", 19)

local function makePickCard(parent, order, name, description, isSelected)
	local card = Instance.new("Frame")
	card.Size = UDim2.new(1, 0, 0, 60)
	card.BackgroundColor3 = isSelected and Color3.fromRGB(90, 70, 40) or Color3.fromRGB(60, 45, 32)
	card.LayoutOrder = order
	card.ZIndex = 26
	card.Parent = parent
	polishPanel(card, 10)

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, -20, 0, 22)
	nameLabel.Position = UDim2.new(0, 10, 0, 4)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 15
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextColor3 = Color3.fromRGB(250, 240, 220)
	nameLabel.Text = (isSelected and "✓ " or "") .. name
	nameLabel.ZIndex = 26
	nameLabel.Parent = card

	local descLabel = Instance.new("TextLabel")
	descLabel.Size = UDim2.new(1, -20, 0, 30)
	descLabel.Position = UDim2.new(0, 10, 0, 26)
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
		local card, clickCatcher = makePickCard(runSetupScroll, 2 + i, variant.name, variant.description, variant.id == selectedDeckVariantId)
		table.insert(deckVariantCards, card)
		clickCatcher.MouseButton1Click:Connect(function()
			playSfx(SOUND_IDS.uiClick, 0.4)
			selectedDeckVariantId = variant.id
			refreshRunSetupCards()
		end)
	end

	for _, child in ipairs(difficultyCards) do
		child:Destroy()
	end
	difficultyCards = {}
	for i, tier in ipairs(DifficultyTiers.Definitions) do
		local card, clickCatcher = makePickCard(runSetupScroll, 20 + i, tier.name, tier.description, tier.id == selectedDifficultyId)
		table.insert(difficultyCards, card)
		clickCatcher.MouseButton1Click:Connect(function()
			playSfx(SOUND_IDS.uiClick, 0.4)
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
	playSfx(SOUND_IDS.uiClick)
	runSetupBackdrop.Visible = false
end)

runSetupBeginButton.MouseButton1Click:Connect(function()
	playSfx(SOUND_IDS.buyPatron)
	StartRunRemote:FireServer(selectedDeckVariantId, selectedDifficultyId)
	runSetupBackdrop.Visible = false
	settingsBackdrop.Visible = false
	menuFrame.Visible = false
	root.Visible = true
	applyMusicVolume()
end)

local function openRunSetup()
	playSfx(SOUND_IDS.uiClick)
	refreshRunSetupCards()
	runSetupBackdrop.Visible = true
end

menuNewRunButton.MouseButton1Click:Connect(openRunSetup)
newRunFromSettingsButton.MouseButton1Click:Connect(openRunSetup)

end -- Run Setup overlay

-- ===== Collection Gallery overlay =====
-- A grid of every Patron and Theme in the game -- owned ones shown in
-- full, locked ones silhouetted with a "?". Session-scoped like the rest
-- of the run state: it tracks what you've found THIS run, not across
-- sessions (no DataStore yet -- see the Themes.lua comment).

do

collectionBackdrop = Instance.new("Frame")
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
polishPanel(collectionPanel)
addSoftShadow(collectionPanel)

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
	playSfx(SOUND_IDS.uiClick)
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

local function makeCollectionRow(order, name, description, isOwned, swatchColor)
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
	swatchLabel.Text = isOwned and "" or "?"
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

refreshCollectionImpl = function()
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
		makeCollectionRow(1 + i, patron.name, patron.description, ownedPatronIds[patron.id] == true, Color3.fromRGB(200, 170, 100))
	end

	makeCollectionSectionHeader(string.format("Themes -- %d / %d found", ownedThemeCount, #Themes.Definitions), 100)
	for i, theme in ipairs(Themes.Definitions) do
		makeCollectionRow(100 + i, theme.name, theme.description, ownedThemeIds[theme.id] == true, theme.colors.accent)
	end
end

collectionButton.MouseButton1Click:Connect(function()
	playSfx(SOUND_IDS.uiClick)
	refreshCollectionImpl()
	collectionBackdrop.Visible = true
end)

end -- Collection Gallery overlay

-- ----- "Unlocked!" popup: a quick celebratory card shown whenever a NEW
-- Patron or Theme appears in latestState compared to the previous
-- render(). See lastOwnedPatronIds/lastOwnedThemeIds + the diff check
-- inside render() further down. -----

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
addSoftShadow(unlockPopup, 20)

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
	screenShake(root, 4)

	local function dismiss()
		if unlockPopupToken ~= myToken then
			return
		end
		unlockPopup.Visible = false
	end

	unlockPopupDismissCatcher.MouseButton1Click:Connect(dismiss)
	task.delay(2.4, dismiss)
end

end -- Unlock popup

-- Snapshots of owned ids from the last render(), used to detect NEW
-- unlocks to celebrate with showUnlockPopup. lastOwnedPatronIds/
-- lastOwnedThemeIds/hasRenderedOnce are already forward-declared (and
-- initialized) up near the top of this do/end section -- see the big
-- forward-declaration comment block above.

-- ===== Menu -> game transition, volume cycling =====

menuPlayButton.MouseButton1Click:Connect(function()
	playSfx(SOUND_IDS.uiClick)
	menuFrame.Visible = false
	root.Visible = true
	applyMusicVolume()
end)

volumeButton.MouseButton1Click:Connect(function()
	volumePresetIndex = (volumePresetIndex % #VOLUME_PRESETS) + 1
	settings.masterVolume = VOLUME_PRESETS[volumePresetIndex]
	volumeButton.Text = currentVolumeIcon()
	applyMusicVolume()
	if settingsRefreshAudioTab then
		settingsRefreshAudioTab() -- keep the Settings sliders in sync if open
	end
end)

-- ===== Client-side state =====
-- latestState is already forward-declared (and initialized to nil) up near
-- the top of the file, alongside the overlay do/end blocks that need to
-- read it before this section runs -- see the big forward-declaration
-- comment block above.

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
local lastPhase = nil

-- When High Contrast Cards is on (Settings -> Game), cards always use a
-- stark white/yellow pair instead of the current Theme's subtler palette,
-- for players who find the themed colors harder to read.
local HIGH_CONTRAST_CARD_BASE = Color3.fromRGB(255, 255, 255)
local HIGH_CONTRAST_CARD_SELECTED = Color3.fromRGB(255, 221, 0)

local function cardBaseColor()
	if settings.highContrastCards then
		return HIGH_CONTRAST_CARD_BASE
	end
	return currentTheme.colors.cardBase
end

local function cardSelectedColor()
	if settings.highContrastCards then
		return HIGH_CONTRAST_CARD_SELECTED
	end
	return currentTheme.colors.cardSelected
end

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

		local roundsPerNight = 3
		local difficulty = DifficultyTiers.getById((latestState and latestState.difficultyId) or DifficultyTiers.DefaultId)
			or DifficultyTiers.getById(DifficultyTiers.DefaultId)
		local bossRoundsEnabled = difficulty.bossRoundsEnabled ~= false

		for round = 1, roundsPerNight do
			local isPast = (night < currentNight) or (night == currentNight and round < currentRound)
			local isCurrent = (night == currentNight and round == currentRound)
			local isBoss = bossRoundsEnabled and BossRounds.isBossRound(round, roundsPerNight)

			local pip = Instance.new("Frame")
			pip.Size = isCurrent and UDim2.new(0, 60, 0, 44) or UDim2.new(0, 52, 0, 38)
			pip.BackgroundColor3 = isCurrent and cardSelectedColor()
				or (isPast and Color3.fromRGB(90, 130, 90) or (isBoss and Color3.fromRGB(90, 45, 45) or Color3.fromRGB(60, 45, 32)))
			pip.Parent = pipsHolder
			roundCorner(pip, 10)

			local pipLabel = Instance.new("TextLabel")
			pipLabel.Size = UDim2.fromScale(1, 1)
			pipLabel.BackgroundTransparency = 1
			pipLabel.Font = Enum.Font.GothamBold
			pipLabel.TextSize = isCurrent and 15 or 13
			pipLabel.TextColor3 = isCurrent and Color3.fromRGB(30, 24, 18) or Color3.fromRGB(240, 230, 215)
			local targetScore = RunStateEngine.targetScoreFor(night, round)
			local bossTag = isBoss and " 👑" or ""
			if isPast then
				pipLabel.Text = string.format("R%d ✓", round)
			else
				pipLabel.Text = string.format("R%d%s\n%d pts", round, bossTag, targetScore)
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
		color = cardSelectedColor()
	else
		color = cardBaseColor():Lerp(cardSelectedColor(), hoverFalloff * 0.35)
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

	-- Cards are bottom-anchored (AnchorPoint 0.5, 1 -- see rebuildHand), so the
	-- target Position must also use Y-scale 1, or hovering would snap every
	-- card up to the middle of its slot instead of just lifting it slightly.
	tweenTo(button, { Position = UDim2.new(0.5, 0, 1, -lift), BackgroundColor3 = color }, duration, style, Enum.EasingDirection.Out)
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

function rebuildHand(handData)
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
		button.BackgroundColor3 = cardBaseColor()
		button.TextColor3 = RED_SUITS[card.suit] and Color3.fromRGB(180, 30, 30) or Color3.fromRGB(20, 20, 20)
		button.Text = string.format("%s\n%s", RANK_NAMES[card.rank] or tostring(card.rank), SUIT_SYMBOLS[card.suit] or "?")
		button.Parent = slot
		polishButton(button, 10)

		-- A dark outline so the card reads clearly as a card against ANY
		-- table theme, even ones whose background happens to sit close in
		-- tone to the card color.
		local outline = Instance.new("UIStroke")
		outline.Color = Color3.fromRGB(20, 15, 10)
		outline.Thickness = 2
		outline.Parent = button

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

	if state.bossModifier then
		bossBanner.Visible = true
		bossBannerLabel.Text = string.format("👑 Boss Round -- %s: %s", state.bossModifier.name, state.bossModifier.description)
	else
		bossBanner.Visible = false
	end

	rebuildHand(state.hand)

	if themesBackdrop.Visible then
		refreshThemesList() -- keep the panel accurate if it's open across a purchase
	end
	if journeyBackdrop.Visible then
		refreshJourney() -- keep "you are here" accurate if it's open across a round change
	end
	if handRefBackdrop.Visible then
		refreshHandReferenceImpl() -- keep play counts accurate if it's open across a hand
	end
	if deckTrackerBackdrop.Visible then
		refreshDeckTrackerImpl() -- keep counts accurate if it's open across a draw
	end
	if collectionBackdrop.Visible then
		refreshCollectionImpl() -- keep found counts accurate if it's open across a purchase
	end

	-- ----- Detect newly-owned Patrons/Themes and celebrate the first one
	-- with an "Unlocked!" popup. Skipped on the very first render (session
	-- start) so the default theme/starting state doesn't look "unlocked". -----
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

	-- A little celebratory jolt the moment a round is won (playing -> shop).
	if lastPhase == "playing" and state.phase == "shop" then
		screenShake(root, 8)
	end
	lastPhase = state.phase
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
