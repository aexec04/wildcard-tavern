--[[
	Engine/MothFlight.lua
	Pure state machine for the one wall moth in the Collection back room (drawn by Client/CollectionGallery). No Roblox APIs.

	Life cycle: cooldown (15 to 30 s) -> approach (flies in from a random panel edge, outside the lantern glow, fading in over
	0.8 s on a curved path) -> circle (6 to 10 s) -> land (settles on the lantern glass) -> rest (2 to 3 s, wings open and
	close slowly) -> takeoff (flies back the way it came, fading out over its last 0.8 s) -> cooldown. It is never opaque
	when it appears or disappears, never spawns inside the glow, and there is one moth at a time. Calm mode and a hidden
	Collection reset it to cooldown and show nothing.

	  local moth = MothFlight.new(rng)       rng(lo, hi) -> number in [lo, hi]; defaults to math.random
	  local s = moth:step(dt, ctx)           ctx = { w, h, lx, ly, calm, hidden } (panel size and lantern centre, px)
	  s = { phase, visible, alpha (0..1), x, y, flap (x scale 0.55..1), rot }
]]

local MothFlight = {}
MothFlight.__index = MothFlight

MothFlight.GLOW_RADIUS = 75 -- the outer lantern glow ring is 150 px across
MothFlight.ORBIT = 46
MothFlight.FADE = 0.8
MothFlight.APPROACH = 3.0
MothFlight.LAND = 1.0
MothFlight.TAKEOFF = 1.6
MothFlight.COOLDOWN = { 15, 30 }
MothFlight.CIRCLE = { 6, 10 }
MothFlight.REST = { 2, 3 }
MothFlight.FLAP_HZ = 8
MothFlight.GLASS_DROP = 6 -- the landing spot sits a little below the lantern centre

local function clamp01(v)
	return math.max(0, math.min(1, v))
end

function MothFlight.new(rng)
	local self = setmetatable({}, MothFlight)
	self.rng = rng or function(lo, hi) return lo + math.random() * (hi - lo) end
	self.phase = "cooldown"
	self.t = 0
	self.duration = self.rng(MothFlight.COOLDOWN[1], MothFlight.COOLDOWN[2])
	self.clock = 0
	return self
end

-- A point on a random panel edge that lies at least GLOW_RADIUS + 20 px from the lantern.
local function pickSpawn(self, w, h, lx, ly)
	local minD = MothFlight.GLOW_RADIUS + 20
	for _ = 1, 12 do
		local edge = math.floor(self.rng(1, 4.999))
		local u = self.rng(0.1, 0.9)
		local x, y
		if edge == 1 then x, y = u * w, 0
		elseif edge == 2 then x, y = w, u * h
		elseif edge == 3 then x, y = u * w, h
		else x, y = 0, u * h end
		local dx, dy = x - lx, y - ly
		if dx * dx + dy * dy >= minD * minD then return x, y end
	end
	-- a tiny panel: take the corner farthest from the lantern
	local best, bx, by = -1, 0, 0
	for _, c in ipairs({ { 0, 0 }, { w, 0 }, { 0, h }, { w, h } }) do
		local d = (c[1] - lx) ^ 2 + (c[2] - ly) ^ 2
		if d > best then best, bx, by = d, c[1], c[2] end
	end
	return bx, by
end

local function setPhase(self, phase, duration)
	self.phase = phase
	self.t = 0
	self.duration = duration
end

-- Curved flight from (ax, ay) to (bx, by): a straight lerp plus a sideways bow that peaks mid-flight, and a small flutter.
local function curve(ax, ay, bx, by, s, clock)
	local x, y = ax + (bx - ax) * s, ay + (by - ay) * s
	local dx, dy = bx - ax, by - ay
	local len = math.max(1, math.sqrt(dx * dx + dy * dy))
	local bow = math.sin(math.pi * s) * len * 0.18
	x = x + (-dy / len) * bow + math.sin(clock * 9) * 2.5 * (1 - s * 0.5)
	y = y + (dx / len) * bow + math.cos(clock * 11) * 2.5 * (1 - s * 0.5)
	return x, y
end

local function flapOf(self, resting)
	local hz = resting and 0.5 or MothFlight.FLAP_HZ
	return 1 - 0.45 * (0.5 + 0.5 * math.sin(self.clock * hz * 2 * math.pi))
end

function MothFlight:step(dt, ctx)
	if ctx.calm or ctx.hidden then
		if self.phase ~= "cooldown" then
			setPhase(self, "cooldown", self.rng(MothFlight.COOLDOWN[1], MothFlight.COOLDOWN[2]))
		end
		return { phase = "cooldown", visible = false, alpha = 0, x = 0, y = 0, flap = 1, rot = 0 }
	end
	self.clock = self.clock + dt
	self.t = self.t + dt
	if self.t >= self.duration then
		local phase = self.phase
		if phase == "cooldown" then
			self.sx, self.sy = pickSpawn(self, ctx.w, ctx.h, ctx.lx, ctx.ly)
			self.theta0 = self.rng(0, 2 * math.pi)
			setPhase(self, "approach", MothFlight.APPROACH)
		elseif phase == "approach" then
			setPhase(self, "circle", self.rng(MothFlight.CIRCLE[1], MothFlight.CIRCLE[2]))
		elseif phase == "circle" then
			self.fromX, self.fromY = self.lastX, self.lastY -- land from wherever the orbit ended
			setPhase(self, "land", MothFlight.LAND)
		elseif phase == "land" then
			setPhase(self, "rest", self.rng(MothFlight.REST[1], MothFlight.REST[2]))
		elseif phase == "rest" then
			setPhase(self, "takeoff", MothFlight.TAKEOFF)
		else
			setPhase(self, "cooldown", self.rng(MothFlight.COOLDOWN[1], MothFlight.COOLDOWN[2]))
		end
	end
	local phase = self.phase
	local lx, ly = ctx.lx, ctx.ly
	local theta0 = self.theta0 or 0
	local function orbit(tt)
		local a = theta0 + tt * 1.6
		return lx + math.cos(a) * MothFlight.ORBIT, ly + math.sin(a) * MothFlight.ORBIT * 0.8
	end
	local s = { phase = phase, visible = true, alpha = 1, flap = flapOf(self, false), rot = 0 }
	local k = clamp01(self.t / self.duration)
	if phase == "cooldown" then
		s.visible, s.alpha = false, 0
		s.x, s.y = 0, 0
	elseif phase == "approach" then
		local ex, ey = orbit(0)
		s.x, s.y = curve(self.sx, self.sy, ex, ey, k, self.clock)
		s.alpha = clamp01(self.t / MothFlight.FADE)
	elseif phase == "circle" then
		s.x, s.y = orbit(self.t)
	elseif phase == "land" then
		s.x, s.y = curve(self.fromX or lx, self.fromY or ly, lx, ly + MothFlight.GLASS_DROP, k, self.clock)
	elseif phase == "rest" then
		s.x, s.y = lx, ly + MothFlight.GLASS_DROP
		s.flap = flapOf(self, true)
	else -- takeoff: back along the way it came
		s.x, s.y = curve(lx, ly + MothFlight.GLASS_DROP, self.sx, self.sy, k, self.clock)
		s.alpha = 1 - clamp01((self.t - (self.duration - MothFlight.FADE)) / MothFlight.FADE)
	end
	s.rot = math.sin(self.clock * 3) * 8
	self.lastX, self.lastY = s.x, s.y
	return s
end

return MothFlight
