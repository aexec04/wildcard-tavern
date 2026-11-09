--[[
	Client/ShopCards.lua
	Art-first item cards for the Shop ("The Counter") and its My Patrons / My Recipes tabs.
	Look only: Shop.lua keeps every remote, price check and phase rule and passes an
	`onAction` callback per card. Cards are ART, a name ribbon and a price coin (Engine/CardShape sizes them
	from the viewport so they fill the row); the rules text moved into the shared hover tooltip (Client/Tooltip,
	also tap-and-hold on touch) and the Buy button slides up over the bottom of the art on hover or selection.

	local cards = ShopCards.new({ roundCorner, playClickSfx, particleBurst?, addTooltip? })

	cards.row(parent, layoutOrder, height) -> ScrollingFrame
		Horizontal row of cards, centered when it fits, scrolls sideways when it does not.
	cards.card(row, spec) -> { slot, pop = fn }
		spec.kind        "patron" | "voucher" | "pack" | "owned"   (shapes the card)
		spec.layoutOrder number
		spec.name, spec.description, spec.line   (line replaces the description, e.g. packs; shown in the tooltip)
		spec.price       number | nil (nil = no price tag, owned cards)
		spec.affordable  bool (false = dimmed card and a red price)
		spec.actionText  "Buy" | "Sell" | "Use"; spec.enabled bool; spec.disabledText ("Full")
		spec.emoji       fallback text while art is missing
		spec.artTab      ContentArt category ("patrons", "house_passes", "recipes", "packs")
		spec.artId       registry id for that category
		spec.rarityTab, spec.rarityId, or spec.rarity ("common".."mythical") for the frame
		spec.badge       small corner text ("JUMBO", "MEGA")
		spec.glow        extra frame thickness for big packs
		spec.onAction    function(card) -> bool  (true = it fired: coin burst and pop)
		spec.onClick     function(card)  pick-style cards (pack reveals): a click calls this instead of pinning the
		                 card; the caller shows the choice with card.setSelected(bool)
		card.hit / card.artClip / card.body / card.setSelected(bool)
	cards.soldSpot(row, layoutOrder, kind, animate) -> Frame   empty shelf spot with a SOLD stamp
	cards.note(parent, layoutOrder, text) -> TextLabel   short message row (empty states)

	Hover (or tap) lifts the card 8px, swells its shadow, sweeps a light strip across the art and
	slides the action button up from the bottom. Fast speed and "Reduce screen shake" skip the
	sweep and the slides (the button just appears). All ZIndex values are 6 like the rest of the
	Shop (Global layering, ties break by creation order, so build order below is stacking order).
]]

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Engine = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine")
local CollectionBook = require(Engine:WaitForChild("CollectionBook"))
local ContentArt = require(Engine:WaitForChild("ContentArt"))
local RarityFrame = require(script.Parent.RarityFrame)
local PatronPlaque = require(script.Parent.PatronPlaque)
local ClientSettings = require(script.Parent.ClientSettings)

local ShopCards = {}

local Z = 6
local INK = Color3.fromRGB(60, 40, 22)
local PARCHMENT = Color3.fromRGB(222, 198, 150)
local CREAM = Color3.fromRGB(250, 235, 200)
local WOOD = Color3.fromRGB(92, 62, 36)
local WOOD_DARK = Color3.fromRGB(58, 40, 26)
local GOLD = Color3.fromRGB(222, 182, 104)
local PRICE_OK = Color3.fromRGB(60, 40, 22)
local PRICE_BAD = Color3.fromRGB(190, 40, 34)

local CardShape = require(Engine:WaitForChild("CardShape"))

local HEAD = 16 -- headroom above a resting card so a lifted card and its price tag never clip
local LIFT = 8
local BANNER_H = CardShape.BANNER_H
local BUTTON_H = CardShape.BUTTON_H

-- Shape of a card for the current viewport (cards grow on big screens, shrink on phones).
local scaleOverride = nil -- the Counter sets this so both rows fit the panel (CardShape.fitScale)
function ShopCards.setScale(s) scaleOverride = s end

local function currentScale()
	if scaleOverride then return scaleOverride end
	local cam = workspace.CurrentCamera
	local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
	return CardShape.scaleFor(vp.X, vp.Y)
end

local function shapeFor(kind, noAction)
	return CardShape.shape(kind, currentScale(), noAction)
end

-- Height a row needs for cards of this kind (headroom for the lift, plus the scroll bar).
function ShopCards.rowHeight(kind, noAction)
	return shapeFor(kind, noAction).h + HEAD + 4 + 8
end

local function slow()
	-- No sweeps or slides under Fast speed or Reduce screen shake.
	return ClientSettings.get("animSpeed") == "fast" or ClientSettings.get("reduceShake") == true
end

local function tween(inst, props, time, style, dir)
	local t = TweenService:Create(inst, TweenInfo.new(time, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
	t:Play()
	return t
end

local function corner(inst, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = inst
	return c
end

local function stroke(inst, color, thickness, transparency)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.Transparency = transparency or 0
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = inst
	return s
end

local function frame(parent, props)
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	f.Active = false
	f.ZIndex = Z
	for k, v in pairs(props) do
		f[k] = v
	end
	f.Parent = parent
	return f
end

local function label(parent, props)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.BorderSizePixel = 0
	l.Font = Enum.Font.GothamBold
	l.TextSize = 15
	l.ZIndex = Z
	for k, v in pairs(props) do
		l[k] = v
	end
	l.Parent = parent
	return l
end

-- Pack ids end in _jumbo / _mega; the art and the reveal tier come from the suffix.
local function packTier(packId)
	if type(packId) == "string" then
		if packId:sub(-6) == "_jumbo" then
			return packId:sub(1, -7), "JUMBO", "rare"
		elseif packId:sub(-5) == "_mega" then
			return packId:sub(1, -6), "MEGA", "epic"
		end
	end
	return packId, nil, "common"
end
ShopCards.packTier = packTier

function ShopCards.new(deps)
	local playClickSfx = deps.playClickSfx or function() end
	local particleBurst = deps.particleBurst
	local addTooltip = deps.addTooltip
	local self = {}
	local selected = nil -- the card whose action button is pinned open (tap / click)

	function self.row(parent, layoutOrder, height)
		local row = Instance.new("ScrollingFrame")
		row.Name = "CardRow"
		row.LayoutOrder = layoutOrder
		row.Size = UDim2.new(1, 0, 0, height)
		row.BackgroundTransparency = 1
		row.BorderSizePixel = 0
		row.ScrollingDirection = Enum.ScrollingDirection.X
		row.AutomaticCanvasSize = Enum.AutomaticSize.X
		row.CanvasSize = UDim2.new(0, 0, 0, 0)
		row.ScrollBarThickness = 6
		row.ZIndex = Z
		row.Parent = parent
		local layout = Instance.new("UIListLayout")
		layout.FillDirection = Enum.FillDirection.Horizontal
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		layout.VerticalAlignment = Enum.VerticalAlignment.Top
		layout.Padding = UDim.new(0, 16)
		layout.Parent = row
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 14)
		pad.PaddingRight = UDim.new(0, 14)
		pad.Parent = row
		return row
	end

	function self.note(parent, layoutOrder, text)
		return label(parent, {
			LayoutOrder = layoutOrder,
			Size = UDim2.new(1, 0, 0, 40),
			Font = Enum.Font.Gotham,
			TextWrapped = true,
			TextColor3 = CREAM,
			Text = text,
		})
	end

	-- A compact, STILL empty state: three small faint ghost cards on dotted outlines and one short line under
	-- them (Engine/EmptyStates). No motion at all (the old bobbing ghosts looked laggy). The hint lives in the
	-- hover tooltip, whose target is the ghosts only, so the tooltip (placed above the target) never covers
	-- the line of text.
	function self.emptyScene(parent, layoutOrder, key)
		local EmptyStates = require(Engine:WaitForChild("EmptyStates"))
		local scale = math.min(currentScale(), 1)
		local gw, gh = math.floor(64 * scale + 0.5), math.floor(86 * scale + 0.5)
		local H = gh + 50 -- about 140px, well under the 200px cap
		local scene = frame(parent, { Name = "EmptyScene", LayoutOrder = layoutOrder, Size = UDim2.new(1, 0, 0, H), BackgroundTransparency = 1 })
		local icons = EmptyStates.icons(key)
		local cluster = frame(scene, { Name = "GhostCluster", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 6),
			Size = UDim2.fromOffset(3 * gw + 2 * 16, gh), BackgroundTransparency = 1 })
		for i = 1, 3 do
			local group = frame(cluster, { Name = "Ghost" .. i, Position = UDim2.fromOffset((i - 1) * (gw + 16), 0),
				Size = UDim2.fromOffset(gw, gh), BackgroundColor3 = CREAM, BackgroundTransparency = 0.93 })
			corner(group, 8)
			-- dotted outline: small dots around the perimeter
			local step = 11
			local function dot(x, y)
				local d = frame(group, { Position = UDim2.fromOffset(x - 2, y - 2), Size = UDim2.fromOffset(4, 4), BackgroundColor3 = CREAM, BackgroundTransparency = 0.45 })
				corner(d, 2)
			end
			for x = 6, gw - 6, step do dot(x, 3) dot(x, gh - 3) end
			for y = 6, gh - 6, step do dot(3, y) dot(gw - 3, y) end
			label(group, { Size = UDim2.fromScale(1, 1), Text = icons[i] or "", TextSize = math.floor(30 * scale), TextTransparency = 0.82,
				TextColor3 = CREAM })
		end
		label(scene, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -4), Size = UDim2.new(1, -20, 0, 30),
			Font = Enum.Font.GothamBold, TextSize = 18, TextColor3 = CREAM, TextStrokeColor3 = Color3.fromRGB(30, 20, 12),
			TextStrokeTransparency = 0.5, Text = EmptyStates.line(key) })
		if addTooltip then
			local hint = EmptyStates.hint(key)
			if hint ~= "" then
				-- the tooltip target must be a GuiButton-like with MouseEnter: a transparent button over the ghosts only
				local hit = Instance.new("TextButton")
				hit.Size = UDim2.fromScale(1, 1)
				hit.BackgroundTransparency = 1
				hit.Text = ""
				hit.AutoButtonColor = false
				hit.ZIndex = Z
				hit.Parent = cluster
				addTooltip(hit, hint)
			end
		end
		return scene
	end

	function self.soldSpot(row, layoutOrder, kind, animate)
		local shape = shapeFor(kind)
		local slot = frame(row, { Name = "SoldSpot", LayoutOrder = layoutOrder,
			Size = UDim2.fromOffset(shape.w, shape.h + HEAD + 4), BackgroundTransparency = 1 })
		local spot = frame(slot, { Position = UDim2.fromOffset(0, HEAD), Size = UDim2.fromOffset(shape.w, shape.h),
			BackgroundColor3 = Color3.fromRGB(20, 14, 10), BackgroundTransparency = 0.45 })
		corner(spot, 10)
		stroke(spot, Color3.fromRGB(120, 88, 56), 2, 0.4)
		local stamp = label(spot, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(shape.w - 30, 48), Text = "SOLD", TextSize = 34, Rotation = -12,
			TextColor3 = Color3.fromRGB(214, 70, 56), TextStrokeColor3 = Color3.fromRGB(40, 12, 8), TextStrokeTransparency = 0.3 })
		if animate and not slow() then
			local scale = Instance.new("UIScale")
			scale.Scale = 2.4
			scale.Parent = stamp
			stamp.TextTransparency = 1
			stamp.TextStrokeTransparency = 1
			tween(scale, { Scale = 1 }, 0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
			tween(stamp, { TextTransparency = 0, TextStrokeTransparency = 0.3 }, 0.14)
		end
		return slot
	end

	function self.card(row, spec)
		local shape = shapeFor(spec.kind, spec.noAction)
		local W = shape.w
		local card = {}

		local slot = frame(row, { Name = "Card_" .. tostring(spec.name), LayoutOrder = spec.layoutOrder or 0,
			Size = UDim2.fromOffset(W, shape.h + HEAD + 4), BackgroundTransparency = 1 })
		card.slot = slot
		card.spec = spec
		-- stable tags for the tutorial spotlight (cards are rebuilt on every refresh)
		slot:SetAttribute("TutorialKind", spec.kind)
		slot:SetAttribute("TutorialPrice", spec.price or 0)

		-- Shadow stays put while the card lifts, so the gap reads as height.
		local shadow = frame(slot, { Position = UDim2.fromOffset(2, HEAD + 6), Size = UDim2.fromOffset(W - 4, shape.h),
			BackgroundColor3 = Color3.fromRGB(0, 0, 0), BackgroundTransparency = 0.7 })
		corner(shadow, 12)

		local body = frame(slot, { Name = "Body", Position = UDim2.fromOffset(0, HEAD), Size = UDim2.fromOffset(W, shape.h),
			BackgroundColor3 = WOOD_DARK })
		corner(body, 10)
		stroke(body, Color3.fromRGB(30, 20, 12), 2, 0)
		card.body = body

		-- ===== Art, the hero: Crop inside a rarity frame =====
		local artFrame = frame(body, { Name = "ArtFrame", Position = UDim2.fromOffset(6, shape.artTop),
			Size = UDim2.fromOffset(W - 12, shape.artH), BackgroundTransparency = 1 })
		corner(artFrame, 8)
		local artClip = frame(artFrame, { Name = "ArtClip", Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Color3.fromRGB(40, 30, 22), ClipsDescendants = true })
		corner(artClip, 8)
		local emoji = label(artClip, { Name = "EmojiFallback", Size = UDim2.fromScale(1, 1), Text = spec.emoji or "",
			TextSize = 54, TextColor3 = CREAM })
		local artId = spec.artTab and spec.artId and ContentArt.getImageId(spec.artTab, spec.artId) or nil
		if artId then
			local art = PatronPlaque.applyById(artClip, artId, { emojiLabel = emoji, zIndex = Z, cornerRadius = 8 })
			if art then
				art.ScaleType = spec.kind == "pack" and Enum.ScaleType.Fit or Enum.ScaleType.Crop
			end
		end
		local rarity = spec.rarity
		if not rarity and spec.rarityTab and spec.rarityId then
			rarity = CollectionBook.rarityForId(spec.rarityTab, spec.rarityId)
		end
		RarityFrame.apply(artFrame, rarity or "common", { thickness = 2 + (spec.glow or 0), radius = 8, zIndex = Z })

		-- Shine strip: Color stops only (no UIGradient.Transparency), clipped by artFrame.
		local strip = frame(artClip, { Name = "ShineStrip", AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.new(0.16, 0, 1.8, 0),
			Position = UDim2.new(-0.3, 0, 0.5, 0), Rotation = 20, BackgroundColor3 = CREAM, BackgroundTransparency = 0.8 })
		local grad = Instance.new("UIGradient")
		grad.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(235, 210, 160)),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 250, 235)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(235, 210, 160)),
		})
		grad.Parent = strip

		if spec.badge then
			local pill = frame(artClip, { Position = UDim2.fromOffset(6, 6), Size = UDim2.fromOffset(#spec.badge * 10 + 16, 22),
				BackgroundColor3 = Color3.fromRGB(30, 20, 14), BackgroundTransparency = 0.15 })
			corner(pill, 11)
			stroke(pill, GOLD, 1.5, 0)
			label(pill, { Size = UDim2.fromScale(1, 1), Text = spec.badge, TextColor3 = GOLD })
		end

		-- ===== Synergy tags (Engine/Synergy.lua): up to 2 small glowing pills, icon plus one word, top right =====
		for i, tag in ipairs(spec.synergy or {}) do
			local pill = frame(artClip, { Name = "Synergy_" .. tag.tag, AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -6, 0, 6 + (i - 1) * 28), Size = UDim2.fromOffset(#tag.word * 8 + 36, 24),
				BackgroundColor3 = Color3.fromRGB(30, 20, 14), BackgroundTransparency = 0.1 })
			corner(pill, 12)
			stroke(pill, Color3.fromRGB(255, 226, 140), 2, 0) -- gold glow ring
			label(pill, { Size = UDim2.new(1, -4, 1, 0), Position = UDim2.fromOffset(2, 0), Text = tag.icon .. " " .. tag.word,
				TextColor3 = Color3.fromRGB(255, 226, 140), TextSize = 14 })
			if addTooltip then
				addTooltip(pill, tag.line .. " " .. (tag.reason or ""))
			end
		end

		-- ===== Boss counter shield (Engine/BossCounters.lua): this item helps against the upcoming boss, bottom left =====
		if spec.shield then
			local pill = frame(artClip, { Name = "BossShield", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 6, 1, -6),
				Size = UDim2.fromOffset(76, 24), BackgroundColor3 = Color3.fromRGB(30, 36, 58), BackgroundTransparency = 0.1 })
			corner(pill, 12)
			stroke(pill, Color3.fromRGB(140, 200, 255), 2, 0)
			label(pill, { Size = UDim2.new(1, -4, 1, 0), Position = UDim2.fromOffset(2, 0), Text = "🛡️ " .. (spec.shield.ruleIcon or ""), TextColor3 = Color3.fromRGB(190, 225, 255), TextSize = 14 })
			if addTooltip then
				addTooltip(pill, spec.shield.line)
			end
		end

		-- ===== Name ribbon overlapping the bottom of the art =====
		local banner = frame(body, { Name = "Banner", Position = UDim2.fromOffset(2, shape.bannerTop), Size = UDim2.fromOffset(W - 4, BANNER_H),
			BackgroundColor3 = WOOD })
		corner(banner, 6)
		stroke(banner, GOLD, 1.5, 0)
		label(banner, { Position = UDim2.fromOffset(6, 0), Size = UDim2.new(1, -12, 1, 0), Text = spec.name or "",
			TextColor3 = CREAM, TextWrapped = true, TextSize = 16 })

		-- ===== Dim when it cannot be afforded =====
		local affordable = spec.affordable ~= false
		if not affordable then
			local dim = frame(body, { Name = "Dim", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(0, 0, 0),
				BackgroundTransparency = 0.72 })
			corner(dim, 10)
		end

		-- ===== Price tag hanging off the top-right corner =====
		if spec.price then
			local tag = frame(body, { Name = "PriceTag", AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromOffset(W + 6, -6),
				Size = UDim2.fromOffset(64, 28), BackgroundColor3 = GOLD, Rotation = 6 })
			corner(tag, 8)
			stroke(tag, Color3.fromRGB(110, 76, 34), 2, 0)
			local coin = frame(tag, { Position = UDim2.fromOffset(7, 6), Size = UDim2.fromOffset(16, 16), BackgroundColor3 = Color3.fromRGB(246, 208, 96) })
			corner(coin, 8)
			stroke(coin, Color3.fromRGB(150, 100, 30), 2, 0)
			label(tag, { Position = UDim2.fromOffset(26, 0), Size = UDim2.new(1, -30, 1, 0), Text = tostring(math.floor(spec.price)),
				TextSize = 18, TextColor3 = affordable and PRICE_OK or PRICE_BAD, TextXAlignment = Enum.TextXAlignment.Center })
		end

		-- ===== Input: one transparent button over the body, then the action drawer =====
		local hit = Instance.new("TextButton")
		hit.Name = "Hit"
		hit.Size = UDim2.fromScale(1, 1)
		hit.BackgroundTransparency = 1
		hit.Text = ""
		hit.AutoButtonColor = false
		hit.ZIndex = Z
		hit.Parent = body
		card.hit = hit
		card.artClip = artClip

		-- Pick-style cards (pack reveals): a green check and a thick gold edge show the choice.
		local pickedBadge = frame(body, { Name = "PickedBadge", Position = UDim2.fromOffset(8, 8), Size = UDim2.fromOffset(34, 34),
			BackgroundColor3 = Color3.fromRGB(86, 140, 80), Visible = false, ZIndex = Z + 2 })
		corner(pickedBadge, 17)
		stroke(pickedBadge, GOLD, 2, 0)
		label(pickedBadge, { Size = UDim2.fromScale(1, 1), Text = "OK", TextSize = 16, TextColor3 = CREAM, ZIndex = Z + 3 })
		local pickedStroke = stroke(body, GOLD, 4, 1)
		function card.setSelected(on)
			pickedBadge.Visible = on
			pickedStroke.Transparency = on and 0 or 1
		end

		-- The rules text lives in the shared hover tooltip (name on the first line, then the effect).
		local tipText = spec.line or spec.description
		if addTooltip and tipText and tipText ~= "" then
			addTooltip(hit, function()
				return (spec.name or "") .. "\n" .. tipText
			end)
		end

		local enabled = spec.enabled ~= false
		local button
		if not spec.noAction then
			local drawer = frame(body, { Name = "Drawer", Position = UDim2.fromOffset(0, shape.drawerTop - 2), Size = UDim2.fromOffset(W, BUTTON_H + 4),
				BackgroundTransparency = 1, ClipsDescendants = true })
			button = Instance.new("TextButton")
			button.Name = "Action"
			button.Size = UDim2.fromOffset(W - 20, BUTTON_H)
			button.Position = UDim2.fromOffset(10, BUTTON_H + 8) -- hidden below the drawer's clip
			button.Font = Enum.Font.GothamBold
			button.TextSize = 16
			button.AutoButtonColor = false
			button.Text = enabled and (spec.actionText or "Buy") or (spec.disabledText or "Full")
			button.TextColor3 = enabled and CREAM or Color3.fromRGB(180, 170, 160)
			button.BackgroundColor3 = enabled and Color3.fromRGB(70, 130, 60) or Color3.fromRGB(70, 60, 55)
			button.ZIndex = Z
			button.Parent = drawer
			corner(button, 8)
			stroke(button, enabled and GOLD or Color3.fromRGB(110, 96, 84), 2, 0)
		end

		local over, pinned, shown, busy = 0, false, false, false
		local function show(on)
			if shown == on then
				return
			end
			shown = on
			if button then
				local restY = on and 2 or (BUTTON_H + 8)
				if slow() then
					button.Position = UDim2.fromOffset(10, restY)
				else
					tween(button, { Position = UDim2.fromOffset(10, restY) }, on and 0.16 or 0.12, on and Enum.EasingStyle.Back or Enum.EasingStyle.Quad)
				end
			end
			if on then
				tween(body, { Position = UDim2.fromOffset(0, HEAD - LIFT) }, 0.14)
				tween(shadow, { BackgroundTransparency = 0.5 }, 0.14)
				if not slow() then
					strip.Position = UDim2.new(-0.3, 0, 0.5, 0)
					tween(strip, { Position = UDim2.new(1.3, 0, 0.5, 0) }, 0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
				end
			else
				tween(body, { Position = UDim2.fromOffset(0, HEAD) }, 0.16)
				tween(shadow, { BackgroundTransparency = 0.7 }, 0.16)
			end
		end
		local function refresh()
			if busy then
				return
			end
			show(over > 0 or pinned)
		end
		local function enter()
			if require(script.Parent.ModalStage).blocks(hit) then return end -- a modal is open: nothing behind it reacts
			over += 1
			refresh()
		end
		local function leave()
			over = math.max(0, over - 1)
			task.delay(0.06, refresh)
		end
		hit.MouseEnter:Connect(enter)
		hit.MouseLeave:Connect(leave)
		if button then
			button.MouseEnter:Connect(enter)
			button.MouseLeave:Connect(leave)
		end

		local function setPinned(on)
			pinned = on
			refresh()
		end
		card.setPinned = setPinned
		hit.MouseButton1Click:Connect(function()
			if spec.onClick then
				playClickSfx(0.3)
				spec.onClick(card)
				return
			end
			playClickSfx(0.3)
			if selected and selected ~= card then
				pcall(selected.setPinned, false)
			end
			selected = (not pinned) and card or nil
			setPinned(not pinned)
		end)

		-- Coin burst + pop when the action actually fires (spec.onAction returns true).
		function card.pop()
			busy = true
			if particleBurst and slot.AbsoluteSize.X > 0 then
				local pos = slot.AbsolutePosition + slot.AbsoluteSize / 2
				pcall(particleBurst, UDim2.fromOffset(pos.X, pos.Y), Color3.fromRGB(246, 208, 96), 16, { spread = 90, duration = 0.5 })
			end
			if slow() then
				return
			end
			local scale = Instance.new("UIScale")
			scale.Parent = body
			tween(scale, { Scale = 1.08 }, 0.1)
			task.delay(0.1, function()
				if scale.Parent then
					tween(scale, { Scale = 0.01 }, 0.18, Enum.EasingStyle.Back, Enum.EasingDirection.In)
				end
			end)
			-- If the server rejected the buy the card is still here after a moment: bring it back.
			task.delay(2.5, function()
				if scale.Parent then
					busy = false
					tween(scale, { Scale = 1 }, 0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
				end
			end)
		end

		if button then
		button.MouseButton1Click:Connect(function()
			-- A disabled ("Full") button still calls onAction so Shop.lua can show its warning.
			if spec.onAction and spec.onAction(card) then
				card.pop()
			end
		end)
		end

		return card
	end

	return self
end

return ShopCards
