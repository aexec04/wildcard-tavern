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
local ClientSettings = require(script.Parent.ClientSettings)
local ModalStage = require(script.Parent.ModalStage)
local Layout = require(Engine:WaitForChild("ChoiceSceneLayout"))
local MenuSceneArt = require(Engine:WaitForChild("MenuSceneArt"))
local SmoothVignette = require(script.Parent.SmoothVignette)

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
	local stroke = Instance.new("UIStroke")
	stroke.Color = isDecline and INK or GOLD
	stroke.Thickness = isDecline and 1.5 or 3
	stroke.Parent = card

	local well = Instance.new("Frame")
	well.Name = "Well"
	well.Size = UDim2.fromOffset(84, 84)
	well.Position = UDim2.new(0.5, -42, 0, 14)
	well.BackgroundColor3 = WOOD
	well.ZIndex = 63
	well.Parent = card
	ui.roundCorner(well, 42)
	local ring = Instance.new("UIStroke")
	ring.Color = GOLD
	ring.Thickness = 2
	ring.Parent = well
	local icon = label(well, { Size = UDim2.fromScale(1, 1), Text = option.icon or choice.icon or "✨", TextSize = 44, TextColor3 = CREAM, ZIndex = 64 })
	if choice.kind == "patron" or choice.kind == "rushPatron" then
		PatronPlaque.apply(well, option.id, { emojiLabel = icon, zIndex = 65, cornerRadius = 42 })
	elseif choice.kind == "modifier" then
		local artId = ContentArt.getImageId("blessing_icons", option.id)
		if artId then
			PatronPlaque.applyById(well, artId, { emojiLabel = icon, zIndex = 65, cornerRadius = 42 })
		end
	elseif choice.kind == "event" and not isDecline then
		local artId = ContentArt.getImageId("events", choice.eventId)
		if artId then
			PatronPlaque.applyById(well, artId, { emojiLabel = icon, zIndex = 65, cornerRadius = 42 })
		end
	end

	label(card, {
		Name = "Name", Size = UDim2.new(1, -20, 0, 26), Position = UDim2.fromOffset(10, 106), Text = option.name, TextSize = 19,
		TextWrapped = true,
	})
	label(card, {
		Name = "Line1", Size = UDim2.new(1, -24, 0, 56), Position = UDim2.fromOffset(12, 136), Text = option.line1 or "", TextSize = 15,
		Font = Enum.Font.GothamMedium, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top,
		TextColor3 = (choice.kind == "modifier") and BLESS or INK,
	})
	label(card, {
		Name = "Line2", Size = UDim2.new(1, -24, 0, 40), Position = UDim2.fromOffset(12, 194), Text = option.line2 or "", TextSize = 15,
		Font = Enum.Font.GothamMedium, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, TextColor3 = CURSE,
	})

	local button = Instance.new("TextButton")
	button.Name = "Pick"
	button.Size = UDim2.new(1, -40, 0, 40)
	button.Position = UDim2.new(0, 20, 1, -52)
	button.Font = Enum.Font.GothamBold
	button.TextSize = 17
	button.Text = isDecline and "No, thanks" or "Choose"
	button.TextColor3 = rgb("buttonText")
	button.BackgroundColor3 = isDecline and rgb("buttonBrown") or rgb("buttonGreen")
	button.ZIndex = 64
	button.Parent = card
	ui.polishButton(button, 10)
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
	if not show then
		ui.backdrop.Visible = false
		return
	end
	local key = ChoicePanel.keyOf(choice)
	if key ~= builtKey then
		builtKey = key
		pcall(ModalStage.setKind, ui.backdrop, choice.kind) -- blessing altar, card table or map desk
		clearCards()
		ui.title.Text = choice.title or ""
		ui.text.Text = choice.text or ""
		ui.text.Visible = ui.text.Text ~= ""
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
	for _, side in ipairs({ 0.1, 0.9 }) do -- candle glow: stacked faint rings, no visible disc edge
		local glow = Instance.new("Frame")
		glow.Name = "CandleGlow"
		glow.AnchorPoint = Vector2.new(0.5, 0.5)
		glow.Position = UDim2.fromScale(side, 0.34)
		glow.Size = UDim2.fromOffset(420, 420)
		glow.BackgroundTransparency = 1
		glow.ZIndex = 60
		glow.Parent = scene
		for i, ring in ipairs(Layout.glowRings(12)) do
			local disc = Instance.new("Frame")
			disc.Name = "Ring" .. i
			disc.AnchorPoint = Vector2.new(0.5, 0.5)
			disc.Position = UDim2.fromScale(0.5, 0.5)
			disc.Size = UDim2.fromScale(ring.size, ring.size)
			disc.BackgroundColor3 = Color3.fromRGB(255, 190, 100)
			disc.BackgroundTransparency = ring.alpha
			disc.BorderSizePixel = 0
			disc.ZIndex = 60
			disc.Parent = glow
			local c = Instance.new("UICorner")
			c.CornerRadius = UDim.new(0.5, 0)
			c.Parent = disc
		end
	end

	local holder = Instance.new("Frame")
	holder.Name = "Holder"
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.new(0.5, 0, 0.5, 24) -- sits below the top toast strip (y 20 to 54)
	holder.Size = UDim2.fromOffset(CARD_W * 3 + 60, CARD_H + 150)
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
	deps.roundCorner(text, 8)

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

	-- shrink to fit small windows: the holder is about 750 x 450
	local function fit()
		local size = deps.screenGui.AbsoluteSize
		local base = math.clamp(math.min(size.X / (CARD_W * 3 + 100), size.Y / (CARD_H + 190)), 0.5, 1.2)
		scale.Scale = base
		if ui then ui.baseScale = base end
	end

	ui = {
		backdrop = backdrop, title = title, text = text, row = row, scale = scale, fit = fit,
		menuFrame = deps.menuFrame, roundCorner = deps.roundCorner, polishButton = deps.polishButton,
		playClickSfx = deps.playClickSfx, choiceRemote = deps.choiceRemote,
	}
	fit()
	ui.baseScale = scale.Scale
	deps.screenGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	if deps.menuFrame then
		deps.menuFrame:GetPropertyChangedSignal("Visible"):Connect(render)
	end
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
