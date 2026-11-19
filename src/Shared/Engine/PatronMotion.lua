--[[
	Shared/Engine/PatronMotion.lua
	Pure numbers (tested) for the Patron card entrance and the hover or tap lift. Client/PatronMotionFX plays them.

	  PatronMotion.entrance(tier, calm) -> nil when calm (the card just appears), else
	      { drop, bounce, dur, settle, glow = {r,g,b}, glowDur, rays }   rays is true for Legendary only
	  PatronMotion.hover(calm) -> { lift, pillScale, dur, animate }   the larger effect pill shows in calm mode too (static,
	      no tween: animate false, lift 0)
	  PatronMotion.isNew(oldId, newId) -> true when a card now holds a different Patron than before
]]

local M = {}

M.GLOW = {
	common = { 205, 145, 85 }, uncommon = { 110, 215, 120 }, rare = { 90, 170, 255 },
	epic = { 190, 120, 255 }, legendary = { 255, 205, 70 },
}

function M.glowOf(tier)
	return M.GLOW[tostring(tier or ""):lower()] or M.GLOW.common
end

function M.entrance(tier, calm)
	if calm then return nil end
	local t = tostring(tier or ""):lower()
	return {
		drop = -28, bounce = 6, dur = 0.26, settle = 0.12,
		glow = M.glowOf(t), glowDur = t == "legendary" and 0.7 or 0.45,
		rays = t == "legendary",
	}
end

function M.hover(calm)
	if calm then return { lift = 0, pillScale = 1.25, dur = 0, animate = false } end
	return { lift = 8, pillScale = 1.25, dur = 0.12, animate = true }
end

function M.isNew(oldId, newId)
	return newId ~= nil and newId ~= oldId
end

return M
