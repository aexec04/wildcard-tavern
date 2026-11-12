--[[
	Shared/Engine/AmbientLayout.lua
	Pure data and maths for the living table backdrops (Client/AmbientLife.lua draws them). No Roblox APIs.

	  AmbientLayout.SETS[setId]            { { kind, count, band = { y0, y1 }, ... } } one entry per Card Set
	  AmbientLayout.MAX_OBJECTS            14, the cap per scene
	  AmbientLayout.objectCount(setId, calm)  animated objects the scene creates (0 in calm mode / Reduce motion)
	  AmbientLayout.list(setId, calm)      flat list { { kind, spec, index } } the renderer pools frames for
	  AmbientLayout.wind(t, seed)          shared breeze 0..1 (gusts every 8 to 14 s)
	  AmbientLayout.state(item, t, wind)   -> { x, y, rot, alpha, scale, frame, sprite } as a pure function of time and wind
	  AmbientLayout.breath(t)              -> { scale, dx, dy } slow zoom and drift of the whole backdrop (fractions)
	  AmbientLayout.SPRITES[kind]          sprite ids (ContentArt "ambient") and optional crop rects, 1536x1024 or 1024 canvases

	All positions are fractions (0..1) of the scene. Bands are fractions of the height (sky, ground, water). Sprites
	missing from the ambient art map fall back to code-drawn shapes in the renderer.
]]

local AmbientLayout = {}

AmbientLayout.MAX_OBJECTS = 14
AmbientLayout.TICK = 1 / 30

local SKY = { 0.04, 0.34 }
local MID = { 0.2, 0.7 }
local GROUND = { 0.55, 0.9 }
local WATER = { 0.62, 0.92 }
local FULL = { 0.0, 1.0 }

-- ids: first = pose A (wings open / up), second = pose B. crop = { x, y, w, h } in source pixels (cloud, sand).
AmbientLayout.SPRITES = {
	butterfly = { ids = { "ambient_butterfly_open", "ambient_butterfly_closed" } },
	cloud = { ids = { "ambient_cloud_a" }, crop = { 240, 330, 1060, 330 } },
	leaf = { ids = { "ambient_leaf_green" } },
	petal = { ids = { "ambient_petal" } },
	snow = { ids = { "ambient_snowflake" } },
	ember = { ids = { "ambient_ember" } },
	sand = { ids = { "ambient_sand_streak" }, crop = { 140, 430, 1280, 170 } },
	lantern = { ids = { "ambient_lantern_float" } },
	ribbon = { ids = { "ambient_ribbon" } },
	mote = { ids = { "ambient_gold_mote" } },
	-- no painted sprite yet: drawn from shapes
	pollen = { ids = {} },
	firefly = { ids = {} },
	mist = { ids = {} },
	bird = { ids = {} },
	shimmer = { ids = {} },
	glow = { ids = {} },
	dust = { ids = {} },
}

local K = {} -- spec builders keep the table readable
local function o(kind, n, band, extra)
	local t = { kind = kind, count = n, band = band }
	for k, v in pairs(extra or {}) do t[k] = v end
	return t
end
K.o = o

local GOLD = { 255, 215, 120 }
local CREAM = { 255, 244, 214 }
local WARM = { 255, 168, 80 }

AmbientLayout.SETS = {
	classic_tavern = { o("dust", 5, { 0.3, 0.8 }, { color = CREAM, size = 0.006 }) },
	meadow_picnic = {
		o("butterfly", 3, { 0.4, 0.85 }, { size = 0.045, color = { 255, 150, 50 } }),
		o("cloud", 2, SKY, { size = 0.2, speed = 0.006, color = { 255, 255, 255 } }),
		o("pollen", 4, MID, { size = 0.006, color = { 255, 240, 170 } }),
		o("petal", 3, FULL, { size = 0.02, speed = 0.02, color = { 255, 255, 255 } }),
	},
	harvest_table = {
		o("leaf", 7, FULL, { size = 0.028, speed = 0.03, color = { 240, 170, 50 } }),
		o("dust", 4, { 0.2, 0.7 }, { color = GOLD, size = 0.006 }),
	},
	snowy_hearth = {
		o("snow", 10, FULL, { size = 0.012, speed = 0.05, layers = 3, color = { 255, 255, 255 } }),
		o("glow", 1, { 0.55, 0.95 }, { size = 0.5, color = WARM, strength = 0.03 }),
	},
	winter_table = { o("snow", 9, FULL, { size = 0.012, speed = 0.045, layers = 3, color = { 255, 255, 255 } }) },
	winter_evening = {
		o("snow", 7, FULL, { size = 0.011, speed = 0.04, layers = 3, color = { 255, 255, 255 } }),
		o("mote", 3, MID, { size = 0.012, color = GOLD }),
	},
	marsh_lanterns = {
		o("firefly", 8, { 0.3, 0.9 }, { size = 0.012, color = { 220, 255, 140 } }),
		o("mist", 3, { 0.65, 0.95 }, { size = 0.5, speed = 0.004, color = { 210, 235, 220 } }),
	},
	dune_market = {
		o("sand", 4, { 0.5, 0.95 }, { size = 0.22, speed = 0.05, color = { 245, 220, 170 } }),
		o("shimmer", 1, { 0.45, 0.65 }, { size = 1.0, color = { 255, 235, 190 } }),
		o("bird", 1, SKY, { size = 0.025, speed = 0.01, color = { 70, 80, 95 } }),
	},
	harbor_lights = {
		o("shimmer", 2, WATER, { size = 1.0, color = { 200, 230, 255 } }),
		o("bird", 1, SKY, { size = 0.025, speed = 0.012, color = { 70, 80, 95 } }),
		o("glow", 2, { 0.2, 0.5 }, { size = 0.2, color = { 255, 200, 110 }, strength = 0.03 }),
	},
	festival_night = {
		o("lantern", 4, MID, { size = 0.045, speed = 0.012, color = { 255, 200, 120 } }),
		o("ribbon", 3, { 0.02, 0.25 }, { size = 0.06, color = { 230, 70, 70 } }),
		o("mote", 5, FULL, { size = 0.012, speed = 0.015, color = GOLD }),
	},
	golden_gala = { o("mote", 12, FULL, { size = 0.014, speed = 0.02, color = GOLD }) },
	riverside_evening = {
		o("mist", 3, WATER, { size = 0.5, speed = 0.004, color = { 220, 225, 240 } }),
		o("firefly", 5, { 0.3, 0.8 }, { size = 0.011, color = { 255, 235, 150 } }),
		o("shimmer", 1, WATER, { size = 1.0, color = { 210, 225, 255 } }),
	},
	closing_time = {
		o("ember", 5, { 0.4, 0.95 }, { size = 0.012, speed = 0.03, color = WARM }),
		o("glow", 1, { 0.55, 0.95 }, { size = 0.45, color = WARM, strength = 0.02 }),
	},
	summit_camp = {
		o("cloud", 2, SKY, { size = 0.22, speed = 0.005, color = { 255, 255, 255 } }),
		o("snow", 5, FULL, { size = 0.01, speed = 0.03, layers = 2, color = { 255, 255, 255 } }),
	},
	tavern_feast = {
		o("dust", 5, { 0.2, 0.7 }, { color = GOLD, size = 0.006 }),
		o("ember", 3, { 0.5, 0.95 }, { size = 0.01, speed = 0.025, color = WARM }),
	},
}

-- ===== deterministic randomness =====

local function rnd(i, salt)
	local v = math.sin(i * 12.9898 + salt * 78.233) * 43758.5453
	return v - math.floor(v)
end

local function lerp(a, b, t)
	return a + (b - a) * t
end

local function clamp(v, a, b)
	if v < a then return a end
	if v > b then return b end
	return v
end

local function wrap01(v)
	return v - math.floor(v)
end

-- ===== list / counts =====

function AmbientLayout.list(setId, calm)
	local out = {}
	if calm then return out end
	local specs = AmbientLayout.SETS[setId]
	if not specs then return out end
	local n = 0
	for si, spec in ipairs(specs) do
		for i = 1, spec.count do
			if n >= AmbientLayout.MAX_OBJECTS then return out end
			n = n + 1
			out[n] = { kind = spec.kind, spec = spec, index = i, uid = si * 101 + i }
		end
	end
	return out
end

function AmbientLayout.objectCount(setId, calm)
	return #AmbientLayout.list(setId, calm)
end

-- ===== wind =====
-- 0..1. A calm base breeze plus a gust (smooth bump) every 8 to 14 s; the gap changes per gust from the seed.

function AmbientLayout.wind(t, seed)
	seed = seed or 0
	-- phase rate swings between 2*pi/14 and 2*pi/8 per second, so the gap between gusts is 8 to 14 s
	local phase = 0.617 * t + 2.4 * math.sin(0.07 * t + seed)
	local gust = math.max(0, math.sin(phase)) ^ 2
	return clamp(0.25 + 0.75 * gust, 0, 1)
end

-- ===== whole-backdrop breath =====
-- Zoom stays at 1.03 or more so a drift of 0.006 of the size never shows an edge (margin is 0.015 per side).

-- Play screen is static: the whole backdrop picture must not zoom or drift (it separated from the table). Client/AmbientLife checks this.
AmbientLayout.BREATH_ENABLED = false

function AmbientLayout.breath(t)
	local s = 0.5 + 0.5 * math.sin(t * (math.pi * 2 / 40))
	return {
		scale = 1.03 + 0.015 * s, -- about 1.5 percent zoom over 40 s
		dx = 0.006 * math.sin(t * (math.pi * 2 / 53)),
		dy = 0.006 * math.sin(t * (math.pi * 2 / 47) + 1.3),
	}
end

-- ===== object motion =====

local function edgeFade(v, m)
	m = m or 0.06
	if v < m then return clamp(v / m, 0, 1) end
	if v > 1 - m then return clamp((1 - v) / m, 0, 1) end
	return 1
end

local function bandY(spec, r)
	local b = spec.band or FULL
	return lerp(b[1], b[2], r)
end

-- Smooth wandering path inside the band (butterflies, fireflies): sums of sines, so it never snaps.
local function wander(item, tau, ax, ay, rate)
	local u = item.uid
	local cx = 0.15 + 0.7 * rnd(u, 1)
	local b = item.spec.band or FULL
	local cy = lerp(b[1], b[2], 0.5)
	local hy = (b[2] - b[1]) * 0.5
	local p1, p2, p3, p4 = rnd(u, 2) * 6.28, rnd(u, 3) * 6.28, rnd(u, 4) * 6.28, rnd(u, 5) * 6.28
	local x = cx + ax * (0.65 * math.sin(tau * 0.31 * rate + p1) + 0.35 * math.sin(tau * 0.77 * rate + p2))
	local y = cy + hy * ay * (0.65 * math.sin(tau * 0.43 * rate + p3) + 0.35 * math.sin(tau * 0.91 * rate + p4))
	return x, y
end

local function sprite(kind, which)
	local s = AmbientLayout.SPRITES[kind]
	if not s or #s.ids == 0 then return nil end
	return s.ids[which] or s.ids[1]
end

function AmbientLayout.state(item, t, wind)
	wind = wind or 0
	local spec, u, kind = item.spec, item.uid, item.kind
	local phase = rnd(u, 7) * 6.28
	local st = { x = 0.5, y = 0.5, rot = 0, alpha = 1, scale = 1, frame = 1, sprite = sprite(kind, 1) }
	if kind == "butterfly" then
		-- time warp: it slows to almost a stop now and then (resting on a flower)
		local tau = t + 2.4 * math.sin(0.4 * t + phase) + u
		local x, y = wander(item, tau, 0.32, 0.8, 1)
		local x2, y2 = wander(item, tau + 0.05, 0.32, 0.8, 1)
		local dx = x2 - x
		x = x + wind * 0.02
		st.x, st.y = clamp(x, 0.03, 0.97), clamp(y, 0.03, 0.97)
		st.rot = clamp(dx * 600, -12, 12) -- banks a few degrees with the heading
		st.frame = (math.floor(tau * 6) % 2) + 1 -- about 6 swaps a second
		st.sprite = sprite(kind, st.frame)
	elseif kind == "firefly" then
		local x, y = wander(item, t + u, 0.3, 0.9, 0.5)
		st.x, st.y = clamp(x, 0.03, 0.97), clamp(y, 0.03, 0.97)
		st.alpha = 0.25 + 0.75 * (0.5 + 0.5 * math.sin(t * (0.6 + 0.4 * rnd(u, 8)) + phase))
	elseif kind == "cloud" or kind == "sand" or kind == "mist" then
		local speed = spec.speed or 0.01
		local x0 = rnd(u, 9)
		local x = wrap01(x0 + speed * t * (1 + wind * 1.5) * (0.8 + 0.4 * rnd(u, 10)))
		-- wind speeds the drift of the whole object; the wrap fades at both edges so nothing pops
		local lane = (item.index - 1) / math.max(1, spec.count)
		st.x = x
		st.y = bandY(spec, clamp(lane + 0.3 * rnd(u, 11), 0, 1)) + 0.004 * math.sin(t * 0.2 + phase)
		local base = (kind == "mist") and 0.35 or (kind == "sand" and 0.5 or 0.9)
		st.alpha = base * edgeFade(x, 0.12)
	elseif kind == "snow" then
		local layers = spec.layers or 3
		local layer = (item.index - 1) % layers + 1
		local depth = layer / layers -- near layers fall faster, look bigger
		local vy = (spec.speed or 0.05) * (0.6 + 0.8 * depth)
		local y = wrap01(rnd(u, 12) + vy * t)
		st.x = wrap01(rnd(u, 13) + math.sin(t * 0.7 + phase) * 0.01 + wind * 0.04 * depth)
		st.y = y
		st.scale = 0.6 + 0.8 * depth
		st.alpha = (0.35 + 0.4 * depth) * edgeFade(y, 0.05)
	elseif kind == "leaf" or kind == "petal" then
		local vy = (spec.speed or 0.03) * (0.7 + 0.6 * rnd(u, 14))
		local y = wrap01(rnd(u, 15) + vy * t)
		st.x = wrap01(rnd(u, 16) + math.sin(t * 0.5 + phase) * 0.03 + wind * 0.08)
		st.y = y
		st.rot = math.sin(t * 0.8 + phase) * 35 + wind * 20
		st.alpha = 0.9 * edgeFade(y, 0.06)
	elseif kind == "mote" or kind == "dust" or kind == "pollen" then
		local up = (kind == "mote") and (spec.speed or 0.02) or 0.004
		local b = spec.band or FULL
		local y = wrap01(rnd(u, 17) - up * t)
		st.y = lerp(b[1], b[2], y)
		st.x = wrap01(rnd(u, 18) + math.sin(t * 0.3 + phase) * 0.02 + wind * 0.03)
		st.alpha = (0.35 + 0.35 * math.sin(t * 0.9 + phase)) * edgeFade(y, 0.15)
	elseif kind == "ember" then
		local period = 6 + 3 * rnd(u, 19)
		local life = ((t + rnd(u, 20) * period) % period) / period
		local b = spec.band or FULL
		st.x = 0.1 + 0.8 * rnd(u, 21) + math.sin(t * 1.3 + phase) * 0.012 + wind * 0.02 * life
		st.y = lerp(b[2], b[1], life)
		st.alpha = (1 - life) * edgeFade(life, 0.15)
	elseif kind == "lantern" then
		local life = ((t * (spec.speed or 0.012) + rnd(u, 22)) % 1)
		local b = spec.band or FULL
		st.x = 0.1 + 0.8 * rnd(u, 23) + math.sin(t * 0.4 + phase) * 0.02 + wind * 0.03
		st.y = lerp(b[2], b[1] - 0.1, life)
		st.rot = math.sin(t * 0.5 + phase) * 6
		st.alpha = edgeFade(life, 0.12)
	elseif kind == "ribbon" then
		local b = spec.band or FULL
		st.x = 0.1 + 0.8 * (item.index - 0.5) / spec.count
		st.y = lerp(b[1], b[2], 0.5)
		st.rot = math.sin(t * 0.9 + phase) * 10 + wind * 6
		st.alpha = 0.95
	elseif kind == "bird" then
		local speed = spec.speed or 0.01
		local x = wrap01(rnd(u, 24) + speed * t)
		local b = spec.band or SKY
		st.x = x
		st.y = lerp(b[1], b[2], 0.5) + 0.03 * math.sin(t * 0.25 + phase)
		st.frame = (math.floor(t * 1.2) % 2) + 1
		st.scale = 1 + 0.15 * (st.frame - 1)
		st.alpha = edgeFade(x, 0.1)
	elseif kind == "shimmer" then
		local b = spec.band or WATER
		st.x, st.y = 0.5, (b[1] + b[2]) * 0.5
		st.alpha = 0.04 + 0.03 * math.sin(t * 0.8 + phase + item.index)
	elseif kind == "glow" then
		local strength = spec.strength or 0.03
		local b = spec.band or GROUND
		st.x = 0.2 + 0.6 * rnd(u, 25)
		st.y = (b[1] + b[2]) * 0.5
		-- breathes by `strength` around a soft base
		st.alpha = 0.05 + strength * math.sin(t * (math.pi * 2 / 4) + phase)
	end
	return st
end

return AmbientLayout
