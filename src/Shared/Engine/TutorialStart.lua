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

-- Where the Skip button sits: top right, at least 24px inside the screen edge (the gold border), below the
-- corner icon row (12..66) and the Tips chip (18..52) with an 18px gap, scaled down on small screens.
TutorialStart.SKIP_MARGIN = 24
TutorialStart.SKIP_TOP = 84
function TutorialStart.skipLayout(viewW, viewH)
	local scale = math.max(0.75, math.min(1, math.min(viewW / 1280, viewH / 720)))
	return { right = TutorialStart.SKIP_MARGIN, top = TutorialStart.SKIP_TOP, scale = scale, width = 92, height = 36 }
end

return TutorialStart
