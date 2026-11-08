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
local RED_INK = Color3.fromRGB(165, 28, 28)
local BLACK_INK = Color3.fromRGB(30, 22, 18)
local WILDCARD_INK = Color3.fromRGB(150, 110, 230)
local GOLD = Color3.fromRGB(205, 170, 95)

-- Settings > Display > Colorblind Suits: one ink per suit (keyed by the
-- symbol CardFace is handed) plus a suit letter in the top-right corner,
-- so suits differ by color AND a second shape cue, not just red/black.
local COLORBLIND_INK = {
	["♠"] = Color3.fromRGB(30, 22, 18), -- black
	["♥"] = Color3.fromRGB(190, 30, 40), -- red
	["♦"] = Color3.fromRGB(30, 90, 200), -- blue
	["♣"] = Color3.fromRGB(25, 125, 55), -- green
}
local SUIT_LETTER = { ["♠"] = "S", ["♥"] = "H", ["♦"] = "D", ["♣"] = "C" }

local ClientSettings = require(script.Parent.ClientSettings)

-- Every face built so far, so they can be redrawn when the setting flips.
local builtFaces = setmetatable({}, { __mode = "k" }) -- [button] = args

local CARD_ASPECT = 1.45 -- height / width, matches the reference cards
local MAX_CARD_WIDTH = 96
local MIN_CARD_WIDTH = 48
local CARD_GAP = 6
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
	return label
end

-- Equipped Cosmetic Set treatment (CosmeticSets.faceStyleOf): { neutral = true } or
-- { paper, border, pip, foil }. Set by CosmeticSetsView; every live face is redrawn on change.
local setFace = nil

local function rgb(t)
	return Color3.fromRGB(t[1], t[2], t[3])
end

-- Low-strength set layers under the corner/centre labels: a paper wash, a thin inset border, optional foil sheen.
local function addSetLayers(face, zIndex)
	if not setFace or setFace.neutral then return end
	local wash = Instance.new("Frame")
	wash.Name = "SetPaper"
	wash.Size = UDim2.fromScale(1, 1)
	wash.BackgroundColor3 = rgb(setFace.paper)
	wash.BackgroundTransparency = 0.8
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
	edgeStroke.Thickness = 1.5
	edgeStroke.Transparency = 0.2
	edgeStroke.Parent = edge

	if setFace.foil then
		local foil = Instance.new("Frame") -- a still diagonal sheen, stacked frames only
		foil.Name = "SetFoil"
		foil.AnchorPoint = Vector2.new(0.5, 0.5)
		foil.Position = UDim2.fromScale(0.62, 0.5)
		foil.Size = UDim2.fromScale(0.14, 1.5)
		foil.Rotation = 22
		foil.BackgroundColor3 = Color3.fromRGB(255, 244, 200)
		foil.BackgroundTransparency = 0.86
		foil.BorderSizePixel = 0
		foil.Active = false
		foil.ZIndex = zIndex
		foil.Parent = wash
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
				sheen.Size = UDim2.fromScale(0.2, 1.6)
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

function CardFace.setStyle(face)
	setFace = face
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
		makeLabel(face, "CornerRank", "✨", WILDCARD_INK, UDim2.fromScale(0.26, 0.15), UDim2.fromScale(0.19, 0.12), nil, Enum.TextXAlignment.Left, zIndex)
		makeLabel(face, "CenterSuit", "???", WILDCARD_INK, UDim2.fromScale(0.6, 0.3), UDim2.fromScale(0.5, 0.52), Vector2.new(0.5, 0.5), nil, zIndex)
		return face
	end

	builtFaces[button] = { rankText, suitText, isRed, zIndex, card }
	addSetLayers(face, zIndex)
	local colorblind = ClientSettings.get("colorblindSuits") and COLORBLIND_INK[suitText] ~= nil
	local ink = colorblind and COLORBLIND_INK[suitText] or (isRed and RED_INK or BLACK_INK)
	if not colorblind and setFace and not setFace.neutral then
		-- set pips: black suits lean toward the set's pip colour, red suits only a little (stay readable)
		ink = ink:Lerp(rgb(setFace.pip), isRed and 0.2 or 0.5)
	end
	local drawSpecial = function() addSpecialLayers(face, card, zIndex) end
	-- Corner rank/suit sit INSIDE the card art's ornate border (it's ~12%
	-- of the card's width and ~8% of its height); they used to start at
	-- 4-8%, right on top of the gold filigree, which made them hard to read.
	makeLabel(face, "CornerRank", rankText, ink, UDim2.fromScale(0.32, 0.15), UDim2.fromScale(0.19, 0.12), nil, Enum.TextXAlignment.Left, zIndex)
	makeLabel(face, "CornerSuit", suitText, ink, UDim2.fromScale(0.16, 0.1), UDim2.fromScale(0.2, 0.27), nil, Enum.TextXAlignment.Left, zIndex)
	makeLabel(face, "CenterSuit", suitText, ink, UDim2.fromScale(0.5, 0.36), UDim2.fromScale(0.5, 0.53), Vector2.new(0.5, 0.5), nil, zIndex)
	makeLabel(face, "BottomSuit", suitText, ink, UDim2.fromScale(0.14, 0.09), UDim2.fromScale(0.81, 0.87), Vector2.new(1, 1), Enum.TextXAlignment.Right, zIndex)
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
	local width = MAX_CARD_WIDTH
	if frameSize.X > 0 and count > 0 then
		local byWidth = math.floor((frameSize.X - 2 * TRAY_PAD - CARD_GAP * (count - 1)) / count)
		local byHeight = math.floor((frameSize.Y - 2 * TRAY_PAD) / CARD_ASPECT)
		width = math.clamp(math.min(MAX_CARD_WIDTH, byWidth, byHeight), MIN_CARD_WIDTH, MAX_CARD_WIDTH)
	end
	local height = math.floor(width * CARD_ASPECT)
	for _, slot in ipairs(slots) do
		slot.Size = UDim2.fromOffset(width, height)
	end

	local tray, host = getTray(handFrame)
	if tray then
		tray.Visible = count > 0 and handFrame.Visible
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
