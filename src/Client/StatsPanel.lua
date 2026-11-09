--[[
	Client/StatsPanel.lua
	Tavern Stats, opened from the "Stats" button in the Collection header. A tavern ledger on a chalkboard: cream
	chalk text on dark green-black with a wood frame, every number labelled.
	  * top row: Wins, Runs, Best Night and a win rate ring (36 small segments, lit up to the rate);
	  * two cards: your favorite Patron (painted art) and your best run (highest Night, a win first);
	  * a bar sparkline of the last 20 runs (bar height = Night reached, gold when won, brown when lost);
	  * the run ledger: one row per run (Won/Lost, Night, stake medal, mode, score, up to 4 Patron icons); tap a row to
	    expand it into its details (Patron names, hands, best hand, stake and, for a Seed Run, the seed code in a
	    read-only box you can select and copy with Ctrl+C because games cannot write to the clipboard);
	  * lifetime tiles with a label under each number;
	  * an empty state with the painted chest and a friendly line when no run has finished yet.
	Reads state.runStats (Engine/RunHistory.view) and refreshes on every StateUpdated while open. Nothing animates, so
	there is no loop to clean up.
	deps: screenGui, polishPanel, polishButton, roundCorner, addSoftShadow, playClickSfx, openButton, addTooltip,
	      getLatestState, popIn, popOut, addButtonHoverScale, StateUpdatedRemote
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

return function(deps)
	local OverlayManager = require(script.Parent.OverlayManager)
	local Engine = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine")
	local Stakes = require(Engine:WaitForChild("Stakes"))
	local Patrons = require(Engine:WaitForChild("Patrons"))
	local ArtIcon = require(script.Parent.ArtIcon)

	local CHALK = Color3.fromRGB(240, 232, 208) -- main text
	local CHALK_DIM = Color3.fromRGB(205, 196, 170)
	local GOLD = Color3.fromRGB(232, 190, 108)
	local BOARD = Color3.fromRGB(30, 42, 36)
	local CARD = Color3.fromRGB(44, 60, 52)
	local CARD_OPEN = Color3.fromRGB(54, 74, 63)
	local WIN_GREEN = Color3.fromRGB(88, 150, 84)
	local LOSS_BROWN = Color3.fromRGB(150, 104, 66)
	local WOOD = Color3.fromRGB(86, 58, 34)
	local ROW_H, OPEN_H = 56, 150

	local MODE_TAGS = { daily = "Daily", weekly = "Weekly", seed = "Seed", challenge = "Twist", rush = "Rush", quick = "Quick" }

	local function label(parent, props)
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Font = Enum.Font.GothamBold
		l.TextColor3 = CHALK
		l.TextTransparency = 0
		l.TextStrokeTransparency = 1
		l.TextSize = 16
		l.ZIndex = 43
		for k, v in pairs(props) do
			l[k] = v
		end
		l.Parent = parent
		return l
	end

	local function fmt(n)
		n = math.floor(tonumber(n) or 0)
		if n >= 1e9 then return string.format("%.1fB", n / 1e9) end
		if n >= 1e6 then return string.format("%.1fM", n / 1e6) end
		if n >= 1e4 then return string.format("%.1fK", n / 1e3) end
		return tostring(n)
	end

	local function box(parent, props, radius, strokeColor)
		local f = Instance.new("Frame")
		f.BorderSizePixel = 0
		f.ZIndex = 42
		for k, v in pairs(props) do
			f[k] = v
		end
		f.Parent = parent
		deps.roundCorner(f, radius or 10)
		if strokeColor then
			local s = Instance.new("UIStroke")
			s.Color = strokeColor
			s.Thickness = 1.5
			s.Parent = f
		end
		return f
	end

	local backdrop = Instance.new("Frame")
	backdrop.Name = "StatsBackdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	backdrop.BackgroundTransparency = 0.4
	backdrop.Visible = false
	backdrop.ZIndex = 40
	backdrop.Parent = deps.screenGui

	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Size = UDim2.fromScale(0.82, 0.9)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.BackgroundColor3 = BOARD
	panel.ZIndex = 41
	panel.Parent = backdrop
	deps.roundCorner(panel, 14)
	deps.addSoftShadow(panel, 18)
	local frameStroke = Instance.new("UIStroke") -- the wooden chalkboard frame
	frameStroke.Color = WOOD
	frameStroke.Thickness = 7
	frameStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	frameStroke.Parent = panel
	local innerRule = Instance.new("Frame")
	innerRule.Size = UDim2.new(1, -12, 1, -12)
	innerRule.Position = UDim2.fromOffset(6, 6)
	innerRule.BackgroundTransparency = 1
	innerRule.Active = false
	innerRule.ZIndex = 41
	innerRule.Parent = panel
	deps.roundCorner(innerRule, 10)
	local ruleStroke = Instance.new("UIStroke")
	ruleStroke.Color = Color3.fromRGB(120, 140, 126)
	ruleStroke.Thickness = 1
	ruleStroke.Parent = innerRule

	label(panel, { Size = UDim2.new(1, 0, 0, 36), Position = UDim2.fromOffset(0, 8), TextSize = 28, Text = "Tavern Ledger", TextColor3 = GOLD })

	local scroll = Instance.new("ScrollingFrame")
	scroll.Size = UDim2.new(1, -36, 1, -112)
	scroll.Position = UDim2.fromOffset(18, 48)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 10
	scroll.ScrollBarImageColor3 = GOLD
	scroll.ScrollBarImageTransparency = 0
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new()
	scroll.ZIndex = 41
	scroll.Parent = panel
	local scrollLayout = Instance.new("UIListLayout")
	scrollLayout.SortOrder = Enum.SortOrder.LayoutOrder
	scrollLayout.Padding = UDim.new(0, 12)
	scrollLayout.Parent = scroll

	local closeButton = Instance.new("TextButton")
	closeButton.Size = UDim2.fromOffset(120, 38)
	closeButton.AnchorPoint = Vector2.new(0.5, 1)
	closeButton.Position = UDim2.new(0.5, 0, 1, -14)
	closeButton.Font = Enum.Font.GothamBold
	closeButton.TextSize = 17
	closeButton.TextColor3 = CHALK
	closeButton.BackgroundColor3 = WOOD
	closeButton.Text = "Close"
	closeButton.ZIndex = 43
	closeButton.Parent = panel
	deps.polishButton(closeButton, 8)
	deps.addButtonHoverScale(closeButton)

	-- ===== Section 1: labelled headline tiles and the win rate ring =====
	local top = Instance.new("Frame")
	top.LayoutOrder = 1
	top.Size = UDim2.new(1, 0, 0, 92)
	top.BackgroundTransparency = 1
	top.ZIndex = 41
	top.Parent = scroll
	local topLayout = Instance.new("UIListLayout")
	topLayout.FillDirection = Enum.FillDirection.Horizontal
	topLayout.SortOrder = Enum.SortOrder.LayoutOrder
	topLayout.Padding = UDim.new(0, 10)
	topLayout.Parent = top
	local bigNumbers = {}
	for i, spec in ipairs({
		{ key = "wins", icon = "🏆", name = "Runs won" },
		{ key = "runs", icon = "🎲", name = "Runs started" },
		{ key = "bestNight", icon = "🌙", name = "Best Night" },
	}) do
		local tile = box(top, { LayoutOrder = i, Size = UDim2.new(0.25, -8, 1, 0), BackgroundColor3 = CARD }, 10, GOLD)
		label(tile, { Size = UDim2.fromOffset(40, 40), Position = UDim2.fromOffset(8, 10), TextSize = 28, Text = spec.icon })
		bigNumbers[spec.key] = label(tile, {
			Size = UDim2.new(1, -56, 0, 40), Position = UDim2.fromOffset(52, 8), TextSize = 32, TextXAlignment = Enum.TextXAlignment.Left, Text = "0",
		})
		label(tile, {
			Size = UDim2.new(1, -12, 0, 22), Position = UDim2.fromOffset(8, 62), TextSize = 16, Font = Enum.Font.GothamMedium,
			TextColor3 = CHALK_DIM, TextXAlignment = Enum.TextXAlignment.Left, Text = spec.name,
		})
	end
	-- win rate ring: 36 segments around a circle
	local ringTile = box(top, { LayoutOrder = 4, Size = UDim2.new(0.25, -8, 1, 0), BackgroundColor3 = CARD }, 10, GOLD)
	local ring = Instance.new("Frame")
	ring.Size = UDim2.fromOffset(76, 76)
	ring.Position = UDim2.fromOffset(8, 8)
	ring.BackgroundTransparency = 1
	ring.ZIndex = 43
	ring.Parent = ringTile
	local SEGMENTS = 36
	local ringSegments = {}
	for i = 1, SEGMENTS do
		local angle = math.rad((i - 1) * (360 / SEGMENTS) - 90)
		local seg = Instance.new("Frame")
		seg.Size = UDim2.fromOffset(5, 10)
		seg.AnchorPoint = Vector2.new(0.5, 0.5)
		seg.Position = UDim2.fromOffset(38 + math.cos(angle) * 32, 38 + math.sin(angle) * 32)
		seg.Rotation = (i - 1) * (360 / SEGMENTS)
		seg.BorderSizePixel = 0
		seg.BackgroundColor3 = Color3.fromRGB(80, 98, 88)
		seg.ZIndex = 44
		seg.Parent = ring
		ringSegments[i] = seg
	end
	local ringPercent = label(ring, { Size = UDim2.fromScale(1, 1), TextSize = 18, Text = "0%" })
	label(ringTile, {
		Size = UDim2.new(1, -96, 0, 44), Position = UDim2.fromOffset(90, 24), TextSize = 16, Font = Enum.Font.GothamMedium,
		TextColor3 = CHALK_DIM, TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true, Text = "Win rate",
	})

	-- ===== Section 2: favorite Patron and best run =====
	local feature = Instance.new("Frame")
	feature.LayoutOrder = 2
	feature.Size = UDim2.new(1, 0, 0, 104)
	feature.BackgroundTransparency = 1
	feature.ZIndex = 41
	feature.Parent = scroll
	local featureLayout = Instance.new("UIListLayout")
	featureLayout.FillDirection = Enum.FillDirection.Horizontal
	featureLayout.SortOrder = Enum.SortOrder.LayoutOrder
	featureLayout.Padding = UDim.new(0, 10)
	featureLayout.Parent = feature
	local favCard = box(feature, { LayoutOrder = 1, Size = UDim2.new(0.5, -5, 1, 0), BackgroundColor3 = CARD }, 10, GOLD)
	local bestCard = box(feature, { LayoutOrder = 2, Size = UDim2.new(0.5, -5, 1, 0), BackgroundColor3 = CARD }, 10, GOLD)
	label(favCard, { Size = UDim2.new(1, -100, 0, 20), Position = UDim2.fromOffset(92, 8), TextSize = 15, TextColor3 = GOLD, TextXAlignment = Enum.TextXAlignment.Left, Text = "Favorite Patron" })
	local favName = label(favCard, { Size = UDim2.new(1, -100, 0, 28), Position = UDim2.fromOffset(92, 30), TextSize = 20, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Text = "None yet" })
	local favNote = label(favCard, { Size = UDim2.new(1, -100, 0, 36), Position = UDim2.fromOffset(92, 58), TextSize = 15, Font = Enum.Font.GothamMedium, TextColor3 = CHALK_DIM, TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true, Text = "" })
	local favArt = box(favCard, { Size = UDim2.fromOffset(76, 76), Position = UDim2.fromOffset(10, 14), BackgroundColor3 = Color3.fromRGB(26, 36, 30) }, 12, GOLD)
	local favGlyph = label(favArt, { Size = UDim2.fromScale(1, 1), TextSize = 42, Text = "⭐", ZIndex = 44 })
	label(bestCard, { Size = UDim2.new(1, -20, 0, 20), Position = UDim2.fromOffset(12, 8), TextSize = 15, TextColor3 = GOLD, TextXAlignment = Enum.TextXAlignment.Left, Text = "Best run" })
	local bestTitle = label(bestCard, { Size = UDim2.new(1, -20, 0, 30), Position = UDim2.fromOffset(12, 30), TextSize = 22, TextXAlignment = Enum.TextXAlignment.Left, Text = "No runs yet" })
	local bestNote = label(bestCard, { Size = UDim2.new(1, -20, 0, 40), Position = UDim2.fromOffset(12, 60), TextSize = 15, Font = Enum.Font.GothamMedium, TextColor3 = CHALK_DIM, TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true, Text = "" })

	-- ===== Section 3: sparkline of the last 20 runs =====
	local sparkCard = box(scroll, { LayoutOrder = 3, Size = UDim2.new(1, 0, 0, 130), BackgroundColor3 = CARD }, 10, Color3.fromRGB(120, 140, 126))
	local sparkTitle = label(sparkCard, { Size = UDim2.new(1, -20, 0, 22), Position = UDim2.fromOffset(12, 6), TextSize = 17, TextXAlignment = Enum.TextXAlignment.Left, Text = "Night reached, last runs" })
	local sparkBars = Instance.new("Frame")
	sparkBars.Size = UDim2.new(1, -24, 0, 76)
	sparkBars.Position = UDim2.fromOffset(12, 40)
	sparkBars.BackgroundTransparency = 1
	sparkBars.ZIndex = 43
	sparkBars.Parent = sparkCard
	label(sparkCard, { Size = UDim2.new(1, -20, 0, 20), Position = UDim2.new(0, 12, 1, -22), TextSize = 14, Font = Enum.Font.GothamMedium, TextColor3 = CHALK_DIM, TextXAlignment = Enum.TextXAlignment.Left, Text = "Gold bar = won, brown = lost. Oldest on the left." })

	-- ===== Section 4: run ledger (tap to expand) =====
	local ledgerTitle = label(scroll, { LayoutOrder = 4, Size = UDim2.new(1, 0, 0, 28), TextSize = 20, TextColor3 = GOLD, TextXAlignment = Enum.TextXAlignment.Left, Text = "Run ledger" })
	local ledger = Instance.new("Frame")
	ledger.LayoutOrder = 5
	ledger.Size = UDim2.new(1, 0, 0, 0)
	ledger.AutomaticSize = Enum.AutomaticSize.Y
	ledger.BackgroundTransparency = 1
	ledger.ZIndex = 41
	ledger.Parent = scroll
	local ledgerLayout = Instance.new("UIListLayout")
	ledgerLayout.SortOrder = Enum.SortOrder.LayoutOrder
	ledgerLayout.Padding = UDim.new(0, 6)
	ledgerLayout.Parent = ledger

	-- empty state: painted chest and a friendly line
	local empty = Instance.new("Frame")
	empty.LayoutOrder = 6
	empty.Size = UDim2.new(1, 0, 0, 150)
	empty.BackgroundTransparency = 1
	empty.Visible = false
	empty.ZIndex = 41
	empty.Parent = scroll
	local emptyArt = box(empty, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 4), Size = UDim2.fromOffset(84, 84), BackgroundColor3 = CARD }, 42, GOLD)
	local emptyGlyph = label(emptyArt, { Size = UDim2.fromScale(1, 1), TextSize = 46, Text = "🧰", ZIndex = 44 })
	pcall(ArtIcon.apply, emptyArt, "discoveries", "chest", emptyGlyph, { cornerRadius = 42, zIndex = 46 })
	label(empty, { Size = UDim2.new(1, 0, 0, 50), Position = UDim2.fromOffset(0, 92), TextSize = 18, TextWrapped = true, Text = "The ledger is empty. Finish a run, win or lose, and it is written here." })

	-- ===== Section 5: lifetime tiles =====
	label(scroll, { LayoutOrder = 7, Size = UDim2.new(1, 0, 0, 28), TextSize = 20, TextColor3 = GOLD, TextXAlignment = Enum.TextXAlignment.Left, Text = "Lifetime" })
	local lifeGrid = Instance.new("Frame")
	lifeGrid.LayoutOrder = 8
	lifeGrid.Size = UDim2.new(1, 0, 0, 90)
	lifeGrid.AutomaticSize = Enum.AutomaticSize.Y
	lifeGrid.BackgroundTransparency = 1
	lifeGrid.ZIndex = 41
	lifeGrid.Parent = scroll
	local lifeLayout = Instance.new("UIGridLayout")
	lifeLayout.CellSize = UDim2.fromOffset(176, 86)
	lifeLayout.CellPadding = UDim2.fromOffset(10, 10)
	lifeLayout.SortOrder = Enum.SortOrder.LayoutOrder
	lifeLayout.Parent = lifeGrid

	local function clear(frame)
		for _, child in ipairs(frame:GetChildren()) do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
	end

	-- a small art square with an emoji behind it (the art covers the emoji once it loads)
	local function artSquare(parent, size, position, category, key, emoji, radius)
		local holder = box(parent, { Size = UDim2.fromOffset(size, size), Position = position, BackgroundColor3 = Color3.fromRGB(26, 36, 30), ZIndex = 44 }, radius or size // 2)
		local glyph = label(holder, { Size = UDim2.fromScale(1, 1), TextSize = math.max(14, size - 12), Text = emoji or "?", ZIndex = 45 })
		if category then
			pcall(ArtIcon.apply, holder, category, key, glyph, { cornerRadius = radius or size // 2, zIndex = 46 })
		end
		return holder
	end

	local expandedOrder -- which ledger row is open (one at a time)
	local rebuildLedger

	local function runRow(entry, order, stats)
		local open = expandedOrder == order
		local row = box(ledger, {
			Name = "Run_" .. order, LayoutOrder = order, Size = UDim2.new(1, 0, 0, open and OPEN_H or ROW_H),
			BackgroundColor3 = open and CARD_OPEN or CARD, ClipsDescendants = true,
		}, 10, entry.won and GOLD or Color3.fromRGB(120, 140, 126))
		local stakeDef = Stakes.get(entry.stake)
		local hit = Instance.new("TextButton") -- the whole row is the tap target
		hit.Size = UDim2.new(1, 0, 0, ROW_H)
		hit.BackgroundTransparency = 1
		hit.Text = ""
		hit.ZIndex = 50
		hit.Parent = row
		hit.MouseButton1Click:Connect(function()
			deps.playClickSfx()
			expandedOrder = (expandedOrder == order) and nil or order
			rebuildLedger(stats)
		end)
		local badge = label(row, {
			Size = UDim2.fromOffset(60, 26), Position = UDim2.fromOffset(10, 15), BackgroundTransparency = 0,
			BackgroundColor3 = entry.won and WIN_GREEN or LOSS_BROWN, TextSize = 16, Text = entry.won and "Won" or "Lost",
		})
		deps.roundCorner(badge, 6)
		label(row, { Size = UDim2.fromOffset(100, 24), Position = UDim2.fromOffset(80, 6), TextSize = 19, TextXAlignment = Enum.TextXAlignment.Left, Text = "Night " .. tostring(entry.night) })
		label(row, {
			Size = UDim2.fromOffset(150, 20), Position = UDim2.fromOffset(80, 30), TextSize = 15, Font = Enum.Font.GothamMedium, TextColor3 = CHALK_DIM,
			TextXAlignment = Enum.TextXAlignment.Left, Text = MODE_TAGS[entry.mode] or "Standard",
		})
		artSquare(row, 34, UDim2.fromOffset(238, 11), "stakes", stakeDef and stakeDef.id or "regular", stakeDef and stakeDef.icon or "🍞", 17)
		label(row, { Size = UDim2.fromOffset(120, 24), Position = UDim2.fromOffset(282, 16), TextSize = 17, TextXAlignment = Enum.TextXAlignment.Left, Text = "Score " .. fmt(entry.score) })
		for i = 1, math.min(4, #entry.patrons) do
			local def = Patrons.getById(entry.patrons[i])
			local sq = artSquare(row, 34, UDim2.new(1, -(4 - i + 1) * 40 - 30, 0, 11), "patrons", entry.patrons[i], def and def.icon or "🙂", 17)
			sq.ZIndex = 46
		end
		label(row, { Size = UDim2.fromOffset(24, 24), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -6, 0, 16), TextSize = 16, TextColor3 = GOLD, Text = open and "▲" or "▼" })
		if open then -- details
			local names = {}
			for _, id in ipairs(entry.patrons) do
				local def = Patrons.getById(id)
				names[#names + 1] = def and def.name or id
			end
			label(row, {
				Size = UDim2.new(1, -24, 0, 38), Position = UDim2.fromOffset(12, 58), TextSize = 15, Font = Enum.Font.GothamMedium, TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
				Text = "Patrons: " .. (#names > 0 and table.concat(names, ", ") or "none"),
			})
			label(row, {
				Size = UDim2.new(1, -24, 0, 22), Position = UDim2.fromOffset(12, 96), TextSize = 15, Font = Enum.Font.GothamMedium, TextColor3 = CHALK_DIM,
				TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
				Text = string.format("%s stake, %d hands%s", stakeDef and stakeDef.name or "Regular", entry.hands or 0,
					entry.bestHand and (", best hand " .. entry.bestHand.name .. " for " .. fmt(entry.bestHand.score)) or ""),
			})
			if entry.seed then
				label(row, { Size = UDim2.fromOffset(60, 22), Position = UDim2.fromOffset(12, 122), TextSize = 15, TextXAlignment = Enum.TextXAlignment.Left, Text = "Seed" })
				local seedBox = Instance.new("TextBox") -- read-only: select, then Ctrl+C (games cannot write the clipboard)
				seedBox.Size = UDim2.fromOffset(190, 24)
				seedBox.Position = UDim2.fromOffset(70, 121)
				seedBox.BackgroundColor3 = Color3.fromRGB(26, 36, 30)
				seedBox.BorderSizePixel = 0
				seedBox.Font = Enum.Font.GothamBold
				seedBox.TextSize = 16
				seedBox.TextColor3 = GOLD
				seedBox.ClearTextOnFocus = false
				seedBox.TextEditable = false
				seedBox.Text = entry.seed
				seedBox.ZIndex = 52
				seedBox.Parent = row
				deps.roundCorner(seedBox, 6)
				label(row, { Size = UDim2.fromOffset(200, 22), Position = UDim2.fromOffset(268, 122), TextSize = 14, Font = Enum.Font.GothamMedium, TextColor3 = CHALK_DIM, TextXAlignment = Enum.TextXAlignment.Left, Text = "Click it, then Ctrl+C" })
			end
		end
	end

	rebuildLedger = function(stats)
		clear(ledger)
		local recent = stats.recent or {}
		-- the ledger shows the 10 newest; the sparkline above uses all of them
		for i = 1, math.min(10, #recent) do
			runRow(recent[i], i, stats)
		end
	end

	local function lifeTile(order, icon, value, name, tip, artCategory, artKey)
		local tile = box(lifeGrid, { LayoutOrder = order, BackgroundColor3 = CARD }, 10, Color3.fromRGB(120, 140, 126))
		artSquare(tile, 40, UDim2.fromOffset(8, 8), artCategory, artKey, icon, 10)
		label(tile, { Size = UDim2.new(1, -58, 0, 28), Position = UDim2.fromOffset(54, 8), TextSize = 21, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Text = value })
		label(tile, { Size = UDim2.new(1, -12, 0, 22), Position = UDim2.fromOffset(8, 56), TextSize = 15, Font = Enum.Font.GothamMedium, TextColor3 = CHALK_DIM, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Text = name })
		deps.addTooltip(tile, tip)
	end

	local function paintRing(rate)
		local lit = math.floor(SEGMENTS * rate + 0.5)
		for i, seg in ipairs(ringSegments) do
			seg.BackgroundColor3 = i <= lit and GOLD or Color3.fromRGB(80, 98, 88)
		end
		ringPercent.Text = string.format("%d%%", math.floor(rate * 100 + 0.5))
	end

	local function refresh()
		local state = deps.getLatestState and deps.getLatestState() or nil
		local stats = state and state.runStats
		if not stats then
			return
		end
		bigNumbers.wins.Text = fmt(stats.wins)
		bigNumbers.runs.Text = fmt(stats.runs)
		bigNumbers.bestNight.Text = tostring(stats.bestNight or 0)
		paintRing((stats.runs or 0) > 0 and math.min(1, (stats.wins or 0) / stats.runs) or 0)

		local recent = stats.recent or {}
		local hasRuns = #recent > 0
		ledgerTitle.Visible = hasRuns
		ledger.Visible = hasRuns
		empty.Visible = not hasRuns
		sparkCard.Visible = hasRuns
		if expandedOrder and not recent[expandedOrder] then expandedOrder = nil end
		rebuildLedger(stats)

		-- favorite Patron
		local fav = stats.favoritePatron
		if fav then
			local def = Patrons.getById(fav.id)
			favName.Text = def and def.name or fav.id
			favNote.Text = string.format("Won %d run%s with it", fav.wins, fav.wins == 1 and "" or "s")
			favGlyph.Text = def and def.icon or "⭐"
			favGlyph.TextTransparency = 0
			for _, c in ipairs(favArt:GetChildren()) do
				if c:IsA("ImageLabel") then c:Destroy() end
			end
			pcall(ArtIcon.apply, favArt, "patrons", fav.id, favGlyph, { cornerRadius = 12, zIndex = 46 })
		else
			favName.Text = "None yet"
			favNote.Text = "Win a run to find your favorite."
		end

		-- best run: highest Night, a win beats a loss, then the higher score
		local best
		for _, entry in ipairs(recent) do
			if not best or entry.night > best.night or (entry.night == best.night and ((entry.won and not best.won) or (entry.won == best.won and entry.score > best.score))) then
				best = entry
			end
		end
		if best then
			local stakeDef = Stakes.get(best.stake)
			bestTitle.Text = string.format("Night %d, %s", best.night, best.won and "won" or "lost")
			bestNote.Text = string.format("%s stake, score %s%s", stakeDef and stakeDef.name or "Regular", fmt(best.score),
				best.bestHand and (", best hand " .. best.bestHand.name) or "")
		else
			bestTitle.Text = "No runs yet"
			bestNote.Text = "Your best of the last runs shows here."
		end

		-- sparkline: oldest on the left
		clear(sparkBars)
		local maxNight = 1
		for _, entry in ipairs(recent) do maxNight = math.max(maxNight, entry.night) end
		local count = #recent
		sparkTitle.Text = string.format("Night reached, last %d run%s", count, count == 1 and "" or "s")
		for i = count, 1, -1 do
			local entry = recent[i]
			local slot = count - i -- 0 = oldest
			local h = math.max(6, math.floor(56 * entry.night / maxNight)) -- leaves room above the bar for its Night number
			local bar = Instance.new("Frame")
			bar.AnchorPoint = Vector2.new(0, 1)
			bar.Size = UDim2.new(1 / 20, -4, 0, h)
			bar.Position = UDim2.new(slot / 20, 2, 1, 0)
			bar.BackgroundColor3 = entry.won and GOLD or LOSS_BROWN
			bar.BorderSizePixel = 0
			bar.ZIndex = 44
			bar.Parent = sparkBars
			deps.roundCorner(bar, 3)
			label(bar, { Size = UDim2.new(1, 0, 0, 16), Position = UDim2.fromOffset(0, -18), TextSize = 14, Text = tostring(entry.night), TextColor3 = CHALK_DIM })
		end

		-- lifetime tiles, each with a label
		clear(lifeGrid)
		local order = 0
		local function add(icon, value, name, tip, cat, key)
			order = order + 1
			lifeTile(order, icon, value, name, tip, cat, key)
		end
		local titleDef = state.equippedTitleId and require(Engine:WaitForChild("Achievements")).getById(state.equippedTitleId)
		add("🎖️", titleDef and titleDef.title or "None", "Title", "The Title you have equipped. Change it in Collection.")
		add("🃏", fmt(stats.hands), "Hands played", "Hands played over every run.")
		add("💥", fmt(stats.bestHandScore), "Best hand score", "Your best scoring hand ever.")
		add("🪙", fmt(stats.tipsEarned), "Tips earned", "Tips earned over every run.", "hud", "coin_purse")
		for stake = 1, 8 do
			local bestNight = stats.bestNightByStake and stats.bestNightByStake[tostring(stake)]
			if bestNight then
				local def = Stakes.get(stake)
				add(def.icon, "Night " .. bestNight, "Best on " .. def.name, "Best Night on " .. def.name .. ".", "stakes", def.id)
			end
		end
	end

	require(script.Parent.PanelTabs).attach(backdrop, "stats", deps.playClickSfx) -- shared tab strip + Back
	OverlayManager.register("stats", function()
		deps.popOut(backdrop, panel)
	end)
	local function openThisPanel()
		deps.playClickSfx()
		OverlayManager.closeAllExcept("stats")
		expandedOrder = nil
		refresh()
		deps.popIn(backdrop, panel)
	end
	OverlayManager.registerOpener("stats", openThisPanel)
	deps.openButton.MouseButton1Click:Connect(openThisPanel)
	closeButton.MouseButton1Click:Connect(function()
		deps.playClickSfx()
		deps.popOut(backdrop, panel)
	end)
	deps.StateUpdatedRemote.OnClientEvent:Connect(function()
		task.defer(function()
			if backdrop.Visible then
				refresh()
			end
		end)
	end)

	return {}
end
