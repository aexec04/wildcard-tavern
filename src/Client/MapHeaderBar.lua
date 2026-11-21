--[[
	Client/MapHeaderBar.lua
	The Tavern Map frame: a dark carved wood header bar with gold trim ("The Tavern Map" plate, a Night / Journey / Keys plate, the round X),
	purple crown banners at the top corners, wood edge rails and candles at the lower corners. Rects come from Engine/MapHeaderRules (tested).

	MapHeaderBar.attach(panel, onClose)  builds once per panel (idempotent), re-lays out when the panel resizes
	MapHeaderBar.setStats{ night, nights, done, total, keys }  numbers for the stats plate; safe before attach (shown on attach)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Rules = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("MapHeaderRules"))
local TavernKit = require(script.Parent.TavernKit)

local MapHeaderBar = {}

local WOOD = Color3.fromRGB(44, 30, 20)
local WOOD_LIGHT = Color3.fromRGB(70, 48, 30)
local GOLD = Color3.fromRGB(176, 138, 66)
local CREAM = Color3.fromRGB(250, 240, 220)
local PURPLE = Color3.fromRGB(92, 46, 130)

local stats = { night = 1, nights = 8, done = 0, total = 8, keys = 0 }
local view = nil -- { setStats = fn } of the attached bar

local function rect(parent, name, color, z)
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundColor3 = color
	f.BorderSizePixel = 0
	f.Active = false
	f.ZIndex = z or 40
	f.Parent = parent
	return f
end

local function place(inst, r)
	inst.Position = UDim2.fromOffset(r.x, r.y)
	inst.Size = UDim2.fromOffset(r.w, r.h)
end

local function round(inst, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = inst
end

local function trim(inst, color, thickness)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = inst
	return s
end

local function label(parent, name, z)
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBold
	l.TextColor3 = CREAM
	l.TextStrokeColor3 = Color3.fromRGB(20, 12, 6)
	l.TextStrokeTransparency = 0.6
	l.TextTransparency = 0
	l.TextWrapped = false
	l.TextScaled = false
	l.Active = false
	l.ZIndex = z
	l.Parent = parent
	return l
end

function MapHeaderBar.setStats(s)
	for k, v in pairs(s or {}) do stats[k] = v end
	if view then view.refresh() end
end

function MapHeaderBar.attach(panel, onClose)
	local old = panel:FindFirstChild("MapFrameKit")
	if old then return view end
	local kit = Instance.new("Frame")
	kit.Name = "MapFrameKit"
	kit.BackgroundTransparency = 1
	kit.Size = UDim2.fromScale(1, 1)
	kit.Active = false
	kit.ZIndex = 40 -- above every map layer (fog is 35), under popups
	kit.Parent = panel

	local rails = {}
	for _, n in ipairs({ "RailL", "RailR", "RailB" }) do
		local r = rect(kit, n, WOOD, 39)
		trim(r, GOLD, 1)
		rails[n] = r
	end
	local bar = rect(kit, "HeaderBar", WOOD, 40)
	local barLine = rect(bar, "GoldLine", GOLD, 41)
	local barSheen = rect(bar, "Sheen", WOOD_LIGHT, 40) -- a lighter wood band across the top half
	barSheen.Size = UDim2.new(1, 0, 0.45, 0)

	local titlePlate = TavernKit.plate(kit, UDim2.fromOffset(200, 40))
	titlePlate.Name = "TitlePlate"
	titlePlate.ZIndex = 41
	local titleText = label(titlePlate, "Title", 42)
	titleText.Size = UDim2.fromScale(1, 1)
	titleText.Font = Enum.Font.GothamBlack
	titleText.Text = "The Tavern Map"
	titleText.TextScaled = true
	local tCap = Instance.new("UITextSizeConstraint")
	tCap.MinTextSize = Rules.MIN_TEXT
	tCap.Parent = titleText

	local statsPlate = TavernKit.plate(kit, UDim2.fromOffset(300, 40))
	statsPlate.Name = "StatsPlate"
	statsPlate.ZIndex = 41
	local cells = {}
	for _, k in ipairs({ "night", "journey", "keys" }) do
		local cell = label(statsPlate, k, 42)
		cell.TextScaled = true
		local cap = Instance.new("UITextSizeConstraint")
		cap.MinTextSize = Rules.MIN_TEXT
		cap.Parent = cell
		cells[k] = cell
	end
	local seps = {}
	for i = 1, 2 do
		seps[i] = rect(statsPlate, "Sep" .. i, GOLD, 42)
	end

	local banners = {}
	for _, n in ipairs({ "BannerL", "BannerR" }) do
		local b = rect(kit, n, PURPLE, 41)
		trim(b, GOLD, 2)
		local crown = label(b, "Crown", 42)
		crown.Size = UDim2.new(1, 0, 0, 30)
		crown.Position = UDim2.fromOffset(0, 8)
		crown.Text = "\u{1F451}"
		crown.TextSize = 18
		banners[n] = b
	end

	local candles = {}
	for _, n in ipairs({ "CandleL", "CandleR" }) do
		local c = Instance.new("Frame")
		c.Name = n
		c.BackgroundTransparency = 1
		c.Active = false
		c.ZIndex = 41
		c.Parent = kit
		local glow = rect(c, "Glow", Color3.fromRGB(255, 180, 80), 41)
		glow.AnchorPoint = Vector2.new(0.5, 0.5)
		glow.Position = UDim2.fromScale(0.5, 0.3)
		glow.Size = UDim2.fromScale(1.1, 1.1)
		glow.BackgroundTransparency = 0.85
		round(glow, 100)
		local body = rect(c, "Body", Color3.fromRGB(240, 226, 190), 42)
		body.AnchorPoint = Vector2.new(0.5, 1)
		body.Position = UDim2.fromScale(0.5, 1)
		body.Size = UDim2.fromScale(0.34, 0.6)
		round(body, 4)
		local flame = rect(c, "Flame", Color3.fromRGB(255, 190, 70), 43)
		flame.AnchorPoint = Vector2.new(0.5, 1)
		flame.Position = UDim2.fromScale(0.5, 0.4)
		flame.Size = UDim2.fromScale(0.16, 0.26)
		round(flame, 100)
		if not TavernKit.still() then
			TweenService:Create(glow, TweenInfo.new(1.3, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { BackgroundTransparency = 0.92 }):Play()
		end
		candles[n] = c
	end

	local xHit = require(script.Parent.CloseX).attach(kit, onClose, { inset = Rules.MARGIN, top = 0, z = 44 })

	local compact = false -- narrow plate: no spaces round the slash
	local function relayout()
		local size = panel.AbsoluteSize
		local sw, sh = math.max(size.X, 320), math.max(size.Y, 240)
		local L = Rules.layout(sw, sh)
		compact = L.stats.w < 400
		place(bar, L.bar)
		barLine.Position = UDim2.new(0, 0, 1, -2)
		barLine.Size = UDim2.new(1, 0, 0, 2)
		local rail = math.max(6, math.floor(sw * 0.006))
		rails.RailL.Position, rails.RailL.Size = UDim2.fromOffset(0, L.bar.h), UDim2.new(0, rail, 1, -L.bar.h)
		rails.RailR.Position, rails.RailR.Size = UDim2.new(1, -rail, 0, L.bar.h), UDim2.new(0, rail, 1, -L.bar.h)
		rails.RailB.Position, rails.RailB.Size = UDim2.new(0, 0, 1, -rail), UDim2.new(1, 0, 0, rail)
		place(titlePlate, L.title)
		place(statsPlate, L.stats)
		titleText.TextSize = L.textSize + 2
		local px = L.stats
		for k, cell in pairs(cells) do
			local r = L.stat[k]
			cell.Position = UDim2.fromOffset(r.x - px.x, 0)
			cell.Size = UDim2.fromOffset(r.w, r.h)
			cell.TextSize = L.textSize
		end
		for i, sep in ipairs(seps) do
			sep.Position = UDim2.fromOffset(L.stat[i == 1 and "journey" or "keys"].x - px.x, 8)
			sep.Size = UDim2.fromOffset(1, px.h - 16)
		end
		place(banners.BannerL, L.bannerL)
		banners.BannerR.Visible = L.bannerR ~= nil
		if L.bannerR then place(banners.BannerR, L.bannerR) end
		place(candles.CandleL, L.candleL)
		place(candles.CandleR, L.candleR)
		xHit.Position = UDim2.new(1, -Rules.MARGIN, 0, math.max(0, L.x.y - 2))
	end

	local function refresh()
		local sl = compact and "/" or " / "
		cells.night.Text = string.format("\u{1F451} Night %d%s%d", math.floor(stats.night), sl, math.floor(stats.nights))
		cells.journey.Text = string.format("\u{1F9ED} Journey %d%s%d", math.floor(stats.done), sl, math.floor(stats.total))
		cells.keys.Text = string.format("\u{1F511} Keys %d", math.floor(stats.keys))
	end

	local function both() relayout() view.refresh() end
	panel:GetPropertyChangedSignal("AbsoluteSize"):Connect(both)
	view = { refresh = refresh, relayout = relayout, kit = kit }
	both()
	return view
end

return MapHeaderBar
