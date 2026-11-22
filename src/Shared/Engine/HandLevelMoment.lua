--[[
	HandLevelMoment.lua
	The small celebration when a poker hand levels up (a level Recipe from the Counter, a pack or the Menu): one toast line and
	one existing sound. Pure Lua, no Roblox APIs. The server compares the hand levels before and after an action and sends the
	line on the reward notice (`levelUp`); Client/UnlockToast shows it in the set plate toast and plays SOUND.

	  HandLevelMoment.diff(before, after)      -> list of { hand, level, gainChips, gainMult } for each hand that went up (stable order)
	  HandLevelMoment.line(hand, level, chips, mult) -> "Pair is now level 3: +2 Chips, +1 Mult" (60 characters or less)
	  HandLevelMoment.notice(before, after)    -> nil, or { text, levelUp = { hand, level } } for the best hand that went up
	  HandLevelMoment.SOUND                    the existing sound id name in Client/Sound SOUND_IDS ("roundReward")
	Calm mode and Reduce motion: the toast is a still line, nothing here animates.
]]

local Scoring = require(script.Parent.Scoring)
local HandEvaluator = require(script.Parent.HandEvaluator)

local HandLevelMoment = {}

HandLevelMoment.SOUND = "roundReward"

function HandLevelMoment.line(hand, level, chips, mult)
	local text = hand .. " is now level " .. math.floor(level)
	local gains = {}
	if (chips or 0) > 0 then gains[#gains + 1] = "+" .. math.floor(chips) .. " Chips" end
	if (mult or 0) > 0 then gains[#gains + 1] = "+" .. math.floor(mult) .. " Mult" end
	if #gains > 0 then text = text .. ": " .. table.concat(gains, ", ") end
	return text
end

function HandLevelMoment.diff(before, after)
	local out = {}
	before, after = before or {}, after or {}
	for _, hand in ipairs(HandEvaluator.HandOrder) do
		local a, b = tonumber(before[hand]) or 0, tonumber(after[hand]) or 0
		if b > a then
			local growth = Scoring.HandLevelGrowth[hand] or { chips = 0, mult = 0 }
			out[#out + 1] = { hand = hand, level = b, gainChips = growth.chips or 0, gainMult = growth.mult or 0 }
		end
	end
	return out
end

function HandLevelMoment.notice(before, after)
	local ups = HandLevelMoment.diff(before, after)
	if #ups == 0 then return nil end
	local best = ups[#ups] -- HandOrder runs weakest to strongest: show the highest hand that went up
	return { text = HandLevelMoment.line(best.hand, best.level, best.gainChips, best.gainMult), levelUp = { hand = best.hand, level = best.level } }
end

return HandLevelMoment
