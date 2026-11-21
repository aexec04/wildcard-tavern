--[[
	Shared/Engine/MapRouteRules.lua
	Pure rules for the Tavern Map's clean route view. No Roblox types.

	dashes(curve, r1, r2, dash, gap) -> list of { x, y, angle, len } dashes laid by arc length along a quadratic curve, starting r1 pixels
	                                    from the first end and stopping r2 pixels before the second (the node edges), evenly spaced
	curve(ax, ay, bx, by, sign, bend)-> { ax, ay, cx, cy, bx, by } a smooth curve whose control point is pushed sideways by bend * length
	plate(name, textSize, maxW)      -> { w, h, lines, wrap } name plate size: text plus 24, never wider than maxW (180), two lines at most
	stopLook(depth, night, flags)    -> "full" | "bubble" | "hidden" for a stop that is off the player's road
	sideLook(parentDepth, night, flags) -> "full" | "bubble" | "hidden" for a side stop
	boxesOverlap(a, b)               -> true when two { x, y, w, h } rects overlap
]]

local M = {}

-- Luau has math.atan2; plain Lua 5.3 and later take two arguments in math.atan
local ATAN2 = math.atan2 or function(y, x) return math.atan(y, x) end

M.DASH, M.GAP, M.PLATE_MAX, M.PLATE_PAD = 14, 10, 180, 24

function M.curve(ax, ay, bx, by, sign, bend)
	local dx, dy = bx - ax, by - ay
	local len = math.sqrt(dx * dx + dy * dy)
	local nx, ny = -dy / math.max(len, 1), dx / math.max(len, 1)
	local push = len * (bend or 0.1) * (sign or 1)
	return { ax = ax, ay = ay, bx = bx, by = by, cx = (ax + bx) / 2 + nx * push, cy = (ay + by) / 2 + ny * push }
end

local function at(c, t)
	local u = 1 - t
	return u * u * c.ax + 2 * u * t * c.cx + t * t * c.bx, u * u * c.ay + 2 * u * t * c.cy + t * t * c.by
end
M.at = at

-- arc length table of the curve (fine steps), used to place dashes at equal distances
local STEPS = 64
local function table_(c)
	local ts, ds, total = { 0 }, { 0 }, 0
	local px, py = at(c, 0)
	for i = 1, STEPS do
		local x, y = at(c, i / STEPS)
		total = total + math.sqrt((x - px) ^ 2 + (y - py) ^ 2)
		ts[i + 1], ds[i + 1] = i / STEPS, total
		px, py = x, y
	end
	return ts, ds, total
end

local function tAtDistance(ts, ds, d)
	for i = 2, #ds do
		if ds[i] >= d then
			local span = ds[i] - ds[i - 1]
			local f = span > 0 and (d - ds[i - 1]) / span or 0
			return ts[i - 1] + (ts[i] - ts[i - 1]) * f
		end
	end
	return 1
end

function M.dashes(c, r1, r2, dash, gap)
	dash, gap = dash or M.DASH, gap or M.GAP
	local ts, ds, total = table_(c)
	local from, to = r1 or 0, total - (r2 or 0)
	local out = {}
	local d = from
	while d + dash <= to + 0.001 do
		local ta, tb = tAtDistance(ts, ds, d), tAtDistance(ts, ds, d + dash)
		local x1, y1 = at(c, ta)
		local x2, y2 = at(c, tb)
		out[#out + 1] = { x = (x1 + x2) / 2, y = (y1 + y2) / 2, angle = math.deg(ATAN2(y2 - y1, x2 - x1)), len = dash }
		d = d + dash + gap
	end
	return out, total
end

-- GothamBold is about 0.6 of the text size per character (a safe over-estimate)
function M.textWidth(text, size)
	return math.ceil(#text * size * 0.6)
end

function M.plate(name, textSize, maxW)
	maxW = maxW or M.PLATE_MAX
	local tw = M.textWidth(name, textSize)
	local lineH = textSize + 4
	if tw + M.PLATE_PAD <= maxW then
		return { w = tw + M.PLATE_PAD, h = lineH + 2, lines = 1, wrap = false }
	end
	local inner = maxW - M.PLATE_PAD
	local lines = math.min(2, math.ceil(tw / inner))
	return { w = maxW, h = lines * lineH + 2, lines = lines, wrap = true }
end

-- A stop that is not on the player's road. flags: choice (a pending fork offers it), lit (the compass points at it), seen, teaser (fog says "?").
-- Only the stops one Night ahead are drawn; far ones stay out of sight so the map shows one clean route.
function M.stopLook(depth, night, flags)
	flags = flags or {}
	if flags.choice or flags.lit then return "full" end
	if depth > night + 1 then return "hidden" end
	if flags.teaser then return "bubble" end
	return "full"
end

function M.sideLook(parentDepth, night, flags)
	flags = flags or {}
	if parentDepth > night + 1 then return "hidden" end
	if flags.stub then
		return (flags.glow or parentDepth <= night) and "bubble" or "hidden"
	end
	return "full"
end

function M.boxesOverlap(a, b)
	return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

return M
