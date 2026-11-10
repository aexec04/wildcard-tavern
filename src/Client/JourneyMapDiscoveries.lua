--[[
	Client/JourneyMapDiscoveries.lua
	Hidden discovery spots on the Tavern Map (rules and placement in Engine/Discoveries.lua).
	  * A region's spots show once that road has been played (or a compass charge revealed them); tapping one
	    claims it (ClaimDiscovery remote, the server pays and shows the reward toast).
	  * Claimed spots stay as small gold check medals, so the counter "Discovered N of M" in the map header can be
	    followed on the map itself.
	  * In the region the player is standing in, an unrevealed region offers one chip to spend a compass charge and
	    reveal its spots (RevealDiscoveries remote).
	  * Unclaimed spots pulse softly, but only while the map is open AND the spot is inside the visible part of the
	    map; the pulse is one engine-run tween per spot, never per-frame code, and it is off under Reduce shake.

	deps = { canvas, scroll, roundCorner, TweenService, Engine, calm = fn() -> bool, graph = JourneyMapGraph }
	Returned: { layout(canvasW, canvasH, nodeSize), refresh(state), setShown(bool) }
]]

return function(deps)
	local canvas = deps.canvas
	local scroll = deps.scroll
	local TweenService = deps.TweenService
	local Engine = deps.Engine
	local WorldMap = require(Engine:WaitForChild("WorldMap"))
	local Discoveries = require(Engine:WaitForChild("Discoveries"))
	local ReplicatedStorage = game:GetService("ReplicatedStorage")

	local GOLD = Color3.fromRGB(222, 182, 104)
	local INK = Color3.fromRGB(60, 40, 22)
	local PARCHMENT = Color3.fromRGB(222, 198, 150)
	local CREAM = Color3.fromRGB(250, 235, 200)
	local SIZE = 44
	local KIND_ICON = { chest = "🧰", merchant = "🛒", secret_patron = "🔓" }
	local SPOT_NAMES = { chest = "Hidden chest", merchant = "Wandering merchant", secret_patron = "Secret stash" }
	local hover = require(script.Parent.MapHover).new({ canvas = canvas, TweenService = TweenService, calm = deps.calm })

	local root = Instance.new("Frame")
	root.Name = "Discoveries"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromScale(1, 1)
	root.Active = false
	root.ZIndex = 24
	root.Parent = canvas

	local canvasW, canvasH, nodeSize = 600, 300, 72
	local lastState
	local shown = false
	local items = {} -- frames of the last build
	local spotViews = {} -- { frame, stroke, tween, x, y, claimed }
	local checkToken = 0

	local function clear()
		for _, view in ipairs(spotViews) do
			if view.tween then view.tween:Cancel() end
		end
		spotViews = {}
		for _, inst in ipairs(items) do
			inst:Destroy()
		end
		items = {}
	end

	local function remote(name)
		local folder = ReplicatedStorage:FindFirstChild("Remotes")
		return folder and folder:FindFirstChild(name)
	end

	-- Where the stops of a region sit: centre x, centre y and half width, from the graph's last build.
	local function regionBox(region)
		local minX, maxX, sumY, n = math.huge, -math.huge, 0, 0
		for id, stop in pairs(WorldMap.Stops) do
			if stop.kind == "night" and stop.region == region then
				local x, y = deps.graph.positionOf(id)
				if x then
					minX, maxX = math.min(minX, x), math.max(maxX, x)
					sumY = sumY + y
					n = n + 1
				end
			end
		end
		if n == 0 then
			return nil
		end
		return (minX + maxX) / 2, sumY / n, math.max(120, (maxX - minX) / 2 + 90)
	end

	local function playerRegion(state)
		local route = state and state.worldRoute
		local last = type(route) == "table" and route[#route] or nil
		return last and WorldMap.regionOf(last) or nil
	end

	-- Pulse only the spots that are on screen (checked when the map moves, throttled).
	local function updatePulses()
		local pos, size = scroll.CanvasPosition, scroll.AbsoluteSize
		for _, view in ipairs(spotViews) do
			local visible = shown and not view.claimed and not deps.calm()
				and view.x >= pos.X - SIZE and view.x <= pos.X + size.X + SIZE
				and view.y >= pos.Y - SIZE and view.y <= pos.Y + size.Y + SIZE
			if visible and not view.tween then
				view.tween = TweenService:Create(view.stroke, TweenInfo.new(1.1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Thickness = 4.5 })
				view.tween:Play()
			elseif not visible and view.tween then
				view.tween:Cancel()
				view.tween = nil
				view.stroke.Thickness = 2.5
			end
		end
	end
	scroll:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
		checkToken += 1
		local mine = checkToken
		task.delay(0.15, function()
			if mine == checkToken then updatePulses() end
		end)
	end)

	local function build()
		clear()
		if not shown or not lastState or type(lastState.discoveries) ~= "table" then
			return
		end
		local disc = lastState.discoveries
		local here = playerRegion(lastState)
		for _, spot in ipairs(Discoveries.spots()) do
			local cx, cy, halfW = regionBox(spot.region)
			if cx then
				local place = Discoveries.place(spot.region, spot.index)
				local x = math.clamp(cx + place.dx * halfW, SIZE, canvasW - SIZE)
				local y = cy + place.side * (nodeSize * 1.5 + place.lift * canvasH * 0.4)
				y = math.clamp(y, SIZE, canvasH - SIZE)
				if deps.graph.freeSpot then
					x, y = deps.graph.freeSpot(x, y, SIZE + 8, SIZE + 8)
				end
				local revealed = disc.revealed and disc.revealed[spot.region]
				local claimed = disc.claimed and disc.claimed[spot.id]
				if revealed or claimed then
					local button = Instance.new("TextButton")
					button.Name = "Spot_" .. spot.id
					button.AnchorPoint = Vector2.new(0.5, 0.5)
					button.Position = UDim2.fromOffset(x, y)
					button.Size = UDim2.fromOffset(SIZE, SIZE)
					button.BackgroundColor3 = claimed and Color3.fromRGB(170, 150, 100) or PARCHMENT
					button.Font = Enum.Font.GothamBold
					button.TextSize = 22
					button.TextColor3 = INK
					button.Text = claimed and "✔" or (KIND_ICON[spot.kind] or "?")
					button.AutoButtonColor = not claimed
					button.ZIndex = 26
					button.Parent = root
					deps.roundCorner(button, SIZE / 2)
					local stroke = Instance.new("UIStroke")
					stroke.Color = GOLD
					stroke.Thickness = 2.5
					stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
					stroke.Parent = button
					items[#items + 1] = button
					if not claimed then -- painted mark over the emoji (art is a child, so the button text is blanked, not hidden)
						require(script.Parent.ArtIcon).apply(button, "discoveries", spot.kind, button, { zIndex = 27, cornerRadius = SIZE / 2 })
					end
					spotViews[#spotViews + 1] = { frame = button, stroke = stroke, x = x, y = y, claimed = claimed == true }
					hover.bind(button, function() -- hover card: honest about what it is (spots only exist once revealed)
						local region = WorldMap.Regions[spot.region]
						return {
							title = SPOT_NAMES[spot.kind] or "Hidden spot", biome = region and region.name or "",
							line = claimed and "You already found this." or "Tap to open it for a reward.", done = claimed == true,
						}
					end, { noGlow = true })
					if not claimed then
						button.MouseButton1Click:Connect(function()
							local r = remote("ClaimDiscovery")
							if r then r:FireServer(spot.id) end
						end)
					end
				end
			end
		end
		-- the compass chip: only in the region the player stands in, only when its spots are still hidden
		if here and not (disc.revealed and disc.revealed[here]) and (lastState.compassCharges or 0) >= 1 then
			local cx, cy = regionBox(here)
			if cx then
				local chip = Instance.new("TextButton")
				chip.Name = "RevealSpots"
				chip.AnchorPoint = Vector2.new(0.5, 0.5)
				chip.Position = UDim2.fromOffset(math.clamp(cx, 150, canvasW - 150), math.clamp(cy - nodeSize * 1.6, 30, canvasH - 30))
				chip.Size = UDim2.fromOffset(280, 32)
				chip.BackgroundColor3 = Color3.fromRGB(86, 58, 34)
				chip.Font = Enum.Font.GothamBold
				chip.TextSize = 15
				chip.TextColor3 = CREAM
				chip.Text = "🧭 Use a charge: reveal secrets here"
				chip.ZIndex = 27
				chip.Parent = root
				deps.roundCorner(chip, 8)
				local stroke = Instance.new("UIStroke")
				stroke.Color = GOLD
				stroke.Thickness = 1.5
				stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
				stroke.Parent = chip
				items[#items + 1] = chip
				chip.MouseButton1Click:Connect(function()
					local r = remote("RevealDiscoveries")
					if r then r:FireServer(here) end
				end)
			end
		end
		updatePulses()
	end

	return {
		layout = function(w, h, size)
			canvasW, canvasH, nodeSize = w, h, size
			build()
		end,
		refresh = function(state)
			lastState = state
			build()
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
