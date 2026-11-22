--[[
	ShareResult.lua
	The short text a player can copy from the run summary to share a result or challenge a friend. Pure Lua, no
	Roblox APIs. Roblox chat takes 200 characters, so every line is kept within MAX_LENGTH.

	line(summary, seedCode)        a seeded run: "I reached Night 6 in The Gilded Knave. Best hand: Flush (1240). Seed: ABC234. Can you beat me?"
	                               an ordinary run: one of three variants for a win or a loss (ShareVariants), 80 characters or less
	challengeLine(summary, code)   "Beat my Night 6 in The Gilded Knave! Open Seed Run and enter ABC234."

	summary = { night, won, bestHand = { name, score } | nil } (the run summary the server sends).
	Games cannot write the clipboard, so the UI shows the line in a selectable box (select, then Ctrl+C).
]]

local GameName = require(script.Parent.GameName)

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
	if seedCode == nil or seedCode == "" then -- an ordinary run: one of three kind variants, 80 characters or less (Engine/ShareVariants)
		local hand = summary and summary.bestHand
		return require(script.Parent.ShareVariants).line((summary and summary.won) and "win" or "loss",
			{ night = night(summary), won = summary and summary.won == true, hand = hand and hand.name or nil },
			night(summary) * 7 + math.floor(tonumber(hand and hand.score) or 0))
	end
	local parts = { string.format("I %s Night %d in " .. GameName.NAME .. ".", (summary and summary.won) and "won and reached" or "reached", night(summary)) }
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
	return clip(string.format("Beat my Night %d in " .. GameName.NAME .. "! Open Seed Run and enter %s.", night(summary), tostring(code or "?")))
end

return ShareResult
