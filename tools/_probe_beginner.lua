-- Beginner probe: a brand new player's first run. Welcome ease on, the guided starter Patron seated, no shopping, no discards.
--   "highlight": plays the cards the first hand guide outlines (GuidedHand.bestPlay) every hand
--   "first five": plays the first five cards dealt, never looking at them
-- Run: lua tools/_probe_beginner.lua [seeds]   Prints the clear rate of Night 1 and Night 2.
package.path = "tools/sim/?.lua;" .. package.path
local L = require("EngineLoader")
local e = L.load("src/Shared")
local Guided = e.loadEngineModule("GuidedHand")
local N = tonumber(arg and arg[1]) or 200

local function trial(style)
	local clears = { 0, 0 }
	for seed = 1, N do
		local state = e.RunState.new({ welcomeEase = true }, e.SeededRng.new(seed))
		Guided.apply(state)
		local ok = true
		while ok and state.night <= 2 do
			local guard = 0
			while not state.roundOver and not state.runOver and guard < 12 do
				guard = guard + 1
				local pick = {}
				if style == "highlight" then
					local best = Guided.bestPlay(state.hand)
					pick = best and best.indices or { 1 }
				else
					for i = 1, math.min(5, #state.hand) do pick[i] = i end
				end
				e.RunState.playHand(state, pick)
			end
			if state.runOver or not (state.roundScore >= state.targetScore) then ok = false break end
			if state.round == 3 then clears[state.night] = clears[state.night] + 1 end
			e.RunState.advanceToNextRound(state)
		end
	end
	print(string.format("%-11s Night 1 clear %5.1f%%   Night 2 clear %5.1f%%   (%d seeds)", style, 100 * clears[1] / N, 100 * clears[2] / N, N))
end

trial("highlight")
trial("first five")
