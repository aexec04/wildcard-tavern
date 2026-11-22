--[[
	NameFit.lua
	Fitting a player name, and a title after it, into a plate. Pure functions, never error on nil or odd input.
	The label's own TextTruncate stays on as a backstop; these rules decide the text first so a long name keeps its
	first letters and an ellipsis, and a title is dropped before the name is cut.

	Used by Client/PlayerMedallion (the Menu sidebar), Client/DailyLeaderboard and Client/SpectatePanel.
	Roblox display names are at most 20 characters.
]]

local NameFit = {}

NameFit.MAX_NAME = 20
NameFit.ELLIPSIS = "..."
NameFit.MIN_CHARS = 4 -- never clip a name below this many characters (including the ellipsis)
NameFit.CHAR_WIDTH = 0.6 -- average glyph width as a fraction of the text size, Gotham bold (wide on purpose)

-- plain text: control characters and line breaks become spaces, runs of spaces collapse, ends trimmed
function NameFit.clean(name)
	if type(name) ~= "string" then
		return ""
	end
	local s = name:gsub("[%c]", " "):gsub("%s+", " ")
	return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function length(s)
	return utf8.len(s) or #s
end

local function head(s, n)
	if length(s) <= n then
		return s
	end
	local cut = utf8.offset(s, n + 1)
	return cut and s:sub(1, cut - 1) or s:sub(1, n)
end

-- How many characters fit in `widthPx` at `textSize`.
function NameFit.maxChars(widthPx, textSize)
	local w, size = tonumber(widthPx) or 0, tonumber(textSize) or 14
	if w <= 0 or size <= 0 then
		return NameFit.MIN_CHARS
	end
	return math.max(NameFit.MIN_CHARS, math.floor(w / (size * NameFit.CHAR_WIDTH)))
end

-- The name cut to `limit` characters, ending in "..." when it was cut. Empty or missing names read "?".
function NameFit.clip(name, limit)
	local s = NameFit.clean(name)
	if s == "" then
		return "?"
	end
	limit = math.max(NameFit.MIN_CHARS, math.floor(tonumber(limit) or NameFit.MAX_NAME))
	if length(s) <= limit then
		return s
	end
	return head(s, limit - #NameFit.ELLIPSIS) .. NameFit.ELLIPSIS
end

-- "Name  |  Title" fitted to `limit` characters in total: the name is kept whole when it fits, the title is cut next and
-- dropped entirely when fewer than 4 characters of room are left. A name never loses letters to make room for a title.
function NameFit.withTitle(name, title, limit)
	limit = math.max(NameFit.MIN_CHARS, math.floor(tonumber(limit) or NameFit.MAX_NAME))
	local n = NameFit.clean(name)
	if n == "" then n = "?" end
	local t = NameFit.clean(title)
	if t == "" then
		return NameFit.clip(n, limit)
	end
	local sep = "  |  "
	local room = limit - length(n) - #sep
	if length(n) > limit or room < NameFit.MIN_CHARS then
		return NameFit.clip(n, limit)
	end
	return n .. sep .. NameFit.clip(t, room)
end

return NameFit
