--[[
	Client/ShopStage.lua
	Counter v2 stage director. Puts the existing Shop controls and card rows onto the painted counter scene
	(Client/ShopBackdrop) using the tested rects of Engine/ShopSceneLayout. Look only: it never changes a handler, price,
	remote or rule; it moves and restyles what Shop.lua already built.

	  * Shop tab: the Buy list stops being a scrolling list. Section headers hide, the Patron row floats above the counter
	    (one gentle shared bob, 5 px, 3.5 s, off in calm mode) with a soft oval shadow under every card on the counter,
	    the Pack row rests on the counter, the Reroll button becomes the service bell with a brass price tag, the table
	    count sits on the counter front.
	  * Haggle becomes the ledger on the counter, the tabs become slim plates along the top, the Next boss chip sits
	    under them, Next Round is the sign at the bottom right.
	  * My Patrons / My Recipes keep their panels on a calm dark plate over the dimmed scene.
	  * When the backdrop art is missing (backdrop == nil) nothing here runs and the old Shop shows unchanged.

	ShopStage.new(deps) -> stage | nil
	  deps: shopFrame, buyList, contentArea, tabBar, plaque, nextRoundButton, backdrop (ShopBackdrop instance or nil),
	        cardRowHeight(kind, scale) -> number, setCardScale(s)
	stage.active, stage.scales(state) -> { patron, pack }, stage.arrange(parts), stage.setTab(key), stage.relayout()
]]

local TweenService = game:GetService("TweenService")
local Engine = game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine")
local Layout = require(Engine:WaitForChild("ShopSceneLayout"))
local ClientSettings = require(script.Parent.ClientSettings)

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

local function tag(parent, name, text, width)
	local t = parent:FindFirstChild(name)
	if not t then
		t = Instance.new("TextLabel")
		t.Name = name
		t.AnchorPoint = Vector2.new(0.5, 0)
		t.BackgroundColor3 = GOLD
		t.BorderSizePixel = 0
		t.Font = Enum.Font.GothamBold
		t.TextSize = 14
		t.TextColor3 = INK
		t.TextTransparency = 0
		t.TextStrokeTransparency = 1
		t.ZIndex = 8
		t.Active = false
		t.Parent = parent
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, 7)
		c.Parent = t
		local s = Instance.new("UIStroke")
		s.Color = Color3.fromRGB(110, 76, 34)
		s.Thickness = 1.5
		s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		s.Parent = t
	end
	t.Text = text
	t.Size = UDim2.fromOffset(width or 110, 24)
	t.Position = UDim2.new(0.5, 0, 1, 4)
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
	local tweens = {}

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
		local zone = Layout.tabZone(W, H, backdrop.marlo == nil)
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
		return { offers = math.max(offers, 1), packs = packs, noMarlo = backdrop.marlo == nil }
	end

	local lastCounts = { offers = 3, packs = 2, noMarlo = backdrop.marlo == nil }
	-- Card scales for the current counts (Shop.lua sets them before building each row).
	function self.scales(state)
		lastCounts = counts(state)
		local W, H = size()
		return Layout.cardScales(Layout.rects(W, H, lastCounts))
	end

	local function cancelTweens()
		for _, t in ipairs(tweens) do pcall(function() t:Cancel() end) end
		tweens = {}
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
		end
		local haggle = shopFrame:FindFirstChild("HaggleButton")
		if haggle and r.props.ledger then
			haggle.AnchorPoint = Vector2.new(0, 0)
			place(haggle, r.props.ledger)
			quiet(haggle)
			haggle.Text = ""
			tag(haggle, "HaggleTag", "Haggle", math.max(r.props.ledger.w, 84))
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
		cancelTweens()
		local W, H = size()
		if parts.counts then lastCounts = parts.counts end
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
			parts.rerollButton.Position = UDim2.new()
			parts.rerollButton.Size = UDim2.fromScale(1, 1)
			local text = parts.rerollButton.Text
			quiet(parts.rerollButton)
			parts.rerollButton.Text = ""
			tag(parts.rerollRow, "BellTag", text ~= "" and text or "Reroll", 120)
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

		-- shadows and the gentle bob, once the row layout has settled
		task.defer(function()
			if not parts.patronRow or not parts.patronRow.Parent then return end
			for _, old in ipairs(buyList:GetChildren()) do
				if old.Name == "OfferShadow" then old:Destroy() end
			end
			local origin = buyList.AbsolutePosition
			local shadows = {}
			for _, slot in ipairs(parts.patronRow:GetChildren()) do
				if slot:IsA("Frame") and slot.Name ~= "SoldSpot" and slot.AbsoluteSize.X > 0 then
					local sh = Instance.new("Frame")
					sh.Name = "OfferShadow"
					sh.AnchorPoint = Vector2.new(0.5, 0.5)
					local cx = slot.AbsolutePosition.X - origin.X + slot.AbsoluteSize.X / 2
					sh.Position = UDim2.fromOffset(cx, r.surfaceY - 4)
					sh.Size = UDim2.fromOffset(slot.AbsoluteSize.X * 0.8, 14)
					sh.BackgroundColor3 = Color3.fromRGB(8, 5, 3)
					sh.BackgroundTransparency = 0.55
					sh.BorderSizePixel = 0
					sh.Active = false
					sh.ZIndex = 6
					sh.Parent = buyList
					local c = Instance.new("UICorner")
					c.CornerRadius = UDim.new(0.5, 0)
					c.Parent = sh
					shadows[#shadows + 1] = sh
				end
			end
			if calm() or ClientSettings.get("animSpeed") == "fast" then return end
			local info = TweenInfo.new(Layout.BOB_PERIOD / 2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
			local row = parts.patronRow
			local y = row.Position.Y.Offset
			local t = TweenService:Create(row, info, { Position = UDim2.fromOffset(row.Position.X.Offset, y - Layout.BOB_PX) })
			t:Play()
			tweens[#tweens + 1] = t
			local fade = Layout.shadowFor(Layout.BOB_PX)
			for _, sh in ipairs(shadows) do
				local st = TweenService:Create(sh, info, { BackgroundTransparency = fade.transparency })
				st:Play()
				tweens[#tweens + 1] = st
			end
		end)
	end

	function self.relayout()
		if last then self.arrange(last) end
	end
	shopFrame:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		if shopFrame.Visible then self.relayout() end
	end)
	shopFrame:GetPropertyChangedSignal("Visible"):Connect(function()
		if not shopFrame.Visible then
			cancelTweens()
		elseif last then
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
