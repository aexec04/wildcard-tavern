--[[
	Client/RoundHintsFX.lua
	The hint plates of the first three rounds (Engine/RoundHints): one small dark plate beside the score stage with a title, one
	sentence and a 44 px "Got it" plate. Shown once per profile (the id is reported through the HintSeen remote the moment it shows),
	skipped in Calm mode and when the Round Hints setting is off. No tweens at all, so Calm mode and Reduce motion are the same.
	Display only: it never takes a click except its own button and never changes the run.

	update(layer, state, selectedCount, rects, viewW, viewH)   from Gameplay2.update; hides itself when nothing is due or nothing fits
	hide()
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Engine = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine")
local Rules = require(Engine:WaitForChild("RoundHints"))
local ClientSettings = require(script.Parent.ClientSettings)

local M = {}
local plate, title, body, button
local current -- id of the plate that is up
local localSeen = {} -- shown or dismissed this session, so nothing repeats before the server state echoes back

local GOLD = Color3.fromRGB(246, 196, 70)

local function build(layer)
	plate = Instance.new("Frame")
	plate.Name = "RoundHint"
	plate.BackgroundColor3 = Color3.fromRGB(46, 28, 14)
	plate.BackgroundTransparency = 0.05
	plate.BorderSizePixel = 0
	plate.Active = false
	plate.ZIndex = 28
	plate.Parent = layer
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 10); c.Parent = plate
	local st = Instance.new("UIStroke"); st.Color = GOLD; st.Thickness = 2; st.Parent = plate
	local function label(name, y, h, size, color, font)
		local t = Instance.new("TextLabel")
		t.Name = name
		t.BackgroundTransparency = 1
		t.Font = font
		t.TextSize = size
		t.TextColor3 = color
		t.TextTransparency = 0
		t.TextStrokeTransparency = 1
		t.TextWrapped = true
		t.TextXAlignment = Enum.TextXAlignment.Left
		t.TextYAlignment = Enum.TextYAlignment.Top
		t.Size = UDim2.new(0.62, 0, 0, h) -- right of the crown window (the picture's left 29 percent), clear of the gold trim
		t.Position = UDim2.new(0.31, 0, 0, y)
		t.ZIndex = 29
		t.Parent = plate
		return t
	end
	local TC = Rules.TITLE_COLOR
	title = label("Title", 14, 22, 18, Color3.fromRGB(TC[1], TC[2], TC[3]), Enum.Font.Merriweather)
	body = label("Body", 38, 36, 15, Color3.fromRGB(235, 218, 180), Enum.Font.Gotham)
	button = Instance.new("TextButton")
	button.Name = "RoundHintGotIt"
	button.ZIndex = 30
	pcall(function() require(script.Parent.TavernKit).skin(button, "Got it", "primary") end)
	do -- dark wood plate with a gold edge and gold text, set after the kit skin; no tween, so Calm mode is the same
		local G = Rules.GOT_IT
		local base = Color3.fromRGB(G.fill[1], G.fill[2], G.fill[3])
		local hot = Color3.fromRGB(G.hover[1], G.hover[2], G.hover[3])
		for _, d in ipairs(button:GetChildren()) do
			if d:IsA("UIGradient") or d:IsA("UIStroke") then d:Destroy() end
		end
		local edge = Instance.new("UIStroke")
		edge.Name = "GotItEdge"
		edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		edge.Color = Color3.fromRGB(G.edge[1], G.edge[2], G.edge[3])
		edge.Thickness = 2
		edge.Parent = button
		button.BackgroundColor3 = base
		button.TextColor3 = Color3.fromRGB(G.text[1], G.text[2], G.text[3])
		button.TextStrokeColor3 = Color3.fromRGB(G.stroke[1], G.stroke[2], G.stroke[3])
		button.TextStrokeTransparency = 0
		button.TextTransparency = 0
		button.TextSize = 18
		button.MouseEnter:Connect(function() button.BackgroundColor3 = hot end)
		button.MouseLeave:Connect(function() button.BackgroundColor3 = base end)
	end
	button.Parent = layer
	button.MouseButton1Click:Connect(function()
		if current then localSeen[current] = true end
		pcall(function()
			local PP = require(script.Parent.PatronPowerPanelFX)
			PP.yieldTo(false) -- a panel that waited for the hint shows again; Got it never closes the panel
		end)
		M.hide()
	end)
end

function M.hide()
	current = nil
	pcall(function() require(script.Parent.PatronPowerPanelFX).yieldTo(false) end)
	if plate then plate.Visible = false end
	if button then button.Visible = false end
end

function M.update(layer, state, selectedCount, rects, viewW, viewH)
	local calm = ClientSettings.get("reduceShake") == true
	local opts = { enabled = ClientSettings.get("roundHints") ~= false, calm = calm, panelOwnsTiers = true }
	if not Rules.enabledFor(state, opts) then M.hide(); return end
	if current and (Rules.satisfied(current, selectedCount) or Rules.expired(current, state)) then
		localSeen[current] = true
		M.hide()
	end
	for _, e in ipairs(Rules.ORDER) do -- a plate that expired before it ever showed is marked seen, so it never comes later
		if Rules.expired(e.id, state) and not localSeen[e.id] and not (type(state.hintsSeen) == "table" and state.hintsSeen[e.id]) then
			localSeen[e.id] = true
			local remotes = ReplicatedStorage:FindFirstChild("Remotes")
			local seenRemote = remotes and remotes:FindFirstChild("HintSeen")
			if seenRemote then seenRemote:FireServer(e.id) end
		end
	end
	local entry = current and Rules.getById(current)
	if not entry then
		local seen = {}
		for id in pairs(type(state.hintsSeen) == "table" and state.hintsSeen or {}) do seen[id] = true end
		for id in pairs(localSeen) do seen[id] = true end
		entry = Rules.next(state, seen, opts)
		if not entry or Rules.satisfied(entry.id, selectedCount) then return M.hide() end
	end
	-- a hint never shares the screen with the boss intro, and never covers the boss rule plate
	if layer:FindFirstChild("BossIntro") then M.hide(); return end
	local avoid = {}
	local bp = layer:FindFirstChild("BossRulePlate")
	if bp and bp.Visible then avoid[1] = { x = bp.Position.X.Offset, y = bp.Position.Y.Offset, w = bp.Size.X.Offset, h = bp.Size.Y.Offset } end
	local PPFX = require(script.Parent.PatronPowerPanelFX)
	local panelRect = PPFX.liveRect()
	local spot
	if panelRect then
		avoid[#avoid + 1] = panelRect -- the hint never prints over the Patron Power panel
		spot = Rules.place(rects, viewW, viewH, avoid)
		if not spot then -- nothing clear of the panel: the hint shows first and the panel comes back after Got it
			avoid[#avoid] = nil
			spot = Rules.place(rects, viewW, viewH, avoid)
			if spot then PPFX.yieldTo(true); PPFX.hide() end
		end
	else
		spot = Rules.place(rects, viewW, viewH, avoid)
	end
	if not spot then M.hide(); return end -- nothing fits clear of the table: skip it rather than overlap
	if not plate or plate.Parent ~= layer then build(layer) end
	if current ~= entry.id then
		current = entry.id
		localSeen[entry.id] = true
		local remotes = ReplicatedStorage:FindFirstChild("Remotes")
		local seenRemote = remotes and remotes:FindFirstChild("HintSeen")
		if seenRemote then seenRemote:FireServer(entry.id) end -- once per profile
	end
	title.Text, body.Text = entry.title, entry.body
	local strip = spot.kind == "strip"
	local paint = layer:FindFirstChild(plate.Name .. "Paint")
	do -- every size is the same flat card with Got it inside it (no crown picture); the layout only moves and scales it
		if paint then paint:Destroy() end
		plate.BackgroundTransparency = 0.05
		for _, d in ipairs(plate:GetChildren()) do if d:IsA("UIStroke") then d.Enabled = true end end
	end
	if not strip then
		local P = Rules.STRIP_PAD + 4
		title.Position = UDim2.fromOffset(P, 8); title.Size = UDim2.fromOffset(spot.textW, 24); title.TextSize = 18
		body.Position = UDim2.fromOffset(P, 34); body.Size = UDim2.fromOffset(spot.textW, math.max(20, spot.plate.h - 34 - (spot.kind == "tall" and spot.button.h + 8 or 8))); body.TextSize = 15
		body.TextWrapped = true; title.TextWrapped = false; body.TextTruncate = Enum.TextTruncate.None
	else
		title.Position = UDim2.fromOffset(Rules.STRIP_PAD + 4, 6); title.Size = UDim2.fromOffset(spot.textW, 26); title.TextSize = Rules.STRIP_TITLE
		body.Position = UDim2.fromOffset(Rules.STRIP_PAD + 4, 33); body.Size = UDim2.fromOffset(spot.textW, 22); body.TextSize = Rules.STRIP_BODY
		body.TextWrapped = false; title.TextWrapped = false; body.TextTruncate = Enum.TextTruncate.None
		pcall(function() while body.TextSize > 14 and body.TextBounds.X > spot.textW do body.TextSize = body.TextSize - 1 end end) -- 20 px, shrunk only when the column is narrower than the line
	end
	plate.Visible = true
	plate.Size = UDim2.fromOffset(spot.plate.w, spot.plate.h)
	plate.Position = UDim2.fromOffset(spot.plate.x, spot.plate.y)
	button.Visible = true
	button.Size = UDim2.fromOffset(spot.button.w, spot.button.h)
	button.Position = UDim2.fromOffset(spot.button.x, spot.button.y)
	if game:GetService("RunService"):IsStudio() and M.lastKey ~= viewW .. "x" .. viewH .. spot.kind then
		M.lastKey = viewW .. "x" .. viewH .. spot.kind
		task.defer(function() print(("[HintLive] RoundHint abs=%d,%d size=%d,%d"):format(math.floor(plate.AbsolutePosition.X), math.floor(plate.AbsolutePosition.Y), math.floor(plate.AbsoluteSize.X), math.floor(plate.AbsoluteSize.Y))) end)
		print(("[HintRects] %s plate=%d,%d,%d,%d button=%d,%d,%d,%d"):format(spot.kind, spot.plate.x, spot.plate.y, spot.plate.w, spot.plate.h, spot.button.x, spot.button.y, spot.button.w, spot.button.h))
	end
end

-- Settings > Replay Hints
function M.replay()
	localSeen = {}
	M.hide()
end

return M
