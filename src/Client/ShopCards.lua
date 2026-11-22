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
		spec.ribbon      the words on the name plate when they differ from spec.name (packs: Engine/Packs.shelfName)
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

	Hover (or tap) lifts the card 6px and turns it straight (the Counter lays every card on the felt at its own angle, kept in
	the slot's Tilt attribute), swells its shadow, shows the action button as a full plate over the art from the
	bottom. Fast speed and "Reduce screen shake" skip the sweep and the slides (the button just appears); "Reduce screen shake"
	also skips the lift and the turn: the card stays put. All ZIndex values are 6 like the rest of the
	Shop (Global layering, ties break by creation order, so build order below is stacking order).
]]

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Engine = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine")
local CollectionBook = require(Engine:WaitForChild("CollectionBook"))
local ChoiceRarity = require(Engine:WaitForChild("ChoiceRarity"))
local PatronCardSpec = require(Engine:WaitForChild("PatronCardSpec"))
local ContentArt = require(Engine:WaitForChild("ContentArt"))
local AbilityText = require(Engine:WaitForChild("AbilityText"))
local Packs = require(Engine:WaitForChild("Packs"))
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
local SceneLayout = require(Engine:WaitForChild("ShopSceneLayout"))

local HEAD = 16 -- headroom above a resting card so a lifted card and its price tag never clip
local LIFT = 6 -- a hovered card rises this far and straightens (ShopStage turns every card to its own fixed angle)
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
local packTier = Packs.sizeInfo -- shared with the tests (Engine/Packs)
ShopCards.packTier = packTier

function ShopCards.new(deps)
	local playClickSfx = deps.playClickSfx or function() end
	local particleBurst = deps.particleBurst
	local flipLast, flipN = nil, 0 -- card flip in stagger (Engine/AnimPass.cardFlip)
	local sparkled = {} -- offer key -> last sparkle time (Engine/ShopSparkle.shouldPlay)
	local addTooltip = deps.addTooltip
	local self = {}
	local selected = nil -- the card whose action button is pinned open (tap / click)

	function self.row(parent, layoutOrder, height, gap)
		local row = Instance.new("ScrollingFrame")
		row.Name = "CardRow"
		row.LayoutOrder = layoutOrder
		row.Size = UDim2.new(1, 0, 0, height)
		row.BackgroundTransparency = 1
		row.BorderSizePixel = 0
		row.ScrollingDirection = Enum.ScrollingDirection.X
		row.AutomaticCanvasSize = Enum.AutomaticSize.X
		row.CanvasSize = UDim2.new(0, 0, 0, 0)
		row.ScrollBarThickness = 0 -- no grey bar under the cards; the row still scrolls by wheel or drag
		row.ZIndex = Z
		row.Parent = parent
		local layout = Instance.new("UIListLayout")
		layout.FillDirection = Enum.FillDirection.Horizontal
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		layout.VerticalAlignment = Enum.VerticalAlignment.Top
		layout.Padding = UDim.new(0, gap or 16)
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
				Size = UDim2.fromOffset(gw, gh), BackgroundColor3 = Color3.fromRGB(26, 18, 12), BackgroundTransparency = 0.35 })
			corner(group, 10)
			stroke(group, Color3.fromRGB(120, 88, 56), 1, 0.6) -- soft dim slot like an Empty seat, no dotted outline
			label(group, { Size = UDim2.fromScale(1, 1), Text = icons[i] or "", TextSize = math.floor(30 * scale), TextTransparency = 0.82,
				TextColor3 = CREAM })
		end
		local msg = label(scene, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -4), Size = UDim2.fromOffset(0, 30),
			Font = Enum.Font.GothamBold, TextSize = 18, TextColor3 = CREAM, TextStrokeColor3 = Color3.fromRGB(30, 20, 12),
			TextStrokeTransparency = 0.8, Text = EmptyStates.line(key), BackgroundColor3 = Color3.fromRGB(26, 18, 12),
			BackgroundTransparency = 0.1 })
		msg.AutomaticSize = Enum.AutomaticSize.X
		corner(msg, 8)
		local msgPad = Instance.new("UIPadding")
		msgPad.PaddingLeft = UDim.new(0, 16)
		msgPad.PaddingRight = UDim.new(0, 16)
		msgPad.Parent = msg
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

	-- An empty seat: a soft dim slot the size of an owned card (My Patrons shows one per free seat), no dotted outline.
	function self.seatSlot(row, layoutOrder, kind)
		local shape = shapeFor(kind)
		local slot = frame(row, { Name = "SeatSlot", LayoutOrder = layoutOrder,
			Size = UDim2.fromOffset(shape.w, shape.h + HEAD + 4), BackgroundTransparency = 1 })
		local box = frame(slot, { Position = UDim2.fromOffset(0, HEAD), Size = UDim2.fromOffset(shape.w, shape.h),
			BackgroundColor3 = Color3.fromRGB(26, 18, 12), BackgroundTransparency = 0.35 })
		corner(box, 10)
		stroke(box, Color3.fromRGB(120, 88, 56), 1, 0.6)
		label(box, { Size = UDim2.fromScale(1, 1), Text = "Empty seat", TextSize = 15, TextWrapped = true,
			TextColor3 = CREAM, TextTransparency = 0.35 })
		return slot
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
			TextColor3 = Color3.fromRGB(214, 70, 56), TextStrokeColor3 = Color3.fromRGB(40, 12, 8), TextStrokeTransparency = 0.8 })
		if animate and not slow() then
			local scale = Instance.new("UIScale")
			scale.Scale = 2.4
			scale.Parent = stamp
			stamp.TextTransparency = 1
			stamp.TextStrokeTransparency = 1
			tween(scale, { Scale = 1 }, 0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
			tween(stamp, { TextTransparency = 0, TextStrokeTransparency = 0.8 }, 0.14)
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

		-- The slot is the LAYOUT root: a direct child of the row (a ScrollingFrame), where Roblox ignores Rotation. So the card is tilted on
		-- an inner full-size wrapper, Tilt (ShopStage sets its Rotation to the card's angle; a hover turns it straight), and everything
		-- the card is made of lives inside it.
		local tilt = frame(slot, { Name = "Tilt", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 })
		card.tilt = tilt

		-- Shadow stays put while the card lifts, so the gap reads as height.
		local shadow = frame(tilt, { Position = UDim2.fromOffset(2, HEAD + 6), Size = UDim2.fromOffset(W - 4, shape.h),
			BackgroundColor3 = Color3.fromRGB(0, 0, 0), BackgroundTransparency = 0.7 })
		corner(shadow, 12)
		-- a soft oval on the felt under the card's lower edge: the card lies on the table
		local contact = frame(tilt, { Name = "ContactShadow", Position = UDim2.fromOffset(math.floor(W * 0.08), HEAD + shape.h - 8),
			Size = UDim2.fromOffset(math.floor(W * 0.84), 18), BackgroundColor3 = Color3.fromRGB(0, 0, 0), BackgroundTransparency = 0.62 })
		corner(contact, 9)

		local body = frame(tilt, { Name = "Body", Position = UDim2.fromOffset(0, HEAD), Size = UDim2.fromOffset(W, shape.h),
			BackgroundColor3 = WOOD_DARK })
		corner(body, 10)
		if spec.highlight == true then -- first buy: a steady gold outline on the one affordable Patron (no tween, so Calm mode is the same)
			local hs = stroke(body, Color3.fromRGB(246, 196, 70), 4, 0)
			hs.Name = "FirstBuyOutline"
		else
			stroke(body, Color3.fromRGB(30, 20, 12), 2, 0)
		end
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
		if spec.kind == "patron" and require(Engine:WaitForChild("Gameplay2Synergy")).completes(spec.synergy) then
			-- an offer that works with a Patron you own: a soft gold outline (the chip below says which theme)
			local glow = Instance.new("Frame")
			glow.Name = "SynergyGlow"
			glow.BackgroundTransparency = 1
			glow.BorderSizePixel = 0
			glow.Size = UDim2.new(1, 6, 1, 6)
			glow.Position = UDim2.fromOffset(-3, -3)
			glow.ZIndex = Z + 2
			glow.Active = false
			local gc = Instance.new("UICorner"); gc.CornerRadius = UDim.new(0, 10); gc.Parent = glow
			local gs = Instance.new("UIStroke"); gs.Color = Color3.fromRGB(246, 196, 70); gs.Thickness = 2; gs.Transparency = 0.4; gs.Parent = glow
			glow.Parent = artFrame
		end
		do -- cards turn up one by one when a shelf first shows (index counts cards built within 0.4 s of each other; none in Calm mode)
			local now = os.clock()
			if now - (flipLast or -1) > 0.4 then flipN = 0 end
			flipLast, flipN = now, flipN + 1
			if spec.kind ~= "owned" then local n = flipN; pcall(function() require(script.Parent.AnimPassFX).cardFlip(slot, n) end) end
		end
		-- a Rare or better offer gives one small sparkle in its tier colour when it first shows (none in calm mode or on Fast)
		if particleBurst and spec.kind ~= "owned" then
			local sp = require(Engine:WaitForChild("ShopSparkle"))
			local plan = sp.spec(rarity, slow())
			if plan and sp.shouldPlay(sparkled, tostring(spec.artTab) .. ":" .. tostring(spec.artId or spec.name), os.clock()) then
				task.delay(0.3, function()
					if slot.Parent and slot.AbsoluteSize.X > 0 then
						local pos = slot.AbsolutePosition + slot.AbsoluteSize / 2
						pcall(particleBurst, UDim2.fromOffset(pos.X, pos.Y), Color3.fromRGB(plan.color[1], plan.color[2], plan.color[3]), plan.count,
							{ spread = plan.spread, duration = plan.duration })
					end
				end)
			end
		end
		-- Pick screens: the tier as a word (readable without colour), only for an item that really has a rarity (ChoiceRarity.lookup is
		-- nil for an unknown id, so "Common" is never shown by mistake). A dark pill at the top right of the art, 15 px.
		if spec.rarityWord and spec.rarityTab and spec.rarityId then
			local info = ChoiceRarity.info(spec.rarityTab, spec.rarityId)
			if info then
				local wordW = math.max(64, #info.word * 9 + 18 + 16) -- 16 px for the tier shape marker
				local tier = Color3.fromRGB(info.text[1], info.text[2], info.text[3])
				local pill = frame(artClip, { Name = "RarityTag", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -6, 0, 6),
					Size = UDim2.fromOffset(wordW, 22), BackgroundColor3 = Color3.fromRGB(info.plate[1], info.plate[2], info.plate[3]), BackgroundTransparency = 0.05 })
				corner(pill, 11)
				stroke(pill, tier, 1.5, 0)
				label(pill, { Name = "Word", Position = UDim2.fromOffset(16, 0), Size = UDim2.new(1, -16, 1, 0), Text = info.word, TextColor3 = tier, TextSize = PatronCardSpec.RARITY_SIZE, TextStrokeTransparency = 1 })
				pcall(function() require(script.Parent.RarityShape).set(pill, info.rarity, 12, 5) end) -- shape beside the word: never colour alone
			end
		end

		-- No shine strip: Roblox ignores ClipsDescendants under the rotated Tilt wrapper, so a moving strip escaped the card.

		local synergy = spec.synergy or {}
		local chipWidths = {}
		for i, tag in ipairs(synergy) do chipWidths[i] = SceneLayout.pillWidth(tag.word) end
		local ov = SceneLayout.cardOverlays(W, shape.artTop, shape.artH, shape.bannerTop,
			spec.badge and SceneLayout.pillWidth(spec.badge) or 0, chipWidths)
		-- overlay rects are in body pixels; artClip starts at (6, artTop)
		local function inArt(r) return UDim2.fromOffset(r.x - 6, r.y - shape.artTop) end

		if spec.badge and ov.badge then
			local pill = frame(artClip, { Name = "BadgePill", Position = inArt(ov.badge), Size = UDim2.fromOffset(ov.badge.w, ov.badge.h),
				BackgroundColor3 = Color3.fromRGB(30, 20, 14), BackgroundTransparency = 0.05 })
			corner(pill, 11)
			stroke(pill, GOLD, 1.5, 0)
			local badgeText = label(pill, { Size = UDim2.fromScale(1, 1), Text = spec.badge, TextColor3 = GOLD, TextScaled = true })
			local badgeFit = Instance.new("UITextSizeConstraint") -- fits the pill, never under 12 px
			badgeFit.MinTextSize, badgeFit.MaxTextSize = 14, 15
			badgeFit.Parent = badgeText
		end

		-- ===== Synergy tags (Engine/Synergy.lua): up to 2 pills, a drawn gold diamond plus one word, top left under the badge =====
		for i, tag in ipairs(synergy) do
			local r = ov.chips[i]
			local pill = frame(artClip, { Name = "Synergy_" .. tag.tag, Position = inArt(r), Size = UDim2.fromOffset(r.w, r.h),
				BackgroundColor3 = Color3.fromRGB(30, 20, 14), BackgroundTransparency = 0.05 })
			corner(pill, 12)
			stroke(pill, Color3.fromRGB(255, 226, 140), 2, 0) -- gold glow ring
			frame(pill, { Name = "Gem", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, 14, 0.5, 0),
				Size = UDim2.fromOffset(8, 8), Rotation = 45, BackgroundColor3 = Color3.fromRGB(255, 226, 140) })
			local chipText = label(pill, { Size = UDim2.new(1, -26, 1, 0), Position = UDim2.fromOffset(24, 0), Text = tag.word,
				TextColor3 = Color3.fromRGB(255, 226, 140), TextSize = 15, TextStrokeTransparency = 1, TextScaled = true })
			local chipFit = Instance.new("UITextSizeConstraint")
			chipFit.MinTextSize, chipFit.MaxTextSize = 14, 15
			chipFit.Parent = chipText
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
			BackgroundColor3 = WOOD_DARK })
		corner(banner, 6)
		stroke(banner, GOLD, 1.5, 0)
		-- shrinks (16 down to 14) so a long name like "Wholesale Pricing" wraps at the space, never mid-word
		local nameLabel = label(banner, { Position = UDim2.fromOffset(6, 0), Size = UDim2.new(1, -12, 1, 0), Text = spec.ribbon or spec.name or "",
			TextColor3 = CREAM, TextWrapped = true, TextSize = PatronCardSpec.NAME.max, TextScaled = true, TextStrokeTransparency = 1 })
		if nameLabel then
			local fit = Instance.new("UITextSizeConstraint")
			fit.MinTextSize, fit.MaxTextSize = PatronCardSpec.NAME.min, PatronCardSpec.NAME.max
			fit.Parent = nameLabel
		end

		-- ===== Dim when it cannot be afforded =====
		local affordable = spec.affordable ~= false
		if not affordable then
			local dim = frame(body, { Name = "Dim", Size = UDim2.new(1, 0, 0, shape.bannerTop), BackgroundColor3 = Color3.fromRGB(0, 0, 0),
				BackgroundTransparency = 0.72 }) -- art only, so the name plate keeps cream text on dark
			corner(dim, 10)
		end

		-- ===== Price tag at the lower right of the art, above the name ribbon =====
		if spec.price then
			local tag = frame(body, { Name = "PriceTag", Position = UDim2.fromOffset(ov.price.x, ov.price.y),
				Size = UDim2.fromOffset(ov.price.w, ov.price.h), BackgroundColor3 = GOLD, ZIndex = Z + 1 })
			corner(tag, 8)
			stroke(tag, Color3.fromRGB(110, 76, 34), 2, 0)
			local coin = frame(tag, { Position = UDim2.fromOffset(7, 6), Size = UDim2.fromOffset(16, 16), BackgroundColor3 = Color3.fromRGB(246, 208, 96), ZIndex = Z + 2 })
			corner(coin, 8)
			stroke(coin, Color3.fromRGB(150, 100, 30), 2, 0)
			label(tag, { Position = UDim2.fromOffset(26, 0), Size = UDim2.new(1, -30, 1, 0), Text = tostring(math.floor(spec.price)),
				TextSize = 18, ZIndex = Z + 3, TextStrokeTransparency = 1, TextColor3 = affordable and PRICE_OK or PRICE_BAD, TextXAlignment = Enum.TextXAlignment.Center })
			pcall(function() require(script.Parent.ConceptTSkin).pricePill(tag, spec.price, affordable, Z + 1) end) -- painted pill like the play HUD; no art id keeps the gold tag
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
		do -- a drawn check mark (two bars), not a font glyph
			local function bar(name, x, y, w, rot)
				local b = frame(pickedBadge, { Name = name, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(x, y),
					Size = UDim2.fromOffset(w, 4), BackgroundColor3 = CREAM, Rotation = rot, ZIndex = Z + 3 })
				corner(b, 2)
			end
			bar("CheckShort", 12, 19, 10, 45)
			bar("CheckLong", 20, 16, 18, -50)
		end
		local pickedStroke = stroke(body, GOLD, 4, 1)
		function card.setSelected(on)
			pickedBadge.Visible = on
			pickedStroke.Transparency = on and 0 or 1
		end

		-- The rules text lives in the shared hover tooltip (name on the first line, then the effect).
		local tipText = spec.line or spec.description
		if addTooltip and tipText and tipText ~= "" then
			-- effect first, the condition on its own line, numbers in gold (Engine/AbilityText); a pack's own line stays as written
			local body = spec.line and tipText or AbilityText.tooltip(tipText)
			addTooltip(hit, function()
				return (spec.name or "") .. "\n" .. body
			end, spec.tipAlign, banner)
		end

		local enabled = spec.enabled ~= false
		local button
		if not spec.noAction then
			local drawer = frame(body, { Name = "Drawer", Position = UDim2.fromOffset(0, (spec.price and ov.price.y or (shape.bannerTop - 4)) - 4 - BUTTON_H), Size = UDim2.fromOffset(W, BUTTON_H),
				BackgroundTransparency = 1, ZIndex = Z + 4 }) -- over the art above the price tag; never clipped (clips fail under Tilt)
			button = Instance.new("TextButton")
			button.Name = "Action"
			-- Buy is a full plate over the art just above the price tag, shown on hover or selection (Visible, no slide)
			button.Size = UDim2.fromOffset(math.max(80, W - 20), BUTTON_H)
			button.Position = UDim2.fromOffset(10, 0)
			button.Visible = false
			button.Font = Enum.Font.GothamBold
			button.TextSize = 16
			button.AutoButtonColor = false
			button.Text = enabled and ((spec.shortBy or 0) > 0 and string.format("Need %d more", math.floor(spec.shortBy)) or (spec.actionText or "Buy")) or (spec.disabledText or "Full")
			button.TextColor3 = enabled and CREAM or Color3.fromRGB(180, 170, 160)
			button.BackgroundColor3 = enabled and Color3.fromRGB(70, 130, 60) or Color3.fromRGB(70, 60, 55)
			button.ZIndex = Z + 4
			button.Parent = drawer
			corner(button, 8)
			stroke(button, enabled and GOLD or Color3.fromRGB(110, 96, 84), 2, 0)
			if enabled then
				pcall(function() require(script.Parent.ConceptTSkin).plateButton(button) end) -- the one green plate style
			end
		end

		local over, pinned, shown, busy = 0, false, false, false
		local function show(on)
			if shown == on then
				return
			end
			shown = on
			if button then
				button.Visible = on
			end
			local still = ClientSettings.get("reduceShake") == true -- calm mode: the card stays where it lies
			if on then
				if not still then
					tween(body, { Position = UDim2.fromOffset(0, HEAD - LIFT) }, 0.14)
					tween(tilt, { Rotation = 0 }, 0.14) -- turn straight (the wrapper: a direct child of the row would ignore it)
				end
				tween(shadow, { BackgroundTransparency = 0.5 }, 0.14)
			else
				if not still then
					tween(body, { Position = UDim2.fromOffset(0, HEAD) }, 0.16)
					tween(tilt, { Rotation = slot:GetAttribute("Tilt") or 0 }, 0.16) -- back to its own angle
				end
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
		-- The tutorial points at a card's action plate (Client/Shop.lua, target myPatronDiscard). The plate is only drawn
		-- while the card is hovered or picked, so the walkthrough asks for it to stay open with this attribute.
		if button then
			button:GetAttributeChangedSignal("HoldOpen"):Connect(function()
				setPinned(button:GetAttribute("HoldOpen") == true)
			end)
		end
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
			elseif (spec.shortBy or 0) > 0 and enabled then
				-- not enough Tips: the card shakes sideways (the cue and Marlo's answer come from Shop.lua)
				local plan = require(game:GetService("ReplicatedStorage").Shared.Engine.ShopBuyUX).shake(ClientSettings.get("reduceShake") == true, slow())
				if plan then
					task.spawn(function()
						for _, dx in ipairs(plan.offsets) do
							if not body.Parent then return end
							tween(body, { Position = UDim2.fromOffset(dx, HEAD - LIFT) }, plan.step)
							task.wait(plan.step)
						end
					end)
				end
			end
		end)
		end

		return card
	end

	return self
end

return ShopCards
