import pathlib
p=pathlib.Path('src/Client/BadgeWall.lua'); s=p.read_text()
def rep(a,b):
    global s
    assert a in s, a[:70]
    s=s.replace(a,b,1)

rep('''-- A round socket behind a badge, concentric with it''','''-- A painted scene (Masters, Night, Special): the picture is cover-fitted over the board, its sockets are in the art, no planks or scrim.
local function sceneBackdrop(board, sc)
	local back = frame(board, { Name = "Furniture", Size = UDim2.fromScale(1, 1), ZIndex = Z - 1, BackgroundColor3 = Color3.fromRGB(40, 28, 20) }, 12)
	local img = artOver(back, sc.art, { Name = "SceneArt", ZIndex = Z - 1, ScaleType = Enum.ScaleType.Crop })
	if img then
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, 12)
		c.Parent = img
	end
	return back
end

-- A round socket behind a badge, concentric with it''')

rep('''local function socketWidget(board, it, owned)
	local r = Wall.socketRect(it)
	local d = r.w
	local holder = frame(board, { Name = "Socket_" .. tostring(it.id), Position = UDim2.fromOffset(r.x, r.y), Size = UDim2.fromOffset(d, d), BackgroundTransparency = 1, ZIndex = Z + 1 })
''','''local function socketWidget(board, it, owned, flat)
	local r = Wall.socketRect(it)
	local d = r.w
	local holder = frame(board, { Name = "Socket_" .. tostring(it.id), Position = UDim2.fromOffset(r.x, r.y), Size = UDim2.fromOffset(d, d), BackgroundTransparency = 1, ZIndex = Z + 1 })
	if flat then -- the picture provides the socket (or the map the pin): only a soft contact shadow, no dark plate and no ring
		if not it.scene then
			frame(holder, { Name = "ContactShadow", Position = UDim2.fromOffset(-1, 3), Size = UDim2.fromOffset(d + 2, d), BackgroundColor3 = Color3.fromRGB(40, 24, 10), BackgroundTransparency = 0.78, ZIndex = Z + 1 }, d)
		end
		return holder
	end
''')

rep('local function badgeWidget(board, def, it, owned, state, opts, isNext, fresh)','local function badgeWidget(board, def, it, owned, state, opts, isNext, fresh, flat)')
rep('''	stroke(medal, owned and GOLD or Color3.fromRGB(92, 80, 66), owned and 3 or 2)''','''	if not flat then stroke(medal, owned and GOLD or Color3.fromRGB(92, 80, 66), owned and 3 or 2) end -- on a scene the badge art itself is the object: no ring''')
rep('''art.ScaleType = Enum.ScaleType.Crop''','''if flat then medal.BackgroundTransparency = 1 end
			art.ScaleType = Enum.ScaleType.Crop''')
rep('''local lock = words(medal, { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -4, 1, -4),''','''-- locked: a small padlock chip (on a scene it sits on the socket rim, outside the clipped medal)
		local lock = words(flat and holder or medal, { Name = "LockChip", AnchorPoint = Vector2.new(1, 1), Position = flat and UDim2.new(1, 3, 0, size + 3) or UDim2.new(1, -4, 1, -4),''')
rep('''	rimOver(holder, size, owned, it.socket)
	local pr = Wall.plateRect(it)
	local plate = frame(holder, { Name = "Nameplate", Position = UDim2.fromOffset(pr.x, Wall.plateY(it)), Size = UDim2.fromOffset(pr.w, pr.h), BackgroundColor3 = Color3.fromRGB(44, 32, 24), ZIndex = Z + 4 }, 4)
	stroke(plate, BRASS, 1)
	words(plate, { Size = UDim2.new(1, -6, 1, 0), Position = UDim2.fromOffset(3, 0), Text = Wall.plateText(def, owned), TextWrapped = true, TextSize = 15, TextTruncate = Enum.TextTruncate.None, ZIndex = Z + 6,
		TextColor3 = owned and CREAM or Color3.fromRGB(196, 182, 156) })''','''	if not flat then rimOver(holder, size, owned, it.socket) end
	local pr = Wall.plateRect(it)
	local nameText = Wall.plateText(def, owned)
	if flat and not it.scene and Wall.plateLines(nameText, pr.w, 14) == 1 then -- Roads: a one-line plate when the name fits its column
		pr = { x = pr.x, w = pr.w, h = Wall.SCENE_PLATE_H }
	end
	-- on a scene or the map the name sits on a small parchment plate, not a big dark box
	local plateColor = flat and (owned and Color3.fromRGB(226, 204, 158) or Color3.fromRGB(190, 172, 136)) or Color3.fromRGB(44, 32, 24)
	local plate = frame(holder, { Name = "Nameplate", Position = UDim2.fromOffset(pr.x, Wall.plateY(it)), Size = UDim2.fromOffset(pr.w, pr.h), BackgroundColor3 = plateColor, ZIndex = Z + 4 }, 4)
	stroke(plate, flat and Color3.fromRGB(122, 90, 48) or BRASS, 1)
	local plateLabel = words(plate, { Size = UDim2.new(1, -6, 1, 0), Position = UDim2.fromOffset(3, 0), Text = nameText, TextWrapped = true, TextSize = flat and 14 or 15, TextTruncate = Enum.TextTruncate.None, ZIndex = Z + 6,
		TextColor3 = flat and (owned and INK or Color3.fromRGB(86, 68, 48)) or (owned and CREAM or Color3.fromRGB(196, 182, 156)) })
	-- the hovered or next-up badge shows its whole name on one line; the others keep the small plate
	local function expandPlate(on)
		if not flat then return end
		local single = math.max(pr.w, #nameText * 8 + 14)
		local wide = on and single > pr.w
		plate.Size = UDim2.fromOffset(wide and single or pr.w, wide and Wall.SCENE_PLATE_H or pr.h)
		plate.Position = UDim2.fromOffset(wide and math.floor((size - single) / 2) or pr.x, Wall.plateY(it))
		plate.ZIndex = on and Z + 14 or Z + 4
		plateLabel.ZIndex = on and Z + 15 or Z + 6
	end''')
rep('''	if isNext then
		local ring = stroke(medal, GOLD, 3)
		table.insert(pulses, { ring = ring, phase = 0 })
		local ribbon = frame(holder, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0, 2 - Wall.pad(size)), Size = UDim2.fromOffset(math.max(64, size * 0.8), 18),''','''	if isNext then
		expandPlate(true)
		local ring = stroke(medal, GOLD, flat and 2 or 3)
		table.insert(pulses, { ring = ring, phase = 0 })
		local ribbon = frame(holder, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0, 2 - (it.noSocket and 0 or Wall.pad(size))), Size = UDim2.fromOffset(math.max(flat and 56 or 64, size * (flat and 0.6 or 0.8)), 18),''')
rep('''		hit.MouseEnter:Connect(function()
			if calm() then return end''','''		hit.MouseEnter:Connect(function()
			expandPlate(true)
			if calm() then return end''')
rep('''		hit.MouseLeave:Connect(function()
''','''		hit.MouseLeave:Connect(function()
			expandPlate(isNext == true)
''')
rep('''	local lay = Wall.layout(chip, nil, w, h)
	local kind = Wall.FURNITURE[chip] or "cabinet"
	furniture(board, kind, w, h, lay.shelves, lay.items)
''','''	-- a painted scene (once its Image id is recorded) places every badge in a socket of the picture; otherwise the drawn layout stays
	local sc = Wall.sceneOf(chip, WallArt)
	local lay = sc and Wall.sceneLayout(chip, nil, w, h)
	local painted = lay ~= nil
	if painted then
		sceneBackdrop(board, sc)
	else
		lay = Wall.layout(chip, nil, w, h)
		furniture(board, Wall.FURNITURE[chip] or "cabinet", w, h, lay.shelves, lay.items)
	end
	local flat = painted or chip == "Roads" -- no dark rings or boxes: the picture and the map hold the badges
''')
rep('for _, seg in ipairs(Wall.lines(chip, nil, have)) do','for _, seg in ipairs(painted and {} or Wall.lines(chip, nil, have)) do')
rep('	elseif chip == "Night" then\n		for _, st in','	elseif chip == "Night" and not painted then\n		for _, st in')
rep('socketWidget(board, it, have[it.id] == true) end','socketWidget(board, it, have[it.id] == true, flat) end')
rep('opts, it.id == nextId, freshSet[def.id]) end','opts, it.id == nextId, freshSet[def.id], flat) end')
p.write_text(s)
