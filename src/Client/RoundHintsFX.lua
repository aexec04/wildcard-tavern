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
		t.Size = UDim2.new(1, -16, 0, h)
		t.Position = UDim2.new(0, 8, 0, y)
		t.ZIndex = 29
		t.Parent = plate
		return t
	end
	title = label("Title", 4, 18, 16, Color3.fromRGB(255, 244, 214), Enum.Font.GothamBold)
	body = label("Body", 22, 32, 15, Color3.fromRGB(235, 218, 180), Enum.Font.Gotham)
	button = Instance.new("TextButton")
	button.Name = "RoundHintGotIt"
	button.ZIndex = 30
	pcall(function() require(script.Parent.TavernKit).skin(button, "Got it", "secondary") end)
	button.Parent = layer
	button.MouseButton1Click:Connect(function()
		if current then localSeen[current] = true end
		M.hide()
	end)
end

function M.hide()
	current = nil
	if plate then plate.Visible = false end
	if button then button.Visible = false end
end

function M.update(layer, state, selectedCount, rects, viewW, viewH)
	local calm = ClientSettings.get("reduceShake") == true
	local opts = { enabled = ClientSettings.get("roundHints") ~= false, calm = calm }
	if not Rules.enabledFor(state, opts) then M.hide(); return end
	if current and Rules.satisfied(current, selectedCount) then
		localSeen[current] = true
		M.hide()
	end
	local entry = current and Rules.getById(current)
	if not entry then
		local seen = {}
		for id in pairs(type(state.hintsSeen) == "table" and state.hintsSeen or {}) do seen[id] = true end
		for id in pairs(localSeen) do seen[id] = true end
		entry = Rules.next(state, seen, opts)
		if not entry or Rules.satisfied(entry.id, selectedCount) then return M.hide() end
	end
	local spot = Rules.place(rects, viewW, viewH)
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
	plate.Visible = true
	plate.Size = UDim2.fromOffset(spot.plate.w, spot.plate.h)
	plate.Position = UDim2.fromOffset(spot.plate.x, spot.plate.y)
	button.Visible = true
	button.Size = UDim2.fromOffset(spot.button.w, spot.button.h)
	button.Position = UDim2.fromOffset(spot.button.x, spot.button.y)
end

-- Settings > Replay Hints
function M.replay()
	localSeen = {}
	M.hide()
end

return M
