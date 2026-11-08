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

	Part 2 (text, motion and audio only): taunts in a parchment speech bubble (Engine/BossLines,
	deterministic from the run/daily/seed code, one at a time, rate limited), an attack beat each
	time a hand is played under a rule that acts on the table (lunge, dark band flash over the hand
	area, thump, tiny shake, strength by rule category), enrage at 50% of the Target (red or, for
	grand bosses, gold flush, bar flash and shake, ENRAGED! banner, slow vignette pulse, music about
	7% faster, faster idle), defeat (desaturate, tilt and slide, DEFEATED stamp, gold particles,
	fanfare, at most 1.5s and it never delays the reward flow) and a victory laugh on a loss. The
	final Night boss and Endless milestone bosses (BossLines.isGrand) get a larger portrait, a
	longer intro line and gold enrage colours. Fast speed skips the long beats; Reduce shake skips
	motion.

	deps: root, SIDEBAR_WIDTH, burst(UDim2, Color3, count, options) (ParticleBurst), screenShake(frame, strength, time),
	      playThump(), playFanfare(), music (the Sound instance, optional)
	module: init(deps) once, get() -> { update(state), reset() }
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Engine = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine")
local StageMotion = require(Engine:WaitForChild("StageMotion"))
local ContentArt = require(Engine:WaitForChild("ContentArt"))
local ClientSettings = require(script.Parent.ClientSettings)
local PatronPlaque = require(script.Parent.PatronPlaque)
local BossRounds = require(Engine:WaitForChild("BossRounds"))
local BossLines = require(Engine:WaitForChild("BossLines"))
local JourneyMap = require(Engine:WaitForChild("JourneyMap"))

local ENRAGE_RED = Color3.fromRGB(220, 40, 30)
local ENRAGE_GOLD = Color3.fromRGB(235, 180, 40)
local BUBBLE_GAP = 3.5 -- seconds between taunts (intro and the ending lines ignore it)
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
	local playThump = deps.playThump
	local playFanfare = deps.playFanfare
	local music = deps.music

	local M = {}
	-- per-fight flags (reset in begin())
	local grand, enraged, halfDone, lowDone = false, false, false, false
	local lastHands, lastTips = nil, nil
	local category, bossDef, seedText = nil, nil, "0"
	local retiring = false
	local lastBubble = -100
	local musicBase = nil
	local tintBase = 1 -- resting transparency of the portrait tint (lower while enraged / defeated)
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

	-- Live characters (Client/CharacterStage.lua): the same events drive the boss and player rigs.
	-- Visual only; any failure there leaves this portrait in charge.
	local function stageEvent(who, name, strength)
		pcall(function()
			local stage = require(script.Parent.CharacterStage).get()
			if not stage then return end
			if who == "boss" then
				stage.playBossState(name, strength)
			else
				stage.playPlayerState(name)
			end
		end)
	end
	local function stageActive()
		local okStage, active = pcall(function()
			local stage = require(script.Parent.CharacterStage).get()
			return stage ~= nil and stage.isActive()
		end)
		return okStage and active == true
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
		-- Cap so plaque + HP bar end by ~34% (38% grand) of the screen height: the
		-- played-cards row and score popup below must stay clear of them (1280x720).
		local h = math.floor(math.min(vp.Y * (grand and 0.34 or 0.28), vp.Y * (grand and 0.38 or 0.34) - 98))
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
		tint.BackgroundTransparency = math.min(tintBase, 1 - strength)
		play(tint, { BackgroundTransparency = tintBase }, 0.35)
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
			stageEvent("boss", "stagger", 1)
			stageEvent("player", "cheer")
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
			stageEvent("boss", "hit", math.min(1, share * 2))
			stageEvent("player", "cheer")
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
			stageEvent("boss", "taunt", 0.3)
			popText("...", CREAM, 20, 0.8)
			if motionOk() then
				play(pscale, { Scale = 1.04 }, 0.2)
				later(0.5, function() play(pscale, { Scale = 1 }, 0.3) end)
			end
		else
			stageEvent("boss", "hit", math.min(1, share * 3))
			flashTint(0.4)
			particles(8, Color3.fromRGB(255, 130, 100))
			shake(5, 4)
		end
	end

	-- ===== idle: breathe + sway while the host is up =====
	local idleTweens = {}
	local swayConn = nil
	local function stopIdle()
		for _, t in ipairs(idleTweens) do t:Cancel() end
		idleTweens = {}
		if swayConn then
			swayConn:Disconnect()
			swayConn = nil
		end
		if art then
			art.Position = UDim2.fromScale(0, 0) -- (the emoji fallback also sits at 0,0)
			art.Rotation = 0
		end
	end
	local function startIdle(period)
		stopIdle()
		if not motionOk() then return end
		period = period or 1.5
		-- One continuous sine (sub-pixel) on the portrait art: breathing + a slight lean. Hit shakes tween
		-- the holder, so the two never fight. Faster while enraged. Disconnected by stopIdle / hide.
		local speed = 1.5 / period
		local phase = grand and 0.4 or 0
		swayConn = RunService.RenderStepped:Connect(function()
			if not (art and host.Visible) then return end
			local dx, dy, rot = StageMotion.sway(os.clock() * speed, phase, grand and 3.5 or 2.5)
			art.Position = UDim2.new(0, dx, 0, dy)
			art.Rotation = rot
		end)
		local info = TweenInfo.new(period, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
		local sway = TweenService:Create(rim, TweenInfo.new(period, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Thickness = 5 })
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

	-- ===== part 2: taunts, attacks, enrage, defeat =====
	local hide -- forward declaration (defeat / loss end by calling it)

	local function fast()
		return ClientSettings.get("animSpeed") == "fast"
	end

	-- parchment speech bubble, left of the portrait (the right side is the corner icon row)
	local bubble = Instance.new("Frame")
	bubble.Name = "BossBubble"
	bubble.AnchorPoint = Vector2.new(1, 0)
	bubble.Size = UDim2.new(0, 210, 0, 62)
	bubble.BackgroundColor3 = Color3.fromRGB(232, 212, 168)
	bubble.BorderSizePixel = 0
	bubble.Active = false
	bubble.Visible = false
	bubble.ZIndex = 5
	bubble.Parent = host
	corner(bubble, 10)
	local bubbleStroke = Instance.new("UIStroke")
	bubbleStroke.Color = Color3.fromRGB(110, 78, 46)
	bubbleStroke.Thickness = 2
	bubbleStroke.Parent = bubble
	local bubbleScale = Instance.new("UIScale")
	bubbleScale.Parent = bubble
	local bubbleText = Instance.new("TextLabel")
	bubbleText.Size = UDim2.new(1, -16, 1, -8)
	bubbleText.Position = UDim2.new(0, 8, 0, 4)
	bubbleText.BackgroundTransparency = 1
	bubbleText.Font = Enum.Font.GothamMedium
	bubbleText.TextSize = 16
	bubbleText.TextColor3 = Color3.fromRGB(60, 40, 22)
	bubbleText.TextStrokeTransparency = 1
	bubbleText.TextWrapped = true
	bubbleText.ZIndex = 6
	bubbleText.Parent = bubble
	local bubbleToken = 0

	local function say(event, force)
		if not bossDef or not visible then return end
		local now = os.clock()
		if not force and now - lastBubble < BUBBLE_GAP then return end
		local line = BossLines.pick(bossDef.id, category, event, seedText)
		if not line then return end
		lastBubble = now
		bubbleToken = bubbleToken + 1
		local mine = bubbleToken
		local h = holder.Size.Y.Offset
		bubble.Position = UDim2.new(0.5, -(h / 2) - 8, 0, 10)
		bubbleText.Text = line
		bubbleText.TextTransparency = 0
		bubbleText.TextStrokeTransparency = 1
		bubble.BackgroundTransparency = 0
		bubbleStroke.Transparency = 0
		bubble.Visible = true
		if motionOk() and not fast() then
			bubbleScale.Scale = 0.6
			play(bubbleScale, { Scale = 1 }, 0.2, Enum.EasingStyle.Back)
		else
			bubbleScale.Scale = 1
		end
		local hold = (grand and event == "intro") and 4 or 2.5
		task.delay(hold, function()
			if bubbleToken ~= mine then return end
			play(bubble, { BackgroundTransparency = 1 }, 0.3)
			play(bubbleText, { TextTransparency = 1 }, 0.3)
			play(bubbleStroke, { Transparency = 1 }, 0.3)
			task.delay(0.35, function()
				if bubbleToken == mine then bubble.Visible = false end
			end)
		end)
	end

	-- dark flash across the hand area (stands in for per-card "sealed" overlays)
	local band = Instance.new("Frame")
	band.Name = "BossAttackBand"
	band.AnchorPoint = Vector2.new(0, 1)
	band.Position = UDim2.fromScale(0, 1)
	band.Size = UDim2.fromScale(1, 0.4)
	band.BackgroundColor3 = Color3.new(0, 0, 0)
	band.BackgroundTransparency = 1
	band.BorderSizePixel = 0
	band.Active = false
	band.ZIndex = 33
	band.Parent = root

	-- slow screen vignette pulse while enraged (a light full-screen tint, never blocks input)
	local rageFx = Instance.new("Frame")
	rageFx.Name = "BossRageTint"
	rageFx.Size = UDim2.fromScale(1, 1)
	rageFx.BackgroundColor3 = ENRAGE_RED
	rageFx.BackgroundTransparency = 1
	rageFx.BorderSizePixel = 0
	rageFx.Active = false
	rageFx.ZIndex = 32
	rageFx.Parent = root

	local banner = Instance.new("TextLabel")
	banner.Name = "BossEnrageBanner"
	banner.AnchorPoint = Vector2.new(0.5, 0.5)
	banner.Position = UDim2.fromScale(0.5, 0.3) -- re-aimed at the portrait on enrage
	banner.Size = UDim2.new(0, 460, 0, 70)
	banner.BackgroundTransparency = 1
	banner.Font = Enum.Font.GothamBlack
	banner.TextSize = 44
	banner.TextColor3 = ENRAGE_RED
	banner.TextStrokeColor3 = Color3.new(0, 0, 0)
	banner.TextStrokeTransparency = 1
	banner.TextTransparency = 1
	banner.Text = "ENRAGED!"
	banner.ZIndex = 37
	banner.Parent = root
	local bannerScale = Instance.new("UIScale")
	bannerScale.Parent = banner

	local stamp = Instance.new("TextLabel")
	stamp.Name = "BossDefeatedStamp"
	stamp.AnchorPoint = Vector2.new(0.5, 0.5)
	stamp.Position = UDim2.new(0.5, 0, 0, 0)
	stamp.Size = UDim2.new(0, 320, 0, 60)
	stamp.BackgroundTransparency = 1
	stamp.Font = Enum.Font.GothamBlack
	stamp.TextSize = 40
	stamp.Text = "DEFEATED"
	stamp.TextColor3 = GOLD
	stamp.TextStrokeColor3 = Color3.fromRGB(60, 20, 10)
	stamp.TextStrokeTransparency = 0.1
	stamp.Rotation = -8
	stamp.Visible = false
	stamp.ZIndex = 6
	stamp.Parent = host
	local stampScale = Instance.new("UIScale")
	stampScale.Parent = stamp

	-- attack strength per rule category: lunge scale, shake, dark band flash
	local ATTACK = {
		debuff = { lunge = 1.08, shake = 3, band = true },
		restriction = { lunge = 1.04, shake = 2, band = false },
		weaken = { lunge = 1.05, shake = 0, band = false },
		squeeze = { lunge = 1.08, shake = 4, band = true },
		tips = { lunge = 1.05, shake = 2, band = false },
	}

	local function attack()
		local spec = ATTACK[category]
		if not spec or not visible or retiring then return end
		if playThump then pcall(playThump) end
		stageEvent("boss", "attack", spec.lunge - 1 > 0.06 and 1 or 0.5)
		stageEvent("player", "flinch")
		if spec.band then
			band.BackgroundTransparency = 0.45
			play(band, { BackgroundTransparency = 1 }, 0.3)
		end
		if motionOk() then
			play(pscale, { Scale = spec.lunge }, 0.1)
			play(holder, { Position = UDim2.new(0.5, 0, 0, 14) }, 0.1)
			later(0.14, function()
				play(pscale, { Scale = 1 }, 0.25, Enum.EasingStyle.Back)
				play(holder, { Position = UDim2.new(0.5, 0, 0, 0) }, 0.25, Enum.EasingStyle.Back)
			end)
			if spec.shake > 0 and screenShake then pcall(screenShake, root, spec.shake, 0.15) end
		end
		say("rule_hit")
	end

	local function enrage()
		enraged = true
		stageEvent("boss", "enrage", 1)
		local color = grand and ENRAGE_GOLD or ENRAGE_RED
		tintBase = 0.78
		tint.BackgroundColor3 = color
		play(tint, { BackgroundTransparency = tintBase }, 0.4)
		rageFx.BackgroundColor3 = color
		banner.TextColor3 = color
		-- sits across the portrait (never on the plaque or HP bar)
		do
			local rs = root.AbsolutePosition
			local c = holder.AbsolutePosition + holder.AbsoluteSize / 2 - rs
			banner.Position = UDim2.fromOffset(c.X, c.Y)
		end
		-- banner slams in for ~1.2s
		banner.TextTransparency = 0
		banner.TextStrokeTransparency = 0.1
		if motionOk() and not fast() then
			bannerScale.Scale = 2.4
			play(bannerScale, { Scale = 1 }, 0.2, Enum.EasingStyle.Back)
		else
			bannerScale.Scale = 1
		end
		later(0.9, function()
			play(banner, { TextTransparency = 1, TextStrokeTransparency = 1 }, 0.3)
		end)
		if playThump then pcall(playThump) end
		-- bar flashes and shakes
		if motionOk() then
			for i = 1, 4 do
				later(i * 0.08, function()
					play(barStroke, { Color = (i % 2 == 1) and color or GOLD }, 0.07)
					local dx = (i % 2 == 1) and 4 or -4
					play(bar, { Position = bar.Position + UDim2.new(0, dx, 0, 0) }, 0.07)
				end)
			end
			later(0.5, function()
				play(bar, { Position = UDim2.new(0.5, 0, 0, holder.Size.Y.Offset + 8 + 50 + 6) }, 0.1)
				play(barStroke, { Color = color }, 0.1)
			end)
			-- slow red/gold pulse over the scene, until the round ends
			rageFx.BackgroundTransparency = 0.88
			local pulse = TweenService:Create(rageFx,
				TweenInfo.new(1.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
				{ BackgroundTransparency = 0.8 })
			pulse:Play()
			table.insert(tweens, pulse)
			startIdle(0.8) -- faster idle
		end
		-- music a touch faster (restored in hide)
		if music and not musicBase then
			local ok, base = pcall(function() return music.PlaybackSpeed end)
			if ok and type(base) == "number" then
				musicBase = base
				pcall(function() music.PlaybackSpeed = base * 1.07 end)
			end
		end
		say("half", true)
	end

	local function defeatSequence()
		retiring = true
		require(script.Parent.Cue).play("boss_defeat")
		setHp(0, false)
		if fast() then
			say("defeated", true)
			later(0.6, function() hide() end)
			return
		end
		if playFanfare then pcall(playFanfare) end
		stageEvent("boss", "defeat", 1)
		stageEvent("player", "cheer")
		-- freeze frame: idle motion stops and the boss holds still for a beat, then
		-- desaturates, tilts and slides down; gold confetti and orange embers burst out.
		stopIdle()
		tintBase = 0.45
		tint.BackgroundColor3 = Color3.fromRGB(110, 110, 115)
		play(tint, { BackgroundTransparency = tintBase }, 0.25)
		if motionOk() then
			later(0.25, function()
				play(holder, { Rotation = 14, Position = UDim2.new(0.5, 0, 0, 36) }, 0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			end)
		end
		screenFlash()
		particles(30, GOLD)
		particles(16, Color3.fromRGB(255, 140, 60)) -- embers
		-- stamp slams in
		stamp.Position = UDim2.new(0.5, 0, 0, holder.Size.Y.Offset * 0.5)
		stamp.Visible = true
		if motionOk() then
			stampScale.Scale = 3
			play(stampScale, { Scale = 1 }, 0.22, Enum.EasingStyle.Back)
		else
			stampScale.Scale = 1
		end
		say("defeated", true) -- the boss's final line (BossLines), before the reward flow
		later(1.5, function() hide() end) -- total beat stays within 1.5s; rewards are never delayed
	end

	local function lossSequence()
		retiring = true
		stageEvent("boss", "victory", 1)
		stageEvent("player", "slump")
		say("victory", true)
		if motionOk() then
			-- grows slightly and laughs (bob)
			play(pscale, { Scale = 1.1 }, 0.3, Enum.EasingStyle.Back)
			for i = 1, 4 do
				later(0.3 + i * 0.16, function()
					play(holder, { Position = UDim2.new(0.5, 0, 0, (i % 2 == 1) and -8 or 0) }, 0.14)
				end)
			end
		end
		later(1.5, function() hide() end)
	end

	hide = function()
		token = token + 1
		for _, t in ipairs(tweens) do t:Cancel() end
		tweens = {}
		stopIdle()
		for _, child in ipairs(host:GetChildren()) do
			if child:IsA("TextLabel") and child.ZIndex == 5 then child:Destroy() end
		end
		bubbleToken = bubbleToken + 1
		bubble.Visible = false
		stamp.Visible = false
		banner.TextTransparency = 1
		banner.TextStrokeTransparency = 1
		band.BackgroundTransparency = 1
		rageFx.BackgroundTransparency = 1
		barStroke.Color = GOLD
		rim.Thickness = 3
		holder.Rotation = 0
		holder.Visible = true
		holder.Position = UDim2.new(0.5, 0, 0, 0)
		pscale.Scale = 1
		tintBase = 1
		tint.BackgroundColor3 = Color3.fromRGB(220, 40, 30)
		tint.BackgroundTransparency = 1
		if musicBase and music then
			pcall(function() music.PlaybackSpeed = musicBase end)
		end
		musicBase = nil
		retiring = false
		arrange()
		host.Visible = false
		visible = false
	end

	-- ===== public =====
	-- True once the boss portrait for this fight is on screen (TravelTransition waits on it for boss rounds).
	function M.portraitReady()
		return visible and art ~= nil
	end

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
			if visible and not retiring then
				-- The fight just ended: cleared (the next screen is the shop / round select),
				-- lost (game over), or abandoned (anything else just hides).
				if state.phase == "gameover" then
					lossSequence()
				elseif state.phase == "shop" or state.phase == "roundSelect" or state.phase == "nightVictory" then
					defeatSequence()
				else
					hide()
				end
			end
			if not visible then roundKey = nil end
			return
		end

		local key = tostring(state.night) .. "-" .. tostring(state.round) .. "-" .. tostring(boss.id)
		target = math.max(state.targetScore or 1, 1)
		local score = state.roundScore or 0
		if key ~= roundKey then
			roundKey = key
			hide() -- fresh token, clean state
			-- per-fight setup
			bossDef = BossRounds.getById(boss.id) or boss
			category = BossRounds.categoryOf(bossDef)
			seedText = tostring(state.seedCode or state.dailyDateKey or state.weeklyDateKey or "run")
			grand = BossLines.isGrand(state.night or 1, state.nightCap or 8, JourneyMap.EndlessMilestones)
			enraged, halfDone, lowDone = false, false, false
			lastHands = state.handsRemaining
			lastBubble = -100
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
			-- entrance: pop in, then the intro taunt once the Boss Intro banner has landed
			pscale.Scale = 0.85
			play(pscale, { Scale = 1 }, 0.35, Enum.EasingStyle.Back)
			later(grand and 1.4 or 1.0, function()
					stageEvent("boss", "taunt", 0.6)
					require(script.Parent.Cue).play("boss_intro")
					say("intro", true)
				end)
			return
		end

		holder.Visible = not stageActive() -- the live boss replaces the framed portrait
		local hands = state.handsRemaining
		local playedHand = lastHands ~= nil and hands ~= nil and hands < lastHands
		lastHands = hands

		if score > lastScore then
			local delta = score - lastScore
			lastScore = score
			setHp(1 - score / target, false)
			react(delta, delta >= LEGENDARY * target)
		elseif score < lastScore then
			lastScore = score
			setHp(1 - score / target, true)
		end

		-- Follow-up beats, delayed so they do not collide with the hit reaction.
		if playedHand and score < target then
			later(0.55, attack)
		end
		if not halfDone and score >= 0.5 * target and score < target then
			halfDone = true
			later(0.8, enrage)
		end
		if not lowDone and hands == 1 and score < target then
			lowDone = true
			later(1.6, function() say("low_hands") end)
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
