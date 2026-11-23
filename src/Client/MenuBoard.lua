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
local TextService = game:GetService("TextService")
local Engine = game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine")
local Layout = require(Engine:WaitForChild("MenuLayout"))
local ContentArt = require(Engine:WaitForChild("ContentArt"))
local RoomLayout = require(Engine:WaitForChild("MenuRoomLayout"))
local NoteText = require(Engine:WaitForChild("MenuNoteText"))

local MenuBoard = {}

local PADN = 12 -- padding inside a pinned note (Engine/MenuNoteText.PAD)
local NOTE_W = 300 -- notes are re-sized to this when pinned (Engine/MenuRoomLayout.NOTE_W) so they fit the cork at full scale
local TILTS = { -1.5, 1.2, -0.8, 1.6 } -- degrees, at most 2
local Z = 14 -- notes are drawn at z 10 to 12 by their modules; lift them above the board and the backdrop

-- How tall a label's text is at `size` when wrapped to `width`, or nil when it cannot be measured.
-- The hub's font pass gives every label a FontFace (Merriweather). After that label.Font reads Enum.Font.Unknown, and
-- GetTextSize refuses it. That refusal used to be swallowed and counted as one line, so a note longer than one line
-- was cut on the menu ("Lantern Weekend: Double"). GetTextBoundsAsync measures with the face the label draws with.
local function textHeight(label, size, width)
	local ok, bounds = pcall(function()
		local params = Instance.new("GetTextBoundsParams")
		params.Text = label.Text
		params.Font = label.FontFace
		params.Size = size
		params.Width = width
		return TextService:GetTextBoundsAsync(params)
	end)
	if not (ok and bounds) then
		ok, bounds = pcall(function()
			return TextService:GetTextSize(label.Text, size, label.Font, Vector2.new(width, 1000))
		end)
	end
	return (ok and bounds) and bounds.Y or nil
end

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
		pcall(function() require(script.Parent.TavernKit).painted(head, "wood_plate") end) -- painted name plate, flat look if it does not load
		local hc = Instance.new("UICorner")
		hc.CornerRadius = UDim.new(0, 6)
		hc.Parent = head
		local hs = Instance.new("UIStroke")
		hs.Color = Color3.fromRGB(176, 140, 60)
		hs.Thickness = 1.5
		hs.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		hs.Parent = head
	end

	local holder = Instance.new("Frame") -- clips the scaled notes to the board
	holder.Name = "Notes"
	holder.Position = UDim2.fromOffset(10, 10)
	holder.Size = UDim2.new(1, -20, 1, -20)
	holder.BackgroundTransparency = 1
	holder.ClipsDescendants = true
	holder.ZIndex = 13
	holder.Parent = frame

	local list = Instance.new("Frame")
	list.Name = "NoteList"
	list.AnchorPoint = Vector2.new(0.5, 0)
	list.Position = UDim2.fromScale(0.5, 0)
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
	local placed = false
	local function fit()
		if placed then return end -- on the painted room the cork rectangle decides the size
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

	-- A note whose words change after the board was laid out (the Next goal after the tutorial, a new news line) is
	-- measured again, so the new line wraps onto a second line. It used to keep its old one-line box and was cut at
	-- the note's edge ("Next goal: win your first run (b").
	local lastPlace = nil
	local placeQueued = false
	local function placeAgain()
		if placeQueued or not lastPlace then return end
		placeQueued = true
		task.defer(function()
			placeQueued = false
			if lastPlace then board.place(lastPlace[1], lastPlace[2], lastPlace[3], lastPlace[4], lastPlace[5]) end
		end)
	end

	-- keep = true: this note is the one that stays when the board is too full (the Next goal).
	function board.pin(note, onClick, keep)
		if keep then note:SetAttribute("KeepOnBoard", true) end
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
		if pcall(function() return require(script.Parent.TavernKit).painted(note, "wh_target") end) and note.BackgroundTransparency >= 1 then note.Rotation = 0 end
		pcall(function() -- an equipped Card Set re-dresses every note plate at once (painted returns the same picture when the set is unchanged)
			require(script.Parent.HudTheme).onSkin(function() if note.Parent then require(script.Parent.TavernKit).painted(note, "wh_target") end end)
		end) -- the same gold framed plate as Target and Tips; a sibling picture cannot tilt, so painted notes stand straight
		for _, d in ipairs(note:GetDescendants()) do
			if d:IsA("TextLabel") or d:IsA("TextButton") then d.TextTruncate = Enum.TextTruncate.None end -- rows wrap onto a second line in place(), nothing ends in an ellipsis
			if d:IsA("TextLabel") and (d.Name == "Text" or d.Name == "Time") then
				d:GetPropertyChangedSignal("Text"):Connect(placeAgain)
			end
		end
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
			local goal = UDim2.fromOffset(0, on and -3 or 0)
			if require(script.Parent.ClientSettings).motionAllowed() then
				TweenService:Create(note, TweenInfo.new(0.12), { Position = goal }):Play()
			else
				note.Position = goal -- Calm and Reduce motion: no tween
			end
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
		lastPlace = { l, t, r, b, painted }
		placed = painted == true
		frame.Position = UDim2.fromOffset(l, t)
		frame.Size = UDim2.fromOffset(r - l, b - t)
		local visibleSlots, heights = {}, {}
		for _, slot in ipairs(slots) do
			slot:SetAttribute("Crowded", false)
			local note = slot:FindFirstChildWhichIsA("GuiObject")
			if note and note.Visible then
				visibleSlots[#visibleSlots + 1] = slot
				heights[#heights + 1] = slot.Size.Y.Offset
			end
		end
		local scale0 = RoomLayout.noteSlots(r - l, b - t, {}).scale -- the scale depends on the width only
		-- the notes are drawn at NOTE_W and shrunk by the scale; raise each line's size so it still reads at least MIN_TEXT (18) px on screen.
		-- A line that does not fit wraps onto more lines (the note grows by the extra height), so no text is ever cut with an ellipsis.
		heights = {}
		for _, slot in ipairs(visibleSlots) do
			local note = slot:FindFirstChildWhichIsA("GuiObject")
			local baseH = note:GetAttribute("BaseH") or note.Size.Y.Offset
			note:SetAttribute("BaseH", baseH)
			local extra, rewardGrow = 0, 0
			for _, d in ipairs(note:GetDescendants()) do
				if (d:IsA("TextLabel") or d:IsA("TextButton")) and d.Text ~= "" and d.Name ~= "NoteHit" then
					local base = d:GetAttribute("BaseTextSize") or d.TextSize
					d:SetAttribute("BaseTextSize", base)
					local want = math.max(base, math.ceil(RoomLayout.MIN_TEXT / scale0))
					d.TextSize = want
					d.TextTruncate = Enum.TextTruncate.None
					if d.Name == "Text" or d.Name == "Time" then
						local baseLabelH = d:GetAttribute("BaseLabelH") or d.Size.Y.Offset
						d:SetAttribute("BaseLabelH", baseLabelH)
						local w = d.Size.X.Offset
						if d.Size.X.Scale ~= 0 then w = d.Size.X.Scale * NOTE_W + w end
						local lines = 1
						local wrapW = NoteText.wrapWidth(d.Position.X.Offset, w) -- 12 px clear of the note edge (TextFit.SIDE)
						if d.Size.X.Scale == 0 and wrapW < w then d.Size = UDim2.new(0, wrapW, d.Size.Y.Scale, d.Size.Y.Offset) end
						local tall = textHeight(d, want, math.max(20, wrapW))
						if tall then lines = math.max(1, math.min(3, math.round(tall / (want + 2)))) end
						lines = math.max(lines, math.min(3, NoteText.lineCount(d.Text, want, math.max(20, wrapW)))) -- the TextFit estimate never lets a line run to the edge
						d.TextWrapped = lines > 1
						local lineH = want + 2
						if d.Size.Y.Scale == 0 and lines > 1 then
							d.Size = UDim2.new(d.Size.X.Scale, d.Size.X.Offset, 0, math.max(baseLabelH, lines * lineH))
							extra = math.max(extra, lines * lineH - baseLabelH)
						elseif d.Size.Y.Scale == 0 then
							d.Size = UDim2.new(d.Size.X.Scale, d.Size.X.Offset, 0, math.max(baseLabelH, lineH))
							extra = math.max(extra, lineH - baseLabelH)
						end
					else
						d.TextWrapped = false
						if d.Size.Y.Scale == 0 and d.Size.X.Scale == 0 and d.Size.X.Offset > 0 then -- a one line word shrinks (12 px at the least) rather than touch the plate edge
							d.TextSize = NoteText.oneLineSize(d.Text, NoteText.wrapWidth(d.Position.X.Offset, d.Size.X.Offset), want)
						end
						if d.Size.Y.Scale == 0 and d.Size.Y.Offset > 0 and d.Size.Y.Offset < want + 4 then
							if d.Name == "Reward" then rewardGrow = (want + 4) - d.Size.Y.Offset end -- the last line grows the plate so it never hangs below the frame
							d.Size = UDim2.new(d.Size.X.Scale, d.Size.X.Offset, 0, want + 4)
						end
					end
				end
			end
			local tx, tm = note:FindFirstChild("Text"), note:FindFirstChild("Time")
			if tx and tm and tx:IsA("TextLabel") and tm:IsA("TextLabel") and tm.Text ~= "" then
				-- a left label and a right label never share a line: stack them, both left aligned, each wrapped to the full width
				local x0 = tx.Position.X.Offset
				local w = NoteText.wrapWidth(x0, NOTE_W - x0 - 10)
				local function lines(l)
					local tall = textHeight(l, l.TextSize, w)
					return tall and math.max(1, math.min(3, math.round(tall / (l.TextSize + 2)))) or 1
				end
				local h1, h2 = lines(tx) * (tx.TextSize + 2), lines(tm) * (tm.TextSize + 2)
				tx.Position = UDim2.fromOffset(x0, PADN)
				tx.Size = UDim2.fromOffset(w, h1)
				tx.TextWrapped, tx.TextYAlignment = true, Enum.TextYAlignment.Top
				tm.Position = UDim2.fromOffset(x0, PADN + h1)
				tm.Size = UDim2.fromOffset(w, h2)
				tm.TextWrapped, tm.TextXAlignment, tm.TextYAlignment = true, Enum.TextXAlignment.Left, Enum.TextYAlignment.Top
				extra = math.max(extra, PADN + h1 + h2 + PADN - baseH)
			end
			local rank = note.Name == "RankBar" and note:FindFirstChild("Text") and note:FindFirstChild("Track") and note:FindFirstChild("Reward")
			if rank then -- the Rank plate lays its rows out from the text size, so no line can sit on the frame edge
				local R = require(Engine:WaitForChild("RankPlateLayout")).rows(rank.TextSize)
				rank.Position = UDim2.fromOffset(rank.Position.X.Offset, R.textY)
				rank.Size = UDim2.new(rank.Size.X.Scale, rank.Size.X.Offset, 0, R.textH)
				rank.TextWrapped = false
				local track, rw = note.Track, note.Reward
				track.Position = UDim2.new(track.Position.X.Scale, track.Position.X.Offset, 0, R.barY)
				rw.Position = UDim2.new(rw.Position.X.Scale, rw.Position.X.Offset, 0, R.rewardY)
				rw.Size = UDim2.new(rw.Size.X.Scale, rw.Size.X.Offset, 0, R.rewardH)
				rw.TextSize = rank.TextSize
				extra, rewardGrow = R.h - baseH, 0
			end
			extra = math.max(0, extra) + rewardGrow
			for _, c in ipairs(rank and {} or note:GetChildren()) do -- the progress track under the text moves down with the extra lines
				if (c.Name == "Track" or c.Name == "Reward") and c:IsA("GuiObject") then
					local baseY = c:GetAttribute("BaseY") or c.Position.Y.Offset
					c:SetAttribute("BaseY", baseY)
					c.Position = UDim2.new(c.Position.X.Scale, c.Position.X.Offset, 0, baseY + extra)
				end
			end
			if rank then extra = require(Engine:WaitForChild("RankPlateLayout")).rows(rank.TextSize).h - baseH end
			local noteH = math.max(baseH + extra, RoomLayout.minNoteH(note.Name))
			note.Size = UDim2.fromOffset(NOTE_W, noteH)
			slot.Size = note.Size
			heights[#heights + 1] = noteH
		end
		local keep = nil
		for i, slot in ipairs(visibleSlots) do
			local note = slot:FindFirstChildWhichIsA("GuiObject")
			if note and note:GetAttribute("KeepOnBoard") == true then keep = i end
		end
		local rankAt = nil -- the Rank note outranks the news when the cork is crowded
		for i, slot in ipairs(visibleSlots) do
			if slot.Name == "Slot_RankBar" then rankAt = i end
		end
		local fitted = RoomLayout.noteSlots(r - l, b - t, heights, keep, rankAt)
		scale.Scale = fitted.scale
		layout.Padding = UDim.new(0, fitted.gap) -- (the rule moves the notes closer before it drops one)
		listPad.PaddingTop = UDim.new(0, fitted.top)
		for i, slot in ipairs(visibleSlots) do
			local crowd = not fitted.show[i]
			slot:SetAttribute("Crowded", crowd)
			slot.Visible = not crowd
		end
		if game:GetService("RunService"):IsStudio() then -- one line per note: where the plate stands and how far its words reach (text bounds are unscaled px inside the note)
			task.defer(function()
				for _, slot in ipairs(visibleSlots) do
					local note = slot:FindFirstChildWhichIsA("GuiObject")
					if note and slot.Visible then
						local parts = {}
						for _, d in ipairs(note:GetDescendants()) do
							if d:IsA("TextLabel") and d.Text ~= "" then parts[#parts + 1] = ("%s x%d..%d y%d..%d"):format(d.Name, d.Position.X.Offset, d.Position.X.Offset + d.TextBounds.X, d.Position.Y.Offset, d.Position.Y.Offset + d.TextBounds.Y) end
						end
						print(("[MenuNotes] %s abs=%d,%d,%d,%d | %s"):format(note.Name, note.AbsolutePosition.X, note.AbsolutePosition.Y, note.AbsoluteSize.X, note.AbsoluteSize.Y, table.concat(parts, "; ")))
					end
				end
			end)
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
		frame:SetAttribute("Phone", phone and true or false)
		frame.Visible = not phone and frame:GetAttribute("PanelOpen") ~= true
		local pxW = N.w * w - 16
		if not placed then scale.Scale = math.clamp(pxW / NOTE_W, 0.4, 1) end -- board.place sets the final scale on the cork rectangle
	end

	return board
end

return MenuBoard
