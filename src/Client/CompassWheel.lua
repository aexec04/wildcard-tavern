--[[
	Client/CompassWheel.lua
	A clickable, turnable compass (claude/MAP_DESIGN.md section 5). The needle points along `bearing`
	(0 = up, 90 = right, degrees, the same convention as WorldMap.bearing). Drag anywhere on the wheel, or tap
	a rim icon, to turn it; the needle follows smoothly (exponential easing every frame, no stepped tweens)
	and the frame loop only runs while it is still moving. Reduce shake snaps instead of easing.

	CompassWheel.new({ parent, size, bearing, icons = { { bearing, text, id } }, onTurn = function(bearing, id) })
	  -> { frame, setBearing(deg, instant), setIcons(list), setCharges(n), destroy() }
	`id` of the tapped icon is passed to onTurn so a caller can tell which rim icon was chosen.
	Text is 15px or larger.
]]

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local ClientSettings = require(script.Parent.ClientSettings)
local CompassLayout = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("CompassLayout"))

local INK = Color3.fromRGB(60, 40, 22)
local GOLD = Color3.fromRGB(222, 182, 104)
local PARCHMENT = Color3.fromRGB(222, 198, 150)

local CompassWheel = {}

local function wrap360(a)
	return a % 360
end

-- Signed shortest turn from a to b, in (-180, 180].
local function shortest(a, b)
	local d = (b - a) % 360
	if d > 180 then d = d - 360 end
	return d
end
CompassWheel.shortest = shortest

function CompassWheel.new(opts)
	local size = opts.size or 130
	local self = {}
	local current = wrap360(opts.bearing or 0)
	local target = current
	local dragging = false
	local connection, inputConn, endConn
	local iconButtons = {}

	local frame = Instance.new("Frame")
	frame.Name = "CompassWheel"
	frame.Size = UDim2.fromOffset(size, size)
	frame.BackgroundColor3 = PARCHMENT
	frame.BorderSizePixel = 0
	frame.Active = true
	frame.Parent = opts.parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = frame
	local ring = Instance.new("UIStroke")
	ring.Color = Color3.fromRGB(110, 80, 45)
	ring.Thickness = 3
	ring.Parent = frame

	-- Inner gold ring so the wheel reads as a brass dial.
	local inner = Instance.new("Frame")
	inner.AnchorPoint = Vector2.new(0.5, 0.5)
	inner.Position = UDim2.fromScale(0.5, 0.5)
	inner.Size = UDim2.fromScale(0.62, 0.62)
	inner.BackgroundTransparency = 1
	inner.Parent = frame
	local innerCorner = Instance.new("UICorner")
	innerCorner.CornerRadius = UDim.new(0.5, 0)
	innerCorner.Parent = inner
	local innerStroke = Instance.new("UIStroke")
	innerStroke.Color = GOLD
	innerStroke.Thickness = 2
	innerStroke.Parent = inner

	-- The needle: a full-size holder that rotates; the pointer sits in its top half.
	local holder = Instance.new("Frame")
	holder.Name = "Needle"
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, 0.5)
	holder.Size = UDim2.fromScale(1, 1)
	holder.BackgroundTransparency = 1
	holder.Parent = frame
	local tip = Instance.new("Frame")
	tip.AnchorPoint = Vector2.new(0.5, 0)
	tip.Position = UDim2.fromScale(0.5, 0.2)
	tip.Size = UDim2.new(0, math.max(6, size * 0.06), 0.3, 0)
	tip.BackgroundColor3 = Color3.fromRGB(190, 60, 44)
	tip.BorderSizePixel = 0
	tip.Parent = holder
	local tail = Instance.new("Frame")
	tail.AnchorPoint = Vector2.new(0.5, 0)
	tail.Position = UDim2.fromScale(0.5, 0.5)
	tail.Size = UDim2.new(0, math.max(6, size * 0.06), 0.22, 0)
	tail.BackgroundColor3 = INK
	tail.BorderSizePixel = 0
	tail.Parent = holder
	local hub = Instance.new("Frame")
	hub.AnchorPoint = Vector2.new(0.5, 0.5)
	hub.Position = UDim2.fromScale(0.5, 0.5)
	hub.Size = UDim2.fromOffset(size * 0.14, size * 0.14)
	hub.BackgroundColor3 = GOLD
	hub.BorderSizePixel = 0
	hub.Parent = frame
	local hubCorner = Instance.new("UICorner")
	hubCorner.CornerRadius = UDim.new(0.5, 0)
	hubCorner.Parent = hub

	-- N, E, S, W on the outer rim in their own fixed places; the road markers ride an inner ring (Engine/CompassLayout), so a
	-- marker never covers a letter
	local radii = CompassLayout.radii(size)
	local letters = {}
	for _, def in ipairs(CompassLayout.LETTERS) do
		local a = math.rad(def.bearing)
		local letter = Instance.new("TextLabel")
		letter.Name = "Letter" .. def.text
		letter.BackgroundTransparency = 1
		letter.AnchorPoint = Vector2.new(0.5, 0.5)
		letter.Position = UDim2.new(0.5, math.floor(math.sin(a) * radii.rim + 0.5), 0.5, -math.floor(math.cos(a) * radii.rim + 0.5))
		letter.Size = UDim2.fromOffset(CompassLayout.LETTER_BOX, CompassLayout.LETTER_BOX)
		letter.Text = def.text
		letter.Font = Enum.Font.GothamBold
		letter.TextSize = 15
		letter.TextColor3 = INK
		letter.TextTransparency = 0
		letter.TextStrokeTransparency = 1
		letter.Parent = frame
		table.insert(letters, letter)
	end

	local function apply()
		holder.Rotation = current
	end

	local function stop()
		if connection then
			connection:Disconnect()
			connection = nil
		end
	end

	local function run()
		if connection then return end
		connection = RunService.RenderStepped:Connect(function(dt)
			local d = shortest(current, target)
			if math.abs(d) < 0.15 then
				current = target
				apply()
				stop()
				return
			end
			current = wrap360(current + d * (1 - math.exp(-12 * math.min(dt, 0.1))))
			apply()
		end)
	end

	function self.setBearing(deg, instant)
		target = wrap360(deg)
		if instant or ClientSettings.get("reduceShake") == true then
			current = target
			apply()
			stop()
		else
			run()
		end
	end

	local function fire(id)
		if opts.onTurn then
			opts.onTurn(target, id)
		end
	end

	local function angleAt(pos)
		local center = frame.AbsolutePosition + frame.AbsoluteSize / 2
		local dx, dy = pos.X - center.X, pos.Y - center.Y
		if dx == 0 and dy == 0 then return nil end
		return math.deg(math.atan2(dx, -dy)) % 360
	end

	frame.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			local a = angleAt(Vector2.new(input.Position.X, input.Position.Y))
			if a then
				self.setBearing(a)
				fire(nil)
			end
		end
	end)
	inputConn = UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			local a = angleAt(Vector2.new(input.Position.X, input.Position.Y))
			if a then
				self.setBearing(a)
				fire(nil)
				if os.clock() - (self._lastTurnCue or 0) > 0.18 then -- tick while dragging
					self._lastTurnCue = os.clock()
					require(script.Parent.Cue).play("compass_turn")
				end
			end
		end
	end)
	endConn = UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)

	-- Rim icons (biome emoji at the bearing of each road). Tapping one turns the needle to it.
	function self.setIcons(list)
		for _, b in ipairs(iconButtons) do
			b:Destroy()
		end
		iconButtons = {}
		local radius = radii.marker
		local bearings = {}
		for i, icon in ipairs(list or {}) do bearings[i] = icon.bearing or 0 end
		local shown = CompassLayout.spread(bearings, size) -- fanned apart so two markers never overlap
		for i, icon in ipairs(list or {}) do
			local a = math.rad(shown[i] or 0)
			local b = Instance.new("TextButton")
			b.AnchorPoint = Vector2.new(0.5, 0.5)
			b.Position = UDim2.new(0.5, math.sin(a) * radius, 0.5, -math.cos(a) * radius)
			b.Size = UDim2.fromOffset(CompassLayout.MARKER, CompassLayout.MARKER)
			b.BackgroundColor3 = GOLD
			b.Text = icon.text or "?"
			b.TextSize = 18
			b.Font = Enum.Font.GothamBold
			b.TextColor3 = INK
			b.AutoButtonColor = true
			b.ZIndex = frame.ZIndex + 3 -- absolute under Global: a bare 3 drew under the whole panel
			b.Parent = frame
			local c = Instance.new("UICorner")
			c.CornerRadius = UDim.new(0.5, 0)
			c.Parent = b
			b.MouseButton1Click:Connect(function()
				self.setBearing(icon.bearing or 0)
				fire(icon.id)
			end)
			table.insert(iconButtons, b)
		end
	end

	-- Small charge pips under the wheel (up to 3).
	local pips = Instance.new("TextLabel")
	pips.BackgroundTransparency = 1
	pips.AnchorPoint = Vector2.new(0.5, 0)
	pips.Position = UDim2.new(0.5, 0, 1, 4)
	pips.Size = UDim2.fromOffset(size, 20)
	pips.Font = Enum.Font.GothamBold
	pips.TextSize = 16
	pips.TextColor3 = GOLD
	pips.TextTransparency = 0
	pips.TextStrokeTransparency = 0.8
	pips.TextStrokeColor3 = Color3.fromRGB(30, 18, 8)
	pips.Text = ""
	pips.Parent = frame

	-- The ScreenGui draws with ZIndexBehavior.Global, so a ZIndex is absolute: children left at 1 drew under the whole panel and
	-- the wheel showed a bare disc with no needle, hub, N or rim icons. Every piece follows the frame's own ZIndex; callers set
	-- frame.ZIndex after new() (RoadChoice 22, JourneyMapCompass 46) and the property signal re-bases the pieces.
	local function syncZ()
		local z = frame.ZIndex
		inner.ZIndex, holder.ZIndex, pips.ZIndex = z + 1, z + 1, z + 1
		tip.ZIndex, tail.ZIndex = z + 2, z + 2
		for _, letter in ipairs(letters) do letter.ZIndex = z + 2 end
		hub.ZIndex = z + 3
		for _, b in ipairs(iconButtons) do
			b.ZIndex = z + 3
		end
	end
	syncZ()
	frame:GetPropertyChangedSignal("ZIndex"):Connect(syncZ)

	function self.setCharges(n)
		n = math.floor(n or 0)
		pips.Text = n > 0 and (string.rep("#", n) .. string.rep("-", math.max(0, 3 - n))) or "-"
	end

	function self.destroy()
		stop()
		if inputConn then inputConn:Disconnect() end
		if endConn then endConn:Disconnect() end
		frame:Destroy()
	end

	self.frame = frame
	self.getBearing = function() return target end
	apply()
	self.setIcons(opts.icons)
	self.setCharges(0)
	return self
end

return CompassWheel
