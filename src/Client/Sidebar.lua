--[[
	Client/Sidebar.lua
	LAYOUT FEATURE 1: the always-visible left-side column showing round/blind
	info, tips, hands/discards remaining, the Patron-slot row, and the live
	score preview. Replaces the old full-width top status bar, which had
	started colliding with the top-right corner icon buttons as more got
	added (a real bug -- the "Hands" label was getting cut off). Genre peers
	keep this info in a dedicated left-side column instead of a top bar, so
	this moves the same data there and leaves the whole top edge free for
	the corner icon buttons with no shared space to collide over.

	Extracted out of init.client.lua as part of splitting the client script
	into smaller, per-feature files. SIDEBAR_WIDTH is consumed as a dep by
	Client/MessageBanner.lua and Client/Shop.lua, so this module must be
	required BEFORE either of those. Every label here is live-updated
	elsewhere: nightRoundLabel/blindInfoLabel/scoreLabel/tipsLabel/
	handsDiscardsLabel/patronsCountLabel/the patronSlots array are all set
	inside render() (still inline in init.client.lua), and
	scorePreviewLabel/scorePreviewBox are driven by refreshScorePreview()
	(also still inline). All of those come back out of the require() call
	so the rest of the script can keep updating them.

	deps fields:
		root        -- Frame, the sidebar's parent
		polishPanel  -- function(instance, radius)
		roundCorner  -- function(instance, radius)
		Patrons      -- the Patrons engine module (needs #Patrons.Definitions)

	SIDEBAR REDO (Tavern Map style): the column is now ONE parchment notice
	board (ContentArt hud/sidebar_board, Crop, flat parchment fallback) with
	sections separated by the flourish divider image. The labels init.client.lua
	writes to (scoreLabel, tipsLabel, handsDiscardsLabel) are kept as hidden data
	labels: a Text-changed handler parses each one into the visible readouts
	(big score + progress bar, icons, Hands/Discards columns), so render() is
	unchanged. nightRoundLabel, blindInfoLabel (restyled to dark ink),
	patronsCountLabel and scorePreviewLabel are shown directly. Text is dark ink
	(60,40,22) with a faint parchment stroke. Patron seats sit in one
	framed inset (double-ring medallions). Icons (coin_purse, hands_cards, discard_bin,
	target_score) fall back to emoji. Dividers hide on short screens.

	Returns:
		{
			SIDEBAR_WIDTH = 240,
			sidebar = Frame,
			nightRoundLabel = TextLabel,
			blindInfoLabel = TextLabel,
			scoreLabel = TextLabel,
			tipsLabel = TextLabel,
			tipsBox = Frame,
			handsDiscardsLabel = TextLabel,
			handsDiscardsBox = Frame,
			patronsCountLabel = TextLabel,
			patronSlots = { [i] = { frame = Frame, label = TextLabel } },
			MAX_SIDEBAR_PATRON_SLOTS = 14,
			scorePreviewBox = Frame,
			scorePreviewLabel = TextLabel,
			setRunModeBadge = function(isDaily, dailyDateKey, isWeekly, weeklyDateKey, isSeeded, seedCode),
		}

	PHASE 16: setDailyBadge was renamed to setRunModeBadge and generalized
	to cover all 3 seeded-run modes (Daily/Weekly/Seed Code) sharing the
	one badge box -- only one of the 3 is ever true for a given run, same
	"at most one seedMode" guarantee Server/init.server.lua's
	startNewSession keeps, so one shared box (swapping color/text/icon)
	is simpler than 3 separate boxes that would always show at most one
	visible anyway.

	POLISH PASS: tipsBox/handsDiscardsBox (previously kept private to this
	module) now come back out too -- render() in init.client.lua pulses
	them (VisualHelpers.lua's pulseFrame) whenever Tips/Hands/Discards
	actually change, so gaining or spending something here gets a visible
	flash instead of the number just silently changing.
]]

return function(deps)
	local root = deps.root
	local polishPanel = deps.polishPanel
	local roundCorner = deps.roundCorner
	local Patrons = deps.Patrons

	local ContentArt = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("ContentArt"))
	local PanelArt = require(script.Parent.PanelArt)

	local SIDEBAR_WIDTH = 240
	local INK = Color3.fromRGB(60, 40, 22)
	local PARCH_STROKE = Color3.fromRGB(240, 222, 180)
	local PARCHMENT = Color3.fromRGB(226, 202, 156)
	local TAG_PARCHMENT = Color3.fromRGB(236, 216, 172)
	local GOLD = Color3.fromRGB(222, 182, 104)
	local BOX_COLOR = Color3.fromRGB(26, 17, 10)
	local Z = 3 -- content above the board's ornaments

	local function hud(key)
		return ContentArt.getImageId("hud", key)
	end

	-- ===== The board: one parchment panel behind everything =====
	local board = Instance.new("Frame")
	board.Name = "SidebarBoard"
	board.Size = UDim2.new(0, SIDEBAR_WIDTH, 1, 0)
	board.BackgroundColor3 = PARCHMENT -- flat fallback when the art is missing
	board.BorderSizePixel = 0
	board.ZIndex = 1
	board.Parent = root
	polishPanel(board, 8)
	-- The board art has a dark half-arch across its top. Push the art up and
	-- clip it so the arch is cropped away instead of showing as a stray shape.
	board.ClipsDescendants = true
	local boardArt = PanelArt.add(board, { category = "hud", key = "sidebar_board", zIndex = 1 })
	if boardArt then
		boardArt.Position = UDim2.new(0, 0, -0.14, 0)
		boardArt.Size = UDim2.new(1, 0, 1.14, 0)
	end

	-- painted play board behind the rows (Client/PlayBoardPaint.lua, step C1); the flat board stays when its art does not load
	pcall(function()
		require(script.Parent.PlayBoardPaint).install({ root = root, board = board, boardArt = boardArt, width = SIDEBAR_WIDTH, fill = PARCHMENT })
	end)

	local sidebar = Instance.new("Frame")
	sidebar.Name = "Sidebar"
	sidebar.Size = UDim2.new(0, SIDEBAR_WIDTH, 1, 0)
	sidebar.BackgroundTransparency = 1
	sidebar.BorderSizePixel = 0
	sidebar.ZIndex = 2
	sidebar.Parent = root

	do
		-- Soft shadow strip on the board's right edge (fades out into the room).
		local edgeShadow = Instance.new("Frame")
		edgeShadow.Name = "EdgeShadow"
		edgeShadow.Position = UDim2.new(0, SIDEBAR_WIDTH, 0, 0)
		edgeShadow.Size = UDim2.new(0, 18, 1, 0)
		edgeShadow.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
		edgeShadow.BorderSizePixel = 0
		edgeShadow.ZIndex = 1
		edgeShadow.Parent = root
		local fade = Instance.new("UIGradient")
		fade.Transparency = NumberSequence.new(0.45, 1)
		fade.Parent = edgeShadow
	end

	local sidebarPadding = Instance.new("UIPadding")
	-- Top 70px is Roblox's own system UI; the player medallion sits just under it (74..135).
	sidebarPadding.PaddingTop = UDim.new(0, 140)
	sidebarPadding.PaddingLeft = UDim.new(0, 12)
	sidebarPadding.PaddingRight = UDim.new(0, 12)
	sidebarPadding.Parent = sidebar

	local sidebarLayout = Instance.new("UIListLayout")
	sidebarLayout.FillDirection = Enum.FillDirection.Vertical
	sidebarLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	sidebarLayout.SortOrder = Enum.SortOrder.LayoutOrder
	sidebarLayout.Padding = UDim.new(0, 6)
	sidebarLayout.Parent = sidebar

	-- ===== Helpers =====
	local function ink(label, size)
		label.Font = Enum.Font.GothamBold
		label.TextSize = size
		label.TextColor3 = INK
		label.TextTransparency = 0
		label.TextStrokeColor3 = PARCH_STROKE
		label.TextStrokeTransparency = 0.5
		label.ZIndex = Z
	end

	local function makeLabel(parent, size, props)
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.TextWrapped = true
		label.Text = ""
		ink(label, size)
		for k, v in pairs(props or {}) do
			label[k] = v
		end
		label.Parent = parent
		return label
	end

	-- A transparent section frame (a Frame so pulseFrame/tutorial spotlights still work).
	local function makeSection(parent, height, order, tint)
		local box = Instance.new("Frame")
		box.Size = UDim2.new(1, 0, 0, height)
		box.LayoutOrder = order
		box.BackgroundColor3 = TAG_PARCHMENT
		box.BackgroundTransparency = tint and 0.82 or 1 -- faint tint so the pulse flash shows
		box.BorderSizePixel = 0
		box.ZIndex = Z
		box.Parent = parent
		if tint then
			roundCorner(box, 6)
		end
		return box
	end

	-- Painted icon in a small rounded tile (the art has a dark backdrop), emoji if no art.
	local function makeIcon(parent, key, emoji, size, props)
		local holder = Instance.new("Frame")
		holder.Name = key or "Icon" -- SidebarTheme swaps in the kit icon by this name
		holder.Size = UDim2.fromOffset(size, size)
		holder.BackgroundTransparency = 1
		holder.Active = false
		holder.ZIndex = Z
		for k, v in pairs(props or {}) do
			holder[k] = v
		end
		holder.Parent = parent
		local id = key and hud(key)
		if id then
			local img = Instance.new("ImageLabel")
			img.Size = UDim2.fromScale(1, 1)
			img.BackgroundTransparency = 1
			img.Image = id
			img.ScaleType = Enum.ScaleType.Fit
			img.Active = false
			img.ZIndex = Z
			img.Parent = holder
			roundCorner(img, 6)
			local stroke = Instance.new("UIStroke")
			stroke.Color = Color3.fromRGB(110, 80, 45)
			stroke.Thickness = 1.5
			stroke.Parent = img
		else
			local e = Instance.new("TextLabel")
			e.Size = UDim2.fromScale(1, 1)
			e.BackgroundTransparency = 1
			e.Font = Enum.Font.Gotham
			e.TextSize = math.floor(size * 0.8)
			e.Text = emoji
			e.TextTransparency = 0
			e.TextStrokeTransparency = 1
			e.ZIndex = Z
			e.Parent = holder
		end
		return holder
	end

	-- ART: the plaque frame is only kept for the small run-mode badge.
	local function makeBadgeBox(height)
		local box = Instance.new("Frame")
		box.Size = UDim2.new(1, 0, 0, height)
		box.BackgroundColor3 = BOX_COLOR
		box.ZIndex = Z
		box.Parent = sidebar
		polishPanel(box, 4)
		return box
	end

	-- ===== Run-mode badge (Daily / Weekly / Seed), pinned above the header =====
	local runModeBadgeBox = makeBadgeBox(36)
	runModeBadgeBox.LayoutOrder = -1
	runModeBadgeBox.BackgroundColor3 = Color3.fromRGB(80, 55, 110)
	runModeBadgeBox.Visible = false
	local runModeBadgeLabel = makeLabel(runModeBadgeBox, 16, { TextColor3 = Color3.fromRGB(230, 210, 255), TextStrokeTransparency = 1 })
	runModeBadgeLabel.Text = "Daily"
	-- The seed code of a Seed Run sits in a read-only TextBox: click it to select the code, then Ctrl+C copies it
	-- (games cannot write to the clipboard themselves). A tiny "Press Ctrl+C" note appears for a moment.
	local seedBox = Instance.new("TextBox")
	seedBox.Name = "SeedCodeBox"
	seedBox.AnchorPoint = Vector2.new(1, 0.5)
	seedBox.Position = UDim2.new(1, -8, 0.5, 0)
	seedBox.Size = UDim2.fromOffset(110, 26)
	seedBox.BackgroundColor3 = Color3.fromRGB(26, 17, 10)
	seedBox.BorderSizePixel = 0
	seedBox.Font = Enum.Font.GothamBold
	seedBox.TextSize = 18
	seedBox.TextColor3 = Color3.fromRGB(255, 232, 160)
	seedBox.TextEditable = false
	seedBox.ClearTextOnFocus = false
	seedBox.Text = ""
	seedBox.Visible = false
	seedBox.ZIndex = Z + 2
	seedBox.Parent = runModeBadgeBox
	roundCorner(seedBox, 5)
	seedBox.Focused:Connect(function()
		seedBox.SelectionStart = 1
		seedBox.CursorPosition = #seedBox.Text + 1
		runModeBadgeLabel.Text = "Press Ctrl+C"
		task.delay(1.6, function()
			if seedBox.Visible then runModeBadgeLabel.Text = "Seed:" end
		end)
	end)

	local SeedDisplay = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("SeedDisplay"))
	local function setRunModeBadge(isDaily, dailyDateKey, isWeekly, weeklyDateKey, isSeeded, seedCode)
		local info = SeedDisplay.label({
			isDaily = isDaily, dailyDateKey = dailyDateKey, isWeekly = isWeekly, weeklyDateKey = weeklyDateKey,
			isSeeded = isSeeded, seedCode = seedCode,
		})
		if not info then
			runModeBadgeBox.Visible = false
			seedBox.Visible = false
			return
		end
		runModeBadgeBox.Visible = true
		runModeBadgeBox.BackgroundColor3 = info.kind == "daily" and Color3.fromRGB(80, 55, 110)
			or (info.kind == "weekly" and Color3.fromRGB(45, 75, 110) or Color3.fromRGB(55, 95, 60))
		if info.kind == "seed" then
			-- "Seed:" on the left, the code selectable on the right
			runModeBadgeLabel.TextXAlignment = Enum.TextXAlignment.Left
			runModeBadgeLabel.Position = UDim2.fromOffset(10, 0)
			if runModeBadgeLabel.Text ~= "Press Ctrl+C" then runModeBadgeLabel.Text = "Seed:" end
			seedBox.Text = info.value
			seedBox.Visible = true
		else
			seedBox.Visible = false
			runModeBadgeLabel.TextXAlignment = Enum.TextXAlignment.Center
			runModeBadgeLabel.Position = UDim2.fromOffset(0, 0)
			runModeBadgeLabel.Text = info.text
		end
	end

	-- ===== Header ribbon: "Night 1/8 · Round 2" =====
	local nightRoundBox = Instance.new("Frame")
	nightRoundBox.Name = "HeaderRibbon"
	nightRoundBox.Size = UDim2.new(1, 0, 0, 44)
	nightRoundBox.LayoutOrder = 1
	nightRoundBox.BackgroundColor3 = Color3.fromRGB(104, 66, 36) -- painted wood plaque
	nightRoundBox.BorderSizePixel = 0
	nightRoundBox.ZIndex = Z + 1
	nightRoundBox.Parent = sidebar
	roundCorner(nightRoundBox, 5)
	do
		local grain = Instance.new("UIGradient") -- Color stops only (never Transparency)
		grain.Color = ColorSequence.new(Color3.fromRGB(128, 84, 46), Color3.fromRGB(86, 54, 28))
		grain.Rotation = 90
		grain.Parent = nightRoundBox
		local st = Instance.new("UIStroke")
		st.Color = GOLD
		st.Thickness = 2
		st.Parent = nightRoundBox
		for side = 1, 2 do -- ribbon tails
			local tail = Instance.new("Frame")
			tail.AnchorPoint = Vector2.new(0.5, 0.5)
			tail.Size = UDim2.fromOffset(16, 28)
			tail.Position = UDim2.new(side == 1 and 0 or 1, side == 1 and 2 or -2, 0.5, 4)
			tail.BackgroundColor3 = Color3.fromRGB(150, 48, 40)
			tail.BorderSizePixel = 0
			tail.ZIndex = Z
			tail.Parent = nightRoundBox
		end
	end
	local nightRoundLabel = makeLabel(nightRoundBox, 19, {
		ZIndex = Z + 2, Size = UDim2.new(1, -14, 1, 0), Position = UDim2.fromOffset(7, 0),
		TextColor3 = Color3.fromRGB(255, 240, 200), TextStrokeColor3 = Color3.fromRGB(40, 24, 12), TextStrokeTransparency = 0.3,
	})

	-- Spacer so the sections start on the parchment, below the board's arched top beam.
	local spacer = Instance.new("Frame")
	spacer.Name = "ArchSpacer"
	spacer.Size = UDim2.new(1, 0, 0, 4)
	spacer.LayoutOrder = 2
	spacer.BackgroundTransparency = 1
	spacer.Parent = sidebar

	local content = Instance.new("Frame")
	content.Name = "BoardContent"
	content.Size = UDim2.new(1, 0, 0, 440)
	content.AutomaticSize = Enum.AutomaticSize.Y
	content.LayoutOrder = 3
	content.BackgroundTransparency = 1
	content.ZIndex = Z
	content.Parent = sidebar
	local contentLayout = Instance.new("UIListLayout")
	contentLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	contentLayout.SortOrder = Enum.SortOrder.LayoutOrder
	contentLayout.Padding = UDim.new(0, 10)
	contentLayout.Parent = content

	local dividers = {}
	local function makeDivider(order)
		local d = Instance.new("Frame")
		d.Name = "Divider"
		d.Size = UDim2.new(1, 0, 0, 26)
		d.LayoutOrder = order
		d.BackgroundTransparency = 1
		d.ZIndex = Z
		d.Parent = content
		local id = hud("flourish_divider")
		if id then
			local img = Instance.new("ImageLabel")
			img.Size = UDim2.fromScale(1, 1)
			img.BackgroundTransparency = 1
			img.Image = id
			-- the flourish sits in the middle band of the 1536x1024 art
			local rx, ry, rw, rh = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("ImageSpace")).rect(30, 395, 1476, 240, 1536, 1024)
			img.ImageRectOffset = Vector2.new(rx, ry)
			img.ImageRectSize = Vector2.new(rw, rh)
			img.ScaleType = Enum.ScaleType.Stretch
			img.Active = false
			img.ZIndex = Z
			img.Parent = d
			roundCorner(img, 4)
		else
			local line = Instance.new("Frame") -- flat fallback: a thin ink line
			line.AnchorPoint = Vector2.new(0.5, 0.5)
			line.Position = UDim2.fromScale(0.5, 0.5)
			line.Size = UDim2.new(0.9, 0, 0, 2)
			line.BackgroundColor3 = INK
			line.BackgroundTransparency = 0.55
			line.BorderSizePixel = 0
			line.ZIndex = Z
			line.Parent = d
		end
		table.insert(dividers, d)
		return d
	end

	-- ===== Round type + rule text (blindInfoLabel keeps RichText from render()) =====
	local blindInfoBox = makeSection(content, 76, 1)
	local blindInfoLabel = makeLabel(blindInfoBox, 17, { RichText = true, TextYAlignment = Enum.TextYAlignment.Center, TextTruncate = Enum.TextTruncate.AtEnd })
	-- render() writes cream rule text; show it in ink instead (cream on parchment is unreadable).
	do
		local busy = false
		blindInfoLabel:GetPropertyChangedSignal("Text"):Connect(function()
			if busy then
				return
			end
			local fixed = blindInfoLabel.Text:gsub("#E6D2AA", "#3C2816")
			if fixed ~= blindInfoLabel.Text then
				busy = true
				blindInfoLabel.Text = fixed
				busy = false
			end
		end)
	end
	makeDivider(2)

	-- ===== Score: big readout + thin target progress bar =====
	local scoreBox = makeSection(content, 96, 3, true)
	-- scoreLabel: data label written by render() ("Score: X / Y\nReward: $R"), not shown.
	local scoreLabel = makeLabel(scoreBox, 19, { Visible = false })
	makeIcon(scoreBox, "target_score", "🎯", 32, { Position = UDim2.fromOffset(6, 5) })
	local bigScore = makeLabel(scoreBox, 34, {
		Size = UDim2.new(1, -50, 0, 40), Position = UDim2.fromOffset(44, 2), TextScaled = true, TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	do
		local limit = Instance.new("UITextSizeConstraint")
		limit.MaxTextSize = 34
		limit.MinTextSize = 18
		limit.Parent = bigScore
	end
	local barTrack = Instance.new("Frame")
	barTrack.Name = "TargetBar"
	barTrack.Position = UDim2.new(0, 8, 0, 48)
	barTrack.Size = UDim2.new(1, -16, 0, 12)
	barTrack.BackgroundColor3 = Color3.fromRGB(96, 64, 36)
	barTrack.BorderSizePixel = 0
	barTrack.ZIndex = Z
	barTrack.Parent = scoreBox
	roundCorner(barTrack, 6)
	local barStroke = Instance.new("UIStroke")
	barStroke.Color = Color3.fromRGB(60, 40, 22)
	barStroke.Thickness = 1.5
	barStroke.Parent = barTrack
	local barFill = Instance.new("Frame")
	barFill.Size = UDim2.fromScale(0, 1)
	barFill.BackgroundColor3 = Color3.fromRGB(236, 184, 70)
	barFill.BorderSizePixel = 0
	barFill.ZIndex = Z + 1
	barFill.Parent = barTrack
	roundCorner(barFill, 6)
	local rewardPlate = Instance.new("Frame") -- owns the painted reward plate (SidebarTheme); the line sits on it
	rewardPlate.Name = "RewardPlate"
	rewardPlate.Size = UDim2.new(1, -16, 0, 26)
	rewardPlate.Position = UDim2.fromOffset(8, 64)
	rewardPlate.BackgroundTransparency = 1
	rewardPlate.BorderSizePixel = 0
	rewardPlate.Active = false
	rewardPlate.ZIndex = Z
	rewardPlate.Parent = scoreBox
	local rewardLine = makeLabel(rewardPlate, 17, { Size = UDim2.fromScale(1, 1), Position = UDim2.new(), TextWrapped = false })
	scoreLabel:GetPropertyChangedSignal("Text"):Connect(function()
		local score, target, reward = scoreLabel.Text:match("Score:%s*([%d%.%-]+)%s*/%s*([%d%.%-]+).-Reward:%s*%$?([%d%.%-]+)")
		score, target = tonumber(score), tonumber(target)
		if not score or not target then
			return
		end
		bigScore.Text = string.format("%d / %d", math.floor(score), math.floor(target))
		rewardLine.Text = "Reward: $" .. tostring(reward)
		barFill.Size = UDim2.fromScale(math.clamp(target > 0 and score / target or 0, 0, 1), 1)
	end)
	makeDivider(4)

	-- ===== Tips with the coin purse =====
	local tipsBox = makeSection(content, 44, 5, true)
	tipsBox.Name = "TipsRow"
	local tipsLabel = makeLabel(tipsBox, 19, { Visible = false }) -- data label ("Tips: N")
	makeIcon(tipsBox, "coin_purse", "💰", 32, { Position = UDim2.fromOffset(8, 6) })
	local tipsShown = makeLabel(tipsBox, 19, { Size = UDim2.new(1, -52, 1, 0), Position = UDim2.fromOffset(46, 0), TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = false })
	tipsLabel:GetPropertyChangedSignal("Text"):Connect(function()
		local n = tipsLabel.Text:match("Tips:%s*([%d%.%-]+)")
		if n then
			tipsShown.Text = "Tips: " .. n
		end
	end)

	-- ===== Hands and Discards side by side =====
	local handsDiscardsBox = makeSection(content, 66, 6, true)
	local handsDiscardsLabel = makeLabel(handsDiscardsBox, 18, { Visible = false }) -- data label ("Hands: N   Discards: M")
	local function column(xScale, key, emoji)
		local col = Instance.new("Frame")
		col.Name = key == "hands_cards" and "HandsTile" or "DiscardsTile"
		col.Size = UDim2.new(0.5, 0, 1, 0)
		col.Position = UDim2.fromScale(xScale, 0)
		col.BackgroundTransparency = 1
		col.ZIndex = Z
		col.Parent = handsDiscardsBox
		makeIcon(col, key, emoji, 28, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 4) })
		return makeLabel(col, 17, { Size = UDim2.new(1, 0, 0, 24), Position = UDim2.new(0, 0, 0, 36), TextWrapped = false })
	end
	local handsShown = column(0, "hands_cards", "🃏")
	local discardsShown = column(0.5, "discard_bin", "🗑")
	handsDiscardsLabel:GetPropertyChangedSignal("Text"):Connect(function()
		local h, d = handsDiscardsLabel.Text:match("Hands:%s*([%d%.%-]+)%s+Discards:%s*([%d%.%-]+)")
		if h and d then
			handsShown.Text = "Hands " .. h
			discardsShown.Text = "Discards " .. d
		end
	end)
	makeDivider(7)

	-- ===== Patrons: title + one framed inset of round double-ring seats =====
	-- Seats are 38px with a 3px gap so 5 fit the 216px content width (inset padding 4);
	-- more than 5 unlocked seats wrap to extra rows and the section grows (AutomaticSize).
	local patronsBox = makeSection(content, 78, 8)
	patronsBox.AutomaticSize = Enum.AutomaticSize.Y
	patronsBox.Name = "PatronsTray"
	local patronsCountLabel = makeLabel(patronsBox, 16, { Visible = false }) -- data label ("n/limit"), set by render()
	local patronsHeader = makeLabel(patronsBox, 16, { Size = UDim2.new(1, -8, 0, 22), Position = UDim2.fromOffset(4, 2), TextXAlignment = Enum.TextXAlignment.Left, Text = "Patrons", Font = Enum.Font.GothamBold })
	patronsCountLabel:GetPropertyChangedSignal("Text"):Connect(function()
		patronsHeader.Text = "Patrons " .. patronsCountLabel.Text
	end)

	local SLOT, SLOT_GAP = 38, 14 -- 14 px between seats leaves 8 clear after the open-seat pulse ring (+1 px each side, 2 px stroke)
	local patronsSlotRow = Instance.new("Frame")
	patronsSlotRow.Name = "PatronsInset"
	patronsSlotRow.Size = UDim2.new(1, 0, 0, SLOT + 12)
	patronsSlotRow.AutomaticSize = Enum.AutomaticSize.Y
	patronsSlotRow.Position = UDim2.fromOffset(0, 26)
	patronsSlotRow.BackgroundColor3 = Color3.fromRGB(199, 178, 137) -- same inset as the status strip
	patronsSlotRow.BackgroundTransparency = 0
	patronsSlotRow.ZIndex = Z
	patronsSlotRow.Parent = patronsBox
	roundCorner(patronsSlotRow, 8)
	local insetStroke = Instance.new("UIStroke")
	insetStroke.Color = Color3.fromRGB(96, 66, 38)
	insetStroke.Thickness = 1.5
	insetStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	insetStroke.Parent = patronsSlotRow
	local insetPad = Instance.new("UIPadding")
	insetPad.PaddingTop, insetPad.PaddingBottom = UDim.new(0, 6), UDim.new(0, 6)
	insetPad.PaddingLeft, insetPad.PaddingRight = UDim.new(0, 4), UDim.new(0, 4)
	insetPad.Parent = patronsSlotRow
	local seatLayout = Instance.new("UIListLayout")
	seatLayout.FillDirection = Enum.FillDirection.Horizontal
	seatLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	seatLayout.Wraps = true
	seatLayout.Padding = UDim.new(0, SLOT_GAP)
	seatLayout.SortOrder = Enum.SortOrder.LayoutOrder
	seatLayout.Parent = patronsSlotRow

	local MAX_SIDEBAR_PATRON_SLOTS = 14
	local patronSlots = {}
	for i = 1, math.min(MAX_SIDEBAR_PATRON_SLOTS, #Patrons.Definitions) do
		local slot = Instance.new("Frame")
		slot.Size = UDim2.fromOffset(SLOT, SLOT)
		slot.BackgroundColor3 = Color3.fromRGB(196, 168, 118) -- slightly darker parchment medallion (render() recolors)
		slot.LayoutOrder = i
		slot.ZIndex = Z + 1
		slot.Parent = patronsSlotRow
		roundCorner(slot, SLOT / 2)
		local seatRing = Instance.new("UIStroke") -- outer ring, ink brown
		seatRing.Color = Color3.fromRGB(96, 64, 36)
		seatRing.Thickness = 2
		seatRing.Transparency = 0
		seatRing.Parent = slot
		-- inner thin gold ring, above any patron art
		local innerRing = Instance.new("Frame")
		innerRing.Name = "InnerRing"
		innerRing.AnchorPoint = Vector2.new(0.5, 0.5)
		innerRing.Position = UDim2.fromScale(0.5, 0.5)
		innerRing.Size = UDim2.new(1, -4, 1, -4)
		innerRing.BackgroundTransparency = 1
		innerRing.Active = false
		innerRing.ZIndex = Z + 4
		innerRing.Parent = slot
		roundCorner(innerRing, SLOT / 2)
		local goldRing = Instance.new("UIStroke")
		goldRing.Color = Color3.fromRGB(222, 182, 104)
		goldRing.Thickness = 1
		goldRing.Parent = innerRing

		local slotLabel = Instance.new("TextLabel")
		slotLabel.Size = UDim2.fromScale(1, 1)
		slotLabel.BackgroundTransparency = 1
		slotLabel.Font = Enum.Font.GothamBold
		slotLabel.TextSize = 20
		slotLabel.TextColor3 = Color3.fromRGB(96, 64, 36)
		slotLabel.TextTransparency = 0.55 -- faint engraved "+"
		slotLabel.Text = "+"
		slotLabel.ZIndex = Z + 1
		slotLabel.Parent = slot

		-- Open-seat pulse: a faint gold ring that slowly breathes while the seat is empty (render() shows it only
		-- then). Static under Reduce screen shake.
		local pulse = Instance.new("Frame")
		pulse.Name = "EmptyPulse"
		pulse.AnchorPoint = Vector2.new(0.5, 0.5)
		pulse.Position = UDim2.fromScale(0.5, 0.5)
		pulse.Size = UDim2.new(1, 2, 1, 2)
		pulse.BackgroundTransparency = 1
		pulse.Active = false
		pulse.ZIndex = Z
		pulse.Parent = slot
		roundCorner(pulse, SLOT / 2 + 1)
		local pulseRing = Instance.new("UIStroke")
		pulseRing.Color = Color3.fromRGB(222, 182, 104)
		pulseRing.Thickness = 2
		pulseRing.Transparency = 0.5
		pulseRing.Parent = pulse
		if not require(script.Parent.ClientSettings).get("reduceShake") then
			game:GetService("TweenService"):Create(pulseRing,
				TweenInfo.new(1.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Transparency = 0.9 }):Play()
		end
		patronSlots[i] = { frame = slot, label = slotLabel, pulse = pulse }
	end
	-- Up to 7 seats share one row: they shrink (min 26 px) instead of wrapping under the plates below.
	local function fitSeats(count)
		local row = patronsSlotRow.AbsoluteSize.X
		local usable = (row > 40 and row or 216) - 8
		-- 5 seats or fewer keep the wide gap; 6 and 7 tighten it so they still fit one row
		local gap = count <= 5 and SLOT_GAP or 3
		seatLayout.Padding = UDim.new(0, gap)
		local size = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("SeatFit")).size(count, usable, gap, SLOT, 26)
		for _, seat in ipairs(patronSlots) do
			seat.frame.Size = UDim2.fromOffset(size, size)
			for _, obj in ipairs({ seat.frame, seat.frame:FindFirstChild("InnerRing"), seat.pulse }) do
				local c = obj and obj:FindFirstChildOfClass("UICorner")
				if c then c.CornerRadius = UDim.new(0.5, 0) end
			end
		end
		patronsSlotRow.Size = UDim2.new(1, 0, 0, size + 12)
		return size
	end
	makeDivider(9)

	-- ===== Status line / live hand preview ("Select cards...") =====
	local scorePreviewBox = makeSection(content, 56, 10, true)
	-- Darker parchment inset (board parchment -12%) with a thin ink-brown outline.
	scorePreviewBox.BackgroundColor3 = Color3.fromRGB(199, 178, 137)
	scorePreviewBox.BackgroundTransparency = 0
	local previewStroke = Instance.new("UIStroke")
	previewStroke.Color = Color3.fromRGB(96, 66, 38)
	previewStroke.Thickness = 1.5
	previewStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	previewStroke.Parent = scorePreviewBox
	local scorePreviewLabel = makeLabel(scorePreviewBox, 16, {
		TextColor3 = INK, Font = Enum.Font.GothamBold, TextTransparency = 0, TextStrokeTransparency = 1, Size = UDim2.new(1, -12, 1, -4), Position = UDim2.fromOffset(6, 2) })

	-- Dividers hide on short screens; the arch spacer keeps sections on the parchment.
	local SECTIONS_H, DIVIDER_H, GAP = 76 + 96 + 44 + 66 + 78 + 56, 26, 10
	local function relayout()
		local h = sidebar.AbsoluteSize.Y
		if h < 50 then
			return
		end
		spacer.Size = UDim2.new(1, 0, 0, math.max(4, math.floor(h * 0.12) - 76 - 44 - 2 * 6))
		local avail = h * 0.9 - h * 0.12
		local withDividers = SECTIONS_H + 4 * DIVIDER_H + 9 * GAP
		local show = avail >= withDividers
		for _, d in ipairs(dividers) do
			d.Visible = show
		end
	end
	sidebar:GetPropertyChangedSignal("AbsoluteSize"):Connect(relayout)
	task.defer(relayout)

	-- Icons live in the sections now; these keep render()'s calls working.
	local function placeRewardIcon() end
	local function setIconText(key, plainText, emojiText)
		if key == "boss" then
			blindInfoLabel.Text = plainText -- no crown in the text: plain name line plus rule text
			blindInfoLabel:SetAttribute("Boss", true) -- PlayBoardHud paints the dark red plate and crown from this
		elseif key == "tips" then
			tipsLabel.Text = plainText
		elseif key == "hands" then
			handsDiscardsLabel.Text = plainText
		end
	end
	local function hideLineIcon(key)
		if key == "boss" then blindInfoLabel:SetAttribute("Boss", nil) end
	end

	return {
		SIDEBAR_WIDTH = SIDEBAR_WIDTH,
		sidebar = sidebar,
		nightRoundLabel = nightRoundLabel,
		blindInfoLabel = blindInfoLabel,
		scoreLabel = scoreLabel,
		-- TUTORIAL WALKTHROUGH spotlights the whole box, not just the text.
		scoreBox = scoreBox,
		tipsLabel = tipsLabel,
		tipsBox = tipsBox,
		handsDiscardsLabel = handsDiscardsLabel,
		handsDiscardsBox = handsDiscardsBox,
		patronsCountLabel = patronsCountLabel,
		patronsInset = patronsSlotRow, -- TUTORIAL: spotlight target for the Patron seats
		patronSlots = patronSlots,
		MAX_SIDEBAR_PATRON_SLOTS = MAX_SIDEBAR_PATRON_SLOTS,
		fitSeats = fitSeats,
		scorePreviewBox = scorePreviewBox,
		scorePreviewLabel = scorePreviewLabel,
		setRunModeBadge = setRunModeBadge,
		placeRewardIcon = placeRewardIcon,
		setIconText = setIconText,
		hideLineIcon = hideLineIcon,
	}
end
