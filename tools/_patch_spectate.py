p = "src/Client/SpectatePanel.lua"
s = open(p, encoding="utf-8").read()

s = s.replace('''	local blockButton = smallButton("Block", -78, Color3.fromRGB(70, 55, 40))
''', '')
s = s.replace('''	local watchedUserId -- set when a snapshot says who it is (the Friend Presence button knows the id)
	blockButton.MouseButton1Click:Connect(function()
		-- blocking is a request for the OTHER player's profile only when THEY block ME; here it hides this table for me
		ActionRemote:FireServer("stop")
		stopWatching()
	end)
	_ = watchedUserId
''', '')
s = s.replace('''	badge.MouseEnter:Connect(function() namesLabel.Visible = badge.Visible and namesLabel.Text ~= "" end)
	badge.MouseLeave:Connect(function() namesLabel.Visible = false end)''', '''	badge.MouseEnter:Connect(function() namesLabel.Visible = badge.Visible and namesLabel.Text ~= "" end)
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
			label(row, { Size = UDim2.new(1, -70, 1, 0), Position = UDim2.fromOffset(6, 0), Font = Enum.Font.GothamMedium, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Text = v.name or "?", ZIndex = 94 })
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
	end)''')
s = s.replace('''		namesLabel.Text = table.concat(e.names or {}, ", ")''', '''		namesLabel.Text = table.concat(e.names or {}, ", ")
		viewersNow = type(e.viewers) == "table" and e.viewers or {}
		if list.Visible then rebuildList() end
		if count == 0 then list.Visible = false end''')
open(p, "w", encoding="utf-8").write(s)

q = "src/Server/init.server.lua"
t = open(q, encoding="utf-8").read()
old = '''	local names = {}
	for _, id in ipairs(viewers) do
		local v = Players:GetPlayerByUserId(id)
		if v then names[#names + 1] = Spec.name(v) end
	end
	if Rem.SpectateStream then
		pcall(function() Rem.SpectateStream:FireClient(target, { kind = "watchers", count = #viewers, names = names }) end)
	end'''
new = '''	local names, rows = {}, {}
	for _, id in ipairs(viewers) do
		local v = Players:GetPlayerByUserId(id)
		if v then
			names[#names + 1] = Spec.name(v)
			rows[#rows + 1] = { id = id, name = Spec.name(v) } -- the watched player may block any of them
		end
	end
	if Rem.SpectateStream then
		pcall(function() Rem.SpectateStream:FireClient(target, { kind = "watchers", count = #viewers, names = names, viewers = rows }) end)
	end'''
assert old in t
t = t.replace(old, new)
open(q, "w", encoding="utf-8").write(t)
print("ok")
