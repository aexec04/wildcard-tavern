--[[
	Client/Gameplay2MomentsFX.lua
	Draws Engine/Gameplay2Moments on the Gameplay v2 table.

	clear(root, lines)               centred "Target cleared" plate: slides in, tips count up, fades out. Takes no input.
	boss(layer, rects, state, w, h)  the boss rule banner under the top bar (rule icon, name, rule) plus a static red candle tint; hides when
	                                 not a boss round. The first time a boss round shows, the banner slides down from the top, holds 1.2 s and
	                                 settles to its resting look. Calm mode and Reduce motion: no slide, resting look at once.
	Calm mode and Reduce motion: the plate just shows, then goes; no tween, no count, no slide. Fast speed halves the times.
]]

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Engine = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine")
local Rules = require(Engine:WaitForChild("Gameplay2Moments"))
local Style = require(Engine:WaitForChild("TavernStyle"))
local Celebration = require(Engine:WaitForChild("Celebration"))
local SoundFX = require(Engine:WaitForChild("SoundFX"))
local ClientSettings = require(script.Parent.ClientSettings)
local Kit = require(script.Parent.TavernKit)
local BossRounds = require(Engine:WaitForChild("BossRounds"))

local M = {}

local function calm() return ClientSettings.get("reduceShake") == true end
local function fast() return ClientSettings.get("animSpeed") == "fast" end
local function color(name) local c = Style.rgb(name); return Color3.fromRGB(c[1], c[2], c[3]) end

local function text(parent, name, str, size, colorName, font, y, h)
	local t = Instance.new("TextLabel")
	t.Name = name
	t.BackgroundTransparency = 1
	t.Size = UDim2.new(1, -24, 0, h)
	t.Position = UDim2.fromOffset(12, y)
	t.Font = Enum.Font[font]
	t.TextSize = size
	t.Text = str
	t.TextColor3 = color(colorName)
	t.TextTransparency = 0
	t.TextStrokeTransparency = 0.3
	t.TextStrokeColor3 = color("outline")
	t.TextTruncate = Enum.TextTruncate.AtEnd
	t.Active = false
	t.ZIndex = 42
	t.Parent = parent
	return t
end

-- Night cleared and Run complete: a bigger plate, gold and purple confetti, tips counting up, a green Continue plate
local function night(root, lines)
	local prior = root:FindFirstChild("NightClearedPlate")
	if prior then prior:Destroy() end
	local n = lines.night
	local size = root.AbsoluteSize
	local rect = Rules.nightPlate(size.X, size.Y, n.runComplete)
	local timing = Rules.clearTiming(calm(), fast())
	local holder = Instance.new("Frame")
	holder.Name = "NightClearedPlate"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromOffset(rect.w, rect.h)
	holder.Position = UDim2.fromOffset(rect.x, rect.y)
	holder.ZIndex = 41
	holder.Parent = root
	if n.runComplete then -- a soft gold crown glow behind the plate: a solid frame, never a Transparency gradient
		local glow = Instance.new("Frame")
		glow.Name = "CrownGlow"
		glow.BorderSizePixel = 0
		glow.Active = false
		glow.BackgroundColor3 = color("gold")
		glow.BackgroundTransparency = 0.82
		glow.AnchorPoint = Vector2.new(0.5, 0.5)
		glow.Position = UDim2.fromScale(0.5, 0.5)
		glow.Size = UDim2.new(1, 28, 1, 28)
		glow.ZIndex = 40
		local gc = Instance.new("UICorner"); gc.CornerRadius = UDim.new(0, 20); gc.Parent = glow
		glow.Parent = holder
	end
	local plate = Kit.plate(holder, UDim2.fromScale(1, 1))
	plate.Name = "Plate"
	plate.Active = false
	plate.ZIndex = 41
	local big = n.runComplete
	text(plate, "Title", n.title, big and 40 or 32, "gold", Style.FONTS.title, 10, big and 48 or 40)
	text(plate, "Night", n.sub, 20, "cream", Style.FONTS.ui, big and 60 or 52, 26)
	text(plate, "Score", lines.score, 20, "cream", Style.FONTS.ui, big and 90 or 80, 26)
	local counting = timing.count and lines.tipsEarned > 0
	local tips = text(plate, "Tips", counting and "Tips +0" or lines.tips, 20, "cream", Style.FONTS.ui, big and 120 or 108, 26)
	if big then -- Run complete: what this run opened, by name, on one gold line (same wording as Run Over)
		local ur = Rules.unlockRow({ w = rect.w, h = rect.h })
		local okU, line = pcall(function()
			local names = require(script.Parent.UnlockToast).namesOf(lines.unlockItems)
			return require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("ProgressionFeel")).unlockLine(names)
		end)
		if ur and okU and line then text(plate, "Unlocks", line, 18, "gold", Style.FONTS.ui, ur.y, ur.h) end
	end
	local cr = Rules.continueRect({ w = rect.w, h = rect.h })
	local btn = Kit.primaryButton(plate, n.button)
	btn.Name = "Continue"
	btn.Size = UDim2.fromOffset(cr.w, cr.h)
	btn.Position = UDim2.fromOffset(cr.x, cr.y)
	btn.ZIndex = 44
	local closed = false
	local function close()
		if closed then return end
		closed = true
		if holder.Parent then holder:Destroy() end
	end
	btn.MouseButton1Click:Connect(close)
	task.delay(Rules.NIGHT_AUTO_CLOSE, close)
	pcall(function() require(script.Parent.ConfettiFX).burst(root, true) end) -- gold and purple, nothing in Calm mode
	if counting then
		local steps = Celebration.countSteps(lines.tipsEarned, false)
		if steps then
			task.spawn(function()
				for i, v in ipairs(steps.values) do
					if not tips.Parent then return end
					tips.Text = string.format("Tips +%d", v)
					pcall(function() require(script.Parent.Cue).play("score_tick", 1, SoundFX.tickSpeed(i)) end) -- a coin tick, pitch rising 1.0 to 1.3
					task.wait(steps.step)
				end
			end)
		end
	end
end

function M.clear(root, lines)
	if not root or not lines then return end
	if lines.night then
		night(root, lines)
		return
	end
	local old = root:FindFirstChild("TargetClearedPlate")
	if old then old:Destroy() end
	local size = root.AbsoluteSize
	local rect = Rules.clearPlate(size.X, size.Y)
	local timing = Rules.clearTiming(calm(), fast())
	local plate = Kit.plate(root, UDim2.fromOffset(rect.w, rect.h))
	plate.Name = "TargetClearedPlate"
	plate.Active = false
	plate.AnchorPoint = Vector2.new(0.5, 0)
	plate.Position = UDim2.fromOffset(rect.x + rect.w / 2, rect.y)
	plate.ZIndex = 41
	local gap = math.floor(rect.h / 4)
	local title = text(plate, "Title", lines.title, 28, "gold", Style.FONTS.title, 6, gap + 8)
	text(plate, "Score", lines.score, 20, "cream", Style.FONTS.ui, 6 + gap + 8, gap)
	local tips = text(plate, "Tips", lines.tipsEarned > 0 and "Tips +0" or lines.tips, 20, "cream", Style.FONTS.ui, 6 + 2 * gap + 8, gap)
	if timing.slide == 0 then
		tips.Text = lines.tips
		task.delay(timing.hold, function() if plate.Parent then plate:Destroy() end end)
		return
	end
	local fall = 18
	plate.Position = UDim2.fromOffset(rect.x + rect.w / 2, rect.y - fall)
	TweenService:Create(plate, TweenInfo.new(timing.slide, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = UDim2.fromOffset(rect.x + rect.w / 2, rect.y) }):Play()
	task.spawn(function()
		local steps = Celebration.countSteps(lines.tipsEarned, false)
		if steps then
			for _, v in ipairs(steps.values) do
				if not tips.Parent then return end
				tips.Text = string.format("Tips +%d", v)
				task.wait(math.min(steps.step, timing.hold / math.max(1, #steps.values)))
			end
		end
		task.wait(math.max(0, timing.hold - 0.2))
		if not plate.Parent then return end
		for _, d in ipairs(plate:GetDescendants()) do
			if d:IsA("TextLabel") then
				TweenService:Create(d, TweenInfo.new(timing.fade), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
			end
		end
		local fadeTween = TweenService:Create(plate, TweenInfo.new(timing.fade), { BackgroundTransparency = 1 })
		fadeTween.Completed:Connect(function() if plate.Parent then plate:Destroy() end end)
		fadeTween:Play()
		task.delay(timing.fade + 0.5, function() if plate.Parent then plate:Destroy() end end)
	end)
end

-- BOSS INTRO: dim the table, slide a plate (portrait, name, rule) in, hold, fade. Once per boss round, never in Calm mode or Reduce
-- motion (Rules.bossIntro is nil). Takes no input (nothing here is Active), so it can never trap a click.
local function introCinematic(layer, bdef, name, rule, tint, w, h, rects)
	local timing = Rules.bossIntro(calm(), fast())
	if not timing or not layer.Parent then return end
	local old = layer:FindFirstChild("BossIntro")
	if old then old:Destroy() end
	local holder = Instance.new("Frame")
	holder.Name = "BossIntro"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromScale(1, 1)
	holder.Active = false
	holder.ZIndex = 34
	holder:SetAttribute("Born", os.clock())
	holder.Parent = layer
	local dim = Instance.new("Frame")
	dim.Name = "Dim"
	dim.BorderSizePixel = 0
	dim.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	dim.BackgroundTransparency = 1
	dim.Size = UDim2.fromScale(1, 1)
	dim.Active = false
	dim.ZIndex = 34
	dim.Parent = holder
	local rect = Rules.bossIntroPlateFor(rects, w, h)
	local plate = Instance.new("Frame")
	plate.Name = "Plate"
	plate.BorderSizePixel = 0
	plate.BackgroundColor3 = Color3.fromRGB(tint.fill[1], tint.fill[2], tint.fill[3])
	plate.BackgroundTransparency = 0.05
	plate.Active = false
	plate.ZIndex = 35
	plate.Size = UDim2.fromOffset(rect.w, rect.h)
	local rest = UDim2.fromOffset(rect.x, rect.y)
	plate.Position = UDim2.fromOffset(rect.x, rect.y - 40)
	local pc = Instance.new("UICorner"); pc.CornerRadius = UDim.new(0, 12); pc.Parent = plate
	local st = Instance.new("UIStroke"); st.Color = Color3.fromRGB(tint.edge[1], tint.edge[2], tint.edge[3]); st.Thickness = 3; st.Parent = plate
	plate.Parent = holder
	local portraitRect, textRect = Rules.bossIntroParts(rect)
	local chip = Instance.new("Frame")
	chip.Name = "Portrait"
	chip.BorderSizePixel = 0
	chip.BackgroundColor3 = Color3.fromRGB(tint.edge[1], tint.edge[2], tint.edge[3])
	chip.Active = false
	chip.ZIndex = 36
	chip.Position = UDim2.fromOffset(portraitRect.x, portraitRect.y)
	chip.Size = UDim2.fromOffset(portraitRect.w, portraitRect.h)
	local cc = Instance.new("UICorner"); cc.CornerRadius = UDim.new(0, 10); cc.Parent = chip
	chip.Parent = plate
	local letter = Instance.new("TextLabel") -- the rule family letter, shown when the boss has no painted portrait
	letter.Name = "Letter"
	letter.BackgroundTransparency = 1
	letter.Size = UDim2.fromScale(1, 1)
	letter.Font = Enum.Font[Style.FONTS.title]
	letter.TextSize = 32
	letter.Text = Rules.bossIcon(bdef and bdef.rules)
	letter.TextColor3 = color("cream")
	letter.TextTransparency = 0
	letter.TextStrokeTransparency = 0.4
	letter.TextStrokeColor3 = color("outline")
	letter.ZIndex = 37
	letter.Parent = chip
	if bdef and bdef.id then
		pcall(function()
			local art = require(script.Parent.PatronPlaque).apply(chip, bdef.id, { category = "bosses", zIndex = 38, cornerRadius = 10 })
			if art then letter.Visible = false end
		end)
	end
	local function line(nm, str, size, colorName, font, y, hh)
		local t = Instance.new("TextLabel")
		t.Name = nm
		t.BackgroundTransparency = 1
		t.Position = UDim2.fromOffset(textRect.x, textRect.y + y)
		t.Size = UDim2.fromOffset(textRect.w, hh)
		t.Font = Enum.Font[font]
		t.TextSize = size
		t.Text = str
		t.TextColor3 = color(colorName)
		t.TextTransparency = 0
		t.TextStrokeTransparency = 0.4
		t.TextStrokeColor3 = color("outline")
		t.TextXAlignment = Enum.TextXAlignment.Left
		t.TextWrapped = true
		t.TextScaled = true -- a long rule shrinks to fit two lines (never below 14 px), it is never cut with dots
		local lim = Instance.new("UITextSizeConstraint"); lim.MaxTextSize = size; lim.MinTextSize = 14; lim.Parent = t
		t.ZIndex = 36
		t.Active = false
		t.Parent = plate
		return t
	end
	line("Name", name, 28, "gold", Style.FONTS.title, 0, 34)
	line("Rule", rule, 17, "cream", Style.FONTS.ui, 38, math.max(20, textRect.h - 38))
	TweenService:Create(dim, TweenInfo.new(timing.slide), { BackgroundTransparency = timing.dim }):Play()
	TweenService:Create(plate, TweenInfo.new(timing.slide, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = rest }):Play()
	task.delay(timing.slide + timing.hold, function()
		if not holder.Parent then return end
		TweenService:Create(dim, TweenInfo.new(timing.fade), { BackgroundTransparency = 1 }):Play()
		TweenService:Create(plate, TweenInfo.new(timing.fade), { BackgroundTransparency = 1 }):Play()
		for _, d in ipairs(plate:GetDescendants()) do
			if d:IsA("TextLabel") then
				TweenService:Create(d, TweenInfo.new(timing.fade), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
			elseif d:IsA("ImageLabel") then
				TweenService:Create(d, TweenInfo.new(timing.fade), { ImageTransparency = 1 }):Play()
			elseif d:IsA("Frame") then
				TweenService:Create(d, TweenInfo.new(timing.fade), { BackgroundTransparency = 1 }):Play()
			end
		end
		task.delay(timing.fade + 0.1, function() if holder.Parent then holder:Destroy() end end)
	end)
end

-- the banner and tint live inside the Gameplay2 layer so they hide with it
function M.boss(layer, rects, state, w, h)
	local tint = layer:FindFirstChild("BossTint")
	local banner = layer:FindFirstChild("BossBanner")
	local name, rule = Rules.bossText(state)
	local rulePlate = layer:FindFirstChild("BossRulePlate")
	if not name then
		if tint then tint.Visible = false end
		if banner then banner.Visible = false end
		if rulePlate then rulePlate.Visible = false end
		return
	end
	local bdef = state.bossModifier and state.bossModifier.id and BossRounds.getById(state.bossModifier.id)
	local tintSet = Rules.bossTint(bdef and bdef.rules)
	-- one line rule plate under the Patron row, tinted by the boss rule family (static, no tween)
	local pr = Rules.rulePlate(rects)
	if not pr or rule == "" then
		if rulePlate then rulePlate.Visible = false end
	else
		if not rulePlate then
			rulePlate = Instance.new("TextLabel")
			rulePlate.Name = "BossRulePlate"
			rulePlate.BorderSizePixel = 0
			rulePlate.BackgroundTransparency = 0.1
			rulePlate.Font = Enum.Font[Style.FONTS.ui]
			rulePlate.TextColor3 = color("cream")
			rulePlate.TextTransparency = 0
			rulePlate.TextStrokeTransparency = 0.5
			rulePlate.TextStrokeColor3 = color("outline")
			rulePlate.TextTruncate = Enum.TextTruncate.AtEnd
			rulePlate.TextXAlignment = Enum.TextXAlignment.Left
			rulePlate.Active = false
			rulePlate.ZIndex = 4
			local ic = Instance.new("TextLabel"); ic.Name = "BossIcon"; ic.BackgroundColor3 = Color3.fromRGB(150, 38, 30); ic.BackgroundTransparency = 0
			ic.Active = false
			ic.Font = Enum.Font[Style.FONTS.title]; ic.TextColor3 = color("cream"); ic.TextStrokeTransparency = 0.4; ic.TextStrokeColor3 = color("outline"); ic.ZIndex = 5
			local icc = Instance.new("UICorner"); icc.CornerRadius = UDim.new(0, 5); icc.Parent = ic
			ic.Parent = rulePlate
			local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 6); c.Parent = rulePlate
			local pd = Instance.new("UIPadding"); pd.Name = "TextPad"; pd.PaddingLeft = UDim.new(0, 30); pd.PaddingRight = UDim.new(0, 8); pd.Parent = rulePlate
			local st = Instance.new("UIStroke"); st.Name = "Edge"; st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; st.Thickness = 2; st.Parent = rulePlate
			rulePlate.Parent = layer
			-- the slim boss plate stays a dark tinted plate with cream text (4.5:1); the cream parchment frame made the text pale
		end
		rulePlate.Visible = true
		rulePlate.Position = UDim2.fromOffset(pr.x, pr.y)
		rulePlate.Size = UDim2.fromOffset(pr.w, pr.h)
		rulePlate.TextSize = math.max(14, math.min(16, pr.h - 6))
		rulePlate.Text = Rules.plateLine(name, rule)
		local parts = Rules.rulePlateParts(pr)
		local side = parts.icon.w
		-- children of a UIPadding parent start after its left padding: shift the chip back by textX so it lands at icon.x (it sat ON the first letters)
			rulePlate.BossIcon.Position = UDim2.fromOffset(parts.icon.x - parts.textX, parts.icon.y)
		rulePlate.BossIcon.Size = UDim2.fromOffset(side, side)
		rulePlate.TextPad.PaddingLeft = UDim.new(0, parts.textX)
		rulePlate.BossIcon.Text = Rules.bossIcon(bdef and bdef.rules)
		rulePlate.BossIcon.TextSize = math.max(12, math.min(16, side - 6))
		local icf = Rules.iconFill(bdef and bdef.rules); rulePlate.BossIcon.BackgroundColor3 = Color3.fromRGB(icf[1], icf[2], icf[3])
		rulePlate.BackgroundColor3 = Color3.fromRGB(tintSet.fill[1], tintSet.fill[2], tintSet.fill[3])
		rulePlate.Edge.Color = Color3.fromRGB(tintSet.edge[1], tintSet.edge[2], tintSet.edge[3])
	end
	if not tint then
		tint = Instance.new("Frame")
		tint.Name = "BossTint"
		tint.BorderSizePixel = 0
		tint.Size = UDim2.fromScale(1, 1)
		tint.Active = false
		tint.ZIndex = 2
		tint.Parent = layer
	end
	local g = Rules.bossGlow(calm())
	tint.BackgroundColor3 = Color3.fromRGB(g.color[1], g.color[2], g.color[3])
	tint.BackgroundTransparency = g.transparency
	tint.Visible = true
	local stale = layer:FindFirstChild("BossIntro") -- an intro that outlived its hold and fade is removed, never left over the Patrons
	if stale and stale:GetAttribute("Born") and os.clock() - stale:GetAttribute("Born") > 8 then stale:Destroy() end
	local introKey = Rules.bossEntranceKey(state)
	if introKey and tint:GetAttribute("IntroKey") ~= introKey then
		tint:SetAttribute("IntroKey", introKey)
		pcall(function() require(script.Parent.Cue).play("boss_intro") end) -- silent until the cue has an id
		pcall(introCinematic, layer, bdef, name, rule, tintSet, w, h, rects)
	end
	-- ONE boss display: the intro cinematic announces the boss, then the slim rule plate under the Patron rows is the only plate left.
	-- The old strip under the top bar (BossBanner) is gone; remove one that an earlier build left in the layer.
	if banner then banner:Destroy() end
end

return M
