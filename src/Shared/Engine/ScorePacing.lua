--[[
	Engine/ScorePacing.lua
	Pure numbers (tested) for how fast a hand's Patron beats play and how big the final flourish is. Presentation only,
	it never changes a score. Client/ScorePopup reads gap(), Client/Gameplay2ScoreFX reads flourish().

	ScorePacing.GAP = 0.18 s between Patron beats, left to right
	ScorePacing.gap(repeats, fast, calm) -> seconds between beats. Playing the same hand again and again speeds up: 0.03 s
	                                        less per repeat, never under 0.06 s. Fast speed caps at 0.12. Calm mode: 0 (instant).
	ScorePacing.nextRepeats(lastName, lastCount, name) -> how many times in a row this hand name was just played (1 = first)
	Beats already run left to right: Scoring applies the Patrons in seat order and PatronEvents keeps that order.
	ScorePacing.flourish(score, target) -> { level 0..4, burst, peak, extraHold } scaled by how far past the Target the round score is
	ScorePacing.skipGap()               -> 0 (a tap or click plays every remaining beat at once)
]]

local M = {}

M.GAP, M.FLOOR, M.STEP, M.FAST_CAP = 0.18, 0.06, 0.03, 0.12

function M.gap(repeats, fast, calm)
	if calm then return 0 end
	local g = M.GAP - M.STEP * math.max((tonumber(repeats) or 1) - 1, 0)
	g = math.max(g, M.FLOOR)
	if fast then g = math.min(g, M.FAST_CAP) end
	return g
end

function M.skipGap() return 0 end

function M.nextRepeats(lastName, lastCount, name)
	if name ~= nil and name == lastName then return (tonumber(lastCount) or 1) + 1 end
	return 1
end

-- level 0: under the Target, 1: reaches it, 2: 1.5x, 3: 2x, 4: 3x or more
local LEVELS = {
	{ min = 3.0, level = 4, burst = 18, peak = 1.5, extraHold = 0.6 },
	{ min = 2.0, level = 3, burst = 14, peak = 1.4, extraHold = 0.4 },
	{ min = 1.5, level = 2, burst = 12, peak = 1.32, extraHold = 0.2 },
	{ min = 1.0, level = 1, burst = 10, peak = 1.25, extraHold = 0 },
}

function M.flourish(score, target)
	score, target = tonumber(score), tonumber(target)
	if not score or not target or target <= 0 then return { level = 0, burst = 8, peak = 1.2, extraHold = 0 } end
	local ratio = score / target
	for _, l in ipairs(LEVELS) do
		if ratio >= l.min then return { level = l.level, burst = l.burst, peak = l.peak, extraHold = l.extraHold } end
	end
	return { level = 0, burst = 8, peak = 1.2, extraHold = 0 }
end

return M
