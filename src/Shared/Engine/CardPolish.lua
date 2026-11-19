--[[
	CardPolish: pure rules for the physical feel of cards (no Roblox calls).

	CardPolish.shadow(selected) -> { layers = { { w, h, dy, transparency } x3 }, alpha }
	    A contact shadow as three stacked soft frames (a blur look without an image). A resting card casts a 0.25 alpha core;
	    a selected card casts a larger one (wider, taller, further down) that is a little fainter at the core.
	CardPolish.deckSteps(remaining, total) -> 0..4   thickness steps of the deck stack: 4 above 75 percent, 3 above 50,
	    2 above 25, 1 while any card is left, 0 when empty. Never rises as cards are drawn.
	CardPolish.deckEdge(steps) -> { { dy, shade } ... }  one edge line per step, drawn under the book's bottom edge
	CardPolish.tilt(key) -> degrees in [-1, 1], the same for the same key every call (stable per card)
]]
local CardPolish = {}

CardPolish.MAX_TILT = 1
CardPolish.DECK_STEPS = 4
CardPolish.REST_ALPHA = 0.25

local function clamp(x, lo, hi) return math.max(lo, math.min(hi, x)) end

function CardPolish.shadow(selected)
	local a = CardPolish.REST_ALPHA
	if selected then
		-- larger and a touch softer at the core; outer layers reach further
		return { alpha = a, layers = {
			{ w = 1.12, h = 26, dy = 12, transparency = 0.94 },
			{ w = 0.98, h = 20, dy = 10, transparency = 0.88 },
			{ w = 0.84, h = 14, dy = 8,  transparency = 0.8 },
		} }
	end
	return { alpha = a, layers = {
		{ w = 1.0,  h = 16, dy = 7, transparency = 0.94 },
		{ w = 0.88, h = 12, dy = 6, transparency = 0.86 },
		{ w = 0.74, h = 8,  dy = 5, transparency = 1 - a }, -- core: 0.25 alpha
	} }
end

function CardPolish.deckSteps(remaining, total)
	remaining = math.max(0, tonumber(remaining) or 0)
	total = math.max(1, tonumber(total) or 52)
	if remaining <= 0 then return 0 end
	local f = clamp(remaining / total, 0, 1)
	if f > 0.75 then return 4 end
	if f > 0.5 then return 3 end
	if f > 0.25 then return 2 end
	return 1
end

function CardPolish.deckEdge(steps)
	local out = {}
	steps = clamp(math.floor(tonumber(steps) or 0), 0, CardPolish.DECK_STEPS)
	for i = 1, steps do
		-- 2 px per step; each lower line is a little darker (card edges in shade)
		out[i] = { dy = (i - 1) * 2, shade = clamp(0.8 - i * 0.1, 0.3, 0.8) }
	end
	return out
end

-- stable hash of a number or string to [-MAX_TILT, MAX_TILT]
function CardPolish.tilt(key)
	local h = 7
	local s = tostring(key)
	for i = 1, #s do
		h = (h * 131 + s:byte(i) * 17 + i) % 1000003 -- plain arithmetic: runs the same in Lua 5.3 and Luau
	end
	local u = (h % 2001) / 1000 - 1 -- -1 .. 1
	return u * CardPolish.MAX_TILT
end

return CardPolish
