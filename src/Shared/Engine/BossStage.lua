--[[
	Shared/Engine/BossStage.lua
	Pure style rules for a Boss Round's stage (tested), so the client has one place to read them.
	A boss round shows the painted boss as the backdrop of the play area. There is no boss health bar
	and nothing turns red: hits flash cream, enrage is a gold banner (no screen tint), defeat greys out.

	  style(isBoss, enraged, grand) -> table
	  isRedish(color3 like {r,g,b} 0-255) -> bool   (used by tests and the client to guard colours)
]]

local BossStage = {}

local CREAM = { 250, 235, 200 }
local GOLD = { 235, 180, 40 }

function BossStage.isRedish(c)
	local r, g, b = c[1], c[2], c[3]
	return r >= 150 and r > g * 1.6 and r > b * 1.6
end

function BossStage.style(isBoss, enraged, grand)
	if not isBoss then
		return { healthBar = false, backdrop = false, hitFlash = nil, rageTint = false, banner = nil, vignette = 0 }
	end
	return {
		healthBar = false, -- the left panel's target progress is the only score progress
		backdrop = true, -- the painted boss fills the centre/right of the play area
		hitFlash = CREAM, -- never red
		rageTint = false, -- no full-screen colour change while enraged
		banner = (enraged or grand) and GOLD or CREAM,
		vignette = grand and 0.6 or 0.5, -- dark edge/bottom fade behind the cards (0..1)
		swayAmp = 1.5, -- gentle on the large art
	}
end

return BossStage
