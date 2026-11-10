--[[
	Client/LedgerBook.lua
	The Tavern Ledger as an open leather book on a tavern desk (used by Client/StatsPanel.lua). Three spreads, picked
	with red silk bookmark tabs on the right edge of the book, level with the top of the pages:
	  Story         left: Runs won, Runs started and Best Night as inked numbers, win rate as an ink bar; right: favourite
	                Patron and the lifetime lines
	  Hall of Fame  left: up to three best runs as notes with a win or loss stamp; right: best Night per stake
	  Records       left: bars of the last runs; right: the run list (tap a row for details and the Seed code)
	The painted book (ledger_book_open) is the page surface and is never redrawn. Every line of writing sits ON the
	book's own ruled lines at their measured angle (Engine/LedgerBookGeometry.lua, maths in Engine/LedgerLayout.lua), in dark
	brown ink at full opacity. The book rests on the table at about 62 percent of the panel width, keeping the art's aspect.
	Page turns flip a sheet cut from the same art (0.22 s in, 0.22 s out); calm mode crossfades in 0.12 s. Numbers count up
	when the ledger opens and a newly beaten record stamps in. "Reduce screen shake" skips every animation. Data mapping
	lives in Engine/LedgerPages.lua (tested). Without the art the drawn leather, cream pages and ruled lines show instead.
	deps: roundCorner, playClickSfx, addTooltip, getLatestState
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local LedgerBook = {}

function LedgerBook.build(deps, desk)
	local Engine = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine")
	local Pages = require(Engine:WaitForChild("LedgerPages"))
	local Layout = require(Engine:WaitForChild("LedgerLayout"))
	local LedgerArt = require(Engine:WaitForChild("LedgerArt"))
	local Stakes = require(Engine:WaitForChild("Stakes"))
	local Patrons = require(Engine:WaitForChild("Patrons"))
	local Achievements = require(Engine:WaitForChild("Achievements"))
	local ArtIcon = require(script.Parent.ArtIcon)
	local ClientSettings = require(script.Parent.ClientSettings)
	local Cue = require(script.Parent.Cue)

	local INK = Color3.fromRGB(Layout.INK[1], Layout.INK[2], Layout.INK[3])
	local INK_DIM = Color3.fromRGB(Layout.INK_DIM[1], Layout.INK_DIM[2], Layout.INK_DIM[3])
	local PAGE = Color3.fromRGB(244, 232, 204)
	local LEATHER = Color3.fromRGB(88, 52, 30)
	local BRASS = Color3.fromRGB(200, 160, 70)
	local WIN_INK = Color3.fromRGB(176, 48, 40)
	local LOSS_INK = Color3.fromRGB(70, 96, 150)
	local Z = 42
	local MODE_TAGS = { daily = "Daily", weekly = "Weekly", seed = "Seed", challenge = "Twist", rush = "Rush", quick = "Quick" }

	local function calm() return ClientSettings.get("reduceShake") == true end

	local function piece(parent, props, radius)
		local f = Instance.new("Frame")
		f.BorderSizePixel = 0
		f.ZIndex = Z
		for k, v in pairs(props) do f[k] = v end
		f.Parent = parent
		if radius then deps.roundCorner(f, radius) end
		return f
	end

	local function text(parent, props)
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Font = Enum.Font.GothamBold
		l.TextColor3 = INK
		l.TextTransparency = 0
		l.TextStrokeTransparency = 1
		l.TextSize = 16
		l.ZIndex = Z + 2
		for k, v in pairs(props) do l[k] = v end
		l.Parent = parent
		return l
	end

	local function stroke(inst, color, thickness)
		local s = Instance.new("UIStroke")
		s.Color = color
		s.Thickness = thickness
		s.Parent = inst
		return s
	end

	-- recorded art laid over a fallback piece (does nothing while the key has no id)
	local function artOver(parent, key, props)
		local id = LedgerArt[key]
		if type(id) ~= "string" or id == "" then return nil end
		local img = Instance.new("ImageLabel")
		img.BackgroundTransparency = 1
		img.Image = id
		img.ZIndex = Z + 1
		img.Active = false
		for k, v in pairs(props or { Size = UDim2.fromScale(1, 1) }) do img[k] = v end
		img.Parent = parent
		return img
	end

	local fmt = Pages.fmt

	-- ===== desk and book =====
	local deskTop = piece(desk, { Name = "LedgerDesk", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(58, 38, 24) }, 14)
	do
		local g = Instance.new("UIGradient") -- Color stops only
		g.Color = ColorSequence.new(Color3.fromRGB(86, 58, 36), Color3.fromRGB(36, 24, 16))
		g.Rotation = 90
		g.Parent = deskTop
	end
	artOver(deskTop, "ledger_desk")
	require(script.Parent.SetSkin).register(deskTop, "panel") -- the set skin's code border (never the old stretched art)
	local ink = piece(deskTop, { Name = "InkwellFallback", Size = UDim2.fromOffset(18, 34), AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(0.985, 0, 0.99, 0), BackgroundColor3 = Color3.fromRGB(30, 22, 18) }, 5)
	stroke(ink, BRASS, 2)
	artOver(deskTop, "ledger_quill_inkwell", { Size = UDim2.fromOffset(70, 70), AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(0.99, 0, 0.995, 0) })

	local R = Pages.LAYOUT
	-- the scene darkens a little behind the book so the pages are the brightest thing
	piece(desk, { Name = "DeskDim", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(0, 0, 0), BackgroundTransparency = 0.7, Active = false }, 14)

	-- The book sits on the table: a slot (about 62 percent of the panel width, bottom on the table line) holds the book at the
	-- art's own aspect ratio, bottom centred, with a soft contact shadow under it that is a little wider than the book.
	local slot = piece(desk, { Name = "BookSlot", BackgroundTransparency = 1, Active = false })
	local function fitSlot()
		local r = (desk.AbsoluteSize.X > 0 and desk.AbsoluteSize.X < 700) and R.bookCompact or R.book
		slot.Position = UDim2.fromScale(r.x, r.y)
		slot.Size = UDim2.fromScale(r.w, r.h)
	end
	fitSlot()
	desk:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitSlot)
	local holder = piece(slot, { Name = "BookHolder", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 1), Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Active = false })
	do
		local ar = Instance.new("UIAspectRatioConstraint")
		ar.AspectRatio = Layout.ASPECT
		ar.AspectType = Enum.AspectType.FitWithinMaxSize
		ar.DominantAxis = Enum.DominantAxis.Width
		ar.Parent = holder
	end
	piece(holder, { Name = "ContactShadow", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 1.0), Size = UDim2.fromScale(1.06, 0.06), BackgroundColor3 = Color3.fromRGB(0, 0, 0), BackgroundTransparency = 0.65, Active = false }, 40)
	local book = piece(holder, { Name = "Book", Size = UDim2.fromScale(1, 1), BackgroundColor3 = LEATHER, ZIndex = Z + 1 }, 10)
	local bookStroke = stroke(book, BRASS, 3)
	-- The painted open book is the page surface: its leather and pages show through, and the page frames below are
	-- transparent (text is written straight onto the paper). Without the art the drawn leather, cream pages and spine show.
	local bookArt = artOver(book, "ledger_book_open")
	local spine = piece(book, { Name = "Spine", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(Layout.GEOMETRY.gutterX, 0.02), Size = UDim2.new(0, 10, 0.96, 0), BackgroundColor3 = Color3.fromRGB(60, 36, 20), ZIndex = Z + 2 })
	if bookArt then
		book.BackgroundTransparency = 1
		bookStroke.Enabled = false
		spine.Visible = false
	end

	-- the book's real pixel height drives the text sizes (falls back to the viewport before the first layout)
	local function metrics()
		local h = book.AbsoluteSize.Y
		if h < 60 then
			local cam = workspace.CurrentCamera
			local vp = cam and cam.ViewportSize or Vector2.new(1920, 1080)
			local pr = Pages.panelRect(vp.X, vp.Y)
			local r = (pr.w < 700) and R.bookCompact or R.book
			h = math.min(pr.w * r.w, pr.h * r.h * Layout.ASPECT) / Layout.ASPECT
		end
		return Layout.sizes(h)
	end

	local function pageFrame(name, side)
		local box = Layout.pageBox(side)
		local p = piece(book, { Name = name, Position = UDim2.fromScale(box.x, box.y), Size = UDim2.fromScale(box.w, box.h), BackgroundColor3 = PAGE, ClipsDescendants = true, ZIndex = Z + 1 }, 6)
		if bookArt then
			p.BackgroundTransparency = 1
		else
			stroke(p, Color3.fromRGB(205, 186, 150), 1)
		end
		return p
	end
	local leftPage = pageFrame("LeftPage", "left")
	local rightPage = pageFrame("RightPage", "right")
	local function pageOf(side) return side == "left" and leftPage or rightPage end

	-- ===== writing on the ruled lines =====
	-- One text row on ruled line i from t0 to t1 of its usable span: bottom-left anchored, rotated to the line's angle and lifted 3 px.
	local function row(side, i, t0, t1, props, tall)
		local sz = metrics()
		local p = Layout.place(side, i, t0, t1)
		local base = {
			AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(p.xs, p.xo, p.ys, p.yo), Size = UDim2.new(p.ws, 0, 0, math.floor(sz.spacing * (tall or 0.95))),
			Rotation = p.angle, Font = Enum.Font.GothamMedium, TextSize = sz.body, TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Bottom, TextTruncate = Enum.TextTruncate.AtEnd,
		}
		for k, v in pairs(props) do base[k] = v end
		return text(pageOf(side), base)
	end

	-- a rotated, page-tilted region between ruled lines k1-1 and k2 (k1 = 1 starts one line spacing above line 1) for widgets
	local function band(side, k1, k2, props)
		local box = Layout.pageBox(side)
		local sp = Layout.spacing()
		local first = Layout.span(side, 1)
		local _, topY = Layout.point(side, k1 == 1 and 1 or (k1 - 1), 0)
		if k1 == 1 then topY = topY - sp end
		local _, botY = Layout.point(side, k2, 0)
		local base = {
			Name = "Band", BackgroundTransparency = 1, Active = false, Rotation = Layout.pageAngle(side),
			Position = UDim2.fromScale((first.x0 - box.x) / box.w, (topY - box.y) / box.h),
			Size = UDim2.fromScale((first.x1 - first.x0) / box.w, (botY - topY) / box.h),
		}
		for k, v in pairs(props or {}) do base[k] = v end
		return piece(pageOf(side), base)
	end

	local function ruledLines(side) -- the painted pages have their own; the drawn fallback follows the same measured lines
		if bookArt then return end
		for i = 1, Layout.LINE_COUNT do
			local p = Layout.place(side, i, 0, 1)
			piece(pageOf(side), { Position = UDim2.new(p.xs, 0, p.ys, 0), Size = UDim2.new(p.ws, 0, 0, 1), Rotation = p.angle, BackgroundColor3 = Color3.fromRGB(222, 205, 172), ZIndex = Z + 1 })
		end
	end

	-- ===== small pieces =====
	local function stamp(parent, pos, won, size)
		local s = piece(parent, { Size = UDim2.fromOffset(size, size), Position = pos, BackgroundTransparency = 1, Rotation = won and -12 or 9, ZIndex = Z + 4 }, size // 2)
		local col = won and WIN_INK or LOSS_INK
		stroke(s, col, 3)
		text(s, { Size = UDim2.fromScale(1, 1), Text = won and "WON" or "LOST", TextSize = math.max(14, size // 4), TextColor3 = col, ZIndex = Z + 5 })
		artOver(s, won and "ledger_stamp_win" or "ledger_stamp_loss", { Size = UDim2.fromScale(1.1, 1.1), Position = UDim2.fromScale(-0.05, -0.05), ZIndex = Z + 6 })
		return s
	end

	local function artSquare(parent, size, position, category, key, emoji, radius)
		local holderFrame = piece(parent, { Size = UDim2.fromOffset(size, size), Position = position, BackgroundColor3 = Color3.fromRGB(226, 208, 170), ZIndex = Z + 3 }, radius or 8)
		local glyph = text(holderFrame, { Size = UDim2.fromScale(1, 1), TextSize = math.max(14, size - 14), Text = emoji or "?" })
		if category then pcall(ArtIcon.apply, holderFrame, category, key, glyph, { cornerRadius = radius or 8, zIndex = Z + 6 }) end
		return holderFrame
	end

	local function clear(frame)
		for _, c in ipairs(frame:GetChildren()) do
			if c:IsA("GuiObject") then c:Destroy() end
		end
	end

	-- ===== pages =====
	local pageIndex = 1
	local counters = {} -- { label, target } rows the count-up animates
	local newRecords = {}
	local lastSeen -- stats snapshot for "newly beaten" stamps
	local expandedOrder

	-- heading on the first ruled line of its page
	local function heading(side, str)
		row(side, 1, 0, 1, { Text = str, Font = Enum.Font.Fondamento, TextSize = metrics().head }, 1.2)
	end

	-- label on the left, value on the right of one ruled line, dotted leader between them along the same line
	local function leader(side, i, name, value)
		local sz = metrics()
		local small = math.max(14, sz.body - 3) -- label and value share one short line, so they are a little smaller
		local n = row(side, i, 0, 1, { Text = name, TextSize = small })
		local v = row(side, i, 0, 1, { Text = value, TextXAlignment = Enum.TextXAlignment.Right, TextSize = small })
		local full = n.AbsoluteSize.X
		if full > 0 then
			local lo = (n.TextBounds.X + 8) / full
			local hi = 1 - (v.TextBounds.X + 8) / full
			if hi - lo > 0.08 then
				row(side, i, lo, hi, { Text = string.rep(". ", 40), TextColor3 = INK_DIM, Font = Enum.Font.Gotham, TextSize = math.max(14, sz.body - 4), TextTruncate = Enum.TextTruncate.None, ClipsDescendants = true })
			end
		end
	end

	local function counter(side, i, target)
		local sz = metrics()
		local l = row(side, i, 0, 1, { Font = Enum.Font.GothamBold, TextSize = sz.big, Text = fmt(target) }, 1.5)
		counters[#counters + 1] = { label = l, target = target }
		return l
	end

	local function emptyNote(side)
		local b = band(side, 4, 6)
		text(b, { Size = UDim2.fromScale(1, 1), Rotation = -3, Font = Enum.Font.Antique, TextSize = metrics().head, TextWrapped = true, Text = Pages.EMPTY_NOTE, TextColor3 = INK_DIM })
	end

	-- one ledger stat: its label on one ruled line, the inked number on the next
	local function inkStat(side, i, target, label)
		row(side, i, 0, 1, { Text = label, TextColor3 = INK_DIM })
		counter(side, i + 1, target)
	end

	local function storyLeft(stats)
		local s = Pages.story(stats)
		heading("left", "My Story")
		inkStat("left", 2, s.wins, "Runs won")
		inkStat("left", 4, s.runs, "Runs started")
		inkStat("left", 6, s.bestNight, "Best Night")
		-- win rate: an ink line and a small hand-drawn bar along the ninth ruled line
		local pct = math.floor(s.winRate * 100 + 0.5)
		row("left", 8, 0, 1, { Text = "Win rate" })
		row("left", 8, 0, 1, { Text = string.format("%d%%", pct), TextXAlignment = Enum.TextXAlignment.Right })
		local p = Layout.place("left", 9, 0, 1)
		local track = piece(leftPage, { Name = "WinRateBar", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(p.xs, p.xo, p.ys, p.yo - 2), Size = UDim2.new(p.ws, 0, 0, 10), Rotation = p.angle, BackgroundTransparency = 1, ZIndex = Z + 2 }, 3)
		stroke(track, INK, 1.5)
		if pct > 0 then piece(track, { Size = UDim2.new(s.winRate, 0, 1, 0), BackgroundColor3 = INK, BackgroundTransparency = 0.15, ZIndex = Z + 3 }, 3) end
	end

	local function storyRight(stats, state)
		local hall = Pages.hall(stats, nil)
		local sz = metrics()
		heading("right", "Regulars' Corner")
		local fav = hall.favorite
		local def = fav and Patrons.getById(fav.id)
		local t0 = 0
		if def then -- a small inked vignette with a soft paper-coloured edge, no frame, beside lines 2 to 4
			local size = math.floor(sz.spacing * 2.3)
			local p = Layout.place("right", 4, 0, 1)
			local vignette = piece(rightPage, { Name = "PatronVignette", AnchorPoint = Vector2.new(0, 1), Size = UDim2.fromOffset(size, size), Position = UDim2.new(p.xs, 0, p.ys, -4), BackgroundTransparency = 1, ZIndex = Z + 3 }, size // 2)
			local glyph = text(vignette, { Size = UDim2.fromScale(1, 1), TextSize = math.max(14, size - 24), Text = def.icon or "?" })
			pcall(ArtIcon.apply, vignette, "patrons", fav.id, glyph, { cornerRadius = size // 2, zIndex = Z + 6 })
			local edge = stroke(vignette, PAGE, 6)
			edge.Transparency = 0.2
			t0 = 0.36
		end
		row("right", 2, t0, 1, { Text = "Favorite Patron", TextColor3 = INK_DIM })
		row("right", 3, t0, 1, { Text = def and def.name or "None yet", Font = Enum.Font.Fondamento, TextSize = sz.head })
		row("right", 4, t0, 1, { Text = fav and string.format("Won %d run%s with it", fav.wins, fav.wins == 1 and "" or "s") or "Win a run to find your favorite.", TextColor3 = INK_DIM, TextSize = math.max(14, sz.body - 2) })
		local titleDef = state and state.equippedTitleId and Achievements.getById(state.equippedTitleId)
		row("right", 5, 0, 1, { Text = "Lifetime", Font = Enum.Font.Fondamento, TextSize = sz.head })
		for i, line in ipairs(Pages.lifeLines(stats, titleDef and titleDef.title or nil)) do leader("right", 5 + i, line.label, line.value) end
	end

	local function hallLeft(stats)
		heading("left", "Hall of Fame")
		local sz = metrics()
		local bests = Pages.bests(stats.recent, Pages.BESTS_SHOWN)
		for i, e in ipairs(bests) do
			local k = 2 + (i - 1) * 2 -- each note fills two ruled lines
			local b = band("left", k, k + 1)
			-- a note written onto the page: the page's own paper tone, a hairline edge and a faint shadow
			piece(b, { Name = "NoteShadow", Size = UDim2.new(1, -6, 1, -8), Position = UDim2.fromOffset(5, 6), BackgroundColor3 = Color3.fromRGB(70, 48, 28), BackgroundTransparency = 0.85, ZIndex = Z + 2 }, 4)
			local note = piece(b, { Name = "Note", Size = UDim2.new(1, -6, 1, -8), Position = UDim2.fromOffset(2, 3), BackgroundColor3 = Color3.fromRGB(240, 226, 192), ZIndex = Z + 2 }, 4)
			stroke(note, Color3.fromRGB(214, 194, 156), 1)
			piece(note, { Size = UDim2.fromOffset(8, 8), Position = UDim2.fromOffset(6, 5), BackgroundColor3 = BRASS, ZIndex = Z + 4 }, 4)
			local stakeDef = Stakes.get(e.stake)
			local stampSize = math.max(36, math.floor(sz.spacing * 2 - 22))
			text(note, { Size = UDim2.new(1, -(stampSize + 28), 0, sz.body + 4), Position = UDim2.fromOffset(20, 4), Text = string.format("Night %d", e.night), Font = Enum.Font.Antique, TextSize = sz.body + 2, TextXAlignment = Enum.TextXAlignment.Left })
			text(note, {
				Size = UDim2.new(1, -(stampSize + 28), 1, -(sz.body + 12)), Position = UDim2.fromOffset(20, sz.body + 8), TextSize = 14, Font = Enum.Font.GothamMedium, TextColor3 = INK_DIM, TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, TextTruncate = Enum.TextTruncate.AtEnd,
				Text = string.format("%s stake, score %s%s", stakeDef and stakeDef.name or "Regular", fmt(e.score), e.bestHand and (", " .. e.bestHand.name) or ""),
			})
			stamp(note, UDim2.new(1, -(stampSize + 4), 0.5, -stampSize // 2), e.won, stampSize)
		end
		if #bests == 0 then emptyNote("left") end
	end

	local function hallRight(stats)
		heading("right", "Best Night by stake")
		local sz = metrics()
		local n = 0
		for stake = 1, 8 do
			local best = stats.bestNightByStake and stats.bestNightByStake[tostring(stake)]
			if best then
				n = n + 1
				local def = Stakes.get(stake)
				local b = band("right", 1 + n, 1 + n)
				local ribbon = piece(b, { Size = UDim2.new(1, 0, 1, -6), Position = UDim2.fromOffset(0, 3), BackgroundColor3 = Color3.fromRGB(150, 36, 36), ZIndex = Z + 2 }, 4)
				local iconSize = math.max(20, math.floor(sz.spacing - 14))
				artSquare(ribbon, iconSize, UDim2.new(0, 4, 0.5, -iconSize // 2), "stakes", def.id, def.icon, iconSize // 2)
				text(ribbon, { Size = UDim2.new(1, -(iconSize + 70), 1, 0), Position = UDim2.fromOffset(iconSize + 10, 0), Text = def.name, TextColor3 = Color3.fromRGB(250, 236, 200), TextSize = sz.body - 2, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd })
				text(ribbon, { Size = UDim2.new(0, 64, 1, 0), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -6, 0, 0), Text = "Night " .. best, TextColor3 = Color3.fromRGB(250, 214, 140), TextSize = sz.body - 2, TextXAlignment = Enum.TextXAlignment.Right })
			end
		end
		if n == 0 then emptyNote("right") end
	end

	local function recordsLeft(stats)
		local rec = Pages.records(stats)
		heading("left", "Night reached, last runs")
		local sz = metrics()
		local bars = band("left", 2, 6)
		local slots = Pages.SPARK_SLOTS
		local maxH = math.max(24, math.floor(sz.spacing * 5 - 26))
		for i, b in ipairs(rec.bars) do
			local bh = math.max(8, math.floor(maxH * b.height))
			local bar = piece(bars, { AnchorPoint = Vector2.new(0, 1), Size = UDim2.new(1 / slots, -4, 0, bh), Position = UDim2.new((i - 1) / slots, 2, 1, -2), BackgroundColor3 = b.won and Color3.fromRGB(190, 140, 40) or Color3.fromRGB(140, 100, 70), ZIndex = Z + 3 }, 3)
			text(bar, { Size = UDim2.new(1, 0, 0, 16), Position = UDim2.fromOffset(0, -18), Text = tostring(b.night), TextSize = 14, TextColor3 = INK_DIM })
		end
		local cap = band("left", 7, 9)
		text(cap, { Size = UDim2.fromScale(1, 1), Text = "Gold bar = won, brown = lost. Oldest on the left.", Font = Enum.Font.GothamMedium, TextSize = 14, TextColor3 = INK_DIM, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top })
		if #rec.bars == 0 then emptyNote("left") end
	end

	local rebuildRight

	local function runRow(listParent, entry, order, stats)
		local sz = metrics()
		local rowH = math.max(44, math.floor(sz.spacing * 1.5))
		local open = expandedOrder == order
		local row0 = piece(listParent, { Name = "Run_" .. order, LayoutOrder = order, Size = UDim2.new(1, -8, 0, open and (rowH + 100) or rowH), BackgroundColor3 = open and Color3.fromRGB(232, 214, 172) or Color3.fromRGB(238, 222, 184), ClipsDescendants = true }, 6)
		stroke(row0, entry.won and BRASS or Color3.fromRGB(190, 170, 130), 1.5)
		local hit = Instance.new("TextButton")
		hit.Size = UDim2.new(1, 0, 0, rowH)
		hit.BackgroundTransparency = 1
		hit.Text = ""
		hit.ZIndex = Z + 8
		hit.Parent = row0
		hit.MouseButton1Click:Connect(function()
			deps.playClickSfx()
			expandedOrder = (expandedOrder == order) and nil or order
			rebuildRight(stats)
		end)
		local stakeDef = Stakes.get(entry.stake)
		local tag = text(row0, { Size = UDim2.fromOffset(44, 22), Position = UDim2.fromOffset(6, (rowH - 22) // 2), Text = entry.won and "Won" or "Lost", TextSize = 14, TextColor3 = Color3.fromRGB(250, 244, 226), BackgroundTransparency = 0, BackgroundColor3 = entry.won and Color3.fromRGB(70, 124, 66) or Color3.fromRGB(128, 86, 54) })
		deps.roundCorner(tag, 6)
		text(row0, { Size = UDim2.new(1, -86, 0, sz.body + 2), Position = UDim2.fromOffset(58, 4), Text = "Night " .. tostring(entry.night), TextXAlignment = Enum.TextXAlignment.Left, TextSize = sz.body })
		text(row0, { Size = UDim2.new(1, -86, 0, 16), Position = UDim2.fromOffset(58, rowH - 20), Text = (MODE_TAGS[entry.mode] or "Standard") .. ", score " .. fmt(entry.score), Font = Enum.Font.GothamMedium, TextColor3 = INK_DIM, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, TextSize = 14 })
		text(row0, { Size = UDim2.fromOffset(22, 22), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -4, 0, (rowH - 22) // 2), Text = open and "▲" or "▼", TextColor3 = INK_DIM, TextSize = 14 })
		if open then
			local names = {}
			for _, id in ipairs(entry.patrons or {}) do
				local def = Patrons.getById(id)
				names[#names + 1] = def and def.name or id
			end
			text(row0, { Size = UDim2.new(1, -20, 0, 36), Position = UDim2.fromOffset(10, rowH + 2), TextSize = 14, Font = Enum.Font.GothamMedium, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, Text = "Patrons: " .. (#names > 0 and table.concat(names, ", ") or "none") })
			text(row0, {
				Size = UDim2.new(1, -20, 0, 20), Position = UDim2.fromOffset(10, rowH + 40), TextSize = 14, Font = Enum.Font.GothamMedium, TextColor3 = INK_DIM, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
				Text = string.format("%s stake, %d hands%s", stakeDef and stakeDef.name or "Regular", entry.hands or 0, entry.bestHand and (", best " .. entry.bestHand.name .. " " .. fmt(entry.bestHand.score)) or ""),
			})
			if entry.seed then
				text(row0, { Size = UDim2.fromOffset(40, 22), Position = UDim2.fromOffset(10, rowH + 66), Text = "Seed", TextXAlignment = Enum.TextXAlignment.Left, TextSize = 14 })
				local seedBox = Instance.new("TextBox") -- read-only: select, then Ctrl+C (games cannot write the clipboard)
				seedBox.Size = UDim2.fromOffset(120, 24)
				seedBox.Position = UDim2.fromOffset(52, rowH + 65)
				seedBox.BackgroundColor3 = Color3.fromRGB(34, 48, 40)
				seedBox.BorderSizePixel = 0
				seedBox.Font = Enum.Font.GothamBold
				seedBox.TextSize = 14
				seedBox.TextColor3 = Color3.fromRGB(232, 190, 108)
				seedBox.ClearTextOnFocus = false
				seedBox.TextEditable = false
				seedBox.Text = entry.seed
				seedBox.ZIndex = Z + 9
				seedBox.Parent = row0
				deps.roundCorner(seedBox, 6)
			end
		end
	end

	local listHolder
	rebuildRight = function(stats)
		if not listHolder then return end
		clear(listHolder)
		local rec = Pages.records(stats)
		for i, e in ipairs(rec.rows) do runRow(listHolder, e, i, stats) end
	end

	local function recordsRight(stats)
		heading("right", "Run list")
		local b = band("right", 2, 9)
		local scroll = Instance.new("ScrollingFrame")
		scroll.Size = UDim2.fromScale(1, 1)
		scroll.BackgroundTransparency = 1
		scroll.BorderSizePixel = 0
		scroll.ScrollBarThickness = 6
		scroll.ScrollBarImageColor3 = BRASS
		scroll.ScrollBarImageTransparency = 0
		scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
		scroll.CanvasSize = UDim2.new()
		scroll.ZIndex = Z + 2
		scroll.Parent = b
		local layout = Instance.new("UIListLayout")
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Padding = UDim.new(0, 5)
		layout.Parent = scroll
		listHolder = scroll
		rebuildRight(stats)
		if #Pages.records(stats).rows == 0 then emptyNote("right") end
	end

	-- ===== page painting, tabs, turning =====
	local tabButtons = {}
	local function paintSide(side, state)
		local stats = state and state.runStats or {}
		local page = pageOf(side)
		clear(page)
		ruledLines(side)
		local kept = {}
		for _, c in ipairs(counters) do
			if c.label.Parent then kept[#kept + 1] = c end -- drop the counters of the page just cleared
		end
		counters = kept
		if side == "right" then listHolder = nil end
		if Pages.isEmpty(stats) then
			emptyNote(side)
			if side == "left" then heading("left", Pages.PAGES[pageIndex]) end
			return
		end
		if side == "left" then
			if pageIndex == 1 then storyLeft(stats) elseif pageIndex == 2 then hallLeft(stats) else recordsLeft(stats) end
		else
			if pageIndex == 1 then storyRight(stats, state) elseif pageIndex == 2 then hallRight(stats) else recordsRight(stats) end
		end
	end
	local function paint(state)
		paintSide("left", state)
		paintSide("right", state)
	end

	-- the open page's ribbon sticks out a little further and is brighter; the ribbons hang off the right edge of the book
	local T = Layout.TABS
	local function paintTabs()
		for i, b in ipairs(tabButtons) do
			local on = i == pageIndex
			b.BackgroundColor3 = on and Color3.fromRGB(150, 44, 44) or Color3.fromRGB(108, 34, 34)
			b.TextColor3 = on and Color3.fromRGB(255, 236, 190) or Color3.fromRGB(224, 196, 168)
			b.Size = UDim2.fromScale(T.w + (on and 0.012 or 0), T.h)
			b.Position = UDim2.fromScale(T.x, T.y + (i - 1) * T.step)
		end
	end

	-- A real page flip: a sheet cut from the SAME art as the pages (the page box of ledger_book_open, so colour, texture
	-- and ruled lines match exactly) squashes its width to 0 about the gutter over 0.22 s (Quad in), then the destination
	-- page's sheet grows from the gutter over 0.22 s (Quad out) with a soft shadow strip on its free edge. Forward turns go
	-- right to left, backward turns left to right. The sheet is tilted like the page and never leaves the page box.
	local FLIP_TIME = 0.44
	local flipToken = 0
	local activeSheet
	local function placeSheet(sheet, image, shadow, side, width)
		local box = Layout.pageBox(side)
		local gutterAnchor = side == "right" and 0 or 1 -- the sheet is hinged on the page edge nearest the gutter
		sheet.AnchorPoint = Vector2.new(gutterAnchor, 0)
		sheet.Position = UDim2.fromScale(gutterAnchor == 0 and box.x or (box.x + box.w), box.y)
		sheet.Size = UDim2.fromScale(width * box.w, box.h)
		sheet.Rotation = Layout.pageAngle(side)
		if image then
			-- the image is the whole book scaled so its page box fills the sheet; anchoring it on the hinge edge keeps the
			-- page art glued to the sheet while the sheet squashes
			image.Size = UDim2.fromScale(1 / box.w, 1 / box.h)
			image.AnchorPoint = Vector2.new(gutterAnchor == 0 and box.x or (box.x + box.w), box.y)
			image.Position = UDim2.fromScale(gutterAnchor, 0)
		end
		shadow.AnchorPoint = Vector2.new(1 - gutterAnchor, 0)
		shadow.Position = UDim2.fromScale(1 - gutterAnchor, 0)
	end
	local function buildSheet()
		local sheet = piece(book, { Name = "PageFlip", BackgroundColor3 = PAGE, BackgroundTransparency = bookArt and 1 or 0, ClipsDescendants = true, ZIndex = Z + 9, Active = false }, 4)
		local image = bookArt and artOver(sheet, "ledger_book_open", { ZIndex = Z + 10 }) or nil
		local shadow = piece(sheet, { Name = "FlipShadow", Size = UDim2.new(0, 22, 1, 0), BackgroundColor3 = Color3.fromRGB(40, 24, 10), BackgroundTransparency = 0.7, ZIndex = Z + 11 }, 8)
		return sheet, image, shadow
	end

	local function flip(forward, state)
		flipToken = flipToken + 1
		local token = flipToken
		local firstSide, secondSide = forward and "right" or "left", forward and "left" or "right"
		local sheet, image, shadow = buildSheet()
		placeSheet(sheet, image, shadow, firstSide, 1)
		activeSheet = sheet
		paintSide(firstSide, state) -- the new page under the departing sheet
		local half = FLIP_TIME / 2
		local box1 = Layout.pageBox(firstSide)
		TweenService:Create(sheet, TweenInfo.new(half, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Size = UDim2.fromScale(0, box1.h) }):Play()
		task.delay(half, function()
			if token ~= flipToken or not sheet.Parent then return end
			placeSheet(sheet, image, shadow, secondSide, 0) -- across the gutter: the sheet now grows over the other page
			local box2 = Layout.pageBox(secondSide)
			TweenService:Create(sheet, TweenInfo.new(half, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = UDim2.fromScale(box2.w, box2.h) }):Play()
			task.delay(half, function()
				if token ~= flipToken or not sheet.Parent then return end
				paintSide(secondSide, state) -- the sheet has landed; the new text fades in as it lifts
				TweenService:Create(sheet, TweenInfo.new(0.1), { BackgroundTransparency = 1 }):Play()
				if image then TweenService:Create(image, TweenInfo.new(0.1), { ImageTransparency = 1 }):Play() end
				TweenService:Create(shadow, TweenInfo.new(0.1), { BackgroundTransparency = 1 }):Play()
				task.delay(0.12, function()
					if activeSheet == sheet then activeSheet = nil end
					sheet:Destroy()
				end)
			end)
		end)
	end

	-- calm mode: paint now and fade a paper veil off the pages in 0.12 s
	local function crossfade(state)
		paint(state)
		local l, r = Layout.pageBox("left"), Layout.pageBox("right")
		local veil = piece(book, { Name = "PageVeil", Position = UDim2.fromScale(l.x, l.y), Size = UDim2.fromScale(r.x + r.w - l.x, l.h), BackgroundColor3 = PAGE, ZIndex = Z + 9, Active = false }, 6)
		TweenService:Create(veil, TweenInfo.new(0.12), { BackgroundTransparency = 1 }):Play()
		task.delay(0.14, function() veil:Destroy() end)
	end

	local function countUp()
		if calm() then return end
		local t0 = os.clock()
		for _, c in ipairs(counters) do c.label.Text = "0" end
		task.spawn(function()
			while os.clock() - t0 < 0.6 do
				for _, c in ipairs(counters) do
					if c.label.Parent then c.label.Text = fmt(Pages.countUp(c.target, (os.clock() - t0) / 0.6)) end
				end
				task.wait()
			end
			for _, c in ipairs(counters) do
				if c.label.Parent then c.label.Text = fmt(c.target) end
			end
		end)
	end

	local function stampIn(kinds)
		if #kinds == 0 or pageIndex ~= 1 then return end
		local mark = stamp(leftPage, UDim2.new(1, -84, 0, 8), true, 70)
		local s = Instance.new("UIScale")
		s.Parent = mark
		if calm() then return end
		s.Scale = 1.4
		TweenService:Create(s, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		local home = desk.Position
		task.delay(0.16, function() -- a small thud
			desk.Position = home + UDim2.fromOffset(0, 4)
			TweenService:Create(desk, TweenInfo.new(0.1), { Position = home }):Play()
		end)
	end

	local function go(i, animate)
		local previous = pageIndex
		pageIndex = i
		local state = deps.getLatestState and deps.getLatestState() or nil
		if activeSheet then -- a turn is still running: end it at once
			flipToken = flipToken + 1
			activeSheet:Destroy()
			activeSheet = nil
		end
		if animate then Cue.play("page_turn", calm() and 0.5 or 1) end -- starts with the flip; respects the SFX slider and Mute
		paintTabs()
		if animate and not calm() and i ~= previous then
			flip(i > previous, state)
		elseif animate and calm() then
			crossfade(state)
		else
			paint(state)
		end
	end

	for i, name in ipairs(Pages.PAGES) do
		local tab = Instance.new("TextButton")
		tab.Name = "Tab_" .. i
		tab.Font = Enum.Font.GothamBold
		tab.TextSize = 14
		tab.TextWrapped = true
		tab.Text = name
		tab.BorderSizePixel = 0
		tab.AutoButtonColor = true
		tab.ZIndex = Z + 3
		tab.Parent = book
		deps.roundCorner(tab, 6)
		tab.MouseButton1Click:Connect(function()
			if i == pageIndex then return end
			deps.playClickSfx()
			go(i, true)
		end)
		tabButtons[i] = tab
	end
	local api = {}

	-- Called every time the ledger opens (animate = true) and on state updates while open (animate = false).
	function api.refresh(animate)
		local state = deps.getLatestState and deps.getLatestState() or nil
		local stats = state and state.runStats
		if not stats then return end
		expandedOrder = animate and nil or expandedOrder
		paintTabs()
		paint(state)
		local beaten = Pages.beaten(lastSeen, stats)
		lastSeen = { wins = stats.wins, bestNight = stats.bestNight, bestHandScore = stats.bestHandScore }
		if animate then
			countUp()
			if #beaten > 0 then newRecords = beaten; task.delay(0.65, function() stampIn(newRecords) end) end
		end
	end

	-- Choose the spread without painting (refresh paints it).
	function api.setPage(i)
		pageIndex = math.max(1, math.min(#Pages.PAGES, i))
		paintTabs()
	end

	paintTabs()
	return api
end

return LedgerBook
