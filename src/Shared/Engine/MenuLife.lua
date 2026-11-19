--[[
	Shared/Engine/MenuLife.lua
	Pure numbers (tested) for the main menu's warm entrance. Client/MenuLifeFX plays them. Calm mode and Reduce motion pass
	calm = true and get the resting value (or nil), so nothing moves or tweens.

	MenuLife.logo(elapsed, calm)   -> { rise, alpha }  rise = pixels still to climb (16 -> 0 over 0.5 s), alpha 0 -> 1
	MenuLife.PULSE_SCALE, PULSE_PERIOD   the Play sign grows 1.0 -> 1.03 and back every 2.5 s
	MenuLife.hoverLift(calm)       -> nil | 4   pixels a menu button rises on hover
	MenuLife.TIPS, TIP_SECONDS     six short family friendly tips, one shown at a time, rotating every 6 s
	MenuLife.tipAt(elapsed)        -> tip text for the seconds since the menu opened
	MenuLife.TIP_MIN_HEIGHT        the tip line is left out of screens shorter than this
]]

local M = {}

M.LOGO_RISE = 16
M.LOGO_SECONDS = 0.5
M.PULSE_SCALE = 1.03
M.PULSE_PERIOD = 2.5
M.HOVER_LIFT = 4
M.HOVER_SECONDS = 0.1
M.TIP_SECONDS = 6
M.TIP_MIN_HEIGHT = 500

M.TIPS = {
	"Tip: Patrons next to each other can share bonuses.",
	"Tip: A Flush needs five cards of one suit.",
	"Tip: Discard cards you do not need to dig for a better hand.",
	"Tip: Higher hands like a Full House score far more than a Pair.",
	"Tip: Visit The Counter between rounds to hire new Patrons.",
	"Tip: Save a few Tips. Spare coins earn a little interest.",
}

function M.logo(elapsed, calm)
	if calm then return { rise = 0, alpha = 1 } end
	local p = math.min(1, math.max(0, (tonumber(elapsed) or 0) / M.LOGO_SECONDS))
	local e = 1 - (1 - p) * (1 - p) -- ease out
	return { rise = M.LOGO_RISE * (1 - e), alpha = e }
end

function M.hoverLift(calm)
	if calm then return nil end
	return M.HOVER_LIFT
end

function M.tipAt(elapsed)
	local n = #M.TIPS
	local i = math.floor(math.max(0, tonumber(elapsed) or 0) / M.TIP_SECONDS) % n
	return M.TIPS[i + 1]
end

return M
