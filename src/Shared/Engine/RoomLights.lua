--[[
	Shared/Engine/RoomLights.lua
	Pure maths and data for the lights of the painted rooms (Client/RoomLights.lua draws them). No Roblox objects.

	M.ROOMS[roomId] = { spots = { { x, y, size, kind } ... }, shaft = { x, y, w, h }, motes = n }
	  x, y = the light's centre and size = the glow's width, all as fractions of the room PICTURE (so they follow its crop and scale);
	  kind = "candle" | "lantern" | "fire" | "window".
	M.BASE[kind]          the glow's resting SoftGlow peak (low contrast)
	M.flicker(kind, t, seed, calm) -> multiplier of the resting peak, always inside 1 +- M.LIMIT (0.08); exactly 1 in calm mode
	M.mote(i, n, t, shaft) -> { x, y, alpha } in picture fractions: a tiny speck drifting up inside the light shaft, fading in and out
	M.MAX_MOTES = 12

	Candle: a 3 to 6 percent wobble at 6 to 9 Hz mixed with a slow 0.5 Hz drift. Lantern: a slow breath with a 2 to 4 second period.
	Fire: warmer and bigger, two overlapping wobbles. Window: a very slow 0.2 Hz shimmer.
]]

local M = {}

M.LIMIT = 0.08
M.MAX_MOTES = 12

M.BASE = { candle = 0.22, lantern = 0.2, fire = 0.3, window = 0.14 }

-- spots measured from the painted pictures at half size (art-wip/panel_scene/*.png)
M.ROOMS = {
	flair = {
		spots = {
			{ x = 0.034, y = 0.26, size = 0.13, kind = "lantern" },
			{ x = 0.948, y = 0.254, size = 0.13, kind = "lantern" },
		},
		shaft = { x = 0.9, y = 0.3, w = 0.08, h = 0.3 },
		motes = 5,
	},
	-- the Concept T play room (ct_table_room, 1536 x 1024): fireplace, chandelier and mantel candles, the left window shaft
	concept_t = {
		spots = {
			{ x = 0.835, y = 0.38, size = 0.17, kind = "fire" },
			{ x = 0.50, y = 0.12, size = 0.14, kind = "candle" },
			{ x = 0.965, y = 0.165, size = 0.08, kind = "candle" },
			{ x = 0.04, y = 0.24, size = 0.14, kind = "window" },
		},
		shaft = { x = 0.03, y = 0.26, w = 0.12, h = 0.3, period = 8 },
		motes = 12,
	},
	stats = {
		spots = {
			{ x = 0.082, y = 0.283, size = 0.2, kind = "lantern" },
			{ x = 0.926, y = 0.283, size = 0.2, kind = "lantern" },
			{ x = 0.094, y = 0.586, size = 0.14, kind = "candle" },
		},
		shaft = { x = 0.06, y = 0.34, w = 0.12, h = 0.22 },
		motes = 6,
	},
}

local TAU = math.pi * 2

local function clamp(v)
	return math.max(-M.LIMIT, math.min(M.LIMIT, v))
end

-- a stable phase per light so two lights never pulse together
local function phase(seed)
	return ((tonumber(seed) or 0) * 2.399963) % TAU
end

function M.flicker(kind, t, seed, calm)
	if calm then return 1 end
	local p = phase(seed)
	local f
	if kind == "candle" then
		-- wobble 7.5 Hz and 6.3 Hz (at most 0.05 together), drift 0.5 Hz (0.02)
		f = 0.03 * math.sin(TAU * 7.5 * t + p) + 0.02 * math.sin(TAU * 6.3 * t + 2 * p) + 0.02 * math.sin(TAU * 0.5 * t + 3 * p)
	elseif kind == "lantern" then
		local period = 2 + (seed or 0) % 3 -- 2, 3 or 4 seconds
		f = 0.05 * math.sin(TAU * t / period + p)
	elseif kind == "fire" then
		f = 0.05 * math.sin(TAU * 3.1 * t + p) + 0.03 * math.sin(TAU * 5.3 * t + 2 * p)
	else -- window
		f = 0.03 * math.sin(TAU * 0.2 * t + p)
	end
	return 1 + clamp(f)
end

-- mote i of n: rises slowly through the shaft box and fades in at the bottom and out at the top
function M.mote(i, n, t, shaft)
	local rise = 0.012 + 0.002 * (i % 4) -- shaft heights per second
	local speed = shaft.period and (1 / shaft.period) or (rise / math.max(shaft.h, 1e-6)) -- a shaft may set seconds per rise
	local cycle = (t * speed + (i - 1) / math.max(n, 1)) % 1
	local sway = math.sin(TAU * t / (9 + i) + i * 1.7) * shaft.w * 0.25
	local col = ((i * 0.618034) % 1)
	return {
		x = shaft.x + shaft.w * col + sway,
		y = shaft.y + shaft.h * (1 - cycle),
		alpha = math.sin(math.pi * cycle), -- 0 at both ends, 1 in the middle
	}
end

function M.moteCount(room)
	local r = M.ROOMS[room]
	return r and math.min(r.motes or 0, M.MAX_MOTES) or 0
end

return M
