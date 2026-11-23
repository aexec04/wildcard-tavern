--[[
	Shared/Engine/Confetti.lua
	Pure, deterministic confetti spec (tested) for the round clear moment. Client/ConfettiFX draws it.

	  Confetti.count(calm, fast, big) -> number of pieces (0 in calm mode; fewer on Fast speed; more for a Boss clear)
	  Confetti.pieces(n, seed) -> { {x, vx, vy, spin, size, color = {r,g,b}, delay} ... }
	      x is a 0..1 fraction of the width the piece starts at, vx and vy are px per second (vy starts upward, gravity pulls it
	      down), colors alternate gold and purple tones, never one alone.
]]

local M = {}

M.PALETTE = {
	{ 255, 205, 70 }, { 246, 176, 40 }, { 255, 232, 150 },
	{ 170, 110, 235 }, { 120, 70, 200 }, { 205, 165, 255 },
}
M.GRAVITY = 900

function M.count(calm, fast, big)
	if calm then return 0 end
	local n = big and 56 or 36
	if fast then n = math.floor(n / 2) end
	return n
end

local function lcg(seed)
	local s = (seed or 1) % 2147483647
	if s <= 0 then s = s + 2147483646 end
	return function()
		s = (s * 16807) % 2147483647
		return s / 2147483647
	end
end

function M.pieces(n, seed)
	local rnd = lcg(seed)
	local out = {}
	for i = 1, n do
		local c = M.PALETTE[(i - 1) % #M.PALETTE + 1]
		out[i] = {
			x = 0.15 + 0.7 * rnd(),
			vx = (rnd() - 0.5) * 360,
			vy = -(220 + 260 * rnd()),
			spin = (rnd() - 0.5) * 540,
			size = 10 + math.floor(rnd() * 6),
			color = { c[1], c[2], c[3] },
			delay = rnd() * 0.25,
		}
	end
	return out
end

return M
