--[[
	Client/JourneyMapView.lua
	The "Tavern Map" tab of the Journey screen: the 8 named Night locations,
	the Endless doors and the Endless milestone nodes on a map. Node positions
	are normalized (0-1) coordinates from Shared/Engine/JourneyMap.lua, drawn on
	a canvas that keeps the map's aspect ratio (scrolls sideways when narrow).

	Background: JourneyMap.Config.journeyMapImage. An id of "rbxassetid://0",
	or one that fails to load, falls back to the UI-built parchment look.

	Treasure-map look: a winding dotted ink trail between round parchment
	medallions that show each landmark (ContentArt map_nodes/<key>, emoji circle
	as the fallback). Node states: cleared (gold wax seal), current (lantern
	glow ring, bobbing red X, hero token standing on it), locked (dimmed art,
	"?" and fog), boss tier badge. Tapping a node opens a detail card (reward,
	how it unlocks, Equip). Candle glows, embers, the X bob and the Endless
	portal spin run only while the map is shown (stopAmbient on hide).

	Clear moment: when the map is shown and a node has been cleared since the
	player last looked, its seal stamps on (with a sparkle burst and a tiny map
	shake), the hero hops along the trail to the next node, that node lights
	up and the reward pops with a short message. Animation speed and "reduce
	screen shake" settings are respected (no bounce when shake is reduced).

	Studio-only debug (never built in live servers): a "Nudge" button in the
	map's corner shows each node's normalized x/y and lets you drag nodes;
	new coordinates print to the Output window as lines ready to paste into
	Engine/JourneyMap.lua.

	State used: state.clearedNightIds (Nights 1-8 and Endless milestone
	Nights), state.night, state.wonRun, state.profileStats.bestNightReached,
	state.cosmetics, state.equippedTitleId.

	deps: parent (the Journey panel), polishPanel, polishButton, roundCorner,
	getLatestState, titleLabel, subtitleLabel, StateUpdatedRemote, playClickSfx

	Returns:
		{
			frame = Frame,
			refresh = function(),
			setShown = function(bool),
			applyHeader = function(isMapTab) -- title/subtitle text and colors
		}
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local ContentProvider = game:GetService("ContentProvider")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

return function(deps)
	local Engine = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine")
	local JourneyMap = require(Engine:WaitForChild("JourneyMap"))
	local CardBacks = require(Engine:WaitForChild("CardBacks"))
	local CosmeticSets = require(Engine:WaitForChild("CosmeticSets"))
	local Achievements = require(Engine:WaitForChild("Achievements"))
	local PlayerProfile = require(Engine:WaitForChild("PlayerProfile"))
	local ClientSettings = require(script.Parent.ClientSettings)
	local PatronPlaque = require(script.Parent.PatronPlaque)
	local ContentArtJMV = require(Engine:WaitForChild("ContentArt"))
	local MapPan = require(Engine:WaitForChild("MapPan")) -- 2D camera maths (clamp, centre, compass target)
	local WorldMapView = require(Engine:WaitForChild("WorldMap")) -- chosen road names on the Night nodes
	local lookups = { cardBack = CardBacks, set = CosmeticSets, title = Achievements }

	local function rgb(t)
		return Color3.fromRGB(t[1], t[2], t[3])
	end

	local CREAM = Color3.fromRGB(250, 240, 220)
	local SOFT = Color3.fromRGB(215, 200, 178)
	local DIM = Color3.fromRGB(140, 130, 120)
	local GOLD = Color3.fromRGB(255, 214, 130)
	local GOLD_DARK = Color3.fromRGB(150, 115, 50)
	local INK = Color3.fromRGB(30, 22, 16)
	local PURPLE = rgb(JourneyMap.EndlessTheme.accent)
	local MAP_BG = Color3.fromRGB(58, 44, 30)
	local MAP_BG_ENDLESS = rgb(JourneyMap.EndlessTheme.background)

	local nodeData = JourneyMap.allNodes()
	local NODE_COUNT = #nodeData
	local ENDLESS_INDEX = JourneyMap.NightCap + 1

	local equipRemote = nil
	task.spawn(function()
		local remotes = ReplicatedStorage:WaitForChild("Remotes", 10)
		equipRemote = remotes and remotes:WaitForChild("EquipJourneyReward", 10)
	end)

	-- Speed multiplier from Settings > Animation Speed (1 = normal).
	local function pace()
		return PlayerProfile.animationPaceDivisor(ClientSettings.get("animSpeed"), false)
	end
	local function calm()
		return ClientSettings.get("reduceShake") == true
	end

	local frame = Instance.new("Frame")
	frame.Name = "TavernMap"
	frame.Size = UDim2.new(1, -20, 1, -144)
	frame.Position = UDim2.new(0, 10, 0, 88) -- room for the two-line Journey plate above
	frame.BackgroundColor3 = MAP_BG
	frame.ZIndex = 21
	frame.Visible = false
	frame.Parent = deps.parent
	deps.polishPanel(frame, 10, "parchment")
	pcall(function() require(script.Parent.ThemeWash).attach(frame, "mapBackdrop") end) -- the equipped Card Set dresses this scene (Engine/ThemeScenes)

	local scroll = Instance.new("ScrollingFrame")
	scroll.Size = UDim2.new(1, -16, 1, -12)
	scroll.Position = UDim2.fromOffset(8, 6)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 4 -- thin: the world is panned by dragging, the wheel and the compass
	scroll.ScrollingDirection = Enum.ScrollingDirection.XY -- a 2D world: pan up, down, left and right (edges clamp)
	scroll.CanvasSize = UDim2.fromOffset(0, 0)
	scroll.ZIndex = 22
	scroll.Parent = frame

	local canvas = Instance.new("Frame")
	canvas.Name = "Canvas"
	canvas.BackgroundTransparency = 1
	canvas.Size = UDim2.fromOffset(600, 300)
	canvas.ZIndex = 22
	canvas.Parent = scroll

	-- Region backdrops, seam fog and decor doodles (art optional; flat parchment fallback).
	local scenery = require(script.Parent.JourneyMapScenery)({
		canvas = canvas, roundCorner = deps.roundCorner, ContentArt = ContentArtJMV,
		RegionTiles = require(Engine:WaitForChild("RegionTiles")),
		MapSeams = require(Engine:WaitForChild("MapSeams")),
		PropRules = require(Engine:WaitForChild("MapPropRules")),
		TweenService = TweenService, calm = calm, parentFrame = frame, addTooltip = deps.addTooltip,
	})
	-- The rest of the branching world (other roads, fork chips, biome reward badges); see JourneyMapGraph.
	local BiomeRewardsJMV = require(Engine:WaitForChild("BiomeRewards"))
	local panelRef = {} -- set to the selection panel once it exists (it is built after the graph)
	local worldGraph = require(script.Parent.JourneyMapGraph)({
		-- the selection panel in canvas pixels, so side stop names keep 12 px clear of it
		avoidRect = function()
			local sp = panelRef.p
			if not sp then return nil end
			local okR, r = pcall(sp.rect)
			if not (okR and r) then return nil end
			local fa, ca = frame.AbsolutePosition, canvas.AbsolutePosition
			return { x = r.x + fa.X - ca.X, y = r.y + fa.Y - ca.Y, w = r.w, h = r.h }
		end,
		-- canvas y of the header bar's bottom edge: fork stops stay below it
		bandTop = function()
			local a = scroll.AbsoluteSize
			local okH, H = pcall(function() return require(Engine:WaitForChild("MapHeaderRules")).layout(a.X + 16, a.Y + 12) end)
			return okH and H and (H.bar.h - 6) or nil
		end,
		canvas = canvas, roundCorner = deps.roundCorner, ReplicatedStorage = ReplicatedStorage, Engine = Engine,
		confirmParent = frame, -- the "Unlock with a Key?" dialog covers the visible map, not the scrolling canvas
		nodeArt = function(key) return key and ContentArtJMV.getImageId("map_nodes", key) or nil end,
		paintArt = function(key) return key and ContentArtJMV.getImageId("map_paint", key) or nil end,
		rewardText = function(region)
			local row = BiomeRewardsJMV.Rows[region]
			local reward = row and row.reward and row.reward[1]
			if not reward then
				return nil
			end
			local more = #row.reward - 1
			return BiomeRewardsJMV.label(reward) .. (more > 0 and (" +" .. more) or "")
		end,
	})
	-- Hidden discovery spots (chests, merchants, secret Patrons) per region; see JourneyMapDiscoveries.
	local worldDiscoveries = require(script.Parent.JourneyMapDiscoveries)({
		canvas = canvas, scroll = scroll, roundCorner = deps.roundCorner, TweenService = TweenService, Engine = Engine,
		calm = calm, graph = worldGraph,
	})
	-- Compass icon and wheel overlay (turns the map view toward the pointed road).
	local worldCompass = require(script.Parent.JourneyMapCompass)({
		parent = frame, roundCorner = deps.roundCorner, ReplicatedStorage = ReplicatedStorage, Engine = Engine,
		graph = worldGraph,
		scrollTo = function(x, y)
			-- pans the camera in both axes to centre (x, y); clamped to the canvas (Engine/MapPan)
			local size = scroll.AbsoluteSize
			local cx, cy = MapPan.centerOn(x, y or scroll.CanvasSize.Y.Offset / 2,
				scroll.CanvasSize.X.Offset, scroll.CanvasSize.Y.Offset, size.X, size.Y)
			TweenService:Create(scroll, TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
				{ CanvasPosition = Vector2.new(cx, cy) }):Play()
		end,
	})
	-- Fog of war: drifting cloud band, "???" teaser glow and the hint tag.
	local fogBand = require(script.Parent.JourneyMapFog)({
		canvas = canvas, TweenService = TweenService, roundCorner = deps.roundCorner, calm = calm, pace = pace, ContentArt = ContentArtJMV,
	})

	local function text(parent, props)
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Font = Enum.Font.Gotham
		l.TextColor3 = CREAM
		l.TextTransparency = 0
		l.TextStrokeTransparency = 1
		l.TextWrapped = true
		l.ZIndex = 26
		for k, v in pairs(props) do
			l[k] = v
		end
		l.Parent = parent
		return l
	end

	-- ===== Treasure-map look =====
	local TRAIL_INK = Color3.fromRGB(70, 46, 26)
	local LABEL_INK = Color3.fromRGB(60, 40, 22)
	local PARCHMENT = Color3.fromRGB(226, 202, 156)
	local TAG_PARCHMENT = Color3.fromRGB(236, 216, 172)
	-- Node names: cream with a dark stroke (same as Round Select titles) so locked and
	-- unlocked labels read equally well over the painted map.
	local NAME_CREAM = Color3.fromRGB(250, 235, 200)
	local NAME_STROKE = Color3.fromRGB(35, 22, 10)
	local RIBBON = Color3.fromRGB(150, 48, 40)

	local function mapArt(key)
		return key and ContentArtJMV.getImageId("map_nodes", key) or nil
	end
	-- the painted Tavern Map pieces (parchment, round node paintings, boss emblem); nil until their ids exist, then the old art stays in use
	local function paintArt(key)
		return key and ContentArtJMV.getImageId("map_paint", key) or nil
	end

	local unlocking = false -- true while the clear moment runs (refresh leaves the picture alone)
	local requestRender -- set once refresh() exists (art that loads late re-renders)
	-- declared up here: applyRoad and render use these, and a local declared further down is a nil global to them
	local MapSelectRules = require(Engine:WaitForChild("MapSelectRules")) -- dashed routes and the lower left selection panel
	local selectedIndex = nil -- the selected node (lower left panel): drawn with the selected look
	local selectNode -- defined after the panel exists

	-- ===== Trail: dotted ink path along a Bezier (segment i joins node i to i + 1) =====
	local segments = {}
	for i = 1, NODE_COUNT - 1 do
		segments[i] = { dots = {}, count = 0, length = 0, filled = false, sign = (i % 2 == 0) and 1 or -1,
			mode = "full", modeChanged = false, -- fog: "full", "fade" (dissolving into the fog) or "none"
			ax = 0, ay = 0, bx = 0, by = 0, cx = 0, cy = 0 }
	end

	local function bezier(seg, t)
		local u = 1 - t
		return u * u * seg.ax + 2 * u * t * seg.cx + t * t * seg.bx,
			u * u * seg.ay + 2 * u * t * seg.cy + t * t * seg.by
	end

	-- ===== Road: a continuous dirt path under the dots, so every stop leads visibly to the next =====
	-- Overlapping round pieces every ~7px along the same Bezier: a dark edge piece under a
	-- sandy fill piece (outline first, fills on top, both below the dots at ZIndex 24).
	-- Light sandy road (~32px) with a dark edge so it stands out against any biome art.
	local ROAD_EDGE = Color3.fromRGB(110, 78, 40)
	local ROAD_FILL = Color3.fromRGB(244, 230, 196)
	local RouteRules = require(Engine:WaitForChild("MapRouteRules")) -- dash layout along one smooth curve per connection
	local function makeRoadPiece(seg)
		-- one rounded dash (14 x 8 px at rest) with a thin darker edge, drawn under the nodes
		local fill = Instance.new("Frame")
		fill.AnchorPoint = Vector2.new(0.5, 0.5)
		fill.Size = UDim2.fromOffset(RouteRules.DASH, 8)
		fill.BackgroundColor3 = ROAD_FILL
		fill.BorderSizePixel = 0
		fill.Visible = false -- applyRoad shows the dashes that belong to a revealed road
		fill.ZIndex = 23
		fill.Parent = canvas
		deps.roundCorner(fill, 4)
		local edge = Instance.new("UIStroke")
		edge.Color = ROAD_EDGE
		edge.Thickness = 1
		edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		edge.Parent = fill
		return { fill = fill, edge = edge }
	end
	-- Show the road with its segment: hidden in the fog, thinning out toward a teaser node.
	local function applyRoad(seg)
		if not seg.road then return end
		local look = MapSelectRules.routeLook(selectedIndex ~= nil and seg.into == selectedIndex, seg.filled)
		local thick = math.max(6, look.thickness - 4)
		local setFill, setEdge -- the equipped Card Set tints the road toward its accent (CosmeticSets.mapPathOf); classic keeps the sand
		pcall(function()
			local f, e = require(Engine:WaitForChild("CosmeticSets")).mapPathOf(require(script.Parent.TavernKit).plateSetId(), look.color, look.edge)
			if f then setFill, setEdge = Color3.fromRGB(f[1], f[2], f[3]), Color3.fromRGB(e[1], e[2], e[3]) end
		end)
		for k, piece in ipairs(seg.road) do
			local shown = k <= (seg.roadCount or 0) and seg.mode ~= "none"
			piece.fill.Visible = shown
			if shown then
				piece.fill.Size = UDim2.fromOffset(RouteRules.DASH, thick)
				piece.edge.Color = Color3.fromRGB(look.edge[1], look.edge[2], look.edge[3])
				piece.fill.BackgroundColor3 = Color3.fromRGB(look.color[1], look.color[2], look.color[3])
				if setFill then
					piece.fill.BackgroundColor3 = setFill
					piece.edge.Color = setEdge
				end
				local tr = 0
				if seg.mode == "fade" then
					tr = math.min(0.95, 0.15 + 0.8 * ((k - 1) / math.max((seg.roadCount or 1) - 1, 1)))
				elseif seg.mode == "dim" then
					tr = 0.5 -- the not yet revealed stretch: a dimmer dashed path that carries on to the boss
				end
				piece.fill.BackgroundTransparency = tr
				piece.edge.Transparency = tr
				piece.fill.ZIndex = seg.mode == "dim" and 36 or 23 -- the dim stretch rides above the fog band (35) so it stays visible
			end
		end
	end

	local function makeDot(seg)
		local dot = Instance.new("Frame")
		dot.AnchorPoint = Vector2.new(0.5, 0.5)
		dot.BackgroundColor3 = TRAIL_INK
		dot.BorderSizePixel = 0
		dot.ZIndex = 24
		dot.Parent = canvas
		deps.roundCorner(dot, 4)
		local foot = text(dot, {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(16, 16),
			TextSize = 12, Text = "", TextWrapped = false, ZIndex = 25, TextTransparency = 1, Visible = false, -- small: decorative footprint glyph
		})
		return { frame = dot, foot = foot }
	end

	-- Visual target of a dot: cleared = solid ink (every 4th a tiny footprint), upcoming = faint.
	local function dotTargets(seg, k)
		if seg.mode == "none" or seg.mode == "dim" then
			return { frame = 1, foot = 1, size = 5 }
		elseif seg.mode == "fade" then
			local t = (k - 1) / math.max(seg.count - 1, 1)
			return { frame = math.min(0.97, 0.4 + 0.57 * t), foot = 1, size = math.max(2, math.floor(5 - 3 * t + 0.5)) }
		end
		if seg.filled then
			if k % 4 == 0 then
				return { frame = 1, foot = 0, size = 7 }
			end
			return { frame = 0, foot = 1, size = 7 }
		end
		return { frame = 0.65, foot = 1, size = 5 }
	end

	local function setDot(seg, k, animate, duration, delay)
		local dot = seg.dots[k]
		local tgt = dotTargets(seg, k)
		dot.frame.Visible = false -- the cream dashed path is the route now; the ink dots stay built so the walk and unlock code keep working
		dot.foot.Visible = false
		if animate then
			dot.frame.BackgroundTransparency = 1
			dot.foot.TextTransparency = 1
			local info = TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.Out, 0, false, delay)
			TweenService:Create(dot.frame, info, { BackgroundTransparency = tgt.frame }):Play()
			if dot.foot.Visible then
				TweenService:Create(dot.foot, info, { TextTransparency = 0 }):Play()
			end
		else
			dot.frame.BackgroundTransparency = tgt.frame
			dot.foot.TextTransparency = dot.foot.Visible and 0 or 1
		end
		dot.frame.Size = UDim2.fromOffset(tgt.size, tgt.size)
	end

	-- ===== Nodes =====
	local nodeHover = require(script.Parent.MapHover).new({ canvas = canvas, TweenService = TweenService, calm = calm })
	local MapNodeRules = require(Engine:WaitForChild("MapNodeRules")) -- node type, state, tag and badge rules (the new node look)
	local revealStateOf = function() return nil end -- replaced below, once `reveal` exists (it is declared after buildNode)
	local nodes = {}
	local nodeSize = 84
	local currentSize, currentNode = 110, nil -- the current node is drawn larger (Engine/MapFitRules CURRENT_SCALE)
	local markerIndex = nil

	local function buildNode(index)
		local data = nodeData[index]
		local info = data.info
		local isEndless = data.kind == "endless"

		-- Round parchment-framed medallion.
		local button = Instance.new("TextButton")
		button.Name = "Node" .. index
		button.AnchorPoint = Vector2.new(0.5, 0.5)
		button.Position = UDim2.fromOffset(0, 0) -- placed by layout()
		button.Size = UDim2.fromOffset(nodeSize, nodeSize)
		button.BackgroundColor3 = PARCHMENT
		button.AutoButtonColor = false
		button.Text = ""
		button.ZIndex = 26
		button.Parent = canvas
		deps.roundCorner(button, 60)
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 3
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Parent = button
		local scale = Instance.new("UIScale")
		scale.Parent = button

		-- Lantern-glow ring for the current node.
		local halo = Instance.new("Frame")
		halo.AnchorPoint = Vector2.new(0.5, 0.5)
		halo.Position = UDim2.fromScale(0.5, 0.5)
		halo.Size = UDim2.fromScale(1.35, 1.35)
		halo.BackgroundTransparency = 1
		halo.Visible = false
		halo.ZIndex = 25
		halo.Parent = button
		deps.roundCorner(halo, 70)
		local haloStroke = Instance.new("UIStroke")
		haloStroke.Thickness = 5
		haloStroke.Transparency = 0.2
		haloStroke.Parent = halo
		local haloScale = Instance.new("UIScale")
		haloScale.Parent = halo
		-- second gold ring just outside the medallion (a double ring); child of the halo so it shows and hides with it
		if MapNodeRules.typeOf(data.kind, nil, data.night == JourneyMap.NightCap) ~= "boss" then -- a boss keeps its one crimson ring, no second gold ring
			local ring = Instance.new("Frame")
			ring.Name = "InnerRing"
			ring.AnchorPoint = Vector2.new(0.5, 0.5)
			ring.Position = UDim2.fromScale(0.5, 0.5)
			ring.Size = UDim2.fromScale(0.83, 0.83)
			ring.BackgroundTransparency = 1
			ring.ZIndex = 25
			ring.Parent = halo
			deps.roundCorner(ring, 70)
			local rs = Instance.new("UIStroke")
			rs.Color = Color3.fromRGB(240, 196, 98)
			rs.Thickness = 3
			rs.Transparency = 0.1
			rs.Parent = ring
		end
		-- soft warm glow behind the current node (child of the halo, so it shows and hides with it)
		require(script.Parent.SoftGlow).build(halo, { name = "CurrentGlow", color = Color3.fromRGB(255, 196, 96), position = UDim2.fromScale(0.5, 0.5),
			size = UDim2.fromScale(1.7, 1.7), peak = 0.45, inner = 0.4, zIndex = 24 })

		-- Emoji fallback (shown when the landmark art is missing or fails to load).
		local icon = text(button, {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.45), Size = UDim2.fromScale(0.8, 0.6),
			TextSize = 36, Text = info.icon, TextWrapped = false, ZIndex = 27,
		})
		local art
		local isBossNode = data.kind ~= "endless" and data.night == JourneyMap.NightCap
		-- the boss node wears the crowned skull emblem on a crimson disc; every other node keeps its own place painting,
		-- with the encounter painting when that is missing
		local artId = (isBossNode and paintArt("boss_emblem")) or mapArt(info.art) or paintArt("node_encounter")
		if isBossNode and paintArt("boss_emblem") then
			button.BackgroundColor3 = Color3.fromRGB(78, 22, 22)
		end
		if artId then
			art = PatronPlaque.applyById(button, artId, {
				emojiLabel = icon, zIndex = 27, cornerRadius = 60,
				size = UDim2.new(1, -12, 1, -12), position = UDim2.fromOffset(6, 6),
			})
		end

		-- Fog for locked nodes (a soft grey wash, never black).
		local fog = Instance.new("Frame")
		fog.Size = UDim2.new(1, -6, 1, -6)
		fog.Position = UDim2.fromOffset(3, 3)
		fog.BackgroundColor3 = Color3.fromRGB(190, 184, 176)
		fog.BackgroundTransparency = 0.55
		fog.BorderSizePixel = 0
		fog.Visible = false
		fog.ZIndex = 28
		fog.Parent = button
		deps.roundCorner(fog, 60)

		-- Night number on a small ribbon.
		local ribbon = text(button, {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 1), Size = UDim2.fromOffset(40, 20),
			Font = Enum.Font.GothamBold, TextSize = 16, TextWrapped = false, ZIndex = 30, BackgroundTransparency = 0,
			BackgroundColor3 = RIBBON, Text = isEndless and "oo" or tostring(data.night),
		})
		deps.roundCorner(ribbon, 5)

		local bossBadge
		if data.kind == "night" or data.kind == "milestone" then
			local tierInfo = JourneyMap.BossTiers[JourneyMap.bossTierFor(data.night)]
			bossBadge = text(button, {
				AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.1, 0.1), Size = UDim2.fromOffset(26, 26),
				TextSize = 16, TextWrapped = false, Text = tierInfo.icon, BackgroundTransparency = 0,
				BackgroundColor3 = Color3.fromRGB(110, 40, 40), ZIndex = 30,
			})
			deps.roundCorner(bossBadge, 13)
		end

		-- Cleared: gold wax seal (OK badge when the seal art is unavailable).
		local check = text(button, {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.88, 0.12), Size = UDim2.fromOffset(26, 26),
			Font = Enum.Font.GothamBold, TextSize = 16, TextWrapped = false, Text = "OK", BackgroundTransparency = 0,
			BackgroundColor3 = GOLD, TextColor3 = INK, Visible = false, ZIndex = 31,
		})
		deps.roundCorner(check, 13)
		local seal, sealScale
		local sealId = mapArt("wax_seal_gold")
		if sealId then
			seal = Instance.new("ImageLabel")
			seal.Name = "Seal"
			seal.AnchorPoint = Vector2.new(0.5, 0.5)
			seal.Position = UDim2.fromScale(0.88, 0.12)
			seal.Size = UDim2.fromOffset(38, 38)
			seal.BackgroundTransparency = 1
			seal.Image = sealId
			seal.ScaleType = Enum.ScaleType.Fit
			seal.Visible = false
			seal.ZIndex = 31
			seal.Parent = button
			sealScale = Instance.new("UIScale")
			sealScale.Parent = seal
			seal:GetPropertyChangedSignal("IsLoaded"):Connect(function()
				if requestRender then
					requestRender()
				end
			end)
			-- Hidden images are not fetched on their own; ask for it so the OK fallback can swap to the seal.
			task.spawn(function()
				pcall(function()
					ContentProvider:PreloadAsync({ seal })
				end)
				if requestRender then
					requestRender()
				end
			end)
		end

		-- Locked: small "?".
		local lockMark = text(button, {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.88, 0.12), Size = UDim2.fromOffset(24, 24),
			Font = Enum.Font.GothamBold, TextSize = 16, TextWrapped = false, Text = "\u{1F512}", BackgroundTransparency = 0,
			BackgroundColor3 = PARCHMENT, TextColor3 = LABEL_INK, Visible = false, ZIndex = 31,
		})
		deps.roundCorner(lockMark, 12)
		-- Hover: lift and an info card; fogged stops only say "???" (the node's own click opens its detail card).
		nodeHover.bind(button, function()
			local fogState = revealStateOf(index)
			if fogState ~= nil and fogState ~= "revealed" then
				return { title = "???", biome = "Night " .. tostring(data.night), line = "Something stirs in the fog." }
			end
			return { title = info.name, biome = isEndless and "Endless Nights" or ("Night " .. tostring(data.night)), line = "Tap for details and rewards." }
		end, { noGlow = true })

		-- Endless: slowly rotating portal (20 s per turn).
		local spin
		if isEndless and art then
			spin = TweenService:Create(art, TweenInfo.new(20, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, -1, false), { Rotation = 360 })
		end

		-- Labels live on the canvas (not the button) so the button's UIScale
		-- pop does not stretch the text. Dark ink with a parchment stroke.
		local name = text(canvas, {
			AnchorPoint = Vector2.new(0.5, 0), Size = UDim2.fromOffset(200, 22), TextWrapped = true,
			Font = Enum.Font.GothamBold, TextSize = 17, Text = info.name, ZIndex = 26, -- under popups (30+) and node icons
			TextColor3 = NAME_CREAM, TextStrokeColor3 = NAME_STROKE, TextStrokeTransparency = 0.8,
			BackgroundColor3 = Color3.fromRGB(34, 24, 16), BackgroundTransparency = 0.12, -- dark plate keeps the name readable on any biome
		})
		do
			local plateCorner = Instance.new("UICorner")
			plateCorner.CornerRadius = UDim.new(0, 6)
			plateCorner.Parent = name
		end
		-- Type tag under the name (SHOP gold, EVENT purple, BOSS red, Encounter green); the Finish Night is the boss.
		local ntype = MapNodeRules.typeOf(data.kind, nil, data.night == JourneyMap.NightCap)
		local tagLook = MapNodeRules.tagFor(ntype)
		-- a small dark pill in the tag colour with cream text, readable on any parchment
		local tc = tagLook.color
		local typeTag = text(canvas, {
			Name = "TypeTag", AnchorPoint = Vector2.new(0.5, 0), Size = UDim2.fromOffset(0, MapNodeRules.TAG_H), TextWrapped = false, AutomaticSize = Enum.AutomaticSize.X,
			Font = Enum.Font.GothamBlack, TextSize = 14, Text = tagLook.text, ZIndex = 27, BackgroundTransparency = 0.05,
			BackgroundColor3 = Color3.fromRGB(math.floor(tc[1] * 0.35), math.floor(tc[2] * 0.35), math.floor(tc[3] * 0.35)),
			TextColor3 = CREAM, TextStrokeColor3 = Color3.fromRGB(20, 12, 6), TextStrokeTransparency = 0.8,
		})
		do
			local pc = Instance.new("UICorner")
			pc.CornerRadius = UDim.new(0, 9)
			pc.Parent = typeTag
			local pp = Instance.new("UIPadding")
			pp.PaddingLeft, pp.PaddingRight = UDim.new(0, 10), UDim.new(0, 10)
			pp.Parent = typeTag
			local ps = Instance.new("UIStroke")
			ps.Color = Color3.fromRGB(tc[1], tc[2], tc[3])
			ps.Thickness = 1.5
			ps.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			ps.Parent = typeTag
		end
		if ntype == "boss" then
			name.BackgroundColor3 = Color3.fromRGB(78, 22, 22)
			local bossEdge = Instance.new("UIStroke")
			bossEdge.Color = Color3.fromRGB(200, 60, 50)
			bossEdge.Thickness = 2
			bossEdge.Parent = name
		end
		-- Reward on a small hanging tag.
		local tag = Instance.new("Frame")
		tag.AnchorPoint = Vector2.new(0.5, 0)
		tag.Size = UDim2.fromOffset(0, 24)
		tag.AutomaticSize = Enum.AutomaticSize.X
		tag.BackgroundColor3 = TAG_PARCHMENT
		tag.BorderSizePixel = 0
		tag.ZIndex = 27
		tag.Parent = canvas
		deps.roundCorner(tag, 6)
		local tagStroke = Instance.new("UIStroke")
		tagStroke.Color = Color3.fromRGB(110, 80, 45)
		tagStroke.Thickness = 1.5
		tagStroke.Parent = tag
		local tagPad = Instance.new("UIPadding")
		tagPad.PaddingLeft = UDim.new(0, 8)
		tagPad.PaddingRight = UDim.new(0, 8)
		tagPad.Parent = tag
		local string_ = Instance.new("Frame")
		string_.AnchorPoint = Vector2.new(0.5, 1)
		string_.Position = UDim2.fromScale(0.5, 0)
		string_.Size = UDim2.fromOffset(2, 6)
		string_.BackgroundColor3 = Color3.fromRGB(110, 80, 45)
		string_.BorderSizePixel = 0
		string_.ZIndex = 27
		string_.Parent = tag
		local preview = text(tag, {
			Size = UDim2.fromOffset(0, 24), AutomaticSize = Enum.AutomaticSize.X, TextSize = 14, Text = "",
			TextWrapped = false, ZIndex = 28, Font = Enum.Font.GothamBold, TextColor3 = LABEL_INK,
		})

		local pulse = TweenService:Create(haloStroke, TweenInfo.new(1.1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Transparency = 0.85 })
		local pulseScale = TweenService:Create(haloScale, TweenInfo.new(1.1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Scale = 1.12 })

		if isBossNode then -- the destination draws above the fog band (35) so it never disappears into the mist
			for _, g in ipairs({ button, table.unpack(button:GetDescendants()) }) do
				if g:IsA("GuiObject") then g.ZIndex = g.ZIndex + 14 end
			end
			name.ZIndex, typeTag.ZIndex, tag.ZIndex = name.ZIndex + 14, typeTag.ZIndex + 14, tag.ZIndex + 14
		end
		nodes[index] = {
			button = button, stroke = stroke, scale = scale, halo = halo, haloStroke = haloStroke, haloScale = haloScale,
			icon = icon, art = art, fog = fog, ribbon = ribbon, bossBadge = bossBadge, check = check, seal = seal,
			sealScale = sealScale, lockMark = lockMark, spin = spin, name = name, tag = tag, preview = preview,
			pulse = pulse, pulseScale = pulseScale, pulsing = false, data = data, isEndless = isEndless, tagStroke = tagStroke,
			typeTag = typeTag, ntype = ntype,
		}
	end

	for index = 1, NODE_COUNT do
		buildNode(index)
	end

	-- ===== Hero token + bobbing red X (stands on the current node) =====
	local marker = Instance.new("Frame")
	marker.Name = "HeroMarker"
	marker.AnchorPoint = Vector2.new(0.5, 1)
	marker.Size = UDim2.fromOffset(64, 92)
	marker.BackgroundTransparency = 1
	marker.Visible = false
	marker.ZIndex = 33
	marker.Parent = canvas
	local bobber = Instance.new("Frame")
	bobber.Size = UDim2.fromScale(1, 1)
	bobber.BackgroundTransparency = 1
	bobber.ZIndex = 33
	bobber.Parent = marker
	-- The hero (avatar clone -> avatar bust -> token), built when the map opens, destroyed when it closes.
	local hero = require(script.Parent.JourneyMapHero)({
		parent = bobber, Players = game:GetService("Players"), TweenService = TweenService,
		ContentArt = ContentArtJMV, PatronPlaque = PatronPlaque, roundCorner = deps.roundCorner, calm = calm,
	})
	local bobTween = TweenService:Create(bobber, TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Position = UDim2.fromOffset(0, -5) })

	-- ===== Candle glows, embers, sparkle layer =====
	-- Flame positions measured on art-wip/backgrounds/journey_map.png (normalized).
	local FLAMES = {} -- the old baked-in painting had flames; the region art does not
	local glows = {}
	for i, f in ipairs(FLAMES) do
		local outer = Instance.new("Frame")
		outer.Name = "FlameGlow" .. i
		outer.AnchorPoint = Vector2.new(0.5, 0.5)
		outer.Position = UDim2.fromScale(f[1], f[2])
		outer.BackgroundColor3 = Color3.fromRGB(255, 170, 70)
		outer.BackgroundTransparency = 0.7
		outer.BorderSizePixel = 0
		outer.Visible = false
		outer.ZIndex = 23
		outer.Parent = canvas
		deps.roundCorner(outer, 100)
		local core = Instance.new("Frame")
		core.AnchorPoint = Vector2.new(0.5, 0.5)
		core.Position = UDim2.fromScale(0.5, 0.5)
		core.Size = UDim2.fromScale(0.45, 0.45)
		core.BackgroundColor3 = Color3.fromRGB(255, 225, 150)
		core.BackgroundTransparency = 0.55
		core.BorderSizePixel = 0
		core.ZIndex = 23
		core.Parent = outer
		deps.roundCorner(core, 100)
		local gScale = Instance.new("UIScale")
		gScale.Parent = outer
		glows[i] = { frame = outer, scale = gScale, fx = f[1], fy = f[2] }
	end

	local embers = {}
	for i = 1, 0 do
		local e = Instance.new("Frame")
		e.Name = "Ember" .. i
		e.AnchorPoint = Vector2.new(0.5, 0.5)
		e.Size = UDim2.fromOffset(3, 3)
		e.BackgroundColor3 = Color3.fromRGB(255, 190, 90)
		e.BorderSizePixel = 0
		e.Visible = false
		e.ZIndex = 24
		e.Parent = canvas
		deps.roundCorner(e, 2)
		embers[i] = e
	end

	local sparkleLayer = Instance.new("Frame")
	sparkleLayer.Name = "Sparkles"
	sparkleLayer.Size = UDim2.fromScale(1, 1)
	sparkleLayer.BackgroundTransparency = 1
	sparkleLayer.ZIndex = 32
	sparkleLayer.Parent = canvas

	-- ===== Edge fades so the horizontal scroll is obvious: ONE smooth gradient frame per side (no stepped strips) =====
	require(script.Parent.SmoothVignette).build(frame, { zIndex = 36, color = Color3.fromRGB(0, 0, 0), name = "MapEdgeFade",
		left = { strength = 0.7, extent = 0.04 }, right = { strength = 0.7, extent = 0.04 } })

	-- ===== Layout: one winding trail left to right =====
	-- Nodes sit at least MIN_SPACING apart on a gentle zig-zag; even nodes ride high
	-- (label above, reward tag below), odd nodes ride low (label and tag below).
	local canvasW, canvasH = 600, 300
	local viewH = 300 -- visible height; the canvas is MapPan.WORLD_SCREENS_Y times taller
	local userPannedY = false -- once the player drags vertically, auto-follow stops re-centering the band
	local MapFit = require(Engine:WaitForChild("MapFitRules"))
	local nodeNames = {}
	for i = 1, NODE_COUNT do nodeNames[i] = nodeData[i].info.name end
	local bossSize = 150
	local routeFits = false -- the whole Night route is on screen at the default zoom (set in layout)
	local mapFitLogged = nil -- the view size the [MapFit] Studio line was last printed for
	local posX, posY = {}, {}
	local nudged = {} -- nodes dragged with the Studio Nudge tool keep the dragged spot
	local debugOn = false -- Studio-only coordinate overlay / drag mode (reveals everything while on)
	local reveal = { states = {}, newly = {} } -- fog state per node, set by render
	revealStateOf = function(index) return reveal.states[index] end
	local revealOverride = nil -- Night used for the fog while the clear moment replays
	local fogAnimate = false -- true while the fog band rolls back
	local lastLayoutKey = nil
	local shownFlags, shownKey = nil, nil -- which nodes are drawn: the layout spreads exactly those evenly from the start to the boss
	local heroWalking = false -- true while the hero walks the trail
	local followHero = false -- the camera tracks the hero while it walks

	local function nodePixel(index)
		if nudged[index] then
			local info = nodeData[index].info
			return info.x * canvasW, info.y * canvasH
		end
		return posX[index] or 0, posY[index] or 0
	end

	local function scrollTargetFor(x)
		if routeFits and x <= (posX[JourneyMap.NightCap] or 0) + 1 then return 0 end -- the Nights all fit: the camera stays at the start
		-- Early nodes sit about 15 percent from the left edge (no blank beige before Night 1); later ones drift to the centre.
		local frac = 0.15 + 0.35 * math.clamp(x / math.max(1, canvasW * 0.5), 0, 1)
		return math.clamp(x - scroll.AbsoluteSize.X * frac, 0, math.max(0, canvasW - scroll.AbsoluteSize.X))
	end
	-- Vertical camera: centred on the road band, unless the player has panned up/down themselves.
	local nodeBandY = nil -- nil = the canvas middle, where the road runs (set in layout)
	local function scrollTargetY(y)
		if userPannedY then
			return scroll.CanvasPosition.Y
		end
		local _, cy = MapPan.centerOn(0, y or canvasH / 2, canvasW, canvasH, scroll.AbsoluteSize.X, scroll.AbsoluteSize.Y)
		return cy
	end

	-- Where the hero's feet rest at node `index`: on the trail just before it
	-- (beside the medallion, clear of its label), or left of the first node.
	local function standPoint(index)
		-- the figure stands ON the node: centred, feet on the ring (callers add 6 px), so it is never beside the node or clipped by the frame
		local x, y = nodePixel(index)
		return x, y + math.floor(currentSize * 0.26) - 6
	end

	local function placeMarker()
		if not markerIndex or not nodes[markerIndex] then
			marker.Visible = false
			return
		end
		if heroWalking then
			return -- the walk drives the position
		end
		local x, y = standPoint(markerIndex)
		marker.Position = UDim2.fromOffset(x, y + 6)
		marker.Visible = true
	end

	-- Fog edge: the first node that is not fully revealed. A teaser sits right on
	-- the edge (half inside the fog); with no teaser the edge sits past the last
	-- revealed node.
	local HINT_Y = require(Engine:WaitForChild("FullScreenRules")).STRIP_H + 22 -- canvas y of the fog chip: just under the header strip
	local function updateFog(animate)
		local states = reveal.states
		local first
		for i = 1, NODE_COUNT do
			if states[i] and states[i] ~= "revealed" then
				first = i
				break
			end
		end
		if not first or debugOn then
			fogBand.update({ edgeX = nil })
			scenery.setFogEdge(nil)
			return
		end
		local fx, fy = nodePixel(first)
		if states[first] == "teaser" then
			-- The tag (centred 40px right of hintX, about 290x36) must not sit on any graph node or label.
			-- Beside the glowing node (right side, 14px gap), level with it, so it never reaches the node
			-- below. FogBand places the tag's centre at hintX + 40, so hintX is shifted back by 40.
			-- the fog chip is small and sits top centre, under the header, never over the painted scenery or a node
			fogBand.update({ edgeX = fx, teaser = { x = fx, y = fy, size = nodeSize }, hintX = canvasW / 2 - 40, hintY = HINT_Y,
				animate = animate })
			scenery.setFogEdge(fx)
		else
			local px = nodePixel(first - 1)
			local edge = px + (fx - px) * 0.7
			fogBand.update({ edgeX = edge, hintX = canvasW / 2 - 40, hintY = HINT_Y, animate = animate })
			scenery.setFogEdge(edge)
		end
	end

	local function layout(force)
		local size = scroll.AbsoluteSize
		if size.X < 10 or size.Y < 10 then
			return
		end
		local key = size.X .. "x" .. size.Y
		if not force and key == lastLayoutKey then
			return
		end
		lastLayoutKey = key
		-- the whole Night route fits the frame at the default zoom (Engine/MapFitRules, tested at four sizes)
		local fit = MapFit.layout(size.X + 2 * MapFit.FRAME_X, size.Y + 2 * MapFit.FRAME_Y, nodeNames, JourneyMap.NightCap, shownFlags, currentNode)
		viewH = fit.viewH
		canvasH = math.max(fit.canvasH, size.Y)
		nodeSize, bossSize, currentSize = fit.nodeSize, fit.bossSize, fit.currentSize
		marker.Size = UDim2.fromOffset(math.floor(currentSize * 0.62), math.floor(currentSize * 0.82)) -- the figure stands about 140 px tall on the 170 px current node
		canvasW = math.max(fit.canvasW, size.X)
		local spacing = fit.spacing
		routeFits = fit.fits
		if RunService:IsStudio() then
			local key = size.X .. "x" .. size.Y
			if mapFitLogged ~= key then
				mapFitLogged = key
				warn(string.format("[MapFit] canvas %dx%d view %dx%d nodeSize %d boss %d nodes %d spacing %d fits=%s",
					canvasW, canvasH, size.X, size.Y, fit.nodeSize, fit.bossSize, NODE_COUNT, math.floor(fit.spacing), tostring(fit.fits)))
			end
		end
		canvas.Size = UDim2.fromOffset(canvasW, canvasH)
		scroll.CanvasSize = UDim2.fromOffset(canvasW, canvasH)
		local minY, maxY = math.huge, -math.huge
		for index = 1, NODE_COUNT do
			posX[index], posY[index] = fit.posX[index], fit.posY[index]
			minY, maxY = math.min(minY, posY[index]), math.max(maxY, posY[index])
		end
		local labelW = fit.labelW
		local LABEL_GAP, TAG_H = 10, 24
		for index, node in ipairs(nodes) do
			local x, y = nodePixel(index)
			local info = node.data.info
			node.button.Position = UDim2.fromOffset(x, y)
			local size = node.ntype == "boss" and bossSize or (index == currentNode and currentSize or nodeSize) -- the boss node is larger, the current one next
			node.button.Size = UDim2.fromOffset(size, size)
			node.icon.TextSize = math.floor(size * 0.45)
			local plate = RouteRules.plate(info.name, node.name.TextSize, RouteRules.PLATE_MAX) -- never wider than 180 px, two lines at most
			local fits = not plate.wrap
			local labelH = plate.h
			if fits then -- plate = text plus 12 px each side, sized by the engine (AutomaticSize), centred
				node.name.TextWrapped = false
				node.name.TextXAlignment = Enum.TextXAlignment.Center
				node.name.AutomaticSize = Enum.AutomaticSize.X
				node.name.Size = UDim2.fromOffset(0, labelH)
				if not node.name:FindFirstChildOfClass("UIPadding") then
					local pad = Instance.new("UIPadding")
					pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 12), UDim.new(0, 12)
					pad.Parent = node.name
				end
			else
				node.name.AutomaticSize = Enum.AutomaticSize.None
				node.name.TextWrapped = true
				node.name.TextXAlignment = Enum.TextXAlignment.Center
				node.name.Size = UDim2.fromOffset(plate.w, labelH)
			end
			-- Labels always sit BELOW the node (never over its icon or the detail popup above).
			node.name.AnchorPoint = Vector2.new(0.5, 0)
			node.name.TextYAlignment = Enum.TextYAlignment.Center
			node.name.Position = UDim2.fromOffset(x, y + size / 2 + LABEL_GAP)
			node.typeTag.Position = UDim2.fromOffset(x, y + size / 2 + LABEL_GAP + labelH + 2)
			node.tag.Position = UDim2.fromOffset(x, y + size / 2 + LABEL_GAP + labelH + 2 + MapNodeRules.TAG_H + 8)
			local nextData = nodeData[index + 1]
			if nextData then
				local nx, ny = nodePixel(index + 1)
				local seg = segments[index]
				seg.ax, seg.ay = x, y
				seg.bx, seg.by = nx, ny
				local dx, dy = seg.bx - seg.ax, seg.by - seg.ay
				seg.length = math.sqrt(dx * dx + dy * dy)
				-- Winding: control point pushed sideways, alternating per segment (the walk and the dots use the same curve).
				local px, py = -dy / math.max(seg.length, 1), dx / math.max(seg.length, 1)
				seg.cx = (seg.ax + seg.bx) / 2 + px * seg.length * 0.1 * seg.sign
				seg.cy = (seg.ay + seg.by) / 2 + py * seg.length * 0.1 * seg.sign
				seg.count = math.clamp(math.floor(seg.length * 1.15 / 14), 6, 80)
				while #seg.dots < seg.count do
					table.insert(seg.dots, makeDot(seg))
				end
				-- one smooth curve per connection: 14 px dashes, 10 px gaps, from the edge of one node to the edge of the next
				local nextNode = nodes[index + 1]
				local r1 = size / 2 + 3
				local r2 = ((nextNode and nextNode.ntype == "boss") and bossSize or (index + 1 == currentNode and currentSize or nodeSize)) / 2 + 3
				local dashes = RouteRules.dashes({ ax = seg.ax, ay = seg.ay, bx = seg.bx, by = seg.by, cx = seg.cx, cy = seg.cy }, r1, r2)
				seg.road = seg.road or {}
				seg.roadCount = #dashes
				while #seg.road < seg.roadCount do
					table.insert(seg.road, makeRoadPiece(seg))
				end
				for k, d in ipairs(dashes) do
					seg.road[k].fill.Position = UDim2.fromOffset(d.x, d.y)
					seg.road[k].fill.Rotation = d.angle
				end
				for k = 1, #seg.dots do
					local dot = seg.dots[k]
					if k <= seg.count then
						local bx, by = bezier(seg, (k - 1) / (seg.count - 1))
						dot.frame.Position = UDim2.fromOffset(bx, by)
					end
				end
			end
		end
		for _, seg in ipairs(segments) do
			for k = 1, #seg.dots do
				setDot(seg, k, false)
			end
			applyRoad(seg)
		end
		for _, g in ipairs(glows) do
			local s = math.max(40, math.floor(viewH * 0.14))
			g.frame.Size = UDim2.fromOffset(s, s)
		end
		-- Decor lives in the empty bands above the highest label and below the lowest tag.
		local nodeXs = {}
		for index = 1, NODE_COUNT do
			nodeXs[index] = (nodePixel(index))
		end
		scenery.layout(canvasW, canvasH, minY - nodeSize / 2 - LABEL_GAP - 2 * 21 - 12, maxY + nodeSize / 2 + LABEL_GAP + 2 * 21 + 8 + TAG_H + 16, nodeXs, size.X)
		fogBand.layout(canvasW, canvasH)
		worldGraph.layout(canvasW, canvasH, nodeSize, nodePixel)
		worldDiscoveries.layout(canvasW, canvasH, nodeSize)
		updateFog(false)
		placeMarker()
	end
	scroll:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		layout()
	end)


	-- ===== View of the current state =====
	local function currentView()
		local state = deps.getLatestState()
		local cleared = {}
		local best = 0
		local night = 0
		local won = false
		if state then
			for _, n in ipairs(state.clearedNightIds or {}) do
				cleared[n] = true
			end
			best = state.profileStats and state.profileStats.bestNightReached or 0
			night = state.night or 0
			won = state.wonRun == true
		end
		local reached = math.max(best, night)
		return {
			state = state, cleared = cleared, reached = reached, night = night,
			inEndless = night > JourneyMap.NightCap,
			endlessOpen = cleared[JourneyMap.NightCap] == true or reached > JourneyMap.NightCap or won,
		}
	end

	-- Which node is "here" (the current Night, or the nearest milestone behind it).
	local function currentIndexFor(view)
		if not view.state then
			return nil
		end
		local night = math.max(view.night, 1)
		if night <= JourneyMap.NightCap then
			return night
		end
		local idx = ENDLESS_INDEX
		for i = ENDLESS_INDEX + 1, NODE_COUNT do
			if nodeData[i].night <= night then
				idx = i
			end
		end
		return idx
	end

	local function isNodeLocked(view, cleared, index)
		local data = nodeData[index]
		if data.kind == "endless" then
			return not view.endlessOpen
		end
		return not cleared[data.night] and data.night > view.reached
	end

	local function setPulse(node, on)
		if node.pulsing == on then
			return
		end
		node.pulsing = on
		node.halo.Visible = on
		if on then
			node.pulse:Play()
			if not calm() then
				node.pulseScale:Play()
			end
		else
			node.pulse:Cancel()
			node.pulseScale:Cancel()
		end
	end

	local function rewardOf(index)
		return nodeData[index].info.reward
	end

	local function previewText(index)
		local reward = rewardOf(index)
		if not reward then
			return ""
		end
		local def = lookups[reward.kind].getById(reward.id)
		local kind = JourneyMap.RewardKinds[reward.kind]
		return kind.noun .. ": " .. (def and (def.title or def.name) or reward.id)
	end

	-- Draws every node and segment from `cleared`. `animating` leaves
	-- the trail alone (the unlock moment animates it itself).
	local function render(view, cleared, animating)
		local currentIndex = currentIndexFor(view)
		if currentIndex ~= currentNode then
			currentNode = currentIndex
			layout(true)
		end
		local endlessSeen = cleared[JourneyMap.NightCap] == true or (not unlocking and view.endlessOpen)
		local states
		if debugOn then
			states = {}
			for i = 1, NODE_COUNT do
				states[i] = "revealed"
			end
		else
			states = JourneyMap.nodeRevealStates(revealOverride or math.max(view.night, 1), cleared, endlessSeen)
		end
		local newly = {}
		for i = 1, NODE_COUNT do
			if states[i] == "revealed" and reveal.states[i] ~= nil and reveal.states[i] ~= "revealed" then
				table.insert(newly, i)
			end
		end
		reveal.states, reveal.newly = states, newly
		do -- the drawn nodes decide the spacing: when that set changes the route is laid out again so it spans the width
			local flags, bits = {}, {}
			for i = 1, NODE_COUNT do
				local d = nodeData[i]
				flags[i] = states[i] == "revealed" or (d and d.kind ~= "endless" and nodes[i] and nodes[i].ntype == "boss") or false
				bits[i] = flags[i] and "1" or "0"
			end
			local key = table.concat(bits)
			if key ~= shownKey then
				shownKey, shownFlags = key, flags
				if frame.Visible then layout(true) end
			end
		end
		local accentHere = view.inEndless and PURPLE or Color3.fromRGB(255, 190, 90)
		for index, node in ipairs(nodes) do
			local data = node.data
			local isCleared = data.kind ~= "endless" and cleared[data.night] == true
			local locked = isNodeLocked(view, cleared, index)
			local isCurrent = currentIndex == index and not isCleared
			-- the Night's boss is the destination: always drawn (fog or not), drawn above the fog, subdued while it is far
			local shownNode = states[index] == "revealed" or (node.ntype == "boss" and data.kind ~= "endless")
			-- far locked stops stay a silhouette: no name until the stop is the current or the next one
			local farLocked = locked and not isCurrent and data.night ~= nil and data.night > math.max(view.reached, view.night, 1) + 1
			node.name.Text = farLocked and "???" or data.info.name
			node.button.Visible = shownNode
			node.name.Visible = shownNode
			node.typeTag.Visible = shownNode

			local nstate = MapNodeRules.stateOf({ completed = isCleared, locked = locked, current = isCurrent })
			local look = MapNodeRules.look(nstate, selectedIndex == index and shownNode, false)
			local ring = look.ring
			if node.ntype == "boss" and (nstate == "available" or nstate == "locked") then ring = MapNodeRules.bossRing() end -- crimson ring on the boss
			node.stroke.Color = Color3.fromRGB(ring[1], ring[2], ring[3])
			if nstate == "current" then node.stroke.Color = accentHere end
			node.stroke.Thickness = look.thickness
			node.state = nstate
			node.button.BackgroundColor3 = PARCHMENT
			node.icon.TextTransparency = locked and 0.45 or 0
			node.icon.TextStrokeTransparency = 1
			if node.art then
				node.art.ImageColor3 = Color3.fromRGB(255, 255, 255)
				node.art.ImageTransparency = locked and 0.45 or 0 -- subdued at 55 percent, never a black disc
			end
			node.fog.Visible = false
			node.lockMark.Visible = locked
			local sealReady = node.seal ~= nil and node.seal.IsLoaded
			if node.seal then
				node.seal.Visible = isCleared and sealReady
			end
			node.check.Visible = isCleared and not sealReady
			node.ribbon.BackgroundColor3 = locked and Color3.fromRGB(110, 70, 62) or RIBBON
			if node.bossBadge then
				node.bossBadge.TextTransparency = locked and 0.4 or 0
				node.bossBadge.BackgroundTransparency = locked and 0.4 or 0
			end

			node.name.TextColor3 = NAME_CREAM
			local pv = previewText(index)
			node.preview.Text = pv
			node.preview.TextColor3 = LABEL_INK -- on the parchment tag, dark ink in both states
			node.tag.Visible = false -- the reward leaves the name: it shows in the lower left panel only, so no chip sits on a label
			node.haloStroke.Color = (selectedIndex == index and not isCurrent) and Color3.fromRGB(255, 205, 90) or accentHere
			setPulse(node, (isCurrent or look.glow) and shownNode and frame.Visible)
			if not unlocking and shownNode then node.scale.Scale = isCurrent and 1.15 or 1 end -- the current stop reads about 15 percent larger
		end

		local endlessEntered = view.reached > JourneyMap.NightCap
		for index, seg in ipairs(segments) do
			local data = nodeData[index]
			local filled
			if data.kind == "endless" then
				filled = endlessEntered
			else
				filled = cleared[data.night] == true
			end
			seg.filled = filled
			seg.into = index + 1 -- the node this road leads to
			local endState = states[index + 1]
			local mode = (states[index] == "revealed" and endState == "revealed") and "full"
				or ((states[index] == "revealed" and endState == "teaser") and "fade" or "none")
			-- everything between the last revealed stop and the boss is a dimmer dashed path, so the route always reaches the destination
			if mode == "none" and data.kind ~= "endless" and nodeData[index + 1] and nodeData[index + 1].kind ~= "endless"
				and nodeData[index + 1].night and nodeData[index + 1].night <= JourneyMap.NightCap then
				mode = "dim"
			end
			seg.modeChanged = seg.mode ~= mode
			seg.mode = mode
			applyRoad(seg)
			if not animating then
				for k = 1, #seg.dots do
					setDot(seg, k, false)
				end
			end
		end
		if not unlocking then
			local idx = currentIndex
			if idx and nodes[idx] and (cleared[nodeData[idx].night or -1] == true) then
				idx = nil
			end
			markerIndex = idx
		end
		placeMarker()
		updateFog(fogAnimate)
		frame.BackgroundColor3 = view.inEndless and MAP_BG_ENDLESS or MAP_BG
	end


	-- ===== Detail card =====
	local card = Instance.new("Frame")
	card.Name = "NodeDetail"
	card.AnchorPoint = Vector2.new(1, 1) -- lower right, above the candle: the lower left is the selection panel
	card.Position = UDim2.new(1, -14, 1, -90)
	local DL = require(Engine:WaitForChild("JourneyDetailLayout")) -- one card per stop, a row of its own for every text and the buttons
	local DR = DL.rects(DL.W)
	local function at(r) return UDim2.fromOffset(r.x, r.y), UDim2.fromOffset(r.w, r.h) end
	card.Size = UDim2.new(0, DL.W, 0, DL.H)
	card.BackgroundColor3 = Color3.fromRGB(35, 26, 18)
	card.Visible = false
	card.ZIndex = 40
	card.Parent = frame
	deps.polishPanel(card, 10, "wood")
	local cardLimit = Instance.new("UISizeConstraint")
	cardLimit.MaxSize = Vector2.new(DL.W, DL.H)
	cardLimit.Parent = card

	local function cardText(props)
		props.ZIndex = 42
		return text(card, props)
	end
	local cardIcon = cardText({ Size = UDim2.fromOffset(DR.icon.w, DR.icon.h), Position = UDim2.fromOffset(DR.icon.x, DR.icon.y), TextSize = 30, TextWrapped = false })
	local cardName = cardText({ Size = UDim2.fromOffset(DR.name.w, DR.name.h), Position = UDim2.fromOffset(DR.name.x, DR.name.y), Font = Enum.Font.GothamBold,
		TextSize = 16, TextXAlignment = Enum.TextXAlignment.Left })
	local cardBoss = cardText({ Size = UDim2.fromOffset(DR.boss.w, DR.boss.h), Position = UDim2.fromOffset(DR.boss.x, DR.boss.y), TextSize = 14,
		TextColor3 = SOFT, TextXAlignment = Enum.TextXAlignment.Left })
	local cardDesc = cardText({ Size = UDim2.fromOffset(DR.desc.w, DR.desc.h), Position = UDim2.fromOffset(DR.desc.x, DR.desc.y), TextSize = 14,
		TextColor3 = SOFT, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top })
	local cardReward = cardText({ Size = UDim2.fromOffset(DR.reward.w, DR.reward.h), Position = UDim2.fromOffset(DR.reward.x, DR.reward.y), Font = Enum.Font.GothamBold,
		TextSize = 16, TextColor3 = GOLD, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top })
	local cardHow = cardText({ Size = UDim2.fromOffset(DR.how.w, DR.how.h), Position = UDim2.fromOffset(DR.how.x, DR.how.y), TextSize = 14,
		TextColor3 = SOFT, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top })

	-- Reward preview swatch (right side): card-back colors, or an icon tile.
	local swatch = Instance.new("Frame")
	swatch.AnchorPoint = Vector2.new(1, 0)
	swatch.Position = UDim2.new(0, DR.swatch.x + DR.swatch.w, 0, DR.swatch.y)
	swatch.Size = UDim2.fromOffset(DR.swatch.w, DR.swatch.h)
	swatch.ZIndex = 42
	swatch.Parent = card
	deps.roundCorner(swatch, 6)
	local swatchStroke = Instance.new("UIStroke")
	swatchStroke.Thickness = 2
	swatchStroke.Parent = swatch
	local swatchIcon = text(swatch, { Size = UDim2.fromScale(1, 1), TextSize = 24, TextWrapped = false, ZIndex = 43 })

	local equipButton = Instance.new("TextButton")
	equipButton.Position = UDim2.fromOffset(DR.equip.x, DR.equip.y) -- its own row under every text
	equipButton.Size = UDim2.fromOffset(DR.equip.w, DR.equip.h)
	equipButton.Font = Enum.Font.GothamBold
	equipButton.TextSize = 14
	equipButton.TextColor3 = CREAM
	equipButton.BackgroundColor3 = Color3.fromRGB(90, 60, 30)
	equipButton.Text = "Equip"
	equipButton.ZIndex = 43
	equipButton.Parent = card
	deps.polishButton(equipButton, 8)

	local closeCard = Instance.new("TextButton")
	closeCard.AnchorPoint = Vector2.new(1, 0)
	closeCard.Position = UDim2.new(1, -8, 0, 8)
	closeCard.Size = UDim2.fromOffset(28, 28)
	closeCard.Font = Enum.Font.GothamBold
	closeCard.TextSize = 14
	closeCard.TextColor3 = CREAM
	closeCard.BackgroundColor3 = Color3.fromRGB(70, 55, 40)
	closeCard.Text = "X"
	closeCard.ZIndex = 43
	closeCard.Parent = card
	deps.polishButton(closeCard, 8)

	local openIndex = nil

	local function equippedNow(view, reward)
		local cosmetics = view.state and view.state.cosmetics
		if reward.kind == "cardBack" then
			return cosmetics ~= nil and cosmetics.pickedCardBackId == reward.id
		elseif reward.kind == "set" then
			return cosmetics ~= nil and cosmetics.equippedSetId == reward.id
		end
		return view.state ~= nil and view.state.equippedTitleId == reward.id
	end

	local function fillCard()
		if not openIndex then
			return
		end
		local view = currentView()
		local data = nodeData[openIndex]
		local info = data.info
		local reward = info.reward
		local isEarned = data.kind ~= "endless" and view.cleared[data.night] == true
		local locked = isNodeLocked(view, view.cleared, openIndex)

		cardIcon.Text = info.icon
		cardName.Text = info.name
		cardDesc.Text = info.description
		if data.kind == "endless" then
			cardBoss.Text = "Boss III and beyond"
			cardBoss.TextColor3 = PURPLE
		elseif DL.showBossLine(nodes[openIndex] and nodes[openIndex].ntype) then
			cardBoss.Text = JourneyMap.BossTiers[JourneyMap.bossTierFor(data.night)].label -- a real boss stop only
			cardBoss.TextColor3 = SOFT
		else
			cardBoss.Text = ""
		end

		swatch.Visible = reward ~= nil
		equipButton.Visible = false
		if not reward then
			cardReward.Text = locked and "Locked: clear Night 8 to open the doors for good." or "The doors are open. Milestones wait ahead."
			cardReward.TextColor3 = locked and DIM or PURPLE
			cardHow.Text = "Endless Nights keep going. Clear Endless Night 10, 15 and 20 for rewards."
			return
		end

		cardReward.Text = JourneyMap.rewardSentence(reward, lookups, isEarned)
		cardReward.TextColor3 = isEarned and GOLD or SOFT
		cardHow.Text = (isEarned and "Unlocked: " or "How to unlock: ") .. JourneyMap.unlockText(data)

		-- Preview
		local def = lookups[reward.kind].getById(reward.id)
		local back = reward.kind == "cardBack" and def or (reward.kind == "set" and def and CardBacks.getById(def.cardBackId)) or nil
		if back then
			swatch.BackgroundColor3 = rgb(back.colors.base)
			swatchStroke.Color = rgb(back.colors.trim)
			swatchIcon.Text = back.icon
		else
			swatch.BackgroundColor3 = Color3.fromRGB(60, 46, 32)
			swatchStroke.Color = GOLD
			swatchIcon.Text = def and def.icon or JourneyMap.RewardKinds[reward.kind].icon
		end
		swatchIcon.TextTransparency = isEarned and 0 or 0.5
		swatchIcon.TextStrokeTransparency = 1

		-- Title rewards: show the Title's art when it has one (emoji otherwise).
		swatchIcon.Visible = true
		local oldArt = swatch:FindFirstChild("EntryArt")
		if oldArt then oldArt:Destroy() end
		do
			local artId = ContentArtJMV.getImageId("titles", reward.id)
			if artId then
				PatronPlaque.applyById(swatch, artId, {
					emojiLabel = swatchIcon,
					dim = not isEarned,
					zIndex = 44,
					cornerRadius = 8,
				})
			end
		end

		if isEarned then
			local equipped = equippedNow(view, reward)
			equipButton.Visible = true
			equipButton.Text = equipped and "Equipped" or "Equip"
			equipButton.Active = not equipped
			equipButton.AutoButtonColor = not equipped
			equipButton.BackgroundColor3 = equipped and Color3.fromRGB(70, 90, 60) or Color3.fromRGB(90, 60, 30)
		end
	end

	local function openCard(index)
		openIndex = index
		selectedIndex = index
		if requestRender then requestRender() end
		card.Visible = true
		if panelRef.p then panelRef.p.hide() end -- one card per stop: the lower left panel steps aside while the rewards card is open
		fillCard()
	end
	local function closeDetail()
		openIndex = nil
		card.Visible = false
		if panelRef.refresh and selectedIndex then panelRef.refresh() end -- the lower left panel returns
	end

	closeCard.MouseButton1Click:Connect(function()
		deps.playClickSfx()
		closeDetail()
	end)
	equipButton.MouseButton1Click:Connect(function()
		if not openIndex or not equipButton.Active then
			return
		end
		local data = nodeData[openIndex]
		if equipRemote and data.night then
			deps.playClickSfx()
			equipRemote:FireServer(data.night)
		end
	end)
	for index, node in ipairs(nodes) do
		node.button.MouseButton1Click:Connect(function()
			if debugOn then
				return
			end
			deps.playClickSfx()
			if openIndex == index then
				closeDetail()
			elseif selectedIndex == index then
				openCard(index) -- a second click on the selected node opens its rewards card
			else
				closeDetail()
				selectNode(index)
			end
		end)
	end

	-- ===== Studio-only coordinate tool =====
	if RunService:IsStudio() then
		local debugLabels = {}
		local function refreshDebugLabels()
			for index, node in ipairs(nodes) do
				local info = node.data.info
				if debugLabels[index] then
					debugLabels[index].Visible = debugOn
					local px, py = nodePixel(index)
					debugLabels[index].Position = UDim2.fromOffset(px, py - nodeSize / 2 - 2)
					debugLabels[index].Text = string.format("x %.2f  y %.2f", px / canvasW, py / canvasH)
				end
			end
		end
		for index, node in ipairs(nodes) do
			local label = text(canvas, {
				AnchorPoint = Vector2.new(0.5, 1), Size = UDim2.fromOffset(110, 14), TextSize = 10, TextWrapped = false, -- small: Studio-only Nudge readout
				Font = Enum.Font.Code, Text = "", Visible = false, TextColor3 = Color3.fromRGB(120, 255, 160),
				BackgroundTransparency = 0.3, BackgroundColor3 = INK, ZIndex = 50,
			})
			debugLabels[index] = label
		end

		local function printAll()
			print("-- Journey node positions (paste x, y into Engine/JourneyMap.lua):")
			for _, node in ipairs(nodes) do
				local d = node.data
				local px, py = nodePixel(_)
				print(string.format("  %s: x = %.2f, y = %.2f", d.night and ("Night " .. d.night) or "Endless doors", px / canvasW, py / canvasH))
			end
		end

		local dragging = nil
		for index, node in ipairs(nodes) do
			node.button.InputBegan:Connect(function(input)
				if not debugOn then
					return
				end
				if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
					dragging = index
					scroll.ScrollingEnabled = false
				end
			end)
		end
		UserInputService.InputChanged:Connect(function(input)
			if not dragging or input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch then
				return
			end
			local gui = frame:FindFirstAncestorOfClass("ScreenGui")
			local inset = (gui and gui.IgnoreGuiInset) and Vector2.zero or GuiService:GetGuiInset()
			local mouse = UserInputService:GetMouseLocation() - inset
			local rel = (mouse - canvas.AbsolutePosition) / canvas.AbsoluteSize
			local info = nodes[dragging].data.info
			info.x = math.clamp(math.floor(rel.X * 100 + 0.5) / 100, 0, 1)
			info.y = math.clamp(math.floor(rel.Y * 100 + 0.5) / 100, 0, 1)
			nudged[dragging] = true
			layout(true)
			refreshDebugLabels()
		end)
		UserInputService.InputEnded:Connect(function(input)
			if dragging and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
				local info = nodes[dragging].data.info
				print(string.format("Journey node %d moved to x = %.2f, y = %.2f", dragging, info.x, info.y))
				dragging = nil
				scroll.ScrollingEnabled = true
				printAll()
			end
		end)

		local nudge = Instance.new("TextButton")
		nudge.Name = "NudgeToggle"
		nudge.AnchorPoint = Vector2.new(1, 0)
		nudge.Position = UDim2.new(1, -14, 0, 72) -- under the header bar
		nudge.Visible = false -- hidden by default: press N in Studio while the map is open to show it
		nudge.Size = UDim2.fromOffset(86, 24)
		nudge.Font = Enum.Font.GothamBold
		nudge.TextSize = 11 -- small: Studio-only Nudge button
		nudge.TextColor3 = CREAM
		nudge.BackgroundColor3 = Color3.fromRGB(40, 90, 60)
		nudge.Text = "Nudge: off"
		nudge.ZIndex = 50
		nudge.Parent = frame
		deps.roundCorner(nudge, 6)
		UserInputService.InputBegan:Connect(function(input, processed)
			if not processed and input.KeyCode == Enum.KeyCode.N and frame.Visible then
				nudge.Visible = not nudge.Visible
			end
		end)
		nudge.MouseButton1Click:Connect(function()
			debugOn = not debugOn
			nudge.Text = debugOn and "Nudge: ON" or "Nudge: off"
			if debugOn then
				closeDetail()
				print("Journey nudge ON: drag nodes; coordinates print here.")
			end
			refreshDebugLabels()
			if requestRender then
				requestRender() -- Nudge reveals every node (the fog steps aside) while on
			end
		end)
	end

	-- ===== Unlock moment =====
	local seen = nil -- nights already shown as cleared (baseline from the first state)
	local playing = 0 -- token; a newer play or hide cancels older ones

	local function copySet(set)
		local out = {}
		for k, v in pairs(set) do
			out[k] = v
		end
		return out
	end

	local toast = text(frame, {
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 10), Size = UDim2.fromOffset(360, 34),
		Font = Enum.Font.GothamBold, TextSize = 14, TextColor3 = INK, BackgroundTransparency = 1,
		BackgroundColor3 = GOLD, Visible = false, ZIndex = 45, TextWrapped = true,
	})
	deps.roundCorner(toast, 8)

	-- "Find me": recentre the camera on the hero.
	local findMe = Instance.new("TextButton")
	findMe.Name = "FindMe"
	-- (below the header strip: at y 8 it sat under Roblox's own top-left buttons and could not be pressed)
	findMe.Position = UDim2.fromOffset(14, require(Engine:WaitForChild("FullScreenRules")).CONTROLS_TOP)
	findMe.Size = UDim2.fromOffset(104, 44) -- a 44 px plate (touch size), 16 px label
	findMe.Font = Enum.Font.GothamBold
	findMe.TextSize = 16
	findMe.TextColor3 = CREAM
	findMe.TextTransparency = 0
	findMe.TextStrokeTransparency = 1
	findMe.BackgroundColor3 = Color3.fromRGB(90, 60, 30)
	findMe.AutoButtonColor = true
	findMe.Text = "Find me"
	findMe.ZIndex = 46
	findMe.Parent = frame
	deps.roundCorner(findMe, 6)
	findMe.MouseButton1Click:Connect(function()
		deps.playClickSfx()
		followHero = false
		userPannedY = false
		local size = scroll.AbsoluteSize
		local cx, cy = MapPan.centerOn(marker.Position.X.Offset, marker.Position.Y.Offset, canvasW, canvasH, size.X, size.Y)
		TweenService:Create(scroll, TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
			{ CanvasPosition = Vector2.new(cx, cy) }):Play()
	end)

	-- Mouse drag-scroll (touch already drags a ScrollingFrame). Grabbing the map ends the camera follow.
	do
		local dragStart, startX, startY, dragFrom = nil, 0, 0, nil
		scroll.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 and not debugOn then
				dragStart, startX, startY = input.Position.X, scroll.CanvasPosition.X, scroll.CanvasPosition.Y
				dragFrom = input.Position.Y
				followHero = false
			end
		end)
		UserInputService.InputChanged:Connect(function(input)
			if dragStart and input.UserInputType == Enum.UserInputType.MouseMovement then
				local size = scroll.AbsoluteSize
				local nx, ny = MapPan.clamp(startX - (input.Position.X - dragStart), startY - (input.Position.Y - dragFrom),
					canvasW, canvasH, size.X, size.Y)
				if math.abs(ny - startY) > 4 then userPannedY = true end
				scroll.CanvasPosition = Vector2.new(nx, ny)
			end
		end)
		UserInputService.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				dragStart = nil
			end
		end)
	end

	local function showToast(message, token, accent)
		toast.Text = message
		toast.BackgroundColor3 = accent
		toast.BackgroundTransparency = 0
		toast.TextTransparency = 0
		toast.TextStrokeTransparency = 1
		toast.Visible = true
		local rise = calm() and 0 or 14
		toast.Position = UDim2.new(0.5, 0, 0, 72 + rise) -- under the header bar
		TweenService:Create(toast, TweenInfo.new(0.25 / pace(), Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Position = UDim2.new(0.5, 0, 0, 72) }):Play()
		task.delay(2.6 / pace(), function()
			if playing ~= token then
				return
			end
			local fade = TweenService:Create(toast, TweenInfo.new(0.35 / pace()),
				{ BackgroundTransparency = 1, TextTransparency = 1 })
			fade:Play()
			fade.Completed:Wait()
			if playing == token then
				toast.Visible = false
			end
		end)
	end

	-- ===== Selected location panel (lower left; Engine/MapSelectRules, Client/MapSelectPanel) =====
	local selectPanel = require(script.Parent.MapSelectPanel).new({
		parent = frame, PatronPlaque = PatronPlaque,
		frameArt = function() return paintArt("frame_ornate") or paintArt("frame_panel") end,
		onContinue = function() -- Continue closes the map: the run goes on from Round Select / the table (the existing launch path)
			deps.playClickSfx()
			if deps.closeMap then deps.closeMap() end
		end,
	})
	panelRef.p = selectPanel
	local RunStateEngine = require(Engine:WaitForChild("RunState"))
	local function panelDescription(index)
		local node = nodes[index]
		local data, info = node.data, node.data.info
		local target = nil
		if data.night and data.kind ~= "endless" then
			local st = deps.getLatestState()
			-- the same number the table shows: the live round's target on the current Night, the first round's on any other
			target = MapSelectRules.targetFor(data.night, st and st.night or 1, st and st.round, st and st.roundTargets, RunStateEngine.targetScoreFor)
		end
		local bossLine = nil
		if data.night and data.kind ~= "endless" then
			local st = deps.getLatestState()
			bossLine = MapSelectRules.bossLine(data.night, st and st.night or 1, st and st.bossModifier)
		end
		return MapSelectRules.describe({ name = node.name.Text, -- the chosen road's stop name when the road is picked
			description = info.description, typeId = node.ntype, state = node.state, target = target, bossLine = bossLine }),
			mapArt(info.art), info.icon
	end
	-- the panel steps down to a strip, then to a tab, when it would cover a node or label (MapSelectRules.pickMode)
	local panelShifting = false
	local function fitPanel()
		if not selectPanel.panel.Visible then return end
		local fp = frame.AbsolutePosition
		local boxes = {}
		for _, node in ipairs(nodes) do
			if node.button.Visible then
				for _, g in ipairs({ node.button, node.name, node.typeTag }) do
					local ap, sz = g.AbsolutePosition, g.AbsoluteSize
					boxes[#boxes + 1] = { x = ap.X - fp.X, y = ap.Y - fp.Y, w = sz.X, h = sz.Y }
				end
			end
		end
		local zone = selectPanel.zone()
		selectPanel.setMode(MapSelectRules.pickMode(zone, boxes))
		-- a node that would still be hidden under the full panel (the panel stepped down for it): shift the view so it stays visible
		if panelShifting or selectPanel.mode() == "full" then return end
		local full = MapSelectRules.panelRect(zone, "full")
		local sel = nodes[selectedIndex or markerIndex or 0]
		if not (sel and sel.button.Visible) then return end
		local ap, sz = sel.button.AbsolutePosition, sel.button.AbsoluteSize
		local box = { x = ap.X - fp.X, y = ap.Y - fp.Y, w = sz.X, h = sz.Y }
		if not (box.x < full.x + full.w and full.x < box.x + box.w and box.y < full.y + full.h and full.y < box.y + box.h) then return end
		local cp = scroll.CanvasPosition
		local maxY = math.max(0, scroll.CanvasSize.Y.Offset - scroll.AbsoluteSize.Y)
		local up = box.y + box.h + 12 - full.y -- scroll the canvas up by this much to lift the node over the panel
		panelShifting = true
		if cp.Y + up <= maxY then
			scroll.CanvasPosition = Vector2.new(cp.X, cp.Y + up)
		else
			scroll.CanvasPosition = Vector2.new(math.max(0, cp.X - (full.x + full.w + 12 - box.x)), cp.Y) -- else push it right of the panel
		end
		panelShifting = false
	end
	local function layoutPanel()
		-- the panel lives in the map frame kit (a sibling of the map, above every map layer, never clipped by the map frame)
		local kit = frame.Parent and frame.Parent:FindFirstChild("MapFrameKit")
		if kit and selectPanel.panel.Parent ~= kit then
			selectPanel.panel.Parent = kit
		end
		local size = frame.AbsoluteSize
		if not (size.X > 0 and size.Y > 0) then
			-- a just shown overlay can still report 0 x 0: use the screen, never leave the panel on its default spot
			local cam = workspace.CurrentCamera
			size = cam and cam.ViewportSize or size
		end
		if size.X > 0 and size.Y > 0 then selectPanel.layout(size.X, size.Y) end
		fitPanel()
	end
	local function refreshPanel()
		if openIndex then selectPanel.hide() return end -- the rewards card is open: one card per stop
		if selectedIndex and nodes[selectedIndex] then
			local desc, artId, iconText = panelDescription(selectedIndex)
			selectPanel.show(desc, artId, iconText)
			layoutPanel()
		else
			selectPanel.hide()
		end
	end
	panelRef.refresh = refreshPanel
	selectNode = function(index)
		local node = nodes[index]
		if not node then return end
		if not MapSelectRules.canSelect(node.state) then
			showToast("Locked. Clear the earlier Nights first.", playing, Color3.fromRGB(110, 70, 62))
			return
		end
		selectedIndex = index
		refreshPanel()
		if requestRender then requestRender() end
	end
	scroll:GetPropertyChangedSignal("CanvasPosition"):Connect(fitPanel)
	do -- the view always keeps the current stop (or the next one) on screen, so the camera never drifts into bare road
		local clamping = false
		scroll:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
			if clamping or debugOn or not currentNode then return end
			local cp = scroll.CanvasPosition
			local nx = MapFit.clampScroll(cp.X, scroll.AbsoluteSize.X, scroll.CanvasSize.X.Offset, posX[currentNode], posX[currentNode + 1])
			if math.abs(nx - cp.X) > 0.5 then
				clamping = true
				scroll.CanvasPosition = Vector2.new(nx, cp.Y) -- no tween, so Calm mode needs no special case
				clamping = false
				if RunService:IsStudio() then
					warn(string.format("[MapView] clamped x %d to %d, current %d at x %d", cp.X, nx, currentNode, posX[currentNode] or -1))
				end
			end
		end)
	end
	frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(layoutPanel)

	local function popNode(node)
		if calm() then
			return
		end
		node.scale.Scale = 1
		local up = TweenService:Create(node.scale, TweenInfo.new(0.18 / pace(), Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1.3 })
		up:Play()
		up.Completed:Wait()
		TweenService:Create(node.scale, TweenInfo.new(0.2 / pace()), { Scale = 1 }):Play()
	end

	-- ===== Ambient motion (candles, embers, bob, portal spin): started on show, stopped on hide =====
	local ambientToken = 0

	local function startAmbient()
		ambientToken += 1
		local my = ambientToken
		if not calm() then
			bobTween:Play()
		end
		for _, node in ipairs(nodes) do
			if node.spin then
				node.spin:Play()
			end
		end
		for _, g in ipairs(glows) do
			task.spawn(function()
				local outer = g.frame
				while ambientToken == my do
					local d = 0.1 + math.random() * 0.15
					local info = TweenInfo.new(d, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
					TweenService:Create(outer, info, { BackgroundTransparency = 0.55 + math.random() * 0.27 }):Play()
					TweenService:Create(g.scale, info, { Scale = 0.88 + math.random() * 0.25 }):Play()
					task.wait(d)
				end
			end)
		end
		for _, e in ipairs(embers) do
			task.spawn(function()
				task.wait(math.random() * 2.5)
				while ambientToken == my do
					if #FLAMES == 0 then
						task.wait(1)
					else
						local f = FLAMES[math.random(1, #FLAMES)]
						local x, y = f[1] * canvasW + math.random(-8, 8), f[2] * canvasH
						local d = 2 + math.random() * 1.5
						e.Position = UDim2.fromOffset(x, y)
						e.BackgroundTransparency = 0.1
						e.Visible = true
						TweenService:Create(e, TweenInfo.new(d, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
							Position = UDim2.fromOffset(x + math.random(-22, 22), y - math.random(60, 110)),
							BackgroundTransparency = 1,
						}):Play()
						task.wait(d)
						e.Visible = false
					end
				end
			end)
		end
	end

	local function stopAmbient()
		ambientToken += 1
		bobTween:Cancel()
		for _, node in ipairs(nodes) do
			if node.spin then
				node.spin:Cancel()
			end
		end
		for _, e in ipairs(embers) do
			e.Visible = false
		end
		sparkleLayer:ClearAllChildren()
	end

	-- ===== Trail animations =====
	-- Reveals one segment dot by dot over `duration` seconds.
	local function drawSegment(seg, duration)
		for k = 1, #seg.dots do
			if k <= seg.count then
				setDot(seg, k, true, 0.15, (k - 1) / math.max(seg.count - 1, 1) * duration)
			end
		end
	end

	-- On open: every segment fades in with a stagger; the segment into the
	-- current Night draws itself over ~1 s.
	local function introTrail(currentIndex, skipDraw)
		for i, seg in ipairs(segments) do
			if i == (currentIndex or 0) - 1 and seg.filled and not skipDraw then
				drawSegment(seg, 1)
			else
				for k = 1, seg.count do
					setDot(seg, k, true, 0.15, (i - 1) * 0.06 + k * 0.012)
				end
			end
		end
	end

	-- ===== Hero walk =====
	local WALK_SPEED = 160 -- px per second
	local hopValue -- the walk's driver value (destroyed on close)

	-- Polyline from where the hero stands at `fromIndex`, over the node, along the trail to its stand point at the next node.
	local function walkPath(fromIndex)
		local seg = segments[fromIndex]
		if not seg or seg.length < 1 then
			return nil, 0
		end
		local back = math.min((nodeSize / 2 + 34) / seg.length, 0.4)
		local sx, sy = standPoint(fromIndex)
		local pts = { { sx, sy, 0 } }
		local total = 0
		for k = 0, 24 do
			local px, py = bezier(seg, back + (1 - 2 * back) * k / 24)
			local last = pts[#pts]
			total += math.sqrt((px - last[1]) ^ 2 + (py - last[2]) ^ 2)
			pts[#pts + 1] = { px, py, total }
		end
		return pts, total
	end

	local function walkSeconds(fromIndex)
		local _, total = walkPath(fromIndex)
		return math.max(0.6, total / WALK_SPEED) / pace()
	end

	-- Steady speed with a short ease at each end: share of the distance covered at time t (0..1).
	local EASE = 0.1
	local function walkProgress(t)
		local peak = 1 / (1 - EASE)
		if t < EASE then
			return peak * t * t / (2 * EASE)
		elseif t > 1 - EASE then
			local r = 1 - t
			return 1 - peak * r * r / (2 * EASE)
		end
		return peak * (EASE / 2 + (t - EASE))
	end

	local function dustPuff(x, y)
		local d = Instance.new("Frame")
		d.AnchorPoint = Vector2.new(0.5, 0.5)
		d.Position = UDim2.fromOffset(x, y + 4)
		d.Size = UDim2.fromOffset(7, 7)
		d.BackgroundColor3 = Color3.fromRGB(214, 196, 160)
		d.BackgroundTransparency = 0.35
		d.BorderSizePixel = 0
		d.ZIndex = 32
		d.Parent = sparkleLayer
		deps.roundCorner(d, 10)
		TweenService:Create(d, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = UDim2.fromOffset(18, 18), Position = UDim2.fromOffset(x, y - 4), BackgroundTransparency = 1,
		}):Play()
		task.delay(0.5, function()
			d:Destroy()
		end)
	end

	local function settleHero()
		heroWalking = false
		hero.setWalking(false)
		bobTween:Cancel()
		bobber.Position = UDim2.fromOffset(0, 0)
		if frame.Visible and not calm() then
			bobTween:Play()
		end
	end

	-- Walks the hero from node `fromIndex` to the next one along the dotted trail. Yields until it arrives.
	local function walkHero(fromIndex, toIndex, token)
		local pts, total = walkPath(fromIndex)
		if not pts or toIndex ~= fromIndex + 1 then
			markerIndex = toIndex
			placeMarker()
			return
		end
		heroWalking = true
		marker.Visible = true
		bobTween:Cancel()
		bobber.Position = UDim2.fromOffset(0, 0)
		hero.setWalking(true)
		hero.face(1)
		local nv = Instance.new("NumberValue")
		hopValue = nv
		local lastDust = 0
		local conn = nv.Changed:Connect(function(t)
			local d = walkProgress(t) * total
			local a, b = pts[1], pts[#pts]
			for k = 2, #pts do
				if pts[k][3] >= d then
					a, b = pts[k - 1], pts[k]
					break
				end
			end
			local span = math.max(b[3] - a[3], 0.001)
			local f = math.clamp((d - a[3]) / span, 0, 1)
			local x, y = a[1] + (b[1] - a[1]) * f, a[2] + (b[2] - a[2]) * f
			marker.Position = UDim2.fromOffset(x, y + 6)
			if math.abs(b[1] - a[1]) > 0.5 then
				hero.face(b[1] > a[1] and 1 or -1)
			end
			if followHero then
				local cur = scroll.CanvasPosition.X
				scroll.CanvasPosition = Vector2.new(cur + (scrollTargetFor(x) - cur) * 0.15, scrollTargetY(y))
			end
			local now = os.clock()
			if not calm() and now - lastDust >= 0.4 then
				lastDust = now
				dustPuff(x, y)
			end
		end)
		local tween = TweenService:Create(nv, TweenInfo.new(math.max(0.6, total / WALK_SPEED) / pace(), Enum.EasingStyle.Linear), { Value = 1 })
		tween:Play()
		tween.Completed:Wait()
		conn:Disconnect()
		nv:Destroy()
		if hopValue == nv then
			hopValue = nil
		end
		if playing == token then
			markerIndex = toIndex
			hero.face(1)
			settleHero()
			placeMarker()
			if followHero then
				local x = standPoint(toIndex)
				TweenService:Create(scroll, TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
					{ CanvasPosition = Vector2.new(scrollTargetFor(x), scrollTargetY(nodeBandY)) }):Play()
			end
		end
	end

	local function sparkleBurst(cx, cy, count)
		for i = 1, count do
			local s = Instance.new("Frame")
			s.AnchorPoint = Vector2.new(0.5, 0.5)
			s.Position = UDim2.fromOffset(cx, cy)
			s.Size = UDim2.fromOffset(7, 7)
			s.Rotation = 45
			s.BackgroundColor3 = GOLD
			s.BorderSizePixel = 0
			s.ZIndex = 36
			s.Parent = sparkleLayer
			local ang = (i / count) * math.pi * 2 + math.random() * 0.3
			local dist = 40 + math.random() * 34
			TweenService:Create(s, TweenInfo.new(0.65, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Position = UDim2.fromOffset(cx + math.cos(ang) * dist, cy + math.sin(ang) * dist),
				BackgroundTransparency = 1, Size = UDim2.fromOffset(2, 2),
			}):Play()
			task.delay(0.75, function()
				s:Destroy()
			end)
		end
	end

	-- A newly revealed node fades in (labels, tag, a small pop unless Reduce Shake is on) with sparkles.
	local function fadeInRevealed(index)
		local node = nodes[index]
		if not node then
			return
		end
		local info = TweenInfo.new(0.6 / pace(), Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
		node.name.TextTransparency, node.name.TextStrokeTransparency = 1, 1
		TweenService:Create(node.name, info, { TextTransparency = 0, TextStrokeTransparency = 0.8 }):Play()
		node.preview.TextTransparency = 1
		node.typeTag.TextTransparency = 1
		TweenService:Create(node.typeTag, info, { TextTransparency = 0 }):Play()
		node.tag.BackgroundTransparency = 1
		node.tagStroke.Transparency = 1
		TweenService:Create(node.preview, info, { TextTransparency = 0 }):Play()
		TweenService:Create(node.tag, info, { BackgroundTransparency = 0 }):Play()
		TweenService:Create(node.tagStroke, info, { Transparency = 0 }):Play()
		if not calm() then
			node.scale.Scale = 0.55
			TweenService:Create(node.scale, TweenInfo.new(0.5 / pace(), Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		end
		local cx, cy = nodePixel(index)
		sparkleBurst(cx, cy, 10)
	end

	-- Gold seal stamps on: scale 1.6 to 1 with a short rotation, map shake, sparkle burst.
	local function stampSeal(node, index)
		if node.seal and node.seal.IsLoaded and node.sealScale and not calm() then
			node.sealScale.Scale = 1.6
			node.seal.Rotation = -25
			TweenService:Create(node.sealScale, TweenInfo.new(0.28 / pace(), Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
			TweenService:Create(node.seal, TweenInfo.new(0.28 / pace(), Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Rotation = 0 }):Play()
		else
			task.spawn(popNode, node)
		end
		if not calm() then
			task.spawn(function()
				local base = scroll.Position
				for _ = 1, 4 do
					scroll.Position = base + UDim2.fromOffset(math.random(-3, 3), math.random(-3, 3))
					task.wait(0.03)
				end
				scroll.Position = base
			end)
		end
		local cx, cy = nodePixel(index)
		sparkleBurst(cx, cy, 12)
		deps.playClickSfx()
	end

	-- Plays the clear moment for each night in `pendingNights` (ascending),
	-- starting from the pre-clear picture.
	local function playUnlocks(view, pendingNights)
		playing = playing + 1
		local token = playing
		unlocking = true
		local shown = copySet(view.cleared)
		for _, n in ipairs(pendingNights) do
			shown[n] = nil
		end
		-- The fog starts where it stood before the clear.
		revealOverride = pendingNights[1]
		-- The hero starts on the first node about to clear.
		for i, data in ipairs(nodeData) do
			if data.night == pendingNights[1] then
				markerIndex = i
			end
		end
		render(view, shown, false)

		task.spawn(function()
			for _, n in ipairs(pendingNights) do
				if playing ~= token then
					return
				end
				local index
				for i, data in ipairs(nodeData) do
					if data.night == n then
						index = i
					end
				end
				if not index then
					continue
				end
				task.wait(0.4 / pace())
				if playing ~= token then
					return
				end
				-- Bring the node into view.
				local target = scrollTargetFor((nodePixel(index)))
				TweenService:Create(scroll, TweenInfo.new(0.4 / pace()), { CanvasPosition = Vector2.new(target, scrollTargetY(nodeBandY)) }):Play()
				task.wait(0.35 / pace())

				-- The node clears: the hero sets off along the trail as the seal stamps on.
				shown[n] = true
				render(view, shown, true)
				local seg = segments[index]
				local walkDone = seg == nil
				if seg then
					seg.filled = true
					drawSegment(seg, walkSeconds(index))
					followHero = true
					task.spawn(function()
						walkHero(index, index + 1, token)
						walkDone = true
					end)
				end
				stampSeal(nodes[index], index)
				if seg then
					-- The fog rolls back one stop while the hero walks; the new node and trail fade in.
					revealOverride = n + 1
					fogAnimate = true
					render(view, shown, true)
					fogAnimate = false
					for _, s2 in ipairs(segments) do
						if s2 ~= seg and s2.modeChanged and s2.mode ~= "none" then
							drawSegment(s2, 0.9 / pace())
						end
					end
					for _, revealedIndex in ipairs(reveal.newly) do
						fadeInRevealed(revealedIndex)
					end
					local nextNode = nodes[index + 1]
					if nextNode and #reveal.newly == 0 then
						popNode(nextNode)
					end
				end
				while not walkDone and playing == token do
					task.wait(0.05)
				end
				followHero = false
				if playing ~= token then
					return
				end
				task.wait(0.3 / pace())

				local reward = rewardOf(index)
				if reward then
					showToast( nodeData[index].info.name .. " cleared! " .. JourneyMap.rewardLabel(reward, lookups),
						token, nodeData[index].kind == "milestone" and PURPLE or GOLD)
					task.wait(1.2 / pace())
				end
			end
			if playing == token then
				unlocking = false
				revealOverride = nil
				render(view, view.cleared, false)
			end
		end)
	end

	-- Takes the first state seen as "what the player has already looked at".
	deps.StateUpdatedRemote.OnClientEvent:Connect(function()
		task.defer(function()
			if seen == nil then
				local view = currentView()
				if view.state then
					seen = copySet(view.cleared)
				end
			end
		end)
	end)

	local function refresh()
		if unlocking then
			return
		end
		local view = currentView()
		render(view, view.cleared, false)
		worldGraph.refresh(view.state)
		worldDiscoveries.refresh(view.state)
		worldCompass.refresh(view.state)
		-- WORLD MAP: Nights whose road is already picked show the chosen stop's name and icon.
		local route = view.state and view.state.worldRoute
		if type(route) == "table" then
			for i = 1, JourneyMap.NightCap do
				local stop = WorldMapView.Stops[route[i] or ""]
				if stop and nodes[i] then
					nodes[i].name.Text = stop.name
					nodes[i].icon.Text = stop.icon or nodes[i].icon.Text
				end
			end
		end
		if openIndex then
			fillCard()
		end
		if selectedIndex then
			refreshPanel()
		end
		-- Anything cleared while the map is already open is not an "unlock moment".
		if frame.Visible and view.state then
			seen = copySet(view.cleared)
		end
	end
	requestRender = refresh

	local function applyHeader(isMapTab)
		if not isMapTab then
			return
		end
		local view = currentView()
		local done, total, percent = JourneyMap.completion(view.cleared)
		local nextNode = JourneyMap.nextReward(view.cleared)
		require(script.Parent.MapHeaderBar).setStats({ night = math.min(math.max(math.floor(view.night), 1), 8), nights = 8, done = done, total = total,
			keys = require(script.Parent.RoadLock).keys(view.state) })
		local hint
		if nextNode then
			local label = string.format("Night %d, %s, %s", nextNode.night, nextNode.info.name,
				(JourneyMap.rewardLabel(nextNode.info.reward, lookups):gsub('^Title: "(.*)"$', 'title %1'):gsub("^(%a+) (%a+): ", "%1 %2 ")))
			hint = "Next reward: " .. label
		else
			hint = "Every reward earned. Well played, Keeper!"
		end
		local progress = string.format("Journey %d of %d cleared", done, total)
		local discoveryInfo = view.state and view.state.discoveries
		if discoveryInfo then
			progress = progress .. string.format("   |   Discovered %d of %d", discoveryInfo.found, discoveryInfo.total)
		end
		local seenInfo = view.state and view.state.placesSeen
		if seenInfo and seenInfo.total > 0 then
			progress = progress .. string.format("   |   Places seen %d of %d", seenInfo.seen, seenInfo.total)
		end
		if view.inEndless then
			deps.titleLabel.Text = JourneyMap.Endless.name
			deps.titleLabel.TextColor3 = PURPLE
			deps.subtitleLabel.Text = string.format("Night %d. %s. %s", math.floor(view.night), progress, hint)
			deps.subtitleLabel.TextColor3 = rgb(JourneyMap.EndlessTheme.subtitle)
		else
			deps.titleLabel.Text = "The Tavern Map"
			deps.titleLabel.TextColor3 = CREAM
			deps.subtitleLabel.Text = progress .. "\n" .. hint
			deps.subtitleLabel.TextColor3 = Color3.fromRGB(220, 205, 185)
		end
	end

	return {
		frame = frame,
		refresh = function()
			refresh()
		end,
		setShown = function(shown)
			frame.Visible = shown
			worldGraph.setShown(shown)
			worldDiscoveries.setShown(shown)
			worldCompass.setShown(shown)
			if not shown then
				playing = playing + 1 -- cancel any unlock in progress
				unlocking = false
				revealOverride = nil
				fogAnimate = false
				toast.Visible = false
				closeDetail()
				selectedIndex = nil
				selectPanel.hide()
				for _, node in ipairs(nodes) do
					setPulse(node, false)
					-- undo any half-finished reveal fade
					node.name.TextTransparency = 0
					node.name.TextStrokeTransparency = 0.8
					node.preview.TextTransparency = 0
					node.typeTag.TextTransparency = 0
					node.typeTag.TextStrokeTransparency = 0.8
					node.tag.BackgroundTransparency, node.tagStroke.Transparency = 0, 0
					node.scale.Scale = 1
				end
				stopAmbient()
				fogBand.stopDrift()
				if hopValue then
					hopValue:Destroy()
					hopValue = nil
				end
				heroWalking = false
				followHero = false
				bobTween:Cancel()
				hero.destroy()
				marker.Visible = false
				return
			end
			layout(true)
			scenery.reportLayers() -- Studio only, once: the ZIndex of every map layer, printed to the Output window
			local view = currentView()
			local pending = {}
			if seen and view.state then
				for _, data in ipairs(nodeData) do
					if data.night and view.cleared[data.night] and not seen[data.night] then
						table.insert(pending, data.night)
					end
				end
				table.sort(pending)
			end
			if view.state then
				seen = copySet(view.cleared)
			end
			playing = playing + 1
			unlocking = false
			startAmbient()
			fogBand.startDrift()
			hero.build()
			hero.face(1)
			hero.setWalking(false)
			if #pending > 0 then
				playUnlocks(view, pending)
				introTrail(nil, true)
			else
				render(view, view.cleared, false)
				introTrail(currentIndexFor(view), false)
				-- Ease the camera to the current Night (a frame later, once the panel has its final size).
				local idx = currentIndexFor(view) or 1
				userPannedY = false
				scroll.CanvasPosition = Vector2.new(0, scrollTargetY(nodeBandY))
				local myPlay = playing
				task.defer(function()
					if not frame.Visible or playing ~= myPlay then
						return
					end
					layout()
					local target = scrollTargetFor((nodePixel(idx)))
					TweenService:Create(scroll, TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
						{ CanvasPosition = Vector2.new(target, scrollTargetY(nodeBandY)) }):Play()
				end)
			end
			-- the current Night starts selected, so the panel is never empty on open (like the reference)
			local startIdx = currentIndexFor(view)
			local states = {}
			for i, n in ipairs(nodes) do states[i] = n.state or "locked" end
			selectedIndex = MapSelectRules.openSelection(startIdx, states) -- never nil while the map has nodes
			local function openPanel(tag)
				local ok, err = xpcall(function()
					refreshPanel()
					if selectedIndex then render(view, view.cleared, false) end
				end, debug.traceback)
				if not ok then require(script.Parent.MapErrors).report("panel " .. tag, err) end
				if RunService:IsStudio() then
					local p = selectPanel.panel
					local pp, ps = p.AbsolutePosition, p.AbsoluteSize
					-- the first hidden ancestor tells what hides the panel
					local hider = "none"
					local anc = p.Parent
					while anc and anc:IsA("GuiObject") do
						if not anc.Visible then hider = anc:GetFullName() .. " Visible=false" break end
						anc = anc.Parent
					end
					-- what is drawn on top of the panel's centre (first entries are topmost): finds an occluder at once
					local top = {}
					pcall(function()
						local pg = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
						for i, g in ipairs(pg:GetGuiObjectsAtPosition(math.floor(pp.X + ps.X / 2), math.floor(pp.Y + ps.Y / 2))) do
							if i > 4 then break end
							top[#top + 1] = g.Name .. "@z" .. g.ZIndex
						end
					end)
					warn(string.format("[MapPanel] %s selected=%s visible=%s mode=%s pos %d,%d size %dx%d parent=%s z=%d hiddenBy=%s",
						tag, tostring(selectedIndex), tostring(p.Visible), selectPanel.mode(), pp.X, pp.Y, ps.X, ps.Y,
						p.Parent and p.Parent:GetFullName() or "nil", p.ZIndex, hider) .. " topAtCentre=" .. table.concat(top, ","))
				end
			end
			openPanel("open")
			-- once the layout has settled (sizes of a just-shown overlay can still be zero), make sure the panel is up and placed
			local myOpen = playing
			task.delay(0.6, function()
				if frame.Visible and playing == myOpen then
					if selectedIndex and not selectPanel.panel.Visible then openPanel("retry") else layoutPanel() end
				end
			end)
			task.delay(1, function()
				if frame.Visible and playing == myOpen then openPanel("1s") end
			end)
		end,
		applyHeader = applyHeader,
	}
end
