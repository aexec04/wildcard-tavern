--[[
	BestLine.lua
	One short kid safe line: the best Night reached and the best hand score so far, from profile stats.
	Pure Lua. The Menu plate and the Run Over screen both draw it; nothing here is stored.

	BestLine.text(stats) -> string | nil     stats = { bestNightReached, bestHandScore } (either may be missing)
	  nil until the player has reached Night 1 or scored a hand, so a brand new profile shows nothing.
]]

local ScoreText = require(script.Parent.ScoreText)

local BestLine = {}

BestLine.MAX_CHARS = 40

local function whole(n)
	if type(n) ~= "number" or n ~= n or n < 0 then return 0 end
	return math.floor(math.min(n, 9e15))
end

function BestLine.text(stats)
	stats = type(stats) == "table" and stats or {}
	local night = whole(stats.bestNightReached)
	local score = whole(stats.bestHandScore)
	local text
	if night > 0 and score > 0 then
		text = string.format("Best: Night %d, hand %s", night, ScoreText.short(score))
	elseif night > 0 then
		text = string.format("Best: Night %d", night)
	elseif score > 0 then
		text = string.format("Best hand: %s", ScoreText.short(score))
	end
	if text and #text > BestLine.MAX_CHARS then text = text:sub(1, BestLine.MAX_CHARS) end
	return text
end

BestLine.RUN_MAX_CHARS = 52

-- This run's biggest hand: "Biggest hand: High Card, 15 points". nil without a hand name.
function BestLine.runLine(handName, score)
	if type(handName) ~= "string" or handName == "" then return nil end
	local pts = whole(score)
	local text = "Biggest hand: " .. handName
	if pts > 0 then text = text .. ", " .. ScoreText.short(pts) .. (pts == 1 and " point" or " points") end
	if #text > BestLine.RUN_MAX_CHARS then text = text:sub(1, BestLine.RUN_MAX_CHARS) end
	return text
end

-- The record across runs, labelled as a record: "Your record: Night 5, best hand 15". nil for a new profile.
function BestLine.recordLine(stats)
	stats = type(stats) == "table" and stats or {}
	local night = whole(stats.bestNightReached)
	local score = whole(stats.bestHandScore)
	local text
	if night > 0 and score > 0 then
		text = string.format("Your record: Night %d, best hand %s", night, ScoreText.short(score))
	elseif night > 0 then
		text = string.format("Your record: Night %d", night)
	elseif score > 0 then
		text = string.format("Your record: best hand %s", ScoreText.short(score))
	end
	if text and #text > BestLine.RUN_MAX_CHARS then text = text:sub(1, BestLine.RUN_MAX_CHARS) end
	return text
end

return BestLine
