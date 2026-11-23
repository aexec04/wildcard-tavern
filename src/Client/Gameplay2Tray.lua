--[[
	Client/Gameplay2Tray.lua
	Gameplay v2 consumables tray: up to two held Recipes as TavernKit plates under Mute and Calm, a Use plate and a Sell plate under
	them, and a prompt plate when a third row fits (Engine/Gameplay2Tray rules, Engine/Gameplay2Layout rects). Tap a slot to arm it,
	pick the hand cards it asks for, press Use. Nothing tweens, so Calm mode and Reduce motion are the same. Remotes: UseRecipe and
	SellRecipe (the server checks the phase and the cards again).

	Recipes: a wood panel behind the tray with a "Recipes" heading; each held slot shows its icon, name and tier rim; an empty slot says
	"Empty slot"; the Use plate says "Pick a Recipe" (grey) until one is armed, then what to do next ("Pick 1 card", then "Use"); the prompt
	plate shows what the armed Recipe does (its description); Sell shows its Tips only when armed. The first time a Recipe is held the
	one shot hint (Engine/Hints first_recipe, stored in profile.hintsSeen) says how it works.

	install(layer, deps{ selectedIndices }, z) -> { update(rects, state) }
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Engine = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine")
local Rules = require(Engine:WaitForChild("Gameplay2Tray"))
local Style = require(Engine:WaitForChild("TavernStyle"))
local Kit = require(script.Parent.TavernKit)
local Layout = require(Engine:WaitForChild("Gameplay2Layout"))

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

	-- the wood plate behind the whole tray, and its heading (made first, so the plates draw over them)
	local panel = Instance.new("Frame")
	panel.Name = "TrayPanel"
	panel.BackgroundColor3 = Color3.fromRGB(58, 40, 26)
	panel.BackgroundTransparency = 0.08
	panel.BorderSizePixel = 0
	panel.Active = false
	panel.Visible = false
	panel.ZIndex = math.max(1, z - 1)
	local pc = Instance.new("UICorner"); pc.CornerRadius = UDim.new(0, 10); pc.Parent = panel
	local ps = Instance.new("UIStroke"); ps.Color = Color3.fromRGB(222, 182, 104); ps.Thickness = 2; ps.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; ps.Parent = panel
	panel.Parent = layer
	local heading = Instance.new("TextLabel")
	heading.Name = "TrayHeading"
	heading.BackgroundTransparency = 1
	heading.Font = Enum.Font[Style.FONTS.title] or Enum.Font.GothamBold
	heading.TextSize = Style.TEXT.min
	heading.TextColor3 = Color3.fromRGB(250, 235, 200)
	heading.TextTransparency, heading.TextStrokeTransparency = 0, 1
	heading.Text = Rules.HEADING
	heading.TextXAlignment = Enum.TextXAlignment.Left
	heading.Active = false
	heading.Visible = false
	heading.ZIndex = z
	heading.Parent = layer
	local GREY, GREY_TEXT = Color3.fromRGB(86, 82, 78), Color3.fromRGB(176, 170, 160)
	-- skin a plate as a kit button, or as the clearly disabled grey plate (not the same dark brown as Sell)
	local function look(b, text, kind, grey)
		local key = kind .. (grey and "|grey" or "")
		if b:GetAttribute("TrayLook") == key then return end
		b:SetAttribute("TrayLook", key)
		Kit.skin(b, text, kind)
		if grey then
			b.BackgroundColor3 = GREY
			b.TextColor3 = GREY_TEXT
			for _, c in ipairs(b:GetChildren()) do if c:IsA("UIGradient") then c:Destroy() end end
		end
	end

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
		for _, b in ipairs({ slotBtn[1], slotBtn[2], useBtn, sellBtn, promptBtn, panel, heading }) do b.Visible = false end
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
				b.BackgroundTransparency = 0.75 -- a faint outline for a free slot, not a dead button
				setLabel(b, Rules.slotText(slot))
				b.TextTransparency = 0.25
				b:SetAttribute("Tier", "")
				local rim0 = b:FindFirstChildWhichIsA("UIStroke")
				if rim0 then rim0.Transparency = 0.45; rim0.Color = Color3.fromRGB(176, 150, 104) end
			else
				b.Active = true
				b.BackgroundTransparency = 0
				b.TextTransparency = 0
				local kind = self.armed == i and "primary" or "secondary"
				if b:GetAttribute("TavernKind") ~= kind then Kit.skin(b, Rules.slotText(slot), kind) end
				setLabel(b, Rules.slotText(slot)) -- icon and name
				b:SetAttribute("Tier", slot.tier)
				local rim = b:FindFirstChildWhichIsA("UIStroke")
				local c = TIER_RGB[slot.tier]
				if rim then rim.Transparency = 0 end
				if rim and c then rim.Color = Color3.fromRGB(c[1], c[2], c[3]) end
			end
		end
		-- the wood plate and its heading (the heading row is left out on screens with no spare row)
		local pr = Layout.trayPanel(r)
		if pr then place(panel, pr); panel.Visible = true else panel.Visible = false end
		if r.trayHeading then
			place(heading, r.trayHeading)
			heading.Visible = true
			heading.TextXAlignment = Enum.TextXAlignment.Left
		else
			heading.Visible = false
		end
		local f = Rules.flow(armedSlot, n, self.suit, armedSlot ~= nil)
		place(useBtn, r.trayUse); place(sellBtn, r.traySell)
		useBtn.ZIndex = z; sellBtn.ZIndex = z
		useBtn.Visible, sellBtn.Visible = true, true
		local usable = armedSlot ~= nil and f.canUse
		local useKind = usable and "primary" or "secondary"
		local text = r.trayPrompt and f.useText or (armedSlot and not f.canUse and f.prompt ~= "" and f.prompt or f.useText)
		look(useBtn, text, useKind, armedSlot == nil) -- nothing armed: grey and "Pick a Recipe"
		setLabel(useBtn, text)
		useBtn.TextTransparency = 0
		if sellBtn:GetAttribute("TavernKind") ~= "secondary" then Kit.skin(sellBtn, "Sell", "secondary") end
		setLabel(sellBtn, armedSlot and ("Sell +" .. math.floor(armedSlot.sell) .. " Tips") or "Sell") -- the Tips value shows only when armed
		sellBtn.TextTransparency = armedSlot and 0 or 0.4
		if r.trayPrompt and armedSlot then
			place(promptBtn, r.trayPrompt)
			promptBtn.ZIndex = z
			promptBtn.Visible = true
			if promptBtn:GetAttribute("TavernKind") ~= "secondary" then Kit.skin(promptBtn, "", "secondary") end
			local line = Rules.promptLine(f, armedSlot) -- what the armed Recipe does (its description)
			setLabel(promptBtn, line ~= "" and line or armedSlot.name)
		else
			promptBtn.Visible = false
		end
	end

	return self
end

return M
