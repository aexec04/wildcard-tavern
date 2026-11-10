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
local ContentArt = require(Engine:WaitForChild("ContentArt"))

local MenuBoard = {}

local NOTE_W = 350 -- notes are re-sized to this when pinned so they fit the cork board at full scale (text stays 14 px or more)
local TILTS = { -1.5, 1.2, -0.8, 1.6 } -- degrees, at most 2
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
	local boardArt = ContentArt.getImageId("menu_room", "menu_room_noticeboard") or ContentArt.getImageId("menu_scene", Layout.SceneArt.board)
	if boardArt then -- painted wall board behind the notes (the flat wood colour is the fallback)
		local img = Instance.new("ImageLabel")
		img.Name = "BoardArt"
		img.Size = UDim2.fromScale(1, 1)
		img.BackgroundTransparency = 1
		img.Image = boardArt
		img.ScaleType = Enum.ScaleType.Stretch
		img.Active = false
		img.ZIndex = 12
		img.Parent = frame
		local ic = Instance.new("UICorner")
		ic.CornerRadius = UDim.new(0, 10)
		ic.Parent = img
	end
	local head = Instance.new("TextLabel") -- name plate above the board, shown on hover (and always on the unpainted board)
	head.Name = "Head"
	head.AnchorPoint = Vector2.new(0.5, 1)
	head.Position = UDim2.new(0.5, 0, 0, -4)
	head.Size = UDim2.fromOffset(150, 28)
	head.BackgroundColor3 = Color3.fromRGB(34, 24, 16)
	head.BackgroundTransparency = 0
	head.Font = Enum.Font.GothamBold
	head.TextSize = 16
	head.TextColor3 = Color3.fromRGB(250, 235, 200)
	head.TextTransparency = 0
	head.TextStrokeTransparency = 1
	head.Text = "Notice Board"
	head.Active = false
	head.Visible = false
	head.ZIndex = 60
	head.Parent = frame
	do
		local hc = Instance.new("UICorner")
		hc.CornerRadius = UDim.new(0, 6)
		hc.Parent = head
		local hs = Instance.new("UIStroke")
		hs.Color = Color3.fromRGB(176, 140, 60)
		hs.Thickness = 1.5
		hs.Parent = head
	end

	local holder = Instance.new("Frame") -- clips the scaled notes to the board
	holder.Name = "Notes"
	holder.Position = UDim2.fromOffset(8, 8)
	holder.Size = UDim2.new(1, -16, 1, -16)
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
	layout.Padding = UDim.new(0, 16)
	layout.Parent = list
	local listPad = Instance.new("UIPadding") -- room above the first note for its pin
	listPad.PaddingTop = UDim.new(0, 10)
	listPad.Parent = list

	-- The board is only as tall as its notes (never taller than its layout rect), so no empty wood hangs under them.
	local function fit()
		local screenH = parent.AbsoluteSize.Y
		if screenH < 1 then return end
		local content = list.AbsoluteSize.Y -- includes the UIScale
		local h = math.min(N.h * screenH, 8 + content + 14)
		frame.Size = UDim2.new(N.w, 0, 0, math.max(60, math.floor(h)))
	end
	list:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	parent:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	task.defer(fit)

	local slots = {}
	local board = { frame = frame, list = list, head = head, slots = slots }

	function board.pin(note, onClick)
		local slot = Instance.new("Frame")
		slot.Name = "Slot_" .. note.Name
		note.Size = UDim2.fromOffset(NOTE_W, note.Size.Y.Offset) -- narrower than the old 460 so it fits the cork at full size
		slot.Size = note.Size
		slot.LayoutOrder = note.LayoutOrder
		slot.BackgroundTransparency = 1
		slot.Visible = note.Visible
		slots[#slots + 1] = slot
		note.Rotation = TILTS[((#slots - 1) % #TILTS) + 1]
		slot.ZIndex = 13
		slot.Parent = list
		note.Position = UDim2.new()
		note.Parent = slot
		lift(note, Z - note.ZIndex)
		note:GetPropertyChangedSignal("Visible"):Connect(function() slot.Visible = note.Visible and slot:GetAttribute("Crowded") ~= true end)
		local pin = Instance.new("Frame") -- the pin holding the note to the board
		pin.Name = "Pin"
		pin.AnchorPoint = Vector2.new(0.5, 0.5)
		pin.Position = UDim2.new(0.5, 0, 0, -4) -- on the note's top edge only, clear of its text rows
		pin.Size = UDim2.fromOffset(10, 10)
		pin.BackgroundColor3 = Color3.fromRGB(190, 150, 62) -- brass
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

	-- Tavern Room: sit on a pixel rectangle (the painted cork board). When the picture is painted the wood and stroke are dropped.
	function board.place(l, t, r, b, painted)
		frame.Position = UDim2.fromOffset(l, t)
		frame.Size = UDim2.fromOffset(r - l, b - t)
		local sc = math.clamp((r - l - 16) / NOTE_W, 0.4, 1)
		scale.Scale = sc
		-- show at most 4 notes; when the cork is small (notes would shrink under 90 percent or run past the board) show the first 2
		local avail, need, shown = b - t - 16, 10, 0
		local visibleSlots = {}
		for _, slot in ipairs(slots) do slot:SetAttribute("Crowded", false) end
		for _, slot in ipairs(slots) do
			local note = slot:FindFirstChildWhichIsA("GuiObject")
			if note and note.Visible then visibleSlots[#visibleSlots + 1] = slot end
		end
		local limit = (sc < 0.9) and 2 or 4
		for i, slot in ipairs(visibleSlots) do
			need += (slot.Size.Y.Offset + 16) * sc
			local crowd = i > limit or need > avail
			slot:SetAttribute("Crowded", crowd)
			slot.Visible = not crowd
			shown += crowd and 0 or 1
		end
		head.Visible = not painted
		if painted then
			frame.BackgroundTransparency = 1
			edge.Enabled = false
			local art = frame:FindFirstChild("BoardArt")
			if art then art.Visible = false end
		end
	end

	function board.setHover(on)
		head.Visible = on
	end

	function board.apply(w, h, phone)
		frame.Visible = not phone
		local pxW = N.w * w - 16
		scale.Scale = math.clamp(pxW / NOTE_W, 0.4, 1) -- board.place sets the final scale on the cork rectangle
	end

	return board
end

return MenuBoard
