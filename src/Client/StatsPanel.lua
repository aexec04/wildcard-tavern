--[[
	Client/StatsPanel.lua
	Tavern Stats: opened from the "Stats" button in the Collection header. Art first, icons over words:
	  * header: three big numbers (Wins, Runs, Best Night);
	  * the last 10 finished runs as compact painted cards: road art (map_regions, flat tint fallback), stake medal
	    (stakes art, emoji fallback), a Won / Lost ribbon, the Night reached, up to 4 Patron icons and a small
	    mode tag (Daily, Weekly, Seed, Challenge, Rush) when it was not a standard run; hover a card for the detail;
	  * a lifetime list of icon tiles (hands played, best hand score, Tips earned, favorite Patron, best Night on
	    each stake), each with a hover line.
	Reads state.runStats (Engine/RunHistory.view, sent by the server) and refreshes on every StateUpdated while
	open. Everything is built once and refilled, nothing animates, so there is no loop to clean up.
	deps: screenGui, polishPanel, polishButton, roundCorner, addSoftShadow, playClickSfx, openButton, addTooltip,
	      getLatestState, popIn, popOut, addButtonHoverScale, StateUpdatedRemote
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

return function(deps)
	local OverlayManager = require(script.Parent.OverlayManager)
	local Engine = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine")
	local Stakes = require(Engine:WaitForChild("Stakes"))
	local WorldMap = require(Engine:WaitForChild("WorldMap"))
	local Patrons = require(Engine:WaitForChild("Patrons"))
	local ContentArt = require(Engine:WaitForChild("ContentArt"))
	local ArtIcon = require(script.Parent.ArtIcon)

	local CREAM = Color3.fromRGB(250, 240, 220)
	local GOLD = Color3.fromRGB(222, 182, 104)
	local BROWN = Color3.fromRGB(70, 55, 40)
	local INK = Color3.fromRGB(60, 40, 22)
	local TILE = Color3.fromRGB(232, 212, 168)
	local WIN_GREEN = Color3.fromRGB(70, 120, 60)
	local LOSS_BROWN = Color3.fromRGB(120, 80, 50)
	local CARD_W, CARD_H = 150, 196

	local MODE_TAGS = { daily = "Daily", weekly = "Weekly", seed = "Seed", challenge = "Twist", rush = "Rush", quick = "Quick" }

	local function label(parent, props)
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Font = Enum.Font.GothamBold
		l.TextColor3 = INK
		l.TextTransparency = 0
		l.TextStrokeTransparency = 1
		l.TextSize = 14
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
	panel.Size = UDim2.fromScale(0.78, 0.9)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.BackgroundColor3 = Color3.fromRGB(40, 30, 22)
	panel.ZIndex = 41
	panel.Parent = backdrop
	deps.polishPanel(panel, 16, "parchment")
	deps.addSoftShadow(panel, 18)

	label(panel, {
		Size = UDim2.new(1, 0, 0, 30), Position = UDim2.fromOffset(0, 6), TextSize = 22, TextColor3 = INK, Text = "Tavern Stats",
	})

	-- header: three big numbers
	local header = Instance.new("Frame")
	header.Size = UDim2.new(1, -30, 0, 78)
	header.Position = UDim2.fromOffset(15, 40)
	header.BackgroundTransparency = 1
	header.ZIndex = 41
	header.Parent = panel
	local headerLayout = Instance.new("UIListLayout")
	headerLayout.FillDirection = Enum.FillDirection.Horizontal
	headerLayout.SortOrder = Enum.SortOrder.LayoutOrder
	headerLayout.Padding = UDim.new(0, 12)
	headerLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	headerLayout.Parent = header
	local bigNumbers = {}
	for i, spec in ipairs({
		{ key = "wins", icon = "🏆", name = "Wins" },
		{ key = "runs", icon = "🎲", name = "Runs" },
		{ key = "bestNight", icon = "🌙", name = "Best Night" },
	}) do
		local tile = Instance.new("Frame")
		tile.LayoutOrder = i
		tile.Size = UDim2.new(0.3, 0, 1, 0)
		tile.BackgroundColor3 = TILE
		tile.BorderSizePixel = 0
		tile.ZIndex = 42
		tile.Parent = header
		deps.roundCorner(tile, 10)
		local stroke = Instance.new("UIStroke")
		stroke.Color = GOLD
		stroke.Thickness = 2
		stroke.Parent = tile
		label(tile, { Size = UDim2.fromOffset(40, 40), Position = UDim2.fromOffset(8, 10), TextSize = 28, Text = spec.icon })
		bigNumbers[spec.key] = label(tile, {
			Size = UDim2.new(1, -56, 0, 38), Position = UDim2.fromOffset(52, 4), TextSize = 30, TextXAlignment = Enum.TextXAlignment.Left, Text = "0",
		})
		label(tile, {
			Size = UDim2.new(1, -56, 0, 20), Position = UDim2.fromOffset(52, 44), TextSize = 14, Font = Enum.Font.Gotham,
			TextXAlignment = Enum.TextXAlignment.Left, Text = spec.name,
		})
	end

	local scroll = Instance.new("ScrollingFrame")
	scroll.Size = UDim2.new(1, -30, 1, -170)
	scroll.Position = UDim2.fromOffset(15, 126)
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
	scrollLayout.Padding = UDim.new(0, 10)
	scrollLayout.Parent = scroll

	local recentTitle = label(scroll, {
		LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 24), TextSize = 17, TextXAlignment = Enum.TextXAlignment.Left, Text = "Last runs",
	})
	local recentGrid = Instance.new("Frame")
	recentGrid.LayoutOrder = 2
	recentGrid.Size = UDim2.new(1, 0, 0, CARD_H)
	recentGrid.AutomaticSize = Enum.AutomaticSize.Y
	recentGrid.BackgroundTransparency = 1
	recentGrid.ZIndex = 41
	recentGrid.Parent = scroll
	local recentLayout = Instance.new("UIGridLayout")
	recentLayout.CellSize = UDim2.fromOffset(CARD_W, CARD_H)
	recentLayout.CellPadding = UDim2.fromOffset(10, 10)
	recentLayout.SortOrder = Enum.SortOrder.LayoutOrder
	recentLayout.Parent = recentGrid
	local emptyLabel = label(scroll, {
		LayoutOrder = 3, Size = UDim2.new(1, 0, 0, 24), Font = Enum.Font.Gotham, TextSize = 15, TextXAlignment = Enum.TextXAlignment.Left,
		Text = "Finish a run and it shows up here.", Visible = false,
	})
	label(scroll, {
		LayoutOrder = 4, Size = UDim2.new(1, 0, 0, 24), TextSize = 17, TextXAlignment = Enum.TextXAlignment.Left, Text = "Lifetime",
	})
	local lifeGrid = Instance.new("Frame")
	lifeGrid.LayoutOrder = 5
	lifeGrid.Size = UDim2.new(1, 0, 0, 80)
	lifeGrid.AutomaticSize = Enum.AutomaticSize.Y
	lifeGrid.BackgroundTransparency = 1
	lifeGrid.ZIndex = 41
	lifeGrid.Parent = scroll
	local lifeLayout = Instance.new("UIGridLayout")
	lifeLayout.CellSize = UDim2.fromOffset(150, 72)
	lifeLayout.CellPadding = UDim2.fromOffset(10, 10)
	lifeLayout.SortOrder = Enum.SortOrder.LayoutOrder
	lifeLayout.Parent = lifeGrid

	local closeButton = Instance.new("TextButton")
	closeButton.Size = UDim2.fromOffset(110, 34)
	closeButton.AnchorPoint = Vector2.new(0.5, 1)
	closeButton.Position = UDim2.new(0.5, 0, 1, -8)
	closeButton.Font = Enum.Font.GothamBold
	closeButton.TextSize = 15
	closeButton.TextColor3 = CREAM
	closeButton.BackgroundColor3 = BROWN
	closeButton.Text = "Close"
	closeButton.ZIndex = 42
	closeButton.Parent = panel
	deps.polishButton(closeButton, 8)
	deps.addButtonHoverScale(closeButton)

	local function clear(frame)
		for _, child in ipairs(frame:GetChildren()) do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
	end

	-- a small art square with an emoji behind it (the art covers the emoji once it loads)
	local function artSquare(parent, size, position, category, key, emoji, radius)
		local holder = Instance.new("Frame")
		holder.Size = UDim2.fromOffset(size, size)
		holder.Position = position
		holder.BackgroundColor3 = Color3.fromRGB(196, 170, 124)
		holder.BorderSizePixel = 0
		holder.ZIndex = 44
		holder.Parent = parent
		deps.roundCorner(holder, radius or size // 2)
		local glyph = label(holder, { Size = UDim2.fromScale(1, 1), TextSize = math.max(14, size - 10), Text = emoji or "?", ZIndex = 45 })
		pcall(ArtIcon.apply, holder, category, key, glyph, { cornerRadius = radius or size // 2, zIndex = 46 })
		return holder
	end

	local function runCard(entry, order)
		local card = Instance.new("Frame")
		card.Name = "Run_" .. order
		card.LayoutOrder = order
		card.BackgroundColor3 = TILE
		card.BorderSizePixel = 0
		card.ClipsDescendants = true
		card.ZIndex = 42
		card.Parent = recentGrid
		deps.roundCorner(card, 10)
		local stroke = Instance.new("UIStroke")
		stroke.Color = entry.won and GOLD or Color3.fromRGB(120, 96, 66)
		stroke.Thickness = entry.won and 2.5 or 1.5
		stroke.Parent = card

		-- road art on top (flat tint fallback)
		local road = entry.road and WorldMap.Regions[entry.road]
		local artFrame = Instance.new("Frame")
		artFrame.Size = UDim2.new(1, 0, 0, 84)
		local tint = road and road.tint or { 200, 180, 140 }
		artFrame.BackgroundColor3 = Color3.fromRGB(tint[1], tint[2], tint[3])
		artFrame.BorderSizePixel = 0
		artFrame.ZIndex = 43
		artFrame.Parent = card
		local roadKey = road and road.scenery or nil
		local artId = roadKey and ContentArt.getImageId("map_regions", roadKey)
		if artId then
			local img = Instance.new("ImageLabel")
			img.Name = "RoadArt"
			img.Size = UDim2.fromScale(1, 1)
			img.BackgroundTransparency = 1
			img.Image = artId
			img.ScaleType = Enum.ScaleType.Crop
			img.ImageTransparency = 0
			img.ZIndex = 44
			img.Parent = artFrame
		end

		-- won / lost ribbon
		local ribbon = label(card, {
			Size = UDim2.fromOffset(64, 22), Position = UDim2.fromOffset(6, 6), BackgroundTransparency = 0,
			BackgroundColor3 = entry.won and WIN_GREEN or LOSS_BROWN, TextColor3 = CREAM, TextSize = 14,
			Text = entry.won and "Won" or "Lost", ZIndex = 47,
		})
		deps.roundCorner(ribbon, 6)

		-- stake medal on the art's corner
		local stakeDef = Stakes.get(entry.stake)
		artSquare(card, 34, UDim2.new(1, -40, 0, 6), "stakes", stakeDef and stakeDef.id or "regular", stakeDef and stakeDef.icon or "🍞", 17).ZIndex = 47

		label(card, {
			Size = UDim2.new(1, -12, 0, 22), Position = UDim2.fromOffset(6, 90), TextSize = 17,
			TextXAlignment = Enum.TextXAlignment.Left, Text = "Night " .. tostring(entry.night),
		})
		local tag = MODE_TAGS[entry.mode]
		label(card, {
			Size = UDim2.new(1, -12, 0, 18), Position = UDim2.fromOffset(6, 112), Font = Enum.Font.Gotham, TextSize = 14,
			TextXAlignment = Enum.TextXAlignment.Left, Text = tag or (road and road.name or ""), TextTruncate = Enum.TextTruncate.AtEnd,
		})

		-- up to 4 Patron icons
		for i = 1, math.min(4, #entry.patrons) do
			local def = Patrons.getById(entry.patrons[i])
			artSquare(card, 30, UDim2.fromOffset(6 + (i - 1) * 35, 136), "patrons", entry.patrons[i], def and def.icon or "🙂", 15)
		end
		if #entry.patrons > 4 then
			label(card, { Size = UDim2.fromOffset(30, 30), Position = UDim2.fromOffset(6 + 4 * 35, 136), TextSize = 14, Text = "+" .. (#entry.patrons - 4) })
		end
		label(card, {
			Size = UDim2.new(1, -12, 0, 18), Position = UDim2.fromOffset(6, 172), Font = Enum.Font.Gotham, TextSize = 14,
			TextXAlignment = Enum.TextXAlignment.Left, Text = "Score " .. fmt(entry.score),
		})

		local tip = string.format("%s on %s. Night %d, %d hands, score %s%s.", entry.won and "Won" or "Lost",
			stakeDef and stakeDef.name or "Regular", entry.night, entry.hands or 0, fmt(entry.score),
			entry.bestHand and (", best hand " .. entry.bestHand.name .. " for " .. fmt(entry.bestHand.score)) or "")
		deps.addTooltip(card, tip)
	end

	local function lifeTile(order, icon, value, tip, artCategory, artKey)
		local tile = Instance.new("Frame")
		tile.LayoutOrder = order
		tile.BackgroundColor3 = TILE
		tile.BorderSizePixel = 0
		tile.ZIndex = 42
		tile.Parent = lifeGrid
		deps.roundCorner(tile, 10)
		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.fromRGB(150, 120, 80)
		stroke.Thickness = 1.5
		stroke.Parent = tile
		artSquare(tile, 44, UDim2.fromOffset(8, 14), artCategory, artKey, icon, 10)
		label(tile, {
			Size = UDim2.new(1, -64, 1, -8), Position = UDim2.fromOffset(58, 4), TextSize = 20,
			TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true, Text = value,
		})
		deps.addTooltip(tile, tip)
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

		clear(recentGrid)
		for i, entry in ipairs(stats.recent or {}) do
			runCard(entry, i)
		end
		emptyLabel.Visible = #(stats.recent or {}) == 0
		recentTitle.Text = "Last runs (" .. #(stats.recent or {}) .. ")"

		clear(lifeGrid)
		local order = 0
		local function add(icon, value, tip, cat, key)
			order = order + 1
			lifeTile(order, icon, value, tip, cat, key)
		end
		add("🃏", fmt(stats.hands), "Hands played over every run.")
		add("💥", fmt(stats.bestHandScore), "Your best scoring hand ever.")
		add("🪙", fmt(stats.tipsEarned), "Tips earned over every run.")
		local fav = stats.favoritePatron
		if fav then
			local def = Patrons.getById(fav.id)
			add(def and def.icon or "⭐", (def and def.name or fav.id), string.format("Favorite Patron: in %d won runs.", fav.wins), "patrons", fav.id)
		else
			add("⭐", "None yet", "Win a run to find your favorite Patron.")
		end
		for stake = 1, 8 do
			local best = stats.bestNightByStake and stats.bestNightByStake[tostring(stake)]
			if best then
				local def = Stakes.get(stake)
				add(def.icon, "Night " .. best, "Best Night on " .. def.name .. ".", "stakes", def.id)
			end
		end
	end

	OverlayManager.register("stats", function()
		deps.popOut(backdrop, panel)
	end)
	deps.openButton.MouseButton1Click:Connect(function()
		deps.playClickSfx()
		OverlayManager.closeAllExcept("stats")
		refresh()
		deps.popIn(backdrop, panel)
	end)
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
