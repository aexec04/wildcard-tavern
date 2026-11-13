--[[
	Client/PlayBoardHud.lua
	Steps C2 to C4 of the painted play screen, in one: while play_board_a is painted, the left HUD rows sit on its slots.
	The Sidebar and BoardContent lists (and the sidebar padding) are switched off and every row is placed by hand from the tested
	Engine/PlayBoardLayout.hud / seats: the Night/Round ribbon in the title band, the score, bar and Reward in the big slot, Tips and
	the round rule in the wide slot, Hands and Discards in their two slots, the Patron seats on the five rings (portraits inset 8 percent).
	Old row fills, strokes, kit plates and pads are hidden so only dark brown ink shows on the painted slots. The Tips row, the Select cards hint, the
	Blessing chip and the Run line (Daily / Weekly / Seed) sit in ONE panel hung under the board (Engine/BoardPanelRows); anything else
	the list used to stack goes in a column below it.

	PlayBoardHud.apply(root, rect)   rect = { x, y, w, h } of the painted board; nil restores every touched property and the lists.
	Everything touched is remembered the first time and put back on nil, so a failed load or a narrow window keeps the old column.
	Seat sizes, row sizes, visibility and the theme's ink are re-applied (deferred, once) when something writes them again.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Engine = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine")
local PlayBoardLayout = require(Engine:WaitForChild("PlayBoardLayout"))
local BoardPanelRows = require(Engine:WaitForChild("BoardPanelRows"))
local LayoutSwitch = require(script.Parent.LayoutSwitch)

local PlayBoardHud = {}
PlayBoardHud.RUN_COOLDOWN = 0.05 -- seconds between two scheduled placements (breaks the watcher re-entrancy chain)

local INK = Color3.fromRGB(52, 32, 16)
-- decoration the theme and the skin draw on the Sidebar and SidebarBoard frames themselves: gone while the board is painted
local FRAME_DECOR = { SetSkinBorder = true, SetAccent = true, CornerStud = true, InnerRim = true, BracketH = true, BracketV = true, HudBrackets = true, Brackets = true }
local INSET = 8 -- text keeps 8 px off a slot's edge
local RULE_INSET = 12 -- the round rule box keeps 12 px each side
local TILE_INSET = 10 -- Hands and Discards keep 10 px
local PLATE = Color3.fromRGB(226, 202, 156)
local THEME_PIECES = { HudKitPlate = true, HudKitPad = true, HudHeaderPlate = true, HudDepth = true, InnerHighlight = true, HudKitFrame = true }
-- the Card Set kit pieces (HudKitPlate, HudKitPad, HudKitFrame ...) are all theme paint over a row; HudKitIcon is a picture a row keeps
local function isThemePiece(name)
	return THEME_PIECES[name] == true or (type(name) == "string" and name:sub(1, 6) == "HudKit" and name ~= "HudKitIcon")
end

local states = setmetatable({}, { __mode = "k" })

local function stateFor(root)
	local st = states[root]
	if not st then
		st = { saved = {}, hosts = {}, conns = {}, made = {}, applying = false, pending = false, rect = nil, watched = setmetatable({}, { __mode = "k" }) }
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

-- text width in px: Roblox's TextService when it answers, else a plain estimate (the fake Roblox has no real fonts)
local function measure(text, size, font)
	text = text or ""
	local ok, v = pcall(function()
		local ts = game:GetService("TextService")
		return ts:GetTextSize(text, size, font or Enum.Font.GothamBold, Vector2.new(10000, 10000)).X
	end)
	if ok and type(v) == "number" then return v end
	return #text * size * 0.6
end

-- the largest size in lo..hi at which the text is one line inside width; second result false when even lo is too wide
local function sizeFor(text, lo, hi, width, font)
	for sz = hi, lo, -1 do
		if measure(text, sz, font) <= width then return sz, true end
	end
	return lo, false
end

-- one line, no scaling, no truncation: shrinks until it fits the slot width
local function fitOne(st, label, width, lo, hi)
	local size = sizeFor(label.Text, lo, hi, width, label.Font)
	put(st, label, { TextScaled = false, TextWrapped = false, RichText = false, TextTruncate = Enum.TextTruncate.None, TextSize = size,
		TextColor3 = INK, TextStrokeTransparency = 1, TextTransparency = 0 })
end

local function makeLabel(st, parent, name)
	local l = parent:FindFirstChild(name)
	if not l then
		l = Instance.new("TextLabel")
		l.Name = name
		l.BackgroundTransparency = 1
		l.BorderSizePixel = 0
		l.Active = false
		l.Font = Enum.Font.GothamBold
		l.Text = ""
		l.Parent = parent
		table.insert(st.made, l)
	end
	return l
end

local function stripTags(str) return (str:gsub("<[^>]+>", "")) end

-- a row that sits on the board panel: see-through, no strokes or gradients of its own, text at 15 px or more
local function flatRow(st, row)
	put(st, row, { BackgroundTransparency = 1 })
	for _, c in ipairs(row:GetDescendants()) do
		if c:IsA("TextLabel") and (c.TextSize or 15) < 15 and not c.TextScaled then put(st, c, { TextSize = 15 }) end
	end
	for _, c in ipairs(row:GetChildren()) do
		if c:IsA("UIStroke") or c:IsA("UIGradient") then put(st, c, { Enabled = false }) end
	end
	for _, c in ipairs(row:GetDescendants()) do -- the rows lie on parchment: dark ink (the theme may have tinted them for a dark plate)
		if c:IsA("TextLabel") then put(st, c, { TextColor3 = INK, TextStrokeTransparency = 1, TextTransparency = 0 }) end
	end
end

-- the Run row ("Seed: ABC"): dark ink on the board's parchment with a thin brass underline, no box of its own
local function inkLineStyle(st, row)
	put(st, row, { BackgroundTransparency = 1 })
	for _, c in ipairs(row:GetChildren()) do
		if c:IsA("UIStroke") or c:IsA("UIGradient") then put(st, c, { Enabled = false }) end
		if c:IsA("TextLabel") then
			put(st, c, { TextColor3 = INK, TextStrokeTransparency = 1, TextTransparency = 0 })
			if (c.TextSize or 15) < 15 then put(st, c, { TextSize = 15 }) end
		end
	end
	local fill = row:FindFirstChild("BoardWoodFill")
	if fill then fill.Visible = false end
	if not row:FindFirstChild("BoardRunUnderline") then
		local u = Instance.new("Frame")
		u.Name = "BoardRunUnderline"
		u.BorderSizePixel = 0
		u.Active = false
		u.BackgroundColor3 = Color3.fromRGB(176, 138, 70)
		u.AnchorPoint = Vector2.new(0, 1)
		u.Position = UDim2.new(0, 6, 1, -1)
		u.Size = UDim2.new(1, -12, 0, 2)
		u.ZIndex = row.ZIndex + 1
		u.Parent = row
		table.insert(st.made, u)
	end
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

local function hideIcons(st, parent, keep)
	for _, c in ipairs(parent:GetChildren()) do
		if (c:IsA("Frame") or c:IsA("ImageLabel")) and not (keep and keep[c.Name]) then put(st, c, { Visible = false }) end
	end
end

local function visibleLabel(parent, scaledOnly)
	for _, c in ipairs(parent:GetChildren()) do
		if c:IsA("TextLabel") and c.Visible and (not scaledOnly or c.TextScaled) then return c end
	end
end

local schedule -- defined below, run() asks for a second pass when the theme re-shows one of its pieces

local function run(root, st)
	local rect = st.rect
	local sidebar = root:FindFirstChild("Sidebar")
	if not (rect and sidebar) then return end
	local content = sidebar:FindFirstChild("BoardContent")
	if not content then return end
	local H = PlayBoardLayout.hud(rect.w, rect.h)
	local boardFrame = root:FindFirstChild("SidebarBoard")
	if boardFrame then boardFrame:SetAttribute("PlayBoardPainted", true) end -- the theme and the set wash read this and draw nothing over the table

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

	-- BoardPanelBack is our own panel: without it here a second pass took it for a row to stack under the board (a cream box off the screen)
	local known = { HeaderRibbon = true, ArchSpacer = true, BoardContent = true, BoardPanelBack = true }
	local ribbon = sidebar:FindFirstChild("HeaderRibbon")
	local spacer = sidebar:FindFirstChild("ArchSpacer")
	if spacer then put(st, spacer, { Visible = false }) end
	if ribbon then
		placeRect(st, ribbon, H.title)
		hideFill(st, ribbon)
		for _, c in ipairs(ribbon:GetChildren()) do
			if c:IsA("TextLabel") then
				put(st, c, { Position = UDim2.fromOffset(INSET, 0), Size = UDim2.new(1, -2 * INSET, 1, 0), TextXAlignment = Enum.TextXAlignment.Center })
				fitOne(st, c, H.title.w - 2 * INSET, 14, 17)
			elseif c:IsA("Frame") then
				put(st, c, { Visible = false })
			end
		end
	end

	local stack = {} -- rows the list used to stack that have no slot: they go under the board
	local patrons, hd, score, rule, runRow
	local seatRects, seatFrames -- the Patron seats of this pass (the extra ones move once the board's growth is known)
	for _, c in ipairs(content:GetChildren()) do
		if c:IsA("GuiObject") then
			if c.Name == "Divider" then
				put(st, c, { Visible = false })
			elseif c.Name == "PatronsTray" then
				patrons = c
			elseif c.Name == "TipsRow" then
				table.insert(stack, c) -- no slot of its own: a plate under the board with its own parchment
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
		if c:IsA("GuiObject") and not known[c.Name] and not FRAME_DECOR[c.Name] and not isThemePiece(c.Name) then
			if c.LayoutOrder == -1 then
				runRow = c -- the Daily / Weekly / Seed line: the Run row of the board panel (collapses when the Sidebar hides it)
			else
				table.insert(stack, c)
			end
		end
	end
	-- anything flat and wide left on the board frame (accent wash, kit pieces, the old strip) goes: the room shows left of the board
	local boardTop = root:FindFirstChild("SidebarBoard")
	if boardTop then
		for _, d in ipairs(boardTop:GetChildren()) do
			if d:IsA("GuiObject") and d.Name ~= "PlayerMedallion" and d.Name ~= "BlessingChip" and (d:IsA("Frame") or d:IsA("ImageLabel")) then
				local sz = d.Size
				local wide = sz ~= nil and (sz.X.Scale >= 0.8 or sz.X.Offset >= 200)
				local filled = d:IsA("ImageLabel") or (d.BackgroundTransparency or 1) < 0.99
				if wide and filled then put(st, d, { Visible = false }) end
			end
		end
	end

	if rule then
		placeRect(st, rule, H.rule)
		local src
		for _, c in ipairs(rule:GetChildren()) do
			if c:IsA("TextLabel") and c.Name ~= "BoardRuleName" and c.Name ~= "BoardRuleLine" then src = c break end
		end
		if src then
			-- the stock label is rich text of two sizes that wraps past the slot: it stays as the data source, hidden, and
			-- two plain one-line labels are drawn instead; a rule line that does not fit at 13 px is dropped (kept as RuleTooltip)
			put(st, src, { Visible = false })
			local plain = stripTags(src.Text)
			local first, second = plain:match("^([^\n]*)\n?(.*)$")
			first, second = first or plain, second or ""
			local w = H.rule.w - 2 * RULE_INSET
			local nameL = makeLabel(st, rule, "BoardRuleName")
			local lineL = makeLabel(st, rule, "BoardRuleLine")
			lineL.Font = Enum.Font.Gotham -- the rule line is narrower in the regular weight, so more of the rules fit
			nameL.ZIndex, lineL.ZIndex = src.ZIndex, src.ZIndex
			nameL.Text, lineL.Text = first, second
			local isBoss = src:GetAttribute("Boss") == true or first:find("👑", 1, true) ~= nil
			local band = rule:FindFirstChild("BossBand")
			if not band then
				band = Instance.new("Frame")
				band.Name = "BossBand"
				band.BackgroundColor3 = Color3.fromRGB(86, 38, 34) -- muted dark red
				band.BackgroundTransparency = 0.1
				band.BorderSizePixel = 0
				band.Active = false
				band.Position = UDim2.fromOffset(5, 4)
				band.Size = UDim2.new(1, -10, 1, -8)
				band.ZIndex = math.max(1, src.ZIndex - 1)
				band.Parent = rule
				table.insert(st.made, band)
				local k = Instance.new("UICorner")
				k.CornerRadius = UDim.new(0, 6)
				k.Parent = band
				local e = Instance.new("UIStroke") -- thin brass line, like the other slots' inner rims
				e.Color = Color3.fromRGB(150, 116, 62)
				e.Thickness = 1
				e.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
				e.Parent = band
			end
			band.Visible = isBoss
			-- the slot is the board's dark wood: no flat fill from the Sidebar over it, and four brass studs like the other plates
			hideFill(st, rule)
			for i, at in ipairs({ { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 } }) do
				local stud = rule:FindFirstChild("BossStud" .. i)
				if not stud then
					stud = Instance.new("Frame")
					stud.Name = "BossStud" .. i
					stud.AnchorPoint = Vector2.new(at[1], at[2])
					stud.Position = UDim2.new(at[1], at[1] == 0 and 3 or -3, at[2], at[2] == 0 and 3 or -3)
					stud.Size = UDim2.fromOffset(6, 6)
					stud.BackgroundColor3 = Color3.fromRGB(205, 164, 84)
					stud.BorderSizePixel = 0
					stud.Active = false
					stud.ZIndex = math.max(1, src.ZIndex)
					stud.Parent = rule
					table.insert(st.made, stud)
					local sk = Instance.new("UICorner")
					sk.CornerRadius = UDim.new(0.5, 0)
					sk.Parent = stud
				end
				stud.Visible = isBoss
			end
			local showLine = second ~= "" and select(2, sizeFor(second, 12, 14, w, Enum.Font.Gotham))
			if isBoss then
				-- boss round: dark red plate, cream text, crown on the name; the rule wraps to two lines at 12 px
				nameL.Text = "\u{1F451} " .. (first:gsub("^\u{1F451}%s*", ""))
				-- the slot keeps its own dark wood like the other board slots; only a muted dark red band sits inside it
				put(st, nameL, { TextColor3 = Color3.fromRGB(246, 232, 200) })
				put(st, lineL, { TextColor3 = Color3.fromRGB(230, 205, 170) })
				showLine = second ~= ""
			end
			-- the two lines are one block centred in the slot: name hugs the middle from above, rule line from below
			put(st, nameL, { Position = UDim2.fromOffset(RULE_INSET, 0), Size = showLine and UDim2.new(1, -2 * RULE_INSET, 0.45, 0) or UDim2.new(1, -2 * RULE_INSET, 1, 0),
				TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = showLine and Enum.TextYAlignment.Bottom or Enum.TextYAlignment.Center, Visible = true })
			fitOne(st, nameL, w, 12, isBoss and 15 or 14)
			if isBoss then
				put(st, nameL, { TextColor3 = Color3.fromRGB(246, 232, 200), Font = Enum.Font.GothamBold }) -- fitOne sets dark ink: cream on the red plate
			else
				-- a plate left red by an earlier boss round goes back to its saved colour
				local sv = st.saved[rule]
				if sv and sv.BackgroundColor3 then rule.BackgroundColor3 = sv.BackgroundColor3[1] end
				if sv and sv.BackgroundTransparency then rule.BackgroundTransparency = sv.BackgroundTransparency[1] end
			end
			put(st, lineL, { Position = UDim2.new(0, RULE_INSET, 0.45, 0), Size = UDim2.new(1, -2 * RULE_INSET, 0.55, 0),
				TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Top, Visible = showLine and true or false })
			if isBoss then
				-- text 15 px or more and never cut: the name on a 22 px line, the rule wraps below it in the rest of the slot
				fitOne(st, nameL, w, 15, 16)
				put(st, nameL, { TextColor3 = Color3.fromRGB(246, 232, 200), Font = Enum.Font.GothamBold,
					Position = UDim2.fromOffset(RULE_INSET, 6), Size = UDim2.new(1, -2 * RULE_INSET, 0, 22), TextYAlignment = Enum.TextYAlignment.Center })
			end
			if showLine and isBoss then
				put(st, lineL, { TextScaled = false, TextSize = 15, TextWrapped = true, RichText = false, TextTruncate = Enum.TextTruncate.None,
					TextColor3 = Color3.fromRGB(246, 232, 200), Font = Enum.Font.Gotham,
					Position = UDim2.fromOffset(RULE_INSET, 28), Size = UDim2.new(1, -2 * RULE_INSET, 0, math.max(20, H.rule.h - 32)),
					TextYAlignment = Enum.TextYAlignment.Top, TextStrokeTransparency = 1, TextTransparency = 0 })
			elseif showLine then
				fitOne(st, lineL, w, 12, 14)
			end
			local logKey = second .. tostring(isBoss)
			if isBoss and rule:GetAttribute("BossPlateLogged") ~= logKey then
				rule:SetAttribute("BossPlateLogged", logKey)
				print("[BossPlate] rule=" .. second .. " red=true")
			end
			rule:SetAttribute("RuleTooltip", (plain:gsub("\n", " - ")))
		end
	end
	if score then
		placeRect(st, score, H.target)
		hideFill(st, score)
		hideIcons(st, score, { TargetBar = true, RewardPlate = true }) -- the bar and the Reward line stay: they are stacked in this slot
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
	if hd then
		placeRect(st, hd, H.handsDiscards)
		hideFill(st, hd)
		local tiles, shared = {}, 18
		for _, col in ipairs(hd:GetChildren()) do
			if col:IsA("Frame") and (col.Name == "HandsTile" or col.Name == "DiscardsTile") then
				local slot = col.Name == "HandsTile" and H.hands or H.discards
				placeRect(st, col, slot, H.handsDiscards)
				hideFill(st, col)
				hideIcons(st, col)
				local lab = visibleLabel(col)
				if lab then
					put(st, lab, { Position = UDim2.fromOffset(TILE_INSET, 0), Size = UDim2.new(1, -2 * TILE_INSET, 1, 0), TextXAlignment = Enum.TextXAlignment.Center })
					local width = slot.w - 2 * TILE_INSET
					shared = math.min(shared, (sizeFor(lab.Text, 14, 18, width, lab.Font)))
					table.insert(tiles, { lab = lab, width = width })
				end
			end
		end
		for _, t in ipairs(tiles) do fitOne(st, t.lab, t.width, 14, shared) end -- Hands and Discards share one size (the smaller that fits both)
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
			if not st.seatReported and #seats > 1 and game:GetService("RunService"):IsStudio() then
				st.seatReported = true
				task.delay(1.5, function() -- Studio side check: the real drawn size and pitch of the seats (and any UIScale left on them)
					local out = {}
					for i, seat in ipairs(seats) do
						local us = seat:FindFirstChildOfClass("UIScale")
						out[i] = string.format("%d@%d(s%.2f)", math.floor(seat.AbsoluteSize.X), math.floor(seat.AbsolutePosition.X), us and us.Scale or 1)
					end
					warn("[SeatFit] seats size@x: " .. table.concat(out, " "))
				end)
			end
			seatRects, seatFrames = rects, seats
			for i, seat in ipairs(seats) do
				placeRect(st, seat, rects[i], H.ringRow)
				-- the painted hole is the seat: no parchment disc under a portrait or an empty seat (the hub recolours the fill on every
				-- render, so only its transparency is pinned); the empty seat shows a dim ink "+" and nothing else
				-- an owned seat is a filled gold pip (the hub sets the Owned attribute and the gold fill each render)
				put(st, seat, { BackgroundTransparency = seat:GetAttribute("Owned") == true and 0 or 1 })
				local ringSpec = rects[i].ring
				if rects[i].extra and ringSpec then
					-- a sixth seat and beyond have no painted ring: a matching brass ring in code, behind the portrait
					local ring = seat:FindFirstChild("ExtraRing")
					if not ring then
						ring = Instance.new("Frame")
						ring.Name = "ExtraRing"
						ring.AnchorPoint = Vector2.new(0.5, 0.5)
						ring.Position = UDim2.fromScale(0.5, 0.5)
						ring.BackgroundColor3 = Color3.fromRGB(74, 50, 28) -- the dark hole
						ring.BorderSizePixel = 0
						ring.Active = false
						ring.ZIndex = math.max(1, seat.ZIndex - 1)
						ring.Parent = seat
						table.insert(st.made, ring)
						local rk = Instance.new("UICorner")
						rk.CornerRadius = UDim.new(0.5, 0)
						rk.Parent = ring
						local rs = Instance.new("UIStroke")
						rs.Color = Color3.fromRGB(205, 164, 84) -- brass
						rs.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
						rs.Parent = ring
					end
					ring.Size = UDim2.fromOffset(ringSpec.d, ringSpec.d)
					local stroke = ring:FindFirstChildOfClass("UIStroke")
					if stroke then stroke.Thickness = math.max(2, math.floor(ringSpec.d * 0.08 + 0.5)) end
				end
				local us = seat:FindFirstChildOfClass("UIScale")
				if us and us.Scale > 1.02 then us.Scale = 1 end -- a pop left stuck above 1 would make neighbouring seats overlap
				for _, c in ipairs(seat:GetChildren()) do
					if c:IsA("UIStroke") then put(st, c, { Enabled = false }) end -- the painted ring is the ring
					if c.Name == "InnerRing" or c.Name == "EmptyPulse" then put(st, c, { Visible = false }) end -- the painted ring is the ring
				end
			end
		end
	end

	-- ONE panel under the board holds Tips, the Select cards hint, the Blessing and the Run line (Engine/BoardPanelRows); rows with no
	-- place there (anything else the list used to stack) keep a plain plate below the panel
	local tipsRow, hintRow, others = nil, nil, {}
	table.sort(stack, function(a, b) return (a.LayoutOrder or 0) < (b.LayoutOrder or 0) end)
	for _, c in ipairs(stack) do
		if c:IsA("Frame") and c.Name == "TipsRow" then tipsRow = c
		elseif c:IsA("Frame") and c.LayoutOrder == 10 then hintRow = c
		else others[#others + 1] = c end
	end
	local chip = boardTop and boardTop:FindFirstChild("BlessingChip")
	local function shown(r) return r ~= nil and r.Visible and (r.Size.Y.Scale == 0 and r.Size.Y.Offset or r.AbsoluteSize.Y) > 0 end
	local chipShown = chip ~= nil and chip:GetAttribute("Shown") == true
	local fullH -- the full Blessing row is as tall as its two effect texts need at the real row width (they wrap, never cut)
	if chipShown then
		pcall(function()
			local BC = require(script.Parent.BlessingChip)
			local tw = BC.textWidth(math.min(H.target.w + 12, rect.w - (H.target.x - 6) - BoardPanelRows.CLIP_PAD) - 2 * BoardPanelRows.PAD)
			local b, c = chip:FindFirstChild("Blessing"), chip:FindFirstChild("Curse")
			if b and c then fullH = BoardPanelRows.fullHeight(BC.lines(b.Text, tw), BC.lines(c.Text, tw)) end
		end)
	end
	local plan = BoardPanelRows.plan({
		blessingFullH = fullH,
		x = H.target.x - 6, w = math.min(H.target.w + 12, rect.w - (H.target.x - 6) - BoardPanelRows.CLIP_PAD), top = PlayBoardLayout.panelTop(rect.w),
		avail = root.AbsoluteSize.Y - 8 - rect.h + math.floor(PlayBoardLayout.PANEL_ROOM * rect.w / PlayBoardLayout.IMG_W),
		want = { tips = shown(tipsRow), hint = shown(hintRow), blessing = chipShown, run = shown(runRow) },
	})
	-- the board itself grows: PlayBoardPaint stretches a plain parchment band so the rows lie on the board's own parchment
	local extend = PlayBoardLayout.extension(rect.w, plan.panel.h)
	if root:GetAttribute("BoardExtend") ~= extend then root:SetAttribute("BoardExtend", extend) end
	if seatRects then -- seats on the wooden base (the sixth and later) move down with the bottom cap
		for i, seatFrame in ipairs(seatFrames) do
			if seatRects[i] and seatRects[i].extra then
				placeRect(st, seatFrame, { x = seatRects[i].x, y = seatRects[i].y + extend, w = seatRects[i].w, h = seatRects[i].h }, H.ringRow)
			end
		end
	end
	local back = sidebar:FindFirstChild("BoardPanelBack") -- only the holder of the brass lines now: no card, no edge, the parchment is the board's
	if plan.panel.h > 0 then
		if not back then
			back = Instance.new("Frame")
			back.Name = "BoardPanelBack"
			back.BorderSizePixel = 0
			back.BackgroundTransparency = 1
			back.Active = false
			back.ZIndex = 2 -- below every row (Sidebar rows draw at 3), above the painted board
			back.Parent = sidebar
			table.insert(st.made, back)
		end
		back.Position, back.Size, back.Visible = UDim2.fromOffset(plan.panel.x, plan.panel.y), UDim2.fromOffset(plan.panel.w, plan.panel.h), true
		local lines = {}
		for _, c in ipairs(back:GetChildren()) do if c.Name == "BoardPanelLine" then lines[#lines + 1] = c end end
		local ys = { plan.panel.y + 3 } -- a thin brass divider under the Patron rings, then the lines between the rows
		for _, ly in ipairs(plan.seps) do ys[#ys + 1] = ly end
		for i = #ys + 1, #lines do lines[i]:Destroy() end
		for i, ly in ipairs(ys) do
			local ln = lines[i]
			if not ln then
				ln = Instance.new("Frame")
				ln.Name = "BoardPanelLine"
				ln.BorderSizePixel = 0
				ln.Active = false
				ln.BackgroundColor3 = Color3.fromRGB(176, 138, 70) -- the thin brass line used between Hands and the rings
				ln.ZIndex = 2
				ln.Parent = back
			end
			ln.Position, ln.Size = UDim2.fromOffset(12, ly - plan.panel.y), UDim2.new(1, -24, 0, 1)
		end
	elseif back then
		back.Visible = false
	end
	local function seat(c, key)
		local r = plan.rows[key]
		if not (c and r) then return end
		flatRow(st, c)
		put(st, c, { AnchorPoint = Vector2.new(0, 0), Position = UDim2.fromOffset(r.x, r.y), Size = UDim2.fromOffset(r.w, r.h) })
	end
	seat(tipsRow, "tips")
	seat(hintRow, "hint")
	if runRow then
		if plan.rows.run then
			inkLineStyle(st, runRow)
			put(st, runRow, { AnchorPoint = Vector2.new(0, 0), Position = UDim2.fromOffset(plan.rows.run.x, plan.rows.run.y), Size = UDim2.fromOffset(plan.rows.run.w, plan.rows.run.h) })
		elseif shown(runRow) then
			put(st, runRow, { Visible = false }) -- no room left on a short screen: the run line is in Settings
		end
	end
	if chip then
		chip:SetAttribute("BoardPanel", true)
		chip:SetAttribute("PanelMode", plan.blessing)
		local r = plan.rows.blessing
		if r then
			put(st, chip, { AnchorPoint = Vector2.new(0, 0), Position = UDim2.fromOffset(r.x, r.y), Size = UDim2.fromOffset(r.w, r.h), BackgroundTransparency = 1 })
			local stroke = chip:FindFirstChildOfClass("UIStroke")
			if stroke then put(st, stroke, { Enabled = false }) end
			chip.Visible = true
		else
			chip.Visible = false
		end
		if not st.watched[chip] then
			st.watched[chip] = true
			for _, prop in ipairs({ "BackgroundTransparency", "Visible" }) do
				table.insert(st.conns, chip:GetPropertyChangedSignal(prop):Connect(function() schedule(root, st) end))
			end
			table.insert(st.conns, chip:GetAttributeChangedSignal("Shown"):Connect(function() schedule(root, st) end))
		end
	end
	local y = rect.h + extend + 6
	local stackW = math.min(230, rect.w - 2 * H.target.x)
	for _, c in ipairs(others) do
		if c.Visible and c ~= runRow then
			local h = c.Size.Y.Scale == 0 and c.Size.Y.Offset or c.AbsoluteSize.Y
			if h > 0 then
				put(st, c, { AnchorPoint = Vector2.new(0, 0), Position = UDim2.fromOffset(H.target.x, y), Size = UDim2.fromOffset(stackW, h) })
				y = y + h + 4
			end
		end
	end

	-- the old parchment fill, border line, accent wash, studs and brackets of the two frames: the table shows through below the board
	for _, top in ipairs({ sidebar, root:FindFirstChild("SidebarBoard") }) do
		if top then
			hideFill(st, top)
			for _, c in ipairs(top:GetChildren()) do
				if FRAME_DECOR[c.Name] and c:IsA("GuiObject") then put(st, c, { Visible = false }) end
			end
		end
	end

	-- pieces the theme adds on top of the rows (kit plates, pads, header plate, depth, frame)
	for _, top in ipairs({ sidebar, root:FindFirstChild("SidebarBoard") }) do
		if top then
			for _, d in ipairs(top:GetDescendants()) do
				if isThemePiece(d.Name) and d:IsA("GuiObject") then
					put(st, d, { Visible = false })
					if not st.watched[d] then
						st.watched[d] = true -- the theme may show it again when a Card Set is equipped or previewed: hide it again, once per change
						table.insert(st.conns, d:GetPropertyChangedSignal("Visible"):Connect(function() schedule(root, st) end))
					end
				end
			end
		end
	end
end

-- Studio only: a visible Frame that overlaps a plate under the board (Tips, the Select cards hint) and is not part of it is named in one warn,
-- with its path, rect, ZIndex, fill and colour, so a stray unpainted block can be found without guessing.
local function reportOverlaps(root, st)
	if not game:GetService("RunService"):IsStudio() or not st.rect then return end
	local plates = {}
	for _, host in ipairs({ root:FindFirstChild("Sidebar") }) do
		if host then
			for _, d in ipairs(host:GetDescendants()) do
				if d:IsA("Frame") and (d.Name == "TipsRow" or d.LayoutOrder == 10 or d.Name == "Hint") and d.Visible then plates[#plates + 1] = d end
			end
		end
	end
	local found = {}
	for _, plate in ipairs(plates) do
		local pp, ps = plate.AbsolutePosition, plate.AbsoluteSize
		for _, d in ipairs(root:GetDescendants()) do
			if d:IsA("Frame") and d.Visible and d.BackgroundTransparency < 1 and d.AbsoluteSize.X > 0 and d ~= plate and not d:IsDescendantOf(plate)
				and not plate:IsDescendantOf(d) and d.Name ~= "BoardPlateBack" and d.Name ~= "BoardWoodFill" then
				local p, sz = d.AbsolutePosition, d.AbsoluteSize
				if p.X < pp.X + ps.X and pp.X < p.X + sz.X and p.Y < pp.Y + ps.Y and pp.Y < p.Y + sz.Y and sz.X < root.AbsoluteSize.X * 0.6 then
					found[#found + 1] = string.format("%s pos=%d,%d size=%dx%d z=%d bgT=%.2f color=%d,%d,%d", d:GetFullName(), p.X, p.Y, sz.X, sz.Y, d.ZIndex,
						d.BackgroundTransparency, d.BackgroundColor3.R * 255, d.BackgroundColor3.G * 255, d.BackgroundColor3.B * 255)
				end
			end
		end
	end
	local key = table.concat(found, "|")
	if key ~= st.overlapKey then
		st.overlapKey = key
		warn("[PlateOverlap] " .. (#found == 0 and "nothing overlaps the Tips and hint plates" or (#found .. " visible Frame(s) overlap them:\n  " .. table.concat(found, "\n  "))))
	end
end
PlayBoardHud.reportOverlaps = function(root) local st = stateFor(root) pcall(reportOverlaps, root, st) end

function schedule(root, st)
	if st.applying or st.pending or not st.rect then return end
	st.pending = true
	-- The watchers that call schedule() fire for the very properties run() changes, so an unbroken defer chain exceeded Roblox's re-entrancy
	-- depth (80). A 50 ms cooldown between two runs moves a repeat to a later frame, which ends the chain.
	local function go()
		st.pending = false
		if not st.rect then return end
		st.applying = true
		pcall(run, root, st)
		st.applying = false
		st.lastRun = os.clock()
	end
	local wait = PlayBoardHud.RUN_COOLDOWN - (os.clock() - (st.lastRun or -1))
	if wait > 0 then task.delay(wait, go) else task.defer(go) end
end

local function unwatch(st)
	for _, cn in ipairs(st.conns) do cn:Disconnect() end
	st.conns = {}
	st.watched = setmetatable({}, { __mode = "k" })
end

local function restore(st, root)
	unwatch(st)
	local b = root and root:FindFirstChild("SidebarBoard")
	if b then b:SetAttribute("PlayBoardPainted", nil) end
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
	local chip = b and b:FindFirstChild("BlessingChip")
	if chip then
		chip:SetAttribute("BoardPanel", nil)
		chip:SetAttribute("PanelMode", nil)
		pcall(function() require(script.Parent.BlessingChip).relayout() end)
	end
end

function PlayBoardHud.apply(root, rect)
	local st = stateFor(root)
	if not rect then
		if st.rect then
			st.rect = nil
			restore(st, root)
		end
		return false
	end
	local first = st.rect == nil
	st.rect = rect
	st.applying = true
	local ok, why = pcall(run, root, st)
	st.applying = false
	if not ok then
		PlayBoardHud.lastError = tostring(why)
		st.rect = nil
		restore(st, root)
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
					table.insert(st.conns, d:GetAttributeChangedSignal("Owned"):Connect(function() schedule(root, st) end))
				elseif d:IsA("TextLabel") then
					table.insert(st.conns, d:GetPropertyChangedSignal("TextColor3"):Connect(function() schedule(root, st) end))
				end
			end
			-- late theme pieces on the board (kit frame, depth, accent wash) are hidden again
			local boardTop = root:FindFirstChild("SidebarBoard")
			if boardTop then
				table.insert(st.conns, boardTop.DescendantAdded:Connect(function() schedule(root, st) end))
				for _, d in ipairs(boardTop:GetChildren()) do
					if d:IsA("GuiObject") then
						for _, prop in ipairs({ "Visible", "BackgroundTransparency" }) do
							table.insert(st.conns, d:GetPropertyChangedSignal(prop):Connect(function() schedule(root, st) end))
						end
					end
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
