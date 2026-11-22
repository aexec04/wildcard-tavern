--[[
	Engine/GameOverTips.lua
	One-line hints for the Game Over screen after an early loss (Night 1). Pure: pick(night, seed) returns a tip
	or nil. Kid-safe.
]]

local GameOverTips = {}

GameOverTips.TIPS = {
	"Discards refresh each round, so use them early.",
	"Pairs and Flushes score better when your Patrons match the hand.",
	"Visit The Counter after each round: a Patron early snowballs.",
	"Aim for five cards: a bigger hand scores far more than a small one.",
	"Check the Boss rule before you play a round.",
	"Save a Discard only when your hand is already strong.",
}

-- Tips show only after a Night 1 loss. seed picks the line (any number); nil seed gives the first.
function GameOverTips.pick(night, seed)
	if night ~= 1 then
		return nil
	end
	local n = #GameOverTips.TIPS
	local i = (math.floor(tonumber(seed) or 0) % n) + 1
	-- One tip chosen from what happened in the run. facts = { patrons = n, handsPlayed = n, discardsUsed = n, bestHandName = "Pair" }.
-- Order: few Patrons, unused discards, low Mult hands. Falls back to pick() on Night 1, else nil. Kid-safe, one line.
GameOverTips.FEW_PATRONS = "Hire more Patrons at The Counter: each one adds Chips or Mult."
GameOverTips.UNUSED_DISCARDS = "You kept your Discards. Use them to dig for a better hand."
GameOverTips.LOW_MULT = "Your hands stayed small. Try Flushes, Straights or five cards for more Mult."
local LOW_HANDS = { ["High Card"] = true, ["Pair"] = true, ["Two Pair"] = true }

function GameOverTips.forRun(facts, night, seed)
	facts = type(facts) == "table" and facts or {}
	local played = math.floor(tonumber(facts.handsPlayed) or 0)
	if facts.patrons ~= nil and (tonumber(facts.patrons) or 0) < 2 then
		return GameOverTips.FEW_PATRONS
	end
	if played >= 2 and facts.discardsUsed ~= nil and (tonumber(facts.discardsUsed) or 0) == 0 then
		return GameOverTips.UNUSED_DISCARDS
	end
	if facts.bestHandName and LOW_HANDS[facts.bestHandName] then
		return GameOverTips.LOW_MULT
	end
	return GameOverTips.pick(night, seed)
end

return GameOverTips.TIPS[i]
end

-- One tip chosen from what happened in the run. facts = { patrons = n, handsPlayed = n, discardsUsed = n, bestHandName = "Pair" }.
-- Order: few Patrons, unused discards, low Mult hands. Falls back to pick() on Night 1, else nil. Kid-safe, one line.
GameOverTips.FEW_PATRONS = "Hire more Patrons at The Counter: each one adds Chips or Mult."
GameOverTips.UNUSED_DISCARDS = "You kept your Discards. Use them to dig for a better hand."
GameOverTips.LOW_MULT = "Your hands stayed small. Try Flushes, Straights or five cards for more Mult."
local LOW_HANDS = { ["High Card"] = true, ["Pair"] = true, ["Two Pair"] = true }

function GameOverTips.forRun(facts, night, seed)
	facts = type(facts) == "table" and facts or {}
	local played = math.floor(tonumber(facts.handsPlayed) or 0)
	if facts.patrons ~= nil and (tonumber(facts.patrons) or 0) < 2 then
		return GameOverTips.FEW_PATRONS
	end
	if played >= 2 and facts.discardsUsed ~= nil and (tonumber(facts.discardsUsed) or 0) == 0 then
		return GameOverTips.UNUSED_DISCARDS
	end
	if facts.bestHandName and LOW_HANDS[facts.bestHandName] then
		return GameOverTips.LOW_MULT
	end
	return GameOverTips.pick(night, seed)
end

return GameOverTips
