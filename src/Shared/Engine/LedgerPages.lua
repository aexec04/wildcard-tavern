--[[
	Engine/LedgerPages.lua
	Pure data mapping for the Tavern Ledger book (Client/LedgerBook.lua): stats from Engine/RunHistory.view become the
	content of three pages. No Roblox APIs, so it is unit tested.

	  Story        runs won (big inked number with a wax seal), runs started, best Night as a chalk tally, win rate ring
	  Hall of Fame favourite Patron, up to three best runs as stamped notes, lifetime ledger lines
	  Records      the sparkline of the last runs and the run list (newest first, ten shown)
]]

local LedgerPages = {}

LedgerPages.PAGES = { "Story", "Hall of Fame", "Records" }
LedgerPages.EMPTY_NOTE = "Nothing written yet. Go lose gracefully."
LedgerPages.RUNS_SHOWN = 10
LedgerPages.SPARK_SLOTS = 20
LedgerPages.BESTS_SHOWN = 3
LedgerPages.TALLY_MAX = 40 -- a chalkboard holds this many marks, then it shows "40+"

local function whole(n)
	n = tonumber(n) or 0
	return math.max(0, math.floor(n))
end

function LedgerPages.fmt(n)
	n = whole(n)
	if n >= 1e9 then return string.format("%.1fB", n / 1e9) end
	if n >= 1e6 then return string.format("%.1fM", n / 1e6) end
	if n >= 1e4 then return string.format("%.1fK", n / 1e3) end
	return tostring(n)
end

-- True when nothing has been written yet (no finished run).
function LedgerPages.isEmpty(stats)
	return stats == nil or (whole(stats.runs) == 0 and #(stats.recent or {}) == 0)
end

-- Win rate 0..1 (never above 1, 0 with no runs).
function LedgerPages.winRate(stats)
	local runs = whole(stats and stats.runs)
	if runs == 0 then return 0 end
	return math.min(1, whole(stats.wins) / runs)
end

-- Chalk tally for a count: groups of five (four strokes and a slash) plus loose strokes. Capped at TALLY_MAX marks.
function LedgerPages.tally(n)
	n = whole(n)
	local shown = math.min(n, LedgerPages.TALLY_MAX)
	return { fives = shown // 5, loose = shown % 5, total = n, capped = n > LedgerPages.TALLY_MAX }
end

-- Page 1 content.
function LedgerPages.story(stats)
	stats = stats or {}
	return {
		wins = whole(stats.wins),
		runs = whole(stats.runs),
		bestNight = whole(stats.bestNight),
		winRate = LedgerPages.winRate(stats),
		tally = LedgerPages.tally(stats.bestNight),
	}
end

-- Best-run ordering: highest Night, a win beats a loss, then the higher score.
local function better(a, b)
	if a.night ~= b.night then return a.night > b.night end
	if (a.won == true) ~= (b.won == true) then return a.won == true end
	return (a.score or 0) > (b.score or 0)
end

-- Up to `max` best runs out of the recent list, best first.
function LedgerPages.bests(recent, max)
	local list = {}
	for _, e in ipairs(recent or {}) do list[#list + 1] = e end
	table.sort(list, better)
	local out = {}
	for i = 1, math.min(max or LedgerPages.BESTS_SHOWN, #list) do out[i] = list[i] end
	return out
end

-- Page 2 lifetime ledger lines, in order: Title, Hands played, Best hand score, Tips earned.
function LedgerPages.lifeLines(stats, titleName)
	stats = stats or {}
	return {
		{ label = "Title", value = titleName or "None" },
		{ label = "Hands played", value = LedgerPages.fmt(stats.hands) },
		{ label = "Best hand score", value = LedgerPages.fmt(stats.bestHandScore) },
		{ label = "Tips earned", value = LedgerPages.fmt(stats.tipsEarned) },
	}
end

-- Page 2 content.
function LedgerPages.hall(stats, titleName)
	stats = stats or {}
	local fav = stats.favoritePatron
	return {
		favorite = fav and { id = fav.id, wins = whole(fav.wins) } or nil,
		bests = LedgerPages.bests(stats.recent, LedgerPages.BESTS_SHOWN),
		life = LedgerPages.lifeLines(stats, titleName),
	}
end

-- Page 3 content: the newest runs for the list and the bars (oldest on the left) for the sparkline.
function LedgerPages.records(stats)
	local recent = (stats and stats.recent) or {}
	local rows = {}
	for i = 1, math.min(LedgerPages.RUNS_SHOWN, #recent) do rows[i] = recent[i] end
	local maxNight = 1
	local bars = {}
	local count = math.min(LedgerPages.SPARK_SLOTS, #recent)
	for _, e in ipairs(recent) do maxNight = math.max(maxNight, whole(e.night)) end
	for slot = 0, count - 1 do
		local e = recent[count - slot] -- recent[1] is the newest, so the oldest shown goes first
		bars[#bars + 1] = { night = whole(e.night), won = e.won == true, height = whole(e.night) / maxNight }
	end
	return { rows = rows, bars = bars, maxNight = maxNight }
end

-- Which headline records grew between two stats snapshots (empty when there is no earlier snapshot, so opening the
-- ledger for the first time never stamps anything).
function LedgerPages.beaten(prev, cur)
	local out = {}
	if not prev or not cur then return out end
	if whole(cur.wins) > whole(prev.wins) then out[#out + 1] = "wins" end
	if whole(cur.bestNight) > whole(prev.bestNight) then out[#out + 1] = "bestNight" end
	if whole(cur.bestHandScore) > whole(prev.bestHandScore) then out[#out + 1] = "bestHandScore" end
	return out
end

-- Count-up value at progress t (0..1), eased out; ends exactly on the target.
function LedgerPages.countUp(target, t)
	target = whole(target)
	if t >= 1 then return target end
	if t <= 0 then return 0 end
	local eased = 1 - (1 - t) * (1 - t)
	return math.floor(target * eased)
end

-- Step to a neighbouring page, clamped to 1..#PAGES.
function LedgerPages.step(index, delta)
	return math.max(1, math.min(#LedgerPages.PAGES, index + delta))
end

-- Layout fractions of the ledger panel (the desk). The book leaves a strip on the right for the bookmark ribbon tabs and
-- a title line on top; the two pages share the book with a spine between them.
LedgerPages.LAYOUT = {
	title = { x = 0, y = 0.012, w = 1, h = 0.07 },
	book = { x = 0.03, y = 0.095, w = 0.90, h = 0.80 },
	-- inside the book (fractions of the book)
	left = { x = 0.03, y = 0.04, w = 0.455, h = 0.92 },
	right = { x = 0.515, y = 0.04, w = 0.455, h = 0.92 },
	tabs = { x = 0.925, y = 0.14, w = 0.07, h = 0.6 },
	close = { x = 0.5, y = 0.93, h = 0.06 },
}

-- Pixel rectangles for a panel of w x h: { title, book, left, right, tabs } each { x, y, w, h } in panel px.
function LedgerPages.rects(w, h)
	local L = LedgerPages.LAYOUT
	local function abs(r) return { x = r.x * w, y = r.y * h, w = r.w * w, h = r.h * h } end
	local book = abs(L.book)
	local function inBook(r) return { x = book.x + r.x * book.w, y = book.y + r.y * book.h, w = r.w * book.w, h = r.h * book.h } end
	return { title = abs(L.title), book = book, left = inBook(L.left), right = inBook(L.right), tabs = abs(L.tabs) }
end

return LedgerPages
