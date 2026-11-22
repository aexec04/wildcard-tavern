--[[
	Client/ShopBackdrop.lua
	Counter v2 back layers for the Shop overlay: the painted back bar wall filling the area, a smooth dark vignette
	(same technique as BossFight), a warm light pool, the counter top across the lower band and four counter props.
	Look only, static (no loops, so calm mode needs nothing). Every piece is skipped when its Image id is missing; the
	backdrop always mounts; without shop_wall or shop_counter_top it draws a warm gradient wall and a wood counter band.
	Geometry comes from Engine/ShopSceneLayout.lua. Everything sits at ZIndex 5 under the offer cards and controls.

	ShopBackdrop.new({ shopFrame }) -> { active, root, relayout(counts), marlo, marloId, marloWaveId, roomId, room }

One painted room: with the shop_room_a Image id and counts.room set (not on phones), the whole Counter is ONE cover-cropped picture
(`Room`), Marlo stands behind it in a frame clipped at the counter top, and the older wall, counter strip, props, table and light
pool are hidden. Without the id, or on a phone, those older pieces show as before.
]]

local Engine = game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine")
local Layout = require(Engine:WaitForChild("ShopSceneLayout"))
local ImageSpace = require(Engine:WaitForChild("ImageSpace"))
local ContentArt = require(Engine:WaitForChild("ContentArt"))
local SoftGlow = require(script.Parent.SoftGlow)

local ShopBackdrop = {}

local function image(parent, name, id, z)
	local img = Instance.new("ImageLabel")
	img.Name = name
	img.BackgroundTransparency = 1
	img.BorderSizePixel = 0
	img.Image = id
	img.Active = false
	img.ZIndex = z or 6
	img.Parent = parent
	return img
end

-- Crop a fraction rect { x, y, w, h } of a 3:2 picture (ImageRect needs the picture's pixel size; the generator
-- writes 1536x1024 for these pieces).
local function crop(img, c)
	img.ScaleType = Enum.ScaleType.Stretch
	local x, y, w, h = ImageSpace.rect(c[1] * 1536, c[2] * 1024, c[3] * 1536, c[4] * 1024, 1536, 1024)
	img.ImageRectOffset = Vector2.new(x, y)
	img.ImageRectSize = Vector2.new(w, h)
end

local function place(obj, r)
	obj.Position = UDim2.fromOffset(r.x, r.y)
	obj.Size = UDim2.fromOffset(r.w, r.h)
end

function ShopBackdrop.new(deps)
	local shopFrame = deps.shopFrame
	local wallId = ContentArt.getImageId("shop_scene", "shop_wall")
	local topId = ContentArt.getImageId("shop_scene", "shop_counter_top")
	local propsId = ContentArt.getImageId("shop_scene", "shop_counter_props")
	local roomId = ContentArt.getImageId("shop_scene", "shop_room_a")
	local self = { active = true, roomId = roomId }
	local older = {} -- the pieces the painted room replaces

	local root = Instance.new("Frame")
	root.Name = "ShopBackdrop"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1
	root.Active = false
	root.ZIndex = 6
	root.ClipsDescendants = true
	root.Parent = shopFrame
	self.root = root
	pcall(function() require(script.Parent.ThemeWash).attach(root, "shopBackdrop") end) -- the equipped Card Set dresses this scene (Engine/ThemeScenes)

	-- Fallback scene (no painted wall yet): a warm vertical gradient wall with a darker wood counter band below it,
	-- so the Counter never reads as an empty dark box. Color stops only, never UIGradient.Transparency.
	local fb = Layout.FALLBACK
	local function rgb(t) return Color3.fromRGB(t[1], t[2], t[3]) end
	if wallId then
		local wall = image(root, "Wall", wallId, 6)
		wall.Size = UDim2.fromScale(1, 1)
		wall.ScaleType = Enum.ScaleType.Crop
		older[#older + 1] = wall
	else
		local wallFrame = Instance.new("Frame")
		wallFrame.Name = "FallbackWall"
		wallFrame.Size = UDim2.fromScale(1, 1)
		wallFrame.BorderSizePixel = 0
		wallFrame.BackgroundColor3 = Color3.new(1, 1, 1)
		wallFrame.Active = false
		wallFrame.ZIndex = 6
		wallFrame.Parent = root
		local g = Instance.new("UIGradient")
		g.Rotation = 90
		g.Color = ColorSequence.new(rgb(fb.wallTop), rgb(fb.wallBottom))
		g.Parent = wallFrame
		older[#older + 1] = wallFrame
	end
	-- the painted room: one picture, cover-cropped (never stretched), above the older wall and below everything else
	local roomImg
	if roomId then
		roomImg = image(root, "Room", roomId, 6)
		roomImg.Size = UDim2.fromScale(1, 1)
		roomImg.ScaleType = Enum.ScaleType.Crop
		roomImg.Visible = false
	end
	self.room = roomImg
	local fallbackCounter = nil
	if not topId then
		fallbackCounter = Instance.new("Frame")
		fallbackCounter.Name = "FallbackCounter"
		fallbackCounter.BorderSizePixel = 0
		fallbackCounter.BackgroundColor3 = rgb(fb.counter)
		fallbackCounter.Active = false
		fallbackCounter.ZIndex = 6
		fallbackCounter.Parent = root
		local edge = Instance.new("Frame")
		edge.Name = "Edge"
		edge.Size = UDim2.new(1, 0, 0, 3)
		edge.BorderSizePixel = 0
		edge.BackgroundColor3 = rgb(fb.counterEdge)
		edge.Active = false
		edge.ZIndex = 6
		edge.Parent = fallbackCounter
		older[#older + 1] = fallbackCounter
	end

	-- Smooth vignette: one gradient frame per edge, no stacked bands.
	require(script.Parent.SmoothVignette).build(root, {
		name = "Vignette", zIndex = 6, color = Color3.fromRGB(14, 8, 4),
		top = { strength = 0.59, extent = 0.1 },
		left = { strength = 0.59, extent = 0.06 },
		right = { strength = 0.59, extent = 0.06 },
	})

	local light = Instance.new("Frame")
	light.Name = "LightPool"
	light.BackgroundColor3 = Color3.fromRGB(255, 196, 110)
	light.BackgroundTransparency = 0.9
	light.BorderSizePixel = 0
	light.Active = false
	light.ZIndex = 6
	light.Parent = root
	older[#older + 1] = light
	do
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0.5, 0)
		c.Parent = light
	end

	-- Marlo stands behind the counter (painted shop_marlo_behind; ShopScene animates him and swaps in the wave piece).
	local marloId = ContentArt.getImageId("shop_scene", "shop_marlo_behind")
	-- his frame is clipped at the counter top line in the painted room, so his feet stay behind the counter
	local marloClip = Instance.new("Frame")
	marloClip.Name = "MarloClip"
	marloClip.Size = UDim2.fromScale(1, 1)
	marloClip.BackgroundTransparency = 1
	marloClip.BorderSizePixel = 0
	marloClip.Active = false
	marloClip.ClipsDescendants = true
	marloClip.ZIndex = 6
	marloClip.Parent = root
	local marlo = marloId and image(marloClip, "Marlo", marloId, 6) or nil
	if marlo then
		marlo.ScaleType = Enum.ScaleType.Fit
	end
	self.marlo = marlo
	-- The counter in front of Marlo: a second label of the SAME room picture, cropped to the counter band (back edge to the foot of the
	-- front, rows measured from shop_room_a), drawn at the room's own scale and place, above Marlo and below the controls, so the wood
	-- hides his lower body with the counter's real back edge. Made after the Marlo frame so it draws over him (equal ZIndex, later sibling).
	local counterFront
	if roomId then
		local R = Layout.ROOM
		counterFront = image(root, "CounterFront", roomId, 6)
		counterFront.ScaleType = Enum.ScaleType.Stretch
		local x, y, w, h = ImageSpace.rect(R.counterX[1] * R.w, R.counterBack * R.h, (R.counterX[2] - R.counterX[1]) * R.w, (R.counterFront - R.counterBack) * R.h, R.w, R.h)
		counterFront.ImageRectOffset = Vector2.new(x, y)
		counterFront.ImageRectSize = Vector2.new(w, h)
		counterFront.Visible = false
		self.counterFront = counterFront
	end
	-- the room picture and its counter band wear the same hint of the equipped Card Set's accent (GameRoot attribute RoomTint, set by
	-- Client/PlayScenePaint), so there is no seam between them; it follows a live skin change
	local gameRoot = deps.shopFrame
	while gameRoot and gameRoot.Name ~= "GameRoot" and gameRoot.Parent do gameRoot = gameRoot.Parent end
	-- A Card Set with its own shop room (Golden Gala) draws that picture on Room and CounterFront and hides the classic wooden strip
	-- (ShopScene CounterStrip) and the tavern layer (TavernScreens TavernScene); classic and every other set keep shop_room_a.
	local function applyRoomArt()
		local okS, id, own = pcall(function()
			local TS = require(Engine:WaitForChild("ThemeScenes"))
			local skin = require(script.Parent.HudTheme).skin()
			local previewId
			local okV, view = pcall(function() return require(script.Parent.CosmeticSetsView) end)
			if okV and view and view.previewSetId then previewId = view.previewSetId() end
			local sid = TS.effectiveSetId(skin and skin.id, previewId)
			return TS.shopRoomId(sid)
		end)
		if not okS or not id then return end
		if roomImg then roomImg.Image = id end
		if counterFront then counterFront.Image = id end
		self.setRoom = own == true
		for _, d in ipairs(shopFrame:GetDescendants()) do
			if d.Name == "CounterStrip" or d.Name == "TavernScene" then d.Visible = not self.setRoom end
		end
	end
	local applyTint
	local function applyRoomAndTint() applyRoomArt(); if applyTint then applyTint() end end
	applyRoomArt()
	pcall(function() require(script.Parent.HudTheme).onSkin(applyRoomAndTint) end)
	pcall(function() require(script.Parent.CosmeticSetsView).onPreview(applyRoomAndTint) end)
	shopFrame.DescendantAdded:Connect(function(d)
		if self.setRoom and (d.Name == "CounterStrip" or d.Name == "TavernScene") then d.Visible = false end
	end)
	shopFrame:GetPropertyChangedSignal("Visible"):Connect(applyRoomAndTint)
	function applyTint()
		local t = gameRoot and gameRoot:GetAttribute("RoomTint") or Color3.new(1, 1, 1)
		if self.setRoom then -- the palace picture keeps only part of the gold hint so the marble and curtains read
			local m = require(Engine:WaitForChild("ThemeScenes")).shopRoomTint(true, { t.R * 255, t.G * 255, t.B * 255 })
			t = Color3.fromRGB(m[1], m[2], m[3])
		end
		if roomImg then roomImg.ImageColor3 = t end
		if counterFront then counterFront.ImageColor3 = t end
	end
	applyTint()
	if gameRoot then gameRoot:GetAttributeChangedSignal("RoomTint"):Connect(applyTint) end
	self.marloId = marloId
	self.marloWaveId = ContentArt.getImageId("shop_scene", "shop_marlo_wave")
	local poolId = ContentArt.getImageId("shop_scene", "shop_light_pool")
	if poolId then
		light.BackgroundTransparency = 1
		local pool = image(root, "LightPoolArt", poolId, 6)
		pool.ScaleType = Enum.ScaleType.Stretch
		pool.ImageTransparency = 0.35
		self.pool = pool
	end

	local counter = topId and image(root, "CounterTop", topId, 6) or nil
	if counter then
		crop(counter, Layout.COUNTER_CROP)
		older[#older + 1] = counter
	end
	local props = {}
	if propsId then
		for name in pairs(Layout.PROP_CROP) do
			local img = image(root, "Prop_" .. name, propsId, 6)
			crop(img, Layout.PROP_CROP[name])
			props[name] = img
		end
	end

	-- The round card table every offer and pack lies on (Engine/ShopSceneLayout `table` and `felt`): a wide oval seen from above, drawn
	-- from capsules (a UICorner at 0.5 scale, the way the Menu room's felt table is made): a soft shadow on the counter, a wood rim in
	-- the Menu table's brown with a lighter edge along its top, and the felt inside it in a calm green that is lighter in the middle than
	-- at the edge, a little darker towards the two ends, with a faint pool of lantern light and a darker line where felt meets rim
	-- (colour stops only, never gradient transparency). Painted art (shop_table, from the held art task) replaces the rim and the felt
	-- when it is recorded; the shadow stays. Created after the counter pieces, so the brass rail passes behind the table, and under the
	-- cards.
	-- a warm moss green (the first felt read as a cold teal once the set tint of the room lay over it)
	local FELT_CENTER, FELT_EDGE = Color3.fromRGB(58, 82, 46), Color3.fromRGB(34, 54, 30)
	local RIM_WOOD, RIM_LIGHT = Color3.fromRGB(120, 78, 44), Color3.fromRGB(176, 124, 76)
	local function capsule(name, color, transparency)
		local f = Instance.new("Frame")
		f.Name = name
		f.BorderSizePixel = 0
		f.BackgroundColor3 = color
		f.BackgroundTransparency = transparency or 0
		f.Active = false
		f.ZIndex = 6
		f.Visible = false
		f.Parent = root
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0.5, 0)
		c.Parent = f
		return f
	end
	local function ramp(a, b, c) -- three colour stops, never a transparency
		return ColorSequence.new({ ColorSequenceKeypoint.new(0, a), ColorSequenceKeypoint.new(0.5, b), ColorSequenceKeypoint.new(1, c) })
	end
	local tableId = ContentArt.getImageId("shop_scene", "shop_table")
	local tablePieces = {} -- every frame of the table, for showing, hiding and placing
	-- The drawn table gets a soft oval shadow. The painted table (shop_table) does not: its picture is taller than the oval (the pedestal
	-- hangs below it), so an oval the size of the whole rect showed as a big smoky disc over the shelves; the painting has its own depth.
	if not tableId then
		tablePieces.shadowFar = capsule("TableShadowFar", Color3.fromRGB(6, 4, 2), 0.82)
		tablePieces.shadow = capsule("TableShadow", Color3.fromRGB(6, 4, 2), 0.6)
	end
	local tableTop
	if tableId then
		tableTop = image(root, "TableTop", tableId, 6)
		tableTop.ScaleType = Enum.ScaleType.Stretch
		tableTop.Visible = false
	else
		tablePieces.edge = capsule("TableRimLight", RIM_LIGHT, 0) -- peeks out 2 px above the rim: the light catching its top edge
		tableTop = capsule("TableTop", RIM_WOOD, 0)
		tablePieces.felt = capsule("TableFelt", Color3.new(1, 1, 1), 0)
		local vertical = Instance.new("UIGradient")
		vertical.Rotation = 90
		vertical.Color = ramp(FELT_EDGE, FELT_CENTER, FELT_EDGE)
		vertical.Parent = tablePieces.felt
		local seam = Instance.new("UIStroke") -- the darker line where the felt meets the rim
		seam.Color = Color3.fromRGB(16, 28, 20)
		seam.Thickness = 2
		seam.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		seam.Parent = tablePieces.felt
		tablePieces.shade = capsule("TableFeltShade", Color3.new(1, 1, 1), 0.72) -- darkens the two ends a little
		local horizontal = Instance.new("UIGradient")
		horizontal.Rotation = 0
		horizontal.Color = ramp(Color3.fromRGB(12, 22, 16), FELT_CENTER, Color3.fromRGB(12, 22, 16))
		horizontal.Parent = tablePieces.shade
		-- the lantern's light pool on the felt: many eased discs (Client/SoftGlow), so no edge shows, centred towards the lantern side
		local pool = SoftGlow.build(root, {
			name = "TableFeltLight", color = Color3.fromRGB(255, 196, 110), position = UDim2.fromOffset(0, 0), size = UDim2.fromOffset(10, 10),
			peak = 0.12, zIndex = 6,
		})
		pool.root.Visible = false
		tablePieces.glow = pool.root
	end
	self.tableTop = tableTop
	self.tablePieces = tablePieces
	older[#older + 1] = tableTop
	local managed = { [tableTop] = true } -- pieces whose Visible relayout sets itself
	for _, piece in pairs(tablePieces) do
		older[#older + 1] = piece
		managed[piece] = true
	end
	for _, img in pairs(props) do managed[img] = true end

	local counts = nil
	function self.relayout(newCounts)
		if type(newCounts) == "table" then counts = newCounts end
		local size = shopFrame.AbsoluteSize
		if size.X < 1 or size.Y < 1 then
			return
		end
		local r = Layout.rects(size.X, size.Y, counts)
		local t, f = r.table, r.felt
		if t then
			if tablePieces.shadowFar then place(tablePieces.shadowFar, { x = t.x - 8, y = t.y + 8, w = t.w + 16, h = t.h + 14 }) end
			if tablePieces.shadow then place(tablePieces.shadow, { x = t.x - 3, y = t.y + 4, w = t.w + 6, h = t.h + 8 }) end
			place(tableTop, t)
			if tablePieces.edge then place(tablePieces.edge, { x = t.x, y = t.y - 2, w = t.w, h = t.h }) end
			if tablePieces.felt then
				place(tablePieces.felt, f)
				place(tablePieces.shade, f)
				tablePieces.glow.Position = UDim2.fromOffset(f.x + f.w * 0.3, f.y + f.h * 0.4) -- centred (SoftGlow anchors at its middle)
				tablePieces.glow.Size = UDim2.fromOffset(f.w * 0.62, f.h * 0.7)
			end
		end
		-- no table on phones: their cards wrap in rows on the counter; in the painted room the table is part of the picture
		local room = r.room == true and roomImg ~= nil
		tableTop.Visible = t ~= nil and not room
		for _, piece in pairs(tablePieces) do piece.Visible = t ~= nil and not room end
		place(light, r.light)
		if self.pool then place(self.pool, r.light) end
		if marlo then place(marlo, r.marlo) end
		-- painted room: no clipping, Marlo is whole and the counter band covers him; the older scenes still clip him at the counter top
		marloClip.ClipsDescendants = not room
		marloClip.Size = room and UDim2.fromScale(1, 1) or UDim2.fromOffset(size.X, r.clipY or size.Y)
		if counterFront then
			counterFront.Visible = room and r.counterBand ~= nil
			if r.counterBand then place(counterFront, r.counterBand) end
		end
		if counter then
			place(counter, r.counter)
		end
		if fallbackCounter then
			place(fallbackCounter, r.counter)
		end
		for name, img in pairs(props) do
			if r.props[name] then
				place(img, r.props[name])
				img.Visible = true
			else
				img.Visible = false
			end
		end
		if roomImg then roomImg.Visible = room end
		if room then
			for _, piece in ipairs(older) do piece.Visible = false end
		else
			-- the older wall, counter and light come back (the table and props were set above)
			for _, piece in ipairs(older) do
				if not managed[piece] then piece.Visible = true end
			end
		end
	end
	shopFrame:GetPropertyChangedSignal("AbsoluteSize"):Connect(function() self.relayout() end)
	self.relayout()
	return self
end

return ShopBackdrop
