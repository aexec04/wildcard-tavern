--[[
	DailyShare.lua
	Today's Daily Run gets a friendly seed name (the same for everyone, made from the UTC date key) and a short kind share
	line a player can copy from the Run Over screen. Pure Lua, no Roblox APIs, no randomness.

	seedName(dateKey)                "Cozy Lantern"
	line(summary, dateKey, twist)    "Daily Cozy Lantern (Steady Hands): I reached Night 6 in <game>. Can you beat me?"

	Roblox games cannot write the clipboard, so the UI shows the line in the selectable share box (select, then Ctrl+C).
	The share button keeps the 44 px hit area of the other More buttons (RunOverLayout.SMALL_H).
]]

local GameName = require(script.Parent.GameName)

local DailyShare = {}

DailyShare.MAX_LENGTH = 200

DailyShare.Adjectives = { "Cozy", "Sunny", "Merry", "Gentle", "Lucky", "Bright", "Snug", "Jolly", "Quiet", "Cheery", "Warm", "Kind" }
DailyShare.Nouns = { "Lantern", "Teapot", "Biscuit", "Fiddle", "Blanket", "Candle", "Pie", "Acorn", "Kettle", "Button", "Ribbon", "Muffin" }

local function digitsOf(dateKey)
	local sum, mix = 0, 7
	for d in tostring(dateKey or ""):gmatch("%d") do
		sum = sum + tonumber(d)
		mix = (mix * 31 + tonumber(d)) % 9973
	end
	return sum, mix
end

function DailyShare.seedName(dateKey)
	local sum, mix = digitsOf(dateKey)
	local a = DailyShare.Adjectives[(mix % #DailyShare.Adjectives) + 1]
	local n = DailyShare.Nouns[((mix + sum) % #DailyShare.Nouns) + 1]
	return a .. " " .. n
end

function DailyShare.line(summary, dateKey, twist)
	local night = math.max(1, math.floor(tonumber(summary and summary.night) or 1))
	local head = "Daily " .. DailyShare.seedName(dateKey)
	if type(twist) == "string" and twist ~= "" then head = head .. " (" .. twist .. ")" end
	local verb = (summary and summary.won) and "won and reached" or "reached"
	local text = string.format("%s: I %s Night %d in %s. Can you beat me?", head, verb, night, GameName.NAME)
	if #text > DailyShare.MAX_LENGTH then text = text:sub(1, DailyShare.MAX_LENGTH - 3) .. "..." end
	return text
end

return DailyShare
