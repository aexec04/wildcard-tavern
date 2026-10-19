--[[
	TrueWildcard.lua
	PHASE C (Signature Mechanic, see claude/mind-blowing-plan.md): the "True
	Wildcard" card. Exactly one real card in a run's deck is seeded as a
	True Wildcard (card.isTrueWildcard = true, card.wildcardLocked = false
	-- see RunState.new). It keeps its ordinary dealt rank/suit right up
	until the FIRST time it's actually played -- at that moment, this
	module figures out which rank+suit would score the MOST for that exact
	hand (trying all 52 real rank/suit combinations and picking the best),
	and the card permanently becomes that card for the rest of the run.
	wildcardLocked flips true the instant it resolves (see
	RunState.playHand) -- same card table reference the whole run, like
	every other card (see RunState.new's own header on cards never being
	regenerated), so after this it just IS whatever it became.

	Pure Lua, no Roblox APIs. findBestChoice below is a non-mutating search
	-- it tries every combination on the real card object (so any Garnish/
	Special/Stamp already on it keeps applying normally during the search)
	but always restores its ORIGINAL rank/suit before returning, leaving it
	exactly as the caller found it. That makes it safe to call from BOTH
	the server's authoritative RunState.playHand AND the client's own
	computeHandPreview (Client/init.client.lua) for a live, accurate
	preview -- repeatedly, on every selection change, with nothing left
	behind -- since both are deterministic given the same cards/context and
	will always agree on the same winning rank+suit. The actual COMMIT
	(setting the card's real rank/suit and wildcardLocked = true) is each
	caller's own responsibility, done once, only when a hand is truly
	played for real -- see RunState.playHand's own comment.
]]

local Card = require(script.Parent.Card)
local HandEvaluator = require(script.Parent.HandEvaluator)
local Scoring = require(script.Parent.Scoring)

local TrueWildcard = {}

-- A deterministic "never lucky" rng used ONLY while comparing the 52
-- candidates against each other -- a real Lucky Garnish/Brittle Garnish
-- proc landing on one candidate and not another would make the comparison
-- noisy (the "best" pick would depend on dice, not on which rank/suit is
-- actually best) instead of a clean, repeatable comparison. Every oneInN
-- check in Scoring.lua's chanceHits uses N > 1 and only hits when
-- rng(N) == 1 -- returning N itself therefore always misses, for any N.
-- (The REAL hand this card ends up part of still scores with the run's
-- real rng afterward, same as always -- this is comparison-only.)
local function noLuckRng(n)
	return n
end

--[[
	cards: the full set of played cards (array), exactly as HandEvaluator.
	       evaluate/Scoring.calculate expect.
	wildcardCard: one specific entry of `cards` (by reference) whose rank/
	       suit this tries all 52 combinations for.
	ownedPatrons: passed straight through to Scoring.calculate.
	buildContext(candidateHandResult): called once per candidate with the
	       hand HandEvaluator.evaluate(cards) produces for that candidate's
	       rank/suit -- must return the Scoring.calculate `context` table
	       to score it with, or nil to treat this candidate as a flat 0
	       (e.g. a "No Repeats" Boss Round blocking that hand type). This
	       function always overrides whatever `context.rng` comes back
	       with the deterministic noLuckRng above, so the caller doesn't
	       need to (and nothing it sets there matters).

	Returns: bestRank, bestSuit, bestHandResult, bestScore -- bestHandResult
	is ONLY safe to read primitive fields off (e.g. .name) by the time this
	returns; its .scoringCards reference the SAME card objects passed in,
	which are back to their ORIGINAL rank/suit by then (see above) -- a
	caller that wants a HandEvaluator result reflecting the winning choice
	should commit bestRank/bestSuit for real and re-run
	HandEvaluator.evaluate itself (see RunState.playHand).
]]
function TrueWildcard.findBestChoice(cards, wildcardCard, ownedPatrons, buildContext)
	local originalRank, originalSuit = wildcardCard.rank, wildcardCard.suit
	local bestScore, bestRank, bestSuit, bestHandResult = -1, originalRank, originalSuit, nil

	for _, suit in ipairs(Card.Suits) do
		for rank = 2, 14 do
			wildcardCard.rank = rank
			wildcardCard.suit = suit
			local candidateHandResult = HandEvaluator.evaluate(cards)
			local score = 0
			local context = buildContext(candidateHandResult)
			if context then
				context.rng = noLuckRng
				score = (Scoring.calculate(candidateHandResult, ownedPatrons, context))
			end
			if score > bestScore then
				bestScore, bestRank, bestSuit, bestHandResult = score, rank, suit, candidateHandResult
			end
		end
	end

	wildcardCard.rank, wildcardCard.suit = originalRank, originalSuit
	return bestRank, bestSuit, bestHandResult, bestScore
end

return TrueWildcard
