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
	frame.Size = UDim2.new(1, -20, 1, -124)
	frame.Position = UDim2.new(0, 10, 0, 68)
	frame.BackgroundColor3 = MAP_BG
	frame.ZIndex = 21
	frame.Visible = false
	frame.Parent = deps.parent
	deps.polishPanel(frame, 10, "parchment")

	local scroll = Instance.new("ScrollingFrame")
	scroll.Size = UDim2.new(1, -16, 1, -12)
	scroll.Position = UDim2.fromOffset(8, 6)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 8
	scroll.ScrollingDirection = Enum.ScrollingDirection.X
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
	})
	-- The rest of the branching world (other roads, fork chips, biome reward badges); see JourneyMapGraph.
	local BiomeRewardsJMV = require(Engine:WaitForChild("BiomeRewards"))
	local worldGraph = require(script.Parent.JourneyMapGraph)({
		canvas = canvas, roundCorner = deps.roundCorner, ReplicatedStorage = ReplicatedStorage, Engine = Engine,
		rewardText = function(region)
			local row = BiomeRewardsJMV.Rows[region]
			local reward = row and row.reward and row.reward[1]
			if not reward then
				return nil
			end
			return JourneyMap.rewardLabel(reward, lookups)
		end,
	})
	-- Compass icon and wheel overlay (turns the map view toward the pointed road).
	local worldCompass = require(script.Parent.JourneyMapCompass)({
		parent = frame, roundCorner = deps.roundCorner, ReplicatedStorage = ReplicatedStorage, Engine = Engine,
		graph = worldGraph,
		scrollTo = function(x)
			local maxX = math.max(0, scroll.CanvasSize.X.Offset - scroll.AbsoluteSize.X)
			TweenService:Create(scroll, TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
				{ CanvasPosition = Vector2.new(math.clamp(x - scroll.AbsoluteSize.X / 2, 0, maxX), 0) }):Play()
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

	local unlocking = false -- true while the clear moment runs (refresh leaves the picture alone)
	local requestRender -- set once refresh() exists (art that loads late re-renders)

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
	local ROAD_EDGE = Color3.fromRGB(78, 52, 28)
	local ROAD_FILL = Color3.fromRGB(240, 220, 168)
	local ROAD_STEP, ROAD_W = 8, 32
	local function makeRoadPiece(seg)
		-- Two separate canvas children so every fill sits above every edge (no dark ridges
		-- where pieces overlap): edge ZIndex 22, fill 23, dots 24.
		local edge = Instance.new("Frame")
		edge.AnchorPoint = Vector2.new(0.5, 0.5)
		edge.Size = UDim2.fromOffset(ROAD_W + 8, ROAD_W + 8)
		edge.BackgroundColor3 = ROAD_EDGE
		edge.BorderSizePixel = 0
		edge.ZIndex = 22
		edge.Parent = canvas
		deps.roundCorner(edge, (ROAD_W + 8) / 2)
		local fill = Instance.new("Frame")
		fill.AnchorPoint = Vector2.new(0.5, 0.5)
		fill.Size = UDim2.fromOffset(ROAD_W, ROAD_W)
		fill.BackgroundColor3 = ROAD_FILL
		fill.BorderSizePixel = 0
		fill.ZIndex = 23
		fill.Parent = canvas
		deps.roundCorner(fill, ROAD_W / 2)
		return { edge = edge, fill = fill }
	end
	-- Show the road with its segment: hidden in the fog, thinning out toward a teaser node.
	local function applyRoad(seg)
		if not seg.road then return end
		for k, piece in ipairs(seg.road) do
			local shown = k <= (seg.roadCount or 0) and seg.mode ~= "none"
			piece.edge.Visible = shown
			piece.fill.Visible = shown
			if shown then
				local tr = 0
				if seg.mode == "fade" then
					tr = math.min(0.95, 0.15 + 0.8 * ((k - 1) / math.max((seg.roadCount or 1) - 1, 1)))
				end
				piece.edge.BackgroundTransparency = tr
				piece.fill.BackgroundTransparency = tr
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
			TextSize = 12, Text = "👣", TextWrapped = false, ZIndex = 25, TextTransparency = 1, Visible = false,
		})
		return { frame = dot, foot = foot }
	end

	-- Visual target of a dot: cleared = solid ink (every 4th a tiny footprint), upcoming = faint.
	local function dotTargets(seg, k)
		if seg.mode == "none" then
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
		dot.frame.Visible = k <= seg.count and seg.mode ~= "none"
		dot.foot.Visible = seg.filled and seg.mode == "full" and k % 4 == 0 and k <= seg.count
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
	local nodes = {}
	local nodeSize = 84
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

		-- Emoji fallback (shown when the landmark art is missing or fails to load).
		local icon = text(button, {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.45), Size = UDim2.fromScale(0.8, 0.6),
			TextSize = 36, Text = info.icon, TextWrapped = false, ZIndex = 27,
		})
		local art
		local artId = mapArt(info.art)
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
			BackgroundColor3 = RIBBON, Text = isEndless and "∞" or tostring(data.night),
		})
		deps.roundCorner(ribbon, 5)

		local bossBadge
		if data.kind == "night" or data.kind == "milestone" then
			local tierInfo = JourneyMap.BossTiers[JourneyMap.bossTierFor(data.night)]
			bossBadge = text(button, {
				AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.9, 0.1), Size = UDim2.fromOffset(26, 26),
				TextSize = 16, TextWrapped = false, Text = tierInfo.icon, BackgroundTransparency = 0,
				BackgroundColor3 = Color3.fromRGB(110, 40, 40), ZIndex = 30,
			})
			deps.roundCorner(bossBadge, 13)
		end

		-- Cleared: gold wax seal (✓ badge when the seal art is unavailable).
		local check = text(button, {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.9, 0.86), Size = UDim2.fromOffset(26, 26),
			Font = Enum.Font.GothamBold, TextSize = 16, TextWrapped = false, Text = "✓", BackgroundTransparency = 0,
			BackgroundColor3 = GOLD, TextColor3 = INK, Visible = false, ZIndex = 31,
		})
		deps.roundCorner(check, 13)
		local seal, sealScale
		local sealId = mapArt("wax_seal_gold")
		if sealId then
			seal = Instance.new("ImageLabel")
			seal.Name = "Seal"
			seal.AnchorPoint = Vector2.new(0.5, 0.5)
			seal.Position = UDim2.fromScale(0.9, 0.86)
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
			-- Hidden images are not fetched on their own; ask for it so the ✓ fallback can swap to the seal.
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
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.9, 0.86), Size = UDim2.fromOffset(24, 24),
			Font = Enum.Font.GothamBold, TextSize = 16, TextWrapped = false, Text = "?", BackgroundTransparency = 0,
			BackgroundColor3 = PARCHMENT, TextColor3 = LABEL_INK, Visible = false, ZIndex = 31,
		})
		deps.roundCorner(lockMark, 12)

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
			TextColor3 = NAME_CREAM, TextStrokeColor3 = NAME_STROKE, TextStrokeTransparency = 0.3,
		})
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

		nodes[index] = {
			button = button, stroke = stroke, scale = scale, halo = halo, haloStroke = haloStroke, haloScale = haloScale,
			icon = icon, art = art, fog = fog, ribbon = ribbon, bossBadge = bossBadge, check = check, seal = seal,
			sealScale = sealScale, lockMark = lockMark, spin = spin, name = name, tag = tag, preview = preview,
			pulse = pulse, pulseScale = pulseScale, pulsing = false, data = data, isEndless = isEndless, tagStroke = tagStroke,
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

	-- ===== Edge fades: stepped black strips so the horizontal scroll is obvious =====
	-- (Frame transparencies only; no UIGradient transparency.)
	local FADE_STEPS = { 0.2, 0.4, 0.55, 0.7, 0.8, 0.88, 0.94, 0.98 }
	for side = 1, 2 do
		for i, tr in ipairs(FADE_STEPS) do
			local strip = Instance.new("Frame")
			strip.Name = side == 1 and "FadeLeft" or "FadeRight"
			strip.AnchorPoint = Vector2.new(side == 1 and 0 or 1, 0)
			strip.Position = UDim2.new(side == 1 and 0 or 1, side == 1 and (8 + (i - 1) * 6) or -(8 + (i - 1) * 6), 0, 6)
			strip.Size = UDim2.new(0, 6, 1, -12)
			strip.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
			strip.BackgroundTransparency = tr
			strip.BorderSizePixel = 0
			strip.Active = false
			strip.ZIndex = 36
			strip.Parent = frame
		end
	end

	-- ===== Layout: one winding trail left to right =====
	-- Nodes sit at least MIN_SPACING apart on a gentle zig-zag; even nodes ride high
	-- (label above, reward tag below), odd nodes ride low (label and tag below).
	local canvasW, canvasH = 600, 300
	local MIN_SPACING = 280
	local LEFT_PAD, RIGHT_PAD = 480, 240 -- room so the first and last node and their labels never clip; the wide left pad gives the road region some sand before Night 1
	local LABEL_MAX = 230
	local posX, posY = {}, {}
	local nudged = {} -- nodes dragged with the Studio Nudge tool keep the dragged spot
	local debugOn = false -- Studio-only coordinate overlay / drag mode (reveals everything while on)
	local reveal = { states = {}, newly = {} } -- fog state per node, set by render
	local revealOverride = nil -- Night used for the fog while the clear moment replays
	local fogAnimate = false -- true while the fog band rolls back
	local lastLayoutKey = nil
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
		return math.clamp(x - scroll.AbsoluteSize.X / 2, 0, math.max(0, canvasW - scroll.AbsoluteSize.X))
	end

	-- Where the hero's feet rest at node `index`: on the trail just before it
	-- (beside the medallion, clear of its label), or left of the first node.
	local function standPoint(index)
		local x, y = nodePixel(index)
		local back = nodeSize / 2 + 34
		local seg = segments[index - 1]
		if seg and seg.length > back * 2 and not nudged[index] and not nudged[index - 1] then
			return bezier(seg, 1 - back / seg.length)
		end
		return x - back, y
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
			return
		end
		local fx, fy = nodePixel(first)
		if states[first] == "teaser" then
			fogBand.update({ edgeX = fx, teaser = { x = fx, y = fy, size = nodeSize }, hintX = fx, hintY = fy + nodeSize * 0.75 + 20,
				animate = animate })
		else
			local px = nodePixel(first - 1)
			local edge = px + (fx - px) * 0.7
			fogBand.update({ edgeX = edge, hintX = edge + 90, hintY = canvasH * 0.5, animate = animate })
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
		canvasH = math.max(260, size.Y - 10)
		nodeSize = math.floor(math.clamp(canvasH * 0.15, 64, 92))
		canvasW = math.max(size.X * 4, LEFT_PAD + RIGHT_PAD + (NODE_COUNT - 1) * MIN_SPACING) -- five region tiles to cross
		local spacing = (canvasW - LEFT_PAD - RIGHT_PAD) / (NODE_COUNT - 1)
		canvas.Size = UDim2.fromOffset(canvasW, canvasH)
		scroll.CanvasSize = UDim2.fromOffset(canvasW, 0)
		local mid, amp = canvasH * 0.5, canvasH * 0.11
		local minY, maxY = math.huge, -math.huge
		for index = 1, NODE_COUNT do
			local wave = (index % 2 == 0) and -1 or 1
			posX[index] = LEFT_PAD + (index - 1) * spacing
			posY[index] = mid + wave * amp * (0.85 + 0.15 * math.sin(index * 1.7))
			minY, maxY = math.min(minY, posY[index]), math.max(maxY, posY[index])
		end
		local labelW = math.floor(math.clamp(spacing * 0.85, 150, LABEL_MAX))
		local LABEL_GAP, TAG_H = 10, 24
		for index, node in ipairs(nodes) do
			local x, y = nodePixel(index)
			local info = node.data.info
			node.button.Position = UDim2.fromOffset(x, y)
			node.button.Size = UDim2.fromOffset(nodeSize, nodeSize)
			node.icon.TextSize = math.floor(nodeSize * 0.45)
			local lines = math.ceil(#info.name * 9.8 / labelW)
			local labelH = lines * 21 + 2
			node.name.Size = UDim2.fromOffset(labelW, labelH)
			-- Labels always sit BELOW the node (never over its icon or the detail popup above).
			node.name.AnchorPoint = Vector2.new(0.5, 0)
			node.name.TextYAlignment = Enum.TextYAlignment.Top
			node.name.Position = UDim2.fromOffset(x, y + nodeSize / 2 + LABEL_GAP)
			node.tag.Position = UDim2.fromOffset(x, y + nodeSize / 2 + LABEL_GAP + labelH + 8)
			local nextData = nodeData[index + 1]
			if nextData then
				local nx, ny = nodePixel(index + 1)
				local seg = segments[index]
				seg.ax, seg.ay = x, y
				seg.bx, seg.by = nx, ny
				local dx, dy = seg.bx - seg.ax, seg.by - seg.ay
				seg.length = math.sqrt(dx * dx + dy * dy)
				-- Winding: control point pushed sideways, alternating per segment.
				local px, py = -dy / math.max(seg.length, 1), dx / math.max(seg.length, 1)
				seg.cx = (seg.ax + seg.bx) / 2 + px * seg.length * 0.1 * seg.sign
				seg.cy = (seg.ay + seg.by) / 2 + py * seg.length * 0.1 * seg.sign
				seg.count = math.clamp(math.floor(seg.length * 1.15 / 14), 6, 80)
				while #seg.dots < seg.count do
					table.insert(seg.dots, makeDot(seg))
				end
				seg.road = seg.road or {}
				seg.roadCount = math.max(8, math.floor(seg.length * 1.1 / ROAD_STEP))
				while #seg.road < seg.roadCount do
					table.insert(seg.road, makeRoadPiece(seg))
				end
				for k = 1, seg.roadCount do
					local rx, ry = bezier(seg, (k - 1) / (seg.roadCount - 1))
					seg.road[k].edge.Position = UDim2.fromOffset(rx, ry)
					seg.road[k].fill.Position = UDim2.fromOffset(rx, ry)
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
			local s = math.max(40, math.floor(canvasH * 0.14))
			g.frame.Size = UDim2.fromOffset(s, s)
		end
		-- Decor lives in the empty bands above the highest label and below the lowest tag.
		local nodeXs = {}
		for index = 1, NODE_COUNT do
			nodeXs[index] = (nodePixel(index))
		end
		scenery.layout(canvasW, canvasH, minY - nodeSize / 2 - LABEL_GAP - 2 * 21 - 12, maxY + nodeSize / 2 + LABEL_GAP + 2 * 21 + 8 + TAG_H + 16, nodeXs)
		fogBand.layout(canvasW, canvasH)
		worldGraph.layout(canvasW, canvasH, nodeSize, nodePixel)
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
		return kind.icon .. " " .. (def and (def.title or def.name) or reward.id)
	end

	-- Draws every node and segment from `cleared`. `animating` leaves
	-- the trail alone (the unlock moment animates it itself).
	local function render(view, cleared, animating)
		local currentIndex = currentIndexFor(view)
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
		local accentHere = view.inEndless and PURPLE or Color3.fromRGB(255, 190, 90)
		for index, node in ipairs(nodes) do
			local data = node.data
			local isCleared = data.kind ~= "endless" and cleared[data.night] == true
			local locked = isNodeLocked(view, cleared, index)
			local isCurrent = currentIndex == index and not isCleared
			local shownNode = states[index] == "revealed"
			node.button.Visible = shownNode
			node.name.Visible = shownNode

			node.stroke.Color = isCleared and GOLD_DARK or (isCurrent and accentHere) or (locked and Color3.fromRGB(110, 92, 72)) or Color3.fromRGB(90, 60, 30)
			node.stroke.Thickness = isCleared and 4 or 3
			node.button.BackgroundColor3 = PARCHMENT
			node.icon.TextTransparency = locked and 0.45 or 0
			node.icon.TextStrokeTransparency = 1
			if node.art then
				node.art.ImageColor3 = locked and Color3.fromRGB(110, 110, 110) or Color3.fromRGB(255, 255, 255)
			end
			node.fog.Visible = locked
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
			node.tag.Visible = shownNode and pv ~= ""
			node.haloStroke.Color = accentHere
			setPulse(node, isCurrent and shownNode and frame.Visible)
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
			local endState = states[index + 1]
			local mode = (states[index] == "revealed" and endState == "revealed") and "full"
				or ((states[index] == "revealed" and endState == "teaser") and "fade" or "none")
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
	card.AnchorPoint = Vector2.new(0.5, 1)
	card.Position = UDim2.new(0.5, 0, 1, -14)
	card.Size = UDim2.new(0, 400, 0, 176)
	card.BackgroundColor3 = Color3.fromRGB(35, 26, 18)
	card.Visible = false
	card.ZIndex = 40
	card.Parent = frame
	deps.polishPanel(card, 10, "wood")
	local cardLimit = Instance.new("UISizeConstraint")
	cardLimit.MaxSize = Vector2.new(400, 176)
	cardLimit.Parent = card

	local function cardText(props)
		props.ZIndex = 42
		return text(card, props)
	end
	local cardIcon = cardText({ Size = UDim2.fromOffset(40, 40), Position = UDim2.fromOffset(10, 8), TextSize = 30, TextWrapped = false })
	local cardName = cardText({ Size = UDim2.new(1, -150, 0, 22), Position = UDim2.fromOffset(54, 8), Font = Enum.Font.GothamBold,
		TextSize = 16, TextXAlignment = Enum.TextXAlignment.Left })
	local cardBoss = cardText({ Size = UDim2.new(1, -150, 0, 16), Position = UDim2.fromOffset(54, 30), TextSize = 11,
		TextColor3 = SOFT, TextXAlignment = Enum.TextXAlignment.Left })
	local cardDesc = cardText({ Size = UDim2.new(1, -20, 0, 34), Position = UDim2.fromOffset(10, 54), TextSize = 11,
		TextColor3 = SOFT, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top })
	local cardReward = cardText({ Size = UDim2.new(1, -110, 0, 18), Position = UDim2.fromOffset(10, 92), Font = Enum.Font.GothamBold,
		TextSize = 12, TextColor3 = GOLD, TextXAlignment = Enum.TextXAlignment.Left })
	local cardHow = cardText({ Size = UDim2.new(1, -110, 0, 30), Position = UDim2.fromOffset(10, 112), TextSize = 10,
		TextColor3 = SOFT, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top })

	-- Reward preview swatch (right side): card-back colors, or an icon tile.
	local swatch = Instance.new("Frame")
	swatch.AnchorPoint = Vector2.new(1, 0)
	swatch.Position = UDim2.new(1, -12, 0, 90)
	swatch.Size = UDim2.fromOffset(46, 64)
	swatch.ZIndex = 42
	swatch.Parent = card
	deps.roundCorner(swatch, 6)
	local swatchStroke = Instance.new("UIStroke")
	swatchStroke.Thickness = 2
	swatchStroke.Parent = swatch
	local swatchIcon = text(swatch, { Size = UDim2.fromScale(1, 1), TextSize = 24, TextWrapped = false, ZIndex = 43 })

	local equipButton = Instance.new("TextButton")
	equipButton.AnchorPoint = Vector2.new(1, 1)
	equipButton.Position = UDim2.new(1, -66, 1, -10)
	equipButton.Size = UDim2.fromOffset(96, 30)
	equipButton.Font = Enum.Font.GothamBold
	equipButton.TextSize = 13
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
	closeCard.Text = "✕"
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
			cardBoss.Text = "Boss ★★★ and beyond"
			cardBoss.TextColor3 = PURPLE
		else
			cardBoss.Text = JourneyMap.BossTiers[JourneyMap.bossTierFor(data.night)].icon .. " "
				.. JourneyMap.BossTiers[JourneyMap.bossTierFor(data.night)].label
			cardBoss.TextColor3 = SOFT
		end

		swatch.Visible = reward ~= nil
		equipButton.Visible = false
		if not reward then
			cardReward.Text = locked and "🔒 Clear Night 8 to open the doors for good." or "The doors are open. Milestones wait ahead."
			cardReward.TextColor3 = locked and DIM or PURPLE
			cardHow.Text = "Endless Nights keep going. Clear Endless Night 10, 15 and 20 for rewards."
			return
		end

		cardReward.Text = (isEarned and "✓ Earned: " or "🎁 Reward: ") .. JourneyMap.rewardLabel(reward, lookups)
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
			equipButton.Text = equipped and "Equipped ✓" or "Equip"
			equipButton.Active = not equipped
			equipButton.AutoButtonColor = not equipped
			equipButton.BackgroundColor3 = equipped and Color3.fromRGB(70, 90, 60) or Color3.fromRGB(90, 60, 30)
		end
	end

	local function openCard(index)
		openIndex = index
		card.Visible = true
		fillCard()
	end
	local function closeDetail()
		openIndex = nil
		card.Visible = false
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
			else
				openCard(index)
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
				AnchorPoint = Vector2.new(0.5, 1), Size = UDim2.fromOffset(110, 14), TextSize = 10, TextWrapped = false,
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
		nudge.Position = UDim2.new(1, -14, 0, 8)
		nudge.Size = UDim2.fromOffset(86, 24)
		nudge.Font = Enum.Font.GothamBold
		nudge.TextSize = 11
		nudge.TextColor3 = CREAM
		nudge.BackgroundColor3 = Color3.fromRGB(40, 90, 60)
		nudge.Text = "🛠 Nudge: off"
		nudge.ZIndex = 50
		nudge.Parent = frame
		deps.roundCorner(nudge, 6)
		nudge.MouseButton1Click:Connect(function()
			debugOn = not debugOn
			nudge.Text = debugOn and "🛠 Nudge: ON" or "🛠 Nudge: off"
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
	findMe.Position = UDim2.fromOffset(14, 8)
	findMe.Size = UDim2.fromOffset(104, 28)
	findMe.Font = Enum.Font.GothamBold
	findMe.TextSize = 14
	findMe.TextColor3 = CREAM
	findMe.TextTransparency = 0
	findMe.TextStrokeTransparency = 1
	findMe.BackgroundColor3 = Color3.fromRGB(90, 60, 30)
	findMe.AutoButtonColor = true
	findMe.Text = "📍 Find me"
	findMe.ZIndex = 46
	findMe.Parent = frame
	deps.roundCorner(findMe, 6)
	findMe.MouseButton1Click:Connect(function()
		deps.playClickSfx()
		followHero = false
		TweenService:Create(scroll, TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
			{ CanvasPosition = Vector2.new(scrollTargetFor(marker.Position.X.Offset), 0) }):Play()
	end)

	-- Mouse drag-scroll (touch already drags a ScrollingFrame). Grabbing the map ends the camera follow.
	do
		local dragStart, startX = nil, 0
		scroll.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 and not debugOn then
				dragStart, startX = input.Position.X, scroll.CanvasPosition.X
				followHero = false
			end
		end)
		UserInputService.InputChanged:Connect(function(input)
			if dragStart and input.UserInputType == Enum.UserInputType.MouseMovement then
				local maxX = math.max(0, canvasW - scroll.AbsoluteSize.X)
				scroll.CanvasPosition = Vector2.new(math.clamp(startX - (input.Position.X - dragStart), 0, maxX), 0)
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
		toast.Position = UDim2.new(0.5, 0, 0, 10 + rise)
		TweenService:Create(toast, TweenInfo.new(0.25 / pace(), Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Position = UDim2.new(0.5, 0, 0, 10) }):Play()
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
				scroll.CanvasPosition = Vector2.new(cur + (scrollTargetFor(x) - cur) * 0.15, 0)
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
					{ CanvasPosition = Vector2.new(scrollTargetFor(x), 0) }):Play()
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
		TweenService:Create(node.name, info, { TextTransparency = 0, TextStrokeTransparency = 0.3 }):Play()
		node.preview.TextTransparency = 1
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
				TweenService:Create(scroll, TweenInfo.new(0.4 / pace()), { CanvasPosition = Vector2.new(target, 0) }):Play()
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
					showToast("🎁 " .. nodeData[index].info.name .. " cleared! " .. JourneyMap.rewardLabel(reward, lookups),
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
		local hint
		if nextNode then
			local label = string.format("Night %d, %s: %s", nextNode.night, nextNode.info.name,
				JourneyMap.rewardLabel(nextNode.info.reward, lookups))
			hint = "Next reward: " .. label
		else
			hint = "Every reward earned. Well played, Keeper!"
		end
		local progress = string.format("Journey %d%% (%d/%d)", percent, done, total)
		local seenInfo = view.state and view.state.placesSeen
		if seenInfo and seenInfo.total > 0 then
			progress = progress .. string.format(". Places seen: %d of %d", seenInfo.seen, seenInfo.total)
		end
		if view.inEndless then
			deps.titleLabel.Text = "♾ " .. JourneyMap.Endless.name .. " ♾"
			deps.titleLabel.TextColor3 = PURPLE
			deps.subtitleLabel.Text = string.format("Night %d. %s. %s", math.floor(view.night), progress, hint)
			deps.subtitleLabel.TextColor3 = rgb(JourneyMap.EndlessTheme.subtitle)
		else
			deps.titleLabel.Text = "The Tavern Map"
			deps.titleLabel.TextColor3 = CREAM
			deps.subtitleLabel.Text = progress .. ". " .. hint
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
			worldCompass.setShown(shown)
			if not shown then
				playing = playing + 1 -- cancel any unlock in progress
				unlocking = false
				revealOverride = nil
				fogAnimate = false
				toast.Visible = false
				closeDetail()
				for _, node in ipairs(nodes) do
					setPulse(node, false)
					-- undo any half-finished reveal fade
					node.name.TextTransparency, node.name.TextStrokeTransparency = 0, 0.3
					node.preview.TextTransparency = 0
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
				scroll.CanvasPosition = Vector2.new(0, 0)
				local myPlay = playing
				task.defer(function()
					if not frame.Visible or playing ~= myPlay then
						return
					end
					layout()
					local target = scrollTargetFor((nodePixel(idx)))
					TweenService:Create(scroll, TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
						{ CanvasPosition = Vector2.new(target, 0) }):Play()
				end)
			end
		end,
		applyHeader = applyHeader,
	}
end
