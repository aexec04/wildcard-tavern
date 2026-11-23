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
-- The words around Skip, one line each: the button says what it does, the dialog says where to replay it, one hold confirms.
TutorialStart.SKIP_TEXT = "Skip tutorial"
TutorialStart.SKIP_TITLE = "Skip the tutorial?"
TutorialStart.SKIP_MESSAGE = "You can replay it any time from Settings."
TutorialStart.SKIP_HOLD = "Hold to Skip"
TutorialStart.SKIP_WIDTH = 150
TutorialStart.SKIP_MARGIN = 24
TutorialStart.SKIP_TOP = 84
function TutorialStart.skipLayout(viewW, viewH)
	local scale = math.max(0.75, math.min(1, math.min(viewW / 1280, viewH / 720)))
	return { right = TutorialStart.SKIP_MARGIN, top = TutorialStart.SKIP_TOP, scale = scale, width = TutorialStart.SKIP_WIDTH, height = 44, minTouch = 44 }
end

return TutorialStart
