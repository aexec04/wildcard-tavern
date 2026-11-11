--[[
	Engine/PostBoss.lua
	Pure wording for the Counter after a Boss Round was cleared. The server keeps nightBossModifier and bossModifier on the
	state until the next Night starts, so the Counter must not announce that boss as upcoming and the sidebar must not
	keep showing its rule.

	  PostBoss.cleared(state)         true in the shop right after a Boss Round was cleared
	  PostBoss.shopBanner(state)      the Counter chip line: "Next boss: ..." before the boss, "Night 2 begins next." after
	  PostBoss.sidebarHeader(state)   the sidebar header line ("Night 1/8 · Round 3", or "Night 1 cleared")
	  PostBoss.sidebarRule(state)     the sidebar rule lines (title, text) after a cleared boss
]]

local PostBoss = {}

function PostBoss.cleared(state)
	if type(state) ~= "table" then return false end
	return state.phase == "shop" and (state.isBossRound == true or state.bossModifier ~= nil)
end

function PostBoss.shopBanner(state, scout)
	if PostBoss.cleared(state) then
		local nextNight = math.floor(state.night or 1) + 1
		local cap = state.nightCap
		if cap and nextNight > cap and not state.endless then
			return "Last Night cleared. The road ends here."
		end
		return string.format("Night %d begins next.", nextNight)
	end
	if scout then
		return "  Next boss: " .. tostring(scout.name) .. ". " .. tostring(scout.line or "")
	end
	return nil
end

function PostBoss.sidebarHeader(state)
	if PostBoss.cleared(state) then
		return string.format("Night %d cleared", math.floor(state.night or 1))
	end
	return nil
end

function PostBoss.sidebarRule(state)
	if PostBoss.cleared(state) then
		return "Boss beaten", "No special rules until the next Night."
	end
	return nil
end

return PostBoss
