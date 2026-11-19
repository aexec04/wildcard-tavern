--[[
	Engine/Gameplay2Score.lua
	Gameplay v2: the centre score on the new table. When a hand pays, the number counts up inside the stage rect, then slams
	in at its full size with a gold burst and a short hold before the next deal. Pure numbers, tested; Client/Gameplay2ScoreFX
	draws them. Calm mode and Reduce motion get the end value at once (no steps, no tween, no burst). Fast speed halves the times.
	The per card pop, pitch ticks and Patron pills already live in ScorePopup (HandFlow, ScoreFeel); this adds the centre box.

	Gameplay2Score.plan(oldScore, newScore, opts) -> nil (nothing to show) or
	  { steps = {values}, stepDur, slam = { from, peak, up, settle }, burst = n, hold, total, final }
	  opts = { calm = bool, fast = bool }
	Gameplay2Score.pitch(i, n)  -> speed 1.0 .. 1.3 for tick i of n
	Gameplay2Score.skipTo(plan) -> the final value (a tap skips the count and the slam lands at once)
]]

local M = {}

M.TABLE = { stepDur = 0.07, maxSteps = 12, slamFrom = 1.0, slamPeak = 1.25, slamUp = 0.12, slamSettle = 0.18, burst = 10, hold = 1.0 }

function M.pitch(i, n)
	if (n or 1) <= 1 then return 1.0 end
	i = math.max(1, math.min(i or 1, n))
	return 1.0 + 0.3 * (i - 1) / (n - 1)
end

function M.plan(oldScore, newScore, opts)
	opts = opts or {}
	oldScore = math.floor(tonumber(oldScore) or 0)
	newScore = math.floor(tonumber(newScore) or 0)
	if newScore <= oldScore then return nil end
	if opts.calm then
		return { steps = { newScore }, stepDur = 0, slam = nil, burst = 0, hold = 0, total = 0, final = newScore }
	end
	local T = M.TABLE
	local k = opts.fast and 0.5 or 1
	local n = T.maxSteps
	local steps = {}
	for i = 1, n do steps[i] = math.floor(oldScore + (newScore - oldScore) * i / n + 0.5) end
	steps[n] = newScore
	local stepDur = T.stepDur * k
	local slam = { from = T.slamFrom, peak = T.slamPeak, up = T.slamUp * k, settle = T.slamSettle * k }
	local hold = T.hold * k
	return { steps = steps, stepDur = stepDur, slam = slam, burst = T.burst, hold = hold, final = newScore,
		total = n * stepDur + slam.up + slam.settle + hold }
end

function M.skipTo(plan) return plan and plan.final end

return M
