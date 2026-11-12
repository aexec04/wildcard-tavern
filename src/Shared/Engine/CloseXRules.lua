--[[
	Engine/CloseXRules.lua
	Pure geometry for the shared round close X (Client/CloseX.lua): a 40 px painted disc inside a hit area of at least 44 px, in a panel
	corner, never outside the panel. No Roblox types.

	rect(panelW, panelH, corner, inset, top) -> { x, y, w, h } of the 44 px hit area inside the panel (corner "topRight" or "topLeft")
	discRect()                               -> the 40 px disc centred in the hit area, relative to it
	fits(panelW, panelH, corner, inset, top) -> true when the X is fully inside a panel of that size
]]

local M = {}

M.DISC = 40
M.HIT = 44
M.INSET = 8

function M.rect(pw, ph, corner, inset, top)
	inset = inset or M.INSET
	top = top or inset
	local x = pw - M.HIT - inset
	if corner == "topLeft" then x = inset end
	return { x = x, y = top, w = M.HIT, h = M.HIT }
end

function M.discRect()
	local o = math.floor((M.HIT - M.DISC) / 2)
	return { x = o, y = o, w = M.DISC, h = M.DISC }
end

function M.fits(pw, ph, corner, inset, top)
	local r = M.rect(pw, ph, corner, inset, top)
	return r.x >= 0 and r.y >= 0 and r.x + r.w <= pw and r.y + r.h <= ph and r.w >= 44 and r.h >= 44
end

return M
