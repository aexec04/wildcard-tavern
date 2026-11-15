--[[
	Engine/RevealHold.lua
	The hand that ends a round (or the run) is the best moment of that round, and it used to be the one hand whose
	score reveal nobody saw: the server answers "the round is over" in the same message as the score, the client drew
	the next screen at once (the Counter, Run Over, the next boss) and that cancelled the reveal in the frame it began.

	The rule (pure, tested; Client/RevealHold applies it): when a reveal has just started for a hand whose state is no
	longer "playing", the table stays up until the reveal has landed, and only then is the new state drawn. Nothing is
	delayed on the server and nothing about the run changes: this is only when the next screen appears.

	  RevealHold.holds(revealStarted, newPhase) -> bool
	  RevealHold.MAX_SECONDS                     a reveal that never reports back cannot keep the next screen away
]]

local RevealHold = {}

-- Longer than the slowest real reveal (eight entries a second apart, their pauses, the finale and its linger at the
-- normal animation speed), and the same order as the score popup's own last-resort clean-up (12 s).
RevealHold.MAX_SECONDS = 12

function RevealHold.holds(revealStarted, newPhase)
	return revealStarted == true and type(newPhase) == "string" and newPhase ~= "playing"
end

return RevealHold
