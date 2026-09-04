--[[
	Client/DailyLeaderboard.lua
	DAILY CHALLENGE (Phase 11): shows today's top 10 Daily Challenge scores
	(by "depth" -- rounds fully cleared, see Server/init.server.lua's
	computeDailyDepth -- tips as the tiebreak) plus the player's own best
	for today, whether or not it placed in the top 10. Reachable from a new
	"🏆" corner button, mirroring Collection.lua's "📔" pattern exactly
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
		leaderboardButton            -- TextButton, the in-game "🏆" corner button
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
	local popIn = deps.popIn
	local popOut = deps.popOut
	local addButtonHoverScale = deps.addButtonHoverScale
	local localPlayer = deps.localPlayer

	local leaderboardBackdrop = Instance.new("Frame")
	leaderboardBackdrop.Name = "DailyLeaderboardBackdrop"
	leaderboardBackdrop.Size = UDim2.fromScale(1, 1)
	leaderboardBackdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	leaderboardBackdrop.BackgroundTransparency = 0.4
	leaderboardBackdrop.Visible = false
	leaderboardBackdrop.ZIndex = 20
	leaderboardBackdrop.Parent = screenGui

	local leaderboardPanel = Instance.new("Frame")
	leaderboardPanel.Size = UDim2.fromScale(0.5, 0.65)
	leaderboardPanel.Position = UDim2.fromScale(0.25, 0.17)
	leaderboardPanel.BackgroundColor3 = Color3.fromRGB(40, 30, 22)
	leaderboardPanel.ZIndex = 21
	leaderboardPanel.Parent = leaderboardBackdrop
	polishPanel(leaderboardPanel, 16)
	addSoftShadow(leaderboardPanel, 18)

	-- WEEKLY CHALLENGE (Phase 16): Daily/Weekly tab row, above the title.
	local function makeTabButton(text, xOffset)
		local button = Instance.new("TextButton")
		button.Size = UDim2.new(0, 90, 0, 26)
		button.Position = UDim2.new(0, xOffset, 0, 0)
		button.Font = Enum.Font.GothamBold
		button.TextSize = 13
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

	local leaderboardTitle = Instance.new("TextLabel")
	leaderboardTitle.Size = UDim2.new(1, 0, 0, 26)
	leaderboardTitle.Position = UDim2.new(0, 0, 0, 32)
	leaderboardTitle.BackgroundTransparency = 1
	leaderboardTitle.Font = Enum.Font.GothamBold
	leaderboardTitle.TextSize = 22
	leaderboardTitle.TextColor3 = Color3.fromRGB(250, 240, 220)
	leaderboardTitle.Text = "\240\159\143\134 Daily Challenge"
	leaderboardTitle.ZIndex = 21
	leaderboardTitle.Parent = leaderboardPanel

	local yourBestLabel = Instance.new("TextLabel")
	yourBestLabel.Size = UDim2.new(1, 0, 0, 18)
	yourBestLabel.Position = UDim2.new(0, 0, 0, 58)
	yourBestLabel.BackgroundTransparency = 1
	yourBestLabel.Font = Enum.Font.Gotham
	yourBestLabel.TextSize = 13
	yourBestLabel.TextColor3 = Color3.fromRGB(200, 185, 165)
	yourBestLabel.Text = ""
	yourBestLabel.ZIndex = 21
	yourBestLabel.Parent = leaderboardPanel

	local leaderboardScroll = Instance.new("ScrollingFrame")
	leaderboardScroll.Size = UDim2.new(1, -30, 1, -142)
	leaderboardScroll.Position = UDim2.new(0, 15, 0, 77)
	leaderboardScroll.BackgroundTransparency = 1
	leaderboardScroll.BorderSizePixel = 0
	leaderboardScroll.ScrollBarThickness = 8
	leaderboardScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	leaderboardScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	leaderboardScroll.ZIndex = 21
	leaderboardScroll.Parent = leaderboardPanel

	local leaderboardLayout = Instance.new("UIListLayout")
	leaderboardLayout.Padding = UDim.new(0, 8)
	leaderboardLayout.Parent = leaderboardScroll

	local leaderboardCloseButton = Instance.new("TextButton")
	leaderboardCloseButton.Size = UDim2.new(0, 140, 0, 40)
	leaderboardCloseButton.Position = UDim2.new(0.5, -70, 1, -50)
	leaderboardCloseButton.Font = Enum.Font.GothamBold
	leaderboardCloseButton.TextSize = 16
	leaderboardCloseButton.Text = "Close"
	leaderboardCloseButton.BackgroundColor3 = Color3.fromRGB(90, 60, 30)
	leaderboardCloseButton.TextColor3 = Color3.fromRGB(250, 240, 220)
	leaderboardCloseButton.ZIndex = 21
	leaderboardCloseButton.Parent = leaderboardPanel
	polishButton(leaderboardCloseButton, 12)
	addButtonHoverScale(leaderboardCloseButton)

	leaderboardCloseButton.MouseButton1Click:Connect(function()
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

	local function makeLeaderboardRow(order, rankText, name, depth, tips, isYou)
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, 0, 0, 34)
		row.BackgroundColor3 = isYou and Color3.fromRGB(80, 60, 32) or Color3.fromRGB(50, 42, 34)
		row.LayoutOrder = order
		row.ZIndex = 21
		row.Parent = leaderboardScroll
		polishPanel(row, 8)

		local rankLabel = Instance.new("TextLabel")
		rankLabel.Size = UDim2.new(0, 40, 1, 0)
		rankLabel.Position = UDim2.new(0, 8, 0, 0)
		rankLabel.BackgroundTransparency = 1
		rankLabel.Font = Enum.Font.GothamBold
		rankLabel.TextSize = 14
		rankLabel.TextXAlignment = Enum.TextXAlignment.Left
		rankLabel.TextColor3 = Color3.fromRGB(255, 214, 130)
		rankLabel.Text = rankText
		rankLabel.ZIndex = 21
		rankLabel.Parent = row

		local nameLabel = Instance.new("TextLabel")
		nameLabel.Size = UDim2.new(1, -220, 1, 0)
		nameLabel.Position = UDim2.new(0, 52, 0, 0)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Font = Enum.Font.GothamBold
		nameLabel.TextSize = 14
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.TextColor3 = Color3.fromRGB(250, 240, 220)
		nameLabel.Text = isYou and (name .. " (you)") or name
		nameLabel.ZIndex = 21
		nameLabel.Parent = row

		local statsLabel = Instance.new("TextLabel")
		statsLabel.Size = UDim2.new(0, 160, 1, 0)
		statsLabel.Position = UDim2.new(1, -168, 0, 0)
		statsLabel.BackgroundTransparency = 1
		statsLabel.Font = Enum.Font.Gotham
		statsLabel.TextSize = 13
		statsLabel.TextXAlignment = Enum.TextXAlignment.Right
		statsLabel.TextColor3 = Color3.fromRGB(200, 185, 165)
		statsLabel.Text = string.format("Depth %d  |  %d Tips", depth, tips)
		statsLabel.ZIndex = 21
		statsLabel.Parent = row
	end

	local function makeLeaderboardMessage(text)
		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(1, 0, 0, 28)
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

	local function updateTabHighlight()
		dailyTabButton.BackgroundColor3 = (activeBoard == "daily") and Color3.fromRGB(110, 80, 40) or Color3.fromRGB(70, 55, 40)
		weeklyTabButton.BackgroundColor3 = (activeBoard == "weekly") and Color3.fromRGB(110, 80, 40) or Color3.fromRGB(70, 55, 40)
	end

	local function refreshLeaderboard()
		clearRows()
		yourBestLabel.Text = ""
		makeLeaderboardMessage("Loading...")
		updateTabHighlight()

		local remote = (activeBoard == "weekly") and GetWeeklyLeaderboardRemote or GetDailyLeaderboardRemote
		local icon = (activeBoard == "weekly") and "\240\159\151\147" or "\240\159\143\134"
		local label = (activeBoard == "weekly") and "Weekly Challenge" or "Daily Challenge"
		local period = (activeBoard == "weekly") and "this week" or "today"
		-- Captured up front so a late-returning InvokeServer for a board
		-- the player has since tabbed AWAY from doesn't paint its result
		-- into the other tab's UI.
		local requestedBoard = activeBoard

		task.spawn(function()
			local ok, result = pcall(function()
				return remote:InvokeServer()
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
			if not leaderboardBackdrop.Visible or not leaderboardPanel.Parent or requestedBoard ~= activeBoard then
				return
			end

			clearRows()

			if not ok or not result then
				makeLeaderboardMessage("Couldn't reach the server. Try again in a moment.")
				return
			end

			leaderboardTitle.Text = icon .. " " .. label .. " -- " .. tostring(result.dateKey or "")

			if result.yourBestOk and result.yourBest then
				yourBestLabel.Text = string.format(
					"Your best %s: Depth %d, %d Tips",
					period, result.yourBest.depth, result.yourBest.tips
				)
			elseif result.yourBestOk then
				yourBestLabel.Text = "You haven't set a score " .. period .. " yet -- play a " .. label .. " run!"
			else
				yourBestLabel.Text = "Couldn't check your best score."
			end

			if not result.ok then
				makeLeaderboardMessage("Couldn't load the top 10 right now. Try again in a moment.")
				return
			end

			local top = result.top or {}
			if #top == 0 then
				makeLeaderboardMessage("Nobody's set a score yet " .. period .. " -- be the first!")
				return
			end

			local localUserId = localPlayer and localPlayer.UserId
			for i, entry in ipairs(top) do
				makeLeaderboardRow(i, "#" .. tostring(i), entry.name or "???", entry.depth or 0, entry.tips or 0, entry.userId ~= nil and entry.userId == localUserId)
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

	leaderboardButton.MouseButton1Click:Connect(function()
		playClickSfx()
		refreshLeaderboard()
		popIn(leaderboardBackdrop, leaderboardPanel)
	end)

	return {}
end
