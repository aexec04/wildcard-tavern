--[[
	Shared/Engine/ScoreJuice.lua
	Pure rules for the score reveal flourishes (no Roblox APIs, unit-tested).
	  isNewBest(score, best)            -> true when a hand beats the run's best (and best > 0, so the first hand is not a "record")
	  clearsTarget(before, score, tgt)  -> true when this hand is the one that takes the round score past the Target
	  shakeFor(score, target)           -> screen shake intensity 3..10 scaled to the hand's share of the Target
	  burstFor(score, target)           -> particle count 8..30
	  slowMoFor(newBest, clears)        -> seconds of slow-motion beat (0 when none)
]]

local ScoreJuice = {}

function ScoreJuice.isNewBest(score, best)
	return (best or 0) > 0 and score > best
end

function ScoreJuice.clearsTarget(before, score, target)
	if not target or target <= 0 then
		return false
	end
	return (before or 0) < target and (before or 0) + score >= target
end

function ScoreJuice.shakeFor(score, target)
	if not target or target <= 0 then
		return 3
	end
	local share = score / target
	return math.max(3, math.min(10, 3 + share * 5))
end

function ScoreJuice.burstFor(score, target)
	if not target or target <= 0 then
		return 8
	end
	return math.max(8, math.min(30, math.floor(8 + (score / target) * 14)))
end

function ScoreJuice.slowMoFor(newBest, clears)
	if newBest and clears then
		return 0.45
	elseif newBest or clears then
		return 0.3
	end
	return 0
end

return ScoreJuice
