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
	l.ZIndex = 8
	l.Parent = parent
	return l
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
		chip = chip, icon = icon, name = name, blessing = blessing, curse = curse,
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
	if type(view) ~= "table" or not parentChip() then
		ui.shown = false
		ui.chip.Visible = false
		return
	end
	ui.shown = true
	ui.crowd = type(state.crowdRules) == "table" and #state.crowdRules > 0
	if shownId ~= view.id then
		shownId = view.id
		ui.icon.Text = view.icon or "!"
		ui.name.Text = view.name
		ui.blessing.Text = "+ " .. view.blessing
		ui.curse.Text = "- " .. view.curse
		pcall(ArtIcon.apply, ui.chip, "blessing_icons", view.id, ui.icon, { cornerRadius = 6 })
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
