--[[
	Funnel.lua
	The "first 5 minutes" funnel as data, plus the once-per-player bookkeeping. Pure Lua, no Roblox APIs.
	Engine/Analytics.lua sends these steps to Roblox AnalyticsService; this module only decides which step is
	new for a profile, so a step is logged once for the whole life of a player (profile.funnelSeen).

	Steps, in order:
		1 menu_shown          the player reached the main menu
		2 tutorial_started    the tutorial run began
		3 tutorial_finished   the tutorial was completed (not skipped)
		4 first_hand_played   the first hand of a normal run
		5 first_round_won     the first round cleared
		6 first_shop_visit    the Counter opened for the first time
		7 first_run_ended     the first run ended (win or loss)
		8 second_run_started  the player came back for another run
]]

local Funnel = {}

Funnel.NAME = "FirstFiveMinutes"

Funnel.Steps = {
	"menu_shown", "tutorial_started", "tutorial_finished", "first_hand_played",
	"first_round_won", "first_shop_visit", "first_run_ended", "second_run_started",
}

local INDEX = {}
for i, id in ipairs(Funnel.Steps) do
	INDEX[id] = i
end

function Funnel.indexOf(stepId)
	return INDEX[stepId]
end

-- Marks a step as logged for this profile. Returns its step number when it is new, nil when it was already
-- logged or is not a step.
function Funnel.markIfNew(profile, stepId)
	local index = INDEX[stepId]
	if not index then
		return nil
	end
	profile.funnelSeen = profile.funnelSeen or {}
	if profile.funnelSeen[stepId] then
		return nil
	end
	profile.funnelSeen[stepId] = true
	return index
end

-- Cleans a saved set: only known step ids survive.
function Funnel.clean(raw)
	local out = {}
	if type(raw) == "table" then
		for id, flag in pairs(raw) do
			if flag == true and INDEX[id] then
				out[id] = true
			end
		end
	end
	return out
end

return Funnel
