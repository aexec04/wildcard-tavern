-- Wording and sizes for the Daily, Weekly and Endless boards (Client/DailyLeaderboard.lua).
-- Pure data and functions so tests can check them. Never errors on nil or odd input.

local EmptyStates = require(script.Parent.EmptyStates)

local LeaderboardText = {}

LeaderboardText.ROW_H = 44 -- a board row, real or placeholder
LeaderboardText.SKELETON_ROWS = 3 -- placeholder rows shown while the board loads
LeaderboardText.SHIMMER_SECONDS = 1.2 -- one light sweep; not played at all in Calm mode or Reduce motion

LeaderboardText.MIN_TEXT = 14
LeaderboardText.MIN_PANEL_W = 620 -- six tab buttons share one row, they need this much
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
	if not ok then return LeaderboardText.BEST_FAILED end
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

-- Rects (x, y, w, h) inside the panel, matching DailyLeaderboard's layout.
function LeaderboardText.layout(vw, vh)
	local w, h = LeaderboardText.panelSize(vw, vh)
	return {
		panel = { w = w, h = h },
		tabsLeft = { x = 0, y = 0, w = 288 + 90, h = 26 },
		tabsRight = { x = w - 186, y = 0, w = 186, h = 26 },
		scroll = { x = 15, y = 77, w = w - 30, h = h - 142 },
		close = { x = w / 2 - 70, y = h - 50, w = 140, h = 40 },
	}
end

return LeaderboardText
