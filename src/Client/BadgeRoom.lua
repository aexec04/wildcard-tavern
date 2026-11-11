--[[
	Client/BadgeRoom.lua
	The Badges panel opens in a trophy room: four objects on its walls, one per shelf of badges (the pinned road map, the navy velvet
	display board, the night window over the rooftops, the shelves). Each is a hotspot with a carved name plate that carries its count
	("Roads 2/8"); a click calls onPick(shelf), which zooms into that object's wall (Client/BadgeWall.lua draws the medals on it) and
	Back or Escape returns. Look and routing only: the counts come from Engine/BadgeWallLayout.sectionCounts, the positions from
	Engine/BadgeRoomLayout.lua (tested). The hotspots, glow and plates are Client/RoomHotspots.lua, shared with the Collection's gallery.

	The objects are drawn from plain frames (colour stops only); the road map shows a pin at each stop's real place
	(BadgeWallLayout.ROAD_STOPS), the same places the medals hang at once you zoom in. A painted room can replace the drawing later.

	BadgeRoom.new({ parent, names = { [shelf] = label }, onPick = function(shelf), zIndex }) -> RoomHotspots (frame, spots, layout, update)
]]

local Engine = game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine")
local Layout = require(Engine:WaitForChild("BadgeRoomLayout"))
local Wall = require(Engine:WaitForChild("BadgeWallLayout"))
local ContentArt = require(Engine:WaitForChild("ContentArt"))
local RoomHotspots = require(script.Parent.RoomHotspots)

local BadgeRoom = {}

local P, piece, stroke = RoomHotspots.PALETTE, RoomHotspots.piece, RoomHotspots.stroke

local PARCHMENT = Color3.fromRGB(214, 188, 140)
local NAVY, NAVY_DEEP = Color3.fromRGB(28, 36, 76), Color3.fromRGB(14, 22, 58)
local DARK_WOOD = Color3.fromRGB(56, 38, 26)
local TRAIL = Color3.fromRGB(150, 128, 92)
local STAR = Color3.fromRGB(230, 236, 255)

local BUILD = {}

-- a pinned map of the roads: a pin at every stop's real place with a dotted trail between them
function BUILD.map(o, z)
	local board = piece(o, "Parchment", 0, 0, 1, 1, PARCHMENT, z, 5)
	stroke(board, Color3.fromRGB(150, 104, 62), 4)
	local order = {}
	for _, d in ipairs(Wall.members("Roads")) do order[#order + 1] = Wall.ROAD_STOPS[d.region] end
	for i = 1, #order - 1 do
		local a, b = order[i], order[i + 1]
		for k = 1, 3 do
			local t = k / 4
			piece(board, "Trail", a[1] + (b[1] - a[1]) * t - 0.01, a[2] + (b[2] - a[2]) * t - 0.012, 0.02, 0.024, TRAIL, z + 1, 99)
		end
	end
	for i, s in ipairs(order) do
		piece(board, "Pin" .. i, s[1] - 0.025, s[2] - 0.03, 0.05, 0.06, P.PIN_RED, z + 2, 99)
	end
end

-- the velvet board: the Master Tavern medal large at the top, seven more in a row below, gold edging
function BUILD.velvet(o, z)
	local board = piece(o, "Velvet", 0, 0, 1, 1, NAVY, z, 5)
	stroke(board, P.BRASS, 3)
	local big = piece(board, "BigSocket", 0.4, 0.08, 0.2, 0.34, NAVY_DEEP, z + 1, 99)
	stroke(big, P.BRASS_BRIGHT, 2)
	for i = 1, 7 do
		local socket = piece(board, "Socket" .. i, 0.04 + (i - 1) * 0.134, 0.58, 0.1, 0.17, NAVY_DEEP, z + 1, 99)
		stroke(socket, P.BRASS, 1.5)
	end
end

-- the night window over the rooftops: a moon, a short line of stars, a dark roofline
function BUILD.sky(o, z)
	local sky = piece(o, "Sky", 0, 0, 1, 1, NAVY_DEEP, z, 5)
	stroke(sky, P.WOOD, 5)
	local moon = piece(sky, "Moon", 0.72, 0.1, 0.18, 0.22, Color3.fromRGB(250, 238, 200), z + 1, 99)
	piece(moon, "Shade", 0.3, -0.1, 0.9, 0.9, NAVY_DEEP, z + 2, 99)
	for i, s in ipairs({ { 0.14, 0.28 }, { 0.32, 0.18 }, { 0.5, 0.34 }, { 0.66, 0.5 } }) do
		piece(sky, "Star" .. i, s[1], s[2], 0.07, 0.1, P.BRASS_BRIGHT, z + 1, 99)
	end
	for i, s in ipairs({ { 0.08, 0.1 }, { 0.42, 0.08 }, { 0.58, 0.2 }, { 0.82, 0.42 }, { 0.2, 0.5 } }) do
		piece(sky, "Dust" .. i, s[1], s[2], 0.02, 0.026, STAR, z + 1, 99)
	end
	piece(sky, "Roof", 0, 0.78, 1, 0.22, Color3.fromRGB(10, 12, 26), z + 2)
	piece(sky, "Chimney1", 0.18, 0.66, 0.08, 0.14, Color3.fromRGB(10, 12, 26), z + 2)
	piece(sky, "Chimney2", 0.64, 0.7, 0.07, 0.1, Color3.fromRGB(10, 12, 26), z + 2)
end

-- two shelves with a row of small sockets resting on each plank
function BUILD.shelves(o, z)
	local back = piece(o, "Back", 0, 0, 1, 1, DARK_WOOD, z, 5)
	stroke(back, P.WOOD, 4)
	for row = 1, 2 do
		local y = row == 1 and 0.42 or 0.84
		piece(back, "Plank" .. row, 0.04, y, 0.92, 0.06, P.WOOD_LIGHT, z + 1, 2)
		for i = 1, 5 do
			local socket = piece(back, "Socket" .. row .. "_" .. i, 0.07 + (i - 1) * 0.18, y - 0.26, 0.12, 0.24, Color3.fromRGB(24, 17, 12), z + 1, 99)
			stroke(socket, P.BRASS, 1.5)
		end
	end
end

-- The painted trophy room (art `badge_wall` / `badge_room`) replaces the drawing when its Image id is recorded and the crop keeps every
-- object; the four hotspots then sit over the picture's own objects (BadgeRoomLayout.PAINTED).
function BadgeRoom.new(opts)
	local paintedArt = ContentArt.getImageId("badge_wall", "badge_room")
	if paintedArt then ContentArt.preload({ { "badge_wall", "badge_room" } }, "badge room") end
	return RoomHotspots.new({
		paintedArt = paintedArt,
		parent = opts.parent, layout = Layout, build = BUILD, names = opts.names, onPick = opts.onPick, zIndex = opts.zIndex or 42,
		name = "TrophyRoom",
		wall = { top = Color3.fromRGB(46, 36, 34), bottom = Color3.fromRGB(26, 20, 22), floor = Color3.fromRGB(20, 15, 14), skirting = P.WOOD_DARK, rim = P.WOOD },
	})
end

return BadgeRoom
