--[[
	Client/VictoryScreen.lua
	The purple and gold Victory screen: painted tavern backdrop, a VICTORY banner with laurels, a cheering keeper on the left,
	a chest of coins on the right, a Continue plate at the bottom. Two modes:
	  show(screenGui, lines)                    Run complete: Rewards Earned card (real Tips, unlocks) + Run Summary card
	  showPick(screenGui, choice, onPick, onSkip)  the Patron reward after a Night: 3 parchment cards above a Skip plate
	  hide()  setBestHand(fn -> { name, score } | nil)
	All text is real UI text; the art holds none. Layout comes from Engine/VictoryLook (pure, tested). Calm mode: no confetti, no tween.
	The backdrop is named VictoryBackdrop (MenuGate and ResultGuard know it).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Engine = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine")
local Look = require(Engine:WaitForChild("VictoryLook"))
local Art = require(Engine:WaitForChild("VictorySceneArt"))
local Style = require(Engine:WaitForChild("TavernStyle"))
local ClientSettings = require(script.Parent.ClientSettings)

local M = {}

local PARCH = Color3.fromRGB(240, 222, 180)
local PARCH_EDGE = Color3.fromRGB(150, 108, 52)
local INK = Color3.fromRGB(52, 34, 18)
local GOLD = Color3.fromRGB(255, 214, 130)
local PURPLE = Color3.fromRGB(72, 36, 112)
local PURPLE_DARK = Color3.fromRGB(28, 14, 44)
local CREAM = Color3.fromRGB(250, 240, 220)
local COIN_INK = Color3.fromRGB(84, 52, 8) -- the mark on the gold coin, 6 to 1 or better

local bestProvider
local current -- { gui, kind }

function M.setBestHand(fn) bestProvider = fn end

local function calm() return ClientSettings.get("reduceShake") == true end
local function serif() return Enum.Font[Style.FONTS.title] or Enum.Font.GothamBold end

local function frame(parent, name, r, z, color)
	local f = Instance.new("Frame")
	f.Name = name
	f.BorderSizePixel = 0
	f.BackgroundColor3 = color or PARCH
	f.BackgroundTransparency = color == false and 1 or 0
	f.Position = UDim2.fromOffset(r.x, r.y)
	f.Size = UDim2.fromOffset(r.w, r.h)
	f.ZIndex = z
	f.Parent = parent
	return f
end

local function text(parent, name, str, size, color, font, z, x, y, w, h, align)
	local t = Instance.new("TextLabel")
	t.Name = name
	t.BackgroundTransparency = 1
	t.Position = UDim2.fromOffset(x, y)
	t.Size = UDim2.fromOffset(w, h)
	t.Font = font
	t.TextSize = size
	t.TextColor3 = color
	t.Text = str
	t.TextTransparency = 0
	t.TextStrokeTransparency = 1
	t.TextWrapped = true
	t.TextXAlignment = align or Enum.TextXAlignment.Center
	t.TextYAlignment = Enum.TextYAlignment.Center
	t.Active = false
	t.ZIndex = z
	t.Parent = parent
	return t
end

-- Place a generated picture so its opaque part fills `slot`; the empty margin hangs outside, harmlessly transparent.
local function placeArt(parent, name, key, slot, z)
	local id, bb = Art[key], Look.bbox(key)
	if not id or not bb then return nil end
	local bw, bh = bb[3] - bb[1], bb[4] - bb[2]
	local fw, fh = slot.w / bw, slot.h / bh
	local img = Instance.new("ImageLabel")
	img.Name = name
	img.BackgroundTransparency = 1
	img.Image = id
	img.ScaleType = Enum.ScaleType.Stretch
	img.Position = UDim2.fromOffset(slot.x - bb[1] * fw, slot.y - bb[2] * fh)
	img.Size = UDim2.fromOffset(fw, fh)
	if Look.MIRROR[key] then -- flipped left to right with a negative source rect (the box above is already mirrored)
		img.ImageRectOffset = Vector2.new(Look.IMAGE_PX, 0)
		img.ImageRectSize = Vector2.new(-Look.IMAGE_PX, Look.IMAGE_PX)
	end
	img.Active = false
	img.ZIndex = z
	img.Parent = parent
	return img
end

local function parchment(parent, name, r, z, s)
	local f = frame(parent, name, r, z)
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, math.max(4, math.floor(10 * s))); c.Parent = f
	local st = Instance.new("UIStroke"); st.Color = PARCH_EDGE; st.Thickness = math.max(2, math.floor(3 * s)); st.Parent = f
	return f
end

local function plateButton(parent, name, r, label, size, z, onClick)
	local holder = Instance.new("Frame")
	holder.Name = name
	holder.BackgroundTransparency = 1
	holder.Position = UDim2.fromOffset(r.x, r.y)
	holder.Size = UDim2.fromOffset(r.w, r.h)
	holder.ZIndex = z
	holder.Parent = parent
	-- the equipped Card Set's own plate when it has one (same family as the table buttons); classic keeps the purple plate
	local kit = require(script.Parent.TavernKit)
	local setPiece = Style.resultPlate("primary", r.w, r.h, kit.plateSetId())
	if not setPiece then placeArt(holder, "Plate", "victory_button", { x = 0, y = 0, w = r.w, h = r.h }, z) end
	local b = Instance.new("TextButton")
	b.Name = "Press"
	b.BackgroundTransparency = 1
	b.Size = UDim2.fromScale(1, 1)
	b.Font = serif()
	b.TextSize = size
	b.TextColor3 = GOLD
	b.Text = label
	b.TextTransparency = 0
	b.TextStrokeTransparency = 0.4
	b.TextStrokeColor3 = PURPLE_DARK
	b.ZIndex = z + 1
	b.Parent = holder
	b.MouseButton1Click:Connect(onClick)
	if setPiece then
		b:SetAttribute("PaintW", r.w); b:SetAttribute("PaintH", r.h)
		pcall(function() kit.painted(b, setPiece) end)
	end
	return b
end

local function baseScene(screenGui, w, h, mode)
	if current and current.gui then current.gui:Destroy() end
	local L = Look.layout(w, h, mode)
	local gui = Instance.new("Frame")
	gui.Name = "VictoryBackdrop"
	gui.Size = UDim2.fromScale(1, 1)
	gui.BackgroundColor3 = PURPLE_DARK
	gui.BorderSizePixel = 0
	gui.Active = true -- sinks clicks so the table behind cannot be pressed
	gui.ZIndex = 62
	gui.Parent = screenGui
	if Art.victory_backdrop then
		local bg = Instance.new("ImageLabel")
		bg.Name = "Scene"
		bg.BackgroundTransparency = 1
		bg.Size = UDim2.fromScale(1, 1)
		bg.Image = Art.victory_backdrop
		bg.ScaleType = Enum.ScaleType.Crop
		pcall(function() -- the room picture wears 25 percent of the equipped Card Set's hue (classic unchanged)
			local TS = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("ThemeScenes"))
			local skin = require(script.Parent.HudTheme).skin()
			local t = TS.washTint(TS.effectiveSetId(skin and skin.id, nil), TS.RESULT_WASH_TINT)
			if t then bg.ImageColor3 = Color3.fromRGB(t[1], t[2], t[3]) end
		end)
		bg.ZIndex = 62
		bg.Parent = gui
	end
	pcall(function() require(script.Parent.ThemeWash).attach(gui, "shopBackdrop") end) -- the equipped Card Set dresses this scene (Engine/ThemeScenes)
	-- warm candle glow: two solid soft frames (never a Transparency gradient)
	for i, spot in ipairs(L.compactCards and {} or { L.heroGlow, L.chestGlow }) do -- each glow stands behind its own art (centred on it)
		local g = Instance.new("Frame")
		g.Name = "CandleGlow" .. i
		g.BorderSizePixel = 0
		g.BackgroundColor3 = Color3.fromRGB(255, 170, 70)
		g.BackgroundTransparency = 0.9
		g.AnchorPoint = Vector2.new(0.5, 0.5)
		g.Position = UDim2.fromOffset(spot.cx, spot.cy)
		g.Size = UDim2.fromOffset(spot.size, spot.size)
		g.Active = false
		g.ZIndex = 62
		local gc = Instance.new("UICorner"); gc.CornerRadius = UDim.new(0.5, 0); gc.Parent = g
		g.Parent = gui
	end
	local s = L.scale
	if not L.compactCards then -- a short window drops the keeper and the chest so the three cards and their 44 px buttons fit
		placeArt(gui, "Hero", "victory_hero", L.hero, 64)
		placeArt(gui, "Chest", "victory_chest", L.chest, 64)
	end
	placeArt(gui, "Banner", "victory_banner", L.banner, 65)
	local title = text(gui, "Title", mode == "pick" and "REWARD" or "VICTORY", Look.fontSize(60, s), GOLD, serif(), 66,
		L.title.x, L.title.y, L.title.w, L.title.h)
	title.TextStrokeTransparency = 0.3
	title.TextStrokeColor3 = PURPLE_DARK
	local sub = text(gui, "Subtitle", mode == "pick" and Look.SUBTITLE_PICK or Look.SUBTITLE_RUN, Look.fontSize(24, s), CREAM, serif(), 66,
		L.subtitle.x, L.subtitle.y, L.subtitle.w, L.subtitle.h)
	sub.TextStrokeTransparency = 0.4
	sub.TextStrokeColor3 = PURPLE_DARK
	return gui, L, s
end

local function rectsOf(gui)
	local out = {}
	for _, name in ipairs({ "Banner", "Hero", "Chest", "Rewards", "Summary", "Card1", "Card2", "Card3", "Continue", "Invite", "ShareLine", "Skip" }) do
		local d = gui:FindFirstChild(name)
		if d then out[#out + 1] = string.format("%s=%d,%d,%d,%d", name, d.AbsolutePosition.X, d.AbsolutePosition.Y, d.AbsoluteSize.X, d.AbsoluteSize.Y) end
	end
	return table.concat(out, " ")
end

local function announce(gui)
	if RunService:IsStudio() then print("[VictoryLook] " .. rectsOf(gui)) end
end

function M.hide()
	if current and current.gui then current.gui:Destroy() end
	current = nil
end

function M.hidePick()
	if current and current.kind == "pick" then M.hide() end
end

function M.show(screenGui, lines)
	if not screenGui or not lines then return end
	local size = screenGui.AbsoluteSize
	local gui, L, s = baseScene(screenGui, size.X, size.Y, "run")
	local summary = lines.summary or {}
	local zc = 66
	-- Rewards Earned
	local rw = parchment(gui, "Rewards", L.rewards, zc, s)
	text(rw, "Heading", "Rewards Earned", Look.fontSize(26, s), INK, serif(), zc + 1, 0, math.floor(8 * s), L.rewards.w, math.floor(40 * s))
	local cols = Look.rewardColumns(summary)
	local cw = L.rewards.w / #cols
	for i, c in ipairs(cols) do
		local x = (i - 1) * cw
		local coin = frame(rw, "Coin" .. i, { x = x + cw / 2 - 30 * s, y = 64 * s, w = 60 * s, h = 60 * s }, zc + 1, GOLD)
		local cc = Instance.new("UICorner"); cc.CornerRadius = UDim.new(0.5, 0); cc.Parent = coin
		local cs = Instance.new("UIStroke"); cs.Color = Color3.fromRGB(150, 100, 20); cs.Thickness = math.max(2, math.floor(3 * s)); cs.Parent = coin
		text(coin, "Mark", i == 1 and "T" or "*", Look.fontSize(28, s), COIN_INK, Enum.Font.GothamBold, zc + 2, 0, 0, 60 * s, 60 * s)
		text(rw, "Value" .. i, c.value, Look.fontSize(34, s), INK, serif(), zc + 1, x, 134 * s, cw, 44 * s)
		text(rw, "Label" .. i, c.label, Look.fontSize(22, s), INK, Enum.Font.GothamMedium, zc + 1, x, 180 * s, cw, 32 * s)
	end
	-- Run Summary
	local sm = parchment(gui, "Summary", L.summary, zc, s)
	text(sm, "Heading", "Run Summary", Look.fontSize(26, s), INK, serif(), zc + 1, 0, math.floor(6 * s), L.summary.w, math.floor(36 * s))
	local best = bestProvider and bestProvider() or nil
	local rows = Look.fitRows(Look.summaryRows(summary, best), size.X, size.Y)
	local rowH = (L.summary.h - 48 * s) / #rows
	for i, row in ipairs(rows) do
		local y = 46 * s + (i - 1) * rowH
		local rowFont = Look.rowSize(#rows)
		local rowSize = Look.fontSize(rowFont, s)
		local fitted = Look.fitRow(row, rowSize, L.summary.w) -- label and value never wider than the card minus 24 px (TextFit)
		local rowLabel = text(sm, "Row" .. i, fitted.label, rowSize, INK, Enum.Font.GothamMedium, zc + 1, 12, y, L.summary.w - 24, rowH, Enum.TextXAlignment.Left)
		local rowValue = text(sm, "Val" .. i, fitted.value, rowSize, INK, Enum.Font.GothamBold, zc + 1, 12, y, L.summary.w - 24, rowH, Enum.TextXAlignment.Right)
		rowLabel.TextWrapped, rowValue.TextWrapped = false, false
		if i < #rows then frame(sm, "Rule" .. i, { x = 14 * s, y = y + rowH - 1, w = L.summary.w - 28 * s, h = 1 }, zc + 1, PARCH_EDGE) end
	end
	local function close()
		M.hide()
	end
	text(gui, "NextStep", Look.NEXT_RUN, Look.fontSize(Look.NEXT_SIZE, s), CREAM, Enum.Font.GothamMedium, zc + 2, L.nextStep.x, L.nextStep.y, L.nextStep.w, L.nextStep.h)
	local btn = plateButton(gui, "Continue", L.button, L.compact and Look.CONTINUE_SHORT or Look.CONTINUE_TEXT, Look.fontSize(Look.CONTINUE_SIZE, s), zc + 2, close)
	btn.Parent.Name = "Continue"
	-- Invite a friend (Roblox's own invite sheet only) and a plain text share line to copy
	local inv = Instance.new("TextButton")
	inv.Name = "Invite"
	inv.Position = UDim2.fromOffset(L.invite.x, L.invite.y)
	inv.Size = UDim2.fromOffset(L.invite.w, L.invite.h)
	inv.BackgroundColor3 = PURPLE_DARK
	inv.BorderSizePixel = 0
	inv.Font = serif()
	inv.TextSize = Look.fontSize(20, s)
	inv.TextColor3 = GOLD
	inv.Text = L.compact and Look.INVITE_SHORT or Look.INVITE_TEXT
	inv.ZIndex = zc + 2
	inv.Parent = gui
	local ic = Instance.new("UICorner"); ic.CornerRadius = UDim.new(0, 10); ic.Parent = inv
	local ist = Instance.new("UIStroke"); ist.Color = GOLD; ist.Thickness = 2; ist.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; ist.Parent = inv
	pcall(function() require(script.Parent.InvitePrompt).bind(inv) end)
	pcall(function() require(script.Parent.PopupSkin).dark(inv, ist, { { inv, GOLD } }, { plate = PURPLE_DARK, edge = GOLD }) end) -- the equipped set's fill, edge and ink (7:1); classic keeps purple and gold
	local shareBox = Instance.new("TextBox")
	shareBox.Name = "ShareLine"
	shareBox.Position = UDim2.fromOffset(L.share.x, L.share.y)
	shareBox.Size = UDim2.fromOffset(L.share.w, L.share.h)
	shareBox.BackgroundColor3 = PURPLE_DARK
	shareBox.BackgroundTransparency = 0.2
	shareBox.BorderSizePixel = 0
	shareBox.Font = serif()
	shareBox.TextSize = Look.fontSize(16, s)
	shareBox.TextColor3 = GOLD
	shareBox.TextEditable = false
	shareBox.ClearTextOnFocus = false
	shareBox.TextTruncate = Enum.TextTruncate.AtEnd
	shareBox.Text = Look.shareLine(summary, best)
	shareBox.ZIndex = zc + 2
	shareBox.Parent = gui
	pcall(function() require(script.Parent.PopupSkin).dark(shareBox, nil, { { shareBox, GOLD } }, { plate = PURPLE_DARK }) end)
	local sc = Instance.new("UICorner"); sc.CornerRadius = UDim.new(0, 8); sc.Parent = shareBox
	shareBox.Focused:Connect(function()
		shareBox.SelectionStart = 1
		shareBox.CursorPosition = #shareBox.Text + 1
	end)
	pcall(function()
		require(script.Parent.PopupDismiss).attach(gui, { policy = "button", press = close, button = true })
	end)
	pcall(function() require(script.Parent.ResultGuard).hold(screenGui) end)
	if not calm() then pcall(function() require(script.Parent.ConfettiFX).burst(screenGui, true) end) end
	current = { gui = gui, kind = "run" }
	announce(gui)
end

function M.showPick(screenGui, choice, onPick, onSkip)
	if not screenGui or not choice then return end
	local size = screenGui.AbsoluteSize
	local key = tostring(choice.title) .. "|" .. #(choice.options or {})
	if current and current.kind == "pick" and current.key == key and current.gui.Parent then return end
	local gui, L, s = baseScene(screenGui, size.X, size.Y, "pick")
	local zc = 66
	local PatronPlaque = require(script.Parent.PatronPlaque)
	for i, option in ipairs(choice.options or {}) do
		local r = L.cards[i]
		if not r then break end
		local card = parchment(gui, "Card" .. i, r, zc, s)
		local compact = L.compactCards == true
		local tap = Look.MIN_TAP
		text(card, "Name", option.name or "", Look.fontSize(22, compact and 1 or s), INK, serif(), zc + 1, 6 * s, compact and 4 or 8 * s, r.w - 12 * s, compact and 28 or 32 * s)
		local lines = {}
		if option.line1 and option.line1 ~= "" then lines[#lines + 1] = option.line1 end
		if option.line2 and option.line2 ~= "" then lines[#lines + 1] = option.line2 end
		local ruleY, ruleH
		if compact then
			ruleY = 34
			ruleH = math.max(36, r.h - 34 - tap - 8)
		else
			local well = frame(card, "Well", { x = r.w / 2 - 38 * s, y = 44 * s, w = 76 * s, h = 76 * s }, zc + 1, PURPLE_DARK)
			local wc = Instance.new("UICorner"); wc.CornerRadius = UDim.new(0.5, 0); wc.Parent = well
			local ws = Instance.new("UIStroke"); ws.Color = PARCH_EDGE; ws.Thickness = math.max(2, math.floor(2 * s)); ws.Parent = well
			local icon = text(well, "Icon", option.icon or "", Look.fontSize(40, s), CREAM, Enum.Font.GothamBold, zc + 2, 0, 0, 76 * s, 76 * s)
			pcall(PatronPlaque.apply, well, option.id, { emojiLabel = icon, zIndex = zc + 3, cornerRadius = 38 * s })
			ruleY = 124 * s
			ruleH = math.max(40, math.min(62 * s, r.h - 8 - tap - 124 * s))
		end
		text(card, "Rule", table.concat(lines, "\n"), Look.fontSize(20, compact and 0.8 or s), INK, Enum.Font.GothamMedium, zc + 1, 8 * s, ruleY, r.w - 16 * s, ruleH)
		local pick = Instance.new("TextButton")
		pick.Name = "Pick"
		pick.Size = UDim2.fromOffset(r.w - 28 * s, tap)
		pick.Position = UDim2.fromOffset(14 * s, r.h - tap - 8)
		pick.BackgroundColor3 = PURPLE
		pick.BorderSizePixel = 0
		pick.Font = serif()
		pick.TextSize = Look.fontSize(22, s)
		pick.TextColor3 = GOLD
		pick.Text = "Choose"
		pick.ZIndex = zc + 2
		pick.Parent = card
		local pc = Instance.new("UICorner"); pc.CornerRadius = UDim.new(0, 8); pc.Parent = pick
		local ps = Instance.new("UIStroke"); ps.Color = GOLD; ps.Thickness = 2; ps.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; ps.Parent = pick
		pcall(function() require(script.Parent.PopupSkin).dark(pick, ps, { { pick, GOLD } }, { plate = PURPLE, edge = GOLD }) end)
		pick.MouseButton1Click:Connect(function() if onPick then onPick(option.id) end end)
	end
	if choice.skip then
		local btn = plateButton(gui, "Skip", L.button, "Skip", Look.fontSize(30, s), zc + 2, function() if onSkip then onSkip() end end)
		btn.Parent.Name = "Skip"
	end
	current = { gui = gui, kind = "pick", key = key }
	announce(gui)
end

function M.isUp() return current ~= nil and current.gui ~= nil and current.gui.Parent ~= nil end

return M
