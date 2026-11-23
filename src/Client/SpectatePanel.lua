--[[
	Client/SpectatePanel.lua
	SPECTATE (Engine/Spectate.lua), same server only. Two roles in one module:

	WATCHER: a read-only mirrored table driven only by the server's whitelisted event stream (remote SpectateStream):
	  the watched player's name, aura crest, stake and road, Night and round, the target and the score bar, their hand as
	  small card faces, their Patrons, the Boss rule chip, and the last hand played with its score. Their Flair shows too
	  (score number color, a Finisher burst on big hands) unless the viewer has Reduce Flashing, Reduce Motion or Reduce Shake
	  on. There is a Stop Watching button (always visible), a Block button and six preset reactions (3 second cooldown, shown
	  as floating icons). A spectator has no way to send game input: the only remote used here is SpectateAction.
	  This is a simplified mirror (it draws its own small card row and score line instead of re-using the full table
	  renderers), which keeps it phone friendly and impossible to confuse with the player's own table.

	WATCHED PLAYER: a small "eye N watching" badge near the sidebar header (a gentle pop when someone joins, static under
	Reduce Motion), a tiny name row on hover, and the reaction icons that spectators send.

	init(deps): { screenGui, particleBurst }   (the Watch buttons live in the Friend Presence card, Client/PhaseB.lua)
]]

local Layers = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("Layers"))
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local SpectatePanel = {}

local CREAM = Color3.fromRGB(250, 235, 200)
local GOLD = Color3.fromRGB(222, 182, 104)
local INK = Color3.fromRGB(60, 40, 22)
local WOOD = Color3.fromRGB(86, 58, 34)

local SUIT_GLYPH = { Hearts = "♥", Diamonds = "♦", Clubs = "♣", Spades = "♠" }
local SUIT_RED = { Hearts = true, Diamonds = true }
local RANK_TEXT = { [11] = "J", [12] = "Q", [13] = "K", [14] = "A" }

function SpectatePanel.init(deps)
	local Engine = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine")
	local NameFit = require(Engine:WaitForChild("NameFit"))
	local Spectate = require(Engine:WaitForChild("Spectate"))
	local SpectateLayout = require(Engine:WaitForChild("SpectateLayout"))
	local Flair = require(Engine:WaitForChild("Flair"))
	local Patrons = require(Engine:WaitForChild("Patrons"))
	local ClientSettings = require(script.Parent.ClientSettings)
	local FlairFX = require(script.Parent.FlairFX)
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local ActionRemote = remotes:WaitForChild("SpectateAction")
	local StreamRemote = remotes:WaitForChild("SpectateStream")
	local gui = deps.screenGui

	local function calm()
		return ClientSettings.get("reduceShake") == true
	end

	local function label(parent, props)
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Font = Enum.Font.GothamBold
		l.TextColor3 = CREAM
		l.TextTransparency = 0
		l.TextStrokeTransparency = 1
		l.TextSize = 15
		l.ZIndex = Layers.effect + 31
		for k, v in pairs(props) do
			l[k] = v
		end
		l.Parent = parent
		return l
	end

	-- ===== the watcher's mirrored table =====
	local overlay = Instance.new("Frame")
	overlay.Name = "SpectateOverlay"
	overlay.AnchorPoint = Vector2.new(0.5, 0)
	overlay.Position = UDim2.new(0.5, 0, 0, 12)
	overlay.Size = UDim2.new(0.9, 0, 0, SpectateLayout.HEIGHT)
	overlay.BackgroundColor3 = Color3.fromRGB(34, 24, 16)
	overlay.BackgroundTransparency = 0.05
	overlay.BorderSizePixel = 0
	overlay.Visible = false
	overlay.ZIndex = Layers.effect + 30
	overlay.Parent = gui
	local sizeLimit = Instance.new("UISizeConstraint")
	sizeLimit.MaxSize = Vector2.new(SpectateLayout.WIDTH_MAX, SpectateLayout.HEIGHT)
	sizeLimit.Parent = overlay
	local oc = Instance.new("UICorner")
	oc.CornerRadius = UDim.new(0, 14)
	oc.Parent = overlay
	-- dark wood frame (calm, low contrast) and a wood header strip with a thin gold line under it, like the other panels
	local os_ = Instance.new("UIStroke")
	os_.Color = Color3.fromRGB(104, 70, 40)
	os_.Thickness = 6
	os_.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	os_.Parent = overlay
	local header = Instance.new("Frame")
	header.Name = "HeaderStrip"
	header.Position = UDim2.fromOffset(0, 0)
	header.Size = UDim2.new(1, 0, 0, 56)
	header.BackgroundColor3 = Color3.fromRGB(96, 66, 38)
	header.BorderSizePixel = 0
	header.Active = false
	header.ZIndex = Layers.effect + 31 -- created before the title and sub line, so they draw on it
	header.Parent = overlay
	local hc = Instance.new("UICorner")
	hc.CornerRadius = UDim.new(0, 14)
	hc.Parent = header
	local headLine = Instance.new("Frame")
	headLine.Name = "HeaderLine"
	headLine.Position = UDim2.fromOffset(0, 56)
	headLine.Size = UDim2.new(1, 0, 0, 2)
	headLine.BackgroundColor3 = GOLD
	headLine.BorderSizePixel = 0
	headLine.Active = false
	headLine.ZIndex = Layers.effect + 31
	headLine.Parent = overlay

	local title = label(overlay, { Size = UDim2.new(1, -24, 0, 28), Position = UDim2.fromOffset(12, 4), TextSize = 22, TextColor3 = CREAM, TextXAlignment = Enum.TextXAlignment.Left, Text = "Watching" })
	local sub = label(overlay, { Size = UDim2.new(1, -24, 0, 20), Position = UDim2.fromOffset(12, 32), Font = Enum.Font.GothamMedium, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left, Text = "" })

	-- one exit only: the parchment Leave button at the bottom (the red Stop was a second copy of it)

	-- score line
	local barBack = Instance.new("Frame")
	barBack.Position = UDim2.fromOffset(12, 62)
	barBack.Size = UDim2.new(1, -24, 0, 22)
	barBack.BackgroundColor3 = Color3.fromRGB(70, 52, 36)
	barBack.BorderSizePixel = 0
	barBack.ZIndex = Layers.effect + 31
	barBack.Parent = overlay
	local bc = Instance.new("UICorner")
	bc.CornerRadius = UDim.new(0, 11)
	bc.Parent = barBack
	local barFill = Instance.new("Frame")
	barFill.Size = UDim2.fromScale(0, 1)
	barFill.BackgroundColor3 = GOLD
	barFill.BorderSizePixel = 0
	barFill.ZIndex = Layers.effect + 32
	barFill.Parent = barBack
	local bfc = Instance.new("UICorner")
	bfc.CornerRadius = UDim.new(0, 11)
	bfc.Parent = barFill
	local barText = label(barBack, { Size = UDim2.fromScale(1, 1), ZIndex = Layers.effect + 33, TextColor3 = INK, TextSize = 14, Text = "" })

	local lastPlayed = label(overlay, { Size = UDim2.new(1, -24, 0, 30), Position = UDim2.fromOffset(12, 86), TextSize = 20, Text = "" })

	-- hand row
	local handRow = Instance.new("Frame")
	handRow.Position = UDim2.fromOffset(12, 122)
	handRow.Size = UDim2.new(1, -24, 0, 84)
	handRow.BackgroundTransparency = 1
	handRow.ZIndex = Layers.effect + 31
	handRow.Parent = overlay
	local handLayout = Instance.new("UIListLayout")
	handLayout.FillDirection = Enum.FillDirection.Horizontal
	handLayout.SortOrder = Enum.SortOrder.LayoutOrder
	handLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	handLayout.Padding = UDim.new(0, 4)
	handLayout.Parent = handRow

	-- patrons and the boss rule chip
	local patronRow = label(overlay, { Size = UDim2.new(1, -24, 0, 28), Position = UDim2.fromOffset(12, 212), TextSize = 22, TextXAlignment = Enum.TextXAlignment.Left, Text = "" })
	local bossChip = label(overlay, { Size = UDim2.new(1, -24, 0, 22), Position = UDim2.fromOffset(12, 242), Font = Enum.Font.GothamMedium, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Text = "" })

	-- reactions: six presets
	local reactRow = Instance.new("Frame")
	reactRow.Position = UDim2.new(0, 12, 1, SpectateLayout.rects(0).react[2] - SpectateLayout.HEIGHT)
	reactRow.Size = UDim2.new(1, -24, 0, SpectateLayout.REACT_H)
	reactRow.BackgroundTransparency = 1
	reactRow.ZIndex = Layers.effect + 31
	reactRow.Parent = overlay
	local reactLayout = Instance.new("UIListLayout")
	reactLayout.FillDirection = Enum.FillDirection.Horizontal
	reactLayout.SortOrder = Enum.SortOrder.LayoutOrder
	reactLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	reactLayout.Padding = UDim.new(0, 8)
	reactLayout.Parent = reactRow
	local lastReact = -1e9
	local reactButtons = {}
	for i, emote in ipairs(Spectate.Emotes) do
		local b = Instance.new("TextButton")
		b.LayoutOrder = i
		b.Size = UDim2.fromOffset(44, 34)
		b.Font = Enum.Font.GothamBold
		b.TextSize = 22
		b.TextColor3 = CREAM
		b.BackgroundColor3 = WOOD
		b.Text = ""
		b.ZIndex = Layers.effect + 32
		b.Parent = reactRow
		-- emoji glyph in its own label so painted art (SpectateArt, category "spectate") can replace it once generated
		local glyph = Instance.new("TextLabel")
		glyph.Size = UDim2.fromScale(1, 1)
		glyph.BackgroundTransparency = 1
		glyph.Font = Enum.Font.GothamBold
		glyph.TextSize = 22
		glyph.TextColor3 = CREAM
		glyph.Text = emote.icon
		glyph.ZIndex = Layers.effect + 33
		glyph.Parent = b
		pcall(function()
			require(script.Parent.ArtIcon).apply(b, "spectate", emote.id, glyph, { cornerRadius = 8, zIndex = Layers.effect + 34 })
		end)
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, 8)
		c.Parent = b
		b.MouseButton1Click:Connect(function()
			if os.clock() - lastReact < Spectate.REACTION_COOLDOWN then
				return -- the server enforces it too; this keeps the buttons honest
			end
			lastReact = os.clock()
			ActionRemote:FireServer("react", emote.id)
			for _, rb in ipairs(reactButtons) do rb.BackgroundTransparency = 0.5 end
			task.delay(Spectate.REACTION_COOLDOWN, function()
				for _, rb in ipairs(reactButtons) do rb.BackgroundTransparency = 0 end
			end)
		end)
		reactButtons[#reactButtons + 1] = b
	end

	-- floating reaction icons (shown to spectators and to the watched player)
	local function floatReaction(icon, from)
		local f = Instance.new("TextLabel")
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Position = UDim2.new(0.15 + math.random() * 0.7, 0, 0.7, 0)
		f.Size = UDim2.fromOffset(60, 60)
		f.BackgroundTransparency = 1
		f.Font = Enum.Font.GothamBold
		f.TextSize = 40
		f.Text = icon
		f.TextTransparency = 0
		f.TextStrokeTransparency = 1
		f.ZIndex = Layers.effect + 70
		f.Active = false
		f.Parent = gui
		if calm() then
			task.delay(1.2, function() f:Destroy() end) -- static under calm mode: no rising motion
			return
		end
		local tween = TweenService:Create(f, TweenInfo.new(1.6, Enum.EasingStyle.Quad), { Position = UDim2.new(f.Position.X.Scale, 0, 0.35, 0), TextTransparency = 1 })
		tween:Play()
		tween.Completed:Connect(function() f:Destroy() end)
		_ = from
	end

	local function cardFace(card, order)
		local f = Instance.new("Frame")
		f.LayoutOrder = order
		f.Size = UDim2.fromOffset(52, 78)
		f.BackgroundColor3 = Color3.fromRGB(250, 244, 230)
		f.BorderSizePixel = 0
		f.ZIndex = Layers.effect + 32
		f.Parent = handRow
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, 6)
		c.Parent = f
		local color = SUIT_RED[card.suit] and Color3.fromRGB(190, 40, 40) or Color3.fromRGB(30, 30, 40)
		label(f, { Size = UDim2.new(1, 0, 0, 30), Position = UDim2.fromOffset(0, 6), TextColor3 = color, TextSize = 24, ZIndex = Layers.effect + 33, Text = RANK_TEXT[card.rank] or tostring(card.rank) })
		label(f, { Size = UDim2.new(1, 0, 0, 34), Position = UDim2.fromOffset(0, 36), TextColor3 = color, TextSize = 28, ZIndex = Layers.effect + 33, Text = SUIT_GLYPH[card.suit] or "?" })
		if card.garnish or card.special or card.stamp then
			local dot = Instance.new("Frame")
			dot.Size = UDim2.fromOffset(10, 10)
			dot.Position = UDim2.new(1, -13, 0, 3)
			dot.BackgroundColor3 = GOLD
			dot.BorderSizePixel = 0
			dot.ZIndex = Layers.effect + 34
			dot.Parent = f
			local dc = Instance.new("UICorner")
			dc.CornerRadius = UDim.new(1, 0)
			dc.Parent = dot
		end
	end

	local watchedFlair = {}
	local function scoreColor()
		local def = watchedFlair.scoreNumbers and Flair.getById(watchedFlair.scoreNumbers)
		if def and def.color and not calm() then
			return Color3.fromRGB(def.color[1], def.color[2], def.color[3])
		end
		return CREAM
	end

	local function applySnapshot(e)
		overlay.Visible = true
		watchedFlair = e.flair or {}
		title.Text = "Watching " .. ((e.crest and e.crest ~= "") and (e.crest .. " ") or "") .. NameFit.clip(e.name or "a friend", 22)
		local bits = {}
		if e.stakeName then bits[#bits + 1] = e.stakeName end
		if e.roadName then bits[#bits + 1] = e.roadName end
		if e.night then bits[#bits + 1] = "Night " .. math.floor(e.night) .. (e.round and (", Round " .. math.floor(e.round)) or "") end
		if e.handsRemaining then bits[#bits + 1] = math.floor(e.handsRemaining) .. " hands" end
		if e.discardsRemaining then bits[#bits + 1] = math.floor(e.discardsRemaining) .. " discards" end
		sub.Text = table.concat(bits, "  |  ")
		local target = math.max(1, e.targetScore or 1)
		local score = e.roundScore or 0
		barFill.Size = UDim2.fromScale(math.clamp(score / target, 0, 1), 1)
		barText.Text = string.format("%d / %d", math.floor(score), math.floor(target))
		for _, child in ipairs(handRow:GetChildren()) do
			if child:IsA("Frame") then child:Destroy() end
		end
		for i, card in ipairs(e.hand or {}) do cardFace(card, i) end
		local icons = {}
		for _, id in ipairs(e.patrons or {}) do
			local def = Patrons.getById(id)
			icons[#icons + 1] = def and def.icon or "🙂"
		end
		patronRow.Text = #icons > 0 and (table.concat(icons, " ")) or "No Patrons yet"
		bossChip.Text = e.boss and ("👑 " .. (e.boss.name or "Boss") .. ": " .. (e.boss.text or "")) or ""
	end

	local function applyHandPlayed(e)
		lastPlayed.TextColor3 = scoreColor()
		lastPlayed.Text = string.format("%s  +%s", e.handName or "Hand", tostring(math.floor(e.score or 0)))
		-- the watched player's Finisher on big hands, only when the viewer allows motion
		local big = e.legendary or ({ ["Flush"] = true, ["Full House"] = true, ["Four of a Kind"] = true, ["Straight Flush"] = true })[e.handName]
		local def = watchedFlair.finisher and Flair.getById(watchedFlair.finisher)
		if big and def and deps.particleBurst then
			local pos = UDim2.fromOffset(overlay.AbsolutePosition.X + overlay.AbsoluteSize.X / 2, overlay.AbsolutePosition.Y + 100)
			FlairFX.preview(deps.particleBurst, "finisher", def, pos)
		end
	end

	local function stopWatching()
		overlay.Visible = false
		lastPlayed.Text = ""
		watchedFlair = {}
	end

	-- Leave: the one exit, a parchment button at the bottom centre (tells the server, hides the overlay, the Menu is underneath)
	local leaveButton = Instance.new("TextButton")
	leaveButton.Name = "LeaveButton"
	leaveButton.AnchorPoint = Vector2.new(0.5, 1)
	leaveButton.Position = UDim2.new(0.5, 0, 1, -SpectateLayout.EDGE)
	leaveButton.Size = UDim2.fromOffset(SpectateLayout.LEAVE_W, SpectateLayout.LEAVE_H)
	leaveButton.Font = Enum.Font.GothamBold
	leaveButton.TextSize = 15
	leaveButton.TextColor3 = INK
	leaveButton.BackgroundColor3 = Color3.fromRGB(236, 220, 184)
	leaveButton.AutoButtonColor = true
	leaveButton.Text = "Leave"
	leaveButton.ZIndex = Layers.effect + 32
	leaveButton.Parent = overlay
	local lc = Instance.new("UICorner")
	lc.CornerRadius = UDim.new(0, 8)
	lc.Parent = leaveButton
	local ls = Instance.new("UIStroke")
	ls.Color = GOLD
	ls.Thickness = 1.5
	ls.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	ls.Parent = leaveButton
	local function leave()
		ActionRemote:FireServer("stop")
		stopWatching()
	end
	leaveButton.MouseButton1Click:Connect(leave)
	-- the other exits: the round X (CloseX) and Escape (PopupDismiss) both mean Leave; a click on the dark area stays off (the overlay is a strip)
	pcall(function() require(script.Parent.CloseX).attach(overlay, leave, { z = Layers.effect + 33 }) end)
	pcall(function()
		require(script.Parent.PopupDismiss).attach(overlay, { policy = "dismiss", close = leave, panel = overlay, outside = false, button = true })
	end)

	-- ===== the watched player's badge =====
	local badge = Instance.new("TextButton")
	badge.Name = "WatchersBadge"
	badge.AutoButtonColor = false
	badge.AnchorPoint = Vector2.new(0, 0)
	badge.Position = UDim2.new(0, 12, 0, 96)
	badge.Size = UDim2.fromOffset(150, 30)
	badge.BackgroundColor3 = Color3.fromRGB(40, 30, 22)
	badge.BackgroundTransparency = 0.1
	badge.Font = Enum.Font.GothamBold
	badge.TextSize = 14
	badge.TextColor3 = CREAM
	badge.TextTransparency = 0
	badge.TextStrokeTransparency = 1
	badge.Text = ""
	badge.Visible = false
	badge.ZIndex = 90
	badge.Parent = gui
	local bdc = Instance.new("UICorner")
	bdc.CornerRadius = UDim.new(0, 15)
	bdc.Parent = badge
	local bds = Instance.new("UIStroke")
	bds.Color = GOLD
	bds.Thickness = 1.5
	bds.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	bds.Parent = badge
	local namesLabel = Instance.new("TextLabel")
	namesLabel.Size = UDim2.fromOffset(190, 22)
	namesLabel.Position = UDim2.fromOffset(0, 34)
	namesLabel.BackgroundColor3 = Color3.fromRGB(40, 30, 22)
	namesLabel.BackgroundTransparency = 0.1
	namesLabel.Font = Enum.Font.Gotham
	namesLabel.TextSize = 14
	namesLabel.TextColor3 = CREAM
	namesLabel.TextTransparency = 0
	namesLabel.TextStrokeTransparency = 1
	namesLabel.TextTruncate = Enum.TextTruncate.AtEnd
	namesLabel.Visible = false
	namesLabel.ZIndex = 91
	namesLabel.Parent = badge
	local nlc = Instance.new("UICorner")
	nlc.CornerRadius = UDim.new(0, 8)
	nlc.Parent = namesLabel
	badge.MouseEnter:Connect(function() namesLabel.Visible = badge.Visible and namesLabel.Text ~= "" end)
	badge.MouseLeave:Connect(function() namesLabel.Visible = false end)

	-- clicking the badge lists who is watching, each with a Block button (blocked players can never watch you again)
	local list = Instance.new("Frame")
	list.Name = "WatchersList"
	list.Position = UDim2.fromOffset(0, 34)
	list.Size = UDim2.fromOffset(210, 0)
	list.AutomaticSize = Enum.AutomaticSize.Y
	list.BackgroundColor3 = Color3.fromRGB(40, 30, 22)
	list.BackgroundTransparency = 0.05
	list.Visible = false
	list.ZIndex = 92
	list.Parent = badge
	local lc = Instance.new("UICorner")
	lc.CornerRadius = UDim.new(0, 8)
	lc.Parent = list
	local ll = Instance.new("UIListLayout")
	ll.SortOrder = Enum.SortOrder.LayoutOrder
	ll.Padding = UDim.new(0, 2)
	ll.Parent = list
	-- the equipped Card Set's panel fill, edge and ink (7:1) on the watcher overlay, the badge, the names tip and the viewers list,
	-- and its plate on Leave; classic keeps the dark wood. Colours only: no layout, no tween.
	pcall(function()
		local Skin = require(script.Parent.PopupSkin)
		Skin.dark(overlay, os_, { { title, CREAM }, { sub, CREAM } }, { plate = Color3.fromRGB(34, 24, 16), edge = Color3.fromRGB(104, 70, 40) })
		Skin.dark(badge, bds, { { badge, CREAM } }, { plate = Color3.fromRGB(40, 30, 22), edge = GOLD })
		Skin.dark(namesLabel, nil, { { namesLabel, CREAM } }, { plate = Color3.fromRGB(40, 30, 22) })
		Skin.dark(list, nil, {}, { plate = Color3.fromRGB(40, 30, 22) })
		local Kit = require(script.Parent.TavernKit)
		Kit.setPlateButton(leaveButton, "primary")
		if leaveButton:GetAttribute("BasePiece") then leaveButton.TextColor3 = CREAM end
	end)
	local viewersNow = {}
	local function rebuildList()
		for _, child in ipairs(list:GetChildren()) do
			if child:IsA("GuiObject") then child:Destroy() end
		end
		for i, v in ipairs(viewersNow) do
			local row = Instance.new("Frame")
			row.LayoutOrder = i
			row.Size = UDim2.new(1, 0, 0, 30)
			row.BackgroundTransparency = 1
			row.ZIndex = 93
			row.Parent = list
			label(row, { Size = UDim2.new(1, -70, 1, 0), Position = UDim2.fromOffset(6, 0), Font = Enum.Font.GothamMedium, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Text = NameFit.clip(v.name, 24), ZIndex = 94 })
			local block = Instance.new("TextButton")
			block.Size = UDim2.fromOffset(58, 24)
			block.AnchorPoint = Vector2.new(1, 0.5)
			block.Position = UDim2.new(1, -4, 0.5, 0)
			block.Font = Enum.Font.GothamBold
			block.TextSize = 14
			block.TextColor3 = CREAM
			block.BackgroundColor3 = Color3.fromRGB(150, 60, 50)
			block.Text = "Block"
			block.ZIndex = 94
			block.Parent = row
			local bc2 = Instance.new("UICorner")
			bc2.CornerRadius = UDim.new(0, 6)
			bc2.Parent = block
			block.MouseButton1Click:Connect(function()
				ActionRemote:FireServer("block", v.id)
			end)
		end
	end
	badge.MouseButton1Click:Connect(function()
		list.Visible = not list.Visible and #viewersNow > 0
		if list.Visible then rebuildList() end
	end)
	local lastCount = 0
	local function applyWatchers(e)
		local count = math.floor(e.count or 0)
		badge.Visible = count > 0
		badge.Text = "👁 " .. count .. " watching"
		local clipped = {}
		for i, n in ipairs(e.names or {}) do clipped[i] = NameFit.clip(n, 16) end
		namesLabel.Text = table.concat(clipped, ", ")
		viewersNow = type(e.viewers) == "table" and e.viewers or {}
		if list.Visible then rebuildList() end
		if count == 0 then list.Visible = false end
		if count > lastCount and not calm() then -- a gentle pop when someone joins (static under Reduce Motion)
			badge.Size = UDim2.fromOffset(168, 34)
			TweenService:Create(badge, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Size = UDim2.fromOffset(150, 30) }):Play()
		end
		lastCount = count
	end

	StreamRemote.OnClientEvent:Connect(function(event)
		if type(event) ~= "table" then return end
		pcall(function()
			if event.kind == "snapshot" then
				applySnapshot(event)
			elseif event.kind == "handPlayed" then
				applyHandPlayed(event)
			elseif event.kind == "roundResult" then
				lastPlayed.Text = event.won and ("✨ " .. (event.banner or "Round cleared")) or ("💤 " .. (event.banner or "Run over"))
			elseif event.kind == "reaction" then
				floatReaction(event.icon or "🎉", event.from)
			elseif event.kind == "watchers" then
				applyWatchers(event)
			elseif event.kind == "ended" then
				stopWatching()
			end
		end)
	end)
end

return SpectatePanel
