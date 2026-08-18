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
local AdvanceRoundRemote = remotes:WaitForChild("AdvanceRound")
local RestartRunRemote = remotes:WaitForChild("RestartRun")
local StateUpdatedRemote = remotes:WaitForChild("StateUpdated")

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
backgroundMusic.Volume = 0.35
backgroundMusic.Parent = SoundService

local musicMuted = false

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
	return button
end

local muteButton = makeCornerButton("♪", -60)
local helpButton = makeCornerButton("?", -110)

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

-- ----- Game over overlay -----

local gameOverFrame = Instance.new("Frame")
gameOverFrame.Name = "GameOver"
gameOverFrame.Size = UDim2.fromScale(0.5, 0.3)
gameOverFrame.Position = UDim2.fromScale(0.25, 0.35)
gameOverFrame.BackgroundColor3 = Color3.fromRGB(40, 30, 22)
gameOverFrame.Visible = false
gameOverFrame.Parent = root

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
	return button
end

local menuPlayButton = makeMenuButton("Play")
local menuHowToPlayButton = makeMenuButton("How to Play")

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
howToPlayPanel.Size = UDim2.fromScale(0.55, 0.55)
howToPlayPanel.Position = UDim2.fromScale(0.225, 0.225)
howToPlayPanel.BackgroundColor3 = Color3.fromRGB(40, 30, 22)
howToPlayPanel.ZIndex = 21
howToPlayPanel.Parent = howToPlayBackdrop

local howToPlayTitle = Instance.new("TextLabel")
howToPlayTitle.Size = UDim2.new(1, 0, 0, 40)
howToPlayTitle.BackgroundTransparency = 1
howToPlayTitle.Font = Enum.Font.GothamBold
howToPlayTitle.TextSize = 22
howToPlayTitle.TextColor3 = Color3.fromRGB(250, 240, 220)
howToPlayTitle.Text = "How to Play"
howToPlayTitle.ZIndex = 21
howToPlayTitle.Parent = howToPlayPanel

local howToPlayText = Instance.new("TextLabel")
howToPlayText.Size = UDim2.new(1, -30, 1, -100)
howToPlayText.Position = UDim2.new(0, 15, 0, 45)
howToPlayText.BackgroundTransparency = 1
howToPlayText.Font = Enum.Font.Gotham
howToPlayText.TextSize = 16
howToPlayText.TextColor3 = Color3.fromRGB(235, 225, 210)
howToPlayText.TextWrapped = true
howToPlayText.TextXAlignment = Enum.TextXAlignment.Left
howToPlayText.TextYAlignment = Enum.TextYAlignment.Top
howToPlayText.ZIndex = 21
howToPlayText.Text = table.concat({
	"- Click cards in your hand to select up to 5 of them.",
	"- Click Play Hand to score the best poker hand among your selected cards",
	"  (Pair, Flush, Full House, etc). Chips x Mult = your score.",
	"- Reach the round's target score before you run out of hands to win it.",
	"- Not happy with your hand? Use a Discard to swap selected cards for new ones",
	"  (this doesn't cost you a hand).",
	"- Win a round and visit The Bar to spend Tips on Patrons -- helpers that",
	"  boost your future hands.",
	"- Survive as many Nights as you can. Good luck!",
}, "\n")
howToPlayText.Parent = howToPlayPanel

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

-- ===== Menu -> game transition, mute toggle =====

menuPlayButton.MouseButton1Click:Connect(function()
	playSfx(SOUND_IDS.uiClick)
	menuFrame.Visible = false
	root.Visible = true
	if backgroundMusic.SoundId ~= "rbxassetid://0" and not musicMuted then
		backgroundMusic:Play()
	end
end)

muteButton.MouseButton1Click:Connect(function()
	musicMuted = not musicMuted
	if musicMuted then
		backgroundMusic:Stop()
		muteButton.Text = "🔇"
	else
		muteButton.Text = "♪"
		if backgroundMusic.SoundId ~= "rbxassetid://0" then
			backgroundMusic:Play()
		end
	end
end)

-- ===== Client-side state =====

local latestState = nil
local selected = {} -- [handIndex] = true
local hovering = {} -- [handIndex] = true
local cardButtons = {} -- [handIndex] = TextButton
local cardScales = {} -- [handIndex] = UIScale

local BASE_SCALE = 1.0
local HOVER_SCALE = 1.06
local SELECTED_SCALE = 1.08
local SELECTED_HOVER_SCALE = 1.14

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
	local isHovering = hovering[index] == true

	local targetColor
	if isSelected then
		targetColor = Color3.fromRGB(255, 214, 130)
	else
		targetColor = Color3.fromRGB(250, 245, 235)
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

	tweenTo(button, { BackgroundColor3 = targetColor }, 0.15)
	if usePop then
		tweenTo(scaleObject, { Scale = targetScale }, 0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	else
		tweenTo(scaleObject, { Scale = targetScale }, 0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
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
	hovering = {}

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
		button.BackgroundColor3 = Color3.fromRGB(250, 245, 235)
		button.TextColor3 = RED_SUITS[card.suit] and Color3.fromRGB(180, 30, 30) or Color3.fromRGB(20, 20, 20)
		button.Text = string.format("%s\n%s", RANK_NAMES[card.rank] or tostring(card.rank), SUIT_SYMBOLS[card.suit] or "?")
		button.Parent = slot

		local scaleObject = Instance.new("UIScale")
		scaleObject.Scale = BASE_SCALE
		scaleObject.Parent = button

		cardButtons[index] = button
		cardScales[index] = scaleObject

		button.MouseButton1Click:Connect(function()
			onCardClicked(index)
		end)
		button.MouseEnter:Connect(function()
			hovering[index] = true
			refreshCardVisual(index, false)
		end)
		button.MouseLeave:Connect(function()
			hovering[index] = nil
			refreshCardVisual(index, false)
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

		buyButton.MouseButton1Click:Connect(function()
			playSfx(SOUND_IDS.buyPatron)
			BuyPatronRemote:FireServer(offer.id)
		end)
	end
end

local function render(state)
	latestState = state

	nightRoundLabel.Text = string.format("Night %d - Round %d", state.night, state.round)
	tipsLabel.Text = string.format("Tips: %d", state.tips)
	scoreLabel.Text = string.format("Score: %d / %d", state.roundScore, state.targetScore)
	handsDiscardsLabel.Text = string.format("Hands: %d  Discards: %d", state.handsRemaining, state.discardsRemaining)

	rebuildHand(state.hand)

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
