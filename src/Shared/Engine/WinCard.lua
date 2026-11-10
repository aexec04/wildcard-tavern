--[[
	Shared/Engine/WinCard.lua
	The Win Card: a shareable parchment card for a won run or a new best. This module only builds the text and the
	data (pure Lua, no Roblox APIs); Client/WinCard.lua draws it.

	build(summary, extras) -> {
	  title, subtitle, nightText, bestHandText, stakeText, footer, patrons = { {id, name, icon} x up to 3 },
	  cardBackId, shareText }
	  summary  = the run summary the server sends (night, won, bestHand, patrons)
	  extras   = { stake, cardBackId, seedText, newBest }

	shareText is within ShareResult.MAX_LENGTH (200), has no dashes and never contains a banned word. Names are
	cleaned so a hyphen in a Patron name cannot sneak a dash into the line.
]]

local ShareResult = require(script.Parent.ShareResult)
local GameName = require(script.Parent.GameName)

local WinCard = {}

WinCard.MAX_PATRONS = 3

local BANNED = { "balatro" }

-- Plain text: dashes become spaces, double spaces collapse, control characters are dropped.
function WinCard.clean(text)
	text = tostring(text or "")
	text = text:gsub("\226\128[\147\148]", " ") -- en and em dash
	text = text:gsub("%-", " ")
	text = text:gsub("[%c]", "")
	text = text:gsub("%s+", " ")
	text = text:gsub("^%s+", ""):gsub("%s+$", "")
	for _, word in ipairs(BANNED) do
		if text:lower():find(word, 1, true) then
			return ""
		end
	end
	return text
end

function WinCard.build(summary, extras)
	summary = summary or {}
	extras = extras or {}
	local night = math.max(1, math.floor(tonumber(summary.night) or 1))
	local stake = math.max(1, math.floor(tonumber(extras.stake) or 1))
	local won = summary.won == true
	local title = won and "Tavern Champion" or (extras.newBest and "New Personal Best" or "Night Reached")
	local hand = summary.bestHand
	local bestHandText = hand and hand.name and string.format("%s for %d", WinCard.clean(hand.name), math.floor(tonumber(hand.score) or 0)) or "No hands yet"

	local patrons = {}
	for _, p in ipairs(summary.patrons or {}) do
		if #patrons >= WinCard.MAX_PATRONS then break end
		patrons[#patrons + 1] = { id = p.id, name = WinCard.clean(p.name), icon = p.icon }
	end

	local parts = { string.format("%s in " .. GameName.NAME .. "!", won and ("I won and reached Night " .. night) or ("I reached Night " .. night)) }
	if hand and hand.name then
		parts[#parts + 1] = string.format("Best hand: %s (%d).", WinCard.clean(hand.name), math.floor(tonumber(hand.score) or 0))
	end
	if stake > 1 then
		parts[#parts + 1] = "Stake " .. stake .. "."
	end
	local seedText = WinCard.clean(extras.seedText)
	if seedText ~= "" then
		parts[#parts + 1] = seedText .. "."
	end
	parts[#parts + 1] = "Can you beat me?"
	local text = WinCard.clean(table.concat(parts, " "))
	if #text > ShareResult.MAX_LENGTH then
		text = text:sub(1, ShareResult.MAX_LENGTH - 3) .. "..."
	end

	local blessing = summary.blessing
	local blessingText = ""
	if type(blessing) == "table" and blessing.name then
		blessingText = WinCard.clean(string.format("Blessing: %s, curse: %s", blessing.name, string.lower(tostring(blessing.curse or ""))))
	end

	return {
		blessingText = blessingText,
		title = title,
		subtitle = won and "You beat the tavern!" or "A fine run!",
		nightText = "Night " .. night,
		bestHandText = bestHandText,
		stakeText = "Stake " .. stake,
		footer = blessingText ~= "" and blessingText or (seedText ~= "" and seedText or GameName.NAME),
		patrons = patrons,
		cardBackId = extras.cardBackId,
		shareText = text,
	}
end

-- A card is offered after a full run win or a new personal best.
function WinCard.worthShowing(summary, extras)
	return (summary and summary.won == true) or (extras and extras.newBest == true) or false
end

return WinCard
