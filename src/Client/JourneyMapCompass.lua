--[[
	Client/JourneyMapCompass.lua
	The compass on the Tavern Map itself: a brass icon (top left of the map, with a charge counter) that opens
	a wheel overlay at any time. Turning the wheel (drag, rim icon, or the two arrow buttons) swings the map to
	the pointed road and lights it up. With a charge and a pending fork, "Spend a charge: take this road"
	fires the existing UseCompass remote (the server spends the charge and reveals the rewards) and then
	ChooseRoad for the pointed road; the server still validates both. With no charge the wheel is a preview.

	deps = { parent (the map frame), roundCorner, ReplicatedStorage, Engine, getState, graph, scrollTo(x, y) }
	Returned: { refresh(state), setShown(bool) }
]]

local CompassWheel = require(script.Parent.CompassWheel)
local RoadLock = require(script.Parent.RoadLock)

return function(deps)
	local WorldMap = require(deps.Engine:WaitForChild("WorldMap"))
	local Layout = require(deps.Engine:WaitForChild("WorldMapLayout"))
	local MapPan = require(deps.Engine:WaitForChild("MapPan"))

	local INK = Color3.fromRGB(60, 40, 22)
	local GOLD = Color3.fromRGB(222, 182, 104)
	local CREAM = Color3.fromRGB(250, 235, 200)
	local PARCHMENT = Color3.fromRGB(222, 198, 150)

	-- Keys counter next to the compass: Keys open locked roads (Engine/Keys.lua).
	local keysPill = Instance.new("TextLabel")
	keysPill.Name = "KeysCounter"
	keysPill.Position = UDim2.fromOffset(74, 54)
	keysPill.Size = UDim2.fromOffset(86, 36)
	keysPill.BackgroundColor3 = Color3.fromRGB(90, 60, 30)
	keysPill.Text = "Keys 0"
	keysPill.Font = Enum.Font.GothamBold
	keysPill.TextSize = 18
	keysPill.TextColor3 = Color3.fromRGB(250, 235, 200)
	keysPill.TextTransparency = 0
	keysPill.TextStrokeTransparency = 1
	keysPill.ZIndex = 44
	keysPill.Visible = false
	keysPill.Parent = deps.parent
	deps.roundCorner(keysPill, 18)

	local icon = Instance.new("TextButton")
	icon.Name = "CompassIcon"
	-- Top left, just under the "Find me" button (14,8 to 36); this is the map's only compass (the old decorative
	-- compass_rose doodle was removed from JourneyMapScenery).
	icon.Position = UDim2.fromOffset(14, 46)
	icon.Size = UDim2.fromOffset(52, 52)
	icon.BackgroundColor3 = PARCHMENT
	icon.Text = "N"
	icon.TextSize = 28
	icon.Font = Enum.Font.GothamBold
	icon.TextColor3 = INK
	icon.AutoButtonColor = true
	icon.ZIndex = 44
	icon.Visible = false
	icon.Parent = deps.parent
	deps.roundCorner(icon, 26)
	local iconStroke = Instance.new("UIStroke")
	iconStroke.Color = Color3.fromRGB(110, 80, 45)
	iconStroke.Thickness = 3
	iconStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	iconStroke.Parent = icon

	local badge = Instance.new("TextLabel")
	badge.Name = "Charges"
	badge.AnchorPoint = Vector2.new(1, 1)
	badge.Position = UDim2.new(1, 6, 1, 6)
	badge.Size = UDim2.fromOffset(24, 24)
	badge.BackgroundColor3 = Color3.fromRGB(60, 120, 60)
	badge.Text = "0"
	badge.Font = Enum.Font.GothamBold
	badge.TextSize = 16
	badge.TextColor3 = CREAM
	badge.TextTransparency = 0
	badge.TextStrokeTransparency = 1
	badge.ZIndex = 46
	badge.Parent = icon
	deps.roundCorner(badge, 12)

	local panel = Instance.new("Frame")
	panel.Name = "CompassPanel"
	panel.Position = UDim2.fromOffset(14, 106)
	panel.Size = UDim2.fromOffset(300, 366)
	panel.BackgroundColor3 = PARCHMENT
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.ZIndex = 45
	panel.Parent = deps.parent
	deps.roundCorner(panel, 12)
	local panelStroke = Instance.new("UIStroke")
	panelStroke.Color = Color3.fromRGB(110, 80, 45)
	panelStroke.Thickness = 2
	panelStroke.Parent = panel

	local function label(text, y, size, h)
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Position = UDim2.fromOffset(12, y)
		l.Size = UDim2.new(1, -24, 0, h or 24)
		l.Text = text
		l.Font = Enum.Font.GothamBold
		l.TextSize = size or 16
		l.TextColor3 = INK
		l.TextTransparency = 0
		l.TextStrokeTransparency = 1
		l.TextWrapped = true
		l.ZIndex = 46
		l.Parent = panel
		return l
	end
	label("Compass", 8, 20, 26)
	local info = label("", 256, 15, 44)

	local function button(text, x, y, w, h, color)
		local b = Instance.new("TextButton")
		b.Position = UDim2.fromOffset(x, y)
		b.Size = UDim2.fromOffset(w, h)
		b.BackgroundColor3 = color or GOLD
		b.Text = text
		b.Font = Enum.Font.GothamBold
		b.TextSize = 16
		b.TextColor3 = color and CREAM or INK
		b.ZIndex = 47
		b.Parent = panel
		deps.roundCorner(b, 8)
		return b
	end

	local state = nil
	local currentStopId = WorldMap.Start
	local bearing = 90
	local pointed = nil -- stop id the wheel points at

	local wheel
	local function pointAt(b, id)
		bearing = b
		pointed = id or WorldMap.pickByBearing(currentStopId, b)
		deps.graph.highlight(pointed)
		if pointed then
			local x, y = deps.graph.positionOf(pointed)
			if x then
				deps.scrollTo(x, y) -- pan the camera in both axes toward the pointed road
			end
		else
			-- No road lies that way: pan toward the nearest unexplored / recommended road in that direction,
			-- or simply a screen's worth along the bearing (Engine/MapPan).
			local hx, hy = deps.graph.positionOf(currentStopId)
			if hx then
				local seen = {}
				for _, sid in ipairs(state and state.worldSeenStopIds or {}) do seen[sid] = true end
				local candidates = {}
				local here = WorldMap.Stops[currentStopId]
				for i, nxt in ipairs(here and here.next or {}) do
					local cx, cy = deps.graph.positionOf(nxt)
					if cx then
						candidates[#candidates + 1] = { id = nxt, x = cx, y = cy, unexplored = not seen[nxt], recommended = i == 1 }
					end
				end
				local hero = { x = hx, y = hy }
				local target = MapPan.compassTarget(hero, b, candidates)
				if target then
					deps.scrollTo(target.x, target.y)
				else
					local tx, ty = MapPan.stepToward(hx, hy, b, 420)
					deps.scrollTo(tx, ty)
				end
			end
		end
		local stop = pointed and WorldMap.Stops[pointed]
		info.Text = stop and ("Pointing at " .. stop.name) or "Turn the wheel to point at a road."
	end

	wheel = CompassWheel.new({
		parent = panel, size = 130,
		onTurn = function(b, id)
			pointAt(b, id)
		end,
	})
	wheel.frame.AnchorPoint = Vector2.new(0.5, 0)
	wheel.frame.Position = UDim2.new(0.5, 0, 0, 48)
	wheel.frame.ZIndex = 46

	local left = button("<", 14, 100, 44, 44)
	local right = button(">", 242, 100, 44, 44)
	left.MouseButton1Click:Connect(function()
		bearing = Layout.stepBearing(bearing, -15)
		wheel.setBearing(bearing)
		pointAt(bearing)
	end)
	right.MouseButton1Click:Connect(function()
		bearing = Layout.stepBearing(bearing, 15)
		wheel.setBearing(bearing)
		pointAt(bearing)
	end)

	local spend = button("Spend a charge: take this road", 12, 308, 276, 40, Color3.fromRGB(60, 120, 60))
	local canSpend -- defined below; the button does nothing unless a charge can be spent on the pointed road
	spend.MouseButton1Click:Connect(function()
		local folder = deps.ReplicatedStorage:FindFirstChild("Remotes")
		if not folder or not pointed or not canSpend() then
			return
		end
		local use, choose = folder:FindFirstChild("UseCompass"), folder:FindFirstChild("ChooseRoad")
		if use then
			use:FireServer(pointed) -- the server refuses (and keeps the charge) when that road is locked
		end
		if choose then
			choose:FireServer(pointed)
		end
	end)

	function canSpend()
		local choices = state and state.worldChoices
		if not (state and type(choices) == "table" and #choices > 1 and (state.compassCharges or 0) > 0 and pointed) then
			return false
		end
		return table.find(choices, pointed) ~= nil and not RoadLock.isLocked(state, pointed)
	end

	local function updateButtons()
		local charges = state and state.compassCharges or 0
		keysPill.Text = "Keys " .. RoadLock.keys(state)
		badge.Text = tostring(math.floor(charges))
		wheel.setCharges(charges)
		local ok = canSpend()
		spend.Visible = true
		spend.BackgroundColor3 = ok and Color3.fromRGB(60, 120, 60) or Color3.fromRGB(140, 125, 100)
		spend.Active = ok
		spend.AutoButtonColor = ok
		if not ok then
			if charges > 0 and pointed and RoadLock.isLocked(state, pointed) then
				spend.Text = "That road needs a Key"
			else
				spend.Text = charges > 0 and "Point at a road of the fork" or "No charges: preview only"
			end
		else
			spend.Text = "Spend a charge: take this road"
		end
	end

	icon.MouseButton1Click:Connect(function()
		panel.Visible = not panel.Visible
		if panel.Visible then
			updateButtons()
		else
			deps.graph.highlight(nil)
		end
	end)

	return {
		refresh = function(s)
			state = s
			local route = s and s.worldRoute
			currentStopId = (type(route) == "table" and route[#route]) or WorldMap.Start
			local icons = {}
			for _, id in ipairs(WorldMap.choicesAfter(currentStopId)) do
				local stop = WorldMap.Stops[id]
				icons[#icons + 1] = { bearing = WorldMap.bearing(currentStopId, id) or 0, text = stop.icon or "?", id = id }
			end
			wheel.setIcons(icons)
			updateButtons()
		end,
		setShown = function(shown)
			icon.Visible = shown
			keysPill.Visible = shown
			if not shown then
				panel.Visible = false
				deps.graph.highlight(nil)
			end
		end,
	}
end
