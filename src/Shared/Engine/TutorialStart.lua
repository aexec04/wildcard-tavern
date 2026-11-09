--[[
	Engine/TutorialStart.lua
	Rules for the tutorial run. It starts ONLY from the Tutorial tile on the main menu (server remote
	StartTutorial). First launch, Play, New Run, Daily, Weekly and Seed never start it. A tutorial run
	is scripted and isolated: it never writes the player's profile (stats, keys, discoveries, rewards).
]]

local TutorialStart = {}

-- The scripted stage a new session begins at: 1 only for an explicit tutorial run, never for seeded modes.
function TutorialStart.initialStage(isTutorial, seeded)
	if isTutorial == true and not seeded then
		return 1
	end
	return nil
end

-- Does this session write to the player's profile? A tutorial run does not.
function TutorialStart.writesProfile(session)
	return not (session and session.isTutorial == true)
end

-- Does the Tutorial tile show its "New" ribbon and glow? Until completed once or dismissed.
function TutorialStart.showNewRibbon(profile, dismissed)
	if dismissed then
		return false
	end
	return not (profile and profile.hasSeenTutorial == true)
end

return TutorialStart
