--[[
	Onboarding.lua
	Pure rules for helping new players. A player who never discards dies on
	Night 1 far more often than one who does, so the game teaches discarding
	early (Client/TutorialWalkthrough.lua), hints once after a wasted High
	Card, and gives brand-new profiles a little slack on Night 1.
]]

local Onboarding = {}

-- A profile gets the extra Night 1 discard for this many runs.
Onboarding.NEW_PLAYER_RUNS = 3
Onboarding.NEW_PLAYER_BONUS_DISCARDS = 1

Onboarding.HIGH_CARD_HINT = "Tip: High Card barely scores. Discard weak cards first, it costs a Discard, not a Hand."

-- Extra discards per round on Night 1. Always 0 on a seeded run (Daily,
-- Weekly, Seed Code), so those stay identical for every player.
function Onboarding.bonusDiscards(runsStarted, isSeeded)
	if isSeeded or type(runsStarted) ~= "number" then
		return 0
	end
	if runsStarted < Onboarding.NEW_PLAYER_RUNS then
		return Onboarding.NEW_PLAYER_BONUS_DISCARDS
	end
	return 0
end

-- Fires once per profile, on the first High Card played with a Discard to
-- spare. Waits until the tutorial is over so it can't talk over it.
function Onboarding.shouldShowHighCardHint(handName, discardsRemaining, profile)
	if not profile or profile.hasSeenHighCardHint or not profile.hasSeenTutorial then
		return false
	end
	return handName == "High Card" and discardsRemaining >= 1
end

return Onboarding
