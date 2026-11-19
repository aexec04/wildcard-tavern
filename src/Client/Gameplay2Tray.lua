--[[
	Client/Gameplay2Tray.lua
	Gameplay v2 consumables tray: up to two held Recipes as TavernKit plates under Mute and Calm, a Use plate and a Sell plate under
	them, and a prompt plate when a third row fits (Engine/Gameplay2Tray rules, Engine/Gameplay2Layout rects). Tap a slot to arm it,
	pick the hand cards it asks for, press Use. Nothing tweens, so Calm mode and Reduce motion are the same. Remotes: UseRecipe and
	SellRecipe (the server checks the phase and the cards again).

	install(layer, deps{ selectedIndices }, z) -> { update(rects, state) }
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Engine = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine")
local Rules = require(Engine:WaitForChild("Gameplay2Tray"))
local Style = require(Engine:WaitForChild("TavernStyle"))
local Kit = require(script.Parent.TavernKit)

local M = {}

local TIER_RGB = { Common = { 176, 120, 66 }, Uncommon = { 96, 168, 96 }, Rare = { 96, 150, 220 } } -- rim colours; the tier is also a word

local function place(g, r)
	g.Position = UDim2.fromOffset(r.x, r.y)
	g.Size = UDim2.fromOffset(r.w, r.h)
end

local function setLabel(b, text)
	if b.Text ~= text then b.Text = text end
	b.TextSize = Style.TEXT.min
	b.TextWrapped = true
	b.TextTruncate = Enum.TextTruncate.None
end

function M.install(layer, deps, z)
	local self = { armed = nil, suit = Rules.SUITS[1], last = nil }
	local function cue(name) pcall(function() require(script.Parent.Cue).play(name) end) end

	local function mk(name)
		local b = Kit.secondaryButton(layer, "")
		b.Name = name
		b.ZIndex = z
		b.Visible = false
		return b
	end
	local slotBtn = { mk("TraySlot1"), mk("TraySlot2") }
	local useBtn, sellBtn, promptBtn = mk("TrayUse"), mk("TraySell"), mk("TrayPrompt")

	local function selection()
		local idx = deps.selectedIndices and deps.selectedIndices() or {}
		return idx, #idx
	end

	local function remote(name)
		local f = ReplicatedStorage:FindFirstChild("Remotes")
		return f and f:FindFirstChild(name)
	end

	local function slotAt(i)
		local held = Rules.held(self.last)
		return held.slots[i], held
	end

	for i = 1, Rules.SLOTS do
		slotBtn[i].MouseButton1Click:Connect(function()
			local slot = slotAt(i)
			if not slot or slot.empty then return end
			cue("button_click")
			if self.armed == i then
				if slot.needsSuit then self.suit = Rules.nextSuit(self.suit) else self.armed = nil end
			else
				self.armed = i
			end
			if self.refresh then self.refresh() end
		end)
	end
	promptBtn.MouseButton1Click:Connect(function()
		local slot = self.armed and slotAt(self.armed)
		if slot and slot.needsSuit then
			cue("button_click")
			self.suit = Rules.nextSuit(self.suit)
			if self.refresh then self.refresh() end
		end
	end)
	useBtn.MouseButton1Click:Connect(function()
		local slot = self.armed and slotAt(self.armed)
		if not slot or slot.empty then return end
		local idx, n = selection()
		local f = Rules.flow(slot, n, self.suit, true)
		if not f.canUse then cue("shop_cant"); return end
		local cat, id, indices, suit = Rules.useArgs(slot, idx, self.suit)
		local rem = remote("UseRecipe")
		if rem then rem:FireServer(cat, id, indices, suit) end
		cue("shop_buy")
		self.armed = nil
		if self.refresh then self.refresh() end
	end)
	sellBtn.MouseButton1Click:Connect(function()
		local slot = self.armed and slotAt(self.armed)
		if not slot or slot.empty then return end
		local rem = remote("SellRecipe")
		if rem then rem:FireServer(slot.category, slot.id) end
		cue("shop_buy")
		self.armed = nil
		if self.refresh then self.refresh() end
	end)

	local function hideAll()
		for _, b in ipairs({ slotBtn[1], slotBtn[2], useBtn, sellBtn, promptBtn }) do b.Visible = false end
	end

	function self.update(r, state)
		self.last = state
		self.rects = r
		self.refresh = function() self.update(self.rects, self.last) end
		local held = Rules.held(state)
		local any = false
		for _, s in ipairs(held.slots) do if not s.empty then any = true end end
		if not r.traySlot1 or not any or not state or state.phase ~= "playing" then
			self.armed = nil
			hideAll()
			return
		end
		local armedSlot = self.armed and held.slots[self.armed]
		if not armedSlot or armedSlot.empty then self.armed, armedSlot = nil, nil end
		local _, n = selection()
		for i = 1, Rules.SLOTS do
			local b, slot = slotBtn[i], held.slots[i]
			place(b, r["traySlot" .. i])
			b.Visible = true
			b.ZIndex = z
			if slot.empty then
				b.Active = false
				b.AutoButtonColor = false
				b.BackgroundTransparency = 0.75 -- a faint outline for a free slot
				setLabel(b, "Empty")
				b.TextTransparency = 0.4
				b:SetAttribute("Tier", "")
			else
				b.Active = true
				b.BackgroundTransparency = 0
				b.TextTransparency = 0
				local kind = self.armed == i and "primary" or "secondary"
				if b:GetAttribute("TavernKind") ~= kind then Kit.skin(b, slot.label, kind) end
				setLabel(b, slot.label)
				b:SetAttribute("Tier", slot.tier)
				local rim = b:FindFirstChildWhichIsA("UIStroke")
				local c = TIER_RGB[slot.tier]
				if rim and c then rim.Color = Color3.fromRGB(c[1], c[2], c[3]) end
			end
		end
		local f = Rules.flow(armedSlot, n, self.suit, armedSlot ~= nil)
		place(useBtn, r.trayUse); place(sellBtn, r.traySell)
		useBtn.ZIndex = z; sellBtn.ZIndex = z
		useBtn.Visible, sellBtn.Visible = true, true
		local usable = armedSlot ~= nil and f.canUse
		local useKind = usable and "primary" or "secondary"
		local text = r.trayPrompt and f.useText or (armedSlot and not f.canUse and f.prompt ~= "" and f.prompt or f.useText)
		if useBtn:GetAttribute("TavernKind") ~= useKind then Kit.skin(useBtn, text, useKind) end
		setLabel(useBtn, text)
		useBtn.TextTransparency = armedSlot and 0 or 0.4
		if sellBtn:GetAttribute("TavernKind") ~= "secondary" then Kit.skin(sellBtn, "Sell", "secondary") end
		setLabel(sellBtn, armedSlot and ("Sell +" .. math.floor(armedSlot.sell)) or "Sell")
		sellBtn.TextTransparency = armedSlot and 0 or 0.4
		if r.trayPrompt and armedSlot then
			place(promptBtn, r.trayPrompt)
			promptBtn.ZIndex = z
			promptBtn.Visible = true
			if promptBtn:GetAttribute("TavernKind") ~= "secondary" then Kit.skin(promptBtn, "", "secondary") end
			setLabel(promptBtn, f.prompt ~= "" and f.prompt or armedSlot.name)
		else
			promptBtn.Visible = false
		end
	end

	return self
end

return M
