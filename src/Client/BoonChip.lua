--[[
	Client/BoonChip.lua
	The active Night boon as a small chip beside the top bar of the table (rect from Engine/BoonChipLayout, clear of the Patron seats and the gear).
	It wears the equipped Card Set's plate and accent (Client/SetInk, classic keeps dark wood and brass). Tap or hover opens a one line tooltip
	under the chip; tapping again closes it. No tween anywhere, so Calm mode and Reduce motion need nothing extra.
	BoonChip.update(layer, state, w, h)   call on every state push; hides itself when no boon is active or there is no clear spot.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Engine = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine")
local ChipLayout = require(Engine:WaitForChild("BoonChipLayout"))
local NightBoons = require(Engine:WaitForChild("NightBoons"))

local BoonChip = {}

local CREAM = Color3.fromRGB(246, 232, 198)
local WOOD = Color3.fromRGB(58, 40, 26)
local BRASS = Color3.fromRGB(200, 160, 84)

local function textLabel(parent, name, props)
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBold
	l.TextSize = ChipLayout.TEXT_SIZE
	l.TextColor3 = CREAM
	l.TextTransparency = 0
	l.TextStrokeTransparency = 1
	l.Active = false
	for k, v in pairs(props) do l[k] = v end
	l.Parent = parent
	return l
end

local function build(layer)
	local chip = Instance.new("TextButton")
	chip.Name = "BoonChip"
	chip.AutoButtonColor = false
	chip.Text = ""
	chip.BackgroundColor3 = WOOD
	chip.BorderSizePixel = 0
	chip.ZIndex = 30
	chip.Visible = false
	chip.Parent = layer
	local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0, 10); corner.Parent = chip
	local stroke = Instance.new("UIStroke"); stroke.Name = "Edge"; stroke.Color = BRASS; stroke.Thickness = 2; stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; stroke.Parent = chip
	local iconLabel = textLabel(chip, "Icon", { Position = UDim2.fromOffset(0, 0), Size = UDim2.fromOffset(ChipLayout.MIN_SIZE, ChipLayout.MIN_SIZE), TextSize = 24, ZIndex = 31 })
	local nameLabel = textLabel(chip, "Name", { Position = UDim2.fromOffset(ChipLayout.MIN_SIZE, 0), Size = UDim2.new(1, -ChipLayout.MIN_SIZE - 8, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 31 })
	local tip = Instance.new("TextLabel")
	tip.Name = "BoonChipTip"
	tip.BackgroundColor3 = WOOD
	tip.BorderSizePixel = 0
	tip.Font = Enum.Font.GothamMedium
	tip.TextSize = ChipLayout.TEXT_SIZE
	tip.TextColor3 = CREAM
	tip.TextTransparency = 0
	tip.TextStrokeTransparency = 1
	tip.TextWrapped = true
	tip.Active = false
	tip.Visible = false
	tip.ZIndex = 32
	tip.Parent = layer
	local tc = Instance.new("UICorner"); tc.CornerRadius = UDim.new(0, 8); tc.Parent = tip
	local ts = Instance.new("UIStroke"); ts.Name = "Edge"; ts.Color = BRASS; ts.Thickness = 1.5; ts.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; ts.Parent = tip
	local open = false
	local function setOpen(v)
		open = v
		tip.Visible = v and chip.Visible
	end
	chip.MouseButton1Click:Connect(function() setOpen(not open) end)
	chip.MouseEnter:Connect(function() setOpen(true) end)
	chip.MouseLeave:Connect(function() setOpen(false) end)
	return { chip = chip, tip = tip, icon = iconLabel, name = nameLabel, edge = stroke, tipEdge = ts, setOpen = setOpen }
end

local parts

function BoonChip.update(layer, state, w, h)
	if not layer then return end
	if not (parts and parts.chip.Parent == layer) then parts = build(layer) end
	local view = NightBoons.view(state)
	local rect = view and ChipLayout.rect(w, h)
	if not (view and rect) then
		parts.chip.Visible = false
		parts.setOpen(false)
		return
	end
	local chip, tip = parts.chip, parts.tip
	chip.Position = UDim2.fromOffset(rect.x, rect.y)
	chip.Size = UDim2.fromOffset(rect.w, rect.h)
	chip.Visible = true
	parts.icon.Text = view.icon
	parts.name.Text = view.name
	parts.name.Visible = rect.showName
	local ok, ink = pcall(function() return require(script.Parent.SetInk).get() end)
	chip.BackgroundColor3 = ok and ink and ink.plate or WOOD
	parts.edge.Color = ok and ink and ink.accent or BRASS
	tip.BackgroundColor3 = chip.BackgroundColor3
	parts.tipEdge.Color = parts.edge.Color
	tip.Text = ChipLayout.tooltip(view)
	local tw = math.min(280, w - 16)
	tip.Size = UDim2.fromOffset(tw, 44)
	tip.Position = UDim2.fromOffset(math.max(8, math.min(rect.x + rect.w - tw, w - tw - 8)), rect.y + rect.h + 6)
end

return BoonChip
