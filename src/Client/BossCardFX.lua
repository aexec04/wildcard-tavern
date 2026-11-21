--[[
	Client/BossCardFX.lua
	Gameplay2 boss round presentation (rules in Engine/BossCard, tested): the Boss card at the left (portrait, name, rule), the boss name
	with a red health bar in the top scroll, a pulsing gold glow and crown on the Boss card and a soft gold edge on every Patron card.
	Health = Target minus Score, floored at 0, tweened 0.3 s (instant in Calm mode). Display only, nothing takes input.

	update(layer, state, rects, viewW, viewH)   called from Gameplay2.update; hides everything when this is not a boss round
	hide()
	liveRect() -> the Boss card rect while shown (the round hints dodge it), else nil
]]

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Engine = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine")
local Rules = require(Engine:WaitForChild("BossCard"))
local Moments = require(Engine:WaitForChild("Gameplay2Moments"))
local ContentArt = require(Engine:WaitForChild("ContentArt"))
local ClientSettings = require(script.Parent.ClientSettings)

local M = {}
local GOLD = Color3.fromRGB(246, 196, 70)
local CREAM = Color3.fromRGB(250, 240, 220)
local card, top, glowFrames, lastFill, lastBossId, pulseTween

local function calm() return ClientSettings.get("reduceShake") == true end

local function label(parent, name, font, color, z)
	local t = Instance.new("TextLabel")
	t.Name = name
	t.BackgroundTransparency = 1
	t.Font = font
	t.TextColor3 = color
	t.TextTransparency = 0
	t.TextStrokeTransparency = 1
	t.Active = false
	t.ZIndex = z
	t.Parent = parent
	return t
end

local function place(f, r) f.Position = UDim2.fromOffset(r.x, r.y); f.Size = UDim2.fromOffset(r.w, r.h) end

local function buildCard(layer)
	local f = Instance.new("Frame")
	f.Name = "BossCard"
	f.BackgroundColor3 = Color3.fromRGB(226, 205, 160) -- parchment
	f.BorderSizePixel = 0
	f.Active = false
	f.ZIndex = 28
	f.Parent = layer
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 10); c.Parent = f
	local st = Instance.new("UIStroke"); st.Name = "Glow"; st.Color = GOLD; st.Thickness = 3; st.Parent = f
	local pf = Instance.new("Frame"); pf.Name = "Portrait"; pf.BackgroundColor3 = Color3.fromRGB(60, 22, 18); pf.BorderSizePixel = 0; pf.Active = false; pf.ZIndex = 29; pf.Parent = f
	local pc = Instance.new("UICorner"); pc.CornerRadius = UDim.new(0, 8); pc.Parent = pf
	local ps = Instance.new("UIStroke"); ps.Color = Color3.fromRGB(150, 38, 30); ps.Thickness = 2; ps.Parent = pf
	local face = label(pf, "Face", Enum.Font.GothamBold, CREAM, 30)
	face.Size = UDim2.fromScale(1, 1); face.TextScaled = true; face.Text = "!"
	local nm = label(f, "Title", Enum.Font.Merriweather, Color3.fromRGB(70, 28, 16), 29)
	nm.TextXAlignment = Enum.TextXAlignment.Left; nm.TextYAlignment = Enum.TextYAlignment.Top; nm.TextTruncate = Enum.TextTruncate.AtEnd
	local rl = label(f, "Rule", Enum.Font.Gotham, Color3.fromRGB(50, 34, 20), 29)
	rl.TextXAlignment = Enum.TextXAlignment.Left; rl.TextYAlignment = Enum.TextYAlignment.Top; rl.TextWrapped = true
	-- crown above the card
	local crown = label(f, "Crown", Enum.Font.GothamBold, GOLD, 31)
	crown.AnchorPoint = Vector2.new(0.5, 1); crown.Position = UDim2.new(0.5, 0, 0, 4); crown.Size = UDim2.fromOffset(40, 24)
	crown.Text = "\u{1F451}"; crown.TextScaled = true
	return f
end

local function buildTop(layer)
	local f = Instance.new("Frame")
	f.Name = "BossHealth"
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	f.Active = false
	f.ZIndex = 8
	f.Parent = layer
	local nm = label(f, "Title", Enum.Font.Merriweather, Color3.fromRGB(60, 24, 14), 9)
	nm.TextTruncate = Enum.TextTruncate.AtEnd
	local bar = Instance.new("Frame"); bar.Name = "Bar"; bar.BackgroundColor3 = Color3.fromRGB(52, 14, 14); bar.BorderSizePixel = 0; bar.Active = false; bar.ZIndex = 9; bar.Parent = f
	local bc = Instance.new("UICorner"); bc.CornerRadius = UDim.new(0, 6); bc.Parent = bar
	local bs = Instance.new("UIStroke"); bs.Color = Color3.fromRGB(246, 196, 70); bs.Thickness = 1.5; bs.Parent = bar
	local fill = Instance.new("Frame"); fill.Name = "Fill"; fill.BackgroundColor3 = Color3.fromRGB(205, 40, 36); fill.BorderSizePixel = 0; fill.Active = false; fill.ZIndex = 10; fill.Parent = bar
	local fc = Instance.new("UICorner"); fc.CornerRadius = UDim.new(0, 6); fc.Parent = fill
	local num = label(bar, "Num", Enum.Font.GothamBold, CREAM, 11)
	num.Size = UDim2.fromScale(1, 1); num.TextStrokeTransparency = 0.4; num.TextStrokeColor3 = Color3.fromRGB(30, 8, 8)
	local night = label(f, "Night", Enum.Font.Gotham, Color3.fromRGB(70, 44, 24), 9)
	return f
end

local function clearGlow()
	for _, g in ipairs(glowFrames or {}) do g:Destroy() end
	glowFrames = nil
end

function M.hide()
	if card then card.Visible = false end
	if top then top.Visible = false end
	clearGlow()
	if pulseTween then pulseTween:Cancel(); pulseTween = nil end
	lastFill, lastBossId = nil, nil
end

function M.liveRect()
	if card and card.Visible and card.Parent then
		return { x = card.Position.X.Offset, y = card.Position.Y.Offset, w = card.Size.X.Offset, h = card.Size.Y.Offset }
	end
	return nil
end

local function applySeatGlow(layer, rects, owned)
	clearGlow()
	glowFrames = {}
	for i = 1, owned do
		local s = rects.slots and rects.slots[i]
		if s and s.card then
			local g = Instance.new("Frame")
			g.Name = "BossSeatGlow"
			g.BackgroundTransparency = 1
			g.BorderSizePixel = 0
			g.Active = false
			g.ZIndex = 6
			g.Position = UDim2.fromOffset(s.card.x - 2, s.card.y - 2)
			g.Size = UDim2.fromOffset(s.card.w + 4, s.card.h + 4)
			local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 8); c.Parent = g
			local st = Instance.new("UIStroke"); st.Color = GOLD; st.Thickness = Rules.glow(true).softStroke; st.Transparency = 0.35; st.Parent = g
			g.Parent = layer
			glowFrames[#glowFrames + 1] = g
		end
	end
end

function M.update(layer, state, rects, viewW, viewH)
	local name, rule = Moments.bossText(state)
	if not name or state.phase ~= "playing" or layer:FindFirstChild("BossIntro") then M.hide(); return end
	local spot = Rules.cardRect(rects, viewW, viewH)
	if not card or card.Parent ~= layer then card = buildCard(layer) end
	if not top or top.Parent ~= layer then top = buildTop(layer) end
	local glow = Rules.glow(calm())
	local boss = state.bossModifier
	-- left Boss card (the Patron Power tip card is replaced by it on a boss round)
	if spot then
		card.Visible = true
		place(card, spot)
		local parts = Rules.cardParts(spot)
		place(card.Portrait, parts.portrait)
		local nameH = math.max(16, math.min(26, math.floor(parts.text.h * 0.3)))
		card.Title.Position = UDim2.fromOffset(parts.text.x, parts.text.y); card.Title.Size = UDim2.fromOffset(parts.text.w, nameH)
		card.Title.TextSize = nameH - 2; card.Title.Text = name
		card.Rule.Position = UDim2.fromOffset(parts.text.x, parts.text.y + nameH + 2); card.Rule.Size = UDim2.fromOffset(parts.text.w, parts.text.h - nameH - 2)
		card.Rule.TextSize = math.max(12, math.min(17, math.floor(parts.text.h * 0.2)))
		card.Rule.Text = rule
		if lastBossId ~= (boss and boss.id) then
			lastBossId = boss and boss.id
			local old = card.Portrait:FindFirstChild("ContentArt"); if old then old:Destroy() end
			local artId = boss and boss.id and ContentArt.getImageId("boss_rounds", boss.id) or nil
			local okA, art = pcall(function() return require(script.Parent.PatronPlaque).applyById(card.Portrait, artId, { size = UDim2.fromScale(1, 1), zIndex = 30, cornerRadius = 8 }) end)
			if okA and art then art.ScaleType = Enum.ScaleType.Crop end
			card.Portrait.Face.Visible = not (okA and art)
			card.Portrait.Face.Text = Moments.bossIcon(boss and boss.rules)
		end
		card.Glow.Thickness = glow.stroke
		if not pulseTween and glow.pulse then
			pulseTween = TweenService:Create(card.Glow, TweenInfo.new(glow.pulse, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Transparency = 0.7 })
			pulseTween:Play()
		elseif not glow.pulse then
			if pulseTween then pulseTween:Cancel(); pulseTween = nil end
			card.Glow.Transparency = 0
		end
	else
		card.Visible = false
	end
	-- top: the name large, the red health bar under it, Night and Round small
	local tp = Rules.topParts(rects)
	top.Visible = true
	top.Position = UDim2.fromOffset(0, 0); top.Size = UDim2.fromOffset(viewW, viewH)
	local nm, bar, night = top.Title, top.Bar, top.Night
	place(nm, tp.name); nm.Size = UDim2.fromOffset(tp.name.w, tp.name.h)
	nm.TextSize = math.max(10, math.min(26, tp.name.h - 2)); nm.Text = name
	place(bar, tp.bar)
	local cur, total = Rules.health(state.targetScore, state.roundScore)
	bar.Num.TextSize = math.max(9, math.min(16, tp.bar.h - 3))
	bar.Num.Text = Rules.healthText(cur, total)
	local want = Rules.fraction(cur, total)
	if calm() or lastFill == nil then
		bar.Fill.Size = UDim2.fromScale(want, 1)
	elseif lastFill ~= want then
		TweenService:Create(bar.Fill, TweenInfo.new(Rules.TWEEN_SECONDS), { Size = UDim2.fromScale(want, 1) }):Play()
	end
	lastFill = want
	if tp.night then
		night.Visible = true
		place(night, tp.night)
		night.TextSize = math.max(9, math.min(14, tp.night.h - 2))
		night.Text = string.format("Night %d, Round %d", math.floor(state.night or 1), math.floor(state.round or 1))
	else
		night.Visible = false
	end
	applySeatGlow(layer, rects, #(state.ownedPatrons or {}))
end

return M
