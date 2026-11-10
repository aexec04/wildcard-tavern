--[[
	Shared/Engine/CollectionFurnitureLayout.lua
	Pure maths for the Collection's tab furniture. THE RULE: furniture is derived from the cells, never the other way round.
	Every piece is a rect in the pixels of ONE cell (origin = the cell's top-left) and is drawn inside that cell's own tile, so it
	scrolls with it and can never drift from it. Neighbouring pieces extend half a gap into the gap between cells so planks, rails
	and the cork board read as one continuous object per row.

	kinds: "cork" (Recipes, Bonds), "trophy" (Boss Rounds), "key" (House Passes), "plate" (Titles)
	ctx = { col = 0-based column, row = 0-based row, cols, index = 1-based, n = item count }
	M.cell(kind, ctx) -> { cell, anchor = {x,y}, segment, ...kind parts }  (anchor = the point the furniture must hang from or stand on)
]]

local M = {}

M.CELL = {
	cork = { w = 92, h = 108 },
	trophy = { w = 100, h = 132 },
	key = { w = 100, h = 128 },
	plate = { w = 150, h = 56 },
}
M.GAP = { -- { x, y } between cells (the grid's CellPadding)
	cork = { x = 10, y = 10 }, trophy = { x = 10, y = 14 }, key = { x = 10, y = 14 }, plate = { x = 10, y = 18 },
}
M.TAB_KIND = { recipes = "cork", bonds = "cork", bosses = "trophy", housePasses = "key", titles = "plate" }
M.PLAIN = { patrons = true } -- tabs that deliberately draw plain cells (the Patrons tab hangs on the gallery wall instead)
M.MARGIN = 14 -- the cork board shows this far past its outer cards
M.EDGE = 6 -- wooden frame strip on the board's outer edges
M.PLANK_H = 20
M.RAIL_H = 10
M.PIN = 12
M.SCREW = 4

-- how many columns the grid fits in `width` px (matches UIGridLayout, which fits as many whole cells as the width allows)
function M.cols(width, kind)
	local c, g = M.CELL[kind], M.GAP[kind]
	return math.max(1, math.floor((width + g.x) / (c.w + g.x)))
end

local function ctxOf(kind, ctx)
	local cols = math.max(1, ctx.cols or 1)
	local index = ctx.index or 1
	local col = ctx.col or ((index - 1) % cols)
	local row = ctx.row or math.floor((index - 1) / cols)
	local n = ctx.n or index
	return col, row, cols, index, n
end

function M.cell(kind, ctx)
	local c, g = M.CELL[kind], M.GAP[kind]
	local col, row, cols, index, n = ctxOf(kind, ctx)
	local hasLeft = col > 0
	local hasRight = col < cols - 1 and index < n
	local hasAbove = row > 0
	local hasBelow = index + cols <= n
	local out = { kind = kind, cell = { x = 0, y = 0, w = c.w, h = c.h }, col = col, row = row }
	local left = hasLeft and g.x / 2 or 0
	local right = hasRight and g.x / 2 or 0

	if kind == "cork" then
		-- board segment: this cell plus half a gap towards every neighbour, plus the outer margin where there is none
		local l = hasLeft and g.x / 2 or M.MARGIN
		local r = hasRight and g.x / 2 or M.MARGIN
		local t = hasAbove and g.y / 2 or M.MARGIN
		local b = hasBelow and g.y / 2 or M.MARGIN
		out.segment = { x = -l, y = -t, w = c.w + l + r, h = c.h + t + b }
		-- wooden frame strips on the outer edges only
		local e = {}
		if not hasLeft then e[#e + 1] = { x = -l, y = -t, w = M.EDGE, h = out.segment.h } end
		if not hasRight then e[#e + 1] = { x = c.w + r - M.EDGE, y = -t, w = M.EDGE, h = out.segment.h } end
		if not hasAbove then e[#e + 1] = { x = -l, y = -t, w = out.segment.w, h = M.EDGE } end
		if not hasBelow then e[#e + 1] = { x = -l, y = c.h + b - M.EDGE, w = out.segment.w, h = M.EDGE } end
		out.edges = e
		out.card = { x = 0, y = 0, w = c.w, h = c.h }
		out.pin = { x = c.w / 2 - M.PIN / 2, y = -M.PIN / 2 + 4, w = M.PIN, h = M.PIN } -- centre 4 px under the card's top edge
		out.anchor = { x = c.w / 2, y = 0 } -- card top centre
		out.pinCentre = { x = out.pin.x + M.PIN / 2, y = out.pin.y + M.PIN / 2 }
	elseif kind == "trophy" then
		local icon = { x = math.floor((c.w - 48) / 2), y = 6, w = 48, h = 48 }
		local baseW, baseH = 68, 14
		local plankY = icon.y + icon.h + baseH - 8 -- the plank top is exactly the bottom of the base
		local base = { x = math.floor((c.w - baseW) / 2), y = plankY - baseH, w = baseW, h = baseH }
		out.icon, out.base = icon, base
		out.plank = { x = -left - (hasLeft and 0 or 6), y = plankY, w = c.w + left + right + (hasLeft and 0 or 6) + (hasRight and 0 or 6), h = M.PLANK_H }
		out.rail = { x = out.plank.x, y = plankY + M.PLANK_H - 4, w = out.plank.w, h = 2 } -- brass line on the plank's front edge
		out.shadow = { x = base.x - 3, y = plankY - 3, w = base.w + 6, h = 6 } -- contact shadow on the plank top
		out.plate = { x = 4, y = plankY + M.PLANK_H + 2, w = c.w - 8, h = c.h - (plankY + M.PLANK_H + 2) - 2 }
		if col % 4 == 3 then out.bracket = { x = c.w + g.x / 2 - 6, y = plankY + M.PLANK_H, w = 12, h = 16 } end
		out.anchor = { x = c.w / 2, y = plankY } -- where the trophy stands
	elseif kind == "key" then
		local railY = 0
		local hook = { x = math.floor(c.w / 2) - 6, y = 0, w = 12, h = 12 } -- centred on the rail
		out.rail = { x = -left - (hasLeft and 0 or 6), y = railY, w = c.w + left + right + (hasLeft and 0 or 6) + (hasRight and 0 or 6), h = M.RAIL_H }
		out.hook = hook
		out.chain = { x = math.floor(c.w / 2) - 1, y = hook.y + hook.h, w = 2, h = 8 }
		out.ticket = { x = math.floor((c.w - 66) / 2), y = out.chain.y + out.chain.h, w = 66, h = 62 }
		out.icon = { x = math.floor((c.w - 48) / 2), y = out.ticket.y + 7, w = 48, h = 48 }
		out.plate = { x = 4, y = out.ticket.y + out.ticket.h + 4, w = c.w - 8, h = c.h - (out.ticket.y + out.ticket.h + 4) - 2 }
		out.anchor = { x = c.w / 2, y = railY + M.RAIL_H / 2 }
		out.hookCentre = { x = hook.x + hook.w / 2, y = hook.y + hook.h / 2 }
		out.sway = { pivotY = hook.y + hook.h / 2, degrees = 1.5 }
	else -- plate
		out.rail = { x = -left - (hasLeft and 0 or 6), y = -M.RAIL_H / 2, w = c.w + left + right + (hasLeft and 0 or 6) + (hasRight and 0 or 6), h = c.h + M.RAIL_H }
		out.plate = { x = 0, y = 0, w = c.w, h = c.h }
		out.screws = {}
		for _, fx in ipairs({ 0, 1 }) do
			for _, fy in ipairs({ 0, 1 }) do
				out.screws[#out.screws + 1] = { x = 6 + fx * (c.w - 12 - M.SCREW), y = 6 + fy * (c.h - 12 - M.SCREW), w = M.SCREW, h = M.SCREW }
			end
		end
		out.anchor = { x = c.w / 2, y = c.h / 2 }
	end
	return out
end

-- a string sagging between two points (px): n+1 points along a parabola that drops `sag` px at the middle
function M.string(ax, ay, bx, by, n, sag)
	n = math.max(2, n or 8)
	local pts = {}
	for i = 0, n do
		local t = i / n
		pts[#pts + 1] = { x = ax + (bx - ax) * t, y = ay + (by - ay) * t + 4 * (sag or 0) * t * (1 - t) }
	end
	return pts
end

-- centre of the pin of cell `index` in the pixels of cell `fromIndex` (for strings that run from one tile into another)
function M.pinOffset(fromIndex, toIndex, cols)
	local c, g = M.CELL.cork, M.GAP.cork
	local function pos(i)
		return ((i - 1) % cols) * (c.w + g.x), math.floor((i - 1) / cols) * (c.h + g.y)
	end
	local fx, fy = pos(fromIndex)
	local tx, ty = pos(toIndex)
	return tx - fx + c.w / 2, ty - fy + 4
end

return M
