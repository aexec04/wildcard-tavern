--[[
	Client/BossFight.lua
	Boss Rounds as a fight, visual and audio only (no scoring, target or balance changes).
	Driven entirely by the server state the hub already renders: update(state) is called from
	render() and compares the round score with the last one it saw.

	Part 1: boss presence (portrait, rim light, floor shadow, name plate with the rule), a boss HP
	bar that drains toward the Target with a lagging pale "damage" chunk, hit reactions sized by the
	hand's share of the Target (small hit = shake + red flash, big hit >= 30% = knock-back + screen
	flash + extra particles, legendary hand = stagger tag), floating damage numbers and a smirk
	on weak hands. Everything lives in one host frame at ZIndex 1 (behind the hand, above the scene
	art) and every tween is tracked so a round end or overlay change cancels cleanly.

	Layout: top centre of the table area (right of the sidebar), portrait about 28% of the screen
	height, then plate and HP bar. Normal rounds are untouched (the host stays hidden).

	deps: root, SIDEBAR_WIDTH, burst(UDim2, Color3, count, options) (ParticleBurst), screenShake(frame, strength, time)
	module: init(deps) once, get() -> { update(state), reset() }
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Engine = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine")
local ContentArt = require(Engine:WaitForChild("ContentArt"))
local ClientSettings = require(script.Parent.ClientSettings)
local PatronPlaque = require(script.Parent.PatronPlaque)

local CREAM = Color3.fromRGB(250, 235, 200)
local GOLD = Color3.fromRGB(222, 182, 104)
local WOOD = Color3.fromRGB(70, 48, 30)
local BAR_W = 340
local BIG_HIT = 0.30 -- share of the Target that counts as a big hit
local LEGENDARY = 2.2 -- same rule the hub uses for isLegendary: hand >= 2.2x Target
local SMIRK_BELOW = 0.08 -- share of the Target below which the boss "does nothing"
local ROUNDS_PER_NIGHT = 3

local function corner(inst, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = inst
	return c
end

local function build(deps)
	local root = deps.root
	local sidebarWidth = deps.SIDEBAR_WIDTH or 240
	local burst = deps.burst
	local screenShake = deps.screenShake

	local M = {}
	local tweens = {} -- every live tween, cancelled on reset
	local token = 0 -- bumps on every reset/new round so delayed callbacks bail out
	local roundKey = nil
	local lastScore = 0
	local target = 1
	local visible = false

	local function motionOk()
		return ClientSettings.get("reduceShake") ~= true
	end

	local function play(inst, props, time, style, dir)
		local t = TweenService:Create(inst, TweenInfo.new(time, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
		table.insert(tweens, t)
		t:Play()
		return t
	end

	local function later(seconds, fn)
		local mine = token
		task.delay(seconds, function()
			if token == mine then fn() end
		end)
	end

	-- ===== host =====
	local host = Instance.new("Frame")
	host.Name = "BossFightHost"
	host.AnchorPoint = Vector2.new(0.5, 0)
	host.BackgroundTransparency = 1
	host.BorderSizePixel = 0
	host.Active = false
	host.ZIndex = 0
	host.Visible = false
	host.Parent = root

	local function layout()
		local cam = workspace.CurrentCamera
		local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
		local h = math.floor(vp.Y * 0.28)
		local areaW = vp.X - sidebarWidth
		host.Position = UDim2.new(0, sidebarWidth + areaW / 2, 0, math.floor(vp.Y * 0.02))
		host.Size = UDim2.new(0, 360, 0, h + 96)
		M.portraitSize = h
		if M.portraitHolder then
			M.portraitHolder.Size = UDim2.new(0, h, 0, h)
		end
	end

	local portraitSize = 200
	do
		local cam = workspace.CurrentCamera
		local vpY = cam and cam.ViewportSize.Y or 720
		portraitSize = math.floor(vpY * 0.28)
	end

	-- floor shadow
	local shadow = Instance.new("Frame")
	shadow.Name = "FloorShadow"
	shadow.AnchorPoint = Vector2.new(0.5, 0)
	shadow.BackgroundColor3 = Color3.new(0, 0, 0)
	shadow.BackgroundTransparency = 0.55
	shadow.BorderSizePixel = 0
	shadow.Active = false
	shadow.ZIndex = 0
	shadow.Parent = host
	corner(shadow, 100)

	-- portrait holder (what shakes / scales / tilts)
	local holder = Instance.new("Frame")
	holder.Name = "BossPortrait"
	holder.AnchorPoint = Vector2.new(0.5, 0)
	holder.Position = UDim2.new(0.5, 0, 0, 0)
	holder.Size = UDim2.new(0, portraitSize, 0, portraitSize)
	holder.BackgroundColor3 = Color3.fromRGB(30, 22, 16)
	holder.BackgroundTransparency = 0.25
	holder.BorderSizePixel = 0
	holder.Active = false
	holder.ZIndex = 0
	holder.Parent = host
	corner(holder, 16)
	M.portraitHolder = holder
	local rim = Instance.new("UIStroke") -- soft rim light
	rim.Color = GOLD
	rim.Thickness = 3
	rim.Transparency = 0.25
	rim.Parent = holder
	local pscale = Instance.new("UIScale")
	pscale.Parent = holder

	local art -- ImageLabel or emoji TextLabel, rebuilt per boss
	local tint = Instance.new("Frame") -- red hit flash over the portrait
	tint.Name = "HitTint"
	tint.Size = UDim2.fromScale(1, 1)
	tint.BackgroundColor3 = Color3.fromRGB(220, 40, 30)
	tint.BackgroundTransparency = 1
	tint.BorderSizePixel = 0
	tint.Active = false
	tint.ZIndex = 0
	tint.Parent = holder
	corner(tint, 16)

	-- name plate
	local plate = Instance.new("Frame")
	plate.Name = "NamePlate"
	plate.AnchorPoint = Vector2.new(0.5, 0)
	plate.BackgroundColor3 = WOOD
	plate.BorderSizePixel = 0
	plate.Size = UDim2.new(0, BAR_W, 0, 50)
	plate.Active = false
	plate.ZIndex = 0
	plate.Parent = host
	corner(plate, 8)
	local plateStroke = Instance.new("UIStroke")
	plateStroke.Color = GOLD
	plateStroke.Thickness = 2
	plateStroke.Parent = plate
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, -12, 0, 24)
	nameLabel.Position = UDim2.new(0, 6, 0, 2)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 18
	nameLabel.TextColor3 = CREAM
	nameLabel.TextStrokeTransparency = 0.3
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.ZIndex = 0
	nameLabel.Parent = plate
	local ruleLabel = Instance.new("TextLabel")
	ruleLabel.Size = UDim2.new(1, -12, 0, 22)
	ruleLabel.Position = UDim2.new(0, 6, 0, 26)
	ruleLabel.BackgroundTransparency = 1
	ruleLabel.Font = Enum.Font.Gotham
	ruleLabel.TextSize = 15
	ruleLabel.TextColor3 = Color3.fromRGB(235, 215, 175)
	ruleLabel.TextStrokeTransparency = 0.4
	ruleLabel.TextTruncate = Enum.TextTruncate.AtEnd
	ruleLabel.ZIndex = 0
	ruleLabel.Parent = plate

	-- HP bar
	local bar = Instance.new("Frame")
	bar.Name = "BossHpBar"
	bar.AnchorPoint = Vector2.new(0.5, 0)
	bar.Size = UDim2.new(0, BAR_W, 0, 26)
	bar.BackgroundColor3 = Color3.fromRGB(34, 22, 18)
	bar.BorderSizePixel = 0
	bar.Active = false
	bar.ZIndex = 0
	bar.Parent = host
	corner(bar, 8)
	local barStroke = Instance.new("UIStroke")
	barStroke.Color = GOLD
	barStroke.Thickness = 2
	barStroke.Parent = bar
	local trackX, trackW = 30, BAR_W - 30 - 86 -- icon on the left, number on the right
	local track = Instance.new("Frame")
	track.Name = "Track"
	track.Position = UDim2.new(0, trackX, 0, 5)
	track.Size = UDim2.new(0, trackW, 0, 16)
	track.BackgroundColor3 = Color3.fromRGB(18, 12, 10)
	track.BorderSizePixel = 0
	track.ClipsDescendants = true
	track.Active = false
	track.ZIndex = 0
	track.Parent = bar
	corner(track, 5)
	local chunk = Instance.new("Frame") -- pale lagging "damage" chunk
	chunk.Name = "DamageChunk"
	chunk.Size = UDim2.new(1, 0, 1, 0)
	chunk.BackgroundColor3 = Color3.fromRGB(255, 230, 200)
	chunk.BorderSizePixel = 0
	chunk.Active = false
	chunk.ZIndex = 0
	chunk.Parent = track
	local fillClip = Instance.new("Frame") -- shrinks; the gradient frame inside keeps its full width
	fillClip.Name = "FillClip"
	fillClip.Size = UDim2.new(1, 0, 1, 0)
	fillClip.BackgroundTransparency = 1
	fillClip.BorderSizePixel = 0
	fillClip.ClipsDescendants = true
	fillClip.Active = false
	fillClip.ZIndex = 0
	fillClip.Parent = track
	local fill = Instance.new("Frame")
	fill.Size = UDim2.new(0, trackW, 1, 0)
	fill.BackgroundColor3 = Color3.new(1, 1, 1)
	fill.BorderSizePixel = 0
	fill.Active = false
	fill.ZIndex = 0
	fill.Parent = fillClip
	local grad = Instance.new("UIGradient") -- Color stops only, never Transparency
	grad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(200, 50, 40)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(235, 190, 70)),
	})
	grad.Parent = fill
	local icon = Instance.new("TextLabel")
	icon.Size = UDim2.new(0, 26, 1, 0)
	icon.Position = UDim2.new(0, 3, 0, 0)
	icon.BackgroundTransparency = 1
	icon.Font = Enum.Font.GothamBold
	icon.TextSize = 18
	icon.Text = "💀"
	icon.TextColor3 = CREAM
	icon.ZIndex = 0
	icon.Parent = bar
	local hpText = Instance.new("TextLabel")
	hpText.Size = UDim2.new(0, 80, 1, 0)
	hpText.Position = UDim2.new(1, -84, 0, 0)
	hpText.BackgroundTransparency = 1
	hpText.Font = Enum.Font.GothamBold
	hpText.TextSize = 16
	hpText.TextXAlignment = Enum.TextXAlignment.Right
	hpText.TextColor3 = CREAM
	hpText.TextStrokeTransparency = 0.4
	hpText.Text = ""
	hpText.ZIndex = 0
	hpText.Parent = bar

	local function arrange()
		layout()
		local h = holder.Size.Y.Offset
		shadow.Position = UDim2.new(0.5, 0, 0, h - 8)
		shadow.Size = UDim2.new(0, math.floor(h * 0.8), 0, 16)
		plate.Position = UDim2.new(0.5, 0, 0, h + 8)
		bar.Position = UDim2.new(0.5, 0, 0, h + 8 + 50 + 6)
		host.Size = UDim2.new(0, 360, 0, h + 8 + 50 + 6 + 26)
	end
	arrange()
	do
		local cam = workspace.CurrentCamera
		if cam then
			cam:GetPropertyChangedSignal("ViewportSize"):Connect(arrange)
		end
	end

	-- ===== effects =====
	local function setHp(fraction, instant)
		fraction = math.clamp(fraction, 0, 1)
		if instant then
			fillClip.Size = UDim2.new(fraction, 0, 1, 0)
			chunk.Size = UDim2.new(fraction, 0, 1, 0)
		else
			play(fillClip, { Size = UDim2.new(fraction, 0, 1, 0) }, 0.15)
			later(0.55, function()
				play(chunk, { Size = UDim2.new(fraction, 0, 1, 0) }, 0.45)
			end)
		end
		hpText.Text = string.format("%d", math.floor(fraction * target + 0.5))
	end

	local function popText(text, color, size, offsetY)
		local label = Instance.new("TextLabel")
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.Position = UDim2.new(0.5, 0, 0, (offsetY or 0.5) * holder.Size.Y.Offset)
		label.Size = UDim2.new(0, 200, 0, size + 8)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamBlack
		label.TextSize = size
		label.TextColor3 = color
		label.TextStrokeColor3 = Color3.new(0, 0, 0)
		label.TextStrokeTransparency = 0.2
		label.Text = text
		label.ZIndex = 5
		label.Parent = host
		play(label, { Position = label.Position - UDim2.new(0, 0, 0, 40), TextTransparency = 1, TextStrokeTransparency = 1 }, 0.9)
		later(1, function() label:Destroy() end)
		return label
	end

	local function shake(strength, count)
		if not motionOk() then return end
		local base = UDim2.new(0.5, 0, 0, 0)
		for i = 1, count do
			later(i * 0.04, function()
				local dx = (i % 2 == 0 and -1 or 1) * strength
				play(holder, { Position = base + UDim2.new(0, dx, 0, 0) }, 0.04)
			end)
		end
		later(count * 0.04 + 0.04, function()
			play(holder, { Position = base }, 0.06)
		end)
	end

	local function flashTint(strength)
		tint.BackgroundTransparency = 1 - strength
		play(tint, { BackgroundTransparency = 1 }, 0.35)
	end

	local function screenFlash()
		local f = Instance.new("Frame")
		f.Size = UDim2.fromScale(1, 1)
		f.BackgroundColor3 = Color3.fromRGB(255, 240, 210)
		f.BackgroundTransparency = 0.75
		f.BorderSizePixel = 0
		f.Active = false
		f.ZIndex = 34
		f.Parent = root
		play(f, { BackgroundTransparency = 1 }, 0.25)
		later(0.3, function() f:Destroy() end)
	end

	local function particles(count, color)
		if not burst then return end
		local pos = holder.AbsolutePosition + holder.AbsoluteSize / 2
		pcall(burst, UDim2.fromOffset(pos.X, pos.Y), color, count, { size = 8, spread = 120 })
	end

	local function react(delta, legendary)
		local share = delta / math.max(target, 1)
		popText(string.format("-%d", math.floor(delta + 0.5)), legendary and GOLD or Color3.fromRGB(255, 120, 90), 26 + math.floor(math.min(share, 1) * 14), 0.2)
		if legendary then
			flashTint(0.6)
			screenFlash()
			particles(26, GOLD)
			popText("STAGGERED!", GOLD, 24, 0.55)
			if motionOk() then
				play(holder, { Rotation = -10 }, 0.15)
				later(0.9, function() play(holder, { Rotation = 0 }, 0.3, Enum.EasingStyle.Back) end)
				play(pscale, { Scale = 0.9 }, 0.15)
				later(0.9, function() play(pscale, { Scale = 1 }, 0.3, Enum.EasingStyle.Back) end)
			end
			if screenShake then pcall(screenShake, root, 6, 0.25) end
		elseif share >= BIG_HIT then
			flashTint(0.5)
			screenFlash()
			particles(18, Color3.fromRGB(255, 170, 80))
			if motionOk() then
				-- knock-back: shove up and back, then spring home
				play(pscale, { Scale = 0.94 }, 0.1)
				play(holder, { Position = UDim2.new(0.5, 0, 0, -12) }, 0.1)
				later(0.12, function()
					play(pscale, { Scale = 1 }, 0.3, Enum.EasingStyle.Back)
					play(holder, { Position = UDim2.new(0.5, 0, 0, 0) }, 0.3, Enum.EasingStyle.Back)
				end)
			end
			if screenShake then pcall(screenShake, root, 4, 0.2) end
		elseif share < SMIRK_BELOW then
			-- quiet beat: the boss shrugs it off
			popText("...", CREAM, 20, 0.8)
			if motionOk() then
				play(pscale, { Scale = 1.04 }, 0.2)
				later(0.5, function() play(pscale, { Scale = 1 }, 0.3) end)
			end
		else
			flashTint(0.4)
			particles(8, Color3.fromRGB(255, 130, 100))
			shake(5, 4)
		end
	end

	-- ===== idle: breathe + sway while the host is up =====
	local idleTweens = {}
	local function stopIdle()
		for _, t in ipairs(idleTweens) do t:Cancel() end
		idleTweens = {}
	end
	local function startIdle()
		stopIdle()
		if not motionOk() then return end
		local info = TweenInfo.new(1.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
		local sway = TweenService:Create(rim, TweenInfo.new(1.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Thickness = 5 })
		sway:Play()
		table.insert(idleTweens, sway)
		local breathe = TweenService:Create(shadow, info, { BackgroundTransparency = 0.7 })
		breathe:Play()
		table.insert(idleTweens, breathe)
	end

	local function setArt(boss)
		if art then art:Destroy() art = nil end
		local artId = boss and ContentArt.getImageId("boss_rounds", boss.id) or nil
		if artId then
			art = PatronPlaque.applyById(holder, artId, {
				size = UDim2.fromScale(1, 1), anchor = Vector2.new(0, 0), position = UDim2.fromScale(0, 0),
				zIndex = 0, cornerRadius = 16,
			})
		end
		if not art then
			art = Instance.new("TextLabel")
			art.Size = UDim2.fromScale(1, 1)
			art.BackgroundTransparency = 1
			art.Font = Enum.Font.GothamBold
			art.TextScaled = true
			art.Text = "👑"
			art.TextColor3 = CREAM
			art.ZIndex = 0
			art.Parent = holder
		end
		tint.Parent = nil
		tint.Parent = holder -- keep the flash above the art
	end

	local function hide()
		token = token + 1
		for _, t in ipairs(tweens) do t:Cancel() end
		tweens = {}
		stopIdle()
		for _, child in ipairs(host:GetChildren()) do
			if child:IsA("TextLabel") and child.ZIndex == 5 then child:Destroy() end
		end
		holder.Rotation = 0
		holder.Position = UDim2.new(0.5, 0, 0, 0)
		pscale.Scale = 1
		tint.BackgroundTransparency = 1
		host.Visible = false
		visible = false
	end

	-- ===== public =====
	function M.reset()
		hide()
		roundKey = nil
	end

	function M.update(state)
		if type(state) ~= "table" then return end
		local boss = state.bossModifier
		local inFight = state.phase == "playing" and boss ~= nil
			and (state.round or 0) >= ROUNDS_PER_NIGHT
		if not inFight then
			if visible then hide() end
			roundKey = nil
			return
		end

		local key = tostring(state.night) .. "-" .. tostring(state.round) .. "-" .. tostring(boss.id)
		target = math.max(state.targetScore or 1, 1)
		local score = state.roundScore or 0
		if key ~= roundKey then
			roundKey = key
			hide() -- fresh token, clean state
			layout()
			arrange()
			setArt(boss)
			nameLabel.Text = boss.name or ""
			ruleLabel.Text = boss.description or ""
			lastScore = score
			setHp(1 - score / target, true)
			host.Visible = true
			visible = true
			startIdle()
			-- entrance: pop in
			pscale.Scale = 0.85
			play(pscale, { Scale = 1 }, 0.35, Enum.EasingStyle.Back)
			return
		end

		if score > lastScore then
			local delta = score - lastScore
			lastScore = score
			setHp(1 - score / target, false)
			react(delta, delta >= LEGENDARY * target)
		elseif score < lastScore then
			lastScore = score
			setHp(1 - score / target, true)
		end
	end

	return M
end

local instance = nil
return {
	init = function(deps)
		instance = build(deps)
		return instance
	end,
	get = function()
		return instance
	end,
}
