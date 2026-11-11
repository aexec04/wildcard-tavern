--[[
	Client/CollectionRoom.lua
	The Collection opens in a gallery room, like the Menu is a tavern room: six objects on its walls, one per section (the wall of
	framed portraits, the recipe cork board, the boss trophy shelf, the key rack, the nameplate rail and the Bonds board). Each one is a
	hotspot: the pointer makes it glow, its carved name plate carries the count ("Recipes 3/24"), and a click calls onPick(sectionId),
	which zooms into that section's furniture. Look and routing only: counts and entries come from Engine/CollectionBook.lua, the
	positions from Engine/CollectionRoomLayout.lua (tested). The hotspots, the glow and the plates are Client/RoomHotspots.lua (shared
	with the Badges trophy room); this file draws the six objects.

	The room is drawn from plain frames (colour stops only, never gradient transparency); a painted room can replace the drawing later
	and keeps the same hotspots. Calm mode (Reduce shake) keeps the highlight but moves nothing and creates no tween.

	CollectionRoom.new({ parent, names = { [id] = label }, onPick = function(id), zIndex }) ->
		{ frame, spots = { [id] = { hotspot, surface, object, glow, plate, label, newTag } }, layout(w, h), update(counts, fresh) }
]]

local Engine = game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine")
local Layout = require(Engine:WaitForChild("CollectionRoomLayout"))
local RoomHotspots = require(script.Parent.RoomHotspots)

local CollectionRoom = {}

local P, piece, stroke = RoomHotspots.PALETTE, RoomHotspots.piece, RoomHotspots.stroke

-- ===== the six drawn objects (z = the object's own layer; pieces step up from it) =====
local BUILD = {}

function BUILD.portraits(o, z)
	piece(o, "Backing", 0, 0, 1, 1, P.WOOD_DARK, z, 6)
	for i, f in ipairs({ { 0.05, 0.18, 0.27, 0.68 }, { 0.365, 0.07, 0.27, 0.80 }, { 0.68, 0.18, 0.27, 0.68 } }) do
		local gilt = piece(o, "Frame" .. i, f[1], f[2], f[3], f[4], P.BRASS, z + 1, 3)
		local canvas = piece(gilt, "Canvas", 0.14, 0.09, 0.72, 0.82, P.CANVAS, z + 2, 2)
		piece(canvas, "Head", 0.28, 0.16, 0.44, 0.30, P.SILHOUETTE, z + 3, 99)
		piece(canvas, "Shoulders", 0.12, 0.54, 0.76, 0.46, P.SILHOUETTE, z + 3, 8)
	end
end

function BUILD.cork(o, z)
	local board = piece(o, "Board", 0, 0, 1, 1, P.CORK, z, 5)
	stroke(board, P.CORK_EDGE, 4)
	for i, n in ipairs({ { 0.10, 0.14, 0.26, 0.34, -3 }, { 0.40, 0.10, 0.26, 0.34, 2 }, { 0.70, 0.16, 0.22, 0.30, -2 },
		{ 0.20, 0.56, 0.28, 0.32, 2 }, { 0.56, 0.58, 0.26, 0.30, -1 } }) do
		local note = piece(board, "Note" .. i, n[1], n[2], n[3], n[4], P.PAPER, z + 1, 2, n[5])
		piece(note, "Pin", 0.38, -0.08, 0.24, 0.18, P.PIN_RED, z + 2, 99)
	end
end

function BUILD.trophies(o, z)
	piece(o, "Wall", 0, 0, 1, 1, P.WOOD_DARK, z, 6)
	piece(o, "Plank", 0.04, 0.68, 0.92, 0.14, P.WOOD, z + 1, 2)
	piece(o, "PlankTop", 0.04, 0.68, 0.92, 0.03, P.WOOD_LIGHT, z + 2)
	piece(o, "BrassRail", 0.04, 0.80, 0.92, 0.02, P.BRASS, z + 2)
	for i, x in ipairs({ 0.14, 0.42, 0.70 }) do
		piece(o, "Base" .. i, x, 0.58, 0.16, 0.10, P.WOOD_LIGHT, z + 2, 3)
		piece(o, "Stem" .. i, x + 0.065, 0.44, 0.03, 0.14, P.BRASS, z + 2)
		piece(o, "Cup" .. i, x + 0.03, 0.22, 0.10, 0.22, P.BRASS_BRIGHT, z + 3, 5)
	end
end

function BUILD.keys(o, z)
	piece(o, "Wall", 0, 0, 1, 1, P.WOOD_DARK, z, 6)
	piece(o, "Rail", 0.04, 0.10, 0.92, 0.09, P.RAIL, z + 1, 3)
	for i, x in ipairs({ 0.14, 0.42, 0.70 }) do
		piece(o, "Hook" .. i, x + 0.065, 0.12, 0.05, 0.08, P.BRASS, z + 2, 99)
		piece(o, "Chain" .. i, x + 0.085, 0.20, 0.012, 0.12, P.CHAIN, z + 2)
		local tag = piece(o, "Tag" .. i, x, 0.32, 0.16, 0.44, P.TICKET, z + 2, 5)
		piece(tag, "Hole", 0.38, 0.10, 0.24, 0.12, P.WOOD_DARK, z + 3, 99)
	end
end

function BUILD.plates(o, z)
	piece(o, "Wall", 0, 0, 1, 1, P.WOOD_DARK, z, 6)
	piece(o, "Rail", 0.05, 0.10, 0.90, 0.07, P.RAIL, z + 1, 2)
	for i = 1, 2 do
		local plate = piece(o, "Plate" .. i, 0.12, 0.24 + (i - 1) * 0.36, 0.76, 0.28, P.BRASS, z + 1, 3)
		stroke(plate, P.BRASS_BRIGHT, 1)
		for _, sx in ipairs({ 0.05, 0.93 }) do
			piece(plate, "Screw", sx, 0.38, 0.03, 0.2, P.BRASS_DULL, z + 2, 99)
		end
	end
end

function BUILD.bonds(o, z)
	local board = piece(o, "Board", 0, 0, 1, 1, P.CORK_EDGE, z, 5)
	stroke(board, P.WOOD, 4)
	-- three cards joined by red string: a horizontal run between the upper two and a vertical drop to the third
	piece(board, "StringAcross", 0.21, 0.145, 0.54, 0.014, P.STRING_RED, z + 2)
	piece(board, "StringDown", 0.475, 0.145, 0.012, 0.42, P.STRING_RED, z + 2)
	for i, c in ipairs({ { 0.08, 0.14 }, { 0.62, 0.14 }, { 0.35, 0.56 } }) do
		local card = piece(board, "Card" .. i, c[1], c[2], 0.26, 0.34, P.PAPER, z + 1, 2, i == 2 and 2 or -2)
		piece(card, "Pin", 0.38, -0.08, 0.24, 0.18, P.PIN_RED, z + 3, 99)
	end
end

function CollectionRoom.new(opts)
	return RoomHotspots.new({
		parent = opts.parent, layout = Layout, build = BUILD, names = opts.names, onPick = opts.onPick, zIndex = opts.zIndex or 22,
		name = "GalleryRoom",
	})
end

return CollectionRoom
