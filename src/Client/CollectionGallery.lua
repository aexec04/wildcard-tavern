--[[
	Client/CollectionGallery.lua
	The Collection as the tavern's back-room Gallery (look only; filters, counts, milestones, tabs and tooltips are
	untouched). Pieces:
	  framed(tabId) / cellSize(tabId)         Patrons hang as framed portraits (collection_frame_owned / _empty), 92x132 cells
	  frameTile(tile, found, rarityColor, ...) gilt frame (chain cropped off), portrait well in its opening, brass name plate
	                                          with a softer rarity rim; returns the portrait well rect for the caller
	  newTag(tile) / dropIn(tile)             brass "New" tag and a 24 px drop-in with a soft bounce (skipped in calm mode and on Fast)
	  mountAlive(wall, panel, backdrop)       two lantern glows that flicker 3 percent and one moth that circles a lantern now and then
	Everything animated stops when the Collection is hidden, and calm mode ("Reduce screen shake") removes flicker, moth and drop-in.
	Every piece falls back to the old tiles when its art id is missing. Geometry and timing are in Engine/CollectionSceneLayout.lua.
]]

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Engine = game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine")
local ContentArt = require(Engine:WaitForChild("ContentArt"))
local Layout = require(Engine:WaitForChild("CollectionSceneLayout"))
local MothFlight = require(Engine:WaitForChild("MothFlight"))
local ClientSettings = require(script.Parent.ClientSettings)

local CollectionGallery = {}

local function art(key) return ContentArt.getImageId("collection_scene", key) end
local function calm() return ClientSettings.get("reduceShake") == true end
local function fast() return ClientSettings.get("animSpeed") == "fast" end

function CollectionGallery.framed(tabId)
	return tabId == "patrons" and art("collection_frame_owned") ~= nil and art("collection_frame_empty") ~= nil
end

-- "trophy" | "key" | "plate" for the shelf tabs whose painted furniture is recorded, else nil (the plain tiles stay)
function CollectionGallery.shelfKind(tabId)
	local kind = Layout.SHELF_TABS[tabId]
	return kind and CollectionGallery.furnitureKey(tabId) and kind or nil
end

function CollectionGallery.cellSize(tabId)
	local FX = require(script.Parent.CollectionFurniture)
	if FX.kind(tabId) then return FX.cellSize(FX.kind(tabId)) end
	local shelf = CollectionGallery.shelfKind(tabId)
	if shelf then
		local c = Layout.SHELF_CELL[shelf]
		return UDim2.fromOffset(c.w, c.h)
	end
	if CollectionGallery.framed(tabId) then
		local c = Layout.FRAMED_CELL
		return UDim2.fromOffset(c.w, c.h)
	end
	return UDim2.fromOffset(92, 108)
end

local BRASS, BRASS_RIM, ENGRAVE = Color3.fromRGB(190, 146, 64), Color3.fromRGB(112, 80, 30), Color3.fromRGB(52, 32, 10)

local function box(parent, props, radius)
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
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

-- A Patron hung on the wall: a soft shadow on the wall behind it, a brass nail with two short chains, the gilt frame (lit when
-- owned, under its grey dust cloth when locked) and a brass plate attached across the frame's bottom edge. Returns the cell parts.
function CollectionGallery.frameTile(tile, found, rarityColor, nameText)
	-- A locked Patron hangs in the same gilt frame, unlit: a dim silhouette in the opening and its name on a duller brass plate. (It used
	-- to hang under a grey dust cloth with "???" on the plate, which read as an empty hole.)
	local kind = "owned"
	local parts = Layout.framedParts(kind)
	tile.BackgroundTransparency = 1
	local f, sh = parts.frame, Layout.SHADOW
	box(tile, { Name = "WallShadow", BackgroundColor3 = Color3.fromRGB(0, 0, 0), BackgroundTransparency = sh.transparency,
		Position = UDim2.fromOffset(f.x + sh.dx, f.y + sh.dy), Size = UDim2.fromOffset(f.w, f.h), ZIndex = 21 }, 8)
	local chain = Layout.chain()
	for _, ln in ipairs(chain.lines) do
		box(tile, { Name = "Chain", BackgroundColor3 = Color3.fromRGB(122, 98, 62), AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(ln.cx, ln.cy), Size = UDim2.fromOffset(ln.len, 2), Rotation = ln.angle, ZIndex = 22 })
	end
	box(tile, { Name = "Nail", BackgroundColor3 = BRASS, AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(chain.nail.x, chain.nail.y), Size = UDim2.fromOffset(9, 9), ZIndex = 23 }, 4)
	local clip = box(tile, { Name = "FrameCrop", BackgroundTransparency = 1, ClipsDescendants = true,
		Position = UDim2.fromOffset(f.x, f.y), Size = UDim2.fromOffset(f.w, f.h), ZIndex = 22 })
	local o = Layout.FRAMES[kind].opening
	box(clip, { BackgroundColor3 = found and Color3.fromRGB(44, 30, 20) or Color3.fromRGB(30, 23, 18),
		Position = UDim2.fromScale(o.x, o.y), Size = UDim2.fromScale(o.w, o.h), ZIndex = 22 }) -- canvas in the opening
	local p = Layout.cropPlacement(kind)
	local img = Instance.new("ImageLabel")
	img.Name = found and "FrameOwned" or "FrameLocked"
	img.BackgroundTransparency = 1
	img.Active = false
	img.Image = art("collection_frame_owned")
	if not found then img.ImageColor3 = Color3.fromRGB(150, 140, 130) end -- unlit gilt (a colour multiply, never transparency)
	img.Size = UDim2.fromScale(p.sizeX, p.sizeY)
	img.Position = UDim2.fromScale(p.posX, p.posY)
	img.ZIndex = 22
	img.Parent = clip
	-- the brass plate is part of the frame: brass colour, dark engraved text, a soft rarity rim when owned
	local pl = parts.plate
	local plate = box(tile, { Name = "NamePlate", BackgroundColor3 = found and BRASS or Color3.fromRGB(96, 74, 40), Position = UDim2.fromOffset(pl.x, pl.y),
		Size = UDim2.fromOffset(pl.w, pl.h), ZIndex = 25 }, 4)
	local rim = Instance.new("UIStroke")
	rim.Color = found and rarityColor or BRASS_RIM
	rim.Thickness = 1.5
	rim.Transparency = found and 0.35 or 0.2
	rim.Parent = plate
	for _, side in ipairs({ 0, 1 }) do
		box(plate, { BackgroundColor3 = BRASS_RIM, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(side, side == 0 and 5 or -5, 0.5, 0),
			Size = UDim2.fromOffset(4, 4), ZIndex = 26 }, 2)
	end
	local name = Instance.new("TextLabel")
	name.BackgroundTransparency = 1
	name.Size = UDim2.new(1, -16, 1, 0)
	name.Position = UDim2.fromOffset(8, 0)
	name.Font = Enum.Font.GothamBold
	name.TextSize = 14
	name.TextColor3 = found and ENGRAVE or Color3.fromRGB(250, 240, 220) -- cream on the duller locked brass (5:1)
	name.TextTransparency = 0
	name.TextStrokeTransparency = 1
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.Text = nameText
	name.ZIndex = 27
	name.Parent = plate
	return parts
end

-- Hand-hung look, stable per Patron id: a tiny fixed tilt and a few px of vertical offset (applied to every piece of the tile,
-- the grid owns the tile's own position). Hover straightens the frame, lifts it 3 px and sways it once; calm mode does it instantly.
-- A tile is a direct child of the section's ScrollingFrame, and Roblox ignores Rotation there, so every piece of the tile moves into an inner
-- full-size Tilt wrapper and the wrapper carries the angle (it is also what hover straightens). Returns { dy, tilt, target = the wrapper }.
function CollectionGallery.hangTile(tile, id)
	local h = Layout.hang(id)
	local wrap = Instance.new("Frame")
	wrap.Name = "Tilt"
	wrap.Size = UDim2.fromScale(1, 1)
	wrap.BackgroundTransparency = 1
	wrap.BorderSizePixel = 0
	wrap.Active = false
	wrap.ZIndex = tile.ZIndex
	for _, c in ipairs(tile:GetChildren()) do
		if c:IsA("GuiObject") then
			c.Position = c.Position + UDim2.fromOffset(0, h.dy)
			c.Parent = wrap
		end
	end
	wrap.Parent = tile
	wrap.Rotation = h.tilt
	return { dy = h.dy, tilt = h.tilt, target = wrap }
end

function CollectionGallery.bindHover(tile, hang, target)
	target = target or hang.target or tile
	local pieces = {}
	for _, c in ipairs(target:GetChildren()) do
		if c:IsA("GuiObject") and not c:GetAttribute("Static") then pieces[#pieces + 1] = { c = c, home = c.Position } end
	end
	local function go(on)
		local lift = on and UDim2.fromOffset(0, -3) or UDim2.new()
		local rot = on and 0 or hang.tilt
		if calm() then
			target.Rotation = rot
			for _, p in ipairs(pieces) do p.c.Position = p.home + lift end
			return
		end
		TweenService:Create(target, TweenInfo.new(on and 0.5 or 0.15, on and Enum.EasingStyle.Elastic or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Rotation = rot }):Play()
		for _, p in ipairs(pieces) do
			TweenService:Create(p.c, TweenInfo.new(0.12), { Position = p.home + lift }):Play()
		end
	end
	tile.MouseEnter:Connect(function() go(true) end)
	tile.MouseLeave:Connect(function() go(false) end)
end

-- The panel title becomes a brass sign hung from the top edge on two short chains (created before the title label so the text
-- draws over it; follows the label's size and text). Returns { bind = function(titleLabel) }.
function CollectionGallery.hangSign(panel)
	local sign = box(panel, { Name = "TitleSign", BackgroundColor3 = BRASS, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(0, 4),
		Size = UDim2.fromOffset(160, 30), ZIndex = 21 }, 6)
	local rim = Instance.new("UIStroke")
	rim.Color = BRASS_RIM
	rim.Thickness = 2
	rim.Parent = sign
	for _, fx in ipairs({ 0.2, 0.8 }) do
		box(panel, { Name = "SignChain", BackgroundColor3 = Color3.fromRGB(122, 98, 62), AnchorPoint = Vector2.new(0.5, 0), Size = UDim2.fromOffset(2, 6),
			Position = UDim2.fromOffset(0, -2), ZIndex = 21 }).Visible = false -- placed by the sign below
	end
	local api = {}
	function api.bind(titleLabel)
		titleLabel.TextColor3 = ENGRAVE
		local function fit()
			local w = math.max(150, math.floor(titleLabel.TextBounds.X) + 48)
			sign.Size = UDim2.fromOffset(w, 30)
			local cx = titleLabel.AbsolutePosition.X - panel.AbsolutePosition.X + titleLabel.AbsoluteSize.X / 2
			sign.Position = UDim2.fromOffset(cx, 4)
			local i = 0
			for _, c in ipairs(panel:GetChildren()) do
				if c.Name == "SignChain" then
					i = i + 1
					c.Visible = true
					c.Position = UDim2.fromOffset(cx + (i == 1 and -1 or 1) * w * 0.3, -2)
				end
			end
		end
		titleLabel:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
		titleLabel:GetPropertyChangedSignal("AbsolutePosition"):Connect(fit)
		titleLabel:GetPropertyChangedSignal("TextBounds"):Connect(fit)
		task.defer(fit)
	end
	return api
end

-- ===== furniture per tab: a painted piece behind the scrolling grid (the grid lives in a layout-managed ScrollingFrame, so the
-- decoration is a sibling behind it that mirrors its rect) =====
local FURNITURE = { recipes = "collection_corkboard", bonds = "collection_corkboard", bosses = "collection_trophy_shelf",
	housePasses = "collection_key_rack", titles = "collection_nameplate_shelf" }

function CollectionGallery.furnitureKey(tabId)
	local key = FURNITURE[tabId]
	return key and art(key) and key or nil
end

-- creates the backdrop (call before the scroll is created so it draws under it; then api.follow(scroll)); returns { follow, setTab }
function CollectionGallery.mountFurniture(panel)
	local img = Instance.new("ImageLabel")
	img.Name = "TabFurniture"
	img.BackgroundTransparency = 1
	img.ScaleType = Enum.ScaleType.Stretch
	img.Active = false
	img.Visible = false
	img.ZIndex = 21
	img.Parent = panel
	local api = {}
	function api.follow(scroll)
		local function fit()
			local p, s, m = scroll.Position, scroll.Size, Layout.FURNITURE_MARGIN
			img.Position = UDim2.new(p.X.Scale, p.X.Offset - m, p.Y.Scale, p.Y.Offset - m)
			img.Size = UDim2.new(s.X.Scale, s.X.Offset + 2 * m, s.Y.Scale, s.Y.Offset + 2 * m)
		end
		scroll:GetPropertyChangedSignal("Position"):Connect(fit)
		scroll:GetPropertyChangedSignal("Size"):Connect(fit)
		fit()
	end
	function api.setTab(tabId)
		img.Visible = false -- furniture is drawn from the cells now (Client/CollectionFurniture.lua), never stretched behind the grid
	end
	return api
end

-- Recipe cards pinned on the cork board: owned cards hang straight-ish (tilt of at most 2 degrees fixed per card) on a pin; a locked
-- recipe is an empty pin dot with a ??? plate. `tile` is already built; this restyles it.
function CollectionGallery.pinCard(tile, found, id, nameLabel, lockedText)
	tile.BackgroundTransparency = found and 0 or 1
	if found then
		tile.BackgroundColor3 = Color3.fromRGB(236, 220, 182)
		if nameLabel then nameLabel.TextColor3 = ENGRAVE end
	end
	local pin = box(tile, { Name = "Pin", BackgroundColor3 = found and Color3.fromRGB(176, 52, 40) or Color3.fromRGB(64, 46, 30),
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, found and 2 or 8), Size = UDim2.fromOffset(found and 12 or 10, found and 12 or 10), ZIndex = 32 }, 6)
	local rim = Instance.new("UIStroke")
	rim.Color = Color3.fromRGB(40, 26, 14)
	rim.Thickness = 1
	rim.Parent = pin
	if not found then
		local plate = box(tile, { Name = "UnknownPlate", BackgroundColor3 = Color3.fromRGB(52, 36, 20), AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.55), Size = lockedText and UDim2.fromOffset(84, 40) or UDim2.fromOffset(52, 24), ZIndex = 28 }, 5)
		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1
		t.Size = UDim2.fromScale(1, 1)
		t.Font = Enum.Font.GothamBold
		t.TextSize = 14
		t.TextColor3 = Color3.fromRGB(250, 240, 220)
		t.TextTransparency = 0
		t.TextStrokeTransparency = 1
		t.Text = lockedText or "???"
		t.TextWrapped = true
		t.ZIndex = 29
		t.Parent = plate
	end
	local h = Layout.hang(id)
	tile.Rotation = math.max(-Layout.CARD_TILT, math.min(Layout.CARD_TILT, h.tilt))
	return { dy = 0, tilt = tile.Rotation }
end

-- A string between two pinned cards (Bonds board): a thin tan line from this card's pin to the next card's pin.
function CollectionGallery.pinString(tile, reach)
	return box(tile, { Name = "PinString", BackgroundColor3 = Color3.fromRGB(186, 156, 104), Position = UDim2.new(0.5, 0, 0, 7),
		Size = UDim2.fromOffset(reach, 2), ZIndex = 31 })
end

-- Boss Rounds (trophy stands), House Passes (keys and tickets on hooks) and Titles (engraved plates). The tile is already built:
-- this restyles it from Layout.shelfParts. Locked = an empty stand, an empty hook or a blank plate; names sit on solid brass plates
-- with a soft rarity rim. Returns the hover hang (no tilt).
function CollectionGallery.shelfTile(kind, tile, found, iconWell, nameLabel, rarityColor)
	local P = Layout.shelfParts(kind)
	tile.BackgroundTransparency = 1
	tile.AutoButtonColor = false
	local function rect(r) return UDim2.fromOffset(r.x, r.y), UDim2.fromOffset(r.w, r.h) end
	local function plateRim(plate)
		local rim = Instance.new("UIStroke")
		rim.Color = rarityColor or BRASS_RIM
		rim.Thickness = 1.5
		rim.Transparency = found and 0.35 or 0.7 -- a soft rim, never a loud glow
		rim.Parent = plate
	end
	if kind == "trophy" then
		local pos, size = rect(P.base)
		box(tile, { Name = "TrophyBase", BackgroundColor3 = BRASS, Position = pos, Size = size, ZIndex = 22 }, 5)
	elseif kind == "key" then
		local pos, size = rect(P.hook)
		box(tile, { Name = "Hook", BackgroundColor3 = BRASS, Position = pos, Size = size, ZIndex = 23 }, 6)
		if found then
			pos, size = rect(P.cord)
			box(tile, { Name = "Cord", BackgroundColor3 = Color3.fromRGB(122, 98, 62), Position = pos, Size = size, ZIndex = 22 })
			pos, size = rect(P.ticket)
			box(tile, { Name = "Ticket", BackgroundColor3 = Color3.fromRGB(214, 184, 112), Position = pos, Size = size, ZIndex = 22 }, 8)
		end
	end
	local plate
	do
		local pos, size = rect(P.plate)
		plate = box(tile, { Name = "BrassPlate", BackgroundColor3 = found and BRASS or Color3.fromRGB(96, 74, 44), Position = pos, Size = size, ZIndex = 24 }, 5)
		plateRim(plate)
	end
	if iconWell then
		if P.icon then
			local pos, size = rect(P.icon)
			iconWell.Position, iconWell.Size = pos, size
			iconWell.Visible = found
		else
			iconWell.Visible = false
		end
	end
	if nameLabel then
		nameLabel.Parent = tile
		nameLabel.AnchorPoint = Vector2.new(0, 0)
		local top = kind == "plate" and 18 or 0
		nameLabel.Position = UDim2.fromOffset(P.plate.x + 3, P.plate.y + top)
		nameLabel.Size = UDim2.fromOffset(P.plate.w - 6, P.plate.h - top)
		nameLabel.TextColor3 = found and ENGRAVE or Color3.fromRGB(250, 240, 220)
		nameLabel.TextYAlignment = Enum.TextYAlignment.Center
		nameLabel.TextWrapped = true
		nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
		nameLabel.ZIndex = 26
		if kind == "plate" and not found then nameLabel.Text = "" end -- locked plates are blank
	end
	return { dy = 0, tilt = 0 }
end

-- The milestone chest on the floor at the bottom right: closed with a small "Next at N%" plate; opens (with a few gold motes) when a
-- milestone has just been earned. Milestones are granted automatically, so there is nothing to click. api.setNext(text), api.open().
function CollectionGallery.mountChest(panel)
	local closedId, openId = art("collection_chest_closed"), art("collection_chest_open")
	if not (closedId and openId) then return nil end
	local chest = Instance.new("ImageLabel")
	chest.Name = "MilestoneChest"
	chest.BackgroundTransparency = 1
	chest.Image = closedId
	chest.ScaleType = Enum.ScaleType.Fit
	chest.Active = false
	chest.ZIndex = 30
	chest.Parent = panel
	local plate = box(panel, { Name = "ChestPlate", BackgroundColor3 = Color3.fromRGB(52, 36, 20), ZIndex = 30 }, 5)
	local rim = Instance.new("UIStroke")
	rim.Color = BRASS
	rim.Thickness = 1.5
	rim.Parent = plate
	local text = Instance.new("TextLabel")
	text.BackgroundTransparency = 1
	text.Size = UDim2.fromScale(1, 1)
	text.Font = Enum.Font.GothamBold
	text.TextSize = 14
	text.TextColor3 = Color3.fromRGB(250, 240, 220)
	text.TextTransparency = 0
	text.TextStrokeTransparency = 1
	text.Text = ""
	text.ZIndex = 31
	text.Parent = plate
	local function place()
		local s = panel.AbsoluteSize
		if s.X < 1 then return end
		local r = Layout.chest(s.X, s.Y)
		chest.Position, chest.Size = UDim2.fromOffset(r.x, r.y), UDim2.fromOffset(r.w, r.h)
		plate.Size = UDim2.fromOffset(130, 22)
		plate.Position = UDim2.fromOffset(r.x - 136, r.y + r.h - 24)
	end
	panel:GetPropertyChangedSignal("AbsoluteSize"):Connect(place)
	place()
	local shown, hasText = true, false
	local function sync()
		chest.Visible = shown
		plate.Visible = shown and hasText
	end
	local api = {}
	function api.setNext(str)
		text.Text = str
		hasText = str ~= ""
		sync()
	end
	function api.setShown(on) -- the gallery room hides the chest; the section shelves show it
		shown = on == true
		sync()
	end
	local token = 0
	function api.open()
		token = token + 1
		local mine = token
		chest.Image = openId
		if not calm() then
			TweenService:Create(chest, TweenInfo.new(0.12), { Rotation = 6 }):Play()
			task.delay(0.12, function() TweenService:Create(chest, TweenInfo.new(0.12), { Rotation = 0 }):Play() end)
			for i = 1, shown and 6 or 0 do -- gold motes rise from the open lid (none while the gallery room hides the chest)
				local m = box(panel, { BackgroundColor3 = Color3.fromRGB(255, 214, 110), Size = UDim2.fromOffset(5, 5), ZIndex = 31,
					Position = chest.Position + UDim2.fromOffset(chest.AbsoluteSize.X / 2 + (i - 3.5) * 6, 8) }, 3)
				TweenService:Create(m, TweenInfo.new(0.9), { Position = m.Position + UDim2.fromOffset((i - 3.5) * 8, -34), BackgroundTransparency = 1 }):Play()
				task.delay(1, function() m:Destroy() end)
			end
		end
		task.delay(6, function() if token == mine then chest.Image = closedId end end)
	end
	return api
end

-- a small brass "New" tag at the top left of a tile
function CollectionGallery.newTag(tile)
	local tag = Instance.new("TextLabel")
	tag.Name = "NewTag"
	tag.Size = UDim2.fromOffset(38, 18)
	tag.Position = UDim2.fromOffset(2, 2)
	tag.BackgroundColor3 = Color3.fromRGB(214, 170, 74)
	tag.BorderSizePixel = 0
	tag.Font = Enum.Font.GothamBold
	tag.TextSize = 14
	tag.TextColor3 = Color3.fromRGB(40, 26, 14)
	tag.TextTransparency = 0
	tag.TextStrokeTransparency = 1
	tag.Text = "New"
	tag.ZIndex = 32
	tag.Parent = tile
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 5)
	corner.Parent = tag
	return tag
end

-- every piece of the tile slides down 24 px on its chain with one soft bounce (the grid owns the tile itself)
local animated = 0
function CollectionGallery.dropIn(tile)
	if calm() or fast() or animated >= 6 then return end
	animated = animated + 1
	for _, c in ipairs(tile:GetChildren()) do
		if c:IsA("GuiObject") then
			local home = c.Position
			c.Position = home + UDim2.fromOffset(0, -Layout.DROP_PX)
			TweenService:Create(c, TweenInfo.new(Layout.DROP_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = home }):Play()
		end
	end
	task.delay(Layout.DROP_TIME + 0.1, function() animated = math.max(0, animated - 1) end)
end

-- Two lantern glows and one moth over the painted wall. One Heartbeat loop that does nothing while the Collection is hidden.
function CollectionGallery.mountAlive(wall, panel, backdrop)
	local glows = {}
	for i = 1, 2 do
		local rings = {}
		-- seven stacked discs at 3 to 4 percent each: a soft falloff with no visible edge
		for k, spec in ipairs({ { 150, 0.97 }, { 128, 0.965 }, { 106, 0.96 }, { 86, 0.96 }, { 68, 0.955 }, { 52, 0.955 }, { 38, 0.95 } }) do
			local g = Instance.new("Frame")
			g.Name = "LanternGlow" .. i .. "_" .. k
			g.AnchorPoint = Vector2.new(0.5, 0.5)
			g.Size = UDim2.fromOffset(spec[1], spec[1])
			g.BackgroundColor3 = Color3.fromRGB(255, 170, 60)
			g.BackgroundTransparency = spec[2]
			g.BorderSizePixel = 0
			g.Active = false
			g.ZIndex = wall.ZIndex
			g.Parent = wall
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0.5, 0)
			corner.Parent = g
			rings[k] = { frame = g, base = spec[2] }
		end
		glows[i] = rings
	end
	local mothId = art("collection_moth")
	local moth
	if mothId then
		moth = Instance.new("ImageLabel")
		moth.Name = "Moth"
		moth.Image = mothId
		moth.BackgroundTransparency = 1
		moth.AnchorPoint = Vector2.new(0.5, 0.5)
		moth.Size = UDim2.fromOffset(14, 14)
		moth.Visible = false
		moth.Active = false
		moth.ZIndex = wall.ZIndex
		moth.Parent = wall
	end
	local motes = {}
	for i = 1, Layout.MOTES do
		local m = Instance.new("Frame")
		m.Name = "Mote" .. i
		m.AnchorPoint = Vector2.new(0.5, 0.5)
		m.Size = UDim2.fromOffset(3, 3)
		m.BackgroundColor3 = Color3.fromRGB(255, 226, 160)
		m.BackgroundTransparency = 0.6
		m.BorderSizePixel = 0
		m.Active = false
		m.Visible = false
		m.ZIndex = wall.ZIndex
		m.Parent = wall
		motes[i] = m
	end
	local flight = MothFlight.new()
	local last = 0
	local t0 = os.clock()
	RunService.Heartbeat:Connect(function()
		if not backdrop.Visible then
			flight:step(0, { w = 1, h = 1, lx = 0, ly = 0, hidden = true }) -- loops stop when hidden; the moth starts over
			return
		end
		local now = os.clock()
		local dt = math.min(now - last, 0.25)
		if dt < 0.05 then return end
		last = now
		local size = panel.AbsoluteSize
		if size.X < 1 or size.Y < 1 then return end
		local t = now - t0
		local isCalm = calm()
		local f = Layout.flicker(t, isCalm)
		wall.ImageColor3 = Color3.fromRGB(0, 0, 0):Lerp(Color3.new(1, 1, 1), math.min(1, 0.97 * f))
		for i = 1, 2 do
			local x, y = Layout.lanternPx(size.X, size.Y, i)
			for _, ring in ipairs(glows[i]) do
				ring.frame.Visible = x >= 0 and x <= size.X -- a narrow panel crops a lantern off the wall
				ring.frame.Position = UDim2.fromOffset(x, y)
				ring.frame.BackgroundTransparency = math.clamp(ring.base - (f - 1) * 2, 0, 1)
			end
		end
		for i, m in ipairs(motes) do -- a few motes drift in the light of the lantern they belong to (none in calm mode)
			if isCalm then
				m.Visible = false
			else
				local lx, ly = Layout.lanternPx(size.X, size.Y, (i % 2) + 1)
				local ox, oy = Layout.moteOffset(i, t, 60)
				m.Position = UDim2.fromOffset(lx + ox, ly + oy)
				m.Visible = lx >= 0 and lx <= size.X
			end
		end
		if moth then
			local lx, ly = Layout.lanternPx(size.X, size.Y, 1)
			local m = flight:step(dt, { w = size.X, h = size.Y, lx = lx, ly = ly, calm = isCalm })
			if m.visible then
				moth.Position = UDim2.fromOffset(m.x, m.y)
				moth.Rotation = m.rot
				moth.Size = UDim2.fromOffset(math.floor(14 * m.flap + 0.5), 14) -- wings flap by scaling X between 1 and 0.55
				moth.ImageTransparency = 1 - 0.8 * m.alpha -- low contrast, never fully opaque
				moth.Visible = true
			else
				moth.Visible = false
			end
		end
	end)
end

return CollectionGallery
