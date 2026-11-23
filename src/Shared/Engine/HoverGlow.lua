--[[
	Engine/HoverGlow.lua
	The one hover and pick glow for Patron seats, hand cards, the Boss seat and shop offer cards, taken from the Round Select blind
	cards (Client/RoundSelectFX): the card grows about 1.04, the art brightens a little, the rim swells and a slow shine passes once.
	There is NO resting glow: at rest every part is hidden (Visible false) and fully transparent. Calm mode and Reduce motion keep only
	the rim (no grow, no brighten, no shine, no tween). Pure and tested; Client/HoverGlowFX draws it.

	plan(calm, strokeOnly) -> { scale, brightenT, rimThickness, rimT, shine, seconds, restSeconds }  what hover does (nothing animates in Calm)
	rest()                 -> { scale = 1, brightenT = 1, rimT = 1, visible = false }              what every card looks like at rest
]]

local M = {}

M.SCALE = 1.04          -- Round Select active card grow
M.SECONDS_IN = 0.18     -- same easing time as the blind cards
M.SECONDS_OUT = 0.2
M.BRIGHTEN_T = 0.9      -- cream wash over the art at hover (BackgroundTransparency): about 10 percent, so ink keeps 4.5:1
M.RIM_THICKNESS = 3
M.RIM_T = 0.25          -- gold rim at hover only
M.SHINE_SECONDS = 0.6

function M.rest()
	return { scale = 1, brightenT = 1, rimT = 1, visible = false }
end

function M.plan(calm, strokeOnly)
	local still = calm == true or strokeOnly == true
	return {
		scale = still and 1 or M.SCALE,
		brightenT = still and 1 or M.BRIGHTEN_T,
		rimThickness = M.RIM_THICKNESS,
		rimT = M.RIM_T,
		shine = not still,
		seconds = calm == true and 0 or M.SECONDS_IN,
		restSeconds = calm == true and 0 or M.SECONDS_OUT,
	}
end

return M
