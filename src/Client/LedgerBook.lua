--[[
	Client/LedgerBook.lua
	The Tavern Ledger as an open leather book on a tavern desk (used by Client/StatsPanel.lua). Three spreads, picked
	with red silk bookmark tabs on the right edge:
	  Story         left: Runs won (big inked number on a wax seal), Runs started, Best Night as a chalk tally on a
	                chalkboard, win rate as an ink ring; right: favourite Patron in a photo frame and the lifetime lines
	  Hall of Fame  left: up to three best runs as pinned notes with a win or loss stamp; right: best Night per stake
	  Records       left: bars of the last runs; right: the run list (tap a row for details and the Seed code)
	Every piece is drawn from Frames first (desk, leather, cream pages, ribbons, ink) so it looks right with
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
	-- the scene darkens a little behind the book so the pages are the brightest thing, and the book rests on the table
	piece(desk, { Name = "DeskDim", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(0, 0, 0), BackgroundTransparency = 0.7, Active = false }, 14)
	piece(desk, { Name = "ContactShadow", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(R.book.x + R.book.w / 2, R.table.y + 0.004), Size = UDim2.fromScale(R.book.w * 1.01, 0.03), BackgroundColor3 = Color3.fromRGB(0, 0, 0), BackgroundTransparency = 0.55, Active = false }, 40)
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

	-- ===== small pieces =====
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

	-- All ink sits inside Pages.inkRect: 7 percent side margins (a little more on the spine side), 8 percent top and bottom.
	local function pad(page)
		local side = (page == leftPage) and "left" or "right"
		local L = R
		local m, my, sp = L.margin, L.marginY, L.spine
		local holder = Instance.new("Frame")
		holder.Name = "Ink"
		holder.BackgroundTransparency = 1
		holder.Size = UDim2.fromScale(1 - 2 * m - sp, 1 - 2 * my)
		holder.Position = UDim2.fromScale(side == "left" and m or (m + sp), my)
		holder.ZIndex = Z + 2
		holder.Parent = page
		return holder
	end

	-- A calligraphic heading on the top margin with a thin hand-drawn underline rule.
	local function heading(h, str)
		text(h, { Size = UDim2.new(1, 0, 0, 30), Text = str, Font = Enum.Font.Fondamento, TextSize = 26, TextColor3 = INK, TextXAlignment = Enum.TextXAlignment.Left })
		piece(h, { Name = "HeadingRule", Position = UDim2.fromOffset(0, 33), Size = UDim2.new(1, 0, 0, 2), BackgroundColor3 = INK_DIM, BackgroundTransparency = 0.25, ZIndex = Z + 2 })
		piece(h, { Name = "HeadingRuleTail", Position = UDim2.fromOffset(0, 36), Size = UDim2.new(0.55, 0, 0, 1), BackgroundColor3 = INK_DIM, BackgroundTransparency = 0.55, ZIndex = Z + 2 })
	end

	-- dotted ledger rule across the ink area
	local function dots(parent, y)
		text(parent, { Size = UDim2.new(1, 0, 0, 16), Position = UDim2.fromOffset(0, y), Text = string.rep(". ", 60), TextColor3 = INK_DIM, Font = Enum.Font.Gotham, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left, TextTransparency = 0.45, ClipsDescendants = true })
	end

	local function counter(parent, props, target)
		local l = text(parent, props)
		counters[#counters + 1] = { label = l, target = target }
		l.Text = fmt(target)
		return l
	end

	local function emptyNote(page)
		local h = pad(page)
		text(h, {
			Size = UDim2.new(1, 0, 0, 90), Position = UDim2.fromScale(0, 0.35), Rotation = -3, Font = Enum.Font.Antique, TextSize = 26,
			TextWrapped = true, Text = Pages.EMPTY_NOTE, TextColor3 = INK_DIM,
		})
	end

	-- one ledger stat: big number in dark brown ink, its label beneath, a dotted rule under both
	local function inkStat(h, y, target, label)
		counter(h, { Size = UDim2.new(1, 0, 0, 44), Position = UDim2.fromOffset(0, y), TextSize = 40, TextXAlignment = Enum.TextXAlignment.Left }, target)
		text(h, { Size = UDim2.new(1, 0, 0, 20), Position = UDim2.fromOffset(0, y + 44), Text = label, TextColor3 = INK_DIM, Font = Enum.Font.GothamMedium, TextSize = 16, TextXAlignment = Enum.TextXAlignment.Left })
		dots(h, y + 62)
	end

	local function storyLeft(stats)
		local h = pad(leftPage)
		local s = Pages.story(stats)
		heading(h, "My Story")
		inkStat(h, 46, s.wins, "Runs won")
		inkStat(h, 128, s.runs, "Runs started")
		inkStat(h, 210, s.bestNight, "Best Night")
		-- win rate: an ink line and a small hand-drawn bar
		local pct = math.floor(s.winRate * 100 + 0.5)
		text(h, { Size = UDim2.new(0.6, 0, 0, 24), Position = UDim2.fromOffset(0, 292), Text = "Win rate", TextXAlignment = Enum.TextXAlignment.Left })
		text(h, { Size = UDim2.new(0.4, 0, 0, 24), Position = UDim2.new(0.6, 0, 0, 292), Text = string.format("%d%%", pct), TextXAlignment = Enum.TextXAlignment.Right })
		local track = piece(h, { Name = "WinRateBar", Position = UDim2.fromOffset(0, 320), Size = UDim2.new(1, 0, 0, 10), BackgroundTransparency = 1, ZIndex = Z + 2 }, 3)
		stroke(track, INK_DIM, 1.5)
		if pct > 0 then piece(track, { Size = UDim2.new(s.winRate, 0, 1, 0), BackgroundColor3 = INK, BackgroundTransparency = 0.15, ZIndex = Z + 3 }, 3) end
	end

	local function storyRight(stats, state)
		local h = pad(rightPage)
		local hall = Pages.hall(stats, nil)
		heading(h, "Regulars' Corner")
		local fav = hall.favorite
		local def = fav and Patrons.getById(fav.id)
		local textX = 0
		if def then -- a small inked vignette with a soft paper-coloured edge, no frame
			local vignette = piece(h, { Name = "PatronVignette", Size = UDim2.fromOffset(84, 84), Position = UDim2.fromOffset(0, 48), BackgroundTransparency = 1, ZIndex = Z + 3 }, 42)
			local glyph = text(vignette, { Size = UDim2.fromScale(1, 1), TextSize = 44, Text = def.icon or "?" })
			pcall(ArtIcon.apply, vignette, "patrons", fav.id, glyph, { cornerRadius = 42, zIndex = Z + 6 })
			local edge = stroke(vignette, PAGE, 8)
			edge.Transparency = 0.2
			textX = 100
		end
		text(h, { Size = UDim2.new(1, -textX, 0, 22), Position = UDim2.fromOffset(textX, 48), Text = "Favorite Patron", TextColor3 = INK_DIM, Font = Enum.Font.GothamMedium, TextSize = 16, TextXAlignment = Enum.TextXAlignment.Left })
		text(h, { Size = UDim2.new(1, -textX, 0, 30), Position = UDim2.fromOffset(textX, 70), Text = def and def.name or "None yet", Font = Enum.Font.Fondamento, TextSize = 22, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd })
		text(h, {
			Size = UDim2.new(1, -textX, 0, 40), Position = UDim2.fromOffset(textX, 102), Font = Enum.Font.GothamMedium, TextSize = 15, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
			Text = fav and string.format("Won %d run%s with it", fav.wins, fav.wins == 1 and "" or "s") or "Win a run to find your favorite.", TextColor3 = INK_DIM,
		})
		local titleDef = state and state.equippedTitleId and Achievements.getById(state.equippedTitleId)
		local lines = Pages.lifeLines(stats, titleDef and titleDef.title or nil)
		text(h, { Size = UDim2.new(1, 0, 0, 26), Position = UDim2.fromOffset(0, 160), Text = "Lifetime", Font = Enum.Font.Fondamento, TextSize = 22, TextXAlignment = Enum.TextXAlignment.Left })
		for i, line in ipairs(lines) do leader(h, 194 + (i - 1) * 34, line.label, line.value) end
	end

	local function hallLeft(stats)
		local h = pad(leftPage)
		heading(h, "Hall of Fame")
		local bests = Pages.bests(stats.recent, Pages.BESTS_SHOWN)
		for i, e in ipairs(bests) do
			local y = 48 + (i - 1) * 104
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
		heading(h, "Best Night by stake")
		local y, n = 50, 0
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
		heading(h, "Night reached, last runs")
		local bars = piece(h, { Position = UDim2.fromOffset(0, 90), Size = UDim2.new(1, 0, 0, 180), BackgroundTransparency = 1, ZIndex = Z + 2 })
		local slots = Pages.SPARK_SLOTS
		for i, b in ipairs(rec.bars) do
			local bh = math.max(8, math.floor(150 * b.height))
			local bar = piece(bars, { AnchorPoint = Vector2.new(0, 1), Size = UDim2.new(1 / slots, -4, 0, bh), Position = UDim2.new((i - 1) / slots, 2, 1, 0), BackgroundColor3 = b.won and Color3.fromRGB(190, 140, 40) or Color3.fromRGB(140, 100, 70), ZIndex = Z + 3 }, 3)
			text(bar, { Size = UDim2.new(1, 0, 0, 16), Position = UDim2.fromOffset(0, -18), Text = tostring(b.night), TextSize = 14, TextColor3 = INK_DIM })
		end
		text(h, { Size = UDim2.new(1, 0, 0, 40), Position = UDim2.fromOffset(0, 282), Text = "Gold bar = won, brown = lost. Oldest on the left.", Font = Enum.Font.GothamMedium, TextColor3 = INK_DIM, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top })
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
		heading(h, "Run list")
		local scroll = Instance.new("ScrollingFrame")
		scroll.Position = UDim2.fromOffset(0, 48)
		scroll.Size = UDim2.new(1, 0, 1, -48)
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
	local function paintSide(side, state)
		local stats = state and state.runStats or {}
		local page = side == "left" and leftPage or rightPage
		clear(page)
		ruledLines(page)
		local kept = {}
		for _, c in ipairs(counters) do
			if c.label.Parent then kept[#kept + 1] = c end -- drop the counters of the page just cleared
		end
		counters = kept
		if side == "right" then listHolder = nil end
		if Pages.isEmpty(stats) then
			emptyNote(page)
			if side == "left" then heading(pad(page), Pages.PAGES[pageIndex]) end
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

	-- A real page flip: a paper sheet anchored at the spine squashes its width from full to 0 on one side, then grows on the
	-- other (Quad easing, FLIP_TIME in total) with a soft moving shadow on its free edge and a brighter fold at the spine.
	-- Forward turns go right to left, backward turns left to right. Each page's new content is painted while the sheet
	-- covers it, so it appears as the sheet passes.
	local FLIP_TIME = 0.4
	local flipToken = 0
	local activeSheet
	local function buildSheet(startAnchor)
		local W = 0.47
		local sheet = piece(book, {
			Name = "PageFlip", AnchorPoint = Vector2.new(startAnchor, 0), Position = UDim2.fromScale(0.5, R.right.y), Size = UDim2.fromScale(W, R.right.h),
			BackgroundColor3 = PAGE, ZIndex = Z + 9, Active = false,
		}, 4)
		stroke(sheet, Color3.fromRGB(205, 186, 150), 1)
		for i = 1, 8 do -- faint ruled lines
			piece(sheet, { Position = UDim2.new(0.07, 0, 0.1 * i, 0), Size = UDim2.new(0.86, 0, 0, 1), BackgroundColor3 = Color3.fromRGB(222, 205, 172), ZIndex = Z + 10 })
		end
		piece(sheet, { Name = "Fold", AnchorPoint = Vector2.new(startAnchor, 0), Position = UDim2.fromScale(startAnchor, 0), Size = UDim2.fromScale(0.07, 1), BackgroundColor3 = Color3.fromRGB(255, 250, 235), BackgroundTransparency = 0.45, ZIndex = Z + 10 })
		local shadow = piece(sheet, { Name = "FlipShadow", AnchorPoint = Vector2.new(1 - startAnchor, 0), Position = UDim2.fromScale(1 - startAnchor, 0), Size = UDim2.new(0, 28, 1, 0), BackgroundColor3 = Color3.fromRGB(40, 24, 10), BackgroundTransparency = 0.72, ZIndex = Z + 8 }, 10)
		return sheet, shadow, W
	end

	local function flip(forward, state)
		flipToken = flipToken + 1
		local token = flipToken
		local startAnchor = forward and 0 or 1
		local firstSide, secondSide = forward and "right" or "left", forward and "left" or "right"
		local sheet, shadow, W = buildSheet(startAnchor)
		activeSheet = sheet
		paintSide(firstSide, state) -- hidden under the sheet
		local half = FLIP_TIME / 2
		TweenService:Create(sheet, TweenInfo.new(half, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Size = UDim2.fromScale(0, R.right.h) }):Play()
		task.delay(half, function()
			if token ~= flipToken or not sheet.Parent then return end
			local a = 1 - startAnchor -- cross the spine: the sheet now grows from it over the other page
			sheet.AnchorPoint = Vector2.new(a, 0)
			shadow.AnchorPoint = Vector2.new(1 - a, 0)
			shadow.Position = UDim2.fromScale(1 - a, 0)
			local fold = sheet:FindFirstChild("Fold")
			if fold then fold.AnchorPoint = Vector2.new(a, 0); fold.Position = UDim2.fromScale(a, 0) end
			TweenService:Create(sheet, TweenInfo.new(half, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = UDim2.fromScale(W, R.right.h) }):Play()
			task.delay(half, function()
				if token ~= flipToken or not sheet.Parent then return end
				paintSide(secondSide, state) -- the sheet has landed on it; the new page shows as the sheet fades
				TweenService:Create(sheet, TweenInfo.new(0.08), { BackgroundTransparency = 1 }):Play()
				for _, c in ipairs(sheet:GetDescendants()) do
					if c:IsA("Frame") then TweenService:Create(c, TweenInfo.new(0.08), { BackgroundTransparency = 1 }):Play() end
				end
				task.delay(0.1, function()
					if activeSheet == sheet then activeSheet = nil end
					sheet:Destroy()
				end)
			end)
		end)
	end

	-- calm mode: paint now and fade a paper veil off the pages in 0.12 s
	local function crossfade(state)
		paint(state)
		local veil = piece(book, { Name = "PageVeil", Position = UDim2.fromScale(R.left.x, R.left.y), Size = UDim2.fromScale(R.right.x + R.right.w - R.left.x, R.left.h), BackgroundColor3 = PAGE, ZIndex = Z + 9, Active = false }, 6)
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
		local mark = stamp(leftPage, UDim2.new(1, -120, 0, 60), true, 90)
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
