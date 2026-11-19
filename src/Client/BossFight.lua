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
local VignetteCurve = require(Engine:WaitForChild("VignetteCurve"))
local ClientSettings = require(script.Parent.ClientSettings)
local PatronPlaque = require(script.Parent.PatronPlaque)
local BossRounds = require(Engine:WaitForChild("BossRounds"))
local BossLines = require(Engine:WaitForChild("BossLines"))
local JourneyMap = require(Engine:WaitForChild("JourneyMap"))
local BossStage = require(Engine:WaitForChild("BossStage"))
local BossBubbleLayout = require(Engine:WaitForChild("BossBubbleLayout"))
local BossHomeLayout = require(Engine:WaitForChild("BossHomeLayout"))
local BannerVisibility = require(Engine:WaitForChild("BannerVisibility"))

local ENRAGE_GOLD = Color3.fromRGB(235, 180, 40)
local BUBBLE_W, BUBBLE_H = 250, 104
local BUBBLE_GAP = 3.5 -- seconds between taunts (intro and the ending lines ignore it)
local CREAM = Color3.fromRGB(250, 235, 200)
local GOLD = Color3.fromRGB(222, 182, 104)
local WOOD = Color3.fromRGB(70, 48, 30)
local BAR_W = 400
local HOME_Z = 7 -- above the painted room (0); the home is in the top strip, so it never meets the Patron Nook
local MED_RIM = Color3.fromRGB(140, 32, 32) -- dark red rim: a boss
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

	-- The boss home (Engine/BossHomeLayout): a round medallion and the name plate in the top strip, above the Patron Nook.
	-- homeRects holds the resting host-relative rects; nil when the strip is too narrow (the old centred plate stays).
	local homeRects = nil
	local function layout()
		local cam = workspace.CurrentCamera
		local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
		local SM = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("SidebarMetrics"))
		-- the play root can be smaller than the window (scaled roots, DebugGoto scale:WxH): measure it, and keep the home right
		-- of the live board so the medallion never sits on the Night/Round pill
		local rs = root.AbsoluteSize
		if rs.X > 100 and rs.Y > 100 then vp = Vector2.new(rs.X, rs.Y) end
		local left = SM.isPainted() and SM.hostLeft(vp.X, vp.Y) or sidebarWidth -- painted board is wider than the flat sidebar
		local sb = root:FindFirstChild("Sidebar")
		if sb and sb:IsA("GuiObject") and sb.Visible and sb.AbsoluteSize.X > 0 then
			left = math.max(left, sb.AbsolutePosition.X - root.AbsolutePosition.X + sb.AbsoluteSize.X)
		end
		local areaW = math.max(vp.X - left, 200)
		host.AnchorPoint = Vector2.new(0, 0)
		host.Position = UDim2.new(0, left, 0, 0)
		host.Size = UDim2.new(0, areaW, 1, 0)
		local cx = math.floor(vp.X / 2 - left)
		local home = BossHomeLayout.place(vp.X, vp.Y, left)
		local pl = host:FindFirstChild("NamePlate")
		local med = host:FindFirstChild("BossMedallion")
		if home then
			homeRects = {
				plate = UDim2.fromOffset(home.plate.x - left, home.plate.y),
				medallion = UDim2.fromOffset(home.medallion.x - left, home.medallion.y),
			}
			if pl then
				pl.AnchorPoint = Vector2.new(0, 0)
				pl.Position = homeRects.plate
				pl.Size = UDim2.fromOffset(home.plate.w, home.plate.h)
			end
			if med then
				med.Position = homeRects.medallion
				med.Size = UDim2.fromOffset(home.medallion.w, home.medallion.h)
				med.Visible = true
			end
		else
			homeRects = nil
			if pl then
				pl.AnchorPoint = Vector2.new(0.5, 0)
				pl.Position = UDim2.new(0, cx, 0, 10)
				pl.Size = UDim2.new(0, BAR_W, 0, 50)
			end
			if med then med.Visible = false end
		end
		host:SetAttribute("CenterX", cx)
		host:SetAttribute("HomeOk", home ~= nil)
	end
	host.ClipsDescendants = true

	-- backdrop holder (what shakes / scales / tilts): fills the play area
	local lastBossStageLog = nil
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
	local artBase = UDim2.fromScale(0, 0) -- resting position of art; sway is added to it
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
		-- one smooth gradient frame per edge (no stacked strips); edge darkness matches the old 8 / 5 layer stacks
		local layer = BossStage.style(true, false, false).vignette * 0.3
		require(script.Parent.SmoothVignette).build(vignette, {
			name = "BossVignetteEdges", zIndex = 0,
			bottom = { strength = VignetteCurve.stacked(layer, 8), extent = 0.66 },
			left = { strength = VignetteCurve.stacked(layer, 5), extent = 0.2 },
			right = { strength = VignetteCurve.stacked(layer, 5), extent = 0.2 },
		})
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

	-- name plate (name and rule text) beside the medallion in the top strip; the old centred banner when the strip is too narrow
	local plate = Instance.new("Frame")
	plate.Name = "NamePlate"
	plate.AnchorPoint = Vector2.new(0.5, 0)
	plate.Position = UDim2.new(0.5, 0, 0, 10)
	plate.BackgroundColor3 = WOOD
	plate.BorderSizePixel = 0
	plate.Size = UDim2.new(0, BAR_W, 0, 50)
	plate.Active = false
	plate.ZIndex = HOME_Z
	plate.Parent = host
	corner(plate, 8)
	local plateStroke = Instance.new("UIStroke")
	plateStroke.Color = GOLD
	plateStroke.Thickness = 2
	plateStroke.Parent = plate
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, -16, 0, 22)
	nameLabel.Position = UDim2.new(0, 8, 0, 3)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 18
	nameLabel.TextColor3 = CREAM
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextStrokeTransparency = 0.3
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.ZIndex = HOME_Z + 1
	nameLabel.Parent = plate
	local ruleLabel = Instance.new("TextLabel")
	ruleLabel.Size = UDim2.new(1, -16, 1, -28)
	ruleLabel.Position = UDim2.new(0, 8, 0, 25)
	ruleLabel.BackgroundTransparency = 1
	ruleLabel.Font = Enum.Font.Gotham
	ruleLabel.TextSize = 15
	ruleLabel.TextColor3 = Color3.fromRGB(235, 215, 175)
	ruleLabel.TextXAlignment = Enum.TextXAlignment.Left
	ruleLabel.TextYAlignment = Enum.TextYAlignment.Top
	ruleLabel.TextWrapped = true
	ruleLabel.TextStrokeTransparency = 0.4
	ruleLabel.TextTruncate = Enum.TextTruncate.AtEnd
	ruleLabel.ZIndex = HOME_Z + 1
	ruleLabel.Parent = plate

	-- the medallion: a round portrait in a dark red rim, left of the plate (art goes in by setArt); pulses on a rule hit
	local medallion = Instance.new("Frame")
	medallion.Name = "BossMedallion"
	medallion.Size = UDim2.fromOffset(72, 72)
	medallion.BackgroundColor3 = WOOD
	medallion.BorderSizePixel = 0
	medallion.ClipsDescendants = true
	medallion.Active = false
	medallion.Visible = false
	medallion.ZIndex = HOME_Z
	medallion.Parent = host
	corner(medallion, 100)
	local medStroke = Instance.new("UIStroke")
	medStroke.Color = MED_RIM
	medStroke.Thickness = 4
	medStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	medStroke.Parent = medallion
	local medScale = Instance.new("UIScale")
	medScale.Scale = 1
	medScale.Parent = medallion
	local medTint = Instance.new("Frame") -- grey wash on defeat
	medTint.Name = "MedallionTint"
	medTint.Size = UDim2.fromScale(1, 1)
	medTint.BackgroundColor3 = Color3.fromRGB(110, 110, 115)
	medTint.BackgroundTransparency = 1
	medTint.BorderSizePixel = 0
	medTint.Active = false
	medTint.ZIndex = HOME_Z + 3
	medTint.Parent = medallion
	corner(medTint, 100)

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
		-- no flat full-screen wash: a short soft cream glow on the boss (Client/FlashFX, Engine/FlashFX "hit")
		require(script.Parent.FlashFX).play(root, "hit", UDim2.fromScale(0.5, 0.3), { zIndex = 34 })
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
			art.Position = artBase -- (the emoji fallback also sits at 0,0)
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
			art.Position = UDim2.new(artBase.X.Scale, artBase.X.Offset + dx, artBase.Y.Scale, artBase.Y.Offset + dy)
			art.Rotation = rot
		end)
	end

	local function setArt(boss)
		if art then art:Destroy() art = nil end
		artBase = UDim2.fromScale(0, 0)
		local artId = boss and ContentArt.getImageId("boss_rounds", boss.id) or nil
		if homeRects then
			-- the medallion is the boss's one home: the art (or a crown) crops into the circle, never under the nook
			artBase = UDim2.fromScale(0.5, 0.5)
			if artId then
				art = PatronPlaque.applyById(medallion, artId, {
					size = UDim2.fromScale(1.12, 1.12), anchor = Vector2.new(0.5, 0.5), position = artBase,
					zIndex = HOME_Z + 1, cornerRadius = 0,
				})
				if art then art.ScaleType = Enum.ScaleType.Crop end
			end
			if not art then
				art = Instance.new("TextLabel")
				art.AnchorPoint = Vector2.new(0.5, 0.5)
				art.Position = artBase
				art.Size = UDim2.fromScale(0.7, 0.7)
				art.BackgroundTransparency = 1
				art.Font = Enum.Font.GothamBold
				art.TextScaled = true
				art.Text = "\u{1F451}"
				art.TextColor3 = CREAM
				art.TextTransparency = 0
				art.TextStrokeTransparency = 1
				art.ZIndex = HOME_Z + 1
				art.Parent = medallion
			end
		elseif artId then
			-- no room for the home (very narrow screen): the old full-area backdrop
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
			art.Text = "\u{1F451}"
			art.TextColor3 = CREAM
			art.ZIndex = 0
			art.Parent = holder
		end
		medTint.Parent = nil
		medTint.Parent = medallion
		-- keep the vignette and flash above the art
		vignette.Parent = nil
		vignette.Parent = holder
		tint.Parent = nil
		tint.Parent = holder
	end

	-- a rule hit pulses the medallion; defeat greys and tilts it; a boss win swells it with a gold rim (hide() resets all three)
	local function pulseHome()
		if not homeRects or not motionOk() then return end
		medScale.Scale = 1.16
		play(medScale, { Scale = 1 }, 0.3, Enum.EasingStyle.Back)
		medStroke.Color = GOLD
		later(0.3, function() medStroke.Color = MED_RIM end)
	end
	local function homeDefeated()
		play(medTint, { BackgroundTransparency = 0.45 }, 0.3)
		medStroke.Color = Color3.fromRGB(120, 120, 125)
		if motionOk() then play(medallion, { Rotation = 10 }, 0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In) end
	end
	local function homeVictory()
		medStroke.Color = GOLD
		if motionOk() then play(medScale, { Scale = 1.14 }, 0.3, Enum.EasingStyle.Back) end
	end

	-- ===== part 2: taunts, attacks, enrage, defeat =====
	local hide -- forward declaration (defeat / loss end by calling it)

	local function fast()
		return ClientSettings.get("animSpeed") == "fast"
	end

	-- parchment speech bubble, left of the portrait (the right side is the corner icon row)
	local bubble = Instance.new("Frame")
	bubble.Name = "BossBubble"
	bubble.AnchorPoint = Vector2.new(0, 0)
	bubble.Size = UDim2.new(0, BUBBLE_W, 0, BUBBLE_H)
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
	-- the speaker: a round portrait chip and the boss name, so the line never comes from nowhere
	local chip = Instance.new("Frame")
	chip.Name = "SpeakerChip"
	chip.Size = UDim2.fromOffset(30, 30)
	chip.Position = UDim2.fromOffset(8, 6)
	chip.BackgroundColor3 = WOOD
	chip.BorderSizePixel = 0
	chip.Active = false
	chip.ClipsDescendants = true
	chip.ZIndex = 6
	chip.Parent = bubble
	corner(chip, 15)
	local chipStroke = Instance.new("UIStroke")
	chipStroke.Color = Color3.fromRGB(140, 32, 32)
	chipStroke.Thickness = 2
	chipStroke.Parent = chip
	local chipImage = Instance.new("ImageLabel")
	chipImage.Name = "Portrait"
	chipImage.Size = UDim2.fromScale(1.4, 1.4)
	chipImage.AnchorPoint = Vector2.new(0.5, 0.4)
	chipImage.Position = UDim2.fromScale(0.5, 0.4)
	chipImage.BackgroundTransparency = 1
	chipImage.ScaleType = Enum.ScaleType.Crop
	chipImage.ZIndex = 6
	chipImage.Parent = chip
	local chipFallback = Instance.new("TextLabel")
	chipFallback.Name = "Crown"
	chipFallback.Size = UDim2.fromScale(1, 1)
	chipFallback.BackgroundTransparency = 1
	chipFallback.Text = "👑"
	chipFallback.TextSize = 16
	chipFallback.ZIndex = 6
	chipFallback.Parent = chip
	local speakerName = Instance.new("TextLabel")
	speakerName.Name = "SpeakerName"
	speakerName.Size = UDim2.new(1, -52, 0, 30)
	speakerName.Position = UDim2.fromOffset(44, 6)
	speakerName.BackgroundTransparency = 1
	speakerName.Font = Enum.Font.GothamBold
	speakerName.TextSize = 15
	speakerName.TextXAlignment = Enum.TextXAlignment.Left
	speakerName.TextColor3 = Color3.fromRGB(140, 32, 32)
	speakerName.TextStrokeTransparency = 1
	speakerName.TextTruncate = Enum.TextTruncate.AtEnd
	speakerName.ZIndex = 6
	speakerName.Parent = bubble
	-- tail: a diamond half hidden behind the bubble, turned to point at the speaker
	local tail = Instance.new("Frame")
	tail.Name = "Tail"
	tail.AnchorPoint = Vector2.new(0.5, 0.5)
	tail.Size = UDim2.fromOffset(16, 16)
	tail.Rotation = 45
	tail.BackgroundColor3 = Color3.fromRGB(232, 212, 168)
	tail.BorderSizePixel = 0
	tail.Active = false
	tail.ZIndex = 4
	tail.Parent = bubble
	local bubbleText = Instance.new("TextLabel")
	bubbleText.Size = UDim2.new(1, -16, 1, -42)
	bubbleText.Position = UDim2.new(0, 8, 0, 38)
	bubbleText.BackgroundTransparency = 1
	bubbleText.Font = Enum.Font.GothamMedium
	bubbleText.TextSize = 16
	bubbleText.TextColor3 = Color3.fromRGB(60, 40, 22)
	bubbleText.TextStrokeTransparency = 1
	bubbleText.TextWrapped = true
	bubbleText.ZIndex = 6
	bubbleText.Parent = bubble
	local bubbleToken = 0

	-- where the bubble goes: the boss portrait frame if it is on screen, else the banner plate; clear of the hand,
	-- the Patron Row and the dock (rects read live; Engine/BossBubbleLayout is the tested rule)
	local function absRect(g)
		if not g or not g.Visible then return nil end
		local sz = g.AbsoluteSize
		if sz.X <= 0 or sz.Y <= 0 then return nil end
		return { x = g.AbsolutePosition.X, y = g.AbsolutePosition.Y, w = sz.X, h = sz.Y }
	end
	local function bubbleSpot()
		if not host.Visible then return nil end
		local anchor = absRect(medallion) or absRect(plate) -- the live portrait medallion, else the name plate
		if not anchor then return nil end
		local keep = {}
		for _, name in ipairs({ "HandFrame", "PatronRow" }) do
			local r = absRect(root:FindFirstChild(name, true))
			if r then keep[#keep + 1] = r end
		end
		local hp, hs = host.AbsolutePosition, host.AbsoluteSize
		keep[#keep + 1] = { x = hp.X + hs.X - 300, y = hp.Y, w = 300, h = 92 } -- corner dock row
		local spot = BossBubbleLayout.place({ x = hp.X, y = hp.Y, w = hs.X, h = hs.Y }, anchor,
			{ w = BUBBLE_W, h = BUBBLE_H }, keep)
		if not spot then return nil end
		-- to host-relative pixels
		spot.rect.x, spot.rect.y = spot.rect.x - hp.X, spot.rect.y - hp.Y
		spot.tail.x, spot.tail.y = spot.tail.x - hp.X, spot.tail.y - hp.Y
		return spot
	end

	local function say(event, force)
		if not bossDef or not visible then return end
		local now = os.clock()
		if not force and now - lastBubble < BUBBLE_GAP then return end
		local line = BossLines.pick(bossDef.id, category, event, seedText)
		if not line then return end
		lastBubble = now
		bubbleToken = bubbleToken + 1
		local mine = bubbleToken
		-- anchored to the speaker's live rect (portrait frame, else the banner plate), tail towards it
		local spot = bubbleSpot()
		if not spot then -- speaker hidden or no clear room: skip this line
			bubble.Visible = false
			lastBubble = -100
			return
		end
		bubble.Position = UDim2.fromOffset(spot.rect.x, spot.rect.y)
		tail.Position = UDim2.fromOffset(spot.tail.x - spot.rect.x, spot.tail.y - spot.rect.y)
		speakerName.Text = bossDef.name or ""
		local artId = ContentArt.getImageId("boss_rounds", bossDef.id)
		chipImage.Image = artId or ""
		chipImage.Visible = artId ~= nil
		chipFallback.Visible = artId == nil
		tail.BackgroundTransparency = 0
		bubbleText.Text = line
		bubbleText.TextTransparency = 0
		bubbleText.TextStrokeTransparency = 1
		speakerName.TextTransparency = 0
		speakerName.TextStrokeTransparency = 1
		chip.BackgroundTransparency = 0
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
			play(speakerName, { TextTransparency = 1 }, 0.3)
			play(tail, { BackgroundTransparency = 1 }, 0.3)
			play(chip, { BackgroundTransparency = 1 }, 0.3)
			play(chipImage, { ImageTransparency = 1 }, 0.3)
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
		pulseHome()
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
		pcall(require(script.Parent.BossPresenceFX).fanfare, root) -- plate and red pulse off, big confetti
		require(script.Parent.Cue).play("boss_defeat")
		require(script.Parent.Cue).duck() -- a big beat: the music dips about 4 dB for 1.2 s
		if fast() then
			say("defeated", true)
			later(0.6, function() hide() end)
			return
		end
		if playFanfare then pcall(playFanfare) end
		stageEvent("boss", "defeat", 1)
		stageEvent("player", "cheer")
		homeDefeated()
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
		homeVictory()
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
		pcall(require(script.Parent.BossPresenceFX).hide)
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
		medallion.Rotation = 0
		medScale.Scale = 1
		medStroke.Color = MED_RIM
		medTint.BackgroundTransparency = 1
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

	-- The banner belongs to the table: hidden while Collection, Card Sets, Badges, Legend, Flair, Stats or the Ledger are open
	-- (any visible "...Backdrop" frame, see Engine/BannerVisibility), back when they close.
	do
		local acc, covered = 0, false
		RunService.Heartbeat:Connect(function(dt)
			acc = acc + dt
			if acc < 0.25 then return end
			acc = 0
			if not visible and not covered then return end -- no fight on screen: nothing to hide or restore
			local names = {}
			local gui = root:FindFirstAncestorOfClass("ScreenGui")
			for _, parent in ipairs({ root, gui }) do
				if parent then
					for _, c in ipairs(parent:GetChildren()) do
						if c:IsA("GuiObject") and c.Visible then names[#names + 1] = c.Name end
					end
				end
			end
			local now = BannerVisibility.isScreenOpen(names)
			if now then
				if host.Visible then host.Visible = false end
			elseif covered and visible then
				host.Visible = true
			end
			covered = now
		end)
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
			pcall(require(script.Parent.BossPresenceFX).show, root, boss) -- rule plate and red edge pulse (Concept T screen)
			-- entrance: the medallion and plate slide down from above the screen edge (0.4 s) and hold 2.2 s with the name and
			-- rule text, then the intro line speaks from the medallion
			pscale.Scale = S(0.96)
			play(pscale, { Scale = BASE_SCALE }, 0.35, Enum.EasingStyle.Back)
			local introDelay = 1.0
			if homeRects then
				if motionOk() and not fast() then
					medallion.Position = homeRects.medallion - UDim2.fromOffset(0, 100)
					plate.Position = homeRects.plate - UDim2.fromOffset(0, 100)
					play(medallion, { Position = homeRects.medallion }, 0.4, Enum.EasingStyle.Back)
					play(plate, { Position = homeRects.plate }, 0.4, Enum.EasingStyle.Back)
					introDelay = 2.6
				end
			end
			later(introDelay, function()
					stageEvent("boss", "taunt", 0.6)
					require(script.Parent.Cue).play("boss_intro")
					say("intro", true)
				end)
			return
		end

		holder.Visible = not stageActive() -- the live boss replaces the framed portrait
		if lastBossStageLog ~= holder.Visible then
			lastBossStageLog = holder.Visible
			print("[BossStage] visible=" .. tostring(holder.Visible))
		end
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
