--[[
	ScoreText.lua
	One safe way to show a big score or target. Never errors on nil, NaN, inf or negative numbers, never needs
	"%d" on a float too large for an integer. Pure Lua, no Roblox APIs.

		full(n)   12345678  -> "12,345,678"   (thousands separators)
		short(n)  1234567   -> "1.2M"         (K, M, B, T, Q; plain below 10,000)
		plate(n)  full up to 999,999,999, then short, so it always fits the Score plate
]]

local ScoreText = {}

ScoreText.MAX = 9e15 -- same ceiling as EndlessRules.TARGET_CAP: exact whole numbers below 2^53

-- A whole, finite, non-negative number no larger than MAX.
function ScoreText.clean(n)
	n = tonumber(n)
	if n == nil or n ~= n then
		return 0
	end
	return math.max(0, math.min(ScoreText.MAX, math.floor(n)))
end

function ScoreText.full(n)
	local text = string.format("%d", ScoreText.clean(n)) -- clean() gives a whole number inside integer range
	while true do
		local nxt, hits = text:gsub("^(%d+)(%d%d%d)", "%1,%2")
		text = nxt
		if hits == 0 then break end
	end
	return text
end

local UNITS = { { 1e15, "Q" }, { 1e12, "T" }, { 1e9, "B" }, { 1e6, "M" }, { 1e3, "K" } }

function ScoreText.short(n)
	n = ScoreText.clean(n)
	if n < 10000 then
		return ScoreText.full(n)
	end
	for index, unit in ipairs(UNITS) do
		if n >= unit[1] then
			local text = string.format("%.1f", n / unit[1])
			if text == "1000.0" and index > 1 then -- rounds up into the next unit, never "1000.0K"
				return "1" .. UNITS[index - 1][2]
			end
			return (text:gsub("%.0$", "")) .. unit[2]
		end
	end
	return ScoreText.full(n)
end

-- The live tally and the popups: full with commas below 1 million, short form (1.2M) from 1 million so it never outgrows its plate.
function ScoreText.tally(n)
	n = ScoreText.clean(n)
	if n < 1e6 then
		return ScoreText.full(n)
	end
	return ScoreText.short(n)
end

function ScoreText.plate(n)
	n = ScoreText.clean(n)
	if n < 1e9 then
		return ScoreText.full(n)
	end
	return ScoreText.short(n)
end

-- The Round Select Target plate: "Target: 12,400", or "Target: 3.4B" once it is too wide. Never inf, NaN or an error, even past Night 60.
function ScoreText.targetLine(target)
	return "Target: " .. ScoreText.plate(target)
end

return ScoreText
