--[[
	Client/PatronRow.lua
	The Patron Row: big painted Patron cards on the table, above the hand, between the dock icons and the cards.
	Rects come from the pure Engine/PatronRowLayout. Each card is the painted portrait inside its rarity frame with a
	name plaque under it; free seats are faint slots with a plus pip. A slow idle float (off in calm mode) and a hover
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
local PatronPlaque = require(script.Parent.PatronPlaque)
local PatronValueText = require(Engine:WaitForChild("PatronValueText"))
local RarityFrame = require(script.Parent.RarityFrame)
local ClientSettings = require(script.Parent.ClientSettings)

local M = {}

local GOLD = Color3.fromRGB(222, 182, 104)
local WOOD = Color3.fromRGB(78, 52, 26)
local CREAM = Color3.fromRGB(240, 225, 190)
local Z = 6

local holder, holderScale, rootRef, handRef, tooltipFn, anchorFn
local boost = { summary = nil, frame = nil } -- the Chips x Mult boost panel (built below)
local placeBoost
local cards = {} -- pool of { slot, float, body, art, name, plus, floatTween, id }
local lastState
local MAX_CARDS = 14

local function calm()
	local ok, v = pcall(function() return ClientSettings.get("reduceShake") end)
	return ok and v == true
end

local function corner(parent, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = parent
end

local function newCard(i)
	local c = { id = nil }
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
	name.Size = UDim2.new(1, -4, 1, 0)
	name.Position = UDim2.fromOffset(2, 0)
	name.BackgroundTransparency = 1
	name.Font = Enum.Font.GothamBold
	name.TextSize = 15
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
	value.TextColor3 = CREAM
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
	if tooltipFn then
		tooltipFn(body, function()
			local owned = lastState and lastState.ownedPatrons and lastState.ownedPatrons[i]
			if owned then return string.format("%s\n%s", owned.name, owned.description) end
			return require(Engine:WaitForChild("EmptyStates")).hint("seat")
		end)
	end
	return c
end

local function startFloat(c, i)
	if c.floatTween then c.floatTween:Cancel(); c.floatTween = nil end
	c.float.Position = UDim2.fromOffset(0, 0)
	if calm() or c.hopping then return end
	local t = TweenService:Create(c.float, TweenInfo.new(3, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Position = UDim2.fromOffset(0, -2) })
	-- stagger so the row does not bob as one block
	task.delay((i % 5) * 0.4, function() if c.floatTween == nil and c.slot.Visible and not c.hopping then c.floatTween = t; t:Play() end end)
end

local function fillCard(c, i, owned)
	if owned then
		c.plus.Visible = false
		c.plaque.Visible = true
		c.name.Text = owned.name
		c.valueText = PatronValueText.of(owned.description)
		c.body.BackgroundTransparency = 0
		c.body.BackgroundColor3 = WOOD
		if c.id ~= owned.id then
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
		pcall(function() RarityFrame.apply(c.body, tier, { thickness = 3, radius = 8, zIndex = Z + 4 }) end)
	else
		c.id = nil
		local old = c.body:FindFirstChild("PatronArt")
		if old then old:Destroy() end
		c.plus.Visible = true
		c.plus.Text = "+"
		c.plus.BackgroundTransparency = 0.8
		c.plaque.Visible = false
		c.valueText = nil
		c.value.Visible = false
		c.body.BackgroundTransparency = 0.75 -- faint slot
		local rs = c.body:FindFirstChild("RarityStroke")
		if rs then rs.Color = GOLD; rs.Transparency = 0.6 end
	end
end

-- ===== the Nook: ledge, back panel, lantern glow, alcoves (code-drawn, rects from PatronRowLayout.nook) =====
local nook -- { root, back, glow, ledge, trim, rivets, alcoves }

local NOOK_BACK = Color3.fromRGB(34, 22, 14)
local NOOK_ALCOVE = Color3.fromRGB(22, 14, 9)

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
	nook = { root = root, back = back, glow = glow, ledge = ledge, trim = trim, rivets = rivets, alcoves = {} }
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
	if show and rootSize.X < 1200 then -- narrow roots: keep the row right of the left board, never over its portrait
		local sb = rootRef:FindFirstChild("Sidebar")
		if sb and sb.Visible then
			opts.leftLimit = sb.AbsolutePosition.X - rootRef.AbsolutePosition.X + sb.AbsoluteSize.X + 8
		end
	end
	if show then
		lay = (paintedId() and Layout.painted(rootSize.X, rootSize.Y, hand, limit, opts)) or Layout.compute(rootSize.X, rootSize.Y, hand, limit, opts)
	end
	holder.Visible = lay ~= nil
	if k ~= 1 and RunService:IsStudio() then
		local r1 = lay and lay.cards[1]
		print(string.format("[PatronRow] scaled root k=%.2f root=%dx%d leftLimit=%s card1=%s", k, math.floor(rootSize.X), math.floor(rootSize.Y),
			tostring(opts and opts.leftLimit), r1 and (math.floor(r1.x) .. "," .. math.floor(r1.y) .. " " .. math.floor(r1.w) .. "x" .. math.floor(r1.h)) or "none"))
	end
	placeNook(lay, rootSize.X, hand, owned, opts)
	if #owned == 0 then boost.summary = nil end
	placeBoost(lay and nook and nook.lastBack or nil, rootSize.X / k)
	for i = 1, MAX_CARDS do
		local c = cards[i]
		if not c and lay and i <= limit then c = newCard(i); cards[i] = c end
		if c then
			local r = lay and lay.cards[i]
			if r then
				c.slot.Visible = true
				c.slot.Position = UDim2.fromOffset(r.x, r.y)
				c.slot.Size = UDim2.fromOffset(r.w, r.h)
				c.slot.ZIndex = Z + i -- later cards overlap earlier ones
				fillCard(c, i, owned[i])
				if c.value then
					c.value.Text = c.valueText or ""
					c.value.Visible = (c.valueText ~= nil) and PatronValueText.visible(r.w)
				end
				if lay.plaqueH <= 0 then c.plaque.Visible = false end -- narrow cards: the tooltip carries the name
				if not c.floatTween and not c.hopping then startFloat(c, i) end
			else
				c.slot.Visible = false
				if c.floatTween then c.floatTween:Cancel(); c.floatTween = nil end
			end
		end
	end
end

-- ===== boost panel: real Chips x Mult of the last scored hand, only while a Patron added to it (Engine/PatronBoost) =====
local function buildBoost()
	local f = Instance.new("Frame")
	f.Name = "PatronBoostPanel"
	f.BackgroundColor3 = Color3.fromRGB(46, 30, 16)
	f.BackgroundTransparency = 0.05
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
	local function label(name, y, h, size, color)
		local l = Instance.new("TextLabel")
		l.Name = name
		l.Position = UDim2.fromOffset(6, y)
		l.Size = UDim2.new(1, -12, 0, h)
		l.BackgroundTransparency = 1
		l.Font = Enum.Font.GothamBold
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
	boost.value = label("Value", 4, 30, 24, GOLD)
	boost.line = label("Line", 36, 38, 15, CREAM)
	boost.frame = f
	return f
end

function placeBoost(back, rootW)
	local sum = boost.summary
	local PatronBoost = require(Engine:WaitForChild("PatronBoost"))
	local r = sum and back and PatronBoost.place(back, rootW) or nil
	if not r then
		if boost.frame then boost.frame.Visible = false end
		return
	end
	local f = boost.frame or buildBoost()
	f.Position = UDim2.fromOffset(r.x, r.y)
	f.Size = UDim2.fromOffset(r.w, r.h)
	boost.value.Text = sum.text
	boost.line.Text = sum.line
	f.Visible = true
end

-- ScorePopup passes PatronBoost.summary(breakdown) once a hand has scored (nil clears the panel)
function M.setBoost(summary)
	boost.summary = summary
	if holder and nook then pcall(placeBoost, nook.lastBack, rootRef.AbsoluteSize.X) end
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
	if nook and nook.ledge and nook.ledge.Visible then
		-- also with no Patron owned yet: the empty nook still stands there, so the score readout must stay below it
		low = math.max(low or 0, nook.ledge.AbsolutePosition.Y + nook.ledge.AbsoluteSize.Y)
	end
	if not low then low = holder.AbsolutePosition.Y + holder.AbsoluteSize.Y end
	return low
end

function M.frameFor(patronId)
	return M.frames()[patronId]
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

local function pill(parent, text, color, size, bold, x, y, rise, hold, frozen)
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
	stroke.Color = color
	stroke.Thickness = 1.5
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

function M.trigger(patronId, event, fast)
	local c = M.cardOf(patronId)
	if not c or not c.slot.Visible or not holder then return end
	local text, key = PatronEvents.text(event)
	-- hop 14 with a gold ring for 0.25 s (the ring stays in calm mode, the hop does not)
	if not calm() then
		if c.floatTween then c.floatTween:Cancel(); c.floatTween = nil end
		c.hopping = true
		c.float.Position = UDim2.fromOffset(0, 0)
		tween(c.float, TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = UDim2.fromOffset(0, -14) })
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
	pill(holder, text, KIND_COLOR[key] or KIND_COLOR.chips, 18, key == "xmult", hostX, hostY, rise, hold, frozen)
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
