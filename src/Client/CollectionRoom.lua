--[[
	Client/CollectionRoom.lua
	The Collection opens in a gallery room, like the Menu is a tavern room: six objects on its walls, one per section (the wall of
	framed portraits, the recipe cork board, the boss trophy shelf, the key rack, the nameplate rail and the Bonds board). Each one is a
	hotspot: the pointer makes it glow, its carved name plate carries the count ("Recipes 3/24"), and a click calls onPick(sectionId),
	which zooms into that section's furniture. Look and routing only: counts and entries come from Engine/CollectionBook.lua, the
	positions from Engine/CollectionRoomLayout.lua (tested).

	The room is drawn from plain frames (colour stops only, never gradient transparency); a painted room can replace the drawing later
	and keeps the same hotspots. Calm mode (Reduce shake) keeps the highlight but moves nothing and creates no tween.

	Hotspot_<id> (Frame) holds Glow, Object (the drawn furniture), NamePlate (with Label), NewTag and Surface, the TextButton that
	takes the click and the hover.

	CollectionRoom.new({ parent, names = { [id] = label }, onPick = function(id), zIndex }) ->
		{ frame, spots = { [id] = { hotspot, surface, object, glow, plate, label, newTag } }, layout(w, h), update(counts, fresh) }
]]

local TweenService = game:GetService("TweenService")

local Engine = game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine")
local Layout = require(Engine:WaitForChild("CollectionRoomLayout"))
local ClientSettings = require(script.Parent.ClientSettings)

local CollectionRoom = {}

local WALL_TOP, WALL_BOTTOM = Color3.fromRGB(62, 45, 32), Color3.fromRGB(36, 26, 19)
local FLOOR = Color3.fromRGB(28, 20, 14)
local WOOD_DARK, WOOD, WOOD_LIGHT = Color3.fromRGB(62, 42, 26), Color3.fromRGB(96, 66, 40), Color3.fromRGB(146, 104, 62)
local RAIL, CHAIN = Color3.fromRGB(70, 46, 28), Color3.fromRGB(122, 98, 62)
local BRASS, BRASS_BRIGHT, BRASS_DULL = Color3.fromRGB(196, 156, 74), Color3.fromRGB(240, 206, 120), Color3.fromRGB(110, 90, 54)
local CORK, CORK_EDGE = Color3.fromRGB(168, 124, 78), Color3.fromRGB(96, 64, 38)
local PAPER, TICKET = Color3.fromRGB(238, 224, 186), Color3.fromRGB(214, 184, 112)
local CANVAS, SILHOUETTE = Color3.fromRGB(34, 26, 20), Color3.fromRGB(70, 54, 40)
local PIN_RED, STRING_RED = Color3.fromRGB(176, 52, 40), Color3.fromRGB(188, 44, 44)
local CREAM = Color3.fromRGB(250, 240, 220)
local GLOW = Color3.fromRGB(255, 196, 110)
local PLATE, PLATE_LIT = Color3.fromRGB(62, 42, 26), Color3.fromRGB(96, 66, 40)

local function calm() return ClientSettings.get("reduceShake") == true end

local function corner(inst, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = inst
end

local function stroke(inst, color, thickness, transparency)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.Transparency = transparency or 0
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = inst
	return s
end

-- a decorative frame placed by fractions of its parent
local function piece(parent, name, x, y, w, h, color, z, radius, rotation)
	local f = Instance.new("Frame")
	f.Name = name
	f.BorderSizePixel = 0
	f.Active = false
	f.Position = UDim2.fromScale(x, y)
	f.Size = UDim2.fromScale(w, h)
	f.BackgroundColor3 = color
	f.BackgroundTransparency = 0
	f.ZIndex = z
	if rotation then f.Rotation = rotation end
	f.Parent = parent
	if radius then corner(f, radius) end
	return f
end

-- ===== the six drawn objects (z = the object's own layer; pieces step up from it) =====
local BUILD = {}

function BUILD.portraits(o, z)
	piece(o, "Backing", 0, 0, 1, 1, WOOD_DARK, z, 6)
	for i, f in ipairs({ { 0.05, 0.18, 0.27, 0.68 }, { 0.365, 0.07, 0.27, 0.80 }, { 0.68, 0.18, 0.27, 0.68 } }) do
		local gilt = piece(o, "Frame" .. i, f[1], f[2], f[3], f[4], BRASS, z + 1, 3)
		local canvas = piece(gilt, "Canvas", 0.14, 0.09, 0.72, 0.82, CANVAS, z + 2, 2)
		piece(canvas, "Head", 0.28, 0.16, 0.44, 0.30, SILHOUETTE, z + 3, 99)
		piece(canvas, "Shoulders", 0.12, 0.54, 0.76, 0.46, SILHOUETTE, z + 3, 8)
	end
end

function BUILD.cork(o, z)
	local board = piece(o, "Board", 0, 0, 1, 1, CORK, z, 5)
	stroke(board, CORK_EDGE, 4)
	for i, n in ipairs({ { 0.10, 0.14, 0.26, 0.34, -3 }, { 0.40, 0.10, 0.26, 0.34, 2 }, { 0.70, 0.16, 0.22, 0.30, -2 },
		{ 0.20, 0.56, 0.28, 0.32, 2 }, { 0.56, 0.58, 0.26, 0.30, -1 } }) do
		local note = piece(board, "Note" .. i, n[1], n[2], n[3], n[4], PAPER, z + 1, 2, n[5])
		piece(note, "Pin", 0.38, -0.08, 0.24, 0.18, PIN_RED, z + 2, 99)
	end
end

function BUILD.trophies(o, z)
	piece(o, "Wall", 0, 0, 1, 1, WOOD_DARK, z, 6)
	piece(o, "Plank", 0.04, 0.68, 0.92, 0.14, WOOD, z + 1, 2)
	piece(o, "PlankTop", 0.04, 0.68, 0.92, 0.03, WOOD_LIGHT, z + 2)
	piece(o, "BrassRail", 0.04, 0.80, 0.92, 0.02, BRASS, z + 2)
	for i, x in ipairs({ 0.14, 0.42, 0.70 }) do
		piece(o, "Base" .. i, x, 0.58, 0.16, 0.10, WOOD_LIGHT, z + 2, 3)
		piece(o, "Stem" .. i, x + 0.065, 0.44, 0.03, 0.14, BRASS, z + 2)
		piece(o, "Cup" .. i, x + 0.03, 0.22, 0.10, 0.22, BRASS_BRIGHT, z + 3, 5)
	end
end

function BUILD.keys(o, z)
	piece(o, "Wall", 0, 0, 1, 1, WOOD_DARK, z, 6)
	piece(o, "Rail", 0.04, 0.10, 0.92, 0.09, RAIL, z + 1, 3)
	for i, x in ipairs({ 0.14, 0.42, 0.70 }) do
		piece(o, "Hook" .. i, x + 0.065, 0.12, 0.05, 0.08, BRASS, z + 2, 99)
		piece(o, "Chain" .. i, x + 0.085, 0.20, 0.012, 0.12, CHAIN, z + 2)
		local tag = piece(o, "Tag" .. i, x, 0.32, 0.16, 0.44, TICKET, z + 2, 5)
		piece(tag, "Hole", 0.38, 0.10, 0.24, 0.12, WOOD_DARK, z + 3, 99)
	end
end

function BUILD.plates(o, z)
	piece(o, "Wall", 0, 0, 1, 1, WOOD_DARK, z, 6)
	piece(o, "Rail", 0.05, 0.10, 0.90, 0.07, RAIL, z + 1, 2)
	for i = 1, 2 do
		local plate = piece(o, "Plate" .. i, 0.12, 0.24 + (i - 1) * 0.36, 0.76, 0.28, BRASS, z + 1, 3)
		stroke(plate, BRASS_BRIGHT, 1)
		for _, sx in ipairs({ 0.05, 0.93 }) do
			piece(plate, "Screw", sx, 0.38, 0.03, 0.2, BRASS_DULL, z + 2, 99)
		end
	end
end

function BUILD.bonds(o, z)
	local board = piece(o, "Board", 0, 0, 1, 1, CORK_EDGE, z, 5)
	stroke(board, WOOD, 4)
	-- three cards joined by red string: a horizontal run between the upper two and a vertical drop to the third
	piece(board, "StringAcross", 0.21, 0.145, 0.54, 0.014, STRING_RED, z + 2)
	piece(board, "StringDown", 0.475, 0.145, 0.012, 0.42, STRING_RED, z + 2)
	for i, c in ipairs({ { 0.08, 0.14 }, { 0.62, 0.14 }, { 0.35, 0.56 } }) do
		local card = piece(board, "Card" .. i, c[1], c[2], 0.26, 0.34, PAPER, z + 1, 2, i == 2 and 2 or -2)
		piece(card, "Pin", 0.38, -0.08, 0.24, 0.18, PIN_RED, z + 3, 99)
	end
end

-- ===== the room =====
function CollectionRoom.new(opts)
	local z = opts.zIndex or 22
	local names = opts.names or {}
	local self = { spots = {}, size = { w = 0, h = 0 } }

	local frame = Instance.new("Frame")
	frame.Name = "GalleryRoom"
	frame.BackgroundColor3 = Color3.new(1, 1, 1)
	frame.BorderSizePixel = 0
	frame.ClipsDescendants = true
	frame.Active = false
	frame.ZIndex = z
	frame.Visible = false
	frame.Parent = opts.parent
	corner(frame, 10)
	stroke(frame, Color3.fromRGB(96, 66, 40), 2)
	local wall = Instance.new("UIGradient") -- colour stops only
	wall.Rotation = 90
	wall.Color = ColorSequence.new(WALL_TOP, WALL_BOTTOM)
	wall.Parent = frame
	self.frame = frame

	local floor = piece(frame, "Floor", 0, 0.9, 1, 0.1, FLOOR, z)
	piece(floor, "Skirting", 0, 0, 1, 0.12, WOOD_DARK, z)

	for _, section in ipairs(Layout.SECTIONS) do
		local id = section.id
		local hotspot = Instance.new("Frame")
		hotspot.Name = "Hotspot_" .. id
		hotspot.BackgroundTransparency = 1
		hotspot.BorderSizePixel = 0
		hotspot.Active = false
		hotspot.ZIndex = z + 1
		hotspot.Parent = frame

		local glow = Instance.new("Frame")
		glow.Name = "Glow"
		glow.BackgroundColor3 = GLOW
		glow.BackgroundTransparency = 1
		glow.BorderSizePixel = 0
		glow.Active = false
		glow.ZIndex = z + 1
		glow.Parent = hotspot
		corner(glow, 10)
		local glowRim = stroke(glow, GLOW, 3, 1)

		local object = Instance.new("Frame")
		object.Name = "Object"
		object.BackgroundTransparency = 1
		object.BorderSizePixel = 0
		object.Active = false
		object.ZIndex = z + 2
		object.Parent = hotspot
		BUILD[section.object](object, z + 2)

		local plate = Instance.new("Frame")
		plate.Name = "NamePlate"
		plate.BackgroundColor3 = PLATE
		plate.BorderSizePixel = 0
		plate.Active = false
		plate.ZIndex = z + 8
		plate.Parent = hotspot
		corner(plate, 6)
		local plateRim = stroke(plate, BRASS, 1.5)
		local label = Instance.new("TextLabel")
		label.Name = "Label"
		label.BackgroundTransparency = 1
		label.Size = UDim2.new(1, -8, 1, 0)
		label.Position = UDim2.fromOffset(4, 0)
		label.Font = Enum.Font.GothamBold
		label.TextSize = 16
		label.TextColor3 = CREAM
		label.TextTransparency = 0
		label.TextStrokeTransparency = 1
		label.TextTruncate = Enum.TextTruncate.AtEnd
		label.Text = Layout.plateText(names[id] or id, 0, 0)
		label.Active = false
		label.ZIndex = z + 9
		label.Parent = plate

		local newTag = Instance.new("TextLabel")
		newTag.Name = "NewTag"
		newTag.Size = UDim2.fromOffset(38, 18)
		newTag.Position = UDim2.fromOffset(2, 2)
		newTag.BackgroundColor3 = Color3.fromRGB(214, 170, 74)
		newTag.BorderSizePixel = 0
		newTag.Font = Enum.Font.GothamBold
		newTag.TextSize = 14
		newTag.TextColor3 = Color3.fromRGB(40, 26, 14)
		newTag.TextTransparency = 0
		newTag.TextStrokeTransparency = 1
		newTag.Text = "New"
		newTag.Visible = false
		newTag.Active = false
		newTag.ZIndex = z + 10
		newTag.Parent = hotspot
		corner(newTag, 5)

		local surface = Instance.new("TextButton")
		surface.Name = "Surface"
		surface.Text = ""
		surface.AutoButtonColor = false
		surface.BackgroundTransparency = 1
		surface.BorderSizePixel = 0
		surface.Size = UDim2.fromScale(1, 1)
		surface.ZIndex = z + 11
		surface.Parent = hotspot

		local spot = { hotspot = hotspot, surface = surface, object = object, glow = glow, plate = plate, label = label, newTag = newTag, lit = false, complete = false }
		self.spots[id] = spot

		local function setLit(on)
			spot.lit = on
			glow.BackgroundTransparency = on and 0.84 or 1
			glowRim.Transparency = on and 0.3 or 1
			plate.BackgroundColor3 = on and PLATE_LIT or PLATE
			plateRim.Color = (on or spot.complete) and BRASS_BRIGHT or BRASS
			if calm() then
				object.Position = UDim2.fromOffset(spot.home.x, spot.home.y)
			else
				local y = spot.home.y - (on and 3 or 0)
				TweenService:Create(object, TweenInfo.new(0.12), { Position = UDim2.fromOffset(spot.home.x, y) }):Play()
			end
		end
		spot.home = { x = 0, y = 0 }
		spot.setLit = setLit
		surface.MouseEnter:Connect(function() setLit(true) end)
		surface.MouseLeave:Connect(function() setLit(false) end)
		surface.MouseButton1Click:Connect(function()
			if opts.onPick then opts.onPick(id) end
		end)
	end

	-- Place every hotspot on its rectangle of the room (the room is w x h px).
	function self.layout(w, h)
		self.size = { w = w, h = h }
		local R = Layout.rects(w, h)
		for _, id in ipairs(R.order) do
			local r, spot = R.spots[id], self.spots[id]
			local hit = r.hit
			spot.hotspot.Position = UDim2.fromOffset(hit.x, hit.y)
			spot.hotspot.Size = UDim2.fromOffset(hit.w, hit.h)
			spot.home = { x = r.object.x - hit.x, y = r.object.y - hit.y }
			spot.object.Position = UDim2.fromOffset(spot.home.x, spot.home.y)
			spot.object.Size = UDim2.fromOffset(r.object.w, r.object.h)
			local pad = 6
			spot.glow.Position = UDim2.fromOffset(spot.home.x - pad, spot.home.y - pad)
			spot.glow.Size = UDim2.fromOffset(r.object.w + 2 * pad, r.object.h + 2 * pad)
			spot.plate.Position = UDim2.fromOffset(r.plate.x - hit.x, r.plate.y - hit.y)
			spot.plate.Size = UDim2.fromOffset(r.plate.w, r.plate.h)
			spot.label.TextSize = Layout.plateTextSize(r.plate.w)
		end
	end

	-- counts = { [id] = { found, total } }, fresh = { [id] = how many entries are new since the last visit }
	function self.update(counts, fresh)
		for id, spot in pairs(self.spots) do
			local c = counts and counts[id] or { found = 0, total = 0 }
			spot.label.Text = Layout.plateText(names[id] or id, c.found, c.total)
			spot.complete = c.total > 0 and c.found >= c.total -- a finished section keeps a bright brass rim
			spot.plate:FindFirstChildOfClass("UIStroke").Color = (spot.lit or spot.complete) and BRASS_BRIGHT or BRASS
			spot.newTag.Visible = fresh ~= nil and (fresh[id] or 0) > 0
		end
	end

	return self
end

return CollectionRoom
