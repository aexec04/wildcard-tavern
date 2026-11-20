--[[
	Client/MenuHotspots.lua
	The Menu's tavern composition (data in Engine/MenuLayout.lua): a wooden bar counter along the bottom with six painted
	items on it, parchment scrolls that unroll upward from an item, and the carved Deal Me In sign hanging from a ceiling beam.

	Every Menu action is ONE real TextButton made by newAction(). Other scripts (the hub, HowToPlay, Journey, RunSetup, the
	tutorial) connect their click handlers to those buttons, so they are never cloned or replaced, only moved between homes:
	  * Play and New Run live on the hanging sign;
	  * every other action lives in the scroll of its counter item (hidden while that scroll is closed), as an ink-lettered row;
	  * the "All actions" list (and phones, which show only the list): every button as a plaque row.
	closeAll() docks every button back to its home. One scroll is open at a time; a click outside, the item again or Escape
	closes it. The scroll opens with a 0.35s tween (rods separate, parchment grows, rows fade in 0.04s apart) and is instant
	in calm mode. A button can show a padlock and a hint: set its attributes Locked (bool) and LockHint (string).

	build{ menuFrame, layer, buttons, calm, onHover, tutorialRibbon } returns
	  { startLoops(), stopLoops(), entry(), applyViewport(w, h), closeAll(instant), openScroll(itemId), hotspotFrames, animatedCount }
]]

local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Engine = game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine")
local Layout = require(Engine:WaitForChild("MenuLayout"))
local ContentArt = require(Engine:WaitForChild("ContentArt"))

local Hotspots = {}

local WOOD = Color3.fromRGB(62, 42, 26)
local WOOD_LIGHT = Color3.fromRGB(96, 66, 38)
local BRASS = Color3.fromRGB(214, 172, 88)
local CREAM = Color3.fromRGB(250, 240, 220)
local CREAM_DIM = Color3.fromRGB(226, 208, 170)
local GLOW = Color3.fromRGB(255, 190, 90)
local PARCHMENT = Color3.fromRGB(238, 222, 186)
local INK = Color3.fromRGB(50, 34, 20)
local INK_DIM = Color3.fromRGB(110, 88, 62)
local GOLD = Color3.fromRGB(214, 160, 40)
local WAX = Color3.fromRGB(150, 44, 36)

-- Z_FAN and Z_LIST stay above every Notice Board pin and hit area (Engine/PopupRules.MENU_AMBIENT_MAX_Z = 44).
local Z_COUNTER, Z_SCENE, Z_FAN, Z_LIST = 11, 16, 50, 64
local ROW_H = Layout.SCROLL.rowH - 6

-- Small icon on each row's wax seal until the painted seals exist.
local ICONS = {
	play = "🃏", newRun = "✨", daily = "📅", weekly = "🗓", seed = "🎲", quests = "📜", leaderboards = "🏆", road = "🗺",
	collection = "📚", cardSets = "🎴", flair = "✨", legend = "👑", stats = "📒", store = "🛒", season = "🎟", rewards = "🎁", invite = "💌",
	howToPlay = "📖", tutorial = "🎓", settings = "⚙", volume = "🔊",
}

-- Sets the ZIndex of a button and everything inside it (children carry a ZOff attribute so the plaque stacks correctly).
local function applyZ(button, z)
	button.ZIndex = z
	for _, d in ipairs(button:GetDescendants()) do
		if d:IsA("GuiObject") then
			d.ZIndex = z + (d:GetAttribute("ZOff") or 1)
		end
	end
end

local function off(instance, n)
	instance:SetAttribute("ZOff", n)
	return instance
end

local function round(inst, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = radius
	c.Parent = inst
	return c
end

local function newPlaque(parent)
	local plaque = Instance.new("Frame")
	plaque.Name = "Plaque"
	plaque.BackgroundColor3 = WOOD
	plaque.BorderSizePixel = 0
	plaque.Active = false
	plaque.Parent = parent
	off(plaque, 1)
	round(plaque, UDim.new(0, 7))
	local stroke = Instance.new("UIStroke")
	stroke.Name = "Rim"
	stroke.Color = BRASS
	stroke.Thickness = 2
	stroke.Parent = plaque
	for i = 1, 4 do -- brass corner studs
		local stud = Instance.new("Frame")
		stud.Name = "Stud"
		stud.AnchorPoint = Vector2.new((i % 2 == 1) and 0 or 1, (i <= 2) and 0 or 1)
		stud.Position = UDim2.new((i % 2 == 1) and 0 or 1, (i % 2 == 1) and 4 or -4, (i <= 2) and 0 or 1, (i <= 2) and 4 or -4)
		stud.Size = UDim2.fromOffset(6, 6)
		stud.BackgroundColor3 = BRASS
		stud.BorderSizePixel = 0
		stud.Active = false
		stud.Parent = plaque
		off(stud, 2)
		round(stud, UDim.new(1, 0))
	end
	local name = Instance.new("TextLabel")
	name.Name = "Title"
	name.BackgroundTransparency = 1
	name.Font = Enum.Font.GothamBold
	name.TextSize = 18
	name.TextColor3 = CREAM
	name.TextTransparency = 0
	name.TextStrokeTransparency = 1
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.Active = false
	name.Parent = plaque
	off(name, 3)
	local desc = Instance.new("TextLabel")
	desc.Name = "Desc"
	desc.BackgroundTransparency = 1
	desc.Font = Enum.Font.Gotham
	desc.TextSize = 14
	desc.TextColor3 = CREAM_DIM
	desc.TextTransparency = 0
	desc.TextStrokeTransparency = 1
	desc.TextTruncate = Enum.TextTruncate.AtEnd
	desc.Active = false
	desc.Parent = plaque
	off(desc, 3)
	return plaque, name, desc
end

local function refreshLock(button)
	local plaque = button:FindFirstChild("Plaque")
	if not plaque then return end
	local locked = button:GetAttribute("Locked") == true
	local seal = plaque:FindFirstChild("Seal")
	if seal then
		seal.Glyph.Text = locked and "🔒" or (ICONS[button:GetAttribute("ActionId")] or "•")
		seal.BackgroundColor3 = locked and INK_DIM or WAX
	end
	if button:GetAttribute("Mode") == "row" then
		local name, desc = plaque.Title, plaque.Desc
		desc.Visible = locked
		desc.Text = button:GetAttribute("LockHint") or ""
		name.TextColor3 = locked and INK_DIM or INK
		name.Position = UDim2.fromOffset(44, locked and 2 or 0)
		name.Size = UDim2.new(1, -52, 0, locked and 22 or ROW_H)
	end
end

-- One real, long-lived button per Menu action. `info` = { actionLabel, hotspotLabel, desc }.
function Hotspots.newAction(id, info)
	local button = Instance.new("TextButton")
	button.Name = "Action_" .. id
	button.Text = ""
	button.BackgroundTransparency = 1
	button.AutoButtonColor = false
	button.Size = UDim2.fromOffset(220, 44)
	button:SetAttribute("ActionId", id)
	button:SetAttribute("ActionLabel", info.actionLabel or id)
	button:SetAttribute("HotspotLabel", info.hotspotLabel or info.actionLabel or id)
	button:SetAttribute("Desc", info.desc or "")
	local plaque = newPlaque(button)
	-- Scroll row furniture: a wax seal with an icon on the left and a gold underline that shows on hover.
	local seal = Instance.new("Frame")
	seal.Name = "Seal"
	seal.AnchorPoint = Vector2.new(0, 0.5)
	seal.Position = UDim2.new(0, 8, 0.5, 0)
	seal.Size = UDim2.fromOffset(28, 28)
	seal.BackgroundColor3 = WAX
	seal.BorderSizePixel = 0
	seal.Active = false
	seal.Visible = false
	seal.Parent = plaque
	off(seal, 2)
	round(seal, UDim.new(1, 0))
	local sealArt = ContentArt.getImageId("menu_scene", (id == "play" or id == "newRun") and Layout.SceneArt.sealGold or Layout.SceneArt.sealRed)
	if sealArt then -- painted wax seal (gold for the Deal Me In actions, red for the rest); the flat wax colour is the fallback
		local img = Instance.new("ImageLabel")
		img.Name = "SealArt"
		img.Size = UDim2.fromScale(1.3, 1.3)
		img.AnchorPoint = Vector2.new(0.5, 0.5)
		img.Position = UDim2.fromScale(0.5, 0.5)
		img.BackgroundTransparency = 1
		img.Image = sealArt
		img.ScaleType = Enum.ScaleType.Fit
		img.Active = false
		img.Parent = seal
		off(img, 2)
	end
	local glyph = Instance.new("TextLabel")
	glyph.Name = "Glyph"
	glyph.Size = UDim2.fromScale(1, 1)
	glyph.BackgroundTransparency = 1
	glyph.Font = Enum.Font.Gotham
	glyph.TextSize = 16
	glyph.TextColor3 = CREAM
	glyph.TextTransparency = 0
	glyph.TextStrokeTransparency = 1
	glyph.Text = ICONS[id] or "•"
	glyph.Active = false
	glyph.Parent = seal
	off(glyph, 3)
	local underline = Instance.new("Frame")
	underline.Name = "Underline"
	underline.AnchorPoint = Vector2.new(0, 1)
	underline.Position = UDim2.new(0, 44, 1, -2)
	underline.Size = UDim2.new(1, -56, 0, 2)
	underline.BackgroundColor3 = GOLD
	underline.BorderSizePixel = 0
	underline.Active = false
	underline.Visible = false
	underline.Parent = plaque
	off(underline, 2)
	button.MouseEnter:Connect(function()
		if button:GetAttribute("Mode") == "row" then underline.Visible = true end
	end)
	button.MouseLeave:Connect(function() underline.Visible = false end)
	button:GetAttributeChangedSignal("Locked"):Connect(function() refreshLock(button) end)
	button:GetAttributeChangedSignal("LockHint"):Connect(function() refreshLock(button) end)
	return button
end

-- mode "plaque": a fixed size wooden row (list, sign). mode "row": an ink-lettered scroll row. mode "surface": unused click area.
local function setMode(button, mode, z, size)
	local plaque = button:FindFirstChild("Plaque")
	local name, desc = plaque.Title, plaque.Desc
	local row = mode == "row"
	button:SetAttribute("Mode", mode)
	plaque.BackgroundTransparency = row and 1 or 0
	plaque.Rim.Enabled = not row
	for _, child in ipairs(plaque:GetChildren()) do
		if child.Name == "Stud" then child.Visible = not row end
	end
	plaque.Seal.Visible = row
	plaque.Underline.Visible = false
	name.TextSize = 18
	name.TextColor3 = row and INK or CREAM
	name.TextTransparency = 0
	desc.TextColor3 = row and INK_DIM or CREAM_DIM
	desc.TextTransparency = 0
	if row then
		button.Size = size or UDim2.new(1, 0, 0, ROW_H)
		button.Position = UDim2.new()
		button.AnchorPoint = Vector2.new(0, 0)
		plaque.Visible = true
		plaque.AnchorPoint = Vector2.new(0, 0)
		plaque.Position = UDim2.new()
		plaque.Size = UDim2.fromScale(1, 1)
		name.Text = button:GetAttribute("ActionLabel")
		name.TextXAlignment = Enum.TextXAlignment.Left
		desc.TextSize = 14
		desc.Position = UDim2.fromOffset(44, 22)
		desc.Size = UDim2.new(1, -52, 0, 18)
		desc.TextXAlignment = Enum.TextXAlignment.Left
		refreshLock(button)
	elseif mode == "surface" then
		button.Size = UDim2.fromScale(1, 1)
		button.Position = UDim2.new()
		button.AnchorPoint = Vector2.new(0, 0)
		name.TextXAlignment = Enum.TextXAlignment.Center
	elseif mode == "plaque" then
		button.Size = size or UDim2.fromOffset(220, 44)
		button.Position = UDim2.new()
		button.AnchorPoint = Vector2.new(0, 0)
		plaque.Visible = true
		plaque.AnchorPoint = Vector2.new(0, 0)
		plaque.Position = UDim2.new()
		plaque.Size = UDim2.fromScale(1, 1)
		name.Text = button:GetAttribute("ActionLabel")
		name.Position = UDim2.fromOffset(10, 0)
		name.Size = UDim2.new(1, -20, 1, 0)
		name.TextXAlignment = Enum.TextXAlignment.Center
		desc.Visible = false
	end
	applyZ(button, z)
end

-- Fades a scroll row in or out (rows fade in with a stagger as the scroll unrolls).
local function fadeRow(button, visible, delay, instant)
	local plaque = button:FindFirstChild("Plaque")
	local goal = visible and 0 or 1
	local targets = { plaque.Title, plaque.Desc, plaque.Seal.Glyph }
	local function apply()
		for _, t in ipairs(targets) do
			if instant then
				t.TextTransparency = goal
			else
				TweenService:Create(t, TweenInfo.new(0.18), { TextTransparency = goal }):Play()
			end
		end
		if instant then
			plaque.Seal.BackgroundTransparency = goal
		else
			TweenService:Create(plaque.Seal, TweenInfo.new(0.18), { BackgroundTransparency = goal }):Play()
		end
	end
	if visible and not instant then
		for _, t in ipairs(targets) do t.TextTransparency = 1 end
		plaque.Seal.BackgroundTransparency = 1
		task.delay(delay, apply)
	else
		apply()
	end
end

local function solid(parent, name, color, z)
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundColor3 = color
	f.BorderSizePixel = 0
	f.Active = false
	f.ZIndex = z
	f.Parent = parent
	return f
end

function Hotspots.build(opts)
	local menuFrame, layer, buttons = opts.menuFrame, opts.layer, opts.buttons
	local calm = opts.calm
	local result = { hotspotFrames = {}, animatedCount = 0 }
	local S = Layout.SCROLL

	-- Hidden home for buttons that are not on screen right now.
	local stash = Instance.new("Frame")
	stash.Name = "ActionStash"
	stash.Visible = false
	stash.BackgroundTransparency = 1
	stash.Size = UDim2.fromOffset(1, 1)
	-- never parented: the 19 action plaques exist (handlers stay wired) but are not part of the live GUI until a list or scroll shows them

	local state = { phone = false, openScroll = nil, listOpen = false, w = 1920, h = 1080 }
	local homes = {} -- actionId -> function(button) that puts it where it lives when nothing is open
	local scrolls = {} -- hotspotId -> { frame, content, hotspot, token }
	local lanterns = {} -- tweens for the primary sign
	local hotspotUI = {} -- hotspotId -> { frame, lift, rim }

	-- Click catcher behind open scrolls / the list: a click anywhere else closes them.
	local catcher = Instance.new("TextButton")
	catcher.Name = "FanCatcher"
	catcher.Text = ""
	catcher.AutoButtonColor = false
	catcher.BackgroundTransparency = 1
	catcher.Size = UDim2.fromScale(1, 1)
	catcher.Visible = false
	catcher.Active = true
	catcher.ZIndex = Z_FAN - 2
	catcher.Parent = menuFrame

	local list = Instance.new("ScrollingFrame")
	list.Name = "AllActions"
	list.BackgroundColor3 = Color3.fromRGB(30, 21, 14)
	list.BackgroundTransparency = 0.15
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 6
	list.ScrollBarImageColor3 = BRASS
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.Visible = false
	list.Active = true -- sinks clicks so the Notice Board behind never gets them
	list.ZIndex = Z_LIST - 1
	list.Parent = menuFrame
	require(script.Parent.PopupShield).watchSound(list)
	do
		round(list, UDim.new(0, 10))
		local ls = Instance.new("UIStroke")
		ls.Color = BRASS
		ls.Thickness = 2
		ls.Parent = list
		local pad = Instance.new("UIPadding")
		pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 8), UDim.new(0, 8)
		pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 8), UDim.new(0, 8)
		pad.Parent = list
		local ll = Instance.new("UIListLayout")
		ll.SortOrder = Enum.SortOrder.LayoutOrder
		ll.Padding = UDim.new(0, 6)
		ll.HorizontalAlignment = Enum.HorizontalAlignment.Center
		ll.Parent = list
	end

	local function dock(id)
		local button = buttons[id]
		if not button then return end
		if state.phone then
			setMode(button, "plaque", Z_LIST)
			button.Parent = list
			return
		end
		local home = homes[id]
		if home then home(button) else
			setMode(button, "plaque", Z_FAN)
			button.Parent = stash
		end
	end

	local function dockAll()
		for _, action in ipairs(Layout.Actions) do dock(action.id) end
	end

	local function closeScroll(id, instant)
		local sc = scrolls[id]
		if not sc or not sc.frame.Visible then return end
		sc.token += 1
		local my = sc.token
		local function finish()
			if sc.token ~= my then return end -- reopened meanwhile
			sc.frame.Visible = false
			for _, actionId in ipairs(sc.hotspot.actions) do dock(actionId) end
		end
		if instant or calm() or not menuFrame.Visible then
			finish()
			return
		end
		for _, actionId in ipairs(sc.hotspot.actions) do
			if buttons[actionId] then fadeRow(buttons[actionId], false, 0, false) end
		end
		TweenService:Create(sc.frame, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ Size = UDim2.fromOffset(sc.frame.Size.X.Offset, S.rod * 2) }):Play()
		task.delay(0.27, finish)
	end

	local function closeAll(instant)
		local wasOpen = state.openScroll ~= nil or state.listOpen
		for id in pairs(scrolls) do closeScroll(id, instant) end
		state.openScroll = nil
		if state.listOpen and not state.phone then
			state.listOpen = false
			list.Visible = false
			dockAll()
		end
		catcher.Visible = false
		return wasOpen
	end
	result.closeAll = closeAll
	-- any panel that opens calls OverlayManager.closeAllExcept, so the All actions list and scrolls never stay over it
	require(script.Parent.OverlayManager).register("menuActions", function()
		if state.openScroll ~= nil or state.listOpen then closeAll(true) end
	end)
	catcher.MouseButton1Click:Connect(function() closeAll() end)

	local function fillList()
		for i, action in ipairs(Layout.Actions) do
			local button = buttons[action.id]
			if button then
				setMode(button, "plaque", Z_LIST)
				button.LayoutOrder = i
				button.Parent = list
			end
		end
	end

	local allButton = Instance.new("TextButton")
	allButton.Name = "AllActionsButton"
	allButton.AnchorPoint = Vector2.new(1, 1)
	allButton.Position = UDim2.new(1, -16, 1, -16)
	allButton.Size = UDim2.fromOffset(168, 42)
	allButton.AutoButtonColor = false
	allButton.BackgroundColor3 = Color3.fromRGB(58, 38, 22) -- a dark wood plate with a brass edge like Deal Me In (cream on it is over 10:1)
	allButton.BackgroundTransparency = 0
	allButton.Font = Enum.Font.GothamBold
	allButton.TextSize = 16
	allButton.TextColor3 = Color3.fromRGB(250, 235, 200)
	allButton.TextTransparency = 0
	allButton.TextStrokeTransparency = 1
	allButton.Text = "All actions"
	allButton.ZIndex = Z_LIST
	allButton.Parent = menuFrame
	do
		round(allButton, UDim.new(0, 7))
		local s = Instance.new("UIStroke")
		s.Color = BRASS
		s.Thickness = 2
		s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border -- the default (Contextual) strokes the button's TEXT too, which crushed the letters
		s.Parent = allButton
	end
	pcall(function() require(script.Parent.TavernKit).paintedButton(allButton, "secondary") end) -- ornate dark wood button like Run Over and the Counter, flat look if it does not load
	local function toggleList()
		if state.listOpen then
			closeAll()
			return
		end
		closeAll(true)
		state.listOpen = true
		list.Visible = true
		catcher.Visible = true
		fillList()
	end
	allButton.MouseButton1Click:Connect(toggleList)

	UserInputService.InputBegan:Connect(function(input, processed)
		if input.KeyCode == Enum.KeyCode.Escape and (state.openScroll or state.listOpen) and menuFrame.Visible then
			closeAll()
		end
	end)

	-- ===== The counter and the beam (the tavern layout only; the Living Map has none) =====
	if not Layout.world then
		local C = Layout.Counter
		local counter = solid(layer, "Counter", Color3.fromRGB(88, 58, 34), Z_COUNTER)
		counter.AnchorPoint = Vector2.new(0.5, 0)
		counter.Position = UDim2.fromScale(0.5, C.top)
		counter.Size = UDim2.fromScale(1.08, C.bottom - C.top + 0.04)
		local lip = solid(counter, "Lip", Color3.fromRGB(128, 88, 52), Z_COUNTER + 1) -- lit top edge of the bar
		lip.Size = UDim2.new(1, 0, 0.1, 0)
		local trim = solid(counter, "BrassTrim", BRASS, Z_COUNTER + 1)
		trim.Position = UDim2.fromScale(0, 0.12)
		trim.Size = UDim2.new(1, 0, 0, 3)
		local front = solid(counter, "Front", Color3.fromRGB(62, 40, 24), Z_COUNTER + 1)
		front.Position = UDim2.fromScale(0, 0.55)
		front.Size = UDim2.fromScale(1, 0.45)
		-- painted counter strip (category menu_scene) slots in here once it exists
		local art = ContentArt.getImageId("menu_scene", "menu_counter")
		if art then
			local img = Instance.new("ImageLabel")
			img.Name = "Art"
			img.Size = UDim2.fromScale(1, 1)
			img.BackgroundTransparency = 1
			img.Image = art
			img.ScaleType = Enum.ScaleType.Stretch
			img.Active = false
			img.ZIndex = Z_COUNTER + 2
			img.Parent = counter
		end
		local beam = solid(layer, "CeilingBeam", Color3.fromRGB(70, 46, 28), 12)
		beam.AnchorPoint = Vector2.new(0.5, 0)
		beam.Position = UDim2.fromScale(0.5, 0.33)
		beam.Size = UDim2.fromScale(0.3, 0.018)
		local beamTrim = solid(beam, "Trim", BRASS, 13)
		beamTrim.Size = UDim2.new(1, 0, 0, 2)
	end

	-- ===== Hotspot objects =====
	local function hover(hotspot, on)
		local ui = hotspotUI[hotspot.id]
		if not ui then return end
		if Layout.roomPainted and not ui.strip then -- the painted room: a soft warm glow on the prop and its name plate above it, nothing at rest
			local object = ui.frame:FindFirstChild("Object")
			if object then
				object.BackgroundColor3 = GLOW
				TweenService:Create(object, TweenInfo.new(calm() and 0 or 0.15), { BackgroundTransparency = on and 0.85 or 1 }):Play()
			end
			local plate = ui.frame:FindFirstChild("NamePlate")
			if plate then plate.Visible = on end
			if object and opts.onLift then opts.onLift(object, on) end -- 4 px lift and the hover sound (none in Calm mode)
			if opts.onHover then opts.onHover(on) end
			return
		end
		TweenService:Create(ui.rim, TweenInfo.new(0.15), { Transparency = on and 0.1 or (hotspot.lit and 0.4 or 0.7) }):Play()
		if not calm() then
			TweenService:Create(ui.lift, TweenInfo.new(0.15, Enum.EasingStyle.Quad), { Scale = on and 1.04 or 1 }):Play()
			local plate = ui.frame:FindFirstChild("NamePlate")
			if plate and Layout.world then -- the name tag rises 4 px with the landmark
				TweenService:Create(plate, TweenInfo.new(0.15, Enum.EasingStyle.Quad), { Position = UDim2.new(0.5, 0, 1, on and -2 or 2) }):Play()
			end
		end
		if opts.onHover then opts.onHover(on) end
	end

	local function openScroll(id)
		local sc = scrolls[id]
		if not sc or state.phone then return end
		closeAll(true)
		state.openScroll = id
		sc.token += 1
		local hotspot = sc.hotspot
		local full = #hotspot.actions * S.rowH + S.pad * 2 + S.rod * 2
		sc.frame.Visible = true
		catcher.Visible = true
		for i, actionId in ipairs(hotspot.actions) do
			local button = buttons[actionId]
			if button then
				setMode(button, "row", Z_FAN + 2)
				button.LayoutOrder = i
				button.Parent = sc.content
			end
		end
		local instant = calm()
		if instant then
			sc.frame.Size = UDim2.fromOffset(sc.frame.Size.X.Offset, full)
		else
			sc.frame.Size = UDim2.fromOffset(sc.frame.Size.X.Offset, S.rod * 2)
			TweenService:Create(sc.frame, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ Size = UDim2.fromOffset(sc.frame.Size.X.Offset, full) }):Play()
		end
		for i, actionId in ipairs(hotspot.actions) do
			if buttons[actionId] then fadeRow(buttons[actionId], true, 0.1 + 0.04 * (i - 1), instant) end
		end
	end
	result.openScroll = openScroll

	local function positionScroll(sc)
		local l, t, r, b = Layout.scrollRect(sc.hotspot, #sc.hotspot.actions, state.w, state.h)
		sc.frame.Position = UDim2.fromOffset((l + r) / 2, b)
		sc.frame.Size = UDim2.fromOffset(r - l, sc.frame.Visible and (b - t) or S.rod * 2)
	end

	local function buildScroll(hotspot)
		local frame = Instance.new("Frame")
		frame.Name = "Scroll_" .. hotspot.id
		frame.AnchorPoint = Vector2.new(0.5, 1)
		frame.BackgroundTransparency = 1
		frame.Visible = false
		frame.Active = true -- sinks clicks over the whole scroll
		frame.ZIndex = Z_FAN
		frame.Parent = layer
		require(script.Parent.PopupShield).watchSound(frame) -- scroll_open / scroll_close through the shared popup gate
		local paper = solid(frame, "Parchment", PARCHMENT, Z_FAN)
		paper.Active = true
		paper.Position = UDim2.fromOffset(0, S.rod)
		paper.Size = UDim2.new(1, 0, 1, -S.rod * 2)
		paper.ClipsDescendants = true
		local paperArt = ContentArt.getImageId("menu_scene", Layout.SceneArt.parchment)
		if paperArt then -- painted parchment tile under the rows (the flat colour stays as the fallback)
			local tile = Instance.new("ImageLabel")
			tile.Name = "ParchmentArt"
			tile.Size = UDim2.fromScale(1, 1)
			tile.BackgroundTransparency = 1
			tile.Image = paperArt
			tile.ScaleType = Enum.ScaleType.Stretch
			tile.Active = false
			tile.ZIndex = Z_FAN
			tile.Parent = paper
		end
		local edge = Instance.new("UIStroke")
		edge.Color = Color3.fromRGB(176, 140, 84)
		edge.Thickness = 1
		edge.Parent = paper
		local content = Instance.new("Frame")
		content.Name = "Rows"
		content.BackgroundTransparency = 1
		content.Position = UDim2.fromOffset(S.pad, S.pad)
		content.Size = UDim2.new(1, -S.pad * 2, 0, #hotspot.actions * S.rowH)
		content.ZIndex = Z_FAN + 1
		content.Parent = paper
		local layout = Instance.new("UIListLayout")
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Padding = UDim.new(0, 6)
		layout.Parent = content
		for _, edgeAt in ipairs({ { "TopRod", 0 }, { "BottomRod", 1 } }) do
			local rod = solid(frame, edgeAt[1], WOOD_LIGHT, Z_FAN + 3)
			rod.AnchorPoint = Vector2.new(0.5, edgeAt[2])
			rod.Position = UDim2.new(0.5, 0, edgeAt[2], 0)
			rod.Size = UDim2.new(1, 12, 0, S.rod)
			round(rod, UDim.new(0, 6))
			local rodArt = ContentArt.getImageId("menu_scene", edgeAt[2] == 0 and Layout.SceneArt.scrollTop or Layout.SceneArt.scrollBottom)
			if rodArt then -- painted rod over the wooden one
				local img = Instance.new("ImageLabel")
				img.Name = "RodArt"
				img.Size = UDim2.fromScale(1, 1)
				img.BackgroundTransparency = 1
				img.Image = rodArt
				img.ScaleType = Enum.ScaleType.Stretch
				img.Active = false
				img.ZIndex = Z_FAN + 3
				img.Parent = rod
			end
			for side = 0, 1 do -- brass caps on the rod ends
				local cap = solid(rod, "Cap", BRASS, Z_FAN + 4)
				cap.AnchorPoint = Vector2.new(side, 0.5)
				cap.Position = UDim2.new(side, side == 0 and -2 or 2, 0.5, 0)
				cap.Size = UDim2.fromOffset(8, S.rod + 4)
				round(cap, UDim.new(0, 3))
			end
		end
		local sc = { frame = frame, content = content, hotspot = hotspot, token = 0 }
		scrolls[hotspot.id] = sc
		return sc
	end

	for _, hotspot in ipairs(Layout.Hotspots) do
		local frame = Instance.new("Frame")
		frame.Name = "Hotspot_" .. hotspot.id
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		frame.Position = UDim2.fromScale(hotspot.x, hotspot.y)
		frame.Size = UDim2.fromScale(1, hotspot.s)
		frame.BackgroundTransparency = 1
		frame.ZIndex = 13
		frame.Parent = layer
		local aspect = Instance.new("UIAspectRatioConstraint")
		aspect.AspectRatio = hotspot.asp
		aspect.Parent = frame
		result.hotspotFrames[hotspot.id] = frame

		-- The object: a soft rounded wood medallion with the painted art inset (so the dark art background never shows as a
		-- hard square over the scene), emoji until the art exists.
		local object = Instance.new("Frame")
		object.Name = "Object"
		object.AnchorPoint = Vector2.new(0.5, 0.5)
		object.Position = UDim2.fromScale(0.5, 0.5)
		object.Size = UDim2.fromScale(1, 1)
		object.BackgroundColor3 = Color3.fromRGB(84, 56, 34)
		object.BackgroundTransparency = 0.12
		object.BorderSizePixel = 0
		object.ZIndex = 14
		object.Parent = frame
		round(object, UDim.new(0.28, 0))
		local rim = Instance.new("UIStroke")
		rim.Name = "Glow"
		rim.Color = GLOW
		rim.Thickness = hotspot.lit and 3 or 2
		rim.Transparency = Layout.roomPainted and 1 or 0.7 -- painted room: no outline at rest, hover glows the Object fill instead
		rim.Parent = object
		local lift = Instance.new("UIScale")
		lift.Parent = object
		-- counter items prefer their painted object (menu_scene) and sit straight on the counter; the older medallion art and the
		-- emoji are the fallbacks
		local itemId = hotspot.item and ContentArt.getImageId("menu_scene", Layout.SceneArt.items[hotspot.item]) or nil
		if Layout.world and hotspot.item then
			-- the painted landmark; without it the medallion or emoji below stands in (the counter painting is not used on the map)
			itemId = Layout.WorldArt[hotspot.id] and ContentArt.getImageId(Layout.WorldArtCategory or "menu_world", Layout.WorldArt[hotspot.id]) or nil
		end
		local artId = itemId or (hotspot.art and ContentArt.getImageId("menu_icons", hotspot.art) or nil)
		if itemId then
			object.BackgroundTransparency = 1
		end
		if artId then
			local img = Instance.new("ImageLabel")
			img.Name = "Art"
			img.Size = itemId and UDim2.fromScale(1, 1) or UDim2.fromScale(0.86, 0.86)
			img.AnchorPoint = Vector2.new(0.5, 0.5)
			img.Position = UDim2.fromScale(0.5, 0.5)
			img.BackgroundTransparency = 1
			img.Image = artId
			img.ScaleType = itemId and Enum.ScaleType.Fit or Enum.ScaleType.Crop
			img.Active = false
			img.ZIndex = 15
			img.Parent = object
			if not itemId then round(img, UDim.new(0.24, 0)) end
		else
			local glyph = Instance.new("TextLabel")
			glyph.Name = "Glyph"
			glyph.Size = UDim2.fromScale(0.8, 0.7)
			glyph.AnchorPoint = Vector2.new(0.5, 0.5)
			glyph.Position = UDim2.fromScale(0.5, 0.5)
			glyph.BackgroundTransparency = 1
			glyph.Font = Enum.Font.Gotham
			glyph.TextScaled = true
			glyph.Text = hotspot.glyph
			glyph.TextTransparency = 0
			glyph.TextStrokeTransparency = 1
			glyph.Active = false
			glyph.ZIndex = 15
			glyph.Parent = object
		end
		local ui = { frame = frame, lift = lift, rim = rim }
		hotspotUI[hotspot.id] = ui

		if hotspot.id == "play" then
			-- the real Play button is the click surface of the sign; New Run is a small plaque on it
			local primary = buttons.play
			ui.surface = primary
			if Layout.world then object.Visible = false end -- the sign is the plaque itself: no dark medallion (its top edge was cut off) behind it
			homes.play = function(button)
				setMode(button, "surface", Z_SCENE)
				button.Parent = frame
				local plaque = button:FindFirstChild("Plaque")
				plaque.Visible = true
				plaque.AnchorPoint = Vector2.new(0.5, 1)
				plaque.Position = UDim2.new(0.5, 0, 1, -46) -- New Run (34 px) sits under it with a 12 px gap
				plaque.Size = UDim2.fromOffset(210, 38)
				plaque.Desc.Visible = false
				plaque.Title.Text = button:GetAttribute("HotspotLabel")
				plaque.Title.Size = UDim2.new(1, -20, 1, 0)
				plaque.Title.Position = UDim2.fromOffset(10, 0)
				plaque.Title.TextSize = 22
				require(script.Parent.MenuPlayButton).style(plaque, lanterns, TweenService) -- Concept T green button look and gentle pulse
			end
			homes.newRun = function(button)
				setMode(button, "plaque", Z_SCENE + 2, UDim2.fromOffset(150, 34))
				button.AnchorPoint = Vector2.new(0.5, 1)
				button.Position = UDim2.new(0.5, 0, 1, 0)
				button:FindFirstChild("Plaque").Title.TextSize = 16
				button.Parent = frame
				pcall(function() -- ornate dark wood plate (150 x 34 picks the wide whole picture), the flat plaque stays if art is missing
					local kit = require(script.Parent.TavernKit)
					local plaque = button:FindFirstChild("Plaque")
					local img = kit.painted(plaque, require(game:GetService("ReplicatedStorage").Shared.Engine.TavernStyle).buttonPiece("secondary", 150, 34))
					if img then plaque.BackgroundTransparency = 1 end
				end)
			end
			if primary then
				primary.MouseEnter:Connect(function() hover(hotspot, true) end)
				primary.MouseLeave:Connect(function() hover(hotspot, false) end)
			end
			for i = 0, Layout.world and -1 or 1 do -- two chains from the ceiling beam (none on the Living Map)
				local chain = solid(frame, "Chain", Color3.fromRGB(120, 100, 70), 13)
				chain.AnchorPoint = Vector2.new(0.5, 1)
				chain.Position = UDim2.fromScale(0.22 + i * 0.56, 0.02)
				chain.Size = UDim2.new(0, 4, 0.44, 0)
			end
			-- lantern pulse of the primary sign
			if not Layout.roomPainted then -- the painted room has its own pulse ring on the deck
				table.insert(lanterns, TweenService:Create(rim, TweenInfo.new(1.25, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
					{ Thickness = 7, Transparency = 0.1 }))
				rim.Transparency = 0.4
				result.animatedCount += 1
			end
		else
			-- a counter item: a click unrolls its scroll; a carved name plate sits under it
			local surface = Instance.new("TextButton")
			surface.Name = "Surface"
			surface.Text = ""
			surface.BackgroundTransparency = 1
			surface.AutoButtonColor = false
			surface.Size = UDim2.fromScale(1, 1)
			surface.ZIndex = Z_SCENE
			surface.Parent = frame
			surface:SetAttribute("Mode", "surface")
			ui.surface = surface
			surface.MouseEnter:Connect(function() hover(hotspot, true) end)
			surface.MouseLeave:Connect(function() hover(hotspot, false) end)
			surface.MouseButton1Click:Connect(function()
				if state.openScroll == hotspot.id then closeAll() else openScroll(hotspot.id) end
			end)
			local plate = solid(frame, "NamePlate", WOOD, Z_SCENE - 1)
			plate.AnchorPoint = Vector2.new(0.5, 0)
			plate.Position = UDim2.new(0.5, 0, 1, 2)
			plate.Size = UDim2.fromScale(Layout.PLATE_W, Layout.PLATE_H / hotspot.s)
			round(plate, UDim.new(0, 6))
			local pr = Instance.new("UIStroke")
			pr.Color = BRASS
			pr.Thickness = 1.5
			pr.Parent = plate
			local label = Instance.new("TextLabel")
			label.Name = "Label"
			label.Size = UDim2.fromScale(1, 1)
			label.BackgroundTransparency = 1
			label.Font = Enum.Font.GothamBold
			label.TextSize = 16
			label.TextColor3 = CREAM
			label.TextTransparency = 0
			label.TextStrokeTransparency = 1
			label.TextTruncate = Enum.TextTruncate.AtEnd
			label.Text = hotspot.label
			label.Active = false
			label.ZIndex = Z_SCENE
			label.Parent = plate
			buildScroll(hotspot)
			for _, id in ipairs(hotspot.actions) do
				homes[id] = nil -- stays in the stash until the scroll opens
			end
		end

		if hotspot.id == "rulebook" and opts.tutorialRibbon then
			local source = opts.tutorialRibbon
			local ribbon = Instance.new("TextLabel") -- mirrors the tutorial's New ribbon until it is done
			ribbon.Name = "NewRibbon"
			ribbon.AnchorPoint = Vector2.new(1, 0)
			ribbon.Position = UDim2.new(1, -2, 0, 2)
			ribbon.Size = UDim2.fromOffset(44, 22)
			ribbon.BackgroundColor3 = Color3.fromRGB(176, 52, 40)
			ribbon.Font = Enum.Font.GothamBold
			ribbon.Text = "New"
			ribbon.TextSize = 15
			ribbon.TextColor3 = Color3.fromRGB(250, 235, 200)
			ribbon.TextTransparency = 0
			ribbon.TextStrokeTransparency = 1
			ribbon.Rotation = 8
			ribbon.Active = false
			ribbon.ZIndex = 20
			ribbon.Visible = source.Visible
			ribbon.Parent = frame
			round(ribbon, UDim.new(0, 5))
			source:GetPropertyChangedSignal("Visible"):Connect(function() ribbon.Visible = source.Visible end)
			if source.Visible and not Layout.roomPainted then
				table.insert(lanterns, TweenService:Create(rim, TweenInfo.new(1.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
					{ Transparency = 0.1, Thickness = 4 }))
				result.animatedCount += 1
			end
		end
	end

	-- Dock everything where it lives.
	dockAll()

	-- The cork board on the right wall of the painted room opens the All actions list (the notes on it keep their own clicks).
	local noticeHit
	if Layout.room then
		noticeHit = Instance.new("TextButton")
		noticeHit.Name = "NoticeBoardHit"
		noticeHit.Text = ""
		noticeHit.BackgroundTransparency = 1
		noticeHit.AutoButtonColor = false
		noticeHit.ZIndex = 12
		noticeHit.Parent = layer
		noticeHit.MouseButton1Click:Connect(toggleList)
		noticeHit.MouseEnter:Connect(function() if opts.onHover then opts.onHover(true) end if opts.onNoticeHover then opts.onNoticeHover(true) end end)
		noticeHit.MouseLeave:Connect(function() if opts.onHover then opts.onHover(false) end if opts.onNoticeHover then opts.onNoticeHover(false) end end)
	end

	-- Tavern Room: place every prop frame on its rectangle of the picture (mapped through the crop). Hotspots that fall outside the
	-- visible crop become plain plates in a bottom strip. With a painted picture the prop is invisible until hovered.
	-- The entry drop-in tweens each hotspot back to the position it had when entry() ran. If the window got its real
	-- size AFTER that (it starts small while the game loads), those tweens used to pull every hotspot back to the old,
	-- small-window position while placeRoom had already given it the new size: the Jukebox's hit area ended up in the
	-- middle of the room, the Rulebook's on the coin jar. placeRoom now cancels any entry motion and owns the position.
	local entryTweens, entryToken = {}, 0
	local function cancelEntry()
		entryToken = entryToken + 1
		for _, tween in ipairs(entryTweens) do tween:Cancel() end
		entryTweens = {}
	end
	local function placeRoom(w, h)
		cancelEntry()
		for _, hs in ipairs(Layout.Hotspots) do
			local f = result.hotspotFrames[hs.id]
			local ui = hotspotUI[hs.id]
			if f then
				local l, t, r, b = Layout.rect(hs, w, h)
				if hs.id == "play" and b > h - 24 then t, b = t - (b - (h - 24)), h - 24 end -- 24 px margin under New Run
				f.Position = UDim2.fromOffset((l + r) / 2, (t + b) / 2)
				f.Size = UDim2.fromOffset(r - l, b - t)
				local aspect = f:FindFirstChildOfClass("UIAspectRatioConstraint")
				if aspect then aspect:Destroy() end
				local strip = Layout.isStrip and Layout.isStrip(hs.id, w, h) or false
				if ui then ui.strip = strip end
				local object = f:FindFirstChild("Object")
				local plate = f:FindFirstChild("NamePlate")
				if Layout.roomPainted then
					if object then
						object.BackgroundColor3 = strip and Color3.fromRGB(84, 56, 34) or GLOW
						object.BackgroundTransparency = strip and 0.12 or 1
						for _, d in ipairs(object:GetChildren()) do
							if d.Name == "Glyph" or d.Name == "Art" then d.Visible = strip end
						end
					end
					if ui then ui.rim.Transparency = 1 end
					if plate then
						plate.AnchorPoint = Vector2.new(0.5, 1)
						plate.Position = UDim2.new(0.5, 0, 0, -4)
						plate.Size = UDim2.fromOffset(math.max(120, r - l), 30)
						plate.Visible = strip
						if strip then
							plate.AnchorPoint = Vector2.new(0.5, 0)
							plate.Position = UDim2.new(0.5, 0, 1, 2)
						end
					end
				end
			end
		end
		if noticeHit then
			local l, t, r, b = Layout.rect(Layout.noticeSpot, w, h)
			noticeHit.Position = UDim2.fromOffset(l, t)
			noticeHit.Size = UDim2.fromOffset(r - l, b - t)
		end
	end

	function result.applyViewport(w, h)
		state.w, state.h = w, h
		if Layout.room then placeRoom(w, h) end
		for _, sc in pairs(scrolls) do positionScroll(sc) end
		local phone = Layout.isPhone(w)
		if phone == state.phone and result._applied then return end
		result._applied = true
		state.phone = phone
		layer.Visible = not phone
		allButton.Visible = not phone
		catcher.Visible = false
		for _, sc in pairs(scrolls) do sc.frame.Visible = false end
		state.openScroll = nil
		if phone then
			list.AnchorPoint = Vector2.new(0.5, 0)
			list.Position = UDim2.new(0.5, 0, 0, 160) -- below the title
			list.Size = UDim2.new(0, 252, 1, -172)
			list.Visible = true
			fillList()
			if buttons.play then buttons.play.LayoutOrder = 0 end
		else
			list.AnchorPoint = Vector2.new(1, 1)
			list.Position = UDim2.new(1, -16, 1, -62)
			list.Size = UDim2.new(0, 252, 0.7, 0)
			list.Visible = false
			state.listOpen = false
			dockAll()
		end
	end

	-- Entry: the sign and the counter items drop in with a 0.06s stagger (skipped in calm mode).
	local entered = false
	function result.entry()
		if entered or calm() then
			entered = true
			return
		end
		entered = true
		cancelEntry()
		local myToken = entryToken
		for i, hotspot in ipairs(Layout.Hotspots) do
			local frame = result.hotspotFrames[hotspot.id]
			local target = frame.Position
			frame.Position = target - UDim2.fromOffset(0, hotspot.item and -40 or 40)
			task.delay(0.06 * (i - 1), function()
				if entryToken ~= myToken then return end -- the room was laid out again since: placeRoom already put this hotspot where it belongs
				local tween = TweenService:Create(frame, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = target })
				entryTweens[#entryTweens + 1] = tween
				tween:Play()
			end)
		end
	end

	function result.startLoops()
		if calm() then return end
		for _, t in ipairs(lanterns) do t:Play() end
	end
	function result.stopLoops()
		for _, t in ipairs(lanterns) do t:Cancel() end
		for _, hotspot in ipairs(Layout.Hotspots) do
			local ui = hotspotUI[hotspot.id]
			if ui then
				ui.rim.Thickness = hotspot.lit and 3 or 2
				ui.rim.Transparency = Layout.roomPainted and 1 or (hotspot.lit and 0.4 or 0.7)
			end
		end
	end

	return result
end

return Hotspots
