--[[
	Client/ShopStage.lua
	Counter v2 stage director. Puts the existing Shop controls and card rows onto the painted counter scene
	(Client/ShopBackdrop) using the tested rects of Engine/ShopSceneLayout. Look only: it never changes a handler, price,
	remote or rule; it moves and restyles what Shop.lua already built.

	  * Shop tab: the Buy list stops being a scrolling list. Section headers hide, the Patron row and the smaller Pack row lie on
	    the oval card table (Engine/ShopSceneLayout `table`), every card at its own fixed angle (-5, +4, -3, +6 by slot; the slot
	    keeps it in its Tilt attribute), the Reroll button becomes the service bell with a name plate, the table count sits on
	    the counter front.
	  * Haggle becomes the ledger on the counter, the tabs become slim plates along the top, the Next boss chip sits
	    under them, Next Round is the sign at the bottom right.
	  * My Patrons / My Recipes keep their panels on a calm dark plate over the dimmed scene.
	  * When the backdrop art is missing (backdrop == nil) nothing here runs and the old Shop shows unchanged.

	ShopStage.new(deps) -> stage | nil
	  deps: shopFrame, buyList, contentArea, tabBar, plaque, nextRoundButton, backdrop (ShopBackdrop instance or nil),
	        cardRowHeight(kind, scale) -> number, setCardScale(s)
	stage.active, stage.scales(state) -> { patron, pack }, stage.arrange(parts), stage.setTab(key), stage.relayout(),
	  stage.keepOut() -> the controls a Counter tooltip must stay clear of
]]

local Engine = game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine")
local Layout = require(Engine:WaitForChild("ShopSceneLayout"))
local ClientSettings = require(script.Parent.ClientSettings)
local SoftGlow = require(script.Parent.SoftGlow)

local ShopStage = {}

local GOLD = Color3.fromRGB(222, 182, 104)
local INK = Color3.fromRGB(60, 40, 22)

local function calm()
	return ClientSettings.get("reduceShake") == true
end

local function place(obj, r)
	obj.Position = UDim2.fromOffset(r.x, r.y)
	obj.Size = UDim2.fromOffset(r.w, r.h)
end

-- hide the painted look of a polished button (stroke, gradient) so only a transparent hit area stays
local function quiet(button)
	button.BackgroundTransparency = 1
	button.TextTransparency = 1
	button.TextStrokeTransparency = 1
	for _, child in ipairs(button:GetChildren()) do
		if child:IsA("UIStroke") or child:IsA("UIGradient") then
			child.Enabled = false
		end
	end
end

-- The gold price tag hangs TAG_GAP under its prop and is TAG_H tall. It is only a label (Active = false), so a click on it goes
-- to whatever is under it: the control's hit area is therefore made TAG_H + TAG_GAP taller (and as wide as the tag), which is what
-- makes the pill itself clickable. (Before, only the small transparent rect over the painted prop was, and the pill did nothing.)
local TAG_H, TAG_GAP = 24, 4
ShopStage.TAG_H, ShopStage.TAG_GAP = TAG_H, TAG_GAP
-- Reroll and Haggle are objects in the room, so their words are a Menu-style name plate (dark, brass edge, cream text at 12:1)
-- under the painted prop, not a gold pill. The plate and the soft warm glow behind the prop light up while the pointer is on it.
local PLATE = Color3.fromRGB(44, 32, 22)
local PLATE_HOVER = Color3.fromRGB(78, 58, 36)
local CREAM = Color3.fromRGB(250, 235, 200)
local BRASS = Color3.fromRGB(190, 150, 62)

local function bindHover(button, tagLabel, glow)
	if button:GetAttribute("TagHover") then return end
	button:SetAttribute("TagHover", true)
	button.MouseEnter:Connect(function()
		tagLabel.BackgroundColor3 = PLATE_HOVER
		if glow and not calm() then glow.root.Visible = true end
	end)
	button.MouseLeave:Connect(function()
		tagLabel.BackgroundColor3 = PLATE
		if glow then glow.root.Visible = false end
	end)
end

local function tag(parent, name, text, width, y)
	local t = parent:FindFirstChild(name)
	if not t then
		t = Instance.new("TextLabel")
		t.Name = name
		t.AnchorPoint = Vector2.new(0.5, 0)
		t.BackgroundColor3 = PLATE
		t.BorderSizePixel = 0
		t.Font = Enum.Font.GothamBold
		t.TextSize = 14
		t.TextColor3 = CREAM
		t.TextTransparency = 0
		t.TextStrokeTransparency = 1
		t.ZIndex = 8
		t.Active = false
		t.Parent = parent
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, 7)
		c.Parent = t
		local s = Instance.new("UIStroke")
		s.Color = BRASS
		s.Thickness = 1.5
		s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		s.Parent = t
	end
	t.Text = text
	t.Size = UDim2.fromOffset(width or 110, TAG_H)
	t.Position = UDim2.new(0.5, 0, 1, y or TAG_GAP)
	return t
end

function ShopStage.new(deps)
	local backdrop = deps.backdrop
	if not backdrop then
		return nil
	end
	local shopFrame, buyList = deps.shopFrame, deps.buyList
	local self = { active = true }
	local last = nil -- last parts handed to arrange

	-- The warm glow behind a prop (the Menu room's hover look), made once per prop and moved with the layout; hidden until the
	-- pointer is on the control, and never lit in calm mode.
	local glows = {}
	local function propGlow(key, r)
		local g = glows[key]
		if not g then
			g = SoftGlow.build(shopFrame, {
				name = "Glow_" .. key, color = Color3.fromRGB(255, 196, 110), position = UDim2.fromOffset(0, 0),
				size = UDim2.fromOffset(10, 10), peak = 0.4, zIndex = 6,
			})
			g.root.Visible = false
			glows[key] = g
		end
		g.root.Position = UDim2.fromOffset(r.x + r.w / 2, r.y + r.h / 2)
		g.root.Size = UDim2.fromOffset(r.w * 2, r.h * 2)
		return g
	end

	-- the older flat art behind the scene is not needed any more
	for _, name in ipairs({ "ShopBackgroundArt", "ShopScrim" }) do
		local old = shopFrame:FindFirstChild(name)
		if old then old.Visible = false end
	end
	if deps.plaque then deps.plaque.Visible = false end

	-- calm dark plate for the My Patrons / My Recipes tabs (z 5: under the tab lists at z 6, over the scene)
	local dim = Instance.new("Frame")
	dim.Name = "SceneDim"
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = Color3.fromRGB(10, 6, 4)
	dim.BackgroundTransparency = 0.45
	dim.BorderSizePixel = 0
	dim.Active = false
	dim.Visible = false
	dim.ZIndex = 5
	dim.Parent = shopFrame
	local plate = Instance.new("Frame")
	plate.Name = "TabPlate"
	plate.Position = UDim2.new(0, 10, 0, 84)
	plate.Size = UDim2.new(1, -20, 1, -148)
	plate.BackgroundColor3 = Color3.fromRGB(34, 24, 16)
	plate.BackgroundTransparency = 0.1
	plate.BorderSizePixel = 0
	plate.Active = false
	plate.Visible = false
	plate.ZIndex = 5
	plate.Parent = shopFrame
	do
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, 10)
		c.Parent = plate
		local s = Instance.new("UIStroke")
		s.Color = GOLD
		s.Thickness = 1.5
		s.Transparency = 0.3
		s.Parent = plate
	end

	local tabKey = "buy"
	-- Left padding (inside the tab lists, which start at x 10) that keeps My Patrons / My Recipes clear of Marlo.
	function self.tabPadLeft()
		local W, H = shopFrame.AbsoluteSize.X, shopFrame.AbsoluteSize.Y
		if W < 1 or H < 1 then return 0 end
		local zone = Layout.tabZone(W, H, backdrop.marlo == nil, backdrop.roomId ~= nil)
		return math.max(zone.x - 10, 0)
	end
	function self.setTab(key)
		tabKey = key
		local onBuy = key == "buy"
		dim.Visible = not onBuy
		plate.Visible = not onBuy
		-- the tab bar and Next Round stay where the scene put them; only the list area changes
	end

	local function size()
		local s = shopFrame.AbsoluteSize
		if s.X < 1 or s.Y < 1 then
			local cam = workspace.CurrentCamera
			local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
			return math.max(vp.X - 300, 320), math.max(vp.Y, 400)
		end
		return s.X, s.Y
	end

	local function counts(state)
		local offers = #(state and state.shopOffers or {}) + ((state and state.voucherOffer) and 1 or 0)
		local packs = #(state and state.packOffers or {})
		return { offers = math.max(offers, 1), packs = packs, noMarlo = backdrop.marlo == nil, room = backdrop.roomId ~= nil }
	end

	local lastCounts = { offers = 3, packs = 2, noMarlo = backdrop.marlo == nil, room = backdrop.roomId ~= nil }
	-- Card scales for the current counts (Shop.lua sets them before building each row).
	function self.scales(state)
		lastCounts = counts(state)
		local W, H = size()
		return Layout.cardScales(Layout.rects(W, H, lastCounts))
	end

	-- Controls that live directly on shopFrame (tabs, Next Round, Haggle, boss chip, speech bubble).
	local function placeControls(r)
		if deps.tabBar then
			place(deps.tabBar, r.tabs)
			for _, b in ipairs(deps.tabBar:GetChildren()) do
				if b:IsA("TextButton") then b.Size = UDim2.new(1 / 3, -6, 1, 0) end
			end
		end
		if deps.nextRoundButton then
			deps.nextRoundButton.AnchorPoint = Vector2.new(0, 0)
			place(deps.nextRoundButton, r.leave)
			-- the painted stone arch is the way out: it glows while the pointer is on Next Round (not in calm mode)
			if r.arch then
				local g = propGlow("Arch", { x = r.arch.x + r.arch.w * 0.1, y = r.arch.y + r.arch.h * 0.35, w = r.arch.w * 0.8, h = r.arch.h * 0.6 })
				if not deps.nextRoundButton:GetAttribute("ArchHover") then
					deps.nextRoundButton:SetAttribute("ArchHover", true)
					deps.nextRoundButton.MouseEnter:Connect(function() if not calm() then g.root.Visible = true end end)
					deps.nextRoundButton.MouseLeave:Connect(function() g.root.Visible = false end)
				end
			end
		end
		local haggle = shopFrame:FindFirstChild("HaggleButton")
		if haggle and r.props.ledger then
			-- Haggle = the ledger AND its tag: one hit area, as wide as the tag and tall enough to include it
			local l = r.props.ledger
			local w = math.max(l.w, 84)
			haggle.AnchorPoint = Vector2.new(0, 0)
			haggle.Position = UDim2.fromOffset(l.x - (w - l.w) / 2, l.y)
			haggle.Size = UDim2.fromOffset(w, l.h + TAG_H + TAG_GAP)
			quiet(haggle)
			haggle.Text = ""
			-- ShopHaggle writes the state word ("Haggle" / "Haggled") into this attribute; a relayout must not reset it
			bindHover(haggle, tag(haggle, "HaggleTag", haggle:GetAttribute("Label") or "Haggle", w, -TAG_H), propGlow("Haggle", l))
		end
		local chip = shopFrame:FindFirstChild("BossScoutChip", true)
		if chip and chip.Parent == shopFrame then
			chip.AnchorPoint = Vector2.new(0, 0)
			chip.Position = UDim2.fromOffset(r.nextBoss.x, r.nextBoss.y)
			chip.Size = UDim2.fromOffset(r.nextBoss.w, 28)
		end
		if deps.onLayout then deps.onLayout(r) end
	end

	function self.arrange(parts)
		last = parts
		local W, H = size()
		if parts.counts then lastCounts = parts.counts end
		lastCounts.room = backdrop.roomId ~= nil
		local r = Layout.rects(W, H, lastCounts)
		backdrop.relayout(lastCounts)

		-- the Buy list covers the whole play area and stops scrolling
		buyList.Position = UDim2.fromOffset(-10, -84)
		buyList.Size = UDim2.new(1, 20, 1, 148)
		buyList.ScrollingEnabled = false
		buyList.ScrollBarThickness = 0
		buyList.AutomaticCanvasSize = Enum.AutomaticSize.None
		buyList.CanvasSize = UDim2.new()
		buyList.ClipsDescendants = false
		local layout = buyList:FindFirstChildOfClass("UIListLayout")
		if layout then layout.Parent = nil end -- UIListLayout has no Enabled; unparent so children keep manual positions

		for _, child in ipairs(buyList:GetChildren()) do
			if child:IsA("GuiObject") and child ~= parts.patronRow and child ~= parts.packRow and child ~= parts.rerollRow
				and child.Name ~= "OfferShadow" and child.Name ~= "EmptyScene" then
				child.Visible = false -- section headers
			end
		end

		local rows = Layout.rows(r, parts.patronRowHeight or 0, parts.packRowHeight or 0)
		for _, row in ipairs({ parts.patronRow, parts.packRow }) do
			if row then
				row.Active = false
				row.ScrollBarThickness = 0
			end
		end
		if parts.patronRow and rows.patron then place(parts.patronRow, rows.patron) end
		if parts.packRow and rows.pack then place(parts.packRow, rows.pack) end
		if parts.emptyScene and rows.patron then
			parts.emptyScene.AnchorPoint = Vector2.new(0.5, 1)
			parts.emptyScene.Position = UDim2.fromOffset(r.bandX0 + (r.bandX1 - r.bandX0) / 2, r.surfaceY - 8)
		end

		-- Reroll = the service bell with its price tag
		if parts.rerollRow and parts.rerollButton then
			local bell = r.props.bell
			parts.rerollRow.Position = UDim2.fromOffset(bell.x, bell.y)
			parts.rerollRow.Size = UDim2.fromOffset(bell.w, bell.h)
			-- the bell AND its price tag are one hit area: as wide as the tag, tall enough to include it
			local tagW = 120
			local extra = math.max(0, (tagW - bell.w) / 2)
			parts.rerollButton.Position = UDim2.fromOffset(-extra, 0)
			parts.rerollButton.Size = UDim2.new(1, 2 * extra, 1, TAG_H + TAG_GAP)
			local text = parts.rerollButton.Text
			if text ~= "" then parts.rerollButton:SetAttribute("Label", text) end -- "Reroll 3"; a relayout keeps it
			quiet(parts.rerollButton)
			parts.rerollButton.Text = ""
			bindHover(parts.rerollButton, tag(parts.rerollRow, "BellTag", parts.rerollButton:GetAttribute("Label") or "Reroll", tagW), propGlow("Reroll", bell))
			if parts.tableLabel then
				parts.tableLabel.Parent = buyList
				parts.tableLabel.AnchorPoint = Vector2.new(0, 0)
				parts.tableLabel.Position = UDim2.fromOffset(math.floor(W * 0.02), r.surfaceY + math.floor(r.counter.h * 0.3))
				parts.tableLabel.Size = UDim2.fromOffset(math.min(420, math.floor(W * 0.4)), 28)
				parts.tableLabel.TextSize = 14
				parts.tableLabel.TextXAlignment = Enum.TextXAlignment.Left
				parts.tableLabel.TextStrokeTransparency = 1
				parts.tableLabel.TextWrapped = false
			end
		end

		placeControls(r)

		-- Once the row layout has settled, every card lies on the felt at its own visible, fixed angle, as if dealt by hand (-5, +4, -3,
		-- +6 by slot): the same each visit, calm mode included. The angle goes on the card's inner Tilt wrapper (Roblox ignores Rotation
		-- on a direct child of a ScrollingFrame, which a Card_ slot is); the slot keeps it in its Tilt attribute, because Client/ShopCards
		-- straightens the card while the pointer is on it and turns it back afterwards. The cards lie still (no bob): a card on a table
		-- does not float; each one carries its own soft shadow (ShopCards).
		task.defer(function()
			if not parts.patronRow or not parts.patronRow.Parent then return end
			local dealt = 0
			for _, row in ipairs({ parts.patronRow, parts.packRow }) do
				for _, slot in ipairs(row and row:GetChildren() or {}) do
					local wrapper = slot:IsA("Frame") and slot.Name ~= "SoldSpot" and slot:FindFirstChild("Tilt") or nil
					if wrapper then
						dealt += 1
						local angle = Layout.cardTilt(dealt)
						wrapper.Rotation = angle
						slot:SetAttribute("Tilt", angle)
					end
				end
			end
		end)
	end

	-- Controls a hover tooltip on the Counter must never cover: the tabs, Next Round, Haggle (the ledger), Reroll (the
	-- bell with its tag) and the Next boss chip. Client/ShopTips hands them to TooltipSpec.placeBeside.
	function self.keepOut()
		local out = {}
		local function add(g) if g then out[#out + 1] = g end end
		add(deps.tabBar)
		add(deps.nextRoundButton)
		add(shopFrame:FindFirstChild("HaggleButton"))
		add(shopFrame:FindFirstChild("BossScoutChip", true))
		if last then add(last.rerollRow) end
		return out
	end

	function self.relayout()
		if last then self.arrange(last) end
	end
	shopFrame:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		if shopFrame.Visible then self.relayout() end
	end)
	shopFrame:GetPropertyChangedSignal("Visible"):Connect(function()
		if shopFrame.Visible and last then
			self.relayout()
		end
	end)
	shopFrame.ChildAdded:Connect(function(child)
		if child.Name == "BossScoutChip" and last then
			task.defer(self.relayout)
		end
	end)

	return self
end

return ShopStage
