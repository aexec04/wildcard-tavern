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

	-- Painted map image (hidden until it is a real id that loads).
	local mapImage = Instance.new("ImageLabel")
	mapImage.Name = "MapImage"
	mapImage.Size = UDim2.fromScale(1, 1)
	mapImage.BackgroundTransparency = 1
	mapImage.ScaleType = Enum.ScaleType.Stretch
	mapImage.Visible = false
	mapImage.ZIndex = 22
	mapImage.Parent = canvas
	do
		local id = JourneyMap.Config.journeyMapImage
		if type(id) == "string" and id ~= "" and id ~= "rbxassetid://0" then
			mapImage.Image = id
			task.spawn(function()
				local ok = pcall(function()
					ContentProvider:PreloadAsync({ mapImage }, function(_, status)
						if status == Enum.AssetFetchStatus.Success then
							mapImage.Visible = true
						end
					end)
				end)
				if not ok then
					mapImage.Visible = false
				end
			end)
		end
	end

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
	local LABEL_STROKE = Color3.fromRGB(240, 222, 180)
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
			ax = 0, ay = 0, bx = 0, by = 0, cx = 0, cy = 0 }
	end

	local function bezier(seg, t)
		local u = 1 - t
		return u * u * seg.ax + 2 * u * t * seg.cx + t * t * seg.bx,
			u * u * seg.ay + 2 * u * t * seg.cy + t * t * seg.by
	end

	local function makeDot(seg)
		local dot = Instance.new("Frame")
		dot.AnchorPoint = Vector2.new(0.5, 0.5)
		dot.BackgroundColor3 = TRAIL_INK
		dot.BorderSizePixel = 0
		dot.ZIndex = 23
		dot.Parent = canvas
		deps.roundCorner(dot, 4)
		local foot = text(dot, {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(16, 16),
			TextSize = 12, Text = "👣", TextWrapped = false, ZIndex = 24, TextTransparency = 1, Visible = false,
		})
		return { frame = dot, foot = foot }
	end

	-- Visual target of a dot: cleared = solid ink (every 4th a tiny footprint), upcoming = faint.
	local function dotTargets(seg, k)
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
		dot.frame.Visible = k <= seg.count
		dot.foot.Visible = seg.filled and k % 4 == 0 and k <= seg.count
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
		button.Position = UDim2.fromScale(info.x, info.y)
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
			AnchorPoint = Vector2.new(0.5, 0), Size = UDim2.fromOffset(200, 22), TextWrapped = false,
			Font = Enum.Font.GothamBold, TextSize = 16, Text = info.name, ZIndex = 27,
			TextColor3 = LABEL_INK, TextStrokeColor3 = LABEL_STROKE, TextStrokeTransparency = 0.4,
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
			pulse = pulse, pulseScale = pulseScale, pulsing = false, data = data, isEndless = isEndless,
		}
	end

	for index = 1, NODE_COUNT do
		buildNode(index)
	end

	-- ===== Hero token + bobbing red X (stands on the current node) =====
	local marker = Instance.new("Frame")
	marker.Name = "HeroMarker"
	marker.AnchorPoint = Vector2.new(0.5, 1)
	marker.Size = UDim2.fromOffset(56, 76)
	marker.BackgroundTransparency = 1
	marker.Visible = false
	marker.ZIndex = 33
	marker.Parent = canvas
	local bobber = Instance.new("Frame")
	bobber.Size = UDim2.fromScale(1, 1)
	bobber.BackgroundTransparency = 1
	bobber.ZIndex = 33
	bobber.Parent = marker
	local heroHolder = Instance.new("Frame")
	heroHolder.AnchorPoint = Vector2.new(0.5, 0)
	heroHolder.Position = UDim2.fromScale(0.5, 0)
	heroHolder.Size = UDim2.fromOffset(46, 46)
	heroHolder.BackgroundColor3 = PARCHMENT
	heroHolder.ZIndex = 33
	heroHolder.Parent = bobber
	deps.roundCorner(heroHolder, 23)
	local heroEmoji = text(heroHolder, {
		Size = UDim2.fromScale(1, 1), TextSize = 28, Text = "🙂", TextWrapped = false, ZIndex = 34,
	})
	do
		local heroId = mapArt("hero_token")
		if heroId then
			PatronPlaque.applyById(heroHolder, heroId, { emojiLabel = heroEmoji, zIndex = 34, cornerRadius = 23, ring = true })
		end
	end
	text(bobber, {
		AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 1), Size = UDim2.fromOffset(34, 30),
		Font = Enum.Font.GothamBold, TextSize = 30, TextWrapped = false, Text = "X",
		TextColor3 = Color3.fromRGB(200, 40, 40), TextStrokeColor3 = LABEL_STROKE, TextStrokeTransparency = 0.4, ZIndex = 35,
	})
	local bobTween = TweenService:Create(bobber, TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Position = UDim2.fromOffset(0, -6) })

	-- ===== Candle glows, embers, sparkle layer =====
	-- Flame positions measured on art-wip/backgrounds/journey_map.png (normalized).
	local FLAMES = { { 0.04, 0.07 }, { 0.945, 0.065 }, { 0.045, 0.875 } }
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
	mapImage:GetPropertyChangedSignal("Visible"):Connect(function()
		for _, g in ipairs(glows) do
			g.frame.Visible = mapImage.Visible
		end
	end)

	local embers = {}
	for i = 1, 8 do
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

	-- ===== Layout (positions come from data; only pixels are computed here) =====
	local canvasW, canvasH = 600, 300
	local RIGHT_PAD = 80 -- room so the last node and its label are never clipped

	local function nodePixel(index)
		local info = nodeData[index].info
		return info.x * canvasW, info.y * canvasH
	end

	local function placeMarker()
		if not markerIndex or not nodes[markerIndex] then
			marker.Visible = false
			return
		end
		local x, y = nodePixel(markerIndex)
		marker.Position = UDim2.fromOffset(x, y - nodeSize / 2 + 8)
		marker.Visible = true
	end

	local function layout()
		local size = scroll.AbsoluteSize
		if size.X < 10 or size.Y < 10 then
			return
		end
		canvasH = math.max(220, size.Y - 10)
		canvasW = math.max(size.X - RIGHT_PAD, canvasH * JourneyMap.Config.mapAspect, 980)
		canvas.Size = UDim2.fromOffset(canvasW, canvasH)
		scroll.CanvasSize = UDim2.fromOffset(canvasW + RIGHT_PAD, 0)
		nodeSize = math.floor(math.clamp(canvasH * 0.22, 64, 84))
		for index, node in ipairs(nodes) do
			node.button.Size = UDim2.fromOffset(nodeSize, nodeSize)
			node.icon.TextSize = math.floor(nodeSize * 0.45)
			local info = node.data.info
			node.name.Position = UDim2.new(info.x, 0, info.y, nodeSize / 2 + 10)
			node.tag.Position = UDim2.new(info.x, 0, info.y, nodeSize / 2 + 36)
			local nextData = nodeData[index + 1]
			if nextData then
				local seg = segments[index]
				seg.ax, seg.ay = info.x * canvasW, info.y * canvasH
				seg.bx, seg.by = nextData.info.x * canvasW, nextData.info.y * canvasH
				local dx, dy = seg.bx - seg.ax, seg.by - seg.ay
				seg.length = math.sqrt(dx * dx + dy * dy)
				-- Winding: control point pushed sideways, alternating per segment.
				local nx, ny = -dy / math.max(seg.length, 1), dx / math.max(seg.length, 1)
				seg.cx = (seg.ax + seg.bx) / 2 + nx * seg.length * 0.22 * seg.sign
				seg.cy = (seg.ay + seg.by) / 2 + ny * seg.length * 0.22 * seg.sign
				seg.count = math.clamp(math.floor(seg.length * 1.15 / 14), 6, 80)
				while #seg.dots < seg.count do
					table.insert(seg.dots, makeDot(seg))
				end
				for k = 1, #seg.dots do
					local dot = seg.dots[k]
					if k <= seg.count then
						local px, py = bezier(seg, (k - 1) / (seg.count - 1))
						dot.frame.Position = UDim2.fromOffset(px, py)
					end
					dot.frame.Visible = k <= seg.count
					dot.foot.Visible = seg.filled and k % 4 == 0 and k <= seg.count
				end
			end
		end
		for _, seg in ipairs(segments) do
			for k = 1, #seg.dots do
				setDot(seg, k, false)
			end
		end
		for _, g in ipairs(glows) do
			local s = math.max(40, math.floor(canvasH * 0.14))
			g.frame.Size = UDim2.fromOffset(s, s)
		end
		placeMarker()
	end
	scroll:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)


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
		local accentHere = view.inEndless and PURPLE or Color3.fromRGB(255, 190, 90)
		for index, node in ipairs(nodes) do
			local data = node.data
			local isCleared = data.kind ~= "endless" and cleared[data.night] == true
			local locked = isNodeLocked(view, cleared, index)
			local isCurrent = currentIndex == index and not isCleared

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

			node.name.TextColor3 = locked and Color3.fromRGB(105, 85, 65) or LABEL_INK
			local pv = previewText(index)
			node.preview.Text = pv
			node.preview.TextColor3 = locked and Color3.fromRGB(105, 85, 65) or LABEL_INK
			node.tag.Visible = pv ~= ""
			node.haloStroke.Color = accentHere
			setPulse(node, isCurrent and frame.Visible)
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
	local debugOn = false -- Studio-only coordinate overlay / drag mode

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
					debugLabels[index].Text = string.format("x %.2f  y %.2f", info.x, info.y)
				end
			end
		end
		for index, node in ipairs(nodes) do
			local label = text(canvas, {
				AnchorPoint = Vector2.new(0.5, 1), Size = UDim2.fromOffset(110, 14), TextSize = 10, TextWrapped = false,
				Font = Enum.Font.Code, Text = "", Visible = false, TextColor3 = Color3.fromRGB(120, 255, 160),
				BackgroundTransparency = 0.3, BackgroundColor3 = INK, ZIndex = 50,
			})
			label.Position = UDim2.new(node.data.info.x, 0, node.data.info.y, -nodeSize / 2 - 2)
			debugLabels[index] = label
		end

		local function printAll()
			print("-- Journey node positions (paste x, y into Engine/JourneyMap.lua):")
			for _, node in ipairs(nodes) do
				local d = node.data
				print(string.format("  %s: x = %.2f, y = %.2f", d.night and ("Night " .. d.night) or "Endless doors", d.info.x, d.info.y))
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
			nodes[dragging].button.Position = UDim2.fromScale(info.x, info.y)
			debugLabels[dragging].Position = UDim2.new(info.x, 0, info.y, -nodeSize / 2 - 2)
			layout()
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
					if not mapImage.Visible then
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

	-- Hero token hops along the trail between two neighbouring nodes.
	local hopValue
	local function hopMarker(fromIndex, toIndex, duration, token)
		local seg = segments[fromIndex]
		if not seg or toIndex ~= fromIndex + 1 then
			markerIndex = toIndex
			placeMarker()
			return
		end
		hopValue = Instance.new("NumberValue")
		local nv = hopValue
		local conn = nv.Changed:Connect(function(t)
			local px, py = bezier(seg, t)
			marker.Position = UDim2.fromOffset(px, py - nodeSize / 2 + 8 - math.sin(t * math.pi) * 26)
		end)
		local tween = TweenService:Create(nv, TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { Value = 1 })
		tween:Play()
		tween.Completed:Wait()
		conn:Disconnect()
		nv:Destroy()
		if hopValue == nv then
			hopValue = nil
		end
		if playing == token then
			markerIndex = toIndex
			placeMarker()
		end
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
		for i = 1, 12 do
			local s = Instance.new("Frame")
			s.AnchorPoint = Vector2.new(0.5, 0.5)
			s.Position = UDim2.fromOffset(cx, cy)
			s.Size = UDim2.fromOffset(7, 7)
			s.Rotation = 45
			s.BackgroundColor3 = GOLD
			s.BorderSizePixel = 0
			s.ZIndex = 32
			s.Parent = sparkleLayer
			local ang = (i / 12) * math.pi * 2 + math.random() * 0.3
			local dist = 40 + math.random() * 34
			TweenService:Create(s, TweenInfo.new(0.65, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Position = UDim2.fromOffset(cx + math.cos(ang) * dist, cy + math.sin(ang) * dist),
				BackgroundTransparency = 1, Size = UDim2.fromOffset(2, 2),
			}):Play()
			task.delay(0.75, function()
				s:Destroy()
			end)
		end
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
				local target = math.clamp(nodes[index].data.info.x * canvasW - scroll.AbsoluteSize.X / 2, 0,
					math.max(0, canvasW + RIGHT_PAD - scroll.AbsoluteSize.X))
				TweenService:Create(scroll, TweenInfo.new(0.4 / pace()), { CanvasPosition = Vector2.new(target, 0) }):Play()
				task.wait(0.35 / pace())

				-- The node clears: the seal stamps on.
				shown[n] = true
				render(view, shown, true)
				stampSeal(nodes[index], index)
				task.wait(0.35 / pace())
				if playing ~= token then
					return
				end

				-- The hero hops along the trail while it draws toward the next node.
				local seg = segments[index]
				if seg then
					seg.filled = true
					drawSegment(seg, 0.8 / pace())
					hopMarker(index, index + 1, 0.8 / pace(), token)
					if playing ~= token then
						return
					end
					local nextNode = nodes[index + 1]
					if nextNode then
						popNode(nextNode)
					end
				end

				local reward = rewardOf(index)
				if reward then
					showToast("🎁 " .. nodeData[index].info.name .. " cleared! " .. JourneyMap.rewardLabel(reward, lookups),
						token, nodeData[index].kind == "milestone" and PURPLE or GOLD)
					task.wait(1.2 / pace())
				end
			end
			if playing == token then
				unlocking = false
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
			if not shown then
				playing = playing + 1 -- cancel any unlock in progress
				unlocking = false
				toast.Visible = false
				closeDetail()
				for _, node in ipairs(nodes) do
					setPulse(node, false)
				end
				stopAmbient()
				if hopValue then
					hopValue:Destroy()
					hopValue = nil
				end
				return
			end
			layout()
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
			if #pending > 0 then
				playUnlocks(view, pending)
				introTrail(nil, true)
			else
				render(view, view.cleared, false)
				introTrail(currentIndexFor(view), false)
				local idx = currentIndexFor(view) or 1
				local target = math.clamp(nodes[idx].data.info.x * canvasW - scroll.AbsoluteSize.X / 2, 0,
					math.max(0, canvasW + RIGHT_PAD - scroll.AbsoluteSize.X))
				scroll.CanvasPosition = Vector2.new(target, 0)
			end
		end,
		applyHeader = applyHeader,
	}
end
