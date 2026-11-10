--[[
	Client/LedgerBook.lua
	The Tavern Ledger as an open leather book on a tavern desk (used by Client/StatsPanel.lua). Three spreads, picked
	with red silk bookmark tabs on the right edge:
	  Story         left: Runs won (big inked number on a wax seal), Runs started, Best Night as a chalk tally on a
	                chalkboard, win rate as an ink ring; right: favourite Patron in a photo frame and the lifetime lines
	  Hall of Fame  left: up to three best runs as pinned notes with a win or loss stamp; right: best Night per stake
	  Records       left: bars of the last runs; right: the run list (tap a row for details and the Seed code)
	Every piece is drawn from Frames first (desk, leather, cream pages, ribbons, seals, chalk) so it looks right with
	Engine/LedgerArt.lua empty; recorded ids are laid over the fallbacks piece by piece. Page turns are a 0.25 s shadow
	sweep; numbers count up when the ledger opens and a newly beaten record stamps in. "Reduce screen shake" skips every
	animation. Data mapping and layout maths live in Engine/LedgerPages.lua (tested).
	deps: roundCorner, playClickSfx, addTooltip, getLatestState
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local LedgerBook = {}

function LedgerBook.build(deps, desk)
	local Engine = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine")
	local Pages = require(Engine:WaitForChild("LedgerPages"))
	local LedgerArt = require(Engine:WaitForChild("LedgerArt"))
	local Stakes = require(Engine:WaitForChild("Stakes"))
	local Patrons = require(Engine:WaitForChild("Patrons"))
	local Achievements = require(Engine:WaitForChild("Achievements"))
	local ArtIcon = require(script.Parent.ArtIcon)
	local ClientSettings = require(script.Parent.ClientSettings)
	local Cue = require(script.Parent.Cue)

	local INK = Color3.fromRGB(52, 34, 20)
	local INK_DIM = Color3.fromRGB(104, 80, 56)
	local PAGE = Color3.fromRGB(244, 232, 204)
	local LEATHER = Color3.fromRGB(88, 52, 30)
	local BRASS = Color3.fromRGB(200, 160, 70)
	local RIBBON = Color3.fromRGB(150, 36, 36)
	local WIN_INK = Color3.fromRGB(176, 48, 40)
	local LOSS_INK = Color3.fromRGB(70, 96, 150)
	local CHALK = Color3.fromRGB(240, 236, 220)
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
	local book = piece(desk, { Name = "Book", Position = UDim2.fromScale(R.book.x, R.book.y), Size = UDim2.fromScale(R.book.w, R.book.h), BackgroundColor3 = LEATHER }, 10)
	local bookStroke = stroke(book, BRASS, 3)
	-- The painted open book is the page surface: its leather and pages show through, and the page frames below are
	-- transparent (text is written straight onto the paper). Without the art the drawn leather, cream pages and spine show.
	local bookArt = artOver(book, "ledger_book_open")
	local spine = piece(book, { Name = "Spine", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.02), Size = UDim2.new(0, 10, 0.96, 0), BackgroundColor3 = Color3.fromRGB(60, 36, 20), ZIndex = Z + 2 })
	if bookArt then
		book.BackgroundTransparency = 1
		bookStroke.Enabled = false
		spine.Visible = false
	end

	local function pageFrame(name, r)
		local p = piece(book, { Name = name, Position = UDim2.fromScale(r.x, r.y), Size = UDim2.fromScale(r.w, r.h), BackgroundColor3 = PAGE, ClipsDescendants = true, ZIndex = Z + 1 }, 6)
		if bookArt then
			p.BackgroundTransparency = 1
		else
			stroke(p, Color3.fromRGB(205, 186, 150), 1)
		end
		return p
	end
	local function ruledLines(page) -- faint ruled lines (the painted pages have their own)
		if bookArt then return end
		for i = 1, 9 do
			piece(page, { Position = UDim2.new(0.05, 0, 0.1 * i, 0), Size = UDim2.new(0.9, 0, 0, 1), BackgroundColor3 = Color3.fromRGB(222, 205, 172), ZIndex = Z + 1 })
		end
	end
	local leftPage = pageFrame("LeftPage", R.left)
	local rightPage = pageFrame("RightPage", R.right)
	artOver(deskTop, "ledger_coffee_ring", { Size = UDim2.fromOffset(90, 90), Position = UDim2.fromScale(0.01, 0.78), ImageTransparency = 0.5 })

	-- ===== small pieces =====
	local function seal(parent, pos, size, gold)
		local s = piece(parent, { Size = UDim2.fromOffset(size, size), Position = pos, BackgroundColor3 = gold and Color3.fromRGB(214, 170, 70) or Color3.fromRGB(168, 44, 44), ZIndex = Z + 2 }, size // 2)
		stroke(s, gold and Color3.fromRGB(150, 112, 36) or Color3.fromRGB(110, 24, 24), 3)
		text(s, { Size = UDim2.fromScale(1, 1), Text = gold and "👑" or "★", TextSize = math.max(14, size // 2), TextColor3 = gold and Color3.fromRGB(120, 84, 20) or Color3.fromRGB(250, 214, 200), ZIndex = Z + 4 })
		artOver(s, gold and "ledger_wax_seal_gold" or "ledger_wax_seal_red", { Size = UDim2.fromScale(1.2, 1.2), Position = UDim2.fromScale(-0.1, -0.1), ZIndex = Z + 3 })
		return s
	end

	local function stamp(parent, pos, won, size)
		local s = piece(parent, { Size = UDim2.fromOffset(size, size), Position = pos, BackgroundTransparency = 1, Rotation = won and -12 or 9, ZIndex = Z + 4 }, size // 2)
		local col = won and WIN_INK or LOSS_INK
		stroke(s, col, 4)
		text(s, { Size = UDim2.fromScale(1, 1), Text = won and "WON" or "LOST", TextSize = math.max(14, size // 4), TextColor3 = col, ZIndex = Z + 5 })
		artOver(s, won and "ledger_stamp_win" or "ledger_stamp_loss", { Size = UDim2.fromScale(1.1, 1.1), Position = UDim2.fromScale(-0.05, -0.05), ZIndex = Z + 6 })
		return s
	end

	local function leader(parent, y, name, value)
		local n = text(parent, { Size = UDim2.new(0.5, 0, 0, 22), Position = UDim2.new(0, 0, 0, y), Text = name, TextXAlignment = Enum.TextXAlignment.Left, TextSize = 16 })
		local v = text(parent, { Size = UDim2.new(0.4, 0, 0, 22), Position = UDim2.new(0.6, 0, 0, y), Text = value, TextXAlignment = Enum.TextXAlignment.Right, TextTruncate = Enum.TextTruncate.AtEnd, TextSize = 16 })
		-- dotted leader between the name and the value
		local left = n.TextBounds.X + 8
		local right = math.min(v.TextBounds.X, v.AbsoluteSize.X) + 8
		text(parent, { Size = UDim2.new(1, -(left + right), 0, 22), Position = UDim2.new(0, left, 0, y + 3), Text = string.rep(". ", 40), TextColor3 = INK_DIM, Font = Enum.Font.Gotham, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left, TextTransparency = 0.4, ClipsDescendants = true })
	end

	local function artSquare(parent, size, position, category, key, emoji, radius)
		local holder = piece(parent, { Size = UDim2.fromOffset(size, size), Position = position, BackgroundColor3 = Color3.fromRGB(226, 208, 170), ZIndex = Z + 3 }, radius or 8)
		local glyph = text(holder, { Size = UDim2.fromScale(1, 1), TextSize = math.max(14, size - 14), Text = emoji or "?" })
		if category then pcall(ArtIcon.apply, holder, category, key, glyph, { cornerRadius = radius or 8, zIndex = Z + 6 }) end
		return holder
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

	local function pad(page)
		local holder = Instance.new("Frame")
		holder.BackgroundTransparency = 1
		holder.Size = UDim2.new(1, -52, 1, -44)
		holder.Position = UDim2.fromOffset(26, 22)
		holder.ZIndex = Z + 2
		holder.Parent = page
		return holder
	end

	local function counter(parent, props, target)
		local l = text(parent, props)
		counters[#counters + 1] = { label = l, target = target }
		l.Text = fmt(target)
		return l
	end

	local function drawTally(parent, n)
		local t = Pages.tally(n)
		local board = piece(parent, { Size = UDim2.new(1, 0, 0, 120), BackgroundColor3 = Color3.fromRGB(34, 48, 40) }, 8)
		stroke(board, Color3.fromRGB(112, 76, 44), 5)
		artOver(board, "ledger_chalkboard", { Size = UDim2.fromScale(1.1, 1.1), Position = UDim2.fromScale(-0.05, -0.05) })
		if n <= 0 then
			text(board, { Size = UDim2.fromScale(1, 1), Text = "No Nights marked yet", TextColor3 = CHALK, TextSize = 16 })
			return board
		end
		local x, y = 14, 14
		local function stroke1(px, py) piece(board, { Position = UDim2.fromOffset(px, py), Size = UDim2.fromOffset(3, 30), BackgroundColor3 = CHALK, ZIndex = Z + 3 }) end
		for g = 1, t.fives + (t.loose > 0 and 1 or 0) do
			local count = g <= t.fives and 4 or t.loose
			for i = 0, count - 1 do stroke1(x + i * 9, y) end
			if g <= t.fives then
				local slash = piece(board, { Position = UDim2.fromOffset(x - 2, y + 13), Size = UDim2.fromOffset(44, 3), BackgroundColor3 = CHALK, Rotation = -22, ZIndex = Z + 4 })
				slash.AnchorPoint = Vector2.new(0, 0)
			end
			x = x + 56
			if x > 300 then x = 14; y = y + 40 end
		end
		if t.capped then text(board, { Size = UDim2.fromOffset(60, 22), AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -8, 1, -6), Text = "40+", TextColor3 = CHALK, TextXAlignment = Enum.TextXAlignment.Right }) end
		return board
	end

	local function drawRing(parent, pos, rate)
		local ring = Instance.new("Frame")
		ring.Size = UDim2.fromOffset(84, 84)
		ring.Position = pos
		ring.BackgroundTransparency = 1
		ring.ZIndex = Z + 2
		ring.Parent = parent
		local lit = math.floor(36 * rate + 0.5)
		for i = 1, 36 do
			local a = math.rad((i - 1) * 10 - 90)
			piece(ring, { Size = UDim2.fromOffset(5, 11), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(42 + math.cos(a) * 36, 42 + math.sin(a) * 36), Rotation = (i - 1) * 10, BackgroundColor3 = i <= lit and INK or Color3.fromRGB(214, 196, 160), ZIndex = Z + 3 })
		end
		text(ring, { Size = UDim2.fromScale(1, 1), Text = string.format("%d%%", math.floor(rate * 100 + 0.5)), TextSize = 18 })
	end

	local function emptyNote(page)
		local h = pad(page)
		text(h, {
			Size = UDim2.new(1, 0, 0, 90), Position = UDim2.fromScale(0, 0.35), Rotation = -3, Font = Enum.Font.Antique, TextSize = 26,
			TextWrapped = true, Text = Pages.EMPTY_NOTE, TextColor3 = INK_DIM,
		})
	end

	local function storyLeft(stats)
		local h = pad(leftPage)
		local s = Pages.story(stats)
		text(h, { Size = UDim2.new(1, 0, 0, 26), Text = "My Story", Font = Enum.Font.Antique, TextSize = 24, TextXAlignment = Enum.TextXAlignment.Left })
		seal(h, UDim2.fromOffset(0, 36), 78, true)
		counter(h, { Name = "WinsNumber", Size = UDim2.new(1, -96, 0, 50), Position = UDim2.fromOffset(92, 34), TextSize = 44, TextXAlignment = Enum.TextXAlignment.Left }, s.wins)
		text(h, { Size = UDim2.new(1, -96, 0, 22), Position = UDim2.fromOffset(92, 82), Text = "Runs won", TextColor3 = INK_DIM, TextXAlignment = Enum.TextXAlignment.Left })
		counter(h, { Size = UDim2.fromOffset(90, 34), Position = UDim2.fromOffset(0, 128), TextSize = 30, TextXAlignment = Enum.TextXAlignment.Left }, s.runs)
		text(h, { Size = UDim2.fromOffset(120, 22), Position = UDim2.fromOffset(0, 162), Text = "Runs started", TextColor3 = INK_DIM, TextXAlignment = Enum.TextXAlignment.Left })
		drawRing(h, UDim2.new(1, -90, 0, 120), s.winRate)
		text(h, { Size = UDim2.fromOffset(90, 22), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 206), Text = "Win rate", TextColor3 = INK_DIM, TextXAlignment = Enum.TextXAlignment.Right })
		local board = drawTally(h, s.bestNight)
		board.Position = UDim2.new(0, 0, 0, 196)
		board.Size = UDim2.new(1, -100, 0, 120)
		text(h, { Size = UDim2.new(1, -100, 0, 28), Position = UDim2.new(0, 0, 0, 322), TextSize = 20, TextXAlignment = Enum.TextXAlignment.Left, Text = "Best Night " .. tostring(s.bestNight) })
	end

	local function storyRight(stats, state)
		local h = pad(rightPage)
		local hall = Pages.hall(stats, nil)
		text(h, { Size = UDim2.new(1, 0, 0, 26), Text = "Regulars' Corner", Font = Enum.Font.Antique, TextSize = 24, TextXAlignment = Enum.TextXAlignment.Left })
		local frame = piece(h, { Size = UDim2.fromOffset(104, 104), Position = UDim2.fromOffset(0, 40), BackgroundColor3 = Color3.fromRGB(112, 76, 44), ZIndex = Z + 2 }, 8)
		stroke(frame, BRASS, 3)
		artOver(frame, "ledger_photo_frame", { Size = UDim2.fromScale(1.15, 1.15), Position = UDim2.fromScale(-0.075, -0.075), ZIndex = Z + 8 })
		local fav = hall.favorite
		local def = fav and Patrons.getById(fav.id)
		artSquare(frame, 80, UDim2.fromOffset(12, 12), fav and "patrons" or nil, fav and fav.id or nil, def and def.icon or "⭐", 6)
		text(h, { Size = UDim2.new(1, -120, 0, 24), Position = UDim2.fromOffset(116, 44), Text = "Favorite Patron", TextColor3 = INK_DIM, TextXAlignment = Enum.TextXAlignment.Left })
		text(h, { Size = UDim2.new(1, -120, 0, 30), Position = UDim2.fromOffset(116, 70), Text = def and def.name or "None yet", Font = Enum.Font.Antique, TextSize = 22, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd })
		text(h, {
			Size = UDim2.new(1, -120, 0, 40), Position = UDim2.fromOffset(116, 102), Font = Enum.Font.Antique, TextSize = 16, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
			Text = fav and string.format("Won %d run%s with it", fav.wins, fav.wins == 1 and "" or "s") or "Win a run to find your favorite.", TextColor3 = INK_DIM,
		})
		local titleDef = state and state.equippedTitleId and Achievements.getById(state.equippedTitleId)
		local lines = Pages.lifeLines(stats, titleDef and titleDef.title or nil)
		text(h, { Size = UDim2.new(1, 0, 0, 24), Position = UDim2.fromOffset(0, 168), Text = "Lifetime", Font = Enum.Font.Antique, TextSize = 22, TextXAlignment = Enum.TextXAlignment.Left })
		for i, line in ipairs(lines) do leader(h, 198 + (i - 1) * 34, line.label, line.value) end
	end

	local function hallLeft(stats)
		local h = pad(leftPage)
		text(h, { Size = UDim2.new(1, 0, 0, 26), Text = "Hall of Fame", Font = Enum.Font.Antique, TextSize = 24, TextXAlignment = Enum.TextXAlignment.Left })
		local bests = Pages.bests(stats.recent, Pages.BESTS_SHOWN)
		for i, e in ipairs(bests) do
			local y = 40 + (i - 1) * 104
			-- a note written onto the page: the page's own paper tone, a hairline edge and a faint shadow, no tilt
			piece(h, { Name = "NoteShadow", Size = UDim2.new(1, -20, 0, 92), Position = UDim2.fromOffset(8, y + 3), BackgroundColor3 = Color3.fromRGB(70, 48, 28), BackgroundTransparency = 0.85, ZIndex = Z + 2 }, 4)
			local note = piece(h, { Name = "Note", Size = UDim2.new(1, -20, 0, 92), Position = UDim2.fromOffset(6, y), BackgroundColor3 = Color3.fromRGB(240, 226, 192), ZIndex = Z + 2 }, 4)
			stroke(note, Color3.fromRGB(214, 194, 156), 1)
			piece(note, { Size = UDim2.fromOffset(10, 10), Position = UDim2.fromOffset(8, 6), BackgroundColor3 = BRASS, ZIndex = Z + 4 }, 5)
			local stakeDef = Stakes.get(e.stake)
			text(note, { Size = UDim2.new(1, -110, 0, 26), Position = UDim2.fromOffset(24, 8), Text = string.format("Night %d", e.night), Font = Enum.Font.Antique, TextSize = 22, TextXAlignment = Enum.TextXAlignment.Left })
			text(note, {
				Size = UDim2.new(1, -110, 0, 44), Position = UDim2.fromOffset(24, 36), TextSize = 15, Font = Enum.Font.GothamMedium, TextColor3 = INK_DIM, TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
				Text = string.format("%s stake, score %s%s", stakeDef and stakeDef.name or "Regular", fmt(e.score), e.bestHand and (", best hand " .. e.bestHand.name) or ""),
			})
			stamp(note, UDim2.new(1, -84, 0, 8), e.won, 74)
		end
		if #bests == 0 then emptyNote(leftPage) end
	end

	local function hallRight(stats)
		local h = pad(rightPage)
		text(h, { Size = UDim2.new(1, 0, 0, 26), Text = "Best Night by stake", Font = Enum.Font.Antique, TextSize = 24, TextXAlignment = Enum.TextXAlignment.Left })
		local y, n = 42, 0
		for stake = 1, 8 do
			local best = stats.bestNightByStake and stats.bestNightByStake[tostring(stake)]
			if best then
				local def = Stakes.get(stake)
				local ribbon = piece(h, { Size = UDim2.new(1, 0, 0, 36), Position = UDim2.fromOffset(0, y), BackgroundColor3 = Color3.fromRGB(150, 36, 36), ZIndex = Z + 2 }, 4)
				artSquare(ribbon, 28, UDim2.fromOffset(6, 4), "stakes", def.id, def.icon, 14)
				text(ribbon, { Size = UDim2.new(1, -110, 1, 0), Position = UDim2.fromOffset(42, 0), Text = def.name, TextColor3 = Color3.fromRGB(250, 236, 200), TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd })
				text(ribbon, { Size = UDim2.fromOffset(90, 36), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 0), Text = "Night " .. best, TextColor3 = Color3.fromRGB(250, 214, 140), TextXAlignment = Enum.TextXAlignment.Right })
				y = y + 42
				n = n + 1
			end
		end
		if n == 0 then emptyNote(rightPage) end
	end

	local function recordsLeft(stats)
		local h = pad(leftPage)
		local rec = Pages.records(stats)
		text(h, { Size = UDim2.new(1, 0, 0, 26), Text = "Night reached, last runs", Font = Enum.Font.Antique, TextSize = 22, TextXAlignment = Enum.TextXAlignment.Left })
		local bars = piece(h, { Position = UDim2.fromOffset(0, 70), Size = UDim2.new(1, 0, 0, 180), BackgroundTransparency = 1, ZIndex = Z + 2 })
		local slots = Pages.SPARK_SLOTS
		for i, b in ipairs(rec.bars) do
			local bh = math.max(8, math.floor(150 * b.height))
			local bar = piece(bars, { AnchorPoint = Vector2.new(0, 1), Size = UDim2.new(1 / slots, -4, 0, bh), Position = UDim2.new((i - 1) / slots, 2, 1, 0), BackgroundColor3 = b.won and Color3.fromRGB(190, 140, 40) or Color3.fromRGB(140, 100, 70), ZIndex = Z + 3 }, 3)
			text(bar, { Size = UDim2.new(1, 0, 0, 16), Position = UDim2.fromOffset(0, -18), Text = tostring(b.night), TextSize = 14, TextColor3 = INK_DIM })
		end
		text(h, { Size = UDim2.new(1, 0, 0, 40), Position = UDim2.fromOffset(0, 262), Text = "Gold bar = won, brown = lost. Oldest on the left.", Font = Enum.Font.GothamMedium, TextColor3 = INK_DIM, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top })
		if #rec.bars == 0 then emptyNote(leftPage) end
	end

	local rebuildRight

	local function runRow(listParent, entry, order, stats)
		local open = expandedOrder == order
		local row = piece(listParent, { Name = "Run_" .. order, LayoutOrder = order, Size = UDim2.new(1, -8, 0, open and 150 or 54), BackgroundColor3 = open and Color3.fromRGB(232, 214, 172) or Color3.fromRGB(238, 222, 184), ClipsDescendants = true }, 6)
		stroke(row, entry.won and BRASS or Color3.fromRGB(190, 170, 130), 1.5)
		local hit = Instance.new("TextButton")
		hit.Size = UDim2.new(1, 0, 0, 54)
		hit.BackgroundTransparency = 1
		hit.Text = ""
		hit.ZIndex = Z + 8
		hit.Parent = row
		hit.MouseButton1Click:Connect(function()
			deps.playClickSfx()
			expandedOrder = (expandedOrder == order) and nil or order
			rebuildRight(stats)
		end)
		local stakeDef = Stakes.get(entry.stake)
		local tag = text(row, { Size = UDim2.fromOffset(56, 24), Position = UDim2.fromOffset(8, 15), Text = entry.won and "Won" or "Lost", TextColor3 = Color3.fromRGB(250, 244, 226), BackgroundTransparency = 0, BackgroundColor3 = entry.won and Color3.fromRGB(70, 124, 66) or Color3.fromRGB(128, 86, 54) })
		deps.roundCorner(tag, 6)
		text(row, { Size = UDim2.fromOffset(120, 22), Position = UDim2.fromOffset(72, 6), Text = "Night " .. tostring(entry.night), TextXAlignment = Enum.TextXAlignment.Left, TextSize = 17 })
		text(row, { Size = UDim2.fromOffset(120, 20), Position = UDim2.fromOffset(72, 28), Text = MODE_TAGS[entry.mode] or "Standard", Font = Enum.Font.GothamMedium, TextColor3 = INK_DIM, TextXAlignment = Enum.TextXAlignment.Left, TextSize = 14 })
		text(row, { Size = UDim2.new(1, -250, 0, 24), Position = UDim2.fromOffset(190, 15), Text = "Score " .. fmt(entry.score), TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd })
		text(row, { Size = UDim2.fromOffset(24, 24), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -6, 0, 15), Text = open and "▲" or "▼", TextColor3 = INK_DIM })
		if open then
			local names = {}
			for _, id in ipairs(entry.patrons or {}) do
				local def = Patrons.getById(id)
				names[#names + 1] = def and def.name or id
			end
			text(row, { Size = UDim2.new(1, -20, 0, 40), Position = UDim2.fromOffset(10, 56), TextSize = 15, Font = Enum.Font.GothamMedium, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, Text = "Patrons: " .. (#names > 0 and table.concat(names, ", ") or "none") })
			text(row, {
				Size = UDim2.new(1, -20, 0, 22), Position = UDim2.fromOffset(10, 96), TextSize = 15, Font = Enum.Font.GothamMedium, TextColor3 = INK_DIM, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
				Text = string.format("%s stake, %d hands%s", stakeDef and stakeDef.name or "Regular", entry.hands or 0, entry.bestHand and (", best hand " .. entry.bestHand.name .. " for " .. fmt(entry.bestHand.score)) or ""),
			})
			if entry.seed then
				text(row, { Size = UDim2.fromOffset(46, 22), Position = UDim2.fromOffset(10, 122), Text = "Seed", TextXAlignment = Enum.TextXAlignment.Left })
				local seedBox = Instance.new("TextBox") -- read-only: select, then Ctrl+C (games cannot write the clipboard)
				seedBox.Size = UDim2.fromOffset(170, 24)
				seedBox.Position = UDim2.fromOffset(58, 121)
				seedBox.BackgroundColor3 = Color3.fromRGB(34, 48, 40)
				seedBox.BorderSizePixel = 0
				seedBox.Font = Enum.Font.GothamBold
				seedBox.TextSize = 16
				seedBox.TextColor3 = Color3.fromRGB(232, 190, 108)
				seedBox.ClearTextOnFocus = false
				seedBox.TextEditable = false
				seedBox.Text = entry.seed
				seedBox.ZIndex = Z + 9
				seedBox.Parent = row
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
		local h = pad(rightPage)
		text(h, { Size = UDim2.new(1, 0, 0, 26), Text = "Run list", Font = Enum.Font.Antique, TextSize = 24, TextXAlignment = Enum.TextXAlignment.Left })
		local scroll = Instance.new("ScrollingFrame")
		scroll.Position = UDim2.fromOffset(0, 36)
		scroll.Size = UDim2.new(1, 0, 1, -36)
		scroll.BackgroundTransparency = 1
		scroll.BorderSizePixel = 0
		scroll.ScrollBarThickness = 8
		scroll.ScrollBarImageColor3 = BRASS
		scroll.ScrollBarImageTransparency = 0
		scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
		scroll.CanvasSize = UDim2.new()
		scroll.ZIndex = Z + 2
		scroll.Parent = h
		local layout = Instance.new("UIListLayout")
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Padding = UDim.new(0, 6)
		layout.Parent = scroll
		listHolder = scroll
		rebuildRight(stats)
		if #Pages.records(stats).rows == 0 then emptyNote(rightPage) end
	end

	-- ===== page painting, tabs, turning =====
	local tabButtons = {}
	local function paint(state)
		local stats = state and state.runStats or {}
		clear(leftPage)
		clear(rightPage)
		ruledLines(leftPage)
		ruledLines(rightPage)
		counters = {}
		listHolder = nil
		if Pages.isEmpty(stats) then
			emptyNote(leftPage)
			emptyNote(rightPage)
			text(leftPage, { Size = UDim2.new(1, -28, 0, 26), Position = UDim2.fromOffset(14, 12), Text = Pages.PAGES[pageIndex], Font = Enum.Font.Antique, TextSize = 24, TextXAlignment = Enum.TextXAlignment.Left })
			return
		end
		if pageIndex == 1 then storyLeft(stats); storyRight(stats, state)
		elseif pageIndex == 2 then hallLeft(stats); hallRight(stats)
		else recordsLeft(stats); recordsRight(stats) end
	end

	-- the open page's ribbon sticks out a little further to the left and is brighter
	local function paintTabs()
		for i, b in ipairs(tabButtons) do
			local on = i == pageIndex
			b.BackgroundColor3 = on and Color3.fromRGB(150, 44, 44) or Color3.fromRGB(108, 34, 34)
			b.TextColor3 = on and Color3.fromRGB(255, 236, 190) or Color3.fromRGB(224, 196, 168)
			b.Size = UDim2.fromScale(R.tabs.w + (on and 0.008 or 0), 0.105)
			b.Position = UDim2.fromScale(R.tabs.x - (on and 0.008 or 0), R.tabs.y + (i - 1) * 0.125)
		end
	end

	local function sweep()
		local shade = piece(book, { Name = "PageSweep", Size = UDim2.fromScale(0.14, 0.92), Position = UDim2.fromScale(0.03, 0.04), BackgroundColor3 = Color3.fromRGB(0, 0, 0), BackgroundTransparency = 1, ZIndex = Z + 9, Active = false })
		TweenService:Create(shade, TweenInfo.new(0.125), { BackgroundTransparency = 0.6, Position = UDim2.fromScale(0.42, 0.04) }):Play()
		task.delay(0.125, function()
			TweenService:Create(shade, TweenInfo.new(0.125), { BackgroundTransparency = 1, Position = UDim2.fromScale(0.83, 0.04) }):Play()
			task.delay(0.13, function() shade:Destroy() end)
		end)
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
		local mark = stamp(leftPage, UDim2.new(1, -110, 0, 128), true, 90)
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
		pageIndex = i
		if animate then Cue.play("page_turn") end -- respects the SFX slider and Mute, and plays in calm mode too
		paintTabs()
		if animate and not calm() then sweep() end
		local state = deps.getLatestState and deps.getLatestState() or nil
		local delay = (animate and not calm()) and 0.125 or 0
		task.delay(delay, function() paint(state) end)
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
		tab.Parent = desk
		tab.Size = UDim2.fromScale(R.tabs.w, 0.105)
		tab.Position = UDim2.fromScale(R.tabs.x, R.tabs.y + (i - 1) * 0.125)
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
