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
	stroke(plate, BRASS, 1.5)
	artOver(plate, "flair_stage", { ScaleType = Enum.ScaleType.Crop, ImageTransparency = 0.9 }) -- the one art layer, barely there

	mirror = bind(make("Frame", plate, { Name = "Mirror", BackgroundColor3 = Color3.fromRGB(26, 30, 40), ClipsDescendants = true }),
		function(r) return { x = r.mirror.x - r.plate.x, y = r.mirror.y - r.plate.y, w = r.mirror.w, h = r.mirror.h } end)
	round(mirror, 10)
	stroke(mirror, GOLD, 2)

	make("TextLabel", mirror, { Position = UDim2.fromOffset(10, 4), Size = UDim2.new(0.4, -10, 0, 20), Text = "Live preview", TextColor3 = GOLD,
		TextXAlignment = Enum.TextXAlignment.Left, ZIndex = Z + 3 })
	local previewingLabel = make("TextLabel", mirror, { Position = UDim2.new(0.4, 0, 0, 4), Size = UDim2.new(0.6, -10, 0, 20), Text = "",
		TextXAlignment = Enum.TextXAlignment.Right, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = Z + 3 })
	local stageScore = make("TextLabel", mirror, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.42), Size = UDim2.fromScale(1, 0.3),
		Text = "12,480", ZIndex = Z + 3 })
	local stageScoreStroke = stroke(stageScore, CREAM, 0)
	local stageName = make("TextLabel", mirror, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.74), Size = UDim2.fromScale(1, 0.16),
		Text = "You", ZIndex = Z + 3 })
	local auraRing = make("Frame", mirror, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.74), Size = UDim2.fromOffset(90, 30),
		BackgroundTransparency = 1, Visible = false, ZIndex = Z + 2 })
	round(auraRing, 15)
	local auraRingStroke = stroke(auraRing, CREAM, 3)
	local stagePoint = make("Frame", mirror, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(2, 2), BackgroundTransparency = 1 })

	local scoreBase, nameBase = 40, 20
	local function sizeStageText()
		scoreBase = math.clamp(math.floor(mirror.AbsoluteSize.Y * 0.2), 24, 56)
		nameBase = math.clamp(math.floor(mirror.AbsoluteSize.Y * 0.09), 16, 26)
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

	-- ===== category tabs (left column, or a row on phones) =====
	local tabsHolder = bind(make("Frame", panel, { Name = "CategoryTabs", BackgroundTransparency = 1 }), function(r) return r.tabs end)
	local tabButtons = {}

	local function layoutTabs()
		local rects = Layout.tabRects({ x = 0, y = 0, w = R.tabs.w, h = R.tabs.h }, #tabButtons, R.narrow)
		for i, t in ipairs(tabButtons) do
			setRect(t.button, rects[i])
			t.sub.Visible = not R.narrow
			t.name.Size = R.narrow and UDim2.new(1, -8, 1, 0) or UDim2.new(1, -16, 0, 22)
			t.name.Position = R.narrow and UDim2.fromOffset(4, 0) or UDim2.fromOffset(10, 8)
			t.name.TextXAlignment = R.narrow and Enum.TextXAlignment.Center or Enum.TextXAlignment.Left
			t.name.TextSize = R.narrow and 14 or 16
		end
	end

	-- ===== tile grid (centre) =====
	local gridFrame = bind(make("ScrollingFrame", panel, { Name = "FlairGrid", BackgroundColor3 = PLATE, BackgroundTransparency = 0, ScrollBarThickness = 8,
		ScrollBarImageColor3 = GOLD, ScrollBarImageTransparency = 0, CanvasSize = UDim2.new(), ScrollingDirection = Enum.ScrollingDirection.Y }), function(r) return r.grid end)
	round(gridFrame, 12)
	stroke(gridFrame, BRASS, 1.5)

	local tiles = {} -- { frame, itemId, ring }

	local function layoutGrid()
		local g = Layout.grid(R.grid.w - 8, #tiles, Layout.cell(R.compact))
		for k, t in ipairs(tiles) do setRect(t.frame, g.cells[k]) end
		gridFrame.CanvasSize = UDim2.fromOffset(0, g.canvasH)
		for _, t in ipairs(tiles) do
			local sel = t.itemId == chosenId
			t.ring.Enabled = sel
			t.frame.BackgroundColor3 = sel and Color3.fromRGB(74, 54, 36) or TILE
		end
	end

	local function buildTile(item)
		local cellSize = Layout.cell(R.compact)
		local med = cellSize.med
		local locked = item.state == "locked"
		local f = make("TextButton", gridFrame, { Name = "Tile_" .. item.id, Text = "", AutoButtonColor = false, BackgroundColor3 = TILE, BackgroundTransparency = 0, ZIndex = Z + 1 })
		round(f, 10)
		stroke(f, item.state == "equipped" and GOLD or Color3.fromRGB(86, 66, 44), item.state == "equipped" and 2.5 or 1)
		local sel = stroke(f, CREAM, 2)
		sel.Enabled = false
		local ic = make("Frame", f, { Name = "Icon", Position = UDim2.fromOffset(math.floor((cellSize.w - med) / 2), 6), Size = UDim2.fromOffset(med, med),
			BackgroundColor3 = locked and Color3.fromRGB(34, 28, 28) or VELVET, ZIndex = Z + 2 })
		circle(ic)
		local glyph = make("TextLabel", ic, { Size = UDim2.fromScale(1, 1), TextSize = math.floor(med * 0.5), Text = item.icon, ZIndex = Z + 3,
			TextColor3 = locked and Color3.fromRGB(110, 100, 96) or CREAM })
		pcall(ArtIcon.apply, ic, "flair", item.id, glyph, { cornerRadius = med / 2, zIndex = Z + 3, dim = locked })
		if locked then
			local shade = make("Frame", ic, { Name = "Silhouette", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(10, 8, 8), BackgroundTransparency = 0.45, ZIndex = Z + 4 })
			circle(shade)
			make("TextLabel", ic, { Name = "Lock", AnchorPoint = Vector2.new(1, 1), Position = UDim2.fromScale(1, 1), Size = UDim2.fromOffset(20, 20), Text = "🔒", TextSize = 14, ZIndex = Z + 5 })
		end
		make("TextLabel", f, { Name = "ItemName", Position = UDim2.fromOffset(4, 6 + med + 4), Size = UDim2.fromOffset(cellSize.w - 8, cellSize.nameH), Text = item.name,
			TextSize = 14, TextWrapped = true, TextTruncate = Enum.TextTruncate.AtEnd, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = Z + 2,
			TextColor3 = locked and Color3.fromRGB(176, 164, 140) or CREAM })
		local status, statusColor
		if item.state == "equipped" then
			status, statusColor = "Equipped", Color3.fromRGB(150, 214, 140)
		elseif item.state == "owned" then
			status, statusColor = (firstSightOwned and not firstSightOwned[item.id]) and "New" or "Unlocked", GOLD
		else
			status, statusColor = item.tag or "Locked", Color3.fromRGB(190, 160, 110)
		end
		make("TextLabel", f, { Name = "Status", Position = UDim2.fromOffset(4, 6 + med + 4 + cellSize.nameH + 2), Size = UDim2.fromOffset(cellSize.w - 8, cellSize.tagH), Text = status,
			TextSize = 14, Font = Enum.Font.GothamMedium, TextColor3 = statusColor, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = Z + 2 })
		f.MouseButton1Click:Connect(function()
			deps.playClickSfx()
			chosenId = item.id
			layoutGrid()
			paintCard()
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
						pcall(deps.particleBurst, UDim2.fromOffset(f.AbsolutePosition.X + cellSize.w / 2, f.AbsolutePosition.Y + 6 + med / 2), GOLD, 10, { size = 7, spread = 60, duration = 0.6 })
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
			stroke(b, on and GOLD or Color3.fromRGB(86, 66, 44), on and 2.5 or 1)
			local name = make("TextLabel", b, { Text = d.icon .. " " .. d.name, TextSize = 16, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = Z + 1,
				TextColor3 = on and CREAM or Color3.fromRGB(210, 194, 164) })
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
		for _, entry in ipairs(placed) do setRect(entry.inst, entry.fn(R)) end
		titleLabel.TextSize = R.compact and 24 or 28
		sizeStageText()
		if #drawers > 0 then FlairDressingRoom._rebuild() end
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
