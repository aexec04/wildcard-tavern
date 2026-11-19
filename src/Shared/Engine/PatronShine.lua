--[[
	Shared/Engine/PatronShine.lua
	Pure numbers (tested) for the idle rarity glow and the Legendary shine on Patron cards. Client/PatronShineFX plays them.

	  PatronShine.glow(tier, calm) -> nil for Common and Uncommon and in calm mode, else
	      { rgb = {r,g,b}, period = 3, alphaMin = 0.15, alphaMax = 0.35, transMin, transMax, grow }
	      alpha is the glow's opacity, trans is the same as BackgroundTransparency (1 - alpha); one half period is one Sine tween
	  PatronShine.shine(tier, calm) -> nil unless Legendary and not calm, else
	      { period = 6, dur = 0.7, angle = 20, width = 0.16, transparency = 0.75, fromX, toX }   a diagonal band every `period` s
	Calm mode and Reduce motion arrive here as `calm` (ClientSettings reduceShake): no glow and no shine, so no tweens.
]]

local PatronMotion = require(script.Parent.PatronMotion)

local M = {}

M.GLOW_TIERS = { rare = true, epic = true, legendary = true }
M.PERIOD = 3
M.ALPHA_MIN, M.ALPHA_MAX = 0.15, 0.35
M.SHINE_PERIOD = 6

local function norm(tier)
	return tostring(tier or ""):lower()
end

function M.glow(tier, calm)
	local t = norm(tier)
	if calm or not M.GLOW_TIERS[t] then return nil end
	return {
		rgb = PatronMotion.glowOf(t), period = M.PERIOD,
		alphaMin = M.ALPHA_MIN, alphaMax = M.ALPHA_MAX,
		transMin = 1 - M.ALPHA_MAX, transMax = 1 - M.ALPHA_MIN,
		grow = 6, -- px the glow rim extends past the card on each axis
	}
end

function M.shine(tier, calm)
	if calm or norm(tier) ~= "legendary" then return nil end
	return { period = M.SHINE_PERIOD, dur = 0.7, angle = 20, width = 0.16, transparency = 0.75, fromX = -0.25, toX = 1.25 }
end

-- the delay before a seat's first sweep, so five Legendary cards do not flash together (seat index 1 to 8)
function M.shineOffset(seat)
	return ((tonumber(seat) or 1) % 5) * 0.9
end

return M
