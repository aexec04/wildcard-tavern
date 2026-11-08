--[[
	Shared/Engine/ChallengeStart.lua
	When a Daily, Weekly or Seed Run can be started from the main menu (pure, tested). The tiles used to fail
	silently; every blocked state now has a one short reason line, and a run in progress asks first.

	check(ctx) -> verdict, line
	    verdict "start"    go ahead
	            "confirm"  a run is in progress: ask with the hold-to-confirm popup, then start
	            "blocked"  say `line` on the tile and do not start
	ctx = { hasState = bool (the server has sent its first state), phase, night, round,
	        tutorialActive = bool, traveling = bool }

	A run is "in progress" once it has left the fresh Round Select of Night 1 (or is being played); a finished run
	(Game Over) and a brand-new session never ask.
]]

local ChallengeStart = {}

ChallengeStart.Lines = {
	connecting = "Connecting to the tavern...",
	tutorial = "Finish the tutorial first",
	traveling = "One moment, traveling...",
}

function ChallengeStart.inProgress(ctx)
	if ctx.phase == nil or ctx.phase == "gameover" then
		return false
	end
	local fresh = ctx.phase == "roundSelect" and (ctx.night or 1) <= 1 and (ctx.round or 1) <= 1
	return not fresh
end

function ChallengeStart.check(ctx)
	ctx = ctx or {}
	if not ctx.hasState then
		return "blocked", ChallengeStart.Lines.connecting
	end
	if ctx.tutorialActive then
		return "blocked", ChallengeStart.Lines.tutorial
	end
	if ctx.traveling then
		return "blocked", ChallengeStart.Lines.traveling
	end
	if ChallengeStart.inProgress(ctx) then
		return "confirm", nil
	end
	return "start", nil
end

return ChallengeStart
