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
local CollectionBook = require(Engine:WaitForChild("CollectionBook"))
local PatronPlaque = require(script.Parent.PatronPlaque)
local RarityFrame = require(script.Parent.RarityFrame)
local ClientSettings = require(script.Parent.ClientSettings)

local M = {}

local GOLD = Color3.fromRGB(222, 182, 104)
local WOOD = Color3.fromRGB(78, 52, 26)
local CREAM = Color3.fromRGB(240, 225, 190)
local Z = 6

local holder, rootRef, handRef, tooltipFn, stateGetter
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
	c.slot, c.float, c.body, c.name, c.plus, c.plaque, c.shadow = slot, float, body, name, plus, plaque, shadow
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
		c.body.BackgroundTransparency = 0.75 -- faint slot
		local rs = c.body:FindFirstChild("RarityStroke")
		if rs then rs.Color = GOLD; rs.Transparency = 0.6 end
	end
end

local function place(state)
	if not holder then return end
	state = state or lastState
	local owned = state and state.ownedPatrons or {}
	local limit = math.min(state and state.patronSlotLimit or #owned, MAX_CARDS)
	limit = math.max(limit, #owned)
	limit = math.min(limit, MAX_CARDS)
	local show = rootRef.Visible ~= false and handRef.Visible and limit > 0
	holder.Visible = show
	local rootSize = rootRef.AbsoluteSize
	local hand = {
		x = handRef.AbsolutePosition.X - rootRef.AbsolutePosition.X,
		y = handRef.AbsolutePosition.Y - rootRef.AbsolutePosition.Y,
		w = handRef.AbsoluteSize.X, h = handRef.AbsoluteSize.Y,
	}
	local lay = show and Layout.compute(rootSize.X, rootSize.Y, hand, limit) or nil
	holder.Visible = lay ~= nil
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
				if not c.floatTween and not c.hopping then startFloat(c, i) end
			else
				c.slot.Visible = false
				if c.floatTween then c.floatTween:Cancel(); c.floatTween = nil end
			end
		end
	end
end

function M.install(deps)
	if holder then return end
	rootRef, handRef, tooltipFn, stateGetter = deps.root, deps.handFrame, deps.tooltip, deps.getState
	holder = Instance.new("Frame")
	holder.Name = "PatronRow"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromScale(1, 1)
	holder.ZIndex = Z
	holder.Active = false
	holder.Visible = false
	holder.Parent = rootRef
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

function M.frames()
	local out = {}
	local owned = lastState and lastState.ownedPatrons or {}
	for i, p in ipairs(owned) do
		local c = cards[i]
		if c and c.slot.Visible then out[p.id] = c.body end
	end
	return out
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

return M
