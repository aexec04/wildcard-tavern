--[[
	Client/MenuBoard.lua
	The Notice Board: a wooden board nailed to the tavern wall (left side) with the Menu's pinned parchment notes: Tavern Rank,
	Next goal, Tonight's news and Today's board. It replaces the old full width strips. It is part of the scene: Menu.lua gives it
	to MenuParallax as a wall layer. Position and size are fractions in Engine/MenuLayout.NoticeBoard.

	build(parent) returns { frame, list, pin(note, onClick), apply(w, h, phone) }
	  list      the frame the note modules attach() into (they set LayoutOrder; pin() then moves each note onto a slot);
	  pin       puts a note on a slot with a pin, hover lifts it, onClick (optional) makes the whole note a button;
	  apply     scales the notes to the board (they are drawn 460 wide) and hides the board on phones.
]]

local TweenService = game:GetService("TweenService")
local Engine = game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine")
local Layout = require(Engine:WaitForChild("MenuLayout"))

local MenuBoard = {}

local NOTE_W = 460
local Z = 14 -- notes are drawn at z 10 to 12 by their modules; lift them above the board and the backdrop

local function lift(root, n)
	root.ZIndex += n
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("GuiObject") then d.ZIndex += n end
	end
end

function MenuBoard.build(parent)
	local N = Layout.NoticeBoard
	local frame = Instance.new("Frame")
	frame.Name = "NoticeBoard"
	frame.Position = UDim2.fromScale(N.x, N.y)
	frame.Size = UDim2.fromScale(N.w, N.h)
	frame.BackgroundColor3 = Color3.fromRGB(112, 78, 46)
	frame.BorderSizePixel = 0
	frame.ZIndex = 12
	frame.Parent = parent
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 10)
	c.Parent = frame
	local edge = Instance.new("UIStroke")
	edge.Color = Color3.fromRGB(62, 40, 24)
	edge.Thickness = 4
	edge.Parent = frame
	local head = Instance.new("TextLabel")
	head.Name = "Head"
	head.Size = UDim2.new(1, 0, 0, 26)
	head.BackgroundTransparency = 1
	head.Font = Enum.Font.GothamBold
	head.TextSize = 16
	head.TextColor3 = Color3.fromRGB(250, 235, 200)
	head.TextTransparency = 0
	head.TextStrokeTransparency = 1
	head.Text = "Notice Board"
	head.Active = false
	head.ZIndex = 13
	head.Parent = frame

	local holder = Instance.new("Frame") -- clips the scaled notes to the board
	holder.Name = "Notes"
	holder.Position = UDim2.fromOffset(8, 28)
	holder.Size = UDim2.new(1, -16, 1, -36)
	holder.BackgroundTransparency = 1
	holder.ClipsDescendants = true
	holder.ZIndex = 13
	holder.Parent = frame

	local list = Instance.new("Frame")
	list.Name = "NoteList"
	list.Size = UDim2.fromOffset(NOTE_W, 0)
	list.AutomaticSize = Enum.AutomaticSize.Y
	list.BackgroundTransparency = 1
	list.ZIndex = 13
	list.Parent = holder
	local scale = Instance.new("UIScale")
	scale.Parent = list
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 12)
	layout.Parent = list

	local board = { frame = frame, list = list }

	function board.pin(note, onClick)
		local slot = Instance.new("Frame")
		slot.Name = "Slot_" .. note.Name
		slot.Size = note.Size
		slot.LayoutOrder = note.LayoutOrder
		slot.BackgroundTransparency = 1
		slot.Visible = note.Visible
		slot.ZIndex = 13
		slot.Parent = list
		note.Position = UDim2.new()
		note.Parent = slot
		lift(note, Z - note.ZIndex)
		note:GetPropertyChangedSignal("Visible"):Connect(function() slot.Visible = note.Visible end)
		local pin = Instance.new("Frame") -- the pin holding the note to the board
		pin.Name = "Pin"
		pin.AnchorPoint = Vector2.new(0.5, 0.5)
		pin.Position = UDim2.new(0.5, 0, 0, 0)
		pin.Size = UDim2.fromOffset(12, 12)
		pin.BackgroundColor3 = Color3.fromRGB(176, 52, 40)
		pin.BorderSizePixel = 0
		pin.Active = false
		pin.ZIndex = Z + 30
		pin.Parent = slot
		local pc = Instance.new("UICorner")
		pc.CornerRadius = UDim.new(1, 0)
		pc.Parent = pin
		local function hover(on)
			TweenService:Create(note, TweenInfo.new(0.12), { Position = UDim2.fromOffset(0, on and -3 or 0) }):Play()
		end
		local target = note
		if onClick then
			local hit = Instance.new("TextButton")
			hit.Name = "NoteHit"
			hit.Text = ""
			hit.BackgroundTransparency = 1
			hit.AutoButtonColor = false
			hit.Size = UDim2.fromScale(1, 1)
			hit.ZIndex = Z + 29
			hit.Parent = note
			hit.MouseButton1Click:Connect(onClick)
			target = hit
		end
		target.MouseEnter:Connect(function() hover(true) end)
		target.MouseLeave:Connect(function() hover(false) end)
		return slot
	end

	function board.apply(w, h, phone)
		frame.Visible = not phone
		local pxW = N.w * w - 16
		scale.Scale = math.clamp(pxW / NOTE_W, 0.4, 1)
	end

	return board
end

return MenuBoard
