--[[
	Client/BossFight.lua
	Boss Rounds as a scene, visual and audio only (no scoring, target or balance changes).
	Driven entirely by the server state the hub already renders: update(state) is called from
	render() and compares the round score with the last one it saw.

	The painted boss portrait is the backdrop of the play area (right of the sidebar): ScaleType Crop,
	anchored so the face stays high, with a dark stepped vignette on the bottom and sides so the card row
	and played hand stay readable. A slim wood banner at the top centre shows the boss name and rule.
	There is NO boss health bar (the sidebar target progress is the only score progress) and nothing
	turns red: hits flash cream, enrage is a gold banner, defeat greys the art (Engine/BossStage holds
	the rules and is tested). Hit reactions are gentle (small shake, knock-back, stagger tilt), plus
	floating damage numbers and a smirk on weak hands.

	Taunts in a parchment speech bubble (Engine/BossLines, deterministic from the run/daily/seed code),
	an attack beat each time a hand is played under a rule that acts on the table, enrage at 50% of the
	Target (banner, thump, music about 7% faster, faster sway), defeat (grey, tilt and slide, DEFEATED
	stamp, gold particles, fanfare, at most 1.5s, never delays the reward flow) and a victory laugh on a
	loss. The final Night boss and Endless milestone bosses (BossLines.isGrand) get a gold banner and a
	longer intro line. Fast speed skips the long beats; Reduce shake skips motion.

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
local BossStage = require(Engine:WaitForChild("BossStage"))

local ENRAGE_GOLD = Color3.fromRGB(235, 180, 40)
local BUBBLE_GAP = 3.5 -- seconds between taunts (intro and the ending lines ignore it)
local CREAM = Color3.fromRGB(250, 235, 200)
local GOLD = Color3.fromRGB(222, 182, 104)
local WOOD = Color3.fromRGB(70, 48, 30)
local BAR_W = 400
local BASE_SCALE = 1.03 -- resting scale of the backdrop: slack so shakes and sway never show an edge
local HIT_FLASH = Color3.fromRGB(250, 240, 210) -- cream, never red
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
	host.BackgroundTransparency = 1
	host.BorderSizePixel = 0
	host.Active = false
	host.ZIndex = 0
	host.Visible = false
	host.Parent = root

	local function layout()
		local cam = workspace.CurrentCamera
		local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
		local areaW = math.max(vp.X - sidebarWidth, 200)
		host.AnchorPoint = Vector2.new(0, 0)
		host.Position = UDim2.new(0, sidebarWidth, 0, 0)
		host.Size = UDim2.new(0, areaW, 1, 0)
	end
	host.ClipsDescendants = true

	-- backdrop holder (what shakes / scales / tilts): fills the play area
	local holder = Instance.new("Frame")
	holder.Name = "BossPortrait"
	holder.AnchorPoint = Vector2.new(0.5, 0)
	holder.Position = UDim2.new(0.5, 0, 0, 0)
	holder.Size = UDim2.fromScale(1, 1)
	holder.BackgroundTransparency = 1
	holder.BorderSizePixel = 0
	holder.Active = false
	holder.ZIndex = 0
	holder.Parent = host
	M.portraitHolder = holder
	local pscale = Instance.new("UIScale")
	pscale.Scale = BASE_SCALE
	pscale.Parent = holder
	local function S(x) return BASE_SCALE * x end

	local art -- ImageLabel or emoji TextLabel, rebuilt per boss
	-- dark stepped vignette (bottom and both sides) so the card row and hand stay readable
	local vignette = Instance.new("Frame")
	vignette.Name = "BossVignette"
	vignette.Size = UDim2.fromScale(1, 1)
	vignette.BackgroundTransparency = 1
	vignette.BorderSizePixel = 0
	vignette.Active = false
	vignette.ZIndex = 0
	vignette.Parent = holder
	do
		local stepT = 1 - BossStage.style(true, false, false).vignette * 0.3 -- 0.85 per layer, they stack
		local function strip(anchor, pos, size)
			local f = Instance.new("Frame")
			f.AnchorPoint = anchor
			f.Position = pos
			f.Size = size
			f.BackgroundColor3 = Color3.fromRGB(10, 7, 5)
			f.BackgroundTransparency = stepT
			f.BorderSizePixel = 0
			f.Active = false
			f.ZIndex = 0
			f.Parent = vignette
		end
		for i = 1, 8 do
			strip(Vector2.new(0, 1), UDim2.fromScale(0, 1), UDim2.fromScale(1, 0.66 * (1 - (i - 1) / 8)))
		end
		for i = 1, 5 do
			local w = 0.2 * (1 - (i - 1) / 5)
			strip(Vector2.new(0, 0), UDim2.fromScale(0, 0), UDim2.fromScale(w, 1))
			strip(Vector2.new(1, 0), UDim2.fromScale(1, 0), UDim2.fromScale(w, 1))
		end
	end
	local tint = Instance.new("Frame") -- cream hit flash / grey defeat wash over the art
	tint.Name = "HitTint"
	tint.Size = UDim2.fromScale(1, 1)
	tint.BackgroundColor3 = HIT_FLASH
	tint.BackgroundTransparency = 1
	tint.BorderSizePixel = 0
	tint.Active = false
	tint.ZIndex = 0
	tint.Parent = holder

	-- slim name banner, top centre
	local plate = Instance.new("Frame")
	plate.Name = "NamePlate"
	plate.AnchorPoint = Vector2.new(0.5, 0)
	plate.Position = UDim2.new(0.5, 0, 0, 10)
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

	local function arrange()
		layout()
	end
	arrange()
	do
		local cam = workspace.CurrentCamera
		if cam then
			cam:GetPropertyChangedSignal("ViewportSize"):Connect(arrange)
		end
	end

	-- ===== effects =====
	local function popText(text, color, size, offsetY)
		local label = Instance.new("TextLabel")
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.Position = UDim2.new(0.5, 0, 0.12 + 0.3 * (offsetY or 0.5), 0)
		label.Size = UDim2.new(0, 260, 0, size + 8)
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
				local dx = (i % 2 == 0 and -1 or 1) * strength * 0.6
				play(holder, { Position = base + UDim2.new(0, dx, 0, 0) }, 0.04)
			end)
		end
		later(count * 0.04 + 0.04, function()
			play(holder, { Position = base }, 0.06)
		end)
	end

	local function flashTint(strength)
		if not require(script.Parent.ClientSettings).flashesAllowed() then return end -- Reduce Flashing
		tint.BackgroundTransparency = math.min(tintBase, 1 - strength)
		play(tint, { BackgroundTransparency = tintBase }, 0.35)
	end

	local function screenFlash()
		if not require(script.Parent.ClientSettings).flashesAllowed() then return end -- Reduce Flashing
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
		local pos = host.AbsolutePosition + Vector2.new(host.AbsoluteSize.X / 2, host.AbsoluteSize.Y * 0.35)
		pcall(burst, UDim2.fromOffset(pos.X, pos.Y), color, count, { size = 8, spread = 120 })
	end

	local function react(delta, legendary)
		local share = delta / math.max(target, 1)
		popText(string.format("-%d", math.floor(delta + 0.5)), legendary and GOLD or CREAM, 26 + math.floor(math.min(share, 1) * 14), 0.2)
		if legendary then
			stageEvent("boss", "stagger", 1)
			stageEvent("player", "cheer")
			flashTint(0.6)
			screenFlash()
			particles(26, GOLD)
			popText("STAGGERED!", GOLD, 24, 0.55)
			if motionOk() then
				play(holder, { Rotation = -1.5 }, 0.15)
				later(0.9, function() play(holder, { Rotation = 0 }, 0.3, Enum.EasingStyle.Back) end)
				play(pscale, { Scale = S(0.97) }, 0.15)
				later(0.9, function() play(pscale, { Scale = BASE_SCALE }, 0.3, Enum.EasingStyle.Back) end)
			end
			if screenShake then pcall(screenShake, root, 6, 0.25) end
		elseif share >= BIG_HIT then
			stageEvent("boss", "hit", math.min(1, share * 2))
			stageEvent("player", "cheer")
			flashTint(0.5)
			screenFlash()
			particles(18, GOLD)
			if motionOk() then
				-- knock-back: shove up and back, then spring home
				play(pscale, { Scale = S(0.98) }, 0.1)
				play(holder, { Position = UDim2.new(0.5, 0, 0, -6) }, 0.1)
				later(0.12, function()
					play(pscale, { Scale = BASE_SCALE }, 0.3, Enum.EasingStyle.Back)
					play(holder, { Position = UDim2.new(0.5, 0, 0, 0) }, 0.3, Enum.EasingStyle.Back)
				end)
			end
			if screenShake then pcall(screenShake, root, 4, 0.2) end
		elseif share < SMIRK_BELOW then
			-- quiet beat: the boss shrugs it off
			stageEvent("boss", "taunt", 0.3)
			popText("...", CREAM, 20, 0.8)
			if motionOk() then
				play(pscale, { Scale = S(1.015) }, 0.2)
				later(0.5, function() play(pscale, { Scale = BASE_SCALE }, 0.3) end)
			end
		else
			stageEvent("boss", "hit", math.min(1, share * 3))
			flashTint(0.4)
			particles(8, CREAM)
			shake(4, 4)
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
		local amp = BossStage.style(true, enraged, grand).swayAmp * (grand and 1.4 or 1)
		swayConn = RunService.RenderStepped:Connect(function()
			if not (art and host.Visible) then return end
			local dx, dy, rot = StageMotion.sway(os.clock() * speed, phase, amp)
			art.Position = UDim2.new(0, dx, 0, dy)
			art.Rotation = rot
		end)
	end

	local function setArt(boss)
		if art then art:Destroy() art = nil end
		local artId = boss and ContentArt.getImageId("boss_rounds", boss.id) or nil
		if artId then
			-- Crop over a frame 30% taller than the area, anchored top: the face stays above the card row.
			art = PatronPlaque.applyById(holder, artId, {
				size = UDim2.fromScale(1, 1.3), anchor = Vector2.new(0, 0), position = UDim2.fromScale(0, 0),
				zIndex = 0, cornerRadius = 0,
			})
			if art then art.ScaleType = Enum.ScaleType.Crop end
		end
		if not art then
			art = Instance.new("TextLabel")
			art.AnchorPoint = Vector2.new(0.5, 0)
			art.Position = UDim2.fromScale(0.5, 0.18)
			art.Size = UDim2.fromScale(0.45, 0.45)
			art.BackgroundTransparency = 1
			art.Font = Enum.Font.GothamBold
			art.TextScaled = true
			art.Text = "👑"
			art.TextColor3 = CREAM
			art.ZIndex = 0
			art.Parent = holder
		end
		-- keep the vignette and flash above the art
		vignette.Parent = nil
		vignette.Parent = holder
		tint.Parent = nil
		tint.Parent = holder
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
		bubble.Position = UDim2.new(0.5, -(BAR_W / 2) - 10, 0, 10) -- left of the banner
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

	local banner = Instance.new("TextLabel")
	banner.Name = "BossEnrageBanner"
	banner.AnchorPoint = Vector2.new(0.5, 0.5)
	banner.Position = UDim2.fromScale(0.5, 0.3) -- re-aimed at the portrait on enrage
	banner.Size = UDim2.new(0, 460, 0, 70)
	banner.BackgroundTransparency = 1
	banner.Font = Enum.Font.GothamBlack
	banner.TextSize = 44
	banner.TextColor3 = ENRAGE_GOLD
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
	stamp.Position = UDim2.fromScale(0.5, 0.3)
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
			play(pscale, { Scale = S(1 + (spec.lunge - 1) * 0.4) }, 0.1)
			play(holder, { Position = UDim2.new(0.5, 0, 0, 6) }, 0.1)
			later(0.14, function()
				play(pscale, { Scale = BASE_SCALE }, 0.25, Enum.EasingStyle.Back)
				play(holder, { Position = UDim2.new(0.5, 0, 0, 0) }, 0.25, Enum.EasingStyle.Back)
			end)
			if spec.shake > 0 and screenShake then pcall(screenShake, root, spec.shake, 0.15) end
		end
		say("rule_hit")
	end

	local function enrage()
		enraged = true
		stageEvent("boss", "enrage", 1)
		-- No red and no screen tint (Engine/BossStage): a gold banner, a cream flash and a faster sway.
		local color = BossStage.style(true, true, grand).banner
		banner.TextColor3 = Color3.fromRGB(color[1], color[2], color[3])
		-- sits across the backdrop's upper middle (never on the name banner)
		do
			local rs = root.AbsolutePosition
			local c = host.AbsolutePosition + host.AbsoluteSize * Vector2.new(0.5, 0.3) - rs
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
		screenFlash()
		startIdle(0.8) -- faster sway (no-op under Reduce shake)
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
				play(holder, { Rotation = 2, Position = UDim2.new(0.5, 0, 0, 24) }, 0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			end)
		end
		screenFlash()
		particles(30, GOLD)
		particles(16, CREAM) -- sparks
		-- stamp slams in
		stamp.Position = UDim2.fromScale(0.5, 0.3)
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
			play(pscale, { Scale = S(1.04) }, 0.3, Enum.EasingStyle.Back)
			for i = 1, 4 do
				later(0.3 + i * 0.16, function()
					play(holder, { Position = UDim2.new(0.5, 0, 0, (i % 2 == 1) and -4 or 0) }, 0.14)
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
		holder.Rotation = 0
		holder.Visible = true
		holder.Position = UDim2.new(0.5, 0, 0, 0)
		pscale.Scale = BASE_SCALE
		tintBase = 1
		tint.BackgroundColor3 = HIT_FLASH
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
					pcall(require(script.Parent.Showdown).play, state, root) -- gold "final blow" banner on the winning hand
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
			host.Visible = true
			visible = true
			startIdle()
			-- entrance: pop in, then the intro taunt once the Boss Intro banner has landed
			pscale.Scale = S(0.96)
			play(pscale, { Scale = BASE_SCALE }, 0.35, Enum.EasingStyle.Back)
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
			react(delta, delta >= LEGENDARY * target)
		elseif score < lastScore then
			lastScore = score
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
