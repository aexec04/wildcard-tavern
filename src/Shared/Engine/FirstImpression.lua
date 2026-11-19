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
