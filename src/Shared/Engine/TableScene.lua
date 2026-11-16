--[[
	Engine/TableScene.lua
	The numbers and the pure math of the 3D play table (Client/Table3D). No Roblox types in here: points are
	{ x, y, z } arrays and everything else is plain numbers, so the plain Lua tests run all of it.

	Table space: x runs to the right of the screen, y is up, z runs toward the player. The felt is y = 0 and the table's
	middle is x = TABLE.centreX, z = 0. The camera never moves: the 2D play screen keeps its layout and its input, and
	every card on the felt stands where its 2D slot is on screen (Client/Table3D/Cards follows the slots through
	groundPoint's live twin). So a wider or shorter window needs no second layout.

	TableScene.CAMERA, TABLE, CARD, CHIP, LIFT   the numbers
	groundPoint(nx, ny, aspect, planeY) -> { x, y, z }   where the pixel at (nx, ny) meets the plane y = planeY
	    nx, ny in -1..1 from the screen's middle (x right, y down); aspect = width / height
	depthOf(point) -> studs along the camera's view axis;  studsPerPixel(depth, viewportH) -> studs one pixel covers there
	onFelt(point, margin) -> bool
	liftFor(liftPx, uiScale, studsPerPx) -> studs above the felt for a hovered, selected or popping card
	spring(x, v, target, dt) -> x, v        a quick, lightly springy follow
	arcPoint(p0, p1, apex, t) -> { x, y, z }   a thrown chip's path
	chipsFor(kind, amount) -> how many chips one scoring beat throws;  potSlot(n) -> dx, dz, level
	shakeAt(t, intensity, duration) -> dx, dy  (studs) from a 2D shake's pixel intensity
	signature(card) -> string;  matchHands(old, new) -> { [newIndex] = oldIndex }
]]

local M = {}

-- Where the scene stands in the world: far above the baseplate and the spawn, which stay as they are.
M.ORIGIN = { 0, 500, 0 }

-- The fixed camera. 58 degrees down with a narrow lens: cards on the felt keep nine tenths of their height on screen
-- and the far end of the table is still in the picture.
M.CAMERA = { fov = 38, pitch = 58, height = 22.4, z = 15.75, x = 0 }

-- A rectangular felt in a wooden rail. The hand row lands about 4.6 studs toward the player from the middle and the
-- played cards land just past it; the rail's near edge sits under the action buttons.
M.TABLE = {
	centreX = 2.5, halfLength = 19, halfWidth = 8.25,
	railWidth = 2.3, railHeight = 0.55, feltThickness = 0.3, bodyDrop = 1.6, floorDrop = 9,
}

M.CARD = { aspect = 1.45, thickness = 0.05, rest = 0.035, stackStep = 0.014 }

-- Lift: the 2D hand raises a hovered card 6 px and a selected one 18 px, and pops a scoring card to 1.22 times its
-- size. On the felt those become height toward the camera, and a card that is tiltAt studs up leans `tilt` degrees.
M.LIFT = { perPx = 2.3, perScale = 6.5, max = 2.6, travel = 0.9, tilt = 9, tiltAt = 1.4 }

M.CHIP = { diameter = 0.86, height = 0.13, perStack = 7, spacing = 0.98, perPile = 35, flight = 0.46, apex = 2.6 }

-- Where the pot stands when no played card is on the table to stand it beside (table space, on the felt).
M.POT = { -7.5, 0, -1.5 }

local function rad(deg) return deg * math.pi / 180 end

-- the camera's position in table space
function M.cameraPosition()
	return { M.CAMERA.x, M.CAMERA.height, M.CAMERA.z }
end

-- the unit vector the pixel at (nx, ny) looks along, in table space
function M.rayThrough(nx, ny, aspect)
	local t = math.tan(rad(M.CAMERA.fov) / 2)
	local cx, cy, cz = nx * t * aspect, -ny * t, -1
	local p = rad(M.CAMERA.pitch)
	local y = cy * math.cos(p) + cz * math.sin(p)
	local z = -cy * math.sin(p) + cz * math.cos(p)
	local len = math.sqrt(cx * cx + y * y + z * z)
	return { cx / len, y / len, z / len }
end

function M.groundPoint(nx, ny, aspect, planeY)
	local dir = M.rayThrough(nx, ny, aspect)
	if dir[2] >= -1e-6 then return nil end -- looking at or above the horizon: it never meets the table
	local cam = M.cameraPosition()
	local t = ((planeY or 0) - cam[2]) / dir[2]
	return { cam[1] + dir[1] * t, cam[2] + dir[2] * t, cam[3] + dir[3] * t }
end

-- how far a point is along the camera's view axis (what perspective divides by)
function M.depthOf(point)
	local p = rad(M.CAMERA.pitch)
	local cam = M.cameraPosition()
	local dy, dz = point[2] - cam[2], point[3] - cam[3]
	return -dy * math.sin(p) - dz * math.cos(p)
end

function M.studsPerPixel(depth, viewportH)
	return 2 * depth * math.tan(rad(M.CAMERA.fov) / 2) / math.max(1, viewportH)
end

function M.onFelt(point, margin)
	margin = margin or 0
	local T = M.TABLE
	return math.abs(point[1] - T.centreX) <= T.halfLength - margin and math.abs(point[3]) <= T.halfWidth - margin
end

function M.liftFor(liftPx, uiScale, studsPerPx)
	local L = M.LIFT
	local up = math.max(0, liftPx or 0) * (studsPerPx or 0.023) * L.perPx
	local pop = math.max(0, (uiScale or 1) - 1) * L.perScale
	return math.min(L.max, up + pop)
end

-- A stiff spring with a little overshoot: a card settles in about a fifth of a second.
function M.spring(x, v, target, dt)
	dt = math.min(dt or 0.016, 0.05)
	local k, c = 260, 21
	v = v + ((target - x) * k - v * c) * dt
	return x + v * dt, v
end

function M.arcPoint(p0, p1, apex, t)
	local u = 1 - t
	return {
		p0[1] * u + p1[1] * t,
		p0[2] * u + p1[2] * t + (apex or 0) * 4 * u * t,
		p0[3] * u + p1[3] * t,
	}
end

-- One scoring beat throws a handful: more for a bigger number, never a flood.
function M.chipsFor(kind, amount)
	local n = math.abs(tonumber(amount) or 0)
	if kind == "chips" then
		return math.max(1, math.min(8, math.floor(n / 4 + 0.5)))
	elseif kind == "tips" then
		return math.max(1, math.min(5, math.floor(n + 0.5)))
	elseif kind == "xmult" then
		return 5
	end
	return math.max(1, math.min(6, math.floor(n + 0.5))) -- mult
end

-- The pot is a small cluster of stacks: the middle one first, then the six around it, then a wider ring.
local RING = {
	{ 0, 0 }, { 1, 0 }, { 0.5, 0.87 }, { -0.5, 0.87 }, { -1, 0 }, { -0.5, -0.87 }, { 0.5, -0.87 },
	{ 2, 0 }, { 1.5, 0.87 }, { 1, 1.73 }, { 0, 1.73 }, { -1, 1.73 }, { -1.5, 0.87 },
}
function M.potSlot(n)
	local per = M.CHIP.perStack
	local stack = math.floor((n - 1) / per)
	local level = (n - 1) % per
	local spot = RING[stack % #RING + 1]
	local lap = math.floor(stack / #RING)
	return spot[1] * M.CHIP.spacing, spot[2] * M.CHIP.spacing, level + lap * per
end

-- A 2D shake of `intensity` pixels becomes a small camera wobble that dies away. Same t, same answer.
function M.shakeAt(t, intensity, duration)
	duration = math.max(0.05, duration or 0.2)
	if t < 0 or t >= duration then return 0, 0 end
	local fade = (1 - t / duration) ^ 2
	local a = math.min(14, intensity or 0) * 0.011 * fade
	return a * math.sin(t * 61), a * math.sin(t * 47 + 1.3)
end

function M.signature(card)
	if type(card) ~= "table" then return "?" end
	local wild = card.isTrueWildcard and (card.wildcardLocked and "W" or "w") or ""
	return table.concat({
		tostring(card.rank), tostring(card.suit), tostring(card.garnish or ""), tostring(card.special or ""),
		tostring(card.stamp or ""), wild,
	}, "|")
end

-- The hand is rebuilt after every play and discard. A card that stayed keeps the piece of card it had on the felt:
-- old and new are signature lists in left to right order, and equal signatures pair up in that order.
function M.matchHands(old, new)
	local used, out = {}, {}
	for newIndex, sig in ipairs(new or {}) do
		for oldIndex, oldSig in ipairs(old or {}) do
			if not used[oldIndex] and oldSig == sig then
				used[oldIndex] = true
				out[newIndex] = oldIndex
				break
			end
		end
	end
	return out
end

return M
