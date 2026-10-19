--[[
	Client/PhaseB.lua
	PHASE B (Alive & Social pass, see claude/mind-blowing-plan.md): two
	small, ambient, ALWAYS-ON corner panels, bundled into one module/
	require for the same top-level-local-budget reason as PhaseA.lua (see
	that file's own header) -- init.client.lua is already right at Lua's
	200-local-per-chunk ceiling, and each separate top-level
	`local XModule = require(...)` costs one of those 200 slots. This
	module also looks up its OWN RemoteEvents off `deps.remotes` instead
	of having init.client.lua hand them over as 2 more top-level locals.

	== Live Leaderboard Ticker ==
	A small corner panel showing today's top Daily Challenge standings,
	refreshed by the server's own broadcast (Server/init.server.lua's
	LeaderboardTicker RemoteEvent, FireAllClients -- not something this
	module requests) roughly every 45s, plus right after any join/leave.
	Purely cosmetic/display -- this module never calls DataStore itself,
	and never gates anything -- it's ambient flavor, not a UI the player
	has to act on.

	== Friend Presence ==
	A small corner panel listing which of your Roblox friends are
	currently in THIS server and what they're up to (their live Night/
	Round, if they're mid-run) -- fed by the server's own FriendPresence
	RemoteEvent (FireClient, personal to you -- nobody else's friends list
	is your business, and vice versa). Hidden entirely when empty, so a
	solo session looks exactly like it always has.

	deps fields:
		root     -- Frame, the full-screen gameplay root (both panels' parent)
		remotes  -- Folder, ReplicatedStorage.Remotes

	Returns {} -- nothing needs to come back out; both panels drive
	themselves entirely off their own RemoteEvents.
]]

return function(deps)
	local root = deps.root
	local remotes = deps.remotes

	-- Shared little "corner card" builder -- both panels are the exact
	-- same shape (title + up to 5 rows), just different corners/colors/
	-- content, so building the chrome once keeps this file from being
	-- twice as long for no real benefit.
	local function buildCornerCard(name, anchor, position, titleText, titleColor)
		local panel = Instance.new("Frame")
		panel.Name = name
		panel.AnchorPoint = anchor
		panel.Position = position
		panel.Size = UDim2.new(0, 220, 0, 0)
		panel.AutomaticSize = Enum.AutomaticSize.Y
		panel.BackgroundColor3 = Color3.fromRGB(18, 14, 20)
		panel.BackgroundTransparency = 0.25
		panel.BorderSizePixel = 0
		panel.Visible = false -- hidden until the first real payload arrives
		panel.ZIndex = 20
		panel.Parent = root

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 8)
		corner.Parent = panel

		local padding = Instance.new("UIPadding")
		padding.PaddingTop = UDim.new(0, 8)
		padding.PaddingBottom = UDim.new(0, 8)
		padding.PaddingLeft = UDim.new(0, 10)
		padding.PaddingRight = UDim.new(0, 10)
		padding.Parent = panel

		local layout = Instance.new("UIListLayout")
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Padding = UDim.new(0, 2)
		layout.Parent = panel

		local title = Instance.new("TextLabel")
		title.Size = UDim2.new(1, 0, 0, 16)
		title.BackgroundTransparency = 1
		title.Font = Enum.Font.GothamBold
		title.TextSize = 13
		title.TextColor3 = titleColor
		title.TextXAlignment = Enum.TextXAlignment.Left
		title.Text = titleText
		title.LayoutOrder = 1
		title.ZIndex = 20
		title.Parent = panel

		local rows = {}
		for i = 1, 5 do
			local row = Instance.new("TextLabel")
			row.Size = UDim2.new(1, 0, 0, 16)
			row.BackgroundTransparency = 1
			row.Font = Enum.Font.Gotham
			row.TextSize = 13
			row.TextColor3 = Color3.fromRGB(228, 224, 230)
			row.TextXAlignment = Enum.TextXAlignment.Left
			row.TextTruncate = Enum.TextTruncate.AtEnd
			row.Text = ""
			row.Visible = false
			row.LayoutOrder = i + 1
			row.ZIndex = 20
			row.Parent = panel
			table.insert(rows, row)
		end

		return panel, rows
	end

	-- ===== Live Leaderboard Ticker =====

	-- BUGFIX (Ahmed's report: "today's best on the top right clearly
	-- covers some of the buttons"). This used to sit at y=12 -- the exact
	-- same top-12px strip as init.client.lua's row of 44px corner icon
	-- buttons (help/mute/Themes/Journey/Hand Reference/Settings/
	-- Collection/Leaderboard, all at y=8, 44px tall -- see makeCornerButton
	-- there), so the panel's own ZIndex (20, well above those buttons'
	-- ZIndex 5) sat right on top of however many of them it was wide
	-- enough to reach. Dropped to y=68 -- comfortably clear of that whole
	-- row (8 + 44 = 52, +16px breathing room) -- instead of guessing a
	-- narrower width that could still clip a button on a smaller window.
	local tickerPanel, tickerRows = buildCornerCard(
		"LeaderboardTicker", Vector2.new(1, 0), UDim2.new(1, -12, 0, 68),
		"👑 TODAY'S BEST", Color3.fromRGB(255, 210, 120)
	)

	-- Small dismiss control, same spot/shape a mobile notification toast
	-- would use -- lets Ahmed (or anyone) hide this ambient panel for the
	-- rest of the session if even the repositioned spot is ever in the
	-- way of something else, without needing a dedicated Settings entry
	-- just for one cosmetic corner panel (also sidesteps adding another
	-- top-level local to init.client.lua, which is already right at
	-- Lua's 200-local ceiling -- this whole toggle lives inside PhaseB.lua's
	-- own closure instead, same pattern as everything else in this file).
	local tickerDismissed = false
	local tickerDismissButton = Instance.new("TextButton")
	tickerDismissButton.Size = UDim2.new(0, 18, 0, 18)
	tickerDismissButton.Position = UDim2.new(1, -2, 0, -2)
	tickerDismissButton.AnchorPoint = Vector2.new(1, 0)
	tickerDismissButton.BackgroundTransparency = 1
	tickerDismissButton.Font = Enum.Font.GothamBold
	tickerDismissButton.TextSize = 14
	tickerDismissButton.TextColor3 = Color3.fromRGB(200, 190, 180)
	tickerDismissButton.Text = "✕"
	tickerDismissButton.ZIndex = 21
	tickerDismissButton.Parent = tickerPanel

	local LeaderboardTickerRemote = remotes:WaitForChild("LeaderboardTicker")
	LeaderboardTickerRemote.OnClientEvent:Connect(function(payload)
		if tickerDismissed then
			return
		end
		local top = (payload and payload.top) or {}
		if #top == 0 then
			tickerPanel.Visible = false
			return
		end
		tickerPanel.Visible = true
		for i, row in ipairs(tickerRows) do
			local entry = top[i]
			if entry then
				row.Visible = true
				-- "Depth %d | %d Tips" matches DailyLeaderboard.lua's own
				-- stat line wording -- same number, same name, just ambient
				-- instead of behind a menu.
				row.Text = string.format("%d. %s -- Depth %d, %d Tips", i, entry.name or "???", entry.depth or 0, entry.tips or 0)
			else
				row.Visible = false
			end
		end
	end)

	tickerDismissButton.MouseButton1Click:Connect(function()
		tickerDismissed = true
		tickerPanel.Visible = false
	end)

	-- ===== Friend Presence =====

	local friendsPanel, friendRows = buildCornerCard(
		"FriendPresence", Vector2.new(1, 1), UDim2.new(1, -12, 1, -12),
		"🫂 FRIENDS HERE", Color3.fromRGB(150, 210, 255)
	)

	local FriendPresenceRemote = remotes:WaitForChild("FriendPresence")
	FriendPresenceRemote.OnClientEvent:Connect(function(friendsList)
		friendsList = friendsList or {}
		if #friendsList == 0 then
			friendsPanel.Visible = false
			return
		end
		friendsPanel.Visible = true
		for i, row in ipairs(friendRows) do
			local friend = friendsList[i]
			if friend then
				row.Visible = true
				if friend.night then
					row.Text = string.format("%s -- Night %d, Round %d", friend.name, friend.night, friend.round or 1)
				else
					row.Text = (friend.name or "???") .. " -- in the tavern"
				end
			else
				row.Visible = false
			end
		end
	end)

	return {}
end
