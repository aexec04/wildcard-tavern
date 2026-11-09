--[[
	RunModes.lua
	Run modes as plain configuration, so a full run and every seeded fair board stay untouched (they pass no mode).

	Quick Run (phone sessions): 4 Nights instead of 8. Target difficulty follows the SAME curve as a full run,
	compressed: Night n of 4 is scored like Night 1 + (n - 1) * 7 / 3 of 8, so the last Night matches Night 8.
	Night 1 is a gentle opener (targets scaled by firstNightScale). Always stake 1. Rewards are about half
	(Tavern XP scaled by xpScale), and a Quick Run never moves records: no stake stamps, no Night or boss-clear
	titles, no Journey rewards, no leaderboard. It still counts for daily quests and run history, and keeps
	its own best score (profile.quickBest).
	Pure Lua, no Roblox APIs.
]]

local RunModes = {}

RunModes.Modes = {
	quick = {
		id = "quick",
		name = "Quick Run",
		icon = "⚡",
		hint = "4 Nights. About 15 minutes.",
		nights = 4,
		fullNights = 8, -- the Night count whose last Night this mode compresses onto
		targetScale = 0.19, -- the whole curve is eased: a Quick Run gives only 4 shop visits to build a deck
		firstNightScale = 0.7,
		xpScale = 0.5,
	},
}

function RunModes.get(id)
	return RunModes.Modes[id]
end

-- True for a mode id the server accepts from a client.
function RunModes.isValid(id)
	return type(id) == "string" and RunModes.Modes[id] ~= nil
end

-- The full-run Night whose difficulty `night` of this mode is scored like (fractional). Unknown mode: the Night itself.
function RunModes.equivalentNight(modeId, night)
	local mode = RunModes.Modes[modeId]
	if not mode then
		return night
	end
	return 1 + (night - 1) * (mode.fullNights - 1) / (mode.nights - 1)
end

-- Extra target factor for this mode on this Night (1 for a normal run).
function RunModes.targetScale(modeId, night)
	local mode = RunModes.Modes[modeId]
	if not mode then
		return 1
	end
	return mode.targetScale * (night == 1 and mode.firstNightScale or 1)
end

-- Tavern XP factor of a mode.
function RunModes.xpScale(modeId)
	local mode = RunModes.Modes[modeId]
	return mode and mode.xpScale or 1
end

return RunModes
