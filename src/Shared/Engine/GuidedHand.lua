--[[
	Shared/Engine/GuidedHand.lua
	The short guided first hand (Backlog 8, option b). A brand new profile's first normal run starts with one fixed starter
	Patron and no blessing draft, and the play screen shows a two line hint that points at one card, then at Play Hand, until
	the first hand is played. The 24 step tutorial is separate and untouched.

	GuidedHand.STARTER                   id of the fixed starter Patron
	GuidedHand.isGuided(runsStarted, seeded, rush, tutorial) -> bool   true only for the first normal run of a profile
	GuidedHand.apply(state) -> ok        seats the starter Patron (RunState.grantPatron), nothing else
	GuidedHand.hint(guided, handsPlayed, selectedCount, calm) -> nil | { line1, line2, target = "card" | "play", pulse }
]]

local M = {}

M.STARTER = "the_regular" -- +4 Mult on every hand, easy to read, painted card exists

function M.isGuided(runsStarted, seeded, rush, tutorial)
	if seeded or rush or tutorial then return false end
	return type(runsStarted) == "number" and runsStarted <= 1
end

function M.apply(state)
	local RunState = require(script.Parent.RunState)
	local ok = RunState.grantPatron(state, M.STARTER)
	if ok then state.startPatronId = M.STARTER end
	return ok
end

function M.hint(guided, handsPlayed, selectedCount, calm)
	if not guided or (tonumber(handsPlayed) or 0) >= 1 then return nil end
	if (tonumber(selectedCount) or 0) < 1 then
		return { line1 = "Tap a card to pick it.", line2 = "Pick up to five cards.", target = "card", pulse = not calm }
	end
	return { line1 = "Now press Play Hand.", line2 = "Your best hand scores.", target = "play", pulse = not calm }
end

return M
