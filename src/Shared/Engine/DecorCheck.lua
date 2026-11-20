--[[
	Engine/DecorCheck.lua
	Pure rules for the Studio only table decor check (DebugGoto "decorcheck", Client/DecorCheck). Reads only.
	check(p) takes rects { x, y, w, h } in the table layer's pixels and returns lines, warns:
	  p.w, p.h   layer size
	  p.felt     the felt ellipse's rect (ConceptTLayout.feltFor(w, h).rim)
	  p.inlay    the gold inlay ellipse's rect
	  p.deck     the painted pile rect (Gameplay2Layout.rects.deck), p.tilt its turn in degrees
	  p.rail     the rail picture { x, w } and its visible box { x, y, w, h } as ConceptTLayout.decorFor returns it (rail.box)
	  p.plates   { { label, rect } } the buttons and count plates the rail must not cover
	Warns when the inlay leaves the felt, the pile leaves the felt, a rail end cap is on screen over a plate, or a plate is off screen.
]]
local CT = require(script.Parent:WaitForChild("ConceptTLayout"))

local M = {}

M.SLACK = 1 -- px of rounding allowed when one rect must lie inside another

local function fmt(label, r)
	return string.format("%s %d,%d,%d,%d", label, math.floor(r.x + 0.5), math.floor(r.y + 0.5), math.floor(r.w + 0.5), math.floor(r.h + 0.5))
end

function M.inside(inner, outer)
	local s = M.SLACK
	return inner.x >= outer.x - s and inner.y >= outer.y - s and inner.x + inner.w <= outer.x + outer.w + s and inner.y + inner.h <= outer.y + outer.h + s
end

local function hit(a, b)
	return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

-- the parts of the rail's two carved end caps that are on screen: { label, rect }
function M.capRects(rail, w)
	local c = CT.RAIL_CAP_ART
	local k = rail.w / c.w
	local out = {}
	local lx0, lx1 = rail.x + c.box0 * k, rail.x + c.left * k
	local rx0, rx1 = rail.x + c.right * k, rail.x + c.box1 * k
	if lx1 > 0 and lx0 < w then out[#out + 1] = { label = "left cap", x = math.max(0, lx0), x1 = math.min(w, lx1) } end
	if rx1 > 0 and rx0 < w then out[#out + 1] = { label = "right cap", x = math.max(0, rx0), x1 = math.min(w, rx1) } end
	for _, o in ipairs(out) do o.rect = { x = o.x, y = rail.box.y, w = o.x1 - o.x, h = rail.box.h } end
	return out
end

function M.check(p)
	local lines, warns = {}, {}
	lines[#lines + 1] = fmt("felt", p.felt)
	lines[#lines + 1] = p.inlay and fmt("inlay", p.inlay) or "inlay none"
	lines[#lines + 1] = fmt("deck", p.deck)
	lines[#lines + 1] = fmt("rail", p.rail.box)
	if p.inlay and not M.inside(p.inlay, p.felt) then
		warns[#warns + 1] = "the inlay leaves the felt: " .. fmt("inlay", p.inlay) .. " vs " .. fmt("felt", p.felt)
	end
	if not CT.insideFelt(p.deck, p.tilt or CT.DECK_TILT, p.w, p.h, 0) then
		warns[#warns + 1] = "the deck leaves the felt: " .. fmt("deck", p.deck)
	end
	for _, c in ipairs(M.capRects(p.rail, p.w)) do
		for _, pl in ipairs(p.plates or {}) do
			if hit(c.rect, pl.rect) then warns[#warns + 1] = "the rail's " .. c.label .. " overlaps " .. tostring(pl.label) end
		end
	end
	for _, pl in ipairs(p.plates or {}) do
		local r = pl.rect
		if r.x < 0 or r.y < 0 or r.x + r.w > p.w or r.y + r.h > p.h then warns[#warns + 1] = tostring(pl.label) .. " is off screen" end
	end
	return lines, warns
end

return M
