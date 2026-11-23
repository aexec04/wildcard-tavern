--[[
	Engine/MenuNoteText.lua
	The words on the Menu's Notice Board notes, pure and tested. A note is 300 px wide on the board with 12 px of padding, so a
	line holds about 28 characters at 14 px; text is cut at a word boundary (never with dots) and kept to two lines.

	  M.PAD                      12   padding inside a note, every side
	  M.LINE_CHARS               28   characters on one line at 14 px in the padded width
	  M.fit(text, lines)         -> text cut at a word boundary to at most `lines` lines of LINE_CHARS, no dots
	  M.newsLine(row)            -> "Harvest Week" (the event name, two lines at most)
	  M.newsTime(row)            -> "4 days left" / "Last day" / "Starts tomorrow"
	  M.rankLines(view)          -> { main = "Rank 1  71 / 80 XP", reward = "Next: +3 Tips" or nil }
	  M.soonLine(soon)           -> "Soon: <event name>", cut to two lines like the live event line
	  M.wrapWidth(x, w)          -> w, less any amount that would leave under TextFit.SIDE (12 px) between the word and the note edge
	  M.lineCount(text, size, w) -> lines the text needs in wrapWidth, never under 1
	  M.oneLineSize(text, w, size) -> size, or the largest smaller size (12 at least) at which the text fits one line of width w
]]

local TextFit = require(script.Parent:WaitForChild("TextFit"))

local M = {}

M.PAD = 12
M.LINE_CHARS = 28
M.MAX_NEWS_LINES = 2

local SHORT_REWARD = { tips = "Tips", title = "Title", cardBack = "Card back", set = "Card Set" }

-- cut at the last space that keeps the text inside `lines` lines; no ellipsis
function M.fit(text, lines)
	text = tostring(text or "")
	local limit = M.LINE_CHARS * math.max(1, math.floor(lines or 1))
	if #text <= limit then return text end
	local cut = text:sub(1, limit)
	local sp = cut:match("^(.*)%s+%S*$")
	cut = (sp and #sp > 0) and sp or cut
	return (cut:gsub("[%s%p]+$", ""))
end

function M.newsLine(row)
	if type(row) ~= "table" then return "" end
	-- the name only (the long sentence stays in the News panel); with the time line the plate is three lines at most
	return M.fit(tostring(row.name or ""), M.MAX_NEWS_LINES)
end

function M.soonLine(soon)
	if type(soon) ~= "table" then return "" end
	return M.fit("Soon: " .. tostring(soon.name or ""), M.MAX_NEWS_LINES)
end

M.NOTE_W = 300 -- Engine/MenuRoomLayout.NOTE_W

function M.wrapWidth(x, w)
	local margin = M.NOTE_W - (x + w) -- space left between the label and the note edge
	return w - math.max(0, TextFit.SIDE - margin)
end

function M.lineCount(text, size, w)
	return TextFit.lines(text, size, w)
end

function M.oneLineSize(text, w, size)
	for s = size, 12, -1 do
		if TextFit.width(text, s) <= w then return s end
	end
	return 12
end

function M.newsTime(row)
	if type(row) ~= "table" then return "" end
	if row.daysLeft then
		local d = math.floor(tonumber(row.daysLeft) or 0)
		return d <= 1 and "Last day" or (tostring(d) .. " days left")
	end
	local n = math.floor(tonumber(row.startsIn) or 0)
	return n <= 1 and "Starts tomorrow" or ("Starts in " .. tostring(n) .. " days")
end

function M.rankLines(view)
	if type(view) ~= "table" then return { main = "Rank 1" } end
	local rank = math.floor(tonumber(view.rank) or 1)
	if view.maxed then return { main = string.format("Rank %d  Max rank", rank) } end
	local out = { main = string.format("Rank %d  %d / %d XP", rank, math.floor(tonumber(view.into) or 0), math.floor(tonumber(view.need) or 0)) }
	local r = view.nextReward
	if r then
		out.reward = "Next: " .. (r.kind == "tips" and ("+" .. tostring(math.floor(tonumber(r.amount) or 0)) .. " Tips") or SHORT_REWARD[r.kind] or "Reward")
	end
	return out
end

return M
