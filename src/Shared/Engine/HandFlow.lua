--[[
	Shared/Engine/HandFlow.lua
	One timing table (tested) for the hand flow: play, score, clear, deal. Presentation only, the engine is untouched.
	Calm mode and Reduce motion pass calm = true and get no motion: zero delays, zero lift, no scale pop.

	HandFlow.TABLE                      the numbers
	HandFlow.playSlide(i, n, calm)      -> { delay, dur }   played card i of n slides to the centred row
	HandFlow.tickLift(active, calm)     -> px a scoring card is raised (0 when not the active card)
	HandFlow.totalPop(calm)             -> { peak, up, settle } for the running Chips x Mult total on each tick
	HandFlow.discardFlight(i, n, calm)  -> { delay, dur } discarded card flies toward the deck
	HandFlow.dealFlip(i, n, calm)       -> { delay, dur, flipFrom } new card dealt from the deck with a flip
]]

local M = {}

M.TABLE = {
	playDur = 0.25, playStagger = 0.04,
	tickLiftPx = 14,
	totalPeak = 1.15, totalUp = 0.06, totalSettle = 0.12,
	discardDur = 0.3, discardStagger = 0.05,
	dealStagger = 0.05, dealDur = 0.3, flipFrom = 0.1,
}

function M.playSlide(i, n, calm)
	if calm then return { delay = 0, dur = 0 } end
	i = math.max(1, math.min(i or 1, math.max(1, n or 1)))
	return { delay = (i - 1) * M.TABLE.playStagger, dur = M.TABLE.playDur }
end

function M.tickLift(active, calm)
	if calm or not active then return 0 end
	return M.TABLE.tickLiftPx
end

function M.totalPop(calm)
	if calm then return nil end
	return { peak = M.TABLE.totalPeak, up = M.TABLE.totalUp, settle = M.TABLE.totalSettle }
end

function M.discardFlight(i, n, calm)
	if calm then return nil end
	i = math.max(1, i or 1)
	return { delay = (i - 1) * M.TABLE.discardStagger, dur = M.TABLE.discardDur }
end

function M.dealFlip(i, n, calm)
	if calm then return nil end
	i = math.max(1, i or 1)
	return { delay = (i - 1) * M.TABLE.dealStagger, dur = M.TABLE.dealDur, flipFrom = M.TABLE.flipFrom }
end

return M
