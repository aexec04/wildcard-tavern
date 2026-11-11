--[[
	Client/PhaseB.lua
	PHASE B (Alive & Social pass, see claude/mind-blowing-plan.md): a
	small, ambient, ALWAYS-ON corner panel, kept in its own module/
	require for the same top-level-local-budget reason as PhaseA.lua (see
	that file's own header) -- init.client.lua is already right at Lua's
	200-local-per-chunk ceiling, and each separate top-level
	`local XModule = require(...)` costs one of those 200 slots. This
	module also looks up its OWN RemoteEvents off `deps.remotes` instead
	of having init.client.lua hand them over as 2 more top-level locals.

	(The top-right "Today's Best" Live Leaderboard Ticker that used to
	live here too was removed -- the Daily/Weekly leaderboard panel
	already shows the same standings on demand.)

	== Friend Presence ==
	A small corner panel listing which of your Roblox friends are
	currently in THIS server and what they're up to (their live Night/
	Round, if they're mid-run) -- fed by the server's own FriendPresence
	RemoteEvent (FireClient, personal to you -- nobody else's friends list
	is your business, and vice versa). Hidden entirely when empty, so a
	solo session looks exactly like it always has.

	deps fields:
		root     -- Frame, the full-screen gameplay root (the panel's parent)
		remotes  -- Folder, ReplicatedStorage.Remotes

	Returns {} -- nothing needs to come back out; the panel drives
	itself entirely off its own RemoteEvent.
]]

return function(deps)
	local root = deps.root
	local remotes = deps.remotes

	-- Little "corner card" builder (title + up to 5 rows) -- kept generic
	-- so another ambient corner panel can reuse it.
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
		title.TextSize = 14
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
			row.TextSize = 14
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
			-- SPECTATE: a Watch button on a friend who is in a run (the server re-checks every request)
			local watch = row:FindFirstChild("WatchButton")
			if not watch then
				watch = Instance.new("TextButton")
				watch.Name = "WatchButton"
				watch.Size = UDim2.fromOffset(58, 22)
				watch.AnchorPoint = Vector2.new(1, 0.5)
				watch.Position = UDim2.new(1, 0, 0.5, 0)
				watch.Font = Enum.Font.GothamBold
				watch.TextSize = 14
				watch.TextColor3 = Color3.fromRGB(250, 235, 200)
				watch.BackgroundColor3 = Color3.fromRGB(70, 110, 150)
				watch.ZIndex = 22
				watch.Visible = false
				watch.Parent = row
				local wc = Instance.new("UICorner")
				wc.CornerRadius = UDim.new(0, 6)
				wc.Parent = watch
				watch.MouseButton1Click:Connect(function()
					local spectateRemote = remotes:FindFirstChild("SpectateAction")
					local id = watch:GetAttribute("UserId")
					if spectateRemote and type(id) == "number" then
						spectateRemote:FireServer(watch:GetAttribute("Watching") == true and "stop" or "watch", id)
					end
				end)
			end
			watch.Visible = friend ~= nil and friend.canWatch == true
			if friend then
				watch:SetAttribute("UserId", friend.userId)
				watch:SetAttribute("Watching", friend.watching == true)
				watch.Text = friend.watching and "Stop" or "Watch"
			end
			if friend then
				row.Visible = true
				if friend.night then
					row.Text = string.format("%s, Night %d, Round %d", friend.name, friend.night, friend.round or 1)
				else
					row.Text = (friend.name or "???") .. ", in the tavern"
				end
			else
				row.Visible = false
			end
		end
	end)

	return {}
end
