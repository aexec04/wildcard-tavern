p = 'src/Client/ConceptTReference.lua'
s = open(p).read()


def rep(a, b):
    global s
    assert a in s, a[:60]
    s = s.replace(a, b)


rep('''local Patrons = require(Engine:WaitForChild("Patrons"))''', '''local Patrons = require(Engine:WaitForChild("Patrons"))
local CollectionBook = require(Engine:WaitForChild("CollectionBook"))''')
rep('''			if def.rarity == tier and CardArt["ctp_" .. def.id] then out[#out + 1] = def; break end''', '''			-- most Patrons have no rarity field: the game's own lookup (CollectionBook.rarityOf) gives the tier
			local ok, rar = pcall(CollectionBook.rarityOf, { tab = "patrons", id = def.id, def = def })
			if ok and rar == tier and CardArt["ctp_" .. def.id] then out[#out + 1] = def; break end''')
rep('''	local gui = Instance.new("ScreenGui")
	gui.Name = "ConceptTReference"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 1000
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	local size = gui.AbsoluteSize
	local r = Layout.rects(size.X, size.Y)''', '''	local screen = Instance.new("ScreenGui")
	screen.Name = "ConceptTReference"
	screen.IgnoreGuiInset = true
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 1000
	screen.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	-- black bars everywhere, the scene in the largest centred 3:2 frame (tools/pixel_match.py crops the bars off)
	local bars = Instance.new("Frame")
	bars.BackgroundColor3 = Color3.new(0, 0, 0)
	bars.BorderSizePixel = 0
	bars.Size = UDim2.fromScale(1, 1)
	bars.Parent = screen
	local fr = Layout.frameRect(screen.AbsoluteSize.X, screen.AbsoluteSize.Y)
	local gui = Instance.new("Frame")
	gui.Name = "Frame3x2"
	gui.BackgroundTransparency = 1
	gui.BorderSizePixel = 0
	gui.ClipsDescendants = true
	gui.Position = UDim2.fromOffset(fr.x, fr.y)
	gui.Size = UDim2.fromOffset(fr.w, fr.h)
	gui.Parent = screen
	local size = { X = fr.w, Y = fr.h }
	local r = Layout.rects(size.X, size.Y)''')
rep('at(label(gui, tostring(S.coins), 20, 3), r.coins)', 'at(label(gui, tostring(S.coins), 20, 3), Layout.textRect(r.coins, "coins"))')
rep('at(label(gui, tostring(S.hands), 20, 3), r.hands)', 'at(label(gui, tostring(S.hands), 20, 3), Layout.textRect(r.hands, "hands"))')
rep('at(label(gui, "Round " .. S.round, 18, 3), { x = r.round.x, y = r.round.y, w = r.round.w, h = math.floor(r.round.h * 0.58) })', 'at(label(gui, "Round " .. S.round, 18, 3), Layout.textRect(r.round, "round"))')
rep('at(label(gui, S.deck, 18, 3), r.deckCount)', 'at(label(gui, S.deck, 18, 3), Layout.textRect(r.deckCount, "deckCount"))')
rep('"ct_deck", 2)', '"ct_deck_a", 2)')
rep('"ct_btn_play", 2)', '"ct_btn_play_a", 2)')
rep('"ct_btn_discard", 2)', '"ct_btn_discard_a", 2)')
rep('img(gui, Layout.pillKey(tier), 3)', 'img(gui, Layout.blankPillKey(tier), 3)')
rep('local t = label(pill, S.pills[i], 15, 4)', 'local t = label(pill, Layout.cleanValue(S.pills[i]), 15, 4)')
a = s.index('	local ring = Instance.new("Frame")')
b = s.index('	local nm = label(gui, S.stage.name')
s = s[:a] + '''	local ringW = math.floor(size.X * 0.26)
	local ring = img(gui, "ct_glow_ring", 2)
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromOffset(st.x + st.w / 2, st.y + math.floor(st.h * 0.74))
	ring.Size = UDim2.fromOffset(ringW, math.floor(ringW / 3))
''' + s[b:]
a = s.index('	local hand = r.hand')
b = s.index('	return gui\nend')
s = s[:a] + '''	local hand = r.hand
	local cw = math.floor(size.X * 0.0977)
	local ch = math.floor(cw * 1.43)
	local n = #S.hand
	local step = (hand.w - cw) / (n - 1)
	local baseY = hand.y + hand.h + math.floor(size.Y * 0.03)
	for i, c in ipairs(S.hand) do
		local rot, dip = Layout.fan(i, n)
		local b = Instance.new("TextButton")
		b.Text = ""
		b.BackgroundColor3 = Color3.fromRGB(246, 238, 214)
		b.AutoButtonColor = false
		b.ZIndex = 5 + i * 2 -- left to right, each above the one before, all above the Play and Discard art
		b.AnchorPoint = Vector2.new(0.5, 1)
		b.Position = UDim2.fromOffset(math.floor(hand.x + cw / 2 + step * (i - 1)), baseY + math.floor(dip * size.Y * Layout.FAN.dipFrac))
		b.Size = UDim2.fromOffset(cw, ch)
		b.Rotation = rot
		b.Parent = gui
		pcall(function() CardFace.build(b, c[1], c[2], c[3], 6 + i * 2, false, nil) end)
	end
	return screen
end
''' + s[b + len('	return gui\nend\n'):]
open(p, 'w').write(s)
