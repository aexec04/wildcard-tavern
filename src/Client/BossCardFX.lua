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
local card, seatCard, top, glowFrames, lastFill, lastBossId, seatBossId, pulseTweens

local function calm() return ClientSettings.get("reduceShake") == true end

local function stopPulse()
	for _, tw in ipairs(pulseTweens or {}) do tw:Cancel() end
	pulseTweens = nil
end

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
	f.BackgroundColor3 = Color3.fromRGB(62, 38, 22) -- dark carved wood like the top plates
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
	local nm = label(f, "Title", Enum.Font.GothamBold, GOLD, 29) -- the name is small and gold above the rule text
	nm.TextXAlignment = Enum.TextXAlignment.Left; nm.TextYAlignment = Enum.TextYAlignment.Top; nm.TextTruncate = Enum.TextTruncate.AtEnd
	local rl = label(f, "Rule", Enum.Font.Gotham, CREAM, 29)
	rl.TextXAlignment = Enum.TextXAlignment.Left; rl.TextYAlignment = Enum.TextYAlignment.Top; rl.TextWrapped = true
	return f
end

-- soft candlelight: `n` stacked UIStroke rings, each `step` px thick, fading outward; parented to the card so they follow it (no picture needed)
local function addRings(f, n, step, radius, z)
	for i = 1, n do
		local d = (i - 1) * step
		local ring = Instance.new("Frame")
		ring.Name = "OuterGlow" .. i
		ring.BackgroundTransparency = 1
		ring.BorderSizePixel = 0
		ring.Active = false
		ring.ZIndex = z
		ring.Position = UDim2.fromOffset(-d, -d)
		ring.Size = UDim2.new(1, 2 * d, 1, 2 * d)
		ring.Parent = f
		local rc = Instance.new("UICorner"); rc.CornerRadius = UDim.new(0, radius + d); rc.Parent = ring
		local rs = Instance.new("UIStroke"); rs.Name = "Ring"; rs.Color = GOLD; rs.Thickness = step; rs.Transparency = 0.5; rs.Parent = ring
	end
end

-- the Boss's own card in the middle Patron seat: portrait filling it, a red BOSS tag where the rarity letter goes, the name on a strip, a crown above
local function buildSeatCard(layer)
	local f = Instance.new("Frame")
	f.Name = "BossSeatCard"
	f.BackgroundColor3 = Color3.fromRGB(60, 22, 18)
	f.BorderSizePixel = 0
	f.Active = false
	f.ZIndex = 28
	f.Parent = layer
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 8); c.Parent = f
	local st = Instance.new("UIStroke"); st.Name = "Glow"; st.Color = GOLD; st.Thickness = 3; st.Parent = f
	addRings(f, 3, 10, 8, 27)
	local art = Instance.new("Frame"); art.Name = "Art"; art.BackgroundTransparency = 1; art.BorderSizePixel = 0; art.Active = false
	art.Size = UDim2.fromScale(1, 1); art.ZIndex = 29; art.ClipsDescendants = true; art.Parent = f
	local face = label(art, "Face", Enum.Font.GothamBold, CREAM, 30)
	face.Size = UDim2.fromScale(1, 1); face.TextScaled = true; face.Text = "!"
	local strip = label(f, "Title", Enum.Font.GothamBold, CREAM, 32)
	strip.BackgroundTransparency = 0.2; strip.BackgroundColor3 = Color3.fromRGB(34, 16, 12)
	strip.AnchorPoint = Vector2.new(0, 1); strip.Position = UDim2.fromScale(0, 1); strip.Size = UDim2.new(1, 0, 0, 24)
	strip.TextScaled = true; strip.TextTruncate = Enum.TextTruncate.AtEnd
	local sc = Instance.new("UICorner"); sc.CornerRadius = UDim.new(0, 6); sc.Parent = strip
	local tag = label(f, "Tag", Enum.Font.GothamBold, CREAM, 33)
	tag.BackgroundTransparency = 0; tag.BackgroundColor3 = Color3.fromRGB(205, 40, 36)
	tag.Position = UDim2.fromOffset(6, 6); tag.Size = UDim2.fromOffset(46, 18); tag.Text = "BOSS"; tag.TextScaled = true
	local tc = Instance.new("UICorner"); tc.CornerRadius = UDim.new(0, 4); tc.Parent = tag
	local crown = label(f, "Crown", Enum.Font.GothamBold, GOLD, 34)
	crown.AnchorPoint = Vector2.new(0.5, 1); crown.Position = UDim2.new(0.5, 0, 0, 10); crown.Size = UDim2.fromOffset(34, 24)
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
	local plate = Instance.new("Frame") -- the taller boss plate behind the rows (hidden when the scroll itself carries them)
	plate.Name = "Plate"
	plate.BackgroundColor3 = Color3.fromRGB(62, 38, 22) -- dark carved wood like the other top plates
	plate.BorderSizePixel = 0
	plate.Active = false
	plate.ZIndex = 8
	plate.Visible = false
	plate.Parent = f
	local pcn = Instance.new("UICorner"); pcn.CornerRadius = UDim.new(0, 10); pcn.Parent = plate
	local pst = Instance.new("UIStroke"); pst.Color = GOLD; pst.Thickness = 2; pst.Parent = plate
	local pg = Instance.new("UIGradient"); pg.Color = ColorSequence.new(Color3.fromRGB(84, 54, 32), Color3.fromRGB(46, 28, 16)); pg.Rotation = 90; pg.Parent = plate -- Color stops only
	local nm = label(f, "Title", Enum.Font.Merriweather, CREAM, 9)
	nm.TextTruncate = Enum.TextTruncate.AtEnd
	local bar = Instance.new("Frame"); bar.Name = "Bar"; bar.BackgroundColor3 = Color3.fromRGB(52, 14, 14); bar.BorderSizePixel = 0; bar.Active = false; bar.ZIndex = 9; bar.Parent = f
	local bc = Instance.new("UICorner"); bc.CornerRadius = UDim.new(0, 6); bc.Parent = bar
	local bs = Instance.new("UIStroke"); bs.Color = Color3.fromRGB(246, 196, 70); bs.Thickness = 1.5; bs.Parent = bar
	local fill = Instance.new("Frame"); fill.Name = "Fill"; fill.BackgroundColor3 = Color3.fromRGB(205, 40, 36); fill.BorderSizePixel = 0; fill.Active = false; fill.ZIndex = 10; fill.Parent = bar
	local fc = Instance.new("UICorner"); fc.CornerRadius = UDim.new(0, 6); fc.Parent = fill
	local num = label(bar, "Num", Enum.Font.GothamBold, CREAM, 11)
	num.Size = UDim2.fromScale(1, 1); num.TextStrokeTransparency = 0.4; num.TextStrokeColor3 = Color3.fromRGB(30, 8, 8)
	local night = label(f, "Night", Enum.Font.Gotham, Color3.fromRGB(226, 205, 160), 9)
	return f
end

local function clearGlow()
	for _, g in ipairs(glowFrames or {}) do g:Destroy() end
	glowFrames = nil
end

function M.hide()
	if card then card.Visible = false end
	if seatCard then seatCard.Visible = false end
	seatBossId = nil
	if top then top.Visible = false end
	clearGlow()
	stopPulse()
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
		local seat = Rules.seatFor(i, true) -- the Boss card holds the middle seat: Patrons 3 and 4 stand in seats 4 and 5, a fifth is out of the row
		local s = seat and rects.slots and rects.slots[seat]
		if s and s.card then
			local g = Instance.new("Frame")
			g.Name = "BossSeatGlow"
			g.BackgroundTransparency = 1
			g.BorderSizePixel = 0
			g.Active = false
			g.ZIndex = 12 -- above the seat shadow and plaque frames so the gold edge is not hidden
			g.Position = UDim2.fromOffset(s.card.x - 2, s.card.y - 2)
			g.Size = UDim2.fromOffset(s.card.w + 4, s.card.h + 4)
			local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 8); c.Parent = g
			local st = Instance.new("UIStroke"); st.Color = GOLD; st.Thickness = Rules.glow(true).seatStroke; st.Transparency = 0; st.Parent = g
			local gl = Rules.glow(true)
			pcall(function() -- candlelight: the shared feathered radial glow (no ring edges, no seams), about 30 px past the card, static in Calm mode and Reduce motion
				local pad = gl.seatHalo
				require(script.Parent.SoftGlow).build(g, {
					name = "Halo", color = GOLD, peak = 0.4, zIndex = 11,
					position = UDim2.new(0.5, 0, 0.5, 0), size = UDim2.new(1, 2 * pad, 1, 2 * pad),
				})
			end)
			g.Parent = layer
			glowFrames[#glowFrames + 1] = g
		end
	end
end

function M.update(layer, state, rects, viewW, viewH)
	local name, rule = Moments.bossText(state)
	if not name or state.phase ~= "playing" or layer:FindFirstChild("BossIntro") then M.hide(); return end
	local spot = Rules.cardRect(rects, viewW, viewH)
	pcall(function() -- a red Concept T plate or old rule strip left behind the Boss card: gone before the card shows
		require(script.Parent.BossPresenceFX).hide()
		for _, n in ipairs({ "BossPresencePlate", "BossBanner" }) do
			local old = layer:FindFirstChild(n) or (layer.Parent and layer.Parent:FindFirstChild(n))
			if old then old:Destroy() end
		end
	end)
	if not card or card.Parent ~= layer then card = buildCard(layer) end
	if not top or top.Parent ~= layer then top = buildTop(layer) end
	if not seatCard or seatCard.Parent ~= layer then seatCard = buildSeatCard(layer); seatBossId = nil end
	pcall(function() -- the same ornate plate picture the Target and Tips plates use (colour stops of the flat plate go transparent under it)
		if not top.Plate:GetAttribute("Painted") then
			top.Plate:SetAttribute("Painted", true)
			require(script.Parent.TavernKit).painted(top.Plate, "wh_target")
		end
	end)
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
		card.Glow.Transparency = 0
	else
		card.Visible = false
	end
	-- the Boss's own card in the middle Patron seat: same size as a Patron card, crown above, the strongest glow
	local seat = Rules.seatRect(rects)
	if seat then
		seatCard.Visible = true
		place(seatCard, seat)
		seatCard.Title.Text = name
		seatCard.Title.TextScaled = false -- shrink to fit: 6 px side padding, never under 12 px
		do
			local tw, ts = math.max(10, seat.w - 12), math.max(12, math.min(18, math.floor(seat.h * 0.1)))
			local function width(s) local ok, b = pcall(function() return game:GetService("TextService"):GetTextSize(name, s, Enum.Font.GothamBold, Vector2.new(10000, 100)) end); return ok and b.X or 0 end
			while width(ts) > tw and ts > 12 do ts = ts - 1 end
			seatCard.Title.TextSize = ts
			seatCard.Title.TextTruncate = Enum.TextTruncate.AtEnd
		end
		seatCard.Title.Size = UDim2.new(1, 0, 0, math.max(16, math.min(26, math.floor(seat.h * 0.16))))
		seatCard.Tag.Size = UDim2.fromOffset(math.max(34, math.min(52, math.floor(seat.w * 0.4))), math.max(14, math.min(20, math.floor(seat.h * 0.1))))
		if seatBossId ~= (boss and boss.id) then
			seatBossId = boss and boss.id
			local old = seatCard.Art:FindFirstChild("ContentArt"); if old then old:Destroy() end
			local artId = boss and boss.id and ContentArt.getImageId("boss_rounds", boss.id) or nil
			local okA, art = pcall(function() return require(script.Parent.PatronPlaque).applyById(seatCard.Art, artId, { size = UDim2.fromScale(1, 1), zIndex = 30, cornerRadius = 8 }) end)
			if okA and art then art.ScaleType = Enum.ScaleType.Crop end
			seatCard.Art.Face.Visible = not (okA and art)
			seatCard.Art.Face.Text = Moments.bossIcon(boss and boss.rules)
		end
		seatCard.Glow.Thickness = glow.stroke
		if not pulseTweens and glow.pulse then
			pulseTweens = {}
			for i = 1, 3 do -- ring i pulses from lo + 0.15 (i - 1) up to hi + 0.15 (i - 1): the inner ring is the strongest
				local ring = seatCard["OuterGlow" .. i].Ring
				ring.Transparency = glow.lo + 0.15 * (i - 1)
				local tw = TweenService:Create(ring, TweenInfo.new(glow.pulse, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Transparency = glow.hi + 0.15 * (i - 1) })
				tw:Play()
				pulseTweens[i] = tw
			end
		elseif not glow.pulse then
			stopPulse()
			for i = 1, 3 do seatCard["OuterGlow" .. i].Ring.Transparency = glow.lo + 0.15 * (i - 1) end -- static in Calm mode and Reduce motion
		end
	else
		seatCard.Visible = false
	end
	-- top: the name large, the red health bar under it, Night and Round small
	local tp = Rules.topParts(rects)
	top.Visible = true
	top.Position = UDim2.fromOffset(0, 0); top.Size = UDim2.fromOffset(viewW, viewH)
	local nm, bar, night = top.Title, top.Bar, top.Night
	if tp.plate then place(top.Plate, tp.plate); top.Plate.Visible = true else top.Plate.Visible = false end
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
