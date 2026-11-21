--[[
	Engine/GlowCurve.lua
	Pure numbers for a soft radial glow built from nested discs (no Roblox types). The glow is the ONE place discs
	are stacked; at least MIN_STEPS of them, with a smoothstep falloff, so no ring edge is visible.

	rings(n, peak, inner) -> { { size = 0..1, transparency = 0..1 }, ... } outermost first. Stacked, the opacity at ring i is
	                  peak * (1 - smoothstep(size_i)); each disc carries only the difference to the ring outside it.
	cumulative(rings) -> opacity the stack reaches inside each ring (for tests).
]]

local GlowCurve = {}

GlowCurve.MIN_STEPS = 24
GlowCurve.DEFAULT_STEPS = 32

local function smoothstep(x)
	x = math.max(0, math.min(1, x))
	return x * x * (3 - 2 * x)
end

function GlowCurve.rings(n, peak, inner)
	n = math.max(GlowCurve.MIN_STEPS, math.floor(n or GlowCurve.DEFAULT_STEPS))
	peak = math.max(0, math.min(0.95, peak or 0.2))
	inner = math.max(0, math.min(0.9, inner or 0)) -- 0..0.9: the glow holds its peak out to this fraction of the radius (a card sits there), then eases out
	local out, below = {}, 0
	for i = 1, n do
		local size = 1 - (i - 1) / n -- 1 for the widest disc down to 1/n
		local target = peak * (1 - smoothstep((size - inner) / (1 - inner))) -- opacity inside this ring
		local a = 0
		if below < 1 then a = math.max(0, 1 - (1 - target) / (1 - below)) end
		below = 1 - (1 - below) * (1 - a)
		out[i] = { size = size, transparency = 1 - a }
	end
	return out
end

function GlowCurve.cumulative(rings)
	local out, below = {}, 0
	for i, r in ipairs(rings) do
		below = 1 - (1 - below) * r.transparency
		out[i] = below
	end
	return out
end

return GlowCurve
