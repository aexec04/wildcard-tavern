--[[
	Client/BlessingChip.lua
	A persistent chip at the foot of the gameplay sidebar showing the blessing and curse picked at the start of the
	run: painted icon (emoji until the art is recorded), name, a green blessing line and a red curse line. Hover
	opens a tooltip with both lines in full. Display only. The server sends state.runModifier (from the saved run
	state, so it survives a reload and updates live); layout maths are in Engine/BlessingChipLayout.lua.
	Module: init(deps) once, update(state) from render().
		deps = { root = Frame, addTooltip = function(guiObject, text, side) }
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Engine = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine")
local Layout = require(Engine:WaitForChild("BlessingChipLayout"))
local ArtIcon = require(script.Parent.ArtIcon)
local Rows = require(Engine:WaitForChild("BoardPanelRows"))

local BlessingChip = {}

local INK = Color3.fromRGB(60, 40, 22)
local GREEN = Color3.fromRGB(30, 100, 40) -- 4.5:1 on the chip parchment
local RED = Color3.fromRGB(150, 36, 30)
local PARCHMENT = Color3.fromRGB(236, 216, 172)
local GOLD = Color3.fromRGB(150, 108, 40)

local ui
local shownId
local CROWD_RESERVE = 110 -- Endless Crowd Rule chips (Client/EndlessChips.lua) sit at the column foot

local function label(parent, name, size, color, y, h, font)
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Position = UDim2.fromOffset(46, y)
	l.Size = UDim2.new(1, -52, 0, h)
	l.Font = font or Enum.Font.GothamBold
	l.TextSize = size
	l.TextColor3 = color
	l.TextTransparency = 0
	l.TextStrokeTransparency = 1
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextTruncate = Enum.TextTruncate.AtEnd
	l.Text = ""
	l.ZIndex = 9 -- above the painted icon
	l.Parent = parent
	return l
end

-- Lines a 15 px effect text needs at widthPx: measured with TextService, the pure estimate when that is not available.
function BlessingChip.lines(text, widthPx)
	local ok, size = pcall(function()
		return game:GetService("TextService"):GetTextSize(tostring(text), 15, Enum.Font.GothamMedium, Vector2.new(math.max(40, widthPx), 1000))
	end)
	if ok and size and size.Y > 0 then
		return math.max(1, math.min(Rows.MAX_LINES, math.floor(size.Y / 15 + 0.5)))
	end
	return Rows.estimateLines(text, widthPx)
end

-- The text width of the full row: the panel row's width minus the icon (46) and the right padding (6).
function BlessingChip.textWidth(rowWidth) return math.max(40, (rowWidth or 0) - 52) end

-- The width the two effect texts really wrap at: the row's text column, cut where the board clips its right edge
-- (rowX = the row's left edge on the board). The board's plan (Client/PlayBoardHud) and the chip's own layout both ask
-- this. The plan used to count lines at the full row width, so two texts that wrap on the board were given a one-line
-- row and the curse's last line ran over the board's lower rail.
function BlessingChip.wrapWidth(rowW, rowX)
	-- (only while the board frame really clips: under the painted board it no longer does, Client/PlayBoardHud)
	if ui and ui.board and ui.board.ClipsDescendants then
		local room = ui.board.AbsoluteSize.X - (rowX or 0) - Rows.CLIP_PAD
		if room > 60 then rowW = math.min(rowW, room) end
	end
	return BlessingChip.textWidth(rowW)
end

-- Lines an effect label's own text needs at widthPx, measured on the label itself, so in the face it is really drawn
-- with (the hub's font pass gives every label Merriweather; BlessingChip.lines measures Gotham). textSize: the size it
-- will be drawn at (15 on the board). The label's Size and TextSize are put back as they were.
function BlessingChip.linesOf(l, widthPx, textSize)
	local ok, tall, size = pcall(function()
		local wasSize, wasText, wasWrap = l.Size, l.TextSize, l.TextWrapped
		l.TextSize = textSize or wasText
		l.TextWrapped = true
		l.Size = UDim2.fromOffset(math.max(40, widthPx), 400)
		local y, ts = l.TextBounds.Y, l.TextSize
		l.Size, l.TextSize, l.TextWrapped = wasSize, wasText, wasWrap
		return y, ts
	end)
	if ok and type(tall) == "number" and tall > 0 and type(size) == "number" and size > 0 then
		return math.max(1, math.min(Rows.MAX_LINES, math.floor(tall / size + 0.5)))
	end
	return BlessingChip.lines(l.Text, widthPx)
end

function BlessingChip.init(deps)
	local chip = Instance.new("Frame")
	chip.Name = "BlessingChip"
	chip.AnchorPoint = Vector2.new(0.5, 0)
	chip.BackgroundColor3 = PARCHMENT
	chip.BorderSizePixel = 0
	chip.Visible = false
	chip.ZIndex = 7
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = chip
	local stroke = Instance.new("UIStroke")
	stroke.Color = GOLD
	stroke.Thickness = 2
	stroke.Parent = chip

	-- Round Select shows the chip over bare wood: its own dark plate (made first, so it sits under the icon and texts)
	local plate = Instance.new("Frame")
	plate.Name = "RoundSelectPlate"
	plate.Size = UDim2.fromScale(1, 1)
	plate.BackgroundColor3 = Color3.fromRGB(30, 22, 16)
	plate.BackgroundTransparency = 0.04
	plate.BorderSizePixel = 0
	plate.Active = false
	plate.Visible = false
	plate.ZIndex = 7
	plate.Parent = chip
	do
		local pc = Instance.new("UICorner"); pc.CornerRadius = UDim.new(0, 8); pc.Parent = plate
		local ps = Instance.new("UIStroke"); ps.Color = Color3.fromRGB(150, 118, 66); ps.Thickness = 1.5; ps.Parent = plate
	end

	local icon = Instance.new("TextLabel")
	icon.Name = "Icon"
	icon.BackgroundTransparency = 1
	icon.Position = UDim2.fromOffset(6, 6)
	icon.Size = UDim2.fromOffset(34, 34)
	icon.Font = Enum.Font.GothamBold
	icon.TextSize = 24
	icon.TextColor3 = INK
	icon.TextTransparency = 0
	icon.TextStrokeTransparency = 1
	icon.ZIndex = 8
	icon.Parent = chip

	local name = label(chip, "Name", 16, INK, 3, 20)
	local blessing = label(chip, "Blessing", 14, GREEN, 26, 20, Enum.Font.GothamMedium)
	local curse = label(chip, "Curse", 14, RED, 48, 20, Enum.Font.GothamMedium)

	ui = {
		chip = chip, plate = plate, icon = icon, name = name, blessing = blessing, curse = curse,
		root = deps.root, addTooltip = deps.addTooltip,
	}
end

local function parentChip()
	if ui.chip.Parent then
		return true
	end
	local board = ui.root:FindFirstChild("SidebarBoard", true)
	if board then
		ui.chip.Parent = board
		ui.chip.Size = UDim2.new(1, -24, 0, Layout.FULL_HEIGHT)
		ui.board = board
		board:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			BlessingChip.relayout()
		end)
	end
	return ui.chip.Parent ~= nil
end

function BlessingChip.relayout()
	if not ui or not ui.board or not ui.shown then
		return
	end
	if ui.chip:GetAttribute("BoardPanel") then
		-- the tall left board owns the row (Client/PlayBoardHud places it, Engine/BoardPanelRows picks full or compact)
		local full = ui.chip:GetAttribute("PanelMode") == "full"
		ui.blessing.Visible = full
		ui.curse.Visible = full
		ui.name.Position = UDim2.fromOffset(46, full and 3 or 12)
		ui.blessing.TextSize, ui.curse.TextSize = 15, 15
		-- each effect text wraps inside the real row width (measured, up to 3 lines) and the next starts right under it: no cut text, no gap
		-- the board clips what lies past its right edge: the text box ends 12 px inside it, whatever width the plan gave the row
		local rowW = ui.chip.Size.X.Offset > 0 and ui.chip.Size.X.Offset or ui.chip.AbsoluteSize.X
		local w = BlessingChip.wrapWidth(rowW, ui.chip.Position.X.Offset)
		local bl, cl = BlessingChip.linesOf(ui.blessing, w, 15), BlessingChip.linesOf(ui.curse, w, 15)
		for _, l in ipairs({ ui.blessing, ui.curse }) do
			l.TextWrapped = true
			l.TextTruncate = Enum.TextTruncate.None
			l.TextYAlignment = Enum.TextYAlignment.Top
		end
		ui.blessing.Position = UDim2.fromOffset(46, 25)
		ui.blessing.Size = UDim2.fromOffset(w, bl * Rows.LINE_H)
		ui.curse.Position = UDim2.fromOffset(46, 25 + bl * Rows.LINE_H + 4)
		ui.curse.Size = UDim2.fromOffset(w, cl * Rows.LINE_H)
		return
	end
	local height = ui.board.AbsoluteSize.Y
	local reserve = ui.crowd and CROWD_RESERVE or 0
	local plan = Layout.plan(height, reserve)
	if plan.mode == "hidden" then
		ui.chip.Visible = false
		return
	end
	ui.chip.Visible = true
	ui.chip.Size = UDim2.new(1, -24, 0, plan.height)
	ui.chip.Position = UDim2.new(0.5, 0, 0, Layout.top(height, plan))
	local full = plan.mode == "full"
	ui.blessing.Visible = full
	ui.curse.Visible = full
	ui.name.Position = UDim2.fromOffset(46, full and 3 or 12)
end

function BlessingChip.update(state)
	if not ui or type(state) ~= "table" then
		return
	end
	local view = state.runModifier
	-- never on Round Select: it hid the first blind's Tag bar and Target (the Settings row "This run: ..." still names the run)
	if type(view) ~= "table" or state.phase == "roundSelect" or not parentChip() then
		ui.shown = false
		ui.chip.Visible = false
		ui.chip:SetAttribute("Shown", false)
		return
	end
	ui.shown = true
	ui.chip:SetAttribute("Shown", true)
	do -- Round Select: cream text on the dark plate (all above 4.5:1), the normal ink colours everywhere else
		local onWood = state.phase == "roundSelect"
		ui.plate.Visible = onWood
		ui.name.TextColor3 = onWood and Color3.fromRGB(250, 235, 200) or INK
		ui.blessing.TextColor3 = onWood and Color3.fromRGB(150, 225, 160) or GREEN
		ui.curse.TextColor3 = onWood and Color3.fromRGB(255, 160, 150) or RED
	end
	ui.crowd = type(state.crowdRules) == "table" and #state.crowdRules > 0
	if shownId ~= view.id then
		shownId = view.id
		ui.icon.Text = view.icon or "!"
		ui.name.Text = view.name
		-- (the shared rule: one sign per line; "+1 Hand every round" was drawn as "+ +1 Hand every round")
		ui.blessing.Text = require(Engine:WaitForChild("RunModifiers")).line("+", view.blessing)
		ui.curse.Text = require(Engine:WaitForChild("RunModifiers")).line("-", view.curse)
		pcall(ArtIcon.apply, ui.chip, "blessing_icons", view.id, ui.icon, { cornerRadius = 6, size = UDim2.fromOffset(34, 34), position = UDim2.fromOffset(6, 6), anchor = Vector2.new(0, 0), zIndex = 8 })
		ui.tip = "This run: " .. view.name .. "\nBlessing: " .. view.blessing .. "\nCurse: " .. view.curse
		if not ui.tipped then
			ui.tipped = true
			ui.chip.Active = true
			ui.addTooltip(ui.chip, function() return ui.tip end, "right")
		end
	end
	BlessingChip.relayout()
end

return BlessingChip
