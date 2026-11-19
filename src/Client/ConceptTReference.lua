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

local M = {}

M.SCENE = {
	round = 3, progress = 0.83, coins = 126, hands = 2, deck = "37/52",
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
			if def.rarity == tier and CardArt["ctp_" .. def.id] then out[#out + 1] = def; break end
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
	local gui = Instance.new("ScreenGui")
	gui.Name = "ConceptTReference"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 1000
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	local size = gui.AbsoluteSize
	local r = Layout.rects(size.X, size.Y)
	local S = M.SCENE

	at(img(gui, "ct_table_room", 0), { x = 0, y = 0, w = size.X, h = size.Y })
	at(img(gui, "ct_hud_coins", 2), r.coins); at(label(gui, tostring(S.coins), 20, 3), r.coins)
	at(img(gui, "ct_hud_hands", 2), r.hands); at(label(gui, tostring(S.hands), 20, 3), r.hands)
	at(img(gui, "ct_hud_round", 2), r.round)
	at(label(gui, "Round " .. S.round, 18, 3), { x = r.round.x, y = r.round.y, w = r.round.w, h = math.floor(r.round.h * 0.58) })
	local bar = Layout.bar(r)
	local fill = Instance.new("Frame")
	fill.BackgroundColor3 = Color3.fromRGB(246, 196, 70)
	fill.BorderSizePixel = 0
	fill.ZIndex = 3
	fill.Position = UDim2.fromOffset(bar.x, bar.y)
	fill.Size = UDim2.fromOffset(math.floor(bar.w * S.progress), bar.h)
	fill.Parent = gui
	at(img(gui, "ct_hud_gear", 2), r.gear)
	at(img(gui, "ct_deck", 2), r.deck)
	at(img(gui, "ct_deck_count", 2), r.deckCount); at(label(gui, S.deck, 18, 3), r.deckCount)
	at(img(gui, "ct_btn_play", 2), r.play)
	at(img(gui, "ct_btn_discard", 2), r.discard)

	-- five Patron cards, centred in the Patron row, each with its rarity label and effect pill
	local pats = pickPatrons()
	local p = r.patrons
	local cardH = math.floor(p.h * 0.70)
	local cardW = math.floor(cardH * 2 / 3)
	local gap = math.floor((p.w - cardW * 5) / 6)
	for i = 1, 5 do
		local x, tier = p.x + gap * i + cardW * (i - 1), S.tiers[i]
		local card = Instance.new("ImageLabel")
		card.BackgroundTransparency = 1
		card.ScaleType = Enum.ScaleType.Fit
		card.ZIndex = 3
		card.Image = pats[i] and CardArt["ctp_" .. pats[i].id] or ""
		at(card, { x = x, y = p.y, w = cardW, h = cardH })
		card.Parent = gui
		local lab = img(gui, Layout.labelKey(tier), 3)
		at(lab, { x = x, y = p.y + cardH + 2, w = cardW, h = 22 })
		local pill = img(gui, Layout.pillKey(tier), 3)
		at(pill, { x = x, y = p.y + cardH + 26, w = cardW, h = 26 })
		local t = label(pill, S.pills[i], 15, 4)
		t.Size = UDim2.fromScale(1, 1)
	end

	-- the scoring stage: hand name, big gold total over a glow ring
	local st = r.stage
	local ring = Instance.new("Frame")
	ring.BackgroundColor3 = Color3.fromRGB(246, 196, 70)
	ring.BackgroundTransparency = 0.7
	ring.ZIndex = 2
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromOffset(st.x + st.w / 2, st.y + st.h / 2)
	ring.Size = UDim2.fromOffset(st.h * 1.6, st.h * 1.6)
	ring.Parent = gui
	local rc = Instance.new("UICorner"); rc.CornerRadius = UDim.new(1, 0); rc.Parent = ring
	local nm = label(gui, S.stage.name, 22, 4); at(nm, { x = st.x, y = st.y, w = st.w, h = math.floor(st.h * 0.3) })
	local tot = label(gui, S.stage.total, 54, 4, Color3.fromRGB(246, 196, 70)); at(tot, { x = st.x, y = st.y + math.floor(st.h * 0.3), w = st.w, h = math.floor(st.h * 0.7) })

	-- the fanned hand of seven, drawn through the game's own card face
	local CardFace = require(script.Parent.CardFace)
	local hand = r.hand
	local cw = math.floor(hand.h * 0.62)
	local ch = hand.h
	local step = math.floor((hand.w - cw) / 6)
	for i, c in ipairs(S.hand) do
		local b = Instance.new("TextButton")
		b.Text = ""
		b.BackgroundColor3 = Color3.fromRGB(246, 238, 214)
		b.AutoButtonColor = false
		b.ZIndex = 5 + i
		b.AnchorPoint = Vector2.new(0.5, 1)
		local mid = (i - 4)
		b.Position = UDim2.fromOffset(hand.x + cw / 2 + step * (i - 1), hand.y + hand.h + math.abs(mid) * 4)
		b.Size = UDim2.fromOffset(cw, ch)
		b.Rotation = mid * 3
		b.Parent = gui
		pcall(function() CardFace.build(b, c[1], c[2], c[3], 6 + i, false, nil) end)
	end
	return gui
end

return M
