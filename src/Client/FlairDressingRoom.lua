--[[
	Client/FlairDressingRoom.lua
	The inside of the Flair panel: a tavern dressing room. Left, a curtained mirror stage that loops a live preview of the
	name plate (Name Aura), score numbers and pop effect; a detail card at the foot of the stage (name, how to get it,
	Equip, Preview, Buy); and one small slot per Flair category under the stage showing what is equipped. Right, a tall
	cabinet with one drawer per Flair category (taken from Flair.view, nothing hardcoded); a drawer slides open like a tray
	(0.2 s) with round medallions on velvet and the name below. Locked pieces are dark silhouettes with a lock, a brass
	tag with the unlock goal and a thin progress rail; the equipped piece has a gold ring and an "On" ribbon.
	One reusable tooltip lives on the ScreenGui, clamped on screen and kept off the live preview.
	Every piece is drawn from Frames first; Engine/FlairUiArt.lua ids are laid over the fallbacks when recorded.
	"Reduce screen shake" skips every tween and loop. Data mapping and layout maths: Engine/FlairRoomLayout.lua (tested).
	Display only: the server validates equip and purchase (remotes EquipFlair, StorePurchase).

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
	local ContentArt = require(Engine:WaitForChild("ContentArt"))
	local ArtIcon = require(script.Parent.ArtIcon)
	local FlairFX = require(script.Parent.FlairFX)
	local ClientSettings = require(script.Parent.ClientSettings)
	local SetSkin = require(script.Parent.SetSkin)
	local StorePanel = require(script.Parent.StorePanel)
	local Remotes = ReplicatedStorage:WaitForChild("Remotes")
	local EquipRemote = Remotes:WaitForChild("EquipFlair")
	local PurchaseRemote = Remotes:WaitForChild("StorePurchase")

	local INK = Color3.fromRGB(60, 40, 22)
	local CREAM = Color3.fromRGB(250, 235, 200)
	local GOLD = Color3.fromRGB(222, 182, 104)
	local BRASS = Color3.fromRGB(176, 138, 70)
	local VELVET = Color3.fromRGB(96, 26, 46)
	local VELVET_DARK = Color3.fromRGB(58, 16, 30)
	local GREEN = Color3.fromRGB(86, 140, 80)
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
		end
		if o:IsA("GuiObject") then o.ZIndex = Z end
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
	local function gradient(inst, a, b, rotation) -- Color stops only
		local g = Instance.new("UIGradient")
		g.Color = ColorSequence.new(a, b)
		g.Rotation = rotation or 90
		g.Parent = inst
	end

	-- A recorded flair_ui Image id is laid over its code-drawn fallback (parented to the piece so Clone() keeps it).
	local function artOver(parent, key, props)
		local id = ContentArt.getImageId("flair_ui", key)
		if not id then return nil end
		local img = make("ImageLabel", parent, { Name = "Art_" .. key, BackgroundTransparency = 1, Image = id, Size = UDim2.fromScale(1, 1),
			ScaleType = Enum.ScaleType.Fit, ZIndex = Z + 1, Active = false })
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
	local drawers = {}
	local openSlot = nil -- slot id of the open drawer
	local chosenId = nil -- piece shown in the detail card
	local previewed = {} -- slotId -> option row (Preview taps)
	local equippedBySlot = {}
	local firstSightOwned = nil
	local lastEquipped = {}
	local scrollMemory = {}
	local R = Layout.rects(1000, 600)

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

	-- ===== stage: curtains, mirror, live preview =====
	local stage = bind(make("Frame", panel, { Name = "Stage", BackgroundColor3 = Color3.fromRGB(26, 19, 14), ClipsDescendants = true }), function(r) return r.stage end)
	round(stage, 12)
	stroke(stage, GOLD, 2)
	artOver(stage, "flair_stage", { ScaleType = Enum.ScaleType.Crop })

	local function curtain(name, fn)
		local c = bind(make("Frame", stage, { Name = name, BackgroundColor3 = VELVET }), function(r) local q = fn(r) return { x = q.x - r.stage.x, y = q.y - r.stage.y, w = q.w, h = q.h } end)
		gradient(c, Color3.fromRGB(128, 34, 58), Color3.fromRGB(70, 18, 34), 0)
		for i = 1, 3 do -- velvet folds
			make("Frame", c, { BackgroundColor3 = VELVET_DARK, Position = UDim2.fromScale(i / 4 - 0.04, 0), Size = UDim2.fromScale(0.08, 1) })
		end
		return c
	end
	curtain("CurtainL", function(r) return r.curtainL end)
	curtain("CurtainR", function(r) return r.curtainR end)

	mirror = bind(make("Frame", stage, { Name = "Mirror", BackgroundColor3 = Color3.fromRGB(34, 40, 52), ClipsDescendants = true }),
		function(r) return { x = r.mirror.x - r.stage.x, y = r.mirror.y - r.stage.y, w = r.mirror.w, h = r.mirror.h } end)
	gradient(mirror, Color3.fromRGB(52, 60, 78), Color3.fromRGB(16, 18, 26), 90)
	round(mirror, 10)
	stroke(mirror, GOLD, 4)
	artOver(mirror, "flair_sparkle_burst", { ImageTransparency = 0.5, Size = UDim2.fromScale(0.6, 0.9), Position = UDim2.fromScale(0.2, 0.05) })

	make("TextLabel", mirror, { Position = UDim2.fromOffset(10, 4), Size = UDim2.new(0.4, -10, 0, 20), Text = "Live preview", TextColor3 = GOLD,
		TextXAlignment = Enum.TextXAlignment.Left, ZIndex = Z + 3 })
	local previewingLabel = make("TextLabel", mirror, { Position = UDim2.new(0.4, 0, 0, 4), Size = UDim2.new(0.6, -10, 0, 20), Text = "",
		TextXAlignment = Enum.TextXAlignment.Right, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = Z + 3 })
	local stageScore = make("TextLabel", mirror, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.38), Size = UDim2.fromScale(1, 0.3),
		Text = "12,480", ZIndex = Z + 3 })
	local stageScoreStroke = stroke(stageScore, CREAM, 0)
	local stageName = make("TextLabel", mirror, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.7), Size = UDim2.fromScale(1, 0.16),
		Text = "You", ZIndex = Z + 3 })
	local auraRing = make("Frame", mirror, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.7), Size = UDim2.fromOffset(90, 30),
		BackgroundTransparency = 1, Visible = false, ZIndex = Z + 2 })
	round(auraRing, 15)
	local auraRingStroke = stroke(auraRing, CREAM, 3)
	local stagePoint = make("Frame", mirror, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(2, 2), BackgroundTransparency = 1 })

	local scoreBase, nameBase = 40, 20
	local function sizeStageText()
		scoreBase = math.clamp(math.floor(mirror.AbsoluteSize.Y * 0.2), 28, 56)
		nameBase = math.clamp(math.floor(mirror.AbsoluteSize.Y * 0.09), 18, 26)
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

	-- ===== detail card (bottom of the stage) =====
	local card = bind(make("Frame", stage, { Name = "DetailCard", BackgroundColor3 = Color3.fromRGB(44, 31, 22), ZIndex = Z + 4 }),
		function(r) return { x = r.detail.x - r.stage.x, y = r.detail.y - r.stage.y, w = r.detail.w, h = r.detail.h } end)
	round(card, 10)
	stroke(card, BRASS, 2)
	SetSkin.register(card, "panel")
	local cardName = make("TextLabel", card, { TextSize = 20, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = Z + 5 })
	local cardHow = make("TextLabel", card, { Font = Enum.Font.GothamMedium, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = Z + 5 })
	local function cardButton(text, color, textColor)
		local b = make("TextButton", card, { Text = text, TextColor3 = textColor or CREAM, BackgroundColor3 = color, BackgroundTransparency = 0, ZIndex = Z + 5, Visible = false })
		deps.polishButton(b, 6)
		return b
	end
	local equipButton = cardButton("Equip", GREEN)
	local previewButton = cardButton("Preview", Color3.fromRGB(80, 62, 44))
	local buyButton = cardButton("Buy", GOLD, INK)

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
		local parts = Layout.detailParts(R.detail)
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
		put(equipButton, d.canEquip)
		put(buyButton, d.canBuy)
		put(previewButton, d.canPreview)
	end
	equipButton.MouseButton1Click:Connect(function()
		if chosenItem and chosenItem.state == "owned" then
			deps.playClickSfx()
			EquipRemote:FireServer(chosenItem.slotId, chosenItem.id)
		end
	end)
	previewButton.MouseButton1Click:Connect(function()
		if chosenItem and chosenItem.state ~= "locked" then
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

	-- ===== equipped slots under the stage =====
	local slotsHolder = bind(make("Frame", panel, { Name = "EquippedSlots", BackgroundTransparency = 1 }), function(r) return r.slots end)
	local slotFrames = {}
	local function buildSlots(eq)
		for _, f in ipairs(slotFrames) do f:Destroy() end
		slotFrames = {}
		local rects = Layout.splitRow({ x = 0, y = 0, w = R.slots.w, h = R.slots.h }, #eq, R.gap)
		for i, entry in ipairs(eq) do
			local r = rects[i]
			local f = make("TextButton", slotsHolder, { Name = "Slot_" .. entry.slotId, Text = "", BackgroundColor3 = VELVET_DARK, BackgroundTransparency = 0, AutoButtonColor = false })
			setRect(f, r)
			round(f, 10)
			stroke(f, BRASS, 1.5)
			local med = math.min(40, r.h - 12)
			local well = make("Frame", f, { Position = UDim2.fromOffset(6, math.floor((r.h - med) / 2)), Size = UDim2.fromOffset(med, med), BackgroundColor3 = VELVET })
			circle(well)
			stroke(well, GOLD, 2)
			local glyph = make("TextLabel", well, { Size = UDim2.fromScale(1, 1), TextSize = 20, Text = entry.optionIcon or "" })
			if entry.optionId then pcall(ArtIcon.apply, well, "flair", entry.optionId, glyph, { cornerRadius = med / 2, zIndex = Z + 2 }) end
			local tx = 6 + med + 6
			make("TextLabel", f, { Position = UDim2.fromOffset(tx, math.floor(r.h / 2) - 20), Size = UDim2.new(1, -tx - 4, 0, 20), Text = entry.slotName, TextColor3 = GOLD,
				TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd })
			make("TextLabel", f, { Position = UDim2.fromOffset(tx, math.floor(r.h / 2)), Size = UDim2.new(1, -tx - 4, 0, 20), Text = entry.optionName,
				Font = Enum.Font.GothamMedium, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd })
			hoverTip(f, function() return entry.slotName .. ": " .. entry.optionName end)
			f.MouseButton1Click:Connect(function()
				deps.playClickSfx()
				openSlot = entry.slotId
				chosenId = entry.optionId
				FlairDressingRoom._layoutCabinet(true)
			end)
			slotFrames[#slotFrames + 1] = f
		end
	end

	-- ===== cabinet of drawers =====
	local cabinet = bind(make("Frame", panel, { Name = "Cabinet", BackgroundColor3 = Color3.fromRGB(82, 56, 34) }), function(r) return r.cabinet end)
	round(cabinet, 12)
	gradient(cabinet, Color3.fromRGB(104, 72, 44), Color3.fromRGB(62, 42, 26), 90)
	stroke(cabinet, BRASS, 2)
	SetSkin.register(cabinet, "panel")
	artOver(cabinet, "flair_cabinet", { ScaleType = Enum.ScaleType.Crop })

	local cabinetParts = {} -- rebuilt each refresh: { front, tray, slotId, cells = { {frame, item} } }

	local function clearCabinet()
		for _, p in ipairs(cabinetParts) do
			p.front:Destroy()
			p.tray:Destroy()
		end
		cabinetParts = {}
	end

	function FlairDressingRoom._layoutCabinet(animate)
		local n = #cabinetParts
		if n == 0 then return end
		local openIndex = nil
		for i, p in ipairs(cabinetParts) do
			if p.slotId == openSlot then openIndex = i end
		end
		local rects = Layout.drawerRects({ x = 0, y = 0, w = R.cabinet.w, h = R.cabinet.h }, n, openIndex)
		local anim = animate and ClientSettings.get("reduceShake") ~= true
		for i, p in ipairs(cabinetParts) do
			local isOpen = i == openIndex
			local fp, fs = rectUdim(rects.fronts[i])
			local tp, ts = rectUdim(rects.trays[i])
			if isOpen then p.tray.Visible = true end
			if anim then
				tween(p.front, 0.2, { Position = fp, Size = fs })
				tween(p.tray, 0.2, { Position = tp, Size = ts })
				if not isOpen then
					task.delay(0.22, function() if p.tray.Parent and p.slotId ~= openSlot then p.tray.Visible = false end end)
				end
			else
				p.front.Position, p.front.Size = fp, fs
				p.tray.Position, p.tray.Size = tp, ts
				p.tray.Visible = isOpen
			end
			p.handle.BackgroundColor3 = isOpen and GOLD or BRASS
			p.frontStroke.Color = isOpen and GOLD or BRASS
			p.frontStroke.Thickness = isOpen and 3 or 1.5
			p.front.BackgroundColor3 = isOpen and Color3.fromRGB(122, 86, 52) or Color3.fromRGB(96, 66, 40)
			if isOpen then
				local g = Layout.grid(rects.trays[i].w, #p.cells, Layout.cell(R.compact))
				for k, c in ipairs(p.cells) do setRect(c, g.cells[k]) end
				p.tray.CanvasSize = UDim2.fromOffset(0, g.canvasH)
				for _, c in ipairs(p.cells) do
					c:SetAttribute("Selected", c.Name == "Cell_" .. tostring(chosenId))
					local ring = c:FindFirstChild("Medallion") and c.Medallion:FindFirstChild("SelectRing")
					if ring then ring.Visible = c:GetAttribute("Selected") == true end
				end
			end
		end
		paintCard()
	end

	local function buildMedallion(part, item, index)
		local cellSize = Layout.cell(R.compact)
		local med = cellSize.med
		local locked = item.state == "locked"
		local c = make("Frame", part.tray, { Name = "Cell_" .. item.id, BackgroundTransparency = 1 })
		local mb = make("TextButton", c, { Name = "Medallion", Text = "", AutoButtonColor = false, BackgroundColor3 = locked and Color3.fromRGB(28, 20, 22) or VELVET,
			BackgroundTransparency = 0, Position = UDim2.fromOffset(math.floor((cellSize.w - med) / 2), 0), Size = UDim2.fromOffset(med, med) })
		circle(mb)
		gradient(mb, locked and Color3.fromRGB(44, 32, 34) or Color3.fromRGB(150, 50, 78), locked and Color3.fromRGB(16, 12, 14) or Color3.fromRGB(70, 18, 36), 90)
		stroke(mb, item.state == "equipped" and GOLD or (locked and Color3.fromRGB(70, 60, 56) or BRASS), item.state == "equipped" and 4 or 2)
		artOver(mb, locked and "flair_medallion_ring_locked" or "flair_medallion_ring")
		local glyph = make("TextLabel", mb, { Size = UDim2.fromScale(1, 1), TextSize = math.floor(med * 0.48), Text = item.icon, ZIndex = Z + 2,
			TextColor3 = locked and Color3.fromRGB(10, 8, 8) or CREAM })
		pcall(ArtIcon.apply, mb, "flair", item.id, glyph, { cornerRadius = med / 2, zIndex = Z + 2, dim = locked })
		if locked then
			local shade = make("Frame", mb, { Name = "Silhouette", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(8, 6, 8), BackgroundTransparency = 0.35, ZIndex = Z + 3 })
			circle(shade)
			local badge = make("Frame", mb, { Name = "Lock", Size = UDim2.fromOffset(24, 24), Position = UDim2.new(1, -24, 1, -24), BackgroundColor3 = Color3.fromRGB(30, 24, 24), BackgroundTransparency = 0, ZIndex = Z + 4 })
			circle(badge)
			stroke(badge, BRASS, 1.5)
			make("TextLabel", badge, { Size = UDim2.fromScale(1, 1), Text = "🔒", TextSize = 14, ZIndex = Z + 5 })
		end
		local sel = make("Frame", mb, { Name = "SelectRing", Position = UDim2.fromOffset(-4, -4), Size = UDim2.new(1, 8, 1, 8), BackgroundTransparency = 1, Visible = false, ZIndex = Z + 3 })
		circle(sel)
		stroke(sel, CREAM, 2)
		if item.state == "equipped" then
			local ribbon = make("Frame", mb, { Name = "OnRibbon", Position = UDim2.new(0, -4, 0, 2), Size = UDim2.fromOffset(34, 18), BackgroundColor3 = GREEN, BackgroundTransparency = 0, ZIndex = Z + 6 })
			round(ribbon, 4)
			stroke(ribbon, GOLD, 1.5)
			artOver(ribbon, "flair_on_ribbon", { ZIndex = Z + 6 })
			make("TextLabel", ribbon, { Size = UDim2.fromScale(1, 1), Text = "On", ZIndex = Z + 7 })
		elseif item.state == "owned" and firstSightOwned and not firstSightOwned[item.id] then
			local new = make("TextLabel", mb, { Name = "NewRibbon", Position = UDim2.new(1, -36, 0, 2), Size = UDim2.fromOffset(40, 18), Text = "NEW", TextColor3 = INK,
				BackgroundTransparency = 0, BackgroundColor3 = GOLD, ZIndex = Z + 6 })
			round(new, 4)
		end
		make("TextLabel", c, { Name = "ItemName", Position = UDim2.fromOffset(0, med + 4), Size = UDim2.fromOffset(cellSize.w, cellSize.nameH), Text = item.name,
			TextWrapped = true, TextTruncate = Enum.TextTruncate.AtEnd, TextYAlignment = Enum.TextYAlignment.Top, TextColor3 = locked and Color3.fromRGB(190, 176, 150) or CREAM })
		if locked then
			local tag = make("Frame", c, { Name = "BrassTag", Position = UDim2.fromOffset(2, med + 4 + cellSize.nameH + 4), Size = UDim2.fromOffset(cellSize.w - 4, cellSize.tagH),
				BackgroundColor3 = BRASS, BackgroundTransparency = 0 })
			round(tag, 5)
			artOver(tag, "flair_brass_tag")
			make("TextLabel", tag, { Size = UDim2.fromScale(1, 1), Text = item.tag or "Locked", TextColor3 = INK, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = Z + 2 })
			if item.ratio then
				local track = make("Frame", c, { Name = "Rail", Position = UDim2.fromOffset(6, med + 4 + cellSize.nameH + 4 + cellSize.tagH + 4), Size = UDim2.fromOffset(cellSize.w - 12, cellSize.railH),
					BackgroundColor3 = Color3.fromRGB(60, 46, 40) })
				round(track, 3)
				local fill = make("Frame", track, { Size = UDim2.fromScale(item.ratio, 1), BackgroundColor3 = GOLD, ZIndex = Z + 1 })
				round(fill, 3)
			end
		end
		mb.MouseButton1Click:Connect(function()
			deps.playClickSfx()
			chosenId = item.id
			FlairDressingRoom._layoutCabinet(false)
		end)
		hoverTip(mb, function()
			if locked then return item.name .. ": " .. (item.store and "Sold in the Tavern Store." or item.hint) end
			return item.name .. (item.state == "equipped" and " (equipped)" or "")
		end)
		-- sparkle on a newly equipped medallion
		if item.state == "equipped" and lastEquipped[item.slotId] ~= item.id then
			if lastEquipped[item.slotId] ~= nil and deps.particleBurst and ClientSettings.get("reduceShake") ~= true then
				task.defer(function()
					if mb.Parent then
						pcall(deps.particleBurst, UDim2.fromOffset(mb.AbsolutePosition.X + med / 2, mb.AbsolutePosition.Y + med / 2), GOLD, 10, { size = 7, spread = 60, duration = 0.6 })
					end
				end)
			end
			lastEquipped[item.slotId] = item.id
		end
		part.cells[#part.cells + 1] = c
	end

	local function buildCabinet()
		for _, p in ipairs(cabinetParts) do
			if p.tray and p.tray.Parent then scrollMemory[p.slotId] = p.tray.CanvasPosition.Y end
		end
		clearCabinet()
		for _, d in ipairs(drawers) do
			local part = { slotId = d.id, cells = {} }
			part.front = make("TextButton", cabinet, { Name = "Drawer_" .. d.id, Text = "", AutoButtonColor = false, BackgroundColor3 = Color3.fromRGB(96, 66, 40), BackgroundTransparency = 0 })
			round(part.front, 8)
			part.frontStroke = stroke(part.front, BRASS, 1.5)
			gradient(part.front, Color3.fromRGB(255, 235, 210), Color3.fromRGB(190, 170, 150), 90)
			artOver(part.front, "flair_drawer_front")
			make("TextLabel", part.front, { Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -88, 1, 0), Text = d.icon .. " " .. d.name .. "   " .. d.ownedCount .. " of " .. d.total,
				TextSize = 16, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = Z + 2 })
			part.handle = make("Frame", part.front, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -14, 0.5, 0), Size = UDim2.fromOffset(52, 10), BackgroundColor3 = BRASS, ZIndex = Z + 2 })
			round(part.handle, 5)
			part.tray = make("ScrollingFrame", cabinet, { Name = "Tray_" .. d.id, BackgroundColor3 = VELVET_DARK, BackgroundTransparency = 0, ScrollBarThickness = 8,
				ScrollBarImageColor3 = GOLD, ScrollBarImageTransparency = 0, CanvasSize = UDim2.new(), Visible = false, ZIndex = Z })
			part.tray.ScrollingDirection = Enum.ScrollingDirection.Y
			round(part.tray, 8)
			artOver(part.tray, "flair_velvet_tray")
			for i, item in ipairs(d.items) do buildMedallion(part, item, i) end
			cabinetParts[#cabinetParts + 1] = part
			part.front.MouseButton1Click:Connect(function()
				deps.playClickSfx()
				openSlot = d.id
				local item = findItem(chosenId or "")
				if not item or item.slotId ~= d.id then
					for _, it in ipairs(d.items) do if it.state == "equipped" then chosenId = it.id end end
				end
				FlairDressingRoom._layoutCabinet(true)
			end)
		end
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
		for _, entry in ipairs(placed) do setRect(entry.inst, entry.fn(R)) end
		titleLabel.TextSize = R.compact and 24 or 28
		sizeStageText()
		FlairDressingRoom._layoutCabinet(false)
		if #drawers > 0 then buildSlots(Layout.equippedSlots(view)) end
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
		buildCabinet()
		buildSlots(eq)
		relayout(true)
		for _, p in ipairs(cabinetParts) do
			if scrollMemory[p.slotId] then p.tray.CanvasPosition = Vector2.new(0, scrollMemory[p.slotId]) end
		end
	end

	relayout(true)
	return room
end

return FlairDressingRoom
