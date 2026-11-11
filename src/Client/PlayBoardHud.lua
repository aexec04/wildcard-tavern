--[[
	Client/PlayBoardHud.lua
	Steps C2 to C4 of the painted play screen, in one: while play_board_a is painted, the left HUD rows sit on its slots.
	The Sidebar and BoardContent lists (and the sidebar padding) are switched off and every row is placed by hand from the tested
	Engine/PlayBoardLayout.hud / seats: the Night/Round ribbon in the title band, the score, bar and Reward in the big slot, Tips and
	the round rule in the wide slot, Hands and Discards in their two slots, the Patron seats on the five rings (portraits inset 8 percent).
	Old row fills, strokes, kit plates and pads are hidden so only dark brown ink shows on the painted slots. The Select cards hint,
	the run badge, the blessing chip and anything else the list used to stack go in a column on a small plate under the board.

	PlayBoardHud.apply(root, rect)   rect = { x, y, w, h } of the painted board; nil restores every touched property and the lists.
	Everything touched is remembered the first time and put back on nil, so a failed load or a narrow window keeps the old column.
	Seat sizes, row sizes, visibility and the theme's ink are re-applied (deferred, once) when something writes them again.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Engine = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine")
local PlayBoardLayout = require(Engine:WaitForChild("PlayBoardLayout"))
local LayoutSwitch = require(script.Parent.LayoutSwitch)

local PlayBoardHud = {}

local INK = Color3.fromRGB(52, 32, 16)
local THEME_PIECES = { HudKitPlate = true, HudKitPad = true, HudHeaderPlate = true, HudDepth = true, InnerHighlight = true, HudKitFrame = true }

local states = setmetatable({}, { __mode = "k" })

local function stateFor(root)
	local st = states[root]
	if not st then
		st = { saved = {}, hosts = {}, conns = {}, made = {}, applying = false, pending = false, rect = nil }
		states[root] = st
	end
	return st
end

-- set properties, remembering each original value the first time it is touched
local function put(st, inst, props)
	local sv = st.saved[inst]
	if not sv then
		sv = {}
		st.saved[inst] = sv
	end
	for k, v in pairs(props) do
		if sv[k] == nil then sv[k] = { inst[k] } end
		if inst[k] ~= v then inst[k] = v end
	end
end

-- a layout has no Enabled property: it is taken out of its host and put back by restore
local function layoutsOff(st, host)
	LayoutSwitch.off(host)
	st.hosts[host] = true
end

local function fit(st, label, lo, hi)
	local c = label:FindFirstChild("BoardFit")
	if not c then
		c = Instance.new("UITextSizeConstraint")
		c.Name = "BoardFit"
		c.Parent = label
		table.insert(st.made, c)
	end
	c.MinTextSize, c.MaxTextSize = lo, hi
	put(st, label, { TextScaled = true, TextWrapped = true, TextColor3 = INK, TextStrokeTransparency = 1, TextTransparency = 0 })
end

local function hideFill(st, frame)
	put(st, frame, { BackgroundTransparency = 1 })
	for _, c in ipairs(frame:GetChildren()) do
		if c:IsA("UIStroke") or c:IsA("UIGradient") then put(st, c, { Enabled = false }) end
	end
end

local function placeRect(st, inst, rc, relTo)
	local x, y = rc.x - (relTo and relTo.x or 0), rc.y - (relTo and relTo.y or 0)
	put(st, inst, { AnchorPoint = Vector2.new(0, 0), Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(rc.w, rc.h) })
end

local function hideIcons(st, parent)
	for _, c in ipairs(parent:GetChildren()) do
		if c:IsA("Frame") or c:IsA("ImageLabel") then put(st, c, { Visible = false }) end
	end
end

local function visibleLabel(parent, scaledOnly)
	for _, c in ipairs(parent:GetChildren()) do
		if c:IsA("TextLabel") and c.Visible and (not scaledOnly or c.TextScaled) then return c end
	end
end

local function run(root, st)
	local rect = st.rect
	local sidebar = root:FindFirstChild("Sidebar")
	if not (rect and sidebar) then return end
	local content = sidebar:FindFirstChild("BoardContent")
	if not content then return end
	local H = PlayBoardLayout.hud(rect.w, rect.h)

	-- the lists and the padding off: rows are placed in board coordinates (the sidebar and content frames start at the screen corner)
	for _, host in ipairs({ sidebar, content }) do
		for _, c in ipairs(host:GetChildren()) do
			if c:IsA("UIPadding") then
				put(st, c, { PaddingTop = UDim.new(0, 0), PaddingBottom = UDim.new(0, 0), PaddingLeft = UDim.new(0, 0), PaddingRight = UDim.new(0, 0) })
			end
		end
		layoutsOff(st, host)
	end
	put(st, content, { AutomaticSize = Enum.AutomaticSize.None, Position = UDim2.fromOffset(0, 0), Size = UDim2.fromOffset(rect.w, rect.h) })

	local known = { HeaderRibbon = true, ArchSpacer = true, BoardContent = true }
	local ribbon = sidebar:FindFirstChild("HeaderRibbon")
	local spacer = sidebar:FindFirstChild("ArchSpacer")
	if spacer then put(st, spacer, { Visible = false }) end
	if ribbon then
		placeRect(st, ribbon, H.title)
		hideFill(st, ribbon)
		for _, c in ipairs(ribbon:GetChildren()) do
			if c:IsA("TextLabel") then
				put(st, c, { Position = UDim2.fromScale(0, 0), Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center })
				fit(st, c, 14, 22)
			elseif c:IsA("Frame") then
				put(st, c, { Visible = false })
			end
		end
	end

	local stack = {} -- rows the list used to stack that have no slot: they go under the board
	local patrons, hd, tips, score, rule
	for _, c in ipairs(content:GetChildren()) do
		if c:IsA("GuiObject") then
			if c.Name == "Divider" then
				put(st, c, { Visible = false })
			elseif c.Name == "PatronsTray" then
				patrons = c
			elseif c.Name == "TipsRow" then
				tips = c
			elseif c.LayoutOrder == 1 then
				rule = c
			elseif c.LayoutOrder == 3 then
				score = c
			elseif c.LayoutOrder == 6 then
				hd = c
			else
				table.insert(stack, c)
			end
		end
	end
	for _, c in ipairs(sidebar:GetChildren()) do
		if c:IsA("GuiObject") and not known[c.Name] then table.insert(stack, c) end
	end

	if rule then
		placeRect(st, rule, H.rule)
		local lab = visibleLabel(rule)
		if lab then
			put(st, lab, { Position = UDim2.fromScale(0, 0), Size = UDim2.fromScale(1, 1) })
			fit(st, lab, 14, 17)
		end
	end
	if score then
		placeRect(st, score, H.target)
		hideFill(st, score)
		hideIcons(st, score)
		local big = visibleLabel(score, true)
		if big then
			put(st, big, { Position = UDim2.fromScale(0.04, 0.02), Size = UDim2.fromScale(0.92, 0.44), TextXAlignment = Enum.TextXAlignment.Center })
			fit(st, big, 14, 30)
		end
		local bar = score:FindFirstChild("TargetBar")
		if bar then put(st, bar, { Position = UDim2.fromScale(0.06, 0.5), Size = UDim2.fromScale(0.88, 0.12) }) end
		local plate = score:FindFirstChild("RewardPlate")
		if plate then
			put(st, plate, { Position = UDim2.fromScale(0.04, 0.66), Size = UDim2.fromScale(0.92, 0.3) })
			local line = visibleLabel(plate)
			if line then
				put(st, line, { Position = UDim2.fromScale(0, 0), Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center })
				fit(st, line, 14, 17)
			end
		end
	end
	if tips then
		placeRect(st, tips, H.tips)
		hideFill(st, tips)
		hideIcons(st, tips)
		local lab = visibleLabel(tips)
		if lab then
			put(st, lab, { Position = UDim2.fromScale(0, 0), Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center })
			fit(st, lab, 14, 19)
		end
	end
	if hd then
		placeRect(st, hd, H.handsDiscards)
		hideFill(st, hd)
		for _, col in ipairs(hd:GetChildren()) do
			if col:IsA("Frame") and (col.Name == "HandsTile" or col.Name == "DiscardsTile") then
				local slot = col.Name == "HandsTile" and H.hands or H.discards
				placeRect(st, col, slot, H.handsDiscards)
				hideFill(st, col)
				hideIcons(st, col)
				local lab = visibleLabel(col)
				if lab then
					put(st, lab, { Position = UDim2.fromScale(0, 0), Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center })
					fit(st, lab, 14, 18)
				end
			end
		end
	end
	if patrons then
		placeRect(st, patrons, H.ringRow)
		put(st, patrons, { AutomaticSize = Enum.AutomaticSize.None })
		hideFill(st, patrons)
		local inset = patrons:FindFirstChild("PatronsInset")
		for _, c in ipairs(patrons:GetChildren()) do
			if c:IsA("TextLabel") then put(st, c, { Visible = false }) end -- the "Patrons n/limit" caption (the board is the label)
		end
		if inset then
			put(st, inset, { AutomaticSize = Enum.AutomaticSize.None, AnchorPoint = Vector2.new(0, 0), Position = UDim2.fromOffset(0, 0), Size = UDim2.fromScale(1, 1) })
			hideFill(st, inset)
			for _, c in ipairs(inset:GetChildren()) do
				if c:IsA("UIPadding") then
					put(st, c, { PaddingTop = UDim.new(0, 0), PaddingBottom = UDim.new(0, 0), PaddingLeft = UDim.new(0, 0), PaddingRight = UDim.new(0, 0) })
				end
			end
			layoutsOff(st, inset)
			local seats = {}
			for _, c in ipairs(inset:GetChildren()) do
				if c:IsA("Frame") and c.Visible then table.insert(seats, c) end
			end
			table.sort(seats, function(a, b) return a.LayoutOrder < b.LayoutOrder end)
			local rects = PlayBoardLayout.seats(rect.w, rect.h, #seats)
			for i, seat in ipairs(seats) do
				placeRect(st, seat, rects[i], H.ringRow)
				for _, c in ipairs(seat:GetChildren()) do
					if c:IsA("UIStroke") then put(st, c, { Enabled = false }) end -- the painted ring is the ring
					if c.Name == "InnerRing" then put(st, c, { Visible = false }) end
				end
			end
		end
	end

	-- rows with no slot: a column of plates under the board, aligned with its left edge
	table.sort(stack, function(a, b) return a.LayoutOrder < b.LayoutOrder end)
	local y = rect.h + 6
	for _, c in ipairs(stack) do
		if c.Visible then
			local h = c.Size.Y.Scale == 0 and c.Size.Y.Offset or c.AbsoluteSize.Y
			if h > 0 then
				put(st, c, { AnchorPoint = Vector2.new(0, 0), Position = UDim2.fromOffset(4, y), Size = UDim2.fromOffset(math.max(120, rect.w - 8), h) })
				y = y + h + 4
			end
		end
	end

	-- pieces the theme adds on top of the rows (kit plates, pads, header plate, depth, frame)
	for _, top in ipairs({ sidebar, root:FindFirstChild("SidebarBoard") }) do
		if top then
			for _, d in ipairs(top:GetDescendants()) do
				if THEME_PIECES[d.Name] and d:IsA("GuiObject") then put(st, d, { Visible = false }) end
			end
		end
	end
end

local function schedule(root, st)
	if st.applying or st.pending or not st.rect then return end
	st.pending = true
	task.defer(function()
		st.pending = false
		if not st.rect then return end
		st.applying = true
		pcall(run, root, st)
		st.applying = false
	end)
end

local function unwatch(st)
	for _, cn in ipairs(st.conns) do cn:Disconnect() end
	st.conns = {}
end

local function restore(st)
	unwatch(st)
	for inst, sv in pairs(st.saved) do
		for k, w in pairs(sv) do
			pcall(function() inst[k] = w[1] end)
		end
	end
	st.saved = {}
	for host in pairs(st.hosts) do LayoutSwitch.on(host) end
	st.hosts = {}
	for _, c in ipairs(st.made) do pcall(function() c:Destroy() end) end
	st.made = {}
end

function PlayBoardHud.apply(root, rect)
	local st = stateFor(root)
	if not rect then
		if st.rect then
			st.rect = nil
			restore(st)
		end
		return false
	end
	local first = st.rect == nil
	st.rect = rect
	st.applying = true
	local ok = pcall(run, root, st)
	st.applying = false
	if not ok then
		st.rect = nil
		restore(st)
		return false
	end
	if first then
		local sidebar = root:FindFirstChild("Sidebar")
		if sidebar then
			-- rows added later (blessing chip, run badge), seats resized by fitSeats, the theme restyling: place again, once
			table.insert(st.conns, sidebar.DescendantAdded:Connect(function() schedule(root, st) end))
			for _, d in ipairs(sidebar:GetDescendants()) do
				if d.Name == "PatronsInset" or d.Name == "PatronsTray" or d.Name == "BoardContent" or d.Name == "HeaderRibbon" then
					for _, prop in ipairs({ "Size", "Position" }) do
						table.insert(st.conns, d:GetPropertyChangedSignal(prop):Connect(function() schedule(root, st) end))
					end
				elseif d:IsA("GuiObject") and d.Parent and d.Parent.Name == "PatronsInset" then
					for _, prop in ipairs({ "Size", "Visible", "Position" }) do
						table.insert(st.conns, d:GetPropertyChangedSignal(prop):Connect(function() schedule(root, st) end))
					end
				elseif d:IsA("TextLabel") then
					table.insert(st.conns, d:GetPropertyChangedSignal("TextColor3"):Connect(function() schedule(root, st) end))
				end
			end
			for _, c in ipairs(sidebar:GetChildren()) do
				if c:IsA("GuiObject") then
					table.insert(st.conns, c:GetPropertyChangedSignal("Visible"):Connect(function() schedule(root, st) end))
				end
			end
		end
	end
	return true
end

return PlayBoardHud
