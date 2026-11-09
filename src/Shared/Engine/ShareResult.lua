--[[
	ShareResult.lua
	The short text a player can copy from the run summary to share a result or challenge a friend. Pure Lua, no
	Roblox APIs. Roblox chat takes 200 characters, so every line is kept within MAX_LENGTH.

	line(summary, seedCode)        "I reached Night 6 in Wildcard Tavern. Best hand: Flush (1240). Seed: ABC234. Can you beat me?"
	challengeLine(summary, code)   "Beat my Night 6 in Wildcard Tavern! Open Seed Run and enter ABC234."

	summary = { night, won, bestHand = { name, score } | nil } (the run summary the server sends).
	Games cannot write the clipboard, so the UI shows the line in a selectable box (select, then Ctrl+C).
]]

local ShareResult = {}

ShareResult.MAX_LENGTH = 200

local function night(summary)
	return math.max(1, math.floor(tonumber(summary and summary.night) or 1))
end

local function clip(text)
	if #text <= ShareResult.MAX_LENGTH then
		return text
	end
	return string.sub(text, 1, ShareResult.MAX_LENGTH - 3) .. "..."
end

function ShareResult.line(summary, seedCode)
	local parts = { string.format("I %s Night %d in Wildcard Tavern.", (summary and summary.won) and "won and reached" or "reached", night(summary)) }
	local hand = summary and summary.bestHand
	if hand and hand.name then
		parts[#parts + 1] = string.format("Best hand: %s (%d).", tostring(hand.name), math.floor(tonumber(hand.score) or 0))
	end
	if seedCode and seedCode ~= "" then
		parts[#parts + 1] = "Seed: " .. tostring(seedCode) .. "."
	end
	parts[#parts + 1] = "Can you beat me?"
	return clip(table.concat(parts, " "))
end

function ShareResult.challengeLine(summary, code)
	return clip(string.format("Beat my Night %d in Wildcard Tavern! Open Seed Run and enter %s.", night(summary), tostring(code or "?")))
end

return ShareResult
