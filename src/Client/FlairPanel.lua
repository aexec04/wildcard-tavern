--[[
	Client/FlairPanel.lua
	FLAIR (Engine/Flair.lua), opened from the "Flair" button in the Collection header. Four slots (Score Numbers, Play Trail,
	Finisher, Name Aura), each a row of option tiles: a preview card with the icon, the name, a rarity frame, and either
	"Equipped", an Equip button, or the unlock hint (locked ones are dimmed, never black; store ones say so). Every unlocked
	option has a Preview button that plays the effect once (nothing plays under Reduce Flashing / Motion / Shake).
	Display only: the server validates the slot, the option and ownership (remote EquipFlair) and sends state.flair.
	Refreshes on every StateUpdated while open.

	init(deps): { screenGui, openButton, polishPanel, polishButton, roundCorner, addSoftShadow, playClickSfx, addTooltip,
	              popIn, popOut, addButtonHoverScale, getLatestState, StateUpdatedRemote, particleBurst }
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local FlairPanel = {}

function FlairPanel.init(deps)
	local OverlayManager = require(script.Parent.OverlayManager)
	local ArtIcon = require(script.Parent.ArtIcon)
	local RarityFrame = require(script.Parent.RarityFrame)
	local FlairFX = require(script.Parent.FlairFX)
	local ClientSettings = require(script.Parent.ClientSettings)
	local EquipRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("EquipFlair")
	local PurchaseRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("StorePurchase")

	local INK = Color3.fromRGB(60, 40, 22)
	local CREAM = Color3.fromRGB(250, 235, 200)
	local GOLD = Color3.fromRGB(222, 182, 104)
	local WOOD = Color3.fromRGB(86, 58, 34)
	local PARCH = Color3.fromRGB(222, 198, 150)
	local GREEN = Color3.fromRGB(86, 140, 80)
	local TILE_W, TILE_H = 132, 196
	local firstSightOwned -- option ids owned when the panel first drew this session; later unlocks wear a NEW ribbon
	local lastEquipped = {} -- slotId -> option id, to sparkle when it changes

	local function label(parent, props)
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Font = Enum.Font.GothamBold
		l.TextColor3 = INK
		l.TextTransparency = 0
		l.TextStrokeTransparency = 1
		l.TextSize = 15
		l.ZIndex = 43
		for k, v in pairs(props) do
			l[k] = v
		end
		l.Parent = parent
		return l
	end

	local backdrop = Instance.new("Frame")
	backdrop.Name = "FlairBackdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	backdrop.BackgroundTransparency = 0.4
	backdrop.Visible = false
	backdrop.ZIndex = 40
	backdrop.Parent = deps.screenGui

	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Size = UDim2.fromScale(0.86, 0.9)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.BackgroundColor3 = Color3.fromRGB(40, 30, 22)
	panel.ZIndex = 41
	panel.Parent = backdrop
	deps.polishPanel(panel, 16, "wood")
	deps.addSoftShadow(panel, 18)

	label(panel, { Size = UDim2.new(1, 0, 0, 34), Position = UDim2.fromOffset(0, 6), TextSize = 28, Text = "Flair", TextColor3 = CREAM })
	label(panel, {
		Size = UDim2.new(1, -30, 0, 22), Position = UDim2.fromOffset(15, 38), Font = Enum.Font.GothamMedium, TextXAlignment = Enum.TextXAlignment.Left,
		Text = "Looks only. Flair never changes your score.", TextColor3 = CREAM, TextSize = 16,
	})

	-- the four Store pieces at a lower price (hidden once everything in it is yours)
	local bundleButton = Instance.new("TextButton")
	bundleButton.Size = UDim2.fromOffset(190, 30)
	bundleButton.AnchorPoint = Vector2.new(1, 0)
	bundleButton.Position = UDim2.new(1, -15, 0, 34)
	bundleButton.Font = Enum.Font.GothamBold
	bundleButton.TextSize = 14
	bundleButton.TextColor3 = INK
	bundleButton.BackgroundColor3 = GOLD
	bundleButton.Text = "Flair Bundle"
	bundleButton.ZIndex = 43
	bundleButton.Visible = false
	bundleButton.Parent = panel
	deps.polishButton(bundleButton, 8)
	bundleButton.MouseButton1Click:Connect(function()
		deps.playClickSfx()
		PurchaseRemote:FireServer("flair_bundle")
	end)
	local StorePanelModule = require(script.Parent.StorePanel)

	local scroll = Instance.new("ScrollingFrame")
	scroll.Size = UDim2.new(1, -30, 1, -250)
	scroll.Position = UDim2.fromOffset(15, 194)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 10
	scroll.ScrollBarImageColor3 = GOLD
	scroll.ScrollBarImageTransparency = 0
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new()
	scroll.ZIndex = 41
	scroll.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 12)
	layout.Parent = scroll

	local closeButton = Instance.new("TextButton")
	closeButton.Size = UDim2.fromOffset(110, 34)
	closeButton.AnchorPoint = Vector2.new(0.5, 1)
	closeButton.Position = UDim2.new(0.5, 0, 1, -10)
	closeButton.Font = Enum.Font.GothamBold
	closeButton.TextSize = 15
	closeButton.TextColor3 = CREAM
	closeButton.BackgroundColor3 = Color3.fromRGB(70, 55, 40)
	closeButton.Text = "Close"
	closeButton.ZIndex = 43
	closeButton.Parent = panel
	deps.polishButton(closeButton, 8)
	deps.addButtonHoverScale(closeButton)

	-- LIVE STAGE: the score number, name aura, play trail and finisher of the selected options (equipped ones until the
	-- player taps Preview on another) loop here. Calm mode shows the static score and name only.
	local selected = {} -- slotId -> option row (Preview taps); equipped options fill the gaps
	local equippedBySlot = {}
	local stage = Instance.new("Frame")
	stage.Name = "Stage"
	stage.Size = UDim2.new(0.56, 0, 0, 124)
	stage.Position = UDim2.fromOffset(15, 66)
	stage.BackgroundColor3 = Color3.fromRGB(26, 19, 14)
	stage.BorderSizePixel = 0
	stage.ClipsDescendants = true
	stage.ZIndex = 42
	stage.Parent = panel
	deps.roundCorner(stage, 12)
	local stageStroke = Instance.new("UIStroke")
	stageStroke.Color = GOLD
	stageStroke.Thickness = 2
	stageStroke.Parent = stage
	local stageScore = label(stage, { Size = UDim2.new(1, 0, 0, 48), Position = UDim2.fromOffset(0, 26), TextSize = 40, Text = "12,480", TextColor3 = CREAM, ZIndex = 45 })
	local stageScoreStroke = Instance.new("UIStroke")
	stageScoreStroke.Thickness = 1
	stageScoreStroke.Parent = stageScore
	local stageName = label(stage, { Size = UDim2.new(1, 0, 0, 26), Position = UDim2.fromOffset(0, 84), TextSize = 20, Text = "You", TextColor3 = CREAM, ZIndex = 45 })
	label(stage, { Size = UDim2.new(1, -16, 0, 20), Position = UDim2.fromOffset(8, 4), TextSize = 15, Text = "Live preview", TextColor3 = GOLD, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 45 })
	local previewingLabel = label(stage, { Size = UDim2.new(0.5, -8, 0, 20), Position = UDim2.new(0.5, 0, 0, 4), TextSize = 15, Text = "", TextColor3 = CREAM,
		TextXAlignment = Enum.TextXAlignment.Right, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 45 })
	local auraRing = Instance.new("Frame") -- soft glow ring that pulses around the name when an aura is previewed
	auraRing.Name = "AuraRing"
	auraRing.AnchorPoint = Vector2.new(0.5, 0.5)
	auraRing.Position = UDim2.new(0.5, 0, 0, 97)
	auraRing.Size = UDim2.fromOffset(90, 30)
	auraRing.BackgroundTransparency = 1
	auraRing.Visible = false
	auraRing.ZIndex = 44
	auraRing.Parent = stage
	deps.roundCorner(auraRing, 15)
	local auraRingStroke = Instance.new("UIStroke")
	auraRingStroke.Thickness = 3
	auraRingStroke.Parent = auraRing
	local stagePoint = Instance.new("Frame") -- where trails and finishers burst
	stagePoint.Size = UDim2.fromOffset(2, 2)
	stagePoint.AnchorPoint = Vector2.new(0.5, 0.5)
	stagePoint.Position = UDim2.fromScale(0.5, 0.5)
	stagePoint.BackgroundTransparency = 1
	stagePoint.Parent = stage

	local summary = Instance.new("Frame") -- "Equipped" summary of all four slots
	summary.Name = "Equipped"
	summary.Size = UDim2.new(0.44, -22, 0, 124)
	summary.Position = UDim2.new(0.56, 7, 0, 66)
	summary.BackgroundColor3 = Color3.fromRGB(26, 19, 14)
	summary.BorderSizePixel = 0
	summary.ZIndex = 42
	summary.Parent = panel
	deps.roundCorner(summary, 12)
	local summaryStroke = Instance.new("UIStroke")
	summaryStroke.Color = Color3.fromRGB(150, 112, 60)
	summaryStroke.Thickness = 1.5
	summaryStroke.Parent = summary
	local summaryLines = {}
	label(summary, { Size = UDim2.new(1, -16, 0, 20), Position = UDim2.fromOffset(10, 4), TextSize = 16, Text = "Equipped", TextColor3 = GOLD, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 45 })
	for i = 1, 4 do
		summaryLines[i] = label(summary, {
			Size = UDim2.new(1, -16, 0, 22), Position = UDim2.fromOffset(10, 24 + (i - 1) * 24), TextSize = 15, Text = "",
			TextColor3 = CREAM, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 45,
		})
	end

	local function rgbOf(option, fallback)
		local c = option and option.color or fallback
		return Color3.fromRGB(c[1], c[2], c[3])
	end

	local function currentOption(slotId)
		return selected[slotId] or equippedBySlot[slotId]
	end

	local function paintStage()
		local num = currentOption("scoreNumbers")
		local aura = currentOption("nameAura")
		local numColor = rgbOf(num, { 250, 235, 200 })
		stageScore.TextColor3 = numColor
		stageScoreStroke.Color = numColor
		stageScoreStroke.Thickness = math.max(0, (num and num.glow or 0))
		local auraColor = rgbOf(aura, { 250, 235, 200 })
		stageName.TextColor3 = auraColor
		stageName.Text = ((aura and aura.crest and aura.crest ~= "") and (aura.crest .. " ") or "") .. "You"
	end

	local function pulseAura(option)
		if not FlairFX.canAnimate() then return end
		auraRingStroke.Color = rgbOf(option, { 250, 235, 200 })
		auraRingStroke.Transparency = 0.2
		auraRing.Size = UDim2.fromOffset(90, 30)
		auraRing.Visible = true
		TweenService:Create(auraRing, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = UDim2.fromOffset(190, 44) }):Play()
		TweenService:Create(auraRingStroke, TweenInfo.new(0.7), { Transparency = 1 }):Play()
		TweenService:Create(stageName, TweenInfo.new(0.12, Enum.EasingStyle.Back), { TextSize = 26 }):Play()
		task.delay(0.15, function() TweenService:Create(stageName, TweenInfo.new(0.2), { TextSize = 20 }):Play() end)
	end

	local function popNumbers()
		if not FlairFX.canAnimate() then return end
		TweenService:Create(stageScore, TweenInfo.new(0.15, Enum.EasingStyle.Back), { TextSize = 54 }):Play()
		task.delay(0.18, function() TweenService:Create(stageScore, TweenInfo.new(0.25), { TextSize = 40 }):Play() end)
	end

	local function stageBurstPos()
		return UDim2.fromOffset(stagePoint.AbsolutePosition.X, stagePoint.AbsolutePosition.Y)
	end

	local stageToken = 0
	local function stopStage()
		stageToken = stageToken + 1
	end
	local function startStage()
		stopStage()
		paintStage()
		if ClientSettings.get("reduceShake") == true or not deps.particleBurst then return end
		local mine = stageToken
		task.spawn(function()
			while stageToken == mine and backdrop.Visible do
				local trail = currentOption("playTrail")
				local finisher = currentOption("finisher")
				if trail then pcall(FlairFX.preview, deps.particleBurst, "playTrail", trail, stageBurstPos()) end
				TweenService:Create(stageScore, TweenInfo.new(0.15, Enum.EasingStyle.Back), { TextSize = 46 }):Play()
				task.wait(0.15)
				TweenService:Create(stageScore, TweenInfo.new(0.2), { TextSize = 40 }):Play()
				task.wait(0.85)
				if stageToken ~= mine then break end
				if finisher then pcall(FlairFX.preview, deps.particleBurst, "finisher", finisher, stageBurstPos()) end
				task.wait(1.8)
			end
		end)
	end

	-- Preview tap: put that option on the stage and play it once, above the panel.
	local function previewSample(slotId, option)
		selected[slotId] = option
		paintStage()
		previewingLabel.Text = "Previewing: " .. tostring(option.name)
		if slotId == "playTrail" or slotId == "finisher" then
			if deps.particleBurst and FlairFX.canAnimate() then
				pcall(FlairFX.preview, deps.particleBurst, slotId, option, stageBurstPos())
			end
		elseif slotId == "scoreNumbers" then
			popNumbers()
		elseif slotId == "nameAura" then
			pulseAura(option)
		end
	end

	local function tile(row, slotId, option)
		local t = Instance.new("Frame")
		t.Name = "Flair_" .. option.id
		t.Size = UDim2.fromOffset(TILE_W, TILE_H)
		t.BackgroundColor3 = option.equipped and Color3.fromRGB(176, 190, 140) or PARCH
		t.BorderSizePixel = 0
		t.ZIndex = 42
		t.Parent = row
		deps.roundCorner(t, 10)
		pcall(RarityFrame.apply, t, option.rarity or "common", { thickness = 2, radius = 10, locked = not option.owned, zIndex = 46 })

		local well = Instance.new("Frame")
		well.Size = UDim2.fromOffset(64, 64)
		well.Position = UDim2.fromOffset(34, 10)
		well.BackgroundColor3 = WOOD
		well.BorderSizePixel = 0
		well.ZIndex = 43
		well.Parent = t
		deps.roundCorner(well, 10)
		local glyph = label(well, { Size = UDim2.fromScale(1, 1), TextSize = 32, TextColor3 = CREAM, Text = option.icon, ZIndex = 44 })
		pcall(ArtIcon.apply, well, "flair", option.id, glyph, { cornerRadius = 10, zIndex = 45, dim = not option.owned })
		if not option.owned then glyph.TextTransparency = 0.35 end -- dimmed, never black

		label(t, { Size = UDim2.new(1, -6, 0, 34), Position = UDim2.fromOffset(3, 78), TextSize = 14, TextWrapped = true, Text = option.name })
		if option.owned then
			label(t, { Size = UDim2.new(1, -6, 0, 16), Position = UDim2.fromOffset(3, 112), Font = Enum.Font.Gotham, TextSize = 14,
				Text = option.equipped and "Equipped" or "Unlocked" })
			if slotId ~= "nameAura" or true then
				local preview = Instance.new("TextButton")
				preview.Size = UDim2.fromOffset(56, 28)
				preview.Position = UDim2.fromOffset(8, 142)
				preview.Font = Enum.Font.GothamBold
				preview.TextSize = 14
				preview.TextColor3 = CREAM
				preview.BackgroundColor3 = Color3.fromRGB(70, 55, 40)
				preview.Text = "Preview"
				preview.ZIndex = 44
				preview.Parent = t
				deps.polishButton(preview, 6)
				preview.MouseButton1Click:Connect(function()
					deps.playClickSfx()
					previewSample(slotId, option)
				end)
			end
			if not option.equipped then
				local equip = Instance.new("TextButton")
				equip.Size = UDim2.fromOffset(56, 28)
				equip.Position = UDim2.fromOffset(68, 142)
				equip.Font = Enum.Font.GothamBold
				equip.TextSize = 14
				equip.TextColor3 = CREAM
				equip.BackgroundColor3 = GREEN
				equip.Text = "Equip"
				equip.ZIndex = 44
				equip.Parent = t
				deps.polishButton(equip, 6)
				equip.MouseButton1Click:Connect(function()
					deps.playClickSfx()
					EquipRemote:FireServer(slotId, option.id)
				end)
			end
		else
			label(t, { Size = UDim2.new(1, -8, 0, option.store and 28 or (option.goal and 42 or 66)), Position = UDim2.fromOffset(4, 112), Font = Enum.Font.GothamMedium, TextSize = 14, TextWrapped = true,
				Text = option.store and "Tavern Store" or option.hint })
			if option.goal and not option.store then -- progress toward the unlock, e.g. Rank 3 of 5
				local track = Instance.new("Frame")
				track.Size = UDim2.new(1, -20, 0, 10)
				track.Position = UDim2.fromOffset(10, 158)
				track.BackgroundColor3 = Color3.fromRGB(120, 100, 70)
				track.BorderSizePixel = 0
				track.ZIndex = 44
				track.Parent = t
				deps.roundCorner(track, 5)
				local fill = Instance.new("Frame")
				fill.Size = UDim2.fromScale(math.clamp((option.progress or 0) / option.goal, 0, 1), 1)
				fill.BackgroundColor3 = GOLD
				fill.BorderSizePixel = 0
				fill.ZIndex = 45
				fill.Parent = track
				deps.roundCorner(fill, 5)
				label(t, { Size = UDim2.new(1, -8, 0, 18), Position = UDim2.fromOffset(4, 172), TextSize = 14, Font = Enum.Font.GothamMedium,
					Text = string.format("%d of %d", math.floor(option.progress or 0), math.floor(option.goal)) })
			end
			if option.store then
				local buy = Instance.new("TextButton")
				buy.Size = UDim2.fromOffset(112, 28)
				buy.Position = UDim2.fromOffset(10, 150)
				buy.Font = Enum.Font.GothamBold
				buy.TextSize = 14
				buy.TextColor3 = INK
				buy.BackgroundColor3 = GOLD
				buy.Text = "Buy"
				buy.ZIndex = 44
				buy.Parent = t
				deps.polishButton(buy, 6)
				buy.MouseButton1Click:Connect(function()
					deps.playClickSfx()
					PurchaseRemote:FireServer("flair_" .. option.id) -- the server checks the item, Studio grants placeholders free
				end)
			end
		end
		deps.addTooltip(t, option.name .. (option.owned and "" or (": " .. (option.store and "Sold in the Tavern Store." or option.hint))))
		if option.owned and firstSightOwned and not firstSightOwned[option.id] then
			local ribbon = label(t, {
				Size = UDim2.fromOffset(46, 20), Position = UDim2.fromOffset(-4, 6), Text = "NEW", TextSize = 14, TextColor3 = INK,
				BackgroundTransparency = 0, BackgroundColor3 = GOLD, ZIndex = 50,
			})
			deps.roundCorner(ribbon, 4)
		end
		if option.equipped and lastEquipped[slotId] ~= option.id then
			if lastEquipped[slotId] ~= nil and deps.particleBurst and ClientSettings.get("reduceShake") ~= true then
				task.defer(function() -- a sparkle on the newly equipped tile
					if t.Parent then
						pcall(deps.particleBurst, UDim2.fromOffset(t.AbsolutePosition.X + TILE_W / 2, t.AbsolutePosition.Y + 40), GOLD, 10, { size = 7, spread = 60, duration = 0.6 })
					end
				end)
			end
			lastEquipped[slotId] = option.id
		end
	end

	local function refresh()
		for _, child in ipairs(scroll:GetChildren()) do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		local state = deps.getLatestState and deps.getLatestState() or nil
		local view = state and state.flair
		if not view then
			return
		end
		bundleButton.Visible = false
		if not firstSightOwned then
			firstSightOwned = {}
			for _, slot in ipairs(view.slots) do
				for _, option in ipairs(slot.options) do
					if option.owned then firstSightOwned[option.id] = true end
				end
			end
		end
		for i, slot in ipairs(view.slots) do
			for _, option in ipairs(slot.options) do
				if option.equipped then
					equippedBySlot[slot.id] = option
					summaryLines[i].Text = slot.icon .. " " .. option.name
				end
			end
		end
		paintStage()
		for _, item in ipairs(state.flairStore and state.flairStore.items or {}) do
			if item.id == "flair_bundle" and not item.owned then
				bundleButton.Visible = true
				bundleButton.Text = "Flair Bundle: " .. StorePanelModule.priceText(item)
			end
		end
		for i, slot in ipairs(view.slots) do
			local section = Instance.new("Frame")
			section.LayoutOrder = i
			section.Size = UDim2.new(1, 0, 0, TILE_H + 34)
			section.BackgroundTransparency = 1
			section.ZIndex = 41
			section.Parent = scroll
			local ownedCount = 0
			for _, option in ipairs(slot.options) do
				if option.owned then ownedCount = ownedCount + 1 end
			end
			label(section, { Size = UDim2.new(1, 0, 0, 28), TextSize = 22, TextColor3 = CREAM, TextXAlignment = Enum.TextXAlignment.Left,
				Text = slot.icon .. " " .. slot.name .. "   " .. ownedCount .. " of " .. #slot.options .. " unlocked" })
			local row = Instance.new("ScrollingFrame")
			row.Position = UDim2.fromOffset(0, 34)
			row.Size = UDim2.new(1, 0, 0, TILE_H + 4)
			row.BackgroundTransparency = 1
			row.BorderSizePixel = 0
			row.ScrollingDirection = Enum.ScrollingDirection.X
			row.ScrollBarThickness = 6
			row.AutomaticCanvasSize = Enum.AutomaticSize.X
			row.CanvasSize = UDim2.new()
			row.ZIndex = 41
			row.Parent = section
			local rowLayout = Instance.new("UIListLayout")
			rowLayout.FillDirection = Enum.FillDirection.Horizontal
			rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
			rowLayout.Padding = UDim.new(0, 10)
			rowLayout.Parent = row
			for _, option in ipairs(slot.options) do
				tile(row, slot.id, option)
			end
		end
	end

	require(script.Parent.PanelTabs).attach(backdrop, "flair", deps.playClickSfx) -- shared tab strip + Back
	OverlayManager.register("flair", function()
		stopStage()
		deps.popOut(backdrop, panel)
	end)
	local function openThisPanel()
		deps.playClickSfx()
		OverlayManager.closeAllExcept("flair")
		for slotId in pairs(selected) do selected[slotId] = nil end -- equipped options return to the stage
		previewingLabel.Text = ""
		refresh()
		deps.popIn(backdrop, panel)
		startStage()
	end
	OverlayManager.registerOpener("flair", openThisPanel)
	deps.openButton.MouseButton1Click:Connect(openThisPanel)
	closeButton.MouseButton1Click:Connect(function()
		deps.playClickSfx()
		stopStage()
		deps.popOut(backdrop, panel)
	end)
	deps.StateUpdatedRemote.OnClientEvent:Connect(function()
		task.defer(function()
			if backdrop.Visible then
				refresh()
			end
		end)
	end)
end

return FlairPanel
