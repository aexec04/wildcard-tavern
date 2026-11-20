--[[
	Client/PatronPowerPanelFX.lua
	The Patron Power panel at the left of the table (Engine/PatronPowerPanel): the painted hint plate (crown medallion on the left), the
	gold heading and one line about the frame colours, and a Got it plate under it (on short screens the whole panel is the dismiss
	button). Shown on Night 1 rounds 1 and 2 and on every boss round, gone when the first hand of the round is played or Got it is pressed.
	No tweens, so Calm mode and Reduce motion look the same. Display only.

	update(layer, state, rects, viewW, viewH)   from Gameplay2.update; hides itself when nothing is due or nothing fits
	hide()
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Engine = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine")
local Rules = require(Engine:WaitForChild("PatronPowerPanel"))
local RoundHints = require(Engine:WaitForChild("RoundHints"))
local ClientSettings = require(script.Parent.ClientSettings)

local M = {}
local plate, title, body, button, tap
local roundKey, handsAtStart -- the round the panel was last due in, and the hands played when it began
local dismissed = {} -- round keys whose panel was closed with Got it

local function build(layer)
	plate = Instance.new("Frame")
	plate.Name = "PatronPowerPanel"
	plate.BackgroundColor3 = Color3.fromRGB(46, 28, 14)
	plate.BackgroundTransparency = 0.05
	plate.BorderSizePixel = 0
	plate.Active = false
	plate.ZIndex = 28
	plate.Parent = layer
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 10); c.Parent = plate
	local st = Instance.new("UIStroke"); st.Color = Color3.fromRGB(246, 196, 70); st.Thickness = 2; st.Parent = plate
	pcall(function() require(script.Parent.TavernKit).painted(plate, "wh_hint") end) -- crown medallion on the left, flat plate if it does not load
	local function label(name, size, color, font)
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
		t.ZIndex = 29
		t.Parent = plate
		return t
	end
	local TC = RoundHints.TITLE_COLOR
	title = label("Title", Rules.TITLE_SIZE, Color3.fromRGB(TC[1], TC[2], TC[3]), Enum.Font.Merriweather)
	body = label("Body", Rules.BODY_SIZE, Color3.fromRGB(235, 218, 180), Enum.Font.Gotham)
	title.Text, body.Text = Rules.TITLE, Rules.BODY
	title.Position = UDim2.new(0.31, 0, 0, 8); title.Size = UDim2.new(0.64, 0, 0, 28)
	body.Position = UDim2.new(0.31, 0, 0, 38); body.Size = UDim2.new(0.64, 0, 1, -42)
	-- the plate is its own dismiss button on short screens (no Got it plate fits there)
	tap = Instance.new("TextButton")
	tap.Name = "PatronPowerTap"
	tap.BackgroundTransparency = 1
	tap.Text = ""
	tap.Size = UDim2.fromScale(1, 1)
	tap.ZIndex = 31
	tap.Parent = plate
	button = Instance.new("TextButton")
	button.Name = "PatronPowerGotIt"
	button.ZIndex = 30
	pcall(function() require(script.Parent.TavernKit).skin(button, "Got it", "primary") end)
	do -- the same dark wood plate with a gold edge as the round hints' Got it
		local G = RoundHints.GOT_IT
		for _, d in ipairs(button:GetChildren()) do
			if d:IsA("UIGradient") or d:IsA("UIStroke") then d:Destroy() end
		end
		local edge = Instance.new("UIStroke")
		edge.Name = "GotItEdge"
		edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		edge.Color = Color3.fromRGB(G.edge[1], G.edge[2], G.edge[3])
		edge.Thickness = 2
		edge.Parent = button
		local base = Color3.fromRGB(G.fill[1], G.fill[2], G.fill[3])
		local hot = Color3.fromRGB(G.hover[1], G.hover[2], G.hover[3])
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
	local function close()
		if roundKey then dismissed[roundKey] = true end
		M.hide()
	end
	button.MouseButton1Click:Connect(close)
	tap.MouseButton1Click:Connect(close)
end

function M.hide()
	if plate then plate.Visible = false end
	if button then button.Visible = false end
end

function M.update(layer, state, rects, viewW, viewH)
	local opts = { enabled = ClientSettings.get("roundHints") ~= false }
	if not Rules.enabledFor(state, opts) then M.hide(); return end
	local key = ("%s:%s"):format(tostring(state.night), tostring(state.round))
	if key ~= roundKey then roundKey = key; handsAtStart = tonumber(state.handsPlayedTotal) or 0 end
	if dismissed[key] or Rules.spent(state, handsAtStart) then M.hide(); return end
	if layer:FindFirstChild("BossIntro") then M.hide(); return end -- never shares the screen with the boss intro
	local avoid = {}
	local bp = layer:FindFirstChild("BossRulePlate")
	if bp and bp.Visible then avoid[1] = { x = bp.Position.X.Offset, y = bp.Position.Y.Offset, w = bp.Size.X.Offset, h = bp.Size.Y.Offset } end
	pcall(function() -- the consumables tray is only drawn when something is held: an empty tray frees its column
		local held = require(Engine:WaitForChild("Gameplay2Tray")).held(state)
		for _, s in ipairs(held.slots) do if not s.empty then return end end
		local free = {}
		for k, v in pairs(rects) do free[k] = v end
		for _, key in ipairs({ "traySlot1", "traySlot2", "trayUse", "traySell", "trayPrompt" }) do free[key] = nil end
		rects = free
	end)
	local spot = Rules.place(rects, viewW, viewH, avoid)
	if not spot then M.hide(); return end -- nothing fits clear of the table: skip it rather than overlap
	if not plate or plate.Parent ~= layer then build(layer) end
	plate.Visible = true
	plate.Size = UDim2.fromOffset(spot.plate.w, spot.plate.h)
	plate.Position = UDim2.fromOffset(spot.plate.x, spot.plate.y)
	tap.Visible = spot.kind == "compact"
	if spot.button then
		button.Visible = true
		button.Size = UDim2.fromOffset(spot.button.w, spot.button.h)
		button.Position = UDim2.fromOffset(spot.button.x, spot.button.y)
	else
		button.Visible = false
	end
	if game:GetService("RunService"):IsStudio() and M.lastKey ~= viewW .. "x" .. viewH .. spot.kind then
		M.lastKey = viewW .. "x" .. viewH .. spot.kind
		print(("[PowerPanel] %s plate=%d,%d,%d,%d"):format(spot.kind, spot.plate.x, spot.plate.y, spot.plate.w, spot.plate.h))
	end
end

return M
