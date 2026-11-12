--[[
	Shared/Engine/FlashFX.lua
	The big moments (a Legendary hand, a True Wildcard, a boss clear) used to wash the whole screen in one flat colour. They are now a
	calm layered effect: a soft radial glow on the thing that triggered it, a faint dark vignette at the screen edges (the middle stays
	unchanged), a handful of drifting motes rising from it and, for Legendary, a thin light sweep across the banner. Pure Lua, tested in
	EngineTests ("FlashFX"); Client/FlashFX.lua draws it.

	FlashFX.spec(kind, reducedMotion)   kind = "legendary" | "wildcard" | "showdown" | "hit"; returns
	    { kind, color, layers = { { type = "glow" | "vignette" | "motes" | "sweep", opacity, coverage, fadeIn, hold, fadeOut, ... } },
	      duration, motion = bool }
	    opacity = the layer's strongest opacity (1 - transparency), coverage = the share of the screen it can cover
	FlashFX.maxFullScreenOpacity(spec)  the strongest opacity among layers that cover most of the screen (must stay at 0.15 or less)
	FlashFX.glowPeakAt(spec, t)         the glow's opacity at t seconds (eased in, held, eased out); a reduced motion glow is just on and off
	FlashFX.vignetteAt(spec, t)         the same for the vignette
	FlashFX.moteCount(kind, reduced)    10 to 16 motes, 0 when motion is reduced
	FlashFX.motes(kind, rolls)          deterministic mote start offsets, drift and life from rolls in 0..1 (so it is testable)
]]

local FlashFX = {}

FlashFX.FULL_SCREEN = 0.9 -- a layer covering this share of the screen or more counts as full screen
FlashFX.MAX_FULL_SCREEN_OPACITY = 0.15

FlashFX.PALETTE = {
	legendary = { 255, 205, 120 }, -- warm gold, muted into the room palette
	wildcard = { 186, 150, 236 }, -- soft violet
	showdown = { 255, 204, 120 },
	hit = { 255, 236, 200 }, -- a boss hit or defeat beat: a short cream glow, nothing else
}

local function ease(k)
	k = math.max(0, math.min(1, k))
	return k * k * (3 - 2 * k)
end

function FlashFX.moteCount(kind, reduced)
	if reduced then return 0 end
	return kind == "legendary" and 16 or 12
end

function FlashFX.spec(kind, reducedMotion)
	local color = FlashFX.PALETTE[kind] or FlashFX.PALETTE.legendary
	local reduced = reducedMotion == true
	-- the glow: transparency about 0.75 at its peak (opacity 0.25), 0.5 s in and 0.8 s out, at most 55 percent of the screen width
	local glow = { type = "glow", opacity = 0.25, coverage = 0.3, fadeIn = reduced and 0 or 0.5, hold = reduced and 1.0 or 0.2, fadeOut = reduced and 0 or 0.8, size = 0.55 }
	-- the vignette: at its strongest transparency 0.85 (opacity 0.15), edges only
	local vignette = { type = "vignette", opacity = 0.15, coverage = 0.9, fadeIn = reduced and 0 or 0.4, hold = reduced and 1.0 or 0.2, fadeOut = reduced and 0 or 0.7, extent = 0.22 }
	local layers = { glow, vignette }
	if kind == "hit" then
		-- a boss hit: one short soft glow, no vignette, no motes (it fires often)
		glow = { type = "glow", opacity = 0.18, coverage = 0.2, fadeIn = reduced and 0 or 0.08, hold = reduced and 0.3 or 0, fadeOut = reduced and 0 or 0.3, size = 0.4 }
		layers = { glow }
	elseif not reduced then
		layers[#layers + 1] = { type = "motes", count = FlashFX.moteCount(kind, false), opacity = 0.6, coverage = 0.1, life = 1.3, rise = 150 }
		if kind == "legendary" then
			layers[#layers + 1] = { type = "sweep", opacity = 0.25, coverage = 0.02, duration = 0.7 } -- a thin light strip across the banner text
		end
	end
	local duration = 0
	for _, l in ipairs(layers) do
		local d = (l.fadeIn or 0) + (l.hold or 0) + (l.fadeOut or 0)
		if l.life then d = l.life + 0.3 end
		if l.duration then d = l.duration end
		duration = math.max(duration, d)
	end
	return { kind = kind, color = { color[1], color[2], color[3] }, layers = layers, duration = duration, motion = not reduced }
end

function FlashFX.maxFullScreenOpacity(spec)
	local m = 0
	for _, l in ipairs(spec.layers) do
		if (l.coverage or 0) >= FlashFX.FULL_SCREEN and l.opacity > m then m = l.opacity end
	end
	return m
end

local function envelope(layer, t)
	local fin, hold, fout = layer.fadeIn or 0, layer.hold or 0, layer.fadeOut or 0
	if t < 0 then return 0 end
	if t < fin then return layer.opacity * ease(t / fin) end
	if t < fin + hold then return layer.opacity end
	if t < fin + hold + fout then return layer.opacity * (1 - ease((t - fin - hold) / fout)) end
	return 0
end

local function layerOf(spec, kind)
	for _, l in ipairs(spec.layers) do
		if l.type == kind then return l end
	end
end

function FlashFX.glowPeakAt(spec, t)
	local g = layerOf(spec, "glow")
	return g and envelope(g, t) or 0
end

function FlashFX.vignetteAt(spec, t)
	local v = layerOf(spec, "vignette")
	return v and envelope(v, t) or 0
end

-- rolls = { r1, r2, r3, r4 } for each mote, all in 0..1: horizontal start, vertical start, drift, speed
function FlashFX.motes(kind, rolls)
	local out = {}
	local n = FlashFX.moteCount(kind, false)
	for i = 1, n do
		local r = rolls[i] or { 0.5, 0.5, 0.5, 0.5 }
		out[i] = {
			dx = (r[1] * 2 - 1) * 70, -- pixels left or right of the centre to start
			dy = (r[2] * 2 - 1) * 24,
			drift = (r[3] * 2 - 1) * 40, -- sideways drift while rising
			rise = 90 + r[4] * 120, -- 90 to 210 px up
			size = 4 + math.floor(r[4] * 4), -- 4 to 7 px
			delay = r[2] * 0.35,
		}
	end
	return out
end

return FlashFX
