-- Choice panel: one overlay for the start-of-run draft (pick 1 of 3 starting Patrons, then 1 of 3 blessings that
-- each come with a curse) and for the random event cards between Nights (always with a "No, thanks" card).
-- Display only: the server decides everything (Engine/RunChoice.lua); a click sends the option id on the
-- `Choice` remote and the server answers with the next choice, a result toast, or nothing.
--
-- state.choice = { kind = "patron" | "modifier" | "event", title, text, icon, eventId?, options = { { id, name, icon, line1, line2 } } }
-- The panel only shows once the run has actually begun (the main menu is hidden), never on top of the menu.
-- Painted cards: Patron art when the draft offers Patrons; events use ContentArt category "events" when an image
-- exists, otherwise the emoji icon.
--
-- init(deps): { screenGui, menuFrame, polishPanel, polishButton, roundCorner, playClickSfx, choiceRemote }
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Engine = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine")
local ContentArt = require(Engine:WaitForChild("ContentArt"))
local PatronPlaque = require(script.Parent.PatronPlaque)
local PORTRAIT_SCALE = 1.3 -- Patron portraits in the draft rings: enlarged and top anchored so the baked in name is clipped away
local ClientSettings = require(script.Parent.ClientSettings)
local ModalStage = require(script.Parent.ModalStage)
local Layout = require(Engine:WaitForChild("ChoiceSceneLayout"))
local MenuSceneArt = require(Engine:WaitForChild("MenuSceneArt"))
local SmoothVignette = require(script.Parent.SmoothVignette)
local SoftGlow = require(script.Parent.SoftGlow)
local DismissRules = require(Engine:WaitForChild("PopupDismissRules"))
local ChoiceRarity = require(Engine:WaitForChild("ChoiceRarity"))

local ChoicePanel = {}

local function rgb(key)
	local c = Layout.PALETTE[key]
	return Color3.fromRGB(c[1], c[2], c[3])
end
local INK, CURSE, BLESS = rgb("ink"), rgb("curse"), rgb("bless")
local PARCHMENT, GOLD, CREAM, WOOD = rgb("paper"), rgb("brass"), rgb("plateText"), rgb("plate")

local CARD_W, CARD_H = 230, 300

local ui
local lastChoice
local builtKey
local clickLocked = false

-- A key that changes when the offered choice changes (so the cards are rebuilt only then).
function ChoicePanel.keyOf(choice)
	if type(choice) ~= "table" then
		return ""
	end
	local ids = {}
	for _, o in ipairs(choice.options or {}) do
		ids[#ids + 1] = o.id
	end
	return tostring(choice.kind) .. ":" .. tostring(choice.eventId) .. ":" .. tostring(choice.step) .. ":" .. table.concat(ids, ",")
end

local function label(parent, props)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBold
	l.TextColor3 = INK
	l.TextTransparency = 0
	l.TextStrokeTransparency = 1
	l.ZIndex = 63
	for k, v in pairs(props) do
		l[k] = v
	end
	l.Parent = parent
	return l
end

local function clearCards()
	for _, child in ipairs(ui.row:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

local function buildCard(choice, option, order)
	local isDecline = option.id == "decline"
	local slot = Instance.new("Frame") -- the layout owns the slot; the card inside bobs on hover
	slot.Name = "Slot_" .. option.id
	slot.Size = UDim2.fromOffset(CARD_W, CARD_H)
	slot.LayoutOrder = order
	slot.BackgroundTransparency = 1
	slot.ZIndex = 61
	slot.Parent = ui.row
	local shadow = Instance.new("Frame") -- soft contact shadow where the card stands on the table
	shadow.Name = "ContactShadow"
	shadow.AnchorPoint = Vector2.new(0.5, 0.5)
	shadow.Position = UDim2.new(0.5, 0, 1, -2)
	shadow.Size = UDim2.new(1, -24, 0, 18)
	shadow.BackgroundColor3 = Color3.new(0, 0, 0)
	shadow.BackgroundTransparency = 0.7
	shadow.BorderSizePixel = 0
	shadow.ZIndex = 61
	shadow.Parent = slot
	ui.roundCorner(shadow, 9)
	local card = Instance.new("Frame")
	card.Name = "Option_" .. option.id
	card.Size = UDim2.fromScale(1, 1)
	card.BackgroundColor3 = isDecline and rgb("paperDecline") or PARCHMENT
	card.BorderSizePixel = 0
	card.ZIndex = 62
	card.Parent = slot
	ui.roundCorner(card, 12)
	local stroke = Instance.new("UIStroke") -- the thin brass line at the paper's edge, inside the wood
	stroke.Color = isDecline and INK or GOLD
	stroke.Thickness = isDecline and 1.5 or 2
	stroke.Parent = card
	local paper = Instance.new("UIGradient") -- warm paper: lighter at the top, a touch darker at the foot (colour stops only)
	paper.Rotation = 90
	paper.Color = ColorSequence.new(Color3.fromRGB(246, 232, 198), Color3.fromRGB(228, 210, 172))
	paper.Parent = card
	-- a slight tilt, a different one per card (1 to 2 degrees); the decline card stands straight
	local TILTS = { -1.5, 1.0, -0.5, 1.5, -1.0 }
	card.Rotation = isDecline and 0 or TILTS[(order - 1) % #TILTS + 1]
	-- the dark wood frame around the paper with four brass studs on its corners (the Round Select cards' look)
	local woodFrame = Instance.new("Frame")
	woodFrame.Name = "WoodFrame"
	woodFrame.Position = UDim2.fromOffset(-7, -7)
	woodFrame.Size = UDim2.new(1, 14, 1, 14)
	woodFrame.BackgroundColor3 = Color3.fromRGB(82, 54, 30)
	woodFrame.BorderSizePixel = 0
	woodFrame.Active = false
	woodFrame.ZIndex = 61
	woodFrame.Parent = card
	ui.roundCorner(woodFrame, 15)
	local woodEdge = Instance.new("UIStroke")
	woodEdge.Color = Color3.fromRGB(38, 24, 12)
	woodEdge.Thickness = 2
	woodEdge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	woodEdge.Parent = woodFrame
	for i, at in ipairs({ { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 } }) do
		local stud = Instance.new("Frame")
		stud.Name = "WoodStud" .. i
		stud.AnchorPoint = Vector2.new(0.5, 0.5)
		stud.Position = UDim2.new(at[1], at[1] == 0 and 7 or -7, at[2], at[2] == 0 and 7 or -7)
		stud.Size = UDim2.fromOffset(9, 9)
		stud.BackgroundColor3 = Color3.fromRGB(205, 164, 84)
		stud.BorderSizePixel = 0
		stud.Active = false
		stud.ZIndex = 62
		stud.Parent = woodFrame
		ui.roundCorner(stud, 5)
	end

	local medalRing = Instance.new("Frame") -- the brass ring the portrait sits in (made first, so it draws under the well)
	medalRing.Name = "MedalRing"
	medalRing.Size = UDim2.fromOffset(140, 98)
	medalRing.Position = UDim2.new(0.5, -70, 0, 6)
	medalRing.BackgroundColor3 = Color3.fromRGB(200, 160, 84)
	medalRing.BorderSizePixel = 0
	medalRing.ZIndex = 63
	medalRing.Parent = card
	ui.roundCorner(medalRing, 12)
	local medalEdge = Instance.new("UIStroke")
	medalEdge.Color = Color3.fromRGB(60, 40, 22)
	medalEdge.Thickness = 2
	medalEdge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	medalEdge.Parent = medalRing
	local well = Instance.new("Frame")
	well.Name = "Well"
	well.Size = UDim2.fromOffset(126, 84)
	well.Position = UDim2.new(0.5, -63, 0, 13)
	well.BackgroundColor3 = WOOD
	well.ZIndex = 63
	well.Parent = card
	ui.roundCorner(well, 8)
	local ring = Instance.new("UIStroke")
	ring.Color = GOLD
	ring.Thickness = 2
	ring.Parent = well
	local icon = label(well, { Size = UDim2.fromScale(1, 1), Text = option.icon or choice.icon or "✨", TextSize = 44, TextColor3 = CREAM, ZIndex = 64 })
	if choice.kind == "patron" or choice.kind == "rushPatron" or choice.kind == "reward" then
		-- Patron art is a full card with its name baked in at the bottom: show it enlarged and anchored to the top, clipped by the
		-- round well, so only the character shows inside the ring
		local crop = Instance.new("Frame")
		crop.Name = "PortraitCrop"
		crop.Size = UDim2.fromScale(1, 1)
		crop.BackgroundTransparency = 1
		crop.BorderSizePixel = 0
		crop.ClipsDescendants = true
		crop.ZIndex = 65
		crop.Parent = well
		ui.roundCorner(crop, 8)
		PatronPlaque.apply(crop, option.id, { emojiLabel = icon, zIndex = 65, cornerRadius = 0,
			size = UDim2.fromScale(PORTRAIT_SCALE, PORTRAIT_SCALE), position = UDim2.fromScale(0.5, 0), anchor = Vector2.new(0.5, 0) })
		if game:GetService("RunService"):IsStudio() then
			print(("[PortraitCrop] patron=%s scale=%.2f anchor=top"):format(tostring(option.id), PORTRAIT_SCALE))
		end
	elseif choice.kind == "modifier" then
		local artId = ContentArt.getImageId("blessing_icons", option.id)
		if artId then
			PatronPlaque.applyById(well, artId, { emojiLabel = icon, zIndex = 65, cornerRadius = 8 })
		end
	elseif choice.kind == "event" then
		-- one painted icon per option kind (decline included), else the event's own art; the emoji is only the last fallback
		local artId = (option.kind and ContentArt.getImageId("option_icons", option.kind)) or (not isDecline and ContentArt.getImageId("events", choice.eventId)) or nil
		if artId then
			PatronPlaque.applyById(well, artId, { emojiLabel = icon, zIndex = 65, cornerRadius = 8 })
		elseif game:GetService("RunService"):IsStudio() then
			print(("[EmojiLeft] event %s option %s is drawn from the emoji %s"):format(tostring(choice.eventId), tostring(option.id), tostring(option.icon)))
		end
	end

	-- Rarity (Patrons in the draft): a muted tier rim, a gem at the top corner, a dark name plate with the tier word as a second line,
	-- a soft glow from Rare up. Items with no rarity (blessings, events, the decline card) show nothing.
	local rarity = (not isDecline) and ChoiceRarity.info(ChoiceRarity.tabFor(choice.kind), option.id) or nil
	local function c3(t) return Color3.fromRGB(t[1], t[2], t[3]) end
	if rarity then
		stroke.Color = c3(rarity.rim)
		local gem = Instance.new("Frame")
		gem.Name = "RarityGem"
		gem.AnchorPoint = Vector2.new(0.5, 0.5)
		gem.Position = UDim2.new(1, -20, 0, 20)
		gem.Size = UDim2.fromOffset(14, 14)
		gem.Rotation = 45
		gem.BackgroundColor3 = c3(rarity.color)
		gem.BorderSizePixel = 0
		gem.ZIndex = 65
		gem.Parent = card
		local gs = Instance.new("UIStroke")
		gs.Color = Color3.fromRGB(30, 20, 10)
		gs.Thickness = 2
		gs.Parent = gem
		if rarity.glow then
			pcall(function()
				local g = SoftGlow.build(slot, {
					name = "RarityGlow", color = c3(rarity.color), zIndex = 61,
					position = UDim2.fromOffset(CARD_W / 2, CARD_H / 2), size = UDim2.fromOffset(CARD_W * 1.25, CARD_H * 1.25), peak = rarity.glow,
				})
				g.root.Active = false
			end)
		end
		local plate = Instance.new("Frame")
		plate.Name = "NamePlate"
		plate.Position = UDim2.fromOffset(8, 108)
		plate.Size = UDim2.new(1, -16, 0, 50)
		plate.BackgroundColor3 = c3(rarity.plate)
		plate.BackgroundTransparency = 0.05
		plate.BorderSizePixel = 0
		plate.ZIndex = 63
		plate.Parent = card
		ui.roundCorner(plate, 8)
		local underline = Instance.new("UIStroke")
		underline.Color = c3(rarity.rim)
		underline.Thickness = 1.5
		underline.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		underline.Parent = plate
		label(plate, {
			Name = "Name", Size = UDim2.new(1, -12, 0, 28), Position = UDim2.fromOffset(6, 3), Text = option.name, TextSize = 19,
			TextColor3 = CREAM, ZIndex = 64, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd,
		})
		label(plate, {
			Name = "Rarity", Size = UDim2.new(1, -12, 0, 20), Position = UDim2.fromOffset(6, 30), Text = rarity.word, TextSize = 15,
			TextColor3 = c3(rarity.text), ZIndex = 64,
		})
	else
		label(card, {
			Name = "Name", Size = UDim2.new(1, -20, 0, 26), Position = UDim2.fromOffset(10, 112), Text = option.name, TextSize = 19,
			TextWrapped = true,
		})
	end
	-- the rule text sits in one block centred in the gap between the name and the Choose plate: dark ink, 16 px, the plus line in green ink
	-- and the minus line in dark red ink (4.5:1 or better on the paper)
	local ruleTop = rarity and 162 or 140
	local ruleBox = Instance.new("Frame")
	ruleBox.Name = "Rule"
	ruleBox.BackgroundTransparency = 1
	ruleBox.BorderSizePixel = 0
	ruleBox.Active = false
	ruleBox.Position = UDim2.fromOffset(12, ruleTop)
	ruleBox.Size = UDim2.new(1, -24, 0, 242 - ruleTop)
	ruleBox.ZIndex = 63
	ruleBox.Parent = card
	local ruleList = Instance.new("UIListLayout")
	ruleList.SortOrder = Enum.SortOrder.LayoutOrder
	ruleList.VerticalAlignment = Enum.VerticalAlignment.Center
	ruleList.HorizontalAlignment = Enum.HorizontalAlignment.Center
	ruleList.Padding = UDim.new(0, 4)
	ruleList.Parent = ruleBox
	local function ruleLine(name, order, text, color)
		if text == nil or text == "" then return end
		label(ruleBox, {
			Name = name, LayoutOrder = order, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Text = text, TextSize = 16,
			Font = Enum.Font.GothamMedium, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Center, TextColor3 = color,
		})
	end
	ruleLine("Line1", 1, option.line1, (choice.kind == "modifier") and BLESS or INK)
	ruleLine("Line2", 2, option.line2, CURSE)

	local button = Instance.new("TextButton")
	button.Name = "Pick"
	button.Size = UDim2.new(1, -40, 0, 44)
	button.Position = UDim2.new(0, 20, 1, -54)
	button.Font = Enum.Font.GothamBold
	button.TextSize = 17
	button.Text = isDecline and "No, thanks" or "Choose"
	button.TextColor3 = rgb("buttonText")
	button.BackgroundColor3 = isDecline and rgb("buttonBrown") or rgb("buttonGreen")
	button.ZIndex = 64
	button.Parent = card
	ui.polishButton(button, 10)
	pcall(function() -- Gameplay v2: native TavernKit buttons, the one clear choice is the green plate, No, thanks is brown
		if require(Engine:WaitForChild("FeatureFlags")).gameplay() == 2 then
			require(script.Parent.TavernKit).skin(button, nil, isDecline and "secondary" or "primary")
		end
	end)
	button.MouseButton1Click:Connect(function()
		if clickLocked then
			return
		end
		clickLocked = true
		task.delay(0.4, function() clickLocked = false end)
		ui.playClickSfx()
		ui.choiceRemote:FireServer(option.id)
	end)
	-- hover: the card rises a little (skipped in calm mode)
	local base = card.Position
	local function bob(up)
		if ClientSettings.get("animSpeed") == "fast" or ClientSettings.get("reduceShake") == true then
			return
		end
		TweenService:Create(card, TweenInfo.new(0.12), { Position = base + UDim2.fromOffset(0, up and -8 or 0) }):Play()
	end
	card.Active = true
	card.MouseEnter:Connect(function() bob(true) end)
	card.MouseLeave:Connect(function() bob(false) end)
	return card
end

local function menuIsOpen()
	return ui.menuFrame ~= nil and ui.menuFrame.Visible
end

local function render()
	local choice = lastChoice
	local show = choice ~= nil and not menuIsOpen()
	local victory = require(script.Parent.VictoryScreen)
	if show and choice.kind == "reward" then -- the Night clear Patron reward is the purple and gold Victory screen's 3 cards
		ui.backdrop.Visible = false
		if pcall(victory.showPick, ui.screenGui, choice, function(id)
			if clickLocked then return end
			clickLocked = true
			task.delay(0.4, function() clickLocked = false end)
			ui.playClickSfx()
			ui.choiceRemote:FireServer(id)
		end, function()
			ui.playClickSfx()
			ui.choiceRemote:FireServer("decline")
		end) then
			return
		end
	end
	victory.hidePick() -- never closes the Run complete screen
	if not show then
		ui.backdrop.Visible = false
		return
	end
	ui.skip.Visible = choice.kind == "reward" and choice.skip == true -- the Night clear Patron reward can be skipped
	local key = ChoicePanel.keyOf(choice)
	if key ~= builtKey then
		builtKey = key
		pcall(ModalStage.setKind, ui.backdrop, choice.kind) -- blessing altar, card table or map desk
		clearCards()
		ui.title.Text = choice.title or ""
		pcall(function() -- Gameplay v2: serif title like the other kit screens
			if require(Engine:WaitForChild("FeatureFlags")).gameplay() == 2 then
				ui.title.Font = Enum.Font[require(Engine:WaitForChild("TavernStyle")).FONTS.title]
			end
		end)
		ui.text.Text = choice.text or ""
		ui.text.Visible = ui.text.Text ~= ""
		ui.row.Position = UDim2.fromOffset(0, ui.text.Visible and 100 or 60) -- no subtitle: the cards sit higher
		for i, option in ipairs(choice.options or {}) do
			buildCard(choice, option, i)
		end
	end
	if not ui.backdrop.Visible then
		ui.backdrop.Visible = true
		local base = ui.baseScale or 1
		if ClientSettings.get("animSpeed") ~= "fast" and ClientSettings.get("reduceShake") ~= true then
			ui.scale.Scale = base * 0.9
			TweenService:Create(ui.scale, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = base }):Play()
		else
			ui.scale.Scale = base
		end
	end
end

function ChoicePanel.init(deps)
	local backdrop = Instance.new("Frame")
	backdrop.Name = "ChoiceBackdrop" -- a "...Backdrop" locks the gameplay hit areas while it is up (InputGuard)
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	backdrop.BackgroundTransparency = 0.25 -- solid enough that Round Select cards never show through the title
	backdrop.Active = true
	backdrop.Visible = false
	backdrop.ZIndex = 60
	backdrop.Parent = deps.screenGui
	local stage = ModalStage.mount(backdrop, "event") -- own opaque stage + modal gate; render() re-themes per choice kind
	local decor = stage and stage:FindFirstChild("Decor")
	if decor then
		decor.Visible = false -- the old stage decor (ghost chair squares along the bottom) is replaced by the painted scene
		decor:GetPropertyChangedSignal("Visible"):Connect(function() decor.Visible = false end)
	end

	-- Painted scene: the tavern room under ONE smooth scrim, a candle glow at each side. The stage stays under it
	-- (opaque) so nothing behind ever shows through.
	local scene = Instance.new("Frame")
	scene.Name = "Scene"
	scene.Size = UDim2.fromScale(1, 1)
	scene.BackgroundColor3 = Color3.fromRGB(34, 24, 16)
	scene.BorderSizePixel = 0
	scene.ZIndex = 60
	scene.Parent = backdrop
	local wood = Instance.new("UIGradient") -- colour stops only; the fallback when the painting has no Image id
	wood.Rotation = 90
	wood.Color = ColorSequence.new(Color3.fromRGB(58, 40, 26), Color3.fromRGB(22, 15, 10))
	wood.Parent = scene
	local art = MenuSceneArt["menu_scene_a"]
	if type(art) == "string" and art ~= "" then
		local painting = Instance.new("ImageLabel")
		painting.Name = "Painting"
		painting.Size = UDim2.fromScale(1, 1)
		painting.BackgroundTransparency = 1
		painting.Image = art
		painting.ScaleType = Enum.ScaleType.Crop
		painting.ZIndex = 60
		painting.Parent = scene
	end
	local scrim = Instance.new("Frame") -- ONE dim layer, soft at the edges through SmoothVignette
	scrim.Name = "Scrim"
	scrim.Size = UDim2.fromScale(1, 1)
	scrim.BackgroundColor3 = rgb("scrim")
	scrim.BackgroundTransparency = 0.42
	scrim.BorderSizePixel = 0
	scrim.ZIndex = 60
	scrim.Parent = scene
	SmoothVignette.build(scene, {
		zIndex = 60, color = rgb("scrim"), name = "SceneVignette",
		top = { strength = 0.7, extent = 0.3 }, bottom = { strength = 0.7, extent = 0.3 },
		left = { strength = 0.5, extent = 0.2 }, right = { strength = 0.5, extent = 0.2 },
	})
	for _, side in ipairs({ 0.1, 0.9 }) do -- candle glow: SoftGlow, no visible disc edge
		SoftGlow.build(scene, { name = "CandleGlow", color = Color3.fromRGB(255, 190, 100), position = UDim2.fromScale(side, 0.34), size = UDim2.fromOffset(420, 420), peak = 0.3, zIndex = 60 })
	end

	local holder = Instance.new("Frame")
	holder.Name = "Holder"
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.new(0.5, 0, 0.5, 24) -- sits below the top toast strip (y 20 to 54)
	holder.Size = UDim2.fromOffset(CARD_W * 3 + 60, CARD_H + 164)
	holder.BackgroundTransparency = 1
	holder.ZIndex = 61
	holder.Parent = backdrop
	local scale = Instance.new("UIScale")
	scale.Parent = holder

	local titlePlaque = Instance.new("Frame") -- wood plaque so the title stays readable on any scene
	titlePlaque.Name = "TitlePlaque"
	titlePlaque.AnchorPoint = Vector2.new(0.5, 0)
	titlePlaque.Position = UDim2.new(0.5, 0, 0, 0)
	titlePlaque.Size = UDim2.new(0, 520, 0, 44)
	titlePlaque.BackgroundColor3 = WOOD
	titlePlaque.ZIndex = 62
	titlePlaque.Parent = holder
	deps.roundCorner(titlePlaque, 10)
	local plaqueStroke = Instance.new("UIStroke")
	plaqueStroke.Color = GOLD
	plaqueStroke.Thickness = 3
	plaqueStroke.Parent = titlePlaque
	local title = label(titlePlaque, {
		Name = "Title", Size = UDim2.fromScale(1, 1), Text = "", TextSize = 28, TextColor3 = CREAM,
		ZIndex = 63,
	})
	local text = label(holder, {
		Name = "Text", AnchorPoint = Vector2.new(0.5, 0), Size = UDim2.new(0, 520, 0, 34), Position = UDim2.new(0.5, 0, 0, 52),
		Text = "", TextSize = 17, TextColor3 = CREAM, BackgroundColor3 = WOOD, BackgroundTransparency = 0.12,
		Font = Enum.Font.GothamMedium, TextWrapped = true, ZIndex = 62,
	})
	text.BackgroundTransparency = 0.05
	deps.roundCorner(text, 14)
	local textStroke = Instance.new("UIStroke") -- brass hairline like the title plate
	textStroke.Color = GOLD
	textStroke.Thickness = 1
	textStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	textStroke.Parent = text

	local row = Instance.new("Frame")
	row.Name = "Row"
	row.Size = UDim2.new(1, 0, 0, CARD_H)
	row.Position = UDim2.fromOffset(0, 100)
	row.BackgroundTransparency = 1
	row.ZIndex = 61
	row.Parent = holder
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 20)
	layout.Parent = row

	-- Skip plate under the cards (Night clear Patron reward only): 160 x 44, answers "decline" like the event cards' No, thanks
	local skipButton = Instance.new("TextButton")
	skipButton.Name = "RewardSkip"
	skipButton.AnchorPoint = Vector2.new(0.5, 0)
	skipButton.Position = UDim2.new(0.5, 0, 0, 100 + CARD_H + 12)
	skipButton.Size = UDim2.fromOffset(160, 44)
	skipButton.Font = Enum.Font.GothamBold
	skipButton.TextSize = 17
	skipButton.Text = "Skip"
	skipButton.TextColor3 = rgb("buttonText")
	skipButton.BackgroundColor3 = rgb("buttonBrown")
	skipButton.Visible = false
	skipButton.ZIndex = 64
	skipButton.Parent = holder
	deps.polishButton(skipButton, 10)
	pcall(function() require(script.Parent.TavernKit).skin(skipButton, nil, "secondary") end)
	skipButton.MouseButton1Click:Connect(function()
		if clickLocked then return end
		clickLocked = true
		task.delay(0.4, function() clickLocked = false end)
		deps.playClickSfx()
		deps.choiceRemote:FireServer("decline")
	end)

	-- shrink to fit small windows: the holder is about 750 x 450
	local function fit()
		local size = deps.screenGui.AbsoluteSize
		local base = math.clamp(math.min(size.X / (CARD_W * 3 + 100), size.Y / (CARD_H + 190)), 0.5, 1.2)
		scale.Scale = base
		if ui then ui.baseScale = base end
	end

	-- Back to menu: the start-of-run draft (first Patron, blessing, Boss Rush Patrons) can be left; a between-Nights event card cannot.
	-- It does what Settings > Main Menu does and sends NOTHING to the server: no run is abandoned, no Tips banked for the run are
	-- spent twice, and the draft stays pending, so the Menu's Play brings the same choice back (render() hides this screen while the
	-- Menu is up) and New Run starts a clean run as it always did. Escape and a click on the dark area do the same.
	-- There is no on screen button any more (the corner buttons belong to the played table); Escape and Roblox's own menu are the way out.
	local function backToMenu()
		if not (lastChoice and DismissRules.canAbandonChoice(lastChoice.kind)) then
			return
		end
		deps.playClickSfx()
		if deps.root then deps.root.Visible = false end
		if deps.menuFrame then deps.menuFrame.Visible = true end
	end
	require(script.Parent.PopupDismiss).attach(backdrop, {
		panel = holder,
		close = backToMenu,
		policy = function()
			return (lastChoice and DismissRules.canAbandonChoice(lastChoice.kind)) and "dismiss" or "locked"
		end,
		button = false,
	})

	ui = {
		skip = skipButton, backdrop = backdrop, title = title, text = text, row = row, scale = scale, fit = fit,
		screenGui = deps.screenGui, menuFrame = deps.menuFrame, roundCorner = deps.roundCorner, polishButton = deps.polishButton,
		playClickSfx = deps.playClickSfx, choiceRemote = deps.choiceRemote,
	}
	fit()
	ui.baseScale = scale.Scale
	deps.screenGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	if deps.menuFrame then
		deps.menuFrame:GetPropertyChangedSignal("Visible"):Connect(render)
	end
	if deps.root then
		deps.root:GetPropertyChangedSignal("Visible"):Connect(render) -- the table showing is also a reason to re-check
	end
end

-- Re-evaluates what is on screen (used by the Play trace as a safety net).
function ChoicePanel.refresh()
	if ui then render() end
end

-- Called from render() with every state push.
function ChoicePanel.update(state)
	if not ui or type(state) ~= "table" then
		return
	end
	lastChoice = state.choice
	render()
end

return ChoicePanel
