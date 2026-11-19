--[[
	Client/ConceptTReference.lua
	STUDIO ONLY debug scene that matches claude/reference/concept_t/full_reference.png so the play screen can be compared with
	tools/pixel_match.py. It never ships (show() does nothing outside Studio), builds its own ScreenGui, and never touches the run
	state, the server or any saved data.

	HOW TO RUN (Studio, press Play, command bar with the client context selected, so the Output filter shows "Client"):
	  require(game.Players.LocalPlayer.PlayerScripts.Client.ConceptTReference).show()
	Set the Game window to 1536 x 1024 (or any 3:2 size), take a screenshot, then run  python3 tools/pixel_match.py <screenshot.png>.
	hide() removes the scene.

	Scene: Round 3, gold bar at 83 percent, coins 126, hands 2, five Patrons (one per rarity, the first with a Concept T cut card;
	the reference names are not in the Patron registry, so the nearest by rarity are used) with effect pills +30, +30, +30, +4, +4,
	a hand of seven (A of spades, K of hearts, Q of hearts, 9 of clubs, 9 of clubs, 6 of diamonds, 2 of spades) fanned, the scoring
	stage "Full House" and 310 over a gold glow ring, deck 37 / 52.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Engine = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Engine")
local Layout = require(Engine:WaitForChild("ConceptTLayout"))
local Art = require(Engine:WaitForChild("ConceptTArt"))
local CardArt = require(Engine:WaitForChild("ConceptTPatronArt"))
local Patrons = require(Engine:WaitForChild("Patrons"))
local CollectionBook = require(Engine:WaitForChild("CollectionBook"))

local M = {}

M.SCENE = {
	round = 3, progress = 0.83, coins = 126, hands = 2, deck = "37 / 52",
	pills = { "+30", "+30", "+30", "+4", "+4" },
	tiers = { "common", "uncommon", "rare", "epic", "legendary" },
	hand = { { "A", "♠", false }, { "K", "♥", true }, { "Q", "♥", true }, { "9", "♣", false }, { "9", "♣", false }, { "6", "♦", true }, { "2", "♠", false } },
	stage = { name = "Full House", total = "310" },
}

local function img(parent, key, z)
	local i = Instance.new("ImageLabel")
	i.BackgroundTransparency = 1
	i.BorderSizePixel = 0
	i.Image = Art[key] or ""
	i.ZIndex = z
	i.Parent = parent
	return i
end

local function label(parent, text, size, z, color)
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Text = text
	t.Font = Enum.Font.GothamBlack
	t.TextSize = size
	t.TextColor3 = color or Color3.fromRGB(255, 244, 214)
	t.TextTransparency = 0
	t.TextStrokeColor3 = Color3.fromRGB(40, 22, 10)
	t.TextStrokeTransparency = 0.2
	t.ZIndex = z
	t.Parent = parent
	return t
end

local function at(g, r)
	g.Position = UDim2.fromOffset(r.x, r.y)
	g.Size = UDim2.fromOffset(r.w, r.h)
end

-- one Patron per rarity that has a cut card, in the order of the reference
local function pickPatrons()
	local out = {}
	for _, tier in ipairs(M.SCENE.tiers) do
		for _, def in ipairs(Patrons.Definitions) do
			-- most Patrons have no rarity field: the game's own lookup (CollectionBook.rarityOf) gives the tier
			local ok, rar = pcall(CollectionBook.rarityOf, { tab = "patrons", id = def.id, def = def })
			if ok and rar == tier and CardArt["ctp_" .. def.id] then out[#out + 1] = def; break end
		end
	end
	return out
end

function M.hide()
	local pg = Players.LocalPlayer and Players.LocalPlayer:FindFirstChild("PlayerGui")
	local old = pg and pg:FindFirstChild("ConceptTReference")
	if old then old:Destroy() end
end

function M.show()
	if not RunService:IsStudio() then return nil end
	M.hide()
	local screen = Instance.new("ScreenGui")
	screen.Name = "ConceptTReference"
	screen.IgnoreGuiInset = true
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 1000
	screen.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	-- the scene in the largest centred 3:2 frame; four black bar frames only OUTSIDE it (a full-screen black frame hid the room)
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	local sw, sh = screen.AbsoluteSize.X, screen.AbsoluteSize.Y
	local fr = Layout.frameRect(sw, sh)
	for i, b in ipairs({
		{ 0, 0, sw, fr.y }, { 0, fr.y + fr.h, sw, sh - fr.y - fr.h },
		{ 0, fr.y, fr.x, fr.h }, { fr.x + fr.w, fr.y, sw - fr.x - fr.w, fr.h },
	}) do
		local bar = Instance.new("Frame")
		bar.Name = "Bar" .. i
		bar.BackgroundColor3 = Color3.new(0, 0, 0)
		bar.BorderSizePixel = 0
		bar.Position = UDim2.fromOffset(b[1], b[2])
		bar.Size = UDim2.fromOffset(math.max(0, b[3]), math.max(0, b[4]))
		bar.Parent = screen
	end
	local gui = Instance.new("Frame")
	gui.Name = "Frame3x2"
	gui.BackgroundColor3 = Color3.fromRGB(92, 36, 0)
	gui.BackgroundTransparency = 0
	gui.BorderSizePixel = 0
	gui.ClipsDescendants = true
	gui.Position = UDim2.fromOffset(fr.x, fr.y)
	gui.Size = UDim2.fromOffset(fr.w, fr.h)
	gui.Parent = screen
	local size = { X = fr.w, Y = fr.h }
	local r = Layout.rects(size.X, size.Y)
	local S = M.SCENE

	local room = img(gui, "ct_table_room", 1); room.Name = "Room"
	at(room, { x = 0, y = 0, w = size.X, h = size.Y })
	print(string.format("[ConceptTReference] room abs=%d,%d size=%dx%d image=%s", room.AbsolutePosition.X, room.AbsolutePosition.Y, room.AbsoluteSize.X, room.AbsoluteSize.Y, room.Image))
	at(img(gui, "ct_hud_coins", 2), r.coins); at(label(gui, tostring(S.coins), Layout.textSize("coins", size.Y), 3), Layout.textRect(r.coins, "coins"))
	at(img(gui, "ct_hud_hands", 2), r.hands); at(label(gui, tostring(S.hands), Layout.textSize("hands", size.Y), 3), Layout.textRect(r.hands, "hands"))
	at(img(gui, "ct_hud_round", 2), r.round)
	local rt = label(gui, "Round " .. S.round, Layout.textSize("round", size.Y), 3, Color3.fromRGB(Layout.ROUND_TEXT.r, Layout.ROUND_TEXT.g, Layout.ROUND_TEXT.b))
	rt.FontFace = Font.new("rbxasset://fonts/families/Merriweather.json", Enum.FontWeight.Bold) -- warm cream serif like the reference
	rt.TextStrokeTransparency = 0.6
	at(rt, Layout.textRect(r.round, "round"))
	local bar = Layout.bar(r)
	local fill = Instance.new("Frame")
	fill.BackgroundColor3 = Color3.fromRGB(246, 196, 70)
	fill.BorderSizePixel = 0
	fill.ZIndex = 3
	fill.Position = UDim2.fromOffset(bar.x, bar.y)
	fill.Size = UDim2.fromOffset(math.floor(bar.w * S.progress), bar.h)
	fill.Parent = gui
	local fcorner = Instance.new("UICorner"); fcorner.CornerRadius = UDim.new(1, 0); fcorner.Parent = fill
	local fgrad = Instance.new("UIGradient"); fgrad.Rotation = 90 -- Color only, never Transparency
	fgrad.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 226, 120)), ColorSequenceKeypoint.new(0.5, Color3.fromRGB(246, 196, 70)), ColorSequenceKeypoint.new(1, Color3.fromRGB(214, 150, 40)) })
	fgrad.Parent = fill
	at(img(gui, "ct_hud_gear", 2), r.gear)
	at(img(gui, "ct_deck_a", 2), r.deck)
	at(img(gui, "ct_deck_count", 2), r.deckCount); at(label(gui, S.deck, Layout.textSize("deckCount", size.Y), 3), Layout.textRect(r.deckCount, "deckCount"))
	at(img(gui, "ct_btn_play_a", 2), r.play)
	at(img(gui, "ct_btn_discard_a", 2), r.discard)

	-- five Patron cards, centred in the Patron row, each with its rarity label and effect pill
	local pats = pickPatrons()
	local slots = Layout.patronSlots(size.X, size.Y, 5)
	for i = 1, 5 do
		local tier, sl = S.tiers[i], slots[i]
		local card = Instance.new("ImageLabel")
		card.BackgroundTransparency = 1
		card.ScaleType = Enum.ScaleType.Fit
		card.ZIndex = 3
		-- the exact reference cut (alpha corners, scene only); the registry card is the fallback
		card.Image = Art["ct_ref_patron_" .. i] or (pats[i] and CardArt["ctp_" .. pats[i].id]) or ""
		at(card, sl.card)
		card.Parent = gui
		local lab = img(gui, Layout.labelKey(tier), 3)
		at(lab, sl.label)
		local pill = img(gui, Layout.blankPillKey(tier), 3)
		at(pill, sl.pill)
		local t = label(pill, Layout.cleanValue(S.pills[i]), math.max(15, Layout.textSize("pill", size.Y)), 4)
		t.Size = UDim2.fromScale(1, 1)
	end

	-- the scoring stage: hand name (white, outlined), big bright gold total (dark outline) over the glow plate with its bright rim
	-- positions measured from the reference: name centre y 0.571, total centre y 0.630, rim centre y 0.646, rim 0.206 wide
	local st = r.stage
	local cx = st.x + st.w / 2
	local ringW = math.floor(size.X * 0.27)
	local ringH = math.floor(ringW * 340 / 1024)
	local ring = img(gui, "ct_glow_ring", 2)
	ring.Position = UDim2.fromOffset(math.floor(cx - ringW / 2), math.floor(size.Y * 0.646 - ringH * 0.66))
	ring.Size = UDim2.fromOffset(ringW, ringH)
	ring.Parent = gui
	local nameH, totH = math.floor(size.Y * 0.05), math.floor(size.Y * 0.09)
	local nm = label(gui, S.stage.name, math.max(15, math.floor(size.Y * 0.036)), 4, Color3.fromRGB(255, 250, 235))
	nm.TextStrokeTransparency = 0
	nm.Position = UDim2.fromOffset(st.x, math.floor(size.Y * 0.571 - nameH / 2)); nm.Size = UDim2.fromOffset(st.w, nameH)
	local tot = label(gui, S.stage.total, math.max(15, math.floor(size.Y * 0.075)), 4, Color3.fromRGB(246, 196, 70))
	tot.TextStrokeColor3 = Color3.fromRGB(60, 30, 8); tot.TextStrokeTransparency = 0
	tot.Position = UDim2.fromOffset(st.x, math.floor(size.Y * 0.630 - totH / 2)); tot.Size = UDim2.fromOffset(st.w, totH)

	-- the fanned hand of seven, drawn through the game's own card face
	local CardFace = require(script.Parent.CardFace)
	local FaceArt = require(Engine:WaitForChild("CardFaceArt"))
	local hand = r.hand
	local cw = math.floor(size.X * 0.098)
	local ch = math.floor(cw * 1.43)
	local n = #S.hand
	local step = (hand.w - cw) / (n - 1)
	-- the middle card bottoms sit on the hand frame bottom (0.874 of the frame in the reference), the outer cards dip below it
	local baseY = hand.y + hand.h
	for i, c in ipairs(S.hand) do
		local rot, dip = Layout.fan(i, n)
		local b = Instance.new("TextButton")
		b.Text = ""
		b.BackgroundColor3 = Color3.fromRGB(table.unpack(FaceArt.PARCHMENT.base)) -- warm parchment, the same base the real hand uses
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

return M
