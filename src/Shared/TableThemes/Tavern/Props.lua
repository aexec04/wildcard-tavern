--[[
	TableThemes/Tavern/Props.lua
	What stands on and around the Tavern table. Every prop is a name, a place and a list of plain parts; the scene
	builder (Client/Table3D/Scene) knows nothing about candles or mugs, so another theme can stand anything here.

	prop   { name, at = { x, y, z }, yaw = degrees, scale = size multiplier, hop = studs a scoring thump lifts it,
	         parts = { part, ... }, light = { offset, color, brightness, range, shadows, flicker } }
	part   { shape = "Block" | "Cylinder" | "Ball" | "Wedge", size, offset = { x, y, z }, rot = { x, y, z }, mat }
	       size: Block and Wedge { x, y, z }; Cylinder { diameter, height } standing upright; Ball { diameter }

	Places are studs from the table's middle: x right, y up from the felt, z toward the player. The felt reaches
	x = -37 to 43 and z = 18.75 either way; the camera sits at z = 27, 12 studs up, and looks down the table at the back
	wall (z = -46). The hand is held at about z = 12, the played cards lie around z = 4 and the Patrons stand around
	z = -8, between x = -8 and 30: keep those clear. The 2D board covers what is left of about x = -16.
	The first props stand on the table; the rest are the room behind it.
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

-- ON THE TABLE (drawn small, stood at twice the size)

-- far left: three candles on a pewter plate
do
	local parts = { cyl(2.7, 0.09, 0, 0, 0, "pewter") }
	add(parts, candle(-0.55, 0.15, 1.5, 0.56))
	add(parts, candle(0.5, -0.35, 1.05))
	add(parts, candle(0.3, 0.6, 0.7))
	props[#props + 1] = {
		name = "CandlePlate", at = { -14, 0, -11 }, scale = 2, hop = 0.08, parts = parts,
		light = { offset = { -0.1, 2.1, 0.1 }, color = { 255, 168, 88 }, brightness = 1.8, range = 26, shadows = true, flicker = 1 },
	}
end

-- a pewter mug of ale behind the candles
props[#props + 1] = {
	name = "Mug", at = { -10.5, 0, -15.5 }, yaw = 24, scale = 2, hop = 0.2,
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
	parts[#parts + 1] = cyl(0.56, 0.07, 1.25, 0, -0.5, "coin")
	props[#props + 1] = { name = "Coins", at = { -12.5, 0, -4 }, scale = 2, hop = 0.3, parts = parts }
end

-- far right: one tall candle in a pewter holder
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
		name = "TallCandle", at = { 35, 0, -13 }, scale = 2, hop = 0.06, parts = parts,
		light = { offset = { 0, 2.6, 0 }, color = { 255, 174, 96 }, brightness = 1.6, range = 26, shadows = true, flicker = 1 },
	}
end

-- a green bottle and the ledger beside it
props[#props + 1] = {
	name = "Bottle", at = { 39.5, 0, -15 }, scale = 2, hop = 0.15,
	parts = {
		cyl(0.85, 1.5, 0, 0, 0, "bottle"),
		cyl(0.34, 0.75, 0, 1.5, 0, "bottle"),
		cyl(0.3, 0.2, 0, 2.2, 0, "cork"),
	},
}
props[#props + 1] = {
	name = "Ledger", at = { 33, 0, -5 }, yaw = -14, scale = 2, hop = 0.08,
	parts = {
		block(2.1, 0.12, 1.5, 0, 0, 0, "leather"),
		block(1.98, 0.3, 1.4, 0.03, 0.12, 0, "page"),
		block(2.1, 0.12, 1.5, 0, 0.42, 0, "leather"),
	},
}

-- two dice that stopped by the deck
do
	local parts = die(0, 0, 0.4, 18, 5)
	add(parts, die(0.72, 0.4, 0.4, -31, 3))
	props[#props + 1] = { name = "Dice", at = { 21, 0, 4.5 }, scale = 2, hop = 0.5, parts = parts }
end

-- the house's chips in a wooden rack
do
	local parts = { block(3.5, 0.2, 1.5, 0, 0, 0, "railEdge") }
	add(parts, chips(-1.1, 0, 8, "chipChips"))
	add(parts, chips(0, 0, 6, "chipMult"))
	add(parts, chips(1.1, 0, 5, "chipTips"))
	props[#props + 1] = { name = "ChipRack", at = { 27, 0, -1 }, yaw = -12, scale = 2, hop = 0.1, parts = parts }
end

-- a few tips and a die by the player's left hand
do
	local parts = coins(0, 0, 4)
	add(parts, coins(0.7, -0.2, 2))
	parts[#parts + 1] = cyl(0.56, 0.07, -0.8, 0, 0.1, "coin")
	add(parts, die(1.9, 0.05, 0.4, 40, 6))
	props[#props + 1] = { name = "Tips", at = { -13, 0, 3 }, scale = 2, hop = 0.3, parts = parts }
end

-- THE ROOM (full size). The floor is 14 studs under the felt; the picture shows the back wall from about y = -7 to 16.
local WALL_Z, FLOOR = -46, -14

do -- the back wall: planks over a stone footing, posts and a beam
	local parts = {
		block(200, 44, 2, 3, FLOOR + 10, 0, "wall"),
		block(200, 10, 2.6, 3, FLOOR, 0.2, "stone"),
		block(200, 2.6, 3.2, 3, 17, 1, "beam"),
	}
	for _, x in ipairs({ -62, -42, -12, 20, 50, 78 }) do
		parts[#parts + 1] = block(2.6, 54, 2.8, x, FLOOR, 0.8, "beam")
	end
	for _, piece in ipairs(parts) do piece.shadow = false end
	props[#props + 1] = { name = "BackWall", at = { 0, 0, WALL_Z }, parts = parts }
end

do -- the fireplace: a raised stone hearth, the fire, and its glow on the room
	local x = -27
	local parts = {
		block(26, 8, 9, x, FLOOR, 4.5, "stone"), -- the raised hearth
		block(5, 14, 5, x - 10.5, FLOOR + 8, 2.5, "stone"),
		block(5, 14, 5, x + 10.5, FLOOR + 8, 2.5, "stone"),
		block(28, 4, 6, x, FLOOR + 22, 3, "stone"), -- the lintel
		block(20, 16, 3.4, x, FLOOR + 26, 1.6, "stone"), -- the chimney breast
		block(16, 14, 0.6, x, FLOOR + 8, 1.2, "soot"),
		block(11, 1.4, 2.2, x, FLOOR + 8, 3.4, "beam", { 0, 12, 0 }), -- logs
		block(9, 1.3, 2, x + 0.5, FLOOR + 9.2, 3.2, "beam", { 0, -16, 6 }),
	}
	-- the fire: glowing embers along the logs and tongues of flame that thin toward the top
	for i, f in ipairs({ { -3.6, 3 }, { -1.5, 5 }, { 0.8, 4 }, { 3, 2.6 } }) do
		parts[#parts + 1] = { shape = "Ball", size = { 2.4 }, offset = { x + f[1], FLOOR + 10.4, 3.2 }, mat = "ember", shadow = false }
		for step = 1, f[2] do
			local size = 2.3 - step * 0.36
			parts[#parts + 1] = {
				shape = "Ball", size = { size }, mat = step > 2 and "flame" or "fire", shadow = false,
				offset = { x + f[1] + ((i + step) % 3 - 1) * 0.35, FLOOR + 10.6 + step * 1.15, 3.3 },
			}
		end
	end
	props[#props + 1] = {
		name = "Fireplace", at = { 0, 0, WALL_Z }, parts = parts,
		light = { offset = { x, FLOOR + 13, 9 }, color = { 255, 132, 56 }, brightness = 4.4, range = 80, shadows = true, flicker = 1.4 },
	}
end

-- a banner: red cloth, a gold band and a gold lozenge
local function banner(name, x)
	return {
		name = name, at = { x, 0, WALL_Z + 1.4 },
		parts = {
			block(11, 0.7, 0.9, 0, 15.6, 0, "beam"),
			block(9, 15, 0.3, 0, 0.8, 0.1, "banner"),
			{ shape = "Wedge", size = { 0.3, 3, 4.5 }, offset = { -2.25, -0.7, 0.1 }, rot = { 0, 90, 180 }, mat = "banner" },
			{ shape = "Wedge", size = { 0.3, 3, 4.5 }, offset = { 2.25, -0.7, 0.1 }, rot = { 0, -90, 180 }, mat = "banner" },
			block(9, 1, 0.36, 0, 13.4, 0.12, "bannerGold"),
			block(2.4, 2.4, 0.36, 0, 7, 0.12, "bannerGold", { 0, 0, 45 }),
		},
	}
end
props[#props + 1] = banner("BannerLeft", 4)
props[#props + 1] = banner("BannerRight", 36)

-- a lantern: an iron cage round a glowing pane, on a chain or a bracket
local function lantern(name, x, y, z, chain, bright)
	local parts = {
		block(2.2, 0.4, 2.2, 0, 3, 0, "iron"),
		block(2.2, 0.4, 2.2, 0, -0.4, 0, "iron"),
		block(1.5, 3, 1.5, 0, 0, 0, "lampGlass"),
		block(0.9, 0.9, 0.9, 0, 3.4, 0, "iron"),
	}
	for _, c in ipairs({ { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }) do
		parts[#parts + 1] = block(0.3, 3, 0.3, c[1] * 0.95, 0, c[2] * 0.95, "iron")
	end
	if chain > 0 then parts[#parts + 1] = block(0.25, chain, 0.25, 0, 4.3, 0, "iron") end
	for _, piece in ipairs(parts) do piece.shadow = false end
	return {
		name = name, at = { x, y, z }, parts = parts,
		light = { offset = { 0, 1.2, 0.6 }, color = { 255, 186, 104 }, brightness = bright, range = 56, flicker = 0.5 },
	}
end
props[#props + 1] = lantern("LanternLeft", -13, 9.5, -24, 30, 1.7)
props[#props + 1] = lantern("LanternRight", 28, 9.5, -24, 30, 1.7)
props[#props + 1] = lantern("WallLantern", 62, 6, WALL_Z + 3, 0, 0.9)

do -- a shelf of bottles and a keg on the wall
	local parts = { block(22, 0.7, 3, 0, 0, 0, "beam") }
	for i, b in ipairs({ { -9, 3, "bottle" }, { -6.5, 2.2, "pewter" }, { -4, 3.4, "bottle" }, { -1, 2, "wax" }, { 5.5, 2.6, "pewter" }, { 8.5, 3.2, "bottle" } }) do
		parts[#parts + 1] = cyl(1.5, b[2], b[1], 0.7, 0.2 * (i % 2), b[3])
	end
	parts[#parts + 1] = { shape = "Cylinder", size = { 4.4, 5 }, offset = { 2, 2.9, 0 }, rot = { 0, 0, 90 }, mat = "barrel" }
	for _, piece in ipairs(parts) do piece.shadow = false end
	props[#props + 1] = { name = "Shelf", at = { 61, -3, WALL_Z + 2.4 }, parts = parts }
end

return props
