--[[
	Client/Gameplay2.lua
	Gameplay v2, the rebuilt table screen (flag GAMEPLAY_V2, default on; the Concept T table is GAMEPLAY_V1, archived and still
	openable). New pieces are drawn with Client/TavernKit (plates, pills, gold box) over the candlelit table scene
	(Engine/TableSceneArt). Rects come from ONE pure function, Engine/Gameplay2Layout.rects, so layout and tests share it.

	No separate hit frames anywhere: Play Hand and Discard are the real buttons from the hub, restyled by TavernKit.skin and
	moved onto their rect, the Rank | Suit control and the deck click catcher are the real instances moved the same way. Server logic,
	scoring and remotes are untouched, as are PopupShield and InputGuard (the buttons keep every handler).
	Active only in phase "playing" on screens of at least 640 x 360.

	install{ root, handFrame, actionFrame, playButton, discardButton, deckWidget, selectedCount, firstCard, cards } -> { update(state), isActive() }
	Studio only: [ClickCheck] lines compare each control's real rect with its layout rect and warn above 4 px.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Engine = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine")
local Layout = require(Engine:WaitForChild("Gameplay2Layout"))
local CTLayout = require(Engine:WaitForChild("ConceptTLayout"))
local Flags = require(Engine:WaitForChild("FeatureFlags"))
local TableArt = require(Engine:WaitForChild("TableSceneArt"))
local Art = require(Engine:WaitForChild("ConceptTArt"))
local Style = require(Engine:WaitForChild("TavernStyle"))
local DeckCountText = require(Engine:WaitForChild("DeckCountText"))
local PlayMotion = require(Engine:WaitForChild("PlayMotion"))
local Kit = require(script.Parent.TavernKit)
local LayoutSwitch = require(script.Parent.LayoutSwitch)

local M = {}
local current = nil

-- the old play screen pieces this screen hides while it is up (same list the Concept T screen hid)
local HIDE = { "Sidebar", "SidebarBoard", "EdgeShadow", "PlayBoardPaint", "PlayBoardPaintBand", "PlayBoardPaintCap", "PlayBoardFiller", "BlessingChip", "PlayFeltShade", "PlayTableFront", "PlayTableBg", "PlayFloorShade", "HandRailLip", "PlayGrooveLip", "PlayRailBack", "PlayRailFront" }

local function place(g, r)
	g.Position = UDim2.fromOffset(r.x, r.y)
	g.Size = UDim2.fromOffset(r.w, r.h)
end

local function setText(box, text)
	local t = box:FindFirstChild("Value") or box:FindFirstChild("Word")
	if t and t.Text ~= text then t.Text = text end
	return t
end

function M.install(deps)
	local root = deps.root
	local layer = Instance.new("Frame")
	layer.Name = "Gameplay2"
	layer.BackgroundColor3 = Color3.fromRGB(Style.rgb("plateDark")[1], Style.rgb("plateDark")[2], Style.rgb("plateDark")[3]) -- plain dark brown until the scene loads
	layer.BorderSizePixel = 0
	layer.Size = UDim2.fromScale(1, 1)
	layer.ZIndex = 1
	layer.Visible = false
	layer.Active = false
	layer.Parent = root

	local scene = Instance.new("ImageLabel")
	scene.Name = "Scene"
	scene.BackgroundTransparency = 1
	scene.BorderSizePixel = 0
	scene.Active = false
	scene.Size = UDim2.fromScale(1, 1)
	scene.ScaleType = Enum.ScaleType.Crop
	scene.ZIndex = 1
	scene.Image = TableArt.table_play or ""
	scene.Parent = layer

	-- every drawn piece sits above the scene; the real buttons are lifted to Z_BTN
	local Z_UI, Z_BTN = 3, 6
	local bar = Kit.plate(layer, UDim2.fromOffset(100, 40)); bar.Name = "RoundBar"; bar.ZIndex = Z_UI
	local roundLabel = Instance.new("TextLabel")
	roundLabel.Name = "RoundName"
	roundLabel.BackgroundTransparency = 1
	roundLabel.Font = Enum.Font[Style.FONTS.title]
	roundLabel.TextSize = Style.TEXT.subtitle
	roundLabel.TextColor3 = Color3.fromRGB(Style.rgb("cream")[1], Style.rgb("cream")[2], Style.rgb("cream")[3])
	roundLabel.TextTransparency = 0
	roundLabel.TextStrokeTransparency = 0.2
	roundLabel.TextStrokeColor3 = Color3.fromRGB(Style.rgb("outline")[1], Style.rgb("outline")[2], Style.rgb("outline")[3])
	roundLabel.TextXAlignment = Enum.TextXAlignment.Left
	roundLabel.TextTruncate = Enum.TextTruncate.AtEnd
	roundLabel.ZIndex = Z_UI + 1
	roundLabel.Parent = layer
	local target = Kit.goldBox(layer, "Target 0"); target.Name = "TargetBox"; target.ZIndex = Z_UI + 1
	local tips = Kit.pill(layer, "Tips 0", "wood"); tips.Name = "TipsPill"; tips.ZIndex = Z_UI + 1
	local handsPill = Kit.pill(layer, "Hands 0", "green"); handsPill.Name = "HandsPill"; handsPill.ZIndex = Z_UI
	local discardsPill = Kit.pill(layer, "Discards 0", "wood"); discardsPill.Name = "DiscardsPill"; discardsPill.ZIndex = Z_UI
	local deckImg = Instance.new("ImageLabel")
	deckImg.Name = "DeckBook"
	deckImg.BackgroundTransparency = 1
	deckImg.BorderSizePixel = 0
	deckImg.Active = false
	deckImg.Image = Art.ct_deck_a or ""
	deckImg.ScaleType = Enum.ScaleType.Fit
	deckImg.ZIndex = Z_UI
	deckImg.Parent = layer
	local deckPill = Kit.pill(layer, "0 / 52", "wood"); deckPill.Name = "DeckCountPill"; deckPill.ZIndex = Z_UI
	for _, p in ipairs({ tips, handsPill, discardsPill, deckPill }) do -- a pill's word fills the whole pill and may be longer than 4 chars
		local w = p:FindFirstChild("Word")
		if w then w.TextSize = Style.TEXT.chip; w.TextScaled = false end
	end

	local active, lastState = false, nil
	local hiddenDeck, sortHost, actionHeld = {}, nil, nil
	local savedFan, savedFanOn = PlayMotion.FAN, PlayMotion.HAND_FAN_ENABLED
	local self = {}

	local function fanHand(on, h)
		if on then
			PlayMotion.FAN = CTLayout.fanProfile(h)
			PlayMotion.HAND_FAN_ENABLED = true
		else
			PlayMotion.FAN = savedFan
			PlayMotion.HAND_FAN_ENABLED = savedFanOn
		end
	end

	local function restoreOld()
		if actionHeld then
			local held = actionHeld
			actionHeld = nil
			LayoutSwitch.on(deps.actionFrame)
			deps.playButton.Size = UDim2.new(0, 200, 1, 0)
			deps.discardButton.Size = UDim2.new(0, 200, 1, 0)
			local cs = deps.actionFrame:FindFirstChild("CompactScale")
			if cs and held.scale then cs.Scale = held.scale end
			deps.actionFrame.Position = UDim2.new(deps.actionFrame.Position.X.Scale, deps.actionFrame.Position.X.Offset + 1, deps.actionFrame.Position.Y.Scale, deps.actionFrame.Position.Y.Offset)
		end
		for c in pairs(hiddenDeck) do c.Visible = true end
		hiddenDeck = {}
		if sortHost and sortHost.Parent then
			local sf = sortHost
			sortHost = nil
			LayoutSwitch.on(sf)
			sf.Size = UDim2.new(0, 214, 1, 0)
			sf.Position = UDim2.new()
			for _, k in ipairs(sf:GetChildren()) do
				if k.Name == "PlatePaint" and k:IsA("GuiObject") then k.Visible = true
				elseif k:IsA("TextLabel") then k.Visible = true
				elseif k.Name == "SortToggle" then
					k:SetAttribute("Flat", false)
					k.Size = UDim2.fromOffset(132, 28)
				end
			end
		end
	end

	local function sceneKey(state)
		local boss = state and state.bossModifier ~= nil and (state.round or 0) >= 3
		return boss and "table_boss" or "table_play"
	end

	local function apply()
		local size = root.AbsoluteSize
		local r = Layout.rects(size.X, size.Y)
		fanHand(true, size.Y)
		place(bar, r.bar)
		place(roundLabel, r.round)
		place(target, r.target); place(tips, r.tips)
		place(handsPill, r.playCount); place(discardsPill, r.discardCount)
		place(deckImg, r.deck); place(deckPill, r.deckCount)
		-- the real controls are the drawn controls: same instance, moved onto the layout rect
		local cs = deps.actionFrame:FindFirstChild("CompactScale")
		if not actionHeld then actionHeld = { scale = cs and cs.Scale or nil } end
		LayoutSwitch.off(deps.actionFrame)
		if cs then cs.Scale = 1 end
		place(deps.handFrame, CTLayout.handFor(r.hand, size.X, lastState and lastState.hand and #lastState.hand or 0))
		deps.actionFrame.Position = UDim2.fromOffset(r.play.x, r.play.y)
		deps.actionFrame.Size = UDim2.fromOffset(r.discard.x + r.discard.w - r.play.x, r.play.h)
		deps.playButton.Position = UDim2.fromOffset(0, 0)
		deps.playButton.Size = UDim2.fromOffset(r.play.w, r.play.h)
		deps.discardButton.Position = UDim2.fromOffset(r.discard.x - r.play.x, 0)
		deps.discardButton.Size = UDim2.fromOffset(r.discard.w, r.discard.h)
		deps.playButton.ZIndex = Z_BTN; deps.discardButton.ZIndex = Z_BTN
		if deps.playButton:GetAttribute("TavernKind") ~= "primary" then Kit.skin(deps.playButton, "Play Hand", "primary") end
		if deps.discardButton:GetAttribute("TavernKind") ~= "secondary" then Kit.skin(deps.discardButton, "Discard", "secondary") end
		-- Rank | Suit: one frame covering the two layout halves
		for _, c in ipairs(deps.actionFrame:GetChildren()) do
			if c:IsA("Frame") and c.LayoutOrder == 0 then
				LayoutSwitch.off(c)
				c.Size = UDim2.fromOffset(r.sortRank.w + r.sortSuit.w, r.sortRank.h)
				c.Position = UDim2.fromOffset(r.sortRank.x - r.play.x, r.sortRank.y - r.play.y)
				sortHost = c
				for _, k in ipairs(c:GetChildren()) do
					if k.Name == "PlatePaint" and k:IsA("GuiObject") then k.Visible = false
					elseif k:IsA("TextLabel") then k.Visible = false
					elseif k.Name == "SortToggle" then
						k:SetAttribute("Flat", true)
						k.Position = UDim2.fromOffset(0, 0)
						k.Size = UDim2.fromOffset(r.sortRank.w + r.sortSuit.w, r.sortRank.h)
						k.BackgroundTransparency = 0
					end
				end
			end
		end
		local dw = deps.deckWidget
		if dw then
			place(dw, r.deck)
			dw.AnchorPoint = Vector2.new(0, 0)
			dw.BackgroundTransparency = 1
			for _, c in ipairs(dw:GetChildren()) do
				if c.Name ~= "ClickCatcher" then
					if c:IsA("GuiObject") then
						if c.Visible then hiddenDeck[c] = true end
						c.Visible = false
					elseif c:IsA("UIStroke") then c.Enabled = false end
				end
			end
		end
	end

	local function shell(on)
		if on then
			for _, name in ipairs(HIDE) do
				local g = root:FindFirstChild(name)
				if g and g:IsA("GuiObject") then g.Visible = false end
			end
		end
		layer.Visible = on
	end

	function self.isActive() return active end

	function self.rects()
		local size = root.AbsoluteSize
		return Layout.rects(size.X, size.Y)
	end

	-- Studio only: the real controls against their layout rects
	function self.selfCheck()
		local size = root.AbsoluteSize
		local r = Layout.rects(size.X, size.Y)
		local origin = root.AbsolutePosition
		local sortToggle
		if sortHost then sortToggle = sortHost:FindFirstChild("SortToggle") end
		local list = {
			{ "PlayHand", deps.playButton, r.play }, { "Discard", deps.discardButton, r.discard },
			{ "Deck", deps.deckWidget and deps.deckWidget:FindFirstChild("ClickCatcher"), r.deck },
			{ "SortRank", sortToggle and sortToggle:FindFirstChild("SortRank", true), r.sortRank },
			{ "SortSuit", sortToggle and sortToggle:FindFirstChild("SortSuit", true), r.sortSuit },
		}
		for _, p in ipairs(list) do
			local b, want = p[2], p[3]
			if b and b.Parent then
				local cx = b.AbsolutePosition.X - origin.X + b.AbsoluteSize.X / 2
				local cy = b.AbsolutePosition.Y - origin.Y + b.AbsoluteSize.Y / 2
				local dx, dy = cx - (want.x + want.w / 2), cy - (want.y + want.h / 2)
				local line = string.format("[ClickCheck v2] %s abs=%d,%d size=%dx%d layout=%d,%d,%dx%d off=%d,%d", p[1], math.floor(b.AbsolutePosition.X), math.floor(b.AbsolutePosition.Y),
					math.floor(b.AbsoluteSize.X), math.floor(b.AbsoluteSize.Y), math.floor(want.x), math.floor(want.y), math.floor(want.w), math.floor(want.h), math.floor(dx), math.floor(dy))
				if math.abs(dx) > 4 or math.abs(dy) > 4 then warn(line) else print(line) end
			end
		end
	end

	function self.update(state)
		lastState = state or lastState
		local size = root.AbsoluteSize
		local on = Flags.gameplay() == 2 and lastState ~= nil and lastState.phase == "playing" and deps.handFrame.Visible and Layout.fits(size.X, size.Y)
		active = on
		shell(on)
		if not on then fanHand(false, size.Y); restoreOld(); return end
		local key = sceneKey(lastState)
		local img = TableArt[key] or ""
		if scene.Image ~= img then scene.Image = img end
		roundLabel.Text = string.format("Night %d, Round %d", math.floor(lastState.night or 1), math.floor(lastState.round or 1))
		setText(target, string.format("Target %d", math.floor(lastState.targetScore or 0)))
		setText(tips, string.format("Tips %d", math.floor(lastState.tips or 0)))
		setText(handsPill, string.format("Hands %d", math.floor(lastState.handsRemaining or 0)))
		setText(discardsPill, string.format("Discards %d", math.floor(lastState.discardsRemaining or 0)))
		local remaining = 0
		for _, suit in pairs(lastState.deckCounts or {}) do
			for _, n in pairs(suit) do remaining = remaining + (tonumber(n) or 0) end
		end
		setText(deckPill, DeckCountText.spaced(remaining, lastState.deckView))
		apply()
		if not self.checked and game:GetService("RunService"):IsStudio() then
			self.checked = true
			task.delay(1.5, function() pcall(self.selfCheck) end)
		end
		if deps.selectedCount then -- the guided first hand hint (Engine/GuidedHand), display only
			pcall(function()
				require(script.Parent.GuidedHint).update(layer, lastState, deps.selectedCount(), deps.firstCard and deps.firstCard(), deps.playButton, Layout.rects(size.X, size.Y))
			end)
		end
	end

	root:GetPropertyChangedSignal("AbsoluteSize"):Connect(function() if active then apply() end end)
	-- other modules rewrite their own Position now and then; this keeps the v2 layout the last word (no per frame work)
	task.spawn(function()
		while layer.Parent do
			task.wait(0.25)
			if active then pcall(shell, true); pcall(apply) end
		end
	end)
	current = self
	return self
end

function M.isActive()
	return current ~= nil and current.isActive()
end

function M.update(state)
	if current then current.update(state) end
end

return M
