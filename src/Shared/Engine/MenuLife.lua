--[[
	Shared/Engine/MenuLife.lua
	Pure numbers (tested) for the main menu's warm entrance. Client/MenuLifeFX plays them. Calm mode and Reduce motion pass
	calm = true and get the resting value (or nil), so nothing moves or tweens.

	MenuLife.logo(elapsed, calm)   -> { rise, alpha }  rise = pixels still to climb (16 -> 0 over 0.5 s), alpha 0 -> 1
	MenuLife.PULSE_SCALE, PULSE_PERIOD   the Play sign grows 1.0 -> 1.03 and back every 2.5 s
	MenuLife.hoverLift(calm)       -> nil | 4   pixels a menu button rises on hover
	MenuLife.TIPS, TIP_SECONDS     twelve short family friendly tips (60 characters or less), one shown at a time, rotating every 6 s
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
	-- twelve tips, each 60 characters or less, all different, so the line never shows the same one twice in a row (it wraps cleanly too)
	"Tip: Patrons seated side by side can share bonuses.",
	"Tip: A Flush is five cards of one suit.",
	"Tip: Discard what you do not need to dig for a better hand.",
	"Tip: A Full House scores far more than a Pair.",
	"Tip: Visit The Counter between rounds to hire Patrons.",
	"Tip: Spare Tips earn a little interest, so save a few.",
	"Tip: A Straight is five ranks in a row, like 4 to 8.",
	"Tip: Tap Today's twist to see how the day plays.",
	"Tip: A Boss Round bends one rule. Read it first.",
	"Tip: Hand levels make your favourite hands score more.",
	"Tip: Sort by Rank or Suit to spot a pair or a flush.",
	"Tip: A hand can use up to five cards, so pick your best.",
}

-- The tip stands on a small plate in the bottom left corner, level with All actions (bottom right) and clear of the Deal Me In
-- sign and New Run plaque that hang in the centre column (340 px wide). Returns nil when there is no room for one line.
M.TIP_MARGIN, M.TIP_PLATE_H, M.TIP_MAX_W, M.TIP_MIN_W, M.TIP_SIGN_HALF, M.TIP_GAP = 16, 56, 520, 240, 170, 16
function M.tipRect(width, height)
	width, height = tonumber(width) or 0, tonumber(height) or 0
	if height ~= 0 and height < M.TIP_MIN_HEIGHT then return nil end
	local w = math.min(M.TIP_MAX_W, width / 2 - M.TIP_SIGN_HALF - M.TIP_GAP - M.TIP_MARGIN)
	if w < M.TIP_MIN_W then return nil end
	return { x = M.TIP_MARGIN, y = height - M.TIP_MARGIN - M.TIP_PLATE_H, w = w, h = M.TIP_PLATE_H }
end

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
