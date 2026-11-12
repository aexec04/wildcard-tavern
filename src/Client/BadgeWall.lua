--[[
	Client/BadgeWall.lua
	Draws the Badges trophy wall into a board Frame (used by Client/BadgesPanel.lua). Each shelf tab changes the whole
	furniture: All = glass cabinet with shelves, Roads = map board with pins and string, Masters = velvet board with brass
	pins and a larger Master Tavern badge, Night = a night sky with a constellation, Special = a curio shelf with hooks.
	Positions come from Engine/BadgeWallLayout.lua (tested). Locked badges are dark silhouettes with a lock and a brass
	nameplate showing the requirement; earned ones shine (a sheen sweep and a warm spotlight), show their name on the
	plate, and sparkle once when first seen after unlocking. The next badge to go for pulses with a "Next up" ribbon.
	Every piece has a code-drawn fallback; Engine/BadgeWallArt.lua (empty until recorded) lays painted art over them.
	"Reduce screen shake" turns off the sweep, pulse, draw-in, hover raise and sparkle.

	  BadgeWall.render(board, chip, have, opts)
	      opts = { equippedId, secondId, vip, onPick = function(def), tooltip = function(inst, text) }
	  BadgeWall.step()   advance the sheen and pulse (called from one Heartbeat in BadgesPanel while open)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local BadgeWall = {}

local Engine = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine")
local Badges = require(Engine:WaitForChild("Badges"))
local Wall = require(Engine:WaitForChild("BadgeWallLayout"))
local WallArt = require(Engine:WaitForChild("BadgeWallArt"))
local ContentArt = require(Engine:WaitForChild("ContentArt"))
local SocketArt = require(Engine:WaitForChild("BadgeSocketArt")) -- empty until Image ids are recorded; drawn sockets show meanwhile
local PatronPlaque = require(script.Parent.PatronPlaque)
local ClientSettings = require(script.Parent.ClientSettings)

local CREAM = Color3.fromRGB(250, 240, 220)
local INK = Color3.fromRGB(52, 34, 20)
local BRASS = Color3.fromRGB(196, 156, 74)
local GOLD = Color3.fromRGB(236, 196, 100)
local Z = 42

local sweeps = {} -- { strip, phase } for earned badges
local pulses = {} -- { ring = UIStroke, phase }
local seenIds = nil -- earned ids already looked at (nil until the first view)

local function calm() return ClientSettings.get("reduceShake") == true end

local function frame(parent, props, radius)
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	f.ZIndex = Z
	f.Active = false
	for k, v in pairs(props) do f[k] = v end
	f.Parent = parent
	if radius then
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, radius)
		c.Parent = f
	end
	return f
end

local function words(parent, props)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBold
	l.TextColor3 = INK
	l.TextTransparency = 0
	l.TextStrokeTransparency = 1
	l.TextSize = 14
	l.ZIndex = Z + 4
	for k, v in pairs(props) do l[k] = v end
	l.Parent = parent
	return l
end

local function stroke(inst, color, thickness)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.Parent = inst
	return s
end

local function artOver(parent, key, props)
	local id = WallArt[key]
	if type(id) ~= "string" or id == "" then return nil end
	local img = Instance.new("ImageLabel")
	img.BackgroundTransparency = 1
	img.Image = id
	img.Active = false
	img.ZIndex = Z + 1
	img.Size = UDim2.fromScale(1, 1)
	for k, v in pairs(props or {}) do img[k] = v end
	img.Parent = parent
	return img
end

-- ===== furniture (code-drawn fallbacks, art laid over when recorded) =====
local function furniture(board, kind, w, h, shelves, items)
	local back = frame(board, { Name = "Furniture", Size = UDim2.fromScale(1, 1), ZIndex = Z - 1 }, 12)
	local g = Instance.new("UIGradient") -- Color stops only
	if kind == "cabinet" then
		back.BackgroundColor3 = Color3.fromRGB(64, 30, 44) -- deep velvet back panel
		g.Color = ColorSequence.new(Color3.fromRGB(88, 44, 60), Color3.fromRGB(44, 20, 30))
		stroke(back, Color3.fromRGB(104, 70, 40), 8) -- dark oak frame
		-- no planks or glare: badges sit on a strict grid over a calm plate, so nothing can sit crooked against a rail
	elseif kind == "map_board" then
		back.BackgroundColor3 = Color3.fromRGB(214, 188, 140) -- parchment
		g.Color = ColorSequence.new(Color3.fromRGB(226, 202, 156), Color3.fromRGB(192, 164, 112))
		stroke(back, Color3.fromRGB(150, 104, 62), 10) -- cork frame
	elseif kind == "velvet_board" then
		back.BackgroundColor3 = Color3.fromRGB(28, 36, 76) -- navy velvet
		g.Color = ColorSequence.new(Color3.fromRGB(40, 50, 96), Color3.fromRGB(20, 26, 58))
		stroke(back, GOLD, 5) -- gold edging
	elseif kind == "night_sky" then
		back.BackgroundColor3 = Color3.fromRGB(14, 22, 58)
		g.Color = ColorSequence.new(Color3.fromRGB(10, 14, 40), Color3.fromRGB(30, 50, 100))
		stroke(back, Color3.fromRGB(30, 40, 80), 6)
		for i = 1, 40 do -- soft stars, fixed positions
			local sx = (i * 37 % 100) / 100
			local sy = (i * 61 % 100) / 100
			frame(back, { Position = UDim2.fromScale(sx, sy), Size = UDim2.fromOffset(2 + i % 3, 2 + i % 3), BackgroundColor3 = Color3.fromRGB(230, 236, 255), BackgroundTransparency = 0.3 + (i % 4) * 0.12 }, 2)
		end
		local moon = frame(back, { Position = UDim2.new(0.9, -30, 0.08, 0), Size = UDim2.fromOffset(46, 46), BackgroundColor3 = Color3.fromRGB(250, 238, 200) }, 23)
		frame(moon, { Position = UDim2.fromOffset(14, -4), Size = UDim2.fromOffset(42, 42), BackgroundColor3 = Color3.fromRGB(16, 24, 62), ZIndex = Z + 1 }, 21)
	else -- curio_shelf
		back.BackgroundColor3 = Color3.fromRGB(56, 38, 26)
		g.Color = ColorSequence.new(Color3.fromRGB(72, 50, 34), Color3.fromRGB(40, 28, 20))
		stroke(back, Color3.fromRGB(96, 64, 38), 8)
	end
	g.Parent = back
	local art = artOver(back, Wall.FURNITURE_ART[kind], { ZIndex = Z - 1, ImageTransparency = 0.05, ScaleType = Enum.ScaleType.Crop }) -- the painted backdrop, fully visible on every tab
	local scrim = frame(back, { Name = "GridScrim", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(26, 19, 14), BackgroundTransparency = kind == "cabinet" and 0.25 or (art and 0.82 or 0.3), ZIndex = Z - 1 }, 12) -- the red velvet cabinet is toned right down
	scrim.Active = false
	-- a plank under each shelf row: the sockets rest on it
	for _, y in ipairs(shelves) do -- planks are always drawn from the rows (never the painted ones), each with a contact shadow
		frame(back, { Name = "PlankShadow", Position = UDim2.fromOffset(math.floor(w * 0.03) + 2, y + Wall.PLANK_H), Size = UDim2.fromOffset(math.floor(w * 0.94) - 4, 6), BackgroundColor3 = Color3.fromRGB(8, 5, 3), BackgroundTransparency = 0.55, ZIndex = Z }, 3)
		local plank = frame(back, { Name = "Plank", Position = UDim2.fromOffset(math.floor(w * 0.03), y), Size = UDim2.fromOffset(math.floor(w * 0.94), Wall.PLANK_H), BackgroundColor3 = Color3.fromRGB(104, 70, 40), ZIndex = Z }, 3)
		stroke(plank, Color3.fromRGB(60, 40, 24), 1)
		frame(plank, { Size = UDim2.new(1, 0, 0, 2), BackgroundColor3 = Color3.fromRGB(150, 108, 64), ZIndex = Z + 1 })
	end
	return back
end

-- A painted scene (Masters, Night, Special): the picture is cover-fitted over the board, its sockets are in the art, no planks or scrim.
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

-- A round socket behind a badge, concentric with it: contact shadow, dark plate with an inner shadow ring and a rim.
-- Painted socket art (Engine/BadgeSocketArt.lua) is laid over when an Image id is recorded; the drawn one shows otherwise.
local ART_SCALE = { badge_socket_star = 1.9 } -- the painted star ring has a hollow centre much smaller than its frame
local RIM = { road = Color3.fromRGB(150, 140, 120), shelf = Color3.fromRGB(150, 108, 64), niche = Color3.fromRGB(190, 150, 70), star = Color3.fromRGB(196, 156, 74) }
local function socketWidget(board, it, owned, flat)
	local r = Wall.socketRect(it)
	local d = r.w
	local holder = frame(board, { Name = "Socket_" .. tostring(it.id), Position = UDim2.fromOffset(r.x, r.y), Size = UDim2.fromOffset(d, d), BackgroundTransparency = 1, ZIndex = Z + 1 })
	if flat then -- the picture provides the socket (or the map the pin): only a soft contact shadow, no dark plate and no ring
		if not it.scene then
			frame(holder, { Name = "ContactShadow", Position = UDim2.fromOffset(-1, 3), Size = UDim2.fromOffset(d + 2, d), BackgroundColor3 = Color3.fromRGB(40, 24, 10), BackgroundTransparency = 0.78, ZIndex = Z + 1 }, d)
		end
		return holder
	end
	frame(holder, { Name = "ContactShadow", Position = UDim2.fromOffset(-2, 3), Size = UDim2.fromOffset(d + 4, d + 2), BackgroundColor3 = Color3.fromRGB(8, 5, 3), BackgroundTransparency = 0.55, ZIndex = Z + 1 }, d)
	local plate = frame(holder, { Name = "Plate", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(24, 17, 12), ZIndex = Z + 2 }, d)
	local rimColor = owned and GOLD or (RIM[it.socket] or BRASS)
	local rim = stroke(plate, rimColor, 3)
	rim.Transparency = owned and 0.15 or 0.55
	local inner = frame(plate, { Name = "InnerShadow", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.9, 0.9), BackgroundTransparency = 1, ZIndex = Z + 2 }, d)
	local shadow = stroke(inner, Color3.fromRGB(4, 3, 2), 4)
	shadow.Transparency = 0.45
	local key = Wall.SOCKET_ART[it.socket]
	local id = SocketArt[key]
	if key == "badge_socket_star" then id = nil end -- the painted star ring is far bigger than the medal; the drawn node is exactly 1.18x
	if type(id) == "string" and id ~= "" then
		local scale = ART_SCALE[key] or 1
		local img = Instance.new("ImageLabel")
		img.Name = "Art_" .. key
		img.BackgroundTransparency = 1
		img.Active = false
		img.Image = id
		img.AnchorPoint = Vector2.new(0.5, 0.5)
		img.Position = UDim2.fromScale(0.5, 0.5)
		img.Size = UDim2.fromScale(scale, scale)
		img.ScaleType = Enum.ScaleType.Fit
		img.ZIndex = Z + 2
		img.Parent = holder
	end
	return holder
end

-- The rim drawn over the badge edge, so the socket reads as holding the badge (not a picture on top of a picture).
local function rimOver(medalHolder, size, owned, kind)
	local ring = frame(medalHolder, { Name = "RimOverlap", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(size / 2, size / 2), Size = UDim2.fromOffset(size + 4, size + 4), BackgroundTransparency = 1, ZIndex = Z + 7 }, size)
	local s = stroke(ring, owned and GOLD or (RIM[kind] or BRASS), 2)
	s.Transparency = owned and 0.2 or 0.5
	return ring
end

local function line(parent, a, b, lit, calmMode)
	local s = Wall.segment(a.x, a.y, b.x, b.y)
	local bar = frame(parent, {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(s.x, s.y), Size = UDim2.fromOffset(s.length, lit and 3 or 2),
		Rotation = s.rotation, ZIndex = Z + 2,
		BackgroundColor3 = lit and Color3.fromRGB(255, 232, 150) or Color3.fromRGB(120, 130, 170), BackgroundTransparency = lit and 0 or 0.6,
	})
	if lit and not calmMode then
		bar.Size = UDim2.fromOffset(0, 3)
		TweenService:Create(bar, TweenInfo.new(0.5), { Size = UDim2.fromOffset(s.length, 3) }):Play()
	end
	return bar
end

-- The Roads path: a dotted trail (the painted badge_path_dash tile is not used until its Image id is recorded and checked).
local function pathDots(parent, points, lit)
	for _, p in ipairs(points) do
		frame(parent, {
			Name = "PathDot", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(p.x, p.y), Size = UDim2.fromOffset(lit and 7 or 5, lit and 7 or 5),
			ZIndex = Z + 1, BackgroundColor3 = lit and Color3.fromRGB(255, 226, 140) or Color3.fromRGB(150, 128, 92), BackgroundTransparency = lit and 0 or 0.35,
		}, 4)
	end
end

local function sparkle(parent, size)
	if calm() then return end
	for i = 1, 8 do
		local a = math.rad(i * 45)
		local p = frame(parent, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(8, 8), BackgroundColor3 = GOLD, ZIndex = Z + 9 }, 4)
		TweenService:Create(p, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = UDim2.new(0.5, math.cos(a) * size * 0.7, 0.5, math.sin(a) * size * 0.7), BackgroundTransparency = 1,
		}):Play()
		task.delay(0.75, function() p:Destroy() end)
	end
end

local function badgeWidget(board, def, it, owned, state, opts, isNext, fresh, flat)
	local size = it.size
	local holder = frame(board, { Name = "Badge_" .. def.id, Position = UDim2.fromOffset(it.x, it.y), Size = UDim2.fromOffset(size, Wall.plateY(it) + Wall.NAMEPLATE_H - 3), BackgroundTransparency = 1, ZIndex = Z + 3 })
	if owned then -- soft spotlight cone behind earned badges
		local spot = frame(holder, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(size / 2, size / 2), Size = UDim2.fromOffset(size * 1.3, size * 1.3), BackgroundColor3 = Color3.fromRGB(255, 226, 140), BackgroundTransparency = 0.9, ZIndex = Z + 2 }, size)
	end
	local medal = frame(holder, { Name = "Medal", Size = UDim2.fromOffset(size, size), BackgroundColor3 = owned and Color3.fromRGB(70, 52, 36) or Color3.fromRGB(58, 50, 44), ClipsDescendants = true, ZIndex = Z + 3 }, math.floor(size / 2))
	if not flat then stroke(medal, owned and GOLD or Color3.fromRGB(92, 80, 66), owned and 3 or 2) end -- on a scene the badge art itself is the object: no ring
	words(medal, { Size = UDim2.fromScale(1, 1), Text = def.icon, TextSize = math.max(14, math.floor(size * 0.5)), TextTransparency = owned and 0 or 0.45, TextColor3 = owned and CREAM or Color3.fromRGB(150, 140, 128), ZIndex = Z + 4 })
	local artId = ContentArt.getImageId("badges", def.id)
	if artId then
		local art = PatronPlaque.applyById(medal, artId, { zIndex = Z + 5, cornerRadius = math.floor(size / 2) })
		if art then
			if flat then medal.BackgroundTransparency = 1 end
			art.ScaleType = Enum.ScaleType.Crop
			art.ImageColor3 = owned and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(150, 146, 142) -- locked: the same icon, muted
		end
	end
	if not owned then
		local mute = frame(medal, { Name = "Mute", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(58, 52, 48), BackgroundTransparency = 0.5, ZIndex = Z + 6 }, math.floor(size / 2))
		mute.Active = false
		-- locked: a small padlock chip (on a scene it sits on the socket rim, outside the clipped medal)
		local lock = words(flat and holder or medal, { Name = "LockChip", AnchorPoint = Vector2.new(1, 1), Position = flat and UDim2.new(1, 3, 0, size + 3) or UDim2.new(1, -4, 1, -4), Size = UDim2.fromOffset(math.max(18, size * 0.28), math.max(18, size * 0.28)), Text = "\240\159\148\146", TextSize = math.max(14, math.floor(size * 0.2)), BackgroundTransparency = 0.25, BackgroundColor3 = Color3.fromRGB(26, 19, 13), ZIndex = Z + 8 })
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(1, 0)
		c.Parent = lock
	else
		local strip = frame(medal, { Position = UDim2.fromScale(2, -0.1), Size = UDim2.fromScale(0.16, 1.3), Rotation = 18, BackgroundColor3 = Color3.fromRGB(255, 244, 200), BackgroundTransparency = 0.7, ZIndex = Z + 7 })
		table.insert(sweeps, { strip = strip, phase = (#sweeps % 7) / 7 })
	end
	-- brass nameplate: earned shows the name, locked shows the requirement
	if not flat then rimOver(holder, size, owned, it.socket) end
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
	end
	if opts.tooltip then opts.tooltip(plate, def.name .. "\n" .. (owned and def.description or def.hint)) end
	if opts.equippedId == def.id or opts.secondId == def.id then
		local tag = frame(holder, { Position = UDim2.fromOffset(-2, 4), Size = UDim2.fromOffset(math.min(88, size), 20), BackgroundColor3 = GOLD, ZIndex = Z + 9 }, 3)
		words(tag, { Size = UDim2.fromScale(1, 1), Text = "Equipped", ZIndex = Z + 10 })
	end
	if isNext then
		expandPlate(true)
		local ring = stroke(medal, GOLD, flat and 2 or 3)
		table.insert(pulses, { ring = ring, phase = 0 })
		local ribbon = frame(holder, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0, 2 - (it.noSocket and 0 or Wall.pad(size))), Size = UDim2.fromOffset(math.max(flat and 56 or 64, size * (flat and 0.6 or 0.8)), 18), BackgroundColor3 = Color3.fromRGB(176, 44, 44), ZIndex = Z + 9 }, 3)
		words(ribbon, { Size = UDim2.fromScale(1, 1), Text = "Next up", TextColor3 = Color3.fromRGB(255, 236, 200), ZIndex = Z + 10 })
	end
	-- the whole medal is the click target; hover raises it a little (not on touch)
	local hit = Instance.new("TextButton")
	hit.Name = "Hit"
	hit.Size = UDim2.fromOffset(size, size)
	hit.BackgroundTransparency = 1
	hit.Text = ""
	hit.AutoButtonColor = false
	hit.ZIndex = Z + 12
	hit.Parent = holder
	hit.MouseButton1Click:Connect(function() if opts.onPick then opts.onPick(def, owned) end end)
	if not UserInputService.TouchEnabled then
		hit.MouseEnter:Connect(function()
			expandPlate(true)
			if calm() then return end
			TweenService:Create(holder, TweenInfo.new(0.12), { Position = UDim2.fromOffset(it.x, it.y - 4) }):Play()
		end)
		hit.MouseLeave:Connect(function()
			expandPlate(isNext == true)
			TweenService:Create(holder, TweenInfo.new(0.12), { Position = UDim2.fromOffset(it.x, it.y) }):Play()
		end)
	end
	if fresh then sparkle(medal, size) end
	return holder
end

-- Rebuild the wall for a tab. `have` = { [badgeId] = true }.
function BadgeWall.render(board, chip, have, opts)
	for _, c in ipairs(board:GetChildren()) do
		if c:IsA("GuiObject") then c:Destroy() end
	end
	sweeps, pulses = {}, {}
	local w, h = board.AbsoluteSize.X, board.AbsoluteSize.Y
	if w < 80 or h < 80 then w, h = math.max(w, 600), math.max(h, 340) end
	-- a painted scene (once its Image id is recorded) places every badge in a socket of the picture; otherwise the drawn layout stays
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

	local byId = {}
	for _, it in ipairs(lay.items) do byId[it.id] = it end
	for _, seg in ipairs(painted and {} or Wall.lines(chip, nil, have)) do
		local a, b = byId[seg.a], byId[seg.b]
		if a and b then
			local ax, ay, bx, by = a.x + a.size / 2, a.y + a.size / 2, b.x + b.size / 2, b.y + b.size / 2
			local ra, rb = Wall.socketRect(a).w / 2, Wall.socketRect(b).w / 2
			if chip == "Roads" then
				-- the road itself: a dotted trail from stop to stop across the map, lit once both ends are earned (the pins and
				-- strings below hold the medals)
				pathDots(board, Wall.dots(ax, ay, bx, by, ra, rb, 14), seg.lit)
			else -- Night: a thin constellation line that starts and ends on the star nodes
				local t = Wall.trim(ax, ay, bx, by, ra, rb)
				if t then line(board, { x = t.x1, y = t.y1 }, { x = t.x2, y = t.y2 }, seg.lit, calm()) end
			end
		end
	end
	if chip == "Roads" and not painted then -- on the painted map the pins and the dotted path are in the picture
		for _, it in ipairs(lay.items) do
			local p = Wall.pinFor(it)
			frame(board, { Name = "PinString", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(p.x, p.y), Size = UDim2.fromOffset(2, p.y2 - p.y), BackgroundColor3 = Color3.fromRGB(186, 156, 104), ZIndex = Z + 1 })
			frame(board, { Name = "PinShadow", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(p.x + 2, p.y + 3), Size = UDim2.fromOffset(Wall.PIN, Wall.PIN), BackgroundColor3 = Color3.fromRGB(8, 5, 3), BackgroundTransparency = 0.6, ZIndex = Z + 1 }, Wall.PIN)
			local pin = frame(board, { Name = "Pin", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(p.x, p.y), Size = UDim2.fromOffset(Wall.PIN, Wall.PIN), BackgroundColor3 = it and have[it.id] and GOLD or BRASS, ZIndex = Z + 2 }, Wall.PIN)
			stroke(pin, Color3.fromRGB(60, 40, 20), 1)
		end
	elseif chip == "Night" and not painted then
		for _, st in ipairs(Wall.tinyStars(lay.items)) do
			frame(board, { Name = "TinyStar", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(st.x, st.y), Size = UDim2.fromOffset(st.size, st.size), BackgroundColor3 = Color3.fromRGB(230, 236, 255), BackgroundTransparency = 0.25, ZIndex = Z + 1 }, st.size)
		end
	end
	for _, it in ipairs(lay.items) do socketWidget(board, it, have[it.id] == true, flat) end
	local nextId = Wall.nextUp(chip, nil, have)
	local freshSet = {}
	for _, id in ipairs(Wall.fresh(seenIds, have)) do freshSet[id] = true end
	for _, it in ipairs(lay.items) do
		local def = Badges.getById(it.id)
		if def then badgeWidget(board, def, it, have[def.id] == true, nil, opts, it.id == nextId, freshSet[def.id], flat) end
	end
	-- everything on screen now counts as seen (the first view only records, nothing sparkles)
	seenIds = seenIds or {}
	for id, flag in pairs(have) do if flag == true then seenIds[id] = true end end
end

-- One animation tick for the sheen sweep and the "Next up" pulse (call from a single Heartbeat while the wall is open).
function BadgeWall.step()
	if calm() then return end
	local t = os.clock()
	for _, s in ipairs(sweeps) do
		if s.strip.Parent then
			local k = ((t / 3.2) + s.phase) % 1.6 -- the last 0.6 of each cycle is a pause off to the right
			s.strip.Position = UDim2.fromScale(k < 1 and (-0.3 + k * 1.6) or 2, -0.1)
		end
	end
	for _, p in ipairs(pulses) do
		if p.ring.Parent then p.ring.Transparency = 0.15 + 0.4 * (0.5 + 0.5 * math.sin(t * 3)) end
	end
end

function BadgeWall.animated()
	return #sweeps > 0 or #pulses > 0
end

-- Earned badges the wall has not shown yet (the trophy room puts a New tag on their shelf; zooming in marks them seen).
function BadgeWall.freshIds(have)
	return Wall.fresh(seenIds, have)
end

return BadgeWall
