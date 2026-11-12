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
	return GameOverTips.TIPS[i]
end

return GameOverTips
