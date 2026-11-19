--[[
	Client/PatronRow.lua
	The Patron Row: big painted Patron cards on the table, above the hand, between the dock icons and the cards.
	Rects come from the pure Engine/PatronRowLayout. Each card is the painted portrait inside its rarity frame with a
	name plaque under it; free seats are faint card-shaped slots (an inner outline and a small suit, no plus sign).
	On roots with room the row is the Patron display (PatronRowLayout.display): a "PATRONS" heading over five card slots on a
	quiet tray, with the Mult panel (Engine/PatronBoost.panel) to its right. A slow idle float (off in calm mode) and a hover
	tooltip with the effect text. Cosmetic only: nothing here sends anything to the server.

	  PatronRow.install{ root, handFrame, tooltip = fn(frame, textFn), getState = fn }   once, from the hub
	  PatronRow.update(state)       call after every render (owned Patrons, seat limit)
	  PatronRow.frameFor(patronId)  the card Body frame of an owned Patron, or nil (ScorePopup pulses it)
	  PatronRow.frames()            { [patronId] = Body } for every owned Patron
	  PatronRow.trigger(patronId, entry)   scoring beat for one Patron event (hop, glow, pill, dim the others)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local Engine = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine")
local Layout = require(Engine:WaitForChild("PatronRowLayout"))
local PlayBudget = require(Engine:WaitForChild("PlayBudget"))
local PatronEvents = require(Engine:WaitForChild("PatronEvents"))
local Rules = require(Engine:WaitForChild("PatronRowRules"))
local CollectionBook = require(Engine:WaitForChild("CollectionBook"))
local CTLayout = require(Engine:WaitForChild("ConceptTLayout"))
local NameFit = require(Engine:WaitForChild("PatronNameFit"))
local PatronPlaque = require(script.Parent.PatronPlaque)
local PatronValueText = require(Engine:WaitForChild("PatronValueText"))
local RarityFrame = require(script.Parent.RarityFrame)
local ClientSettings = require(script.Parent.ClientSettings)

local M = {}

local GOLD = Color3.fromRGB(222, 182, 104)
local WOOD = Color3.fromRGB(78, 52, 26)
local CREAM = Color3.fromRGB(240, 225, 190)
local SLOT = Color3.fromRGB(22, 14, 9)
local WALNUT = Color3.fromRGB(37, 23, 15)
local Z = 6

local holder, holderScale, rootRef, handRef, tooltipFn, anchorFn
local boost = { summary = nil, frame = nil } -- the Mult panel (built below): preview = selected cards, last = last scored hand
local placeBoost
local ctPlace = false -- the last place() ran for the Concept T screen
local ctPill = nil -- the small Chips x Mult preview pill of the Concept T screen
local cards = {} -- pool of { slot, float, body, art, name, plus, floatTween, id }
local lastState
local MAX_CARDS = 14

local function calm()
	local ok, v = pcall(function() return ClientSettings.get("reduceShake") end)
	return ok and v == true
end

-- Concept T hover or long press plate with synergy tags (Client/PatronTipFX); the old generic tooltip stays on other screens
local function tipActive()
	local ok, v = pcall(function() return require(script.Parent.ConceptTPlay).isActive() end)
	return ok and v == true
end

local TipTap = require(Engine:WaitForChild("TipTap"))
local tipTap = TipTap.new() -- which Patron plate a touch left open

local function hideTip()
	tipTap.open = nil
	pcall(function() require(script.Parent.PatronTipFX).hide() end)
end

local function touchOnly()
	local UIS = game:GetService("UserInputService")
	return UIS.TouchEnabled and not UIS.MouseEnabled
end

local function showTip(i, c)
	local owned = lastState and lastState.ownedPatrons and lastState.ownedPatrons[i]
	if not owned or not c.id or not tipActive() then return end
	local tier = "common"
	pcall(function() tier = CollectionBook.rarityForId("patrons", owned.id) or "common" end)
	pcall(function()
		require(script.Parent.PatronTipFX).show(rootRef, cards, i,
			{ id = owned.id, name = owned.name, description = owned.description, rarity = tier, value = c.valueText }, calm())
	end)
end

local function corner(parent, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = parent
end

local startFloat -- defined below (hover and entrance hand control back to it)

local function newCard(i)
	local c = { id = nil, seat = i }
	local slot = Instance.new("Frame")
	slot.Name = "PatronCard" .. i
	slot.BackgroundTransparency = 1
	slot.BorderSizePixel = 0
	slot.ZIndex = Z
	slot.Visible = false
	slot.Parent = holder
	local float = Instance.new("Frame")
	float.Name = "Float"
	float.BackgroundTransparency = 1
	float.Size = UDim2.fromScale(1, 1)
	float.ZIndex = Z
	float.Parent = slot
	local shadow = Instance.new("Frame") -- soft drop shadow, kept off the card so a pulse does not scale it
	shadow.Name = "Shadow"
	shadow.AnchorPoint = Vector2.new(0.5, 0)
	shadow.Position = UDim2.new(0.5, 0, 1, -6)
	shadow.Size = UDim2.new(0.9, 0, 0, 10)
	shadow.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	shadow.BackgroundTransparency = 0.6
	shadow.BorderSizePixel = 0
	shadow.ZIndex = Z - 1
	shadow.Active = false
	shadow.Parent = slot
	corner(shadow, 5)
	local body = Instance.new("Frame")
	body.Name = "Body"
	body.Size = UDim2.fromScale(1, 1)
	body.BackgroundColor3 = WOOD
	body.BorderSizePixel = 0
	body.ZIndex = Z
	body.Parent = float
	corner(body, 8)
	local plus = Instance.new("TextLabel") -- empty seat pip
	plus.Name = "Plus"
	plus.AnchorPoint = Vector2.new(0.5, 0.5)
	plus.Position = UDim2.fromScale(0.5, 0.5)
	plus.Size = UDim2.fromOffset(34, 34)
	plus.BackgroundColor3 = GOLD
	plus.BackgroundTransparency = 0.8
	plus.Font = Enum.Font.GothamBold
	plus.TextSize = 22
	plus.TextColor3 = CREAM
	plus.TextTransparency = 0.2
	plus.TextStrokeTransparency = 0.6
	plus.Text = "+"
	plus.ZIndex = Z + 1
	plus.Active = false
	plus.Parent = body
	corner(plus, 17)
	local mark = Instance.new("Frame") -- empty slot: a card outline with a faint suit, so it reads as a place for a card
	mark.Name = "EmptyMark"
	mark.Size = UDim2.fromScale(1, 1)
	mark.BackgroundTransparency = 1
	mark.ZIndex = Z + 1
	mark.Active = false
	mark.Visible = false
	mark.Parent = body
	corner(mark, 8)
	local markEdge = Instance.new("UIStroke")
	markEdge.Color = GOLD
	markEdge.Thickness = 1.5
	markEdge.Transparency = 0.5
	markEdge.Parent = mark
	local inner = Instance.new("Frame")
	inner.Name = "Inner"
	inner.AnchorPoint = Vector2.new(0.5, 0.5)
	inner.Position = UDim2.fromScale(0.5, 0.5)
	inner.Size = UDim2.new(1, -14, 1, -14)
	inner.BackgroundTransparency = 1
	inner.ZIndex = Z + 1
	inner.Active = false
	inner.Parent = mark
	corner(inner, 5)
	local innerEdge = Instance.new("UIStroke")
	innerEdge.Color = GOLD
	innerEdge.Thickness = 1
	innerEdge.Transparency = 0.75
	innerEdge.Parent = inner
	local suit = Instance.new("TextLabel")
	suit.Name = "Suit"
	suit.AnchorPoint = Vector2.new(0.5, 0.5)
	suit.Position = UDim2.fromScale(0.5, 0.5)
	suit.Size = UDim2.fromOffset(34, 34)
	suit.BackgroundTransparency = 1
	suit.Font = Enum.Font.GothamBold
	suit.TextSize = 26
	suit.TextColor3 = GOLD
	suit.TextTransparency = 0.72
	suit.TextStrokeTransparency = 1
	suit.Text = "♠"
	suit.ZIndex = Z + 1
	suit.Active = false
	suit.Parent = mark
	c.mark = mark
	local dim = Instance.new("Frame") -- dims the card while another Patron triggers
	dim.Name = "Dim"
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	dim.BackgroundTransparency = 1
	dim.BorderSizePixel = 0
	dim.ZIndex = Z + 5
	dim.Active = false
	dim.Parent = body
	corner(dim, 8)
	local ring = Instance.new("Frame") -- gold ring that flashes when the card triggers
	ring.Name = "GlowRing"
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromScale(0.5, 0.5)
	ring.Size = UDim2.new(1, 8, 1, 8)
	ring.BackgroundTransparency = 1
	ring.Active = false
	ring.ZIndex = Z + 6
	ring.Parent = body
	corner(ring, 12)
	local ringStroke = Instance.new("UIStroke")
	ringStroke.Color = GOLD
	ringStroke.Thickness = 4
	ringStroke.Transparency = 1
	ringStroke.Parent = ring
	local plaque = Instance.new("Frame")
	plaque.Name = "Plaque"
	plaque.Position = UDim2.new(0, 0, 1, 4)
	plaque.Size = UDim2.new(1, 0, 0, Layout.PLAQUE_H - 4)
	plaque.BackgroundColor3 = Color3.fromRGB(46, 30, 16)
	plaque.BackgroundTransparency = 0.1
	plaque.BorderSizePixel = 0
	plaque.ZIndex = Z + 2
	plaque.Active = false
	plaque.Parent = float
	corner(plaque, 5)
	local name = Instance.new("TextLabel")
	name.Name = "Name"
	name.Size = UDim2.new(1, -4, 1, 0) -- c.name is resized per card width in the layout loop (PatronNameFit)
	name.Position = UDim2.fromOffset(2, 0)
	name.BackgroundTransparency = 1
	name.Font = Enum.Font.GothamMedium
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextScaled = true -- shrinks to fit the remaining width, between 11 and 16 px
	name.TextSize = 15
	do
		local cons = Instance.new("UITextSizeConstraint")
		cons.MinTextSize, cons.MaxTextSize = NameFit.MIN_SIZE, NameFit.MAX_SIZE
		cons.Parent = name
	end
	name.TextColor3 = CREAM
	name.TextTransparency = 0
	name.TextStrokeTransparency = 1
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.ZIndex = Z + 3
	name.Active = false
	name.Parent = plaque
	local value = Instance.new("TextLabel") -- the real effect figure ("+4 Mult") on a dark strip at the foot of the portrait
	value.Name = "Value"
	value.AnchorPoint = Vector2.new(0.5, 1)
	value.Position = UDim2.new(0.5, 0, 1, -4)
	value.Size = UDim2.new(1, -8, 0, 20)
	value.BackgroundColor3 = Color3.fromRGB(30, 20, 11)
	value.BackgroundTransparency = 0.2
	value.BorderSizePixel = 0
	value.Font = Enum.Font.GothamBold
	value.TextSize = 15
	value.TextColor3 = GOLD
	value.TextTransparency = 0
	value.TextStrokeTransparency = 1
	value.TextTruncate = Enum.TextTruncate.AtEnd
	value.ZIndex = Z + 5
	value.Active = false
	value.Visible = false
	value.Parent = body
	corner(value, 4)
	c.value = value
	c.slot, c.float, c.body, c.name, c.plus, c.plaque, c.shadow = slot, float, body, name, plus, plaque, shadow
	c.dim, c.ringStroke = dim, ringStroke
	-- hover: an owned Patron's gold ring shows faintly (the scoring beat owns the ring while a card hops)
	c.afterMotion = function() if c.slot.Visible and not c.hovering and not c.floatTween then startFloat(c, 1) end end
	body.MouseEnter:Connect(function()
		if c.id and not c.hopping then ringStroke.Transparency = 0.45 end
		if c.id then pcall(function() require(script.Parent.PatronMotionFX).hover(c, true, calm()) end) end
		showTip(i, c)
	end)
	body.MouseLeave:Connect(function()
		hideTip()
		if not c.hopping then ringStroke.Transparency = 1 end
		if c.hovering then
			pcall(function() require(script.Parent.PatronMotionFX).hover(c, false, calm()) end)
			if not calm() then task.delay(0.15, function() if not c.hovering then startFloat(c, 1) end end) end
		end
	end)
	-- touch: holding the card 0.35 s lifts it and shows the tooltip (Engine/TouchGestures); letting go hides it
	pcall(function()
		require(script.Parent.HandTouchFX).press(body, function()
			if not c.id then return end
			pcall(function() require(script.Parent.PatronMotionFX).hover(c, true, calm()) end)
			showTip(i, c)
		end, function()
			-- touch: the plate stays open after a long press; a tap on the card or away from it closes it (Engine/TipTap)
			if touchOnly() then TipTap.longPress(tipTap, i) return end
			hideTip()
			if c.hovering then pcall(function() require(script.Parent.PatronMotionFX).hover(c, false, calm()) end) end
		end)
	end)
	-- touch: a quick tap on an owned Patron opens its plate, another tap on it closes it; a tap anywhere else closes it
	pcall(function()
		if not tipTap.awayHooked then
			tipTap.awayHooked = true
			game:GetService("UserInputService").InputBegan:Connect(function(input)
				if input.UserInputType ~= Enum.UserInputType.Touch or not tipTap.open then return end
				local card = cards[tipTap.open]
				local rect
				if card and card.body and card.body.Parent then
					local p, s = card.body.AbsolutePosition, card.body.AbsoluteSize
					rect = { x = p.X, y = p.Y, w = s.X, h = s.Y }
				end
				-- InputObject.Position is in the same space as AbsolutePosition (the inset is not added)
				if TipTap.tapAway(tipTap, input.Position.X, input.Position.Y, rect) then hideTip() end
			end)
		end
		local down
		body.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Touch then down = { pos = input.Position, at = os.clock() } end
		end)
		body.InputEnded:Connect(function(input)
			if input.UserInputType ~= Enum.UserInputType.Touch or not down then return end
			local d, held = (input.Position - down.pos).Magnitude, os.clock() - down.at
			down = nil
			if not c.id or not TipTap.isTap(d, held) then return end
			if TipTap.tapCard(tipTap, i) == "open" then showTip(i, c) else hideTip() end
		end)
	end)
	if tooltipFn then
		tooltipFn(body, function()
			local owned = lastState and lastState.ownedPatrons and lastState.ownedPatrons[i]
			if owned and tipActive() then return "" end -- the Concept T plate (PatronTipFX) carries the text
			if owned then return string.format("%s\n%s", owned.name, owned.description) end
			return require(Engine:WaitForChild("EmptyStates")).hint("seat")
		end)
	end
	return c
end

function startFloat(c, i)
	if c.floatTween then c.floatTween:Cancel(); c.floatTween = nil end
	c.float.Position = UDim2.fromOffset(0, 0)
	if calm() or c.hopping or c.hovering then return end
	local t = TweenService:Create(c.float, TweenInfo.new(3, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Position = UDim2.fromOffset(0, -2) })
	-- stagger so the row does not bob as one block
	task.delay((i % 5) * 0.4, function() if c.floatTween == nil and c.slot.Visible and not c.hopping and not c.hovering then c.floatTween = t; t:Play() end end)
end

local function fillCard(c, i, owned)
	if owned then
		c.plus.Visible = false
		c.mark.Visible = false
		local ro = c.body:FindFirstChild("RarityOrnaments")
		if ro then ro.Visible = true end
		local rs0 = c.body:FindFirstChild("RarityStroke")
		if rs0 then rs0.Enabled = true end
		c.plaque.Visible = true
		c.name.Text = owned.name
		c.valueText = PatronValueText.of(owned.description)
		c.body.BackgroundTransparency = 0
		c.body.BackgroundColor3 = WOOD
		if c.id ~= owned.id then
			c.enterPending = require(Engine:WaitForChild("PatronMotion")).isNew(c.id, owned.id)
			c.id = owned.id
			local old = c.body:FindFirstChild("PatronArt")
			if old then old:Destroy() end
			local art = PatronPlaque.apply(c.body, owned.id, { cornerRadius = 8, zIndex = Z + 1 })
			if not art then -- no painted portrait yet: the first letter stands in
				c.plus.Visible = true
				c.plus.Text = owned.name:sub(1, 1)
				c.plus.BackgroundTransparency = 0.6
			end
		end
		local tier = "common"
		pcall(function() tier = CollectionBook.rarityForId("patrons", owned.id) or "common" end)
		local cut = c.body:FindFirstChild("PatronArt")
		cut = cut ~= nil and cut:GetAttribute("ConceptTCard") == true
		if not cut then -- a Concept T cut card carries its own rarity frame and name plate
			pcall(function() RarityFrame.apply(c.body, tier, { thickness = 3, radius = 8, zIndex = Z + 4 }) end)
		end
		pcall(function() require(script.Parent.ConceptTPatronCard).set(c.slot, tier, c.valueText, cut) end)
		pcall(function() require(script.Parent.PatronShineFX).sync(c, tier, calm(), c.seat or 1) end)
		if c.enterPending then
			c.enterPending = false
			pcall(function() require(script.Parent.PatronMotionFX).enter(c, tier, calm()) end)
		end
		if cut then
			c.plaque.Visible = false
			c.body.BackgroundTransparency = 1 -- the cut card has its own frame: no dark slot panel behind it
			local rs1 = c.body:FindFirstChild("RarityStroke")
			if rs1 then rs1.Enabled = false end
			local ro1 = c.body:FindFirstChild("RarityOrnaments")
			if ro1 then ro1.Visible = false end
		end
	else
		pcall(function() require(script.Parent.ConceptTPatronCard).set(c.slot, "common", nil, false) end)
		pcall(function() require(script.Parent.PatronShineFX).clear(c) end)
		c.id = nil
		local old = c.body:FindFirstChild("PatronArt")
		if old then old:Destroy() end
		c.plus.Visible = false -- no plus sign: the card outline says "a Patron goes here"
		c.mark.Visible = true
		c.plaque.Visible = false
		c.valueText = nil
		c.value.Visible = false
		c.body.BackgroundColor3 = SLOT
		c.body.BackgroundTransparency = 0.45 -- quiet slot
		local rs = c.body:FindFirstChild("RarityStroke")
		if rs then rs.Enabled = false end
		local ro = c.body:FindFirstChild("RarityOrnaments")
		if ro then ro.Visible = false end
	end
end

-- ===== the Nook: ledge, back panel, lantern glow, alcoves (code-drawn, rects from PatronRowLayout.nook) =====
local nook -- { root, back, glow, ledge, trim, rivets, alcoves }

local NOOK_BACK = Color3.fromRGB(34, 22, 14)
local NOOK_ALCOVE = Color3.fromRGB(22, 14, 9)
local HEAD_TEXT_W = 96

local function nookFrame(parent, name, z, color, tr)
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundColor3 = color
	f.BackgroundTransparency = tr or 0
	f.BorderSizePixel = 0
	f.ZIndex = z
	f.Active = false
	f.Parent = parent
	return f
end

local function buildNook()
	local root = Instance.new("Frame")
	root.Name = "Nook"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromScale(1, 1)
	root.ZIndex = Z - 4
	root.Active = false
	root.Parent = holder
	local back = nookFrame(root, "Back", Z - 4, NOOK_BACK)
	corner(back, 8)
	local glow = nookFrame(root, "Glow", Z - 3, NOOK_BACK) -- warm lantern light: ONE frame, Color stops only
	local warm, keys = Color3.fromRGB(150, 98, 40), {}
	for i = 0, 13 do
		local t = i / 13
		keys[#keys + 1] = ColorSequenceKeypoint.new(t, NOOK_BACK:Lerp(warm, (1 - t) ^ 2))
	end
	local gg = Instance.new("UIGradient")
	gg.Rotation = 90
	gg.Color = ColorSequence.new(keys)
	gg.Parent = glow
	local ledge = nookFrame(root, "Ledge", Z - 1, Color3.fromRGB(88, 58, 30))
	local lg = Instance.new("UIGradient") -- wood grain, light to dark, Color only
	lg.Rotation = 90
	lg.Color = ColorSequence.new(Color3.fromRGB(112, 76, 40), Color3.fromRGB(66, 43, 22))
	lg.Parent = ledge
	local trim = nookFrame(root, "Trim", Z, GOLD)
	local rivets = {}
	for i = 1, 2 do
		rivets[i] = nookFrame(root, "Rivet" .. i, Z, GOLD)
		corner(rivets[i], 4)
	end
	local trayEdge = Instance.new("UIStroke") -- only drawn for the Patron display's tray
	trayEdge.Name = "TrayEdge"
	trayEdge.Color = GOLD
	trayEdge.Thickness = 1
	trayEdge.Transparency = 1
	trayEdge.Parent = back
	local head = Instance.new("Frame") -- "PATRONS" between two brass rules
	head.Name = "Heading"
	head.BackgroundTransparency = 1
	head.ZIndex = Z - 2
	head.Active = false
	head.Visible = false
	head.Parent = root
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.AnchorPoint = Vector2.new(0.5, 0.5)
	title.Position = UDim2.new(0.5, 0, 0.5, 1)
	title.Size = UDim2.fromOffset(HEAD_TEXT_W, 22)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.Fondamento
	title.TextSize = 19
	title.TextColor3 = GOLD
	title.TextTransparency = 0
	title.TextStrokeTransparency = 1
	title.Text = "PATRONS"
	title.ZIndex = Z - 2
	title.Active = false
	title.Parent = head
	for _, side in ipairs({ 0, 1 }) do
		local rule = nookFrame(head, side == 0 and "RuleL" or "RuleR", Z - 2, GOLD, 0.55)
		rule.AnchorPoint = Vector2.new(side, 0.5)
		rule.Position = UDim2.new(side, side == 0 and 14 or -14, 0.5, 1)
		rule.Size = UDim2.new(0.5, -(HEAD_TEXT_W / 2 + 22), 0, 1)
	end
	nook = { root = root, back = back, glow = glow, ledge = ledge, trim = trim, rivets = rivets, alcoves = {}, head = head, trayEdge = trayEdge }
end

-- The Patron display (lay.display): heading and a quiet tray, none of the shelf pieces.
local function placeDisplay(lay)
	if nook.paint then nook.paint.Visible = false end
	for _, k in ipairs({ "glow", "ledge", "trim" }) do nook[k].Visible = false end
	for _, r in ipairs(nook.rivets) do r.Visible = false end
	for _, a in ipairs(nook.alcoves) do a.Visible = false end
	nook.back.Visible = true
	nook.back.BackgroundColor3 = WALNUT
	nook.back.BackgroundTransparency = 0.35
	nook.trayEdge.Transparency = 0.55
	nook.back.Position = UDim2.fromOffset(lay.tray.x, lay.tray.y)
	nook.back.Size = UDim2.fromOffset(lay.tray.w, lay.tray.h)
	nook.head.Visible = lay.head ~= nil -- given up when the room is short (a Boss Round's home sits where it would be)
	if lay.head then
		nook.head.Position = UDim2.fromOffset(lay.head.x, lay.head.y)
		nook.head.Size = UDim2.fromOffset(lay.head.w, lay.head.h)
	end
	nook.lastBack = lay.tray
	nook.display = true
end

local function setRect(f, r)
	f.Position = UDim2.fromOffset(r.x, r.y)
	f.Size = UDim2.fromOffset(r.w, r.h)
end

local function buildAlcove(i)
	local f = nookFrame(nook.root, "Alcove" .. i, Z - 2, NOOK_ALCOVE, 0.25)
	corner(f, 8)
	local st = Instance.new("UIStroke")
	st.Color = GOLD
	st.Thickness = 1
	st.Transparency = 0.7
	st.Parent = f
	local pip = Instance.new("TextLabel") -- faint brass number pip
	pip.Name = "Pip"
	pip.Size = UDim2.fromOffset(20, 20)
	pip.Position = UDim2.fromOffset(4, 4)
	pip.BackgroundColor3 = GOLD
	pip.BackgroundTransparency = 0.75
	pip.Font = Enum.Font.GothamBold
	pip.TextSize = 15
	pip.TextColor3 = CREAM
	pip.TextTransparency = 0.25
	pip.TextStrokeTransparency = 1
	pip.Text = tostring(i)
	pip.ZIndex = Z - 1
	pip.Active = false
	pip.Parent = f
	corner(pip, 10)
	return f
end

-- Painted strip (play_nook_strip_b): replaces the back panel, glow, ledge, trim and rivets once its Image id exists.
local function paintedId()
	local ok, art = pcall(function() return require(Engine:WaitForChild("PlaySceneArt")) end)
	local id = ok and type(art) == "table" and art.play_nook_strip_b or nil
	if id and id ~= "" then return id end
	return nil
end

local function placePainted(strip)
	local id = strip and paintedId()
	if not id then
		if nook.paint then nook.paint.Visible = false end
		for _, k in ipairs({ "back", "glow", "ledge", "trim" }) do nook[k].Visible = true end
		for _, r in ipairs(nook.rivets) do r.Visible = true end
		return false
	end
	if not nook.paint then
		local img = Instance.new("ImageLabel")
		img.Name = "NookPaint"
		img.BackgroundTransparency = 1
		img.BorderSizePixel = 0
		img.Active = false
		img.ZIndex = Z - 4
		img.ScaleType = Enum.ScaleType.Stretch -- the rect already has the picture's aspect
		img.Parent = nook.root
		nook.paint = img
	end
	local img = nook.paint
	img.Image = id
	img.Visible = true
	setRect(img, strip)
	for _, k in ipairs({ "back", "glow", "ledge", "trim" }) do nook[k].Visible = false end
	for _, r in ipairs(nook.rivets) do r.Visible = false end
	return true
end

local function placeNook(lay, rootW, hand, owned, opts)
	if not lay then
		if nook then nook.root.Visible = false end
		return
	end
	if not nook then buildNook() end
	if lay.display then
		nook.root.Visible = true
		placeDisplay(lay)
		return
	end
	nook.display = false
	nook.head.Visible = false
	nook.trayEdge.Transparency = 1
	nook.back.BackgroundColor3 = NOOK_BACK
	nook.back.BackgroundTransparency = 0
	local nk = Layout.nook(lay, rootW, hand, opts)
	nook.root.Visible = nk ~= nil
	if not nk then return end
	setRect(nook.back, nk.back)
	setRect(nook.glow, nk.glow)
	setRect(nook.ledge, nk.ledge)
	setRect(nook.trim, nk.trim)
	for i, r in ipairs(nk.rivets) do
		nook.rivets[i].Position = UDim2.fromOffset(r.x, r.y)
		nook.rivets[i].Size = UDim2.fromOffset(Layout.RIVET, Layout.RIVET)
	end
	local painted = placePainted(lay.strip)
	nook.lastBack = nk.back
	for i = 1, math.max(#nk.alcoves, #nook.alcoves) do
		local r = nk.alcoves[i]
		if r and not nook.alcoves[i] then nook.alcoves[i] = buildAlcove(i) end
		local a = nook.alcoves[i]
		if a then
			a.Visible = r ~= nil and not painted -- the picture has its own alcoves
			if r then
				setRect(a, r)
				a.Pip.Visible = owned[i] == nil
			end
		end
	end
end

-- Product of every UIScale on this object and its GuiObject ancestors (1 on a normal screen).
local function uiScaleOf(inst)
	local k = 1
	while inst and inst:IsA("GuiBase2d") do
		for _, c in ipairs(inst:GetChildren()) do
			if c:IsA("UIScale") then k = k * c.Scale end
		end
		inst = inst.Parent
	end
	return math.max(k, 0.05)
end

-- The boss's home (Client/BossFight.lua: medallion and name plate in the top strip) reaches down into the top of the
-- nook. While it shows, the Patron display starts under it instead of behind it. Returns the home's bottom edge in
-- root pixels, or nil when no boss home is showing.
local BOSS_AIR = 4
local bossHooked = false
local placeAgain
local function bossHomeBottom()
	local host = rootRef:FindFirstChild("BossFightHost")
	if not host then return nil end
	if not bossHooked then
		bossHooked = true
		host:GetPropertyChangedSignal("Visible"):Connect(function() if placeAgain then placeAgain() end end)
		host:GetAttributeChangedSignal("HomeOk"):Connect(function() if placeAgain then placeAgain() end end)
	end
	if not host.Visible then return nil end
	if host:GetAttribute("HomeOk") == true then
		return require(Engine:WaitForChild("BossHomeLayout")).BOTTOM_LIMIT
	end
	return 60 -- the narrow-strip fallback: a centred 50 px plate from y 10
end

local function place(state)
	if not holder then return end
	state = state or lastState
	local owned = state and state.ownedPatrons or {}
	local limit = math.min(state and state.patronSlotLimit or #owned, MAX_CARDS)
	limit = math.max(limit, #owned)
	limit = math.min(limit, MAX_CARDS)
	local panelOpen = false
	pcall(function() panelOpen = not require(script.Parent.CornerDock).isShown() end) -- same live answer as the corner dock
	local show = Rules.visible({ phase = state and state.phase, rootVisible = rootRef.Visible, handVisible = handRef.Visible,
		panelOpen = panelOpen, seats = limit })
	holder.Visible = show
	local k = uiScaleOf(rootRef) -- Studio scale:WxH puts a UIScale on the root; measurements below are absolute, so the holder cancels it
	holder.Size = UDim2.fromScale(k, k)
	holderScale.Scale = 1 / k
	local rootSize = rootRef.AbsoluteSize
	local hand = {
		x = handRef.AbsolutePosition.X - rootRef.AbsolutePosition.X,
		y = handRef.AbsolutePosition.Y - rootRef.AbsolutePosition.Y,
		w = handRef.AbsoluteSize.X, h = handRef.AbsoluteSize.Y,
	}
	local lay = nil
	local budgetH, budgetTop = PlayBudget.nookMax(rootSize.X / k, rootSize.Y / k)
	local opts = { topLimit = budgetTop * k, maxStripH = budgetH * k, maxCardH = 100 * PlayBudget.scale(rootSize.X / k, rootSize.Y / k) * k } -- one vertical budget (Engine/PlayBudget): a slim nook
	local bossBottom = show and bossHomeBottom() or nil
	if bossBottom and bossBottom + BOSS_AIR > opts.topLimit then -- a Boss Round: start under the boss's home, inside what is left of the budget
		opts.maxStripH = opts.maxStripH - (bossBottom + BOSS_AIR - opts.topLimit)
		opts.topLimit = bossBottom + BOSS_AIR
	end
	if show and rootSize.X < 1200 then -- narrow roots: keep the row right of the left board, never over its portrait
		local sb = rootRef:FindFirstChild("Sidebar")
		if sb and sb.Visible then
			opts.leftLimit = sb.AbsolutePosition.X - rootRef.AbsolutePosition.X + sb.AbsoluteSize.X + 8
		end
	end
	local ctOn = false
	if show then pcall(function() ctOn = require(script.Parent.ConceptTPlay).isActive() end) end
	ctPlace = ctOn
	if show and ctOn then
		-- Concept T play screen: five cards on the painted rug, no panel, nook or Mult panel (rects: Engine/ConceptTLayout.patronRow)
		local v2 = false
		pcall(function() v2 = require(script.Parent.Gameplay2).isActive() end)
		local row = v2 and require(Engine:WaitForChild("Gameplay2Layout")).patronRow(rootSize.X, rootSize.Y, limit) or CTLayout.patronRow(rootSize.X, rootSize.Y, limit)
		lay = { cards = row.cards, plaqueH = 20 }
	elseif show then
		-- the Patron display first (card slots under a heading); the painted strip and the code nook are the fallbacks for roots it declines
		lay = Layout.wrapped(rootSize.X, rootSize.Y, hand, limit, opts) or Layout.display(rootSize.X, rootSize.Y, hand, limit, opts)
			or (paintedId() and Layout.painted(rootSize.X, rootSize.Y, hand, limit, opts)) or Layout.compute(rootSize.X, rootSize.Y, hand, limit, opts)
	end
	holder.Visible = lay ~= nil
	if k ~= 1 and RunService:IsStudio() then
		local r1 = lay and lay.cards[1]
		print(string.format("[PatronRow] scaled root k=%.2f root=%dx%d leftLimit=%s card1=%s", k, math.floor(rootSize.X), math.floor(rootSize.Y),
			tostring(opts and opts.leftLimit), r1 and (math.floor(r1.x) .. "," .. math.floor(r1.y) .. " " .. math.floor(r1.w) .. "x" .. math.floor(r1.h)) or "none"))
	end
	placeNook(ctOn and nil or lay, rootSize.X, hand, owned, opts)
	if #owned == 0 then boost.summary = nil end
	if state and (state.roundScore or 0) == 0 and state.handsRemaining == state.roundStartHands then boost.last = nil end -- a fresh round has no last hand
	boost.cardsY = lay and lay.display and lay.rect.y or nil
	placeBoost((not ctOn) and lay and nook and nook.lastBack or nil, rootSize.X / k)
	M.placePill()
	for i = 1, MAX_CARDS do
		local c = cards[i]
		if not c and lay and i <= limit then c = newCard(i); cards[i] = c end
		if c then
			local r = lay and lay.cards[i]
			if r then
				c.slot.Visible = true
				c.slot.Position = UDim2.fromOffset(r.x, r.y)
				c.slot.Size = UDim2.fromOffset(r.w, r.h)
				local nr = NameFit.rect(r.w) -- the power disc covers the strip's right end: the name keeps clear of it
				c.name.Position = UDim2.fromOffset(nr.x, 0)
				c.name.Size = UDim2.new(0, nr.w, 1, 0)
				if game:GetService("RunService"):IsStudio() and c.name.Text ~= "" and c.name.TextBounds.X > nr.w + 1 then
					warn(string.format("[PatronRow] name '%s' is %d px wide in a %d px strip", c.name.Text, math.floor(c.name.TextBounds.X), nr.w))
				end
				c.slot.ZIndex = Z + i -- later cards overlap earlier ones
				fillCard(c, i, owned[i])
				if c.value then
					c.value.Text = c.valueText or ""
					c.value.Visible = (c.valueText ~= nil) and PatronValueText.visible(r.w)
				end
				local ctl = c.slot:FindFirstChild("CTLabel")
				if ctl and ctl.Visible and c.value then c.value.Visible = false end -- the Concept T effect pill shows the value
				if c.value and c.slot:FindFirstChild("TierDeco") and c.slot.TierDeco.Visible then c.value.Visible = false end -- Gameplay v2: the disc has the number, the pill the unit, no loose string
				if lay.plaqueH <= 0 then c.plaque.Visible = false end -- narrow cards: the tooltip carries the name
				if not c.floatTween and not c.hopping and not c.hovering then startFloat(c, i) end
			else
				c.slot.Visible = false
				if c.floatTween then c.floatTween:Cancel(); c.floatTween = nil end
			end
		end
	end
end

-- ===== Mult panel: the real Mult of the selected cards (the hub's hand preview), else of the last scored hand (Engine/PatronBoost.panel) =====
local function buildBoost()
	local f = Instance.new("Frame")
	f.Name = "PatronBoostPanel"
	f.BackgroundColor3 = WALNUT
	f.BackgroundTransparency = 0.08
	f.BorderSizePixel = 0
	f.ZIndex = Z + 1
	f.Active = false
	f.Visible = false
	f.Parent = holder
	corner(f, 8)
	local st = Instance.new("UIStroke")
	st.Color = GOLD
	st.Thickness = 2
	st.Parent = f
	local function label(name, y, h, size, color, font)
		local l = Instance.new("TextLabel")
		l.Name = name
		l.Position = UDim2.fromOffset(8, y)
		l.Size = UDim2.new(1, -16, 0, h)
		l.BackgroundTransparency = 1
		l.Font = font or Enum.Font.GothamBold
		l.TextSize = size
		l.TextColor3 = color
		l.TextTransparency = 0
		l.TextStrokeTransparency = 1
		l.TextWrapped = true
		l.ZIndex = Z + 2
		l.Active = false
		l.Parent = f
		return l
	end
	boost.label = label("Label", 7, 18, 15, CREAM)
	boost.value = label("Value", 26, 40, 36, GOLD, Enum.Font.Fondamento)
	boost.valueScale = Instance.new("UIScale")
	boost.valueScale.Parent = boost.value
	local rule = Instance.new("Frame")
	rule.Name = "Rule"
	rule.AnchorPoint = Vector2.new(0.5, 0)
	rule.Position = UDim2.new(0.5, 0, 0, 68)
	rule.Size = UDim2.new(1, -36, 0, 1)
	rule.BackgroundColor3 = GOLD
	rule.BackgroundTransparency = 0.55
	rule.BorderSizePixel = 0
	rule.ZIndex = Z + 2
	rule.Active = false
	rule.Parent = f
	boost.rule = rule
	boost.line = label("Line", 71, 36, 15, CREAM)
	boost.frame = f
	return f
end

-- The corner icon row's rectangle in the root (nil before its first layout). The Mult panel keeps clear of it
-- (Engine/PatronBoost.placePanel). The row gets its width a moment after it is built and changes it when an icon comes
-- or goes, so the panel is placed again when that happens.
local watchedDock = nil
local function dockRect()
	local row = rootRef and rootRef:FindFirstChild("CornerIconRow")
	if not row then return nil end
	if row ~= watchedDock then
		watchedDock = row
		row:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			if holder and nook then pcall(placeBoost, holder.Visible and nook.lastBack or nil, rootRef.AbsoluteSize.X / uiScaleOf(rootRef)) end
		end)
	end
	if row.AbsoluteSize.X <= 0 then return nil end
	return {
		x = row.AbsolutePosition.X - rootRef.AbsolutePosition.X, y = row.AbsolutePosition.Y - rootRef.AbsolutePosition.Y,
		w = row.AbsoluteSize.X, h = row.AbsoluteSize.Y,
	}
end

function placeBoost(back, rootW)
	local PatronBoost = require(Engine:WaitForChild("PatronBoost"))
	local r = back and PatronBoost.placePanel(back, boost.cardsY, rootW, dockRect()) or nil
	if not r then
		if boost.frame then boost.frame.Visible = false end
		return
	end
	local f = boost.frame or buildBoost()
	f.Position = UDim2.fromOffset(r.x, r.y)
	f.Size = UDim2.fromOffset(r.w, r.h)
	local m = PatronBoost.panel(boost.preview, boost.last)
	boost.label.Text = m.label
	boost.value.Text = m.value or ""
	boost.value.Visible = m.value ~= nil
	boost.rule.Visible = m.value ~= nil
	boost.line.Text = m.line
	-- a compact panel (a short screen: it stands below the corner icons) has no label row; the rest moves up by it
	local up = r.compact and PatronBoost.LABEL_H or 0
	boost.label.Visible = not r.compact
	boost.value.Position = UDim2.fromOffset(8, 26 - up)
	boost.rule.Position = UDim2.new(0.5, 0, 0, 68 - up)
	boost.line.Position = UDim2.fromOffset(8, m.value and (71 - up) or (r.compact and 28 or 40)) -- no figure yet: the hint sits in the middle of the panel
	if m.value ~= boost.shown then
		boost.shown = m.value
		if m.value and not calm() then -- a short pop when the figure changes (never in calm mode)
			boost.valueScale.Scale = 1.14
			TweenService:Create(boost.valueScale, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		else
			boost.valueScale.Scale = 1
		end
	end
	f.Visible = true
end

-- Concept T screen: the Mult panel is replaced by one small pill, "<chips> Chips x <mult> Mult", between the Patron pills and
-- the scoring stage; shown only while the selected cards (or the last hand) give a figure. No tween, so Calm mode is the same.
function M.placePill()
	if not (holder and rootRef) then return end
	local m = require(Engine:WaitForChild("PatronBoost")).panel(boost.preview, boost.last)
	local v2 = false
	pcall(function() v2 = require(script.Parent.Gameplay2).isActive() end)
	-- the v2 table has its own PreviewPill (Gameplay2); a second box here would sit on the centre score
	local on = ctPlace and (not v2) and holder.Visible and m.value ~= nil
	if not on then
		if ctPill then ctPill.Visible = false end
		return
	end
	local size = rootRef.AbsoluteSize
	local r = CTLayout.previewRect(size.X, size.Y)
	if not ctPill then
		ctPill = Instance.new("Frame")
		ctPill.Name = "CTPreviewPill"
		ctPill.BackgroundColor3 = WALNUT
		ctPill.BackgroundTransparency = 0.1
		ctPill.BorderSizePixel = 0
		ctPill.ZIndex = Z + 3
		ctPill.Active = false
		ctPill.Parent = holder
		corner(ctPill, 10)
		local st = Instance.new("UIStroke")
		st.Color = GOLD
		st.Thickness = 2
		st.Parent = ctPill
		local t = Instance.new("TextLabel")
		t.Name = "Text"
		t.Size = UDim2.fromScale(1, 1)
		t.BackgroundTransparency = 1
		t.Font = Enum.Font.GothamBold
		t.TextColor3 = CREAM
		t.TextTransparency = 0
		t.TextStrokeTransparency = 1
		t.ZIndex = Z + 4
		t.Active = false
		t.Parent = ctPill
	end
	ctPill.Position = UDim2.fromOffset(r.x, r.y)
	ctPill.Size = UDim2.fromOffset(r.w, r.h)
	local t = ctPill.Text
	t.TextSize = math.max(15, math.floor(r.h * 0.55))
	t.Text = (m.line:match("([^\n]+)$")) or ""
	ctPill.Visible = true
end

local function refreshBoost()
	if holder and nook then pcall(placeBoost, (not ctPlace) and holder.Visible and nook.lastBack or nil, rootRef.AbsoluteSize.X / uiScaleOf(rootRef)) end
	pcall(M.placePill)
end

-- ScorePopup passes PatronBoost.summary(breakdown) once a hand has scored (kept for callers; the panel reads setLast)
function M.setBoost(summary)
	boost.summary = summary
end

-- ScorePopup passes PatronBoost.totals(breakdown) once a hand has scored: { chips, mult } of that hand
function M.setLast(totals)
	boost.last = totals
	refreshBoost()
end

-- The hub passes its live hand preview (computeHandPreview) whenever the selection changes; nil when nothing previewable is selected
function M.setPreview(preview)
	boost.preview = preview and { chips = preview.chips, mult = preview.mult } or nil
	refreshBoost()
end

-- The Mult panel's rect in root pixels while it shows, else nil (Client/CornerToast starts its column under it).
function M.panelRect()
	local f = boost.frame
	if not (f and f.Visible and holder and holder.Visible) then return nil end
	local at, size, origin = f.AbsolutePosition, f.AbsoluteSize, rootRef.AbsolutePosition
	return { x = at.X - origin.X, y = at.Y - origin.Y, w = size.X, h = size.Y }
end

function M.install(deps)
	if holder then return end
	rootRef, handRef, tooltipFn, anchorFn = deps.root, deps.handFrame, deps.tooltip, deps.tavernAnchor
	holder = Instance.new("Frame")
	holder.Name = "PatronRow"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromScale(1, 1)
	holder.ZIndex = Z
	holder.Active = false
	holder.Visible = false
	holder.Parent = rootRef
	holderScale = Instance.new("UIScale")
	holderScale.Name = "AbsoluteUnits"
	holderScale.Parent = holder
	local function again() pcall(place) end
	placeAgain = again
	for _, prop in ipairs({ "AbsoluteSize", "AbsolutePosition", "Visible" }) do
		handRef:GetPropertyChangedSignal(prop):Connect(again)
	end
	rootRef:GetPropertyChangedSignal("AbsoluteSize"):Connect(again)
end

function M.update(state)
	lastState = state
	if not holder then return end
	local ok, err = pcall(place, state)
	if not ok and RunService:IsStudio() then warn("[PatronRow] " .. tostring(err)) end
end

-- CornerDock calls this when a page opens or closes, so the row follows the same live answer
function M.refresh()
	if holder then pcall(place) end
end

function M.frames()
	local out = {}
	local owned = lastState and lastState.ownedPatrons or {}
	for i, p in ipairs(owned) do
		local c = cards[i]
		if c and c.slot.Visible then out[p.id] = c.body end
	end
	return out
end

-- lowest screen Y of the visible row (cards and nook ledge), or nil when no row shows: played cards land below this
function M.bottomEdge()
	if not holder or not holder.Visible then return nil end
	local low
	for _, body in pairs(M.frames()) do
		local y = body.AbsolutePosition.Y + body.AbsoluteSize.Y
		if not low or y > low then low = y end
	end
	if nook and nook.display and nook.back.Visible then
		low = math.max(low or 0, nook.back.AbsolutePosition.Y + nook.back.AbsoluteSize.Y) -- the display's tray, plaques included
	elseif nook and nook.ledge and nook.ledge.Visible then
		-- also with no Patron owned yet: the empty nook still stands there, so the score readout must stay below it
		low = math.max(low or 0, nook.ledge.AbsolutePosition.Y + nook.ledge.AbsoluteSize.Y)
	end
	if not low then low = holder.AbsolutePosition.Y + holder.AbsoluteSize.Y end
	return low
end

function M.frameFor(patronId)
	return M.frames()[patronId]
end

-- A hovered card whose MouseLeave never came (a panel opened over it) lets go once the cursor is no longer on it.
function M.releaseStaleHover()
	local UIS, GuiService = game:GetService("UserInputService"), game:GetService("GuiService")
	if UIS.TouchEnabled and not UIS.MouseEnabled then return end -- touch holds end on release
	local m = UIS:GetMouseLocation() - GuiService:GetGuiInset()
	for _, c in ipairs(cards) do
		if c.hovering and c.body and c.body.Parent then
			local p, s = c.body.AbsolutePosition, c.body.AbsoluteSize
			if m.X < p.X or m.Y < p.Y or m.X > p.X + s.X or m.Y > p.Y + s.Y then
				pcall(function() require(script.Parent.PatronMotionFX).hover(c, false, calm()) end)
				hideTip()
			end
		end
	end
end

function M.cardOf(patronId)
	local owned = lastState and lastState.ownedPatrons or {}
	for i, p in ipairs(owned) do
		if p.id == patronId then return cards[i] end
	end
	return nil
end

-- ===== scoring beats =====
local KIND_COLOR = {
	chips = Color3.fromRGB(120, 175, 255),
	mult = Color3.fromRGB(255, 118, 104),
	xmult = Color3.fromRGB(255, 96, 84),
	money = Color3.fromRGB(246, 206, 112),
}
local dimToken = 0

local function tween(obj, info, goal)
	local t = TweenService:Create(obj, info, goal)
	t:Play()
	return t
end

local function pill(parent, text, color, size, bold, x, y, rise, hold, frozen, rim)
	local p = Instance.new("TextLabel")
	p.AnchorPoint = Vector2.new(0.5, 1)
	p.Position = UDim2.fromOffset(x, y)
	p.AutomaticSize = Enum.AutomaticSize.X
	p.Size = UDim2.fromOffset(0, size + 12)
	p.BackgroundColor3 = Color3.fromRGB(28, 18, 10)
	p.BackgroundTransparency = 0.12
	p.BorderSizePixel = 0
	p.Font = bold and Enum.Font.GothamBlack or Enum.Font.GothamBold
	p.TextSize = size
	p.TextColor3 = color
	p.TextTransparency = 0
	p.TextStrokeTransparency = 1
	p.Text = "  " .. text .. "  "
	p.ZIndex = Z + 40
	p.Active = false
	p.Parent = parent
	corner(p, (size + 12) / 2)
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = rim or color
	stroke.Thickness = rim and 2.5 or 1.5
	stroke.Transparency = 0.2
	stroke.Parent = p
	local sc = Instance.new("UIScale")
	sc.Scale = calm() and 1 or 0.5
	sc.Parent = p
	if not calm() then
		tween(sc, TweenInfo.new(0.14, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
	end
	task.delay(hold or 0.55, function()
		while frozen and frozen() and p.Parent do task.wait(0.1) end -- Studio beatslow:freeze
		if not p.Parent then return end
		local info = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		if not calm() then tween(p, info, { Position = UDim2.fromOffset(x, y - rise) }) end
		tween(p, info, { TextTransparency = 1, BackgroundTransparency = 1 })
		tween(stroke, info, { Transparency = 1 })
		task.delay(0.4, function() if p.Parent then p:Destroy() end end)
	end)
	return p
end

-- Round clear: every owned Patron hops 8 px in order, 0.12 s apart (Engine/Celebration; nothing in Calm mode)
function M.celebrate()
	local Cel = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("Celebration"))
	for i, c in ipairs(cards) do
		local delay = c.id and Cel.patronHopDelay(i, calm())
		if delay then
			task.delay(delay, function()
				if not c.slot.Visible or c.hopping or c.hovering then return end
				c.hopping = true
				tween(c.float, TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = UDim2.fromOffset(0, -8) })
				task.delay(0.12, function()
					tween(c.float, TweenInfo.new(0.13, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = UDim2.fromOffset(0, 0) })
					task.delay(0.14, function() c.hopping = false end)
				end)
			end)
		end
	end
end

function M.trigger(patronId, event, fast)
	local c = M.cardOf(patronId)
	if not c or not c.slot.Visible or not holder then return end
	local text, key = PatronEvents.text(event)
	pcall(function() require(script.Parent.Cue).play("patron_trigger", 2) end) -- no id yet: silent
	-- hop 8 (Engine/TavernLife.patronHop) with a gold ring for 0.25 s (the ring stays in calm mode, the hop does not)
	local hopPx = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("TavernLife")).patronHop(calm())
	local v2 = false -- the v2 table: a tier effect (Engine/PatronJuice) replaces the plain callout and sets the hop
	pcall(function() v2 = require(script.Parent.Gameplay2).isActive() == true end)
	local tierName
	if v2 then
		tierName = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("PatronJuice")).tierOf(CollectionBook.rarityForId("patrons", patronId))
		if hopPx then hopPx = require(script.Parent.PatronJuiceFX).hopPx(tierName) or hopPx end
	end
	if hopPx then
		if c.floatTween then c.floatTween:Cancel(); c.floatTween = nil end
		c.hopping = true
		c.float.Position = UDim2.fromOffset(0, 0)
		tween(c.float, TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = UDim2.fromOffset(0, -hopPx) })
		task.delay(0.12, function()
			tween(c.float, TweenInfo.new(0.13, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = UDim2.fromOffset(0, 0) })
			task.delay(0.14, function() c.hopping = false; startFloat(c, 1) end)
		end)
	end
	local hold = PatronEvents.hold() -- nil outside Studio beatslow
	local frozen = event.freeze and function() return PatronEvents.slowMode() == "freeze" end or nil
	c.ringStroke.Transparency = 0
	if hold then
		task.delay(hold, function()
			while frozen and frozen() and c.ringStroke.Parent do task.wait(0.1) end
			tween(c.ringStroke, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Transparency = 1 })
		end)
	else
		tween(c.ringStroke, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Transparency = 1 })
	end
	-- the effect pill above the card
	local r = c.slot
	local hostX = r.Position.X.Offset + r.Size.X.Offset / 2
	local hostY, rise = Layout.pillSpot(r.Position.Y.Offset, r.Size.Y.Offset)
	local rim
	pcall(function()
		local t = PatronEvents.rarityRim(CollectionBook.rarityForId("patrons", patronId))
		rim = Color3.fromRGB(t[1], t[2], t[3])
	end)
	-- the serif callout rises 24 px over 0.6 s (static 0.4 s in calm mode, one per card in order); the Studio slow
	-- modes keep the old pill because it can be frozen for screenshots
	if hold or frozen then
		pill(holder, text, KIND_COLOR[key] or KIND_COLOR.chips, 18, key == "xmult", hostX, hostY, rise, hold, frozen, rim)
	else
		if v2 then
			require(script.Parent.PatronJuiceFX).play(c.slot, tierName, key, event.amount, rim)
		else
			require(script.Parent.PatronCalloutFX).show(holder, patronId, text, key, hostX, r.Position.Y.Offset)
		end
	end
	-- every other Patron dims to 70 percent while this one triggers
	dimToken = dimToken + 1
	local mine = dimToken
	for _, other in ipairs(cards) do
		if other ~= c and other.slot.Visible and other.id then
			tween(other.dim, TweenInfo.new(0.08), { BackgroundTransparency = 0.7 })
		end
	end
	c.dim.BackgroundTransparency = 1
	task.delay(hold or (PatronEvents.gap(fast) + 0.3), function()
		while frozen and frozen() and dimToken == mine do task.wait(0.1) end
		if dimToken ~= mine then return end
		for _, other in ipairs(cards) do
			if other.dim.Parent then tween(other.dim, TweenInfo.new(0.2), { BackgroundTransparency = 1 }) end
		end
	end)
end

-- a Boss Round or Bargain score change: a grey (helps) or red (hurts) pill on the tavern plate, never on a Patron
function M.tavernNote(text, hurts)
	if not rootRef then return end
	local anchor = anchorFn and anchorFn() or nil
	local x, y = 240, 200
	if anchor and anchor.Parent then
		x = anchor.AbsolutePosition.X - rootRef.AbsolutePosition.X + anchor.AbsoluteSize.X + 90
		y = anchor.AbsolutePosition.Y - rootRef.AbsolutePosition.Y + anchor.AbsoluteSize.Y / 2 + 14
	end
	pill(rootRef, text, hurts and Color3.fromRGB(255, 120, 108) or Color3.fromRGB(190, 190, 190), 18, false, x, y, 16)
end

return M
