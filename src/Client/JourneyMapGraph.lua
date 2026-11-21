--[[
	Client/JourneyMapGraph.lua
	Draws the rest of the branching world on the Tavern Map canvas: every Night stop that is not on the
	player's road, and the dimmed dotted roads that split from and rejoin it. The road itself (picked stops
	plus the default road onward) stays the nodes JourneyMapView already draws. Positions come from the pure
	Engine/WorldMapLayout. Also adds:
	  - a "Take this road" chip on each stop of a pending fork (fires the ChooseRoad remote; the server
	    validates, the Round Select popup stays as a fallback);
	  - a reward badge on each biome's branch end;
	  - side stops (shop, shrine, rest, minigames) as small nodes on dotted detours off their parent stop; a
	    hidden one is a "?" stub until revealed with a map token or compass charge (SideStop remote, action
	    "reveal") and then pops in; a usable one shows a hint, since the stops themselves open on Round Select;
	  - the existing fog rule (current Night + 3 shown, +4 a "?" teaser, the rest hidden).

	Built with deps = { canvas, roundCorner, ReplicatedStorage, Engine, rewardText = fn(region) -> string|nil }.
	Returned: { layout(canvasW, canvasH, nodeSize, nightPixel), refresh(state), setShown(bool) }.
]]

return function(deps)
	local canvas = deps.canvas
	local Engine = deps.Engine
	deps.TweenService = deps.TweenService or game:GetService("TweenService")
	local WorldMap = require(Engine:WaitForChild("WorldMap"))
	local Layout = require(Engine:WaitForChild("WorldMapLayout"))
	local NodeRules = require(Engine:WaitForChild("MapNodeRules")) -- node type, tag and badge (same look as the road nodes)
	local RouteRules = require(Engine:WaitForChild("MapRouteRules")) -- one clean route: dashes, name plates, what is drawn
	local RoadLock = require(script.Parent.RoadLock) -- locked roads: padlock + "Unlock with a Key?" confirm

	local CREAM = Color3.fromRGB(250, 235, 200)
	local GOLD = Color3.fromRGB(222, 182, 104)
	local INK = Color3.fromRGB(60, 40, 22)

	local root = Instance.new("Frame")
	root.Name = "WorldGraph"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromScale(1, 1)
	root.Active = false
	root.ZIndex = 23
	root.Parent = canvas

	local nodeSize, canvasH = 72, 300
	local nightPixel = function() return 0, 0 end
	local laidOut = false -- build() waits for layout(): before it nightPixel is a (0,0) stub that stacked every stop at x=0
	local lastState = nil
	local shown = false
	local items = {} -- frames created by the last build (destroyed on rebuild)
	local highlighted = nil -- stop id the compass points at
	local focusId = nil -- stop whose biome reward chip is shown (tap or hover); nil = only the next branch end
	local lastPos = {} -- stopId -> {x, y} from the last build (route stops included)
	local lastBoxes = {} -- stopId -> node + label box from the last build (WorldMapLayout.boxesOf)

	-- "Name" over a coloured type tag line (SHOP gold, EVENT purple, BOSS red, Encounter green); long names keep the plain name
	local function tagged(label, typeId, maxChars)
		if #label.Text > maxChars then return end
		local c = NodeRules.tagFor(typeId).color
		label.RichText = true
		label.Text = string.format('%s\n<font color="#%02x%02x%02x"><b>%s</b></font>', label.Text, c[1], c[2], c[3], NodeRules.tagFor(typeId).text)
	end

	-- a round painting inside a node button (the button's own text is dropped)
	local SIDE_ART = { shop = "node_shop", shrine = "node_shrine", rest = "node_rest", minigame = "node_event" }
	local function paintNode(btn, artId)
		btn.Text = ""
		local img = Instance.new("ImageLabel")
		img.Name = "NodePainting"
		img.AnchorPoint = Vector2.new(0.5, 0.5)
		img.Position = UDim2.fromScale(0.5, 0.5)
		img.Size = UDim2.new(1, -6, 1, -6)
		img.BackgroundTransparency = 1
		img.BorderSizePixel = 0
		img.Image = artId
		img.ScaleType = Enum.ScaleType.Crop
		img.Active = false
		img.ZIndex = btn.ZIndex + 1
		img.Parent = btn
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0.5, 0)
		c.Parent = img
	end

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

	-- One smooth dashed route (14 px dashes, 10 px gaps) from the edge of one node to the edge of the next (Engine/MapRouteRules).
	-- lit = a road a fork offers or the compass points at. r1 and r2 are the two node radii.
	local function route(ax, ay, bx, by, r1, r2, lit, transparency, sign)
		local curve = RouteRules.curve(ax, ay, bx, by, sign or 1, 0.08)
		for _, d in ipairs(RouteRules.dashes(curve, r1 + 3, r2 + 3)) do
			local dash = remember(Instance.new("Frame"))
			dash.AnchorPoint = Vector2.new(0.5, 0.5)
			dash.Position = UDim2.fromOffset(d.x, d.y)
			dash.Size = UDim2.fromOffset(d.len, lit and 9 or 7)
			dash.Rotation = d.angle
			dash.BackgroundColor3 = lit and GOLD or Color3.fromRGB(244, 230, 196) -- cream
			dash.BackgroundTransparency = transparency
			dash.BorderSizePixel = 0
			dash.Active = false
			dash.ZIndex = 23
			dash.Parent = root
			deps.roundCorner(dash, 4)
			local edge = Instance.new("UIStroke")
			edge.Color = Color3.fromRGB(110, 84, 50)
			edge.Thickness = 1
			edge.Transparency = math.min(1, transparency + 0.1)
			edge.Parent = dash
		end
	end

	local function textLabel(text, x, y, w, h, size, z)
		local l = remember(Instance.new("TextLabel"))
		l.AnchorPoint = Vector2.new(0.5, 0)
		l.Position = UDim2.fromOffset(x, y)
		l.Size = UDim2.fromOffset(w, h)
		l.BackgroundColor3 = Color3.fromRGB(34, 24, 16) -- dark plate: cream text stays readable over any map art
		l.BackgroundTransparency = 0.1
		local plateCorner = Instance.new("UICorner")
		plateCorner.CornerRadius = UDim.new(0, 6)
		plateCorner.Parent = l
		l.Text = text
		l.Font = Enum.Font.GothamBold
		l.TextSize = math.max(size, 15)
		l.TextColor3 = CREAM
		l.TextStrokeColor3 = Color3.fromRGB(30, 22, 16)
		l.TextStrokeTransparency = 0.8
		l.TextTransparency = 0
		l.TextWrapped = true
		l.Active = false
		if #text > 4 and #text <= 28 then -- plate = text plus 12 px each side, sized by the engine (AutomaticSize), centred
			l.TextWrapped = false
			l.TextXAlignment = Enum.TextXAlignment.Center
			l.AutomaticSize = Enum.AutomaticSize.X
			l.Size = UDim2.fromOffset(0, h)
			local pad = Instance.new("UIPadding")
			pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 12), UDim.new(0, 12)
			pad.Parent = l
		end
		l.ZIndex = z or 25
		l.Parent = root
		return l
	end

	local popped = {} -- revealed side stops that already played their pop-in
	local menuFor, hintFor = nil, nil -- side stop whose reveal menu / "ready" hint is open
	local build

	function build()
		clear()
		if not shown or not laidOut then
			return
		end
		local state = lastState or {}
		local route = Layout.displayRoute(state.worldRoute)
		local nightX, routeY = {}, {}
		for d = 1, WorldMap.NIGHTS do
			nightX[d], routeY[d] = nightPixel(d)
		end
		local res = Layout.compute({ nightX = nightX, routeY = routeY, height = canvasH, route = route,
			minGap = math.floor(nodeSize * 1.5), nodeSize = nodeSize })
		local onRoute = {}
		for i, id in ipairs(route) do
			onRoute[id] = i
		end
		lastPos = res.pos
		lastBoxes = Layout.boxesOf(res, nodeSize, route)
		local night = math.floor(state.night or 1)
		local seen = {}
		for _, id in ipairs(state.worldSeenStopIds or {}) do
			seen[id] = true
		end
		local choices = {}
		for _, id in ipairs(state.worldChoices or {}) do
			choices[id] = true
		end
		local lockedRoad = {}
		for _, id in ipairs(state.lockedRoads or {}) do
			lockedRoad[id] = true
		end
		local keys = RoadLock.keys(state)
		local haveBadge = {}
		for _, b in ipairs(state.badgeIds or {}) do
			haveBadge[b] = true
		end
		local function takeRoad(id, stop)
			RoadLock.pick(id, state, deps.confirmParent or canvas, stop.name, function()
				fire(id)
			end)
		end
		local ends = Layout.branchEnds()
		-- Default chip: the next branch end ahead on the player's own road. Any other stop shows its chip
		-- only while focused (tapped or hovered), so the map is not covered in reward text.
		local nextEnd = nil
		for d, id in ipairs(route) do
			if ends[id] and d >= night then nextEnd = id break end
		end

		local function vis(id)
			if onRoute[id] then
				return "revealed"
			end
			return Layout.visibility(res.pos[id].depth, night, seen[id] == true)
		end

		-- what is drawn for a stop: "full" node with its label, a small "?" bubble with no label, or nothing (one clean route)
		local function lookOf(id)
			if onRoute[id] then return "full" end
			local v = vis(id)
			if v == "hidden" then return "hidden" end
			return RouteRules.stopLook(res.pos[id].depth, night, { choice = choices[id], lit = id == highlighted, teaser = v == "teaser" })
		end
		local size = math.floor(nodeSize * 0.78)
		local bubble = math.floor(nodeSize * 0.4)
		local function radiusOf(id)
			if onRoute[id] then return nodeSize / 2 end
			return (lookOf(id) == "bubble" and bubble or size) / 2
		end

		-- Roads: the picked road is the existing trail; every other road is a dim dashed curve between two drawn stops.
		for ei, e in ipairs(res.edges) do
			if not e.onRoute and lookOf(e.from) ~= "hidden" and lookOf(e.to) ~= "hidden" then
				local a, b = res.pos[e.from], res.pos[e.to]
				local lit = (choices[e.to] == true and onRoute[e.from] ~= nil) or e.to == highlighted
				route(a.x, a.y, b.x, b.y, radiusOf(e.from), radiusOf(e.to), lit, lit and 0.1 or 0.45, (ei % 2 == 0) and 1 or -1)
			end
		end

		for id, p in pairs(res.pos) do
			local v = lookOf(id) == "hidden" and "hidden" or vis(id)
			local stop = WorldMap.Stops[id]
			local region = WorldMap.Regions[stop.region]
			local tint = region and region.tint or { 200, 190, 150 }
			local top = p.y - (onRoute[id] and nodeSize or size) / 2 - 6
			-- Reward badge on the biome's branch end.
			local badge = nil
			if ends[id] and v ~= "hidden" and v ~= "teaser" then
				local text = deps.rewardText and deps.rewardText(ends[id])
				if text then
					local region = ends[id]
				local mark = haveBadge["master_" .. region] and "  Master" or (haveBadge["biome_" .. region] and "  cleared" or "")
				badge = textLabel(text .. mark, p.x, top - 24, 230, 22, 15, 27)
					badge.TextColor3 = Color3.fromRGB(255, 226, 150)
					badge.Name = "RewardChip_" .. id
					badge.Visible = focusId == id
					top = top - 24
				end
			end
			-- STAKES: a small stamp medal with the highest stake won on this finished road (state.stakeStamps).
				local stamp = ends[id] and v ~= "hidden" and v ~= "teaser" and state.stakeStamps and state.stakeStamps[ends[id]] or 0
				if stamp > 0 then
					local medal = textLabel(tostring(math.floor(stamp)), p.x + size / 2, p.y - size / 2 - 4, 24, 24, 15, 28)
					medal.Name = "StakeStamp_" .. id
					medal.AnchorPoint = Vector2.new(0.5, 0.5)
					medal.BackgroundTransparency = 0
					medal.BackgroundColor3 = Color3.fromRGB(222, 182, 104)
					medal.TextColor3 = Color3.fromRGB(60, 40, 22)
					medal.TextStrokeTransparency = 1
					deps.roundCorner(medal, 12)
					local ring = Instance.new("UIStroke")
					ring.Color = Color3.fromRGB(86, 58, 34)
					ring.Thickness = 2
					ring.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
					ring.Parent = medal
				end
				-- Take-this-road chip on a pending fork.
			if choices[id] then
				local chip = remember(Instance.new("TextButton"))
				chip.Name = "TakeRoad_" .. id
				chip.AnchorPoint = Vector2.new(0.5, 0)
				chip.Size = UDim2.fromOffset(lockedRoad[id] and 176 or 132, 28)
				chip.Position = UDim2.fromOffset(p.x, top - 30)
				chip.BackgroundColor3 = lockedRoad[id] and Color3.fromRGB(150, 110, 50) or Color3.fromRGB(60, 120, 60)
				chip.Text = lockedRoad[id] and (keys > 0 and "Unlock with a Key" or "Locked") or "Take this road"
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
				st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
				st.Parent = chip
				chip.Activated:Connect(function()
					takeRoad(id, stop)
				end)
			end
			if not onRoute[id] and v ~= "hidden" then
				local isBubble = lookOf(id) == "bubble"
				local size = isBubble and bubble or size -- a "?" bubble is small and has no label
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
				local stopArt = v ~= "teaser" and ((deps.nodeArt and deps.nodeArt(stop.art)) or (deps.paintArt and deps.paintArt("node_encounter"))) or nil
				if stopArt then paintNode(btn, stopArt) end
				local st = Instance.new("UIStroke")
				st.Color = glow and GOLD or Color3.fromRGB(110, 80, 45)
				st.Thickness = id == highlighted and 5 or (choices[id] and 3 or 2)
				st.Transparency = glow and 0 or 0.35
				st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
				st.Parent = btn
				if choices[id] then
					btn.Activated:Connect(function()
						takeRoad(id, stop)
					end)
				elseif badge then
					-- tap pins the reward chip, hover previews it
					btn.Activated:Connect(function()
						focusId = (focusId ~= id) and id or nil
						build()
					end)
				end
				if badge then
					btn.MouseEnter:Connect(function() badge.Visible = true end)
					btn.MouseLeave:Connect(function()
						badge.Visible = focusId == id
					end)
				end
				if lockedRoad[id] and v ~= "teaser" then -- every locked road keeps a padlock, pending or not
					local pad = textLabel("Lock", p.x + size / 2 - 2, p.y - size / 2 - 10, 30, 28, 22, 29)
					pad.Name = "Padlock_" .. id
					-- Keys cost, shown while the stop is focused (tap) or hovered
					local cost = textLabel(keys > 0 and "Costs 1 Key" or "Needs a Key", p.x, p.y - size / 2 - 34, 130, 22, 15, 41)
					cost.Name = "KeyCost_" .. id
					cost.TextColor3 = Color3.fromRGB(255, 226, 150)
					cost.Visible = focusId == id
					btn.MouseEnter:Connect(function() cost.Visible = true end)
					btn.MouseLeave:Connect(function() cost.Visible = (focusId == id) end)
					if not choices[id] and not badge then
						btn.Activated:Connect(function()
							focusId = (focusId ~= id) and id or nil
							build()
						end)
					end
				end
				if not isBubble and v ~= "teaser" and stop.name and stop.name ~= "" then -- no label plate for a "?" bubble or an empty name
					local plate = RouteRules.plate(stop.name, 16, RouteRules.PLATE_MAX)
					local lab = textLabel(stop.name, p.x, p.y + size / 2 + 6, plate.w, plate.h, 16, 26)
					lab.TextYAlignment = Enum.TextYAlignment.Center -- sized to its text: no empty line under the name
					if plate.wrap then
						lab.AutomaticSize = Enum.AutomaticSize.None
						lab.TextWrapped = true
						lab.Size = UDim2.fromOffset(plate.w, plate.h)
					end
					tagged(lab, NodeRules.typeOf("night"), 99)
				end
			end
		end

		-- Side stops: small nodes on a dotted detour off their parent. Hidden ones stay a "?" stub until
		-- revealed (map token or compass charge, standing at the parent); a reveal pops in once.
		local usable, revealable, revealed, visited = {}, {}, {}, {}
		for _, e in ipairs(state.sideStops or {}) do usable[e.id] = true end
		for _, id in ipairs(state.sideHidden or {}) do revealable[id] = true end
		for _, id in ipairs(state.sideRevealed or {}) do revealed[id] = true end
		for _, id in ipairs(state.sideVisited or {}) do visited[id] = true end
		local sideSize = math.floor(nodeSize * 0.56)
		local sideIds = {}
		for id in pairs(res.side) do sideIds[#sideIds + 1] = id end
		table.sort(sideIds)
		for _, id in ipairs(sideIds) do
			local p, stop = res.side[id], WorldMap.Stops[id]
			local parent = res.pos[p.parent]
			local stub = stop.hidden and not revealed[id]
			local glow = usable[id] == true or revealable[id] == true
			local sideLook = RouteRules.sideLook(res.pos[p.parent].depth, night, { stub = stub, glow = glow })
			if vis(p.parent) == "revealed" and sideLook ~= "hidden" then
				local sideSize = sideLook == "bubble" and math.floor(nodeSize * 0.34) or sideSize -- an unrevealed stop is a small "?" bubble
				route(parent.x, parent.y, p.x, p.y, nodeSize / 2, sideSize / 2, glow, glow and 0.1 or 0.35, 1)
				local btn = remember(Instance.new("TextButton"))
				btn.Name = "Side_" .. id
				btn.AnchorPoint = Vector2.new(0.5, 0.5)
				btn.Position = UDim2.fromOffset(p.x, p.y)
				btn.Size = UDim2.fromOffset(sideSize, sideSize)
				btn.BackgroundColor3 = stub and Color3.fromRGB(120, 105, 80) or Color3.fromRGB(222, 198, 150)
				btn.BackgroundTransparency = visited[id] and 0.5 or 0.1
				btn.Text = stub and "?" or (stop.icon or "?")
				btn.TextSize = math.floor(sideSize * 0.5)
				btn.Font = Enum.Font.GothamBold
				btn.TextColor3 = stub and CREAM or INK
				btn.AutoButtonColor = false
				btn.ZIndex = 27
				btn.Parent = root
				deps.roundCorner(btn, sideSize)
				local sideArt = (not stub) and deps.paintArt and deps.paintArt(SIDE_ART[stop.side]) or nil
				if sideArt then paintNode(btn, sideArt) end
				local st = Instance.new("UIStroke")
				st.Color = glow and GOLD or Color3.fromRGB(110, 80, 45)
				st.Thickness = glow and 3 or 2
				st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
				st.Parent = btn
				local lab = textLabel(stub and " " or (stop.name .. (visited[id] and " (done)" or "")), p.x + sideSize / 2 + 4, p.y, 150, 40, 15, 27)
				lab.Visible = not stub -- no label bar under or beside a "?" bubble
				-- label sits to the right of the node (WorldMapLayout.box "side")
				lab.AnchorPoint = Vector2.new(0, 0.5)
				lab.TextXAlignment = Enum.TextXAlignment.Left
				lab.TextYAlignment = Enum.TextYAlignment.Center
				local stype = NodeRules.typeOf("side", stop.side)
				if not stub then
					tagged(lab, stype, 16)
					local badgeKind = NodeRules.badgeFor(stype, visited[id] and "completed" or "available")
					if badgeKind then -- coin for a shop, ? for an event, a check once visited
						local bsz = math.max(18, math.floor(sideSize * 0.42))
						local b = textLabel(badgeKind == "check" and "OK" or (badgeKind == "coin" and "$" or "?"), p.x + sideSize * 0.35, p.y - sideSize * 0.35 - bsz / 2, bsz, bsz, 15, 29)
						b.Name = "Badge_" .. id
						b.AutomaticSize = Enum.AutomaticSize.None
						b.Size = UDim2.fromOffset(bsz, bsz)
						b.BackgroundColor3 = badgeKind == "coin" and Color3.fromRGB(222, 182, 60) or (badgeKind == "check" and Color3.fromRGB(90, 160, 80) or Color3.fromRGB(110, 60, 160))
						b.BackgroundTransparency = 0
						b.TextXAlignment = Enum.TextXAlignment.Center
						b.TextYAlignment = Enum.TextYAlignment.Center
						local bp = b:FindFirstChildOfClass("UIPadding")
						if bp then bp:Destroy() end
						b.TextWrapped = false
						local bc = b:FindFirstChildOfClass("UICorner")
						if bc then bc.CornerRadius = UDim.new(0.5, 0) end
					end
				end
				if p.compact and not stub then -- crowded spot (WorldMapLayout): the name shows while hovering
					lab.Visible = false
					btn.MouseEnter:Connect(function() lab.Visible = true end)
					btn.MouseLeave:Connect(function() lab.Visible = false end)
				end
				lab.TextTransparency = visited[id] and 0.25 or 0
				lab.TextStrokeTransparency = 0.8
				if revealed[id] and not popped[id] then
					popped[id] = true
					local sc = Instance.new("UIScale")
					sc.Scale = 0.2
					sc.Parent = btn
					deps.TweenService:Create(sc, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
				end
				btn.Activated:Connect(function()
					if revealable[id] then
						menuFor = (menuFor ~= id) and id or nil
						build()
					elseif usable[id] then
						hintFor = id
						build()
					end
				end)
				if hintFor == id then
					local h = textLabel("Ready! Close the map and open it from Round Select.", p.x, p.y - sideSize / 2 - 46, 200, 42, 15, 40)
					h.TextColor3 = Color3.fromRGB(255, 226, 150)
					task.delay(3, function()
						if hintFor == id then
							hintFor = nil
							build()
						end
					end)
				end
				-- Reveal menu: spend a map token or a compass charge.
				if menuFor == id and revealable[id] then
					local menu = remember(Instance.new("Frame"))
					menu.AnchorPoint = Vector2.new(0.5, 1)
					menu.Position = UDim2.fromOffset(p.x, p.y - sideSize / 2 - 8)
					menu.Size = UDim2.fromOffset(220, 98)
					menu.BackgroundColor3 = Color3.fromRGB(222, 198, 150)
					menu.ZIndex = 45
					menu.Parent = root
					deps.roundCorner(menu, 10)
					local ms = Instance.new("UIStroke")
					ms.Color = Color3.fromRGB(110, 80, 45)
					ms.Thickness = 2
					ms.Parent = menu
					local function option(text, y, enabled, method)
						local b = Instance.new("TextButton")
						b.Position = UDim2.fromOffset(8, y)
						b.Size = UDim2.new(1, -16, 0, 38)
						b.BackgroundColor3 = enabled and GOLD or Color3.fromRGB(150, 135, 110)
						b.Text = text
						b.Font = Enum.Font.GothamBold
						b.TextSize = 15
						b.TextColor3 = INK
						b.AutoButtonColor = enabled
						b.ZIndex = 46
						b.Parent = menu
						deps.roundCorner(b, 8)
						b.Activated:Connect(function()
							if not enabled then return end
							local folder = deps.ReplicatedStorage:FindFirstChild("Remotes")
							local remote = folder and folder:FindFirstChild("SideStop")
							if remote then
								remote:FireServer(id, "reveal", method)
							end
							menuFor = nil
						end)
					end
					local tokens, charges = math.floor(state.mapTokens or 0), math.floor(state.compassCharges or 0)
					option(string.format("Use a map token (%d)", tokens), 8, tokens > 0, "token")
					option(string.format("Use a compass charge (%d)", charges), 52, charges > 0, "compass")
				end
			end
		end
	end

	return {
		layout = function(canvasW, h, size, pixelFn)
			canvasH = h
			nodeSize = size
			nightPixel = pixelFn
			laidOut = true
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
		-- Nearest spot to (cx, cy) where a w x h box (centred) overlaps no node or label from the last
		-- build; scans down then up in 20px steps, then falls back to the request. Returns x, y.
		freeSpot = function(cx, cy, w, h)
			local function clashAt(y)
				local b = { x0 = cx - w / 2, x1 = cx + w / 2, y0 = y - h / 2, y1 = y + h / 2 }
				for _, other in pairs(lastBoxes) do
					if Layout.overlaps(b, other) then return true end
				end
				return false
			end
			for off = 0, math.max(canvasH, 200), 20 do
				for _, dir in ipairs({ 0, 1, -1 }) do
					local y = cy + dir * off
					if y - h / 2 >= 0 and y + h / 2 <= canvasH and not clashAt(y) then
						return cx, y
					end
				end
			end
			return cx, cy
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
				menuFor, hintFor = nil, nil
				clear()
			end
		end,
	}
end
