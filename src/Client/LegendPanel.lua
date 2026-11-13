--[[
	Client/LegendPanel.lua
	LEGEND PRESTIGE (Engine/Legend.lua), opened from the "Legend" button in the Collection header. A showpiece in dark
	gold and burgundy: a big gold crest with the Legend level (slow glow, shimmering gold ring and drifting sparks), a
	"Show off" card (title, aura, card back) and a ladder of ten medallions on a winding gold path: reached ones glow
	with a check, the next one pulses, locked ones are dim with a lock. Display only: the server awards points and
	rewards when a standard stake 8 run is won and sends state.legend. Refreshes on every StateUpdated while open.
	All text is cream on dark. Loops stop under Reduce Motion / calm mode and when the panel closes.

	LegendPanel.crestText(level) -> "👑3" style text, used by other screens next to the player's name.
	init(deps): { screenGui, openButton, polishPanel, polishButton, roundCorner, addSoftShadow, playClickSfx, addTooltip,
	              popIn, popOut, addButtonHoverScale, getLatestState, StateUpdatedRemote }
]]

local LegendPanel = {}
local FullScreen = require(script.Parent.PanelFullScreen)

function LegendPanel.crestText(level)
	level = math.floor(tonumber(level) or 0)
	if level <= 0 then
		return ""
	end
	return "👑" .. tostring(level)
end

function LegendPanel.init(deps)
	local OverlayManager = require(script.Parent.OverlayManager)
	local ArtIcon = require(script.Parent.ArtIcon)
	local TweenService = game:GetService("TweenService")
	local ClientSettings = require(script.Parent.ClientSettings)
	local Scene = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("LegendSceneLayout"))
	local PanelScene = require(script.Parent.PanelScene)

	-- Dark gold and burgundy palette: cream on dark everywhere, never dark on dark.
	local BURGUNDY = Color3.fromRGB(58, 20, 30)
	local BURGUNDY_DEEP = Color3.fromRGB(38, 12, 20)
	local CREAM = Color3.fromRGB(250, 235, 200)
	local CREAM_DIM = Color3.fromRGB(206, 188, 160)
	local GOLD = Color3.fromRGB(222, 182, 104)
	local BRIGHT = Color3.fromRGB(255, 226, 140)
	local DIM = Color3.fromRGB(96, 78, 66) -- locked medallion fill: dark but never black
	local PATH = Color3.fromRGB(196, 150, 70)
	local WOOD = Color3.fromRGB(86, 58, 34)

	local function calm()
		return ClientSettings.get("reduceShake") == true
	end

	local function label(parent, props)
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Font = Enum.Font.GothamBold
		l.TextColor3 = CREAM
		l.TextTransparency = 0
		l.TextStrokeTransparency = 1
		l.TextSize = 18
		l.ZIndex = 43
		for k, v in pairs(props) do
			l[k] = v
		end
		l.Parent = parent
		return l
	end

	local backdrop = Instance.new("Frame")
	backdrop.Name = "LegendBackdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	backdrop.BackgroundTransparency = 0.35
	backdrop.Visible = false
	backdrop.ZIndex = 40
	backdrop.Parent = deps.screenGui

	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Size = UDim2.fromScale(0.8, 0.88)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.BackgroundColor3 = BURGUNDY
	panel.ZIndex = 41
	panel.Parent = backdrop
	deps.roundCorner(panel, 16)
	deps.addSoftShadow(panel, 18)
	local panelStroke = Instance.new("UIStroke")
	panelStroke.Color = GOLD
	panelStroke.Thickness = 4
	panelStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	panelStroke.Parent = panel
	local panelLimit = Instance.new("UISizeConstraint")
	panelLimit.MaxSize = Vector2.new(980, 640)
	panelLimit.MinSize = Vector2.new(640, 520)
	panelLimit.Parent = panel
	local scene = PanelScene.new(panel, { artKey = Scene.ART_KEY, def = Scene.DEF, z = 41 }) -- painted trophy hall under everything (after Studio: Image id recorded)
	local sceneLayer = Instance.new("Frame") -- the trophy hall's live widgets: crest line, card back, shelf text, plaque medallions
	sceneLayer.Name = "RoomLayer"
	sceneLayer.BackgroundTransparency = 1
	sceneLayer.Size = UDim2.fromScale(1, 1)
	sceneLayer.Active = false
	sceneLayer.Visible = false
	sceneLayer.ZIndex = 42
	sceneLayer.Parent = panel
	local sceneOn = false
	local scenePlaced = nil -- last Scene.place result while the room is on
	local innerFrame = Instance.new("Frame") -- thin inner gold rule: the ornate double border
	innerFrame.Size = UDim2.new(1, -16, 1, -16)
	innerFrame.Position = UDim2.fromOffset(8, 8)
	innerFrame.BackgroundTransparency = 1
	innerFrame.Active = false
	innerFrame.ZIndex = 41
	innerFrame.Parent = panel
	deps.roundCorner(innerFrame, 12)
	local innerStroke = Instance.new("UIStroke")
	innerStroke.Color = Color3.fromRGB(150, 112, 60)
	innerStroke.Thickness = 1.5
	innerStroke.Parent = innerFrame

	-- Title and subtitle (cream and gold on burgundy)
	label(panel, { Size = UDim2.new(1, 0, 0, 40), Position = UDim2.fromOffset(0, 10), TextSize = 32, Text = "Legend", TextColor3 = BRIGHT })
	local hintLabel = label(panel, {
		Size = UDim2.new(1, -60, 0, 24), Position = UDim2.fromOffset(30, 50), TextSize = 18, Font = Enum.Font.GothamMedium,
		TextWrapped = true, Text = "",
	})

	-- Crest: a gold medallion with a slow glow pulse, drifting sparks and the level shown large.
	local crestHolder = Instance.new("Frame")
	crestHolder.Size = UDim2.fromOffset(150, 150)
	crestHolder.Position = UDim2.fromOffset(34, 84)
	crestHolder.BackgroundTransparency = 1
	crestHolder.ZIndex = 42
	crestHolder.Parent = panel
	local glow = Instance.new("Frame")
	glow.Name = "Glow"
	glow.AnchorPoint = Vector2.new(0.5, 0.5)
	glow.Position = UDim2.fromScale(0.5, 0.5)
	glow.Size = UDim2.fromOffset(150, 150)
	glow.BackgroundColor3 = BRIGHT
	glow.BackgroundTransparency = 0.75
	glow.BorderSizePixel = 0
	glow.ZIndex = 42
	glow.Parent = crestHolder
	deps.roundCorner(glow, 75)
	local crest = Instance.new("Frame")
	crest.AnchorPoint = Vector2.new(0.5, 0.5)
	crest.Position = UDim2.fromScale(0.5, 0.5)
	crest.Size = UDim2.fromOffset(122, 122)
	crest.BackgroundColor3 = BURGUNDY_DEEP
	crest.BorderSizePixel = 0
	crest.ZIndex = 43
	crest.Parent = crestHolder
	deps.roundCorner(crest, 61)
	local crestStroke = Instance.new("UIStroke")
	crestStroke.Color = BRIGHT
	crestStroke.Thickness = 5
	crestStroke.Parent = crest
	local crestGradient = Instance.new("UIGradient") -- Color stops only: a slow gold shimmer
	crestGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(150, 104, 40)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 232, 160)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(150, 104, 40)),
	})
	crestGradient.Parent = crestStroke
	label(crest, { Size = UDim2.new(1, 0, 0, 36), Position = UDim2.fromOffset(0, 10), TextSize = 32, Text = "👑", TextColor3 = BRIGHT, ZIndex = 44 })
	local levelLabel = label(crest, { Size = UDim2.new(1, 0, 0, 52), Position = UDim2.fromOffset(0, 50), TextSize = 40, Text = "0", TextColor3 = CREAM, ZIndex = 44 })

	local sparks = {}
	for i = 1, 6 do
		local sp = Instance.new("Frame")
		sp.Size = UDim2.fromOffset(6, 6)
		sp.BackgroundColor3 = BRIGHT
		sp.BorderSizePixel = 0
		sp.Rotation = 45
		sp.BackgroundTransparency = 1
		sp.ZIndex = 45
		sp.Active = false
		sp.Parent = crestHolder
		sparks[i] = sp
	end

	local loopToken = 0
	local function stopLoops()
		loopToken = loopToken + 1
	end
	local function startLoops()
		stopLoops()
		if calm() then return end
		local mine = loopToken
		task.spawn(function() -- glow breathes, the ring gradient sweeps slowly
			local grow = true
			while loopToken == mine and backdrop.Visible do
				TweenService:Create(glow, TweenInfo.new(1.6, Enum.EasingStyle.Sine), {
					BackgroundTransparency = grow and 0.55 or 0.85, Size = UDim2.fromOffset(grow and 166 or 146, grow and 166 or 146),
				}):Play()
				TweenService:Create(crestGradient, TweenInfo.new(1.6, Enum.EasingStyle.Sine), { Rotation = grow and 90 or 0 }):Play()
				grow = not grow
				task.wait(1.6)
			end
		end)
		for i, sp in ipairs(sparks) do
			task.spawn(function() -- drifting sparks rise off the crest
				task.wait(i * 0.45)
				while loopToken == mine and backdrop.Visible do
					local x = math.random(30, 120)
					sp.Position = UDim2.fromOffset(x, 120)
					sp.BackgroundTransparency = 0.1
					TweenService:Create(sp, TweenInfo.new(2.4, Enum.EasingStyle.Quad), {
						Position = UDim2.fromOffset(x + math.random(-14, 14), 6), BackgroundTransparency = 1,
					}):Play()
					task.wait(2.7)
				end
			end)
		end
	end

	-- "Show off": the title, aura and card back the player has earned, on one card.
	local show = Instance.new("Frame")
	show.Name = "ShowOff"
	show.Size = UDim2.new(1, -230, 0, 150)
	show.Position = UDim2.fromOffset(200, 84)
	show.BackgroundColor3 = BURGUNDY_DEEP
	show.BorderSizePixel = 0
	show.ZIndex = 42
	show.Parent = panel
	deps.roundCorner(show, 12)
	local showStroke = Instance.new("UIStroke")
	showStroke.Color = GOLD
	showStroke.Thickness = 2
	showStroke.Parent = show
	label(show, { Size = UDim2.new(1, -20, 0, 24), Position = UDim2.fromOffset(14, 8), TextSize = 18, Text = "Show off", TextColor3 = BRIGHT, TextXAlignment = Enum.TextXAlignment.Left })
	local showTitle = label(show, { Size = UDim2.new(1, -150, 0, 28), Position = UDim2.fromOffset(14, 40), TextSize = 20, Text = "", TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd })
	local showAura = label(show, { Size = UDim2.new(1, -150, 0, 26), Position = UDim2.fromOffset(14, 72), TextSize = 18, Text = "", TextColor3 = GOLD, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd })
	local showBackLabel = label(show, { Size = UDim2.new(1, -150, 0, 26), Position = UDim2.fromOffset(14, 102), TextSize = 18, Text = "", TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd })
	local showBack = Instance.new("Frame") -- card back preview, 2:3
	showBack.Size = UDim2.fromOffset(84, 126)
	showBack.AnchorPoint = Vector2.new(1, 0.5)
	showBack.Position = UDim2.new(1, -16, 0.5, 0)
	showBack.BackgroundColor3 = WOOD
	showBack.BorderSizePixel = 0
	showBack.ZIndex = 43
	showBack.Parent = show
	deps.roundCorner(showBack, 8)
	local showBackStroke = Instance.new("UIStroke")
	showBackStroke.Color = BRIGHT
	showBackStroke.Thickness = 2
	showBackStroke.Parent = showBack
	local showBackGlyph = label(showBack, { Size = UDim2.fromScale(1, 1), TextSize = 34, Text = "🂠", TextColor3 = CREAM, ZIndex = 44 })

	-- The ladder: ten medallions on a winding gold path (row one runs left to right, row two right to left).
	local ladder = Instance.new("Frame")
	ladder.Name = "Ladder"
	ladder.Size = UDim2.new(1, -40, 0, 260)
	ladder.Position = UDim2.fromOffset(20, 250)
	ladder.BackgroundTransparency = 1
	ladder.ZIndex = 41
	ladder.Parent = panel

	local closeButton = Instance.new("TextButton")
	closeButton.Size = UDim2.fromOffset(120, 38)
	closeButton.AnchorPoint = Vector2.new(0.5, 1)
	closeButton.Position = UDim2.new(0.5, 0, 1, -14)
	closeButton.Font = Enum.Font.GothamBold
	closeButton.TextSize = 18
	closeButton.TextColor3 = CREAM
	closeButton.BackgroundColor3 = Color3.fromRGB(110, 40, 52)
	closeButton.Text = "Close"
	closeButton.ZIndex = 43
	closeButton.Parent = panel
	deps.polishButton(closeButton, 8)
	deps.addButtonHoverScale(closeButton)

	local NODE = 84
	local ROW_H = 126
	local function nodePos(i)
		-- two rows of five; the second row runs right to left so the path snakes
		local col = (i - 1) % 5
		local row = math.floor((i - 1) / 5)
		if row == 1 then col = 4 - col end
		return col, row
	end

	local function medallion(row, isNext)
		local col, r = nodePos(row.level)
		local m = Instance.new("Frame")
		m.Name = "Level_" .. row.level
		m.AnchorPoint = Vector2.new(0.5, 0)
		m.Position = UDim2.new((col + 0.5) / 5, 0, 0, r * ROW_H + 6)
		m.Size = UDim2.fromOffset(NODE, NODE)
		m.BackgroundColor3 = row.reached and BURGUNDY_DEEP or DIM
		m.BorderSizePixel = 0
		m.ZIndex = 44
		m.Parent = ladder
		deps.roundCorner(m, NODE / 2)
		local ring = Instance.new("UIStroke")
		ring.Color = (row.reached or isNext) and BRIGHT or Color3.fromRGB(70, 56, 48)
		ring.Thickness = (row.reached or isNext) and 4 or 2
		ring.Parent = m
		local emoji = row.icon or (row.kind == "cardBack" and "🂠" or "🏷️")
		local glyph = label(m, { Size = UDim2.fromScale(1, 1), TextSize = 38, Text = emoji, TextColor3 = CREAM, ZIndex = 46 })
		local category = (row.kind == "cardBack" and "card_backs") or (row.kind == "title" and "titles") or (row.kind == "trinket" and "legend") or nil
		if category then
			pcall(ArtIcon.apply, m, category, row.id, glyph, { cornerRadius = NODE / 2, zIndex = 47, dim = not row.reached })
		end
		if not row.reached then
			glyph.TextTransparency = 0.5
			label(m, { Size = UDim2.fromOffset(26, 26), AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, 2, 1, 2), TextSize = 20, Text = "🔒", ZIndex = 50 })
		else
			local check = label(m, {
				Size = UDim2.fromOffset(26, 26), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 4, 0, -4), TextSize = 18,
				Text = "✓", TextColor3 = BURGUNDY_DEEP, BackgroundTransparency = 0, BackgroundColor3 = BRIGHT, ZIndex = 50,
			})
			deps.roundCorner(check, 13)
		end
		if isNext and not calm() then -- the next medallion pulses
			local mine = loopToken
			task.spawn(function()
				local big = true
				while loopToken == mine and backdrop.Visible and m.Parent do
					TweenService:Create(ring, TweenInfo.new(0.9, Enum.EasingStyle.Sine), { Thickness = big and 7 or 3 }):Play()
					big = not big
					task.wait(0.9)
				end
			end)
		end
		label(ladder, {
			Size = UDim2.fromOffset(150, 34), AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new((col + 0.5) / 5, 0, 0, r * ROW_H + NODE + 8),
			TextSize = 15, Text = row.text, TextWrapped = true,
			TextColor3 = row.reached and CREAM or CREAM_DIM, Font = Enum.Font.GothamMedium,
		})
		deps.addTooltip(m, row.text .. (row.reached and "" or (" at Legend level " .. row.level)))
	end

	-- gold path segments between neighbouring medallions (created first so the medallions sit on top)
	local function pathSegment(i, reachedUpTo)
		local c1, r1 = nodePos(i)
		local c2, r2 = nodePos(i + 1)
		local seg = Instance.new("Frame")
		seg.BorderSizePixel = 0
		local lit = (i + 1) <= reachedUpTo
		seg.BackgroundColor3 = lit and BRIGHT or PATH
		seg.BackgroundTransparency = lit and 0 or 0.45
		seg.ZIndex = 43
		seg.Active = false
		if r1 == r2 then
			local left = math.min(c1, c2)
			seg.Position = UDim2.new((left + 0.5) / 5, 0, 0, r1 * ROW_H + 6 + math.floor(NODE / 2) - 3)
			seg.Size = UDim2.new(1 / 5, 0, 0, 6)
		else -- the turn at the right end: a short vertical rung down from the last medallion
			seg.AnchorPoint = Vector2.new(0.5, 0)
			seg.Position = UDim2.new((c2 + 0.5) / 5, 0, 0, r1 * ROW_H + 6 + NODE)
			seg.Size = UDim2.fromOffset(6, ROW_H - NODE)
		end
		seg.Parent = ladder
	end

	-- ===== painted trophy hall (legend_room_a): the card back stands in the alcove, Show off lines sit on the shelves, the ten ladder
	-- rewards are medallions on the five brass plaques (two levels each; full names in the tooltip and the "Next" line) =====
	local function layoutRoom()
		local screen = deps.screenGui.AbsoluteSize
		local pw, ph = Scene.panel(screen.X, screen.Y)
		pw, ph = FullScreen.fit(panel, pw, ph, screen.X, screen.Y) -- a full screen panel: the real screen below the tab strip
		local placed = scene.id and Scene.place(pw, ph - Scene.TOP - Scene.BOTTOM) or nil
		sceneOn = placed ~= nil and placed.ok and pw >= 640 and ph >= 520 -- the panel's own minimum size
		scenePlaced = sceneOn and placed or nil
		-- the frame, header and footer are the dark wood of the other Tome panels while the room is up (maroon only in the plain layout)
		local C = Scene.COLORS
		panel.BackgroundColor3 = sceneOn and Color3.fromRGB(C.frame[1], C.frame[2], C.frame[3]) or BURGUNDY
		innerStroke.Color = sceneOn and Color3.fromRGB(C.frameLine[1], C.frameLine[2], C.frameLine[3]) or Color3.fromRGB(150, 112, 60)
		closeButton.BackgroundColor3 = sceneOn and Color3.fromRGB(C.closeButton[1], C.closeButton[2], C.closeButton[3]) or Color3.fromRGB(110, 40, 52)
		if sceneOn then
			panelLimit.MaxSize = Vector2.new(Scene.PANEL_MAX[1], Scene.PANEL_MAX[2])
			FullScreen.setRect(panel, UDim2.fromOffset(pw, ph))
			scene.show({ x = 0, y = Scene.TOP, w = pw, h = ph - Scene.TOP }, placed) -- the painting runs under the footer to the panel bottom
			for _, p in ipairs(placed.plaques) do p.y = p.y + Scene.TOP end
			for _, p in ipairs(placed.shelves) do p.y = p.y + Scene.TOP end
			placed.alcove.y = placed.alcove.y + Scene.TOP
		else
			panelLimit.MaxSize = Vector2.new(980, 640)
			FullScreen.setRect(panel, UDim2.fromScale(0.8, 0.88))
			scene.hide()
		end
		sceneLayer.Visible = sceneOn
		do local sh = panel.Parent and panel.Parent:FindFirstChild("Shadow"); if sh then sh.Visible = not sceneOn end -- the sibling drop shadow keeps the plain size and showed as a stray lighter rectangle behind the room
		end
		crestHolder.Visible = not sceneOn
		show.Visible = not sceneOn
		ladder.Visible = not sceneOn
		if not sceneOn then
			-- the card back goes home to the Show off card
			showBack.Parent = show
			showBack.AnchorPoint = Vector2.new(1, 0.5)
			showBack.Position = UDim2.new(1, -16, 0.5, 0)
			showBack.Size = UDim2.fromOffset(84, 126)
		end
		if game:GetService("RunService"):IsStudio() then
			local key = pw .. "x" .. ph .. (sceneOn and "on" or "off")
			if key ~= LegendPanel._lastKey then
				LegendPanel._lastKey = key
				local shownH = sceneOn and ph or math.min(math.floor(screen.Y * 0.88), 640) -- the plain panel is 88 percent of the height, max 640
				local fit = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("PanelLayout")).fit(screen.Y, shownH)
				print(string.format("[PanelFit] legend screen=%dx%d panel=%dx%d top=%d bottom=%d fits=%s", screen.X, screen.Y, pw, shownH, fit.top, fit.bottom, tostring(fit.fits)))
				print(string.format("[LegendRoom] %s slots=%d (alcove 1, plaques %d, shelves %d) panel %dx%d", sceneOn and "painted" or "plain",
					sceneOn and (1 + #placed.plaques + #placed.shelves) or 0, sceneOn and #placed.plaques or 0, sceneOn and #placed.shelves or 0, pw, ph))
			end
		end
	end

	local function clearRoom()
		showBack.Parent = show -- the card back is reparented into the alcove while the room is up; save it before clearing
		for _, ch in ipairs(sceneLayer:GetChildren()) do ch:Destroy() end
	end

	local function paintRoom(view, nextRow, lines)
		clearRoom()
		if not sceneOn or not scenePlaced then return end
		local P = scenePlaced
		local function holder(rect)
			local f = Instance.new("Frame")
			f.BackgroundTransparency = 1
			f.Position, f.Size = UDim2.fromOffset(rect.x, rect.y), UDim2.fromOffset(rect.w, rect.h)
			f.Active = false
			f.ZIndex = 43
			f.Parent = sceneLayer
			return f
		end
		-- alcove: crest line on top, the card back, the next reward under it
		local alcove = holder(P.alcove)
		local parts = Scene.alcoveParts(P.alcove)
		label(alcove, { Position = UDim2.fromOffset(parts.crest.x, parts.crest.y), Size = UDim2.fromOffset(parts.crest.w, parts.crest.h),
			TextSize = 20, Text = "👑 Legend " .. tostring(view.level), TextColor3 = BRIGHT })
		showBack.Parent = alcove
		showBack.AnchorPoint = Vector2.new(0, 0)
		showBack.Position, showBack.Size = UDim2.fromOffset(parts.back.x, parts.back.y), UDim2.fromOffset(parts.back.w, parts.back.h)
		label(alcove, { Position = UDim2.fromOffset(parts.next.x, parts.next.y), Size = UDim2.fromOffset(parts.next.w, parts.next.h), TextSize = 14,
			Font = Enum.Font.GothamMedium, TextWrapped = true,
			Text = nextRow and ("Next: " .. nextRow.text .. " at Legend " .. nextRow.level) or "Every reward earned" })
		-- shelves: the three Show off lines
		for i, line in ipairs(lines) do
			local shelf = P.shelves[i]
			if shelf then
				-- a small parchment strip each, ink on it (the bare dark shelf back made the text float)
				local strip = Scene.shelfStrip(shelf)
				local sc = Scene.COLORS
				local plate = label(sceneLayer, { Name = "ShelfStrip" .. i, Position = UDim2.fromOffset(shelf.x + strip.x, shelf.y + strip.y), Size = UDim2.fromOffset(strip.w, strip.h),
					TextSize = 14, TextWrapped = true, Text = line.text, TextColor3 = Color3.fromRGB(sc.shelfInk[1], sc.shelfInk[2], sc.shelfInk[3]),
					Font = Enum.Font.GothamMedium, BackgroundTransparency = 0.12, BackgroundColor3 = Color3.fromRGB(sc.shelfStrip[1], sc.shelfStrip[2], sc.shelfStrip[3]) })
				deps.roundCorner(plate, 4)
				local pad = Instance.new("UIPadding") -- 8 px inner padding so text never touches the strip edge (two lines allowed)
				pad.PaddingLeft, pad.PaddingRight, pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 8), UDim.new(0, 8), UDim.new(0, 4), UDim.new(0, 4)
				pad.Parent = plate
			end
		end
		-- plaques: two reward medallions each, level under every one
		local byLevel = {}
		for _, row in ipairs(view.rewards) do byLevel[row.level] = row end
		local nextLevel = view.level < view.max and (view.level + 1) or nil
		for k, lv in ipairs(Scene.pairs(#view.rewards)) do
			local plaque = P.plaques[k]
			if plaque then
				local box = holder(plaque)
				local pp = Scene.plaqueParts(plaque)
				for c = 1, 2 do
					local level = lv[c]
					local row = byLevel[level]
					if row and (c == 1 or level ~= lv[1]) then
						local r = pp[c]
						local isNext = row.level == nextLevel
						local m = Instance.new("Frame")
						m.Name = "Level_" .. row.level
						m.Position, m.Size = UDim2.fromOffset(r.medal.x, r.medal.y), UDim2.fromOffset(r.medal.w, r.medal.h)
						m.BackgroundColor3 = row.reached and BURGUNDY_DEEP or DIM
						m.BorderSizePixel = 0
						m.ZIndex = 44
						m.Parent = box
						deps.roundCorner(m, r.medal.w / 2)
						local ring = Instance.new("UIStroke")
						ring.Color = (row.reached or isNext) and BRIGHT or Color3.fromRGB(70, 56, 48)
						ring.Thickness = (row.reached or isNext) and 3 or 1.5
						ring.Parent = m
						local glyph = label(m, { Size = UDim2.fromScale(1, 1), TextSize = math.max(14, math.floor(r.medal.w * 0.55)), Text = row.icon or (row.kind == "cardBack" and "🂠" or "🏷️"),
							TextColor3 = CREAM, ZIndex = 46 })
						local category = (row.kind == "cardBack" and "card_backs") or (row.kind == "title" and "titles") or (row.kind == "trinket" and "legend") or nil
						if category then
							pcall(ArtIcon.apply, m, category, row.id, glyph, { cornerRadius = r.medal.w / 2, zIndex = 47, dim = not row.reached })
						end
						if not row.reached then
							glyph.TextTransparency = 0.5
							label(m, { Size = UDim2.fromOffset(16, 16), AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, 3, 1, 3), TextSize = 14, Text = "🔒", ZIndex = 50 })
						else
							local check = label(m, { Size = UDim2.fromOffset(16, 16), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 3, 0, -3), TextSize = 14,
								Text = "✓", TextColor3 = BURGUNDY_DEEP, BackgroundTransparency = 0, BackgroundColor3 = BRIGHT, ZIndex = 50 })
							deps.roundCorner(check, 8)
						end
						-- cream on a small dark pill (cream straight on the brass is only 3.8:1)
						local lc = Scene.COLORS
						local pillW = math.min(r.num.w - 4, 46)
						local pill = label(box, { Name = "Lv" .. row.level, Position = UDim2.fromOffset(r.num.x + math.floor((r.num.w - pillW) / 2), r.num.y), Size = UDim2.fromOffset(pillW, r.num.h), TextSize = 14,
							Text = "Lv " .. row.level, TextColor3 = Color3.fromRGB(lc.lvInk[1], lc.lvInk[2], lc.lvInk[3]), ZIndex = 44,
							BackgroundTransparency = 0.1, BackgroundColor3 = Color3.fromRGB(lc.lvPill[1], lc.lvPill[2], lc.lvPill[3]) })
						deps.roundCorner(pill, r.num.h // 2)
						deps.addTooltip(m, row.text .. (row.reached and "" or (" at Legend level " .. row.level)))
					end
				end
			end
		end
	end

	local function refresh()
		for _, child in ipairs(ladder:GetChildren()) do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		local state = deps.getLatestState and deps.getLatestState() or nil
		local view = state and state.legend
		if not view then
			levelLabel.Text = "0"
			hintLabel.Text = "Legend loads when you join."
			if sceneOn then clearRoom() end
			return
		end
		levelLabel.Text = tostring(view.level)
		hintLabel.Text = view.open and view.hint or "Clear stake 8 to become a Legend. Rewards are cosmetic, never power."
		local nextLevel = view.level < view.max and (view.level + 1) or nil
		if not sceneOn then
			for i = 1, #view.rewards - 1 do
				pathSegment(i, view.level)
			end
			for _, row in ipairs(view.rewards) do
				medallion(row, row.level == nextLevel)
			end
		end
		-- Show off card: the newest title, the aura and the newest card back earned so far
		local bestTitle, bestBack
		for _, row in ipairs(view.rewards) do
			if row.reached and row.kind == "title" then bestTitle = row end
			if row.reached and row.kind == "cardBack" then bestBack = row end
		end
		showTitle.Text = bestTitle and ("Title: " .. bestTitle.text) or "Title: earn Legend 1"
		showAura.Text = view.aura and "Aura: Gold name aura" or "Aura: unlocks at Legend 2"
		showBackLabel.Text = bestBack and ("Back: " .. bestBack.text) or "Card back: unlocks at Legend 3"
		showBackGlyph.Text = "🂠"
		showBackGlyph.TextTransparency = 0
		for _, c in ipairs(showBack:GetChildren()) do
			if c:IsA("ImageLabel") then c:Destroy() end
		end
		-- Nothing earned yet: show the default painted back (dimmed) instead of the grey missing-art box.
		pcall(ArtIcon.apply, showBack, "card_backs", bestBack and bestBack.id or "classic", showBackGlyph,
			{ cornerRadius = 8, zIndex = 46, dim = not bestBack })
		if sceneOn then
			local nextRow
			for _, row in ipairs(view.rewards) do
				if not row.reached and (not nextRow or row.level < nextRow.level) then nextRow = row end
			end
			paintRoom(view, nextRow, {
				{ text = showTitle.Text }, { text = showAura.Text, color = GOLD }, { text = showBackLabel.Text },
			})
		end
	end

	require(script.Parent.PanelTabs).attach(backdrop, "legend", deps.playClickSfx, panel) -- shared tab strip + Back
	OverlayManager.register("legend", function()
		stopLoops()
		deps.popOut(backdrop, panel)
	end)
	local function openThisPanel()
		deps.playClickSfx()
		OverlayManager.closeAllExcept("legend")
		deps.popIn(backdrop, panel)
		layoutRoom() -- the painted room (or the plain layout) is decided from the screen size before anything is built
		startLoops() -- before refresh: refresh starts the next-medallion pulse with the current loop token
		refresh()
	end
	OverlayManager.registerOpener("legend", openThisPanel)
	deps.openButton.MouseButton1Click:Connect(openThisPanel)
	require(script.Parent.CloseX).retire(closeButton)
	require(script.Parent.CloseX).attach(panel, function()
		deps.playClickSfx()
		stopLoops()
		deps.popOut(backdrop, panel)
	end)
	backdrop:GetPropertyChangedSignal("Visible"):Connect(function()
		if not backdrop.Visible then stopLoops() end
	end)
	deps.screenGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		if backdrop.Visible then
			layoutRoom()
			refresh()
		end
	end)
	deps.StateUpdatedRemote.OnClientEvent:Connect(function()
		task.defer(function()
			if backdrop.Visible then
				refresh()
			end
		end)
	end)
end

return LegendPanel
