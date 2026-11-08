--[[
	Shared/Engine/MapPan.lua
	Pure helpers for panning the Tavern Map camera in two axes (tested). The map canvas is several
	screens wide and a couple of screens tall; the view (ScrollingFrame) shows a window of it.

	WORLD_SCREENS_Y                     canvas height in view heights (the world is taller than the screen)
	canvasHeight(viewH)                 -> canvas height in pixels
	clamp(x, y, canvasW, canvasH, viewW, viewH) -> x, y     keep the window inside the canvas
	centerOn(px, py, canvasW, canvasH, viewW, viewH) -> x, y   window top-left that centres a world point (clamped)
	stepToward(px, py, bearing, distance) -> x, y   a point `distance` away in a compass bearing (0 up, 90 right)
	compassTarget(hero, bearing, candidates) -> candidate | nil
	    candidates = { { id, x, y, unexplored = bool, recommended = bool } }. Picks the candidate closest to the
	    bearing (within 70 degrees), preferring a recommended road, then an unexplored one, when several are
	    within 25 degrees of the best angle; nil when none is within 70 degrees of the bearing.
]]

local MapPan = {}

MapPan.WORLD_SCREENS_Y = 2.2
MapPan.MAX_BEARING_DIFF = 70
MapPan.TIE_DIFF = 25

function MapPan.canvasHeight(viewH)
	return math.floor(viewH * MapPan.WORLD_SCREENS_Y)
end

local function clamp1(v, lo, hi)
	if v < lo then return lo end
	if v > hi then return hi end
	return v
end

function MapPan.clamp(x, y, canvasW, canvasH, viewW, viewH)
	local maxX = math.max(0, canvasW - viewW)
	local maxY = math.max(0, canvasH - viewH)
	return clamp1(x, 0, maxX), clamp1(y, 0, maxY)
end

function MapPan.centerOn(px, py, canvasW, canvasH, viewW, viewH)
	return MapPan.clamp(px - viewW / 2, py - viewH / 2, canvasW, canvasH, viewW, viewH)
end

function MapPan.stepToward(px, py, bearing, distance)
	local r = math.rad(bearing)
	return px + math.sin(r) * distance, py - math.cos(r) * distance
end

local atan2 = math.atan2 or math.atan

local function bearingTo(hero, x, y)
	local dx, dy = x - hero.x, y - hero.y
	if dx == 0 and dy == 0 then return nil end
	return math.deg(atan2(dx, -dy)) % 360
end

local function angleDiff(a, b)
	local d = math.abs(a - b) % 360
	return d > 180 and 360 - d or d
end

function MapPan.compassTarget(hero, bearing, candidates)
	local scored = {}
	for _, c in ipairs(candidates or {}) do
		local b = bearingTo(hero, c.x, c.y)
		if b then
			local diff = angleDiff(b, bearing)
			if diff <= MapPan.MAX_BEARING_DIFF then
				scored[#scored + 1] = { c = c, diff = diff }
			end
		end
	end
	if #scored == 0 then return nil end
	table.sort(scored, function(a, b)
		if a.diff ~= b.diff then return a.diff < b.diff end
		return tostring(a.c.id) < tostring(b.c.id)
	end)
	local best = scored[1]
	local pick = best
	for _, s in ipairs(scored) do
		if s.diff - best.diff <= MapPan.TIE_DIFF then
			local function rank(x)
				return (x.c.recommended and 2 or 0) + (x.c.unexplored and 1 or 0)
			end
			if rank(s) > rank(pick) then pick = s end
		end
	end
	return pick.c
end

return MapPan
