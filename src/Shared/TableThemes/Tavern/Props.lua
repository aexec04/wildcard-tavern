--[[
	TableThemes/Tavern/Props.lua
	What stands on and around the Tavern table. Every prop is a name, a place and a list of plain parts; the scene
	builder (Client/Table3D/Scene) knows nothing about candles or mugs, so another theme can stand anything here.

	prop   { name, at = { x, y, z }, yaw = degrees, hop = studs a scoring thump lifts it, parts = { part, ... },
	         light = { offset, color, brightness, range, shadows, flicker } }
	part   { shape = "Block" | "Cylinder" | "Ball" | "Wedge", size, offset = { x, y, z }, rot = { x, y, z }, mat }
	       size: Block and Wedge { x, y, z }; Cylinder { diameter, height } standing upright; Ball { diameter }

	Places are studs from the table's middle: x right, y up from the felt (the rail's top is y = 0.55), z toward the
	player. The felt reaches x = 19 and z = 8.25 either way. Keep the middle of the felt clear: the cards play there,
	and the 2D board, the Patron row and the corner icons cover the left edge and most of the far rail.
]]

local RAIL = 0.55

local function cyl(d, h, x, y, z, mat, rot)
	return { shape = "Cylinder", size = { d, h }, offset = { x, y + h / 2, z }, mat = mat, rot = rot }
end

local function block(sx, sy, sz, x, y, z, mat, rot)
	return { shape = "Block", size = { sx, sy, sz }, offset = { x, y + sy / 2, z }, mat = mat, rot = rot }
end

local function add(list, more)
	for _, piece in ipairs(more) do list[#list + 1] = piece end
	return list
end

-- a candle standing at (x, z): wax, wick and a small flame
local function candle(x, z, height, width)
	width = width or 0.5
	return {
		cyl(width, height, x, 0, z, "wax"),
		cyl(0.06, 0.14, x, height, z, "wick"),
		cyl(0.2, 0.44, x, height + 0.12, z, "flame"),
	}
end

-- coins stacked at (x, z), each a hair off the one below (the same every time)
local function coins(x, z, count)
	local out = {}
	for i = 1, count do
		local dx = ((i * 37) % 7 - 3) * 0.012
		local dz = ((i * 53) % 7 - 3) * 0.012
		out[#out + 1] = cyl(0.56, 0.07, x + dx, (i - 1) * 0.075, z + dz, "coin")
	end
	return out
end

-- a die at (x, z) turned `yaw` degrees, showing `pips` on top (1 to 6)
local PIPS = {
	{ { 0, 0 } },
	{ { -1, -1 }, { 1, 1 } },
	{ { -1, -1 }, { 0, 0 }, { 1, 1 } },
	{ { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } },
	{ { -1, -1 }, { 1, -1 }, { 0, 0 }, { -1, 1 }, { 1, 1 } },
	{ { -1, -1 }, { 1, -1 }, { -1, 0 }, { 1, 0 }, { -1, 1 }, { 1, 1 } },
}
local function die(x, z, size, yaw, pips)
	local out = { block(size, size, size, x, 0, z, "bone", { 0, yaw, 0 }) }
	local c, s = math.cos(math.rad(yaw)), math.sin(math.rad(yaw))
	for _, spot in ipairs(PIPS[pips] or PIPS[1]) do
		local px, pz = spot[1] * size * 0.27, spot[2] * size * 0.27
		out[#out + 1] = cyl(size * 0.17, 0.012, x + px * c + pz * s, size, z - px * s + pz * c, "wick")
	end
	return out
end

-- a stack of chips: every other piece is the stripe
local function chips(x, z, count, mat)
	local out = {}
	for i = 1, count do
		out[#out + 1] = cyl(0.84, 0.12, x, 0.2 + (i - 1) * 0.125, z, i % 2 == 0 and "chipStripe" or mat)
	end
	return out
end

local props = {}

-- far left corner of the felt: three candles on a pewter plate, the brightest spot on the table
do
	local parts = { cyl(2.7, 0.09, 0, 0, 0, "pewter") }
	add(parts, candle(-0.55, 0.15, 1.5, 0.56))
	add(parts, candle(0.5, -0.35, 1.05))
	add(parts, candle(0.3, 0.6, 0.7))
	props[#props + 1] = {
		name = "CandlePlate", at = { -9.6, 0, -6.3 }, hop = 0.05, parts = parts,
		light = { offset = { -0.1, 2.1, 0.1 }, color = { 255, 168, 88 }, brightness = 1.7, range = 13, shadows = true, flicker = 1 },
	}
end

-- a pewter mug of ale behind the candles
props[#props + 1] = {
	name = "Mug", at = { -7.4, 0, -7.4 }, yaw = 24, hop = 0.12,
	parts = {
		cyl(1.05, 1.25, 0, 0, 0, "pewter"),
		cyl(0.86, 0.06, 0, 1.2, 0, "ale"),
		cyl(0.8, 0.07, 0, 1.24, 0, "foam"),
		block(0.14, 0.14, 0.5, 0.62, 0.95, 0, "pewter"),
		block(0.14, 0.7, 0.14, 0.82, 0.32, 0, "pewter"),
		block(0.14, 0.14, 0.5, 0.62, 0.25, 0, "pewter"),
	},
}

-- winnings: three stacks of coins and two that rolled off
do
	local parts = coins(0, 0, 6)
	add(parts, coins(0.72, 0.3, 3))
	add(parts, coins(0.25, 0.78, 8))
	parts[#parts + 1] = cyl(0.56, 0.07, -0.75, 0, 0.55, "coin")
	parts[#parts + 1] = cyl(0.56, 0.07, 1.25, 0, -0.5, "coin", { 0, 0, 0 })
	props[#props + 1] = { name = "Coins", at = { -6.4, 0, -5.0 }, hop = 0.16, parts = parts }
end

-- far right: one tall candle in an iron holder
do
	local parts = {
		cyl(1.3, 0.12, 0, 0, 0, "pewter"),
		cyl(0.22, 0.5, 0, 0.12, 0, "pewter"),
		cyl(0.85, 0.1, 0, 0.6, 0, "pewter"),
	}
	for _, piece in ipairs(candle(0, 0, 1.3, 0.5)) do
		piece.offset[2] = piece.offset[2] + 0.7
		parts[#parts + 1] = piece
	end
	props[#props + 1] = {
		name = "TallCandle", at = { 17.0, 0, -4.6 }, hop = 0.04, parts = parts,
		light = { offset = { 0, 2.6, 0 }, color = { 255, 174, 96 }, brightness = 1.5, range = 14, shadows = true, flicker = 1 },
	}
end

-- a green bottle on the near rail, and the ledger under the board
props[#props + 1] = {
	name = "Bottle", at = { 10.2, RAIL, 9.4 }, hop = 0.1,
	parts = {
		cyl(0.85, 1.5, 0, 0, 0, "bottle"),
		cyl(0.34, 0.75, 0, 1.5, 0, "bottle"),
		cyl(0.3, 0.2, 0, 2.2, 0, "cork"),
	},
}
props[#props + 1] = {
	name = "Ledger", at = { -13.2, RAIL, 9.35 }, yaw = 12, hop = 0.05,
	parts = {
		block(2.1, 0.12, 1.5, 0, 0, 0, "leather"),
		block(1.98, 0.3, 1.4, 0.03, 0.12, 0, "page"),
		block(2.1, 0.12, 1.5, 0, 0.42, 0, "leather"),
	},
}

-- two dice that stopped below the chip rack
do
	local parts = die(0, 0, 0.4, 18, 5)
	add(parts, die(0.72, 0.4, 0.4, -31, 3))
	props[#props + 1] = { name = "Dice", at = { 15.3, 0, 2.7 }, hop = 0.3, parts = parts }
end

-- the house's chips in a wooden rack, right of the play
do
	local parts = { block(3.5, 0.2, 1.5, 0, 0, 0, "railEdge") }
	add(parts, chips(-1.1, 0, 8, "chipChips"))
	add(parts, chips(0, 0, 6, "chipMult"))
	add(parts, chips(1.1, 0, 5, "chipTips"))
	props[#props + 1] = { name = "ChipRack", at = { 15.6, 0, 0.6 }, yaw = -8, hop = 0.06, parts = parts }
end

-- on the near rail: a few tips and a die
do
	local parts = coins(0, 0, 4)
	add(parts, coins(0.7, -0.2, 2))
	parts[#parts + 1] = cyl(0.56, 0.07, -0.8, 0, 0.1, "coin")
	add(parts, die(1.9, 0.05, 0.4, 40, 6))
	props[#props + 1] = { name = "Tips", at = { -9.2, RAIL, 9.35 }, hop = 0.2, parts = parts }
end

return props
