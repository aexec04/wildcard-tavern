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
local ClientSettings = require(script.Parent.ClientSettings)

local CollectionGallery = {}

local function art(key) return ContentArt.getImageId("collection_scene", key) end
local function calm() return ClientSettings.get("reduceShake") == true end
local function fast() return ClientSettings.get("animSpeed") == "fast" end

function CollectionGallery.framed(tabId)
	return tabId == "patrons" and art("collection_frame_owned") ~= nil and art("collection_frame_empty") ~= nil
end

function CollectionGallery.cellSize(tabId)
	if CollectionGallery.framed(tabId) then
		local c = Layout.FRAMED_CELL
		return UDim2.fromOffset(c.w, c.h)
	end
	return UDim2.fromOffset(92, 108)
end

function CollectionGallery.frameTile(tile, found, rarityColor, nameText, nameColor)
	local parts = Layout.framedParts()
	tile.BackgroundTransparency = 1
	local f = parts.frame
	local clip = Instance.new("Frame")
	clip.Name = "FrameCrop"
	clip.BackgroundTransparency = 1
	clip.BorderSizePixel = 0
	clip.Active = false
	clip.ClipsDescendants = true
	clip.Position = UDim2.fromOffset(f.x, f.y)
	clip.Size = UDim2.fromOffset(f.w, f.h)
	clip.ZIndex = 22
	clip.Parent = tile
	local o = Layout.FRAME_OPENING
	local back = Instance.new("Frame") -- dark canvas in the opening (the empty frame art is see-through there)
	back.BackgroundColor3 = found and Color3.fromRGB(44, 30, 20) or Color3.fromRGB(22, 17, 14)
	back.BorderSizePixel = 0
	back.Active = false
	back.Position = UDim2.fromScale(o.x, o.y)
	back.Size = UDim2.fromScale(o.w, o.h)
	back.ZIndex = 22
	back.Parent = clip
	local p = Layout.cropPlacement()
	local img = Instance.new("ImageLabel")
	img.Name = found and "FrameOwned" or "FrameEmpty"
	img.BackgroundTransparency = 1
	img.Active = false
	img.Image = art(found and "collection_frame_owned" or "collection_frame_empty")
	img.Size = UDim2.fromScale(p.sizeX, p.sizeY)
	img.Position = UDim2.fromScale(p.posX, p.posY)
	img.ZIndex = 22
	img.Parent = clip
	-- brass name plate on a solid plate (readable text), rim in the rarity colour but soft
	local pl = parts.plate
	local plate = Instance.new("Frame")
	plate.Name = "NamePlate"
	plate.BackgroundColor3 = Color3.fromRGB(52, 36, 20)
	plate.BorderSizePixel = 0
	plate.Position = UDim2.fromOffset(pl.x, pl.y)
	plate.Size = UDim2.fromOffset(pl.w, pl.h)
	plate.ZIndex = 23
	plate.Parent = tile
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 5)
	corner.Parent = plate
	local rim = Instance.new("UIStroke")
	rim.Color = found and rarityColor or Color3.fromRGB(96, 76, 52)
	rim.Thickness = 1.5
	rim.Transparency = found and 0.3 or 0.5
	rim.Parent = plate
	local name = Instance.new("TextLabel")
	name.BackgroundTransparency = 1
	name.Size = UDim2.fromScale(1, 1)
	name.Font = Enum.Font.GothamBold
	name.TextSize = 14
	name.TextColor3 = nameColor
	name.TextTransparency = 0
	name.TextStrokeTransparency = 1
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.Text = nameText
	name.ZIndex = 24
	name.Parent = plate
	return parts
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
		for k, spec in ipairs({ { 150, 0.93 }, { 100, 0.9 }, { 56, 0.86 } }) do
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
		moth.Size = UDim2.fromOffset(22, 22)
		moth.Visible = false
		moth.Active = false
		moth.ZIndex = wall.ZIndex
		moth.Parent = wall
	end
	local last = 0
	local t0 = os.clock()
	RunService.Heartbeat:Connect(function()
		if not backdrop.Visible then return end -- loops stop when hidden
		local now = os.clock()
		if now - last < 0.05 then return end
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
		if moth then
			if Layout.mothVisible(t, isCalm) then
				local lx, ly = Layout.lanternPx(size.X, size.Y, 1)
				local mx, my = Layout.mothPos(t, lx, ly, 46)
				moth.Position = UDim2.fromOffset(mx, my)
				moth.Rotation = math.deg(math.sin(t * 3)) * 0.2
				moth.Visible = true
			else
				moth.Visible = false
			end
		end
	end)
end

return CollectionGallery
