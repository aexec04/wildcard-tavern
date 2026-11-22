--[[
	Shared/Engine/FirstImpression.lua
	The path from the Menu to the first played hand, as data, so a test can hold it to a short length.
	Every step is one tap on one obvious primary plate and there is no extra confirm screen in between.
	(The Night intro plate is timed, not a tap, so it is not a step.)

	FirstImpression.PATH                   ordered steps { id, plate, taps }
	FirstImpression.MAX_TAPS               the budget: 6 taps from the Menu to the first played hand
	FirstImpression.tapsToFirstHand(cards) total taps when the player picks `cards` hand cards (the guided hint asks for 2)
	FirstImpression.confirmSteps()         ids of steps that are only a confirm (must stay empty)
]]

local M = {}

M.MAX_TAPS = 6
M.PATH = {
	{ id = "menu", plate = "Deal Me In", taps = 1 },
	{ id = "run_setup", plate = "Begin Run", taps = 1 },
	{ id = "night_map", plate = "Play this round", taps = 1 },
	-- Night intro plate: timed (1.2 s), a tap only skips it
	{ id = "pick_cards", plate = "hand cards", taps = 2, perCard = true },
	{ id = "play", plate = "Play Hand", taps = 1 },
}

-- Longest stretch with nothing to do or no pointer, in seconds, for each wait on the way to Night 1 cleared (estimates from the timers and hint rules, not measured in Studio).
-- A test holds every one under MAX_IDLE.
M.MAX_IDLE = 20
M.IDLE = {
	{ id = "night_intro", seconds = 1.2, note = "timed plate, a tap skips it" },
	{ id = "travel_cover", seconds = 3, note = "TravelTiming.MAX, a tap skips after 0.5 s" },
	{ id = "first_hand_to_play", seconds = 12, note = "guided hint points at the cards, then Play Hand" },
	{ id = "after_first_hand", seconds = 15, note = "guided follow-up lines for hands 2 and 3 (was unguided)" },
	{ id = "round_won_to_counter", seconds = 6, note = "round clear banner, then the Counter opens with a first_counter hint" },
}

function M.tapsToFirstHand(cards)
	local total = 0
	for _, s in ipairs(M.PATH) do
		if s.perCard then
			total = total + math.max(1, tonumber(cards) or 2)
		else
			total = total + s.taps
		end
	end
	return total
end

function M.confirmSteps()
	local out = {}
	for _, s in ipairs(M.PATH) do
		if s.confirm then out[#out + 1] = s.id end
	end
	return out
end

return M
