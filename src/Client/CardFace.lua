--[[
	Client/CardFace.lua
	REFERENCE-MATCH PASS (Nov 1 2026): the playing-card face layout and the
	dark "tray" the hand sits in, matching the reference mockup.

	Before this, every card showed its rank and suit as ONE centered
	two-line label ("A\n♥") at 70x100px, with no tray behind the hand. The
	reference shows a real card layout: rank in the top-left corner with a
	small suit under it, a big suit in the middle, a small suit in the
	bottom-right corner, bigger cards, and a gold-rimmed dark tray behind
	the whole hand.

	Required inline (function-scoped) from init.client.lua, never as a new
	top-level local -- that file is right at Lua's 200-local ceiling.

	CardFace.build(button, rankText, suitText, isRed, zIndex, hiddenWildcard)
		Builds (or rebuilds) a "CardFace" Frame inside `button` holding the
		corner/center labels. Everything lives under one named Frame so a
		cloned ghost (ScorePopup's scoring choreography) can swap it out
		cleanly with one Destroy + rebuild.

	CardFace.layoutHand(handFrame)
		Sizes every card slot to fit the space available (cards shrink on
		a narrow window instead of overflowing) and positions the tray
		behind them. Safe to call any time; also re-runs itself whenever
		handFrame's on-screen size/position changes.
]]

local CardFace = {}

local SERIF = "rbxasset://fonts/families/Merriweather.json"
local RED_INK = Color3.fromRGB(140, 34, 30) -- muted brick red
local BLACK_INK = Color3.fromRGB(60, 40, 22) -- warm ink, same family as the parchment board
local WILDCARD_INK = Color3.fromRGB(150, 110, 230)
local MYSTERY_BACK = Color3.fromRGB(226, 212, 244) -- lavender card back
local MYSTERY_INK = Color3.fromRGB(50, 20, 90) -- dark purple, about 10:1 on the back
local GOLD = Color3.fromRGB(205, 170, 95)

-- Settings > Display > Colorblind Suits: one ink per suit (keyed by the
-- symbol CardFace is handed) plus a suit letter in the top-right corner,
-- so suits differ by color AND a second shape cue, not just red/black.
local SuitMarks = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("Accessibility")).SuitMarks
local Accessibility = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("Accessibility"))
local CosmeticSets = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("CosmeticSets"))
local COLORBLIND_INK, SUIT_LETTER = {}, {}
for _, m in pairs(SuitMarks) do
	COLORBLIND_INK[m.glyph] = Color3.fromRGB(m.ink[1], m.ink[2], m.ink[3])
	SUIT_LETTER[m.glyph] = m.letter
end

local ClientSettings = require(script.Parent.ClientSettings)
local HandSizing = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("HandSizing"))

-- Every face built so far, so they can be redrawn when the setting flips.
local builtFaces = setmetatable({}, { __mode = "k" }) -- [button] = args

local CARD_ASPECT = 1.45 -- height / width, matches the reference cards
local MAX_CARD_WIDTH = 114 -- 19 percent larger than the old 96; PlayTableLayout.HAND_H is 200 to hold it
local MIN_CARD_WIDTH = 48
local CARD_GAP = 6 -- equals the hub hand UIListLayout padding
local TRAY_PAD = 16

local function makeLabel(parent, name, text, color, size, position, anchor, xAlign, zIndex)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Size = size
	label.Position = position
	label.AnchorPoint = anchor or Vector2.new(0, 0)
	label.FontFace = Font.new(SERIF, Enum.FontWeight.Bold)
	label.TextScaled = true
	label.TextColor3 = color
	label.TextXAlignment = xAlign or Enum.TextXAlignment.Center
	label.Text = text
	label.ZIndex = zIndex
	label.Parent = parent
	-- TextScaled alone shrank the corner index to about 8 px; keep it readable
	local limit = Instance.new("UITextSizeConstraint")
	limit.MinTextSize = 18
	limit.MaxTextSize = 60
	limit.Parent = label
	return label
end

-- Equipped Cosmetic Set treatment (CosmeticSets.faceStyleOf): { neutral = true } or
-- { paper, border, pip, foil }. Set by CosmeticSetsView; every live face is redrawn on change.
local setFace = nil
local setDef = nil -- the equipped set definition, for Colorblind Suits ink contrast

local function rgb(t)
	return Color3.fromRGB(t[1], t[2], t[3])
end

-- Low-strength set layers under the corner/centre labels: a paper wash, a thin inset border, optional foil sheen.
local foilLog = { done = false }
local function addSetLayers(face, zIndex, rankText)
	pcall(require(script.Parent.SetSkin).cardLayers, face, zIndex, rankText) -- set art: paper tile, court ornament, frame
	if not setFace or setFace.neutral then return end
	local wash = Instance.new("Frame")
	wash.Name = "SetPaper"
	wash.Size = UDim2.fromScale(1, 1)
	wash.BackgroundColor3 = rgb(setFace.paper)
	wash.BackgroundTransparency = 1 - 0.10 -- the set's paper colour tints the ivory face 10 percent (CosmeticSets.cardLook)
	wash.BorderSizePixel = 0
	wash.Active = false
	wash.ZIndex = zIndex
	wash.Parent = face
	local washCorner = Instance.new("UICorner")
	washCorner.CornerRadius = UDim.new(0, 6)
	washCorner.Parent = wash

	local edge = Instance.new("Frame")
	edge.Name = "SetBorder"
	edge.AnchorPoint = Vector2.new(0.5, 0.5)
	edge.Position = UDim2.fromScale(0.5, 0.5)
	edge.Size = UDim2.fromScale(0.9, 0.93)
	edge.BackgroundTransparency = 1
	edge.BorderSizePixel = 0
	edge.Active = false
	edge.ZIndex = zIndex
	edge.Parent = face
	local edgeCorner = Instance.new("UICorner")
	edgeCorner.CornerRadius = UDim.new(0, 5)
	edgeCorner.Parent = edge
	local edgeStroke = Instance.new("UIStroke")
	edgeStroke.Color = rgb(setFace.border)
	edgeStroke.Thickness = 1
	edgeStroke.Transparency = 0
	edgeStroke.Parent = edge
	-- corner pips in the set accent, so the set reads even where the thin edge is small
	for _, pos in ipairs({ { 0.07, 0.05 }, { 0.93, 0.05 }, { 0.07, 0.95 }, { 0.93, 0.95 } }) do
		local pip = Instance.new("Frame")
		pip.Name = "SetPip"
		pip.AnchorPoint = Vector2.new(0.5, 0.5)
		pip.Position = UDim2.fromScale(pos[1], pos[2])
		pip.Size = UDim2.fromOffset(4, 4)
		pip.BackgroundColor3 = rgb(setFace.border)
		pip.BorderSizePixel = 0
		pip.Active = false
		pip.ZIndex = zIndex
		pip.Parent = face
		local pc = Instance.new("UICorner")
		pc.CornerRadius = UDim.new(1, 0)
		pc.Parent = pip
	end
	if setFace.motif == "frost" then -- ice sets: a pale second edge just inside the first
		local frost = Instance.new("Frame")
		frost.Name = "SetFrost"
		frost.AnchorPoint = Vector2.new(0.5, 0.5)
		frost.Position = UDim2.fromScale(0.5, 0.5)
		frost.Size = UDim2.fromScale(0.84, 0.88)
		frost.BackgroundTransparency = 1
		frost.BorderSizePixel = 0
		frost.Active = false
		frost.ZIndex = zIndex
		frost.Parent = face
		local fs = Instance.new("UIStroke")
		fs.Color = Color3.fromRGB(235, 246, 255)
		fs.Thickness = 1
		fs.Transparency = 0.35
		fs.Parent = frost
	end

	if setFace.foil then
		local foil = Instance.new("Frame") -- a still diagonal sheen, stacked frames only
		foil.Name = "SetFoil"
		foil.AnchorPoint = Vector2.new(0.5, 0.5)
		foil.Position = UDim2.fromScale(0.62, 0.5)
		foil.Size = UDim2.fromScale(0.14, 0.9) -- short enough to sit fully inside the card at 22 degrees (Roblox ignores clipping of rotated children)
		foil.Rotation = 22
		foil.BackgroundColor3 = Color3.fromRGB(255, 244, 200)
		foil.BackgroundTransparency = 0.86
		foil.BorderSizePixel = 0
		foil.Active = false
		foil.ZIndex = zIndex
		foil.Parent = wash
		local ok, studio = pcall(function() return game:GetService("RunService"):IsStudio() end)
		if ok and studio and not foilLog.done then
			foilLog.done = true
			print("[CardFoil] clipped=1 size=0.14x0.90 inside=true")
		end
	end
	wash.ClipsDescendants = true
end

-- The universal pattern for special cards (Engine/SpecialPatterns): a round corner seal with the modifier's
-- glyph and an edge treatment (border, steel with rivets, or a foil sheen), drawn the same on every card face
-- everywhere, tinted 20 percent by the equipped Card Set's accent. UI shapes only.
local SpecialPatterns = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Engine"):WaitForChild("SpecialPatterns"))
local SEAL_POS = {
	tr = { Vector2.new(1, 0), UDim2.fromScale(0.97, 0.03) },
	bl = { Vector2.new(0, 1), UDim2.fromScale(0.03, 0.97) },
	br = { Vector2.new(1, 1), UDim2.fromScale(0.97, 0.97) },
}

local function addSpecialLayers(face, card, zIndex)
	if not SpecialPatterns.hasSpecial(card) then return end
	local accent = setFace and not setFace.neutral and setFace.border or nil
	for _, p in ipairs(SpecialPatterns.patternsFor(card)) do
		local c = rgb(SpecialPatterns.tinted(p.color, accent))
		if p.edge ~= "none" then
			local edge = Instance.new("Frame")
			edge.Name = "SpecialEdge_" .. p.kind
			edge.AnchorPoint = Vector2.new(0.5, 0.5)
			edge.Position = UDim2.fromScale(0.5, 0.5)
			edge.Size = UDim2.fromScale(p.edge == "steel" and 0.98 or 0.94, p.edge == "steel" and 0.985 or 0.96)
			edge.BackgroundTransparency = 1
			edge.BorderSizePixel = 0
			edge.Active = false
			edge.ZIndex = zIndex + 1
			edge.ClipsDescendants = true
			edge.Parent = face
			local ec = Instance.new("UICorner")
			ec.CornerRadius = UDim.new(0, 5)
			ec.Parent = edge
			local st = Instance.new("UIStroke")
			st.Color = c
			st.Thickness = p.edge == "steel" and 3 or 2
			st.Transparency = 0.1
			st.Parent = edge
			if p.edge == "foil" then
				local sheen = Instance.new("Frame") -- a still diagonal sheen in the modifier's colour
				sheen.AnchorPoint = Vector2.new(0.5, 0.5)
				sheen.Position = UDim2.fromScale(0.45, 0.5)
				sheen.Size = UDim2.fromScale(0.2, 0.85)
				sheen.Rotation = 24
				sheen.BackgroundColor3 = c
				sheen.BackgroundTransparency = 0.78
				sheen.BorderSizePixel = 0
				sheen.Active = false
				sheen.ZIndex = zIndex + 1
				sheen.Parent = edge
			elseif p.rivets then
				for _, pos in ipairs({ { 0.05, 0.04 }, { 0.95, 0.04 }, { 0.05, 0.96 }, { 0.95, 0.96 } }) do
					local rivet = Instance.new("Frame")
					rivet.AnchorPoint = Vector2.new(0.5, 0.5)
					rivet.Position = UDim2.fromScale(pos[1], pos[2])
					rivet.Size = UDim2.fromOffset(5, 5)
					rivet.BackgroundColor3 = Color3.fromRGB(205, 212, 225)
					rivet.BorderSizePixel = 0
					rivet.Active = false
					rivet.ZIndex = zIndex + 2
					rivet.Parent = edge
					local rc = Instance.new("UICorner")
					rc.CornerRadius = UDim.new(0.5, 0)
					rc.Parent = rivet
				end
			end
		end
		local where = SEAL_POS[p.corner] or SEAL_POS.tr
		local seal = Instance.new("Frame")
		seal.Name = "SpecialSeal_" .. p.kind
		seal.AnchorPoint = where[1]
		seal.Position = where[2]
		seal.Size = UDim2.fromScale(0.3, 0.3)
		seal.BackgroundColor3 = c
		seal.BorderSizePixel = 0
		seal.Active = false
		seal.ZIndex = zIndex + 3
		seal.Parent = face
		local ar = Instance.new("UIAspectRatioConstraint")
		ar.AspectRatio = 1
		ar.Parent = seal
		local sc = Instance.new("UICorner")
		sc.CornerRadius = UDim.new(0.5, 0)
		sc.Parent = seal
		local ss = Instance.new("UIStroke")
		ss.Color = Color3.fromRGB(40, 28, 18)
		ss.Thickness = 1.5
		ss.Parent = seal
		local g = Instance.new("TextLabel")
		g.Size = UDim2.fromScale(1, 1)
		g.BackgroundTransparency = 1
		g.Font = Enum.Font.GothamBlack
		g.TextScaled = true
		g.TextColor3 = Color3.fromRGB(30, 22, 16)
		g.Text = p.glyph
		g.ZIndex = zIndex + 4
		g.Parent = seal
		local pad = Instance.new("UIPadding")
		pad.PaddingTop = UDim.new(0.18, 0)
		pad.PaddingBottom = UDim.new(0.18, 0)
		pad.PaddingLeft = UDim.new(0.12, 0)
		pad.PaddingRight = UDim.new(0.12, 0)
		pad.Parent = g
	end
end

function CardFace.setStyle(face, set)
	setFace = face
	setDef = set
	for button, args in pairs(builtFaces) do
		if button.Parent then
			CardFace.build(button, args[1], args[2], args[3], args[4], false, args[5])
		else
			builtFaces[button] = nil
		end
	end
end

function CardFace.build(button, rankText, suitText, isRed, zIndex, hiddenWildcard, card)
	builtFaces[button] = nil -- re-registered below unless this is a hidden wildcard
	local old = button:FindFirstChild("CardFace")
	if old then
		old:Destroy()
	end

	local face = Instance.new("Frame")
	face.Name = "CardFace"
	face.Size = UDim2.fromScale(1, 1)
	face.BackgroundTransparency = 1
	face.ZIndex = zIndex
	face.Parent = button

	if hiddenWildcard then
		-- A full card of its own (the hand shows only this): lavender back, gold border, purple diamond pattern, dark purple ink
		-- (about 10:1 on the back). It never shows the rank or suit.
		local base = Instance.new("Frame")
		base.Name = "MysteryBase"
		base.Size = UDim2.fromScale(1, 1)
		base.BackgroundColor3 = MYSTERY_BACK
		base.BorderSizePixel = 0
		base.ZIndex = zIndex
		base.Active = false
		base.Parent = face
		local bc = Instance.new("UICorner"); bc.CornerRadius = UDim.new(0.08, 0); bc.Parent = base
		local bs = Instance.new("UIStroke"); bs.Name = "MysteryBorder"; bs.Color = Color3.fromRGB(214, 170, 70); bs.Thickness = 2; bs.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; bs.Parent = base
		for i, at in ipairs({ { 0.5, 0.52 }, { 0.5, 0.52 } }) do -- two nested diamonds
			local d = Instance.new("Frame")
			d.Name = "MysteryDiamond" .. i
			d.AnchorPoint = Vector2.new(0.5, 0.5)
			d.Position = UDim2.fromScale(at[1], at[2])
			local side = i == 1 and 0.62 or 0.46
			d.Size = UDim2.fromScale(side, side * 0.7)
			d.Rotation = 45
			d.BackgroundTransparency = 1
			d.ZIndex = zIndex
			d.Active = false
			d.Parent = base
			local ds = Instance.new("UIStroke"); ds.Color = Color3.fromRGB(150, 110, 200); ds.Thickness = 1; ds.Parent = d
		end
		makeLabel(face, "CornerRank", "?", MYSTERY_INK, UDim2.fromScale(0.26, 0.15), UDim2.fromScale(0.19, 0.12), nil, Enum.TextXAlignment.Left, zIndex + 1)
		makeLabel(face, "CenterQuestion", "?", MYSTERY_INK, UDim2.fromScale(0.5, 0.34), UDim2.fromScale(0.5, 0.42), Vector2.new(0.5, 0.5), nil, zIndex + 1)
		makeLabel(face, "CenterSuit", "Mystery", MYSTERY_INK, UDim2.fromScale(0.72, 0.16), UDim2.fromScale(0.5, 0.72), Vector2.new(0.5, 0.5), nil, zIndex + 1)
		return face
	end

	builtFaces[button] = { rankText, suitText, isRed, zIndex, card }
	addSetLayers(face, zIndex, rankText)
	local colorblind = ClientSettings.get("colorblindSuits") and COLORBLIND_INK[suitText] ~= nil
	local ink = colorblind and COLORBLIND_INK[suitText] or (isRed and RED_INK or BLACK_INK)
	if colorblind then
		local mark = Accessibility.suitMarkByGlyph(suitText)
		local c = CosmeticSets.colorblindInkOf(setDef, mark.ink)
		ink = Color3.fromRGB(c[1], c[2], c[3])
	end
	if not colorblind and setFace and not setFace.neutral then
		-- set pips: black suits lean toward the set's pip colour, red suits only a little (stay readable)
		ink = ink:Lerp(rgb(setFace.pip), isRed and 0.2 or 0.5)
	end
	local drawSpecial = function() addSpecialLayers(face, card, zIndex) end
	-- Corner rank/suit sit INSIDE the card art's ornate border (it's ~12%
	-- of the card's width and ~8% of its height); they used to start at
	-- 4-8%, right on top of the gold filigree, which made them hard to read.
	local okIdx, info = pcall(require(script.Parent.SetSkin).indexInfo, isRed)
	if not okIdx then info = nil end
	local indexInk = ink
	if info and not colorblind then indexInk = info.ink end
	local L = info and info.layout
	-- the ivory face drawn alone has no ornate frame to stay inside: its index goes back to the top-left corner
	local okIv, ivory = pcall(function() return require(script.Parent.SetSkin).ivoryAlone() end)
	local IV = okIv and ivory and require(game:GetService("ReplicatedStorage").Shared.Engine.CardFaceArt).IVORY_LAYOUT or nil
	-- a fully painted face (rank, suit and pips are in the picture) stands in for the code-drawn one when its id is recorded
	if IV and not colorblind then
		local okP, paintedId = pcall(function()
			local Engine = game:GetService("ReplicatedStorage").Shared.Engine
			return require(Engine.CardFacePainted).resolve(require(Engine.ConceptTCardFaces), rankText, suitText)
		end)
		if okP and paintedId ~= "" then
			local painted = Instance.new("ImageLabel")
			painted.Name = "PaintedFace"
			painted.BackgroundTransparency = 1
			painted.Image = paintedId
			painted.ScaleType = Enum.ScaleType.Stretch
			painted.Size = UDim2.fromScale(1, 1)
			painted.ZIndex = zIndex + 1
			painted.Active = false
			painted.Parent = face
			drawSpecial()
			return face
		end
	end
	if IV then
		L = IV
		-- Concept T parchment: ONE vertical Color-only gradient that darkens the rim, on the painted face or on a flat-fill button
		local FaceArt = require(game:GetService("ReplicatedStorage").Shared.Engine.CardFaceArt)
		local paper = button:FindFirstChild("CardArt")
		if not (paper and paper:IsA("ImageLabel") and paper.Visible) then paper = button end
		if not paper:FindFirstChild("ParchmentShade") then
			local g = Instance.new("UIGradient")
			g.Name = "ParchmentShade"
			g.Rotation = 90
			local pts = {}
			for _, k in ipairs(FaceArt.shadeStops()) do
				pts[#pts + 1] = ColorSequenceKeypoint.new(k[1], Color3.fromRGB(k[2][1] * 255 // 240, k[2][2] * 255 // 240, k[2][3] * 255 // 240))
			end
			g.Color = ColorSequence.new(pts)
			g.Parent = paper
		end
	end
	local rank, suit, bottom
	if L then
		-- inside the frame's measured inner window, no box behind the index
		rank = makeLabel(face, "CornerRank", rankText, indexInk, UDim2.fromScale(L.rank.w, L.rank.h), UDim2.fromScale(L.rank.x, L.rank.y), nil, Enum.TextXAlignment.Left, zIndex + 2)
		suit = makeLabel(face, "CornerSuit", suitText, indexInk, UDim2.fromScale(L.suit.w, L.suit.h), UDim2.fromScale(L.suit.x, L.suit.y), nil, Enum.TextXAlignment.Left, zIndex + 2)
		bottom = makeLabel(face, "BottomSuit", suitText, indexInk, UDim2.fromScale(L.bottom.w, L.bottom.h), UDim2.fromScale(L.bottom.x, L.bottom.y), Vector2.new(1, 1), Enum.TextXAlignment.Right, zIndex + 2)
		if info then
			for _, lab in ipairs({ rank, suit, bottom }) do
				lab.TextStrokeColor3 = info.stroke
				lab.TextStrokeTransparency = 0.55
			end
		end
	else
		-- default set: index about 25 percent larger and inset from the inner border; stacked rank, suit and the centre pip
		-- never overlap (rank 0.14 to 0.32, suit 0.32 to 0.43, centre pip 0.42 to 0.74, bottom suit 0.74 to 0.85)
		makeLabel(face, "CornerRank", rankText, indexInk, UDim2.fromScale(0.36, 0.18), UDim2.fromScale(0.22, 0.14), nil, Enum.TextXAlignment.Left, zIndex)
		makeLabel(face, "CornerSuit", suitText, indexInk, UDim2.fromScale(0.2, 0.11), UDim2.fromScale(0.22, 0.32), nil, Enum.TextXAlignment.Left, zIndex)
		makeLabel(face, "BottomSuit", suitText, indexInk, UDim2.fromScale(0.18, 0.11), UDim2.fromScale(0.78, 0.85), Vector2.new(1, 1), Enum.TextXAlignment.Right, zIndex)
	end
	local C = IV and IV.center or { x = 0.5, y = 0.58, w = 0.5, h = 0.32 }
	-- a painted K, Q or J figure takes the place of the big suit symbol on the ivory face (corner index stays text)
	local courtImage, CL = "", nil
	if IV then
		local okCourt, id, layout = pcall(function()
			local Engine = game:GetService("ReplicatedStorage").Shared.Engine
			local Court = require(Engine.CourtFaceArt)
			return Court.resolve(require(Engine.ConceptTCardArt), rankText, suitText), Court.LAYOUT
		end)
		if okCourt then courtImage, CL = id, layout end
	end
	if courtImage ~= "" then
		local figure = Instance.new("ImageLabel")
		figure.Name = "CourtFigure"
		figure.BackgroundTransparency = 1
		figure.Image = courtImage
		figure.ScaleType = Enum.ScaleType.Fit
		figure.AnchorPoint = Vector2.new(0.5, 0.5)
		figure.Position = UDim2.fromScale(CL.x, CL.y)
		figure.Size = UDim2.fromScale(CL.w, CL.h)
		figure.ZIndex = zIndex + 1
		figure.Active = false
		figure.Parent = face
	else
		-- Concept T parchment: real pip layouts for number cards (Engine/PipLayout), one big pip for the Ace
		local pips
		if IV then
			local okP, list = pcall(function() return require(game:GetService("ReplicatedStorage").Shared.Engine.PipLayout) end)
			if okP then pips = list.pips(rankText); if pips then pips.size = list.SIZE; pips.bigSize = list.BIG end end
		end
		if pips then
			for i, p in ipairs(pips) do
				local sz = p.big and pips.bigSize or pips.size
				makeLabel(face, "Pip" .. i, suitText, ink, UDim2.fromScale(sz.w, sz.h), UDim2.fromScale(p.x, p.y), Vector2.new(0.5, 0.5), nil, zIndex)
			end
		else
			makeLabel(face, "CenterSuit", suitText, ink, UDim2.fromScale(C.w, C.h), UDim2.fromScale(C.x, C.y), Vector2.new(0.5, 0.5), nil, zIndex)
		end
	end
	if colorblind then
		makeLabel(face, "SuitLetter", SUIT_LETTER[suitText], ink, UDim2.fromScale(0.2, 0.13), UDim2.fromScale(0.81, 0.12), Vector2.new(1, 0), Enum.TextXAlignment.Right, zIndex)
	end
	drawSpecial()
	return face
end

-- Redraw every live card face when Colorblind Suits is toggled.
ClientSettings.onChanged(function(key)
	if key ~= "colorblindSuits" then
		return
	end
	for button, args in pairs(builtFaces) do
		if button.Parent then
			CardFace.build(button, args[1], args[2], args[3], args[4], false, args[5])
		else
			builtFaces[button] = nil
		end
	end
end)

-- The tray lives under GameBackgroundArt (ZIndex 0), NOT under handFrame:
-- handFrame holds a UIListLayout, which would lay the tray out as if it
-- were a card (same bug class as the old Sidebar texture / Journey path
-- line). Under the background art it is guaranteed to draw behind every
-- other root-level element, in both Sibling and Global ZIndex modes.
local function getTray(handFrame)
	local root = handFrame.Parent
	if not root then
		return nil
	end
	-- Parented straight to root: the scene stack and TableLook (created earlier, same ZIndex 0) used to
	-- draw over a tray living under GameBackgroundArt. Created lazily after them, it draws above them
	-- and below every ZIndex >= 1 element.
	local host = root
	local tray = host:FindFirstChild("HandTray") or (root:FindFirstChild("GameBackgroundArt") and root.GameBackgroundArt:FindFirstChild("HandTray"))
	if tray and tray.Parent ~= host then
		tray.Parent = host -- migrate a tray created under the old parent
	end
	if tray then
		return tray, host
	end

	tray = Instance.new("Frame")
	tray.Name = "HandTray"
	tray.AnchorPoint = Vector2.new(0.5, 0.5)
	tray.BackgroundColor3 = Color3.fromRGB(34, 22, 13)
	tray.BackgroundTransparency = 0.12
	tray.BorderSizePixel = 0
	tray.ZIndex = 0
	tray.Parent = host

	-- ART: the carved wood tray image (ArtAssets.handTrayArt), created
	-- before the code-drawn inner rim so it draws underneath it -- which is
	-- then hidden once the art has loaded.
	do
		local SkinArt = require(script.Parent.SkinArt)
		local slice = SkinArt.Slices.handTray
		SkinArt.apply(tray, require(script.Parent.ArtAssets).handTrayArt, {
			tint = SkinArt.Tints.handTray,
			zIndex = 0,
			sliceCenter = slice.center,
			sliceScale = slice.scale,
			onLoaded = function()
				SkinArt.hideCodeChrome(tray)
			end,
		})
	end

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = tray

	local stroke = Instance.new("UIStroke")
	stroke.Color = GOLD
	stroke.Thickness = 2
	stroke.Transparency = 0.1
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = tray

	-- Color-only gradient (never Transparency -- see setup-guide.md's
	-- addGloss bug): slightly lighter at the top, like carved wood.
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(150, 150, 150))
	gradient.Parent = tray

	local inner = Instance.new("Frame")
	inner.Name = "InnerRim"
	inner.Position = UDim2.fromOffset(5, 5)
	inner.Size = UDim2.new(1, -10, 1, -10)
	inner.BackgroundTransparency = 1
	inner.ZIndex = 0
	inner.Parent = tray
	local innerCorner = Instance.new("UICorner")
	innerCorner.CornerRadius = UDim.new(0, 9)
	innerCorner.Parent = inner
	local innerStroke = Instance.new("UIStroke")
	innerStroke.Color = GOLD
	innerStroke.Thickness = 1
	innerStroke.Transparency = 0.6
	innerStroke.Parent = inner

	return tray, host
end

function CardFace.layoutHand(handFrame)
	local slots = {}
	for _, child in ipairs(handFrame:GetChildren()) do
		if child:IsA("Frame") then
			table.insert(slots, child)
		end
	end
	local count = #slots

	local frameSize = handFrame.AbsoluteSize
	local maxWidth = math.max(MAX_CARD_WIDTH, handFrame:GetAttribute("MaxCardWidth") or 0)
	local width = maxWidth
	if frameSize.X > 0 and count > 0 then
		local bigHand = (handFrame:GetAttribute("MaxCardWidth") or 0) > MAX_CARD_WIDTH -- cards stand on the bottom padding only
		local byWidth = math.floor((frameSize.X - 2 * TRAY_PAD - CARD_GAP * (count - 1)) / count)
		if bigHand then byWidth = math.floor((frameSize.X - 2 * TRAY_PAD) / (count - HandSizing.overlapFor(count) * (count - 1))) end -- reference cards overlap
		local byHeight = math.floor((frameSize.Y - (bigHand and TRAY_PAD or 2 * TRAY_PAD)) / CARD_ASPECT)
		width = math.clamp(math.min(maxWidth, byWidth, byHeight), MIN_CARD_WIDTH, maxWidth)
	end
	local height = math.floor(width * CARD_ASPECT)
	for _, slot in ipairs(slots) do
		slot.Size = UDim2.fromOffset(width, height)
	end
	do -- roomy windows: neighbours overlap like the reference hand (the list layout padding goes negative)
		local list = handFrame:FindFirstChildOfClass("UIListLayout")
		if list then
			local big = (handFrame:GetAttribute("MaxCardWidth") or 0) > MAX_CARD_WIDTH
			list.Padding = UDim.new(0, big and HandSizing.gapFor(1200, width, count, frameSize.X) or CARD_GAP)
		end
	end

	local tray, host = getTray(handFrame)
	if tray then
		-- the painted table (Client/PlayScenePaint) has its own rail: no code-drawn tray while it is on
		tray.Visible = count > 0 and handFrame.Visible and not handFrame:GetAttribute("PaintedRail")
		local center = handFrame.AbsolutePosition + frameSize / 2 - host.AbsolutePosition
		tray.Position = UDim2.fromOffset(center.X, center.Y)
		tray.Size = UDim2.fromOffset(
			count * width + math.max(count - 1, 0) * CARD_GAP + 2 * TRAY_PAD,
			height + 2 * TRAY_PAD
		)
	end

	-- Hook resize/visibility once, so the hand and tray follow window
	-- resizes instead of only updating on the next rebuild.
	if not handFrame:GetAttribute("CardFaceLayoutHooked") then
		handFrame:SetAttribute("CardFaceLayoutHooked", true)
		local function relayout()
			CardFace.layoutHand(handFrame)
		end
		handFrame:GetPropertyChangedSignal("AbsoluteSize"):Connect(relayout)
		handFrame:GetPropertyChangedSignal("AbsolutePosition"):Connect(relayout)
		handFrame:GetPropertyChangedSignal("Visible"):Connect(relayout)
	end
end

CardFace.CARD_GAP = CARD_GAP

return CardFace
