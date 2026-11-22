--[[
	Shared/Engine/ClaimMoment.lua
	What a reward claim (Season tier, Daily chest, login streak) looks and sounds like. Pure Lua, no Roblox APIs.

	ClaimMoment.plan(setId, calm) -> { cue = "reward_claim", glow = nil | { color = {r,g,b}, seconds = 0.4 } }
	  cue    the existing claim sound, always (Cue already honours Sound off and Mute)
	  glow   a 0.4 s outline flash in the equipped Card Set accent (gold for classic or an unknown set), lightened until it keeps 3:1
	         on the dark wood; nil in Calm mode (no tween at all)
]]

local CosmeticSets = require(script.Parent.CosmeticSets)

local ClaimMoment = {}

ClaimMoment.CUE = "reward_claim"
ClaimMoment.GLOW_SECONDS = 0.4

function ClaimMoment.plan(setId, calm)
	local plan = { cue = ClaimMoment.CUE }
	if not calm then
		plan.glow = { color = CosmeticSets.focusRingOf(setId), seconds = ClaimMoment.GLOW_SECONDS }
	end
	return plan
end

return ClaimMoment
