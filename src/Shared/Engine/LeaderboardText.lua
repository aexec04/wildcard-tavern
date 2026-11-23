-- Wording and sizes for the Daily, Weekly and Endless boards (Client/DailyLeaderboard.lua).
-- Pure data and functions so tests can check them. Never errors on nil or odd input.

local EmptyStates = require(script.Parent.EmptyStates)

local LeaderboardText = {}

LeaderboardText.ROW_H = 44 -- a board row, real or placeholder
LeaderboardText.SKELETON_ROWS = 3 -- placeholder rows shown while the board loads
LeaderboardText.SHIMMER_SECONDS = 1.2 -- one light sweep; not played at all in Calm mode or Reduce motion

LeaderboardText.MIN_TEXT = 14
LeaderboardText.MIN_PANEL_W = 700 -- six tab buttons share one row, plus 56 px kept clear for the round close X
LeaderboardText.MIN_PANEL_H = 330
LeaderboardText.LOADING = "Loading the board..."
LeaderboardText.OFFLINE = "Couldn't reach the board. Press Close and try again in a moment."
LeaderboardText.TOP_FAILED = "The top 10 isn't loading right now. Press Close and try again soon."
LeaderboardText.BEST_FAILED = "Couldn't check your best score."

local function whole(n)
	n = tonumber(n) or 0
	return math.max(0, math.floor(n))
end

-- 12345 -> "12,345"
function LeaderboardText.fmt(n)
	local text = string.format("%d", whole(n))
	while true do
		local nxt, hits = text:gsub("^(%d+)(%d%d%d)", "%1,%2")
		text = nxt
		if hits == 0 then break end
	end
	return text
end

function LeaderboardText.rank(n)
	return "#" .. LeaderboardText.fmt(n)
end

function LeaderboardText.stats(endless, a, b)
	if endless then
		return "Night " .. LeaderboardText.fmt(a) .. "  |  Best hand " .. LeaderboardText.fmt(b)
	end
	return "Depth " .. LeaderboardText.fmt(a) .. "  |  " .. LeaderboardText.fmt(b) .. " Tips"
end

-- yourBestOk false: couldn't check. yourBest nil: no score yet.
function LeaderboardText.yourBest(endless, period, ok, best)
	if not ok then -- The six tab rects (x, y, w, h) by name, in panel pixels: Daily, Weekly, Endless, Global on the left, Standard and Revived on the right.
function LeaderboardText.tabRects(vw, vh)
	local L = LeaderboardText
	local lay = L.layout(vw, vh)
	local r = {}
	for i, name in ipairs({ "daily", "weekly", "endless", "global" }) do
		r[name] = { x = L.TAB_LEFT + (i - 1) * L.TAB_STEP, y = L.TAB_TOP, w = L.TAB_W, h = L.TAB_H }
	end
	r.standard = { x = lay.tabsRight.x, y = L.TAB_TOP, w = L.TAB_W, h = L.TAB_H }
	r.revived = { x = lay.tabsRight.x + L.TAB_W + 6, y = L.TAB_TOP, w = L.TAB_W_WIDE, h = L.TAB_H }
	return r
end

LeaderboardText.TAB_LABELS = { daily = "Daily", weekly = "Weekly", endless = "Endless", global = "Global", standard = "Standard", revived = "Revived" }

return LeaderboardText.BEST_FAILED end
	if not best then
		return "No score " .. period .. " yet. Finish a run to get on the board!"
	end
	if endless then
		return "Your best " .. period .. ": Night " .. LeaderboardText.fmt(best.depth)
			.. ", best hand " .. LeaderboardText.fmt(best.tips)
	end
	return "Your best " .. period .. ": Depth " .. LeaderboardText.fmt(best.depth)
		.. ", " .. LeaderboardText.fmt(best.tips) .. " Tips"
end

-- The line for a board with no rows. It comes from Engine/EmptyStates so every empty page speaks the same way.
function LeaderboardText.empty(friends)
	return friends and EmptyStates.Screens.friends or EmptyStates.Screens.leaderboard
end

-- Panel size in pixels for a viewport: half the width and 65 percent of the height, never below the minimum.
function LeaderboardText.panelSize(vw, vh)
	return math.max(LeaderboardText.MIN_PANEL_W, math.floor(vw * 0.5)),
		math.max(LeaderboardText.MIN_PANEL_H, math.floor(vh * 0.65))
end

-- ROW PARTS: rank badge, name and stats of one board row, in row pixels, never overlapping. Text is 14 px; widths come from the real strings
-- (0.6 em per glyph for bold, 0.56 for regular, a cautious estimate), so a big score like "Night 99,999  |  Best hand 9,999,999" gets the room
-- it needs and the name takes what is left (it truncates with "..." if it must). 8 px padding at the edges and between the parts.
LeaderboardText.ROW_PAD = 8
LeaderboardText.ROW_TEXT = 14
LeaderboardText.NAME_MIN_W = 80
function LeaderboardText.textWidth(text, bold)
	return math.ceil(#tostring(text or "") * LeaderboardText.ROW_TEXT * (bold and 0.6 or 0.56))
end
function LeaderboardText.rowParts(rowW, rankText, statsText)
	local pad, h = LeaderboardText.ROW_PAD, LeaderboardText.ROW_H
	local rankW = math.max(40, LeaderboardText.textWidth(rankText, true) + 14)
	local statsW = math.max(160, LeaderboardText.textWidth(statsText, false) + 8)
	statsW = math.min(statsW, math.max(160, math.floor(rowW * 0.6))) -- on a very narrow row the stats stop growing, the name keeps its minimum
	local nameX = pad + rankW + pad
	local nameW = rowW - nameX - pad - statsW - pad
	if nameW < LeaderboardText.NAME_MIN_W then
		statsW = math.max(0, statsW - (LeaderboardText.NAME_MIN_W - nameW))
		nameW = LeaderboardText.NAME_MIN_W
	end
	return {
		rank = { x = pad, y = 0, w = rankW, h = h },
		name = { x = nameX, y = 0, w = nameW, h = h },
		stats = { x = nameX + nameW + pad, y = 0, w = statsW, h = h },
	}
end

-- Vertical rows of the panel, shared with Client/DailyLeaderboard: tab buttons are 44 px tall (touch size), then the title, the
-- "your best" line, the scroll, and a 44 px Close button 12 px above the bottom edge.
LeaderboardText.TAB_H = 44
LeaderboardText.TAB_TOP = 8 -- clear space between the plate border and the tab row
LeaderboardText.TAB_LEFT = 12
LeaderboardText.TAB_W = 96
LeaderboardText.TAB_STEP = 100
LeaderboardText.TAB_W_WIDE = 108 -- Revived: the longest label
LeaderboardText.CLOSE_X_RESERVE = 56 -- the round close X (44 px hit area, 8 px inset) owns the top right corner
LeaderboardText.EMPTY_TEXT = 16 -- the friendly line on an empty board
LeaderboardText.TITLE_Y = 58
LeaderboardText.TITLE_H = 26
LeaderboardText.BEST_Y = 86
LeaderboardText.BEST_H = 20
LeaderboardText.SCROLL_Y = 110
LeaderboardText.CLOSE_H = 44
LeaderboardText.CLOSE_W = 140
LeaderboardText.BOTTOM_PAD = 12
LeaderboardText.SCROLL_GAP = 8

-- Rects (x, y, w, h) inside the panel, matching DailyLeaderboard's layout.
function LeaderboardText.layout(vw, vh)
	local L = LeaderboardText
	local w, h = L.panelSize(vw, vh)
	local closeY = h - L.BOTTOM_PAD - L.CLOSE_H
	return {
		panel = { w = w, h = h },
		tabsLeft = { x = L.TAB_LEFT, y = L.TAB_TOP, w = 3 * L.TAB_STEP + L.TAB_W, h = L.TAB_H },
		tabsRight = { x = w - L.CLOSE_X_RESERVE - L.TAB_W_WIDE - 6 - L.TAB_W, y = L.TAB_TOP,
			w = L.TAB_W + 6 + L.TAB_W_WIDE, h = L.TAB_H },
		closeX = { x = w - 8 - 44, y = 8, w = 44, h = 44 },
		title = { x = 0, y = L.TITLE_Y, w = w, h = L.TITLE_H },
		best = { x = 0, y = L.BEST_Y, w = w, h = L.BEST_H },
		scroll = { x = 15, y = L.SCROLL_Y, w = w - 30, h = closeY - L.SCROLL_GAP - L.SCROLL_Y },
		close = { x = w / 2 - L.CLOSE_W / 2, y = closeY, w = L.CLOSE_W, h = L.CLOSE_H },
	}
end

-- The six tab rects (x, y, w, h) by name, in panel pixels: Daily, Weekly, Endless, Global on the left, Standard and Revived on the right.
function LeaderboardText.tabRects(vw, vh)
	local L = LeaderboardText
	local lay = L.layout(vw, vh)
	local r = {}
	for i, name in ipairs({ "daily", "weekly", "endless", "global" }) do
		r[name] = { x = L.TAB_LEFT + (i - 1) * L.TAB_STEP, y = L.TAB_TOP, w = L.TAB_W, h = L.TAB_H }
	end
	r.standard = { x = lay.tabsRight.x, y = L.TAB_TOP, w = L.TAB_W, h = L.TAB_H }
	r.revived = { x = lay.tabsRight.x + L.TAB_W + 6, y = L.TAB_TOP, w = L.TAB_W_WIDE, h = L.TAB_H }
	return r
end

LeaderboardText.TAB_LABELS = { daily = "Daily", weekly = "Weekly", endless = "Endless", global = "Global", standard = "Standard", revived = "Revived" }

return LeaderboardText
