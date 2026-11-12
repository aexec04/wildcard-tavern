--[[
	MenuTicker.lua
	The slim social-proof line on the main menu: today's best run from the Daily board, roughly how many runs were played
	today, and a button that opens the Daily board. Pure Lua, no Roblox APIs (the server fetches and caches the numbers,
	the client draws the text). When the board or the run counter is unavailable it falls back to a friendly flavor line,
	so the strip is never empty or broken.
]]

local MenuTicker = {}

MenuTicker.CACHE_SECONDS = 60 -- the server refreshes the board and the run count at most this often (per server)

MenuTicker.FlavorLines = {
	"Lanterns lit. Take a seat.",
	"A fresh deck is waiting at the corner table.",
	"Today's Daily is the same for everyone.",
	"Patrons are gathering. Who will you hire?",
	"Every Night has a Boss. Every Boss has a rule.",
	"The Tavern Map is full of secrets.",
	"Finish today's quests for extra Tips.",
}

-- Rounded so the number never looks exact or fake: 0 to 9 is "a few", then steps of 10, 50 and 100.
function MenuTicker.roundRuns(n)
	n = math.floor(tonumber(n) or 0)
	if n < 10 then return 0 end
	if n < 100 then return n - n % 10 end
	if n < 1000 then return n - n % 50 end
	return n - n % 100
end

-- Night 1 .. : "Night 6". `depth` is the Night reached on the Daily board.
local function nightText(depth)
	return "Night " .. tostring(math.max(1, math.floor(tonumber(depth) or 1)))
end

-- The strip text and whether it shows a real board result.
--   data = { top = { name, depth, tips, title } | nil, runs = number | nil }, dayIndex = any number (rotates the flavor line)
function MenuTicker.text(data, dayIndex)
	data = type(data) == "table" and data or {}
	local top = data.top
	local lines = MenuTicker.FlavorLines
	if type(top) == "table" and type(top.name) == "string" and top.name ~= "" and top.name ~= "???" then
		local who = top.name
		if type(top.title) == "string" and top.title ~= "" then
			who = who .. " (" .. top.title .. ")"
		end
		local text = "Today's best: " .. who .. " reached " .. nightText(top.depth)
		local rounded = MenuTicker.roundRuns(data.runs)
		if rounded > 0 then
			text = text .. "   |   about " .. tostring(rounded) .. " runs today"
		end
		return text, true
	end
	local rounded = MenuTicker.roundRuns(data.runs)
	local day = tonumber(dayIndex) or 0
	if day ~= day or day == math.huge or day == -math.huge then
		day = 0 -- NaN or infinity must never break the strip
	end
	local line = lines[(math.floor(day) % #lines) + 1]
	if rounded > 0 then
		line = line .. "   |   about " .. tostring(rounded) .. " runs today"
	end
	return line, false
end

return MenuTicker
