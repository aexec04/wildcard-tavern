--[[
	Client/FlairDressingRoom.lua
	The inside of the Flair panel, v2: three calm columns. Left, one tab per Flair category (taken from Flair.view, nothing
	hardcoded). Centre, a grid of solid flair tiles for the open category: one round icon each, the name and a status line
	on the tile (Equipped, Unlocked, or the unlock goal), locked pieces as muted silhouettes. Right, a preview plate with a
	live preview (name plate, score numbers, pop effect) and a detail card with Equip, Unequip, Preview and Buy. On phones
	the tabs become a row on top and the preview plate drops to the bottom. Nothing overlaps; text never sits on art.
	One art layer (flair_stage) sits behind the preview plate at very low opacity. One reusable tooltip lives on the
	ScreenGui, clamped on screen and kept off the live preview.
	"Reduce screen shake" skips every tween and loop. Data mapping and layout maths: Engine/FlairRoomLayout.lua (tested).
	Display only: the server validates equip and purchase (remotes EquipFlair, StorePurchase). Unequip equips the
	category's default piece.

	FlairDressingRoom.build(deps, panel) -> { closeButton, bundleButton, refresh(state), reset(), startStage(), stopStage(), hideTip() }
	deps: screenGui, roundCorner, polishButton, playClickSfx, particleBurst
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local TextService = game:GetService("TextService")

local FlairDressingRoom = {}

function FlairDressingRoom.build(deps, panel)
	local Engine = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine")
	local Layout = require(Engine:WaitForChild("FlairRoomLayout"))
	local Scene = require(Engine:WaitForChild("FlairSceneLayout"))
	local ContentArt = require(Engine:WaitForChild("ContentArt"))
	local ArtIcon = require(script.Parent.ArtIcon)
	local FlairFX = require(script.Parent.FlairFX)
	local ClientSettings = require(script.Parent.ClientSettings)
	local StorePanel = require(script.Parent.StorePanel)
	local Remotes = ReplicatedStorage:WaitForChild("Remotes")
	local EquipRemote = Remotes:WaitForChild("EquipFlair")
	local PurchaseRemote = Remotes:WaitForChild("StorePurchase")

	local INK = Color3.fromRGB(60, 40, 22)
	local CREAM = Color3.fromRGB(250, 235, 200)
	local GOLD = Color3.fromRGB(222, 182, 104)
	local BRASS = Color3.fromRGB(176, 138, 70)
	local VELVET = Color3.fromRGB(96, 26, 46)
	local GREEN = Color3.fromRGB(86, 140, 80)
	local PLATE = Color3.fromRGB(38, 28, 22)
	local TILE = Color3.fromRGB(52, 38, 28)
	local PARCHMENT = Color3.fromRGB(226, 208, 170)
	local Z = 43

	local function tween(inst, seconds, props, style)
		if ClientSettings.get("reduceShake") == true then
			for k, v in pairs(props) do inst[k] = v end
			return
		end
		TweenService:Create(inst, TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props):Play()
	end

	local function make(class, parent, props)
		local o = Instance.new(class)
		if o:IsA("GuiObject") then
			o.BorderSizePixel = 0
			if o:IsA("TextLabel") or o:IsA("TextButton") then
				o.BackgroundTransparency = 1
				o.Font = Enum.Font.GothamBold
				o.TextColor3 = CREAM
				o.TextTransparency = 0
				o.TextStrokeTransparency = 1
				o.TextSize = 14
			end
			o.ZIndex = Z
		end
		for k, v in pairs(props or {}) do o[k] = v end
		o.Parent = parent
		return o
	end

	local function rectUdim(r)
		return UDim2.fromOffset(r.x, r.y), UDim2.fromOffset(r.w, r.h)
	end
	local function setRect(inst, r)
		inst.Position, inst.Size = rectUdim(r)
	end

	local function round(inst, radius)
		deps.roundCorner(inst, radius)
	end
	local function circle(inst)
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0.5, 0)
		c.Parent = inst
	end
	local function stroke(inst, color, thickness)
		local s = Instance.new("UIStroke")
		s.Color = color
		s.Thickness = thickness
		s.Parent = inst
		return s
	end

	-- A recorded flair_ui Image id is laid behind the content (parented to the piece so Clone() keeps it).
	local function artOver(parent, key, props)
		local id = ContentArt.getImageId("flair_ui", key)
		if not id then return nil end
		local img = make("ImageLabel", parent, { Name = "Art_" .. key, BackgroundTransparency = 1, Image = id, Size = UDim2.fromScale(1, 1),
			ScaleType = Enum.ScaleType.Fit, ZIndex = Z, Active = false })
		for k, v in pairs(props or {}) do img[k] = v end
		return img
	end

	-- ===== placement bookkeeping: everything the layout owns is re-placed when the panel size changes =====
	local placed = {} -- { inst, fn(R) -> rect }
	local function bind(inst, fn)
		placed[#placed + 1] = { inst = inst, fn = fn }
		return inst
	end

	-- ===== state =====
	local view = nil
	local drawers = {} -- categories: { id, name, icon, ownedCount, total, items }
	local openSlot = nil -- slot id of the open category
	local chosenId = nil -- piece shown in the detail card
	local previewed = {} -- slotId -> option row (Preview taps)
	local equippedBySlot = {}
	local firstSightOwned = nil
	local lastEquipped = {}
	local scrollMemory = {}
	local R = Layout.rects(1000, 600)

	-- ===== painted scene (flair_room_a): drawn under everything once its Image id is recorded and the panel is big enough =====
	local sceneId = ContentArt.getImageId("panel_scene", Scene.ART_KEY)
	local sceneHolder = make("Frame", panel, { Name = "FlairScene", BackgroundColor3 = Color3.fromRGB(26, 18, 12), ClipsDescendants = true, Visible = false, Active = false })
	local SCENE_WASH = 0.3 -- the same painting, cover-fitted behind the picture under a dark wash, so uncovered bands read as the room (not flat brown)
	local sceneBack = make("ImageLabel", sceneHolder, { Name = "Backdrop", BackgroundTransparency = 1, Image = sceneId or "", ScaleType = Enum.ScaleType.Stretch, Active = false, Visible = false })
	local sceneWash = make("Frame", sceneHolder, { Name = "BackdropWash", BackgroundColor3 = Color3.fromRGB(26, 18, 12), BackgroundTransparency = SCENE_WASH, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), Active = false, Visible = false })
	local sceneBase = 0
	local sceneImage = make("ImageLabel", sceneHolder, { Name = "Picture", BackgroundTransparency = 1, Image = sceneId or "", ScaleType = Enum.ScaleType.Stretch, Active = false })
	local sceneVignette = make("Frame", sceneHolder, { Name = "Vignette", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Active = false }) -- over the picture
	local sceneMarks = make("Frame", sceneHolder, { Name = "SoonMarks", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Active = false })
	local roomLights = require(script.Parent.RoomLights).attach(sceneHolder, { room = "flair", zIndex = Z, visible = function() return sceneHolder.Visible and panel.Visible and (panel.Parent == nil or not panel.Parent:IsA("GuiObject") or panel.Parent.Visible) end })
	local sceneOn = false
	local sceneS = nil -- the last Scene.place result while the painted room is on
	local truncatedLabels = 0 -- cubby names that do not fit their two lines (reset on every relayout)
	-- the dark vignette: strips in the holder colour, opaque at the picture's uncovered edge and fading inward (no stretched picture pixels)
	local function paintVignette(items)
		for _, ch in ipairs(sceneVignette:GetChildren()) do ch:Destroy() end
		for _, it in ipairs(items) do
			local f = make("Frame", sceneVignette, { Name = it.name, BackgroundColor3 = Color3.fromRGB(26, 18, 12), BackgroundTransparency = 0,
				Position = UDim2.fromOffset(it.rect.x, it.rect.y), Size = UDim2.fromOffset(it.rect.w, it.rect.h), Active = false })
			local g = Instance.new("UIGradient")
			g.Rotation = it.rotation
			local keys = {}
			for _, k in ipairs(it.points) do keys[#keys + 1] = NumberSequenceKeypoint.new(k[1], sceneBase + (1 - sceneBase) * k[2]) end
			g.Transparency = NumberSequence.new(keys)
			g.Parent = f
		end
	end
	-- plates of categories that do not exist stay intact painted plates with a faint "More soon" (no hole in the wall)
	local function paintPatches()
		for _, ch in ipairs(sceneMarks:GetChildren()) do ch:Destroy() end
		if not sceneS or #drawers == 0 then return end
		for i = #drawers + 1, #sceneS.tabs do
			local t = sceneS.tabs[i]
			make("TextLabel", sceneMarks, { Name = "SoonPlate" .. i, Position = UDim2.fromOffset(t.x + 14, t.y), Size = UDim2.fromOffset(t.w - 28, t.h),
				Text = "More soon", TextSize = 14, Font = Enum.Font.GothamMedium, TextTransparency = 0.5, TextColor3 = Color3.fromRGB(226, 208, 170), Active = false })
		end
	end

	-- ===== title, bundle, close =====
	local titleBox = bind(make("Frame", panel, { Name = "TitleBox", BackgroundTransparency = 1 }), function(r) return r.title end)
	local titleLabel = make("TextLabel", titleBox, { Size = UDim2.new(1, 0, 0, 34), TextSize = 28, Text = "Flair: the Dressing Room",
		TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd })
	make("TextLabel", titleBox, { Position = UDim2.fromOffset(0, 34), Size = UDim2.new(1, 0, 0, 22), Font = Enum.Font.GothamMedium, TextSize = 16,
		Text = "Looks only. Flair never changes your score.", TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd })

	local bundleButton = bind(make("TextButton", panel, { Name = "FlairBundle", TextSize = 14, TextColor3 = INK, BackgroundColor3 = GOLD, BackgroundTransparency = 0,
		Text = "Flair Bundle", Visible = false }), function(r) return r.bundle end)
	deps.polishButton(bundleButton, 8)
	bundleButton.MouseButton1Click:Connect(function()
		deps.playClickSfx()
		PurchaseRemote:FireServer("flair_bundle")
	end)

	local closeButton = bind(make("TextButton", panel, { Name = "FlairClose", TextSize = 15, BackgroundColor3 = Color3.fromRGB(70, 55, 40), BackgroundTransparency = 0,
		Text = "Close" }), function(r) return r.close end)
	deps.polishButton(closeButton, 8)

	-- ===== the single reusable tooltip =====
	local tip = make("Frame", deps.screenGui, { Name = "FlairTooltip", BackgroundColor3 = Color3.fromRGB(30, 22, 16), Visible = false, ZIndex = 190, Active = false })
	round(tip, 8)
	stroke(tip, GOLD, 1.5)
	local tipText = make("TextLabel", tip, { Position = UDim2.fromOffset(8, 6), Size = UDim2.new(1, -16, 1, -12), ZIndex = 191, Font = Enum.Font.GothamMedium,
		TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top })
	local mirror -- assigned below; the tooltip stays off it

	local function hideTip() tip.Visible = false end
	local function showTip(target, text)
		if not target or not target.Parent or text == "" then return end
		local screen = deps.screenGui.AbsoluteSize
		local maxW = math.min(280, screen.X - 16)
		local ok, bounds = pcall(TextService.GetTextSize, TextService, text, 14, Enum.Font.GothamMedium, Vector2.new(maxW - 16, 1000))
		bounds = ok and bounds or Vector2.new(maxW - 16, 36)
		local size = { w = math.min(maxW, math.ceil(bounds.X) + 18), h = math.ceil(bounds.Y) + 14 }
		local ap, asz = target.AbsolutePosition, target.AbsoluteSize
		local avoid = nil
		if mirror and mirror.Parent then
			avoid = { x = mirror.AbsolutePosition.X, y = mirror.AbsolutePosition.Y, w = mirror.AbsoluteSize.X, h = mirror.AbsoluteSize.Y }
		end
		local x, y = Layout.placeTooltip({ x = ap.X, y = ap.Y, w = asz.X, h = asz.Y }, size, { w = screen.X, h = screen.Y }, avoid)
		tipText.Text = text
		tip.Size = UDim2.fromOffset(size.w, size.h)
		tip.Position = UDim2.fromOffset(x, y)
		tip.Visible = true
	end
	local function hoverTip(gui, textFn)
		gui.MouseEnter:Connect(function() showTip(gui, textFn()) end)
		gui.MouseLeave:Connect(hideTip)
	end

	-- ===== preview plate: live preview on top, detail card below =====
	local plate = bind(make("Frame", panel, { Name = "PreviewPlate", BackgroundColor3 = PLATE, ClipsDescendants = true }), function(r) return r.plate end)
	round(plate, 12)
	local plateStroke = stroke(plate, BRASS, 1.5)
	local stageArt = artOver(plate, "flair_stage", { ScaleType = Enum.ScaleType.Crop, ImageTransparency = 0.9 }) -- the one art layer, barely there

	mirror = bind(make("Frame", plate, { Name = "Mirror", BackgroundColor3 = Color3.fromRGB(26, 30, 40), ClipsDescendants = true }),
		function(r) return { x = r.mirror.x - r.plate.x, y = r.mirror.y - r.plate.y, w = r.mirror.w, h = r.mirror.h } end)
	round(mirror, 10)
	local mirrorStroke = stroke(mirror, GOLD, 2)
	-- on the painted door the glass is an arch: a circle on top and a rectangle below it (a UICorner cannot round only two corners)
	local GLASS = Color3.fromRGB(16, 18, 24)
	local glassTop = make("Frame", mirror, { Name = "GlassTop", BackgroundColor3 = GLASS, BackgroundTransparency = 0.05, BorderSizePixel = 0, Visible = false, ZIndex = Z + 1 })
	round(glassTop, 9999)
	local glassBody = make("Frame", mirror, { Name = "GlassBody", BackgroundColor3 = GLASS, BackgroundTransparency = 0.05, BorderSizePixel = 0, Visible = false, ZIndex = Z + 1 })
	local liveLabel

	liveLabel = make("TextLabel", mirror, { Position = UDim2.fromOffset(10, 4), Size = UDim2.new(0.4, -10, 0, 20), Text = "Live preview", TextColor3 = GOLD,
		TextXAlignment = Enum.TextXAlignment.Left, ZIndex = Z + 3 })
	local previewingLabel = make("TextLabel", mirror, { Position = UDim2.new(0.4, 0, 0, 4), Size = UDim2.new(0.6, -10, 0, 20), Text = "",
		TextXAlignment = Enum.TextXAlignment.Right, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = Z + 3 })
	local plaque = bind(make("Frame", panel, { Name = "ScenePlaque", BackgroundTransparency = 1, Visible = false, Active = false }), function(r) return r.plaque or r.close end)
	local stageScore = make("TextLabel", mirror, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.4), Size = UDim2.fromScale(1, 0.3),
		Text = "12,480", ZIndex = Z + 3 })
	local stageScoreStroke = stroke(stageScore, CREAM, 0)
	local stageName = make("TextLabel", mirror, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.74), Size = UDim2.new(0.5, 0, 0.14, 0),
		Text = "You", ZIndex = Z + 3, BackgroundColor3 = Color3.fromRGB(18, 14, 12), BackgroundTransparency = 0.25 })
	round(stageName, 8) -- "You" sits on a small plaque under the sample number
	local auraRing = make("Frame", mirror, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.74), Size = UDim2.fromOffset(90, 30),
		BackgroundTransparency = 1, Visible = false, ZIndex = Z + 2 })
	round(auraRing, 15)
	local auraRingStroke = stroke(auraRing, CREAM, 3)
	local stagePoint = make("Frame", mirror, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(2, 2), BackgroundTransparency = 1 })

	local scoreBase, nameBase = 40, 20
	local function sizeStageText()
		-- the sample "12,480" is about 3.7 em wide and pops to 1.3x, so it must fit the mirror glass (width W): em <= W / 4.8
		local glassW = math.max(1, mirror.AbsoluteSize.X - 12)
		scoreBase = math.clamp(math.floor(math.min(math.max(36, mirror.AbsoluteSize.Y * 0.2), glassW / 4.8)), 14, 56)
		nameBase = math.clamp(math.floor(math.min(mirror.AbsoluteSize.Y * 0.09, glassW / 5.5)), 14, 26)
		stageScore.TextSize = scoreBase
		stageName.TextSize = nameBase
	end

	local function rgbOf(option, fallback)
		local c = option and option.color or fallback
		return Color3.fromRGB(c[1], c[2], c[3])
	end
	local function currentOption(slotId) return previewed[slotId] or equippedBySlot[slotId] end

	local function paintStage()
		local num, aura = currentOption("scoreNumbers"), currentOption("nameAura")
		local numColor = rgbOf(num, { 250, 235, 200 })
		stageScore.TextColor3 = numColor
		stageScoreStroke.Color = numColor
		stageScoreStroke.Thickness = math.max(0, (num and num.glow or 0))
		stageName.TextColor3 = rgbOf(aura, { 250, 235, 200 })
		stageName.Text = ((aura and aura.crest and aura.crest ~= "") and (aura.crest .. " ") or "") .. "You"
	end

	local function pulseAura(option)
		if not FlairFX.canAnimate() then return end
		auraRingStroke.Color = rgbOf(option, { 250, 235, 200 })
		auraRingStroke.Transparency = 0.2
		auraRing.Size = UDim2.fromOffset(90, 30)
		auraRing.Visible = true
		tween(auraRing, 0.7, { Size = UDim2.fromOffset(190, 44) })
		tween(auraRingStroke, 0.7, { Transparency = 1 })
		tween(stageName, 0.12, { TextSize = nameBase + 6 }, Enum.EasingStyle.Back)
		task.delay(0.15, function() tween(stageName, 0.2, { TextSize = nameBase }) end)
	end
	local function popNumbers()
		if not FlairFX.canAnimate() then return end
		tween(stageScore, 0.15, { TextSize = math.floor(scoreBase * 1.3) }, Enum.EasingStyle.Back)
		task.delay(0.18, function() tween(stageScore, 0.25, { TextSize = scoreBase }) end)
	end
	local function burstPos()
		return UDim2.fromOffset(stagePoint.AbsolutePosition.X, stagePoint.AbsolutePosition.Y)
	end

	local stageToken = 0
	local function stopStage() stageToken = stageToken + 1 end
	local function startStage()
		stopStage()
		sizeStageText()
		paintStage()
		if ClientSettings.get("reduceShake") == true or not deps.particleBurst then return end
		local mine = stageToken
		task.spawn(function()
			while stageToken == mine and panel.Parent and panel.Parent.Visible do
				local trail, finisher = currentOption("playTrail"), currentOption("finisher")
				if trail then pcall(FlairFX.preview, deps.particleBurst, "playTrail", trail, burstPos()) end
				tween(stageScore, 0.15, { TextSize = math.floor(scoreBase * 1.15) }, Enum.EasingStyle.Back)
				task.wait(0.15)
				tween(stageScore, 0.2, { TextSize = scoreBase })
				task.wait(0.85)
				if stageToken ~= mine then break end
				if finisher then pcall(FlairFX.preview, deps.particleBurst, "finisher", finisher, burstPos()) end
				task.wait(1.8)
			end
		end)
	end

	local function previewSample(option)
		previewed[option.slotId] = option.option
		paintStage()
		previewingLabel.Text = "Previewing: " .. tostring(option.name)
		local slotId, row = option.slotId, option.option
		if slotId == "playTrail" or slotId == "finisher" then
			if deps.particleBurst and FlairFX.canAnimate() then pcall(FlairFX.preview, deps.particleBurst, slotId, row, burstPos()) end
		elseif slotId == "scoreNumbers" then
			popNumbers()
		elseif slotId == "nameAura" then
			pulseAura(row)
		end
	end

	-- ===== detail card (below the preview) =====
	local card = bind(make("Frame", plate, { Name = "DetailCard", BackgroundColor3 = TILE, ZIndex = Z + 4 }),
		function(r) return { x = r.detail.x - r.plate.x, y = r.detail.y - r.plate.y, w = r.detail.w, h = r.detail.h } end)
	round(card, 10)
	local cardStroke = stroke(card, BRASS, 2)
	cardStroke.Enabled = false
	local cardName = make("TextLabel", card, { TextSize = 20, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = Z + 5 })
	local cardHow = make("TextLabel", card, { Font = Enum.Font.GothamMedium, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = Z + 5 })
	local function cardButton(text, color, textColor)
		local b = make("TextButton", card, { Text = text, TextColor3 = textColor or CREAM, BackgroundColor3 = color, BackgroundTransparency = 0, ZIndex = Z + 5, Visible = false })
		deps.polishButton(b, 6)
		return b
	end
	local equipButton = cardButton("Equip", GREEN)
	local unequipButton = cardButton("Unequip", Color3.fromRGB(110, 70, 50))
	local previewButton = cardButton("Preview", Color3.fromRGB(80, 62, 44))
	local buyButton = cardButton("Buy", GOLD, INK)
	local statusLabel = make("TextLabel", card, { Name = "StatusLabel", Text = "", TextSize = 16, Font = Enum.Font.GothamBold, ZIndex = Z + 5, Visible = false,
		BackgroundColor3 = Color3.fromRGB(46, 38, 32), BackgroundTransparency = 0, TextColor3 = Color3.fromRGB(176, 164, 140) })
	round(statusLabel, 6)

	local chosenItem = nil
	local function findItem(id)
		for _, d in ipairs(drawers) do
			for _, item in ipairs(d.items) do
				if item.id == id then return item end
			end
		end
	end
	local function paintCard()
		chosenItem = chosenId and findItem(chosenId) or nil
		local d = Layout.detail(chosenItem)
		cardName.Text = d.title
		cardHow.Text = d.how
		local parts = Layout.detailParts({ w = R.detail.w, h = R.detail.h })
		setRect(cardName, parts.name)
		setRect(cardHow, parts.how)
		local slot = 1
		local function put(button, on)
			button.Visible = on
			if on then
				setRect(button, parts.buttons[slot])
				slot = slot + 1
			end
		end
		statusLabel.Text = d.status or ""
		statusLabel.TextColor3 = d.status == "Equipped" and Color3.fromRGB(150, 214, 140) or Color3.fromRGB(176, 164, 140)
		put(statusLabel, d.status ~= nil)
		put(equipButton, d.canEquip)
		put(unequipButton, d.canUnequip)
		put(buyButton, d.canBuy)
		put(previewButton, d.canPreview)
	end
	equipButton.MouseButton1Click:Connect(function()
		if chosenItem and chosenItem.state == "owned" then
			deps.playClickSfx()
			EquipRemote:FireServer(chosenItem.slotId, chosenItem.id)
		end
	end)
	unequipButton.MouseButton1Click:Connect(function()
		if chosenItem and chosenItem.state == "equipped" and not chosenItem.default then
			deps.playClickSfx()
			for _, d in ipairs(drawers) do
				if d.id == chosenItem.slotId then
					for _, it in ipairs(d.items) do
						if it.default then
							chosenId = it.id
							EquipRemote:FireServer(it.slotId, it.id) -- the default piece is the plain look
						end
					end
				end
			end
		end
	end)
	previewButton.MouseButton1Click:Connect(function()
		if chosenItem then
			deps.playClickSfx()
			previewSample(chosenItem)
		end
	end)
	buyButton.MouseButton1Click:Connect(function()
		if chosenItem and chosenItem.store and chosenItem.state == "locked" then
			deps.playClickSfx()
			PurchaseRemote:FireServer("flair_" .. chosenItem.id) -- the server checks the item, Studio grants placeholders free
		end
	end)

	-- ===== category tabs (left column, or a row on phones) =====
	local tabsHolder = bind(make("Frame", panel, { Name = "CategoryTabs", BackgroundTransparency = 1 }), function(r) return r.tabs end)
	local tabButtons = {}

	local function layoutTabs()
		local rects = R.sceneOn and R.tabPlates or Layout.tabRects({ x = 0, y = 0, w = R.tabs.w, h = R.tabs.h }, #tabButtons, R.narrow)
		for i, t in ipairs(tabButtons) do
			local rect = rects[i] or rects[#rects]
			setRect(t.button, rect)
			if R.sceneOn then
				-- text sits on the painted plate, inside its brass corners; the count line only when the plate is tall enough
				t.sub.Visible = rect.h >= 46
				t.name.Size = UDim2.new(1, -32, 0, 22)
				t.name.Position = UDim2.fromOffset(16, t.sub.Visible and 5 or math.floor((rect.h - 22) / 2))
				t.sub.Position = UDim2.fromOffset(16, 26)
				t.sub.Size = UDim2.new(1, -32, 0, 18)
				t.name.TextXAlignment = Enum.TextXAlignment.Left
				t.name.TextSize = 16
				t.name.TextScaled = true -- the whole category name, shrinking to 14 at the smallest, never dots
			else
				t.name.TextScaled = false
				t.sub.Visible = not R.narrow
				t.sub.Position = UDim2.fromOffset(10, 32)
				t.sub.Size = UDim2.new(1, -16, 0, 18)
				t.name.Size = R.narrow and UDim2.new(1, -8, 1, 0) or UDim2.new(1, -16, 0, 22)
				t.name.Position = R.narrow and UDim2.fromOffset(4, 0) or UDim2.fromOffset(10, 8)
				t.name.TextXAlignment = R.narrow and Enum.TextXAlignment.Center or Enum.TextXAlignment.Left
				t.name.TextSize = R.narrow and 14 or 16
			end
		end
	end

	-- ===== tile grid (centre) =====
	local gridFrame = bind(make("ScrollingFrame", panel, { Name = "FlairGrid", BackgroundColor3 = PLATE, BackgroundTransparency = 0, ScrollBarThickness = 8,
		ScrollBarImageColor3 = GOLD, ScrollBarImageTransparency = 0, CanvasSize = UDim2.new(), ScrollingDirection = Enum.ScrollingDirection.Y }), function(r) return r.grid end)
	round(gridFrame, 12)
	local gridStroke = stroke(gridFrame, BRASS, 1.5)

	local tiles = {} -- { frame, itemId, ring }

	local function layoutGrid()
		if R.sceneOn then
			-- one tile per painted cubby (4 x 3, row by row); the grid frame is the cubby block and does not scroll
			for k, t in ipairs(tiles) do
				local c = R.cubbies[k]
				t.frame.Visible = c ~= nil
				if c then setRect(t.frame, { x = c.x - R.grid.x, y = c.y - R.grid.y, w = c.w, h = c.h }) end
			end
			gridFrame.CanvasSize = UDim2.new()
		else
			local g = Layout.grid(R.grid.w - 8, #tiles, Layout.cell(R.compact))
			for k, t in ipairs(tiles) do t.frame.Visible = true; setRect(t.frame, g.cells[k]) end
			gridFrame.CanvasSize = UDim2.fromOffset(0, g.canvasH)
		end
		for _, t in ipairs(tiles) do
			local sel = t.itemId == chosenId
			t.ring.Enabled = sel
			t.frame.BackgroundColor3 = sel and Color3.fromRGB(74, 54, 36) or TILE
			if R.sceneOn then t.frame.BackgroundTransparency = sel and 0.55 or 1 end
		end
	end

	local function buildTile(item)
		local cellSize = (R.sceneOn and R.cubbies[1]) and Scene.cell(R.cubbies[1].w, R.cubbies[1].h) or Layout.cell(R.compact)
		local med = cellSize.med
		local locked = item.state == "locked"
		local f = make("TextButton", gridFrame, { Name = "Tile_" .. item.id, Text = "", AutoButtonColor = false, BackgroundColor3 = TILE, BackgroundTransparency = 0, ZIndex = Z + 1 })
		round(f, 10)
		if R.sceneOn then
			stroke(f, GOLD, item.state == "equipped" and 2 or 0)
		else
			stroke(f, item.state == "equipped" and GOLD or Color3.fromRGB(86, 66, 44), item.state == "equipped" and 2.5 or 1)
		end
		local sel = stroke(f, CREAM, 2)
		sel.Enabled = false
		local ic = make("Frame", f, { Name = "Icon", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 6), Size = UDim2.fromOffset(med, med),
			BackgroundColor3 = locked and Color3.fromRGB(34, 28, 28) or VELVET, ZIndex = Z + 2 })
		circle(ic)
		local glyph = make("TextLabel", ic, { Size = UDim2.fromScale(1, 1), TextSize = math.floor(med * 0.5), Text = item.icon, ZIndex = Z + 3,
			TextColor3 = locked and Color3.fromRGB(110, 100, 96) or CREAM })
		pcall(ArtIcon.apply, ic, "flair", item.id, glyph, { cornerRadius = med / 2, zIndex = Z + 3, dim = locked })
		if locked then
			local shade = make("Frame", ic, { Name = "Silhouette", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(10, 8, 8), BackgroundTransparency = 0.7, ZIndex = Z + 4 })
			circle(shade)
			make("TextLabel", ic, { Name = "Lock", AnchorPoint = Vector2.new(1, 1), Position = UDim2.fromScale(1, 1), Size = UDim2.fromOffset(20, 20), Text = "🔒", TextSize = 14, ZIndex = Z + 5 })
		end
		local nameW = math.max(10, (R.sceneOn and R.cubbies[1] and R.cubbies[1].w or 120) - 8)
		-- whole names: wrap onto two lines, never dots; the room counts any name that still does not fit (the [FlairRoom] line wants 0)
		local okSize, nameBounds = pcall(TextService.GetTextSize, TextService, item.name, 14, Enum.Font.GothamBold, Vector2.new(nameW, 1000))
		if R.sceneOn and okSize and nameBounds.Y > cellSize.nameH then truncatedLabels = truncatedLabels + 1 end
		make("TextLabel", f, { Name = "ItemName", Position = UDim2.fromOffset(4, 6 + med + 4), Size = UDim2.new(1, -8, 0, cellSize.nameH), Text = item.name,
			TextSize = 14, TextWrapped = true, TextTruncate = R.sceneOn and Enum.TextTruncate.None or Enum.TextTruncate.AtEnd, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = Z + 2,
			TextColor3 = locked and Color3.fromRGB(176, 164, 140) or CREAM })
		local status, statusColor
		if item.state == "equipped" then
			status, statusColor = "Equipped", Color3.fromRGB(150, 214, 140)
		elseif item.state == "owned" then
			status, statusColor = (firstSightOwned and not firstSightOwned[item.id]) and "New" or "Unlocked", GOLD
		else
			status, statusColor = item.tag or "Locked", Color3.fromRGB(190, 160, 110)
		end
		if cellSize.showTag == false then
			status = nil -- a short cubby gives its height to the name; the ring and the lock already say equipped or locked
		end
		if status then make("TextLabel", f, { Name = "Status", Position = UDim2.fromOffset(4, 6 + med + 4 + cellSize.nameH + 2), Size = UDim2.new(1, -8, 0, cellSize.tagH), Text = status,
			TextSize = 14, Font = Enum.Font.GothamMedium, TextColor3 = statusColor, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = Z + 2 }) end
		f.MouseButton1Click:Connect(function()
			deps.playClickSfx()
			chosenId = item.id
			layoutGrid()
			paintCard()
			previewSample(item) -- any tile, locked or not, plays right away (cosmetic only, never equips)
		end)
		hoverTip(f, function()
			if locked then return item.name .. ": " .. (item.store and "Sold in the Tavern Store." or item.hint) end
			return item.name .. (item.state == "equipped" and " (equipped)" or "")
		end)
		-- sparkle on a newly equipped tile
		if item.state == "equipped" and lastEquipped[item.slotId] ~= item.id then
			if lastEquipped[item.slotId] ~= nil and deps.particleBurst and ClientSettings.get("reduceShake") ~= true then
				task.defer(function()
					if f.Parent then
						pcall(deps.particleBurst, UDim2.fromOffset(f.AbsolutePosition.X + f.AbsoluteSize.X / 2, f.AbsolutePosition.Y + 6 + med / 2), GOLD, 10, { size = 7, spread = 60, duration = 0.6 })
					end
				end)
			end
			lastEquipped[item.slotId] = item.id
		end
		tiles[#tiles + 1] = { frame = f, itemId = item.id, ring = sel }
	end

	local function buildTabs()
		for _, t in ipairs(tabButtons) do t.button:Destroy() end
		tabButtons = {}
		for _, d in ipairs(drawers) do
			local on = d.id == openSlot
			local b = make("TextButton", tabsHolder, { Name = "Tab_" .. d.id, Text = "", AutoButtonColor = false, BackgroundColor3 = on and Color3.fromRGB(86, 62, 38) or TILE, BackgroundTransparency = 0 })
			round(b, 8)
			if sceneOn then
				-- the painted plate is the button: a faint gold wash and a gold edge only on the open tab
				b.BackgroundTransparency = on and 0.7 or 1
				stroke(b, GOLD, on and 2.5 or 0)
			else
				stroke(b, on and GOLD or Color3.fromRGB(86, 66, 44), on and 2.5 or 1)
			end
			local name = make("TextLabel", b, { Text = d.name, TextSize = 16, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = Z + 1,
				TextColor3 = on and CREAM or Color3.fromRGB(210, 194, 164) })
			local nameLimit = Instance.new("UITextSizeConstraint")
			nameLimit.MinTextSize, nameLimit.MaxTextSize = 14, 16
			nameLimit.Parent = name
			local sub = make("TextLabel", b, { Position = UDim2.fromOffset(10, 32), Size = UDim2.new(1, -16, 0, 18), Font = Enum.Font.GothamMedium, TextSize = 14,
				Text = d.ownedCount .. " of " .. d.total .. " unlocked", TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
				TextColor3 = GOLD, ZIndex = Z + 1 })
			b.MouseButton1Click:Connect(function()
				deps.playClickSfx()
				openSlot = d.id
				chosenId = nil
				for _, it in ipairs(d.items) do if it.state == "equipped" then chosenId = it.id end end
				FlairDressingRoom._rebuild()
			end)
			tabButtons[#tabButtons + 1] = { button = b, name = name, sub = sub }
		end
		layoutTabs()
	end

	local function buildGrid()
		truncatedLabels = 0
		if openSlot then scrollMemory[openSlot] = gridFrame.CanvasPosition.Y end
		for _, t in ipairs(tiles) do t.frame:Destroy() end
		tiles = {}
		for _, d in ipairs(drawers) do
			if d.id == openSlot then
				for _, item in ipairs(d.items) do buildTile(item) end
			end
		end
	end

	-- one full redraw of the parts that depend on the open category and the chosen piece
	function FlairDressingRoom._rebuild()
		paintPatches()
		buildTabs()
		buildGrid()
		layoutGrid()
		paintCard()
		if openSlot and scrollMemory[openSlot] then gridFrame.CanvasPosition = Vector2.new(0, scrollMemory[openSlot]) end
	end

	-- ===== relayout when the panel size changes =====
	local lastKey = ""
	local function relayout(force)
		local w, h = math.floor(panel.AbsoluteSize.X), math.floor(panel.AbsoluteSize.Y)
		if w < 200 or h < 200 then return end
		local key = w .. "x" .. h
		if key == lastKey and not force then return end
		lastKey = key
		R = Layout.rects(w, h)
		local S = nil
		if sceneId and not R.narrow then
			local areaY = R.topH
			local areaH = h - R.topH - R.bottomH
			S = Scene.place(w, areaH)
			if S.ok then S.areaY = areaY else S = nil end
		end
		sceneOn = S ~= nil
		R.sceneOn = sceneOn
		if S then
			local function down(r) return { x = r.x, y = r.y + S.areaY, w = r.w, h = r.h } end
			R.tabs = { x = 0, y = 0, w = w, h = h }
			R.tabPlates = {}
			for i, t in ipairs(S.tabs) do R.tabPlates[i] = down(t) end
			R.cubbies = {}
			for i, c in ipairs(S.cubbies) do R.cubbies[i] = down(c) end
			R.grid = down(S.bounds)
			R.plate = { x = 0, y = 0, w = w, h = h }
			R.mirror, R.detail, R.plaque = down(S.mirror), down(S.detail), down(S.plaque)
			sceneHolder.Position, sceneHolder.Size = UDim2.fromOffset(0, S.areaY), UDim2.fromOffset(w, h - R.topH) -- the painting runs under the footer to the panel bottom
			sceneImage.Position, sceneImage.Size = UDim2.fromOffset(S.image.x, S.image.y), UDim2.fromOffset(S.image.w, S.image.h)
			local aw, ah = w, h - R.topH
			local gap = S.image.x > 0.5 or S.image.y > 0.5 or S.image.x + S.image.w < aw - 0.5 or S.image.y + S.image.h < ah - 0.5
			sceneBack.Visible, sceneWash.Visible = gap, gap
			sceneBase = gap and SCENE_WASH or 0
			if gap then
				local cs = math.max(aw / S.image.w, ah / S.image.h) -- cover scale relative to the placed (smaller) picture
				local bw, bh = S.image.w * cs, S.image.h * cs
				sceneBack.Size = UDim2.fromOffset(math.ceil(bw), math.ceil(bh))
				sceneBack.Position = UDim2.fromOffset(math.floor((aw - bw) / 2), math.floor((ah - bh) / 2))
			end
			paintVignette(Scene.edges(S, aw, ah))
			sceneS = S
			paintPatches()
		end
		if not S then sceneS = nil; paintPatches() end
		sceneHolder.Visible = sceneOn
		roomLights.place(sceneOn and sceneS and { x = sceneS.image.x, y = sceneS.image.y, w = sceneS.image.w, h = sceneS.image.h } or nil)
		plaque.Visible = sceneOn
		-- panels drawn by hand give way to the painting
		plate.BackgroundTransparency = sceneOn and 1 or 0
		plateStroke.Enabled = not sceneOn
		if stageArt then stageArt.Visible = not sceneOn end
		gridFrame.BackgroundTransparency = sceneOn and 1 or 0
		gridFrame.ScrollBarThickness = sceneOn and 0 or 8
		gridFrame.ScrollingEnabled = not sceneOn
		mirror.BackgroundTransparency = sceneOn and 1 or 0
		mirror.ClipsDescendants = not sceneOn
		glassTop.Visible, glassBody.Visible = sceneOn, sceneOn
		if sceneOn and R.mirror then
			local A = Scene.arch(R.mirror)
			glassTop.Position, glassTop.Size = UDim2.fromOffset(A.top.x, A.top.y), UDim2.fromOffset(A.top.w, A.top.h)
			glassBody.Position, glassBody.Size = UDim2.fromOffset(A.body.x, A.body.y), UDim2.fromOffset(A.body.w, A.body.h)
		end
		mirrorStroke.Enabled = not sceneOn
		gridStroke.Enabled = not sceneOn
		-- the detail card is a parchment plate with a brass edge on the painted room (not a black box); ink text at 9:1
		card.BackgroundColor3 = sceneOn and PARCHMENT or TILE
		card.BackgroundTransparency = sceneOn and 0.06 or 0
		cardStroke.Enabled = sceneOn
		cardName.TextColor3 = sceneOn and INK or CREAM
		cardHow.TextColor3 = sceneOn and INK or CREAM
		if sceneOn then
			-- both labels live on the brass plaque under the mirror, so nothing floats over the sample number
			liveLabel.Parent = plaque
			liveLabel.Position, liveLabel.Size, liveLabel.TextXAlignment = UDim2.new(0, 14, 0, 0), UDim2.new(1, -28, 0.45, 0), Enum.TextXAlignment.Center
			liveLabel.TextYAlignment, previewingLabel.TextYAlignment = Enum.TextYAlignment.Center, Enum.TextYAlignment.Center
			local function centreLabels()
				-- one label alone fills the plaque so its text sits in the middle; two stack
				local two = previewingLabel.Text ~= ""
				liveLabel.Size = two and UDim2.new(1, -28, 0.5, 0) or UDim2.new(1, -28, 1, 0)
				previewingLabel.Position = UDim2.new(0, 14, 0.5, 0)
				previewingLabel.Size = UDim2.new(1, -28, 0.5, 0)
			end
			if not previewingLabel:GetAttribute("CentreHooked") then
				previewingLabel:SetAttribute("CentreHooked", true)
				previewingLabel:GetPropertyChangedSignal("Text"):Connect(function() if previewingLabel.Parent == plaque then centreLabels() end end)
			end
			previewingLabel.Parent = plaque
			previewingLabel.TextXAlignment = Enum.TextXAlignment.Center
			centreLabels()
		else
			liveLabel.Parent = mirror
			liveLabel.Position, liveLabel.Size, liveLabel.TextXAlignment = UDim2.fromOffset(10, 4), UDim2.new(0.4, -10, 0, 20), Enum.TextXAlignment.Left
			previewingLabel.Parent = mirror
			previewingLabel.Position, previewingLabel.Size, previewingLabel.TextXAlignment = UDim2.new(0.4, 0, 0, 4), UDim2.new(0.6, -10, 0, 20), Enum.TextXAlignment.Right
		end
		for _, entry in ipairs(placed) do setRect(entry.inst, entry.fn(R)) end
		titleLabel.TextSize = R.compact and 24 or 28
		sizeStageText()
		truncatedLabels = 0
		if #drawers > 0 then FlairDressingRoom._rebuild() end
		if game:GetService("RunService"):IsStudio() then
			local cover = math.max(w / Scene.IMAGE_W, (h - R.topH - R.bottomH) / Scene.IMAGE_H)
			print(string.format("[FlairRoom] %s scale=%.2f cover=%.2f labels=%d truncated=%d", sceneOn and "painted" or "plain", sceneS and sceneS.scale or 0, cover, #tiles, truncatedLabels))
		end
	end
	panel:GetPropertyChangedSignal("AbsoluteSize"):Connect(function() relayout(false) end)

	-- ===== public =====
	local room = { closeButton = closeButton, bundleButton = bundleButton, stopStage = stopStage, startStage = startStage, hideTip = hideTip }

	function room.reset()
		for slotId in pairs(previewed) do previewed[slotId] = nil end
		previewingLabel.Text = ""
		hideTip()
		openSlot = nil
		chosenId = nil
	end

	function room.refresh(state)
		view = state and state.flair
		if not view then return end
		hideTip()
		bundleButton.Visible = false
		if not firstSightOwned then
			firstSightOwned = {}
			for _, slot in ipairs(view.slots) do
				for _, option in ipairs(slot.options) do
					if option.owned then firstSightOwned[option.id] = true end
				end
			end
		end
		drawers = Layout.drawers(view)
		local eq = Layout.equippedSlots(view)
		for _, e in ipairs(eq) do equippedBySlot[e.slotId] = e.option end
		for _, item in ipairs(state.flairStore and state.flairStore.items or {}) do
			if item.id == "flair_bundle" and not item.owned then
				bundleButton.Visible = true
				bundleButton.Text = "Flair Bundle: " .. StorePanel.priceText(item)
			end
		end
		if not openSlot and drawers[1] then openSlot = drawers[1].id end
		if not findItem(chosenId or "") then
			chosenId = nil
			for _, d in ipairs(drawers) do
				if d.id == openSlot then
					for _, it in ipairs(d.items) do if it.state == "equipped" then chosenId = it.id end end
				end
			end
		end
		paintStage()
		relayout(true)
		FlairDressingRoom._rebuild()
	end

	relayout(true)
	return room
end

return FlairDressingRoom
