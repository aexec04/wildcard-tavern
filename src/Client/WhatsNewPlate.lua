-- The What's new plate on the Menu: a parchment plate with the latest three additions and a 44 px Got it plate. It shows once per
-- update (the server sends state.whatsNew until DismissWhatsNew saves the version) and only while the Menu is open. No tweens, so
-- Calm mode needs nothing extra. Numbers come from Engine/WhatsNew.layout (tested at four sizes).
--
-- init(deps): { screenGui, menuFrame, remote, playClickSfx, roundCorner }
-- update(state): called from render in a pcall
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WhatsNewPlate = {}

local WhatsNew = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("WhatsNew"))
local Kit = require(script.Parent.TavernKit)

local INK = Color3.fromRGB(60, 40, 22)
local PARCHMENT = Color3.fromRGB(222, 198, 150)
local GOLD = Color3.fromRGB(222, 182, 104)

local ui
local dismissed = false -- this session, so a late state push cannot bring the plate back before the server saves
local lastState

local function place()
	if not ui then return end
	local size = ui.screenGui.AbsoluteSize
	local r = WhatsNew.layout(size.X, size.Y)
	local function put(inst, rect) inst.Position = UDim2.fromOffset(rect.x - r.plate.x, rect.y - r.plate.y); inst.Size = UDim2.fromOffset(rect.w, rect.h) end
	ui.plate.Position = UDim2.fromOffset(r.plate.x, r.plate.y)
	ui.plate.Size = UDim2.fromOffset(r.plate.w, r.plate.h)
	put(ui.title, r.title)
	for i, line in ipairs(ui.lines) do put(line, r.lines[i]) end
	put(ui.button, r.button)
end

local function refresh()
	if not ui then return end
	local show = (not dismissed) and type(lastState) == "table" and type(lastState.whatsNew) == "table" and ui.menuFrame.Visible == true
	ui.plate.Visible = show
	if show then
		local view = lastState.whatsNew
		ui.title.Text = tostring(view.title or WhatsNew.TITLE)
		for i, line in ipairs(ui.lines) do line.Text = tostring(view.lines and view.lines[i] or "") end
		place()
	end
end

function WhatsNewPlate.init(deps)
	if ui then return end
	local plate = Instance.new("Frame")
	plate.Name = "WhatsNewPlate"
	plate.BackgroundColor3 = PARCHMENT
	plate.BorderSizePixel = 0
	plate.Visible = false
	plate.Active = true
	plate.ZIndex = 40
	plate.Parent = deps.screenGui
	deps.roundCorner(plate, 12)
	local stroke = Instance.new("UIStroke")
	stroke.Color = GOLD
	stroke.Thickness = 2.5
	stroke.Parent = plate

	local function text(name, size, font)
		local l = Instance.new("TextLabel")
		l.Name = name
		l.BackgroundTransparency = 1
		l.Font = font
		l.TextSize = size
		l.TextColor3 = INK
		l.TextTransparency = 0
		l.TextStrokeTransparency = 1
		l.TextWrapped = true
		l.TextXAlignment = Enum.TextXAlignment.Left
		l.ZIndex = 41
		l.Parent = plate
		return l
	end
	local title = text("Title", 24, Enum.Font.Merriweather)
	title.TextXAlignment = Enum.TextXAlignment.Center
	local lines = {}
	for i = 1, #WhatsNew.Entries do lines[i] = text("Line" .. i, 16, Enum.Font.Merriweather) end

	local button = Instance.new("TextButton")
	button.Name = "GotIt"
	button.ZIndex = 41
	button.Parent = plate
	Kit.skin(button, WhatsNew.BUTTON, "primary")
	button.MouseButton1Click:Connect(function()
		deps.playClickSfx()
		dismissed = true
		plate.Visible = false
		if deps.remote then deps.remote:FireServer() end
	end)

	ui = { screenGui = deps.screenGui, menuFrame = deps.menuFrame, plate = plate, title = title, lines = lines, button = button }
	deps.menuFrame:GetPropertyChangedSignal("Visible"):Connect(refresh)
	deps.screenGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function() if plate.Visible then place() end end)
end

function WhatsNewPlate.update(state)
	lastState = state
	refresh()
end

return WhatsNewPlate
