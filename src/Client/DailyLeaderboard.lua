--[[
	Client/DailyLeaderboard.lua
	DAILY CHALLENGE (Phase 11): shows today's top 10 Daily Challenge scores
	(by "depth" -- rounds fully cleared, see Server/init.server.lua's
	computeDailyDepth -- tips as the tiebreak) plus the player's own best
	for today, whether or not it placed in the top 10. Reachable from the
	Settings panel's "🏆 Leaderboards" button, mirroring Collection.lua's pattern
	(backdrop + panel + popIn/popOut + Close button).

	Extracted as its own file for the same reason every other overlay in
	this codebase is: keeps this self-contained and keeps init.client.lua
	from growing past its 200-local ceiling (Menu.lua's header comment has
	the fuller explanation of why that ceiling matters here). Fully
	self-contained -- nothing outside this module needs anything it builds,
	so it returns an empty table, same as Collection.lua.

	WEEKLY CHALLENGE (Phase 16): this overlay now has a Daily/Weekly tab
	toggle at the top instead of getting a whole separate
	WeeklyLeaderboard.lua file -- same panel/rows/close button, just a
	2nd RemoteFunction (GetWeeklyLeaderboardRemote) and a small
	`activeBoard` ("daily"/"weekly") flag deciding which one
	refreshLeaderboard() calls and how the labels read.

	deps fields:
		screenGui                -- ScreenGui, the panel's ultimate parent (via backdrop)
		polishPanel                -- function(instance, radius)
		polishButton                -- function(instance, radius)
		roundCorner                 -- function(instance, radius)
		addSoftShadow                -- function(instance, radius)
		playClickSfx                -- function(volume?)
		leaderboardButton            -- TextButton, Settings.lua's "🏆 Leaderboards" button (was the corner icon)
		GetDailyLeaderboardRemote    -- RemoteFunction, InvokeServer() -> see below
		GetWeeklyLeaderboardRemote   -- RemoteFunction, same shape as GetDailyLeaderboardRemote (Phase 16)
		popIn                        -- function(backdrop, content, opts?)
		popOut                       -- function(backdrop, content, opts?, onHidden?)
		addButtonHoverScale          -- function(button, opts?)
		localPlayer                  -- Player, this client's Players.LocalPlayer

	GetDailyLeaderboardRemote:InvokeServer() (and GetWeeklyLeaderboardRemote,
	identical shape) returns:
		{
			ok = boolean,          -- false: top-10 fetch failed OR rate-limited
			dateKey = "YYYY-MM-DD" (or "W<n>" for Weekly),
			top = { { userId, name, depth, tips }, ... },  -- up to 10, best first
			yourBest = { depth, tips } or nil,
			yourBestOk = boolean,  -- false: this player's own-best fetch failed
		}
	`ok = false` covers two different server-side cases (a real DataStore
	failure, and the server's own short per-player request cooldown) --
	this module can't tell them apart and doesn't need to; either way the
	right UI is just "couldn't load the board right now, try again in a
	moment" rather than pretending the board is empty.

	ONE MORE ROUND: each period has a Standard and a Revived board
	(Shared/Engine/Leaderboards.lua). A Standard/Revived toggle at the
	top-right picks which one, defaulting to Standard every time the
	overlay opens; its id is passed to InvokeServer(board). Every run on
	the Revived board used its continue, so one "Revived" badge next to
	"Your best" marks the whole board.

	Returns: {}
]]

return function(deps)
	local screenGui = deps.screenGui
	local polishPanel = deps.polishPanel
	local polishButton = deps.polishButton
	local roundCorner = deps.roundCorner
	local addSoftShadow = deps.addSoftShadow
	local playClickSfx = deps.playClickSfx
	local leaderboardButton = deps.leaderboardButton
	local GetDailyLeaderboardRemote = deps.GetDailyLeaderboardRemote
	local GetWeeklyLeaderboardRemote = deps.GetWeeklyLeaderboardRemote
	local GetEndlessLeaderboardRemote = deps.GetEndlessLeaderboardRemote -- Endless board: highest Night, then best hand
	local popIn = deps.popIn
	local popOut = deps.popOut
	local addButtonHoverScale = deps.addButtonHoverScale
	local localPlayer = deps.localPlayer
	-- BUGFIX (overlapping overlays): see Client/OverlayManager.lua's own
	-- header comment for the full story.
	local OverlayManager = require(script.Parent.OverlayManager)
	local Leaderboards = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("Leaderboards"))
	local LBText = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("LeaderboardText"))
	local NameFit = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("NameFit"))

	local leaderboardBackdrop = Instance.new("Frame")
	leaderboardBackdrop.Name = "DailyLeaderboardBackdrop"
	leaderboardBackdrop.Size = UDim2.fromScale(1, 1)
	leaderboardBackdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	leaderboardBackdrop.BackgroundTransparency = 0.4
	leaderboardBackdrop.Visible = false
	leaderboardBackdrop.ZIndex = 20
	leaderboardBackdrop.Parent = screenGui
	require(script.Parent.MenuTitleHider).bind(screenGui, leaderboardBackdrop)

	local leaderboardPanel = Instance.new("Frame")
	leaderboardPanel.Size = UDim2.fromScale(0.5, 0.65)
	leaderboardPanel.AnchorPoint = Vector2.new(0.5, 0.5)
	leaderboardPanel.Position = UDim2.fromScale(0.5, 0.5)
	do -- keep the six tab buttons on one row on small screens (LeaderboardText.layout)
		local limit = Instance.new("UISizeConstraint")
		limit.MinSize = Vector2.new(LBText.MIN_PANEL_W, LBText.MIN_PANEL_H)
		limit.Parent = leaderboardPanel
	end
	leaderboardPanel.BackgroundColor3 = Color3.fromRGB(40, 30, 22)
	leaderboardPanel.ZIndex = 21
	leaderboardPanel.Parent = leaderboardBackdrop
	polishPanel(leaderboardPanel, 16, "parchment")
	-- Painted background (PanelArt): flat panel color if the art id is missing.
	local leaderboardPanelArt = require(script.Parent.PanelArt).add(leaderboardPanel, {
		key = "challenge_bg", scrim = { position = UDim2.fromScale(0, 0), size = UDim2.fromScale(1, 1) },
		scrimTransparency = 0.35,
	})
	addSoftShadow(leaderboardPanel, 18)

	-- WEEKLY CHALLENGE (Phase 16): Daily/Weekly tab row, above the title.
	local function makeTabButton(text, xOffset, xScale)
		local button = Instance.new("TextButton")
		button.Size = UDim2.new(0, 90, 0, LBText.TAB_H)
		button.Position = UDim2.new(xScale or 0, xOffset, 0, 0)
		button.Font = Enum.Font.GothamBold
		button.TextSize = 14
		button.Text = text
		button.BackgroundColor3 = Color3.fromRGB(70, 55, 40)
		button.TextColor3 = Color3.fromRGB(250, 240, 220)
		button.ZIndex = 21
		button.Parent = leaderboardPanel
		polishButton(button, 8)
		addButtonHoverScale(button)
		return button
	end

	local dailyTabButton = makeTabButton("\240\159\147\133 Daily", 0)
	local weeklyTabButton = makeTabButton("\240\159\151\147 Weekly", 96)
	-- ONE MORE ROUND: Standard/Revived toggle, right-aligned on the same row.
	local standardTabButton = makeTabButton("Standard", -186, 1)
	local revivedTabButton = makeTabButton("\u{1F4AB} Revived", -90, 1)
	-- FRIENDS: toggles the board between everyone and only your Roblox friends (plus you).
	-- ENDLESS board tab, and the scope toggle (it shows the scope you are on: Global or Friends).
	local endlessTabButton = makeTabButton("\u{267E} Endless", 192)
	local friendsTabButton = makeTabButton("\u{1F30D} Global", 288)
	friendsTabButton.TextSize = 15

	local leaderboardTitle = Instance.new("TextLabel")
	leaderboardTitle.Size = UDim2.new(1, 0, 0, LBText.TITLE_H)
	leaderboardTitle.Position = UDim2.new(0, 0, 0, LBText.TITLE_Y)
	leaderboardTitle.BackgroundTransparency = 1
	leaderboardTitle.Font = Enum.Font.GothamBold
	leaderboardTitle.TextSize = 22
	leaderboardTitle.TextColor3 = Color3.fromRGB(250, 240, 220)
	leaderboardTitle.Text = "\240\159\143\134 Daily Challenge"
	leaderboardTitle.ZIndex = 21
	leaderboardTitle.Parent = leaderboardPanel

	local yourBestLabel = Instance.new("TextLabel")
	yourBestLabel.Size = UDim2.new(1, 0, 0, LBText.BEST_H)
	yourBestLabel.Position = UDim2.new(0, 0, 0, LBText.BEST_Y)
	yourBestLabel.BackgroundTransparency = 1
	yourBestLabel.Font = Enum.Font.Gotham
	yourBestLabel.TextSize = 14
	yourBestLabel.TextColor3 = Color3.fromRGB(200, 185, 165)
	yourBestLabel.Text = ""
	yourBestLabel.ZIndex = 21
	yourBestLabel.Parent = leaderboardPanel

	local revivedBadge = Instance.new("TextLabel")
	revivedBadge.Name = "RevivedBadge"
	revivedBadge.AnchorPoint = Vector2.new(1, 0)
	revivedBadge.Size = UDim2.new(0, 100, 0, 20)
	revivedBadge.Position = UDim2.new(1, -15, 0, LBText.BEST_Y)
	revivedBadge.BackgroundColor3 = Color3.fromRGB(70, 120, 150)
	revivedBadge.Font = Enum.Font.GothamBold
	revivedBadge.TextSize = 14
	revivedBadge.TextColor3 = Color3.fromRGB(250, 240, 220)
	revivedBadge.Text = "\u{1F4AB} Revived"
	revivedBadge.Visible = false
	revivedBadge.ZIndex = 21
	revivedBadge.Parent = leaderboardPanel
	roundCorner(revivedBadge, 9)

	local leaderboardScroll = Instance.new("ScrollingFrame")
	leaderboardScroll.Size = UDim2.new(1, -30, 1, -(LBText.SCROLL_Y + LBText.SCROLL_GAP + LBText.CLOSE_H + LBText.BOTTOM_PAD))
	leaderboardScroll.Position = UDim2.new(0, 15, 0, LBText.SCROLL_Y)
	leaderboardScroll.BackgroundTransparency = 1
	leaderboardScroll.BorderSizePixel = 0
	leaderboardScroll.ScrollBarThickness = 8
	leaderboardScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	leaderboardScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	leaderboardScroll.ZIndex = 21
	leaderboardScroll.Parent = leaderboardPanel

	local leaderboardLayout = Instance.new("UIListLayout")
	leaderboardLayout.Padding = UDim.new(0, 8)
	leaderboardLayout.SortOrder = Enum.SortOrder.LayoutOrder
	leaderboardLayout.Parent = leaderboardScroll

	local leaderboardCloseButton = Instance.new("TextButton")
	leaderboardCloseButton.Size = UDim2.new(0, LBText.CLOSE_W, 0, LBText.CLOSE_H)
	leaderboardCloseButton.Position = UDim2.new(0.5, -LBText.CLOSE_W / 2, 1, -(LBText.BOTTOM_PAD + LBText.CLOSE_H))
	leaderboardCloseButton.Font = Enum.Font.GothamBold
	leaderboardCloseButton.TextSize = 16
	leaderboardCloseButton.Text = "Close"
	leaderboardCloseButton.BackgroundColor3 = Color3.fromRGB(90, 60, 30)
	leaderboardCloseButton.TextColor3 = Color3.fromRGB(250, 240, 220)
	leaderboardCloseButton.ZIndex = 21
	leaderboardCloseButton.Parent = leaderboardPanel
	polishButton(leaderboardCloseButton, 12)
	addButtonHoverScale(leaderboardCloseButton)

	require(script.Parent.CloseX).retire(leaderboardCloseButton)
	require(script.Parent.CloseX).attach(leaderboardPanel, function()
		playClickSfx()
		popOut(leaderboardBackdrop, leaderboardPanel)
	end)

	local function clearRows()
		for _, child in ipairs(leaderboardScroll:GetChildren()) do
			if child:IsA("Frame") or child:IsA("TextLabel") then
				child:Destroy()
			end
		end
	end

	local endlessBoard = false -- the Endless board reads "Night N  |  Best hand N"
	local function makeLeaderboardRow(order, rankText, name, depth, tips, isYou, flair)
		local skin = require(script.Parent.RowSkin).get() -- the equipped Card Set's row plate, ink and rank badge; nil keeps the brown rows
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, 0, 0, LBText.ROW_H)
		row.BackgroundColor3 = skin and (isYou and skin.hot or skin.row) or (isYou and Color3.fromRGB(80, 60, 32) or Color3.fromRGB(50, 42, 34))
		row.LayoutOrder = order
		row.ZIndex = 21
		row.Parent = leaderboardScroll
		polishPanel(row, 8)

		local statsText = LBText.stats(endlessBoard, depth, tips)
		local rowW = math.max(1, leaderboardScroll.AbsoluteSize.X > 0 and (leaderboardScroll.AbsoluteSize.X - leaderboardScroll.ScrollBarThickness) or LBText.layout(1920, 1080).scroll.w)
		local parts = LBText.rowParts(rowW, rankText, statsText) -- rank, name and stats never overlap, whatever the numbers
		local rankLabel = Instance.new("TextLabel")
		rankLabel.Size = UDim2.new(0, parts.rank.w, 1, 0)
		rankLabel.Position = UDim2.new(0, parts.rank.x, 0, 0)
		rankLabel.BackgroundTransparency = 1
		rankLabel.Font = Enum.Font.GothamBold
		rankLabel.TextSize = 14
		rankLabel.TextXAlignment = Enum.TextXAlignment.Left
		rankLabel.TextColor3 = Color3.fromRGB(255, 214, 130)
		rankLabel.Text = rankText
		if skin then -- an accent rank badge with ink at 4.5:1
			rankLabel.Size = UDim2.new(0, parts.rank.w, 0, 22)
			rankLabel.Position = UDim2.new(0, parts.rank.x, 0, math.floor((LBText.ROW_H - 22) / 2))
			rankLabel.BackgroundTransparency = 0
			rankLabel.BackgroundColor3 = skin.badge
			rankLabel.TextColor3 = skin.badgeInk
			rankLabel.TextXAlignment = Enum.TextXAlignment.Center
			roundCorner(rankLabel, 6)
		end
		rankLabel.ZIndex = 21
		rankLabel.Parent = row

		local nameLabel = Instance.new("TextLabel")
		nameLabel.Size = UDim2.new(0, parts.name.w, 1, 0)
		nameLabel.Position = UDim2.new(0, parts.name.x, 0, 0)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Font = Enum.Font.GothamBold
		nameLabel.TextSize = 14
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.TextColor3 = skin and skin.ink or Color3.fromRGB(250, 240, 220)
		-- the name keeps its letters; the "(you)" tag and the title are cut first (Engine/NameFit), 14 px in the room left of the stats
		local shown = NameFit.clip(name, NameFit.MAX_NAME) .. (isYou and " (you)" or "")
		nameLabel.Text = NameFit.withTitle(shown, flair, NameFit.maxChars(parts.name.w, 14))
		nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
		nameLabel.ZIndex = 21
		nameLabel.Parent = row

		local statsLabel = Instance.new("TextLabel")
		statsLabel.Size = UDim2.new(0, parts.stats.w, 1, 0)
		statsLabel.Position = UDim2.new(0, parts.stats.x, 0, 0)
		statsLabel.TextTruncate = Enum.TextTruncate.AtEnd
		statsLabel.BackgroundTransparency = 1
		statsLabel.Font = Enum.Font.Gotham
		statsLabel.TextSize = 14
		statsLabel.TextXAlignment = Enum.TextXAlignment.Right
		statsLabel.TextColor3 = skin and skin.sub or Color3.fromRGB(200, 185, 165)
		statsLabel.Text = statsText
		statsLabel.ZIndex = 21
		statsLabel.Parent = row
	end

	-- Loading: three placeholder rows on the set's row plate (RowSkin; classic keeps the brown rows). A light strip sweeps across each
	-- once per LBText.SHIMMER_SECONDS, only when ClientSettings.motionAllowed(); in Calm mode and Reduce motion the rows stay still.
	local function makeSkeletonRows()
		local skin = require(script.Parent.RowSkin).get()
		local animate = require(script.Parent.ClientSettings).motionAllowed()
		for i = 1, LBText.SKELETON_ROWS do
			local row = Instance.new("Frame")
			row.Name = "LoadingRow"
			row.Size = UDim2.new(1, 0, 0, LBText.ROW_H)
			row.BackgroundColor3 = skin and skin.row or Color3.fromRGB(50, 42, 34)
			row.ClipsDescendants = true
			row.LayoutOrder = i
			row.ZIndex = 21
			row.Parent = leaderboardScroll
			polishPanel(row, 8)
			local strip = Instance.new("Frame")
			strip.Name = "Shimmer"
			strip.Size = UDim2.new(0.25, 0, 1, 0)
			strip.Position = UDim2.fromScale(-0.3, 0)
			strip.BackgroundColor3 = skin and skin.ink or Color3.fromRGB(250, 240, 220)
			strip.BackgroundTransparency = animate and 0.9 or 1
			strip.BorderSizePixel = 0
			strip.ZIndex = 22
			strip.Parent = row
			if animate then
				task.spawn(function()
					task.wait((i - 1) * 0.15)
					while strip.Parent and require(script.Parent.ClientSettings).motionAllowed() do
						strip.Position = UDim2.fromScale(-0.3, 0)
						local sweep = game:GetService("TweenService"):Create(strip, TweenInfo.new(LBText.SHIMMER_SECONDS, Enum.EasingStyle.Sine), { Position = UDim2.fromScale(1.05, 0) })
						sweep:Play()
						task.wait(LBText.SHIMMER_SECONDS + 0.3) -- not Completed:Wait(), so a destroyed row never leaves a thread waiting
					end
				end)
			end
		end
	end

	local function makeLeaderboardMessage(text)
		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(1, 0, 0, 44)
		label.TextWrapped = true
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.Gotham
		label.TextSize = 14
		label.TextColor3 = Color3.fromRGB(200, 185, 165)
		label.Text = text
		label.ZIndex = 21
		label.Parent = leaderboardScroll
	end

	-- WEEKLY CHALLENGE (Phase 16): which board is currently showing --
	-- "daily" or "weekly". Read by refreshLeaderboard and by the 2 tab
	-- buttons' click handlers below (which flip it and re-refresh).
	local activeBoard = "daily"
	-- ONE MORE ROUND: Leaderboards.STANDARD or Leaderboards.REVIVED.
	local activeBucket = Leaderboards.STANDARD
	-- GLOBAL (everyone, cached on the server) or FRIENDS.
	local activeScope = Leaderboards.GLOBAL

	local ACTIVE_TAB = Color3.fromRGB(110, 80, 40)
	local IDLE_TAB = Color3.fromRGB(70, 55, 40)
	local function updateTabHighlight()
		dailyTabButton.BackgroundColor3 = (activeBoard == "daily") and ACTIVE_TAB or IDLE_TAB
		weeklyTabButton.BackgroundColor3 = (activeBoard == "weekly") and ACTIVE_TAB or IDLE_TAB
		endlessTabButton.BackgroundColor3 = (activeBoard == "endless") and ACTIVE_TAB or IDLE_TAB
		friendsTabButton.Text = (activeScope == Leaderboards.FRIENDS) and "\u{1F465} Friends" or "\u{1F30D} Global"
		standardTabButton.BackgroundColor3 = (activeBucket == Leaderboards.STANDARD) and ACTIVE_TAB or IDLE_TAB
		revivedTabButton.BackgroundColor3 = (activeBucket == Leaderboards.REVIVED) and ACTIVE_TAB or IDLE_TAB
		friendsTabButton.BackgroundColor3 = (activeScope == Leaderboards.FRIENDS) and ACTIVE_TAB or IDLE_TAB
		pcall(function() -- the equipped Card Set's tab plates (green when lit); classic keeps the flat browns above
			local Kit = require(script.Parent.TavernKit)
			Kit.setPlateTab(dailyTabButton, activeBoard == "daily")
			Kit.setPlateTab(weeklyTabButton, activeBoard == "weekly")
			Kit.setPlateTab(endlessTabButton, activeBoard == "endless")
			Kit.setPlateTab(standardTabButton, activeBucket == Leaderboards.STANDARD)
			Kit.setPlateTab(revivedTabButton, activeBucket == Leaderboards.REVIVED)
			Kit.setPlateTab(friendsTabButton, activeScope == Leaderboards.FRIENDS)
		end)
	end

	local function refreshLeaderboard()
		clearRows()
		yourBestLabel.Text = ""
		revivedBadge.Visible = false
		makeLeaderboardMessage(LBText.LOADING)
		makeSkeletonRows()
		updateTabHighlight()

		local remote = (activeBoard == "weekly") and GetWeeklyLeaderboardRemote or GetDailyLeaderboardRemote
		local icon = (activeBoard == "weekly") and "\240\159\151\147" or "\240\159\143\134"
		local label = (activeBoard == "weekly") and "Weekly Challenge" or "Daily Challenge"
		local period = (activeBoard == "weekly") and "this week" or "today"
		endlessBoard = false
		if activeBoard == "endless" then
			remote, icon, label, period = GetEndlessLeaderboardRemote, "\u{267E}", "Endless Mode", "so far"
			endlessBoard = true
		end
		-- Captured up front so a late-returning InvokeServer for a board
		-- the player has since tabbed AWAY from doesn't paint its result
		-- into the other tab's UI.
		local requestedBoard = activeBoard
		local requestedBucket = activeBucket
		local requestedScope = activeScope

		task.spawn(function()
			local ok, result = pcall(function()
				return remote:InvokeServer(requestedBucket, requestedScope)
			end)

			-- The player may have closed the overlay (or the whole client
			-- may have torn down) by the time this yielding InvokeServer
			-- call returns -- checking Visible (not just .Parent, which
			-- nothing in this codebase ever actually clears via Destroy())
			-- is what actually catches "player already hit Close": bail
			-- out quietly rather than repaint a panel nobody's looking at.
			-- Also bail if they've since switched tabs (see requestedBoard
			-- above) -- that other tab's own refreshLeaderboard call is
			-- already handling its own repaint.
			if not leaderboardBackdrop.Visible or not leaderboardPanel.Parent or requestedBoard ~= activeBoard or requestedBucket ~= activeBucket or requestedScope ~= activeScope then
				return
			end

			clearRows()

			if not ok or not result then
				makeLeaderboardMessage(LBText.OFFLINE)
				return
			end

			leaderboardTitle.Text = icon .. " " .. label .. ((result.dateKey and result.dateKey ~= "alltime") and (": " .. tostring(result.dateKey)) or "")
			revivedBadge.Visible = requestedBucket == Leaderboards.REVIVED

			yourBestLabel.Text = LBText.yourBest(activeBoard == "endless", period, result.yourBestOk, result.yourBestOk and result.yourBest or nil)

			if not result.ok then
				makeLeaderboardMessage(LBText.TOP_FAILED)
				return
			end

			local top = result.top or {}
			if #top == 0 then
				makeLeaderboardMessage(LBText.empty(requestedScope == Leaderboards.FRIENDS))
				return
			end

			local localUserId = localPlayer and localPlayer.UserId
			for i, entry in ipairs(top) do
				local flairParts = {}
				if entry.badgeIcon then table.insert(flairParts, entry.badgeIcon) end
				if entry.titleText then table.insert(flairParts, entry.titleText) end
				if entry.cardBackName then table.insert(flairParts, entry.cardBackName .. " back") end
					if entry.tavernRank then table.insert(flairParts, "Rank " .. tostring(entry.tavernRank)) end
				makeLeaderboardRow(i, LBText.rank(entry.rank or i), (entry.vip and "\u{2605} " or "") .. (entry.name or "???"), entry.depth or 0, entry.tips or 0, entry.userId ~= nil and entry.userId == localUserId, table.concat(flairParts, ", "))
			end
		end)
	end

	dailyTabButton.MouseButton1Click:Connect(function()
		playClickSfx()
		if activeBoard ~= "daily" then
			activeBoard = "daily"
			refreshLeaderboard()
		end
	end)

	weeklyTabButton.MouseButton1Click:Connect(function()
		playClickSfx()
		if activeBoard ~= "weekly" then
			activeBoard = "weekly"
			refreshLeaderboard()
		end
	end)

	standardTabButton.MouseButton1Click:Connect(function()
		playClickSfx()
		if activeBucket ~= Leaderboards.STANDARD then
			activeBucket = Leaderboards.STANDARD
			refreshLeaderboard()
		end
	end)

	revivedTabButton.MouseButton1Click:Connect(function()
		playClickSfx()
		if activeBucket ~= Leaderboards.REVIVED then
			activeBucket = Leaderboards.REVIVED
			refreshLeaderboard()
		end
	end)

	endlessTabButton.MouseButton1Click:Connect(function()
		playClickSfx()
		if activeBoard ~= "endless" then
			activeBoard = "endless"
			refreshLeaderboard()
		end
	end)

	friendsTabButton.MouseButton1Click:Connect(function()
		playClickSfx()
		activeScope = (activeScope == Leaderboards.FRIENDS) and Leaderboards.GLOBAL or Leaderboards.FRIENDS
		refreshLeaderboard()
	end)

	OverlayManager.register("dailyLeaderboard", function()
		popOut(leaderboardBackdrop, leaderboardPanel)
	end)
	-- Escape and a click on the dark area close it (Client/PopupDismiss).
	require(script.Parent.PopupDismiss).attach(leaderboardBackdrop, { id = "dailyLeaderboard", panel = leaderboardPanel, button = true })

	local function openLeaderboard()
		playClickSfx()
		OverlayManager.closeAllExcept("dailyLeaderboard")
		activeBucket = Leaderboards.STANDARD -- every open starts on Standard
		activeScope = Leaderboards.GLOBAL -- and on the Global board
		refreshLeaderboard()
		popIn(leaderboardBackdrop, leaderboardPanel)
	end
	leaderboardButton.MouseButton1Click:Connect(openLeaderboard)
	OverlayManager.registerOpener("dailyLeaderboard", openLeaderboard) -- the Menu's chalkboard hotspot
	if deps.menuTickerButton then -- the main menu strip's "Daily board" button opens the same overlay
		deps.menuTickerButton.MouseButton1Click:Connect(openLeaderboard)
	end

	return {}
end
