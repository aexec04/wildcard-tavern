--[[
	Client/JourneyMapGraph.lua
	Draws the rest of the branching world on the Tavern Map canvas: every Night stop that is not on the
	player's road, and the dimmed dotted roads that split from and rejoin it. The road itself (picked stops
	plus the default road onward) stays the nodes JourneyMapView already draws. Positions come from the pure
	Engine/WorldMapLayout. Also adds:
	  - a "Take this road" chip on each stop of a pending fork (fires the ChooseRoad remote; the server
	    validates, the Round Select popup stays as a fallback);
	  - a reward badge on each biome's branch end;
	  - the existing fog rule (current Night + 3 shown, +4 a "?" teaser, the rest hidden).

	Built with deps = { canvas, roundCorner, ReplicatedStorage, Engine, rewardText = fn(region) -> string|nil }.
	Returned: { layout(canvasW, canvasH, nodeSize, nightPixel), refresh(state), setShown(bool) }.
]]

return function(deps)
	local canvas = deps.canvas
	local Engine = deps.Engine
	local WorldMap = require(Engine:WaitForChild("WorldMap"))
	local Layout = require(Engine:WaitForChild("WorldMapLayout"))

	local CREAM = Color3.fromRGB(250, 235, 200)
	local GOLD = Color3.fromRGB(222, 182, 104)
	local INK = Color3.fromRGB(60, 40, 22)
	local DOT_STEP = 16

	local root = Instance.new("Frame")
	root.Name = "WorldGraph"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromScale(1, 1)
	root.Active = false
	root.ZIndex = 23
	root.Parent = canvas

	local nodeSize, canvasH = 72, 300
	local nightPixel = function() return 0, 0 end
	local lastState = nil
	local shown = false
	local items = {} -- frames created by the last build (destroyed on rebuild)
	local highlighted = nil -- stop id the compass points at
	local lastPos = {} -- stopId -> {x, y} from the last build (route stops included)

	local function remember(inst)
		items[#items + 1] = inst
		return inst
	end

	local function clear()
		for _, inst in ipairs(items) do
			inst:Destroy()
		end
		items = {}
	end

	local function fire(stopId)
		local folder = deps.ReplicatedStorage:FindFirstChild("Remotes")
		local remote = folder and folder:FindFirstChild("ChooseRoad")
		if remote then
			remote:FireServer(stopId)
		end
	end

	local function dotted(ax, ay, bx, by, color, transparency)
		local dx, dy = bx - ax, by - ay
		local len = math.sqrt(dx * dx + dy * dy)
		local n = math.max(2, math.floor(len / DOT_STEP))
		for k = 1, n - 1 do
			local t = k / n
			local dot = remember(Instance.new("Frame"))
			dot.Size = UDim2.fromOffset(7, 7)
			dot.AnchorPoint = Vector2.new(0.5, 0.5)
			dot.Position = UDim2.fromOffset(ax + dx * t, ay + dy * t)
			dot.BackgroundColor3 = color
			dot.BackgroundTransparency = transparency
			dot.BorderSizePixel = 0
			dot.Active = false
			dot.ZIndex = 23
			dot.Parent = root
			deps.roundCorner(dot, 4)
		end
	end

	local function textLabel(text, x, y, w, h, size, z)
		local l = remember(Instance.new("TextLabel"))
		l.AnchorPoint = Vector2.new(0.5, 0)
		l.Position = UDim2.fromOffset(x, y)
		l.Size = UDim2.fromOffset(w, h)
		l.BackgroundTransparency = 1
		l.Text = text
		l.Font = Enum.Font.GothamBold
		l.TextSize = size
		l.TextColor3 = CREAM
		l.TextStrokeColor3 = Color3.fromRGB(30, 22, 16)
		l.TextStrokeTransparency = 0.3
		l.TextTransparency = 0
		l.TextWrapped = true
		l.Active = false
		l.ZIndex = z or 25
		l.Parent = root
		return l
	end

	local function build()
		clear()
		if not shown then
			return
		end
		local state = lastState or {}
		local route = Layout.displayRoute(state.worldRoute)
		local nightX, routeY = {}, {}
		for d = 1, WorldMap.NIGHTS do
			nightX[d], routeY[d] = nightPixel(d)
		end
		local res = Layout.compute({ nightX = nightX, routeY = routeY, height = canvasH, route = route,
			minGap = math.floor(nodeSize * 1.5) })
		local onRoute = {}
		for i, id in ipairs(route) do
			onRoute[id] = i
		end
		lastPos = res.pos
		local night = math.floor(state.night or 1)
		local seen = {}
		for _, id in ipairs(state.worldSeenStopIds or {}) do
			seen[id] = true
		end
		local choices = {}
		for _, id in ipairs(state.worldChoices or {}) do
			choices[id] = true
		end
		local ends = Layout.branchEnds()

		local function vis(id)
			if onRoute[id] then
				return "revealed"
			end
			return Layout.visibility(res.pos[id].depth, night, seen[id] == true)
		end

		-- Roads: the picked road is the existing trail; every other road is dim and dotted.
		for _, e in ipairs(res.edges) do
			if not e.onRoute then
				local a, b = res.pos[e.from], res.pos[e.to]
				local va, vb = vis(e.from), vis(e.to)
				if va ~= "hidden" and vb ~= "hidden" then
					local lit = (choices[e.to] == true and onRoute[e.from] ~= nil) or e.to == highlighted
					dotted(a.x, a.y, b.x, b.y, lit and GOLD or Color3.fromRGB(110, 90, 62), lit and 0.15 or 0.5)
				end
			end
		end

		local size = math.floor(nodeSize * 0.78)
		for id, p in pairs(res.pos) do
			local v = vis(id)
			local stop = WorldMap.Stops[id]
			local region = WorldMap.Regions[stop.region]
			local tint = region and region.tint or { 200, 190, 150 }
			local top = p.y - (onRoute[id] and nodeSize or size) / 2 - 6
			-- Reward badge on the biome's branch end.
			if ends[id] and v ~= "hidden" then
				local text = deps.rewardText and deps.rewardText(ends[id])
				if text then
					local badge = textLabel("🎁 " .. text, p.x, top - 24, 190, 22, 15, 27)
					badge.TextColor3 = Color3.fromRGB(255, 226, 150)
					if v == "teaser" then
						badge.TextTransparency = 0.4
					end
					top = top - 24
				end
			end
			-- Take-this-road chip on a pending fork.
			if choices[id] then
				local chip = remember(Instance.new("TextButton"))
				chip.Name = "TakeRoad_" .. id
				chip.AnchorPoint = Vector2.new(0.5, 0)
				chip.Size = UDim2.fromOffset(132, 28)
				chip.Position = UDim2.fromOffset(p.x, top - 30)
				chip.BackgroundColor3 = Color3.fromRGB(60, 120, 60)
				chip.Text = "Take this road"
				chip.Font = Enum.Font.GothamBold
				chip.TextSize = 15
				chip.TextColor3 = CREAM
				chip.AutoButtonColor = true
				chip.ZIndex = 40
				chip.Parent = root
				deps.roundCorner(chip, 8)
				local st = Instance.new("UIStroke")
				st.Color = GOLD
				st.Thickness = 1.5
				st.Parent = chip
				chip.Activated:Connect(function()
					fire(id)
				end)
			end
			if not onRoute[id] and v ~= "hidden" then
				local btn = remember(Instance.new("TextButton"))
				btn.Name = "Stop_" .. id
				btn.AnchorPoint = Vector2.new(0.5, 0.5)
				btn.Position = UDim2.fromOffset(p.x, p.y)
				btn.Size = UDim2.fromOffset(size, size)
				btn.BackgroundColor3 = Color3.fromRGB(tint[1], tint[2], tint[3])
				local glow = choices[id] or id == highlighted
				btn.BackgroundTransparency = glow and 0 or 0.3
				btn.Text = v == "teaser" and "?" or (stop.icon or "?")
				btn.TextSize = math.floor(size * 0.45)
				btn.Font = Enum.Font.GothamBold
				btn.TextColor3 = v == "teaser" and INK or Color3.fromRGB(255, 255, 255)
				btn.AutoButtonColor = false
				btn.ZIndex = 26
				btn.Parent = root
				deps.roundCorner(btn, size)
				local st = Instance.new("UIStroke")
				st.Color = glow and GOLD or Color3.fromRGB(110, 80, 45)
				st.Thickness = id == highlighted and 5 or (choices[id] and 3 or 2)
				st.Transparency = glow and 0 or 0.35
				st.Parent = btn
				if choices[id] then
					btn.Activated:Connect(function()
						fire(id)
					end)
				end
				local name = v == "teaser" and "???" or stop.name
				local lab = textLabel(name, p.x, p.y + size / 2 + 6, 190, 44, 16, 26)
				lab.TextYAlignment = Enum.TextYAlignment.Top
				if not choices[id] then
					lab.TextTransparency = 0.25
				end
			end
		end
	end

	return {
		layout = function(canvasW, h, size, pixelFn)
			canvasH = h
			nodeSize = size
			nightPixel = pixelFn
			build()
		end,
		refresh = function(state)
			lastState = state
			build()
		end,
		-- The compass points at a road: its stop (and the road leading to it) light up.
		highlight = function(stopId)
			if highlighted ~= stopId then
				highlighted = stopId
				build()
			end
		end,
		-- Canvas position of a stop from the last build (nil before the first layout).
		positionOf = function(stopId)
			local p = lastPos[stopId]
			return p and p.x, p and p.y
		end,
		setShown = function(s)
			shown = s
			if s then
				build()
			else
				clear()
			end
		end,
	}
end
