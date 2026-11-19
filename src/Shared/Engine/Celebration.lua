--[[
	Shared/Engine/Celebration.lua
	Pure numbers (tested) for the round clear, win and defeat moments. Client/CelebrationFX plays them. Calm mode and
	Reduce motion pass calm = true and get nil (the end state is simply shown), so nothing tweens or loops.

	Celebration.countSteps(total, calm) -> nil | { values = {...}, step }   Tips count up one coin at a time (at most 12 steps)
	Celebration.bannerSlide(calm)       -> nil | { dur = 0.4, dy = 16 }      the gold banner slides down into place
	Celebration.patronHopDelay(i, calm) -> nil | seconds                      Patron i (from 1) hops after the ones before it
	Celebration.confetti(seed, calm)    -> nil | { dur = 2.5, pieces = {...} } 40 gold and red card-suit shapes
	Celebration.titleIn(calm)           -> nil | { from, peak, dur }          the win title scales in with a slight overshoot
	Celebration.defeat(calm)            -> nil | { saturation = 0.6, tint, dur = 0.8 }  gentle grey wash, no shake
	Celebration.defeatTitle / TRY_AGAIN the calm retry wording
]]

local M = {}

M.COUNT_STEP = 0.07
M.MAX_STEPS = 12
M.BANNER_SECONDS = 0.4
M.HOP_STEP = 0.12
M.CONFETTI_COUNT = 40
M.CONFETTI_SECONDS = 2.5
M.TITLE_FROM, M.TITLE_PEAK, M.TITLE_SECONDS = 0.6, 1.08, 0.5
M.DEFEAT_SATURATION, M.DEFEAT_SECONDS = 0.6, 0.8
M.TRY_AGAIN = "Try Again"
M.SUITS = { "\u{2660}", "\u{2665}", "\u{2666}", "\u{2663}" } -- spade, heart, diamond, club
M.GOLD = { 246, 196, 70 }
M.RED = { 214, 70, 64 }

function M.countSteps(total, calm)
	total = math.floor(tonumber(total) or 0)
	if calm or total <= 0 then return nil end
	local n = math.min(total, M.MAX_STEPS)
	local values = {}
	for i = 1, n do values[i] = math.ceil(total * i / n) end
	values[n] = total
	return { values = values, step = M.COUNT_STEP }
end

function M.bannerSlide(calm)
	if calm then return nil end
	return { dur = M.BANNER_SECONDS, dy = 16 }
end

function M.patronHopDelay(i, calm)
	if calm or type(i) ~= "number" or i < 1 then return nil end
	return (i - 1) * M.HOP_STEP
end

local function lcg(seed)
	local s = (seed or 1) % 2147483647
	if s <= 0 then s = s + 2147483646 end
	return function()
		s = (s * 16807) % 2147483647
		return s / 2147483647
	end
end

function M.confetti(seed, calm)
	if calm then return nil end
	local rnd = lcg(seed)
	local pieces = {}
	for i = 1, M.CONFETTI_COUNT do
		local red = i % 2 == 0
		pieces[i] = {
			glyph = M.SUITS[(i - 1) % #M.SUITS + 1],
			color = red and M.RED or M.GOLD,
			x = 0.05 + 0.9 * rnd(),
			delay = rnd() * 0.6,
			fall = 1.6 + rnd() * 0.3, -- every piece lands before dur
			sway = (rnd() - 0.5) * 120,
			spin = (rnd() - 0.5) * 360,
			size = 18 + math.floor(rnd() * 10),
		}
	end
	return { dur = M.CONFETTI_SECONDS, pieces = pieces }
end

function M.titleIn(calm)
	if calm then return nil end
	return { from = M.TITLE_FROM, peak = M.TITLE_PEAK, dur = M.TITLE_SECONDS }
end

function M.defeat(calm)
	if calm then return nil end
	-- the room goes to 0.6 saturation: a grey wash whose strength is 1 - saturation
	return { saturation = M.DEFEAT_SATURATION, tint = 1 - M.DEFEAT_SATURATION, dur = M.DEFEAT_SECONDS }
end

return M
