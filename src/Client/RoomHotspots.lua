--[[
	Client/RoomHotspots.lua
	The shared builder for a "room with hotspots" (the Collection's gallery room, the Badges trophy room): a dark wall and floor, and one
	object per section on it. Each object is a hotspot that glows and lifts 3 px under the pointer (calm mode: the glow only, nothing
	moves and no tween is made), carries a carved name plate with its count ("Recipes 3/24", "Roads 2/8"), shows a New tag when
	something was found since the last visit, and calls onPick(sectionId) when it is clicked.

	Hotspot_<id> (Frame) holds Glow, Object (the drawn furniture), NamePlate (with Label), NewTag and Surface, the TextButton that takes
	the click and the hover. Positions come from the layout module (a CollectionRoomLayout-shaped table: SECTIONS, rects, plateText,
	plateTextSize), so they are tested without Roblox.

	RoomHotspots.new({ parent, layout, build = { [objectName] = function(objectFrame, z) }, names = { [id] = label }, onPick, zIndex, name,
	                   wall = { top, bottom, floor, skirting, rim } }) ->
		{ frame, spots = { [id] = { hotspot, surface, object, glow, plate, label, newTag } }, layout(w, h), update(counts, fresh) }
	RoomHotspots.piece / .stroke / .corner / .PALETTE are for the drawers in the room modules.
]]

local TweenService = game:GetService("TweenService")

local ClientSettings = require(script.Parent.ClientSettings)

local RoomHotspots = {}

local P = {
	WOOD_DARK = Color3.fromRGB(62, 42, 26), WOOD = Color3.fromRGB(96, 66, 40), WOOD_LIGHT = Color3.fromRGB(146, 104, 62),
	RAIL = Color3.fromRGB(70, 46, 28), CHAIN = Color3.fromRGB(122, 98, 62),
	BRASS = Color3.fromRGB(196, 156, 74), BRASS_BRIGHT = Color3.fromRGB(240, 206, 120), BRASS_DULL = Color3.fromRGB(110, 90, 54),
	CORK = Color3.fromRGB(168, 124, 78), CORK_EDGE = Color3.fromRGB(96, 64, 38),
	PAPER = Color3.fromRGB(238, 224, 186), TICKET = Color3.fromRGB(214, 184, 112),
	CANVAS = Color3.fromRGB(34, 26, 20), SILHOUETTE = Color3.fromRGB(70, 54, 40),
	PIN_RED = Color3.fromRGB(176, 52, 40), STRING_RED = Color3.fromRGB(188, 44, 44),
	CREAM = Color3.fromRGB(250, 240, 220), GLOW = Color3.fromRGB(255, 196, 110),
	PLATE = Color3.fromRGB(62, 42, 26), PLATE_LIT = Color3.fromRGB(96, 66, 40),
}
RoomHotspots.PALETTE = P

local DEFAULT_WALL = {
	top = Color3.fromRGB(62, 45, 32), bottom = Color3.fromRGB(36, 26, 19), floor = Color3.fromRGB(28, 20, 14),
	skirting = P.WOOD_DARK, rim = Color3.fromRGB(96, 66, 40),
}

local REST_RING = 0.8

local function calm() return ClientSettings.get("reduceShake") == true end

local function corner(inst, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = inst
end
RoomHotspots.corner = corner

local function stroke(inst, color, thickness, transparency)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.Transparency = transparency or 0
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = inst
	return s
end
RoomHotspots.stroke = stroke

-- a decorative frame placed by fractions of its parent (radius 99 makes a circle or oval)
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
RoomHotspots.piece = piece

function RoomHotspots.new(opts)
	local Layout = opts.layout
	local z = opts.zIndex or 22
	local names = opts.names or {}
	local wall = opts.wall or DEFAULT_WALL
	local self = { spots = {}, size = { w = 0, h = 0 } }

	local frame = Instance.new("Frame")
	frame.Name = opts.name or "Room"
	frame.BackgroundColor3 = Color3.new(1, 1, 1)
	frame.BorderSizePixel = 0
	frame.ClipsDescendants = true
	frame.Active = false
	frame.ZIndex = z
	frame.Visible = false
	frame.Parent = opts.parent
	corner(frame, 10)
	stroke(frame, wall.rim or DEFAULT_WALL.rim, 2)
	local gradient = Instance.new("UIGradient") -- colour stops only
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new(wall.top, wall.bottom)
	gradient.Parent = frame
	self.frame = frame

	local floor = piece(frame, "Floor", 0, 0.9, 1, 0.1, wall.floor or DEFAULT_WALL.floor, z)
	piece(floor, "Skirting", 0, 0, 1, 0.12, wall.skirting or DEFAULT_WALL.skirting, z)

	-- The painted room (opts.paintedArt = an Image id, Layout.paintedRects): the picture is sized by the tested cover-fit maths (cropped
	-- by the room's clip, never stretched) and the hotspots sit over its objects. Without the id, or when a crop would cut an object, the
	-- drawn room above stays.
	local painting
	if opts.paintedArt and Layout.paintedRects then
		painting = Instance.new("ImageLabel")
		painting.Name = "Painting"
		painting.BackgroundTransparency = 1
		painting.BorderSizePixel = 0
		painting.Active = false
		painting.Image = opts.paintedArt
		painting.ScaleType = Enum.ScaleType.Stretch -- the size already has the picture's own aspect
		painting.ImageTransparency = 0
		painting.ZIndex = z
		painting.Visible = false
		painting.Parent = frame
	end
	self.painting = painting
	self.isPainted = false

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
		glow.BackgroundColor3 = P.GLOW
		glow.BackgroundTransparency = 1
		glow.BorderSizePixel = 0
		glow.Active = false
		glow.ZIndex = z + 1
		glow.Parent = hotspot
		corner(glow, 10)
		local glowRim = stroke(glow, P.GLOW, 2, REST_RING) -- faint always-on ring: says "click me" with no hover (phones)

		local object = Instance.new("Frame")
		object.Name = "Object"
		object.BackgroundTransparency = 1
		object.BorderSizePixel = 0
		object.Active = false
		object.ZIndex = z + 2
		object.Parent = hotspot
		if opts.build and opts.build[section.object] then opts.build[section.object](object, z + 2) end

		local plate = Instance.new("Frame")
		plate.Name = "NamePlate"
		plate.BackgroundColor3 = P.PLATE
		plate.BorderSizePixel = 0
		plate.Active = false
		plate.ZIndex = z + 8
		plate.Parent = hotspot
		corner(plate, 6)
		local plateRim = stroke(plate, P.BRASS, 1.5)
		local label = Instance.new("TextLabel")
		label.Name = "Label"
		label.BackgroundTransparency = 1
		label.Size = UDim2.new(1, -8, 1, 0)
		label.Position = UDim2.fromOffset(4, 0)
		label.Font = Enum.Font.GothamBold
		label.TextSize = 16
		label.TextColor3 = P.CREAM
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
		spot.home = { x = 0, y = 0 }
		self.spots[id] = spot

		local function setLit(on)
			spot.lit = on
			glow.BackgroundTransparency = on and 0.84 or 1
			glowRim.Transparency = on and 0.3 or REST_RING
			plate.BackgroundColor3 = on and P.PLATE_LIT or P.PLATE
			plateRim.Color = (on or spot.complete) and P.BRASS_BRIGHT or P.BRASS
			plate.Visible = true
			if self.isPainted then return end -- nothing to lift: the object is part of the picture
			if calm() then
				object.Position = UDim2.fromOffset(spot.home.x, spot.home.y)
			else
				local y = spot.home.y - (on and 3 or 0)
				TweenService:Create(object, TweenInfo.new(0.12), { Position = UDim2.fromOffset(spot.home.x, y) }):Play()
			end
		end
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
		local R = painting and Layout.paintedRects(w, h)
		if R and not R.ok then R = nil end
		self.isPainted = R ~= nil
		if painting then
			painting.Visible = R ~= nil
			if R then
				painting.Position = UDim2.fromOffset(math.floor(R.image.x), math.floor(R.image.y))
				painting.Size = UDim2.fromOffset(math.ceil(R.image.w), math.ceil(R.image.h))
			end
		end
		floor.Visible = R == nil
		gradient.Enabled = R == nil
		frame.BackgroundTransparency = R and 1 or 0
		R = R or Layout.rects(w, h)
		for _, id in ipairs(R.order) do
			local r, spot = R.spots[id], self.spots[id]
			local hit = r.hit
			spot.hotspot.Position = UDim2.fromOffset(hit.x, hit.y)
			spot.hotspot.Size = UDim2.fromOffset(hit.w, hit.h)
			spot.home = { x = r.object.x - hit.x, y = r.object.y - hit.y }
			spot.object.Position = UDim2.fromOffset(spot.home.x, spot.home.y)
			spot.object.Size = UDim2.fromOffset(r.object.w, r.object.h)
			spot.object.Visible = not self.isPainted -- drawn furniture is only the fallback
			spot.plate.Visible = true
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
			spot.plate:FindFirstChildOfClass("UIStroke").Color = (spot.lit or spot.complete) and P.BRASS_BRIGHT or P.BRASS
			spot.newTag.Visible = fresh ~= nil and (fresh[id] or 0) > 0
		end
	end

	return self
end

return RoomHotspots
